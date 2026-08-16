#ifndef RUNNER_ACTIVE_NODE_VIDEO_SCANNER_H_
#define RUNNER_ACTIVE_NODE_VIDEO_SCANNER_H_

#include <windows.h>

#include <cstdint>
#include <functional>
#include <optional>
#include <string>
#include <vector>

namespace active_node_video_scanner {

struct OcrLine {
  std::string text;
  double left = 0;
  double top = 0;
  double width = 0;
  double height = 0;
};

struct OcrFrame {
  int index = 0;
  std::int64_t timestamp_milliseconds = 0;
  double sharpness = 0;
  std::vector<OcrLine> lines;
};

struct ScanResult {
  bool success = false;
  std::string error_code;
  std::string error_message;
  std::string source_path;
  std::string ocr_language;
  int source_width = 0;
  int source_height = 0;
  std::int64_t duration_milliseconds = 0;
  std::vector<OcrFrame> frames;
  std::vector<std::string> diagnostics;
};

struct ScanProgress {
  double fraction = 0;
  int completed_frames = 0;
  int estimated_frames = 0;
};

using ScanProgressCallback = std::function<void(const ScanProgress&)>;
using ScanResultReadyCallback = std::function<void(const ScanResult&)>;

/// Uses Windows Media Foundation and Windows.Media.Ocr only. The caller owns
/// threading; this function performs no Flutter calls and is safe to run on a
/// background MTA thread.
ScanResult Scan(const std::wstring& path,
                ScanProgressCallback progress_callback = {},
                std::int64_t preferred_interval_milliseconds = 500,
                int maximum_frames = 32,
                ScanResultReadyCallback result_ready_callback = {});

/// Decodes one PNG/JPEG/WebP screenshot with Windows Imaging Component and
/// runs the same Windows.Media.Ocr pipeline used by the video scanner.
ScanResult ScanImage(const std::wstring& path,
                     ScanProgressCallback progress_callback = {},
                     ScanResultReadyCallback result_ready_callback = {});

/// Opens Snipping Tool's rectangle-recording overlay with the documented
/// Win+Shift+R shortcut. The portable Win32 build has no MSIX identity, so it
/// cannot rely on the protocol redirect callback; the app subsequently finds
/// or asks the user to choose the saved MP4.
bool LaunchRectangleRecording(HWND owner);

/// Finds the newest Snipping Tool MP4 in the known auto-save and temporary
/// recording folders. [modified_after_unix_milliseconds] may be zero.
std::optional<std::wstring> FindLatestRecording(
    std::int64_t modified_after_unix_milliseconds = 0);

}  // namespace active_node_video_scanner

#endif  // RUNNER_ACTIVE_NODE_VIDEO_SCANNER_H_
