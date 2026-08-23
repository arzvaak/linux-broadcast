# Changelog

## 0.2.0 - 2026-08-23

Complete self-contained Linux packages.

- RPM, DEB, and portable builds for RTX 20, 30, 40, and 50 generations
- Noise Removal, BNR 2.0, Room Echo, Noise + Room Echo, and Studio Voice models
- Measured CUDA, TensorRT, and NVIDIA AFX runtime closure included; unused cuDNN and Studio Voice HQ payloads excluded
- No NGC login, CUDA toolkit, or separate model download after installation
- Dedicated GitHub Pages download homepage and Netcup artifact mirror

## 0.1.0 - 2026-08-23

First public preview.

- Native NVIDIA AFX Noise + Room Echo processing on PipeWire
- Automatic RTX 20, 30, 40, and 50 architecture selection
- Minimal Tauri interface with microphone and monitoring-output selection
- Persistent Linux Broadcast virtual microphone
- Easy Effects-compatible routing
- Per-effect intensity, VAD, and 10/20 ms frame controls
- Background mode, tray integration, and start-at-login support
- Uncompressed generation-specific portable bundles without cuDNN

The RTX 40 bundle is hardware-probed on a GeForce RTX 4080. Other generation
bundles are architecture-validated and need community hardware reports.
