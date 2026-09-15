import 'package:bdo_map_core/bdo_map_core.dart';
import 'package:flutter/material.dart';

import '../../domain/state/planner_state.dart';
import '../../features/opportunities/opportunities_visuals.dart';
import '../../visual/visual.dart';
import '../state/planner_application_controller.dart';
import '../window/app_title_bar_visual.dart';

enum ApplicationWorkspaceDestination {
  planner,
  resourceMap,
  gathering,
  fishing,
  opportunities,
}

/// Presentation only: never writes a Planner or standalone appearance setting.
@immutable
class ApplicationWorkspacePresentation {
  const ApplicationWorkspacePresentation({
    required this.spec,
    required this.standardSettings,
    this.titleVisual,
  });
  factory ApplicationWorkspacePresentation.resolve({
    required ApplicationWorkspaceDestination destination,
    required AppearanceSettings appearance,
    required ResourceMapInterfaceStyle mapStyle,
  }) {
    if (destination == ApplicationWorkspaceDestination.planner) {
      return ApplicationWorkspacePresentation(
        spec: RetainedThemeRegistry.resolve(
          backgroundId: appearance.background,
        ),
        standardSettings: StandardVisualSettings(
          backgroundId: appearance.background,
          accentHue: appearance.accentHue,
          rainbow: appearance.rainbow,
          neon: appearance.neon,
        ),
      );
    }
    final map = mapStyle == ResourceMapInterfaceStyle.ghostLedger
        ? ResourceMapChromeThemeData.ghostLedger
        : ResourceMapChromeThemeData.glassDock;
    final visual = switch (destination) {
      ApplicationWorkspaceDestination.resourceMap =>
        mapStyle == ResourceMapInterfaceStyle.ghostLedger
            ? AppTitleBarVisual.resourceMapGhost
            : AppTitleBarVisual.resourceMap,
      ApplicationWorkspaceDestination.gathering => AppTitleBarVisual.gathering,
      ApplicationWorkspaceDestination.fishing => AppTitleBarVisual.fishing,
      ApplicationWorkspaceDestination.opportunities =>
        AppTitleBarVisual.opportunities,
      ApplicationWorkspaceDestination.planner => throw StateError(
        'Planner resolved above',
      ),
    };
    final palette = switch (destination) {
      ApplicationWorkspaceDestination.opportunities =>
        OpportunitiesVisualSpec.palette,
      ApplicationWorkspaceDestination.resourceMap => _palette(
        visual,
        surface: map.paper,
        raised: map.paperRaised,
        positive: map.positive,
        warning: map.warning,
        danger: map.error,
      ),
      ApplicationWorkspaceDestination.gathering => _palette(visual),
      ApplicationWorkspaceDestination.fishing => _palette(visual),
      _ => _palette(visual),
    };
    final reading = switch (destination) {
      ApplicationWorkspaceDestination.opportunities =>
        OpportunitiesVisualSpec.overlay,
      ApplicationWorkspaceDestination.resourceMap => _opaque(
        map.readingSurfaceGradient,
      ),
      ApplicationWorkspaceDestination.gathering => LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [visual.tabHoverSurface, visual.tabSurface],
      ),
      ApplicationWorkspaceDestination.fishing => LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [visual.tabHoverSurface, visual.tabSurface],
      ),
      _ => LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [visual.tabHoverSurface, visual.tabSurface],
      ),
    };
    final base = StandardSpec.theme;
    final spec = ThemeSpec(
      id: 'application-chrome-${visual.id}',
      displayName: visual.id,
      family: RetainedVisualFamily.standard,
      layoutProfile: base.layoutProfile,
      brightness: Brightness.dark,
      palette: palette,
      typography: ThemeTypography(
        display: base.typography.display.copyWith(
          color: palette.text,
          fontFamily: visual.fontFamily,
        ),
        section: base.typography.section.copyWith(
          color: palette.text,
          fontFamily: visual.fontFamily,
        ),
        body: base.typography.body.copyWith(
          color: palette.text,
          fontFamily: visual.fontFamily,
        ),
        meta: base.typography.meta.copyWith(
          color: palette.textMuted,
          fontFamily: visual.fontFamily,
        ),
        label: base.typography.label.copyWith(
          color: palette.textMuted,
          fontFamily: visual.fontFamily,
        ),
        button: base.typography.button.copyWith(
          color: palette.text,
          fontFamily: visual.fontFamily,
        ),
      ),
      geometry: base.geometry,
      materials: ThemeMaterials(
        canvas: visual.titleGradient,
        surface: reading,
        surfaceRaised: reading,
        primary: LinearGradient(
          colors: [visual.tabSelectedSurface, visual.tabPressedSurface],
        ),
        secondary: reading,
        modalScrim: base.materials.modalScrim,
        lowShadow: base.materials.lowShadow,
        highShadow: base.materials.highShadow,
      ),
      motion: const ThemeMotionCapabilities(
        interactionDuration: Duration(milliseconds: 140),
        supportsAtmosphere: false,
        supportsButtonEffects: false,
        supportsOrnament: false,
      ),
    );
    return ApplicationWorkspacePresentation(
      spec: spec,
      titleVisual: visual,
      standardSettings: StandardVisualSettings(
        backgroundId: spec.id,
        accentHue: HSVColor.fromColor(palette.primary).hue,
      ),
    );
  }

  final ThemeSpec spec;
  final StandardVisualSettings standardSettings;
  final AppTitleBarVisual? titleVisual;

  static ThemePalette _palette(
    AppTitleBarVisual visual, {
    Color? surface,
    Color? raised,
    Color? positive,
    Color? warning,
    Color? danger,
  }) => ThemePalette(
    canvas: visual.titleGradient.colors.first,
    canvasDeep: visual.titleGradient.colors.last,
    surface: (surface ?? visual.tabSurface).withAlpha(255),
    surfaceRaised: (raised ?? visual.tabHoverSurface).withAlpha(255),
    surfaceInset: visual.tabPressedSurface,
    primary: visual.tabAccent,
    primaryBright: visual.tabHoverForeground,
    secondary: visual.tabAccent,
    trim: visual.tabDivider,
    trimBright: visual.iconBorder,
    text: visual.foreground,
    textMuted: visual.tabForeground,
    success: positive ?? visual.tabAccent,
    warning: warning ?? StandardSpec.theme.palette.warning,
    danger: danger ?? StandardSpec.theme.palette.danger,
    shadow: const Color(0x99000000),
    specular: visual.tabAccent.withAlpha(72),
  );

  static LinearGradient _opaque(LinearGradient gradient) => LinearGradient(
    begin: gradient.begin,
    end: gradient.end,
    stops: gradient.stops,
    colors: gradient.colors
        .map((color) => color.withAlpha(255))
        .toList(growable: false),
    tileMode: gradient.tileMode,
    transform: gradient.transform,
  );
}

/// One observable source for shared chrome, including overlays already open.
/// Only appearance/destination changes notify; market receipts and planning do
/// not re-theme the shell, and there is no animation or polling timer here.
class ApplicationWorkspacePresentationController
    extends ValueNotifier<ApplicationWorkspacePresentation> {
  ApplicationWorkspacePresentationController(this.controller)
    : super(
        ApplicationWorkspacePresentation.resolve(
          destination: ApplicationWorkspaceDestination.planner,
          appearance: controller.active.state.value.appearance,
          mapStyle: controller.resourceMapInterfaceStyle.value,
        ),
      ) {
    _mode = controller.active;
    controller.activeMode.addListener(_modeChanged);
    controller.resourceMapInterfaceStyle.addListener(_refresh);
    _mode.state.addListener(_refresh);
    _refresh();
  }
  final PlannerApplicationController controller;
  late ModeFeatureController _mode;
  ApplicationWorkspaceDestination _destination =
      ApplicationWorkspaceDestination.planner;
  Object? _identity;
  void select(ApplicationWorkspaceDestination destination) {
    if (_destination == destination) return;
    _destination = destination;
    _refresh();
  }

  void _modeChanged() {
    _mode.state.removeListener(_refresh);
    _mode = controller.active;
    _mode.state.addListener(_refresh);
    _refresh();
  }

  void _refresh() {
    final appearance = _mode.state.value.appearance;
    final mapStyle = controller.resourceMapInterfaceStyle.value;
    final identity = (
      _destination,
      _destination == ApplicationWorkspaceDestination.planner
          ? appearance
          : null,
      _destination == ApplicationWorkspaceDestination.resourceMap
          ? mapStyle
          : null,
    );
    if (_identity == identity) return;
    _identity = identity;
    value = ApplicationWorkspacePresentation.resolve(
      destination: _destination,
      appearance: appearance,
      mapStyle: mapStyle,
    );
  }

  @override
  void dispose() {
    controller.activeMode.removeListener(_modeChanged);
    controller.resourceMapInterfaceStyle.removeListener(_refresh);
    _mode.state.removeListener(_refresh);
    super.dispose();
  }
}
