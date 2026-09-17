#pragma once

#include <cstdint>
#include <functional>
#include <optional>
#include <string>
#include <vector>

namespace bsl::installer {

struct InstalledBeta {
  std::wstring root;
  std::wstring version;
  std::uint32_t root_volume_serial = 0;
  std::uint64_t root_file_id = 0;
};

struct InstalledBetaLookup {
  std::optional<InstalledBeta> installation;
  // Set only for a positively absent location on a reachable fixed drive.
  // Discovery is read-only; the user must explicitly confirm a fresh install.
  std::wstring missing_registered_root;
  std::wstring error;
};

[[nodiscard]] std::wstring DefaultInstallPath();
[[nodiscard]] InstalledBetaLookup LocateInstalledBeta();
[[nodiscard]] bool ValidateFreshInstallRegistration(
    const std::wstring &expected_missing_root, const std::wstring &chosen_root,
    bool allow_prepared_root, std::wstring *error);
[[nodiscard]] bool VerifyInstalledBetaRoot(const std::wstring &root,
                                           InstalledBeta *installation,
                                           std::wstring *error);
[[nodiscard]] bool QueryRegisteredInstallLocation(std::wstring *location,
                                                   bool *exists,
                                                   std::wstring *error);

// Read-only dependencies let native tests exercise registration changes and
// filesystem failures without replacing the user's real HKCU registration.
enum class InstalledRootState {
  missing,
  empty_directory,
  installed,
  unavailable_preferred,
  invalid
};

struct InstalledRootProbe {
  InstalledRootState state = InstalledRootState::invalid;
  std::optional<InstalledBeta> installation;
  std::wstring error;
};

struct InstallerDiscoveryEnvironment {
  std::function<bool(std::wstring *, bool *, std::wstring *)> query_registration;
  std::function<InstalledRootProbe(const std::wstring &)> probe_root;
  std::vector<std::wstring> fallback_roots;
  std::wstring preferred_root;
};

[[nodiscard]] InstalledBetaLookup LocateInstalledBetaForTesting(
    const InstallerDiscoveryEnvironment &environment);
[[nodiscard]] bool ValidateFreshInstallRegistrationForTesting(
    const std::wstring &expected_missing_root, const std::wstring &chosen_root,
    bool allow_prepared_root, const InstallerDiscoveryEnvironment &environment,
    std::wstring *error);

// Returns -1, 0, or 1 using Semantic Version precedence rules.
[[nodiscard]] int CompareSemanticVersions(const std::wstring &left,
                                          const std::wstring &right);

} // namespace bsl::installer
