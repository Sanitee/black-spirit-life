# Public source and credit rules

This records the source review through **October 29, 2026 (0.1.15)**. Counts and hashes describe that review, not a fresh audit of every later release. See [release notes](releases/) for later changes.

Public repository: <https://github.com/Sanitee/black-spirit-life>. Package: `BlackSpiritLife.App`; update channel: `win-x64-stable`.

## What may be published

Keep the complete approved application and its reviewed reference data. Exclude personal saves, accounts, credentials, browser state, private machine paths, caches and internal release evidence. Private Beta Git history must not enter the public repository.

Pearl Abyss owns the game content. The project uses its [Fan Content Guidelines](https://www.pearlabyss.com/en-US/legal/detail?_policyNo=42) for this free, unofficial, noncommercial fan app. Keep the exact notice and credits. The code licence grants no rights in third-party content.

BDO Codex and BDOLytics are research/mirror references. The project owner confirms that their website design, HTML, guide prose, commentary, annotations and custom translations are not retained. Licensed material keeps its licence; copied creative material or complete organized datasets need their own recorded treatment. This is the project's release decision, not a legal opinion for every jurisdiction.

## Credited use without separate permission

The owner accepted the remaining risk for the named Workerman/Shrddr, FishyStuff, Bairog/BDO Workshop, Garmoth and creator materials below. Public availability and attribution are **not** a licence or written permission. Do not describe the owner's decision as permission from those sources.

Keep credits, source links and a correction/removal route. Workerman's recorded scope covers map tiles/cache, 64 node icons, the 812-house/31-town graph and economics inputs for 352 sites/30 towns. These groups remain replaceable if a substantiated request requires it. Do not reopen that decision solely because no separate licence was found; review new concrete evidence.

## Reviewed source list

Exact scope and qualifications are retained here for attribution and future corrections:

| ID | Material / exact scope | Classification | Result | Release treatment |
|---|---|---|---|---|
| PA-01 | Overall Black Desert fan project | Pearl Abyss fan content | **Satisfied** | Keep the project free, unofficial and noncommercial; retain the exact required notice in README and release notes; keep third-party material outside the code licence |
| PA-02 | Black Desert item/NPC names, descriptions, recipes, prices, IDs, coordinates, node/vendor facts, 4,486 named embedded icon entries, eight gathering-tool icons and 231 NPC portraits | Pearl Abyss-origin facts and game artwork | **Satisfied** | Retain PA attribution and fan-content notice; BDO Codex/BDOLytics remain credited references or mirrors, not separate owners of these facts/assets |
| PA-03 | 154 Opportunities item icons and the Resource Map house, material, silver and bare-hands UI textures | Pearl Abyss-origin game artwork extracted from the owner's installed client | **Satisfied** | Ship only decoded artwork plus neutral client-relative provenance, hashes and sizes; no client path, extractor payload or account data is retained |
| PRIV-01 | Per-user Fishing profile/journal databases, SQLite sidecars, haul/sale records and generated WebView profile | Personal player/publisher data | **Excluded** | Ship the complete Fish Map and immutable bundled Fishing reference databases/datasets, but no generated `fish-journal*.sqlite3*` file or browser state; create/load these only beneath the selected personal-data root, and migrate existing v0.1.7 profiles and aggregate journals without fabricating catches or sales |
| PRIV-02 | Gathering mastery, loadout notes and sessions plus four full-frame guide captures exposing real player/browser context | Personal player/publisher data and privacy-bearing media | **Excluded** | Ship the complete Gathering workflow and eleven remaining credited guide images; migrate existing v0.1.7 mastery, notes and sessions from the selected root while preserving the source, and retain links/credits for the four omitted captures without redistributing their pixels |
| PRIV-03 | Garmoth login, cookies, browser profile, saved sessions, drafts and receipts | Personal account/activity data | **Excluded** | Ship the approved integration/helper and immutable public catalog/art inputs only; generate and read personal state beneath the selected local data root |
| FISH-01 | FishyStuff map/API/Dex snapshot, derived region/map files, branding and organized reference data | Credited third-party reference corpus plus PA-origin game facts/art | **Owner-approved credited inclusion; no separate licence or written permission claimed** | Preserve exact sources/credits and immutable product hashes; keep these reference databases/datasets bundled and non-personal, with user profiles/journals in a separate runtime database |
| FISH-02 | Fish recognition catalog and item images | PA-origin game art delivered through credited FishyStuff/BDO Codex URLs | **PA fan content / owner-approved credited delivery source** | Retain exact URL/hash catalog and PA attribution; no recognition result or user screenshot is bundled |
| GATH-01 | Bairog Haan / BDO Workshop calculator inputs, 20-route benchmark set and source logo | Credited third-party reference data/expression plus PA facts | **Owner-approved credited inclusion; no separate licence or written permission claimed** | Preserve visible source link, exact assumptions and provenance; do not present benchmark data as user history |
| GATH-02 | Eleven retained Gathering guide images and linked creator videos | Four PA update illustrations plus credited creator expression | **PA fan content / owner-approved credited creator references** | Preserve creator/source credits and limitations; no creator licence or permission is claimed; do not bundle the four privacy-bearing captures |
| GARM-01 | Garmoth public sidebar/site IDs, supported session-column snapshot, official site icon, PA static art and app-managed integration | Credited service reference material plus project-owned integration code | **Owner-approved credited inclusion; no Garmoth licence or written permission claimed** | Keep public page patterns/provenance and user-directed operation; exclude all login/cookie/profile/session state |
| REF-01 | BDO Codex and BDOLytics URLs, recipe IDs, item IDs and retrieval notes | Research/provenance references | **No blocker** | Retain citations for auditability. The generated runtime scan found no HTML/page markup; source-domain strings are provenance URLs, IDs and project-authored source notes |
| FACT-01 | App-specific cooking/alchemy data: 178 added alchemy recipes, 461 added cooking recipes, preserved project records and normalized ingredients/yields/variants | Selected PA game facts in project schema | **No blocker** | No raw recipe-page or site database export is tracked or shipped; no site-authored prose or layout is retained |
| FACT-02 | App-specific processing catalog: 602 planner-relevant recipes curated from 4,824 reviewed rows | Selected PA game facts in project schema | **No blocker** | The shipped file retains the curated planner schema, not the 4,824-row source export; cross-reference IDs and URLs remain provenance only |
| FACT-03 | 501 Stone Cobra/Rock Scorpion, 34 Coral Stoneback Crab and 198 Stillcoral positions | Selected PA in-game coordinates transformed into map records | **No blocker** | Keep the app-specific layers and factual provenance; no route geometry, page design or site commentary is copied |
| FACT-04 | Royal Workshop (124 goods/eight managers), Edania (28 nodes/37 resources plus Part II facts), Caphras cross-checks (36 identities/18 coordinates), 982 project-authored acquisition records, and the numeric Central Market eligibility/enhancement identity tables | Official/client-verified PA facts and project-authored summaries | **No blocker** | Retain source links and correction route; no client path, account data, extractor payload or third-party presentation is retained |
| FACT-05 | `resource_map.json` vendor subset: 51 relevant items, 266 physical pins and 1,243 listings selected from the researched vendor rows | PA facts selected and normalized into Black Spirit Life's app-specific schema | **No blocker** | This is a purpose-limited planner subset, not a wholesale copy of either reference site's database. Keep the credited research links and current-game correction route |
| FACT-06 | `resource_map.json` `workerNodes`: 1,052 PA world-map records and 1,622 node-output relationships across 285 PA game items | PA facts selected, normalized and connected for Black Spirit Life's worker network, calculations and map UI | **No content blocker** | Credit PA as game-content owner and BDO Codex as a research/extraction reference. The numeric icon/layer fields are internal map-model metadata, not copied site presentation |
| REF-RAW-01 | Tracked world-map seeds with 1,008 and 1,052 nodes | Source-only private normalized research inputs containing complete one-source world-map collections | **Excluded from the public repository** | Exclude the two exact files listed below from the clean public snapshot; retain internal provenance privately. Do not delete the internal copies |
| REF-PRIVATE-02 | Rusalka, Stillcoral, vendor and portrait private research inputs | Narrower app-specific research/provenance records rather than runtime assets or wholesale site exports | **Excluded from the public repository for hygiene** | Exclude the four exact files listed below while retaining the generated runtime datasets and internal provenance |
| SHR-01 | Runtime `workerman-community-120138d` tile URL and 64 MiB cache | Workerman/Shrddr public community basemap and runtime hotlink | **Owner-approved community use; no separate licence file found** | Keep the credited full map under the explicit owner decision; retain the provider boundary and takedown/replacement path. No tile files are bundled |
| SHR-02 | `packages/bdo_map_core/assets/images/node_icons/**`: 64 exact PNG copies, 1,625,566 bytes | Workerman/Shrddr public community icon set | **Owner-approved community use; no separate licence file found** | Keep the credited glyphs under the explicit owner decision; they remain independently replaceable after a substantiated request |
| SHR-03 | `lodging_houses.json`: complete 812-house/31-town prerequisite graph | Workerman-organized data containing PA game facts | **Owner-approved community use; no separate licence file found** | Keep the credited lodging tool intact under the explicit owner decision; retain its independent adapter and correction route |
| SHR-04 | `worker_economics.json`: Workerman-derived inputs for 352 sites/30 towns | Workerman-organized inputs plus separately licensed calculation code | **Owner-approved community use; no separate licence file found** | Keep the credited economics tool intact; preserve the Unlicense notice and independent input boundary |
| SL-01 | 12,582 historical SomethingLovely gathering points | Licensed upstream dataset | **Cleared** | Preserve the bundled MIT notice and historical-through-2021 label |
| EMP-01 | `bdo-empire` calculation code | Upstream Unlicense | **Cleared** | Preserve the notice; Workerman-derived inputs remain isolated under SHR-04 |
| ART-01 | Sakura art, installer derivatives and project-held app/ledger/scene artwork | Project-authored/project-held expression; no identified community-site source | **No blocker** | Preserve hashes and generation records. Completing older creation notes is good provenance work, not a generalized release block without contrary evidence |
| API-01 | Official/community market APIs, FishyStuff refresh endpoints, credited creator-video playback and user-directed Garmoth interaction | Runtime services; Fishing additionally ships the reviewed reference snapshot classified in FISH-01 | **No separate runtime-service blocker** | Respect live service limits, keep unrelated work offline-safe, and do not add personal profile/session data to reference requests |
| CODE-01 | Original Black Spirit Life source code | Project-owned code | **Cleared** | Root `LICENSE` remains separate and expressly grants no rights in PA artwork, game data or other third-party material |
| CODE-02 | Approved Beta Gathering, Fish Map, and Session Import implementations promoted for 0.1.9 | Project-owned code/runtime plus PA-origin facts/art and user-authored local records | **Cleared within the rows above** | Preserve exact product behavior and immutable reference inputs; persist every generated profile, setting, browser state, loadout and session beneath the selected personal-data folder |
| DEP-01 | `webview_flutter_windows` fork, Microsoft.Web.WebView2 package and WebView2 loader/runtime interface | BSD-3-Clause fork plus Microsoft dependency/runtime | **Cleared subject to retained notices** | Keep the accepted temporary Fish WebView implementation, explicit selected-root browser storage and shutdown lifecycle; never bundle a generated browser profile |
| CODE-03 | Session Import Windows/.NET helper, native host, browser extension and OCR helper | Project-owned code plus Microsoft .NET/WebView2 dependencies | **Cleared subject to the GARM-01/PRIV-03 boundaries** | Ship manifest-verified release payload without PDBs, local paths, credentials, browser state, drafts, receipts or sessions |
| VPK-01 | Velopack 1.2.0 | Licensed dependency | **Cleared** | Preserve the bundled licence and pinned checksums |
| OCR-01 | Black Spirit Hub v0.9.52 storage-grid recognition source and sealed Recipe Book snapshot, commit `6ccbad52d25b54d8b67065ce8a9eb1bcece87d9f` | Shared implementation with project-owner reuse authorization | **Cleared for Black Spirit Life reuse** | Preserve `SOURCE-NOTICE.txt`; do not describe the authorization as a general licence grant to third parties |
| OCR-02 | PaddleOCR PP-OCRv5 model and ONNX Runtime 1.29.0 | Licensed dependencies | **Cleared** | Preserve the PaddleOCR, model, ONNX Runtime, and complete third-party notices beside the helper payload |
| OCR-03 | 3,897 sealed Recipe Book item icons and two generated recognition atlases | Pearl Abyss-origin game artwork used by the isolated OCR helper | **Satisfied** | Retain PA attribution and the helper asset notice; private contributor screenshot fixtures remain excluded from public source and packages |

## Private research files

Keep these out of public source and packages, while preserving internal copies:

- `packages/bdo_map_core/tool/seeds/bdocodex_worldmap_2026_07_29_private_seed.json`
  (619,297 bytes; 1,008 nodes; SHA-256
  `06FAD53C9E282AC942BA4F3642939D0C975A3AE95670BA8AF921E982F9C32BD4`);
- `packages/bdo_map_core/tool/seeds/bdocodex_worldmap_2026_08_15_private_seed.json`
  (644,544 bytes; 1,052 nodes; SHA-256
  `752DC2AF7C7350D1E8154984D12DD200559460D51C6FFDE521099A6A52EF375C`);
- `packages/bdo_map_core/tool/seeds/rusalka_coral_bdocodex_2026_07_28_private_seed.json`;
- `packages/bdo_map_core/tool/seeds/stillcoral_coastal_gathering_bdocodex_2026_08_01_private_seed.json`;
- `packages/bdo_map_core/tool/seeds/vendor_npcs_bdocodex_2026_08_15_private_seed.json`;
- `packages/bdo_map_core/tool/seeds/vendor_npc_portraits_2026_08_16_private_manifest.json`.

The runtime map is separate: it contains selected game facts in the app's own format, not raw responses or website presentation. Excluding research inputs must not remove the approved map features.

## Personal data

Bundle immutable Fishing reference data, never generated journals, profile databases or SQLite sidecars. Apply the same rule to Gathering, Planner, Opportunities, imports and browser/account state. Four guide captures exposing player/browser context are excluded; their links and credits remain.

Updates keep each user's selected save folder outside the installation. Older migrations preserve original files and backups. Fishing aggregate history stays read-only without invented catches/sales. Gathering history keeps its recorded fields without invented loot or missing inputs. See the migration documents for exact mappings.

## Release checks

Publish only the approved source and artifacts after their required privacy, package, install/update, save-preservation and public-route checks. Retain exact hashes and all failures or unrun checks in the audit. Source classification alone is not release acceptance.

No permission-request draft may be sent without an explicit instruction. Credits and notices must not be removed to shorten documentation.
