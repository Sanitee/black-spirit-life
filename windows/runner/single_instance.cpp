#include "single_instance.h"

#include <sddl.h>
#include <strsafe.h>
#include <utility>
#include <vector>

namespace bsl::windows {
namespace {
std::wstring UserSid(HANDLE process) {
  HANDLE token = nullptr;
  if (!OpenProcessToken(process, TOKEN_QUERY, &token)) return {};
  DWORD bytes = 0;
  GetTokenInformation(token, TokenUser, nullptr, 0, &bytes);
  std::vector<BYTE> buffer(bytes);
  const bool read = bytes != 0 &&
      GetTokenInformation(token, TokenUser, buffer.data(), bytes, &bytes);
  CloseHandle(token);
  if (!read) return {};
  LPWSTR text = nullptr;
  if (!ConvertSidToStringSidW(
          reinterpret_cast<TOKEN_USER*>(buffer.data())->User.Sid, &text)) {
    return {};
  }
  const std::wstring sid(text);
  LocalFree(text);
  return sid;
}

bool IsBlackSpiritLifeImage(HANDLE process) {
  std::vector<wchar_t> path(32768);
  DWORD length = static_cast<DWORD>(path.size());
  if (!QueryFullProcessImageNameW(process, 0, path.data(), &length)) return false;
  const std::wstring image(path.data(), length);
  const auto separator = image.find_last_of(L"\\/");
  if (_wcsicmp(image.substr(separator == std::wstring::npos ? 0 : separator + 1)
                   .c_str(), L"BlackSpiritLife.exe") != 0) return false;
  DWORD ignored = 0;
  const DWORD bytes = GetFileVersionInfoSizeW(image.c_str(), &ignored);
  if (bytes == 0 || bytes > 1024 * 1024) return false;
  std::vector<BYTE> version(bytes);
  if (!GetFileVersionInfoW(image.c_str(), 0, bytes, version.data())) return false;
  struct Translation { WORD language; WORD codepage; };
  Translation* translations = nullptr;
  UINT translation_bytes = 0;
  if (!VerQueryValueW(version.data(), L"\\VarFileInfo\\Translation",
                      reinterpret_cast<void**>(&translations),
                      &translation_bytes)) return false;
  for (UINT i = 0; i < translation_bytes / sizeof(Translation); ++i) {
    wchar_t query[96];
    StringCchPrintfW(query, 96, L"\\StringFileInfo\\%04x%04x\\ProductName",
                     translations[i].language, translations[i].codepage);
    wchar_t* product = nullptr;
    UINT characters = 0;
    if (VerQueryValueW(version.data(), query, reinterpret_cast<void**>(&product),
                       &characters) && characters > 0 &&
        std::wstring(product, characters - 1) == L"Black Spirit Life") return true;
  }
  return false;
}
}  // namespace

SingleInstance::SingleInstance(std::wstring identity)
    : identity_(std::move(identity)), user_sid_(UserSid(GetCurrentProcess())) {
  property_ = identity_ + L"." + user_sid_;
  activate_message_ = RegisterWindowMessageW((identity_ + L".Activate").c_str());
}

SingleInstance::~SingleInstance() {
  if (window_ != nullptr) {
    RemovePropW(window_, property_.c_str());
    RemoveWindowSubclass(window_, WindowProc, reinterpret_cast<UINT_PTR>(this));
  }
  if (acquired_) ReleaseMutex(mutex_);
  if (mutex_ != nullptr) CloseHandle(mutex_);
}

SingleInstance::Result SingleInstance::AcquireOrActivate(DWORD timeout_ms) {
  if (acquired_) return Result::primary;
  if (user_sid_.empty() || activate_message_ == 0) return Result::unavailable;
  // Released/previously built copies cannot answer the new activation message.
  // Identify their actual main window before claiming a new UI instance, even
  // when a failed newer copy already owns the UI mutex. No saved files are read.
  if (const HWND legacy = FindLegacyWindow()) {
    return ActivateLegacy(legacy, timeout_ms);
  }
  if (mutex_ == nullptr) {
    const std::wstring name = L"Local\\" + property_;
    mutex_ = CreateMutexW(nullptr, FALSE, name.c_str());
    if (mutex_ == nullptr) return Result::unavailable;
  }
  const ULONGLONG deadline = GetTickCount64() + timeout_ms;
  do {
    const DWORD wait = WaitForSingleObject(mutex_, 0);
    if (wait == WAIT_OBJECT_0 || wait == WAIT_ABANDONED) {
      acquired_ = true;
      return Result::primary;
    }
    if (wait != WAIT_TIMEOUT) return Result::unavailable;
    found_ = nullptr;
    EnumWindows(FindWindowCallback, reinterpret_cast<LPARAM>(this));
    if (found_ != nullptr) {
      DWORD process_id = 0;
      GetWindowThreadProcessId(found_, &process_id);
      // The user-launched secondary grants foreground permission to the owner.
      // Windows may still deny focus; the owner then flashes its taskbar button.
      AllowSetForegroundWindow(process_id);
      DWORD_PTR acknowledged = 0;
      if (SendMessageTimeoutW(found_, activate_message_, 0, 0,
                              SMTO_ABORTIFHUNG | SMTO_BLOCK, 250,
                              &acknowledged) && acknowledged == 1) {
        return Result::forwarded;
      }
    }
    if (GetTickCount64() >= deadline) break;
    Sleep(40);
  } while (true);
  // Never start a competing writer if the owner is starting or unresponsive.
  return Result::unavailable;
}

HWND SingleInstance::FindLegacyWindow() {
  found_ = nullptr;
  legacy_creation_ = ~ULONGLONG{0};
  if (!user_sid_.empty()) {
    EnumWindows(FindLegacyWindowCallback, reinterpret_cast<LPARAM>(this));
  }
  return found_;
}

BOOL CALLBACK SingleInstance::FindLegacyWindowCallback(HWND window,
                                                       LPARAM parameter) {
  auto* self = reinterpret_cast<SingleInstance*>(parameter);
  if (GetWindow(window, GW_OWNER) != nullptr ||
      GetPropW(window, self->property_.c_str()) != nullptr) return TRUE;
  wchar_t class_name[128]{};
  wchar_t title[128]{};
  GetClassNameW(window, class_name, 128);
  GetWindowTextW(window, title, 128);
  if (wcscmp(class_name, L"FLUTTER_RUNNER_WIN32_WINDOW") != 0 ||
      wcscmp(title, L"Black Spirit Life") != 0) return TRUE;
  DWORD pid = 0;
  GetWindowThreadProcessId(window, &pid);
  DWORD session = 0, own_session = 0;
  if (pid == GetCurrentProcessId() ||
      !ProcessIdToSessionId(pid, &session) ||
      !ProcessIdToSessionId(GetCurrentProcessId(), &own_session) ||
      session != own_session) return TRUE;
  const HANDLE process = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, FALSE, pid);
  if (process == nullptr) return TRUE;
  FILETIME creation{}, exit{}, kernel{}, user{};
  const bool matches = UserSid(process) == self->user_sid_ &&
      IsBlackSpiritLifeImage(process) &&
      GetProcessTimes(process, &creation, &exit, &kernel, &user);
  CloseHandle(process);
  if (matches) {
    const ULONGLONG created = (static_cast<ULONGLONG>(creation.dwHighDateTime) << 32)
                              | creation.dwLowDateTime;
    // If an older build has also opened an error window, prefer the original
    // process rather than the last duplicate that happened to be foreground.
    if (created < self->legacy_creation_) {
      self->legacy_creation_ = created;
      self->found_ = window;
    }
  }
  return TRUE;
}

SingleInstance::Result SingleInstance::ActivateLegacy(HWND window,
                                                      DWORD timeout_ms) {
  const ULONGLONG deadline = GetTickCount64() + timeout_ms;
  DWORD expected_pid = 0;
  GetWindowThreadProcessId(window, &expected_pid);
  do {
    DWORD pid = 0;
    if (!IsWindow(window) || !GetWindowThreadProcessId(window, &pid) ||
        pid != expected_pid) return Result::unavailable;
    DWORD_PTR response = 0;
    if (IsWindowVisible(window) &&
        SendMessageTimeoutW(window, WM_NULL, 0, 0,
                            SMTO_ABORTIFHUNG | SMTO_BLOCK, 250, &response)) {
      if (IsIconic(window) &&
          !SendMessageTimeoutW(window, WM_SYSCOMMAND, SC_RESTORE, 0,
                               SMTO_ABORTIFHUNG | SMTO_BLOCK, 250, &response)) {
        return Result::unavailable;
      }
      const HWND popup = GetLastActivePopup(window);
      const HWND target = popup != nullptr && IsWindowVisible(popup) ? popup : window;
      // The secondary process owns the user's launch foreground permission.
      // Do not send the new protocol to a binary that does not implement it.
      if (!SetForegroundWindow(target)) {
        FLASHWINFO flash{sizeof(FLASHWINFO), window, FLASHW_TRAY, 3, 0};
        FlashWindowEx(&flash);
      }
      return Result::forwarded;
    }
    if (GetTickCount64() >= deadline) break;
    Sleep(40);
  } while (true);
  return Result::unavailable;
}

BOOL CALLBACK SingleInstance::FindWindowCallback(HWND window, LPARAM parameter) {
  auto* self = reinterpret_cast<SingleInstance*>(parameter);
  if (!IsWindowVisible(window) || GetWindow(window, GW_OWNER) != nullptr ||
      GetPropW(window, self->property_.c_str()) != reinterpret_cast<HANDLE>(1)) {
    return TRUE;
  }
  DWORD process_id = 0;
  GetWindowThreadProcessId(window, &process_id);
  if (process_id == GetCurrentProcessId()) return TRUE;
  const HANDLE process = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, FALSE,
                                     process_id);
  if (process == nullptr) return TRUE;
  const bool same_user = UserSid(process) == self->user_sid_;
  CloseHandle(process);
  if (!same_user) return TRUE;
  self->found_ = window;
  return FALSE;
}

bool SingleInstance::AttachWindow(HWND window) {
  if (!acquired_ || window_ != nullptr || !IsWindow(window)) return false;
  if (!SetWindowSubclass(window, WindowProc, reinterpret_cast<UINT_PTR>(this),
                         reinterpret_cast<DWORD_PTR>(this))) return false;
  if (!SetPropW(window, property_.c_str(), reinterpret_cast<HANDLE>(1))) {
    RemoveWindowSubclass(window, WindowProc, reinterpret_cast<UINT_PTR>(this));
    return false;
  }
  window_ = window;
  return true;
}

void SingleInstance::Activate(HWND window) {
  if (IsIconic(window)) ShowWindow(window, SW_RESTORE);
  // Keep a native modal in front of its disabled owner, and retain maximization.
  const HWND popup = GetLastActivePopup(window);
  const HWND target = popup != nullptr && IsWindowVisible(popup) ? popup : window;
  if (!SetForegroundWindow(target)) {
    FLASHWINFO flash{sizeof(FLASHWINFO), window, FLASHW_TRAY, 3, 0};
    FlashWindowEx(&flash);
  }
}

LRESULT CALLBACK SingleInstance::WindowProc(HWND window, UINT message,
                                            WPARAM wparam, LPARAM lparam,
                                            UINT_PTR id, DWORD_PTR reference) {
  auto* self = reinterpret_cast<SingleInstance*>(reference);
  if (message == self->activate_message_) {
    self->Activate(window);
    return 1;
  }
  if (message == WM_NCDESTROY) {
    RemovePropW(window, self->property_.c_str());
    RemoveWindowSubclass(window, WindowProc, id);
    self->window_ = nullptr;
  }
  return DefSubclassProc(window, message, wparam, lparam);
}
}  // namespace bsl::windows
