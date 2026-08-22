# Linux Broadcast

Linux Broadcast is a native NVIDIA Audio Effects SDK (AFX) voice processor for
PipeWire with a Tauri desktop interface. It runs NVIDIA's own Noise Removal,
experimental **BNR 2.0**, Room Echo Removal, combined Noise + Room Echo, and
Studio Voice Low Latency models. There are no substitute denoising backends.

## GPU and model selection

The application selects an architecture-specific TensorRT model from the GPU's
compute capability:

| GeForce generation | Compute capability | Model directory | NVIDIA package equivalent |
| --- | ---: | --- | --- |
| RTX 20 / Turing | 7.5 | `sm_75` | T4 |
| RTX 30 / Ampere | 8.6 | `sm_86` | A10 |
| RTX 40 / Ada | 8.9 | `sm_89` | L40 |
| RTX 50 / Blackwell | 12.0 | `sm_120` | RTX PRO 6000 |

The package equivalents identify matching compute architectures. They do not
imply official GeForce support from NVIDIA.

This covers desktop and laptop GeForce RTX cards, Quadro RTX, RTX A-series,
RTX Ada, and RTX PRO Blackwell cards. On multi-GPU systems the app prefers a
compatible RTX GPU with an installed model. Set `LINUX_BROADCAST_GPU_INDEX` to
override automatic selection.

```bash
./scripts/detect-gpu.sh
```

The Linux SDK's supported-device selector rejects GeForce cards, so the engine
retains CUDA device 0 and loads the matching model directly.

## Licensed AFX installation

Set `AFX_SDK_ROOT` to an extracted AFX 2.x SDK. Models and NVIDIA libraries are
never committed or redistributed by this project.

```text
$AFX_SDK_ROOT/
├── nvafx/include/nvAudioEffects.h
├── nvafx/lib/libnv_audiofx.so
└── features/
    ├── denoiser/
    ├── dereverb/
    ├── dereverb_denoiser/
    └── studio_voice/
```

With NVIDIA AI Enterprise access, install the 48 kHz feature packages for the
detected RTX architecture:

```bash
export AFX_SDK_ROOT=/path/to/Audio_Effects_SDK
./scripts/install-licensed-denoiser.sh
```

The installer reads the standard NGC CLI credential store when `NGC_API_KEY` is
not set.

## Native engine

The engine configures AFX for 48 kHz mono and one stream. Regular effects can
use NVIDIA-supported 10 ms or 20 ms frames; Studio Voice Low Latency is fixed
to 10 ms. VAD, intensity, and effect-version parameters are applied only to
models that support them.

```bash
cmake -S native -B build/native -DAFX_SDK_ROOT="$AFX_SDK_ROOT"
cmake --build build/native -j
export LD_LIBRARY_PATH="$AFX_SDK_ROOT/nvafx/lib:$AFX_SDK_ROOT/features/denoiser/lib:$AFX_SDK_ROOT/features/dereverb/lib:$AFX_SDK_ROOT/features/dereverb_denoiser/lib:$AFX_SDK_ROOT/features/studio_voice/lib:$AFX_SDK_ROOT/external/cuda/lib:${LD_LIBRARY_PATH:-}"
./build/native/linux-broadcast-afx --probe noise
./build/native/linux-broadcast-afx --probe bnr2
./build/native/linux-broadcast-afx --probe room_echo
./build/native/linux-broadcast-afx --probe noise_room_echo
./build/native/linux-broadcast-afx --probe studio_voice
```

The probe loads the selected model and processes one frame.

## Tauri UI

`ui/` is a working Tauri 2 desktop wrapper around the native AFX engine. Its
Rust bridge detects physical PipeWire microphones, starts a persistent
`pw-cli` controller, loads the selected AFX effect chain, and publishes the
processed stream as `linux_broadcast.source`. Stopping the effect or quitting
from the tray removes the virtual microphone. Closing the window keeps it
active when **Run in background** is enabled.

The UI exposes the input source, effect mode, intensity, headphone monitoring,
GPU architecture, and model/plugin readiness. Monitoring is off by default to
prevent speaker feedback. Easy Effects is used as the monitoring source when
available.

SDK-specific VAD and frame sizing live in the collapsed Advanced view. A fresh
installation starts with Noise Removal, 75% intensity, VAD off, and 20 ms
frames. Every effect remembers its own tuning.

The Settings page contains the two lifecycle controls:

- **Run in background** closes the window to the tray while keeping NVIDIA AFX
  and the virtual microphone active.
- **Start at login** installs and enables a user-level systemd service. It
  launches the app hidden with the saved microphone, effect, and tuning.
  Enabling it also enables background mode.

The release build can also be installed or removed from the terminal:

```bash
./scripts/install-background-service.sh
./scripts/uninstall-background-service.sh
```

The service installs only into the current user's `~/.local` and
`~/.config/systemd/user` directories; it does not require root.

Build the native plugin first, then the release wrapper:

```bash
cmake -S native -B build/native-cmake \
  -DAFX_SDK_ROOT="$HOME/.local/share/linux-broadcast/nvidia/current"
cmake --build build/native-cmake -j
npm ci --prefix ui
npm run tauri --prefix ui -- build
./ui/src-tauri/target/release/linux-broadcast
```

The Tauri build produces RPM and DEB packages under
`ui/src-tauri/target/release/bundle/`. The packages include the native wrapper,
but not NVIDIA's licensed SDK libraries or models.

The application looks for the native plugin at
`build/native-cmake/liblinux_broadcast_afx_ladspa.so`. `AFX_SDK_ROOT` and
`LINUX_BROADCAST_PLUGIN` can override the default SDK and plugin paths.

## Primary references

- [AFX model architecture layout](https://docs.nvidia.com/maxine/afx/latest/UseAFXInApps/SetParametersOfAnEffect.html)
- [BNR 2.0](https://docs.nvidia.com/maxine/afx/latest/AboutTheEffects/AboutNoiseRemovalBackgroundNoiseSuppression.html)
- [Set AFX effect parameters](https://docs.nvidia.com/maxine/afx/latest/UseAFXInApps/SetParametersOfAnEffect.html)
- [Query supported AFX frame sizes](https://docs.nvidia.com/maxine/afx/latest/UseAFXInApps/GetParametersOfAnEffect.html)
- [Studio Voice modes and latency](https://docs.nvidia.com/maxine/afx/2.1.0/AboutTheEffects/AboutStudioVoiceEffect.html)
- [Official AFX samples](https://github.com/NVIDIA-Maxine/AFX-SDK-Samples)
