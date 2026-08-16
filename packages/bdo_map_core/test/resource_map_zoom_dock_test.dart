import 'package:bdo_map_core/src/widgets/resource_map_zoom_dock.dart';
import 'package:bdo_map_core/src/widgets/resource_map_desktop_shell.dart';
import 'package:bdo_map_core/src/widgets/resource_map_chrome_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('renders one connected atlas rail and preserves callbacks', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    var zoomIns = 0;
    var zoomOuts = 0;
    var fullWorlds = 0;

    await tester.pumpWidget(
      _testApp(
        child: ResourceMapZoomDock(
          key: const ValueKey<String>('resource-map-zoom-controls'),
          onZoomIn: () => zoomIns += 1,
          onZoomOut: () => zoomOuts += 1,
          onShowFullWorld: () => fullWorlds += 1,
        ),
      ),
    );

    final surfaceFinder = find.byKey(
      const ValueKey<String>('resource-map-zoom-dock-surface'),
    );
    final surface = tester.widget<Material>(surfaceFinder);
    expect(surface.color, ResourceMapAtlasColors.paperRaised);
    expect(surface.elevation, 2);
    expect(surface.shadowColor, const Color(0x330A1512));
    expect(
      (surface.shape! as RoundedRectangleBorder).borderRadius,
      BorderRadius.circular(10),
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
      findsNWidgets(2),
    );

    final actionFinders = <Finder>[
      find.byKey(const ValueKey<String>('resource-map-zoom-in')),
      find.byKey(const ValueKey<String>('resource-map-zoom-out')),
      find.byKey(const ValueKey<String>('resource-map-full-world')),
    ];
    final actionRects = actionFinders.map(tester.getRect).toList();
    for (final rect in actionRects) {
      expect(rect.width, ResourceMapZoomDock.controlExtent);
      expect(rect.height, ResourceMapZoomDock.controlExtent);
    }
    expect(actionRects[1].top, actionRects[0].bottom + 1);
    expect(actionRects[2].top, actionRects[1].bottom + 1);

    expect(find.byTooltip('Zoom in'), findsOneWidget);
    expect(find.byTooltip('Zoom out'), findsOneWidget);
    expect(find.byTooltip('Show the full world'), findsOneWidget);
    expect(find.bySemanticsLabel('Zoom in'), findsOneWidget);
    expect(find.bySemanticsLabel('Zoom out'), findsOneWidget);
    expect(find.bySemanticsLabel('Show full world'), findsOneWidget);

    await tester.tap(actionFinders[0]);
    await tester.tap(actionFinders[1]);
    await tester.tap(actionFinders[2]);
    await tester.pumpAndSettle();
    expect(zoomIns, 1);
    expect(zoomOuts, 1);
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
          onZoomIn: () {},
          onZoomOut: () {},
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
      ResourceMapZoomDock.controlExtent * 3 + 2,
    );
    expect(find.byTooltip('Show the full world'), findsOneWidget);
  });

  testWidgets('uses Illuminated Atlas semantic chrome roles', (tester) async {
    const chrome = ResourceMapChromeThemeData.illuminatedAtlas;
    await tester.pumpWidget(
      _testApp(
        chrome: chrome,
        child: ResourceMapZoomDock(
          onZoomIn: () {},
          onZoomOut: () {},
          onShowFullWorld: () {},
        ),
      ),
    );

    final surfaceFinder = find.byKey(
      const ValueKey<String>('resource-map-zoom-dock-surface'),
    );
    final surface = tester.widget<Material>(surfaceFinder);
    final shape = surface.shape! as RoundedRectangleBorder;
    expect(surface.color, chrome.paperRaised);
    expect(surface.shadowColor, chrome.idleShadow.color);
    expect(shape.side.color, chrome.divider);
    expect(shape.borderRadius, BorderRadius.circular(chrome.toolRadius));

    final decoration =
        tester
                .widget<DecoratedBox>(
                  find
                      .descendant(
                        of: surfaceFinder,
                        matching: find.byType(DecoratedBox),
                      )
                      .first,
                )
                .decoration
            as BoxDecoration;
    final gradient = decoration.gradient! as LinearGradient;
    expect(gradient.colors, <Color>[chrome.graphiteHighlight, chrome.graphite]);
    expect(tester.takeException(), isNull);
  });
}

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
