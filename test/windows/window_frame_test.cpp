#include <windows.h>
#include <windowsx.h>

#include <iostream>
#include <string>
#include <vector>

#include "win32_window.h"

namespace {
int checks = 0;
int failures = 0;

void Check(bool condition, const std::string& message) {
  ++checks;
  if (!condition) ++failures;
  std::cout << (condition ? "PASS " : "FAIL ") << message << std::endl;
}

class TestWindow : public Win32Window {
 public:
  int activations = 0;
  int shows = 0;
  int dpi_changes = 0;

 protected:
  LRESULT MessageHandler(HWND hwnd, UINT message, WPARAM wparam,
                         LPARAM lparam) noexcept override {
    if (message == WM_ACTIVATE && LOWORD(wparam) != WA_INACTIVE) ++activations;
    if (message == WM_SHOWWINDOW && wparam != FALSE) ++shows;
    if (message == WM_DPICHANGED) ++dpi_changes;
    return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
  }
};

bool Equal(const RECT& a, const RECT& b) {
  return a.left == b.left && a.top == b.top && a.right == b.right &&
         a.bottom == b.bottom;
}

void CheckHidden(TestWindow& window, const std::string& label) {
  Check(!IsWindowVisible(window.GetHandle()) && window.activations == 0 &&
            window.shows == 0 && GetForegroundWindow() != window.GetHandle(),
        label + ": owned window stays hidden and never activates");
}

void CheckCalculation(TestWindow& window, bool native,
                      const std::string& label) {
  const HWND hwnd = window.GetHandle();
  NCCALCSIZE_PARAMS actual{};
  actual.rgrc[0] = {-1550, -720, -910, 0};
  actual.rgrc[1] = actual.rgrc[0];
  actual.rgrc[2] = actual.rgrc[0];
  WINDOWPOS proposed{hwnd, nullptr, -1550, -720, 640, 720,
                     SWP_NOACTIVATE | SWP_NOZORDER};
  actual.lppos = &proposed;
  auto expected = actual;
  const RECT full = actual.rgrc[0];
  DefWindowProc(hwnd, WM_NCCALCSIZE, TRUE,
                reinterpret_cast<LPARAM>(&expected));
  SendMessage(hwnd, WM_NCCALCSIZE, TRUE, reinterpret_cast<LPARAM>(&actual));
  Check(Equal(actual.rgrc[0], native ? expected.rgrc[0] : full),
        label + ": TRUE nonclient calculation follows selected frame policy");
  if (native) {
    Check(actual.rgrc[0].top > full.top &&
              actual.rgrc[0].bottom < full.bottom,
          label + ": native caption and lower frame retain their own area");
  }

  RECT actual_false = full;
  RECT expected_false = full;
  DefWindowProc(hwnd, WM_NCCALCSIZE, FALSE,
                reinterpret_cast<LPARAM>(&expected_false));
  SendMessage(hwnd, WM_NCCALCSIZE, FALSE,
              reinterpret_cast<LPARAM>(&actual_false));
  Check(Equal(actual_false, expected_false),
        label + ": FALSE preserves default Windows rectangle calculation");
}

void CheckGeometry(TestWindow& window, bool native,
                   const std::string& label) {
  const HWND hwnd = window.GetHandle();
  RECT bounds{};
  RECT client{};
  Check(GetWindowRect(hwnd, &bounds) && GetClientRect(hwnd, &client),
        label + ": native window/client rectangles available");
  POINT origin{0, 0};
  ClientToScreen(hwnd, &origin);
  const LONG top_inset = origin.y - bounds.top;
  std::cout << "GEOMETRY " << label << " dpi=" << GetDpiForWindow(hwnd)
            << " topInset=" << top_inset << " windowHeight="
            << bounds.bottom - bounds.top << " clientHeight=" << client.bottom
            << std::endl;
  Check(native ? top_inset > 0 : top_inset == 0,
        label + ": actual client origin reserves only the selected frame");
  const auto style = static_cast<DWORD>(GetWindowLongPtr(hwnd, GWL_STYLE));
  const DWORD controls = WS_SYSMENU | WS_MINIMIZEBOX | WS_MAXIMIZEBOX;
  Check((style & controls) == controls &&
            ((style & WS_CAPTION) == WS_CAPTION) == native,
        label + ": caption and system control style bits stay unchanged");
  if (native) {
    const HMENU menu = GetSystemMenu(hwnd, FALSE);
    Check(menu != nullptr && GetMenuState(menu, SC_CLOSE, MF_BYCOMMAND) != UINT(-1) &&
              GetMenuState(menu, SC_MINIMIZE, MF_BYCOMMAND) != UINT(-1) &&
              GetMenuState(menu, SC_MAXIMIZE, MF_BYCOMMAND) != UINT(-1),
          label + ": native Close/Minimize/Maximize commands remain available");
    const UINT dpi = GetDpiForWindow(hwnd);
    const int border = GetSystemMetricsForDpi(SM_CYFRAME, dpi) +
                       GetSystemMetricsForDpi(SM_CXPADDEDBORDER, dpi);
    const int caption = GetSystemMetricsForDpi(SM_CYCAPTION, dpi);
    const LPARAM point = MAKELPARAM(bounds.left + (bounds.right - bounds.left) / 2,
                                   bounds.top + border + caption / 2);
    Check(SendMessage(hwnd, WM_NCHITTEST, 0, point) == HTCAPTION,
          label + ": native caption hit testing remains reachable");
  }
  CheckHidden(window, label);
}

BOOL CALLBACK CollectMonitors(HMONITOR monitor, HDC, LPRECT, LPARAM data) {
  auto& areas = *reinterpret_cast<std::vector<RECT>*>(data);
  MONITORINFO info{};
  info.cbSize = sizeof(info);
  if (GetMonitorInfo(monitor, &info)) areas.push_back(info.rcWork);
  return TRUE;
}

void Exercise(TestWindow& window, bool native, const std::string& label,
              const std::vector<RECT>& monitors) {
  Check(window.Create(L"Hidden window frame regression", {10, 10}, {540, 620},
                      native),
        label + ": production Win32Window creates without Show");
  if (window.GetHandle() == nullptr) return;
  CheckCalculation(window, native, label + " creation");
  // Creation can use the FALSE calculation. Force the TRUE layout transition
  // before testing unchanged-size messages so both modes have a known baseline.
  Check(SetWindowPos(window.GetHandle(), nullptr, 0, 0, 0, 0,
                     SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE | SWP_NOZORDER |
                         SWP_FRAMECHANGED) != FALSE,
        label + ": explicit initial frame recalculation succeeds");

  // These messages exercise production resizing, not actual monitor DPI changes.
  for (const UINT dpi : {96U, 120U, 144U, 192U, 96U}) {
    RECT suggested{-1700, -800, -1700 + MulDiv(540, dpi, 96),
                    -800 + MulDiv(620, dpi, 96)};
    SendMessage(window.GetHandle(), WM_DPICHANGED, MAKEWPARAM(dpi, dpi),
                reinterpret_cast<LPARAM>(&suggested));
    CheckGeometry(window, native, label + " synthetic-DPI-" + std::to_string(dpi));
    CheckCalculation(window, native, label + " post-DPI");
  }
  Check(SetWindowPos(window.GetHandle(), nullptr, -1200, -640, 610, 700,
                     SWP_NOACTIVATE | SWP_NOZORDER | SWP_FRAMECHANGED) != FALSE,
        label + ": negative-origin frame-changed move/resize succeeds");
  CheckGeometry(window, native, label + " frame-changed");

  const int prior_dpi_events = window.dpi_changes;
  for (size_t index = 0; index < monitors.size(); ++index) {
    const RECT area = monitors[index];
    const int x = area.left + (area.right - area.left) / 3;
    const int y = area.top + (area.bottom - area.top) / 3;
    Check(SetWindowPos(window.GetHandle(), nullptr, x, y, 540, 620,
                       SWP_NOACTIVATE | SWP_NOZORDER | SWP_FRAMECHANGED) != FALSE,
          label + ": owned hidden move to connected monitor " + std::to_string(index));
    CheckGeometry(window, native, label + " actual-monitor-" + std::to_string(index));
  }
  std::cout << "ACTUAL_MONITOR_DPI_EVENTS " << label << " "
            << window.dpi_changes - prior_dpi_events << std::endl;
  CheckHidden(window, label + " complete");
  window.Destroy();
}
}  // namespace

int main() {
  // Process-local awareness only; no display settings or user window changes.
  const BOOL awareness = SetProcessDpiAwarenessContext(DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2);
  Check(awareness || AreDpiAwarenessContextsEqual(GetThreadDpiAwarenessContext(),
                                                DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2),
        "fixture is PerMonitorV2 aware");
  std::vector<RECT> monitors;
  Check(EnumDisplayMonitors(nullptr, nullptr, CollectMonitors,
                             reinterpret_cast<LPARAM>(&monitors)) != FALSE,
        "connected monitor work areas enumerated read-only");
  std::cout << "CONNECTED_MONITORS " << monitors.size() << std::endl;
  TestWindow window;
  Exercise(window, true, "native", monitors);
  Exercise(window, false, "borderless-recreated", monitors);
  Exercise(window, true, "native-recreated", monitors);
  Check(window.activations == 0 && window.shows == 0,
        "all owned test windows remained hidden and never activated");
  std::cout << "RESULT checks=" << checks << " failures=" << failures << std::endl;
  std::cout << "No Flutter engine, Show, OS input, other-window movement, profile access, or monitor-setting changes."
            << std::endl;
  return failures == 0 ? 0 : 1;
}
