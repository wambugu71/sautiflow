cmake_minimum_required(VERSION 3.14)

set(PROJECT_NAME "projectm_visualizer")
project(${PROJECT_NAME} LANGUAGES C CXX)

# This value is used when generating builds using this plugin, so it must
# not be changed.
set(PLUGIN_NAME "projectm_visualizer_plugin")

# Invoke the build for native code shared with other platforms.
add_subdirectory("${CMAKE_CURRENT_SOURCE_DIR}/../src" "${CMAKE_CURRENT_BINARY_DIR}/shared")

# List of absolute paths to libraries that should be bundled with the plugin.
set(projectm_visualizer_bundled_libraries
  $<TARGET_FILE:projectm_visualizer>
  PARENT_SCOPE
)
