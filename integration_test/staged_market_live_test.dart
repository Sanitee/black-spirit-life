import 'dart:convert';
import 'dart:io';

import 'package:bdo_craft_planner_flutter/app/application_bootstrap.dart';
import 'package:bdo_craft_planner_flutter/app/workspace/application_workspace.dart';
import 'package:bdo_craft_planner_flutter/data/market/market_response_guard.dart';
import 'package:bdo_craft_planner_flutter/data/market/shared_market_repository.dart';
import 'package:bdo_craft_planner_flutter/data/opportunities/opportunity_market_cache_store.dart';
import 'package:bdo_craft_planner_flutter/data/opportunities/opportunity_market_service.dart';
import 'package:bdo_craft_planner_flutter/data/persistence/planner_state_repository.dart';
import 'package:bdo_craft_planner_flutter/features/opportunities/opportunities_controller.dart';
import 'package:bdo_craft_planner_flutter/features/opportunities/opportunities_visuals.dart';
import 'package:bdo_craft_planner_flutter/features/opportunities/opportunities_workspace.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

// Opt-in normal workflow, not a capacity test. It uses the production transport,
// parser, broker, catalog, controller and UI. No live profile is modified.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
  const enabled = bool.fromEnvironment('LIVE_STAGED_MARKET');
  const requireFullFreshRefresh = bool.fromEnvironment(
    'LIVE_FULL_FRESH_REFRESH',
  );
  const authorizeExpiredPauseRetry = bool.fromEnvironment(
    'LIVE_AUTHORIZE_EXPIRED_PAUSE_RETRY',
  );
  const evidencePath = String.fromEnvironment('MARKET_EVIDENCE_PATH');
  const liveProfile = String.fromEnvironment('MARKET_READ_ONLY_PROFILE');

  testWidgets(
    'cold summaries, inspected recipes, demand and warm cache',
    (tester) async {
      // Profile-mode Windows input needs an explicit test client.
      tester.testTextInput.register();
      addTearDown(tester.testTextInput.unregister);
      if (evidencePath.isEmpty || liveProfile.isEmpty) {
        throw StateError(
          'Explicit evidence and read-only profile paths required.',
        );
      }
      final reportFile = File(evidencePath);
      if (await reportFile.exists()) {
        throw StateError(
          'Evidence already exists; do not repeat live requests.',
        );
      }
      final root = await Directory.systemTemp.createTemp(
        'bsl-staged-market-live-',
      );
      final data = Directory('${root.path}/profile');
      final marketDirectory = Directory('${data.path}/opportunities');
      await marketDirectory.create(recursive: true);
      final sourcePause = File('$liveProfile/market-request-pauses.json');
      final sourceCache = File('$liveProfile/opportunity-market-cache.json');
      final sourceWindow = File('$liveProfile/market-request-window.json');
      final windowBefore = await sourceWindow.exists()
          ? await sourceWindow.readAsString()
          : null;
      if (windowBefore != null) {
        await File(
          '${marketDirectory.path}/market-request-window.json',
        ).writeAsString(windowBefore);
      }
      final pauseBefore = await sourcePause.exists()
          ? await sourcePause.readAsString()
          : null;
      final cacheBefore = await sourceCache.exists()
          ? await sourceCache.readAsString()
          : null;
      // Cold market data is intentional; the actual pause and request ledger
      // still carry forward unchanged from the latest failed session.
      var inheritedProtectedPause = false;
      num? inheritedRetryAt;
      if (pauseBefore != null) {
        final decoded = jsonDecode(pauseBefore) as Map;
        final pause = (decoded['regions'] as Map?)?['eu'] as Map?;
        final until = pause?['retryAt'];
        inheritedProtectedPause = pause?['reason'] == 'protected';
        inheritedRetryAt = until is num ? until : null;
        if (until is num && DateTime.now().millisecondsSinceEpoch < until) {
          throw StateError('The provider waiting period is still active.');
        }
        if (inheritedProtectedPause &&
            (!authorizeExpiredPauseRetry || until is! num)) {
          throw StateError(
            'An expired protected pause requires explicit retry authorization.',
          );
        }
        // Carry operational state forward; never clear a protective denial to
        // make an isolated performance test look successful.
        await File(
          '${marketDirectory.path}/market-request-pauses.json',
        ).writeAsString(pauseBefore);
      }
      final transport = _ObservedTransport();
      final broker = SharedMarketRepository.application(
        cacheStore: OpportunityMarketCacheStore(directory: marketDirectory),
        transport: transport,
      );
      final bundle = await const ApplicationBootstrapService().load(
        pathPolicy: PlannerStatePathPolicy(
          applicationDirectory: data,
          legacyStateFile: File('${root.path}/nonexistent-legacy.json'),
        ),
      );
      OpportunitiesController? controller;
      var observed = transport;
      final report = <String, Object?>{
        'startedAt': DateTime.now().toUtc().toIso8601String(),
        'isolatedProfile': data.path,
        'readOnlyProfile': liveProfile,
        'initialState': {
          'marketData': 'cold cache; source cache is not copied',
          'operationalState': 'original pause and request window retained',
          'sourceCachePresent': cacheBefore != null,
          'inheritedProtectedPause': inheritedProtectedPause,
          'inheritedRetryAt': inheritedRetryAt,
          'expiredPauseRetryAuthorized': authorizeExpiredPauseRetry,
        },
        'requests': transport.requests,
        'policy': {
          'workers': broker.concurrency,
          'primeSession': broker.primeSession,
          'quoteBatchSize': broker.quoteBatchSize,
          'searchCharacterLimit': sharedMarketSearchCharacterLimit,
          'requestWindowLimit': broker.requestWindowLimit,
          'requestWindowDurationMs':
              broker.requestWindowDuration.inMilliseconds,
          'orderBookStartGapMs': broker.orderBookRequestSpacing.inMilliseconds,
          'minimumBookRefreshAgeMs':
              broker.minimumBookRefreshAge.inMilliseconds,
          'minimumQuoteRefreshAgeMs':
              broker.minimumQuoteRefreshAge.inMilliseconds,
          'timeoutMs': broker.requestTimeout.inMilliseconds,
        },
        'phases': <String, Object?>{},
        'passed': false,
      };
      final phases = report['phases']! as Map<String, Object?>;
      final total = Stopwatch()..start();

      Future<void> waitFor(
        bool Function() predicate,
        String description,
      ) async {
        final timer = Stopwatch()..start();
        while (!predicate() && timer.elapsed < const Duration(seconds: 100)) {
          if (observed.failed || broker.diagnostics.failedRequests > 0) {
            controller?.cancel();
            throw StateError(
              'Market failure during $description; no further live checks.',
            );
          }
          await tester.pump(const Duration(milliseconds: 50));
        }
        expect(predicate(), isTrue, reason: description);
        expect(observed.protected, isFalse);
        expect(observed.failed, isFalse);
        expect(broker.diagnostics.failedRequests, 0);
        expect(tester.takeException(), isNull);
      }

      Future<void> mount(SharedMarketRepository market) => tester.pumpWidget(
        MaterialApp(
          home: ApplicationWorkspace(
            bundle: bundle,
            sharedMarket: market,
            fishMapWorkspace: const SizedBox.shrink(),
            enableBetaUpdates: false,
          ),
        ),
      );

      Future<void> openTab() async {
        await tester.tap(
          find.byKey(const ValueKey('top-workspace-tab-opportunities')),
        );
        await tester.pump();
        controller = tester
            .widget<OpportunitiesWorkspace>(find.byType(OpportunitiesWorkspace))
            .controller;
        await waitFor(() => !controller!.loading, 'controller ready');
      }

      Future<void> closeRecipe() async {
        await tester.tap(
          find
              .descendant(
                of: find.byType(Dialog),
                matching: find.byIcon(Icons.close),
              )
              .first,
        );
        await tester.pump(const Duration(milliseconds: 300));
      }

      try {
        final cold = Stopwatch()..start();
        await mount(broker);
        await openTab();
        if (inheritedProtectedPause) {
          expect(broker.pauseFor('eu'), isNotNull);
          await waitFor(() => !controller!.scanning, 'saved pause respected');
          expect(
            transport.requests,
            isEmpty,
            reason: 'A protected startup must not make automatic requests.',
          );
          phases['protectedStartup'] = {
            'httpRequestsBeforeUserRefresh': transport.requests.length,
            'retryAt': inheritedRetryAt,
            'manualRetryAuthorized': authorizeExpiredPauseRetry,
          };
        }
        if (pauseBefore != null && broker.pauseFor('eu') != null) {
          await waitFor(() => !controller!.scanning, 'saved pause respected');
          await tester.tap(find.byKey(const ValueKey('opportunities-refresh')));
          await tester.pump();
        }
        await waitFor(
          () => controller!.summaryComplete && !controller!.scanning,
          'all startup price and stock summaries',
        );
        phases['coldSummary'] = {
          'milliseconds': cold.elapsedMilliseconds,
          'items': controller!.summaryStatus.total,
          'loaded': controller!.summaryStatus.loaded,
          'httpRequests': transport.requests.length,
          'books': transport.bookCount,
        };
        expect(controller!.summaryStatus.total, greaterThan(1000));
        expect(transport.bookCount, 0);
        expect(
          controller!.market.items.values
              .where(
                (item) => item.quoteIsFresh(
                  DateTime.now().toUtc(),
                  const Duration(hours: 3),
                ),
              )
              .length,
          controller!.summaryStatus.total,
        );

        await tester.tap(
          find.descendant(
            of: find.byType(OpportunitiesWorkspace),
            matching: find.text('Alchemy'),
          ),
        );
        await tester.pump(const Duration(milliseconds: 250));
        await tester.tap(find.text('Filters').first);
        await tester.pump(const Duration(milliseconds: 250));
        if (controller!.preferences.profitableOnly) {
          await tester.tap(find.text('Profitable'));
          await tester.pump(const Duration(milliseconds: 100));
        }
        await closeRecipe();
        final search = find.descendant(
          of: find.byKey(const ValueKey('craft-search')),
          matching: find.byType(TextField),
        );
        await tester.enterText(search, 'Perfume of Deep Sea');
        expect(controller!.preferences.craftSearch, 'Perfume of Deep Sea');
        await waitFor(
          () => find
              .byKey(const ValueKey('craft-card:Perfume of Deep Sea'))
              .evaluate()
              .isNotEmpty,
          'real recipe appears',
        );
        final beforeDetails = transport.requests.length;
        final details = Stopwatch()..start();
        await tester.tap(
          find.byKey(const ValueKey('craft-card:Perfume of Deep Sea')),
        );
        await waitFor(
          () =>
              controller!.detailStatus.requested &&
              controller!.detailStatus.complete &&
              !controller!.scanning &&
              !controller!.calculating,
          'inspected recipe order details',
        );
        expect(
          find.byKey(const ValueKey('craft-result:Perfume of Deep Sea')),
          findsOneWidget,
        );
        expect(find.text('Sale after tax'), findsOneWidget);
        final quote = controller!.quotes.firstWhere(
          (quote) => quote.recipeName == 'Perfume of Deep Sea',
        );
        expect(quote.listingRevenue, isNotNull);
        expect(quote.calculationInputCost, isNotNull);
        phases['recipe'] = {
          'milliseconds': details.elapsedMilliseconds,
          'requests': transport.requests.length - beforeDetails,
          'detailItems': controller!.detailStatus.total,
          'saleAfterTax': quote.listingRevenue,
          'inputCost': quote.calculationInputCost,
          'checkedCost': quote.inputCost,
          'estimated': quote.hasEstimatedInputs,
        };

        final beforeNested = transport.requests.length;
        final nested = Stopwatch()..start();
        await tester.tap(
          find.byKey(const ValueKey('ingredient-recipe-Oil of the Abyss')),
        );
        await waitFor(
          () =>
              controller!.detailStatus.complete &&
              !controller!.scanning &&
              !controller!.calculating &&
              find
                  .byKey(const ValueKey('craft-result:Oil of the Abyss'))
                  .evaluate()
                  .isNotEmpty,
          'nested recipe calculations',
        );
        phases['nestedRecipe'] = {
          'milliseconds': nested.elapsedMilliseconds,
          'requests': transport.requests.length - beforeNested,
          'detailItems': controller!.detailStatus.total,
        };
        await tester.tap(find.byKey(const ValueKey('ingredient-recipe-back')));
        await waitFor(
          () =>
              find
                  .byKey(const ValueKey('craft-result:Perfume of Deep Sea'))
                  .evaluate()
                  .isNotEmpty &&
              !controller!.scanning,
          'back to parent recipe',
        );
        await closeRecipe();

        // A normal filtered Demand view requests its result outputs, not the
        // thousands of catalog ingredient books. No count is fabricated.
        await tester.enterText(search, 'Perfume');
        expect(controller!.preferences.craftSearch, 'Perfume');
        await waitFor(
          () => !controller!.calculating,
          'filtered perfume results',
        );
        final beforeDemand = transport.requests.length;
        final filteredDemand = Stopwatch()..start();
        await tester.tap(find.text('Demand').first);
        await waitFor(
          () =>
              controller!.detailStatus.requested &&
              controller!.detailStatus.complete &&
              !controller!.scanning,
          'filtered Demand output orders',
        );
        phases['demand'] = {
          'milliseconds': filteredDemand.elapsedMilliseconds,
          'requests': transport.requests.length - beforeDemand,
          'resultCount': controller!.visibleQuotes.length,
          'detailItems': controller!.detailStatus.total,
        };
        expect(controller!.detailStatus.total, lessThan(30));

        // Also exercise the user's ordinary unfiltered Alchemy/Profitables
        // Demand view. This is a single normal view load, not a rate sweep.
        await tester.tap(find.text('Filters').first);
        await tester.pump(const Duration(milliseconds: 250));
        if (!controller!.preferences.profitableOnly) {
          await tester.tap(find.text('Profitable'));
          await tester.pump(const Duration(milliseconds: 100));
        }
        await closeRecipe();
        final fullDemand = Stopwatch()..start();
        final beforeFullDemand = transport.requests.length;
        await tester.enterText(search, '');
        await tester.pump(const Duration(milliseconds: 300));
        await waitFor(
          () =>
              !controller!.calculating &&
              controller!.detailStatus.requested &&
              controller!.detailStatus.complete &&
              !controller!.scanning,
          'full profitable Alchemy Demand view',
        );
        phases['fullAlchemyDemand'] = {
          'milliseconds': fullDemand.elapsedMilliseconds,
          'requests': transport.requests.length - beforeFullDemand,
          'visibleResults': controller!.visibleQuotes.length,
          'detailItems': controller!.detailStatus.total,
        };

        // The original failure included the full, non-profit-filtered Alchemy
        // list. Exercise that same larger normal view, not a reduced scope.
        final allDemand = Stopwatch()..start();
        final beforeAllDemand = transport.requests.length;
        await tester.tap(find.text('Filters').first);
        await tester.pump(const Duration(milliseconds: 250));
        await tester.tap(find.text('Profitable'));
        await closeRecipe();
        expect(controller!.preferences.profitableOnly, isFalse);
        await waitFor(
          () =>
              !controller!.calculating &&
              controller!.detailStatus.complete &&
              !controller!.scanning,
          'all Alchemy Demand outputs',
        );
        phases['allAlchemyDemand'] = {
          'milliseconds': allDemand.elapsedMilliseconds,
          'requests': transport.requests.length - beforeAllDemand,
          'visibleResults': controller!.visibleQuotes.length,
          'detailItems': controller!.detailStatus.total,
          'loaded': controller!.detailStatus.loaded,
          'failed': controller!.detailStatus.failed,
        };

        // The strict mode measures a fully new current-view refresh, not a
        // cache replay. Age real receipts naturally: never rewrite timestamps,
        // reset operational ledgers or disable the production cache policy.
        if (requireFullFreshRefresh) {
          expect(controller!.summaryStatus.total, 1442);
          expect(controller!.detailStatus.total, 90);
          expect(controller!.preferences.profitableOnly, isFalse);
          expect(controller!.preferences.craftSearch, isEmpty);
          final quietStarted = DateTime.now().toUtc();
          final beforeQuiet = transport.requests.length;
          final quiet = Stopwatch()..start();
          while (quiet.elapsed < const Duration(seconds: 61)) {
            await tester.pump(const Duration(milliseconds: 200));
            expect(observed.failed, isFalse);
            expect(broker.diagnostics.failedRequests, 0);
            expect(transport.requests.length, beforeQuiet);
          }
          phases['freshRefreshPrecondition'] = {
            'startedAt': quietStarted.toIso8601String(),
            'milliseconds': quiet.elapsedMilliseconds,
            'httpRequests': transport.requests.length - beforeQuiet,
            'includedInRefreshTiming': false,
            'purpose':
                'Let real receipts and the rolling allowance age normally',
          };
        }

        await waitFor(
          () => controller!.refreshReadiness.canRefresh,
          'shared full-refresh allowance',
        );
        // Measure fresh work separately from a disabled immediate repeat.
        for (final phaseName
            in requireFullFreshRefresh
                ? const [
                    'fullFreshAlchemyRefresh',
                    'immediateRepeatAfterFullFresh',
                  ]
                : const ['manualFullRefresh', 'immediateRepeatRefresh']) {
          final beforeRefresh = transport.requests.length;
          if (phaseName.startsWith('immediateRepeat')) {
            final readiness = controller!.refreshReadiness;
            expect(readiness.canRefresh, isFalse);
            expect(readiness.wait, greaterThan(Duration.zero));
            final saved = {
              for (final entry in controller!.market.items.entries)
                entry.key: (
                  entry.value.quoteFetchedAt,
                  entry.value.bookFetchedAt,
                ),
            };
            await tester.pump(const Duration(milliseconds: 250));
            final button = tester.widget<OpportunityButton>(
              find.byKey(const ValueKey('opportunities-refresh')),
            );
            expect(button.onPressed, isNull);
            // Also verify callers cannot bypass the disabled toolbar.
            await controller!.refresh();
            await tester.pump(const Duration(seconds: 1));
            expect(transport.requests.length, beforeRefresh);
            expect(controller!.scanning, isFalse);
            for (final entry in saved.entries) {
              final item = controller!.market.items[entry.key]!;
              expect((item.quoteFetchedAt, item.bookFetchedAt), entry.value);
            }
            phases[phaseName] = {
              'disabledByCooldown': true,
              'remainingMilliseconds': readiness.wait.inMilliseconds,
              'httpRequests': 0,
              'preservedQuotes': controller!.summaryStatus.loaded,
              'preservedBooks': controller!.detailStatus.loaded,
            };
            continue;
          }
          final refreshBooks = controller!.detailStatus.total;
          final refreshBookIds = {
            for (final quote in controller!.visibleQuotes)
              if (controller!.outputMarketFor(quote.recipeName)
                  case final item?)
                item.itemId,
          };
          expect(refreshBookIds.length, refreshBooks);
          final booksBeforeRefresh = {
            for (final id in refreshBookIds) id: controller!.market.items[id],
          };
          final quotesBeforeRefresh = {
            for (final entry in controller!.market.items.entries)
              if (entry.value.quoteFetchedAt != null) entry.key: entry.value,
          };
          expect(quotesBeforeRefresh.length, controller!.summaryStatus.total);
          final freshAt = DateTime.now().toUtc();
          DateTime? depthFetchObservedAt;
          DateTime? quoteFetchObservedAt;
          void observeDepthRefresh() {
            if (quoteFetchObservedAt == null &&
                controller!.scanning &&
                controller!.progress.startsWith('Loading ') &&
                controller!.progressFraction == 0) {
              quoteFetchObservedAt = DateTime.now().toUtc();
            }
            if (depthFetchObservedAt == null &&
                controller!.scanning &&
                controller!.progress.startsWith('Loading market details') &&
                controller!.progressFraction == 0) {
              // This callback runs immediately before the broker checks ages.
              // It is an observation bound, not an invented server timestamp.
              depthFetchObservedAt = DateTime.now().toUtc();
            }
          }

          final manualRefresh = Stopwatch()..start();
          controller!.addListener(observeDepthRefresh);
          try {
            await tester.tap(
              find.byKey(const ValueKey('opportunities-refresh')),
            );
            await tester.pump();
            await waitFor(
              () =>
                  quoteFetchObservedAt != null &&
                  depthFetchObservedAt != null &&
                  controller!.summaryComplete &&
                  controller!.detailStatus.complete &&
                  !controller!.scanning &&
                  !controller!.calculating,
              '$phaseName of quotes and required Alchemy preorder books',
            );
          } finally {
            controller!.removeListener(observeDepthRefresh);
          }
          manualRefresh.stop();
          final refreshFinishedAt = DateTime.now().toUtc();
          final depthObservedAt = depthFetchObservedAt!;
          final quoteObservedAt = quoteFetchObservedAt!;
          final newQuotes = controller!.market.items.values
              .where(
                (item) =>
                    item.quoteFetchedAt != null &&
                    !item.quoteFetchedAt!.isBefore(freshAt),
              )
              .length;
          final quoteRequests = transport.requests
              .skip(beforeRefresh)
              .where((row) => row['part'] == 'summary')
              .toList();
          final quoteRequestsById = {
            for (final row in quoteRequests)
              for (final id in '${row['ids']}'.split(',')) id: row,
          };
          for (final row in quoteRequests) {
            final search = '${row['ids']}';
            expect(
              search.length,
              lessThanOrEqualTo(sharedMarketSearchCharacterLimit),
            );
            expect(
              search.split(',').length,
              lessThanOrEqualTo(broker.quoteBatchSize),
            );
          }
          expect(
            quoteRequests.fold<int>(
              0,
              (count, row) => count + '${row['ids']}'.split(',').length,
            ),
            quoteRequestsById.length,
            reason: 'A refresh must not download the same quote twice.',
          );
          expect(
            quoteRequestsById.keys.toSet().difference(
              quotesBeforeRefresh.keys.toSet(),
            ),
            isEmpty,
          );
          final quoteEvidence = <Map<String, Object?>>[];
          var reusedQuotes = 0;
          for (final entry in quotesBeforeRefresh.entries) {
            final before = entry.value;
            final beforeAt = before.quoteFetchedAt!;
            final after = controller!.market.items[entry.key]!;
            final afterAt = after.quoteFetchedAt!;
            final request = quoteRequestsById[entry.key];
            if (request == null) {
              reusedQuotes++;
              expect(
                before.quoteIsFresh(quoteObservedAt, broker.cacheMaxAge),
                isTrue,
              );
              expect(
                quoteObservedAt.difference(beforeAt) <
                    broker.minimumQuoteRefreshAge,
                isTrue,
              );
              expect(afterAt, beforeAt);
              expect(after.basePrice, before.basePrice);
              expect(after.stock, before.stock);
              expect(after.totalTrades, before.totalTrades);
              expect(after.lastSoldAt, before.lastSoldAt);
              expect(after.unlisted, before.unlisted);
            } else {
              final sentAt = DateTime.parse(request['startedAt']! as String);
              expect(
                !before.quoteIsFresh(sentAt, broker.cacheMaxAge) ||
                    sentAt.difference(beforeAt) >=
                        broker.minimumQuoteRefreshAge,
                isTrue,
                reason:
                    'Quote ${entry.key} was fetched inside its reuse interval.',
              );
              expect(afterAt.isBefore(sentAt), isFalse);
              expect(afterAt.isAfter(refreshFinishedAt), isFalse);
              expect(afterAt.isAfter(beforeAt), isTrue);
            }
            quoteEvidence.add({
              'itemId': entry.key,
              'beforeFetchedAt': beforeAt.toIso8601String(),
              'afterFetchedAt': afterAt.toIso8601String(),
              'observed': request == null ? 'reused' : 'fetched',
              'requestStartedAt': request?['startedAt'],
            });
          }
          expect(newQuotes, quoteRequestsById.length);
          expect(reusedQuotes + newQuotes, controller!.summaryStatus.total);
          final bookRequests = transport.requests
              .skip(beforeRefresh)
              .where((row) => row['part'] == 'orders')
              .toList();
          final requestedBookIds = {
            for (final row in bookRequests) '${row['ids']}',
          };
          expect(requestedBookIds.difference(refreshBookIds), isEmpty);
          expect(bookRequests.length, requestedBookIds.length);
          final bookEvidence = <Map<String, Object?>>[];
          var reusedBooks = 0;
          for (final id in refreshBookIds) {
            final before = booksBeforeRefresh[id];
            final beforeAt = before?.bookFetchedAt;
            final after = controller!.market.items[id];
            expect(after, isNotNull, reason: 'Missing refreshed book $id');
            expect(after!.asks, isNotNull, reason: 'Missing sellers for $id');
            expect(after.bids, isNotNull, reason: 'Missing buyers for $id');
            final afterAt = after.bookFetchedAt;
            expect(afterAt, isNotNull, reason: 'Missing book receipt time $id');
            final request = bookRequests
                .where((row) => '${row['ids']}' == id)
                .firstOrNull;
            final expectedReuseAtObservation =
                beforeAt != null &&
                before!.bookIsFresh(depthObservedAt, broker.cacheMaxAge) &&
                depthObservedAt.difference(beforeAt) <
                    broker.minimumBookRefreshAge;
            if (request == null) {
              reusedBooks++;
              expect(
                expectedReuseAtObservation,
                isTrue,
                reason: 'Missing or old book $id must not be reused',
              );
              expect(
                afterAt,
                beforeAt,
                reason: 'Reusing $id must retain its original receipt time',
              );
              expect(after.asks, orderedEquals(before!.asks!));
              expect(after.bids, orderedEquals(before.bids!));
            } else {
              final sentAt = DateTime.parse(request['startedAt']! as String);
              // A record can cross the strict age boundary between the observed
              // depth start and dispatch. Such a fetch is valid, not cache reuse.
              expect(
                beforeAt == null ||
                    !before!.bookIsFresh(sentAt, broker.cacheMaxAge) ||
                    sentAt.difference(beforeAt) >= broker.minimumBookRefreshAge,
                isTrue,
                reason: 'Book $id was fetched again inside its reuse interval',
              );
              expect(afterAt!.isBefore(sentAt), isFalse);
              expect(afterAt.isAfter(refreshFinishedAt), isFalse);
              if (beforeAt != null) {
                expect(afterAt.isAfter(beforeAt), isTrue);
              }
            }
            bookEvidence.add({
              'itemId': id,
              'beforeFetchedAt': beforeAt?.toIso8601String(),
              'afterFetchedAt': afterAt?.toIso8601String(),
              'ageAtRefreshClickMs': beforeAt == null
                  ? null
                  : freshAt.difference(beforeAt).inMilliseconds,
              'ageAtDepthObservationMs': beforeAt == null
                  ? null
                  : depthObservedAt.difference(beforeAt).inMilliseconds,
              'expectedAtDepthObservation': expectedReuseAtObservation
                  ? 'reuse'
                  : 'fetch',
              'observed': request == null ? 'reused' : 'fetched',
              'requestStartedAt': request?['startedAt'],
            });
          }
          final allBooksYoungThroughout = booksBeforeRefresh.values.every(
            (item) =>
                item != null &&
                item.bookIsFresh(refreshFinishedAt, broker.cacheMaxAge) &&
                refreshFinishedAt.difference(item.bookFetchedAt!) <
                    broker.minimumBookRefreshAge,
          );
          if (allBooksYoungThroughout) {
            expect(bookRequests, isEmpty);
            expect(reusedBooks, refreshBooks);
          }
          expect(reusedBooks + requestedBookIds.length, refreshBooks);
          expect(controller!.detailStatus.failed, 0);
          expect(controller!.failedItems, 0);
          if (phaseName == 'fullFreshAlchemyRefresh') {
            expect(reusedQuotes, 0, reason: 'Cached quotes do not count here.');
            expect(reusedBooks, 0, reason: 'Cached books do not count here.');
            expect(newQuotes, controller!.summaryStatus.total);
            expect(requestedBookIds, refreshBookIds);
            final longestId = quotesBeforeRefresh.keys.fold<int>(
              0,
              (length, id) => id.length > length ? id.length : length,
            );
            final characterCapacity =
                (sharedMarketSearchCharacterLimit + 1) ~/ (longestId + 1);
            final guaranteedBatchCapacity =
                characterCapacity < broker.quoteBatchSize
                ? characterCapacity
                : broker.quoteBatchSize;
            expect(
              quoteRequests.length,
              inInclusiveRange(
                (newQuotes / broker.quoteBatchSize).ceil(),
                (newQuotes / guaranteedBatchCapacity).ceil(),
              ),
              reason: 'Use full batches within both item and character bounds.',
            );
            expect(
              transport.requests.length - beforeRefresh,
              quoteRequests.length + requestedBookIds.length,
            );
          }
          if (phaseName == 'immediateRepeatAfterFullFresh') {
            expect(transport.requests.length, beforeRefresh);
            expect(newQuotes, 0);
            expect(requestedBookIds, isEmpty);
            expect(reusedQuotes, controller!.summaryStatus.total);
            expect(reusedBooks, refreshBooks);
          }
          phases[phaseName] = {
            'milliseconds': manualRefresh.elapsedMilliseconds,
            'httpRequests': transport.requests.length - beforeRefresh,
            'quoteBatchSizes': [
              for (final row in quoteRequests)
                '${row['ids']}'.split(',').length,
            ],
            'quoteSearchLengths': [
              for (final row in quoteRequests) '${row['ids']}'.length,
            ],
            'fetchedQuotes': newQuotes,
            'reusedQuotes': reusedQuotes,
            'requestedQuotes': controller!.summaryStatus.total,
            'fetchedBooks': requestedBookIds.length,
            'reusedBooks': reusedBooks,
            'requestedBooks': refreshBooks,
            'scope': 'All catalog quotes and all active Alchemy output books',
            'fullyFresh': reusedQuotes == 0 && reusedBooks == 0,
            'noRequestsInFlightMs': _networkIdleMilliseconds(
              transport.requests.skip(beforeRefresh),
              freshAt,
              refreshFinishedAt,
            ),
            'minimumBookRefreshAgeMs':
                broker.minimumBookRefreshAge.inMilliseconds,
            'minimumQuoteRefreshAgeMs':
                broker.minimumQuoteRefreshAge.inMilliseconds,
            'refreshClickedAt': freshAt.toIso8601String(),
            'quoteFetchObservedAt': quoteObservedAt.toIso8601String(),
            'depthFetchObservedAt': depthObservedAt.toIso8601String(),
            'finishedAt': refreshFinishedAt.toIso8601String(),
            'allBooksYoungThroughout': allBooksYoungThroughout,
            'books': bookEvidence,
            'quotes': quoteEvidence,
            'failed': controller!.failedItems,
          };
        }

        final beforeWarm = transport.requests.length;
        final warmTab = Stopwatch()..start();
        await tester.tap(
          find.byKey(const ValueKey('top-workspace-tab-planner')),
        );
        await tester.pump(const Duration(milliseconds: 250));
        await openTab();
        await waitFor(
          () => controller!.summaryComplete && !controller!.scanning,
          'warm tab revisit',
        );
        expect(transport.requests.length, beforeWarm);
        phases['warmTab'] = {
          'milliseconds': warmTab.elapsedMilliseconds,
          'httpRequests': transport.requests.length - beforeWarm,
        };

        await controller!.flush();
        await tester.pumpWidget(const SizedBox.shrink());
        controller = null;
        await broker.close();
        final warmTransport = _ObservedTransport();
        observed = warmTransport;
        final warmBroker = SharedMarketRepository.application(
          cacheStore: OpportunityMarketCacheStore(directory: marketDirectory),
          transport: warmTransport,
        );
        try {
          final warm = Stopwatch()..start();
          await mount(warmBroker);
          await openTab();
          await waitFor(
            () => controller!.summaryComplete && !controller!.scanning,
            'persisted cache restart',
          );
          expect(warmTransport.requests, isEmpty);
          phases['warmRestart'] = {
            'milliseconds': warm.elapsedMilliseconds,
            'httpRequests': warmTransport.requests.length,
            'items': controller!.summaryStatus.loaded,
          };
          await tester.pumpWidget(const SizedBox.shrink());
          controller = null;
        } finally {
          await warmBroker.close();
        }
        report['passed'] = true;
      } catch (error, stack) {
        report['error'] = '$error';
        report['stack'] = '$stack';
        rethrow;
      } finally {
        controller?.cancel();
        await tester.pumpWidget(const SizedBox.shrink());
        await broker.close();
        await bundle.controller.dispose();
        report['totalMilliseconds'] = total.elapsedMilliseconds;
        report['failedRequests'] = broker.diagnostics.failedRequests;
        report['peakConcurrentRequests'] =
            broker.diagnostics.peakActiveRequests;
        report['requestsWithServerSession'] =
            transport.requestsWithServerSession;
        final inheritedStarts = windowBefore == null
            ? <DateTime>[]
            : [
                for (final value
                    in ((jsonDecode(windowBefore) as Map)['starts'] as List))
                  DateTime.fromMillisecondsSinceEpoch(
                    value as int,
                    isUtc: true,
                  ),
              ];
        report['maximumStartsInRollingMinute'] = _maximumRollingMinute([
          ...inheritedStarts,
          for (final row in transport.requests)
            DateTime.parse(row['startedAt']! as String),
        ]);
        report['readOnlyProfileUnchanged'] =
            windowBefore ==
                (await sourceWindow.exists()
                    ? await sourceWindow.readAsString()
                    : null) &&
            pauseBefore ==
                (await sourcePause.exists()
                    ? await sourcePause.readAsString()
                    : null) &&
            cacheBefore ==
                (await sourceCache.exists()
                    ? await sourceCache.readAsString()
                    : null);
        if (report['readOnlyProfileUnchanged'] != true ||
            broker.diagnostics.failedRequests != 0 ||
            transport.failed ||
            transport.requestsWithServerSession <
                transport.requests.length ~/ 2 ||
            (broker.requestWindowLimit != null &&
                (report['maximumStartsInRollingMinute'] as int) >
                    broker.requestWindowLimit!)) {
          report['passed'] = false;
        }
        await reportFile.writeAsString(
          const JsonEncoder.withIndent('  ').convert(report),
        );
        binding.reportData = report;
        expect(report['passed'], isTrue);
        // Keep this isolated profile as audit evidence; do not delete live data.
      }
    },
    skip: !enabled,
    timeout: const Timeout(Duration(minutes: 6)),
  );
}

final class _ObservedTransport implements OpportunityMarketTransport {
  final _delegate = HttpOpportunityMarketTransport();
  final requests = <Map<String, Object?>>[];
  bool protected = false;
  bool failed = false;
  int get bookCount => requests.where((row) => row['part'] == 'orders').length;
  int get requestsWithServerSession => _delegate.requestsWithSessionCookies;

  @override
  Future<OpportunityHttpResponse> post(
    Uri uri, {
    required Map<String, String> headers,
    required String body,
    Future<void>? abortTrigger,
  }) async {
    if (failed) throw StateError('Live check stopped after a market failure.');
    if (requests.length >= 400) {
      failed = true;
      throw StateError(
        'Normal-workflow request ceiling exceeded; stop validation.',
      );
    }
    final payload = jsonDecode(body) as Map;
    final row = <String, Object?>{
      'startedAt': DateTime.now().toUtc().toIso8601String(),
      'part': uri.path.endsWith('GetBiddingInfoList') ? 'orders' : 'summary',
      'ids': payload['searchResult'] ?? payload['mainKey'],
    };
    requests.add(row);
    final timer = Stopwatch()..start();
    try {
      final response = await _delegate.post(
        uri,
        headers: headers,
        body: body,
        abortTrigger: abortTrigger,
      );
      final blocked = isProtectedMarketResponse(
        bytes: response.bytes,
        headers: response.headers,
      );
      protected = protected || blocked || response.statusCode == 429;
      failed =
          failed ||
          protected ||
          response.statusCode < 200 ||
          response.statusCode >= 300;
      row.addAll({
        'milliseconds': timer.elapsedMilliseconds,
        'httpStatus': response.statusCode,
        'bytes': response.bytes.length,
        'protected': blocked,
        'retryAfter': response.headers['retry-after'],
      });
      return response;
    } catch (error) {
      failed = true;
      row['milliseconds'] = timer.elapsedMilliseconds;
      row['error'] = '$error';
      rethrow;
    }
  }

  @override
  void close() => _delegate.close();
}

// Time without any in-flight HTTP request, including dispatch waiting and UI
// completion. Do not mislabel this entire value as measured provider latency.
int _networkIdleMilliseconds(
  Iterable<Map<String, Object?>> requests,
  DateTime startedAt,
  DateTime finishedAt,
) {
  final sorted = requests.toList()
    ..sort(
      (a, b) =>
          (a['startedAt']! as String).compareTo(b['startedAt']! as String),
    );
  var coveredUntil = startedAt;
  var idle = Duration.zero;
  for (final row in sorted) {
    final rawStart = DateTime.parse(row['startedAt']! as String);
    final rawEnd = rawStart.add(
      Duration(milliseconds: row['milliseconds']! as int),
    );
    if (rawEnd.isBefore(startedAt) || rawStart.isAfter(finishedAt)) continue;
    final start = rawStart.isBefore(startedAt) ? startedAt : rawStart;
    final end = rawEnd.isAfter(finishedAt) ? finishedAt : rawEnd;
    if (start.isAfter(coveredUntil)) idle += start.difference(coveredUntil);
    if (end.isAfter(coveredUntil)) coveredUntil = end;
  }
  if (finishedAt.isAfter(coveredUntil)) {
    idle += finishedAt.difference(coveredUntil);
  }
  return idle.inMilliseconds;
}

int _maximumRollingMinute(List<DateTime> starts) {
  starts.sort();
  var first = 0;
  var maximum = 0;
  for (var i = 0; i < starts.length; i++) {
    while (first < i &&
        starts[i].difference(starts[first]) >= const Duration(minutes: 1)) {
      first++;
    }
    final count = i - first + 1;
    if (count > maximum) maximum = count;
  }
  return maximum;
}
