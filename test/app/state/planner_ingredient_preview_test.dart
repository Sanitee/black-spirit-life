import 'package:bdo_craft_planner_flutter/app/state/planner_application_controller.dart';
import 'package:bdo_craft_planner_flutter/domain/models/catalog_models.dart';
import 'package:bdo_craft_planner_flutter/domain/models/craft_mode.dart';
import 'package:bdo_craft_planner_flutter/domain/state/planner_state.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final useOwned in <bool>[false, true]) {
    test(
      'row preview preserves the batch substitute chosen by '
      '${useOwned ? 'ownership' : 'market stock'} without saving a choice',
      () async {
        final formula = Ingredient(
          name: 'Base',
          quantity: 2,
          options: const <String>['Base', 'Alternate'],
          substituteGroup: 'materials',
          substituteRatios: const <String, double>{'Alternate': 2},
        );
        var saves = 0;
        final controller = _controller(
          formula: formula,
          inventory: useOwned
              ? const <String, double>{'Base': 2, 'Alternate': 40}
              : const <String, double>{},
          ignoreInventory: !useOwned,
          market: useOwned
              ? MarketState()
              : MarketState(
                  prices: const <String, double>{'Base': 1, 'Alternate': 2},
                  stock: const <String, double>{'Base': 2, 'Alternate': 100},
                ),
          onSave: () => saves += 1,
        );
        addTearDown(controller.dispose);
        final mode = controller.active;
        final stateBefore = mode.state.value;
        final documentBefore = controller.documentSnapshot;
        final planBefore = mode.plan.value;
        final row = planBefore.steps.single.ingredients.single;
        expect(row.name, 'Alternate');
        expect(row.need, 40);
        expect(row.missing, useOwned ? 0 : 40);

        final automatic = mode.previewIngredientSelection(
          parentName: 'Target',
          ingredient: formula,
        );
        expect(automatic.name, 'Base');
        expect(automatic.need, 2);

        final pinned = mode.previewIngredientSelection(
          parentName: 'Target',
          ingredient: formula,
          selectedIngredient: row,
        );
        expect(pinned.name, row.name);
        expect(pinned.baseName, row.baseName);
        expect(pinned.grade, row.grade);
        expect(pinned.need, 4);
        expect(mode.state.value, same(stateBefore));
        expect(controller.documentSnapshot, same(documentBefore));
        expect(mode.plan.value, same(planBefore));
        expect(mode.state.value.substituteChoices, isEmpty);
        await controller.flush();
        expect(saves, 0);
      },
    );
  }

  test('row preview preserves one-attempt quality rounding', () {
    final formula = _ingredient('Sunrise Herb', 2);
    final controller = _controller(
      formula: formula,
      grades: const <String, String>{'recipe:Target:Sunrise Herb': 'special'},
    );
    addTearDown(controller.dispose);
    final mode = controller.active;
    final stateBefore = mode.state.value;
    final row = mode.plan.value.steps.single.ingredients.single;
    expect(row.name, 'Special Sunrise Herb');
    expect(row.grade, 'special');
    expect(row.need, 4);

    final preview = mode.previewIngredientSelection(
      parentName: 'Target',
      ingredient: formula,
      selectedIngredient: row,
    );
    expect(preview.name, row.name);
    expect(preview.grade, row.grade);
    expect(preview.need, 1);
    expect(mode.state.value, same(stateBefore));
  });

  test('10x processing formula and mass scheduling are not scaled twice', () {
    final normalFormula = _ingredient('Sunrise Herb', 2);
    final batchFormula = _ingredient('Sunrise Herb', 20);
    final controller = _controller(
      mode: CraftMode.processing,
      formula: normalFormula,
      want: 100,
      massProcessing: true,
      variants: <RecipeVariant>[
        _variant('normal', 1, normalFormula),
        _variant('tenfold', 10, batchFormula),
      ],
      variantChoices: const <String, String>{'Target': 'tenfold'},
      grades: const <String, String>{'recipe:Target:Sunrise Herb': 'special'},
    );
    addTearDown(controller.dispose);
    final mode = controller.active;
    final stateBefore = mode.state.value;
    final step = mode.plan.value.steps.single;
    final row = step.ingredients.single;
    expect(step.count, 10);
    expect(step.batchSize, greaterThan(1));
    expect(row.name, 'Sunrise Herb');
    expect(row.grade, 'normal');
    expect(row.need, 200);

    final preview = mode.previewIngredientSelection(
      parentName: 'Target',
      ingredient: mode.selectedRecipe('Target')!.ingredients.single,
      selectedIngredient: row,
    );
    expect(preview.name, row.name);
    expect(preview.grade, 'normal');
    expect(preview.need, 20);
    expect(mode.state.value, same(stateBefore));
    expect(mode.state.value.ingredientGrades.values.single, 'special');
    expect(mode.state.value.recipeVariantChoices['Target'], 'tenfold');
  });
}

PlannerApplicationController _controller({
  required Ingredient formula,
  CraftMode mode = CraftMode.alchemy,
  int want = 10,
  bool ignoreInventory = true,
  bool massProcessing = false,
  Map<String, double> inventory = const <String, double>{},
  Map<String, String> grades = const <String, String>{},
  Map<String, String> variantChoices = const <String, String>{},
  List<RecipeVariant> variants = const <RecipeVariant>[],
  MarketState? market,
  void Function()? onSave,
}) {
  ModeState state(CraftMode craftMode) => ModeState(
    target: 'Target',
    bonusTarget: 'Target',
    want: want,
    inventory: inventory,
    ingredientGrades: grades,
    recipeVariantChoices: variantChoices,
    ignoreIngredientInventory: ignoreInventory,
    useMassProcessing: massProcessing,
    processingMastery: 1000,
    market: market ?? MarketState(),
    appearance: AppearanceSettings.defaultsFor(craftMode),
  );
  ModeCatalog catalog(CraftMode craftMode) => ModeCatalog(
    mode: craftMode,
    items: <String, Recipe>{
      'Target': _recipe('Target', craftMode.key, <Ingredient>[
        formula,
      ], variants: variants),
      for (final name in <String>[
        'Base',
        'Alternate',
        'Sunrise Herb',
        'Special Sunrise Herb',
      ])
        name: _recipe(name, 'gathered', const <Ingredient>[]),
    },
    iconDataUris: const <String, String>{},
    defaults: const <String, Object?>{},
    metadata: const <String, Object?>{},
    searchAliases: const <String, String>{},
  );
  return PlannerApplicationController(
    catalog: CatalogSnapshot(
      sourceSha256: 'isolated-ingredient-preview-test',
      sourceByteCount: 1,
      alchemy: catalog(CraftMode.alchemy),
      cooking: catalog(CraftMode.cooking),
      processing: catalog(CraftMode.processing),
      supportingData: const <String, Object?>{
        'qualityIngredients': <String>['Sunrise Herb'],
      },
      collisions: const [],
    ),
    initialState: PlannerState(
      applicationVersion: 'test',
      lastSuccessfulWriteUtc: DateTime.utc(2026),
      activeMode: mode,
      alchemy: state(CraftMode.alchemy),
      cooking: state(CraftMode.cooking),
      processing: state(CraftMode.processing),
      processingYields: const <String, double>{},
      marketTax: MarketTax(),
    ),
    saveState: (state) async {
      onSave?.call();
      return state;
    },
  );
}

Ingredient _ingredient(String name, double quantity) => Ingredient(
  name: name,
  quantity: quantity,
  options: const <String>[],
  substituteGroup: null,
  substituteRatios: const <String, double>{},
);

RecipeVariant _variant(String id, int multiplier, Ingredient ingredient) =>
    RecipeVariant(
      id: id,
      label: id,
      type: 'processing',
      baseOutput: multiplier.toDouble(),
      method: 'Grinding',
      ingredients: <Ingredient>[ingredient],
      outputMinimum: multiplier.toDouble(),
      outputMaximum: multiplier.toDouble(),
      batchMultiplier: multiplier,
    );

Recipe _recipe(
  String name,
  String type,
  List<Ingredient> ingredients, {
  List<RecipeVariant> variants = const <RecipeVariant>[],
}) => Recipe(
  name: name,
  type: type,
  baseOutput: 1,
  group: null,
  method: null,
  ingredients: ingredients,
  marketId: name,
  sourceNote: null,
  vendor: null,
  location: null,
  npcPrice: 0,
  qualityBase: null,
  qualityGrade: null,
  outputMinimum: 1,
  outputMaximum: 1,
  variants: variants,
  defaultVariantId: variants.firstOrNull?.id,
);
