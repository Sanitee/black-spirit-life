# Asset and dataset sources

Review snapshot: 2026-08-16
Technical baseline: Black Spirit Life `0.1.3+22`, commit
`8ab34ffbb7013cffbc340868646f56bfa83299cf`

This inventory separates ownership of underlying material from the websites
used to find or verify it. The controlling release decision is
`docs/public-release-source-matrix.md`.

Status vocabulary:

- **PA fan content**: Pearl Abyss-origin Black Desert game content or facts
  used under the project's free, unofficial, noncommercial fan-content basis.
- **Research reference**: a credited website helped locate or cross-check a
  fact or PA asset but no website-authored expression is retained.
- **Project-authored**: Black Spirit Life's code, selection, normalization,
  calculations, relationships, summaries, artwork or presentation.
- **Licensed**: a recorded upstream licence covers the retained material.
- **Owner-approved community use**: the credited material is intentionally
  public and community-hosted, no separate licence file was found, and the
  project owner accepts the residual risk for this free noncommercial release.
  This is not represented as separate written permission.

## Pearl Abyss-origin game content and facts

The project owner confirms that the retained icons, portraits, in-game text,
translations and facts found through BDO Codex or BDOLytics originate directly
from Black Desert. The application retains no website design, HTML, guide
prose, commentary, annotation or other original site presentation. BDO Codex,
BDOLytics and other sites are credited as research, cross-checking or mirror
references; Pearl Abyss is credited as owner of the underlying game content.

| Shipped material | Research / retrieval references | Black Spirit Life treatment | Status |
|---|---|---|---|
| Embedded item artwork in `assets/data/app-data.json`: 438 base, 612 cooking and 3,436 processing name entries | PA item artwork retrieved through BDO Codex mirror records; BDOLytics cross-checks; official PA sources for Edania | Converted to local data URLs and keyed through the app's own catalog | **PA fan content**; no separate mirror-site permission blocker |
| `packages/bdo_map_core/assets/images/gathering_tools/*.webp`: eight tool icons | BDO Codex item pages and URLs recorded in `BDO-CODEX-GATHERING-TOOL-ICON-NOTICE.md` | Eight local 44 x 44 PA game icons | **PA fan content** |
| `packages/bdo_map_core/assets/images/vendor_portraits/*.webp`: 231 portrait files for 251 mappings | PA NPC artwork retrieved through BDO Codex mirror paths; exact hashes/URLs in the project provenance manifest | Pinned local 360 x 360 files; no runtime hotlink; app silhouette used when artwork is unavailable | **PA fan content** |
| Cooking/alchemy recipes | BDO Codex, BDOLytics, user lists and game verification | 178 added alchemy and 461 added cooking records normalized into the planner's ingredient/yield/variant schema | **PA facts in project-authored compilation**; no raw site export shipped |
| Processing recipes | BDO Codex processing records and BDOLytics category cross-checks | 602 planner-relevant records curated from 4,824 reviewed rows; raw rows and site structure are not tracked or shipped | **PA facts in project-authored compilation** |
| Edania Part II facts | Official PA patch notes plus BDO Codex item cross-checks | Two alchemy recipes, 32 conversions, 24 reference items and 83 icon entries in the existing planner schema | **PA fan content** |
| Acquisition catalog | Official PA pages, market API and credited community research | 982 project-authored records / 1,164 routes with 2,569 traceability links | **PA facts plus project-authored summaries** |
| Vendor map subset | BDO Codex seller/NPC records used as research | 51 relevant items selected into 266 physical pins and 1,241 listings; nonphysical/unmapped records fail closed | **PA facts in a purpose-limited project schema**; not a wholesale website database |
| Selected gathering coordinates | BDO Codex map records used as research | 501 Stone Cobra/Rock Scorpion, 34 Coral Stoneback Crab and 198 Stillcoral points transformed to game coordinates; no copied route, page or annotation | **PA facts in project-authored map records** |
| Royal Workshop, Caphras and Edania node facts | Official PA pages, client verification and credited references | 124 goods/eight managers; 36 identities/18 coordinates; reduced Edania 28-node/37-resource seed | **PA facts in project-authored records** |

The exact required notice remains prominent:

> This is unofficial content which contains copyrighted materials and IP from Pearl Abyss, and is not official/endorsed content.

## Owner-approved Workerman/Shrddr community-use groups

| Exact component | Source | Retained form | Status / narrow replacement |
|---|---|---|---|
| Runtime basemap provider `workerman-community-120138d` in `packages/bdo_map_core/lib/src/model/tile_source.dart` | Workerman/Shrddr tile set at `https://shrddr.github.io/maptiles/{z}/{x}_{y}.webp` | Runtime hotlink with clearable 64 MiB cache; no tiles bundled | **Owner-approved community use; no separate licence file found**; keep credit, provider boundary and takedown route |
| `packages/bdo_map_core/assets/images/node_icons/**` | Exact copies from `shrddr/workermanjs` commit `cb4965a5be4e68f231c4bbad7b7a87003e27038b` | 64 unchanged PNGs, 1,625,566 bytes | **Owner-approved community use; no separate licence file found**; keep credit and independent replacement boundary |
| `packages/bdo_map_core/assets/data/lodging_houses.json` | Complete Workerman housing inputs | 812 houses / 31 towns and prerequisite graph | **Owner-approved community use; no separate licence file found**; keep the full credited lodging tool |
| Workerman-derived inputs inside `packages/bdo_map_core/assets/data/worker_economics.json` | Workerman data snapshot processed with `bdo-empire` | Workload/yield/distance/worker inputs for 352 sites / 30 towns | **Owner-approved community use; no separate licence file found**; keep the full credited tool and the separate Unlicense notice |

Workerman is publicly hosted for community use and directs users to a public
GitHub issue tracker. Black Spirit Life is free and noncommercial, provides
full attribution, and will respond promptly to correction or removal requests.
No separate written licence was found, so this basis is recorded as an owner
risk decision rather than permission.

No BDO Codex- or BDOLytics-referenced icon, portrait, recipe, description,
price, NPC, coordinate or normalized worker-node record is a separate
permission blocker.

## Black Spirit Life map contribution

Black Spirit Life independently created the complete map interface, rendering,
interaction, search, filtering, routing, calculations and presentation. The
runtime `workerNodes` array contains 1,052 Pearl Abyss-origin node facts and
1,622 node-output relationships normalized into Black Spirit Life's own
application schema. BDO Codex is credited as the retrieval/reference source,
not as owner of the Black Desert map, nodes or game facts.

The runtime JSON contains no raw response, HTML or copied page structure. Its
numeric icon/layer fields are internal map-model metadata. The owner has
directed that the full current map and presentation remain intact.

## Licensed and project material

| Material | Source / licence | Status |
|---|---|---|
| 12,582 historical gathering points | `fffam/blackdesert-somethinglovely-map` commit `289c833d34851dc84f3a647a2d9cf604eda9c93a`; bundled MIT notice | **Licensed**; keep the historical-through-2021 label |
| Worker-economics calculation code | `bdo-empire` 0.8.1 / commit `4a24b6f...`; bundled Unlicense | **Licensed**; data inputs remain separately isolated above |
| Sakura botanicals/materials and themed-installer derivatives | Project image-generation record in `docs/themes/sakura-night-garden/ASSET_GENERATION.md` | **Project-authored** |
| App icons, Ledger art and eight scene backdrops | Project-held accepted application checkpoint; no community-site source identified | **Project-held**; complete older creation notes when available, but general provenance uncertainty is not an unrelated release blocker |
| Original Black Spirit Life code | Project contributor ownership; root `LICENSE` | **Project-owned**; licence grants no rights in PA or other third-party material |
| Velopack 1.2.0 | Bundled upstream licence | **Licensed** |

Exact application-art hashes are recorded in
`docs/public-release-asset-manifest.sha256`.

## Private research inputs versus public app data

The application-specific generated files contain normalized Black Desert facts
and project provenance, not HTML or copied website presentation. A structured
scan of the shipped JSON found zero HTML-like strings. Source-domain strings
are URLs, reference IDs and project-authored research notes.

Six tracked source-only private research inputs are excluded from the clean
public snapshot. Two contain an entire single-source world-map collection:

- `packages/bdo_map_core/tool/seeds/bdocodex_worldmap_2026_07_29_private_seed.json`
  — 1,008 nodes, 619,297 bytes;
- `packages/bdo_map_core/tool/seeds/bdocodex_worldmap_2026_08_15_private_seed.json`
  — 1,052 nodes, 644,544 bytes.

The other four excluded private research inputs are:

- `packages/bdo_map_core/tool/seeds/rusalka_coral_bdocodex_2026_07_28_private_seed.json`;
- `packages/bdo_map_core/tool/seeds/stillcoral_coastal_gathering_bdocodex_2026_08_01_private_seed.json`;
- `packages/bdo_map_core/tool/seeds/vendor_npcs_bdocodex_2026_08_15_private_seed.json`;
- `packages/bdo_map_core/tool/seeds/vendor_npc_portraits_2026_08_16_private_manifest.json`.

They are not installer assets. The four narrower coordinate/vendor/portrait
records are app-specific research records rather than wholesale site exports;
their exclusion is repository hygiene, not a content blocker. The internal
copies remain untouched.

## Runtime services

Market-price refresh can contact official Pearl Abyss endpoints and the
community Arsha/Black Desert Market API. No response corpus is bundled. The
app must respect live service limits, fail without blocking offline use, and
never mix responses into personal planner data without the user's action.

## Replacement boundary

The basemap provider, node glyphs, lodging graph and economics inputs remain
independently replaceable for a future correction or substantiated takedown.
The current release retains them under the explicit owner community-use decision; no
replacement may alter worker-node facts, recipes, portraits, vendor facts,
gathering overlays, inventory, profiles, custom personal-data locations,
themes or the rest of the planner/map interface.
