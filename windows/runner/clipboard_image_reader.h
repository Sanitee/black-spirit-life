#ifndef RUNNER_CLIPBOARD_IMAGE_READER_H_
#define RUNNER_CLIPBOARD_IMAGE_READER_H_

#include <windows.h>

#include <cstdint>
#include <optional>
#include <vector>

namespace clipboard_image_reader {

// Returns the current Windows clipboard image encoded as PNG. Both direct PNG
// clipboard payloads and the standard Windows DIB/bitmap formats are accepted.
// A clipboard without a supported image returns std::nullopt.
std::optional<std::vector<uint8_t>> ReadPng(HWND owner);

}  // namespace clipboard_image_reader

#endif  // RUNNER_CLIPBOARD_IMAGE_READER_H_
