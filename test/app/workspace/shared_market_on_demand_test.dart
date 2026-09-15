import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:bdo_craft_planner_flutter/app/state/planner_application_controller.dart';
import 'package:bdo_craft_planner_flutter/app/window/window_host_service.dart';
import 'package:bdo_craft_planner_flutter/app/workspace/application_workspace.dart';
import 'package:bdo_craft_planner_flutter/data/market/shared_market_repository.dart';
import 'package:bdo_craft_planner_flutter/data/opportunities/opportunity_market_service.dart';
import 'package:bdo_craft_planner_flutter/domain/models/craft_mode.dart';
import 'package:bdo_craft_planner_flutter/features/planner/planner_contracts.dart';
import 'package:bdo_craft_planner_flutter/features/planner/planner_keys.dart';
import 'package:bdo_craft_planner_flutter/features/planner/planner_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/application_test_harness.dart';

void main() {
  testWidgets(
    'plan checks reuse five-minute receipts and do not refresh while idle',
    (tester) async {
      final f = await _Fixture.mount(tester);
      await tester.tap(find.byKey(PlannerActionKeys.p04));
      await f.settleCheck(tester);
      final firstIds = List<String>.of(f.transport.ids);
      final firstAt = f.controller.state.value.market.fetchedAt;
      expect(firstIds, isNotEmpty);
      expect(firstIds.length, lessThan(100));
      expect(firstAt, f.now.millisecondsSinceEpoch);

      f.now = f.now.add(const Duration(minutes: 4));
      final fullTarget = f.controller.state.value.ignoreTargetInventory;
      await tester.tap(find.byKey(PlannerActionKeys.p05));
      await f.settleCheck(tester);
      expect(f.controller.state.value.ignoreTargetInventory, !fullTarget);
      await tester.tap(find.byKey(PlannerActionKeys.p04));
      await f.settleCheck(tester);
      expect(f.transport.ids, firstIds);
      expect(f.controller.state.value.market.fetchedAt, firstAt);

      // Ordinary Check Prices follows the same cache rule, even though it is
      // an explicit action. It must not silently use forceRefresh.
      final view = tester.widget<PlannerView>(find.byType(PlannerView));
      final plan = f.controller.plan.value;
      late PlannerMarketRefresh checked;
      await _completeIo(
        tester,
        view.externalActions
            .checkPrices(
              PlannerMarketRequest(
                controller: f.controller,
                materials: plan.missing,
                materialNames: f.controller
                    .recipeRouteMarketNamesForPlan(plan)
                    .toList(),
              ),
            )
            .then((value) => checked = value),
      );
      expect(checked.fetchedAt, firstAt);
      expect(f.transport.ids, firstIds);

      f.now = f.now.add(const Duration(minutes: 2));
      await tester.pump(const Duration(minutes: 6));
      expect(
        f.transport.ids,
        firstIds,
        reason: 'Expiry alone is not a request.',
      );
      expect(f.controller.state.value.market.prices, isNotEmpty);
      expect(f.controller.state.value.market.fetchedAt, firstAt);

      await tester.tap(find.byKey(PlannerActionKeys.p05));
      await f.settleCheck(tester);
      expect(f.transport.ids.length, greaterThan(firstIds.length));
      expect(
        f.controller.state.value.market.fetchedAt,
        f.now.millisecondsSinceEpoch,
      );
      final refreshed = f.transport.ids.length;
      await tester.pump(const Duration(seconds: 2));
      expect(
        f.transport.ids.length,
        refreshed,
        reason: 'Publishing market receipts must not cause a second check.',
      );
      await f.dispose(tester);
    },
  );

  testWidgets(
    'recipe changes and returning to Planner check only the active plan',
    (tester) async {
      final f = await _Fixture.mount(tester);
      await tester.tap(find.byKey(PlannerActionKeys.p04));
      await f.settleCheck(tester);
      expect(f.controller.selectTarget('Pure Powder Reagent'), isTrue);
      await f.settleCheck(tester);
      final bothRecipes = f.transport.ids.length;
      expect(f.controller.selectTarget('Clear Liquid Reagent'), isTrue);
      await f.settleCheck(tester);
      expect(f.transport.ids.length, bothRecipes);

      await tester.tap(_topTab('fish-map'));
      await tester.pump();
      f.now = f.now.add(const Duration(minutes: 6));
      expect(f.controller.selectTarget('Pure Powder Reagent'), isTrue);
      f.harness.bundle.controller.modes[CraftMode.cooking]!.commitAmount('25');
      await tester.pump(const Duration(seconds: 1));
      expect(
        f.transport.ids.length,
        bothRecipes,
        reason: 'Hidden Planner state changes must not start requests.',
      );

      await tester.tap(_topTab('planner'));
      await f.settleCheck(tester);
      expect(f.transport.ids.length, greaterThan(bothRecipes));
      final afterReturn = f.transport.ids.length;
      await tester.tap(_topTab('fish-map'));
      await tester.pump();
      await tester.tap(_topTab('planner'));
      await f.settleCheck(tester);
      expect(f.transport.ids.length, afterReturn);
      expect(
        f.transport.ids.toSet().length,
        lessThan(100),
        reason: 'Only current plan materials, not all inventory, are checked.',
      );
      await f.dispose(tester);
    },
  );

  testWidgets(
    'Buy to Process checks the new raw ingredient and reuses cached materials',
    (tester) async {
      final f = await _Fixture.mount(
        tester,
        activeMode: CraftMode.cooking,
        target: 'Oatmeal',
      );
      await tester.tap(find.byKey(PlannerActionKeys.p04));
      await f.settleCheck(tester);
      final initialIds = List<String>.of(f.transport.ids);
      final honeyId =
          f.controller.state.value.market.tradeMarketIds['Cooking Honey'];
      expect(honeyId, isNotNull);
      expect(initialIds, contains(honeyId));
      final honeyReceipt = f.broker
          .snapshot('eu')
          .items[honeyId]!
          .quoteFetchedAt;
      f.now = f.now.add(const Duration(minutes: 4));

      final needArrow = find.byKey(
        PlannerActionKeys.row('P12', 'missing-acquisition:Cooking Honey'),
      );
      await tester.ensureVisible(needArrow);
      await tester.tap(needArrow);
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('acquisition-choice:Cooking Honey:process')),
      );
      await f.settleCheck(tester);
      expect(f.controller.processesAcquisition('Cooking Honey'), isTrue);
      final beehiveId =
          f.controller.state.value.market.tradeMarketIds['Wild Beehive'];
      expect(beehiveId, isNotNull);
      expect(initialIds, isNot(contains(beehiveId)));
      expect(f.transport.ids.skip(initialIds.length), [beehiveId]);
      expect(
        f.broker.snapshot('eu').items[honeyId]!.quoteFetchedAt,
        honeyReceipt,
      );
      expect(f.broker.snapshot('eu').items[beehiveId]!.quoteFetchedAt, f.now);

      final queueArrow = find.byKey(
        PlannerActionKeys.row('P12', 'queue-title:Cooking Honey'),
      );
      await tester.ensureVisible(queueArrow);
      await tester.tap(queueArrow);
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('acquisition-choice:Cooking Honey:buy')),
      );
      await f.settleCheck(tester);
      expect(f.controller.processesAcquisition('Cooking Honey'), isFalse);
      expect(
        f.transport.ids.skip(initialIds.length),
        [beehiveId],
        reason: 'Returning to Buy must reuse the original honey receipt.',
      );
      expect(f.controller.state.value.market.prices['Cooking Honey'], 1000);
      await f.dispose(tester);
    },
  );

  testWidgets(
    'a recipe change during a held check receives one latest-scope follow-up',
    (tester) async {
      final f = await _Fixture.mount(tester);
      f.transport.hold = Completer<void>();
      await tester.tap(find.byKey(PlannerActionKeys.p04));
      await tester.pump(const Duration(milliseconds: 200));
      await _waitFor(tester, () => f.transport.ids.isNotEmpty);
      final first = f.transport.ids.toSet();
      expect(f.controller.selectTarget('Oil of Fortitude'), isTrue);
      await tester.pump(const Duration(milliseconds: 200));
      expect(f.transport.ids.toSet(), first);
      f.transport.hold!.complete();
      await f.settleCheck(tester);
      expect(f.transport.ids.toSet().difference(first), isNotEmpty);
      expect(
        f.transport.ids.length,
        f.transport.ids.toSet().length,
        reason: 'Overlapping materials are reused rather than fetched twice.',
      );
      expect(f.controller.state.value.market.prices, isNotEmpty);
      final completed = f.transport.ids.length;
      await tester.pump(const Duration(seconds: 2));
      expect(f.transport.ids.length, completed);
      await f.dispose(tester);
    },
  );

  testWidgets('closing cancels the pending planner check and held work', (
    tester,
  ) async {
    final f = await _Fixture.mount(tester);
    await tester.tap(find.byKey(PlannerActionKeys.p04));
    await _completeIo(tester, f.window.beforeClose!());
    await tester.pump(const Duration(milliseconds: 200));
    expect(f.transport.ids, isEmpty);
    await f.dispose(tester);

    final held = await _Fixture.mount(tester);
    held.transport.hold = Completer<void>();
    await tester.tap(find.byKey(PlannerActionKeys.p04));
    await tester.pump(const Duration(milliseconds: 200));
    await _waitFor(tester, () => held.transport.ids.isNotEmpty);
    await _completeIo(tester, held.window.beforeClose!());
    await _waitFor(tester, () => held.transport.aborted);
    expect(held.controller.state.value.market.prices, isEmpty);
    await held.dispose(tester);
  });
}

Finder _topTab(String name) => find.byKey(ValueKey('top-workspace-tab-$name'));

final class _Fixture {
  _Fixture(this.harness);
  final ApplicationTestHarness harness;
  final window = _WindowHost();
  final transport = _Transport();
  DateTime now = DateTime.utc(2026, 9, 11, 12);
  late final SharedMarketRepository broker;
  ModeFeatureController get controller => harness.bundle.controller.active;

  static Future<_Fixture> mount(
    WidgetTester tester, {
    CraftMode activeMode = CraftMode.alchemy,
    String target = 'Clear Liquid Reagent',
  }) async {
    configureApplicationTestSurface(tester, const Size(1500, 940));
    final original = (await tester.runAsync(
      () => ApplicationTestHarness.create(activeMode: activeMode),
    ))!;
    await tester.runAsync(original.disposeControllerOnly);
    final f = _Fixture(original.rebindControllerInCurrentZone());
    f.controller.selectTarget(target);
    f.broker = SharedMarketRepository(
      transport: f.transport,
      utcNow: () => f.now,
      cacheMaxAge: sharedMarketFreshness,
      quoteBatchSize: 100,
      requestSpacing: Duration.zero,
      recoveryRequestSpacing: Duration.zero,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: ApplicationWorkspace(
          bundle: f.harness.bundle,
          sharedMarket: f.broker,
          windowHost: f.window,
          fishMapWorkspace: const SizedBox.shrink(),
          enableBetaUpdates: false,
          enableOpportunityAutoCheck: false,
        ),
      ),
    );
    await tester.pump();
    return f;
  }

  Future<void> settleCheck(WidgetTester tester) async {
    await tester.pump(const Duration(milliseconds: 200));
    await _waitFor(
      tester,
      () =>
          broker.diagnostics.activeRequests == 0 &&
          broker.diagnostics.queuedParts == 0,
    );
    // Complete caller publication and the coalesced shared receipt update.
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pumpAndSettle();
  }

  Future<void> dispose(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await _completeIo(tester, broker.close());
    await _completeIo(tester, harness.dispose());
    expect(tester.takeException(), isNull);
  }
}

final class _WindowHost extends WindowHostService {
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

final class _Transport implements OpportunityMarketTransport {
  final ids = <String>[];
  Completer<void>? hold;
  bool aborted = false;

  @override
  Future<OpportunityHttpResponse> post(
    Uri uri, {
    required Map<String, String> headers,
    required String body,
    Future<void>? abortTrigger,
  }) async {
    expect(
      uri.path.endsWith('GetBiddingInfoList'),
      isFalse,
      reason: 'Planner requests quote and stock evidence only.',
    );
    final payload = jsonDecode(body) as Map<String, dynamic>;
    final bulk = payload['searchResult'] is String;
    final requested = bulk
        ? (payload['searchResult'] as String).split(',')
        : ['${payload['mainKey']}'];
    ids.addAll(requested);
    if (hold != null && !hold!.isCompleted) {
      await Future.any([
        hold!.future,
        if (abortTrigger != null)
          abortTrigger.then((_) {
            aborted = true;
            throw const MarketFetchCancelledException();
          }),
      ]);
    }
    return OpportunityHttpResponse(
      statusCode: 200,
      bytes: Uint8List.fromList(
        utf8.encode(
          jsonEncode({
            'resultCode': 0,
            'resultMsg': bulk
                ? requested.map((id) => '$id-1000-1000-10000').join('|')
                : '${requested.single}-0-0-1000-1000-10000',
          }),
        ),
      ),
    );
  }

  @override
  void close() {}
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
  await _waitFor(tester, () => complete, advance: Duration.zero);
  if (failure != null) Error.throwWithStackTrace(failure!, stack!);
}

Future<void> _waitFor(
  WidgetTester tester,
  bool Function() condition, {
  Duration advance = const Duration(milliseconds: 20),
}) async {
  for (var i = 0; i < 500 && !condition(); i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump(advance);
  }
  expect(condition(), isTrue, reason: 'Expected the controlled market work.');
}
