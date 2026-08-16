import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:bdo_craft_planner_flutter/visual/visual.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const settings = AtmosphereVisualSettings(
    style: 'embers',
    density: .5,
    opacity: .7,
    minimumSize: .7,
    maximumSize: 1.6,
    blur: .1,
    speed: .5,
    strength: .5,
    hue: 30,
    rainbow: false,
    neon: false,
    animated: true,
  );

  testWidgets('atmosphere is paint-only and reduced motion is static', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: SizedBox(
          width: 400,
          height: 300,
          child: StandardAtmosphere(settings: settings, reduceMotion: true),
        ),
      ),
    );

    final atmosphere = find.byType(StandardAtmosphere);
    expect(
      find.descendant(of: atmosphere, matching: find.byType(IgnorePointer)),
      findsOneWidget,
    );
    expect(
      find.descendant(of: atmosphere, matching: find.byType(ExcludeSemantics)),
      findsOneWidget,
    );
    final paint = tester.widget<CustomPaint>(
      find.descendant(of: atmosphere, matching: find.byType(CustomPaint)),
    );
    expect(paint.painter, isA<StandardAtmospherePainter>());
  });

  test('painter invalidates for time and settings changes', () {
    const first = StandardAtmospherePainter(settings: settings, progress: 0);
    const second = StandardAtmospherePainter(settings: settings, progress: .5);
    expect(second.shouldRepaint(first), isTrue);
  });

  test('authored default palettes remain distinct from custom hue', () async {
    final authored = await _paint(
      _settings(style: 'embers', hue: 158, customColor: false),
    );
    final custom = await _paint(
      _settings(style: 'embers', hue: 158, customColor: true),
    );

    expect(
      _containsPixel(
        authored,
        (red, green, blue, alpha) =>
            alpha > 20 && red > green + 40 && green > blue,
      ),
      isTrue,
      reason: 'default embers use Avalonia\'s authored orange palette',
    );
    expect(
      _containsPixel(
        custom,
        (red, green, blue, alpha) =>
            alpha > 20 && green > red + 40 && green > blue + 20,
      ),
      isTrue,
      reason: 'a selected hue still overrides the authored default palette',
    );
  });

  test(
    'depth-radius formula materially scales the visible silhouettes',
    () async {
      final small = await _paint(
        _settings(style: 'petals', minimumSize: .45, maximumSize: .45, blur: 0),
      );
      final large = await _paint(
        _settings(style: 'petals', minimumSize: 2.2, maximumSize: 2.2, blur: 0),
      );

      expect(_alphaCoverage(large), greaterThan(_alphaCoverage(small) * 2));
    },
  );
}

AtmosphereVisualSettings _settings({
  required String style,
  double hue = 158,
  bool customColor = false,
  double minimumSize = .72,
  double maximumSize = 1.6,
  double blur = .12,
}) => AtmosphereVisualSettings(
  style: style,
  density: .57,
  opacity: .69,
  minimumSize: minimumSize,
  maximumSize: maximumSize,
  blur: blur,
  speed: .23,
  strength: .19,
  hue: hue,
  customColor: customColor,
  rainbow: false,
  neon: false,
  animated: true,
);

Future<Uint8List> _paint(AtmosphereVisualSettings settings) async {
  final recorder = ui.PictureRecorder();
  StandardAtmospherePainter(
    settings: settings,
    progress: .37,
  ).paint(ui.Canvas(recorder), const Size(600, 400));
  final picture = recorder.endRecording();
  final image = await picture.toImage(600, 400);
  final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  image.dispose();
  picture.dispose();
  return data!.buffer.asUint8List();
}

bool _containsPixel(
  Uint8List bytes,
  bool Function(int red, int green, int blue, int alpha) matches,
) {
  for (var index = 0; index < bytes.length; index += 4) {
    if (matches(
      bytes[index],
      bytes[index + 1],
      bytes[index + 2],
      bytes[index + 3],
    )) {
      return true;
    }
  }
  return false;
}

int _alphaCoverage(Uint8List bytes) {
  var count = 0;
  for (var index = 3; index < bytes.length; index += 4) {
    if (bytes[index] > 8) count++;
  }
  return count;
}
