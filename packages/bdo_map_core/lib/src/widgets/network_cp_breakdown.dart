import 'package:flutter/material.dart';

import 'resource_map_chrome_theme.dart';
import 'resource_map_panel_metrics.dart';

/// Displays the same route costs used by the plan's save/budget checks.
class NetworkCpBreakdown extends StatelessWidget {
  const NetworkCpBreakdown({
    super.key,
    required this.limit,
    required this.keptNodes,
    required this.newNodes,
    this.lodgingHouses = 0,
    this.royalWorkshops = 0,
  });

  final int limit;
  final int keptNodes;
  final int newNodes;
  final int lodgingHouses;
  final int royalWorkshops;

  int get used => keptNodes + newNodes + lodgingHouses + royalWorkshops;
  int get remaining => limit - used;

  @override
  Widget build(BuildContext context) {
    final chrome = context.mapChrome;
    Widget row(String label, int amount, {bool balance = false}) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                color: balance ? chrome.ink : chrome.muted,
                fontSize: ResourceMapPanelMetrics.primary,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Text(
            balance ? '$amount CP' : '$amount',
            style: TextStyle(
              color: balance && amount < 0 ? chrome.error : chrome.ink,
              fontSize: ResourceMapPanelMetrics.primary,
              fontWeight: balance ? FontWeight.w600 : FontWeight.w500,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (keptNodes > 0) row('Kept nodes', keptNodes),
        row('New nodes', newNodes),
        if (lodgingHouses > 0) row('Lodging houses', lodgingHouses),
        if (royalWorkshops > 0) row('Royal Workshops', royalWorkshops),
        Divider(height: 10, color: chrome.softOutline),
        row('Remaining', remaining, balance: true),
      ],
    );
  }
}
