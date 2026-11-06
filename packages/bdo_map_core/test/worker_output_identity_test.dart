import 'dart:convert';
import 'dart:io';

import 'package:bdo_map_core/bdo_map_core.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late BdoResourceMapDataset map;
  late BdoWorkerEconomicsDataset economics;
  setUpAll(() {
    map = BdoResourceMapDataset.fromJson(
      jsonDecode(File('assets/data/resource_map.json').readAsStringSync())
          as Map<String, Object?>,
    );
    economics = BdoWorkerEconomicsDataset.fromJsonString(
      File('assets/data/worker_economics.json').readAsStringSync(),
    );
  });

  test('all modeled worker output identities agree with the map', () {
    expect(economics.productionNodesById, hasLength(352));
    for (final production in economics.productionNodesById.values) {
      final outputs = map.workerNodesById[production.nodeId]!.outputs;
      final mapIds = outputs.map((output) => output.gameItemId).toSet();
      expect(
        production.outputItemIds.difference(mapIds),
        isEmpty,
        reason: 'Unmapped expected output at node ${production.nodeId}',
      );
      expect(
        mapIds.difference(production.outputItemIds),
        isEmpty,
        reason: 'Mapped output without a model at node ${production.nodeId}',
      );
    }
  });

  test('Marak grain identities retain their recorded numerical estimates', () {
    for (final (nodeId, grainId, otherGrainId) in [
      ('1673', 7002, 7005),
      ('1674', 7005, 7002),
    ]) {
      final node = economics.productionNodesById[nodeId]!;
      expect(node.standardYields, {grainId: 18.0});
      expect(node.giantYields, {grainId: 29.75029096});
      expect(node.luckyBonusYields, {1024: .3});
      expect(node.outputItemIds, isNot(contains(otherGrainId)));
      expect(node.baseWorkload, 280);
    }
  });

  test(
    'Marak barley and corn both contribute to their correct recipe demand',
    () {
      final demands = [
        for (final (nodeId, grainId) in [('1673', 7002), ('1674', 7005)])
          BdoWorkerRecipeDemand(
            id: '$grainId',
            name: '$grainId',
            quantity: 1,
            resourceUnits: {
              map.workerNodesById[nodeId]!.outputs
                      .singleWhere((output) => output.gameItemId == grainId)
                      .resourceId:
                  1,
            },
          ),
      ];
      final allocator = BdoRecipeWorkerAllocator(
        data: map,
        economics: economics,
        demands: demands,
      );
      expect(allocator.rates['1673'], {'7002': 18 / 280});
      expect(allocator.rates['1674'], {'7005': 18 / 280});
      final plan = allocator.restore(500, {'1673', '1674'});
      expect(plan.nodesFor('7002'), contains('1673'));
      expect(plan.nodesFor('7005'), contains('1674'));
      expect(plan.coverage(demands[0]), greaterThan(0));
      expect(plan.coverage(demands[1]), greaterThan(0));
    },
  );

  test(
    'current map outputs produce income estimates without obsolete mappings',
    () {
      final result = const BdoWorkerIncomeEstimator().evaluate(
        BdoWorkerIncomeRequest(
          dataset: economics,
          marketNetRate: .65,
          onlineHoursPerDay: 8,
          candidates: [
            for (final nodeId in ['1673', '1674', '1833'])
              BdoWorkerIncomeNodeInput(
                nodeId: nodeId,
                nodeName: nodeId,
                minimumContributionPoints: 1,
                incrementalContributionPoints: 1,
                outputs: [
                  for (final output in map.workerNodesById[nodeId]!.outputs)
                    BdoWorkerIncomeMarketOutputInput(
                      gameItemId: output.gameItemId!,
                      resourceId: output.resourceId,
                      name: output.name,
                      // Synthetic prices test calculation plumbing, not sale
                      // eligibility, live quotes, or measured server yields.
                      isMarketable: true,
                      currentUnitPrice: 100,
                      listedStock: 1000,
                    ),
                ],
              ),
          ],
        ),
      );
      expect(result.excluded, isEmpty);
      expect(result.ranked.map((node) => node.nodeId).toSet(), {
        '1673',
        '1674',
        '1833',
      });
      for (final node in result.ranked) {
        expect(node.netSilverPerOnlineHour, greaterThan(0));
        expect(
          node.outputs.map((output) => output.gameItemId),
          isNot(contains(8022)),
        );
        expect(
          node.caveats,
          contains(BdoWorkerIncomeCaveat.expectedYieldEstimate),
        );
      }
    },
  );

  test('removed Starlight Powder is not modeled at any worker node', () {
    for (final node in economics.productionNodesById.values) {
      expect(node.outputItemIds, isNot(contains(8022)), reason: node.nodeId);
    }
    final quarry = economics.productionNodesById['1833']!;
    expect(quarry.standardYields, {
      8027: .2,
      8028: .2,
      8029: .2,
      8030: .2,
      820138: 7.6,
    });
    expect(quarry.giantYields, {
      8027: .21813555,
      8028: .21813555,
      8029: .21813555,
      8030: .21813555,
      820138: 12.33333302,
    });
    expect(quarry.luckyBonusYields, {1026: 4.0});
    expect(quarry.baseWorkload, 4000);
  });
}
