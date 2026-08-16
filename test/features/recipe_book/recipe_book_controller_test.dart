import 'dart:async';
import 'dart:io';

import 'package:bdo_craft_planner_flutter/app/state/planner_application_controller.dart';
import 'package:bdo_craft_planner_flutter/data/catalog/bundled_catalog_parser.dart';
import 'package:bdo_craft_planner_flutter/data/catalog/catalog_repository.dart';
import 'package:bdo_craft_planner_flutter/data/persistence/planner_state_repository.dart';
import 'package:bdo_craft_planner_flutter/domain/models/catalog_models.dart';
import 'package:bdo_craft_planner_flutter/domain/models/craft_mode.dart';
import 'package:bdo_craft_planner_flutter/domain/state/planner_state.dart';
import 'package:bdo_craft_planner_flutter/domain/state/state_copy.dart';
import 'package:bdo_craft_planner_flutter/features/planner/planner_contracts.dart';
import 'package:bdo_craft_planner_flutter/features/recipe_book/recipe_book.dart';
import 'package:flutter_test/flutter_test.dart';

import 'recipe_book_test_support.dart';

void main() {
  test(
    'Processing Elixir of Seal acquisition uses its real Alchemy recipe',
    () {
      final catalog = const BundledCatalogParser().parse(
        File('assets/data/app-data.json').readAsStringSync(),
      );
      final application = PlannerApplicationController(
        catalog: catalog,
        initialState: PlannerState(
          applicationVersion: 'acquisition-resolution-test',
          lastSuccessfulWriteUtc: DateTime.utc(2026, 7, 24),
          activeMode: CraftMode.processing,
          alchemy: _productionMode(
            CraftMode.alchemy,
            target: 'Clear Liquid Reagent',
          ),
          cooking: _productionMode(CraftMode.cooking, target: 'Beer'),
          processing: _productionMode(
            CraftMode.processing,
            target: 'Agile Seal Elixir',
          ),
          processingYields: const <String, double>{'defaultYield': 2.5},
          marketTax: MarketTax(),
          showDeleteTools: true,
        ),
        saveState: (state) async => state,
        saveDebounce: Duration.zero,
      );
      final repository = CatalogRepository(catalog);
      final mode = application.modes[CraftMode.processing]!;
      final book = RecipeBookController(
        modeController: mode,
        catalogRepository: repository,
        callingContext: RecipeBookCallingContext.planner,
        allowedTargets: mode.craftableNames,
      );
      addTearDown(book.dispose);
      addTearDown(application.dispose);

      final info = book.itemInfoFor('Elixir of Seal');

      expect(info?.howToObtain, hasLength(1));
      expect(
        info?.howToObtain.single,
        'Alchemy: 3 Dwarf Mushroom + 1 Birch Sap + '
        '4 Wolf Blood (or substitute) + 5 Purified Water.',
      );
      expect(info?.howToObtain.join(' '), isNot(contains('Gathering')));
    },
  );

  test('bundled vendor routes appear instead of an unknown leaf source', () {
    final catalog = const BundledCatalogParser().parse(
      File('assets/data/app-data.json').readAsStringSync(),
    );
    final application = PlannerApplicationController(
      catalog: catalog,
      initialState: PlannerState(
        applicationVersion: 'vendor-acquisition-resolution-test',
        lastSuccessfulWriteUtc: DateTime.utc(2026, 7, 24),
        activeMode: CraftMode.cooking,
        alchemy: _productionMode(
          CraftMode.alchemy,
          target: 'Clear Liquid Reagent',
        ),
        cooking: _productionMode(CraftMode.cooking, target: 'Beer'),
        processing: _productionMode(
          CraftMode.processing,
          target: 'Wheat Flour',
        ),
        processingYields: const <String, double>{'defaultYield': 2.5},
        marketTax: MarketTax(),
        showDeleteTools: true,
      ),
      saveState: (state) async => state,
      saveDebounce: Duration.zero,
    );
    final repository = CatalogRepository(catalog);
    final mode = application.modes[CraftMode.cooking]!;
    final book = RecipeBookController(
      modeController: mode,
      catalogRepository: repository,
      callingContext: RecipeBookCallingContext.planner,
      allowedTargets: mode.craftableNames,
    );
    addTearDown(book.dispose);
    addTearDown(application.dispose);

    final info = book.itemInfoFor('Strawberry');

    expect(info?.howToObtain, contains('Buy from Milano Belucci in Calpheon.'));
    expect(info?.howToObtain.join(' '), isNot(contains('Gathering')));
  });

  test('Used For includes consumers from the other workstation catalogs', () {
    final environment = buildRecipeBookTestEnvironment(
      activeMode: CraftMode.processing,
      showDeleteTools: true,
    );
    final mode = environment.application.modes[CraftMode.processing]!;
    final book = RecipeBookController(
      modeController: mode,
      catalogRepository: environment.catalogRepository,
      callingContext: RecipeBookCallingContext.planner,
      allowedTargets: mode.craftableNames,
    );
    addTearDown(book.dispose);
    addTearDown(environment.dispose);

    final info = book.itemInfoFor('Trace of Earth');
    expect(
      info?.craftUses.map((use) => use.output),
      contains('Pure Powder Reagent'),
    );
  });

  test('Used In activation selects the exact substitute and quality path', () {
    final environment = buildRecipeBookTestEnvironment(
      includeRecipeVariants: true,
    );
    final mode = environment.application.modes[CraftMode.alchemy]!;
    mode.updateState(
      (state) => state.copyWith(
        target: 'Pure Powder Reagent',
        substituteChoices: const <String, String>{
          'recipe:Clear Liquid Reagent:Wild Plants': 'Wild Grass',
        },
        ingredientGrades: const <String, String>{
          'recipe:Clear Liquid Reagent:Sunflower': 'normal',
        },
      ),
      immediate: true,
    );
    final book = RecipeBookController(
      modeController: mode,
      catalogRepository: environment.catalogRepository,
      callingContext: RecipeBookCallingContext.planner,
      allowedTargets: mode.craftableNames,
    );
    addTearDown(book.dispose);
    addTearDown(environment.dispose);

    final weedUse = book
        .usedInFor('Weed')
        .entries
        .singleWhere((entry) => entry.name == 'Clear Liquid Reagent');
    final weedActivation = book.activateUsedIn(weedUse);

    expect(weedActivation?.exactName, 'Clear Liquid Reagent');
    expect(mode.state.value.target, 'Clear Liquid Reagent');
    expect(
      mode.state.value.recipeVariantChoices['Clear Liquid Reagent'],
      'wild-plants',
    );
    expect(
      mode
          .state
          .value
          .substituteChoices['recipe:Clear Liquid Reagent:Wild Plants'],
      'Weed',
    );

    final specialUse = book
        .usedInFor('Special Sunflower')
        .entries
        .singleWhere((entry) => entry.name == 'Clear Liquid Reagent');
    final specialActivation = book.activateUsedIn(specialUse);

    expect(specialActivation?.exactName, 'Clear Liquid Reagent');
    expect(
      mode
          .state
          .value
          .ingredientGrades['recipe:Clear Liquid Reagent:Sunflower'],
      'special',
    );
  });

  test(
    'Show Hidden exposes Used In consumers hidden in another workstation',
    () {
      final environment = buildRecipeBookTestEnvironment(
        activeMode: CraftMode.alchemy,
        showDeleteTools: true,
      );
      final processing = environment.application.modes[CraftMode.processing]!;
      processing.updateState(
        (state) => state.copyWith(
          recipeEdits: <String, RecipeState?>{
            ...state.recipeEdits,
            'Black Stone Batch 01': null,
          },
          hiddenItems: <String>{...state.hiddenItems, 'Black Stone Batch 01'},
        ),
        immediate: true,
      );
      final alchemy = environment.application.modes[CraftMode.alchemy]!;
      final book = RecipeBookController(
        modeController: alchemy,
        catalogRepository: environment.catalogRepository,
        callingContext: RecipeBookCallingContext.planner,
        allowedTargets: alchemy.craftableNames,
      );
      addTearDown(book.dispose);
      addTearDown(environment.dispose);

      expect(book.hiddenItemCount, 0);
      expect(book.totalHiddenItemCount, 1);
      expect(book.canShowHidden, isTrue);
      expect(
        book
            .usedInFor('Raw Material 01')
            .entries
            .where((entry) => entry.name == 'Black Stone Batch 01'),
        isEmpty,
      );

      book.setShowHidden(true);

      final hiddenUse = book
          .usedInFor('Raw Material 01')
          .entries
          .singleWhere((entry) => entry.name == 'Black Stone Batch 01');
      expect(hiddenUse.mode, CraftMode.processing);
      expect(hiddenUse.hidden, isTrue);
    },
  );

  test('ingredient-only curated materials can show item info', () async {
    final environment = buildRecipeBookTestEnvironment(
      activeMode: CraftMode.processing,
      showDeleteTools: true,
    );
    final mode = environment.application.modes[CraftMode.processing]!;
    final book = RecipeBookController(
      modeController: mode,
      catalogRepository: environment.catalogRepository,
      callingContext: RecipeBookCallingContext.planner,
      allowedTargets: mode.craftableNames,
    );
    addTearDown(book.dispose);
    addTearDown(environment.dispose);

    expect(book.recipeFor('Magical Lightstone Crystal'), isNull);
    expect(
      book.itemInfoFor('Magical Lightstone Crystal')?.howToObtain.single,
      contains('Dalishain'),
    );
  });

  test('uncatalogued ingredients get compact consumer recipe info', () async {
    final environment = buildRecipeBookTestEnvironment(
      activeMode: CraftMode.processing,
      showDeleteTools: true,
    );
    final mode = environment.application.modes[CraftMode.processing]!;
    mode.updateState(
      (state) => state.copyWith(
        recipeEdits: <String, RecipeState?>{
          ...state.recipeEdits,
          'Black Stone Batch 01': RecipeState(
            type: 'processing',
            baseOutput: 1,
            group: 'Processing - Grinding',
            method: 'Grinding',
            ingredients: <IngredientState>[
              IngredientState(
                name: 'External Material',
                quantity: 2,
                options: const <String>[],
                substituteGroup: null,
                substituteRatios: const <String, double>{},
              ),
            ],
            marketId: null,
            sourceNote: null,
            vendor: null,
            location: null,
            npcPrice: 0,
            qualityBase: null,
            qualityGrade: null,
            outputMinimum: null,
            outputMaximum: null,
          ),
        },
      ),
      immediate: true,
    );
    final book = RecipeBookController(
      modeController: mode,
      catalogRepository: environment.catalogRepository,
      callingContext: RecipeBookCallingContext.planner,
      allowedTargets: mode.craftableNames,
    );
    addTearDown(book.dispose);
    addTearDown(environment.dispose);

    final info = book.itemInfoFor('External Material');
    expect(info, isNotNull);
    expect(info?.summary, isEmpty);
    expect(info?.craftUses.single.output, 'Black Stone Batch 01');
    expect(
      info?.craftUses.single.recipes.single,
      'Grinding: 2 External Material.',
    );
  });

  test(
    'reference-only custom conversions stay out of targets and Used For',
    () {
      final environment = buildRecipeBookTestEnvironment(
        activeMode: CraftMode.processing,
        showDeleteTools: true,
      );
      final mode = environment.application.modes[CraftMode.processing]!;
      mode.updateState(
        (state) => state.copyWith(
          recipeEdits: <String, RecipeState?>{
            ...state.recipeEdits,
            'Manual Recovery Output': RecipeState(
              type: 'processing',
              role: RecipeRole.manualConversion,
              baseOutput: 1,
              group: 'Reference',
              method: 'Heating',
              ingredients: <IngredientState>[
                IngredientState(name: 'Reference Input', quantity: 1),
              ],
            ),
          },
        ),
        immediate: true,
      );
      final book = RecipeBookController(
        modeController: mode,
        catalogRepository: environment.catalogRepository,
        callingContext: RecipeBookCallingContext.planner,
        allowedTargets: mode.craftableNames,
      );
      addTearDown(book.dispose);
      addTearDown(environment.dispose);

      expect(
        book.snapshot.entries.map((entry) => entry.name),
        isNot(contains('Manual Recovery Output')),
      );
      expect(book.itemInfoFor('Reference Input')?.craftUses, isEmpty);
    },
  );

  test(
    'curated reference records are browsable but never become planner state',
    () {
      final environment = buildRecipeBookTestEnvironment(
        activeMode: CraftMode.processing,
        showDeleteTools: true,
        includeEdaniaReferenceFixture: true,
      );
      final mode = environment.application.modes[CraftMode.processing]!;
      final book = RecipeBookController(
        modeController: mode,
        catalogRepository: environment.catalogRepository,
        callingContext: RecipeBookCallingContext.planner,
        allowedTargets: mode.craftableNames,
      );
      addTearDown(book.dispose);
      addTearDown(environment.dispose);

      const reference = 'Dawnbound Ekleta Necklace';
      final names = book.snapshot.entries.map((entry) => entry.name).toSet();
      expect(names, contains(reference));
      expect(names, isNot(contains('Legacy Manual Record')));

      final targetBefore = mode.state.value.target;
      expect(book.activate(reference), isNull);
      expect(mode.state.value.target, targetBefore);
      book.toggleFavorite(reference);
      expect(mode.state.value.favoriteRecipes, isNot(contains(reference)));
      book.beginDeleteSelection();
      book.toggleDeleteSelection(reference);
      expect(book.selectedForDeletion, isEmpty);

      final info = book.itemInfoFor(reference);
      expect(info?.acquisitionFormulas, hasLength(1));
      expect(
        info?.acquisitionFormulas.single.ingredients
            .map((ingredient) => (ingredient.name, ingredient.quantity))
            .toList(),
        const <(String, double)>[
          ('Ekleta Necklace', 1),
          ('Cup of Destined Dawn', 1),
        ],
      );
      expect(book.isEstimatedOutput('Polished Marble'), isTrue);
      expect(book.isEstimatedOutput(reference), isFalse);
    },
  );

  test(
    'deleted current-mode recipes do not reappear as acquisition info',
    () async {
      final environment = buildRecipeBookTestEnvironment(
        activeMode: CraftMode.processing,
        showDeleteTools: true,
      );
      final mode = environment.application.modes[CraftMode.processing]!;
      mode.updateState(
        (state) => state.copyWith(
          recipeEdits: <String, RecipeState?>{
            ...state.recipeEdits,
            'Black Stone Batch 01': null,
            'Crystal Shard 02': RecipeState(
              type: 'processing',
              baseOutput: 1,
              group: 'Processing',
              method: 'Heating',
              ingredients: <IngredientState>[
                IngredientState(
                  name: 'Black Stone Batch 01',
                  quantity: 2,
                  options: const <String>[],
                  substituteGroup: null,
                  substituteRatios: const <String, double>{},
                ),
              ],
              marketId: null,
              sourceNote: null,
              vendor: null,
              location: null,
              npcPrice: 0,
              qualityBase: null,
              qualityGrade: null,
              outputMinimum: 1,
              outputMaximum: 1,
            ),
          },
        ),
        immediate: true,
      );
      final book = RecipeBookController(
        modeController: mode,
        catalogRepository: environment.catalogRepository,
        callingContext: RecipeBookCallingContext.planner,
        allowedTargets: mode.craftableNames,
      );
      addTearDown(book.dispose);
      addTearDown(environment.dispose);

      final info = book.itemInfoFor('Black Stone Batch 01');
      expect(info, isNotNull);
      expect(
        info?.howToObtain,
        isEmpty,
        reason: 'The bundled copy was explicitly deleted from this mode.',
      );
      expect(info?.craftUses.single.output, 'Crystal Shard 02');
      expect(
        info?.craftUses.single.recipes.single,
        'Heating: 2 Black Stone Batch 01.',
      );
    },
  );

  test(
    'search refresh waits until the platform edit event has unwound',
    () async {
      final environment = buildRecipeBookTestEnvironment();
      final mode = environment.application.modes[CraftMode.alchemy]!;
      final book = RecipeBookController(
        modeController: mode,
        catalogRepository: environment.catalogRepository,
        callingContext: RecipeBookCallingContext.planner,
        allowedTargets: mode.craftableNames,
      );
      addTearDown(book.dispose);
      addTearDown(environment.dispose);
      var notifications = 0;
      book.addListener(() => notifications += 1);

      book.setSearch('Clear');
      expect(book.search, 'Clear');
      expect(notifications, 0);

      await Future<void>.microtask(() {});
      expect(
        notifications,
        0,
        reason: 'A microtask still runs inside the Windows text-input event.',
      );

      await Future<void>.delayed(Duration.zero);
      expect(notifications, 1);
    },
  );

  test('search and persisted filters reset page and scroll', () async {
    final environment = buildRecipeBookTestEnvironment(
      activeMode: CraftMode.processing,
    );
    final mode = environment.application.modes[CraftMode.processing]!;
    final book = RecipeBookController(
      modeController: mode,
      catalogRepository: environment.catalogRepository,
      callingContext: RecipeBookCallingContext.planner,
      allowedTargets: mode.craftableNames,
    );
    addTearDown(book.dispose);
    addTearDown(environment.dispose);

    Recipe classificationRecipe(String name) => Recipe(
      name: name,
      type: 'processing',
      baseOutput: 1,
      group: 'Processing',
      method: 'Grinding',
      ingredients: const <Ingredient>[],
      marketId: null,
      sourceNote: null,
      vendor: null,
      location: null,
      npcPrice: 0,
      qualityBase: null,
      qualityGrade: null,
      outputMinimum: null,
      outputMaximum: null,
    );

    expect(
      book.processingGroupFor(
        'Black Stone Powder',
        classificationRecipe('Black Stone Powder'),
      ),
      ProcessingRecipeGroup.alchemy,
    );
    expect(
      book.processingGroupFor(
        'Pure Copper Crystal',
        classificationRecipe('Pure Copper Crystal'),
      ),
      ProcessingRecipeGroup.metals,
    );
    expect(
      book.processingGroupFor(
        'Concentrated Boss Crystal',
        classificationRecipe('Concentrated Boss Crystal'),
      ),
      ProcessingRecipeGroup.enhancement,
    );

    expect(book.snapshot.entries, hasLength(36));
    book.nextPage();
    book.recordScrollOffset(90);
    expect(book.page, 0);
    expect(book.scrollOffset, 90);

    book.setSearch('sovereign');
    expect(book.page, 0);
    expect(book.scrollOffset, 0);
    expect(
      book.snapshot.entries.map((entry) => entry.name),
      contains('Black Stone Batch 01'),
    );

    book.setSearch('');
    book.setFavoritesOnly(true);
    expect(mode.state.value.bookFavoritesOnly, isTrue);
    expect(book.snapshot.entries, isEmpty);
  });

  test('R05 Processing can search recipes by their direct ingredients', () {
    final environment = buildRecipeBookTestEnvironment(
      activeMode: CraftMode.processing,
    );
    final mode = environment.application.modes[CraftMode.processing]!;
    final book = RecipeBookController(
      modeController: mode,
      catalogRepository: environment.catalogRepository,
      callingContext: RecipeBookCallingContext.planner,
      allowedTargets: mode.craftableNames,
    );
    addTearDown(book.dispose);
    addTearDown(environment.dispose);

    book.nextPage();
    book.recordScrollOffset(75);
    book.setSearch('Raw Material 01');
    expect(book.snapshot.entries, isEmpty);

    book.setSearchByIngredient(true);

    expect(mode.state.value.bookSearchIngredients, isTrue);
    expect(book.page, 0);
    expect(book.scrollOffset, 0);
    expect(book.searchHint, 'Ingredient name, for example Black Stone Powder');
    expect(book.snapshot.entries.map((entry) => entry.name), const <String>[
      'Black Stone Batch 01',
    ]);

    book.setSearchByIngredient(false);
    expect(book.snapshot.entries, isEmpty);
  });

  test(
    'ingredient search previews and targets the exact searched substitute',
    () {
      final environment = buildRecipeBookTestEnvironment(
        includeLongSubstituteFixture: true,
      );
      final mode = environment.application.modes[CraftMode.alchemy]!;
      final book = RecipeBookController(
        modeController: mode,
        catalogRepository: environment.catalogRepository,
        callingContext: RecipeBookCallingContext.planner,
        allowedTargets: mode.craftableNames,
      );
      addTearDown(book.dispose);
      addTearDown(environment.dispose);

      book.setSearchByIngredient(true);
      book.setSearch('Wolf Blood');
      expect(
        book.snapshot.entries.map((entry) => entry.name),
        contains("Clown's Blood"),
      );

      book.openPreview("Clown's Blood");
      final ingredient = book.recipeFor("Clown's Blood")!.ingredients.first;
      expect(
        book.selectedSubstitute("Clown's Blood", ingredient),
        'Wolf Blood',
      );
      expect(mode.state.value.substituteChoices, isEmpty);

      final activation = book.activate("Clown's Blood");

      expect(activation?.exactName, "Clown's Blood");
      expect(mode.state.value.target, "Clown's Blood");
      expect(
        mode.state.value.substituteChoices["recipe:Clown's Blood:Blood Group"],
        'Wolf Blood',
      );
    },
  );

  test('a manual preview substitute overrides ingredient-search context', () {
    final environment = buildRecipeBookTestEnvironment(
      includeLongSubstituteFixture: true,
    );
    final mode = environment.application.modes[CraftMode.alchemy]!;
    final book = RecipeBookController(
      modeController: mode,
      catalogRepository: environment.catalogRepository,
      callingContext: RecipeBookCallingContext.planner,
      allowedTargets: mode.craftableNames,
    );
    addTearDown(book.dispose);
    addTearDown(environment.dispose);

    book.setSearchByIngredient(true);
    book.setSearch('Wolf Blood');
    book.openPreview("Clown's Blood");
    final ingredient = book.recipeFor("Clown's Blood")!.ingredients.first;
    book.selectSubstitute(
      parentName: "Clown's Blood",
      ingredient: ingredient,
      selection: 'Flamingo Blood',
    );

    expect(
      book.selectedSubstitute("Clown's Blood", ingredient),
      'Flamingo Blood',
    );
    expect(book.activate("Clown's Blood"), isNotNull);
    expect(
      mode.state.value.substituteChoices["recipe:Clown's Blood:Blood Group"],
      'Flamingo Blood',
    );
  });

  test('a direct recipe-name hit never invents an ingredient selection', () {
    final environment = buildRecipeBookTestEnvironment(
      includeLongSubstituteFixture: true,
    );
    final mode = environment.application.modes[CraftMode.alchemy]!;
    final book = RecipeBookController(
      modeController: mode,
      catalogRepository: environment.catalogRepository,
      callingContext: RecipeBookCallingContext.planner,
      allowedTargets: mode.craftableNames,
    );
    addTearDown(book.dispose);
    addTearDown(environment.dispose);

    book.setSearchByIngredient(true);
    book.setSearch("Clown's Blood");
    book.openPreview("Clown's Blood");
    final ingredient = book.recipeFor("Clown's Blood")!.ingredients.first;

    expect(
      book.selectedSubstitute("Clown's Blood", ingredient),
      'Cheetah Dragon Blood',
    );
    expect(book.activate("Clown's Blood"), isNotNull);
    expect(
      mode.state.value.substituteChoices,
      isNot(contains("recipe:Clown's Blood:Blood Group")),
    );
  });

  test('a substitute-group hit remains visible without choosing an option', () {
    final environment = buildRecipeBookTestEnvironment(
      includeLongSubstituteFixture: true,
    );
    final mode = environment.application.modes[CraftMode.alchemy]!;
    final book = RecipeBookController(
      modeController: mode,
      catalogRepository: environment.catalogRepository,
      callingContext: RecipeBookCallingContext.planner,
      allowedTargets: mode.craftableNames,
    );
    addTearDown(book.dispose);
    addTearDown(environment.dispose);

    book.setSearchByIngredient(true);
    book.setSearch('Blood Group');
    expect(
      book.snapshot.entries.map((entry) => entry.name),
      contains("Clown's Blood"),
    );
    book.openPreview("Clown's Blood");
    final ingredient = book.recipeFor("Clown's Blood")!.ingredients.first;

    expect(
      book.selectedSubstitute("Clown's Blood", ingredient),
      'Cheetah Dragon Blood',
    );
    expect(book.activate("Clown's Blood"), isNotNull);
    expect(
      mode.state.value.substituteChoices,
      isNot(contains("recipe:Clown's Blood:Blood Group")),
    );
  });

  test('a Processing alias hit stays visible without ingredient context', () {
    final environment = buildRecipeBookTestEnvironment(
      activeMode: CraftMode.processing,
    );
    final mode = environment.application.modes[CraftMode.processing]!;
    final book = RecipeBookController(
      modeController: mode,
      catalogRepository: environment.catalogRepository,
      callingContext: RecipeBookCallingContext.planner,
      allowedTargets: mode.craftableNames,
    );
    addTearDown(book.dispose);
    addTearDown(environment.dispose);

    book.setSearchByIngredient(true);
    book.setSearch('sovereign');

    expect(book.snapshot.entries.map((entry) => entry.name), const <String>[
      'Black Stone Batch 01',
    ]);
    expect(book.activate('Black Stone Batch 01'), isNotNull);
    expect(mode.state.value.substituteChoices, isEmpty);
    expect(mode.state.value.recipeVariantChoices, isEmpty);
  });

  test('base and alternate variant ingredient hits use the same matcher', () {
    final environment = buildRecipeBookTestEnvironment(
      includeUsedInVariantFixture: true,
    );
    final mode = environment.application.modes[CraftMode.alchemy]!;
    final book = RecipeBookController(
      modeController: mode,
      catalogRepository: environment.catalogRepository,
      callingContext: RecipeBookCallingContext.planner,
      allowedTargets: mode.craftableNames,
    );
    addTearDown(book.dispose);
    addTearDown(environment.dispose);

    book.setSearchByIngredient(true);
    book.setSearch('Sunflower');
    expect(
      book.snapshot.entries.map((entry) => entry.name),
      contains('Elixir of Life'),
    );
    expect(book.selectedRecipeVariantId('Elixir of Life'), 'classic-1x');

    book.setSearch('Pure Powder Reagent');
    expect(
      book.snapshot.entries.map((entry) => entry.name),
      contains('Elixir of Life'),
    );
    expect(book.selectedRecipeVariantId('Elixir of Life'), 'concentrated-1x');
  });

  test('ingredient search selects a matching complete recipe variant', () {
    final environment = buildRecipeBookTestEnvironment(
      includeUsedInVariantFixture: true,
    );
    final mode = environment.application.modes[CraftMode.alchemy]!;
    final book = RecipeBookController(
      modeController: mode,
      catalogRepository: environment.catalogRepository,
      callingContext: RecipeBookCallingContext.planner,
      allowedTargets: mode.craftableNames,
    );
    addTearDown(book.dispose);
    addTearDown(environment.dispose);

    book.setSearchByIngredient(true);
    book.setSearch('Pure Powder Reagent');
    book.openPreview('Elixir of Life');

    expect(book.selectedRecipeVariantId('Elixir of Life'), 'concentrated-1x');
    expect(
      book.recipeFor('Elixir of Life')!.ingredients.map((value) => value.name),
      contains('Pure Powder Reagent'),
    );
    expect(
      mode.state.value.recipeVariantChoices['Elixir of Life'],
      isNull,
      reason: 'Preview context must remain transient.',
    );

    final activation = book.activate('Elixir of Life');

    expect(activation?.variantId, 'concentrated-1x');
    expect(
      mode.state.value.recipeVariantChoices['Elixir of Life'],
      'concentrated-1x',
    );
  });

  test(
    'market refresh includes recipes resolved by the bundled ID index',
    () async {
      final environment = buildRecipeBookTestEnvironment();
      final mode = environment.application.modes[CraftMode.alchemy]!;
      final requestedNames = <String>[];
      final book = RecipeBookController(
        modeController: mode,
        catalogRepository: environment.catalogRepository,
        callingContext: RecipeBookCallingContext.planner,
        allowedTargets: const <String>['Clear Liquid Reagent'],
        checkPrices: (request) async {
          requestedNames.addAll(request.namesForRefresh);
          return const PlannerMarketRefresh(
            prices: <String, double>{'Clear Liquid Reagent': 5100},
            stock: <String, double>{'Clear Liquid Reagent': 25},
            tradeMarketIds: <String, String>{'Clear Liquid Reagent': '5301'},
            totalTrades: <String, int>{'Clear Liquid Reagent': 1200},
            tradeObservedAt: <String, int>{'Clear Liquid Reagent': 1000},
            observedDailyTrades: <String, double>{'Clear Liquid Reagent': 240},
            tradeObservationHours: <String, double>{'Clear Liquid Reagent': 6},
            lastSoldAtEpochSeconds: <String, int>{'Clear Liquid Reagent': 900},
            unlistedItemNames: <String>{},
            fetchedAt: 42,
            summary: 'Market stock updated.',
          );
        },
      );
      addTearDown(book.dispose);
      addTearDown(environment.dispose);

      expect(mode.recipes['Clear Liquid Reagent']?.marketId, isNull);
      expect(mode.state.value.ingredientMeta, isEmpty);

      await book.checkMarket();

      expect(requestedNames, const <String>['Clear Liquid Reagent']);
      expect(mode.state.value.market.stock['Clear Liquid Reagent'], 25);
      expect(
        mode.state.value.market.observedDailyTrades['Clear Liquid Reagent'],
        240,
      );
      expect(
        mode.state.value.market.tradeObservationHours['Clear Liquid Reagent'],
        6,
      );
    },
  );

  test(
    'Recipe Book market mode refreshes visible outputs and filters zero stock',
    () async {
      final environment = buildRecipeBookTestEnvironment();
      final mode = environment.application.modes[CraftMode.alchemy]!;
      mode.updateState(
        (state) => state.copyWith(
          ingredientMeta: <String, IngredientMetadata>{
            'Clear Liquid Reagent': IngredientMetadata(marketId: '5301'),
            'Pure Powder Reagent': IngredientMetadata(marketId: '5302'),
            'Elixir of Life': IngredientMetadata(marketId: '5303'),
          },
        ),
        immediate: true,
      );
      final requestedNames = <String>[];
      var refreshCount = 0;
      final book = RecipeBookController(
        modeController: mode,
        catalogRepository: environment.catalogRepository,
        callingContext: RecipeBookCallingContext.planner,
        allowedTargets: mode.craftableNames,
        checkPrices: (request) async {
          refreshCount += 1;
          requestedNames.addAll(request.namesForRefresh);
          return const PlannerMarketRefresh(
            prices: <String, double>{},
            stock: <String, double>{
              'Clear Liquid Reagent': 0,
              'Pure Powder Reagent': 12,
              'Elixir of Life': 3,
            },
            unlistedItemNames: <String>{},
            fetchedAt: 42,
            summary: 'Market stock updated.',
          );
        },
      );
      addTearDown(book.dispose);
      addTearDown(environment.dispose);

      expect(book.marketControlsVisible, isFalse);
      expect(book.snapshot.entries.map((entry) => entry.marketStock), [
        null,
        null,
        null,
      ]);

      await book.checkMarket();
      expect(book.marketControlsVisible, isTrue);
      expect(refreshCount, 1);
      expect(requestedNames, const <String>[
        'Clear Liquid Reagent',
        'Elixir of Life',
        'Pure Powder Reagent',
      ]);
      expect(mode.state.value.market.stock['Clear Liquid Reagent'], 0);

      book.setOutOfStockOnly(true);
      expect(book.snapshot.entries.map((entry) => entry.name), const <String>[
        'Clear Liquid Reagent',
      ]);

      book.setOutOfStockOnly(false);
      book.setMarketSort(RecipeBookMarketSort.stockLowToHigh);
      expect(book.snapshot.entries.map((entry) => entry.name), const <String>[
        'Clear Liquid Reagent',
        'Elixir of Life',
        'Pure Powder Reagent',
      ]);

      await book.checkMarket();
      expect(refreshCount, 2);

      book.hideMarket();
      expect(book.marketControlsVisible, isFalse);
      expect(book.outOfStockOnly, isFalse);
      expect(book.marketSort, RecipeBookMarketSort.none);
      expect(book.marketMessage, isNull);
      expect(book.snapshot.entries.map((entry) => entry.marketStock), [
        null,
        null,
        null,
      ]);
    },
  );

  test(
    'profitable recipes buy every direct ingredient and intersect with zero stock',
    () async {
      final environment = buildRecipeBookTestEnvironment();
      final mode = environment.application.modes[CraftMode.alchemy]!;
      const ids = <String, String>{
        'Clear Liquid Reagent': '5301',
        'Pure Powder Reagent': '5302',
        'Elixir of Life': '5303',
        'Wild Grass': '5304',
        'Sunflower': '5305',
        'Trace of Earth': '5306',
      };
      mode.updateState(
        (state) => state.copyWith(
          ingredientMeta: <String, IngredientMetadata>{
            for (final entry in ids.entries)
              entry.key: IngredientMetadata(marketId: entry.value),
          },
        ),
        immediate: true,
      );
      final requestedNames = <String>[];
      final book = RecipeBookController(
        modeController: mode,
        catalogRepository: environment.catalogRepository,
        callingContext: RecipeBookCallingContext.planner,
        allowedTargets: mode.craftableNames,
        checkPrices: (request) async {
          requestedNames.addAll(request.namesForRefresh);
          return const PlannerMarketRefresh(
            prices: <String, double>{
              'Clear Liquid Reagent': 1000,
              'Pure Powder Reagent': 500,
              'Elixir of Life': 2000,
              'Wild Grass': 100,
              'Sunflower': 100,
              'Trace of Earth': 400,
            },
            stock: <String, double>{
              'Clear Liquid Reagent': 0,
              'Pure Powder Reagent': 12,
              'Elixir of Life': 3,
              'Wild Grass': 1000,
              'Sunflower': 1000,
              'Trace of Earth': 1000,
            },
            unlistedItemNames: <String>{},
            fetchedAt: 42,
            summary: 'Market stock updated.',
          );
        },
      );
      addTearDown(book.dispose);
      addTearDown(environment.dispose);

      await book.checkMarket();

      expect(requestedNames, const <String>[
        'Clear Liquid Reagent',
        'Elixir of Life',
        'Pure Powder Reagent',
        'Sunflower',
        'Trace of Earth',
        'Wild Grass',
      ]);

      book.setProfitableOnly(true);
      expect(book.profitableOnly, isTrue);
      expect(book.marketSort, RecipeBookMarketSort.profitHighToLow);
      expect(book.snapshot.entries.map((entry) => entry.name), const <String>[
        'Elixir of Life',
        'Clear Liquid Reagent',
      ]);
      expect(
        book.snapshot.entries.every(
          (entry) =>
              entry.profitability?.isAvailable == true &&
              entry.profitability!.profitPerPiece! > 0,
        ),
        isTrue,
      );

      book.setMarketSort(RecipeBookMarketSort.profitLowToHigh);
      expect(book.snapshot.entries.map((entry) => entry.name), const <String>[
        'Clear Liquid Reagent',
        'Elixir of Life',
      ]);

      book.setOutOfStockOnly(true);
      expect(book.snapshot.entries.map((entry) => entry.name), const <String>[
        'Clear Liquid Reagent',
      ]);

      book.setOutOfStockOnly(false);
      mode.updateState(
        (state) => state.copyWith(
          ingredientMeta: <String, IngredientMetadata>{
            for (final entry in state.ingredientMeta.entries)
              if (entry.key != 'Trace of Earth') entry.key: entry.value,
          },
        ),
        immediate: true,
      );
      expect(
        book.snapshot.entries.map((entry) => entry.name),
        const <String>['Clear Liquid Reagent'],
        reason:
            'A stale cached ingredient price must not make a recipe look '
            'currently estimable after its market ID becomes unavailable.',
      );

      book.hideMarket();
      expect(book.profitableOnly, isFalse);
      expect(book.outOfStockOnly, isFalse);
      expect(book.marketSort, RecipeBookMarketSort.none);
      expect(
        book.snapshot.entries.every((entry) => entry.profitability == null),
        isTrue,
      );
    },
  );

  test(
    'global market bonuses notify the book and recompute profitability',
    () async {
      final environment = buildRecipeBookTestEnvironment();
      final mode = environment.application.modes[CraftMode.alchemy]!;
      mode.updateState(
        (state) => state.copyWith(
          ingredientMeta: <String, IngredientMetadata>{
            'Clear Liquid Reagent': IngredientMetadata(marketId: '5301'),
            'Wild Grass': IngredientMetadata(marketId: '5302'),
            'Sunflower': IngredientMetadata(marketId: '5303'),
          },
          market: state.market.copyWith(
            prices: const <String, double>{
              'Clear Liquid Reagent': 1000,
              'Wild Grass': 100,
              'Sunflower': 100,
            },
          ),
        ),
        immediate: true,
      );
      final book = RecipeBookController(
        modeController: mode,
        catalogRepository: environment.catalogRepository,
        callingContext: RecipeBookCallingContext.planner,
        allowedTargets: mode.craftableNames,
      );
      addTearDown(book.dispose);
      addTearDown(environment.dispose);
      final modeStateBeforeTaxChange = mode.state.value;
      var notifications = 0;
      book.addListener(() => notifications += 1);

      final baseTaxQuote = book.profitabilityFor('Clear Liquid Reagent')!;
      expect(baseTaxQuote.marketNetRate, closeTo(.65, 1e-12));
      expect(baseTaxQuote.netRevenue, closeTo(650, 1e-9));

      environment.application.updateDocument(
        (document) => document.copyWith(
          marketTax: document.marketTax.copyWith(
            enabled: true,
            valuePack: true,
          ),
        ),
        immediate: true,
      );
      await Future<void>.delayed(Duration.zero);

      expect(identical(mode.state.value, modeStateBeforeTaxChange), isTrue);
      expect(notifications, 1);
      final valuePackQuote = book.profitabilityFor('Clear Liquid Reagent')!;
      expect(valuePackQuote.marketNetRate, closeTo(.845, 1e-12));
      expect(valuePackQuote.netRevenue, closeTo(845, 1e-9));
    },
  );

  test('pending market refresh can finish after the book closes', () async {
    final environment = buildRecipeBookTestEnvironment();
    final mode = environment.application.modes[CraftMode.alchemy]!;
    mode.updateState(
      (state) => state.copyWith(
        ingredientMeta: <String, IngredientMetadata>{
          'Clear Liquid Reagent': IngredientMetadata(marketId: '5301'),
        },
      ),
      immediate: true,
    );
    final refresh = Completer<PlannerMarketRefresh>();
    final book = RecipeBookController(
      modeController: mode,
      catalogRepository: environment.catalogRepository,
      callingContext: RecipeBookCallingContext.planner,
      allowedTargets: const <String>['Clear Liquid Reagent'],
      checkPrices: (_) => refresh.future,
    );

    final pending = book.checkMarket();
    expect(book.marketLoading, isTrue);
    book.dispose();
    refresh.complete(
      const PlannerMarketRefresh(
        prices: <String, double>{},
        stock: <String, double>{'Clear Liquid Reagent': 7},
        unlistedItemNames: <String>{},
        fetchedAt: 44,
        summary: 'Market stock updated.',
      ),
    );
    await pending;

    expect(mode.state.value.market.stock['Clear Liquid Reagent'], 7);
    await environment.dispose();
  });

  test('Processing uses one continuous grouped catalog', () async {
    final environment = buildRecipeBookTestEnvironment(
      activeMode: CraftMode.processing,
    );
    final mode = environment.application.modes[CraftMode.processing]!;
    final book = RecipeBookController(
      modeController: mode,
      catalogRepository: environment.catalogRepository,
      callingContext: RecipeBookCallingContext.planner,
      allowedTargets: mode.craftableNames,
    );
    addTearDown(book.dispose);
    addTearDown(environment.dispose);

    expect(book.snapshot.entries, hasLength(36));
    book.setDensity(RecipeBookDensity.fiveByFour);
    expect(book.snapshot.entries, hasLength(36));
    book.setDensity(RecipeBookDensity.sixByFive);
    expect(book.snapshot.entries, hasLength(36));
    expect(book.snapshot.pageCount, 1);
    book.nextPage();
    book.nextPage();
    expect(book.page, 0);
    expect(book.snapshot.entries, hasLength(36));
    book.previousPage();
    expect(book.page, 0);

    book.setGroup(ProcessingRecipeGroup.metals);
    expect(book.page, 0);
    expect(
      book.snapshot.entries,
      everyElement(
        isA<RecipeBookEntry>().having(
          (entry) => entry.processingGroup,
          'group',
          ProcessingRecipeGroup.metals,
        ),
      ),
    );

    book.setGroup(ProcessingRecipeGroup.lightstones);
    expect(book.snapshot.entries.map((entry) => entry.name), const <String>[
      'Lightstone Fragment 03',
    ]);
    expect(
      book.snapshot.entries.single.processingGroup,
      ProcessingRecipeGroup.lightstones,
    );

    book.setGroup(ProcessingRecipeGroup.crystals);
    expect(
      book.snapshot.entries.map((entry) => entry.name),
      isNot(contains('Lightstone Fragment 03')),
    );
    expect(
      book.snapshot.entries,
      everyElement(
        isA<RecipeBookEntry>().having(
          (entry) => entry.processingGroup,
          'group',
          ProcessingRecipeGroup.crystals,
        ),
      ),
    );
  });

  test('calling contexts mutate only their target contract', () async {
    final environment = buildRecipeBookTestEnvironment();
    final mode = environment.application.modes[CraftMode.alchemy]!;
    final planner = RecipeBookController(
      modeController: mode,
      catalogRepository: environment.catalogRepository,
      callingContext: RecipeBookCallingContext.planner,
      allowedTargets: mode.craftableNames,
    );
    final bonus = RecipeBookController(
      modeController: mode,
      catalogRepository: environment.catalogRepository,
      callingContext: RecipeBookCallingContext.bonus,
      allowedTargets: const <String>['Elixir of Life', 'Pure Powder Reagent'],
    );
    addTearDown(planner.dispose);
    addTearDown(bonus.dispose);
    addTearDown(environment.dispose);

    mode.toggleCompleted('Clear Liquid Reagent');
    final bonusActivation = bonus.activate('Pure Powder Reagent');
    expect(bonusActivation?.context, RecipeBookCallingContext.bonus);
    expect(mode.state.value.bonusTarget, 'Pure Powder Reagent');
    expect(mode.state.value.target, 'Clear Liquid Reagent');
    expect(mode.state.value.completedSteps, contains('Clear Liquid Reagent'));

    final plannerActivation = planner.activate('Elixir of Life');
    expect(plannerActivation?.context, RecipeBookCallingContext.planner);
    expect(mode.state.value.target, 'Elixir of Life');
    expect(mode.state.value.completedSteps, isEmpty);
  });

  test(
    'favorites are canonical, case-insensitive distinct, and sorted',
    () async {
      final environment = buildRecipeBookTestEnvironment();
      final mode = environment.application.modes[CraftMode.alchemy]!;
      mode.updateState(
        (state) => state.copyWith(
          favoriteRecipes: const <String>[
            'pure powder reagent',
            'Pure Powder Reagent',
          ],
        ),
        immediate: true,
      );
      final book = RecipeBookController(
        modeController: mode,
        catalogRepository: environment.catalogRepository,
        callingContext: RecipeBookCallingContext.planner,
        allowedTargets: mode.craftableNames,
      );
      addTearDown(book.dispose);
      addTearDown(environment.dispose);

      book.toggleFavorite('Clear Liquid Reagent');
      expect(mode.state.value.favoriteRecipes, const <String>[
        'Clear Liquid Reagent',
        'Pure Powder Reagent',
      ]);
      book.toggleFavorite('PURE POWDER REAGENT');
      expect(mode.state.value.favoriteRecipes, const <String>[
        'Clear Liquid Reagent',
      ]);
    },
  );

  test(
    'preview substitute and quality choices use ModeFeatureController',
    () async {
      final environment = buildRecipeBookTestEnvironment();
      final mode = environment.application.modes[CraftMode.alchemy]!;
      final book = RecipeBookController(
        modeController: mode,
        catalogRepository: environment.catalogRepository,
        callingContext: RecipeBookCallingContext.planner,
        allowedTargets: mode.craftableNames,
      );
      addTearDown(book.dispose);
      addTearDown(environment.dispose);

      final recipe = book.recipeFor('Clear Liquid Reagent')!;
      final substitute = recipe.ingredients.first;
      book.selectSubstitute(
        parentName: recipe.name,
        ingredient: substitute,
        selection: 'Weed',
      );
      expect(
        mode
            .state
            .value
            .substituteChoices['recipe:Clear Liquid Reagent:Wild Plants'],
        'Weed',
      );

      final quality = recipe.ingredients[1];
      expect(
        book.qualityGrades(
          parentName: recipe.name,
          ingredient: quality,
          selectedName: 'Sunflower',
        ),
        const <String>['normal', 'high', 'special'],
      );
      book.selectQuality(
        parentName: recipe.name,
        ingredient: quality,
        grade: 'special',
      );
      expect(
        mode
            .state
            .value
            .ingredientGrades['recipe:Clear Liquid Reagent:Sunflower'],
        'special',
      );
    },
  );

  test(
    'disabling delete tools clears the live selection immediately',
    () async {
      final environment = buildRecipeBookTestEnvironment(
        activeMode: CraftMode.processing,
        showDeleteTools: true,
      );
      final mode = environment.application.modes[CraftMode.processing]!;
      final book = RecipeBookController(
        modeController: mode,
        catalogRepository: environment.catalogRepository,
        callingContext: RecipeBookCallingContext.planner,
        allowedTargets: mode.craftableNames,
      );
      addTearDown(book.dispose);
      addTearDown(environment.dispose);

      book.beginDeleteSelection();
      book.toggleDeleteSelection(book.snapshot.entries.first.name);
      book.requestDeleteConfirmation();
      expect(book.selectedForDeletion, isNotEmpty);
      expect(book.deleteConfirmationVisible, isTrue);

      environment.application.updateDocument(
        (document) => document.copyWith(showDeleteTools: false),
        immediate: true,
      );

      expect(book.deleteSelectionMode, isFalse);
      expect(book.selectedForDeletion, isEmpty);
      expect(book.deleteConfirmationVisible, isFalse);
    },
  );

  test(
    'Show Hidden restores a legacy bundled tombstone after restart',
    () async {
      final environment = buildRecipeBookTestEnvironment(
        activeMode: CraftMode.processing,
        showDeleteTools: true,
      );
      final mode = environment.application.modes[CraftMode.processing]!;
      final hiddenName = mode.craftableNames.first;
      mode.updateState(
        (state) => state.copyWith(
          hiddenItems: <String>[hiddenName],
          recipeEdits: <String, RecipeState?>{
            ...state.recipeEdits,
            hiddenName: null,
          },
        ),
        immediate: true,
      );
      final book = RecipeBookController(
        modeController: mode,
        catalogRepository: environment.catalogRepository,
        callingContext: RecipeBookCallingContext.planner,
        allowedTargets: mode.craftableNames,
      );
      addTearDown(book.dispose);
      addTearDown(environment.dispose);

      expect(book.canShowHidden, isTrue);
      expect(book.hiddenItemCount, 1);
      expect(
        book.snapshot.entries.any((entry) => entry.name == hiddenName),
        isFalse,
      );

      book.setShowHidden(true);
      final hiddenEntry = book.snapshot.entries.singleWhere(
        (entry) => entry.name == hiddenName,
      );
      expect(hiddenEntry.hidden, isTrue);

      await book.restoreHiddenItem(hiddenName);

      expect(mode.state.value.hiddenItems, isNot(contains(hiddenName)));
      expect(mode.state.value.recipeEdits, isNot(contains(hiddenName)));
      expect(book.hiddenItemCount, 0);
      expect(book.showHidden, isFalse);
      expect(
        book.snapshot.entries
            .singleWhere((entry) => entry.name == hiddenName)
            .hidden,
        isFalse,
      );
    },
  );

  test(
    'R20 write failure rolls back and leaves no false success or undo',
    () async {
      final environment = buildRecipeBookTestEnvironment(
        activeMode: CraftMode.processing,
        showDeleteTools: true,
        saveState: (_) async => throw const FileSystemException(
          'injected recipe book disk failure',
        ),
      );
      final mode = environment.application.modes[CraftMode.processing]!;
      final book = RecipeBookController(
        modeController: mode,
        catalogRepository: environment.catalogRepository,
        callingContext: RecipeBookCallingContext.planner,
        allowedTargets: mode.craftableNames,
      );
      addTearDown(book.dispose);
      addTearDown(environment.dispose);
      final selected = book.snapshot.entries.first.name;

      book.beginDeleteSelection();
      book.toggleDeleteSelection(selected);
      book.requestDeleteConfirmation();
      final outcome = await book.confirmDeleteSelection();

      expect(outcome, isNull);
      expect(mode.state.value.hiddenItems, isNot(contains(selected)));
      expect(book.canUndoDeletion, isFalse);
      expect(book.deleteSelectionMode, isTrue);
      expect(book.deletionError, contains('injected recipe book disk failure'));
    },
  );

  test('R20 Undo preserves unrelated changes made after hiding', () async {
    final environment = buildRecipeBookTestEnvironment(
      activeMode: CraftMode.processing,
      showDeleteTools: true,
    );
    final mode = environment.application.modes[CraftMode.processing]!;
    final book = RecipeBookController(
      modeController: mode,
      catalogRepository: environment.catalogRepository,
      callingContext: RecipeBookCallingContext.planner,
      allowedTargets: mode.craftableNames,
    );
    addTearDown(book.dispose);
    addTearDown(environment.dispose);
    final selected = book.snapshot.entries[1].name;

    book.beginDeleteSelection();
    book.toggleDeleteSelection(selected);
    book.requestDeleteConfirmation();
    expect(await book.confirmDeleteSelection(), isNotNull);

    mode.updateState(
      (state) => state.copyWith(
        inventory: <String, double>{...state.inventory, 'Unrelated': 77},
      ),
      immediate: true,
    );
    await book.undoLastDeletion();

    expect(mode.state.value.hiddenItems, isNot(contains(selected)));
    expect(mode.state.value.inventory['Unrelated'], 77);
  });

  test('R20 delete and undo each survive a real repository restart', () async {
    final seed = buildRecipeBookTestEnvironment(
      activeMode: CraftMode.processing,
      showDeleteTools: true,
    );
    final catalog = seed.application.catalog;
    final initial = seed.application.documentSnapshot;
    await seed.dispose();
    final temporary = await Directory.systemTemp.createTemp(
      'bdo-recipe-book-restart-',
    );
    addTearDown(() async {
      if (await temporary.exists()) {
        await temporary.delete(recursive: true);
      }
    });
    final repository = PlannerStateRepository(
      paths: PlannerStatePathPolicy(
        applicationDirectory: Directory(
          '${temporary.path}${Platform.pathSeparator}state',
        ),
        legacyStateFile: File(
          '${temporary.path}${Platform.pathSeparator}legacy${Platform.pathSeparator}planner-state.json',
        ),
      ),
      applicationVersion: 'recipe-book-restart-test',
      utcNow: () => DateTime.utc(2026, 7, 20, 14),
    );
    final persistedInitial = await repository.save(initial);
    final application = PlannerApplicationController(
      catalog: catalog,
      initialState: persistedInitial,
      saveState: repository.save,
      saveDebounce: Duration.zero,
    );
    addTearDown(application.dispose);
    final mode = application.modes[CraftMode.processing]!;
    final book = RecipeBookController(
      modeController: mode,
      catalogRepository: CatalogRepository(catalog),
      callingContext: RecipeBookCallingContext.planner,
      allowedTargets: mode.craftableNames,
    );
    addTearDown(book.dispose);
    final selected = book.snapshot.entries.first.name;

    book.beginDeleteSelection();
    book.toggleDeleteSelection(selected);
    book.requestDeleteConfirmation();
    final outcome = await book.confirmDeleteSelection();
    expect(outcome?.hiddenNames, contains(selected));

    final afterDelete = await repository.load(catalog);
    expect(afterDelete.state.processing.hiddenItems, contains(selected));

    await book.undoLastDeletion();
    expect(book.deletionError, isNull);
    final afterUndo = await repository.load(catalog);
    expect(afterUndo.state.processing.hiddenItems, isNot(contains(selected)));
  });
}

ModeState _productionMode(CraftMode mode, {required String target}) =>
    ModeState(
      target: target,
      bonusTarget: target,
      market: MarketState(),
      appearance: AppearanceSettings.defaultsFor(mode),
    );
