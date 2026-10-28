import 'dart:io';

import 'package:bdo_craft_planner_flutter/app/state/planner_application_controller.dart';
import 'package:bdo_craft_planner_flutter/data/catalog/bundled_catalog_parser.dart';
import 'package:bdo_craft_planner_flutter/data/catalog/catalog_repository.dart';
import 'package:bdo_craft_planner_flutter/domain/models/catalog_models.dart';
import 'package:bdo_craft_planner_flutter/domain/models/craft_mode.dart';
import 'package:bdo_craft_planner_flutter/domain/state/planner_state.dart';
import 'package:bdo_craft_planner_flutter/features/planner/planner_contracts.dart';
import 'package:bdo_craft_planner_flutter/features/recipe_book/recipe_book_controller.dart';
import 'package:bdo_craft_planner_flutter/features/recipe_book/recipe_book_item_info.dart';
import 'package:bdo_craft_planner_flutter/features/recipe_book/recipe_book_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late CatalogSnapshot catalog;
  late PlannerApplicationController application;
  late RecipeBookController book;
  const slots = ['Necklace', 'Earring', 'Ring', 'Belt'];
  const acquisitionMethods = ['Item Reform', 'Quest Exchange'];

  setUpAll(() {
    catalog = const BundledCatalogParser().parse(
      File('assets/data/app-data.json').readAsStringSync(),
    );
  });
  setUp(() {
    ModeState state(CraftMode mode, String target) => ModeState(
      target: target,
      want: 11,
      bonusTarget: target,
      market: MarketState(),
      appearance: AppearanceSettings.defaultsFor(mode),
    );
    application = PlannerApplicationController(
      catalog: catalog,
      initialState: PlannerState(
        applicationVersion: 'ekleta-search-test',
        lastSuccessfulWriteUtc: DateTime.utc(2026, 9, 25),
        activeMode: CraftMode.processing,
        alchemy: state(CraftMode.alchemy, 'Clear Liquid Reagent'),
        cooking: state(CraftMode.cooking, 'Beer'),
        processing: state(CraftMode.processing, 'Wheat Flour'),
        processingYields: const {},
        marketTax: MarketTax(),
        showDeleteTools: false,
      ),
      saveState: (value) async => value,
      saveDebounce: Duration.zero,
    );
    book = RecipeBookController(
      modeController: application.active,
      catalogRepository: CatalogRepository(catalog),
      callingContext: RecipeBookCallingContext.planner,
      allowedTargets: application.active.craftableNames,
    );
  });
  tearDown(() async {
    book.dispose();
    await application.dispose();
  });

  test('Ekleta finds every stone and keeps its exact 1x and 10x recipes', () {
    for (final query in ['ekleta', 'EKLETA', 'ekle']) {
      book.setSearch(query);
      final entries = book.snapshot.entries;
      expect(
        entries.map((entry) => entry.name),
        containsAll([for (final slot in slots) 'Causality Shardstone - $slot']),
      );
      expect(
        entries.where(
          (entry) => acquisitionMethods.contains(entry.recipe.method),
        ),
        isEmpty,
      );
    }
    book.setGroup(ProcessingRecipeGroup.enhancement);
    for (final slot in slots) {
      final name = 'Causality Shardstone - $slot';
      final entry = book.snapshot.entries.singleWhere(
        (entry) => entry.name == name,
      );
      expect(entry.recipe.isCraftable, isTrue);
      expect(entry.processingGroup, ProcessingRecipeGroup.enhancement);
      final formulas = recipeBookFormulas(
        entry.recipe,
        mode: CraftMode.processing,
      );
      expect(formulas, hasLength(2));
      for (final formula in formulas) {
        final batch = formula.batchMultiplier;
        expect(formula.method, 'Heating');
        expect(formula.outputMinimum, batch);
        expect(formula.outputMaximum, batch);
        expect(
          {for (final item in formula.ingredients) item.name: item.quantity},
          {
            'Twilight of the End - $slot': 5 * batch,
            'Caphras Stone': 10 * batch,
            'Magical Shard': 10 * batch,
            'Essence of Dawn': 10 * batch,
            if (batch == 10) 'Black Stone Powder': 1,
          },
        );
        expect(book.canActivateFormula(formula), isTrue);
      }
    }
  });

  test(
    'reforms and quest exchanges stay out of the book, not out of item info',
    () {
      for (final query in [
        '',
        'ekleta',
        'Item Reform',
        'Quest Exchange',
        'Dawnbound Ekleta Necklace',
      ]) {
        book.setSearch(query);
        expect(
          book.snapshot.entries.where(
            (entry) => acquisitionMethods.contains(entry.recipe.method),
          ),
          isEmpty,
        );
      }
      final info = book.itemInfoFor('Dawnbound Ekleta Necklace');
      expect(info?.acquisitionFormulas, isNotEmpty);
      expect(book.activate('Dawnbound Ekleta Necklace'), isNull);
      book.setSearch('Twilight of the End');
      expect(
        book.snapshot.entries.map((entry) => entry.name),
        containsAll([for (final slot in slots) 'Twilight of the End - $slot']),
      );
      book.setSearch('Cup of Destined Dawn');
      expect(
        book.snapshot.entries.map((entry) => entry.name),
        contains('Cup of Destined Dawn'),
      );
    },
  );

  test(
    'Sovereign search and direct Shardstone ingredient searches still work',
    () {
      book.setSearch('sov');
      expect(
        book.snapshot.entries.map((entry) => entry.name),
        containsAll([
          'Primordial Black Stone',
          'Flame of the Primordial',
          'Gem of the Primordial',
        ]),
      );
      book.setSearchByIngredient(true);
      book.setSearch('Twilight of the End - Belt');
      expect(
        book.snapshot.entries.map((entry) => entry.name),
        contains('Causality Shardstone - Belt'),
      );
      book.setSearch('Ekleta Necklace');
      expect(
        book.snapshot.entries.map((entry) => entry.name),
        isNot(contains('Dawnbound Ekleta Necklace')),
      );
    },
  );
}
