import 'package:flutter/material.dart';

import '../../domain/formatting/planner_formatters.dart';
import '../../visual/visual.dart';

/// The compact, trailing total below the Need First list.
class PlannerMarketSummary extends StatelessWidget {
  const PlannerMarketSummary({
    required this.total,
    required this.loading,
    required this.fetchedAt,
    required this.region,
    this.hasUnknownPrices = false,
    this.message,
    super.key,
  });

  final double total;
  final bool loading;
  final int fetchedAt;
  final String region;
  final bool hasUnknownPrices;
  final String? message;

  static const surfaceKey = ValueKey('planner-market-summary-surface');

  @override
  Widget build(BuildContext context) {
    final spec = context.visualTheme;
    final time = formatMarketFetchedTime(fetchedAt);
    return Padding(
      padding: const EdgeInsets.only(top: 2, bottom: 8),
      child: Align(
        alignment: Alignment.centerRight,
        child: AppSurface(
          key: surfaceKey,
          role: AppSurfaceRole.row,
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
          tone: loading ? AppSurfaceTone.info : AppSurfaceTone.neutral,
          semanticLabel: [
            'Market price summary',
            if (hasUnknownPrices)
              'Some item prices are unavailable; total is incomplete',
            'Last fetched ${formatMarketFetchedAt(fetchedAt)}',
            if (region.trim().isNotEmpty) 'Region ${region.toUpperCase()}',
            if (message?.trim().isNotEmpty ?? false) message!.trim(),
          ].join('. '),
          child: Wrap(
            alignment: WrapAlignment.end,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 18,
            runSpacing: 6,
            children: [
              Text(
                hasUnknownPrices && total > 0 ? 'Known Cost' : 'Estimated Cost',
                style: spec.typography.label,
              ),
              Text(
                hasUnknownPrices && total <= 0 ? '—' : formatSilver(total),
                style: spec.typography.section.copyWith(fontSize: 21),
              ),
              if (time.isNotEmpty)
                Container(
                  padding: const EdgeInsets.only(left: 14),
                  decoration: BoxDecoration(
                    border: Border(
                      left: BorderSide(
                        color: spec.palette.textMuted.withAlpha(90),
                      ),
                    ),
                  ),
                  child: Text(time, style: spec.typography.meta),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
