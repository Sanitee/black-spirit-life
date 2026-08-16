import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../foundations/theme_spec.dart';

enum StandardBackdropFamily { atmospheric, plain }

@immutable
final class StandardSceneSpec {
  const StandardSceneSpec({
    required this.id,
    required this.displayName,
    required this.assetPath,
    required this.defaultParticleId,
    required this.accentHue,
    this.contrastStrength = 0.1,
  });

  final String id;
  final String displayName;
  final String assetPath;
  final String defaultParticleId;
  final double accentHue;
  final double contrastStrength;
}

@immutable
final class StandardPlainSpec {
  const StandardPlainSpec({
    required this.id,
    required this.displayName,
    required this.left,
    required this.right,
  });

  final String id;
  final String displayName;
  final Color left;
  final Color right;

  LinearGradient get gradient => LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: <Color>[left, const Color.fromARGB(154, 2, 7, 8), right],
    stops: const <double>[0, 0.55, 1],
  );
}

@immutable
final class StandardBackdropSelection {
  const StandardBackdropSelection._({
    required this.id,
    required this.family,
    this.scene,
    this.plain,
  });

  factory StandardBackdropSelection.scene(StandardSceneSpec scene) =>
      StandardBackdropSelection._(
        id: scene.id,
        family: StandardBackdropFamily.atmospheric,
        scene: scene,
      );

  factory StandardBackdropSelection.plain(StandardPlainSpec plain) =>
      StandardBackdropSelection._(
        id: plain.id,
        family: StandardBackdropFamily.plain,
        plain: plain,
      );

  final String id;
  final StandardBackdropFamily family;
  final StandardSceneSpec? scene;
  final StandardPlainSpec? plain;
}

/// Live Standard appearance values that cannot be represented by the retained
/// [ThemeSpec] singleton alone. The scope lets semantic components resolve the
/// active scene material without learning about feature or persistence state.
@immutable
final class StandardVisualSettings {
  const StandardVisualSettings({
    this.backgroundId = StandardSpec.defaultBackgroundId,
    this.accentHue = 158,
    this.rainbow = false,
    this.neon = false,
  });

  static const StandardVisualSettings fallback = StandardVisualSettings();

  final String backgroundId;
  final double accentHue;
  final bool rainbow;
  final bool neon;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is StandardVisualSettings &&
          other.backgroundId == backgroundId &&
          other.accentHue == accentHue &&
          other.rainbow == rainbow &&
          other.neon == neon;

  @override
  int get hashCode => Object.hash(backgroundId, accentHue, rainbow, neon);
}

class StandardVisualScope extends InheritedTheme {
  const StandardVisualScope({
    required this.settings,
    required super.child,
    super.key,
  });

  final StandardVisualSettings settings;

  static StandardVisualSettings of(BuildContext context) =>
      maybeOf(context) ?? StandardVisualSettings.fallback;

  static StandardVisualSettings? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<StandardVisualScope>()
      ?.settings;

  @override
  Widget wrap(BuildContext context, Widget child) =>
      StandardVisualScope(settings: settings, child: child);

  @override
  bool updateShouldNotify(StandardVisualScope oldWidget) =>
      oldWidget.settings != settings;
}

extension StandardVisualContext on BuildContext {
  StandardVisualSettings get standardVisual => StandardVisualScope.of(this);
}

abstract final class StandardSpec {
  static const String defaultBackgroundId = 'greenhouse';

  static const Color backdropBacking = Color(0xFF050809);

  static const ThemePalette palette = ThemePalette(
    canvas: backdropBacking,
    canvasDeep: Color(0xFF030706),
    surface: Color(0xFF18231F),
    surfaceRaised: Color(0xFF24322C),
    surfaceInset: Color(0xFF0D1512),
    primary: Color(0xFF2F9E7A),
    primaryBright: Color(0xFF69D6AC),
    secondary: Color(0xFFA67746),
    trim: Color(0xFF53645D),
    trimBright: Color(0xFF9DB8AA),
    text: Color(0xFFFFF4D8),
    textMuted: Color(0xFFB9C9C1),
    success: Color(0xFF6ED6A7),
    warning: Color(0xFFE4B45C),
    danger: Color(0xFFD16E65),
    shadow: Color(0xC0000000),
    specular: Color(0x8FFFFFE8),
  );

  static const ThemeGeometry geometry = ThemeGeometry(
    titleStripHeight: 40,
    workspacePadding: EdgeInsets.fromLTRB(20, 20, 24, 18),
    sidebarWidth: 226,
    contentGap: 14,
    panelRadius: 11,
    commandRadius: 9,
    cardRadius: 8,
    buttonRadius: 9,
    navigationRadius: 11,
    fieldRadius: 6,
    compactBreakpoint: Size(1260, 780),
    minimumWindowSize: Size(1200, 752),
  );

  static const ThemeTypography typography = ThemeTypography(
    display: TextStyle(
      color: Color(0xFFFFF4D8),
      fontFamily: 'Georgia',
      fontSize: 28,
      fontWeight: FontWeight.w700,
      letterSpacing: 0.2,
      height: 1.08,
    ),
    section: TextStyle(
      color: Color(0xFFFFF4D8),
      fontFamily: 'Georgia',
      fontSize: 20,
      fontWeight: FontWeight.w700,
      letterSpacing: 0.15,
      height: 1.14,
    ),
    body: TextStyle(
      color: Color(0xFFFFF4D8),
      fontFamily: 'Segoe UI',
      fontSize: 14,
      fontWeight: FontWeight.w400,
      height: 1.35,
    ),
    meta: TextStyle(
      color: Color(0xFFB9C9C1),
      fontFamily: 'Segoe UI',
      fontSize: 12,
      fontWeight: FontWeight.w400,
      height: 1.25,
    ),
    label: TextStyle(
      color: Color(0xFFB9C9C1),
      fontFamily: 'Segoe UI',
      fontSize: 11,
      fontWeight: FontWeight.w600,
      letterSpacing: 0.45,
      height: 1.2,
    ),
    button: TextStyle(
      color: Color(0xFFFFF4D8),
      fontFamily: 'Segoe UI',
      fontSize: 14,
      fontWeight: FontWeight.w700,
      height: 1.15,
    ),
  );

  static const ThemeMaterials materials = ThemeMaterials(
    canvas: LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: <Color>[backdropBacking, Color(0xFF030706)],
    ),
    surface: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: <Color>[
        Color.fromARGB(44, 16, 48, 36),
        Color.fromARGB(10, 5, 19, 15),
        Color.fromARGB(16, 1, 6, 7),
      ],
      stops: <double>[0, 0.55, 1],
    ),
    surfaceRaised: LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: <Color>[
        Color.fromARGB(178, 16, 48, 36),
        Color.fromARGB(140, 5, 19, 15),
        Color.fromARGB(188, 1, 6, 7),
      ],
      stops: <double>[0, 0.55, 1],
    ),
    primary: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: <Color>[Color(0xFF69D6AC), Color(0xFF2F9E7A)],
    ),
    secondary: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: <Color>[Color(0xFF3D5148), Color(0xFF18231F)],
    ),
    modalScrim: Color(0xB8030706),
    lowShadow: <BoxShadow>[],
    highShadow: <BoxShadow>[
      BoxShadow(
        color: Color(0xA0000000),
        blurRadius: 28,
        offset: Offset(0, 12),
      ),
    ],
  );

  static const ThemeMotionCapabilities motion = ThemeMotionCapabilities(
    interactionDuration: Duration(milliseconds: 90),
    supportsAtmosphere: true,
    supportsButtonEffects: false,
    supportsOrnament: false,
  );

  static const ThemeSpec theme = ThemeSpec(
    id: 'standard',
    displayName: 'Standard',
    family: RetainedVisualFamily.standard,
    layoutProfile: ThemeLayoutProfile.standardWorkspace,
    brightness: Brightness.dark,
    palette: palette,
    typography: typography,
    geometry: geometry,
    materials: materials,
    motion: motion,
  );

  static const Map<String, StandardSceneSpec> scenes =
      <String, StandardSceneSpec>{
        'greenhouse': StandardSceneSpec(
          id: 'greenhouse',
          displayName: 'Greenhouse',
          assetPath: 'assets/scenes/backdrop-alchemy-greenhouse.png',
          defaultParticleId: 'fumes',
          accentHue: 158,
          contrastStrength: 0.08,
        ),
        'orrery': StandardSceneSpec(
          id: 'orrery',
          displayName: 'Orrery',
          assetPath: 'assets/scenes/backdrop-moon-orrery.png',
          defaultParticleId: 'stars',
          accentHue: 218,
          contrastStrength: 0.06,
        ),
        'hearth': StandardSceneSpec(
          id: 'hearth',
          displayName: 'Hearth',
          assetPath: 'assets/scenes/backdrop-copper-hearth.png',
          defaultParticleId: 'embers',
          accentHue: 28,
          contrastStrength: 0.08,
        ),
        'frostbound': StandardSceneSpec(
          id: 'frostbound',
          displayName: 'Winter Glade',
          assetPath: 'assets/scenes/backdrop-winter-glade.png',
          defaultParticleId: 'snow',
          accentHue: 196,
          contrastStrength: 0.1,
        ),
        'summer': StandardSceneSpec(
          id: 'summer',
          displayName: 'Summer Courtyard',
          assetPath: 'assets/scenes/backdrop-summer-courtyard.png',
          defaultParticleId: 'fireflies',
          accentHue: 62,
          contrastStrength: 0.12,
        ),
        'tide': StandardSceneSpec(
          id: 'tide',
          displayName: 'Tide Grotto',
          assetPath: 'assets/scenes/backdrop-tide-grotto.png',
          defaultParticleId: 'bubbles',
          accentHue: 188,
          contrastStrength: 0.1,
        ),
        'lagoon': StandardSceneSpec(
          id: 'lagoon',
          displayName: 'Cove Outlook',
          assetPath: 'assets/scenes/backdrop-rocky-cove.png',
          defaultParticleId: 'bubbles',
          accentHue: 188,
          contrastStrength: 0.22,
        ),
        'reef': StandardSceneSpec(
          id: 'reef',
          displayName: 'Coral Reef',
          assetPath: 'assets/scenes/backdrop-coral-reef.png',
          defaultParticleId: 'bubbles',
          accentHue: 188,
          contrastStrength: 0.24,
        ),
      };

  static const Map<String, StandardPlainSpec> plainBackgrounds =
      <String, StandardPlainSpec>{
        'plain-dark': StandardPlainSpec(
          id: 'plain-dark',
          displayName: 'Midnight Glass',
          left: Color.fromARGB(214, 7, 14, 18),
          right: Color.fromARGB(176, 22, 58, 55),
        ),
        'plain-verdant': StandardPlainSpec(
          id: 'plain-verdant',
          displayName: 'Verdant Glass',
          left: Color.fromARGB(210, 8, 48, 31),
          right: Color.fromARGB(186, 42, 112, 69),
        ),
        'plain-violet': StandardPlainSpec(
          id: 'plain-violet',
          displayName: 'Astral Glass',
          left: Color.fromARGB(210, 25, 25, 58),
          right: Color.fromARGB(186, 84, 54, 128),
        ),
        'plain-amber': StandardPlainSpec(
          id: 'plain-amber',
          displayName: 'Warm Glass',
          left: Color.fromARGB(210, 76, 47, 14),
          right: Color.fromARGB(186, 128, 87, 31),
        ),
        'plain-cobalt': StandardPlainSpec(
          id: 'plain-cobalt',
          displayName: 'Cobalt Glass',
          left: Color.fromARGB(210, 8, 32, 48),
          right: Color.fromARGB(186, 32, 108, 132),
        ),
        'plain-rose': StandardPlainSpec(
          id: 'plain-rose',
          displayName: 'Rose Glass',
          left: Color.fromARGB(210, 54, 18, 35),
          right: Color.fromARGB(186, 126, 54, 86),
        ),
      };

  static StandardBackdropSelection resolveBackdrop(String backgroundId) {
    final scene = scenes[backgroundId];
    if (scene != null) {
      return StandardBackdropSelection.scene(scene);
    }
    final plain = plainBackgrounds[backgroundId];
    if (plain != null) {
      return StandardBackdropSelection.plain(plain);
    }
    return StandardBackdropSelection.scene(scenes[defaultBackgroundId]!);
  }

  static LinearGradient glassGradient({
    int topAlpha = 44,
    int bottomAlpha = 16,
  }) {
    final safeTop = topAlpha.clamp(0, 255);
    final safeBottom = bottomAlpha.clamp(0, 255);
    return LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: <Color>[
        Color.fromARGB(safeTop, 16, 48, 36),
        Color.fromARGB(math.max(10, safeTop - 38), 5, 19, 15),
        Color.fromARGB(safeBottom, 1, 6, 7),
      ],
      stops: const <double>[0, 0.55, 1],
    );
  }

  static Color accentBrush(double hue, {double alpha = 1, bool neon = false}) =>
      _hsl(hue, neon ? .86 : .62, neon ? .64 : .52, alpha);

  static LinearGradient accentGlass(
    double hue, {
    int topAlpha = 136,
    int bottomAlpha = 58,
    bool neon = false,
  }) {
    final safeTop = topAlpha.clamp(0, 255);
    final safeBottom = bottomAlpha.clamp(0, 255);
    return LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: <Color>[
        _hsl(hue, neon ? .86 : .58, neon ? .62 : .46, safeTop / 255),
        _hsl(
          hue - 8,
          neon ? .74 : .48,
          neon ? .5 : .32,
          math.max(24, safeTop - 46) / 255,
        ),
        _hsl(hue - 18, neon ? .68 : .42, neon ? .34 : .18, safeBottom / 255),
      ],
      stops: const <double>[0, 0.58, 1],
    );
  }

  static Color plannerCardFill(String backgroundId, AppSurfaceTone tone) {
    if (tone == AppSurfaceTone.danger) {
      return const Color.fromARGB(146, 58, 27, 25);
    }
    final base = switch (backgroundId) {
      'hearth' => const (58, 37, 23),
      'orrery' => const (20, 30, 55),
      'frostbound' => const (18, 47, 57),
      'summer' => const (34, 55, 29),
      'tide' || 'lagoon' || 'reef' => const (18, 51, 56),
      'plain-amber' => const (58, 39, 20),
      'plain-violet' => const (28, 26, 58),
      _ => const (17, 42, 34),
    };
    if (tone == AppSurfaceTone.success) {
      return Color.fromARGB(148, base.$1 + 6, base.$2 + 9, base.$3 + 6);
    }
    return Color.fromARGB(148, base.$1, base.$2, base.$3);
  }

  static Color plannerCardBorder(AppSurfaceTone tone) => switch (tone) {
    AppSurfaceTone.success => const Color(0x4A7BCB83),
    AppSurfaceTone.warning => const Color(0x48B8964B),
    AppSurfaceTone.danger => const Color(0x50A05C52),
    AppSurfaceTone.info => const Color(0x4857BFAE),
    AppSurfaceTone.neutral => const Color(0x334C6C5D),
  };

  static LinearGradient titleStripGradient(String backgroundId) {
    final colors = switch (backgroundId) {
      'hearth' => const <Color>[
        Color.fromARGB(224, 45, 24, 16),
        Color.fromARGB(186, 55, 31, 17),
        Color.fromARGB(212, 25, 16, 13),
      ],
      'orrery' => const <Color>[
        Color.fromARGB(224, 8, 22, 43),
        Color.fromARGB(182, 7, 18, 39),
        Color.fromARGB(212, 5, 12, 28),
      ],
      'frostbound' => const <Color>[
        Color.fromARGB(224, 10, 25, 34),
        Color.fromARGB(184, 11, 34, 44),
        Color.fromARGB(212, 5, 16, 24),
      ],
      'summer' => const <Color>[
        Color.fromARGB(224, 18, 43, 24),
        Color.fromARGB(184, 15, 52, 29),
        Color.fromARGB(212, 7, 24, 14),
      ],
      'tide' || 'lagoon' || 'reef' => const <Color>[
        Color.fromARGB(224, 5, 34, 42),
        Color.fromARGB(184, 6, 42, 48),
        Color.fromARGB(212, 4, 18, 24),
      ],
      _ => const <Color>[
        Color.fromARGB(222, 10, 48, 32),
        Color.fromARGB(184, 9, 33, 26),
        Color.fromARGB(210, 6, 22, 19),
      ],
    };
    return LinearGradient(
      begin: Alignment.centerLeft,
      end: Alignment.centerRight,
      colors: colors,
      stops: const <double>[0, .56, 1],
    );
  }

  static Color _hsl(
    double hue,
    double saturation,
    double lightness,
    double alpha,
  ) => HSLColor.fromAHSL(
    alpha.clamp(0, 1).toDouble(),
    ((hue % 360) + 360) % 360,
    saturation.clamp(0, 1).toDouble(),
    lightness.clamp(0, 1).toDouble(),
  ).toColor();

  static const LinearGradient backdropTone = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: <Color>[
      Color.fromARGB(104, 1, 6, 5),
      Color.fromARGB(62, 4, 18, 13),
      Color.fromARGB(124, 3, 5, 7),
    ],
    stops: <double>[0, 0.48, 1],
  );
}
