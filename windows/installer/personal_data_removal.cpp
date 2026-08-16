#include "personal_data_removal.h"

#include <windows.h>

#include <knownfolders.h>
#include <shellapi.h>
#include <shlobj.h>
#include <shobjidl.h>

#include <algorithm>
#include <array>
#include <charconv>
#include <chrono>
#include <cstdint>
#include <cstring>
#include <cwchar>
#include <cwctype>
#include <filesystem>
#include <fstream>
#include <limits>
#include <map>
#include <optional>
#include <set>
#include <string>
#include <string_view>
#include <utility>
#include <vector>

#include "installed_beta_locator.h"
#include "installer_build_config.h"

namespace bsl::installer {
namespace {

constexpr wchar_t kProfileDirectoryName[] = L"Black Spirit Life";
constexpr wchar_t kBootstrapDirectoryName[] = L"Bootstrap";
constexpr wchar_t kLocatorFileName[] = L"personal-data-location.json";
constexpr wchar_t kLocatorMirrorFileName[] =
    L"personal-data-location.committed.json";
constexpr wchar_t kMoveJournalFileName[] =
    L"personal-data-move-journal.json";
constexpr wchar_t kProfileMarkerFileName[] =
    L".black-spirit-life-profile.json";
constexpr wchar_t kResetMarkerFileName[] =
    L".black-spirit-life-intentional-reset.json";
constexpr wchar_t kRemovalControlDirectoryName[] =
    L"BlackSpiritLife.App.Removal";
constexpr wchar_t kRemovalJournalFileName[] =
    L"pending-personal-data-removal.journal";
constexpr wchar_t kRemovalJournalMirrorFileName[] =
    L"pending-personal-data-removal.committed.journal";
constexpr char kJournalMagic[] = "BSL-PERSONAL-DATA-REMOVAL-V1";
constexpr std::uint64_t kMaximumIdentityFileBytes = 128 * 1024;

enum class JsonScalarKind { other, string, number, boolean };

struct JsonScalar {
  JsonScalarKind kind = JsonScalarKind::other;
  std::wstring text;
  bool boolean = false;
};

class JsonReader final {
public:
  explicit JsonReader(std::wstring_view input) : input_(input) {}

  bool ReadRootObject(std::map<std::wstring, JsonScalar> *values) {
    SkipWhitespace();
    if (!Consume(L'{'))
      return false;
    SkipWhitespace();
    if (Consume(L'}')) {
      SkipWhitespace();
      return position_ == input_.size();
    }
    while (position_ < input_.size()) {
      std::wstring key;
      if (!ReadString(&key))
        return false;
      SkipWhitespace();
      if (!Consume(L':'))
        return false;
      JsonScalar value;
      if (!ReadValue(&value, 1) ||
          !values->emplace(std::move(key), std::move(value)).second) {
        return false;
      }
      SkipWhitespace();
      if (Consume(L'}')) {
        SkipWhitespace();
        return position_ == input_.size();
      }
      if (!Consume(L','))
        return false;
      SkipWhitespace();
    }
    return false;
  }

private:
  bool ReadValue(JsonScalar *value, int depth) {
    if (depth > 32)
      return false;
    SkipWhitespace();
    if (position_ >= input_.size())
      return false;
    if (input_[position_] == L'"') {
      value->kind = JsonScalarKind::string;
      return ReadString(&value->text);
    }
    if (input_[position_] == L'{') {
      value->kind = JsonScalarKind::other;
      return SkipObject(depth + 1);
    }
    if (input_[position_] == L'[') {
      value->kind = JsonScalarKind::other;
      return SkipArray(depth + 1);
    }
    if (input_[position_] == L'-' || std::iswdigit(input_[position_]) != 0) {
      value->kind = JsonScalarKind::number;
      return ReadNumber(&value->text);
    }
    if (ConsumeLiteral(L"true")) {
      value->kind = JsonScalarKind::boolean;
      value->boolean = true;
      return true;
    }
    if (ConsumeLiteral(L"false")) {
      value->kind = JsonScalarKind::boolean;
      value->boolean = false;
      return true;
    }
    value->kind = JsonScalarKind::other;
    return ConsumeLiteral(L"null");
  }

  bool SkipObject(int depth) {
    if (depth > 32 || !Consume(L'{'))
      return false;
    SkipWhitespace();
    if (Consume(L'}'))
      return true;
    while (position_ < input_.size()) {
      std::wstring ignored_key;
      JsonScalar ignored_value;
      if (!ReadString(&ignored_key))
        return false;
      SkipWhitespace();
      if (!Consume(L':') || !ReadValue(&ignored_value, depth))
        return false;
      SkipWhitespace();
      if (Consume(L'}'))
        return true;
      if (!Consume(L','))
        return false;
      SkipWhitespace();
    }
    return false;
  }

  bool SkipArray(int depth) {
    if (depth > 32 || !Consume(L'['))
      return false;
    SkipWhitespace();
    if (Consume(L']'))
      return true;
    while (position_ < input_.size()) {
      JsonScalar ignored;
      if (!ReadValue(&ignored, depth))
        return false;
      SkipWhitespace();
      if (Consume(L']'))
        return true;
      if (!Consume(L','))
        return false;
      SkipWhitespace();
    }
    return false;
  }

  bool ReadString(std::wstring *value) {
    if (!Consume(L'"'))
      return false;
    value->clear();
    while (position_ < input_.size()) {
      const wchar_t current = input_[position_++];
      if (current == L'"')
        return true;
      if (current < 0x20)
        return false;
      if (current != L'\\') {
        value->push_back(current);
        continue;
      }
      if (position_ >= input_.size())
        return false;
      const wchar_t escaped = input_[position_++];
      switch (escaped) {
      case L'"':
      case L'\\':
      case L'/':
        value->push_back(escaped);
        break;
      case L'b':
        value->push_back(L'\b');
        break;
      case L'f':
        value->push_back(L'\f');
        break;
      case L'n':
        value->push_back(L'\n');
        break;
      case L'r':
        value->push_back(L'\r');
        break;
      case L't':
        value->push_back(L'\t');
        break;
      case L'u': {
        std::uint16_t code_unit = 0;
        if (!ReadHex4(&code_unit))
          return false;
        value->push_back(static_cast<wchar_t>(code_unit));
        break;
      }
      default:
        return false;
      }
    }
    return false;
  }

  bool ReadHex4(std::uint16_t *value) {
    if (position_ + 4 > input_.size())
      return false;
    std::uint16_t result = 0;
    for (int index = 0; index < 4; ++index) {
      const wchar_t character = input_[position_++];
      int digit = -1;
      if (character >= L'0' && character <= L'9')
        digit = character - L'0';
      else if (character >= L'a' && character <= L'f')
        digit = character - L'a' + 10;
      else if (character >= L'A' && character <= L'F')
        digit = character - L'A' + 10;
      if (digit < 0)
        return false;
      result = static_cast<std::uint16_t>((result << 4) | digit);
    }
    *value = result;
    return true;
  }

  bool ReadNumber(std::wstring *value) {
    const std::size_t start = position_;
    if (position_ < input_.size() && input_[position_] == L'-')
      ++position_;
    const std::size_t integer_start = position_;
    while (position_ < input_.size() &&
           std::iswdigit(input_[position_]) != 0) {
      ++position_;
    }
    if (position_ == integer_start)
      return false;
    if (position_ < input_.size() && input_[position_] == L'.') {
      ++position_;
      const std::size_t fraction_start = position_;
      while (position_ < input_.size() &&
             std::iswdigit(input_[position_]) != 0) {
        ++position_;
      }
      if (position_ == fraction_start)
        return false;
    }
    if (position_ < input_.size() &&
        (input_[position_] == L'e' || input_[position_] == L'E')) {
      ++position_;
      if (position_ < input_.size() &&
          (input_[position_] == L'+' || input_[position_] == L'-')) {
        ++position_;
      }
      const std::size_t exponent_start = position_;
      while (position_ < input_.size() &&
             std::iswdigit(input_[position_]) != 0) {
        ++position_;
      }
      if (position_ == exponent_start)
        return false;
    }
    *value = std::wstring(input_.substr(start, position_ - start));
    return true;
  }

  bool ConsumeLiteral(std::wstring_view literal) {
    if (input_.substr(position_, literal.size()) != literal)
      return false;
    position_ += literal.size();
    return true;
  }

  bool Consume(wchar_t value) {
    if (position_ >= input_.size() || input_[position_] != value)
      return false;
    ++position_;
    return true;
  }

  void SkipWhitespace() {
    while (position_ < input_.size() &&
           std::iswspace(input_[position_]) != 0) {
      ++position_;
    }
  }

  std::wstring_view input_;
  std::size_t position_ = 0;
};

class ScopedHandle final {
public:
  ScopedHandle() = default;
  explicit ScopedHandle(HANDLE value) : value_(value) {}
  ~ScopedHandle() { Reset(); }
  ScopedHandle(const ScopedHandle &) = delete;
  ScopedHandle &operator=(const ScopedHandle &) = delete;
  ScopedHandle(ScopedHandle &&other) noexcept : value_(other.Release()) {}
  ScopedHandle &operator=(ScopedHandle &&other) noexcept {
    if (this != &other)
      Reset(other.Release());
    return *this;
  }

  [[nodiscard]] HANDLE get() const { return value_; }
  [[nodiscard]] bool valid() const {
    return value_ != nullptr && value_ != INVALID_HANDLE_VALUE;
  }
  HANDLE Release() {
    const HANDLE value = value_;
    value_ = INVALID_HANDLE_VALUE;
    return value;
  }
  void Reset(HANDLE value = INVALID_HANDLE_VALUE) {
    if (valid())
      CloseHandle(value_);
    value_ = value;
  }

private:
  HANDLE value_ = INVALID_HANDLE_VALUE;
};

struct DirectoryIdentity {
  bool exists = false;
  std::uint32_t volume_serial = 0;
  std::uint64_t file_id = 0;
  std::wstring final_path;
};

struct RemovalEnvironment {
  std::wstring roaming_app_data;
  std::wstring local_app_data;
  std::wstring journal_directory;
};

enum class FileReadState { missing, valid, invalid };

struct FileReadResult {
  FileReadState state = FileReadState::invalid;
  std::vector<char> bytes;
};

std::wstring Normalize(const std::wstring &input) {
  if (input.empty() || input.rfind(L"\\\\", 0) == 0 ||
      input.rfind(L"\\\\?\\", 0) == 0 ||
      input.rfind(L"\\\\.\\", 0) == 0) {
    return {};
  }
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

bool SamePath(const std::wstring &left, const std::wstring &right) {
  const std::wstring a = Normalize(left);
  const std::wstring b = Normalize(right);
  return !a.empty() && !b.empty() && _wcsicmp(a.c_str(), b.c_str()) == 0;
}

bool SameOrChild(const std::wstring &candidate, const std::wstring &root) {
  const std::wstring a = Normalize(candidate);
  const std::wstring b = Normalize(root);
  if (a.empty() || b.empty())
    return false;
  if (_wcsicmp(a.c_str(), b.c_str()) == 0)
    return true;
  return a.size() > b.size() && a[b.size()] == L'\\' &&
         _wcsnicmp(a.c_str(), b.c_str(), b.size()) == 0;
}

std::wstring FinalPath(HANDLE handle) {
  constexpr DWORD flags = FILE_NAME_NORMALIZED | VOLUME_NAME_NT;
  const DWORD required = GetFinalPathNameByHandleW(handle, nullptr, 0, flags);
  if (required == 0)
    return {};
  std::wstring path(required, L'\0');
  const DWORD written =
      GetFinalPathNameByHandleW(handle, path.data(), required, flags);
  if (written == 0 || written >= required)
    return {};
  path.resize(written);
  while (path.size() > 1 &&
         (path.back() == L'\\' || path.back() == L'/')) {
    path.pop_back();
  }
  return path;
}

bool SameOrChildFinal(const std::wstring &candidate,
                      const std::wstring &root) {
  if (candidate.empty() || root.empty())
    return false;
  if (_wcsicmp(candidate.c_str(), root.c_str()) == 0)
    return true;
  return candidate.size() > root.size() &&
         (candidate[root.size()] == L'\\' || candidate[root.size()] == L'/') &&
         _wcsnicmp(candidate.c_str(), root.c_str(), root.size()) == 0;
}

bool MissingPathError(DWORD error) {
  return error == ERROR_FILE_NOT_FOUND || error == ERROR_PATH_NOT_FOUND ||
         error == ERROR_INVALID_NAME;
}

bool ReadDirectoryIdentity(const std::wstring &path,
                           DirectoryIdentity *identity,
                           std::wstring *error,
                           DWORD desired_access = FILE_READ_ATTRIBUTES,
                           DWORD share_mode = FILE_SHARE_READ |
                                              FILE_SHARE_WRITE |
                                              FILE_SHARE_DELETE,
                           ScopedHandle *retained = nullptr) {
  if (identity)
    *identity = {};
  const DWORD attributes = GetFileAttributesW(path.c_str());
  if (attributes == INVALID_FILE_ATTRIBUTES) {
    if (MissingPathError(GetLastError()))
      return true;
    if (error)
      *error = L"Windows could not inspect a planner-data folder.";
    return false;
  }
  if ((attributes & FILE_ATTRIBUTE_DIRECTORY) == 0 ||
      (attributes & FILE_ATTRIBUTE_REPARSE_POINT) != 0) {
    if (error)
      *error = L"A planner-data path is not an ordinary folder.";
    return false;
  }
  ScopedHandle handle(CreateFileW(
      path.c_str(), desired_access, share_mode, nullptr, OPEN_EXISTING,
      FILE_FLAG_BACKUP_SEMANTICS | FILE_FLAG_OPEN_REPARSE_POINT, nullptr));
  if (!handle.valid()) {
    if (error)
      *error = L"A planner-data folder could not be opened safely.";
    return false;
  }
  BY_HANDLE_FILE_INFORMATION information{};
  const std::wstring final_path = FinalPath(handle.get());
  if (!GetFileInformationByHandle(handle.get(), &information) ||
      (information.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY) == 0 ||
      (information.dwFileAttributes & FILE_ATTRIBUTE_REPARSE_POINT) != 0 ||
      final_path.empty()) {
    if (error)
      *error = L"A planner-data folder identity could not be verified.";
    return false;
  }
  if (identity) {
    identity->exists = true;
    identity->volume_serial = information.dwVolumeSerialNumber;
    identity->file_id =
        (static_cast<std::uint64_t>(information.nFileIndexHigh) << 32) |
        information.nFileIndexLow;
    identity->final_path = final_path;
  }
  if (retained)
    retained->Reset(handle.Release());
  return true;
}

bool IdentityMatches(const DirectoryIdentity &identity,
                     const PersonalDataRemovalTarget &target) {
  return identity.exists &&
         identity.volume_serial == target.volume_serial &&
         identity.file_id == target.file_id;
}

bool HasReparseAncestor(const std::wstring &path) {
  std::filesystem::path current(Normalize(path));
  while (!current.empty()) {
    const DWORD attributes = GetFileAttributesW(current.c_str());
    if (attributes != INVALID_FILE_ATTRIBUTES &&
        (attributes & FILE_ATTRIBUTE_REPARSE_POINT) != 0) {
      return true;
    }
    const std::filesystem::path parent = current.parent_path();
    if (parent.empty() || parent == current)
      break;
    current = parent;
  }
  return false;
}

bool TreeContainsReparsePoint(const std::wstring &root, std::wstring *error) {
  std::vector<std::filesystem::path> pending{std::filesystem::path(root)};
  while (!pending.empty()) {
    const std::filesystem::path directory = std::move(pending.back());
    pending.pop_back();
    WIN32_FIND_DATAW data{};
    const std::wstring pattern = (directory / L"*").wstring();
    HANDLE find = FindFirstFileW(pattern.c_str(), &data);
    if (find == INVALID_HANDLE_VALUE) {
      if (GetLastError() == ERROR_FILE_NOT_FOUND)
        continue;
      if (error)
        *error = L"A planner-data folder could not be enumerated safely.";
      return true;
    }
    bool failed = false;
    do {
      if (std::wcscmp(data.cFileName, L".") == 0 ||
          std::wcscmp(data.cFileName, L"..") == 0) {
        continue;
      }
      if ((data.dwFileAttributes & FILE_ATTRIBUTE_REPARSE_POINT) != 0) {
        failed = true;
        if (error)
          *error = L"Planner data contains a link or junction and was not "
                   L"removed.";
        break;
      }
      if ((data.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY) != 0)
        pending.push_back(directory / data.cFileName);
    } while (FindNextFileW(find, &data));
    const DWORD enumeration_error = GetLastError();
    FindClose(find);
    if (failed)
      return true;
    if (enumeration_error != ERROR_NO_MORE_FILES) {
      if (error)
        *error = L"A planner-data folder changed during verification.";
      return true;
    }
  }
  return false;
}

FileReadResult ReadSmallOrdinaryFile(const std::wstring &path) {
  const DWORD attributes = GetFileAttributesW(path.c_str());
  if (attributes == INVALID_FILE_ATTRIBUTES) {
    return {.state = MissingPathError(GetLastError())
                         ? FileReadState::missing
                         : FileReadState::invalid};
  }
  if ((attributes & FILE_ATTRIBUTE_DIRECTORY) != 0 ||
      (attributes & FILE_ATTRIBUTE_REPARSE_POINT) != 0) {
    return {.state = FileReadState::invalid};
  }
  ScopedHandle file(CreateFileW(
      path.c_str(), GENERIC_READ, FILE_SHARE_READ, nullptr, OPEN_EXISTING,
      FILE_ATTRIBUTE_NORMAL | FILE_FLAG_OPEN_REPARSE_POINT, nullptr));
  if (!file.valid())
    return {.state = FileReadState::invalid};
  BY_HANDLE_FILE_INFORMATION information{};
  LARGE_INTEGER size{};
  if (!GetFileInformationByHandle(file.get(), &information) ||
      (information.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY) != 0 ||
      (information.dwFileAttributes & FILE_ATTRIBUTE_REPARSE_POINT) != 0 ||
      !GetFileSizeEx(file.get(), &size) || size.QuadPart <= 0 ||
      static_cast<std::uint64_t>(size.QuadPart) > kMaximumIdentityFileBytes) {
    return {.state = FileReadState::invalid};
  }
  std::vector<char> bytes(static_cast<std::size_t>(size.QuadPart));
  DWORD total = 0;
  while (total < bytes.size()) {
    DWORD read = 0;
    const DWORD remaining = static_cast<DWORD>(bytes.size() - total);
    if (!ReadFile(file.get(), bytes.data() + total, remaining, &read, nullptr) ||
        read == 0) {
      return {.state = FileReadState::invalid};
    }
    total += read;
  }
  return {.state = FileReadState::valid, .bytes = std::move(bytes)};
}

bool Utf8ToWide(const std::vector<char> &bytes, std::wstring *wide) {
  std::size_t offset = 0;
  if (bytes.size() >= 3 && static_cast<unsigned char>(bytes[0]) == 0xEF &&
      static_cast<unsigned char>(bytes[1]) == 0xBB &&
      static_cast<unsigned char>(bytes[2]) == 0xBF) {
    offset = 3;
  }
  if (offset >= bytes.size() || bytes.size() - offset > INT_MAX)
    return false;
  const int input_length = static_cast<int>(bytes.size() - offset);
  const int required = MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS,
                                            bytes.data() + offset, input_length,
                                            nullptr, 0);
  if (required <= 0)
    return false;
  wide->assign(static_cast<std::size_t>(required), L'\0');
  return MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS,
                             bytes.data() + offset, input_length, wide->data(),
                             required) == required;
}

bool ParseIdentityJson(const std::vector<char> &bytes,
                       std::map<std::wstring, JsonScalar> *values) {
  std::wstring json;
  if (!Utf8ToWide(bytes, &json) || !JsonReader(json).ReadRootObject(values))
    return false;
  const auto schema = values->find(L"schemaVersion");
  const auto package = values->find(L"packageId");
  const auto channel = values->find(L"releaseChannel");
  return schema != values->end() && package != values->end() &&
         channel != values->end() &&
         schema->second.kind == JsonScalarKind::number &&
         schema->second.text == L"1" &&
         package->second.kind == JsonScalarKind::string &&
         package->second.text == std::wstring(build_config::kPackageId) &&
         channel->second.kind == JsonScalarKind::string &&
         channel->second.text == std::wstring(build_config::kChannel);
}

bool IsIdentityToken(const std::wstring &value) {
  const std::size_t first = value.find(L'-');
  const std::size_t second =
      first == std::wstring::npos ? std::wstring::npos
                                  : value.find(L'-', first + 1);
  if (first == 0 || second == std::wstring::npos || second == first + 1 ||
      value.size() - second - 1 != 32) {
    return false;
  }
  for (std::size_t index = 0; index < first; ++index) {
    if (value[index] < L'a' || value[index] > L'z')
      return false;
  }
  for (std::size_t index = first + 1; index < value.size(); ++index) {
    if (index == second)
      continue;
    const wchar_t character = value[index];
    if (!((character >= L'0' && character <= L'9') ||
          (character >= L'a' && character <= L'f'))) {
      return false;
    }
  }
  return true;
}

bool ParseLocator(const std::wstring &path, std::wstring *directory,
                  FileReadState *state) {
  const FileReadResult file = ReadSmallOrdinaryFile(path);
  *state = file.state;
  if (file.state != FileReadState::valid)
    return false;
  std::map<std::wstring, JsonScalar> values;
  if (!ParseIdentityJson(file.bytes, &values)) {
    *state = FileReadState::invalid;
    return false;
  }
  const auto value = values.find(L"applicationDirectory");
  if (value == values.end() || value->second.kind != JsonScalarKind::string) {
    *state = FileReadState::invalid;
    return false;
  }
  *directory = Normalize(value->second.text);
  if (directory->size() < 3 || (*directory)[1] != L':' ||
      (*directory)[2] != L'\\') {
    *state = FileReadState::invalid;
    return false;
  }
  return true;
}

bool ValidOwnedProfileMarker(const std::wstring &directory) {
  const FileReadResult marker = ReadSmallOrdinaryFile(
      (std::filesystem::path(directory) / kProfileMarkerFileName).wstring());
  if (marker.state != FileReadState::valid)
    return false;
  std::map<std::wstring, JsonScalar> values;
  if (!ParseIdentityJson(marker.bytes, &values))
    return false;
  const auto profile = values.find(L"profile");
  const auto profile_id = values.find(L"profileId");
  const auto transaction_id = values.find(L"transactionId");
  return profile != values.end() &&
         profile->second.kind == JsonScalarKind::boolean &&
         profile->second.boolean && profile_id != values.end() &&
         profile_id->second.kind == JsonScalarKind::string &&
         IsIdentityToken(profile_id->second.text) &&
         transaction_id != values.end() &&
         transaction_id->second.kind == JsonScalarKind::string &&
         IsIdentityToken(transaction_id->second.text);
}

bool IsNonemptyOrdinaryFile(const std::filesystem::path &path) {
  const DWORD attributes = GetFileAttributesW(path.c_str());
  if (attributes == INVALID_FILE_ATTRIBUTES ||
      (attributes & FILE_ATTRIBUTE_DIRECTORY) != 0 ||
      (attributes & FILE_ATTRIBUTE_REPARSE_POINT) != 0) {
    return false;
  }
  ScopedHandle file(CreateFileW(path.c_str(), GENERIC_READ, FILE_SHARE_READ,
                                nullptr, OPEN_EXISTING,
                                FILE_FLAG_OPEN_REPARSE_POINT, nullptr));
  LARGE_INTEGER size{};
  return file.valid() && GetFileSizeEx(file.get(), &size) && size.QuadPart > 0;
}

bool HasProfileStateWitness(const std::wstring &directory) {
  const std::filesystem::path root(directory);
  if (IsNonemptyOrdinaryFile(root / L"planner-state.json"))
    return true;
  WIN32_FIND_DATAW data{};
  HANDLE find =
      FindFirstFileW((root / L"planner-state.json.backup-*").c_str(), &data);
  if (find == INVALID_HANDLE_VALUE)
    return false;
  bool found = false;
  do {
    if ((data.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY) == 0 &&
        (data.dwFileAttributes & FILE_ATTRIBUTE_REPARSE_POINT) == 0 &&
        (data.nFileSizeHigh != 0 || data.nFileSizeLow != 0)) {
      found = true;
      break;
    }
  } while (FindNextFileW(find, &data));
  FindClose(find);
  return found;
}

std::optional<std::wstring> KnownFolder(REFKNOWNFOLDERID identifier) {
  PWSTR value = nullptr;
  const HRESULT result =
      SHGetKnownFolderPath(identifier, KF_FLAG_DONT_VERIFY, nullptr, &value);
  if (FAILED(result) || value == nullptr)
    return std::nullopt;
  std::wstring path = Normalize(value);
  CoTaskMemFree(value);
  if (path.empty())
    return std::nullopt;
  return path;
}

std::optional<RemovalEnvironment> ProductionEnvironment(std::wstring *error) {
  const auto roaming = KnownFolder(FOLDERID_RoamingAppData);
  const auto local = KnownFolder(FOLDERID_LocalAppData);
  if (!roaming || !local) {
    if (error)
      *error = L"Windows could not resolve this account's data folders.";
    return std::nullopt;
  }
  return RemovalEnvironment{
      .roaming_app_data = *roaming,
      .local_app_data = *local,
      .journal_directory =
          (std::filesystem::path(*local) / kRemovalControlDirectoryName)
              .wstring(),
  };
}

std::optional<RemovalEnvironment>
NormalizeTestEnvironment(const PersonalDataRemovalTestEnvironment &environment,
                         std::wstring *error) {
  RemovalEnvironment result{
      .roaming_app_data = Normalize(environment.roaming_app_data),
      .local_app_data = Normalize(environment.local_app_data),
      .journal_directory = Normalize(environment.journal_directory),
  };
  if (result.roaming_app_data.empty() || result.local_app_data.empty() ||
      result.journal_directory.empty()) {
    if (error)
      *error = L"The isolated personal-data test environment is invalid.";
    return std::nullopt;
  }
  return result;
}

bool EnsureOrdinaryDirectory(const std::wstring &path, std::wstring *error) {
  if (path.empty() || HasReparseAncestor(path)) {
    if (error)
      *error = L"A removal-control path redirects through a link or junction.";
    return false;
  }
  std::error_code create_error;
  std::filesystem::create_directories(path, create_error);
  if (create_error) {
    if (error)
      *error = L"The removal-control folder could not be created.";
    return false;
  }
  DirectoryIdentity identity;
  if (!ReadDirectoryIdentity(path, &identity, error) || !identity.exists)
    return false;
  return true;
}

std::wstring NewTransactionIdentity() {
  GUID guid{};
  if (FAILED(CoCreateGuid(&guid)))
    return {};
  FILETIME now{};
  GetSystemTimeAsFileTime(&now);
  const std::uint64_t ticks =
      (static_cast<std::uint64_t>(now.dwHighDateTime) << 32) | now.dwLowDateTime;
  wchar_t result[96]{};
  swprintf_s(result,
             L"uninstall-%llx-%08x%04x%04x%02x%02x%02x%02x%02x%02x%02x%02x",
             static_cast<unsigned long long>(ticks), guid.Data1, guid.Data2,
             guid.Data3, guid.Data4[0], guid.Data4[1], guid.Data4[2],
             guid.Data4[3], guid.Data4[4], guid.Data4[5], guid.Data4[6],
             guid.Data4[7]);
  const std::wstring value(result);
  return IsIdentityToken(value) ? value : std::wstring{};
}

char HexDigit(unsigned value) {
  return static_cast<char>(value < 10 ? '0' + value : 'A' + (value - 10));
}

std::string HexEncode(const std::wstring &value) {
  std::string result;
  result.reserve(value.size() * 4);
  for (const wchar_t character : value) {
    const unsigned code = static_cast<unsigned>(character) & 0xFFFFU;
    result.push_back(HexDigit((code >> 12) & 0xFU));
    result.push_back(HexDigit((code >> 8) & 0xFU));
    result.push_back(HexDigit((code >> 4) & 0xFU));
    result.push_back(HexDigit(code & 0xFU));
  }
  return result;
}

int HexValue(char value) {
  if (value >= '0' && value <= '9')
    return value - '0';
  if (value >= 'A' && value <= 'F')
    return value - 'A' + 10;
  if (value >= 'a' && value <= 'f')
    return value - 'a' + 10;
  return -1;
}

bool HexDecode(const std::string &value, std::wstring *result) {
  if (value.size() % 4 != 0 || value.size() > 65535 * 4)
    return false;
  result->clear();
  result->reserve(value.size() / 4);
  for (std::size_t offset = 0; offset < value.size(); offset += 4) {
    unsigned code = 0;
    for (int index = 0; index < 4; ++index) {
      const int digit = HexValue(value[offset + static_cast<std::size_t>(index)]);
      if (digit < 0)
        return false;
      code = (code << 4) | static_cast<unsigned>(digit);
    }
    if (code == 0)
      return false;
    result->push_back(static_cast<wchar_t>(code));
  }
  return true;
}

std::string StatusText(PersonalDataRemovalStatus status) {
  switch (status) {
  case PersonalDataRemovalStatus::prepared:
    return "prepared";
  case PersonalDataRemovalStatus::application_removed:
    return "application_removed";
  case PersonalDataRemovalStatus::cleanup_pending:
    return "cleanup_pending";
  case PersonalDataRemovalStatus::complete:
    return "complete";
  case PersonalDataRemovalStatus::none:
  case PersonalDataRemovalStatus::invalid:
    return "invalid";
  }
  return "invalid";
}

std::string NarrowAscii(std::wstring_view value) {
  std::string result;
  result.reserve(value.size());
  for (const wchar_t character : value) {
    if (character < 0x20 || character > 0x7E)
      return {};
    result.push_back(static_cast<char>(character));
  }
  return result;
}

bool ParseStatus(const std::string &value, PersonalDataRemovalStatus *status) {
  if (value == "prepared")
    *status = PersonalDataRemovalStatus::prepared;
  else if (value == "application_removed")
    *status = PersonalDataRemovalStatus::application_removed;
  else if (value == "cleanup_pending")
    *status = PersonalDataRemovalStatus::cleanup_pending;
  else if (value == "complete")
    *status = PersonalDataRemovalStatus::complete;
  else
    return false;
  return true;
}

void AppendJournalLine(std::string *journal, const char *key,
                       const std::string &value) {
  journal->append(key);
  journal->push_back('=');
  journal->append(value);
  journal->append("\r\n");
}

std::string SerializeJournal(const PersonalDataRemovalPlan &plan) {
  std::string journal(kJournalMagic);
  journal.append("\r\n");
  AppendJournalLine(&journal, "packageId", NarrowAscii(build_config::kPackageId));
  AppendJournalLine(&journal, "releaseChannel",
                    NarrowAscii(build_config::kChannel));
  AppendJournalLine(&journal, "status", StatusText(plan.status));
  AppendJournalLine(&journal, "transactionId", HexEncode(plan.transaction_id));
  AppendJournalLine(&journal, "customProfile", plan.custom_profile ? "1" : "0");
  AppendJournalLine(
      &journal, "journalDirectoryVolume",
      std::to_string(plan.journal_directory_volume_serial));
  AppendJournalLine(&journal, "journalDirectoryFileId",
                    std::to_string(plan.journal_directory_file_id));
  AppendJournalLine(&journal, "resetMarkerPath", HexEncode(plan.reset_marker_path));
  AppendJournalLine(&journal, "installRoot", HexEncode(plan.install_root));
  AppendJournalLine(&journal, "registeredInstallRoot",
                    HexEncode(plan.registered_install_root));
  AppendJournalLine(&journal, "installedVersion",
                    HexEncode(plan.installed_version));
  AppendJournalLine(&journal, "installVolume",
                    std::to_string(plan.install_root_volume_serial));
  AppendJournalLine(&journal, "installFileId",
                    std::to_string(plan.install_root_file_id));
  const auto append_target = [&](const char *prefix,
                                 const PersonalDataRemovalTarget &target) {
    const std::string name(prefix);
    AppendJournalLine(&journal, (name + "Present").c_str(),
                      target.present ? "1" : "0");
    AppendJournalLine(&journal, (name + "Quarantined").c_str(),
                      target.quarantined ? "1" : "0");
    AppendJournalLine(&journal, (name + "Recycled").c_str(),
                      target.recycled ? "1" : "0");
    AppendJournalLine(&journal, (name + "Path").c_str(),
                      HexEncode(target.path));
    AppendJournalLine(&journal, (name + "QuarantinePath").c_str(),
                      HexEncode(target.quarantine_path));
    AppendJournalLine(&journal, (name + "Volume").c_str(),
                      std::to_string(target.volume_serial));
    AppendJournalLine(&journal, (name + "FileId").c_str(),
                      std::to_string(target.file_id));
    AppendJournalLine(&journal, (name + "ParentVolume").c_str(),
                      std::to_string(target.parent_volume_serial));
    AppendJournalLine(&journal, (name + "ParentFileId").c_str(),
                      std::to_string(target.parent_file_id));
  };
  append_target("profile", plan.active_profile);
  append_target("local", plan.local_data);
  return journal;
}

bool ParseJournalLines(const std::vector<char> &bytes,
                       std::map<std::string, std::string> *values) {
  if (bytes.empty() || bytes.size() > kMaximumIdentityFileBytes)
    return false;
  const std::string source(bytes.begin(), bytes.end());
  std::size_t start = 0;
  std::size_t end = source.find('\n');
  std::string first = source.substr(0, end);
  if (!first.empty() && first.back() == '\r')
    first.pop_back();
  if (first != kJournalMagic)
    return false;
  start = end == std::string::npos ? source.size() : end + 1;
  while (start < source.size()) {
    end = source.find('\n', start);
    std::string line = source.substr(start, end - start);
    if (!line.empty() && line.back() == '\r')
      line.pop_back();
    if (!line.empty()) {
      const std::size_t separator = line.find('=');
      if (separator == std::string::npos || separator == 0 ||
          !values->emplace(line.substr(0, separator),
                           line.substr(separator + 1))
               .second) {
        return false;
      }
    }
    if (end == std::string::npos)
      break;
    start = end + 1;
  }
  return true;
}

bool ReadRequired(const std::map<std::string, std::string> &values,
                  const std::string &key, std::string *value) {
  const auto found = values.find(key);
  if (found == values.end())
    return false;
  *value = found->second;
  return true;
}

bool ParseBoolean(const std::string &value, bool *result) {
  if (value == "0")
    *result = false;
  else if (value == "1")
    *result = true;
  else
    return false;
  return true;
}

template <typename T> bool ParseUnsigned(const std::string &value, T *result) {
  if (value.empty())
    return false;
  std::uint64_t parsed = 0;
  const auto conversion =
      std::from_chars(value.data(), value.data() + value.size(), parsed);
  if (conversion.ec != std::errc{} ||
      conversion.ptr != value.data() + value.size() ||
      parsed > static_cast<std::uint64_t>(std::numeric_limits<T>::max())) {
    return false;
  }
  *result = static_cast<T>(parsed);
  return true;
}

bool ParseTarget(const std::map<std::string, std::string> &values,
                 const std::string &prefix,
                 PersonalDataRemovalTarget *target) {
  std::string present;
  std::string quarantined;
  std::string recycled;
  std::string path;
  std::string quarantine_path;
  std::string volume;
  std::string file_id;
  std::string parent_volume;
  std::string parent_file_id;
  if (!ReadRequired(values, prefix + "Present", &present) ||
      !ReadRequired(values, prefix + "Quarantined", &quarantined) ||
      !ReadRequired(values, prefix + "Recycled", &recycled) ||
      !ReadRequired(values, prefix + "Path", &path) ||
      !ReadRequired(values, prefix + "QuarantinePath", &quarantine_path) ||
      !ReadRequired(values, prefix + "Volume", &volume) ||
      !ReadRequired(values, prefix + "FileId", &file_id) ||
      !ReadRequired(values, prefix + "ParentVolume", &parent_volume) ||
      !ReadRequired(values, prefix + "ParentFileId", &parent_file_id) ||
      !ParseBoolean(present, &target->present) ||
      !ParseBoolean(quarantined, &target->quarantined) ||
      !ParseBoolean(recycled, &target->recycled) ||
      !HexDecode(path, &target->path) ||
      !HexDecode(quarantine_path, &target->quarantine_path) ||
      !ParseUnsigned(volume, &target->volume_serial) ||
      !ParseUnsigned(file_id, &target->file_id) ||
      !ParseUnsigned(parent_volume, &target->parent_volume_serial) ||
      !ParseUnsigned(parent_file_id, &target->parent_file_id)) {
    return false;
  }
  target->path = Normalize(target->path);
  target->quarantine_path = Normalize(target->quarantine_path);
  if (target->path.empty() || target->quarantine_path.empty() ||
      target->parent_volume_serial == 0 || target->parent_file_id == 0 ||
      (target->present &&
       (target->volume_serial == 0 || target->file_id == 0)) ||
      (!target->present &&
       (target->volume_serial != 0 || target->file_id != 0)) ||
      (target->recycled && target->present && !target->quarantined)) {
    return false;
  }
  return true;
}

bool ParseJournal(const std::vector<char> &bytes,
                  PersonalDataRemovalPlan *plan) {
  std::map<std::string, std::string> values;
  if (!ParseJournalLines(bytes, &values))
    return false;
  std::string package;
  std::string channel;
  std::string status;
  std::string transaction;
  std::string custom;
  std::string journal_directory_volume;
  std::string journal_directory_file_id;
  std::string reset_marker;
  std::string install_root;
  std::string registered_root;
  std::string version;
  std::string install_volume;
  std::string install_file_id;
  if (!ReadRequired(values, "packageId", &package) ||
      !ReadRequired(values, "releaseChannel", &channel) ||
      package != NarrowAscii(build_config::kPackageId) ||
      channel != NarrowAscii(build_config::kChannel) ||
      !ReadRequired(values, "status", &status) ||
      !ParseStatus(status, &plan->status) ||
      !ReadRequired(values, "transactionId", &transaction) ||
      !HexDecode(transaction, &plan->transaction_id) ||
      !IsIdentityToken(plan->transaction_id) ||
      !ReadRequired(values, "customProfile", &custom) ||
      !ParseBoolean(custom, &plan->custom_profile) ||
      !ReadRequired(values, "journalDirectoryVolume",
                    &journal_directory_volume) ||
      !ParseUnsigned(journal_directory_volume,
                     &plan->journal_directory_volume_serial) ||
      !ReadRequired(values, "journalDirectoryFileId",
                    &journal_directory_file_id) ||
      !ParseUnsigned(journal_directory_file_id,
                     &plan->journal_directory_file_id) ||
      !ReadRequired(values, "resetMarkerPath", &reset_marker) ||
      !HexDecode(reset_marker, &plan->reset_marker_path) ||
      !ReadRequired(values, "installRoot", &install_root) ||
      !HexDecode(install_root, &plan->install_root) ||
      !ReadRequired(values, "registeredInstallRoot", &registered_root) ||
      !HexDecode(registered_root, &plan->registered_install_root) ||
      !ReadRequired(values, "installedVersion", &version) ||
      !HexDecode(version, &plan->installed_version) ||
      !ReadRequired(values, "installVolume", &install_volume) ||
      !ParseUnsigned(install_volume, &plan->install_root_volume_serial) ||
      !ReadRequired(values, "installFileId", &install_file_id) ||
      !ParseUnsigned(install_file_id, &plan->install_root_file_id) ||
      !ParseTarget(values, "profile", &plan->active_profile) ||
      !ParseTarget(values, "local", &plan->local_data)) {
    return false;
  }
  plan->reset_marker_path = Normalize(plan->reset_marker_path);
  plan->install_root = Normalize(plan->install_root);
  plan->registered_install_root = Normalize(plan->registered_install_root);
  if (plan->reset_marker_path.empty() || plan->install_root.empty() ||
      plan->registered_install_root.empty() || plan->installed_version.empty() ||
      plan->journal_directory_volume_serial == 0 ||
      plan->journal_directory_file_id == 0 ||
      plan->install_root_volume_serial == 0 || plan->install_root_file_id == 0) {
    return false;
  }
  const std::wstring expected_profile_quarantine =
      plan->active_profile.path + L".bsl-uninstall-" + plan->transaction_id;
  const std::wstring expected_local_quarantine =
      plan->local_data.path + L".bsl-uninstall-" + plan->transaction_id;
  return SamePath(plan->active_profile.quarantine_path,
                  expected_profile_quarantine) &&
         SamePath(plan->local_data.quarantine_path,
                  expected_local_quarantine);
}

bool WriteDurableFile(const std::wstring &path, const std::string &bytes,
                      const std::wstring &transaction_id,
                      std::wstring *error) {
  // Every checkpoint gets a new staging name. Reusing one transaction-scoped
  // name makes a power loss after CREATE_NEW permanently block every retry.
  const std::wstring write_token = NewTransactionIdentity();
  if (write_token.size() < 32 || transaction_id.empty()) {
    if (error)
      *error = L"A durable checkpoint identity could not be created.";
    return false;
  }
  const std::wstring write_identity = write_token.substr(write_token.size() - 32);
  const std::wstring staged_path =
      path + L"." + transaction_id.substr(0, 8) + L"." + write_identity +
      L".tmp";
  ScopedHandle staged(CreateFileW(staged_path.c_str(), GENERIC_WRITE, 0, nullptr,
                                  CREATE_NEW, FILE_ATTRIBUTE_NORMAL,
                                  nullptr));
  if (!staged.valid()) {
    if (error)
      *error = L"A durable personal-data removal record could not be staged.";
    return false;
  }
  DWORD written_total = 0;
  while (written_total < bytes.size()) {
    const DWORD requested = static_cast<DWORD>(bytes.size() - written_total);
    DWORD written = 0;
    if (!WriteFile(staged.get(), bytes.data() + written_total, requested,
                   &written, nullptr) ||
        written == 0) {
      staged.Reset();
      DeleteFileW(staged_path.c_str());
      if (error)
        *error = L"A durable personal-data removal record could not be written.";
      return false;
    }
    written_total += written;
  }
  if (!FlushFileBuffers(staged.get())) {
    staged.Reset();
    DeleteFileW(staged_path.c_str());
    if (error)
      *error = L"A personal-data removal record could not be flushed to disk.";
    return false;
  }
  staged.Reset();
  if (!MoveFileExW(staged_path.c_str(), path.c_str(),
                   MOVEFILE_REPLACE_EXISTING | MOVEFILE_WRITE_THROUGH)) {
    DeleteFileW(staged_path.c_str());
    if (error)
      *error = L"A personal-data removal record could not be committed.";
    return false;
  }
  return true;
}

bool JournalDirectoryStillMatches(const PersonalDataRemovalPlan &plan,
                                  std::wstring *error);

bool WriteJournal(const PersonalDataRemovalPlan &plan, std::wstring *error) {
  if (!JournalDirectoryStillMatches(plan, error))
    return false;
  const std::string serialized = SerializeJournal(plan);
  if (!WriteDurableFile(plan.journal_mirror_path, serialized,
                        plan.transaction_id, error)) {
    return false;
  }
  std::wstring primary_error;
  // The committed mirror is authoritative. A missing primary can be repaired
  // by DetectPendingPersonalDataRemoval after a crash or transient lock.
  (void)WriteDurableFile(plan.journal_path, serialized, plan.transaction_id,
                         &primary_error);
  return true;
}

bool DeleteExactFileIfPresent(const std::wstring &path, std::wstring *error) {
  const DWORD attributes = GetFileAttributesW(path.c_str());
  if (attributes == INVALID_FILE_ATTRIBUTES) {
    if (MissingPathError(GetLastError()))
      return true;
    if (error)
      *error = L"A completed removal record could not be inspected.";
    return false;
  }
  if ((attributes & FILE_ATTRIBUTE_DIRECTORY) != 0 ||
      (attributes & FILE_ATTRIBUTE_REPARSE_POINT) != 0 ||
      !DeleteFileW(path.c_str())) {
    if (error)
      *error = L"A completed removal record could not be cleared.";
    return false;
  }
  return true;
}

bool ClearJournal(const PersonalDataRemovalPlan &plan, std::wstring *error) {
  if (!JournalDirectoryStillMatches(plan, error))
    return false;
  // The committed mirror is authoritative. Never discard it when the working
  // copy could not be cleared; Detect can repair a missing working copy from a
  // retained mirror on the next retry.
  if (!DeleteExactFileIfPresent(plan.journal_path, error))
    return false;
  return DeleteExactFileIfPresent(plan.journal_mirror_path, error);
}

bool JournalDirectoryStillMatches(const PersonalDataRemovalPlan &plan,
                                  std::wstring *error) {
  const std::wstring journal_directory =
      std::filesystem::path(plan.journal_path).parent_path().wstring();
  if (journal_directory.empty() ||
      !SamePath(journal_directory,
                std::filesystem::path(plan.journal_mirror_path)
                    .parent_path()
                    .wstring()) ||
      HasReparseAncestor(journal_directory)) {
    if (error)
      *error = L"The removal-control folder redirects through a link or "
               L"junction.";
    return false;
  }
  DirectoryIdentity identity;
  if (!ReadDirectoryIdentity(journal_directory, &identity, error) ||
      !identity.exists ||
      identity.volume_serial != plan.journal_directory_volume_serial ||
      identity.file_id != plan.journal_directory_file_id) {
    if (error && error->empty())
      *error = L"The removal-control folder changed after consent was saved.";
    return false;
  }
  return true;
}

bool ValidateJournalControlDirectory(const RemovalEnvironment &environment,
                                     const PersonalDataRemovalPlan &plan,
                                     std::wstring *error) {
  if (!SamePath(std::filesystem::path(plan.journal_path)
                    .parent_path()
                    .wstring(),
                environment.journal_directory) ||
      HasReparseAncestor(environment.local_app_data) ||
      HasReparseAncestor(environment.journal_directory) ||
      !JournalDirectoryStillMatches(plan, error)) {
    if (error && error->empty())
      *error = L"The removal-control folder is no longer safe.";
    return false;
  }
  DirectoryIdentity local_root;
  DirectoryIdentity journal_root;
  if (!ReadDirectoryIdentity(environment.local_app_data, &local_root, error) ||
      !local_root.exists ||
      !ReadDirectoryIdentity(environment.journal_directory, &journal_root,
                             error) ||
      !journal_root.exists ||
      !SameOrChildFinal(journal_root.final_path, local_root.final_path)) {
    if (error && error->empty())
      *error = L"The removal-control folder is not physically beneath this "
               L"account's local data folder.";
    return false;
  }
  return true;
}

bool ValidateLoadedPlan(const RemovalEnvironment &environment,
                        PersonalDataRemovalPlan *plan,
                        std::wstring *error) {
  const std::wstring default_profile =
      (std::filesystem::path(environment.roaming_app_data) /
       kProfileDirectoryName)
          .wstring();
  const std::wstring local_data =
      (std::filesystem::path(environment.local_app_data) /
       kProfileDirectoryName)
          .wstring();
  const std::wstring reset_marker =
      (std::filesystem::path(default_profile) / kResetMarkerFileName).wstring();
  const std::wstring journal =
      (std::filesystem::path(environment.journal_directory) /
       kRemovalJournalFileName)
          .wstring();
  const std::wstring mirror =
      (std::filesystem::path(environment.journal_directory) /
       kRemovalJournalMirrorFileName)
          .wstring();
  if (!SamePath(plan->local_data.path, local_data) ||
      !SamePath(plan->reset_marker_path, reset_marker) ||
      (!plan->custom_profile &&
       !SamePath(plan->active_profile.path, default_profile)) ||
      SameOrChild(environment.journal_directory, plan->active_profile.path) ||
      SameOrChild(plan->active_profile.path, environment.journal_directory) ||
      SameOrChild(environment.journal_directory, plan->local_data.path) ||
      SameOrChild(plan->local_data.path, environment.journal_directory) ||
      SameOrChild(environment.journal_directory, plan->install_root) ||
      SameOrChild(plan->install_root, environment.journal_directory) ||
      SameOrChild(plan->install_root, plan->active_profile.path) ||
      SameOrChild(plan->active_profile.path, plan->install_root) ||
      SameOrChild(plan->install_root, plan->local_data.path) ||
      SameOrChild(plan->local_data.path, plan->install_root)) {
    if (error)
      *error = L"The pending personal-data removal record has unsafe paths.";
    return false;
  }
  const std::array<std::wstring, 3> never_remove = {
      (std::filesystem::path(environment.roaming_app_data) /
       L"Black Spirit Life Beta")
          .wstring(),
      (std::filesystem::path(environment.roaming_app_data) /
       L"BDO Craft Planner Map Candidate")
          .wstring(),
      (std::filesystem::path(environment.roaming_app_data) /
       L"BDO Craft Planner Avalonia")
          .wstring(),
  };
  for (const auto &protected_path : never_remove) {
    if (SameOrChild(plan->active_profile.path, protected_path) ||
        SameOrChild(protected_path, plan->active_profile.path)) {
      if (error)
        *error = L"The active profile overlaps a preserved profile.";
      return false;
    }
  }
  plan->journal_path = journal;
  plan->journal_mirror_path = mirror;
  return ValidateJournalControlDirectory(environment, *plan, error);
}

PersonalDataRemovalResult Failure(PersonalDataRemovalStatus status,
                                  std::wstring message,
                                  const std::wstring &journal_path = {}) {
  return {
      .success = false,
      .status = status,
      .message = std::move(message),
      .journal_path = journal_path,
  };
}

PersonalDataRemovalResult StatusResult(const PersonalDataRemovalPlan &plan,
                                       std::wstring message) {
  return {
      .success = true,
      .application_removed =
          plan.status == PersonalDataRemovalStatus::application_removed ||
          plan.status == PersonalDataRemovalStatus::cleanup_pending ||
          plan.status == PersonalDataRemovalStatus::complete,
      .removed = plan.status == PersonalDataRemovalStatus::complete,
      .retained_quarantine =
          (plan.active_profile.quarantined &&
           !plan.active_profile.recycled) ||
          (plan.local_data.quarantined && !plan.local_data.recycled),
      .retry_available =
          plan.status == PersonalDataRemovalStatus::application_removed ||
          plan.status == PersonalDataRemovalStatus::cleanup_pending ||
          plan.status == PersonalDataRemovalStatus::complete,
      .status = plan.status,
      .message = std::move(message),
      .journal_path = plan.journal_path,
  };
}

PersonalDataRemovalResult DetectWithEnvironment(
    const RemovalEnvironment &environment, PersonalDataRemovalPlan *plan) {
  if (plan)
    *plan = {};
  if (HasReparseAncestor(environment.roaming_app_data) ||
      HasReparseAncestor(environment.local_app_data) ||
      HasReparseAncestor(environment.journal_directory)) {
    return Failure(PersonalDataRemovalStatus::invalid,
                   L"A pending removal-control path redirects through a link "
                   L"or junction. Nothing was changed.");
  }
  const std::wstring journal =
      (std::filesystem::path(environment.journal_directory) /
       kRemovalJournalFileName)
          .wstring();
  const std::wstring mirror =
      (std::filesystem::path(environment.journal_directory) /
       kRemovalJournalMirrorFileName)
          .wstring();
  DirectoryIdentity control_identity;
  ScopedHandle control_lease;
  std::wstring control_error;
  if (!ReadDirectoryIdentity(
          environment.journal_directory, &control_identity, &control_error,
          FILE_READ_ATTRIBUTES, FILE_SHARE_READ | FILE_SHARE_WRITE,
          &control_lease)) {
    return Failure(PersonalDataRemovalStatus::invalid,
                   control_error.empty()
                       ? L"The removal-control folder could not be reserved "
                         L"safely."
                       : control_error,
                   journal);
  }
  const FileReadResult primary = ReadSmallOrdinaryFile(journal);
  const FileReadResult committed = ReadSmallOrdinaryFile(mirror);
  if (primary.state == FileReadState::missing &&
      committed.state == FileReadState::missing) {
    return {.success = true,
            .status = PersonalDataRemovalStatus::none,
            .message = L"No personal-data cleanup is pending."};
  }
  if (!control_identity.exists) {
    return Failure(PersonalDataRemovalStatus::invalid,
                   L"A removal record exists without its verified control "
                   L"folder. Nothing was changed.",
                   journal);
  }
  if (committed.state != FileReadState::valid) {
    return Failure(PersonalDataRemovalStatus::invalid,
                   L"The committed personal-data removal record is missing or "
                   L"unreadable. Nothing was removed.",
                   journal);
  }
  PersonalDataRemovalPlan loaded;
  std::wstring validation_error;
  if (!ParseJournal(committed.bytes, &loaded) ||
      !ValidateLoadedPlan(environment, &loaded, &validation_error)) {
    return Failure(PersonalDataRemovalStatus::invalid,
                   validation_error.empty()
                       ? L"The personal-data removal record is invalid. Nothing "
                         L"was removed."
                       : validation_error,
                   journal);
  }
  if (primary.state != FileReadState::valid ||
      primary.bytes != committed.bytes) {
    std::wstring repair_error;
    if (!WriteDurableFile(journal,
                          std::string(committed.bytes.begin(),
                                      committed.bytes.end()),
                          loaded.transaction_id, &repair_error)) {
      return Failure(PersonalDataRemovalStatus::invalid,
                     L"The committed removal record is safe, but its working "
                     L"copy could not be repaired.",
                     journal);
    }
  }
  if (plan)
    *plan = loaded;
  return StatusResult(loaded, L"A personal-data removal task is pending.");
}

bool SameImmutableTarget(const PersonalDataRemovalTarget &left,
                         const PersonalDataRemovalTarget &right) {
  return left.present == right.present && SamePath(left.path, right.path) &&
         SamePath(left.quarantine_path, right.quarantine_path) &&
         left.volume_serial == right.volume_serial &&
         left.file_id == right.file_id &&
         left.parent_volume_serial == right.parent_volume_serial &&
         left.parent_file_id == right.parent_file_id;
}

bool SameImmutablePlan(const PersonalDataRemovalPlan &left,
                       const PersonalDataRemovalPlan &right) {
  return left.transaction_id == right.transaction_id &&
         left.journal_directory_volume_serial ==
             right.journal_directory_volume_serial &&
         left.journal_directory_file_id == right.journal_directory_file_id &&
         SamePath(left.reset_marker_path, right.reset_marker_path) &&
         SamePath(left.install_root, right.install_root) &&
         SamePath(left.registered_install_root,
                  right.registered_install_root) &&
         left.installed_version == right.installed_version &&
         left.install_root_volume_serial == right.install_root_volume_serial &&
         left.install_root_file_id == right.install_root_file_id &&
         left.custom_profile == right.custom_profile &&
         SameImmutableTarget(left.active_profile, right.active_profile) &&
         SameImmutableTarget(left.local_data, right.local_data);
}

bool ValidResetMarker(const std::wstring &directory) {
  const FileReadResult marker = ReadSmallOrdinaryFile(
      (std::filesystem::path(directory) / kResetMarkerFileName).wstring());
  if (marker.state != FileReadState::valid)
    return false;
  std::map<std::wstring, JsonScalar> values;
  if (!ParseIdentityJson(marker.bytes, &values))
    return false;
  const auto intentional = values.find(L"intentionalReset");
  const auto transaction = values.find(L"transactionId");
  return intentional != values.end() &&
         intentional->second.kind == JsonScalarKind::boolean &&
         intentional->second.boolean && transaction != values.end() &&
         transaction->second.kind == JsonScalarKind::string &&
         IsIdentityToken(transaction->second.text);
}

enum class DirectoryUse { empty, has_entries, unreadable };

DirectoryUse InspectDirectoryUse(const std::wstring &path) {
  WIN32_FIND_DATAW data{};
  HANDLE find = FindFirstFileW(
      (std::filesystem::path(path) / L"*").wstring().c_str(), &data);
  if (find == INVALID_HANDLE_VALUE) {
    return GetLastError() == ERROR_FILE_NOT_FOUND ? DirectoryUse::empty
                                                  : DirectoryUse::unreadable;
  }
  DirectoryUse result = DirectoryUse::empty;
  do {
    if (std::wcscmp(data.cFileName, L".") != 0 &&
        std::wcscmp(data.cFileName, L"..") != 0) {
      result = DirectoryUse::has_entries;
      break;
    }
  } while (FindNextFileW(find, &data));
  const DWORD enumeration_error = GetLastError();
  FindClose(find);
  if (result == DirectoryUse::empty && enumeration_error != ERROR_NO_MORE_FILES)
    return DirectoryUse::unreadable;
  return result;
}

bool CaptureTarget(const std::wstring &path, const std::wstring &transaction_id,
                   bool require_profile_ownership,
                   bool exact_default_profile,
                   PersonalDataRemovalTarget *target, std::wstring *error) {
  *target = {};
  target->path = Normalize(path);
  if (target->path.empty() || HasReparseAncestor(target->path)) {
    if (error)
      *error = L"A planner-data path redirects through a link or junction.";
    return false;
  }
  const std::filesystem::path parent =
      std::filesystem::path(target->path).parent_path();
  DirectoryIdentity parent_identity;
  if (parent.empty() ||
      !ReadDirectoryIdentity(parent.wstring(), &parent_identity, error) ||
      !parent_identity.exists) {
    if (error && error->empty())
      *error = L"A planner-data parent folder could not be verified.";
    return false;
  }
  target->parent_volume_serial = parent_identity.volume_serial;
  target->parent_file_id = parent_identity.file_id;
  target->quarantine_path =
      target->path + L".bsl-uninstall-" + transaction_id;
  const DWORD quarantine_attributes =
      GetFileAttributesW(target->quarantine_path.c_str());
  if (quarantine_attributes != INVALID_FILE_ATTRIBUTES ||
      !MissingPathError(GetLastError())) {
    if (error)
      *error = L"A personal-data quarantine path already exists.";
    return false;
  }

  DirectoryIdentity identity;
  if (!ReadDirectoryIdentity(target->path, &identity, error))
    return false;
  if (!identity.exists)
    return true;
  target->present = true;
  target->volume_serial = identity.volume_serial;
  target->file_id = identity.file_id;
  if (identity.volume_serial != parent_identity.volume_serial ||
      !SameOrChildFinal(identity.final_path, parent_identity.final_path)) {
    if (error)
      *error = L"A planner-data folder is not physically beneath its parent.";
    return false;
  }
  if (TreeContainsReparsePoint(target->path, error))
    return false;
  if (require_profile_ownership &&
      (!ValidOwnedProfileMarker(target->path) ||
       !HasProfileStateWitness(target->path))) {
    if (error)
      *error = L"The custom personal-data folder is not a verified Black "
               L"Spirit Life profile.";
    return false;
  }
  if (exact_default_profile &&
      !HasProfileStateWitness(target->path) &&
      !ValidOwnedProfileMarker(target->path) &&
      !ValidResetMarker(target->path) &&
      InspectDirectoryUse(target->path) != DirectoryUse::empty) {
    if (error)
      *error = L"The default data folder has no app-owned profile "
               L"witness, so it was not selected for removal.";
    return false;
  }
  return true;
}

bool PhysicalTargetsOverlap(const PersonalDataRemovalTarget &left,
                            const PersonalDataRemovalTarget &right) {
  if (!left.present || !right.present)
    return false;
  DirectoryIdentity left_identity;
  DirectoryIdentity right_identity;
  std::wstring ignored;
  if (!ReadDirectoryIdentity(left.path, &left_identity, &ignored) ||
      !ReadDirectoryIdentity(right.path, &right_identity, &ignored) ||
      !left_identity.exists || !right_identity.exists) {
    return true;
  }
  return SameOrChildFinal(left_identity.final_path, right_identity.final_path) ||
         SameOrChildFinal(right_identity.final_path, left_identity.final_path);
}

bool TargetPhysicallyOverlapsExistingPath(
    const PersonalDataRemovalTarget &target, const std::wstring &protected_path,
    std::wstring *error) {
  if (!target.present)
    return false;
  DirectoryIdentity target_identity;
  DirectoryIdentity protected_identity;
  if (!ReadDirectoryIdentity(target.path, &target_identity, error) ||
      !target_identity.exists ||
      !ReadDirectoryIdentity(protected_path, &protected_identity, error)) {
    if (error && error->empty()) {
      *error = L"A protected folder could not be physically verified.";
    }
    return true;
  }
  if (!protected_identity.exists)
    return false;
  if (SameOrChildFinal(target_identity.final_path,
                       protected_identity.final_path) ||
      SameOrChildFinal(protected_identity.final_path,
                       target_identity.final_path)) {
    if (error)
      *error = L"The active profile physically overlaps a preserved folder.";
    return true;
  }
  return false;
}

bool VerifyRegisteredInstall(const InstalledBeta &installed,
                             std::wstring *registered_root,
                             std::wstring *error) {
  bool exists = false;
  std::wstring registered;
  if (!QueryRegisteredInstallLocation(&registered, &exists, error) || !exists) {
    if (error && error->empty())
      *error = L"The installed application registration is missing.";
    return false;
  }
  InstalledBeta verified;
  std::wstring verification_error;
  if (!VerifyInstalledBetaRoot(registered, &verified, &verification_error) ||
      verified.root_volume_serial != installed.root_volume_serial ||
      verified.root_file_id != installed.root_file_id) {
    if (error)
      *error = L"The installed application registration does not match the captured "
               L"application folder.";
    return false;
  }
  *registered_root = Normalize(registered);
  return !registered_root->empty();
}

PersonalDataRemovalResult PrepareWithEnvironment(
    const RemovalEnvironment &environment, const std::wstring &install_root,
    bool require_registration, PersonalDataRemovalPlan *output) {
  if (output)
    *output = {};
  PersonalDataRemovalPlan pending;
  const PersonalDataRemovalResult detected =
      DetectWithEnvironment(environment, &pending);
  if (!detected.success || detected.status != PersonalDataRemovalStatus::none) {
    return detected.success
               ? Failure(detected.status,
                         L"A previous personal-data removal task must be "
                         L"finished or canceled first.",
                         detected.journal_path)
               : detected;
  }

  InstalledBeta installed;
  std::wstring error;
  if (!VerifyInstalledBetaRoot(install_root, &installed, &error)) {
    return Failure(PersonalDataRemovalStatus::invalid,
                   L"The installed application could not be verified before planner "
                   L"data removal was prepared.");
  }
  std::wstring registered_root = installed.root;
  if (require_registration &&
      !VerifyRegisteredInstall(installed, &registered_root, &error)) {
    return Failure(PersonalDataRemovalStatus::invalid, error);
  }

  if (HasReparseAncestor(environment.roaming_app_data) ||
      HasReparseAncestor(environment.local_app_data) ||
      HasReparseAncestor(environment.journal_directory)) {
    return Failure(PersonalDataRemovalStatus::invalid,
                   L"An account data path redirects through a link or "
                    L"junction. Nothing was prepared.");
  }
  if (!EnsureOrdinaryDirectory(environment.journal_directory, &error))
    return Failure(PersonalDataRemovalStatus::invalid, error);
  DirectoryIdentity journal_directory_identity;
  DirectoryIdentity local_root_identity;
  if (!ReadDirectoryIdentity(environment.journal_directory,
                             &journal_directory_identity, &error) ||
      !journal_directory_identity.exists ||
      !ReadDirectoryIdentity(environment.local_app_data, &local_root_identity,
                             &error) ||
      !local_root_identity.exists ||
      !SameOrChildFinal(journal_directory_identity.final_path,
                        local_root_identity.final_path)) {
    return Failure(
        PersonalDataRemovalStatus::invalid,
        error.empty()
            ? L"The removal-control folder is not physically beneath this "
              L"account's local data folder."
            : error);
  }
  const std::filesystem::path default_profile =
      std::filesystem::path(environment.roaming_app_data) /
      kProfileDirectoryName;
  const std::filesystem::path local_data =
      std::filesystem::path(environment.local_app_data) /
      kProfileDirectoryName;
  const std::filesystem::path bootstrap =
      local_data / kBootstrapDirectoryName;
  const DWORD move_attributes =
      GetFileAttributesW((bootstrap / kMoveJournalFileName).c_str());
  if (move_attributes != INVALID_FILE_ATTRIBUTES ||
      !MissingPathError(GetLastError())) {
    return Failure(
        PersonalDataRemovalStatus::invalid,
        L"A personal-data move is unfinished. Open Black Spirit Life "
        L"once to complete recovery before removing planner data.");
  }

  std::wstring primary_location;
  std::wstring mirror_location;
  FileReadState primary_state = FileReadState::missing;
  FileReadState mirror_state = FileReadState::missing;
  const bool primary_valid =
      ParseLocator((bootstrap / kLocatorFileName).wstring(),
                   &primary_location, &primary_state);
  const bool mirror_valid =
      ParseLocator((bootstrap / kLocatorMirrorFileName).wstring(),
                   &mirror_location, &mirror_state);
  bool custom_profile = false;
  std::wstring active_profile = default_profile.wstring();
  if (primary_state == FileReadState::missing &&
      mirror_state == FileReadState::missing) {
    custom_profile = false;
  } else if (primary_valid && mirror_valid &&
             SamePath(primary_location, mirror_location)) {
    active_profile = mirror_location;
    custom_profile = !SamePath(active_profile, default_profile.wstring());
  } else {
    return Failure(PersonalDataRemovalStatus::invalid,
                   L"The saved personal-data location records do not match. "
                   L"Nothing was prepared.");
  }

  PersonalDataRemovalPlan plan;
  plan.status = PersonalDataRemovalStatus::prepared;
  plan.transaction_id = NewTransactionIdentity();
  if (plan.transaction_id.empty()) {
    return Failure(PersonalDataRemovalStatus::invalid,
                   L"A secure removal transaction could not be created.");
  }
  plan.journal_path =
      (std::filesystem::path(environment.journal_directory) /
       kRemovalJournalFileName)
          .wstring();
  plan.journal_mirror_path =
      (std::filesystem::path(environment.journal_directory) /
       kRemovalJournalMirrorFileName)
          .wstring();
  plan.journal_directory_volume_serial =
      journal_directory_identity.volume_serial;
  plan.journal_directory_file_id = journal_directory_identity.file_id;
  plan.reset_marker_path =
      (default_profile / kResetMarkerFileName).wstring();
  plan.install_root = Normalize(installed.root);
  plan.registered_install_root = Normalize(registered_root);
  plan.installed_version = installed.version;
  plan.install_root_volume_serial = installed.root_volume_serial;
  plan.install_root_file_id = installed.root_file_id;
  plan.custom_profile = custom_profile;

  if (!CaptureTarget(active_profile, plan.transaction_id, custom_profile,
                     !custom_profile, &plan.active_profile, &error) ||
      !CaptureTarget(local_data.wstring(), plan.transaction_id, false, false,
                     &plan.local_data, &error)) {
    return Failure(PersonalDataRemovalStatus::invalid, error);
  }
  if (custom_profile && !plan.active_profile.present) {
    return Failure(PersonalDataRemovalStatus::invalid,
                   L"The configured custom personal-data folder is "
                   L"unavailable. Nothing was prepared.");
  }
  if (SameOrChild(plan.active_profile.path, plan.local_data.path) ||
      SameOrChild(plan.local_data.path, plan.active_profile.path) ||
      PhysicalTargetsOverlap(plan.active_profile, plan.local_data)) {
    return Failure(PersonalDataRemovalStatus::invalid,
                   L"The planner profile and application cache overlap. Nothing was "
                   L"prepared.");
  }
  const std::array<std::wstring, 4> physically_preserved = {
      plan.install_root,
      (std::filesystem::path(environment.roaming_app_data) /
       L"Black Spirit Life Beta")
          .wstring(),
      (std::filesystem::path(environment.roaming_app_data) /
       L"BDO Craft Planner Map Candidate")
          .wstring(),
      (std::filesystem::path(environment.roaming_app_data) /
       L"BDO Craft Planner Avalonia")
          .wstring(),
  };
  for (const auto &protected_path : physically_preserved) {
    if (TargetPhysicallyOverlapsExistingPath(plan.active_profile,
                                             protected_path, &error)) {
      return Failure(PersonalDataRemovalStatus::invalid, error);
    }
  }
  if (!ValidateLoadedPlan(environment, &plan, &error))
    return Failure(PersonalDataRemovalStatus::invalid, error);
  if (!WriteJournal(plan, &error))
    return Failure(PersonalDataRemovalStatus::invalid, error);
  if (output)
    *output = plan;
  return StatusResult(
      plan,
      L"Planner-data removal is prepared. No personal files have been changed.");
}

bool CapturedApplicationRemoved(const PersonalDataRemovalPlan &plan,
                                bool require_registration,
                                std::wstring *error) {
  if (require_registration) {
    std::wstring registered;
    bool registration_exists = false;
    if (!QueryRegisteredInstallLocation(&registered, &registration_exists,
                                        error)) {
      return false;
    }
    // A new registration means the application has been installed again. Do not remove
    // data that may already belong to that new installation.
    if (registration_exists) {
      if (error)
        *error = L"A Black Spirit Life registration is still present.";
      return false;
    }
  }

  DirectoryIdentity root_identity;
  if (!ReadDirectoryIdentity(plan.install_root, &root_identity, error))
    return false;
  if (root_identity.exists &&
      (root_identity.volume_serial != plan.install_root_volume_serial ||
       root_identity.file_id != plan.install_root_file_id)) {
    if (error)
      *error = L"The old application path now belongs to a different folder.";
    return false;
  }
  const std::filesystem::path root(plan.install_root);
  const std::array<std::filesystem::path, 4> required_files = {
      root / L"BlackSpiritLife.exe",
      root / L"current" / L"BlackSpiritLife.exe",
      root / L"current" / L"BlackSpiritLifeUpdater.exe",
      root / L"current" / L"sq.version",
  };
  for (const auto &file : required_files) {
    const DWORD attributes = GetFileAttributesW(file.c_str());
    if (attributes != INVALID_FILE_ATTRIBUTES) {
      if (error)
        *error = L"The captured application is still installed.";
      return false;
    }
    if (!MissingPathError(GetLastError())) {
      if (error)
        *error = L"Windows could not prove that every captured application "
                 L"entry point is gone.";
      return false;
    }
  }
  return true;
}

bool CapturedApplicationPresent(const PersonalDataRemovalPlan &plan,
                                bool require_registration,
                                std::wstring *error) {
  InstalledBeta installed;
  std::wstring verification_error;
  if (!VerifyInstalledBetaRoot(plan.install_root, &installed,
                               &verification_error) ||
      installed.root_volume_serial != plan.install_root_volume_serial ||
      installed.root_file_id != plan.install_root_file_id ||
      installed.version != plan.installed_version) {
    if (error)
      *error = L"The captured application is no longer unchanged.";
    return false;
  }
  if (!require_registration)
    return true;
  std::wstring registered;
  bool exists = false;
  if (!QueryRegisteredInstallLocation(&registered, &exists, error) || !exists ||
      !SamePath(registered, plan.registered_install_root)) {
    if (error && error->empty())
      *error = L"The captured application registration changed.";
    return false;
  }
  return true;
}

bool OriginalTargetStillMatches(const PersonalDataRemovalTarget &target,
                                std::wstring *error) {
  const DWORD quarantine_attributes =
      GetFileAttributesW(target.quarantine_path.c_str());
  if (quarantine_attributes != INVALID_FILE_ATTRIBUTES ||
      !MissingPathError(GetLastError()) || target.quarantined ||
      target.recycled) {
    if (error)
      *error = L"A planner-data target already entered quarantine.";
    return false;
  }
  DirectoryIdentity current;
  if (!ReadDirectoryIdentity(target.path, &current, error))
    return false;
  if (!target.present)
    return !current.exists;
  if (!IdentityMatches(current, target)) {
    if (error)
      *error = L"A planner-data target changed after consent was captured.";
    return false;
  }
  return true;
}

PersonalDataRemovalResult MarkWithEnvironment(
    const RemovalEnvironment &environment,
    const PersonalDataRemovalPlan &requested_plan,
    bool require_registration) {
  PersonalDataRemovalPlan plan;
  PersonalDataRemovalResult detected =
      DetectWithEnvironment(environment, &plan);
  if (!detected.success)
    return detected;
  if (!SameImmutablePlan(requested_plan, plan)) {
    return Failure(PersonalDataRemovalStatus::invalid,
                   L"The pending removal task does not match this request.",
                   detected.journal_path);
  }
  if (plan.status != PersonalDataRemovalStatus::prepared) {
    return StatusResult(plan,
                        L"Application removal was already recorded for this "
                        L"personal-data task.");
  }
  std::wstring error;
  if (!CapturedApplicationRemoved(plan, require_registration, &error)) {
    return Failure(PersonalDataRemovalStatus::prepared,
                   error + L" Planner data was not changed.",
                   plan.journal_path);
  }
  plan.status = PersonalDataRemovalStatus::application_removed;
  if (!WriteJournal(plan, &error))
    return Failure(PersonalDataRemovalStatus::prepared, error,
                   plan.journal_path);
  return StatusResult(plan,
                      L"Application removal was confirmed. Planner-data "
                      L"cleanup can now continue.");
}

PersonalDataRemovalResult CancelWithEnvironment(
    const RemovalEnvironment &environment,
    const PersonalDataRemovalPlan &requested_plan,
    bool require_registration) {
  PersonalDataRemovalPlan plan;
  PersonalDataRemovalResult detected =
      DetectWithEnvironment(environment, &plan);
  if (!detected.success)
    return detected;
  if (detected.status == PersonalDataRemovalStatus::none) {
    return detected;
  }
  if (!SameImmutablePlan(requested_plan, plan) ||
      plan.status != PersonalDataRemovalStatus::prepared ||
      plan.active_profile.quarantined || plan.active_profile.recycled ||
      plan.local_data.quarantined || plan.local_data.recycled) {
    return Failure(plan.status,
                   L"This removal task can no longer be canceled safely.",
                   plan.journal_path);
  }
  std::wstring error;
  if (!CapturedApplicationPresent(plan, require_registration, &error) ||
      !OriginalTargetStillMatches(plan.active_profile, &error) ||
      !OriginalTargetStillMatches(plan.local_data, &error)) {
    return Failure(PersonalDataRemovalStatus::prepared,
                   error + L" The durable removal record was kept.",
                   plan.journal_path);
  }
  if (!ClearJournal(plan, &error)) {
    return Failure(PersonalDataRemovalStatus::prepared, error,
                   plan.journal_path);
  }
  return {.success = true,
          .status = PersonalDataRemovalStatus::none,
          .message = L"Planner-data removal was canceled. No personal files "
                     L"were changed."};
}

bool ParentStillMatches(const PersonalDataRemovalTarget &target,
                        std::wstring *error) {
  DirectoryIdentity parent;
  if (!ReadDirectoryIdentity(
          std::filesystem::path(target.path).parent_path().wstring(), &parent,
          error) ||
      !parent.exists || parent.volume_serial != target.parent_volume_serial ||
      parent.file_id != target.parent_file_id) {
    if (error && error->empty())
      *error = L"A planner-data parent folder changed during removal.";
    return false;
  }
  return true;
}

bool RenameDirectoryByHandle(const PersonalDataRemovalTarget &target,
                             std::wstring *error) {
  ScopedHandle handle;
  DirectoryIdentity identity;
  if (!ReadDirectoryIdentity(
          target.path, &identity, error, DELETE | FILE_READ_ATTRIBUTES,
          FILE_SHARE_READ | FILE_SHARE_WRITE, &handle) ||
      !IdentityMatches(identity, target)) {
    if (error && error->empty())
      *error = L"A planner-data folder changed before quarantine.";
    return false;
  }
  if (!ParentStillMatches(target, error) ||
      TreeContainsReparsePoint(target.path, error)) {
    return false;
  }
  const DWORD quarantine_attributes =
      GetFileAttributesW(target.quarantine_path.c_str());
  if (quarantine_attributes != INVALID_FILE_ATTRIBUTES ||
      !MissingPathError(GetLastError())) {
    if (error)
      *error = L"The quarantine destination is no longer empty.";
    return false;
  }
  const DWORD name_bytes = static_cast<DWORD>(target.quarantine_path.size() *
                                               sizeof(wchar_t));
  std::vector<BYTE> buffer(sizeof(FILE_RENAME_INFO) + name_bytes);
  auto *rename = reinterpret_cast<FILE_RENAME_INFO *>(buffer.data());
  rename->ReplaceIfExists = FALSE;
  rename->RootDirectory = nullptr;
  rename->FileNameLength = name_bytes;
  std::memcpy(rename->FileName, target.quarantine_path.data(), name_bytes);
  if (!SetFileInformationByHandle(handle.get(), FileRenameInfo, rename,
                                  static_cast<DWORD>(buffer.size()))) {
    if (error)
      *error = L"The verified planner-data folder could not enter quarantine.";
    return false;
  }
  handle.Reset();
  DirectoryIdentity quarantined;
  if (!ReadDirectoryIdentity(target.quarantine_path, &quarantined, error) ||
      !IdentityMatches(quarantined, target)) {
    if (error && error->empty())
      *error = L"The planner-data quarantine identity could not be verified.";
    return false;
  }
  const DWORD original_attributes = GetFileAttributesW(target.path.c_str());
  if (original_attributes != INVALID_FILE_ATTRIBUTES ||
      !MissingPathError(GetLastError())) {
    if (error)
      *error = L"The original planner-data path remained after quarantine.";
    return false;
  }
  return true;
}

bool EnsureTargetQuarantined(PersonalDataRemovalTarget *target,
                             bool require_custom_marker,
                             std::wstring *error) {
  if (!ParentStillMatches(*target, error))
    return false;
  DirectoryIdentity original;
  DirectoryIdentity quarantine;
  if (!ReadDirectoryIdentity(target->path, &original, error) ||
      !ReadDirectoryIdentity(target->quarantine_path, &quarantine, error)) {
    return false;
  }
  if (!target->present) {
    if (original.exists || quarantine.exists) {
      if (error)
        *error = L"An unplanned planner-data folder appeared after consent.";
      return false;
    }
    target->recycled = true;
    return true;
  }
  if (original.exists && quarantine.exists) {
    if (error)
      *error = L"Both original and quarantine planner-data folders exist.";
    return false;
  }
  if (quarantine.exists) {
    if (!IdentityMatches(quarantine, *target) ||
        TreeContainsReparsePoint(target->quarantine_path, error) ||
        (require_custom_marker &&
         !ValidOwnedProfileMarker(target->quarantine_path))) {
      if (error && error->empty())
        *error = L"The retained planner-data quarantine is not the captured "
                 L"folder.";
      return false;
    }
    target->quarantined = true;
    return true;
  }
  if (!original.exists) {
    if (target->recycled)
      return true;
    if (error) {
      *error = target->quarantined
                   ? L"The recorded planner-data quarantine is missing, so "
                     L"Windows cannot prove that it reached the Recycle Bin."
                   : L"The captured planner-data folder disappeared before "
                     L"it entered verified quarantine.";
    }
    return false;
  }
  if (!IdentityMatches(original, *target) ||
      (require_custom_marker && !ValidOwnedProfileMarker(target->path)) ||
      !RenameDirectoryByHandle(*target, error)) {
    if (error && error->empty())
      *error = L"The captured planner-data folder changed before quarantine.";
    return false;
  }
  target->quarantined = true;
  return true;
}

bool RecycleWithWindows(const std::wstring &path, std::wstring *error) {
  const HRESULT initialized =
      CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED | COINIT_DISABLE_OLE1DDE);
  const bool uninitialize = SUCCEEDED(initialized);
  if (FAILED(initialized) && initialized != RPC_E_CHANGED_MODE) {
    if (error)
      *error = L"Windows could not initialize the Recycle Bin operation.";
    return false;
  }
  IFileOperation *operation = nullptr;
  IShellItem *item = nullptr;
  HRESULT result = CoCreateInstance(CLSID_FileOperation, nullptr,
                                    CLSCTX_INPROC_SERVER,
                                    IID_PPV_ARGS(&operation));
  if (SUCCEEDED(result)) {
    result = operation->SetOperationFlags(
        FOF_ALLOWUNDO | FOF_NOCONFIRMATION | FOF_NOERRORUI | FOF_SILENT |
        FOFX_RECYCLEONDELETE | FOFX_EARLYFAILURE);
  }
  if (SUCCEEDED(result)) {
    result = SHCreateItemFromParsingName(path.c_str(), nullptr,
                                         IID_PPV_ARGS(&item));
  }
  if (SUCCEEDED(result))
    result = operation->DeleteItem(item, nullptr);
  if (SUCCEEDED(result))
    result = operation->PerformOperations();
  BOOL aborted = TRUE;
  const HRESULT aborted_result =
      operation == nullptr ? E_POINTER
                           : operation->GetAnyOperationsAborted(&aborted);
  if (item != nullptr)
    item->Release();
  if (operation != nullptr)
    operation->Release();
  if (uninitialize)
    CoUninitialize();
  if (FAILED(result) || FAILED(aborted_result) || aborted) {
    if (error)
      *error = L"Windows could not move the planner-data quarantine to the "
               L"Recycle Bin. It was retained for retry.";
    return false;
  }
  return true;
}

bool RecycleTarget(PersonalDataRemovalTarget *target,
                   const PersonalDataRecycleCallback &recycle,
                   std::wstring *error) {
  if (target->recycled)
    return true;
  if (!target->quarantined) {
    if (error)
      *error = L"A planner-data target was not quarantined.";
    return false;
  }
  DirectoryIdentity quarantine;
  if (!ReadDirectoryIdentity(target->quarantine_path, &quarantine, error))
    return false;
  if (!quarantine.exists) {
    if (error)
      *error = L"The planner-data quarantine is missing, so Windows cannot "
               L"prove that it reached the Recycle Bin.";
    return false;
  }
  if (!IdentityMatches(quarantine, *target) ||
      TreeContainsReparsePoint(target->quarantine_path, error)) {
    if (error && error->empty())
      *error = L"The quarantine changed before it reached the Recycle Bin.";
    return false;
  }
  if (!recycle(target->quarantine_path, error))
    return false;
  const DWORD quarantine_attributes =
      GetFileAttributesW(target->quarantine_path.c_str());
  const DWORD quarantine_error = GetLastError();
  const DWORD original_attributes = GetFileAttributesW(target->path.c_str());
  const DWORD original_error = GetLastError();
  if (quarantine_attributes != INVALID_FILE_ATTRIBUTES ||
      !MissingPathError(quarantine_error) ||
      original_attributes != INVALID_FILE_ATTRIBUTES ||
      !MissingPathError(original_error) || !ParentStillMatches(*target, error)) {
    if (error && error->empty())
      *error = L"Windows did not confirm that quarantine reached the Recycle "
               L"Bin.";
    return false;
  }
  target->recycled = true;
  return true;
}

std::string JsonEscapeAscii(std::wstring_view value) {
  std::string result;
  for (const wchar_t character : value) {
    if (character == L'"' || character == L'\\')
      result.push_back('\\');
    if (character < 0x20 || character > 0x7E)
      return {};
    result.push_back(static_cast<char>(character));
  }
  return result;
}

bool WriteResetMarker(const PersonalDataRemovalPlan &plan,
                      std::wstring *error) {
  const std::filesystem::path directory =
      std::filesystem::path(plan.reset_marker_path).parent_path();
  if (!EnsureOrdinaryDirectory(directory.wstring(), error) ||
      HasReparseAncestor(plan.reset_marker_path)) {
    if (error && error->empty())
      *error = L"The intentional-reset marker path is unsafe.";
    return false;
  }
  const std::string marker =
      "{\"schemaVersion\":1,\"packageId\":\"" +
      JsonEscapeAscii(build_config::kPackageId) +
      "\",\"releaseChannel\":\"" + JsonEscapeAscii(build_config::kChannel) +
      "\",\"intentionalReset\":true,\"transactionId\":\"" +
      JsonEscapeAscii(plan.transaction_id) + "\"}";
  return WriteDurableFile(plan.reset_marker_path, marker, plan.transaction_id,
                          error);
}

bool ResetMarkerMatches(const PersonalDataRemovalPlan &plan) {
  const FileReadResult marker = ReadSmallOrdinaryFile(plan.reset_marker_path);
  if (marker.state != FileReadState::valid)
    return false;
  std::map<std::wstring, JsonScalar> values;
  if (!ParseIdentityJson(marker.bytes, &values))
    return false;
  const auto reset = values.find(L"intentionalReset");
  const auto transaction = values.find(L"transactionId");
  return reset != values.end() &&
         reset->second.kind == JsonScalarKind::boolean &&
         reset->second.boolean && transaction != values.end() &&
         transaction->second.kind == JsonScalarKind::string &&
         transaction->second.text == plan.transaction_id;
}

PersonalDataRemovalResult FinalizeWithEnvironment(
    const RemovalEnvironment &environment,
    const PersonalDataRemovalPlan &requested_plan,
    bool require_registration,
    const PersonalDataRecycleCallback &recycle) {
  PersonalDataRemovalPlan plan;
  PersonalDataRemovalResult detected =
      DetectWithEnvironment(environment, &plan);
  if (!detected.success)
    return detected;
  if (!SameImmutablePlan(requested_plan, plan)) {
    return Failure(PersonalDataRemovalStatus::invalid,
                   L"The pending cleanup does not match this removal request.",
                   detected.journal_path);
  }
  std::wstring error;
  if (!ValidateJournalControlDirectory(environment, plan, &error)) {
    return Failure(PersonalDataRemovalStatus::invalid, error,
                   plan.journal_path);
  }
  if (plan.status == PersonalDataRemovalStatus::prepared) {
    if (!CapturedApplicationRemoved(plan, require_registration, &error)) {
      return Failure(PersonalDataRemovalStatus::prepared,
                     error + L" Planner data was not changed.",
                     plan.journal_path);
    }
    plan.status = PersonalDataRemovalStatus::application_removed;
    if (!WriteJournal(plan, &error))
      return Failure(PersonalDataRemovalStatus::prepared, error,
                     plan.journal_path);
  }
  if (plan.status == PersonalDataRemovalStatus::complete) {
    if (!ResetMarkerMatches(plan)) {
      return Failure(PersonalDataRemovalStatus::cleanup_pending,
                     L"The intentional-reset marker could not be verified.",
                     plan.journal_path);
    }
    if (!ClearJournal(plan, &error)) {
      PersonalDataRemovalResult result = Failure(
          PersonalDataRemovalStatus::complete, error, plan.journal_path);
      result.application_removed = true;
      result.removed = true;
      result.retry_available = true;
      return result;
    }
    return {.success = true,
            .application_removed = true,
            .removed = true,
            .status = PersonalDataRemovalStatus::complete,
            .message = L"Planner data was moved to the Recycle Bin."};
  }
  plan.status = PersonalDataRemovalStatus::cleanup_pending;
  const auto checkpoint = [&]() { return WriteJournal(plan, &error); };
  if (!ValidateJournalControlDirectory(environment, plan, &error) ||
      !EnsureTargetQuarantined(&plan.active_profile, plan.custom_profile,
                               &error) ||
      !checkpoint() ||
      !ValidateJournalControlDirectory(environment, plan, &error) ||
      !EnsureTargetQuarantined(&plan.local_data, false, &error) ||
      !checkpoint()) {
    PersonalDataRemovalResult result = Failure(
        PersonalDataRemovalStatus::cleanup_pending, error, plan.journal_path);
    result.application_removed = true;
    result.retained_quarantine =
        (plan.active_profile.quarantined &&
         !plan.active_profile.recycled) ||
        (plan.local_data.quarantined && !plan.local_data.recycled);
    result.retry_available = true;
    return result;
  }
  if (!ValidateJournalControlDirectory(environment, plan, &error) ||
      !RecycleTarget(&plan.active_profile, recycle, &error) || !checkpoint() ||
      !ValidateJournalControlDirectory(environment, plan, &error) ||
      !RecycleTarget(&plan.local_data, recycle, &error) || !checkpoint()) {
    PersonalDataRemovalResult result = Failure(
        PersonalDataRemovalStatus::cleanup_pending, error, plan.journal_path);
    result.application_removed = true;
    result.removed = plan.active_profile.recycled && plan.local_data.recycled;
    result.retained_quarantine =
        (plan.active_profile.quarantined &&
         !plan.active_profile.recycled) ||
        (plan.local_data.quarantined && !plan.local_data.recycled);
    result.retry_available = true;
    return result;
  }
  if (!ValidateJournalControlDirectory(environment, plan, &error) ||
      !WriteResetMarker(plan, &error)) {
    PersonalDataRemovalResult result = Failure(
        PersonalDataRemovalStatus::cleanup_pending,
        error + L" Planner data is in the Recycle Bin; final reset cleanup can "
                L"be retried.",
        plan.journal_path);
    result.application_removed = true;
    result.removed = true;
    result.retry_available = true;
    return result;
  }
  plan.status = PersonalDataRemovalStatus::complete;
  if (!WriteJournal(plan, &error) || !ClearJournal(plan, &error)) {
    PersonalDataRemovalResult result = Failure(
        PersonalDataRemovalStatus::complete,
        error + L" Planner data is already in the Recycle Bin.",
        plan.journal_path);
    result.application_removed = true;
    result.removed = true;
    result.retry_available = true;
    return result;
  }
  return {.success = true,
          .application_removed = true,
          .removed = true,
          .status = PersonalDataRemovalStatus::complete,
          .message = L"Planner data was moved to the Recycle Bin. It can be "
                     L"restored from there if needed."};
}

} // namespace

bool PreparedPersonalDataRemovalMatchesInstallation(
    const PersonalDataRemovalPlan &plan, const std::wstring &install_root,
    const std::wstring &registered_install_root,
    const std::wstring &installed_version,
    std::uint32_t install_root_volume_serial,
    std::uint64_t install_root_file_id) {
  return plan.status == PersonalDataRemovalStatus::prepared &&
         SamePath(plan.install_root, install_root) &&
         SamePath(plan.registered_install_root, registered_install_root) &&
         plan.installed_version == installed_version &&
         plan.install_root_volume_serial == install_root_volume_serial &&
         plan.install_root_file_id == install_root_file_id;
}

PersonalDataRemovalResult
PreparePersonalDataRemoval(const std::wstring &install_root,
                           PersonalDataRemovalPlan *plan) {
  std::wstring error;
  const auto environment = ProductionEnvironment(&error);
  if (!environment)
    return Failure(PersonalDataRemovalStatus::invalid, error);
  return PrepareWithEnvironment(*environment, install_root, true, plan);
}

PersonalDataRemovalResult
DetectPendingPersonalDataRemoval(PersonalDataRemovalPlan *plan) {
  std::wstring error;
  const auto environment = ProductionEnvironment(&error);
  if (!environment)
    return Failure(PersonalDataRemovalStatus::invalid, error);
  return DetectWithEnvironment(*environment, plan);
}

PersonalDataRemovalResult MarkPersonalDataApplicationRemoved(
    const PersonalDataRemovalPlan &plan) {
  std::wstring error;
  const auto environment = ProductionEnvironment(&error);
  if (!environment)
    return Failure(PersonalDataRemovalStatus::invalid, error);
  return MarkWithEnvironment(*environment, plan, true);
}

PersonalDataRemovalResult
CancelPreparedPersonalDataRemoval(const PersonalDataRemovalPlan &plan) {
  std::wstring error;
  const auto environment = ProductionEnvironment(&error);
  if (!environment)
    return Failure(PersonalDataRemovalStatus::invalid, error);
  return CancelWithEnvironment(*environment, plan, true);
}

PersonalDataRemovalResult
FinalizePersonalDataRemoval(const PersonalDataRemovalPlan &plan) {
  std::wstring error;
  const auto environment = ProductionEnvironment(&error);
  if (!environment)
    return Failure(PersonalDataRemovalStatus::invalid, error);
  return FinalizeWithEnvironment(*environment, plan, true, RecycleWithWindows);
}

PersonalDataRemovalResult RetryPendingPersonalDataRemoval() {
  PersonalDataRemovalPlan plan;
  PersonalDataRemovalResult detected = DetectPendingPersonalDataRemoval(&plan);
  if (!detected.success || detected.status == PersonalDataRemovalStatus::none)
    return detected;
  return FinalizePersonalDataRemoval(plan);
}

PersonalDataRemovalResult PreparePersonalDataRemovalForTesting(
    const PersonalDataRemovalTestEnvironment &test_environment,
    const std::wstring &install_root, PersonalDataRemovalPlan *plan) {
  std::wstring error;
  const auto environment = NormalizeTestEnvironment(test_environment, &error);
  if (!environment)
    return Failure(PersonalDataRemovalStatus::invalid, error);
  return PrepareWithEnvironment(*environment, install_root, false, plan);
}

PersonalDataRemovalResult DetectPendingPersonalDataRemovalForTesting(
    const PersonalDataRemovalTestEnvironment &test_environment,
    PersonalDataRemovalPlan *plan) {
  std::wstring error;
  const auto environment = NormalizeTestEnvironment(test_environment, &error);
  if (!environment)
    return Failure(PersonalDataRemovalStatus::invalid, error);
  return DetectWithEnvironment(*environment, plan);
}

PersonalDataRemovalResult MarkPersonalDataApplicationRemovedForTesting(
    const PersonalDataRemovalPlan &plan) {
  const PersonalDataRemovalTestEnvironment test_environment{
      .roaming_app_data = std::filesystem::path(plan.reset_marker_path)
                              .parent_path()
                              .parent_path()
                              .wstring(),
      .local_app_data = std::filesystem::path(plan.local_data.path)
                            .parent_path()
                            .wstring(),
      .journal_directory =
          std::filesystem::path(plan.journal_path).parent_path().wstring(),
  };
  std::wstring error;
  const auto environment = NormalizeTestEnvironment(test_environment, &error);
  if (!environment)
    return Failure(PersonalDataRemovalStatus::invalid, error);
  return MarkWithEnvironment(*environment, plan, false);
}

PersonalDataRemovalResult CancelPreparedPersonalDataRemovalForTesting(
    const PersonalDataRemovalPlan &plan) {
  const PersonalDataRemovalTestEnvironment test_environment{
      .roaming_app_data = std::filesystem::path(plan.reset_marker_path)
                              .parent_path()
                              .parent_path()
                              .wstring(),
      .local_app_data = std::filesystem::path(plan.local_data.path)
                            .parent_path()
                            .wstring(),
      .journal_directory =
          std::filesystem::path(plan.journal_path).parent_path().wstring(),
  };
  std::wstring error;
  const auto environment = NormalizeTestEnvironment(test_environment, &error);
  if (!environment)
    return Failure(PersonalDataRemovalStatus::invalid, error);
  return CancelWithEnvironment(*environment, plan, false);
}

PersonalDataRemovalResult FinalizePersonalDataRemovalForTesting(
    const PersonalDataRemovalPlan &plan,
    const PersonalDataRecycleCallback &recycle) {
  if (!recycle) {
    return Failure(PersonalDataRemovalStatus::invalid,
                   L"The isolated Recycle Bin callback is missing.");
  }
  const PersonalDataRemovalTestEnvironment test_environment{
      .roaming_app_data = std::filesystem::path(plan.reset_marker_path)
                              .parent_path()
                              .parent_path()
                              .wstring(),
      .local_app_data = std::filesystem::path(plan.local_data.path)
                            .parent_path()
                            .wstring(),
      .journal_directory =
          std::filesystem::path(plan.journal_path).parent_path().wstring(),
  };
  std::wstring error;
  const auto environment = NormalizeTestEnvironment(test_environment, &error);
  if (!environment)
    return Failure(PersonalDataRemovalStatus::invalid, error);
  return FinalizeWithEnvironment(*environment, plan, false, recycle);
}

PersonalDataRemovalResult RetryPendingPersonalDataRemovalForTesting(
    const PersonalDataRemovalTestEnvironment &test_environment,
    const PersonalDataRecycleCallback &recycle) {
  PersonalDataRemovalPlan plan;
  PersonalDataRemovalResult detected =
      DetectPendingPersonalDataRemovalForTesting(test_environment, &plan);
  if (!detected.success || detected.status == PersonalDataRemovalStatus::none)
    return detected;
  return FinalizePersonalDataRemovalForTesting(plan, recycle);
}

} // namespace bsl::installer
