import 'dart:io';

import 'package:bdo_craft_planner_flutter/app/app.dart';
import 'package:bdo_craft_planner_flutter/app/application_bootstrap.dart';
import 'package:bdo_craft_planner_flutter/data/persistence/planner_state_repository.dart';
import 'package:bdo_craft_planner_flutter/domain/market/market_cancellation.dart';
import 'package:bdo_craft_planner_flutter/domain/market/market_price_gateway.dart';
import 'package:bdo_craft_planner_flutter/domain/market/market_price_models.dart';
import 'package:bdo_craft_planner_flutter/domain/models/craft_mode.dart';
import 'package:bdo_craft_planner_flutter/features/planner/planner.dart';
import 'package:bdo_craft_planner_flutter/features/recipe_book/recipe_book.dart';
import 'package:bdo_craft_planner_flutter/features/shell/shell.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  testWidgets(
    'profile full-data Standard and Ledger critical workflows for ten cycles',
    (tester) async {
      final root = await Directory.systemTemp.createTemp(
        'bdo-profile-integration-',
      );
      final roaming = Directory(
        '${root.path}${Platform.pathSeparator}AppData'
        '${Platform.pathSeparator}Roaming',
      );
      final paths = PlannerStatePathPolicy.fromEnvironment(<String, String>{
        'APPDATA': roaming.path,
      });
      final startup = Stopwatch()..start();
      final bundle = await const ApplicationBootstrapService(
        applicationVersion: 'windows-profile-test',
      ).load(pathPolicy: paths);
      final bootstrapMilliseconds = startup.elapsedMilliseconds;
      final memorySamples = <int>[];
      final idleMemorySamples = <int>[];

      try {
        await tester.pumpWidget(
          BdoCraftPlannerApp(
            applicationFuture: Future<ApplicationBundle>.value(bundle),
            marketGateway: const _EmptyMarketGateway(),
          ),
        );
        await _waitFor(
          tester,
          find.byType(PlannerView),
          description: 'the first interactive Planner frame',
        );
        startup.stop();
        final startupToInteractiveMilliseconds = startup.elapsedMilliseconds;

        await _criticalCycle(tester, 0);
        await bundle.controller.flush();

        await binding.watchPerformance(() async {
          for (var iteration = 0; iteration < 5; iteration++) {
            await _criticalCycle(tester, iteration);
            memorySamples.add(ProcessInfo.currentRss);
          }
        }, reportKey: 'standard_critical_flow');
        _verifyPerformanceReport(
          binding.reportData!['standard_critical_flow'],
          flow: 'Standard',
        );

        await _openAppearance(tester);
        final themes = find.byKey(const ValueKey<String>('A01'));
        await tester.ensureVisible(themes);
        await tester.tap(themes);
        await _pumpFrames(tester, count: 3);
        final ledger = find.byKey(const ValueKey<String>('A02'));
        await tester.ensureVisible(ledger);
        await tester.tap(ledger);
        await _pumpFrames(tester, count: 6);
        expect(
          bundle.controller.active.state.value.appearance.background,
          'illuminated-ledger',
        );
        await tester.tap(find.byKey(ShellDestination.planner.actionKey));
        await _pumpFrames(tester);

        await _criticalCycle(tester, 5);

        await binding.watchPerformance(() async {
          for (var iteration = 5; iteration < 10; iteration++) {
            await _criticalCycle(tester, iteration);
            memorySamples.add(ProcessInfo.currentRss);
          }
        }, reportKey: 'ledger_critical_flow');
        _verifyPerformanceReport(
          binding.reportData!['ledger_critical_flow'],
          flow: 'Illuminated Ledger',
        );

        for (var sample = 0; sample < 6; sample++) {
          await _pumpFrames(tester, count: 5);
          idleMemorySamples.add(ProcessInfo.currentRss);
        }

        await bundle.controller.flush();
        final logicalSize =
            tester.view.physicalSize / tester.view.devicePixelRatio;
        binding.reportData ??= <String, dynamic>{};
        binding.reportData!['application_metrics'] = <String, dynamic>{
          'profile_mode': kProfileMode,
          'measurement_scope':
              'In-process bootstrap through interactive Flutter frames; '
              'Windows process and engine launch are measured separately.',
          'dataset_entries': bundle.catalog.totalItemCount,
          'bootstrap_milliseconds': bootstrapMilliseconds,
          'startup_to_interactive_milliseconds':
              startupToInteractiveMilliseconds,
          'logical_width': logicalSize.width,
          'logical_height': logicalSize.height,
          'device_pixel_ratio': tester.view.devicePixelRatio,
          'workflow_cycles': 10,
          'warmup_cycles': 2,
          'memory_samples_mebibytes': memorySamples
              .map((bytes) => bytes / 1024 / 1024)
              .toList(growable: false),
          'standard_memory_samples_mebibytes': memorySamples
              .take(5)
              .map((bytes) => bytes / 1024 / 1024)
              .toList(growable: false),
          'ledger_memory_samples_mebibytes': memorySamples
              .skip(5)
              .map((bytes) => bytes / 1024 / 1024)
              .toList(growable: false),
          'idle_memory_samples_mebibytes': idleMemorySamples
              .map((bytes) => bytes / 1024 / 1024)
              .toList(growable: false),
          'peak_memory_mebibytes':
              <int>[
                ...memorySamples,
                ...idleMemorySamples,
              ].reduce((left, right) => left > right ? left : right) /
              1024 /
              1024,
          'steady_memory_delta_mebibytes':
              (idleMemorySamples.last - idleMemorySamples.first) / 1024 / 1024,
          'steady_memory_range_mebibytes':
              (idleMemorySamples.reduce(
                    (left, right) => left > right ? left : right,
                  ) -
                  idleMemorySamples.reduce(
                    (left, right) => left < right ? left : right,
                  )) /
              1024 /
              1024,
          'frame_budget_milliseconds': 16.67,
          'allowed_budget_miss_fraction': 0.005,
        };
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await _pumpFrames(tester, count: 2);
        await bundle.controller.dispose();
        if (await root.exists()) await root.delete(recursive: true);
      }
    },
    timeout: const Timeout(Duration(minutes: 10)),
  );
}

void _verifyPerformanceReport(Object? raw, {required String flow}) {
  if (!kProfileMode) return;
  final report = (raw as Map).cast<String, dynamic>();
  const budget = 16.67;
  const allowedMissFraction = 0.005;
  final frames = report['frame_count'] as int;
  final allowedMisses = (frames * allowedMissFraction).ceil();
  final buildP99 = report['99th_percentile_frame_build_time_millis'] as num;
  final rasterP99 =
      report['99th_percentile_frame_rasterizer_time_millis'] as num;
  final buildWorst = report['worst_frame_build_time_millis'] as num;
  final rasterWorst = report['worst_frame_rasterizer_time_millis'] as num;
  final buildMisses = report['missed_frame_build_budget_count'] as int;
  final rasterMisses = report['missed_frame_rasterizer_budget_count'] as int;

  expect(buildP99, lessThanOrEqualTo(budget), reason: '$flow build p99');
  expect(rasterP99, lessThanOrEqualTo(budget), reason: '$flow raster p99');
  expect(
    buildWorst,
    lessThanOrEqualTo(budget * 3),
    reason: '$flow worst isolated build frame',
  );
  expect(
    rasterWorst,
    lessThanOrEqualTo(budget * 3),
    reason: '$flow worst isolated raster frame',
  );
  expect(
    buildMisses,
    lessThanOrEqualTo(allowedMisses),
    reason: '$flow build misses must not be recurrent',
  );
  expect(
    rasterMisses,
    lessThanOrEqualTo(allowedMisses),
    reason: '$flow raster misses must not be recurrent',
  );
}

Future<void> _criticalCycle(WidgetTester tester, int iteration) async {
  await tester.tap(find.byKey(ShellActionKeys.mode(CraftMode.processing)));
  await _pumpFrames(tester);
  await tester.tap(find.byKey(ShellDestination.planner.actionKey));
  await _pumpFrames(tester);

  await tester.tap(find.byKey(PlannerActionKeys.p03));
  await _waitFor(
    tester,
    find.byKey(RecipeBookKeys.modal),
    description: 'the Processing Recipe Book',
  );
  final cardScroll = find.byKey(RecipeBookKeys.r10CardScroll);
  expect(cardScroll, findsOneWidget);
  await tester.drag(cardScroll, const Offset(0, -420));
  await _pumpFrames(tester, count: 3);
  final recipeSearch = find.descendant(
    of: find.byKey(RecipeBookKeys.r03Search),
    matching: find.byType(EditableText),
  );
  await tester.enterText(recipeSearch, iteration.isEven ? 'powder' : 'grain');
  await _pumpFrames(tester, count: 4);
  await tester.tap(find.byKey(RecipeBookKeys.r02Close));
  await _waitUntilAbsent(tester, find.byKey(RecipeBookKeys.modal));

  await tester.tap(find.byKey(ShellDestination.inventory.actionKey));
  await _pumpFrames(tester);
  final inventorySearch = find.descendant(
    of: find.byKey(const ValueKey<String>('I01')),
    matching: find.byType(EditableText),
  );
  await tester.enterText(inventorySearch, iteration.isEven ? 'powder' : 'ore');
  await _pumpFrames(tester, count: 4);

  await tester.tap(find.byKey(ShellActionKeys.mode(CraftMode.alchemy)));
  await _pumpFrames(tester);
  await tester.tap(find.byKey(ShellDestination.planner.actionKey));
  await _pumpFrames(tester);
  final amount = find.descendant(
    of: find.byKey(PlannerActionKeys.p02),
    matching: find.byType(EditableText),
  );
  await tester.enterText(amount, iteration.isEven ? '2' : '3');
  await tester.testTextInput.receiveAction(TextInputAction.done);
  await _pumpFrames(tester, count: 4);
}

Future<void> _openAppearance(WidgetTester tester) async {
  await tester.tap(find.byKey(ShellActionKeys.mode(CraftMode.alchemy)));
  await _pumpFrames(tester);
  await tester.tap(find.byKey(ShellDestination.appearance.actionKey));
  await _pumpFrames(tester);
}

Future<void> _waitFor(
  WidgetTester tester,
  Finder finder, {
  required String description,
}) async {
  for (var attempt = 0; attempt < 120; attempt++) {
    if (finder.evaluate().isNotEmpty) return;
    await tester.pump(const Duration(milliseconds: 50));
  }
  expect(finder, findsWidgets, reason: 'Timed out waiting for $description.');
}

Future<void> _waitUntilAbsent(WidgetTester tester, Finder finder) async {
  for (var attempt = 0; attempt < 80; attempt++) {
    if (finder.evaluate().isEmpty) return;
    await tester.pump(const Duration(milliseconds: 50));
  }
  expect(finder, findsNothing);
}

Future<void> _pumpFrames(WidgetTester tester, {int count = 5}) async {
  for (var index = 0; index < count; index++) {
    await tester.pump(const Duration(milliseconds: 40));
  }
}

final class _EmptyMarketGateway implements MarketPriceGateway {
  const _EmptyMarketGateway();

  @override
  Future<MarketPriceFetchResult> fetch(
    Iterable<MarketPriceRequest> requests, {
    MarketCancellationToken? cancellationToken,
  }) async => MarketPriceFetchResult(
    region: 'eu',
    language: 'en-US',
    fetchedAt: DateTime.utc(2026, 7, 20, 12),
    items: const <MarketPriceRow>[],
    attemptedSources: const <MarketPriceSource>[],
  );
}
