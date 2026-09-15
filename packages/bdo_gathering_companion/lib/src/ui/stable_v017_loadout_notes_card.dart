import 'package:flutter/material.dart';

import 'theme.dart';

class StableV017GatheringLoadoutNotesCard extends StatelessWidget {
  const StableV017GatheringLoadoutNotesCard({required this.notes, super.key});

  final String notes;

  @override
  Widget build(BuildContext context) {
    if (notes.isEmpty) return const SizedBox.shrink();
    return GlassSurface(
      key: const ValueKey('stable-v017-gathering-loadout-notes'),
      elevated: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Imported v0.1.7 loadout notes',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 6),
          const Text(
            'Kept from your previous local Gathering profile.',
            style: TextStyle(color: muted),
          ),
          const SizedBox(height: 10),
          SelectableText(notes),
        ],
      ),
    );
  }
}
