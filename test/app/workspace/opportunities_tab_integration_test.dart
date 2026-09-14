import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:bdo_craft_planner_flutter/app/window/window_host_service.dart';
import 'package:bdo_craft_planner_flutter/app/workspace/application_workspace.dart';
import 'package:bdo_craft_planner_flutter/data/opportunities/opportunity_market_service.dart';
import 'package:bdo_craft_planner_flutter/domain/models/craft_mode.dart';
import 'package:bdo_craft_planner_flutter/domain/opportunities/exchange_models.dart';
import 'package:bdo_craft_planner_flutter/domain/opportunities/opportunity_calculator.dart';
import 'package:bdo_craft_planner_flutter/features/opportunities/opportunities_item_actions.dart';
import 'package:bdo_craft_planner_flutter/features/opportunities/opportunities_workspace.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/application_test_harness.dart';

void main() {
  for (final openTab in [false, true]) {
    testWidgets(
      'startup market check stays in the background and closes safely '
      '${openTab ? 'after opening Opportunities' : 'without opening Opportunities'}',
      (tester) async {
        configureApplicationTestSurface(tester, const Size(1500, 940));
        final harness = await _createHarness(tester);
        final window = _RecordingWindowHost();
        final sessions = <_StartupMarketTransport>[];
        final plannerBefore = harness.bundle.controller.documentSnapshot;
        await tester.pumpWidget(
          _host(
            harness,
            window,
            autoCheck: true,
            serviceFactory: (region) {
              final transport = _StartupMarketTransport();
              sessions.add(transport);
              return OpportunityMarketService(
                region: region,
                quoteBatchSize: 1,
                transport: transport,
                concurrency: 1,
                requestSpacing: Duration.zero,
                requestTimeout: const Duration(minutes: 5),
              );
            },
          ),
        );
        expect(_topTab('planner'), findsOneWidget);
        expect(_opportunities(includeHidden: true), findsNothing);
        await _waitFor(
          tester,
          () => sessions.isNotEmpty && sessions.single.waitingForQuote,
        );
        expect(sessions, hasLength(1));
        expect(sessions.single.quoteIds, isNotEmpty);
        expect(_opportunities(includeHidden: true), findsNothing);

        if (openTab) {
          await tester.tap(_topTab('opportunities'));
          await tester.pump();
          final controller = tester
              .widget<OpportunitiesWorkspace>(_opportunities())
              .controller;
          await _completeIo(tester, controller.ready);
          expect(controller.scanning, isTrue);
          expect(controller.market.items, isNotEmpty);
          final cachedId = controller.market.items.keys.first;
          final cachedQuote = controller.market.items[cachedId];
          expect(cachedQuote!.basePrice, 1000);
          expect(cachedQuote.quoteFetchedAt, isNotNull);
          expect(cachedQuote.bookFetchedAt, isNull);

          await tester.tap(_withinOpportunities('Exchanges'));
          await tester.pump(const Duration(milliseconds: 500));
          await tester.tap(_topTab('planner'));
          await tester.pump();
          await tester.tap(_topTab('opportunities'));
          await tester.pump(const Duration(milliseconds: 500));
          expect(
            tester.widget<OpportunitiesWorkspace>(_opportunities()).controller,
            same(controller),
          );
          expect(controller.market.items[cachedId], same(cachedQuote));
          expect(controller.scanning, isTrue);
          expect(sessions, hasLength(1));
          expect(sessions.single.aborted, isFalse);
        }

        expect(window.beforeClose, isNotNull);
        await _completeIo(tester, window.beforeClose!());
        expect(sessions.single.aborted, isTrue);
        expect(sessions.single.closed, isTrue);
        expect(harness.bundle.controller.documentSnapshot, same(plannerBefore));
        await tester.pumpWidget(const SizedBox.shrink());
        expect(window.beforeClose, isNull);
        await _completeIo(tester, harness.dispose());
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'third tab mounts lazily, retains both panes and leaves the planner intact',
    (tester) async {
      configureApplicationTestSurface(tester, const Size(1500, 940));
      final harness = await _createHarness(tester);
      final window = _RecordingWindowHost();
      final planner = harness.bundle.controller;
      final alchemy = planner.modes[CraftMode.alchemy]!;
      expect(alchemy.selectTarget('Clear Liquid Reagent'), isTrue);
      expect(alchemy.commitAmount('75'), isTrue);
      expect(alchemy.commitInventory('Wild Grass', '123'), isTrue);
      await tester.pump();
      final plannerBefore = planner.documentSnapshot;
      await tester.pumpWidget(_host(harness, window));
      await tester.pump();

      final topTabs = ['planner', 'resource-map', 'opportunities'];
      for (final tab in topTabs) {
        expect(_topTab(tab), findsOneWidget);
      }
      final tabPositions = topTabs
          .map((tab) => tester.getCenter(_topTab(tab)).dx)
          .toList();
      expect(tabPositions, orderedEquals([...tabPositions]..sort()));
      expect(_opportunities(includeHidden: true), findsNothing);

      await tester.tap(_topTab('opportunities'));
      await tester.pump();
      final controller = tester
          .widget<OpportunitiesWorkspace>(_opportunities())
          .controller;
      await _completeIo(tester, controller.ready);
      expect(controller.loading, isFalse);
      expect(controller.scanning, isFalse);
      expect(controller.quotes, isNotEmpty);
      expect(controller.market.items, isEmpty);
      final retainedElement = tester.element(_opportunities());
      final itemActions = OpportunityItemActionsScope.maybeOf(retainedElement);
      expect(itemActions?.resolveMapLookup, isNotNull);
      expect(itemActions?.openMapLookup, isNotNull);

      await tester.enterText(_input('craft-search'), 'Beer');
      await tester.pump();
      controller.change((preferences) => preferences.crafts = 12);
      expect(
        OpportunityItemActionsScope.maybeOf(
          tester.element(find.byKey(const ValueKey('craft-toolbar'))),
        ),
        same(itemActions),
        reason: 'The split toolbar retains the application map actions.',
      );
      await tester.tap(find.byKey(const ValueKey('craft-sort-preorders')));
      expect(controller.preferences.demandOnly, isFalse);
      await tester.tap(find.byKey(const ValueKey('craft-has-demand')));
      await tester.tap(
        find.byKey(const ValueKey('craft-ingredients-available')),
      );
      await tester.pump();
      await _completeIo(tester, controller.calculationSettled);
      expect(controller.preferences.craftSearch, 'Beer');
      expect(controller.preferences.crafts, 12);
      expect(controller.preferences.craftSort, 'preorders');
      expect(controller.preferences.demandOnly, isTrue);
      expect(controller.preferences.readyOnly, isTrue);
      expect(find.byKey(const ValueKey('Crafts')), findsNothing);
      expect(find.byType(Dialog), findsNothing);

      await tester.tap(_withinOpportunities('Exchanges'));
      await tester.pump();
      await tester.enterText(_input('exchange-search'), 'Sangpyeong');
      await tester.pump();
      await tester.enterText(_input('You have'), '1234');
      await tester.pump();
      expect(_withinOpportunities('List for sale'), findsNothing);
      expect(_withinOpportunities('Current buyers'), findsNothing);
      expect(controller.exchangeSaleMode, ExchangeSaleMode.listing);
      expect(controller.owned, 1234);

      await tester.tap(_withinOpportunities('Crafting'));
      await tester.pump();
      expect(_inputText(tester, 'craft-search'), 'Beer');
      expect(controller.preferences.crafts, 12);
      expect(
        tester
            .widget<FilterChip>(find.byKey(const ValueKey('craft-has-demand')))
            .selected,
        isTrue,
      );
      expect(
        tester
            .widget<FilterChip>(
              find.byKey(const ValueKey('craft-ingredients-available')),
            )
            .selected,
        isTrue,
      );
      expect(controller.preferences.craftSort, 'preorders');
      expect(find.byType(Dialog), findsNothing);
      expect(controller.craftSaleMode, OpportunitySaleMode.listing);

      await tester.tap(_topTab('planner'));
      await tester.pump();
      expect(_opportunities(), findsNothing);
      expect(_opportunities(includeHidden: true), findsOneWidget);
      expect(planner.activeMode.value, CraftMode.alchemy);
      expect(alchemy.state.value.target, 'Clear Liquid Reagent');
      expect(alchemy.state.value.want, 75);
      expect(alchemy.state.value.inventory['Wild Grass'], 123);
      expect(planner.documentSnapshot, same(plannerBefore));

      await tester.tap(_topTab('opportunities'));
      await tester.pump();
      expect(tester.element(_opportunities()), same(retainedElement));
      expect(
        tester.widget<OpportunitiesWorkspace>(_opportunities()).controller,
        same(controller),
      );
      expect(_inputText(tester, 'craft-search'), 'Beer');
      expect(controller.preferences.crafts, 12);
      expect(controller.preferences.craftSort, 'preorders');
      expect(
        tester
            .widget<FilterChip>(find.byKey(const ValueKey('craft-has-demand')))
            .selected,
        isTrue,
      );
      expect(
        tester
            .widget<FilterChip>(
              find.byKey(const ValueKey('craft-ingredients-available')),
            )
            .selected,
        isTrue,
      );
      await tester.tap(_withinOpportunities('Exchanges'));
      await tester.pump();
      expect(_inputText(tester, 'exchange-search'), 'Sangpyeong');
      expect(_inputText(tester, 'You have'), '1234');
      expect(controller.exchangeSaleMode, ExchangeSaleMode.listing);
      expect(planner.documentSnapshot, same(plannerBefore));

      // Close immediately after an edit, before the settings debounce expires.
      await tester.enterText(_input('You have'), '4321');
      expect(window.beforeClose, isNotNull);
      await _completeIo(tester, window.beforeClose!());
      final saved = (await tester.runAsync(() async {
        final file = File(
          '${harness.bundle.stateRepository.paths.applicationDirectory.path}'
          '/opportunities/opportunities-settings.json',
        );
        return jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      }))!;
      expect(saved['section'], 'exchanges');
      expect(saved['craftSearch'], 'Beer');
      expect(saved['crafts'], 12);
      expect(saved['craftSort'], 'preorders');
      expect(saved['demandOnly'], isTrue);
      expect(saved['readyOnly'], isTrue);
      expect(saved['craftSale'], controller.preferences.craftSale);
      expect(saved['exchangeSearch'], 'Sangpyeong');
      expect(saved['exchangeSale'], controller.preferences.exchangeSale);
      expect((saved['owned'] as Map)[controller.currency.id], 4321);
      expect(planner.documentSnapshot, same(plannerBefore));
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(const SizedBox.shrink());
      expect(window.beforeClose, isNull);
      await _completeIo(tester, harness.dispose());
    },
  );

  testWidgets(
    'inline Opportunities mastery commits to the shared Planner state',
    (tester) async {
      configureApplicationTestSurface(tester, const Size(1200, 752));
      final harness = await _createHarness(tester);
      final window = _RecordingWindowHost();
      try {
        await tester.pumpWidget(_host(harness, window));
        await tester.tap(_topTab('opportunities'));
        await tester.pump();
        final controller = tester
            .widget<OpportunitiesWorkspace>(_opportunities())
            .controller;
        await _completeIo(tester, controller.ready);
        final planner = harness.bundle.controller;
        expect(
          find.byKey(const ValueKey('opportunities-sidebar')),
          findsNothing,
        );
        expect(
          find.byKey(const ValueKey('opportunities-sections')),
          findsOneWidget,
        );
        final input = find.descendant(
          of: find.byKey(const ValueKey('craft-mastery-input')),
          matching: find.byType(TextField),
          matchRoot: true,
        );
        for (final record in [
          (CraftMode.cooking, 925),
          (CraftMode.alchemy, 1700),
          (CraftMode.processing, 2750),
        ]) {
          await tester.tap(find.byKey(ValueKey('craft-mode-${record.$1.key}')));
          await tester.pump();
          await _completeIo(tester, controller.calculationSettled);
          final mode = planner.modes[record.$1]!;
          final before = mode.state.value;
          await tester.tap(find.byKey(const ValueKey('craft-mastery')));
          await tester.pump();
          await tester.enterText(input, '${record.$2}');
          await tester.pump();
          expect(mode.state.value, same(before));
          expect(find.byType(Dialog), findsNothing);
          await tester.sendKeyEvent(LogicalKeyboardKey.enter);
          await tester.pump();
          await _completeIo(tester, controller.calculationSettled);
          final state = mode.state.value;
          final value = switch (record.$1) {
            CraftMode.cooking => state.cookingMastery,
            CraftMode.alchemy => state.alchemyMastery,
            CraftMode.processing => state.processingMastery,
          };
          expect(value, record.$2);
          expect(controller.state, same(state));
          expect(input, findsNothing);
          expect(
            find.descendant(
              of: find.byKey(const ValueKey('craft-mastery')),
              matching: find.text('${record.$2}'),
            ),
            findsOneWidget,
          );
        }
        expect(planner.documentSnapshot.cooking.cookingMastery, 925);
        expect(planner.documentSnapshot.alchemy.alchemyMastery, 1700);
        expect(planner.documentSnapshot.processing.processingMastery, 2750);
        final committed = planner.documentSnapshot;
        await tester.tap(_topTab('planner'));
        await tester.pump();
        await tester.tap(_topTab('opportunities'));
        await tester.pump();
        expect(planner.documentSnapshot, same(committed));
        expect(
          find.descendant(
            of: find.byKey(const ValueKey('craft-mastery')),
            matching: find.text('2750'),
          ),
          findsOneWidget,
        );
        expect(find.byType(Dialog), findsNothing);
        expect(tester.takeException(), isNull);
        await _completeIo(tester, window.beforeClose!());
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await _completeIo(tester, harness.dispose());
      }
    },
  );

  testWidgets(
    'crafting mode buttons only offer recipes from the selected production mode',
    (tester) async {
      configureApplicationTestSurface(tester, const Size(1500, 940));
      final harness = await _createHarness(tester);
      final window = _RecordingWindowHost();
      await tester.pumpWidget(_host(harness, window));
      await tester.tap(_topTab('opportunities'));
      await tester.pump();
      final controller = tester
          .widget<OpportunitiesWorkspace>(_opportunities())
          .controller;
      await _completeIo(tester, controller.ready);
      final plannerBefore = harness.bundle.controller.documentSnapshot;

      for (final mode in [
        CraftMode.cooking,
        CraftMode.alchemy,
        CraftMode.processing,
      ]) {
        await tester.tap(_withinOpportunities(mode.label).first);
        await tester.pump();
        await _completeIo(tester, controller.calculationSettled);
        expect(controller.preferences.mode, mode);
        final expected = controller.recipes.values
            .where(
              (recipe) =>
                  recipe.isCraftable &&
                  recipe.type.trim().toLowerCase() == mode.key,
            )
            .map((recipe) => recipe.name)
            .toSet();
        expect(expected, isNotEmpty);
        expect(
          controller.quotes.map((quote) => quote.recipeName).toSet(),
          expected,
          reason: '${mode.label} must not offer recipes from another mode.',
        );
        if (mode == CraftMode.cooking) {
          expect(
            controller.recipes['Barley Flour']?.type.trim().toLowerCase(),
            'processing',
          );
          expect(
            controller.quotes.any(
              (quote) => quote.recipeName == 'Barley Flour',
            ),
            isFalse,
            reason: 'Supporting ingredients stay resolvable, not selectable.',
          );
          expect(
            controller.quotes.any((quote) => quote.recipeName == 'Beer'),
            isTrue,
          );
        }
      }
      expect(harness.bundle.controller.documentSnapshot, same(plannerBefore));
      expect(tester.takeException(), isNull);
      await _completeIo(tester, window.beforeClose!());
      await tester.pumpWidget(const SizedBox.shrink());
      await _completeIo(tester, harness.dispose());
    },
  );
}

Finder _topTab(String name) => find.byKey(ValueKey('top-workspace-tab-$name'));

Finder _opportunities({bool includeHidden = false}) =>
    find.byType(OpportunitiesWorkspace, skipOffstage: !includeHidden);

Finder _withinOpportunities(String label) =>
    find.descendant(of: _opportunities(), matching: find.text(label));

Finder _input(String key) => find.descendant(
  of: find.byKey(ValueKey(key)),
  matching: find.byType(TextField),
);

String _inputText(WidgetTester tester, String key) =>
    tester.widget<TextField>(_input(key)).controller!.text;

Future<ApplicationTestHarness> _createHarness(WidgetTester tester) async {
  final harness = (await tester.runAsync(ApplicationTestHarness.create))!;
  await tester.runAsync(harness.disposeControllerOnly);
  return harness.rebindControllerInCurrentZone();
}

Widget _host(
  ApplicationTestHarness harness,
  WindowHostService window, {
  bool autoCheck = false,
  OpportunityMarketService Function(String region)? serviceFactory,
}) => MaterialApp(
  home: ApplicationWorkspace(
    bundle: harness.bundle,
    marketGateway: const EmptyMarketGateway(),
    windowHost: window,
    enableBetaUpdates: false,
    enableOpportunityAutoCheck: autoCheck,
    opportunityMarketServiceFactory: serviceFactory,
  ),
);

// Alternate real I/O with fake-zone microtasks without advancing debounce time.
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

Future<void> _waitFor(WidgetTester tester, bool Function() condition) async {
  for (var i = 0; i < 1500 && !condition(); i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump(const Duration(milliseconds: 20));
  }
  expect(condition(), isTrue, reason: 'Startup market check did not begin.');
}

final class _StartupMarketTransport implements OpportunityMarketTransport {
  final quoteIds = <String>[];
  bool waitingForQuote = false;
  bool aborted = false;
  bool closed = false;

  @override
  Future<OpportunityHttpResponse> post(
    Uri uri, {
    required Map<String, String> headers,
    required String body,
    Future<void>? abortTrigger,
  }) async {
    final id = '${(jsonDecode(body) as Map)['mainKey']}';
    if (uri.path.endsWith('GetBiddingInfoList')) {
      throw StateError('Background startup must not request order books.');
    }
    if (quoteIds.isNotEmpty) {
      waitingForQuote = true;
      await abortTrigger;
      aborted = true;
      throw const MarketFetchCancelledException();
    }
    quoteIds.add(id);
    return OpportunityHttpResponse(
      statusCode: 200,
      bytes: Uint8List.fromList(
        utf8.encode(
          jsonEncode({
            'resultCode': 0,
            'resultMsg': '$id-0-0-1000-100-500000-100-10000-1000-0|',
          }),
        ),
      ),
    );
  }

  @override
  void close() => closed = true;
}

class _RecordingWindowHost extends WindowHostService {
  Future<void> Function()? beforeClose;

  @override
  void installCloseRequestHandler(Future<void> Function()? handler) {
    beforeClose = handler;
  }

  @override
  void removeCloseRequestHandler() => beforeClose = null;

  @override
  Future<bool> isMaximized() async => false;

  @override
  Future<void> setBottomInset(double inset) async {}
}
