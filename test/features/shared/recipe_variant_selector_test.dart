import 'package:bdo_craft_planner_flutter/domain/models/catalog_models.dart';
import 'package:bdo_craft_planner_flutter/features/shared/recipe_variant_selector.dart';
import 'package:bdo_craft_planner_flutter/visual/components/app_button.dart';
import 'package:bdo_craft_planner_flutter/visual/components/app_form_controls.dart';
import 'package:bdo_craft_planner_flutter/visual/foundations/theme_spec.dart';
import 'package:bdo_craft_planner_flutter/visual/standard/standard_spec.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final size in const <Size>[Size(1200, 752), Size(1500, 940)]) {
    testWidgets(
      'route and batch controls stay independent at ${size.width.toInt()}x'
      '${size.height.toInt()}',
      (tester) async {
        await tester.binding.setSurfaceSize(size);
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final recipe = _matrixRecipe();
        var selectedId = 'a-100x';

        await tester.pumpWidget(
          _host(
            StatefulBuilder(
              builder: (context, setState) => RecipeVariantSelector(
                recipe: recipe,
                selectedVariantId: selectedId,
                onSelected: (value) => setState(() => selectedId = value),
              ),
            ),
          ),
        );

        expect(
          find.byKey(
            RecipeVariantSelector.routeChoiceKey(recipe.name, 'route-a'),
          ),
          findsOneWidget,
        );
        expect(
          find.byKey(
            RecipeVariantSelector.routeChoiceKey(recipe.name, 'route-b'),
          ),
          findsOneWidget,
        );
        for (final batch in const <int>[1, 10, 100]) {
          expect(
            find.byKey(
              RecipeVariantSelector.batchChoiceKey(recipe.name, batch),
            ),
            findsOneWidget,
          );
        }
        expect(find.text('RECIPE'), findsOneWidget);
        expect(find.text('BATCH'), findsOneWidget);

        await tester.tap(
          find.byKey(
            RecipeVariantSelector.routeChoiceKey(recipe.name, 'route-b'),
          ),
        );
        await tester.pumpAndSettle();
        expect(selectedId, 'b-1x');

        final unsupported = tester.widget<AppButton>(
          find.descendant(
            of: find.byKey(
              RecipeVariantSelector.batchChoiceKey(recipe.name, 100),
            ),
            matching: find.byType(AppButton),
          ),
        );
        expect(unsupported.onPressed, isNull);

        await tester.tap(
          find.byKey(RecipeVariantSelector.batchChoiceKey(recipe.name, 10)),
        );
        await tester.pumpAndSettle();
        expect(selectedId, 'b-10x');

        await tester.tap(
          find.byKey(
            RecipeVariantSelector.routeChoiceKey(recipe.name, 'route-a'),
          ),
        );
        await tester.pumpAndSettle();
        expect(selectedId, 'a-10x');
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('compact recipe and batch groups keep a visible gap', (
    tester,
  ) async {
    final recipe = _matrixRecipe();
    await tester.pumpWidget(
      _host(
        RecipeVariantSelector(
          recipe: recipe,
          selectedVariantId: 'a-1x',
          compact: true,
          axisSpacing: 13,
          onSelected: (_) {},
        ),
      ),
    );

    final lastRecipeChoice = tester.getRect(
      find.byKey(RecipeVariantSelector.routeChoiceKey(recipe.name, 'route-b')),
    );
    final batchLabel = tester.getRect(find.text('BATCH'));

    expect(batchLabel.left - lastRecipeChoice.right, greaterThanOrEqualTo(13));
  });

  testWidgets(
    'a lone filtered formula keeps its original route and batch identity',
    (tester) async {
      final recipe = _matrixRecipe();
      const namespace = 'used-in:filtered';

      await tester.pumpWidget(
        _host(
          RecipeVariantSelector(
            recipe: recipe,
            selectedVariantId: 'b-10x',
            allowedVariantIds: const <String>{'b-10x'},
            showSingleAllowedIdentity: true,
            keyNamespace: namespace,
            onSelected: (_) {},
          ),
        ),
      );

      final route = find.byKey(
        RecipeVariantSelector.routeChoiceKey(
          recipe.name,
          'route-b',
          keyNamespace: namespace,
        ),
      );
      final batch = find.byKey(
        RecipeVariantSelector.batchChoiceKey(
          recipe.name,
          10,
          keyNamespace: namespace,
        ),
      );
      expect(route, findsOneWidget);
      expect(
        find.descendant(of: route, matching: find.text('B')),
        findsOneWidget,
      );
      expect(batch, findsOneWidget);
      expect(find.text('RECIPE'), findsOneWidget);
      expect(find.text('BATCH'), findsOneWidget);
      expect(
        find.byKey(
          RecipeVariantSelector.routeChoiceKey(
            recipe.name,
            'route-a',
            keyNamespace: namespace,
          ),
        ),
        findsNothing,
      );
      expect(
        find.byKey(
          RecipeVariantSelector.batchChoiceKey(
            recipe.name,
            1,
            keyNamespace: namespace,
          ),
        ),
        findsNothing,
      );
    },
  );

  testWidgets(
    'filtered route and batch axes disable unavailable combinations',
    (tester) async {
      final recipe = _matrixRecipe();
      const namespace = 'used-in:missing-combination';
      var selectedId = 'a-1x';

      await tester.pumpWidget(
        _host(
          StatefulBuilder(
            builder: (context, setState) => RecipeVariantSelector(
              recipe: recipe,
              selectedVariantId: selectedId,
              allowedVariantIds: const <String>{'a-1x', 'b-10x'},
              keyNamespace: namespace,
              onSelected: (value) => setState(() => selectedId = value),
            ),
          ),
        ),
      );

      Finder batch(int multiplier) => find.byKey(
        RecipeVariantSelector.batchChoiceKey(
          recipe.name,
          multiplier,
          keyNamespace: namespace,
        ),
      );
      AppButton button(Finder owner) => tester.widget<AppButton>(
        find.descendant(of: owner, matching: find.byType(AppButton)),
      );

      expect(button(batch(10)).onPressed, isNull);
      expect(
        tester
            .widget<Tooltip>(
              find.descendant(of: batch(10), matching: find.byType(Tooltip)),
            )
            .message,
        contains('No matching 10× formula'),
      );

      await tester.tap(
        find.byKey(
          RecipeVariantSelector.routeChoiceKey(
            recipe.name,
            'route-b',
            keyNamespace: namespace,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(selectedId, 'b-10x');
      expect(button(batch(1)).onPressed, isNull);
      expect(button(batch(10)).onPressed, isNotNull);
    },
  );

  testWidgets('batch-only recipes do not show a redundant route control', (
    tester,
  ) async {
    final recipe = _recipe(
      variants: <RecipeVariant>[
        _variant(
          id: 'standard',
          label: 'Standard',
          routeId: 'standard',
          ingredients: <Ingredient>[_ingredient('Raw', 1)],
        ),
        _variant(
          id: 'standard-10x',
          label: 'Standard',
          routeId: 'standard',
          batchMultiplier: 10,
          baseOutput: 4,
          output: 10,
          ingredients: <Ingredient>[_ingredient('Raw', 10)],
        ),
      ],
    );

    await tester.pumpWidget(
      _host(
        RecipeVariantSelector(
          recipe: recipe,
          selectedVariantId: 'standard',
          onSelected: (_) {},
        ),
      ),
    );

    expect(find.text('RECIPE'), findsNothing);
    expect(find.text('BATCH'), findsOneWidget);
  });

  testWidgets(
    'six-route selector widens its closed control for the complete route name',
    (tester) async {
      const selectedLabel = 'F - Cheetah Dragon Blood Preparation';
      final recipe = _recipe(
        variants: <RecipeVariant>[
          for (var index = 0; index < 6; index += 1)
            _variant(
              id: 'route-$index',
              label: index == 5
                  ? 'Cheetah Dragon Blood Preparation'
                  : 'Route ${index + 1}',
              routeId: 'route-$index',
              ingredients: <Ingredient>[_ingredient('Raw', 1)],
            ),
        ],
      );

      await tester.pumpWidget(
        _host(
          RecipeVariantSelector(
            recipe: recipe,
            selectedVariantId: 'route-5',
            onSelected: (_) {},
          ),
        ),
      );

      final anchor = find.byKey(AppSelect.anchorMaterialKey);
      expect(anchor, findsOneWidget);
      expect(tester.getSize(anchor).width, greaterThan(180));
      final label = find.descendant(
        of: anchor,
        matching: find.text(selectedLabel),
      );
      expect(label, findsOneWidget);
      final paragraph = tester.renderObject<RenderParagraph>(label);
      expect(paragraph.didExceedMaxLines, isFalse);
      expect(paragraph.text.style?.fontSize, isNot(lessThan(12)));
      expect(tester.takeException(), isNull);
    },
  );
}

Widget _host(Widget child) => MaterialApp(
  theme: StandardSpec.theme.materialTheme(),
  home: ThemeSpecScope(
    spec: StandardSpec.theme,
    child: StandardVisualScope(
      settings: StandardVisualSettings.fallback,
      child: Scaffold(body: Center(child: child)),
    ),
  ),
);

Recipe _matrixRecipe() => _recipe(
  variants: <RecipeVariant>[
    _variant(
      id: 'a-1x',
      label: 'Raw Materials',
      routeId: 'route-a',
      ingredients: <Ingredient>[_ingredient('Raw', 1)],
    ),
    _variant(
      id: 'a-10x',
      label: 'Raw Materials',
      routeId: 'route-a',
      batchMultiplier: 10,
      baseOutput: 4,
      output: 10,
      ingredients: <Ingredient>[_ingredient('Raw', 10)],
    ),
    _variant(
      id: 'a-100x',
      label: 'Raw Materials',
      routeId: 'route-a',
      batchMultiplier: 100,
      baseOutput: 40,
      output: 100,
      ingredients: <Ingredient>[_ingredient('Raw', 100)],
    ),
    _variant(
      id: 'b-1x',
      label: 'Prepared',
      routeId: 'route-b',
      ingredients: <Ingredient>[_ingredient('Prepared', 1)],
    ),
    _variant(
      id: 'b-10x',
      label: 'Prepared',
      routeId: 'route-b',
      batchMultiplier: 10,
      baseOutput: 4,
      output: 10,
      ingredients: <Ingredient>[_ingredient('Prepared', 10)],
    ),
  ],
);

Recipe _recipe({required List<RecipeVariant> variants}) => Recipe(
  name: 'Matrix Output',
  type: 'processing',
  baseOutput: 0.4,
  group: null,
  method: 'Heating',
  ingredients: variants.first.ingredients,
  marketId: null,
  sourceNote: null,
  vendor: null,
  location: null,
  npcPrice: 0,
  qualityBase: null,
  qualityGrade: null,
  outputMinimum: 1,
  outputMaximum: 1,
  variants: variants,
  defaultVariantId: variants.first.id,
);

RecipeVariant _variant({
  required String id,
  required String label,
  required String routeId,
  required List<Ingredient> ingredients,
  int batchMultiplier = 1,
  double baseOutput = 0.4,
  double output = 1,
}) => RecipeVariant(
  id: id,
  label: label,
  routeId: routeId,
  batchMultiplier: batchMultiplier,
  type: 'processing',
  baseOutput: baseOutput,
  method: 'Heating',
  ingredients: ingredients,
  outputMinimum: output,
  outputMaximum: output,
);

Ingredient _ingredient(String name, double quantity) => Ingredient(
  name: name,
  quantity: quantity,
  options: const <String>[],
  substituteGroup: null,
  substituteRatios: const <String, double>{},
);
