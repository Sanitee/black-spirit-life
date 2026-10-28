import 'dart:io';

import 'package:bdo_craft_planner_flutter/app/state/planner_application_controller.dart';
import 'package:bdo_craft_planner_flutter/data/catalog/bundled_catalog_parser.dart';
import 'package:bdo_craft_planner_flutter/domain/models/catalog_models.dart';
import 'package:bdo_craft_planner_flutter/domain/models/craft_mode.dart';
import 'package:bdo_craft_planner_flutter/domain/state/planner_state.dart';
import 'package:bdo_craft_planner_flutter/domain/state/planner_state_json_codec.dart';
import 'package:bdo_craft_planner_flutter/features/planner/planner.dart';
import 'package:bdo_craft_planner_flutter/features/shared/recipe_variant_selector.dart';
import 'package:bdo_craft_planner_flutter/shared/overlays/anchored_popover.dart';
import 'package:bdo_craft_planner_flutter/visual/visual.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _adaptation = 'Adaptation Draught';
const _elixirs = <String>[
  'Elixir of Life',
  'Defense Elixir',
  'Elixir of Endurance',
  'Helix Elixir',
];

void main() {
  late CatalogSnapshot catalog;
  setUpAll(() {
    catalog = const BundledCatalogParser().parse(
      File('assets/data/app-data.json').readAsStringSync(),
    );
  });

  for (final craftMode in [CraftMode.alchemy, CraftMode.processing]) {
    testWidgets(
      'fresh ${craftMode.name} Adaptation batch buttons select the recorded catalyst and persist',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(1500, 940);
        addTearDown(tester.view.reset);
        PlannerState? saved;
        final controller = _controller(
          catalog,
          craftMode: craftMode,
          target: _adaptation,
          inventory: {for (final name in _elixirs) name: 300},
          save: (state) => saved = state,
        );
        addTearDown(controller.dispose);
        final mode = controller.active;
        expect(mode.state.value.recipeVariantChoices, isEmpty);
        expect(mode.recipeRouteSelection(_adaptation)!.hasComparison, isFalse);
        await tester.pumpWidget(_host(controller));
        await tester.pumpAndSettle();
        expect(
          find.byKey(RecipeVariantSelector.automaticChoiceKey(_adaptation)),
          findsNothing,
        );
        expect(
          find.byKey(RecipeVariantSelector.batchChoiceKey(_adaptation, 1)),
          findsNothing,
        );

        void expectFormula(int batch) {
          final catalyst = batch == 100
              ? 'Concentrated Spellbound Catalyst'
              : 'Spellbound Catalyst';
          final step = mode.plan.value.steps.singleWhere(
            (step) => step.name == _adaptation,
          );
          expect(
            mode.selectedRecipeVariantId(_adaptation),
            'simple-alchemy-${batch}x',
          );
          expect(mode.state.value.want, 100);
          expect(step.count, batch == 100 ? 1 : 10);
          expect(step.produced, 100);
          expect(step.demand, 100);
          expect(
            {
              for (final ingredient in step.ingredients)
                ingredient.name: ingredient.need,
            },
            {
              for (final name in _elixirs) name: 300,
              catalyst: batch == 100 ? 10 : 100,
            },
          );
          final need = mode.plan.value.missing.singleWhere(
            (item) => item.name == catalyst,
          );
          expect(need.need, batch == 100 ? 10 : 100);
          expect(
            mode.plan.value.missing.any(
              (item) =>
                  item.name ==
                  (batch == 100
                      ? 'Spellbound Catalyst'
                      : 'Concentrated Spellbound Catalyst'),
            ),
            isFalse,
          );
        }

        expectFormula(10);
        for (final batch in [100, 10, 100]) {
          final button = find.byKey(
            RecipeVariantSelector.batchChoiceKey(_adaptation, batch),
          );
          await tester.ensureVisible(button);
          await tester.tap(button);
          await tester.pumpAndSettle();
          expectFormula(batch);
        }
        mode.replaceMarketValues(
          prices: const {'Elixir of Life': 12345},
          stock: const {'Elixir of Life': 2000},
          unlistedItemNames: const {},
          fetchedAt: 1792764000000,
          region: 'eu',
        );
        await tester.pumpAndSettle();
        expectFormula(100);
        await controller.flush();
        expect(saved, isNotNull);
        const codec = PlannerStateJsonCodec();
        final reloaded = PlannerApplicationController(
          catalog: catalog,
          initialState: codec.decode(codec.encode(saved!)),
          saveState: (state) async => state,
          saveDebounce: Duration.zero,
        );
        addTearDown(reloaded.dispose);
        await tester.pumpWidget(_host(reloaded));
        await tester.pumpAndSettle();
        expect(
          reloaded.active.selectedRecipeVariantId(_adaptation),
          'simple-alchemy-100x',
        );
        expect(reloaded.active.state.value.want, 100);
        final restored = reloaded.active.plan.value.steps.singleWhere(
          (step) => step.name == _adaptation,
        );
        expect(restored.count, 1);
        expect(
          restored.ingredients.last.name,
          'Concentrated Spellbound Catalyst',
        );
        expect(restored.ingredients.last.need, 10);
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final name in ['Black Gem', 'Caphras Stone']) {
    testWidgets('fresh $name supports every recorded batch without Auto', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1500, 940);
      addTearDown(tester.view.reset);
      final recipe = catalog.processing.items[name]!;
      final controller = _controller(
        catalog,
        craftMode: CraftMode.processing,
        target: name,
        inventory: {
          for (final variant in recipe.variants)
            for (final ingredient in variant.ingredients)
              ingredient.name: 100000,
        },
      );
      addTearDown(controller.dispose);
      expect(controller.active.state.value.recipeVariantChoices, isEmpty);
      await tester.pumpWidget(_host(controller));
      await tester.pumpAndSettle();
      for (final batch in [100, 10, 1]) {
        final target = recipe.variants.singleWhere(
          (variant) => variant.batchMultiplier == batch,
        );
        final button = find.byKey(
          RecipeVariantSelector.batchChoiceKey(name, batch),
        );
        await tester.ensureVisible(button);
        await tester.tap(button);
        await tester.pumpAndSettle();
        final mode = controller.active;
        expect(mode.selectedRecipeVariantId(name), target.id);
        expect(mode.state.value.want, 100);
        final step = mode.plan.value.steps.singleWhere(
          (step) => step.name == name,
        );
        final attempts = (100 / target.outputMinimum!).ceil();
        expect(step.count, attempts);
        expect(
          {
            for (final ingredient in step.ingredients)
              ingredient.name: ingredient.need,
          },
          {
            for (final ingredient in target.ingredients)
              ingredient.name: ingredient.quantity * attempts,
          },
        );
      }
      expect(tester.takeException(), isNull);
    });
  }
}

PlannerApplicationController _controller(
  CatalogSnapshot catalog, {
  required CraftMode craftMode,
  required String target,
  required Map<String, double> inventory,
  void Function(PlannerState)? save,
}) {
  ModeState state(CraftMode mode) => ModeState(
    target: target,
    want: 100,
    ignoreIngredientInventory: false,
    bonusTarget: '',
    bonusWant: 1,
    inventory: inventory,
    market: MarketState(),
    appearance: AppearanceSettings.defaultsFor(mode),
  );
  return PlannerApplicationController(
    catalog: catalog,
    initialState: PlannerState(
      applicationVersion: 'test',
      lastSuccessfulWriteUtc: DateTime.utc(2026, 10, 23),
      activeMode: craftMode,
      alchemy: state(CraftMode.alchemy),
      cooking: state(CraftMode.cooking),
      processing: state(CraftMode.processing),
      processingYields: const {},
      marketTax: MarketTax(),
      showDeleteTools: false,
    ),
    saveState: (state) async {
      save?.call(state);
      return state;
    },
    saveDebounce: Duration.zero,
  );
}

Widget _host(PlannerApplicationController controller) {
  final spec = SakuraNightGardenSpec.theme;
  return AppOverlayCoordinatorHost(
    child: MaterialApp(
      theme: spec.materialTheme(),
      home: ThemeSpecScope(
        spec: spec,
        child: Scaffold(
          body: PlannerView(
            controller: controller.active,
            externalActions: PlannerExternalActions(
              openRecipeBook: (_) {},
              copyName: (_) async {},
              checkPrices: (_) async => const PlannerMarketRefresh(
                prices: {},
                stock: {},
                unlistedItemNames: {},
                fetchedAt: 1792764000000,
                summary: 'Test prices',
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
