#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>

#include "../shared/beta_maintenance_gate.h"
#include "Velopack.h"
#include "flutter_window.h"
#include "utils.h"

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  // Velopack lifecycle hooks must run before the app initializes COM, Flutter,
  // or any other process state. In ordinary launches this returns immediately.
  vpkc_app_set_auto_apply_on_startup(false);
  vpkc_app_run(nullptr);

  bsl::windows::BetaMaintenanceGate startup_gate;
  std::wstring maintenance_error;
  if (!startup_gate.TryAcquire(&maintenance_error)) {
    MessageBoxW(nullptr, maintenance_error.c_str(), L"Black Spirit Life",
                MB_OK | MB_ICONINFORMATION);
    return EXIT_FAILURE;
  }

  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  // Initialize COM, so that it is available for use in the library and/or
  // plugins.
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  flutter::DartProject project(L"data");
  // The resource map composites a large tiled surface, route network, and
  // retained marker layers. Prefer a discrete/high-performance GPU when one
  // exists; Flutter safely falls back on single-GPU and integrated systems.
  project.set_gpu_preference(flutter::GpuPreference::HighPerformancePreference);

  std::vector<std::string> command_line_arguments = GetCommandLineArguments();

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project);
  Win32Window::Point origin(10, 10);
  // Keep the established 75:47 desktop composition while giving the map and
  // planner a little more room on first launch. The 1200x752 resize floor in
  // flutter_window.cpp remains unchanged for smaller displays.
  Win32Window::Size size(1575, 987);
  if (!window.Create(L"Black Spirit Life", origin, size)) {
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(true);
  // The process is now visible with its final executable path. Releasing the
  // startup gate lets maintenance acquire it and then reliably discover this
  // running planner before Velopack is allowed to replace application files.
  startup_gate.Release();

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  ::CoUninitialize();
  return EXIT_SUCCESS;
}
