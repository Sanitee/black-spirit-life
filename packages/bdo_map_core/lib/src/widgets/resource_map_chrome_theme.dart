import 'package:flutter/material.dart';

import '../model/map_ui_opacity.dart';

/// The two complete Resource Map interface systems available to the user.
///
/// [id] is deliberately stable because it is written into the portable
/// planner document. Unknown or older values safely return to [glassDock].
enum ResourceMapInterfaceStyle {
  glassDock('glassDock', 'Glass Dock'),
  ghostLedger('ghostLedger', 'Ghost Ledger');

  const ResourceMapInterfaceStyle(this.id, this.label);

  final String id;
  final String label;

  ResourceMapInterfaceStyle get alternate => switch (this) {
    glassDock => ghostLedger,
    ghostLedger => glassDock,
  };

  static ResourceMapInterfaceStyle fromId(Object? value) {
    final id = value?.toString().trim();
    return ResourceMapInterfaceStyle.values.firstWhere(
      (style) => style.id == id,
      orElse: () => ResourceMapInterfaceStyle.glassDock,
    );
  }
}

/// The visual language used by the Resource Map's package-owned chrome.
///
/// This deliberately lives in `bdo_map_core`: applications can select a map
/// skin without making the reusable map package depend on an app theme model.
enum ResourceMapChromeThemeVariant {
  fieldAtlas,
  ghostLedger,
  sakuraCartographer,
  illuminatedAtlas,
}

/// Semantic colors, materials and geometry for Resource Map controls.
///
/// Map features should consume these roles through [ResourceMapChromeTheme]
/// rather than branching on [variant]. That keeps app-selected skins coherent
/// and allows future themes to be supplied without changing map widgets.
@immutable
class ResourceMapChromeThemeData {
  const ResourceMapChromeThemeData({
    this.uiOpacity = ResourceMapUiOpacity.defaultValue,
    required this.variant,
    required this.canvas,
    required this.paper,
    required this.paperRaised,
    required this.ink,
    required this.text,
    required this.muted,
    required this.warmOutline,
    required this.softOutline,
    required this.primary,
    required this.deepAccent,
    required this.onPrimary,
    required this.accent,
    required this.positive,
    required this.warning,
    required this.error,
    required this.chromeBase,
    required this.chromeRaised,
    required this.chromeHighlight,
    required this.modeStripFadeColor,
    required this.trimDeep,
    required this.trimLine,
    required this.trimWash,
    required this.idleControlGradient,
    required this.idleCompactGradient,
    required this.hoverControlGradient,
    required this.selectedControlGradient,
    required this.selectedModeGradient,
    required this.selectedCompactGradient,
    required this.selectedInlineGradient,
    required this.idleInlineGradient,
    required this.idleSearchGradient,
    required this.focusedSearchGradient,
    required this.surfaceGradient,
    required this.subtleSurfaceGradient,
    required this.taskStripGradient,
    required this.readingSurfaceGradient,
    required this.edgeFadeGradient,
    required this.contourColor,
    required this.fleckColor,
    required this.readingInk,
    required this.readingMuted,
    required this.readingOutline,
    required this.idleShadow,
    required this.selectedShadow,
    required this.hoverShadow,
    required this.surfaceShadows,
    required this.subtleSurfaceShadows,
    required this.headingFontFamily,
    required this.commandRadius,
    required this.controlRadius,
    required this.toolRadius,
    required this.inlineRadius,
    required this.keycapRadius,
    required this.compactRadius,
    required this.surfaceRadius,
  });

  final ResourceMapChromeThemeVariant variant;
  final double uiOpacity;
  final Color canvas;
  final Color paper;
  final Color paperRaised;
  final Color ink;
  final Color text;
  final Color muted;
  final Color warmOutline;
  final Color softOutline;
  Color get divider => softOutline;
  final Color primary;
  final Color deepAccent;
  final Color onPrimary;
  final Color accent;
  final Color positive;
  final Color warning;
  final Color error;
  final Color chromeBase;
  final Color chromeRaised;
  final Color chromeHighlight;
  final Color modeStripFadeColor;
  final Color trimDeep;
  final Color trimLine;
  final Color trimWash;

  // Compatibility role names used by the map's older feature widgets. They
  // intentionally resolve to semantic chrome roles so those widgets can move
  // between skins without relying on a second palette or global mutable state.
  Color get tealDeep => deepAccent;
  Color get graphite => chromeBase;
  Color get graphiteRaised => chromeRaised;
  Color get graphiteHighlight => chromeHighlight;
  Color get brassDeep => trimDeep;
  Color get brassLine => trimLine;
  Color get brassWash => trimWash;

  final LinearGradient idleControlGradient;
  final LinearGradient idleCompactGradient;
  final LinearGradient hoverControlGradient;
  final LinearGradient selectedControlGradient;
  final LinearGradient selectedModeGradient;
  final LinearGradient selectedCompactGradient;
  final LinearGradient selectedInlineGradient;
  final LinearGradient idleInlineGradient;
  final LinearGradient idleSearchGradient;
  final LinearGradient focusedSearchGradient;
  final LinearGradient surfaceGradient;
  final LinearGradient subtleSurfaceGradient;
  final LinearGradient taskStripGradient;
  final LinearGradient readingSurfaceGradient;
  final LinearGradient edgeFadeGradient;

  final Color contourColor;
  final Color fleckColor;
  final Color readingInk;
  final Color readingMuted;
  final Color readingOutline;
  final BoxShadow idleShadow;
  final BoxShadow selectedShadow;
  final BoxShadow hoverShadow;
  final List<BoxShadow> surfaceShadows;
  final List<BoxShadow> subtleSurfaceShadows;
  final String? headingFontFamily;
  final double commandRadius;
  final double controlRadius;
  final double toolRadius;
  final double inlineRadius;
  final double keycapRadius;
  final double compactRadius;
  final double surfaceRadius;

  double get materialOpacity => ResourceMapUiOpacity.material(uiOpacity);

  /// Multiplies material fills and their shadows. Foreground colours, icons,
  /// geometry and the basemap canvas are deliberately retained verbatim.
  ResourceMapChromeThemeData withUiOpacity(Object? value) {
    final opacity = ResourceMapUiOpacity.normalize(value);
    if (opacity == uiOpacity) return this;
    final multiplier = ResourceMapUiOpacity.material(opacity) / materialOpacity;
    Color fade(Color color) => color.withValues(alpha: color.a * multiplier);
    BoxShadow fadeShadow(BoxShadow shadow) =>
        shadow.copyWith(color: fade(shadow.color));
    LinearGradient fadeGradient(LinearGradient gradient) => LinearGradient(
      begin: gradient.begin,
      end: gradient.end,
      colors: gradient.colors.map(fade).toList(growable: false),
      stops: gradient.stops,
      tileMode: gradient.tileMode,
      transform: gradient.transform,
    );
    return ResourceMapChromeThemeData(
      uiOpacity: opacity,
      variant: variant,
      canvas: canvas,
      paper: fade(paper),
      paperRaised: fade(paperRaised),
      ink: ink,
      text: text,
      muted: muted,
      warmOutline: warmOutline,
      softOutline: softOutline,
      primary: primary,
      deepAccent: deepAccent,
      onPrimary: onPrimary,
      accent: accent,
      positive: positive,
      warning: warning,
      error: error,
      chromeBase: fade(chromeBase),
      chromeRaised: fade(chromeRaised),
      chromeHighlight: fade(chromeHighlight),
      modeStripFadeColor: fade(modeStripFadeColor),
      trimDeep: fade(trimDeep),
      trimLine: trimLine,
      trimWash: fade(trimWash),
      idleControlGradient: fadeGradient(idleControlGradient),
      idleCompactGradient: fadeGradient(idleCompactGradient),
      hoverControlGradient: fadeGradient(hoverControlGradient),
      selectedControlGradient: fadeGradient(selectedControlGradient),
      selectedModeGradient: fadeGradient(selectedModeGradient),
      selectedCompactGradient: fadeGradient(selectedCompactGradient),
      selectedInlineGradient: fadeGradient(selectedInlineGradient),
      idleInlineGradient: fadeGradient(idleInlineGradient),
      idleSearchGradient: fadeGradient(idleSearchGradient),
      focusedSearchGradient: fadeGradient(focusedSearchGradient),
      surfaceGradient: fadeGradient(surfaceGradient),
      subtleSurfaceGradient: fadeGradient(subtleSurfaceGradient),
      taskStripGradient: fadeGradient(taskStripGradient),
      readingSurfaceGradient: fadeGradient(readingSurfaceGradient),
      edgeFadeGradient: fadeGradient(edgeFadeGradient),
      contourColor: fade(contourColor),
      fleckColor: fade(fleckColor),
      readingInk: readingInk,
      readingMuted: readingMuted,
      readingOutline: readingOutline,
      idleShadow: fadeShadow(idleShadow),
      selectedShadow: fadeShadow(selectedShadow),
      hoverShadow: fadeShadow(hoverShadow),
      surfaceShadows: surfaceShadows.map(fadeShadow).toList(growable: false),
      subtleSurfaceShadows: subtleSurfaceShadows
          .map(fadeShadow)
          .toList(growable: false),
      headingFontFamily: headingFontFamily,
      commandRadius: commandRadius,
      controlRadius: controlRadius,
      toolRadius: toolRadius,
      inlineRadius: inlineRadius,
      keycapRadius: keycapRadius,
      compactRadius: compactRadius,
      surfaceRadius: surfaceRadius,
    );
  }

  /// For fills that deliberately override their role's base alpha.
  Color fillAlpha(Color color, double alpha) =>
      color.withValues(alpha: alpha * materialOpacity);

  TextStyle headingStyle({
    double fontSize = 15,
    Color? color,
    FontWeight fontWeight = FontWeight.w700,
  }) => TextStyle(
    color: color ?? ink,
    fontFamily: headingFontFamily,
    fontSize: fontSize,
    height: 1.2,
    fontWeight: fontWeight,
    letterSpacing: headingFontFamily == null ? .05 : .12,
  );

  /// Neutral, map-native chrome used by the application map workspace.
  ///
  /// It deliberately does not inherit the decorative identity of either
  /// planner theme. Surfaces are compact graphite tools with cool location
  /// accents, letting the basemap and familiar game artwork carry the view.
  static const fieldAtlas = ResourceMapChromeThemeData(
    variant: ResourceMapChromeThemeVariant.fieldAtlas,
    canvas: Color(0xFF0C1C2D),
    paper: Color(0xFF142A40),
    paperRaised: Color(0xFF1C344B),
    ink: Color(0xFFF0F4FA),
    text: Color(0xFFE7EFF7),
    muted: Color(0xFFC0CFDF),
    warmOutline: Color(0x996689A0),
    softOutline: Color(0x8847647C),
    primary: Color(0xFF80D6D5),
    deepAccent: Color(0xFF1C4559),
    onPrimary: Color(0xFF071221),
    accent: Color(0xFFACCFDF),
    positive: Color(0xFF9CDEB7),
    warning: Color(0xFFEDC38C),
    error: Color(0xFFF2A39A),
    chromeBase: Color(0xFF102338),
    chromeRaised: Color(0xFF193249),
    chromeHighlight: Color(0xFF26445B),
    modeStripFadeColor: Color(0xF0102338),
    trimDeep: Color(0xFF365D77),
    trimLine: Color(0xFF80D6D5),
    trimWash: Color(0x2480D6D5),
    idleControlGradient: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: <Color>[Color(0xF02B495F), Color(0xF51A3048)],
    ),
    idleCompactGradient: LinearGradient(
      colors: <Color>[Color(0xF0233F55), Color(0xF0152B42)],
    ),
    hoverControlGradient: LinearGradient(
      colors: <Color>[Color(0xFF345A70), Color(0xFF223B59)],
    ),
    selectedControlGradient: LinearGradient(
      colors: <Color>[Color(0xFF2E6372), Color(0xFF214958)],
    ),
    selectedModeGradient: LinearGradient(
      colors: <Color>[Color(0xFF2E6372), Color(0xFF214958)],
    ),
    selectedCompactGradient: LinearGradient(
      colors: <Color>[Color(0xFF2E6372), Color(0xFF214958)],
    ),
    selectedInlineGradient: LinearGradient(
      colors: <Color>[Color(0xFF285366), Color(0xFF1B3C53)],
    ),
    idleInlineGradient: LinearGradient(
      colors: <Color>[Color(0xFF1E3C53), Color(0xFF162B43)],
    ),
    idleSearchGradient: LinearGradient(
      colors: <Color>[Color(0xFF102338), Color(0xFF102338)],
    ),
    focusedSearchGradient: LinearGradient(
      colors: <Color>[Color(0xFF193B50), Color(0xFF102338)],
    ),
    surfaceGradient: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: <Color>[Color(0xF0213C51), Color(0xF5102036)],
    ),
    subtleSurfaceGradient: LinearGradient(
      colors: <Color>[Color(0xEA1C354D), Color(0xED12263E)],
    ),
    taskStripGradient: LinearGradient(
      colors: <Color>[Color(0xE318324A), Color(0xED172D45)],
    ),
    readingSurfaceGradient: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: <Color>[Color(0xED18324A), Color(0xF0172D45), Color(0xF511203A)],
      stops: <double>[0, .48, 1],
    ),
    edgeFadeGradient: LinearGradient(
      begin: Alignment.centerLeft,
      end: Alignment.centerRight,
      colors: <Color>[Color(0xFA0E141A), Color(0xE60E141A), Color(0x000E141A)],
      stops: <double>[0, .72, 1],
    ),
    contourColor: Color(0x00000000),
    fleckColor: Color(0x00000000),
    readingInk: Color(0xFFF0F4FA),
    readingMuted: Color(0xFFC0CFDF),
    readingOutline: Color(0x996689A0),
    idleShadow: BoxShadow(
      color: Color(0x59000000),
      blurRadius: 10,
      offset: Offset(0, 4),
    ),
    selectedShadow: BoxShadow(
      color: Color(0x336CB7C8),
      blurRadius: 12,
      offset: Offset(0, 4),
    ),
    hoverShadow: BoxShadow(
      color: Color(0x1F6CB7C8),
      blurRadius: 9,
      offset: Offset(0, 3),
    ),
    surfaceShadows: <BoxShadow>[
      BoxShadow(color: Color(0x66000000), blurRadius: 14, offset: Offset(0, 6)),
    ],
    subtleSurfaceShadows: <BoxShadow>[
      BoxShadow(color: Color(0x4D000000), blurRadius: 8, offset: Offset(0, 3)),
    ],
    headingFontFamily: 'Segoe UI',
    commandRadius: 10,
    controlRadius: 9,
    toolRadius: 9,
    inlineRadius: 8,
    keycapRadius: 4,
    compactRadius: 8,
    surfaceRadius: 14,
  );

  /// Compact cyan smoked glass over the map.
  ///
  /// The geometry and material treatment live in the interface primitives;
  /// these roles also restyle every dialog, form, notice and data surface that
  /// can be opened from the map.
  static const glassDock = fieldAtlas;

  /// The saved alternate palette keeps its cool green tint, with the same
  /// legible reading planes and shared navigation as the default glass.
  static const ghostLedger = ResourceMapChromeThemeData(
    variant: ResourceMapChromeThemeVariant.ghostLedger,
    canvas: Color(0xFF071014),
    paper: Color(0xE80A151A),
    paperRaised: Color(0xEE0D1B21),
    ink: Color(0xFFF1F7F6),
    text: Color(0xFFE8F0F0),
    muted: Color(0xFFCEDCD9),
    warmOutline: Color(0x3667E3D0),
    softOutline: Color(0x243D6967),
    primary: Color(0xFF74E7D3),
    deepAccent: Color(0xFF123D3B),
    onPrimary: Color(0xFF04100F),
    accent: Color(0xFFE8C278),
    positive: Color(0xFF72D5A9),
    warning: Color(0xFFE6B36C),
    error: Color(0xFFF2A39A),
    chromeBase: Color(0xD9081318),
    chromeRaised: Color(0xE80B191F),
    chromeHighlight: Color(0xD914292E),
    modeStripFadeColor: Color(0xC9061116),
    trimDeep: Color(0xFF1F5A55),
    trimLine: Color(0xFF74E7D3),
    trimWash: Color(0x1F74E7D3),
    idleControlGradient: LinearGradient(
      begin: Alignment.centerLeft,
      end: Alignment.centerRight,
      colors: <Color>[Color(0xB309161B), Color(0x7009161B), Color(0x0009161B)],
      stops: <double>[0, .72, 1],
    ),
    idleCompactGradient: LinearGradient(
      colors: <Color>[Color(0xA80A171C), Color(0x700A171C)],
    ),
    hoverControlGradient: LinearGradient(
      begin: Alignment.centerLeft,
      end: Alignment.centerRight,
      colors: <Color>[Color(0xC4142B30), Color(0x70142B30), Color(0x00142B30)],
      stops: <double>[0, .72, 1],
    ),
    selectedControlGradient: LinearGradient(
      begin: Alignment.centerLeft,
      end: Alignment.centerRight,
      colors: <Color>[Color(0xC31B3E3C), Color(0x76142D2D), Color(0x00142D2D)],
      stops: <double>[0, .76, 1],
    ),
    selectedModeGradient: LinearGradient(
      begin: Alignment.centerLeft,
      end: Alignment.centerRight,
      colors: <Color>[Color(0xB71B3E3C), Color(0x00142D2D)],
    ),
    selectedCompactGradient: LinearGradient(
      colors: <Color>[Color(0xB71B3E3C), Color(0x76142D2D)],
    ),
    selectedInlineGradient: LinearGradient(
      begin: Alignment.centerLeft,
      end: Alignment.centerRight,
      colors: <Color>[Color(0xA61B3E3C), Color(0x00142D2D)],
    ),
    idleInlineGradient: LinearGradient(
      begin: Alignment.centerLeft,
      end: Alignment.centerRight,
      colors: <Color>[Color(0x8A0A171C), Color(0x000A171C)],
    ),
    idleSearchGradient: LinearGradient(
      begin: Alignment.centerLeft,
      end: Alignment.centerRight,
      colors: <Color>[Color(0xE609171C), Color(0xDA09171C), Color(0xC909171C)],
      stops: <double>[0, .9, 1],
    ),
    focusedSearchGradient: LinearGradient(
      begin: Alignment.centerLeft,
      end: Alignment.centerRight,
      colors: <Color>[Color(0xED0B2024), Color(0xE00B2024), Color(0xCD0B2024)],
      stops: <double>[0, .9, 1],
    ),
    surfaceGradient: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: <Color>[Color(0xF0193B42), Color(0xF1122D37), Color(0xF510202C)],
      stops: <double>[0, .48, 1],
    ),
    subtleSurfaceGradient: LinearGradient(
      begin: Alignment.centerLeft,
      end: Alignment.centerRight,
      colors: <Color>[Color(0xED14343B), Color(0xED102B34), Color(0xF010202C)],
      stops: <double>[0, .72, 1],
    ),
    taskStripGradient: LinearGradient(
      begin: Alignment.centerLeft,
      end: Alignment.centerRight,
      colors: <Color>[Color(0xED16393E), Color(0xF0132D34), Color(0xF010202C)],
      stops: <double>[0, .9, 1],
    ),
    readingSurfaceGradient: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: <Color>[Color(0xED16343D), Color(0xF0122B35), Color(0xF510202C)],
      stops: <double>[0, .48, 1],
    ),
    edgeFadeGradient: LinearGradient(
      begin: Alignment.centerLeft,
      end: Alignment.centerRight,
      colors: <Color>[
        Color(0xF2081318),
        Color(0xD9081318),
        Color(0x78081318),
        Color(0x00081318),
      ],
      stops: <double>[0, .68, .88, 1],
    ),
    contourColor: Color(0x00000000),
    fleckColor: Color(0x00000000),
    readingInk: Color(0xFFF1F7F6),
    readingMuted: Color(0xFFCEDCD9),
    readingOutline: Color(0x3674E7D3),
    idleShadow: BoxShadow(color: Color(0x26000000), blurRadius: 12),
    selectedShadow: BoxShadow(color: Color(0x2E74E7D3), blurRadius: 18),
    hoverShadow: BoxShadow(color: Color(0x1F74E7D3), blurRadius: 14),
    surfaceShadows: <BoxShadow>[
      BoxShadow(color: Color(0x3D000000), blurRadius: 24, offset: Offset(0, 8)),
    ],
    subtleSurfaceShadows: <BoxShadow>[
      BoxShadow(color: Color(0x26000000), blurRadius: 14, offset: Offset(0, 5)),
    ],
    headingFontFamily: 'Segoe UI',
    commandRadius: 10,
    controlRadius: 9,
    toolRadius: 9,
    inlineRadius: 8,
    keycapRadius: 2,
    compactRadius: 8,
    surfaceRadius: 14,
  );

  /// The established dark Sakura/Emberglass map chrome.
  ///
  /// Values intentionally mirror the pre-contract implementation exactly so
  /// callers that do not install a theme scope retain their current visuals.
  static const sakuraCartographer = ResourceMapChromeThemeData(
    variant: ResourceMapChromeThemeVariant.sakuraCartographer,
    canvas: Color(0xFF100E12),
    paper: Color(0xFF171419),
    paperRaised: Color(0xFF211B22),
    ink: Color(0xFFF5EDDF),
    text: Color(0xFFD8C9BE),
    muted: Color(0xFFA18F86),
    warmOutline: Color(0x667A625B),
    softOutline: Color(0x995A4548),
    primary: Color(0xFFEAA083),
    deepAccent: Color(0xFF44252F),
    onPrimary: Color(0xFF100E12),
    accent: Color(0xFFE6C174),
    positive: Color(0xFF7BD0A3),
    warning: Color(0xFFE7A764),
    error: Color(0xFFF07D84),
    chromeBase: Color(0xFF110F13),
    chromeRaised: Color(0xFF211B20),
    chromeHighlight: Color(0xFF33262D),
    modeStripFadeColor: Color(0xF0110F13),
    trimDeep: Color(0xFF765746),
    trimLine: Color(0xFFC99969),
    trimWash: Color(0x28E6C174),
    idleControlGradient: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: <Color>[Color(0xF02D252A), Color(0xF019161B)],
    ),
    idleCompactGradient: LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: <Color>[Color(0xE62D252A), Color(0xE61B171C)],
    ),
    hoverControlGradient: LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: <Color>[Color(0xF0392B32), Color(0xF020191F)],
    ),
    selectedControlGradient: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: <Color>[Color(0xFF5A303B), Color(0xFF38222B), Color(0xFF241A20)],
      stops: <double>[0, .58, 1],
    ),
    selectedModeGradient: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: <Color>[Color(0xFF5A303B), Color(0xFF352129), Color(0xFF241A20)],
      stops: <double>[0, .58, 1],
    ),
    selectedCompactGradient: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: <Color>[Color(0xFF59303A), Color(0xFF2C1E25)],
    ),
    selectedInlineGradient: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: <Color>[Color(0xFF59303A), Color(0xFF2B1E25)],
    ),
    idleInlineGradient: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: <Color>[Color(0xD92B2429), Color(0xD918151A)],
    ),
    idleSearchGradient: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: <Color>[Color(0xF02B2429), Color(0xF018151A)],
    ),
    focusedSearchGradient: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: <Color>[Color(0xFA3A2931), Color(0xFA1C171D)],
    ),
    surfaceGradient: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: <Color>[Color(0xF22E252B), Color(0xF21D191E), Color(0xF2171419)],
      stops: <double>[0, .48, 1],
    ),
    subtleSurfaceGradient: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: <Color>[Color(0xD9282228), Color(0xD919161B), Color(0xD9141216)],
      stops: <double>[0, .48, 1],
    ),
    taskStripGradient: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: <Color>[Color(0xF22F272D), Color(0xF219161B)],
    ),
    readingSurfaceGradient: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: <Color>[Color(0xF22E252B), Color(0xF2171419)],
    ),
    edgeFadeGradient: LinearGradient(
      begin: Alignment.centerLeft,
      end: Alignment.centerRight,
      colors: <Color>[
        Color(0xFA100E12),
        Color(0xF5100E12),
        Color(0xE6100E12),
        Color(0x00100E12),
      ],
      stops: <double>[0, .78, .88, 1],
    ),
    contourColor: Color(0x0CF5EDDF),
    fleckColor: Color(0x0AF0C7AE),
    readingInk: Color(0xFFF5EDDF),
    readingMuted: Color(0xFFA18F86),
    readingOutline: Color(0x667A625B),
    idleShadow: BoxShadow(
      color: Color(0x52000000),
      blurRadius: 12,
      offset: Offset(0, 5),
    ),
    selectedShadow: BoxShadow(
      color: Color(0x3DEAA083),
      blurRadius: 15,
      offset: Offset(0, 5),
    ),
    hoverShadow: BoxShadow(
      color: Color(0x2EEAA083),
      blurRadius: 13,
      offset: Offset(0, 4),
    ),
    surfaceShadows: <BoxShadow>[
      BoxShadow(color: Color(0x52000000), blurRadius: 16, offset: Offset(0, 6)),
      BoxShadow(color: Color(0x16F4D8C2), blurRadius: 0, offset: Offset(0, 1)),
    ],
    subtleSurfaceShadows: <BoxShadow>[
      BoxShadow(color: Color(0x3D000000), blurRadius: 9, offset: Offset(0, 3)),
    ],
    headingFontFamily: null,
    commandRadius: 15,
    controlRadius: 14,
    toolRadius: 13,
    inlineRadius: 10,
    keycapRadius: 4,
    compactRadius: 11,
    surfaceRadius: 12,
  );

  /// Navy leather, restrained gilt trim and vellum reading surfaces matching
  /// the planner's Illuminated Ledger skin.
  static const illuminatedAtlas = ResourceMapChromeThemeData(
    variant: ResourceMapChromeThemeVariant.illuminatedAtlas,
    canvas: Color(0xFF0B1420),
    paper: Color(0xFF101C2C),
    paperRaised: Color(0xFF16263A),
    ink: Color(0xFFF2E5C2),
    text: Color(0xFFD9C9A4),
    muted: Color(0xFFA99976),
    warmOutline: Color(0x998B6C32),
    softOutline: Color(0xB36E5528),
    primary: Color(0xFFD4A94F),
    deepAccent: Color(0xFF581F2B),
    onPrimary: Color(0xFF101722),
    accent: Color(0xFFE6C66F),
    positive: Color(0xFF77B79A),
    warning: Color(0xFFE0A952),
    error: Color(0xFFD87970),
    chromeBase: Color(0xFF091321),
    chromeRaised: Color(0xFF13233A),
    chromeHighlight: Color(0xFF203653),
    modeStripFadeColor: Color(0xF0091321),
    trimDeep: Color(0xFF76591F),
    trimLine: Color(0xFFC39A43),
    trimWash: Color(0x2ED9B65C),
    idleControlGradient: LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: <Color>[Color(0xF51B2B42), Color(0xFA0C1828)],
    ),
    idleCompactGradient: LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: <Color>[Color(0xE61B2B42), Color(0xE60C1828)],
    ),
    hoverControlGradient: LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: <Color>[Color(0xFF263C58), Color(0xFF112039)],
    ),
    selectedControlGradient: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: <Color>[Color(0xFF6A2631), Color(0xFF3F1B29), Color(0xFF17233A)],
      stops: <double>[0, .52, 1],
    ),
    selectedModeGradient: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: <Color>[Color(0xFF6A2631), Color(0xFF3B1B2A), Color(0xFF17233A)],
      stops: <double>[0, .52, 1],
    ),
    selectedCompactGradient: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: <Color>[Color(0xFF642833), Color(0xFF15253C)],
    ),
    selectedInlineGradient: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: <Color>[Color(0xFF642833), Color(0xFF14243A)],
    ),
    idleInlineGradient: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: <Color>[Color(0xEE17283E), Color(0xEE0A1726)],
    ),
    idleSearchGradient: LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: <Color>[Color(0xFA17283E), Color(0xFA0A1726)],
    ),
    focusedSearchGradient: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: <Color>[Color(0xFF243A54), Color(0xFF0D1A2A)],
    ),
    surfaceGradient: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: <Color>[Color(0xFA1B2C43), Color(0xFA101D2E), Color(0xFA091421)],
      stops: <double>[0, .48, 1],
    ),
    subtleSurfaceGradient: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: <Color>[Color(0xE61A2A3F), Color(0xE60E1A29), Color(0xE608111D)],
      stops: <double>[0, .48, 1],
    ),
    taskStripGradient: LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: <Color>[Color(0xFA1B2E48), Color(0xFA0A1727)],
    ),
    readingSurfaceGradient: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: <Color>[Color(0xFFF1E4BE), Color(0xFFE0CFA3)],
    ),
    edgeFadeGradient: LinearGradient(
      begin: Alignment.centerLeft,
      end: Alignment.centerRight,
      colors: <Color>[
        Color(0xFC091421),
        Color(0xF7091421),
        Color(0xE6091421),
        Color(0x00091421),
      ],
      stops: <double>[0, .78, .88, 1],
    ),
    contourColor: Color(0x12D8B85D),
    fleckColor: Color(0x14E3D0A1),
    readingInk: Color(0xFF302516),
    readingMuted: Color(0xFF746342),
    readingOutline: Color(0xFF9D7935),
    idleShadow: BoxShadow(
      color: Color(0x66020A13),
      blurRadius: 10,
      offset: Offset(0, 4),
    ),
    selectedShadow: BoxShadow(
      color: Color(0x4DD4A94F),
      blurRadius: 12,
      offset: Offset(0, 4),
    ),
    hoverShadow: BoxShadow(
      color: Color(0x33D4A94F),
      blurRadius: 10,
      offset: Offset(0, 3),
    ),
    surfaceShadows: <BoxShadow>[
      BoxShadow(color: Color(0x73020A13), blurRadius: 14, offset: Offset(0, 5)),
      BoxShadow(color: Color(0x24D4A94F), blurRadius: 0, offset: Offset(0, 1)),
    ],
    subtleSurfaceShadows: <BoxShadow>[
      BoxShadow(color: Color(0x59020A13), blurRadius: 8, offset: Offset(0, 3)),
    ],
    headingFontFamily: 'Georgia',
    commandRadius: 8,
    controlRadius: 8,
    toolRadius: 7,
    inlineRadius: 7,
    keycapRadius: 3,
    compactRadius: 6,
    surfaceRadius: 7,
  );
}

/// Installs a package-owned Resource Map chrome skin below this point.
///
/// Without a scope, the neutral [ResourceMapChromeThemeData.fieldAtlas] skin
/// keeps the package visually independent from an embedding application.
class ResourceMapChromeTheme extends InheritedTheme {
  const ResourceMapChromeTheme({
    required this.data,
    required super.child,
    super.key,
  });

  final ResourceMapChromeThemeData data;

  static ResourceMapChromeThemeData of(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<ResourceMapChromeTheme>()
          ?.data ??
      ResourceMapChromeThemeData.fieldAtlas;

  static ResourceMapChromeThemeData? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<ResourceMapChromeTheme>()
      ?.data;

  @override
  bool updateShouldNotify(ResourceMapChromeTheme oldWidget) =>
      data != oldWidget.data;

  @override
  Widget wrap(BuildContext context, Widget child) =>
      ResourceMapChromeTheme(data: data, child: child);
}

extension ResourceMapChromeBuildContext on BuildContext {
  ResourceMapChromeThemeData get mapChrome => ResourceMapChromeTheme.of(this);
}
