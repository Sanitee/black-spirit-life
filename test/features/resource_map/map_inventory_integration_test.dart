import 'dart:io';
import 'package:bdo_craft_planner_flutter/data/catalog/bundled_catalog_parser.dart';
import 'package:bdo_craft_planner_flutter/domain/models/craft_mode.dart';
import 'package:bdo_craft_planner_flutter/features/resource_map/resource_map_need_availability.dart';
import 'package:bdo_craft_planner_flutter/features/shared/inventory_count_badge.dart';
import 'package:bdo_craft_planner_flutter/features/shared/market_count_badges.dart';
import 'package:bdo_craft_planner_flutter/visual/visual.dart';
import 'package:bdo_map_core/bdo_map_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import '../planner/planner_review_projection_test.dart' as fixture;

void main() {
  testWidgets('Live Map shortlist mounts inventory/market in its real rows', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final dataset = (await tester.runAsync(BdoResourceMapLoader.loadBundled))!;
    final catalog = const BundledCatalogParser().parse(
      File('assets/data/app-data.json').readAsStringSync(),
    );
    final app = fixture.controller(catalog, CraftMode.cooking, 'Beer', 100);
    final cache = Directory('build/map-integration-cache');
    await tester.runAsync(() => cache.create(recursive: true));
    final client = MockClient((_) async => http.Response('', 404));
    final needs = [
      for (final n in ['Rough Stone', 'Log', 'Deer Meat'])
        BdoPlannerMaterialNeed(
          name: n,
          missingQuantity: 1234,
          marketable: true,
          stockKnown: false,
          stock: 0,
          marketRegion: 'EU',
          marketFetchedAt: null,
        ),
    ];
    await tester.pumpWidget(
      MaterialApp(
        home: ThemeSpecScope(
          spec: RetainedThemeRegistry.sakuraNightGarden,
          child: BdoResourceMap(
            dataset: dataset,
            cacheDirectory: cache,
            tileHttpClient: client,
            showSourceNotice: false,
            plannerNeeds: needs,
            plannerNeedAvailabilityBuilder: (context, need) =>
                ResourceMapNeedAvailability(
                  controller: app.active,
                  need: need,
                  needs: needs,
                  ownedFor: (_) => 75,
                ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('resource-map-home-find-material')),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('resource-map-gather-plan-shortlist')),
    );
    await tester.pumpAndSettle();
    expect(find.byType(ResourceMapNeedAvailability), findsNWidgets(3));
    expect(find.byType(InventoryCountBadge), findsNWidgets(3));
    expect(find.byType(MarketCountBadges), findsNWidgets(3));
    for (final name in ['Rough Stone', 'Log', 'Deer Meat']) {
      expect(find.text(name), findsWidgets);
    }
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    client.close();
    await app.dispose();
  });
}
