import 'package:bdo_craft_planner_flutter/domain/models/craft_mode.dart';
import 'package:bdo_craft_planner_flutter/domain/state/planner_state.dart';
import 'package:bdo_craft_planner_flutter/features/resource_map/resource_map_theme_adapter.dart';
import 'package:bdo_craft_planner_flutter/visual/foundations/application_theme.dart';
import 'package:bdo_craft_planner_flutter/visual/illuminated_ledger/ledger_spec.dart';
import 'package:bdo_craft_planner_flutter/visual/sakura_night_garden/sakura_spec.dart';

import '../../../packages/bdo_map_core/test/resource_map_navigation_glass_test.dart'
    as fixture;

void main() => fixture.resourceMapNavigationGlassTests(
  onlyAppearance: true,
  appearanceThemes: {
    'sakura': resourceMapChromeThemeForPlannerTheme(
      SakuraNightGardenSpec.theme,
    ),
    'ledger': resourceMapChromeThemeForPlannerTheme(
      IlluminatedLedgerSpec.theme,
    ),
    'forest': resourceMapChromeThemeForPlannerTheme(
      applicationThemeForAppearance(
        AppearanceSettings.classicDefaultsFor(CraftMode.alchemy),
      ),
    ),
  },
);
