# bdo_map_core

The native Flutter Resource Map package for Black Spirit Life. It provides search, gathering points, worker routes, housing, screenshot import and tile caching. It uses no embedded browser.

See the [map guide](../../docs/resource-map/README.md) for features and limits. This is a local package, not a pub.dev release.

## Development

```powershell
flutter pub get
flutter analyze --no-pub
flutter test --no-pub
```

Load the bundled data and provide a writable cache directory outside the source tree:

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

## Tiles and performance

The default is `BdoTileSource.workermanCommunity`. Its cache namespace, `workerman-community-120138d`, identifies the reviewed revision. The live URL can change; the name is not a content hash. Change the namespace when adopting another revision.

Tile loading allows six requests, 48 MiB of decoded images and 64 MiB on disk. Turning downloads off cancels requests and rejects late results. Clearing the cache leaves downloads paused. Source and HTTP clients can be replaced for testing.

Dense markers reuse screen snapshots while panning, then refresh their layout when the camera settles. Routing runs in a background isolate; outdated results are ignored. Exact and approximate routing limits are described in the map guide.

## Bundled data

Historical snapshot description, `2026.08.28-beta-v4`; not a claim that these counts cover later changes.

Dataset `2026.08.28-beta-v4` contains 1,052 numeric current nodes: 610 map
records, 76 non-resource town/service records, and 366 resource-producing
production records. The source provides 425 unique factual production links.
Twelve more relationships were matched from reviewed named node-detail
records, so 437 production-layer rows are connected and five keep
`parentId: null`; the generator never infers topology from proximity. The
dataset contains 357 resources and 39 field sources. Citron resolves to both
its worker node and a radius-free Maslan's Yulas Citron Orchard focus;
individual tree coordinates are not fabricated.
Milk resolves to a separate Dairy Cow source and six named farm-center
anchors, so milking is not confused with Cow / Ox meat, blood, or hide.


That snapshot contained 13,315 exact dots: 12,582 historical SomethingLovely points, 501 Stone Cobra/Rock Scorpion points, 34 Coral Stoneback Crab points and 198 coastal-object points. The 22 named-area focuses were navigation aids, not spawn circles or routes. Regional Truffle images were not attached to unmatched exact dots.

SomethingLovely source commit: `289c833d34851dc84f3a647a2d9cf604eda9c93a`; `src/data.json` SHA-256: `030d87ad1b752ad07df521aa9faef5b03fd2164a8e13726ebc31b3b0313d4c49`. Keep `assets/licenses/SOMETHINGLOVELY-MIT.txt` and the historical-through-2021 label.

The reviewed snapshot was 7,967,874 bytes, SHA-256 `BCA30627453873569DF749F1ED3D137BE6C3B8C7AEBE29B44A554AF4E94BC78B`. These are historical checksums, not validation of a later build.

## Credits and licence

Pearl Abyss owns the game content. BDO Codex is a research reference. Raw research responses and website presentation are not shipped.

Workerman/Shrddr material is retained with credit under the project owner's recorded decision. No separate written licence is claimed. Corrections and removal requests go through the public Issues tab.

The root and package licences cover original code only; they do not relicense third-party content. See [source rules](../../docs/resource-map/release-and-packaging.md) and [notices](../../THIRD_PARTY_NOTICES.md).
