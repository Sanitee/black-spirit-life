#include "clipboard_image_reader.h"

#include <objidl.h>
#include <wincodec.h>
#include <wrl/client.h>

#include <array>
#include <cstddef>
#include <cstdint>
#include <limits>
#include <optional>
#include <utility>
#include <vector>

namespace clipboard_image_reader {
namespace {

using Microsoft::WRL::ComPtr;

constexpr std::array<uint8_t, 8> kPngSignature = {
    0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A};
// BI_ALPHABITFIELDS is part of the packed-DIB contract but is hidden by some
// Windows SDK target-version combinations used by Flutter's runner template.
constexpr DWORD kBiAlphaBitfields = 6;

class ScopedClipboard final {
 public:
  explicit ScopedClipboard(HWND owner) {
    // Screenshot utilities can still own the clipboard for a few milliseconds
    // after copying. A short bounded retry avoids making Paste feel flaky while
    // keeping the platform-channel call responsive.
    for (int attempt = 0; attempt < 4 && !open_; ++attempt) {
      open_ = OpenClipboard(owner) != FALSE;
      if (!open_) Sleep(2);
    }
  }

  ~ScopedClipboard() {
    if (open_) CloseClipboard();
  }

  ScopedClipboard(const ScopedClipboard&) = delete;
  ScopedClipboard& operator=(const ScopedClipboard&) = delete;

  bool is_open() const { return open_; }

 private:
  bool open_ = false;
};

class ScopedBitmap final {
 public:
  explicit ScopedBitmap(HBITMAP bitmap = nullptr) : bitmap_(bitmap) {}
  ~ScopedBitmap() {
    if (bitmap_ != nullptr) DeleteObject(bitmap_);
  }

  ScopedBitmap(const ScopedBitmap&) = delete;
  ScopedBitmap& operator=(const ScopedBitmap&) = delete;

  HBITMAP get() const { return bitmap_; }
  explicit operator bool() const { return bitmap_ != nullptr; }

 private:
  HBITMAP bitmap_;
};

bool HasPngSignature(const std::vector<uint8_t>& bytes) {
  if (bytes.size() < kPngSignature.size()) return false;
  for (size_t index = 0; index < kPngSignature.size(); ++index) {
    if (bytes[index] != kPngSignature[index]) return false;
  }
  return true;
}

std::optional<std::vector<uint8_t>> ReadDirectPng(UINT format) {
  if (format == 0 || IsClipboardFormatAvailable(format) == FALSE) {
    return std::nullopt;
  }
  const HGLOBAL payload =
      static_cast<HGLOBAL>(GetClipboardData(static_cast<UINT>(format)));
  if (payload == nullptr) return std::nullopt;

  const SIZE_T byte_count = GlobalSize(payload);
  if (byte_count == 0) return std::nullopt;
  const auto* data = static_cast<const uint8_t*>(GlobalLock(payload));
  if (data == nullptr) return std::nullopt;
  std::vector<uint8_t> bytes(data, data + byte_count);
  GlobalUnlock(payload);
  return HasPngSignature(bytes)
             ? std::optional<std::vector<uint8_t>>(std::move(bytes))
             : std::nullopt;
}

std::optional<size_t> DibPixelOffset(const BITMAPINFOHEADER& header,
                                     size_t payload_size) {
  if (header.biSize < sizeof(BITMAPINFOHEADER) ||
      header.biSize > payload_size || header.biPlanes != 1 ||
      header.biWidth <= 0 || header.biHeight == 0 || header.biBitCount == 0) {
    return std::nullopt;
  }
  if (header.biCompression != BI_RGB &&
      header.biCompression != BI_BITFIELDS &&
      header.biCompression != kBiAlphaBitfields) {
    return std::nullopt;
  }

  uint64_t offset = header.biSize;
  if (header.biSize == sizeof(BITMAPINFOHEADER)) {
    if (header.biCompression == BI_BITFIELDS) {
      offset += 3 * sizeof(DWORD);
    } else if (header.biCompression == kBiAlphaBitfields) {
      offset += 4 * sizeof(DWORD);
    }
  }

  uint64_t color_count = header.biClrUsed;
  if (color_count == 0 && header.biBitCount <= 8) {
    color_count = uint64_t{1} << header.biBitCount;
  }
  offset += color_count * sizeof(RGBQUAD);
  if (offset > payload_size) return std::nullopt;

  const uint64_t absolute_height = header.biHeight < 0
                                       ? -static_cast<int64_t>(header.biHeight)
                                       : header.biHeight;
  const uint64_t row_bytes =
      ((static_cast<uint64_t>(header.biWidth) * header.biBitCount + 31) / 32) *
      4;
  const uint64_t required_bytes =
      header.biSizeImage == 0 ? row_bytes * absolute_height
                              : header.biSizeImage;
  if (required_bytes > payload_size - offset) return std::nullopt;
  return static_cast<size_t>(offset);
}

HBITMAP CopyDibClipboardBitmap(UINT format) {
  if (IsClipboardFormatAvailable(format) == FALSE) return nullptr;
  const HGLOBAL payload = static_cast<HGLOBAL>(GetClipboardData(format));
  if (payload == nullptr) return nullptr;
  const SIZE_T payload_size = GlobalSize(payload);
  if (payload_size < sizeof(BITMAPINFOHEADER)) return nullptr;

  const auto* bytes = static_cast<const uint8_t*>(GlobalLock(payload));
  if (bytes == nullptr) return nullptr;
  const auto* header = reinterpret_cast<const BITMAPINFOHEADER*>(bytes);
  const auto pixel_offset = DibPixelOffset(*header, payload_size);
  HBITMAP bitmap = nullptr;
  if (pixel_offset.has_value()) {
    HDC screen = GetDC(nullptr);
    if (screen != nullptr) {
      bitmap = CreateDIBitmap(
          screen, header, CBM_INIT, bytes + pixel_offset.value(),
          reinterpret_cast<const BITMAPINFO*>(bytes), DIB_RGB_COLORS);
      ReleaseDC(nullptr, screen);
    }
  }
  GlobalUnlock(payload);
  return bitmap;
}

HBITMAP CopyClipboardBitmap() {
  if (IsClipboardFormatAvailable(CF_BITMAP) == FALSE) return nullptr;
  const auto bitmap = static_cast<HBITMAP>(GetClipboardData(CF_BITMAP));
  if (bitmap == nullptr) return nullptr;
  return static_cast<HBITMAP>(
      CopyImage(bitmap, IMAGE_BITMAP, 0, 0, LR_CREATEDIBSECTION));
}

std::optional<std::vector<uint8_t>> EncodeBitmapAsPng(HBITMAP bitmap) {
  if (bitmap == nullptr) return std::nullopt;

  ComPtr<IWICImagingFactory> factory;
  if (FAILED(CoCreateInstance(
          CLSID_WICImagingFactory, nullptr, CLSCTX_INPROC_SERVER,
          IID_PPV_ARGS(factory.ReleaseAndGetAddressOf())))) {
    return std::nullopt;
  }

  ComPtr<IWICBitmap> source;
  if (FAILED(factory->CreateBitmapFromHBITMAP(
          bitmap, nullptr, WICBitmapIgnoreAlpha,
          source.ReleaseAndGetAddressOf()))) {
    return std::nullopt;
  }

  ComPtr<IStream> stream;
  if (FAILED(CreateStreamOnHGlobal(nullptr, TRUE,
                                   stream.ReleaseAndGetAddressOf()))) {
    return std::nullopt;
  }

  ComPtr<IWICBitmapEncoder> encoder;
  if (FAILED(factory->CreateEncoder(GUID_ContainerFormatPng, nullptr,
                                    encoder.ReleaseAndGetAddressOf())) ||
      FAILED(encoder->Initialize(stream.Get(), WICBitmapEncoderNoCache))) {
    return std::nullopt;
  }

  ComPtr<IWICBitmapFrameEncode> frame;
  ComPtr<IPropertyBag2> properties;
  if (FAILED(encoder->CreateNewFrame(frame.ReleaseAndGetAddressOf(),
                                     properties.ReleaseAndGetAddressOf())) ||
      FAILED(frame->Initialize(properties.Get()))) {
    return std::nullopt;
  }

  UINT width = 0;
  UINT height = 0;
  if (FAILED(source->GetSize(&width, &height)) || width == 0 || height == 0 ||
      FAILED(frame->SetSize(width, height))) {
    return std::nullopt;
  }
  WICPixelFormatGUID pixel_format = GUID_WICPixelFormat32bppBGRA;
  if (FAILED(frame->SetPixelFormat(&pixel_format)) ||
      FAILED(frame->WriteSource(source.Get(), nullptr)) ||
      FAILED(frame->Commit()) || FAILED(encoder->Commit())) {
    return std::nullopt;
  }

  STATSTG stats{};
  if (FAILED(stream->Stat(&stats, STATFLAG_NONAME)) ||
      stats.cbSize.QuadPart == 0 ||
      stats.cbSize.QuadPart > std::numeric_limits<size_t>::max()) {
    return std::nullopt;
  }
  HGLOBAL encoded = nullptr;
  if (FAILED(GetHGlobalFromStream(stream.Get(), &encoded)) ||
      encoded == nullptr) {
    return std::nullopt;
  }
  const auto* data = static_cast<const uint8_t*>(GlobalLock(encoded));
  if (data == nullptr) return std::nullopt;
  const size_t byte_count = static_cast<size_t>(stats.cbSize.QuadPart);
  std::vector<uint8_t> bytes(data, data + byte_count);
  GlobalUnlock(encoded);
  return HasPngSignature(bytes)
             ? std::optional<std::vector<uint8_t>>(std::move(bytes))
             : std::nullopt;
}

}  // namespace

std::optional<std::vector<uint8_t>> ReadPng(HWND owner) {
  HBITMAP clipboard_bitmap = nullptr;
  {
    ScopedClipboard clipboard(owner);
    if (!clipboard.is_open()) return std::nullopt;

    const UINT png_format = RegisterClipboardFormatW(L"PNG");
    if (auto png = ReadDirectPng(png_format); png.has_value()) return png;

    clipboard_bitmap = CopyDibClipboardBitmap(CF_DIBV5);
    if (clipboard_bitmap == nullptr) {
      clipboard_bitmap = CopyDibClipboardBitmap(CF_DIB);
    }
    if (clipboard_bitmap == nullptr) {
      clipboard_bitmap = CopyClipboardBitmap();
    }
  }
  ScopedBitmap copied_bitmap(clipboard_bitmap);
  return copied_bitmap ? EncodeBitmapAsPng(copied_bitmap.get())
                       : std::nullopt;
}

}  // namespace clipboard_image_reader
