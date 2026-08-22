#pragma once

#include <filesystem>
#include <span>
#include <string>
#include <nvAudioEffects.h>

namespace linux_broadcast {

enum class EffectMode { kNoise, kBnr2, kRoomEcho, kNoiseRoomEcho, kStudioVoice };

struct EffectSpec {
  EffectMode mode;
  std::string selector;
  std::string display_name;
  std::filesystem::path model;
  bool effect_version_2;
  bool supports_vad;
  bool enable_vad;
  bool supports_intensity;
};

EffectMode parse_effect_mode(const std::string& value);
EffectSpec resolve_effect(const std::filesystem::path& sdk_root,
                          const std::string& architecture,
                          EffectMode mode);

class AfxDenoiser final {
 public:
  static constexpr unsigned kSampleRate = 48000;
  static constexpr unsigned kFrameSamples = 480;
  static constexpr unsigned kMaxFrameSamples = 960;
  static constexpr unsigned kEffectVersion = 2;

  explicit AfxDenoiser(const EffectSpec& effect, float intensity = 1.0F,
                       unsigned frame_samples = kFrameSamples);
  ~AfxDenoiser();
  AfxDenoiser(const AfxDenoiser&) = delete;
  AfxDenoiser& operator=(const AfxDenoiser&) = delete;

  void process(std::span<const float> input, std::span<float> output);
  void set_intensity(float intensity);

 private:
  static void require(NvAFX_Status status, const char* operation);
  NvAFX_Handle handle_ = nullptr;
  bool supports_intensity_ = true;
  unsigned frame_samples_ = kFrameSamples;
};

}  // namespace linux_broadcast
