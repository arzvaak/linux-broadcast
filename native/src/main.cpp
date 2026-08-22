#include "afx_denoiser.hpp"
#include "gpu_model.hpp"

#include <array>
#include <cstdlib>
#include <filesystem>
#include <iostream>
#include <stdexcept>
#include <string_view>

int main(const int argc, char** argv) {
  try {
    if (argc < 2 || argc > 5 || std::string_view(argv[1]) != "--probe") {
      std::cerr << "Usage: linux-broadcast-afx --probe [effect] [frame-ms] [vad-0-or-1]\n";
      return 2;
    }
    std::filesystem::path sdk_root;
    if (const char* configured = std::getenv("AFX_SDK_ROOT"); configured != nullptr && *configured != '\0') {
      sdk_root = configured;
    } else if (const char* home = std::getenv("HOME"); home != nullptr && *home != '\0') {
      sdk_root = std::filesystem::path(home) / ".local/share/linux-broadcast/nvidia/current";
    } else {
      throw std::runtime_error("Could not locate AFX_SDK_ROOT or the user-local SDK");
    }
    const auto target = linux_broadcast::detect_gpu_target();
    const auto mode = linux_broadcast::parse_effect_mode(argc >= 3 ? argv[2] : "bnr2");
    auto effect = linux_broadcast::resolve_effect(sdk_root, target.sm_directory, mode);
    const unsigned frame_ms = argc >= 4 ? static_cast<unsigned>(std::stoul(argv[3])) : 10U;
    if ((frame_ms != 10U && frame_ms != 20U) ||
        (mode == linux_broadcast::EffectMode::kStudioVoice && frame_ms != 10U)) {
      throw std::invalid_argument("Unsupported frame size for the selected effect");
    }
    if (argc == 5 && effect.supports_vad) effect.enable_vad = std::string_view(argv[4]) != "0";
    const unsigned frame_samples = linux_broadcast::AfxDenoiser::kSampleRate * frame_ms / 1000U;
    std::cout << "Architecture: " << target.sm_directory << "\nEffect: " << effect.display_name
              << "\nFrame: " << frame_ms << " ms\nVAD: " << (effect.enable_vad ? "on" : "off")
              << "\nModel: " << effect.model << '\n';
    const auto logger_status = NvAFX_InitializeLogger(
        LOG_LEVEL_INFO, LOG_TARGET_STDERR, nullptr, nullptr, nullptr);
    if (logger_status != NVAFX_STATUS_SUCCESS) {
      throw std::runtime_error("Could not initialize the AFX logger");
    }
    {
      linux_broadcast::AfxDenoiser denoiser(effect, 1.0F, frame_samples);
      std::array<float, linux_broadcast::AfxDenoiser::kMaxFrameSamples> input{};
      std::array<float, linux_broadcast::AfxDenoiser::kMaxFrameSamples> output{};
      denoiser.process({input.data(), frame_samples}, {output.data(), frame_samples});
    }
    std::cout << effect.display_name << " probe passed: model loaded and one frame completed\n";
    NvAFX_UninitializeLogger();
    return 0;
  } catch (const std::exception& error) {
    std::cerr << "NVIDIA AFX probe failed: " << error.what() << '\n';
    return 1;
  }
}
