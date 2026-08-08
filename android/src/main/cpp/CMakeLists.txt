cmake_minimum_required(VERSION 3.10)
project(miniaudiodart_android LANGUAGES CXX C)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

file(GLOB FAAD2_SOURCES "../../../../third_party/faad2/libfaad/*.c")
file(GLOB LIBSAMPLERATE_SOURCES "../../../../third_party/libsamplerate/src/*.c")
file(GLOB VIPER_EFFECT_SRCS
  "../../../../ViPERDSP/viper/ViPER.cpp"
  "../../../../ViPERDSP/viper/effects/*.cpp"
  "../../../../ViPERDSP/viper/utils/*.cpp"
  "../../../../ViPERDSP/viper/utils/*.c"
)

add_library(audio_engine SHARED
  ../../../../audio_engine.cpp
  ../../../../mp4_aac_decoder.cpp
  ${VIPER_EFFECT_SRCS}
  ${FAAD2_SOURCES}
  ${LIBSAMPLERATE_SOURCES}
)

target_include_directories(audio_engine PRIVATE
  ../../../../
  ../../../../third_party
  ../../../../third_party/faad2/include
  ../../../../third_party/faad2/libfaad
  ../../../../third_party/libsamplerate/include
  ../../../../ViPERDSP/include
  ../../../../ViPERDSP/viper
  ../../../../ViPERDSP/viper/effects
  ../../../../ViPERDSP/viper/utils
)

target_compile_definitions(audio_engine PRIVATE
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
)

if(CMAKE_CXX_COMPILER_ID MATCHES "Clang|GNU")
  target_compile_options(audio_engine PRIVATE $<$<NOT:$<CONFIG:Debug>>:-O3 -ffast-math -ftree-vectorize>)
  if(ANDROID_ABI STREQUAL "armeabi-v7a")
    target_compile_options(audio_engine PRIVATE -mfpu=neon)
  endif()
endif()

# Suppress harmless warnings from third-party FAAD2 C code
set_source_files_properties(${FAAD2_SOURCES} PROPERTIES
  COMPILE_FLAGS "-Wno-everything"
)

find_library(log-lib log)

# IMPORTANT:
# Avoid find_package(CURL) in Android plugin builds. It can trigger repeated
# CMake regeneration loops on some NDK/AGP setups (ninja: build.ninja dirty).
# If you need native URL streaming on Android, pass explicit variables from
# Gradle/CMake args instead:
#   -DMINIAUDIODART_ENABLE_CURL=ON
#   -DMINIAUDIODART_CURL_INCLUDE_DIR=<path>
#   -DMINIAUDIODART_CURL_LIBRARY=<path-to-libcurl>
# Optional convenience:
#   -DMINIAUDIODART_CURL_LIBRARY_DIR=<dir-containing-abi-folders>
# If MINIAUDIODART_CURL_LIBRARY is omitted, CMake will attempt to resolve
# one of:
#   <MINIAUDIODART_CURL_LIBRARY_DIR>/<ANDROID_ABI>/libcurl.a
#   <MINIAUDIODART_CURL_LIBRARY_DIR>/<ANDROID_ABI>/libcurl.so
# and fallback to:
#   <repo>/native/android/<ANDROID_ABI>/libcurl.a
#   <repo>/native/android/<ANDROID_ABI>/libcurl.so
option(MINIAUDIODART_ENABLE_CURL "Enable native URL streaming via libcurl" ON)
if(MINIAUDIODART_ENABLE_CURL)
  set(_md_repo_root "${CMAKE_CURRENT_SOURCE_DIR}/../../../../")
  set(_md_default_include_dir "${_md_repo_root}/native/android/include")
  set(_md_default_library_dir "${_md_repo_root}/native/android")

  set(_md_curl_include_dir "${MINIAUDIODART_CURL_INCLUDE_DIR}")
  set(_md_curl_library "${MINIAUDIODART_CURL_LIBRARY}")
  set(_md_curl_library_dir "${MINIAUDIODART_CURL_LIBRARY_DIR}")
  set(_md_curl_extra_libs "${MINIAUDIODART_CURL_EXTRA_LIBS}")

  if(NOT _md_curl_include_dir)
    if(EXISTS "${_md_default_include_dir}")
      set(_md_curl_include_dir "${_md_default_include_dir}")
    endif()
  endif()

  if(NOT _md_curl_library)
    if(NOT _md_curl_library_dir)
      set(_md_curl_library_dir "${_md_default_library_dir}")
    endif()

    if(ANDROID_ABI)
      set(_md_curl_abi_dir "${_md_curl_library_dir}/${ANDROID_ABI}")
      # Prefer static linking on Android plugin builds to avoid extra .so packaging.
      if(EXISTS "${_md_curl_abi_dir}/libcurl.a")
        set(_md_curl_library "${_md_curl_abi_dir}/libcurl.a")
      elseif(EXISTS "${_md_curl_abi_dir}/libcurl.so")
        set(_md_curl_library "${_md_curl_abi_dir}/libcurl.so")
      endif()
    endif()
  endif()

  if(NOT _md_curl_library)
    find_library(_md_system_curl curl)
    if(_md_system_curl)
      set(_md_curl_library "${_md_system_curl}")
    endif()
  endif()

  if(_md_curl_include_dir AND _md_curl_library)
    target_compile_definitions(audio_engine PRIVATE AE_ENABLE_CURL=1)
    target_include_directories(audio_engine PRIVATE ${_md_curl_include_dir})
    target_link_libraries(audio_engine PRIVATE ${_md_curl_library} ${_md_curl_extra_libs})
    message(STATUS "MiniAudioDart Android: native network streaming enabled (libcurl).")
  else()
    message(WARNING
      "MiniAudioDart Android: libcurl not resolved; building without native network streaming. "
      "To enable, provide MINIAUDIODART_CURL_INCLUDE_DIR and MINIAUDIODART_CURL_LIBRARY "
      "or bundle artifacts under native/android/include and native/android/<ABI>/libcurl.(so|a)."
    )
  endif()
endif()

target_link_libraries(audio_engine
  ${log-lib}
  android
  m
)

set_target_properties(audio_engine PROPERTIES
  OUTPUT_NAME "sautiflow"
)
