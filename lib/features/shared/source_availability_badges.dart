import 'package:flutter/material.dart';
import 'market_count_badges.dart';

/// The same availability vocabulary and materials in every item surface.
/// This displays supplied facts only; it never guesses stock or fetches data.
class SourceAvailabilityBadges extends StatelessWidget {
  const SourceAvailabilityBadges({
    required this.stock,
    this.preorders,
    this.npc = false,
    this.showMarket,
    this.density = MarketBadgeDensity.compact,
    this.alignment = WrapAlignment.start,
    this.stockKey,
    super.key,
  });
  final int? stock, preorders;
  final bool npc;
  final bool? showMarket;
  final MarketBadgeDensity density;
  final WrapAlignment alignment;
  final Key? stockKey;

  MarketCountBadges presentation(BuildContext context) {
    return MarketCountBadges(
      stock: stock,
      preorders: preorders,
      npc: npc,
      showMarket: showMarket,
      density: density,
      alignment: alignment,
      stockKey: stockKey,
    );
  }

  @override
  Widget build(BuildContext context) => presentation(context);
}

/// Shared right-side source rail. Wrap below the label when room is limited;
/// never shrink the text or let counts collide with names.
class SourceAvailabilityLine extends StatelessWidget {
  const SourceAvailabilityLine({
    required this.label,
    required this.badge,
    this.availableWidth,
    super.key,
  });
  final Widget label;
  final SourceAvailabilityBadges badge;

  /// Supply the host's measured width inside intrinsic-height recipe rows.
  final double? availableWidth;

  @override
  Widget build(BuildContext context) => availableWidth != null
      ? _line(context, availableWidth!)
      : LayoutBuilder(
          builder: (context, constraints) =>
              _line(context, constraints.maxWidth),
        );

  Widget _line(BuildContext context, double width) {
    final natural = badge.presentation(context).preferredWidth(context);
    final badgeWidth = natural.clamp(0.0, width * .52);
    final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
    if (width - badgeWidth - 10 < 150 * scale) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          label,
          const SizedBox(height: 6),
          Align(alignment: Alignment.centerRight, child: badge),
        ],
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(child: label),
        const SizedBox(width: 10),
        SizedBox(width: badgeWidth, child: badge),
      ],
    );
  }
}

/// Recipe ingredients keep their availability directly beneath their names.
class SourceAvailabilityBelowLabel extends StatelessWidget {
  const SourceAvailabilityBelowLabel({
    required this.label,
    required this.badge,
    super.key,
  });
  final Widget label;
  final SourceAvailabilityBadges badge;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [label, const SizedBox(height: 6), badge],
  );
}
