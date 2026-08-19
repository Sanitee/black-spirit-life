cmake_minimum_required(VERSION 3.25)

project(BlackSpiritLifeInstaller LANGUAGES CXX RC)

set(BSL_INSTALLER_VERSION "0.1.4" CACHE STRING
    "Semantic version shown by the themed installer")
set(BSL_INSTALLER_BUILD_NUMBER "23" CACHE STRING
    "Flutter build number included in Windows version metadata")
set(BSL_INSTALLER_PACKAGE_ID "BlackSpiritLife.App" CACHE STRING
    "Permanent Velopack package identity")
set(BSL_INSTALLER_CHANNEL "win-x64-stable" CACHE STRING
    "Permanent public update channel")
set(BSL_INSTALLER_ENGINE "" CACHE FILEPATH
    "Generated Velopack Setup executable embedded in production builds")
set(BSL_INSTALLER_ENGINE_SHA256 "" CACHE STRING
    "SHA-256 of the embedded Velopack Setup executable")

if(NOT BSL_INSTALLER_VERSION MATCHES "^([0-9]+)\\.([0-9]+)\\.([0-9]+)$")
  message(FATAL_ERROR
          "BSL_INSTALLER_VERSION must contain exactly three numeric parts")
endif()
set(BSL_INSTALLER_VERSION_MAJOR "${CMAKE_MATCH_1}")
set(BSL_INSTALLER_VERSION_MINOR "${CMAKE_MATCH_2}")
set(BSL_INSTALLER_VERSION_PATCH "${CMAKE_MATCH_3}")
if(NOT BSL_INSTALLER_BUILD_NUMBER MATCHES "^[0-9]+$" OR
   BSL_INSTALLER_BUILD_NUMBER GREATER 65535)
  message(FATAL_ERROR
          "BSL_INSTALLER_BUILD_NUMBER must be an integer from 0 through 65535")
endif()

get_filename_component(BSL_PROJECT_ROOT "${CMAKE_CURRENT_SOURCE_DIR}/../.." ABSOLUTE)
file(TO_CMAKE_PATH "${BSL_PROJECT_ROOT}/windows/runner/resources/app_icon.ico" BSL_APP_ICON)
file(TO_CMAKE_PATH "${CMAKE_CURRENT_SOURCE_DIR}/assets/blackened-cedar-installer.jpg" BSL_SAKURA_CEDAR)
file(TO_CMAKE_PATH "${CMAKE_CURRENT_SOURCE_DIR}/assets/charcoal-plum-lacquer-installer.jpg" BSL_SAKURA_LACQUER)
file(TO_CMAKE_PATH "${BSL_PROJECT_ROOT}/assets/sakura/botanicals/title-sprig.png" BSL_SAKURA_TITLE_SPRIG)

file(SHA256 "${BSL_SAKURA_CEDAR}" BSL_SAKURA_CEDAR_SHA256)
file(SHA256 "${BSL_SAKURA_LACQUER}" BSL_SAKURA_LACQUER_SHA256)
if(NOT BSL_SAKURA_CEDAR_SHA256 STREQUAL
   "4d614522b41bf8aad766e95516beb086e96c4516dda58acf564d3912931e563e")
  message(FATAL_ERROR "The optimized installer cedar texture changed unexpectedly")
endif()
if(NOT BSL_SAKURA_LACQUER_SHA256 STREQUAL
   "d0a6ab9f4db69a34b3070ad0ff2a169f3c62a491b1e928718b1d042bc0a796a3")
  message(FATAL_ERROR "The optimized installer lacquer texture changed unexpectedly")
endif()

set(BSL_HAS_EMBEDDED_ENGINE 0)
set(BSL_ENGINE_RESOURCE_LINE "")
if(BSL_INSTALLER_ENGINE)
  get_filename_component(BSL_INSTALLER_ENGINE "${BSL_INSTALLER_ENGINE}" ABSOLUTE)
  if(NOT EXISTS "${BSL_INSTALLER_ENGINE}")
    message(FATAL_ERROR "BSL_INSTALLER_ENGINE does not exist: ${BSL_INSTALLER_ENGINE}")
  endif()
  string(LENGTH "${BSL_INSTALLER_ENGINE_SHA256}" BSL_INSTALLER_ENGINE_SHA256_LENGTH)
  if(NOT BSL_INSTALLER_ENGINE_SHA256_LENGTH EQUAL 64 OR
     NOT BSL_INSTALLER_ENGINE_SHA256 MATCHES "^[0-9A-Fa-f]+$")
    message(FATAL_ERROR "A 64-character BSL_INSTALLER_ENGINE_SHA256 is required")
  endif()
  file(TO_CMAKE_PATH "${BSL_INSTALLER_ENGINE}" BSL_INSTALLER_ENGINE_RESOURCE_PATH)
  set(BSL_HAS_EMBEDDED_ENGINE 1)
  set(BSL_ENGINE_RESOURCE_LINE
      "IDR_VELOPACK_SETUP RCDATA \"${BSL_INSTALLER_ENGINE_RESOURCE_PATH}\"")
endif()

set(BSL_GENERATED_DIR "${CMAKE_CURRENT_BINARY_DIR}/generated")
file(MAKE_DIRECTORY "${BSL_GENERATED_DIR}")
configure_file(installer.manifest
               "${BSL_GENERATED_DIR}/installer.manifest" @ONLY)
file(TO_CMAKE_PATH "${BSL_GENERATED_DIR}/installer.manifest" BSL_INSTALLER_MANIFEST)
configure_file(installer_build_config.h.in
               "${BSL_GENERATED_DIR}/installer_build_config.h" @ONLY)
configure_file(installer_resources.rc
               "${BSL_GENERATED_DIR}/installer_resources.rc" @ONLY)

add_executable(BlackSpiritLifeInstaller WIN32
  main.cpp
  embedded_payload.cpp
  embedded_payload.h
  install_engine.cpp
  install_engine.h
  install_path_policy.cpp
  install_path_policy.h
  install_process_guard.cpp
  install_process_guard.h
  installed_beta_locator.cpp
  installed_beta_locator.h
  personal_data_removal.cpp
  personal_data_removal.h
  ../shared/beta_maintenance_gate.cpp
  ../shared/beta_maintenance_gate.h
  installer_model.h
  installer_renderer.cpp
  installer_renderer.h
  "${BSL_GENERATED_DIR}/installer_resources.rc"
  resource.h
)

target_include_directories(BlackSpiritLifeInstaller PRIVATE
  "${CMAKE_CURRENT_SOURCE_DIR}"
  "${BSL_PROJECT_ROOT}/windows/shared"
  "${BSL_GENERATED_DIR}"
)

target_compile_features(BlackSpiritLifeInstaller PRIVATE cxx_std_20)
target_compile_definitions(BlackSpiritLifeInstaller PRIVATE
  NOMINMAX
  STRICT
  UNICODE
  _UNICODE
  WIN32_LEAN_AND_MEAN
)

if(MSVC)
  target_compile_options(BlackSpiritLifeInstaller PRIVATE
    /W4
    /permissive-
    /utf-8
    /EHsc
  )
  target_link_options(BlackSpiritLifeInstaller PRIVATE /MANIFEST:NO)
endif()

target_link_libraries(BlackSpiritLifeInstaller PRIVATE
  d2d1
  dwrite
  dwmapi
  bcrypt
  gdiplus
  ole32
  shell32
  shlwapi
  uuid
  version
)

set_target_properties(BlackSpiritLifeInstaller PROPERTIES
  OUTPUT_NAME "BlackSpiritLifeInstaller"
  VS_DPI_AWARE "PerMonitor"
)

include(CTest)
if(BUILD_TESTING)
  add_executable(BlackSpiritLifeInstallerNativeTests EXCLUDE_FROM_ALL
    installer_native_tests.cpp
    install_path_policy.cpp
    install_path_policy.h
    install_process_guard.cpp
    install_process_guard.h
    installed_beta_locator.cpp
    installed_beta_locator.h
    personal_data_removal.cpp
    personal_data_removal.h
    ../shared/beta_maintenance_gate.cpp
    ../shared/beta_maintenance_gate.h
  )
  target_include_directories(BlackSpiritLifeInstallerNativeTests PRIVATE
    "${CMAKE_CURRENT_SOURCE_DIR}"
    "${BSL_PROJECT_ROOT}/windows/shared"
    "${BSL_GENERATED_DIR}"
  )
  target_compile_features(BlackSpiritLifeInstallerNativeTests PRIVATE
    cxx_std_20)
  target_compile_definitions(BlackSpiritLifeInstallerNativeTests PRIVATE
    NOMINMAX STRICT UNICODE _UNICODE WIN32_LEAN_AND_MEAN)
  if(MSVC)
    target_compile_options(BlackSpiritLifeInstallerNativeTests PRIVATE
      /W4 /permissive- /utf-8 /EHsc)
  endif()
  target_link_libraries(BlackSpiritLifeInstallerNativeTests PRIVATE
    ole32 shell32)
  add_test(NAME BlackSpiritLifeInstallerNativeTests
           COMMAND BlackSpiritLifeInstallerNativeTests)
endif()
