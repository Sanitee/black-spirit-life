import 'package:bdo_craft_planner_flutter/domain/models/craft_mode.dart';
import 'package:bdo_craft_planner_flutter/domain/state/planner_state.dart';
import 'package:bdo_craft_planner_flutter/domain/state/state_copy.dart';
import 'package:bdo_craft_planner_flutter/domain/state/transactions/state_transactions.dart';
import 'package:flutter_test/flutter_test.dart';

import 'state_test_fixture.dart';

void main() {
  const transactions = PlannerStateTransactions();

  group('PlannerStateTransactions.renameItem', () {
    test('atomically migrates every persisted DEC-08 name reference', () {
      final original = buildStateFixture();
      final before = original.toJson();

      final result = transactions.renameItem(
        state: original,
        mode: CraftMode.alchemy,
        oldName: 'Old Item',
        newName: 'Renamed Item',
        existingItemNames: const ['Old Item', 'Safe Item'],
      );

      expect(
        original.toJson(),
        before,
        reason: 'the input must stay immutable',
      );
      final mode = result.state.alchemy;
      expect(mode.target, 'Renamed Item');
      expect(mode.bonusTarget, 'Renamed Item');
      expect(mode.inventory, {'Renamed Item': 8, 'Safe Item': 2});
      expect(mode.recipeEdits, contains('Renamed Item'));
      expect(mode.recipeEdits, isNot(contains('Old Item')));
      final ingredient = mode.recipeEdits['Renamed Item']!.ingredients.single;
      expect(ingredient.options, ['Renamed Item', 'Raw']);
      expect(ingredient.substituteRatios, {'Renamed Item': 2, 'Raw': 1});
      expect(mode.customIcons, contains('Renamed Item'));
      expect(mode.iconAliases, {
        'Renamed Item': 'Alias Target',
        'Alias Source': 'Renamed Item',
      });
      expect(mode.ingredientMeta, contains('Renamed Item'));
      expect(mode.ingredientMeta, isNot(contains('Old Item')));
      expect(mode.ingredientMeta['Quality Child']!.qualityBase, 'Renamed Item');
      expect(mode.favoriteRecipes, {'Renamed Item'});
      expect(mode.hiddenItems, {'Renamed Item'});
      expect(mode.completedSteps, {'Renamed Item'});
      expect(mode.market.prices, {'Renamed Item': 50});
      expect(mode.market.stock, {'Renamed Item': 4});
      expect(mode.market.tradeMarketIds, {
        'Renamed Item': '12345678901234567890',
      });
      expect(mode.market.totalTrades, {'Renamed Item': 1200});
      expect(mode.market.tradeObservedAt, {'Renamed Item': 1700000000000});
      expect(mode.market.observedDailyTrades, {'Renamed Item': 48});
      expect(mode.market.tradeObservationHours, {'Renamed Item': 6});
      expect(mode.market.lastSoldAtEpochSeconds, {'Renamed Item': 1700000000});
      expect(mode.market.unlistedItemNames, {'renamed item', 'second item'});
      expect(mode.market.search, 'Renamed Item');
      expect(mode.market.selected, 'Renamed Item');
      expect(mode.compatibility.done, {'Renamed Item': true});
      expect(mode.compatibility.planSearch, 'Renamed Item');
      expect(mode.substituteChoices, {
        'recipe:Renamed Item:Choice Group': 'Renamed Item',
      });
      expect(mode.ingredientGrades, {
        'recipe:Renamed Item:Renamed Item': 'high',
      });
      expect(mode.recipeVariantChoices, {'Renamed Item': 'preferred-low-cost'});
      expect(
        result.impact.affectedReferences,
        contains('recipeVariantChoices[Old Item]'),
      );
      expect(result.impact.sessionNamesToClear, ['Old Item']);
      expect(result.state.cooking.toJson(), original.cooking.toJson());
      expect(result.state.processing.toJson(), original.processing.toJson());
    });

    test('rejects a collision without changing the source state', () {
      final original = buildStateFixture();
      final before = original.toJson();

      expect(
        () => transactions.renameItem(
          state: original,
          mode: CraftMode.alchemy,
          oldName: 'Old Item',
          newName: 'safe item',
          existingItemNames: const ['Old Item', 'Safe Item'],
        ),
        throwsA(
          isA<StateTransactionFailure>()
              .having((error) => error.code, 'code', 'name-collision')
              .having((error) => error.conflicts, 'conflicts', ['Safe Item']),
        ),
      );
      expect(original.toJson(), before);
    });
  });

  group('PlannerStateTransactions.hideInventoryItem', () {
    test('preserves the complete item definition for reliable restoration', () {
      final fixture = buildStateFixture();
      final original = fixture.copyWith(
        alchemy: fixture.alchemy.copyWith(hiddenItems: const <String>[]),
      );
      final before = original.toJson();

      final result = transactions.hideInventoryItem(
        state: original,
        mode: CraftMode.alchemy,
        itemName: '  Old Item  ',
      );

      expect(original.toJson(), before, reason: 'the input stays immutable');
      expect(result.state.alchemy.hiddenItems, {'Old Item'});
      expect(result.impact.operation, 'hide-inventory-item');
      expect(result.impact.affectedReferences, ['hiddenItems[Old Item]']);
      expect(result.impact.sessionNamesToClear, ['Old Item']);
      expect(
        result.state.alchemy.recipeEdits['Old Item'],
        same(original.alchemy.recipeEdits['Old Item']),
      );
      expect(result.state.alchemy.customIcons, original.alchemy.customIcons);
      expect(
        result.state.alchemy.ingredientMeta,
        original.alchemy.ingredientMeta,
      );

      final restored = result.state.copyWith(
        alchemy: result.state.alchemy.copyWith(hiddenItems: const <String>[]),
      );
      expect(
        restored.toJson(),
        before,
        reason: 'Data > Restore hidden must recover bundled and custom rows',
      );
    });
  });

  group('PlannerStateTransactions.hideRecipeBookItem', () {
    test('keeps recipe and editor data available for later restoration', () {
      final fixture = buildStateFixture();
      final original = fixture.copyWith(
        alchemy: fixture.alchemy.copyWith(hiddenItems: const <String>[]),
      );

      final hidden = transactions.hideRecipeBookItem(
        state: original,
        mode: CraftMode.alchemy,
        itemName: 'Old Item',
        fallbackTarget: 'Safe Item',
      );

      expect(hidden.state.alchemy.hiddenItems, {'Old Item'});
      expect(hidden.state.alchemy.target, 'Safe Item');
      expect(hidden.state.alchemy.bonusTarget, 'Safe Item');
      expect(
        hidden.state.alchemy.recipeEdits['Old Item'],
        same(original.alchemy.recipeEdits['Old Item']),
      );
      expect(hidden.state.alchemy.customIcons, original.alchemy.customIcons);
      expect(
        hidden.state.alchemy.ingredientMeta,
        original.alchemy.ingredientMeta,
      );
      expect(hidden.impact.operation, 'hide-recipe-book-item');

      final restored = transactions.restoreHiddenItems(
        state: hidden.state,
        mode: CraftMode.alchemy,
        itemNames: const <String>['old item'],
      );
      expect(restored.state.alchemy.hiddenItems, isEmpty);
      expect(
        restored.state.alchemy.recipeEdits['Old Item'],
        same(original.alchemy.recipeEdits['Old Item']),
      );
    });
  });

  group('PlannerStateTransactions.restoreHiddenItems', () {
    test('clears legacy bundled tombstones as well as hidden markers', () {
      final fixture = buildStateFixture();
      final legacy = fixture.copyWith(
        alchemy: fixture.alchemy.copyWith(
          hiddenItems: const <String>['Old Item'],
          recipeEdits: <String, RecipeState?>{
            ...fixture.alchemy.recipeEdits,
            'Old Item': null,
          },
        ),
      );

      final result = transactions.restoreHiddenItems(
        state: legacy,
        mode: CraftMode.alchemy,
      );

      expect(result.state.alchemy.hiddenItems, isEmpty);
      expect(result.state.alchemy.recipeEdits, isNot(contains('Old Item')));
      expect(
        result.impact.affectedReferences,
        containsAll(<String>['hiddenItems[Old Item]', 'recipeEdits[Old Item]']),
      );
      expect(result.impact.sessionNamesToClear, ['Old Item']);
    });
  });

  group('PlannerStateTransactions.deleteOrHideItem', () {
    test('hides a bundled item, cleans references, and repairs selections', () {
      final original = buildStateFixture();
      final result = transactions.deleteOrHideItem(
        state: original,
        mode: CraftMode.alchemy,
        itemName: 'Old Item',
        bundledItem: true,
        fallbackTarget: 'Safe Item',
      );

      final mode = result.state.alchemy;
      expect(mode.recipeEdits['Old Item'], isNull);
      expect(mode.hiddenItems, contains('Old Item'));
      expect(mode.target, 'Safe Item');
      expect(mode.bonusTarget, 'Safe Item');
      expect(mode.inventory, {'Safe Item': 2});
      expect(mode.favoriteRecipes, isEmpty);
      expect(mode.completedSteps, isEmpty);
      expect(mode.customIcons, isEmpty);
      expect(mode.iconAliases, isEmpty);
      expect(mode.market.prices, isEmpty);
      expect(mode.market.stock, isEmpty);
      expect(mode.market.tradeMarketIds, isEmpty);
      expect(mode.market.totalTrades, isEmpty);
      expect(mode.market.tradeObservedAt, isEmpty);
      expect(mode.market.observedDailyTrades, isEmpty);
      expect(mode.market.tradeObservationHours, isEmpty);
      expect(mode.market.lastSoldAtEpochSeconds, isEmpty);
      expect(mode.market.unlistedItemNames, const <String>{'second item'});
      expect(mode.market.selected, 'Safe Item');
      expect(mode.market.search, isEmpty);
      expect(mode.compatibility.done, isEmpty);
      expect(mode.compatibility.planSearch, isEmpty);
      expect(mode.substituteChoices, isEmpty);
      expect(mode.ingredientGrades, isEmpty);
      expect(mode.recipeVariantChoices, {'Old Item': 'preferred-low-cost'});
      expect(
        result.impact.affectedReferences,
        isNot(contains('recipeVariantChoices[Old Item]')),
      );
      expect(mode.ingredientMeta, isNot(contains('Old Item')));
      expect(mode.ingredientMeta['Quality Child']!.qualityBase, isNull);
      expect(mode.ingredientMeta['Quality Child']!.sourceNote, 'keep me');
      expect(
        result.impact.iconFilesEligibleForDeletion,
        isEmpty,
        reason: 'the same app-owned icon file is still used by other modes',
      );
      expect(result.impact.sessionNamesToClear, ['Old Item']);
    });

    test('offers an icon file for cleanup only after its final reference', () {
      final original = buildStateFixture();
      final state = original.copyWith(
        cooking: original.cooking.copyWith(customIcons: const {}),
        processing: original.processing.copyWith(customIcons: const {}),
      );

      final result = transactions.deleteOrHideItem(
        state: state,
        mode: CraftMode.alchemy,
        itemName: 'Old Item',
        bundledItem: true,
        fallbackTarget: 'Safe Item',
      );

      expect(result.impact.iconFilesEligibleForDeletion, ['icons/old.png']);
    });

    test('permanent user deletion removes its saved recipe variant', () {
      final result = transactions.deleteOrHideItem(
        state: buildStateFixture(),
        mode: CraftMode.alchemy,
        itemName: 'Old Item',
        bundledItem: false,
        fallbackTarget: 'Safe Item',
      );

      expect(result.state.alchemy.recipeVariantChoices, isEmpty);
      expect(
        result.impact.affectedReferences,
        contains('recipeVariantChoices[Old Item]'),
      );
    });

    test('blocks deletion while another user recipe depends on the item', () {
      final original = buildStateFixture(includeDependentRecipe: true);
      final before = original.toJson();

      expect(
        () => transactions.deleteOrHideItem(
          state: original,
          mode: CraftMode.alchemy,
          itemName: 'Old Item',
          bundledItem: false,
          fallbackTarget: 'Safe Item',
        ),
        throwsA(
          isA<StateTransactionFailure>()
              .having((error) => error.code, 'code', 'dependent-recipes')
              .having((error) => error.conflicts, 'conflicts', ['Dependent']),
        ),
      );
      expect(original.toJson(), before);
    });
  });

  group('custom category transactions', () {
    test(
      'normalizes add and treats case-insensitive duplicates as unchanged',
      () {
        final state = buildStateFixture();
        final duplicate = transactions.addCategory(
          state: state,
          mode: CraftMode.alchemy,
          category: '  custom b  ',
        );
        expect(duplicate.changed, isFalse);
        expect(duplicate.selectedCategory, 'Custom B');
        expect(identical(duplicate.state, state), isTrue);

        final added = transactions.addCategory(
          state: state,
          mode: CraftMode.alchemy,
          category: '  Custom C  ',
        );
        expect(added.changed, isTrue);
        expect(added.selectedCategory, 'Custom C');
        expect(added.state.alchemy.customCategories, [
          'Custom A',
          'Custom B',
          'Custom C',
        ]);
      },
    );

    test('rename migrates metadata and reset removes empty overrides', () {
      final state = buildStateFixture();
      final renamed = transactions.renameCategory(
        state: state,
        mode: CraftMode.alchemy,
        oldCategory: 'Custom B',
        newCategory: 'Custom C',
      );
      expect(renamed.state.alchemy.customCategories, ['Custom A', 'Custom C']);
      for (final name in ['Old Item', 'Quality Child', 'Only Category']) {
        expect(
          renamed.state.alchemy.ingredientMeta[name]!.category,
          'Custom C',
        );
      }

      final reset = transactions.resetCategoryOverrides(
        state: renamed.state,
        mode: CraftMode.alchemy,
        category: 'custom c',
      );
      final metadata = reset.state.alchemy.ingredientMeta;
      expect(metadata, isNot(contains('Only Category')));
      expect(metadata['Old Item']!.category, isNull);
      expect(metadata['Old Item']!.marketId, '12345678901234567890');
      expect(metadata['Quality Child']!.category, isNull);
      expect(metadata['Quality Child']!.sourceNote, 'keep me');
    });
  });
}
