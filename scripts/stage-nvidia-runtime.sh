#!/usr/bin/env bash
set -euo pipefail

: "${AFX_SDK_ROOT:?Set AFX_SDK_ROOT to the extracted NVIDIA AFX SDK}"

project_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
destination="${1:-$project_root/build/nvidia-runtime}"
: "${LINUX_BROADCAST_MODEL_ARCHES:?Set LINUX_BROADCAST_MODEL_ARCHES to one release architecture}"
architectures="$LINUX_BROADCAST_MODEL_ARCHES"
features=(denoiser dereverb dereverb_denoiser studio_voice)

for path in \
  "$AFX_SDK_ROOT/nvafx/lib/libnv_audiofx.so" \
  "$AFX_SDK_ROOT/external/cuda/lib" \
  "$AFX_SDK_ROOT/licenses"; do
  [[ -e "$path" ]] || { printf 'Required NVIDIA runtime path is missing: %s\n' "$path" >&2; exit 2; }
done

IFS=',' read -ra architecture_list <<< "$architectures"
for feature in "${features[@]}"; do
  [[ -d "$AFX_SDK_ROOT/features/$feature/lib" ]] || { printf 'Missing NVIDIA feature library: %s\n' "$feature" >&2; exit 2; }
  [[ -d "$AFX_SDK_ROOT/features/$feature/licenses" ]] || { printf 'Missing NVIDIA feature licenses: %s\n' "$feature" >&2; exit 2; }
  for architecture in "${architecture_list[@]}"; do
    model_dir="$AFX_SDK_ROOT/features/$feature/models/$architecture"
    [[ -d "$model_dir" ]] || { printf 'Missing NVIDIA model directory: %s\n' "$model_dir" >&2; exit 2; }
    find "$model_dir" -maxdepth 1 -type f -name '*.trtpkg' -print -quit | grep -q . || {
      printf 'No NVIDIA models found in: %s\n' "$model_dir" >&2
      exit 2
    }
  done
done

if [[ -e "$destination" ]]; then
  printf 'Staging destination already exists: %s\n' "$destination" >&2
  printf 'Remove it before creating a new release bundle.\n' >&2
  exit 2
fi

install -d "$destination/nvafx/lib" "$destination/external/cuda/lib" "$destination/features"
# Keep the SONAME as the real file and the development name as a relative link.
# RPM, DEB, and portable packages preserve this without duplicating the library.
install -m 0755 "$(readlink -f "$AFX_SDK_ROOT/nvafx/lib/libnv_audiofx.so")" \
  "$destination/nvafx/lib/libnv_audiofx.so.2"
ln -s libnv_audiofx.so.2 "$destination/nvafx/lib/libnv_audiofx.so"
runtime_libraries=(
  libcublas.so.12
  libcublasLt.so.12
  libcudart.so.12
  libcufft.so.11
  libnvinfer.so.10
  libnvinfer_plugin.so.10
  libnvrtc.so.12
)
for library in "${runtime_libraries[@]}"; do
  source="$AFX_SDK_ROOT/external/cuda/lib/$library"
  [[ -e "$source" ]] || { printf 'Missing NVIDIA runtime library: %s\n' "$library" >&2; exit 2; }
  install -m 0755 "$(readlink -f "$source")" "$destination/external/cuda/lib/$library"
done
cp -a "$AFX_SDK_ROOT/licenses" "$destination/"
[[ -f "$AFX_SDK_ROOT/external/ThirdPartyLicenses.txt" ]] && \
  cp -a "$AFX_SDK_ROOT/external/ThirdPartyLicenses.txt" "$destination/external/"

for feature in "${features[@]}"; do
  install -d "$destination/features/$feature/models"
  install -d "$destination/features/$feature/lib"
  for library in "$AFX_SDK_ROOT/features/$feature/lib/"*.so; do
    if [[ "$feature" == studio_voice && "$(basename "$library")" != libnv_audiofx_studio_voice_low_latency.so ]]; then
      continue
    fi
    install -m 0755 "$(readlink -f "$library")" \
      "$destination/features/$feature/lib/$(basename "$library")"
  done
  cp -a "$AFX_SDK_ROOT/features/$feature/licenses" "$destination/features/$feature/"
  for architecture in "${architecture_list[@]}"; do
    install -d "$destination/features/$feature/models/$architecture"
    for model in "$AFX_SDK_ROOT/features/$feature/models/$architecture/"*.trtpkg; do
      [[ -L "$model" ]] || continue
      if [[ "$feature" == studio_voice && "$(basename "$model")" != studio_voice_low_latency_48k.trtpkg ]]; then
        continue
      fi
      install -m 0644 "$(readlink -f "$model")" \
        "$destination/features/$feature/models/$architecture/$(basename "$model")"
    done
  done
done

if find "$destination" -type f | grep -E '/(\.ngc|config|credentials|\.env)(/|$)' >/dev/null; then
  printf 'Credential-like file found in staged NVIDIA runtime\n' >&2
  exit 3
fi

if find "$destination" -type f -name 'libcudnn*.so*' -print -quit | grep -q .; then
  printf 'Unused cuDNN library found in staged runtime\n' >&2
  exit 3
fi

printf 'Staged the measured NVIDIA AFX, CUDA, and TensorRT runtime closure for %s at %s\n' "$architectures" "$destination"
