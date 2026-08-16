#include "install_path_policy.h"

#include <windows.h>

#include <algorithm>
#include <climits>
#include <cstdint>
#include <cwchar>
#include <cwctype>
#include <filesystem>
#include <map>
#include <set>
#include <string_view>
#include <utility>
#include <vector>

#include "installer_build_config.h"

namespace bsl::installer {
namespace {

constexpr wchar_t kLocalProfileRootName[] = L"Black Spirit Life";
constexpr wchar_t kBootstrapDirectoryName[] = L"Bootstrap";
constexpr wchar_t kLocatorFileName[] = L"personal-data-location.json";
constexpr wchar_t kLocatorMirrorFileName[] =
    L"personal-data-location.committed.json";
constexpr wchar_t kMoveJournalFileName[] = L"personal-data-move-journal.json";
constexpr wchar_t kRemovalControlDirectoryName[] =
    L"BlackSpiritLife.App.Removal";
constexpr std::int64_t kMaximumLocatorBytes = 64 * 1024;

enum class JsonScalarKind { other, string, number };

struct JsonScalar {
  JsonScalarKind kind = JsonScalarKind::other;
  std::wstring text;
};

class JsonReader {
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
      if (!ReadValue(&value, 1))
        return false;
      if (!values->emplace(std::move(key), std::move(value)).second)
        return false;
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
    if (input_[position_] == L'-' ||
        (input_[position_] >= L'0' && input_[position_] <= L'9')) {
      value->kind = JsonScalarKind::number;
      return ReadNumber(&value->text);
    }
    value->kind = JsonScalarKind::other;
    return ConsumeLiteral(L"true") || ConsumeLiteral(L"false") ||
           ConsumeLiteral(L"null");
  }

  bool SkipObject(int depth) {
    if (depth > 32 || !Consume(L'{'))
      return false;
    SkipWhitespace();
    if (Consume(L'}'))
      return true;
    while (position_ < input_.size()) {
      std::wstring key;
      if (!ReadString(&key))
        return false;
      SkipWhitespace();
      if (!Consume(L':'))
        return false;
      JsonScalar ignored;
      if (!ReadValue(&ignored, depth))
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
        if (code_unit >= 0xD800 && code_unit <= 0xDBFF) {
          if (position_ + 2 > input_.size() || input_[position_] != L'\\' ||
              input_[position_ + 1] != L'u') {
            return false;
          }
          position_ += 2;
          std::uint16_t low = 0;
          if (!ReadHex4(&low) || low < 0xDC00 || low > 0xDFFF)
            return false;
          value->push_back(static_cast<wchar_t>(code_unit));
          value->push_back(static_cast<wchar_t>(low));
        } else {
          if (code_unit >= 0xDC00 && code_unit <= 0xDFFF)
            return false;
          value->push_back(static_cast<wchar_t>(code_unit));
        }
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
      const wchar_t digit = input_[position_++];
      result = static_cast<std::uint16_t>(result << 4);
      if (digit >= L'0' && digit <= L'9') {
        result = static_cast<std::uint16_t>(result + digit - L'0');
      } else if (digit >= L'a' && digit <= L'f') {
        result = static_cast<std::uint16_t>(result + digit - L'a' + 10);
      } else if (digit >= L'A' && digit <= L'F') {
        result = static_cast<std::uint16_t>(result + digit - L'A' + 10);
      } else {
        return false;
      }
    }
    *value = result;
    return true;
  }

  bool ReadNumber(std::wstring *value) {
    const std::size_t start = position_;
    if (position_ < input_.size() && input_[position_] == L'-')
      ++position_;
    if (position_ >= input_.size())
      return false;
    if (input_[position_] == L'0') {
      ++position_;
    } else {
      if (input_[position_] < L'1' || input_[position_] > L'9')
        return false;
      while (position_ < input_.size() && input_[position_] >= L'0' &&
             input_[position_] <= L'9') {
        ++position_;
      }
    }
    if (position_ < input_.size() && input_[position_] == L'.') {
      ++position_;
      const std::size_t fraction_start = position_;
      while (position_ < input_.size() && input_[position_] >= L'0' &&
             input_[position_] <= L'9') {
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
      while (position_ < input_.size() && input_[position_] >= L'0' &&
             input_[position_] <= L'9') {
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
    while (position_ < input_.size() && std::iswspace(input_[position_]) != 0) {
      ++position_;
    }
  }

  std::wstring_view input_;
  std::size_t position_ = 0;
};

enum class LocatorCopyState { missing, valid, invalid };

struct LocatorCopy {
  LocatorCopyState state = LocatorCopyState::invalid;
  std::wstring directory;
};

enum class CommittedLocationState { none, valid, invalid };

struct CommittedLocation {
  CommittedLocationState state = CommittedLocationState::invalid;
  std::wstring directory;
};

enum class MoveJournalState { none, valid, invalid };

struct PendingMoveJournal {
  MoveJournalState state = MoveJournalState::invalid;
  std::vector<std::wstring> protected_directories;
};

enum class IdentityFileState { missing, valid, invalid };

struct IdentityFileContents {
  IdentityFileState state = IdentityFileState::invalid;
  std::vector<char> bytes;
};

class ScopedHandle {
public:
  explicit ScopedHandle(HANDLE value) : value_(value) {}
  ~ScopedHandle() {
    if (value_ != INVALID_HANDLE_VALUE && value_ != nullptr)
      CloseHandle(value_);
  }
  ScopedHandle(const ScopedHandle &) = delete;
  ScopedHandle &operator=(const ScopedHandle &) = delete;

  [[nodiscard]] HANDLE get() const { return value_; }

private:
  HANDLE value_ = INVALID_HANDLE_VALUE;
};

std::wstring Trim(std::wstring value) {
  const auto first = value.find_first_not_of(L" \t\r\n\"");
  if (first == std::wstring::npos)
    return {};
  const auto last = value.find_last_not_of(L" \t\r\n\"");
  return value.substr(first, last - first + 1);
}

std::wstring Normalize(const std::wstring &input) {
  const std::wstring trimmed = Trim(input);
  if (trimmed.empty())
    return {};
  if (trimmed.rfind(L"\\\\", 0) == 0 || trimmed.rfind(L"\\\\?\\", 0) == 0 ||
      trimmed.rfind(L"\\\\.\\", 0) == 0) {
    return {};
  }
  const DWORD required = GetFullPathNameW(trimmed.c_str(), 0, nullptr, nullptr);
  if (required == 0)
    return {};
  std::wstring result(required, L'\0');
  const DWORD written =
      GetFullPathNameW(trimmed.c_str(), required, result.data(), nullptr);
  if (written == 0 || written >= required)
    return {};
  result.resize(written);
  while (result.size() > 3 &&
         (result.back() == L'\\' || result.back() == L'/')) {
    result.pop_back();
  }
  return result;
}

std::wstring CanonicalPhysicalPath(const std::wstring &input) {
  const std::wstring normalized = Normalize(input);
  if (normalized.empty())
    return {};
  std::filesystem::path current(normalized);
  std::vector<std::wstring> missing_components;
  while (!current.empty()) {
    const DWORD attributes = GetFileAttributesW(current.c_str());
    if (attributes != INVALID_FILE_ATTRIBUTES) {
      if ((attributes & FILE_ATTRIBUTE_DIRECTORY) == 0 ||
          (attributes & FILE_ATTRIBUTE_REPARSE_POINT) != 0) {
        return {};
      }
      ScopedHandle handle(CreateFileW(
          current.c_str(), FILE_READ_ATTRIBUTES,
          FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE, nullptr,
          OPEN_EXISTING,
          FILE_FLAG_BACKUP_SEMANTICS | FILE_FLAG_OPEN_REPARSE_POINT, nullptr));
      if (handle.get() == INVALID_HANDLE_VALUE)
        return {};
      BY_HANDLE_FILE_INFORMATION information{};
      if (!GetFileInformationByHandle(handle.get(), &information) ||
          (information.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY) == 0 ||
          (information.dwFileAttributes & FILE_ATTRIBUTE_REPARSE_POINT) != 0) {
        return {};
      }
      constexpr DWORD flags = FILE_NAME_NORMALIZED | VOLUME_NAME_NT;
      const DWORD required =
          GetFinalPathNameByHandleW(handle.get(), nullptr, 0, flags);
      if (required == 0)
        return {};
      std::wstring physical(required, L'\0');
      const DWORD written = GetFinalPathNameByHandleW(
          handle.get(), physical.data(), required, flags);
      if (written == 0 || written >= required)
        return {};
      physical.resize(written);
      while (!physical.empty() &&
             (physical.back() == L'\\' || physical.back() == L'/')) {
        physical.pop_back();
      }
      for (auto iterator = missing_components.rbegin();
           iterator != missing_components.rend(); ++iterator) {
        physical.push_back(L'\\');
        physical.append(*iterator);
      }
      return physical;
    }
    const DWORD error = GetLastError();
    if (error != ERROR_FILE_NOT_FOUND && error != ERROR_PATH_NOT_FOUND)
      return {};
    const std::filesystem::path parent = current.parent_path();
    if (parent.empty() || parent == current)
      return {};
    const std::wstring leaf = current.filename().wstring();
    if (leaf.empty())
      return {};
    missing_components.push_back(leaf);
    current = parent;
  }
  return {};
}

bool SameOrChildCanonical(const std::wstring &candidate,
                          const std::wstring &root) {
  if (candidate.empty() || root.empty())
    return false;
  if (_wcsicmp(candidate.c_str(), root.c_str()) == 0)
    return true;
  return candidate.size() > root.size() && candidate[root.size()] == L'\\' &&
         _wcsnicmp(candidate.c_str(), root.c_str(), root.size()) == 0;
}

bool SameOrChild(const std::wstring &candidate, const std::wstring &root) {
  const std::wstring a = Normalize(candidate);
  const std::wstring b = Normalize(root);
  if (a.empty() || b.empty())
    return false;
  if (_wcsicmp(a.c_str(), b.c_str()) == 0)
    return true;
  if (a.size() <= b.size() || a[b.size()] != L'\\')
    return false;
  return _wcsnicmp(a.c_str(), b.c_str(), b.size()) == 0;
}

std::wstring EnvironmentPath(const wchar_t *name) {
  const DWORD required = GetEnvironmentVariableW(name, nullptr, 0);
  if (required == 0)
    return {};
  std::wstring value(required, L'\0');
  if (GetEnvironmentVariableW(name, value.data(), required) == 0)
    return {};
  while (!value.empty() && value.back() == L'\0')
    value.pop_back();
  return Normalize(value);
}

enum class DirectoryContents { empty, not_empty, unreadable };

DirectoryContents InspectDirectoryContents(const std::wstring &path) {
  WIN32_FIND_DATAW data{};
  const std::wstring pattern = (std::filesystem::path(path) / L"*").wstring();
  HANDLE find = FindFirstFileW(pattern.c_str(), &data);
  if (find == INVALID_HANDLE_VALUE) {
    return GetLastError() == ERROR_FILE_NOT_FOUND
               ? DirectoryContents::empty
               : DirectoryContents::unreadable;
  }
  DirectoryContents contents = DirectoryContents::empty;
  do {
    if (std::wcscmp(data.cFileName, L".") != 0 &&
        std::wcscmp(data.cFileName, L"..") != 0) {
      contents = DirectoryContents::not_empty;
      break;
    }
  } while (FindNextFileW(find, &data));
  if (contents == DirectoryContents::empty &&
      GetLastError() != ERROR_NO_MORE_FILES) {
    contents = DirectoryContents::unreadable;
  }
  FindClose(find);
  return contents;
}

bool HasUnsafeSegment(const std::wstring &path) {
  static const std::set<std::wstring> reserved = {
      L"CON",  L"PRN",  L"AUX",  L"NUL",  L"COM1", L"COM2", L"COM3", L"COM4",
      L"COM5", L"COM6", L"COM7", L"COM8", L"COM9", L"LPT1", L"LPT2", L"LPT3",
      L"LPT4", L"LPT5", L"LPT6", L"LPT7", L"LPT8", L"LPT9"};
  for (const auto &component : std::filesystem::path(path)) {
    std::wstring segment = component.wstring();
    if (segment == L"\\" || segment.find(L':') != std::wstring::npos)
      continue;
    if (segment.empty() || segment.back() == L'.' || segment.back() == L' ') {
      return true;
    }
    const auto dot = segment.find(L'.');
    if (dot != std::wstring::npos)
      segment.resize(dot);
    std::transform(segment.begin(), segment.end(), segment.begin(), towupper);
    if (reserved.contains(segment))
      return true;
  }
  return false;
}

bool HasReparseAncestor(const std::wstring &path) {
  std::filesystem::path current(path);
  while (!current.empty()) {
    const DWORD attributes = GetFileAttributesW(current.c_str());
    if (attributes != INVALID_FILE_ATTRIBUTES &&
        (attributes & FILE_ATTRIBUTE_REPARSE_POINT) != 0) {
      return true;
    }
    const auto parent = current.parent_path();
    if (parent == current)
      break;
    current = parent;
  }
  return false;
}

bool ParseIdentityJson(const std::vector<char> &bytes,
                       std::map<std::wstring, JsonScalar> *values) {
  std::size_t offset = 0;
  if (bytes.size() >= 3 && static_cast<unsigned char>(bytes[0]) == 0xEF &&
      static_cast<unsigned char>(bytes[1]) == 0xBB &&
      static_cast<unsigned char>(bytes[2]) == 0xBF) {
    offset = 3;
  }
  if (offset >= bytes.size())
    return false;
  const std::size_t byte_count = bytes.size() - offset;
  if (byte_count > static_cast<std::size_t>(INT_MAX))
    return false;
  const int input_length = static_cast<int>(byte_count);
  const int wide_length =
      MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, bytes.data() + offset,
                          input_length, nullptr, 0);
  if (wide_length <= 0)
    return false;
  std::wstring json(static_cast<std::size_t>(wide_length), L'\0');
  if (MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, bytes.data() + offset,
                          input_length, json.data(),
                          wide_length) != wide_length) {
    return false;
  }

  JsonReader reader(json);
  if (!reader.ReadRootObject(values))
    return false;
  const auto schema = values->find(L"schemaVersion");
  const auto package_id = values->find(L"packageId");
  const auto channel = values->find(L"releaseChannel");
  return schema != values->end() && package_id != values->end() &&
         channel != values->end() &&
         schema->second.kind == JsonScalarKind::number &&
         schema->second.text == L"1" &&
         package_id->second.kind == JsonScalarKind::string &&
         package_id->second.text == std::wstring(build_config::kPackageId) &&
         channel->second.kind == JsonScalarKind::string &&
         channel->second.text == std::wstring(build_config::kChannel);
}

bool ParseAbsoluteIdentityPath(const std::map<std::wstring, JsonScalar> &values,
                               const wchar_t *key, std::wstring *directory) {
  const auto path = values.find(key);
  if (path == values.end() || path->second.kind != JsonScalarKind::string)
    return false;
  const std::wstring raw = Trim(path->second.text);
  if (raw.size() < 3 || !std::iswalpha(raw[0]) || raw[1] != L':' ||
      (raw[2] != L'\\' && raw[2] != L'/')) {
    return false;
  }
  *directory = Normalize(raw);
  return !directory->empty();
}

bool ParseLocatorJson(const std::vector<char> &bytes, std::wstring *directory) {
  std::map<std::wstring, JsonScalar> values;
  if (!ParseIdentityJson(bytes, &values))
    return false;
  return ParseAbsoluteIdentityPath(values, L"applicationDirectory", directory);
}

IdentityFileContents ReadIdentityFile(const std::wstring &path) {
  const DWORD attributes = GetFileAttributesW(path.c_str());
  if (attributes == INVALID_FILE_ATTRIBUTES) {
    const DWORD error = GetLastError();
    if (error == ERROR_FILE_NOT_FOUND || error == ERROR_PATH_NOT_FOUND)
      return {.state = IdentityFileState::missing};
    return {.state = IdentityFileState::invalid};
  }
  if ((attributes & FILE_ATTRIBUTE_DIRECTORY) != 0 ||
      (attributes & FILE_ATTRIBUTE_REPARSE_POINT) != 0) {
    return {.state = IdentityFileState::invalid};
  }

  ScopedHandle file(CreateFileW(
      path.c_str(), GENERIC_READ, FILE_SHARE_READ | FILE_SHARE_DELETE, nullptr,
      OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL | FILE_FLAG_OPEN_REPARSE_POINT,
      nullptr));
  if (file.get() == INVALID_HANDLE_VALUE)
    return {.state = IdentityFileState::invalid};
  BY_HANDLE_FILE_INFORMATION information{};
  if (!GetFileInformationByHandle(file.get(), &information) ||
      (information.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY) != 0 ||
      (information.dwFileAttributes & FILE_ATTRIBUTE_REPARSE_POINT) != 0) {
    return {.state = IdentityFileState::invalid};
  }
  LARGE_INTEGER size{};
  if (!GetFileSizeEx(file.get(), &size) || size.QuadPart <= 0 ||
      size.QuadPart > kMaximumLocatorBytes) {
    return {.state = IdentityFileState::invalid};
  }
  std::vector<char> bytes(static_cast<std::size_t>(size.QuadPart));
  DWORD total = 0;
  while (total < bytes.size()) {
    const DWORD remaining = static_cast<DWORD>(bytes.size() - total);
    DWORD read = 0;
    if (!ReadFile(file.get(), bytes.data() + total, remaining, &read,
                  nullptr) ||
        read == 0) {
      return {.state = IdentityFileState::invalid};
    }
    total += read;
  }
  return {.state = IdentityFileState::valid, .bytes = std::move(bytes)};
}

LocatorCopy ReadLocatorCopy(const std::wstring &path) {
  IdentityFileContents contents = ReadIdentityFile(path);
  if (contents.state == IdentityFileState::missing)
    return {.state = LocatorCopyState::missing};
  if (contents.state != IdentityFileState::valid)
    return {.state = LocatorCopyState::invalid};
  std::wstring directory;
  if (!ParseLocatorJson(contents.bytes, &directory))
    return {.state = LocatorCopyState::invalid};
  return {.state = LocatorCopyState::valid, .directory = std::move(directory)};
}

PendingMoveJournal
ReadPendingPersonalDataMove(const std::wstring &local_app_data) {
  if (local_app_data.empty())
    return {.state = MoveJournalState::invalid};
  const std::filesystem::path bootstrap =
      std::filesystem::path(local_app_data) / kLocalProfileRootName /
      kBootstrapDirectoryName;
  if (HasReparseAncestor(bootstrap.wstring()))
    return {.state = MoveJournalState::invalid};
  IdentityFileContents contents =
      ReadIdentityFile((bootstrap / kMoveJournalFileName).wstring());
  if (contents.state == IdentityFileState::missing)
    return {.state = MoveJournalState::none};
  if (contents.state != IdentityFileState::valid)
    return {.state = MoveJournalState::invalid};

  std::map<std::wstring, JsonScalar> values;
  if (!ParseIdentityJson(contents.bytes, &values))
    return {.state = MoveJournalState::invalid};
  const auto phase = values.find(L"phase");
  const auto profile_id = values.find(L"profileId");
  const auto transaction_id = values.find(L"transactionId");
  if (phase == values.end() || profile_id == values.end() ||
      transaction_id == values.end() ||
      phase->second.kind != JsonScalarKind::string ||
      profile_id->second.kind != JsonScalarKind::string ||
      profile_id->second.text.empty() ||
      transaction_id->second.kind != JsonScalarKind::string ||
      transaction_id->second.text.empty()) {
    return {.state = MoveJournalState::invalid};
  }
  const bool pre_promotion = phase->second.text == L"copying" ||
                             phase->second.text == L"copiedAndVerified";
  const bool post_promotion = phase->second.text == L"destinationPromoted" ||
                              phase->second.text == L"locatorSwitched";
  if (!pre_promotion && !post_promotion)
    return {.state = MoveJournalState::invalid};

  PendingMoveJournal journal{.state = MoveJournalState::valid};
  std::wstring source;
  std::wstring destination;
  if (!ParseAbsoluteIdentityPath(values, L"sourcePath", &source) ||
      !ParseAbsoluteIdentityPath(values, L"destinationPath", &destination)) {
    return {.state = MoveJournalState::invalid};
  }
  journal.protected_directories.push_back(std::move(source));
  journal.protected_directories.push_back(std::move(destination));

  const auto staging = values.find(L"stagingPath");
  if (staging == values.end())
    return {.state = MoveJournalState::invalid};
  if (pre_promotion) {
    std::wstring staging_directory;
    if (!ParseAbsoluteIdentityPath(values, L"stagingPath",
                                   &staging_directory)) {
      return {.state = MoveJournalState::invalid};
    }
    journal.protected_directories.push_back(std::move(staging_directory));
  } else if (staging->second.kind == JsonScalarKind::string) {
    return {.state = MoveJournalState::invalid};
  }
  return journal;
}

CommittedLocation
ReadCommittedPersonalDataLocation(const std::wstring &local_app_data) {
  if (local_app_data.empty())
    return {.state = CommittedLocationState::invalid};
  const std::filesystem::path bootstrap =
      std::filesystem::path(local_app_data) / kLocalProfileRootName /
      kBootstrapDirectoryName;
  if (HasReparseAncestor(bootstrap.wstring()))
    return {.state = CommittedLocationState::invalid};
  const LocatorCopy primary =
      ReadLocatorCopy((bootstrap / kLocatorFileName).wstring());
  const LocatorCopy mirror =
      ReadLocatorCopy((bootstrap / kLocatorMirrorFileName).wstring());
  if (primary.state == LocatorCopyState::missing &&
      mirror.state == LocatorCopyState::missing) {
    return {.state = CommittedLocationState::none};
  }
  if (primary.state != LocatorCopyState::valid ||
      mirror.state != LocatorCopyState::valid ||
      _wcsicmp(primary.directory.c_str(), mirror.directory.c_str()) != 0) {
    return {.state = CommittedLocationState::invalid};
  }
  return {.state = CommittedLocationState::valid,
          .directory = mirror.directory};
}

} // namespace

InstallPathValidation
ValidateInstallRootPersonalDataSafety(const std::wstring &install_root) {
  InstallPathValidation result;
  result.normalized_path = Normalize(install_root);
  if (result.normalized_path.empty()) {
    result.error = L"The application folder could not be verified.";
    return result;
  }
  const std::wstring physical_install_root =
      CanonicalPhysicalPath(result.normalized_path);
  if (physical_install_root.empty()) {
    result.error =
        L"Windows could not verify the physical application folder. No "
        L"application files were changed.";
    return result;
  }

  const std::wstring appdata = EnvironmentPath(L"APPDATA");
  const std::wstring local = EnvironmentPath(L"LOCALAPPDATA");
  const CommittedLocation committed_location =
      ReadCommittedPersonalDataLocation(local);
  const PendingMoveJournal pending_move = ReadPendingPersonalDataMove(local);
  if (committed_location.state == CommittedLocationState::invalid ||
      pending_move.state == MoveJournalState::invalid) {
    result.error =
        L"The saved personal-data location or pending move could not be "
        L"verified. Open Black Spirit Life once to finish or repair it, "
        L"then try again.";
    return result;
  }

  std::vector<std::wstring> protected_roots;
  if (!appdata.empty()) {
    protected_roots.push_back(
        (std::filesystem::path(appdata) / L"Black Spirit Life Beta").wstring());
    protected_roots.push_back(
        (std::filesystem::path(appdata) / L"Black Spirit Life").wstring());
    protected_roots.push_back(
        (std::filesystem::path(appdata) / L"BDO Craft Planner Map Candidate")
            .wstring());
  }
  if (!local.empty()) {
    protected_roots.push_back(
        (std::filesystem::path(local) / L"Black Spirit Life Beta").wstring());
    protected_roots.push_back(
        (std::filesystem::path(local) / L"Black Spirit Life").wstring());
    protected_roots.push_back(
        (std::filesystem::path(local) / L"BDO Craft Planner Map Candidate")
            .wstring());
    protected_roots.push_back(
        (std::filesystem::path(local) / kRemovalControlDirectoryName)
            .wstring());
  }
  if (committed_location.state == CommittedLocationState::valid)
    protected_roots.push_back(committed_location.directory);
  if (pending_move.state == MoveJournalState::valid) {
    protected_roots.insert(protected_roots.end(),
                           pending_move.protected_directories.begin(),
                           pending_move.protected_directories.end());
  }
  for (const auto &protected_root : protected_roots) {
    if (protected_root.empty())
      continue;
    const std::wstring physical_protected_root =
        CanonicalPhysicalPath(protected_root);
    if (physical_protected_root.empty()) {
      result.error =
          L"Windows could not verify a protected planner-data folder. No "
          L"application files were changed.";
      return result;
    }
    if (SameOrChild(result.normalized_path, protected_root) ||
        SameOrChild(protected_root, result.normalized_path) ||
        SameOrChildCanonical(physical_install_root, physical_protected_root) ||
        SameOrChildCanonical(physical_protected_root, physical_install_root)) {
      result.error =
          L"The application folder overlaps planner settings, cache, or a "
          L"pending personal-data move. Keep the application and personal "
          L"data in separate folders.";
      return result;
    }
  }
  result.valid = true;
  return result;
}

InstallPathValidation
ValidateFreshInstallPath(const std::wstring &requested_path) {
  InstallPathValidation result;
  result.normalized_path = Normalize(requested_path);
  if (result.normalized_path.empty() || result.normalized_path.size() > 240) {
    result.error =
        L"Choose a normal local folder with a shorter absolute path.";
    return result;
  }
  if (result.normalized_path.size() < 4 || result.normalized_path[1] != L':' ||
      result.normalized_path[2] != L'\\') {
    result.error =
        L"Choose a folder on a local drive, not a network or device path.";
    return result;
  }
  wchar_t volume[MAX_PATH]{};
  if (!GetVolumePathNameW(result.normalized_path.c_str(), volume, MAX_PATH) ||
      GetDriveTypeW(volume) != DRIVE_FIXED) {
    result.error = L"Choose a folder on a fixed local drive.";
    return result;
  }
  if (Normalize(volume) == result.normalized_path ||
      HasUnsafeSegment(result.normalized_path)) {
    result.error = L"Choose a named application folder, not a drive root or "
                   L"reserved Windows path.";
    return result;
  }
  if (HasReparseAncestor(result.normalized_path)) {
    result.error = L"This path redirects through a junction or link. Choose a "
                   L"regular local folder.";
    return result;
  }

  const InstallPathValidation personal_data_safety =
      ValidateInstallRootPersonalDataSafety(result.normalized_path);
  if (!personal_data_safety.valid)
    return personal_data_safety;

  const std::wstring user = EnvironmentPath(L"USERPROFILE");
  const std::wstring physical_destination =
      CanonicalPhysicalPath(result.normalized_path);
  if (physical_destination.empty()) {
    result.error = L"Windows could not verify the physical installation "
                   L"folder. Choose a different local folder.";
    return result;
  }
  std::vector<std::wstring> protected_roots = {
      EnvironmentPath(L"WINDIR"), EnvironmentPath(L"ProgramFiles"),
      EnvironmentPath(L"ProgramFiles(x86)"), EnvironmentPath(L"ProgramData")};
  for (const auto &protected_root : protected_roots) {
    if (protected_root.empty())
      continue;
    const std::wstring physical_protected =
        CanonicalPhysicalPath(protected_root);
    if (physical_protected.empty()) {
      result.error = L"Windows could not verify a protected system folder. "
                     L"Choose a different local folder.";
      return result;
    }
    if (SameOrChild(result.normalized_path, protected_root) ||
        SameOrChild(protected_root, result.normalized_path) ||
        SameOrChildCanonical(physical_destination, physical_protected) ||
        SameOrChildCanonical(physical_protected, physical_destination)) {
      result.error = L"Choose a folder outside Windows and outside every "
                     L"planner settings or cache folder.";
      return result;
    }
  }
  if (!user.empty()) {
    const std::wstring physical_user = CanonicalPhysicalPath(user);
    if (physical_user.empty()) {
      result.error = L"Windows could not verify the user profile folder. "
                     L"Choose a different local folder.";
      return result;
    }
    if (SameOrChild(user, result.normalized_path) ||
        SameOrChildCanonical(physical_user, physical_destination)) {
      result.error =
          L"Choose a named folder inside your account, not the whole "
          L"user profile.";
      return result;
    }
  }

  const DWORD attributes = GetFileAttributesW(result.normalized_path.c_str());
  if (attributes != INVALID_FILE_ATTRIBUTES) {
    const DirectoryContents contents =
        (attributes & FILE_ATTRIBUTE_DIRECTORY) != 0
            ? InspectDirectoryContents(result.normalized_path)
            : DirectoryContents::not_empty;
    if (contents != DirectoryContents::empty) {
      result.error =
          contents == DirectoryContents::unreadable
              ? L"Windows could not safely inspect this folder. Choose a "
                L"different empty folder."
              : L"This folder already contains files. Choose a new or empty "
                L"folder.";
      return result;
    }
  }
  result.valid = true;
  return result;
}

} // namespace bsl::installer
