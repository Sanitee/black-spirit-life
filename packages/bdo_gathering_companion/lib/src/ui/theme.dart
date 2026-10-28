import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../assets.dart';
import 'item_artwork.dart';
import 'visual_palette.dart';

const ink = Color(0xFFF1E8D8);
const muted = Color(0xFFB9ABB1);
const canvasColor = Color(0xFF141218);
const accent = Color(0xFFE1B5B1);
const positive = Color(0xFF9DC4AA);
const _glassRim = Color(0xFFF2DCC0);
const gold = Color(0xFFC6A06B);
const defaultGlassOpacityPercent = 60;
const glassOpacityPreferenceKey = 'glassOpacityPercent';
const glassBlurSigma = 14.0;

int normalizeGlassOpacity(Object? value) {
  if (value == null || value.toString().trim().isEmpty) {
    return defaultGlassOpacityPercent;
  }
  final parsed = value is num ? value.toDouble() : double.tryParse('$value');
  if (parsed == null || !parsed.isFinite) return defaultGlassOpacityPercent;
  return parsed.round().clamp(0, 100);
}

@immutable
class CompanionGlassTheme extends ThemeExtension<CompanionGlassTheme> {
  const CompanionGlassTheme({
    this.visualPalette,
    required this.opacityPercent,
    required this.surfaceOpacity,
    required this.softOpacity,
    required this.controlOpacity,
    required this.solidOpacity,
    required this.hoverOpacity,
    required this.hoverStrongOpacity,
    required this.selectedOpacity,
    required this.selectedStrongOpacity,
    required this.borderOpacity,
    required this.strongBorderOpacity,
    required this.shadowOpacity,
    required this.softShadowOpacity,
    required this.deepShadowOpacity,
    required this.highlightOpacity,
  });

  factory CompanionGlassTheme.fromPercent(
    Object? value, {
    CompanionVisualPalette? visualPalette,
  }) {
    final percent = normalizeGlassOpacity(value);
    final material = math.max(.02, percent / 100);
    final soft = math.min(1.0, material * (.82 / .76));
    final control = math.min(1.0, material * (.86 / .76));
    final solid = math.min(1.0, material * (.90 / .76));
    final strength = math.min(1.0, material / .76);
    // Hosted surfaces use the same satin pigment as Opportunities. Give that
    // pigment enough body over terrain instead of brightening its RGB. Keep
    // the saved percentage and the original 2%/100% endpoints unchanged.
    double density(double alpha) {
      if (visualPalette == null) return alpha;
      final unit = ((alpha - .02) / .98).clamp(0.0, 1.0);
      return .02 + .98 * (1 - (1 - unit) * (1 - unit));
    }

    return CompanionGlassTheme(
      visualPalette: visualPalette,
      opacityPercent: percent,
      surfaceOpacity: density(material),
      softOpacity: density(soft),
      controlOpacity: density(control),
      solidOpacity: density(solid),
      hoverOpacity: density(math.max(.16, control)),
      hoverStrongOpacity: density(math.max(.20, solid)),
      selectedOpacity: density(math.max(.24, control)),
      selectedStrongOpacity: density(math.max(.30, solid)),
      borderOpacity: .18 * strength,
      strongBorderOpacity: .34 * strength,
      shadowOpacity: .42 * strength,
      softShadowOpacity: .24 * strength,
      deepShadowOpacity: .68 * strength,
      highlightOpacity: .13 * strength,
    );
  }

  final int opacityPercent;
  final CompanionVisualPalette? visualPalette;
  CompanionVisualPalette get colors =>
      visualPalette ?? CompanionVisualPalette.fieldDesk;

  // Standalone callers retain the approved field-desk material. The host
  // supplies semantic colors, never feature/theme-ID conditionals.
  Color adapt(Color original, Color themed) =>
      visualPalette == null ? original : themed;
  final double surfaceOpacity;
  final double softOpacity;
  final double controlOpacity;
  final double solidOpacity;
  final double hoverOpacity;
  final double hoverStrongOpacity;
  final double selectedOpacity;
  final double selectedStrongOpacity;
  final double borderOpacity;
  final double strongBorderOpacity;
  final double shadowOpacity;
  final double softShadowOpacity;
  final double deepShadowOpacity;
  final double highlightOpacity;

  double get effectStrength =>
      math.min(1.0, math.max(.02, opacityPercent / 100) / .76);
  // Reading a popup must not depend on how transparent the user wants the map.
  double get backdropOpacity => .60;

  // Translucent glass needs a lighter tint to retain its apparent shade over
  // the scene. Fade that lift out as opacity rises; opaque surfaces keep their
  // original readable colors, and the saved opacity itself is unchanged.
  Color _litTint(Color solid, Color translucent, double opacity) => Color.lerp(
    solid,
    translucent,
    ((1 - surfaceOpacity) / .4).clamp(0.0, 1.0),
  )!.withValues(alpha: opacity);

  Color get panel => _litTint(
    adapt(const Color(0xFF25212A), colors.surface),
    adapt(const Color(0xFF3A3038), colors.raised),
    surfaceOpacity,
  );
  Color get row => _litTint(
    adapt(const Color(0xFF342B32), colors.raised),
    adapt(const Color(0xFF45353D), colors.raised),
    controlOpacity,
  );
  Color get group => _litTint(
    adapt(const Color(0xFF1B171E), colors.surface),
    adapt(const Color(0xFF241D26), colors.surface),
    math.max(.02, softOpacity * .5),
  );
  Color get inset => adapt(
    const Color(0xFF141117),
    colors.inset,
  ).withValues(alpha: math.max(.02, softOpacity * .54));

  /// Quiet warm-plum backing also keeps missing-artwork fallback text readable.
  Color get iconWell => _litTint(
    adapt(const Color(0xFF393039), colors.raised),
    adapt(const Color(0xFF4D3B44), colors.raised),
    controlOpacity,
  );

  /// Light bronze plates are for artwork only; labels stay on the dark control.
  Color get toolPlate => _litTint(
    adapt(const Color(0xFF6B5A57), colors.raised),
    adapt(const Color(0xFF89746A), colors.raised),
    controlOpacity,
  );
  Color get toolPlateSelected => _litTint(
    adapt(const Color(0xFF7A6260), colors.raised),
    adapt(const Color(0xFFA18A7E), colors.raised),
    selectedOpacity,
  );

  Color get line => colors.edge.withValues(alpha: .62 * effectStrength);
  Color get strongLine => colors.edge.withValues(alpha: .62 * effectStrength);
  Color get insetLine => colors.edge.withValues(alpha: .47 * effectStrength);
  Color get active => _litTint(
    adapt(
      const Color(0xFF51343D),
      Color.lerp(colors.surface, colors.accent, .20)!,
    ),
    adapt(
      const Color(0xFF63404A),
      Color.lerp(colors.surface, colors.accent, .20)!,
    ),
    selectedOpacity,
  );
  Color get hover => _litTint(
    adapt(
      const Color(0xFF46333D),
      Color.lerp(colors.raised, colors.accent, .10)!,
    ),
    adapt(
      const Color(0xFF5B414B),
      Color.lerp(colors.raised, colors.accent, .10)!,
    ),
    hoverOpacity,
  );
  Color get accentSelection => active;
  Color get accentSelectionSoft => active.withValues(alpha: active.a * .7);
  Color get popup => adapt(
    const Color(0xFF1B171E),
    colors.surface,
  ).withValues(alpha: math.max(.98, solidOpacity));

  /// Retain the actual Opportunities pigment. Material density is resolved
  /// once in fromPercent; inverse colour compensation would wash it out again.
  Color materialPigment(Color target, double opacity, {bool artwork = false}) {
    assert(opacity.isFinite && opacity >= 0 && opacity <= 1);
    return target.withValues(alpha: opacity);
  }

  /// Broad, smooth reflection within the existing face, not a translucent
  /// overlay. Preserve every original alpha stop and its gradient direction.
  LinearGradient polishedMaterialGradient(
    LinearGradient source, {
    bool accented = false,
  }) {
    final light = colors.brightness == Brightness.light;
    final rawTop = source.colors.first.withAlpha(255);
    final top = light ? Color.lerp(rawTop, colors.raised, .85)! : rawTop;
    final middle = source.colors.length > 2
        ? source.colors[1].withAlpha(255)
        : source.colors.last.withAlpha(255);
    final bottom = source.colors.length > 2
        ? source.colors.last.withAlpha(255)
        : colors.inset.withAlpha(255);
    final face = light
        ? [
            Color.lerp(top, Colors.white, .42)!,
            Color.lerp(top, Colors.white, .16)!,
            top,
            Color.lerp(middle, top, visualPalette == null ? .90 : .85)!,
          ]
        : [
            Color.alphaBlend(colors.ink.withAlpha(accented ? 8 : 20), top),
            Color.alphaBlend(colors.ink.withAlpha(accented ? 4 : 10), top),
            Color.lerp(middle, top, .48)!,
            Color.lerp(bottom, middle, .70)!,
          ];
    const faceStops = [0.0, .16, .55, 1.0];
    final sourceStops =
        source.stops ??
        [
          for (var i = 0; i < source.colors.length; i++)
            i / (source.colors.length - 1),
        ];
    final stops = {...sourceStops, ...faceStops}.toList()..sort();
    Color interpolate(
      List<Color> values,
      List<double> positions,
      double value,
    ) {
      for (var i = 1; i < positions.length; i++) {
        if (value <= positions[i]) {
          return Color.lerp(
            values[i - 1],
            values[i],
            (value - positions[i - 1]) / (positions[i] - positions[i - 1]),
          )!;
        }
      }
      return values.last;
    }

    return LinearGradient(
      begin: visualPalette == null ? source.begin : Alignment.topCenter,
      end: visualPalette == null ? source.end : Alignment.bottomCenter,
      stops: stops,
      tileMode: source.tileMode,
      transform: source.transform,
      colors: [
        for (final stop in stops)
          materialPigment(
            interpolate(face, faceStops, stop),
            interpolate(source.colors, sourceStops, stop).a,
          ),
      ],
    );
  }

  LinearGradient get surfaceGradient => polishedMaterialGradient(
    LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      stops: const [0, .52, 1],
      colors: [
        _litTint(
          adapt(const Color(0xFF3B3038), colors.raised),
          adapt(const Color(0xFF51404A), colors.raised),
          surfaceOpacity,
        ),
        _litTint(
          adapt(const Color(0xFF251F28), colors.surface),
          adapt(const Color(0xFF352B35), colors.surface),
          surfaceOpacity,
        ),
        _litTint(
          adapt(const Color(0xFF1C1820), colors.inset),
          adapt(const Color(0xFF2A232D), colors.inset),
          softOpacity,
        ),
      ],
    ),
  );

  /// A single fill plane with a satin artwork lane and optional inset actions.
  /// RGB changes by role; the existing full-face alpha envelope does not.
  Decoration segmentedDecoration(
    BoxDecoration base, {
    required double leadingWidth,
    double? leadingHeight,
    double trailingWidth = 0,
  }) {
    final source = base.gradient! as LinearGradient;
    final light = colors.brightness == Brightness.light;
    final metal = Color.lerp(
      colors.raised,
      colors.rim,
      light
          ? .30
          : visualPalette == null
          ? .68
          : .42,
    )!;
    const positions = [0.0, .14, .45, 1.0];
    final values = [
      Color.lerp(metal, colors.inset, .24)!,
      Color.lerp(
        metal,
        Colors.white,
        light
            ? .24
            : visualPalette == null
            ? .22
            : .12,
      )!,
      metal,
      Color.lerp(metal, colors.inset, light ? .34 : .49)!,
    ];
    final sourceStops =
        source.stops ??
        [
          for (var i = 0; i < source.colors.length; i++)
            i / (source.colors.length - 1),
        ];
    Color readColor(List<Color> colors, List<double> stops, double t) {
      for (var i = 1; i < stops.length; i++) {
        if (t <= stops[i]) {
          return Color.lerp(
            colors[i - 1],
            colors[i],
            (t - stops[i - 1]) / (stops[i] - stops[i - 1]),
          )!;
        }
      }
      return colors.last;
    }

    final stops = {...sourceStops, ...positions}.toList()..sort();
    return SegmentedGlassDecoration(
      base: base,
      leadingWidth: leadingWidth,
      leadingHeight: leadingHeight,
      trailingWidth: trailingWidth,
      bayLocalCoordinates: visualPalette != null,
      bayReliefStrength: visualPalette == null ? 0 : effectStrength,
      lightSurface: light,
      seam: colors.rim.withValues(alpha: .28 * effectStrength),
      bay: LinearGradient(
        begin: visualPalette == null ? source.begin : const Alignment(-1, -.45),
        end: visualPalette == null ? source.end : const Alignment(1, .80),
        stops: stops,
        colors: [
          for (final t in stops)
            materialPigment(
              readColor(values, positions, t),
              readColor(source.colors, sourceStops, t).a,
              artwork: true,
            ),
        ],
      ),
      actions: LinearGradient(
        begin: source.begin,
        end: source.end,
        stops: source.stops,
        colors: [
          for (final color in source.colors)
            Color.lerp(
              color.withAlpha(255),
              colors.inset,
              .22,
            )!.withValues(alpha: color.a),
        ],
      ),
    );
  }

  /// The approved copper card is opt-in. Ordinary controls and standalone
  /// surfaces retain their existing Opportunities/field-desk material.
  LinearGradient copperCardGradient({bool selected = false}) {
    final source = selected ? selectedGradient : controlGradient;
    if (visualPalette == null) return source;
    final r = colors.raised.withAlpha(255);
    final b = colors.surface.withAlpha(255);
    final i = colors.inset.withAlpha(255);
    final p = colors.accent.withAlpha(255);
    final a = colors.rim.withAlpha(255);
    final k = colors.ink.withAlpha(255);
    Color mix(Color first, Color second, double t) =>
        Color.lerp(first, second, t)!;
    final light = colors.brightness == Brightness.light;
    final values = light
        ? [
            mix(r, Colors.white, .34),
            mix(r, Colors.white, .12),
            r,
            mix(r, b, .15),
            mix(r, a, .10),
            mix(b, i, .18),
          ]
        : [
            mix(mix(r, p, .36), k, .12),
            mix(r, p, .26),
            mix(r, p, .15),
            mix(b, p, .12),
            mix(r, p, .24),
            mix(b, i, .24),
          ];
    const positions = [0.0, .12, .44, .76, .92, 1.0];
    final pigment = LinearGradient(colors: values, stops: positions);
    final stops = {..._materialStops(source), ...positions}.toList()..sort();
    return LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      stops: stops,
      colors: [
        for (final stop in stops)
          _materialAt(
            pigment,
            stop,
          ).withValues(alpha: _materialAt(source, stop).a),
      ],
    );
  }

  /// Broad metal/reflection colour is baked into one fill, never another
  /// opacity layer. Hover changes only this artwork material, not reading ink.
  LinearGradient copperBayGradient(
    LinearGradient source, {
    double reflection = .65,
  }) {
    final r = colors.raised.withAlpha(255);
    final b = colors.surface.withAlpha(255);
    final p = colors.accent.withAlpha(255);
    final a = colors.rim.withAlpha(255);
    Color mix(Color first, Color second, double t) =>
        Color.lerp(first, second, t)!;
    final warm = mix(a, const Color(0xFFFFDFB0), .60);
    final values = colors.brightness == Brightness.light
        ? [
            mix(r, a, .22),
            mix(a, r, .34),
            mix(a, warm, .45),
            mix(a, r, .24),
            mix(r, a, .48),
            mix(r, b, .20),
          ]
        : [
            mix(r, a, .30),
            mix(a, r, .10),
            mix(a, warm, .42),
            mix(a, r, .18),
            mix(a, r, .38),
            mix(r, p, .12),
          ];
    const positions = [0.0, .15, .35, .58, .77, 1.0];
    const reflectionStops = [0.0, .12, .31, .47, .74, 1.0];
    const reflectionAlphas = [0.0, .02, .62, .26, 0.0, 0.0];
    final pigment = LinearGradient(colors: values, stops: positions);
    final light = LinearGradient(
      colors: [
        for (final alpha in reflectionAlphas) warm.withValues(alpha: alpha),
      ],
      stops: reflectionStops,
    );
    final stops = {
      ..._materialStops(source),
      ...positions,
      ...reflectionStops,
    }.toList()..sort();
    return LinearGradient(
      begin: const Alignment(-.84, -1),
      end: const Alignment(.84, 1),
      stops: stops,
      colors: [
        for (final stop in stops)
          Color.alphaBlend(
            warm.withValues(
              alpha: _materialAt(light, stop).a * reflection.clamp(0.0, 1.0),
            ),
            _materialAt(pigment, stop),
          ).withValues(alpha: _materialAt(source, stop).a),
      ],
    );
  }

  Decoration copperCardDecoration(
    BoxDecoration base, {
    required double leadingWidth,
    double? leadingHeight,
    double trailingWidth = 0,
    double reflection = .65,
  }) {
    if (visualPalette == null) {
      return segmentedDecoration(
        base,
        leadingWidth: leadingWidth,
        leadingHeight: leadingHeight,
        trailingWidth: trailingWidth,
      );
    }
    final source = base.gradient! as LinearGradient;
    return SegmentedGlassDecoration(
      base: base,
      bay: copperBayGradient(source, reflection: reflection),
      actions: source,
      seam: colors.rim.withValues(alpha: .28 * effectStrength),
      leadingWidth: leadingWidth,
      leadingHeight: leadingHeight,
      trailingWidth: trailingWidth,
      bayLocalCoordinates: true,
      bayReliefStrength: effectStrength,
      lightSurface: colors.brightness == Brightness.light,
    );
  }

  static List<double> _materialStops(LinearGradient source) =>
      source.stops ??
      [
        for (var index = 0; index < source.colors.length; index++)
          index / (source.colors.length - 1),
      ];

  static Color _materialAt(LinearGradient source, double t) {
    final stops = _materialStops(source);
    for (var index = 1; index < stops.length; index++) {
      if (t <= stops[index]) {
        return Color.lerp(
          source.colors[index - 1],
          source.colors[index],
          (t - stops[index - 1]) / (stops[index] - stops[index - 1]),
        )!;
      }
    }
    return source.colors.last;
  }

  LinearGradient get headerGradient => visualPalette != null
      ? surfaceGradient
      : LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            _litTint(
              adapt(const Color(0xFF30262D), colors.raised),
              adapt(const Color(0xFF3A2F36), colors.raised),
              surfaceOpacity,
            ),
            _litTint(
              adapt(const Color(0xFF141117), colors.inset),
              adapt(const Color(0xFF1B161D), colors.inset),
              softOpacity,
            ),
          ],
        );

  LinearGradient get controlGradient => polishedMaterialGradient(
    LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [
        row,
        _litTint(
          adapt(const Color(0xFF201A23), colors.surface),
          adapt(const Color(0xFF2B222D), colors.surface),
          controlOpacity,
        ),
      ],
    ),
  );

  LinearGradient _hostedInteractionGradient(int tint, double opacity) {
    final normal = controlGradient;
    return LinearGradient(
      begin: normal.begin,
      end: normal.end,
      stops: normal.stops,
      colors: [
        for (final color in normal.colors)
          Color.alphaBlend(
            colors.accent.withAlpha(tint),
            color.withAlpha(255),
          ).withValues(alpha: opacity),
      ],
    );
  }

  LinearGradient get hoverGradient => visualPalette != null
      ? _hostedInteractionGradient(3, hoverOpacity)
      : polishedMaterialGradient(
          LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              hover,
              panel.withValues(alpha: controlOpacity),
            ],
          ),
          accented: true,
        );

  LinearGradient get selectedGradient => visualPalette != null
      ? _hostedInteractionGradient(8, selectedOpacity)
      : polishedMaterialGradient(
          LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              active,
              _litTint(
                adapt(
                  const Color(0xFF33242F),
                  Color.lerp(colors.surface, colors.accent, .20)!,
                ),
                adapt(
                  const Color(0xFF422D39),
                  Color.lerp(colors.surface, colors.accent, .20)!,
                ),
                selectedOpacity,
              ),
            ],
          ),
          accented: true,
        );

  /// Actions stay opaque, as before, so dark action text stays readable even
  /// when the surrounding glass is set to its minimum opacity.
  LinearGradient get primaryGradient => LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [colors.accent, colors.accentBright],
  );

  LinearGradient get groupGradient => LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [group, inset],
  );

  LinearGradient get iconWellGradient => LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    stops: const [0, .32, 1],
    colors: [
      Color.lerp(
        iconWell,
        colors.inset,
        .65,
      )!.withValues(alpha: controlOpacity),
      Color.lerp(
        iconWell,
        colors.inset,
        .80,
      )!.withValues(alpha: controlOpacity),
      iconWell,
    ],
  );

  LinearGradient get toolWellGradient => LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    stops: const [0, .32, 1],
    colors: [
      Color.lerp(
        toolPlate,
        colors.inset,
        .45,
      )!.withValues(alpha: controlOpacity),
      Color.lerp(
        toolPlate,
        colors.inset,
        .70,
      )!.withValues(alpha: controlOpacity),
      toolPlate,
    ],
  );

  RadialGradient artworkHighlight({bool tool = false}) => RadialGradient(
    center: const Alignment(0, .76),
    radius: .85,
    colors: [
      colors.rim.withValues(alpha: (tool ? .22 : .06) * effectStrength),
      colors.rim.withValues(alpha: 0),
    ],
    stops: const [0, 1],
  );

  /// Compatibility sheen is extremely subtle. Raised controls use edge-only
  /// glints instead, leaving their approved colored faces uncoated.
  LinearGradient get clearcoatGradient => LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    stops: const [0, .36, .72, 1],
    colors: [
      colors.rim.withValues(alpha: highlightOpacity * .035),
      colors.rim.withValues(alpha: highlightOpacity * .015),
      Colors.transparent,
      adapt(
        const Color(0xFF120F14),
        colors.inset,
      ).withValues(alpha: highlightOpacity * .18),
    ],
  );

  List<BoxShadow> get panelShadows => [
    BoxShadow(
      color: Colors.black.withValues(alpha: .33 * effectStrength),
      blurRadius: 26,
      offset: const Offset(0, 12),
    ),
    BoxShadow(
      color: Colors.black.withValues(alpha: softShadowOpacity),
      blurRadius: 3,
      offset: const Offset(0, 2),
    ),
  ];

  @override
  CompanionGlassTheme copyWith({
    int? opacityPercent,
    CompanionVisualPalette? visualPalette,
  }) => CompanionGlassTheme.fromPercent(
    opacityPercent ?? this.opacityPercent,
    visualPalette: visualPalette ?? this.visualPalette,
  );

  @override
  CompanionGlassTheme lerp(covariant CompanionGlassTheme? other, double t) =>
      CompanionGlassTheme.fromPercent(
        lerpDouble(
          opacityPercent.toDouble(),
          other?.opacityPercent.toDouble(),
          t,
        ),
        visualPalette: t < .5 ? visualPalette : other?.visualPalette,
      );
}

extension CompanionGlassContext on BuildContext {
  CompanionVisualPalette get gatheringColors => glass.colors;
  CompanionGlassTheme get glass =>
      Theme.of(this).extension<CompanionGlassTheme>() ??
      CompanionGlassTheme.fromPercent(defaultGlassOpacityPercent);
}

/// Mutually exclusive painted regions keep transparent cards transparent.
/// The shader coordinates remain the whole card in every region, so splitting
/// a face never restarts its alpha ramp or adds a second material fill.
@immutable
class SegmentedGlassDecoration extends Decoration {
  const SegmentedGlassDecoration({
    required this.base,
    required this.bay,
    required this.actions,
    required this.seam,
    required this.leadingWidth,
    this.leadingHeight,
    this.trailingWidth = 0,
    this.bayLocalCoordinates = false,
    this.bayReliefStrength = 0,
    this.lightSurface = false,
  });
  final BoxDecoration base;
  final LinearGradient bay, actions;
  final Color seam;
  final double leadingWidth, trailingWidth;
  final double? leadingHeight;
  final bool bayLocalCoordinates;
  final double bayReliefStrength;
  final bool lightSurface;

  @override
  EdgeInsetsGeometry get padding => base.padding;

  @override
  Path getClipPath(Rect rect, TextDirection textDirection) => Path()
    ..addRRect(
      (base.borderRadius ?? BorderRadius.zero)
          .resolve(textDirection)
          .toRRect(rect),
    );

  @override
  Decoration? lerpFrom(Decoration? a, double t) {
    if (a is! SegmentedGlassDecoration) return super.lerpFrom(a, t);
    return SegmentedGlassDecoration(
      base: BoxDecoration.lerp(a.base, base, t)!,
      bay: LinearGradient.lerp(a.bay, bay, t)!,
      actions: LinearGradient.lerp(a.actions, actions, t)!,
      seam: Color.lerp(a.seam, seam, t)!,
      leadingWidth: lerpDouble(a.leadingWidth, leadingWidth, t)!,
      leadingHeight: a.leadingHeight == null && leadingHeight == null
          ? null
          : lerpDouble(a.leadingHeight, leadingHeight, t),
      trailingWidth: lerpDouble(a.trailingWidth, trailingWidth, t)!,
      bayLocalCoordinates: t < .5 ? a.bayLocalCoordinates : bayLocalCoordinates,
      bayReliefStrength: lerpDouble(a.bayReliefStrength, bayReliefStrength, t)!,
      lightSurface: t < .5 ? a.lightSurface : lightSurface,
    );
  }

  @override
  Decoration? lerpTo(Decoration? b, double t) =>
      b is SegmentedGlassDecoration ? b.lerpFrom(this, t) : super.lerpTo(b, t);

  @override
  BoxPainter createBoxPainter([VoidCallback? onChanged]) =>
      _SegmentedGlassPainter(this, onChanged);

  @override
  bool operator ==(Object other) =>
      other is SegmentedGlassDecoration &&
      base == other.base &&
      bay == other.bay &&
      actions == other.actions &&
      seam == other.seam &&
      leadingWidth == other.leadingWidth &&
      leadingHeight == other.leadingHeight &&
      trailingWidth == other.trailingWidth &&
      bayLocalCoordinates == other.bayLocalCoordinates &&
      bayReliefStrength == other.bayReliefStrength &&
      lightSurface == other.lightSurface;

  @override
  int get hashCode => Object.hash(
    base,
    bay,
    actions,
    seam,
    leadingWidth,
    leadingHeight,
    trailingWidth,
    bayLocalCoordinates,
    bayReliefStrength,
    lightSurface,
  );
}

class _SegmentedGlassPainter extends BoxPainter {
  _SegmentedGlassPainter(this.decoration, super.onChanged);
  final SegmentedGlassDecoration decoration;

  @override
  void paint(Canvas canvas, Offset offset, ImageConfiguration configuration) {
    final size = configuration.size;
    if (size == null || size.isEmpty) return;
    final d = decoration;
    final area = offset & size;
    final direction = configuration.textDirection ?? TextDirection.ltr;
    final radius = (d.base.borderRadius ?? BorderRadius.zero).resolve(
      direction,
    );
    if (d.base.boxShadow?.isNotEmpty == true) {
      final shadow = BoxDecoration(
        borderRadius: radius,
        boxShadow: d.base.boxShadow,
      ).createBoxPainter();
      shadow.paint(canvas, offset, configuration);
      shadow.dispose();
    }
    final leading = d.leadingWidth.clamp(0.0, size.width);
    final trailing = d.trailingWidth.clamp(0.0, size.width - leading);
    final bayHeight = (d.leadingHeight ?? size.height).clamp(0.0, size.height);
    final bayRect = Rect.fromLTWH(area.left, area.top, leading, bayHeight);
    final actionRect = Rect.fromLTWH(
      area.right - trailing,
      area.top,
      trailing,
      size.height,
    );
    canvas.save();
    canvas.clipRRect(radius.toRRect(area));
    void fill(Rect clip, Gradient gradient, {bool localCoordinates = false}) {
      if (clip.isEmpty) return;
      canvas.save();
      canvas.clipRect(clip, doAntiAlias: false);
      canvas.drawRect(
        area,
        Paint()
          ..shader = gradient.createShader(
            localCoordinates ? clip : area,
            textDirection: direction,
          ),
      );
      canvas.restore();
    }

    fill(
      Rect.fromLTRB(
        area.left + leading,
        area.top,
        area.right - trailing,
        area.bottom,
      ),
      d.base.gradient!,
    );
    fill(
      Rect.fromLTRB(
        area.left,
        area.top + bayHeight,
        area.left + leading,
        area.bottom,
      ),
      d.base.gradient!,
    );
    if (leading > 0) {
      fill(bayRect, d.bay, localCoordinates: d.bayLocalCoordinates);
      if (d.bayReliefStrength > 0) {
        final strength = d.bayReliefStrength;
        final shadowSeam = Rect.fromLTWH(
          bayRect.right - 3,
          bayRect.top,
          3,
          bayRect.height,
        );
        canvas.drawRect(
          shadowSeam,
          Paint()
            ..shader = LinearGradient(
              colors: [
                Colors.transparent,
                Colors.black.withValues(
                  alpha: (d.lightSurface ? 48 : 110) / 255 * strength,
                ),
              ],
            ).createShader(shadowSeam),
        );
        if (leading > 36 && bayHeight > 16) {
          final ledge = Rect.fromLTWH(
            bayRect.left + 18,
            bayRect.bottom - 8,
            leading - 36,
            1,
          );
          canvas.drawRect(
            ledge,
            Paint()
              ..shader = LinearGradient(
                colors: [
                  d.seam.withValues(alpha: 0),
                  d.seam.withValues(alpha: 210 / 255 * strength),
                  d.seam.withValues(alpha: 0),
                ],
              ).createShader(ledge),
          );
        }
      }
    }
    if (trailing > 0) fill(actionRect, d.actions);
    final seam = Paint()
      ..color = d.seam
      ..strokeWidth = 1;
    if (leading > 0 && leading < size.width) {
      if (d.bayReliefStrength > 0) {
        seam.shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          stops: const [0, .5, 1],
          colors: [
            d.seam.withValues(alpha: 225 / 255 * d.bayReliefStrength),
            d.seam.withValues(alpha: 125 / 255 * d.bayReliefStrength),
            d.seam.withValues(alpha: 60 / 255 * d.bayReliefStrength),
          ],
        ).createShader(bayRect);
      }
      canvas.drawLine(bayRect.topRight, bayRect.bottomRight, seam);
      seam.shader = null;
    }
    if (trailing > 0) {
      canvas.drawLine(actionRect.topLeft, actionRect.bottomLeft, seam);
    }
    canvas.restore();
    if (d.base.border != null) {
      final border = BoxDecoration(
        borderRadius: radius,
        border: d.base.border,
      ).createBoxPainter();
      border.paint(canvas, offset, configuration);
      border.dispose();
    }
  }
}

BoxDecoration glassPanelDecoration({
  required CompanionGlassTheme glass,
  double radius = 12,
  bool elevated = false,
  Gradient? gradient,
}) => BoxDecoration(
  gradient: gradient ?? glass.surfaceGradient,
  borderRadius: BorderRadius.circular(radius),
  border: Border.all(color: glass.strongLine),
  boxShadow: elevated
      ? [
          BoxShadow(
            color: Colors.black.withValues(alpha: glass.deepShadowOpacity),
            blurRadius: 22,
            offset: const Offset(0, 9),
          ),
          BoxShadow(
            color: glass.colors.rim.withValues(
              alpha: glass.highlightOpacity * .55,
            ),
            blurRadius: 1,
            offset: const Offset(0, -1),
          ),
        ]
      : null,
);

/// A structural glass surface. Keep this around whole panels rather than small
/// repeated controls so the blur remains inexpensive and the icons stay crisp.
class GlassSurface extends StatelessWidget {
  const GlassSurface({
    super.key,
    required this.child,
    this.padding = EdgeInsets.zero,
    this.radius = 12,
    this.elevated = true,
    this.gradient,
    this.reading = false,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  final bool elevated;
  final Gradient? gradient;

  /// Dialogs keep their glass finish without letting map labels compete with
  /// the content. Ordinary map panels still follow the user's opacity slider.
  final bool reading;

  @override
  Widget build(BuildContext context) {
    if (reading) {
      return Theme(
        data: companionTheme(
          opacityPercent: math.max(96, context.glass.opacityPercent),
          visualPalette: context.glass.visualPalette,
        ),
        child: Builder(builder: _buildSurface),
      );
    }
    return _buildSurface(context);
  }

  Widget _buildSurface(BuildContext context) {
    final borderRadius = BorderRadius.circular(radius);
    final glass = context.glass;
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: borderRadius,
        boxShadow: elevated ? glass.panelShadows : null,
      ),
      child: ClipRRect(
        borderRadius: borderRadius,
        child: BackdropFilter(
          filter: ImageFilter.blur(
            sigmaX: glassBlurSigma,
            sigmaY: glassBlurSigma,
            tileMode: TileMode.clamp,
          ),
          child: DecoratedBox(
            decoration: glassPanelDecoration(
              glass: glass,
              radius: radius,
              gradient: gradient,
            ),
            child: CustomPaint(
              foregroundPainter: _GlassEdgePainter(
                radius,
                .48 * glass.effectStrength,
                rim: glass.colors.rim,
                bottomOpacity: .44 * glass.effectStrength,
                raised: true,
                lightSurface: glass.colors.brightness == Brightness.light,
              ),
              child: Padding(padding: padding, child: child),
            ),
          ),
        ),
      ),
    );
  }
}

/// A raised face without changing its child's layout or interaction contract.
/// The shared Material keeps InkWell feedback above the gradient, not below it.
class GlassControl extends StatefulWidget {
  const GlassControl({
    super.key,
    required this.child,
    this.selected = false,
    this.hovered = false,
    this.primary = false,
    this.radius = 9,
    this.leadingWidth,
    this.leadingHeight,
    this.trailingWidth = 0,
    this.copperInlay = false,
  });

  final Widget child;
  final bool selected;
  final bool hovered;
  final bool primary;
  final double radius;
  final double? leadingWidth, leadingHeight;
  final double trailingWidth;
  final bool copperInlay;

  @override
  State<GlassControl> createState() => _GlassControlState();
}

class _GlassControlState extends State<GlassControl> {
  bool _hover = false, _pressed = false, _focus = false;

  // Direct Material buttons expose their disabled state. Other children keep
  // ownership of action gating; this decorative wrapper never enables actions.
  bool get _feedbackEnabled => switch (widget.child) {
    ButtonStyleButton(:final onPressed, :final onLongPress) =>
      onPressed != null || onLongPress != null,
    IconButton(:final onPressed) => onPressed != null,
    _ => true,
  };

  @override
  Widget build(BuildContext context) {
    final glass = context.glass;
    final borderRadius = BorderRadius.circular(widget.radius);
    final selected = widget.selected;
    final hovered = _feedbackEnabled && (widget.hovered || _hover || _focus);
    final pressed = _feedbackEnabled && _pressed;
    final copper =
        widget.copperInlay &&
        glass.visualPalette != null &&
        widget.leadingWidth != null &&
        !widget.primary;
    final reducedMotion = MediaQuery.disableAnimationsOf(context);
    final duration = reducedMotion
        ? Duration.zero
        : Duration(milliseconds: copper ? 140 : 160);
    return Focus(
      canRequestFocus: false,
      onFocusChange: (value) => setState(() => _focus = value),
      child: MouseRegion(
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() {
          _hover = false;
          _pressed = false;
        }),
        child: Listener(
          onPointerDown: (event) {
            if (_feedbackEnabled && event.buttons == kPrimaryButton) {
              setState(() => _pressed = true);
            }
          },
          onPointerUp: (_) => setState(() => _pressed = false),
          onPointerCancel: (_) => setState(() => _pressed = false),
          child: TweenAnimationBuilder<double>(
            key: const ValueKey('glass-control-lift'),
            tween: Tween(
              begin: 0,
              end: hovered && !pressed && !reducedMotion && !copper ? -1 : 0,
            ),
            duration: duration,
            curve: Curves.easeOutCubic,
            builder: (context, lift, child) => Transform.translate(
              offset: Offset(0, lift),
              transformHitTests: false,
              child: child,
            ),
            child: AnimatedScale(
              scale: pressed && !reducedMotion && !copper ? .985 : 1,
              duration: duration,
              curve: Curves.easeOutCubic,
              child: AnimatedContainer(
                duration: duration,
                curve: Curves.easeOutCubic,
                decoration: _controlShadowDecoration(
                  exteriorOnly:
                      glass.visualPalette != null &&
                      widget.leadingWidth != null &&
                      !widget.primary,
                  borderRadius: borderRadius,
                  boxShadow: [
                    if ((hovered || selected) && !copper)
                      BoxShadow(
                        color: context.gatheringColors.accent.withValues(
                          alpha: _focus ? .18 : .07,
                        ),
                        blurRadius: hovered ? 16 : 9,
                        spreadRadius: _focus ? 1 : 0,
                      ),
                    if (glass.visualPalette != null) ...[
                      BoxShadow(
                        color: Colors.black.withValues(
                          alpha:
                              (glass.colors.brightness == Brightness.light
                                  ? 46
                                  : 140) /
                              255 *
                              glass.effectStrength,
                        ),
                        blurRadius: 2,
                        offset: const Offset(0, 3),
                      ),
                      BoxShadow(
                        color: Colors.black.withValues(
                          alpha:
                              (glass.colors.brightness == Brightness.light
                                  ? 28
                                  : 90) /
                              255 *
                              glass.effectStrength,
                        ),
                        blurRadius: 8,
                        offset: const Offset(0, 4),
                      ),
                    ] else
                      BoxShadow(
                        color: Colors.black.withValues(
                          alpha: (selected ? .47 : .33) * glass.effectStrength,
                        ),
                        blurRadius: selected ? 12 : 7,
                        offset: Offset(0, selected ? 5 : 3),
                      ),
                  ],
                ),
                child: Material(
                  color: Colors.transparent,
                  borderRadius: borderRadius,
                  clipBehavior: Clip.antiAlias,
                  child: _GlassControlInk(
                    selected: selected,
                    hovered: hovered,
                    pressed: pressed,
                    focused: _feedbackEnabled && _focus,
                    primary: widget.primary,
                    radius: widget.radius,
                    leadingWidth: widget.leadingWidth,
                    leadingHeight: widget.leadingHeight,
                    trailingWidth: widget.trailingWidth,
                    copperInlay: copper,
                    child: widget.child,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

BoxDecoration _controlShadowDecoration({
  required bool exteriorOnly,
  required BorderRadius borderRadius,
  required List<BoxShadow> boxShadow,
}) => exteriorOnly
    ? _GlassContactDecoration(borderRadius: borderRadius, boxShadow: boxShadow)
    : BoxDecoration(borderRadius: borderRadius, boxShadow: boxShadow);

/// Contact shadows belong outside the card. Filling beneath its translucent
/// body would silently add a black layer and change the selected material.
class _GlassContactDecoration extends BoxDecoration {
  const _GlassContactDecoration({
    required super.borderRadius,
    required super.boxShadow,
  });

  static _GlassContactDecoration _between(
    BoxDecoration? a,
    BoxDecoration? b,
    double t,
  ) {
    final result = BoxDecoration.lerp(a, b, t)!;
    return _GlassContactDecoration(
      borderRadius: result.borderRadius,
      boxShadow: result.boxShadow,
    );
  }

  @override
  BoxDecoration? lerpFrom(Decoration? a, double t) =>
      a == null || a is BoxDecoration
      ? _between(a as BoxDecoration?, this, t)
      : super.lerpFrom(a, t);

  @override
  BoxDecoration? lerpTo(Decoration? b, double t) =>
      b == null || b is BoxDecoration
      ? _between(this, b as BoxDecoration?, t)
      : super.lerpTo(b, t);

  @override
  BoxPainter createBoxPainter([VoidCallback? onChanged]) =>
      _GlassContactPainter(this, onChanged);
}

class _GlassContactPainter extends BoxPainter {
  _GlassContactPainter(this.decoration, VoidCallback? onChanged)
    : delegate = BoxDecoration(
        borderRadius: decoration.borderRadius,
        boxShadow: decoration.boxShadow,
      ).createBoxPainter(onChanged),
      super(onChanged);

  final _GlassContactDecoration decoration;
  final BoxPainter delegate;

  @override
  void paint(Canvas canvas, Offset offset, ImageConfiguration configuration) {
    final size = configuration.size;
    if (size == null || size.isEmpty) return;
    final bounds = offset & size;
    var extent = 0.0;
    for (final shadow in decoration.boxShadow ?? const <BoxShadow>[]) {
      extent = math.max(
        extent,
        shadow.blurSigma * 3 +
            shadow.spreadRadius.abs() +
            math.max(shadow.offset.dx.abs(), shadow.offset.dy.abs()) +
            1,
      );
    }
    final outside = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(bounds.inflate(extent))
      ..addRRect(
        decoration.borderRadius!
            .resolve(configuration.textDirection)
            .toRRect(bounds),
      );
    canvas.save();
    canvas.clipPath(outside);
    delegate.paint(canvas, offset, configuration);
    canvas.restore();
  }

  @override
  void dispose() {
    delegate.dispose();
    super.dispose();
  }
}

class _GlassControlInk extends StatelessWidget {
  const _GlassControlInk({
    required this.child,
    this.selected = false,
    this.hovered = false,
    this.pressed = false,
    this.focused = false,
    this.primary = false,
    this.radius = 9,
    this.leadingWidth,
    this.leadingHeight,
    this.trailingWidth = 0,
    this.copperInlay = false,
  });

  final Widget child;
  final bool selected;
  final bool hovered;
  final bool pressed;
  final bool focused;
  final bool primary;
  final double radius;
  final double? leadingWidth, leadingHeight;
  final double trailingWidth;
  final bool copperInlay;

  @override
  Widget build(BuildContext context) {
    final glass = context.glass;
    final raisedCard =
        glass.visualPalette != null && leadingWidth != null && !primary;
    final base = BoxDecoration(
      gradient: copperInlay
          ? glass.copperCardGradient(selected: selected)
          : primary
          ? glass.primaryGradient
          : selected
          ? glass.selectedGradient
          : hovered
          ? glass.hoverGradient
          : glass.controlGradient,
      borderRadius: BorderRadius.circular(radius),
    );
    final finish = leadingWidth == null
        ? base
        : copperInlay
        ? glass.copperCardDecoration(
            base,
            leadingWidth: leadingWidth!,
            leadingHeight: leadingHeight,
            trailingWidth: trailingWidth,
            reflection: hovered || focused ? .85 : .65,
          )
        : glass.segmentedDecoration(
            base,
            leadingWidth: leadingWidth!,
            leadingHeight: leadingHeight,
            trailingWidth: trailingWidth,
          );
    final duration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : Duration(milliseconds: copperInlay ? 140 : 160);
    Widget paintEdges(double highlight) => CustomPaint(
      foregroundPainter: _GlassEdgePainter(
        radius,
        copperInlay
            ? .84 * glass.effectStrength
            : raisedCard
            ? .96 * glass.effectStrength
            : primary
            ? .38
            : (selected ? .82 : .72) * glass.effectStrength,
        rim: glass.colors.rim,
        bottomOpacity:
            (primary ? .20 : (raisedCard ? .70 : .50)) * glass.effectStrength,
        raised: raisedCard,
        cardFinish: raisedCard,
        copperInlay: copperInlay,
        copperPressed: copperInlay && pressed,
        upperHighlight: copperInlay ? highlight : 0,
        lightSurface: glass.colors.brightness == Brightness.light,
        focusColor: focused ? context.gatheringColors.accent : null,
        borderColor: primary
            ? Color.lerp(
                context.gatheringColors.accent,
                context.gatheringColors.rim,
                .65,
              )!
            : selected
            ? context.gatheringColors.accent.withValues(
                alpha: .55 + .45 * glass.effectStrength,
              )
            : hovered && !copperInlay
            ? context.gatheringColors.rim.withValues(
                alpha: glass.effectStrength,
              )
            : glass.line,
      ),
      child: child,
    );
    return TweenAnimationBuilder<Decoration>(
      key: const ValueKey('glass-control-finish'),
      tween: DecorationTween(begin: finish, end: finish),
      duration: duration,
      curve: Curves.easeOutCubic,
      builder: (context, decoration, child) =>
          Ink(padding: EdgeInsets.zero, decoration: decoration, child: child),
      // Keep the child tree stable when a retained surface opts into/out of
      // copper. Ordinary controls keep a stationary zero-duration shell.
      child: TweenAnimationBuilder<double>(
        key: const ValueKey('copper-rim-highlight'),
        tween: Tween(
          begin: 0,
          end: copperInlay && (hovered || focused) ? 1 : 0,
        ),
        duration: copperInlay ? duration : Duration.zero,
        curve: Curves.easeOutCubic,
        builder: (context, highlight, _) => paintEdges(highlight),
      ),
    );
  }
}

/// A crisp artwork-only well. No opacity/filter is applied to the game asset.
class GlassArtworkWell extends StatelessWidget {
  const GlassArtworkWell({
    super.key,
    required this.child,
    this.tool = false,
    this.radius = 7,
  });

  final Widget child;
  final bool tool;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final glass = context.glass;
    final borderRadius = BorderRadius.circular(radius);
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: tool ? glass.toolWellGradient : glass.iconWellGradient,
        borderRadius: borderRadius,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: .33 * glass.effectStrength),
            blurRadius: 3,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: glass.artworkHighlight(tool: tool),
          borderRadius: borderRadius,
        ),
        child: CustomPaint(
          foregroundPainter: _GlassEdgePainter(
            radius,
            .28 * glass.effectStrength,
            rim: glass.colors.rim,
            bottomOpacity: .50 * glass.effectStrength,
            lightSurface: glass.colors.brightness == Brightness.light,
            inset: true,
          ),
          child: child,
        ),
      ),
    );
  }
}

/// Brief confirmation around changed read-only totals; never animates or
/// replaces editable text, and stays still when reduced motion is requested.
class ValueChangePulse extends StatefulWidget {
  const ValueChangePulse({super.key, required this.value, required this.child});
  final Object value;
  final Widget child;

  @override
  State<ValueChangePulse> createState() => _ValueChangePulseState();
}

class _ValueChangePulseState extends State<ValueChangePulse>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 650),
    value: 1,
  );

  @override
  void didUpdateWidget(ValueChangePulse oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.value != oldWidget.value) {
      if (MediaQuery.disableAnimationsOf(context)) {
        _pulse.value = 1;
      } else {
        _pulse.forward(from: 0);
      }
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) _pulse.value = 1;
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _pulse,
    child: widget.child,
    builder: (context, child) => DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(5),
        color: context.gatheringColors.accent.withValues(
          alpha: (1 - _pulse.value) * .18,
        ),
      ),
      child: child,
    ),
  );
}

/// Painted below text and artwork, and on the same Material as its ink response.
/// No extra backdrop filter per card or control.
class GlassSheen extends StatelessWidget {
  const GlassSheen({super.key, required this.child, this.radius = 10});

  final Widget child;
  final double radius;

  @override
  Widget build(BuildContext context) => Ink(
    decoration: BoxDecoration(
      gradient: context.glass.clearcoatGradient,
      borderRadius: BorderRadius.circular(radius),
    ),
    child: child,
  );
}

class _GlassEdgePainter extends CustomPainter {
  const _GlassEdgePainter(
    this.radius,
    this.opacity, {
    this.bottomOpacity = 0,
    this.borderColor,
    this.rim = _glassRim,
    this.focusColor,
    this.raised = false,
    this.cardFinish = false,
    this.copperInlay = false,
    this.copperPressed = false,
    this.upperHighlight = 0,
    this.lightSurface = false,
    this.inset = false,
  });

  final double radius;
  final double opacity;
  final double bottomOpacity;
  final Color? borderColor;
  final Color rim;
  final Color? focusColor;
  final bool raised;
  final bool cardFinish;
  final bool copperInlay;
  final bool copperPressed;
  final double upperHighlight;
  final bool lightSurface;
  final bool inset;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width < 8 || size.height < 8) return;
    if (focusColor case final color?) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          (Offset.zero & size).deflate(3),
          Radius.circular(math.max(0, radius - 3)),
        ),
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1,
      );
    }
    if (raised && cardFinish && !inset) {
      _paintCardEdge(canvas, size);
      return;
    }
    if (borderColor case final color?) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          (Offset.zero & size).deflate(.5),
          Radius.circular(radius),
        ),
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1,
      );
    }
    final area = Offset.zero & size;
    final shape = RRect.fromRectAndRadius(
      area.deflate(1),
      Radius.circular(math.max(0, radius - 1)),
    );
    final shade = bottomOpacity * (lightSurface ? .60 : 1);
    // Two opposed rounded cuts replace disconnected edge lines. The finish
    // stays within three pixels of the rim: no coating over labels or icons.
    canvas.drawRRect(
      shape,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = raised ? 1.5 : 1
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: inset
              ? [
                  Colors.black.withValues(alpha: shade),
                  rim.withValues(alpha: opacity * .10),
                  rim.withValues(alpha: opacity),
                ]
              : [
                  rim.withValues(alpha: opacity),
                  rim.withValues(alpha: opacity * .16),
                  Colors.black.withValues(alpha: shade),
                ],
          stops: const [0, .16, 1],
        ).createShader(area),
    );
    canvas.drawRRect(
      shape.deflate(1.5),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = .75
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            inset
                ? Colors.black.withValues(alpha: shade * .38)
                : rim.withValues(alpha: opacity * .40),
            Colors.transparent,
            inset
                ? rim.withValues(alpha: opacity * .28)
                : Colors.black.withValues(alpha: shade * .50),
          ],
          stops: const [0, .26, 1],
        ).createShader(area),
    );
  }

  void _paintCardEdge(Canvas canvas, Size size) {
    final area = (Offset.zero & size).deflate(.5);
    final shape = RRect.fromRectAndRadius(area, Radius.circular(radius));
    final shade =
        bottomOpacity * (lightSurface ? .60 : 1) * (copperPressed ? .55 : 1);
    final topLight = (opacity * (1 + upperHighlight / 7)).clamp(0.0, 1.0);
    final topColor = copperPressed
        ? Colors.black.withValues(alpha: bottomOpacity * .9)
        : rim.withValues(alpha: topLight);
    // A single lit shoulder falls quickly into quiet sides, then a dark lower
    // lip. There is no second bright rectangle around the reading content.
    canvas.drawRRect(
      shape,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            topColor,
            (borderColor ?? rim).withValues(
              alpha: (borderColor?.a ?? opacity) * .40,
            ),
            Colors.black.withValues(alpha: shade),
          ],
          stops: const [0, .12, 1],
        ).createShader(area),
    );
    canvas.save();
    canvas.clipRRect(shape.deflate(1));
    final shoulder = Rect.fromLTWH(1.5, 1.5, size.width - 3, 4);
    canvas.drawRect(
      shoulder,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            rim.withValues(alpha: opacity * .16),
            Colors.transparent,
          ],
        ).createShader(shoulder),
    );
    if (copperInlay) {
      // The five-pixel lower return makes the face read as a solid inset,
      // while the warm bounce stays below the text/artwork rather than
      // adding a second tint across the translucent reading surface.
      final lowerReturn = Rect.fromLTWH(
        1.5,
        size.height - 6.5,
        size.width - 3,
        5,
      );
      canvas.drawRect(
        lowerReturn,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              rim.withValues(alpha: opacity * (lightSurface ? .12 : .24)),
              Colors.black.withValues(alpha: shade * .38),
              Colors.black.withValues(alpha: shade * .92),
            ],
            stops: const [0, .24, 1],
          ).createShader(lowerReturn),
      );
    }
    canvas.restore();
    if (size.width > radius * 2 + 2) {
      canvas.drawLine(
        Offset(radius, .7),
        Offset(size.width - radius, .7),
        Paint()
          ..strokeWidth = 1
          ..shader = LinearGradient(
            colors: [
              topColor,
              (copperPressed ? Colors.black : Colors.white).withValues(
                alpha: topLight * .58,
              ),
              rim.withValues(alpha: opacity * .14),
            ],
            stops: const [0, .33, 1],
          ).createShader(area),
      );
    }
    canvas.drawRRect(
      shape.deflate(1.25),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            (copperPressed ? Colors.black : Colors.white).withValues(
              alpha: opacity * (lightSurface ? .50 : .28),
            ),
            Colors.transparent,
            Colors.black.withValues(alpha: shade * .80),
          ],
          stops: const [0, .16, 1],
        ).createShader(area),
    );
  }

  @override
  bool? hitTest(Offset position) => false;

  @override
  bool shouldRepaint(_GlassEdgePainter oldDelegate) =>
      oldDelegate.radius != radius ||
      oldDelegate.opacity != opacity ||
      oldDelegate.bottomOpacity != bottomOpacity ||
      oldDelegate.rim != rim ||
      oldDelegate.focusColor != focusColor ||
      oldDelegate.borderColor != borderColor ||
      oldDelegate.raised != raised ||
      oldDelegate.cardFinish != cardFinish ||
      oldDelegate.copperInlay != copperInlay ||
      oldDelegate.copperPressed != copperPressed ||
      oldDelegate.upperHighlight != upperHighlight ||
      oldDelegate.lightSurface != lightSurface ||
      oldDelegate.inset != inset;
}

class CompanionBackdrop extends StatelessWidget {
  const CompanionBackdrop({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => SizedBox.expand(
    child: DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          stops: [0, .72],
          colors: [
            context.gatheringColors.canvas,
            // Light ink needs a light desk behind labels outside cards. The
            // host's deep accent may intentionally be navy, not a text plane.
            context.gatheringColors.brightness == Brightness.light
                ? context.gatheringColors.surface
                : context.gatheringColors.canvasDeep,
          ],
        ),
      ),
      child: CustomPaint(
        // At near-clear settings the glow is directly behind text. Keep it
        // readable there without dulling the selected default appearance.
        painter: _BackdropDepthPainter(
          math.min(1.0, .78 + .22 * context.glass.surfaceOpacity / .6),
          context.gatheringColors,
        ),
        child: child,
      ),
    ),
  );
}

class _BackdropDepthPainter extends CustomPainter {
  const _BackdropDepthPainter(this.lightStrength, this.colors);

  final double lightStrength;
  final CompanionVisualPalette colors;

  Color _light(Color color) => color.withValues(alpha: color.a * lightStrength);

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;

    final firstLight = Rect.fromCircle(
      center: Offset(size.width * .13, 0),
      radius: size.longestSide * .46,
    );
    canvas.drawCircle(
      firstLight.center,
      firstLight.width / 2,
      Paint()
        ..shader = RadialGradient(
          stops: [0, 1],
          colors: [
            _light(colors.gold.withAlpha(0x20)),
            colors.gold.withAlpha(0),
          ],
        ).createShader(firstLight),
    );

    final secondLight = Rect.fromCircle(
      center: Offset(size.width * .90, 0),
      radius: size.longestSide * .40,
    );
    canvas.drawCircle(
      secondLight.center,
      secondLight.width / 2,
      Paint()
        ..shader = RadialGradient(
          stops: [0, 1],
          colors: [
            _light(colors.accent.withAlpha(0x18)),
            colors.accent.withAlpha(0),
          ],
        ).createShader(secondLight),
    );

    // Decorative contour engraving, not geographic data. The centre stays
    // quiet for the working panels; only the exposed edges carry linework.
    for (final origin in [
      Offset(size.width * 1.04, size.height * .22),
      Offset(-size.width * .14, size.height * .94),
    ]) {
      for (var ring = 0; ring < 19; ring++) {
        final path = Path();
        final radius = 70.0 + ring * 24;
        for (var step = 0; step <= 160; step++) {
          final angle = step / 160 * math.pi * 2;
          final ripple =
              math.sin(angle * 3 + ring * .16) * 15 +
              math.cos(angle * 5 - ring * .11) * 8;
          final point =
              origin +
              Offset(
                math.cos(angle) * (radius + ripple) * 1.18,
                math.sin(angle) * (radius + ripple) * .72,
              );
          if (step == 0) {
            path.moveTo(point.dx, point.dy);
          } else {
            path.lineTo(point.dx, point.dy);
          }
        }
        canvas.drawPath(
          path,
          Paint()
            ..color = colors.accent.withValues(
              alpha: (ring % 4 == 0 ? .065 : .026) * lightStrength,
            )
            ..style = PaintingStyle.stroke
            ..strokeWidth = ring % 4 == 0 ? 1 : .7,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_BackdropDepthPainter oldDelegate) =>
      lightStrength != oldDelegate.lightStrength ||
      colors != oldDelegate.colors;
}

Widget companionBackdropBuilder(BuildContext context, Widget? child) =>
    SizedBox.expand(
      child: Stack(
        fit: StackFit.expand,
        children: [
          const CompanionBackdrop(child: SizedBox.expand()),
          if (child != null) Positioned.fill(child: child),
        ],
      ),
    );

// Client item grades; colors checked against BDO Codex's grade frames.
Color? itemGradeColor(int? grade) => switch (grade) {
  0 => const Color(0xFFFFFFFF),
  1 => const Color(0xFF5FF369),
  2 => const Color(0xFF04B3F1),
  3 => const Color(0xFFF6C232),
  4 => const Color(0xFFFF7C00),
  5 => const Color(0xFFA070EF),
  _ => null,
};

ThemeData companionTheme({
  Object? opacityPercent,
  CompanionVisualPalette? visualPalette,
}) {
  final glass = CompanionGlassTheme.fromPercent(
    opacityPercent,
    visualPalette: visualPalette,
  );
  final colors = glass.colors;
  final ink = colors.ink,
      muted = colors.muted,
      accent = colors.accent,
      gold = colors.gold;
  return ThemeData(
    useMaterial3: true,
    brightness: colors.brightness,
    scaffoldBackgroundColor: Colors.transparent,
    fontFamily: 'Segoe UI',
    colorScheme: ColorScheme.fromSeed(
      seedColor: accent,
      brightness: colors.brightness,
      primary: accent,
      onPrimary: visualPalette == null
          ? const Color(0xFF22191C)
          : colors.onAccent,
      secondary: gold,
      surface: glass.panel,
      onSurface: ink,
      error: colors.danger,
      shadow: Colors.black.withValues(alpha: glass.shadowOpacity),
    ),
    shadowColor: Colors.black.withValues(alpha: glass.shadowOpacity),
    textTheme: TextTheme(
      headlineLarge: TextStyle(
        fontFamily: 'Georgia',
        fontSize: 32,
        fontWeight: FontWeight.w700,
        letterSpacing: -.7,
        color: ink,
      ),
      headlineSmall: TextStyle(
        fontFamily: 'Georgia',
        fontSize: 22,
        fontWeight: FontWeight.w600,
        color: ink,
      ),
      titleLarge: TextStyle(
        fontSize: 20,
        fontWeight: FontWeight.w700,
        color: ink,
      ),
      titleMedium: TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w600,
        color: ink,
      ),
      bodyLarge: TextStyle(fontSize: 15, height: 1.45, color: ink),
      bodyMedium: TextStyle(fontSize: 14, height: 1.4, color: ink),
      bodySmall: TextStyle(fontSize: 14, height: 1.4, color: muted),
    ),
    tooltipTheme: TooltipThemeData(
      waitDuration: const Duration(milliseconds: 300),
      textStyle: TextStyle(fontSize: 14, height: 1.4, color: ink),
      textAlign: TextAlign.left,
      constraints: const BoxConstraints(maxWidth: 360),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: glass.popup,
        border: Border.all(color: colors.edge.withValues(alpha: .7)),
        borderRadius: BorderRadius.circular(8),
        boxShadow: const [
          BoxShadow(
            color: Color(0x66000000),
            blurRadius: 16,
            offset: Offset(0, 6),
          ),
        ],
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: glass.inset,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 15),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: glass.line),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: glass.line),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: accent, width: 1.5),
      ),
    ),
    dividerColor: glass.line,
    dividerTheme: DividerThemeData(color: glass.line, thickness: 1),
    cardTheme: CardThemeData(
      color: glass.panel,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: glass.strongLine),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: glass.popup,
      barrierColor: Colors.black.withValues(alpha: glass.backdropOpacity),
      surfaceTintColor: Colors.transparent,
    ),
    popupMenuTheme: PopupMenuThemeData(
      // Menus are reading surfaces, not part of the transparent map chrome.
      color: glass.popup,
      surfaceTintColor: Colors.transparent,
      shadowColor: const Color(0x66000000),
      elevation: 8,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: colors.edge.withValues(alpha: .7)),
      ),
      menuPadding: const EdgeInsets.symmetric(vertical: 6),
      textStyle: TextStyle(fontSize: 14, height: 1.35, color: ink),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 17),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        backgroundBuilder: (context, states, child) =>
            states.contains(WidgetState.disabled)
            ? child ?? const SizedBox.shrink()
            : _GlassControlInk(
                primary: true,
                radius: 10,
                child: child ?? const SizedBox.shrink(),
              ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: ink,
        side: BorderSide(color: glass.line),
        padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 15),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    ),
    chipTheme: ChipThemeData(
      side: BorderSide(color: glass.line),
      backgroundColor: glass.row,
      selectedColor: glass.active,
      labelStyle: TextStyle(color: ink),
      secondaryLabelStyle: TextStyle(color: ink),
      checkmarkColor: accent,
    ),
    scrollbarTheme: const ScrollbarThemeData(
      thumbVisibility: WidgetStatePropertyAll(false),
      trackVisibility: WidgetStatePropertyAll(false),
    ),
    extensions: [glass],
  );
}

class GameIcon extends StatelessWidget {
  const GameIcon(
    this.path, {
    super.key,
    this.size = 36,
    this.grade,
    this.backgroundColor,
    this.recessed = false,
  });
  final String path;
  final double size;
  final int? grade;
  final Color? backgroundColor;

  /// Paint-only mount for the compact hosted spot cards; artwork stays intact.
  final bool recessed;
  @override
  Widget build(BuildContext context) {
    final resolvedPath = gatheringItemArtwork(path);
    final resolvedGrade = grade ?? gatheringItemGrade(path);
    final isItem = resolvedPath != path || grade != null;
    final radius = BorderRadius.circular(
      isItem ? (size * .12).clamp(3.0, 7.0) : 7,
    );
    final artwork = path.isEmpty
        ? const SizedBox.shrink()
        : Padding(
            padding: EdgeInsets.all(isItem && size < 32 ? 1.5 : 2),
            child: Image.asset(
              resolvedPath,
              package: gatheringAssetPackage,
              fit: BoxFit.contain,
              filterQuality: FilterQuality.medium,
              errorBuilder: (_, error, stack) => Tooltip(
                message: 'Game artwork unavailable',
                child: Center(
                  child: Text(
                    '?',
                    style: TextStyle(
                      color: context.gatheringColors.muted,
                      fontSize: size * .45,
                    ),
                  ),
                ),
              ),
            ),
          );
    return Container(
      width: size,
      height: size,
      clipBehavior: isItem ? Clip.antiAlias : Clip.none,
      decoration: BoxDecoration(
        color: backgroundColor,
        gradient: backgroundColor == null
            ? context.glass.iconWellGradient
            : null,
        borderRadius: radius,
      ),
      foregroundDecoration: switch (itemGradeColor(resolvedGrade)) {
        final color? => BoxDecoration(
          border: Border.all(
            color: color.withAlpha(resolvedGrade == 0 ? 125 : 210),
            width: size >= 36 ? 1.2 : 1,
          ),
          borderRadius: radius,
        ),
        null => null,
      },
      child: recessed && context.glass.visualPalette != null
          ? CustomPaint(
              key: const ValueKey('gathering-recessed-icon-well'),
              foregroundPainter: _GlassIconWellPainter(
                radius.topLeft.x,
                context.gatheringColors.rim,
                context.glass.effectStrength,
                context.gatheringColors.brightness == Brightness.light,
              ),
              child: artwork,
            )
          : isItem || backgroundColor != null
          ? artwork
          : DecoratedBox(
              decoration: BoxDecoration(
                gradient: context.glass.artworkHighlight(),
                borderRadius: BorderRadius.circular(7),
              ),
              child: CustomPaint(
                foregroundPainter: _GlassEdgePainter(
                  7,
                  .13 * context.glass.effectStrength,
                  rim: context.gatheringColors.rim,
                  bottomOpacity: .5 * context.glass.effectStrength,
                  lightSurface:
                      context.gatheringColors.brightness == Brightness.light,
                  inset: true,
                ),
                child: artwork,
              ),
            ),
    );
  }
}

/// Opposed inset edges inside the original icon bounds, with no blur or new
/// surface fill. Grade borders are still painted by GameIcon above this mount.
class _GlassIconWellPainter extends CustomPainter {
  const _GlassIconWellPainter(this.radius, this.rim, this.strength, this.light);
  final double radius, strength;
  final Color rim;
  final bool light;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.shortestSide < 8) return;
    final area = (Offset.zero & size).deflate(.75);
    final shape = RRect.fromRectAndRadius(area, Radius.circular(radius));
    canvas.drawRRect(
      shape,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.black.withValues(alpha: (light ? .50 : .85) * strength),
            rim.withValues(alpha: .16 * strength),
            rim.withValues(alpha: .72 * strength),
          ],
          stops: const [0, .50, 1],
        ).createShader(area),
    );
    canvas.drawRRect(
      shape.deflate(1.5),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.black.withValues(alpha: (light ? .24 : .55) * strength),
            Colors.transparent,
            rim.withValues(alpha: .18 * strength),
          ],
          stops: const [0, .22, 1],
        ).createShader(area),
    );
  }

  @override
  bool? hitTest(Offset position) => false;

  @override
  bool shouldRepaint(_GlassIconWellPainter oldDelegate) =>
      radius != oldDelegate.radius ||
      rim != oldDelegate.rim ||
      strength != oldDelegate.strength ||
      light != oldDelegate.light;
}

class SectionCard extends StatelessWidget {
  const SectionCard({
    super.key,
    required this.title,
    this.subtitle,
    required this.child,
    this.trailing,
  });
  final String title;
  final String? subtitle;
  final Widget child;
  final Widget? trailing;
  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              ?trailing,
            ],
          ),
          if (subtitle != null)
            Padding(
              padding: const EdgeInsets.only(top: 5),
              child: Text(
                subtitle!,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          const SizedBox(height: 16),
          child,
        ],
      ),
    ),
  );
}

String countText(num n) => n.toInt().toString().replaceAllMapped(
  RegExp(r'(\d)(?=(\d{3})+(?!\d))'),
  (m) => '${m[1]},',
);
String numberText(num n) =>
    n == n.roundToDouble() ? n.toInt().toString() : n.toStringAsFixed(1);
String formatDurationMinutes(num minutes) => minutes.isFinite && minutes >= 0
    ? durationText((minutes * 60).round())
    : '—';

String durationText(int seconds) {
  if (seconds <= 0) return '0 s';
  final days = seconds ~/ 86400;
  final hours = seconds % 86400 ~/ 3600;
  final minutes = seconds % 3600 ~/ 60;
  final remainder = seconds % 60;
  return [
    if (days > 0) '$days ${days == 1 ? 'day' : 'days'}',
    if (hours > 0) '$hours h',
    if (minutes > 0) '$minutes min',
    if (remainder > 0) '$remainder s',
  ].join(' ');
}
