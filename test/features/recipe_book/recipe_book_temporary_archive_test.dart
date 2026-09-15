import 'dart:io';

import 'package:bdo_craft_planner_flutter/app/state/planner_application_controller.dart';
import 'package:bdo_craft_planner_flutter/data/catalog/bundled_catalog_parser.dart';
import 'package:bdo_craft_planner_flutter/data/catalog/catalog_repository.dart';
import 'package:bdo_craft_planner_flutter/domain/catalog/temporarily_archived_items.dart';
import 'package:bdo_craft_planner_flutter/domain/models/catalog_models.dart';
import 'package:bdo_craft_planner_flutter/domain/models/craft_mode.dart';
import 'package:bdo_craft_planner_flutter/domain/state/planner_state.dart';
import 'package:bdo_craft_planner_flutter/domain/state/state_copy.dart';
import 'package:bdo_craft_planner_flutter/features/planner/planner_contracts.dart';
import 'package:bdo_craft_planner_flutter/features/recipe_book/recipe_book.dart';
import 'package:bdo_craft_planner_flutter/features/recipe_book/recipe_book_item_info.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late CatalogSnapshot catalog;
  setUpAll(() {
    catalog = const BundledCatalogParser().parse(
      File('assets/data/app-data.json').readAsStringSync(),
    );
  });

  test(
    'visible hide formulas use available inputs without changing raw definitions',
    () {
      final (app, book) = _environment(catalog, CraftMode.processing);
      addTearDown(app.dispose);
      addTearDown(book.dispose);
      for (final name in ['Hard Hide', 'Thin Hide', 'Magical Shard']) {
        final raw = catalog.processing.items[name]!;
        final formulas = book.itemInfoFor(name)!.acquisitionFormulas;
        expect(formulas, isNotEmpty, reason: name);
        for (final formula in formulas) {
          for (final ingredient in formula.ingredients) {
            expect(isTemporarilyArchivedItem(ingredient.name), isFalse);
            expect(
              ingredient.options.where(isTemporarilyArchivedItem),
              isEmpty,
            );
            expect(
              ingredient.substituteRatios.keys.where(isTemporarilyArchivedItem),
              isEmpty,
            );
          }
        }
        if (name == 'Hard Hide') {
          expect(raw.ingredients.first.name, 'Dinosaur Hide');
          expect(formulas.first.ingredients.first.name, 'Lizard Hide');
          expect(formulas.first.ingredients.first.quantity, 5);
        }
      }
    },
  );

  test(
    'reference substitution quantities are rebased and archived-only routes are not offered',
    () {
      final raw = Ingredient(
        name: 'Monkey Hide',
        quantity: 5,
        options: ['Monkey Hide', 'Raccoon Hide'],
        substituteGroup: 'Hides',
        substituteRatios: {'Monkey Hide': 1, 'Raccoon Hide': 2},
      );
      final info = RecipeBookItemInfo(
        title: 'Thin Hide',
        kind: 'Material',
        summary: '',
        acquisitionFormulas: [
          RecipeBookFormula(
            outputName: 'Thin Hide',
            type: 'processing',
            method: 'Drying',
            baseOutput: 1,
            ingredients: [raw],
          ),
        ],
      );
      final visible = withVisibleRecipeBookFormulas(
        info,
      ).acquisitionFormulas.single.ingredients.single;
      expect(visible.name, 'Raccoon Hide');
      expect(visible.quantity, 10);
      expect(visible.substituteRatios, {'Raccoon Hide': 1});
      expect(raw.name, 'Monkey Hide');
      expect(raw.quantity, 5);
      final archivedOnly = info.copyWith(
        acquisitionFormulas: [
          info.acquisitionFormulas.single.copyWith(
            ingredients: [
              Ingredient(
                name: 'Monkey Hide',
                quantity: 5,
                options: [],
                substituteGroup: null,
                substituteRatios: {},
              ),
            ],
          ),
        ],
      );
      expect(
        withVisibleRecipeBookFormulas(archivedOnly).acquisitionFormulas,
        isEmpty,
      );
    },
  );

  test(
    'all eight retain inspectable reference info without acquisition claims',
    () {
      final (app, book) = _environment(catalog, CraftMode.processing);
      addTearDown(app.dispose);
      addTearDown(book.dispose);
      for (final name in temporarilyArchivedItemsById.values) {
        final info = book.itemInfoFor(name)!;
        expect(info.title, name);
        expect(info.kind, temporarilyArchivedItemLabel, reason: name);
        expect(info.isTemporarilyArchived, isTrue, reason: name);
        expect(
          info.notes,
          contains(temporarilyArchivedItemReason),
          reason: name,
        );
        expect(info.howToObtain, isEmpty, reason: name);
        expect(info.summary.toLowerCase(), isNot(contains('hunting a monkey')));
        expect(info.summary.toLowerCase(), isNot(contains('hunt a monkey')));
        final enriched = withResearchedAcquisition(info, [
          'A historical source claim',
        ], vendor: 'Historical vendor');
        expect(enriched.howToObtain, isEmpty, reason: name);
        expect(enriched.isTemporarilyArchived, isTrue);
      }
      expect(
        book.itemInfoFor('Black Magic Crystal - Power')!.effects,
        isNotEmpty,
      );
      expect(book.itemInfoFor('Monkey Hide')!.craftUses, isNotEmpty);
      expect(book.itemInfoFor('Dinosaur Hide')!.craftUses, isNotEmpty);
      expect(
        book.itemInfoFor('Cheetah Dragon Hide')!.isTemporarilyArchived,
        isFalse,
      );
      expect(
        book
            .itemInfoFor('Black Magic Crystal - Precision')!
            .isTemporarilyArchived,
        isFalse,
      );
    },
  );

  test(
    'normal book pools and ingredient searches omit archived suggestions',
    () {
      for (final craftMode in CraftMode.values) {
        final (app, book) = _environment(catalog, craftMode);
        addTearDown(app.dispose);
        addTearDown(book.dispose);
        final before = app.documentSnapshot;
        expect(
          book.snapshot.entries.where(
            (entry) => isTemporarilyArchivedItem(
              entry.name,
              itemId: entry.recipe.marketId,
            ),
          ),
          isEmpty,
        );
        // Even a stale allow-list cannot reintroduce an archived target.
        for (final name in temporarilyArchivedItemsById.values) {
          expect(
            book.activate(name),
            isNull,
            reason: '${craftMode.key}: $name',
          );
        }
        expect(identical(app.documentSnapshot, before), isTrue);
        book.setSearchByIngredient(true);
        book.setSearch('Monkey Blood');
        expect(book.snapshot.entries, isEmpty, reason: craftMode.key);
      }
    },
  );

  test(
    'substitute choices filter eight identities but preserve raw options and saved data',
    () {
      final (app, book) = _environment(catalog, CraftMode.processing);
      addTearDown(app.dispose);
      addTearDown(book.dispose);
      final mode = app.modes[CraftMode.processing]!;
      final ingredient = mode.recipes['Magical Shard']!.ingredients.single;
      final rawOptions = ingredient.options;
      expect(rawOptions, contains('Black Magic Crystal - Power'));
      final options = book.substituteOptions(ingredient);
      expect(options.where(isTemporarilyArchivedItem), isEmpty);
      expect(options, contains('Sealed Black Magic Crystal'));
      expect(options, contains('Black Magic Crystal - Precision'));
      const archivedName = 'Black Magic Crystal - Power';
      final choiceKey =
          'recipe:Magical Shard:${ingredient.substituteGroup ?? ingredient.name}';
      mode.updateState(
        (state) => state.copyWith(
          inventory: {...state.inventory, archivedName: 12},
          substituteChoices: {
            ...state.substituteChoices,
            choiceKey: archivedName,
          },
        ),
      );
      final saved = mode.state.value;
      book.selectSubstitute(
        parentName: 'Magical Shard',
        ingredient: ingredient,
        selection: archivedName,
      );
      expect(identical(mode.state.value, saved), isTrue);
      expect(mode.state.value.inventory[archivedName], 12);
      expect(mode.state.value.substituteChoices[choiceKey], archivedName);
      expect(identical(ingredient.options, rawOptions), isTrue);
      expect(ingredient.options, contains(archivedName));

      final archivedOnly = Ingredient(
        name: archivedName,
        quantity: 1,
        options: [],
        substituteGroup: null,
        substituteRatios: {},
      );
      expect(book.substituteOptions(archivedOnly), isEmpty);
      expect(
        book.selectedSubstitute('Old saved recipe', archivedOnly),
        archivedName,
      );
    },
  );

  test(
    'historical Used In remains readable without targeting archived substitutes',
    () {
      final (app, book) = _environment(catalog, CraftMode.processing);
      addTearDown(app.dispose);
      addTearDown(book.dispose);
      final usages = book.usedInFor('Black Magic Crystal - Power');
      expect(usages.entries, isNotEmpty);
      for (final entry in usages.entries) {
        expect(book.canActivateUsedIn(entry), isFalse);
        expect(book.activateUsedIn(entry), isNull);
      }
    },
  );
}

(PlannerApplicationController, RecipeBookController) _environment(
  CatalogSnapshot catalog,
  CraftMode mode,
) {
  ModeState state(CraftMode mode, String target) => ModeState(
    target: target,
    bonusTarget: target,
    market: MarketState(),
    appearance: AppearanceSettings.defaultsFor(mode),
  );
  final app = PlannerApplicationController(
    catalog: catalog,
    initialState: PlannerState(
      applicationVersion: 'archive-book-test',
      lastSuccessfulWriteUtc: DateTime.utc(2026, 9, 10),
      activeMode: mode,
      alchemy: state(CraftMode.alchemy, 'Clear Liquid Reagent'),
      cooking: state(CraftMode.cooking, 'Beer'),
      processing: state(CraftMode.processing, 'Magical Shard'),
      processingYields: {},
      marketTax: MarketTax(),
      showDeleteTools: false,
    ),
    saveState: (state) async => state,
    saveDebounce: Duration.zero,
  );
  return (
    app,
    RecipeBookController(
      modeController: app.modes[mode]!,
      catalogRepository: CatalogRepository(catalog),
      callingContext: RecipeBookCallingContext.planner,
      allowedTargets: [
        ...app.modes[mode]!.craftableNames,
        ...temporarilyArchivedItemsById.values,
      ],
    ),
  );
}
