import 'dart:convert';
import 'dart:io';

import 'package:bdo_craft_planner_flutter/app/state/planner_application_controller.dart';
import 'package:bdo_craft_planner_flutter/data/catalog/bundled_data_service.dart';
import 'package:bdo_craft_planner_flutter/data/catalog/catalog_repository.dart';
import 'package:bdo_craft_planner_flutter/data/opportunities/opportunity_market_cache_store.dart';
import 'package:bdo_craft_planner_flutter/domain/models/craft_mode.dart';
import 'package:bdo_craft_planner_flutter/domain/state/planner_state_json_codec.dart';
import 'package:bdo_craft_planner_flutter/features/opportunities/opportunities_controller.dart';
import 'package:bdo_craft_planner_flutter/features/opportunities/opportunities_preferences.dart';
import 'package:bdo_craft_planner_flutter/features/opportunities/opportunities_workspace.dart';
import 'package:bdo_craft_planner_flutter/visual/visual.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

// Opt-in native benchmark. The profile/cache inputs are read-only; all writes
// go to test-owned temporary folders. It never fetches the live market.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
  const statePath = String.fromEnvironment('OPP_STATE');
  const cachePath = String.fromEnvironment('OPP_CACHE_DIRECTORY');
  const reportPath = String.fromEnvironment('OPP_REPORT');
  const repeats = int.fromEnvironment('OPP_BENCH_REPEATS', defaultValue: 5);

  testWidgets(
    'native Opportunities first frames and warm category switches',
    (tester) async {
      expect(
        kProfileMode,
        isTrue,
        reason: 'Use Windows profile mode for timings.',
      );
      expect(statePath, isNotEmpty);
      expect(cachePath, isNotEmpty);
      final previousHttp = HttpOverrides.current;
      final networkGuard = _RejectHttp();
      HttpOverrides.global = networkGuard;
      final setup = Stopwatch()..start();
      final catalog = await BundledDataService().load();
      final state = const PlannerStateJsonCodec().decode(
        await File(statePath).readAsString(),
      );
      final app = PlannerApplicationController(
        catalog: catalog,
        initialState: state,
        saveState: (value) async => value,
      );
      final market = await OpportunityMarketCacheStore(
        directory: Directory(cachePath),
      ).load();
      final receiptTimes = [
        for (final region in market.values)
          for (final item in region.values) ...[
            if (item.quoteFetchedAt != null) item.quoteFetchedAt!,
            if (item.bookFetchedAt != null) item.bookFetchedAt!,
          ],
      ];
      final receiptTime = receiptTimes.isEmpty
          ? DateTime.now().toUtc()
          : receiptTimes.reduce((a, b) => a.isAfter(b) ? a : b);
      final setupMs = setup.elapsedMilliseconds;
      final measurements = <Map<String, Object?>>[];
      try {
        for (var trial = 0; trial < repeats; trial++) {
          final directory = await Directory.systemTemp.createTemp(
            'bsl-opportunities-native-',
          );
          await OpportunityMarketCacheStore(directory: directory).save(market);
          await OpportunitiesPreferenceStore(directory).save(
            OpportunitiesPreferences()
              ..profitableOnly = false
              ..useInventory = true,
          );
          // Alternate fresh historical receipts and today's expired receipts.
          // Never pretend these cached prices have just been fetched.
          final now = trial.isEven ? receiptTime : DateTime.now().toUtc();
          final watch = Stopwatch()..start();
          final controller = OpportunitiesController(
            appController: app,
            catalog: CatalogRepository(catalog),
            directory: directory,
            clock: () => now,
            serviceFactory: (_) =>
                throw StateError('Live market access forbidden'),
          );
          void report(String phase) {
            final sample = <String, Object?>{
              'trial': trial,
              'phase': phase,
              'mode': controller.preferences.mode.key,
              'us': watch.elapsedMicroseconds,
              'rows': controller.quotes.length,
              'receipts': trial.isEven ? 'historical-fresh' : 'expired',
            };
            measurements.add(sample);
            debugPrint('NATIVE_OPP ${jsonEncode(sample)}');
            expect(
              watch.elapsedMilliseconds,
              lessThan(5000),
              reason: '$sample',
            );
            expect(controller.quotes, isNotEmpty);
            expect(find.byType(CircularProgressIndicator), findsNothing);
          }

          try {
            await controller.ready;
            controller.selectGlassFinish(trial.isEven ? 'bronze' : 'moon');
            await tester.pumpWidget(
              _host(OpportunitiesWorkspace(controller: controller)),
            );
            await controller.ready;
            await tester.pump();
            await binding.endOfFrame;
            report('cold_visible_frame');
            for (final mode in [CraftMode.alchemy, CraftMode.processing]) {
              watch.reset();
              await tester.tap(find.byKey(ValueKey('craft-mode-${mode.name}')));
              await controller.calculationSettled;
              await tester.pump();
              await binding.endOfFrame;
              report('first_category_visible_frame');
            }
            for (var round = 0; round < 5; round++) {
              for (final mode in CraftMode.values) {
                watch.reset();
                await tester.tap(
                  find.byKey(ValueKey('craft-mode-${mode.name}')),
                );
                // Inspect the first new frame, not a later settled replacement.
                await tester.pump();
                expect(controller.calculating, isFalse);
                expect(find.byType(CircularProgressIndicator), findsNothing);
                await binding.endOfFrame;
                report('warm_visible_frame');
              }
            }
            final stableQuotes = controller.quotes;
            for (final finish in ['moon', 'bronze', 'moon', 'bronze']) {
              watch.reset();
              await tester.tap(
                find.byKey(ValueKey('opportunities-finish-$finish')),
              );
              await tester.pump();
              await binding.endOfFrame;
              report('finish_visible_frame_$finish');
              expect(controller.calculating, isFalse);
              expect(identical(controller.quotes, stableQuotes), isTrue);
            }
            if (trial < 2) {
              controller.selectGlassFinish(trial == 0 ? 'bronze' : 'moon');
              await tester.pumpAndSettle();
              await binding.watchPerformance(() async {
                final list = find.byKey(
                  const PageStorageKey('craft-opportunities'),
                );
                for (var i = 0; i < 6; i++) {
                  await tester.timedDrag(
                    list,
                    Offset(0, i < 3 ? -350 : 350),
                    const Duration(milliseconds: 350),
                  );
                  await tester.pumpAndSettle();
                }
              }, reportKey: 'scroll_${controller.preferences.glassFinish}');
            }
            expect(tester.takeException(), isNull);
          } finally {
            await tester.pumpWidget(const SizedBox.shrink());
            await controller.flush();
            controller.dispose();
            await directory.delete(recursive: true);
          }
        }
        expect(networkGuard.attempts, 0);
        final report = <String, Object?>{
          'platform': Platform.operatingSystem,
          'build': 'profile',
          'catalogAndIsolatedProfileSetupMs': setupMs,
          'liveNetworkAttempts': networkGuard.attempts,
          'measurements': measurements,
          'frameTimings': Map<String, dynamic>.of(binding.reportData ?? {}),
        };
        binding.reportData = report;
        if (reportPath.isNotEmpty) {
          await File(
            reportPath,
          ).writeAsString(const JsonEncoder.withIndent('  ').convert(report));
        }
      } finally {
        await app.dispose();
        HttpOverrides.global = previousHttp;
      }
    },
    skip: statePath.isEmpty || cachePath.isEmpty,
    timeout: const Timeout(Duration(minutes: 6)),
  );
}

Widget _host(Widget child) => MaterialApp(
  debugShowCheckedModeBanner: false,
  theme: SakuraNightGardenSpec.theme.materialTheme(),
  home: Scaffold(
    body: ThemeSpecScope(spec: SakuraNightGardenSpec.theme, child: child),
  ),
);

class _RejectHttp extends HttpOverrides {
  int attempts = 0;
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    final client = super.createHttpClient(context);
    client.findProxy = (_) => 'DIRECT';
    client.connectionFactory = (uri, proxyHost, proxyPort) {
      if (!['127.0.0.1', '::1', 'localhost'].contains(uri.host)) {
        attempts++;
        throw StateError('No external HTTP in the navigation benchmark.');
      }
      return Socket.startConnect(
        uri.host == 'localhost' ? InternetAddress.loopbackIPv4 : uri.host,
        uri.port,
      );
    };
    return client;
  }
}
