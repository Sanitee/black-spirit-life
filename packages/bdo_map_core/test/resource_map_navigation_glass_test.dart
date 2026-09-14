import 'dart:io';
import 'dart:convert';
import 'dart:ui' as ui;

import 'package:bdo_map_core/bdo_map_core.dart';
import 'package:bdo_map_core/src/widgets/resource_map_atlas_shell.dart';
import 'package:bdo_map_core/src/widgets/map_canvas.dart';
import 'package:bdo_map_core/src/widgets/house_use_icon.dart';
import 'package:bdo_map_core/src/widgets/resource_map_pill.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

// Native Windows typography over a deliberately busy, generated basemap.
// All geographical markers and workflows use the complete bundled dataset.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late BdoResourceMapDataset dataset;
  late LodgingDataset lodging;
  late List<int> tilePng;
  late Directory cache;
  late MockClient client;
  late Map<String, dynamic> itemIcons;
  final decodedItemIcons = <String, Uint8List>{};

  setUpAll(() async {
    dataset = await BdoResourceMapLoader.loadBundled();
    lodging = await LodgingDataLoader.loadBundled();
    final catalog =
        jsonDecode(File('../../assets/data/app-data.json').readAsStringSync())
            as Map<String, dynamic>;
    itemIcons = <String, dynamic>{
      ...(catalog['processing'] as Map<String, dynamic>)['itemIcons']
          as Map<String, dynamic>,
      ...(catalog['cooking'] as Map<String, dynamic>)['itemIcons']
          as Map<String, dynamic>,
      ...catalog['itemIcons'] as Map<String, dynamic>,
    };
    if (Platform.isWindows) {
      final windows = Platform.environment['WINDIR'] ?? 'C:/Windows';
      final font = FontLoader('Segoe UI');
      for (final file in ['segoeui.ttf', 'seguisb.ttf', 'segoeuib.ttf']) {
        font.addFont(
          File('$windows/Fonts/$file').readAsBytes().then(ByteData.sublistView),
        );
      }
      await font.load();
      var sdk = File(Platform.resolvedExecutable).parent;
      while (!Directory(
        '${sdk.path}/bin/cache/artifacts/material_fonts',
      ).existsSync()) {
        if (sdk.parent.path == sdk.path) {
          throw StateError('Flutter font directory was not found.');
        }
        sdk = sdk.parent;
      }
      await (FontLoader('MaterialIcons')..addFont(
            File(
              '${sdk.path}/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
            ).readAsBytes().then(ByteData.sublistView),
          ))
          .load();
    }
    tilePng = await _busyTile();
  });
  setUp(() {
    cache = Directory.systemTemp.createTempSync('map_glass_navigation_');
    // The overview is a visual fixture, not a cache-write benchmark. Seed its
    // tiny generated tiles so Windows file locks cannot race the first frame.
    final directory = Directory('${cache.path}/map-glass-test')..createSync();
    final source = BdoTileSource.workermanCommunity;
    for (var zoom = 0; zoom <= 3; zoom++) {
      for (var x = -10; x <= 10; x++) {
        for (var y = -10; y <= 10; y++) {
          final tile = BdoTileCoordinate(zoom: zoom, x: x, y: y);
          if (source.contains(tile)) {
            File(
              '${directory.path}/${tile.cacheKey}.png',
            ).writeAsBytesSync(tilePng);
          }
        }
      }
    }
    client = MockClient(
      (_) async => http.Response.bytes(
        tilePng,
        200,
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

  Future<void> settleTerrain(WidgetTester tester) async {
    var stableFrames = 0;
    for (var i = 0; i < 250; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump(const Duration(milliseconds: 50));
      final manager = tester
          .widget<BdoMapCanvas>(find.byType(BdoMapCanvas))
          .tileManager;
      if (manager.activeRequestCount == 0 &&
          manager.queuedRequestCount == 0 &&
          manager.visibleCoordinates.isNotEmpty &&
          manager.visibleCoordinates.every(
            (tile) => manager.tile(tile) != null,
          )) {
        if (++stableFrames == 5) break;
      } else {
        stableFrames = 0;
      }
    }
    final manager = tester
        .widget<BdoMapCanvas>(find.byType(BdoMapCanvas))
        .tileManager;
    expect(
      stableFrames,
      5,
      reason:
          'Wait for all visible terrain to decode: '
          '${manager.decodedTileCount} decoded, ${manager.activeRequestCount} active, '
          '${manager.queuedRequestCount} queued, ${manager.failedVisibleTileCount} failed.',
    );
    await tester.pumpAndSettle();
  }

  Future<void> open(
    WidgetTester tester, {
    Size size = const Size(1500, 940),
    double scale = 1,
    ResourceMapInterfaceStyle style = ResourceMapInterfaceStyle.glassDock,
    ValueChanged<BdoNodeNetworkPreferences>? onPreferences,
    BdoNodeNetworkPreferences? preferences,
    double uiOpacity = 1,
    ValueChanged<double>? onUiOpacityChanged,
    BdoResourceMapController? controller,
    bool originalItemArtwork = false,
  }) async {
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 80)),
      );
    });
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(fontFamily: 'Segoe UI'),
        home: MediaQuery(
          data: MediaQueryData(
            size: size,
            textScaler: TextScaler.linear(scale),
            disableAnimations: true,
          ),
          child: ResourceMapChromeTheme(
            data:
                (style == ResourceMapInterfaceStyle.ghostLedger
                        ? ResourceMapChromeThemeData.ghostLedger
                        : ResourceMapChromeThemeData.glassDock)
                    .withUiOpacity(uiOpacity),
            child: RepaintBoundary(
              key: const ValueKey('map-glass-capture'),
              child: BdoResourceMap(
                dataset: dataset,
                controller: controller,
                lodgingDataset: lodging,
                cacheDirectory: cache,
                tileHttpClient: client,
                showSourceNotice: false,
                interfaceStyle: style,
                uiOpacity: uiOpacity,
                onUiOpacityChanged: onUiOpacityChanged,
                resourceIconBuilder: originalItemArtwork
                    ? (context, resource, size) {
                        final encoded = itemIcons[resource.name] as String?;
                        expect(
                          encoded,
                          isNotNull,
                          reason:
                              '${resource.name} has original catalog artwork',
                        );
                        final bytes = decodedItemIcons.putIfAbsent(
                          resource.name,
                          () => UriData.parse(encoded!).contentAsBytes(),
                        );
                        return Image.memory(
                          bytes,
                          width: size,
                          height: size,
                          key: ValueKey('original-item-art-${resource.id}'),
                          fit: BoxFit.contain,
                        );
                      }
                    : null,
                onNodeNetworkPreferencesChanged: onPreferences,
                nodeNetworkPreferences: preferences,
                tileSource: BdoTileSource(
                  id: 'map-glass-test',
                  displayName: 'Generated terrain fixture',
                  urlTemplate: 'https://example.test/{z}/{x}_{y}.png',
                  worldBounds: BdoTileSource.workermanCommunity.worldBounds,
                  attribution: 'Generated test fixture',
                  usageNotice: 'Automated visual QA only.',
                  fileExtension: 'png',
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await settleTerrain(tester);
  }

  Future<void> capture(WidgetTester tester, String name) async {
    await settleTerrain(tester);
    for (final element in find.byType(Image).evaluate().toList()) {
      await tester.runAsync(
        () => precacheImage((element.widget as Image).image, element),
      );
    }
    await tester.runAsync(
      () => precacheImage(
        const AssetImage(HouseUseIcon.asset, package: 'bdo_map_core'),
        tester.element(find.byType(BdoResourceMap)),
      ),
    );
    await tester.pumpAndSettle();
    final manager = tester
        .widget<BdoMapCanvas>(find.byType(BdoMapCanvas))
        .tileManager;
    expect(
      manager.decodedTileCount,
      greaterThan(0),
      reason: 'The terrain fixture must actually be decoded.',
    );
    expect(tester.takeException(), isNull);
    expect(find.byType(Scrollbar), findsNothing);
    expect(find.byType(RawScrollbar), findsNothing);
    final captureDirectory = Platform.environment['RESOURCE_MAP_CAPTURE_DIR'];
    if (captureDirectory != null) {
      await tester.runAsync(() async {
        final boundary = tester.renderObject<RenderRepaintBoundary>(
          find.byKey(const ValueKey('map-glass-capture')),
        );
        final image = await boundary.toImage();
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        image.dispose();
        final directory = Directory(captureDirectory)
          ..createSync(recursive: true);
        await File(
          '${directory.path}/$name.png',
        ).writeAsBytes(bytes!.buffer.asUint8List());
      });
    }
    await expectLater(
      find.byKey(const ValueKey('map-glass-capture')),
      matchesGoldenFile('goldens/$name.png'),
    );
  }

  Future<void> tap(WidgetTester tester, String key) async {
    final target = find.byKey(ValueKey(key));
    await tester.ensureVisible(target);
    await tester.tap(target);
    await tester.pumpAndSettle();
  }

  for (final opacity in [1.0, .6]) {
    testWidgets(
      'Materials and source entries are independent pills at opacity $opacity',
      (tester) async {
        await open(
          tester,
          size: const Size(1200, 752),
          style: ResourceMapInterfaceStyle.ghostLedger,
          uiOpacity: opacity,
          originalItemArtwork: true,
          onUiOpacityChanged: (_) {},
        );
        await tap(tester, 'resource-map-home-find-material');
        expect(
          tester
              .widget<ResourceMapJourneySurface>(
                find.byType(ResourceMapJourneySurface),
              )
              .framedBody,
          isFalse,
        );
        final categories = find.byKey(
          const ValueKey('resource-map-material-categories'),
        );
        expect(
          find.descendant(
            of: categories,
            matching: find.byType(ResourceMapPill),
          ),
          findsNWidgets(BdoResourceSection.values.length),
        );
        final suffix = opacity == 1 ? '100' : '60';
        await capture(
          tester,
          'resource_map_material_pills_1200_opacity_$suffix',
        );
        await tap(tester, 'resource-map-section-plantsWood');
        expect(
          tester
              .widget<ResourceMapJourneySurface>(
                find.byType(ResourceMapJourneySurface),
              )
              .framedBody,
          isFalse,
        );
        final name = find.text('Acacia Tree').first;
        expect(name, findsOneWidget);
        final text = tester.widget<Text>(name);
        expect(text.style!.fontSize, 16);
        expect(text.style!.fontWeight, FontWeight.w700);
        expect(
          find.ancestor(of: name, matching: find.byType(ResourceMapPill)),
          findsOneWidget,
        );
        await capture(tester, 'resource_map_source_pills_1200_opacity_$suffix');
        await tester.tap(name);
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('resource-map-sidebar-details')),
          findsOneWidget,
        );
        expect(
          tester
              .widget<ResourceMapJourneySurface>(
                find.byType(ResourceMapJourneySurface),
              )
              .framedBody,
          isTrue,
        );
        await capture(
          tester,
          'resource_map_source_detail_1200_opacity_$suffix',
        );
        expect(tester.takeException(), isNull);
      },
      skip: !Platform.isWindows,
    );
  }

  for (final scale in [1.0, 1.5]) {
    testWidgets(
      'compact home and complete 18-node review at ${scale}x',
      (tester) async {
        int available(BdoResourceDefinition resource) => dataset
            .workerNodesForResource(resource.id)
            .where((node) => node.isResourceNode)
            .length;
        final candidates =
            dataset.resources
                .where((resource) => available(resource) >= 18)
                .toList()
              ..sort(
                (left, right) => available(left).compareTo(available(right)),
              );
        final resource = candidates.first;
        BdoNodeNetworkPreferences? saved;
        await open(
          tester,
          size: const Size(1200, 752),
          scale: scale,
          preferences: BdoNodeNetworkPreferences(
            contributionPointBudget: 1000,
            desiredResourceNodeCounts: {resource.id: 18},
          ),
          onPreferences: (value) => saved = value,
          onUiOpacityChanged: (_) {},
        );
        final suffix = scale == 1 ? 'normal' : 'text150';
        expect(find.text('Opacity').hitTestable(), findsOneWidget);
        await capture(tester, 'resource_map_compact_home_1200_$suffix');
        await tap(tester, 'resource-map-home-more-tools');
        await tester.tap(
          find.byKey(const ValueKey('resource-map-home-plan-materials')),
        );
        await tester.pump();
        for (var attempt = 0; attempt < 2000; attempt++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 10)),
          );
          await tester.pump(const Duration(milliseconds: 20));
          if (find
              .byKey(const ValueKey('resource-map-node-target-preview-loading'))
              .evaluate()
              .isEmpty) {
            break;
          }
        }
        final build = find.byKey(
          const ValueKey('resource-map-build-node-network'),
        );
        await capture(tester, 'resource_map_targets_1200_$suffix');
        await tester.ensureVisible(build);
        await tester.tap(build);
        await tester.pump();
        for (var attempt = 0; attempt < 2000; attempt++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 10)),
          );
          await tester.pump();
          if (find
              .byKey(const ValueKey('resource-map-node-network-calculating'))
              .evaluate()
              .isEmpty) {
            break;
          }
        }
        expect(
          find.byKey(const ValueKey('resource-map-node-network-calculating')),
          findsNothing,
        );
        await tester.pumpAndSettle();
        expect(find.text('Review network'), findsOneWidget);
        expect(find.text('18 worker nodes'), findsNothing);
        expect(find.textContaining('Large plan:'), findsNothing);
        expect(find.text('Opacity').hitTestable(), findsOneWidget);
        expect(find.textContaining('every route line'), findsNothing);
        expect(find.text('The complete route is on the map'), findsNothing);
        expect(
          tester.getRect(find.byType(ResourceMapJourneySurface)).right,
          lessThanOrEqualTo(470),
        );
        await capture(tester, 'resource_map_review_18_nodes_1200_$suffix');
        final apply = find.byKey(
          const ValueKey('resource-map-save-current-node-network'),
        );
        await tester.ensureVisible(apply);
        await tester.tap(apply);
        await tester.pump();
        for (var attempt = 0; attempt < 2000; attempt++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 10)),
          );
          await tester.pump();
          if (find
              .byKey(const ValueKey('resource-map-node-network-calculating'))
              .evaluate()
              .isEmpty) {
            break;
          }
        }
        expect(
          find.byKey(const ValueKey('resource-map-node-network-calculating')),
          findsNothing,
        );
        expect(saved, isNotNull);
        expect(
          saved!.currentNodeIds
              .where(
                (id) => dataset.workerNodesById[id]?.isResourceNode == true,
              )
              .length,
          18,
        );
        expect(tester.takeException(), isNull);
      },
      skip: !Platform.isWindows,
    );
  }

  testWidgets('one search-first home leads directly into tasks', (
    tester,
  ) async {
    await open(tester);
    expect(find.byType(ResourceMapAtlasNavigator), findsNothing);
    expect(
      find.byKey(const ValueKey('resource-map-home-find-material')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('resource-map-invest-node-mode')),
      findsNothing,
    );
    await capture(tester, 'resource_map_task_home_1500');
    final home = tester.getRect(find.byType(ResourceMapJourneySurface));
    expect(home.width, 266);
    expect(home.height, lessThan(300));
    expect(
      find.byKey(const ValueKey('resource-map-unframed-home')),
      findsOneWidget,
    );
    await tap(tester, 'resource-map-home-find-material');
    expect(find.byType(ResourceMapJourneySurface), findsOneWidget);
    expect(
      find.byKey(const ValueKey('resource-map-material-categories')),
      findsOneWidget,
    );
    await capture(tester, 'resource_map_task_materials_1500');
    await tap(tester, 'resource-map-task-back');
    expect(
      find.byKey(const ValueKey('resource-map-home-find-material')),
      findsOneWidget,
    );
    await tap(tester, 'resource-map-home-more-tools');
    await tap(tester, 'resource-map-home-setup');
    expect(
      find.byKey(const ValueKey('resource-map-invest-node-mode')).hitTestable(),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('resource-map-node-mode-materials')),
      findsNothing,
    );
    await capture(tester, 'resource_map_task_setup_1500');
  }, skip: !Platform.isWindows);

  testWidgets(
    'minimized tasks restore and Houses has a predictable Back',
    (tester) async {
      await open(
        tester,
        size: const Size(1280, 820),
        onUiOpacityChanged: (_) {},
      );
      await tap(tester, 'resource-map-home-more-tools');
      await tap(tester, 'resource-map-home-browse-nodes');
      await tap(tester, 'resource-map-atlas-workspace-minimize');
      expect(
        find.byKey(const ValueKey('resource-map-atlas-task-chip')),
        findsOneWidget,
      );
      expect(
        find
            .byKey(const ValueKey('resource-map-ui-opacity-slider'))
            .hitTestable(),
        findsOneWidget,
      );
      await tap(tester, 'resource-map-atlas-task-restore');
      expect(
        find.byKey(const ValueKey('resource-map-worker-activity-picker')),
        findsOneWidget,
      );
      await tap(tester, 'resource-map-home-button');
      await tap(tester, 'resource-map-home-houses');
      expect(
        find.byKey(const ValueKey('resource-map-sidebar-housing-directory')),
        findsOneWidget,
      );
      await capture(tester, 'resource_map_task_houses_1280');
      final town = lodging.towns.firstWhere(
        (town) => town.name == 'Calpheon City',
      );
      await tap(tester, 'resource-map-housing-town-${town.townNodeId}');
      await tap(tester, 'resource-map-task-back');
      expect(
        find.byKey(const ValueKey('resource-map-sidebar-housing-directory')),
        findsOneWidget,
      );
      await tap(tester, 'resource-map-task-back');
      expect(
        find.byKey(const ValueKey('resource-map-home-find-material')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
    skip: !Platform.isWindows,
  );

  testWidgets(
    'the single task panel stays inside the map at enlarged text',
    (tester) async {
      for (final style in ResourceMapInterfaceStyle.values) {
        await open(tester, size: const Size(900, 820), scale: 2, style: style);
        final panel = tester.getRect(find.byType(ResourceMapJourneySurface));
        expect(panel.left, greaterThanOrEqualTo(0));
        expect(panel.right, lessThanOrEqualTo(820));
        expect(panel.bottom, lessThanOrEqualTo(820));
        await capture(tester, 'resource_map_task_${style.id}_home_900_200');
        await tap(tester, 'resource-map-home-find-material');
        await tap(tester, 'resource-map-section-meat');
        expect(find.byType(ResourceMapJourneySurface), findsOneWidget);
        expect(
          tester.getRect(find.byType(ResourceMapJourneySurface)).bottom,
          lessThanOrEqualTo(820),
        );
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        await tester.pumpAndSettle();
      }
    },
    skip: !Platform.isWindows,
  );

  testWidgets(
    'a result replaces the list; global search still finds towns',
    (tester) async {
      await open(tester, size: const Size(900, 820), scale: 2);
      final search = find.byKey(
        const ValueKey('resource-map-atlas-search-field'),
      );
      await tester.enterText(search, 'lizard');
      await tester.pumpAndSettle();
      final firstResult = find
          .byWidgetPredicate(
            (widget) =>
                widget.key is ValueKey<String> &&
                (widget.key! as ValueKey<String>).value.startsWith(
                  'resource-map-search-result-',
                ),
          )
          .first;
      await tester.tap(firstResult);
      await tester.pumpAndSettle();
      expect(find.byType(ResourceMapJourneySurface), findsOneWidget);
      expect(
        find.byKey(const ValueKey('resource-map-sidebar-details')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('resource-map-task-back')),
        findsOneWidget,
      );
      expect(
        tester.getRect(find.byType(ResourceMapJourneySurface)).bottom,
        lessThanOrEqualTo(820),
      );
      await capture(tester, 'resource_map_task_detail_900_200');
      await tester.enterText(search, 'Heidel');
      await tester.pumpAndSettle();
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget.key is ValueKey<String> &&
              (widget.key! as ValueKey<String>).value.startsWith(
                'resource-map-search-result-workerNode-',
              ),
        ),
        findsWidgets,
      );
      expect(tester.takeException(), isNull);
    },
    skip: !Platform.isWindows,
  );

  testWidgets(
    'opacity changes material fills and preserves the current task',
    (tester) async {
      double? changed;
      await open(tester, onUiOpacityChanged: (value) => changed = value);
      final slider = find.byKey(
        const ValueKey('resource-map-ui-opacity-slider'),
      );
      expect(slider, findsOneWidget);
      expect(slider.hitTestable(), findsOneWidget);
      expect(find.text('Opacity'), findsOneWidget);
      expect(tester.widget<Slider>(slider).min, 0);
      await tester.tapAt(
        tester.getRect(slider).centerLeft + const Offset(1, 0),
      );
      await tester.pumpAndSettle();
      expect(changed, 0);
      await open(
        tester,
        uiOpacity: .65,
        onUiOpacityChanged: (value) => changed = value,
      );
      expect(tester.widget<Slider>(slider).value, .65);
      await capture(tester, 'resource_map_compact_home_opacity_65');
      await tap(tester, 'resource-map-home-find-material');
      final task = find.byKey(
        const ValueKey('resource-map-material-categories'),
      );
      expect(task, findsOneWidget);
      expect(slider.hitTestable(), findsOneWidget);
      await open(
        tester,
        uiOpacity: .8,
        onUiOpacityChanged: (value) => changed = value,
      );
      expect(task, findsOneWidget);
      await tap(tester, 'resource-map-task-back');
      expect(
        find.byKey(const ValueKey('resource-map-unframed-home')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
    skip: !Platform.isWindows,
  );

  testWidgets(
    'Layers remains readable and scrollable at enlarged text',
    (tester) async {
      await open(
        tester,
        size: const Size(900, 700),
        scale: 2,
        onUiOpacityChanged: (_) {},
      );
      await tester.tap(
        find.byKey(const ValueKey('resource-map-layer-menu-toggle')),
      );
      await tester.pumpAndSettle();
      final menu = find.byKey(const ValueKey('resource-map-layer-menu'));
      final scrollable = find
          .ancestor(of: menu, matching: find.byType(SingleChildScrollView))
          .first;
      final bounds = tester.getRect(scrollable);
      expect(bounds.bottom, lessThanOrEqualTo(700));
      await tester.tap(
        find.byKey(const ValueKey('resource-map-layer-all-nodes')),
      );
      await tester.pumpAndSettle();
      final output = find.byKey(
        const ValueKey('resource-map-layer-worker-outputs'),
      );
      await tester.ensureVisible(output);
      await tester.pumpAndSettle();
      expect(output.hitTestable(), findsOneWidget);
      expect(tester.getRect(output).bottom, lessThanOrEqualTo(700));
      await capture(tester, 'resource_map_glass_layers_900_200');
    },
    skip: !Platform.isWindows,
  );

  testWidgets(
    'connection lines live in Layers and keep their existing preference effects',
    (tester) async {
      BdoNodeNetworkPreferences? latest;
      await open(
        tester,
        onPreferences: (value) => latest = value,
        preferences: BdoNodeNetworkPreferences(
          showAllMapNodes: false,
          showAllNodeConnections: false,
        ),
      );
      await tester.tap(
        find.byKey(const ValueKey('resource-map-layer-menu-toggle')),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('resource-map-layer-all-connections')),
      );
      await tester.pumpAndSettle();
      expect(latest?.showAllNodeConnections, isTrue);
      expect(latest?.showAllMapNodes, isTrue);
      await tester.tap(
        find.byKey(const ValueKey('resource-map-layer-all-connections')),
      );
      await tester.pumpAndSettle();
      expect(latest?.showAllNodeConnections, isFalse);
      expect(latest?.showAllMapNodes, isTrue);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'compact details leave the visible opacity control reachable',
    (tester) async {
      final controller = BdoResourceMapController();
      addTearDown(controller.dispose);
      await open(
        tester,
        size: const Size(600, 500),
        scale: 1.5,
        controller: controller,
        onUiOpacityChanged: (_) {},
      );
      final slider = find.byKey(
        const ValueKey('resource-map-ui-opacity-slider'),
      );
      expect(slider.hitTestable(), findsOneWidget);
      controller.focus(
        const BdoResourceMapFocusRequest(
          materialName: 'Snake Meat',
          source: BdoResourceMapFocusSource.manualGathering,
        ),
      );
      await tester.pumpAndSettle();
      expect(slider.hitTestable(), findsOneWidget);
      expect(
        tester
            .getRect(find.byKey(const ValueKey('resource-map-details-card')))
            .bottom,
        lessThanOrEqualTo(
          tester
              .getRect(
                find.byKey(const ValueKey('resource-map-ui-opacity-control')),
              )
              .top,
        ),
      );
      await capture(tester, 'resource_map_compact_detail_opacity_600_text150');
      expect(tester.takeException(), isNull);
    },
    skip: !Platform.isWindows,
  );
}

Future<List<int>> _busyTile() async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawRect(
    const Rect.fromLTWH(0, 0, 256, 256),
    Paint()..color = const Color(0xFF385051),
  );
  final land = Path()
    ..moveTo(0, 110)
    ..cubicTo(76, 70, 103, 164, 174, 77)
    ..cubicTo(211, 22, 251, 82, 256, 58)
    ..lineTo(256, 256)
    ..lineTo(0, 256)
    ..close();
  canvas.drawPath(land, Paint()..color = const Color(0xFF7E806A));
  for (var offset = -80.0; offset < 300; offset += 21) {
    canvas.drawPath(
      Path()
        ..moveTo(0, offset)
        ..cubicTo(62, offset + 65, 181, offset - 43, 256, offset + 33),
      Paint()
        ..color = const Color(0x55606B4F)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
  }
  canvas.drawPath(
    Path()
      ..moveTo(0, 213)
      ..cubicTo(71, 109, 164, 245, 256, 123),
    Paint()
      ..color = const Color(0xFFE2CA9A)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3,
  );
  for (final offset in [const Offset(54, 172), const Offset(162, 185)]) {
    canvas.drawCircle(offset, 5, Paint()..color = const Color(0xFFD2C69F));
    canvas.drawCircle(offset, 3, Paint()..color = const Color(0xFF43462E));
  }
  final picture = recorder.endRecording();
  final image = await picture.toImage(256, 256);
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  picture.dispose();
  return bytes!.buffer.asUint8List();
}
