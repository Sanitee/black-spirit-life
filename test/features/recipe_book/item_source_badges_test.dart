import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:bdo_craft_planner_flutter/app/workspace/application_copy_toast.dart';
import 'package:bdo_craft_planner_flutter/app/workspace/application_workspace.dart';
import 'package:bdo_craft_planner_flutter/data/market/shared_market_repository.dart';
import 'package:bdo_craft_planner_flutter/domain/models/craft_mode.dart';
import 'package:bdo_craft_planner_flutter/features/planner/planner_keys.dart';
import 'package:bdo_craft_planner_flutter/features/planner/planner_review_panels.dart';
import 'package:bdo_craft_planner_flutter/features/recipe_book/recipe_book.dart';
import 'package:bdo_craft_planner_flutter/visual/visual.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/application_test_harness.dart';
import '../../support/availability_badge_finders.dart';
import '../../support/choice_market_transport.dart';
import '../../support/substitute_chooser_helpers.dart';
import '../planner/planner_choice_market_test.dart' show settle;

const _capture = ValueKey('source-badges-capture');
Finder k(String name) => find.byKey(ValueKey(name));

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
      testWidgets('actual Recipe Book source pills ${spec.id} $scale', (
        tester,
      ) async {
        configureApplicationTestSurface(
          tester,
          const Size(1200, 900),
          textScaleFactor: scale,
        );
        final original = (await tester.runAsync(
          () => ApplicationTestHarness.create(
            activeMode: CraftMode.cooking,
            backgroundId: spec.isStandard ? 'greenhouse' : spec.id,
          ),
        ))!;
        final harness = original.rebindControllerInCurrentZone();
        await tester.runAsync(original.disposeControllerOnly);
        final mode = harness.bundle.controller.active;
        mode.selectTarget('Citron Juice');
        mode.commitAmount('100');
        final before = jsonEncode(mode.state.value.toJson());
        final transport = ChoiceMarketTransport();
        final citron = mode.recipes['Citron']!.marketId!;
        final honey = mode.recipes['Cooking Honey']!.marketId!;
        transport.values[citron] = (price: 2000, stock: 2532, preorders: 0);
        transport.values[honey] = (price: 3000, stock: 0, preorders: 84);
        final broker = SharedMarketRepository(
          transport: transport,
          requestSpacing: Duration.zero,
        );
        final copies = <String>[];
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          (call) async {
            if (call.method == 'Clipboard.setData') {
              copies.add((call.arguments as Map)['text'] as String);
            }
            return null;
          },
        );
        try {
          await tester.pumpWidget(
            RepaintBoundary(
              key: _capture,
              child: MaterialApp(
                debugShowCheckedModeBanner: false,
                home: ApplicationWorkspace(
                  bundle: harness.bundle,
                  sharedMarket: broker,
                  fishMapWorkspace: const SizedBox.shrink(),
                  enableBetaUpdates: false,
                  enableOpportunityAutoCheck: false,
                  marketGateway: const EmptyMarketGateway(),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          await tester.tap(k('planner-shopping-open'));
          await tester.pumpAndSettle();
          await tester.tap(k('planner-shopping-copy'));
          await tester.pumpAndSettle();
          expect(copies.last, shoppingText(shoppingGroups(mode)));
          expect(find.text('Shopping list copied'), findsOneWidget);
          expect(
            tester.getRect(find.byKey(ApplicationCopyToastKeys.surface)).top,
            lessThan(100),
          );
          expect(find.byType(SnackBar), findsNothing);
          await capture(tester, '${spec.id}-$scale-shopping-copy');
          await tester.pump(const Duration(milliseconds: 1400));
          await tester.sendKeyEvent(LogicalKeyboardKey.escape);
          await tester.pumpAndSettle();
          await tester.tap(find.byKey(PlannerActionKeys.p03));
          await tester.pumpAndSettle();
          final book = tester
              .widget<RecipeBookModal>(find.byType(RecipeBookModal))
              .controller;
          book.setSearch('Citron Juice');
          await tester.pumpAndSettle();
          await tester.tap(
            find.byKey(RecipeBookKeys.r13Details('Citron Juice')),
          );
          await tester.pumpAndSettle();
          final art = find
              .descendant(
                of: find.byKey(RecipeBookKeys.previewPanel),
                matching: find.byType(RecipeBookItemIcon),
              )
              .first;
          await tester.tap(art);
          await tester.pumpAndSettle();
          await settle(tester, broker);
          final card = find.byType(ItemReferenceCard);
          expect(card, findsOneWidget);
          // Ingredient-bearing cards also request their visible availability.
          // These exact detail-card identities must still all be requested.
          expect(
            transport.requests.expand((r) => r.ids).toSet(),
            containsAll({
              '9355', // Citron Juice's own verified Central Market source.
              citron,
              honey,
            }),
          );
          for (final entry in {
            'Citron': '2,5k',
            'Cooking Honey': '0',
            'Sugar': 'NPC',
            'Mineral Water': 'NPC',
          }.entries) {
            final badge = find.descendant(
              of: card,
              matching: k('reference-source:${entry.key}'),
            );
            expect(
              find.descendant(of: badge, matching: find.text(entry.value)),
              findsOneWidget,
            );
            final label = find.descendant(
              of: card,
              matching: find.text(entry.key),
            );
            expect(
              tester.getRect(badge).left,
              greaterThan(tester.getRect(label).right),
            );
            if (scale == 1) {
              expect(
                tester.getRect(badge).center.dy,
                closeTo(tester.getRect(label).center.dy, 1),
              );
              // Source pills occupy separate aligned columns, without overlap.
              expect(
                tester
                    .getRect(badge)
                    .overlaps(tester.getRect(label).inflate(5)),
                isFalse,
              );
            }
          }
          expect(
            find.descendant(
              of: find.descendant(
                of: card,
                matching: k('reference-source:Cooking Honey'),
              ),
              matching: find.text('Orders 84'),
            ),
            findsOneWidget,
          );
          // Hidden alternatives load only when their chooser is opened.
          expect(
            transport.requests.expand((r) => r.ids),
            isNot(contains('7361')),
          );
          await openSubstitutes(tester, 'Citron Juice', 'Citron');
          await settle(tester, broker);
          expect(
            transport.requests.expand((r) => r.ids),
            containsAll(['7361', '7362']),
          );
          await chooseSubstitute(tester, 'Citron Juice', 'Citron');
          final scroll = tester.state<ScrollableState>(
            find.descendant(
              of: card,
              matching: find.byWidgetPredicate(
                (widget) =>
                    widget is Scrollable &&
                    widget.axisDirection == AxisDirection.down,
              ),
            ),
          );
          if (scale == 1) {
            // Grades now have their own aligned inventory/market rows. The
            // longer table may scroll, but notes must remain reachable.
            final notes = find.descendant(
              of: card,
              matching: find.text('Notes'),
            );
            await tester.ensureVisible(notes);
            await tester.pumpAndSettle();
            expect(notes.hitTestable(), findsOneWidget);
            scroll.position.jumpTo(0);
            await tester.pumpAndSettle();
          }
          await capture(tester, '${spec.id}-$scale-citron');
          if (scale == 1) {
            await capture(
              tester,
              '${spec.id}-citron-window',
              target: find
                  .ancestor(of: card, matching: find.byType(RepaintBoundary))
                  .first,
            );
          }
          await tester.ensureVisible(
            find.descendant(of: card, matching: find.text('Sugar')),
          );
          await tester.tap(
            find.descendant(of: card, matching: find.text('Sugar')),
          );
          await tester.pumpAndSettle();
          expect(copies.last, 'Sugar');
          expect(find.text('Copied Sugar'), findsOneWidget);
          expect(card, findsOneWidget);
          expect(find.byType(SnackBar), findsNothing);
          // A live region change clears the old region without rebuilding the host.
          expect(jsonEncode(mode.state.value.toJson()), before);
          transport.hold = Completer<void>();
          mode.setMarketRegion('na');
          await tester.pump(const Duration(milliseconds: 200));
          expect(
            find.descendant(
              of: find.descendant(
                of: card,
                matching: k('reference-source:Citron'),
              ),
              matching: stockBadgeText('—'),
            ),
            findsOneWidget,
          );
          expect(transport.requests.last.region, 'na');
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump(const Duration(milliseconds: 500));
          expect(transport.aborted, isTrue);
          transport.hold!.complete();
          expect(tester.takeException(), isNull);
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
            SystemChannels.platform,
            null,
          );
          await broker.close();
          await harness.disposeControllerOnly();
          await tester.runAsync(
            () => harness.temporaryDirectory.delete(recursive: true),
          );
        }
      });
    }
  }
}

Future<void> capture(WidgetTester tester, String name, {Finder? target}) async {
  final dir = Platform.environment['BSL_CONSISTENT_CAPTURE_DIR'];
  if (dir == null) return;
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    target ?? find.byKey(_capture),
  );
  await tester.runAsync(() async {
    await Directory(dir).create(recursive: true);
    final image = await boundary.toImage(pixelRatio: 1);
    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      await File('$dir/$name.png').writeAsBytes(data!.buffer.asUint8List());
    } finally {
      image.dispose();
    }
  });
}
