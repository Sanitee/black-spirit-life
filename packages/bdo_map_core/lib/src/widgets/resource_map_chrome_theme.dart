import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../model/map_ui_opacity.dart';
import 'resource_map_annotation_clip.dart';

/// Keeps ordinary action labels semantic without opening hover text.
class MapQuietTooltip extends Tooltip {
  const MapQuietTooltip({
    super.key,
    super.message,
    super.richMessage,
    super.constraints,
    super.padding,
    super.margin,
    super.verticalOffset,
    super.preferBelow,
    super.excludeFromSemantics,
    super.decoration,
    super.textStyle,
    super.textAlign,
    super.waitDuration,
    super.showDuration,
    super.exitDuration,
    super.enableTapToDismiss,
    super.triggerMode,
    super.enableFeedback,
    super.onTriggered,
    super.mouseCursor,
    super.ignorePointer,
    super.positionDelegate,
    super.child,
  });

  @override
  TooltipState createState() => _MapQuietTooltipState();
}

class _MapQuietTooltipState extends TooltipState {
  @override
  Widget build(BuildContext context) {
    final hint = widget as MapQuietTooltip;
    final excluded =
        hint.excludeFromSemantics ??
        TooltipTheme.of(context).excludeFromSemantics ??
        false;
    return Semantics(
      tooltip: excluded
          ? null
          : hint.message ?? hint.richMessage?.toPlainText(),
      child: hint.child ?? const SizedBox.shrink(),
    );
  }
}

/// Keeps icon-button action names in accessibility without opening hover text.
class MapQuietIconButton extends IconButton {
  const MapQuietIconButton({
    super.key,
    super.iconSize,
    super.visualDensity,
    super.padding,
    super.alignment,
    super.splashRadius,
    super.color,
    super.focusColor,
    super.hoverColor,
    super.highlightColor,
    super.splashColor,
    super.disabledColor,
    required super.onPressed,
    super.onHover,
    super.onLongPress,
    super.mouseCursor,
    super.focusNode,
    super.autofocus,
    super.tooltip,
    super.enableFeedback,
    super.constraints,
    super.style,
    super.isSelected,
    super.selectedIcon,
    super.statesController,
    required super.icon,
    this.approvedHover = false,
  });

  final bool approvedHover;

  @override
  Widget build(BuildContext context) => approvedHover
      ? super.build(context)
      : Semantics(
          tooltip: tooltip,
          child: TooltipVisibility(visible: false, child: super.build(context)),
        );
}

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
    // Palette constants describe full-strength material. User opacity is
    // applied by withUiOpacity, including the translucent default.
    this.uiOpacity = 1,
    required this.variant,
    required this.canvas,
    this.inputInset,
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
    this.materialAccent,
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
  final Color? inputInset;

  /// Input wells are not the basemap's empty-area colour in a light palette.
  Color get controlInset => inputInset ?? canvas;
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

  /// Bright finish accent; selection retains its separate primary role.
  final Color? materialAccent;
  Color get finishAccent => materialAccent ?? primary;
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

  /// A satin reading plane keeps its colour at intermediate slider settings.
  /// The saved value is untouched; zero retains the existing two-percent floor.
  double get materialOpacity => materialDensity(uiOpacity);

  static double materialDensity(Object? value) {
    final opacity = ResourceMapUiOpacity.material(value);
    const floor = ResourceMapUiOpacity.minimumMaterial;
    final remaining = (1 - opacity) / (1 - floor);
    return floor + (1 - floor) * (1 - remaining * remaining);
  }

  Brightness get brightness => chromeRaised.computeLuminance() > .45
      ? Brightness.light
      : Brightness.dark;

  /// Recolours the existing map material without changing its shape, alpha,
  /// typography or layout. The embedding application supplies semantic colours;
  /// the map package does not need to know about its appearance settings.
  ResourceMapChromeThemeData withPalette({
    required Color canvas,
    required Color surface,
    required Color raised,
    required Color inset,
    required Color foreground,
    required Color secondaryForeground,
    required Color primary,
    required Color primaryBright,
    required Color trim,
    required Color trimBright,
    required Color positive,
    required Color warning,
    required Color error,
    required Color shadow,
  }) {
    Color tint(Color base, Color accent, double amount) =>
        Color.lerp(base, accent, amount)!;
    Color alpha(Color colour, Color original) =>
        colour.withValues(alpha: original.a);
    LinearGradient gradient(LinearGradient original, Color top, Color bottom) =>
        LinearGradient(
          begin: original.begin,
          end: original.end,
          colors: [
            for (var i = 0; i < original.colors.length; i++)
              alpha(
                tint(top, bottom, i / (original.colors.length - 1)),
                original.colors[i],
              ),
          ],
          stops: original.stops,
          tileMode: original.tileMode,
          transform: original.transform,
        );
    BoxShadow recolourShadow(BoxShadow original, Color colour) =>
        original.copyWith(color: alpha(colour, original.color));
    final highlight = tint(raised, primaryBright, .16);
    final selection = tint(raised, primary, .22);
    final selectedEnd = tint(surface, primary, .14);
    const darkInk = Color(0xFF151515);
    const lightInk = Color(0xFFF8F5EF);
    final primaryLight = primary.computeLuminance() + .05;
    final darkContrast = primaryLight / (darkInk.computeLuminance() + .05);
    final lightContrast = (lightInk.computeLuminance() + .05) / primaryLight;
    return ResourceMapChromeThemeData(
      uiOpacity: uiOpacity,
      variant: variant,
      canvas: canvas,
      inputInset: alpha(inset, controlInset),
      paper: alpha(surface, paper),
      paperRaised: alpha(raised, paperRaised),
      ink: foreground,
      text: foreground,
      muted: secondaryForeground,
      warmOutline: alpha(trimBright, warmOutline),
      softOutline: alpha(trim, softOutline),
      primary: primary,
      deepAccent: selectedEnd,
      onPrimary: darkContrast >= lightContrast ? darkInk : lightInk,
      accent: trimBright,
      materialAccent: primaryBright,
      positive: positive,
      warning: warning,
      error: error,
      chromeBase: alpha(surface, chromeBase),
      chromeRaised: alpha(raised, chromeRaised),
      chromeHighlight: alpha(highlight, chromeHighlight),
      modeStripFadeColor: alpha(surface, modeStripFadeColor),
      trimDeep: alpha(tint(surface, trim, .22), trimDeep),
      trimLine: trimBright,
      trimWash: alpha(trimBright, trimWash),
      idleControlGradient: gradient(idleControlGradient, raised, surface),
      idleCompactGradient: gradient(idleCompactGradient, raised, surface),
      hoverControlGradient: gradient(hoverControlGradient, highlight, surface),
      selectedControlGradient: gradient(
        selectedControlGradient,
        selection,
        selectedEnd,
      ),
      selectedModeGradient: gradient(
        selectedModeGradient,
        selection,
        selectedEnd,
      ),
      selectedCompactGradient: gradient(
        selectedCompactGradient,
        selection,
        selectedEnd,
      ),
      selectedInlineGradient: gradient(
        selectedInlineGradient,
        selection,
        selectedEnd,
      ),
      idleInlineGradient: gradient(idleInlineGradient, raised, surface),
      idleSearchGradient: gradient(idleSearchGradient, inset, surface),
      focusedSearchGradient: gradient(focusedSearchGradient, highlight, inset),
      surfaceGradient: gradient(surfaceGradient, raised, surface),
      subtleSurfaceGradient: gradient(subtleSurfaceGradient, raised, surface),
      taskStripGradient: gradient(taskStripGradient, raised, surface),
      readingSurfaceGradient: gradient(readingSurfaceGradient, raised, surface),
      edgeFadeGradient: gradient(edgeFadeGradient, surface, surface),
      contourColor: alpha(trimBright, contourColor),
      fleckColor: alpha(foreground, fleckColor),
      readingInk: foreground,
      readingMuted: secondaryForeground,
      readingOutline: alpha(trim, readingOutline),
      idleShadow: recolourShadow(idleShadow, shadow),
      selectedShadow: recolourShadow(selectedShadow, primary),
      hoverShadow: recolourShadow(hoverShadow, primaryBright),
      surfaceShadows: [
        for (final value in surfaceShadows) recolourShadow(value, shadow),
      ],
      subtleSurfaceShadows: [
        for (final value in subtleSurfaceShadows) recolourShadow(value, shadow),
      ],
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

  /// Multiplies material fills and their shadows. Foreground colours, icons,
  /// geometry and the basemap canvas are deliberately retained verbatim.
  ResourceMapChromeThemeData withUiOpacity(Object? value) {
    final opacity = ResourceMapUiOpacity.normalize(value);
    if (opacity == uiOpacity) return this;
    final multiplier = materialDensity(opacity) / materialOpacity;
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
      inputInset: inputInset == null ? null : fade(controlInset),
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
      materialAccent: materialAccent,
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

  /// Beta by Codex field desk: charcoal and plum reading planes, ivory type
  /// and a quiet brass rim. Static material leaves the map free to move.
  static const fieldAtlas = ResourceMapChromeThemeData(
    variant: ResourceMapChromeThemeVariant.fieldAtlas,
    canvas: Color(0xFF141218),
    paper: Color(0xFF25212A),
    paperRaised: Color(0xFF342B32),
    ink: Color(0xFFF1E8D8),
    text: Color(0xFFE3D7D2),
    muted: Color(0xFFB9ABB1),
    warmOutline: Color(0x99C6A06B),
    softOutline: Color(0x886E5965),
    primary: Color(0xFFC88D91),
    deepAccent: Color(0xFF49313F),
    onPrimary: Color(0xFF141218),
    accent: Color(0xFFC6A06B),
    positive: Color(0xFF8EB79C),
    warning: Color(0xFFE1B880),
    error: Color(0xFFEB978A),
    chromeBase: Color(0xFF1D1921),
    chromeRaised: Color(0xFF2C252E),
    chromeHighlight: Color(0xFF44323E),
    modeStripFadeColor: Color(0xF01D1921),
    trimDeep: Color(0xFF705846),
    trimLine: Color(0xFFC6A06B),
    trimWash: Color(0x24C6A06B),
    idleControlGradient: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: <Color>[Color(0xF03A3039), Color(0xF5242029)],
    ),
    idleCompactGradient: LinearGradient(
      colors: <Color>[Color(0xF0342B32), Color(0xF0211C25)],
    ),
    hoverControlGradient: LinearGradient(
      colors: <Color>[Color(0xFF58404B), Color(0xFF392B37)],
    ),
    selectedControlGradient: LinearGradient(
      colors: <Color>[Color(0xFF654551), Color(0xFF422E3C)],
    ),
    selectedModeGradient: LinearGradient(
      colors: <Color>[Color(0xFF654551), Color(0xFF422E3C)],
    ),
    selectedCompactGradient: LinearGradient(
      colors: <Color>[Color(0xFF654551), Color(0xFF422E3C)],
    ),
    selectedInlineGradient: LinearGradient(
      colors: <Color>[Color(0xFF503844), Color(0xFF332733)],
    ),
    idleInlineGradient: LinearGradient(
      colors: <Color>[Color(0xFF302731), Color(0xFF221D26)],
    ),
    idleSearchGradient: LinearGradient(
      colors: <Color>[Color(0xFF17141B), Color(0xFF201A23)],
    ),
    focusedSearchGradient: LinearGradient(
      colors: <Color>[Color(0xFF3D2E3B), Color(0xFF221B25)],
    ),
    surfaceGradient: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: <Color>[Color(0xE0322932), Color(0xED1B171F)],
    ),
    subtleSurfaceGradient: LinearGradient(
      colors: <Color>[Color(0xF0312832), Color(0xF51D1921)],
    ),
    taskStripGradient: LinearGradient(
      colors: <Color>[Color(0xF0382B35), Color(0xF5231D27)],
    ),
    readingSurfaceGradient: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: <Color>[Color(0xE6322932), Color(0xED29222D), Color(0xF01C1821)],
      stops: <double>[0, .48, 1],
    ),
    edgeFadeGradient: LinearGradient(
      begin: Alignment.centerLeft,
      end: Alignment.centerRight,
      colors: <Color>[Color(0xFA1D1921), Color(0xE61D1921), Color(0x001D1921)],
      stops: <double>[0, .72, 1],
    ),
    contourColor: Color(0x00000000),
    fleckColor: Color(0x00000000),
    readingInk: Color(0xFFF1E8D8),
    readingMuted: Color(0xFFB9ABB1),
    readingOutline: Color(0x99C6A06B),
    idleShadow: BoxShadow(
      color: Color(0x59000000),
      blurRadius: 10,
      offset: Offset(0, 4),
    ),
    selectedShadow: BoxShadow(
      color: Color(0x33C88D91),
      blurRadius: 12,
      offset: Offset(0, 4),
    ),
    hoverShadow: BoxShadow(
      color: Color(0x1FC6A06B),
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

  /// Compact field-desk material over the map.
  ///
  /// The geometry and material treatment live in the interface primitives;
  /// these roles also restyle every dialog, form, notice and data surface that
  /// can be opened from the map.
  static const glassDock = fieldAtlas;

  /// The saved alternate layout retains its ID and feathered control geometry
  /// while participating in the experiment's common field-desk palette.
  static const ghostLedger = ResourceMapChromeThemeData(
    variant: ResourceMapChromeThemeVariant.ghostLedger,
    canvas: Color(0xFF141218),
    paper: Color(0xFF25212A),
    paperRaised: Color(0xFF342B32),
    ink: Color(0xFFF1E8D8),
    text: Color(0xFFE3D7D2),
    muted: Color(0xFFB9ABB1),
    warmOutline: Color(0x99C6A06B),
    softOutline: Color(0x886E5965),
    primary: Color(0xFFC88D91),
    deepAccent: Color(0xFF49313F),
    onPrimary: Color(0xFF141218),
    accent: Color(0xFFC6A06B),
    positive: Color(0xFF8EB79C),
    warning: Color(0xFFE1B880),
    error: Color(0xFFEB978A),
    chromeBase: Color(0xFF1D1921),
    chromeRaised: Color(0xFF2C252E),
    chromeHighlight: Color(0xFF44323E),
    modeStripFadeColor: Color(0xF01D1921),
    trimDeep: Color(0xFF705846),
    trimLine: Color(0xFFC6A06B),
    trimWash: Color(0x24C6A06B),
    idleControlGradient: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: <Color>[Color(0xF03A3039), Color(0xF5242029)],
    ),
    idleCompactGradient: LinearGradient(
      colors: <Color>[Color(0xF0342B32), Color(0xF0211C25)],
    ),
    hoverControlGradient: LinearGradient(
      colors: <Color>[Color(0xFF58404B), Color(0xFF392B37)],
    ),
    selectedControlGradient: LinearGradient(
      colors: <Color>[Color(0xFF654551), Color(0xFF422E3C)],
    ),
    selectedModeGradient: LinearGradient(
      colors: <Color>[Color(0xFF654551), Color(0xFF422E3C)],
    ),
    selectedCompactGradient: LinearGradient(
      colors: <Color>[Color(0xFF654551), Color(0xFF422E3C)],
    ),
    selectedInlineGradient: LinearGradient(
      colors: <Color>[Color(0xFF503844), Color(0xFF332733)],
    ),
    idleInlineGradient: LinearGradient(
      colors: <Color>[Color(0xFF302731), Color(0xFF221D26)],
    ),
    idleSearchGradient: LinearGradient(
      colors: <Color>[Color(0xFF17141B), Color(0xFF201A23)],
    ),
    focusedSearchGradient: LinearGradient(
      colors: <Color>[Color(0xFF3D2E3B), Color(0xFF221B25)],
    ),
    surfaceGradient: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: <Color>[Color(0xE0322932), Color(0xED1B171F)],
    ),
    subtleSurfaceGradient: LinearGradient(
      colors: <Color>[Color(0xF0312832), Color(0xF51D1921)],
    ),
    taskStripGradient: LinearGradient(
      colors: <Color>[Color(0xF0382B35), Color(0xF5231D27)],
    ),
    readingSurfaceGradient: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: <Color>[Color(0xE6322932), Color(0xED29222D), Color(0xF01C1821)],
      stops: <double>[0, .48, 1],
    ),
    edgeFadeGradient: LinearGradient(
      begin: Alignment.centerLeft,
      end: Alignment.centerRight,
      colors: <Color>[Color(0xFA1D1921), Color(0xE61D1921), Color(0x001D1921)],
      stops: <double>[0, .72, 1],
    ),
    contourColor: Color(0x00000000),
    fleckColor: Color(0x00000000),
    readingInk: Color(0xFFF1E8D8),
    readingMuted: Color(0xFFB9ABB1),
    readingOutline: Color(0x99C6A06B),
    idleShadow: BoxShadow(
      color: Color(0x59000000),
      blurRadius: 10,
      offset: Offset(0, 4),
    ),
    selectedShadow: BoxShadow(
      color: Color(0x33C88D91),
      blurRadius: 12,
      offset: Offset(0, 4),
    ),
    hoverShadow: BoxShadow(
      color: Color(0x1FC6A06B),
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
    this.liveData,
    this.opacityOverride,
    super.key,
  });

  final ResourceMapChromeThemeData data;
  // Captured popup themes subscribe to the same source as the retained map.
  // Dialog scopes can retain their opaque reading material independently.
  final ValueListenable<ResourceMapChromeThemeData>? liveData;
  final double? opacityOverride;

  static ValueListenable<ResourceMapChromeThemeData>? liveDataOf(
    BuildContext context,
  ) => context
      .dependOnInheritedWidgetOfExactType<ResourceMapChromeTheme>()
      ?.liveData;

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
      data != oldWidget.data ||
      liveData != oldWidget.liveData ||
      opacityOverride != oldWidget.opacityOverride;

  @override
  Widget wrap(BuildContext context, Widget child) {
    final source = liveData;
    if (source == null) {
      return ResourceMapChromeTheme(data: data, child: child);
    }
    return ValueListenableBuilder<ResourceMapChromeThemeData>(
      valueListenable: source,
      child: child,
      builder: (context, current, child) => ResourceMapChromeTheme(
        data: opacityOverride == null
            ? current
            : current.withUiOpacity(opacityOverride),
        liveData: source,
        opacityOverride: opacityOverride,
        child: child!,
      ),
    );
  }
}

/// Identifies an existing glass backing so nested options do not stack a
/// second full-strength pane over it. Content itself remains fully opaque.
class ResourceMapReadingPlane extends StatelessWidget {
  const ResourceMapReadingPlane({required this.child, super.key});
  final Widget child;

  static bool contains(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_ReadingPlaneScope>() != null;

  @override
  Widget build(BuildContext context) =>
      ResourceMapAnnotationPlane(child: _ReadingPlaneScope(child: child));
}

class _ReadingPlaneScope extends InheritedWidget {
  const _ReadingPlaneScope({required super.child});

  @override
  bool updateShouldNotify(_ReadingPlaneScope oldWidget) => false;
}

extension ResourceMapChromeBuildContext on BuildContext {
  ResourceMapChromeThemeData get mapChrome => ResourceMapChromeTheme.of(this);
}
