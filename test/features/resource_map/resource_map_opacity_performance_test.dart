import 'dart:convert';
import 'dart:io';

import 'package:bdo_craft_planner_flutter/data/catalog/catalog_repository.dart';
import 'package:bdo_craft_planner_flutter/features/resource_map/resource_map_theme_adapter.dart';
import 'package:bdo_craft_planner_flutter/features/resource_map/resource_map_workspace.dart';
import 'package:bdo_map_core/bdo_map_core.dart';
import 'package:bdo_map_core/src/widgets/map_canvas.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../../support/application_test_harness.dart';

void main() {
  testWidgets('live opacity keeps production map inputs and camera retained', (
    tester,
  ) async {
    configureApplicationTestSurface(tester, const Size(1500, 940));
    final original = (await tester.runAsync(ApplicationTestHarness.create))!;
    await tester.runAsync(original.disposeControllerOnly);
    final harness = original.rebindControllerInCurrentZone();
    final app = harness.bundle.controller;
    final mapController = BdoResourceMapController();
    app.active.selectTarget('Harmony Draught');
    app.active.commitAmount('100');
    final dataset = (await tester.runAsync(BdoResourceMapLoader.loadBundled))!;
    final economics = (await tester.runAsync(
      BdoWorkerEconomicsLoader.loadBundled,
    ))!;
    final lodging = (await tester.runAsync(LodgingDataLoader.loadBundled))!;
    var tileRequests = 0;
    final client = MockClient((_) async {
      tileRequests++;
      return http.Response('', 404);
    });
    await tester.pumpWidget(
      MaterialApp(
        home: ResourceMapThemeBinding(
          controller: app,
          child: ResourceMapWorkspace(
            fallbackApplicationDirectory: harness.temporaryDirectory,
            appController: app,
            controller: mapController,
            catalogRepository: CatalogRepository(harness.bundle.catalog),
            configuration: ResourceMapWorkspaceConfiguration(
              cacheDirectory: Directory(
                '${harness.temporaryDirectory.path}/tiles',
              ),
              tileHttpClient: client,
              showSourceNotice: false,
            ),
            datasetCache: ResourceMapDatasetCache(loader: () async => dataset),
            workerEconomicsCache: ResourceMapWorkerEconomicsCache(
              loader: () async => economics,
            ),
            lodgingCache: ResourceMapLodgingCache(loader: () async => lodging),
          ),
        ),
      ),
    );
    await _settleInitialTileRequests(tester, () => tileRequests);
    final sliderFinder = find.byKey(
      const ValueKey('resource-map-ui-opacity-slider'),
    );
    expect(sliderFinder, findsOneWidget);
    final mapBefore = tester.widget<BdoResourceMap>(
      find.byType(BdoResourceMap),
    );
    final canvasBefore = tester.widget<BdoMapCanvas>(find.byType(BdoMapCanvas));
    final camera = canvasBefore.cameraController;
    final tiles = canvasBefore.tileManager;
    final plan = app.active.plan.value;
    final document = app.documentSnapshot;
    final requestsBefore = tileRequests;
    final builds = <String, int>{};
    final frames = <int>[];
    debugOnRebuildDirtyWidget = (element, _) {
      final name = element.widget.runtimeType.toString();
      if (name == 'ResourceMapWorkspace' ||
          name == 'BdoResourceMap' ||
          name == 'BdoMapCanvas') {
        builds.update(name, (count) => count + 1, ifAbsent: () => 1);
      }
    };
    try {
      for (var i = 0; i < 40; i++) {
        final timer = Stopwatch()..start();
        final slider = tester.widget<Slider>(sliderFinder);
        slider.onChanged!((i + 1) / 50);
        await tester.pump(const Duration(milliseconds: 16));
        timer.stop();
        frames.add(timer.elapsedMicroseconds);
        expect(
          tester.widget<Slider>(sliderFinder).value,
          closeTo((i + 1) / 50, .00001),
        );
      }
    } finally {
      debugOnRebuildDirtyWidget = null;
    }
    final before = Platform.environment['RESOURCE_OPACITY_BASELINE'] == '1';
    if (!before) {
      expect(builds['ResourceMapWorkspace'] ?? 0, 0);
      expect(
        tester.widget<BdoResourceMap>(find.byType(BdoResourceMap)),
        same(mapBefore),
      );
      expect(app.documentSnapshot, same(document));
      expect(tileRequests, requestsBefore);
    }
    final canvas = tester.widget<BdoMapCanvas>(find.byType(BdoMapCanvas));
    expect(canvas.cameraController, same(camera));
    expect(canvas.tileManager, same(tiles));
    expect(app.active.plan.value, same(plan));
    tester.widget<Slider>(sliderFinder).onChangeEnd?.call(.8);
    await tester.pump();
    if (!before) {
      expect(
        (app.documentSnapshot.extensions['resourceMap'] as Map)['uiOpacity'],
        .8,
      );
      final slider = tester.widget<Slider>(sliderFinder);
      expect(slider.divisions, isNull);
      final theme = tester.widget<AnimatedTheme>(
        find
            .descendant(
              of: find.byType(BdoResourceMap),
              matching: find.byType(AnimatedTheme),
            )
            .first,
      );
      expect(theme.duration, Duration.zero);
    }
    final audit = Platform.environment['RESOURCE_OPACITY_AUDIT_DIR'];
    if (audit != null) {
      final sorted = [...frames]..sort();
      final report = {
        'baseline': before,
        'productionRecords': dataset.resources.length,
        'dragUpdates': frames.length,
        'builds': builds,
        'headlessPumpMedianUs': sorted[sorted.length ~/ 2],
        'headlessPumpP95Us': sorted[(sorted.length * .95).floor()],
        'headlessPumpTotalUs': frames.fold<int>(0, (a, b) => a + b),
        'tileRequestsDuringDrag': tileRequests - requestsBefore,
        'nativeTiming': false,
        'timingUsesReducedMotion': true,
      };
      await tester.runAsync(() async {
        final file = File('$audit/opacity-${before ? 'before' : 'after'}.json');
        await file.parent.create(recursive: true);
        await file.writeAsString(
          const JsonEncoder.withIndent('  ').convert(report),
        );
      });
    }
    if (!before) {
      // Exercise the real gesture path as well as repeatable frame samples.
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: false);
      await tester.pump();
      final committed = app.documentSnapshot;
      final rect = tester.getRect(sliderFinder);
      final gesture = await tester.startGesture(
        Offset(rect.left + rect.width * .7, rect.center.dy),
      );
      await tester.pump();
      await gesture.moveTo(
        Offset(rect.left + rect.width * .35, rect.center.dy),
      );
      await tester.pump(const Duration(milliseconds: 16));
      expect(app.documentSnapshot, same(committed));
      final live = app.resourceMapUiOpacity.value;
      expect(live, lessThan(.7));
      expect(
        tester
            .widget<AnimatedTheme>(
              find
                  .descendant(
                    of: find.byType(BdoResourceMap),
                    matching: find.byType(AnimatedTheme),
                  )
                  .first,
            )
            .duration,
        Duration.zero,
      );
      await gesture.up();
      await tester.pump();
      expect(
        (app.documentSnapshot.extensions['resourceMap'] as Map)['uiOpacity'],
        live,
      );
      tester
          .widget<FocusableActionDetector>(
            find.descendant(
              of: sliderFinder,
              matching: find.byType(FocusableActionDetector),
            ),
          )
          .focusNode!
          .requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
      expect(app.resourceMapUiOpacity.value, greaterThan(live));
      expect(
        (app.documentSnapshot.extensions['resourceMap'] as Map)['uiOpacity'],
        app.resourceMapUiOpacity.value,
      );
      final cancelled = await tester.startGesture(
        Offset(rect.left + rect.width * .5, rect.center.dy),
      );
      await cancelled.moveBy(const Offset(20, 0));
      await tester.pump();
      await cancelled.cancel();
      await tester.pump();
      expect(
        (app.documentSnapshot.extensions['resourceMap'] as Map)['uiOpacity'],
        app.resourceMapUiOpacity.value,
      );
      await tester.pump(const Duration(seconds: 2));
      expect(tester.binding.hasScheduledFrame, isFalse);
      mapController.focus(
        const BdoResourceMapFocusRequest(
          materialName: 'Ash Timber',
          source: BdoResourceMapFocusSource.workerNodes,
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(seconds: 4));
      BdoMapPainter painter() => tester
          .widgetList<CustomPaint>(find.byType(CustomPaint))
          .map((widget) => widget.painter)
          .whereType<BdoMapPainter>()
          .single;
      final layout = painter().overlayLayout;
      expect(painter().workerNodes, isNotEmpty);
      for (final value in [.1, .53, 1.0, 0.0, .6]) {
        tester.widget<Slider>(sliderFinder).onChanged!(value);
        await tester.pump(const Duration(milliseconds: 16));
        expect(
          painter().overlayLayout,
          same(layout),
          reason:
              'Presentation changes must retain geographic layout/hit testing.',
        );
      }
      tester.widget<Slider>(sliderFinder).onChangeEnd!(.6);
    }
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await app.dispose();
    mapController.dispose();
    client.close();
    await tester.runAsync(
      () => harness.temporaryDirectory.delete(recursive: true),
    );
  });
}

/// Real filesystem cache initialization is not advanced by fake-clock pumps.
/// Wait for the actual startup queue to drain, not an arbitrary frame count,
/// so requests first reaching the mock client cannot be attributed to dragging.
Future<void> _settleInitialTileRequests(
  WidgetTester tester,
  int Function() requestCount,
) async {
  final timeout = Stopwatch()..start();
  BdoTileManager? manager;
  bool drained(BdoTileManager value) =>
      value.visibleCoordinates.isNotEmpty &&
      requestCount() > 0 &&
      value.activeRequestCount == 0 &&
      value.queuedRequestCount == 0 &&
      // This fixture has an empty temporary cache and always returns HTTP404.
      // Every visible tile must have completed that initial request, not just
      // reached the pre-viewport idle state.
      value.failedVisibleTileCount == value.visibleCoordinates.length;
  Future<void> allowFilesystemWork() async {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
  }

  while (timeout.elapsed < const Duration(seconds: 20)) {
    await tester.pump(const Duration(milliseconds: 16));
    await allowFilesystemWork();
    final canvas = find.byType(BdoMapCanvas);
    if (canvas.evaluate().length != 1) continue;
    manager = tester.widget<BdoMapCanvas>(canvas).tileManager;
    if (!drained(manager)) continue;

    final requests = requestCount();
    final viewportBuilds = manager.debugViewportBuildCount;
    await tester.pumpAndSettle();
    await allowFilesystemWork();
    await tester.pump();
    if (identical(tester.widget<BdoMapCanvas>(canvas).tileManager, manager) &&
        drained(manager) &&
        requestCount() == requests &&
        manager.debugViewportBuildCount == viewportBuilds) {
      return;
    }
  }
  throw TestFailure(
    'Initial tile queue did not settle before opacity measurement: '
    '${requestCount()} requests, ${manager?.activeRequestCount} active, '
    '${manager?.queuedRequestCount} queued, '
    '${manager?.visibleCoordinates.length} visible, '
    '${manager?.failedVisibleTileCount} completed visible failures.',
  );
}
