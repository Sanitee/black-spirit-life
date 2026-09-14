import 'package:bdo_craft_planner_flutter/domain/models/craft_mode.dart';
import 'package:bdo_craft_planner_flutter/features/opportunities/opportunities_preferences.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'old settings keep their existing section and gain no selected material',
    () {
      final preferences = OpportunitiesPreferences.fromJson({
        'version': 1,
        'section': 'crafting',
        'mode': 'alchemy',
        'craftSearch': 'Elixir',
        'craftSort': 'preorders',
        'demandOnly': true,
        'readyOnly': true,
        'crafts': 31,
        'extraCostPerRun': 17,
      });
      expect(preferences.section, 'crafting');
      expect(preferences.bestUseItem, isEmpty);
      expect(preferences.mode, CraftMode.alchemy);
      expect(preferences.craftSearch, 'Elixir');
      expect(preferences.craftSort, 'preorders');
      expect(preferences.demandOnly, isTrue);
      expect(preferences.readyOnly, isTrue);
      expect(preferences.crafts, 31);
      expect(preferences.extraCostPerRun, 17);
    },
  );

  test(
    'Best use persists its material independently of crafting and exchanges',
    () {
      final original = OpportunitiesPreferences()
        ..section = 'best-use'
        ..bestUseItem = 'Thuja Sap'
        ..mode = CraftMode.processing
        ..craftSearch = 'Ingot'
        ..exchangeSearch = 'Milk'
        ..currencyId = 'sangpyeong'
        ..craftSort = 'profit'
        ..profitableOnly = false
        ..demandOnly = true
        ..readyOnly = true;
      final restored = OpportunitiesPreferences.fromJson(original.toJson());
      expect(restored.toJson(), original.toJson());
      expect(restored.bestUseItem, 'Thuja Sap');
      expect(restored.mode, CraftMode.processing);
      expect(
        restored.toJson().keys.where(
          (key) => key.toLowerCase().contains('bestuse'),
        ),
        ['bestUseItem'],
      );
    },
  );

  test(
    'malformed Best use selection stays empty without changing sort migration',
    () {
      final result = OpportunitiesPreferences.fromJson({
        'version': 1,
        'section': 'best-use',
        'bestUseItem': 12,
        'craftSort': 'demand',
      });
      expect(result.bestUseItem, isEmpty);
      expect(result.section, 'best-use');
      expect(result.craftSort, 'profit');
      expect(result.demandOnly, isTrue);
      expect(
        OpportunitiesPreferences.fromJson({
          ...result.toJson(),
          'bestUseItem': '  Thuja Sap  ',
        }).bestUseItem,
        'Thuja Sap',
      );
    },
  );
}
