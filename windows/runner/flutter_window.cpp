#include "flutter_window.h"

#include <flutter/standard_method_codec.h>
#include <flutter/method_result_functions.h>
#include <windowsx.h>
#include <commctrl.h>
#include <commdlg.h>
#include <shobjidl.h>
#include <algorithm>
#include <array>
#include <cstdint>
#include <cmath>
#include <exception>
#include <filesystem>
#include <optional>
#include <string>
#include <utility>
#include <vector>

#include "active_node_scan_protocol.h"
#include "active_node_video_scanner.h"
#include "clipboard_image_reader.h"
#include "flutter/generated_plugin_registrant.h"

namespace {

std::string WideToUtf8(const std::wstring& value) {
  if (value.empty()) return std::string();
  const int size = WideCharToMultiByte(CP_UTF8, 0, value.data(),
                                      static_cast<int>(value.size()), nullptr,
                                      0, nullptr, nullptr);
  std::string output(size, '\0');
  WideCharToMultiByte(CP_UTF8, 0, value.data(),
                      static_cast<int>(value.size()), output.data(), size,
                      nullptr, nullptr);
  return output;
}

std::filesystem::path ExecutableDirectory() {
  std::vector<wchar_t> buffer(MAX_PATH);
  while (true) {
    const DWORD size = GetModuleFileNameW(
        nullptr, buffer.data(), static_cast<DWORD>(buffer.size()));
    if (size == 0) return std::filesystem::path();
    if (size < buffer.size() - 1) {
      return std::filesystem::path(std::wstring(buffer.data(), size))
          .parent_path();
    }
    buffer.resize(buffer.size() * 2);
  }
}

std::wstring QuoteCommandLineArgument(const std::wstring& value) {
  if (value.empty()) return L"\"\"";
  if (value.find_first_of(L" \t\n\v\"") == std::wstring::npos) return value;
  std::wstring quoted = L"\"";
  std::size_t backslashes = 0;
  for (const wchar_t character : value) {
    if (character == L'\\') {
      ++backslashes;
      continue;
    }
    if (character == L'\"') {
      quoted.append(backslashes * 2 + 1, L'\\');
      quoted.push_back(character);
      backslashes = 0;
      continue;
    }
    quoted.append(backslashes, L'\\');
    backslashes = 0;
    quoted.push_back(character);
  }
  quoted.append(backslashes * 2, L'\\');
  quoted.push_back(L'\"');
  return quoted;
}

std::filesystem::path ActiveNodeTemporaryPath(const wchar_t* suffix) {
  std::vector<wchar_t> buffer(MAX_PATH);
  DWORD size = GetTempPathW(static_cast<DWORD>(buffer.size()), buffer.data());
  if (size == 0) return std::filesystem::path();
  if (size >= buffer.size()) {
    buffer.resize(size + 1);
    size = GetTempPathW(static_cast<DWORD>(buffer.size()), buffer.data());
    if (size == 0 || size >= buffer.size()) return std::filesystem::path();
  }
  const auto unique = L"bdo-active-node-" +
                      std::to_wstring(GetCurrentProcessId()) + L"-" +
                      std::to_wstring(GetTickCount64()) + suffix;
  return std::filesystem::path(std::wstring(buffer.data(), size)) / unique;
}

std::wstring Utf8ToWide(const std::string& value) {
  if (value.empty()) return std::wstring();
  const int size = MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS,
                                       value.data(),
                                       static_cast<int>(value.size()), nullptr,
                                       0);
  if (size <= 0) return std::wstring();
  std::wstring output(size, L'\0');
  MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, value.data(),
                      static_cast<int>(value.size()), output.data(), size);
  return output;
}

std::string StringArgument(const flutter::EncodableValue* arguments,
                           const char* key) {
  const auto* map = std::get_if<flutter::EncodableMap>(arguments);
  if (map == nullptr) return std::string();
  const auto entry = map->find(flutter::EncodableValue(key));
  if (entry == map->end()) return std::string();
  const auto* value = std::get_if<std::string>(&entry->second);
  return value == nullptr ? std::string() : *value;
}

std::int64_t Int64Argument(const flutter::EncodableValue* arguments,
                           const char* key) {
  const auto* map = std::get_if<flutter::EncodableMap>(arguments);
  if (map == nullptr) return 0;
  const auto entry = map->find(flutter::EncodableValue(key));
  if (entry == map->end()) return 0;
  if (const auto* value = std::get_if<std::int64_t>(&entry->second)) {
    return *value;
  }
  if (const auto* value = std::get_if<std::int32_t>(&entry->second)) {
    return *value;
  }
  return 0;
}

double DoubleArgument(const flutter::EncodableValue* arguments,
                      const char* key) {
  const auto* map = std::get_if<flutter::EncodableMap>(arguments);
  if (map == nullptr) return 0;
  const auto entry = map->find(flutter::EncodableValue(key));
  if (entry == map->end()) return 0;
  if (const auto* value = std::get_if<double>(&entry->second)) return *value;
  if (const auto* value = std::get_if<std::int64_t>(&entry->second)) {
    return static_cast<double>(*value);
  }
  if (const auto* value = std::get_if<std::int32_t>(&entry->second)) {
    return static_cast<double>(*value);
  }
  return 0;
}

flutter::EncodableValue EncodeActiveNodeScan(
    const active_node_video_scanner::ScanResult& scan) {
  flutter::EncodableList frames;
  frames.reserve(scan.frames.size());
  for (const auto& frame : scan.frames) {
    flutter::EncodableList lines;
    lines.reserve(frame.lines.size());
    for (const auto& line : frame.lines) {
      lines.emplace_back(flutter::EncodableMap{
          {flutter::EncodableValue("text"),
           flutter::EncodableValue(line.text)},
          {flutter::EncodableValue("left"),
           flutter::EncodableValue(line.left)},
          {flutter::EncodableValue("top"), flutter::EncodableValue(line.top)},
          {flutter::EncodableValue("width"),
           flutter::EncodableValue(line.width)},
          {flutter::EncodableValue("height"),
           flutter::EncodableValue(line.height)},
      });
    }
    frames.emplace_back(flutter::EncodableMap{
        {flutter::EncodableValue("index"),
         flutter::EncodableValue(frame.index)},
        {flutter::EncodableValue("timestampMilliseconds"),
         flutter::EncodableValue(frame.timestamp_milliseconds)},
        {flutter::EncodableValue("sharpness"),
         flutter::EncodableValue(frame.sharpness)},
        {flutter::EncodableValue("lines"),
         flutter::EncodableValue(std::move(lines))},
    });
  }
  flutter::EncodableList diagnostics;
  diagnostics.reserve(scan.diagnostics.size());
  for (const auto& diagnostic : scan.diagnostics) {
    diagnostics.emplace_back(diagnostic);
  }
  return flutter::EncodableValue(flutter::EncodableMap{
      {flutter::EncodableValue("sourcePath"),
       flutter::EncodableValue(scan.source_path)},
      {flutter::EncodableValue("ocrLanguage"),
       flutter::EncodableValue(scan.ocr_language)},
      {flutter::EncodableValue("sourceWidth"),
       flutter::EncodableValue(scan.source_width)},
      {flutter::EncodableValue("sourceHeight"),
       flutter::EncodableValue(scan.source_height)},
      {flutter::EncodableValue("durationMilliseconds"),
       flutter::EncodableValue(scan.duration_milliseconds)},
      {flutter::EncodableValue("frames"),
       flutter::EncodableValue(std::move(frames))},
      {flutter::EncodableValue("diagnostics"),
       flutter::EncodableValue(std::move(diagnostics))},
  });
}

const wchar_t* DialogFilter(const std::string& kind) {
  static const wchar_t image_filter[] =
      L"Image files (*.png;*.jpg;*.jpeg;*.webp;*.gif)\0"
      L"*.png;*.jpg;*.jpeg;*.webp;*.gif\0All files (*.*)\0*.*\0\0";
  static const wchar_t json_filter[] =
      L"JSON files (*.json)\0*.json\0All files (*.*)\0*.*\0\0";
  static const wchar_t video_filter[] =
      L"MP4 screen recordings (*.mp4)\0*.mp4\0All files (*.*)\0*.*\0\0";
  if (kind == "image") return image_filter;
  if (kind == "video") return video_filter;
  return json_filter;
}

constexpr int kResizeAspectWidth = 75;
constexpr int kResizeAspectHeight = 47;
constexpr int kMinimumWindowWidth = 1200;
constexpr int kMinimumWindowHeight = 752;
constexpr UINT_PTR kFlutterViewResizeSubclassId = 1;
constexpr UINT kApplyBottomInsetMessage = WM_APP + 0x51;

bool IsCornerResize(WPARAM edge) {
  return edge == WMSZ_TOPLEFT || edge == WMSZ_TOPRIGHT ||
         edge == WMSZ_BOTTOMLEFT || edge == WMSZ_BOTTOMRIGHT;
}

bool IsHorizontalEdgeResize(WPARAM edge) {
  return edge == WMSZ_LEFT || edge == WMSZ_RIGHT;
}

bool IsVerticalEdgeResize(WPARAM edge) {
  return edge == WMSZ_TOP || edge == WMSZ_BOTTOM;
}

void PreserveResizeAspect(HWND, WPARAM edge, RECT* proposed,
                          int bottom_inset) {
  if (proposed == nullptr) return;

  const bool corner = IsCornerResize(edge);
  const bool horizontal_edge = IsHorizontalEdgeResize(edge);
  const bool vertical_edge = IsVerticalEdgeResize(edge);
  if (!corner && !horizontal_edge && !vertical_edge) return;

  // Project the raw corner proposal onto the fixed 75:47 aspect line. The
  // previous implementation selected a width- or height-driven branch by
  // comparing against the previously corrected rectangle on every WM_SIZING
  // message. Because that rectangle was already changed by the preceding
  // message, the selected branch alternated while dragging and made the whole
  // app twitch.
  // This projection is continuous, stateless, and keeps the opposite corner
  // fixed while both moving edges follow the pointer smoothly.
  const double raw_width =
      static_cast<double>(proposed->right - proposed->left);
  const double raw_height = static_cast<double>(std::max<LONG>(
      0, proposed->bottom - proposed->top - bottom_inset));
  const double aspect_width = static_cast<double>(kResizeAspectWidth);
  const double aspect_height = static_cast<double>(kResizeAspectHeight);
  const double minimum_scale = std::max(
      static_cast<double>(kMinimumWindowWidth) / aspect_width,
      static_cast<double>(kMinimumWindowHeight) / aspect_height);
  double proposed_scale = 0.0;
  if (corner) {
    const double denominator = aspect_width * aspect_width +
                               aspect_height * aspect_height;
    proposed_scale =
        (raw_width * aspect_width + raw_height * aspect_height) / denominator;
  } else if (horizontal_edge) {
    proposed_scale = raw_width / aspect_width;
  } else {
    proposed_scale = raw_height / aspect_height;
  }
  const double scale = std::max(minimum_scale, proposed_scale);
  const int width = static_cast<int>(std::lround(aspect_width * scale));
  const int height =
      static_cast<int>(std::lround(aspect_height * scale)) + bottom_inset;

  if (horizontal_edge) {
    const int vertical_center = proposed->top +
                                (proposed->bottom - proposed->top) / 2;
    proposed->top = vertical_center - height / 2;
    proposed->bottom = proposed->top + height;
    if (edge == WMSZ_LEFT) {
      proposed->left = proposed->right - width;
    } else {
      proposed->right = proposed->left + width;
    }
    return;
  }

  if (vertical_edge) {
    const int horizontal_center = proposed->left +
                                  (proposed->right - proposed->left) / 2;
    proposed->left = horizontal_center - width / 2;
    proposed->right = proposed->left + width;
    if (edge == WMSZ_TOP) {
      proposed->top = proposed->bottom - height;
    } else {
      proposed->bottom = proposed->top + height;
    }
    return;
  }

  const bool resize_left = edge == WMSZ_TOPLEFT || edge == WMSZ_BOTTOMLEFT;
  const bool resize_top = edge == WMSZ_TOPLEFT || edge == WMSZ_TOPRIGHT;
  if (resize_left) {
    proposed->left = proposed->right - width;
  } else {
    proposed->right = proposed->left + width;
  }
  if (resize_top) {
    proposed->top = proposed->bottom - height;
  } else {
    proposed->bottom = proposed->top + height;
  }
}

bool EqualRectValues(const RECT& left, const RECT& right) {
  return left.left == right.left && left.top == right.top &&
         left.right == right.right && left.bottom == right.bottom;
}

RECT WorkAreaForWindowPlacement(const MONITORINFO& monitor_info) {
  RECT work_area = monitor_info.rcWork;
  // WINDOWPLACEMENT.rcNormalPosition uses workspace coordinates for this
  // top-level window. Normalize the monitor's screen-coordinate work area into
  // the same coordinate space while retaining its virtual-monitor origin.
  OffsetRect(&work_area,
             monitor_info.rcMonitor.left - monitor_info.rcWork.left,
             monitor_info.rcMonitor.top - monitor_info.rcWork.top);
  return work_area;
}

void FitWorkspaceRectToInset(RECT* bounds, int old_inset, int new_inset,
                             const RECT& work_area) {
  if (bounds == nullptr) return;
  const double current_width =
      static_cast<double>(std::max<LONG>(1, bounds->right - bounds->left));
  const double current_base_height = static_cast<double>(std::max<LONG>(
      1, bounds->bottom - bounds->top - old_inset));
  const double work_width = static_cast<double>(
      std::max<LONG>(1, work_area.right - work_area.left));
  const double work_base_height = static_cast<double>(std::max<LONG>(
      1, work_area.bottom - work_area.top - new_inset));
  const double desired_scale =
      std::min(current_width / kResizeAspectWidth,
               current_base_height / kResizeAspectHeight);
  const double fitting_scale =
      std::min(work_width / kResizeAspectWidth,
               work_base_height / kResizeAspectHeight);
  const double scale = std::max(1.0, std::min(desired_scale, fitting_scale));
  const int width =
      static_cast<int>(std::lround(kResizeAspectWidth * scale));
  const int total_height =
      static_cast<int>(std::lround(kResizeAspectHeight * scale)) + new_inset;

  // Keep the top-left stable when there is room, so the status area visibly
  // grows below the planner. Shift only as much as the monitor requires.
  bounds->right = bounds->left + width;
  bounds->bottom = bounds->top + total_height;
  if (bounds->right > work_area.right) {
    const int overflow = bounds->right - work_area.right;
    bounds->left -= overflow;
    bounds->right -= overflow;
  }
  if (bounds->left < work_area.left) {
    bounds->left = work_area.left;
    bounds->right = bounds->left + width;
  }
  if (bounds->bottom > work_area.bottom) {
    const int overflow = bounds->bottom - work_area.bottom;
    bounds->top -= overflow;
    bounds->bottom -= overflow;
  }
  if (bounds->top < work_area.top) {
    bounds->top = work_area.top;
    bounds->bottom = bounds->top + total_height;
  }
}

LRESULT HitTestResizeFrame(HWND window, LPARAM position) {
  if (IsZoomed(window)) return HTCLIENT;

  const UINT dpi = GetDpiForWindow(window);
  const int edge_frame = MulDiv(10, dpi, 96);
  const int corner_frame = MulDiv(18, dpi, 96);
  RECT bounds{};
  GetWindowRect(window, &bounds);
  const int x = GET_X_LPARAM(position);
  const int y = GET_Y_LPARAM(position);

  const bool corner_left = x < bounds.left + corner_frame;
  const bool corner_right = x >= bounds.right - corner_frame;
  const bool corner_top = y < bounds.top + corner_frame;
  const bool corner_bottom = y >= bounds.bottom - corner_frame;
  if (corner_top && corner_left) return HTTOPLEFT;
  if (corner_top && corner_right) return HTTOPRIGHT;
  if (corner_bottom && corner_left) return HTBOTTOMLEFT;
  if (corner_bottom && corner_right) return HTBOTTOMRIGHT;

  const bool left = x < bounds.left + edge_frame;
  const bool right = x >= bounds.right - edge_frame;
  const bool top = y < bounds.top + edge_frame;
  const bool bottom = y >= bounds.bottom - edge_frame;
  if (left) return HTLEFT;
  if (right) return HTRIGHT;
  if (top) return HTTOP;
  if (bottom) return HTBOTTOM;
  return HTCLIENT;
}

LRESULT CALLBACK FlutterViewResizeSubclassProc(
    HWND child,
    UINT message,
    WPARAM wparam,
    LPARAM lparam,
    UINT_PTR subclass_id,
    DWORD_PTR reference_data) {
  const HWND parent = reinterpret_cast<HWND>(reference_data);
  if (message == WM_NCHITTEST && parent != nullptr && IsWindow(parent)) {
    const LRESULT hit = HitTestResizeFrame(parent, lparam);
    if (hit != HTCLIENT) {
      // The Flutter view fills the entire borderless parent. Returning
      // HTTRANSPARENT here lets Windows retry the hit test against that parent
      // so its native corner and edge resize cursors remain reachable.
      return HTTRANSPARENT;
    }
  } else if (message == WM_NCDESTROY) {
    RemoveWindowSubclass(child, FlutterViewResizeSubclassProc, subclass_id);
  }
  return DefSubclassProc(child, message, wparam, lparam);
}

std::optional<std::string> PickOpenFile(HWND owner,
                                        const std::string& kind) {
  std::array<wchar_t, 32768> path{};
  OPENFILENAMEW dialog{};
  dialog.lStructSize = sizeof(dialog);
  dialog.hwndOwner = owner;
  dialog.lpstrFile = path.data();
  dialog.nMaxFile = static_cast<DWORD>(path.size());
  dialog.lpstrFilter = DialogFilter(kind);
  dialog.nFilterIndex = 1;
  dialog.Flags = OFN_FILEMUSTEXIST | OFN_PATHMUSTEXIST |
                 OFN_NOCHANGEDIR | OFN_DONTADDTORECENT;
  if (GetOpenFileNameW(&dialog) == FALSE) return std::nullopt;
  return WideToUtf8(path.data());
}

std::optional<std::string> PickSaveFile(HWND owner,
                                        const std::string& default_name) {
  std::array<wchar_t, 32768> path{};
  const std::wstring initial = Utf8ToWide(default_name);
  if (!initial.empty() && initial.size() < path.size()) {
    std::copy(initial.begin(), initial.end(), path.begin());
  }
  OPENFILENAMEW dialog{};
  dialog.lStructSize = sizeof(dialog);
  dialog.hwndOwner = owner;
  dialog.lpstrFile = path.data();
  dialog.nMaxFile = static_cast<DWORD>(path.size());
  dialog.lpstrFilter = DialogFilter("json");
  dialog.nFilterIndex = 1;
  dialog.lpstrDefExt = L"json";
  dialog.Flags = OFN_PATHMUSTEXIST | OFN_OVERWRITEPROMPT |
                 OFN_NOCHANGEDIR | OFN_DONTADDTORECENT;
  if (GetSaveFileNameW(&dialog) == FALSE) return std::nullopt;
  return WideToUtf8(path.data());
}

struct DirectoryPickResult {
  std::optional<std::string> selection;
  std::optional<std::string> error;
};

DirectoryPickResult PickDirectory(HWND owner,
                                  const std::string& initial_path) {
  IFileOpenDialog* dialog = nullptr;
  if (FAILED(CoCreateInstance(CLSID_FileOpenDialog, nullptr,
                              CLSCTX_INPROC_SERVER, IID_PPV_ARGS(&dialog))) ||
      dialog == nullptr) {
    return {std::nullopt, "The Windows folder picker could not be opened."};
  }

  FILEOPENDIALOGOPTIONS options = 0;
  const HRESULT get_options_result = dialog->GetOptions(&options);
  if (FAILED(get_options_result)) {
    dialog->Release();
    return {std::nullopt,
            "Windows could not configure a folder-only picker."};
  }
  const HRESULT set_options_result = dialog->SetOptions(
      options | FOS_PICKFOLDERS | FOS_FORCEFILESYSTEM | FOS_PATHMUSTEXIST |
      FOS_DONTADDTORECENT);
  if (FAILED(set_options_result)) {
    dialog->Release();
    return {std::nullopt,
            "Windows could not configure a folder-only picker."};
  }
  const std::wstring initial = Utf8ToWide(initial_path);
  if (!initial.empty()) {
    IShellItem* initial_item = nullptr;
    if (SUCCEEDED(SHCreateItemFromParsingName(
            initial.c_str(), nullptr, IID_PPV_ARGS(&initial_item))) &&
        initial_item != nullptr) {
      dialog->SetFolder(initial_item);
      initial_item->Release();
    }
  }

  const HRESULT show_result = dialog->Show(owner);
  if (show_result == HRESULT_FROM_WIN32(ERROR_CANCELLED)) {
    dialog->Release();
    return {std::nullopt, std::nullopt};
  }
  if (FAILED(show_result)) {
    dialog->Release();
    return {std::nullopt, "The Windows folder picker failed."};
  }
  IShellItem* selected_item = nullptr;
  if (FAILED(dialog->GetResult(&selected_item)) || selected_item == nullptr) {
    dialog->Release();
    return {std::nullopt, "Windows did not return the selected folder."};
  }
  PWSTR selected_path = nullptr;
  if (FAILED(selected_item->GetDisplayName(SIGDN_FILESYSPATH,
                                            &selected_path)) ||
      selected_path == nullptr) {
    selected_item->Release();
    dialog->Release();
    return {std::nullopt, "Windows did not return a local folder path."};
  }
  const std::string selection = WideToUtf8(selected_path);
  CoTaskMemFree(selected_path);
  selected_item->Release();
  dialog->Release();
  return {selection, std::nullopt};
}

}  // namespace

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::QueueBottomInset(double logical_pixels) {
  if (!std::isfinite(logical_pixels)) logical_pixels = 0;
  pending_bottom_inset_logical_ = std::clamp(logical_pixels, 0.0, 96.0);
  if (bottom_inset_message_pending_) return true;

  const HWND window = GetHandle();
  if (window == nullptr) return false;
  bottom_inset_message_pending_ = true;
  if (PostMessage(window, kApplyBottomInsetMessage, 0, 0) == 0) {
    bottom_inset_message_pending_ = false;
    return false;
  }
  return true;
}

void FlutterWindow::SetBottomInset(double logical_pixels) {
  const HWND window = GetHandle();
  if (window == nullptr) return;
  if (!std::isfinite(logical_pixels)) logical_pixels = 0;
  logical_pixels = std::clamp(logical_pixels, 0.0, 96.0);
  const UINT dpi = std::max<UINT>(96, GetDpiForWindow(window));
  const int next_physical = static_cast<int>(
      std::lround(logical_pixels * static_cast<double>(dpi) / 96.0));
  if (next_physical == bottom_inset_physical_ &&
      logical_pixels == bottom_inset_logical_) {
    return;
  }

  const int old_physical = bottom_inset_physical_;
  if (next_physical == old_physical) {
    bottom_inset_logical_ = logical_pixels;
    return;
  }

  MONITORINFO monitor_info{};
  monitor_info.cbSize = sizeof(monitor_info);
  const HMONITOR monitor =
      MonitorFromWindow(window, MONITOR_DEFAULTTONEAREST);
  if (monitor == nullptr || GetMonitorInfoW(monitor, &monitor_info) == FALSE) {
    return;
  }

  const bool use_placement = IsZoomed(window) || IsIconic(window);
  WINDOWPLACEMENT placement{};
  placement.length = sizeof(placement);
  RECT current{};
  if (use_placement) {
    if (GetWindowPlacement(window, &placement) == FALSE) return;
    current = placement.rcNormalPosition;
  } else if (GetWindowRect(window, &current) == FALSE) {
    return;
  }

  if (old_physical == 0 && next_physical > 0) {
    has_bottom_inset_restore_bounds_ = true;
    bottom_inset_restore_uses_placement_ = use_placement;
    bottom_inset_restore_bounds_ = current;
  }

  RECT target = current;
  const bool restore_unchanged =
      next_physical == 0 && has_bottom_inset_restore_bounds_ &&
      bottom_inset_restore_uses_placement_ == use_placement &&
      EqualRectValues(current, bottom_inset_applied_bounds_);
  if (restore_unchanged) {
    target = bottom_inset_restore_bounds_;
  } else {
    const RECT placement_work_area = WorkAreaForWindowPlacement(monitor_info);
    FitWorkspaceRectToInset(&target, old_physical, next_physical,
                            use_placement ? placement_work_area
                                          : monitor_info.rcWork);
  }

  bool applied = false;
  if (use_placement) {
    placement.rcNormalPosition = target;
    applied = SetWindowPlacement(window, &placement) != FALSE;
  } else {
    applied = SetWindowPos(window, nullptr, target.left, target.top,
                           target.right - target.left,
                           target.bottom - target.top,
                           SWP_NOACTIVATE | SWP_NOZORDER) != FALSE;
  }
  if (!applied) return;

  bottom_inset_logical_ = logical_pixels;
  bottom_inset_physical_ = next_physical;
  if (next_physical > 0) {
    RECT actual = target;
    if (use_placement) {
      WINDOWPLACEMENT actual_placement{};
      actual_placement.length = sizeof(actual_placement);
      if (GetWindowPlacement(window, &actual_placement) != FALSE) {
        actual = actual_placement.rcNormalPosition;
      }
    } else {
      GetWindowRect(window, &actual);
    }
    bottom_inset_applied_bounds_ = actual;
  } else {
    has_bottom_inset_restore_bounds_ = false;
  }
}

void FlutterWindow::StopActiveNodeScanner(bool terminate) {
  if (active_node_scan_process_ != nullptr) {
    if (terminate) {
      DWORD exit_code = 0;
      if (GetExitCodeProcess(active_node_scan_process_, &exit_code) != FALSE &&
          exit_code == STILL_ACTIVE) {
        TerminateProcess(active_node_scan_process_, 2);
        // The helper is isolated precisely because Windows decoder teardown can
        // hang. Never make the planner wait more than a fraction of a second.
        WaitForSingleObject(active_node_scan_process_, 250);
      }
    }
    CloseHandle(active_node_scan_process_);
    active_node_scan_process_ = nullptr;
  }
  if (!active_node_scan_result_path_.empty()) {
    DeleteFileW(active_node_scan_result_path_.c_str());
    const auto temporary = active_node_scan_result_path_ + L".tmp-" +
                           std::to_wstring(active_node_scan_process_id_);
    DeleteFileW(temporary.c_str());
  }
  if (!active_node_scan_progress_path_.empty()) {
    DeleteFileW(active_node_scan_progress_path_.c_str());
    const auto temporary = active_node_scan_progress_path_ + L".tmp-" +
                           std::to_wstring(active_node_scan_process_id_);
    DeleteFileW(temporary.c_str());
  }
  active_node_scan_process_id_ = 0;
  active_node_scan_result_path_.clear();
  active_node_scan_progress_path_.clear();
  active_node_scan_last_progress_ = -1;
  active_node_scan_last_completed_frames_ = -1;
  active_node_scan_last_estimated_frames_ = -1;
}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  RECT frame = GetClientArea();

  // The size here must match the window dimensions to avoid unnecessary surface
  // creation / destruction in the startup path.
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  // Ensure that basic setup of the controller was successful.
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());
  window_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          flutter_controller_->engine()->messenger(),
          "com.bdocraftplanner.flutter/window",
          &flutter::StandardMethodCodec::GetInstance());
  active_node_progress_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          flutter_controller_->engine()->messenger(),
          "com.bdocraftplanner.flutter/active_node_video_progress",
          &flutter::StandardMethodCodec::GetInstance());
  window_channel_->SetMethodCallHandler(
      [this](const flutter::MethodCall<flutter::EncodableValue>& call,
             std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
                 result) {
        const HWND window = GetHandle();
        if (window == nullptr) {
          result->Error("window_unavailable", "The native window is closed.");
          return;
        }
        if (call.method_name() == "beginDrag") {
          ReleaseCapture();
          SendMessage(window, WM_NCLBUTTONDOWN, HTCAPTION, 0);
          result->Success();
        } else if (call.method_name() == "minimize") {
          ShowWindow(window, SW_MINIMIZE);
          result->Success();
        } else if (call.method_name() == "toggleMaximize") {
          ShowWindow(window, IsZoomed(window) ? SW_RESTORE : SW_MAXIMIZE);
          result->Success(flutter::EncodableValue(IsZoomed(window) != FALSE));
        } else if (call.method_name() == "close") {
          native_close_allowed_ = true;
          if (PostMessage(window, WM_CLOSE, 0, 0) == 0) {
            native_close_allowed_ = false;
            result->Error("window_close_failed",
                          "Windows could not queue the close request.");
          } else {
            result->Success();
          }
        } else if (call.method_name() == "isMaximized") {
          result->Success(flutter::EncodableValue(IsZoomed(window) != FALSE));
        } else if (call.method_name() == "setBottomInset") {
          if (QueueBottomInset(
                  DoubleArgument(call.arguments(), "logicalPixels"))) {
            result->Success();
          } else {
            result->Error("window_resize_failed",
                          "Windows could not queue the update-bar resize.");
          }
        } else if (call.method_name() == "pickOpenFile") {
          const auto selection =
              PickOpenFile(window, StringArgument(call.arguments(), "kind"));
          if (selection.has_value()) {
            result->Success(flutter::EncodableValue(selection.value()));
          } else {
            result->Success(flutter::EncodableValue());
          }
        } else if (call.method_name() == "pickSaveFile") {
          const auto selection = PickSaveFile(
              window, StringArgument(call.arguments(), "defaultName"));
          if (selection.has_value()) {
            result->Success(flutter::EncodableValue(selection.value()));
          } else {
            result->Success(flutter::EncodableValue());
          }
        } else if (call.method_name() == "pickDirectory") {
          const auto directory_pick = PickDirectory(
              window, StringArgument(call.arguments(), "initialPath"));
          if (directory_pick.error.has_value()) {
            result->Error("folder_picker_unavailable",
                          directory_pick.error.value());
          } else if (directory_pick.selection.has_value()) {
            result->Success(
                flutter::EncodableValue(directory_pick.selection.value()));
          } else {
            result->Success(flutter::EncodableValue());
          }
        } else if (call.method_name() == "readClipboardImagePng") {
          const auto image = clipboard_image_reader::ReadPng(window);
          if (image.has_value()) {
            result->Success(flutter::EncodableValue(image.value()));
          } else {
            result->Success(flutter::EncodableValue());
          }
        } else if (call.method_name() == "launchActiveNodeRecording") {
          result->Success(flutter::EncodableValue(
              active_node_video_scanner::LaunchRectangleRecording(window)));
        } else if (call.method_name() == "findLatestActiveNodeRecording") {
          const auto recording = active_node_video_scanner::FindLatestRecording(
              Int64Argument(call.arguments(), "modifiedAfterMilliseconds"));
          if (recording.has_value()) {
            result->Success(
                flutter::EncodableValue(WideToUtf8(recording.value())));
          } else {
            result->Success(flutter::EncodableValue());
          }
        } else if (call.method_name() == "scanActiveNodeRecording" ||
                   call.method_name() == "scanInventoryScreenshot") {
          const bool still_image =
              call.method_name() == "scanInventoryScreenshot";
          const auto path =
              Utf8ToWide(StringArgument(call.arguments(), "path"));
          if (path.empty()) {
            result->Error(
                "invalid_path",
                still_image ? "Choose an inventory screenshot first."
                            : "Choose an MP4 recording first.");
            return;
          }
          if (active_node_scan_process_ != nullptr) {
            DWORD exit_code = STILL_ACTIVE;
            if (GetExitCodeProcess(active_node_scan_process_, &exit_code) ==
                    FALSE ||
                exit_code == STILL_ACTIVE) {
              result->Error("scan_busy",
                            "Another screenshot or recording is still being "
                            "read.");
              return;
            }
            StopActiveNodeScanner(false);
          }
          const auto executable_directory = ExecutableDirectory();
          const auto helper =
              executable_directory / L"BDOActiveNodeScanner.exe";
          if (executable_directory.empty() ||
              GetFileAttributesW(helper.c_str()) == INVALID_FILE_ATTRIBUTES) {
            result->Error(
                "scanner_helper_missing",
                "The isolated image scanner is missing. Keep the complete "
                "application folder together and try again.");
            return;
          }
          const auto result_path = ActiveNodeTemporaryPath(L"-result.bin");
          const auto progress_path = ActiveNodeTemporaryPath(L"-progress.bin");
          if (result_path.empty() || progress_path.empty()) {
            result->Error("scan_start_failed",
                          "Windows could not create a temporary scan file.");
            return;
          }
          std::wstring command_line =
              QuoteCommandLineArgument(helper.wstring()) + L" " +
              (still_image ? L"--image " : L"") +
              QuoteCommandLineArgument(path) + L" " +
              QuoteCommandLineArgument(result_path.wstring()) + L" " +
              QuoteCommandLineArgument(progress_path.wstring());
          std::vector<wchar_t> mutable_command(command_line.begin(),
                                               command_line.end());
          mutable_command.push_back(L'\0');
          STARTUPINFOW startup_info{};
          startup_info.cb = sizeof(startup_info);
          PROCESS_INFORMATION process_info{};
          const BOOL started = CreateProcessW(
              helper.c_str(), mutable_command.data(), nullptr, nullptr, FALSE,
              CREATE_NO_WINDOW, nullptr, executable_directory.c_str(),
              &startup_info, &process_info);
          if (started == FALSE) {
            result->Error(
                "scan_start_failed",
                "Windows could not start the isolated image scanner.");
            return;
          }
          CloseHandle(process_info.hThread);
          active_node_scan_process_ = process_info.hProcess;
          active_node_scan_process_id_ = process_info.dwProcessId;
          active_node_scan_result_path_ = result_path.wstring();
          active_node_scan_progress_path_ = progress_path.wstring();
          active_node_scan_last_progress_ = -1;
          active_node_scan_last_completed_frames_ = -1;
          active_node_scan_last_estimated_frames_ = -1;
          result->Success(flutter::EncodableValue(true));
        } else if (call.method_name() == "pollActiveNodeRecordingScan" ||
                   call.method_name() == "pollInventoryScreenshotScan") {
          if (active_node_scan_process_ == nullptr) {
            result->Error("scan_not_running",
                          "No screenshot or recording is currently being read.");
            return;
          }
          const auto progress = active_node_scan_protocol::ReadProgress(
              active_node_scan_progress_path_);
          if (progress.has_value() &&
              (progress->fraction != active_node_scan_last_progress_ ||
               progress->completed_frames !=
                   active_node_scan_last_completed_frames_ ||
               progress->estimated_frames !=
                   active_node_scan_last_estimated_frames_)) {
            active_node_scan_last_progress_ = progress->fraction;
            active_node_scan_last_completed_frames_ =
                progress->completed_frames;
            active_node_scan_last_estimated_frames_ =
                progress->estimated_frames;
            if (active_node_progress_channel_ != nullptr) {
              flutter::EncodableMap values;
              values[flutter::EncodableValue("fraction")] =
                  flutter::EncodableValue(progress->fraction);
              values[flutter::EncodableValue("completedFrames")] =
                  flutter::EncodableValue(progress->completed_frames);
              values[flutter::EncodableValue("estimatedFrames")] =
                  flutter::EncodableValue(progress->estimated_frames);
              active_node_progress_channel_->InvokeMethod(
                  "scanProgress", std::make_unique<flutter::EncodableValue>(
                                      std::move(values)));
            }
          }
          std::string read_error;
          auto scan = active_node_scan_protocol::ReadResult(
              active_node_scan_result_path_, &read_error);
          if (!scan.has_value()) {
            if (!read_error.empty()) {
              StopActiveNodeScanner(true);
              result->Error("scanner_result_invalid", read_error);
              return;
            }
            DWORD exit_code = STILL_ACTIVE;
            if (GetExitCodeProcess(active_node_scan_process_, &exit_code) !=
                    FALSE &&
                exit_code != STILL_ACTIVE) {
              StopActiveNodeScanner(false);
              result->Error(
                  "scanner_helper_failed",
                  "The isolated image scanner closed before returning OCR "
                  "results.");
              return;
            }
            result->Success(flutter::EncodableValue());
            return;
          }
          StopActiveNodeScanner(true);
          if (!scan->success) {
            result->Error(
                scan->error_code.empty() ? "scan_failed" : scan->error_code,
                scan->error_message.empty()
                    ? "Windows could not read that image."
                    : scan->error_message);
          } else {
            result->Success(EncodeActiveNodeScan(*scan));
          }
        } else if (call.method_name() == "cancelActiveNodeRecordingScan" ||
                   call.method_name() == "cancelInventoryScreenshotScan") {
          StopActiveNodeScanner(true);
          result->Success();
        } else {
          result->NotImplemented();
        }
      });
  flutter_view_window_ = flutter_controller_->view()->GetNativeWindow();
  SetChildContent(flutter_view_window_);
  if (SetWindowSubclass(flutter_view_window_, FlutterViewResizeSubclassProc,
                        kFlutterViewResizeSubclassId,
                        reinterpret_cast<DWORD_PTR>(GetHandle())) == FALSE) {
    return false;
  }

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    this->Show();
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
  StopActiveNodeScanner(true);
  if (flutter_view_window_ != nullptr) {
    RemoveWindowSubclass(flutter_view_window_, FlutterViewResizeSubclassProc,
                         kFlutterViewResizeSubclassId);
    flutter_view_window_ = nullptr;
  }
  if (flutter_controller_) {
    active_node_progress_channel_.reset();
    window_channel_.reset();
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                               LPARAM const lparam) noexcept {
  if (message == WM_DPICHANGED) {
    const UINT next_dpi = HIWORD(wparam);
    bottom_inset_physical_ = static_cast<int>(std::lround(
        bottom_inset_logical_ * static_cast<double>(next_dpi) / 96.0));
    // Windows supplies a newly scaled rectangle. If the user later hides the
    // strip, preserve that scaled placement instead of restoring stale pixels
    // captured on the previous monitor.
    has_bottom_inset_restore_bounds_ = false;
  }
  // Native frame behavior must run before Flutter's top-level handler. The
  // embedded view can otherwise answer HTCLIENT first, swallowing the custom
  // resize frame around this borderless window.
  switch (message) {
    case kApplyBottomInsetMessage: {
      // SetWindowPos synchronously sends WM_SIZE to Flutter's child view.
      // Applying it inside the platform-channel callback can therefore
      // re-enter flutter_windows while that callback is still active. Queue
      // the resize and perform it only after the callback has returned.
      bottom_inset_message_pending_ = false;
      SetBottomInset(pending_bottom_inset_logical_);
      return 0;
    }
    case WM_NCHITTEST:
      return HitTestResizeFrame(hwnd, lparam);
    case WM_SIZING:
      PreserveResizeAspect(hwnd, wparam, reinterpret_cast<RECT*>(lparam),
                           bottom_inset_physical_);
      return TRUE;
    case WM_GETMINMAXINFO: {
      auto* info = reinterpret_cast<MINMAXINFO*>(lparam);
      // These parity/audit bounds are physical window dimensions. Scaling the
      // track minimum a second time made 1200x752 become 1500x940 at 125% DPI,
      // preventing both normal edge resizing and UI automation from reaching
      // the supported minimum.
      info->ptMinTrackSize.x = kMinimumWindowWidth;
      info->ptMinTrackSize.y =
          kMinimumWindowHeight + bottom_inset_physical_;
      return 0;
    }
  }

  // Give Flutter, including plugins, an opportunity to handle window messages.
  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) {
      return *result;
    }
  }

  switch (message) {
    case WM_CLOSE: {
      if (native_close_allowed_) {
        DestroyWindow(hwnd);
        return 0;
      }
      if (close_request_pending_ || window_channel_ == nullptr) {
        return 0;
      }
      close_request_pending_ = true;
      window_channel_->InvokeMethod(
          "closeRequested", std::make_unique<flutter::EncodableValue>(),
          std::make_unique<flutter::MethodResultFunctions<
              flutter::EncodableValue>>(
              [this](const flutter::EncodableValue* result) {
                close_request_pending_ = false;
                const bool* approved =
                    result == nullptr ? nullptr : std::get_if<bool>(result);
                if (approved == nullptr || !*approved || GetHandle() == nullptr) {
                  return;
                }
                native_close_allowed_ = true;
                if (PostMessage(GetHandle(), WM_CLOSE, 0, 0) == 0) {
                  native_close_allowed_ = false;
                }
              },
              [this](const std::string&, const std::string&,
                     const flutter::EncodableValue*) {
                close_request_pending_ = false;
              },
              [this]() { close_request_pending_ = false; }));
      return 0;
    }
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
