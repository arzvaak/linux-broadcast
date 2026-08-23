#!/usr/bin/env bash
set -euo pipefail

artifact="${1:?Usage: verify-release-artifact.sh ARTIFACT rtx20|rtx30|rtx40|rtx50}"
series="${2:?Usage: verify-release-artifact.sh ARTIFACT rtx20|rtx30|rtx40|rtx50}"
case "$series" in
  rtx20) architecture=sm_75 ;;
  rtx30) architecture=sm_86 ;;
  rtx40) architecture=sm_89 ;;
  rtx50) architecture=sm_120 ;;
  *) printf 'Unknown GPU series: %s\n' "$series" >&2; exit 2 ;;
esac

listing="$(mktemp)"
trap 'rm -f "$listing"' EXIT
case "$artifact" in
  *.rpm) rpm -qpl "$artifact" > "$listing" ;;
  *.deb)
    member="$(ar t "$artifact" | awk '/^data\.tar/ {print; exit}')"
    [[ -n "$member" ]] || { printf 'DEB data archive not found\n' >&2; exit 3; }
    ar p "$artifact" "$member" | tar -tf - > "$listing"
    ;;
  *.tar) tar -tf "$artifact" > "$listing" ;;
  *) printf 'Unsupported artifact: %s\n' "$artifact" >&2; exit 2 ;;
esac

for required in \
  linux-broadcast \
  liblinux_broadcast_afx_ladspa.so \
  "features/denoiser/models/$architecture/denoiser_48k.trtpkg" \
  "features/denoiser/models/$architecture/denoiser_v2_48k.trtpkg" \
  "features/dereverb/models/$architecture/dereverb_48k.trtpkg" \
  "features/dereverb_denoiser/models/$architecture/dereverb_denoiser_48k.trtpkg" \
  "features/studio_voice/models/$architecture/studio_voice_low_latency_48k.trtpkg" \
  external/cuda/lib/libcublas.so.12 \
  external/cuda/lib/libcublasLt.so.12 \
  external/cuda/lib/libcudart.so.12 \
  external/cuda/lib/libcufft.so.11 \
  external/cuda/lib/libnvinfer.so.10 \
  external/cuda/lib/libnvinfer_plugin.so.10 \
  external/cuda/lib/libnvrtc.so.12 \
  nvafx/lib/libnv_audiofx.so.2 \
  'NVIDIA Software License Agreement.pdf' \
  'NVIDIA Models Community License.pdf'; do
  grep -Fq "$required" "$listing" || { printf 'Missing release payload: %s\n' "$required" >&2; exit 3; }
done

if grep -Eq 'libcudnn|studio_voice_high_quality' "$listing"; then
  printf 'Artifact contains a runtime or model that Linux Broadcast never loads: %s\n' "$artifact" >&2
  exit 4
fi

model_count="$(grep -Ec "/$architecture/[^/]+\.trtpkg$" "$listing")"
[[ "$model_count" -eq 5 ]] || { printf 'Expected 5 %s models; found %s\n' "$architecture" "$model_count" >&2; exit 3; }
if grep -E '/models/(sm_75|sm_86|sm_89|sm_120)/' "$listing" | \
  grep -Fv "/$architecture/" | grep -q .; then
  printf 'Artifact contains a model for the wrong GPU architecture\n' >&2
  exit 3
fi

printf 'Verified complete %s payload in %s\n' "$series" "$artifact"
