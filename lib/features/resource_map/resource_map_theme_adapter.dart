import 'package:bdo_map_core/bdo_map_core.dart';
import 'package:flutter/material.dart';

import '../../app/state/planner_application_controller.dart';
import '../../visual/foundations/theme_registry.dart';
import '../../visual/foundations/theme_spec.dart';

/// Resolves the Resource Map skin paired with an application theme.
///
/// Standard scenes intentionally retain the established Sakura cartographer
/// chrome until a separate Standard map skin is designed and approved.
ResourceMapChromeThemeData resourceMapChromeThemeForPlannerTheme(
  ThemeSpec spec,
) => switch (spec.family) {
  RetainedVisualFamily.illuminatedLedger =>
    ResourceMapChromeThemeData.illuminatedAtlas,
  RetainedVisualFamily.sakuraNightGarden || RetainedVisualFamily.standard =>
    ResourceMapChromeThemeData.sakuraCartographer,
};

/// Applies the map skin that belongs to [spec] without exposing a second map
/// theme choice to the user.
class ResourceMapThemeAdapter extends StatelessWidget {
  const ResourceMapThemeAdapter({
    required this.spec,
    required this.child,
    super.key,
  });

  final ThemeSpec spec;
  final Widget child;

  @override
  Widget build(BuildContext context) => ResourceMapChromeTheme(
    data: resourceMapChromeThemeForPlannerTheme(spec),
    child: child,
  );
}

/// Keeps the retained Resource Map synchronized with the active Planner
/// theme. Only the inherited chrome data changes; [child] remains mounted so
/// its camera, search, checklist, and network-planning state are preserved.
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
  }

  void _detach(PlannerApplicationController controller) {
    controller.activeMode.removeListener(_activeModeChanged);
    _activeMode.state.removeListener(_appearanceChanged);
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
    return ResourceMapThemeAdapter(spec: spec, child: widget.child);
  }
}
