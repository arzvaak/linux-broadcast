Linux Broadcast portable bundle

Run ./linux-broadcast from this directory. The launcher selects the NVIDIA AFX
runtime and native PipeWire plugin included in the bundle.

Requirements:
- A supported NVIDIA RTX GPU and proprietary NVIDIA driver
- PipeWire and pw-cli
- WebKitGTK 4.1 and the normal Tauri Linux desktop libraries

The bundle includes the measured NVIDIA AFX runtime needed by Linux Broadcast,
including CUDA and TensorRT libraries, plus Noise Removal, BNR 2.0, Room
Echo Removal, Noise + Room Echo and low-latency Studio Voice for its RTX
generation. No NVIDIA SDK, CUDA toolkit or NGC login is required.

This bundle contains NVIDIA software under the license notices inside nvidia/.
The Linux Broadcast source code is licensed under the accompanying MIT LICENSE.
