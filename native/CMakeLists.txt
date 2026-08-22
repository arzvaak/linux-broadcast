cmake_minimum_required(VERSION 3.20)
project(linux_broadcast_native VERSION 0.1.0 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

if(NOT AFX_SDK_ROOT AND DEFINED ENV{AFX_SDK_ROOT})
  set(AFX_SDK_ROOT "$ENV{AFX_SDK_ROOT}")
endif()
if(NOT AFX_SDK_ROOT)
  message(FATAL_ERROR "Set AFX_SDK_ROOT to the extracted NVIDIA AFX 2.x SDK")
endif()

set(AFX_CORE_INCLUDE "${AFX_SDK_ROOT}/nvafx/include")
set(AFX_CORE_LIBRARY "${AFX_SDK_ROOT}/nvafx/lib/libnv_audiofx.so")
set(AFX_DENOISER_ROOT "${AFX_SDK_ROOT}/features/denoiser")
foreach(required "${AFX_CORE_INCLUDE}/nvAudioEffects.h" "${AFX_CORE_LIBRARY}"
                 "${AFX_DENOISER_ROOT}/include/denoiser.h")
  if(NOT EXISTS "${required}")
    message(FATAL_ERROR "Required AFX component not found: ${required}")
  endif()
endforeach()

file(GLOB AFX_DENOISER_LIBRARIES "${AFX_DENOISER_ROOT}/lib/*.so")
if(NOT AFX_DENOISER_LIBRARIES)
  message(FATAL_ERROR "No denoiser library found under ${AFX_DENOISER_ROOT}/lib")
endif()

add_executable(linux-broadcast-afx src/main.cpp src/afx_denoiser.cpp src/gpu_model.cpp)
target_include_directories(linux-broadcast-afx PRIVATE src "${AFX_CORE_INCLUDE}"
  "${AFX_DENOISER_ROOT}/include")
target_link_libraries(linux-broadcast-afx PRIVATE "${AFX_CORE_LIBRARY}")
target_compile_options(linux-broadcast-afx PRIVATE -Wall -Wextra -Wpedantic -Werror)
set_target_properties(linux-broadcast-afx PROPERTIES
  SKIP_BUILD_RPATH TRUE)

add_library(linux-broadcast-afx-ladspa SHARED
  src/ladspa_plugin.cpp src/afx_denoiser.cpp src/gpu_model.cpp)
target_include_directories(linux-broadcast-afx-ladspa PRIVATE src "${AFX_CORE_INCLUDE}"
  "${AFX_DENOISER_ROOT}/include")
target_link_libraries(linux-broadcast-afx-ladspa PRIVATE "${AFX_CORE_LIBRARY}" ${CMAKE_DL_LIBS})
target_compile_options(linux-broadcast-afx-ladspa PRIVATE -Wall -Wextra -Wpedantic -Werror)
set_target_properties(linux-broadcast-afx-ladspa PROPERTIES
  OUTPUT_NAME "linux_broadcast_afx_ladspa"
  PREFIX "lib"
  SKIP_BUILD_RPATH TRUE)

install(TARGETS linux-broadcast-afx linux-broadcast-afx-ladspa
  RUNTIME DESTINATION bin
  LIBRARY DESTINATION lib/linux-broadcast)

include(CTest)
if(BUILD_TESTING)
  add_executable(gpu-model-test tests/gpu_model_test.cpp src/gpu_model.cpp)
  target_include_directories(gpu-model-test PRIVATE src)
  target_compile_options(gpu-model-test PRIVATE -Wall -Wextra -Wpedantic -Werror)
  add_test(NAME gpu-model-test COMMAND gpu-model-test)
endif()
