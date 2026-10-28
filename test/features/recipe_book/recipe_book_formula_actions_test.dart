import 'dart:io';

import 'package:bdo_craft_planner_flutter/data/catalog/bundled_catalog_parser.dart';
import 'package:bdo_craft_planner_flutter/domain/models/craft_mode.dart';
import 'package:bdo_craft_planner_flutter/domain/state/state_copy.dart';
import 'package:bdo_craft_planner_flutter/features/planner/planner_contracts.dart';
import 'package:bdo_craft_planner_flutter/features/recipe_book/recipe_book_controller.dart';
import 'package:bdo_craft_planner_flutter/features/recipe_book/recipe_book_item_info.dart';
import 'package:bdo_craft_planner_flutter/features/recipe_book/recipe_book_item_info_view.dart';
import 'package:bdo_craft_planner_flutter/features/shared/mode_item_icon.dart';
import 'package:bdo_craft_planner_flutter/visual/visual.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'recipe_book_test_support.dart';

void main() {
  test('Tenacity formulas preserve workstation, route and batch identity', () {
    final catalog = const BundledCatalogParser().parse(
      File('assets/data/app-data.json').readAsStringSync(),
    );
    final formulas = [
      ...recipeBookFormulas(
        catalog.alchemy.items['Perfume of Tenacity'],
        mode: CraftMode.alchemy,
      ),
      ...recipeBookFormulas(
        catalog.processing.items['Perfume of Tenacity'],
        mode: CraftMode.processing,
      ),
    ];
    expect(
      formulas.map((f) => (f.mode, f.method, f.variantId, f.batchMultiplier)),
      [
        (CraftMode.alchemy, 'Alchemy', null, 1),
        (CraftMode.processing, 'Simple Alchemy', 'standard', 1),
        (CraftMode.processing, 'Simple Alchemy', 'standard-10x', 10),
      ],
    );
    expect(
      formulas.last.ingredients
          .firstWhere((i) => i.name == 'Caphras Essence')
          .quantity,
      100,
    );
    final projected = withVisibleRecipeBookFormulas(
      RecipeBookItemInfo(
        title: 'Perfume of Tenacity',
        kind: 'Perfume',
        summary: '',
        acquisitionFormulas: formulas,
      ),
    );
    final estimated = withEstimatedRecipeBookOutputs(projected, {
      'perfume of tenacity',
    });
    expect(
      estimated.acquisitionFormulas.map(
        (f) => (f.mode, f.variantId, f.routeId, f.batchMultiplier),
      ),
      formulas.map((f) => (f.mode, f.variantId, f.routeId, f.batchMultiplier)),
    );
  });

  testWidgets('Use recipe selects the displayed variant and closes its card', (
    tester,
  ) async {
    final environment = buildRecipeBookTestEnvironment(
      includeRecipeVariants: true,
    );
    addTearDown(environment.dispose);
    final book = _book(environment);
    addTearDown(book.dispose);
    final recipe = environment.application.active.recipeDefinition(
      'Clear Liquid Reagent',
    )!;
    final formula = recipeBookFormulas(recipe, mode: CraftMode.alchemy).last;
    var closed = 0;
    await _pumpCard(tester, book, formula, onClose: () => closed++);
    await tester.tap(_useButton(formula));
    await tester.pumpAndSettle();
    expect(closed, 1);
    expect(environment.application.active.state.value.target, recipe.name);
    expect(
      environment.application.active.state.value.recipeVariantChoices[recipe
          .name],
      'trace-route',
    );
    expect(
      environment.application.active
          .selectedRecipe(recipe.name)!
          .ingredients
          .map((ingredient) => ingredient.name),
      ['Trace of Earth'],
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('formula material icons and activation use its own workstation', (
    tester,
  ) async {
    final environment = buildRecipeBookTestEnvironment();
    addTearDown(environment.dispose);
    final book = _book(environment);
    addTearDown(book.dispose);
    final alchemy = environment.application.active;
    final oldTarget = alchemy.state.value.target;
    final processing = environment.application.modes[CraftMode.processing]!;
    final formula = recipeBookFormulas(
      processing.recipeDefinition('Black Stone Batch 01'),
      mode: CraftMode.processing,
    ).single;
    await _pumpCard(tester, book, formula);
    final materialIcon = tester
        .widgetList<ModeItemIcon>(find.byType(ModeItemIcon))
        .firstWhere((icon) => icon.name == formula.ingredients.first.name);
    expect(materialIcon.controller, same(processing));
    await tester.tap(_useButton(formula));
    await tester.pumpAndSettle();
    expect(environment.application.activeMode.value, CraftMode.processing);
    expect(processing.state.value.target, formula.outputName);
    expect(alchemy.state.value.target, oldTarget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('hidden and unbound formulas do not expose a target action', (
    tester,
  ) async {
    final environment = buildRecipeBookTestEnvironment();
    addTearDown(environment.dispose);
    final book = _book(environment);
    addTearDown(book.dispose);
    final mode = environment.application.active;
    final recipe = mode.recipeDefinition('Clear Liquid Reagent')!;
    final unbound = recipeBookFormulas(recipe).single;
    await _pumpCard(tester, book, unbound);
    expect(find.text('Use recipe'), findsNothing);

    final formula = recipeBookFormulas(recipe, mode: CraftMode.alchemy).single;
    mode.updateState((state) => state.copyWith(hiddenItems: [recipe.name]));
    await _pumpCard(tester, book, formula);
    expect(find.text('Use recipe'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}

RecipeBookController _book(RecipeBookTestEnvironment environment) =>
    RecipeBookController(
      modeController: environment.application.active,
      catalogRepository: environment.catalogRepository,
      callingContext: RecipeBookCallingContext.planner,
      allowedTargets: environment.application.active.craftableNames,
    );

Finder _useButton(RecipeBookFormula formula) => find.byKey(
  ValueKey<String>(
    'item-info-use-recipe:${formula.mode!.key}:${formula.outputName}:'
    '${formula.variantId ?? 'base'}:${formula.batchMultiplier}',
  ),
);

Future<void> _pumpCard(
  WidgetTester tester,
  RecipeBookController book,
  RecipeBookFormula formula, {
  VoidCallback? onClose,
}) async {
  const spec = StandardSpec.theme;
  await tester.pumpWidget(
    MaterialApp(
      theme: spec.materialTheme(),
      home: ThemeSpecScope(
        spec: spec,
        child: Scaffold(
          body: Center(
            child: ItemReferenceCard(
              controller: book,
              mode: CraftMode.alchemy,
              name: formula.outputName,
              info: RecipeBookItemInfo(
                title: formula.outputName,
                kind: 'Recipe',
                summary: '',
                acquisitionFormulas: [formula],
              ),
              maxWidth: 440,
              spec: spec,
              onClose: onClose,
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}
