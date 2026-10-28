import 'package:flutter/material.dart';

import 'ui/reference_window.dart';
import 'ui/theme.dart';
import 'ui/visual_palette.dart';

CompanionVisualPalette? gatheringReferenceVisualPalette(List<String> args) {
  final argument = args
      .where((value) => value.startsWith('--gathering-theme='))
      .firstOrNull;
  return CompanionVisualPalette.decode(
    argument?.substring('--gathering-theme='.length),
  );
}

bool isGatheringReferenceMode(List<String> args) =>
    args.contains('--reference');

int gatheringReferenceGlassOpacity(List<String> args) {
  final argument = args
      .where((value) => value.startsWith('--glass-opacity='))
      .firstOrNull;
  return normalizeGlassOpacity(argument?.substring('--glass-opacity='.length));
}

/// Runs the accepted standalone Minigame Helper in its own process.
///
/// This deliberately opens no gathering session store and persists no pasted
/// image. The Windows bridge launches this same executable with `--reference`.
void runGatheringReferenceMode(List<String> args) {
  WidgetsFlutterBinding.ensureInitialized();
  PaintingBinding.instance.imageCache.maximumSizeBytes = 64 * 1024 * 1024;
  runApp(
    MaterialApp(
      title: 'Minigame Helper',
      debugShowCheckedModeBanner: false,
      theme: companionTheme(
        opacityPercent: gatheringReferenceGlassOpacity(args),
        visualPalette: gatheringReferenceVisualPalette(args),
      ),
      builder: companionBackdropBuilder,
      home: const ReferenceWindow(),
    ),
  );
}
