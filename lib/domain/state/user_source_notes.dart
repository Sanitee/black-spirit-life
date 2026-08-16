import 'planner_state.dart';

/// Returns the note a person explicitly saved for [itemName].
///
/// Bundled recipe notes are intentionally not an input here. They contain
/// catalog provenance and curation details, while Inventory and the Need First
/// info affordance present this value as a user-owned source note.
String? displayableUserSourceNote(ModeState state, String itemName) {
  final metadata = _foldedValue(state.ingredientMeta, itemName);
  final edit = _foldedValue(state.recipeEdits, itemName);
  for (final candidate in <String?>[metadata?.sourceNote, edit?.sourceNote]) {
    final note = sanitizeDisplayableSourceNote(candidate);
    if (note != null) return note;
  }
  return null;
}

/// Removes known catalog-import provenance from user-facing note surfaces.
///
/// Older saves can contain these strings after a bundled item was opened and
/// saved in the editor, so provenance alone is not sufficient to distinguish
/// them from a deliberate note.
String? sanitizeDisplayableSourceNote(String? value) {
  final note = value?.trim();
  if (note == null || note.isEmpty) return null;
  final folded = note.toLowerCase();
  if (folded.startsWith('imported from bdolytics') ||
      folded.startsWith('imported from bdo codex') ||
      folded.contains('icons and item ids checked through bdo codex') ||
      folded.contains('remaining variants stay in import metadata')) {
    return null;
  }
  return note;
}

T? _foldedValue<T>(Map<String, T> values, String name) {
  final exact = values[name];
  if (exact != null) return exact;
  final folded = _fold(name);
  for (final entry in values.entries) {
    if (_fold(entry.key) == folded) return entry.value;
  }
  return null;
}

String _fold(String value) => value.trim().toLowerCase();
