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
import 'package:bdo_craft_planner_flutter/visual/visual.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import '../../support/choice_market_transport.dart';
import '../planner/planner_choice_market_test.dart' show settle;
import '../planner/planner_review_projection_test.dart' as fixture;
import 'recipe_book_availability_test.dart'
    show checkColumnAlignment, checkBadgeLines;

const proposed = true;
const audit = 'build/consistent-substitute-captures';

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
    for (final scale in [1.0, 2.0]) {
      testWidgets('Reference substitutes ${spec.id} scale $scale', (
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
          allowedTargets: ['Oatmeal'],
        );
        addTearDown(book.dispose);
        addTearDown(app.dispose);
        final values = <String, (double, int, int)>{
          'Wheat Flour': (1, 44, 9000),
          'Barley Flour': (20000, 862, 14000),
          'Potato Flour': (15000, 15400, 10900),
          'Corn Flour': (1, 1400, 11100),
          'Sweet Potato Flour': (1, 0, 14700),
          'Milk': (618400, 100, 89200),
          'Cooking Honey': (839900, 35400, 0),
          'Onion': (0, 0, 115800),
          'High-Quality Onion': (0, 1400, 5700),
          'Special Onion': (139900, 81100, 2200),
        };
        app.active.updateState(
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
        final info = book.itemInfoFor('Cooking Honey')!;
        final use = info.craftUses.singleWhere((u) => u.output == 'Oatmeal');
        final focused = info.copyWith(craftUses: [use], uses: []);
        final beforeSelection = app.active.state.value;
        final size = Size(scale == 1 ? 1200 : 1700, scale == 1 ? 1120 : 1600);
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
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
                              mode: CraftMode.cooking,
                              name: 'Cooking Honey',
                              info: focused,
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
        await tester.pumpAndSettle();
        await tester.tap(find.text('Used for'));
        await settle(tester, broker);
        await tester.pumpAndSettle();
        final tables = find.byType(RecipeIngredientTable);
        expect(tables, findsOneWidget);
        final table = tester.widget<RecipeIngredientTable>(tables);
        expect(table.rows.length, proposed ? 4 : 10);
        checkColumnAlignment(tester);
        checkBadgeLines(tester);
        expect(tester.takeException(), isNull);
        if (scale == 1) {
          await capture(tester, '${spec.id}-default', key: 'card-capture');
        }
        if (proposed) {
          for (final ingredient in ['Wheat Flour', 'Onion']) {
            final button = find.byKey(
              ValueKey('recipe-substitutes:Oatmeal:$ingredient'),
            );
            expect(button, findsOneWidget);
            await tester.ensureVisible(button);
            await tester.tap(button);
            await settle(tester, broker);
            await tester.pumpAndSettle();
            final chooser = find.byWidgetPredicate(
              (w) => w is RecipeIngredientTable && w.onChoose != null,
            );
            expect(chooser, findsOneWidget);
            final choices = tester.widget<RecipeIngredientTable>(chooser);
            expect(choices.rows.length, ingredient == 'Onion' ? 3 : 5);
            checkColumnAlignment(tester);
            checkBadgeLines(tester);
            expect(tester.takeException(), isNull);
            if (scale == 1) {
              await capture(tester, '${spec.id}-$ingredient-popup');
            }
            final chosen = ingredient == 'Onion'
                ? 'Special Onion'
                : 'Barley Flour';
            await tester.tap(
              find.byKey(ValueKey('recipe-choose:Oatmeal:$chosen')),
            );
            await tester.pumpAndSettle();
            expect(chooser, findsNothing);
            final visible = tester.widget<RecipeIngredientTable>(tables).rows;
            expect(visible.any((row) => row.name == chosen), isTrue);
            expect(
              visible.firstWhere((row) => row.name == chosen).quantity,
              ingredient == 'Onion' ? 1 : 9,
            );
            expect(
              identical(app.active.state.value, beforeSelection),
              isTrue,
              reason:
                  'Inspecting/choosing a substitute must not edit saved Planner state.',
            );
          }
        }
        checkColumnAlignment(tester);
        checkBadgeLines(tester);
        if (scale == 1) {
          await capture(tester, '${spec.id}-chosen', key: 'card-capture');
        }
        await tester.tap(find.text('Use recipe'));
        await tester.pumpAndSettle();
        expect(app.active.state.value.target, 'Oatmeal');
        final committed = book.availabilityFor('Oatmeal').ingredients;
        expect(committed.map((row) => row.name), [
          'Barley Flour',
          'Milk',
          'Cooking Honey',
          'Special Onion',
        ]);
        expect(committed.map((row) => row.quantity), [9, 3, 2, 1]);
        expect(tester.takeException(), isNull);
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
  final images = tester.widgetList<Image>(find.byType(Image)).toList();
  await tester.runAsync(() async {
    for (final image in images) {
      await precacheImage(
        image.image,
        tester.element(find.byKey(const ValueKey('capture'))),
      );
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
