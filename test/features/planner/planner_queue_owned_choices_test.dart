import 'dart:convert';
import 'dart:io';

import 'package:bdo_craft_planner_flutter/app/app.dart';
import 'package:bdo_craft_planner_flutter/app/workspace/application_workspace.dart';
import 'package:bdo_craft_planner_flutter/data/market/shared_market_repository.dart';
import 'package:bdo_craft_planner_flutter/domain/models/craft_mode.dart';
import 'package:bdo_craft_planner_flutter/features/opportunities/opportunity_silver_amount.dart';
import 'package:bdo_craft_planner_flutter/features/planner/planner_shared.dart';
import 'package:bdo_craft_planner_flutter/features/shared/market_count_badges.dart';
import 'package:bdo_craft_planner_flutter/visual/visual.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/application_test_harness.dart';
import '../../support/availability_badge_finders.dart';
import '../../support/choice_market_transport.dart';
import 'planner_sculpted_panels_test.dart' as support;

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
      final loader = FontLoader(entry.key);
      for (final file in entry.value) {
        loader.addFont(File(file).readAsBytes().then(ByteData.sublistView));
      }
      await loader.load();
    }
  });
  testWidgets(
    'long fish choices scroll to the last item without moving the queue',
    (tester) async {
      configureApplicationTestSurface(tester, const Size(1200, 752));
      final original = (await tester.runAsync(
        () => ApplicationTestHarness.create(
          activeMode: CraftMode.cooking,
          backgroundId: 'sakura-night-garden',
        ),
      ))!;
      final harness = original.rebindControllerInCurrentZone();
      await tester.runAsync(original.disposeControllerOnly);
      final mode = harness.bundle.controller.active;
      const recipe = 'Fish Fillet Chips';
      mode.selectTarget(recipe);
      final fish = mode.recipes[recipe]!.ingredients.firstWhere(
        (i) => i.substituteGroup == 'BDO group 6',
      );
      mode.selectSubstitute(
        parentName: recipe,
        ingredient: fish,
        selection: fish.name,
      );
      try {
        await tester.pumpWidget(
          BdoCraftPlannerApp(
            applicationFuture: Future.value(harness.bundle),
            enableOpportunityAutoCheck: false,
            marketGateway: const EmptyMarketGateway(),
          ),
        );
        await tester.pumpAndSettle();
        final queue = find
            .descendant(
              of: find.byKey(
                const PageStorageKey<String>('planner-craft-queue'),
              ),
              matching: find.byType(Scrollable),
            )
            .first;
        final expand = support.k('P09:$recipe');
        final anchor = support.k('P12:step:$recipe:${fish.substituteGroup}');
        await tester.scrollUntilVisible(expand, 250, scrollable: queue);
        if (anchor.evaluate().isEmpty) await support.tap(tester, expand);
        await tester.scrollUntilVisible(anchor, 100, scrollable: queue);
        await support.tap(tester, anchor);
        expect(find.text('Dried fish'), findsOneWidget);
        final background = tester.state<ScrollableState>(queue).position;
        final offset = background.pixels;
        final panel = support.k('planner-owned-choices-panel');
        final scroll = find
            .descendant(of: panel, matching: find.byType(Scrollable))
            .first;
        expect(
          tester.state<ScrollableState>(scroll).position.maxScrollExtent,
          greaterThan(0),
        );
        final choices = find.byWidgetPredicate(
          (w) =>
              w.key is ValueKey<String> &&
              (w.key as ValueKey<String>).value.startsWith(
                'planner-owned-option:',
              ),
        );
        expect(choices.evaluate().length, greaterThan(20));
        final last = choices.last;
        await Scrollable.ensureVisible(tester.element(last));
        await tester.pumpAndSettle();
        expect(background.pixels, offset);
        final name = (tester.widget(last).key as ValueKey<String>).value
            .substring('planner-owned-option:'.length);
        await support.tap(tester, last);
        expect(mode.state.value.substituteChoices.values, contains(name));
        expect(panel, findsNothing);
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
  for (final spec in RetainedThemeRegistry.themes) {
    for (final layout in [
      (const Size(1200, 752), 1.0),
      (const Size(960, 600), 1.0),
      (const Size(1200, 752), 2.0),
      (const Size(1500, 940), 1.25),
    ]) {
      testWidgets(
        'queue owned choices ${spec.id} ${layout.$1.width} ${layout.$2}',
        (tester) async {
          configureApplicationTestSurface(
            tester,
            layout.$1,
            textScaleFactor: layout.$2,
          );
          final original = (await tester.runAsync(
            () => ApplicationTestHarness.create(
              activeMode: CraftMode.alchemy,
              backgroundId: spec.isStandard ? 'greenhouse' : spec.id,
            ),
          ))!;
          final harness = original.rebindControllerInCurrentZone();
          await tester.runAsync(original.disposeControllerOnly);
          final mode = harness.bundle.controller.active;
          mode.selectTarget("Clown's Blood");
          mode.commitAmount('300');
          final blood = mode.recipes["Clown's Blood"]!.ingredients.firstWhere(
            (i) => i.options.contains('Wolf Blood'),
          );
          mode.selectSubstitute(
            parentName: "Clown's Blood",
            ingredient: blood,
            selection: 'Wolf Blood',
          );
          mode.commitInventory('Wolf Blood', '12');
          mode.commitInventory('Flamingo Blood', '1400');
          mode.setIgnoreOwnedIngredients(false);
          final before = jsonEncode(mode.state.value.toJson());
          String? copied;
          tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
            SystemChannels.platform,
            (call) async {
              if (call.method == 'Clipboard.setData') {
                copied = (call.arguments as Map)['text'] as String;
              }
              return null;
            },
          );
          final transport = ChoiceMarketTransport();
          for (final (index, name) in blood.options.indexed) {
            final id = mode.recipes[name]!.marketId!;
            transport.values[id] = (
              price: 480 + index * 20,
              stock: index == 1 ? 0 : 12594,
              preorders: index > 0 ? 84 : 0,
            );
          }
          final broker = SharedMarketRepository(
            transport: transport,
            requestSpacing: Duration.zero,
          );
          final preview = mode.previewSubstituteAmounts(
            parentName: "Clown's Blood",
            ingredient: blood,
            selection: 'Flamingo Blood',
          );
          try {
            await tester.pumpWidget(
              RepaintBoundary(
                key: support.captureKey,
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
            final queue = find.byKey(
              const PageStorageKey<String>('planner-craft-queue'),
            );
            final queueScroll = find
                .descendant(of: queue, matching: find.byType(Scrollable))
                .first;
            final anchor = support.k(
              "P12:step:Clown's Blood:${blood.substituteGroup}",
            );
            final expand = support.k("P09:Clown's Blood");
            await tester.scrollUntilVisible(
              expand,
              200,
              scrollable: queueScroll,
            );
            if (anchor.evaluate().isEmpty) await support.tap(tester, expand);
            await tester.scrollUntilVisible(
              anchor,
              200,
              scrollable: queueScroll,
            );
            final queueInput = mode.plan.value.steps
                .firstWhere((s) => s.name == "Clown's Blood")
                .ingredients
                .firstWhere((i) => i.original == blood.name);
            final name = support.k("P11:Clown's Blood:${queueInput.key}");
            expect(name, findsOneWidget);
            await support.tap(tester, name);
            expect(support.k('planner-owned-choices-panel'), findsNothing);
            expect(copied, 'Wolf Blood');
            await support.tap(tester, anchor);
            await tester.pump(const Duration(milliseconds: 200));
            await tester.pumpAndSettle();
            expect(support.k('planner-owned-choices-panel'), findsOneWidget);
            expect(find.text('Blood Group 1'), findsOneWidget);
            final choicePanel = support.k('planner-owned-choices-panel');
            final wolfRow = support.k('planner-owned-option:Wolf Blood');
            final wolfName = tester.widget<Text>(
              find.descendant(of: wolfRow, matching: find.text('Wolf Blood')),
            );
            expect(wolfName.style!.fontSize, 16);
            expect(wolfName.style!.fontFamily, spec.typography.body.fontFamily);
            expect(wolfName.style!.color, spec.palette.text);
            final badge = tester.widget<MarketCountBadges>(
              find.descendant(
                of: wolfRow,
                matching: find.byType(MarketCountBadges),
              ),
            );
            expect(badge.density, MarketBadgeDensity.comfortable);
            final stockText = tester.widget<Text>(
              find.descendant(of: wolfRow, matching: stockBadgeText()),
            );
            expect(stockText.style!.fontSize, 14);
            final itemArt = tester.widget<PlannerItemIcon>(
              find.descendant(
                of: wolfRow,
                matching: find.byWidgetPredicate(
                  (w) => w is PlannerItemIcon && w.name == 'Wolf Blood',
                ),
              ),
            );
            expect(itemArt.size, 42 * layout.$2.clamp(1.0, 1.35));
            expect(
              tester.getSize(choicePanel).width,
              lessThanOrEqualTo(layout.$1.width),
            );
            expect(tester.getSize(choicePanel).width, greaterThan(360));
            expect(find.textContaining('bdo group'), findsNothing);
            expect(jsonEncode(mode.state.value.toJson()), before);
            expect(find.textContaining('1,4k'), findsWidgets);
            final amount = tester.widget<OpportunitySilverAmount>(
              find.ancestor(
                of: support.k('choice-buy-all:Flamingo Blood'),
                matching: find.byType(OpportunitySilverAmount),
              ),
            );
            expect(amount.value, preview.needed * 500);
            expect(amount.style.fontSize, 14);
            expect(amount.style.fontFamily, spec.typography.body.fontFamily);
            expect(preview.missing, 0);
            expect(
              amount.value,
              greaterThan(0),
              reason: 'All-needed price is not reduced by owned inventory',
            );
            await support.tap(
              tester,
              support.k('choice-buy-all:Flamingo Blood'),
            );
            expect(support.k('planner-owned-choices-panel'), findsOneWidget);
            expect(jsonEncode(mode.state.value.toJson()), before);
            await support.tap(
              tester,
              support.k('choice-buy-all:Flamingo Blood'),
            );
            expect(
              tester
                  .element(support.k('planner-owned-choices-panel'))
                  .visualTheme
                  .id,
              spec.id,
            );
            final position = tester
                .state<ScrollableState>(queueScroll)
                .position;
            final offset = position.pixels;
            await tester.sendEventToBinding(
              PointerScrollEvent(
                position: tester.getCenter(
                  support.k('planner-owned-choices-panel'),
                ),
                scrollDelta: const Offset(0, 1800),
              ),
            );
            await tester.pumpAndSettle();
            expect(position.pixels, offset);
            expect(support.k('planner-owned-choices-panel'), findsOneWidget);
            await tester.pump(const Duration(seconds: 3));
            await support.capture(
              tester,
              'queue-${spec.id}-${layout.$1.width.toInt()}-${layout.$2}',
            );
            await support.tap(
              tester,
              support.k('planner-owned-option:Flamingo Blood'),
            );
            expect(support.k('planner-owned-choices-panel'), findsNothing);
            expect(
              mode.state.value.substituteChoices.values,
              contains('Flamingo Blood'),
            );
            expect(mode.state.value.inventory['Flamingo Blood'], 1400);
            final selected = mode.plan.value.steps
                .firstWhere((s) => s.name == "Clown's Blood")
                .ingredients
                .firstWhere((i) => i.original == blood.name);
            expect(selected.name, preview.name);
            expect(selected.missing, preview.missing);
            expect(tester.takeException(), isNull);
          } finally {
            await tester.pumpWidget(const SizedBox.shrink());
            await broker.close();
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
