#pragma once

#include <windows.h>

#include <string>

namespace bsl::installer {

// Owns only the final application directory created by this install attempt.
// Pre-launch rollback never removes pre-existing folders, children or profiles.
class InstallRootLease {
public:
  InstallRootLease() = default;
  ~InstallRootLease();
  InstallRootLease(const InstallRootLease &) = delete;
  InstallRootLease &operator=(const InstallRootLease &) = delete;

  [[nodiscard]] bool AcquireFresh(const std::wstring &root,
                                  std::wstring *error);
  // Keep the original installer's read-attributes-only lease during Setup:
  // holding DELETE access would require every engine open to share deletion.
  [[nodiscard]] bool PrepareForSetup(std::wstring *error);
  // After the installation engine starts, it owns the payload lifecycle.
  // Do not remove its directory even if the engine subsequently fails.
  void Commit() noexcept { committed_ = true; }

private:
  HANDLE handle_ = INVALID_HANDLE_VALUE;
  bool rollback_new_directory_ = false;
  bool committed_ = false;
  DWORD volume_serial_ = 0;
  DWORD file_index_high_ = 0;
  DWORD file_index_low_ = 0;
  std::wstring root_;
};

} // namespace bsl::installer
