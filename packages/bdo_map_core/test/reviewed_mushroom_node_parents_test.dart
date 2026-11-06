import 'dart:convert';
import 'package:bdo_map_core/bdo_map_core.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import '../tool/reviewed_mushroom_node_parents.dart';

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
        (p) => p['id'] == reviewedMushroomParentProvenance['id'],
      ),
      reviewedMushroomParentProvenance,
    );
  });
  List<Map<String, Object?>> historical() => [
    for (final n in current)
      if (n['id'] == '1640')
        {
          ...n,
          'name': 'Looney Cabin - Grow Mushroom',
          'parentId': '1628',
          'linkIds': ['1628'],
        }
      else if (n['id'] == '1641')
        {
          ...n,
          'name': 'Weenie Cabin - Grow Mushroom',
          'parentId': '1629',
          'linkIds': ['1629'],
        }
      else if (n['id'] == '1628' || n['id'] == '1629')
        {
          ...n,
          'linkIds': [
            for (final id in n['linkIds'] as List)
              if (id == '1640') '1641' else if (id == '1641') '1640' else id,
          ],
        }
      else
        {...n},
  ];
  test('exact two identities and reciprocal links, no other facts change', () {
    final old = historical(), snapshot = jsonEncode(historical());
    expect(applyReviewedMushroomNodeParents(old), current);
    expect(jsonEncode(old), snapshot, reason: 'Do not mutate the source seed.');
    expect(applyReviewedMushroomNodeParents(current), current);
  });
  for (final id in ['1640', '1641']) {
    test('current path for $id includes the correct cabin', () {
      final parent = id == '1640' ? '1629' : '1628';
      final result = const BdoProductionNodePathCostService().calculate(
        data: data,
        request: BdoProductionNodePathRequest(targetNodeId: id),
      );
      expect(result.minimumTotalPath, isNotNull);
      expect(result.minimumTotalPath!.orderedNodeIds, contains(parent));
      final node = data.workerNodes.singleWhere((n) => n.id == id);
      expect(node.parentId, parent);
      expect(
        node.name,
        startsWith(id == '1640' ? 'Weenie Cabin' : 'Looney Cabin'),
      );
    });
  }
  for (final mutation in [
    'missing',
    'duplicate',
    'name',
    'products',
    'mixed',
    'reverse link',
  ]) {
    test('fail closed on $mutation', () {
      final rows = historical();
      final i = rows.indexWhere((n) => n['id'] == '1640');
      switch (mutation) {
        case 'missing':
          rows.removeAt(i);
        case 'duplicate':
          rows.add({...rows[i]});
        case 'name':
          rows[i]['name'] = 'Different identity';
        case 'products':
          rows[i]['outputs'] = <Map<String, Object?>>[];
        case 'mixed':
          rows[i] = {...current.singleWhere((n) => n['id'] == '1640')};
        case 'reverse link':
          rows.singleWhere((n) => n['id'] == '1628')['linkIds'] = ['1627'];
      }
      expect(
        () => applyReviewedMushroomNodeParents(rows),
        throwsFormatException,
      );
    });
  }
}
