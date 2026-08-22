#pragma once

#include <filesystem>
#include <string>

namespace linux_broadcast {

struct GpuModelTarget {
  std::string sm_directory;
};

GpuModelTarget target_for_compute_capability(int major, int minor);
GpuModelTarget detect_gpu_target();
std::filesystem::path resolve_bnr2_model(const std::filesystem::path& sdk_root,
                                         const GpuModelTarget& target);

}  // namespace linux_broadcast
