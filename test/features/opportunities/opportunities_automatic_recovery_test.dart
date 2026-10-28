import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:bdo_craft_planner_flutter/data/catalog/catalog_repository.dart';
import 'package:bdo_craft_planner_flutter/data/market/shared_market_repository.dart';
import 'package:bdo_craft_planner_flutter/data/opportunities/market_eligibility.dart';
import 'package:bdo_craft_planner_flutter/data/opportunities/opportunity_market_service.dart';
import 'package:bdo_craft_planner_flutter/domain/models/catalog_models.dart';
import 'package:bdo_craft_planner_flutter/features/opportunities/opportunities_controller.dart';
import 'package:bdo_craft_planner_flutter/features/opportunities/opportunities_visuals.dart';
import 'package:bdo_craft_planner_flutter/features/opportunities/opportunities_workspace.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/application_test_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final (size, textScale) in [
    (const Size(1500, 940), 1.0),
    (const Size(900, 940), 2.0),
  ]) {
    testWidgets(
      'scrolling cards retain geometry through background details at ${size.width} / $textScale',
      (tester) async {
        final f = await _openWorkspace(
          tester,
          search: '',
          size: size,
          textScale: textScale,
          scrollingRecipes: true,
        );
        try {
          final panes = find.byKey(const ValueKey('opportunities-panes'));
          final list = find.byKey(const PageStorageKey('craft-opportunities'));
          final beforePanes = tester.getRect(panes);
          final beforeList = tester.getRect(list);
          await _pumpUntil(tester, () => f.transport.held.isCompleted);
          expect(f.controller.detailStatus.loading, isTrue);
          expect(_headerProgress(), findsNothing);
          expect(find.textContaining('Market details ·'), findsNothing);
          expect(tester.getRect(panes), beforePanes);
          expect(tester.getRect(list), beforeList);

          await tester.drag(list, const Offset(0, -280));
          await tester.pump(const Duration(seconds: 1));
          final scrollable = tester.state<ScrollableState>(
            find.descendant(of: list, matching: find.byType(Scrollable)).first,
          );
          final position = scrollable.position;
          final offset = position.pixels;
          expect(offset, greaterThan(0));
          final visibleCard = find
              .descendant(
                of: list,
                matching: find.byWidgetPredicate(
                  (w) =>
                      w.key is ValueKey<String> &&
                      (w.key! as ValueKey<String>).value.startsWith(
                        'craft-card:',
                      ),
                ),
              )
              .hitTestable()
              .first;
          final cardKey = tester.widget(visibleCard).key!;
          final cardBounds = tester.getRect(visibleCard);

          f.transport.release.complete();
          await _pumpUntil(
            tester,
            () => f.controller.detailStatus.complete && !f.controller.scanning,
          );
          await _pumpWork(tester, f.controller.calculationSettled);
          expect(f.controller.market.items['9101']!.bookFetchedAt, isNotNull);
          expect(tester.getRect(panes), beforePanes);
          expect(tester.getRect(list), beforeList);
          expect(position.pixels, closeTo(offset, .01));
          expect(tester.getRect(find.byKey(cardKey)), cardBounds);
          expect(_headerProgress(), findsNothing);
          expect(tester.takeException(), isNull);
        } finally {
          await _closeWorkspace(tester, f);
        }
      },
    );

    testWidgets(
      'Demand checks keep the workspace steady while prices finish at ${size.width} / $textScale',
      (tester) async {
        final f = await _openWorkspace(
          tester,
          size: size,
          textScale: textScale,
        );
        try {
          final panes = find.byKey(const ValueKey('opportunities-panes'));
          final before = tester.getRect(panes);
          f.transport.heldPart = _part('9101', true);
          await _selectDemandSort(tester);
          await _pumpUntil(tester, () => f.transport.held.isCompleted);

          expect(f.controller.summaryComplete, isTrue);
          expect(f.controller.summaryStatus.loading, isFalse);
          expect(find.text('Stop check'), findsOneWidget);
          expect(_headerText('Preorders · 0 / 1'), findsNothing);
          expect(_headerProgress(), findsNothing);
          expect(tester.getRect(panes), before);
          expect(find.byType(Dialog), findsNothing);
          expect(tester.takeException(), isNull);

          f.transport.release.complete();
          await _pumpUntil(
            tester,
            () => f.controller.detailStatus.complete && !f.controller.scanning,
          );
          expect(_headerText('Preorders · 0 / 1'), findsNothing);
          expect(_headerText('Preorders · 1 / 1'), findsNothing);
          expect(_headerProgress(), findsNothing);
          expect(find.text('Refresh'), findsOneWidget);
          expect(tester.getRect(panes), before);
        } finally {
          await _closeWorkspace(tester, f);
        }
      },
    );
  }

  testWidgets(
    'Demand header keeps retrying preorder failures after prices finish',
    (tester) async {
      final f = await _openWorkspace(tester, search: '');
      try {
        f.transport.failedPart = _part('9101', true);
        await _selectDemandSort(tester);
        await _pumpUntil(
          tester,
          () => f.activeTimers.isNotEmpty && !f.controller.detailStatus.loading,
        );

        expect(f.controller.summaryComplete, isTrue);
        expect(f.controller.summaryNotice, isNull);
        expect(_headerText('Preorders · 1 / 2 · 1 failed'), findsOneWidget);
        expect(
          _headerText('Retrying missing market data shortly.'),
          findsOneWidget,
        );
        expect(_headerProgress(), findsNothing);

        await _pumpWork(tester, f.fireNext());
        await _pumpWork(tester, f.fireNext());
        expect(f.nextTimer.delay, const Duration(minutes: 1));
        expect(f.controller.scanning, isFalse);
        const failure = 'Retrying missing market data shortly.';
        expect(_headerText(failure), findsOneWidget);
        expect(_headerText('Preorders · 1 / 2 · 1 failed'), findsOneWidget);
        expect(_headerProgress(), findsNothing);

        f.transport.failedPart = null;
        await _pumpWork(tester, f.fireNext());
        await _pumpUntil(
          tester,
          () => f.controller.detailStatus.complete && !f.controller.scanning,
        );
        expect(_headerText(failure), findsNothing);
        expect(_headerText('Preorders · 1 / 2 · 1 failed'), findsNothing);
        expect(f.controller.summaryComplete, isTrue);
      } finally {
        await _closeWorkspace(tester, f);
      }
    },
  );

  testWidgets(
    'Demand header exposes a throttled preorder pause and clears after recovery',
    (tester) async {
      final f = await _openWorkspace(tester);
      try {
        f.transport
          ..status = 429
          ..retryAfter = 90;
        await _selectDemandSort(tester);
        await _pumpUntil(
          tester,
          () => f.activeTimers.isNotEmpty && !f.controller.detailStatus.loading,
        );

        expect(f.controller.summaryComplete, isTrue);
        expect(f.controller.summaryNotice, isNull);
        const waiting = 'Market is busy. Retrying automatically.';
        expect(_headerText(waiting), findsOneWidget);
        expect(_headerText('Preorders · 0 / 1 · 1 failed'), findsOneWidget);
        expect(_headerProgress(), findsNothing);
        expect(f.nextTimer.delay, const Duration(seconds: 90));

        f.transport.status = null;
        await _pumpWork(tester, f.fireNext());
        expect(f.controller.detailStatus.complete, isTrue);
        expect(_headerText(waiting), findsNothing);
        expect(_headerText('Preorders · 0 / 1 · 1 failed'), findsNothing);
      } finally {
        await _closeWorkspace(tester, f);
      }
    },
  );

  testWidgets(
    'Demand header keeps blocked preorder warnings when prices are complete',
    (tester) async {
      final f = await _openWorkspace(tester);
      try {
        f.transport.protected = true;
        await _selectDemandSort(tester);
        await _pumpUntil(
          tester,
          () =>
              f.controller.detailStatus.blocked &&
              !f.controller.detailStatus.loading,
        );

        expect(f.controller.summaryComplete, isTrue);
        expect(f.controller.summaryNotice, isNull);
        expect(f.activeTimers, isEmpty);
        expect(_headerText('Preorders · 0 / 1 · 1 failed'), findsOneWidget);
        expect(
          _headerText('Market access is blocked. Loaded prices are kept.'),
          findsOneWidget,
        );
        expect(_headerProgress(), findsNothing);
        expect(find.text('Refresh in'), findsOneWidget);
        expect(f.controller.refreshReadiness.providerPaused, isTrue);
        final refresh = tester.widget<OpportunityButton>(
          find.byKey(const ValueKey('opportunities-refresh')),
        );
        expect(refresh.onPressed, isNull);
        final requests = f.transport.requests.length;
        await _pumpWork(tester, f.controller.refresh());
        expect(f.transport.requests, hasLength(requests));
        expect(f.controller.detailStatus.blocked, isTrue);
        expect(f.activeTimers, isEmpty);
      } finally {
        await _closeWorkspace(tester, f);
      }
    },
  );

  test(
    'automatic retry fills only the missing book and keeps the quote time',
    () async {
      final f = await _Fixture.create();
      addTearDown(f.dispose);
      f.transport.failedPart = _part('9101', true);
      await f.loadDepth(['9101']);
      expect(f.nextTimer.delay, const Duration(seconds: 5));
      final quoteTime = f.controller.market.items['9101']!.quoteFetchedAt;
      f.transport
        ..failedPart = null
        ..requests.clear();
      await f.fireNext();
      expect(f.transport.requests, [_part('9101', true)]);
      expect(f.controller.market.items['9101']!.quoteFetchedAt, quoteTime);
      expect(f.controller.market.items['9101']!.bookFetchedAt, f.now);
      expect(f.controller.failedItems, 0);
      expect(f.controller.notice, isNull);
      expect(f.activeTimers, isEmpty);
    },
  );

  test(
    'persistent transient errors keep capped backoff and recover without Refresh',
    () async {
      final f = await _Fixture.create();
      addTearDown(f.dispose);
      f.transport.failedPart = _part('9101', true);
      await f.loadDepth(['9101']);
      final quoteAt = f.controller.market.items['9101']!.quoteFetchedAt;
      for (final seconds in [5, 20, 60, 120, 300, 300]) {
        expect(f.nextTimer.delay, Duration(seconds: seconds));
        await f.fireNext();
      }
      expect(f.nextTimer.delay, const Duration(minutes: 5));
      expect(f.controller.failedItems, 1);
      expect(f.controller.notice, 'Retrying missing market data shortly.');
      final requests = f.transport.requests.length;
      expect(f.controller.market.items['9101']!.quoteFetchedAt, quoteAt);
      f.controller.change((p) => p.craftSearch = 'First');
      f.controller.ensureMarketCurrent();
      await Future<void>.delayed(const Duration(milliseconds: 450));
      // This explicit demand check is after 13m25s: its quote is older than
      // the five-minute automatic age. Only that quote may load immediately;
      // the failed preorder remains on its existing capped retry deadline.
      expect(f.transport.requests.skip(requests), [_part('9101', false)]);
      final checkedQuoteAt = f.controller.market.items['9101']!.quoteFetchedAt;
      expect(checkedQuoteAt, f.now);
      expect(f.nextTimer.delay, const Duration(minutes: 5));
      f.transport
        ..failedPart = null
        ..requests.clear();
      await f.fireNext();
      expect(f.transport.requests, [_part('9101', true)]);
      expect(f.controller.market.items['9101']!.quoteFetchedAt, checkedQuoteAt);
      expect(f.controller.failedItems, 0);
      expect(f.activeTimers, isEmpty);
    },
  );

  for (final fallback in [false, true]) {
    final source = fallback ? 'fallback' : 'shared';
    test(
      '$source manual missing-parts Refresh uses normal book pacing',
      () async {
        final f = await _Fixture.create(
          fallback: fallback,
          orderBookRequestSpacing: const Duration(milliseconds: 40),
          recoveryRequestSpacing: const Duration(seconds: 2),
        );
        addTearDown(f.dispose);
        final missing = {_part('9101', true), _part('9102', true)};
        f.transport.failedParts.addAll(missing);
        await f.loadDepth(['9101', '9102']);
        expect(f.controller.failedItems, 2);
        expect(f.activeTimers, hasLength(1));
        final quoteTimes = {
          for (final part in missing)
            part.key.itemId:
                f.controller.market.items[part.key.itemId]!.quoteFetchedAt,
        };
        f.transport
          ..failedParts.clear()
          ..requests.clear()
          ..startedAt.clear();
        f.now = f.now.add(const Duration(seconds: 1));
        await f.controller.refresh();
        expect(f.transport.requests.toSet(), missing);
        expect(f.transport.startedAt, hasLength(2));
        final gap = f.transport.startedAt[1] - f.transport.startedAt[0];
        expect(gap, greaterThanOrEqualTo(const Duration(milliseconds: 30)));
        expect(
          gap,
          lessThan(const Duration(seconds: 1)),
          reason:
              'Explicit Refresh must not take the two-second test recovery lane.',
        );
        for (final entry in quoteTimes.entries) {
          expect(
            f.controller.market.items[entry.key]!.quoteFetchedAt,
            entry.value,
          );
        }
        expect(f.controller.failedItems, 0);
        expect(f.controller.notice, isNull);
        expect(f.activeTimers, isEmpty);
      },
    );

    test(
      '$source timer retry retains the slower recovery book pacing',
      () async {
        final f = await _Fixture.create(
          fallback: fallback,
          orderBookRequestSpacing: const Duration(milliseconds: 20),
          recoveryRequestSpacing: const Duration(milliseconds: 120),
        );
        addTearDown(f.dispose);
        final missing = {_part('9101', true), _part('9102', true)};
        f.transport.failedParts.addAll(missing);
        await f.loadDepth(['9101', '9102']);
        expect(f.nextTimer.delay, const Duration(seconds: 5));
        f.transport
          ..failedParts.clear()
          ..requests.clear()
          ..startedAt.clear();
        await f.fireNext();
        expect(f.transport.requests.toSet(), missing);
        expect(f.transport.startedAt, hasLength(2));
        expect(
          f.transport.startedAt[1] - f.transport.startedAt[0],
          greaterThanOrEqualTo(const Duration(milliseconds: 100)),
        );
        expect(f.controller.failedItems, 0);
        expect(f.activeTimers, isEmpty);
      },
    );
  }

  test(
    'repeated429 follows each server deadline until automatic success',
    () async {
      final f = await _Fixture.create();
      addTearDown(f.dispose);
      f.transport
        ..status = 429
        ..retryAfter = 90;
      await f.controller.refresh();
      expect(f.nextTimer.delay, const Duration(seconds: 90));
      expect(f.controller.notice, 'Market is busy. Retrying automatically.');
      await f.fireNext();
      expect(f.nextTimer.delay, const Duration(seconds: 90));
      expect(f.controller.failedItems, greaterThan(0));
      final count = f.transport.requests.length;
      f.controller.ensureMarketCurrent();
      await Future<void>.delayed(const Duration(milliseconds: 450));
      expect(f.transport.requests, hasLength(count));
      await f.fireNext();
      expect(f.nextTimer.delay, const Duration(seconds: 90));
      await f.fireNext();
      expect(f.nextTimer.delay, const Duration(minutes: 2));
      f.transport.status = null;
      await f.fireNext();
      expect(f.controller.failedItems, 0);
      expect(f.controller.notice, isNull);
      expect(f.activeTimers, isEmpty);
    },
  );

  test('protective HTML never schedules an automatic retry', () async {
    final f = await _Fixture.create();
    addTearDown(f.dispose);
    f.transport.protected = true;
    await f.controller.refresh();
    expect(f.activeTimers, isEmpty);
    expect(
      f.controller.notice,
      'Market access is blocked. Loaded prices are kept.',
    );
    final count = f.transport.requests.length;
    f.now = f.now.add(const Duration(hours: 4));
    f.controller.change((p) => p.craftSearch = 'Second');
    f.controller.ensureMarketCurrent();
    await Future<void>.delayed(const Duration(milliseconds: 450));
    expect(f.transport.requests, hasLength(count));
    expect(f.activeTimers, isEmpty);
  });

  test(
    'zero Retry-After cannot create an immediate automatic retry loop',
    () async {
      final f = await _Fixture.create();
      addTearDown(f.dispose);
      f.transport
        ..status = 429
        ..retryAfter = 0;
      await f.controller.refresh();
      for (final seconds in [5, 20, 60, 120, 300, 300]) {
        expect(f.nextTimer.delay, Duration(seconds: seconds));
        await f.fireNext();
      }
      f.transport.status = null;
      await f.fireNext();
      expect(f.controller.failedItems, 0);
      expect(f.activeTimers, isEmpty);
    },
  );

  test(
    'repeated book timeouts resume only missing data when healthy',
    () async {
      final f = await _Fixture.create();
      addTearDown(f.dispose);
      f.transport
        ..failedPart = _part('9101', true)
        ..timeout = true;
      await f.loadDepth(['9101']);
      final quoteAt = f.controller.market.items['9101']!.quoteFetchedAt;
      for (final seconds in [5, 20, 60]) {
        expect(f.nextTimer.delay, Duration(seconds: seconds));
        await f.fireNext();
      }
      f.transport
        ..failedPart = null
        ..requests.clear();
      await f.fireNext();
      expect(f.transport.requests, [_part('9101', true)]);
      expect(f.controller.market.items['9101']!.quoteFetchedAt, quoteAt);
      expect(f.controller.failedItems, 0);
      expect(f.activeTimers, isEmpty);
    },
  );

  test('a later429 replaces an existing transient retry deadline', () async {
    final f = await _Fixture.create();
    addTearDown(f.dispose);
    f.transport.failedPart = _part('9101', true);
    await f.loadDepth(['9101']);
    final oldTimer = f.nextTimer;
    expect(oldTimer.delay, const Duration(seconds: 5));
    f.now = f.now.add(const Duration(seconds: 2));
    f.transport
      ..status = 429
      ..retryAfter = 90
      ..requests.clear();
    await f.controller.ensureMarketDepth(['9101', '9102']);
    expect(f.transport.requests, [_part('9102', true)]);
    expect(oldTimer.isActive, isFalse);
    expect(f.nextTimer.delay, const Duration(seconds: 90));
    final deadlineTimer = f.nextTimer;
    final count = f.transport.requests.length;
    // An early timer delivery must rearm instead of spending a retry attempt.
    f.now = f.now.add(const Duration(seconds: 3));
    deadlineTimer.fire();
    await Future<void>.delayed(Duration.zero);
    expect(f.transport.requests, hasLength(count));
    expect(f.nextTimer.delay, const Duration(seconds: 87));
    f.transport
      ..status = null
      ..failedPart = null
      ..requests.clear();
    await f.fireNext();
    expect(f.transport.requests.toSet(), {
      _part('9101', true),
      _part('9102', true),
    });
    expect(f.controller.failedItems, 0);
    expect(f.activeTimers, isEmpty);
  });

  test(
    'successful depth additions do not retry or postpone waiting parts',
    () async {
      final f = await _Fixture.create();
      addTearDown(f.dispose);
      f.transport.failedPart = _part('9101', true);
      await f.loadDepth(['9101']);
      final originalTimer = f.nextTimer;
      f.now = f.now.add(const Duration(seconds: 2));
      f.transport.requests.clear();
      await f.controller.ensureMarketDepth(['9101', '9102']);
      expect(f.transport.requests, [_part('9102', true)]);
      expect(f.nextTimer, same(originalTimer));
      f.now = f.now.add(const Duration(seconds: 3));
      f.transport
        ..failedPart = null
        ..requests.clear();
      originalTimer.fire();
      await Future<void>.delayed(Duration.zero);
      await _until(() => !f.controller.scanning);
      expect(f.transport.requests, [_part('9101', true)]);
      expect(f.controller.failedItems, 0);
      expect(f.activeTimers, isEmpty);
    },
  );

  test(
    'a retry waiting behind held work honors its later server deadline',
    () async {
      final f = await _Fixture.create();
      addTearDown(f.dispose);
      f.transport.failedPart = _part('9101', true);
      await f.loadDepth(['9101']);
      final oldTimer = f.nextTimer;
      f.now = f.now.add(const Duration(seconds: 2));
      f.transport
        ..heldPart = _part('9102', true)
        ..requests.clear();
      final addition = f.controller.ensureMarketDepth(['9101', '9102']);
      await f.transport.held.future;
      f.now = f.now.add(const Duration(seconds: 3));
      oldTimer.fire();
      await Future<void>.delayed(Duration.zero);
      expect(f.transport.requests, [_part('9102', true)]);
      f.transport
        ..status = 429
        ..retryAfter = 90;
      f.transport.release.complete();
      await addition;
      await Future<void>.delayed(Duration.zero);
      expect(f.nextTimer.delay, const Duration(seconds: 90));
      expect(f.transport.requests, [_part('9102', true)]);
      f.transport
        ..status = null
        ..failedPart = null
        ..requests.clear();
      await f.fireNext();
      expect(f.transport.requests.toSet(), {
        _part('9101', true),
        _part('9102', true),
      });
      expect(f.controller.failedItems, 0);
      expect(f.activeTimers, isEmpty);
    },
  );

  for (final stop in [false, true]) {
    test(
      'additive depth preserves held work${stop ? ' until explicit Stop' : ''}',
      () async {
        final f = await _Fixture.create();
        addTearDown(f.dispose);
        await f.controller.refresh();
        f.transport
          ..heldPart = _part('9101', true)
          ..requests.clear();
        final first = f.controller.ensureMarketDepth(['9101']);
        await f.transport.held.future;
        final added = f.controller.ensureMarketDepth(['9101', '9102']);
        await Future<void>.delayed(const Duration(milliseconds: 20));
        expect(f.transport.aborted, isFalse);
        expect(f.transport.requests, [_part('9101', true)]);
        if (stop) f.controller.cancel();
        f.transport.release.complete();
        await Future.wait([first, added]);
        expect(
          f.transport.requests.where((part) => part == _part('9101', true)),
          hasLength(1),
        );
        if (stop) {
          expect(f.transport.requests, [_part('9101', true)]);
          expect(f.activeTimers, isEmpty);
        } else {
          expect(f.transport.aborted, isFalse);
          expect(f.transport.requests, [
            _part('9101', true),
            _part('9102', true),
          ]);
          expect(f.controller.detailStatus.complete, isTrue);
        }
      },
    );
  }

  test(
    'a removed failed book does not rejoin the retained scan retry',
    () async {
      final f = await _Fixture.create();
      addTearDown(f.dispose);
      await f.controller.refresh();
      f.transport
        ..failedPart = _part('9101', true)
        ..heldPart = _part('9102', true)
        ..requests.clear();
      f.transport.failedParts.add(_part('9102', true));
      final details = f.controller.ensureMarketDepth(['9101', '9102']);
      await f.transport.held.future;
      final narrowed = f.controller.ensureMarketDepth(['9102']);
      await Future<void>.delayed(Duration.zero);
      expect(f.transport.aborted, isFalse);
      expect(f.controller.progressFraction, 0);
      f.transport.release.complete();
      await Future.wait([details, narrowed]);
      expect(f.controller.detailStatus.total, 1);
      expect(f.controller.detailStatus.failed, 1);
      expect(f.nextTimer.delay, const Duration(seconds: 5));
      f.transport
        ..failedPart = null
        ..failedParts.clear()
        ..requests.clear();
      await f.fireNext();
      expect(f.transport.requests, [_part('9102', true)]);
      expect(f.controller.detailStatus.complete, isTrue);
      expect(f.controller.failedItems, 0);
      expect(f.activeTimers, isEmpty);
      expect(f.controller.market.items['9101']!.bookFetchedAt, isNull);
    },
  );

  test(
    'temporary service construction errors recover but programming errors do not',
    () async {
      final f = await _Fixture.create(fallback: true);
      addTearDown(f.dispose);
      f.serviceCreationError = TimeoutException(
        'Synthetic construction timeout',
      );
      await f.controller.refresh();
      expect(f.transport.requests, isEmpty);
      expect(f.nextTimer.delay, const Duration(seconds: 5));
      f.serviceCreationError = null;
      await f.fireNext();
      expect(f.controller.summaryComplete, isTrue);
      expect(f.activeTimers, isEmpty);
      f.serviceCreationError = StateError('Synthetic programming error');
      await f.controller.refresh();
      expect(f.activeTimers, isEmpty);
      expect(f.controller.notice, contains('could not be reached'));
    },
  );

  test('fallback retained protection is not labelled a new denial', () async {
    final f = await _Fixture.create(fallback: true);
    addTearDown(f.dispose);
    f.transport.protected = true;
    await f.controller.refresh();
    expect(
      f.controller.notice,
      'Market access is blocked. Loaded prices are kept.',
    );
    final requestCount = f.transport.requests.length;
    await f.controller.refresh();
    expect(f.transport.requests, hasLength(requestCount));
    expect(
      f.controller.notice,
      'Market access was blocked earlier. Prices are kept. Try Refresh.',
    );
    f.now = f.now.add(const Duration(minutes: 2));
    await f.controller.refresh(onlyStale: true);
    expect(f.transport.requests, hasLength(requestCount));
    expect(f.activeTimers, isEmpty);
    await f.controller.refresh();
    expect(f.transport.requests.length, greaterThan(requestCount));
    expect(
      f.controller.notice,
      'Market access is blocked. Loaded prices are kept.',
    );
    expect(f.activeTimers, isEmpty);
  });

  test('Stop does not revive recovery on tab return or cache expiry', () async {
    final f = await _Fixture.create();
    try {
      f.transport.failedPart = _part('9101', true);
      await f.loadDepth(['9101']);
      expect(f.activeTimers, hasLength(1));
      f.controller.cancel();
      expect(f.activeTimers, isEmpty);
      final count = f.transport.requests.length;
      f.now = f.now.add(const Duration(hours: 4));
      f.controller.ensureMarketCurrent();
      f.controller.change((p) => p.craftSearch = 'First');
      await Future<void>.delayed(const Duration(milliseconds: 450));
      expect(f.transport.requests, hasLength(count));
      expect(f.activeTimers, isEmpty);
    } finally {
      await f.dispose();
    }
  });

  test(
    'flush waits for visibility before resuming the same recovery backoff',
    () async {
      final f = await _Fixture.create();
      addTearDown(f.dispose);
      f.transport.failedPart = _part('9101', true);
      await f.loadDepth(['9101']);
      await f.fireNext();
      expect(f.nextTimer.delay, const Duration(seconds: 20));
      await f.controller.flush();
      expect(f.activeTimers, isEmpty);
      final count = f.transport.requests.length;
      f.now = f.now.add(const Duration(seconds: 8));
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(f.transport.requests, hasLength(count));
      expect(f.activeTimers, isEmpty);
      f.controller.ensureMarketCurrent();
      expect(f.nextTimer.delay, const Duration(seconds: 12));
      await f.fireNext();
      expect(f.nextTimer.delay, const Duration(minutes: 1));
      expect(f.controller.failedItems, 1);
    },
  );

  test(
    'switching to a waiting region cancels the old active caller first',
    () async {
      final f = await _Fixture.create();
      addTearDown(f.dispose);
      f.controller.change((p) => p.region = 'na');
      f.transport.failedPart = _part('9101', false, region: 'na');
      await f.controller.refresh();
      expect(f.activeTimers, hasLength(1));
      f.controller.change((p) => p.region = 'eu');
      f.transport.heldPart = _part('9101', false);
      final oldScan = f.controller.refresh();
      await f.transport.held.future;
      f.controller.change((p) => p.region = 'na');
      await oldScan;
      expect(f.transport.aborted, isTrue);
      expect(f.activeTimers, hasLength(1));
      f.transport.failedPart = null;
      await f.fireNext();
      expect(f.controller.failedItems, 0);
      expect(f.controller.notice, isNull);
    },
  );

  test(
    'region return resumes the existing deadline without resetting backoff',
    () async {
      final f = await _Fixture.create();
      addTearDown(f.dispose);
      f.transport.failedPart = _part('9101', false);
      await f.controller.refresh();
      await f.fireNext();
      expect(f.nextTimer.delay, const Duration(seconds: 20));
      f.controller.change((p) => p.region = 'na');
      expect(f.activeTimers, isEmpty);
      await f.controller.refresh();
      expect(f.controller.failedItems, 0);
      f.now = f.now.add(const Duration(seconds: 8));
      f.controller.change((p) => p.region = 'eu');
      expect(f.nextTimer.delay, const Duration(seconds: 12));
      await f.fireNext();
      expect(f.nextTimer.delay, const Duration(minutes: 1));
      expect(f.controller.failedItems, 1);
    },
  );

  test('a successful sibling receipt cancels pending automatic work', () async {
    final f = await _Fixture.create();
    addTearDown(f.dispose);
    final part = _part('9101', true);
    f.transport.failedPart = part;
    await f.loadDepth(['9101']);
    f.transport.failedPart = null;
    f.now = f.now.add(const Duration(seconds: 1));
    await f.broker.fetch(
      bookKeys: [part.key],
      forceRefresh: true,
      userInitiated: true,
    );
    await _until(() => f.controller.failedItems == 0);
    expect(f.activeTimers, isEmpty);
    expect(f.controller.notice, isNull);
  });

  test('503 and429 transitions retain continuing backoff', () async {
    final f = await _Fixture.create();
    addTearDown(f.dispose);
    f.transport
      ..status = 503
      ..retryAfter = 7;
    await f.controller.refresh();
    expect(f.nextTimer.delay, const Duration(seconds: 7));
    f.transport
      ..status = 429
      ..retryAfter = 11;
    await f.fireNext();
    expect(f.nextTimer.delay, const Duration(seconds: 11));
    f.transport
      ..status = 503
      ..retryAfter = 2;
    await f.fireNext();
    expect(f.nextTimer.delay, const Duration(seconds: 20));
    await f.fireNext();
    expect(f.nextTimer.delay, const Duration(minutes: 1));
    expect(f.controller.failedItems, greaterThan(0));
  });

  test(
    'timeout then429 in one batch continues to honor throttle backoff',
    () async {
      final f = await _Fixture.create();
      addTearDown(f.dispose);
      f.transport.scripted.addAll([(0, null), (429, 11)]);
      await f.controller.refresh();
      expect(f.nextTimer.delay, const Duration(seconds: 11));
      expect(f.controller.notice, 'Market is busy. Retrying automatically.');
      f.transport
        ..status = 429
        ..retryAfter = 11;
      await f.fireNext();
      expect(f.nextTimer.delay, const Duration(seconds: 20));
      expect(f.controller.failedItems, greaterThan(0));
      f.transport.status = null;
      await f.fireNext();
      expect(f.controller.failedItems, 0);
      expect(f.activeTimers, isEmpty);
    },
  );

  test(
    'early fallback Refresh keeps the automatic429 resume deadline',
    () async {
      final f = await _Fixture.create(fallback: true);
      addTearDown(f.dispose);
      f.transport
        ..status = 429
        ..retryAfter = 20;
      await f.controller.refresh();
      expect(f.nextTimer.delay, const Duration(seconds: 20));
      final count = f.transport.requests.length;
      f.now = f.now.add(const Duration(seconds: 5));
      await f.controller.refresh();
      expect(f.transport.requests, hasLength(count));
      expect(f.nextTimer.delay, const Duration(seconds: 15));
      f.transport.status = null;
      await f.fireNext();
      expect(f.controller.failedItems, 0);
      expect(f.controller.notice, isNull);
    },
  );

  test(
    'successful fallback manual recovery clears protection for later expiry',
    () async {
      final f = await _Fixture.create(fallback: true);
      addTearDown(f.dispose);
      f.transport.protected = true;
      await f.controller.refresh();
      expect(f.activeTimers, isEmpty);
      f.now = f.now.add(const Duration(seconds: 61));
      f.transport.protected = false;
      await f.controller.refresh();
      expect(f.controller.notice, isNull);
      final count = f.transport.requests.length;
      f.now = f.now.add(const Duration(hours: 3, seconds: 1));
      f.controller.ensureMarketCurrent();
      await _until(
        () => f.transport.requests.length > count && !f.controller.scanning,
      );
      expect(f.controller.notice, isNull);
      expect(f.controller.failedItems, 0);
    },
  );

  test(
    'Stop then manual resume retains unfinished whole-startup targets',
    () async {
      final f = await _Fixture.create(startup: true, holdStartup: true);
      addTearDown(f.dispose);
      await f.transport.held.future;
      final offscreen = f.transport.heldPart!;
      f.controller.cancel();
      await _until(() => !f.controller.scanning);
      expect(f.controller.failedItems, 0);
      final freshParts = {
        for (final item in f.controller.market.items.values) ...[
          if (item.quoteIsFresh(f.now, OpportunitiesController.maxMarketAge))
            _part(item.itemId, false),
          if (item.bookIsFresh(f.now, OpportunitiesController.maxMarketAge))
            _part(item.itemId, true),
        ],
      };
      f.transport.release.complete();
      f.transport.requests.clear();
      f.controller.change((p) {
        p.section = 'exchanges';
        p.currencyId = 'witchs-delicacy';
      });
      await f.controller.refresh();
      expect(f.transport.requests, contains(offscreen));
      expect(f.transport.requests.any(freshParts.contains), isFalse);
      expect(f.controller.failedItems, 0);
      expect(f.controller.notice, isNull);
    },
  );

  test(
    'explicit offscreen Processing depth recovers after quote-only startup',
    () async {
      final f = await _Fixture.create(startup: true);
      addTearDown(f.dispose);
      await _until(
        () => f.transport.requests.isNotEmpty && !f.controller.scanning,
      );
      expect(f.transport.requests.length, greaterThan(1000));
      expect(
        f.transport.requests.every(
          (part) => part.part == SharedMarketPart.quote,
        ),
        isTrue,
      );
      final missing = f.transport.failedPart!;
      final quoteAt =
          f.controller.market.items[missing.key.itemId]!.quoteFetchedAt;
      expect(quoteAt, isNotNull);
      await f.controller.ensureMarketDepth([missing.key.itemId]);
      expect(f.activeTimers, hasLength(1));
      f.controller.change((p) => p.craftSearch = 'Beer');
      f.transport
        ..failedPart = null
        ..requests.clear();
      await f.fireNext();
      expect(f.transport.requests, [missing]);
      expect(
        f.controller.market.items[missing.key.itemId]!.quoteFetchedAt,
        quoteAt,
      );
      expect(f.controller.failedItems, 0);
      expect(f.controller.notice, isNull);
    },
  );
}

SharedMarketPartKey _part(String id, bool book, {String region = 'eu'}) =>
    SharedMarketPartKey(
      SharedMarketKey(region: region, itemId: id),
      book ? SharedMarketPart.orderBook : SharedMarketPart.quote,
    );

Future<void> _selectDemandSort(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('craft-sort-preorders')));
  await tester.pump();
}

Finder _headerText(String text) => find.descendant(
  of: find.byKey(const ValueKey('opportunities-market-progress')),
  matching: find.text(text),
);

Finder _headerProgress() => find.descendant(
  of: find.byKey(const ValueKey('opportunities-market-progress')),
  matching: find.byType(LinearProgressIndicator),
);

Future<_Fixture> _openWorkspace(
  WidgetTester tester, {
  String search = 'First',
  Size size = const Size(1500, 940),
  double textScale = 1,
  bool scrollingRecipes = false,
}) async {
  configureApplicationTestSurface(tester, size);
  final f = (await tester.runAsync(() async {
    final fixture = await _Fixture.create();
    if (scrollingRecipes) {
      fixture.controller.recipes = {
        ...fixture.controller.recipes,
        for (var i = 0; i < 40; i++)
          'Example $i': _recipe('Example $i', '9101', input: 'Raw A'),
      };
      fixture.transport.heldPart = _part('9101', true);
    }
    fixture.controller.change((p) {
      p.craftSearch = search;
      p.profitableOnly = false;
    });
    await fixture.controller.refresh();
    await fixture.controller.calculationSettled;
    fixture.controller.setWorkspaceActive(true);
    return fixture;
  }))!;
  expect(f.controller.summaryComplete, isTrue);
  expect(f.controller.detailStatus.requested, isFalse);
  await tester.pumpWidget(
    MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: Scaffold(body: OpportunitiesWorkspace(controller: f.controller)),
    ),
  );
  await tester.pump();
  return f;
}

Future<void> _closeWorkspace(WidgetTester tester, _Fixture fixture) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await _pumpWork(tester, fixture.dispose());
}

Future<void> _pumpUntil(WidgetTester tester, bool Function() condition) async {
  for (var attempt = 0; attempt < 500 && !condition(); attempt++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump(const Duration(milliseconds: 20));
  }
  expect(
    condition(),
    isTrue,
    reason: 'Market workspace should reach its state',
  );
  await tester.pump();
}

// UI callbacks and their saves start in the fake zone; fixture I/O starts in
// the real zone. Drain both instead of blocking either with runAsync(dispose).
Future<void> _pumpWork(WidgetTester tester, Future<void> work) async {
  var done = false;
  Object? error;
  StackTrace? stack;
  unawaited(
    work.then(
      (_) => done = true,
      onError: (Object failure, StackTrace trace) {
        error = failure;
        stack = trace;
        done = true;
      },
    ),
  );
  await _pumpUntil(tester, () => done);
  if (error != null) Error.throwWithStackTrace(error!, stack!);
}

final class _Fixture {
  _Fixture(this.harness);
  final ApplicationTestHarness harness;
  DateTime now = DateTime.utc(2026, 9, 10, 16);
  final List<_TestTimer> timers = [];
  late final _Transport transport;
  late final SharedMarketRepository broker;
  late final OpportunitiesController controller;
  Object? serviceCreationError;
  Iterable<_TestTimer> get activeTimers =>
      timers.where((timer) => timer.isActive);
  _TestTimer get nextTimer => activeTimers.single;

  static Future<_Fixture> create({
    bool startup = false,
    bool fallback = false,
    bool holdStartup = false,
    Duration orderBookRequestSpacing = Duration.zero,
    Duration recoveryRequestSpacing = Duration.zero,
  }) async {
    final f = _Fixture(await ApplicationTestHarness.create());
    f.transport = _Transport(() => f.now);
    if (startup) {
      final cookingIds = f.harness.bundle.catalog.cooking.items.values
          .map((recipe) => recipe.marketId)
          .toSet();
      final id = f.harness.bundle.catalog.processing.items.values
          .firstWhere(
            (recipe) =>
                recipe.isCraftable &&
                recipe.marketId != null &&
                !cookingIds.contains(recipe.marketId) &&
                isOpportunityMarketRequestEligible(recipe.marketId!),
          )
          .marketId!;
      if (holdStartup) {
        f.transport.heldPart = _part(id, false);
      } else {
        f.transport.failedPart = _part(id, true);
      }
    }
    f.broker = SharedMarketRepository(
      transport: f.transport,
      utcNow: () => f.now,
      requestSpacing: Duration.zero,
      orderBookRequestSpacing: orderBookRequestSpacing,
      recoveryRequestSpacing: recoveryRequestSpacing,
      quoteBatchSize: startup ? 40 : 1,
      concurrency: 1,
    );
    f.controller = OpportunitiesController(
      appController: f.harness.bundle.controller,
      catalog: CatalogRepository(f.harness.bundle.catalog),
      directory: f.harness.temporaryDirectory,
      clock: () => f.now,
      sharedMarket: fallback ? null : f.broker,
      serviceFactory: (region) {
        if (f.serviceCreationError case final Object error) throw error;
        return OpportunityMarketService(
          region: region,
          transport: f.transport,
          utcNow: () => f.now,
          concurrency: 1,
          quoteBatchSize: 1,
          requestSpacing: Duration.zero,
          orderBookRequestSpacing: orderBookRequestSpacing,
          recoveryRequestSpacing: recoveryRequestSpacing,
        );
      },
      autoCheck: true,
      prefetchAll: startup,
      recoveryTimerFactory: (delay, callback) {
        final timer = _TestTimer(delay, callback);
        f.timers.add(timer);
        return timer;
      },
    );
    await f.controller.ready;
    if (!startup) {
      f.controller.cancel();
      await _until(() => !f.controller.scanning);
      f.controller.recipes = {
        'First': _recipe('First', '9101', input: 'Raw A'),
        'Second': _recipe('Second', '9102', input: 'Raw B'),
        'Raw A': _recipe('Raw A', '9201'),
        'Raw B': _recipe('Raw B', '9202'),
      };
      f.controller.recalculate();
      await f.controller.calculationSettled;
      f.transport.requests.clear();
    }
    return f;
  }

  Future<void> fireNext() async {
    final timer = nextTimer;
    now = now.add(timer.delay);
    timer.fire();
    await Future<void>.delayed(Duration.zero);
    await _until(() => !controller.scanning);
    await controller.calculationSettled;
  }

  Future<void> loadDepth(Iterable<String> ids) async {
    await controller.refresh();
    await controller.ensureMarketDepth(ids);
  }

  Future<void> dispose() async {
    controller.cancel();
    if (!transport.release.isCompleted) transport.release.complete();
    await broker.close();
    await controller.flush();
    controller.dispose();
    await harness.dispose();
  }
}

final class _TestTimer implements Timer {
  _TestTimer(this.delay, this.callback);
  final Duration delay;
  final void Function() callback;
  bool _active = true;
  int _tick = 0;
  @override
  bool get isActive => _active;
  @override
  int get tick => _tick;
  @override
  void cancel() => _active = false;
  void fire() {
    if (!_active) return;
    _active = false;
    _tick++;
    callback();
  }
}

Recipe _recipe(String name, String id, {String? input}) => Recipe(
  name: name,
  type: input == null ? 'gathered' : 'cooking',
  baseOutput: 1,
  group: null,
  method: null,
  ingredients: [
    if (input != null)
      Ingredient(
        name: input,
        quantity: 1,
        options: const [],
        substituteGroup: null,
        substituteRatios: const {},
      ),
  ],
  marketId: id,
  sourceNote: null,
  vendor: null,
  location: null,
  npcPrice: 0,
  qualityBase: null,
  qualityGrade: null,
  outputMinimum: 2,
  outputMaximum: 2,
);

final class _Transport implements OpportunityMarketTransport {
  _Transport(this.now);
  final DateTime Function() now;
  final List<SharedMarketPartKey> requests = [];
  final List<Duration> startedAt = [];
  final Stopwatch elapsed = Stopwatch()..start();
  final Set<SharedMarketPartKey> failedParts = {};
  SharedMarketPartKey? failedPart;
  int? status;
  int? retryAfter;
  final List<(int, int?)> scripted = [];
  bool protected = false;
  bool timeout = false;
  SharedMarketPartKey? heldPart;
  final held = Completer<void>();
  final release = Completer<void>();
  bool aborted = false;
  @override
  Future<OpportunityHttpResponse> post(
    Uri uri, {
    required Map<String, String> headers,
    required String body,
    Future<void>? abortTrigger,
  }) async {
    final payload = jsonDecode(body) as Map;
    final ids = payload['searchResult'] is String
        ? (payload['searchResult'] as String).split(',')
        : ['${payload['mainKey']}'];
    final book = uri.path.endsWith('GetBiddingInfoList');
    final region = uri.host.startsWith('na-') ? 'na' : 'eu';
    final parts = ids.map((id) => _part(id, book, region: region)).toList();
    requests.addAll(parts);
    startedAt.add(elapsed.elapsed);
    if (scripted.isNotEmpty) {
      final (code, wait) = scripted.removeAt(0);
      if (code == 0) throw TimeoutException('Synthetic timeout');
      return OpportunityHttpResponse(
        statusCode: code,
        headers: {if (wait != null) 'retry-after': '$wait'},
        bytes: Uint8List(0),
      );
    }
    if (parts.contains(heldPart) && !release.isCompleted) {
      if (!held.isCompleted) held.complete();
      await Future.any([
        release.future,
        if (abortTrigger != null)
          abortTrigger.then((_) {
            aborted = true;
            throw const MarketFetchCancelledException();
          }),
      ]);
    }
    if (protected) {
      return OpportunityHttpResponse(
        statusCode: 200,
        bytes: Uint8List.fromList(
          utf8.encode('<html>Incapsula incident ID</html>'),
        ),
      );
    }
    if (status != null ||
        parts.contains(failedPart) ||
        parts.any(failedParts.contains)) {
      if (timeout) throw TimeoutException('Synthetic timeout');
      return OpportunityHttpResponse(
        statusCode: status ?? 503,
        headers: {if (retryAfter != null) 'retry-after': '$retryAfter'},
        bytes: Uint8List(0),
      );
    }
    final text = ids.length > 1
        ? ids.map((id) => '$id-1234-1000-500000').join('|')
        : book
        ? '1000-100000-0|'
        : '${ids.single}-0-0-1000-1234-500000-100-10000-1000-${now().millisecondsSinceEpoch ~/ 1000}|';
    return OpportunityHttpResponse(
      statusCode: 200,
      bytes: Uint8List.fromList(
        utf8.encode(jsonEncode({'resultCode': 0, 'resultMsg': text})),
      ),
    );
  }

  @override
  void close() {}
}

Future<void> _until(bool Function() condition) async {
  final until = DateTime.now().add(const Duration(seconds: 30));
  while (!condition()) {
    if (DateTime.now().isAfter(until)) {
      fail('Automatic recovery did not settle.');
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}
