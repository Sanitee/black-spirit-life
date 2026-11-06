import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:bdo_craft_planner_flutter/domain/planner/planner_models.dart';
import 'package:bdo_craft_planner_flutter/features/shared/recipe_variant_selector.dart';
import 'package:bdo_craft_planner_flutter/features/shared/source_availability_badges.dart';
import 'package:bdo_craft_planner_flutter/shared/overlays/anchored_popover.dart';
import 'package:bdo_craft_planner_flutter/visual/visual.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/availability_badge_finders.dart';
import '../../support/native_preview_fonts.dart';

const _capture = bool.fromEnvironment('CAPTURE_ROUTE_DETAILS');
const _captureKey = ValueKey('route-details-native-capture');
late Map<String, dynamic> _catalog;

void main() {
  if (_capture) {
    setUpAll(() async {
      await loadNativePreviewFonts();
      _catalog =
          jsonDecode(File('assets/data/app-data.json').readAsStringSync())
              as Map<String, dynamic>;
    });
  }
  for (final spec in [
    StandardSpec.theme,
    IlluminatedLedgerSpec.theme,
    SakuraNightGardenSpec.theme,
  ]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets(
        'route details are reachable, current and bounded ${spec.id} $scale',
        (tester) async {
          tester.view.devicePixelRatio = 1;
          tester.view.physicalSize = Size(scale == 1 ? 900 : 420, 640);
          addTearDown(tester.view.reset);
          final model = ValueNotifier(_selection(10000));
          addTearDown(model.dispose);
          await tester.pumpWidget(
            MaterialApp(
              theme: spec.materialTheme(),
              builder: _capture
                  ? (_, child) =>
                        RepaintBoundary(key: _captureKey, child: child!)
                  : null,
              home: ThemeSpecScope(
                spec: spec,
                child: AppOverlayCoordinatorHost(
                  child: Scaffold(
                    body: MediaQuery(
                      data: MediaQueryData(
                        textScaler: TextScaler.linear(scale),
                      ),
                      child: Align(
                        alignment: Alignment.topCenter,
                        child: Padding(
                          padding: const EdgeInsets.all(20),
                          child: ValueListenableBuilder<RecipeRouteSelection>(
                            valueListenable: model,
                            builder: (context, value, _) =>
                                RecipeRouteCostComparison(
                                  selection: value,
                                  itemIconBuilder: (name, size) => _capture
                                      ? _nativeIcon(name, size)
                                      : SizedBox.square(dimension: size),
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
          final open = find.byKey(const ValueKey('recipe-route-cost-open'));
          final panel = find.byKey(const ValueKey('recipe-route-cost-panel'));
          expect(panel, findsNothing);
          await tester.tap(open);
          await tester.pumpAndSettle();
          expect(panel, findsOneWidget);
          expect(find.text('NPC'), findsOneWidget);
          expect(stockBadgeText('10.000'), findsOneWidget);
          expect(find.byType(SourceAvailabilityBelowLabel), findsNWidgets(2));
          final bounds = tester.getRect(panel);
          expect(bounds.left, greaterThanOrEqualTo(0));
          expect(
            bounds.right,
            lessThanOrEqualTo(tester.view.physicalSize.width),
          );
          expect(
            bounds.bottom,
            lessThanOrEqualTo(tester.view.physicalSize.height),
          );
          expect(tester.takeException(), isNull);

          await _saveCapture(tester, '${spec.id}-$scale-stock');
          if (scale == 2) {
            final total = find.descendant(
              of: panel,
              matching: find.text('4,8b'),
            );
            await tester.ensureVisible(total);
            await tester.pumpAndSettle();
            expect(
              tester.getRect(total).bottom,
              lessThanOrEqualTo(bounds.bottom),
            );
            await _saveCapture(tester, '${spec.id}-$scale-bottom');
            final scroll = tester.state<ScrollableState>(
              find
                  .descendant(of: panel, matching: find.byType(Scrollable))
                  .first,
            );
            scroll.position.jumpTo(0);
            await tester.pumpAndSettle();
          }

          // A quote change updates an already-open panel; missing is not zero.
          model.value = _selection(0);
          await tester.pumpAndSettle();
          expect(stockBadgeText('0'), findsOneWidget);
          expect(
            find.text('Not enough listed for this amount'),
            findsOneWidget,
          );
          await _saveCapture(tester, '${spec.id}-$scale-zero');
          model.value = _selection(null);
          await tester.pumpAndSettle();
          expect(stockBadgeText('—'), findsOneWidget);
          expect(stockBadgeText('0'), findsNothing);
          expect(find.text('Not enough listed for this amount'), findsNothing);
          expect(tester.takeException(), isNull);
          await _saveCapture(tester, '${spec.id}-$scale-unknown');

          await tester.sendKeyEvent(LogicalKeyboardKey.escape);
          await tester.pumpAndSettle();
          expect(panel, findsNothing);
          await tester.tap(open);
          await tester.pumpAndSettle();
          await tester.tap(
            find.bySemanticsLabel('Close Buying missing materials'),
          );
          await tester.pumpAndSettle();
          expect(panel, findsNothing);
          expect(model.value.selectedVariantId, 'npc');
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
}

Widget _nativeIcon(String name, double size) {
  final uri =
      (_catalog['itemIconArtwork'] as Map)[name.toLowerCase()] as String;
  return ItemIconFrame(
    size: size,
    grade: (_catalog['itemIconGrades'] as Map)[name.toLowerCase()] as int?,
    child: Image.memory(
      UriData.parse(uri).contentAsBytes(),
      fit: BoxFit.contain,
    ),
  );
}

Future<void> _saveCapture(WidgetTester tester, String name) async {
  if (!_capture) return;
  final root = find.byKey(_captureKey);
  for (final element
      in find.descendant(of: root, matching: find.byType(Image)).evaluate()) {
    await tester.runAsync(
      () => precacheImage((element.widget as Image).image, element),
    );
  }
  await tester.pumpAndSettle();
  final boundary = tester.renderObject<RenderRepaintBoundary>(root);
  await tester.runAsync(() async {
    final image = await boundary.toImage();
    try {
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      const directory = String.fromEnvironment('ROUTE_DETAILS_CAPTURE_DIR');
      if (directory.isEmpty) {
        throw StateError('Specify a synthetic capture folder.');
      }
      final file = File('$directory/$name.png');
      await file.parent.create(recursive: true);
      await file.writeAsBytes(bytes!.buffer.asUint8List());
    } finally {
      image.dispose();
    }
  });
}

RecipeRouteSelection _selection(int? stock) => RecipeRouteSelection(
  selectedVariantId: 'npc',
  automaticVariantId: 'npc',
  isAutomatic: true,
  options: [
    RecipeRouteOption(
      variantId: 'npc',
      ingredientName: 'Oquilla Piece of the Old Moon',
      ingredientQuantity: 2,
      outputPerCraft: 1,
      batchMultiplier: 1,
      unitPrice: 50000000,
      npcBuyable: true,
      neededQuantity: 80,
      ownedQuantity: 0,
      missingQuantity: 80,
      purchaseCost: 4000000000,
      stockKnown: false,
      availableStock: 0,
    ),
    RecipeRouteOption(
      variantId: 'market',
      ingredientName: 'Sharp Black Crystal Shard',
      ingredientQuantity: 20,
      outputPerCraft: 1,
      batchMultiplier: 1,
      unitPrice: 6000000,
      npcBuyable: false,
      neededQuantity: 800,
      ownedQuantity: 0,
      missingQuantity: 800,
      purchaseCost: 4800000000,
      stockKnown: stock != null,
      availableStock: (stock ?? 0).toDouble(),
    ),
  ],
);
