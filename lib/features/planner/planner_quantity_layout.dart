import 'package:flutter/material.dart';

import '../../domain/formatting/planner_formatters.dart';
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
    super.key,
  });

  final Widget icon;
  final Widget identity;
  final Text total;
  final double iconWidth;
  final double totalRightInset;

  @override
  Widget build(BuildContext context) {
    final plannerLayout = PlannerQuantityLayout.of(context);
    final totalWidget = Tooltip(
      message: 'Total needed for this craft step',
      child: Padding(
        padding: EdgeInsets.only(right: totalRightInset),
        child: plannerLayout
            ? PlannerQuantityBadge(child: total)
            : SizedBox(
                width: 86,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerRight,
                  child: total,
                ),
              ),
      ),
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
          final totalWidth = painter.width + 12 + totalRightInset;
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
    super.key,
  });

  final String stableId;
  final double need;
  final double have;
  final double missing;

  @override
  Widget build(BuildContext context) {
    final spec = context.visualTheme;
    final values = [
      ('Need', formatQuantity(need)),
      ('Have', formatQuantity(have)),
      ('Missing', formatQuantity(missing)),
    ];
    final labelStyle = spec.typography.meta.copyWith(
      fontSize: 12.5,
      fontWeight: FontWeight.w400,
      fontStyle: FontStyle.normal,
      height: 1.2,
      color: spec.palette.textMuted,
    );
    TextStyle valueStyle(int index) => spec.typography.body.copyWith(
      fontSize: index == 0 ? 16 : 15,
      fontWeight: index == 0 ? FontWeight.w700 : FontWeight.w500,
      fontStyle: FontStyle.normal,
      height: 1.25,
      color: index == 0 ? spec.palette.text : spec.palette.textMuted,
      fontFeatures: const [FontFeature.tabularFigures()],
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        const gap = 10.0;
        var minimumWidth = 0.0;
        // Measure actual values and text scale so columns reflow, not shrink.
        for (var i = 0; i < values.length; i++) {
          for (final text in [
            TextSpan(text: values[i].$1, style: labelStyle),
            TextSpan(text: values[i].$2, style: valueStyle(i)),
          ]) {
            final painter = TextPainter(
              text: text,
              textDirection: Directionality.of(context),
              textScaler: MediaQuery.textScalerOf(context),
            )..layout();
            if (painter.width > minimumWidth) minimumWidth = painter.width;
            painter.dispose();
          }
        }
        minimumWidth = minimumWidth.ceilToDouble() + 2;
        final columns = ((constraints.maxWidth + gap) / (minimumWidth + gap))
            .floor()
            .clamp(1, 3);
        final width = (constraints.maxWidth - (columns - 1) * gap) / columns;
        return Wrap(
          spacing: gap,
          runSpacing: 7,
          children: [
            for (var i = 0; i < values.length; i++)
              SizedBox(
                width: width,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(values[i].$1, style: labelStyle),
                    const SizedBox(height: 2),
                    Text(
                      values[i].$2,
                      key: ValueKey(
                        'planner-need-quantity:$stableId:${values[i].$1}',
                      ),
                      style: valueStyle(i),
                    ),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }
}

/// Keep amount-entry controls beside the row, or below on narrow Planners.
class PlannerNeedRowLayout extends StatelessWidget {
  const PlannerNeedRowLayout({
    required this.icon,
    required this.content,
    required this.actions,
    required this.gap,
    required this.reservedWidth,
    super.key,
  });

  final Widget icon;
  final Widget content;
  final Widget actions;
  final double gap;
  final double reservedWidth;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final stackActions =
          PlannerQuantityLayout.of(context) &&
          constraints.maxWidth <
              reservedWidth + MediaQuery.textScalerOf(context).scale(220);
      final item = Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          icon,
          SizedBox(width: gap),
          Expanded(child: content),
          if (!stackActions) ...[SizedBox(width: gap), actions],
        ],
      );
      if (!stackActions) return item;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          item,
          const SizedBox(height: 8),
          Align(alignment: Alignment.centerRight, child: actions),
        ],
      );
    },
  );
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
