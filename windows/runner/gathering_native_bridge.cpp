#include "gathering_native_bridge.h"

#include <flutter/standard_method_codec.h>
#include <shellapi.h>
#include <shobjidl.h>
#include <wrl/client.h>
#include <algorithm>
#include <cstdint>
#include <optional>
#include <string>
#include <utility>
#include <vector>

#include "clipboard_image_reader.h"

namespace {
using flutter::EncodableMap;
using flutter::EncodableValue;
using Microsoft::WRL::ComPtr;

HANDLE g_session_import_process = nullptr;
DWORD g_session_import_process_id = 0;

void ForgetSessionImportProcess() {
  if (g_session_import_process != nullptr) {
    CloseHandle(g_session_import_process);
    g_session_import_process = nullptr;
  }
  g_session_import_process_id = 0;
}

bool SessionImportIsRunning() {
  if (g_session_import_process == nullptr) return false;
  if (WaitForSingleObject(g_session_import_process, 0) == WAIT_TIMEOUT) {
    return true;
  }
  ForgetSessionImportProcess();
  return false;
}

BOOL CALLBACK ActivateSessionImportWindow(HWND window, LPARAM parameter) {
  DWORD process_id = 0;
  GetWindowThreadProcessId(window, &process_id);
  if (process_id != static_cast<DWORD>(parameter) || !IsWindowVisible(window)) {
    return TRUE;
  }
  if (IsIconic(window)) ShowWindow(window, SW_RESTORE);
  SetForegroundWindow(window);
  return FALSE;
}

BOOL CALLBACK CloseSessionImportWindow(HWND window, LPARAM parameter) {
  DWORD process_id = 0;
  GetWindowThreadProcessId(window, &process_id);
  if (process_id == static_cast<DWORD>(parameter)) {
    PostMessageW(window, WM_CLOSE, 0, 0);
  }
  return TRUE;
}

std::wstring ToWide(const std::string& value) {
  if (value.empty()) return {};
  const int size = MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, value.data(),
                                      static_cast<int>(value.size()), nullptr, 0);
  if (size <= 0) return {};
  std::wstring result(size, L'\0');
  MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, value.data(),
                      static_cast<int>(value.size()), result.data(), size);
  return result;
}

std::string ToUtf8(const std::wstring& value) {
  if (value.empty()) return {};
  const int size = WideCharToMultiByte(CP_UTF8, 0, value.data(),
                                      static_cast<int>(value.size()), nullptr, 0,
                                      nullptr, nullptr);
  if (size <= 0) return {};
  std::string result(size, '\0');
  WideCharToMultiByte(CP_UTF8, 0, value.data(), static_cast<int>(value.size()),
                      result.data(), size, nullptr, nullptr);
  return result;
}

const EncodableValue* Argument(const EncodableValue* arguments,
                               const std::string& key) {
  if (arguments == nullptr) return nullptr;
  const auto* map = std::get_if<EncodableMap>(arguments);
  if (map == nullptr) return nullptr;
  const auto found = map->find(EncodableValue(key));
  return found == map->end() ? nullptr : &found->second;
}

std::optional<std::string> PickImage(HWND window) {
  ComPtr<IFileOpenDialog> dialog;
  if (FAILED(CoCreateInstance(CLSID_FileOpenDialog, nullptr, CLSCTX_INPROC_SERVER,
                              IID_PPV_ARGS(dialog.GetAddressOf())))) return std::nullopt;
  const COMDLG_FILTERSPEC filters[] = {
      {L"Screenshot images", L"*.png;*.jpg;*.jpeg;*.bmp"}};
  dialog->SetFileTypes(1, filters);
  dialog->SetTitle(L"Choose an inventory screenshot");
  FILEOPENDIALOGOPTIONS options;
  if (SUCCEEDED(dialog->GetOptions(&options))) {
    dialog->SetOptions(options | FOS_FORCEFILESYSTEM | FOS_FILEMUSTEXIST |
                       FOS_PATHMUSTEXIST | FOS_NOCHANGEDIR | FOS_DONTADDTORECENT);
  }
  if (FAILED(dialog->Show(window))) return std::nullopt;
  ComPtr<IShellItem> item;
  if (FAILED(dialog->GetResult(item.GetAddressOf()))) return std::nullopt;
  PWSTR path = nullptr;
  if (FAILED(item->GetDisplayName(SIGDN_FILESYSPATH, &path)) || path == nullptr) {
    return std::nullopt;
  }
  const std::string selected = ToUtf8(path);
  CoTaskMemFree(path);
  return selected.empty() ? std::nullopt : std::optional<std::string>(selected);
}

bool OpenExternal(HWND window, const std::string& url) {
  if (url.size() > 8192 ||
      (url.rfind("https://", 0) != 0 && url.rfind("http://", 0) != 0) ||
      std::any_of(url.begin(), url.end(), [](unsigned char c) {
        return c <= 0x20 || c == 0x7f || c == '"';
      })) return false;
  const std::wstring wide = ToWide(url);
  if (wide.empty()) return false;
  return reinterpret_cast<INT_PTR>(ShellExecuteW(window, L"open", wide.c_str(),
      nullptr, nullptr, SW_SHOWNORMAL)) > 32;
}

bool OpenReferenceWindow(int glass_opacity_percent) {
  std::wstring executable(32768, L'\0');
  const DWORD size = GetModuleFileNameW(nullptr, executable.data(),
                                      static_cast<DWORD>(executable.size()));
  if (size == 0 || size >= executable.size()) return false;
  executable.resize(size);
  const auto slash = executable.find_last_of(L"\\/");
  if (slash == std::wstring::npos) return false;
  const std::wstring directory = executable.substr(0, slash);
  glass_opacity_percent = std::clamp(glass_opacity_percent, 0, 100);
  std::wstring command = L"\"" + executable + L"\" --reference "
                         L"--glass-opacity=" +
                         std::to_wstring(glass_opacity_percent);
  STARTUPINFOW startup{};
  startup.cb = sizeof(startup);
  PROCESS_INFORMATION process{};
  // The GUI child has its own lifetime and receives no screenshot file or data.
  if (!CreateProcessW(executable.c_str(), command.data(), nullptr, nullptr, FALSE,
                       CREATE_NO_WINDOW, nullptr, directory.c_str(), &startup,
                       &process)) return false;
  CloseHandle(process.hThread);
  CloseHandle(process.hProcess);
  return true;
}

bool OpenSessionImport(const std::optional<std::string>& receipt_directory) {
  if (!receipt_directory.has_value()) return false;
  std::wstring inbox;
  inbox = ToWide(*receipt_directory);
  if (inbox.size() < 4 || inbox.size() > 4096 ||
      !((inbox[0] >= L'A' && inbox[0] <= L'Z') ||
        (inbox[0] >= L'a' && inbox[0] <= L'z')) ||
      inbox[1] != L':' || (inbox[2] != L'\\' && inbox[2] != L'/') ||
      std::any_of(inbox.begin(), inbox.end(), [](wchar_t c) {
        return c < 0x20 || c == 0x7f || c == L'"';
      })) return false;
  std::replace(inbox.begin(), inbox.end(), L'/', L'\\');
  while (!inbox.empty() && inbox.back() == L'\\') inbox.pop_back();
  const auto inbox_slash = inbox.find_last_of(L'\\');
  if (inbox_slash == std::wstring::npos ||
      _wcsicmp(inbox.substr(inbox_slash + 1).c_str(),
               L"session-import-inbox") != 0) {
    return false;
  }
  const std::wstring gathering_directory = inbox.substr(0, inbox_slash);
  const auto gathering_slash = gathering_directory.find_last_of(L'\\');
  if (gathering_slash == std::wstring::npos ||
      _wcsicmp(gathering_directory.substr(gathering_slash + 1).c_str(),
               L"gathering") != 0) {
    return false;
  }
  const std::wstring selected_root = gathering_directory.substr(0, gathering_slash);
  if (selected_root.size() < 4) return false;
  const std::wstring data_root =
      selected_root + L"\\integrations\\session-import";

  if (SessionImportIsRunning()) {
    EnumWindows(ActivateSessionImportWindow,
                static_cast<LPARAM>(g_session_import_process_id));
    return true;
  }
  std::wstring executable(32768, L'\0');
  const DWORD size = GetModuleFileNameW(nullptr, executable.data(),
                                       static_cast<DWORD>(executable.size()));
  if (size == 0 || size >= executable.size()) return false;
  executable.resize(size);
  const auto slash = executable.find_last_of(L"\\/");
  if (slash == std::wstring::npos) return false;

  const std::wstring application_directory = executable.substr(0, slash);
  const std::wstring helper_directory =
      application_directory + L"\\session_import";
  const std::wstring helper = helper_directory + L"\\Session Import.exe";
  const DWORD attributes = GetFileAttributesW(helper.c_str());
  if (attributes == INVALID_FILE_ATTRIBUTES ||
      (attributes & FILE_ATTRIBUTE_DIRECTORY) != 0) {
    return false;
  }

  std::wstring command = L"\"" + helper + L"\"";
  command += L" \"--receipt-directory=" + inbox + L"\"";
  command += L" \"--data-root=" + data_root + L"\"";
  STARTUPINFOW startup{};
  startup.cb = sizeof(startup);
  PROCESS_INFORMATION process{};
  if (!CreateProcessW(helper.c_str(), command.data(), nullptr, nullptr, FALSE,
                      0, nullptr, helper_directory.c_str(), &startup,
                      &process)) {
    return false;
  }
  CloseHandle(process.hThread);
  g_session_import_process = process.hProcess;
  g_session_import_process_id = process.dwProcessId;
  return true;
}

bool ShutdownSessionImport() {
  if (!SessionImportIsRunning()) return true;
  EnumWindows(CloseSessionImportWindow,
              static_cast<LPARAM>(g_session_import_process_id));
  if (WaitForSingleObject(g_session_import_process, 8000) != WAIT_OBJECT_0) {
    return false;
  }
  ForgetSessionImportProcess();
  return true;
}
}  // namespace

std::unique_ptr<flutter::MethodChannel<EncodableValue>>
CreateGatheringNativeBridge(
    flutter::BinaryMessenger* messenger, HWND window) {
  auto channel = std::make_unique<flutter::MethodChannel<EncodableValue>>(
      messenger, "bdo_gathering/native", &flutter::StandardMethodCodec::GetInstance());
  channel->SetMethodCallHandler(
      [window](const flutter::MethodCall<EncodableValue>& call,
               std::unique_ptr<flutter::MethodResult<EncodableValue>> result) {
        if (call.method_name() == "readClipboardImage") {
          auto png = clipboard_image_reader::ReadPng(window);
          if (png.has_value()) result->Success(EncodableValue(std::move(*png)));
          else result->Success();
        } else if (call.method_name() == "pickImage") {
          const auto path = PickImage(window);
          if (path.has_value()) result->Success(EncodableValue(*path));
          else result->Success();
        } else if (call.method_name() == "openExternal") {
          const auto* argument = Argument(call.arguments(), "url");
          const auto* url = argument ? std::get_if<std::string>(argument) : nullptr;
          result->Success(EncodableValue(url && OpenExternal(window, *url)));
        } else if (call.method_name() == "openReferenceWindow") {
          int opacity = 48;
          const auto* argument = Argument(call.arguments(), "glassOpacityPercent");
          if (const auto* value = argument
                  ? std::get_if<int32_t>(argument)
                  : nullptr) {
            opacity = *value;
          } else if (const auto* wide_value = argument
                         ? std::get_if<int64_t>(argument)
                         : nullptr) {
            opacity =
                static_cast<int>(std::clamp<int64_t>(*wide_value, 0, 100));
          }
          result->Success(EncodableValue(OpenReferenceWindow(opacity)));
        } else if (call.method_name() == "openSessionImport") {
          const auto* argument = Argument(call.arguments(), "receiptDirectory");
          const auto* directory = argument ? std::get_if<std::string>(argument) : nullptr;
          if (argument && !directory) result->Success(EncodableValue(false));
          else result->Success(EncodableValue(OpenSessionImport(
              directory ? std::optional<std::string>(*directory) : std::nullopt)));
        } else if (call.method_name() == "shutdownSessionImport") {
          result->Success(EncodableValue(ShutdownSessionImport()));
        } else if (call.method_name() == "setAlwaysOnTop") {
          const auto* argument = Argument(call.arguments(), "enabled");
          const auto* enabled = argument ? std::get_if<bool>(argument) : nullptr;
          const bool success = enabled && SetWindowPos(
              window, *enabled ? HWND_TOPMOST : HWND_NOTOPMOST, 0, 0, 0, 0,
              SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE) != FALSE;
          result->Success(EncodableValue(success));
        } else {
          result->NotImplemented();
        }
      });
  return channel;
}
