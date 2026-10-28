import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../app/state/planner_application_controller.dart';
import '../../domain/formatting/planner_formatters.dart';
import '../../visual/visual.dart';
import 'planner_inventory_input.dart';

/// Content-dependent layout boundaries in unscaled Planner-body coordinates.
///
/// Call when the plan, theme, inventory or OS text settings change, not from
/// the zoom notifier. All queue steps and Need rows participate, including
/// lazily unmounted cards and collapsed ingredients. This never assembles a plan.
List<double> plannerQueueFitBreakpoints(
  BuildContext context,
  ModeFeatureController controller,
) {
  final spec = context.visualTheme;
  final dense = spec.usesDenseSplitLayout;
  final scaler = MediaQuery.textScalerOf(context);
  final direction = Directionality.of(context);
  final thresholds = <double>{};

  // PlannerPlanColumns: 12px central gap; queue flex 96/200 or 108/200.
  // Queue: dense right inset 12; layout padding 12+12; list-card right
  // inset 8 dense; AppSurface card padding 10+10 and border 1+1 for both
  // dense themes, versus Standard's 14+14 padding and no card border.
  final queueFraction = dense ? .48 : .54;
  final queueInsets = dense ? 12 + 24 + 8 + 20 + 2.0 : 24 + 28.0;
  double bodyWidth(double cardContentWidth) =>
      12 + (cardContentWidth + queueInsets) / queueFraction;
  void addCardBoundary(double width) => thresholds.add(bodyWidth(width));

  final inherited = dense
      ? DefaultTextStyle.of(context).style.merge(spec.typography.body)
      : DefaultTextStyle.of(context).style;
  // Text widgets inherit Material's remaining metrics (notably letterSpacing),
  // while the ingredient/owned layout probes deliberately use raw TextSpans.
  final labelStyle = inherited.merge(
    spec.typography.meta.copyWith(
      fontSize: 12,
      fontStyle: FontStyle.normal,
      color: spec.palette.textMuted,
    ),
  );
  final summaryValueStyle = inherited.merge(
    spec.typography.body.copyWith(
      fontSize: 16,
      fontWeight: FontWeight.w700,
      fontStyle: FontStyle.normal,
      color: spec.palette.text,
      fontFeatures: const [FontFeature.tabularFigures()],
    ),
  );
  final ingredientValueStyle = spec.typography.meta.copyWith(
    fontSize: 16,
    fontWeight: FontWeight.w600,
    fontStyle: FontStyle.normal,
    color: spec.palette.text,
    fontFeatures: const [FontFeature.tabularFigures()],
  );
  final ownedStyle = spec.typography.meta.copyWith(
    fontSize: 13,
    height: 1.15,
    fontStyle: FontStyle.normal,
    color: spec.palette.text,
    fontWeight: FontWeight.w600,
    fontFeatures: const [FontFeature.tabularFigures()],
  );
  final measurements = <(String, TextStyle), double>{};
  double measure(String text, TextStyle style) =>
      measurements.putIfAbsent((text, style), () {
        final painter = TextPainter(
          text: TextSpan(text: text, style: style),
          textDirection: direction,
          textScaler: scaler,
        )..layout();
        final width = painter.width;
        painter.dispose();
        return width;
      });

  final owned = <String, double>{};
  for (final entry in controller.state.value.inventory.entries) {
    owned.putIfAbsent(entry.key.trim().toLowerCase(), () => entry.value);
  }
  final gradeAvailability = <(String, String), bool>{};
  for (final step in controller.plan.value.steps) {
    // PlannerInventoryInput's non-editing icon extent grows to its abbreviated
    // owned footer. The header additionally reserves its 2px side padding,
    // icon/title gap, 8px completion gap and fixed completion control.
    final amount = owned[step.name.trim().toLowerCase()] ?? 0;
    final iconExtent = math.max(
      dense ? 48.0 : 54.0,
      measure(formatPlannerInventoryAmount(amount), ownedStyle) + 10,
    );
    final summaryInset =
        iconExtent + 4 + (dense ? 9 : 12) + 8 + (dense ? 46 : 48);
    final chips = [
      for (final value in [
        ('Craft', step.count),
        ('Results', step.produced),
        ('Need', step.demand),
      ])
        (
          label: measure(value.$1, labelStyle),
          value: measure(formatQuantity(value.$2), summaryValueStyle),
        ),
    ];
    for (final boundary in _quantityWrapBoundaries(
      chips,
      innerSpacing: 7,
      outerSpacing: 8,
      chipPadding: 16,
    )) {
      addCardBoundary(summaryInset + boundary);
    }

    if (scaler.scale(1) <= 1.3 &&
        controller.recipeDefinition(step.name) != null) {
      addCardBoundary(330); // _QueueStepCard.showAfkLabel.
    }
    for (final ingredient in step.ingredients) {
      final icon = dense ? 40.0 : 46.0;
      final rightInset = spec.isSakuraNightGarden
          ? SakuraQueueCornerAsset.authoredSize.width - 8
          : 18.0;
      final totalWidth =
          measure(formatQuantity(ingredient.need), ingredientValueStyle) +
          12 +
          rightInset;
      // PlannerIngredientRowLayout's exact stacked-total branch.
      final totalBoundary = icon + 21 + scaler.scale(100) + totalWidth;
      addCardBoundary(totalBoundary);
      final hasGrades = gradeAvailability.putIfAbsent(
        (ingredient.parentName, ingredient.baseName),
        () => controller
            .availableIngredientGrades(
              parentName: ingredient.parentName,
              selectedName: ingredient.baseName,
            )
            .isNotEmpty,
      );
      if (!hasGrades) continue;
      // Identity receives the remaining Row width. A stacked total no longer
      // reserves its 10px gap or amount width on the identity's line.
      final renderedTotalWidth =
          measure(
            formatQuantity(ingredient.need),
            inherited.merge(ingredientValueStyle),
          ) +
          12 +
          rightInset;
      final inlineBoundary = icon + 21 + renderedTotalWidth + scaler.scale(330);
      addCardBoundary(inlineBoundary);
      final stackedInlineBoundary = icon + 11 + scaler.scale(330);
      if (stackedInlineBoundary < totalBoundary) {
        addCardBoundary(stackedInlineBoundary);
      }
    }
  }
  // Need First uses the other column, a 48px icon and its 12px identity gap.
  // Its row padding/border is 22px dense or 30px Standard. Market accents are
  // paint-only and never change these insets.
  final needFraction = dense ? .52 : .46;
  final needInsets = dense ? 20 + 24 + 8 + 22.0 : 24 + 30.0;
  void addNeedBoundary(double width) =>
      thresholds.add(12 + (width + needInsets) / needFraction);
  final needLabelStyle = inherited.merge(
    spec.typography.meta.copyWith(
      fontSize: 12.5,
      fontWeight: FontWeight.w400,
      fontStyle: FontStyle.normal,
      height: 1.2,
      color: spec.palette.textMuted,
    ),
  );
  final needValueStyle = inherited.merge(
    spec.typography.body.copyWith(
      fontSize: 14,
      fontWeight: FontWeight.w500,
      fontStyle: FontStyle.normal,
      height: 1.2,
      color: spec.palette.text,
      fontFeatures: const [FontFeature.tabularFigures()],
    ),
  );
  final missingStyle = needValueStyle.copyWith(
    fontSize: 16,
    fontWeight: FontWeight.w700,
  );
  // _OwnedDraftActions: fixed field, gap, and content-sized Add button. The
  // button replaces (does not merge) DefaultTextStyle; its child is a 13px
  // glyph, 4px gap and Add. Its default border is 1.15px for Sakura primary.
  final addWidth = math.max(
    dense ? 72.0 : 78.0,
    13 +
        4 +
        measure('Add', spec.typography.button) +
        24 +
        (spec.isSakuraNightGarden ? 2.3 : 2),
  );
  final actionsWidth = (dense ? 82 + 8 : 92 + 10) + addWidth;
  final sideBySide = 60 + scaler.scale(350);
  for (final row in controller.plan.value.missing) {
    final pairs = [
      for (final field in [
        ('Need', row.need),
        ('Have', row.have),
        ('Missing', row.missing),
      ])
        (
          label: measure(field.$1, needLabelStyle),
          value: measure(
            formatQuantity(field.$2),
            field.$1 == 'Missing' ? missingStyle : needValueStyle,
          ),
        ),
    ];
    for (final boundary in _quantityWrapBoundaries(
      pairs,
      innerSpacing: 6,
      outerSpacing: 16,
    )) {
      final belowActions = boundary + 60;
      if (belowActions < sideBySide) addNeedBoundary(belowActions);
      final besideActions = boundary + 60 + 16 + actionsWidth;
      if (besideActions >= sideBySide) addNeedBoundary(besideActions);
    }
  }
  return thresholds.toList()..sort();
}

/// Exact greedy Wrap transitions for three quantity pairs, including each
/// pair's inner label/value wrap. Candidate ranges are only three items long.
List<double> _quantityWrapBoundaries(
  List<({double label, double value})> chips, {
  required double innerSpacing,
  required double outerSpacing,
  double chipPadding = 0,
}) {
  final widths = [
    for (final chip in chips)
      (
        full: chip.label + innerSpacing + chip.value + chipPadding,
        stacked: math.max(chip.label, chip.value) + chipPadding,
      ),
  ];
  final candidates = <double>{
    for (final chip in widths) ...[chip.full, chip.stacked],
  };
  for (var start = 0; start < widths.length; start++) {
    for (var end = start + 1; end < widths.length; end++) {
      final length = end - start + 1;
      for (var mask = 0; mask < (1 << length); mask++) {
        var width = outerSpacing * (length - 1);
        for (var offset = 0; offset < length; offset++) {
          final chip = widths[start + offset];
          width += mask & (1 << offset) == 0 ? chip.full : chip.stacked;
        }
        candidates.add(width);
      }
    }
  }
  String signature(double width) {
    var runWidth = 0.0;
    var run = 0;
    final parts = <String>[];
    for (final chip in widths) {
      final inline = width >= chip.full;
      final childWidth = math.min(width, inline ? chip.full : chip.stacked);
      if (runWidth > 0 && runWidth + outerSpacing + childWidth > width) {
        run++;
        runWidth = 0;
      }
      runWidth += (runWidth > 0 ? outerSpacing : 0) + childWidth;
      parts.add('$run:$inline:${width >= chip.stacked}');
    }
    return parts.join(',');
  }

  return candidates
      .where((width) => signature(width - .0001) != signature(width + .0001))
      .toList();
}
