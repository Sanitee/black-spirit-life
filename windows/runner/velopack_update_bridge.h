#ifndef RUNNER_VELOPACK_UPDATE_BRIDGE_H_
#define RUNNER_VELOPACK_UPDATE_BRIDGE_H_

#include <flutter/binary_messenger.h>
#include <flutter/encodable_value.h>
#include <flutter/method_channel.h>
#include <windows.h>

#include <memory>
#include <string>

// Keeps all Velopack network and package work away from Flutter's platform
// thread. The bridge only posts lightweight status notifications back to the
// native window, where it is safe to invoke the Dart method channel.
class VelopackUpdateBridge {
 public:
  VelopackUpdateBridge(flutter::BinaryMessenger* messenger, HWND window);
  ~VelopackUpdateBridge();

  VelopackUpdateBridge(const VelopackUpdateBridge&) = delete;
  VelopackUpdateBridge& operator=(const VelopackUpdateBridge&) = delete;

  bool HandleWindowMessage(UINT message, WPARAM wparam, LPARAM lparam,
                           LRESULT* result);

 private:
  struct SharedState;

  static constexpr UINT kStatusChangedMessage = WM_APP + 0x42;

  static void CheckForUpdates(std::shared_ptr<SharedState> state,
                              std::string source);
  static void DownloadUpdate(std::shared_ptr<SharedState> state);
  static void DownloadProgress(void* user_data, size_t progress);

  flutter::EncodableValue CurrentSnapshot() const;
  void InvokeStatusChanged();

  std::shared_ptr<SharedState> state_;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel_;
};

#endif  // RUNNER_VELOPACK_UPDATE_BRIDGE_H_
