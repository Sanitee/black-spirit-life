import 'package:flutter/material.dart';

import '../../visual/visual.dart';
import 'opportunities_controller.dart';

/// Only unfinished market work needs a progress row. Loaded results remain in
/// the workspace while another request group is loading or waiting to resume.
class OpportunityMarketProgress extends StatelessWidget {
  const OpportunityMarketProgress({
    required this.status,
    required this.label,
    this.showLoading = true,
    super.key,
  });

  final OpportunityMarketLoadStatus status;
  final String label;

  /// Quiet background checks must not insert/remove space above a scrolling
  /// workspace. Failures and blocked requests still remain visible.
  final bool showLoading;

  @override
  Widget build(BuildContext context) {
    if (status.complete ||
        ((!showLoading || !status.loading) &&
            status.failed == 0 &&
            !status.blocked)) {
      return const SizedBox.shrink();
    }
    final spec = context.visualTheme;
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '$label · ${status.loaded} / ${status.total}'
            '${status.failed > 0 ? ' · ${status.failed} failed' : ''}',
            style: spec.typography.meta.copyWith(
              color: status.failed > 0 || status.blocked
                  ? spec.palette.warning
                  : null,
            ),
          ),
          if (showLoading && status.loading) ...[
            const SizedBox(height: 4),
            LinearProgressIndicator(
              value: status.total == 0 ? null : status.loaded / status.total,
              minHeight: 2,
              semanticsLabel:
                  '$label: ${status.loaded} of ${status.total} loaded',
            ),
          ],
        ],
      ),
    );
  }
}
