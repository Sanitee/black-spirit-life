import 'package:bdo_map_core/bdo_map_core.dart';
import 'package:flutter/material.dart';

import '../../app/state/planner_application_controller.dart';
import '../../visual/foundations/theme_registry.dart';
import '../../visual/foundations/theme_spec.dart';

/// Resolves the application-independent Resource Map skin.
///
/// The map is a separate workspace, so switching Planner appearances must not
/// restyle its controls or reduce map readability.
ResourceMapChromeThemeData resourceMapChromeThemeForPlannerTheme(
  ThemeSpec spec, {
  ResourceMapInterfaceStyle interfaceStyle =
      ResourceMapInterfaceStyle.glassDock,
}) => switch (interfaceStyle) {
  ResourceMapInterfaceStyle.glassDock => ResourceMapChromeThemeData.glassDock,
  ResourceMapInterfaceStyle.ghostLedger =>
    ResourceMapChromeThemeData.ghostLedger,
};

/// Applies the dedicated map skin without exposing another appearance choice.
/// Both retained IDs use the shared navigation; the saved alternate tint is
/// still respected without rewriting any planner or map preference.
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

  @override
  void initState() {
    super.initState();
    _attach(widget.controller);
  }

  @override
  void didUpdateWidget(ResourceMapThemeBinding oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (identical(oldWidget.controller, widget.controller)) return;
    _detach(oldWidget.controller);
    _attach(widget.controller);
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
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _detach(widget.controller);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final spec = RetainedThemeRegistry.resolve(
      backgroundId: _activeMode.state.value.appearance.background,
    );
    return ResourceMapThemeAdapter(
      spec: spec,
      interfaceStyle: widget.controller.resourceMapInterfaceStyle.value,
      uiOpacity: widget.controller.resourceMapUiOpacity.value,
      child: widget.child,
    );
  }
}
