import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../visual/visual.dart';
import 'opportunities_visuals.dart';

/// The Codex workbench keeps its geometry while following app Appearance.
/// Place this above the feature Navigator so open routes inherit live changes.
class OpportunitiesTheme extends StatelessWidget {
  const OpportunitiesTheme({required this.child, this.theme, super.key});
  final Widget child;
  final ValueListenable<ThemeSpec>? theme;
  static final _materialThemes = Expando<ThemeData>();

  static ThemeData _materialTheme(ThemeSpec spec) =>
      _materialThemes[spec] ??= (() {
        final base = spec.materialTheme();
        return base.copyWith(
          tooltipTheme: base.tooltipTheme.copyWith(
            constraints: const BoxConstraints(minHeight: 32, maxWidth: 340),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              gradient: spec.materials.surfaceRaised,
              borderRadius: BorderRadius.circular(spec.geometry.fieldRadius),
              border: Border.all(color: spec.palette.trim),
              boxShadow: spec.materials.highShadow,
            ),
            textStyle: spec.typography.body,
            waitDuration: const Duration(milliseconds: 450),
          ),
        );
      })();

  @override
  Widget build(BuildContext context) {
    final source = theme;
    if (source != null) {
      return ValueListenableBuilder<ThemeSpec>(
        valueListenable: source,
        child: child,
        builder: (context, spec, child) => _build(spec, child!),
      );
    }
    return _build(
      ThemeSpecScope.maybeOf(context) ??
          RetainedThemeRegistry.sakuraNightGarden,
      child,
    );
  }

  Widget _build(ThemeSpec source, Widget child) {
    final spec = OpportunitiesVisualSpec.forAppearance(source);
    return ThemeSpecScope(
      spec: spec,
      child: Theme(
        data: _materialTheme(spec),
        child: DefaultTextStyle(
          style: spec.typography.body.copyWith(color: spec.palette.text),
          child: Stack(
            fit: StackFit.expand,
            children: [
              const Positioned.fill(child: OpportunityDeskBackdrop()),
              Positioned.fill(
                child: Material(
                  type: MaterialType.transparency,
                  child: OpportunityEntrance(child: child),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
