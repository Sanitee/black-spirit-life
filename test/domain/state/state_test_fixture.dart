import 'package:bdo_craft_planner_flutter/domain/models/craft_mode.dart';
import 'package:bdo_craft_planner_flutter/domain/state/planner_state.dart';

PlannerState buildStateFixture({bool includeDependentRecipe = false}) {
  ModeState mode(CraftMode craftMode) {
    final recipeType = switch (craftMode) {
      CraftMode.alchemy => 'alchemy',
      CraftMode.cooking => 'cooking',
      CraftMode.processing => 'processing',
    };
    final oldRecipe = RecipeState(
      type: recipeType,
      baseOutput: 2,
      marketId: '9007199254740991',
      ingredients: [
        IngredientState(
          name: 'Raw',
          quantity: 3,
          options: const ['Old Item', 'Raw'],
          substituteGroup: 'Choice Group',
          substituteRatios: const {'Old Item': 2, 'Raw': 1},
          extensions: const {'ingredientFuture': true},
        ),
      ],
      extensions: const {'recipeFuture': 'kept'},
    );
    final edits = <String, RecipeState?>{'Old Item': oldRecipe};
    if (includeDependentRecipe) {
      edits['Dependent'] = RecipeState(
        type: recipeType,
        ingredients: [IngredientState(name: 'Old Item', quantity: 1)],
      );
    }
    return ModeState(
      target: 'Old Item',
      want: 17,
      bonusTarget: 'Old Item',
      bonusWant: 9,
      inventory: const {'Old Item': 8, 'Safe Item': 2},
      view: 'appearance',
      recipeEdits: edits,
      iconAliases: const {
        'Old Item': 'Alias Target',
        'Alias Source': 'Old Item',
      },
      customIcons: const {
        'Old Item': CustomIconReference(
          relativePath: 'icons/old.png',
          sha256:
              'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA',
          mediaType: 'image/png',
          byteCount: 128,
          width: 32,
          height: 32,
        ),
      },
      ingredientMeta: {
        'Old Item': IngredientMetadata(
          category: 'Custom B',
          marketId: '12345678901234567890',
          extensions: const {'metaFuture': 1},
        ),
        'Quality Child': IngredientMetadata(
          category: 'Custom B',
          qualityBase: 'Old Item',
          sourceNote: 'keep me',
        ),
        'Only Category': IngredientMetadata(category: 'Custom B'),
      },
      customCategories: const ['Custom A', 'Custom B'],
      substituteChoices: const {'recipe:Old Item:Choice Group': 'Old Item'},
      ingredientGrades: const {'recipe:Old Item:Old Item': 'high'},
      recipeVariantChoices: const {'Old Item': 'preferred-low-cost'},
      favoriteRecipes: const ['Old Item'],
      hiddenItems: const ['Old Item'],
      bookFavoritesOnly: true,
      bookSearchIngredients: true,
      market: MarketState(
        prices: const {'Old Item': 50},
        stock: const {'Old Item': 4},
        tradeMarketIds: const {'Old Item': '12345678901234567890'},
        totalTrades: const {'Old Item': 1200},
        tradeObservedAt: const {'Old Item': 1700000000000},
        observedDailyTrades: const {'Old Item': 48},
        tradeObservationHours: const {'Old Item': 6},
        lastSoldAtEpochSeconds: const {'Old Item': 1700000000},
        unlistedItemNames: const {' Old Item ', 'SECOND ITEM'},
        search: 'Old Item',
        selected: 'Old Item',
        fetchedAt: 1234,
      ),
      appearance: AppearanceSettings.defaultsFor(craftMode),
      ignoreTargetInventory: false,
      ignoreIngredientInventory: false,
      alchemyMastery: 50,
      cookingMastery: 60,
      processingMastery: craftMode == CraftMode.processing ? 20 : 0,
      useMassProcessing: true,
      completedSteps: const ['Old Item'],
      afkCraftProgress: {
        'Old%20Item': AfkCraftProgress(
          stepKey: 'Old%20Item',
          targetName: 'Old Item',
          targetAmount: 17,
          recipeName: 'Old Item',
          planSignature: 'old-item:v1:normal',
          totalAttempts: 17,
          attemptsPerRound: 6,
          completedAttempts: 12,
          extensions: const {'progressFuture': true},
        ),
      },
      compatibility: LegacyModeState(
        done: const {'Old Item': true},
        planSearch: 'Old Item',
        bookSearchRelatedItems: true,
        alchemyYield: 2.75,
        extensions: const {'legacyFuture': 'yes'},
      ),
      extensions: const {
        'modeFuture': {'enabled': true},
      },
    );
  }

  return PlannerState(
    applicationVersion: '1.0.0+1',
    lastSuccessfulWriteUtc: DateTime.utc(2026, 7, 20, 12),
    origin: MigrationOrigin(
      sourceKind: 'synthetic',
      sourceVersion: 1,
      sourceModeVersions: const {
        CraftMode.alchemy: 1,
        CraftMode.cooking: 1,
        CraftMode.processing: 1,
      },
      sourceSha256:
          'BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB',
      sourceByteCount: 100,
      migratedAtUtc: DateTime.utc(2026, 7, 20, 11),
      archiveRelativePath: 'Migration/source.json',
    ),
    activeMode: CraftMode.alchemy,
    alchemy: mode(CraftMode.alchemy),
    cooking: mode(CraftMode.cooking),
    processing: mode(CraftMode.processing),
    processingYields: const {
      'defaultYield': 2.5,
      'Shaking': 0,
      'Grinding': 3,
      'Chopping': 0,
      'Drying': 0,
      'Heating': 0,
      'Filtering': 0,
      'Thinning': 0,
      'Simple Alchemy': 0,
      'Simple Cooking': 0,
      'Other': 1.25,
    },
    marketTax: MarketTax(
      valuePack: true,
      familyFameBonus: .01,
      extensions: const {'taxFuture': true},
    ),
    afkWeightProfile: AfkWeightProfile(
      maximumWeightLt: 1625.5,
      currentCarriedWeightLt: 137.25,
      safetyBufferLt: 25,
      featheryStepsLevel: 4,
      extensions: const {'weightFuture': true},
    ),
    extensions: const {
      'rootFuture': [1, 2],
    },
  );
}
