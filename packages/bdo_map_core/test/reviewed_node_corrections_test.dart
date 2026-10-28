import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../tool/reviewed_node_corrections.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Map<String, Object?> seaNode(String id, String name) => {
    'id': id,
    'name': name,
    'nodeType': 'Connection',
    'isProductionNode': false,
    'isResourceNode': false,
    'contributionPoints': 0,
    'outputs': <Object?>[],
    'linkIds': <Object?>[],
  };

  late List<Map<String, Object?>> seed;
  setUp(() {
    seed = [
      seaNode('1', 'Other connection'),
      seaNode('2113', 'Oceanus Sea'),
      seaNode('2114', 'Tiamat Sea'),
      {...seaNode('2', 'Fishing'), 'isProductionNode': true},
    ];
  });

  test('future generation excludes only the two reviewed labels', () {
    final corrected = applyReviewedSeaNodeCorrection(seed);
    expect(corrected, [seed[0], seed[3]]);
    expect(seed, hasLength(4));
  });

  for (final mutation in [
    'production',
    'outgoing link',
    'incoming link',
    'missing',
  ]) {
    test('changed seed fails closed: $mutation', () {
      switch (mutation) {
        case 'production':
          seed[1]['isProductionNode'] = true;
        case 'outgoing link':
          seed[1]['linkIds'] = ['1'];
        case 'incoming link':
          seed[0]['linkIds'] = ['2113'];
        case 'missing':
          seed.removeAt(1);
      }
      expect(() => applyReviewedSeaNodeCorrection(seed), throwsFormatException);
    });
  }

  test('generated correction provenance matches the shipped bundle', () async {
    final data =
        jsonDecode(
              await rootBundle.loadString(
                'packages/bdo_map_core/assets/data/resource_map.json',
              ),
            )
            as Map<String, dynamic>;
    final manifest = data['manifest'] as Map<String, dynamic>;
    final provenance = (manifest['provenance'] as List<Object?>)
        .cast<Map<String, Object?>>();
    expect(
      provenance.singleWhere(
        (record) => record['id'] == octoberSeaNodeCorrection['id'],
      ),
      octoberSeaNodeCorrection,
    );
  });
}
