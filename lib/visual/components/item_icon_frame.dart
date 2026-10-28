import 'package:flutter/material.dart';

import '../foundations/theme_spec.dart';

/// Item quality is game data, not a theme accent or ingredient substitution.
Color? itemQualityColor(int? grade) => switch (grade) {
  0 => const Color(0xFFFFFFFF),
  1 => const Color(0xFF5FF369),
  2 => const Color(0xFF04B3F1),
  3 => const Color(0xFFF6C232),
  4 => const Color(0xFFFF7C00),
  5 => const Color(0xFFA070EF),
  _ => null,
};

/// A single frame around original, borderless artwork. The foreground border
/// cannot be covered by opaque images; padding keeps the complete art visible.
class ItemIconFrame extends StatelessWidget {
  const ItemIconFrame({
    required this.size,
    required this.child,
    this.grade,
    super.key,
  });

  final double size;
  final int? grade;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final spec = ThemeSpecScope.maybeOf(context);
    final surface = spec?.palette.surfaceInset ?? const Color(0xFF101C24);
    // Keep pale artwork and white/yellow quality frames readable on light
    // themes too. The dark well still comes from that theme's own palette.
    final inset = surface.computeLuminance() > .35
        ? spec?.palette.canvasDeep ?? const Color(0xFF101C24)
        : surface;
    final edge = itemQualityColor(grade);
    final radius = BorderRadius.circular((size * .12).clamp(3.0, 7.0));
    return Container(
      width: size,
      height: size,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(color: inset, borderRadius: radius),
      foregroundDecoration: BoxDecoration(
        borderRadius: radius,
        border: Border.all(
          color:
              edge?.withAlpha(grade == 0 ? 125 : 210) ??
              (spec?.palette.trimBright ?? const Color(0xFF9DA6AB)).withAlpha(
                140,
              ),
          width: size >= 36 ? 1.2 : 1,
        ),
      ),
      child: Padding(
        padding: EdgeInsets.all(size >= 32 ? 2 : 1.5),
        child: child,
      ),
    );
  }
}
