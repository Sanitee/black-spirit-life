# Public-release source matrix

Review result: **proportionate source review complete; project-owner
Workerman community-use decision and accepted residual risk recorded; private
Beta integrations, personal data, and six source-only research inputs excluded
from the public tree**

Release identity: Black Spirit Life `0.1.7+26`, tag `v0.1.7`, package
`BlackSpiritLife.App`, channel `win-x64-stable`. The exact source commit and
artifact hashes are recorded by the release-candidate manifest generated from
the sanitized public history, which contains no internal Beta history.

Review date: 2026-09-15

Permanent public/update destination approved by the project owner:
`https://github.com/Sanitee/black-spirit-life`

This is the controlling source-by-source gate for the full-feature public
route. It replaces earlier blanket treatment of every fact or game asset seen
through a community reference as separately blocked.

## 0.1.7 public-promotion boundary

Version 0.1.7 preserves the reviewed Planner, Resource Map, shared market,
Opportunities, and update-notice work and adds original native Gathering and
Fishing local-record workspaces. It does not copy the Beta repository or its
history.

The following remain private and are absent from public source and packages:

- the private Fish Companion WebView/Python code, FishyStuff cache/data,
  private icons and bundled fishing journals/loadouts;
- the standalone Gathering Companion package, guide media, Bairog-derived
  data, copied site logos and legacy import inbox;
- Garmoth session-import code, captured catalog/art and all saved sessions;
- every local user profile, mastery value, inventory, plan, favorite, loadout,
  session, cache, credential, screenshot and machine-specific path.

A fresh install therefore contains no personal profile values, loadouts or
sessions. The app loads an existing Stable profile only from the locally
selected personal-data folder. All user-authored Planner, Resource Map,
Gathering, Fishing and Opportunities state is stored beneath that folder and
read back from there. The folder is shown in the title bar and can be changed
from the in-app Craft Profile page; ordinary updates keep it outside the
installation directory and do not replace it.

## Proportionate review standard

1. Pearl Abyss's published
   [Fan Content Guidelines](https://www.pearlabyss.com/en-US/legal/detail?_policyNo=42)
   are the permission basis for this personal, free, unofficial,
   noncommercial fan project. A personal reply from Pearl Abyss is not a
   release prerequisite.
2. The Pearl Abyss condition is satisfied for this project through the exact
   required unofficial-content notice, clear attribution, noncommercial
   distribution, a correction/takedown route, and a code license that grants
   no rights in Pearl Abyss or third-party content.
3. Verified Black Desert names, recipes, descriptions, prices, IDs, NPC
   identities and locations, coordinates, item icons, NPC portraits and other
   game artwork are treated as Pearl Abyss-origin content. A browser page or
   mirror used to retrieve or verify them does not become the owner of those
   individual game facts or assets.
4. The project owner confirms that no BDO Codex- or BDOLytics-authored prose,
   translation, commentary, annotation, page design, HTML or other original
   site material is retained. BDO Codex and BDOLytics are credited research,
   verification and mirror references.
5. A genuine separate blocker exists only where the project retains another
   site's own creative material, or a raw, wholesale or effectively
   substantial copy of an unlicensed organized database. App-specific factual
   schemas, selected records, normalization, cross-checks and project-authored
   summaries are not blocked merely because a community reference was used.
6. Licensed material remains subject to its recorded license. Each mixed file
   is reviewed by subsection so one blocked source does not disable unrelated
   planner or map functionality.

This classification is a release-governance decision for this fan project,
not a legal opinion about every possible jurisdiction.

## Final project-owner Workerman community-use decision

On 2026-08-16 the project owner directed that the full application remain
intact and accepted the remaining practical risk for the credited
Workerman/Shrddr groups in this small, completely free, noncommercial fan
release. This is a project-owner decision with accepted residual risk, not
written permission, and must never
be described as permission from Workerman/Shrddr.

The practical basis recorded by the owner is that Workerman is publicly hosted
for community use and directs users to its public GitHub issue tracker; Black
Spirit Life is free and noncommercial, gives full attribution, and will respond
promptly to correction or removal requests. No separate written licence was
found.

The retained functionality includes the full current public map presentation,
worker nodes and gathering locations, vendors, lodging and worker-economics
tools, planner/recipes, original local Gathering/Fishing journals,
Opportunities, PA artwork, Edania data, installer and in-app updating. Private
Beta integrations listed above are deliberately excluded.
Credits, source links, correction/takedown route and the ability to replace an
individual group after a substantiated request remain mandatory.

## Source matrix

| ID | Material / exact scope | Classification | Result | Release treatment |
|---|---|---|---|---|
| PA-01 | Overall Black Desert fan project | Pearl Abyss fan content | **Satisfied** | Keep the project free, unofficial and noncommercial; retain the exact required notice in README and release notes; keep third-party material outside the code licence |
| PA-02 | Black Desert item/NPC names, descriptions, recipes, prices, IDs, coordinates, node/vendor facts, 4,486 named embedded icon entries, eight gathering-tool icons and 231 NPC portraits | Pearl Abyss-origin facts and game artwork | **Satisfied** | Retain PA attribution and fan-content notice; BDO Codex/BDOLytics remain credited references or mirrors, not separate owners of these facts/assets |
| PA-03 | 154 Opportunities item icons and the Resource Map house, material, silver and bare-hands UI textures | Pearl Abyss-origin game artwork extracted from the owner's installed client | **Satisfied** | Ship only decoded artwork plus neutral client-relative provenance, hashes and sizes; no client path, extractor payload or account data is retained |
| PRIV-01 | Private Beta Fish Companion WebView/Python code, bundled journals/loadouts, caches, private node icons and FishyStuff-derived payload | Personal data plus unapproved third-party/private Beta material | **Excluded** | The private package and integration remain private; 0.1.7 uses unrelated original native local-record code with no bundled records or FishyStuff material |
| PRIV-02 | Standalone Gathering Companion guide media, Bairog-derived calculator data, copied site logos and legacy import inbox | Unapproved third-party/private Beta material | **Excluded** | The standalone Beta package and integration remain private; 0.1.7 uses unrelated original native local-record code, while the independently reviewed Resource Map gathering checklist remains public |
| PRIV-03 | Garmoth session-import catalog, spot art and saved sessions | Captured service material plus personal activity data | **Excluded** | Session Import and its Windows helper are absent from public source and packages |
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
| API-01 | Official/community market APIs | Runtime services; no response corpus bundled | **No redistribution blocker** | Respect live service limits and keep failures non-blocking/offline-safe |
| CODE-01 | Original Black Spirit Life source code | Project-owned code | **Cleared** | Root `LICENSE` remains separate and expressly grants no rights in PA artwork, game data or other third-party material |
| CODE-02 | Original native Gathering and Fishing profile/session/loadout workspaces added for 0.1.7 | Project-owned code plus user-authored local records | **Cleared** | Ship code and empty defaults only; persist records beneath the selected personal-data folder and exclude every generated record from source and packages |
| VPK-01 | Velopack 1.2.0 | Licensed dependency | **Cleared** | Preserve the bundled licence and pinned checksums |
| OCR-01 | Black Spirit Hub v0.9.52 storage-grid recognition source and sealed Recipe Book snapshot, commit `6ccbad52d25b54d8b67065ce8a9eb1bcece87d9f` | Shared implementation with project-owner reuse authorization | **Cleared for Black Spirit Life reuse** | Preserve `SOURCE-NOTICE.txt`; do not describe the authorization as a general licence grant to third parties |
| OCR-02 | PaddleOCR PP-OCRv5 model and ONNX Runtime 1.29.0 | Licensed dependencies | **Cleared** | Preserve the PaddleOCR, model, ONNX Runtime, and complete third-party notices beside the helper payload |
| OCR-03 | 3,897 sealed Recipe Book item icons and two generated recognition atlases | Pearl Abyss-origin game artwork used by the isolated OCR helper | **Satisfied** | Retain PA attribution and the helper asset notice; private contributor screenshot fixtures remain excluded from public source and packages |

## Exact owner-approved Workerman/Shrddr groups

These groups are disclosed precisely so credits and any future correction or
takedown can be source-specific. Under the final owner decision, they are not
being used as generic blockers for unrelated functionality, and the project
does not claim written permission.

1. `packages/bdo_map_core/lib/src/model/tile_source.dart`, lines 66-80:
   the Workerman/Shrddr tile URL and production hotlink/cache configuration.
   No tile image is bundled.
2. `packages/bdo_map_core/assets/images/node_icons/**`: 64 exact Workerman
   PNG files, 1,625,566 bytes total.
3. `packages/bdo_map_core/assets/data/lodging_houses.json`: 789,050 bytes,
   SHA-256
   `096D1205BBB12FD0ED0AD0F9AE1A613C680AE0E037CDAA4AF91C7F4AD4EFA6F6`;
   complete 812-house/31-town Workerman-derived graph.
4. `packages/bdo_map_core/assets/data/worker_economics.json`: 354,383 bytes,
   SHA-256
   `64ABEDA209B82EA1CAF6FC8C5EB29DDC8F1007837FA4D13652ABE534697C29D7`;
   Workerman-derived inputs for 352 production sites and 30 towns. The
   separately licensed calculation formulas are not blocked.

The current `resource_map.json` is 7,544,577 bytes (SHA-256
`BE62E56A6B18F14C7A6439521A9CA9CA240974219DBD1E44D85CDEC136C94C15`).
It contains no raw response, HTML or copied website presentation. Its 1,052
worker-node records are PA facts in the app's own schema and are not a content
blocker. Its numeric icon/layer fields are internal map-model metadata, not
site HTML, design or prose; no runtime schema change is required for this
release.

### Source-only files that must not enter the clean public snapshot

These are not installer assets and are absent from the clean public Git tree.
They must remain excluded:

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

The last four are normalized project research/provenance records, not
wholesale site exports. They are not content blockers under this standard;
they are excluded to maintain a clean public/private research boundary.

## Authorized release treatment

The project owner authorized the sanitized 0.1.7 promotion on 2026-09-15. The
release work must:

1. preserve the reviewed Planner, Resource Map and Opportunities behavior and
   include only the original native Gathering/Fishing local-record workspaces;
2. retain all credits, notices, source links and the correction/takedown route;
3. exclude the private Beta integrations, all generated personal data and all
   six private research inputs listed above while keeping internal copies
   untouched;
4. keep the code licence separate from PA and other third-party material;
5. describe the Workerman/Shrddr position accurately as a project-owner
   community-use decision with accepted residual risk, never as separate
   written permission; and
6. publish only after the exact clean commit, installer, full package, smaller
   delta package and update manifest pass the release gates.

## Permission-request drafts

The Pearl Abyss, BDO Codex and BDOLytics drafts are retired and remain unsent
archive material; they are not required for the PA-origin facts and artwork
classified above. The Shrddr/Workerman draft remains an optional alternative
to replacing that project's custom expression and substantial data extracts.
No draft may be sent without a new explicit user instruction.

## Repository and publication gates unrelated to source classification

The private Beta ancestry contains private-machine paths and a historical
migration fixture with real-looking planner values, so it must never be added
to this repository. The separate public branch contains only the sanitized
five-release history through `v0.1.6`; publication of `v0.1.7` must remain the
single reviewed sixth commit on that history, followed by a fresh-clone scan
of every public ref and tag.

Publication remains conditional on Stable install/update/uninstall
verification, the exact clean source commit and tag, final release notes and
artifact hashes. The project owner has authorized publication to the exact
repository above when those technical and privacy gates pass.
