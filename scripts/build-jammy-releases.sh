#!/usr/bin/env bash
set -euo pipefail

: "${AFX_SDK_ROOT:?Set AFX_SDK_ROOT to the extracted NVIDIA AFX SDK}"
project_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
image="localhost/linux-broadcast-jammy:22.04"

podman build -t "$image" "$project_root/packaging/jammy"
for series in rtx20 rtx30 rtx40 rtx50; do
  podman run --rm \
    --security-opt label=disable \
    -e AFX_SDK_ROOT=/nvidia \
    -e CARGO_TARGET_DIR=/workspace/ui/src-tauri/target-jammy \
    -v "$project_root:/workspace" \
    -v "$AFX_SDK_ROOT:/nvidia:ro" \
    -w /workspace \
    "$image" \
    ./scripts/build-packages.sh "$series"
done

podman run --rm \
  --security-opt label=disable \
  -e AFX_SDK_ROOT=/nvidia \
  -e CARGO_TARGET_DIR=/workspace/ui/src-tauri/target-jammy \
  -v "$project_root:/workspace" \
  -v "$AFX_SDK_ROOT:/nvidia:ro" \
  -w /workspace \
  "$image" \
  ./scripts/build-portable-releases.sh
