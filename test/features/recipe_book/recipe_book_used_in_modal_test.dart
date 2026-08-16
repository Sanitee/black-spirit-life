import 'package:bdo_craft_planner_flutter/app/state/planner_application_controller.dart';
import 'package:bdo_craft_planner_flutter/data/catalog/catalog_repository.dart';
import 'package:bdo_craft_planner_flutter/domain/models/catalog_models.dart';
import 'package:bdo_craft_planner_flutter/domain/models/craft_mode.dart';
import 'package:bdo_craft_planner_flutter/domain/state/planner_state.dart';
import 'package:bdo_craft_planner_flutter/features/planner/planner_contracts.dart';
import 'package:bdo_craft_planner_flutter/features/recipe_book/recipe_book.dart';
import 'package:bdo_craft_planner_flutter/features/recipe_book/recipe_book_used_in_panel.dart';
import 'package:bdo_craft_planner_flutter/features/shared/mode_item_icon.dart';
import 'package:bdo_craft_planner_flutter/features/shared/recipe_variant_selector.dart';
import 'package:bdo_craft_planner_flutter/visual/visual.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'recipe_book_test_support.dart' show testIconDataUri;

typedef _ThemeCase = ({String name, ThemeSpec spec});

const String _source = 'Catalyst Core';
const String _currentResult = 'Current Tonic';
const String _crossModeResult = 'Cross-Mode Feast';
const String _crossModeVariant = 'catalyst-10x';

void main() {
  const themes = <_ThemeCase>[
    (name: 'Standard', spec: StandardSpec.theme),
    (name: 'Sakura', spec: SakuraNightGardenSpec.theme),
    (name: 'Ledger', spec: IlluminatedLedgerSpec.theme),
  ];
  const sizes = <Size>[Size(1200, 752), Size(1500, 940)];

  for (final theme in themes) {
    for (final size in sizes) {
      testWidgets('${theme.name} Used In panel stays in the '
          '${size.width.toInt()}x${size.height.toInt()} viewport', (
        tester,
      ) async {
        await _setSize(tester, size);
        final environment = _buildEnvironment();
        final book = _bookFor(environment, CraftMode.alchemy);
        addTearDown(book.dispose);
        addTearDown(environment.dispose);

        await tester.pumpWidget(
          _host(
            RecipeBookModal(
              controller: book,
              onClose: () {},
              onActivated: (_) {},
            ),
            spec: theme.spec,
          ),
        );
        await tester.pumpAndSettle();

        final action = find.byKey(RecipeBookKeys.usedIn(_source));
        final card = find.byKey(RecipeBookKeys.card(_source));
        expect(action, findsOneWidget);
        expect(card, findsOneWidget);
        _expectContained(tester.getRect(card), tester.getRect(action));

        final expectedRole = theme.spec.isIlluminatedLedger
            ? AppButtonRole.primary
            : theme.spec.isSakuraNightGarden
            ? AppButtonRole.secondary
            : AppButtonRole.optionPill;
        expect(tester.widget<AppButton>(action).role, expectedRole);

        await tester.tap(action);
        await tester.pump();

        final panel = find.byKey(RecipeBookKeys.usedInPanel(_source));
        expect(panel, findsOneWidget);
        final panelRect = tester.getRect(panel);
        expect(panelRect.left, greaterThanOrEqualTo(12));
        expect(panelRect.top, greaterThanOrEqualTo(12));
        expect(panelRect.right, lessThanOrEqualTo(size.width - 12));
        expect(panelRect.bottom, lessThanOrEqualTo(size.height - 12));
        expect(find.text('Used In'), findsOneWidget);
        expect(find.textContaining('21 recipe paths'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets(
    'Used In scrolls, expands exact ingredient cards, and every dismissal is layered',
    (tester) async {
      await _setSize(tester, const Size(1200, 752));
      final environment = _buildEnvironment();
      final mode = environment.application.modes[CraftMode.alchemy]!;
      final book = _bookFor(environment, CraftMode.alchemy);
      addTearDown(book.dispose);
      addTearDown(environment.dispose);
      var closeCount = 0;
      final activations = <RecipeBookActivation>[];

      await tester.pumpWidget(
        _host(
          RecipeBookModal(
            controller: book,
            onClose: () => closeCount += 1,
            onActivated: activations.add,
          ),
        ),
      );
      await tester.pumpAndSettle();
      final originalTarget = mode.state.value.target;

      await _openUsedIn(tester);
      final panel = find.byKey(RecipeBookKeys.usedInPanel(_source));
      final scroll = find.byKey(RecipeBookKeys.usedInScroll(_source));
      expect(panel, findsOneWidget);
      expect(scroll, findsOneWidget);
      final scrollable = find.descendant(
        of: scroll,
        matching: find.byType(Scrollable),
      );
      expect(scrollable, findsOneWidget);
      expect(
        find.descendant(of: panel, matching: find.byType(Scrollbar)),
        findsNothing,
      );
      expect(
        find.descendant(of: panel, matching: find.byType(RawScrollbar)),
        findsNothing,
      );
      final position = tester.state<ScrollableState>(scrollable).position;
      expect(position.maxScrollExtent, greaterThan(0));
      final before = position.pixels;
      await tester.sendEventToBinding(
        PointerScrollEvent(
          viewId: tester.view.viewId,
          kind: PointerDeviceKind.mouse,
          position: tester.getCenter(panel),
          scrollDelta: const Offset(0, 220),
        ),
      );
      await tester.pumpAndSettle();
      expect(position.pixels, greaterThan(before));

      final expand = find.byKey(
        RecipeBookKeys.expandUsedInResult(
          _source,
          CraftMode.cooking.key,
          _crossModeResult,
        ),
      );
      final target = find.byKey(
        RecipeBookKeys.targetUsedInResult(
          _source,
          CraftMode.cooking.key,
          _crossModeResult,
        ),
      );
      await tester.scrollUntilVisible(expand, 180, scrollable: scrollable);
      await tester.pumpAndSettle();
      final targetRect = tester.getRect(target);
      final expandRect = tester.getRect(expand);
      expect(expandRect.left, greaterThanOrEqualTo(targetRect.right));
      expect(
        (expandRect.center.dy - targetRect.center.dy).abs(),
        lessThanOrEqualTo(1),
      );
      await tester.tap(expand);
      await tester.pumpAndSettle();
      final expandedResult = find.byKey(
        RecipeBookKeys.usedInResult(
          _source,
          CraftMode.cooking.key,
          _crossModeResult,
        ),
      );
      expect(
        find.descendant(
          of: expandedResult,
          matching: find.text('Catalyst Core'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(of: expandedResult, matching: find.text('Need 2')),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: expandedResult,
          matching: find.text('Makes 10 Cross-Mode Feast'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(of: expandedResult, matching: find.text('2')),
        findsNothing,
      );
      expect(
        find.descendant(
          of: expandedResult,
          matching: find.byType(ModeItemIcon),
        ),
        findsNWidgets(2),
      );

      await tester.tap(find.byKey(RecipeBookKeys.closeUsedIn(_source)));
      await tester.pump();
      _expectDismissedWithoutMutation(
        tester,
        mode: mode,
        expectedTarget: originalTarget,
        closeCount: closeCount,
        activations: activations,
      );

      await _openUsedIn(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      _expectDismissedWithoutMutation(
        tester,
        mode: mode,
        expectedTarget: originalTarget,
        closeCount: closeCount,
        activations: activations,
      );

      await _openUsedIn(tester);
      await tester.tapAt(const Offset(8, 8));
      await tester.pump();
      _expectDismissedWithoutMutation(
        tester,
        mode: mode,
        expectedTarget: originalTarget,
        closeCount: closeCount,
        activations: activations,
      );
      expect(tester.takeException(), isNull);
    },
  );

  test(
    'direct Used In activation returns before deferred projection work',
    () async {
      final environment = _buildEnvironment();
      final book = _bookFor(environment, CraftMode.alchemy);
      final entry = book
          .usedInFor(_source)
          .entries
          .singleWhere(
            (candidate) =>
                candidate.mode == CraftMode.alchemy &&
                candidate.name == _currentResult,
          );

      final activation = book.activateUsedIn(entry);

      expect(activation?.exactName, _currentResult);
      expect(
        environment.application.modes[CraftMode.alchemy]!.state.value.target,
        _currentResult,
      );
      expect(book.snapshot.pageCount, 1);
      await Future<void>.delayed(Duration.zero);
      expect(book.snapshot.pageCount, 1);
      book.dispose();
      await environment.dispose();
    },
  );

  testWidgets('a short Used In list uses a compact readable panel', (
    tester,
  ) async {
    await _setSize(tester, const Size(1500, 940));
    final environment = _buildEnvironment();
    final book = _bookFor(environment, CraftMode.alchemy);
    addTearDown(book.dispose);
    addTearDown(environment.dispose);
    final snapshot = book.usedInFor('Base Dust');
    expect(snapshot.entries, hasLength(1));

    await tester.pumpWidget(
      _host(
        Center(
          child: SizedBox(
            width: 570,
            child: RecipeBookUsedInPanel(
              controller: book,
              sourceName: 'Base Dust',
              snapshot: snapshot,
              onClose: () {},
              onActivate: (_, _) => true,
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    final panel = find.byKey(RecipeBookKeys.usedInPanel('Base Dust'));
    expect(panel, findsOneWidget);
    final size = tester.getSize(panel);
    expect(size.width, 570);
    expect(size.height, inInclusiveRange(230, 390));
    expect(find.text('1 recipe path'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'Used In keeps recipe and batch as independent compact selectors',
    (tester) async {
      await _setSize(tester, const Size(1200, 752));
      final environment = _buildEnvironment();
      final cooking = environment.application.modes[CraftMode.cooking]!;
      final book = _bookFor(environment, CraftMode.alchemy);
      addTearDown(book.dispose);
      addTearDown(environment.dispose);
      final activations = <RecipeBookActivation>[];

      await tester.pumpWidget(
        _host(
          RecipeBookModal(
            controller: book,
            onClose: () {},
            onActivated: activations.add,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await _openUsedIn(tester);

      final scrollable = find.descendant(
        of: find.byKey(RecipeBookKeys.usedInScroll(_source)),
        matching: find.byType(Scrollable),
      );
      final expand = find.byKey(
        RecipeBookKeys.expandUsedInResult(
          _source,
          CraftMode.cooking.key,
          _crossModeResult,
        ),
      );
      await tester.scrollUntilVisible(expand, 180, scrollable: scrollable);
      await tester.tap(expand);
      await tester.pumpAndSettle();

      final result = find.byKey(
        RecipeBookKeys.usedInResult(
          _source,
          CraftMode.cooking.key,
          _crossModeResult,
        ),
      );
      final selectorNamespace =
          'used-in:$_source:${CraftMode.cooking.key}:$_crossModeResult';
      final catalyst = find.byKey(
        RecipeVariantSelector.routeChoiceKey(
          _crossModeResult,
          'catalyst',
          keyNamespace: selectorNamespace,
        ),
      );
      final alternate = find.byKey(
        RecipeVariantSelector.routeChoiceKey(
          _crossModeResult,
          'alternate',
          keyNamespace: selectorNamespace,
        ),
      );
      final single = find.byKey(
        RecipeVariantSelector.batchChoiceKey(
          _crossModeResult,
          1,
          keyNamespace: selectorNamespace,
        ),
      );
      final ten = find.byKey(
        RecipeVariantSelector.batchChoiceKey(
          _crossModeResult,
          10,
          keyNamespace: selectorNamespace,
        ),
      );
      expect(catalyst, findsOneWidget);
      expect(alternate, findsOneWidget);
      expect(single, findsOneWidget);
      expect(ten, findsOneWidget);
      expect(
        find.byKey(
          RecipeVariantSelector.routeChoiceKey(
            _crossModeResult,
            'plain',
            keyNamespace: selectorNamespace,
          ),
        ),
        findsNothing,
      );
      expect(
        find.descendant(of: catalyst, matching: find.text('B')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: alternate, matching: find.text('C')),
        findsOneWidget,
      );
      expect(_appButton(tester, catalyst).selected, isTrue);
      expect(_appButton(tester, ten).selected, isTrue);
      expect(
        find.descendant(of: result, matching: find.text('Need 2')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: result, matching: find.text('Need 30')),
        findsNothing,
      );

      await tester.tap(alternate);
      await tester.pumpAndSettle();
      expect(
        cooking.selectedRecipeVariantId(_crossModeResult),
        _crossModeVariant,
      );
      expect(_appButton(tester, alternate).selected, isTrue);
      expect(_appButton(tester, ten).selected, isTrue);
      expect(
        find.descendant(of: result, matching: find.text('Need 30')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: result, matching: find.text('Cooking Base')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: result, matching: find.text('Need 2')),
        findsNothing,
      );

      await tester.tap(single);
      await tester.pumpAndSettle();
      expect(
        cooking.selectedRecipeVariantId(_crossModeResult),
        _crossModeVariant,
      );
      expect(_appButton(tester, alternate).selected, isTrue);
      expect(_appButton(tester, single).selected, isTrue);
      expect(
        find.descendant(of: result, matching: find.text('Need 3')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: result, matching: find.text('Need 30')),
        findsNothing,
      );

      await tester.tap(catalyst);
      await tester.pumpAndSettle();
      expect(
        cooking.selectedRecipeVariantId(_crossModeResult),
        _crossModeVariant,
      );
      expect(_appButton(tester, catalyst).selected, isTrue);
      expect(_appButton(tester, single).selected, isTrue);
      expect(
        find.descendant(of: result, matching: find.text('Cooking Base')),
        findsNothing,
      );
      expect(
        find.descendant(of: result, matching: find.text('Need 1')),
        findsOneWidget,
      );

      await tester.tap(alternate);
      await tester.pumpAndSettle();
      expect(_appButton(tester, alternate).selected, isTrue);
      expect(_appButton(tester, single).selected, isTrue);
      expect(
        cooking.selectedRecipeVariantId(_crossModeResult),
        _crossModeVariant,
      );

      await tester.tap(
        find.byKey(
          RecipeBookKeys.targetUsedInResult(
            _source,
            CraftMode.cooking.key,
            _crossModeResult,
          ),
        ),
      );
      await tester.pump();

      expect(environment.application.activeMode.value, CraftMode.cooking);
      expect(cooking.state.value.target, _crossModeResult);
      expect(cooking.selectedRecipeVariantId(_crossModeResult), 'alternate-1x');
      expect(
        cooking.state.value.recipeVariantChoices[_crossModeResult],
        'alternate-1x',
      );
      expect(activations, hasLength(1));
      expect(activations.single.exactName, _crossModeResult);
      expect(activations.single.mode, CraftMode.cooking);
      expect(activations.single.variantId, 'alternate-1x');
      expect(find.byKey(RecipeBookKeys.usedInPanel(_source)), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Used In item info stays mode-aware and dismisses one layer at a time',
    (tester) async {
      await _setSize(tester, const Size(1200, 752));
      final environment = _buildEnvironment();
      final alchemy = environment.application.modes[CraftMode.alchemy]!;
      final cooking = environment.application.modes[CraftMode.cooking]!;
      final book = _bookFor(environment, CraftMode.alchemy);
      addTearDown(book.dispose);
      addTearDown(environment.dispose);
      final activations = <RecipeBookActivation>[];
      var closeCount = 0;
      final originalAlchemyTarget = alchemy.state.value.target;
      final originalCookingTarget = cooking.state.value.target;

      await tester.pumpWidget(
        _host(
          RecipeBookModal(
            controller: book,
            onClose: () => closeCount += 1,
            onActivated: activations.add,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await _openUsedIn(tester);

      final panel = find.byKey(RecipeBookKeys.usedInPanel(_source));
      final scrollable = find.descendant(
        of: find.byKey(RecipeBookKeys.usedInScroll(_source)),
        matching: find.byType(Scrollable),
      );
      final expand = find.byKey(
        RecipeBookKeys.expandUsedInResult(
          _source,
          CraftMode.cooking.key,
          _crossModeResult,
        ),
      );
      await tester.scrollUntilVisible(expand, 180, scrollable: scrollable);
      await tester.tap(expand);
      await tester.pumpAndSettle();

      final result = find.byKey(
        RecipeBookKeys.usedInResult(
          _source,
          CraftMode.cooking.key,
          _crossModeResult,
        ),
      );
      final itemIcons = tester
          .widgetList<RecipeBookItemIcon>(
            find.descendant(
              of: result,
              matching: find.byType(RecipeBookItemIcon),
            ),
          )
          .toList(growable: false);
      final outputIcon = itemIcons.singleWhere(
        (icon) => icon.name == _crossModeResult,
      );
      final ingredientIcon = itemIcons.singleWhere(
        (icon) =>
            icon.name == _source && icon.anchorId.contains(':ingredient:'),
      );
      expect(outputIcon.mode, CraftMode.cooking);
      expect(ingredientIcon.mode, CraftMode.cooking);

      final outputAnchor = find.byKey(
        RecipeBookKeys.itemInfoAnchor(outputIcon.name, outputIcon.anchorId),
      );
      final ingredientAnchor = find.byKey(
        RecipeBookKeys.itemInfoAnchor(
          ingredientIcon.name,
          ingredientIcon.anchorId,
        ),
      );
      expect(outputAnchor, findsOneWidget);
      expect(ingredientAnchor, findsOneWidget);
      expect(
        tester
            .widget<ModeItemIcon>(
              find.descendant(
                of: outputAnchor,
                matching: find.byType(ModeItemIcon),
              ),
            )
            .controller,
        same(cooking),
      );
      expect(
        tester
            .widget<ModeItemIcon>(
              find.descendant(
                of: ingredientAnchor,
                matching: find.byType(ModeItemIcon),
              ),
            )
            .controller,
        same(cooking),
      );

      final outputTooltip = find.descendant(
        of: outputAnchor,
        matching: find.byWidgetPredicate(
          (widget) => widget is Tooltip && widget.richMessage != null,
        ),
      );
      expect(outputTooltip, findsOneWidget);
      tester.state<TooltipState>(outputTooltip).ensureTooltipVisible();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 180));
      expect(
        find.byKey(RecipeBookKeys.itemInfo(_crossModeResult)),
        findsOneWidget,
      );
      expect(panel, findsOneWidget);
      expect(activations, isEmpty);
      Tooltip.dismissAllToolTips();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 180));

      await tester.tap(outputAnchor);
      await tester.pump();
      final pinnedOutput = find.byKey(
        RecipeBookKeys.pinnedItemInfo(outputIcon.name, outputIcon.anchorId),
      );
      expect(pinnedOutput, findsOneWidget);
      expect(panel, findsOneWidget);
      final pinnedRect = tester.getRect(pinnedOutput);
      expect(pinnedRect.left, greaterThanOrEqualTo(12));
      expect(pinnedRect.top, greaterThanOrEqualTo(12));
      expect(pinnedRect.right, lessThanOrEqualTo(1188));
      expect(pinnedRect.bottom, lessThanOrEqualTo(740));
      expect(activations, isEmpty);

      await tester.tap(
        find.byKey(
          RecipeBookKeys.closePinnedItemInfo(
            outputIcon.name,
            outputIcon.anchorId,
          ),
        ),
      );
      await tester.pump();
      expect(pinnedOutput, findsNothing);
      expect(panel, findsOneWidget);

      await tester.ensureVisible(ingredientAnchor);
      await tester.pumpAndSettle();
      final ingredientTooltip = find.descendant(
        of: ingredientAnchor,
        matching: find.byWidgetPredicate(
          (widget) => widget is Tooltip && widget.richMessage != null,
        ),
      );
      expect(ingredientTooltip, findsOneWidget);
      tester.state<TooltipState>(ingredientTooltip).ensureTooltipVisible();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 180));
      final ingredientHover = find.byKey(RecipeBookKeys.itemInfo(_source));
      expect(ingredientHover, findsOneWidget);
      final cookingFormula = find.descendant(
        of: ingredientHover,
        matching: find.byKey(RecipeBookKeys.itemInfoFormula(_source, null, 1)),
      );
      expect(
        find.descendant(of: cookingFormula, matching: find.text('Cooking')),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: ingredientHover,
          matching: find.byKey(
            RecipeBookKeys.itemInfoMaterial(_source, null, 'Cooking Base'),
          ),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: ingredientHover,
          matching: find.byKey(
            RecipeBookKeys.itemInfoMaterial(_source, null, 'Base Dust'),
          ),
        ),
        findsNothing,
      );
      expect(panel, findsOneWidget);
      Tooltip.dismissAllToolTips();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 180));

      await tester.tap(ingredientAnchor);
      await tester.pump();
      final pinnedIngredient = find.byKey(
        RecipeBookKeys.pinnedItemInfo(
          ingredientIcon.name,
          ingredientIcon.anchorId,
        ),
      );
      expect(pinnedIngredient, findsOneWidget);
      expect(panel, findsOneWidget);
      await tester.tapAt(const Offset(8, 8));
      await tester.pump();
      expect(pinnedIngredient, findsNothing);
      expect(panel, findsOneWidget);
      expect(activations, isEmpty);

      await tester.tapAt(const Offset(8, 8));
      await tester.pump();
      expect(panel, findsNothing);
      expect(find.byKey(RecipeBookKeys.modal), findsOneWidget);
      expect(closeCount, 0);

      await _openUsedIn(tester);
      final reopenedScroll = find.descendant(
        of: find.byKey(RecipeBookKeys.usedInScroll(_source)),
        matching: find.byType(Scrollable),
      );
      final reopenedOutputAnchor = find.byKey(
        RecipeBookKeys.itemInfoAnchor(outputIcon.name, outputIcon.anchorId),
      );
      await tester.scrollUntilVisible(
        reopenedOutputAnchor,
        180,
        scrollable: reopenedScroll,
      );
      await tester.tap(reopenedOutputAnchor);
      await tester.pump();
      expect(pinnedOutput, findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(pinnedOutput, findsNothing);
      expect(panel, findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(panel, findsNothing);
      expect(find.byKey(RecipeBookKeys.modal), findsOneWidget);

      expect(alchemy.state.value.target, originalAlchemyTarget);
      expect(cooking.state.value.target, originalCookingTarget);
      expect(activations, isEmpty);
      expect(closeCount, 0);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Used In targets current and cross-mode recipes with the matching variant',
    (tester) async {
      await _setSize(tester, const Size(1500, 940));
      final environment = _buildEnvironment();
      final alchemy = environment.application.modes[CraftMode.alchemy]!;
      final cooking = environment.application.modes[CraftMode.cooking]!;
      final book = _bookFor(environment, CraftMode.alchemy);
      addTearDown(book.dispose);
      addTearDown(environment.dispose);
      final activations = <RecipeBookActivation>[];

      await tester.pumpWidget(
        _host(
          RecipeBookModal(
            controller: book,
            onClose: () {},
            onActivated: activations.add,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await _openUsedIn(tester);
      await tester.tap(
        find.byKey(
          RecipeBookKeys.targetUsedInResult(
            _source,
            CraftMode.alchemy.key,
            _currentResult,
          ),
        ),
      );
      await tester.pump();
      expect(alchemy.state.value.target, _currentResult);
      expect(environment.application.activeMode.value, CraftMode.alchemy);
      expect(activations, hasLength(1));
      expect(activations.single.exactName, _currentResult);
      expect(activations.single.mode, CraftMode.alchemy);
      expect(find.byKey(RecipeBookKeys.usedInPanel(_source)), findsNothing);

      await _openUsedIn(tester);
      final crossModeTarget = find.byKey(
        RecipeBookKeys.targetUsedInResult(
          _source,
          CraftMode.cooking.key,
          _crossModeResult,
        ),
      );
      final usedInScrollable = find.descendant(
        of: find.byKey(RecipeBookKeys.usedInScroll(_source)),
        matching: find.byType(Scrollable),
      );
      await tester.scrollUntilVisible(
        crossModeTarget,
        180,
        scrollable: usedInScrollable,
      );
      await tester.pumpAndSettle();
      await tester.tap(crossModeTarget);
      await tester.pump();

      expect(environment.application.activeMode.value, CraftMode.cooking);
      expect(cooking.state.value.target, _crossModeResult);
      expect(
        cooking.selectedRecipeVariantId(_crossModeResult),
        _crossModeVariant,
      );
      expect(
        cooking.state.value.recipeVariantChoices[_crossModeResult],
        _crossModeVariant,
      );
      expect(cooking.state.value.view, 'plan');
      expect(cooking.state.value.completedSteps, isEmpty);
      expect(activations, hasLength(2));
      expect(activations.last.exactName, _crossModeResult);
      expect(activations.last.mode, CraftMode.cooking);
      expect(activations.last.variantId, _crossModeVariant);
      expect(tester.takeException(), isNull);
    },
  );

  for (final theme in themes) {
    testWidgets(
      '${theme.name} compact Processing cards retain stock and three actions',
      (tester) async {
        await _setSize(tester, const Size(1200, 752));
        final environment = _buildEnvironment(activeMode: CraftMode.processing);
        final mode = environment.application.modes[CraftMode.processing]!;
        final book = RecipeBookController(
          modeController: mode,
          catalogRepository: environment.catalogRepository,
          callingContext: RecipeBookCallingContext.planner,
          allowedTargets: mode.craftableNames,
          checkPrices: (request) async {
            final names = request.namesForRefresh.toSet();
            return PlannerMarketRefresh(
              prices: <String, double>{for (final name in names) name: 25},
              stock: <String, double>{for (final name in names) name: 125},
              unlistedItemNames: const <String>{},
              fetchedAt: 42,
              summary: 'Market stock updated.',
            );
          },
        );
        addTearDown(book.dispose);
        addTearDown(environment.dispose);
        book.setDensity(RecipeBookDensity.sixByFive);
        final marketCheck = book.checkMarket();
        await tester.pump(const Duration(milliseconds: 60));
        await marketCheck;

        await tester.pumpWidget(
          _host(
            RecipeBookModal(
              controller: book,
              onClose: () {},
              onActivated: (_) {},
            ),
            spec: theme.spec,
          ),
        );
        await tester.pumpAndSettle();

        final card = find.byKey(RecipeBookKeys.card(_source));
        final details = find.byKey(RecipeBookKeys.r13Details(_source));
        final usedIn = find.byKey(RecipeBookKeys.usedIn(_source));
        final favorite = find.byKey(RecipeBookKeys.r12Favorite(_source));
        final target = find.byKey(RecipeBookKeys.r11Target(_source));
        expect(card, findsOneWidget);
        expect(details, findsOneWidget);
        expect(usedIn, findsOneWidget);
        expect(favorite, findsOneWidget);
        expect(target, findsOneWidget);

        final cardRect = tester.getRect(card);
        final detailsRect = tester.getRect(details);
        final usedInRect = tester.getRect(usedIn);
        final favoriteRect = tester.getRect(favorite);
        final targetRect = tester.getRect(target);
        for (final actionRect in <Rect>[
          detailsRect,
          usedInRect,
          favoriteRect,
          targetRect,
        ]) {
          _expectContained(cardRect, actionRect);
        }
        expect(detailsRect.right, lessThanOrEqualTo(usedInRect.left));
        expect(favoriteRect.bottom, lessThanOrEqualTo(usedInRect.top));
        expect(
          (usedInRect.right - favoriteRect.right).abs(),
          lessThanOrEqualTo(1),
        );
        expect(
          (detailsRect.center.dy - targetRect.center.dy).abs(),
          lessThanOrEqualTo(1),
        );
        expect(
          (usedInRect.center.dy - targetRect.center.dy).abs(),
          lessThanOrEqualTo(1),
        );
        expect(tester.getSize(usedIn), const Size.square(26));

        final stockText = find.descendant(of: card, matching: find.text('125'));
        expect(stockText, findsOneWidget);
        expect(
          tester.renderObject<RenderParagraph>(stockText).didExceedMaxLines,
          isFalse,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }
}

Future<void> _openUsedIn(WidgetTester tester) async {
  final action = find.byKey(RecipeBookKeys.usedIn(_source));
  await tester.ensureVisible(action);
  await tester.tap(action);
  await tester.pump();
  expect(find.byKey(RecipeBookKeys.usedInPanel(_source)), findsOneWidget);
}

void _expectDismissedWithoutMutation(
  WidgetTester tester, {
  required ModeFeatureController mode,
  required String expectedTarget,
  required int closeCount,
  required List<RecipeBookActivation> activations,
}) {
  expect(find.byKey(RecipeBookKeys.usedInPanel(_source)), findsNothing);
  expect(find.byKey(RecipeBookKeys.modal), findsOneWidget);
  expect(mode.state.value.target, expectedTarget);
  expect(closeCount, 0);
  expect(activations, isEmpty);
}

void _expectContained(Rect outer, Rect inner) {
  expect(inner.left, greaterThanOrEqualTo(outer.left));
  expect(inner.top, greaterThanOrEqualTo(outer.top));
  expect(inner.right, lessThanOrEqualTo(outer.right));
  expect(inner.bottom, lessThanOrEqualTo(outer.bottom));
}

AppButton _appButton(WidgetTester tester, Finder owner) =>
    tester.widget<AppButton>(
      find.descendant(of: owner, matching: find.byType(AppButton)),
    );

Future<void> _setSize(WidgetTester tester, Size size) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
}

Widget _host(Widget child, {ThemeSpec spec = StandardSpec.theme}) =>
    MaterialApp(
      theme: spec.materialTheme(),
      home: ThemeSpecScope(
        spec: spec,
        child: Scaffold(body: child),
      ),
    );

RecipeBookController _bookFor(
  _UsedInTestEnvironment environment,
  CraftMode mode,
) {
  final controller = environment.application.modes[mode]!;
  return RecipeBookController(
    modeController: controller,
    catalogRepository: environment.catalogRepository,
    callingContext: RecipeBookCallingContext.planner,
    allowedTargets: controller.craftableNames,
  );
}

_UsedInTestEnvironment _buildEnvironment({
  CraftMode activeMode = CraftMode.alchemy,
  bool showDeleteTools = false,
}) {
  final catalog = _catalog();
  final application = PlannerApplicationController(
    catalog: catalog,
    initialState: PlannerState(
      applicationVersion: 'recipe-book-used-in-test',
      lastSuccessfulWriteUtc: DateTime.utc(2026, 7, 26),
      activeMode: activeMode,
      alchemy: _modeState(
        CraftMode.alchemy,
        target: _source,
        bonusTarget: _currentResult,
      ),
      cooking: _modeState(
        CraftMode.cooking,
        target: 'Cooking Use 01',
        bonusTarget: _crossModeResult,
        recipeVariantChoices: const <String, String>{
          _crossModeResult: _crossModeVariant,
        },
      ),
      processing: _modeState(
        CraftMode.processing,
        target: _source,
        bonusTarget: '',
      ),
      processingYields: const <String, double>{'defaultYield': 2.5},
      marketTax: MarketTax(),
      showDeleteTools: showDeleteTools,
    ),
    saveDebounce: Duration.zero,
    saveState: (value) async => value,
  );
  return _UsedInTestEnvironment(
    application: application,
    catalogRepository: CatalogRepository(catalog),
  );
}

CatalogSnapshot _catalog() {
  final alchemy = <String, Recipe>{
    _source: _production(
      _source,
      CraftMode.alchemy,
      ingredients: <Ingredient>[_ingredient('Base Dust', 1)],
      marketId: '1000',
    ),
    _currentResult: _production(
      _currentResult,
      CraftMode.alchemy,
      ingredients: <Ingredient>[_ingredient(_source, 1)],
      marketId: '1001',
    ),
    for (var index = 1; index <= 10; index++)
      'Elixir Use ${index.toString().padLeft(2, '0')}': _production(
        'Elixir Use ${index.toString().padLeft(2, '0')}',
        CraftMode.alchemy,
        ingredients: <Ingredient>[_ingredient(_source, index.toDouble())],
        marketId: '${1010 + index}',
      ),
    'Base Dust': _leaf('Base Dust'),
  };
  final cooking = <String, Recipe>{
    _source: _production(
      _source,
      CraftMode.cooking,
      ingredients: <Ingredient>[_ingredient('Cooking Base', 1)],
      marketId: '2000',
    ),
    _crossModeResult: _production(
      _crossModeResult,
      CraftMode.cooking,
      ingredients: <Ingredient>[_ingredient('Plain Grain', 1)],
      variants: <RecipeVariant>[
        _variant(
          id: 'plain-1x',
          label: 'Plain',
          routeId: 'plain',
          mode: CraftMode.cooking,
          ingredients: <Ingredient>[_ingredient('Plain Grain', 1)],
        ),
        _variant(
          id: 'catalyst-1x',
          label: 'Catalyst',
          routeId: 'catalyst',
          mode: CraftMode.cooking,
          ingredients: <Ingredient>[_ingredient(_source, 1)],
        ),
        _variant(
          id: _crossModeVariant,
          label: 'Catalyst',
          routeId: 'catalyst',
          mode: CraftMode.cooking,
          batchMultiplier: 10,
          baseOutput: 10,
          ingredients: <Ingredient>[_ingredient(_source, 2)],
        ),
        _variant(
          id: 'alternate-1x',
          label: 'Alternate',
          routeId: 'alternate',
          mode: CraftMode.cooking,
          ingredients: <Ingredient>[
            _ingredient(_source, 3),
            _ingredient('Cooking Base', 1),
          ],
        ),
        _variant(
          id: 'alternate-10x',
          label: 'Alternate',
          routeId: 'alternate',
          mode: CraftMode.cooking,
          batchMultiplier: 10,
          baseOutput: 10,
          ingredients: <Ingredient>[
            _ingredient(_source, 30),
            _ingredient('Cooking Base', 10),
          ],
        ),
      ],
      defaultVariantId: 'plain-1x',
      marketId: '2001',
    ),
    for (var index = 1; index <= 4; index++)
      'Cooking Use ${index.toString().padLeft(2, '0')}': _production(
        'Cooking Use ${index.toString().padLeft(2, '0')}',
        CraftMode.cooking,
        ingredients: <Ingredient>[_ingredient(_source, index.toDouble())],
        marketId: '${2010 + index}',
      ),
    'Cooking Base': _leaf('Cooking Base'),
    'Plain Grain': _leaf('Plain Grain'),
  };
  final processing = <String, Recipe>{
    _source: _production(
      _source,
      CraftMode.processing,
      ingredients: <Ingredient>[_ingredient('Raw Catalyst', 1)],
      marketId: '3000',
    ),
    for (var index = 1; index <= 5; index++)
      'Processing Use ${index.toString().padLeft(2, '0')}': _production(
        'Processing Use ${index.toString().padLeft(2, '0')}',
        CraftMode.processing,
        ingredients: <Ingredient>[_ingredient(_source, index.toDouble())],
        marketId: '${3010 + index}',
      ),
    'Raw Catalyst': _leaf('Raw Catalyst'),
  };

  ModeCatalog modeCatalog(CraftMode mode, Map<String, Recipe> items) =>
      ModeCatalog(
        mode: mode,
        items: items,
        iconDataUris: <String, String>{
          for (final name in items.keys) name: testIconDataUri,
        },
        defaults: const <String, Object?>{},
        metadata: const <String, Object?>{},
        searchAliases: const <String, String>{},
      );

  return CatalogSnapshot(
    sourceSha256: 'recipe-book-used-in-fixture',
    sourceByteCount: 1,
    alchemy: modeCatalog(CraftMode.alchemy, alchemy),
    cooking: modeCatalog(CraftMode.cooking, cooking),
    processing: modeCatalog(CraftMode.processing, processing),
    supportingData: const <String, Object?>{},
    collisions: const <CaseCollision>[],
  );
}

ModeState _modeState(
  CraftMode mode, {
  required String target,
  required String bonusTarget,
  Map<String, String> recipeVariantChoices = const <String, String>{},
}) => ModeState(
  target: target,
  bonusTarget: bonusTarget,
  recipeVariantChoices: recipeVariantChoices,
  market: MarketState(),
  appearance: AppearanceSettings.defaultsFor(mode),
);

Recipe _production(
  String name,
  CraftMode mode, {
  required List<Ingredient> ingredients,
  String? marketId,
  List<RecipeVariant> variants = const <RecipeVariant>[],
  String? defaultVariantId,
}) => Recipe(
  name: name,
  type: mode.key,
  baseOutput: 1,
  group: '${mode.label} recipes',
  method: switch (mode) {
    CraftMode.alchemy => 'Alchemy',
    CraftMode.cooking => 'Cooking',
    CraftMode.processing => 'Heating',
  },
  ingredients: ingredients,
  marketId: marketId,
  sourceNote: null,
  vendor: null,
  location: null,
  npcPrice: 0,
  qualityBase: null,
  qualityGrade: null,
  outputMinimum: 1,
  outputMaximum: 1,
  variants: variants,
  defaultVariantId: defaultVariantId,
);

RecipeVariant _variant({
  required String id,
  required String label,
  required String routeId,
  required CraftMode mode,
  required List<Ingredient> ingredients,
  int batchMultiplier = 1,
  double baseOutput = 1,
}) => RecipeVariant(
  id: id,
  label: label,
  routeId: routeId,
  batchMultiplier: batchMultiplier,
  type: mode.key,
  baseOutput: baseOutput,
  method: mode == CraftMode.processing ? 'Heating' : mode.label,
  ingredients: ingredients,
  outputMinimum: baseOutput,
  outputMaximum: baseOutput,
);

Ingredient _ingredient(String name, double quantity) => Ingredient(
  name: name,
  quantity: quantity,
  options: const <String>[],
  substituteGroup: null,
  substituteRatios: const <String, double>{},
);

Recipe _leaf(String name) => Recipe(
  name: name,
  type: 'gathered',
  baseOutput: 1,
  group: 'Materials',
  method: null,
  ingredients: const <Ingredient>[],
  marketId: null,
  sourceNote: null,
  vendor: null,
  location: null,
  npcPrice: 0,
  qualityBase: null,
  qualityGrade: null,
  outputMinimum: null,
  outputMaximum: null,
);

final class _UsedInTestEnvironment {
  const _UsedInTestEnvironment({
    required this.application,
    required this.catalogRepository,
  });

  final PlannerApplicationController application;
  final CatalogRepository catalogRepository;

  Future<void> dispose() => application.dispose();
}
