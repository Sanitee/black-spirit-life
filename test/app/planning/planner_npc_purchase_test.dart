import 'dart:io';

import 'package:bdo_craft_planner_flutter/app/planning/planner_assembly.dart';
import 'package:bdo_craft_planner_flutter/app/state/planner_application_controller.dart';
import 'package:bdo_craft_planner_flutter/data/catalog/bundled_catalog_parser.dart';
import 'package:bdo_craft_planner_flutter/data/catalog/catalog_repository.dart';
import 'package:bdo_craft_planner_flutter/domain/models/catalog_models.dart';
import 'package:bdo_craft_planner_flutter/domain/models/craft_mode.dart';
import 'package:bdo_craft_planner_flutter/domain/state/planner_state.dart';
import 'package:flutter_test/flutter_test.dart';

const _catalyst = 'Concentrated Spellbound Catalyst';

void main() {
  late CatalogSnapshot catalog;
  const assembly = PlannerAssembly();

  setUpAll(() {
    catalog = const BundledCatalogParser().parse(
      File('assets/data/app-data.json').readAsStringSync(),
    );
  });

  test(
    'recorded catalyst purchase fact stays separate from its exchange recipe',
    () {
      final reference = catalog.processing.items[_catalyst]!;
      expect(reference.npcPrice, 10000000);
      expect(reference.role, RecipeRole.manualConversion);
      expect(reference.ingredients.single.name, 'Spellbound Catalyst');
      expect(reference.ingredients.single.quantity, 10);
      expect(catalog.alchemy.items.containsKey(_catalyst), isFalse);
      expect(
        CatalogRepository.cached(catalog).npcPurchasePrices[_catalyst
            .toLowerCase()],
        10000000,
      );
    },
  );

  for (final mode in CraftMode.values) {
    for (final owned in [0.0, 20.0]) {
      test(
        '$mode charges verified NPC price for only missing catalyst ($owned owned)',
        () {
          final plan = assembly.build(
            catalog: catalog,
            mode: mode,
            state: _state(mode, owned: owned),
          );
          final row = plan.missing.singleWhere((row) => row.name == _catalyst);
          expect(row.need, 50);
          expect(row.have, owned);
          expect(row.missing, 50 - owned);
          expect(row.market.status, 'vendor');
          expect(row.market.marketable, isFalse);
          expect(row.market.price, 10000000);
          expect(row.market.total, (50 - owned) * 10000000);
        },
      );
    }
    test('$mode keeps valid custom NPC purchase price precedence', () {
      final plan = assembly.build(
        catalog: catalog,
        mode: mode,
        state: _state(mode, customPrice: 9000000),
      );
      final row = plan.missing.singleWhere((row) => row.name == _catalyst);
      expect(row.market.price, 9000000);
      expect(row.market.total, 450000000);
    });
  }

  test(
    'feature source details use the same cross-mode purchase rules without saving',
    () async {
      var saves = 0;
      final controller = PlannerApplicationController(
        catalog: catalog,
        initialState: PlannerState(
          applicationVersion: 'test',
          lastSuccessfulWriteUtc: DateTime.utc(2026),
          activeMode: CraftMode.alchemy,
          alchemy: _state(CraftMode.alchemy),
          cooking: _state(CraftMode.cooking),
          processing: _state(CraftMode.processing),
          processingYields: const {},
          marketTax: MarketTax(),
        ),
        saveState: (state) async {
          saves++;
          return state;
        },
      );
      try {
        for (final feature in controller.modes.values) {
          expect(feature.resolveItemSource(_catalyst).npcPrice, 10000000);
          expect(feature.resolveItemSource('Unrecorded item').npcPrice, 0);
        }
      } finally {
        await controller.dispose();
      }
      expect(saves, 0);
    },
  );
}

ModeState _state(CraftMode mode, {double owned = 0, double customPrice = 0}) =>
    ModeState(
      target: 'NPC purchase regression fixture',
      want: 50,
      bonusTarget: '',
      inventory: {_catalyst: owned},
      ignoreIngredientInventory: false,
      recipeEdits: {
        'NPC purchase regression fixture': RecipeState(
          type: 'processing',
          baseOutput: 1,
          outputMinimum: 1,
          outputMaximum: 1,
          ingredients: [IngredientState(name: _catalyst, quantity: 1)],
        ),
      },
      ingredientMeta: {
        if (customPrice > 0)
          _catalyst: IngredientMetadata(npcPrice: customPrice),
      },
      // An old market cache is not an NPC buying price.
      market: MarketState(
        prices: const {_catalyst: 1},
        stock: const {_catalyst: 0},
      ),
      appearance: AppearanceSettings.defaultsFor(mode),
    );
