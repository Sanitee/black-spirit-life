import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:bdo_craft_planner_flutter/app/app.dart';
import 'package:bdo_craft_planner_flutter/app/appearance/appearance_actions.dart';
import 'package:bdo_craft_planner_flutter/domain/models/craft_mode.dart';
import 'package:bdo_craft_planner_flutter/domain/state/craft_completion.dart';
import 'package:bdo_craft_planner_flutter/features/planner/planner_review_panels.dart';
import 'package:bdo_craft_planner_flutter/features/resource_map/resource_map_workspace.dart';
import 'package:bdo_craft_planner_flutter/visual/visual.dart';
import 'package:bdo_map_core/bdo_map_core.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import '../../support/application_test_harness.dart';

const captureKey = ValueKey('sculpted-capture');
Finder k(String key) => find.byKey(ValueKey(key));

void main() {
  setUpAll(() async {
    for (final entry in {
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
      final fonts = FontLoader(entry.key);
      for (final path in entry.value) {
        if (File(path).existsSync()) {
          fonts.addFont(File(path).readAsBytes().then(ByteData.sublistView));
        }
      }
      await fonts.load();
    }
    await BdoResourceMapLoader.loadBundled();
    await BdoWorkerEconomicsLoader.loadBundled();
    await LodgingDataLoader.loadBundled();
  });
  for (final spec in RetainedThemeRegistry.themes) {
    for (final layout in [
      (const Size(1200, 752), 1.0),
      (const Size(960, 600), 1.0),
      (const Size(1200, 752), 2.0),
      (const Size(1500, 940), 1.25),
    ]) {
      testWidgets('sculpted ${spec.id} ${layout.$1.width} ${layout.$2}', (
        tester,
      ) async {
        configureApplicationTestSurface(
          tester,
          layout.$1,
          textScaleFactor: layout.$2,
        );
        final original = (await tester.runAsync(
          () => ApplicationTestHarness.create(
            activeMode: CraftMode.cooking,
            backgroundId: spec.isStandard ? 'greenhouse' : spec.id,
          ),
        ))!;
        final harness = original.rebindControllerInCurrentZone();
        await tester.runAsync(original.disposeControllerOnly);
        final app = harness.bundle.controller;
        final mode = app.active;
        mode.selectTarget('Beer');
        mode.commitAmount('1000');
        final grain = mode.recipes['Beer']!.ingredients.firstWhere(
          (i) => i.options.contains('Corn'),
        );
        mode.selectSubstitute(
          parentName: 'Beer',
          ingredient: grain,
          selection: 'Corn',
        );
        for (final entry in {
          'Corn': 600,
          'Wheat': 2400,
          'Potato': 1500,
          'Barley': 0,
          'Sweet Potato': 400,
        }.entries) {
          mode.commitInventory(entry.key, '${entry.value}');
        }
        mode.setIgnoreOwnedIngredients(false);
        final before = jsonEncode(mode.state.value.toJson());
        final projected = mode.previewSubstituteAmounts(
          parentName: 'Beer',
          ingredient: grain,
          selection: 'Wheat',
        );
        expect(projected, (
          name: 'Wheat',
          owned: 2400.0,
          missing: 0.0,
          needed: 2000.0,
        ));
        expect(jsonEncode(mode.state.value.toJson()), before);
        final client = MockClient(
          (_) async => http.Response('No networking', 503),
        );
        final stem = '${spec.id}-${layout.$1.width.toInt()}-${layout.$2}';
        try {
          await tester.pumpWidget(
            RepaintBoundary(
              key: captureKey,
              child: BdoCraftPlannerApp(
                applicationFuture: Future.value(harness.bundle),
                enableOpportunityAutoCheck: false,
                marketGateway: const EmptyMarketGateway(),
                resourceMapConfiguration: ResourceMapWorkspaceConfiguration(
                  cacheDirectory: Directory(
                    '${harness.temporaryDirectory.path}/map-cache',
                  ),
                  tileHttpClient: client,
                  showSourceNotice: false,
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          await tap(tester, k('planner-shopping-open'));
          expect(k('planner-shopping-list-panel'), findsOneWidget);
          final groups = shoppingGroups(mode);
          expect(
            groups['NPC']!.map((r) => r.name),
            containsAll(['Mineral Water', 'Sugar', 'Leavening Agent']),
          );
          expect(groups['Market / gather']!.single.name, 'Corn');
          expect(groups['Market / gather']!.single.missing, 1400);
          expect(shoppingText(groups), contains('Corn ×1.400'));
          for (final label in groups.keys) {
            final rail = k('sculpted-rail:$label');
            final text = find.descendant(of: rail, matching: find.text(label));
            final railCenter = tester.getCenter(rail);
            final textCenter = tester.getCenter(text);
            expect(textCenter.dx, closeTo(railCenter.dx, 1));
            expect(textCenter.dy, closeTo(railCenter.dy, 1));
            expect(tester.widget<Text>(text).textAlign, TextAlign.center);
          }
          expect(jsonEncode(mode.state.value.toJson()), before);
          await capture(tester, '$stem-shopping');
          if (spec.isSakuraNightGarden &&
              layout.$1.width == 1200 &&
              layout.$2 == 1) {
            for (final theme in RetainedThemeRegistry.themes) {
              app.updateDocument(
                (doc) => AppearanceActions.selectSharedBackground(
                  doc,
                  theme.isStandard ? 'greenhouse' : theme.id,
                ),
              );
              await tester.pumpAndSettle();
              if (k('planner-shopping-list-panel').evaluate().isEmpty) {
                await tap(tester, k('planner-shopping-open'));
              }
              expect(
                tester.element(k('planner-shopping-list-panel')).visualTheme.id,
                theme.id,
              );
              expect(shoppingText(shoppingGroups(mode)), shoppingText(groups));
              await capture(tester, 'switch-${theme.id}');
            }
            app.updateDocument(
              (doc) => AppearanceActions.selectSharedBackground(doc, spec.id),
            );
            await tester.pumpAndSettle();
            if (k('planner-shopping-list-panel').evaluate().isEmpty) {
              await tap(tester, k('planner-shopping-open'));
            }
          }
          await tester.sendKeyEvent(LogicalKeyboardKey.escape);
          await tester.pumpAndSettle();
          expect(k('planner-shopping-list-panel'), findsNothing);
          await tester.ensureVisible(k('P20:Corn'));
          await tester.pumpAndSettle();
          await tap(tester, k('P20:Corn'));
          expect(k('planner-owned-choices-panel'), findsNothing);
          await tap(tester, k('P12:missing:Corn:${grain.substituteGroup}'));
          expect(k('planner-owned-choices-panel'), findsOneWidget);
          expect(find.textContaining('2,4k'), findsWidgets);
          expect(jsonEncode(mode.state.value.toJson()), before);
          await capture(tester, '$stem-owned');
          final backgroundScroll = tester
              .state<ScrollableState>(
                find
                    .descendant(
                      of: find.byKey(
                        const PageStorageKey<String>('planner-need-first'),
                      ),
                      matching: find.byType(Scrollable),
                    )
                    .first,
              )
              .position;
          final backgroundOffset = backgroundScroll.pixels;
          final popupScroll = tester
              .state<ScrollableState>(
                find
                    .descendant(
                      of: k('planner-owned-choices-panel'),
                      matching: find.byType(Scrollable),
                    )
                    .first,
              )
              .position;
          if (popupScroll.maxScrollExtent > 0) {
            await tester.sendEventToBinding(
              PointerScrollEvent(
                position: tester.getCenter(k('planner-owned-choices-panel')),
                scrollDelta: const Offset(0, 1600),
              ),
            );
            await tester.pumpAndSettle();
            expect(popupScroll.pixels, greaterThan(0));
            expect(backgroundScroll.pixels, backgroundOffset);
            expect(k('planner-owned-choices-panel'), findsOneWidget);
          }
          await tap(tester, k('planner-owned-option:Wheat'));
          expect(k('planner-owned-choices-panel'), findsNothing);
          expect(mode.state.value.substituteChoices.values, contains('Wheat'));
          expect(mode.state.value.inventory['Wheat'], 2400);
          expect(
            mode.plan.value.missing.any(
              (r) => r.name == 'Wheat' && r.missing > 0,
            ),
            isFalse,
          );

          // Receipt reflects actual output and clamped consumption, not forecast.
          final step = mode.plan.value.steps.firstWhere(
            (s) => s.name == 'Beer',
          );
          final inventoryBefore = Map.of(mode.state.value.inventory);
          app.updateDocument(
            (document) => recordCraftCompletion(
              document: document,
              mode: CraftMode.cooking,
              step: step,
              target: 'Beer',
              want: 1000,
              markComplete: true,
              actualOutput: 900,
            ),
          );
          final receipt = mode.completionReview!;
          expect(receipt.remove['Beer'], 900);
          expect(receipt.restore['Wheat'], 2000);
          expect(receipt.restore.containsKey('Mineral Water'), isFalse);
          await tester.pumpAndSettle();
          final completed = jsonEncode(mode.state.value.toJson());
          await tap(tester, k('planner-undo-completion'));
          expect(k('planner-undo-review-panel'), findsOneWidget);
          expect(jsonEncode(mode.state.value.toJson()), completed);
          await capture(tester, '$stem-undo');
          await tap(tester, k('planner-undo-confirm'));
          expect(mode.state.value.inventory['Wheat'], inventoryBefore['Wheat']);
          expect(mode.state.value.inventory['Beer'] ?? 0, 0);
          expect(mode.completionReview, isNull);
          expect(tester.takeException(), isNull);
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          await harness.disposeControllerOnly();
          client.close();
          await tester.runAsync(
            () => harness.temporaryDirectory.delete(recursive: true),
          );
        }
      });
    }
  }
}

Future<void> tap(WidgetTester tester, Finder finder) async {
  final scroll = Scrollable.maybeOf(tester.element(finder));
  if (scroll != null) {
    await Scrollable.ensureVisible(tester.element(finder));
    await tester.pumpAndSettle();
  }
  await tester.tap(finder);
  await tester.pumpAndSettle();
  expect(tester.takeException(), isNull);
}

Future<void> capture(WidgetTester tester, String name) async {
  final directory = Platform.environment['BSL_SCULPTED_CAPTURE_DIR'];
  if (directory == null) return;
  for (final element in find.byType(Image).evaluate()) {
    await tester.runAsync(
      () => precacheImage((element.widget as Image).image, element),
    );
  }
  await tester.pumpAndSettle();
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(captureKey),
  );
  await tester.runAsync(() async {
    await Directory(directory).create(recursive: true);
    final image = await boundary.toImage(pixelRatio: 1);
    try {
      final data = (await image.toByteData(format: ui.ImageByteFormat.png))!;
      await File(
        '$directory/$name.png',
      ).writeAsBytes(data.buffer.asUint8List());
    } finally {
      image.dispose();
    }
  });
}
