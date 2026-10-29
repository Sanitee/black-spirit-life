# Fish Map startup correction

Live 0.1.13 started its Fish service on loopback ports 8765–8795, but the
embedded browser's navigation policy still allowed only the isolated Trial's
8925–8955. The service was healthy; the browser canceled its navigation with
WebView2 status 14 (`OPERATION_CANCELED`).

The Stable runtime constants and native allowlist now both use 8765–8795.
The port allocator uses those constants rather than a second literal range.
There is no change to the service's established ports, token authentication,
personal-data location, browser profile, journal, map content or rendering.
The isolated Trial's source and range are not changed.

## Verification

- The new port-contract test failed against the released constants and passes
  after the correction. The runtime lifecycle test also asserts the actual
  `--port` argument is inside the declared browser-allowed range.
- Native tests exercise all 65,536 ports, malformed origins, the token-fragment
  URL shape and existing Gathering/video frame restrictions. Only Stable's
  range is allowed; arbitrary local services remain blocked.
- A hidden native harness built from the actual WebView host/platform/view
  sources reproduced the failure on 8765 with the released policy. The same
  map and host reached ready on 8925, isolating the allowlist mismatch.
- With the fix, actual Fish HTML reached `document.readyState == 'complete'`,
  removed its boot overlay and displayed its app on both 8765 and 8795.
  Reopening with the same disposable browser profile also succeeded.

These native runs used an isolated Fish service and disposable personal/cache/
browser directories, not the installed application or the user's saved data.
They verify real page loading, not just `/api/health` or mocked widget readiness.
Full installer/update publication verification is a separate release gate.
