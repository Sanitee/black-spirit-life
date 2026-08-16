#include "install_process_guard.h"

#include <windows.h>

#include <tlhelp32.h>

#include <algorithm>
#include <iterator>
#include <string>

namespace bsl::installer {
namespace {

std::wstring NormalizeProcessPath(const std::wstring &input) {
  if (input.empty())
    return {};
  const DWORD required = GetFullPathNameW(input.c_str(), 0, nullptr, nullptr);
  if (required == 0)
    return {};
  std::wstring result(required, L'\0');
  const DWORD written =
      GetFullPathNameW(input.c_str(), required, result.data(), nullptr);
  if (written == 0 || written >= required)
    return {};
  result.resize(written);
  while (result.size() > 3 &&
         (result.back() == L'\\' || result.back() == L'/')) {
    result.pop_back();
  }
  return result;
}

bool PathIsWithin(const std::wstring &candidate, const std::wstring &root) {
  const std::wstring normalized_candidate = NormalizeProcessPath(candidate);
  const std::wstring normalized_root = NormalizeProcessPath(root);
  if (normalized_candidate.empty() || normalized_root.empty())
    return false;
  if (_wcsicmp(normalized_candidate.c_str(), normalized_root.c_str()) == 0)
    return true;
  return normalized_candidate.size() > normalized_root.size() &&
         normalized_candidate[normalized_root.size()] == L'\\' &&
         _wcsnicmp(normalized_candidate.c_str(), normalized_root.c_str(),
                   normalized_root.size()) == 0;
}

bool IsUniqueBetaProcessName(const wchar_t *name) {
  if (name == nullptr)
    return false;
  constexpr const wchar_t *known_names[] = {L"BlackSpiritLife.exe",
                                            L"BlackSpiritLifeUpdater.exe",
                                            L"BDOActiveNodeScanner.exe"};
  return std::any_of(
      std::begin(known_names), std::end(known_names),
      [name](const wchar_t *known) { return _wcsicmp(name, known) == 0; });
}

bool IsVelopackUpdateProcessName(const wchar_t *name) {
  return name != nullptr && _wcsicmp(name, L"Update.exe") == 0;
}

} // namespace

bool EnsureNoRunningBetaProcess(const std::wstring &install_root,
                                std::wstring *error) {
  HANDLE snapshot = CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0);
  if (snapshot == INVALID_HANDLE_VALUE) {
    if (error)
      *error = L"Windows could not check whether the planner is still open.";
    return false;
  }
  PROCESSENTRY32W entry{};
  entry.dwSize = sizeof(entry);
  bool safe = true;
  bool enumeration_failed = false;
  if (!Process32FirstW(snapshot, &entry)) {
    safe = false;
    enumeration_failed = true;
  } else {
    do {
      if (entry.th32ProcessID == 0 ||
          entry.th32ProcessID == GetCurrentProcessId()) {
        continue;
      }
      if (IsUniqueBetaProcessName(entry.szExeFile)) {
        safe = false;
        break;
      }
      HANDLE process = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, FALSE,
                                   entry.th32ProcessID);
      if (process == nullptr) {
        if (IsVelopackUpdateProcessName(entry.szExeFile)) {
          safe = false;
          break;
        }
        continue;
      }
      std::wstring image(32768, L'\0');
      DWORD image_size = static_cast<DWORD>(image.size());
      const bool queried = QueryFullProcessImageNameW(process, 0, image.data(),
                                                      &image_size) != FALSE;
      CloseHandle(process);
      if (!queried) {
        if (IsVelopackUpdateProcessName(entry.szExeFile)) {
          safe = false;
          break;
        }
        continue;
      }
      image.resize(image_size);
      if (PathIsWithin(image, install_root)) {
        safe = false;
        break;
      }
    } while (Process32NextW(snapshot, &entry));
    if (safe && GetLastError() != ERROR_NO_MORE_FILES) {
      safe = false;
      enumeration_failed = true;
    }
  }
  CloseHandle(snapshot);
  if (!safe && error) {
    *error = enumeration_failed
                 ? L"Windows could not check whether the planner is still "
                   L"open. No application files were changed."
                 : L"Close Black Spirit Life and any update task, then "
                   L"try again. Your planner data was not changed.";
  }
  return safe;
}

} // namespace bsl::installer
