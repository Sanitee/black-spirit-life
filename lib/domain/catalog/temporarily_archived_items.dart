/// Reversible availability review, not a claim that these items were removed.
/// Keep raw catalog records and saved state intact; normal choices and market
/// requests consult this policy instead of deleting historical identities.
const temporarilyArchivedItemsById = <String, String>{
  '6211': 'Monkey Blood',
  '6011': 'Monkey Hide',
  '6007': 'Dinosaur Hide',
  '15202': 'Black Magic Crystal - Power',
  '15208': 'Black Magic Crystal - Patience',
  '15209': 'Black Magic Crystal - Healing',
  '15210': 'Black Magic Crystal - Resonance',
  '15215': 'Black Magic Crystal - Endurance',
};

const temporarilyArchivedItemLabel = 'Temporarily archived';
const temporarilyArchivedItemReason = 'No current source confirmed.';

bool isTemporarilyArchivedMarketItemId(String itemId) {
  final numeric = int.tryParse(itemId.trim());
  return numeric != null &&
      numeric > 0 &&
      temporarilyArchivedItemsById.containsKey('$numeric');
}

bool isTemporarilyArchivedItem(String name, {String? itemId}) {
  final numeric = itemId == null ? null : int.tryParse(itemId.trim());
  // An explicit different identity wins over a same-name custom alias. The
  // fallback is exact folded-name matching only, never a crystal-family match.
  if (numeric != null && numeric > 0) {
    return isTemporarilyArchivedMarketItemId('$numeric');
  }
  final folded = name.trim().toLowerCase();
  return temporarilyArchivedItemsById.values.any(
    (canonical) => canonical.toLowerCase() == folded,
  );
}
