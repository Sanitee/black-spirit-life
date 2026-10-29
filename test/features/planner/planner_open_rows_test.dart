import 'dart:io';
import 'dart:ui' as ui;

import 'package:bdo_craft_planner_flutter/app/app.dart';
import 'package:bdo_craft_planner_flutter/domain/models/craft_mode.dart';
import 'package:bdo_craft_planner_flutter/domain/state/state_copy.dart';
import 'package:bdo_craft_planner_flutter/features/planner/planner.dart';
import 'package:bdo_craft_planner_flutter/features/planner/planner_quantity_layout.dart';
import 'package:bdo_craft_planner_flutter/features/shared/mode_item_icon.dart';
import 'package:bdo_craft_planner_flutter/visual/visual.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/application_test_harness.dart';

const _root = ValueKey('open-rows-render');
const _recipe = 'Chicken Breast Salad';

void main() {
  setUpAll(_loadFonts);
  for (final spec in [
    SakuraNightGardenSpec.theme,
    IlluminatedLedgerSpec.theme,
    StandardSpec.theme,
  ]) {
    for (final sizeAndScale in [
      (const Size(1500, 940), 1.0),
      (const Size(1200, 752), 1.0),
      (const Size(1200, 940), 2.0),
    ]) {
      final (size, scale) = sizeAndScale;
      testWidgets('open rows ${spec.id} $size text $scale', (tester) async {
        configureApplicationTestSurface(tester, size, textScaleFactor: scale);
        final original = (await tester.runAsync(
          () => ApplicationTestHarness.create(
            backgroundId: spec.isStandard ? 'greenhouse' : spec.id,
            activeMode: CraftMode.cooking,
          ),
        ))!;
        final harness = original.rebindControllerInCurrentZone();
        await tester.runAsync(original.disposeControllerOnly);
        final controller = harness.bundle.controller.active;
        expect(controller.selectTarget(_recipe), isTrue);
        controller.updateState(
          (state) => state.copyWith(
            want: 100,
            ignoreIngredientInventory: false,
            inventory: const {'Vinegar': 100},
          ),
          immediate: true,
        );
        final inventoryBefore = Map.of(controller.state.value.inventory);
        final quantitiesBefore = [
          for (final step in controller.plan.value.steps)
            for (final ingredient in step.ingredients) ingredient.need,
        ];
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
          await tester.pumpAndSettle();
          await tester.runAsync(() async {
            await Future.wait([
              for (final element in find.byType(Image).evaluate())
                precacheImage((element.widget as Image).image, element),
            ]);
          });
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          final bands = find.byWidgetPredicate((widget) {
            final key = widget.key;
            return key is ValueKey<String> &&
                key.value.startsWith('planner-ingredient-band:$_recipe:');
          });
          expect(bands, findsNWidgets(5));
          final card = find
              .ancestor(
                of: bands.first,
                matching: find.byWidgetPredicate(
                  (widget) =>
                      widget is AppSurface &&
                      widget.role == AppSurfaceRole.card,
                ),
              )
              .first;
          final cardBounds = tester.getRect(card);
          Rect? previous;
          final colors = <Color?>[];
          for (var i = 0; i < 5; i++) {
            final band = bands.at(i);
            final bounds = tester.getRect(band);
            // Every stripe reaches the same card edge without an inset box.
            expect(bounds.left - cardBounds.left, inInclusiveRange(0, 2));
            expect(cardBounds.right - bounds.right, inInclusiveRange(0, 2));
            if (previous != null) {
              expect(bounds.top, closeTo(previous.bottom, .01));
              expect(bounds.left, previous.left);
              expect(bounds.right, previous.right);
            }
            previous = bounds;
            final decoration =
                tester
                        .widget<DecoratedBox>(
                          find
                              .descendant(
                                of: band,
                                matching: find.byType(DecoratedBox),
                              )
                              .first,
                        )
                        .decoration
                    as BoxDecoration;
            colors.add(decoration.color);
            expect(decoration.border, isNull);
            expect(decoration.boxShadow, isNull);
            expect(
              find.descendant(
                of: band,
                matching: find.byType(PlannerQuantityBadge),
              ),
              findsNothing,
            );
            expect(
              find.descendant(of: band, matching: find.byType(ItemIconFrame)),
              findsNothing,
            );
            for (final icon in tester.widgetList<ModeItemIcon>(
              find.descendant(of: band, matching: find.byType(ModeItemIcon)),
            )) {
              expect(icon.showFrame, isFalse);
            }
          }
          expect(colors[0], colors[2]);
          expect(colors[1], colors[3]);
          expect(colors[0], isNot(colors[1]));
          expect(controller.state.value.inventory, inventoryBefore);
          expect([
            for (final step in controller.plan.value.steps)
              for (final ingredient in step.ingredients) ingredient.need,
          ], quantitiesBefore);
          await _capture(
            tester,
            card,
            '${spec.id}-${size.width.toInt()}-text${(scale * 100).round()}',
          );
          // Long cards remain scrollable: their final row must be reachable.
          await tester.ensureVisible(bands.last);
          await tester.pumpAndSettle();
          expect(
            tester.getRect(bands.last).bottom,
            lessThanOrEqualTo(size.height),
          );
          if (scale == 2) {
            await _capture(
              tester,
              card,
              '${spec.id}-${size.width.toInt()}-text200-scrolled',
            );
          }
          // Existing ingredient disclosure still collapses and reopens cleanly.
          final toggle = find.byKey(PlannerActionKeys.row('P09', _recipe));
          if (toggle.evaluate().isNotEmpty) {
            await tester.ensureVisible(toggle);
            await tester.pumpAndSettle();
            await tester.tap(toggle);
            await tester.pumpAndSettle();
            expect(bands, findsNothing);
            await tester.tap(toggle);
            await tester.pumpAndSettle();
            expect(bands, findsNWidgets(5));
          }
          expect(tester.takeException(), isNull);
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          await harness.disposeControllerOnly();
          await tester.runAsync(
            () => harness.temporaryDirectory.delete(recursive: true),
          );
        }
      });
    }
  }
}

Future<void> _capture(WidgetTester tester, Finder card, String name) async {
  final directory = Platform.environment['PLANNER_OPEN_ROWS_CAPTURE_DIR'];
  if (directory == null || directory.isEmpty) return;
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(_root),
  );
  final viewport = Offset.zero & boundary.size;
  final cardRect = tester
      .getRect(card)
      .shift(-boundary.localToGlobal(Offset.zero))
      .inflate(10)
      .intersect(viewport);
  await tester.runAsync(() async {
    await Directory(directory).create(recursive: true);
    for (final entry in {'app': viewport, 'detail': cardRect}.entries) {
      final image = await (boundary.debugLayer! as OffsetLayer).toImage(
        entry.value,
        pixelRatio: 1,
      );
      try {
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        await File(
          '$directory/$name-${entry.key}.png',
        ).writeAsBytes(data!.buffer.asUint8List());
      } finally {
        image.dispose();
      }
    }
  });
}

Future<void> _loadFonts() async {
  if (!Platform.isWindows) return;
  final win = Platform.environment['WINDIR'] ?? r'C:\Windows';
  var sdk = File(Platform.resolvedExecutable).parent;
  while (!Directory(
    '${sdk.path}/bin/cache/artifacts/material_fonts',
  ).existsSync()) {
    if (sdk.parent.path == sdk.path) {
      throw StateError('Flutter fonts not found');
    }
    sdk = sdk.parent;
  }
  for (final family in <String, List<String>>{
    'Georgia': ['$win/Fonts/georgia.ttf', '$win/Fonts/georgiab.ttf'],
    'Segoe UI': [
      '$win/Fonts/segoeui.ttf',
      '$win/Fonts/seguisb.ttf',
      '$win/Fonts/segoeuib.ttf',
    ],
    'Roboto': [
      '${sdk.path}/bin/cache/artifacts/material_fonts/roboto-regular.ttf',
      '${sdk.path}/bin/cache/artifacts/material_fonts/roboto-bold.ttf',
    ],
    'MaterialIcons': [
      '${sdk.path}/bin/cache/artifacts/material_fonts/materialicons-regular.otf',
    ],
  }.entries) {
    final loader = FontLoader(family.key);
    for (final path in family.value) {
      loader.addFont(File(path).readAsBytes().then(ByteData.sublistView));
    }
    await loader.load();
  }
}
