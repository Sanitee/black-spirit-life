import 'package:flutter/material.dart';

import '../../domain/formatting/compact_quantity.dart';
import '../../domain/formatting/planner_formatters.dart';
import '../../domain/opportunities/opportunity_card_reading.dart';
import '../../visual/components/app_tooltip.dart';
import '../../visual/visual.dart';
import '../opportunities/opportunity_craft_card_material.dart';
import 'availability_game_icon.dart';
import 'market_count_badges.dart';

/// The same availability material and game-icon family as market/NPC badges.
class InventoryCountBadge extends StatelessWidget {
  const InventoryCountBadge({
    required this.owned,
    this.showLabel = false,
    this.density = MarketBadgeDensity.compact,
    this.semanticLabel,
    super.key,
  });
  final double owned;
  final bool showLabel;
  final MarketBadgeDensity density;
  final String? semanticLabel;
  bool get _comfortable => density == MarketBadgeDensity.comfortable;
  TextStyle _textStyle(BuildContext context) =>
      context.visualTheme.typography.meta.copyWith(
        fontSize: _comfortable ? 14 : 12,
        fontWeight: _comfortable ? FontWeight.w500 : null,
        fontStyle: _comfortable ? FontStyle.normal : null,
      );
  String get _label =>
      '${showLabel ? 'Owned ' : ''}${formatCompactQuantity(owned)}';

  double preferredWidth(BuildContext context) {
    final painter = TextPainter(
      text: TextSpan(
        text: _label,
        style: DefaultTextStyle.of(context).style.merge(_textStyle(context)),
      ),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
    )..layout();
    final width =
        painter.width.ceilToDouble() +
        (_comfortable ? 17 : 16) +
        (_comfortable ? 5 : 4) +
        14;
    painter.dispose();
    return width;
  }

  @override
  Widget build(BuildContext context) {
    final material = OpportunityCraftCardMaterial.forSpec(
      context.visualTheme,
      owned > 0
          ? OpportunityStockTone.available
          : OpportunityStockTone.outOfStock,
    );
    return AppTooltip(
      message: semanticLabel ?? 'Owned ${formatQuantity(owned)}',
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: 6,
          vertical: _comfortable ? 4 : 2,
        ),
        decoration: BoxDecoration(
          color: material.badgeFill,
          borderRadius: BorderRadius.circular(3),
          border: Border.all(color: material.badgeInk.withAlpha(100)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            AvailabilityGameIcon(
              artwork: AvailabilityArtwork.inventory,
              size: _comfortable ? 17 : 16,
              color: material.badgeInk,
            ),
            SizedBox(width: _comfortable ? 5 : 4),
            Flexible(
              child: Text(
                _label,
                maxLines: 1,
                softWrap: false,
                style: _textStyle(context).copyWith(color: material.badgeInk),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
