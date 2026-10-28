#include <iostream>
#include <limits>
#include <string_view>

#include "../frame_delivery_policy.h"

namespace {
int failures = 0;
int assertions = 0;

void Expect(bool condition, std::string_view description) {
  ++assertions;
  if (condition) return;
  ++failures;
  std::cerr << "FAIL: " << description << '\n';
}

void CheckLifecycle() {
  using webview_capture::FrameDeliveryPolicy;

  FrameDeliveryPolicy visible;
  Expect(!visible.ShouldCapture(), "default enabled is not yet sized");
  visible.SetSuspended(false);
  Expect(!visible.ShouldCapture(), "resume cannot start before a valid size");
  visible.SetEnabled(true);
  Expect(!visible.ShouldCapture(), "enable cannot start before a valid size");
  visible.SetSurfaceReady(true);
  Expect(visible.ShouldCapture(), "visible valid size permits capture");
  visible.SetEnabled(false);
  Expect(!visible.ShouldCapture(), "disable stops a running capture");
  visible.SetSurfaceReady(true);
  Expect(!visible.ShouldCapture(), "hidden valid resize cannot restart capture");
  visible.SetSuspended(false);
  Expect(!visible.ShouldCapture(), "hidden resume cannot restart capture");
  visible.SetEnabled(true);
  Expect(visible.ShouldCapture(), "reenable reuses the valid surface");

  visible.SetSuspended(true);
  Expect(!visible.ShouldCapture(), "explicit suspension stops capture");
  visible.SetEnabled(false);
  visible.SetEnabled(true);
  Expect(!visible.ShouldCapture(), "delivery toggle does not cancel suspension");
  visible.SetSurfaceReady(true);
  Expect(!visible.ShouldCapture(), "resize does not cancel suspension");
  visible.SetSuspended(false);
  Expect(visible.ShouldCapture(), "explicit resume starts a ready enabled view");

  visible.SetSurfaceReady(false);
  Expect(!visible.ShouldCapture(), "failed resize revokes previous valid size");
  visible.SetSuspended(false);
  visible.SetEnabled(true);
  Expect(!visible.ShouldCapture(), "resume or enable cannot bypass size failure");
  visible.SetSurfaceReady(true);
  Expect(visible.ShouldCapture(), "successful resize recovers failed surface");

  FrameDeliveryPolicy hidden;
  hidden.SetEnabled(false);
  hidden.SetSurfaceReady(true);
  Expect(!hidden.ShouldCapture(), "hidden before initial size never starts");
  hidden.SetSuspended(true);
  hidden.SetSuspended(false);
  Expect(!hidden.ShouldCapture(), "hidden suspend and resume never starts");
  hidden.SetEnabled(true);
  Expect(hidden.ShouldCapture(), "first visible delivery can use retained size");
  for (int i = 0; i < 100; ++i) {
    hidden.SetEnabled(false);
    Expect(!hidden.ShouldCapture(), "rapid hide stops capture");
    hidden.SetEnabled(false);
    Expect(!hidden.ShouldCapture(), "repeated hide remains stopped");
    hidden.SetEnabled(true);
    Expect(hidden.ShouldCapture(), "rapid show restores capture");
    hidden.SetEnabled(true);
    Expect(hidden.ShouldCapture(), "repeated show retains ready state");
  }

  // All flag combinations, including arbitrary event ordering: no one method
  // can accidentally override either of the other two independent constraints.
  for (int order = 0; order < 6; ++order) {
    constexpr int orders[6][3] = {
        {0, 1, 2}, {0, 2, 1}, {1, 0, 2},
        {1, 2, 0}, {2, 0, 1}, {2, 1, 0}};
    for (int flags = 0; flags < 8; ++flags) {
      FrameDeliveryPolicy policy;
      bool enabled = true;
      bool ready = false;
      bool suspended = false;
      for (const auto flag : orders[order]) {
        switch (flag) {
          case 0:
            enabled = (flags & 1) != 0;
            policy.SetEnabled(enabled);
            break;
          case 1:
            ready = (flags & 2) != 0;
            policy.SetSurfaceReady(ready);
            break;
          case 2:
            suspended = (flags & 4) != 0;
            policy.SetSuspended(suspended);
            break;
        }
        Expect(policy.ShouldCapture() == (enabled && ready && !suspended),
               "all delivery/size/suspension orderings obey the same gate");
      }
    }
  }
}

void CheckSizing() {
  using webview_capture::IsUsableSurfaceSize;
  Expect(IsUsableSurfaceSize(1024, 768, 1), "ordinary size remains valid");
  Expect(IsUsableSurfaceSize(1024, 768, 1.25), "fractional DPI remains valid");
  Expect(IsUsableSurfaceSize(1024.75, 768.5, 2),
         "existing integer logical-size conversion remains valid");
  Expect(IsUsableSurfaceSize(1024, 768, 0.5), "subunit scale can remain valid");
  Expect(IsUsableSurfaceSize(1, 1, 1), "single physical pixel remains valid");
  Expect(!IsUsableSurfaceSize(0, 768, 1), "zero width is not ready");
  Expect(!IsUsableSurfaceSize(1024, 0, 1), "zero height is not ready");
  Expect(!IsUsableSurfaceSize(-1, 768, 1), "negative width is rejected");
  Expect(!IsUsableSurfaceSize(1024, -1, 1), "negative height is rejected");
  Expect(!IsUsableSurfaceSize(0.9, 768, 1),
         "logical width truncating to zero is rejected");
  Expect(!IsUsableSurfaceSize(1024, 0.9, 1),
         "logical height truncating to zero is rejected");
  Expect(!IsUsableSurfaceSize(1024, 768, 0), "zero scale is rejected");
  Expect(!IsUsableSurfaceSize(1024, 768, -1), "negative scale is rejected");
  Expect(!IsUsableSurfaceSize(1, 1, 0.5),
         "physical dimensions truncating to zero are rejected");
  Expect(!IsUsableSurfaceSize(1024, 768, 1e30),
         "physical RECT coordinate overflow is rejected");
  Expect(!IsUsableSurfaceSize(1e30, 768, 1),
         "logical dimension overflow is rejected before integer conversion");
  const auto long_limit =
      static_cast<double>((std::numeric_limits<std::int32_t>::max)());
  Expect(!IsUsableSurfaceSize(long_limit, 768, 1),
         "float rounding across the RECT signed limit is rejected");
  for (const auto invalid : {std::numeric_limits<double>::infinity(),
                             -std::numeric_limits<double>::infinity(),
                             std::numeric_limits<double>::quiet_NaN()}) {
    Expect(!IsUsableSurfaceSize(invalid, 768, 1), "nonfinite width rejected");
    Expect(!IsUsableSurfaceSize(1024, invalid, 1), "nonfinite height rejected");
    Expect(!IsUsableSurfaceSize(1024, 768, invalid), "nonfinite scale rejected");
  }
  webview_capture::FrameDeliveryPolicy policy;
  policy.SetSurfaceReady(IsUsableSurfaceSize(1024, 768, 1));
  Expect(policy.ShouldCapture(), "valid sizing enables ready delivery");
  policy.SetSurfaceReady(IsUsableSurfaceSize(0, 768, 1));
  Expect(!policy.ShouldCapture(), "zero resize stops previously ready delivery");
  policy.SetSurfaceReady(false);  // The COM sizing operation reports failure.
  policy.SetEnabled(true);
  Expect(!policy.ShouldCapture(), "failed native bounds never arm delivery");

  using webview_capture::ClassifySurfaceSize;
  using webview_capture::SurfaceSizeState;
  Expect(ClassifySurfaceSize(0, 768, 1) == SurfaceSizeState::kEmpty,
         "collapsed width is a successful no-frame layout, not an error");
  Expect(ClassifySurfaceSize(1024, 0, 1) == SurfaceSizeState::kEmpty,
         "collapsed height is a successful no-frame layout, not an error");
  Expect(ClassifySurfaceSize(0, 0, 1) == SurfaceSizeState::kEmpty,
         "fully collapsed layout succeeds without frames");
  Expect(ClassifySurfaceSize(0.9, 768, 1) == SurfaceSizeState::kEmpty,
         "subpixel logical size succeeds without frames");
  Expect(ClassifySurfaceSize(1, 1, 0.5) == SurfaceSizeState::kEmpty,
         "subpixel physical size succeeds without frames");
  Expect(ClassifySurfaceSize(-1, 768, 1) == SurfaceSizeState::kInvalid,
         "negative size remains a malformed request");
  Expect(ClassifySurfaceSize(0, 0, 0) == SurfaceSizeState::kInvalid,
         "invalid scale is not concealed by a collapsed layout");
  Expect(ClassifySurfaceSize(std::numeric_limits<double>::quiet_NaN(), 768, 1) ==
             SurfaceSizeState::kInvalid,
         "NaN remains a malformed request");
}
}  // namespace

int main() {
  CheckLifecycle();
  CheckSizing();
  if (failures != 0) return 1;
  std::cout << "Frame delivery policy passed " << assertions
            << " assertions: first size, hidden delivery, resize, suspension, "
               "rapid toggles and safe sizing.\n";
  return 0;
}
