#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <shobjidl.h>
#include <windows.h>

#include <algorithm>
#include <string>
#include <vector>

#include "../shared/beta_maintenance_gate.h"
#include "Velopack.h"
#include "flutter_window.h"
#include "utils.h"

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  std::vector<std::string> command_line_arguments = GetCommandLineArguments();
  const bool reference_mode =
      std::find(command_line_arguments.begin(), command_line_arguments.end(),
                "--reference") != command_line_arguments.end();

  bsl::windows::BetaMaintenanceGate startup_gate;
  if (!reference_mode) {
    // Velopack lifecycle hooks and the maintenance gate belong to the primary
    // application only. The standalone-compatible Minigame Helper is an
    // independent child process and never owns or updates application files.
    vpkc_app_set_auto_apply_on_startup(false);
    vpkc_app_run(nullptr);
    std::wstring maintenance_error;
    if (!startup_gate.TryAcquire(&maintenance_error)) {
      MessageBoxW(nullptr, maintenance_error.c_str(), L"Black Spirit Life",
                  MB_OK | MB_ICONINFORMATION);
      return EXIT_FAILURE;
    }
  }

  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  // Initialize COM, so that it is available for use in the library and/or
  // plugins.
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);
  if (reference_mode) {
    ::SetCurrentProcessExplicitAppUserModelID(
        L"BlackSpiritLife.BdoGatheringCompanion");
  }

  flutter::DartProject project(L"data");
  // The resource map composites a large tiled surface, route network, and
  // retained marker layers. Prefer a discrete/high-performance GPU when one
  // exists; Flutter safely falls back on single-GPU and integrated systems.
  project.set_gpu_preference(flutter::GpuPreference::HighPerformancePreference);

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project, reference_mode);
  Win32Window::Point origin(10, 10);
  // Keep the established 75:47 desktop composition while giving the map and
  // planner a little more room on first launch. The 1200x752 resize floor in
  // flutter_window.cpp remains unchanged for smaller displays.
  Win32Window::Size size(reference_mode ? 540 : 1575,
                         reference_mode ? 620 : 987);
  if (!window.Create(reference_mode ? L"Minigame Helper"
                                    : L"Black Spirit Life",
                     origin, size, reference_mode)) {
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(true);
  // The process is now visible with its final executable path. Releasing the
  // startup gate lets maintenance acquire it and then reliably discover this
  // running planner before Velopack is allowed to replace application files.
  if (!reference_mode) startup_gate.Release();

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  ::CoUninitialize();
  return EXIT_SUCCESS;
}
