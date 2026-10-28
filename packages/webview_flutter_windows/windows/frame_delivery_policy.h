#pragma once

#include <cmath>
#include <cstddef>
#include <cstdint>
#include <limits>

// Pure capture policy: it never suspends scripts or changes WebView visibility.
// Keeping it independent of COM makes hidden/resize/resume ordering testable.
namespace webview_capture {

enum class SurfaceSizeState { kInvalid, kEmpty, kReady };

inline SurfaceSizeState ClassifySurfaceSize(double width, double height,
                                           double scale) {
  constexpr auto max_dimension = (std::numeric_limits<std::int32_t>::max)();
  if (!std::isfinite(width) || !std::isfinite(height) ||
      !std::isfinite(scale) || width < 0 || height < 0 || scale <= 0 ||
      width > max_dimension || height > max_dimension) {
    return SurfaceSizeState::kInvalid;
  }
  // A collapsed layout is a successful no-frame state, not a method error.
  if (width < 1 || height < 1) {
    return SurfaceSizeState::kEmpty;
  }
  // Match SetSurfaceSize's integer logical dimensions and float composition
  // dimensions before either conversion to Windows RECT coordinates.
  const auto scaled_width =
      static_cast<float>(static_cast<std::size_t>(width)) *
      static_cast<float>(scale);
  const auto scaled_height =
      static_cast<float>(static_cast<std::size_t>(height)) *
      static_cast<float>(scale);
  if (!std::isfinite(scaled_width) || !std::isfinite(scaled_height) ||
      static_cast<double>(scaled_width) > max_dimension ||
      static_cast<double>(scaled_height) > max_dimension) {
    return SurfaceSizeState::kInvalid;
  }
  if (scaled_width < 1 || scaled_height < 1) {
    return SurfaceSizeState::kEmpty;
  }
  return SurfaceSizeState::kReady;
}

inline bool IsUsableSurfaceSize(double width, double height, double scale) {
  return ClassifySurfaceSize(width, height, scale) == SurfaceSizeState::kReady;
}

class FrameDeliveryPolicy {
 public:
  void SetEnabled(bool enabled) { enabled_ = enabled; }
  void SetSurfaceReady(bool ready) { surface_ready_ = ready; }
  void SetSuspended(bool suspended) { suspended_ = suspended; }

  bool ShouldCapture() const {
    return enabled_ && surface_ready_ && !suspended_;
  }

 private:
  bool enabled_ = true;
  bool surface_ready_ = false;
  bool suspended_ = false;
};

}  // namespace webview_capture
