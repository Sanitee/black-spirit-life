#include "active_node_video_scanner.h"

#include <mfapi.h>
#include <mferror.h>
#include <mfidl.h>
#include <mfreadwrite.h>
#include <propvarutil.h>
#include <shlobj.h>
#include <wincodec.h>
#include <wrl/client.h>

#include <winrt/Windows.Foundation.h>
#include <winrt/Windows.Foundation.Collections.h>
#include <winrt/Windows.Globalization.h>
#include <winrt/Windows.Graphics.Imaging.h>
#include <winrt/Windows.Media.Ocr.h>

#include <algorithm>
#include <atomic>
#include <array>
#include <chrono>
#include <cctype>
#include <cmath>
#include <filesystem>
#include <limits>
#include <mutex>
#include <string_view>
#include <thread>
#include <utility>

namespace active_node_video_scanner {
namespace {

using Microsoft::WRL::ComPtr;
using winrt::Windows::Foundation::IMemoryBufferReference;
using winrt::Windows::Globalization::Language;
using winrt::Windows::Graphics::Imaging::BitmapAlphaMode;
using winrt::Windows::Graphics::Imaging::BitmapBufferAccessMode;
using winrt::Windows::Graphics::Imaging::BitmapPixelFormat;
using winrt::Windows::Graphics::Imaging::SoftwareBitmap;
using winrt::Windows::Media::Ocr::OcrEngine;

constexpr std::int64_t kHundredNanosecondsPerMillisecond = 10000;
constexpr DWORD kFirstVideoStream =
    static_cast<DWORD>(MF_SOURCE_READER_FIRST_VIDEO_STREAM);
constexpr DWORD kMediaSource =
    static_cast<DWORD>(MF_SOURCE_READER_MEDIASOURCE);

HRESULT EnsureMediaFoundationStarted() {
  // Media Foundation is process-wide. Starting and shutting it down around
  // every individual scan can deadlock while a hardware video transform is
  // winding down, even though every sampled frame and OCR result is already
  // complete. Keep the single startup alive for this private desktop process;
  // Windows reclaims it with the process, and subsequent imports reuse it.
  static std::once_flag startup_once;
  static HRESULT startup_result = E_UNEXPECTED;
  std::call_once(startup_once, []() {
    startup_result = MFStartup(MF_VERSION, MFSTARTUP_LITE);
  });
  return startup_result;
}

struct PropVariantLifetime {
  PropVariantLifetime() { PropVariantInit(&value); }
  ~PropVariantLifetime() { PropVariantClear(&value); }
  PROPVARIANT value{};
};

struct FramePixels {
  int width = 0;
  int height = 0;
  std::int64_t timestamp_milliseconds = 0;
  double sharpness = 0;
  std::vector<std::uint8_t> bgra;
};

std::string WideToUtf8(std::wstring_view value) {
  if (value.empty()) return {};
  const int size = WideCharToMultiByte(
      CP_UTF8, 0, value.data(), static_cast<int>(value.size()), nullptr, 0,
      nullptr, nullptr);
  if (size <= 0) return {};
  std::string output(size, '\0');
  WideCharToMultiByte(CP_UTF8, 0, value.data(),
                      static_cast<int>(value.size()), output.data(), size,
                      nullptr, nullptr);
  return output;
}

std::string HResultMessage(HRESULT result) {
  wchar_t* message = nullptr;
  const DWORD length = FormatMessageW(
      FORMAT_MESSAGE_ALLOCATE_BUFFER | FORMAT_MESSAGE_FROM_SYSTEM |
          FORMAT_MESSAGE_IGNORE_INSERTS,
      nullptr, static_cast<DWORD>(result), 0,
      reinterpret_cast<wchar_t*>(&message), 0, nullptr);
  std::string output = length == 0 || message == nullptr
                           ? "Windows error " + std::to_string(result)
                           : WideToUtf8(std::wstring_view(message, length));
  if (message != nullptr) LocalFree(message);
  while (!output.empty() &&
         (output.back() == '\r' || output.back() == '\n' ||
          output.back() == ' ')) {
    output.pop_back();
  }
  return output;
}

ScanResult Failure(std::string code, std::string message,
                   const std::wstring& path) {
  ScanResult result;
  result.error_code = std::move(code);
  result.error_message = std::move(message);
  result.source_path = WideToUtf8(path);
  return result;
}

double ComputeSharpness(const std::vector<std::uint8_t>& bgra, int width,
                        int height) {
  if (width < 3 || height < 3 ||
      bgra.size() < static_cast<std::size_t>(width * height * 4)) {
    return 0;
  }
  double gradient_sum = 0;
  std::size_t samples = 0;
  const int step = std::max(1, std::min(width, height) / 360);
  const auto luminance = [&](int x, int y) {
    const auto index = static_cast<std::size_t>((y * width + x) * 4);
    return (29 * static_cast<int>(bgra[index]) +
            150 * static_cast<int>(bgra[index + 1]) +
            77 * static_cast<int>(bgra[index + 2])) /
           256;
  };
  for (int y = step; y < height; y += step) {
    for (int x = step; x < width; x += step) {
      const int center = luminance(x, y);
      gradient_sum += std::abs(center - luminance(x - step, y));
      gradient_sum += std::abs(center - luminance(x, y - step));
      samples += 2;
    }
  }
  return samples == 0 ? 0 : gradient_sum / (255.0 * samples);
}

HRESULT CopySamplePixels(IMFSample* media_frame, int width, int height,
                         FramePixels* output) {
  if (media_frame == nullptr || output == nullptr) return E_INVALIDARG;
  ComPtr<IMFMediaBuffer> buffer;
  HRESULT result = media_frame->ConvertToContiguousBuffer(&buffer);
  if (FAILED(result)) return result;

  output->width = width;
  output->height = height;
  output->bgra.assign(static_cast<std::size_t>(width * height * 4), 0);

  ComPtr<IMF2DBuffer> two_dimensional;
  if (SUCCEEDED(buffer.As(&two_dimensional))) {
    BYTE* scanline_zero = nullptr;
    LONG pitch = 0;
    result = two_dimensional->Lock2D(&scanline_zero, &pitch);
    if (FAILED(result)) return result;
    const auto unlock = [&] { two_dimensional->Unlock2D(); };
    if (scanline_zero == nullptr || std::abs(pitch) < width * 4) {
      unlock();
      return E_UNEXPECTED;
    }
    for (int y = 0; y < height; ++y) {
      const BYTE* source = scanline_zero + static_cast<std::ptrdiff_t>(y) * pitch;
      std::copy_n(source, static_cast<std::size_t>(width * 4),
                  output->bgra.data() +
                      static_cast<std::size_t>(y * width * 4));
    }
    unlock();
    return S_OK;
  }

  BYTE* data = nullptr;
  DWORD maximum_length = 0;
  DWORD current_length = 0;
  result = buffer->Lock(&data, &maximum_length, &current_length);
  if (FAILED(result)) return result;
  const std::size_t required = static_cast<std::size_t>(width * height * 4);
  if (data == nullptr || current_length < required) {
    buffer->Unlock();
    return E_UNEXPECTED;
  }
  // The RGB32 Source Reader output is conventionally bottom-up when it does
  // not expose IMF2DBuffer. Flip it into the top-down orientation expected by
  // SoftwareBitmap and OCR.
  for (int y = 0; y < height; ++y) {
    const BYTE* source = data +
                         static_cast<std::size_t>((height - 1 - y) * width * 4);
    std::copy_n(source, static_cast<std::size_t>(width * 4),
                output->bgra.data() + static_cast<std::size_t>(y * width * 4));
  }
  buffer->Unlock();
  return S_OK;
}

double OcrBitmapScale(const FramePixels& frame,
                      double maximum_requested_scale = 2.25) {
  const int maximum_dimension = static_cast<int>(OcrEngine::MaxImageDimension());
  return std::min(
      maximum_requested_scale,
      std::min(maximum_dimension / static_cast<double>(frame.width),
               maximum_dimension / static_cast<double>(frame.height)));
}

enum class OcrPreprocessMode {
  kAdaptiveGrayscale,
  kLightGlyphs,
};

SoftwareBitmap BuildOcrBitmap(const FramePixels& frame,
                              double maximum_requested_scale = 2.25,
                              OcrPreprocessMode preprocess_mode =
                                  OcrPreprocessMode::kAdaptiveGrayscale) {
  const double scale = OcrBitmapScale(frame, maximum_requested_scale);
  const int width = std::max(1, static_cast<int>(std::round(frame.width * scale)));
  const int height =
      std::max(1, static_cast<int>(std::round(frame.height * scale)));
  SoftwareBitmap bitmap(BitmapPixelFormat::Bgra8, width, height,
                        BitmapAlphaMode::Ignore);
  auto bitmap_buffer = bitmap.LockBuffer(BitmapBufferAccessMode::Write);
  IMemoryBufferReference reference = bitmap_buffer.CreateReference();
  BYTE* destination = reference.data();
  const UINT32 capacity = reference.Capacity();
  const auto plane = bitmap_buffer.GetPlaneDescription(0);
  if (destination == nullptr || plane.StartIndex < 0 ||
      plane.Stride < width * 4) {
    throw winrt::hresult_error(E_UNEXPECTED, L"SoftwareBitmap buffer too small");
  }
  const auto last_row_end =
      static_cast<std::size_t>(plane.StartIndex) +
      static_cast<std::size_t>(height - 1) *
          static_cast<std::size_t>(plane.Stride) +
      static_cast<std::size_t>(width * 4);
  if (capacity < last_row_end) {
    throw winrt::hresult_error(E_UNEXPECTED, L"SoftwareBitmap buffer too small");
  }

  double luminance_sum = 0;
  const auto source_pixels = static_cast<std::size_t>(frame.width * frame.height);
  for (std::size_t index = 0; index < source_pixels; ++index) {
    const auto offset = index * 4;
    luminance_sum +=
        (29 * frame.bgra[offset] + 150 * frame.bgra[offset + 1] +
         77 * frame.bgra[offset + 2]) /
        256.0;
  }
  const bool invert = source_pixels > 0 &&
                      luminance_sum / static_cast<double>(source_pixels) < 138;

  for (int y = 0; y < height; ++y) {
    const int source_y = std::min(
        frame.height - 1, static_cast<int>(std::floor(y / scale)));
    for (int x = 0; x < width; ++x) {
      const int source_x = std::min(
          frame.width - 1, static_cast<int>(std::floor(x / scale)));
      const auto source =
          static_cast<std::size_t>((source_y * frame.width + source_x) * 4);
      const int blue = frame.bgra[source];
      const int green = frame.bgra[source + 1];
      const int red = frame.bgra[source + 2];
      int value = (29 * blue + 150 * green + 77 * red) / 256;
      if (preprocess_mode == OcrPreprocessMode::kLightGlyphs) {
        const int chroma =
            std::max({red, green, blue}) - std::min({red, green, blue});
        value = value >= 145 && chroma <= 92 ? 0 : 255;
      } else {
        if (invert) value = 255 - value;
        value =
            std::clamp(static_cast<int>((value - 128) * 1.28 + 128), 0, 255);
      }
      const auto target = static_cast<std::size_t>(plane.StartIndex) +
                          static_cast<std::size_t>(y) *
                              static_cast<std::size_t>(plane.Stride) +
                          static_cast<std::size_t>(x * 4);
      destination[target] = static_cast<BYTE>(value);
      destination[target + 1] = static_cast<BYTE>(value);
      destination[target + 2] = static_cast<BYTE>(value);
      destination[target + 3] = 255;
    }
  }
  return bitmap;
}

OcrFrame RecognizeFrame(const FramePixels& frame, int index,
                        const OcrEngine& engine) {
  OcrFrame output;
  output.index = index;
  output.timestamp_milliseconds = frame.timestamp_milliseconds;
  output.sharpness = frame.sharpness;
  const SoftwareBitmap bitmap = BuildOcrBitmap(frame);
  const auto recognized = engine.RecognizeAsync(bitmap).get();
  for (const auto& line : recognized.Lines()) {
    OcrLine parsed;
    parsed.text = WideToUtf8(line.Text().c_str());
    bool has_bounds = false;
    float left = std::numeric_limits<float>::max();
    float top = std::numeric_limits<float>::max();
    float right = 0;
    float bottom = 0;
    for (const auto& word : line.Words()) {
      const auto bounds = word.BoundingRect();
      has_bounds = true;
      left = std::min(left, bounds.X);
      top = std::min(top, bounds.Y);
      right = std::max(right, bounds.X + bounds.Width);
      bottom = std::max(bottom, bounds.Y + bounds.Height);
    }
    if (has_bounds) {
      parsed.left = left;
      parsed.top = top;
      parsed.width = std::max(0.0f, right - left);
      parsed.height = std::max(0.0f, bottom - top);
    }
    if (!parsed.text.empty()) output.lines.push_back(std::move(parsed));
  }
  return output;
}

OcrFrame RecognizeImageWords(const FramePixels& frame,
                             const OcrEngine& engine,
                             double maximum_requested_scale = 2.25,
                             double source_left = 0,
                             double source_top = 0,
                             OcrPreprocessMode preprocess_mode =
                                 OcrPreprocessMode::kAdaptiveGrayscale) {
  OcrFrame output;
  output.sharpness = frame.sharpness;
  const SoftwareBitmap bitmap =
      BuildOcrBitmap(frame, maximum_requested_scale, preprocess_mode);
  const double scale = OcrBitmapScale(frame, maximum_requested_scale);
  const auto recognized = engine.RecognizeAsync(bitmap).get();
  for (const auto& line : recognized.Lines()) {
    for (const auto& word : line.Words()) {
      const auto text = WideToUtf8(word.Text().c_str());
      if (text.empty()) continue;
      const auto bounds = word.BoundingRect();
      output.lines.push_back(OcrLine{
          text,
          source_left + bounds.X / scale,
          source_top + bounds.Y / scale,
          bounds.Width / scale,
          bounds.Height / scale,
      });
    }
  }
  return output;
}

FramePixels CropFrame(const FramePixels& source, int left, int top, int width,
                      int height) {
  FramePixels output;
  output.width = width;
  output.height = height;
  output.timestamp_milliseconds = source.timestamp_milliseconds;
  output.bgra.resize(static_cast<std::size_t>(width * height * 4));
  for (int y = 0; y < height; ++y) {
    const auto source_offset =
        static_cast<std::size_t>(((top + y) * source.width + left) * 4);
    const auto target_offset = static_cast<std::size_t>(y * width * 4);
    std::copy_n(source.bgra.data() + source_offset,
                static_cast<std::size_t>(width * 4),
                output.bgra.data() + target_offset);
  }
  output.sharpness = ComputeSharpness(output.bgra, width, height);
  return output;
}

struct StillImageTile {
  int left = 0;
  int top = 0;
  int width = 0;
  int height = 0;
};

std::vector<StillImageTile> BuildStillImageTiles(int width, int height) {
  // Storage screenshots may be small crops or full game windows. Keep the
  // number of OCR calls bounded while giving tiny outlined quantities a much
  // larger effective font than the full-image pass can provide.
  const int columns = width < 700 ? 1 : width < 1600 ? 2 : width < 3000 ? 3 : 4;
  const int rows = height < 500 ? 1 : height < 1200 ? 2 : height < 2000 ? 3 : 4;
  const int horizontal_overlap = std::clamp(width / 28, 24, 96);
  const int vertical_overlap = std::clamp(height / 28, 20, 80);
  std::vector<StillImageTile> output;
  output.reserve(static_cast<std::size_t>(columns * rows));
  for (int row = 0; row < rows; ++row) {
    const int base_top = height * row / rows;
    const int base_bottom = height * (row + 1) / rows;
    const int top = std::max(0, base_top - (row == 0 ? 0 : vertical_overlap));
    const int bottom =
        std::min(height, base_bottom + (row + 1 == rows ? 0 : vertical_overlap));
    for (int column = 0; column < columns; ++column) {
      const int base_left = width * column / columns;
      const int base_right = width * (column + 1) / columns;
      const int left =
          std::max(0, base_left - (column == 0 ? 0 : horizontal_overlap));
      const int right = std::min(
          width, base_right + (column + 1 == columns ? 0 : horizontal_overlap));
      output.push_back(StillImageTile{left, top, right - left, bottom - top});
    }
  }
  return output;
}

bool LooksLikeQuantityFragment(std::string text) {
  text.erase(std::remove_if(text.begin(), text.end(), [](unsigned char value) {
               return std::isspace(value) != 0;
             }),
             text.end());
  if (text.empty() || text.front() == '+' || text.find('/') != std::string::npos) {
    return false;
  }
  if ((text.front() == '-' || text.front() == '_') && text.size() > 1) {
    text.erase(text.begin());
  }
  bool has_digit = false;
  for (char value : text) {
    const char upper = static_cast<char>(
        std::toupper(static_cast<unsigned char>(value)));
    if (upper >= '0' && upper <= '9') {
      has_digit = true;
      continue;
    }
    if (upper != 'O' && upper != 'I' && upper != 'L' && upper != '.' &&
        upper != ',' && upper != 'K' && upper != 'M' && upper != 'B') {
      return false;
    }
  }
  return has_digit;
}

std::vector<StillImageTile> BuildQuantityBands(const FramePixels& source,
                                               const OcrFrame& recognized) {
  struct QuantityAnchor {
    double left = 0;
    double right = 0;
    double top = 0;
    double height = 0;
  };
  std::vector<QuantityAnchor> anchors;
  for (const auto& line : recognized.lines) {
    if (!LooksLikeQuantityFragment(line.text)) continue;
    anchors.push_back(QuantityAnchor{line.left, line.left + line.width,
                                     line.top, line.height});
  }
  if (anchors.size() < 6) return {};
  std::sort(anchors.begin(), anchors.end(), [](const auto& left,
                                                const auto& right) {
    return left.top < right.top;
  });

  std::vector<std::vector<QuantityAnchor>> rows;
  for (const auto& anchor : anchors) {
    std::vector<QuantityAnchor>* target = nullptr;
    const double center = anchor.top + anchor.height / 2;
    for (auto& row : rows) {
      const double row_center = row.front().top + row.front().height / 2;
      if (std::abs(row_center - center) <=
          std::max(5.0, std::min(row.front().height, anchor.height) * 0.85)) {
        target = &row;
        break;
      }
    }
    if (target == nullptr) {
      rows.push_back({});
      target = &rows.back();
    }
    target->push_back(anchor);
  }

  std::vector<double> row_tops;
  std::vector<double> row_heights;
  double left = static_cast<double>(source.width);
  double right = 0;
  for (const auto& anchor : anchors) {
    left = std::min(left, anchor.left);
    right = std::max(right, anchor.right);
  }
  for (auto& row : rows) {
    if (row.size() < 3) continue;
    std::sort(row.begin(), row.end(), [](const auto& left,
                                         const auto& right) {
      return left.top < right.top;
    });
    row_tops.push_back(row[row.size() / 2].top);
    row_heights.push_back(row[row.size() / 2].height);
  }
  if (row_tops.size() < 2 || right - left < 90) return {};
  std::sort(row_tops.begin(), row_tops.end());
  std::sort(row_heights.begin(), row_heights.end());
  std::vector<double> vertical_steps;
  for (std::size_t index = 1; index < rows.size(); ++index) {
    const double previous = rows[index - 1].front().top;
    const double current = rows[index].front().top;
    const double difference = current - previous;
    if (difference >= 28 && difference <= 96) {
      vertical_steps.push_back(difference);
    }
  }
  if (vertical_steps.empty()) return {};
  std::sort(vertical_steps.begin(), vertical_steps.end());
  const double step = vertical_steps[vertical_steps.size() / 2];
  const double line_height = row_heights[row_heights.size() / 2];
  const int band_left = std::max(0, static_cast<int>(std::floor(left - 10)));
  const int band_right = std::min(
      source.width, static_cast<int>(std::ceil(right + 8)));
  const double first_top = row_tops.front() - step;
  const double last_top = row_tops.back() + step;
  std::vector<StillImageTile> output;
  for (double top = first_top; top <= last_top + step * 0.2; top += step) {
    const int band_top = std::max(0, static_cast<int>(std::floor(top - 4)));
    const int band_bottom = std::min(
        source.height,
        static_cast<int>(std::ceil(top + std::max(12.0, line_height) + 5)));
    if (band_right - band_left < 90 || band_bottom - band_top < 10) continue;
    output.push_back(StillImageTile{band_left, band_top,
                                    band_right - band_left,
                                    band_bottom - band_top});
    if (output.size() >= 16) break;
  }
  return output;
}

OcrEngine CreateOcrEngine() {
  OcrEngine engine{nullptr};
  const Language english(L"en-US");
  if (OcrEngine::IsLanguageSupported(english)) {
    engine = OcrEngine::TryCreateFromLanguage(english);
  }
  if (!engine) engine = OcrEngine::TryCreateFromUserProfileLanguages();
  return engine;
}

std::optional<std::filesystem::path> EnvironmentPath(const wchar_t* name) {
  const DWORD required = GetEnvironmentVariableW(name, nullptr, 0);
  if (required == 0) return std::nullopt;
  std::wstring value(required, L'\0');
  if (GetEnvironmentVariableW(name, value.data(), required) == 0) {
    return std::nullopt;
  }
  if (!value.empty() && value.back() == L'\0') value.pop_back();
  return value.empty() ? std::nullopt
                       : std::optional<std::filesystem::path>(value);
}

std::int64_t FileModifiedUnixMilliseconds(
    const std::filesystem::file_time_type& time) {
  const auto system_time = std::chrono::time_point_cast<
      std::chrono::system_clock::duration>(time -
                                           std::filesystem::file_time_type::clock::now() +
                                           std::chrono::system_clock::now());
  return std::chrono::duration_cast<std::chrono::milliseconds>(
             system_time.time_since_epoch())
      .count();
}

void ConsiderRecordingsIn(const std::filesystem::path& directory,
                          std::int64_t modified_after,
                          std::optional<std::filesystem::path>* newest_path,
                          std::int64_t* newest_time) {
  std::error_code error;
  if (!std::filesystem::is_directory(directory, error)) return;
  for (const auto& entry : std::filesystem::directory_iterator(directory, error)) {
    if (error || !entry.is_regular_file(error)) continue;
    std::wstring extension = entry.path().extension().wstring();
    std::transform(extension.begin(), extension.end(), extension.begin(),
                   towlower);
    if (extension != L".mp4") continue;
    const auto write_time = entry.last_write_time(error);
    if (error) continue;
    const auto milliseconds = FileModifiedUnixMilliseconds(write_time);
    if (milliseconds < modified_after || milliseconds <= *newest_time) continue;
    *newest_time = milliseconds;
    *newest_path = entry.path();
  }
}

}  // namespace

ScanResult ScanImage(const std::wstring& path,
                     ScanProgressCallback progress_callback,
                     ScanResultReadyCallback result_ready_callback) {
  const auto finish = [&](ScanResult result) {
    if (result_ready_callback) result_ready_callback(result);
    return result;
  };
  const auto report_progress = [&](double fraction, int completed_frames) {
    if (!progress_callback) return;
    progress_callback(ScanProgress{
        std::clamp(fraction, 0.0, 1.0), completed_frames, 1});
  };
  report_progress(0.02, 0);
  if (path.empty()) {
    return finish(Failure("invalid_path", "No screenshot was selected.", path));
  }
  std::error_code file_error;
  if (!std::filesystem::is_regular_file(path, file_error) || file_error) {
    return finish(Failure("file_not_found",
                          "The selected screenshot no longer exists.", path));
  }
  const auto byte_count = std::filesystem::file_size(path, file_error);
  if (file_error || byte_count == 0 || byte_count > 40ULL * 1024ULL * 1024ULL) {
    return finish(Failure(
        "image_too_large",
        "Choose a PNG, JPEG, or WebP screenshot smaller than 40 MB.", path));
  }

  try {
    winrt::init_apartment(winrt::apartment_type::multi_threaded);
    ComPtr<IWICImagingFactory> factory;
    HRESULT result = CoCreateInstance(
        CLSID_WICImagingFactory, nullptr, CLSCTX_INPROC_SERVER,
        IID_PPV_ARGS(&factory));
    if (FAILED(result)) {
      return finish(
          Failure("image_decoder_unavailable", HResultMessage(result), path));
    }
    ComPtr<IWICBitmapDecoder> decoder;
    result = factory->CreateDecoderFromFilename(
        path.c_str(), nullptr, GENERIC_READ, WICDecodeMetadataCacheOnLoad,
        &decoder);
    if (FAILED(result)) {
      return finish(Failure(
          "unsupported_image",
          "Windows could not decode that screenshot as PNG, JPEG, or WebP.",
          path));
    }
    ComPtr<IWICBitmapFrameDecode> frame;
    result = decoder->GetFrame(0, &frame);
    if (FAILED(result)) {
      return finish(Failure("image_decode_failed", HResultMessage(result),
                            path));
    }
    UINT width = 0;
    UINT height = 0;
    result = frame->GetSize(&width, &height);
    const std::uint64_t pixels =
        static_cast<std::uint64_t>(width) * static_cast<std::uint64_t>(height);
    if (FAILED(result) || width == 0 || height == 0 || width > 12000 ||
        height > 12000 || pixels > 100000000ULL) {
      return finish(Failure(
          "invalid_image_size",
          "That screenshot has unsupported dimensions. Crop it to the BDO "
          "storage or inventory window and try again.",
          path));
    }
    ComPtr<IWICFormatConverter> converter;
    result = factory->CreateFormatConverter(&converter);
    if (SUCCEEDED(result)) {
      result = converter->Initialize(
          frame.Get(), GUID_WICPixelFormat32bppBGRA, WICBitmapDitherTypeNone,
          nullptr, 0.0, WICBitmapPaletteTypeCustom);
    }
    if (FAILED(result)) {
      return finish(Failure("image_decode_failed", HResultMessage(result),
                            path));
    }
    report_progress(0.20, 0);

    FramePixels pixels_frame;
    pixels_frame.width = static_cast<int>(width);
    pixels_frame.height = static_cast<int>(height);
    const UINT stride = width * 4;
    const UINT buffer_size = stride * height;
    pixels_frame.bgra.resize(buffer_size);
    result = converter->CopyPixels(nullptr, stride, buffer_size,
                                   pixels_frame.bgra.data());
    if (FAILED(result)) {
      return finish(Failure("image_decode_failed", HResultMessage(result),
                            path));
    }
    pixels_frame.sharpness = ComputeSharpness(
        pixels_frame.bgra, pixels_frame.width, pixels_frame.height);
    report_progress(0.42, 0);

    OcrEngine engine = CreateOcrEngine();
    if (!engine) {
      return finish(Failure(
          "ocr_language_unavailable",
          "Windows OCR is unavailable. Install the English Windows language "
          "OCR capability, then try again.",
          path));
    }
    ScanResult output;
    output.source_path = WideToUtf8(path);
    output.ocr_language =
        WideToUtf8(engine.RecognizerLanguage().LanguageTag());
    output.source_width = pixels_frame.width;
    output.source_height = pixels_frame.height;
    output.frames.push_back(RecognizeImageWords(pixels_frame, engine));
    const auto tiles = BuildStillImageTiles(pixels_frame.width,
                                            pixels_frame.height);
    for (std::size_t index = 0; index < tiles.size(); ++index) {
      const auto& tile = tiles[index];
      FramePixels cropped = CropFrame(pixels_frame, tile.left, tile.top,
                                      tile.width, tile.height);
      OcrFrame recognized = RecognizeImageWords(
          cropped, engine, 5.25, static_cast<double>(tile.left),
          static_cast<double>(tile.top));
      recognized.index = static_cast<int>(index + 1);
      output.frames.push_back(std::move(recognized));
      report_progress(
          0.55 + 0.40 * (static_cast<double>(index + 1) / tiles.size()),
          static_cast<int>(index + 2));
    }
    const auto quantity_bands =
        BuildQuantityBands(pixels_frame, output.frames.front());
    constexpr std::array<OcrPreprocessMode, 2> kQuantityModes = {
        OcrPreprocessMode::kAdaptiveGrayscale,
        OcrPreprocessMode::kLightGlyphs,
    };
    const std::size_t quantity_passes =
        quantity_bands.size() * kQuantityModes.size();
    std::size_t completed_quantity_passes = 0;
    for (const auto mode : kQuantityModes) {
      for (const auto& band : quantity_bands) {
        FramePixels cropped = CropFrame(pixels_frame, band.left, band.top,
                                        band.width, band.height);
        OcrFrame recognized = RecognizeImageWords(
            cropped, engine, 8.0, static_cast<double>(band.left),
            static_cast<double>(band.top), mode);
        recognized.index = static_cast<int>(
            tiles.size() + completed_quantity_passes + 1);
        output.frames.push_back(std::move(recognized));
        ++completed_quantity_passes;
        report_progress(
            0.95 + 0.04 * (static_cast<double>(completed_quantity_passes) /
                           std::max<std::size_t>(1, quantity_passes)),
            static_cast<int>(tiles.size() + completed_quantity_passes + 1));
      }
    }
    output.success = true;
    output.diagnostics.push_back(
        "Windows Imaging Component decoded one still image. Windows OCR read "
        "one full-image pass plus bounded enlarged overlapping sections and "
        "isolated quantity bands in the scanner process.");
    return finish(std::move(output));
  } catch (const winrt::hresult_error& error) {
    return finish(Failure("ocr_failed",
                          WideToUtf8(error.message().c_str()), path));
  } catch (const std::exception& error) {
    return finish(Failure("image_scan_failed", error.what(), path));
  }
}

ScanResult Scan(const std::wstring& path,
                ScanProgressCallback progress_callback,
                std::int64_t preferred_interval_milliseconds,
                int maximum_frames,
                ScanResultReadyCallback result_ready_callback) {
  const auto finish = [&](ScanResult result) {
    // Deliver the small OCR result while decoder and WinRT objects are still
    // alive. Some Windows video drivers can wait indefinitely while those
    // objects are released; that cleanup must never hold the Flutter review
    // hostage after recognition is already complete.
    if (result_ready_callback) result_ready_callback(result);
    return result;
  };
  const auto report_progress = [&](double fraction, int completed_frames,
                                   int estimated_frames) {
    if (!progress_callback) return;
    progress_callback(ScanProgress{
        std::clamp(fraction, 0.0, 1.0), completed_frames, estimated_frames});
  };
  report_progress(0.01, 0, maximum_frames);
  if (path.empty()) {
    return finish(Failure("invalid_path", "No MP4 was selected.", path));
  }
  if (maximum_frames < 1 || maximum_frames > 240) maximum_frames = 32;
  if (preferred_interval_milliseconds < 250) {
    preferred_interval_milliseconds = 250;
  }

  std::error_code file_error;
  if (!std::filesystem::is_regular_file(path, file_error)) {
    return finish(Failure(
        "file_not_found", "The selected recording no longer exists.", path));
  }
  auto previous_size = std::filesystem::file_size(path, file_error);
  auto previous_write = std::filesystem::last_write_time(path, file_error);
  bool file_ready = !file_error && previous_size > 0 &&
                    std::filesystem::file_time_type::clock::now() -
                            previous_write >=
                        std::chrono::milliseconds(750);
  int stable_checks = 0;
  for (int check = 0; !file_ready && check < 40; ++check) {
    std::this_thread::sleep_for(std::chrono::milliseconds(100));
    const auto current_size = std::filesystem::file_size(path, file_error);
    const auto current_write =
        std::filesystem::last_write_time(path, file_error);
    if (file_error) break;
    if (current_size > 0 && current_size == previous_size &&
        current_write == previous_write) {
      ++stable_checks;
    } else {
      stable_checks = 0;
    }
    previous_size = current_size;
    previous_write = current_write;
    const auto age = std::filesystem::file_time_type::clock::now() -
                     current_write;
    file_ready = stable_checks >= 3 && age >= std::chrono::milliseconds(500);
    report_progress(0.01 + 0.019 * (check + 1) / 40.0, 0,
                    maximum_frames);
  }
  if (!file_ready) {
    return finish(Failure(
        "video_not_ready",
        "The recording is still being saved. Wait a moment, then scan it "
        "again.",
        path));
  }
  report_progress(0.03, 0, maximum_frames);

  winrt::init_apartment(winrt::apartment_type::multi_threaded);
  const HRESULT media_foundation_result = EnsureMediaFoundationStarted();
  if (FAILED(media_foundation_result)) {
    return finish(Failure("media_foundation_unavailable",
                          HResultMessage(media_foundation_result), path));
  }
  report_progress(0.04, 0, maximum_frames);

  ComPtr<IMFAttributes> reader_attributes;
  HRESULT result = MFCreateAttributes(&reader_attributes, 3);
  if (FAILED(result)) {
    return finish(
        Failure("video_open_failed", HResultMessage(result), path));
  }
  // Screen-recording clips are small and sampled sparsely. Windows' hardware
  // video transform can finish decoding quickly but then wait indefinitely
  // while its driver tears down. The software transform is still fast here,
  // avoids that driver dependency, and leaves the CPU-heavy OCR parallelized.
  reader_attributes->SetUINT32(MF_READWRITE_ENABLE_HARDWARE_TRANSFORMS, FALSE);
  reader_attributes->SetUINT32(
      MF_SOURCE_READER_ENABLE_ADVANCED_VIDEO_PROCESSING, TRUE);
  report_progress(0.05, 0, maximum_frames);

  ComPtr<IMFSourceReader> reader;
  result = MFCreateSourceReaderFromURL(path.c_str(), reader_attributes.Get(),
                                       &reader);
  if (FAILED(result)) {
    return finish(
        Failure("video_open_failed", HResultMessage(result), path));
  }
  report_progress(0.07, 0, maximum_frames);

  ComPtr<IMFMediaType> requested_type;
  result = MFCreateMediaType(&requested_type);
  if (FAILED(result)) {
    return finish(
        Failure("video_decode_failed", HResultMessage(result), path));
  }
  requested_type->SetGUID(MF_MT_MAJOR_TYPE, MFMediaType_Video);
  requested_type->SetGUID(MF_MT_SUBTYPE, MFVideoFormat_RGB32);
  result = reader->SetCurrentMediaType(kFirstVideoStream, nullptr,
                                       requested_type.Get());
  if (FAILED(result)) {
    return finish(Failure("unsupported_video", HResultMessage(result), path));
  }
  report_progress(0.09, 0, maximum_frames);

  ComPtr<IMFMediaType> current_type;
  result = reader->GetCurrentMediaType(kFirstVideoStream, &current_type);
  if (FAILED(result)) {
    return finish(
        Failure("video_decode_failed", HResultMessage(result), path));
  }
  UINT32 width = 0;
  UINT32 height = 0;
  result = MFGetAttributeSize(current_type.Get(), MF_MT_FRAME_SIZE, &width, &height);
  if (FAILED(result) || width == 0 || height == 0) {
    return finish(Failure(
        "video_dimensions_missing",
        FAILED(result) ? HResultMessage(result)
                       : "The recording has no video dimensions.",
        path));
  }

  std::int64_t duration_hundred_nanoseconds = 0;
  PropVariantLifetime duration;
  if (SUCCEEDED(reader->GetPresentationAttribute(
      kMediaSource, MF_PD_DURATION, &duration.value)) &&
      duration.value.vt == VT_UI8) {
    duration_hundred_nanoseconds =
        static_cast<std::int64_t>(duration.value.uhVal.QuadPart);
  }
  const auto duration_milliseconds =
      duration_hundred_nanoseconds / kHundredNanosecondsPerMillisecond;
  const auto interval_milliseconds = std::max<std::int64_t>(
      preferred_interval_milliseconds,
      duration_milliseconds > 0
          ? static_cast<std::int64_t>(
                std::ceil(duration_milliseconds /
                          static_cast<double>(maximum_frames)))
          : preferred_interval_milliseconds);
  const int estimated_frames = duration_milliseconds > 0
                                   ? std::clamp(
                                         static_cast<int>(std::ceil(
                                             duration_milliseconds /
                                             static_cast<double>(
                                                 interval_milliseconds))),
                                         1, maximum_frames)
                                   : maximum_frames;
  report_progress(0.10, 0, estimated_frames);

  OcrEngine engine{nullptr};
  const Language english(L"en-US");
  if (OcrEngine::IsLanguageSupported(english)) {
    engine = OcrEngine::TryCreateFromLanguage(english);
  }
  if (!engine) {
    engine = OcrEngine::TryCreateFromUserProfileLanguages();
  }
  if (!engine) {
    return finish(Failure(
        "ocr_language_unavailable",
        "Windows OCR is unavailable. Install the English Windows language OCR "
        "capability, then try again.",
        path));
  }
  report_progress(0.12, 0, estimated_frames);

  ScanResult output;
  output.source_path = WideToUtf8(path);
  output.ocr_language = WideToUtf8(engine.RecognizerLanguage().LanguageTag());
  output.source_width = static_cast<int>(width);
  output.source_height = static_cast<int>(height);

  std::vector<FramePixels> selected_frames;
  selected_frames.reserve(static_cast<std::size_t>(maximum_frames));
  std::optional<FramePixels> bucket_best;
  std::int64_t active_bucket = -1;
  int last_candidate_slot = -1;
  std::int64_t last_timestamp = 0;
  const auto keep_bucket = [&]() {
    if (!bucket_best.has_value() ||
        selected_frames.size() >= static_cast<std::size_t>(maximum_frames)) {
      return;
    }
    const auto selected_timestamp = bucket_best->timestamp_milliseconds;
    selected_frames.push_back(std::move(*bucket_best));
    bucket_best.reset();
    const double decode_fraction =
        duration_milliseconds > 0
            ? std::clamp(selected_timestamp /
                             static_cast<double>(duration_milliseconds),
                         0.0, 1.0)
            : selected_frames.size() / static_cast<double>(estimated_frames);
    report_progress(0.12 + 0.18 * decode_fraction, 0, estimated_frames);
  };

  while (selected_frames.size() < static_cast<std::size_t>(maximum_frames)) {
    DWORD actual_stream = 0;
    DWORD flags = 0;
    LONGLONG timestamp = 0;
    ComPtr<IMFSample> media_frame;
    result = reader->ReadSample(kFirstVideoStream, 0, &actual_stream, &flags,
                                &timestamp, &media_frame);
    if (FAILED(result)) {
      return finish(
          Failure("video_decode_failed", HResultMessage(result), path));
    }
    if ((flags & MF_SOURCE_READERF_ENDOFSTREAM) != 0) break;
    if (!media_frame) continue;

    const auto timestamp_milliseconds =
        timestamp / kHundredNanosecondsPerMillisecond;
    last_timestamp = std::max(last_timestamp, timestamp_milliseconds);
    const auto sample_bucket =
        timestamp_milliseconds / interval_milliseconds;
    if (active_bucket < 0) active_bucket = sample_bucket;
    if (sample_bucket != active_bucket) {
      keep_bucket();
      active_bucket = sample_bucket;
      last_candidate_slot = -1;
      if (selected_frames.size() >=
          static_cast<std::size_t>(maximum_frames)) {
        break;
      }
    }
    const auto position_in_bucket =
        timestamp_milliseconds % interval_milliseconds;
    const int candidate_slot = std::clamp(
        static_cast<int>(position_in_bucket * 3 / interval_milliseconds), 0,
        2);
    if (candidate_slot == last_candidate_slot) continue;
    last_candidate_slot = candidate_slot;

    FramePixels pixels;
    result = CopySamplePixels(media_frame.Get(), static_cast<int>(width),
                              static_cast<int>(height), &pixels);
    if (FAILED(result)) continue;
    pixels.timestamp_milliseconds = timestamp_milliseconds;
    pixels.sharpness = ComputeSharpness(pixels.bgra, pixels.width, pixels.height);
    if (!bucket_best.has_value() ||
        pixels.sharpness > bucket_best->sharpness) {
      bucket_best = std::move(pixels);
    }
  }
  keep_bucket();
  if (selected_frames.empty()) {
    return finish(Failure(
        "no_video_frames",
        "No readable video frames were found in the recording.", path));
  }

  const int sampled_count = static_cast<int>(selected_frames.size());
  output.duration_milliseconds =
      duration_milliseconds > 0 ? duration_milliseconds : last_timestamp;
  report_progress(0.30, 0, sampled_count);

  const std::wstring recognizer_language =
      engine.RecognizerLanguage().LanguageTag().c_str();
  std::vector<OcrFrame> recognized_frames(selected_frames.size());
  std::vector<std::uint8_t> recognized_success(selected_frames.size(), 0);
  std::vector<std::string> worker_diagnostics;
  std::atomic<std::size_t> next_frame{0};
  std::mutex result_mutex;
  std::mutex progress_mutex;
  int completed_frames = 0;
  const auto available_threads = std::thread::hardware_concurrency();
  const int worker_count = std::min(
      4, std::min(sampled_count,
                  static_cast<int>(available_threads == 0
                                       ? 2
                                       : available_threads)));
  std::vector<std::thread> workers;
  workers.reserve(static_cast<std::size_t>(worker_count));
  for (int worker_index = 0; worker_index < worker_count; ++worker_index) {
    workers.emplace_back([&]() {
      try {
        winrt::init_apartment(winrt::apartment_type::multi_threaded);
        const Language language(recognizer_language);
        OcrEngine worker_engine = OcrEngine::TryCreateFromLanguage(language);
        if (!worker_engine) {
          worker_engine = OcrEngine::TryCreateFromUserProfileLanguages();
        }
        if (!worker_engine) {
          std::lock_guard<std::mutex> lock(result_mutex);
          worker_diagnostics.push_back(
              "A Windows OCR worker could not be initialized.");
          winrt::uninit_apartment();
          return;
        }
        while (true) {
          const auto frame_index = next_frame.fetch_add(1);
          if (frame_index >= selected_frames.size()) break;
          try {
            recognized_frames[frame_index] = RecognizeFrame(
                selected_frames[frame_index], static_cast<int>(frame_index),
                worker_engine);
            recognized_success[frame_index] = 1;
          } catch (const winrt::hresult_error& error) {
            std::lock_guard<std::mutex> lock(result_mutex);
            worker_diagnostics.push_back(
                "OCR skipped frame " + std::to_string(frame_index) + ": " +
                WideToUtf8(error.message().c_str()));
          }
          {
            std::lock_guard<std::mutex> lock(progress_mutex);
            ++completed_frames;
            report_progress(
                0.30 + 0.64 * completed_frames /
                           static_cast<double>(sampled_count),
                completed_frames, sampled_count);
          }
        }
        winrt::uninit_apartment();
      } catch (const winrt::hresult_error& error) {
        std::lock_guard<std::mutex> lock(result_mutex);
        worker_diagnostics.push_back(
            "A Windows OCR worker stopped: " +
            WideToUtf8(error.message().c_str()));
      }
    });
  }
  for (auto& worker : workers) {
    if (worker.joinable()) worker.join();
  }
  for (std::size_t index = 0; index < recognized_frames.size(); ++index) {
    if (recognized_success[index] != 0) {
      output.frames.push_back(std::move(recognized_frames[index]));
    }
  }
  output.diagnostics.insert(output.diagnostics.end(),
                            worker_diagnostics.begin(),
                            worker_diagnostics.end());
  if (output.frames.empty()) {
    return finish(Failure(
        "ocr_failed", "Windows OCR could not read any sampled video frame.",
        path));
  }
  report_progress(0.97, sampled_count, estimated_frames);
  output.success = true;
  output.diagnostics.push_back(
      "Media Foundation selected " + std::to_string(sampled_count) +
      " frames at approximately " + std::to_string(interval_milliseconds) +
      " ms intervals and Windows OCR used " +
      std::to_string(worker_count) + " concurrent workers.");
  // The Flutter bridge owns completion. Reporting 100% here made the dialog
  // claim it had finished before the result had crossed the native boundary,
  // which was especially misleading if Windows still had worker-thread
  // cleanup to perform. Keep the scan in its short finalization phase until
  // the actual result replaces the progress view.
  return finish(std::move(output));
}

bool LaunchRectangleRecording(HWND owner) {
  if (owner != nullptr && IsWindow(owner)) SetForegroundWindow(owner);
  std::array<INPUT, 6> input{};
  const auto key = [](WORD virtual_key, DWORD flags) {
    INPUT value{};
    value.type = INPUT_KEYBOARD;
    value.ki.wVk = virtual_key;
    value.ki.dwFlags = flags;
    return value;
  };
  input[0] = key(VK_LWIN, 0);
  input[1] = key(VK_SHIFT, 0);
  input[2] = key('R', 0);
  input[3] = key('R', KEYEVENTF_KEYUP);
  input[4] = key(VK_SHIFT, KEYEVENTF_KEYUP);
  input[5] = key(VK_LWIN, KEYEVENTF_KEYUP);
  return SendInput(static_cast<UINT>(input.size()), input.data(),
                   sizeof(INPUT)) == input.size();
}

std::optional<std::wstring> FindLatestRecording(
    std::int64_t modified_after_unix_milliseconds) {
  std::vector<std::filesystem::path> directories;
  if (const auto local = EnvironmentPath(L"LOCALAPPDATA"); local.has_value()) {
    directories.push_back(*local / L"Packages" /
                          L"Microsoft.ScreenSketch_8wekyb3d8bbwe" /
                          L"TempState" / L"Recordings");
  }
  PWSTR videos = nullptr;
  if (SUCCEEDED(SHGetKnownFolderPath(FOLDERID_Videos, KF_FLAG_DEFAULT, nullptr,
                                     &videos)) &&
      videos != nullptr) {
    directories.emplace_back(std::filesystem::path(videos) /
                             L"Screen Recordings");
    directories.emplace_back(std::filesystem::path(videos) / L"Captures");
    CoTaskMemFree(videos);
  }
  std::optional<std::filesystem::path> newest;
  std::int64_t newest_time = std::numeric_limits<std::int64_t>::min();
  for (const auto& directory : directories) {
    ConsiderRecordingsIn(directory, modified_after_unix_milliseconds, &newest,
                         &newest_time);
  }
  return newest.has_value() ? std::optional<std::wstring>(newest->wstring())
                            : std::nullopt;
}

}  // namespace active_node_video_scanner
