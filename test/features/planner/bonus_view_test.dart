import 'package:bdo_craft_planner_flutter/domain/models/craft_mode.dart';
import 'package:bdo_craft_planner_flutter/domain/state/state_copy.dart';
import 'package:bdo_craft_planner_flutter/features/planner/planner.dart';
import 'package:bdo_craft_planner_flutter/features/planner/planner_shared.dart';
import 'package:bdo_craft_planner_flutter/visual/visual.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'planner_test_fixture.dart';

void main() {
  testWidgets('bonus command and Standard plan use reference geometry', (
    tester,
  ) async {
    await setPlannerTestSize(tester, const Size(1200, 752));
    final harness = PlannerTestHarness();

    await tester.pumpWidget(harness.bonusHost());
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.text('BONUS TARGET'), findsOneWidget);
    expect(find.text('AMOUNT'), findsOneWidget);
    expect(
      tester.getSize(find.byKey(const ValueKey<String>('bonus-command-gap'))),
      const Size(1176, 48),
    );
    expect(find.text('2 steps'), findsOneWidget);
    expect(find.text('2 left'), findsNothing);
    expect(
      find.descendant(
        of: find.byKey(BonusActionKeys.b03),
        matching: _glyph('book'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(BonusActionKeys.b04),
        matching: _glyph('calc'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(BonusActionKeys.b05),
        matching: _glyph('target'),
      ),
      findsOneWidget,
    );

    final targetGroup = tester.getRect(
      find.byKey(const ValueKey<String>('bonus-command-target')),
    );
    final target = tester.getRect(find.byKey(BonusActionKeys.b01));
    final recipes = tester.getRect(find.byKey(BonusActionKeys.b03));
    final amount = tester.getRect(find.byKey(BonusActionKeys.b02));
    final rebuild = tester.getRect(find.byKey(BonusActionKeys.b04));
    final finalAction = tester.getRect(find.byKey(BonusActionKeys.b05));
    expect(targetGroup.width, 490);
    expect(target.width, 390);
    expect(recipes.width, 122);
    expect(amount.width, 78);
    expect(rebuild.width, 68);
    expect(finalAction.width, 206);
    expect(recipes.left - targetGroup.right, 13);
    expect(amount.left - recipes.right, 13);
    expect(rebuild.left - (amount.left + 86), 13);
    expect(finalAction.left - rebuild.right, 13);
    expect(
      _inputContainerRect(tester, find.byKey(BonusActionKeys.b01)),
      target,
    );
    expect(
      tester
          .widget<TextField>(
            find.descendant(
              of: find.byKey(BonusActionKeys.b01),
              matching: find.byType(TextField),
            ),
          )
          .style!
          .fontSize,
      plannerStandardTargetFontSize,
    );
    expect(
      _inputContainerRect(tester, find.byKey(BonusActionKeys.b02)),
      amount,
    );
    for (final rect in <Rect>[target, recipes, amount, rebuild, finalAction]) {
      expect(rect.height, plannerStandardCommandControlHeight);
      expect(rect.top, target.top);
      expect(rect.bottom, target.bottom);
    }
    for (final action in <Key>[
      BonusActionKeys.b03,
      BonusActionKeys.b04,
      BonusActionKeys.b05,
    ]) {
      expect(
        tester.getRect(
          find.descendant(
            of: find.byKey(action),
            matching: find.byKey(AppButton.materialKey),
          ),
        ),
        tester.getRect(find.byKey(action)),
      );
    }

    final queue = tester.getRect(
      find
          .ancestor(
            of: find.text('Craft Queue'),
            matching: find.byType(AppSurface),
          )
          .first,
    );
    final need = tester.getRect(
      find
          .ancestor(
            of: find.text('Need First'),
            matching: find.byType(AppSurface),
          )
          .first,
    );
    expect(queue.width / need.width, closeTo(106 / 94, .02));
    expect(need.left - queue.right, 12);

    await harness.controller.dispose();
  });

  testWidgets('B07 Bonus Need First icons open acquisition guidance', (
    tester,
  ) async {
    await setPlannerTestSize(tester, const Size(1200, 752));
    final harness = PlannerTestHarness();

    await tester.pumpWidget(harness.bonusHost());
    await tester.pump(const Duration(milliseconds: 200));

    final action = find.byKey(
      PlannerActionKeys.row('P22', 'need:Sunrise Herb'),
    );
    final card = find.bySemanticsLabel('How to obtain Sunrise Herb');
    expect(action, findsOneWidget);
    expect(card, findsNothing);

    await tester.tap(action);
    await tester.pump();
    expect(card, findsOneWidget);
    expect(find.text('Gathered near Heidel roads.'), findsOneWidget);

    await tester.tapAt(const Offset(20, 20));
    await tester.pump();
    expect(card, findsNothing);
    expect(tester.takeException(), isNull);
    await harness.controller.dispose();
  });

  testWidgets('Ledger Bonus matches the authored command band and actions', (
    tester,
  ) async {
    await setPlannerTestSize(tester, const Size(1200, 752));
    final harness = PlannerTestHarness();

    await tester.pumpWidget(_ledgerHost(harness));
    await tester.pump(const Duration(milliseconds: 200));

    expect(
      tester.getSize(find.byKey(const ValueKey<String>('bonus-command-gap'))),
      const Size(1176, 24),
    );
    expect(find.text('BONUS TARGET'), findsOneWidget);
    expect(find.text('AMOUNT'), findsOneWidget);
    expect(find.byKey(PlannerActionKeys.p15), findsNothing);
    expect(find.byKey(PlannerActionKeys.p16), findsNothing);
    expect(
      tester.widget<Text>(find.text('CRAFT QUEUE')).style?.color,
      IlluminatedLedgerSpec.palette.primary,
    );
    final stepMeta = tester.widget<Text>(find.text('2 steps'));
    expect(stepMeta.style?.fontSize, 13);
    expect(stepMeta.style?.fontWeight, FontWeight.w600);
    expect(stepMeta.style?.fontStyle, FontStyle.normal);
    expect(stepMeta.style?.color, IlluminatedLedgerSpec.palette.text);
    final ledgerTarget = tester.widget<TextField>(
      find.descendant(
        of: find.byKey(BonusActionKeys.b01),
        matching: find.byType(TextField),
      ),
    );
    expect(ledgerTarget.style!.fontSize, 13);

    final recipes = tester.widget<AppButton>(find.byKey(BonusActionKeys.b03));
    final rebuild = tester.widget<AppButton>(find.byKey(BonusActionKeys.b04));
    expect(recipes.role, AppButtonRole.primary);
    expect(rebuild.role, AppButtonRole.primary);
    expect(
      find.descendant(
        of: find.byKey(BonusActionKeys.b04),
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is AppVectorGlyph &&
              widget.name == 'calc' &&
              widget.size == 23,
        ),
      ),
      findsOneWidget,
    );

    final targetGroup = tester.getRect(
      find.byKey(const ValueKey<String>('bonus-command-target')),
    );
    final amountGroup = tester.getRect(
      find.byKey(const ValueKey<String>('bonus-command-amount')),
    );
    final targetRect = tester.getRect(find.byKey(BonusActionKeys.b01));
    final recipesRect = tester.getRect(find.byKey(BonusActionKeys.b03));
    final amountRect = tester.getRect(find.byKey(BonusActionKeys.b02));
    final rebuildRect = tester.getRect(find.byKey(BonusActionKeys.b04));
    final finalRect = tester.getRect(find.byKey(BonusActionKeys.b05));
    expect(recipesRect.size, const Size(112, 46));
    expect(amountRect.size, const Size(78, 38));
    expect(rebuildRect.size, const Size(48, 46));
    expect(finalRect.width, greaterThan(140));
    expect(finalRect.height, closeTo(46, .01));
    expect(amountGroup.top, closeTo(targetGroup.top, .01));
    expect(recipesRect.center.dy, closeTo(targetRect.center.dy, .01));
    expect(rebuildRect.center.dy, closeTo(amountRect.center.dy, .01));
    expect(finalRect.center.dy, closeTo(amountRect.center.dy, .01));

    await harness.controller.dispose();
  });

  testWidgets('Sakura Bonus keeps the Ledger-format command and split fit', (
    tester,
  ) async {
    await setPlannerTestSize(tester, const Size(1200, 752));
    final harness = PlannerTestHarness();

    Future<Map<String, Rect>> capture(ThemeSpec spec) async {
      await tester.pumpWidget(_fullThemeHost(harness, spec));
      await tester.pump(const Duration(milliseconds: 200));
      final frames = find.byWidgetPredicate(
        (widget) =>
            widget is AppSurface &&
            widget.role == AppSurfaceRole.layout &&
            (widget.semanticLabel == 'Craft Queue' ||
                widget.semanticLabel == 'Need First'),
      );
      final frameRects = <Rect>[
        tester.getRect(frames.at(0)),
        tester.getRect(frames.at(1)),
      ]..sort((left, right) => left.left.compareTo(right.left));
      return <String, Rect>{
        'command': tester.getRect(
          find.byWidgetPredicate(
            (widget) =>
                widget is AppSurface &&
                widget.semanticLabel == 'Bonus recipe commands',
          ),
        ),
        'gap': tester.getRect(
          find.byKey(const ValueKey<String>('bonus-command-gap')),
        ),
        'target': tester.getRect(
          find.byKey(const ValueKey<String>('bonus-command-target')),
        ),
        'amount': tester.getRect(
          find.byKey(const ValueKey<String>('bonus-command-amount')),
        ),
        'recipes': tester.getRect(find.byKey(BonusActionKeys.b03)),
        'rebuild': tester.getRect(find.byKey(BonusActionKeys.b04)),
        'final': tester.getRect(find.byKey(BonusActionKeys.b05)),
        'queue': frameRects.first,
        'need': frameRects.last,
      };
    }

    final ledger = await capture(IlluminatedLedgerSpec.theme);
    final sakura = await capture(SakuraNightGardenSpec.theme);
    for (final key in ledger.keys) {
      // Sakura's 1.15 px lacquer keyline may resolve to a subpixel wider than
      // Ledger's 1 px ink rule without changing the retained grid geometry.
      expect(sakura[key]!.width, closeTo(ledger[key]!.width, .35), reason: key);
      expect(
        sakura[key]!.height,
        closeTo(ledger[key]!.height, .01),
        reason: key,
      );
      expect(sakura[key]!.left, closeTo(ledger[key]!.left, .35), reason: key);
      expect(sakura[key]!.right, closeTo(ledger[key]!.right, .35), reason: key);
      expect(
        sakura[key]!.top,
        closeTo(ledger[key]!.top, 1.01),
        reason: '$key should stay on the dense full-theme geometry',
      );
    }
    expect(sakura['need']!.left - sakura['queue']!.right, 44);
    expect(
      tester.widget<AppButton>(find.byKey(BonusActionKeys.b03)).role,
      AppButtonRole.secondary,
    );
    expect(
      tester.widget<AppButton>(find.byKey(BonusActionKeys.b04)).role,
      AppButtonRole.secondary,
    );
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is AppSurface &&
            widget.role == AppSurfaceRole.card &&
            widget.ornamentIndex != null,
      ),
      findsWidgets,
    );
    expect(tester.takeException(), isNull);
    await harness.controller.dispose();
  });

  testWidgets(
    'responsive Standard Bonus target paints through its complete control height',
    (tester) async {
      await setPlannerTestSize(tester, const Size(700, 700));
      final harness = PlannerTestHarness();

      await tester.pumpWidget(harness.bonusHost());
      await tester.pump(const Duration(milliseconds: 200));

      final target = tester.getRect(find.byKey(BonusActionKeys.b01));
      final recipes = tester.getRect(find.byKey(BonusActionKeys.b03));
      expect(target.height, plannerStandardCommandControlHeight);
      expect(recipes.height, plannerStandardCommandControlHeight);
      expect(
        _inputContainerRect(tester, find.byKey(BonusActionKeys.b01)),
        target,
      );
      expect(
        tester
            .widget<TextField>(
              find.descendant(
                of: find.byKey(BonusActionKeys.b01),
                matching: find.byType(TextField),
              ),
            )
            .style!
            .fontSize,
        plannerStandardTargetFontSize,
      );
      expect(tester.takeException(), isNull);
      await harness.controller.dispose();
    },
  );

  testWidgets(
    'wide Standard Bonus paints one aligned compact command row at 1500x940',
    (tester) async {
      await setPlannerTestSize(tester, const Size(1500, 940));
      final harness = PlannerTestHarness();

      await tester.pumpWidget(harness.bonusHost());
      await tester.pump(const Duration(milliseconds: 200));

      final target = tester.getRect(find.byKey(BonusActionKeys.b01));
      final amount = tester.getRect(find.byKey(BonusActionKeys.b02));
      final recipes = tester.getRect(find.byKey(BonusActionKeys.b03));
      final rebuild = tester.getRect(find.byKey(BonusActionKeys.b04));
      final finalAction = tester.getRect(find.byKey(BonusActionKeys.b05));
      for (final rect in <Rect>[
        target,
        recipes,
        amount,
        rebuild,
        finalAction,
      ]) {
        expect(rect.height, plannerStandardCommandControlHeight);
        expect(rect.top, target.top);
        expect(rect.bottom, target.bottom);
      }
      expect(
        _inputContainerRect(tester, find.byKey(BonusActionKeys.b01)),
        target,
      );
      expect(
        tester
            .widget<TextField>(
              find.descendant(
                of: find.byKey(BonusActionKeys.b01),
                matching: find.byType(TextField),
              ),
            )
            .style!
            .fontSize,
        plannerStandardTargetFontSize,
      );
      expect(
        _inputContainerRect(tester, find.byKey(BonusActionKeys.b02)),
        amount,
      );
      for (final action in <Key>[
        BonusActionKeys.b03,
        BonusActionKeys.b04,
        BonusActionKeys.b05,
      ]) {
        expect(
          tester.getRect(
            find.descendant(
              of: find.byKey(action),
              matching: find.byKey(AppButton.materialKey),
            ),
          ),
          tester.getRect(find.byKey(action)),
        );
      }
      expect(tester.takeException(), isNull);
      await harness.controller.dispose();
    },
  );

  testWidgets('Ledger Use As Target keeps its full label at 1500x940', (
    tester,
  ) async {
    await setPlannerTestSize(tester, const Size(1500, 940));
    final harness = PlannerTestHarness();

    await tester.pumpWidget(_ledgerHost(harness));
    await tester.pump(const Duration(milliseconds: 200));

    final label = find.descendant(
      of: find.byKey(BonusActionKeys.b05),
      matching: find.text('Use As Target'),
    );
    final paragraph = tester.renderObject<RenderParagraph>(label);
    final labelRect = tester.getRect(label);
    final buttonRect = tester.getRect(find.byKey(BonusActionKeys.b05));
    expect(paragraph.didExceedMaxLines, isFalse);
    expect(labelRect.left, greaterThanOrEqualTo(buttonRect.left));
    expect(labelRect.top, greaterThanOrEqualTo(buttonRect.top));
    expect(labelRect.right, lessThanOrEqualTo(buttonRect.right));
    expect(labelRect.bottom, lessThanOrEqualTo(buttonRect.bottom));
    expect(tester.takeException(), isNull);

    await harness.controller.dispose();
  });

  testWidgets(
    'dense Bonus action lane stays compact at both supported window sizes',
    (tester) async {
      for (final size in <Size>[const Size(1200, 752), const Size(1500, 940)]) {
        await setPlannerTestSize(tester, size);
        for (final spec in <ThemeSpec>[
          IlluminatedLedgerSpec.theme,
          SakuraNightGardenSpec.theme,
        ]) {
          final harness = PlannerTestHarness();
          await tester.pumpWidget(_fullThemeHost(harness, spec));
          await tester.pump(const Duration(milliseconds: 200));

          final command = tester.getRect(
            find.byWidgetPredicate(
              (widget) =>
                  widget is AppSurface &&
                  widget.semanticLabel == 'Bonus recipe commands',
            ),
          );
          final target = tester.getRect(find.byKey(BonusActionKeys.b01));
          final amount = tester.getRect(find.byKey(BonusActionKeys.b02));
          final recipes = tester.getRect(find.byKey(BonusActionKeys.b03));
          final rebuild = tester.getRect(find.byKey(BonusActionKeys.b04));
          final finalAction = tester.getRect(find.byKey(BonusActionKeys.b05));

          expect(recipes.size, const Size(112, 46), reason: '$size ${spec.id}');
          expect(rebuild.size, const Size(48, 46), reason: '$size ${spec.id}');
          expect(finalAction.size, const Size(176, 46));
          expect(recipes.center.dy, closeTo(target.center.dy, .01));
          expect(rebuild.center.dy, closeTo(amount.center.dy, .01));
          expect(finalAction.center.dy, closeTo(amount.center.dy, .01));
          expect(finalAction.right, lessThanOrEqualTo(command.right));
          expect(finalAction.bottom, lessThanOrEqualTo(command.bottom));

          for (final action in <Key>[
            BonusActionKeys.b03,
            BonusActionKeys.b04,
            BonusActionKeys.b05,
          ]) {
            expect(
              tester.getRect(
                find.descendant(
                  of: find.byKey(action),
                  matching: find.byKey(AppButton.materialKey),
                ),
              ),
              tester.getRect(find.byKey(action)),
            );
          }
          expect(tester.takeException(), isNull);
          await harness.controller.dispose();
        }
      }
    },
  );

  testWidgets('bonus plan changes reset a retained queue scroll position', (
    tester,
  ) async {
    await setPlannerTestSize(tester, const Size(1200, 500));
    final harness = PlannerTestHarness();

    await tester.pumpWidget(harness.bonusHost());
    await tester.pump(const Duration(milliseconds: 200));

    ScrollPosition queuePosition() => tester
        .state<ScrollableState>(
          find
              .descendant(
                of: find.byKey(
                  const PageStorageKey<String>('planner-craft-queue'),
                ),
                matching: find.byType(Scrollable),
              )
              .first,
        )
        .position;

    final initial = queuePosition();
    expect(initial.maxScrollExtent, greaterThan(0));
    initial.jumpTo(initial.maxScrollExtent);
    await tester.pump();
    expect(initial.pixels, greaterThan(0));

    harness.controller.active.updateState(
      (state) => state.copyWith(bonusTarget: 'Pure Powder Reagent'),
      immediate: true,
    );
    await tester.pump();

    final updated = queuePosition();
    expect(updated.pixels, updated.minScrollExtent);
    expect(
      find.byKey(const ValueKey<String>('queue:Pure Powder Reagent')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);

    await harness.controller.dispose();
  });

  testWidgets('200% dense themes keep Bonus actions content-sized', (
    tester,
  ) async {
    await setPlannerTestSize(tester, const Size(1200, 752));
    for (final spec in <ThemeSpec>[
      IlluminatedLedgerSpec.theme,
      SakuraNightGardenSpec.theme,
    ]) {
      final harness = PlannerTestHarness();
      await tester.pumpWidget(
        _fullThemeHost(harness, spec, textScaler: const TextScaler.linear(2)),
      );
      await tester.pump(const Duration(milliseconds: 200));

      final command = tester.getRect(
        find.byWidgetPredicate(
          (widget) =>
              widget is AppSurface &&
              widget.semanticLabel == 'Bonus recipe commands',
        ),
      );
      final target = tester.getRect(find.byKey(BonusActionKeys.b01));
      final amount = tester.getRect(find.byKey(BonusActionKeys.b02));
      final recipes = tester.getRect(find.byKey(BonusActionKeys.b03));
      final rebuild = tester.getRect(find.byKey(BonusActionKeys.b04));
      final finalAction = tester.getRect(find.byKey(BonusActionKeys.b05));

      expect(amount.width, lessThan(220));
      expect(amount.top, greaterThan(target.bottom));
      expect(recipes.top, greaterThan(amount.bottom));
      expect(recipes.width, lessThan(command.width / 2));
      expect(rebuild.width, lessThan(100));
      expect(finalAction.width, lessThan(command.width / 2));
      for (final label in <String>['Recipes', 'Use As Target']) {
        final paragraph = tester.renderObject<RenderParagraph>(
          find.text(label),
        );
        expect(
          paragraph.didExceedMaxLines,
          isFalse,
          reason: '$label ${spec.id}',
        );
      }
      expect(tester.takeException(), isNull);
      await harness.controller.dispose();
    }
  });

  testWidgets('200% text stacks flexible bonus command controls', (
    tester,
  ) async {
    await setPlannerTestSize(tester, const Size(1200, 752));
    final harness = PlannerTestHarness();

    await tester.pumpWidget(
      harness.bonusHost(textScaler: TextScaler.linear(2)),
    );
    await tester.pump(const Duration(milliseconds: 200));

    final target = tester.getRect(find.byKey(BonusActionKeys.b01));
    final amount = tester.getRect(find.byKey(BonusActionKeys.b02));
    final recipes = tester.getRect(find.byKey(BonusActionKeys.b03));
    final finalAction = tester.getRect(find.byKey(BonusActionKeys.b05));
    expect(target.height, greaterThan(46));
    expect(amount.height, greaterThan(46));
    expect(recipes.height, greaterThanOrEqualTo(46));
    expect(finalAction.height, greaterThanOrEqualTo(46));
    final recipesLabel = tester.getRect(
      find.descendant(
        of: find.byKey(BonusActionKeys.b03),
        matching: find.text('Recipes'),
      ),
    );
    expect(recipes.top, lessThanOrEqualTo(recipesLabel.top));
    expect(recipes.bottom, greaterThanOrEqualTo(recipesLabel.bottom));
    expect(amount.top, greaterThan(target.bottom));
    expect(recipes.top, greaterThan(amount.bottom));
    expect(tester.takeException(), isNull);

    await harness.controller.dispose();
  });

  testWidgets('bonus uses only quest pool and can move the result to Planner', (
    tester,
  ) async {
    await setPlannerTestSize(tester, const Size(1200, 752));
    final harness = PlannerTestHarness();

    await tester.pumpWidget(harness.bonusHost());
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.byKey(BonusActionKeys.b01), findsOneWidget);
    expect(find.byKey(BonusActionKeys.b07), findsOneWidget);
    expect(find.textContaining('Done'), findsNothing);

    final amount = find.descendant(
      of: find.byKey(BonusActionKeys.b02),
      matching: find.byType(TextField),
    );
    await tester.enterText(amount, '14.9');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump(const Duration(milliseconds: 200));
    expect(harness.controller.active.state.value.bonusWant, 14);

    await tester.tap(find.byKey(BonusActionKeys.b03));
    await tester.pump();
    expect(harness.recipeRequests.single.allowedTargets, hasLength(3));
    expect(harness.recipeRequests.single.context.name, 'bonus');

    await tester.tap(find.byKey(BonusActionKeys.b05));
    await tester.pump(const Duration(milliseconds: 200));
    final state = harness.controller.active.state.value;
    expect(state.target, state.bonusTarget);
    expect(state.want, 14);
    expect(state.view, 'plan');
    expect(tester.takeException(), isNull);
    await harness.controller.dispose();
  });

  testWidgets(
    'empty quest pool hides editor actions until advanced tools are enabled',
    (tester) async {
      await setPlannerTestSize(tester, const Size(1200, 752));
      final empty = PlannerTestHarness(emptyAlchemyBonusPool: true);
      await tester.pumpWidget(empty.bonusHost());
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.byKey(BonusActionKeys.b06), findsNothing);
      expect(find.textContaining('Add the quest recipe'), findsNothing);

      final advanced = PlannerTestHarness(
        emptyAlchemyBonusPool: true,
        showAdvancedEditor: true,
      );
      await tester.pumpWidget(advanced.bonusHost());
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.byKey(BonusActionKeys.b06), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(BonusActionKeys.b06),
          matching: _glyph('edit'),
        ),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey<String>('bonus-empty-path')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey<String>('bonus-empty-need')),
        findsOneWidget,
      );
      expect(find.text('No bonus quest recipe data'), findsOneWidget);
      expect(
        find.textContaining('No alchemy bonus quest formulas'),
        findsOneWidget,
      );
      expect(
        find.textContaining('Bonus quest materials will appear here'),
        findsOneWidget,
      );
      expect(find.text('Open Recipe Editor'), findsNothing);
      await tester.tap(find.byKey(BonusActionKeys.b06));
      await tester.pump(const Duration(milliseconds: 200));
      expect(advanced.controller.active.state.value.view, 'editor');

      final processing = PlannerTestHarness(activeMode: CraftMode.processing);
      await tester.pumpWidget(processing.bonusHost());
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.byKey(BonusActionKeys.b01), findsNothing);
      expect(find.byKey(BonusActionKeys.b07), findsNothing);
      expect(find.bySemanticsLabel('Processing Bonus Recipes'), findsNothing);
      expect(tester.takeException(), isNull);
      await empty.controller.dispose();
      await advanced.controller.dispose();
      await processing.controller.dispose();
    },
  );
}

Widget _ledgerHost(PlannerTestHarness harness) => MaterialApp(
  theme: IlluminatedLedgerSpec.theme.materialTheme(),
  home: ThemeSpecScope(
    spec: IlluminatedLedgerSpec.theme,
    child: Scaffold(
      body: ColoredBox(
        color: IlluminatedLedgerSpec.palette.canvas,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: BonusView(
            controller: harness.controller.active,
            externalActions: harness.actions,
          ),
        ),
      ),
    ),
  ),
);

Widget _fullThemeHost(
  PlannerTestHarness harness,
  ThemeSpec spec, {
  TextScaler? textScaler,
}) => MaterialApp(
  builder: textScaler == null
      ? null
      : (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: textScaler),
          child: child!,
        ),
  theme: spec.materialTheme(),
  home: ThemeSpecScope(
    spec: spec,
    child: Scaffold(
      body: ColoredBox(
        color: spec.palette.canvas,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: BonusView(
            controller: harness.controller.active,
            externalActions: harness.actions,
          ),
        ),
      ),
    ),
  ),
);

Finder _glyph(String name) => find.byWidgetPredicate(
  (widget) => widget is AppVectorGlyph && widget.name == name,
);

Rect _inputContainerRect(WidgetTester tester, Finder fieldAncestor) {
  final editable = find.descendant(
    of: fieldAncestor,
    matching: find.byType(EditableText),
  );
  final container = InputDecorator.containerOf(tester.element(editable))!;
  return container.localToGlobal(Offset.zero) & container.size;
}
