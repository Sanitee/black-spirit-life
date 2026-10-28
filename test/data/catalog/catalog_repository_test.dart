import 'dart:io';

import 'package:bdo_craft_planner_flutter/data/catalog/bundled_catalog_parser.dart';
import 'package:bdo_craft_planner_flutter/data/catalog/catalog_repository.dart';
import 'package:bdo_craft_planner_flutter/domain/models/catalog_models.dart';
import 'package:bdo_craft_planner_flutter/domain/models/craft_mode.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late CatalogRepository repository;

  setUpAll(() {
    final source = File('assets/data/app-data.json').readAsStringSync();
    repository = CatalogRepository(const BundledCatalogParser().parse(source));
  });

  test('exact icon spelling wins across a case-only collision', () {
    final lower = repository.iconDataUri(
      CraftMode.cooking,
      'High-quality Grape',
    );
    final title = repository.iconDataUri(
      CraftMode.cooking,
      'High-Quality Grape',
    );

    expect(lower, isNotNull);
    expect(title, isNotNull);
    expect(lower, isNot(title));
  });

  test('nonexact icon lookup chooses the active catalog spelling', () {
    final nonexact = repository.iconDataUri(
      CraftMode.cooking,
      'HIGH-QUALITY GRAPE',
    );
    final canonical = repository.iconDataUri(
      CraftMode.cooking,
      'High-Quality Grape',
    );

    expect(nonexact, canonical);
  });

  test('market lookup follows exact then normalized aliases', () {
    expect(repository.bundledMarketId('Wheat'), isNotNull);
    expect(
      repository.bundledMarketId('  wheat  '),
      repository.bundledMarketId('Wheat'),
    );
  });

  test('shared surfaces can resolve artwork from a different craft mode', () {
    expect(repository.iconDataUri(CraftMode.alchemy, 'Ash Timber'), isNull);
    expect(
      repository.iconDataUriAcrossModes(CraftMode.alchemy, 'Ash Timber'),
      repository.iconDataUri(CraftMode.processing, 'Ash Timber'),
    );
  });

  test('cross-mode artwork still prefers the active craft mode', () {
    expect(
      repository.iconDataUriAcrossModes(
        CraftMode.cooking,
        'High-Quality Grape',
      ),
      repository.iconDataUri(CraftMode.cooking, 'High-Quality Grape'),
    );
  });

  test(
    'NPC fallback excludes conflicting names, identities and invalid prices',
    () {
      final alchemy = {
        'Same price': _priced('Same price', 100, id: '1'),
        'Price conflict': _priced('Price conflict', 100),
        'Identity conflict': _priced('Identity conflict', 100, id: '2'),
        'Invalid': _priced('Invalid', double.infinity),
        'Zero': _priced('Zero', 0),
      };
      final processing = {
        'same price': _priced('same price', 100, id: '1'),
        'price conflict': _priced('price conflict', 200),
        'identity conflict': _priced('identity conflict', 100, id: '3'),
      };
      final fixture = CatalogRepository(
        CatalogSnapshot(
          sourceSha256: 'npc-fixture',
          sourceByteCount: 1,
          alchemy: _mode(CraftMode.alchemy, alchemy),
          cooking: _mode(CraftMode.cooking, const {}),
          processing: _mode(CraftMode.processing, processing),
          supportingData: const {
            'fallbackMarketPrices': {'Unknown': 500},
          },
          collisions: const [],
        ),
      );
      expect(fixture.npcPurchasePrices, {'same price': 100});
      expect(
        () => fixture.npcPurchasePrices['Unknown'] = 1,
        throwsUnsupportedError,
      );
    },
  );
}

ModeCatalog _mode(CraftMode mode, Map<String, Recipe> items) => ModeCatalog(
  mode: mode,
  items: items,
  iconDataUris: const {},
  defaults: const {},
  metadata: const {},
  searchAliases: const {},
);

Recipe _priced(String name, double npcPrice, {String? id}) => Recipe(
  name: name,
  type: 'gathered',
  baseOutput: 1,
  group: null,
  method: null,
  ingredients: const [],
  marketId: id,
  sourceNote: null,
  vendor: null,
  location: null,
  npcPrice: npcPrice,
  qualityBase: null,
  qualityGrade: null,
  outputMinimum: null,
  outputMaximum: null,
);
