import '../models/catalog_models.dart';
import '../models/craft_mode.dart';

/// The canonical recipe to present when explaining how an item is obtained.
///
/// Mode-local planner snapshots contain terminal leaf records for every
/// referenced ingredient. Those records keep dependency planning complete,
/// but they are not evidence that the item is gathered. A real recipe from
/// another workstation therefore outranks an empty local leaf.
final class ResolvedAcquisitionRecipe {
  const ResolvedAcquisitionRecipe({
    required this.name,
    required this.recipe,
    required this.mode,
  });

  final String name;
  final Recipe recipe;
  final CraftMode mode;
}

/// Resolves one item across the assembled recipe maps for every workstation.
///
/// A craftable recipe always wins over an empty planner leaf. Within the same
/// class of candidate, the current workstation wins, followed by the stable
/// [CraftMode] order. Callers can suppress a workstation when that mode has an
/// explicit deletion tombstone for [name]. Reference-only manual conversions
/// and salvage recipes are never presented as primary acquisition routes.
ResolvedAcquisitionRecipe? resolveAcquisitionRecipe({
  required String name,
  required CraftMode currentMode,
  required Map<CraftMode, Map<String, Recipe>> recipesByMode,
  Set<CraftMode> suppressedModes = const <CraftMode>{},
}) {
  final candidates = <ResolvedAcquisitionRecipe>[];
  final orderedModes = <CraftMode>[
    currentMode,
    for (final mode in CraftMode.values)
      if (mode != currentMode) mode,
  ];
  for (final mode in orderedModes) {
    if (suppressedModes.contains(mode)) continue;
    final entry = _foldedEntry(recipesByMode[mode], name);
    if (entry == null) continue;
    candidates.add(
      ResolvedAcquisitionRecipe(
        name: entry.key,
        recipe: entry.value,
        mode: mode,
      ),
    );
  }
  for (final candidate in candidates) {
    if (candidate.recipe.isCraftable) return candidate;
  }
  for (final candidate in candidates) {
    if (!candidate.recipe.hasRecordedRecipe) return candidate;
  }
  return null;
}

MapEntry<String, Recipe>? _foldedEntry(
  Map<String, Recipe>? recipes,
  String name,
) {
  if (recipes == null) return null;
  final exact = recipes[name];
  if (exact != null) return MapEntry<String, Recipe>(name, exact);
  final foldedName = _fold(name);
  final matches =
      recipes.entries
          .where((entry) => _fold(entry.key) == foldedName)
          .toList(growable: false)
        ..sort((left, right) => left.key.compareTo(right.key));
  return matches.isEmpty ? null : matches.first;
}

String _fold(String value) => value.trim().toLowerCase();
