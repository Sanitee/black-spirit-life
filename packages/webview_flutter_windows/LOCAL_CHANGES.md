# Black Spirit Life changes

Based on `webview_flutter_windows` 1.1.1, under BSD 3-Clause; keep [LICENSE](LICENSE). [Upstream](https://github.com/omar-hanafy/webview_flutter_windows).

The app uses the installed WebView2 runtime, not a bundled browser. Native navigation rules allow the Gathering player page, `about:blank`, and the Fishing service at `http://127.0.0.1:8765–8795`. Frames allow HTTPS and `about:blank`. Downloads and external application schemes are blocked. See `windows/video_navigation_policy.h` for exact matching rules.

Keep these restrictions when updating upstream. They preserve normal YouTube controls, consent, advertising and embed rules. App code owns page identity, browser storage and playback/service lifetime.

Release builds map compiler paths so developer folders do not enter WIL diagnostics in the DLL. The native bridge unregisters event and method channels before releasing its texture/WebView, preventing shutdown callbacks after disposal.
