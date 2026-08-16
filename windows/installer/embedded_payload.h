#pragma once

#include <windows.h>

#include <optional>
#include <string>

namespace bsl::installer {

struct ExtractedPayload {
  ExtractedPayload() = default;
  ~ExtractedPayload();
  ExtractedPayload(const ExtractedPayload &) = delete;
  ExtractedPayload &operator=(const ExtractedPayload &) = delete;
  ExtractedPayload(ExtractedPayload &&other) noexcept;
  ExtractedPayload &operator=(ExtractedPayload &&other) noexcept;

  std::wstring directory;
  std::wstring executable;
  std::wstring log_file;
  HANDLE directory_handle = INVALID_HANDLE_VALUE;
  HANDLE executable_handle = INVALID_HANDLE_VALUE;

  void ReleaseLocks();
};

[[nodiscard]] bool HasEmbeddedPayload();
[[nodiscard]] bool VerifyEmbeddedPayload(std::wstring *error);
[[nodiscard]] std::optional<ExtractedPayload>
ExtractEmbeddedPayload(std::wstring *error);
void CleanupExtractedPayload(ExtractedPayload &payload);

} // namespace bsl::installer
