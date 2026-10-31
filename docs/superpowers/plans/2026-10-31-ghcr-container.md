# GHCR Container Implementation Plan

> **For agentic workers:** Use superpowers:executing-plans to implement this plan inline.

**Goal:** Publish and verify a public all-RTX Linux Broadcast image with a desktop launcher.
**Architecture:** Versioned SDK runtime layers reused by a Tauri app image; host launcher forwards session sockets and manages one per-user container.
**Tech Stack:** Podman/Docker, OCI/GHCR, Bash, Rust/Tauri, GitHub Actions.
**Spec:** ../specs/2026-10-31-ghcr-container-design.md

## Global Constraints
- AFX 2.1.0; amd64; all four supported model architectures.
- Preserve original checkout and existing dependency fixes.
- No privileged container, Docker socket mount, broad X server permissions, or host networking by default.
- Issue #1: do not reintroduce RestrictSUIDSGID; retain bounded restart behavior.
- Keep Actions usage low: publish manually; reuse local results; no GPU CI matrix.

## Review Focus
- Existing background container: second launch reopens it without duplicate processing.
- Runtime-only host: no source checkout, NGC key, or SDK required.
- Missing GPU/CDI/session sockets: actionable error.
- GTK/WebKit sandbox and PipeWire client plugin remain functional.
- Persistent state and host login toggle survive container replacement.

## Tasks
- [x] Add a small local launcher-contract test for engine arguments, reuse, and missing prerequisites; observe failure.
- [x] Add container launcher, installer, runtime staging and layered Containerfiles; keep runtime build context explicit.
- [x] Add container-aware host login service control and existing-container window activation.
- [x] Run focused shell/Rust/frontend checks locally, build image, test actual GPU/PipeWire/desktop behavior.
- [x] Add manual GHCR publishing workflow and installation documentation; keep existing release downloads.
- [x] Review changes once; fix material findings; publish image and verify anonymous pull; commit/push source and report verification limits.

## Execution ledger
- User approved implementation/public publishing; no extra plan approval required.
- Source baseline: 1fe96d8 plus existing local dependency fixes copied into isolated checkout.
- Issue #1 reporter confirms main fixed; do not re-add hardening without platform evidence.

- Live verification: all five AFX effects processed 48000 finite output samples each; real PD200X-to-container plugin-to-host virtual source reached running state, output discarded.
- Fixed live runtime failures: old PipeWire 0.3.65 JSON incompatibility, writable runtime directory, persistent WebKit storage, and host systemctl offline unit-file operations.
- Review fixes: shared native/container single-instance D-Bus identity, explicit unit stop, Xauthority fallback, and fresh-cache runtime pre-pull.

- Final validation: three launcher contract checks, six Rust tests, frontend build, native GPU-model test in image build, rootless GPU access, all five DSP effects, live PipeWire route, device JSON/default input, persistent home, cross-edition single-instance forwarding, and adopted-unit stop (0.16 s) passed. X11 and RTX20/30/50 hardware remain unverified.
- User requested no further interruptions to their running app; all remaining work is registry/source publication and read-only verification.
