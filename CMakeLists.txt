cmake_minimum_required(VERSION 3.16)
project(audio_engine LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

file(GLOB VIPER_EFFECT_SRCS
  ViPERDSP/viper/ViPER.cpp
  ViPERDSP/viper/effects/*.cpp
  ViPERDSP/viper/utils/*.cpp
  ViPERDSP/viper/utils/*.c
)

add_library(audio_engine SHARED audio_engine.cpp ${VIPER_EFFECT_SRCS})

set_target_properties(audio_engine PROPERTIES
  OUTPUT_NAME "sautiflow"
)

target_include_directories(audio_engine PRIVATE 
  ${CMAKE_CURRENT_SOURCE_DIR}
  ${CMAKE_CURRENT_SOURCE_DIR}/ViPERDSP/include
  ${CMAKE_CURRENT_SOURCE_DIR}/ViPERDSP/viper
  ${CMAKE_CURRENT_SOURCE_DIR}/ViPERDSP/viper/effects
  ${CMAKE_CURRENT_SOURCE_DIR}/ViPERDSP/viper/utils
)

if(MSVC)
  target_compile_options(audio_engine PRIVATE /O2 /fp:fast)
elseif(CMAKE_CXX_COMPILER_ID MATCHES "Clang|GNU")
  target_compile_options(audio_engine PRIVATE -O3 -ffast-math -ftree-vectorize)
endif()

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
