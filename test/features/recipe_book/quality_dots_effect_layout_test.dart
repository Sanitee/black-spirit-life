import 'dart:convert';
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
import 'package:bdo_craft_planner_flutter/features/recipe_book/recipe_book_exact_buff_info.dart';
import 'package:bdo_craft_planner_flutter/features/recipe_book/recipe_book_exact_food_info.dart';
import 'package:bdo_craft_planner_flutter/features/recipe_book/recipe_book_item_info.dart';
import 'package:bdo_craft_planner_flutter/visual/visual.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/choice_market_transport.dart';
import '../planner/planner_choice_market_test.dart' show settle;
import '../planner/planner_review_projection_test.dart' as fixture;

final proposed = true;
const captureDir = 'build/consistent-quality-dots';
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

  for (final kind in ['recipe', 'effects', 'short', 'narrow', 'large']) {
    final buffName = kind == 'short' ? 'Adaptation Draught' : 'Harmony Draught';
    final width = kind == 'recipe'
        ? 745.0
        : kind == 'narrow'
        ? 495.0
        : 745.0;
    final textScale = kind == 'large' ? 2.0 : 1.0;
    testWidgets('$kind ${proposed ? 'suggested' : 'current'}', (tester) async {
      final catalog = const BundledCatalogParser().parse(
        File('assets/data/app-data.json').readAsStringSync(),
      );
      final repo = CatalogRepository.cached(catalog);
      final app = fixture.controller(catalog, CraftMode.cooking, 'Beer', 1);
      final book = RecipeBookController(
        modeController: app.active,
        catalogRepository: repo,
        callingContext: RecipeBookCallingContext.planner,
        allowedTargets: const [],
      );
      addTearDown(book.dispose);
      addTearDown(app.dispose);
      final values = <String, (double, int, int)>{
        'Elixir of Life': (0, 10600, 2000),
        'Defense Elixir': (0, 2400, 2500),
        'Elixir of Endurance': (0, 16500, 0),
        'Helix Elixir': (0, 0, 13500),
        'Spellbound Catalyst': (260, 0, 0),
        'Elixir of Strong Life': (36, 7800, 180),
        'Elixir of Steel Defense': (12, 0, 1200),
      };
      app.modes[CraftMode.alchemy]!.updateState(
        (s) => s.copyWith(
          inventory: {for (final e in values.entries) e.key: e.value.$1},
        ),
        immediate: true,
      );
      final transport = ChoiceMarketTransport();
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
      final spec = SakuraNightGardenSpec.theme;
      final actual = book.itemInfoFor(
        'Adaptation Draught',
        mode: CraftMode.alchemy,
      )!;
      final formula = actual.acquisitionFormulas.firstWhere(
        (f) => f.batchMultiplier == 10,
      );
      final info = kind == 'recipe'
          ? actual.copyWith(
              summary: '',
              effects: [],
              notes: [],
              acquisitionNotes: [],
              uses: [],
              craftUses: [],
              acquisitionFormulas: [formula],
            )
          : actual.copyWith(
              summary: '',
              effects: [],
              notes: [],
              acquisitionNotes: [],
              uses: [],
              acquisitionFormulas: [],
              craftUses: [RecipeBookCraftUse(output: buffName)],
            );
      const size = Size(1200, 1400);
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        RepaintBoundary(
          key: const ValueKey('root'),
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
                    textScaler: TextScaler.linear(textScale),
                  ),
                  child: Scaffold(
                    backgroundColor: spec.palette.canvas,
                    body: Center(
                      child: SizedBox(
                        width: width,
                        child: ItemReferenceCard(
                          controller: book,
                          mode: CraftMode.alchemy,
                          name: 'Adaptation Draught',
                          info: info,
                          maxWidth: width,
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
      );
      await tester.pumpAndSettle();
      if (kind != 'recipe') {
        await tester.tap(find.text('Used for'));
      }
      await settle(tester, broker);
      await tester.pumpAndSettle();
      final target = kind == 'recipe'
          ? find.byKey(
              RecipeBookKeys.itemInfoFormula(
                formula.outputName,
                formula.variantId,
                formula.batchMultiplier,
              ),
            )
          : find.byType(ItemReferenceCard);
      expect(target, findsOneWidget);
      if (kind == 'recipe') {
        expect(
          find.text('Simple Alchemy'),
          proposed ? findsOneWidget : findsNWidgets(2),
        );
        final table = tester.widget<RecipeIngredientTable>(
          find.byType(RecipeIngredientTable),
        );
        expect(table.rows.map((r) => r.quantity), [30, 30, 30, 30, 10]);
        expect(table.rows.last.owned, 260);
        final geometry = tester.widget<Table>(
          find
              .descendant(
                of: find.byType(RecipeIngredientTable),
                matching: find.byType(Table),
              )
              .first,
        );
        for (final row in geometry.children.skip(1)) {
          final ingredient = tester.getRect(find.byWidget(row.children[0]));
          final npc = tester.getRect(find.byWidget(row.children[2]));
          expect(npc.left - ingredient.right, greaterThanOrEqualTo(31.9));
        }
        if (proposed) {
          final heading = find.byKey(
            const ValueKey('formula-heading:Adaptation Draught:10'),
          );
          final quantity = find.descendant(
            of: heading,
            matching: find.text('×10'),
          );
          expect(quantity, findsOneWidget);
          expect(find.textContaining('× batch'), findsNothing);
          final headingRect = tester.getRect(heading);
          final quantityRect = tester.getRect(quantity);
          final methodRect = tester.getRect(find.text('Simple Alchemy'));
          expect(
            quantityRect.left - headingRect.left,
            inInclusiveRange(30, 36),
          );
          expect(methodRect.left - quantityRect.right, closeTo(18, .1));
          for (final ingredient in ['Elixir of Life', 'Defense Elixir']) {
            final button = find.byKey(
              ValueKey('recipe-grade:Adaptation Draught:$ingredient:blue'),
            );
            expect(button, findsOneWidget);
            await tester.tap(button);
            await settle(tester, broker);
            await tester.pumpAndSettle();
          }
          final updated = tester.widget<RecipeIngredientTable>(
            find.byType(RecipeIngredientTable),
          );
          expect(updated.rows.map((r) => r.name), [
            'Elixir of Strong Life',
            'Elixir of Steel Defense',
            'Elixir of Endurance',
            'Helix Elixir',
            'Spellbound Catalyst',
          ]);
          expect(updated.rows.map((r) => r.quantity), [10, 10, 30, 30, 10]);
          expect(updated.rows.take(2).map((r) => r.owned), [36, 12]);
          expect(
            book
                .referenceFormulaForActivation(formula)
                .ingredientChoiceNames
                .values,
            contains('Elixir of Strong Life'),
          );
        }
      } else {
        final effects = book
            .itemInfoFor(buffName, mode: CraftMode.alchemy)!
            .effects;
        expect(effects.length, kind == 'short' ? 4 : 13);
        if (proposed) {
          expect(find.text('Effects'), findsOneWidget);
          for (final effect in effects) {
            expect(find.text(effect), findsOneWidget);
          }
          if (kind == 'effects') {
            final title = tester.getRect(find.text(buffName).last);
            final bottom = effects
                .map((effect) => tester.getRect(find.text(effect)).bottom)
                .reduce((a, b) => a > b ? a : b);
            expect(bottom - title.top, lessThan(300));
          }
          expect(
            find.byKey(const ValueKey('effect-columns')),
            kind == 'effects' ? findsOneWidget : findsNothing,
          );
          expect(find.text('A temporary draught buff.'), findsNothing);
        } else {
          for (final effect in effects) {
            expect(find.text(effect), findsOneWidget);
          }
        }
      }
      expect(tester.takeException(), isNull);
      await tester.runAsync(() async {
        for (final image
            in tester.widgetList<Image>(find.byType(Image)).take(12)) {
          await precacheImage(
            image.image,
            tester.element(target),
          ).timeout(const Duration(seconds: 3));
        }
      });
      await tester.pumpAndSettle();
      final boundary = tester.renderObject<RenderRepaintBoundary>(
        find.byKey(const ValueKey('root')),
      );
      var rect = tester.getRect(target).intersect(Offset.zero & size);
      if (kind != 'recipe') {
        final title = tester.getRect(find.text(buffName).last);
        final effects = book
            .itemInfoFor(buffName, mode: CraftMode.alchemy)!
            .effects;
        final bottom = effects
            .map((value) => tester.getRect(find.text(value)).bottom)
            .reduce((a, b) => a > b ? a : b);
        rect = Rect.fromLTRB(
          rect.left + 1,
          title.top - 12,
          rect.right - 1,
          (bottom + 16).clamp(0, size.height),
        );
      }
      await tester.runAsync(() async {
        final image = await (boundary.debugLayer! as OffsetLayer).toImage(
          rect,
          pixelRatio: 1.5,
        );
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        Directory(captureDir).createSync(recursive: true);
        File(
          '$captureDir/$kind-${proposed ? 'suggested' : 'current'}.png',
        ).writeAsBytesSync(bytes!.buffer.asUint8List());
        image.dispose();
        File(
          '$captureDir/$kind-${proposed ? 'suggested' : 'current'}.txt',
        ).writeAsStringSync('${rect.width} x ${rect.height}\n');
      });
      await tester.pumpWidget(const SizedBox.shrink());
      book.connectAvailabilityMarket(null);
      await tester.pumpAndSettle();
    });
  }
  test('audit all bundled item effect lists', () {
    final catalog = const BundledCatalogParser().parse(
      File('assets/data/app-data.json').readAsStringSync(),
    );
    final app = fixture.controller(catalog, CraftMode.cooking, 'Beer', 1);
    final repo = CatalogRepository.cached(catalog);
    final book = RecipeBookController(
      modeController: app.active,
      catalogRepository: repo,
      callingContext: RecipeBookCallingContext.planner,
      allowedTargets: const [],
    );
    final names = <String>{
      for (final mode in CraftMode.values) ...catalog.forMode(mode).items.keys,
      for (final value in exactBuffInfoByName.values) value.title,
      for (final value in exactFoodInfoByName.values) value.title,
    }.toList()..sort();
    final rows = <Map<String, Object?>>[];
    final histogram = <String, int>{};
    for (final name in names) {
      final info = book.itemInfoFor(name);
      if (info == null || info.effects.isEmpty) continue;
      final effects = info.effects.where((s) => s.trim().isNotEmpty).toList();
      final count = effects.length;
      histogram['$count'] = (histogram['$count'] ?? 0) + 1;
      rows.add({
        'name': name,
        'count': count,
        'heading': info.effectsTitle,
        'effects': effects,
        'eligibleForColumns':
            count >= 8 &&
            info.effectsTitle == 'Effects' &&
            effects.every((e) => !e.contains('\n')),
      });
    }
    Directory(captureDir).createSync(recursive: true);
    File('$captureDir/buff-list-audit.json').writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert({
        'namesInspected': names.length,
        'effectLists': rows.length,
        'histogram': histogram,
        'columnCandidates': rows
            .where((r) => r['eligibleForColumns'] == true)
            .length,
        'records': rows,
        'scope':
            'All catalogued names plus exact buff and food registries, projected through actual itemInfoFor. Layout review, not a new gameplay fact audit.',
      }),
    );
    debugPrint(
      'Effect layout audit: ${names.length} names, ${rows.length} lists, ${rows.where((r) => r["eligibleForColumns"] == true).length} column candidates.',
    );
    book.dispose();
    app.dispose();
  });
  if (proposed) {
    testWidgets('all long effect lists fit wide narrow and large text', (
      tester,
    ) async {
      final audit =
          jsonDecode(
                File('$captureDir/buff-list-audit.json').readAsStringSync(),
              )
              as Map;
      final records = (audit['records'] as List)
          .cast<Map>()
          .where((r) => r['eligibleForColumns'] == true)
          .toList();
      expect(records.length, 15);
      final catalog = const BundledCatalogParser().parse(
        File('assets/data/app-data.json').readAsStringSync(),
      );
      final app = fixture.controller(catalog, CraftMode.cooking, 'Beer', 1);
      final book = RecipeBookController(
        modeController: app.active,
        catalogRepository: CatalogRepository.cached(catalog),
        callingContext: RecipeBookCallingContext.planner,
        allowedTargets: const [],
      );
      addTearDown(book.dispose);
      addTearDown(app.dispose);
      const viewport = Size(1300, 1800);
      tester.view.physicalSize = viewport;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var checked = 0;
      for (final spec in RetainedThemeRegistry.themes) {
        for (final record in records) {
          final name = record['name'] as String;
          final info = book
              .itemInfoFor(name)!
              .copyWith(
                summary: '',
                notes: [],
                acquisitionNotes: [],
                uses: [],
                craftUses: [],
                acquisitionFormulas: [],
              );
          for (final size in [(745.0, 1.0), (495.0, 1.0), (745.0, 2.0)]) {
            await tester.pumpWidget(
              MaterialApp(
                theme: spec.materialTheme(),
                home: ThemeSpecScope(
                  spec: spec,
                  child: MediaQuery(
                    data: MediaQueryData(
                      size: viewport,
                      textScaler: TextScaler.linear(size.$2),
                    ),
                    child: Scaffold(
                      body: Center(
                        child: SizedBox(
                          width: size.$1,
                          child: ItemReferenceCard(
                            key: ValueKey('$name:$size'),
                            controller: book,
                            mode: CraftMode.alchemy,
                            name: name,
                            info: info,
                            maxWidth: size.$1,
                            spec: spec,
                            onClose: () {},
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
            await tester.pumpAndSettle();
            for (final effect in info.effects) {
              expect(
                find.text(effect),
                findsOneWidget,
                reason: '$name $size: $effect',
              );
            }
            if (size != (745.0, 1.0)) {
              expect(
                find.byKey(const ValueKey('effect-columns')),
                findsNothing,
              );
            }
            expect(tester.takeException(), isNull, reason: '$name $size');
            checked++;
          }
        }
      }
      await tester.pumpWidget(const SizedBox.shrink());
      debugPrint('Long-list layout combinations checked: $checked');
    });
  }
}
