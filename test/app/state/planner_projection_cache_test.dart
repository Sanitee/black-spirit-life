import 'dart:io';

import 'package:bdo_craft_planner_flutter/app/state/planner_application_controller.dart';
import 'package:bdo_craft_planner_flutter/data/catalog/bundled_catalog_parser.dart';
import 'package:bdo_craft_planner_flutter/domain/models/craft_mode.dart';
import 'package:bdo_craft_planner_flutter/domain/state/planner_state.dart';
import 'package:bdo_craft_planner_flutter/domain/state/state_copy.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../features/recipe_book/recipe_book_test_support.dart';

void main() {
  test(
    'presentation and receipt timestamps preserve the current plan',
    () async {
      final environment = buildRecipeBookTestEnvironment();
      addTearDown(environment.dispose);
      final mode = environment.application.active;
      final plan = mode.plan.value;
      var stateNotifications = 0;
      var planNotifications = 0;
      mode.state.addListener(() => stateNotifications++);
      mode.plan.addListener(() => planNotifications++);
      mode.toggleFavorite(mode.state.value.target);
      mode.navigate('inventory');
      mode.updateState(
        (s) => s.copyWith(
          bookFavoritesOnly: true,
          market: s.market.copyWith(fetchedAt: 5000, search: 'new filter'),
        ),
      );
      expect(mode.plan.value, same(plan));
      expect(planNotifications, 0);
      expect(stateNotifications, 3);
      await environment.application.flush();
      expect(
        environment.application.documentSnapshot
            .forMode(mode.mode)
            .market
            .fetchedAt,
        5000,
      );
      mode.recalculate();
      expect(
        mode.plan.value,
        isNot(same(plan)),
        reason: 'Explicit recalculate remains an explicit computation.',
      );
      expect(mode.plan.value.toJson(), plan.toJson());
    },
  );

  final edits = <String, ModeState Function(ModeState)>{
    'target': (s) => s.copyWith(target: 'Pure Powder Reagent'),
    'quantity': (s) => s.copyWith(want: s.want + 1),
    'owned inventory': (s) => s.copyWith(inventory: {'Wild Grass': 20}),
    'completed step': (s) => s.copyWith(completedSteps: {s.target}),
    'target inventory rule': (s) =>
        s.copyWith(ignoreTargetInventory: !s.ignoreTargetInventory),
    'ingredient inventory rule': (s) =>
        s.copyWith(ignoreIngredientInventory: !s.ignoreIngredientInventory),
    'alchemy mastery': (s) =>
        s.copyWith(alchemyMastery: s.alchemyMastery + 100),
    'cooking mastery': (s) =>
        s.copyWith(cookingMastery: s.cookingMastery + 100),
    'processing mastery': (s) =>
        s.copyWith(processingMastery: s.processingMastery + 100),
    'mass processing': (s) =>
        s.copyWith(useMassProcessing: !s.useMassProcessing),
    'substitutes': (s) =>
        s.copyWith(substituteChoices: {'Wild Plants': 'Weed'}),
    'ingredient grades': (s) =>
        s.copyWith(ingredientGrades: {'Sunflower': 'high'}),
    'recipe variant': (s) => s.copyWith(
      recipeVariantChoices: {'Clear Liquid Reagent': 'trace-route'},
    ),
    'market price': (s) =>
        s.copyWith(market: s.market.copyWith(prices: {'Wild Grass': 5000})),
    'market stock': (s) =>
        s.copyWith(market: s.market.copyWith(stock: {'Wild Grass': 20})),
    'recipe metadata': (s) => s.copyWith(
      ingredientMeta: {'Sunflower': IngredientMetadata(npcPrice: 300)},
    ),
    'recipe edit': (s) =>
        s.copyWith(recipeEdits: {'Pure Powder Reagent': null}),
    'hidden item': (s) => s.copyWith(hiddenItems: {'Pure Powder Reagent'}),
  };
  for (final entry in edits.entries) {
    test(
      'plan invalidation includes ${entry.key} and matches the engine',
      () async {
        final environment = buildRecipeBookTestEnvironment(
          includeRecipeVariants: true,
        );
        addTearDown(environment.dispose);
        final mode = environment.application.active;
        final before = mode.plan.value;
        mode.updateState(entry.value);
        expect(mode.plan.value, isNot(same(before)));
        expect(mode.plan.value.toJson(), _freshPlan(mode));
      },
    );
  }

  test(
    'completed reference plan is reused on expand and unrelated edits',
    () async {
      final environment = buildRecipeBookTestEnvironment(
        includeUsedInVariantFixture: true,
      );
      addTearDown(environment.dispose);
      final mode = environment.application.active;
      mode.selectTarget('Elixir of Life');
      mode.toggleCompleted('Clear Liquid Reagent');
      final full = mode.completedPlan;
      expect(full.toJson(), _freshPlan(mode, ignoreCompleted: true));
      mode.toggleIngredients('Elixir of Life');
      mode.toggleFavorite('Elixir of Life');
      expect(mode.completedPlan, same(full));
      mode.toggleCompleted('Elixir of Life');
      expect(
        mode.completedPlan,
        same(full),
        reason: 'Completion mask does not change the uncompleted reference.',
      );
      mode.updateState((s) => s.copyWith(want: s.want + 5));
      expect(mode.completedPlan, isNot(same(full)));
      expect(
        mode.completedPlan.toJson(),
        _freshPlan(mode, ignoreCompleted: true),
      );
      mode.resetCompleted();
      expect(mode.completedPlan, same(mode.plan.value));
    },
  );

  test(
    'production Balenos reference stays identical to a fresh assembly',
    () async {
      final app = await _productionController('Balenos Meal');
      addTearDown(app.dispose);
      final mode = app.active;
      expect(mode.plan.value.steps.length, greaterThan(3));
      mode.toggleCompleted(mode.plan.value.steps.first.name);
      final before = mode.completedPlan;
      expect(before.toJson(), _freshPlan(mode, ignoreCompleted: true));
      mode.updateState(
        (s) => s.copyWith(
          market: s.market.copyWith(
            prices: {for (final name in mode.recipes.keys) name: 1000},
            stock: {for (final name in mode.recipes.keys) name: 100000},
          ),
        ),
      );
      final cachedMarketPlan = mode.plan.value;
      final cachedMarketReference = mode.completedPlan;
      mode.updateState(
        (s) => s.copyWith(market: s.market.copyWith(fetchedAt: 9000)),
      );
      expect(mode.plan.value, same(cachedMarketPlan));
      expect(mode.completedPlan, same(cachedMarketReference));
      expect(
        mode.completedPlan.toJson(),
        _freshPlan(mode, ignoreCompleted: true),
      );
    },
  );

  test(
    'processing acquisition choice invalidates both production projections',
    () async {
      final app = await _productionController('Oatmeal');
      addTearDown(app.dispose);
      final mode = app.active;
      mode.toggleCompleted('Oatmeal');
      final before = mode.plan.value;
      final fullBefore = mode.completedPlan;
      expect(
        mode.selectProcessingAcquisition('Cooking Honey', process: true),
        isTrue,
      );
      expect(mode.plan.value, isNot(same(before)));
      expect(mode.completedPlan, isNot(same(fullBefore)));
      expect(mode.plan.value.toJson(), _freshPlan(mode));
      expect(
        mode.completedPlan.toJson(),
        _freshPlan(mode, ignoreCompleted: true),
      );
      expect(
        mode.selectProcessingAcquisition('Cooking Honey', process: false),
        isTrue,
      );
      expect(
        mode.completedPlan.toJson(),
        _freshPlan(mode, ignoreCompleted: true),
      );
    },
  );
}

Future<PlannerApplicationController> _productionController(
  String target,
) async {
  final seed = buildRecipeBookTestEnvironment(activeMode: CraftMode.cooking);
  final document = seed.application.documentSnapshot;
  await seed.dispose();
  return PlannerApplicationController(
    catalog: const BundledCatalogParser().parse(
      await File('assets/data/app-data.json').readAsString(),
    ),
    initialState: document.copyWith(
      cooking: document.cooking.copyWith(target: target, want: 1000),
    ),
    saveState: (state) async => state,
  );
}

Map<String, Object?> _freshPlan(
  ModeFeatureController mode, {
  bool ignoreCompleted = false,
}) => mode.owner.assembly
    .build(
      catalog: mode.owner.catalog,
      mode: mode.mode,
      state: ignoreCompleted
          ? mode.state.value.copyWith(completedSteps: const {})
          : mode.state.value,
    )
    .toJson();
