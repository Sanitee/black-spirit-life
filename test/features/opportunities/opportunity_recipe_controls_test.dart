import 'package:bdo_craft_planner_flutter/domain/models/catalog_models.dart';
import 'package:bdo_craft_planner_flutter/domain/opportunities/opportunity_recipe_routes.dart';
import 'package:bdo_craft_planner_flutter/features/opportunities/opportunities_theme.dart';
import 'package:bdo_craft_planner_flutter/features/opportunities/opportunity_recipe_controls.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../domain/opportunities/opportunity_calculator_test.dart' as fixture;

void main() {
  for (final width in [320.0, 560.0, 1120.0]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('recipe controls wrap at $width with text $scale', (
        tester,
      ) async {
        tester.view.physicalSize = const Size(1400, 1200);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        RecipeVariant variant(String route, int batch) => RecipeVariant(
          id: '$route-$batch',
          label: route,
          type: 'processing',
          baseOutput: 1,
          method: 'Simple Alchemy',
          routeId: route,
          batchMultiplier: batch,
          ingredients: [
            fixture.ingredient('$route ingredient', batch.toDouble()),
          ],
          outputMinimum: batch.toDouble(),
          outputMaximum: batch.toDouble(),
        );
        final recipe = fixture.recipe(
          'Product',
          variants: [
            for (final route in ['a', 'b', 'c'])
              for (final batch in [1, 10, 100]) variant(route, batch),
          ],
        );
        final routes = opportunityRecipeRoutes([recipe]);
        OpportunityRecipeFormula? selected;
        await tester.pumpWidget(
          MaterialApp(
            home: MediaQuery(
              data: MediaQueryData(textScaler: TextScaler.linear(scale)),
              child: OpportunitiesTheme(
                child: Align(
                  alignment: Alignment.topLeft,
                  child: SizedBox(
                    width: width,
                    child: OpportunityRecipeControls(
                      routes: routes,
                      recipe: recipe,
                      variantId: 'a-10',
                      onSelected: (formula) => selected = formula,
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final recipeB = find.byKey(
          const ValueKey('opportunity-recipe-route:1'),
        );
        final batch = find.byKey(
          const ValueKey('opportunity-recipe-batch:100'),
        );
        expect(tester.getSize(recipeB).height, tester.getSize(batch).height);
        for (final label in [
          'Recipe A',
          'Recipe B',
          'Recipe C',
          '1×',
          '10×',
          '100×',
        ]) {
          final bounds = tester.getRect(find.text(label));
          expect(bounds.left, greaterThanOrEqualTo(0));
          expect(bounds.right, lessThanOrEqualTo(width));
        }
        await tester.tap(recipeB);
        expect(selected!.variantId, 'b-10');
        await tester.tap(batch);
        expect(selected!.variantId, 'a-100');
        expect(tester.takeException(), isNull);
      });
    }
  }
}
