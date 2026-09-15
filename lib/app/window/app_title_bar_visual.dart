import 'package:bdo_map_core/bdo_map_core.dart';
import 'package:flutter/material.dart';

import '../../features/opportunities/opportunities_visuals.dart';

/// A restrained title-strip palette owned by a non-planner workspace.
///
/// Planner deliberately does not use one of these overrides: its title strip
/// continues to resolve from the user's selected Planner appearance. The
/// Resource Map, Gathering, and Fish Map use the same color roles as their
/// accepted surfaces so switching the top-level destination does not carry a
/// Planner theme over an otherwise 1:1 embedded application.
@immutable
class AppTitleBarVisual {
  const AppTitleBarVisual({
    required this.id,
    required this.titleGradient,
    required this.titleDivider,
    required this.foreground,
    required this.iconBorder,
    required this.tabAccent,
    required this.tabSurface,
    required this.tabSelectedSurface,
    required this.tabHoverSurface,
    required this.tabPressedSurface,
    required this.tabDivider,
    required this.tabForeground,
    required this.tabSelectedForeground,
    required this.tabHoverForeground,
    required this.captionHoverSurface,
    required this.captionPressedSurface,
    this.tabRadius = 8,
    this.fontFamily = 'Segoe UI',
  });

  final String id;
  final LinearGradient titleGradient;
  final Color titleDivider;
  final Color foreground;
  final Color iconBorder;
  final Color tabAccent;
  final Color tabSurface;
  final Color tabSelectedSurface;
  final Color tabHoverSurface;
  final Color tabPressedSurface;
  final Color tabDivider;
  final Color tabForeground;
  final Color tabSelectedForeground;
  final Color tabHoverForeground;
  final Color captionHoverSurface;
  final Color captionPressedSurface;
  final double tabRadius;
  final String fontFamily;

  BoxDecoration get titleDecoration => BoxDecoration(
    gradient: titleGradient,
    border: Border(bottom: BorderSide(color: titleDivider)),
  );

  /// Resolves the current package-owned map palettes, not a historical tint.
  static final resourceMap = _mapVisual(ResourceMapChromeThemeData.glassDock);
  static final resourceMapGhost = _mapVisual(
    ResourceMapChromeThemeData.ghostLedger,
  );

  static AppTitleBarVisual _mapVisual(ResourceMapChromeThemeData chrome) =>
      AppTitleBarVisual(
        id: 'resource-map-${chrome.variant.name}',
        titleGradient: LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [chrome.canvas, chrome.chromeRaised, chrome.chromeBase],
          stops: const [0, .58, 1],
        ),
        titleDivider: chrome.trimLine.withAlpha(128),
        foreground: chrome.ink,
        iconBorder: chrome.warmOutline,
        tabAccent: chrome.primary,
        tabSurface: chrome.chromeBase,
        tabSelectedSurface: chrome.deepAccent,
        tabHoverSurface: chrome.chromeHighlight,
        tabPressedSurface: chrome.canvas,
        tabDivider: chrome.warmOutline,
        tabForeground: chrome.muted,
        tabSelectedForeground: chrome.ink,
        tabHoverForeground: chrome.text,
        captionHoverSurface: chrome.chromeHighlight,
        captionPressedSurface: chrome.deepAccent,
      );

  static final opportunities = AppTitleBarVisual(
    id: OpportunitiesVisualSpec.id,
    titleGradient: LinearGradient(
      begin: Alignment.centerLeft,
      end: Alignment.centerRight,
      colors: [
        OpportunitiesVisualSpec.palette.canvasDeep,
        OpportunitiesVisualSpec.palette.canvas,
        OpportunitiesVisualSpec.palette.surfaceInset,
      ],
      stops: [0, .58, 1],
    ),
    titleDivider: OpportunitiesVisualSpec.palette.trim,
    foreground: OpportunitiesVisualSpec.palette.text,
    iconBorder: OpportunitiesVisualSpec.palette.trimBright,
    tabAccent: OpportunitiesVisualSpec.palette.primary,
    tabSurface: OpportunitiesVisualSpec.palette.surfaceInset,
    tabSelectedSurface: OpportunitiesVisualSpec.palette.surfaceRaised,
    tabHoverSurface: OpportunitiesVisualSpec.palette.surface,
    tabPressedSurface: OpportunitiesVisualSpec.palette.canvasDeep,
    tabDivider: OpportunitiesVisualSpec.palette.trim,
    tabForeground: OpportunitiesVisualSpec.palette.textMuted,
    tabSelectedForeground: OpportunitiesVisualSpec.palette.text,
    tabHoverForeground: OpportunitiesVisualSpec.palette.primaryBright,
    captionHoverSurface: OpportunitiesVisualSpec.palette.surface,
    captionPressedSurface: OpportunitiesVisualSpec.palette.surfaceInset,
  );

  /// Continues the Gathering field-journal's midnight and luminous teal roles.
  static const gathering = AppTitleBarVisual(
    id: 'gathering',
    titleGradient: LinearGradient(
      begin: Alignment.centerLeft,
      end: Alignment.centerRight,
      colors: <Color>[Color(0xFF0C151D), Color(0xFF1B2D38), Color(0xFF11252C)],
      stops: <double>[0, .58, 1],
    ),
    titleDivider: Color(0xA6638695),
    foreground: Color(0xFFF1F3ED),
    iconBorder: Color(0xFF638695),
    tabAccent: Color(0xFF7DE0D3),
    tabSurface: Color(0xFF14232E),
    tabSelectedSurface: Color(0xFF214A4D),
    tabHoverSurface: Color(0xFF2A424E),
    tabPressedSurface: Color(0xFF102A31),
    tabDivider: Color(0xFF638695),
    tabForeground: Color(0xFFB3C2C5),
    tabSelectedForeground: Color(0xFFF1F3ED),
    tabHoverForeground: Color(0xFFD8F2EE),
    captionHoverSurface: Color(0xFF2A424E),
    captionPressedSurface: Color(0xFF102A31),
  );

  /// Dark navy from the Fish Companion shell with its prize-fish burgundy.
  ///
  /// The burgundy is confined to the title strip and selection state; the
  /// embedded Fish Companion remains byte-for-byte owned by its standalone
  /// source and is never recolored by this wrapper.
  static const fishMap = AppTitleBarVisual(
    id: 'fish-map',
    titleGradient: LinearGradient(
      begin: Alignment.centerLeft,
      end: Alignment.centerRight,
      colors: <Color>[Color(0xFF0A0E12), Color(0xFF111A22), Color(0xFF24131A)],
      stops: <double>[0, .58, 1],
    ),
    titleDivider: Color(0xA6FA6384),
    foreground: Color(0xFFF2F5F7),
    iconBorder: Color(0xFF8A4658),
    tabAccent: Color(0xFFFA6384),
    tabSurface: Color(0xFF111A22),
    tabSelectedSurface: Color(0xFF3A1D28),
    tabHoverSurface: Color(0xFF28202A),
    tabPressedSurface: Color(0xFF0A0E12),
    tabDivider: Color(0xFF714052),
    tabForeground: Color(0xFFB8C7CE),
    tabSelectedForeground: Color(0xFFFFE6EC),
    tabHoverForeground: Color(0xFFFFD2DC),
    captionHoverSurface: Color(0xFF28202A),
    captionPressedSurface: Color(0xFF3A1D28),
  );
}

/// Supplies a non-planner title-strip visual without changing ThemeSpec or
/// any persisted Planner appearance value.
class AppTitleBarVisualScope extends InheritedWidget {
  const AppTitleBarVisualScope({
    required this.visual,
    required super.child,
    super.key,
  });

  final AppTitleBarVisual visual;

  static AppTitleBarVisual? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<AppTitleBarVisualScope>()
      ?.visual;

  @override
  bool updateShouldNotify(AppTitleBarVisualScope oldWidget) =>
      oldWidget.visual != visual;
}
