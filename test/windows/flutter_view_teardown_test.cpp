#include <windows.h>
#include <iostream>

#include "flutter_view_teardown_guard.h"

namespace {
int failures = 0;
int live_requests = 0;
int destruction_requests = 0;
constexpr UINT kOrdinaryMessage = WM_APP + 7;
constexpr LRESULT kProvider = 12345;

void Check(bool condition, const char* description) {
  std::cout << (condition ? "PASS " : "FAIL ") << description << '\n';
  if (!condition) ++failures;
}

LRESULT CALLBACK TestProc(HWND window, UINT message, WPARAM wparam,
                          LPARAM lparam) {
  if (message == WM_GETOBJECT) {
    ++live_requests;
    return kProvider;
  }
  if (message == kOrdinaryMessage) return 6789;
  if (message == WM_DESTROY || message == WM_NCDESTROY) {
    // Reproduce WebView2's synchronous query while the Flutter view is being
    // destroyed. The native test never starts Flutter, a browser or a service.
    ++destruction_requests;
    Check(SendMessage(window, WM_GETOBJECT, 0, OBJID_CLIENT) == 0,
          "reentrant destruction query cannot reach the deleted provider");
  }
  return DefWindowProc(window, message, wparam, lparam);
}
}  // namespace

int main() {
  WNDCLASS type = {};
  type.lpfnWndProc = TestProc;
  type.hInstance = GetModuleHandle(nullptr);
  type.lpszClassName = L"CodexTeardownMessageOnlyTest";
  if (!RegisterClass(&type)) return 2;
  FlutterViewTeardownGuard guard;
  Check(!guard.Attach(nullptr), "null HWND rejected without attachment");
  for (int cycle = 0; cycle < 2; ++cycle) {
    HWND window = CreateWindow(type.lpszClassName, L"", 0, 0, 0, 0, 0,
                               HWND_MESSAGE, nullptr, type.hInstance, nullptr);
    if (!window) return 3;
    Check(!IsWindowVisible(window), "test owns a message-only, never shown HWND");
    Check(guard.Attach(window), "guard attaches to live view");
    Check(guard.attached(), "attachment tracks native lifetime");
    const int previous_requests = live_requests;
    for (const LPARAM object : {static_cast<LPARAM>(OBJID_CLIENT),
                                static_cast<LPARAM>(-25),
                                static_cast<LPARAM>(OBJID_WINDOW)}) {
      Check(SendMessage(window, WM_GETOBJECT, 0, object) == kProvider,
            "live accessibility requests reach the original provider");
    }
    Check(live_requests == previous_requests + 3,
          "all live MSAA/UIA/window accessibility requests forwarded");
    guard.BeginTeardown();
    guard.BeginTeardown();
    for (const LPARAM object : {static_cast<LPARAM>(OBJID_CLIENT),
                                static_cast<LPARAM>(-25),
                                static_cast<LPARAM>(OBJID_WINDOW)}) {
      Check(SendMessage(window, WM_GETOBJECT, 0, object) == 0,
            "closing view exposes no stale accessibility provider");
    }
    Check(live_requests == previous_requests + 3,
          "teardown accessibility requests never enter Flutter");
    Check(SendMessage(window, kOrdinaryMessage, 0, 0) == 6789,
          "ordinary native messages remain forwarded during teardown");
    Check(DestroyWindow(window) != FALSE, "message-only view destroys normally");
    Check(!guard.attached(), "WM_NCDESTROY clears attachment");
    Check(live_requests == previous_requests + 3,
          "reentrant queries throughout native destruction stay guarded");
  }
  Check(destruction_requests == 4, "both destruction stages exercised twice");
  UnregisterClass(type.lpszClassName, type.hInstance);
  return failures == 0 ? 0 : 1;
}
