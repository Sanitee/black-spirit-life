import 'dart:convert';
import 'dart:io';

import 'package:bdo_craft_planner_flutter/app/state/planner_application_controller.dart';
import 'package:bdo_craft_planner_flutter/data/catalog/bundled_data_service.dart';
import 'package:bdo_craft_planner_flutter/data/catalog/catalog_repository.dart';
import 'package:bdo_craft_planner_flutter/data/opportunities/opportunity_market_cache_store.dart';
import 'package:bdo_craft_planner_flutter/data/opportunities/opportunity_market_service.dart';
import 'package:bdo_craft_planner_flutter/domain/models/craft_mode.dart';
import 'package:bdo_craft_planner_flutter/domain/opportunities/opportunity_market_models.dart';
import 'package:bdo_craft_planner_flutter/domain/state/planner_state.dart';
import 'package:bdo_craft_planner_flutter/domain/state/state_copy.dart';
import 'package:bdo_craft_planner_flutter/features/opportunities/opportunities_controller.dart';
import 'package:bdo_craft_planner_flutter/features/opportunities/opportunities_workspace.dart';
import 'package:bdo_craft_planner_flutter/features/planner/planner_contracts.dart';
import 'package:bdo_craft_planner_flutter/features/planner/planner_view.dart';
import 'package:bdo_craft_planner_flutter/features/recipe_book/recipe_book_controller.dart';
import 'package:bdo_craft_planner_flutter/visual/visual.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

const _logicalSize = Size(1200, 752);
const _crystal = 'JIN Dawn Crystal - Accuracy';
final _now = DateTime.utc(2026, 9, 12, 11);

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
  testWidgets(
    'offline production catalog performance profile',
    (tester) async {
      expect(
        kProfileMode,
        isTrue,
        reason: 'Timing evidence must be native profile mode.',
      );
      final previousHttp = HttpOverrides.current;
      final networkGuard = _RejectHttp();
      HttpOverrides.global = networkGuard;
      final directory = await Directory.systemTemp.createTemp(
        'bsl-offline-profile-',
      );
      final catalog = await BundledDataService().load();
      var saves = 0;
      ModeState modeState(CraftMode mode, String target) => ModeState(
        target: target,
        want: 1000,
        bonusTarget: target,
        market: MarketState(),
        appearance: AppearanceSettings.sakuraDefaultsFor(mode),
        alchemyMastery: 1900,
        cookingMastery: 1900,
        processingMastery: 1900,
      );
      final app = PlannerApplicationController(
        catalog: catalog,
        initialState: PlannerState(
          applicationVersion: 'isolated-offline-profile',
          lastSuccessfulWriteUtc: _now,
          activeMode: CraftMode.cooking,
          alchemy: modeState(CraftMode.alchemy, 'Pure Powder Reagent'),
          cooking: modeState(CraftMode.cooking, 'Balenos Meal'),
          processing: modeState(CraftMode.processing, _crystal),
          processingYields: const {},
          marketTax: MarketTax(),
        ),
        saveState: (state) async {
          saves++;
          return state;
        },
      );
      final mode = app.modes[CraftMode.cooking]!;
      final operations = <String, Object?>{};
      OpportunitiesController? opportunities;
      RecipeBookController? book;
      try {
        expect(mode.plan.value.steps.length, greaterThan(3));
        final completedName = mode.plan.value.steps.first.name;
        mode.toggleCompleted(completedName);
        final expansionName = mode.plan.value.steps.last.name;
        final baselinePlan = jsonEncode(mode.plan.value.toJson());
        // Warm the actual algorithms, but exclude these iterations from evidence.
        for (var i = 0; i < 10; i++) {
          mode.toggleFavorite('Balenos Meal');
        }
        _measure(
          operations,
          'planner_favorite_updates',
          200,
          (i) => mode.toggleFavorite('Balenos Meal'),
        );
        expect(jsonEncode(mode.plan.value.toJson()), baselinePlan);
        _measure(operations, 'planner_timestamp_only_updates', 200, (i) {
          mode.updateState(
            (state) =>
                state.copyWith(market: state.market.copyWith(fetchedAt: i + 1)),
          );
        });
        expect(jsonEncode(mode.plan.value.toJson()), baselinePlan);
        _measure(
          operations,
          'planner_actual_quantity_edits_control',
          100,
          (i) => mode.commitAmount(i.isEven ? '1001' : '1000'),
        );
        expect(mode.plan.value.want, 1000);
        if (mode.state.value.completedSteps.isEmpty) {
          mode.toggleCompleted(completedName);
        }
        await app.flush();
        final actions = PlannerExternalActions(
          openRecipeBook: (_) {},
          copyName: (_) async {},
          checkPrices: (_) async => const PlannerMarketRefresh(
            prices: {},
            stock: {},
            unlistedItemNames: {},
            fetchedAt: 0,
            summary: 'Offline profile',
          ),
        );
        await tester.pumpWidget(
          _host(PlannerView(controller: mode, externalActions: actions)),
        );
        await _warmFrames(tester);
        for (var i = 0; i < 6; i++) {
          mode.toggleIngredients(expansionName);
          await tester.pump();
        }
        await binding.watchPerformance(() async {
          for (var i = 0; i < 100; i++) {
            mode.toggleIngredients(expansionName);
            await tester.pump(const Duration(milliseconds: 20));
          }
        }, reportKey: 'planner_completed_step_expansion_frames');
        await binding.watchPerformance(() async {
          for (var i = 0; i < 80; i++) {
            mode.toggleFavorite('Balenos Meal');
            await tester.pump(const Duration(milliseconds: 20));
          }
        }, reportKey: 'planner_favorite_frames');
        await tester.pumpWidget(const SizedBox.shrink());
        await app.flush();

        book = RecipeBookController(
          modeController: app.modes[CraftMode.processing]!,
          catalogRepository: CatalogRepository(catalog),
          callingContext: RecipeBookCallingContext.planner,
          allowedTargets: const [],
        );
        final names = app.modes[CraftMode.processing]!.recipes.keys.toList()
          ..sort();
        final uniqueNames = names.take(300).toList();
        var infoDigest = 0;
        _measure(
          operations,
          'item_info_first_unique_lookup',
          uniqueNames.length,
          (i) {
            final info = book!.itemInfoFor(
              uniqueNames[i],
              mode: CraftMode.processing,
            );
            infoDigest += info?.title.length ?? 0;
          },
        );
        _measure(operations, 'item_info_repeated_lookup', 1200, (i) {
          final info = book!.itemInfoFor(
            uniqueNames[i % uniqueNames.length],
            mode: CraftMode.processing,
          );
          infoDigest += info?.title.length ?? 0;
        });
        expect(infoDigest, greaterThan(0));
        operations['item_info_digest'] = infoDigest;
        book.dispose();
        book = null;

        final ids = <String>{
          ...(catalog.supportingData['marketIds']! as Map).values.map(
            (id) => '$id',
          ),
          for (final controller in app.modes.values)
            for (final recipe in controller.recipes.values)
              if (recipe.marketId != null) recipe.marketId!,
        };
        final cache = OpportunityMarketCacheStore(
          directory: directory,
          utcNow: () => _now,
        );
        await cache.save({
          'eu': {
            for (final id in ids)
              id: OpportunityMarketItem(
                itemId: id,
                basePrice: 1000,
                stock: 100000,
                quoteFetchedAt: _now,
                bookFetchedAt: _now,
                asks: const [
                  OpportunityMarketLevel(price: 1000, quantity: 100000),
                ],
                bids: const [
                  OpportunityMarketLevel(price: 1000, quantity: 100000),
                ],
              ),
          },
        });
        final transport = _RejectTransport();
        opportunities = OpportunitiesController(
          appController: app,
          catalog: CatalogRepository(catalog),
          directory: directory,
          clock: () => _now,
          serviceFactory: (region) => OpportunityMarketService(
            region: region,
            transport: transport,
            utcNow: () => _now,
          ),
        );
        await opportunities.ready;
        opportunities.change((p) {
          p.mode = CraftMode.processing;
          p.profitableOnly = false;
        });
        await opportunities.calculationSettled;
        expect(opportunities.visibleQuotes.length, greaterThan(100));
        operations['opportunity_row_count'] =
            opportunities.visibleQuotes.length;
        _measure(operations, 'opportunities_repeated_visible_sort', 400, (i) {
          infoDigest += opportunities!.visibleQuotes.length;
        });
        await tester.pumpWidget(
          _host(OpportunitiesWorkspace(controller: opportunities)),
        );
        await _warmFrames(tester);
        await binding.watchPerformance(() async {
          for (var i = 0; i < 100; i++) {
            // Same public fields/notifier used by production progress callbacks.
            // No fake-clock frame timings or transport delay is counted as CPU.
            opportunities!.progress = 'Loading market prices · ${i + 1} / 100';
            opportunities.progressFraction = (i + 1) / 100;
            opportunities.notifyListeners();
            await tester.pump(const Duration(milliseconds: 20));
          }
        }, reportKey: 'opportunities_progress_only_frames');
        final scrollable = find
            .descendant(
              of: find.byType(OpportunitiesWorkspace),
              matching: find.byType(Scrollable),
            )
            .first;
        await binding.watchPerformance(() async {
          for (var i = 0; i < 12; i++) {
            await tester.drag(scrollable, Offset(0, i < 6 ? -300 : 300));
            await tester.pump(const Duration(milliseconds: 40));
          }
        }, reportKey: 'opportunities_icon_list_scroll_frames');
        await tester.pumpWidget(const SizedBox.shrink());
        final calculateTimes = <int>[];
        for (var i = 0; i < 6; i++) {
          final watch = Stopwatch()..start();
          opportunities.change((p) => p.crafts = i.isEven ? 2 : 1);
          await opportunities.calculationSettled;
          calculateTimes.add(watch.elapsedMicroseconds);
        }
        operations['opportunities_full_calculation_wall_us'] = calculateTimes;
        operations['transport_requests'] = transport.requests;
        expect(transport.requests, 0);
        expect(networkGuard.attempts, 0);
        binding.reportData ??= {};
        binding.reportData!['offline_operations'] = operations;
        binding.reportData!['environment'] = {
          'profileMode': kProfileMode,
          'contentWidth': _logicalSize.width,
          'contentHeight': _logicalSize.height,
          'physicalWidth': tester.view.physicalSize.width,
          'physicalHeight': tester.view.physicalSize.height,
          'devicePixelRatio': tester.view.devicePixelRatio,
          'catalogRecipes': {
            for (final m in CraftMode.values)
              m.key: app.modes[m]!.recipes.length,
          },
          'inMemorySaves': saves,
          'currentRssBytes': ProcessInfo.currentRss,
          'httpClientAttempts': networkGuard.attempts,
          'syntheticDataOnly': true,
          'testOwnedTemporaryDirectory': directory.path,
        };
      } finally {
        book?.dispose();
        await tester.pumpWidget(const SizedBox.shrink());
        if (opportunities != null) {
          await opportunities.flush();
          opportunities.dispose();
        }
        await app.dispose();
        await directory.delete(recursive: true);
        HttpOverrides.global = previousHttp;
      }
    },
    timeout: const Timeout(Duration(minutes: 8)),
  );
}

void _measure(
  Map<String, Object?> report,
  String name,
  int count,
  void Function(int) operation,
) {
  final samples = <int>[];
  final watch = Stopwatch();
  for (var i = 0; i < count; i++) {
    watch
      ..reset()
      ..start();
    operation(i);
    watch.stop();
    samples.add(watch.elapsedMicroseconds);
  }
  report[name] = {
    'count': count,
    'samples_us': samples,
    'total_us': samples.fold<int>(0, (a, b) => a + b),
  };
}

Widget _host(Widget child) => MaterialApp(
  debugShowCheckedModeBanner: false,
  theme: SakuraNightGardenSpec.theme.materialTheme(),
  home: Scaffold(
    backgroundColor: Colors.black,
    body: Center(
      child: SizedBox.fromSize(
        size: _logicalSize,
        child: MediaQuery(
          data: const MediaQueryData(size: _logicalSize),
          child: ThemeSpecScope(
            spec: SakuraNightGardenSpec.theme,
            child: child,
          ),
        ),
      ),
    ),
  ),
);

Future<void> _warmFrames(WidgetTester tester) async {
  for (var i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

class _RejectHttp extends HttpOverrides {
  int attempts = 0;
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    final client = super.createHttpClient(context);
    client.findProxy = (_) => 'DIRECT';
    client.connectionFactory = (uri, proxyHost, proxyPort) {
      // watchPerformance itself opens the local Dart VM instrumentation
      // WebSocket. Permit only that loopback connection, never market HTTP.
      if (uri.host != '127.0.0.1' &&
          uri.host != '::1' &&
          uri.host != 'localhost') {
        attempts++;
        throw StateError('External HTTP is prohibited in the offline profile.');
      }
      return Socket.startConnect(
        uri.host == 'localhost' ? InternetAddress.loopbackIPv4 : uri.host,
        uri.port,
      );
    };
    return client;
  }
}

class _RejectTransport implements OpportunityMarketTransport {
  int requests = 0;
  @override
  Future<OpportunityHttpResponse> post(
    Uri uri, {
    required Map<String, String> headers,
    required String body,
    Future<void>? abortTrigger,
  }) async {
    requests++;
    throw StateError('Unexpected offline market request.');
  }

  @override
  void close() {}
}
