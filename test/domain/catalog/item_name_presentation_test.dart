import 'package:bdo_craft_planner_flutter/domain/catalog/item_name_presentation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final stable in reviewedPartyDraughtNames) {
    test('$stable displays canonically without changing saved keys', () {
      final current = '[Party] $stable';
      expect(itemDisplayName(stable), current);
      expect(itemDisplayName(current), current);
      expect(stableItemName(current), stable);
      expect(stableItemName(stable), stable);
      expect(itemDisplayLabel(stable, '$stable ×10'), '$current ×10');
      expect(itemDisplayLabel(stable, '$current ×10'), '$current ×10');
      expect(itemDisplayLabel(stable, null), current);
      expect(itemDisplayLabel(stable, 'Custom label'), 'Custom label');
    });
  }
  test('no inferred aliases for base, immortal, event or unrelated items', () {
    for (final name in [
      'Harmony Draught',
      'Immortal: Harmony Draught - Human',
      '[Event] Harmony Draught - Human',
      'Sugar',
      '[Party] Elixir of Fury',
    ]) {
      expect(itemDisplayName(name), name);
      expect(stableItemName(name), name);
    }
  });
}
