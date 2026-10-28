import 'dart:io';
import 'dart:ui' as ui;

import 'package:bdo_craft_planner_flutter/app/app.dart';
import 'package:bdo_craft_planner_flutter/domain/models/craft_mode.dart';
import 'package:bdo_craft_planner_flutter/domain/state/state_copy.dart';
import 'package:bdo_craft_planner_flutter/features/planner/planner.dart';
import 'package:bdo_craft_planner_flutter/features/recipe_book/recipe_book.dart';
import 'package:bdo_craft_planner_flutter/visual/visual.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/application_test_harness.dart';

const _captureDirectory = String.fromEnvironment(
  'VISUAL_BBB_CAPTURE_DIRECTORY',
);
const _root = ValueKey('visual-bbb-root');

void main() {
  if (_captureDirectory.isNotEmpty) setUpAll(_fonts);
  for (final spec in [
    SakuraNightGardenSpec.theme,
    StandardSpec.theme,
    IlluminatedLedgerSpec.theme,
  ]) {
    for (final scale in [1.0, 1.5]) {
      testWidgets(
        'A3 recipe cards and 2B 3B real-catalog actions ${spec.id} scale $scale',
        (tester) async {
          configureApplicationTestSurface(
            tester,
            const Size(1500, 940),
            textScaleFactor: scale,
          );
          final original = (await tester.runAsync(
            () => ApplicationTestHarness.create(
              backgroundId: spec.isStandard ? 'greenhouse' : spec.id,
              activeMode: CraftMode.alchemy,
            ),
          ))!;
          final harness = original.rebindControllerInCurrentZone();
          await tester.runAsync(original.disposeControllerOnly);
          final mode = harness.bundle.controller.active;
          mode.selectTarget('Perfume of Courage');
          mode.commitAmount('100');
          mode.updateState(
            (state) => state.copyWith(
              ignoreIngredientInventory: false,
              market: state.market.copyWith(
                prices: const {
                  'Great Ocean Oil': 23300000,
                  'Trace of Nature': 266000,
                  'Weeds': 9350,
                  'Purified Water': 5000,
                },
                stock: const {
                  'Great Ocean Oil': 0,
                  'Trace of Nature': 162452,
                  'Weeds': 0,
                  'Purified Water': 12000,
                },
                fetchedAt: DateTime.utc(2026, 9, 26, 12).millisecondsSinceEpoch,
              ),
            ),
            immediate: true,
          );
          mode.setPricesVisible(true);
          try {
            await tester.pumpWidget(
              RepaintBoundary(
                key: _root,
                child: BdoCraftPlannerApp(
                  enableOpportunityAutoCheck: false,
                  applicationFuture: Future.value(harness.bundle),
                  marketGateway: const EmptyMarketGateway(),
                ),
              ),
            );
            await _settle(tester);
            expect(tester.takeException(), isNull);
            final missing = find.byKey(
              const ValueKey('planner-need-quantity:Trace of Nature:Missing'),
            );
            final need = find.byKey(
              const ValueKey('planner-need-quantity:Trace of Nature:Need'),
            );
            expect(missing, findsOneWidget);
            expect(tester.widget<Text>(missing).style!.fontSize, 24);
            expect(
              tester.getTopLeft(missing).dy,
              lessThan(tester.getTopLeft(need).dy),
            );
            expect(
              tester.widget<Text>(missing).style!.color,
              spec.palette.text,
            );
            if (scale == 1) await _capture(tester, '2b-need-first-${spec.id}');

            final salt = find.byKey(PlannerActionKeys.row('P17', 'Salt'));
            await tester.scrollUntilVisible(
              salt,
              140,
              scrollable: find
                  .descendant(
                    of: find.byKey(
                      const PageStorageKey<String>('planner-need-first'),
                    ),
                    matching: find.byType(Scrollable),
                  )
                  .first,
            );
            await Scrollable.ensureVisible(tester.element(salt), alignment: .4);
            await tester.pumpAndSettle();
            await tester.tap(salt);
            await _settle(tester);
            final body = find.byKey(const ValueKey('planner-source-info-body'));
            final card = find.byKey(const ValueKey('planner-source-info-card'));
            expect(body, findsOneWidget);
            expect(
              tester.getTopLeft(body).dx - tester.getTopLeft(card).dx,
              greaterThan(60),
            );
            expect(tester.takeException(), isNull);
            if (scale == 1) await _capture(tester, '3b-source-help-${spec.id}');
            await tester.tap(
              find.byKey(const ValueKey('planner-source-info-close')),
            );
            await tester.pumpAndSettle();
            expect(body, findsNothing);

            await tester.tap(find.byKey(PlannerActionKeys.p03));
            await _settle(tester);
            if (scale == 1) {
              await _capture(tester, 'a3-recipe-book-all-${spec.id}');
            }
            await tester.enterText(
              find.descendant(
                of: find.byKey(RecipeBookKeys.r03Search),
                matching: find.byType(TextField),
              ),
              'Perfume of Courage',
            );
            await _settle(tester);
            if (scale == 1) await _capture(tester, 'a3-recipe-book-${spec.id}');
            final recipe = find.byKey(
              RecipeBookKeys.card('Perfume of Courage'),
            );
            await tester.scrollUntilVisible(
              recipe,
              180,
              scrollable: find
                  .descendant(
                    of: find.byKey(RecipeBookKeys.r10CardScroll),
                    matching: find.byType(Scrollable),
                  )
                  .first,
            );
            await tester.pumpAndSettle();
            expect(recipe, findsOneWidget);
            final decoration =
                tester
                        .widget<DecoratedBox>(
                          find.byKey(
                            const ValueKey(
                              'recipe-soft-card:Perfume of Courage',
                            ),
                          ),
                        )
                        .decoration
                    as BoxDecoration;
            expect(decoration.border, isNull);
            expect(decoration.gradient, isA<LinearGradient>());
            expect(decoration.borderRadius, BorderRadius.circular(7));
            final icon = find.byKey(
              const ValueKey('recipe-card-icon:Perfume of Courage'),
            );
            expect(tester.getSize(icon), const Size(50, 50));
            expect(
              tester.getCenter(icon).dy,
              closeTo(tester.getCenter(recipe).dy, .5),
            );
            final method = find.byKey(
              RecipeBookKeys.productionMethod('Perfume of Courage'),
            );
            expect(tester.widget<Text>(method).style!.fontSize, 14);
            final target = find.byKey(
              RecipeBookKeys.r11Target('Perfume of Courage'),
            );
            expect(tester.widget<AppTextAction>(target).fontSize, 14);
            expect(
              tester.getRect(target).top - tester.getRect(method).bottom,
              closeTo(18, .5),
            );
            expect(
              tester.widget(
                find.byKey(RecipeBookKeys.r11Target('Perfume of Courage')),
              ),
              isA<AppTextAction>(),
            );
            expect(tester.takeException(), isNull);
            await tester.tap(
              find.byKey(RecipeBookKeys.r12Favorite('Perfume of Courage')),
            );
            await tester.pumpAndSettle();
            expect(
              mode.state.value.favoriteRecipes,
              contains('Perfume of Courage'),
            );
            await tester.tap(
              find.byKey(RecipeBookKeys.r13Details('Perfume of Courage')),
            );
            await tester.pumpAndSettle();
            expect(find.byKey(RecipeBookKeys.previewPanel), findsOneWidget);
            await tester.sendKeyEvent(LogicalKeyboardKey.escape);
            await tester.pumpAndSettle();
            await tester.tap(
              find.byKey(RecipeBookKeys.r11Target('Perfume of Courage')),
            );
            await tester.pumpAndSettle();
            expect(find.byKey(RecipeBookKeys.modal), findsNothing);
            expect(mode.state.value.target, 'Perfume of Courage');
            expect(tester.takeException(), isNull);
          } finally {
            await tester.pumpWidget(const SizedBox.shrink());
            await harness.disposeControllerOnly();
            await tester.runAsync(
              () => harness.temporaryDirectory.delete(recursive: true),
            );
          }
        },
      );
    }
  }
}

Future<void> _settle(WidgetTester tester) async {
  await tester.pumpAndSettle();
  for (final element in find.byType(Image).evaluate()) {
    await tester.runAsync(
      () => precacheImage((element.widget as Image).image, element),
    );
  }
  await tester.pumpAndSettle();
}

Future<void> _capture(WidgetTester tester, String name) async {
  if (_captureDirectory.isEmpty) return;
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(_root),
  );
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 1);
    try {
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      final file = File('$_captureDirectory/$name.png');
      await file.parent.create(recursive: true);
      await file.writeAsBytes(bytes!.buffer.asUint8List());
    } finally {
      image.dispose();
    }
  });
}

Future<void> _fonts() async {
  var sdk = File(Platform.resolvedExecutable).parent;
  while (!File(
    '${sdk.path}/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
  ).existsSync()) {
    if (sdk.parent.path == sdk.path) {
      throw StateError('Flutter icon font not found');
    }
    sdk = sdk.parent;
  }
  final icons = FontLoader('MaterialIcons')
    ..addFont(
      File(
        '${sdk.path}/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
      ).readAsBytes().then(ByteData.sublistView),
    );
  await icons.load();
  for (final entry in {
    'Segoe UI': ['segoeui.ttf', 'seguisb.ttf', 'segoeuib.ttf'],
    'Georgia': ['georgia.ttf', 'georgiab.ttf', 'georgiai.ttf'],
  }.entries) {
    final loader = FontLoader(entry.key);
    for (final font in entry.value) {
      loader.addFont(
        File(
          '${Platform.environment['WINDIR'] ?? r'C:\Windows'}/Fonts/$font',
        ).readAsBytes().then(ByteData.sublistView),
      );
    }
    await loader.load();
  }
}
