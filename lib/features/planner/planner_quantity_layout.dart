import 'package:bdo_craft_planner_flutter/visual/components/app_tooltip.dart';
import 'package:flutter/material.dart';

import '../../domain/formatting/planner_formatters.dart';
import '../../domain/planner/planner_models.dart';
import '../../visual/visual.dart';

/// Main Planner quantities; shared Bonus rows retain their own presentation.
class PlannerQuantityLayout extends InheritedWidget {
  const PlannerQuantityLayout({required super.child, super.key});

  static bool of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<PlannerQuantityLayout>() !=
      null;

  @override
  bool updateShouldNotify(PlannerQuantityLayout oldWidget) => false;
}

/// Existing calculation results in a compact, wrapping header line.
class PlannerCraftQuantities extends StatelessWidget {
  const PlannerCraftQuantities({required this.step, super.key});

  final PlanStep step;

  @override
  Widget build(BuildContext context) {
    final spec = context.visualTheme;
    final values = [
      ('Craft', step.count),
      ('Results', step.produced),
      ('Need', step.demand),
    ];
    final labelStyle = spec.typography.meta.copyWith(
      fontSize: 12,
      fontStyle: FontStyle.normal,
      color: spec.palette.textMuted,
    );
    final valueStyle = spec.typography.body.copyWith(
      fontSize: 16,
      fontWeight: FontWeight.w700,
      fontStyle: FontStyle.normal,
      color: spec.palette.text,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    return Column(
      key: ValueKey('planner-step-summary:${step.name}'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            for (final value in values)
              DecoratedBox(
                key: ValueKey('planner-craft-field:${step.name}:${value.$1}'),
                decoration: BoxDecoration(
                  color: spec.palette.surfaceInset.withValues(alpha: .24),
                  borderRadius: BorderRadius.circular(5),
                  border: Border(
                    bottom: BorderSide(
                      color: spec.palette.trim.withValues(alpha: .30),
                    ),
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Wrap(
                    spacing: 7,
                    runSpacing: 3,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(value.$1, style: labelStyle),
                      Text(
                        formatQuantity(value.$2),
                        style: valueStyle,
                        key: ValueKey(
                          'planner-craft-quantity:${step.name}:${value.$1}',
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
        if (step.batchSize > 1) ...[
          const SizedBox(height: 8),
          Text(
            'Mass batches ${formatQuantity(step.batchCount)} ×${step.batchSize}',
            style: labelStyle,
          ),
        ],
      ],
    );
  }
}

/// A quiet, noninteractive backing shared by per-craft and total quantities.
class PlannerQuantityBadge extends StatelessWidget {
  const PlannerQuantityBadge({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!PlannerQuantityLayout.of(context)) return child;
    final spec = context.visualTheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: spec.palette.text.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(3),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        child: child,
      ),
    );
  }
}

/// Keep full-size quantities readable when an ingredient row gets narrow.
class PlannerIngredientRowLayout extends StatelessWidget {
  const PlannerIngredientRowLayout({
    required this.icon,
    required this.identity,
    required this.total,
    required this.iconWidth,
    required this.totalRightInset,
    this.showQuantityBadge = true,
    super.key,
  });

  final Widget icon;
  final Widget identity;
  final Text total;
  final double iconWidth;
  final double totalRightInset;
  final bool showQuantityBadge;

  @override
  Widget build(BuildContext context) {
    final plannerLayout = PlannerQuantityLayout.of(context);
    final amount = Padding(
      padding: EdgeInsets.only(right: totalRightInset),
      child: plannerLayout
          ? showQuantityBadge
                ? PlannerQuantityBadge(child: total)
                : total
          : SizedBox(
              width: 86,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerRight,
                child: total,
              ),
            ),
    );
    final totalWidget = showQuantityBadge
        ? AppTooltip(message: 'Total needed for this craft step', child: amount)
        : Semantics(
            label: '${total.data} total needed for this craft step',
            excludeSemantics: true,
            child: amount,
          );
    return LayoutBuilder(
      builder: (context, constraints) {
        var stackTotal = false;
        if (plannerLayout) {
          final scaler = MediaQuery.textScalerOf(context);
          final painter = TextPainter(
            text: TextSpan(text: total.data, style: total.style),
            textDirection: Directionality.of(context),
            textScaler: scaler,
          )..layout();
          final totalWidth =
              painter.width + (showQuantityBadge ? 12 : 0) + totalRightInset;
          painter.dispose();
          stackTotal =
              constraints.maxWidth <
              iconWidth + 21 + scaler.scale(100) + totalWidth;
        }
        final item = Row(
          children: [
            icon,
            const SizedBox(width: 11),
            Expanded(child: identity),
            if (!stackTotal) ...[const SizedBox(width: 10), totalWidget],
          ],
        );
        if (!stackTotal) return item;
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            item,
            const SizedBox(height: 4),
            Align(alignment: Alignment.centerRight, child: totalWidget),
          ],
        );
      },
    );
  }
}

/// Displays existing plan values unchanged; Need is total demand, not Missing.
class PlannerNeedQuantities extends StatelessWidget {
  const PlannerNeedQuantities({
    required this.stableId,
    required this.need,
    required this.have,
    required this.missing,
    required this.leading,
    required this.identity,
    required this.actions,
    this.marketDetails,
    super.key,
  });

  final String stableId;
  final double need;
  final double have;
  final double missing;
  final Widget leading;
  final Widget identity;
  final Widget actions;
  final Widget? marketDetails;

  Widget _emphasized(BuildContext context) {
    final spec = context.visualTheme;
    final labelStyle = spec.typography.meta.copyWith(
      fontSize: 12.5,
      fontWeight: FontWeight.w400,
      fontStyle: FontStyle.normal,
      height: 1.2,
      color: spec.palette.textMuted,
    );
    final valueStyle = spec.typography.body.copyWith(
      fontSize: 14,
      fontWeight: FontWeight.w500,
      fontStyle: FontStyle.normal,
      height: 1.2,
      color: spec.palette.text,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    final missingStyle = valueStyle.copyWith(
      fontSize: 16,
      fontWeight: FontWeight.w700,
    );
    Widget value(String label, double amount, TextStyle style) => Text(
      formatQuantity(amount),
      key: ValueKey('planner-need-quantity:$stableId:$label'),
      style: style,
    );
    Widget inline(String label, double amount) => Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 6,
      runSpacing: 3,
      children: [
        Text(label, style: labelStyle),
        value(label, amount, label == 'Missing' ? missingStyle : valueStyle),
      ],
    );
    final item = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        leading,
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              identity,
              const SizedBox(height: 8),
              Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 16,
                runSpacing: 6,
                children: [
                  inline('Need', need),
                  inline('Have', have),
                  inline('Missing', missing),
                ],
              ),
              if (marketDetails case final market?) ...[
                const SizedBox(height: 10),
                market,
              ],
            ],
          ),
        ),
      ],
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        // Keep the item details together; move only the Add controls below
        // when the column or enlarged text needs the extra room.
        final sideBySideWidth =
            60 + MediaQuery.textScalerOf(context).scale(350);
        if (constraints.maxWidth < sideBySideWidth) {
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              item,
              const SizedBox(height: 12),
              Align(alignment: Alignment.centerRight, child: actions),
            ],
          );
        }
        return Row(
          children: [
            Expanded(child: item),
            const SizedBox(width: 16),
            actions,
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) => _emphasized(context);
}

/// Keep names and quality actions intact beside the more readable quantity.
class PlannerIngredientIdentity extends StatelessWidget {
  const PlannerIngredientIdentity({
    required this.name,
    this.quantity,
    this.quality,
    super.key,
  });

  final Widget name;
  final Widget? quantity;
  final Widget? quality;

  @override
  Widget build(BuildContext context) {
    if (PlannerQuantityLayout.of(context)) {
      return LayoutBuilder(
        builder: (context, constraints) {
          final inlineQuality =
              constraints.maxWidth >=
              MediaQuery.textScalerOf(context).scale(330);
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Flexible(child: name),
                  if (quantity != null) ...[
                    const SizedBox(width: 6),
                    quantity!,
                  ],
                  if (inlineQuality && quality != null) ...[
                    const SizedBox(width: 6),
                    quality!,
                  ],
                ],
              ),
              if (!inlineQuality && quality != null) ...[
                const SizedBox(height: 5),
                quality!,
              ],
            ],
          );
        },
      );
    }
    return Row(
      children: [
        Flexible(child: name),
        if (quantity != null) ...[const SizedBox(width: 6), quantity!],
        if (quality != null) ...[const SizedBox(width: 6), quality!],
      ],
    );
  }
}
