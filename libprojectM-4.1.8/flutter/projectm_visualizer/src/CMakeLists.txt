cmake_minimum_required(VERSION 3.20)

project(projectm_visualizer VERSION 4.1.8 LANGUAGES C CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# Resolve real path in case CMAKE_CURRENT_SOURCE_DIR is inside Flutter's ephemeral .plugin_symlinks
get_filename_component(CURRENT_REAL_DIR "${CMAKE_CURRENT_SOURCE_DIR}" REALPATH)

set(ROOT_DIR "")

# 1. Check direct candidates from environment or known relative project layouts
set(CANDIDATE_SEARCH_DIRS
    "$ENV{LIBPROJECTM_DIR}"
    "$ENV{PROJECTM_ROOT}"
    "${CMAKE_CURRENT_LIST_DIR}/../../.."
    "${CURRENT_REAL_DIR}/../../.."
)

foreach(CANDIDATE ${CANDIDATE_SEARCH_DIRS})
    if(CANDIDATE AND EXISTS "${CANDIDATE}/src/libprojectM/ProjectM.cpp")
        set(ROOT_DIR "${CANDIDATE}")
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
message(STATUS "FOUND ROOT_DIR: ${ROOT_DIR}")

if (ANDROID OR (UNIX AND NOT APPLE) OR APPLE)
    if(NOT TARGET projectM)
        set(ENABLE_INSTALL OFF CACHE BOOL "" FORCE)
        set(ENABLE_PLAYLIST OFF CACHE BOOL "" FORCE)
        set(ENABLE_SDL_UI OFF CACHE BOOL "" FORCE)
        set(BUILD_TESTING OFF CACHE BOOL "" FORCE)
        set(BUILD_DOCS OFF CACHE BOOL "" FORCE)
        set(BUILD_SHARED_LIBS OFF CACHE BOOL "" FORCE)

        add_subdirectory(${ROOT_DIR} ${CMAKE_CURRENT_BINARY_DIR}/pm EXCLUDE_FROM_ALL)
    endif()
endif()

add_library(projectm_visualizer SHARED
    pmvis.cpp
)

set_target_properties(projectm_visualizer PROPERTIES
    PUBLIC_HEADER pmvis.h
    OUTPUT_NAME "projectm_visualizer"
)

target_compile_definitions(projectm_visualizer PUBLIC DART_SHARED_LIB)

target_include_directories(projectm_visualizer PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}
    ${ROOT_DIR}/src/api/include
    ${ROOT_DIR}/build/projectm/src/api/include
    ${ROOT_DIR}
)

if (WIN32)
    set(GLEW_ROOT "${ROOT_DIR}/vendor/glew/glew-2.2.0")
    set(GLEW_INCLUDE_DIRS "${GLEW_ROOT}/include")
    set(GLEW_LIBRARIES "${GLEW_ROOT}/lib/Release/x64/glew32.lib")

    target_include_directories(projectm_visualizer PRIVATE
        ${GLEW_INCLUDE_DIRS}
    )

    find_package(OpenGL REQUIRED)

    target_link_libraries(projectm_visualizer PRIVATE
        ${ROOT_DIR}/build/projectm/src/libprojectM/Release/projectM-4.lib
        ${GLEW_LIBRARIES}
        OpenGL::GL
        winmm
        ole32
        gdi32
        user32
    )

    # Copy projectM-4.dll and glew32.dll alongside the built plugin dll
    add_custom_command(TARGET projectm_visualizer POST_BUILD
        COMMAND ${CMAKE_COMMAND} -E copy_if_different
            "${ROOT_DIR}/build/projectm/src/libprojectM/Release/projectM-4.dll"
            "$<TARGET_FILE_DIR:projectm_visualizer>"
        COMMAND ${CMAKE_COMMAND} -E copy_if_different
            "${GLEW_ROOT}/bin/Release/x64/glew32.dll"
            "$<TARGET_FILE_DIR:projectm_visualizer>"
    )
elseif (ANDROID)
    find_library(EGL_LIB EGL)
    find_library(GLES3_LIB GLESv3)
    find_library(ANDROID_LIB android)
    find_library(LOG_LIB log)

    target_link_libraries(projectm_visualizer PRIVATE
        projectM
        ${EGL_LIB}
        ${GLES3_LIB}
        ${ANDROID_LIB}
        ${LOG_LIB}
    )
    target_link_options(projectm_visualizer PRIVATE "-Wl,-z,max-page-size=16384")
elseif (APPLE)
    if (IOS OR CMAKE_SYSTEM_NAME STREQUAL "iOS")
        target_link_libraries(projectm_visualizer PRIVATE
            projectM
            "-framework OpenGLES"
            "-framework CoreFoundation"
            "-framework CoreAudio"
            "-framework AudioToolbox"
            "-framework AVFoundation"
            pthread
        )
    else()
        find_package(OpenGL REQUIRED)
        target_link_libraries(projectm_visualizer PRIVATE
            projectM
            "-framework OpenGL"
            "-framework CoreFoundation"
            "-framework CoreAudio"
            "-framework AudioUnit"
            pthread
        )
    endif()
else()
    find_package(OpenGL REQUIRED)
    find_library(EGL_LIB EGL)
    target_link_libraries(projectm_visualizer PRIVATE
        projectM
        OpenGL::GL
        ${EGL_LIB}
        pthread
        ${CMAKE_DL_LIBS}
        m
    )
endif()
