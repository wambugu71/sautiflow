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
message(STATUS "FOUND ROOT_DIR: ${ROOT_DIR}")

if(WIN32)
    set(GLEW_ROOT "${ROOT_DIR}/vendor/glew/glew-2.2.0")
    set(GLEW_INCLUDE_DIR "${GLEW_ROOT}/include" CACHE PATH "" FORCE)
    set(GLEW_LIBRARY "${GLEW_ROOT}/lib/Release/x64/glew32.lib" CACHE FILEPATH "" FORCE)
    set(GLEW_SHARED_LIBRARY_RELEASE "${GLEW_ROOT}/lib/Release/x64/glew32.lib" CACHE FILEPATH "" FORCE)
endif()

if(NOT TARGET projectM)
    set(ENABLE_INSTALL OFF CACHE BOOL "" FORCE)
    set(ENABLE_PLAYLIST OFF CACHE BOOL "" FORCE)
    set(ENABLE_SDL_UI OFF CACHE BOOL "" FORCE)
    set(BUILD_TESTING OFF CACHE BOOL "" FORCE)
    set(BUILD_DOCS OFF CACHE BOOL "" FORCE)
    set(BUILD_SHARED_LIBS OFF CACHE BOOL "" FORCE)

    add_subdirectory(${ROOT_DIR} ${CMAKE_CURRENT_BINARY_DIR}/pm EXCLUDE_FROM_ALL)
endif()

add_library(projectm_visualizer SHARED
    pmvis.cpp
)

set_target_properties(projectm_visualizer PROPERTIES
    PUBLIC_HEADER pmvis.h
    OUTPUT_NAME "projectm_visualizer"
    C_VISIBILITY_PRESET hidden
    CXX_VISIBILITY_PRESET hidden
    VISIBILITY_INLINES_HIDDEN YES
)

if(MSVC)
    target_compile_options(projectm_visualizer PRIVATE
        $<$<CONFIG:Release>:/O2>
        $<$<CONFIG:Release>:/Oi>
        $<$<CONFIG:Release>:/Ot>
        $<$<CONFIG:Release>:/fp:fast>
        $<$<CONFIG:Release>:/Gw>
        $<$<CONFIG:Release>:/Gy>
    )
    target_link_options(projectm_visualizer PRIVATE
        $<$<CONFIG:Release>:/OPT:REF>
        $<$<CONFIG:Release>:/OPT:ICF>
    )
else()
    target_compile_options(projectm_visualizer PRIVATE
        $<$<CONFIG:Release>:-O3>
        $<$<CONFIG:Release>:-ffast-math>
        $<$<CONFIG:Release>:-fno-math-errno>
        $<$<CONFIG:Release>:-ffunction-sections>
        $<$<CONFIG:Release>:-fdata-sections>
    )
    if(NOT APPLE)
        target_link_options(projectm_visualizer PRIVATE $<$<CONFIG:Release>:-Wl,--gc-sections>)
    else()
        target_link_options(projectm_visualizer PRIVATE $<$<CONFIG:Release>:-Wl,-dead_strip>)
    endif()
endif()

target_compile_definitions(projectm_visualizer PUBLIC DART_SHARED_LIB)

target_include_directories(projectm_visualizer PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}
    ${ROOT_DIR}/src/api/include
    ${CMAKE_CURRENT_BINARY_DIR}/pm/src/api/include
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
        projectM
        ${GLEW_LIBRARIES}
        OpenGL::GL
        winmm
        ole32
        gdi32
        user32
    )

    # Copy glew32.dll alongside the built plugin dll
    add_custom_command(TARGET projectm_visualizer POST_BUILD
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
