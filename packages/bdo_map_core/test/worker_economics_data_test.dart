import 'dart:convert';
import 'dart:io';

import 'package:bdo_map_core/bdo_map_core.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('bundled worker economics is pinned and fails closed for new sites', () {
    final file = File('assets/data/worker_economics.json');
    final bytes = file.readAsBytesSync();
    final dataset = BdoWorkerEconomicsDataset.fromJsonString(
      String.fromCharCodes(bytes),
    );
    final map = BdoResourceMapDataset.fromJson(
      jsonDecode(File('assets/data/resource_map.json').readAsStringSync())
          as Map<String, Object?>,
    );

    expect(bytes, hasLength(354383));
    expect(
      sha256.convert(bytes).toString(),
      '64abeda209b82ea1caf6fc8c5eb29ddc8f1007837fa4d13652abe534697c29d7',
    );
    expect(dataset.manifest.sourcePackageVersion, '0.8.1');
    expect(dataset.manifest.sourceLicenseExpression, 'Unlicense');
    expect(dataset.manifest.permittedUse, contains('project-owner approved'));
    expect(dataset.manifest.permittedUse, contains('no separate Workerman'));
    expect(dataset.townsByNodeId, hasLength(30));
    expect(dataset.productionNodesById, hasLength(352));

    final productionResourceIds = map.workerNodes
        .where((node) => node.isProductionNode && node.isResourceNode)
        .map((node) => node.id)
        .toSet();
    final economicsNodeIds = dataset.productionNodesById.keys.toSet();
    expect(economicsNodeIds.difference(productionResourceIds), isEmpty);
    expect(
      productionResourceIds.difference(economicsNodeIds),
      <String>{for (var id = 2115; id <= 2128; id += 1) id.toString()},
      reason:
          'Inner Edania map sites remain visible, but income estimates must '
          'stay unavailable until exact workload, yield, and town-distance '
          'records are independently verified.',
    );
    expect(dataset.verifiedFreeNetworkRootNodeIds(map), hasLength(28));
    final verifiedFreeRoots = dataset.verifiedFreeNetworkRootNodeIds(map);
    expect(
      verifiedFreeRoots,
      isNot(contains('1343')),
      reason: 'Ancado is a verified worker town, but its map node costs CP.',
    );
    expect(
      verifiedFreeRoots,
      isNot(contains('1604')),
      reason:
          'Old Wisdom Tree is a verified worker town, but its map node costs '
          'CP.',
    );

    final potato = dataset.productionNodesById['131']!;
    expect(potato.baseWorkload, 200);
    expect(potato.standardYields[7003], 16.5);
    expect(potato.townDistances['1'], 180);
    expect(potato.townDistances.values, everyElement(lessThan(10000000)));

    final dokkebiForestCrystal = dataset.productionNodesById['1807']!;
    final dokkebiHarmony = dataset.productionNodesById['1808']!;
    final beombawiDecimation = dataset.productionNodesById['1830']!;
    expect(dokkebiForestCrystal.baseWorkload, 5100);
    expect(dokkebiForestCrystal.standardYields[820036], closeTo(.0126, 1e-9));
    expect(dokkebiForestCrystal.standardYields[65267], closeTo(.0126, 1e-9));
    expect(dokkebiHarmony.baseWorkload, 5100);
    expect(dokkebiHarmony.standardYields[820035], closeTo(.0113, 1e-9));
    expect(beombawiDecimation.baseWorkload, 5100);
    expect(beombawiDecimation.standardYields[820039], closeTo(.0108, 1e-9));
    for (final rareYield in <double>[
      dokkebiForestCrystal.standardYields[820036]!,
      dokkebiHarmony.standardYields[820035]!,
      beombawiDecimation.standardYields[820039]!,
    ]) {
      expect(rareYield, allOf(greaterThan(0), lessThan(.013)));
    }
  });

  test('parser rejects a production site that references an unknown town', () {
    expect(
      () => BdoWorkerEconomicsDataset.fromJson(<String, Object?>{
        'schemaVersion': 1,
        'manifest': _manifestJson(),
        'towns': <String, Object?>{
          'town': <String, Object?>{
            'nodeId': 'town',
            'regionId': 1,
            'baseWorkerSlots': 1,
            'profiles': <Object?>[_profileJson()],
          },
        },
        'productionNodes': <String, Object?>{
          'node': <String, Object?>{
            'nodeId': 'node',
            'baseWorkload': 100,
            'workerTypes': <int>[0],
            'standardYields': <String, double>{'1': 1},
            'giantYields': <String, double>{'1': 1},
            'luckyBonusYields': <String, double>{},
            'townDistances': <String, double>{'missing-town': 1},
          },
        },
      }),
      throwsFormatException,
    );
  });

  test(
    'eligible worker towns require a distance and compatible worker type',
    () {
      BdoWorkerTownEconomics town(String id, int workerType) {
        return BdoWorkerTownEconomics(
          nodeId: id,
          regionId: 1,
          baseWorkerSlots: 1,
          profiles: <BdoWorkerProfileEstimate>[
            BdoWorkerProfileEstimate(
              id: '$id-worker',
              label: 'Worker',
              workerType: workerType,
              characterKey: workerType + 1,
              isGiant: false,
              workSpeed: 100,
              movementSpeed: 10,
              luck: 20,
            ),
          ],
        );
      }

      final dataset = BdoWorkerEconomicsDataset(
        schemaVersion: 1,
        manifest: BdoWorkerEconomicsManifest.fromJson(_manifestJson()),
        townsByNodeId: <String, BdoWorkerTownEconomics>{
          'eligible': town('eligible', 0),
          'no-distance': town('no-distance', 0),
          'wrong-type': town('wrong-type', 1),
        },
        productionNodesById: <String, BdoWorkerProductionEconomics>{
          'production': BdoWorkerProductionEconomics(
            nodeId: 'production',
            baseWorkload: 100,
            workerTypes: const <int>{0},
            standardYields: const <int, double>{1: 1},
            giantYields: const <int, double>{1: 1},
            luckyBonusYields: const <int, double>{},
            townDistances: const <String, double>{
              'eligible': 100,
              'wrong-type': 100,
            },
          ),
        },
      );

      expect(
        dataset.eligibleWorkerTownNodeIds(
          productionNodeId: 'production',
          connectedNodeIds: const <String>{
            'eligible',
            'no-distance',
            'wrong-type',
            'not-a-town',
          },
        ),
        const <String>{'eligible'},
      );
      expect(
        dataset.eligibleWorkerTownNodeIds(
          productionNodeId: 'missing',
          connectedNodeIds: const <String>{'eligible'},
        ),
        isEmpty,
      );
    },
  );
}

Map<String, Object?> _manifestJson() => <String, Object?>{
  'datasetVersion': 'test',
  'generatedAt': '2026-07-29T00:00:00.000Z',
  'sourceRepository': 'https://example.invalid/source',
  'sourceCommit': 'test',
  'sourcePackageVersion': 'test',
  'sourceLicenseExpression': 'test',
  'upstreamWorkermanCommit': 'test',
  'permittedUse': 'test',
  'sourceSha256': <String, String>{'test': 'test'},
  'assumptions': <String>['test'],
};

Map<String, Object?> _profileJson() => <String, Object?>{
  'id': 'worker',
  'label': 'Worker',
  'workerType': 0,
  'characterKey': 1,
  'isGiant': false,
  'workSpeed': 100,
  'movementSpeed': 10,
  'luck': 20,
};
