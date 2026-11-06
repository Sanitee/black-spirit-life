#ifndef RUNNER_SINGLE_INSTANCE_H_
#define RUNNER_SINGLE_INSTANCE_H_

#include <windows.h>
#include <commctrl.h>
#include <string>

namespace bsl::windows {

// UI routing only. The independent shared-profile writer lease remains the
// authority for saved data, including other Windows sessions and older builds.
class SingleInstance {
 public:
  enum class Result { primary, forwarded, unavailable };
  explicit SingleInstance(
      std::wstring identity = L"BlackSpiritLife.SharedProfile.Window.v1");
  ~SingleInstance();
  SingleInstance(const SingleInstance&) = delete;
  SingleInstance& operator=(const SingleInstance&) = delete;

  Result AcquireOrActivate(DWORD timeout_ms = 8000);
  bool AttachWindow(HWND window);
  // Read-only discovery also used by the native compatibility regression probe.
  HWND FindLegacyWindow();

 private:
  static BOOL CALLBACK FindWindowCallback(HWND window, LPARAM parameter);
  static BOOL CALLBACK FindLegacyWindowCallback(HWND window, LPARAM parameter);
  static LRESULT CALLBACK WindowProc(HWND window, UINT message, WPARAM wparam,
                                    LPARAM lparam, UINT_PTR id,
                                    DWORD_PTR reference);
  void Activate(HWND window);
  Result ActivateLegacy(HWND window, DWORD timeout_ms);
  std::wstring identity_;
  std::wstring user_sid_;
  std::wstring property_;
  HANDLE mutex_ = nullptr;
  bool acquired_ = false;
  HWND window_ = nullptr;
  HWND found_ = nullptr;
  UINT activate_message_ = 0;
  ULONGLONG legacy_creation_ = ~ULONGLONG{0};
};

}  // namespace bsl::windows
#endif
