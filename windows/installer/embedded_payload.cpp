#include "embedded_payload.h"

#include <windows.h>

#include <bcrypt.h>
#include <objbase.h>

#include <algorithm>
#include <array>
#include <cctype>
#include <cstdint>
#include <filesystem>
#include <iomanip>
#include <sstream>
#include <string_view>
#include <utility>
#include <vector>

#include "installer_build_config.h"
#include "resource.h"

namespace bsl::installer {
namespace {

struct ResourceBytes {
  const unsigned char *data = nullptr;
  DWORD size = 0;
};

std::optional<ResourceBytes> ReadPayloadResource() {
  if (!build_config::kHasEmbeddedEngine)
    return std::nullopt;
  HMODULE module = GetModuleHandleW(nullptr);
  HRSRC resource =
      FindResourceW(module, MAKEINTRESOURCEW(IDR_VELOPACK_SETUP), RT_RCDATA);
  if (resource == nullptr)
    return std::nullopt;
  HGLOBAL loaded = LoadResource(module, resource);
  const DWORD size = SizeofResource(module, resource);
  const auto *data = static_cast<const unsigned char *>(
      loaded == nullptr ? nullptr : LockResource(loaded));
  if (data == nullptr || size == 0)
    return std::nullopt;
  return ResourceBytes{data, size};
}

char LowerAscii(char value) {
  return value >= 'A' && value <= 'Z' ? static_cast<char>(value - 'A' + 'a')
                                      : value;
}

std::string Sha256(const unsigned char *data, std::size_t size) {
  BCRYPT_ALG_HANDLE algorithm = nullptr;
  BCRYPT_HASH_HANDLE hash = nullptr;
  DWORD object_bytes = 0;
  DWORD hash_bytes = 0;
  DWORD received = 0;
  std::vector<unsigned char> object;
  std::vector<unsigned char> digest;
  std::string result;
  if (BCryptOpenAlgorithmProvider(&algorithm, BCRYPT_SHA256_ALGORITHM, nullptr,
                                  0) < 0 ||
      BCryptGetProperty(algorithm, BCRYPT_OBJECT_LENGTH,
                        reinterpret_cast<PUCHAR>(&object_bytes),
                        sizeof(object_bytes), &received, 0) < 0 ||
      BCryptGetProperty(algorithm, BCRYPT_HASH_LENGTH,
                        reinterpret_cast<PUCHAR>(&hash_bytes),
                        sizeof(hash_bytes), &received, 0) < 0) {
    if (algorithm)
      BCryptCloseAlgorithmProvider(algorithm, 0);
    return result;
  }
  object.resize(object_bytes);
  digest.resize(hash_bytes);
  if (BCryptCreateHash(algorithm, &hash, object.data(), object_bytes, nullptr,
                       0, 0) >= 0 &&
      BCryptHashData(hash, const_cast<PUCHAR>(data), static_cast<ULONG>(size),
                     0) >= 0 &&
      BCryptFinishHash(hash, digest.data(), hash_bytes, 0) >= 0) {
    std::ostringstream stream;
    stream << std::hex << std::setfill('0');
    for (unsigned char byte : digest) {
      stream << std::setw(2) << static_cast<unsigned>(byte);
    }
    result = stream.str();
  }
  if (hash)
    BCryptDestroyHash(hash);
  BCryptCloseAlgorithmProvider(algorithm, 0);
  return result;
}

std::wstring UniqueTemporaryDirectory() {
  const DWORD required = GetTempPathW(0, nullptr);
  if (required == 0)
    return {};
  std::wstring root(required, L'\0');
  const DWORD written = GetTempPathW(required, root.data());
  if (written == 0 || written >= required)
    return {};
  root.resize(written);
  GUID guid{};
  if (FAILED(CoCreateGuid(&guid)))
    return {};
  std::array<wchar_t, 64> text{};
  if (StringFromGUID2(guid, text.data(), static_cast<int>(text.size())) == 0) {
    return {};
  }
  std::wstring id(text.data());
  id.erase(std::remove_if(
               id.begin(), id.end(),
               [](wchar_t c) { return c == L'{' || c == L'}' || c == L'-'; }),
           id.end());
  return (std::filesystem::path(root) / (L"BlackSpiritLifeInstaller-" + id))
      .wstring();
}

bool WriteAll(HANDLE file, const unsigned char *data, DWORD size) {
  DWORD offset = 0;
  while (offset < size) {
    DWORD written = 0;
    if (!WriteFile(file, data + offset, size - offset, &written, nullptr) ||
        written == 0) {
      return false;
    }
    offset += written;
  }
  return FlushFileBuffers(file) != FALSE;
}

std::string Sha256FileHandle(HANDLE file, std::uint64_t expected_size) {
  if (file == nullptr || file == INVALID_HANDLE_VALUE)
    return {};
  LARGE_INTEGER size{};
  if (!GetFileSizeEx(file, &size) || size.QuadPart < 0 ||
      static_cast<std::uint64_t>(size.QuadPart) != expected_size ||
      expected_size > static_cast<std::uint64_t>(SIZE_MAX)) {
    return {};
  }
  LARGE_INTEGER start{};
  if (!SetFilePointerEx(file, start, nullptr, FILE_BEGIN))
    return {};
  std::vector<unsigned char> bytes(static_cast<std::size_t>(expected_size));
  std::size_t offset = 0;
  while (offset < bytes.size()) {
    const DWORD requested = static_cast<DWORD>(std::min<std::size_t>(
        bytes.size() - offset, static_cast<std::size_t>(4 * 1024 * 1024)));
    DWORD received = 0;
    if (!ReadFile(file, bytes.data() + offset, requested, &received, nullptr) ||
        received == 0) {
      return {};
    }
    offset += received;
  }
  return Sha256(bytes.data(), bytes.size());
}

} // namespace

ExtractedPayload::~ExtractedPayload() { ReleaseLocks(); }

ExtractedPayload::ExtractedPayload(ExtractedPayload &&other) noexcept
    : directory(std::move(other.directory)),
      executable(std::move(other.executable)),
      log_file(std::move(other.log_file)),
      directory_handle(other.directory_handle),
      executable_handle(other.executable_handle) {
  other.directory_handle = INVALID_HANDLE_VALUE;
  other.executable_handle = INVALID_HANDLE_VALUE;
}

ExtractedPayload &
ExtractedPayload::operator=(ExtractedPayload &&other) noexcept {
  if (this == &other)
    return *this;
  ReleaseLocks();
  directory = std::move(other.directory);
  executable = std::move(other.executable);
  log_file = std::move(other.log_file);
  directory_handle = other.directory_handle;
  executable_handle = other.executable_handle;
  other.directory_handle = INVALID_HANDLE_VALUE;
  other.executable_handle = INVALID_HANDLE_VALUE;
  return *this;
}

void ExtractedPayload::ReleaseLocks() {
  if (executable_handle != INVALID_HANDLE_VALUE) {
    CloseHandle(executable_handle);
    executable_handle = INVALID_HANDLE_VALUE;
  }
  if (directory_handle != INVALID_HANDLE_VALUE) {
    CloseHandle(directory_handle);
    directory_handle = INVALID_HANDLE_VALUE;
  }
}

bool HasEmbeddedPayload() { return build_config::kHasEmbeddedEngine; }

bool VerifyEmbeddedPayload(std::wstring *error) {
  const auto payload = ReadPayloadResource();
  if (!payload) {
    if (error)
      *error = L"This preview build does not contain an installation engine.";
    return false;
  }
  std::string actual = Sha256(payload->data, payload->size);
  std::string expected(build_config::kPayloadSha256);
  std::transform(actual.begin(), actual.end(), actual.begin(), LowerAscii);
  std::transform(expected.begin(), expected.end(), expected.begin(),
                 LowerAscii);
  if (actual.empty() || actual != expected) {
    if (error)
      *error = L"The embedded installation engine failed its integrity check.";
    return false;
  }
  return true;
}

std::optional<ExtractedPayload> ExtractEmbeddedPayload(std::wstring *error) {
  if (!VerifyEmbeddedPayload(error))
    return std::nullopt;
  const auto payload = ReadPayloadResource();
  if (!payload)
    return std::nullopt;
  ExtractedPayload extracted;
  extracted.directory = UniqueTemporaryDirectory();
  if (extracted.directory.empty() ||
      !CreateDirectoryW(extracted.directory.c_str(), nullptr)) {
    if (error)
      *error = L"A private temporary installer folder could not be created.";
    return std::nullopt;
  }
  const DWORD directory_attributes =
      GetFileAttributesW(extracted.directory.c_str());
  if (directory_attributes == INVALID_FILE_ATTRIBUTES ||
      (directory_attributes & FILE_ATTRIBUTE_REPARSE_POINT) != 0) {
    if (error)
      *error = L"The temporary installer folder is not a regular local folder.";
    RemoveDirectoryW(extracted.directory.c_str());
    return std::nullopt;
  }
  extracted.executable = (std::filesystem::path(extracted.directory) /
                          L"BlackSpiritLife.Velopack.Setup.exe")
                             .wstring();
  extracted.log_file =
      (std::filesystem::path(extracted.directory) / L"setup.log").wstring();
  HANDLE file = CreateFileW(
      extracted.executable.c_str(), GENERIC_WRITE, 0, nullptr, CREATE_NEW,
      FILE_ATTRIBUTE_TEMPORARY | FILE_ATTRIBUTE_NOT_CONTENT_INDEXED, nullptr);
  if (file == INVALID_HANDLE_VALUE ||
      !WriteAll(file, payload->data, payload->size)) {
    if (file != INVALID_HANDLE_VALUE)
      CloseHandle(file);
    if (error)
      *error = L"The verified installation engine could not be prepared.";
    CleanupExtractedPayload(extracted);
    return std::nullopt;
  }
  CloseHandle(file);
  extracted.directory_handle = CreateFileW(
      extracted.directory.c_str(), FILE_READ_ATTRIBUTES,
      FILE_SHARE_READ | FILE_SHARE_WRITE, nullptr, OPEN_EXISTING,
      FILE_FLAG_BACKUP_SEMANTICS | FILE_FLAG_OPEN_REPARSE_POINT, nullptr);
  extracted.executable_handle =
      CreateFileW(extracted.executable.c_str(), GENERIC_READ, FILE_SHARE_READ,
                  nullptr, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, nullptr);
  BY_HANDLE_FILE_INFORMATION executable_information{};
  if (extracted.directory_handle == INVALID_HANDLE_VALUE ||
      extracted.executable_handle == INVALID_HANDLE_VALUE ||
      !GetFileInformationByHandle(extracted.executable_handle,
                                  &executable_information) ||
      (executable_information.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY) !=
          0 ||
      (executable_information.dwFileAttributes &
       FILE_ATTRIBUTE_REPARSE_POINT) != 0) {
    if (error)
      *error = L"The prepared installation engine could not be locked safely.";
    CleanupExtractedPayload(extracted);
    return std::nullopt;
  }
  std::string actual =
      Sha256FileHandle(extracted.executable_handle, payload->size);
  std::string expected(build_config::kPayloadSha256);
  std::transform(actual.begin(), actual.end(), actual.begin(), LowerAscii);
  std::transform(expected.begin(), expected.end(), expected.begin(),
                 LowerAscii);
  if (actual != expected) {
    if (error)
      *error = L"The prepared installation engine failed its integrity check.";
    CleanupExtractedPayload(extracted);
    return std::nullopt;
  }
  return std::optional<ExtractedPayload>(std::move(extracted));
}

void CleanupExtractedPayload(ExtractedPayload &payload) {
  payload.ReleaseLocks();
  if (!payload.log_file.empty())
    DeleteFileW(payload.log_file.c_str());
  if (!payload.executable.empty())
    DeleteFileW(payload.executable.c_str());
  if (!payload.directory.empty())
    RemoveDirectoryW(payload.directory.c_str());
}

} // namespace bsl::installer
