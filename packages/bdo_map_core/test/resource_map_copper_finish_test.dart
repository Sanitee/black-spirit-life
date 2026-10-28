import 'package:bdo_map_core/src/widgets/resource_map_chrome_theme.dart';
import 'package:bdo_map_core/src/widgets/resource_map_copper_finish.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final light in [false, true]) {
    for (final opacity in [0.0, .25, .7, 1.0]) {
      test('copper $light/$opacity retains single-plane alpha and roles', () {
        final chrome = _palette(light).withUiOpacity(opacity);
        final density = chrome.materialOpacity;
        final source = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          stops: const [0, .12, .72, 1],
          tileMode: TileMode.mirror,
          colors: [
            for (final envelope in [.96, .96, .98, .98])
              Colors.red.withValues(alpha: density * .48 * envelope),
          ],
        );
        final face = resourceMapCopperFace(chrome, source);
        final bay = resourceMapCopperBay(chrome, source);
        final highlighted = resourceMapCopperBay(
          chrome,
          source,
          highlighted: true,
        );
        final pressed = resourceMapCopperFace(chrome, source, pressed: true);
        expect(face.begin, source.begin);
        expect(face.end, source.end);
        expect(face.tileMode, TileMode.mirror);
        expect(face.stops, containsAll([0, .12, .44, .76, .92, 1]));
        for (var index = 0; index < face.colors.length; index++) {
          final stop = face.stops![index];
          expect(face.colors[index].a, closeTo(_at(source, stop).a, 1e-12));
          expect(pressed.colors[index].a, face.colors[index].a);
        }
        expect(
          pressed.colors.first.withValues(alpha: 1),
          face.colors.last.withValues(alpha: 1),
        );
        expect(bay.begin, const Alignment(-.84, -1));
        expect(bay.end, const Alignment(.84, 1));
        expect(bay.tileMode, source.tileMode);
        expect(bay.stops, highlighted.stops);
        for (var index = 0; index < bay.colors.length; index++) {
          final stop = bay.stops![index];
          final envelope = stop <= .12
              ? .96
              : stop >= .72
              ? .98
              : .96 + .02 * (stop - .12) / .60;
          expect(bay.colors[index].a, closeTo(density * envelope, 1e-12));
          expect(highlighted.colors[index].a, bay.colors[index].a);
        }
        final reflected = bay.stops!.indexOf(.31);
        expect(
          highlighted.colors[reflected].computeLuminance(),
          greaterThan(bay.colors[reflected].computeLuminance()),
        );
        expect(highlighted.colors.first, bay.colors.first);
        expect(highlighted.colors.last, bay.colors.last);
        expect(face.colors.first.a, lessThan(bay.colors.first.a));
      });
    }
  }

  test('quiet source cannot attenuate copper artwork or its reflection', () {
    final chrome = _palette(false).withUiOpacity(.7);
    const full = LinearGradient(colors: [Colors.red, Colors.blue]);
    final quiet = LinearGradient(
      colors: full.colors.map((color) => color.withValues(alpha: .01)).toList(),
    );
    expect(
      resourceMapCopperBay(chrome, quiet),
      resourceMapCopperBay(chrome, full),
    );
    expect(
      resourceMapCopperBay(chrome, quiet, highlighted: true),
      resourceMapCopperBay(chrome, full, highlighted: true),
    );
  });
}

ResourceMapChromeThemeData _palette(bool light) {
  const base = ResourceMapChromeThemeData.fieldAtlas;
  return base.withPalette(
    canvas: const Color(0xFF141218),
    surface: Color(light ? 0xFFE3C780 : 0xFF211A20),
    raised: Color(light ? 0xFFF6E6B7 : 0xFF2B2028),
    inset: Color(light ? 0xFFD7B970 : 0xFF100E12),
    foreground: Color(light ? 0xFF172B3B : 0xFFEEE5DC),
    secondaryForeground: Color(light ? 0xFF39434A : 0xFFB9A7A2),
    primary: Color(light ? 0xFF315A70 : 0xFFCF7F98),
    primaryBright: Color(light ? 0xFF5B8793 : 0xFFE8B0BF),
    trim: Color(light ? 0xFF9B733C : 0xFF6B3C48),
    trimBright: Color(light ? 0xFFB98D45 : 0xFFA66C69),
    positive: base.positive,
    warning: base.warning,
    error: base.error,
    shadow: Colors.black,
  );
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
