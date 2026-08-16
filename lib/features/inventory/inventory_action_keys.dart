import 'package:flutter/widgets.dart';

/// Stable acceptance-test identifiers for the complete Inventory action slice.
abstract final class InventoryActionKeys {
  static const i01 = ValueKey<String>('I01');
  static const i02 = ValueKey<String>('I02');
  static const i03 = ValueKey<String>('I03');
  static const i04 = ValueKey<String>('I04');
  static const i05 = ValueKey<String>('I05');
  static const i06 = ValueKey<String>('I06');
  static const i07 = ValueKey<String>('I07');
  static const i08 = ValueKey<String>('I08');
  static const i08Selector = ValueKey<String>('I08-selector');
  static const i09 = ValueKey<String>('I09');
  static const i10 = ValueKey<String>('I10');
  static const i11 = ValueKey<String>('I11');
  static const i12 = ValueKey<String>('I12');
  static const i13 = ValueKey<String>('I13');
  static const i14 = ValueKey<String>('I14');
  static const pasteScreenshot = ValueKey<String>(
    'inventory-paste-screenshot',
  );
  static const chooseScreenshot = ValueKey<String>(
    'inventory-choose-screenshot',
  );
  static const addStorage = ValueKey<String>('inventory-add-storage');

  static Key row(String actionId, String stableName) =>
      ValueKey<String>('$actionId:$stableName');

  static Key group(String category) => ValueKey<String>('I02:$category');

  static Key storage(String id) => ValueKey<String>('inventory-storage:$id');

  static Key smartGroup(String name) =>
      ValueKey<String>('inventory-family:$name');

  static Key filter(String name) => ValueKey<String>('inventory-filter:$name');
}
