import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:bdo_craft_planner_flutter/app/workspace/planner_gather_checklist_bridge.dart';
import 'package:bdo_craft_planner_flutter/data/catalog/bundled_catalog_parser.dart';
import 'package:bdo_craft_planner_flutter/data/catalog/catalog_repository.dart';
import 'package:bdo_craft_planner_flutter/data/market/shared_market_repository.dart';
import 'package:bdo_craft_planner_flutter/domain/models/craft_mode.dart';
import 'package:bdo_craft_planner_flutter/domain/state/inventory_storage.dart';
import 'package:bdo_craft_planner_flutter/features/planner/planner_choice_market.dart';
import 'package:bdo_craft_planner_flutter/features/resource_map/resource_map_need_availability.dart';
import 'package:bdo_craft_planner_flutter/features/resource_map/resource_map_theme_adapter.dart';
import 'package:bdo_craft_planner_flutter/features/shared/inventory_count_badge.dart';
import 'package:bdo_craft_planner_flutter/features/shared/market_count_badges.dart';
import 'package:bdo_craft_planner_flutter/visual/visual.dart';
import 'package:bdo_map_core/bdo_map_core.dart';
import 'package:bdo_map_core/src/widgets/gather_checklist_quantity_row.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import '../../support/choice_market_transport.dart';
import '../../support/native_preview_fonts.dart';
import '../planner/planner_choice_market_test.dart' show settle;
import '../planner/planner_review_projection_test.dart' as fixture;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final catalog = const BundledCatalogParser().parse(
    File('assets/data/app-data.json').readAsStringSync(),
  );
  setUpAll(loadNativePreviewFonts);
  for (final spec in RetainedThemeRegistry.themes) {
    if (![
      'standard',
      'sakura-night-garden',
      'illuminated-ledger',
    ].contains(spec.id)) {
      continue;
    }
    for (final scale in [1.0, 2.0]) {
      testWidgets('Map inventory/market alignment ${spec.id} $scale', (
        tester,
      ) async {
        tester.view.physicalSize = const Size(850, 720);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final app = fixture.controller(catalog, CraftMode.cooking, 'Beer', 100);
        final bridge = PlannerGatherChecklistBridge(
          controller: app,
          catalog: CatalogRepository.cached(catalog),
        );
        final names = ['Rough Stone', 'Log', 'Deer Meat'];
        app.updateDocument(
          (s) =>
              applySharedInventoryDeltas(s, {'Rough Stone': 1234, 'Log': 75}),
        );
        app.active.setIgnoreOwnedIngredients(true);
        expect(bridge.ownedFor('Rough Stone'), 1234);
        final needs = [
          for (final n in names)
            BdoPlannerMaterialNeed(
              name: n,
              missingQuantity: n == 'Log' ? 2500 : 1200,
              marketable: true,
              stockKnown: false,
              stock: 0,
              marketRegion: 'EU',
              marketFetchedAt: null,
            ),
        ];
        final transport = ChoiceMarketTransport();
        final ids = [
          for (final n in names)
            choiceMarketIdentity(app.active, n, acrossModes: true).marketId!,
        ];
        transport.values[ids[0]] = (price: 500, stock: 0, preorders: 84);
        transport.values[ids[1]] = (price: 500, stock: 12345, preorders: 7);
        final broker = SharedMarketRepository(
          transport: transport,
          requestSpacing: Duration.zero,
        );
        await tester.pumpWidget(
          MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: spec.materialTheme(),
            home: ThemeSpecScope(
              spec: spec,
              child: PlannerChoiceMarketScope(
                repository: broker,
                child: MediaQuery(
                  data: MediaQueryData(textScaler: TextScaler.linear(scale)),
                  child: ResourceMapThemeAdapter(
                    spec: spec,
                    child: Scaffold(
                      backgroundColor: spec.palette.surface,
                      body: Center(
                        child: RepaintBoundary(
                          key: const ValueKey('capture'),
                          child: SizedBox(
                            width: scale == 1 ? 470 : 700,
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                for (final need in needs)
                                  ResourceMapPill(
                                    child: Padding(
                                      padding: const EdgeInsets.all(14),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            need.name,
                                            style: TextStyle(
                                              fontSize: 16,
                                              fontWeight: FontWeight.w700,
                                              color: spec.palette.text,
                                            ),
                                          ),
                                          const SizedBox(height: 6),
                                          ResourceMapNeedAvailability(
                                            controller: app.active,
                                            need: need,
                                            needs: needs,
                                            ownedFor: bridge.ownedFor,
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await settle(tester, broker);
        expect(find.byType(InventoryCountBadge), findsNWidgets(3));
        expect(find.text('Orders 84'), findsOneWidget);
        expect(find.text('Need 2.500'), findsOneWidget);
        final inventories = find
            .byType(InventoryCountBadge)
            .evaluate()
            .map((e) => tester.getRect(find.byWidget(e.widget)))
            .toList();
        final markets = find
            .byType(MarketCountBadges)
            .evaluate()
            .map((e) => tester.getRect(find.byWidget(e.widget)))
            .toList();
        for (var i = 0; i < 3; i++) {
          expect(
            markets[i].left - inventories[i].right,
            greaterThanOrEqualTo(12 * scale - 0.1),
          );
          expect(markets[i].center.dy, closeTo(inventories[i].center.dy, 1));
          expect(inventories[i].left, closeTo(inventories[0].left, 1));
          expect(markets[i].left, closeTo(markets[0].left, 1));
        }
        expect(tester.takeException(), isNull);
        final boundary = tester.renderObject<RenderRepaintBoundary>(
          find.byKey(const ValueKey('capture')),
        );
        await tester.runAsync(() async {
          for (final image in tester.widgetList<Image>(find.byType(Image))) {
            await precacheImage(
              image.image,
              tester.element(find.byKey(const ValueKey('capture'))),
            );
          }
        });
        await tester.pumpAndSettle();
        await tester.runAsync(() async {
          final img = await (boundary.debugLayer! as OffsetLayer).toImage(
            Offset.zero & boundary.size,
          );
          final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
          final file = File(
            'build/map-inventory-number-consistency/${spec.id}-$scale.png',
          );
          await file.parent.create(recursive: true);
          await file.writeAsBytes(bytes!.buffer.asUint8List());
          img.dispose();
        });
        app.updateDocument((s) => applySharedInventoryDeltas(s, {'Log': 25}));
        await tester.pumpAndSettle();
        expect(
          tester
              .widgetList<InventoryCountBadge>(find.byType(InventoryCountBadge))
              .elementAt(1)
              .owned,
          100,
        );
        transport.hold = Completer<void>();
        app.active.setMarketRegion('na');
        await tester.pump(const Duration(milliseconds: 200));
        expect(
          tester
              .widgetList<MarketCountBadges>(find.byType(MarketCountBadges))
              .every((b) => b.stock == null && b.preorders == null),
          isTrue,
        );
        await tester.pumpWidget(const SizedBox());
        transport.hold!.complete();
        await broker.close();
        bridge.dispose();
        await app.dispose();
      });
    }
  }
  testWidgets(
    'Map grouped input and decimals record exact quantities, Undo stays intact',
    (tester) async {
      final values = <double>[];
      var undos = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: ResourceMapChromeTheme(
            data: ResourceMapChromeThemeData.glassDock,
            child: Scaffold(
              body: SizedBox(
                width: 400,
                child: GatherChecklistQuantityRow(
                  resourceId: 'stone',
                  quantity: const BdoGatherChecklistQuantity(
                    needed: 3000,
                    owned: 1234,
                    canRecord: true,
                  ),
                  onRecord: (_, amount) async {
                    values.add(amount);
                    return BdoGatherChecklistReceipt(
                      undo: () async {
                        undos++;
                      },
                    );
                  },
                  child: const Text('Rough Stone'),
                ),
              ),
            ),
          ),
        ),
      );
      expect(find.text('1.234'), findsOneWidget);
      expect(find.text('1.766'), findsOneWidget);
      for (final value in ['1.234', '1.234,5', '4.5', '0,125']) {
        await tester.tap(
          find.byKey(const ValueKey('gather-record-open:stone')),
        );
        await tester.pump();
        await tester.enterText(
          find.byKey(const ValueKey('gather-record-amount:stone')),
          value,
        );
        await tester.tap(
          find.byKey(const ValueKey('gather-record-save:stone')),
        );
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(const ValueKey('gather-record-undo:stone')),
        );
        await tester.pumpAndSettle();
      }
      expect(values, [1234, 1234.5, 4.5, .125]);
      expect(undos, 4);
      expect(tester.takeException(), isNull);
    },
  );
}
