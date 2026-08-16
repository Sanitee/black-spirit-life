cmake_minimum_required(VERSION 3.14)
project(runner LANGUAGES CXX)

# Define the application target. To change its name, change BINARY_NAME in the
# top-level CMakeLists.txt, not the value here, or `flutter run` will no longer
# work.
#
# Any new source files that you add to the application should be added here.
add_executable(${BINARY_NAME} WIN32
  "active_node_scan_protocol.cpp"
  "active_node_video_scanner.cpp"
  "clipboard_image_reader.cpp"
  "flutter_window.cpp"
  "main.cpp"
  "utils.cpp"
  "win32_window.cpp"
  "../shared/beta_maintenance_gate.cpp"
  "../shared/beta_maintenance_gate.h"
  "${FLUTTER_MANAGED_DIR}/generated_plugin_registrant.cc"
  "Runner.rc"
  "runner.exe.manifest"
)

# Apply the standard set of build settings. This can be removed for applications
# that need different build settings.
apply_standard_settings(${BINARY_NAME})

# Add preprocessor definitions for the build version.
target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION=\"${FLUTTER_VERSION}\"")
target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION_MAJOR=${FLUTTER_VERSION_MAJOR}")
target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION_MINOR=${FLUTTER_VERSION_MINOR}")
target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION_PATCH=${FLUTTER_VERSION_PATCH}")
target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION_BUILD=${FLUTTER_VERSION_BUILD}")

# Disable Windows macros that collide with C++ standard library functions.
target_compile_definitions(${BINARY_NAME} PRIVATE "NOMINMAX")

# Add dependency libraries and include directories. Add any application-specific
# dependencies here.
target_link_libraries(${BINARY_NAME} PRIVATE flutter flutter_wrapper_app)

target_include_directories(${BINARY_NAME} SYSTEM PRIVATE
  "${VELOPACK_ROOT}/include")
target_link_libraries(${BINARY_NAME} PRIVATE "${VELOPACK_IMPORT_LIBRARY}")
target_link_libraries(${BINARY_NAME} PRIVATE
  "dwmapi.lib"
  "comdlg32.lib"
  "comctl32.lib"
  "gdi32.lib"
  "mfplat.lib"
  "mfreadwrite.lib"
  "mfuuid.lib"
  "ole32.lib"
  "shell32.lib"
  "windowsapp.lib"
  "windowscodecs.lib"
  "wininet.lib"
)
target_include_directories(${BINARY_NAME} PRIVATE "${CMAKE_SOURCE_DIR}")

# Run the Flutter tool portions of the build. This must not be removed.
add_dependencies(${BINARY_NAME} flutter_assemble)

# Run Media Foundation and Windows OCR outside the Flutter process. Some video
# drivers can stall indefinitely during decoder teardown even after OCR has
# completed; isolating that work keeps the planner responsive and lets it stop
# the helper after collecting the atomic result file.
add_executable(BDOActiveNodeScanner
  "active_node_scan_protocol.cpp"
  "active_node_scanner_main.cpp"
  "active_node_video_scanner.cpp"
)
apply_standard_settings(BDOActiveNodeScanner)
target_compile_definitions(BDOActiveNodeScanner PRIVATE "NOMINMAX")
target_include_directories(BDOActiveNodeScanner PRIVATE "${CMAKE_SOURCE_DIR}")
target_link_libraries(BDOActiveNodeScanner PRIVATE
  "mfplat.lib"
  "mfreadwrite.lib"
  "mfuuid.lib"
  "ole32.lib"
  "shell32.lib"
  "windowsapp.lib"
  "windowscodecs.lib"
)
add_dependencies(${BINARY_NAME} BDOActiveNodeScanner)

# Velopack manager/check/download/apply operations run only in this short-lived
# helper so a native updater fault cannot terminate the planner process.
add_executable(BlackSpiritLifeUpdater WIN32
  "beta_updater_main.cpp"
  "../shared/beta_maintenance_gate.cpp"
  "../shared/beta_maintenance_gate.h"
)
apply_standard_settings(BlackSpiritLifeUpdater)
target_compile_definitions(BlackSpiritLifeUpdater PRIVATE "NOMINMAX")
target_include_directories(BlackSpiritLifeUpdater SYSTEM PRIVATE
  "${VELOPACK_ROOT}/include")
target_link_libraries(BlackSpiritLifeUpdater PRIVATE
  "${VELOPACK_IMPORT_LIBRARY}"
  "shell32.lib"
  "wininet.lib"
)
add_dependencies(${BINARY_NAME} BlackSpiritLifeUpdater)
