#!/usr/bin/env bash
set -euo pipefail
root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
: "${AFX_SDK_ROOT:?Set AFX_SDK_ROOT to the extracted NVIDIA AFX 2.1.0 SDK}"
engine="${CONTAINER_ENGINE:-podman}"
runtime="${RUNTIME_IMAGE:-ghcr.io/arzvaak/linux-broadcast-runtime@sha256:1a950b7eefde67907e00523bedbfc1529e2089fa3dafd491fdb6f5712be97865}"
image="${CONTAINER_IMAGE:-ghcr.io/arzvaak/linux-broadcast:0.2.2}"
stage="$(mktemp -d "${TMPDIR:-/tmp}/linux-broadcast-container.XXXXXX")"
trap 'rm -rf -- "$stage"' EXIT
if [[ "${BUILD_RUNTIME:-0}" == 1 ]]; then
  LINUX_BROADCAST_MODEL_ARCHES=sm_75,sm_86,sm_89,sm_120 "$root/scripts/stage-nvidia-runtime.sh" "$stage/runtime/nvidia"
  runtime="${RUNTIME_TAG:-ghcr.io/arzvaak/linux-broadcast-runtime:afx-2.1.0}"
  "$engine" build -f "$root/packaging/container/Containerfile.runtime" -t "$runtime" "$stage/runtime"
fi
mkdir -p "$stage/app/ui/src-tauri" "$stage/app/packaging/container" "$stage/app/sdk-headers/nvafx" "$stage/app/sdk-headers/features/denoiser"
# Explicit source allowlist; avoid .git, local SDKs, logs, caches, and generated build outputs.
cp "$root/LICENSE" "$stage/app/"
cp -a "$root/native" "$root/systemd" "$stage/app/"
cp -a "$root/ui/src" "$stage/app/ui/"
cp "$root/ui/package.json" "$root/ui/package-lock.json" "$root/ui/tsconfig.json" "$root/ui/index.html" "$stage/app/ui/"
cp -a "$root/ui/src-tauri/src" "$root/ui/src-tauri/icons" "$stage/app/ui/src-tauri/"
cp "$root/ui/src-tauri/Cargo.toml" "$root/ui/src-tauri/Cargo.lock" "$root/ui/src-tauri/build.rs" "$root/ui/src-tauri/tauri.conf.json" "$stage/app/ui/src-tauri/"
cp "$root/packaging/container/tauri.conf.json" "$stage/app/packaging/container/"
cp -a "$AFX_SDK_ROOT/nvafx/include" "$stage/app/sdk-headers/nvafx/"
cp -a "$AFX_SDK_ROOT/features/denoiser/include" "$stage/app/sdk-headers/features/denoiser/"
# Build-only SDK linking libraries are explicitly selected, not copied from an arbitrary SDK tree.
mkdir -p "$stage/app/sdk-headers/nvafx/lib" "$stage/app/sdk-headers/features/denoiser/lib"
cp -L "$AFX_SDK_ROOT/nvafx/lib/libnv_audiofx.so" "$stage/app/sdk-headers/nvafx/lib/"
cp -L "$AFX_SDK_ROOT/features/denoiser/lib/"*.so "$stage/app/sdk-headers/features/denoiser/lib/"
build_args=()
if [[ "$(basename "$engine")" == podman ]]; then
  for base in docker.io/library/node:22-bookworm-slim docker.io/library/rust:1.97-bookworm; do
    "$engine" image exists "$base" || "$engine" pull "$base"
  done
  # Never replace the runtime just built locally with an older remote tag.
  build_args+=(--pull=never)
fi
"$engine" build "${build_args[@]}" --build-arg "RUNTIME_IMAGE=$runtime" --build-arg "REVISION=$(git -C "$root" rev-parse HEAD)" \
  -f "$root/packaging/container/Containerfile" -t "$image" "$stage/app"
