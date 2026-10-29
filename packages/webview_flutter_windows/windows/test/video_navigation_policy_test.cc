#include <iostream>
#include <string>
#include <string_view>

#include "../video_navigation_policy.h"

namespace {
int failures = 0;

void Expect(bool condition, std::wstring_view description) {
  if (condition) return;
  ++failures;
  std::wcerr << L"FAIL: " << description << L'\n';
}
}  // namespace

int main() {
  // Exercise the production functions, not a copied URL parser. Checking every
  // port catches both boundary mistakes and accidental permission for Trial.
  for (unsigned int port = 0; port <= 65535; ++port) {
    const auto origin = L"http://127.0.0.1:" + std::to_wstring(port);
    const bool expected = port >= 8765 && port <= 8795;
    for (const auto suffix : {L"", L"/", L"/index.html?view=map#atlas",
                              L"/#apiToken=synthetic"}) {
      const auto url = origin + suffix;
      Expect(bdo_video::AllowsFishCompanionLoopback(url) == expected, url);
      Expect(bdo_video::AllowsTopLevel(url) == expected, url);
      // Fish remains a top-level exception; it never grants frame access to
      // arbitrary local services or changes the media iframe rules.
      Expect(!bdo_video::AllowsFrame(url), url);
    }
  }

  for (const auto url : {
           L"http://127.0.0.1:/", L"http://127.0.0.1:87650/",
           L"http://127.0.0.1:876500/", L"http://127.0.0.1:-8765/",
           L"http://127.0.0.1:+8765/", L"http://127.0.0.1:8765x/",
           L"http://127.0.0.1:8765@evil.example/",
           L"http://127.0.0.1:8765.evil.example/",
           L"http://127.0.0.1:8765\\evil.example/",
           L"http://user@127.0.0.1:8765/", L"http://localhost:8765/",
           L"http://[::1]:8765/", L"http://127.0.0.2:8765/",
           L"https://127.0.0.1:8765/", L"http://evil.example:8765/",
           L"file:///C:/private.txt", L"custom-app://launch",
           L"javascript:alert(1)", L"data:text/html,hello"}) {
    Expect(!bdo_video::AllowsFishCompanionLoopback(url), url);
    Expect(!bdo_video::AllowsTopLevel(url), url);
  }

  Expect(bdo_video::AllowsTopLevel(L"about:blank"), L"blank top-level");
  Expect(bdo_video::AllowsFrame(L"about:blank"), L"blank frame");
  Expect(bdo_video::AllowsTopLevel(
             L"https://blackspiritlife.bdogatheringcompanion/player.html"),
         L"existing Gathering player");
  Expect(!bdo_video::AllowsTopLevel(
             L"https://blackspiritlife.bdogatheringcompanion/player.html/evil"),
         L"exact Gathering player path only");
  for (const auto url : {L"https://www.youtube.com/embed/video",
                         L"https://consent.youtube.com/",
                         L"https://googleads.g.doubleclick.net/"}) {
    Expect(bdo_video::AllowsFrame(url), url);
    Expect(!bdo_video::AllowsTopLevel(url), url);
  }
  for (const auto url : {L"http://www.youtube.com/embed/video",
                         L"file:///C:/private.txt", L"custom-app://launch"}) {
    Expect(!bdo_video::AllowsFrame(url), url);
  }

  if (failures != 0) return 1;
  std::cout << "Companion URL policy passed: all 65536 ports, isolation, "
               "malformed origins and existing media boundaries.\n";
  return 0;
}
