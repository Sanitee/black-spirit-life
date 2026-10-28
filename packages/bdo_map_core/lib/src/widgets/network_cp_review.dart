import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'network_cp_breakdown.dart';
import 'resource_map_chrome_theme.dart';
import 'resource_map_panel_metrics.dart';
import 'resource_map_pill.dart';

/// The route review's compact cost summary. It does not calculate or save a
/// network: the owner retains the existing budget and save action contracts.
class NetworkCpReview extends StatelessWidget {
  const NetworkCpReview({
    super.key,
    required this.budgetController,
    required this.onCommitBudget,
    this.breakdown,
  });

  final TextEditingController budgetController;
  final VoidCallback onCommitBudget;
  final NetworkCpBreakdown? breakdown;

  @override
  Widget build(BuildContext context) {
    final chrome = context.mapChrome;
    final planeStrength = ResourceMapReadingPlane.contains(context) ? .48 : 1.0;
    final headerSource = chrome.subtleSurfaceGradient;
    final headerGradient = resourceMapRaisedSurfaceGradient(
      chrome,
      LinearGradient(
        begin: headerSource.begin,
        end: headerSource.end,
        colors: [
          for (final color in headerSource.colors)
            color.withValues(alpha: color.a * planeStrength),
        ],
        stops: headerSource.stops,
        tileMode: headerSource.tileMode,
        transform: headerSource.transform,
      ),
    );
    const radius = BorderRadius.all(Radius.circular(10));
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: radius,
        border: Border.all(color: chrome.softOutline),
      ),
      child: ClipRRect(
        borderRadius: radius,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DecoratedBox(
              key: const ValueKey('resource-map-review-cost-header'),
              decoration: BoxDecoration(
                gradient: headerGradient,
                border: Border(bottom: BorderSide(color: chrome.softOutline)),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Network cost',
                        style: TextStyle(
                          color: chrome.ink,
                          fontFamily: chrome.headingFontFamily,
                          fontSize: ResourceMapPanelMetrics.primary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      breakdown == null ? '— CP' : '${breakdown!.used} CP',
                      key: const ValueKey('resource-map-review-total-cp'),
                      style: TextStyle(
                        color: chrome.ink,
                        fontSize: 20,
                        fontWeight: FontWeight.w600,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            DecoratedBox(
              key: const ValueKey('resource-map-review-cost-body'),
              decoration: BoxDecoration(
                color: chrome.fillAlpha(chrome.paper, planeStrength),
              ),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildBudget(context),
                    if (breakdown case final costs?) ...[
                      Divider(height: 18, color: chrome.softOutline),
                      costs,
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBudget(BuildContext context) {
    final chrome = context.mapChrome;
    final textScale = MediaQuery.textScalerOf(context).scale(14) / 14;
    final label = Text(
      'Network CP limit',
      style: TextStyle(
        color: chrome.ink,
        fontSize: ResourceMapPanelMetrics.primary,
      ),
    );
    final input = SizedBox(
      width: 76 * textScale.clamp(1.0, 1.5),
      child: Semantics(
        label: 'Network CP limit',
        textField: true,
        child: TextField(
          key: const ValueKey<String>('resource-map-node-cp-budget'),
          controller: budgetController,
          keyboardType: TextInputType.number,
          textAlign: TextAlign.end,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          onSubmitted: (_) => onCommitBudget(),
          onTapOutside: (_) {
            FocusScope.of(context).unfocus();
            onCommitBudget();
          },
          decoration: const InputDecoration(isDense: true),
        ),
      ),
    );
    final apply = TextButton(
      key: const ValueKey<String>('resource-map-node-apply-cp'),
      onPressed: onCommitBudget,
      style: TextButton.styleFrom(
        minimumSize: const Size(0, 32),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      child: const Text('Update'),
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 250 || textScale > 1.35) {
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              label,
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [input, const SizedBox(width: 6), apply],
              ),
            ],
          );
        }
        return Row(
          children: [
            Expanded(child: label),
            const SizedBox(width: 8),
            input,
            const SizedBox(width: 6),
            apply,
          ],
        );
      },
    );
  }
}

/// A quiet separated shelf, keeping the existing route-save action visible
/// while the route's material and node details scroll independently.
class NetworkReviewActionShelf extends StatelessWidget {
  const NetworkReviewActionShelf({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final chrome = context.mapChrome;
    final planeStrength = ResourceMapReadingPlane.contains(context) ? .48 : 1.0;
    return DecoratedBox(
      key: const ValueKey('resource-map-review-action-fill'),
      decoration: BoxDecoration(
        color: chrome.fillAlpha(chrome.controlInset, planeStrength),
        border: Border(top: BorderSide(color: chrome.softOutline)),
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(8)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Align(alignment: Alignment.centerRight, child: child),
      ),
    );
  }
}
