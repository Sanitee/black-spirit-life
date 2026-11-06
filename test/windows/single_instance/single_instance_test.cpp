#include "single_instance.h"
#include <iostream>
#include <string>
#include <vector>

using bsl::windows::SingleInstance;
namespace {
constexpr wchar_t kClass[] = L"BSL_ISOLATED_SINGLE_INSTANCE_TEST";
int checks = 0;
int failures = 0;
HWND modal = nullptr;
void Check(bool pass, const char* text) {
  ++checks;
  if (!pass) ++failures;
  std::cout << (pass ? "PASS " : "FAIL ") << text << std::endl;
}
LRESULT CALLBACK Proc(HWND window, UINT message, WPARAM wp, LPARAM lp) {
  if (message == WM_APP + 1) { ShowWindow(window, SW_MINIMIZE); return 1; }
  if (message == WM_APP + 2) { ShowWindow(window, SW_MAXIMIZE); return 1; }
  if (message == WM_APP + 3) {
    modal = CreateWindowW(kClass, L"Test modal", WS_OVERLAPPEDWINDOW,
                          0, 0, 200, 100, window, nullptr,
                          GetModuleHandle(nullptr), nullptr);
    EnableWindow(window, FALSE);
    ShowWindow(modal, SW_SHOW);
    return reinterpret_cast<LRESULT>(modal);
  }
  if (message == WM_APP + 4) {
    if (modal) DestroyWindow(modal);
    modal = nullptr;
    EnableWindow(window, TRUE);
    return 1;
  }
  return DefWindowProc(window, message, wp, lp);
}
bool Register() {
  WNDCLASSW c{}; c.lpfnWndProc = Proc;
  c.hInstance = GetModuleHandle(nullptr); c.lpszClassName = kClass;
  return RegisterClassW(&c) != 0;
}
HWND Window() {
  return CreateWindowW(kClass, L"Synthetic planner", WS_OVERLAPPEDWINDOW,
                        0, 0, 500, 300, nullptr, nullptr,
                        GetModuleHandle(nullptr), nullptr);
}
HANDLE Event(const std::wstring& key, const wchar_t* suffix) {
  return CreateEventW(nullptr, TRUE, FALSE, (L"Local\\" + key + suffix).c_str());
}
struct Child {
  HANDLE process = nullptr;
  HANDLE thread = nullptr;
  DWORD pid = 0;
};
Child Start(const std::wstring& exe, const std::wstring& key,
            const std::wstring& desktop, const wchar_t* mode) {
  std::wstring command = L"\"" + exe + L"\" " + mode + L" " + key;
  STARTUPINFOW startup{}; startup.cb = sizeof(startup);
  startup.lpDesktop = const_cast<LPWSTR>(desktop.c_str());
  PROCESS_INFORMATION info{};
  if (!CreateProcessW(exe.c_str(), command.data(), nullptr, nullptr, FALSE,
                       CREATE_NO_WINDOW, nullptr, nullptr, &startup, &info)) {
    return {};
  }
  return {info.hProcess, info.hThread, info.dwProcessId};
}
DWORD Finish(Child& child, DWORD timeout = 12000) {
  if (!child.process) return 999;
  if (WaitForSingleObject(child.process, timeout) != WAIT_OBJECT_0) {
    // Only this harness's own synthetic child can reach this cleanup path.
    TerminateProcess(child.process, 998);
    WaitForSingleObject(child.process, 2000);
  }
  DWORD code = 997; GetExitCodeProcess(child.process, &code);
  CloseHandle(child.thread); CloseHandle(child.process); child = {};
  return code;
}
struct Lookup { DWORD pid; HWND window = nullptr; };
BOOL CALLBACK Find(HWND window, LPARAM value) {
  auto* lookup = reinterpret_cast<Lookup*>(value);
  DWORD pid = 0; GetWindowThreadProcessId(window, &pid);
  if (pid == lookup->pid && GetWindow(window, GW_OWNER) == nullptr) {
    lookup->window = window; return FALSE;
  }
  return TRUE;
}
HWND FindChild(DWORD pid) {
  Lookup lookup{pid}; EnumWindows(Find, reinterpret_cast<LPARAM>(&lookup));
  return lookup.window;
}
int ChildMain(const std::wstring& mode, const std::wstring& key) {
  if (mode == L"--legacy" || mode == L"--legacy-helper") {
    // Old binary simulation: exact old window identity, no new mutex/property/
    // message handler, and an independently held synthetic saved-data lease.
    if (!Register()) return 30;
    WNDCLASSW c{}; c.lpfnWndProc = Proc;
    c.hInstance = GetModuleHandle(nullptr);
    c.lpszClassName = L"FLUTTER_RUNNER_WIN32_WINDOW";
    if (!RegisterClassW(&c)) return 31;
    wchar_t image[32768]{}; GetModuleFileNameW(nullptr, image, 32768);
    const std::wstring executable(image);
    const std::wstring lease_path = executable.substr(0, executable.find_last_of(L"\\"))
        + L"\\synthetic-writer.lock";
    HANDLE lease = CreateFileW(lease_path.c_str(), GENERIC_READ | GENERIC_WRITE,
        FILE_SHARE_READ | FILE_SHARE_WRITE, nullptr, OPEN_ALWAYS, FILE_ATTRIBUTE_NORMAL, nullptr);
    OVERLAPPED range{};
    if (lease == INVALID_HANDLE_VALUE ||
        !LockFileEx(lease, LOCKFILE_EXCLUSIVE_LOCK | LOCKFILE_FAIL_IMMEDIATELY, 0, 1, 0, &range)) return 32;
    const HWND window = CreateWindowW(c.lpszClassName,
        mode == L"--legacy-helper" ? L"Minigame Helper" : L"Black Spirit Life",
        WS_OVERLAPPEDWINDOW, 0, 0, 500, 300, nullptr, nullptr, c.hInstance, nullptr);
    if (!window) return 33;
    ShowWindow(window, SW_SHOWNOACTIVATE);
    HANDLE acquired = Event(key, L".Acquired");
    HANDLE stop = Event(key, L".Stop");
    SetEvent(acquired);
    const ULONGLONG deadline = GetTickCount64() + 20000;
    while (WaitForSingleObject(stop, 0) == WAIT_TIMEOUT && GetTickCount64() < deadline) {
      MSG message;
      while (PeekMessageW(&message, nullptr, 0, 0, PM_REMOVE)) {
        TranslateMessage(&message); DispatchMessageW(&message);
      }
      Sleep(5);
    }
    DestroyWindow(window); CloseHandle(lease);
    CloseHandle(acquired); CloseHandle(stop);
    return 0;
  }
  SingleInstance coordinator(key);
  const auto result = coordinator.AcquireOrActivate(5000);
  if (mode == L"--secondary") {
    return result == SingleInstance::Result::forwarded ? 0 : 20;
  }
  if (result != SingleInstance::Result::primary) return 21;
  HANDLE acquired = Event(key, L".Acquired");
  HANDLE stop = Event(key, L".Stop");
  SetEvent(acquired);
  Sleep(400);  // A real competing launch must wait for initial window setup.
  if (!Register()) return 22;
  HWND window = Window();
  if (!window || !coordinator.AttachWindow(window)) return 23;
  if (mode != L"--hidden") ShowWindow(window, SW_SHOWNOACTIVATE);
  const ULONGLONG deadline = GetTickCount64() + 20000;
  while (WaitForSingleObject(stop, 0) == WAIT_TIMEOUT &&
         GetTickCount64() < deadline) {
    MSG message;
    while (PeekMessageW(&message, nullptr, 0, 0, PM_REMOVE)) {
      TranslateMessage(&message); DispatchMessageW(&message);
    }
    Sleep(5);
  }
  if (modal) DestroyWindow(modal);
  DestroyWindow(window);
  CloseHandle(acquired); CloseHandle(stop);
  return 0;
}
}  // namespace

int wmain(int argc, wchar_t** argv) {
  if (argc == 2 && std::wstring(argv[1]) == L"--inspect-legacy") {
#if BSL_TEST_LEGACY_DISCOVERY
    // Metadata-only diagnostic: no acquisition, activation, app launch or files.
    SingleInstance probe;
    DWORD pid = 0;
    if (const HWND window = probe.FindLegacyWindow()) GetWindowThreadProcessId(window, &pid);
    std::cout << "legacyCandidatePid=" << pid << std::endl;
    return 0;
#else
    return 40;
#endif
  }
  if (argc == 3) return ChildMain(argv[1], argv[2]);
  // Never display test windows or send input on the user's desktop. No Flutter,
  // app executable, profile, real lock namespace, or Fish service is started.
  const std::wstring unique = L"BSL.SingleInstance.Tests." +
      std::to_wstring(GetCurrentProcessId()) + L"." + std::to_wstring(GetTickCount64());
  const std::wstring desktop_name = unique + L".Desktop";
  const HDESK original = GetThreadDesktop(GetCurrentThreadId());
  const HDESK desktop = CreateDesktopW(desktop_name.c_str(), nullptr, nullptr,
                                      0, GENERIC_ALL, nullptr);
  Check(desktop != nullptr && SetThreadDesktop(desktop), "private test desktop");
  if (failures) return 1;
  wchar_t buffer[32768]; GetModuleFileNameW(nullptr, buffer, 32768);
  const std::wstring exe(buffer);
  const std::wstring full_desktop = L"WinSta0\\" + desktop_name;
  HANDLE acquired = Event(unique, L".Acquired");
  HANDLE stop = Event(unique, L".Stop");
  Child primary = Start(exe, unique, full_desktop, L"--primary");
  Check(primary.process && WaitForSingleObject(acquired, 5000) == WAIT_OBJECT_0,
        "first process alone claims the instance");
  {
    SingleInstance second(unique);
    Check(second.AcquireOrActivate(5000) == SingleInstance::Result::forwarded,
          "launch during startup waits, activates owner, and never becomes writer");
  }
  const HWND owner = FindChild(primary.pid);
  Check(owner != nullptr, "owner window is discoverable on private desktop");
  if (owner) {
    SendMessageW(owner, WM_APP + 1, 0, 0);
    Check(IsIconic(owner), "fixture minimized");
    { SingleInstance second(unique);
      Check(second.AcquireOrActivate(2000) == SingleInstance::Result::forwarded,
            "minimized owner accepts repeat launch"); }
    Check(!IsIconic(owner), "repeat launch restores minimized window");
    SendMessageW(owner, WM_APP + 2, 0, 0);
    { SingleInstance second(unique);
      Check(second.AcquireOrActivate(2000) == SingleInstance::Result::forwarded,
            "maximized owner accepts repeat launch"); }
    Check(IsZoomed(owner), "repeat launch retains maximized state");
    const auto popup = reinterpret_cast<HWND>(SendMessageW(owner, WM_APP + 3, 0, 0));
    { SingleInstance second(unique);
      Check(second.AcquireOrActivate(2000) == SingleInstance::Result::forwarded,
            "modal owner accepts repeat launch"); }
    Check(popup && IsWindowVisible(popup) && !IsWindowEnabled(owner),
          "repeat launch preserves open modal and disabled owner");
    SendMessageW(owner, WM_APP + 4, 0, 0);
  }
  std::vector<Child> repeats;
  for (int i = 0; i < 6; ++i) repeats.push_back(Start(exe, unique, full_desktop, L"--secondary"));
  bool all_forwarded = true;
  for (auto& child : repeats) all_forwarded = Finish(child) == 0 && all_forwarded;
  Check(all_forwarded, "six simultaneous launches all forward without a second startup");
  wchar_t temporary[32768]{};
  const DWORD temp_length = GetTempPathW(32768, temporary);
  const std::wstring copied_folder = std::wstring(temporary) + unique;
  const std::wstring copied_exe = copied_folder + L"\\another-build.exe";
  const bool copied = temp_length > 0 && temp_length < 32768 &&
      CreateDirectoryW(copied_folder.c_str(), nullptr) &&
      CopyFileW(exe.c_str(), copied_exe.c_str(), TRUE);
  Check(copied, "isolated second build path prepared");
  if (copied) {
    Child different_build = Start(copied_exe, unique, full_desktop, L"--secondary");
    Check(Finish(different_build) == 0,
          "different executable path forwards to the same user instance");
    Check(DeleteFileW(copied_exe.c_str()) && RemoveDirectoryW(copied_folder.c_str()),
          "only disposable native test copy removed");
  }
  SetEvent(stop);
  Check(Finish(primary) == 0, "clean primary exit");
  { SingleInstance next(unique);
    Check(next.AcquireOrActivate(0) == SingleInstance::Result::primary,
          "reopen after normal exit becomes primary"); }
  ResetEvent(stop); ResetEvent(acquired);
  primary = Start(exe, unique, full_desktop, L"--hidden");
  Check(primary.process && WaitForSingleObject(acquired, 5000) == WAIT_OBJECT_0,
        "hidden startup fixture holds lease");
  { SingleInstance other(unique);
    Check(other.AcquireOrActivate(650) == SingleInstance::Result::unavailable,
          "unready owner times out safely, without starting a writer");
    if (primary.process) TerminateProcess(primary.process, 90);
    Check(Finish(primary) == 90, "only synthetic primary is terminated for crash test");
    Check(other.AcquireOrActivate(2000) == SingleInstance::Result::primary,
          "waiting contender safely takes an abandoned mutex after owner crash"); }
  { SingleInstance next(unique);
    Check(next.AcquireOrActivate(2000) == SingleInstance::Result::primary,
          "crashed owner releases mutex; no stale instance file"); }
  { SingleInstance separate(unique + L".Separate");
    Check(separate.AcquireOrActivate(0) == SingleInstance::Result::primary,
          "independent test namespace does not affect application namespace");
    Check(!separate.AttachWindow(nullptr), "invalid window cannot publish an owner"); }

  const std::wstring legacy_folder = std::wstring(temporary) + unique + L".Legacy";
  const std::wstring legacy_exe = legacy_folder + L"\\BlackSpiritLife.exe";
  const std::wstring legacy_lock = legacy_folder + L"\\synthetic-writer.lock";
  const bool legacy_copied = CreateDirectoryW(legacy_folder.c_str(), nullptr) &&
      CopyFileW(exe.c_str(), legacy_exe.c_str(), TRUE);
  Check(legacy_copied, "old-build fixture has real executable/version/window identity");
  if (legacy_copied) {
    ResetEvent(stop); ResetEvent(acquired);
    Child legacy = Start(legacy_exe, unique, full_desktop, L"--legacy");
    Check(legacy.process && WaitForSingleObject(acquired, 5000) == WAIT_OBJECT_0,
          "older unmodified-protocol fixture is already open");
    HWND legacy_window = FindChild(legacy.pid);
    Check(legacy_window != nullptr, "older fixture main window found");
    HANDLE lease_probe = CreateFileW(legacy_lock.c_str(), GENERIC_READ | GENERIC_WRITE,
        FILE_SHARE_READ | FILE_SHARE_WRITE, nullptr, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, nullptr);
    OVERLAPPED range{};
    const BOOL locked = lease_probe != INVALID_HANDLE_VALUE &&
        LockFileEx(lease_probe, LOCKFILE_EXCLUSIVE_LOCK | LOCKFILE_FAIL_IMMEDIATELY, 0, 1, 0, &range);
    const DWORD lock_error = GetLastError();
    Check(!locked && lock_error == ERROR_LOCK_VIOLATION,
          "reproduction: older fixture holds shared-data lease");
    if (lease_probe != INVALID_HANDLE_VALUE) CloseHandle(lease_probe);
    { SingleInstance second(unique);
#if BSL_TEST_LEGACY_DISCOVERY
      Check(second.FindLegacyWindow() == legacy_window, "read-only legacy discovery matches exact older owner");
#endif
      Check(second.AcquireOrActivate(2000) == SingleInstance::Result::forwarded,
            "new launch redirects to older build BEFORE attempting saved-data startup"); }
    if (legacy_window) {
      SendMessageW(legacy_window, WM_APP + 1, 0, 0);
      { SingleInstance second(unique);
        Check(second.AcquireOrActivate(2000) == SingleInstance::Result::forwarded,
              "legacy minimized window accepts repeat launch without new protocol"); }
      Check(!IsIconic(legacy_window), "legacy minimized window restored");
      SendMessageW(legacy_window, WM_APP + 2, 0, 0);
      { SingleInstance second(unique);
        Check(second.AcquireOrActivate(2000) == SingleInstance::Result::forwarded,
              "legacy maximized window accepts repeat launch"); }
      Check(IsZoomed(legacy_window), "legacy maximization retained");
    }
    { SingleInstance fresh_namespace(unique + L".SeparateBuild");
      Check(fresh_namespace.AcquireOrActivate(2000) == SingleInstance::Result::forwarded,
            "legacy detection is independent of new build mutex namespace"); }
    SetEvent(stop);
    Check(Finish(legacy) == 0, "legacy fixture exits normally");
    ResetEvent(stop); ResetEvent(acquired);
    legacy = Start(legacy_exe, unique, full_desktop, L"--legacy-helper");
    Check(legacy.process && WaitForSingleObject(acquired, 5000) == WAIT_OBJECT_0,
          "same-image helper fixture opens");
    { SingleInstance second(unique);
#if BSL_TEST_LEGACY_DISCOVERY
      Check(second.FindLegacyWindow() == nullptr, "Minigame Helper is not mistaken for the primary window");
#endif
      Check(second.AcquireOrActivate(0) == SingleInstance::Result::primary,
            "helper alone does not block normal application startup"); }
    SetEvent(stop);
    Check(Finish(legacy) == 0, "helper fixture exits normally");
    Check(DeleteFileW(legacy_lock.c_str()) && DeleteFileW(legacy_exe.c_str()) &&
              RemoveDirectoryW(legacy_folder.c_str()), "only disposable legacy fixture files removed");
  }
  CloseHandle(acquired); CloseHandle(stop);
  Check(SetThreadDesktop(original), "original thread desktop restored without switching input desktop");
  CloseDesktop(desktop);
  std::cout << checks << " checks, " << failures << " failures" << std::endl;
  return failures ? 1 : 0;
}
