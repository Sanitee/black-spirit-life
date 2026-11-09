# Third-party notices

Black Spirit Life is a free, noncommercial, unofficial fan tool.

> This is unofficial content which contains copyrighted materials and IP from
> Pearl Abyss, and is not official/endorsed content.

The root [LICENSE](LICENSE) covers original app code only. It grants no rights in game content or other third-party material. These notices record sources and use decisions; they do not grant permission or provide legal advice.

## Pearl Abyss / Black Desert

Pearl Abyss owns the game names, artwork and game-derived content. This project uses its [Fan Content Guidelines](https://www.pearlabyss.com/en-US/legal/detail?_policyNo=42). Keep the required notice and respect third-party rights. The reviewed policy's contact is `fancontent@pearlabysscorp.com`.

Game artwork includes item/NPC images, Resource Map interface textures, 154 reviewed Opportunities icons and the OCR helper's 3,897 fixed item icons plus two recognition atlases. Exact source paths/hashes and asset-specific notices are retained beside the files. No local game installation or account data is distributed.

## FishyStuff

Fishing includes a credited map/API/Dex snapshot, region imagery, branding, markers and Pearl Abyss recognition artwork.

- [FishyStuff map](https://fishystuff.fish/map/) and [Dex](https://fishystuff.fish/dex/)
- Recognition URLs/hashes: `packages/bdo_fishing_core/assets/fish_companion/recognizer/reference-icons/catalog.json`

No separate redistribution licence or written permission is documented. The project owner approved credited inclusion and accepted the remaining risk. Public availability is not permission. Personal profiles, catches, sales and journals are stored separately under the user's save folder and are not bundled.

## Gathering creators, Bairog and BDO Workshop

Gathering uses credited calculator inputs, 20 route benchmarks, links and the Bairog/BDO Workshop logo. Eleven guide images include four Pearl Abyss illustrations and material credited to MMOSUMO/alext96, GrumpyG, Saarith and bunnygirl.

- [Bairog / BDO Workshop calculator](https://bdoworkshop.com/gathering-calculator)
- Exact creators, URLs, dates, hashes and limits: `packages/bdo_gathering_companion/assets/rotations/NOTICE.md` and adjacent `provenance.json`

No separate creator licence or written permission is claimed. Inclusion follows the project owner's credited-use decision. Four full-frame captures exposing player/browser context are excluded; their links and credits remain.

## Garmoth and Session Import

[Garmoth](https://garmoth.com/) supplies the credited public site/catalogue references used by the app-managed import workflow. Provenance is in `windows/session_import/src/SessionImport.App/Assets/garmoth_spot_catalog.json`.

The project owner approved this integration and reference snapshot; no Garmoth licence or written permission is claimed. Logins, cookies, browser profiles, drafts, receipts and session history stay in the user's selected save folder and are never bundled.

## WebView2

The `webview_flutter_windows` fork keeps its BSD-3-Clause licence and local-change notice. Session Import uses Microsoft.Web.WebView2 directly. The browser runtime comes from Windows/the user's installation; generated browser profiles are not installer assets.

## Black Spirit Hub OCR

The storage-screenshot reader and fixed Recipe Book assets came from Black Spirit Hub v0.9.52, commit `6ccbad52d25b54d8b67065ce8a9eb1bcece87d9f`. Its owner shared them for Black Spirit Life reuse. No top-level software licence was found, so this is project-specific permission, not a general licence for others.

Keep `windows/storage_ocr/BlackSpiritStorageOcr/SOURCE-NOTICE.txt` and `Assets/RecipeBook/NOTICE.txt`.

## PaddleOCR and ONNX Runtime

Local recognition uses RapidOCR 3.9.2's English PP-OCRv5 mobile ONNX model. The relevant RapidOCR/PaddleOCR components use Apache 2.0; Microsoft ONNX Runtime 1.29.0 uses MIT. Screenshots are processed locally, not sent to these projects.

Keep the complete model and dependency notices under `windows/storage_ocr/BlackSpiritStorageOcr/Assets/RecipeBook/ocr`: `MODEL-NOTICE-PPOCRV5.txt`, `LICENSE-PADDLEOCR.txt`, `LICENSE-ONNXRUNTIME.txt` and `THIRD-PARTY-NOTICES-ONNXRUNTIME.txt`.

## BDO Codex and BDOLytics

[BDO Codex](https://bdocodex.com/) ([contact](https://bdocodex.com/us/contacts/)) and [BDOLytics](https://bdolytics.com/) are credited research, checking and mirror sources. Pearl Abyss owns the underlying game content.

The project owner confirms that site design, HTML, guides, commentary, annotations and custom translations are not retained. URLs and record IDs remain as source evidence. Six private research files are excluded; the app's own selected and normalized runtime records are separate. See [the source rules](docs/public-release-source-matrix.md).

## Workerman / Shrddr

Credited uses cover the basemap/cache, 64 node icons, the 812-house lodging graph and worker-income inputs.

- [Workerman source](https://github.com/shrddr/workermanjs)
- [Workerman issues](https://github.com/shrddr/workermanjs/issues)
- [Map tiles](https://github.com/shrddr/shrddr.github.io/tree/main/maptiles)

No separate written licence was found. The project owner accepted the remaining risk for this credited, free fan app; this is not permission from Shrddr. Keep attribution and respond promptly to substantiated correction/removal requests. Review new evidence that prohibits use; absence of a separate licence alone does not change the recorded owner decision. Each group can be replaced independently.

## SomethingLovely

The historical location layer includes 12,582 points from [SomethingLovely](https://github.com/fffam/blackdesert-somethinglovely-map), commit `289c833d34851dc84f3a647a2d9cf604eda9c93a`. It is historical through 2021, not complete current coverage.

Keep `packages/bdo_map_core/assets/licenses/SOMETHINGLOVELY-MIT.txt` with distributions containing it. MIT covers the upstream licensed material, not Pearl Abyss IP.

## bdo-empire

[bdo-empire](https://github.com/Thell/bdo-empire) 0.8.1, commit `4a24b6f42926543e5f3eae5c8c559ebd689b698c`, supplies calculation code under the Unlicense. This does not license its Workerman data inputs. Keep `packages/bdo_map_core/assets/licenses/BDO-EMPIRE-UNLICENSE.txt` and the separate Workerman use record.

## bdo-data-extractor

A private Edania cross-check used output from [bdo-data-extractor](https://github.com/iDevelopThings/bdo-data-extractor), commit `2e4ace61e2a3967663cb36580edb7201b7ca3fd4`. Its licence covers its code/docs, not extracted game content. The reduced research seed is not an installer asset.

## Velopack

[Velopack](https://velopack.io/) 1.2.0 handles Windows packaging/updates. Keep its complete licence at `windows/third_party/velopack/1.2.0/LICENSE`.

## Other research

Further citations include Pearl Abyss, Caphras Archives, Black Desert Foundry, GrumpyG, Inven Global and `api.blackdesertmarket.com`. Credits identify research sources; copied creative material and organized datasets are listed separately in the source rules.

## Corrections or removal

Open **Issues → Report a mistake or request removal**. Name the file, item or screen, explain the concern and say what should change. Do not post private information or confidential proof. If private evidence is needed, first ask the owner for a private contact route.
