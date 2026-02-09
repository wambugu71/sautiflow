cmake_minimum_required(VERSION 3.10)
project(miniaudiodart_android LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

add_library(audio_engine SHARED
  ../../../../audio_engine.cpp
)

target_include_directories(audio_engine PRIVATE
  ../../../../
)

find_library(log-lib log)

target_link_libraries(audio_engine
  ${log-lib}
  android
)
