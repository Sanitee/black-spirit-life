import 'dart:io';
import 'dart:ui' as ui;

import 'package:bdo_map_core/bdo_map_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late BdoResourceMapDataset bundled;
  late List<int> tileBytes;
  late Directory cache;
  late MockClient client;

  setUpAll(() async {
    bundled = await BdoResourceMapLoader.loadBundled();
    final recorder = ui.PictureRecorder();
    Canvas(recorder).drawColor(const Color(0xFF182D38), BlendMode.src);
    final picture = recorder.endRecording();
    final image = await picture.toImage(16, 16);
    tileBytes = (await image.toByteData(
      format: ui.ImageByteFormat.png,
    ))!.buffer.asUint8List();
    image.dispose();
    picture.dispose();
  });

  setUp(() {
    cache = Directory.systemTemp.createTempSync('map_task_routes_');
    client = MockClient(
      (_) async => http.Response.bytes(
        tileBytes,
        HttpStatus.ok,
        headers: {'content-type': 'image/png'},
      ),
    );
  });

  tearDown(() async {
    client.close();
    for (var attempt = 0; attempt < 30 && cache.existsSync(); attempt++) {
      try {
        await cache.delete(recursive: true);
      } on FileSystemException {
        if (attempt == 29) rethrow;
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
    }
  });

  Future<void> open(
    WidgetTester tester, {
    required Size size,
    BdoResourceMapDataset? dataset,
    BdoNodeNetworkPreferences? preferences,
    ValueChanged<BdoNodeNetworkPreferences>? onPreferences,
    ValueChanged<Set<String>>? onFavorites,
  }) async {
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(size: size, disableAnimations: true),
          child: BdoResourceMap(
            dataset: dataset ?? bundled,
            cacheDirectory: cache,
            tileHttpClient: client,
            showSourceNotice: false,
            nodeNetworkPreferences: preferences,
            onNodeNetworkPreferencesChanged: onPreferences,
            onFavoriteResourceIdsChanged: onFavorites,
            tileSource: BdoTileSource(
              id: 'task-route-test',
              displayName: 'Local test fixture',
              urlTemplate: 'https://example.test/{z}/{x}_{y}.png',
              worldBounds: BdoTileSource.workermanCommunity.worldBounds,
              attribution: 'Local test fixture',
              usageNotice: 'Automated tests only.',
              fileExtension: 'png',
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> tap(WidgetTester tester, String key) async {
    final target = find.byKey(ValueKey(key));
    await tester.ensureVisible(target);
    await tester.tap(target);
    await tester.pump(const Duration(milliseconds: 250));
    final preview = find.byKey(
      const ValueKey('resource-map-node-target-preview-loading'),
    );
    for (
      var attempt = 0;
      attempt < 200 && preview.evaluate().isNotEmpty;
      attempt++
    ) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump();
    }
    expect(
      preview,
      findsNothing,
      reason: 'The background preview must finish.',
    );
    await tester.pumpAndSettle();
  }

  for (final width in [900.0, 1500.0]) {
    for (final income in [true, false]) {
      testWidgets(
        'direct ${income ? 'income' : 'materials'} task returns home at $width',
        (tester) async {
          final original = BdoNodeNetworkPreferences(
            contributionPointBudget: 333,
            desiredResourceNodeCounts: {'item:4001': 2},
            currentNodeIds: {'42'},
            currentOwnedHouseIds: {'fixture-owned-house'},
          );
          final savedChanges = <BdoNodeNetworkPreferences>[];
          await open(
            tester,
            size: Size(width, 850),
            preferences: original,
            onPreferences: savedChanges.add,
          );
          if (!income) {
            await tap(tester, 'resource-map-home-more-tools');
          }
          await tap(
            tester,
            income
                ? 'resource-map-home-worker-income'
                : 'resource-map-home-plan-materials',
          );
          expect(
            find.byKey(
              ValueKey(
                income
                    ? 'resource-map-market-value-page'
                    : 'resource-map-node-planner-targets',
              ),
            ),
            findsOneWidget,
          );
          expect(find.text('What should your workers collect?'), findsNothing);
          await tap(tester, 'resource-map-task-back');
          expect(
            find.byKey(const ValueKey('resource-map-home-find-material')),
            findsOneWidget,
          );
          expect(find.text('What should your workers collect?'), findsNothing);
          expect(
            find.byKey(const ValueKey('resource-map-node-planner-targets')),
            findsNothing,
          );
          expect(
            find.byKey(const ValueKey('resource-map-market-value-page')),
            findsNothing,
          );
          expect(savedChanges, isEmpty);
          expect(original.contributionPointBudget, 333);
          expect(original.desiredResourceNodeCounts, {'item:4001': 2});
          expect(original.currentNodeIds, {'42'});
          expect(original.currentOwnedHouseIds, {'fixture-owned-house'});
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  testWidgets('known browse row keeps its exact ID when names are identical', (
    tester,
  ) async {
    Set<String>? favorites;
    final data = _sameNameResources(bundled.manifest);
    final firstTextMatch = data
        .search('Shared Ore')
        .firstWhere((result) => result.kind == BdoSearchKind.resource);
    final selectedId = firstTextMatch.resourceId == 'ore-a' ? 'ore-b' : 'ore-a';
    await open(
      tester,
      size: const Size(1500, 850),
      dataset: data,
      onFavorites: (value) => favorites = value,
    );
    await tap(tester, 'resource-map-home-find-material');
    await tap(tester, 'resource-map-section-oresMinerals');
    await tap(tester, 'resource-map-browser-resource-$selectedId');
    expect(
      find.byKey(const ValueKey('resource-map-sidebar-details')),
      findsOneWidget,
    );
    await tap(tester, 'resource-map-detail-favorite-$selectedId');
    expect(favorites, {selectedId});
    expect(favorites, isNot(contains(firstTextMatch.resourceId)));
    await tap(tester, 'resource-map-task-back');
    expect(
      find.byKey(ValueKey('resource-map-browser-resource-$selectedId')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
}

BdoResourceMapDataset _sameNameResources(BdoDatasetManifest manifest) {
  final resources = [
    for (final id in ['ore-a', 'ore-b'])
      BdoResourceDefinition(
        id: id,
        name: 'Shared Ore',
        category: 'Ore',
        section: BdoResourceSection.oresMinerals,
        aliases: const [],
        acquisitionModes: const {BdoAcquisitionMode.fieldGathering},
      ),
  ];
  return BdoResourceMapDataset(
    manifest: manifest,
    resources: resources,
    workerNodes: const [],
    gatheringSpots: const [],
    gatheringRoutes: const [],
    gatheringPoints: [
      for (final resource in resources)
        BdoGatheringPoint(
          id: 'point-${resource.id}',
          location: BdoWorldPoint(resource.id == 'ore-a' ? -1000 : 1000, 1000),
          resourceIds: [resource.id],
          target: resource.name,
          kind: 'mining',
          label: resource.name,
          verification: BdoGatheringVerification.crossChecked,
          provenanceId: 'fixture',
        ),
    ],
  );
}
