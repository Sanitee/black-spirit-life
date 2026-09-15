#define NOMINMAX
#include <windows.h>
#include <wincrypt.h>

#include <algorithm>
#include <cmath>
#include <cwctype>
#include <filesystem>
#include <iostream>
#include <iterator>
#include <numeric>
#include <sstream>
#include <stdexcept>
#include <string>
#include <vector>

#include <winrt/Windows.Foundation.h>
#include <winrt/Windows.Foundation.Collections.h>
#include <winrt/Windows.Globalization.h>
#include <winrt/Windows.Graphics.Imaging.h>
#include <winrt/Windows.Media.Ocr.h>
#include <winrt/Windows.Storage.h>
#include <winrt/Windows.Storage.Streams.h>

using namespace winrt;
using namespace Windows::Foundation;
using namespace Windows::Globalization;
using namespace Windows::Graphics::Imaging;
using namespace Windows::Media::Ocr;
using namespace Windows::Storage;
using namespace Windows::Storage::Streams;

namespace
{
    constexpr double CountColumnFraction = 0.72;
    constexpr double MaximumUpscale = 4.0;

    struct PositionedWord
    {
        std::wstring text;
        double x;
        double y;
        double width;
        double height;

        [[nodiscard]] double center_y() const noexcept
        {
            return y + (height / 2.0);
        }
    };

    struct SummaryRow
    {
        std::wstring item_name;
        std::int64_t count;
    };

    [[nodiscard]] std::string utf8(std::wstring_view value)
    {
        if (value.empty())
        {
            return {};
        }

        const auto length = WideCharToMultiByte(
            CP_UTF8,
            WC_ERR_INVALID_CHARS,
            value.data(),
            static_cast<int>(value.size()),
            nullptr,
            0,
            nullptr,
            nullptr);
        if (length <= 0)
        {
            throw std::runtime_error("Could not encode OCR text as UTF-8.");
        }

        std::string result(static_cast<std::size_t>(length), '\0');
        WideCharToMultiByte(
            CP_UTF8,
            WC_ERR_INVALID_CHARS,
            value.data(),
            static_cast<int>(value.size()),
            result.data(),
            length,
            nullptr,
            nullptr);
        return result;
    }

    [[nodiscard]] std::string json_escape(std::wstring_view value)
    {
        const auto encoded = utf8(value);
        std::ostringstream output;
        for (const auto byte : encoded)
        {
            const auto character = static_cast<unsigned char>(byte);
            switch (character)
            {
            case '\"': output << "\\\""; break;
            case '\\': output << "\\\\"; break;
            case '\b': output << "\\b"; break;
            case '\f': output << "\\f"; break;
            case '\n': output << "\\n"; break;
            case '\r': output << "\\r"; break;
            case '\t': output << "\\t"; break;
            default:
                if (character < 0x20)
                {
                    constexpr char hex[] = "0123456789abcdef";
                    output << "\\u00" << hex[(character >> 4) & 0x0f] << hex[character & 0x0f];
                }
                else
                {
                    output << static_cast<char>(character);
                }
            }
        }
        return output.str();
    }

    [[nodiscard]] bool equals_ignore_case(std::wstring_view left, std::wstring_view right)
    {
        return left.size() == right.size()
            && std::equal(left.begin(), left.end(), right.begin(), [](const wchar_t a, const wchar_t b)
            {
                return std::towlower(a) == std::towlower(b);
            });
    }

    [[nodiscard]] std::wstring normalize_name(std::wstring_view value)
    {
        std::wstring result;
        result.reserve(value.size());
        bool pending_space = false;
        for (const auto character : value)
        {
            if (std::iswspace(character))
            {
                pending_space = !result.empty();
                continue;
            }

            if (pending_space)
            {
                result.push_back(L' ');
                pending_space = false;
            }
            result.push_back(character);
        }
        return result;
    }

    [[nodiscard]] bool try_parse_count(std::wstring_view value, std::int64_t& count)
    {
        std::wstring normalized;
        for (auto character : value)
        {
            if (character == L'O' || character == L'o')
            {
                character = L'0';
            }
            if (character == L',' || character == L'.' || std::iswspace(character))
            {
                continue;
            }
            if (!std::iswdigit(character))
            {
                return false;
            }
            normalized.push_back(character);
        }

        if (normalized.empty())
        {
            return false;
        }

        try
        {
            std::size_t parsed = 0;
            count = std::stoll(normalized, &parsed, 10);
            return parsed == normalized.size();
        }
        catch (...)
        {
            return false;
        }
    }

    [[nodiscard]] IRandomAccessStream stream_from_base64(std::string encoded)
    {
        DWORD byte_count = 0;
        if (!CryptStringToBinaryA(
            encoded.c_str(),
            static_cast<DWORD>(encoded.size()),
            CRYPT_STRING_BASE64_ANY,
            nullptr,
            &byte_count,
            nullptr,
            nullptr))
        {
            throw std::runtime_error("The standard-input payload is not valid base64.");
        }

        std::vector<std::uint8_t> bytes(byte_count);
        if (!CryptStringToBinaryA(
            encoded.c_str(),
            static_cast<DWORD>(encoded.size()),
            CRYPT_STRING_BASE64_ANY,
            bytes.data(),
            &byte_count,
            nullptr,
            nullptr))
        {
            throw std::runtime_error("The standard-input payload is not valid base64.");
        }
        bytes.resize(byte_count);

        InMemoryRandomAccessStream memory;
        DataWriter writer{memory};
        writer.WriteBytes(bytes);
        writer.StoreAsync().get();
        writer.DetachStream();
        memory.Seek(0);
        return memory;
    }

    [[nodiscard]] IRandomAccessStream stream_from_path(std::wstring_view image_path)
    {
        const auto full_path = std::filesystem::absolute(image_path).wstring();
        const auto file = StorageFile::GetFileFromPathAsync(full_path).get();
        return file.OpenAsync(FileAccessMode::Read).get();
    }

    [[nodiscard]] std::vector<std::vector<PositionedWord>> cluster_rows(
        const std::vector<PositionedWord>& words)
    {
        std::vector<std::vector<PositionedWord>> rows;
        for (const auto& word : words)
        {
            const auto tolerance = std::max(5.0, word.height * 0.55);
            auto matching_row = rows.end();
            if (!rows.empty())
            {
                const auto& candidate = rows.back();
                const auto average_center = std::accumulate(
                    candidate.begin(),
                    candidate.end(),
                    0.0,
                    [](const double sum, const PositionedWord& existing)
                    {
                        return sum + existing.center_y();
                    }) / static_cast<double>(candidate.size());
                if (std::abs(average_center - word.center_y()) <= tolerance)
                {
                    matching_row = std::prev(rows.end());
                }
            }

            if (matching_row == rows.end())
            {
                rows.push_back({word});
            }
            else
            {
                matching_row->push_back(word);
            }
        }
        return rows;
    }

    [[nodiscard]] std::vector<SummaryRow> parse_rows(
        const OcrResult& result,
        const std::uint32_t image_width)
    {
        std::vector<PositionedWord> words;
        for (const auto& line : result.Lines())
        {
            for (const auto& word : line.Words())
            {
                const auto box = word.BoundingRect();
                words.push_back({
                    word.Text().c_str(),
                    box.X,
                    box.Y,
                    box.Width,
                    box.Height
                });
            }
        }

        std::sort(words.begin(), words.end(), [](const PositionedWord& left, const PositionedWord& right)
        {
            if (left.center_y() != right.center_y())
            {
                return left.center_y() < right.center_y();
            }
            return left.x < right.x;
        });

        auto count_start = static_cast<double>(image_width) * CountColumnFraction;
        const auto count_header = std::find_if(words.begin(), words.end(), [](const PositionedWord& word)
        {
            return equals_ignore_case(word.text, L"COUNT");
        });
        if (count_header != words.end())
        {
            count_start = std::max(static_cast<double>(image_width) * 0.60, count_header->x - 12.0);
        }

        std::vector<SummaryRow> parsed;
        for (auto& row : cluster_rows(words))
        {
            std::sort(row.begin(), row.end(), [](const PositionedWord& left, const PositionedWord& right)
            {
                return left.x < right.x;
            });

            std::wstring name;
            std::wstring count_text;
            for (const auto& word : row)
            {
                if (word.x >= count_start)
                {
                    count_text.append(word.text);
                }
                else
                {
                    if (!name.empty())
                    {
                        name.push_back(L' ');
                    }
                    name.append(word.text);
                }
            }

            name = normalize_name(name);
            std::int64_t count = 0;
            if (name.empty()
                || count_text.empty()
                || equals_ignore_case(name, L"ITEM")
                || !try_parse_count(count_text, count))
            {
                continue;
            }
            parsed.push_back({std::move(name), count});
        }
        return parsed;
    }

    [[nodiscard]] std::string serialize_result(
        const std::vector<SummaryRow>& rows,
        std::wstring_view raw_text)
    {
        std::ostringstream output;
        output << "{\"rows\":[";
        for (std::size_t index = 0; index < rows.size(); ++index)
        {
            if (index > 0)
            {
                output << ',';
            }
            output << "{\"itemName\":\"" << json_escape(rows[index].item_name)
                   << "\",\"count\":" << rows[index].count << '}';
        }
        output << "],\"rawText\":\"" << json_escape(raw_text) << "\",\"warnings\":[";
        if (rows.empty())
        {
            output << "\"No item/count rows were found.\"";
        }
        output << "]}";
        return output.str();
    }

    [[nodiscard]] std::string recognize(const IRandomAccessStream& stream)
    {
        const auto decoder = BitmapDecoder::CreateAsync(stream).get();
        const auto largest_dimension = std::max(decoder.PixelWidth(), decoder.PixelHeight());
        if (largest_dimension == 0)
        {
            throw std::runtime_error("The image has no pixels.");
        }

        const auto scale = std::min(
            MaximumUpscale,
            static_cast<double>(OcrEngine::MaxImageDimension()) / largest_dimension);
        BitmapTransform transform;
        transform.ScaledWidth(static_cast<std::uint32_t>(std::round(decoder.PixelWidth() * scale)));
        transform.ScaledHeight(static_cast<std::uint32_t>(std::round(decoder.PixelHeight() * scale)));
        transform.InterpolationMode(BitmapInterpolationMode::Cubic);

        const auto bitmap = decoder.GetSoftwareBitmapAsync(
            BitmapPixelFormat::Bgra8,
            BitmapAlphaMode::Premultiplied,
            transform,
            ExifOrientationMode::RespectExifOrientation,
            ColorManagementMode::ColorManageToSRgb).get();

        auto engine = OcrEngine::TryCreateFromLanguage(Language{L"en-US"});
        if (!engine)
        {
            engine = OcrEngine::TryCreateFromUserProfileLanguages();
        }
        if (!engine)
        {
            throw std::runtime_error(
                "Windows English OCR is unavailable. Install the English OCR language capability in Windows Settings.");
        }

        const auto result = engine.RecognizeAsync(bitmap).get();
        return serialize_result(parse_rows(result, bitmap.PixelWidth()), result.Text().c_str());
    }
}

int wmain(const int argc, wchar_t* argv[])
{
    try
    {
        init_apartment(apartment_type::multi_threaded);
        IRandomAccessStream stream{nullptr};

        if (argc == 2 && std::wstring_view{argv[1]} == L"--stdin-base64")
        {
            std::string encoded(
                std::istreambuf_iterator<char>{std::cin},
                std::istreambuf_iterator<char>{});
            stream = stream_from_base64(std::move(encoded));
        }
        else if (argc == 2)
        {
            stream = stream_from_path(argv[1]);
        }
        else
        {
            std::cerr << "Usage: SummaryOcrNative <image-path> | --stdin-base64\n";
            return 2;
        }

        std::cout << recognize(stream) << '\n';
        return 0;
    }
    catch (const hresult_error& error)
    {
        std::cerr << utf8(error.message().c_str()) << '\n';
        return 1;
    }
    catch (const std::exception& error)
    {
        std::cerr << error.what() << '\n';
        return 1;
    }
}
