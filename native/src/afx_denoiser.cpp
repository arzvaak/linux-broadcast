#include "afx_denoiser.hpp"

#include <denoiser.h>
#include <algorithm>
#include <cctype>
#include <stdexcept>
#include <string>

namespace linux_broadcast {

void AfxDenoiser::require(const NvAFX_Status status, const char* operation) {
  if (status != NVAFX_STATUS_SUCCESS) {
    throw std::runtime_error(std::string(operation) + " failed with status " +
                             std::to_string(static_cast<int>(status)));
  }
}

EffectMode parse_effect_mode(const std::string& value) {
  std::string mode = value;
  std::transform(mode.begin(), mode.end(), mode.begin(),
                 [](const unsigned char character) { return std::tolower(character); });
  if (mode == "noise") return EffectMode::kNoise;
  if (mode == "bnr2") return EffectMode::kBnr2;
  if (mode == "room_echo") return EffectMode::kRoomEcho;
  if (mode == "noise_room_echo") return EffectMode::kNoiseRoomEcho;
  if (mode == "studio_voice") return EffectMode::kStudioVoice;
  throw std::invalid_argument("Unknown NVIDIA AFX effect mode: " + value);
}

EffectSpec resolve_effect(const std::filesystem::path& sdk_root,
                          const std::string& architecture,
                          const EffectMode mode) {
  std::string feature;
  std::string selector;
  std::string model_name;
  std::string display_name;
  bool version_2 = false;
  bool supports_vad = false;
  bool vad = false;
  bool intensity = true;
  switch (mode) {
    case EffectMode::kNoise:
      feature = "denoiser";
      selector = "denoiser";
      model_name = "denoiser_48k.trtpkg";
      display_name = "Noise Removal";
      supports_vad = true;
      break;
    case EffectMode::kBnr2:
      feature = "denoiser";
      selector = "denoiser";
      model_name = "denoiser_v2_48k.trtpkg";
      display_name = "BNR 2.0";
      version_2 = true;
      supports_vad = true;
      vad = true;
      break;
    case EffectMode::kRoomEcho:
      feature = "dereverb";
      selector = "dereverb";
      model_name = "dereverb_48k.trtpkg";
      display_name = "Room Echo Removal";
      break;
    case EffectMode::kNoiseRoomEcho:
      feature = "dereverb_denoiser";
      selector = "dereverb_denoiser";
      model_name = "dereverb_denoiser_48k.trtpkg";
      display_name = "Noise + Room Echo";
      supports_vad = true;
      break;
    case EffectMode::kStudioVoice:
      feature = "studio_voice";
      selector = "studio_voice_low_latency";
      model_name = "studio_voice_low_latency_48k.trtpkg";
      display_name = "Studio Voice";
      intensity = false;
      break;
  }
  auto model = sdk_root / "features" / feature / "models" / architecture / model_name;
  if (!std::filesystem::exists(model)) {
    throw std::runtime_error(display_name + " model not found: " + model.string());
  }
  return {mode, selector, display_name, std::filesystem::canonical(model),
          version_2, supports_vad, vad, intensity};
}

AfxDenoiser::AfxDenoiser(const EffectSpec& effect, const float intensity,
                         const unsigned frame_samples)
    : supports_intensity_(effect.supports_intensity), frame_samples_(frame_samples) {
  try {
    require(NvAFX_CreateEffect(effect.selector.c_str(), &handle_), "Create audio effect");
    // The Linux AFX device selector rejects GeForce cards, so retain CUDA device 0.
    require(NvAFX_SetU32(handle_, NVAFX_PARAM_USE_DEFAULT_GPU, 0), "Select GPU");
    require(NvAFX_SetU32(handle_, NVAFX_PARAM_INPUT_SAMPLE_RATE, kSampleRate), "Set 48 kHz");
    require(NvAFX_SetU32(handle_, NVAFX_PARAM_NUM_STREAMS, 1), "Set one stream");
    if (effect.effect_version_2) {
      require(NvAFX_SetU32(handle_, NVAFX_PARAM_EFFECT_VERSION, kEffectVersion), "Enable BNR 2.0");
    }
    if (effect.enable_vad) {
      require(NvAFX_SetU32(handle_, NVAFX_PARAM_ENABLE_VAD, 1), "Enable VAD");
    }
    require(NvAFX_SetU32(handle_, NVAFX_PARAM_NUM_SAMPLES_PER_INPUT_FRAME, frame_samples_),
            "Set input frame size");
    const std::string model_path = effect.model.string();
    const char* models[] = {model_path.c_str()};
    require(NvAFX_SetStringList(handle_, NVAFX_PARAM_MODEL_PATH, models, 1), "Set model");
    require(NvAFX_Load(handle_), "Load audio effect");
    if (supports_intensity_) set_intensity(intensity);
  } catch (...) {
    if (handle_ != nullptr) NvAFX_DestroyEffect(handle_);
    handle_ = nullptr;
    throw;
  }
}

AfxDenoiser::~AfxDenoiser() {
  if (handle_ != nullptr) NvAFX_DestroyEffect(handle_);
}

void AfxDenoiser::set_intensity(const float intensity) {
  if (!supports_intensity_) return;
  if (intensity < 0.0F || intensity > 1.0F) {
    throw std::invalid_argument("AFX intensity must be between 0.0 and 1.0");
  }
  require(NvAFX_SetFloat(handle_, NVAFX_PARAM_INTENSITY_RATIO, intensity), "Set intensity");
}

void AfxDenoiser::process(const std::span<const float> input,
                          const std::span<float> output) {
  if (input.size() != frame_samples_ || output.size() != frame_samples_) {
    throw std::invalid_argument("AFX frame does not match the configured size");
  }
  const float* inputs[] = {input.data()};
  float* outputs[] = {output.data()};
  require(NvAFX_Run(handle_, inputs, outputs, frame_samples_, 1), "Process NVIDIA AFX frame");
}

}  // namespace linux_broadcast
