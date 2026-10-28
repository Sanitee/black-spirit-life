import 'package:bdo_map_core/bdo_map_core.dart';
import 'package:flutter/material.dart';

import '../../features/opportunities/opportunities_visuals.dart';

/// A restrained title-strip palette owned by a non-planner workspace.
///
/// Planner deliberately does not use one of these overrides: its title strip
/// continues to resolve from the user's selected Planner appearance. The
/// Resource Map, Gathering, and Fish Map use the experimental field-desk roles
/// so their shared navigation matches the destination beneath it.
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

  static final opportunities = opportunitiesFinish('bronze');
  static final _opportunityFinishes = <String, AppTitleBarVisual>{};
  static AppTitleBarVisual opportunitiesFinish(String finish) =>
      _opportunityFinishes.putIfAbsent(finish, () {
        final spec = OpportunitiesVisualSpec.forFinish(finish);
        final palette = spec.palette;
        return AppTitleBarVisual(
          id: spec.id,
          titleGradient: LinearGradient(
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
            colors: [palette.canvasDeep, palette.canvas, palette.surfaceInset],
            stops: [0, .58, 1],
          ),
          titleDivider: palette.trim,
          foreground: palette.text,
          iconBorder: palette.trimBright,
          tabAccent: palette.primary,
          tabSurface: palette.surfaceInset,
          tabSelectedSurface: palette.surfaceRaised,
          tabHoverSurface: palette.surface,
          tabPressedSurface: palette.canvasDeep,
          tabDivider: palette.trim,
          tabForeground: palette.textMuted,
          tabSelectedForeground: palette.text,
          tabHoverForeground: palette.primaryBright,
          captionHoverSurface: palette.surface,
          captionPressedSurface: palette.surfaceInset,
        );
      });

  /// Experimental field-desk chrome; Planner never receives this override.
  static const gathering = AppTitleBarVisual(
    id: 'gathering',
    titleGradient: LinearGradient(
      begin: Alignment.centerLeft,
      end: Alignment.centerRight,
      colors: [Color(0xFF141218), Color(0xFF342B32), Color(0xFF1D1920)],
      stops: [0, .58, 1],
    ),
    titleDivider: Color(0x668D7274),
    foreground: Color(0xFFF1E8D8),
    iconBorder: Color(0xFF8D7274),
    tabAccent: Color(0xFFC88D91),
    tabSurface: Color(0xFF211C24),
    tabSelectedSurface: Color(0xFF51343D),
    tabHoverSurface: Color(0xFF46333D),
    tabPressedSurface: Color(0xFF241C26),
    tabDivider: Color(0xFF8D7274),
    tabForeground: Color(0xFFB9ABB1),
    tabSelectedForeground: Color(0xFFF1E8D8),
    tabHoverForeground: Color(0xFFF2DCC0),
    captionHoverSurface: Color(0xFF46333D),
    captionPressedSurface: Color(0xFF241C26),
  );

  static const fishMap = AppTitleBarVisual(
    id: 'fish-map',
    titleGradient: LinearGradient(
      begin: Alignment.centerLeft,
      end: Alignment.centerRight,
      colors: [Color(0xFF141218), Color(0xFF342B32), Color(0xFF1D1920)],
      stops: [0, .58, 1],
    ),
    titleDivider: Color(0x668D7274),
    foreground: Color(0xFFF1E8D8),
    iconBorder: Color(0xFF8D7274),
    tabAccent: Color(0xFFC88D91),
    tabSurface: Color(0xFF211C24),
    tabSelectedSurface: Color(0xFF51343D),
    tabHoverSurface: Color(0xFF46333D),
    tabPressedSurface: Color(0xFF241C26),
    tabDivider: Color(0xFF8D7274),
    tabForeground: Color(0xFFB9ABB1),
    tabSelectedForeground: Color(0xFFF1E8D8),
    tabHoverForeground: Color(0xFFF2DCC0),
    captionHoverSurface: Color(0xFF46333D),
    captionPressedSurface: Color(0xFF241C26),
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
