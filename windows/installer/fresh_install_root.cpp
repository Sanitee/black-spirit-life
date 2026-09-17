#include "fresh_install_root.h"

#include <shlobj.h>

#include <filesystem>

#include "install_path_policy.h"

namespace bsl::installer {

InstallRootLease::~InstallRootLease() {
  if (rollback_new_directory_ && !committed_) {
    // PrepareForSetup deliberately uses the engine-compatible read-only lease.
    // Reacquire deletion rights only on failure, and verify the stored identity
    // after reopening so a swapped path can never select a different directory.
    if (handle_ != INVALID_HANDLE_VALUE)
      CloseHandle(handle_);
    handle_ = CreateFileW(
        root_.c_str(), FILE_READ_ATTRIBUTES | DELETE,
        FILE_SHARE_READ | FILE_SHARE_WRITE, nullptr, OPEN_EXISTING,
        FILE_FLAG_BACKUP_SEMANTICS | FILE_FLAG_OPEN_REPARSE_POINT, nullptr);
    BY_HANDLE_FILE_INFORMATION current{};
    if (handle_ != INVALID_HANDLE_VALUE &&
        GetFileInformationByHandle(handle_, &current) &&
        current.dwVolumeSerialNumber == volume_serial_ &&
        current.nFileIndexHigh == file_index_high_ &&
        current.nFileIndexLow == file_index_low_ &&
        (current.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY) != 0 &&
        (current.dwFileAttributes & FILE_ATTRIBUTE_REPARSE_POINT) == 0) {
      // Windows refuses this operation on a nonempty directory. Delete through
      // the identity-bound handle, never a path that could now name a different
      // folder, and never recurse or try to remove application/personal files.
      FILE_DISPOSITION_INFO disposition{TRUE};
      SetFileInformationByHandle(handle_, FileDispositionInfo, &disposition,
                                 sizeof(disposition));
    }
  }
  if (handle_ != INVALID_HANDLE_VALUE)
    CloseHandle(handle_);
}

bool InstallRootLease::AcquireFresh(
    const std::wstring &root, std::wstring *error,
    bool roll_back_precreated_empty_directory) {
  if (error)
    error->clear();
  if (handle_ != INVALID_HANDLE_VALUE) {
    if (error)
      *error = L"An installation folder has already been prepared.";
    return false;
  }
  const auto before = ValidateFreshInstallPath(root);
  if (!before.valid) {
    if (error)
      *error = before.error;
    return false;
  }
  const std::filesystem::path destination(before.normalized_path);
  const auto parent = destination.parent_path();
  const int parent_status =
      SHCreateDirectoryExW(nullptr, parent.c_str(), nullptr);
  if (parent_status != ERROR_SUCCESS && parent_status != ERROR_ALREADY_EXISTS &&
      parent_status != ERROR_FILE_EXISTS) {
    if (error)
      *error = L"The selected installation folder could not be prepared. "
               L"Choose a folder you can write to.";
    return false;
  }
  // Unlike checking for absence followed by recursive creation, this atomic
  // final-component call tells us whether THIS attempt created the directory.
  const bool created = CreateDirectoryW(destination.c_str(), nullptr) != FALSE;
  if (!created) {
    const DWORD failure = GetLastError();
    if (failure != ERROR_ALREADY_EXISTS && failure != ERROR_FILE_EXISTS) {
      if (error)
        *error = L"The selected installation folder could not be prepared. "
                 L"Choose a folder you can write to.";
      return false;
    }
  }
  const bool roll_back = created || roll_back_precreated_empty_directory;
  handle_ = CreateFileW(
      destination.c_str(), FILE_READ_ATTRIBUTES | (roll_back ? DELETE : 0),
      FILE_SHARE_READ | FILE_SHARE_WRITE, nullptr, OPEN_EXISTING,
      FILE_FLAG_BACKUP_SEMANTICS | FILE_FLAG_OPEN_REPARSE_POINT, nullptr);
  if (handle_ == INVALID_HANDLE_VALUE) {
    if (error)
      *error = L"The installation folder could not be locked safely. "
               L"No application files were installed.";
    // Without an identity-bound handle, deleting by pathname is not safe.
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
  volume_serial_ = information.dwVolumeSerialNumber;
  file_index_high_ = information.nFileIndexHigh;
  file_index_low_ = information.nFileIndexLow;
  root_ = destination.wstring();
  rollback_new_directory_ = roll_back;
  // Rollback is armed before revalidation: another process adding a file makes
  // validation fail, and makes nonrecursive directory deletion fail as well.
  const auto after = ValidateFreshInstallPath(destination.wstring());
  if (!after.valid) {
    if (error)
      *error = after.error;
    return false;
  }
  return true;
}

bool InstallRootLease::PrepareForSetup(std::wstring *error) {
  if (error)
    error->clear();
  if (handle_ == INVALID_HANDLE_VALUE || root_.empty()) {
    if (error)
      *error = L"The installation folder has not been safely prepared.";
    return false;
  }
  CloseHandle(handle_);
  handle_ = CreateFileW(
      root_.c_str(), FILE_READ_ATTRIBUTES, FILE_SHARE_READ | FILE_SHARE_WRITE,
      nullptr, OPEN_EXISTING,
      FILE_FLAG_BACKUP_SEMANTICS | FILE_FLAG_OPEN_REPARSE_POINT, nullptr);
  BY_HANDLE_FILE_INFORMATION current{};
  if (handle_ == INVALID_HANDLE_VALUE ||
      !GetFileInformationByHandle(handle_, &current) ||
      current.dwVolumeSerialNumber != volume_serial_ ||
      current.nFileIndexHigh != file_index_high_ ||
      current.nFileIndexLow != file_index_low_ ||
      (current.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY) == 0 ||
      (current.dwFileAttributes & FILE_ATTRIBUTE_REPARSE_POINT) != 0) {
    if (error)
      *error =
          L"The prepared installation folder changed. No setup was started.";
    return false;
  }
  const auto validated = ValidateFreshInstallPath(root_);
  if (!validated.valid) {
    if (error)
      *error = validated.error;
    return false;
  }
  return true;
}

} // namespace bsl::installer
