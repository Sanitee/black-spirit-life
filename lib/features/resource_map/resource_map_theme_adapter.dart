import 'package:bdo_map_core/bdo_map_core.dart';
import 'package:flutter/material.dart';

import '../../app/state/planner_application_controller.dart';
import '../../visual/foundations/application_theme.dart';
import '../../visual/foundations/theme_spec.dart';

// Isolated physical-display comparison only; normal builds keep Appearance.
const _diagnosticLegacyCanvas = bool.fromEnvironment(
  'BSL_DIAGNOSTIC_RESOURCE_LEGACY_CANVAS',
  defaultValue: false,
);

/// Appearance supplies colours; the saved map style retains its geometry.
ResourceMapChromeThemeData resourceMapChromeThemeForPlannerTheme(
  ThemeSpec spec, {
  ResourceMapInterfaceStyle interfaceStyle =
      ResourceMapInterfaceStyle.glassDock,
}) {
  final base = switch (interfaceStyle) {
    ResourceMapInterfaceStyle.glassDock => ResourceMapChromeThemeData.glassDock,
    ResourceMapInterfaceStyle.ghostLedger =>
      ResourceMapChromeThemeData.ghostLedger,
  };
  final palette = spec.palette;
  return base.withPalette(
    canvas: _diagnosticLegacyCanvas ? base.canvas : palette.resourceMapCanvas,
    surface: palette.surface,
    raised: palette.surfaceRaised,
    inset: palette.surfaceInset,
    foreground: palette.text,
    secondaryForeground: palette.textMuted,
    primary: palette.primary,
    primaryBright: palette.primaryBright,
    trim: palette.trim,
    trimBright: palette.trimBright,
    positive: palette.success,
    warning: palette.warning,
    error: palette.danger,
    shadow: palette.shadow,
  );
}

/// Applies Appearance without changing map preferences or task navigation.
class ResourceMapThemeAdapter extends StatelessWidget {
  const ResourceMapThemeAdapter({
    required this.spec,
    required this.child,
    this.interfaceStyle = ResourceMapInterfaceStyle.glassDock,
    this.uiOpacity = ResourceMapUiOpacity.defaultValue,
    super.key,
  });

  final ThemeSpec spec;
  final Widget child;
  final ResourceMapInterfaceStyle interfaceStyle;
  final double uiOpacity;

  @override
  Widget build(BuildContext context) => ResourceMapChromeTheme(
    data: resourceMapChromeThemeForPlannerTheme(
      spec,
      interfaceStyle: interfaceStyle,
    ).withUiOpacity(uiOpacity),
    child: child,
  );
}

/// Keeps the retained Resource Map mounted while Planner themes change.
class ResourceMapThemeBinding extends StatefulWidget {
  const ResourceMapThemeBinding({
    required this.controller,
    required this.child,
    super.key,
  });

  final PlannerApplicationController controller;
  final Widget child;

  @override
  State<ResourceMapThemeBinding> createState() =>
      _ResourceMapThemeBindingState();
}

class _ResourceMapThemeBindingState extends State<ResourceMapThemeBinding> {
  late ModeFeatureController _activeMode;
  late final ValueNotifier<ResourceMapChromeThemeData> _chrome;
  (String, double, bool, ResourceMapInterfaceStyle, double)? _signature;
  (String, double, bool, ResourceMapInterfaceStyle)? _paletteSignature;
  ResourceMapChromeThemeData? _palette;

  @override
  void initState() {
    super.initState();
    _attach(widget.controller);
    _chrome = ValueNotifier(_resolve());
  }

  @override
  void didUpdateWidget(ResourceMapThemeBinding oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (identical(oldWidget.controller, widget.controller)) return;
    _detach(oldWidget.controller);
    _attach(widget.controller);
    _signature = null;
    _appearanceChanged();
  }

  void _attach(PlannerApplicationController controller) {
    _activeMode = controller.active;
    controller.activeMode.addListener(_activeModeChanged);
    _activeMode.state.addListener(_appearanceChanged);
    controller.resourceMapInterfaceStyle.addListener(_appearanceChanged);
    controller.resourceMapUiOpacity.addListener(_appearanceChanged);
  }

  void _detach(PlannerApplicationController controller) {
    controller.activeMode.removeListener(_activeModeChanged);
    _activeMode.state.removeListener(_appearanceChanged);
    controller.resourceMapInterfaceStyle.removeListener(_appearanceChanged);
    controller.resourceMapUiOpacity.removeListener(_appearanceChanged);
  }

  void _activeModeChanged() {
    _activeMode.state.removeListener(_appearanceChanged);
    _activeMode = widget.controller.active;
    _activeMode.state.addListener(_appearanceChanged);
    _appearanceChanged();
  }

  void _appearanceChanged() {
    final appearance = _activeMode.state.value.appearance;
    final signature = (
      appearance.background,
      appearance.accentHue.isFinite ? appearance.accentHue : 158.0,
      appearance.neon,
      widget.controller.resourceMapInterfaceStyle.value,
      widget.controller.resourceMapUiOpacity.value,
    );
    if (signature == _signature) return;
    _signature = signature;
    _chrome.value = _resolve();
  }

  ResourceMapChromeThemeData _resolve() {
    final appearance = _activeMode.state.value.appearance;
    final paletteSignature = (
      appearance.background,
      appearance.accentHue.isFinite ? appearance.accentHue : 158.0,
      appearance.neon,
      widget.controller.resourceMapInterfaceStyle.value,
    );
    _signature = (
      appearance.background,
      appearance.accentHue.isFinite ? appearance.accentHue : 158.0,
      appearance.neon,
      widget.controller.resourceMapInterfaceStyle.value,
      widget.controller.resourceMapUiOpacity.value,
    );
    if (_paletteSignature != paletteSignature) {
      _paletteSignature = paletteSignature;
      _palette = resourceMapChromeThemeForPlannerTheme(
        applicationThemeForAppearance(appearance),
        interfaceStyle: widget.controller.resourceMapInterfaceStyle.value,
      );
    }
    return _palette!.withUiOpacity(
      widget.controller.resourceMapUiOpacity.value,
    );
  }

  @override
  void dispose() {
    _detach(widget.controller);
    _chrome.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      ValueListenableBuilder<ResourceMapChromeThemeData>(
        valueListenable: _chrome,
        child: widget.child,
        builder: (context, data, child) => ResourceMapChromeTheme(
          data: data,
          liveData: _chrome,
          child: child!,
        ),
      );
}
