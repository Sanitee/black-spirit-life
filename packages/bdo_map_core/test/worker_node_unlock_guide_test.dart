import 'package:bdo_map_core/bdo_map_core.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late BdoResourceMapDataset dataset;

  setUpAll(() async {
    dataset = await BdoResourceMapLoader.loadBundled();
  });

  test(
    'covers verified excavation parents without guessing Inner Edania managers',
    () {
      final excavationNodes = dataset.workerNodes
          .where(
            (node) =>
                node.isProductionNode &&
                node.nodeType == 'Excavation' &&
                node.parentId != null,
          )
          .toList(growable: false);
      final excavationParentIds = excavationNodes
          .map((node) => node.parentId!)
          .toSet();
      final guideParentIds = bdoExcavationUnlockGuides
          .map((guide) => guide.parentNodeId)
          .toSet();

      const pendingInnerEdaniaParents = <String>{
        '2087',
        '2089',
        '2090',
        '2091',
        '2097',
      };
      expect(excavationNodes, hasLength(45));
      expect(excavationParentIds, hasLength(41));
      expect(guideParentIds.difference(excavationParentIds), isEmpty);
      expect(
        excavationParentIds.difference(guideParentIds),
        pendingInnerEdaniaParents,
      );
      expect(guideParentIds, hasLength(bdoExcavationUnlockGuides.length));

      for (final node in excavationNodes) {
        final guide = bdoExcavationUnlockGuideFor(node);
        if (pendingInnerEdaniaParents.contains(node.parentId)) {
          expect(guide, isNull, reason: '${node.id}: ${node.name}');
          continue;
        }
        expect(guide, isNotNull, reason: '${node.id}: ${node.name}');
        expect(
          guide!.parentNodeId,
          node.parentId,
          reason: '${node.id}: ${node.name}',
        );
        expect(guide.managerName, isNotEmpty);
        expect(guide.managerGameNpcId, greaterThan(0));
      }
    },
  );

  test('only exact independently verified locations enable map markers', () {
    final exactGuides = bdoExcavationUnlockGuides
        .where((guide) => guide.canMarkManagerOnMap)
        .toList(growable: false);
    final managerOnlyGuides = bdoExcavationUnlockGuides
        .where((guide) => !guide.canMarkManagerOnMap)
        .toList(growable: false);

    expect(exactGuides, hasLength(18));
    expect(managerOnlyGuides, hasLength(18));

    final glish = bdoExcavationUnlockGuides.singleWhere(
      (guide) => guide.parentNodeId == '345',
    );
    expect(glish.managerName, 'Karu');
    expect(glish.managerGameNpcId, 41086);
    expect(glish.managerLocation, const BdoWorldPoint(37478.7, -107868));

    final morningLight = bdoExcavationUnlockGuides.singleWhere(
      (guide) => guide.parentNodeId == '1788',
    );
    expect(morningLight.managerName, 'Tombkebi');
    expect(morningLight.managerLocation, isNull);
    expect(morningLight.canMarkManagerOnMap, isFalse);
  });

  test('uses current manager identities for the Pilgrim excavation nodes', () {
    final managersByParentId = <String, String>{
      for (final guide in bdoExcavationUnlockGuides)
        guide.parentNodeId: guide.managerName,
    };

    expect(managersByParentId['1332'], 'Siriya Min');
    expect(managersByParentId['1333'], 'Semica');
    expect(managersByParentId['1334'], 'Samaya');
    expect(managersByParentId['1335'], 'Saimar');
    expect(managersByParentId['1336'], 'Tarik');
  });

  test('keeps unlock wording conditional and does not invent Energy costs', () {
    final guide = bdoExcavationUnlockGuides.first;

    expect(
      guide.unlockInstructions,
      startsWith('If this excavation is hidden'),
    );
    expect(guide.unlockInstructions, contains(guide.managerName));
    expect(guide.unlockInstructions, contains('Energy cost can vary'));
    expect(guide.unlockInstructions, isNot(contains('35 Energy')));
  });

  test('does not attach excavation guidance to other worker-node types', () {
    const ordinaryNode = BdoWorkerNode(
      id: 'test-mining',
      name: 'Test Mine - Mining',
      nodeType: 'Mining',
      region: 'Test',
      location: BdoWorldPoint(0, 0),
      contributionPoints: 1,
      linkIds: <String>[],
      outputs: <BdoNodeOutput>[],
      isResourceNode: true,
      isProductionNode: true,
      parentId: '345',
    );

    expect(bdoExcavationUnlockGuideFor(ordinaryNode), isNull);
  });
}
