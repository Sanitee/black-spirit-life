# Asset and data credits

This source inventory began with the September 15, 2026 review and includes later recorded additions. Counts describe those reviews, not a live catalogue count. See the [source rules](docs/public-release-source-matrix.md) and [notices](THIRD_PARTY_NOTICES.md).

- **PA fan content:** Black Desert content owned by Pearl Abyss.
- **Research reference:** a source used to find or check facts or game artwork.
- **Project-authored:** Black Spirit Life's own code, summaries, calculations or artwork.
- **Licensed:** covered by a recorded upstream licence.
- **Owner-approved use:** retained with credit despite no separate licence or written permission; the project owner accepts the remaining risk.

## Game content

Pearl Abyss owns the underlying game art and facts. BDO Codex and BDOLytics are credited references, not the owners of those game assets. The project owner confirms that website design, HTML, guides, commentary and other site-authored presentation are not retained.

| Shipped material | Research / retrieval references | Black Spirit Life treatment | Status |
|---|---|---|---|
| Embedded item artwork in `assets/data/app-data.json`: 438 base, 612 cooking and 3,436 processing name entries | PA item artwork retrieved through BDO Codex mirror records; BDOLytics cross-checks; official PA sources for Edania | Converted to local data URLs and keyed through the app's own catalog | **PA fan content**; no separate mirror-site permission blocker |
| `windows/storage_ocr/BlackSpiritStorageOcr/Assets/RecipeBook/icons/items/**`: 3,897 sealed OCR reference icons plus two generated atlases | PA item artwork in the shared Black Spirit Hub Recipe Book snapshot | Local, hash-verified recognition references used only by the isolated Windows OCR helper | **PA fan content**; provenance and redistribution notices stay beside the helper |
| `packages/bdo_map_core/assets/images/gathering_tools/*.webp`: eight tool icons | BDO Codex item pages and URLs recorded in `BDO-CODEX-GATHERING-TOOL-ICON-NOTICE.md` | Eight local 44 x 44 PA game icons | **PA fan content** |
| `packages/bdo_map_core/assets/images/vendor_portraits/*.webp`: 231 portrait files for 251 mappings | PA NPC artwork retrieved through BDO Codex mirror paths; exact hashes/URLs in the project provenance manifest | Pinned local 360 x 360 files; no runtime hotlink; app silhouette used when artwork is unavailable | **PA fan content** |
| `assets/opportunities/items/**`: 154 item icons | Read-only extraction from the owner's installed Black Desert PC client; client-relative provenance, hashes and sizes in `assets/opportunities/icon-provenance.json` | Unmodified local icons used by the Opportunities workspace; no local installation path or extractor payload retained | **PA fan content** |
| `assets/app/availability_*.png`: three game UI references | Owner-supplied marketplace Buy/Sell, marketplace coin bag and Inventory screenshots, approved 5 November 2026 | Byte-exact local references; shared UI selects and tints only each icon at render time. Buy cart is the approved app mapping for Preorders, not a claimed original preorder glyph. NPC reuses the existing interaction texture | **PA fan content**; see `docs/consistent-market-indicators.md` |
| Central Market eligibility and enhancement identity tables | Project-held audits of the 3 and 10 September 2026 PC client item metadata; public scope and source hashes in `docs/opportunities-market-eligibility.md` | Numeric item IDs and boolean/enhancement flags only; no client path, account data or extractor payload retained | **PA facts in project-authored records** |
| Resource Map menu, house-use and bare-hands interaction textures | Read-only extraction from the owner's installed Black Desert PC client; exact archive paths and hashes in the three `pearl-abyss-*.md` notices beside the assets | Decoded local artwork used only in the public Resource Map interface | **PA fan content** |
| Cooking/alchemy recipes | BDO Codex, BDOLytics, user lists and game verification | 178 added alchemy and 461 added cooking records normalized into the planner's ingredient/yield/variant schema | **PA facts in project-authored compilation**; no raw site export shipped |
| Processing recipes | BDO Codex processing records and BDOLytics category cross-checks | 602 planner-relevant records curated from 4,824 reviewed rows; raw rows and site structure are not tracked or shipped | **PA facts in project-authored compilation** |
| Edania Part II facts | Official PA patch notes plus BDO Codex item cross-checks | Two alchemy recipes, 32 conversions, 24 reference items and 83 icon entries in the existing planner schema | **PA fan content** |
| Acquisition catalog | Official PA pages, market API and credited community research | 982 project-authored records / 1,164 routes with 2,569 traceability links | **PA facts plus project-authored summaries** |
| Vendor map subset | BDO Codex seller/NPC records used as research | 51 relevant items selected into 266 physical pins and 1,243 listings; nonphysical/unmapped records fail closed | **PA facts in a purpose-limited project schema**; not a wholesale website database |
| Selected gathering coordinates | BDO Codex map records used as research | 501 Stone Cobra/Rock Scorpion, 34 Coral Stoneback Crab and 198 Stillcoral points transformed to game coordinates; no copied route, page or annotation | **PA facts in project-authored map records** |
| Royal Workshop, Caphras and Edania node facts | Official PA pages, client verification and credited references | 124 goods/eight managers; 36 identities/18 coordinates; reduced Edania 28-node/37-resource seed | **PA facts in project-authored records** |

> This is unofficial content which contains copyrighted materials and IP from
> Pearl Abyss, and is not official/endorsed content.

## Workerman / Shrddr

| Exact component | Source | Retained form | Status / narrow replacement |
|---|---|---|---|
| Runtime basemap provider `workerman-community-120138d` in `packages/bdo_map_core/lib/src/model/tile_source.dart` | Workerman/Shrddr tile set at `https://shrddr.github.io/maptiles/{z}/{x}_{y}.webp` | Runtime hotlink with clearable 64 MiB cache; no tiles bundled | **Owner-approved community use; no separate licence file found**; keep credit, provider boundary and takedown route |
| `packages/bdo_map_core/assets/images/node_icons/**` | Exact copies from `shrddr/workermanjs` commit `cb4965a5be4e68f231c4bbad7b7a87003e27038b` | 64 unchanged PNGs, 1,625,566 bytes | **Owner-approved community use; no separate licence file found**; keep credit and independent replacement boundary |
| `packages/bdo_map_core/assets/data/lodging_houses.json` | Complete Workerman housing inputs | 812 houses / 31 towns and prerequisite graph | **Owner-approved community use; no separate licence file found**; keep the full credited lodging tool |
| Workerman-derived inputs inside `packages/bdo_map_core/assets/data/worker_economics.json` | Workerman data snapshot processed with `bdo-empire` | Workload/yield/distance/worker inputs for 352 sites / 30 towns | **Owner-approved community use; no separate licence file found**; keep the full credited tool and the separate Unlicense notice |

No separate written licence was found. Public hosting and credit are not permission. The project owner accepted this use for the free fan app; corrections and substantiated removal requests will be handled through Issues. Each group remains replaceable.

## Other materials

| Material | Source / licence | Status |
|---|---|---|
| 12,582 historical gathering points | `fffam/blackdesert-somethinglovely-map` commit `289c833d34851dc84f3a647a2d9cf604eda9c93a`; bundled MIT notice | **Licensed**; keep the historical-through-2021 label |
| Worker-economics calculation code | `bdo-empire` 0.8.1 / commit `4a24b6f...`; bundled Unlicense | **Licensed**; data inputs remain separately isolated above |
| Sakura botanicals/materials and themed-installer derivatives | Project image-generation record in `docs/themes/sakura-night-garden/ASSET_GENERATION.md` | **Project-authored** |
| App icons, Ledger art and eight scene backdrops | Project-held accepted application checkpoint; no community-site source identified | **Project-held**; complete older creation notes when available, but general provenance uncertainty is not an unrelated release blocker |
| Fish Companion code and local service | Project-owned Dart/Python code plus CPython, PyInstaller, NumPy, Pillow, OpenSSL, libffi, zlib, and SQLite components documented beneath `packages/bdo_fishing_core/assets/fish_companion/runtime` | **Project-owned / licensed dependencies**; executable SBOM and complete dependency notices are retained |
| Fishing map/reference snapshot, FishyStuff branding, node markers, and recognition icons | Public FishyStuff map/API/Dex/CDN responses and PA-origin item artwork, retained from the approved Beta with source URLs and catalog hashes | **Owner-approved credited reference use; no separate redistribution licence or written permission is claimed**; no profile or journal database is included |
| Gathering companion reference data and Bairog/BDO Workshop material | Credited Bairog Haan / BDO Workshop gathering calculator, route benchmarks, logo, creator links, and PA-origin game facts/art | **Owner-approved credited reference use; no separate redistribution licence or written permission is claimed**; local user settings/loadouts/sessions are not bundled |
| Eleven Gathering guide images | Four PA update illustrations plus credited MMOSUMO/alext96, GrumpyG, Saarith, and bunnygirl guide frames recorded in `packages/bdo_gathering_companion/assets/rotations/NOTICE.md` and `provenance.json` | **PA fan content / owner-approved credited creator references**; no creator licence or permission is claimed; four privacy-bearing full-frame captures are excluded |
| Garmoth Session Import integration | Project-owned local helper/automation code, public Garmoth sidebar/session-column snapshot, official site icon, PA-origin static art, and source URLs recorded with the feature | **Project-owned code / owner-approved credited service references**; no Garmoth licence or written permission is claimed and no saved account/session/browser state is included |
| `webview_flutter_windows` fork and WebView2 loader | BSD-3-Clause upstream source plus Microsoft WebView2 interfaces; the package retains its licence and local-change notice | **Licensed source dependency**; the installed runtime and generated user profiles are external to the release payload |
| Original Black Spirit Life code | Project contributor ownership; root `LICENSE` | **Project-owned**; licence grants no rights in PA or other third-party material |
| Velopack 1.2.0 | Bundled upstream licence | **Licensed** |
| PaddleOCR PP-OCRv5 recognition model and ONNX Runtime 1.29.0 | Upstream licences and complete notices under `windows/storage_ocr/BlackSpiritStorageOcr/Assets/RecipeBook/ocr` | **Licensed**; notices remain in the helper payload |
| Shared Black Spirit Hub v0.9.52 OCR implementation | Black Spirit Hub commit `6ccbad52d25b54d8b67065ce8a9eb1bcece87d9f`; the owner shared it with the Black Spirit Life owner for reuse | **Owner-authorized reuse** recorded in `SOURCE-NOTICE.txt`; not represented as a general third-party licence |

Application artwork hashes are in `docs/public-release-asset-manifest.sha256`. Keep all bundled upstream licences and notices.

## Excluded material

The [source rules](docs/public-release-source-matrix.md#private-research-files) list six private research files that must stay out of public source. Their reviewed runtime data is separate and remains included.

Never bundle personal Planner, Gathering or Fishing records, import drafts/receipts, accounts, credentials, browser profiles, caches, debug symbols or local machine paths. Personal Fishing databases are created under the selected save folder, not shipped as reference data.

## Online services

Market refresh uses official Pearl Abyss and community market APIs. Fishing may refresh public reference data; Gathering can open credited videos; Session Import uses the user-directed Garmoth workflow. Respect service limits and keep unrelated offline features usable when a service fails. No publisher account or personal history belongs in a release.
