# BlackSpiritStorageOcr

Windows-only .NET 8 x64 helper derived from the shared Black Spirit Hub v0.9.52
storage-grid scanner, with its byte-exact frozen Recipe Book snapshot. Black
Spirit Life adds an adaptive, numeric-grammar CTC pass for malformed quantity
reads. The bundled PP-OCRv5 model, item artwork, and icon scoring remain
unchanged; the helper now keeps up to 64 credible icon candidates so the app
can use full-resolution artwork and reviewed recipe evidence to resolve
difficult lookalikes without losing a legitimate lower-ranked identity. Scores
below the app's calibrated credibility floor are omitted from the JSON rather
than adding transfer and parsing work that cannot affect a decision.

## Protocol

With no arguments, the executable reads exactly one bounded JSON request from
standard input and writes exactly one camel-case JSON recognition result to
standard output. Diagnostics are bounded and written only to standard error.

```json
{"fileName":"storage.png","mimeType":"image/png","dataBase64":"..."}
```

The native operation times out after 90 seconds. PNG, JPEG, and BMP are accepted
only when filename extension, MIME type, and raster signature agree. Filesystem
paths are never accepted by the recognition bridge.

The application launches the same executable with `--server` and keeps one
`RecipeBookScreenshotService` alive for sequential requests. This reuses the
already-loaded ONNX session and frozen artwork atlases without changing any
recognition views, candidates, scores, or thresholds. Requests and responses
are bounded, processed one at a time, and framed as tab-separated request IDs
plus the same JSON payload. The original one-request protocol remains available
for diagnostics and compatibility.

After `READY\t1`, a server client may send `request-id\tWARM`. The helper
eagerly loads the same frozen Recipe Book atlas, full client-catalog atlas, and
PP-OCRv5 session that ordinary recognition uses, then replies
`OK\trequest-id\tWARM`. Warm-up is serialized with recognition and uses the
same 90-second request timeout. It does not decode or recognize a screenshot;
existing recognition frames remain `request-id\t{json}` and keep their
unchanged `OK`/`ERR` response format.

## Verification and publish

```powershell
.\verify-assets.ps1
.\build-publish.ps1 -DotnetPath C:\path\to\dotnet.exe
```

The publisher uses no more than four MSBuild workers and writes to
`build/windows/x64/storage_ocr` by default. It creates a self-contained win-x64
payload and retains the native ONNX Runtime DLLs beside the executable. The
verification step checks the sealed upstream asset hashes, both atlas
contracts, approved native source hashes, required notices, and fixture publish
exclusions. Planner eligibility and item grouping remain in Flutter. Quantity
character recovery stays inside the native helper so it can use model
probabilities, the strict BDO number grammar, and agreement across image views.
The result also records whether a suggested amount came from agreeing direct
reads or from a recovery/single-view path, so the review UI highlights only
the latter instead of treating every normal K/M display as uncertain.

An inactive catalog-extension experiment remains available only in the private
development repository for recovery and review. Its generated overlay is
excluded from this public source snapshot, `Assets/RecipeBook`, and every build
or publish output. It must not be enabled without an explicit decision to fork
the sealed OCR tool.

## Private golden-fixture validation

Contributor screenshot fixtures remain in the private development repository.
They are excluded from this public source snapshot and every build or publish
output. Before promotion, the private fixture suite passed at schema 4 with 5
cases and 284 slots, including the pinned numeric-grammar review suggestions.
