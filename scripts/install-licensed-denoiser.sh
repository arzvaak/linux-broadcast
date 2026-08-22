#!/usr/bin/env bash
set -euo pipefail

: "${AFX_SDK_ROOT:?Set AFX_SDK_ROOT to the extracted NVIDIA AFX SDK}"

if [[ -z "${NGC_API_KEY:-}" && -f "${HOME}/.ngc/config" ]]; then
  NGC_API_KEY="$(awk -F' = ' '/^apikey = / {print $2}' "${HOME}/.ngc/config")"
  export NGC_API_KEY
fi
: "${NGC_API_KEY:?Configure the NVIDIA NGC CLI or set NGC_API_KEY}"

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
detector_output="$("$script_dir/detect-gpu.sh")"
printf '%s\n' "$detector_output"
target="$(printf '%s\n' "$detector_output" | sed -n 's/^NVIDIA package target: //p')"
downloader="$AFX_SDK_ROOT/features/download_features.sh"

if [[ ! -x "$downloader" ]]; then
  printf 'Official NVIDIA feature downloader not found: %s\n' "$downloader" >&2
  exit 2
fi

printf 'Requesting licensed NVIDIA AFX feature packages for %s...\n' "$target"
"$downloader" --gpu "$target" --ngc-org nvidia --ngc-team maxine \
  --effects denoiser-48k,dereverb-48k,dereverb_denoiser-48k,studio_voice-48k \
  --output-dir "$AFX_SDK_ROOT/features"
