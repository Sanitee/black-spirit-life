import 'package:flutter/material.dart';

import 'theme.dart';

/// One visible review message for old Khan setups in every preparation host.
/// Showing it never changes or subtracts from saved character values.
class GatheringStoneStatReview extends StatelessWidget {
  const GatheringStoneStatReview({super.key});

  @override
  Widget build(BuildContext context) => Text(
    'Khan’s Heart now includes +25 mastery. Recheck your base stats '
    'without selected buffs and stones.',
    key: const ValueKey('gathering-stone-stat-review'),
    // This instruction must remain readable; secondary accent colors are not
    // text-contrast safe on every supplied theme's reading surface.
    style: TextStyle(color: context.gatheringColors.ink),
  );
}
