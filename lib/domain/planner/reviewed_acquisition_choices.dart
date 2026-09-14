import '../models/catalog_models.dart';
import '../models/craft_mode.dart';
import '../state/planner_state.dart';

const processingAcquisitionChoicesKey = 'processingAcquisitionChoices';

bool hasReviewedProcessingChoice(CraftMode mode, String name) {
  final folded = name.trim().toLowerCase();
  return (mode == CraftMode.cooking && folded == 'cooking honey') ||
      (mode != CraftMode.processing && folded == 'purified water');
}

Set<String> selectedProcessingAcquisitions(ModeState state) {
  final raw = state.extensions[processingAcquisitionChoicesKey];
  if (raw is! Map) return const {};
  return {
    for (final entry in raw.entries)
      if (entry.key is String && entry.value == 'process')
        (entry.key as String).trim().toLowerCase(),
  };
}

Recipe? reviewedProcessingAcquisition({
  required CatalogSnapshot catalog,
  required CraftMode mode,
  required String name,
}) {
  if (!hasReviewedProcessingChoice(mode, name)) return null;
  final folded = name.trim().toLowerCase();
  final local = catalog
      .forMode(mode)
      .items
      .values
      .where((recipe) => recipe.name.toLowerCase() == folded)
      .firstOrNull;
  if (local?.isManualConversion != true) return null;
  final processing = catalog.processing.items.values
      .where((recipe) => recipe.name.toLowerCase() == folded)
      .firstOrNull;
  return processing?.isCraftable == true ? processing : null;
}
