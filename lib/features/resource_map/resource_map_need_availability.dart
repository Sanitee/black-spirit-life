import 'dart:math' as math;
import 'package:bdo_map_core/bdo_map_core.dart';
import 'package:flutter/material.dart';
import '../../app/state/planner_application_controller.dart';
import '../../domain/formatting/planner_formatters.dart';
import '../../domain/market/shared_market_models.dart';
import '../planner/planner_choice_market.dart';
import '../shared/inventory_count_badge.dart';
import '../shared/market_count_badges.dart';

/// Visible map rows use the same broker, freshness and badges as ingredient rows.
class ResourceMapNeedAvailability extends StatelessWidget {
  const ResourceMapNeedAvailability({
    required this.controller,
    required this.need,
    required this.needs,
    required this.ownedFor,
    super.key,
  });
  final ModeFeatureController controller;
  final BdoPlannerMaterialNeed need;
  final List<BdoPlannerMaterialNeed> needs;
  final double Function(String) ownedFor;

  @override
  Widget build(BuildContext context) => PlannerChoiceMarket(
    controller: controller,
    names: [need.name],
    resolveAcrossModes: true,
    builder: (context, marketFor, now) {
      final item = marketFor(need.name);
      final identity = choiceMarketIdentity(
        controller,
        need.name,
        acrossModes: true,
      );
      final market = MarketCountBadges(
        stock: item?.stockFor(now, sharedMarketFreshness),
        preorders: item?.bookIsFresh(now, sharedMarketFreshness) == true
            ? item?.preorderCount
            : null,
        compactNumbers: true,
        singleLine: true,
      );
      final inventory = InventoryCountBadge(owned: ownedFor(need.name));
      final showMarket = identity.marketId != null;
      final style = Theme.of(context).textTheme.bodySmall;
      String label(BdoPlannerMaterialNeed n) =>
          'Need ${formatGroupedEditableQuantity(n.missingQuantity, fractionDigits: 2)}';
      double textWidth(String text) {
        final painter = TextPainter(
          text: TextSpan(text: text, style: style),
          textDirection: Directionality.of(context),
          textScaler: MediaQuery.textScalerOf(context),
        )..layout();
        final width = painter.width.ceilToDouble();
        painter.dispose();
        return width;
      }

      final needWidth = needs.fold<double>(
        textWidth(label(need)),
        (width, n) => math.max(width, textWidth(label(n))),
      );
      final inventoryWidth = needs.fold<double>(
        inventory.preferredWidth(context),
        (width, n) => math.max(
          width,
          InventoryCountBadge(owned: ownedFor(n.name)).preferredWidth(context),
        ),
      );
      final scale = MediaQuery.textScalerOf(context).scale(12) / 12;
      final gap = 12 * scale;
      final badgesWidth =
          inventoryWidth +
          (showMarket ? gap + market.preferredWidth(context) : 0);
      // Keep every row on the same side of the responsive breakpoint while
      // quotes arrive. A row without Orders must not shift its inventory column.
      final stableBadgesWidth =
          inventoryWidth +
          gap +
          const MarketCountBadges(
            stock: 999999,
            preorders: 999999,
            compactNumbers: true,
            singleLine: true,
          ).preferredWidth(context);
      final badges = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: inventoryWidth,
            child: Align(alignment: Alignment.centerLeft, child: inventory),
          ),
          if (showMarket) ...[SizedBox(width: gap), market],
        ],
      );
      final needLabel = Text(label(need), style: style);
      return LayoutBuilder(
        builder: (context, constraints) {
          if (needWidth + gap * 2 + math.max(badgesWidth, stableBadgesWidth) <=
              constraints.maxWidth) {
            return Row(
              children: [
                SizedBox(width: needWidth, child: needLabel),
                SizedBox(width: gap * 2),
                badges,
              ],
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              needLabel,
              const SizedBox(height: 6),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: badges,
              ),
            ],
          );
        },
      );
    },
  );
}
