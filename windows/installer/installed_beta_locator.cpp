#include "installed_beta_locator.h"

#include <windows.h>

#include <algorithm>
#include <charconv>
#include <climits>
#include <cwctype>
#include <filesystem>
#include <fstream>
#include <set>
#include <sstream>
#include <string_view>
#include <vector>

#include "installer_build_config.h"

namespace bsl::installer {
namespace {

constexpr wchar_t kExecutableName[] = L"BlackSpiritLife.exe";
constexpr wchar_t kUpdaterHelperName[] = L"BlackSpiritLifeUpdater.exe";

std::wstring Trim(std::wstring value) {
  const auto first = value.find_first_not_of(L" \t\r\n");
  if (first == std::wstring::npos)
    return {};
  const auto last = value.find_last_not_of(L" \t\r\n");
  return value.substr(first, last - first + 1);
}

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
  return _wcsicmp(NormalizePath(left).c_str(), NormalizePath(right).c_str()) ==
         0;
}

bool ValidateExistingRootPath(const std::wstring &path, HANDLE *root_handle,
                              std::wstring *error) {
  if (root_handle)
    *root_handle = INVALID_HANDLE_VALUE;
  if (path.size() < 4 || !std::iswalpha(path[0]) || path[1] != L':' ||
      path[2] != L'\\' || path.rfind(L"\\\\", 0) == 0 ||
      path.rfind(L"\\\\?\\", 0) == 0 || path.rfind(L"\\\\.\\", 0) == 0) {
    if (error)
      *error = L"The installed location is not a normal local drive path.";
    return false;
  }
  wchar_t volume[MAX_PATH]{};
  if (!GetVolumePathNameW(path.c_str(), volume, MAX_PATH) ||
      GetDriveTypeW(volume) != DRIVE_FIXED || SamePath(path, volume)) {
    if (error)
      *error = L"The installed location is not on a fixed local drive.";
    return false;
  }
  std::filesystem::path current(path);
  while (!current.empty()) {
    const DWORD attributes = GetFileAttributesW(current.c_str());
    if (attributes == INVALID_FILE_ATTRIBUTES ||
        (attributes & FILE_ATTRIBUTE_REPARSE_POINT) != 0) {
      if (error)
        *error = L"The installed location redirects through a link or could "
                 L"not be verified.";
      return false;
    }
    const auto parent = current.parent_path();
    if (parent == current)
      break;
    current = parent;
  }
  HANDLE handle = CreateFileW(
      path.c_str(), FILE_READ_ATTRIBUTES,
      FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE, nullptr,
      OPEN_EXISTING, FILE_FLAG_BACKUP_SEMANTICS | FILE_FLAG_OPEN_REPARSE_POINT,
      nullptr);
  if (handle == INVALID_HANDLE_VALUE) {
    if (error)
      *error = L"The installed location could not be opened safely.";
    return false;
  }
  BY_HANDLE_FILE_INFORMATION information{};
  if (!GetFileInformationByHandle(handle, &information) ||
      (information.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY) == 0 ||
      (information.dwFileAttributes & FILE_ATTRIBUTE_REPARSE_POINT) != 0) {
    CloseHandle(handle);
    if (error)
      *error = L"The installed location is not a regular local directory.";
    return false;
  }
  if (root_handle) {
    *root_handle = handle;
  } else {
    CloseHandle(handle);
  }
  return true;
}

bool IsOrdinaryDirectory(const std::filesystem::path &path) {
  const DWORD attributes = GetFileAttributesW(path.c_str());
  return attributes != INVALID_FILE_ATTRIBUTES &&
         (attributes & FILE_ATTRIBUTE_DIRECTORY) != 0 &&
         (attributes & FILE_ATTRIBUTE_REPARSE_POINT) == 0;
}

bool IsOrdinaryFile(const std::filesystem::path &path) {
  const DWORD attributes = GetFileAttributesW(path.c_str());
  return attributes != INVALID_FILE_ATTRIBUTES &&
         (attributes & FILE_ATTRIBUTE_DIRECTORY) == 0 &&
         (attributes & FILE_ATTRIBUTE_REPARSE_POINT) == 0;
}

std::optional<std::string> ReadSmallFile(const std::filesystem::path &path) {
  std::error_code size_error;
  const auto size = std::filesystem::file_size(path, size_error);
  if (size_error || size == 0 || size > 1024 * 1024)
    return std::nullopt;
  std::ifstream stream(path, std::ios::binary);
  if (!stream)
    return std::nullopt;
  std::string bytes(static_cast<std::size_t>(size), '\0');
  stream.read(bytes.data(), static_cast<std::streamsize>(bytes.size()));
  if (!stream)
    return std::nullopt;
  return bytes;
}

std::wstring Utf8ToWide(const std::string &value) {
  if (value.empty())
    return {};
  const int required =
      MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, value.data(),
                          static_cast<int>(value.size()), nullptr, 0);
  if (required <= 0)
    return {};
  std::wstring result(static_cast<std::size_t>(required), L'\0');
  if (MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, value.data(),
                          static_cast<int>(value.size()), result.data(),
                          required) != required) {
    return {};
  }
  return result;
}

std::wstring XmlValue(const std::wstring &xml, std::wstring_view name) {
  const std::wstring opening = L"<" + std::wstring(name) + L">";
  const std::wstring closing = L"</" + std::wstring(name) + L">";
  const auto start = xml.find(opening);
  if (start == std::wstring::npos)
    return {};
  const auto content_start = start + opening.size();
  const auto end = xml.find(closing, content_start);
  if (end == std::wstring::npos)
    return {};
  return Trim(xml.substr(content_start, end - content_start));
}

std::optional<std::wstring> ReadRegistryInstallLocation(std::wstring *error) {
  const std::wstring key_path =
      L"Software\\Microsoft\\Windows\\CurrentVersion\\Uninstall\\" +
      std::wstring(build_config::kPackageId);
  HKEY key = nullptr;
  const LONG open_status =
      RegOpenKeyExW(HKEY_CURRENT_USER, key_path.c_str(), 0, KEY_READ, &key);
  if (open_status == ERROR_FILE_NOT_FOUND ||
      open_status == ERROR_PATH_NOT_FOUND) {
    return std::nullopt;
  }
  if (open_status != ERROR_SUCCESS) {
    if (error)
        *error = L"The existing application registration could not be opened.";
    return std::nullopt;
  }
  DWORD type = 0;
  DWORD bytes = 0;
  LONG status = RegQueryValueExW(key, L"InstallLocation", nullptr, &type,
                                 nullptr, &bytes);
  if (status != ERROR_SUCCESS || (type != REG_SZ && type != REG_EXPAND_SZ) ||
      bytes < sizeof(wchar_t) || bytes > 32768 * sizeof(wchar_t)) {
    RegCloseKey(key);
    if (error)
      *error =
          L"The existing application registration has an invalid install location.";
    return std::nullopt;
  }
  std::wstring value(bytes / sizeof(wchar_t), L'\0');
  status = RegQueryValueExW(key, L"InstallLocation", nullptr, &type,
                            reinterpret_cast<BYTE *>(value.data()), &bytes);
  RegCloseKey(key);
  if (status != ERROR_SUCCESS) {
    if (error)
      *error = L"The existing application registration could not be read.";
    return std::nullopt;
  }
  while (!value.empty() && value.back() == L'\0')
    value.pop_back();
  if (type == REG_EXPAND_SZ) {
    const DWORD required = ExpandEnvironmentStringsW(value.c_str(), nullptr, 0);
    if (required == 0) {
      if (error)
        *error = L"The existing application registration could not be expanded.";
      return std::nullopt;
    }
    std::wstring expanded(required, L'\0');
    if (ExpandEnvironmentStringsW(value.c_str(), expanded.data(), required) ==
        0) {
      if (error)
        *error = L"The existing application registration could not be expanded.";
      return std::nullopt;
    }
    while (!expanded.empty() && expanded.back() == L'\0')
      expanded.pop_back();
    value = std::move(expanded);
  }
  value = NormalizePath(value);
  if (value.empty()) {
    if (error)
      *error = L"The existing application registration contains an invalid path.";
    return std::nullopt;
  }
  return value;
}

std::wstring DefaultInstallRoot() {
  const DWORD required = GetEnvironmentVariableW(L"LOCALAPPDATA", nullptr, 0);
  if (required == 0)
    return {};
  std::wstring local(required, L'\0');
  if (GetEnvironmentVariableW(L"LOCALAPPDATA", local.data(), required) == 0) {
    return {};
  }
  while (!local.empty() && local.back() == L'\0')
    local.pop_back();
  return NormalizePath(
      (std::filesystem::path(local) / std::wstring(build_config::kPackageId))
          .wstring());
}

struct SemVersion {
  std::vector<unsigned long long> core;
  std::vector<std::wstring> prerelease;
  bool valid = false;
};

bool ParseUnsigned(std::wstring_view value, unsigned long long *result) {
  if (value.empty() || !std::all_of(value.begin(), value.end(), [](wchar_t c) {
        return c >= L'0' && c <= L'9';
      })) {
    return false;
  }
  unsigned long long number = 0;
  for (wchar_t c : value) {
    const unsigned digit = static_cast<unsigned>(c - L'0');
    if (number > (ULLONG_MAX - digit) / 10ULL)
      return false;
    number = number * 10ULL + digit;
  }
  *result = number;
  return true;
}

std::vector<std::wstring> Split(const std::wstring &value, wchar_t delimiter) {
  std::vector<std::wstring> result;
  std::size_t start = 0;
  while (start <= value.size()) {
    const auto end = value.find(delimiter, start);
    result.push_back(value.substr(
        start, end == std::wstring::npos ? std::wstring::npos : end - start));
    if (end == std::wstring::npos)
      break;
    start = end + 1;
  }
  return result;
}

SemVersion ParseSemVersion(std::wstring value) {
  SemVersion parsed;
  const auto plus = value.find(L'+');
  if (plus != std::wstring::npos)
    value.resize(plus);
  const auto dash = value.find(L'-');
  std::wstring core = value.substr(0, dash);
  if (dash != std::wstring::npos) {
    parsed.prerelease = Split(value.substr(dash + 1), L'.');
    if (parsed.prerelease.empty() ||
        std::any_of(parsed.prerelease.begin(), parsed.prerelease.end(),
                    [](const std::wstring &part) {
                      if (part.empty() ||
                          !std::all_of(part.begin(), part.end(), [](wchar_t c) {
                            return (c >= L'0' && c <= L'9') ||
                                   (c >= L'A' && c <= L'Z') ||
                                   (c >= L'a' && c <= L'z') || c == L'-';
                          })) {
                        return true;
                      }
                      unsigned long long numeric = 0;
                      return ParseUnsigned(part, &numeric) && part.size() > 1 &&
                             part.front() == L'0';
                    })) {
      return parsed;
    }
  }
  const auto core_parts = Split(core, L'.');
  if (core_parts.size() != 3)
    return parsed;
  for (const auto &part : core_parts) {
    unsigned long long number = 0;
    if (!ParseUnsigned(part, &number) ||
        (part.size() > 1 && part.front() == L'0'))
      return parsed;
    parsed.core.push_back(number);
  }
  parsed.valid = true;
  return parsed;
}

} // namespace

bool QueryRegisteredInstallLocation(std::wstring *location, bool *exists,
                                    std::wstring *error) {
  if (error)
    error->clear();
  if (location)
    location->clear();
  if (exists)
    *exists = false;
  std::wstring read_error;
  const auto registered = ReadRegistryInstallLocation(&read_error);
  if (!read_error.empty()) {
    if (error)
      *error = read_error;
    return false;
  }
  if (!registered)
    return true;
  if (location)
    *location = *registered;
  if (exists)
    *exists = true;
  return true;
}

bool VerifyInstalledBetaRoot(const std::wstring &root,
                             InstalledBeta *installation, std::wstring *error) {
  const std::wstring normalized = NormalizePath(root);
  if (normalized.empty()) {
    if (error)
      *error = L"The installed location is not a valid absolute path.";
    return false;
  }
  HANDLE root_handle = INVALID_HANDLE_VALUE;
  if (!ValidateExistingRootPath(normalized, &root_handle, error))
    return false;
  BY_HANDLE_FILE_INFORMATION root_information{};
  if (!GetFileInformationByHandle(root_handle, &root_information)) {
    CloseHandle(root_handle);
    if (error)
      *error = L"The installed location identity could not be confirmed.";
    return false;
  }
  CloseHandle(root_handle);
  const std::filesystem::path root_path(normalized);
  const std::filesystem::path current = root_path / L"current";
  if (!IsOrdinaryDirectory(root_path) || !IsOrdinaryDirectory(current)) {
    if (error)
      *error = L"The installed folder is missing or redirects elsewhere.";
    return false;
  }
  const std::vector<std::filesystem::path> required_files = {
      root_path / L"Update.exe", root_path / kExecutableName,
      current / kExecutableName, current / kUpdaterHelperName,
      current / L"sq.version"};
  for (const auto &file : required_files) {
    if (!IsOrdinaryFile(file)) {
      if (error)
        *error = L"The installed folder does not contain a complete Black "
                 L"Spirit Life installation.";
      return false;
    }
  }
  const auto bytes = ReadSmallFile(current / L"sq.version");
  if (!bytes) {
    if (error)
      *error = L"The installed package identity could not be read.";
    return false;
  }
  const std::wstring xml = Utf8ToWide(*bytes);
  const std::wstring id = XmlValue(xml, L"id");
  const std::wstring channel = XmlValue(xml, L"channel");
  const std::wstring main_exe = XmlValue(xml, L"mainExe");
  const std::wstring version = XmlValue(xml, L"version");
  if (id != build_config::kPackageId || channel != build_config::kChannel ||
      main_exe != kExecutableName || !ParseSemVersion(version).valid) {
    if (error)
      *error =
          L"The folder belongs to a different application or update channel.";
    return false;
  }
  if (installation) {
    installation->root = normalized;
    installation->version = version;
    installation->root_volume_serial = root_information.dwVolumeSerialNumber;
    installation->root_file_id =
        (static_cast<std::uint64_t>(root_information.nFileIndexHigh) << 32) |
        root_information.nFileIndexLow;
  }
  return true;
}

InstalledBetaLookup LocateInstalledBeta() {
  InstalledBetaLookup result;
  std::vector<std::wstring> candidates;
  std::wstring registry_error;
  if (auto registry = ReadRegistryInstallLocation(&registry_error); registry) {
    if (GetFileAttributesW(registry->c_str()) == INVALID_FILE_ATTRIBUTES) {
      result.error = L"The registered install location is missing. "
                     L"Nothing was changed.";
      return result;
    }
    candidates.push_back(*registry);
  }
  if (!registry_error.empty()) {
    result.error = registry_error + L" Nothing was changed.";
    return result;
  }
  const std::wstring default_root = DefaultInstallRoot();
  if (!default_root.empty())
    candidates.push_back(default_root);

  std::vector<InstalledBeta> valid;
  std::set<std::wstring> seen;
  for (const auto &candidate : candidates) {
    std::wstring folded = NormalizePath(candidate);
    std::transform(folded.begin(), folded.end(), folded.begin(), towlower);
    if (!seen.insert(folded).second)
      continue;
    const DWORD attributes = GetFileAttributesW(candidate.c_str());
    if (attributes == INVALID_FILE_ATTRIBUTES)
      continue;
    InstalledBeta installation;
    std::wstring verification_error;
    if (!VerifyInstalledBetaRoot(candidate, &installation,
                                 &verification_error)) {
      result.error = L"An existing application location was found but could not be "
                     L"verified. Nothing was changed. " +
                     verification_error;
      return result;
    }
    valid.push_back(std::move(installation));
  }
  if (valid.size() > 1 && !SamePath(valid[0].root, valid[1].root)) {
    result.error = L"More than one Black Spirit Life installation was "
                   L"found. Nothing was changed.";
    return result;
  }
  if (!valid.empty())
    result.installation = std::move(valid.front());
  return result;
}

int CompareSemanticVersions(const std::wstring &left,
                            const std::wstring &right) {
  const SemVersion a = ParseSemVersion(left);
  const SemVersion b = ParseSemVersion(right);
  if (!a.valid || !b.valid)
    return _wcsicmp(left.c_str(), right.c_str());
  for (std::size_t index = 0; index < 3; ++index) {
    if (a.core[index] < b.core[index])
      return -1;
    if (a.core[index] > b.core[index])
      return 1;
  }
  if (a.prerelease.empty() && b.prerelease.empty())
    return 0;
  if (a.prerelease.empty())
    return 1;
  if (b.prerelease.empty())
    return -1;
  const std::size_t count = std::min(a.prerelease.size(), b.prerelease.size());
  for (std::size_t index = 0; index < count; ++index) {
    unsigned long long a_number = 0;
    unsigned long long b_number = 0;
    const bool a_numeric = ParseUnsigned(a.prerelease[index], &a_number);
    const bool b_numeric = ParseUnsigned(b.prerelease[index], &b_number);
    if (a_numeric && b_numeric) {
      if (a_number < b_number)
        return -1;
      if (a_number > b_number)
        return 1;
      continue;
    }
    if (a_numeric != b_numeric)
      return a_numeric ? -1 : 1;
    const int comparison =
        _wcsicmp(a.prerelease[index].c_str(), b.prerelease[index].c_str());
    if (comparison != 0)
      return comparison < 0 ? -1 : 1;
  }
  if (a.prerelease.size() < b.prerelease.size())
    return -1;
  if (a.prerelease.size() > b.prerelease.size())
    return 1;
  return 0;
}

} // namespace bsl::installer
