#include "active_node_scan_protocol.h"

#include <windows.h>

#include <algorithm>
#include <array>
#include <cstring>
#include <limits>
#include <type_traits>
#include <utility>
#include <vector>

namespace active_node_scan_protocol {
namespace {

constexpr std::array<char, 8> kResultMagic = {'B', 'D', 'O', 'N', 'O', 'D', '1', '\0'};
constexpr std::array<char, 8> kProgressMagic = {'B', 'D', 'O', 'P', 'R', 'G', '1', '\0'};
constexpr std::uint32_t kProtocolVersion = 1;
constexpr std::size_t kMaximumFileBytes = 64 * 1024 * 1024;
constexpr std::uint32_t kMaximumStringBytes = 8 * 1024 * 1024;
constexpr std::uint32_t kMaximumFrames = 1000;
constexpr std::uint32_t kMaximumLinesPerFrame = 10000;

void SetError(std::string* error, std::string value) {
  if (error != nullptr) *error = std::move(value);
}

template <typename T>
void Append(std::vector<std::uint8_t>* bytes, const T& value) {
  static_assert(std::is_trivially_copyable_v<T>);
  const auto* begin = reinterpret_cast<const std::uint8_t*>(&value);
  bytes->insert(bytes->end(), begin, begin + sizeof(T));
}

void AppendBytes(std::vector<std::uint8_t>* bytes,
                 const char* data,
                 std::size_t size) {
  const auto* begin = reinterpret_cast<const std::uint8_t*>(data);
  bytes->insert(bytes->end(), begin, begin + size);
}

void AppendString(std::vector<std::uint8_t>* bytes, const std::string& value) {
  const auto size = static_cast<std::uint32_t>(std::min<std::size_t>(
      value.size(), std::numeric_limits<std::uint32_t>::max()));
  Append(bytes, size);
  AppendBytes(bytes, value.data(), size);
}

class Reader {
 public:
  explicit Reader(const std::vector<std::uint8_t>& bytes) : bytes_(bytes) {}

  template <typename T>
  bool Read(T* output) {
    static_assert(std::is_trivially_copyable_v<T>);
    if (output == nullptr || offset_ > bytes_.size() ||
        sizeof(T) > bytes_.size() - offset_) {
      return false;
    }
    std::memcpy(output, bytes_.data() + offset_, sizeof(T));
    offset_ += sizeof(T);
    return true;
  }

  bool ReadMagic(const std::array<char, 8>& expected) {
    if (offset_ > bytes_.size() || expected.size() > bytes_.size() - offset_) {
      return false;
    }
    const bool matches =
        std::memcmp(bytes_.data() + offset_, expected.data(), expected.size()) ==
        0;
    offset_ += expected.size();
    return matches;
  }

  bool ReadString(std::string* output) {
    std::uint32_t size = 0;
    if (!Read(&size) || size > kMaximumStringBytes || offset_ > bytes_.size() ||
        size > bytes_.size() - offset_) {
      return false;
    }
    output->assign(reinterpret_cast<const char*>(bytes_.data() + offset_), size);
    offset_ += size;
    return true;
  }

  bool AtEnd() const { return offset_ == bytes_.size(); }

 private:
  const std::vector<std::uint8_t>& bytes_;
  std::size_t offset_ = 0;
};

bool WriteFileAtomic(const std::filesystem::path& path,
                     const std::vector<std::uint8_t>& bytes,
                     std::string* error) {
  const auto temporary = path.wstring() + L".tmp-" +
                         std::to_wstring(GetCurrentProcessId());
  HANDLE file = CreateFileW(temporary.c_str(), GENERIC_WRITE, 0, nullptr,
                            CREATE_ALWAYS, FILE_ATTRIBUTE_TEMPORARY, nullptr);
  if (file == INVALID_HANDLE_VALUE) {
    SetError(error, "Could not create the scanner result file.");
    return false;
  }
  bool success = true;
  std::size_t written_total = 0;
  while (written_total < bytes.size()) {
    const auto remaining = bytes.size() - written_total;
    const DWORD requested = static_cast<DWORD>(std::min<std::size_t>(
        remaining, std::numeric_limits<DWORD>::max()));
    DWORD written = 0;
    if (!WriteFile(file, bytes.data() + written_total, requested, &written,
                   nullptr) ||
        written == 0) {
      success = false;
      break;
    }
    written_total += written;
  }
  if (success) success = FlushFileBuffers(file) != FALSE;
  CloseHandle(file);
  if (success) {
    success = MoveFileExW(temporary.c_str(), path.c_str(),
                          MOVEFILE_REPLACE_EXISTING | MOVEFILE_WRITE_THROUGH) !=
              FALSE;
  }
  if (!success) {
    DeleteFileW(temporary.c_str());
    SetError(error, "Could not finish the scanner result file.");
  }
  return success;
}

std::optional<std::vector<std::uint8_t>> ReadFileBytes(
    const std::filesystem::path& path) {
  HANDLE file = CreateFileW(path.c_str(), GENERIC_READ,
                            FILE_SHARE_READ | FILE_SHARE_WRITE |
                                FILE_SHARE_DELETE,
                            nullptr, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL,
                            nullptr);
  if (file == INVALID_HANDLE_VALUE) return std::nullopt;
  LARGE_INTEGER size{};
  if (!GetFileSizeEx(file, &size) || size.QuadPart < 0 ||
      static_cast<std::uint64_t>(size.QuadPart) > kMaximumFileBytes) {
    CloseHandle(file);
    return std::nullopt;
  }
  std::vector<std::uint8_t> bytes(static_cast<std::size_t>(size.QuadPart));
  std::size_t read_total = 0;
  while (read_total < bytes.size()) {
    const auto remaining = bytes.size() - read_total;
    const DWORD requested = static_cast<DWORD>(std::min<std::size_t>(
        remaining, std::numeric_limits<DWORD>::max()));
    DWORD read = 0;
    if (!ReadFile(file, bytes.data() + read_total, requested, &read, nullptr) ||
        read == 0) {
      CloseHandle(file);
      return std::nullopt;
    }
    read_total += read;
  }
  CloseHandle(file);
  return bytes;
}

}  // namespace

bool WriteResultAtomic(
    const std::filesystem::path& path,
    const active_node_video_scanner::ScanResult& result,
    std::string* error) {
  std::vector<std::uint8_t> bytes;
  bytes.reserve(4096);
  AppendBytes(&bytes, kResultMagic.data(), kResultMagic.size());
  Append(&bytes, kProtocolVersion);
  const std::uint8_t success = result.success ? 1 : 0;
  Append(&bytes, success);
  AppendString(&bytes, result.error_code);
  AppendString(&bytes, result.error_message);
  AppendString(&bytes, result.source_path);
  AppendString(&bytes, result.ocr_language);
  Append(&bytes, result.source_width);
  Append(&bytes, result.source_height);
  Append(&bytes, result.duration_milliseconds);
  const auto diagnostic_count =
      static_cast<std::uint32_t>(result.diagnostics.size());
  Append(&bytes, diagnostic_count);
  for (const auto& diagnostic : result.diagnostics) {
    AppendString(&bytes, diagnostic);
  }
  const auto frame_count = static_cast<std::uint32_t>(result.frames.size());
  Append(&bytes, frame_count);
  for (const auto& frame : result.frames) {
    Append(&bytes, frame.index);
    Append(&bytes, frame.timestamp_milliseconds);
    Append(&bytes, frame.sharpness);
    const auto line_count = static_cast<std::uint32_t>(frame.lines.size());
    Append(&bytes, line_count);
    for (const auto& line : frame.lines) {
      AppendString(&bytes, line.text);
      Append(&bytes, line.left);
      Append(&bytes, line.top);
      Append(&bytes, line.width);
      Append(&bytes, line.height);
    }
  }
  return WriteFileAtomic(path, bytes, error);
}

std::optional<active_node_video_scanner::ScanResult> ReadResult(
    const std::filesystem::path& path,
    std::string* error) {
  const auto bytes = ReadFileBytes(path);
  if (!bytes.has_value()) return std::nullopt;
  Reader reader(*bytes);
  std::uint32_t version = 0;
  std::uint8_t success = 0;
  active_node_video_scanner::ScanResult result;
  if (!reader.ReadMagic(kResultMagic) || !reader.Read(&version) ||
      version != kProtocolVersion || !reader.Read(&success) ||
      !reader.ReadString(&result.error_code) ||
      !reader.ReadString(&result.error_message) ||
      !reader.ReadString(&result.source_path) ||
      !reader.ReadString(&result.ocr_language) ||
      !reader.Read(&result.source_width) ||
      !reader.Read(&result.source_height) ||
      !reader.Read(&result.duration_milliseconds)) {
    SetError(error, "The scanner returned an unreadable result.");
    return std::nullopt;
  }
  result.success = success != 0;
  std::uint32_t diagnostic_count = 0;
  if (!reader.Read(&diagnostic_count) || diagnostic_count > kMaximumLinesPerFrame) {
    SetError(error, "The scanner returned too many diagnostics.");
    return std::nullopt;
  }
  result.diagnostics.reserve(diagnostic_count);
  for (std::uint32_t index = 0; index < diagnostic_count; ++index) {
    std::string diagnostic;
    if (!reader.ReadString(&diagnostic)) {
      SetError(error, "The scanner diagnostics were incomplete.");
      return std::nullopt;
    }
    result.diagnostics.push_back(std::move(diagnostic));
  }
  std::uint32_t frame_count = 0;
  if (!reader.Read(&frame_count) || frame_count > kMaximumFrames) {
    SetError(error, "The scanner returned too many frames.");
    return std::nullopt;
  }
  result.frames.reserve(frame_count);
  for (std::uint32_t frame_index = 0; frame_index < frame_count; ++frame_index) {
    active_node_video_scanner::OcrFrame frame;
    std::uint32_t line_count = 0;
    if (!reader.Read(&frame.index) ||
        !reader.Read(&frame.timestamp_milliseconds) ||
        !reader.Read(&frame.sharpness) || !reader.Read(&line_count) ||
        line_count > kMaximumLinesPerFrame) {
      SetError(error, "The scanner frame data was incomplete.");
      return std::nullopt;
    }
    frame.lines.reserve(line_count);
    for (std::uint32_t line_index = 0; line_index < line_count; ++line_index) {
      active_node_video_scanner::OcrLine line;
      if (!reader.ReadString(&line.text) || !reader.Read(&line.left) ||
          !reader.Read(&line.top) || !reader.Read(&line.width) ||
          !reader.Read(&line.height)) {
        SetError(error, "The scanner line data was incomplete.");
        return std::nullopt;
      }
      frame.lines.push_back(std::move(line));
    }
    result.frames.push_back(std::move(frame));
  }
  if (!reader.AtEnd()) {
    SetError(error, "The scanner result contained unexpected data.");
    return std::nullopt;
  }
  return result;
}

bool WriteProgressAtomic(
    const std::filesystem::path& path,
    const active_node_video_scanner::ScanProgress& progress,
    std::string* error) {
  std::vector<std::uint8_t> bytes;
  bytes.reserve(32);
  AppendBytes(&bytes, kProgressMagic.data(), kProgressMagic.size());
  Append(&bytes, kProtocolVersion);
  Append(&bytes, progress.fraction);
  Append(&bytes, progress.completed_frames);
  Append(&bytes, progress.estimated_frames);
  return WriteFileAtomic(path, bytes, error);
}

std::optional<active_node_video_scanner::ScanProgress> ReadProgress(
    const std::filesystem::path& path) {
  const auto bytes = ReadFileBytes(path);
  if (!bytes.has_value()) return std::nullopt;
  Reader reader(*bytes);
  std::uint32_t version = 0;
  active_node_video_scanner::ScanProgress progress;
  if (!reader.ReadMagic(kProgressMagic) || !reader.Read(&version) ||
      version != kProtocolVersion || !reader.Read(&progress.fraction) ||
      !reader.Read(&progress.completed_frames) ||
      !reader.Read(&progress.estimated_frames) || !reader.AtEnd()) {
    return std::nullopt;
  }
  progress.fraction = std::clamp(progress.fraction, 0.0, 1.0);
  return progress;
}

}  // namespace active_node_scan_protocol
