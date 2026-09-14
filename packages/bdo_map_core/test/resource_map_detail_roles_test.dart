import 'dart:io';
import 'dart:ui' as ui;

import 'package:bdo_map_core/bdo_map_core.dart';
import 'package:bdo_map_core/src/widgets/map_canvas.dart';
import 'package:bdo_map_core/src/widgets/resource_map_panel_metrics.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'support/map_menu_capture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late BdoResourceMapDataset dataset;
  late Directory cache;
  late MockClient client;
  late BdoTileSource tiles;

  setUpAll(() async {
    dataset = await BdoResourceMapLoader.loadBundled();
    cache = await Directory.systemTemp.createTemp('map_detail_roles_');
    final recorder = ui.PictureRecorder();
    Canvas(recorder).drawColor(const Color(0xFF132329), BlendMode.src);
    final picture = recorder.endRecording();
    final image = await picture.toImage(32, 32);
    final bytes = (await image.toByteData(
      format: ui.ImageByteFormat.png,
    ))!.buffer.asUint8List();
    image.dispose();
    picture.dispose();
    client = MockClient((_) async => http.Response.bytes(bytes, 200));
    tiles = BdoTileSource(
      id: 'detail-role-fixture',
      displayName: 'Offline test',
      urlTemplate: 'https://example.test/{z}/{x}_{y}.png',
      worldBounds: BdoTileSource.workermanCommunity.worldBounds,
      attribution: 'Generated test fixture',
      usageNotice: 'Offline only',
      fileExtension: 'png',
    );
  });
  tearDownAll(() async {
    client.close();
    await cache.delete(recursive: true);
  });

  for (final scale in [1.0, 2.0]) {
    testWidgets(
      'compact source detail uses shared readable roles at $scale text',
      (tester) async {
        await tester.runAsync(loadMapMenuCaptureFonts);
        await tester.binding.setSurfaceSize(const Size(680, 752));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final controller = BdoResourceMapController()
          ..focus(
            const BdoResourceMapFocusRequest(
              materialName: 'Insectivore Plant Flower',
              resourceId: 'item:5440',
              source: BdoResourceMapFocusSource.manualGathering,
            ),
          );
        addTearDown(controller.dispose);
        await tester.pumpWidget(
          MaterialApp(
            builder: (context, child) => RepaintBoundary(
              key: const ValueKey('detail-role-capture'),
              child: MediaQuery(
                data: MediaQuery.of(context).copyWith(
                  textScaler: TextScaler.linear(scale),
                  disableAnimations: true,
                ),
                child: child!,
              ),
            ),
            home: BdoResourceMap(
              dataset: dataset,
              cacheDirectory: cache,
              tileSource: tiles,
              tileHttpClient: client,
              showSourceNotice: false,
              controller: controller,
            ),
          ),
        );
        await tester.pumpAndSettle();
        final details = find.byKey(const ValueKey('resource-map-details-card'));
        Finder text(String value) =>
            find.descendant(of: details, matching: find.text(value));
        final title = tester
            .widgetList<Text>(text('Poisonous Swamp Plant'))
            .singleWhere(
              (widget) =>
                  widget.style?.fontSize == ResourceMapPanelMetrics.heading,
            );
        expect(title.softWrap, isTrue);
        expect(title.maxLines, isNull);
        expect(
          tester.widget<Text>(text('What you get')).style?.fontSize,
          ResourceMapPanelMetrics.primary,
        );
        final product = text('Insectivore Plant Flower');
        expect(
          tester.widget<Text>(product).style?.fontSize,
          ResourceMapPanelMetrics.primary,
        );
        final source = dataset.fieldSources.singleWhere(
          (value) => value.name == 'Poisonous Swamp Plant',
        );
        final firstProduct = source.products.firstWhere(
          (value) => value.resourceId == 'item:5440',
        );
        final method = [
          firstProduct.method,
          firstProduct.tool,
        ].where((value) => value.trim().isNotEmpty).toSet().join(' · ');
        expect(text(method), findsNothing);
        expect(find.byTooltip(method), findsWidgets);
        final canvas = tester.widget<BdoMapCanvas>(find.byType(BdoMapCanvas));
        expect(canvas.gatheringPoints, isEmpty);
        await captureMapMenu(
          tester,
          boundary: find.byKey(const ValueKey('detail-role-capture')),
          name: 'field-source-detail-text${(scale * 100).round()}',
        );
        final otherResource =
            dataset.resourcesById[source.products[1].resourceId]!;
        final otherProduct = text(otherResource.name);
        await tester.ensureVisible(otherProduct);
        await tester.tap(otherProduct);
        await tester.pumpAndSettle();
        expect(
          find.byKey(
            ValueKey('resource-map-detail-favorite-${otherResource.id}'),
          ),
          findsOneWidget,
        );
        expect(text('Poisonous Swamp Plant'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
      },
    );
  }
}
