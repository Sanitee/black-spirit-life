cmake_minimum_required(VERSION 3.14)
project(window_frame_regression LANGUAGES CXX)
if(NOT WIN32)
  message(FATAL_ERROR "This regression requires native Windows.")
endif()
set(BSL_REPO_ROOT "${CMAKE_CURRENT_LIST_DIR}/../.." CACHE PATH "BS Life repository root")
get_filename_component(BSL_REPO_ROOT "${BSL_REPO_ROOT}" ABSOLUTE)
set(FLUTTER_EPHEMERAL "${BSL_REPO_ROOT}/windows/flutter/ephemeral" CACHE PATH
  "Existing Flutter engine artifacts; can be shared with a read-only source witness")
if(NOT EXISTS "${FLUTTER_EPHEMERAL}/flutter_windows.dll.lib")
  message(FATAL_ERROR "Run Flutter Windows configuration first; real Flutter import library required.")
endif()
add_executable(window_frame_test window_frame_test.cpp
  "${BSL_REPO_ROOT}/windows/runner/win32_window.cpp")
target_compile_features(window_frame_test PRIVATE cxx_std_17)
target_compile_definitions(window_frame_test PRIVATE NOMINMAX UNICODE _UNICODE)
target_include_directories(window_frame_test PRIVATE
  "${BSL_REPO_ROOT}/windows/runner" "${FLUTTER_EPHEMERAL}")
target_link_libraries(window_frame_test PRIVATE
  "${FLUTTER_EPHEMERAL}/flutter_windows.dll.lib" dwmapi.lib)
add_custom_command(TARGET window_frame_test POST_BUILD COMMAND ${CMAKE_COMMAND} -E copy_if_different
  "${FLUTTER_EPHEMERAL}/flutter_windows.dll" "$<TARGET_FILE_DIR:window_frame_test>")
enable_testing()
add_test(NAME window_frame_regression COMMAND window_frame_test)
