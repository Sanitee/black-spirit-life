import 'dart:io';
import 'dart:ui' as ui;
import 'package:bdo_craft_planner_flutter/data/catalog/bundled_catalog_parser.dart';
import 'package:bdo_craft_planner_flutter/data/catalog/catalog_repository.dart';
import 'package:bdo_craft_planner_flutter/data/market/shared_market_repository.dart';
import 'package:bdo_craft_planner_flutter/domain/models/craft_mode.dart';
import 'package:bdo_craft_planner_flutter/domain/state/state_copy.dart';
import 'package:bdo_craft_planner_flutter/features/planner/planner_choice_market.dart';
import 'package:bdo_craft_planner_flutter/features/planner/planner_contracts.dart';
import 'package:bdo_craft_planner_flutter/features/recipe_book/recipe_book.dart';
import 'package:bdo_craft_planner_flutter/features/shared/inventory_count_badge.dart';
import 'package:bdo_craft_planner_flutter/visual/visual.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import '../../support/choice_market_transport.dart';
import '../planner/planner_choice_market_test.dart' show settle;
import '../planner/planner_review_projection_test.dart' as fixture;

const audit = String.fromEnvironment(
  'captureDirectory',
  defaultValue: 'build/compact-reference-captures',
);
const baseline = bool.fromEnvironment('baseline');
void main() {
  setUpAll(() async {
    for (final e in {
      'Segoe UI': [
        'C:/Windows/Fonts/segoeui.ttf',
        'C:/Windows/Fonts/seguisb.ttf',
      ],
      'Georgia': [
        'C:/Windows/Fonts/georgia.ttf',
        'C:/Windows/Fonts/georgiab.ttf',
      ],
      'MaterialIcons': [
        'D:/Tools/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
      ],
    }.entries) {
      final loader = FontLoader(e.key);
      for (final f in e.value) {
        loader.addFont(File(f).readAsBytes().then(ByteData.sublistView));
      }
      await loader.load();
    }
  });

  for (final spec in RetainedThemeRegistry.themes) {
    for (final (scale, viewport) in [
      (1.0, 1440.0),
      (2.0, 1700.0),
      (2.0, 720.0),
    ]) {
      testWidgets('Compact reference ${spec.id} $scale $viewport', (
        tester,
      ) async {
        final catalog = const BundledCatalogParser().parse(
          File('assets/data/app-data.json').readAsStringSync(),
        );
        final repo = CatalogRepository.cached(catalog);
        final app = fixture.controller(catalog, CraftMode.cooking, 'Beer', 1);
        final book = RecipeBookController(
          modeController: app.active,
          catalogRepository: repo,
          callingContext: RecipeBookCallingContext.planner,
          allowedTargets: ['Purified Lightstone of Fire'],
        );
        addTearDown(book.dispose);
        addTearDown(app.dispose);
        final transport = ChoiceMarketTransport();
        final values = <String, (double, int, int)>{
          'Imperfect Lightstone of Fire': (0, 1300, 0),
          'Black Gem Fragment': (0, 18700, 0),
          'Black Stone': (0, 650100, 0),
          'Powder of Flame': (124800, 62600, 10000),
          'Clear Liquid Reagent': (45400, 138600, 0),
        };
        app.active.updateState(
          (s) => s.copyWith(
            inventory: {for (final e in values.entries) e.key: e.value.$1},
          ),
          immediate: true,
        );
        for (final e in values.entries) {
          final id = repo.bundledMarketId(e.key);
          if (id != null) {
            transport.values[id] = (
              price: 480,
              stock: e.value.$2,
              preorders: e.value.$3,
            );
          }
        }
        final broker = SharedMarketRepository(
          transport: transport,
          requestSpacing: Duration.zero,
        );
        addTearDown(broker.dispose);
        final size = Size(viewport, scale == 1 ? 1080 : 1500);
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final full = book.itemInfoFor(
          'Magical Lightstone Crystal',
          mode: CraftMode.alchemy,
        )!;
        final info = spec == RetainedThemeRegistry.themes.first && scale == 1
            ? full
            : full.copyWith(
                craftUses: [full.craftUses.first, full.craftUses.last],
              );
        await tester.pumpWidget(
          RepaintBoundary(
            key: const ValueKey('capture-root'),
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: spec.materialTheme(),
              home: ThemeSpecScope(
                spec: spec,
                child: PlannerChoiceMarketScope(
                  repository: broker,
                  child: MediaQuery(
                    data: MediaQueryData(
                      size: size,
                      textScaler: TextScaler.linear(scale),
                    ),
                    child: Scaffold(
                      key: const ValueKey('capture'),
                      backgroundColor: spec.palette.canvas,
                      body: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Align(
                          alignment: Alignment.topCenter,
                          child: RepaintBoundary(
                            key: const ValueKey('card-capture'),
                            child: ItemReferenceCard(
                              controller: book,
                              mode: CraftMode.alchemy,
                              name: info.title,
                              info: info,
                              maxWidth: size.width - 48,
                              spec: spec,
                              onClose: () {},
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
        await tester.pumpAndSettle(
          const Duration(milliseconds: 100),
          EnginePhase.sendSemanticsUpdate,
          const Duration(seconds: 10),
        );
        await tester.tap(find.text('Used for'));
        await settle(tester, broker);
        await tester.pumpAndSettle();
        final card = tester.getRect(find.byKey(const ValueKey('card-capture')));
        final tables = find.byType(RecipeIngredientTable);
        final firstTable = tables.first;
        if (!baseline) {
          // Fit one complete formula plus the initial information, not the
          // total list or a long effect description on an output further down.
          final formulas = find.byWidgetPredicate(
            (w) =>
                w.key is ValueKey<String> &&
                (w.key as ValueKey<String>).value.startsWith(
                  'recipe-book-item-info-formula:',
                ),
          );
          final first = tester.getRect(formulas.first);
          final tallest = formulas
              .evaluate()
              .map((e) => tester.getSize(find.byWidget(e.widget)).height)
              .reduce((a, b) => a > b ? a : b);
          final wanted = first.top - card.top + tallest + 1;
          expect(card.height, closeTo(wanted.clamp(0, size.height - 48), 1.5));
          expect(card.width, lessThanOrEqualTo(size.width - 48));
          if (scale == 1) {
            expect(card.height, lessThan(760));
            expect(card.width, lessThan(840));
          }
          checkTable(tester, firstTable, scale);
          final label = find.byKey(
            RecipeBookKeys.itemInfoMaterial(
              'Purified Lightstone of Fire',
              null,
              'Black Gem Fragment',
            ),
          );
          final quantity = find.descendant(
            of: label,
            matching: find.text('×10'),
          );
          final swap = find.byKey(
            const ValueKey(
              'recipe-substitutes:Purified Lightstone of Fire:Black Gem Fragment',
            ),
          );
          final gap =
              tester.getRect(swap).left - tester.getRect(quantity).right;
          expect(gap, inInclusiveRange(0, 16));
        }
        expect(tester.takeException(), isNull);
        await capture(
          tester,
          '${spec.id}-$scale-$viewport-${baseline ? 'before' : 'after'}',
          key: 'card-capture',
        );
        if (!baseline) {
          final scroll = tester.widget<SingleChildScrollView>(
            find.byKey(const ValueKey('attached-reference-scroll')),
          );
          expect(scroll.controller!.position.maxScrollExtent, greaterThan(0));
          scroll.controller!.jumpTo(
            scroll.controller!.position.maxScrollExtent,
          );
          await tester.pumpAndSettle();
          final actions = find.text('Use recipe');
          expect(
            tester.getRect(actions.last).bottom,
            lessThanOrEqualTo(card.bottom),
          );
          scroll.controller!.jumpTo(0);
          await tester.pumpAndSettle();
          final swap = find.byKey(
            const ValueKey(
              'recipe-substitutes:Purified Lightstone of Fire:Black Gem Fragment',
            ),
          );
          await tester.ensureVisible(swap);
          await tester.tap(swap);
          await settle(tester, broker);
          await tester.pumpAndSettle();
          final chooser = find.byWidgetPredicate(
            (w) => w is RecipeIngredientTable && w.onChoose != null,
          );
          expect(chooser, findsOneWidget);
          checkTable(tester, chooser, scale);
          await tester.sendKeyEvent(LogicalKeyboardKey.escape);
          await tester.pumpAndSettle();
          expect(chooser, findsNothing);
          expect(tester.takeException(), isNull);
        }
        await tester.pumpWidget(const SizedBox.shrink());
        book.connectAvailabilityMarket(null);
        await tester.pumpAndSettle();
      });
    }
  }
}

Future<void> capture(
  WidgetTester tester,
  String name, {
  String key = 'capture-root',
}) async {
  final bounds = tester.getRect(find.byKey(ValueKey(key)));
  final images = tester
      .widgetList<Image>(find.byType(Image))
      .take(18)
      .where((w) => tester.getRect(find.byWidget(w)).overlaps(bounds))
      .toList();
  await tester.runAsync(() async {
    for (final image in images) {
      await precacheImage(
        image.image,
        tester.element(find.byKey(const ValueKey('capture'))),
      ).timeout(const Duration(seconds: 3));
    }
  });
  await tester.pumpAndSettle();
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(ValueKey(key)),
  );
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 1.5);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    Directory(audit).createSync(recursive: true);
    File('$audit/$name.png').writeAsBytesSync(bytes!.buffer.asUint8List());
    image.dispose();
  });
}

void checkTable(WidgetTester tester, Finder host, double scale) {
  final table = tester.widget<Table>(
    find.descendant(of: host, matching: find.byType(Table)).first,
  );
  for (final row in table.children.skip(1).take(6)) {
    Rect rect(int i) => tester.getRect(find.byWidget(row.children[i]));
    expect(rect(2).left - rect(0).right, greaterThanOrEqualTo(32 * scale - .1));
    expect(rect(4).left - rect(2).right, greaterThanOrEqualTo(14 * scale - .1));
    expect(rect(0).center.dy, closeTo(rect(2).center.dy, .1));
    final badge = find.descendant(
      of: find.byWidget(row.children[2]),
      matching: find.byType(InventoryCountBadge),
    );
    expect(tester.getCenter(badge).dx, closeTo(rect(2).center.dx, .1));
  }
}
