import 'dart:convert';

import 'package:flutter/material.dart';

/// Immutable presentation values supplied by the host. No app or saved-state
/// dependencies: the same palette can be carried to the detached helper.
@immutable
class CompanionVisualPalette {
  const CompanionVisualPalette({
    required this.brightness,
    required this.canvas,
    required this.canvasDeep,
    required this.surface,
    required this.raised,
    required this.inset,
    required this.ink,
    required this.muted,
    required this.accent,
    required this.accentBright,
    required this.gold,
    required this.edge,
    required this.rim,
    required this.positive,
    required this.warning,
    required this.danger,
  });

  static const fieldDesk = CompanionVisualPalette(
    brightness: Brightness.dark,
    canvas: Color(0xFF27212A),
    canvasDeep: Color(0xFF100E14),
    surface: Color(0xFF25212A),
    raised: Color(0xFF342B32),
    inset: Color(0xFF141117),
    ink: Color(0xFFF1E8D8),
    muted: Color(0xFFB9ABB1),
    accent: Color(0xFFE1B5B1),
    accentBright: Color(0xFFC58C92),
    gold: Color(0xFFC6A06B),
    edge: Color(0xFF8D7274),
    rim: Color(0xFFF2DCC0),
    positive: Color(0xFF9DC4AA),
    warning: Color(0xFFC6A06B),
    danger: Color(0xFFFFB4A3),
  );

  final Brightness brightness;
  final Color canvas, canvasDeep, surface, raised, inset;
  final Color ink, muted, accent, accentBright, gold, edge, rim;
  final Color positive, warning, danger;

  Color get onAccent {
    final light = const Color(0xFFFFFCF4);
    final dark = const Color(0xFF171419);
    double contrast(Color first, Color second) {
      final a = first.computeLuminance(), b = second.computeLuminance();
      return (a > b ? a + .05 : b + .05) / (a > b ? b + .05 : a + .05);
    }

    final darkScore = [
      accent,
      accentBright,
    ].map((color) => contrast(color, dark)).reduce((a, b) => a < b ? a : b);
    final lightScore = [
      accent,
      accentBright,
    ].map((color) => contrast(color, light)).reduce((a, b) => a < b ? a : b);
    return darkScore >= lightScore ? dark : light;
  }

  Map<String, Color> get _colors => {
    'canvas': canvas,
    'canvasDeep': canvasDeep,
    'surface': surface,
    'raised': raised,
    'inset': inset,
    'ink': ink,
    'muted': muted,
    'accent': accent,
    'accentBright': accentBright,
    'gold': gold,
    'edge': edge,
    'rim': rim,
    'positive': positive,
    'warning': warning,
    'danger': danger,
  };

  /// Argument-safe, bounded data only. Never interprets paths, URLs or code.
  String encode() => base64Url
      .encode(
        utf8.encode(
          jsonEncode({
            'version': 1,
            'brightness': brightness.name,
            'colors': _colors.map(
              (key, color) => MapEntry(key, color.toARGB32()),
            ),
          }),
        ),
      )
      .replaceAll('=', '');

  static CompanionVisualPalette? decode(String? payload) {
    if (payload == null ||
        payload.isEmpty ||
        payload.length > 8192 ||
        !RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(payload)) {
      return null;
    }
    try {
      final value = jsonDecode(
        utf8.decode(base64Url.decode(base64Url.normalize(payload))),
      );
      if (value is! Map<String, dynamic> ||
          value['version'] != 1 ||
          !const ['light', 'dark'].contains(value['brightness'])) {
        return null;
      }
      final colors = value['colors'];
      if (colors is! Map<String, dynamic> || colors.length != 15) return null;
      Color color(String key) {
        final value = colors[key];
        // Opaque semantic colors keep text opaque, independently of glass.
        if (value is! int || value < 0xFF000000 || value > 0xFFFFFFFF) {
          throw const FormatException('Invalid palette color');
        }
        return Color(value);
      }

      return CompanionVisualPalette(
        brightness: value['brightness'] == 'light'
            ? Brightness.light
            : Brightness.dark,
        canvas: color('canvas'),
        canvasDeep: color('canvasDeep'),
        surface: color('surface'),
        raised: color('raised'),
        inset: color('inset'),
        ink: color('ink'),
        muted: color('muted'),
        accent: color('accent'),
        accentBright: color('accentBright'),
        gold: color('gold'),
        edge: color('edge'),
        rim: color('rim'),
        positive: color('positive'),
        warning: color('warning'),
        danger: color('danger'),
      );
    } on FormatException {
      return null;
    }
  }
}
