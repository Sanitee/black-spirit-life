import 'dart:io';
import 'package:bdo_craft_planner_flutter/app/state/planner_application_controller.dart';
import 'package:bdo_craft_planner_flutter/data/catalog/bundled_catalog_parser.dart';
import 'package:bdo_craft_planner_flutter/domain/models/catalog_models.dart';
import 'package:bdo_craft_planner_flutter/domain/models/craft_mode.dart';
import 'package:bdo_craft_planner_flutter/domain/state/planner_state.dart';
import 'package:bdo_craft_planner_flutter/domain/state/state_copy.dart';
import 'package:bdo_craft_planner_flutter/features/planner/planner_review_panels.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late CatalogSnapshot catalog;
  setUpAll(() {
    catalog = const BundledCatalogParser().parse(
      File('assets/data/app-data.json').readAsStringSync(),
    );
  });

  test(
    'owned previews preserve unequal substitution ratios and never commit',
    () async {
      final app = controller(
        catalog,
        CraftMode.alchemy,
        'Elixir of Concentration',
        1,
      );
      addTearDown(app.dispose);
      final mode = app.active;
      final ingredient = mode.recipes['Elixir of Concentration']!.ingredients
          .firstWhere((i) => i.name == 'Weeds');
      mode.commitInventory('Weeds', '1');
      mode.commitInventory('Wild Grass', '1');
      final before = app.documentSnapshot.toJson();
      final planBefore = mode.plan.value;
      final weeds = mode.previewSubstituteAmounts(
        parentName: 'Elixir of Concentration',
        ingredient: ingredient,
        selection: 'Weeds',
      );
      final grass = mode.previewSubstituteAmounts(
        parentName: 'Elixir of Concentration',
        ingredient: ingredient,
        selection: 'Wild Grass',
      );
      expect(weeds.missing, 7);
      expect(grass.missing, 1);
      expect(weeds.owned, 1);
      expect(grass.owned, 1);
      expect(weeds.needed, 8);
      expect(grass.needed, 2);
      expect(app.documentSnapshot.toJson(), before);
      expect(mode.plan.value, same(planBefore));
      mode.selectSubstitute(
        parentName: 'Elixir of Concentration',
        ingredient: ingredient,
        selection: 'Wild Grass',
      );
      expect(
        mode.plan.value.missing
            .firstWhere((r) => r.name == 'Wild Grass')
            .missing,
        grass.missing,
      );
    },
  );

  test(
    'owned previews retain manual grade and show the actual graded item',
    () async {
      final app = controller(catalog, CraftMode.cooking, 'Beer', 1000);
      addTearDown(app.dispose);
      final mode = app.active;
      final grain = mode.recipes['Beer']!.ingredients.firstWhere(
        (i) => i.options.contains('Corn'),
      );
      mode.selectSubstitute(
        parentName: 'Beer',
        ingredient: grain,
        selection: 'Corn',
      );
      mode.selectIngredientGrade(
        parentName: 'Beer',
        ingredientName: grain.name,
        selectedName: 'Corn',
        grade: 'high',
      );
      mode.commitInventory('High-Quality Wheat', '123');
      final before = app.documentSnapshot.toJson();
      final preview = mode.previewSubstituteAmounts(
        parentName: 'Beer',
        ingredient: grain,
        selection: 'Wheat',
      );
      expect(preview.name, 'High-Quality Wheat');
      expect(preview.owned, 123);
      expect(app.documentSnapshot.toJson(), before);
      mode.selectSubstitute(
        parentName: 'Beer',
        ingredient: grain,
        selection: 'Wheat',
      );
      final row = mode.plan.value.missing.firstWhere(
        (r) => r.name == preview.name,
      );
      expect(preview.missing, row.missing);
      expect(preview.needed, row.need);
    },
  );

  test(
    'automatic grade previews can mix normal and high even with none owned',
    () async {
      final app = controller(catalog, CraftMode.cooking, 'Beer', 100);
      addTearDown(app.dispose);
      final mode = app.active;
      app.updateDocument(
        (doc) => doc.copyWith(
          cooking: doc.cooking.copyWith(
            market: MarketState(
              prices: {
                'Barley': 10,
                'High-Quality Barley': 100,
                'Special Barley': 1000,
                'Potato': 100,
                'High-Quality Potato': 1,
                'Special Potato': 1000,
              },
              stock: {
                'Barley': 10000,
                'High-Quality Barley': 10000,
                'Special Barley': 10000,
                'Potato': 10000,
                'High-Quality Potato': 10000,
                'Special Potato': 10000,
              },
            ),
          ),
        ),
      );
      final grain = mode.recipes['Beer']!.ingredients.firstWhere(
        (i) => i.options.contains('Potato'),
      );
      final before = app.documentSnapshot.toJson();
      final barley = mode.previewSubstituteAmounts(
        parentName: 'Beer',
        ingredient: grain,
        selection: 'Barley',
      );
      final potato = mode.previewSubstituteAmounts(
        parentName: 'Beer',
        ingredient: grain,
        selection: 'Potato',
      );
      expect(barley.name, 'Barley');
      expect(potato.name, 'High-Quality Potato');
      expect(potato.owned, 0);
      expect(potato.missing, lessThan(barley.missing));
      expect(app.documentSnapshot.toJson(), before);
      mode.selectIngredientGrade(
        parentName: 'Beer',
        ingredientName: grain.name,
        selectedName: 'Barley',
        grade: 'normal',
      );
      expect(
        mode
            .previewSubstituteAmounts(
              parentName: 'Beer',
              ingredient: grain,
              selection: 'Potato',
            )
            .name,
        'Potato',
      );
    },
  );

  test(
    'shopping excludes covered materials and follows inventory mode',
    () async {
      final app = controller(catalog, CraftMode.cooking, 'Beer', 1000);
      addTearDown(app.dispose);
      final mode = app.active;
      final grain = mode.recipes['Beer']!.ingredients.firstWhere(
        (i) => i.options.contains('Corn'),
      );
      mode.selectSubstitute(
        parentName: 'Beer',
        ingredient: grain,
        selection: 'Corn',
      );
      mode.commitInventory('Corn', '2400');
      mode.commitInventory('Sugar', '400');
      var groups = shoppingGroups(mode);
      expect(groups.containsKey('Market / gather'), isFalse);
      expect(groups['NPC']!.any((r) => r.name == 'Sugar'), isFalse);
      mode.setIgnoreOwnedIngredients(true);
      groups = shoppingGroups(mode);
      expect(groups['Market / gather']!.single.missing, 2000);
      expect(groups['NPC']!.firstWhere((r) => r.name == 'Sugar').missing, 400);
      expect(shoppingText(groups), contains('NPC\n'));
    },
  );
}

PlannerApplicationController controller(
  CatalogSnapshot catalog,
  CraftMode mode,
  String target,
  int want,
) {
  ModeState state(CraftMode m) => ModeState(
    target: target,
    want: want,
    ignoreIngredientInventory: false,
    bonusTarget: '',
    bonusWant: 1,
    market: MarketState(),
    inventory: {},
    appearance: AppearanceSettings.defaultsFor(m),
  );
  return PlannerApplicationController(
    catalog: catalog,
    initialState: PlannerState(
      applicationVersion: 'test',
      lastSuccessfulWriteUtc: DateTime.utc(2026, 10, 30),
      activeMode: mode,
      alchemy: state(CraftMode.alchemy),
      cooking: state(CraftMode.cooking),
      processing: state(CraftMode.processing),
      processingYields: const {},
      marketTax: MarketTax(),
      showDeleteTools: false,
    ),
    saveState: (state) async => state,
    saveDebounce: Duration.zero,
  );
}
