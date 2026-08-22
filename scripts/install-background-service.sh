#!/usr/bin/env bash
set -euo pipefail

project_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
binary="$project_root/ui/src-tauri/target/release/linux-broadcast"
plugin="$project_root/build/native-cmake/liblinux_broadcast_afx_ladspa.so"
unit="$project_root/systemd/linux-broadcast.service"

if [[ ! -x "$binary" || ! -f "$plugin" ]]; then
  printf 'Build the release application and native plugin before installing the service.\n' >&2
  exit 1
fi

binary_destination="$HOME/.local/bin/linux-broadcast"
plugin_destination="$HOME/.local/lib/linux-broadcast/liblinux_broadcast_afx_ladspa.so"
unit_destination="$HOME/.config/systemd/user/linux-broadcast.service"

install -Dm755 "$binary" "$binary_destination.installing"
mv -f -- "$binary_destination.installing" "$binary_destination"
install -Dm755 "$plugin" "$plugin_destination.installing"
mv -f -- "$plugin_destination.installing" "$plugin_destination"
install -Dm644 "$unit" "$unit_destination.installing"
mv -f -- "$unit_destination.installing" "$unit_destination"

systemctl --user daemon-reload
systemctl --user reenable linux-broadcast.service
systemctl --user restart linux-broadcast.service
printf 'Linux Broadcast is installed and running in the background.\n'
