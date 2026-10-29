import 'package:bdo_map_core/src/engine/map_camera.dart';
import 'package:bdo_map_core/src/model/map_geometry.dart';
import 'package:bdo_map_core/src/model/tile_source.dart';
import 'package:bdo_map_core/src/widgets/resource_map_zoom_dock.dart';
import 'package:bdo_map_core/src/widgets/resource_map_chrome_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('renders a continuous slider rail and preserves callbacks', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final camera = _camera();
    final zoomValues = <double>[];
    var fullWorlds = 0;

    await tester.pumpWidget(
      _testApp(
        child: ResourceMapZoomDock(
          key: const ValueKey<String>('resource-map-zoom-controls'),
          cameraController: camera,
          onZoomChanged: zoomValues.add,
          onShowFullWorld: () => fullWorlds += 1,
        ),
      ),
    );

    final surfaceFinder = find.byKey(
      const ValueKey<String>('resource-map-zoom-dock-surface'),
    );
    final surface = tester.widget<Material>(surfaceFinder);
    expect(surface.color, Colors.transparent);
    final face =
        tester
                .widget<Ink>(
                  find
                      .descendant(of: surfaceFinder, matching: find.byType(Ink))
                      .first,
                )
                .decoration!
            as BoxDecoration;
    expect(
      face.gradient!.colors.every((color) => (color.a - .9).abs() < .005),
      isTrue,
    );
    expect(face.gradient!.colors.first, isNot(face.gradient!.colors.last));
    expect(surface.elevation, 6);
    expect(surface.shadowColor, const Color(0x59000000));
    expect(
      (surface.shape! as RoundedRectangleBorder).borderRadius,
      BorderRadius.circular(12),
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey<String>('resource-map-zoom-controls')),
        matching: find.byType(Card),
      ),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey<String>('resource-map-zoom-divider')),
      findsOneWidget,
    );

    final slider = find.byKey(
      const ValueKey<String>('resource-map-zoom-slider'),
    );
    final fullWorld = find.byKey(
      const ValueKey<String>('resource-map-full-world'),
    );
    expect(slider, findsOneWidget);
    expect(
      tester.getRect(slider).height,
      greaterThan(tester.getRect(slider).width),
    );
    expect(tester.getSize(fullWorld), const Size(44, 44));

    expect(_findQuietAction('Show the full world'), findsOneWidget);
    expect(find.bySemanticsLabel('Map zoom level'), findsOneWidget);
    expect(find.bySemanticsLabel('Show full world'), findsOneWidget);

    tester.widget<Slider>(slider).onChanged!(5.25);
    await tester.tap(fullWorld);
    await tester.pumpAndSettle();
    expect(zoomValues, <double>[5.25]);
    expect(fullWorlds, 1);
    expect(tester.takeException(), isNull);
    await expectLater(
      surfaceFinder,
      matchesGoldenFile('goldens/resource_map_zoom_dock.png'),
    );
    semantics.dispose();
  });

  testWidgets('keeps compact hit targets at 200 percent text', (tester) async {
    await tester.pumpWidget(
      _testApp(
        textScaler: TextScaler.linear(2),
        child: ResourceMapZoomDock(
          cameraController: _camera(),
          onZoomChanged: (_) {},
          onShowFullWorld: () {},
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(
      tester
          .getSize(
            find.byKey(
              const ValueKey<String>('resource-map-zoom-dock-surface'),
            ),
          )
          .height,
      ResourceMapZoomDock.sliderExtent + ResourceMapZoomDock.controlExtent + 1,
    );
    expect(_findQuietAction('Show the full world'), findsOneWidget);
  });

  testWidgets('uses Illuminated Atlas semantic chrome roles', (tester) async {
    const chrome = ResourceMapChromeThemeData.illuminatedAtlas;
    await tester.pumpWidget(
      _testApp(
        chrome: chrome,
        child: ResourceMapZoomDock(
          cameraController: _camera(),
          onZoomChanged: (_) {},
          onShowFullWorld: () {},
        ),
      ),
    );

    final surfaceFinder = find.byKey(
      const ValueKey<String>('resource-map-zoom-dock-surface'),
    );
    final surface = tester.widget<Material>(surfaceFinder);
    final shape = surface.shape! as RoundedRectangleBorder;
    expect(surface.color, Colors.transparent);
    final face =
        tester
                .widget<Ink>(
                  find
                      .descendant(of: surfaceFinder, matching: find.byType(Ink))
                      .first,
                )
                .decoration!
            as BoxDecoration;
    expect(
      face.gradient!.colors.every((color) => (color.a - .9).abs() < .005),
      isTrue,
    );
    expect(surface.shadowColor, const Color(0x59000000));
    expect(shape.side.color, chrome.softOutline.withValues(alpha: .82));
    expect(shape.borderRadius, BorderRadius.circular(12));
    expect(
      find.descendant(
        of: surfaceFinder,
        matching: find.byType(LinearProgressIndicator),
      ),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });
}

Finder _findQuietAction(String message) => find.byWidgetPredicate(
  (widget) =>
      (widget is MapQuietIconButton && widget.tooltip == message) ||
      (widget is MapQuietTooltip && widget.message == message),
);

BdoMapCameraController _camera() => BdoMapCameraController(
  tileSource: BdoTileSource.workermanCommunity,
  initialCamera: const BdoMapCamera(center: BdoMapPoint(0, 0), zoom: 3),
);

Widget _testApp({
  required Widget child,
  TextScaler textScaler = TextScaler.noScaling,
  ResourceMapChromeThemeData chrome =
      ResourceMapChromeThemeData.sakuraCartographer,
}) {
  return MaterialApp(
    home: ResourceMapChromeTheme(
      data: chrome,
      child: MediaQuery(
        data: MediaQueryData(textScaler: textScaler),
        child: Scaffold(
          backgroundColor: const Color(0xFF0A1210),
          body: Center(child: child),
        ),
      ),
    ),
  );
}
