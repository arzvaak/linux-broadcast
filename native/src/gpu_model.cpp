#include "gpu_model.hpp"

#include <array>
#include <cerrno>
#include <cstdio>
#include <cstdlib>
#include <stdexcept>
#include <string>

namespace linux_broadcast {

GpuModelTarget target_for_compute_capability(const int major, const int minor) {
  if (major == 7 && minor == 5) return {"sm_75"};
  if (major == 8 && minor == 6) return {"sm_86"};
  if (major == 8 && minor == 9) return {"sm_89"};
  if (major == 12 && minor == 0) return {"sm_120"};
  throw std::runtime_error("No NVIDIA AFX package mapping for compute capability " +
                           std::to_string(major) + "." + std::to_string(minor));
}

GpuModelTarget detect_gpu_target() {
  std::string command = "nvidia-smi ";
  if (const char* configured = std::getenv("LINUX_BROADCAST_GPU_INDEX");
      configured != nullptr && *configured != '\0') {
    char* end = nullptr;
    errno = 0;
    const unsigned long index = std::strtoul(configured, &end, 10);
    if (errno != 0 || end == configured || *end != '\0') {
      throw std::runtime_error("Invalid LINUX_BROADCAST_GPU_INDEX");
    }
    command += "--id=" + std::to_string(index) + " ";
  }
  command += "--query-gpu=compute_cap --format=csv,noheader,nounits 2>/dev/null";
  std::array<char, 128> buffer{};
  std::string output;
  FILE* pipe = popen(command.c_str(), "r");
  if (pipe == nullptr) throw std::runtime_error("Failed to start nvidia-smi");
  while (fgets(buffer.data(), static_cast<int>(buffer.size()), pipe) != nullptr) {
    output += buffer.data();
  }
  const int status = pclose(pipe);
  if (status != 0) throw std::runtime_error("nvidia-smi failed while detecting the GPU");
  int major = -1;
  int minor = -1;
  if (std::sscanf(output.c_str(), "%d.%d", &major, &minor) != 2) {
    throw std::runtime_error("Could not detect NVIDIA compute capability");
  }
  return target_for_compute_capability(major, minor);
}

std::filesystem::path resolve_bnr2_model(const std::filesystem::path& sdk_root,
                                         const GpuModelTarget& target) {
  const auto model = sdk_root / "features" / "denoiser" / "models" /
                     target.sm_directory / "denoiser_v2_48k.trtpkg";
  if (!std::filesystem::exists(model)) {
    throw std::runtime_error("BNR 2.0 model not found: " + model.string());
  }
  return std::filesystem::canonical(model);
}

}  // namespace linux_broadcast
