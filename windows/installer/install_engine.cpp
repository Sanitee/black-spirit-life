#include "install_engine.h"

#include <windows.h>
#include <winver.h>

#include <shlobj.h>

#include <algorithm>
#include <cwchar>
#include <filesystem>
#include <optional>
#include <string>
#include <vector>

#include "beta_maintenance_gate.h"
#include "embedded_payload.h"
#include "install_path_policy.h"
#include "install_process_guard.h"
#include "installed_beta_locator.h"
#include "installer_build_config.h"
#include "personal_data_removal.h"

namespace bsl::installer {
namespace {

class InstallRootLease final {
public:
  InstallRootLease() = default;
  ~InstallRootLease() {
    if (handle_ != INVALID_HANDLE_VALUE)
      CloseHandle(handle_);
  }
  InstallRootLease(const InstallRootLease &) = delete;
  InstallRootLease &operator=(const InstallRootLease &) = delete;

  [[nodiscard]] bool AcquireFresh(const std::wstring &root,
                                  std::wstring *error) {
    const InstallPathValidation before = ValidateFreshInstallPath(root);
    if (!before.valid) {
      if (error)
        *error = before.error;
      return false;
    }
    const int created = SHCreateDirectoryExW(nullptr, root.c_str(), nullptr);
    if (created != ERROR_SUCCESS && created != ERROR_ALREADY_EXISTS &&
        created != ERROR_FILE_EXISTS) {
      if (error)
        *error = L"The selected installation folder could not be prepared.";
      return false;
    }
    const InstallPathValidation after = ValidateFreshInstallPath(root);
    if (!after.valid) {
      if (error)
        *error = after.error;
      return false;
    }

    handle_ = CreateFileW(
        root.c_str(), FILE_READ_ATTRIBUTES, FILE_SHARE_READ | FILE_SHARE_WRITE,
        nullptr, OPEN_EXISTING,
        FILE_FLAG_BACKUP_SEMANTICS | FILE_FLAG_OPEN_REPARSE_POINT, nullptr);
    if (handle_ == INVALID_HANDLE_VALUE) {
      if (error)
        *error =
            L"The installation folder could not be locked for a safe update.";
      return false;
    }
    BY_HANDLE_FILE_INFORMATION information{};
    if (!GetFileInformationByHandle(handle_, &information) ||
        (information.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY) == 0 ||
        (information.dwFileAttributes & FILE_ATTRIBUTE_REPARSE_POINT) != 0) {
      if (error)
        *error = L"The installation folder is not a regular local directory.";
      CloseHandle(handle_);
      handle_ = INVALID_HANDLE_VALUE;
      return false;
    }
    return true;
  }

private:
  HANDLE handle_ = INVALID_HANDLE_VALUE;
};

std::wstring QuoteArgument(const std::wstring &value) {
  std::wstring result = L"\"";
  unsigned backslashes = 0;
  for (wchar_t character : value) {
    if (character == L'\\') {
      ++backslashes;
      continue;
    }
    if (character == L'\"') {
      result.append(backslashes * 2 + 1, L'\\');
      result.push_back(L'\"');
      backslashes = 0;
      continue;
    }
    result.append(backslashes, L'\\');
    backslashes = 0;
    result.push_back(character);
  }
  result.append(backslashes * 2, L'\\');
  result.push_back(L'\"');
  return result;
}

std::wstring FinalPathForHandle(HANDLE handle) {
  constexpr DWORD flags = FILE_NAME_NORMALIZED | VOLUME_NAME_NT;
  const DWORD required = GetFinalPathNameByHandleW(handle, nullptr, 0, flags);
  if (required == 0)
    return {};
  std::wstring result(required, L'\0');
  const DWORD written =
      GetFinalPathNameByHandleW(handle, result.data(), required, flags);
  if (written == 0 || written >= required)
    return {};
  result.resize(written);
  while (result.size() > 1 &&
         (result.back() == L'\\' || result.back() == L'/')) {
    result.pop_back();
  }
  return result;
}

bool SameOrChildPhysicalPath(const std::wstring &candidate,
                             const std::wstring &root) {
  if (candidate.size() < root.size() ||
      _wcsnicmp(candidate.c_str(), root.c_str(), root.size()) != 0) {
    return false;
  }
  return candidate.size() == root.size() ||
         candidate[root.size()] == L'\\' || candidate[root.size()] == L'/';
}

std::wstring CurrentModulePath() {
  std::wstring path(32768, L'\0');
  const DWORD written = GetModuleFileNameW(
      nullptr, path.data(), static_cast<DWORD>(path.size()));
  if (written == 0 || written >= path.size())
    return {};
  path.resize(written);
  return path;
}

bool DirectoryFinalPath(const std::wstring &path, std::wstring *final_path) {
  HANDLE handle = CreateFileW(
      path.c_str(), FILE_READ_ATTRIBUTES,
      FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE, nullptr,
      OPEN_EXISTING, FILE_FLAG_BACKUP_SEMANTICS | FILE_FLAG_OPEN_REPARSE_POINT,
      nullptr);
  if (handle == INVALID_HANDLE_VALUE)
    return false;
  BY_HANDLE_FILE_INFORMATION information{};
  const bool ordinary =
      GetFileInformationByHandle(handle, &information) &&
      (information.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY) != 0 &&
      (information.dwFileAttributes & FILE_ATTRIBUTE_REPARSE_POINT) == 0;
  std::wstring resolved = ordinary ? FinalPathForHandle(handle) : L"";
  CloseHandle(handle);
  if (!ordinary || resolved.empty())
    return false;
  if (final_path)
    *final_path = std::move(resolved);
  return true;
}

bool VerifyVelopackUpdaterVersion(const std::wstring &path,
                                  std::wstring *error) {
  if (error)
    error->clear();
  DWORD ignored = 0;
  const DWORD size = GetFileVersionInfoSizeW(path.c_str(), &ignored);
  if (size == 0 || size > 16 * 1024 * 1024) {
    if (error)
      *error = L"The installed update engine has no trusted version data.";
    return false;
  }
  std::vector<BYTE> data(size);
  if (!GetFileVersionInfoW(path.c_str(), 0, size, data.data())) {
    if (error)
      *error = L"The installed update engine version could not be read.";
    return false;
  }
  VS_FIXEDFILEINFO *fixed = nullptr;
  UINT fixed_size = 0;
  if (!VerQueryValueW(data.data(), L"\\", reinterpret_cast<void **>(&fixed),
                      &fixed_size) ||
      fixed == nullptr || fixed_size < sizeof(VS_FIXEDFILEINFO) ||
      fixed->dwSignature != 0xFEEF04BD ||
      HIWORD(fixed->dwFileVersionMS) != 1 ||
      LOWORD(fixed->dwFileVersionMS) != 2 ||
      HIWORD(fixed->dwFileVersionLS) != 0 ||
      LOWORD(fixed->dwFileVersionLS) != 0 ||
      HIWORD(fixed->dwProductVersionMS) != 1 ||
      LOWORD(fixed->dwProductVersionMS) != 2 ||
      HIWORD(fixed->dwProductVersionLS) != 0 ||
      LOWORD(fixed->dwProductVersionLS) != 0) {
    if (error)
      *error = L"The installed update engine is not the expected Velopack "
               L"1.2.0 engine.";
    return false;
  }

  struct Translation {
    WORD language;
    WORD code_page;
  };
  Translation *translations = nullptr;
  UINT translation_bytes = 0;
  if (!VerQueryValueW(data.data(), L"\\VarFileInfo\\Translation",
                      reinterpret_cast<void **>(&translations),
                      &translation_bytes) ||
      translations == nullptr || translation_bytes < sizeof(Translation)) {
    if (error)
      *error = L"The installed update engine identity is incomplete.";
    return false;
  }
  const UINT translation_count = translation_bytes / sizeof(Translation);
  for (UINT index = 0; index < translation_count; ++index) {
    wchar_t product_query[96]{};
    wchar_t description_query[96]{};
    swprintf_s(product_query,
               L"\\StringFileInfo\\%04x%04x\\ProductName",
               translations[index].language, translations[index].code_page);
    swprintf_s(description_query,
               L"\\StringFileInfo\\%04x%04x\\FileDescription",
               translations[index].language, translations[index].code_page);
    wchar_t *product = nullptr;
    wchar_t *description = nullptr;
    UINT product_length = 0;
    UINT description_length = 0;
    if (VerQueryValueW(data.data(), product_query,
                       reinterpret_cast<void **>(&product),
                       &product_length) &&
        VerQueryValueW(data.data(), description_query,
                       reinterpret_cast<void **>(&description),
                       &description_length) &&
        product != nullptr && description != nullptr && product_length > 1 &&
        description_length > 1 && wcscmp(product, L"Velopack") == 0 &&
        wcscmp(description, L"Velopack 1.2.0") == 0) {
      return true;
    }
  }
  if (error)
    *error = L"The installed update engine identity is not Velopack 1.2.0.";
  return false;
}

class ExistingInstallLaunchLease final {
public:
  ExistingInstallLaunchLease() = default;
  ~ExistingInstallLaunchLease() { Release(); }
  ExistingInstallLaunchLease(const ExistingInstallLaunchLease &) = delete;
  ExistingInstallLaunchLease &
  operator=(const ExistingInstallLaunchLease &) = delete;

  [[nodiscard]] bool Acquire(const InstalledBeta &expected,
                             bool require_updater,
                             std::wstring *updater_path,
                             std::wstring *error) {
    if (error)
      error->clear();
    Release();
    root_ = CreateFileW(
        expected.root.c_str(), FILE_READ_ATTRIBUTES,
        FILE_SHARE_READ | FILE_SHARE_WRITE, nullptr, OPEN_EXISTING,
        FILE_FLAG_BACKUP_SEMANTICS | FILE_FLAG_OPEN_REPARSE_POINT, nullptr);
    if (root_ == INVALID_HANDLE_VALUE) {
      if (error)
        *error = L"The installed folder could not be reserved safely.";
      return false;
    }
    BY_HANDLE_FILE_INFORMATION root_information{};
    if (!GetFileInformationByHandle(root_, &root_information) ||
        (root_information.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY) == 0 ||
        (root_information.dwFileAttributes & FILE_ATTRIBUTE_REPARSE_POINT) !=
            0 ||
        root_information.dwVolumeSerialNumber != expected.root_volume_serial ||
        ((static_cast<std::uint64_t>(root_information.nFileIndexHigh) << 32) |
         root_information.nFileIndexLow) != expected.root_file_id) {
      if (error)
        *error = L"The installed folder changed while it was being prepared.";
      return false;
    }
    const std::wstring root_final = FinalPathForHandle(root_);
    if (root_final.empty()) {
      if (error)
        *error = L"The installed folder identity could not be resolved.";
      return false;
    }

    const std::wstring module_path = CurrentModulePath();
    HANDLE module =
        module_path.empty()
            ? INVALID_HANDLE_VALUE
            : CreateFileW(module_path.c_str(), FILE_READ_ATTRIBUTES,
                          FILE_SHARE_READ | FILE_SHARE_WRITE |
                              FILE_SHARE_DELETE,
                          nullptr, OPEN_EXISTING, FILE_FLAG_OPEN_REPARSE_POINT,
                          nullptr);
    if (module == INVALID_HANDLE_VALUE) {
      if (error)
        *error = L"The themed installer location could not be verified.";
      return false;
    }
    const std::wstring module_final = FinalPathForHandle(module);
    CloseHandle(module);
    if (module_final.empty() ||
        SameOrChildPhysicalPath(module_final, root_final)) {
      if (error)
        *error = L"Move this installer outside the Black Spirit Life "
                 L"installation folder, then run it again.";
      return false;
    }

    const DWORD current_required = GetCurrentDirectoryW(0, nullptr);
    std::wstring current_directory(current_required, L'\0');
    if (current_required == 0 ||
        GetCurrentDirectoryW(current_required, current_directory.data()) == 0) {
      if (error)
        *error = L"The installer working folder could not be verified.";
      return false;
    }
    while (!current_directory.empty() && current_directory.back() == L'\0')
      current_directory.pop_back();
    std::wstring current_final;
    if (!DirectoryFinalPath(current_directory, &current_final)) {
      if (error)
        *error = L"The installer working folder could not be verified.";
      return false;
    }
    if (SameOrChildPhysicalPath(current_final, root_final)) {
      const std::filesystem::path parent =
          std::filesystem::path(expected.root).parent_path();
      if (parent.empty() || !SetCurrentDirectoryW(parent.c_str())) {
        if (error)
          *error = L"The installer could not leave the application folder.";
        return false;
      }
      const DWORD moved_required = GetCurrentDirectoryW(0, nullptr);
      std::wstring moved_directory(moved_required, L'\0');
      if (moved_required == 0 ||
          GetCurrentDirectoryW(moved_required, moved_directory.data()) == 0) {
        if (error)
          *error = L"The installer working folder could not be moved safely.";
        return false;
      }
      while (!moved_directory.empty() && moved_directory.back() == L'\0')
        moved_directory.pop_back();
      std::wstring moved_final;
      if (!DirectoryFinalPath(moved_directory, &moved_final) ||
          SameOrChildPhysicalPath(moved_final, root_final)) {
        if (error)
          *error = L"The installer working folder is still inside the "
                   L"application folder.";
        return false;
      }
    }

    if (!require_updater)
      return true;
    const std::filesystem::path updater =
        std::filesystem::path(expected.root) / L"Update.exe";
    updater_ = CreateFileW(updater.c_str(), GENERIC_READ | FILE_READ_ATTRIBUTES,
                           FILE_SHARE_READ, nullptr, OPEN_EXISTING,
                           FILE_FLAG_OPEN_REPARSE_POINT, nullptr);
    if (updater_ == INVALID_HANDLE_VALUE) {
      if (error)
        *error = L"The installed update engine could not be reserved safely.";
      return false;
    }
    BY_HANDLE_FILE_INFORMATION updater_information{};
    const std::wstring updater_final = FinalPathForHandle(updater_);
    const std::wstring expected_final = root_final + L"\\Update.exe";
    if (!GetFileInformationByHandle(updater_, &updater_information) ||
        (updater_information.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY) !=
            0 ||
        (updater_information.dwFileAttributes & FILE_ATTRIBUTE_REPARSE_POINT) !=
            0 ||
        (updater_information.nFileSizeHigh == 0 &&
         updater_information.nFileSizeLow == 0) ||
        updater_final.empty() ||
        _wcsicmp(updater_final.c_str(), expected_final.c_str()) != 0 ||
        !VerifyVelopackUpdaterVersion(updater.wstring(), error)) {
      if (error && error->empty())
        *error = L"The installed update engine identity could not be verified.";
      return false;
    }
    if (updater_path)
      *updater_path = updater.wstring();
    return true;
  }

  void Release() {
    if (updater_ != INVALID_HANDLE_VALUE) {
      CloseHandle(updater_);
      updater_ = INVALID_HANDLE_VALUE;
    }
    if (root_ != INVALID_HANDLE_VALUE) {
      CloseHandle(root_);
      root_ = INVALID_HANDLE_VALUE;
    }
  }

private:
  HANDLE root_ = INVALID_HANDLE_VALUE;
  HANDLE updater_ = INVALID_HANDLE_VALUE;
};

bool VerifyRegisteredRoot(const InstalledBeta &expected,
                          std::wstring *registered_path,
                          std::wstring *error) {
  std::wstring path;
  bool exists = false;
  if (!QueryRegisteredInstallLocation(&path, &exists, error))
    return false;
  if (!exists) {
    if (error)
      *error = L"The installed application registration is missing.";
    return false;
  }
  InstalledBeta registered;
  std::wstring verification_error;
  if (!VerifyInstalledBetaRoot(path, &registered, &verification_error) ||
      registered.root_volume_serial != expected.root_volume_serial ||
      registered.root_file_id != expected.root_file_id) {
    if (error)
      *error = L"The installed application registration no longer matches the "
               L"application folder.";
    return false;
  }
  if (registered_path)
    *registered_path = std::move(path);
  return true;
}

bool IsPathAbsent(const std::filesystem::path &path, bool *absent,
                  std::wstring *error) {
  const DWORD attributes = GetFileAttributesW(path.c_str());
  if (attributes == INVALID_FILE_ATTRIBUTES) {
    const DWORD failure = GetLastError();
    if (failure == ERROR_FILE_NOT_FOUND || failure == ERROR_PATH_NOT_FOUND) {
      *absent = true;
      return true;
    }
    if (error)
      *error = L"Windows could not verify that the old application files "
               L"were removed.";
    return false;
  }
  *absent = false;
  return true;
}

bool UninstallPostconditionSatisfied(const InstalledBeta &expected,
                                     const std::wstring &registered_before,
                                     bool *satisfied, std::wstring *error) {
  *satisfied = false;
  InstalledBeta still_installed;
  std::wstring ignored;
  if (VerifyInstalledBetaRoot(expected.root, &still_installed, &ignored))
    return true;

  const std::filesystem::path root(expected.root);
  const std::vector<std::filesystem::path> required_files = {
      root / L"BlackSpiritLife.exe",
      root / L"current" / L"BlackSpiritLife.exe",
      root / L"current" / L"BlackSpiritLifeUpdater.exe",
      root / L"current" / L"sq.version"};
  for (const auto &path : required_files) {
    bool absent = false;
    if (!IsPathAbsent(path, &absent, error))
      return false;
    if (!absent)
      return true;
  }

  std::wstring registered_now;
  bool registration_exists = false;
  if (!QueryRegisteredInstallLocation(&registered_now, &registration_exists,
                                      error)) {
    return false;
  }
  const bool old_registration_remains =
      registration_exists &&
      _wcsicmp(registered_now.c_str(), registered_before.c_str()) == 0;
  *satisfied = !old_registration_remains;
  return true;
}

std::wstring RetainLogAndRemoveEngine(ExtractedPayload &payload) {
  payload.ReleaseLocks();
  if (!payload.executable.empty())
    DeleteFileW(payload.executable.c_str());
  const DWORD attributes = payload.log_file.empty()
                               ? INVALID_FILE_ATTRIBUTES
                               : GetFileAttributesW(payload.log_file.c_str());
  if (attributes != INVALID_FILE_ATTRIBUTES &&
      (attributes & FILE_ATTRIBUTE_DIRECTORY) == 0 &&
      (attributes & FILE_ATTRIBUTE_REPARSE_POINT) == 0) {
    return payload.log_file;
  }
  if (!payload.directory.empty())
    RemoveDirectoryW(payload.directory.c_str());
  return {};
}

void RecordFailure(InstallEngineResult *result, const std::wstring &message,
                   const std::wstring &install_root, bool fresh_install,
                   bool setup_started) {
  if (result == nullptr)
    return;
  result->setup_started = setup_started;
  result->error = message;
  if (!setup_started) {
    result->error += L" No application files or personal data were changed.";
    return;
  }
  result->error += L" Your personal data was not changed.";
  InstalledBeta verified;
  std::wstring ignored;
  if (VerifyInstalledBetaRoot(install_root, &verified, &ignored)) {
    result->application_verified_after_failure = true;
    if (fresh_install &&
        CompareSemanticVersions(verified.version,
                                std::wstring(build_config::kVersion)) == 0) {
      result->success = true;
      result->installed_root = verified.root;
      result->installed_version = verified.version;
      return;
    }
    result->error += L" The installed application is still verified as " +
                     verified.version + L".";
  } else if (!fresh_install) {
    result->error += L" The application files could not be verified; close "
                     L"other setup tasks and run Repair.";
  }
  if (fresh_install) {
    result->error +=
        L" The selected folder may contain incomplete application files. "
        L"Choose another new or empty folder before trying again.";
  }
}

} // namespace

InstallEngineResult
RunInstallEngine(const std::wstring &install_root, bool fresh_install,
                 const InstallEngineProgressCallback &progress_callback) {
  InstallEngineResult result;
  bsl::windows::BetaMaintenanceGate maintenance_gate;
  std::wstring root_error;
  if (!maintenance_gate.TryAcquire(&root_error)) {
    RecordFailure(&result, root_error, install_root, fresh_install, false);
    return result;
  }
  std::wstring extraction_error;
  auto payload = ExtractEmbeddedPayload(&extraction_error);
  if (!payload) {
    RecordFailure(&result, extraction_error, install_root, fresh_install,
                  false);
    return result;
  }
  InstallRootLease root_lease;
  ExistingInstallLaunchLease existing_launch_lease;
  std::optional<InstalledBeta> expected_existing;
  if (fresh_install) {
    if (!root_lease.AcquireFresh(install_root, &root_error)) {
      RecordFailure(&result, root_error, install_root, fresh_install, false);
      CleanupExtractedPayload(*payload);
      return result;
    }
    if (!EnsureNoRunningBetaProcess(install_root, &root_error)) {
      RecordFailure(&result, root_error, install_root, fresh_install, false);
      CleanupExtractedPayload(*payload);
      return result;
    }
  } else {
    InstalledBeta existing;
    if (!VerifyInstalledBetaRoot(install_root, &existing, &root_error)) {
      RecordFailure(&result,
                    L"The existing installation changed before it could "
                    L"be updated.",
                    install_root, fresh_install, false);
      CleanupExtractedPayload(*payload);
      return result;
    }
    const InstallPathValidation personal_data_safety =
        ValidateInstallRootPersonalDataSafety(existing.root);
    if (!personal_data_safety.valid) {
      RecordFailure(&result, personal_data_safety.error, install_root,
                    fresh_install, false);
      CleanupExtractedPayload(*payload);
      return result;
    }
    if (!EnsureNoRunningBetaProcess(existing.root, &root_error)) {
      RecordFailure(&result, root_error, install_root, fresh_install, false);
      CleanupExtractedPayload(*payload);
      return result;
    }
    expected_existing = existing;
  }
  std::wstring command_line = QuoteArgument(payload->executable) +
                              L" --silent --log " +
                              QuoteArgument(payload->log_file) +
                              L" --installto " + QuoteArgument(install_root);
  std::vector<wchar_t> mutable_command(command_line.begin(),
                                       command_line.end());
  mutable_command.push_back(L'\0');
  if (!fresh_install) {
    if (!expected_existing ||
        !existing_launch_lease.Acquire(*expected_existing, false, nullptr,
                                       &root_error)) {
      RecordFailure(&result, root_error, install_root, fresh_install, false);
      CleanupExtractedPayload(*payload);
      return result;
    }
    InstalledBeta immediately_verified;
    if (!expected_existing ||
        !VerifyInstalledBetaRoot(install_root, &immediately_verified,
                                 &root_error) ||
        immediately_verified.root_volume_serial !=
            expected_existing->root_volume_serial ||
        immediately_verified.root_file_id != expected_existing->root_file_id ||
        CompareSemanticVersions(immediately_verified.version,
                                expected_existing->version) != 0) {
      RecordFailure(&result,
                    L"The existing installation changed while setup was "
                    L"being prepared.",
                    install_root, fresh_install, false);
      CleanupExtractedPayload(*payload);
      return result;
    }
    const InstallPathValidation personal_data_safety =
        ValidateInstallRootPersonalDataSafety(immediately_verified.root);
    if (!personal_data_safety.valid) {
      RecordFailure(&result, personal_data_safety.error, install_root,
                    fresh_install, false);
      CleanupExtractedPayload(*payload);
      return result;
    }
    if (!EnsureNoRunningBetaProcess(immediately_verified.root, &root_error)) {
      RecordFailure(&result, root_error, install_root, fresh_install, false);
      CleanupExtractedPayload(*payload);
      return result;
    }
  } else if (!EnsureNoRunningBetaProcess(install_root, &root_error)) {
    RecordFailure(&result, root_error, install_root, fresh_install, false);
    CleanupExtractedPayload(*payload);
    return result;
  }
  STARTUPINFOW startup{sizeof(STARTUPINFOW)};
  PROCESS_INFORMATION process{};
  const BOOL started = CreateProcessW(
      payload->executable.c_str(), mutable_command.data(), nullptr, nullptr,
      FALSE, CREATE_UNICODE_ENVIRONMENT | CREATE_NO_WINDOW, nullptr,
      payload->directory.c_str(), &startup, &process);
  if (!started) {
    RecordFailure(&result, L"The installation engine could not be started.",
                  install_root, fresh_install, false);
    result.retained_log = RetainLogAndRemoveEngine(*payload);
    return result;
  }
  // CreateProcess has opened the verified image. It is now safe to release the
  // deny-write/delete handles that closed the verification-to-launch window.
  existing_launch_lease.Release();
  payload->ReleaseLocks();
  result.setup_started = true;
  DWORD wait_result = WAIT_TIMEOUT;
  DWORD elapsed_seconds = 0;
  while (wait_result == WAIT_TIMEOUT || wait_result == WAIT_FAILED) {
    wait_result = WaitForSingleObject(process.hProcess, 1000);
    if (wait_result == WAIT_OBJECT_0)
      break;
    if (wait_result == WAIT_TIMEOUT) {
      ++elapsed_seconds;
    } else {
      DWORD active_code = 0;
      if (GetExitCodeProcess(process.hProcess, &active_code) &&
          active_code != STILL_ACTIVE) {
        wait_result = WAIT_OBJECT_0;
        break;
      }
      ++elapsed_seconds;
      Sleep(1000);
    }
    if (progress_callback &&
        (elapsed_seconds == 120 ||
         (elapsed_seconds > 120 && elapsed_seconds % 120 == 0))) {
      progress_callback(
          L"Windows Setup is still working. Please keep this window open. "
          L"Diagnostic log: " +
              payload->log_file,
          payload->log_file);
    }
  }
  DWORD exit_code = 1;
  const BOOL exit_code_read = GetExitCodeProcess(process.hProcess, &exit_code);
  CloseHandle(process.hThread);
  CloseHandle(process.hProcess);
  if (wait_result != WAIT_OBJECT_0 || !exit_code_read) {
    RecordFailure(&result,
                  L"Windows could not confirm that installation finished.",
                  install_root, fresh_install, true);
    result.retained_log = RetainLogAndRemoveEngine(*payload);
    return result;
  }
  if (exit_code != 0) {
    RecordFailure(&result, L"Installation did not finish.", install_root,
                  fresh_install, true);
    result.retained_log = RetainLogAndRemoveEngine(*payload);
    return result;
  }
  InstalledBeta verified;
  std::wstring verification_error;
  if (!VerifyInstalledBetaRoot(install_root, &verified, &verification_error) ||
      CompareSemanticVersions(verified.version,
                              std::wstring(build_config::kVersion)) != 0) {
    RecordFailure(&result,
                  L"Installation finished, but the installed package could "
                  L"not be verified. " +
                      verification_error,
                  install_root, fresh_install, true);
    result.retained_log = RetainLogAndRemoveEngine(*payload);
    return result;
  }
  result.success = true;
  result.installed_root = verified.root;
  result.installed_version = verified.version;
  CleanupExtractedPayload(*payload);
  return result;
}

InstallEngineResult RunUninstallEngine(
    const std::wstring &install_root, bool remove_personal_data,
    const InstallEngineProgressCallback &progress_callback) {
  InstallEngineResult result;
  result.personal_data_requested = remove_personal_data;
  bsl::windows::BetaMaintenanceGate maintenance_gate;
  std::wstring error;
  if (!maintenance_gate.TryAcquire(&error)) {
    result.error = error +
                   L" No application files or planner settings were changed.";
    return result;
  }

  InstalledBeta expected;
  if (!VerifyInstalledBetaRoot(install_root, &expected, &error)) {
    result.error = L"The existing installation could not be verified. "
                   L"Nothing was changed.";
    return result;
  }
  std::wstring registered_before;
  if (!VerifyRegisteredRoot(expected, &registered_before, &error)) {
    result.error = error + L" Nothing was changed.";
    return result;
  }
  const InstallPathValidation personal_data_safety =
      ValidateInstallRootPersonalDataSafety(expected.root);
  if (!personal_data_safety.valid) {
    result.error = personal_data_safety.error + L" Nothing was changed.";
    return result;
  }
  if (!EnsureNoRunningBetaProcess(expected.root, &error)) {
    result.error = error + L" Nothing was changed.";
    return result;
  }

  PersonalDataRemovalPlan removal_plan;
  if (remove_personal_data) {
    PersonalDataRemovalResult prepared =
        DetectPendingPersonalDataRemoval(&removal_plan);
    if (prepared.success &&
        prepared.status == PersonalDataRemovalStatus::none) {
      prepared = PreparePersonalDataRemoval(expected.root, &removal_plan);
    } else if (prepared.success &&
               PreparedPersonalDataRemovalMatchesInstallation(
                   removal_plan, expected.root, registered_before,
                   expected.version, expected.root_volume_serial,
                   expected.root_file_id)) {
      // Resume the same explicitly approved uninstall after an earlier
      // pre-launch or Velopack failure. The durable plan is revalidated by the
      // removal subsystem before it is returned here.
    } else if (prepared.success) {
      prepared.success = false;
      prepared.message =
          L"A previous planner-data cleanup must be finished before another "
          L"uninstall can start.";
    }
    if (!prepared.success) {
      result.error = prepared.message.empty()
                         ? L"The personal-data folders could not be "
                           L"verified. Nothing was changed."
                         : prepared.message;
      return result;
    }
  }

  ExistingInstallLaunchLease launch_lease;
  std::wstring updater_path;
  if (!launch_lease.Acquire(expected, true, &updater_path, &error)) {
    result.error = error + L" Nothing was changed.";
    return result;
  }

  InstalledBeta immediately_verified;
  std::wstring registered_immediately;
  if (!VerifyInstalledBetaRoot(expected.root, &immediately_verified, &error) ||
      immediately_verified.root_volume_serial != expected.root_volume_serial ||
      immediately_verified.root_file_id != expected.root_file_id ||
      CompareSemanticVersions(immediately_verified.version,
                              expected.version) != 0 ||
      !VerifyRegisteredRoot(immediately_verified, &registered_immediately,
                            &error) ||
      _wcsicmp(registered_immediately.c_str(), registered_before.c_str()) != 0) {
    result.error = L"The installed application changed while uninstall was being "
                   L"prepared. Nothing was changed.";
    return result;
  }
  const InstallPathValidation immediate_personal_data_safety =
      ValidateInstallRootPersonalDataSafety(immediately_verified.root);
  if (!immediate_personal_data_safety.valid) {
    result.error = immediate_personal_data_safety.error +
                   L" Nothing was changed.";
    return result;
  }
  if (!EnsureNoRunningBetaProcess(immediately_verified.root, &error)) {
    result.error = error + L" Nothing was changed.";
    return result;
  }

  const std::wstring command_line =
      QuoteArgument(updater_path) + L" --uninstall --silent";
  std::vector<wchar_t> mutable_command(command_line.begin(),
                                       command_line.end());
  mutable_command.push_back(L'\0');
  STARTUPINFOW startup{sizeof(STARTUPINFOW)};
  PROCESS_INFORMATION process{};
  const BOOL started = CreateProcessW(
      updater_path.c_str(), mutable_command.data(), nullptr, nullptr, FALSE,
      CREATE_UNICODE_ENVIRONMENT | CREATE_NO_WINDOW, nullptr,
      immediately_verified.root.c_str(), &startup, &process);
  if (!started) {
    result.error = L"The verified uninstall engine could not be started. "
                   L"Nothing was changed.";
    return result;
  }
  launch_lease.Release();
  result.setup_started = true;

  DWORD wait_result = WAIT_TIMEOUT;
  DWORD elapsed_seconds = 0;
  while (wait_result == WAIT_TIMEOUT || wait_result == WAIT_FAILED) {
    wait_result = WaitForSingleObject(process.hProcess, 1000);
    if (wait_result == WAIT_OBJECT_0)
      break;
    if (wait_result == WAIT_TIMEOUT) {
      ++elapsed_seconds;
    } else {
      DWORD active_code = 0;
      if (GetExitCodeProcess(process.hProcess, &active_code) &&
          active_code != STILL_ACTIVE) {
        wait_result = WAIT_OBJECT_0;
        break;
      }
      ++elapsed_seconds;
      Sleep(1000);
    }
    if (progress_callback && elapsed_seconds > 0 &&
        elapsed_seconds % 30 == 0) {
      progress_callback(L"Windows is still removing the application files.",
                        L"");
    }
  }
  DWORD exit_code = 1;
  const BOOL exit_code_read = GetExitCodeProcess(process.hProcess, &exit_code);
  CloseHandle(process.hThread);
  CloseHandle(process.hProcess);
  if (wait_result != WAIT_OBJECT_0 || !exit_code_read || exit_code != 0) {
    result.error =
        L"Uninstall did not finish. Your planner settings and personal data "
        L"were not changed by this installer.";
    return result;
  }

  bool postcondition_satisfied = false;
  for (int attempt = 0; attempt < 20; ++attempt) {
    if (!UninstallPostconditionSatisfied(expected, registered_before,
                                         &postcondition_satisfied, &error)) {
      result.error = error;
      return result;
    }
    if (postcondition_satisfied)
      break;
    Sleep(250);
  }
  if (!postcondition_satisfied) {
    result.error = L"Windows finished uninstalling, but the old application "
                   L"registration or complete application files are still "
                   L"present. The installer did not remove any planner "
                   L"settings.";
    return result;
  }

  result.uninstalled = true;
  result.installed_root = expected.root;
  result.installed_version = expected.version;

  if (remove_personal_data) {
    const PersonalDataRemovalResult marked =
        MarkPersonalDataApplicationRemoved(removal_plan);
    if (!marked.success) {
      result.personal_data_cleanup_pending = true;
      result.error =
          marked.message.empty()
              ? L"The application was removed, but Windows could not record "
                L"the planner-data cleanup step. Your planner data was left "
                L"in place so cleanup can be retried safely."
              : marked.message;
      return result;
    }
    if (progress_callback) {
      progress_callback(
          L"The application was removed. Sending its planner data "
          L"to the Recycle Bin.",
          L"");
    }
    const PersonalDataRemovalResult cleanup =
        FinalizePersonalDataRemoval(removal_plan);
    if (!cleanup.success || !cleanup.removed) {
      result.personal_data_cleanup_pending = true;
      result.error = cleanup.message.empty()
                         ? L"The application was removed, but its planner "
                           L"data could not be sent to the Recycle Bin. The "
                           L"verified data was retained for a safe retry."
                         : cleanup.message;
      return result;
    }
    result.personal_data_removed = true;
  }

  result.success = true;
  return result;
}

InstallEngineResult RunPendingPersonalDataCleanup(
    const InstallEngineProgressCallback &progress_callback) {
  InstallEngineResult result;
  result.personal_data_requested = true;
  result.uninstalled = true;

  bsl::windows::BetaMaintenanceGate maintenance_gate;
  std::wstring error;
  if (!maintenance_gate.TryAcquire(&error)) {
    result.personal_data_cleanup_pending = true;
    result.error = error;
    return result;
  }
  if (!EnsureNoRunningBetaProcess(L"", &error)) {
    result.personal_data_cleanup_pending = true;
    result.error = error;
    return result;
  }
  if (progress_callback) {
    progress_callback(
        L"Finishing the requested planner-data cleanup through the Recycle "
        L"Bin.",
        L"");
  }
  const PersonalDataRemovalResult cleanup = RetryPendingPersonalDataRemoval();
  if (!cleanup.success || !cleanup.removed) {
    result.personal_data_cleanup_pending = true;
    result.error = cleanup.message.empty()
                       ? L"Planner-data cleanup is still pending. The data "
                         L"was not permanently deleted."
                       : cleanup.message;
    return result;
  }
  result.success = true;
  result.personal_data_removed = true;
  return result;
}

} // namespace bsl::installer
