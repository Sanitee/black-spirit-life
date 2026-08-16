#pragma once

#include <cstdint>
#include <optional>
#include <string>

namespace bsl::installer {

struct InstalledBeta {
  std::wstring root;
  std::wstring version;
  std::uint32_t root_volume_serial = 0;
  std::uint64_t root_file_id = 0;
};

struct InstalledBetaLookup {
  std::optional<InstalledBeta> installation;
  std::wstring error;
};

[[nodiscard]] InstalledBetaLookup LocateInstalledBeta();
[[nodiscard]] bool VerifyInstalledBetaRoot(const std::wstring &root,
                                           InstalledBeta *installation,
                                           std::wstring *error);
[[nodiscard]] bool QueryRegisteredInstallLocation(std::wstring *location,
                                                   bool *exists,
                                                   std::wstring *error);

// Returns -1, 0, or 1 using Semantic Version precedence rules.
[[nodiscard]] int CompareSemanticVersions(const std::wstring &left,
                                          const std::wstring &right);

} // namespace bsl::installer
