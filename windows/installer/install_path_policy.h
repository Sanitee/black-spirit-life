#pragma once

#include <string>

namespace bsl::installer {

struct InstallPathValidation {
  bool valid = false;
  std::wstring normalized_path;
  std::wstring error;
};

[[nodiscard]] InstallPathValidation
ValidateFreshInstallPath(const std::wstring &requested_path);

[[nodiscard]] InstallPathValidation
ValidateInstallRootPersonalDataSafety(const std::wstring &install_root);

} // namespace bsl::installer
