#!/usr/bin/env bash
set -euo pipefail

: "${AFX_SDK_ROOT:?Set AFX_SDK_ROOT to the extracted NVIDIA AFX SDK}"

project_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
destination="${1:-$project_root/build/nvidia-runtime}"
: "${LINUX_BROADCAST_MODEL_ARCHES:?Set LINUX_BROADCAST_MODEL_ARCHES to one release architecture}"
architectures="$LINUX_BROADCAST_MODEL_ARCHES"
feature="dereverb_denoiser"
model="dereverb_denoiser_48k.trtpkg"

for path in \
  "$AFX_SDK_ROOT/nvafx/lib/libnv_audiofx.so" \
  "$AFX_SDK_ROOT/external/cuda/lib" \
  "$AFX_SDK_ROOT/licenses"; do
  [[ -e "$path" ]] || { printf 'Required NVIDIA runtime path is missing: %s\n' "$path" >&2; exit 2; }
done

IFS=',' read -ra architecture_list <<< "$architectures"
[[ -d "$AFX_SDK_ROOT/features/$feature/lib" ]] || { printf 'Missing NVIDIA feature library: %s\n' "$feature" >&2; exit 2; }
for architecture in "${architecture_list[@]}"; do
  source="$AFX_SDK_ROOT/features/$feature/models/$architecture/$model"
  [[ -e "$source" ]] || { printf 'Missing NVIDIA model: %s\n' "$source" >&2; exit 2; }
done

if [[ -e "$destination" ]]; then
  printf 'Staging destination already exists: %s\n' "$destination" >&2
  printf 'Remove it before creating a new release bundle.\n' >&2
  exit 2
fi

install -d "$destination/nvafx" "$destination/external/cuda" "$destination/features"
cp -a "$AFX_SDK_ROOT/nvafx/lib" "$destination/nvafx/"
install -d "$destination/external/cuda/lib"
for pattern in libcublas.so\* libcublasLt.so\* libcudart.so\* libcufft.so\* libnvinfer.so.10\* libnvinfer_plugin.so.10\* libnvrtc.so\*; do
  libraries=("$AFX_SDK_ROOT/external/cuda/lib/"$pattern)
  [[ -e "${libraries[0]}" ]] || { printf 'Missing NVIDIA runtime library: %s\n' "$pattern" >&2; exit 2; }
  cp -a "${libraries[@]}" "$destination/external/cuda/lib/"
done
cp -a "$AFX_SDK_ROOT/licenses" "$destination/"
[[ -f "$AFX_SDK_ROOT/external/ThirdPartyLicenses.txt" ]] && \
  cp -a "$AFX_SDK_ROOT/external/ThirdPartyLicenses.txt" "$destination/external/"

install -d "$destination/features/$feature/models"
cp -a "$AFX_SDK_ROOT/features/$feature/lib" "$destination/features/$feature/"
cp -a "$AFX_SDK_ROOT/features/$feature/licenses" "$destination/features/$feature/"
for architecture in "${architecture_list[@]}"; do
  install -d "$destination/features/$feature/models/$architecture"
  source="$AFX_SDK_ROOT/features/$feature/models/$architecture/$model"
  cp -L "$source" "$destination/features/$feature/models/$architecture/$model"
done

if find "$destination" -name 'libcudnn*' -print -quit | grep -q .; then
  printf 'cuDNN library found in compact NVIDIA runtime\n' >&2
  exit 3
fi

if find "$destination" -type f | grep -E '/(\.ngc|config|credentials|\.env)(/|$)' >/dev/null; then
  printf 'Credential-like file found in staged NVIDIA runtime\n' >&2
  exit 3
fi

printf 'Staged Noise + Room Echo NVIDIA runtime for %s at %s\n' "$architectures" "$destination"
