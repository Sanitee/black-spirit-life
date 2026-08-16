# Project-level configuration.
cmake_minimum_required(VERSION 3.14)
project(black_spirit_life LANGUAGES CXX)

# The name of the executable created for the application. Change this to change
# the on-disk name of your application.
set(BINARY_NAME "BlackSpiritLife")

# Explicitly opt in to modern CMake behaviors to avoid warnings with recent
# versions of CMake.
cmake_policy(VERSION 3.14...3.25)

# Define build configuration option.
get_property(IS_MULTICONFIG GLOBAL PROPERTY GENERATOR_IS_MULTI_CONFIG)
if(IS_MULTICONFIG)
  set(CMAKE_CONFIGURATION_TYPES "Debug;Profile;Release"
    CACHE STRING "" FORCE)
else()
  if(NOT CMAKE_BUILD_TYPE AND NOT CMAKE_CONFIGURATION_TYPES)
    set(CMAKE_BUILD_TYPE "Debug" CACHE
      STRING "Flutter build mode" FORCE)
    set_property(CACHE CMAKE_BUILD_TYPE PROPERTY STRINGS
      "Debug" "Profile" "Release")
  endif()
endif()
# Define settings for the Profile build mode.
set(CMAKE_EXE_LINKER_FLAGS_PROFILE "${CMAKE_EXE_LINKER_FLAGS_RELEASE}")
set(CMAKE_SHARED_LINKER_FLAGS_PROFILE "${CMAKE_SHARED_LINKER_FLAGS_RELEASE}")
set(CMAKE_C_FLAGS_PROFILE "${CMAKE_C_FLAGS_RELEASE}")
set(CMAKE_CXX_FLAGS_PROFILE "${CMAKE_CXX_FLAGS_RELEASE}")

# Use Unicode for all projects.
add_definitions(-DUNICODE -D_UNICODE)

# Compilation settings that should be applied to most targets.
#
# Be cautious about adding new options here, as plugins use this function by
# default. In most cases, you should add new options to specific targets instead
# of modifying this function.
function(APPLY_STANDARD_SETTINGS TARGET)
  target_compile_features(${TARGET} PUBLIC cxx_std_17)
  target_compile_options(${TARGET} PRIVATE /W4 /WX /wd"4100")
  target_compile_options(${TARGET} PRIVATE /EHsc)
  target_compile_definitions(${TARGET} PRIVATE "_HAS_EXCEPTIONS=0")
  target_compile_definitions(${TARGET} PRIVATE "$<$<CONFIG:Debug>:_DEBUG>")
endfunction()

# The native updater is intentionally vendored and checksum-pinned so release
# builds remain reproducible and do not fetch executable code at build
# time. The matching vpk 1.2.0 CLI is used separately by local packaging.
set(VELOPACK_ROOT "${CMAKE_SOURCE_DIR}/third_party/velopack/1.2.0")
set(VELOPACK_HEADER "${VELOPACK_ROOT}/include/Velopack.h")
set(VELOPACK_HPP "${VELOPACK_ROOT}/include/Velopack.hpp")
set(VELOPACK_DLL "${VELOPACK_ROOT}/lib/x64/velopack_libc_win_x64_msvc.dll")
set(VELOPACK_IMPORT_LIBRARY
  "${VELOPACK_ROOT}/lib/x64/velopack_libc_win_x64_msvc.dll.lib")
set(VELOPACK_RUNTIME_BUNDLE_NAME "velopack_libc.dll")

function(verify_pinned_file FILE_PATH EXPECTED_SHA256)
  if(NOT EXISTS "${FILE_PATH}")
    message(FATAL_ERROR "Pinned dependency is missing: ${FILE_PATH}")
  endif()
  file(SHA256 "${FILE_PATH}" ACTUAL_SHA256)
  if(NOT ACTUAL_SHA256 STREQUAL EXPECTED_SHA256)
    message(FATAL_ERROR
      "Pinned dependency hash mismatch for ${FILE_PATH}. "
      "Expected ${EXPECTED_SHA256}; found ${ACTUAL_SHA256}.")
  endif()
endfunction()

verify_pinned_file("${VELOPACK_HEADER}"
  "e6711fcc565386ef6c4e80079c44b6f3221a98e5c43b33a9331311a28b54c8fc")
verify_pinned_file("${VELOPACK_HPP}"
  "16cfdf96c48360b7d76ba06dd941d464e3427fa7aca2f84626c6ee3af76b14c9")
verify_pinned_file("${VELOPACK_DLL}"
  "c36d8b984639a8af9d3397088d3ffb8213fe1bd0917f555cf0c6e33f014403ec")
verify_pinned_file("${VELOPACK_IMPORT_LIBRARY}"
  "063def3f77ccdd44fd719536b9cb464015cc34e3c10197add6643aec02408d11")

# Flutter library and tool build rules.
set(FLUTTER_MANAGED_DIR "${CMAKE_CURRENT_SOURCE_DIR}/flutter")
add_subdirectory(${FLUTTER_MANAGED_DIR})

# Application build; see runner/CMakeLists.txt.
add_subdirectory("runner")


# Generated plugin build rules, which manage building the plugins and adding
# them to the application.
include(flutter/generated_plugins.cmake)


# === Installation ===
# Support files are copied into place next to the executable, so that it can
# run in place. This is done instead of making a separate bundle (as on Linux)
# so that building and running from within Visual Studio will work.
set(BUILD_BUNDLE_DIR "$<TARGET_FILE_DIR:${BINARY_NAME}>")
# Make the "install" step default, as it's required to run.
set(CMAKE_VS_INCLUDE_INSTALL_TO_DEFAULT_BUILD 1)
if(CMAKE_INSTALL_PREFIX_INITIALIZED_TO_DEFAULT)
  set(CMAKE_INSTALL_PREFIX "${BUILD_BUNDLE_DIR}" CACHE PATH "..." FORCE)
endif()

set(INSTALL_BUNDLE_DATA_DIR "${CMAKE_INSTALL_PREFIX}/data")
set(INSTALL_BUNDLE_LIB_DIR "${CMAKE_INSTALL_PREFIX}")

install(TARGETS ${BINARY_NAME} RUNTIME DESTINATION "${CMAKE_INSTALL_PREFIX}"
  COMPONENT Runtime)
install(TARGETS BDOActiveNodeScanner RUNTIME DESTINATION "${CMAKE_INSTALL_PREFIX}"
  COMPONENT Runtime)
install(TARGETS BlackSpiritLifeUpdater
  RUNTIME DESTINATION "${CMAKE_INSTALL_PREFIX}"
  COMPONENT Runtime)

install(FILES "${VELOPACK_DLL}" DESTINATION "${INSTALL_BUNDLE_LIB_DIR}"
  RENAME "${VELOPACK_RUNTIME_BUNDLE_NAME}"
  COMPONENT Runtime)
install(FILES "${VELOPACK_ROOT}/LICENSE"
  DESTINATION "${CMAKE_INSTALL_PREFIX}/licenses/velopack"
  COMPONENT Runtime)

install(FILES "${FLUTTER_ICU_DATA_FILE}" DESTINATION "${INSTALL_BUNDLE_DATA_DIR}"
  COMPONENT Runtime)

install(FILES "${FLUTTER_LIBRARY}" DESTINATION "${INSTALL_BUNDLE_LIB_DIR}"
  COMPONENT Runtime)

if(PLUGIN_BUNDLED_LIBRARIES)
  install(FILES "${PLUGIN_BUNDLED_LIBRARIES}"
    DESTINATION "${INSTALL_BUNDLE_LIB_DIR}"
    COMPONENT Runtime)
endif()

# Copy the native assets provided by the build.dart from all packages.
set(NATIVE_ASSETS_DIR "${PROJECT_BUILD_DIR}native_assets/windows/")
install(DIRECTORY "${NATIVE_ASSETS_DIR}"
   DESTINATION "${INSTALL_BUNDLE_LIB_DIR}"
   COMPONENT Runtime)

# Fully re-copy the assets directory on each build to avoid having stale files
# from a previous install.
set(FLUTTER_ASSET_DIR_NAME "flutter_assets")
install(CODE "
  file(REMOVE_RECURSE \"${INSTALL_BUNDLE_DATA_DIR}/${FLUTTER_ASSET_DIR_NAME}\")
  " COMPONENT Runtime)
install(DIRECTORY "${PROJECT_BUILD_DIR}/${FLUTTER_ASSET_DIR_NAME}"
  DESTINATION "${INSTALL_BUNDLE_DATA_DIR}" COMPONENT Runtime)

# Install the AOT library on non-Debug builds only.
install(FILES "${AOT_LIBRARY}" DESTINATION "${INSTALL_BUNDLE_DATA_DIR}"
  CONFIGURATIONS Profile;Release
  COMPONENT Runtime)
