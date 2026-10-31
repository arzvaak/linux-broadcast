# Native background-service hardening

Issue #1's reporter confirmed that `RestrictSUIDSGID=true` caused the
Arch/glycin/bubblewrap crash. The native unit now restores the other original
options together: `NoNewPrivileges`, `PrivateTmp`, `ProtectSystem=strict`,
`ProtectControlGroups`, `ProtectClock`, `ProtectHostname`, `ProtectKernelLogs`,
`ProtectKernelModules`, `ProtectKernelTunables`, and `LockPersonality`.
`RestrictSUIDSGID` is explicitly false. The three-starts-per-minute limit and
five-second restart delay remain.

Strict filesystem protection makes HOME read-only too. The service permits writes
to its preferences, WebKit data, dedicated cache, user login-unit directory, and
per-user desktop runtime directory. Cache locations are pinned under
`~/.cache/linux-broadcast`, including CUDA's cache. The installer and in-app native
login setup create these directories before loading the unit.

The user login-unit directory remains writable because the native app's Start at
login control installs its unit there. Session sockets/runtime files remain
available to GTK, PipeWire, and desktop helpers. These are compatibility exceptions,
not a claim that a desktop application with session-bus access is fully isolated.

## Validation

On Fedora 45, the complete option set launched the native GTK/WebKit app under a
separate D-Bus session, Xvfb display, and temporary HOME for twelve seconds without
an abort or read-only-state failure. An explicit probe could write allowed state
and received EROFS when writing elsewhere. A native NVIDIA BNR2 probe also processed
48,000 finite audio samples under the same restrictions.

The isolated D-Bus session does not provide the normal desktop portals/user-manager
services, so expected portal activation warnings are not evidence of normal tray or
login-control behavior. This check establishes startup and filesystem compatibility
on this host; Arch/glycin still needs confirmation with the combined configuration.
It does not replace listening tests or a real desktop-session check.

## Existing installations

The repository's native installer installs the updated unit. To update an existing
session without interrupting it, create the writable directories and install the
same Service settings as a user drop-in, then run `systemctl --user daemon-reload`.
Do not restart a running application merely to apply this change: process sandbox
settings take effect on the next normal service start. A drop-in also survives an
older binary rewriting its embedded base unit through the login toggle.

The container launcher's service has separate requirements for rootless Podman and
is unchanged by this native-service update.
