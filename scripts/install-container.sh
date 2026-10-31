#!/usr/bin/env bash
set -euo pipefail
root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
install -Dm755 "$root/scripts/linux-broadcast-container" "$HOME/.local/bin/linux-broadcast-container"
install -Dm644 "$root/systemd/linux-broadcast-container.service" "$HOME/.config/systemd/user/linux-broadcast-container.service"
install -Dm644 "$root/packaging/container/linux-broadcast.desktop" "$HOME/.local/share/applications/com.arzvak.linuxbroadcast.container.desktop"
install -Dm644 "$root/ui/src-tauri/icons/128x128.png" "$HOME/.local/share/icons/hicolor/128x128/apps/linux-broadcast-container.png"
# Desktop entries do not expand $HOME or require ~/.local/bin to be on PATH.
sed -i "s|^Exec=.*|Exec=$HOME/.local/bin/linux-broadcast-container|" "$HOME/.local/share/applications/com.arzvak.linuxbroadcast.container.desktop"
systemctl --user daemon-reload
printf 'Installed Linux Broadcast (Container). Start it from your app menu.\nNVIDIA Container Toolkit/CDI must be configured first; see docs/container.md.\n'
