import 'package:bdo_craft_planner_flutter/features/resource_map/resource_map_workspace.dart';
import 'package:bdo_map_core/bdo_map_core.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('shares one dataset load until explicitly invalidated', () async {
    var loadCount = 0;
    final dataset = _dataset();
    final cache = ResourceMapDatasetCache(
      loader: () async {
        loadCount += 1;
        return dataset;
      },
    );

    final first = cache.load();
    final second = cache.load();

    expect(identical(first, second), isTrue);
    expect(await first, same(dataset));
    expect(await second, same(dataset));
    expect(loadCount, 1);

    cache.invalidate();
    final reloaded = cache.load();

    expect(identical(reloaded, first), isFalse);
    expect(await reloaded, same(dataset));
    expect(loadCount, 2);
  });
}

BdoResourceMapDataset _dataset() {
  return BdoResourceMapDataset(
    manifest: BdoDatasetManifest(
      schemaVersion: 1,
      datasetVersion: 'cache-test',
      generatedAt: DateTime.utc(2026),
      coordinateReference: 'test',
      provenance: const <BdoProvenanceRecord>[],
    ),
    resources: const <BdoResourceDefinition>[],
    workerNodes: const <BdoWorkerNode>[],
    gatheringSpots: const <BdoGatheringSpot>[],
    gatheringRoutes: const <BdoGatheringRoute>[],
  );
}
