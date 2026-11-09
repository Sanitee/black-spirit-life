# Storage screenshot reader

Windows .NET 8 x64 helper based on Black Spirit Hub v0.9.52 and its fixed Recipe Book assets. Black Spirit Life adds number recovery and returns up to 64 credible item matches for the app to review. The PP-OCRv5 model, artwork and icon scoring are unchanged.

## Requests

With no arguments, read one bounded JSON request from stdin and write one camel-case JSON result to stdout. Send diagnostics to stderr only.

```json
{"fileName":"storage.png","mimeType":"image/png","dataBase64":"..."}
```

Accept PNG, JPEG or BMP only when extension, MIME type and signature agree. Never accept a filesystem path. Each request has a 90-second timeout.

`--server` keeps the model and atlases loaded for sequential requests through `RecipeBookScreenshotService`. Frames use tab-separated request IDs and the same JSON; existing `OK`/`ERR` responses remain.

After `READY\t1`, `request-id\tWARM` loads the same atlases and model, then returns `OK\trequest-id\tWARM`. Warm-up is serialized, uses the same timeout and does not scan an image.

## Build and check

```powershell
.\verify-assets.ps1
.\build-publish.ps1 -DotnetPath <dotnet-executable>
```

The build uses up to four MSBuild workers. Its self-contained win-x64 output defaults to `build/windows/x64/storage_ocr`, with ONNX DLLs beside the executable.

Verification checks fixed source/asset hashes, both atlases, notices and excluded fixtures. Flutter handles item eligibility/grouping. The helper handles number recovery and marks recovered or single-view amounts for review; normal agreeing K/M reads are not automatically uncertain.

`Tools/PlannerCatalog/GeneratedOverlayBackup` is an inactive experiment. Do not ship or enable it without a separate decision to fork the fixed tool.

## Screenshot fixtures

Fixtures under `tests/` are never packaged. After building:

```powershell
& <publish>\BlackSpiritStorageOcr.exe --fixture `
  .\tests\fixtures\recipe-book-ocr\manifest.json
```

The expected result is schema 4, 5 cases, 284 slots, 260 resolved quantities,
18 abstentions, 2 assumed-one quantities, 12 material assertions, 40 border
assertions, minimum border confidence 0.721, and three pinned numeric-grammar
review suggestions for the difficult short-number fixture.
