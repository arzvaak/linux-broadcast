# Linux Broadcast public container distribution

## Intent and scope

Replace the repeated NVIDIA payloads in GPU-specific desktop downloads with a public GitHub Container Registry image for `arzvaak/linux-broadcast`. Keep the existing Tauri application, NVIDIA AFX effects, PipeWire virtual microphone, microphone reconnection, tray, settings, and background operation. Hermes and the homelab service migration are unrelated work.

The user chose container distribution after reviewing Blucast. The choices below are proposed implementation decisions, pending approval. No existing downloads or installed services are to be removed during this work.

## Approaches

1. Four GPU-specific images share a runtime layer and select model layers by generation. This minimizes each user's initial download, but retains generation-specific image builds and launcher tag selection.
2. One image includes the common runtime and all four model sets. This gives one build and release per version and lets the existing GPU selection choose models at runtime. The initial payload is larger, but registry layers are cached between app updates.
3. A container imports or downloads NVIDIA dependencies on first launch. This reduces image size, but brings NGC credentials/access and runtime installation into ordinary setup.

Recommend approach 2 because reducing release maintenance is the user's stated concern. Measured v0.2.1 payloads suggest approximately 4.67 GiB of common NVIDIA files plus all four model sets before compression; this is not a measured final image size. SDK compatibility remains pinned to AFX 2.1.0 initially. No automatic SDK upgrade is part of this change.

## Image and build

Use Linux amd64 initially, matching the existing packages. Publish `ghcr.io/arzvaak/linux-broadcast` with immutable version tags and a stable tag only after validation. Include OCI source, revision, version, and license labels.

Build the app and native plugin using a multi-stage Containerfile with a pinned compatible Linux baseline. Place NVIDIA core/runtime/effect libraries and all four model directories in layers independent of application source. Include required NVIDIA notices. Build dependencies stay out of the runtime image. Do not include NGC credentials, SDK headers not needed at runtime, host configuration, source checkout credentials, or caches. Use explicit staging and a strict build-context allowlist.

The initial runtime is staged from the already installed SDK using the project's existing measured-library staging logic. SDK acquisition remains a maintainer operation. CI can build application layers against an explicitly pinned, published runtime base without requiring end users to hold NGC credentials. A runtime version change requires a deliberate rebuild, inspection, and smoke test.

The installed SDK's AI product terms section 1.1.3 permits distribution as part of a Customer Product, subject to the agreement's conditions. Keep runtime distribution tied to Linux Broadcast and review the actual feature/model notices before publishing; a public source license does not relicense NVIDIA components. Do not publish an unrelated general-purpose SDK mirror.

## Host launcher and desktop integration

Provide a host launcher and install/uninstall scripts. Prefer rootless Podman; support Docker where session UID and GPU access can be verified. Detect prerequisites and report actionable errors. Installation creates a desktop entry and optional user service pointing at the host launcher, rather than installing NVIDIA files into the host.

Run with the user's identity. Expose the selected GPU through NVIDIA Container Toolkit/CDI as supported by the chosen engine. Bind only the necessary PipeWire socket, Wayland socket or X11 connection/authentication, session D-Bus socket, and application settings directory. No Docker socket, host root filesystem, privileged mode, global X server access changes, or host network mode is required by default. Account for Fedora SELinux without relabeling desktop session sockets or modifying global policy.

The PipeWire client and its LADSPA plugin run inside the container and connect to the host PipeWire server. Do not require the host PipeWire daemon to load a container-only plugin path. Verify this with actual virtual-source creation and audio processing.

Keep user settings in a persistent host directory with correct ownership. If settings migration from an existing native install is required, preserve a backup and avoid running two processors simultaneously. Host autostart/service management must target the host launcher: the app's existing systemctl operations need an explicit container-aware path or helper. Do not silently claim start-at-login support merely because the GUI launches.

Maintain one container per desktop user. A second desktop launch must activate the existing application's window, including when it was started in background mode, rather than create another audio processor. Define an activation mechanism that works across container invocations instead of assuming the native single-instance lock spans namespaces. Verify desktop launch, close-to-tray, tray reopen, and service restart together.

Validate WebKit sandbox operation under the selected rootless engine. Do not blanket-disable application sandboxing or use privileged mode as a default workaround. GTK/WebKit, tray D-Bus, Wayland/X11, and session forwarding can require platform-specific handling; failures must remain explicit.

## Publishing and user installation

Add a GHCR workflow using repository-scoped `GITHUB_TOKEN` and minimum permissions, with write access only in the publishing job. Pull-request checks must not publish or receive publishing credentials. Separate app-image publishing from maintainer runtime publication. Pin the runtime digest and require successful validation before moving stable tags.

Verify the GHCR package is public and that an anonymous client can fetch its manifest/image. A public source repository alone does not guarantee package visibility. Never pass credentials in build arguments or image layers. Verify GitHub's current registry billing policy; container image storage and bandwidth are currently free, while Actions compute is a separate allowance.

Update README and the download homepage to explain the supported container installation, GPU/driver prerequisites, persistent settings, update/uninstall behavior, and known validation limits. Preserve existing release URLs until an explicit retirement decision.

## Validation and completion criteria

- Preserve existing local uncommitted dependency changes. Proposed source baseline is the current local application tree, including the existing dependency updates after verification; carry that state into an isolated checkout without altering or discarding the user's original files. Record its commit and patch provenance before building.
- Run shell validation, launcher contract tests where meaningful, frontend build, Rust tests, native GPU-selection/plugin tests, and image build checks.
- Inspect staged files and image history for unintended credentials or host files; verify source/model/runtime provenance and required notices.
- On the available RTX 4080 SUPER, verify GPU access, AFX model loading, all supported effects, real host PipeWire input/output, microphone reconnect behavior, persistent settings, tray reopen, and background startup/shutdown.
- Test Wayland on the current host. Report X11 and RTX 20/30/50 as unverified unless actually exercised. Included models and passing unit tests are not proof of hardware validation.
- Publish and independently verify anonymous GHCR access. Report measured compressed image size and app-update layer reuse.
- Do not retire Netcup downloads or replace the user's installed native application until the container path has passed its checks and any unresolved behavior is disclosed.

## Open implementation decisions

Select exact base-image digests and toolchain versions from the repository's requirements. Determine a safe container-aware implementation for autostart and host service control. Check GPU Toolkit/CDI prerequisites on the current host before installing anything. Settle these routine details during implementation and record material deviations.
