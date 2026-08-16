import 'package:flutter/material.dart';

import '../foundations/theme_spec.dart';

abstract final class IlluminatedLedgerSpec {
  static const String backgroundId = 'illuminated-ledger';
  static const String leatherAssetPath =
      'assets/ledger/ledger-navy-leather.png';
  static const String vellumAssetPath =
      'assets/ledger/ledger-vellum-texture.png';
  static const String marginaliaAssetPath =
      'assets/ledger/ledger-botanical-marginalia.png';
  static const String dropCapAssetPath = 'assets/ledger/ledger-drop-cap-b.png';

  static const ThemePalette palette = ThemePalette(
    canvas: Color(0xFFE8D2A3),
    canvasDeep: Color(0xFF071A2E),
    surface: Color(0xFFE9D5A8),
    surfaceRaised: Color(0xFFF2E3BD),
    surfaceInset: Color(0xFFD8BF8A),
    primary: Color(0xFF123D69),
    primaryBright: Color(0xFF1A5487),
    secondary: Color(0xFF647B35),
    trim: Color(0xFF9A742F),
    trimBright: Color(0xFFD6B45A),
    text: Color(0xFF352516),
    textMuted: Color(0xFF765F3B),
    success: Color(0xFF647B35),
    warning: Color(0xFFB78338),
    danger: Color(0xFFA45648),
    shadow: Color(0x70352516),
    specular: Color(0x66FFF0C9),
  );

  static const ThemeGeometry geometry = ThemeGeometry(
    titleStripHeight: 40,
    workspacePadding: EdgeInsets.fromLTRB(20, 20, 24, 18),
    sidebarWidth: 226,
    contentGap: 14,
    panelRadius: 2,
    commandRadius: 2,
    cardRadius: 2,
    buttonRadius: 2,
    navigationRadius: 2,
    fieldRadius: 2,
    compactBreakpoint: Size(1260, 780),
    minimumWindowSize: Size(1200, 752),
  );

  static const ThemeTypography typography = ThemeTypography(
    display: TextStyle(
      color: Color(0xFF352516),
      fontFamily: 'Georgia',
      fontSize: 30,
      fontWeight: FontWeight.w700,
      height: 1.04,
    ),
    section: TextStyle(
      color: Color(0xFF352516),
      fontFamily: 'Georgia',
      fontSize: 25,
      fontWeight: FontWeight.w600,
      letterSpacing: 1.3,
      height: 1.08,
    ),
    body: TextStyle(
      color: Color(0xFF352516),
      fontFamily: 'Georgia',
      fontSize: 14,
      fontWeight: FontWeight.w400,
      height: 1.36,
    ),
    meta: TextStyle(
      color: Color(0xFF765F3B),
      fontFamily: 'Georgia',
      fontSize: 12,
      fontStyle: FontStyle.normal,
      height: 1.28,
    ),
    label: TextStyle(
      color: Color(0xFF765F3B),
      fontFamily: 'Georgia',
      fontSize: 11,
      fontWeight: FontWeight.w700,
      letterSpacing: 0.75,
      height: 1.2,
    ),
    button: TextStyle(
      color: Color(0xFF352516),
      fontFamily: 'Georgia',
      fontSize: 14,
      fontWeight: FontWeight.w700,
      height: 1.08,
    ),
  );

  static const LinearGradient vellumGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: <Color>[Color(0xFFF2E2BC), Color(0xFFE6CE99), Color(0xFFD3B77D)],
    stops: <double>[0, 0.58, 1],
  );

  static const LinearGradient raisedVellumGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: <Color>[Color(0xFFF8EAC8), Color(0xFFEBD4A3), Color(0xFFD8BC83)],
    stops: <double>[0, 0.62, 1],
  );

  static const LinearGradient lapisGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: <Color>[Color(0xFF174D7E), Color(0xFF0A2744)],
  );

  static const RadialGradient waxGradient = RadialGradient(
    colors: <Color>[Color(0xFFA0A96A), Color(0xFF647B35), Color(0xFF34491F)],
    stops: <double>[0, 0.48, 1],
  );

  static const ThemeMaterials materials = ThemeMaterials(
    canvas: LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: <Color>[Color(0xFF174D7E), Color(0xFF071A2E)],
    ),
    surface: vellumGradient,
    surfaceRaised: raisedVellumGradient,
    primary: lapisGradient,
    secondary: LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: <Color>[Color(0xFFA0A96A), Color(0xFF52652C)],
    ),
    modalScrim: Color(0x99030F1E),
    lowShadow: <BoxShadow>[
      BoxShadow(color: Color(0x40352516), blurRadius: 8, offset: Offset(0, 3)),
    ],
    highShadow: <BoxShadow>[
      BoxShadow(
        color: Color(0x70352516),
        blurRadius: 24,
        offset: Offset(0, 10),
      ),
    ],
  );

  static const ThemeMotionCapabilities motion = ThemeMotionCapabilities(
    interactionDuration: Duration(milliseconds: 80),
    supportsAtmosphere: false,
    supportsButtonEffects: false,
    supportsOrnament: true,
  );

  static const ThemeSpec theme = ThemeSpec(
    id: backgroundId,
    displayName: 'Illuminated Ledger',
    family: RetainedVisualFamily.illuminatedLedger,
    layoutProfile: ThemeLayoutProfile.denseSplitWorkspace,
    brightness: Brightness.light,
    palette: palette,
    typography: typography,
    geometry: geometry,
    materials: materials,
    motion: motion,
  );

  // LedgerBackdrop is hosted below the native 40 px title strip. The Avalonia
  // vellum begins eight pixels into that client body; counting the title strip
  // a second time left a 47 px leather band over workspace headings.
  static const EdgeInsets pageInsets = EdgeInsets.fromLTRB(16, 8, 16, 16);
  static const double referenceSidebarFoldX = 246;
  static const double defaultCenterFoldRatio = 0.575;
}
