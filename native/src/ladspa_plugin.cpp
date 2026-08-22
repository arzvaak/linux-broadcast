#include "afx_denoiser.hpp"
#include "gpu_model.hpp"

#include <ladspa.h>
#include <dlfcn.h>

#include <algorithm>
#include <array>
#include <cmath>
#include <cstdlib>
#include <filesystem>
#include <memory>
#include <mutex>
#include <string_view>

namespace {

constexpr unsigned long kPluginId = 41089;
constexpr unsigned long kInputPort = 0;
constexpr unsigned long kOutputPort = 1;
constexpr unsigned long kIntensityPort = 2;
constexpr unsigned long kPortCount = 3;

std::filesystem::path sdk_root() {
  if (const char* configured = std::getenv("AFX_SDK_ROOT"); configured != nullptr && *configured) {
    return configured;
  }
  if (const char* home = std::getenv("HOME"); home != nullptr && *home) {
    return std::filesystem::path(home) / ".local/share/linux-broadcast/nvidia/current";
  }
  throw std::runtime_error("AFX SDK location is unavailable");
}

linux_broadcast::EffectSpec prepare_effect() {
  static std::once_flag runtime_libraries_loaded;
  static std::string runtime_library_error;
  std::call_once(runtime_libraries_loaded, [] {
    constexpr std::array runtime_libraries = {
        "libnvinfer_plugin.so.10",
        "libcufft.so.11",
    };
    for (const char* library : runtime_libraries) {
      if (dlopen(library, RTLD_NOW | RTLD_GLOBAL) == nullptr) {
        runtime_library_error = std::string("Could not load AFX runtime library: ") + library;
        break;
      }
    }
  });
  if (!runtime_library_error.empty()) {
    throw std::runtime_error(runtime_library_error);
  }
  const auto target = linux_broadcast::detect_gpu_target();
  const char* configured = std::getenv("LINUX_BROADCAST_EFFECT");
  const auto mode = linux_broadcast::parse_effect_mode(
      configured == nullptr || *configured == '\0' ? "bnr2" : configured);
  auto effect = linux_broadcast::resolve_effect(sdk_root(), target.sm_directory, mode);
  if (const char* configured_vad = std::getenv("LINUX_BROADCAST_VAD");
      configured_vad != nullptr && *configured_vad != '\0' && effect.supports_vad) {
    effect.enable_vad = std::string_view(configured_vad) != "0";
  }
  return effect;
}

unsigned configured_frame_samples(const linux_broadcast::EffectSpec& effect) {
  const char* configured = std::getenv("LINUX_BROADCAST_FRAME_MS");
  const unsigned frame_ms = configured == nullptr || *configured == '\0'
                                ? 10U
                                : static_cast<unsigned>(std::strtoul(configured, nullptr, 10));
  if ((frame_ms != 10U && frame_ms != 20U) ||
      (effect.mode == linux_broadcast::EffectMode::kStudioVoice && frame_ms != 10U)) {
    throw std::runtime_error("Unsupported frame size for the selected NVIDIA AFX effect");
  }
  return linux_broadcast::AfxDenoiser::kSampleRate * frame_ms / 1000U;
}

class PluginInstance {
 public:
  explicit PluginInstance(const unsigned long sample_rate)
      : PluginInstance(sample_rate, prepare_effect()) {}

 private:
  PluginInstance(const unsigned long sample_rate, const linux_broadcast::EffectSpec& effect)
      : frame_samples_(configured_frame_samples(effect)), denoiser_(effect, 1.0F, frame_samples_) {
    if (sample_rate != linux_broadcast::AfxDenoiser::kSampleRate) {
      throw std::runtime_error("Linux Broadcast requires 48 kHz audio");
    }
  }

 public:
  void connect(const unsigned long port, LADSPA_Data* data) {
    if (port == kInputPort) input_ = data;
    if (port == kOutputPort) output_ = data;
    if (port == kIntensityPort) intensity_ = data;
  }

  void reset() noexcept {
    input_fill_ = 0;
    output_read_ = 0;
    output_write_ = 0;
    output_count_ = 0;
    failed_ = false;
    input_frame_.fill(0.0F);
    output_frame_.fill(0.0F);
    output_queue_.fill(0.0F);
  }

  void run(const unsigned long sample_count) noexcept {
    if (output_ == nullptr) return;
    if (input_ == nullptr || failed_) {
      std::fill_n(output_, sample_count, 0.0F);
      return;
    }

    try {
      const float requested = intensity_ == nullptr ? 1.0F : std::clamp(*intensity_, 0.0F, 1.0F);
      if (std::fabs(requested - active_intensity_) > 0.0001F) {
        denoiser_.set_intensity(requested);
        active_intensity_ = requested;
      }

      for (unsigned long index = 0; index < sample_count; ++index) {
        input_frame_[input_fill_++] = input_[index];
        output_[index] = pop_output();
        if (input_fill_ == frame_samples_) {
          denoiser_.process({input_frame_.data(), frame_samples_},
                            {output_frame_.data(), frame_samples_});
          push_frame({output_frame_.data(), frame_samples_});
          input_fill_ = 0;
        }
      }
    } catch (...) {
      failed_ = true;
      std::fill_n(output_, sample_count, 0.0F);
    }
  }

 private:
  float pop_output() noexcept {
    if (output_count_ == 0) return 0.0F;
    const float value = output_queue_[output_read_];
    output_read_ = (output_read_ + 1) % output_queue_.size();
    --output_count_;
    return value;
  }

  void push_frame(const std::span<const float> frame) noexcept {
    for (const float value : frame) {
      if (output_count_ == output_queue_.size()) {
        output_read_ = (output_read_ + 1) % output_queue_.size();
        --output_count_;
      }
      output_queue_[output_write_] = value;
      output_write_ = (output_write_ + 1) % output_queue_.size();
      ++output_count_;
    }
  }

  std::size_t frame_samples_ = linux_broadcast::AfxDenoiser::kFrameSamples;
  linux_broadcast::AfxDenoiser denoiser_;
  LADSPA_Data* input_ = nullptr;
  LADSPA_Data* output_ = nullptr;
  LADSPA_Data* intensity_ = nullptr;
  float active_intensity_ = 1.0F;
  bool failed_ = false;
  std::array<float, linux_broadcast::AfxDenoiser::kMaxFrameSamples> input_frame_{};
  std::array<float, linux_broadcast::AfxDenoiser::kMaxFrameSamples> output_frame_{};
  std::array<float, linux_broadcast::AfxDenoiser::kMaxFrameSamples * 2> output_queue_{};
  std::size_t input_fill_ = 0;
  std::size_t output_read_ = 0;
  std::size_t output_write_ = 0;
  std::size_t output_count_ = 0;
};

LADSPA_Handle instantiate(const LADSPA_Descriptor*, const unsigned long sample_rate) {
  try {
    return new PluginInstance(sample_rate);
  } catch (...) {
    return nullptr;
  }
}

void connect_port(const LADSPA_Handle instance, const unsigned long port, LADSPA_Data* data) {
  static_cast<PluginInstance*>(instance)->connect(port, data);
}

void activate(const LADSPA_Handle instance) {
  static_cast<PluginInstance*>(instance)->reset();
}

void run(const LADSPA_Handle instance, const unsigned long count) {
  static_cast<PluginInstance*>(instance)->run(count);
}

void cleanup(const LADSPA_Handle instance) {
  delete static_cast<PluginInstance*>(instance);
}

const LADSPA_Descriptor* descriptor() {
  static constexpr std::array<LADSPA_PortDescriptor, kPortCount> port_descriptors = {
      LADSPA_PORT_INPUT | LADSPA_PORT_AUDIO,
      LADSPA_PORT_OUTPUT | LADSPA_PORT_AUDIO,
      LADSPA_PORT_INPUT | LADSPA_PORT_CONTROL,
  };
  static constexpr std::array<const char*, kPortCount> port_names = {
      "Microphone Input", "NVIDIA AFX Output", "Intensity",
  };
  static constexpr std::array<LADSPA_PortRangeHint, kPortCount> range_hints = {{
      {0, 0.0F, 0.0F},
      {0, 0.0F, 0.0F},
      {LADSPA_HINT_BOUNDED_BELOW | LADSPA_HINT_BOUNDED_ABOVE | LADSPA_HINT_DEFAULT_MAXIMUM,
       0.0F, 1.0F},
  }};
  static const LADSPA_Descriptor value = {
      kPluginId,
      "linux_broadcast_bnr2",
      0,
      "Linux Broadcast — NVIDIA AFX Voice Effects",
      "Ayush",
      "Proprietary NVIDIA AFX runtime; Linux Broadcast wrapper is MIT",
      kPortCount,
      port_descriptors.data(),
      port_names.data(),
      range_hints.data(),
      nullptr,
      instantiate,
      connect_port,
      activate,
      run,
      nullptr,
      nullptr,
      nullptr,
      cleanup,
  };
  return &value;
}

}  // namespace

extern "C" const LADSPA_Descriptor* ladspa_descriptor(const unsigned long index) {
  return index == 0 ? descriptor() : nullptr;
}
