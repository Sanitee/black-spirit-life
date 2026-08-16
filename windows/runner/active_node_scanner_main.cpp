#include <windows.h>

#include <atomic>
#include <exception>
#include <filesystem>
#include <string>

#include "active_node_scan_protocol.h"
#include "active_node_video_scanner.h"

namespace {

active_node_video_scanner::ScanResult Failure(const std::wstring& source,
                                               const std::string& message) {
  active_node_video_scanner::ScanResult result;
  result.error_code = "scanner_helper_failed";
  result.error_message = message;
  if (!source.empty()) {
    const int size = WideCharToMultiByte(CP_UTF8, 0, source.data(),
                                        static_cast<int>(source.size()),
                                        nullptr, 0, nullptr, nullptr);
    if (size > 0) {
      result.source_path.resize(size);
      WideCharToMultiByte(CP_UTF8, 0, source.data(),
                          static_cast<int>(source.size()),
                          result.source_path.data(), size, nullptr, nullptr);
    }
  }
  return result;
}

}  // namespace

int wmain(int argc, wchar_t** argv) {
  const bool still_image = argc == 5 && std::wstring(argv[1]) == L"--image";
  if ((!still_image && argc != 4) || (still_image && argc != 5)) return 64;
  const int offset = still_image ? 1 : 0;
  const std::wstring source = argv[1 + offset];
  const std::filesystem::path result_path(argv[2 + offset]);
  const std::filesystem::path progress_path(argv[3 + offset]);
  std::atomic_bool delivered = false;
  const auto deliver = [&](const active_node_video_scanner::ScanResult& value) {
    if (delivered.load()) return;
    std::string ignored_error;
    if (active_node_scan_protocol::WriteResultAtomic(result_path, value,
                                                     &ignored_error)) {
      delivered.store(true);
    }
  };
  try {
    const auto progress =
        [&](const active_node_video_scanner::ScanProgress& value) {
          std::string ignored_error;
          active_node_scan_protocol::WriteProgressAtomic(
              progress_path, value, &ignored_error);
        };
    const auto result = still_image
                            ? active_node_video_scanner::ScanImage(
                                  source, progress, deliver)
                            : active_node_video_scanner::Scan(
                                  source, progress, 500, 32, deliver);
    deliver(result);
    return result.success ? 0 : 1;
  } catch (const std::exception& error) {
    deliver(Failure(source, error.what()));
  } catch (...) {
    deliver(Failure(source, "Windows could not read that recording."));
  }
  return 1;
}
