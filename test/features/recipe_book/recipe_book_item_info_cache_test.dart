import 'package:bdo_craft_planner_flutter/domain/models/craft_mode.dart';
import 'package:bdo_craft_planner_flutter/domain/state/planner_state.dart';
import 'package:bdo_craft_planner_flutter/domain/state/state_copy.dart';
import 'package:bdo_craft_planner_flutter/features/planner/planner_contracts.dart';
import 'package:bdo_craft_planner_flutter/features/recipe_book/recipe_book_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import 'recipe_book_test_support.dart';

void main() {
  test(
    'shared item info reuses results through unrelated state changes',
    () async {
      final environment = buildRecipeBookTestEnvironment();
      addTearDown(environment.dispose);
      final mode = environment.application.active;
      final book = RecipeBookController(
        modeController: mode,
        catalogRepository: environment.catalogRepository,
        callingContext: RecipeBookCallingContext.planner,
        allowedTargets: const [],
      );
      addTearDown(book.dispose);
      final before = book.itemInfoFor('Clear Liquid Reagent');
      expect(before, isNotNull);
      expect(book.itemInfoFor('Clear Liquid Reagent'), same(before));
      mode.toggleFavorite('Clear Liquid Reagent');
      mode.updateState(
        (s) => s.copyWith(market: s.market.copyWith(fetchedAt: 2500)),
      );
      expect(book.itemInfoFor('Clear Liquid Reagent'), same(before));
      final otherMode = book.itemInfoFor(
        'Clear Liquid Reagent',
        mode: CraftMode.processing,
      );
      expect(otherMode, isNotNull);
      expect(
        book.itemInfoFor('Clear Liquid Reagent', mode: CraftMode.processing),
        same(otherMode),
      );
    },
  );

  test(
    'cross-mode metadata changes invalidate researched item information immediately',
    () async {
      final environment = buildRecipeBookTestEnvironment(
        activeMode: CraftMode.processing,
      );
      addTearDown(environment.dispose);
      final book = RecipeBookController(
        modeController: environment.application.active,
        catalogRepository: environment.catalogRepository,
        callingContext: RecipeBookCallingContext.planner,
        allowedTargets: const [],
      );
      addTearDown(book.dispose);
      final before = book.itemInfoFor('Clear Liquid Reagent');
      environment.application.modes[CraftMode.alchemy]!.updateState(
        (s) => s.copyWith(
          ingredientMeta: {
            ...s.ingredientMeta,
            'Clear Liquid Reagent': IngredientMetadata(
              sourceNote: 'My source note',
            ),
          },
        ),
      );
      final after = book.itemInfoFor('Clear Liquid Reagent');
      expect(after, isNot(same(before)));
      expect(after!.acquisitionNotes.join(' '), contains('My source note'));
      expect(book.itemInfoFor('Clear Liquid Reagent'), same(after));
    },
  );

  test(
    'cached unknown reference gains its formula after a real recipe edit',
    () async {
      final environment = buildRecipeBookTestEnvironment();
      addTearDown(environment.dispose);
      final mode = environment.application.active;
      final book = RecipeBookController(
        modeController: mode,
        catalogRepository: environment.catalogRepository,
        callingContext: RecipeBookCallingContext.planner,
        allowedTargets: const [],
      );
      addTearDown(book.dispose);
      const name = 'New custom reagent';
      final before = book.itemInfoFor(name)!;
      expect(before.acquisitionFormulas, isEmpty);
      mode.updateState(
        (s) => s.copyWith(
          recipeEdits: {
            ...s.recipeEdits,
            name: RecipeState(
              type: 'alchemy',
              baseOutput: 1,
              ingredients: [IngredientState(name: 'Sunflower', quantity: 2)],
            ),
          },
        ),
      );
      final after = book.itemInfoFor(name)!;
      expect(after, isNot(same(before)));
      expect(after.acquisitionFormulas, isNotEmpty);
    },
  );

  test(
    'item info cache is bounded and eviction does not change facts',
    () async {
      final environment = buildRecipeBookTestEnvironment();
      addTearDown(environment.dispose);
      final book = RecipeBookController(
        modeController: environment.application.active,
        catalogRepository: environment.catalogRepository,
        callingContext: RecipeBookCallingContext.planner,
        allowedTargets: const [],
      );
      addTearDown(book.dispose);
      final before = book.itemInfoFor('Clear Liquid Reagent')!;
      for (var i = 0; i < 520; i++) {
        book.itemInfoFor('Unknown cache probe $i');
      }
      final after = book.itemInfoFor('Clear Liquid Reagent')!;
      expect(after, isNot(same(before)));
      expect(after.title, before.title);
      expect(after.summary, before.summary);
      expect(
        after.acquisitionFormulas.map((f) => f.outputName),
        before.acquisitionFormulas.map((f) => f.outputName),
      );
    },
  );
}
