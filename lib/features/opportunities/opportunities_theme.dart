import 'package:flutter/material.dart';

import '../../visual/visual.dart';
import 'opportunities_visuals.dart';

/// Opportunities has its own fixed identity, independent of Craft Profile.
class OpportunitiesTheme extends StatelessWidget {
  const OpportunitiesTheme({required this.child, super.key});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    const spec = OpportunitiesVisualSpec.spec;
    final materialTheme = spec.materialTheme();
    return ThemeSpecScope(
      spec: spec,
      child: Theme(
        data: materialTheme.copyWith(
          tooltipTheme: materialTheme.tooltipTheme.copyWith(
            constraints: const BoxConstraints(minHeight: 32, maxWidth: 380),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              gradient: OpportunitiesVisualSpec.overlay,
              borderRadius: BorderRadius.circular(spec.geometry.fieldRadius),
              border: Border.all(color: spec.palette.trim),
              boxShadow: spec.materials.highShadow,
            ),
            textStyle: spec.typography.body,
          ),
        ),
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
