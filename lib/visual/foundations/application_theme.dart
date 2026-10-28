import 'package:flutter/material.dart';

import '../../domain/state/planner_state.dart';
import '../standard/standard_spec.dart';
import 'theme_registry.dart';
import 'theme_spec.dart';

/// Shared appearance colours for feature workspaces that retain their own
/// layout. Planner keeps its original full component and backdrop rendering.
ThemeSpec applicationThemeForAppearance(AppearanceSettings appearance) {
  final base = RetainedThemeRegistry.resolve(
    backgroundId: appearance.background,
  );
  if (!base.isStandard) return base;
  final hue = appearance.accentHue.isFinite
      ? ((appearance.accentHue % 360) + 360) % 360
      : 158.0;
  final key = (appearance.background, hue, appearance.neon);
  if (_sceneThemes[key] case final cached?) return cached;
  final plain = StandardSpec.plainBackgrounds[appearance.background];
  final surface = plain == null
      ? StandardSpec.plannerCardFill(
          appearance.background,
          AppSurfaceTone.neutral,
        ).withAlpha(255)
      : Color.lerp(plain.left, plain.right, .22)!.withAlpha(255);
  final accent = StandardSpec.accentBrush(hue, neon: appearance.neon);
  final raised = Color.lerp(surface, accent, .13)!;
  final inset = Color.lerp(surface, Colors.black, .38)!;
  final canvas = Color.lerp(surface, Colors.black, .65)!;
  final palette = ThemePalette(
    canvas: canvas,
    canvasDeep: Color.lerp(canvas, Colors.black, .35)!,
    surface: surface,
    surfaceRaised: raised,
    surfaceInset: inset,
    primary: accent,
    primaryBright: Color.lerp(accent, base.palette.text, .35)!,
    secondary: base.palette.secondary,
    trim: Color.lerp(surface, accent, .42)!,
    trimBright: Color.lerp(accent, base.palette.text, .45)!,
    text: base.palette.text,
    textMuted: Color.lerp(base.palette.textMuted, accent, .10)!,
    success: base.palette.success,
    warning: base.palette.warning,
    danger: base.palette.danger,
    shadow: base.palette.shadow,
    specular: base.palette.specular,
  );
  final result = ThemeSpec(
    id: 'application-standard-${appearance.background}-${accent.toARGB32()}',
    displayName: base.displayName,
    family: base.family,
    layoutProfile: base.layoutProfile,
    brightness: base.brightness,
    palette: palette,
    typography: base.typography,
    geometry: base.geometry,
    materials: ThemeMaterials(
      canvas: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [canvas, palette.canvasDeep],
      ),
      surface: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [raised, surface],
      ),
      surfaceRaised: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [raised, surface, inset],
      ),
      primary: LinearGradient(colors: [palette.primaryBright, accent]),
      secondary: LinearGradient(colors: [raised, surface]),
      modalScrim: base.materials.modalScrim,
      lowShadow: base.materials.lowShadow,
      highShadow: base.materials.highShadow,
    ),
    motion: base.motion,
  );
  // Appearance sliders must not accumulate an unbounded theme cache.
  if (_sceneThemes.length >= 16) _sceneThemes.remove(_sceneThemes.keys.first);
  _sceneThemes[key] = result;
  return result;
}

final _sceneThemes = <(String, double, bool), ThemeSpec>{};
