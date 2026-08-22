#!/usr/bin/env bash
set -euo pipefail

systemctl --user disable --now linux-broadcast.service 2>/dev/null || true
rm -f -- "$HOME/.config/systemd/user/linux-broadcast.service"
rm -f -- "$HOME/.local/bin/linux-broadcast"
rm -f -- "$HOME/.local/lib/linux-broadcast/liblinux_broadcast_afx_ladspa.so"
systemctl --user daemon-reload
printf 'Linux Broadcast background service was removed.\n'
