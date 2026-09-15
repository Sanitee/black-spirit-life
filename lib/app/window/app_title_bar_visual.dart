import 'package:bdo_map_core/bdo_map_core.dart';
import 'package:flutter/material.dart';

import '../../features/opportunities/opportunities_visuals.dart';

/// A restrained title-strip palette owned by a non-planner workspace.
///
/// Planner deliberately does not use one of these overrides: its title strip
/// continues to resolve from the user's selected Planner appearance. The
/// Resource Map and Opportunities use the same color roles as their accepted
/// surfaces so switching the top-level destination does not carry a Planner
/// theme over an otherwise distinct workspace.
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

  static final gathering = AppTitleBarVisual(
    id: 'gathering-journal',
    titleGradient: const LinearGradient(
      begin: Alignment.centerLeft,
      end: Alignment.centerRight,
      colors: [Color(0xFF07100D), Color(0xFF13231B), Color(0xFF0A1110)],
      stops: [0, .58, 1],
    ),
    titleDivider: const Color(0xFF355C48),
    foreground: const Color(0xFFE7F2EA),
    iconBorder: const Color(0xFF4C765E),
    tabAccent: const Color(0xFF7ABF8C),
    tabSurface: const Color(0xFF0A1110),
    tabSelectedSurface: const Color(0xFF254333),
    tabHoverSurface: const Color(0xFF172720),
    tabPressedSurface: const Color(0xFF07100D),
    tabDivider: const Color(0xFF355C48),
    tabForeground: const Color(0xFFA8B9AD),
    tabSelectedForeground: const Color(0xFFE7F2EA),
    tabHoverForeground: const Color(0xFF9ED9AC),
    captionHoverSurface: const Color(0xFF172720),
    captionPressedSurface: const Color(0xFF254333),
  );

  static final fishing = AppTitleBarVisual(
    id: 'fishing-journal',
    titleGradient: const LinearGradient(
      begin: Alignment.centerLeft,
      end: Alignment.centerRight,
      colors: [Color(0xFF100A12), Color(0xFF281329), Color(0xFF110B14)],
      stops: [0, .58, 1],
    ),
    titleDivider: const Color(0xFF6C365F),
    foreground: const Color(0xFFFFEDF7),
    iconBorder: const Color(0xFF864471),
    tabAccent: const Color(0xFFF18AC4),
    tabSurface: const Color(0xFF110B14),
    tabSelectedSurface: const Color(0xFF51243F),
    tabHoverSurface: const Color(0xFF32182A),
    tabPressedSurface: const Color(0xFF100A12),
    tabDivider: const Color(0xFF6C365F),
    tabForeground: const Color(0xFFC5A8B9),
    tabSelectedForeground: const Color(0xFFFFEDF7),
    tabHoverForeground: const Color(0xFFFFA9D8),
    captionHoverSurface: const Color(0xFF32182A),
    captionPressedSurface: const Color(0xFF51243F),
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
