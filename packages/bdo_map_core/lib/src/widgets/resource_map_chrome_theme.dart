import 'package:flutter/material.dart';

/// The visual language used by the Resource Map's package-owned chrome.
///
/// This deliberately lives in `bdo_map_core`: applications can select a map
/// skin without making the reusable map package depend on an app theme model.
enum ResourceMapChromeThemeVariant { sakuraCartographer, illuminatedAtlas }

/// Semantic colors, materials and geometry for Resource Map controls.
///
/// Map features should consume these roles through [ResourceMapChromeTheme]
/// rather than branching on [variant]. That keeps app-selected skins coherent
/// and allows future themes to be supplied without changing map widgets.
@immutable
class ResourceMapChromeThemeData {
  const ResourceMapChromeThemeData({
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
/// Without a scope, [ResourceMapChromeThemeData.sakuraCartographer] is used to
/// preserve existing embedder behavior.
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
      ResourceMapChromeThemeData.sakuraCartographer;

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
