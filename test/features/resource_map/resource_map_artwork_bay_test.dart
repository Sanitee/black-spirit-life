import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:bdo_craft_planner_flutter/domain/models/craft_mode.dart';
import 'package:bdo_craft_planner_flutter/domain/state/planner_state.dart';
import 'package:bdo_craft_planner_flutter/features/resource_map/resource_map_theme_adapter.dart';
import 'package:bdo_craft_planner_flutter/visual/foundations/application_theme.dart';
import 'package:bdo_craft_planner_flutter/visual/foundations/theme_spec.dart';
import 'package:bdo_craft_planner_flutter/visual/illuminated_ledger/ledger_spec.dart';
import 'package:bdo_craft_planner_flutter/visual/sakura_night_garden/sakura_spec.dart';
import 'package:bdo_map_core/src/widgets/resource_map_chrome_theme.dart';
import 'package:bdo_map_core/src/widgets/resource_map_copper_finish.dart';
import 'package:bdo_map_core/src/widgets/resource_map_pill.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _size = Size(280, 64);
const _bayWidth = 52.0;
const _margin = 8;
const _artworkKey = ValueKey('retained-artwork');
const _labelKey = ValueKey('retained-label');

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
      for (final direction in TextDirection.values) {
        testWidgets(
          '$name $opacity% $direction artwork bay keeps geometry and one alpha plane',
          (tester) async {
            var taps = 0;
            await tester.pumpWidget(
              _fixture(spec, opacity, direction, onTap: () => taps++),
            );
            await tester.pumpAndSettle();
            final plain = _renderedDecoration(tester);
            expect(plain.runtimeType, BoxDecoration);
            final originalBounds = tester.getRect(find.byType(ResourceMapPill));
            final artworkBounds = tester.getRect(find.byKey(_artworkKey));
            final labelBounds = tester.getRect(find.byKey(_labelKey));
            final artwork = tester.element(find.byKey(_artworkKey));
            final label = tester.element(find.byKey(_labelKey));

            await tester.pumpWidget(
              _fixture(
                spec,
                opacity,
                direction,
                leadingWidth: _bayWidth,
                onTap: () => taps++,
              ),
            );
            await tester.pumpAndSettle();
            final split = _renderedDecoration(tester);
            expect(split.runtimeType, isNot(BoxDecoration));
            final chrome = resourceMapChromeThemeForPlannerTheme(
              spec,
            ).withUiOpacity(opacity / 100);
            final copper = resourceMapCopperFace(
              chrome,
              plain.gradient! as LinearGradient,
            );
            final actualFace = split.gradient! as LinearGradient;
            for (final stop in actualFace.stops!) {
              final actual = _at(actualFace, stop);
              final expected = _at(copper, stop);
              expect(actual.r, closeTo(expected.r, 1e-9));
              expect(actual.g, closeTo(expected.g, 1e-9));
              expect(actual.b, closeTo(expected.b, 1e-9));
              expect(actual.a, closeTo(expected.a, 1e-9));
            }
            expect(split.border!.dimensions, plain.border!.dimensions);
            expect(
              (split.border! as Border).top.color,
              chrome.accent.withValues(alpha: .34 * chrome.materialOpacity),
            );
            expect(split.borderRadius, plain.borderRadius);
            expect(split.padding, plain.padding);
            expect(split.color, isNull);
            expect(split.image, isNull);
            expect(split.boxShadow, isNull);
            _expectDirectBayRecipe(split, spec, opacity / 100);
            expect(originalBounds.size, _size);
            expect(
              tester.getRect(find.byType(ResourceMapPill)),
              originalBounds,
            );
            expect(tester.getRect(find.byKey(_artworkKey)), artworkBounds);
            expect(tester.getRect(find.byKey(_labelKey)), labelBounds);
            expect(tester.element(find.byKey(_artworkKey)), same(artwork));
            expect(tester.element(find.byKey(_labelKey)), same(label));
            await tester.runAsync(
              () => _expectSplitPixels(
                split,
                _plainFace(split),
                direction,
                '$name/$opacity/$direction',
                expectStrongBay: opacity > 0,
              ),
            );

            await tester.tapAt(originalBounds.center);
            await tester.pumpAndSettle();
            expect(taps, 1);
            expect(
              tester.getRect(find.byType(ResourceMapPill)),
              originalBounds,
            );
            expect(find.byType(Opacity), findsNothing);
            expect(find.byType(ShaderMask), findsNothing);
            expect(find.byType(BackdropFilter), findsNothing);
            expect(find.byType(ImageFiltered), findsNothing);
            expect(find.byType(ColorFiltered), findsNothing);
            expect(tester.binding.transientCallbackCount, 0);
            expect(tester.takeException(), isNull);
          },
        );
      }
    }
  }

  testWidgets(
    'artwork bay retains keyboard focus, press and animated split fill',
    (tester) async {
      final focus = FocusNode();
      addTearDown(focus.dispose);
      await tester.pumpWidget(
        _fixture(
          SakuraNightGardenSpec.theme,
          60,
          TextDirection.ltr,
          leadingWidth: _bayWidth,
          focusNode: focus,
        ),
      );
      await tester.pumpAndSettle();
      final idle = _renderedDecoration(tester);
      final bounds = tester.getRect(find.byType(ResourceMapPill));
      final artwork = tester.element(find.byKey(_artworkKey));
      focus.requestFocus();
      await tester.pumpAndSettle();
      expect(focus.hasFocus, isTrue);
      final focused = _renderedDecoration(tester);
      expect(focused.gradient, idle.gradient);
      expect(_bay(focused), isNot(_bay(idle)));
      expect(
        tester
            .widget<AnimatedContainer>(
              find.descendant(
                of: find.byType(ResourceMapPill),
                matching: find.byType(AnimatedContainer),
              ),
            )
            .duration,
        const Duration(milliseconds: 140),
      );
      final mouse = await tester.createGesture(
        kind: ui.PointerDeviceKind.mouse,
      );
      await mouse.addPointer(location: Offset.zero);
      await mouse.moveTo(bounds.center);
      await tester.pumpAndSettle();
      expect(_renderedDecoration(tester).runtimeType, idle.runtimeType);
      expect(_renderedDecoration(tester).gradient, idle.gradient);

      final gesture = await tester.startGesture(bounds.center);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 75));
      final pressed = _renderedDecoration(tester);
      expect(pressed.runtimeType, idle.runtimeType);
      expect(pressed.gradient, isNot(idle.gradient));
      await tester.runAsync(
        () => _expectSplitPixels(
          pressed,
          _plainFace(pressed),
          TextDirection.ltr,
          'mid-press',
        ),
      );
      await gesture.up();
      await mouse.removePointer();
      await tester.pumpAndSettle();
      expect(focus.hasFocus, isTrue);
      expect(tester.element(find.byKey(_artworkKey)), same(artwork));
      expect(tester.getRect(find.byType(ResourceMapPill)), bounds);

      // Adding the optional bay must retain its painter during the transition,
      // not merely at the target; press/hover transitions above use it as well.
      for (final t in [.25, .5, .75]) {
        final tween =
            Decoration.lerp(_plainFace(idle), idle, t)! as BoxDecoration;
        expect(tween.runtimeType, idle.runtimeType);
        expect(tween.padding, idle.padding);
        await tester.runAsync(
          () => _expectSplitPixels(
            tween,
            _plainFace(tween),
            TextDirection.ltr,
            'entry tween/$t',
            leadingWidth: _bayWidth * t,
            expectStrongBay: false,
          ),
        );
      }
      expect(tester.binding.transientCallbackCount, 0);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('bounded twelve-control artwork bay recording and raster cost', (
    tester,
  ) async {
    final samples = <Map<String, Object?>>[];
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
        await tester.pumpWidget(
          _fixture(spec, opacity, TextDirection.ltr, leadingWidth: _bayWidth),
        );
        await tester.pumpAndSettle();
        final split = _renderedDecoration(tester);
        final plain = _plainFace(split);
        for (final (variant, decoration) in [
          ('plain', plain),
          ('artwork-bay', split),
        ]) {
          final timing = await tester.runAsync(
            () => _measureDecoration(decoration),
          );
          expect(timing, isNotNull);
          samples.add({
            'theme': name,
            'opacityPercent': opacity,
            'variant': variant,
            ...timing!,
          });
        }
        expect(tester.binding.transientCallbackCount, 0);
        expect(tester.takeException(), isNull);
      }
    }
    final report = {
      'scene': {
        'controls': 12,
        'controlSize': [280, 64],
        'rasterSize': [900, 320],
      },
      'recordWarmups': 5,
      'recordSamples': 15,
      'rasterWarmups': 2,
      'rasterSamples': 6,
      'samples': samples,
      'method':
          'Twelve retained production BoxPainters, comparing the exact same face gradient and border with and without the optional satin artwork bay. Shared app themes at 0, 60 and 100 percent. Display-list recording and awaited offscreen rasterization measured separately.',
      'limitations':
          'Bounded headless Flutter test/debug diagnostic, not hardware FPS, GPU frame time or release performance. Material-only cost excludes child text, artwork, outer contact shadow, existing edge painters, layout, input handling and network. Raster cost includes scheduling/image transfer and system noise.',
    };
    final directory = Platform.environment['MAP_ARTWORK_BAY_AUDIT_DIR'];
    if (directory != null) {
      await tester.runAsync(() async {
        await Directory(directory).create(recursive: true);
        await File(
          '$directory/resource-artwork-bay-benchmark.json',
        ).writeAsString(const JsonEncoder.withIndent('  ').convert(report));
      });
    } else {
      debugPrint(jsonEncode(report));
    }
  });
}

Future<Map<String, Object?>> _measureDecoration(
  BoxDecoration decoration,
) async {
  final painters = [for (var i = 0; i < 12; i++) decoration.createBoxPainter()];
  ui.Picture record() {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder)
      ..drawColor(const Color(0xFF63745B), BlendMode.src);
    for (var i = 0; i < painters.length; i++) {
      painters[i].paint(
        canvas,
        Offset(10 + (i % 3) * 300.0, 8 + (i ~/ 3) * 80.0),
        const ImageConfiguration(size: _size, textDirection: TextDirection.ltr),
      );
    }
    return recorder.endRecording();
  }

  Map<String, double> statistics(List<double> values) {
    final sorted = [...values]..sort();
    return {
      'medianMicroseconds': sorted[sorted.length ~/ 2],
      'p90Microseconds': sorted[(sorted.length * .9).ceil() - 1],
      'maxMicroseconds': sorted.last,
    };
  }

  final recording = <double>[];
  final raster = <double>[];
  try {
    for (var i = 0; i < 20; i++) {
      final timer = Stopwatch()..start();
      final picture = record();
      timer.stop();
      if (i >= 5) recording.add(timer.elapsedMicroseconds.toDouble());
      picture.dispose();
    }
    final picture = record();
    try {
      for (var i = 0; i < 8; i++) {
        final timer = Stopwatch()..start();
        final image = await picture.toImage(900, 320);
        timer.stop();
        if (i >= 2) raster.add(timer.elapsedMicroseconds.toDouble());
        image.dispose();
      }
    } finally {
      picture.dispose();
    }
    final recordStats = statistics(recording);
    final rasterStats = statistics(raster);
    expect(recordStats['medianMicroseconds'], lessThan(1000000));
    expect(rasterStats['medianMicroseconds'], lessThan(5000000));
    return {'record': recordStats, 'raster': rasterStats};
  } finally {
    for (final painter in painters) {
      painter.dispose();
    }
  }
}

Widget _fixture(
  ThemeSpec spec,
  int opacity,
  TextDirection direction, {
  double? leadingWidth,
  VoidCallback? onTap,
  FocusNode? focusNode,
}) => MaterialApp(
  theme: spec.materialTheme(),
  home: Scaffold(
    body: Directionality(
      textDirection: direction,
      child: ResourceMapChromeTheme(
        data: resourceMapChromeThemeForPlannerTheme(
          spec,
        ).withUiOpacity(opacity / 100),
        child: Center(
          child: SizedBox(
            width: _size.width,
            height: _size.height,
            child: ResourceMapPill(
              leadingWidth: leadingWidth,
              child: InkWell(
                onTap: onTap ?? () {},
                focusNode: focusNode,
                child: const Padding(
                  padding: EdgeInsetsDirectional.fromSTEB(8, 6, 10, 6),
                  child: Row(
                    children: [
                      SizedBox(key: _artworkKey, width: 36, height: 36),
                      SizedBox(width: 12),
                      Expanded(child: Text('Readout', key: _labelKey)),
                    ],
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

BoxDecoration _renderedDecoration(WidgetTester tester) {
  final face = find.descendant(
    of: find.byType(ResourceMapPill),
    matching: find.byWidgetPredicate(
      (widget) =>
          widget is DecoratedBox &&
          widget.decoration is BoxDecoration &&
          (widget.decoration as BoxDecoration).gradient != null,
    ),
  );
  expect(face, findsOneWidget);
  return tester.widget<DecoratedBox>(face).decoration as BoxDecoration;
}

BoxDecoration _plainFace(BoxDecoration split) => BoxDecoration(
  gradient: split.gradient,
  border: split.border,
  borderRadius: split.borderRadius,
);

Future<ByteData> _raster(
  BoxDecoration decoration,
  TextDirection direction,
) async {
  final recorder = ui.PictureRecorder();
  final painter = decoration.createBoxPainter();
  painter.paint(
    Canvas(recorder),
    const Offset(8, 8),
    ImageConfiguration(size: _size, textDirection: direction),
  );
  final picture = recorder.endRecording();
  try {
    final image = await picture.toImage(
      _size.width.toInt() + _margin * 2,
      _size.height.toInt() + _margin * 2,
    );
    try {
      return (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
    } finally {
      image.dispose();
    }
  } finally {
    painter.dispose();
    picture.dispose();
  }
}

Future<void> _expectSplitPixels(
  BoxDecoration actual,
  BoxDecoration expected,
  TextDirection direction,
  String label, {
  double leadingWidth = _bayWidth,
  bool expectStrongBay = true,
}) async {
  final bytes = await _raster(actual, direction);
  final reference = await _raster(expected, direction);
  final bayReference = await _rasterBay(actual, direction, leadingWidth);
  final width = _size.width.toInt() + _margin * 2;
  final height = _size.height.toInt() + _margin * 2;
  var alphaMismatch = 0;
  var bodyMismatch = 0;
  var bayPixels = 0;
  var changedBayPixels = 0;
  var outside = 0;
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final index = (y * width + x) * 4;
      final localX = x - _margin;
      final localY = y - _margin;
      if (localX < 0 ||
          localY < 0 ||
          localX >= _size.width ||
          localY >= _size.height) {
        if (bytes.getUint8(index + 3) != 0) outside++;
        continue;
      }
      // The intentional seam/edge glints and 1px lower ledge are not reading
      // surfaces. Test all actual face pixels, not just one centre sample.
      final distanceFromLeading = direction == TextDirection.rtl
          ? _size.width - localX - 1
          : localX.toDouble();
      if (localY < 8 ||
          localY >= _size.height - 8 ||
          localX < 8 ||
          localX >= _size.width - 8 ||
          (distanceFromLeading - leadingWidth).abs() < 3) {
        continue;
      }
      final inBay = distanceFromLeading < leadingWidth;
      final alphaReference = inBay ? bayReference : reference;
      if ((bytes.getUint8(index + 3) - alphaReference.getUint8(index + 3))
              .abs() >
          1) {
        alphaMismatch++;
      }
      final differs = [
        for (var c = 0; c < 4; c++)
          bytes.getUint8(index + c) != reference.getUint8(index + c),
      ].any((value) => value);
      if (inBay) {
        bayPixels++;
        if (differs) changedBayPixels++;
        for (var channel = 0; channel < 3; channel++) {
          expect(
            bytes.getUint8(index + channel),
            closeTo(bayReference.getUint8(index + channel), 1),
            reason: '$label bay-relative direct pigment at $localX,$localY',
          );
        }
      } else if (differs) {
        bodyMismatch++;
      }
    }
  }
  expect(outside, 0, reason: '$label artwork material stays inside the pill');
  expect(
    alphaMismatch,
    0,
    reason:
        '$label paints exactly one density-mapped plane in each disjoint region',
  );
  expect(
    bodyMismatch,
    0,
    reason: '$label leaves the reading face byte-identical',
  );
  expect(bayPixels, greaterThan(0));
  expect(
    changedBayPixels,
    expectStrongBay ? greaterThan(bayPixels * .7) : greaterThan(0),
    reason: '$label changes the broad artwork material, not only its border',
  );
}

// The decoration's public paint value is inspected without exposing its private
// implementation type. This also verifies interpolated press/entry gradients.
LinearGradient _bay(BoxDecoration decoration) =>
    (decoration as dynamic).bay as LinearGradient;

void _expectDirectBayRecipe(
  BoxDecoration decoration,
  ThemeSpec spec,
  double opacity,
) {
  final actual = _bay(decoration);
  final chrome = resourceMapChromeThemeForPlannerTheme(spec);
  final r = chrome.chromeRaised.withValues(alpha: 1);
  final b = chrome.chromeBase.withValues(alpha: 1);
  final p = chrome.primary.withValues(alpha: 1);
  final a = chrome.accent.withValues(alpha: 1);
  final warm = Color.lerp(a, const Color(0xFFFFDFB0), .60)!;
  final light = r.computeLuminance() > .45;
  final reference = LinearGradient(
    colors: light
        ? [
            Color.lerp(r, a, .22)!,
            Color.lerp(a, r, .34)!,
            Color.lerp(a, warm, .45)!,
            Color.lerp(a, r, .24)!,
            Color.lerp(r, a, .48)!,
            Color.lerp(r, b, .20)!,
          ]
        : [
            Color.lerp(r, a, .30)!,
            Color.lerp(a, r, .10)!,
            Color.lerp(a, warm, .42)!,
            Color.lerp(a, r, .18)!,
            Color.lerp(a, r, .38)!,
            Color.lerp(r, p, .12)!,
          ],
    stops: const [0, .15, .35, .58, .77, 1],
  );
  final reflection = LinearGradient(
    colors: [
      for (final alpha in [0.0, .02, .62, .26, 0.0, 0.0])
        warm.withValues(alpha: alpha * .65),
    ],
    stops: const [0, .12, .31, .47, .74, 1],
  );
  expect(actual.begin, const Alignment(-.84, -1));
  expect(actual.end, const Alignment(.84, 1));
  final u = opacity < .02 ? .02 : opacity;
  final density = .02 + .98 * (1 - ((1 - u) / .98) * ((1 - u) / .98));
  for (var i = 0; i < actual.colors.length; i++) {
    final stop = actual.stops![i];
    final target = Color.alphaBlend(
      _at(reflection, stop),
      _at(reference, stop),
    );
    expect(actual.colors[i].r, closeTo(target.r, 1e-9));
    expect(actual.colors[i].g, closeTo(target.g, 1e-9));
    expect(actual.colors[i].b, closeTo(target.b, 1e-9));
    final envelope = stop <= .12
        ? .96
        : stop >= .72
        ? .98
        : .96 + .02 * (stop - .12) / .60;
    expect(actual.colors[i].a, closeTo(density * envelope, 1e-9));
  }
}

Color _at(LinearGradient gradient, double position) {
  for (var i = 1; i < gradient.colors.length; i++) {
    if (position <= gradient.stops![i]) {
      return Color.lerp(
        gradient.colors[i - 1],
        gradient.colors[i],
        (position - gradient.stops![i - 1]) /
            (gradient.stops![i] - gradient.stops![i - 1]),
      )!;
    }
  }
  return gradient.colors.last;
}

Future<ByteData> _rasterBay(
  BoxDecoration decoration,
  TextDirection direction,
  double width,
) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  final rect = const Offset(8, 8) & _size;
  final bay = Rect.fromLTWH(
    direction == TextDirection.rtl ? rect.right - width : rect.left,
    rect.top,
    width,
    rect.height,
  );
  canvas.clipRRect(decoration.borderRadius!.resolve(direction).toRRect(rect));
  canvas.drawRect(bay, Paint()..shader = _bay(decoration).createShader(bay));
  final picture = recorder.endRecording();
  try {
    final image = await picture.toImage(
      _size.width.toInt() + _margin * 2,
      _size.height.toInt() + _margin * 2,
    );
    try {
      return (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
    } finally {
      image.dispose();
    }
  } finally {
    picture.dispose();
  }
}
