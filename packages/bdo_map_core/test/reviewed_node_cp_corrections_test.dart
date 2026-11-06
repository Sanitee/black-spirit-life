import 'dart:convert';

import 'package:bdo_map_core/bdo_map_core.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../tool/reviewed_node_cp_corrections.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Map<String, Object?> raw;
  late List<Map<String, Object?>> nodes;
  late BdoResourceMapDataset data;
  setUpAll(() async {
    final text = await rootBundle.loadString(BdoResourceMapLoader.bundledAsset);
    raw = jsonDecode(text) as Map<String, Object?>;
    nodes = (raw['workerNodes']! as List).cast<Map<String, Object?>>();
    data = BdoResourceMapLoader.parse(text);
  });

  test('all 170 exact reviewed identities carry the supported cost', () {
    expect(novemberReviewedNodeCosts, hasLength(170));
    for (final entry in novemberReviewedNodeCosts.entries) {
      final node = nodes.singleWhere((n) => n['id'] == entry.key);
      expect(node['name'], entry.value.name);
      expect(node['contributionPoints'], entry.value.after);
    }
    final manifest = raw['manifest']! as Map;
    expect(
      (manifest['provenance'] as List).singleWhere(
        (p) => (p as Map)['id'] == novemberReviewedCpProvenance['id'],
      ),
      novemberReviewedCpProvenance,
    );
  });

  test('bank paths have no CP toll or invented worker income', () async {
    final economics = await BdoWorkerEconomicsLoader.loadBundled();
    for (final id in ['1189', '1190', '1191', '1192']) {
      final node = data.workerNodes.singleWhere((n) => n.id == id);
      expect(node.nodeType, 'Bank');
      expect(node.isResourceNode, isFalse);
      expect(node.parentId, '1101');
      expect(economics.productionNodesById.containsKey(id), isFalse);
      final result = const BdoProductionNodePathCostService().calculate(
        data: data,
        request: BdoProductionNodePathRequest(
          targetNodeId: id,
          allowedRootNodeIds: {'1101'},
        ),
      );
      expect(result.hasErrors, isFalse);
      expect(result.minimumTotalPath!.orderedNodeIds, ['1101', id]);
      expect(result.minimumTotalPath!.totalContributionPoints, 0);
      expect(result.minimumTotalPath!.incrementalContributionPoints, 0);
    }
    // Specialty nodes are a separate unresolved question, not inferred banks.
    for (final id in ['110', '915', '1193']) {
      expect(data.workerNodes.singleWhere((n) => n.id == id).contributionPoints, 1);
    }
  });

  test('generation corrects old costs without changing other node facts', () {
    final historical = [
      for (final node in nodes)
        if (novemberReviewedNodeCosts[node['id']] case final correction?)
          {...node, 'contributionPoints': correction.before}
        else
          {...node},
    ];
    expect(applyNovemberReviewedNodeCosts(historical), nodes);
    expect(applyNovemberReviewedNodeCosts(nodes), nodes);
    for (final entry in novemberReviewedNodeCosts.entries) {
      expect(
        historical.singleWhere(
          (n) => n['id'] == entry.key,
        )['contributionPoints'],
        entry.value.before,
      );
    }
  });

  for (final mutation in ['missing', 'duplicate', 'name', 'unknown cost']) {
    test('generation fails closed on $mutation instead of guessing', () {
      final changed = [
        for (final n in nodes) {...n},
      ];
      final id = novemberReviewedNodeCosts.keys.first;
      final index = changed.indexWhere((n) => n['id'] == id);
      switch (mutation) {
        case 'missing':
          changed.removeAt(index);
        case 'duplicate':
          changed.add({...changed[index]});
        case 'name':
          changed[index]['name'] = 'Unreviewed same-ID replacement';
        case 'unknown cost':
          changed[index]['contributionPoints'] = 999;
      }
      expect(
        () => applyNovemberReviewedNodeCosts(changed),
        throwsFormatException,
      );
    });
  }

  test(
    'Old Wisdom Tree starts a four-CP Shady Tree route with no town toll',
    () {
      const service = BdoProductionNodePathCostService();
      final full = service.calculate(
        data: data,
        request: BdoProductionNodePathRequest(
          targetNodeId: '1635',
          allowedRootNodeIds: {'1604'},
        ),
      );
      expect(full.hasErrors, isFalse);
      expect(full.minimumTotalPath!.orderedNodeIds, ['1604', '1605', '1635']);
      expect(full.minimumTotalPath!.totalContributionPoints, 4);
      expect(full.minimumTotalPath!.connectNodeIds, ['1605', '1635']);
      final retained = service.calculate(
        data: data,
        request: BdoProductionNodePathRequest(
          targetNodeId: '1635',
          allowedRootNodeIds: {'1604'},
          currentNodeIds: {'1605'},
        ),
      );
      expect(retained.minimumIncrementalPath!.totalContributionPoints, 4);
      expect(retained.minimumIncrementalPath!.incrementalContributionPoints, 3);
      expect(retained.minimumIncrementalPath!.connectNodeIds, ['1635']);
    },
  );

  test('actual production paths include the corrected costs exactly once', () {
    final byId = {for (final n in data.workerNodes) n.id: n};
    var reviewed = 0;
    for (final id in novemberReviewedNodeCosts.keys) {
      if (!byId[id]!.isProductionNode) continue;
      final result = const BdoProductionNodePathCostService().calculate(
        data: data,
        request: BdoProductionNodePathRequest(targetNodeId: id),
      );
      final path = result.minimumTotalPath;
      expect(path, isNotNull, reason: id);
      expect(path!.orderedNodeIds.toSet().length, path.orderedNodeIds.length);
      final sum = path.orderedNodeIds.fold<int>(
        0,
        (total, id) => total + byId[id]!.contributionPoints,
      );
      expect(path.totalContributionPoints, sum, reason: id);
      expect(path.orderedNodeIds, contains(id));
      expect(path.incrementalContributionPoints, sum, reason: id);
      reviewed++;
    }
    expect(reviewed, greaterThan(0));
  });
}
