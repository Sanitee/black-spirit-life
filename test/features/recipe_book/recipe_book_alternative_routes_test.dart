import 'dart:io';

import 'package:bdo_craft_planner_flutter/app/state/planner_application_controller.dart';
import 'package:bdo_craft_planner_flutter/data/catalog/bundled_catalog_parser.dart';
import 'package:bdo_craft_planner_flutter/data/catalog/catalog_repository.dart';
import 'package:bdo_craft_planner_flutter/domain/catalog/temporarily_archived_items.dart';
import 'package:bdo_craft_planner_flutter/domain/models/catalog_models.dart';
import 'package:bdo_craft_planner_flutter/domain/models/craft_mode.dart';
import 'package:bdo_craft_planner_flutter/domain/planner/planner_models.dart'
    show PlanStep;
import 'package:bdo_craft_planner_flutter/domain/state/planner_state.dart';
import 'package:bdo_craft_planner_flutter/domain/state/state_copy.dart';
import 'package:bdo_craft_planner_flutter/features/planner/planner_contracts.dart';
import 'package:bdo_craft_planner_flutter/features/recipe_book/recipe_book_controller.dart';
import 'package:bdo_craft_planner_flutter/features/recipe_book/recipe_book_item_info.dart';
import 'package:bdo_craft_planner_flutter/features/recipe_book/recipe_book_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late CatalogSnapshot catalog;
  late PlannerApplicationController application;
  late RecipeBookController book;

  setUpAll(() {
    catalog = const BundledCatalogParser().parse(
      File('assets/data/app-data.json').readAsStringSync(),
    );
  });

  setUp(() {
    application = PlannerApplicationController(
      catalog: catalog,
      initialState: PlannerState(
        applicationVersion: 'recipe-alternative-routes-test',
        lastSuccessfulWriteUtc: DateTime.utc(2026, 9, 18),
        activeMode: CraftMode.alchemy,
        alchemy: _mode(CraftMode.alchemy, 'Clear Liquid Reagent'),
        cooking: _mode(CraftMode.cooking, 'Beer'),
        processing: _mode(CraftMode.processing, 'Wheat Flour'),
        processingYields: const {'defaultYield': 999, 'Simple Alchemy': 999},
        marketTax: MarketTax(),
        showDeleteTools: true,
      ),
      saveState: (state) async => state,
      saveDebounce: Duration.zero,
    );
    final alchemy = application.modes[CraftMode.alchemy]!;
    book = RecipeBookController(
      modeController: alchemy,
      catalogRepository: CatalogRepository(catalog),
      callingContext: RecipeBookCallingContext.planner,
      allowedTargets: alchemy.craftableNames,
    );
  });

  tearDown(() async {
    book.dispose();
    await application.dispose();
  });

  test('Alchemy ingredient search discovers both Caphras perfume recipes', () {
    book.setSearchByIngredient(true);
    book.setSearch('Caphras Essence');

    final entries = book.snapshot.entries;
    expect(
      entries.map((entry) => entry.name),
      unorderedEquals(['Perfume of Envy', 'Perfume of Tenacity']),
      reason: 'An unrelated Essence alias must not match Caphras Essence.',
    );
    for (final name in ['Perfume of Envy', 'Perfume of Tenacity']) {
      final entry = entries.singleWhere(
        (entry) => entry.name == name && entry.mode == CraftMode.processing,
      );
      expect(entry.recipe.method, 'Simple Alchemy');
      final source = book.controllerForMode(entry.mode!);
      expect(
        source
            .recipeFor(name)!
            .ingredients
            .map((ingredient) => ingredient.name),
        contains('Caphras Essence'),
      );
      expect(source.selectedRecipeVariantId(name), 'standard');
    }
    expect(
      entries.where(
        (entry) =>
            entry.name == 'Perfume of Tenacity' &&
            entry.mode == CraftMode.alchemy,
      ),
      isEmpty,
      reason: 'The residence formula does not use Caphras Essence.',
    );
    expect(application.activeMode.value, CraftMode.alchemy);

    final activation = book.activateInMode(
      'Perfume of Envy',
      CraftMode.processing,
    );
    expect(activation?.mode, CraftMode.processing);
    expect(activation?.variantId, 'standard');
    expect(application.activeMode.value, CraftMode.processing);
    expect(application.active.state.value.target, 'Perfume of Envy');
    expect(_step(application.active, 'Perfume of Envy').produced, 11);
  });

  test('Tenacity detail retains residence and both Simple Alchemy batches', () {
    final formulas = book
        .itemInfoFor('Perfume of Tenacity')!
        .acquisitionFormulas;
    expect(
      formulas.map((formula) => (formula.mode, formula.variantId)),
      unorderedEquals([
        (CraftMode.alchemy, null),
        (CraftMode.processing, 'standard'),
        (CraftMode.processing, 'standard-10x'),
      ]),
    );
    final residence = _formula(formulas, CraftMode.alchemy, null);
    final single = _formula(formulas, CraftMode.processing, 'standard');
    final batch = _formula(formulas, CraftMode.processing, 'standard-10x');
    expect(residence.method, 'Alchemy');
    expect(_quantities(residence.ingredients), {
      'Trace of Nature': 5,
      "Spirit's Leaf": 5,
      'Pure Powder Reagent': 5,
      'Oil of Regeneration': 6,
      "Rusalka's Coral": 30,
    });
    expect(single.method, 'Simple Alchemy');
    expect(_quantities(single.ingredients), {
      'Perfume of Deep Sea': 1,
      'Shining Powder': 3,
      'Caphras Essence': 10,
    });
    expect(single.outputMinimum, 1);
    expect(single.outputMaximum, 1);
    expect(batch.batchMultiplier, 10);
    expect(_quantities(batch.ingredients), {
      'Perfume of Deep Sea': 10,
      'Shining Powder': 30,
      'Caphras Essence': 100,
      "Ibellab's Essence": 1,
    });
    expect(batch.outputMinimum, 10);
    expect(batch.outputMaximum, 10);
  });

  test('formula activation plans exact batches and returns to residence', () {
    const name = 'Perfume of Tenacity';
    final formulas = book.itemInfoFor(name)!.acquisitionFormulas;
    final single = _formula(formulas, CraftMode.processing, 'standard');
    final batch = _formula(formulas, CraftMode.processing, 'standard-10x');
    final residence = _formula(formulas, CraftMode.alchemy, null);
    final processing = application.modes[CraftMode.processing]!;
    final alchemy = application.modes[CraftMode.alchemy]!;

    expect(book.canActivateFormula(single), isTrue);
    final singleActivation = book.activateFormula(single);
    expect(singleActivation?.variantId, 'standard');
    expect(book.lastRouteActivation, same(singleActivation));
    expect(application.activeMode.value, CraftMode.processing);
    expect(processing.selectedRecipeVariantId(name), 'standard');
    final singleStep = _step(processing, name);
    expect(singleStep.count, 11);
    expect(singleStep.produced, 11);
    expect(_needs(singleStep), {
      'Perfume of Deep Sea': 11,
      'Shining Powder': 33,
      'Caphras Essence': 110,
    });

    final batchActivation = book.activateFormula(batch);
    expect(batchActivation?.variantId, 'standard-10x');
    expect(book.lastRouteActivation, same(batchActivation));
    expect(processing.selectedRecipeVariantId(name), 'standard-10x');
    final batchStep = _step(processing, name);
    expect(batchStep.count, 2);
    expect(batchStep.produced, 20);
    expect(_needs(batchStep), {
      'Perfume of Deep Sea': 20,
      'Shining Powder': 60,
      'Caphras Essence': 200,
      "Ibellab's Essence": 2,
    });

    final residenceActivation = book.activateFormula(residence);
    expect(residenceActivation?.mode, CraftMode.alchemy);
    expect(book.lastRouteActivation, same(residenceActivation));
    expect(application.activeMode.value, CraftMode.alchemy);
    expect(alchemy.state.value.target, name);
    expect(alchemy.selectedRecipe(name)!.type, 'alchemy');
    final residenceStep = _step(alchemy, name);
    expect(residenceStep.count, 5);
    expect(residenceStep.produced, 12.5);
    expect(_needs(residenceStep), {
      'Trace of Nature': 25,
      "Spirit's Leaf": 25,
      'Pure Powder Reagent': 25,
      'Oil of Regeneration': 30,
      "Rusalka's Coral": 150,
    });
    expect(processing.selectedRecipeVariantId(name), 'standard-10x');
  });

  test('all 29 cross-mode outputs retain every complete source formula', () {
    final sources = <String, Map<CraftMode, Recipe>>{};
    for (final mode in CraftMode.values) {
      for (final recipe in catalog.forMode(mode).items.values) {
        if (!recipe.isCraftable) continue;
        sources.putIfAbsent(recipe.name, () => {})[mode] = recipe;
      }
    }
    final repeated = sources.entries.where((entry) => entry.value.length > 1);
    expect(repeated, hasLength(29));

    for (final entry in repeated) {
      final name = entry.key;
      book.setSearch(name);
      final results = book.snapshot.entries.where((item) => item.name == name);
      expect(
        results.map((item) => item.mode),
        unorderedEquals(entry.value.keys),
        reason: '$name must remain discoverable in each source category.',
      );
      final formulas = book.itemInfoFor(name)!.acquisitionFormulas;
      final expected = <(CraftMode, String?)>{};
      for (final source in entry.value.entries) {
        final variants = source.value.variants;
        if (variants.isEmpty) {
          expected.add((source.key, null));
        } else {
          expected.addAll(variants.map((variant) => (source.key, variant.id)));
        }
      }
      expect(
        formulas.map((formula) => (formula.mode, formula.variantId)),
        unorderedEquals(expected),
        reason: '$name must not collapse category, route, or batch identity.',
      );
      for (final formula in formulas) {
        final source = application.modes[formula.mode]!
            .recipeDefinition(name)!
            .resolveVariant(formula.variantId);
        expect(
          _ingredientRecords(formula.ingredients),
          _ingredientRecords(source.ingredients),
          reason: '$name / ${formula.mode} / ${formula.variantId}',
        );
        expect(formula.baseOutput, source.baseOutput);
        expect(formula.outputMinimum, source.outputMinimum);
        expect(formula.outputMaximum, source.outputMaximum);
        expect(book.canActivateFormula(formula), isTrue);
      }
    }
  });

  test('all production variants retain complete selectable formula identities', () {
    var productionRecipes = 0;
    var productionFormulas = 0;
    var referenceRecipes = 0;
    var referenceFormulas = 0;
    var browsableReferenceFormulas = 0;
    final repository = CatalogRepository(catalog);

    for (final mode in CraftMode.values) {
      final controller = application.modes[mode]!;
      bool archived(String name) => isTemporarilyArchivedItem(
        name,
        itemId:
            controller.recipes[name]?.marketId ??
            repository.bundledMarketId(name),
      );

      for (final recorded in catalog.forMode(mode).items.values) {
        if (recorded.variants.isEmpty) continue;
        final source = controller.recipeDefinition(recorded.name)!;
        final context = '${mode.key} / ${source.name}';
        if (!source.isCraftable) {
          referenceRecipes++;
          // Planner assembly intentionally strips unbrowsable reference routes.
          // Count raw catalog variants separately from curated visible formulas.
          referenceFormulas += recorded.variants.length;
          final browsable = recipeBookFormulas(source, mode: mode);
          browsableReferenceFormulas += browsable.length;
          for (final formula in browsable) {
            expect(book.canActivateFormula(formula), isFalse, reason: context);
          }
          for (final variant in recorded.variants) {
            final formula = RecipeBookFormula(
              outputName: source.name,
              mode: mode,
              type: variant.type,
              method: variant.method ?? '',
              baseOutput: variant.baseOutput,
              ingredients: variant.ingredients,
              variantId: variant.id,
            );
            expect(book.canActivateFormula(formula), isFalse, reason: context);
          }
          continue;
        }

        productionRecipes++;
        expect(archived(source.name), isFalse, reason: context);
        final formulas = book
            .itemInfoFor(source.name, mode: mode)!
            .acquisitionFormulas
            .where((formula) => formula.mode == mode)
            .toList();
        productionFormulas += formulas.length;
        expect(
          formulas.map(
            (formula) =>
                (formula.variantId, formula.routeId, formula.batchMultiplier),
          ),
          unorderedEquals(
            source.variants.map(
              (variant) =>
                  (variant.id, variant.routeId, variant.batchMultiplier),
            ),
          ),
          reason: '$context must preserve every route and batch identity.',
        );
        for (final variant in source.variants) {
          final formula = _formula(formulas, mode, variant.id);
          final variantContext = '$context / ${variant.id}';
          expect(formula.outputName, source.name, reason: variantContext);
          expect(formula.type, variant.type, reason: variantContext);
          expect(formula.method, variant.method, reason: variantContext);
          expect(formula.routeLabel, variant.label, reason: variantContext);
          expect(
            formula.baseOutput,
            variant.baseOutput,
            reason: variantContext,
          );
          expect(
            formula.outputMinimum,
            variant.outputMinimum,
            reason: variantContext,
          );
          expect(
            formula.outputMaximum,
            variant.outputMaximum,
            reason: variantContext,
          );
          // The current production catalog never requires an archived primary
          // ingredient. Archived substitute options must stay unavailable, while
          // all remaining options, ratios, quantities and row identities survive.
          expect(
            variant.ingredients.map((ingredient) => archived(ingredient.name)),
            everyElement(isFalse),
            reason: variantContext,
          );
          expect(_ingredientRecords(formula.ingredients), [
            for (final ingredient in variant.ingredients)
              [
                ingredient.name,
                ingredient.quantity,
                ingredient.options.where((name) => !archived(name)).toList(),
                ingredient.substituteGroup,
                {
                  for (final entry in ingredient.substituteRatios.entries)
                    if (!archived(entry.key)) entry.key: entry.value,
                },
              ],
          ], reason: variantContext);
          expect(
            book.canActivateFormula(formula),
            isTrue,
            reason: variantContext,
          );
        }
      }
    }
    expect(productionRecipes, 146);
    expect(productionFormulas, 344);
    expect(referenceRecipes, 10);
    expect(referenceFormulas, 27);
    expect(browsableReferenceFormulas, 8);
  });

  test('Processing category filters constrain cross-mode perfume search', () {
    final processing = application.modes[CraftMode.processing]!;
    final processingBook = RecipeBookController(
      modeController: processing,
      catalogRepository: CatalogRepository(catalog),
      callingContext: RecipeBookCallingContext.planner,
      allowedTargets: processing.craftableNames,
    );
    addTearDown(processingBook.dispose);
    processingBook.setSearch('Perfume');
    for (final group in [
      ProcessingRecipeGroup.metals,
      ProcessingRecipeGroup.crystals,
    ]) {
      processingBook.setGroup(group);
      expect(
        processingBook.snapshot.entries.where(
          (entry) => entry.mode == CraftMode.alchemy,
        ),
        isEmpty,
        reason: '${group.label} must not admit foreign Alchemy perfumes.',
      );
    }
    processingBook.setGroup(ProcessingRecipeGroup.all);
    expect(
      processingBook.snapshot.entries
          .where((entry) => entry.name == 'Perfume of Tenacity')
          .map((entry) => entry.mode),
      unorderedEquals([CraftMode.alchemy, CraftMode.processing]),
    );
  });

  test('cross-mode ingredient activation retains the searched substitute', () {
    book.setSearchByIngredient(true);
    book.setSearch('Special Wheat');
    expect(
      book.snapshot.entries.any(
        (entry) =>
            entry.name == 'Wheat Flour' && entry.mode == CraftMode.processing,
      ),
      isTrue,
    );

    final activation = book.activateInMode('Wheat Flour', CraftMode.processing);
    expect(activation?.mode, CraftMode.processing);
    final processing = application.modes[CraftMode.processing]!;
    final ingredient = processing
        .selectedRecipe('Wheat Flour')!
        .ingredients
        .single;
    expect(
      processing
          .state
          .value
          .substituteChoices['recipe:Wheat Flour:${ingredient.substituteGroup ?? ingredient.name}'],
      'Special Wheat',
    );
    expect(
      _step(processing, 'Wheat Flour').ingredients.single.name,
      'Special Wheat',
    );
    expect(
      application.modes[CraftMode.alchemy]!.state.value.substituteChoices,
      isEmpty,
    );
  });

  test(
    'method search includes a method recorded only on an alternate route',
    () {
      book.setSearch('Simple Alchemy');
      expect(
        book.snapshot.entries.any(
          (entry) =>
              entry.name == 'Perfume of Verdure' &&
              entry.mode == CraftMode.alchemy,
        ),
        isTrue,
      );
      final formulas = book
          .itemInfoFor('Perfume of Verdure')!
          .acquisitionFormulas;
      final simple = _formula(formulas, CraftMode.alchemy, 'simple-alchemy');
      expect(simple.method, 'Simple Alchemy');
      expect(book.activateFormula(simple)?.variantId, 'simple-alchemy');
      expect(
        application.active.selectedRecipe('Perfume of Verdure')!.type,
        'simple_alchemy',
      );
      expect(_step(application.active, 'Perfume of Verdure').produced, 11);
    },
  );

  test('hidden and deleted foreign routes cannot reappear or activate', () {
    final stale = _formula(
      book.itemInfoFor('Perfume of Tenacity')!.acquisitionFormulas,
      CraftMode.processing,
      'standard',
    );
    final processing = application.modes[CraftMode.processing]!;
    processing.updateState(
      (state) => state.copyWith(
        hiddenItems: const {'Perfume of Tenacity'},
        recipeEdits: const {'Perfume of Envy': null},
      ),
      immediate: true,
    );
    book.setSearch('Perfume');
    expect(
      book.snapshot.entries.where(
        (entry) =>
            entry.mode == CraftMode.processing &&
            const {
              'Perfume of Envy',
              'Perfume of Tenacity',
            }.contains(entry.name),
      ),
      isEmpty,
    );
    expect(
      book
          .itemInfoFor('Perfume of Tenacity')!
          .acquisitionFormulas
          .map((formula) => formula.mode),
      everyElement(CraftMode.alchemy),
    );
    expect(book.canActivateFormula(stale), isFalse);
    expect(book.activateFormula(stale), isNull);
    expect(
      book.activateInMode('Perfume of Envy', CraftMode.processing),
      isNull,
    );
    expect(application.activeMode.value, CraftMode.alchemy);
  });

  test(
    'reference formulas remain viewable without becoming planner targets',
    () {
      const name = 'Dawnbound Ekleta Necklace';
      final processing = catalog.processing.items[name]!;
      expect(processing.isManualConversion, isTrue);
      final formulas = recipeBookFormulas(
        processing,
        mode: CraftMode.processing,
      );
      expect(formulas, isNotEmpty);
      final originalTarget = application.active.state.value.target;
      for (final formula in formulas) {
        expect(book.canActivateFormula(formula), isFalse);
        expect(book.activateFormula(formula), isNull);
      }
      expect(application.activeMode.value, CraftMode.alchemy);
      expect(application.active.state.value.target, originalTarget);
    },
  );

  test('bonus search and activation stay within the allowed bonus pool', () {
    final alchemy = application.modes[CraftMode.alchemy]!;
    final bonusBook = RecipeBookController(
      modeController: alchemy,
      catalogRepository: CatalogRepository(catalog),
      callingContext: RecipeBookCallingContext.bonus,
      allowedTargets: const [
        'Clear Liquid Reagent',
        'Pure Powder Reagent',
        "Clown's Blood",
      ],
    );
    addTearDown(bonusBook.dispose);
    bonusBook.setSearchByIngredient(true);
    bonusBook.setSearch('Caphras Essence');
    expect(bonusBook.snapshot.entries, isEmpty);
    final foreign = _formula(
      book.itemInfoFor('Perfume of Tenacity')!.acquisitionFormulas,
      CraftMode.processing,
      'standard',
    );
    final outsidePool = _formula(
      book.itemInfoFor('Perfume of Tenacity')!.acquisitionFormulas,
      CraftMode.alchemy,
      null,
    );
    expect(bonusBook.canActivateFormula(foreign), isFalse);
    expect(bonusBook.activateFormula(foreign), isNull);
    expect(bonusBook.canActivateFormula(outsidePool), isFalse);
    expect(bonusBook.activateFormula(outsidePool), isNull);
    expect(
      bonusBook.activateInMode('Perfume of Tenacity', CraftMode.processing),
      isNull,
    );
    expect(application.activeMode.value, CraftMode.alchemy);
    expect(alchemy.state.value.bonusTarget, 'Clear Liquid Reagent');
  });
}

ModeState _mode(CraftMode mode, String target) => ModeState(
  target: target,
  want: 11,
  bonusTarget: target,
  market: MarketState(),
  appearance: AppearanceSettings.defaultsFor(mode),
);

RecipeBookFormula _formula(
  List<RecipeBookFormula> formulas,
  CraftMode mode,
  String? variantId,
) => formulas.singleWhere(
  (formula) => formula.mode == mode && formula.variantId == variantId,
);

PlanStep _step(ModeFeatureController mode, String name) =>
    mode.plan.value.steps.singleWhere((step) => step.name == name);

Map<String, double> _quantities(List<Ingredient> ingredients) => {
  for (final ingredient in ingredients) ingredient.name: ingredient.quantity,
};

Map<String, double> _needs(PlanStep step) => {
  for (final ingredient in step.ingredients) ingredient.name: ingredient.need,
};

List<Object?> _ingredientRecords(List<Ingredient> ingredients) => [
  for (final ingredient in ingredients)
    [
      ingredient.name,
      ingredient.quantity,
      ingredient.options,
      ingredient.substituteGroup,
      ingredient.substituteRatios,
    ],
];
