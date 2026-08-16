import 'package:bdo_craft_planner_flutter/domain/models/catalog_models.dart';
import 'package:bdo_craft_planner_flutter/domain/planner/planner_models.dart';
import 'package:bdo_craft_planner_flutter/domain/planner/source_resolution.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('assembled item metadata takes precedence over vendorInfo', () {
    final resolved = resolveSourceInfo(
      name: 'Strawberry',
      recipe: _leaf(
        'Strawberry',
        sourceNote: 'Custom note',
        vendor: 'Custom Vendor',
        location: 'Custom Location',
        npcPrice: 925,
      ),
      rules: PlannerRules(
        vendorInfo: const <String, VendorSourceRule>{
          'Strawberry': VendorSourceRule(
            vendor: 'Milano Belucci',
            role: 'Fruit Vendor',
            location: 'Calpheon',
            price: 700,
          ),
        },
      ),
    );

    expect(resolved.sourceNote, 'Custom note');
    expect(resolved.vendor, 'Custom Vendor');
    expect(resolved.location, 'Custom Location');
    expect(resolved.role, 'Fruit Vendor');
    expect(resolved.npcPrice, 925);
  });

  test(
    'vendorInfo supplies source details and NPC price as final fallback',
    () {
      final resolved = resolveSourceInfo(
        name: 'Strawberry',
        recipe: _leaf('Strawberry'),
        rules: PlannerRules(
          vendorInfo: const <String, VendorSourceRule>{
            'Strawberry': VendorSourceRule(
              vendor: 'Milano Belucci',
              role: 'Fruit Vendor',
              location: 'Calpheon',
              price: 700,
            ),
          },
        ),
      );

      expect(resolved.vendor, 'Milano Belucci');
      expect(resolved.role, 'Fruit Vendor');
      expect(resolved.location, 'Calpheon');
      expect(resolved.npcPrice, 700);
      expect(resolved.hasDetails, isTrue);
    },
  );

  test('market name alias is consulted only after a direct vendor match', () {
    final rules = PlannerRules(
      marketNameAliases: const <String, String>{
        'Quality Strawberry': 'Strawberry',
      },
      vendorInfo: const <String, VendorSourceRule>{
        'Strawberry': VendorSourceRule(vendor: 'Alias Vendor', price: 700),
        'Quality Strawberry': VendorSourceRule(
          vendor: 'Direct Vendor',
          price: 800,
        ),
      },
    );
    final direct = resolveSourceInfo(
      name: 'Quality Strawberry',
      recipe: _leaf('Quality Strawberry'),
      rules: rules,
    );
    expect(direct.vendor, 'Direct Vendor');
    expect(direct.npcPrice, 800);

    final aliasOnly = resolveSourceInfo(
      name: 'quality strawberry',
      recipe: _leaf('quality strawberry'),
      rules: PlannerRules(
        marketNameAliases: const {'Quality Strawberry': 'Strawberry'},
        vendorInfo: const {
          'Strawberry': VendorSourceRule(vendor: 'Alias Vendor', price: 700),
        },
      ),
    );
    expect(aliasOnly.vendor, 'Alias Vendor');
    expect(aliasOnly.npcPrice, 700);
  });
}

Recipe _leaf(
  String name, {
  String? sourceNote,
  String? vendor,
  String? location,
  double npcPrice = 0,
}) => Recipe(
  name: name,
  type: 'gathered',
  baseOutput: 1,
  group: null,
  method: null,
  ingredients: const <Ingredient>[],
  marketId: null,
  sourceNote: sourceNote,
  vendor: vendor,
  location: location,
  npcPrice: npcPrice,
  qualityBase: null,
  qualityGrade: null,
  outputMinimum: null,
  outputMaximum: null,
);
