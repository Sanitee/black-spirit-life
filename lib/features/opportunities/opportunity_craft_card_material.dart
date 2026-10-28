import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../domain/opportunities/opportunity_card_reading.dart';
import '../../visual/visual.dart';
import 'opportunities_visuals.dart';
import 'opportunity_glass_finish.dart';

/// Crafting-only status material. Availability never changes the profit colour.
/// The broad wash covers the reading face without increasing its intensity.
class OpportunityCraftCardMaterial {
  OpportunityCraftCardMaterial._(this.spec, this.tone);

  static final _cache =
      Expando<Map<OpportunityStockTone, OpportunityCraftCardMaterial>>();
  static OpportunityCraftCardMaterial forSpec(
    ThemeSpec spec,
    OpportunityStockTone tone,
  ) => (_cache[spec] ??= {}).putIfAbsent(
    tone,
    () => OpportunityCraftCardMaterial._(spec, tone),
  );

  final ThemeSpec spec;
  final OpportunityStockTone tone;
  bool get light => spec.brightness == Brightness.light;

  // Explicit semantic hues keep green/red/orange recognisable even in themes
  // whose generic success/warning colours are deliberately desaturated.
  late final Color bay = switch (tone) {
    OpportunityStockTone.available => const Color(0xFF416C50),
    OpportunityStockTone.outOfStock => const Color(0xFF7D4858),
    OpportunityStockTone.mixed => const Color(0xFF8A603E),
    OpportunityStockTone.unknown => Color.lerp(
      spec.palette.trim,
      spec.palette.surface,
      .35,
    )!,
  };
  late final Color glow = switch (tone) {
    OpportunityStockTone.available => const Color(0xFF9ED6AC),
    OpportunityStockTone.outOfStock => const Color(0xFFE9A7B5),
    OpportunityStockTone.mixed => const Color(0xFFF2C38A),
    OpportunityStockTone.unknown => spec.palette.textMuted,
  };
  Color get wash => light ? bay : glow;
  double get washOpacity => light ? .12 : .24;
  late final LinearGradient headerWash = LinearGradient(
    begin: Alignment.bottomCenter,
    end: Alignment.topCenter,
    colors: [
      wash.withValues(alpha: washOpacity),
      wash.withValues(alpha: washOpacity * (10 / 24)),
      wash.withValues(alpha: 0),
    ],
    stops: const [0, .48, .96],
  );
  late final List<Color> readingSurfaces = [
    for (final base in OpportunityGlassFinish.forSpec(spec).cardSurface.colors)
      for (final opacity in [0.0, washOpacity * (10 / 24), washOpacity])
        Color.alphaBlend(wash.withValues(alpha: opacity), base),
  ];
  late final Color badgeFill = (light ? bay : glow).withValues(alpha: .07);
  late final Color badgeInk = readable(light ? bay : glow, badge: true);
  late final Color mutedInk = readable(spec.palette.textMuted);
  late final Color lossInk = readable(
    OpportunitiesVisualSpec.readableValueColor(spec, spec.palette.danger),
  );
  Color get border =>
      Color.lerp(spec.palette.trimBright, light ? bay : glow, .45)!;

  Color readable(Color original, {bool badge = false}) {
    final backgrounds = badge
        ? readingSurfaces.map((base) => Color.alphaBlend(badgeFill, base))
        : readingSurfaces;
    final luminances = backgrounds.map((c) => c.computeLuminance()).toList();
    bool passes(Color color) {
      final value = color.computeLuminance();
      return luminances.every(
        (base) =>
            (math.max(value, base) + .05) / (math.min(value, base) + .05) >=
            4.5,
      );
    }

    if (passes(original)) return original;
    final end = light ? Colors.black : Colors.white;
    for (var step = 1; step <= 20; step++) {
      final candidate = Color.lerp(original, end, step / 20)!;
      if (passes(candidate)) return candidate;
    }
    return end;
  }
}
