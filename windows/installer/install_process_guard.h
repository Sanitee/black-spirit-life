#pragma once

#include <string>

namespace bsl::installer {

[[nodiscard]] bool EnsureNoRunningBetaProcess(const std::wstring &install_root,
                                              std::wstring *error);

} // namespace bsl::installer
