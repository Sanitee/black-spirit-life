#include <windows.h>
#include <windowsx.h>

#include <dwmapi.h>
#include <shellapi.h>
#include <shobjidl.h>

#include <algorithm>
#include <cmath>
#include <filesystem>
#include <memory>
#include <new>
#include <string>
#include <thread>
#include <vector>

#include "embedded_payload.h"
#include "install_engine.h"
#include "install_path_policy.h"
#include "installed_beta_locator.h"
#include "installer_build_config.h"
#include "installer_model.h"
#include "installer_renderer.h"
#include "personal_data_removal.h"
#include "resource.h"

namespace bsl::installer {
namespace {

constexpr wchar_t kWindowClass[] = L"BlackSpiritLifeInstallerWindow";
constexpr UINT_PTR kCaretTimer = 1;
constexpr UINT_PTR kActivityTimer = 2;
constexpr UINT kInstallFinishedMessage = WM_APP + 41;
constexpr UINT kInstallProgressMessage = WM_APP + 42;
constexpr int kWindowWorkAreaMargin = 12;
constexpr float kCompactPreviewHeight = 370.0F;

struct InstallProgressNotice {
  std::wstring message;
  std::wstring retained_log;
};

struct WindowState {
  explicit WindowState(HINSTANCE instance) : renderer(instance) {}

  InstallerRenderer renderer;
  InstallerModel model;
  InteractionState interaction;
  UINT dpi = 96;
  bool tracking_mouse = false;
  std::thread install_worker;
};

struct FittedWindowMetrics {
  UINT render_dpi = 96;
  int width = static_cast<int>(kPreviewWidth);
  int height = static_cast<int>(kPreviewHeight);
};

FittedWindowMetrics FitWindowToWorkArea(UINT requested_dpi,
                                        const RECT &work_area) {
  const int available_width =
      std::max(1, static_cast<int>(work_area.right - work_area.left) -
                      2 * kWindowWorkAreaMargin);
  const int available_height =
      std::max(1, static_cast<int>(work_area.bottom - work_area.top) -
                      2 * kWindowWorkAreaMargin);
  const UINT width_dpi = static_cast<UINT>(
      std::max(48.0, std::floor(available_width * 96.0 / kPreviewWidth)));
  const UINT height_dpi = static_cast<UINT>(std::max(
      48.0, std::floor(available_height * 96.0 / kCompactPreviewHeight)));
  const UINT render_dpi =
      std::max<UINT>(48, std::min({requested_dpi, width_dpi, height_dpi}));
  const double scale = static_cast<double>(render_dpi) / 96.0;
  const float logical_height =
      std::clamp(static_cast<float>(available_height / scale),
                 kCompactPreviewHeight, kPreviewHeight);
  return {
      render_dpi,
      static_cast<int>(std::lround(kPreviewWidth * scale)),
      static_cast<int>(std::lround(logical_height * scale)),
  };
}

RECT MonitorWorkAreaForRect(const RECT &reference) {
  MONITORINFO monitor_info{sizeof(MONITORINFO)};
  const HMONITOR monitor =
      MonitorFromRect(&reference, MONITOR_DEFAULTTONEAREST);
  if (monitor != nullptr && GetMonitorInfoW(monitor, &monitor_info))
    return monitor_info.rcWork;
  RECT fallback{0, 0, GetSystemMetrics(SM_CXSCREEN),
                GetSystemMetrics(SM_CYSCREEN)};
  return fallback;
}

POINT CenteredWindowOrigin(const RECT &work_area,
                           const FittedWindowMetrics &metrics) {
  const int work_width = static_cast<int>(work_area.right - work_area.left);
  const int work_height = static_cast<int>(work_area.bottom - work_area.top);
  return {work_area.left + std::max(0, (work_width - metrics.width) / 2),
          work_area.top + std::max(0, (work_height - metrics.height) / 2)};
}

std::wstring DefaultInstallPath() {
  std::wstring result(32768, L'\0');
  const DWORD length = GetEnvironmentVariableW(
      L"LOCALAPPDATA", result.data(), static_cast<DWORD>(result.size()));
  if (length == 0 || length >= result.size()) {
    return L"C:\\BlackSpiritLife.App";
  }
  result.resize(length);
  return (std::filesystem::path(result) /
          std::wstring(build_config::kPackageId))
      .wstring();
}

bool PointInRect(const D2D1_RECT_F &rect, float x, float y) {
  return x >= rect.left && x < rect.right && y >= rect.top && y < rect.bottom;
}

HRESULT RenderBufferedInstaller(WindowState &state, HDC target,
                                const RECT &client) {
  const int width = std::max(0L, client.right - client.left);
  const int height = std::max(0L, client.bottom - client.top);
  if (width == 0 || height == 0) {
    return S_OK;
  }

  HDC buffer_dc = CreateCompatibleDC(target);
  if (buffer_dc == nullptr) {
    return state.renderer.Render(target, static_cast<UINT>(width),
                                 static_cast<UINT>(height),
                                 static_cast<float>(state.dpi), state.model,
                                 state.interaction);
  }
  HBITMAP buffer_bitmap = CreateCompatibleBitmap(target, width, height);
  if (buffer_bitmap == nullptr) {
    DeleteDC(buffer_dc);
    return state.renderer.Render(target, static_cast<UINT>(width),
                                 static_cast<UINT>(height),
                                 static_cast<float>(state.dpi), state.model,
                                 state.interaction);
  }
  HGDIOBJ previous = SelectObject(buffer_dc, buffer_bitmap);
  if (previous == nullptr || previous == HGDI_ERROR) {
    DeleteObject(buffer_bitmap);
    DeleteDC(buffer_dc);
    return state.renderer.Render(target, static_cast<UINT>(width),
                                 static_cast<UINT>(height),
                                 static_cast<float>(state.dpi), state.model,
                                 state.interaction);
  }

  HRESULT result = state.renderer.Render(
      buffer_dc, static_cast<UINT>(width), static_cast<UINT>(height),
      static_cast<float>(state.dpi), state.model, state.interaction);
  if (SUCCEEDED(result) &&
      !BitBlt(target, 0, 0, width, height, buffer_dc, 0, 0, SRCCOPY)) {
    result = HRESULT_FROM_WIN32(GetLastError());
  }
  SelectObject(buffer_dc, previous);
  DeleteObject(buffer_bitmap);
  DeleteDC(buffer_dc);
  return result;
}

InteractiveElement HitTest(WindowState &state, HWND window, LPARAM lparam) {
  const float scale = static_cast<float>(state.dpi) / 96.0F;
  RECT client{};
  GetClientRect(window, &client);
  const float width = static_cast<float>(client.right) / scale;
  const float height = static_cast<float>(client.bottom) / scale;
  const float x = static_cast<float>(GET_X_LPARAM(lparam)) / scale;
  const float y = static_cast<float>(GET_Y_LPARAM(lparam)) / scale;
  const auto layout = state.renderer.CalculateLayout(width, height);
  if (state.model.close_enabled() && PointInRect(layout.close, x, y)) {
    return InteractiveElement::close;
  }
  if (state.model.path_editable() && PointInRect(layout.browse, x, y)) {
    return InteractiveElement::browse;
  }
  if (state.model.secondary_visible() &&
      PointInRect(layout.secondary, x, y)) {
    return InteractiveElement::secondary;
  }
  if (state.model.personal_data_choice_visible() &&
      PointInRect(layout.remove_personal_data, x, y)) {
    return InteractiveElement::remove_personal_data;
  }
  if (state.model.phase != InstallerPhase::installing &&
      PointInRect(layout.primary, x, y)) {
    return InteractiveElement::primary;
  }
  if (PointInRect(layout.install_path, x, y)) {
    return state.model.path_editable() ? InteractiveElement::install_path
                                       : InteractiveElement::none;
  }
  return InteractiveElement::none;
}

bool PickFolder(HWND owner, std::wstring *path) {
  IFileOpenDialog *dialog = nullptr;
  HRESULT result =
      CoCreateInstance(CLSID_FileOpenDialog, nullptr, CLSCTX_INPROC_SERVER,
                       IID_PPV_ARGS(&dialog));
  if (FAILED(result))
    return false;
  DWORD options = 0;
  result = dialog->GetOptions(&options);
  if (SUCCEEDED(result)) {
    result =
        dialog->SetOptions(options | FOS_PICKFOLDERS | FOS_FORCEFILESYSTEM |
                           FOS_PATHMUSTEXIST | FOS_NOCHANGEDIR);
  }
  if (SUCCEEDED(result) && !path->empty()) {
    IShellItem *current = nullptr;
    if (SUCCEEDED(SHCreateItemFromParsingName(path->c_str(), nullptr,
                                              IID_PPV_ARGS(&current)))) {
      dialog->SetFolder(current);
      current->Release();
    }
  }
  if (SUCCEEDED(result))
    result = dialog->Show(owner);
  if (SUCCEEDED(result)) {
    IShellItem *item = nullptr;
    result = dialog->GetResult(&item);
    if (SUCCEEDED(result)) {
      PWSTR selected = nullptr;
      result = item->GetDisplayName(SIGDN_FILESYSPATH, &selected);
      if (SUCCEEDED(result) && selected != nullptr) {
        *path = selected;
        CoTaskMemFree(selected);
      }
      item->Release();
    }
  }
  dialog->Release();
  return SUCCEEDED(result);
}

void FocusElement(WindowState &state, HWND window, InteractiveElement element) {
  state.interaction.focused = element;
  state.interaction.caret = state.model.install_path.size();
  state.interaction.selection_anchor = state.interaction.caret;
  state.interaction.caret_visible = element == InteractiveElement::install_path;
  if (element == InteractiveElement::install_path) {
    SetTimer(window, kCaretTimer, 520, nullptr);
  } else {
    KillTimer(window, kCaretTimer);
  }
  InvalidateRect(window, nullptr, FALSE);
}

void AdvanceFocus(WindowState &state, HWND window, bool backwards) {
  if (state.model.phase == InstallerPhase::installing)
    return;
  std::vector<InteractiveElement> order;
  if (state.model.path_editable()) {
    order = {InteractiveElement::install_path, InteractiveElement::browse,
             InteractiveElement::primary, InteractiveElement::close};
  } else {
    if (state.model.personal_data_choice_visible())
      order.push_back(InteractiveElement::remove_personal_data);
    if (state.model.secondary_visible())
      order.push_back(InteractiveElement::secondary);
    order.push_back(InteractiveElement::primary);
    order.push_back(InteractiveElement::close);
  }
  auto iterator =
      std::find(order.begin(), order.end(), state.interaction.focused);
  int index = iterator == order.end()
                  ? 0
                  : static_cast<int>(std::distance(order.begin(), iterator));
  index = (index + (backwards ? -1 : 1) + static_cast<int>(order.size())) %
          static_cast<int>(order.size());
  FocusElement(state, window, order[static_cast<std::size_t>(index)]);
}

void StartInstallation(WindowState &state, HWND window) {
  if (state.model.phase == InstallerPhase::installing)
    return;

  std::wstring install_root = state.model.install_path;
  if (state.model.state == PreviewState::fresh) {
    const InstallPathValidation validation =
        ValidateFreshInstallPath(install_root);
    if (!validation.valid) {
      state.model.phase = InstallerPhase::ready;
      state.model.message = validation.error;
      InvalidateRect(window, nullptr, FALSE);
      return;
    }
    install_root = validation.normalized_path;
  } else {
    InstalledBeta installed;
    std::wstring error;
    if (!VerifyInstalledBetaRoot(install_root, &installed, &error)) {
      state.model.phase = InstallerPhase::blocked;
      state.model.message = L"The existing installation could not be "
                            L"verified. Nothing was changed.";
      InvalidateRect(window, nullptr, FALSE);
      return;
    }
    const int comparison =
        CompareSemanticVersions(installed.version, state.model.version);
    if (comparison > 0) {
      state.model.phase = InstallerPhase::blocked;
      state.model.message = L"A newer version is already installed. This "
                            L"installer will not downgrade it.";
      InvalidateRect(window, nullptr, FALSE);
      return;
    }
    state.model.installed_version = installed.version;
    state.model.state =
        comparison == 0 ? PreviewState::repair : PreviewState::update;
    install_root = installed.root;
  }

  std::wstring payload_error;
  if (!VerifyEmbeddedPayload(&payload_error)) {
    state.model.phase = InstallerPhase::blocked;
    state.model.message = payload_error;
    InvalidateRect(window, nullptr, FALSE);
    return;
  }

  if (state.install_worker.joinable())
    state.install_worker.join();
  state.model.install_path = install_root;
  state.model.message.clear();
  state.model.retained_log.clear();
  state.model.phase = InstallerPhase::installing;
  state.interaction.focused = InteractiveElement::none;
  state.interaction.hovered = InteractiveElement::none;
  state.interaction.animation_phase = 0.0F;
  KillTimer(window, kCaretTimer);
  SetTimer(window, kActivityTimer, 32, nullptr);
  InvalidateRect(window, nullptr, FALSE);

  const bool fresh_install = state.model.state == PreviewState::fresh;

  try {
    state.install_worker = std::thread([window, install_root, fresh_install]() {
      InstallEngineResult outcome;
      try {
        outcome = RunInstallEngine(
            install_root, fresh_install,
            [window](const std::wstring &message,
                     const std::wstring &retained_log) {
              auto *notice = new (std::nothrow)
                  InstallProgressNotice{message, retained_log};
              if (notice != nullptr &&
                  !PostMessageW(window, kInstallProgressMessage, 0,
                                reinterpret_cast<LPARAM>(notice))) {
                delete notice;
              }
            });
      } catch (...) {
        outcome.error =
            L"Installation stopped unexpectedly. Personal data is stored "
            L"separately and was not changed.";
      }
      auto *result = new (std::nothrow) InstallEngineResult(std::move(outcome));
      if (result == nullptr) {
        PostMessageW(window, kInstallFinishedMessage, 0, 0);
        return;
      }
      if (!PostMessageW(window, kInstallFinishedMessage, 0,
                        reinterpret_cast<LPARAM>(result))) {
        delete result;
      }
    });
  } catch (...) {
    KillTimer(window, kActivityTimer);
    state.model.phase = InstallerPhase::failed;
    state.model.message =
        L"The installer could not start its installation task.";
    InvalidateRect(window, nullptr, FALSE);
  }
}

void RestoreMaintenanceScreen(WindowState &state, HWND window) {
  if (state.model.intent == InstallerIntent::uninstall &&
      state.model.remove_personal_data &&
      !state.model.personal_data_cleanup_pending) {
    PersonalDataRemovalPlan pending;
    const PersonalDataRemovalResult detected =
        DetectPendingPersonalDataRemoval(&pending);
    if (detected.status == PersonalDataRemovalStatus::invalid) {
      state.model.phase = InstallerPhase::blocked;
      state.model.message =
          detected.message.empty()
              ? L"The pending planner-data cleanup record could not be "
                L"verified. Nothing was removed."
              : detected.message;
      InvalidateRect(window, nullptr, FALSE);
      return;
    }
    if (detected.status == PersonalDataRemovalStatus::prepared) {
      const PersonalDataRemovalResult cancelled =
          CancelPreparedPersonalDataRemoval(pending);
      if (!cancelled.success) {
        state.model.phase = InstallerPhase::blocked;
        state.model.message =
            cancelled.message.empty()
                ? L"The pending removal request could not be cancelled "
                  L"safely. No planner data was removed."
                : cancelled.message;
        InvalidateRect(window, nullptr, FALSE);
        return;
      }
    }
  }
  state.model.intent = InstallerIntent::maintain;
  state.model.remove_personal_data = false;
  state.model.personal_data_cleanup_pending = false;
  state.model.message.clear();
  state.model.retained_log.clear();
  const int comparison = CompareSemanticVersions(state.model.installed_version,
                                                 state.model.version);
  if (comparison > 0) {
    state.model.state = PreviewState::repair;
    state.model.phase = InstallerPhase::blocked;
    state.model.message = L"A newer version is already installed. This installer "
                          L"will not downgrade it.";
  } else {
    state.model.state =
        comparison == 0 ? PreviewState::repair : PreviewState::update;
    state.model.phase = InstallerPhase::ready;
  }
  FocusElement(state, window, InteractiveElement::primary);
}

void OpenUninstallConfirmation(WindowState &state, HWND window) {
  if (state.model.state == PreviewState::fresh ||
      state.model.phase == InstallerPhase::installing ||
      state.model.phase == InstallerPhase::succeeded) {
    return;
  }
  state.model.intent = InstallerIntent::uninstall;
  state.model.remove_personal_data = false;
  state.model.personal_data_cleanup_pending = false;
  state.model.phase = InstallerPhase::ready;
  state.model.message.clear();
  state.model.retained_log.clear();
  FocusElement(state, window, InteractiveElement::secondary);
}

void StartUninstallation(WindowState &state, HWND window) {
  if (state.model.intent != InstallerIntent::uninstall ||
      (state.model.state == PreviewState::fresh &&
       !state.model.personal_data_cleanup_pending) ||
      state.model.phase == InstallerPhase::installing) {
    return;
  }
  const bool cleanup_only = state.model.personal_data_cleanup_pending;
  InstalledBeta installed;
  std::wstring error;
  if (!cleanup_only &&
      !VerifyInstalledBetaRoot(state.model.install_path, &installed, &error)) {
    state.model.phase = InstallerPhase::blocked;
    state.model.message = L"The existing installation could not be "
                          L"verified. Nothing was changed.";
    InvalidateRect(window, nullptr, FALSE);
    return;
  }
  if (state.install_worker.joinable())
    state.install_worker.join();
  if (!cleanup_only) {
    state.model.install_path = installed.root;
    state.model.installed_version = installed.version;
  }
  state.model.message.clear();
  state.model.retained_log.clear();
  state.model.phase = InstallerPhase::installing;
  state.interaction.focused = InteractiveElement::none;
  state.interaction.hovered = InteractiveElement::none;
  state.interaction.animation_phase = 0.0F;
  KillTimer(window, kCaretTimer);
  SetTimer(window, kActivityTimer, 32, nullptr);
  InvalidateRect(window, nullptr, FALSE);

  const std::wstring install_root = cleanup_only ? L"" : installed.root;
  const bool remove_personal_data = state.model.remove_personal_data;
  try {
    state.install_worker = std::thread(
        [window, install_root, remove_personal_data, cleanup_only]() {
      InstallEngineResult outcome;
      try {
        const auto progress =
            [window](const std::wstring &message,
                     const std::wstring &retained_log) {
              auto *notice = new (std::nothrow)
                  InstallProgressNotice{message, retained_log};
              if (notice != nullptr &&
                  !PostMessageW(window, kInstallProgressMessage, 0,
                                reinterpret_cast<LPARAM>(notice))) {
                delete notice;
              }
            };
        outcome = cleanup_only
                      ? RunPendingPersonalDataCleanup(progress)
                      : RunUninstallEngine(install_root,
                                           remove_personal_data, progress);
      } catch (...) {
        outcome.personal_data_requested = remove_personal_data || cleanup_only;
        outcome.personal_data_cleanup_pending = cleanup_only;
        outcome.error =
            cleanup_only
                ? L"Planner-data cleanup stopped unexpectedly. The verified "
                  L"data was retained for a safe retry."
                : L"Uninstall stopped unexpectedly. If planner-data removal "
                  L"was requested, it will only continue after the "
                  L"application uninstall is confirmed.";
      }
      auto *result = new (std::nothrow) InstallEngineResult(std::move(outcome));
      if (result == nullptr) {
        PostMessageW(window, kInstallFinishedMessage, 0, 0);
        return;
      }
      if (!PostMessageW(window, kInstallFinishedMessage, 0,
                        reinterpret_cast<LPARAM>(result))) {
        delete result;
      }
    });
  } catch (...) {
    KillTimer(window, kActivityTimer);
    state.model.phase = InstallerPhase::failed;
    state.model.message = L"The installer could not start its uninstall task.";
    InvalidateRect(window, nullptr, FALSE);
  }
}

bool OpenInstalledApplication(WindowState &state, HWND window) {
  InstalledBeta installed;
  std::wstring verification_error;
  if (!VerifyInstalledBetaRoot(state.model.install_path, &installed,
                               &verification_error) ||
      CompareSemanticVersions(installed.version, state.model.version) != 0) {
    state.model.message =
        L"Installation is complete, but the installed application could not "
        L"be verified before it was opened.";
    InvalidateRect(window, nullptr, FALSE);
    return false;
  }

  const std::filesystem::path current_directory =
      std::filesystem::path(installed.root) / L"current";
  const std::filesystem::path executable =
      current_directory / L"BlackSpiritLife.exe";
  STARTUPINFOW startup{sizeof(STARTUPINFOW)};
  PROCESS_INFORMATION process{};
  const BOOL launched = CreateProcessW(
      executable.c_str(), nullptr, nullptr, nullptr, FALSE,
      CREATE_UNICODE_ENVIRONMENT, nullptr, current_directory.c_str(), &startup,
      &process);
  if (launched) {
    CloseHandle(process.hThread);
    CloseHandle(process.hProcess);
    DestroyWindow(window);
    return true;
  }
  state.model.message = L"Installation is complete, but Windows could not open "
                        L"the planner automatically.";
  InvalidateRect(window, nullptr, FALSE);
  return false;
}

void Activate(WindowState &state, HWND window, InteractiveElement element) {
  switch (element) {
  case InteractiveElement::close:
    PostMessageW(window, WM_CLOSE, 0, 0);
    return;
  case InteractiveElement::browse:
    if (PickFolder(window, &state.model.install_path)) {
      state.model.phase = InstallerPhase::ready;
      state.model.message.clear();
      state.interaction.caret = state.model.install_path.size();
      state.interaction.selection_anchor = state.interaction.caret;
      InvalidateRect(window, nullptr, FALSE);
    }
    return;
  case InteractiveElement::remove_personal_data:
    if (state.model.personal_data_choice_visible()) {
      state.model.remove_personal_data = !state.model.remove_personal_data;
      InvalidateRect(window, nullptr, FALSE);
    }
    return;
  case InteractiveElement::secondary:
    if (state.model.intent == InstallerIntent::uninstall) {
      RestoreMaintenanceScreen(state, window);
    } else {
      OpenUninstallConfirmation(state, window);
    }
    return;
  case InteractiveElement::primary:
    if (state.model.phase == InstallerPhase::blocked) {
      PostMessageW(window, WM_CLOSE, 0, 0);
    } else if (state.model.phase == InstallerPhase::succeeded) {
      if (state.model.intent == InstallerIntent::uninstall) {
        PostMessageW(window, WM_CLOSE, 0, 0);
      } else {
        (void)OpenInstalledApplication(state, window);
      }
    } else if (state.model.intent == InstallerIntent::uninstall) {
      StartUninstallation(state, window);
    } else {
      StartInstallation(state, window);
    }
    return;
  case InteractiveElement::install_path:
    FocusElement(state, window, element);
    return;
  case InteractiveElement::none:
    return;
  }
}

LRESULT CALLBACK WindowProcedure(HWND window, UINT message, WPARAM wparam,
                                 LPARAM lparam) {
  auto *state =
      reinterpret_cast<WindowState *>(GetWindowLongPtrW(window, GWLP_USERDATA));
  if (message == WM_NCCREATE) {
    auto *create = reinterpret_cast<CREATESTRUCTW *>(lparam);
    state = static_cast<WindowState *>(create->lpCreateParams);
    SetWindowLongPtrW(window, GWLP_USERDATA, reinterpret_cast<LONG_PTR>(state));
  }
  if (state == nullptr) {
    return DefWindowProcW(window, message, wparam, lparam);
  }
  switch (message) {
  case kInstallProgressMessage: {
    std::unique_ptr<InstallProgressNotice> notice(
        reinterpret_cast<InstallProgressNotice *>(lparam));
    if (notice && state->model.phase == InstallerPhase::installing) {
      state->model.message = notice->message;
      state->model.retained_log = notice->retained_log;
      InvalidateRect(window, nullptr, FALSE);
    }
    return 0;
  }
  case kInstallFinishedMessage: {
    std::unique_ptr<InstallEngineResult> result(
        reinterpret_cast<InstallEngineResult *>(lparam));
    KillTimer(window, kActivityTimer);
    if (state->install_worker.joinable())
      state->install_worker.join();
    const bool uninstalling =
        state->model.intent == InstallerIntent::uninstall;
    const bool matching_success =
        result && result->success && result->uninstalled == uninstalling;
    if (matching_success) {
      state->model.phase = InstallerPhase::succeeded;
      state->model.install_path = result->installed_root;
      state->model.installed_version = result->installed_version;
      state->model.message.clear();
      state->model.personal_data_cleanup_pending = false;
      if (!uninstalling && OpenInstalledApplication(*state, window)) {
        return 0;
      }
    } else {
      state->model.phase = InstallerPhase::failed;
      state->model.personal_data_cleanup_pending =
          result && result->personal_data_cleanup_pending;
      if (result && result->personal_data_requested) {
        state->model.remove_personal_data = true;
      }
      state->model.message =
          result && !result->error.empty()
              ? result->error
              : uninstalling
                    ? L"Uninstall did not finish. Planner settings were not "
                      L"changed by this installer."
                    : L"Installation did not finish.";
      state->model.retained_log = result ? result->retained_log : L"";
      if (!state->model.retained_log.empty()) {
        state->model.message +=
            L" Diagnostic log: " + state->model.retained_log;
      }
    }
    state->interaction.animation_phase = 0.0F;
    FocusElement(*state, window, InteractiveElement::primary);
    InvalidateRect(window, nullptr, FALSE);
    return 0;
  }
  case WM_CLOSE:
    if (state->model.phase == InstallerPhase::installing)
      return 0;
    DestroyWindow(window);
    return 0;
  case WM_ERASEBKGND:
    return 1;
  case WM_DPICHANGED: {
    const auto *suggested = reinterpret_cast<RECT *>(lparam);
    const RECT work_area = MonitorWorkAreaForRect(*suggested);
    const FittedWindowMetrics metrics =
        FitWindowToWorkArea(HIWORD(wparam), work_area);
    state->dpi = metrics.render_dpi;
    const POINT origin = CenteredWindowOrigin(work_area, metrics);
    SetWindowPos(window, nullptr, origin.x, origin.y, metrics.width,
                 metrics.height, SWP_NOACTIVATE | SWP_NOZORDER);
    return 0;
  }
  case WM_PAINT: {
    PAINTSTRUCT paint{};
    HDC dc = BeginPaint(window, &paint);
    RECT client{};
    GetClientRect(window, &client);
    const HRESULT render_result =
        RenderBufferedInstaller(*state, dc, client);
    (void)render_result;
    EndPaint(window, &paint);
    return 0;
  }
  case WM_MOUSEMOVE: {
    const auto hovered = HitTest(*state, window, lparam);
    if (hovered != state->interaction.hovered) {
      state->interaction.hovered = hovered;
      InvalidateRect(window, nullptr, FALSE);
    }
    if (!state->tracking_mouse) {
      TRACKMOUSEEVENT tracking{sizeof(TRACKMOUSEEVENT), TME_LEAVE, window, 0};
      TrackMouseEvent(&tracking);
      state->tracking_mouse = true;
    }
    return 0;
  }
  case WM_MOUSELEAVE:
    state->tracking_mouse = false;
    state->interaction.hovered = InteractiveElement::none;
    InvalidateRect(window, nullptr, FALSE);
    return 0;
  case WM_LBUTTONDOWN: {
    const auto element = HitTest(*state, window, lparam);
    if (element == InteractiveElement::none) {
      RECT client{};
      GetClientRect(window, &client);
      const float scale = static_cast<float>(state->dpi) / 96.0F;
      const auto layout = state->renderer.CalculateLayout(
          static_cast<float>(client.right) / scale,
          static_cast<float>(client.bottom) / scale);
      const float x = static_cast<float>(GET_X_LPARAM(lparam)) / scale;
      const float y = static_cast<float>(GET_Y_LPARAM(lparam)) / scale;
      if (PointInRect(layout.title_drag, x, y)) {
        ReleaseCapture();
        SendMessageW(window, WM_NCLBUTTONDOWN, HTCAPTION, 0);
        return 0;
      }
    }
    SetFocus(window);
    FocusElement(*state, window, element);
    return 0;
  }
  case WM_LBUTTONUP:
    Activate(*state, window, HitTest(*state, window, lparam));
    return 0;
  case WM_TIMER:
    if (wparam == kCaretTimer) {
      state->interaction.caret_visible = !state->interaction.caret_visible;
      InvalidateRect(window, nullptr, FALSE);
      return 0;
    }
    if (wparam == kActivityTimer &&
        state->model.phase == InstallerPhase::installing) {
      state->interaction.animation_phase =
          std::fmod(state->interaction.animation_phase + 0.0125F, 1.0F);
      InvalidateRect(window, nullptr, FALSE);
      return 0;
    }
    break;
  case WM_CHAR:
    if (state->interaction.focused == InteractiveElement::install_path &&
        state->model.path_editable()) {
      state->model.phase = InstallerPhase::ready;
      state->model.message.clear();
      if (wparam == VK_BACK) {
        if (state->interaction.caret > 0 &&
            state->interaction.caret <= state->model.install_path.size()) {
          state->model.install_path.erase(state->interaction.caret - 1, 1);
          --state->interaction.caret;
        }
      } else if (wparam >= 0x20 && wparam != 0x7F) {
        state->interaction.caret = std::min(state->interaction.caret,
                                            state->model.install_path.size());
        state->model.install_path.insert(state->interaction.caret, 1,
                                         static_cast<wchar_t>(wparam));
        ++state->interaction.caret;
      }
      state->interaction.selection_anchor = state->interaction.caret;
      state->interaction.caret_visible = true;
      InvalidateRect(window, nullptr, FALSE);
      return 0;
    }
    break;
  case WM_KEYDOWN:
    if (wparam == VK_TAB) {
      AdvanceFocus(*state, window, (GetKeyState(VK_SHIFT) & 0x8000) != 0);
      return 0;
    }
    if (wparam == VK_ESCAPE) {
      if (state->model.intent == InstallerIntent::uninstall &&
          !state->model.personal_data_cleanup_pending &&
          state->model.phase != InstallerPhase::installing &&
          state->model.phase != InstallerPhase::succeeded) {
        RestoreMaintenanceScreen(*state, window);
      } else {
        PostMessageW(window, WM_CLOSE, 0, 0);
      }
      return 0;
    }
    if (state->interaction.focused == InteractiveElement::install_path &&
        state->model.path_editable()) {
      if (wparam == VK_LEFT && state->interaction.caret > 0) {
        --state->interaction.caret;
      } else if (wparam == VK_RIGHT &&
                 state->interaction.caret < state->model.install_path.size()) {
        ++state->interaction.caret;
      } else if (wparam == VK_HOME) {
        state->interaction.caret = 0;
      } else if (wparam == VK_END) {
        state->interaction.caret = state->model.install_path.size();
      } else if (wparam == VK_DELETE &&
                 state->interaction.caret < state->model.install_path.size()) {
        state->model.install_path.erase(state->interaction.caret, 1);
        state->model.phase = InstallerPhase::ready;
        state->model.message.clear();
      } else if (wparam == L'V' && (GetKeyState(VK_CONTROL) & 0x8000) != 0 &&
                 OpenClipboard(window)) {
        HANDLE clipboard = GetClipboardData(CF_UNICODETEXT);
        if (clipboard != nullptr) {
          const auto *text =
              static_cast<const wchar_t *>(GlobalLock(clipboard));
          if (text != nullptr) {
            const std::wstring pasted(text);
            state->model.install_path.insert(state->interaction.caret, pasted);
            state->interaction.caret += pasted.size();
            GlobalUnlock(clipboard);
            state->model.phase = InstallerPhase::ready;
            state->model.message.clear();
          }
        }
        CloseClipboard();
      } else if (wparam == VK_RETURN) {
        Activate(*state, window, InteractiveElement::primary);
        return 0;
      } else {
        break;
      }
      state->interaction.selection_anchor = state->interaction.caret;
      state->interaction.caret_visible = true;
      InvalidateRect(window, nullptr, FALSE);
      return 0;
    }
    if (wparam == VK_RETURN || wparam == VK_SPACE) {
      Activate(*state, window, state->interaction.focused);
      return 0;
    }
    break;
  case WM_DESTROY:
    KillTimer(window, kCaretTimer);
    KillTimer(window, kActivityTimer);
    PostQuitMessage(0);
    return 0;
  default:
    break;
  }
  return DefWindowProcW(window, message, wparam, lparam);
}

PreviewState ParsePreviewState(const std::wstring &value) {
  if (value == L"update")
    return PreviewState::update;
  if (value == L"repair")
    return PreviewState::repair;
  return PreviewState::fresh;
}

InstallerPhase ParsePreviewPhase(const std::wstring &value) {
  if (value == L"installing")
    return InstallerPhase::installing;
  if (value == L"succeeded")
    return InstallerPhase::succeeded;
  if (value == L"failed")
    return InstallerPhase::failed;
  if (value == L"blocked")
    return InstallerPhase::blocked;
  return InstallerPhase::ready;
}

InstallerIntent ParsePreviewIntent(const std::wstring &value) {
  return value == L"uninstall" ? InstallerIntent::uninstall
                                : InstallerIntent::maintain;
}

void ConfigureBuildIdentity(InstallerModel &model) {
  model.version = std::wstring(build_config::kVersion);
  model.package_id = std::wstring(build_config::kPackageId);
  model.channel = std::wstring(build_config::kChannel);
}

void ConfigureActualInstallation(InstallerModel &model) {
  model.phase = InstallerPhase::ready;
  model.message.clear();
  model.retained_log.clear();
  model.install_path = DefaultInstallPath();

  PersonalDataRemovalPlan pending_removal;
  const PersonalDataRemovalResult pending =
      DetectPendingPersonalDataRemoval(&pending_removal);
  if (pending.status == PersonalDataRemovalStatus::invalid) {
    model.state = PreviewState::fresh;
    model.phase = InstallerPhase::blocked;
    model.message = pending.message.empty()
                        ? L"A pending planner-data cleanup record could not "
                          L"be verified. No files were changed."
                        : pending.message;
    return;
  }

  const InstalledBetaLookup lookup = LocateInstalledBeta();
  if (!lookup.error.empty()) {
    model.phase = InstallerPhase::blocked;
    model.message = lookup.error;
    return;
  }
  if (!lookup.installation) {
    model.state = PreviewState::fresh;
    if (pending.status == PersonalDataRemovalStatus::prepared ||
        pending.status == PersonalDataRemovalStatus::application_removed ||
        pending.status == PersonalDataRemovalStatus::cleanup_pending ||
        pending.status == PersonalDataRemovalStatus::complete) {
      model.intent = InstallerIntent::uninstall;
      model.remove_personal_data = true;
      model.personal_data_cleanup_pending = true;
      model.phase = InstallerPhase::failed;
      model.message = pending.message.empty()
                          ? L"The application is gone, but its requested "
                            L"planner-data cleanup still needs to finish."
                          : pending.message;
    }
    return;
  }

  model.install_path = lookup.installation->root;
  model.installed_version = lookup.installation->version;
  const int comparison =
      CompareSemanticVersions(model.installed_version, model.version);
  if (comparison > 0) {
    model.state = PreviewState::repair;
    model.phase = InstallerPhase::blocked;
    model.message = L"A newer version is already installed. This installer will "
                    L"not downgrade it.";
  } else {
    model.state = comparison == 0 ? PreviewState::repair : PreviewState::update;
  }
  if (pending.status == PersonalDataRemovalStatus::prepared) {
    model.intent = InstallerIntent::uninstall;
    model.remove_personal_data = true;
    model.phase = InstallerPhase::failed;
    model.message = pending.message.empty()
                        ? L"A previous data-removing uninstall stopped before "
                          L"the application was removed. Try again or go Back "
                          L"to keep your planner data."
                        : pending.message;
  }
}

} // namespace
} // namespace bsl::installer

int WINAPI wWinMain(HINSTANCE instance, HINSTANCE, PWSTR, int show_command) {
  using namespace bsl::installer;
  SetProcessDpiAwarenessContext(DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2);
  const HRESULT com_result = CoInitializeEx(
      nullptr, COINIT_APARTMENTTHREADED | COINIT_DISABLE_OLE1DDE);

  WindowState state(instance);
  ConfigureBuildIdentity(state.model);
  state.model.install_path = DefaultInstallPath();

  std::wstring capture_path;
  std::wstring validation_path;
  bool verify_payload = false;
  float preview_height = kPreviewHeight;
  int argument_count = 0;
  PWSTR *arguments = CommandLineToArgvW(GetCommandLineW(), &argument_count);
  for (int index = 1; arguments != nullptr && index < argument_count; ++index) {
    const std::wstring argument = arguments[index];
    if (argument == L"--capture-preview" && index + 1 < argument_count) {
      capture_path = arguments[++index];
    } else if (argument == L"--preview-state" && index + 1 < argument_count) {
      state.model.state = ParsePreviewState(arguments[++index]);
      if (state.model.state != PreviewState::fresh &&
          state.model.installed_version.empty()) {
        state.model.installed_version = L"0.0.9";
      }
    } else if (argument == L"--preview-phase" && index + 1 < argument_count) {
      state.model.phase = ParsePreviewPhase(arguments[++index]);
    } else if (argument == L"--preview-intent" &&
               index + 1 < argument_count) {
      state.model.intent = ParsePreviewIntent(arguments[++index]);
    } else if (argument == L"--preview-remove-personal-data") {
      state.model.remove_personal_data = true;
    } else if (argument == L"--install-path" && index + 1 < argument_count) {
      state.model.install_path = arguments[++index];
    } else if (argument == L"--installed-version" &&
               index + 1 < argument_count) {
      state.model.installed_version = arguments[++index];
    } else if (argument == L"--verify-payload") {
      verify_payload = true;
    } else if (argument == L"--preview-height" && index + 1 < argument_count) {
      preview_height = static_cast<float>(_wtoi(arguments[++index]));
    } else if (argument == L"--validate-install-path" &&
               index + 1 < argument_count) {
      validation_path = arguments[++index];
    }
  }
  if (arguments != nullptr)
    LocalFree(arguments);

  if (verify_payload) {
    std::wstring error;
    const bool valid = VerifyEmbeddedPayload(&error);
    if (SUCCEEDED(com_result))
      CoUninitialize();
    return valid ? 0 : 6;
  }
  if (!validation_path.empty()) {
    const bool valid = ValidateFreshInstallPath(validation_path).valid;
    if (SUCCEEDED(com_result))
      CoUninitialize();
    return valid ? 0 : 7;
  }

  if (!state.renderer.IsReady()) {
    if (SUCCEEDED(com_result))
      CoUninitialize();
    return 2;
  }
  if (!capture_path.empty()) {
    const HRESULT capture = state.renderer.CapturePreviewPng(
        capture_path, state.model, {}, kPreviewWidth, preview_height);
    if (SUCCEEDED(com_result))
      CoUninitialize();
    return SUCCEEDED(capture) ? 0 : 3;
  }

  ConfigureActualInstallation(state.model);

  WNDCLASSEXW window_class{sizeof(WNDCLASSEXW)};
  window_class.style = CS_HREDRAW | CS_VREDRAW | CS_DROPSHADOW;
  window_class.lpfnWndProc = WindowProcedure;
  window_class.hInstance = instance;
  window_class.hIcon =
      LoadIconW(instance, MAKEINTRESOURCEW(IDI_BLACK_SPIRIT_LIFE));
  window_class.hIconSm = window_class.hIcon;
  window_class.hCursor = LoadCursorW(nullptr, IDC_ARROW);
  window_class.lpszClassName = kWindowClass;
  if (RegisterClassExW(&window_class) == 0) {
    if (SUCCEEDED(com_result))
      CoUninitialize();
    return 4;
  }

  const RECT primary_reference{0, 0, GetSystemMetrics(SM_CXSCREEN),
                               GetSystemMetrics(SM_CYSCREEN)};
  const RECT primary_work_area = MonitorWorkAreaForRect(primary_reference);
  const FittedWindowMetrics initial_metrics =
      FitWindowToWorkArea(GetDpiForSystem(), primary_work_area);
  state.dpi = initial_metrics.render_dpi;
  const POINT initial_origin =
      CenteredWindowOrigin(primary_work_area, initial_metrics);
  HWND window = CreateWindowExW(
      WS_EX_APPWINDOW, kWindowClass, L"Black Spirit Life Setup",
      WS_POPUP | WS_SYSMENU | WS_MINIMIZEBOX, initial_origin.x,
      initial_origin.y, initial_metrics.width, initial_metrics.height, nullptr,
      nullptr, instance, &state);
  if (window == nullptr) {
    if (SUCCEEDED(com_result))
      CoUninitialize();
    return 5;
  }
  MARGINS margins{1, 1, 1, 1};
  DwmExtendFrameIntoClientArea(window, &margins);
  ShowWindow(window, show_command);
  UpdateWindow(window);
  FocusElement(state, window,
               state.model.personal_data_cleanup_pending
                   ? InteractiveElement::primary
               : state.model.intent == InstallerIntent::uninstall
                   ? InteractiveElement::secondary
               : state.model.path_editable()
                   ? InteractiveElement::install_path
                   : InteractiveElement::primary);

  MSG message{};
  int exit_code = 0;
  while (GetMessageW(&message, nullptr, 0, 0) > 0) {
    TranslateMessage(&message);
    DispatchMessageW(&message);
  }
  exit_code = static_cast<int>(message.wParam);
  if (state.install_worker.joinable())
    state.install_worker.join();
  if (SUCCEEDED(com_result))
    CoUninitialize();
  return exit_code;
}
