#!/usr/bin/env bash
set -euo pipefail

query=(--query-gpu=index,name,compute_cap --format=csv,noheader,nounits)
if [[ -n "${LINUX_BROADCAST_GPU_INDEX:-}" ]]; then
  [[ "$LINUX_BROADCAST_GPU_INDEX" =~ ^[0-9]+$ ]] || {
    printf 'LINUX_BROADCAST_GPU_INDEX must be a non-negative integer.\n' >&2
    exit 2
  }
  query=(--id="$LINUX_BROADCAST_GPU_INDEX" "${query[@]}")
fi

selected=""
while IFS=, read -r index gpu_name capability; do
  index="${index//[[:space:]]/}"
  capability="${capability//[[:space:]]/}"
  gpu_name="${gpu_name# }"
  case "$capability" in
    7.5|8.6|8.9|12.0)
      if [[ "${gpu_name^^}" == *RTX* ]]; then
        selected="$index|$gpu_name|$capability"
        break
      fi
      ;;
  esac
done < <(nvidia-smi "${query[@]}")

if [[ -z "$selected" ]]; then
  printf 'No supported RTX GPU was found.\n' >&2
  exit 2
fi

IFS='|' read -r gpu_index gpu_name capability <<< "$selected"

case "$capability" in
  7.5) sm=sm_75; target=t4; generation="RTX 20 / Turing" ;;
  8.6) sm=sm_86; target=a10; generation="RTX 30 / Ampere" ;;
  8.9) sm=sm_89; target=l40; generation="RTX 40 / Ada" ;;
  12.0) sm=sm_120; target=rtx_pro_6000; generation="RTX 50 / Blackwell" ;;
  *)
    printf 'Unsupported or unmapped compute capability: %s\n' "$capability" >&2
    exit 2
    ;;
esac

printf 'GPU index: %s\nGPU: %s\nCompute capability: %s\nGeneration: %s\nAFX model directory: %s\nNVIDIA package target: %s\n' \
  "$gpu_index" "$gpu_name" "$capability" "$generation" "$sm" "$target"
