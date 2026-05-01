cmake_minimum_required(VERSION 3.14)
project(miniaudiodart_windows LANGUAGES CXX C)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

set(CMAKE_C_STANDARD 11)
set(CMAKE_C_STANDARD_REQUIRED ON)

file(GLOB FAAD2_SOURCES "../third_party/faad2/libfaad/*.c")
file(GLOB LIBSAMPLERATE_SOURCES "../third_party/libsamplerate/src/*.c")

add_library(audio_engine SHARED
  ../audio_engine.cpp
  ../mp4_aac_decoder.cpp
  ${FAAD2_SOURCES}
  ${LIBSAMPLERATE_SOURCES}
)

target_include_directories(audio_engine PRIVATE
  ${CMAKE_CURRENT_SOURCE_DIR}/..
  ${CMAKE_CURRENT_SOURCE_DIR}/../third_party
  ${CMAKE_CURRENT_SOURCE_DIR}/../third_party/faad2/include
  ${CMAKE_CURRENT_SOURCE_DIR}/../third_party/faad2/libfaad
  ${CMAKE_CURRENT_SOURCE_DIR}/../third_party/libsamplerate/include
)

target_compile_definitions(audio_engine PRIVATE
  NOMINMAX
  WIN32_LEAN_AND_MEAN
  PACKAGE_VERSION="2.11.1"
  HAVE_INTTYPES_H=1
  HAVE_MEMCPY=1
  HAVE_STRING_H=1
  HAVE_STDBOOL_H=1
  HAVE_STRINGS_H=1
  HAVE_SYS_TYPES_H=1
  PACKAGE="libsamplerate"
  VERSION="0.2.2"
)

# Suppress harmless warnings from third-party FAAD2 C code
if(MSVC)
  # /FS forces synchronous PDB writes, preventing C1041 errors in parallel builds
  target_compile_options(audio_engine PRIVATE /FS /std:c11)
  set_source_files_properties(${FAAD2_SOURCES} PROPERTIES
    COMPILE_FLAGS "/wd4100 /wd4244 /wd4267 /wd4701 /wd4706"
  )
endif()

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
