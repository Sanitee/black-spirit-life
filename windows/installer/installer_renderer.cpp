#include "installer_renderer.h"

#include <objidl.h>

#include <algorithm>
#include <array>
#include <cmath>
#include <cstring>
#include <cwchar>
#include <vector>

#include "resource.h"

namespace bsl::installer {
namespace {

using Gdiplus::Bitmap;
using Gdiplus::Color;
using Gdiplus::Font;
using Gdiplus::FontFamily;
using Gdiplus::Graphics;
using Gdiplus::GraphicsPath;
using Gdiplus::Image;
using Gdiplus::ImageAttributes;
using Gdiplus::LinearGradientBrush;
using Gdiplus::Pen;
using Gdiplus::PointF;
using Gdiplus::RectF;
using Gdiplus::SolidBrush;
using Gdiplus::StringFormat;

const Color kCanvas(255, 14, 12, 15);
const Color kRosewood(255, 111, 60, 71);
const Color kRosewoodDim(255, 73, 39, 48);
const Color kDustySakura(255, 207, 127, 152);
const Color kPaleBlossom(255, 244, 202, 214);
const Color kWarmIvory(255, 241, 233, 223);
const Color kMutedText(255, 187, 170, 176);
const Color kQuietText(255, 143, 126, 133);
const Color kBarkCopper(255, 157, 96, 72);

RectF ToRect(const D2D1_RECT_F &rect) {
  return RectF(rect.left, rect.top, rect.right - rect.left,
               rect.bottom - rect.top);
}

void AddRoundedRect(GraphicsPath *path, const RectF &rect, float radius) {
  const float diameter = radius * 2.0F;
  path->AddArc(rect.X, rect.Y, diameter, diameter, 180.0F, 90.0F);
  path->AddArc(rect.GetRight() - diameter, rect.Y, diameter, diameter, 270.0F,
               90.0F);
  path->AddArc(rect.GetRight() - diameter, rect.GetBottom() - diameter,
               diameter, diameter, 0.0F, 90.0F);
  path->AddArc(rect.X, rect.GetBottom() - diameter, diameter, diameter, 90.0F,
               90.0F);
  path->CloseFigure();
}

void FillRounded(Graphics &graphics, const RectF &rect, float radius,
                 Gdiplus::Brush &brush) {
  GraphicsPath path;
  AddRoundedRect(&path, rect, radius);
  graphics.FillPath(&brush, &path);
}

void StrokeRounded(Graphics &graphics, const RectF &rect, float radius,
                   const Color &color, float width = 1.0F) {
  GraphicsPath path;
  AddRoundedRect(&path, rect, radius);
  Pen pen(color, width);
  graphics.DrawPath(&pen, &path);
}

void DrawText(
    Graphics &graphics, const std::wstring &text, const wchar_t *face,
    float size, INT style, const Color &color, const RectF &rect,
    Gdiplus::StringAlignment horizontal = Gdiplus::StringAlignmentNear,
    Gdiplus::StringAlignment vertical = Gdiplus::StringAlignmentNear) {
  FontFamily requested_family(face);
  const FontFamily *family = requested_family.IsAvailable()
                                 ? &requested_family
                                 : FontFamily::GenericSansSerif();
  Font font(family, size, style, Gdiplus::UnitPixel);
  StringFormat format;
  format.SetAlignment(horizontal);
  format.SetLineAlignment(vertical);
  format.SetTrimming(Gdiplus::StringTrimmingEllipsisCharacter);
  format.SetFormatFlags(Gdiplus::StringFormatFlagsNoWrap);
  SolidBrush brush(color);
  graphics.DrawString(text.c_str(), static_cast<INT>(text.size()), &font, rect,
                      &format, &brush);
}

void DrawWrappedText(Graphics &graphics, const std::wstring &text,
                     const wchar_t *face, float size, INT style,
                     const Color &color, const RectF &rect) {
  FontFamily requested_family(face);
  const FontFamily *family = requested_family.IsAvailable()
                                 ? &requested_family
                                 : FontFamily::GenericSansSerif();
  Font font(family, size, style, Gdiplus::UnitPixel);
  StringFormat format;
  format.SetAlignment(Gdiplus::StringAlignmentNear);
  format.SetLineAlignment(Gdiplus::StringAlignmentNear);
  format.SetTrimming(Gdiplus::StringTrimmingEllipsisWord);
  SolidBrush brush(color);
  graphics.DrawString(text.c_str(), static_cast<INT>(text.size()), &font, rect,
                      &format, &brush);
}

void DrawTexture(Graphics &graphics, Image *image, const RectF &destination,
                 float opacity) {
  if (image == nullptr || image->GetLastStatus() != Gdiplus::Ok) {
    return;
  }
  Gdiplus::ColorMatrix matrix = {{
      {1.0F, 0.0F, 0.0F, 0.0F, 0.0F},
      {0.0F, 1.0F, 0.0F, 0.0F, 0.0F},
      {0.0F, 0.0F, 1.0F, 0.0F, 0.0F},
      {0.0F, 0.0F, 0.0F, opacity, 0.0F},
      {0.0F, 0.0F, 0.0F, 0.0F, 1.0F},
  }};
  ImageAttributes attributes;
  attributes.SetColorMatrix(&matrix);
  graphics.DrawImage(
      image, destination, 0.0F, 0.0F, static_cast<float>(image->GetWidth()),
      static_cast<float>(image->GetHeight()), Gdiplus::UnitPixel, &attributes);
}

bool GetPngEncoderClsid(CLSID *result) {
  UINT count = 0;
  UINT bytes = 0;
  if (Gdiplus::GetImageEncodersSize(&count, &bytes) != Gdiplus::Ok ||
      bytes == 0) {
    return false;
  }
  std::vector<std::byte> storage(bytes);
  auto *encoders = reinterpret_cast<Gdiplus::ImageCodecInfo *>(storage.data());
  if (Gdiplus::GetImageEncoders(count, bytes, encoders) != Gdiplus::Ok) {
    return false;
  }
  for (UINT index = 0; index < count; ++index) {
    if (std::wcscmp(encoders[index].MimeType, L"image/png") == 0) {
      *result = encoders[index].Clsid;
      return true;
    }
  }
  return false;
}

void DrawFolderGlyph(Graphics &graphics, const RectF &rect, Color color) {
  GraphicsPath path;
  path.AddLine(rect.X, rect.Y + 6.0F, rect.X + 10.0F, rect.Y + 6.0F);
  path.AddLine(rect.X + 10.0F, rect.Y + 6.0F, rect.X + 14.0F, rect.Y + 10.0F);
  path.AddLine(rect.X + 14.0F, rect.Y + 10.0F, rect.GetRight(), rect.Y + 10.0F);
  path.AddLine(rect.GetRight(), rect.Y + 10.0F, rect.GetRight() - 2.0F,
               rect.GetBottom());
  path.AddLine(rect.GetRight() - 2.0F, rect.GetBottom(), rect.X + 2.0F,
               rect.GetBottom());
  path.AddLine(rect.X + 2.0F, rect.GetBottom(), rect.X, rect.Y + 6.0F);
  path.CloseFigure();
  SolidBrush fill(Color(42, color.GetR(), color.GetG(), color.GetB()));
  Pen pen(color, 1.2F);
  graphics.FillPath(&fill, &path);
  graphics.DrawPath(&pen, &path);
}

} // namespace

InstallerRenderer::InstallerRenderer(HINSTANCE module) : module_(module) {
  Gdiplus::GdiplusStartupInput startup_input;
  const auto status =
      Gdiplus::GdiplusStartup(&gdiplus_token_, &startup_input, nullptr);
  if (status != Gdiplus::Ok) {
    initialization_result_ = E_FAIL;
    return;
  }
  cedar_ = LoadPngResource(IDR_SAKURA_CEDAR);
  lacquer_ = LoadPngResource(IDR_SAKURA_LACQUER);
  title_sprig_ = LoadPngResource(IDR_SAKURA_TITLE_SPRIG);
  HICON loaded_icon = static_cast<HICON>(
      LoadImageW(module_, MAKEINTRESOURCEW(IDI_BLACK_SPIRIT_LIFE), IMAGE_ICON,
                 256, 256, LR_DEFAULTCOLOR));
  if (loaded_icon != nullptr) {
    std::unique_ptr<Bitmap> decoded(Bitmap::FromHICON(loaded_icon));
    if (decoded && decoded->GetLastStatus() == Gdiplus::Ok) {
      app_icon_.reset(decoded->Clone(0, 0, decoded->GetWidth(),
                                     decoded->GetHeight(),
                                     PixelFormat32bppARGB));
    }
    DestroyIcon(loaded_icon);
  }
  initialization_result_ =
      cedar_ && lacquer_ && title_sprig_ && app_icon_ ? S_OK : E_FAIL;
}

InstallerRenderer::~InstallerRenderer() {
  app_icon_.reset();
  title_sprig_.reset();
  lacquer_.reset();
  cedar_.reset();
  if (gdiplus_token_ != 0) {
    Gdiplus::GdiplusShutdown(gdiplus_token_);
  }
}

bool InstallerRenderer::IsReady() const noexcept {
  return SUCCEEDED(initialization_result_);
}

InstallerLayout InstallerRenderer::CalculateLayout(float width_dip,
                                                   float height_dip) const {
  InstallerLayout layout;
  layout.title_drag = {0.0F, 0.0F, width_dip - 62.0F, 42.0F};
  layout.close = {width_dip - 54.0F, 0.0F, width_dip, 42.0F};
  constexpr float path_top = 204.0F;
  layout.install_path = {318.0F, path_top, width_dip - 172.0F,
                         path_top + 46.0F};
  layout.browse = {width_dip - 160.0F, path_top, width_dip - 44.0F,
                   path_top + 46.0F};
  layout.remove_personal_data = {318.0F, 260.0F, width_dip - 44.0F, 292.0F};
  layout.secondary = {width_dip - 392.0F, height_dip - 76.0F,
                      width_dip - 252.0F, height_dip - 28.0F};
  layout.primary = {width_dip - 240.0F, height_dip - 76.0F, width_dip - 44.0F,
                    height_dip - 28.0F};
  return layout;
}

HRESULT InstallerRenderer::Render(HDC target, UINT width_pixels,
                                  UINT height_pixels, float dpi,
                                  const InstallerModel &model,
                                  const InteractionState &interaction) {
  if (!IsReady() || target == nullptr || width_pixels == 0 ||
      height_pixels == 0 || dpi <= 0.0F) {
    return E_INVALIDARG;
  }
  Graphics graphics(target);
  graphics.SetPageUnit(Gdiplus::UnitPixel);
  const float scale = dpi / 96.0F;
  graphics.ScaleTransform(scale, scale);
  return Draw(graphics, static_cast<float>(width_pixels) / scale,
              static_cast<float>(height_pixels) / scale, model, interaction);
}

HRESULT
InstallerRenderer::CapturePreviewPng(const std::wstring &output_path,
                                     const InstallerModel &model,
                                     const InteractionState &interaction,
                                     float width_dip, float height_dip) {
  if (!IsReady() || output_path.empty() || width_dip < 720.0F ||
      height_dip < 370.0F) {
    return E_INVALIDARG;
  }
  Bitmap bitmap(static_cast<INT>(width_dip), static_cast<INT>(height_dip),
                PixelFormat32bppARGB);
  if (bitmap.GetLastStatus() != Gdiplus::Ok) {
    return E_FAIL;
  }
  Graphics graphics(&bitmap);
  const HRESULT draw_result =
      Draw(graphics, width_dip, height_dip, model, interaction);
  if (FAILED(draw_result)) {
    return draw_result;
  }
  CLSID png_encoder{};
  if (!GetPngEncoderClsid(&png_encoder) ||
      bitmap.Save(output_path.c_str(), &png_encoder, nullptr) != Gdiplus::Ok) {
    return E_FAIL;
  }
  return S_OK;
}

std::unique_ptr<Bitmap>
InstallerRenderer::LoadPngResource(int resource_id) const {
  HRSRC resource =
      FindResourceW(module_, MAKEINTRESOURCEW(resource_id), RT_RCDATA);
  if (resource == nullptr) {
    return nullptr;
  }
  HGLOBAL loaded = LoadResource(module_, resource);
  const DWORD size = SizeofResource(module_, resource);
  const void *bytes = loaded == nullptr ? nullptr : LockResource(loaded);
  if (bytes == nullptr || size == 0) {
    return nullptr;
  }
  HGLOBAL copy = GlobalAlloc(GMEM_MOVEABLE, size);
  if (copy == nullptr) {
    return nullptr;
  }
  void *destination = GlobalLock(copy);
  std::memcpy(destination, bytes, size);
  GlobalUnlock(copy);
  IStream *stream = nullptr;
  if (FAILED(CreateStreamOnHGlobal(copy, TRUE, &stream))) {
    GlobalFree(copy);
    return nullptr;
  }
  std::unique_ptr<Bitmap> decoded(Bitmap::FromStream(stream, FALSE));
  if (!decoded || decoded->GetLastStatus() != Gdiplus::Ok) {
    stream->Release();
    return nullptr;
  }
  auto clone = std::unique_ptr<Bitmap>(decoded->Clone(
      0, 0, decoded->GetWidth(), decoded->GetHeight(), PixelFormat32bppARGB));
  stream->Release();
  return clone;
}

HRESULT InstallerRenderer::Draw(Graphics &graphics, float width_dip,
                                float height_dip, const InstallerModel &model,
                                const InteractionState &interaction) {
  graphics.SetSmoothingMode(Gdiplus::SmoothingModeAntiAlias);
  graphics.SetInterpolationMode(Gdiplus::InterpolationModeHighQualityBicubic);
  graphics.SetTextRenderingHint(Gdiplus::TextRenderingHintClearTypeGridFit);
  graphics.Clear(kCanvas);

  const RectF full(0.0F, 0.0F, width_dip, height_dip);
  DrawTexture(graphics, lacquer_.get(), full, 0.46F);
  LinearGradientBrush veil(PointF(0.0F, 42.0F), PointF(width_dip, height_dip),
                           Color(215, 12, 11, 14), Color(235, 27, 17, 24));
  graphics.FillRectangle(&veil, 0.0F, 42.0F, width_dip, height_dip - 42.0F);

  const RectF title(0.0F, 0.0F, width_dip, 42.0F);
  DrawTexture(graphics, cedar_.get(), title, 0.82F);
  LinearGradientBrush title_shade(PointF(0.0F, 0.0F), PointF(width_dip, 42.0F),
                                  Color(216, 11, 13, 15),
                                  Color(245, 15, 10, 14));
  graphics.FillRectangle(&title_shade, title);
  Pen title_rule(
      Color(190, kRosewood.GetR(), kRosewood.GetG(), kRosewood.GetB()), 1.0F);
  graphics.DrawLine(&title_rule, 0.0F, 41.0F, width_dip, 41.0F);

  if (app_icon_) {
    graphics.DrawImage(app_icon_.get(), RectF(12.0F, 8.0F, 26.0F, 26.0F));
  }
  DrawText(graphics, L"Black Spirit Life Setup", L"Segoe UI", 12.0F,
           Gdiplus::FontStyleRegular, kWarmIvory,
           RectF(46.0F, 0.0F, 360.0F, 42.0F), Gdiplus::StringAlignmentNear,
           Gdiplus::StringAlignmentCenter);
  if (title_sprig_) {
    DrawTexture(graphics, title_sprig_.get(),
                RectF(width_dip - 320.0F, 9.0F, 205.0F, 28.0F), 0.82F);
  }

  const auto layout = CalculateLayout(width_dip, height_dip);
  const bool close_hovered =
      model.close_enabled() && interaction.hovered == InteractiveElement::close;
  const bool close_focused =
      model.close_enabled() && interaction.focused == InteractiveElement::close;
  if (close_hovered || close_focused) {
    SolidBrush close_fill(Color(70, 126, 44, 58));
    graphics.FillRectangle(&close_fill, ToRect(layout.close));
  }
  if (close_focused) {
    Pen focus_pen(kPaleBlossom, 1.4F);
    graphics.DrawRectangle(&focus_pen, layout.close.left + 4.5F,
                           layout.close.top + 4.5F,
                           layout.close.right - layout.close.left - 9.0F,
                           layout.close.bottom - layout.close.top - 9.0F);
  }
  Pen close_pen(close_hovered || close_focused ? kPaleBlossom
                : model.close_enabled()        ? kMutedText
                                               : kQuietText,
                1.5F);
  const float close_center_x = (layout.close.left + layout.close.right) / 2.0F;
  const float close_center_y = (layout.close.top + layout.close.bottom) / 2.0F;
  graphics.DrawLine(&close_pen, close_center_x - 6.0F, close_center_y - 6.0F,
                    close_center_x + 6.0F, close_center_y + 6.0F);
  graphics.DrawLine(&close_pen, close_center_x + 6.0F, close_center_y - 6.0F,
                    close_center_x - 6.0F, close_center_y + 6.0F);

  const RectF brand_panel(0.0F, 42.0F, 270.0F, height_dip - 42.0F);
  DrawTexture(graphics, cedar_.get(), brand_panel, 0.88F);
  LinearGradientBrush brand_shade(
      PointF(0.0F, 42.0F), PointF(270.0F, height_dip), Color(110, 13, 13, 16),
      Color(218, 17, 12, 16));
  graphics.FillRectangle(&brand_shade, brand_panel);
  Pen division(
      Color(170, kBarkCopper.GetR(), kBarkCopper.GetG(), kBarkCopper.GetB()),
      1.0F);
  graphics.DrawLine(&division, 269.0F, 42.0F, 269.0F, height_dip);
  Pen inner_division(
      Color(95, kDustySakura.GetR(), kDustySakura.GetG(), kDustySakura.GetB()),
      1.0F);
  graphics.DrawLine(&inner_division, 266.0F, 42.0F, 266.0F, height_dip);

  constexpr float brand_icon_y = 54.0F;
  constexpr float brand_icon_size = 104.0F;
  if (app_icon_) {
    graphics.DrawImage(app_icon_.get(),
                       RectF((270.0F - brand_icon_size) / 2.0F, brand_icon_y,
                             brand_icon_size, brand_icon_size));
  }
  DrawText(graphics, L"BLACK SPIRIT LIFE", L"Georgia", 16.0F,
           Gdiplus::FontStyleBold, kWarmIvory,
           RectF(30.0F, 170.0F, 210.0F, 28.0F),
           Gdiplus::StringAlignmentCenter);
  DrawText(graphics, L"FREE FAN TOOL", L"Segoe UI", 10.0F,
           Gdiplus::FontStyleBold, kDustySakura,
           RectF(30.0F, 202.0F, 210.0F, 20.0F),
           Gdiplus::StringAlignmentCenter);
  Pen brand_rule(kBarkCopper, 1.0F);
  constexpr float brand_rule_y = 238.0F;
  graphics.DrawLine(&brand_rule, 42.0F, brand_rule_y, 228.0F, brand_rule_y);
  if (title_sprig_) {
    DrawTexture(graphics, title_sprig_.get(),
                RectF(25.0F, height_dip - 104.0F, 220.0F, 54.0F), 0.88F);
  }

  const float content_x = 318.0F;
  constexpr float eyebrow_y = 56.0F;
  constexpr float heading_y = 82.0F;
  constexpr float summary_y = 130.0F;
  constexpr float path_label_y = 178.0F;
  DrawText(graphics, model.eyebrow(), L"Segoe UI", 10.0F,
           Gdiplus::FontStyleBold, kDustySakura,
           RectF(content_x, eyebrow_y, width_dip - content_x - 44.0F, 20.0F));
  DrawText(graphics, model.heading(), L"Georgia", 30.0F, Gdiplus::FontStyleBold,
           kWarmIvory,
           RectF(content_x, heading_y, width_dip - content_x - 44.0F, 48.0F));
  DrawWrappedText(
      graphics, model.summary(), L"Segoe UI", 12.5F, Gdiplus::FontStyleRegular,
      kMutedText,
      RectF(content_x, summary_y, width_dip - content_x - 44.0F, 38.0F));

  if (model.location_visible()) {
    DrawText(
        graphics,
        model.path_editable() ? L"INSTALL LOCATION" : L"INSTALLED LOCATION",
        L"Segoe UI", 9.5F, Gdiplus::FontStyleBold, kMutedText,
        RectF(content_x, path_label_y, 260.0F, 18.0F));

    const bool path_focused =
        interaction.focused == InteractiveElement::install_path;
    RectF path_rect = ToRect(layout.install_path);
    if (!model.path_editable()) {
      path_rect.Width = width_dip - 44.0F - path_rect.X;
    }
    LinearGradientBrush field_fill(PointF(path_rect.X, path_rect.Y),
                                   PointF(path_rect.X, path_rect.GetBottom()),
                                   Color(245, 24, 18, 23),
                                   Color(245, 14, 12, 16));
    FillRounded(graphics, path_rect, 6.0F, field_fill);
    StrokeRounded(graphics, path_rect, 6.0F,
                  path_focused ? kPaleBlossom : kRosewood,
                  path_focused ? 1.6F : 1.0F);
    DrawText(graphics, model.install_path, L"Segoe UI", 11.0F,
             Gdiplus::FontStyleRegular, kWarmIvory,
             RectF(path_rect.X + 14.0F, path_rect.Y, path_rect.Width - 28.0F,
                   path_rect.Height),
             Gdiplus::StringAlignmentNear, Gdiplus::StringAlignmentCenter);
    if (path_focused && interaction.caret_visible &&
        interaction.caret >= model.install_path.size()) {
      Gdiplus::RectF measured;
      FontFamily family(L"Segoe UI");
      Font font(&family, 11.0F, Gdiplus::FontStyleRegular, Gdiplus::UnitPixel);
      StringFormat format;
      format.SetFormatFlags(Gdiplus::StringFormatFlagsMeasureTrailingSpaces |
                            Gdiplus::StringFormatFlagsNoWrap);
      graphics.MeasureString(model.install_path.c_str(),
                             static_cast<INT>(model.install_path.size()), &font,
                             PointF(path_rect.X + 14.0F, path_rect.Y + 14.0F),
                             &format, &measured);
      Pen caret(kPaleBlossom, 1.0F);
      const float caret_x =
          std::min(measured.GetRight() + 1.0F, path_rect.GetRight() - 12.0F);
      graphics.DrawLine(&caret, caret_x, path_rect.Y + 12.0F, caret_x,
                        path_rect.GetBottom() - 12.0F);
    }
  }

  if (model.location_visible() && model.path_editable()) {
    const RectF browse_rect = ToRect(layout.browse);
    const bool browse_hovered =
        interaction.hovered == InteractiveElement::browse;
    const bool browse_focused =
        interaction.focused == InteractiveElement::browse;
    SolidBrush browse_fill(browse_hovered || browse_focused
                               ? Color(235, 60, 35, 47)
                               : Color(225, 40, 28, 35));
    FillRounded(graphics, browse_rect, 6.0F, browse_fill);
    StrokeRounded(graphics, browse_rect, 6.0F,
                  browse_focused   ? kPaleBlossom
                  : browse_hovered ? kDustySakura
                                   : kRosewood,
                  browse_focused ? 1.8F : 1.0F);
    DrawFolderGlyph(
        graphics,
        RectF(browse_rect.X + 23.0F, browse_rect.Y + 10.5F, 22.0F, 19.0F),
        browse_hovered || browse_focused ? kPaleBlossom : kDustySakura);
    DrawText(graphics, L"Browse", L"Segoe UI", 10.5F, Gdiplus::FontStyleBold,
             kWarmIvory,
             RectF(browse_rect.X + 52.0F, browse_rect.Y,
                   browse_rect.Width - 58.0F, browse_rect.Height),
             Gdiplus::StringAlignmentNear, Gdiplus::StringAlignmentCenter);
  }

  if (model.personal_data_choice_visible()) {
    const RectF choice = ToRect(layout.remove_personal_data);
    const bool choice_hovered =
        interaction.hovered == InteractiveElement::remove_personal_data;
    const bool choice_focused =
        interaction.focused == InteractiveElement::remove_personal_data;
    if (choice_hovered || choice_focused) {
      SolidBrush choice_fill(Color(150, 57, 32, 43));
      FillRounded(graphics, choice, 5.0F, choice_fill);
    }

    const RectF box(choice.X + 2.0F, choice.Y + 4.0F, 24.0F, 24.0F);
    SolidBrush box_fill(model.remove_personal_data ? kDustySakura
                                                   : Color(235, 18, 15, 19));
    FillRounded(graphics, box, 5.0F, box_fill);
    StrokeRounded(graphics, box, 5.0F,
                  choice_focused || choice_hovered ? kPaleBlossom
                                                   : kDustySakura,
                  1.3F);
    if (model.remove_personal_data) {
      Pen check(kWarmIvory, 2.1F);
      graphics.DrawLine(&check, box.X + 5.5F, box.Y + 12.5F,
                        box.X + 10.0F, box.Y + 17.0F);
      graphics.DrawLine(&check, box.X + 10.0F, box.Y + 17.0F,
                        box.X + 19.0F, box.Y + 7.0F);
    }
    DrawText(graphics, L"Also delete my planner data", L"Segoe UI", 11.2F,
             Gdiplus::FontStyleBold, kWarmIvory,
             RectF(choice.X + 38.0F, choice.Y, choice.Width - 44.0F,
                   choice.Height),
             Gdiplus::StringAlignmentNear,
             Gdiplus::StringAlignmentCenter);
  }

  if (model.phase == InstallerPhase::installing) {
    const RectF track(content_x, height_dip - 98.0F,
                      width_dip - content_x - 44.0F, 4.0F);
    SolidBrush track_fill(Color(155, 52, 35, 44));
    FillRounded(graphics, track, 2.0F, track_fill);
    const float travel = std::max(0.0F, track.Width - 124.0F);
    const float x = track.X + travel * interaction.animation_phase;
    LinearGradientBrush activity(
        PointF(x, track.Y), PointF(x + 124.0F, track.Y),
        Color(18, kDustySakura.GetR(), kDustySakura.GetG(),
              kDustySakura.GetB()),
        Color(235, kPaleBlossom.GetR(), kPaleBlossom.GetG(),
              kPaleBlossom.GetB()));
    FillRounded(graphics, RectF(x, track.Y, 124.0F, track.Height), 2.0F,
                activity);
  }

  if (!model.footer().empty()) {
    DrawText(graphics, model.footer(), L"Segoe UI", 9.5F,
             Gdiplus::FontStyleRegular, kQuietText,
             RectF(content_x, height_dip - 65.0F, 300.0F, 24.0F),
             Gdiplus::StringAlignmentNear, Gdiplus::StringAlignmentCenter);
  }
  if (model.secondary_visible()) {
    const RectF secondary = ToRect(layout.secondary);
    const bool secondary_hovered =
        interaction.hovered == InteractiveElement::secondary;
    const bool secondary_focused =
        interaction.focused == InteractiveElement::secondary;
    SolidBrush secondary_fill(
        secondary_hovered || secondary_focused ? Color(225, 68, 35, 45)
                                                : Color(205, 35, 25, 31));
    FillRounded(graphics, secondary, 6.0F, secondary_fill);
    StrokeRounded(graphics, secondary, 6.0F,
                  secondary_focused   ? kWarmIvory
                  : secondary_hovered ? kPaleBlossom
                                      : kRosewood,
                  secondary_focused ? 1.8F : 1.0F);
    DrawText(graphics, model.secondary_label(), L"Segoe UI", 10.8F,
             Gdiplus::FontStyleBold, kWarmIvory, secondary,
             Gdiplus::StringAlignmentCenter,
             Gdiplus::StringAlignmentCenter);
  }
  const RectF primary = ToRect(layout.primary);
  const bool primary_hovered =
      model.phase != InstallerPhase::installing &&
      interaction.hovered == InteractiveElement::primary;
  const bool primary_focused =
      model.phase != InstallerPhase::installing &&
      interaction.focused == InteractiveElement::primary;
  LinearGradientBrush primary_fill(
      PointF(primary.X, primary.Y), PointF(primary.X, primary.GetBottom()),
      model.phase == InstallerPhase::installing ? Color(255, 64, 47, 55)
      : primary_hovered || primary_focused      ? Color(255, 139, 66, 89)
                                                : Color(255, 112, 50, 69),
      model.phase == InstallerPhase::installing ? Color(255, 44, 34, 40)
      : primary_hovered || primary_focused      ? Color(255, 81, 37, 53)
                                                : Color(255, 64, 30, 43));
  FillRounded(graphics, primary, 6.0F, primary_fill);
  StrokeRounded(graphics, primary, 6.0F,
                primary_focused   ? kWarmIvory
                : primary_hovered ? kPaleBlossom
                                  : kDustySakura,
                primary_focused ? 2.0F : 1.3F);
  StrokeRounded(graphics,
                RectF(primary.X + 3.0F, primary.Y + 3.0F, primary.Width - 6.0F,
                      primary.Height - 6.0F),
                4.0F, Color(95, 247, 200, 215));
  DrawText(graphics, model.primary_label(), L"Segoe UI", 11.5F,
           Gdiplus::FontStyleBold, kWarmIvory, primary,
           Gdiplus::StringAlignmentCenter, Gdiplus::StringAlignmentCenter);

  Pen outer(kBarkCopper, 1.0F);
  graphics.DrawRectangle(&outer, 0.5F, 0.5F, width_dip - 1.0F,
                         height_dip - 1.0F);
  return S_OK;
}

} // namespace bsl::installer
