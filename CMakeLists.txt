cmake_minimum_required(VERSION 3.16)
project(audio_engine LANGUAGES CXX C)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

file(GLOB FAAD2_SOURCES "third_party/faad2/libfaad/*.c")
file(GLOB LIBSAMPLERATE_SOURCES "third_party/libsamplerate/src/*.c")
set(LIBSOXR_SOURCES
  "third_party/libsoxr/src/soxr.c"
  "third_party/libsoxr/src/data-io.c"
  "third_party/libsoxr/src/filter.c"
  "third_party/libsoxr/src/cr.c"
  "third_party/libsoxr/src/cr32.c"
  "third_party/libsoxr/src/cr32s.c"
  "third_party/libsoxr/src/cr64.c"
  "third_party/libsoxr/src/vr32.c"
  "third_party/libsoxr/src/pffft32s.c"
  "third_party/libsoxr/src/pffft-wrap.c"
  "third_party/libsoxr/src/fft4g32.c"
  "third_party/libsoxr/src/fft4g64.c"
  "third_party/libsoxr/src/dbesi0.c"
  "third_party/libsoxr/src/vr-coefs.c"
  "third_party/libsoxr/src/util32s.c"
)
file(GLOB VIPER_EFFECT_SRCS
  ViPERDSP/viper/ViPER.cpp
  ViPERDSP/viper/effects/*.cpp
  ViPERDSP/viper/utils/*.cpp
  ViPERDSP/viper/utils/*.c
)

add_library(audio_engine SHARED
  audio_engine.cpp
  mp4_aac_decoder.cpp
  ${VIPER_EFFECT_SRCS}
  ${FAAD2_SOURCES}
  ${LIBSAMPLERATE_SOURCES}
  ${LIBSOXR_SOURCES}
)

set_target_properties(audio_engine PROPERTIES
  OUTPUT_NAME "sautiflow"
)

target_include_directories(audio_engine PRIVATE 
  ${CMAKE_CURRENT_SOURCE_DIR}
  ${CMAKE_CURRENT_SOURCE_DIR}/third_party
  ${CMAKE_CURRENT_SOURCE_DIR}/third_party/faad2/include
  ${CMAKE_CURRENT_SOURCE_DIR}/third_party/faad2/libfaad
  ${CMAKE_CURRENT_SOURCE_DIR}/third_party/libsamplerate/include
  ${CMAKE_CURRENT_SOURCE_DIR}/third_party/libsoxr/include
  ${CMAKE_CURRENT_SOURCE_DIR}/third_party/libsoxr/src
  ${CMAKE_CURRENT_SOURCE_DIR}/ViPERDSP/include
  ${CMAKE_CURRENT_SOURCE_DIR}/ViPERDSP/viper
  ${CMAKE_CURRENT_SOURCE_DIR}/ViPERDSP/viper/effects
  ${CMAKE_CURRENT_SOURCE_DIR}/ViPERDSP/viper/utils
)

if(MSVC)
  target_compile_options(audio_engine PRIVATE $<$<NOT:$<CONFIG:Debug>>:/O2 /fp:fast>)
elseif(CMAKE_CXX_COMPILER_ID MATCHES "Clang|GNU")
  target_compile_options(audio_engine PRIVATE $<$<NOT:$<CONFIG:Debug>>:-O3 -ffast-math -ftree-vectorize>)
endif()

target_compile_definitions(audio_engine PRIVATE
  _USE_MATH_DEFINES
  HAVE_INTTYPES_H=1
  HAVE_MEMCPY=1
  HAVE_STRING_H=1
  HAVE_STDBOOL_H=1
  HAVE_STRINGS_H=1
  HAVE_SYS_TYPES_H=1
  PACKAGE="libsamplerate"
  VERSION="0.2.2"
  PACKAGE_VERSION="2.11.1"
  ENABLE_SINC_BEST_CONVERTER=1
  ENABLE_SINC_MEDIUM_CONVERTER=1
  ENABLE_SINC_FAST_CONVERTER=1
  SOXR_LIB=1
)

if (WIN32)
  target_compile_definitions(audio_engine PRIVATE NOMINMAX WIN32_LEAN_AND_MEAN)
  # Disabled by default on Windows because CMake may resolve MSYS2/MinGW curl
  # headers, which are not MSVC-compatible.
  target_link_libraries(audio_engine PRIVATE winmm)
elseif(APPLE)
  find_library(COREAUDIO_FRAMEWORK CoreAudio)
  find_library(AUDIOTOOLBOX_FRAMEWORK AudioToolbox)
  find_package(CURL QUIET)
  if(CURL_FOUND)
    target_compile_definitions(audio_engine PRIVATE AE_ENABLE_CURL=1)
    target_link_libraries(audio_engine PRIVATE ${CURL_LIBRARIES})
    target_include_directories(audio_engine PRIVATE ${CURL_INCLUDE_DIRS})
  endif()
  target_link_libraries(audio_engine PRIVATE ${COREAUDIO_FRAMEWORK} ${AUDIOTOOLBOX_FRAMEWORK})
elseif(UNIX)
  find_package(CURL QUIET)
  if(CURL_FOUND)
    target_compile_definitions(audio_engine PRIVATE AE_ENABLE_CURL=1)
    target_link_libraries(audio_engine PRIVATE ${CURL_LIBRARIES})
    target_include_directories(audio_engine PRIVATE ${CURL_INCLUDE_DIRS})
  endif()
  target_link_libraries(audio_engine PRIVATE pthread dl m)
endif()

add_executable(test_cases test/auto_sr_disable_cases_test.cpp)
target_link_libraries(test_cases PRIVATE audio_engine)
target_include_directories(test_cases PRIVATE ${CMAKE_CURRENT_SOURCE_DIR})

