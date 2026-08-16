#pragma once

#include <windows.h>

#include <d2d1.h>
#include <gdiplus.h>

#include <cstddef>
#include <memory>
#include <string>

#include "installer_model.h"

namespace bsl::installer {

inline constexpr float kPreviewWidth = 920.0F;
inline constexpr float kPreviewHeight = 400.0F;

enum class InteractiveElement {
  none,
  install_path,
  browse,
  remove_personal_data,
  secondary,
  primary,
  close,
};

struct InteractionState {
  InteractiveElement hovered = InteractiveElement::none;
  InteractiveElement focused = InteractiveElement::none;
  std::size_t caret = 0;
  std::size_t selection_anchor = 0;
  bool caret_visible = false;
  float animation_phase = 0.0F;
};

struct InstallerLayout {
  D2D1_RECT_F title_drag{};
  D2D1_RECT_F close{};
  D2D1_RECT_F install_path{};
  D2D1_RECT_F browse{};
  D2D1_RECT_F remove_personal_data{};
  D2D1_RECT_F secondary{};
  D2D1_RECT_F primary{};
};

class InstallerRenderer final {
public:
  explicit InstallerRenderer(HINSTANCE module);
  ~InstallerRenderer();

  InstallerRenderer(const InstallerRenderer &) = delete;
  InstallerRenderer &operator=(const InstallerRenderer &) = delete;

  [[nodiscard]] bool IsReady() const noexcept;
  [[nodiscard]] InstallerLayout CalculateLayout(float width_dip,
                                                float height_dip) const;
  [[nodiscard]] HRESULT Render(HDC target, UINT width_pixels,
                               UINT height_pixels, float dpi,
                               const InstallerModel &model,
                               const InteractionState &interaction);
  [[nodiscard]] HRESULT CapturePreviewPng(
      const std::wstring &output_path, const InstallerModel &model,
      const InteractionState &interaction = {}, float width_dip = kPreviewWidth,
      float height_dip = kPreviewHeight);

private:
  [[nodiscard]] std::unique_ptr<Gdiplus::Bitmap>
  LoadPngResource(int resource_id) const;
  [[nodiscard]] HRESULT Draw(Gdiplus::Graphics &graphics, float width_dip,
                             float height_dip, const InstallerModel &model,
                             const InteractionState &interaction);

  HINSTANCE module_ = nullptr;
  ULONG_PTR gdiplus_token_ = 0;
  std::unique_ptr<Gdiplus::Bitmap> cedar_;
  std::unique_ptr<Gdiplus::Bitmap> lacquer_;
  std::unique_ptr<Gdiplus::Bitmap> title_sprig_;
  std::unique_ptr<Gdiplus::Bitmap> app_icon_;
  HRESULT initialization_result_ = E_FAIL;
};

} // namespace bsl::installer
