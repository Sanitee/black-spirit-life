import 'package:flutter/material.dart';

import '../../visual/visual.dart';

/// Static, opaque reading planes with baked-in light. No backdrop filters or
/// continuous effects: scrolling cards only paint a few gradients and borders.
@immutable
class OpportunityGlassFinish {
  const OpportunityGlassFinish({
    required this.key,
    required this.name,
    required this.top,
    required this.middle,
    required this.bottom,
    required this.canvas,
    required this.light,
    required this.coolLight,
    required this.accent,
    required this.text,
    required this.muted,
    required this.edge,
    required this.railLight,
  });

  static const bronze = OpportunityGlassFinish(
    key: 'bronze',
    name: 'Rosewood & brass',
    top: Color(0xFF3A2D35),
    middle: Color(0xFF28222C),
    bottom: Color(0xFF201D25),
    canvas: Color(0xFF141218),
    light: Color(0x32C88D91),
    coolLight: Color(0x184B445E),
    accent: Color(0xFFC6A06B),
    text: Color(0xFFF1E8D8),
    muted: Color(0xFFB9ABB1),
    edge: Color(0xFF7E6268),
    railLight: Color(0xFFC88D91),
  );
  static const moon = OpportunityGlassFinish(
    key: 'moon',
    name: 'Midnight & silver',
    top: Color(0xFF303342),
    middle: Color(0xFF232733),
    bottom: Color(0xFF1A1E29),
    canvas: Color(0xFF12141B),
    light: Color(0x329DA7CB),
    coolLight: Color(0x184A6A87),
    accent: Color(0xFFADBBD7),
    text: Color(0xFFF0ECDF),
    muted: Color(0xFFADB3C3),
    edge: Color(0xFF626B84),
    railLight: Color(0xFFA6B1CE),
  );
  static const values = [bronze, moon];
  static OpportunityGlassFinish fromKey(String key) =>
      key == 'moon' ? moon : bronze;
  static final _appearanceFinishes = Expando<OpportunityGlassFinish>();
  static OpportunityGlassFinish of(BuildContext context) {
    final spec = ThemeSpecScope.maybeOf(context);
    if (spec == null) return bronze;
    return forSpec(spec);
  }

  static OpportunityGlassFinish forSpec(ThemeSpec spec) {
    if (!spec.id.startsWith('opportunities-smoked-glass-appearance-')) {
      return spec.id.endsWith('-moon') ? moon : bronze;
    }
    final p = spec.palette;
    return _appearanceFinishes[spec] ??= OpportunityGlassFinish(
      key: spec.id,
      name: spec.displayName,
      top: p.surfaceRaised,
      middle: p.surface,
      bottom: p.surfaceInset,
      canvas: p.canvas,
      light: p.primary.withAlpha(40),
      coolLight: p.secondary.withAlpha(20),
      accent: p.primaryBright,
      text: p.text,
      muted: p.textMuted,
      edge: p.trim,
      railLight: p.trimBright,
    );
  }

  final String key, name;
  final Color top, middle, bottom, canvas, light, coolLight;
  final Color accent, text, muted, edge, railLight;
  bool get lightSurface => middle.computeLuminance() > .4;

  LinearGradient get surface => LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      lightSurface
          ? Color.lerp(top, Colors.white, .28)!
          : Color.alphaBlend(accent.withAlpha(18), top),
      top,
      middle,
      bottom,
    ],
    stops: const [0, .12, .48, 1],
  );
  LinearGradient get overlay => LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color.lerp(top, middle, .65)!, bottom],
  );

  // Cards sit above the desk. Keep the entire reading plane opaque, with a
  // broad satin shoulder rather than a bright reflection crossing the text.
  LinearGradient get cardSurface => LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: lightSurface
        ? [
            Color.lerp(top, Colors.white, .42)!,
            Color.lerp(top, Colors.white, .16)!,
            top,
            Color.lerp(middle, top, .85)!,
          ]
        : [
            Color.alphaBlend(text.withAlpha(20), top),
            Color.alphaBlend(text.withAlpha(10), top),
            Color.lerp(middle, top, .48)!,
            Color.lerp(bottom, middle, .70)!,
          ],
    stops: const [0, .16, .55, 1],
  );

  BoxShadow get contactShadow => BoxShadow(
    color: Colors.black.withAlpha(lightSurface ? 46 : 140),
    blurRadius: 2,
    offset: const Offset(0, 3),
  );

  BoxDecoration get card => BoxDecoration(
    gradient: cardSurface,
    borderRadius: BorderRadius.circular(8),
    border: Border.all(color: edge.withAlpha(165)),
    boxShadow: [
      // A tight contact shadow plus a soft cast shadow, as in the approved
      // material study. These are static; no backdrop filtering is involved.
      contactShadow,
      BoxShadow(
        color: Colors.black.withAlpha(lightSurface ? 28 : 90),
        blurRadius: 8,
        offset: const Offset(0, 4),
      ),
    ],
  );
  BoxDecoration get rail => BoxDecoration(
    gradient: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [
        railLight.withAlpha(125),
        top.withAlpha(125),
        bottom.withAlpha(75),
      ],
      stops: const [0, .42, 1],
    ),
    border: Border(right: BorderSide(color: accent.withAlpha(38))),
  );
  BoxDecoration get footer => BoxDecoration(
    gradient: LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: lightSurface
          ? const [Color(0x10FFFFFF), Color(0x28FFFFFF)]
          : const [Color(0x14000000), Color(0x48000000)],
    ),
    border: Border(top: BorderSide(color: accent.withAlpha(38))),
  );

  ThemeSpec theme(ThemeSpec base) {
    final p = ThemePalette(
      canvas: canvas,
      canvasDeep: Color.lerp(canvas, Colors.black, .22)!,
      surface: middle,
      surfaceRaised: Color.lerp(top, middle, .65)!,
      surfaceInset: bottom,
      primary: accent,
      primaryBright: accent,
      secondary: railLight,
      trim: edge,
      trimBright: accent,
      text: text,
      textMuted: muted,
      success: const Color(0xFF8EB79C),
      warning: const Color(0xFFEDC38C),
      danger: const Color(0xFFEB978A),
      shadow: const Color(0x99000000),
      specular: accent.withAlpha(80),
    );
    final t = base.typography;
    return ThemeSpec(
      id: 'opportunities-smoked-glass-$key',
      displayName: name,
      family: base.family,
      layoutProfile: base.layoutProfile,
      brightness: Brightness.dark,
      palette: p,
      geometry: base.geometry,
      typography: ThemeTypography(
        display: t.display.copyWith(color: text),
        section: t.section.copyWith(color: text),
        body: t.body.copyWith(color: text),
        meta: t.meta.copyWith(color: muted),
        label: t.label.copyWith(color: muted),
        button: t.button.copyWith(color: text),
      ),
      materials: ThemeMaterials(
        canvas: LinearGradient(colors: [canvas, p.canvasDeep]),
        surface: surface,
        surfaceRaised: overlay,
        primary: surface,
        secondary: overlay,
        modalScrim: base.materials.modalScrim,
        lowShadow: card.boxShadow!,
        highShadow: base.materials.highShadow,
      ),
      motion: base.motion,
    );
  }
}
