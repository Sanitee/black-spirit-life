import 'dart:convert';
import 'package:bdo_map_core/bdo_map_core.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import '../tool/reviewed_valtarra_node_parents.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late List<Map<String, Object?>> current;
  late BdoResourceMapDataset data;
  setUpAll(() async {
    final text = await rootBundle.loadString(BdoResourceMapLoader.bundledAsset);
    final raw = jsonDecode(text) as Map;
    current = (raw['workerNodes'] as List).cast<Map<String, Object?>>();
    data = BdoResourceMapLoader.parse(text);
    expect(
      (raw['manifest']['provenance'] as List).singleWhere(
        (p) => p['id'] == reviewedValtarraParentProvenance['id'],
      ),
      reviewedValtarraParentProvenance,
    );
  });
  List<Map<String, Object?>> historical() => [
    for (final n in current)
      if (n['id'] == '2065' || n['id'] == '2066')
        {
          ...n,
          'name': 'Valtarra - Altar of Training - Mining',
          'parentId': '1612',
          'linkIds': ['1612'],
        }
      else if (n['id'] == '1611')
        {
          ...n,
          'linkIds': [
            for (final id in n['linkIds'] as List)
              if (id != '2065' && id != '2066') id,
          ],
        }
      else if (n['id'] == '1612')
        {
          ...n,
          'linkIds': [...n['linkIds'] as List, '2065', '2066'],
        }
      else
        {...n},
  ];
  test('only exact parent/name/reciprocal links change; idempotent', () {
    final old = historical(), snapshot = jsonEncode(historical());
    expect(applyReviewedValtarraNodeParents(old), current);
    expect(jsonEncode(old), snapshot);
    expect(applyReviewedValtarraNodeParents(current), current);
  });
  for (final id in ['2065', '2066']) {
    test('$id uses Mountains without paying the Altar detour', () {
      final result = const BdoProductionNodePathCostService().calculate(
        data: data,
        request: BdoProductionNodePathRequest(
          targetNodeId: id,
          allowedRootNodeIds: {'1604'},
        ),
      );
      expect(result.hasErrors, isFalse);
      final path = result.minimumTotalPath!;
      expect(path.orderedNodeIds, contains('1611'));
      expect(path.orderedNodeIds, isNot(contains('1612')));
      final node = data.workerNodes.singleWhere((n) => n.id == id);
      expect(node.parentId, '1611');
      expect(node.name, 'Valtarra Mountains - Mining');
      expect(node.contributionPoints, 2);
      final retained = const BdoProductionNodePathCostService().calculate(
        data: data,
        request: BdoProductionNodePathRequest(
          targetNodeId: id,
          allowedRootNodeIds: {'1604'},
          currentNodeIds: path.orderedNodeIds.where((n) => n != id).toSet(),
        ),
      );
      expect(retained.minimumIncrementalPath!.incrementalContributionPoints, 2);
      expect(retained.minimumIncrementalPath!.connectNodeIds, [id]);
    });
  }
  for (final mutation in [
    'missing',
    'duplicate',
    'name',
    'outputs',
    'mixed',
    'reciprocal',
  ]) {
    test('fails closed on $mutation', () {
      final rows = historical(),
          i = historical().indexWhere((n) => n['id'] == '2065');
      switch (mutation) {
        case 'missing':
          rows.removeAt(i);
        case 'duplicate':
          rows.add({...rows[i]});
        case 'name':
          rows[i]['name'] = 'Unreviewed';
        case 'outputs':
          rows[i]['outputs'] = <Map<String, Object?>>[];
        case 'mixed':
          rows[i] = {...current.singleWhere((n) => n['id'] == '2065')};
        case 'reciprocal':
          rows.singleWhere((n) => n['id'] == '1612')['linkIds'] = [
            '1611',
            '1616',
          ];
      }
      expect(
        () => applyReviewedValtarraNodeParents(rows),
        throwsFormatException,
      );
    });
  }
}
