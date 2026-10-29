import 'package:bdo_craft_planner_flutter/domain/models/craft_mode.dart';
import 'package:bdo_craft_planner_flutter/features/planner/planner_contracts.dart';
import 'package:bdo_craft_planner_flutter/features/recipe_book/recipe_book_controller.dart';
import 'package:bdo_craft_planner_flutter/features/recipe_book/recipe_book_item_info.dart';
import 'package:bdo_craft_planner_flutter/features/recipe_book/recipe_book_item_info_view.dart';
import 'package:bdo_craft_planner_flutter/visual/visual.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'recipe_book_test_support.dart';

const _used = ValueKey('attached-reference-tab:used');
const _recipe = ValueKey('attached-reference-tab:recipe');
const _art = ValueKey('supplied-reference-art');

void main() {
  late RecipeBookTestEnvironment environment;
  late RecipeBookController book;
  setUp(() {
    environment = buildRecipeBookTestEnvironment(includeRecipeVariants: true);
    book = RecipeBookController(
      modeController: environment.application.active,
      catalogRepository: environment.catalogRepository,
      callingContext: RecipeBookCallingContext.planner,
      allowedTargets: environment.application.active.craftableNames,
    );
  });
  tearDown(() async {
    book.dispose();
    await environment.dispose();
  });

  testWidgets('single recipe stays available and delegates once to its host', (
    tester,
  ) async {
    final formula = recipeBookFormulas(
      environment.application.active.recipeDefinition('Clear Liquid Reagent'),
      mode: CraftMode.alchemy,
    ).last;
    final before = environment.application.active.state.value.toJson();
    final selected = <RecipeBookFormula>[];
    var closed = 0;
    await _pump(
      tester,
      book,
      RecipeBookItemInfo(
        title: formula.outputName,
        kind: 'Reagent',
        summary: '',
        acquisitionFormulas: [formula],
      ),
      onClose: () => closed++,
      onUse: selected.add,
    );
    expect(find.byKey(_used), findsNothing);
    expect(find.text('Use recipe'), findsOneWidget);
    await tester.tap(find.text('Use recipe'));
    await tester.pumpAndSettle();
    expect(selected, [formula]);
    expect(closed, 0);
    expect(environment.application.active.state.value.toJson(), before);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('tabs preserve facts, custom art, copying and alternatives', (
    tester,
  ) async {
    final formulas = recipeBookFormulas(
      environment.application.active.recipeDefinition('Clear Liquid Reagent'),
      mode: CraftMode.alchemy,
    );
    final copied = <String>[];
    await _pump(
      tester,
      book,
      RecipeBookItemInfo(
        title: 'Wild Grass',
        kind: 'Material',
        summary: 'Gathered material.',
        effects: ['A recorded effect.'],
        acquisitionNotes: ['A recorded source.'],
        notes: ['A recorded note.'],
        craftUses: [
          RecipeBookCraftUse(
            output: 'Clear Liquid Reagent',
            formulas: formulas,
          ),
        ],
      ),
      onCopy: copied.add,
    );
    expect(find.byKey(_art), findsOneWidget);
    expect(find.text('Details'), findsOneWidget);
    for (final text in [
      'Gathered material.',
      'A recorded effect.',
      'A recorded source.',
      'A recorded note.',
    ]) {
      expect(find.text(text), findsOneWidget);
    }
    await tester.tap(find.text('Wild Grass'));
    expect(copied, ['Wild Grass']);
    await tester.tap(find.byKey(_used));
    await tester.pumpAndSettle();
    expect(find.text('or 5 Weed'), findsOneWidget);
    expect(find.text('Trace of Earth'), findsNothing);
    await tester.tap(find.text('or 5 Weed'));
    expect(copied, ['Wild Grass', 'Weed']);
    await tester.tap(find.byKey(_recipe));
    await tester.pumpAndSettle();
    expect(find.text('Gathered material.'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('distinct acquisition routes keep distinct usable actions', (
    tester,
  ) async {
    final formulas = recipeBookFormulas(
      environment.application.active.recipeDefinition('Clear Liquid Reagent'),
      mode: CraftMode.alchemy,
    );
    final selected = <RecipeBookFormula>[];
    await _pump(
      tester,
      book,
      RecipeBookItemInfo(
        title: 'Clear Liquid Reagent',
        kind: 'Reagent',
        summary: '',
        acquisitionFormulas: formulas,
      ),
      onUse: selected.add,
    );
    for (final formula in formulas) {
      final action = find.byKey(
        ValueKey(
          'item-info-use-recipe:alchemy:${formula.outputName}:'
          '${formula.variantId ?? 'base'}:${formula.batchMultiplier}',
        ),
      );
      expect(action, findsOneWidget);
      await tester.ensureVisible(action);
      await tester.pumpAndSettle();
      await tester.tap(action);
      await tester.pumpAndSettle();
    }
    expect(selected, formulas);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'short reference has no unnecessary tabs and item change resets selection',
    (tester) async {
      const withUses = RecipeBookItemInfo(
        title: 'Wild Grass',
        kind: 'Material',
        summary: 'First details.',
        uses: ['First use.'],
      );
      await _pump(tester, book, withUses);
      await tester.tap(find.byKey(_used));
      await tester.pumpAndSettle();
      expect(find.text('First use.'), findsOneWidget);
      await _pump(
        tester,
        book,
        const RecipeBookItemInfo(
          title: 'Sunflower',
          kind: 'Material',
          summary: 'Second details.',
        ),
      );
      expect(find.byKey(_used), findsNothing);
      expect(find.byKey(_recipe), findsNothing);
      expect(find.text('Second details.'), findsOneWidget);
      expect(find.text('Use recipe'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  for (final spec in [
    SakuraNightGardenSpec.theme,
    StandardSpec.theme,
    IlluminatedLedgerSpec.theme,
  ]) {
    testWidgets('narrow enlarged pinned content fits ${spec.id}', (
      tester,
    ) async {
      final formulas = recipeBookFormulas(
        environment.application.active.recipeDefinition('Clear Liquid Reagent'),
        mode: CraftMode.alchemy,
      );
      await _pump(
        tester,
        book,
        RecipeBookItemInfo(
          title: 'An unusually long item name with several words',
          kind: 'Alchemy material',
          summary: 'A readable description.',
          acquisitionFormulas: formulas,
          uses: ['Used for another recipe.'],
        ),
        spec: spec,
        width: 320,
        scale: 2,
      );
      expect(tester.takeException(), isNull);
      await tester.tap(find.byKey(_used));
      await tester.pumpAndSettle();
      expect(find.text('Used for another recipe.'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}

Future<void> _pump(
  WidgetTester tester,
  RecipeBookController book,
  RecipeBookItemInfo info, {
  VoidCallback? onClose,
  ValueChanged<String>? onCopy,
  ValueChanged<RecipeBookFormula>? onUse,
  ThemeSpec spec = SakuraNightGardenSpec.theme,
  double width = 480,
  double scale = 1,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(900, 900);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      theme: spec.materialTheme(),
      home: ThemeSpecScope(
        spec: spec,
        child: Scaffold(
          body: Builder(
            builder: (context) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(scale)),
              child: Center(
                child: ItemReferenceCard(
                  controller: book,
                  mode: CraftMode.alchemy,
                  name: info.title,
                  info: info,
                  maxWidth: width,
                  spec: spec,
                  onClose: onClose ?? () {},
                  onCopyItemName: onCopy,
                  onUseFormula: onUse,
                  icon: const SizedBox(key: _art, width: 44, height: 44),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}
