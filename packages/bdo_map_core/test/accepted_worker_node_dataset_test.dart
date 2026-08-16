import 'package:bdo_map_core/bdo_map_core.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late BdoResourceMapDataset dataset;
  late List<int> bundledBytes;

  setUpAll(() async {
    final byteData = await rootBundle.load(BdoResourceMapLoader.bundledAsset);
    bundledBytes = byteData.buffer.asUint8List(
      byteData.offsetInBytes,
      byteData.lengthInBytes,
    );
    dataset = await BdoResourceMapLoader.loadBundled();
  });

  group('accepted Stable worker-node dataset', () {
    test('pins the reviewed v17 payload and its public source boundary', () {
      expect(bundledBytes, hasLength(7801681));
      expect(
        sha256.convert(bundledBytes).toString(),
        '50cfe1c7a6fad8aa731578a67c305c9c703a619af7edce5c5142ea9e826ac462',
        reason:
            'A data refresh must update the source review, accepted counts, '
            'and this checksum deliberately.',
      );
      expect(dataset.manifest.schemaVersion, 1);
      expect(dataset.manifest.datasetVersion, '2026.08.16-stable-v1');

      final currentSnapshot = dataset.manifest.provenance.singleWhere(
        (record) =>
            record.id ==
            'bdo-codex-current-worldmap-nodes-2026-08-15-reference',
      );
      expect(
        currentSnapshot.url.toString(),
        'https://bdocodex.com/us/worldmap/',
      );
      expect(
        currentSnapshot.permittedUse,
        allOf(
          contains('1,052 current records'),
          contains('610 raw exploration-layer records'),
          contains('442 raw production-layer records'),
          contains('425 unique parent-linked children'),
          contains('free noncommercial fan-content basis'),
        ),
      );

      final vendorSnapshot = dataset.manifest.provenance.singleWhere(
        (record) =>
            record.id == 'bdo-codex-vendor-npc-locations-2026-08-15-reference',
      );
      expect(
        vendorSnapshot.permittedUse,
        allOf(
          contains('51 reviewed planner vendor items'),
          contains('266 NPC location pins'),
          contains('1241 item-to-location listings'),
          contains('free noncommercial fan-content basis'),
        ),
      );
      expect(dataset.vendorNpcs, hasLength(266));
      expect(dataset.vendorListings, hasLength(1241));
    });

    test('retains the complete graph, including every fishing record', () {
      final productionNodes = dataset.workerNodes
          .where((node) => node.isProductionNode)
          .toList(growable: false);
      final explorationNodes = dataset.workerNodes
          .where((node) => !node.isProductionNode)
          .toList(growable: false);
      final resourceNodes = dataset.workerNodes
          .where((node) => node.isResourceNode)
          .toList(growable: false);
      final fishingRecords = dataset.workerNodes
          .where(
            (node) =>
                node.nodeType == 'Fish Drying Yard' ||
                node.nodeType == 'Fishing',
          )
          .toList(growable: false);
      final outputResourceIds = dataset.workerNodes
          .expand((node) => node.outputs)
          .map((output) => output.resourceId)
          .toSet();

      expect(dataset.workerNodes, hasLength(1052));
      expect(dataset.workerNodesById, hasLength(1052));
      expect(
        dataset.workerNodes.every(
          (node) => RegExp(r'^[0-9]+$').hasMatch(node.id),
        ),
        isTrue,
        reason:
            'The accepted snapshot uses current numeric records only; older '
            'client-prefixed Edania duplicates must not be appended.',
      );
      expect(
        dataset.workerNodes
            .map((node) => int.parse(node.id))
            .reduce((highest, id) => id > highest ? id : highest),
        2128,
      );
      expect(productionNodes, hasLength(442));
      expect(explorationNodes, hasLength(610));
      expect(resourceNodes, hasLength(366));
      expect(dataset.resources, hasLength(356));
      expect(outputResourceIds, hasLength(285));

      expect(
        productionNodes.where((node) => node.parentId != null),
        hasLength(437),
      );
      expect(
        productionNodes
            .where((node) => node.parentId == null)
            .map((node) => node.id)
            .toSet(),
        <String>{'1826', '1827', '1828', '1829', '2056'},
      );

      expect(fishingRecords, hasLength(42));
      expect(
        fishingRecords.where((node) => node.isResourceNode),
        hasLength(41),
      );
      final emptyFishingRecord = dataset.workerNodesById['1044']!;
      expect(emptyFishingRecord.name, 'Angie Island - Fish Drying Yard 2');
      expect(emptyFishingRecord.isProductionNode, isTrue);
      expect(emptyFishingRecord.isResourceNode, isFalse);
      expect(emptyFishingRecord.outputs, isEmpty);

      for (final node in dataset.workerNodes) {
        expect(node.sourceIconType, isNotNull, reason: node.id);
        for (final linkId in node.linkIds) {
          final linkedNode = dataset.workerNodesById[linkId];
          expect(linkedNode, isNotNull, reason: '${node.id} -> $linkId');
          expect(
            linkedNode!.linkIds,
            contains(node.id),
            reason: '$linkId must link back to ${node.id}',
          );
        }
        if (node.parentId case final parentId?) {
          expect(
            dataset.workerNodesById,
            contains(parentId),
            reason: '${node.id} -> $parentId',
          );
          expect(node.linkIds, contains(parentId), reason: node.id);
        }
        for (final output in node.outputs) {
          expect(
            dataset.resourcesById,
            contains(output.resourceId),
            reason: '${node.id} -> ${output.resourceId}',
          );
        }
        if (node.isResourceNode) {
          expect(node.isProductionNode, isTrue, reason: node.id);
          expect(node.outputs, isNotEmpty, reason: node.id);
          expect(() => node.activity, returnsNormally, reason: node.id);
        }
      }
    });

    test('includes the reviewed Inner Edania node and resource delta', () {
      expect(dataset.workerNodesById['2085']!.name, 'Epeiros Mountains');
      expect(dataset.workerNodesById['2114']!.name, 'Tiamat Sea');

      final olivine = dataset.workerNodesById['2121']!;
      final marble = dataset.workerNodesById['2122']!;
      final magnetite = dataset.workerNodesById['2126']!;
      expect(olivine.parentId, '2090');
      expect(marble.parentId, '2090');
      expect(magnetite.parentId, '2091');
      expect(
        olivine.outputs.map((output) => output.resourceId),
        contains('item:4415'),
      );
      expect(
        marble.outputs.map((output) => output.resourceId),
        contains('item:4016'),
      );
      expect(
        magnetite.outputs.map((output) => output.resourceId),
        contains('item:4017'),
      );

      final official = dataset.manifest.provenance.singleWhere(
        (record) =>
            record.id == 'pearl-abyss-inner-edania-production-nodes-2026-08-13',
      );
      expect(official.url.toString(), contains('_boardNo=19693'));
      expect(official.permittedUse, contains('Rough Marble'));
      expect(official.permittedUse, contains('Magnetite Ore'));
      expect(official.permittedUse, contains('Olivine Ore'));
    });

    test(
      'builds the Activated-list catalog from real resource nodes and labels',
      () {
        final result = BdoActiveNodeListMatcher.match(
          frames: <BdoActiveNodeOcrFrame>[
            _activeListFrame(<String>[
              "Pilgrim's Sanctum: Sincerity - Excavation",
              'Behr Riverhead - Mining',
              'Rhua Tree Stub - Gathering',
              'Bartali Farm - Chicken Meat Production',
              'Finto Farm - Potato Farming',
              'Orffs Island - Fish Drying Yard 2',
              'Northern Wheat Plantation - Barley Farming',
            ]),
          ],
          productionNodes: dataset.workerNodes,
        );

        expect(result.rejected, isEmpty);
        expect(result.matches, hasLength(7));
        expect(
          result.matches.map((match) => match.canonicalActivity).toSet(),
          containsAll(<String>{
            'Excavation',
            'Mining',
            'Gathering',
            'Chicken Meat Production',
            'Potato Farming',
            'Fish Drying Yard 2',
            'Barley Farming',
          }),
        );
        expect(
          result.matches.every(
            (match) =>
                match.disposition == BdoActiveNodeMatchDisposition.accepted,
          ),
          isTrue,
        );
      },
    );

    test('retains the locally cross-checked Edania-era numeric records', () {
      const managerIds = <String>{
        '2010',
        '2013',
        '2014',
        '2016',
        '2022',
        '2024',
        '2028',
        '2030',
        '2034',
        '2035',
        '2036',
        '2053',
      };
      const productionParents = <String, String>{
        '2037': '2030',
        '2038': '2028',
        '2039': '2016',
        '2040': '2014',
        '2041': '2010',
        '2042': '2013',
        '2043': '2013',
        '2044': '2030',
        '2045': '2034',
        '2046': '2035',
        '2047': '2022',
        '2048': '2024',
        '2049': '2024',
        '2050': '2035',
        '2051': '2036',
        '2054': '2053',
      };

      for (final managerId in managerIds) {
        final manager = dataset.workerNodesById[managerId];
        expect(manager, isNotNull, reason: managerId);
        expect(manager!.isProductionNode, isFalse, reason: managerId);
        expect(manager.isResourceNode, isFalse, reason: managerId);
      }
      for (final entry in productionParents.entries) {
        final node = dataset.workerNodesById[entry.key];
        expect(node, isNotNull, reason: entry.key);
        expect(node!.isProductionNode, isTrue, reason: entry.key);
        expect(node.isResourceNode, isTrue, reason: entry.key);
        expect(node.parentId, entry.value, reason: entry.key);
        expect(node.contributionPoints, 1, reason: entry.key);
        expect(node.outputs, isNotEmpty, reason: entry.key);
      }

      expect(
        dataset.workerNodesById['2037']!.outputs.map((output) => output.name),
        containsAll(<String>['Caphras Tree Timber', 'Caphras Tree Sap']),
      );
      expect(
        dataset.workerNodesById['2051']!.activity,
        BdoWorkerActivity.fishing,
      );
      expect(
        dataset.workerNodesById['2054']!.outputs.map((output) => output.name),
        containsAll(<String>['Purified Water', 'Bag of Muddy Water']),
      );

      final provenanceIds = dataset.manifest.provenance
          .map((record) => record.id)
          .toSet();
      expect(
        provenanceIds,
        containsAll(<String>{
          'na-client-edania-node-facts-2026-reference',
          'pearl-abyss-edania-production-node-facts-2025',
          'pearl-abyss-frozen-halo-node-facts-2026',
          'pearl-abyss-production-node-update-2026-06-04',
        }),
      );
    });

    test('retains Morning Light rare-crystal production nodes', () {
      final dokkebiForestCrystal = dataset.workerNodesById['1807']!;
      final dokkebiHarmony = dataset.workerNodesById['1808']!;
      final beombawiDecimation = dataset.workerNodesById['1830']!;

      expect(dokkebiForestCrystal.name, 'Dokkebi Forest - Excavation');
      expect(dokkebiForestCrystal.parentId, '1788');
      expect(
        dokkebiForestCrystal.outputs.map((output) => output.name),
        containsAll(<String>[
          'Forest Crystal',
          'Embers of Hongik',
          'Mysterious Powder',
          'Trace of Nature',
        ]),
      );
      expect(
        dokkebiHarmony.outputs.map((output) => output.name),
        contains('Crystal of Harmony'),
      );
      expect(beombawiDecimation.name, 'Beombawi Valley - Excavation');
      expect(beombawiDecimation.parentId, '1797');
      expect(
        beombawiDecimation.outputs.map((output) => output.name),
        contains('Crystal of Decimation'),
      );

      for (final node in <BdoWorkerNode>[
        dokkebiForestCrystal,
        dokkebiHarmony,
        beombawiDecimation,
      ]) {
        expect(node.isProductionNode, isTrue, reason: node.id);
        expect(node.isResourceNode, isTrue, reason: node.id);
        expect(node.contributionPoints, 1, reason: node.id);
      }
    });
  });
}

BdoActiveNodeOcrFrame _activeListFrame(List<String> rows) =>
    BdoActiveNodeOcrFrame(
      frameIndex: 0,
      timestampMilliseconds: 100,
      sharpness: .2,
      lines: <BdoActiveNodeOcrLine>[
        for (final row in rows)
          BdoActiveNodeOcrLine(
            text: row,
            frameIndex: 0,
            timestampMilliseconds: 100,
            frameSharpness: .2,
          ),
      ],
    );
