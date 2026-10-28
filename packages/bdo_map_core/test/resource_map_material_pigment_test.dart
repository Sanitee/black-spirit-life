import 'package:bdo_map_core/src/widgets/resource_map_chrome_theme.dart';
import 'package:bdo_map_core/src/widgets/resource_map_pill.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('actual finish pigments retain exact RGB at every material alpha', () {
    const chrome = ResourceMapChromeThemeData.fieldAtlas;
    const pigment = Color.from(alpha: 1, red: .271001, green: .19, blue: .21);
    for (final artwork in [false, true]) {
      for (final alpha in [0.0, .02, .1, .3, .6, .7, 1.0]) {
        final result = resourceMapMaterialPigment(
          chrome,
          pigment,
          alpha,
          artwork: artwork,
        );
        expect(result.r, pigment.r);
        expect(result.g, pigment.g);
        expect(result.b, pigment.b);
        expect(result.a, alpha);
      }
    }
  });

  test(
    'material density retains saved values and the smooth two-percent floor',
    () {
      const base = ResourceMapChromeThemeData.fieldAtlas;
      var previous = 0.0;
      for (var step = 0; step <= 100; step++) {
        final slider = step / 100;
        final chrome = base.withUiOpacity(slider);
        expect(chrome.uiOpacity, slider);
        expect(chrome.materialOpacity, inInclusiveRange(.02, 1));
        expect(chrome.materialOpacity, greaterThanOrEqualTo(previous));
        final expected = slider <= .02
            ? .02
            : .02 + .98 * (1 - ((1 - slider) / .98) * ((1 - slider) / .98));
        expect(chrome.materialOpacity, closeTo(expected, .00000001));
        previous = chrome.materialOpacity;
      }
      expect(base.withUiOpacity(0).materialOpacity, .02);
      expect(base.withUiOpacity(.02).materialOpacity, .02);
      expect(
        base.withUiOpacity(.7).materialOpacity,
        closeTo(.9081632653, .00000001),
      );
      expect(base.withUiOpacity(1).materialOpacity, 1);
    },
  );

  test('opacity changes material only and retains bright finish accent', () {
    const base = ResourceMapChromeThemeData.fieldAtlas;
    final palette = base.withPalette(
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
    for (final slider in [0.0, .25, .7, 1.0]) {
      final chrome = palette.withUiOpacity(slider);
      expect(chrome.finishAccent, const Color(0xFFE8B0BF));
      expect(chrome.accent, const Color(0xFFA66C69));
      expect(chrome.primary, palette.primary);
      expect(chrome.ink, palette.ink);
      expect(chrome.muted, palette.muted);
      expect(chrome.canvas, const Color(0xFF141218));
      expect(chrome.commandRadius, palette.commandRadius);
      expect(chrome.surfaceRadius, palette.surfaceRadius);
      expect(
        chrome.surfaceGradient.colors.first.a,
        closeTo(
          palette.surfaceGradient.colors.first.a * chrome.materialOpacity,
          .0000001,
        ),
      );
      final restored = chrome.withUiOpacity(1);
      expect(
        restored.surfaceGradient.colors.first.a,
        closeTo(palette.surfaceGradient.colors.first.a, .0000001),
      );
      expect(restored.finishAccent, palette.finishAccent);
    }
  });

  test('raised gradient retains source alpha, direction and transform', () {
    const source = LinearGradient(
      begin: Alignment(-.8, -.6),
      end: Alignment(.9, .7),
      tileMode: TileMode.mirror,
      transform: GradientRotation(.3),
      stops: [0, .13, .76, 1],
      colors: [
        Color(0x05303030),
        Color(0x70505050),
        Color(0xB0707070),
        Color(0xEE909090),
      ],
    );
    for (final pressed in [false, true]) {
      final gradient = resourceMapRaisedSurfaceGradient(
        ResourceMapChromeThemeData.sakuraCartographer,
        source,
        pressed: pressed,
      );
      expect(gradient.begin, source.begin);
      expect(gradient.end, source.end);
      expect(gradient.tileMode, source.tileMode);
      expect(gradient.transform, same(source.transform));
      expect(gradient.stops, containsAll(source.stops!));
      for (var index = 0; index < gradient.colors.length; index++) {
        expect(
          gradient.colors[index].a,
          _interpolate(source, gradient.stops![index]).a,
        );
      }
    }
  });
}

Color _interpolate(LinearGradient gradient, double stop) {
  final positions = gradient.stops!;
  for (var index = 1; index < positions.length; index++) {
    if (stop <= positions[index]) {
      return Color.lerp(
        gradient.colors[index - 1],
        gradient.colors[index],
        (stop - positions[index - 1]) /
            (positions[index] - positions[index - 1]),
      )!;
    }
  }
  return gradient.colors.last;
}
