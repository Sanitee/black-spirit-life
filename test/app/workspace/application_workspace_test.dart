import 'dart:async';
import 'dart:io';

import 'package:bdo_craft_planner_flutter/app/app.dart';
import 'package:bdo_craft_planner_flutter/app/appearance/appearance_actions.dart';
import 'package:bdo_craft_planner_flutter/app/application_bootstrap.dart';
import 'package:bdo_craft_planner_flutter/app/state/planner_application_controller.dart';
import 'package:bdo_craft_planner_flutter/app/workspace/application_copy_toast.dart';
import 'package:bdo_craft_planner_flutter/app_identity.dart';
import 'package:bdo_craft_planner_flutter/domain/market/market_cancellation.dart';
import 'package:bdo_craft_planner_flutter/domain/market/market_price_gateway.dart';
import 'package:bdo_craft_planner_flutter/domain/market/market_price_models.dart';
import 'package:bdo_craft_planner_flutter/domain/models/craft_mode.dart';
import 'package:bdo_craft_planner_flutter/domain/state/planner_state.dart';
import 'package:bdo_craft_planner_flutter/domain/state/state_copy.dart';
import 'package:bdo_craft_planner_flutter/features/about/about.dart';
import 'package:bdo_craft_planner_flutter/features/inventory/inventory.dart';
import 'package:bdo_craft_planner_flutter/features/planner/planner.dart';
import 'package:bdo_craft_planner_flutter/features/recipe_book/recipe_book.dart';
import 'package:bdo_craft_planner_flutter/features/shell/shell.dart';
import 'package:bdo_craft_planner_flutter/visual/visual.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/application_test_harness.dart';

void main() {
  test('Windows runner keeps the proportional 1575x987 launch frame', () {
    final runnerSource = File('windows/runner/main.cpp').readAsStringSync();
    expect(runnerSource, contains('Win32Window::Size size(1575, 987);'));
  });

  testWidgets('isolated production bundle loads in the widget test zone', (
    tester,
  ) async {
    final harness = (await tester.runAsync(
      () => ApplicationTestHarness.create(),
    ))!;
    expect(harness.bundle.catalog.alchemy.items, isNotEmpty);
    await tester.runAsync(harness.dispose);
  });

  testWidgets(
    'complete workspace renders at the proportional Windows launch size',
    (tester) async {
      configureApplicationTestSurface(tester, const Size(1575, 987));
      final harness = (await tester.runAsync(
        () => ApplicationTestHarness.create(),
      ))!;
      await tester.pumpWidget(
        BdoCraftPlannerApp(
          applicationFuture: Future.value(harness.bundle),
          marketGateway: const EmptyMarketGateway(),
        ),
      );
      await _pumpWorkspace(tester);
      expect(find.byType(PlannerView), findsOneWidget);
      final profileGlyph = tester.widget<AppVectorGlyph>(
        find.descendant(
          of: find.byKey(ShellDestination.data.actionKey),
          matching: find.byType(AppVectorGlyph),
        ),
      );
      expect(profileGlyph.name, 'profile');
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.runAsync(harness.dispose);
    },
  );

  testWidgets('a retained About view falls back to Planner while gated', (
    tester,
  ) async {
    configureApplicationTestSurface(tester, const Size(1575, 987));
    final harness = (await tester.runAsync(
      () => ApplicationTestHarness.create(view: 'about'),
    ))!;

    await tester.pumpWidget(
      BdoCraftPlannerApp(
        applicationFuture: Future.value(harness.bundle),
        marketGateway: const EmptyMarketGateway(),
        enableBetaUpdates: false,
      ),
    );
    await _pumpWorkspace(tester);

    expect(AppIdentity.showAboutDestination, isFalse);
    expect(find.byType(PlannerView), findsOneWidget);
    expect(find.byType(AboutView), findsNothing);
    expect(find.byKey(ShellDestination.about.actionKey), findsNothing);
    expect(
      tester
          .widget<AppButton>(find.byKey(ShellDestination.planner.actionKey))
          .selected,
      isTrue,
    );

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.runAsync(harness.dispose);
  });

  testWidgets(
    'real AFK Load action opens Data settings and copies a configured load',
    (tester) async {
      configureApplicationTestSurface(tester, const Size(1500, 940));
      final platformMessenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      String? clipboardText;
      platformMessenger.setMockMethodCallHandler(SystemChannels.platform, (
        call,
      ) async {
        if (call.method == 'Clipboard.setData') {
          clipboardText =
              (call.arguments as Map<Object?, Object?>)['text'] as String?;
        }
        return null;
      });
      addTearDown(
        () => platformMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );

      var harness = (await tester.runAsync(
        () => ApplicationTestHarness.create(),
      ))!;
      await tester.runAsync(harness.disposeControllerOnly);
      harness = harness.rebindControllerInCurrentZone();
      harness.bundle.controller.updateDocument(
        (document) => document.copyWith(
          afkWeightProfile: AfkWeightProfile(),
          alchemy: document.alchemy.copyWith(
            target: 'Clear Liquid Reagent',
            want: 10,
            view: 'plan',
            inventory: const <String, double>{},
            ignoreTargetInventory: true,
            ignoreIngredientInventory: true,
          ),
        ),
        immediate: true,
      );

      await tester.pumpWidget(
        BdoCraftPlannerApp(
          applicationFuture: Future.value(harness.bundle),
          marketGateway: const EmptyMarketGateway(),
        ),
      );
      await _pumpWorkspace(tester);

      const afkLoadAction = ValueKey<String>(
        'planner-afk-load:alchemy:Clear Liquid Reagent',
      );
      expect(find.byKey(afkLoadAction), findsOneWidget);
      await tester.tap(find.byKey(afkLoadAction));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey<String>('planner-afk-open-settings')),
      );
      await _pumpWorkspace(tester);

      expect(
        tester
            .widget<AppButton>(find.byKey(ShellDestination.data.actionKey))
            .selected,
        isTrue,
      );
      expect(
        find.byKey(const ValueKey<String>('data-afk-maximum-weight')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey<String>('data-afk-current-weight')),
        findsOneWidget,
      );

      harness.bundle.controller.updateDocument(
        (document) => document.copyWith(
          afkWeightProfile: AfkWeightProfile(
            maximumWeightLt: 1000,
            currentCarriedWeightLt: 100,
            safetyBufferLt: 25,
            featheryStepsLevel: 5,
          ),
        ),
        immediate: true,
      );
      await tester.tap(find.byKey(ShellDestination.planner.actionKey));
      await _pumpWorkspace(tester);
      await tester.tap(find.byKey(afkLoadAction));
      await tester.pumpAndSettle();

      final copyLoad = find.byKey(
        const ValueKey<String>('planner-afk-copy-load'),
      );
      expect(copyLoad, findsOneWidget);
      tester.widget<AppButton>(copyLoad).onPressed!();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 20));

      expect(clipboardText, startsWith('AFK Load'));
      // Ten requested outputs use the catalog's 2.5 expected yield, so the
      // goal-aware load correctly asks for four recipe attempts rather than
      // filling the character's entire safe capacity.
      expect(
        clipboardText,
        contains('Planner goal: 10 x Clear Liquid Reagent'),
      );
      expect(clipboardText, contains('This recipe: 4 attempts'));
      expect(clipboardText, contains('Round 1 of 1: 4 attempts'));
      expect(clipboardText, contains('Load:'));
      expect(find.text('AFK load list copied.'), findsOneWidget);
      expect(find.byType(SnackBar), findsOneWidget);
      expect(tester.takeException(), isNull);
      await _disposeWidgetHarness(tester, harness);
    },
  );

  testWidgets('persisted transition speed reaches the workspace shell', (
    tester,
  ) async {
    configureApplicationTestSurface(tester, const Size(1500, 940));
    final harness = (await tester.runAsync(
      () => ApplicationTestHarness.create(),
    ))!;
    harness.bundle.controller.updateDocument(
      (document) => document.copyWith(
        alchemy: document.alchemy.copyWith(
          appearance: AppearanceActions.copyAppearance(
            document.alchemy.appearance,
            tabTransitionSpeed: 'slow',
          ),
        ),
      ),
      immediate: true,
    );
    await tester.pumpWidget(
      BdoCraftPlannerApp(
        applicationFuture: Future.value(harness.bundle),
        marketGateway: const EmptyMarketGateway(),
      ),
    );
    await _pumpWorkspace(tester);

    expect(
      tester
          .widget<WorkspaceShell>(find.byType(WorkspaceShell))
          .transitionSpeed,
      ShellContentTransitionSpeed.slow,
    );

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.runAsync(harness.dispose);
  });

  testWidgets(
    'duplicate market names are deduplicated silently without losing row data',
    (tester) async {
      configureApplicationTestSurface(tester, const Size(1500, 940));
      final gateway = _SuccessfulRecordingMarketGateway();
      var harness = (await tester.runAsync(
        () => ApplicationTestHarness.create(),
      ))!;
      await tester.runAsync(harness.disposeControllerOnly);
      harness = harness.rebindControllerInCurrentZone();
      harness.bundle.controller.updateDocument(
        (document) => document.copyWith(
          alchemy: document.alchemy.copyWith(
            target: 'Elixir of Will',
            want: 1,
            view: 'plan',
            ignoreTargetInventory: true,
            ignoreIngredientInventory: true,
            substituteChoices: const <String, String>{
              'recipe:Elixir of Will:Blood Group 1': 'Wolf Blood',
            },
          ),
        ),
        immediate: true,
      );

      final rawNames = PlannerMarketRequest(
        controller: harness.bundle.controller.active,
        materials: harness.bundle.controller.active.plan.value.missing,
      ).namesForRefresh.toList(growable: false);
      expect(
        rawNames.where((name) => name == 'Wolf Blood').length,
        greaterThan(1),
        reason: 'the fixture must exercise the duplicate-name branch',
      );

      await tester.pumpWidget(
        BdoCraftPlannerApp(
          applicationFuture: Future.value(harness.bundle),
          marketGateway: gateway,
        ),
      );
      await _pumpWorkspace(tester);
      await tester.tap(find.byKey(PlannerActionKeys.p15));
      await _pumpWorkspace(tester);

      expect(
        gateway.requests.where((request) => request.name == 'Wolf Blood'),
        hasLength(1),
        reason: 'only the redundant gateway request is removed',
      );
      expect(
        harness
            .bundle
            .controller
            .active
            .state
            .value
            .market
            .prices['Wolf Blood'],
        18100,
      );
      expect(
        harness.bundle.controller.active.state.value.market.stock['Wolf Blood'],
        20000,
      );
      expect(
        harness
            .bundle
            .controller
            .active
            .state
            .value
            .market
            .totalTrades['Wolf Blood'],
        1000,
      );
      expect(
        harness.bundle.controller.active.state.value.market.observedDailyTrades,
        isEmpty,
        reason: 'one cumulative snapshot is not measured demand',
      );

      await tester.tap(find.byKey(PlannerActionKeys.p16));
      await _pumpWorkspace(tester);
      await tester.tap(find.byKey(PlannerActionKeys.p15));
      await _pumpWorkspace(tester);
      expect(
        harness
            .bundle
            .controller
            .active
            .state
            .value
            .market
            .observedDailyTrades['Wolf Blood'],
        480,
      );
      expect(
        harness
            .bundle
            .controller
            .active
            .state
            .value
            .market
            .tradeObservationHours['Wolf Blood'],
        6,
      );

      final wolfRow = find.byKey(const ValueKey<String>('need:Wolf Blood'));
      await tester.scrollUntilVisible(
        wolfRow,
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
      expect(wolfRow, findsOneWidget);
      expect(
        find.descendant(
          of: wolfRow,
          matching: find.text(
            'Wolf Blood was requested more than once and was deduplicated.',
          ),
        ),
        findsNothing,
      );
      expect(
        find.descendant(of: wolfRow, matching: find.text('20.000 in stock')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: wolfRow, matching: find.text('18.100 each')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      await _disposeWidgetHarness(tester, harness);
    },
  );

  testWidgets(
    'inventory clear is immediate and Data session spans modes/themes',
    (tester) async {
      configureApplicationTestSurface(tester, const Size(1500, 940));
      var harness = (await tester.runAsync(
        () => ApplicationTestHarness.create(),
      ))!;
      await tester.runAsync(harness.disposeControllerOnly);
      harness = harness.rebindControllerInCurrentZone();
      harness.bundle.controller.updateDocument(
        (document) => document.copyWith(
          showDeleteTools: true,
          alchemy: document.alchemy.copyWith(
            inventory: const <String, double>{'Dialog Probe': 2},
          ),
        ),
        immediate: true,
      );

      await tester.pumpWidget(
        BdoCraftPlannerApp(
          applicationFuture: Future.value(harness.bundle),
          marketGateway: const EmptyMarketGateway(),
        ),
      );
      await _pumpWorkspace(tester);

      await tester.tap(find.byKey(ShellDestination.inventory.actionKey));
      await _pumpWorkspace(tester);
      await tester.tap(find.byKey(InventoryActionKeys.i04));
      await _pumpWorkspace(tester);
      await tester.tap(find.byKey(InventoryActionKeys.i03));
      await _pumpWorkspace(tester);

      expect(find.text('Clear Inventory'), findsNothing);
      expect(find.text('Cancel'), findsNothing);
      expect(find.text('Undo'), findsNothing);
      expect(
        harness.bundle.controller.documentSnapshot.alchemy.inventory,
        isEmpty,
      );
      expect(tester.takeException(), isNull);

      await tester.tap(find.byKey(ShellDestination.data.actionKey));
      await _pumpWorkspace(tester);
      await tester.tap(
        find.byKey(const ValueKey<String>('data-afk-load-toggle')),
      );
      await _pumpWorkspace(tester);
      expect(
        find.byKey(const ValueKey<String>('data-afk-maximum-weight')),
        findsOneWidget,
      );

      harness.bundle.controller.updateDocument(
        (document) => AppearanceActions.selectSharedBackground(
          document,
          'illuminated-ledger',
        ),
        immediate: true,
      );
      await _pumpWorkspace(tester);
      var backdrop = tester.widget<LedgerBackdrop>(find.byType(LedgerBackdrop));
      expect(backdrop.showMarginalia, isFalse);
      expect(backdrop.centerFoldX, 649);
      expect(backdrop.centerFoldWidth, 24);

      await tester.tap(find.byKey(ShellDestination.planner.actionKey));
      await _pumpWorkspace(tester);
      backdrop = tester.widget<LedgerBackdrop>(find.byType(LedgerBackdrop));
      expect(backdrop.centerFoldX, isNull);
      expect(backdrop.centerFoldRatio, .575);
      expect(backdrop.centerFoldWidth, 18);

      await tester.tap(find.byKey(ShellDestination.data.actionKey));
      await _pumpWorkspace(tester);

      await tester.tap(find.byKey(ShellDestination.recipeEditor.actionKey));
      await _pumpWorkspace(tester);
      backdrop = tester.widget<LedgerBackdrop>(find.byType(LedgerBackdrop));
      expect(backdrop.centerFoldX, 620);
      expect(backdrop.centerFoldWidth, 30);

      await tester.tap(find.byKey(ShellDestination.appearance.actionKey));
      await _pumpWorkspace(tester);
      backdrop = tester.widget<LedgerBackdrop>(find.byType(LedgerBackdrop));
      expect(backdrop.centerFoldX, isNull);
      expect(backdrop.centerFoldRatio, .659);
      expect(backdrop.centerFoldWidth, 18);

      await tester.tap(find.byKey(ShellDestination.data.actionKey));
      await _pumpWorkspace(tester);
      expect(
        find.byKey(const ValueKey<String>('data-afk-maximum-weight')),
        findsOneWidget,
      );

      await tester.tap(find.byKey(ShellActionKeys.mode(CraftMode.processing)));
      await _pumpWorkspace(tester);
      await tester.tap(find.byKey(ShellDestination.data.actionKey));
      await _pumpWorkspace(tester);
      expect(
        find.byKey(const ValueKey<String>('data-afk-maximum-weight')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      await _disposeWidgetHarness(tester, harness);
    },
  );

  testWidgets(
    'real workspace preserves feature sessions and closes Recipe Book on navigation',
    (tester) async {
      configureApplicationTestSurface(tester, const Size(1500, 940));
      final platformMessenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      String? clipboardText;
      platformMessenger.setMockMethodCallHandler(SystemChannels.platform, (
        call,
      ) async {
        if (call.method == 'Clipboard.setData') {
          clipboardText =
              (call.arguments as Map<Object?, Object?>)['text'] as String?;
        }
        return null;
      });
      addTearDown(
        () => platformMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      var harness = (await tester.runAsync(
        () => ApplicationTestHarness.create(),
      ))!;
      await tester.runAsync(harness.disposeControllerOnly);
      harness = harness.rebindControllerInCurrentZone();
      harness.bundle.controller.updateDocument(
        (document) => document.copyWith(showDeleteTools: true),
        immediate: true,
      );

      await tester.pumpWidget(
        BdoCraftPlannerApp(
          applicationFuture: Future.value(harness.bundle),
          marketGateway: const EmptyMarketGateway(),
        ),
      );
      await _pumpWorkspace(tester);

      expect(find.byType(PlannerView), findsOneWidget);
      await tester.tap(find.byKey(ShellDestination.inventory.actionKey));
      await _pumpWorkspace(tester);
      final projection = InventoryProjection.assemble(
        harness.bundle.controller.active,
      );
      final selectedCategory = projection.repairCategory('');
      final visibleItem = projection
          .visibleItems(category: selectedCategory, search: '')
          .first;
      await tester.enterText(
        find.descendant(
          of: find.byKey(InventoryActionKeys.i01),
          matching: find.byType(TextField),
        ),
        visibleItem.name,
      );
      await tester.pump(const Duration(milliseconds: 200));

      await tester.tap(find.byKey(ShellDestination.data.actionKey));
      await _pumpWorkspace(tester);
      await tester.tap(find.byKey(ShellDestination.inventory.actionKey));
      await _pumpWorkspace(tester);
      final search = tester.widget<TextField>(
        find.descendant(
          of: find.byKey(InventoryActionKeys.i01),
          matching: find.byType(TextField),
        ),
      );
      expect(search.controller?.text, visibleItem.name);
      await tester.tap(
        find.byKey(InventoryActionKeys.row('I09', visibleItem.name)),
      );
      await tester.pump();
      expect(find.byKey(ApplicationCopyToastKeys.overlay), findsOneWidget);
      expect(clipboardText, visibleItem.name);
      expect(find.text('Copied ${visibleItem.name}'), findsOneWidget);
      expect(find.byType(SnackBar), findsNothing);
      expect(
        tester.getRect(find.byKey(ApplicationCopyToastKeys.surface)).top,
        52,
      );
      await tester.pump(const Duration(milliseconds: 1349));
      expect(find.byKey(ApplicationCopyToastKeys.overlay), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 1));
      expect(find.byKey(ApplicationCopyToastKeys.overlay), findsNothing);

      await tester.tap(find.byKey(ShellDestination.planner.actionKey));
      await _pumpWorkspace(tester);
      await tester.tap(find.byKey(PlannerActionKeys.p03));
      await _pumpWorkspace(tester);
      expect(find.byKey(RecipeBookKeys.modal), findsOneWidget);
      expect(
        tester.getRect(find.byKey(RecipeBookKeys.modal)),
        const Rect.fromLTWH(140, 83, 1220, 814),
      );
      await tester.enterText(
        find.descendant(
          of: find.byKey(RecipeBookKeys.r03Search),
          matching: find.byType(TextField),
        ),
        'Clear Liquid',
      );
      await tester.tapAt(const Offset(12, 100));
      await _pumpWorkspace(tester);
      expect(find.byKey(RecipeBookKeys.modal), findsNothing);
      await tester.tap(find.byKey(PlannerActionKeys.p03));
      await _pumpWorkspace(tester);
      expect(
        tester
            .widget<TextField>(
              find.descendant(
                of: find.byKey(RecipeBookKeys.r03Search),
                matching: find.byType(TextField),
              ),
            )
            .controller
            ?.text,
        'Clear Liquid',
      );
      await tester.tapAt(const Offset(12, 100));
      await _pumpWorkspace(tester);

      await tester.tap(find.byKey(ShellActionKeys.mode(CraftMode.processing)));
      await _pumpWorkspace(tester);
      expect(find.byKey(ShellDestination.bonusRecipes.actionKey), findsNothing);
      expect(harness.bundle.controller.activeMode.value, CraftMode.processing);
      await _disposeWidgetHarness(tester, harness);
    },
  );

  testWidgets(
    'Bonus remains compact with visible plan columns in the real 1200x752 shell',
    (tester) async {
      configureApplicationTestSurface(tester, const Size(1200, 752));
      var harness = (await tester.runAsync(
        () => ApplicationTestHarness.create(backgroundId: 'greenhouse'),
      ))!;
      await tester.runAsync(harness.disposeControllerOnly);
      harness = harness.rebindControllerInCurrentZone();

      await tester.pumpWidget(
        BdoCraftPlannerApp(
          applicationFuture: Future.value(harness.bundle),
          marketGateway: const EmptyMarketGateway(),
        ),
      );
      await _pumpWorkspace(tester);
      expect(find.byType(PlannerView), findsOneWidget);

      await tester.tap(find.byKey(ShellDestination.bonusRecipes.actionKey));
      await _pumpWorkspace(tester);

      expect(find.byType(BonusView), findsOneWidget);
      final contentRect = tester.getRect(
        find.byKey(WorkspaceShellKeys.contentHost),
      );
      final commandRect = tester.getRect(
        find.byKey(const ValueKey<String>('bonus-command-band')),
      );
      final columnsRect = tester.getRect(
        find.byKey(const ValueKey<String>('bonus-plan-columns')),
      );
      final visibleColumns = columnsRect.intersect(contentRect);
      final visibleFinalAction = tester
          .getRect(find.byKey(BonusActionKeys.b05))
          .intersect(contentRect);

      expect(commandRect.height, lessThanOrEqualTo(100));
      expect(
        columnsRect.top,
        closeTo(commandRect.bottom + 48, .01),
        reason: 'Standard Bonus retains its authored command-to-plan gap',
      );
      expect(visibleColumns.width, greaterThan(0));
      expect(visibleColumns.height, greaterThan(300));
      expect(visibleFinalAction.width, greaterThan(40));
      expect(visibleFinalAction.height, greaterThan(0));
      expect(columnsRect.bottom, lessThanOrEqualTo(contentRect.bottom));
      expect(tester.takeException(), isNull);
      await _disposeWidgetHarness(tester, harness);
    },
  );

  testWidgets(
    'Bonus Use As Target public control transfers and visibly opens Planner',
    (tester) async {
      configureApplicationTestSurface(tester, const Size(1500, 940));
      var harness = (await tester.runAsync(
        () => ApplicationTestHarness.create(
          backgroundId: 'illuminated-ledger',
          view: 'bonus',
        ),
      ))!;
      await tester.runAsync(harness.disposeControllerOnly);
      harness = harness.rebindControllerInCurrentZone();
      harness.bundle.controller.active.updateState(
        (state) => state.copyWith(
          bonusWant: 17,
          completedSteps: const <String>{'Clear Liquid Reagent'},
          view: 'bonus',
        ),
        immediate: true,
      );

      await tester.pumpWidget(
        BdoCraftPlannerApp(
          applicationFuture: Future.value(harness.bundle),
          marketGateway: const EmptyMarketGateway(),
        ),
      );
      await _pumpWorkspace(tester);
      expect(find.byType(BonusView), findsOneWidget);

      await tester.tap(find.byKey(BonusActionKeys.b05));
      await _pumpWorkspace(tester);

      final state = harness.bundle.controller.active.state.value;
      expect(state.target, state.bonusTarget);
      expect(state.want, 17);
      expect(state.completedSteps, isEmpty);
      expect(state.view, 'plan');
      expect(find.byType(PlannerView), findsOneWidget);
      expect(find.byType(BonusView), findsNothing);
      expect(
        tester
            .widget<AppButton>(find.byKey(ShellDestination.planner.actionKey))
            .selected,
        isTrue,
      );
      expect(tester.takeException(), isNull);
      await _disposeWidgetHarness(tester, harness);
    },
  );

  testWidgets(
    'ordinary save failure is global, retryable, and survives restart',
    (tester) async {
      configureApplicationTestSurface(tester, const Size(1500, 940));
      var saveAttempt = 0;
      var harness = (await tester.runAsync(
        () => ApplicationTestHarness.create(backgroundId: 'plain-verdant'),
      ))!;
      var persisted = harness.bundle.controller.documentSnapshot;
      await tester.runAsync(harness.disposeControllerOnly);
      harness = harness.rebindControllerInCurrentZone(
        saveStateFactory: (_) => (state) async {
          saveAttempt++;
          if (saveAttempt == 1) {
            throw const FileSystemException(
              'injected global planner save failure',
            );
          }
          persisted = state;
          return state;
        },
      );
      await tester.pumpWidget(
        BdoCraftPlannerApp(
          applicationFuture: Future.value(harness.bundle),
          marketGateway: const EmptyMarketGateway(),
        ),
      );
      await _pumpWorkspace(tester);

      await tester.tap(find.byKey(ShellActionKeys.mode(CraftMode.processing)));
      await _pumpWorkspace(tester);

      expect(harness.bundle.controller.activeMode.value, CraftMode.processing);
      expect(
        find.textContaining('Planner state could not be written to disk'),
        findsOneWidget,
      );
      expect(find.text('Retry'), findsOneWidget);
      expect(
        tester.widget<SnackBar>(find.byType(SnackBar)).duration,
        const Duration(seconds: 8),
      );

      final retryButton = tester.widget<AppButton>(
        find
            .ancestor(of: find.text('Retry'), matching: find.byType(AppButton))
            .first,
      );
      retryButton.onPressed!();
      for (var attempt = 0; attempt < 20; attempt++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump(const Duration(milliseconds: 20));
        if (find.textContaining('safely synchronized').evaluate().isNotEmpty) {
          break;
        }
      }
      expect(saveAttempt, greaterThanOrEqualTo(2));
      expect(harness.bundle.controller.saveError.value, isNull);
      expect(find.textContaining('safely synchronized'), findsOneWidget);
      final restarted = PlannerApplicationController(
        catalog: harness.bundle.catalog,
        initialState: persisted,
        saveState: (state) async => state,
        saveDebounce: Duration.zero,
      );
      expect(restarted.activeMode.value, CraftMode.processing);
      await restarted.dispose();
      await _disposeWidgetHarness(tester, harness);
    },
  );

  testWidgets('startup failure is explicit and never substitutes demo data', (
    tester,
  ) async {
    configureApplicationTestSurface(tester, const Size(1200, 752));
    final application = Completer<ApplicationBundle>();
    await tester.pumpWidget(
      BdoCraftPlannerApp(
        applicationFuture: application.future,
        marketGateway: const EmptyMarketGateway(),
      ),
    );
    application.completeError(
      const FormatException('packaged dataset checksum failed'),
    );
    await tester.pump();

    expect(
      find.text('${AppIdentity.displayName} could not start.'),
      findsOneWidget,
    );
    expect(find.textContaining('No test or fallback data'), findsOneWidget);
    expect(
      find.textContaining('packaged dataset checksum failed'),
      findsOneWidget,
    );
  });

  testWidgets(
    '200% text scale keeps root semantics, focus order, Enter and Space usable',
    (tester) async {
      configureApplicationTestSurface(
        tester,
        const Size(1200, 752),
        textScaleFactor: 2,
      );
      var harness = (await tester.runAsync(
        () => ApplicationTestHarness.create(),
      ))!;
      await tester.runAsync(harness.disposeControllerOnly);
      harness = harness.rebindControllerInCurrentZone();
      harness.bundle.controller.updateDocument(
        (document) => document.copyWith(showDeleteTools: true),
        immediate: true,
      );
      final semantics = tester.ensureSemantics();

      await tester.pumpWidget(
        BdoCraftPlannerApp(
          applicationFuture: Future.value(harness.bundle),
          marketGateway: const EmptyMarketGateway(),
        ),
      );
      await _pumpWorkspace(tester);

      expect(find.bySemanticsLabel('Minimize'), findsOneWidget);
      expect(find.bySemanticsLabel('Maximize or restore'), findsOneWidget);
      expect(find.bySemanticsLabel('Close'), findsOneWidget);
      expect(find.bySemanticsLabel('Main navigation'), findsOneWidget);
      expect(find.bySemanticsLabel('Craft mode'), findsOneWidget);

      final planner = find.byKey(ShellDestination.planner.actionKey);
      final plannerFocus = _appButtonFocus(tester, planner);
      plannerFocus.requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      final nextFocus = FocusManager.instance.primaryFocus;
      expect(nextFocus, isNotNull);
      expect(identical(nextFocus, plannerFocus), isFalse);
      expect(nextFocus!.canRequestFocus, isTrue);

      await tester.sendKeyDownEvent(LogicalKeyboardKey.shift);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shift);
      await tester.pump();
      expect(plannerFocus.hasFocus, isTrue);

      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await _pumpWorkspace(tester);
      expect(find.byType(PlannerView), findsOneWidget);

      final inventory = find.byKey(ShellDestination.inventory.actionKey);
      _appButtonFocus(tester, inventory).requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await _pumpWorkspace(tester);
      expect(find.byType(InventoryView), findsOneWidget);
      expect(tester.takeException(), isNull);
      semantics.dispose();
      await _disposeWidgetHarness(tester, harness);
    },
  );
}

final class _SuccessfulRecordingMarketGateway implements MarketPriceGateway {
  final List<MarketPriceRequest> requests = <MarketPriceRequest>[];
  int _fetchCount = 0;

  @override
  Future<MarketPriceFetchResult> fetch(
    Iterable<MarketPriceRequest> requested, {
    MarketCancellationToken? cancellationToken,
  }) async {
    final captured = requested.toList(growable: false);
    requests
      ..clear()
      ..addAll(captured);
    final observationIndex = _fetchCount++;
    final fetchedAt = DateTime.utc(2026, 7, 20, 12 + observationIndex * 6);
    return MarketPriceFetchResult(
      region: 'eu',
      language: 'en-US',
      fetchedAt: fetchedAt,
      attemptedSources: const <MarketPriceSource>[
        MarketPriceSource.pearlAbyssCentralMarket,
      ],
      items: <MarketPriceRow>[
        for (final request in captured)
          MarketPriceRow(
            name: request.name,
            id: request.id,
            ok: true,
            price: 18100,
            stock: 20000,
            source: MarketPriceSource.pearlAbyssCentralMarket,
            fetchedAt: fetchedAt,
            diagnosticCode: MarketDiagnosticCode.none,
            totalTrades: 1000 + observationIndex * 120,
            lastSoldAtEpochSeconds: 1784548800 + observationIndex * 6 * 60 * 60,
          ),
      ],
    );
  }
}

Future<void> _pumpWorkspace(WidgetTester tester) async {
  for (var index = 0; index < 4; index++) {
    await tester.pump(const Duration(milliseconds: 80));
  }
}

FocusNode _appButtonFocus(WidgetTester tester, Finder action) => tester
    .widget<FocusableActionDetector>(
      find
          .descendant(
            of: action,
            matching: find.byType(FocusableActionDetector),
          )
          .first,
    )
    .focusNode!;

Future<void> _disposeWidgetHarness(
  WidgetTester tester,
  ApplicationTestHarness harness,
) async {
  await tester.pumpWidget(const SizedBox.shrink());
  var disposed = false;
  final disposeFuture = harness.bundle.controller.dispose().whenComplete(
    () => disposed = true,
  );
  for (var attempt = 0; attempt < 20 && !disposed; attempt++) {
    await tester.pump();
  }
  expect(disposed, isTrue, reason: 'controller disposal must drain in-zone');
  await disposeFuture;
  await tester.runAsync(() async {
    if (await harness.temporaryDirectory.exists()) {
      await harness.temporaryDirectory.delete(recursive: true);
    }
  });
}
