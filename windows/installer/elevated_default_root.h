#pragma once

#include <string>

namespace bsl::installer {

// The public installer always suggests this exact root. A missing root-level
// directory needs a short elevated helper because the application installer
// and its per-user registration must continue to run as the signed-in user.
[[nodiscard]] bool IsDefaultInstallRootPath(const std::wstring &root);

// Starts the current installer executable through the Windows `runas` verb.
// The elevated helper may create only the fixed default root and grants the
// calling user inheritable access for future non-elevated application updates.
[[nodiscard]] bool PrepareDefaultInstallRootWithElevation(
    const std::wstring &root, bool *created, std::wstring *error);

// Internal elevated entry point. Returns zero only after the fixed default
// root was created and its ACL was assigned to the supplied account SID.
[[nodiscard]] int
RunElevatedDefaultRootPreparation(const std::wstring &user_sid);

} // namespace bsl::installer
