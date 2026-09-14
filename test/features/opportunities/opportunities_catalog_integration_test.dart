import 'dart:io';

import 'package:bdo_craft_planner_flutter/app/planning/planner_assembly.dart';
import 'package:bdo_craft_planner_flutter/data/catalog/bundled_catalog_parser.dart';
import 'package:bdo_craft_planner_flutter/data/catalog/catalog_repository.dart';
import 'package:bdo_craft_planner_flutter/domain/market/market_calculations.dart';
import 'package:bdo_craft_planner_flutter/domain/market/market_price_models.dart';
import 'package:bdo_craft_planner_flutter/domain/models/catalog_models.dart';
import 'package:bdo_craft_planner_flutter/domain/models/craft_mode.dart';
import 'package:bdo_craft_planner_flutter/domain/opportunities/opportunity_calculator.dart';
import 'package:bdo_craft_planner_flutter/domain/opportunities/opportunity_market_models.dart';
import 'package:bdo_craft_planner_flutter/domain/planner/planner_engine.dart';
import 'package:bdo_craft_planner_flutter/domain/planner/planner_models.dart'
    as planning;
import 'package:bdo_craft_planner_flutter/domain/state/planner_state.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const assembly = PlannerAssembly();
  const calculator = OpportunityCalculator();
  final now = DateTime.utc(2026, 9, 8, 17);
  late CatalogSnapshot snapshot;
  late CatalogRepository catalog;
  late planning.PlannerRules rules;

  setUpAll(() {
    snapshot = const BundledCatalogParser().parse(
      File('assets/data/app-data.json').readAsStringSync(),
    );
    catalog = CatalogRepository(snapshot);
    rules = assembly.plannerRules(snapshot.supportingData);
  });

  Map<String, Recipe> assembled(CraftMode mode, ModeState state) =>
      assembly.assembleRecipes(
        catalog: snapshot.forMode(mode),
        state: state,
        supportingData: snapshot.supportingData,
        sharedMetadata: snapshot.alchemy.metadata,
        mode: mode,
      );

  // Fixed market prices are test evidence only. Every recipe, ingredient,
  // variant, NPC price and output bound comes from the production catalog.
  OpportunityMarketSnapshot evidence(Map<String, Recipe> recipes) {
    final ids = <String>{
      for (final recipe in recipes.values.where((recipe) => recipe.isCraftable))
        ...calculator.marketItemIds(
          recipe: recipe,
          recipes: recipes,
          rules: rules,
        ),
    };
    return OpportunityMarketSnapshot(
      region: 'eu',
      items: {
        for (final id in ids)
          id: OpportunityMarketItem(
            itemId: id,
            basePrice: 1000,
            stock: 1000000000,
            quoteFetchedAt: now,
            bookFetchedAt: now,
            asks: const [
              OpportunityMarketLevel(price: 10, quantity: 1000000000),
            ],
            bids: const [
              OpportunityMarketLevel(price: 900, quantity: 1000000000),
            ],
          ),
      },
    );
  }

  for (final mode in CraftMode.values) {
    test(
      '${mode.key}: full catalog discoveries and yields use shared rules',
      () {
        final state = modeState(mode);
        final recipes = assembled(mode, state);
        final market = evidence(recipes);
        final tax = MarketTax(
          valuePack: true,
          merchantRing: true,
          familyFameBonus: .005,
        );
        var checked = 0;
        for (final recipe in recipes.values.where(
          (recipe) => recipe.isCraftable,
        )) {
          final ids = calculator.marketItemIds(
            recipe: recipe,
            recipes: recipes,
            rules: rules,
          );
          expect(
            ids.every((id) => normalizeNumericMarketId(id) == id),
            isTrue,
            reason: recipe.name,
          );
          final names = calculator.marketItemNames(
            recipe: recipe,
            recipes: recipes,
            rules: rules,
          );
          for (final name in names) {
            final id = calculator.marketItemId(
              name: name,
              recipes: recipes,
              rules: rules,
            );
            if (id != null) {
              expect(ids, contains(id), reason: '${recipe.name}: $name');
            }
          }
          final quote = calculator.evaluate(
            recipe: recipe,
            recipes: recipes,
            state: state,
            rules: rules,
            marketTax: tax,
            market: market,
            now: now,
            crafts: 3,
          );
          if (quote.outputPerCraft != null) {
            final formula = recipe.resolveVariant(quote.selectedVariantId);
            final expected = const PlannerEngine().outputPerCraft(
              recipe: formula,
              state: assembly.plannerState(state),
            );
            expect(quote.outputPerCraft, expected, reason: recipe.name);
            expect(quote.expectedOutput, expected * 3, reason: recipe.name);
            if (quote.listingRevenue != null) {
              expect(
                quote.listingRevenue,
                closeTo(expected * 3 * 1000 * marketNetRate(tax), .000001),
                reason: recipe.name,
              );
            }
            if (quote.buyerRevenue != null) {
              expect(
                quote.buyerRevenue,
                closeTo(expected * 3 * 900 * marketNetRate(tax), .000001),
                reason: recipe.name,
              );
            }
            expect(quote.estimatedSeconds, isNull, reason: recipe.name);
          }
          checked++;
        }
        expect(checked, greaterThan(100));
      },
    );
  }

  test(
    'original output and ingredient artwork remains available for discovery',
    () {
      for (final (mode, name) in [
        (CraftMode.cooking, 'Beer'),
        (CraftMode.alchemy, 'Clear Liquid Reagent'),
        (CraftMode.processing, 'Brimming Essence of Aether'),
      ]) {
        final recipe = snapshot.forMode(mode).items[name]!;
        expect(
          catalog.iconDataUriAcrossModes(mode, recipe.name),
          isNotNull,
          reason: name,
        );
        for (final ingredient in recipe.ingredients) {
          expect(
            catalog.iconDataUriAcrossModes(mode, ingredient.name),
            isNotNull,
            reason: ingredient.name,
          );
        }
      }
    },
  );

  test(
    'actual Brimming Essence 1x and10x routes preserve exact total inputs',
    () {
      final state = modeState(CraftMode.processing);
      final recipes = assembled(CraftMode.processing, state);
      final recipe = recipes['Brimming Essence of Aether']!;
      final market = evidence(recipes);
      for (final route in recipe.variantRoutes) {
        final single = route.variantForBatch(1);
        final ten = route.variantForBatch(10);
        if (single == null || ten == null) continue;
        OpportunityQuote quote(String variant, int crafts) =>
            calculator.evaluate(
              recipe: recipe,
              recipes: recipes,
              state: state,
              rules: rules,
              marketTax: MarketTax(valuePack: true),
              market: market,
              now: now,
              selectedVariantId: variant,
              crafts: crafts,
            );
        final small = quote(single.id, 40);
        final bulk = quote(ten.id, 4);
        expect(small.expectedOutput, bulk.expectedOutput);
        expect(bulk.batchMultiplier, 10);
        for (final input in small.ingredients) {
          final other = bulk.ingredients.singleWhere(
            (row) => row.name == input.name,
          );
          expect(
            other.quantity,
            input.quantity,
            reason: '${route.id}: ${input.name}',
          );
        }
        expect(
          bulk.ingredients
              .singleWhere((row) => row.name == 'Black Stone Powder')
              .quantity,
          4,
        );
      }
    },
  );

  test(
    'retired processing yield values cannot enter the opportunity snapshot',
    () {
      final states = {
        for (final mode in CraftMode.values) mode: modeState(mode),
      };
      final persisted = PlannerState(
        applicationVersion: 'opportunities-test',
        lastSuccessfulWriteUtc: now,
        activeMode: CraftMode.processing,
        alchemy: states[CraftMode.alchemy]!,
        cooking: states[CraftMode.cooking]!,
        processing: states[CraftMode.processing]!,
        processingYields: {'defaultYield': 999, 'Simple Alchemy': 999},
        marketTax: MarketTax(valuePack: true),
      );
      final state = persisted.processing;
      final recipes = assembled(CraftMode.processing, state);
      final recipe = recipes['Brimming Essence of Aether']!;
      final quote = calculator.evaluate(
        recipe: recipe,
        recipes: recipes,
        state: state,
        rules: rules,
        marketTax: persisted.marketTax,
        market: evidence(recipes),
        now: now,
      );
      final formula = recipe.resolveVariant(quote.selectedVariantId);
      expect(
        quote.outputPerCraft,
        const PlannerEngine().outputPerCraft(
          recipe: formula,
          state: assembly.plannerState(state),
        ),
      );
      expect(quote.outputPerCraft, isNot(999));
      expect(persisted.processingYields['defaultYield'], 999);
    },
  );

  test(
    'quality IDs discovered through normalized rule names stay in the fetch set',
    () {
      final state = modeState(CraftMode.cooking);
      final recipes = assembled(CraftMode.cooking, state);
      final recipe = recipes['Beer']!;
      final ids = calculator.marketItemIds(
        recipe: recipe,
        recipes: recipes,
        rules: rules,
      );
      for (final name in ['Wheat', 'Special Wheat']) {
        final id = calculator.marketItemId(
          name: name.toUpperCase(),
          recipes: recipes,
          rules: rules,
        );
        expect(id, isNotNull, reason: name);
        expect(ids, contains(id), reason: name);
      }
    },
  );
}

ModeState modeState(CraftMode mode) => ModeState(
  target: mode == CraftMode.cooking
      ? 'Beer'
      : mode == CraftMode.alchemy
      ? 'Clear Liquid Reagent'
      : 'Brimming Essence of Aether',
  bonusTarget: '',
  alchemyMastery: 1550,
  cookingMastery: 2200,
  processingMastery: 3000,
  useMassProcessing: true,
  inventory: {'Wheat': 1000000, 'Sharp Black Crystal Shard': 1000000},
  market: MarketState(),
  appearance: AppearanceSettings.defaultsFor(mode),
);
