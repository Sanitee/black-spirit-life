import 'dart:convert';

import 'package:bdo_map_core/bdo_map_core.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../tool/reviewed_island_link.dart';

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

  List<Map<String, Object?>> oldNodes() => [
    for (final n in nodes)
      {
        ...n,
        'linkIds': [
          for (final id in n['linkIds']! as List)
            if (!(n['id'] == '1054' && id == '1055') &&
                !(n['id'] == '1055' && id == '1054'))
              id,
        ],
      },
  ];

  test('bundled islands have the exact symmetric reviewed connection', () {
    expect(data.workerNodesById['1054']!.linkIds, contains('1055'));
    expect(data.workerNodesById['1055']!.linkIds, contains('1054'));
    expect(
      ((raw['manifest']! as Map)['provenance'] as List).singleWhere(
        (entry) => (entry as Map)['id'] == reviewedIslandLinkProvenance['id'],
      ),
      reviewedIslandLinkProvenance,
    );
  });

  test('generation only adds the two directed halves and is idempotent', () {
    final historical = oldNodes();
    final before = jsonEncode(historical);
    expect(applyReviewedIslandLink(historical), nodes);
    expect(applyReviewedIslandLink(nodes), nodes);
    expect(jsonEncode(historical), before);
  });

  test('existing Narvo branch reaches Lisz fish yard with two new CP', () {
    const service = BdoProductionNodePathCostService();
    final request = BdoProductionNodePathRequest(
      targetNodeId: '1086',
      allowedRootNodeIds: {'1'},
      currentNodeIds: {
        '1',
        '1018',
        '1021',
        '1010',
        '1009',
        '1016',
        '1017',
        '1026',
        '1055',
      },
    );
    final corrected = service.calculate(data: data, request: request);
    final historical = service.calculate(
      data: BdoResourceMapLoader.parse(
        jsonEncode({...raw, 'workerNodes': oldNodes()}),
      ),
      request: request,
    );
    expect(corrected.hasErrors, isFalse);
    expect(historical.hasErrors, isFalse);
    expect(corrected.minimumIncrementalPath!.incrementalContributionPoints, 2);
    expect(historical.minimumIncrementalPath!.incrementalContributionPoints, 3);
    expect(
      corrected.minimumIncrementalPath!.orderedNodeIds,
      containsAllInOrder(['1055', '1054', '1086']),
    );
    // This does not claim every fresh route is cheaper.
    expect(corrected.minimumTotalPath!.totalContributionPoints, 9);
    expect(historical.minimumTotalPath!.totalContributionPoints, 9);
  });

  for (final mutation in ['missing', 'duplicate', 'name', 'asymmetric']) {
    test('generation refuses $mutation instead of inferring topology', () {
      final changed = oldNodes();
      final index = changed.indexWhere((n) => n['id'] == '1054');
      switch (mutation) {
        case 'missing':
          changed.removeAt(index);
        case 'duplicate':
          changed.add({...changed[index]});
        case 'name':
          changed[index]['name'] = 'Unreviewed island identity';
        case 'asymmetric':
          (changed[index]['linkIds']! as List).add('1055');
      }
      expect(() => applyReviewedIslandLink(changed), throwsFormatException);
    });
  }
}
