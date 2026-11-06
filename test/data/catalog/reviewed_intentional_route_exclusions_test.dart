import 'dart:convert';
import 'dart:io';
import 'package:bdo_craft_planner_flutter/app/planning/planner_assembly.dart';
import 'package:bdo_craft_planner_flutter/data/catalog/bundled_catalog_parser.dart';
import 'package:bdo_craft_planner_flutter/domain/models/catalog_models.dart';
import 'package:bdo_craft_planner_flutter/domain/models/craft_mode.dart';
import 'package:bdo_craft_planner_flutter/domain/opportunities/opportunity_calculator.dart';
import 'package:bdo_craft_planner_flutter/domain/planner/planner_engine.dart';
import 'package:bdo_craft_planner_flutter/domain/planner/planner_models.dart'
    as planning;
import 'package:bdo_craft_planner_flutter/domain/state/planner_state.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final review =
      jsonDecode(
            File(
              'docs/reviewed-intentional-route-exclusions.json',
            ).readAsStringSync(),
          )
          as Map<String, dynamic>;
  final groups = (review['groups'] as List).cast<Map<String, dynamic>>();
  late CatalogSnapshot catalog;
  late Map<String, Recipe> recipes;
  late planning.PlannerRules rules;
  setUpAll(() {
    catalog = const BundledCatalogParser().parse(
      File('assets/data/app-data.json').readAsStringSync(),
    );
    recipes = const PlannerAssembly().assembleRecipes(
      catalog: catalog.processing,
      state: ModeState(
        target: '',
        bonusTarget: '',
        market: MarketState(),
        appearance: AppearanceSettings.defaultsFor(CraftMode.processing),
      ),
      supportingData: catalog.supportingData,
      sharedMetadata: catalog.alchemy.metadata,
      mode: CraftMode.processing,
      processingRecipes: catalog.processing.items,
    );
    rules = const PlannerAssembly().plannerRules(catalog.supportingData);
  });
  test(
    'exclusion fixtures cover696gear candidates,not the Alluvial Gold exception',
    () {
      expect(groups, hasLength(21));
      expect(
        groups.fold<int>(0, (n, g) => n + (g['cases'] as List).length),
        696,
      );
      expect(
        (review['exceptions'] as List)
            .cast<Map<String, dynamic>>()
            .single['key'],
        'native_processing_route_not_represented:811',
      );
    },
  );
  for (final group in groups) {
    final name = group['name'] as String;
    test(
      '$name does not buy or consume excluded equipment even when owned',
      () {
        final excluded = {
          for (final row
              in (group['cases'] as List).cast<Map<String, dynamic>>())
            for (final input
                in (row['inputs'] as List).cast<Map<String, dynamic>>())
              input['name'] as String,
        };
        final recipe = recipes[name]!;
        expect(recipe.marketId ?? rules.marketIds[name], '${group['id']}');
        expect(recipe.isCraftable, isTrue);
        final marketNames = const OpportunityCalculator().marketItemNames(
          recipe: recipe,
          recipes: recipes,
          rules: rules,
        );
        expect(marketNames.intersection(excluded), isEmpty);
        final result = const PlannerEngine().buildPlan(
          mode: CraftMode.processing,
          recipes: recipes,
          rules: rules,
          state: planning.PlannerState(
            target: name,
            want: 100,
            inventory: {for (final item in excluded) item: 10000},
            ignoreIngredientInventory: false,
          ),
        );
        expect(result.steps.any((s) => s.name == name), isTrue);
        final plannedInputs = {
          for (final step in result.steps)
            for (final input in step.ingredients) input.name,
        };
        expect(plannedInputs.intersection(excluded), isEmpty);
      },
    );
  }
}
