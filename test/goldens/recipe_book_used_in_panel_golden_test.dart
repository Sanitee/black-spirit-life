import 'package:bdo_craft_planner_flutter/domain/models/craft_mode.dart';
import 'package:bdo_craft_planner_flutter/domain/state/planner_state.dart';
import 'package:bdo_craft_planner_flutter/domain/state/state_copy.dart';
import 'package:bdo_craft_planner_flutter/features/planner/planner_contracts.dart';
import 'package:bdo_craft_planner_flutter/features/recipe_book/recipe_book.dart';
import 'package:bdo_craft_planner_flutter/features/shared/mode_item_icon.dart';
import 'package:bdo_craft_planner_flutter/features/shared/recipe_variant_selector.dart';
import 'package:bdo_craft_planner_flutter/visual/visual.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../features/recipe_book/recipe_book_test_support.dart';

typedef _ThemeFamily = ({String name, ThemeSpec spec});

const String _source = 'Clear Liquid Reagent';
const String _expandedResult = 'Elixir of Life';

void main() {
  const goldenRoot = ValueKey<String>('recipe-book-used-in-panel-golden-root');
  const sizes = <Size>[Size(1200, 752), Size(1500, 940)];
  const families = <_ThemeFamily>[
    (name: 'standard', spec: StandardSpec.theme),
    (name: 'sakura', spec: SakuraNightGardenSpec.theme),
    (name: 'ledger', spec: IlluminatedLedgerSpec.theme),
  ];

  for (final family in families) {
    for (final size in sizes) {
      testWidgets('${family.name} expanded Recipe Book Used In panel '
          '${size.width.toInt()}x${size.height.toInt()}', (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = size;
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetPhysicalSize);

        final environment = buildRecipeBookTestEnvironment(
          includeUsedInVariantFixture: true,
          showDeleteTools: true,
        );
        _configureUsedInConsumers(environment, useVariantFixture: true);
        final mode = environment.application.modes[CraftMode.alchemy]!;
        final book = RecipeBookController(
          modeController: mode,
          catalogRepository: environment.catalogRepository,
          callingContext: RecipeBookCallingContext.planner,
          allowedTargets: mode.craftableNames,
        );

        await tester.pumpWidget(
          RepaintBoundary(
            key: goldenRoot,
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
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

        expect(book.usedInFor(_source).recipeCount, 15);
        final usedInAction = find.byKey(RecipeBookKeys.usedIn(_source));
        expect(usedInAction, findsOneWidget);
        await tester.tap(usedInAction);
        await tester.pumpAndSettle();

        final panel = find.byKey(RecipeBookKeys.usedInPanel(_source));
        expect(panel, findsOneWidget);
        final expand = find.byKey(
          RecipeBookKeys.expandUsedInResult(
            _source,
            CraftMode.alchemy.key,
            _expandedResult,
          ),
        );
        expect(expand, findsOneWidget);
        await tester.tap(expand);
        await _settleGoldenImages(tester, root: golden, spec: family.spec);

        expect(find.text('Used In'), findsOneWidget);
        expect(find.textContaining('15 recipe paths'), findsOneWidget);
        final expandedResult = find.byKey(
          RecipeBookKeys.usedInResult(
            _source,
            CraftMode.alchemy.key,
            _expandedResult,
          ),
        );
        expect(
          find.descendant(
            of: expandedResult,
            matching: find.text('Clear Liquid Reagent'),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(of: expandedResult, matching: find.text('Need 2')),
          findsOneWidget,
        );
        expect(
          find.descendant(of: expandedResult, matching: find.text('Sunflower')),
          findsOneWidget,
        );
        expect(
          find.descendant(of: expandedResult, matching: find.text('Need 3')),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: expandedResult,
            matching: find.text('Makes 1 Elixir of Life'),
          ),
          findsOneWidget,
        );
        const selectorNamespace =
            'used-in:Clear Liquid Reagent:alchemy:Elixir of Life';
        expect(
          find.byKey(
            RecipeVariantSelector.routeChoiceKey(
              _expandedResult,
              'classic',
              keyNamespace: selectorNamespace,
            ),
          ),
          findsOneWidget,
        );
        expect(
          find.byKey(
            RecipeVariantSelector.routeChoiceKey(
              _expandedResult,
              'concentrated',
              keyNamespace: selectorNamespace,
            ),
          ),
          findsOneWidget,
        );
        expect(
          find.byKey(
            RecipeVariantSelector.batchChoiceKey(
              _expandedResult,
              1,
              keyNamespace: selectorNamespace,
            ),
          ),
          findsOneWidget,
        );
        expect(
          find.byKey(
            RecipeVariantSelector.batchChoiceKey(
              _expandedResult,
              10,
              keyNamespace: selectorNamespace,
            ),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: expandedResult,
            matching: find.byType(ModeItemIcon),
          ),
          findsNWidgets(3),
        );
        expect(tester.takeException(), isNull);
        await expectLater(
          golden,
          matchesGoldenFile(
            'states/state_${family.name}_alchemy_recipe_book_used_in_'
            'expanded_${size.width.toInt()}x${size.height.toInt()}.png',
          ),
        );

        const outputAnchorId =
            'used-in:Clear Liquid Reagent:alchemy:Elixir of Life:output';
        final outputAnchor = find.byKey(
          RecipeBookKeys.itemInfoAnchor(_expandedResult, outputAnchorId),
        );
        expect(outputAnchor, findsOneWidget);
        await tester.tap(outputAnchor);
        await _settleGoldenImages(tester, root: golden, spec: family.spec);
        expect(
          find.byKey(
            RecipeBookKeys.pinnedItemInfo(_expandedResult, outputAnchorId),
          ),
          findsOneWidget,
        );
        await expectLater(
          golden,
          matchesGoldenFile(
            'states/state_${family.name}_alchemy_recipe_book_used_in_'
            'item_info_${size.width.toInt()}x${size.height.toInt()}.png',
          ),
        );

        await tester.pumpWidget(const SizedBox.shrink());
        book.dispose();
        await environment.dispose();
      });

      testWidgets('${family.name} Recipe Book ingredient preview '
          '${size.width.toInt()}x${size.height.toInt()}', (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = size;
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetPhysicalSize);

        final environment = buildRecipeBookTestEnvironment();
        final mode = environment.application.modes[CraftMode.alchemy]!;
        final book = RecipeBookController(
          modeController: mode,
          catalogRepository: environment.catalogRepository,
          callingContext: RecipeBookCallingContext.planner,
          allowedTargets: mode.craftableNames,
        );

        await tester.pumpWidget(
          RepaintBoundary(
            key: goldenRoot,
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
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

        final recipe = book.recipeFor(_source)!;
        await tester.tap(find.byKey(RecipeBookKeys.r13Details(_source)));
        await _settleGoldenImages(tester, root: golden, spec: family.spec);

        final preview = find.byKey(RecipeBookKeys.previewPanel);
        expect(preview, findsOneWidget);
        expect(
          find.descendant(
            of: preview,
            matching: find.byWidgetPredicate(
              (widget) =>
                  widget is Text && (widget.data?.startsWith('Need ') ?? false),
            ),
          ),
          findsNWidgets(recipe.ingredients.length),
        );
        for (final ingredient in recipe.ingredients) {
          expect(
            find.byKey(
              RecipeBookKeys.previewQuantity(_source, ingredient.name),
            ),
            findsNothing,
          );
        }
        expect(tester.takeException(), isNull);
        await expectLater(
          golden,
          matchesGoldenFile(
            'states/state_${family.name}_alchemy_recipe_book_preview_'
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

void _configureUsedInConsumers(
  RecipeBookTestEnvironment environment, {
  bool useVariantFixture = false,
}) {
  final alchemy = environment.application.modes[CraftMode.alchemy]!;
  alchemy.updateState(
    (state) => state.copyWith(
      recipeEdits: <String, RecipeState?>{
        ...state.recipeEdits,
        if (!useVariantFixture)
          _expandedResult: _consumer(
            CraftMode.alchemy,
            quantity: 2,
            secondaryName: 'Sunflower',
            secondaryQuantity: 3,
          ),
        'Pure Powder Reagent': _consumer(
          CraftMode.alchemy,
          secondaryName: 'Trace of Earth',
        ),
      },
    ),
    immediate: true,
  );

  final cooking = environment.application.modes[CraftMode.cooking]!;
  cooking.updateState(
    (state) => state.copyWith(
      recipeEdits: <String, RecipeState?>{
        ...state.recipeEdits,
        for (final name in const <String>[
          'Beer',
          'Grilled Bird Meat',
          'Pickled Vegetables',
        ])
          name: _consumer(
            CraftMode.cooking,
            secondaryName: 'Cooking Ingredient',
          ),
      },
    ),
    immediate: true,
  );

  final processing = environment.application.modes[CraftMode.processing]!;
  final processingConsumers = processing.craftableNames.take(10).toList();
  processing.updateState(
    (state) => state.copyWith(
      recipeEdits: <String, RecipeState?>{
        ...state.recipeEdits,
        for (var index = 0; index < processingConsumers.length; index++)
          processingConsumers[index]: _consumer(
            CraftMode.processing,
            quantity: (index + 1).toDouble(),
          ),
      },
    ),
    immediate: true,
  );
}

RecipeState _consumer(
  CraftMode mode, {
  double quantity = 1,
  String? secondaryName,
  double secondaryQuantity = 1,
}) => RecipeState(
  type: mode.key,
  baseOutput: 1,
  group: '${mode.label} recipes',
  method: switch (mode) {
    CraftMode.alchemy => 'Alchemy',
    CraftMode.cooking => 'Cooking',
    CraftMode.processing => 'Heating',
  },
  ingredients: <IngredientState>[
    IngredientState(name: _source, quantity: quantity),
    if (secondaryName != null)
      IngredientState(name: secondaryName, quantity: secondaryQuantity),
  ],
  outputMinimum: 1,
  outputMaximum: 1,
);

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
