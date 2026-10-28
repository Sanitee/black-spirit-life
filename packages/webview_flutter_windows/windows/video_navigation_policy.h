#pragma once

#include <string_view>

namespace bdo_video {
// Keep the experimental companion isolated from normal Beta's 8765–8795.
// The Dart isolation contract checks these against the service's bind range.
inline constexpr unsigned int kFishCompanionFirstPort = 8925;
inline constexpr unsigned int kFishCompanionLastPort = 8955;

inline bool AllowsFishCompanionLoopback(std::wstring_view uri) {
  constexpr std::wstring_view kLoopbackPrefix = L"http://127.0.0.1:";
  if (uri.substr(0, kLoopbackPrefix.size()) != kLoopbackPrefix) {
    return false;
  }

  const auto port_begin = kLoopbackPrefix.size();
  const auto path_begin = uri.find(L'/', port_begin);
  const auto port_text = uri.substr(
      port_begin,
      path_begin == std::wstring_view::npos ? std::wstring_view::npos
                                            : path_begin - port_begin);
  if (port_text.empty() || port_text.size() > 5) {
    return false;
  }

  unsigned int port = 0;
  for (const auto character : port_text) {
    if (character < L'0' || character > L'9') {
      return false;
    }
    port = port * 10 + static_cast<unsigned int>(character - L'0');
  }
  return port >= kFishCompanionFirstPort && port <= kFishCompanionLastPort;
}

inline bool AllowsTopLevel(std::wstring_view uri) {
  return uri == L"https://blackspiritlife.bdogatheringcompanion/player.html" ||
         uri == L"about:blank" || AllowsFishCompanionLoopback(uri);
}

inline bool AllowsFrame(std::wstring_view uri) {
  // Keep legitimate YouTube, consent, and advertising HTTPS frames intact.
  // No iframe may launch a local file, app protocol, or external application.
  return uri == L"about:blank" || uri.substr(0, 8) == L"https://";
}
}  // namespace bdo_video
