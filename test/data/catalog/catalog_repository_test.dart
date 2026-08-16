import 'dart:io';

import 'package:bdo_craft_planner_flutter/data/catalog/bundled_catalog_parser.dart';
import 'package:bdo_craft_planner_flutter/data/catalog/catalog_repository.dart';
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
}
