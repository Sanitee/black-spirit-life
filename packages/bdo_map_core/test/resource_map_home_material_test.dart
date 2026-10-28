import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:bdo_map_core/src/widgets/resource_map_chrome_theme.dart';
import 'package:bdo_map_core/src/widgets/resource_map_discovery_home.dart';
import 'package:bdo_map_core/src/widgets/resource_map_field_desk.dart';
import 'package:bdo_map_core/src/widgets/resource_map_pill.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/map_menu_capture.dart';

const _capture = ValueKey('actual-resource-home-material');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadMapMenuCaptureFonts);

  testWidgets('real home normal and quiet artwork bays retain visible copper', (
    tester,
  ) async {
    await _open(tester, .7);
    final normal = _pill(tester, 'resource-map-home-find-material');
    final quiet = _pill(tester, 'resource-map-home-saved');
    final pixels = await _pixels(tester, [
      normal.topLeft + const Offset(21, 5),
      normal.topLeft + const Offset(100, 5),
      quiet.topLeft + const Offset(21, 5),
      quiet.topLeft + const Offset(100, 5),
    ]);
    final normalBay = pixels[0], normalFace = pixels[1];
    final quietBay = pixels[2], quietFace = pixels[3];
    for (final pair in [(normalBay, normalFace), (quietBay, quietFace)]) {
      expect(pair.$1.r, greaterThan(.25));
      expect(pair.$1.r - pair.$1.b, greaterThan(.065));
      expect(pair.$1.r - pair.$2.r, greaterThan(.08));
    }
    expect(
      (normalBay.r - quietBay.r).abs(),
      lessThan(.025),
      reason: 'Quiet actions keep quieter reading faces, not washed-out metal.',
    );
    expect(normal.height, quiet.height);
    expect(normal.height, 52); // Retained 50px child plus the existing 1px rim.
    for (final pill in tester.widgetList<ResourceMapPill>(
      find.byType(ResourceMapPill),
    )) {
      expect(pill.leadingWidth, 52);
      final pillFinder = find.byWidget(pill);
      final mount = find.descendant(
        of: pillFinder,
        matching: find.byType(ResourceMapArtworkMount),
      );
      expect(tester.getSize(mount), const Size(30, 30));
      expect(
        tester.getCenter(mount).dx - tester.getTopLeft(pillFinder).dx,
        26,
        reason: 'The retained artwork sits in the middle of its 52px bay.',
      );
      expect(tester.getCenter(mount).dy, tester.getCenter(pillFinder).dy);
    }
    expect(tester.getSize(find.byType(ResourceMapFieldDesk)).width, 200);
    expect(find.byType(BackdropFilter), findsNothing);
    expect(find.byType(Opacity), findsNothing);
    await captureMapMenu(
      tester,
      boundary: find.byKey(_capture),
      name: 'resource-home-copper-70',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'home opacity endpoints keep artwork, dimensions and copper roles',
    (tester) async {
      Rect? firstBounds;
      double? clearRed;
      for (final opacity in [0.0, .7, 1.0]) {
        await _open(tester, opacity);
        final bounds = _pill(tester, 'resource-map-home-find-material');
        firstBounds ??= bounds;
        expect(bounds, firstBounds);
        final colour = (await _pixels(tester, [
          bounds.topLeft + const Offset(21, 5),
        ])).single;
        if (opacity == 0) {
          clearRed = colour.r;
          expect(colour.r, lessThan(.12));
        } else {
          expect(colour.r, greaterThan(clearRed! + .12));
        }
        final mounts = tester
            .widgetList<CustomPaint>(find.byType(CustomPaint))
            .map((widget) => widget.foregroundPainter)
            .whereType<ResourceMapArtworkMountEdge>();
        expect(mounts.length, 5);
        for (final mount in mounts) {
          expect(mount.light, const Color(0xFFA66C69));
          expect(mount.accent, const Color(0xFFE8B0BF));
          expect(
            mount.opacity,
            closeTo(
              ResourceMapChromeThemeData.materialDensity(opacity),
              .000001,
            ),
          );
        }
        for (final artwork in tester.widgetList<Image>(find.byType(Image))) {
          expect(artwork.color, isNull);
          expect(artwork.opacity, isNull);
        }
        final label = tester.widget<Text>(find.text('Materials'));
        expect(label.style!.color, const Color(0xFFEEE5DC));
        expect(label.style!.color!.a, 1);
        expect(tester.takeException(), isNull);
      }
    },
  );

  testWidgets('home cards carry the raised edge above a quiet backplate', (
    tester,
  ) async {
    await _open(tester, .7);
    final bounds = _pill(tester, 'resource-map-home-find-material');
    final colours = await _pixels(tester, [
      bounds.topLeft + const Offset(100, 1),
      bounds.topLeft + const Offset(100, 6),
      // Compare the reading face's upper and side rims. The opposite side now
      // contains the intentionally brighter full-density copper artwork bay.
      bounds.topLeft + Offset(bounds.width - 2, bounds.height / 2),
      bounds.topLeft + Offset(100, bounds.height - 2),
      bounds.topLeft + Offset(100, bounds.height - 8),
    ]);
    expect(
      colours[0].computeLuminance(),
      greaterThan(colours[1].computeLuminance()),
    );
    expect(
      colours[0].computeLuminance(),
      greaterThan(colours[2].computeLuminance()),
    );
    expect(
      colours[3].computeLuminance(),
      lessThan(colours[4].computeLuminance()),
    );

    final rail = tester
        .widgetList<CustomPaint>(find.byType(CustomPaint))
        .map((widget) => widget.foregroundPainter)
        .whereType<ResourceMapInstrumentEdge>()
        .singleWhere((painter) => painter.quiet);
    expect(rail.radius, 8);
    expect(rail.opacity, _sakura().withUiOpacity(.7).materialOpacity);
    final backplate = tester
        .widgetList<Container>(
          find.descendant(
            of: find.byType(ResourceMapFieldDesk),
            matching: find.byType(Container),
          ),
        )
        .map((widget) => widget.decoration)
        .whereType<BoxDecoration>()
        .first;
    expect(
      (backplate.gradient! as LinearGradient).colors.map((colour) => colour.a),
      _sakura()
          .withUiOpacity(.7)
          .surfaceGradient
          .colors
          .map((colour) => colour.a),
      reason:
          'Quieter pigmentation must not change the saved opacity envelope.',
    );
    final mounts = find.byType(ResourceMapArtworkMount);
    for (final mount in mounts.evaluate()) {
      final finder = find.byWidget(mount.widget);
      final container = tester.widget<Container>(
        find.descendant(of: finder, matching: find.byType(Container)),
      );
      expect(tester.getSize(finder), const Size(30, 30));
      expect(container.alignment, Alignment.center);
      expect(
        (container.decoration! as BoxDecoration).borderRadius,
        BorderRadius.circular(4),
      );
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('rail shadow gutter stays vertically clipped while scrolling', (
    tester,
  ) async {
    const scrollKey = ValueKey('resource-map-field-desk-scroll');
    const searchKey = ValueKey('clip-search');
    const footerKey = ValueKey('clip-footer');
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ResourceMapChromeTheme(
            data: _sakura().withUiOpacity(.7),
            child: RepaintBoundary(
              key: _capture,
              child: Align(
                alignment: Alignment.topLeft,
                child: SizedBox(
                  width: 200,
                  height: 260,
                  child: ResourceMapFieldDesk(
                    onHome: () {},
                    search: const ColoredBox(
                      key: searchKey,
                      color: Color(0xFF15356D),
                      child: SizedBox(height: 30),
                    ),
                    controls: const ColoredBox(
                      key: footerKey,
                      color: Color(0xFF274E23),
                      child: SizedBox(height: 20),
                    ),
                    navigation: Column(
                      children: [
                        for (var i = 0; i < 20; i++)
                          ColoredBox(
                            color: i.isEven
                                ? const Color(0xFFE63627)
                                : const Color(0xFFEBB430),
                            child: const SizedBox(
                              height: 50,
                              width: double.infinity,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final clipFinder = find.byWidgetPredicate(
      (widget) =>
          widget is ClipRect && widget.clipper is ResourceMapRailShadowClipper,
    );
    final clip = tester.widget<ClipRect>(clipFinder);
    final size = tester.getSize(clipFinder);
    final bounds = tester.getRect(find.byKey(scrollKey));
    expect(tester.getSize(find.byKey(scrollKey)), size);
    expect(
      clip.clipper!.getClip(size),
      Rect.fromLTRB(-8, 0, size.width + 8, size.height),
    );
    expect(
      tester.widget<SingleChildScrollView>(find.byKey(scrollKey)).clipBehavior,
      Clip.none,
    );
    final points = [
      tester.getCenter(find.byKey(searchKey)),
      tester.getCenter(find.byKey(footerKey)),
      Offset(bounds.center.dx, bounds.top - 3),
      Offset(bounds.center.dx, bounds.bottom + 3),
    ];
    final protectedPixels = await _pixels(tester, points);
    expect(protectedPixels.take(2), const [
      Color(0xFF15356D),
      Color(0xFF274E23),
    ]);
    await tester.drag(find.byKey(scrollKey), const Offset(0, -180));
    await tester.pumpAndSettle();
    expect(
      tester.state<ScrollableState>(find.byType(Scrollable)).position.pixels,
      greaterThan(0),
    );
    expect(tester.getRect(find.byKey(scrollKey)), bounds);
    expect(
      await _pixels(tester, points),
      protectedPixels,
      reason:
          'Scrolled rows cannot paint over the search, heading or controls.',
    );
    expect(tester.takeException(), isNull);
  });
}

Future<void> _open(WidgetTester tester, double opacity) async {
  tester.view.physicalSize = const Size(420, 700);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        backgroundColor: const Color(0xFF141218),
        body: ResourceMapChromeTheme(
          data: _sakura().withUiOpacity(opacity),
          child: RepaintBoundary(
            key: _capture,
            child: ColoredBox(
              color: const Color(0xFF141218),
              child: Align(
                alignment: Alignment.topLeft,
                child: SizedBox(
                  width: 200,
                  child: ResourceMapFieldDesk(
                    search: const SizedBox(height: 30),
                    onHome: () {},
                    navigation: ResourceMapDiscoveryHome(
                      onFindMaterial: () {},
                      onWorkerIncome: () {},
                      onHouses: () {},
                      onSaved: () {},
                      onTodoList: () {},
                      onPlanMaterials: () {},
                      onBrowseWorkerNodes: () {},
                      onSetup: () {},
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  for (final element in find.byType(Image).evaluate()) {
    await tester.runAsync(
      () => precacheImage((element.widget as Image).image, element),
    );
  }
  await tester.pumpAndSettle();
}

Rect _pill(WidgetTester tester, String key) => tester.getRect(
  find.descendant(
    of: find.byKey(ValueKey(key)),
    matching: find.byType(ResourceMapPill),
  ),
);

Future<List<Color>> _pixels(WidgetTester tester, List<Offset> points) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(_capture),
  );
  final origin = tester.getTopLeft(find.byKey(_capture));
  return (await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 1);
    try {
      final data = (await image.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      ))!;
      return [
        for (final point in points) _pixel(data, image.width, point - origin),
      ];
    } finally {
      image.dispose();
    }
  }))!;
}

Color _pixel(ByteData data, int width, Offset point) {
  final offset = (point.dy.floor() * width + point.dx.floor()) * 4;
  return Color.fromARGB(
    data.getUint8(offset + 3),
    data.getUint8(offset),
    data.getUint8(offset + 1),
    data.getUint8(offset + 2),
  );
}

// These are the actual semantic roles from the shared Sakura Appearance.
ResourceMapChromeThemeData _sakura() {
  const base = ResourceMapChromeThemeData.fieldAtlas;
  return base.withPalette(
    canvas: const Color(0xFF141218),
    surface: const Color(0xFF211A20),
    raised: const Color(0xFF2B2028),
    inset: const Color(0xFF100E12),
    foreground: const Color(0xFFEEE5DC),
    secondaryForeground: const Color(0xFFB9A7A2),
    primary: const Color(0xFFCF7F98),
    primaryBright: const Color(0xFFE8B0BF),
    trim: const Color(0xFF6B3C48),
    trimBright: const Color(0xFFA66C69),
    positive: base.positive,
    warning: base.warning,
    error: base.error,
    shadow: Colors.black,
  );
}
