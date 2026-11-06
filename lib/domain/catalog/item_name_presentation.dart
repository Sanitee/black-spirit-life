/// Current PC display/copy names without changing persisted recipe keys.
/// Exact legacy keys only: no generic stripping of [Party], [Event] or grades.
/// Item IDs 1401/1403/1405/1407; PC item descriptions checked 2026-11-02.
const reviewedPartyDraughtNames = <String>[
  'Harmony Draught - Human',
  'Harmony Draught - Demihuman',
  'Harmony Draught - Kamasylvia',
  'Harmony Draught - Edania',
];

String itemDisplayName(String name) {
  final folded = name.trim().toLowerCase();
  for (final stable in reviewedPartyDraughtNames) {
    if (folded == stable.toLowerCase() ||
        folded == '[party] ${stable.toLowerCase()}') {
      return '[Party] $stable';
    }
  }
  return name;
}

/// Resolve a copied current name back to its existing internal key. This is
/// input compatibility, not a saved-data migration or a broader alias guess.
String stableItemName(String name) {
  final folded = name.trim().toLowerCase();
  for (final stable in reviewedPartyDraughtNames) {
    if (folded == '[party] ${stable.toLowerCase()}') return stable;
  }
  return name;
}

String itemDisplayLabel(String name, String? label) {
  final display = itemDisplayName(name);
  if (label == null) return display;
  if (display == name || label.contains(display)) return label;
  return label.replaceFirst(name, display);
}
