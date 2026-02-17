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

# Optional native URL byte-streaming via libcurl (OFF by default on Windows).
# Enable only when using an MSVC-compatible curl (e.g. vcpkg toolchain).
option(MINIAUDIODART_ENABLE_CURL "Enable native URL streaming via libcurl" OFF)
if(MINIAUDIODART_ENABLE_CURL)
  find_package(CURL REQUIRED)
  target_compile_definitions(audio_engine PRIVATE AE_ENABLE_CURL=1)
  target_include_directories(audio_engine PRIVATE ${CURL_INCLUDE_DIRS})
  target_link_libraries(audio_engine PRIVATE ${CURL_LIBRARIES})
endif()

target_link_libraries(audio_engine PRIVATE
  winmm
)

set_target_properties(audio_engine PROPERTIES
  OUTPUT_NAME "sautiflow"
)

# Required by Flutter FFI plugin packaging.
set(sautiflow_bundled_libraries
  $<TARGET_FILE:audio_engine>
  PARENT_SCOPE
)
