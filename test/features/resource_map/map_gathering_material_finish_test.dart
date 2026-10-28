import 'dart:ui' as ui;

import 'package:bdo_craft_planner_flutter/domain/models/craft_mode.dart';
import 'package:bdo_craft_planner_flutter/domain/state/planner_state.dart';
import 'package:bdo_craft_planner_flutter/features/gathering/gathering_workspace.dart';
import 'package:bdo_craft_planner_flutter/features/resource_map/resource_map_theme_adapter.dart';
import 'package:bdo_craft_planner_flutter/visual/foundations/application_theme.dart';
import 'package:bdo_craft_planner_flutter/visual/foundations/theme_spec.dart';
import 'package:bdo_craft_planner_flutter/visual/illuminated_ledger/ledger_spec.dart';
import 'package:bdo_craft_planner_flutter/visual/sakura_night_garden/sakura_spec.dart';
import 'package:bdo_gathering_companion/src/ui/field_desk_materials.dart';
import 'package:bdo_gathering_companion/src/ui/theme.dart';
import 'package:bdo_map_core/src/widgets/resource_map_atlas_shell.dart';
import 'package:bdo_map_core/src/widgets/resource_map_chrome_theme.dart';
import 'package:bdo_map_core/src/widgets/resource_map_pill.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _keys = ['atlas', 'map-pill', 'glass', 'desk', 'control'];
const _rimTypes = {
  'atlas': '_MapGlassLight',
  'map-pill': '_OptionEdge',
  'glass': '_GlassEdgePainter',
  'desk': '_DeskEdgePainter',
  'control': '_GlassEdgePainter',
};

void main() {
  for (final (name, spec) in [
    ('sakura', SakuraNightGardenSpec.theme),
    ('ledger', IlluminatedLedgerSpec.theme),
    (
      'greenhouse',
      applicationThemeForAppearance(
        AppearanceSettings.classicDefaultsFor(CraftMode.alchemy),
      ),
    ),
  ]) {
    for (final opacity in [0, 60, 100]) {
      testWidgets(
        '$name $opacity% faces and rims preserve content and bounds',
        (tester) async {
          tester.view.devicePixelRatio = 1;
          tester.view.physicalSize = const Size(1000, 500);
          addTearDown(tester.view.reset);
          var taps = 0;
          await tester.pumpWidget(_fixture(spec, opacity, onTap: () => taps++));
          await tester.pumpAndSettle();
          final retainedBounds = <String, Rect>{};
          final oldPainters = <CustomPainter>[];
          for (final key in _keys) {
            final panel = find.byKey(ValueKey(key));
            final bounds = tester.getRect(panel);
            retainedBounds[key] = bounds;
            expect(bounds.size, const Size(180, 90));
            final label = '$name/$opacity/$key';
            final face = _readingFace(tester, panel, label);
            final envelope = _opacityEnvelope(spec, opacity, key);
            _expectOpacityEnvelope(face.gradient, envelope, label);
            if (opacity == 100) {
              _expectReadingContrast(face.gradient, spec, label);
            }
            await tester.runAsync(
              () => _expectFaceAlpha(face.gradient, envelope, face.size, label),
            );
            final backgrounds = find.descendant(
              of: panel,
              matching: find.byWidgetPredicate(
                (widget) => widget is CustomPaint && widget.painter != null,
              ),
            );
            for (final background in backgrounds.evaluate()) {
              final widget = background.widget as CustomPaint;
              await tester.runAsync(
                () => _expectBottomLipOnly(
                  widget.painter!,
                  tester.getSize(
                    find.byElementPredicate((e) => e == background),
                  ),
                  label,
                ),
              );
            }
            final paint = find.descendant(
              of: panel,
              matching: find.byWidgetPredicate(
                (widget) =>
                    widget is CustomPaint &&
                    widget.foregroundPainter.runtimeType.toString() ==
                        _rimTypes[key],
              ),
            );
            expect(paint, findsOneWidget);
            final painter = tester
                .widget<CustomPaint>(paint)
                .foregroundPainter!;
            oldPainters.add(painter);
            expect(painter.hitTest(Offset.zero), isFalse);
            expect(painter.hitTest(const Offset(80, 40)), isFalse);
            expect(painter.shouldRepaint(painter), isFalse);
            await tester.runAsync(
              () => _expectEdgeOnly(
                painter,
                tester.getSize(paint),
                '$name/$opacity/$key',
              ),
            );
            await tester.tapAt(bounds.center);
            await tester.pumpAndSettle();
            expect(tester.getRect(panel), bounds);
            expect(tester.binding.transientCallbackCount, 0);
          }
          expect(taps, _keys.length);
          expect(find.byType(Opacity), findsNothing);
          expect(find.byType(ShaderMask), findsNothing);
          expect(find.byType(ColorFiltered), findsNothing);
          expect(find.byType(ImageFiltered), findsNothing);
          // Only the existing, clipped Gathering panel owns a backdrop blur.
          expect(find.byType(BackdropFilter), findsOneWidget);
          expect(
            find.descendant(
              of: find.byKey(const ValueKey('glass')),
              matching: find.byType(BackdropFilter),
            ),
            findsOneWidget,
          );
          // A material-opacity change must invalidate every rim, including the
          // new light-surface/raised variants, without replacing the child.
          final retained = find.text('Readout').evaluate().toList();
          await tester.pumpWidget(_fixture(spec, opacity == 100 ? 60 : 100));
          await tester.pumpAndSettle();
          for (var i = 0; i < _keys.length; i++) {
            expect(
              tester.getRect(find.byKey(ValueKey(_keys[i]))),
              retainedBounds[_keys[i]],
              reason:
                  '${_keys[i]} opacity must not change panel placement or size',
            );
            final paint = find.descendant(
              of: find.byKey(ValueKey(_keys[i])),
              matching: find.byWidgetPredicate(
                (widget) =>
                    widget is CustomPaint &&
                    widget.foregroundPainter.runtimeType.toString() ==
                        _rimTypes[_keys[i]],
              ),
            );
            final current = tester
                .widget<CustomPaint>(paint)
                .foregroundPainter!;
            expect(current.shouldRepaint(oldPainters[i]), isTrue);
            expect(
              find.text('Readout').evaluate().elementAt(i),
              same(retained[i]),
            );
          }
          expect(tester.binding.transientCallbackCount, 0);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
}

({LinearGradient gradient, Size size}) _readingFace(
  WidgetTester tester,
  Finder panel,
  String label,
) {
  BoxDecoration? decoration(Widget widget) => switch (widget) {
    DecoratedBox(:final decoration) =>
      decoration is BoxDecoration ? decoration : null,
    Ink(:final decoration) => decoration is BoxDecoration ? decoration : null,
    _ => null,
  };
  final faces = find.descendant(
    of: panel,
    matching: find.byWidgetPredicate(
      (widget) => decoration(widget)?.gradient != null,
    ),
  );
  expect(faces, findsOneWidget, reason: '$label has one reading fill plane');
  final decorated = find.descendant(
    of: panel,
    matching: find.byWidgetPredicate((widget) => decoration(widget) != null),
  );
  for (final element in decorated.evaluate()) {
    final box = decoration(element.widget)!;
    expect(
      box.color?.a ?? 0,
      0,
      reason: '$label must not stack a solid coat below its translucent face',
    );
    expect(box.image, isNull, reason: '$label has no repeating texture');
  }
  for (final material in tester.widgetList<Material>(
    find.descendant(of: panel, matching: find.byType(Material)),
  )) {
    if (material.type != MaterialType.transparency) {
      expect(
        material.color?.a,
        0,
        reason: '$label retains transparent Material beneath its single face',
      );
    }
  }
  expect(
    find.descendant(of: panel, matching: find.byType(ColoredBox)),
    findsNothing,
    reason: '$label must not add a second fill behind the material',
  );
  final face = decoration(tester.widget(faces))!;
  expect(face.color?.a ?? 0, 0, reason: '$label has no stacked color coat');
  expect(face.image, isNull, reason: '$label has no texture image');
  expect(face.gradient, isA<LinearGradient>());
  return (
    gradient: face.gradient! as LinearGradient,
    size: tester.getSize(faces),
  );
}

/// The corrected hosted finish uses one denser satin plane, not stacked coats.
/// Lock its explicitly approved, floor-normalized quadratic density and the
/// vertical reading-face direction independently of the material implementation.
LinearGradient _opacityEnvelope(ThemeSpec spec, int opacity, String key) {
  final material = (opacity / 100).clamp(.02, 1.0);
  double density(double alpha) {
    final unit = ((alpha - .02) / .98).clamp(0.0, 1.0);
    return .02 + .98 * (1 - (1 - unit) * (1 - unit));
  }

  final surface = density(material);
  final soft = density((material * .82 / .76).clamp(.02, 1.0));
  final control = density((material * .86 / .76).clamp(.02, 1.0));
  LinearGradient envelope(
    List<double> alpha, {
    List<double>? stops,
    Alignment begin = Alignment.topCenter,
    Alignment end = Alignment.bottomCenter,
  }) => LinearGradient(
    begin: begin,
    end: end,
    stops: stops,
    colors: [for (final value in alpha) Colors.black.withValues(alpha: value)],
  );
  return switch (key) {
    'atlas' => resourceMapChromeThemeForPlannerTheme(
      spec,
    ).withUiOpacity(opacity / 100).readingSurfaceGradient,
    'map-pill' => envelope(
      [surface * .96, surface * .96, surface * .98, surface * .98],
      stops: const [0, .12, .72, 1],
    ),
    'glass' => envelope([surface, surface, soft], stops: const [0, .52, 1]),
    'desk' => envelope([surface, surface]),
    'control' => envelope([control, control]),
    _ => throw ArgumentError.value(key),
  };
}

Color _gradientColor(LinearGradient gradient, double position) {
  final stops =
      gradient.stops ??
      [
        for (var i = 0; i < gradient.colors.length; i++)
          i / (gradient.colors.length - 1),
      ];
  if (position <= stops.first) return gradient.colors.first;
  for (var i = 1; i < stops.length; i++) {
    if (position <= stops[i]) {
      return Color.lerp(
        gradient.colors[i - 1],
        gradient.colors[i],
        (position - stops[i - 1]) / (stops[i] - stops[i - 1]),
      )!;
    }
  }
  return gradient.colors.last;
}

void _expectOpacityEnvelope(
  LinearGradient actual,
  LinearGradient expected,
  String label,
) {
  expect(
    actual.begin,
    expected.begin,
    reason: '$label retains alpha direction',
  );
  expect(actual.end, expected.end, reason: '$label retains alpha direction');
  expect(actual.tileMode, expected.tileMode);
  expect(actual.transform, expected.transform);
  final positions = <double>{
    ...?actual.stops,
    ...?expected.stops,
    for (var i = 0; i <= 200; i++) i / 200,
  };
  for (final position in positions) {
    expect(
      _gradientColor(actual, position).a,
      closeTo(_gradientColor(expected, position).a, 1e-6),
      reason: '$label retains the alpha envelope at $position',
    );
  }
}

void _expectReadingContrast(LinearGradient face, ThemeSpec spec, String label) {
  // Sample the actual reading gradient, not the deliberately bright rim or
  // artwork well. Transparency is checked separately: this checks the opaque
  // material tint across every stop and the entire interpolated face.
  final positions = <double>{
    ...?face.stops,
    for (var i = 0; i <= 100; i++) i / 100,
  };
  for (final position in positions) {
    final background = _gradientColor(face, position).computeLuminance();
    for (final ink in [spec.palette.text, spec.palette.textMuted]) {
      final foreground = ink.computeLuminance();
      final ratio = foreground > background
          ? (foreground + .05) / (background + .05)
          : (background + .05) / (foreground + .05);
      expect(
        ratio,
        greaterThanOrEqualTo(4.5),
        reason: '$label reading contrast at $position for $ink',
      );
    }
  }
}

Future<void> _expectFaceAlpha(
  LinearGradient actual,
  LinearGradient expected,
  Size size,
  String label,
) async {
  const margin = 8;
  final width = size.width.ceil() + margin * 2;
  final height = size.height.ceil() + margin * 2;
  final rect = Offset(margin.toDouble(), margin.toDouble()) & size;
  Future<ui.Image> render(LinearGradient gradient) async {
    final recorder = ui.PictureRecorder();
    Canvas(
      recorder,
    ).drawRect(rect, Paint()..shader = gradient.createShader(rect));
    final picture = recorder.endRecording();
    try {
      return await picture.toImage(width, height);
    } finally {
      picture.dispose();
    }
  }

  final image = await render(actual);
  final reference = await render(expected);
  try {
    final bytes = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
    final baseline = (await reference.toByteData(
      format: ui.ImageByteFormat.rawRgba,
    ))!;
    var mismatches = 0;
    var outside = 0;
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        final index = (y * width + x) * 4 + 3;
        final alpha = bytes.getUint8(index);
        if ((alpha - baseline.getUint8(index)).abs() > 1) mismatches++;
        if (!rect.contains(Offset(x + .5, y + .5)) && alpha != 0) outside++;
      }
    }
    expect(mismatches, 0, reason: '$label preserves the raster alpha envelope');
    expect(outside, 0, reason: '$label face stays within its panel');
  } finally {
    image.dispose();
    reference.dispose();
  }
}

Future<void> _expectBottomLipOnly(
  CustomPainter painter,
  Size size,
  String label,
) async {
  const margin = 8;
  final width = size.width.ceil() + margin * 2;
  final height = size.height.ceil() + margin * 2;
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder)
    ..translate(margin.toDouble(), margin.toDouble());
  painter.paint(canvas, size);
  final picture = recorder.endRecording();
  final image = await picture.toImage(width, height);
  try {
    final bytes = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
    var outside = 0;
    var readingPixels = 0;
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        if (bytes.getUint8((y * width + x) * 4 + 3) == 0) continue;
        if (x < margin ||
            y < margin ||
            x >= margin + size.width ||
            y >= margin + size.height) {
          outside++;
        }
        if (y < margin + size.height - 5) readingPixels++;
      }
    }
    expect(outside, 0, reason: '$label background paint stays in bounds');
    expect(
      readingPixels,
      0,
      reason: '$label does not stack paint over its reading face',
    );
    expect(painter.hitTest(Offset.zero), isFalse);
    expect(painter.shouldRepaint(painter), isFalse);
  } finally {
    image.dispose();
    picture.dispose();
  }
}

Widget _fixture(ThemeSpec spec, int opacity, {VoidCallback? onTap}) {
  Widget content() => GestureDetector(
    behavior: HitTestBehavior.opaque,
    onTap: onTap ?? () {},
    child: const SizedBox.expand(child: Center(child: Text('Readout'))),
  );
  Widget panel(String key, Widget child) =>
      SizedBox(key: ValueKey(key), width: 180, height: 90, child: child);
  return MaterialApp(
    theme: spec.materialTheme(),
    home: Scaffold(
      body: Center(
        child: ResourceMapChromeTheme(
          data: resourceMapChromeThemeForPlannerTheme(
            spec,
          ).withUiOpacity(opacity / 100),
          child: Theme(
            data: companionTheme(
              opacityPercent: opacity,
              visualPalette: gatheringPaletteForTheme(spec),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                panel('atlas', ResourceMapAtlasPalette(child: content())),
                panel('map-pill', ResourceMapPill(child: content())),
                panel('glass', GlassSurface(child: content())),
                panel('desk', FieldDeskPanel(child: content())),
                panel('control', GlassControl(child: content())),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

Future<void> _expectEdgeOnly(
  CustomPainter painter,
  Size size,
  String label,
) async {
  const margin = 8;
  final width = size.width.ceil() + margin * 2;
  final height = size.height.ceil() + margin * 2;
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder)
    ..translate(margin.toDouble(), margin.toDouble());
  painter.paint(canvas, size);
  final picture = recorder.endRecording();
  final image = await picture.toImage(width, height);
  try {
    final bytes = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
    int alpha(int x, int y) => bytes.getUint8((y * width + x) * 4 + 3);
    var edgePixels = 0;
    var outsidePixels = 0;
    var readingPixels = 0;
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        final value = alpha(x, y);
        final outside =
            x < margin ||
            y < margin ||
            x >= margin + size.width ||
            y >= margin + size.height;
        if (outside && value > 0) outsidePixels++;
        if (value > 0) edgePixels++;
      }
    }
    expect(
      edgePixels,
      greaterThan(0),
      reason: '$label retains its faint 0% rim',
    );
    expect(alpha(margin, margin), 0, reason: '$label respects rounded corners');
    expect(outsidePixels, 0, reason: '$label paints outside its bounds');
    for (var y = margin + 5; y < margin + size.height - 5; y++) {
      for (var x = margin + 20; x < margin + size.width - 20; x++) {
        if (alpha(x, y) > 0) readingPixels++;
      }
    }
    expect(
      readingPixels,
      0,
      reason: '$label leaves the reading centre unpainted',
    );
  } finally {
    image.dispose();
    picture.dispose();
  }
}
