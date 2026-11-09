import 'package:flutter/material.dart';

import '../../domain/formatting/compact_quantity.dart';
import '../../domain/formatting/planner_formatters.dart';
import '../../domain/opportunities/opportunity_card_reading.dart';
import '../../visual/visual.dart';
import '../opportunities/opportunity_craft_card_material.dart';

/// A shortage uses the same material, type and spacing as availability pills.
class MissingCountBadge extends _QuantityCountBadge {
  const MissingCountBadge({required double missing, super.key})
    : super(value: missing);
  double get missing => value;
  @override
  String get title => 'Missing';
  @override
  OpportunityStockTone get tone => missing > 0
      ? OpportunityStockTone.outOfStock
      : OpportunityStockTone.available;
}

/// Required quantity is neutral: it is neither owned nor missing stock.
class NeedCountBadge extends _QuantityCountBadge {
  const NeedCountBadge({required double need, super.key}) : super(value: need);
  @override
  String get title => 'Need';
  @override
  OpportunityStockTone get tone => OpportunityStockTone.unknown;
}

abstract class _QuantityCountBadge extends StatelessWidget {
  const _QuantityCountBadge({required this.value, super.key});
  final double value;
  String get title;
  OpportunityStockTone get tone;

  String get label => '$title ${formatCompactQuantity(value)}';
  TextStyle style(BuildContext context) =>
      context.visualTheme.typography.meta.copyWith(
        fontSize: 14,
        fontWeight: FontWeight.w500,
        fontStyle: FontStyle.normal,
      );

  double preferredWidth(BuildContext context) {
    final painter = TextPainter(
      text: TextSpan(
        text: label,
        style: DefaultTextStyle.of(context).style.merge(style(context)),
      ),
      textScaler: MediaQuery.textScalerOf(context),
      textDirection: Directionality.of(context),
      maxLines: 1,
    )..layout();
    final width = painter.width + 14;
    painter.dispose();
    return width;
  }

  @override
  Widget build(BuildContext context) {
    final material = OpportunityCraftCardMaterial.forSpec(
      context.visualTheme,
      tone,
    );
    return Semantics(
      label: '$title ${formatQuantity(value)}',
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        decoration: BoxDecoration(
          color: material.badgeFill,
          border: Border.all(color: material.badgeInk.withAlpha(100)),
          borderRadius: BorderRadius.circular(3),
        ),
        child: Text(
          label,
          maxLines: 1,
          softWrap: false,
          style: style(context).copyWith(color: material.badgeInk),
        ),
      ),
    );
  }
}
