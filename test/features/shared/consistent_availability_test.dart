import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:bdo_craft_planner_flutter/data/catalog/bundled_catalog_parser.dart';
import 'package:bdo_craft_planner_flutter/data/catalog/catalog_repository.dart';
import 'package:bdo_craft_planner_flutter/data/market/shared_market_repository.dart';
import 'package:bdo_craft_planner_flutter/domain/models/catalog_models.dart';
import 'package:bdo_craft_planner_flutter/domain/models/craft_mode.dart';
import 'package:bdo_craft_planner_flutter/features/gathering/gathering_workspace.dart';
import 'package:bdo_craft_planner_flutter/features/opportunities/opportunity_silver_amount.dart';
import 'package:bdo_craft_planner_flutter/features/planner/planner_choice_market.dart';
import 'package:bdo_craft_planner_flutter/features/planner/planner_contracts.dart';
import 'package:bdo_craft_planner_flutter/features/recipe_book/recipe_book_controller.dart';
import 'package:bdo_craft_planner_flutter/features/recipe_book/recipe_book_item_info_view.dart';
import 'package:bdo_craft_planner_flutter/features/resource_map/resource_map_theme_adapter.dart';
import 'package:bdo_craft_planner_flutter/features/shared/shared_silver_amount.dart';
import 'package:bdo_craft_planner_flutter/features/shared/source_availability_badges.dart';
import 'package:bdo_craft_planner_flutter/visual/visual.dart';
import 'package:bdo_gathering_companion/domain/bairog_calculator.dart';
import 'package:bdo_gathering_companion/domain/models.dart' as gathering;
import 'package:bdo_gathering_companion/src/services/gathering_market_service.dart';
import 'package:bdo_gathering_companion/src/ui/field_guide.dart';
import 'package:bdo_gathering_companion/src/ui/theme.dart';
import 'package:bdo_map_core/bdo_map_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/availability_badge_finders.dart';
import '../../support/choice_market_transport.dart';
import '../planner/planner_choice_market_test.dart' show settle;
import '../planner/planner_review_projection_test.dart' as projection;

const captureKey = ValueKey('consistent-availability-capture');
Finder k(String key) => find.byKey(ValueKey(key));

void main() {
  late CatalogSnapshot catalog;
  setUpAll(() async {
    catalog = const BundledCatalogParser().parse(
      File('assets/data/app-data.json').readAsStringSync(),
    );
    for (final entry in {
      'Segoe UI': [
        'C:/Windows/Fonts/segoeui.ttf',
        'C:/Windows/Fonts/seguisb.ttf',
      ],
      'Georgia': [
        'C:/Windows/Fonts/georgia.ttf',
        'C:/Windows/Fonts/georgiab.ttf',
      ],
      'Roboto': [
        'D:/Tools/flutter/bin/cache/artifacts/material_fonts/roboto-regular.ttf',
      ],
      'MaterialIcons': [
        'D:/Tools/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
      ],
    }.entries) {
      final loader = FontLoader(entry.key);
      for (final path in entry.value) {
        loader.addFont(File(path).readAsBytes().then(ByteData.sublistView));
      }
      await loader.load();
    }
  });

  for (final spec in RetainedThemeRegistry.themes) {
    for (final scale in [1.0, 2.0]) {
      testWidgets(
        'inline exchange uses aligned shared availability columns ${spec.id} $scale',
        (tester) async {
          await viewport(tester, const Size(900, 1400));
          final app = projection.controller(
            catalog,
            CraftMode.cooking,
            'Beer',
            100,
          );
          final before = jsonEncode(app.documentSnapshot.toJson());
          final book = RecipeBookController(
            modeController: app.active,
            catalogRepository: CatalogRepository(catalog),
            callingContext: RecipeBookCallingContext.planner,
            allowedTargets: app.active.craftableNames,
          );
          final transport = ChoiceMarketTransport();
          transport.values['9057'] = (price: 1200, stock: 0, preorders: 84);
          final broker = SharedMarketRepository(
            transport: transport,
            requestSpacing: Duration.zero,
          );
          final copies = <String>[];
          try {
            final info = book.itemInfoFor('Iridescent Maehwa')!;
            await tester.pumpWidget(
              host(
                spec,
                scale,
                PlannerChoiceMarketScope(
                  repository: broker,
                  child: SingleChildScrollView(
                    child: Center(
                      child: Container(
                        width: 540,
                        padding: const EdgeInsets.all(18),
                        child: ItemReferenceSections(
                          controller: book,
                          mode: CraftMode.cooking,
                          name: 'Iridescent Maehwa',
                          info: info,
                          spec: spec,
                          onCopyItemName: copies.add,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
            await settle(tester, broker);
            await tester.pumpAndSettle();
            expect(
              find.descendant(
                of: k('reference-source:Leavening Agent'),
                matching: find.text('NPC'),
              ),
              findsOneWidget,
            );
            expect(find.text('Inventory'), findsOneWidget);
            expect(stockBadgeText('0'), findsOneWidget);
            expect(find.text('Orders 84'), findsOneWidget);
            // Maehwa is also market-eligible in the current shared catalogue.
            // The pre-existing registry fallback correctly resolves its ID.
            expect(transport.requests.expand((r) => r.ids).toSet(), {
              '9057',
              '820131',
            });
            expect(stockBadgeText('12,6k'), findsOneWidget);
            for (final name in [
              'Leavening Agent',
              'Essence of Liquor',
              'Maehwa',
            ]) {
              final label = tester.getRect(find.text(name));
              final badge = tester.getRect(k('reference-source:$name'));
              expect(badge.center.dy, closeTo(label.center.dy, 1));
              expect(badge.left, greaterThan(label.right));
            }
            await tester.tap(find.text('Leavening Agent'));
            expect(copies, ['Leavening Agent']);
            await capture(tester, 'exchange-${spec.id}-$scale');
            expect(jsonEncode(app.documentSnapshot.toJson()), before);
            transport.hold = Completer<void>();
            app.modes[CraftMode.processing]!.setMarketRegion('na');
            await tester.pump(const Duration(milliseconds: 200));
            expect(stockBadgeText('—'), findsNWidgets(2));
            expect(transport.requests.last.region, 'na');
            await tester.pumpWidget(const SizedBox());
            await tester.pump(const Duration(milliseconds: 600));
            expect(transport.aborted, isTrue);
            transport.hold!.complete();
            expect(tester.takeException(), isNull);
          } finally {
            await tester.pumpWidget(const SizedBox());
            book.dispose();
            await broker.close();
            await app.dispose();
          }
        },
      );

      testWidgets(
        'hosted Royal Workshop uses shared silver ${spec.id} $scale',
        (tester) async {
          await viewport(tester, const Size(1200, 1050));
          final plan = BdoRoyalWorkshopPlan(
            accessInvested: true,
            areaPlans: const {
              'infirmary': BdoRoyalWorkshopAreaPlan(
                workerName: 'Review worker',
                isRunning: true,
                workshopPlans: {
                  0: BdoRoyalWorkshopSlotPlan(
                    selectedGoodId: 821120,
                    recordedGoodName: 'Dew-kissed Green Plum',
                    taskHours: 1,
                    netSilverPerCycle: 1100000,
                    isRareOrSpecial: false,
                  ),
                },
              ),
            },
          );
          await tester.pumpWidget(
            host(
              spec,
              scale,
              ResourceMapThemeAdapter(
                spec: spec,
                child: BdoRoyalWorkshopManager(
                  plan: plan,
                  goods: const [
                    BdoRoyalWorkshopGood(
                      id: 821120,
                      name: 'Dew-kissed Green Plum',
                      kind: BdoRoyalWorkshopKind.production,
                      referencePrice: 35000,
                      rareRoll: false,
                    ),
                  ],
                  onChanged: (_) =>
                      fail('Display-only silver must not edit the plan.'),
                  onOpenYukjoHousing: () {},
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(find.byType(SharedSilverAmount), findsWidgets);
          expect(k('royal-workshop-income-summary'), findsOneWidget);
          expect(
            tester.widget<Text>(k('royal-workshop-income-summary')).data,
            '1,1m',
          );
          await capture(tester, 'royal-${spec.id}-$scale');
          await tester.tap(k('royal-workshop-income-summary'));
          await tester.pumpAndSettle();
          expect(
            tester.widget<Text>(k('royal-workshop-income-summary')).data,
            '1.100.000',
          );
          await tester.tap(k('royal-workshop-area-button-infirmary'));
          await tester.pumpAndSettle();
          expect(find.text('Income'), findsOneWidget);
          expect(find.byType(SharedSilverAmount), findsOneWidget);
          expect(find.text('1,1m'), findsOneWidget);
          await tester.ensureVisible(find.text('Income'));
          await capture(tester, 'royal-area-${spec.id}-$scale');
          await tester.tap(find.text('1,1m'));
          await tester.pumpAndSettle();
          expect(find.text('1.100.000'), findsOneWidget);
          // Clicking the read-only amount must not open the editable fields.
          expect(k('royal-workshop-net-infirmary-0'), findsNothing);
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox());
        },
      );

      testWidgets(
        'Gathering Value Demand and detail use shared widgets ${spec.id} $scale',
        (tester) async {
          await viewport(tester, const Size(1400, 1100));
          final data = (await tester.runAsync(gathering.Catalog.load))!;
          await tester.pumpWidget(
            host(
              spec,
              scale,
              GatheringSharedMarketStyle(
                child: FieldGuide(
                  catalog: data,
                  bairogCalculatorData: data.bairogCalculatorData,
                  bairogSettings: const BairogCalculatorSettings(),
                  marketOrderBookLoader:
                      (items, {includePreorders = false}) async => {
                        for (final id in items.keys)
                          id: GatheringMarketQuote(
                            itemId: int.parse(id),
                            price: id == '4998' ? 4800000 : 100000,
                            stock: id == '4998' ? 0 : 12594,
                            preorders: includePreorders
                                ? (id == '4998' ? 84 : 0)
                                : null,
                            fetchedAt: DateTime.now().toUtc(),
                          ),
                      },
                  onUse: (_) {},
                ),
              ),
              gatheringTheme: true,
            ),
          );
          await tester.pumpAndSettle();
          await tester.enterText(k('spot-search'), 'Tshira');
          await tester.pumpAndSettle();
          for (final mode in ['value', 'demand']) {
            await tester.tap(k('spot-filter-compact-control'));
            await tester.pumpAndSettle();
            final rank = k(
              mode == 'value' ? 'spot-ranking-profit' : 'spot-ranking-demand',
            );
            await tester.ensureVisible(rank);
            await tester.tap(rank);
            await tester.pumpAndSettle();
            await tester.tap(k('spot-filter-compact-control'));
            await tester.pumpAndSettle();
            final card = k('spot-route-48');
            final row = find.descendant(
              of: card,
              matching: k('$mode-contribution-row-4998'),
            );
            expect(
              find.descendant(
                of: row,
                matching: find.byType(SourceAvailabilityBadges),
              ),
              findsOneWidget,
            );
            expect(
              find.descendant(of: row, matching: stockBadgeText('0')),
              findsOneWidget,
            );
            expect(
              find.descendant(of: row, matching: find.text('Orders 84')),
              findsOneWidget,
            );
            expect(
              find.descendant(
                of: row,
                matching: find.byType(OpportunitySilverAmount),
              ),
              findsOneWidget,
            );
            expect(
              find.descendant(of: row, matching: find.byType(FittedBox)),
              findsNothing,
            );
            await capture(tester, 'gathering-$mode-${spec.id}-$scale');
            final info = k('$mode-calculation-info-48');
            await tester.ensureVisible(info);
            await tester.tap(info);
            // The real detail action precaches all loot artwork before opening.
            // Let its asset I/O finish outside the fake clock before settling.
            for (
              var i = 0;
              i < 100 && k('market-calculation-dialog').evaluate().isEmpty;
              i++
            ) {
              await tester.runAsync(
                () => Future<void>.delayed(const Duration(milliseconds: 10)),
              );
              await tester.pump(const Duration(milliseconds: 20));
            }
            expect(k('market-calculation-dialog'), findsOneWidget);
            await precacheVisible(tester);
            await tester.pumpAndSettle();
            final detail = k('calculation-income-4998');
            expect(
              find.descendant(
                of: detail,
                matching: find.byType(SourceAvailabilityBadges),
              ),
              findsOneWidget,
            );
            expect(
              find.descendant(of: detail, matching: find.text('Orders 84')),
              findsOneWidget,
            );
            expect(
              find.descendant(
                of: detail,
                matching: find.byType(SharedSilverAmount),
              ),
              findsOneWidget,
            );
            await capture(tester, 'gathering-$mode-details-${spec.id}-$scale');
            await tester.sendKeyEvent(LogicalKeyboardKey.escape);
            await tester.pumpAndSettle();
          }
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox());
        },
      );
    }
  }
}

Widget host(
  ThemeSpec spec,
  double scale,
  Widget child, {
  bool gatheringTheme = false,
}) => RepaintBoundary(
  key: captureKey,
  child: MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: gatheringTheme
        ? companionTheme(visualPalette: gatheringPaletteForTheme(spec))
        : spec.materialTheme(),
    builder: (context, child) => ThemeSpecScope(
      spec: spec,
      child: MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
    ),
    home: Scaffold(backgroundColor: spec.palette.canvas, body: child),
  ),
);

Future<void> viewport(WidgetTester tester, Size size) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
}

Future<void> capture(WidgetTester tester, String name) async {
  final dir = Platform.environment['BSL_CONSISTENT_CAPTURE_DIR'];
  if (dir == null) return;
  await precacheVisible(tester);
  await tester.pumpAndSettle();
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(captureKey),
  );
  await tester.runAsync(() async {
    await Directory(dir).create(recursive: true);
    final image = await boundary.toImage(pixelRatio: 1);
    try {
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      await File('$dir/$name.png').writeAsBytes(bytes!.buffer.asUint8List());
    } finally {
      image.dispose();
    }
  });
}

Future<void> precacheVisible(WidgetTester tester) async {
  await tester.pump();
  await tester.runAsync(() async {
    await Future.wait([
      for (final element in find.byType(Image).evaluate())
        precacheImage((element.widget as Image).image, element),
    ]);
  });
}
