import 'package:flutter/material.dart';

import '../domain/models.dart';
import '../domain/world_map.dart';
import '../ui/theme.dart';
import 'spot_map.dart';

/// A large, temporary map. Selecting a spot returns it immediately.
Future<Spot?> showSpotMapPicker({
  required BuildContext context,
  required List<Spot> spots,
  required Spot? selected,
  required List<Method> methods,
  required List<WorldNode> nodes,
}) => showDialog<Spot>(
  context: context,
  builder: (dialogContext) {
    final size = MediaQuery.sizeOf(dialogContext);
    final inset = size.width < 800 ? 12.0 : 24.0;
    return Dialog(
      insetPadding: EdgeInsets.all(inset),
      constraints: BoxConstraints(
        maxWidth: size.width - inset * 2,
        maxHeight: size.height - inset * 2,
      ),
      child: SizedBox(
        width: size.width - inset * 2,
        height: size.height - inset * 2,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Choose a spot',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  GatheringQuietIconButton(
                    key: const ValueKey('close-spot-map'),
                    tooltip: 'Close',
                    onPressed: () => Navigator.of(dialogContext).pop(),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Expanded(
                child: SpotMap(
                  spots: spots,
                  selected: selected,
                  methods: methods,
                  nodes: nodes,
                  overview: selected == null,
                  onSelect: (spot) => Navigator.of(dialogContext).pop(spot),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  },
);
