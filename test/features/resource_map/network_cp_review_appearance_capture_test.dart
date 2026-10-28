import 'package:bdo_craft_planner_flutter/domain/models/craft_mode.dart';
import 'package:bdo_craft_planner_flutter/domain/state/planner_state.dart';
import 'package:bdo_craft_planner_flutter/features/resource_map/resource_map_theme_adapter.dart';
import 'package:bdo_craft_planner_flutter/visual/foundations/application_theme.dart';
import 'package:bdo_craft_planner_flutter/visual/illuminated_ledger/ledger_spec.dart';
import 'package:bdo_craft_planner_flutter/visual/sakura_night_garden/sakura_spec.dart';

import '../../../packages/bdo_map_core/test/network_cp_review_test.dart'
    as fixture;

void main() {
  final themes = {
    'sakura': SakuraNightGardenSpec.theme,
    'ledger': IlluminatedLedgerSpec.theme,
    'forest': applicationThemeForAppearance(
      AppearanceSettings.classicDefaultsFor(CraftMode.alchemy),
    ),
  };
  fixture.networkCpReviewTests(
    onlyAppearance: true,
    appearanceThemes: {
      for (final entry in themes.entries)
        entry.key: (
          chrome: resourceMapChromeThemeForPlannerTheme(entry.value),
          theme: entry.value.materialTheme(),
        ),
    },
  );
}
