#ifndef RUNNER_FLUTTER_WINDOW_H_
#define RUNNER_FLUTTER_WINDOW_H_

#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <flutter/method_channel.h>

#include <memory>
#include <string>

#include "win32_window.h"

// A window that does nothing but host a Flutter view.
class FlutterWindow : public Win32Window {
 public:
  // Creates a new FlutterWindow hosting a Flutter view running |project|.
  explicit FlutterWindow(const flutter::DartProject& project);
  virtual ~FlutterWindow();

 protected:
  // Win32Window:
  bool OnCreate() override;
  void OnDestroy() override;
  LRESULT MessageHandler(HWND window, UINT const message, WPARAM const wparam,
                         LPARAM const lparam) noexcept override;

 private:
  void StopActiveNodeScanner(bool terminate);
  bool QueueBottomInset(double logical_pixels);
  void SetBottomInset(double logical_pixels);

  // The project to run.
  flutter::DartProject project_;

  // The Flutter instance hosted by this window.
  std::unique_ptr<flutter::FlutterViewController> flutter_controller_;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>>
      window_channel_;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>>
      active_node_progress_channel_;
  HWND flutter_view_window_ = nullptr;
  bool native_close_allowed_ = false;
  bool close_request_pending_ = false;
  double bottom_inset_logical_ = 0;
  int bottom_inset_physical_ = 0;
  double pending_bottom_inset_logical_ = 0;
  bool bottom_inset_message_pending_ = false;
  bool has_bottom_inset_restore_bounds_ = false;
  bool bottom_inset_restore_uses_placement_ = false;
  RECT bottom_inset_restore_bounds_{};
  RECT bottom_inset_applied_bounds_{};
  HANDLE active_node_scan_process_ = nullptr;
  DWORD active_node_scan_process_id_ = 0;
  std::wstring active_node_scan_result_path_;
  std::wstring active_node_scan_progress_path_;
  double active_node_scan_last_progress_ = -1;
  int active_node_scan_last_completed_frames_ = -1;
  int active_node_scan_last_estimated_frames_ = -1;
};

#endif  // RUNNER_FLUTTER_WINDOW_H_
