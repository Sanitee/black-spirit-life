#include "beta_maintenance_gate.h"

namespace bsl::windows {
namespace {

constexpr wchar_t kMaintenanceMutexName[] =
    L"Local\\BlackSpiritLife.App.MaintenanceGate.v1";

} // namespace

BetaMaintenanceGate::~BetaMaintenanceGate() {
  Release();
  if (mutex_ != nullptr)
    CloseHandle(mutex_);
}

bool BetaMaintenanceGate::TryAcquire(std::wstring *error) {
  if (acquired_)
    return true;
  if (mutex_ == nullptr) {
    mutex_ = CreateMutexW(nullptr, FALSE, kMaintenanceMutexName);
    if (mutex_ == nullptr) {
      if (error)
        *error = L"Windows could not open the application maintenance gate.";
      return false;
    }
  }
  const DWORD wait = WaitForSingleObject(mutex_, 0);
  if (wait == WAIT_OBJECT_0 || wait == WAIT_ABANDONED) {
    acquired_ = true;
    return true;
  }
  if (error) {
    *error =
        wait == WAIT_TIMEOUT
            ? L"Black Spirit Life or another setup task is still "
              L"running. Close it, then try again."
            : L"Windows could not safely reserve the app for maintenance.";
  }
  return false;
}

void BetaMaintenanceGate::Release() {
  if (!acquired_)
    return;
  ReleaseMutex(mutex_);
  acquired_ = false;
}

} // namespace bsl::windows
