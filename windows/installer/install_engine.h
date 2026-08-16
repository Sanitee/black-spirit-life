#pragma once

#include <functional>
#include <string>

namespace bsl::installer {

struct InstallEngineResult {
  bool success = false;
  bool uninstalled = false;
  bool personal_data_requested = false;
  bool personal_data_removed = false;
  bool personal_data_cleanup_pending = false;
  bool setup_started = false;
  bool application_verified_after_failure = false;
  std::wstring installed_root;
  std::wstring installed_version;
  std::wstring error;
  std::wstring retained_log;
};

using InstallEngineProgressCallback = std::function<void(
    const std::wstring &message, const std::wstring &retained_log)>;

[[nodiscard]] InstallEngineResult
RunInstallEngine(const std::wstring &install_root, bool fresh_install,
                 const InstallEngineProgressCallback &progress_callback = {});

[[nodiscard]] InstallEngineResult RunUninstallEngine(
    const std::wstring &install_root, bool remove_personal_data,
    const InstallEngineProgressCallback &progress_callback = {});

[[nodiscard]] InstallEngineResult RunPendingPersonalDataCleanup(
    const InstallEngineProgressCallback &progress_callback = {});

} // namespace bsl::installer
