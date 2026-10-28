import 'package:flutter/material.dart';

import 'resource_map_chrome_theme.dart';

/// Copper-card pigments are derived from Appearance roles, not a theme ID.
/// Reflection is baked into each pigment so it never adds an opacity layer.
/// Keep this six-stop recipe aligned with Gathering's copper-card finish.
LinearGradient resourceMapCopperFace(
  ResourceMapChromeThemeData chrome,
  LinearGradient source, {
  bool pressed = false,
}) {
  final r = chrome.chromeRaised.withValues(alpha: 1);
  final b = chrome.chromeBase.withValues(alpha: 1);
  final i = chrome.controlInset.withValues(alpha: 1);
  final p = chrome.primary.withValues(alpha: 1);
  final a = chrome.accent.withValues(alpha: 1);
  final k = chrome.ink.withValues(alpha: 1);
  final light = r.computeLuminance() > .45;
  final colours = light
      ? [
          Color.lerp(r, Colors.white, .34)!,
          Color.lerp(r, Colors.white, .12)!,
          r,
          Color.lerp(r, b, .15)!,
          Color.lerp(r, a, .10)!,
          Color.lerp(b, i, .18)!,
        ]
      : [
          Color.lerp(Color.lerp(r, p, .36), k, .12)!,
          Color.lerp(r, p, .26)!,
          Color.lerp(r, p, .15)!,
          Color.lerp(b, p, .12)!,
          Color.lerp(r, p, .24)!,
          Color.lerp(b, i, .24)!,
        ];
  const positions = [0.0, .12, .44, .76, .92, 1.0];
  final sourceStops = _stops(source);
  final stops = {...sourceStops, ...positions}.toList()..sort();
  final face = pressed ? colours.reversed.toList() : colours;
  return LinearGradient(
    begin: source.begin,
    end: source.end,
    stops: stops,
    tileMode: source.tileMode,
    transform: source.transform,
    colors: [
      for (final stop in stops)
        _colourAt(
          face,
          positions,
          stop,
        ).withValues(alpha: _colourAt(source.colors, sourceStops, stop).a),
    ],
  );
}

LinearGradient resourceMapCopperBay(
  ResourceMapChromeThemeData chrome,
  LinearGradient source, {
  bool pressed = false,
  bool highlighted = false,
}) {
  final r = chrome.chromeRaised.withValues(alpha: 1);
  final b = chrome.chromeBase.withValues(alpha: 1);
  final p = chrome.primary.withValues(alpha: 1);
  final a = chrome.accent.withValues(alpha: 1);
  final warm = Color.lerp(a, const Color(0xFFFFDFB0), .60)!;
  final light = r.computeLuminance() > .45;
  final colours = light
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
        ];
  const positions = [0.0, .15, .35, .58, .77, 1.0];
  const reflectionStops = [0.0, .12, .31, .47, .74, 1.0];
  const reflectionAlphas = [0.0, .02, .62, .26, 0.0, 0.0];
  final stops = {...positions, ...reflectionStops, 0.72}.toList()..sort();
  final metal = pressed ? colours.reversed.toList() : colours;
  final reflection = highlighted ? .85 : .65;
  return LinearGradient(
    // Resolve this shader in the artwork bay, never in the full row's width.
    begin: const Alignment(-.84, -1),
    end: const Alignment(.84, 1),
    stops: stops,
    tileMode: source.tileMode,
    transform: source.transform,
    colors: [
      for (final stop in stops)
        Color.alphaBlend(
          warm.withValues(
            alpha:
                _valueAt(reflectionAlphas, reflectionStops, stop) * reflection,
          ),
          _colourAt(metal, positions, stop),
        ).withValues(
          // Artwork keeps its full material density, including quiet rows.
          alpha:
              chrome.materialOpacity *
              (stop <= .12
                  ? .96
                  : stop >= .72
                  ? .98
                  : .96 + .02 * (stop - .12) / .60),
        ),
    ],
  );
}

List<double> _stops(LinearGradient gradient) =>
    gradient.stops ??
    [
      for (var i = 0; i < gradient.colors.length; i++)
        i / (gradient.colors.length - 1),
    ];

Color _colourAt(List<Color> colours, List<double> stops, double position) {
  for (var i = 1; i < stops.length; i++) {
    if (position <= stops[i]) {
      return Color.lerp(
        colours[i - 1],
        colours[i],
        (position - stops[i - 1]) / (stops[i] - stops[i - 1]),
      )!;
    }
  }
  return colours.last;
}

double _valueAt(List<double> values, List<double> stops, double position) {
  for (var i = 1; i < stops.length; i++) {
    if (position <= stops[i]) {
      final t = (position - stops[i - 1]) / (stops[i] - stops[i - 1]);
      return values[i - 1] * (1 - t) + values[i] * t;
    }
  }
  return values.last;
}
