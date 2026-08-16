import 'package:bdo_craft_planner_flutter/domain/models/craft_mode.dart';
import 'package:bdo_craft_planner_flutter/domain/state/planner_state.dart';
import 'package:bdo_craft_planner_flutter/domain/state/state_copy.dart';
import 'package:bdo_craft_planner_flutter/features/planner/planner_contracts.dart';
import 'package:bdo_craft_planner_flutter/features/recipe_book/recipe_book.dart';
import 'package:bdo_craft_planner_flutter/visual/visual.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../features/recipe_book/recipe_book_test_support.dart';

typedef _ThemeFamily = ({String name, ThemeSpec spec});
typedef _BookFamily = ({String name, CraftMode mode});

void main() {
  const goldenRoot = ValueKey<String>('recipe-book-market-golden-root');
  const sizes = <Size>[Size(1200, 752), Size(1500, 940)];
  const families = <_ThemeFamily>[
    (name: 'standard', spec: StandardSpec.theme),
    (name: 'ledger', spec: IlluminatedLedgerSpec.theme),
    (name: 'sakura', spec: SakuraNightGardenSpec.theme),
  ];
  const books = <_BookFamily>[
    (name: 'processing', mode: CraftMode.processing),
    (name: 'alchemy', mode: CraftMode.alchemy),
  ];

  for (final family in families) {
    for (final bookFamily in books) {
      for (final size in sizes) {
        testWidgets('${family.name} ${bookFamily.name} Recipe Book market layout '
            '${size.width.toInt()}x${size.height.toInt()}', (tester) async {
          tester.view.devicePixelRatio = 1;
          tester.view.physicalSize = size;
          addTearDown(tester.view.resetDevicePixelRatio);
          addTearDown(tester.view.resetPhysicalSize);

          final environment = buildRecipeBookTestEnvironment(
            activeMode: bookFamily.mode,
            showDeleteTools: true,
          );
          final mode = environment.application.modes[bookFamily.mode]!;
          final names = mode.craftableNames.toList()..sort();
          final marketNames = <String>{
            ...names,
            for (final name in names)
              for (final ingredient in mode.recipes[name]!.ingredients)
                ingredient.name,
          }.toList()..sort();
          final processing =
              environment.application.modes[CraftMode.processing]!;
          final hiddenName = (processing.craftableNames.toList()..sort()).first;
          processing.updateState(
            (state) => state.copyWith(
              hiddenItems: <String>[hiddenName],
              recipeEdits: <String, RecipeState?>{
                ...state.recipeEdits,
                hiddenName: null,
              },
            ),
            immediate: true,
          );
          mode.updateState(
            (state) => state.copyWith(
              ingredientMeta: <String, IngredientMetadata>{
                for (var index = 0; index < marketNames.length; index++)
                  marketNames[index]: IngredientMetadata(
                    marketId: '${7000 + index}',
                  ),
              },
            ),
            immediate: true,
          );
          final book = RecipeBookController(
            modeController: mode,
            catalogRepository: environment.catalogRepository,
            callingContext: RecipeBookCallingContext.planner,
            allowedTargets: mode.craftableNames,
            checkPrices: (_) async => PlannerMarketRefresh(
              prices: <String, double>{
                for (var index = 0; index < marketNames.length; index++)
                  marketNames[index]: names.contains(marketNames[index])
                      ? 5000 + index * 1000
                      : 100,
              },
              stock: <String, double>{
                for (var index = 0; index < names.length; index++)
                  names[index]: index % 4 == 0 ? 0 : (index + 1) * 125,
              },
              unlistedItemNames: const <String>{},
              fetchedAt: 42,
              summary: 'Market stock updated.',
            ),
          );
          final marketCheck = book.checkMarket();
          await tester.pump(const Duration(milliseconds: 60));
          await marketCheck;
          book.setProfitableOnly(true);

          await tester.pumpWidget(
            RepaintBoundary(
              key: goldenRoot,
              child: MaterialApp(
                theme: family.spec.materialTheme(),
                home: ThemeSpecScope(
                  spec: family.spec,
                  child: Scaffold(
                    body: RecipeBookModal(
                      controller: book,
                      onClose: () {},
                      onActivated: (_) {},
                    ),
                  ),
                ),
              ),
            ),
          );
          final golden = find.byKey(goldenRoot);
          await _settleGoldenImages(tester, root: golden, spec: family.spec);
          expect(tester.takeException(), isNull);
          await expectLater(
            golden,
            matchesGoldenFile(
              'states/state_${family.name}_${bookFamily.name}_recipe_book_market_'
              '${size.width.toInt()}x${size.height.toInt()}.png',
            ),
          );

          await tester.pumpWidget(const SizedBox.shrink());
          book.dispose();
          await environment.dispose();
        });
      }
    }
  }
}

Future<void> _settleGoldenImages(
  WidgetTester tester, {
  required Finder root,
  required ThemeSpec spec,
}) async {
  await tester.pump();
  final rootElement = tester.element(root);
  if (spec.isSakuraNightGarden) {
    await tester.runAsync(
      () => precacheImage(
        const AssetImage('assets/sakura/materials/charcoal-plum-lacquer.png'),
        rootElement,
      ),
    );
  }
  final imageElements = find
      .descendant(of: root, matching: find.byType(Image))
      .evaluate()
      .toList(growable: false);
  for (final element in imageElements) {
    await tester.runAsync(
      () => precacheImage((element.widget as Image).image, element),
    );
  }
  await tester.pumpAndSettle();
}
