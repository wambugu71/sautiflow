# The Flutter tooling requires that developers have a version of Visual Studio
# installed that includes CMake 3.14 or later. You should not increase this
# version, as doing so will cause the plugin to fail to compile for some
# customers of the plugin.
cmake_minimum_required(VERSION 3.14)

# Project-level configuration.
set(PROJECT_NAME "projectm_visualizer")
project(${PROJECT_NAME} LANGUAGES CXX)

# Invoke the build for native code shared with the other target platforms.
# This can be changed to accommodate different builds.
add_subdirectory("${CMAKE_CURRENT_SOURCE_DIR}/../src" "${CMAKE_CURRENT_BINARY_DIR}/shared")

# Resolve real path in case CMAKE_CURRENT_SOURCE_DIR is inside Flutter's ephemeral .plugin_symlinks
get_filename_component(CURRENT_REAL_DIR "${CMAKE_CURRENT_SOURCE_DIR}" REALPATH)

set(ROOT_DIR "")

# 1. Check direct candidates from environment or known relative project layouts
set(CANDIDATE_SEARCH_DIRS
    "$ENV{LIBPROJECTM_DIR}"
    "$ENV{PROJECTM_ROOT}"
    "${CURRENT_REAL_DIR}/../../.."
    "${CMAKE_CURRENT_LIST_DIR}/../../.."
)

foreach(CANDIDATE ${CANDIDATE_SEARCH_DIRS})
    if(CANDIDATE AND EXISTS "${CANDIDATE}/src/libprojectM/ProjectM.cpp")
        get_filename_component(ROOT_DIR "${CANDIDATE}" REALPATH)
        break()
    endif()
endforeach()

# 2. Walk up directory tree from both REALPATH and syntactic paths
if(NOT ROOT_DIR)
    foreach(START_DIR ${CURRENT_REAL_DIR} ${CMAKE_CURRENT_SOURCE_DIR} ${CMAKE_CURRENT_LIST_DIR})
        set(SEARCH_DIR "${START_DIR}")
        foreach(STEP RANGE 1 12)
            if(EXISTS "${SEARCH_DIR}/src/libprojectM/ProjectM.cpp")
                set(ROOT_DIR "${SEARCH_DIR}")
                break()
            endif()
            if(EXISTS "${SEARCH_DIR}/libprojectM-4.1.8/src/libprojectM/ProjectM.cpp")
                set(ROOT_DIR "${SEARCH_DIR}/libprojectM-4.1.8")
                break()
            endif()
            get_filename_component(SEARCH_DIR "${SEARCH_DIR}/.." ABSOLUTE)
        endforeach()
        if(ROOT_DIR)
            break()
        endif()
    endforeach()
endif()

if(NOT ROOT_DIR)
    message(FATAL_ERROR "Could not find libprojectM root directory containing src/libprojectM/ProjectM.cpp (searched from ${CMAKE_CURRENT_SOURCE_DIR} and ${CURRENT_REAL_DIR})")
endif()

file(TO_CMAKE_PATH "${ROOT_DIR}" ROOT_DIR)

# List of absolute paths to libraries that should be bundled with the plugin.
# This list could contain prebuilt libraries, or libraries created by an
# external build triggered from this build file.
set(projectm_visualizer_bundled_libraries
  $<TARGET_FILE:projectm_visualizer>
  "${ROOT_DIR}/vendor/glew/glew-2.2.0/bin/Release/x64/glew32.dll"
  PARENT_SCOPE
)
