import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../foundations/theme_spec.dart';

/// Shared hierarchy for item/recipe reading windows, not dashboard geometry.
abstract final class ItemDetailStyle {
  static const double headerIcon = 48;
  static const double recipeIcon = 40;
  static const double ingredientIcon = 36;
  static const double sectionGap = 20;
  static const double itemGap = 12;

  static TextStyle title(ThemeSpec spec) => spec.typography.section.copyWith(
    fontSize: 20,
    height: 1.2,
    color: spec.palette.text,
  );
  static TextStyle recipe(ThemeSpec spec) => spec.typography.body.copyWith(
    fontSize: 17,
    height: 1.3,
    fontWeight: FontWeight.w700,
    color: spec.palette.text,
  );
  static TextStyle ingredient(ThemeSpec spec) => spec.typography.body.copyWith(
    fontSize: 15,
    height: 1.4,
    fontWeight: FontWeight.w600,
    color: spec.palette.text,
  );
  static TextStyle section(ThemeSpec spec) => spec.typography.label.copyWith(
    fontSize: 15,
    height: 1.3,
    fontWeight: FontWeight.w600,
    color: accent(spec),
  );
  static TextStyle body(ThemeSpec spec) => spec.typography.body.copyWith(
    fontSize: 14,
    height: 1.4,
    color: spec.palette.text,
  );
  static TextStyle meta(ThemeSpec spec) => spec.typography.meta.copyWith(
    fontSize: 13,
    height: 1.3,
    fontWeight: FontWeight.w500,
    color: spec.palette.textMuted,
  );

  static Color accent(ThemeSpec spec) {
    final foreground = spec.palette.primaryBright;
    final background = spec.palette.surfaceRaised;
    final light = math.max(
      foreground.computeLuminance(),
      background.computeLuminance(),
    );
    final dark = math.min(
      foreground.computeLuminance(),
      background.computeLuminance(),
    );
    return (light + .05) / (dark + .05) >= 4.5 ? foreground : spec.palette.text;
  }

  static double width(BuildContext context) {
    final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
    return (480 * scale.clamp(1.0, 2.0))
        .clamp(
          0.0,
          (MediaQuery.sizeOf(context).width - 32).clamp(0.0, double.infinity),
        )
        .toDouble();
  }
}

/// One light grouping rule for formulas; never a framed card inside a card.
class ItemDetailGroup extends StatelessWidget {
  const ItemDetailGroup({required this.child, super.key});
  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
    decoration: BoxDecoration(
      border: Border(
        left: BorderSide(
          color: context.visualTheme.palette.trim.withAlpha(150),
          width: 2,
        ),
      ),
    ),
    child: child,
  );
}
