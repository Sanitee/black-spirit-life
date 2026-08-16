#include "velopack_update_bridge.h"

#include <flutter/method_call.h>
#include <flutter/method_result.h>
#include <flutter/standard_method_codec.h>
#include <wininet.h>

#include <algorithm>
#include <atomic>
#include <cstdint>
#include <mutex>
#include <thread>
#include <utility>
#include <vector>

#include "Velopack.h"

namespace {

struct UpdateSnapshot {
  std::string status = "idle";
  bool installed = false;
  bool portable = true;
  std::string current_version;
  std::string app_id;
  std::string target_version;
  std::string release_notes_markdown;
  std::int64_t size_bytes = 0;
  double progress = 0;
  std::string message;
};

std::string StringArgument(const flutter::EncodableValue* arguments,
                           const char* key) {
  const auto* map = std::get_if<flutter::EncodableMap>(arguments);
  if (map == nullptr) return std::string();
  const auto entry = map->find(flutter::EncodableValue(key));
  if (entry == map->end()) return std::string();
  const auto* value = std::get_if<std::string>(&entry->second);
  return value == nullptr ? std::string() : *value;
}

std::string SafeString(const char* value) {
  return value == nullptr ? std::string() : std::string(value);
}

std::string LastVelopackError() {
  std::vector<char> buffer(1024, '\0');
  const size_t required = vpkc_get_last_error(buffer.data(), buffer.size());
  if (required > buffer.size()) {
    buffer.assign(required, '\0');
    vpkc_get_last_error(buffer.data(), buffer.size());
  }
  const std::string message(buffer.data());
  return message.empty() ? "Velopack did not provide an error message."
                         : message;
}

std::string ManagerString(vpkc_update_manager_t* manager, bool app_id) {
  const size_t required = app_id
                              ? vpkc_get_app_id(manager, nullptr, 0)
                              : vpkc_get_current_version(manager, nullptr, 0);
  if (required == 0) return std::string();
  std::vector<char> buffer(required, '\0');
  if (app_id) {
    vpkc_get_app_id(manager, buffer.data(), buffer.size());
  } else {
    vpkc_get_current_version(manager, buffer.data(), buffer.size());
  }
  return std::string(buffer.data());
}

bool IsRemoteSource(const std::string& source) {
  return source.rfind("https://", 0) == 0 || source.rfind("http://", 0) == 0;
}

std::string FailureStatus(const std::string& source) {
  DWORD flags = 0;
  if (IsRemoteSource(source) &&
      InternetGetConnectedState(&flags, 0) == FALSE) {
    return "offline";
  }
  return "error";
}

flutter::EncodableValue EncodeSnapshot(const UpdateSnapshot& snapshot) {
  flutter::EncodableMap values;
  values[flutter::EncodableValue("status")] =
      flutter::EncodableValue(snapshot.status);
  values[flutter::EncodableValue("installed")] =
      flutter::EncodableValue(snapshot.installed);
  values[flutter::EncodableValue("portable")] =
      flutter::EncodableValue(snapshot.portable);
  values[flutter::EncodableValue("currentVersion")] =
      flutter::EncodableValue(snapshot.current_version);
  values[flutter::EncodableValue("appId")] =
      flutter::EncodableValue(snapshot.app_id);
  values[flutter::EncodableValue("targetVersion")] =
      flutter::EncodableValue(snapshot.target_version);
  values[flutter::EncodableValue("releaseNotesMarkdown")] =
      flutter::EncodableValue(snapshot.release_notes_markdown);
  values[flutter::EncodableValue("sizeBytes")] =
      flutter::EncodableValue(snapshot.size_bytes);
  values[flutter::EncodableValue("progress")] =
      flutter::EncodableValue(snapshot.progress);
  values[flutter::EncodableValue("message")] =
      flutter::EncodableValue(snapshot.message);
  return flutter::EncodableValue(std::move(values));
}

}  // namespace

struct VelopackUpdateBridge::SharedState {
  ~SharedState() {
    std::lock_guard<std::mutex> lock(mutex);
    if (update != nullptr) {
      vpkc_free_update_info(update);
      update = nullptr;
    }
    if (manager != nullptr) {
      vpkc_free_update_manager(manager);
      manager = nullptr;
    }
  }

  void Publish(UpdateSnapshot next) {
    {
      std::lock_guard<std::mutex> lock(mutex);
      snapshot = std::move(next);
    }
    const HWND target = window.load();
    if (alive.load() && target != nullptr) {
      PostMessage(target, kStatusChangedMessage, 0, 0);
    }
  }

  UpdateSnapshot ReadSnapshot() const {
    std::lock_guard<std::mutex> lock(mutex);
    return snapshot;
  }

  void ResetVelopack() {
    std::lock_guard<std::mutex> lock(mutex);
    if (update != nullptr) {
      vpkc_free_update_info(update);
      update = nullptr;
    }
    if (manager != nullptr) {
      vpkc_free_update_manager(manager);
      manager = nullptr;
    }
  }

  mutable std::mutex mutex;
  std::atomic<bool> alive{true};
  std::atomic<bool> busy{false};
  std::atomic<HWND> window{nullptr};
  UpdateSnapshot snapshot;
  std::string source;
  vpkc_update_manager_t* manager = nullptr;
  vpkc_update_info_t* update = nullptr;
};

VelopackUpdateBridge::VelopackUpdateBridge(
    flutter::BinaryMessenger* messenger, HWND window)
    : state_(std::make_shared<SharedState>()),
      channel_(
          std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
              messenger, "com.blackspiritlife/updates",
              &flutter::StandardMethodCodec::GetInstance())) {
  state_->window.store(window);
  channel_->SetMethodCallHandler(
      [this](const flutter::MethodCall<flutter::EncodableValue>& call,
             std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
                 result) {
        if (call.method_name() == "getUpdateStatus") {
          result->Success(CurrentSnapshot());
          return;
        }

        if (call.method_name() == "checkForUpdates") {
          const std::string source = StringArgument(call.arguments(), "source");
          if (source.empty()) {
            UpdateSnapshot snapshot = state_->ReadSnapshot();
            snapshot.status = "notConfigured";
            snapshot.message =
                "No update source has been configured.";
            state_->Publish(std::move(snapshot));
            result->Success(CurrentSnapshot());
            return;
          }
          if (state_->busy.exchange(true)) {
            result->Error("update_busy",
                          "Another update operation is already in progress.");
            return;
          }
          UpdateSnapshot snapshot = state_->ReadSnapshot();
          snapshot.status = "checking";
          snapshot.target_version.clear();
          snapshot.release_notes_markdown.clear();
          snapshot.size_bytes = 0;
          snapshot.progress = 0;
          snapshot.message = "Checking the Black Spirit Life update source.";
          state_->Publish(std::move(snapshot));
          std::thread(&VelopackUpdateBridge::CheckForUpdates, state_, source)
              .detach();
          result->Success(CurrentSnapshot());
          return;
        }

        if (call.method_name() == "downloadUpdate") {
          if (state_->busy.exchange(true)) {
            result->Error("update_busy",
                          "Another update operation is already in progress.");
            return;
          }
          {
            std::lock_guard<std::mutex> lock(state_->mutex);
            if (state_->manager == nullptr || state_->update == nullptr ||
                state_->update->TargetFullRelease == nullptr) {
              state_->busy.store(false);
              result->Error("update_unavailable",
                            "Check for an available update first.");
              return;
            }
          }
          UpdateSnapshot snapshot = state_->ReadSnapshot();
          snapshot.status = "downloading";
          snapshot.progress = 0;
          snapshot.message = "Downloading the Black Spirit Life update.";
          state_->Publish(std::move(snapshot));
          std::thread(&VelopackUpdateBridge::DownloadUpdate, state_).detach();
          result->Success(CurrentSnapshot());
          return;
        }

        if (call.method_name() == "restartAndApply") {
          if (state_->busy.load()) {
            result->Error("update_busy",
                          "Wait for the current update operation to finish.");
            return;
          }
          bool prepared = false;
          {
            std::lock_guard<std::mutex> lock(state_->mutex);
            if (state_->manager == nullptr || state_->update == nullptr ||
                state_->update->TargetFullRelease == nullptr ||
                state_->snapshot.status != "ready") {
              result->Error("update_not_ready",
                            "Download the update before restarting.");
              return;
            }
            prepared = vpkc_wait_exit_then_apply_updates(
                state_->manager, state_->update->TargetFullRelease, false, true,
                nullptr, 0);
          }
          if (!prepared) {
            UpdateSnapshot snapshot = state_->ReadSnapshot();
            snapshot.status = FailureStatus(state_->source);
            snapshot.message = LastVelopackError();
            state_->Publish(std::move(snapshot));
            result->Error("update_apply_failed", LastVelopackError());
            return;
          }
          UpdateSnapshot snapshot = state_->ReadSnapshot();
          snapshot.status = "applying";
          snapshot.message =
              "The updater is ready. Black Spirit Life can now close.";
          state_->Publish(std::move(snapshot));
          result->Success(CurrentSnapshot());
          return;
        }

        result->NotImplemented();
      });
}

VelopackUpdateBridge::~VelopackUpdateBridge() {
  if (state_ != nullptr) {
    state_->alive.store(false);
    state_->window.store(nullptr);
  }
  if (channel_ != nullptr) {
    channel_->SetMethodCallHandler(nullptr);
    channel_.reset();
  }
  state_.reset();
}

bool VelopackUpdateBridge::HandleWindowMessage(UINT message, WPARAM wparam,
                                               LPARAM lparam,
                                               LRESULT* result) {
  if (message != kStatusChangedMessage) return false;
  InvokeStatusChanged();
  if (result != nullptr) *result = 0;
  return true;
}

void VelopackUpdateBridge::CheckForUpdates(
    std::shared_ptr<SharedState> state, std::string source) {
  state->ResetVelopack();
  state->source = source;

  vpkc_update_manager_t* manager = nullptr;
  if (!vpkc_new_update_manager(source.c_str(), nullptr, nullptr, &manager) ||
      manager == nullptr) {
    UpdateSnapshot snapshot = state->ReadSnapshot();
    snapshot.status = FailureStatus(source);
    snapshot.message = LastVelopackError();
    state->busy.store(false);
    state->Publish(std::move(snapshot));
    return;
  }

  UpdateSnapshot snapshot = state->ReadSnapshot();
  snapshot.portable = vpkc_is_portable(manager);
  snapshot.installed = !snapshot.portable;
  snapshot.current_version = ManagerString(manager, false);
  snapshot.app_id = ManagerString(manager, true);
  if (snapshot.portable) {
    snapshot.status = "unsupported";
    snapshot.message =
        "Update checks are available after Black Spirit Life is installed.";
    vpkc_free_update_manager(manager);
    state->busy.store(false);
    state->Publish(std::move(snapshot));
    return;
  }

  vpkc_update_info_t* update = nullptr;
  const vpkc_update_check_t check =
      vpkc_check_for_updates(manager, &update);
  if (check == UPDATE_ERROR) {
    snapshot.status = FailureStatus(source);
    snapshot.message = LastVelopackError();
    if (update != nullptr) vpkc_free_update_info(update);
    vpkc_free_update_manager(manager);
    state->busy.store(false);
    state->Publish(std::move(snapshot));
    return;
  }
  if (check == NO_UPDATE_AVAILABLE || check == REMOTE_IS_EMPTY ||
      update == nullptr || update->TargetFullRelease == nullptr) {
    snapshot.status = "upToDate";
    snapshot.message = check == REMOTE_IS_EMPTY
                           ? "The update source has no newer release yet."
                           : "Black Spirit Life is up to date.";
    if (update != nullptr) vpkc_free_update_info(update);
    vpkc_free_update_manager(manager);
    state->busy.store(false);
    state->Publish(std::move(snapshot));
    return;
  }

  snapshot.status = "available";
  snapshot.target_version = SafeString(update->TargetFullRelease->Version);
  snapshot.release_notes_markdown =
      SafeString(update->TargetFullRelease->NotesMarkdown);
  snapshot.size_bytes =
      static_cast<std::int64_t>(update->TargetFullRelease->Size);
  snapshot.message = "A Black Spirit Life update is available.";
  {
    std::lock_guard<std::mutex> lock(state->mutex);
    state->manager = manager;
    state->update = update;
  }
  state->busy.store(false);
  state->Publish(std::move(snapshot));
}

void VelopackUpdateBridge::DownloadUpdate(
    std::shared_ptr<SharedState> state) {
  vpkc_update_manager_t* manager = nullptr;
  vpkc_update_info_t* update = nullptr;
  {
    std::lock_guard<std::mutex> lock(state->mutex);
    manager = state->manager;
    update = state->update;
  }
  const bool downloaded = manager != nullptr && update != nullptr &&
                          vpkc_download_updates(manager, update,
                                                DownloadProgress, state.get());
  UpdateSnapshot snapshot = state->ReadSnapshot();
  if (downloaded) {
    snapshot.status = "ready";
    snapshot.progress = 1;
    snapshot.message = "The update is ready to install.";
  } else {
    snapshot.status = FailureStatus(state->source);
    snapshot.message = LastVelopackError();
  }
  state->busy.store(false);
  state->Publish(std::move(snapshot));
}

void VelopackUpdateBridge::DownloadProgress(void* user_data, size_t progress) {
  auto* state = static_cast<SharedState*>(user_data);
  if (state == nullptr || !state->alive.load()) return;
  UpdateSnapshot snapshot = state->ReadSnapshot();
  snapshot.status = "downloading";
  snapshot.progress = std::clamp(static_cast<double>(progress) / 100.0, 0.0, 1.0);
  snapshot.message = "Downloading the Black Spirit Life update.";
  state->Publish(std::move(snapshot));
}

flutter::EncodableValue VelopackUpdateBridge::CurrentSnapshot() const {
  return EncodeSnapshot(state_->ReadSnapshot());
}

void VelopackUpdateBridge::InvokeStatusChanged() {
  if (channel_ == nullptr) return;
  channel_->InvokeMethod(
      "statusChanged",
      std::make_unique<flutter::EncodableValue>(CurrentSnapshot()));
}
