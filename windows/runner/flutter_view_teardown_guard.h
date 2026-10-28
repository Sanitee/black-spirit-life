#ifndef RUNNER_FLUTTER_VIEW_TEARDOWN_GUARD_H_
#define RUNNER_FLUTTER_VIEW_TEARDOWN_GUARD_H_

#include <windows.h>
#include <commctrl.h>

// Embedded media can synchronously query its parent's accessibility provider while
// DestroyWindow is running. Flutter's AX tree has already been destroyed at
// that point. Keep the view's normal accessibility intact until teardown, then
// answer that no provider remains instead of entering the dead engine tree.
class FlutterViewTeardownGuard {
 public:
  FlutterViewTeardownGuard() = default;
  FlutterViewTeardownGuard(const FlutterViewTeardownGuard&) = delete;
  FlutterViewTeardownGuard& operator=(const FlutterViewTeardownGuard&) = delete;

  ~FlutterViewTeardownGuard() {
    if (window_ != nullptr) {
      RemoveWindowSubclass(window_, SubclassProc, SubclassId());
    }
  }

  bool Attach(HWND window) {
    if (window == nullptr || window_ != nullptr) return false;
    destroying_ = false;
    if (!SetWindowSubclass(window, SubclassProc, SubclassId(),
                           reinterpret_cast<DWORD_PTR>(this))) {
      return false;
    }
    window_ = window;
    return true;
  }

  void BeginTeardown() { destroying_ = true; }
  bool attached() const { return window_ != nullptr; }

 private:
  UINT_PTR SubclassId() const { return reinterpret_cast<UINT_PTR>(this); }

  static LRESULT CALLBACK SubclassProc(HWND window, UINT message, WPARAM wparam,
                                      LPARAM lparam, UINT_PTR subclass_id,
                                      DWORD_PTR reference_data) {
    auto* guard = reinterpret_cast<FlutterViewTeardownGuard*>(reference_data);
    if (message == WM_GETOBJECT && guard->destroying_) return 0;
    if (message == WM_NCDESTROY) {
      // Keep protection installed through the underlying window procedure's
      // final destruction, including any reentrant accessibility request.
      const auto result = DefSubclassProc(window, message, wparam, lparam);
      RemoveWindowSubclass(window, SubclassProc, subclass_id);
      guard->window_ = nullptr;
      return result;
    }
    return DefSubclassProc(window, message, wparam, lparam);
  }

  HWND window_ = nullptr;
  bool destroying_ = false;
};

#endif  // RUNNER_FLUTTER_VIEW_TEARDOWN_GUARD_H_
