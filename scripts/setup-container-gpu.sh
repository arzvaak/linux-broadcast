#!/usr/bin/env bash
# Optional rootless CDI setup using NVIDIA's official, checksum-pinned toolkit.
set -euo pipefail
command -v nvidia-smi >/dev/null || { printf 'Install the host NVIDIA driver first.\n' >&2; exit 1; }
state="${LINUX_BROADCAST_CONTAINER_STATE:-${XDG_DATA_HOME:-$HOME/.local/share}/linux-broadcast-container}"
version=1.20.1
checksum=e01964a064fbdb62425ab22ec5832349f92c5b0b50c8f23fdf14dad004db4fb2
tools="$state/toolkit/$version/bin"
if [[ ! -x "$tools/nvidia-ctk" || ! -x "$tools/nvidia-cdi-hook" ]]; then
  tmp="$(mktemp -d)"; trap 'rm -rf -- "$tmp"' EXIT
  curl --fail --location --proto '=https' --tlsv1.2 \
    "https://nvidia.github.io/libnvidia-container/stable/deb/amd64/nvidia-container-toolkit-base_${version}-1_amd64.deb" -o "$tmp/toolkit.deb"
  printf '%s  %s\n' "$checksum" "$tmp/toolkit.deb" | sha256sum -c -
  (cd "$tmp"; ar p toolkit.deb data.tar.xz | tar -xJ ./usr/bin/nvidia-ctk ./usr/bin/nvidia-cdi-hook)
  install -Dm755 "$tmp/usr/bin/nvidia-ctk" "$tools/nvidia-ctk"
  install -Dm755 "$tmp/usr/bin/nvidia-cdi-hook" "$tools/nvidia-cdi-hook"
fi
mkdir -p "$state/cdi"
"$tools/nvidia-ctk" cdi generate --nvidia-cdi-hook-path "$tools/nvidia-cdi-hook" --output "$state/cdi/nvidia.yaml"
printf 'Rootless NVIDIA CDI configured. Rerun this script after changing your NVIDIA driver.\n'
