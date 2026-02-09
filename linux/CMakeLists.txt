cmake_minimum_required(VERSION 3.10)
project(miniaudiodart_linux LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

add_library(audio_engine SHARED
  ../audio_engine.cpp
)

target_include_directories(audio_engine PRIVATE
  ${CMAKE_CURRENT_SOURCE_DIR}/..
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
  OUTPUT_NAME "audio_engine"
)

# Required by Flutter FFI plugin packaging.
set(miniaudiodart_bundled_libraries
  $<TARGET_FILE:audio_engine>
  PARENT_SCOPE
)
