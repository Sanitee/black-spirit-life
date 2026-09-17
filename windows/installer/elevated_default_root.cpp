#include "elevated_default_root.h"

#include <windows.h>

#include <aclapi.h>
#include <objbase.h>
#include <sddl.h>
#include <shellapi.h>

#include <cstring>
#include <string>
#include <vector>

#include "installed_beta_locator.h"

namespace bsl::installer {
namespace {

constexpr wchar_t kPrepareArgument[] =
    L"--prepare-default-root-for-user";

std::wstring NormalizePath(const std::wstring &input) {
  if (input.empty())
    return {};
  const DWORD required = GetFullPathNameW(input.c_str(), 0, nullptr, nullptr);
  if (required == 0)
    return {};
  std::wstring buffer(required, L'\0');
  const DWORD written =
      GetFullPathNameW(input.c_str(), required, buffer.data(), nullptr);
  if (written == 0 || written >= required)
    return {};
  buffer.resize(written);
  while (buffer.size() > 3 &&
         (buffer.back() == L'\\' || buffer.back() == L'/')) {
    buffer.pop_back();
  }
  return buffer;
}

bool SamePath(const std::wstring &left, const std::wstring &right) {
  const std::wstring normalized_left = NormalizePath(left);
  const std::wstring normalized_right = NormalizePath(right);
  return !normalized_left.empty() && !normalized_right.empty() &&
         _wcsicmp(normalized_left.c_str(), normalized_right.c_str()) == 0;
}

bool IsMissingError(DWORD error) {
  return error == ERROR_FILE_NOT_FOUND || error == ERROR_PATH_NOT_FOUND;
}

bool ProcessIsElevated() {
  HANDLE token = nullptr;
  if (!OpenProcessToken(GetCurrentProcess(), TOKEN_QUERY, &token))
    return false;
  TOKEN_ELEVATION elevation{};
  DWORD returned = 0;
  const bool elevated =
      GetTokenInformation(token, TokenElevation, &elevation,
                          sizeof(elevation), &returned) &&
      elevation.TokenIsElevated != 0;
  CloseHandle(token);
  return elevated;
}

bool IsSupportedAccountSid(PSID sid) {
  if (sid == nullptr || !IsValidSid(sid))
    return false;
  const SID_IDENTIFIER_AUTHORITY *authority =
      GetSidIdentifierAuthority(sid);
  const UCHAR count = *GetSidSubAuthorityCount(sid);
  if (authority == nullptr || count == 0)
    return false;
  const DWORD first = *GetSidSubAuthority(sid, 0);
  const SID_IDENTIFIER_AUTHORITY nt_authority = SECURITY_NT_AUTHORITY;
  if (std::memcmp(authority, &nt_authority, sizeof(nt_authority)) == 0)
    return first == SECURITY_NT_NON_UNIQUE && count >= 4;
  // Microsoft Entra ID user SIDs use S-1-12-1-... on joined devices.
  const SID_IDENTIFIER_AUTHORITY entra_authority = {{0, 0, 0, 0, 0, 12}};
  return std::memcmp(authority, &entra_authority, sizeof(entra_authority)) ==
             0 &&
         first == 1 && count >= 5;
}

bool CurrentUserSidString(std::wstring *sid_string, std::wstring *error) {
  if (sid_string)
    sid_string->clear();
  HANDLE token = nullptr;
  if (!OpenProcessToken(GetCurrentProcess(), TOKEN_QUERY, &token)) {
    if (error)
      *error = L"The current Windows account could not be identified.";
    return false;
  }
  DWORD required = 0;
  GetTokenInformation(token, TokenUser, nullptr, 0, &required);
  std::vector<unsigned char> bytes(required);
  const bool read = required != 0 &&
      GetTokenInformation(token, TokenUser, bytes.data(), required, &required);
  CloseHandle(token);
  if (!read) {
    if (error)
      *error = L"The current Windows account could not be identified.";
    return false;
  }
  const auto *user = reinterpret_cast<const TOKEN_USER *>(bytes.data());
  if (!IsSupportedAccountSid(user->User.Sid)) {
    if (error)
      *error = L"The current Windows account cannot own this installation.";
    return false;
  }
  LPWSTR converted = nullptr;
  if (!ConvertSidToStringSidW(user->User.Sid, &converted) ||
      converted == nullptr) {
    if (error)
      *error = L"The current Windows account could not be identified.";
    return false;
  }
  if (sid_string)
    *sid_string = converted;
  LocalFree(converted);
  return true;
}

std::wstring CurrentExecutablePath() {
  std::vector<wchar_t> buffer(32768, L'\0');
  const DWORD written = GetModuleFileNameW(
      nullptr, buffer.data(), static_cast<DWORD>(buffer.size()));
  if (written == 0 || written >= buffer.size())
    return {};
  return std::wstring(buffer.data(), written);
}

void RollBackCreatedEmptyDirectory(HANDLE directory) {
  FILE_DISPOSITION_INFO disposition{TRUE};
  SetFileInformationByHandle(directory, FileDispositionInfo, &disposition,
                             sizeof(disposition));
}

bool GrantAccountFullControl(HANDLE directory, PSID user_sid) {
  PACL current_dacl = nullptr;
  PSECURITY_DESCRIPTOR descriptor = nullptr;
  DWORD result = GetSecurityInfo(directory, SE_FILE_OBJECT,
                                 DACL_SECURITY_INFORMATION, nullptr, nullptr,
                                 &current_dacl, nullptr, &descriptor);
  if (result != ERROR_SUCCESS)
    return false;

  EXPLICIT_ACCESSW access{};
  access.grfAccessPermissions = FILE_ALL_ACCESS;
  access.grfAccessMode = GRANT_ACCESS;
  access.grfInheritance = SUB_CONTAINERS_AND_OBJECTS_INHERIT;
  access.Trustee.TrusteeForm = TRUSTEE_IS_SID;
  access.Trustee.TrusteeType = TRUSTEE_IS_USER;
  access.Trustee.ptstrName = static_cast<LPWSTR>(user_sid);

  PACL updated_dacl = nullptr;
  result = SetEntriesInAclW(1, &access, current_dacl, &updated_dacl);
  if (result == ERROR_SUCCESS) {
    result = SetSecurityInfo(directory, SE_FILE_OBJECT,
                             DACL_SECURITY_INFORMATION, nullptr, nullptr,
                             updated_dacl, nullptr);
  }
  if (updated_dacl != nullptr)
    LocalFree(updated_dacl);
  if (descriptor != nullptr)
    LocalFree(descriptor);
  return result == ERROR_SUCCESS;
}

bool CreateElevatedDefaultRoot(const std::wstring &sid_string) {
  if (!ProcessIsElevated())
    return false;

  PSID user_sid = nullptr;
  if (!ConvertStringSidToSidW(sid_string.c_str(), &user_sid) ||
      !IsSupportedAccountSid(user_sid)) {
    if (user_sid != nullptr)
      LocalFree(user_sid);
    return false;
  }

  const std::wstring root = DefaultInstallPath();
  const DWORD attributes = GetFileAttributesW(root.c_str());
  if (attributes != INVALID_FILE_ATTRIBUTES || !IsMissingError(GetLastError())) {
    LocalFree(user_sid);
    return false;
  }
  if (!CreateDirectoryW(root.c_str(), nullptr)) {
    LocalFree(user_sid);
    return false;
  }

  HANDLE directory = CreateFileW(
      root.c_str(), FILE_READ_ATTRIBUTES | READ_CONTROL | WRITE_DAC | DELETE,
      FILE_SHARE_READ | FILE_SHARE_WRITE, nullptr, OPEN_EXISTING,
      FILE_FLAG_BACKUP_SEMANTICS | FILE_FLAG_OPEN_REPARSE_POINT, nullptr);
  BY_HANDLE_FILE_INFORMATION information{};
  const bool ordinary = directory != INVALID_HANDLE_VALUE &&
      GetFileInformationByHandle(directory, &information) &&
      (information.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY) != 0 &&
      (information.dwFileAttributes & FILE_ATTRIBUTE_REPARSE_POINT) == 0;
  const bool granted = ordinary && GrantAccountFullControl(directory, user_sid);
  LocalFree(user_sid);
  if (!granted && directory != INVALID_HANDLE_VALUE)
    RollBackCreatedEmptyDirectory(directory);
  if (directory != INVALID_HANDLE_VALUE)
    CloseHandle(directory);
  return granted;
}

} // namespace

bool IsDefaultInstallRootPath(const std::wstring &root) {
  return SamePath(root, DefaultInstallPath());
}

bool PrepareDefaultInstallRootWithElevation(const std::wstring &root,
                                            bool *created,
                                            std::wstring *error) {
  if (created)
    *created = false;
  if (error)
    error->clear();
  if (!IsDefaultInstallRootPath(root)) {
    if (error)
      *error = L"Only C:\\Black Spirit Life may use the elevated folder "
               L"preparation step.";
    return false;
  }
  const DWORD attributes = GetFileAttributesW(DefaultInstallPath().c_str());
  if (attributes != INVALID_FILE_ATTRIBUTES) {
    if (error)
      *error = L"The default installation folder already exists and was not "
               L"changed.";
    return false;
  }
  const DWORD missing_error = GetLastError();
  if (!IsMissingError(missing_error)) {
    if (error)
      *error = L"The default installation folder could not be inspected "
               L"safely. Nothing was changed.";
    return false;
  }

  std::wstring sid;
  if (!CurrentUserSidString(&sid, error))
    return false;
  const std::wstring executable = CurrentExecutablePath();
  if (executable.empty()) {
    if (error)
      *error = L"The installer could not start its Windows permission step.";
    return false;
  }
  const std::wstring parameters =
      std::wstring(kPrepareArgument) + L" " + sid;
  SHELLEXECUTEINFOW execute{sizeof(execute)};
  execute.fMask = SEE_MASK_NOCLOSEPROCESS | SEE_MASK_NOASYNC;
  execute.lpVerb = L"runas";
  execute.lpFile = executable.c_str();
  execute.lpParameters = parameters.c_str();
  execute.nShow = SW_HIDE;
  const HRESULT com = CoInitializeEx(
      nullptr, COINIT_APARTMENTTHREADED | COINIT_DISABLE_OLE1DDE);
  const bool started = ShellExecuteExW(&execute) != FALSE;
  const DWORD start_error = started ? ERROR_SUCCESS : GetLastError();
  if (SUCCEEDED(com))
    CoUninitialize();
  if (!started || execute.hProcess == nullptr) {
    if (error) {
      *error = start_error == ERROR_CANCELLED
                   ? L"Windows permission was not approved. No application "
                     L"files or personal data were changed."
                   : L"Windows could not create C:\\Black Spirit Life. No "
                     L"application files or personal data were changed.";
    }
    return false;
  }

  const DWORD wait = WaitForSingleObject(execute.hProcess, INFINITE);
  DWORD exit_code = 1;
  const bool finished = wait == WAIT_OBJECT_0 &&
      GetExitCodeProcess(execute.hProcess, &exit_code);
  CloseHandle(execute.hProcess);
  if (!finished || exit_code != 0) {
    if (error)
      *error = L"Windows could not prepare C:\\Black Spirit Life safely. "
               L"No application files or personal data were changed.";
    return false;
  }
  if (created)
    *created = true;
  return true;
}

int RunElevatedDefaultRootPreparation(const std::wstring &user_sid) {
  return CreateElevatedDefaultRoot(user_sid) ? 0 : 8;
}

} // namespace bsl::installer
