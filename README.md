# Black Spirit Life

This source tree builds the plain-name Windows application **Black Spirit
Life**. It combines the complete craft-planner workflows with a native
resource-map workspace.

> This is unofficial content which contains copyrighted materials and IP from Pearl Abyss, and is not official/endorsed content.

Black Spirit Life is a free, noncommercial fan-made BDO life-skill tool.

> The project owner has selected a completely free, non-commercial
> full-feature fan release for friends and guild members. Pearl Abyss-origin
> game content and facts are covered by the
> project's fan-content basis; BDO Codex and BDOLytics are credited research
> references. The source matrix records the project owner's community-use
> decision and accepted residual risk for the credited Workerman/Shrddr groups and excludes six
> source-only private research inputs from the public tree. Each release is
> produced from one sanitized source commit and an exact release tag, with
> artifact hashes and verification recorded alongside the GitHub release.

The accepted Flutter planner, predecessor applications, their published
runnables, and existing personal data are protected references. The public
target has a separate Stable package identity while every user-facing surface
uses only the plain application name:

| Concern | Public target |
|---|---|
| Display and installer name | `Black Spirit Life` |
| Integrated executable | `BlackSpiritLife.exe` |
| Planner state | `%APPDATA%\Black Spirit Life` |
| Integrated map cache | `%LOCALAPPDATA%\Black Spirit Life\Map Cache` |
| Update channel | `win-x64-stable` |

Black Spirit Life starts with a clean, separate personal profile. It does not
automatically copy a Beta or legacy planner profile, inventory, mastery values,
plans, custom edits, or personal-data location. Reference recipes, item data,
icons, portraits, and map data remain bundled application content rather than
personal input. Values entered after installation are written only to the
selected personal-data directory. Regular updates must preserve that directory
and must not reopen setup. These behaviors remain part of the local installer
and upgrade verification gate.

Portable planner exports remain intentionally compatible with BDO Craft
Planner. Their existing `BDO Craft Planner` document marker identifies the
portable format, not the installed application, and is unchanged.

Every app-owned surface is rendered with Flutter/Dart widgets and painters plus
native Windows channels. There is no WebView2, embedded Chromium, HTML, CSS, or
JavaScript application surface.

## Current map scope

Dataset `2026.08.16-stable-v1` contains:

- the 1,052-node worker graph from the pinned August 15 current world-map
  snapshot: 610 map records, 76 non-resource town/service records, and 366
  resource-producing production records;
- 437 production children linked to reviewed parents and five explicitly left
  unlinked because a safe factual relationship is still unavailable;
- 356 searchable resources and 38 grouped tree, animal, plant, mushroom,
  coastal, and hunting sources;
- 13,315 exact gathering points: 12,582 historical SomethingLovely positions,
  501 Stone Cobra/Rock Scorpion positions, 34 Coral Stoneback Crab positions
  for Rusalka's Coral, and 198 Stillcoral coastal
  positions covering Rainbow Coral, Oyster, Giant Pearl Clam, and Sea Fan;
- three radius-free focuses: Tshira Ruins over exact points, the Beombawi
  Valley Marni Sniper Hunting region anchor, and Maslan's Yulas Citron Orchard
  as a named Citron Tree destination; and
- zero broad gathering/Hunting areas and zero traced routes;
- 51 reviewed vendor-sold planner items with 266 curated physical NPC location
  pins and 1,241 item-to-physical-NPC listings. These are Pearl Abyss game
  facts selected and normalized for Black Spirit Life; BDO Codex is credited
  as a research reference rather than described as the owner of the facts.

The Beombawi focus is grounded in Pearl Abyss's
[official Marni sniper-hunting guide](https://www.naeu.playblackdesert.com/en-US/Wiki?wikiNo=74)
and uses the existing reviewed Beombawi Valley node coordinate only as a
navigation anchor. Animals roam within the preserve, so the Stable map deliberately
fabricates neither exact animal spawn dots nor a coverage radius. The source
covers boars, bears, hawks, and rare tigers; its searchable products are Pork,
Pig Blood, Pig Hide, Bear Meat, Bear Blood, Bear Hide, Crystal of Decimation,
Crystal of Bitterness, Crystal of Darkness, Forest Crystal, and Live Meat.
The Gather interface exposes those outcomes through **Meat** and **Blood &
hides** instead of presenting Marni Sniper Hunting as a separate destination.

The Stillcoral coastal source adds 198 separate source-recorded dots: 105
Rainbow Coral, 66 Oyster, six Giant Pearl Clam, and 21 Sea Fan. They remain
distinct from the 34 Coral Stoneback Crab dots. No path order, broad coverage
circle, or invented route is claimed for either layer.

The current `workerNodes` array contains 1,052 Pearl Abyss-origin world-map
facts selected, normalized and connected through Black Spirit Life's original
map interface, rendering, search, filtering, routing and calculations. BDO
Codex is credited as a retrieval/reference source, not as owner of the Black
Desert map or nodes. Six private research inputs, including the two complete
world-map snapshots, are excluded from the public source boundary; the
normalized runtime map remains.
Edania is included in the same numeric node graph instead of being appended as
duplicate client-prefixed records.
Twelve previously orphaned production relationships were matched to reviewed
named parents; the remaining five stay visibly unresolved rather than being
connected by proximity.

The open historical gathering layer is pinned to SomethingLovely commit
`289c833d34851dc84f3a647a2d9cf604eda9c93a`. It is historical through 2021
and is not represented as complete current spawn coverage. Wolf, Deer, Fox,
Pig, Cow/Ox, Everlasting Herb, and eleven tree families are included from that
pinned source. Log is exposed as a product of the existing tree coordinates
without fabricating a separate point layer. Additional Rusalka and Drieghan
animal positions are not added unless their underlying game facts can be
reviewed and normalized reliably.

The desktop map uses a dark emerald, jade, and muted-gold command shell with a
narrow rail and a collapsible, animated source sheet. Selected controls use
their complete surface instead of an underline. Materials are grouped into
compact sections and favorites; product
queries such as `Thuja Sap` resolve to the physical Thuja Tree source and show
all applicable products, tools, worker alternatives, and exact historical
locations. Individual dots remain visible without numbered region circles.
Zoom-aware output artwork, towns, hubs, all-node orientation, and connection
lines can be switched independently.

The integrated planner adds a source-aware right-click and long-press menu to
material rows. Users can open manual gathering locations, add the material to
the checklist, or open the worker-node planner with that material already
configured as a target. Worker planning starts with one distinct production
node, or preserves the previously selected count, ready for adjustment and
route calculation. Both top workspaces remain mounted, so the browser-style
**Craft Planner** and **Resource Map** tabs do not disappear when map panels or
transient UI open. The active tab expands to its icon and name while the
inactive tab stays a full-size icon button.

The worker-node planner accepts a CP budget, selected starting towns, and a
count for each requested output. It solves the complete request together,
including shared paths and multi-output nodes, and recalculates the whole
network whenever targets change. A saved network is comparison context only:
the result may retain, add, or remove any route when a cheaper configuration
becomes available. Cooking and Alchemy shortages can be expanded, checked
individually, and optimized together. Tractable calculations are exact; large
one-node-per-material requests, including the current 28-material Alchemy
portfolio, receive a complete connected scalable route with an explicit
non-global-optimum status. Oversized repeated-node enumeration remains
fail-closed. Every generated plan paints its complete connection lines.

**Copy my in-game setup** accepts staffed production destinations and infers
their lowest-cost complete paths from the selected worker towns and already
marked nodes. The inferred path can be corrected manually; saving records
comparison context in the planner only and changes nothing in BDO.

The same setup area can read saved in-game map screenshots. Use smaller
regional images for worker nodes (including separate sea/fish crops) and a
fully zoomed town image for houses. Align the outlined records with the icons
in the image, review every recognized investment, and add only the checked
rows. More images can be added for adjoining regions or dense towns. Imports
only add to the saved setup: an icon that is absent or unclear never removes a
node or house. Confirmed houses add their required preceding house chain, but
the image does not guess whether a house is used for lodging, storage, a stable,
or a workshop.

The application also compares raw-sale worker networks using current
prices after tax, pinned workload/yield/travel inputs, online hours, CP, and
manually entered available workers or vacant owned-lodging slots. It reports
rough online hour/day/week income. Optional completed-trade evidence needs two
comparable market snapshots and is kept separate from listed stock. Raw-sale
portfolio selection is a deterministic shared-path income-per-added-CP
heuristic, not a globally optimal claim. Worker skills, stamina/feeding
interruptions, and unverified lodging-house CP are not included.

The map engine also supports mouse/touch pan-and-zoom, keyboard navigation,
bounded caching, and cache-only viewing. Additional exact markers are added
only after a documented source review or independent in-game verification.

## Repository layout

| Path | Purpose |
|---|---|
| `lib/` | Integrated craft planner and browser-style Craft Planner / Resource Map tabs |
| `packages/bdo_map_core/` | Reusable native map models, loader, renderer, tile engine, cache, data, and tests |
| `docs/resource-map/` | Public map provenance, release boundary, cache behavior, and user guidance |

## Rights, credits, and corrections

- `THIRD_PARTY_NOTICES.md` records third-party notices, credits, and source
  links.
- `ASSET_SOURCES.md` records source URLs, review or retrieval dates,
  transformations, and the distribution status of each asset and dataset.
- `docs/public-release-source-matrix.md` records the controlling source
  classifications, credits, exclusions, and project-owner decisions.
- The repository's **Content correction or takedown** issue form is the public
  route for reporting an incorrect record or rights concern. Do not include
  private personal information or confidential evidence in a public issue.

The root `LICENSE` covers only original Black Spirit Life source code. It does
not grant rights in Pearl Abyss artwork or other Black Desert content,
Workerman/Shrddr material, map-provider content, or any site-authored
expression from credited research references.

## Clean bootstrap

Install Flutter with Windows desktop support, Visual Studio's Desktop
development with C++ workload, and the Windows SDK. From the repository root:

```powershell
flutter doctor
flutter config --enable-windows-desktop
flutter pub get
flutter run -d windows
```

The integrated app opens on **Craft Planner**. Select **Resource Map** in the
top title strip to create the map workspace lazily. Returning to either tab
retains that workspace's in-memory state.

See `docs/resource-map/README.md` for controls, cache behavior, and
troubleshooting.

## Local Windows builds

For an ordinary local development build:

```powershell
flutter build windows --release --no-pub
```

Output:
`build\windows\x64\runner\Release\BlackSpiritLife.exe`

The guarded public release-candidate builder requires the permanent GitHub
repository URL, a clean one-commit source tree, and the exact `v0.1.3` tag:

```powershell
PowerShell -File tool\build_public_stable_candidate.ps1 `
  -PublicGitHubRepository https://github.com/Sanitee/black-spirit-life `
  -ConfirmPublicCandidateOnly
```

A runnable Windows application is the complete `Release` directory, not the
EXE alone. Public releases use the themed `BlackSpiritLifeInstaller.exe` and
the matching GitHub Releases update assets. The binaries are not code-signed,
so Windows may show an unknown-publisher or SmartScreen warning.

The application requires 64-bit Windows 10 or 11 and the Microsoft Visual C++
2015–2022 x64 runtime.

## Verification

Run `flutter pub get` once before commands that use `--no-pub`.

```powershell
flutter analyze --no-pub
flutter test --no-pub --concurrency=1
flutter test --no-pub integration_test\application_smoke_test.dart -d windows
flutter drive --profile --no-pub -d windows --driver=test_driver\performance_driver.dart --target=integration_test\performance_profile_test.dart --timeout=900
flutter build windows --release --no-pub
powershell -ExecutionPolicy Bypass -File tool\verify_production_source.ps1
```

Verify the shared package independently:

```powershell
Push-Location packages\bdo_map_core
flutter pub get
flutter analyze --no-pub
flutter test --no-pub
Pop-Location
```

## Working tree versus handoff artifacts

The repository is a development workspace, not the folder to hand to an end
user. `.dart_tool`, `build`, and test-failure images are ignored; runtime
caches and captures stay in their documented external locations. These are
reproducible or diagnostic artifacts. The generated
`packages/bdo_map_core/assets/data/resource_map.json` is different: it is a
reviewed, bundled runtime asset and is intentionally versioned with its
generator.

Use a separate staging directory for any future source archive or runnable
package. Keep personal planner backups and release evidence outside the public
source tree.
