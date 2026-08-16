# bdo_map_core

`bdo_map_core` is the reusable native Flutter resource-map package used by
Black Spirit Life. It contains no WebView, HTML, CSS, JavaScript, or embedded
browser runtime.

> The default Workerman / Shrddr basemap and related map inputs are publicly
> credited and retained under the project-owner community-use decision. No
> separate written licence is claimed; corrections and substantiated removal
> requests are handled through the public project issue route.

## Features

- Black Desert X/Z world-coordinate models and signed raster-tile transforms.
- Source-first search that still resolves item and product names. A query such
  as `Thuja Sap` opens the Thuja Tree source, its gathering method, its other
  products, and relevant worker alternatives.
- Grouped source browsing, favourites, and a compact animated map sheet that
  collapses to a persistent command rail.
- Optional current-node, city/town, gateway-hub, and progressive worker-output
  artwork layers.
- Compact **Your nodes > Scan screenshots** capture for overlapping land, sea,
  and town-house views. **Anywhere / sea** is an explicit checkbox, regions and
  towns use bounded type-ahead suggestions, and images can be chosen from disk
  or pasted directly from the Windows clipboard. Repeated evidence is
  deduplicated and reinforced, and manual review remains authoritative.
- A saved CP-budgeted worker-network planner that optimizes all requested
  outputs together, re-solves the complete network after changes, and marks
  retained, new, and removable connections separately. Tractable requests are
  globally exact. Large one-node-per-material portfolios receive a complete,
  deterministic connected route with an explicit scalable-optimization status;
  repeated-node requests remain fail-closed beyond exact enumeration limits. A
  long-lived background isolate keeps calculation off the map UI and generation
  checks reject stale results.
- A collapsible Cooking and Alchemy shortage picker that can optimize any
  checked combination in one shared-route request.
- An optional worker-income model using pinned workload,
  expected yield, travel distance, representative worker profiles, current
  prices after tax, online hours, and manually entered town worker capacity.
  It reports online hour/day/week estimates and always paints the complete
  selected route.
- Two-snapshot completed-trade evidence for an optional shared portfolio sales
  ceiling. Listed stock remains separate competition context and is never
  called demand. Raw-sale portfolio selection is a deterministic shared-path
  signal-per-added-CP heuristic, not a global-optimum claim; worker skills,
  stamina/feeding interruptions, and unverified lodging-house CP are excluded.
- Native `CustomPainter` rendering for tiles, clusters, connections, markers,
  labels, and route geometry.
- Retained screen-space snapshots for dense landmarks, worker outputs,
  all-node markers, and town houses during pure pan. Collision/culling layout
  reconciles after the camera settles, so every mapped record remains
  available without rebuilding the dense widget layers on each pointer frame.
- Pointer-anchored wheel zoom, drag/pinch pan and zoom, double-click zoom,
  arrow-key pan, `+`/`-` zoom, and `Home`/`0` reset.
- Low-resolution ancestor fallback while detailed tiles load.
- Six-request concurrency cap, 48 MiB decoded-image LRU, and 64 MiB
  provider-namespaced disk cache.
- Cache-only mode with a distinct “Offline — area not cached” state.
- In-app cache measurement and clearing. Clearing pauses downloads, clears
  decoded and downloaded tiles, cancels owned HTTP work, and rejects late
  responses before they can refill the cache.
- Injectable tile source and HTTP client for provider replacement and tests.

## Getting started

The package is a local path dependency and is not published to pub.dev.

```powershell
flutter pub get
flutter analyze --no-pub
flutter test --no-pub
```

The bundled dataset is loaded through Flutter assets. A host must supply a
writable cache directory outside its source tree.

## Usage

```dart
import 'dart:io';

import 'package:bdo_map_core/bdo_map_core.dart';
import 'package:flutter/material.dart';

class MapWorkspace extends StatelessWidget {
  const MapWorkspace({required this.cacheDirectory, super.key});

  final Directory cacheDirectory;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<BdoResourceMapDataset>(
      future: BdoResourceMapLoader.loadBundled(),
      builder: (context, snapshot) {
        final dataset = snapshot.data;
        if (dataset == null) {
          return const Center(child: CircularProgressIndicator());
        }
        return BdoResourceMap(
          dataset: dataset,
          cacheDirectory: cacheDirectory,
        );
      },
    );
  }
}
```

`BdoResourceMap` defaults to `BdoTileSource.workermanCommunity`. That provider
uses the cache namespace `workerman-community-120138d`, tied to the upstream
revision reviewed for this release. The live URL is not immutable; the
namespace is an application cache-invalidation label, not proof that upstream
content remains pinned. A newly reviewed upstream revision requires a new
provider ID so old and new tile bytes cannot be mixed.

Provider attribution, cache limits, the project-owner community-use decision,
and the correction/removal route are recorded in the public notices.

## Bundled data

Dataset `2026.08.16-stable-v1` contains 1,052 numeric current nodes: 610 map
records, 76 non-resource town/service records, and 366 resource-producing
production records. The source provides 425 unique factual production links.
Twelve more relationships were matched from reviewed named node-detail
records, so 437 production-layer rows are connected and five keep
`parentId: null`; the generator never infers topology from proximity. The
dataset contains 356 resources and 38 field sources. Citron resolves to both
its worker node and a radius-free Maslan's Yulas Citron Orchard focus;
individual tree coordinates are not fabricated.

The 13,315 exact gathering points retain four distinct provenance groups:

- 12,582 historical, MIT-licensed SomethingLovely points, explicitly labeled
  historical through 2021;
- 501 Pearl Abyss-origin Stone Cobra and Rock Scorpion points researched
  through BDO Codex; and
- 34 Pearl Abyss-origin Coral Stoneback Crab points for Rusalka's Coral and the
  crab's other reviewed normal gathering outputs; and
- 198 Pearl Abyss-origin Stillcoral coastal-object points researched through
  BDO Codex: 105 Rainbow Coral,
  66 Oyster, six Giant Pearl Clam, and 21 Sea Fan records.

Stillcoral objects remain a separate field source from Coral Stoneback Crabs.
Every retained object is an exact dot; the dataset creates no line or path
order and does not claim a route. Trade-only Oyster Shell with Pearls,
Glittering Coral, and Giant Pearl Clam Shell records are omitted from the main
resource cards.

The historical total is the prior 6,952 points plus 2,776 exact Wolf, Deer,
Fox, Pig, Cow/Ox, and Everlasting Herb positions and 2,854 genuine Ash, Birch,
Cedar, Fir, Maple, Pine, Acacia, Elder, White Cedar, and Thornwood coordinates.
Large tree families are selected deterministically from their real source
coordinates with a maximum of 300 points per family. Log reuses all 3,445
existing tree coordinates rather than adding another point layer. Shared
animal coordinates are reused for supported meat, blood, skin, and hide
resources.

The dataset has two radius-free focus records, zero broad gathering areas, and
zero routes. Tshira groups reviewed exact Snake and Scorpion points. The
Beombawi Valley focus identifies the Wild Game Preserve described by Pearl
Abyss's
[official Marni sniper-hunting guide](https://www.naeu.playblackdesert.com/en-US/Wiki?wikiNo=74)
and uses the existing reviewed node coordinate only as a navigational region
anchor. Because its animals roam, the dataset does not fabricate exact Marni
animal spawn dots or a coverage radius. The source covers boars, bears, hawks,
and rare tigers. Its searchable outputs include Pork, Pig Blood, Pig Hide, Bear
Meat, Bear Blood, Bear Hide, Crystal of Decimation, Crystal of Bitterness,
Crystal of Darkness, Forest Crystal, and Live Meat, as documented in Pearl
Abyss's
[Land of the Morning Light update](https://www.naeu.playblackdesert.com/en-US/News/Detail?groupContentNo=5387).
Exact gathering records remain individual small dots at every zoom; spatial
buckets enlarge only invisible low-zoom hit targets.

Worker production nodes are presented by activity—Mining, Farming, Lumbering,
Gathering, Fishing, or Excavation—with filterable icon markers and
primary-output-first labels. Search covers every current node name and all
parsed output item names; the optional full-node layer can therefore expose
non-resource orientation nodes without misclassifying them as worker
production.

The historical gathering seed is transformed from SomethingLovely commit
`289c833d34851dc84f3a647a2d9cf604eda9c93a`, whose input `src/data.json`
must match SHA-256
`030d87ad1b752ad07df521aa9faef5b03fd2164a8e13726ebc31b3b0313d4c49`.
The data is historical through 2021. Its MIT notice is bundled at
`assets/licenses/SOMETHINGLOVELY-MIT.txt`.

The public runtime dataset is Black Spirit Life's normalized,
application-specific selection of Pearl Abyss-origin map facts. BDO Codex was a
credited research and retrieval reference; it is not described as the owner of
the Black Desert map, nodes, icons, NPCs, recipes, or coordinates. Raw private
research inputs and website structures are not published.

The reviewed generated `resource_map.json` is 7,801,681 bytes with SHA-256
`50CFE1C7A6FAD8AA731578A67C305C9C703A619AF7EDCE5C5142EA9E826AC462`.
It retains the full 1,052-node map, the 501 Stone Cobra/Rock Scorpion points,
the 34 Coral Stoneback Crab points, the 198 Stillcoral points, vendor records,
and Edania relationships in Black Spirit Life's own schema and presentation.
See `../../docs/public-release-source-matrix.md` and
`../../docs/resource-map/release-and-packaging.md` for the public source and
release boundary.

See the repository documentation:

- `../../docs/resource-map/README.md`
- `../../docs/resource-map/release-and-packaging.md`
- `../../docs/resource-map/lodging-house-data-provenance.md`
- `../../docs/resource-map/worker-income-data-provenance.md`

## License status

The repository root `LICENSE` controls the original Black Spirit Life source
code. The package-level `LICENSE` does not relicense Pearl Abyss game content,
Workerman/Shrddr material, or other third-party material. See the root notices
for the recorded fan-content and community-use bases.
