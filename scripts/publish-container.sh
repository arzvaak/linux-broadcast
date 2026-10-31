#!/usr/bin/env bash
set -euo pipefail
engine="${CONTAINER_ENGINE:-podman}"
image="${CONTAINER_IMAGE:-ghcr.io/arzvaak/linux-broadcast:0.2.2}"
# Authenticate separately using your local engine credential store. No key is
# copied into the image or build context. This deliberately does not log tokens.
"$engine" push --format v2s2 --digestfile "${TMPDIR:-/tmp}/linux-broadcast-image.digest" "$image"
printf 'Pushed %s\nDigest: %s\n' "$image" "$(cat "${TMPDIR:-/tmp}/linux-broadcast-image.digest")"
printf 'Verify anonymous pulls and actual desktop/audio behavior before promoting stable.\n'
