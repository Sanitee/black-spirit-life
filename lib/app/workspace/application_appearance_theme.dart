import 'package:flutter/foundation.dart';

import '../../visual/foundations/application_theme.dart';
import '../../visual/foundations/theme_spec.dart';
import '../state/planner_application_controller.dart';

/// One live theme source for non-Fish features. Inventory, prices and timer
/// receipts do not notify it; retained tabs and their controllers stay mounted.
class ApplicationAppearanceThemeController extends ValueNotifier<ThemeSpec> {
  ApplicationAppearanceThemeController(this.controller)
    : super(
        applicationThemeForAppearance(controller.active.state.value.appearance),
      ) {
    _mode = controller.active;
    controller.activeMode.addListener(_modeChanged);
    _mode.state.addListener(_refresh);
    _refresh();
  }

  final PlannerApplicationController controller;
  late ModeFeatureController _mode;
  Object? _identity;

  void _modeChanged() {
    _mode.state.removeListener(_refresh);
    _mode = controller.active;
    _mode.state.addListener(_refresh);
    _refresh();
  }

  void _refresh() {
    final appearance = _mode.state.value.appearance;
    final identity = (
      appearance.background,
      appearance.accentHue,
      appearance.neon,
    );
    if (identity == _identity) return;
    _identity = identity;
    value = applicationThemeForAppearance(appearance);
  }

  @override
  void dispose() {
    controller.activeMode.removeListener(_modeChanged);
    _mode.state.removeListener(_refresh);
    super.dispose();
  }
}
