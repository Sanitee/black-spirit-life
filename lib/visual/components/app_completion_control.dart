import 'package:flutter/material.dart';

import '../foundations/theme_spec.dart';
import 'app_button.dart';
import 'app_vector_glyph.dart';

/// Semantic completion action whose material/silhouette is owned by the
/// retained visual system. Planner domain state remains outside this control.
class AppCompletionControl extends StatelessWidget {
  const AppCompletionControl({
    required this.completed,
    required this.onPressed,
    required this.semanticLabel,
    super.key,
  });

  final bool completed;
  final VoidCallback? onPressed;
  final String semanticLabel;

  @override
  Widget build(BuildContext context) {
    final tokens = context.visualTheme;
    final ledger = tokens.isIlluminatedLedger;
    final sakura = tokens.isSakuraNightGarden;
    final dimension = tokens.usesDenseSplitLayout ? 46.0 : 48.0;
    return SizedBox.square(
      dimension: dimension,
      child: AppButton(
        role: AppButtonRole.completion,
        selected: completed,
        semanticLabel: semanticLabel,
        tooltip: semanticLabel,
        minimumSize: Size.square(dimension),
        padding: EdgeInsets.zero,
        onPressed: onPressed,
        child: ledger && completed
            ? const Icon(Icons.undo_rounded, size: 23)
            : AppVectorGlyph(
                'check',
                size: sakura ? 20 : 23,
                tightBounds: true,
              ),
      ),
    );
  }
}
