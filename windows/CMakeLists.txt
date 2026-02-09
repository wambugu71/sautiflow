cmake_minimum_required(VERSION 3.14)
project(miniaudiodart_windows LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

add_library(audio_engine SHARED
  ../audio_engine.cpp
)

target_include_directories(audio_engine PRIVATE
  ${CMAKE_CURRENT_SOURCE_DIR}/..
)

target_compile_definitions(audio_engine PRIVATE
  NOMINMAX
  WIN32_LEAN_AND_MEAN
)

# NOTE: Disabled for Windows plugin builds by default.
# On many setups CMake picks MSYS2/MinGW curl headers, which are incompatible
# with MSVC and cause compile failures in stdlib/stdio headers.
# If you want native URL streaming on Windows, use an MSVC-compatible curl
# package (for example via vcpkg) and wire it explicitly.

target_link_libraries(audio_engine PRIVATE
  winmm
)

set_target_properties(audio_engine PROPERTIES
  OUTPUT_NAME "audio_engine"
)

# Required by Flutter FFI plugin packaging.
set(miniaudiodart_bundled_libraries
  $<TARGET_FILE:audio_engine>
  PARENT_SCOPE
)
