import 'package:bdo_craft_planner_flutter/domain/models/craft_mode.dart';
import 'package:bdo_craft_planner_flutter/features/planner/planner_contracts.dart';
import 'package:bdo_craft_planner_flutter/features/recipe_book/recipe_book_controller.dart';
import 'package:bdo_craft_planner_flutter/features/recipe_book/recipe_book_item_info.dart';
import 'package:bdo_craft_planner_flutter/features/recipe_book/recipe_book_item_info_view.dart';
import 'package:bdo_craft_planner_flutter/features/recipe_book/recipe_book_keys.dart';
import 'package:bdo_craft_planner_flutter/features/shared/source_availability_badges.dart';
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

  for (final spec in [
    SakuraNightGardenSpec.theme,
    StandardSpec.theme,
    IlluminatedLedgerSpec.theme,
  ]) {
    for (final host in ['clicked', 'passive', 'inline']) {
      testWidgets(
        '$host reference owns ${spec.id} for all descendants despite another ambient theme',
        (tester) async {
          final ambient = spec.isStandard
              ? SakuraNightGardenSpec.theme
              : StandardSpec.theme;
          const info = RecipeBookItemInfo(
            title: 'Clear Liquid Reagent',
            kind: 'Material',
            summary: '',
            effects: ['Recorded effect'],
            acquisitionNotes: ['Central Market'],
          );
          Widget content(ThemeSpec selected) => host == 'inline'
              ? ItemReferenceSections(
                  controller: book,
                  mode: CraftMode.alchemy,
                  name: info.title,
                  info: info,
                  spec: selected,
                )
              : ItemReferenceCard(
                  controller: book,
                  mode: CraftMode.alchemy,
                  name: info.title,
                  info: info,
                  maxWidth: 480,
                  spec: selected,
                  interactive: host != 'passive',
                );
          Future<void> pump(ThemeSpec selected) => tester.pumpWidget(
            MaterialApp(
              theme: ambient.materialTheme(),
              home: ThemeSpecScope(
                spec: ambient,
                child: Scaffold(
                  body: Center(
                    child: SizedBox(width: 480, child: content(selected)),
                  ),
                ),
              ),
            ),
          );
          for (final selected in [spec, ambient, spec]) {
            await pump(selected);
            await tester.pumpAndSettle();
            final badge = find.byType(SourceAvailabilityBadges);
            expect(badge, findsOneWidget);
            expect(tester.element(badge).visualTheme, same(selected));
            final heading = tester.widget<Text>(find.text('Effects'));
            expect(heading.style!.color, ItemDetailStyle.accent(selected));
            final ink = tester
                .widget<Text>(
                  find.descendant(of: badge, matching: find.byType(Text)).first,
                )
                .style!
                .color!;
            final surface = selected.palette.surface;
            final lighter = ink.computeLuminance() > surface.computeLuminance()
                ? ink
                : surface;
            final darker = lighter == surface ? ink : surface;
            expect(
              (lighter.computeLuminance() + .05) /
                  (darker.computeLuminance() + .05),
              greaterThanOrEqualTo(4.5),
            );
            expect(tester.takeException(), isNull);
          }
        },
      );
    }
  }

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

  for (final scale in [1.0, 2.0]) {
    testWidgets('ingredient quantities stay beside names at $scale text', (
      tester,
    ) async {
      final formula = recipeBookFormulas(
        environment.application.active.recipeDefinition('Clear Liquid Reagent'),
        mode: CraftMode.alchemy,
      ).first;
      final copied = <String>[];
      await _pump(
        tester,
        book,
        RecipeBookItemInfo(
          title: formula.outputName,
          kind: 'Reagent',
          summary: '',
          acquisitionFormulas: [formula],
        ),
        width: scale == 1 ? 480 : 320,
        scale: scale,
        onCopy: copied.add,
      );
      for (final ingredient in formula.ingredients) {
        final row = find.byKey(
          RecipeBookKeys.itemInfoMaterial(
            formula.outputName,
            formula.variantId,
            ingredient.name,
          ),
        );
        final name = find.descendant(
          of: row,
          matching: find.text(ingredient.name),
        );
        final quantity = find.descendant(
          of: row,
          matching: find.text('×${ingredient.quantity.toInt()}'),
        );
        await tester.ensureVisible(name);
        await tester.pumpAndSettle();
        expect(
          tester.getRect(quantity).left - tester.getRect(name).right,
          closeTo(8, .1),
        );
        expect(
          tester.getRect(quantity).right,
          lessThan(tester.getRect(row).right),
        );
        await tester.tap(name);
      }
      expect(
        copied,
        formula.ingredients.map((ingredient) => ingredient.name).toList(),
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  for (final spec in [
    SakuraNightGardenSpec.theme,
    StandardSpec.theme,
    IlluminatedLedgerSpec.theme,
  ]) {
    testWidgets('height follows content and caps long lists ${spec.id}', (
      tester,
    ) async {
      final formula = recipeBookFormulas(
        environment.application.active.recipeDefinition('Clear Liquid Reagent'),
        mode: CraftMode.alchemy,
      ).first;
      final before = environment.application.active.state.value.toJson();
      RecipeBookItemInfo info(List<RecipeBookFormula> formulas) =>
          RecipeBookItemInfo(
            title: 'Clear Liquid Reagent',
            kind: 'Reagent',
            summary: 'A short description.',
            acquisitionFormulas: formulas,
          );
      final card = find.byType(ItemReferenceCard);
      ScrollPosition position() => tester
          .state<ScrollableState>(
            find.descendant(
              of: card,
              matching: find.byWidgetPredicate(
                (widget) =>
                    widget is Scrollable &&
                    widget.axisDirection == AxisDirection.down,
              ),
            ),
          )
          .position;
      await _pump(tester, book, info([]), spec: spec);
      final shortHeight = tester.getSize(card).height;
      expect(shortHeight, lessThan(300));
      expect(position().maxScrollExtent, 0);

      await _pump(tester, book, info([formula]), spec: spec);
      final recipeHeight = tester.getSize(card).height;
      expect(recipeHeight, greaterThan(shortHeight));
      expect(recipeHeight, lessThan(760));
      expect(position().maxScrollExtent, 0);
      final action = find.text('Use recipe');
      expect(action.hitTestable(), findsOneWidget);
      final lastRow = find.byKey(
        RecipeBookKeys.itemInfoMaterial(
          formula.outputName,
          formula.variantId,
          formula.ingredients.last.name,
        ),
      );
      expect(
        tester.getRect(lastRow).bottom,
        lessThanOrEqualTo(tester.getRect(action).top),
      );

      final routes = [
        for (var i = 0; i < 10; i++)
          RecipeBookFormula(
            outputName: formula.outputName,
            type: formula.type,
            method: formula.method,
            // Distinct synthetic yields prevent the production formula
            // deduplicator collapsing this long-list fixture to one recipe.
            baseOutput: formula.baseOutput + i,
            ingredients: formula.ingredients,
            mode: formula.mode,
            variantId: 'height-test-$i',
          ),
      ];
      await _pump(tester, book, info(routes), spec: spec);
      expect(tester.getSize(card).height, closeTo(868, .1));
      expect(position().maxScrollExtent, greaterThan(0));
      final firstRecipe = find.byKey(
        RecipeBookKeys.itemInfoFormula(
          routes.first.outputName,
          routes.first.variantId,
          1,
        ),
      );
      final viewport = tester.getRect(
        find.byKey(const ValueKey('attached-reference-scroll')),
      );
      expect(
        tester.getRect(firstRecipe).top,
        greaterThanOrEqualTo(viewport.top),
      );
      expect(
        tester.getRect(firstRecipe).bottom,
        lessThanOrEqualTo(viewport.bottom),
      );
      position().jumpTo(position().maxScrollExtent);
      await tester.pumpAndSettle();
      final lastRecipe = find.byKey(
        RecipeBookKeys.itemInfoFormula(
          routes.last.outputName,
          routes.last.variantId,
          1,
        ),
      );
      expect(tester.getRect(lastRecipe).bottom, closeTo(viewport.bottom, .1));

      // Reflow the same open window, then reduce its contents again. No stale
      // height/offset may leave blank space or hide the short description.
      tester.view.physicalSize = const Size(900, 500);
      await tester.pumpAndSettle();
      expect(tester.getRect(card).top, greaterThanOrEqualTo(0));
      expect(tester.getRect(card).bottom, lessThanOrEqualTo(500));
      expect(position().maxScrollExtent, greaterThan(0));
      await _pump(tester, book, info([]), spec: spec);
      expect(tester.getSize(card).height, closeTo(shortHeight, .1));
      expect(position().pixels, 0);
      expect(position().maxScrollExtent, 0);
      expect(environment.application.active.state.value.toJson(), before);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });

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
