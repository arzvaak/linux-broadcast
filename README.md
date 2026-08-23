<div align="center">
  <img src="ui/src-tauri/icons/icon.png" alt="Linux Broadcast" width="88">
  <h1>Linux Broadcast</h1>
  <p>NVIDIA Broadcast-style voice processing for Linux, powered by NVIDIA AFX.</p>
  <p>
    <a href="https://github.com/arzvaak/linux-broadcast/releases"><img src="https://img.shields.io/github/v/release/arzvaak/linux-broadcast?include_prereleases" alt="Release"></a>
    <a href="https://github.com/arzvaak/linux-broadcast/actions/workflows/ci.yml"><img src="https://github.com/arzvaak/linux-broadcast/actions/workflows/ci.yml/badge.svg" alt="CI"></a>
    <a href="LICENSE"><img src="https://img.shields.io/github/license/arzvaak/linux-broadcast" alt="MIT License"></a>
    <img src="https://img.shields.io/badge/platform-Linux-111111" alt="Linux">
    <img src="https://img.shields.io/badge/GPU-NVIDIA%20RTX-76B900" alt="NVIDIA RTX">
  </p>
</div>

Linux Broadcast is a native NVIDIA Audio Effects SDK (AFX) voice processor for
PipeWire with a minimal Tauri desktop interface. The codebase supports NVIDIA's
Noise Removal, experimental **BNR 2.0**, Room Echo Removal, combined Noise +
Room Echo, and Studio Voice Low Latency models. There are no substitute
denoising backends.

## Features

- NVIDIA Noise Removal and experimental BNR 2.0
- Room Echo Removal and combined Noise + Room Echo processing
- Studio Voice Low Latency
- Automatic RTX 20, 30, 40, and 50-series model selection
- A persistent `Linux Broadcast Microphone` for PipeWire applications
- Physical microphone and monitoring-output selection
- Easy Effects-compatible routing
- Per-effect intensity, VAD, and frame-size controls
- Background operation, system tray, and start-at-login support

## Installation

Linux Broadcast requires an RTX GPU, the proprietary NVIDIA driver, PipeWire,
and WebKitGTK 4.1. The public preview provides uncompressed portable bundles
from [GitHub Releases](https://github.com/arzvaak/linux-broadcast/releases).
Each bundle contains the app, native plugin, licensed NVIDIA runtime, and one
architecture-specific **Noise + Room Echo** model. The bundles intentionally
omit cuDNN, separate Noise Removal and Room Echo models, BNR 2.0, and Studio
Voice. The application only offers effects whose models are installed.

Choose the release matching the installed GPU generation:

| Download | GPUs |
| --- | --- |
| `linux-broadcast-0.1.0-rtx20-x86_64.tar` | GeForce RTX 20 and Quadro RTX |
| `linux-broadcast-0.1.0-rtx30-x86_64.tar` | GeForce RTX 30 and RTX A-series |
| `linux-broadcast-0.1.0-rtx40-x86_64.tar` | GeForce RTX 40 and RTX Ada |
| `linux-broadcast-0.1.0-rtx50-x86_64.tar` | GeForce RTX 50 and RTX PRO Blackwell |

Extract the matching archive and run its launcher:

```bash
tar -xf linux-broadcast-0.1.0-rtx40-x86_64.tar
cd linux-broadcast-0.1.0-rtx40-x86_64
./linux-broadcast
```

Verify the download with the accompanying `SHA256SUMS` file. Portable bundles
are not registered with the system package manager. RPM and DEB builds remain
available for maintainers using the packaging instructions below.

This is a public preview. The RTX 40 bundle is hardware-probed on a GeForce RTX
4080. RTX 20, 30, and 50 bundles pass the same architecture, model, and runtime
checks but still need compatibility reports from those GPUs.

### Fedora, RHEL, and compatible distributions

```bash
sudo dnf install ./linux-broadcast-<version>-rtx<series>.x86_64.rpm
```

Remove it with `sudo dnf remove linux-broadcast`.

### Debian, Ubuntu, and compatible distributions

```bash
sudo apt install ./linux-broadcast_<version>_rtx<series>_amd64.deb
```

Remove it with `sudo apt remove linux-broadcast`.

RPM and DEB installations are available from the desktop menu or as
`linux-broadcast`. Portable bundles are launched from their extracted
directory. Source builds use `AFX_SDK_ROOT` or
`~/.local/share/linux-broadcast/nvidia/current`.

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

Set `AFX_SDK_ROOT` to an extracted AFX 2.x SDK. NVIDIA files are never committed
to Git. Release packages stage the permitted runtime subset and applicable
license notices directly from this directory.

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
not set. When run in a terminal without either configuration, it prompts for a
personal key without echoing or saving it.

To create an NGC personal key:

1. Sign in to [NVIDIA NGC](https://org.ngc.nvidia.com/setup/personal-keys).
2. Select **Generate Personal Key**, give it a descriptive name, and grant the
   catalog access required by the AFX resources in your organization.
3. Copy the key when NVIDIA displays it. NVIDIA does not display it again.
4. Run `./scripts/install-licensed-denoiser.sh` and paste the key at the secure
   prompt, or configure it with `ngc config set`.

Release RPM and DEB files already contain their targeted models and do not ask
for an NGC key during package installation. The key flow is for source builds,
custom architecture packages, and future models that are not in a release.

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

The UI exposes the input source, installed effect modes, intensity, headphone
monitoring, GPU architecture, and model/plugin readiness. Monitoring is off by
default to prevent speaker feedback. Easy Effects is used as the monitoring
source when available.

SDK-specific VAD and frame sizing live in the collapsed Advanced view. A
prebuilt installation starts with Noise + Room Echo, 70% intensity, VAD off,
and 20 ms frames. Every installed effect remembers its own tuning.

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

## Build from source

The source build requires CMake 3.20 or newer, a C++20 compiler, LADSPA
headers, Node.js 20.19 or newer, npm, the stable Rust toolchain, and the Linux
dependencies required by Tauri 2.

Fedora:

```bash
sudo dnf install gcc-c++ cmake ladspa-devel nodejs npm rust cargo \
  pkgconf-pkg-config webkit2gtk4.1-devel openssl-devel \
  libappindicator-gtk3-devel librsvg2-devel libxdo-devel pipewire-utils
```

Debian or Ubuntu:

```bash
sudo apt update
sudo apt install build-essential cmake ladspa-sdk pkg-config curl wget file \
  libwebkit2gtk-4.1-dev libssl-dev libayatana-appindicator3-dev \
  librsvg2-dev libxdo-dev pipewire-bin
```

Install a supported Node.js release and the stable Rust toolchain if the
distribution versions do not meet the requirements above. Then clone the
repository, configure the licensed SDK, and build the native plugin followed by
the desktop application:

```bash
git clone https://github.com/arzvaak/linux-broadcast.git
cd linux-broadcast

export AFX_SDK_ROOT="$HOME/.local/share/linux-broadcast/nvidia/current"
cmake -S native -B build/native-cmake \
  -DAFX_SDK_ROOT="$AFX_SDK_ROOT" \
  -DBUILD_TESTING=ON
cmake --build build/native-cmake --parallel
ctest --test-dir build/native-cmake --output-on-failure

npm ci --prefix ui
npm run build --prefix ui
cargo test --manifest-path ui/src-tauri/Cargo.toml --locked
npm run tauri --prefix ui -- build --no-bundle
./ui/src-tauri/target/release/linux-broadcast
```

The application automatically uses the plugin at
`build/native-cmake/liblinux_broadcast_afx_ladspa.so`. `AFX_SDK_ROOT` and
`LINUX_BROADCAST_PLUGIN` override the default SDK and plugin paths.

## Build RPM and DEB packages

Each release package contains one GPU generation so downloads do not carry
models that cannot run on the target machine. The compact profile contains the
combined 48 kHz Noise + Room Echo model and the runtime libraries it loads. It
does not contain cuDNN. NVIDIA files remain outside Git and are read from
`AFX_SDK_ROOT` only while packaging.

Build the RPM and DEB for a generation after installing its model variant into
the SDK tree:

```bash
export AFX_SDK_ROOT=/path/to/Audio_Effects_SDK
./scripts/build-packages.sh rtx40
```

Supported release targets are:

| Release target | GPUs | Model architecture |
| --- | --- | --- |
| `rtx20` | RTX 20 and Quadro RTX | `sm_75` |
| `rtx30` | RTX 30 and RTX A-series | `sm_86` |
| `rtx40` | RTX 40 and RTX Ada | `sm_89` |
| `rtx50` | RTX 50 and RTX PRO Blackwell | `sm_120` |

The resulting files are written to:

```text
build/releases/<version>/<series>/linux-broadcast-<version>-<series>.x86_64.rpm
build/releases/<version>/<series>/linux-broadcast_<version>_<series>_amd64.deb
```

The staging script copies only the combined model, required runtime libraries,
and applicable license notices. It fails if cuDNN or a credential-like file is
found in the staged tree. NGC configuration and credentials are never read into
the package.

Create the four uncompressed portable release archives with:

```bash
export AFX_SDK_ROOT=/path/to/Audio_Effects_SDK
./scripts/build-portable-releases.sh
```

## Primary references

- [AFX model architecture layout](https://docs.nvidia.com/maxine/afx/latest/UseAFXInApps/SetParametersOfAnEffect.html)
- [BNR 2.0](https://docs.nvidia.com/maxine/afx/latest/AboutTheEffects/AboutNoiseRemovalBackgroundNoiseSuppression.html)
- [Set AFX effect parameters](https://docs.nvidia.com/maxine/afx/latest/UseAFXInApps/SetParametersOfAnEffect.html)
- [Query supported AFX frame sizes](https://docs.nvidia.com/maxine/afx/latest/UseAFXInApps/GetParametersOfAnEffect.html)
- [Studio Voice modes and latency](https://docs.nvidia.com/maxine/afx/2.1.0/AboutTheEffects/AboutStudioVoiceEffect.html)
- [Official AFX samples](https://github.com/NVIDIA-Maxine/AFX-SDK-Samples)

## About me

I'm Ayush, also known as [Arzvak](https://github.com/arzvaak). I study electrical
and electronics engineering and build software around the problems I run into.
I started Linux Broadcast because Linux users with RTX hardware should have a
native, polished voice-processing tool instead of giving up the NVIDIA hardware
they already own.

## Contributing

Bug reports, compatibility results, documentation improvements, and focused
pull requests are welcome. Read [CONTRIBUTING.md](CONTRIBUTING.md) before making
a change. Please report security issues through the process in
[SECURITY.md](SECURITY.md), not a public issue.

## License

The Linux Broadcast source code is available under the [MIT License](LICENSE).
NVIDIA AFX libraries and models remain NVIDIA software and are distributed in
release packages under their accompanying NVIDIA license terms. They are not
part of the MIT-licensed source repository.

Linux Broadcast is an independent project and is not sponsored or endorsed by
NVIDIA Corporation. NVIDIA, RTX, and NVIDIA Broadcast are trademarks of NVIDIA
Corporation.

## Acknowledgements

- [NVIDIA Maxine Audio Effects SDK](https://developer.nvidia.com/maxine)
- [PipeWire](https://pipewire.org/) for the Linux audio graph
- [Tauri](https://tauri.app/) for the desktop application framework
- [BluCast](https://github.com/Andrei9383/Blucast) for demonstrating another
  community-built Maxine workflow on Linux
