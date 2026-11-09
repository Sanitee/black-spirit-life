import 'dart:io';
import 'dart:ui' as ui;

import 'package:bdo_craft_planner_flutter/data/catalog/bundled_catalog_parser.dart';
import 'package:bdo_craft_planner_flutter/data/market/shared_market_repository.dart';
import 'package:bdo_craft_planner_flutter/domain/models/catalog_models.dart';
import 'package:bdo_craft_planner_flutter/domain/models/craft_mode.dart';
import 'package:bdo_craft_planner_flutter/features/planner/planner.dart';
import 'package:bdo_craft_planner_flutter/features/planner/planner_choice_market.dart';
import 'package:bdo_craft_planner_flutter/features/planner/planner_quantity_layout.dart';
import 'package:bdo_craft_planner_flutter/features/shared/market_count_badges.dart';
import 'package:bdo_craft_planner_flutter/features/shared/npc_source_marker.dart';
import 'package:bdo_craft_planner_flutter/shared/overlays/anchored_popover.dart';
import 'package:bdo_craft_planner_flutter/visual/visual.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/choice_market_transport.dart';
import 'planner_choice_market_test.dart' show settle;
import 'planner_review_projection_test.dart' as fixture;

void main() {
  setUpAll(() async {
    final win = Platform.environment['WINDIR']!;
    for (final entry in {
      'Segoe UI': ['$win/Fonts/segoeui.ttf', '$win/Fonts/seguisb.ttf'],
      'Georgia': ['$win/Fonts/georgia.ttf', '$win/Fonts/georgiab.ttf'],
    }.entries) {
      final loader = FontLoader(entry.key);
      for (final file in entry.value) {
        loader.addFont(File(file).readAsBytes().then(ByteData.sublistView));
      }
      await loader.load();
    }
  });
  for (final spec in RetainedThemeRegistry.themes) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('NPC and orders ${spec.id} $scale', (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(1800, 1300);
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final base = const BundledCatalogParser().parse(
          File('assets/data/app-data.json').readAsStringSync(),
        );
        final cooking = base.cooking;
        final catalog = CatalogSnapshot(
          sourceSha256: base.sourceSha256,
          sourceByteCount: base.sourceByteCount,
          alchemy: base.alchemy,
          processing: base.processing,
          supportingData: base.supportingData,
          collisions: base.collisions,
          cooking: ModeCatalog(
            mode: CraftMode.cooking,
            iconDataUris: cooking.iconDataUris,
            defaults: cooking.defaults,
            metadata: cooking.metadata,
            searchAliases: cooking.searchAliases,
            items: {
              ...cooking.items,
              'Vendor display fixture': Recipe(
                name: 'Vendor display fixture',
                type: 'cooking',
                baseOutput: 1,
                group: null,
                method: null,
                marketId: null,
                sourceNote: null,
                vendor: null,
                location: null,
                npcPrice: 0,
                qualityBase: null,
                qualityGrade: null,
                outputMinimum: null,
                outputMaximum: null,
                ingredients: [
                  for (final row in [
                    ('Base Sauce', 1.0),
                    ('Milk', 3.0),
                    ('Mineral Water', 6.0),
                    ('Paprika', 2.0),
                  ])
                    Ingredient(
                      name: row.$1,
                      quantity: row.$2,
                      options: [],
                      substituteGroup: null,
                      substituteRatios: {},
                    ),
                ],
              ),
            },
          ),
        );
        final app = fixture.controller(
          catalog,
          CraftMode.cooking,
          'Vendor display fixture',
          100,
        );
        final mode = app.active;
        mode.setPricesVisible(true);
        mode.replaceMarketValues(
          prices: {'Milk': 10800},
          stock: {'Milk': 0},
          unlistedItemNames: const [],
          fetchedAt: DateTime.now().millisecondsSinceEpoch,
          region: 'eu',
        );
        final transport = ChoiceMarketTransport();
        final milkId = choiceMarketIdentity(
          mode,
          'Milk',
          acrossModes: true,
        ).marketId!;
        final paprikaId = choiceMarketIdentity(
          mode,
          'Paprika',
          acrossModes: true,
        ).marketId!;
        transport.values[milkId] = (price: 10800, stock: 0, preorders: 89300);
        transport.values[paprikaId] = (price: 1000, stock: 7, preorders: 33);
        final broker = SharedMarketRepository(
          transport: transport,
          requestSpacing: Duration.zero,
        );
        final before = app.documentSnapshot.toJson();
        await tester.pumpWidget(
          RepaintBoundary(
            key: const ValueKey('full-capture'),
            child: AppOverlayCoordinatorHost(
              child: MaterialApp(
                debugShowCheckedModeBanner: false,
                theme: spec.materialTheme(),
                builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(
                    context,
                  ).copyWith(textScaler: TextScaler.linear(scale)),
                  child: child!,
                ),
                home: ThemeSpecScope(
                  spec: spec,
                  child: PlannerChoiceMarketScope(
                    repository: broker,
                    child: Scaffold(
                      body: RepaintBoundary(
                        key: const ValueKey('capture'),
                        child: PlannerView(
                          controller: mode,
                          externalActions: PlannerExternalActions(
                            openRecipeBook: (_) {},
                            copyName: (_) async {},
                            checkPrices: (_) async => throw StateError(
                              'No explicit refresh in this fixture',
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
        await tester.pumpAndSettle();
        // Stable IDs can include selection metadata; find through displayed name.
        Finder namedRow(String name) => find
            .ancestor(
              of: find.byKey(PlannerActionKeys.row('P20', name)),
              matching: find.byType(PlannerNeedQuantities),
            )
            .first;
        for (final name in ['Base Sauce', 'Mineral Water', 'Paprika']) {
          final r = namedRow(name);
          await tester.ensureVisible(r);
          await tester.pumpAndSettle();
          final marker = find.descendant(
            of: r,
            matching: find.byType(NpcSourceMarker),
          );
          expect(marker, findsOneWidget, reason: name);
          expect(find.byKey(PlannerActionKeys.row('P17', name)), findsNothing);
          final label = find.descendant(of: r, matching: find.text(name)).first;
          expect(
            tester.getRect(marker).left - tester.getRect(label).right,
            closeTo(12, 2),
          );
          expect(
            tester.getRect(marker).center.dy,
            closeTo(tester.getRect(label).center.dy, 1),
          );
        }
        final milk = namedRow('Milk');
        await tester.ensureVisible(milk);
        await tester.pumpAndSettle();
        final milkBadges = tester.widget<MarketCountBadges>(
          find.descendant(of: milk, matching: find.byType(MarketCountBadges)),
        );
        expect(milkBadges.stock, 0);
        expect(milkBadges.preorders, 89300);
        expect(
          find.descendant(of: milk, matching: find.byType(NpcSourceMarker)),
          findsNothing,
        );
        final paprika = namedRow('Paprika');
        final badges = tester.widget<MarketCountBadges>(
          find.descendant(
            of: paprika,
            matching: find.byType(MarketCountBadges),
          ),
        );
        expect(badges.stock, 7);
        expect(badges.preorders, 33);
        expect(app.documentSnapshot.toJson(), before);
        expect(tester.takeException(), isNull);
        final out = Platform.environment['BSL_NPC_CAPTURE'];
        if (out != null) {
          await tester.ensureVisible(namedRow('Mineral Water'));
          await tester.pumpAndSettle();
          for (final element in find.byType(Image).evaluate()) {
            await tester.runAsync(
              () => precacheImage((element.widget as Image).image, element),
            );
          }
          await tester.pumpAndSettle();
          final boundary = tester.renderObject<RenderRepaintBoundary>(
            find.byKey(const ValueKey('capture')),
          );
          await tester.runAsync(() async {
            final bounds = tester.getRect(
              find.byKey(const PageStorageKey<String>('planner-need-first')),
            );
            final rect = Rect.fromLTRB(
              bounds.left,
              (bounds.top - 55).clamp(0, 1300),
              bounds.right,
              (bounds.top + 700 * scale).clamp(0, 1300),
            );
            // Test-only capture of the actual rendered Need First region.
            // ignore: invalid_use_of_protected_member
            final image = await (boundary.layer! as OffsetLayer).toImage(
              rect,
              pixelRatio: 1,
            );
            final bytes = (await image.toByteData(
              format: ui.ImageByteFormat.png,
            ))!;
            await Directory(out).create(recursive: true);
            await File(
              '$out/need-${spec.id}-$scale.png',
            ).writeAsBytes(bytes.buffer.asUint8List());
            image.dispose();
          });
          if (scale == 1 && spec.id == 'standard') {
            final marker = find.descendant(
              of: namedRow('Base Sauce'),
              matching: find.byType(NpcSourceMarker),
            );
            final mouse = await tester.createGesture(
              kind: PointerDeviceKind.mouse,
            );
            await mouse.addPointer(location: Offset.zero);
            await mouse.moveTo(tester.getCenter(marker));
            await tester.pump(const Duration(milliseconds: 1250));
            await tester.pumpAndSettle();
            expect(find.text('Food Vendor or Innkeeper'), findsOneWidget);
            final root = tester.renderObject<RenderRepaintBoundary>(
              find.byKey(const ValueKey('full-capture')),
            );
            await tester.runAsync(() async {
              final bounds = tester.getRect(
                find.byKey(const PageStorageKey<String>('planner-need-first')),
              );
              // ignore: invalid_use_of_protected_member
              final hover = await (root.layer! as OffsetLayer).toImage(
                Rect.fromLTRB(
                  bounds.left - 20,
                  bounds.top - 55,
                  bounds.right,
                  bounds.top + 700,
                ),
              );
              final hoverBytes = (await hover.toByteData(
                format: ui.ImageByteFormat.png,
              ))!;
              await File(
                '$out/npc-hover.png',
              ).writeAsBytes(hoverBytes.buffer.asUint8List());
              hover.dispose();
            });
            await mouse.removePointer();
          }
        }
        await tester.pumpWidget(const SizedBox());
        await tester.pumpAndSettle();
        await tester.runAsync(() async {
          await broker.close();
          await app.dispose();
        });
      });
    }
  }
}
