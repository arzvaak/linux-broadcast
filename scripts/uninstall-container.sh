#!/usr/bin/env bash
set -euo pipefail
systemctl --user disable --now linux-broadcast-container.service 2>/dev/null || true
"$HOME/.local/bin/linux-broadcast-container" --stop 2>/dev/null || true
rm -f -- "$HOME/.local/bin/linux-broadcast-container" \
  "$HOME/.config/systemd/user/linux-broadcast-container.service" \
  "$HOME/.local/share/applications/com.arzvak.linuxbroadcast.container.desktop" \
  "$HOME/.local/share/icons/hicolor/128x128/apps/linux-broadcast-container.png"
systemctl --user daemon-reload
printf 'Container launcher removed. Your settings and downloaded image were retained.\n'
