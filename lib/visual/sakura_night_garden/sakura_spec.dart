import 'package:flutter/material.dart';

import '../foundations/theme_spec.dart';

/// Stable tokens for the approved Sakura Night Garden Atelier skin.
///
/// The theme deliberately reuses the dense Ledger layout profile while
/// remaining a dark, non-manuscript visual family of its own.
abstract final class SakuraNightGardenSpec {
  static const String backgroundId = 'sakura-night-garden';
  static const String blackenedCedarAssetPath =
      'assets/sakura/materials/blackened-cedar.png';

  static const Color nightCedar = Color(0xFF151414);
  static const Color canvasDeep = Color(0xFF0D0B0F);
  static const Color charcoalPlum = Color(0xFF211A20);
  static const Color raisedPlum = Color(0xFF2B2028);
  static const Color insetPlum = Color(0xFF100E12);
  static const Color darkCherrywood = Color(0xFF42282D);
  static const Color rosewood = Color(0xFF6B3C48);
  static const Color barkCopper = Color(0xFF8E5D55);
  static const Color copperHighlight = Color(0xFFA66C69);
  static const Color dustySakura = Color(0xFFCF7F98);
  static const Color paleBlossom = Color(0xFFE8B0BF);
  static const Color mutedMoss = Color(0xFF66765F);
  static const Color warmIvory = Color(0xFFEEE5DC);
  static const Color mutedText = Color(0xFFB9A7A2);
  static const Color emberBerry = Color(0xFFA74E69);

  static const ThemePalette palette = ThemePalette(
    canvas: nightCedar,
    canvasDeep: canvasDeep,
    surface: charcoalPlum,
    surfaceRaised: raisedPlum,
    surfaceInset: insetPlum,
    primary: dustySakura,
    primaryBright: paleBlossom,
    secondary: mutedMoss,
    trim: rosewood,
    trimBright: copperHighlight,
    text: warmIvory,
    textMuted: mutedText,
    success: mutedMoss,
    warning: Color(0xFFB78358),
    danger: emberBerry,
    shadow: Color(0xB3000000),
    specular: Color(0x4DE8B0BF),
  );

  static const ThemeGeometry geometry = ThemeGeometry(
    titleStripHeight: 40,
    workspacePadding: EdgeInsets.fromLTRB(20, 20, 24, 18),
    sidebarWidth: 226,
    contentGap: 14,
    panelRadius: 6,
    commandRadius: 6,
    cardRadius: 6,
    buttonRadius: 5,
    navigationRadius: 5,
    fieldRadius: 5,
    compactBreakpoint: Size(1260, 780),
    minimumWindowSize: Size(1200, 752),
  );

  static const ThemeTypography typography = ThemeTypography(
    display: TextStyle(
      color: warmIvory,
      fontFamily: 'Georgia',
      fontSize: 30,
      fontWeight: FontWeight.w700,
      height: 1.04,
    ),
    section: TextStyle(
      color: warmIvory,
      fontFamily: 'Georgia',
      fontSize: 25,
      fontWeight: FontWeight.w600,
      letterSpacing: 0.55,
      height: 1.08,
    ),
    body: TextStyle(
      color: warmIvory,
      fontFamily: 'Segoe UI',
      fontSize: 14,
      fontWeight: FontWeight.w400,
      height: 1.3,
    ),
    meta: TextStyle(
      color: mutedText,
      fontFamily: 'Segoe UI',
      fontSize: 12,
      fontWeight: FontWeight.w400,
      height: 1.24,
    ),
    label: TextStyle(
      color: Color(0xFFD8B7AD),
      fontFamily: 'Segoe UI',
      fontSize: 11,
      fontWeight: FontWeight.w700,
      letterSpacing: 0.65,
      height: 1.18,
    ),
    button: TextStyle(
      color: warmIvory,
      fontFamily: 'Segoe UI',
      fontSize: 13,
      fontWeight: FontWeight.w600,
      height: 1.1,
    ),
  );

  static const LinearGradient canvasGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: <Color>[
      Color(0xFF1D1819),
      nightCedar,
      Color(0xFF0B0A0D),
      Color(0xFF191118),
    ],
    stops: <double>[0, 0.27, 0.7, 1],
  );

  static const LinearGradient surfaceGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: <Color>[
      Color(0xFF2C2229),
      Color(0xFF241C23),
      Color(0xFF181419),
      Color(0xFF0F0D11),
    ],
    stops: <double>[0, 0.25, 0.72, 1],
  );

  static const LinearGradient raisedSurfaceGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: <Color>[
      Color(0xFF372A33),
      Color(0xFF2C222B),
      Color(0xFF1E181F),
      Color(0xFF110E13),
    ],
    stops: <double>[0, 0.18, 0.72, 1],
  );

  static const LinearGradient sakuraLacquerGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: <Color>[
      Color(0xFF512E3A),
      Color(0xFF412631),
      Color(0xFF2B1A23),
      Color(0xFF171117),
    ],
    stops: <double>[0, 0.2, 0.68, 1],
  );

  static const LinearGradient mossGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: <Color>[
      Color(0xFF53614D),
      Color(0xFF3D4A39),
      Color(0xFF273124),
      Color(0xFF151D16),
    ],
    stops: <double>[0, 0.23, 0.7, 1],
  );

  static const ThemeMaterials materials = ThemeMaterials(
    canvas: canvasGradient,
    surface: surfaceGradient,
    surfaceRaised: raisedSurfaceGradient,
    primary: sakuraLacquerGradient,
    secondary: mossGradient,
    modalScrim: Color(0xC20A080B),
    lowShadow: <BoxShadow>[
      BoxShadow(color: Color(0x8A000000), blurRadius: 9, offset: Offset(0, 4)),
      BoxShadow(color: Color(0x1FA66C69), blurRadius: 1, offset: Offset(0, -1)),
    ],
    highShadow: <BoxShadow>[
      BoxShadow(
        color: Color(0xB8000000),
        blurRadius: 24,
        offset: Offset(0, 11),
      ),
      BoxShadow(color: Color(0x26A66C69), blurRadius: 2, offset: Offset(0, -1)),
    ],
  );

  static const ThemeMotionCapabilities motion = ThemeMotionCapabilities(
    interactionDuration: Duration(milliseconds: 90),
    supportsAtmosphere: false,
    supportsOrnament: true,
    supportsButtonEffects: false,
  );

  static const ThemeSpec theme = ThemeSpec(
    id: backgroundId,
    displayName: 'Sakura Night Garden',
    family: RetainedVisualFamily.sakuraNightGarden,
    layoutProfile: ThemeLayoutProfile.denseSplitWorkspace,
    brightness: Brightness.dark,
    palette: palette,
    typography: typography,
    geometry: geometry,
    materials: materials,
    motion: motion,
  );
}
