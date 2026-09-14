import 'dart:ui' as ui;

import 'package:bdo_map_core/src/widgets/house_use_icon.dart';
import 'package:bdo_map_core/src/widgets/resource_map_chrome_theme.dart';
import 'package:bdo_map_core/src/widgets/resource_map_menu_artwork.dart';
import 'package:bdo_map_core/src/widgets/worker_activity_style.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final kind in ResourceMapMenuArtworkKind.values) {
    testWidgets('${kind.name} keeps the menu icon bounded and decorative', (
      tester,
    ) async {
      await tester.pumpWidget(_iconApp(ResourceMapMenuArtwork(kind: kind)));
      await tester.pumpAndSettle();

      expect(
        tester.getSize(find.byType(ResourceMapMenuArtwork)),
        const Size.square(36),
      );
      final decoration = find.descendant(
        of: find.byType(ResourceMapMenuArtwork),
        matching: find.byType(ExcludeSemantics),
      );
      expect(decoration, findsOneWidget);
      expect(tester.widget<ExcludeSemantics>(decoration).excluding, isTrue);
      expect(tester.takeException(), isNull);
    });
  }

  for (final (kind, name) in [
    (ResourceMapMenuArtworkKind.materials, 'iron_ore'),
    (ResourceMapMenuArtworkKind.income, 'silver'),
    (ResourceMapMenuArtworkKind.houses, 'house'),
  ]) {
    testWidgets('${kind.name} uses original untinted game artwork', (
      tester,
    ) async {
      await tester.pumpWidget(_iconApp(ResourceMapMenuArtwork(kind: kind)));
      await tester.pumpAndSettle();
      final image = tester.widget<Image>(find.byType(Image));
      final source = image.image as AssetImage;
      expect(source.assetName, 'assets/images/menu_artwork/$name.webp');
      expect(source.package, 'bdo_map_core');
      expect(image.filterQuality, FilterQuality.high);
      expect(image.color, isNull);
      expect(image.fit, BoxFit.contain);
      expect(find.byType(HouseUseIcon), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  for (final kind in [
    ResourceMapMenuArtworkKind.findNodes,
    ResourceMapMenuArtworkKind.invest,
  ]) {
    testWidgets('${kind.name} normalizes original node artwork only in menus', (
      tester,
    ) async {
      await tester.pumpWidget(
        _iconApp(
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ResourceMapMenuArtwork(kind: kind),
              const BdoNodeTypeImage(
                key: ValueKey('unchanged-map-node-artwork'),
                sourceIconType: 0,
              ),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();

      final menu = find.byType(ResourceMapMenuArtwork);
      final node = tester.widget<BdoNodeTypeImage>(
        find.descendant(of: menu, matching: find.byType(BdoNodeTypeImage)),
      );
      expect(node.sourceIconType, 0);
      expect(node.size, 36);
      final image = tester.widget<Image>(
        find.descendant(of: menu, matching: find.byType(Image)),
      );
      final source = image.image as AssetImage;
      expect(source.assetName, 'assets/images/node_icons/0.png');
      expect(source.package, 'bdo_map_core');
      expect(image.excludeFromSemantics, isTrue);
      final normalization = tester.widget<Transform>(
        find.descendant(of: menu, matching: find.byType(Transform)),
      );
      expect(normalization.transform.entry(0, 0), 1.7);
      expect(normalization.transform.entry(1, 1), 1.7);
      expect(
        find.descendant(of: menu, matching: find.byType(ClipRect)),
        findsOneWidget,
      );
      expect(
        find.descendant(of: menu, matching: find.byType(CustomPaint)),
        kind == ResourceMapMenuArtworkKind.invest
            ? findsOneWidget
            : findsNothing,
      );

      final outsideMenu = find.byKey(
        const ValueKey('unchanged-map-node-artwork'),
      );
      expect(tester.getSize(outsideMenu), const Size.square(26));
      expect(
        find.ancestor(of: outsideMenu, matching: find.byType(Transform)),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
    });
  }

  final customKinds = ResourceMapMenuArtworkKind.values.where(
    (kind) =>
        kind != ResourceMapMenuArtworkKind.materials &&
        kind != ResourceMapMenuArtworkKind.income &&
        kind != ResourceMapMenuArtworkKind.houses &&
        kind != ResourceMapMenuArtworkKind.findNodes,
  );
  for (final kind in customKinds) {
    testWidgets('${kind.name} paints a transparent bounded native UI symbol', (
      tester,
    ) async {
      final pixels = await _paintSymbol(tester, kind);
      final alpha = [
        for (var offset = 3; offset < pixels.length; offset += 4)
          pixels[offset],
      ];
      expect(alpha.where((value) => value > 0).length, greaterThan(50));
      expect(alpha.where((value) => value == 0).length, greaterThan(324));
      for (var coordinate = 0; coordinate < 36; coordinate++) {
        expect(alpha[coordinate], 0, reason: 'Transparent top edge');
        expect(
          alpha[35 * 36 + coordinate],
          0,
          reason: 'Transparent bottom edge',
        );
        expect(alpha[coordinate * 36], 0, reason: 'Transparent left edge');
        expect(
          alpha[coordinate * 36 + 35],
          0,
          reason: 'Transparent right edge',
        );
      }
      if (kind != ResourceMapMenuArtworkKind.invest) {
        expect(find.byType(Image), findsNothing);
      }
      expect(find.byType(HouseUseIcon), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('Needed, Checklist and Saved have visibly distinct symbols', (
    tester,
  ) async {
    final plan = await _paintSymbol(tester, ResourceMapMenuArtworkKind.plan);
    final checklist = await _paintSymbol(
      tester,
      ResourceMapMenuArtworkKind.checklist,
    );
    final saved = await _paintSymbol(tester, ResourceMapMenuArtworkKind.saved);
    for (final pair in [(plan, checklist), (plan, saved), (checklist, saved)]) {
      var differentPixels = 0;
      for (var offset = 0; offset < pair.$1.length; offset += 4) {
        if (pair.$1[offset + 3] != pair.$2[offset + 3]) differentPixels++;
      }
      expect(
        differentPixels,
        greaterThan(150),
        reason:
            'Actions need different silhouettes, not just different colors.',
      );
    }
  });
}

Widget _iconApp(Widget child) => ResourceMapChromeTheme(
  data: ResourceMapChromeThemeData.glassDock,
  child: Directionality(
    textDirection: TextDirection.ltr,
    child: Center(child: child),
  ),
);

Future<Uint8List> _paintSymbol(
  WidgetTester tester,
  ResourceMapMenuArtworkKind kind,
) async {
  await tester.pumpWidget(_iconApp(ResourceMapMenuArtwork(kind: kind)));
  await tester.pumpAndSettle();
  final painter = tester.widget<CustomPaint>(find.byType(CustomPaint)).painter!;
  return (await tester.runAsync(() async {
    final recorder = ui.PictureRecorder();
    painter.paint(Canvas(recorder), const Size.square(36));
    final picture = recorder.endRecording();
    final image = await picture.toImage(36, 36);
    try {
      final data = (await image.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      ))!;
      return Uint8List.fromList(data.buffer.asUint8List());
    } finally {
      image.dispose();
      picture.dispose();
    }
  }))!;
}
