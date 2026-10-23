cmake_minimum_required(VERSION 3.22)
project(projectm_spike LANGUAGES C CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

set(ROOT_DIR "${CMAKE_CURRENT_SOURCE_DIR}/../../..")

find_package(OpenGL REQUIRED)

set(GLEW_ROOT "${ROOT_DIR}/vendor/glew/glew-2.2.0")
find_package(GLEW REQUIRED)

add_executable(test_app_windows test_app_windows.cpp)

target_include_directories(test_app_windows PRIVATE
    ${ROOT_DIR}/src/api/include
    ${ROOT_DIR}/build/projectm/src/api/include
    ${ROOT_DIR}
    ${GLEW_INCLUDE_DIRS}
)

target_link_libraries(test_app_windows PRIVATE
    ${ROOT_DIR}/build/projectm/src/libprojectM/Release/projectM-4.lib
    ${GLEW_LIBRARIES}
    OpenGL::GL
    winmm
    ole32
    gdi32
    user32
)

# Copy projectM-4.dll and glew32.dll next to the output executable
add_custom_command(TARGET test_app_windows POST_BUILD
    COMMAND ${CMAKE_COMMAND} -E copy_if_different
        "${ROOT_DIR}/build/projectm/src/libprojectM/Release/projectM-4.dll"
        "$<TARGET_FILE_DIR:test_app_windows>"
    COMMAND ${CMAKE_COMMAND} -E copy_if_different
        "${GLEW_ROOT}/bin/Release/x64/glew32.dll"
        "$<TARGET_FILE_DIR:test_app_windows>"
)
