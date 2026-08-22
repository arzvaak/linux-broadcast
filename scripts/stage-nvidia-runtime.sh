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
  for architecture in "${architecture_list[@]}"; do
    model_dir="$AFX_SDK_ROOT/features/$feature/models/$architecture"
    [[ -d "$model_dir" ]] || {
      printf 'Missing %s models for %s\n' "$feature" "$architecture" >&2
      exit 2
    }
  done
done

if [[ -e "$destination" ]]; then
  printf 'Staging destination already exists: %s\n' "$destination" >&2
  printf 'Remove it before creating a new release bundle.\n' >&2
  exit 2
fi

install -d "$destination/nvafx" "$destination/external/cuda" "$destination/features"
cp -a "$AFX_SDK_ROOT/nvafx/lib" "$destination/nvafx/"
cp -a "$AFX_SDK_ROOT/external/cuda/lib" "$destination/external/cuda/"
cp -a "$AFX_SDK_ROOT/licenses" "$destination/"
[[ -f "$AFX_SDK_ROOT/external/ThirdPartyLicenses.txt" ]] && \
  cp -a "$AFX_SDK_ROOT/external/ThirdPartyLicenses.txt" "$destination/external/"

for feature in "${features[@]}"; do
  install -d "$destination/features/$feature/models"
  cp -a "$AFX_SDK_ROOT/features/$feature/lib" "$destination/features/$feature/"
  cp -a "$AFX_SDK_ROOT/features/$feature/licenses" "$destination/features/$feature/"
  for architecture in "${architecture_list[@]}"; do
    install -d "$destination/features/$feature/models/$architecture"
    case "$feature" in
      denoiser) models=(denoiser_48k.trtpkg denoiser_v2_48k.trtpkg) ;;
      dereverb) models=(dereverb_48k.trtpkg) ;;
      dereverb_denoiser) models=(dereverb_denoiser_48k.trtpkg) ;;
      studio_voice) models=(studio_voice_low_latency_48k.trtpkg) ;;
    esac
    for model in "${models[@]}"; do
      source="$AFX_SDK_ROOT/features/$feature/models/$architecture/$model"
      [[ -e "$source" ]] || { printf 'Missing NVIDIA model: %s\n' "$source" >&2; exit 2; }
      cp -L "$source" "$destination/features/$feature/models/$architecture/$model"
    done
  done
done

if find "$destination" -type f | grep -E '/(\.ngc|config|credentials|\.env)(/|$)' >/dev/null; then
  printf 'Credential-like file found in staged NVIDIA runtime\n' >&2
  exit 3
fi

printf 'Staged NVIDIA runtime for %s at %s\n' "$architectures" "$destination"
