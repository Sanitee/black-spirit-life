import 'dart:io';

import 'package:bdo_gathering_companion/bdo_gathering_companion.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../../visual/foundations/theme_spec.dart';

CompanionVisualPalette gatheringPaletteForTheme(ThemeSpec theme) {
  final p = theme.palette;
  return CompanionVisualPalette(
    brightness: theme.brightness,
    canvas: p.canvas,
    canvasDeep: p.canvasDeep,
    surface: p.surface,
    raised: p.surfaceRaised,
    inset: p.surfaceInset,
    ink: p.text,
    // Keep the same warm text hue, with extra strength over the map's glass.
    muted: Color.lerp(p.textMuted, p.text, .27)!,
    accent: p.primary,
    accentBright: p.primaryBright,
    gold: p.secondary,
    edge: p.trim,
    // Opportunities uses the theme's coloured metal, not its pale reflection.
    rim: p.trimBright,
    positive: p.success,
    warning: p.warning,
    danger: p.danger,
  );
}

class GatheringWorkspace extends StatelessWidget {
  const GatheringWorkspace({
    required this.dataDirectory,
    this.durabilityController,
    this.sharedMarketLoader,
    this.sharedMarketUpdates,
    this.marketFreshFor = const Duration(minutes: 2),
    this.theme,
    this.recipeChecklistBuilder,
    this.recipeChecklistController,
    super.key,
  });

  final Directory dataDirectory;
  final GatheringDurabilityController? durabilityController;
  final GatheringSharedMarketLoader? sharedMarketLoader;
  final Stream<GatheringMarketReceipt>? sharedMarketUpdates;
  final Duration marketFreshFor;
  final ValueListenable<ThemeSpec>? theme;
  final GatheringRecipeChecklistBuilder? recipeChecklistBuilder;
  final GatheringRecipeChecklistController? recipeChecklistController;

  @override
  Widget build(BuildContext context) {
    final source = theme;
    if (source == null) return _feature(null);
    return ValueListenableBuilder<ThemeSpec>(
      valueListenable: source,
      builder: (context, value, child) =>
          _feature(gatheringPaletteForTheme(value)),
    );
  }

  Widget _feature(CompanionVisualPalette? palette) => GatheringCompanionFeature(
    recipeChecklistBuilder: recipeChecklistBuilder,
    recipeChecklistController: recipeChecklistController,
    visualPalette: palette,
    dataDirectory: dataDirectory,
    durabilityController: durabilityController,
    sharedMarketLoader: sharedMarketLoader,
    sharedMarketUpdates: sharedMarketUpdates,
    marketFreshFor: marketFreshFor,
    // The independent experiment starts clean. Importing a standalone journal
    // must remain a deliberate user action, never an implicit startup read.
  );
}

@visibleForTesting
Future<void> migrateLegacyGatheringSessions({
  required Directory destinationDirectory,
  Directory? legacyDirectory,
}) async {
  final roamingPath = Platform.environment['APPDATA']?.trim();
  final sourceDirectory =
      legacyDirectory ??
      (roamingPath == null || roamingPath.isEmpty
          ? null
          : Directory(
              '$roamingPath${Platform.pathSeparator}BDO Gathering Companion',
            ));
  if (sourceDirectory == null ||
      sourceDirectory.absolute.path.toLowerCase() ==
          destinationDirectory.absolute.path.toLowerCase()) {
    return;
  }

  final source = File(
    '${sourceDirectory.path}${Platform.pathSeparator}sessions.json',
  );
  final destination = File(
    '${destinationDirectory.path}${Platform.pathSeparator}sessions.json',
  );
  if (!await source.exists() || await destination.exists()) return;

  await destinationDirectory.create(recursive: true);
  await _copyGatheringFileWithoutOverwrite(source, destination);

  final sourceBackup = File('${source.path}.bak');
  final destinationBackup = File('${destination.path}.bak');
  if (await sourceBackup.exists() && !await destinationBackup.exists()) {
    await _copyGatheringFileWithoutOverwrite(sourceBackup, destinationBackup);
  }
}

Future<void> _copyGatheringFileWithoutOverwrite(
  File source,
  File destination,
) async {
  if (await destination.exists()) return;
  final temporary = File('${destination.path}.legacy-import');
  try {
    await source.copy(temporary.path);
    if (await destination.exists()) return;
    await temporary.rename(destination.path);
  } finally {
    if (await temporary.exists()) await temporary.delete();
  }
}
