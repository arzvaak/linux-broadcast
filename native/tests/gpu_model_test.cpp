#include "gpu_model.hpp"
#include <iostream>
#include <stdexcept>

int main() {
  using linux_broadcast::target_for_compute_capability;
  if (target_for_compute_capability(7, 5).sm_directory != "sm_75") return 1;
  if (target_for_compute_capability(8, 6).sm_directory != "sm_86") return 1;
  if (target_for_compute_capability(8, 9).sm_directory != "sm_89") return 1;
  if (target_for_compute_capability(12, 0).sm_directory != "sm_120") return 1;
  bool rejected = false;
  try { static_cast<void>(target_for_compute_capability(8, 0)); }
  catch (const std::runtime_error&) { rejected = true; }
  if (!rejected) return 1;
  std::cout << "GPU model mapping tests passed\n";
}
