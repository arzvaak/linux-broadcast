# Linux Broadcast container installation

The container edition keeps the desktop app, NVIDIA AFX 2.1.0 runtime and models
in a public image at `ghcr.io/arzvaak/linux-broadcast`. One amd64 image includes
models for supported RTX 20/30/40/50 GPUs. NVIDIA files retain their own licenses.
The host NVIDIA driver is still required; users do not need an NGC key or SDK.

## Prerequisites

- A supported NVIDIA RTX GPU with a compatible proprietary driver (`nvidia-smi`).
- A running PipeWire graphical desktop session.
- Rootless Podman (recommended) or Docker configured to run the desktop user's UID.
- [NVIDIA Container Toolkit](https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/latest/install-guide.html)
  with [CDI configured](https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/latest/cdi-support.html).
  Follow NVIDIA's instructions for your distribution; confirm that
  `nvidia-ctk cdi list` includes `nvidia.com/gpu=all`.

Do not launch the app with sudo. Run the host launcher from the graphical session.
It forwards the PipeWire and session D-Bus sockets and the selected Wayland or X11
connection. Fedora/SELinux needs the per-container `label=disable` option because
session sockets retain their existing labels; the launcher applies that option
on Podman. It does not relabel host sockets or change global SELinux policy.

For rootless Podman on amd64, an optional setup script installs only NVIDIA's
checksum-pinned CDI tools under your user data directory, without sudo:

```sh
./scripts/setup-container-gpu.sh
```

The launcher detects this private CDI directory automatically. Rerun the script
after a driver update. This is an alternative to a system Toolkit installation,
not a replacement for the NVIDIA driver. The extracted toolkit remains subject
to NVIDIA's license shipped with its official package.

## Install and launch

```sh
git clone https://github.com/arzvaak/linux-broadcast.git
cd linux-broadcast
./scripts/install-container.sh
~/.local/bin/linux-broadcast-container
```

The app menu entry is **Linux Broadcast (Container)**. Its first launch pulls the
image; subsequent launches reuse the running instance and reopen its window.
Quit an existing native Linux Broadcast app before starting the container edition.
The launcher detects the native instance on session D-Bus and refuses to start a
competing processor.

Settings persist in `~/.local/share/linux-broadcast-container/home/`. This includes WebKit local storage as well as app preferences and caches. Native
preferences are copied once on first launch, without modifying the originals.
**Start at login** controls the host user unit `linux-broadcast-container.service`.
The installer creates but does not enable that unit. **Run in background** and
close-to-tray retain their existing behavior.

```sh
linux-broadcast-container --stop
linux-broadcast-container --update
linux-broadcast-container
```

Use `LINUX_BROADCAST_IMAGE=ghcr.io/arzvaak/linux-broadcast:0.2.2` to pin a version.
Set `LINUX_BROADCAST_ENGINE=podman` or `docker` to select the engine.
A custom Podman CDI directory can be supplied with `LINUX_BROADCAST_CDI_DIR`.
The `--update` command refuses to replace a running app: stop it first.

Uninstall with `./scripts/uninstall-container.sh`. Settings and images are retained
so they can be recovered. Existing native packages and Netcup downloads remain
available during the transition.

## Maintainer builds and releases

Build on a machine with an extracted, licensed AFX 2.1.0 SDK containing all four
model architectures. The script assembles an explicit context: no NGC credentials,
whole SDK directory, source Git metadata, host caches, or personal configuration.

```sh
export AFX_SDK_ROOT=/path/to/Audio_Effects_SDK
./scripts/build-container.sh
# Rebuild the runtime only when deliberately changing SDK/runtime dependencies:
# BUILD_RUNTIME=1 ./scripts/build-container.sh
# Authenticate to GHCR using the container engine's credential store.
podman push ghcr.io/arzvaak/linux-broadcast-runtime:afx-2.1.0
./scripts/publish-container.sh
```

Runtime and application source are separate layers. The default reuses the published runtime pinned by digest. Set `BUILD_RUNTIME=1`
to rebuild it deliberately, or `RUNTIME_IMAGE=...@sha256:...` to select another
explicitly verified runtime.
A runtime change is a separate maintainer operation; SDK updates are never pulled
automatically into a running application.

Verify GPU access, model loading, all effects, PipeWire audio, window reopening,
persistent settings, and login behavior locally before publishing a stable tag.
Then make the linked GHCR package public and test anonymous access. A public source
repository alone does not make a newly created package public.

The **Promote container release** workflow runs only when explicitly dispatched.
It promotes an already built/tested digest to a version and `stable`; it performs
no SDK download, compiler build, or GPU matrix. Normal pushes do not trigger it.
GitHub currently provides free Container Registry image storage and bandwidth;
Actions runner minutes are a separate allowance.

## Issue #1 and desktop sandboxing

The reporter confirmed that current main fixes the Arch/glycin crash loop and
identified `RestrictSUIDSGID=true` as the failing restriction. Neither the native
nor container unit enables it. Both retain bounded restarts. The container does
not use privileged mode or disable the WebKit application sandbox by default.
An Arch/glycin report does not establish that every container/runtime combination
works: validate actual GTK/WebKit startup, rather than restoring restrictions
based only on unit syntax.
