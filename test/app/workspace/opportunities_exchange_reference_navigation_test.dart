import 'dart:async';

import 'package:bdo_craft_planner_flutter/app/window/window_host_service.dart';
import 'package:bdo_craft_planner_flutter/app/workspace/application_workspace.dart';
import 'package:bdo_craft_planner_flutter/data/opportunities/opportunity_market_service.dart';
import 'package:bdo_craft_planner_flutter/domain/models/craft_mode.dart';
import 'package:bdo_craft_planner_flutter/features/opportunities/opportunities_workspace.dart';
import 'package:bdo_craft_planner_flutter/features/recipe_book/recipe_book_item_info_view.dart';
import 'package:bdo_craft_planner_flutter/visual/visual.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/application_test_harness.dart';

void main() {
  for (final scenario in [
    (fromIcon: false, nested: false, disableAnimations: true),
    (fromIcon: false, nested: false, disableAnimations: false),
    (fromIcon: true, nested: false, disableAnimations: true),
    (fromIcon: true, nested: false, disableAnimations: false),
    (fromIcon: true, nested: true, disableAnimations: true),
    (fromIcon: true, nested: true, disableAnimations: false),
  ]) {
    final fromIcon = scenario.fromIcon;
    testWidgets('Maehwa ${scenario.nested
            ? 'nested icon'
            : fromIcon
            ? 'direct icon'
            : 'inline'} recipe opens the actual Processing Planner workspace '
        '${scenario.disableAnimations ? 'without motion' : 'with motion'}', (
      tester,
    ) async {
      configureApplicationTestSurface(
        tester,
        const Size(1500, 940),
        disableAnimations: scenario.disableAnimations,
      );
      final loaded = (await tester.runAsync(ApplicationTestHarness.create))!;
      await tester.runAsync(loaded.disposeControllerOnly);
      final harness = loaded.rebindControllerInCurrentZone();
      final window = _Window();
      final transport = _NoMarketRequests();
      final planner = harness.bundle.controller;
      final alchemy = planner.modes[CraftMode.alchemy]!;
      final processing = planner.modes[CraftMode.processing]!;
      expect(alchemy.selectTarget('Clear Liquid Reagent'), isTrue);
      expect(alchemy.commitInventory('Wild Grass', '123'), isTrue);
      expect(processing.commitAmount('73'), isTrue);
      final before = planner.documentSnapshot;

      try {
        await tester.pumpWidget(
          MaterialApp(
            home: ApplicationWorkspace(
              bundle: harness.bundle,
              marketGateway: const EmptyMarketGateway(),
              windowHost: window,
              fishMapWorkspace: const SizedBox.shrink(),
              enableBetaUpdates: false,
              enableOpportunityAutoCheck: false,
              opportunityMarketServiceFactory: (region) =>
                  OpportunityMarketService(
                    region: region,
                    transport: transport,
                  ),
            ),
          ),
        );
        await tester.tap(_tab('opportunities'));
        await tester.pump();
        final opportunities = tester
            .widget<OpportunitiesWorkspace>(find.byType(OpportunitiesWorkspace))
            .controller;
        await _completeIo(tester, opportunities.ready);
        opportunities.change((preferences) {
          // The displayed use belongs to Processing, not the selected
          // Opportunities production mode or the current Alchemy Planner.
          preferences.mode = CraftMode.cooking;
          preferences.section = 'exchanges';
          preferences.currencyId = 'sangpyeong';
          preferences.owned['sangpyeong'] = 50;
        });
        await _completeIo(tester, opportunities.calculationSettled);
        await _settle(tester);
        expect(_selected(tester, 'opportunities'), isTrue);

        final open = find.byWidgetPredicate(
          (widget) =>
              widget is AppButton &&
              widget.semanticLabel == 'Exchange details for Iridescent Maehwa',
        );
        await tester.scrollUntilVisible(
          open,
          300,
          scrollable: find
              .descendant(
                of: find.byKey(const PageStorageKey('exchange-sangpyeong')),
                matching: find.byType(Scrollable),
              )
              .first,
          maxScrolls: 40,
        );
        if (!fromIcon || scenario.nested) {
          await tester.tap(open);
          await _settle(tester);
        }
        if (fromIcon) {
          final icon = find.byKey(
            const ValueKey('opportunity-item:exchange-icon:820141'),
          );
          await tester.tap(
            scenario.nested
                ? find.descendant(of: find.byType(Dialog), matching: icon).first
                : icon.first,
          );
          await _settle(tester);
        }
        final reference = fromIcon
            ? find.byType(ItemReferenceCard)
            : find.byKey(const ValueKey('exchange-reference:820141'));
        expect(reference, findsOneWidget);
        expect(
          find.byType(Dialog, skipOffstage: false),
          findsNWidgets(scenario.nested ? 2 : 1),
        );
        expect(
          find.descendant(of: reference, matching: find.text('Used For')),
          findsOneWidget,
        );
        final useRecipe = find.descendant(
          of: reference,
          matching: find.byKey(
            const ValueKey(
              'item-info-use-recipe:processing:'
              'Iridescent Maehwa Liquor:base:1',
            ),
          ),
        );
        expect(useRecipe, findsOneWidget);
        expect(planner.documentSnapshot, same(before));
        expect(transport.requests, isEmpty);

        await tester.ensureVisible(useRecipe);
        await tester.pump();
        await tester.tap(useRecipe);
        await _settle(tester);
        // Animated dialog teardown completes after its final frame. Let the
        // completion callback rebuild the shell, without waiting indefinitely.
        for (var i = 0; i < 16 && _selected(tester, 'planner') != true; i++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 10)),
          );
          await tester.pump(const Duration(milliseconds: 50));
        }

        // This is the regression: changing only the target/mode while leaving
        // Opportunities in front is not successful recipe navigation.
        expect(_selected(tester, 'planner'), isTrue);
        expect(_selected(tester, 'opportunities'), isFalse);
        expect(
          FocusManager.instance.primaryFocus?.context
              ?.findAncestorWidgetOfExactType<OpportunitiesWorkspace>(),
          isNull,
          reason: 'The hidden exchange icon must not reclaim keyboard focus.',
        );
        expect(find.byType(OpportunitiesWorkspace), findsNothing);
        expect(
          find.byType(OpportunitiesWorkspace, skipOffstage: false),
          findsOneWidget,
        );
        expect(find.byType(Dialog, skipOffstage: false), findsNothing);
        expect(planner.activeMode.value, CraftMode.processing);
        expect(processing.state.value.view, 'plan');
        expect(processing.state.value.target, 'Iridescent Maehwa Liquor');
        expect(
          processing.selectedRecipeVariantId('Iridescent Maehwa Liquor'),
          isNull,
        );
        expect(processing.state.value.want, 73);
        expect(alchemy.state.value, same(before.alchemy));
        expect(opportunities.preferences.mode, CraftMode.cooking);
        expect(transport.requests, isEmpty);

        await tester.tap(_tab('opportunities'));
        await _settle(tester);
        expect(_selected(tester, 'opportunities'), isTrue);
        expect(
          tester
              .widget<OpportunitiesWorkspace>(
                find.byType(OpportunitiesWorkspace),
              )
              .controller,
          same(opportunities),
        );
        expect(opportunities.preferences.section, 'exchanges');
        expect(opportunities.currency.id, 'sangpyeong');
        expect(find.byType(Dialog, skipOffstage: false), findsNothing);
        expect(tester.takeException(), isNull);
      } finally {
        if (window.beforeClose case final close?) {
          await _completeIo(tester, close());
        }
        await tester.pumpWidget(const SizedBox.shrink());
        await _completeIo(tester, harness.dispose());
      }
    });
  }
}

Finder _tab(String name) => find.byKey(ValueKey('top-workspace-tab-$name'));

bool? _selected(WidgetTester tester, String name) =>
    tester.widget<Semantics>(_tab(name)).properties.selected;

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 4; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 15)),
    );
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _completeIo(WidgetTester tester, Future<void> work) async {
  var complete = false;
  Object? failure;
  StackTrace? stack;
  unawaited(
    work.then(
      (_) => complete = true,
      onError: (Object error, StackTrace trace) {
        failure = error;
        stack = trace;
        complete = true;
      },
    ),
  );
  for (var i = 0; i < 1500 && !complete; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump();
  }
  expect(complete, isTrue, reason: 'Workspace I/O did not finish.');
  if (failure != null) Error.throwWithStackTrace(failure!, stack!);
  await tester.pump();
}

class _NoMarketRequests implements OpportunityMarketTransport {
  final requests = <Uri>[];

  @override
  Future<OpportunityHttpResponse> post(
    Uri uri, {
    required Map<String, String> headers,
    required String body,
    Future<void>? abortTrigger,
  }) async {
    requests.add(uri);
    throw StateError('Reading the bound Maehwa reward must not fetch prices.');
  }

  @override
  void close() {}
}

class _Window extends WindowHostService {
  Future<void> Function()? beforeClose;

  @override
  void installCloseRequestHandler(Future<void> Function()? handler) =>
      beforeClose = handler;

  @override
  void removeCloseRequestHandler() => beforeClose = null;

  @override
  Future<bool> isMaximized() async => false;

  @override
  Future<void> setBottomInset(double inset) async {}
}
