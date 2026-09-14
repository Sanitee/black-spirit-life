import 'package:bdo_map_core/bdo_map_core.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late BdoResourceMapDataset dataset;
  setUpAll(() async => dataset = await BdoResourceMapLoader.loadBundled());

  test(
    'beehives use the reviewed Balenos Forest area, not invented spawn dots',
    () {
      final resource = dataset.resourcesById['item:7701']!;
      expect(resource.name, 'Wild Beehive');
      final spots = dataset.gatheringSpots.where(
        (spot) => spot.resourceIds.contains(resource.id),
      );
      expect(spots, hasLength(1));
      final spot = spots.single;
      expect(spot.location, dataset.workerNodesById['44']!.location);
      expect(spot.nearestNode, 'Balenos Forest');
      expect(spot.summary, contains('area marker, not an exact hive location'));
      expect(spot.radiusWorld, isNull);
      expect(spot.targets.single.tool, 'Hunting Matchlock');
      expect(dataset.gatheringPointsForResource(resource.id), isEmpty);
      expect(
        dataset.workerNodes.where(
          (node) =>
              node.outputs.any((output) => output.resourceId == resource.id),
        ),
        isEmpty,
      );
    },
  );

  test(
    'hunting instructions explain the optional Grinding step without a knife',
    () {
      final source = dataset.fieldSourcesForResource('item:7701').single;
      expect(
        source.summary,
        contains('Shoot beehives from trees in Balenos Forest'),
      );
      expect(source.note, contains('Grind 3 Wild Beehives into Cooking Honey'));
      expect(source.products.single.tool, 'Hunting Matchlock');
      expect(
        source.products.single.instruction,
        contains('No butcher knife needed'),
      );
      final provenance = dataset.manifest.provenance.singleWhere(
        (entry) => entry.id == 'bdo-codex-wild-beehive-facts-2026-09-09',
      );
      expect(
        provenance.url.toString(),
        'https://bdocodex.com/us/quest/9042/5/',
      );
    },
  );

  test(
    'Cooking Honey still has its two original worker nodes and no fake direct hunt',
    () {
      final nodes = dataset.workerNodes
          .where(
            (node) =>
                node.outputs.any((output) => output.resourceId == 'item:7702'),
          )
          .toList();
      expect(nodes.map((node) => node.id).toSet(), {'432', '1779'});
      expect(dataset.fieldSourcesForResource('item:7702'), isEmpty);
      expect(
        dataset.gatheringSpots.where(
          (spot) => spot.resourceIds.contains('item:7702'),
        ),
        isEmpty,
      );
    },
  );
}
