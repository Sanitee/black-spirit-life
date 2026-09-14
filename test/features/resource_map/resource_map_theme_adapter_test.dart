import 'package:bdo_craft_planner_flutter/features/resource_map/resource_map_theme_adapter.dart';
import 'package:bdo_craft_planner_flutter/visual/foundations/theme_spec.dart';
import 'package:bdo_craft_planner_flutter/visual/illuminated_ledger/ledger_spec.dart';
import 'package:bdo_craft_planner_flutter/visual/sakura_night_garden/sakura_spec.dart';
import 'package:bdo_craft_planner_flutter/visual/standard/standard_spec.dart';
import 'package:bdo_map_core/bdo_map_core.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('planner themes resolve to the independent Glass Dock skin', () {
    expect(
      resourceMapChromeThemeForPlannerTheme(SakuraNightGardenSpec.theme),
      same(ResourceMapChromeThemeData.fieldAtlas),
    );
    expect(
      resourceMapChromeThemeForPlannerTheme(IlluminatedLedgerSpec.theme),
      same(ResourceMapChromeThemeData.fieldAtlas),
    );
  });

  test('Ghost Ledger resolves independently from the planner appearance', () {
    for (final spec in <ThemeSpec>[
      SakuraNightGardenSpec.theme,
      IlluminatedLedgerSpec.theme,
      StandardSpec.theme,
    ]) {
      expect(
        resourceMapChromeThemeForPlannerTheme(
          spec,
          interfaceStyle: ResourceMapInterfaceStyle.ghostLedger,
        ),
        same(ResourceMapChromeThemeData.ghostLedger),
      );
    }
  });

  test('Standard scenes also use the independent field atlas skin', () {
    expect(
      resourceMapChromeThemeForPlannerTheme(StandardSpec.theme),
      same(ResourceMapChromeThemeData.fieldAtlas),
    );
  });
}
