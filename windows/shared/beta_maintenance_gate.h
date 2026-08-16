#pragma once

#include <windows.h>

#include <string>

namespace bsl::windows {

// Serializes Black Spirit Life process startup with application
// maintenance. Ordinary planner/helper processes hold this gate only while
// they become visible to process enumeration. The themed installer holds it
// for the complete Velopack Setup operation.
class BetaMaintenanceGate final {
public:
  BetaMaintenanceGate() = default;
  ~BetaMaintenanceGate();

  BetaMaintenanceGate(const BetaMaintenanceGate &) = delete;
  BetaMaintenanceGate &operator=(const BetaMaintenanceGate &) = delete;

  [[nodiscard]] bool TryAcquire(std::wstring *error);
  void Release();
  [[nodiscard]] bool acquired() const { return acquired_; }

private:
  HANDLE mutex_ = nullptr;
  bool acquired_ = false;
};

} // namespace bsl::windows
