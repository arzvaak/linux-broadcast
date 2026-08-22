# Contributing

Thanks for helping improve Linux Broadcast.

Before opening a pull request, search the existing issues and keep the change
focused. Describe the GPU, driver, distribution, desktop session, PipeWire
version, microphone, selected effect, and exact reproduction steps for audio or
compatibility bugs.

## Development checks

Set `AFX_SDK_ROOT` to an extracted NVIDIA AFX 2.x SDK, then run:

```bash
cmake -S native -B build/native-cmake \
  -DAFX_SDK_ROOT="$AFX_SDK_ROOT" \
  -DBUILD_TESTING=ON
cmake --build build/native-cmake --parallel
ctest --test-dir build/native-cmake --output-on-failure
npm ci --prefix ui
npm run build --prefix ui
cargo test --manifest-path ui/src-tauri/Cargo.toml --locked
```

Do not commit NVIDIA SDK files, models, build output, credentials, recordings,
or local device configuration. Pull requests should explain what changed, why
it changed, and how it was verified.

By contributing, you agree that your contribution is licensed under the MIT
License used by this repository.
