import 'package:bdo_map_core/src/model/planner_material_need.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'planner substitute family owns immutable member and ratio snapshots',
    () {
      final members = <String>['Wolf Blood', 'Flamingo Blood'];
      final ratios = <String, double>{'Wolf Blood': 1, 'Flamingo Blood': 1};
      final family = BdoPlannerSubstituteFamily(
        parentName: "Clown's Blood",
        originalName: 'Wolf Blood',
        familyName: 'Blood Group 1',
        selectedName: 'Wolf Blood',
        members: members,
        ratios: ratios,
      );

      members.add('Rhino Blood');
      ratios['Wolf Blood'] = 2;

      expect(family.members, <String>['Wolf Blood', 'Flamingo Blood']);
      expect(family.ratios, <String, double>{
        'Wolf Blood': 1,
        'Flamingo Blood': 1,
      });
      expect(() => family.members.add('Rhino Blood'), throwsUnsupportedError);
      expect(() => family.ratios['Wolf Blood'] = 2, throwsUnsupportedError);

      final need = BdoPlannerMaterialNeed(
        name: 'Wolf Blood',
        missingQuantity: 2,
        marketable: true,
        stockKnown: true,
        stock: 0,
        marketRegion: 'eu',
        marketFetchedAt: null,
        substituteFamily: family,
      );
      expect(need.substituteFamily, same(family));
    },
  );

  test('planner material need keeps substitute metadata optional', () {
    const need = BdoPlannerMaterialNeed(
      name: 'Truffle Mushroom',
      missingQuantity: 1,
      marketable: true,
      stockKnown: false,
      stock: 0,
      marketRegion: 'eu',
      marketFetchedAt: null,
    );

    expect(need.substituteFamily, isNull);
  });
}
