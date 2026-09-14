import 'package:bdo_map_core/bdo_map_core.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('opacity clamps malformed imports and keeps the old default', () {
    for (final value in [null, '0.7', true, double.nan, double.infinity]) {
      expect(ResourceMapUiOpacity.normalize(value), 1);
    }
    expect(ResourceMapUiOpacity.minimum, 0);
    expect(ResourceMapUiOpacity.normalize(-1), 0);
    expect(ResourceMapUiOpacity.normalize(3), 1);
    expect(ResourceMapUiOpacity.normalize(.75), .75);
    for (final value in [0.0, .01, .02, .25, .65, .75, 1.0]) {
      expect(ResourceMapUiOpacity.normalize(value), value);
      expect(ResourceMapUiOpacity.material(value), value < .02 ? .02 : value);
    }
  });

  for (final chrome in [
    ResourceMapChromeThemeData.glassDock,
    ResourceMapChromeThemeData.ghostLedger,
    ResourceMapChromeThemeData.sakuraCartographer,
    ResourceMapChromeThemeData.illuminatedAtlas,
  ]) {
    for (final opacity in [0.0, .01, .25, .6, 1.0]) {
      test('${chrome.variant.name} fades material and shadows at $opacity', () {
        final changed = chrome.withUiOpacity(opacity);
        final material = opacity < .02 ? .02 : opacity;
        expect(changed.uiOpacity, opacity);
        expect(changed.materialOpacity, material);
        _expectMaterials(changed, chrome, material);
        expect(
          changed.fillAlpha(chrome.primary, .9).a,
          closeTo(.9 * material, 1e-9),
        );
      });
    }
    test('${chrome.variant.name} safely refades from zero without drift', () {
      var changed = chrome;
      for (var repeat = 0; repeat < 4; repeat++) {
        for (final opacity in [0.0, .01, .75, 0.0, 1.0, .25, .65, 1.0]) {
          changed = changed.withUiOpacity(opacity);
          expect(changed.uiOpacity, opacity);
          _expectMaterials(changed, chrome, opacity < .02 ? .02 : opacity);
        }
      }
    });
    test('${chrome.variant.name} changes fills without dimming content', () {
      final translucent = chrome.withUiOpacity(.65);
      expect(translucent.uiOpacity, .65);
      expect(translucent.ink, chrome.ink);
      expect(translucent.text, chrome.text);
      expect(translucent.muted, chrome.muted);
      expect(translucent.readingInk, chrome.readingInk);
      expect(translucent.readingMuted, chrome.readingMuted);
      expect(translucent.primary, chrome.primary);
      expect(translucent.accent, chrome.accent);
      expect(translucent.positive, chrome.positive);
      expect(translucent.error, chrome.error);
      expect(translucent.canvas, chrome.canvas);
      expect(translucent.headingStyle(), chrome.headingStyle());
      expect(translucent.surfaceRadius, chrome.surfaceRadius);
      expect(
        translucent.chromeBase.a,
        closeTo(chrome.chromeBase.a * .65, .001),
      );
      expect(
        translucent.fillAlpha(chrome.chromeBase, .9).a,
        closeTo(.585, .001),
      );
      for (var i = 0; i < chrome.readingSurfaceGradient.colors.length; i++) {
        expect(
          translucent.readingSurfaceGradient.colors[i].a,
          closeTo(chrome.readingSurfaceGradient.colors[i].a * .65, .001),
        );
      }
      expect(
        translucent.readingSurfaceGradient.stops,
        chrome.readingSurfaceGradient.stops,
      );
      expect(translucent.withUiOpacity(.65), same(translucent));
      final restored = translucent.withUiOpacity(1);
      expect(restored.chromeBase.a, closeTo(chrome.chromeBase.a, .001));
      expect(
        restored.readingSurfaceGradient.colors.first.a,
        closeTo(chrome.readingSurfaceGradient.colors.first.a, .001),
      );
    });
  }
}

void _expectMaterials(
  ResourceMapChromeThemeData actual,
  ResourceMapChromeThemeData original,
  double multiplier,
) {
  expect(
    [
      actual.ink,
      actual.text,
      actual.muted,
      actual.readingInk,
      actual.readingMuted,
      actual.primary,
      actual.deepAccent,
      actual.onPrimary,
      actual.accent,
      actual.positive,
      actual.warning,
      actual.error,
      actual.canvas,
    ],
    [
      original.ink,
      original.text,
      original.muted,
      original.readingInk,
      original.readingMuted,
      original.primary,
      original.deepAccent,
      original.onPrimary,
      original.accent,
      original.positive,
      original.warning,
      original.error,
      original.canvas,
    ],
  );
  expect(actual.headingStyle(), original.headingStyle());
  expect(actual.surfaceRadius, original.surfaceRadius);
  expect(actual.controlRadius, original.controlRadius);
  final actualFills = _fills(actual);
  final originalFills = _fills(original);
  for (var i = 0; i < actualFills.length; i++) {
    final faded = actualFills[i];
    final base = originalFills[i];
    expect(faded.a.isFinite, isTrue);
    expect(faded.a, closeTo(base.a * multiplier, 1e-9));
    expect([faded.r, faded.g, faded.b], [base.r, base.g, base.b]);
  }
  final actualGradients = _gradients(actual);
  final originalGradients = _gradients(original);
  for (var i = 0; i < actualGradients.length; i++) {
    expect(actualGradients[i].stops, originalGradients[i].stops);
    expect(actualGradients[i].begin, originalGradients[i].begin);
    expect(actualGradients[i].end, originalGradients[i].end);
  }
  final actualShadows = _shadows(actual);
  final originalShadows = _shadows(original);
  for (var i = 0; i < actualShadows.length; i++) {
    final faded = actualShadows[i];
    final base = originalShadows[i];
    expect(faded.color.a, closeTo(base.color.a * multiplier, 1e-9));
    expect(faded.offset, base.offset);
    expect(faded.blurRadius, base.blurRadius);
    expect(faded.spreadRadius, base.spreadRadius);
    expect(faded.blurStyle, base.blurStyle);
  }
}

List<Color> _fills(ResourceMapChromeThemeData chrome) => [
  chrome.paper,
  chrome.paperRaised,
  chrome.chromeBase,
  chrome.chromeRaised,
  chrome.chromeHighlight,
  chrome.modeStripFadeColor,
  chrome.trimDeep,
  chrome.trimWash,
  chrome.contourColor,
  chrome.fleckColor,
  for (final gradient in _gradients(chrome)) ...gradient.colors,
];

List<LinearGradient> _gradients(ResourceMapChromeThemeData chrome) => [
  chrome.idleControlGradient,
  chrome.idleCompactGradient,
  chrome.hoverControlGradient,
  chrome.selectedControlGradient,
  chrome.selectedModeGradient,
  chrome.selectedCompactGradient,
  chrome.selectedInlineGradient,
  chrome.idleInlineGradient,
  chrome.idleSearchGradient,
  chrome.focusedSearchGradient,
  chrome.surfaceGradient,
  chrome.subtleSurfaceGradient,
  chrome.taskStripGradient,
  chrome.readingSurfaceGradient,
  chrome.edgeFadeGradient,
];

List<BoxShadow> _shadows(ResourceMapChromeThemeData chrome) => [
  chrome.idleShadow,
  chrome.selectedShadow,
  chrome.hoverShadow,
  ...chrome.surfaceShadows,
  ...chrome.subtleSurfaceShadows,
];
