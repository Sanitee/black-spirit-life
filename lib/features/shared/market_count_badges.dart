import 'package:flutter/material.dart';

import '../../domain/formatting/compact_quantity.dart';
import '../../domain/formatting/planner_formatters.dart';
import '../../domain/opportunities/opportunity_card_reading.dart';
import '../../visual/components/app_tooltip.dart';
import '../../visual/visual.dart';
import '../opportunities/opportunity_craft_card_material.dart';
import 'availability_game_icon.dart';
import 'npc_source_marker.dart';

enum MarketBadgeDensity { compact, comfortable }

/// One badge vocabulary and material, with a roomier Planner presentation.
class MarketCountBadges extends StatelessWidget {
  const MarketCountBadges({
    required this.stock,
    required this.preorders,
    this.npc = false,
    this.vendorHint,
    this.showMarket,
    this.density = MarketBadgeDensity.compact,
    this.alignment = WrapAlignment.start,
    this.stockKey,
    this.wrapKey,
    this.compactNumbers = false,
    this.singleLine = false,
    this.stockColumnWidth,
    this.stockColumnAlignment = Alignment.centerLeft,
    super.key,
  });
  final int? stock, preorders;
  final bool npc;
  final String? vendorHint;
  final bool? showMarket;
  bool get _showMarket => showMarket ?? !npc;
  final MarketBadgeDensity density;
  final WrapAlignment alignment;
  final Key? stockKey;
  final Key? wrapKey;
  final bool compactNumbers;
  final bool singleLine;
  final double? stockColumnWidth;
  final Alignment stockColumnAlignment;
  String _quantity(int value) => compactNumbers
      ? formatCompactQuantity(value)
      : formatQuantity(value.toDouble());

  /// Natural single-line width, used by hosts before deciding to reflow.
  double preferredWidth(BuildContext context) {
    final comfortable = density == MarketBadgeDensity.comfortable;
    final labels = [
      if (npc) 'NPC',
      if (_showMarket) ...[
        stock == null ? '—' : _quantity(stock!),
        if ((preorders ?? 0) > 0) 'Orders ${_quantity(preorders!)}',
      ],
    ];
    final painter = TextPainter(
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
    );
    var width = 0.0;
    for (final label in labels) {
      if (label == 'NPC') {
        width += const NpcSourceMarker().preferredWidth(context);
        continue;
      }
      painter.text = TextSpan(
        text: label,
        style: DefaultTextStyle.of(context).style.merge(
          context.visualTheme.typography.meta.copyWith(
            fontSize: comfortable ? 14 : 12,
            fontWeight: comfortable ? FontWeight.w500 : null,
            fontStyle: comfortable ? FontStyle.normal : null,
          ),
        ),
      );
      painter.layout();
      width +=
          painter.width.ceilToDouble() +
          (comfortable ? 17 : 16) +
          14 +
          (comfortable ? 5 : 4);
    }
    painter.dispose();
    return width + (labels.length - 1) * (comfortable ? 7 : 6);
  }

  @override
  Widget build(BuildContext context) {
    final comfortable = density == MarketBadgeDensity.comfortable;
    String quantity(int value) => _quantity(value);
    final labels = <(AvailabilityArtwork, String, OpportunityStockTone)>[
      if (npc) (AvailabilityArtwork.npc, 'NPC', OpportunityStockTone.mixed),
      if (_showMarket) ...[
        (
          AvailabilityArtwork.stock,
          stock == null ? '—' : quantity(stock!),
          marketStockTone(stock),
        ),
        if ((preorders ?? 0) > 0)
          (
            AvailabilityArtwork.preorders,
            'Orders ${quantity(preorders!)}',
            OpportunityStockTone.mixed,
          ),
      ],
    ];
    return Semantics(
      excludeSemantics: true,
      label: [
        if (npc) 'Available from an NPC',
        if (_showMarket)
          'Stock: ${stock == null ? 'not checked' : formatQuantity(stock!.toDouble())}\nPreorders: ${preorders == null ? 'not checked' : formatQuantity(preorders!.toDouble())}',
      ].join('\n'),
      child: _layout(
        key: wrapKey,
        alignment: alignment,
        spacing: comfortable ? 7 : 6,
        runSpacing: comfortable ? 6 : 4,
        children: [
          for (final entry in labels)
            Builder(
              builder: (context) {
                if (entry.$1 == AvailabilityArtwork.npc) {
                  return NpcSourceMarker(
                    vendorHint: vendorHint,
                    textKey: entry == labels.first ? stockKey : null,
                  );
                }
                final material = OpportunityCraftCardMaterial.forSpec(
                  context.visualTheme,
                  entry.$3,
                );
                final color = material.badgeInk;
                final fill = material.badgeFill;
                return AppTooltip(
                  message: switch (entry.$1) {
                    AvailabilityArtwork.stock =>
                      stock == null
                          ? 'Market stock: not checked'
                          : 'Market stock: ${formatQuantity(stock!.toDouble())}',
                    AvailabilityArtwork.preorders =>
                      'Preorders: ${formatQuantity(preorders!.toDouble())} waiting to buy',
                    _ => 'Available from an NPC',
                  },
                  child: Container(
                    padding: EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: comfortable ? 4 : 2,
                    ),
                    decoration: BoxDecoration(
                      color: fill,
                      border: Border.all(color: color.withAlpha(100)),
                      borderRadius: BorderRadius.circular(3),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        AvailabilityGameIcon(
                          artwork: entry.$1,
                          size: comfortable ? 17 : 16,
                          color: color,
                        ),
                        SizedBox(width: comfortable ? 5 : 4),
                        Flexible(
                          child: Text(
                            entry.$2,
                            maxLines: singleLine ? 1 : null,
                            softWrap: !singleLine,
                            key: entry == labels.first ? stockKey : null,
                            style: context.visualTheme.typography.meta.copyWith(
                              fontSize: comfortable ? 14 : 12,
                              fontWeight: comfortable ? FontWeight.w500 : null,
                              fontStyle: comfortable ? FontStyle.normal : null,
                              color: color,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
        ],
      ),
    );
  }

  Widget _layout({
    Key? key,
    required WrapAlignment alignment,
    required double spacing,
    required double runSpacing,
    required List<Widget> children,
  }) {
    if (!singleLine) {
      return Wrap(
        key: key,
        alignment: alignment,
        spacing: spacing,
        runSpacing: runSpacing,
        children: children,
      );
    }
    return Row(
      key: key,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var index = 0; index < children.length; index++) ...[
          if (index > 0) SizedBox(width: spacing),
          if (index == (npc ? 1 : 0) && _showMarket && stockColumnWidth != null)
            SizedBox(
              width: stockColumnWidth,
              child: Align(
                alignment: stockColumnAlignment,
                child: children[index],
              ),
            )
          else
            children[index],
        ],
      ],
    );
  }
}
