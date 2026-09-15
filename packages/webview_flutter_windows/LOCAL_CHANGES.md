# Private video-only build

Runtime source copied from `webview_flutter_windows` 1.1.1 (BSD 3-Clause; see LICENSE).
Upstream: https://github.com/omar-hanafy/webview_flutter_windows

This app uses the installed WebView2 runtime, never a bundled browser. Its only
webview is the optional YouTube player. Native guards in `webview.cc` run before
navigation/downloads: allow only this app's local player page at top level;
reject non-HTTPS frame navigation and external schemes; cancel all downloads.
These restrictions deliberately make this copy unsuitable as a general browser.
They do not modify YouTube controls, media requests, ads, or embed restrictions.

Retain these guards when updating upstream. App-owned HTML/origin identity,
temporary profile disposal, and playback lifecycle live in SpotVideoPlayer.

Release builds also apply MSVC path mapping to the plugin so WIL diagnostics
cannot embed the developer machine's source or build roots in the shipped DLL.

The native bridge explicitly unregisters both its event and method channels
before releasing its texture and WebView. This keeps Flutter's binary messenger
callbacks bounded to the bridge lifetime during application shutdown.
