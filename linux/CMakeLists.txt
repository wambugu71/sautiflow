cmake_minimum_required(VERSION 3.10)
project(miniaudiodart_linux LANGUAGES CXX C)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

file(GLOB FAAD2_SOURCES "../third_party/faad2/libfaad/*.c")
file(GLOB LIBSAMPLERATE_SOURCES "../third_party/libsamplerate/src/*.c")
file(GLOB VIPER_EFFECT_SRCS
  "../ViPERDSP/viper/ViPER.cpp"
  "../ViPERDSP/viper/effects/*.cpp"
  "../ViPERDSP/viper/utils/*.cpp"
  "../ViPERDSP/viper/utils/*.c"
)

add_library(audio_engine SHARED
  ../audio_engine.cpp
  ../mp4_aac_decoder.cpp
  ${VIPER_EFFECT_SRCS}
  ${FAAD2_SOURCES}
  ${LIBSAMPLERATE_SOURCES}
)

target_include_directories(audio_engine PRIVATE
  ${CMAKE_CURRENT_SOURCE_DIR}/..
  ${CMAKE_CURRENT_SOURCE_DIR}/../third_party
  ${CMAKE_CURRENT_SOURCE_DIR}/../third_party/faad2/include
  ${CMAKE_CURRENT_SOURCE_DIR}/../third_party/faad2/libfaad
  ${CMAKE_CURRENT_SOURCE_DIR}/../third_party/libsamplerate/include
  ${CMAKE_CURRENT_SOURCE_DIR}/../ViPERDSP/include
  ${CMAKE_CURRENT_SOURCE_DIR}/../ViPERDSP/viper
  ${CMAKE_CURRENT_SOURCE_DIR}/../ViPERDSP/viper/effects
  ${CMAKE_CURRENT_SOURCE_DIR}/../ViPERDSP/viper/utils
)

target_compile_definitions(audio_engine PRIVATE
  PACKAGE_VERSION="2.11.1"
  PACKAGE="libsamplerate"
  VERSION="0.2.2"
  HAVE_INTTYPES_H=1
  HAVE_MEMCPY=1
  HAVE_STRING_H=1
  HAVE_STDBOOL_H=1
  HAVE_STRINGS_H=1
  HAVE_SYS_TYPES_H=1
)

find_package(CURL QUIET)
if(CURL_FOUND)
  target_compile_definitions(audio_engine PRIVATE AE_ENABLE_CURL=1)
  target_link_libraries(audio_engine PRIVATE ${CURL_LIBRARIES})
  target_include_directories(audio_engine PRIVATE ${CURL_INCLUDE_DIRS})
endif()

target_link_libraries(audio_engine PRIVATE
  pthread
  dl
  m
)

set_target_properties(audio_engine PROPERTIES
  OUTPUT_NAME "sautiflow"
)

# Required by Flutter FFI plugin packaging.
set(sautiflow_bundled_libraries
  $<TARGET_FILE:audio_engine>
  PARENT_SCOPE
)
