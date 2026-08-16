# Changelog

## 0.1.13 - 2026-08-12

- Advanced the private map dataset to `2026.08.12-private-v14` without changing
  the 1,008-node worker graph or 13,315 exact gathering points. Citron now has
  a reviewed radius-free Maslan's Yulas Citron Orchard focus alongside its
  worker node, with no fabricated individual tree coordinates.
- Made map-display layers behave as dependencies: hiding map nodes also hides
  connection lines, worker-output artwork, and their controls while preserving
  the user's saved choices for when nodes return.
- Passed mouse-wheel zoom through interactive city, town, and gateway labels,
  so hovering a landmark never blocks map navigation.
- Reserved compact planner source badges for dependable NPC-purchase guidance;
  Central Market and manual-gathering prose now use the planner-to-map actions
  instead of redundant question-mark popovers.
- Added bundled in-game item artwork for every resource-map material, including
  Vedelona, and locked complete icon coverage with a catalog regression test.

## 0.1.12 - 2026-08-04

- Replaced the screenshot importer's full-list region and town menus with
  compact type-ahead fields whose suggestion surfaces stay bounded to six
  readable rows. **Anywhere / sea** is now a separate checkbox rather than a
  misleading dropdown value, and an unconfirmed typed location cannot start a
  scan accidentally.
- Reduced the initial screenshot chooser from an 820-pixel-wide workbench to a
  focused 640-pixel dialog while preserving the larger alignment and review
  canvases where image space is genuinely useful.
- Added **Paste screenshot** for clipboard captures from Lightshot and other
  Windows tools. Direct PNG, DIBV5, DIB, and bitmap clipboard formats are read
  natively and pass through the same image limits, alignment, confidence
  review, and multi-part merge as file-picked screenshots.
- Added a short reduced-motion-aware reveal to the exact house marker or
  cluster when a lodging-summary row is selected. The effect never changes the
  map camera or its hit target, so a user can immediately see which house was
  chosen without losing their position.

## 0.1.11 - 2026-08-03

- Reworked setup capture as **Scan screenshots** under **Your nodes**. Worker
  scans now use optional broad regions, default to an Anywhere/Not sure mode
  that includes sea routes, and no longer require a guessed nearby landmark.
- Compacted the screenshot chooser and made multi-part capture explicit.
  Several overlapping land, sea, or town screenshots can be aligned and
  reviewed in one session; duplicate records are combined before saving.
- Added evidence reinforcement across overlapping screenshots. Repeated clear
  sightings increase confidence, only strong opposing readings become a
  conflict, and a user's manual checkbox choice remains unchanged when another
  screenshot is added.
- Reduced dense planned-network frame work without hiding content: pure pans
  repaint the map directly, route edges and node rings are batched, and dense
  marker layers reuse isolated widgets while live hit testing follows the
  camera.
- Retained landmarks, worker outputs, all-node markers, and dense town-house
  layers as screen-space snapshots during pure pan, then reconciled viewport
  entry and collision layout after the camera settles. Windows also requests
  the high-performance GPU while retaining Flutter's normal safe fallback.

## 0.1.10 - 2026-08-03

- Added screenshot-assisted setup capture for smaller worker-node regions,
  sparse sea routes, and zoomed town-house views. The import aligns known map
  records with the image, recognizes the normal invested/uninvested palettes,
  and accepts additional overlapping images in the same review.
- Added a confidence review before saving. Strong matches are selected first,
  uncertain or overlapping icons require an explicit choice, existing setup
  records are never removed, and every confirmed import is additive.
- Added connected house-path handling to imports. Confirmed houses include
  their missing prerequisite chain while current storage, lodging, stable, and
  workshop choices remain unchanged; image color never guesses a house use.
- Included required lodging in every worker-route CP total, highlighted the
  exact lodging and prerequisite houses, and added town counts plus a movable
  lodging summary.
- Added Recipe Book production-method labels, direct mapped-source actions,
  preserved book state across map visits, and reduced-motion-aware reveals and
  wheel scrolling.

## 0.1.9 - 2026-08-02

- Added the approved paired map skins: Sakura Night now selects Sakura
  Cartographer, while Illuminated Ledger selects Illuminated Atlas. The active
  planner theme drives the map automatically; there is no second map-theme
  setting.
- Retained the mounted Resource Map while switching themes so its camera,
  search, checklist, and planned worker network stay intact.
- Applied the paired chrome to the command shell, contextual surfaces, node
  panels, zoom controls, lodging setup, map symbols, canvas highlights,
  loading, and failure states. BDO map imagery and semantic route/status colors
  remain unchanged.

## 0.1.8 - 2026-08-02

- Added one shared feathered reading rail to every desktop map sidebar. It
  suppresses map labels, symbols, and connection lines beneath contextual text
  while fading back into the live map instead of drawing a hard-edged drawer.
- Restored the Craft Planner's `?` source-information action for NPC/vendor
  materials, including vendor, location, role, and NPC price details, without
  adding the action to ordinary category-only materials.

## 0.1.7 - 2026-08-02

- Changed the Craft Planner's **Add to planned network** action to open the
  Resource Map directly in the planned-network material editor, with the
  selected material ready to adjust and any higher saved node count preserved.
- Compacted the planned-network editor around the material list. CP, worker
  towns, saved-setup actions, and reset controls now live behind one small
  settings control instead of permanently consuming list space.
- Replaced the clipped filter row with an adaptive four-state strip. The active
  filter keeps its complete name while inactive filters remain accessible as
  labelled icon controls at narrow widths and large text sizes.

## 0.1.6 - 2026-08-02

- Added a source-aware planner material menu for right-click and touch
  long-press, with gathering, checklist, and worker actions. Worker actions now
  add the selected material to a persistent planned-network queue without
  leaving the Craft Planner, preserve higher existing counts, and expose the
  queue directly from the map.
- Reworked planned networks into a compact material workspace with resource
  artwork, remove/decrease/increase controls, live CP-left or CP-short feedback,
  and a reusable summary of the user's currently saved production setup.
- Added destination-based setup capture through **Copy my in-game setup**.
  Adding a staffed production destination infers its complete compatible path,
  remains manually adjustable, and saves planner comparison context without
  changing BDO.
- Removed historical-location explanatory headings and copy from source cards
  while retaining interactive exact dots, verification status, and provenance
  in the underlying data and audit documentation.
- Flattened gathering results into direct resource cards with gathering-tool
  icons and exact worker-node counts. Activating a node-count control now fits
  and pulses the matching production nodes, including repeated activation of
  the same result.

## 0.1.5 - 2026-08-01

- Advanced the private map dataset to `2026.08.01-private-v13`: 1,008 current
  nodes presented as 580 map records, 76 non-resource town/service records,
  and 352 resource-producing production records, plus 353 resources, 37 field
  sources, and 13,315 exact points. The 1,008-node worker graph is unchanged.
- Added a private Stillcoral coastal field source with 198 separate
  source-recorded BDO Codex object dots: 105 Rainbow Coral, 66 Oyster, six
  Giant Pearl Clam, and 21 Sea Fan. It remains separate from the 34 Coral
  Stoneback Crab dots and adds no route, path order, or broad circle.
- Added Marni Sniper Hunting as a searchable field source covering boars,
  bears, hawks, and rare tigers at the Beombawi Valley Wild Game Preserve. Its
  products include Pork, Pig Blood, Pig Hide, Bear Meat, Bear Blood, Bear Hide,
  Crystal of Decimation, Crystal of Bitterness, Crystal of Darkness, Forest
  Crystal, and Live Meat. The activity and animal guidance are verified against
  Pearl Abyss's official
  guide and update notes. Its
  single marker is a radius-free region anchor at the reviewed Beombawi node;
  no exact animal spawn dots, broad area, or route are fabricated.
- The dataset now has two radius-free focuses, Tshira and Beombawi, while
  retaining zero broad gathering areas and zero gathering routes.
- Folded Marni Sniper Hunting into the Meat and Blood & hides material
  categories, and refreshed the desktop shell with a dark emerald, jade, and
  muted-gold skin whose selected controls no longer use underline indicators.

## 0.1.4 - 2026-07-29

- Added a saved, CP-budgeted node-network planner with global shared-path
  optimization, exact add/keep/remove changes, colored routes, grouped resource
  counts, and configurable starting towns. Every returned plan is globally
  exact; oversized searches fail closed instead of returning an approximation.
  Each target change re-solves the complete request, so a former shared route
  is replaced when it is no longer cheapest. Calculation runs in a reusable
  background isolate and stale UI results are rejected.
- Reworked output-marker collision handling and added one-step contextual map
  history so resource, worker, and node-plan navigation restores prior state.
- Reviewed 12 previously orphaned production relationships against named node
  records, leaving only five rows explicitly unlinked rather than guessing.
- Retained all 42 fish drying yards; 41 have reviewed outputs spanning 44
  distinct dried-fish resources plus two reviewed byproducts, while Angie
  Island yard 2 remains honestly output-unknown.
- Expanded the pinned historical exact-point layer with Wolf, Deer, Fox, Pig,
  Cow/Ox, and Everlasting Herb, and exposed Log on all 11 existing tree
  sources without adding a separate coordinate payload. The v11 dataset now
  contains 342 resources, 35 field sources, and 13,117 exact points.
- Added Vedelona plant/acquisition guidance, cross-mode item-art resolution,
  and clean category fallbacks where no reviewed artwork is bundled.

## 0.1.3 - 2026-07-29

- Replaced the historical worker graph and separate client-prefixed Edania
  additions with a complete private snapshot of 1,008 numeric current nodes:
  580 exploration-layer rows and 428 production-layer rows. Preserved 411
  factual production-parent relationships and left all 17 upstream-unlinked
  production rows unlinked instead of guessing topology.
- Safely classified 352 resource-producing rows and indexed every current node
  name and parsed output item across 325 resources.
- Added 28 source entities so product searches such as `Thuja Sap` resolve to
  their tree, animal, plant, or other gatherable source, alongside acquisition
  methods, related products, and worker alternatives.
- Reworked the desktop map into a compact collapsible sheet and persistent
  command rail with grouped source browsing, favourites, animated detail
  transitions, current-node/city/hub layer controls, and progressive worker
  output artwork.
- Expanded exact points to 10,341: 9,806 historical MIT-licensed
  SomethingLovely coordinates, 501 private BDO Codex Stone Cobra/Rock Scorpion
  coordinates, and 34 private BDO Codex Rusalka coordinates. The historical
  expansion adds 2,854 genuine tree positions selected deterministically with
  at most 300 per newly added tree family.
- Replaced the broad Tshira approximation with one radius-free focus over
  exact points; the dataset contains no broad gathering areas and no routes.
- Kept the distribution gate closed: redistribution rights for the full
  current BDO Codex node seed and its derived node layer are unconfirmed, so
  the v10 candidate is not shareable.

## 0.1.2 - 2026-07-28

- Expanded the deterministic dataset to 267 resources and 6,986 exact
  locations: 6,952 historical MIT points plus a quarantined, private 34-point
  Rusalka's Coral candidate layer.
- Replaced overlapping floating controls with a fixed, material-first desktop
  sidebar and a secondary worker-network explorer that stays clear until the
  user chooses an activity.
- Kept individual location dots visible at every zoom, removed visible
  numbered cluster circles, and preserved sibling dots during point selection.
- Added contextual Gather/Worker source filtering, production item artwork,
  and active-plan shortage rows ordered by the saved market-stock snapshot.
- Kept the distribution gate closed for the basemap and private coordinate
  seeds.

## 0.1.1 - 2026-07-28

- Removed the broad Tshira and Edania gathering/Hunting circles because their
  centers were not verified spawn geometry.
- The v6 release retained all 1,699 then-licensed historical gathering points
  and the complete worker-node and resource layers.
- Reworked worker nodes around six clear activities with distinct icons,
  activity filters, activity-first labels, quieter overview clustering, and
  focused selection states.
- Replaced the stacked map controls with a compact search and mode surface that
  keeps gathering guidance and worker browsing separate.
- Stopped treating the Edania Golden Leaf Snake name as an alias for generic
  Snake Meat, so that query no longer projects unrelated historical snake
  points onto Edania.

## 0.1.0 - 2026-07-28

- Added the reusable native Flutter map renderer, camera, tile provider
  abstraction, search index, overlays, hit testing, and responsive interface.
- Added bounded tile loading with a six-request concurrency cap, a 48 MiB
  decoded-image cache, and a 64 MiB revisioned disk cache.
- Added cache-only and offline-missing states, request cancellation,
  late-response rejection, cache-size reporting, and in-app cache clearing.
- Added the reproducible `2026.07.28-open-seed-v2` dataset generator and pinned
  SomethingLovely MIT attribution.
- Added 764 historical graph nodes, 232 displayed craft-resource nodes, 223
  resources, and one broad community-reported Tshira gathering area.
- Added integration support for the craft planner and the standalone map lab.
- Recorded that the current Workerman / Shrddr basemap remains private-
  development-only pending written distribution permission.
