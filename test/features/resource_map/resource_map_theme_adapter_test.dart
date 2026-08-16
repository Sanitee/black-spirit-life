import 'package:bdo_craft_planner_flutter/features/resource_map/resource_map_theme_adapter.dart';
import 'package:bdo_craft_planner_flutter/visual/illuminated_ledger/ledger_spec.dart';
import 'package:bdo_craft_planner_flutter/visual/sakura_night_garden/sakura_spec.dart';
import 'package:bdo_craft_planner_flutter/visual/standard/standard_spec.dart';
import 'package:bdo_map_core/bdo_map_core.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('planner themes resolve to their approved Resource Map skins', () {
    expect(
      resourceMapChromeThemeForPlannerTheme(SakuraNightGardenSpec.theme),
      same(ResourceMapChromeThemeData.sakuraCartographer),
    );
    expect(
      resourceMapChromeThemeForPlannerTheme(IlluminatedLedgerSpec.theme),
      same(ResourceMapChromeThemeData.illuminatedAtlas),
    );
  });

  test('Standard scenes preserve the established map chrome', () {
    expect(
      resourceMapChromeThemeForPlannerTheme(StandardSpec.theme),
      same(ResourceMapChromeThemeData.sakuraCartographer),
    );
  });
}
