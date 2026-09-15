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

An inactive catalog-extension experiment is preserved under
`Tools/PlannerCatalog/GeneratedOverlayBackup` for recovery and review. It is
not part of `Assets/RecipeBook`, is not copied to build or publish output, and
must not be enabled without an explicit decision to fork the sealed OCR tool.

## Golden fixture runner

The fixture screenshots live under `tests/` and are never copied to build or
publish output. After publishing, run:

```powershell
& <publish>\BlackSpiritStorageOcr.exe --fixture `
  .\tests\fixtures\recipe-book-ocr\manifest.json
```

The expected result is schema 4, 5 cases, 284 slots, 260 resolved quantities,
18 abstentions, 2 assumed-one quantities, 12 material assertions, 40 border
assertions, minimum border confidence 0.721, and three pinned numeric-grammar
review suggestions for the difficult short-number fixture.
