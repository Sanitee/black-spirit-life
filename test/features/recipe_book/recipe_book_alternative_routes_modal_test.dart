import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:bdo_craft_planner_flutter/app/state/planner_application_controller.dart';
import 'package:bdo_craft_planner_flutter/data/catalog/bundled_catalog_parser.dart';
import 'package:bdo_craft_planner_flutter/data/catalog/catalog_repository.dart';
import 'package:bdo_craft_planner_flutter/domain/models/catalog_models.dart';
import 'package:bdo_craft_planner_flutter/domain/models/craft_mode.dart';
import 'package:bdo_craft_planner_flutter/domain/state/planner_state.dart';
import 'package:bdo_craft_planner_flutter/features/planner/planner_contracts.dart';
import 'package:bdo_craft_planner_flutter/features/recipe_book/recipe_book.dart';
import 'package:bdo_craft_planner_flutter/features/recipe_book/recipe_ingredient_line.dart';
import 'package:bdo_craft_planner_flutter/features/shared/recipe_variant_selector.dart';
import 'package:bdo_craft_planner_flutter/shared/overlays/anchored_popover.dart';
import 'package:bdo_craft_planner_flutter/visual/visual.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderRepaintBoundary;
import 'package:flutter/services.dart' show FontLoader;
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late CatalogSnapshot catalog;
  setUpAll(() async {
    await _loadFonts();
    catalog = const BundledCatalogParser().parse(
      File('assets/data/app-data.json').readAsStringSync(),
    );
  });

  const themes = <String, ThemeSpec>{
    'Sakura': SakuraNightGardenSpec.theme,
    'Ledger': IlluminatedLedgerSpec.theme,
    'Green': StandardSpec.theme,
  };

  for (final theme in themes.entries) {
    for (final view in [
      (size: const Size(1200, 752), scale: 1.0),
      (size: const Size(1500, 940), scale: 1.0),
      (size: const Size(1200, 752), scale: 1.5),
    ]) {
      testWidgets('${theme.key} Used In grows and shrinks with content '
          'at ${view.size.height} height and ${view.scale} text', (
        tester,
      ) async {
        final harness = await _openBook(
          tester,
          catalog,
          theme.value,
          viewport: view.size,
          textScale: view.scale,
        );
        const name = 'Adaptation Draught';
        await tester.enterText(_search(), name);
        await tester.pumpAndSettle();
        await tester.tap(
          find.descendant(
            of: find.byKey(RecipeBookKeys.card(name)),
            matching: find.byKey(RecipeBookKeys.usedIn(name)),
          ),
        );
        await tester.pumpAndSettle();
        final panel = find.byKey(RecipeBookKeys.usedInPanel(name));
        final collapsedHeight = tester.getSize(panel).height;
        final expand = find.byKey(
          RecipeBookKeys.expandUsedInResult(
            name,
            CraftMode.alchemy.key,
            'Harmony Draught',
          ),
        );
        await tester.tap(expand);
        await tester.pumpAndSettle();
        final bounds = tester.getRect(panel);
        expect(bounds.height, greaterThan(610));
        expect(bounds.height, greaterThan(collapsedHeight));
        expect(bounds.top, greaterThanOrEqualTo(12));
        expect(bounds.bottom, lessThanOrEqualTo(view.size.height - 12));
        expect(bounds.left, greaterThanOrEqualTo(12));
        expect(bounds.right, lessThanOrEqualTo(view.size.width - 12));
        expect(tester.takeException(), isNull);
        await _capture(
          tester,
          'taller-used-in-${theme.key}-${view.size.height}-${view.scale}',
        );

        final scrollable = find.descendant(
          of: find.byKey(RecipeBookKeys.usedInScroll(name)),
          matching: find.byType(Scrollable),
        );
        final position = tester.state<ScrollableState>(scrollable).position;
        if (view.size.height == 940 && view.scale == 1) {
          expect(position.maxScrollExtent, 0);
        } else {
          expect(position.maxScrollExtent, greaterThan(0));
        }
        position.jumpTo(position.maxScrollExtent);
        await tester.pumpAndSettle();
        expect(
          find
              .byKey(
                RecipeBookKeys.expandUsedInResult(
                  name,
                  CraftMode.processing.key,
                  'Immortal: Adaptation Draught',
                ),
              )
              .hitTestable(),
          findsOneWidget,
        );
        position.jumpTo(0);
        await tester.pumpAndSettle();
        await tester.tap(expand);
        await tester.pumpAndSettle();
        expect(tester.getSize(panel).height, closeTo(collapsedHeight, .5));
        if (view.scale == 1) {
          expect(collapsedHeight, lessThan(500));
        }
        await tester.tap(find.byKey(RecipeBookKeys.closeUsedIn(name)));
        await tester.pumpAndSettle();
        expect(panel, findsNothing);
        expect(harness.saved, isEmpty);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('${theme.key} recipe preview uses the viewport height', (
      tester,
    ) async {
      final harness = await _openBook(
        tester,
        catalog,
        theme.value,
        viewport: const Size(1500, 940),
        textScale: 2,
      );
      const name = 'Adaptation Draught';
      await tester.enterText(_search(), name);
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byKey(RecipeBookKeys.card(name)),
          matching: find.byKey(RecipeBookKeys.r13Details(name)),
        ),
      );
      await tester.pumpAndSettle();
      _expectPreviewFits(tester);
      final preview = find.byKey(RecipeBookKeys.previewPanel);
      expect(
        find.descendant(
          of: preview,
          matching: find.byWidgetPredicate(
            (widget) =>
                widget is ConstrainedBox &&
                widget.constraints.maxHeight == 940 - 32 - 28,
          ),
        ),
        findsOneWidget,
      );
      await _capture(
        tester,
        'taller-recipe-preview-${theme.key}-2.0',
        panelOnly: true,
      );
      expect(harness.saved, isEmpty);
      expect(tester.takeException(), isNull);
    });

    for (final scale in [1.0, 1.5]) {
      testWidgets(
        '${theme.key} open ingredient rows retain selectors at $scale text',
        (tester) async {
          final harness = await _openBook(
            tester,
            catalog,
            theme.value,
            textScale: scale,
          );
          const name = 'Adaptation Draught';
          await tester.enterText(_search(), name);
          await tester.pumpAndSettle();
          await tester.tap(
            find.descendant(
              of: find.byKey(RecipeBookKeys.card(name)),
              matching: find.byKey(RecipeBookKeys.r13Details(name)),
            ),
          );
          await tester.pumpAndSettle();
          await tester.tap(
            find.byKey(RecipeVariantSelector.batchChoiceKey(name, 10)),
          );
          await tester.pumpAndSettle();
          _expectPreviewFits(tester);
          final preview = find.byKey(RecipeBookKeys.previewPanel);
          expect(
            find.descendant(
              of: preview,
              matching: find.byType(AppFilterButton),
            ),
            findsNothing,
          );
          expect(
            tester
                .getRect(find.byKey(RecipeBookKeys.r11Target('$name:preview')))
                .bottom,
            lessThan(
              tester
                  .getRect(
                    find.byKey(
                      const ValueKey('recipe-preview-ingredients-heading'),
                    ),
                  )
                  .top,
            ),
          );
          final rows = find.descendant(
            of: preview,
            matching: find.byType(RecipeIngredientLine),
          );
          expect(rows, findsNWidgets(5));
          expect(
            find.descendant(
              of: rows,
              matching: find.byWidgetPredicate(
                (widget) =>
                    widget is AppSurface && widget.role == AppSurfaceRole.row,
              ),
            ),
            findsNothing,
          );
          final selectorKey = RecipeBookKeys.r15Substitute(
            name,
            'Elixir of Life',
          );
          final selector = find.byKey(selectorKey);
          expect(tester.widget<AppSelect<String>>(selector).inline, isTrue);
          final quantity = find.byKey(
            RecipeBookKeys.previewQuantity(name, 'Elixir of Life'),
          );
          expect(tester.widget<Text>(quantity).data, '×30');
          expect(
            tester.getRect(quantity).left - tester.getRect(selector).right,
            closeTo(8, .5),
          );
          expect(
            tester.getCenter(quantity).dy,
            closeTo(tester.getCenter(selector).dy, .5),
          );
          await _capture(
            tester,
            'open-ingredients-adaptation-${theme.key}-$scale',
            panelOnly: true,
          );
          await tester.tap(
            find.byKey(
              RecipeBookKeys.r16Quality(name, 'Elixir of Life', 'blue'),
            ),
          );
          await tester.pumpAndSettle();
          expect(
            harness.application.modes[CraftMode.alchemy]!
                .selectedIngredientGrade(
                  parentName: name,
                  ingredientName: 'Elixir of Life',
                  selectedName: 'Elixir of Life',
                ),
            'blue',
          );
          final current = tester.widget<AppSelect<String>>(selector);
          final alternate = current.items.firstWhere(
            (value) => value != current.value,
          );
          await tester.tap(selector);
          await tester.pumpAndSettle();
          await tester.tap(find.text(alternate).last);
          await tester.pumpAndSettle();
          expect(tester.widget<AppSelect<String>>(selector).value, alternate);
          await tester.tap(
            find.byKey(RecipeVariantSelector.batchChoiceKey(name, 100)),
          );
          await tester.pumpAndSettle();
          expect(_previewText('Output 100'), findsOneWidget);
          _expectPreviewFits(tester);
          await tester.pumpWidget(const SizedBox.shrink());
        },
      );
    }
  }

  testWidgets(
    'Berserk duplicate from Processing keeps its batch and targets the complete recipe',
    (tester) async {
      final harness = await _openBook(
        tester,
        catalog,
        SakuraNightGardenSpec.theme,
        activeMode: CraftMode.processing,
      );
      const name = 'Berserk Draught';
      final processing = harness.application.modes[CraftMode.processing]!;
      final alchemy = harness.application.modes[CraftMode.alchemy]!;
      processing.selectRecipeVariant(
        recipeName: name,
        variantId: 'simple-alchemy-100x',
      );
      final originalAlchemyVariant = alchemy.selectedRecipeVariantId(name);
      final originalProcessingTarget = processing.state.value.target;
      await tester.enterText(_search(), name);
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byKey(RecipeBookKeys.card(name)),
          matching: find.byKey(RecipeBookKeys.r13Details(name)),
        ),
      );
      await tester.pumpAndSettle();
      final book = tester
          .widget<RecipeBookModal>(find.byType(RecipeBookModal))
          .controller;
      expect(book.previewRoutesFor(name), hasLength(1));
      expect(book.previewController.modeController.mode, CraftMode.alchemy);
      expect(
        book.previewController.selectedRecipeVariantId(name),
        'simple-alchemy-100x',
      );
      expect(alchemy.selectedRecipeVariantId(name), originalAlchemyVariant);
      expect(harness.application.activeMode.value, CraftMode.processing);
      expect(
        find.byKey(
          RecipeBookKeys.r15Substitute(name, 'Elixir of Assassination'),
        ),
        findsOneWidget,
      );
      expect(_previewText('Output 100'), findsOneWidget);
      await _capture(tester, 'berserk-header-100x', panelOnly: true);
      book.closePreview();
      await tester.pumpAndSettle();
      expect(alchemy.selectedRecipeVariantId(name), originalAlchemyVariant);
      book.openPreview(name, mode: CraftMode.alchemy);
      await tester.pumpAndSettle();
      expect(_previewText('Output 10'), findsOneWidget);
      await _capture(tester, 'berserk-header', panelOnly: true);
      book.closePreview();
      await tester.pumpAndSettle();
      book.openPreview(name, mode: CraftMode.processing);
      await tester.pumpAndSettle();
      expect(_previewText('Output 100'), findsOneWidget);
      expect(alchemy.selectedRecipeVariantId(name), originalAlchemyVariant);
      await tester.tap(find.byKey(RecipeBookKeys.r11Target('$name:preview')));
      await tester.pumpAndSettle();
      expect(harness.results.single!.mode, CraftMode.alchemy);
      expect(harness.results.single!.exactName, name);
      expect(harness.results.single!.variantId, 'simple-alchemy-100x');
      expect(alchemy.state.value.target, name);
      expect(processing.state.value.target, originalProcessingTarget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'Ekleta search opens every Heating stone and targets its 10x batch',
    (tester) async {
      final harness = await _openBook(
        tester,
        catalog,
        SakuraNightGardenSpec.theme,
        activeMode: CraftMode.processing,
      );
      await tester.enterText(_search(), 'ekleta');
      await tester.pumpAndSettle();
      final book = tester
          .widget<RecipeBookModal>(find.byType(RecipeBookModal))
          .controller;
      expect(
        book.snapshot.entries.where(
          (entry) =>
              entry.recipe.method == 'Item Reform' ||
              entry.recipe.method == 'Quest Exchange',
        ),
        isEmpty,
      );
      for (final slot in ['Belt', 'Earring', 'Necklace', 'Ring']) {
        final name = 'Causality Shardstone - $slot';
        await _revealCard(tester, find.byKey(RecipeBookKeys.card(name)));
        expect(find.byKey(RecipeBookKeys.r11Target(name)), findsOneWidget);
      }
      await tester.drag(
        find.byKey(RecipeBookKeys.r10CardScroll),
        const Offset(0, 800),
      );
      await tester.pumpAndSettle();
      await _capture(tester, 'sakura-ekleta-search');

      const name = 'Causality Shardstone - Ring';
      await tester.tap(find.byKey(RecipeBookKeys.r13Details(name)));
      await tester.pumpAndSettle();
      _expectPreviewFits(tester);
      expect(_previewText('Twilight of the End - Ring'), findsOneWidget);
      expect(_previewText('Caphras Stone'), findsOneWidget);
      expect(_previewText('Magical Shard'), findsOneWidget);
      expect(_previewText('Essence of Dawn'), findsOneWidget);
      expect(_previewText('Output 1'), findsOneWidget);
      await tester.tap(
        find.byKey(RecipeVariantSelector.batchChoiceKey(name, 10)),
      );
      await tester.pumpAndSettle();
      expect(_previewText('Output 10'), findsOneWidget);
      expect(_previewText('Black Stone Powder'), findsOneWidget);
      await _capture(tester, 'sakura-ekleta-stone-10x');
      await tester.tap(find.byKey(RecipeBookKeys.r11Target('$name:preview')));
      await tester.pumpAndSettle();
      expect(harness.results.single?.variantId, 'heating-10x');
      final step = harness.application.active.plan.value.steps.singleWhere(
        (step) => step.name == name,
      );
      expect(step.count, 2);
      expect(step.produced, 20);
      expect(
        {for (final item in step.ingredients) item.name: item.need},
        {
          'Twilight of the End - Ring': 100,
          'Caphras Stone': 200,
          'Magical Shard': 200,
          'Essence of Dawn': 200,
          'Black Stone Powder': 2,
        },
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  for (final theme in themes.entries) {
    testWidgets(
      '${theme.key} 1200x752 ingredient search opens and targets foreign perfume cards',
      (tester) async {
        final harness = await _openBook(tester, catalog, theme.value);
        final alchemy = harness.application.modes[CraftMode.alchemy]!;
        final originalTarget = alchemy.state.value.target;

        await tester.tap(find.byKey(RecipeBookKeys.r05SearchByIngredient));
        await tester.enterText(_search(), 'caphras essence');
        await tester.pumpAndSettle();
        expect(alchemy.state.value.bookSearchIngredients, isTrue);
        expect(tester.takeException(), isNull);
        final modal = tester.widget<RecipeBookModal>(
          find.byType(RecipeBookModal),
        );
        expect(
          tester.widget<TextField>(_search()).controller!.text,
          'caphras essence',
        );
        expect(modal.controller.search, 'caphras essence');
        expect(
          modal.controller.snapshot.entries
              .where((entry) => entry.mode == CraftMode.processing)
              .map((entry) => entry.name),
          containsAll(['Perfume of Envy', 'Perfume of Tenacity']),
        );
        // Related aliases can add earlier results. Reveal the real lazy grid
        // rows through its scroll surface before interacting with their cards.
        await _revealCard(tester, _foreignCard('Perfume of Tenacity'));
        await _capture(tester, '${theme.key.toLowerCase()}-caphras-search');

        for (final name in ['Perfume of Envy', 'Perfume of Tenacity']) {
          final card = _foreignCard(name);
          await _revealCard(tester, card);
          expect(card, findsOneWidget);
          expect(
            find.descendant(
              of: card,
              matching: find.byKey(RecipeBookKeys.productionMethod(name)),
            ),
            findsOneWidget,
          );
          expect(
            find.descendant(of: card, matching: find.text('Simple Alchemy')),
            findsOneWidget,
          );
          await tester.tap(
            find.descendant(
              of: card,
              matching: find.byKey(RecipeBookKeys.r13Details(name)),
            ),
          );
          await tester.pumpAndSettle();
          _expectPreviewFits(tester);
          expect(_previewText('Caphras Essence'), findsOneWidget);
          expect(_previewText('Shining Powder'), findsOneWidget);
          expect(
            _previewText(
              name == 'Perfume of Envy'
                  ? 'Perfume of Courage'
                  : 'Perfume of Deep Sea',
            ),
            findsOneWidget,
          );
          expect(_previewText("Rusalka's Coral"), findsNothing);
          expect(_previewText('Output 1'), findsOneWidget);
          expect(harness.application.activeMode.value, CraftMode.alchemy);
          expect(alchemy.state.value.target, originalTarget);
          if (name == 'Perfume of Tenacity') {
            await _capture(
              tester,
              '${theme.key.toLowerCase()}-tenacity-simple-alchemy-preview',
            );
          }

          await tester.tap(find.byKey(RecipeBookKeys.r14ClosePreview(name)));
          await tester.pumpAndSettle();
          expect(find.byKey(RecipeBookKeys.previewPanel), findsNothing);
          expect(find.byKey(RecipeBookKeys.modal), findsOneWidget);
          expect(tester.takeException(), isNull);
        }

        const target = 'Perfume of Tenacity';
        await tester.tap(
          find.descendant(
            of: _foreignCard(target),
            matching: find.byKey(RecipeBookKeys.r11Target(target)),
          ),
        );
        await tester.pumpAndSettle();
        await harness.application.flush();
        expect(find.byKey(RecipeBookKeys.modal), findsNothing);
        expect(harness.results, hasLength(1));
        expect(harness.results.single?.mode, CraftMode.processing);
        expect(harness.results.single?.exactName, target);
        expect(harness.results.single?.variantId, 'standard');
        expect(harness.application.activeMode.value, CraftMode.processing);
        final processing = harness.application.active;
        final step = processing.plan.value.steps.singleWhere(
          (step) => step.name == target,
        );
        expect(step.count, 11);
        expect(step.produced, 11);
        expect(
          {
            for (final ingredient in step.ingredients)
              ingredient.name: ingredient.need,
          },
          {
            'Perfume of Deep Sea': 11,
            'Shining Powder': 33,
            'Caphras Essence': 110,
          },
        );
        expect(alchemy.state.value.target, originalTarget);
        expect(harness.saved.last.alchemy.target, originalTarget);
        expect(harness.saved.last.processing.target, target);
        expect(harness.saved.last.activeMode, CraftMode.processing);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );

    testWidgets(
      '${theme.key} 1200x752 Tenacity methods switch the preview and target its selected batch',
      (tester) async {
        final harness = await _openBook(tester, catalog, theme.value);
        final alchemy = harness.application.modes[CraftMode.alchemy]!;
        final originalTarget = alchemy.state.value.target;
        const name = 'Perfume of Tenacity';

        await tester.enterText(_search(), name);
        await tester.pumpAndSettle();
        final residenceCard = find.byKey(RecipeBookKeys.card(name));
        final processingCard = _foreignCard(name);
        expect(residenceCard, findsOneWidget);
        expect(processingCard, findsOneWidget);
        expect(
          find.descendant(
            of: residenceCard,
            matching: find.text('Residence Alchemy'),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: processingCard,
            matching: find.text('Simple Alchemy'),
          ),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);

        await tester.tap(
          find.descendant(
            of: residenceCard,
            matching: find.byKey(RecipeBookKeys.r13Details(name)),
          ),
        );
        await tester.pumpAndSettle();
        _expectPreviewFits(tester);
        expect(_previewText("Rusalka's Coral"), findsOneWidget);
        expect(_previewText('Oil of Regeneration'), findsOneWidget);
        expect(_previewText('Caphras Essence'), findsNothing);

        final residenceMethod = _method(CraftMode.alchemy, name);
        final processingMethod = _method(CraftMode.processing, name);
        expect(
          tester.widget<AppFilterButton>(residenceMethod).label,
          'Residence Alchemy',
        );
        expect(
          tester.widget<AppFilterButton>(processingMethod).label,
          'Simple Alchemy',
        );
        expect(residenceMethod, findsOneWidget);
        expect(processingMethod, findsOneWidget);
        expect(
          tester.widget<AppFilterButton>(residenceMethod).selected,
          isTrue,
        );

        await tester.tap(processingMethod);
        await tester.pumpAndSettle();
        _expectPreviewFits(tester);
        expect(
          tester.widget<AppFilterButton>(processingMethod).selected,
          isTrue,
        );
        expect(_previewText('Caphras Essence'), findsOneWidget);
        expect(_previewText('Perfume of Deep Sea'), findsOneWidget);
        expect(_previewText("Rusalka's Coral"), findsNothing);
        expect(_previewText('Output 1'), findsOneWidget);

        await tester.tap(residenceMethod);
        await tester.pumpAndSettle();
        _expectPreviewFits(tester);
        expect(
          tester.widget<AppFilterButton>(residenceMethod).selected,
          isTrue,
        );
        expect(_previewText("Rusalka's Coral"), findsOneWidget);
        expect(_previewText('Caphras Essence'), findsNothing);

        await tester.tap(processingMethod);
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(RecipeVariantSelector.batchChoiceKey(name, 10)),
        );
        await tester.pumpAndSettle();
        _expectPreviewFits(tester);
        expect(_previewText("Ibellab's Essence"), findsOneWidget);
        expect(_previewText('Output 10'), findsOneWidget);
        expect(alchemy.state.value.target, originalTarget);
        expect(harness.application.activeMode.value, CraftMode.alchemy);
        expect(harness.results, isEmpty);

        await tester.tap(find.byKey(RecipeBookKeys.r11Target('$name:preview')));
        await tester.pumpAndSettle();
        await harness.application.flush();
        expect(find.byKey(RecipeBookKeys.modal), findsNothing);
        expect(find.byKey(RecipeBookKeys.previewPanel), findsNothing);
        expect(harness.results, hasLength(1));
        expect(harness.results.single?.mode, CraftMode.processing);
        expect(harness.results.single?.exactName, name);
        expect(harness.results.single?.variantId, 'standard-10x');
        final processing = harness.application.active;
        expect(processing.mode, CraftMode.processing);
        expect(processing.selectedRecipeVariantId(name), 'standard-10x');
        final step = processing.plan.value.steps.singleWhere(
          (step) => step.name == name,
        );
        expect(step.count, 2);
        expect(step.produced, 20);
        expect(
          {
            for (final ingredient in step.ingredients)
              ingredient.name: ingredient.need,
          },
          {
            'Perfume of Deep Sea': 20,
            'Shining Powder': 60,
            'Caphras Essence': 200,
            "Ibellab's Essence": 2,
          },
        );
        expect(alchemy.state.value.target, originalTarget);
        expect(harness.saved.last.alchemy.target, originalTarget);
        expect(
          harness.saved.last.processing.recipeVariantChoices[name],
          'standard-10x',
        );
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }
}

final class _ModalHarness {
  _ModalHarness(this.application, this.saved);

  final PlannerApplicationController application;
  final List<PlannerState> saved;
  final results = <RecipeBookActivation?>[];
}

Future<_ModalHarness> _openBook(
  WidgetTester tester,
  CatalogSnapshot catalog,
  ThemeSpec spec, {
  CraftMode activeMode = CraftMode.alchemy,
  double textScale = 1,
  Size viewport = const Size(1200, 752),
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = viewport;
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  final saved = <PlannerState>[];
  final application = PlannerApplicationController(
    catalog: catalog,
    initialState: PlannerState(
      applicationVersion: 'recipe-alternative-modal-test',
      lastSuccessfulWriteUtc: DateTime.utc(2026, 9, 18),
      activeMode: activeMode,
      alchemy: _mode(CraftMode.alchemy, 'Clear Liquid Reagent'),
      cooking: _mode(CraftMode.cooking, 'Beer'),
      processing: _mode(CraftMode.processing, 'Wheat Flour'),
      processingYields: const {'defaultYield': 999, 'Simple Alchemy': 999},
      marketTax: MarketTax(),
      showDeleteTools: false,
    ),
    saveState: (state) async {
      saved.add(state);
      return state;
    },
    saveDebounce: Duration.zero,
  );
  addTearDown(application.dispose);
  final harness = _ModalHarness(application, saved);
  await tester.pumpWidget(
    RepaintBoundary(
      key: const ValueKey('recipe-route-capture'),
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: spec.materialTheme(),
        builder: (context, child) => ThemeSpecScope(
          spec: spec,
          child: MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(textScale)),
            child: AppOverlayCoordinatorHost(child: child!),
          ),
        ),
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: AppButton.label(
                'Open recipes',
                onPressed: () async {
                  final source = application.modes[activeMode]!;
                  harness.results.add(
                    await showRecipeBookModal(
                      context: context,
                      request: RecipeBookRequest(
                        controller: source,
                        context: RecipeBookCallingContext.planner,
                        allowedTargets: source.craftableNames,
                      ),
                      catalogRepository: CatalogRepository(catalog),
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open recipes'));
  await tester.pumpAndSettle();
  expect(find.byKey(RecipeBookKeys.modal), findsOneWidget);
  expect(tester.takeException(), isNull);
  return harness;
}

ModeState _mode(CraftMode mode, String target) => ModeState(
  target: target,
  want: 11,
  bonusTarget: target,
  market: MarketState(),
  appearance: AppearanceSettings.defaultsFor(mode),
);

Finder _search() => find.descendant(
  of: find.byKey(RecipeBookKeys.r03Search),
  matching: find.byType(TextField),
);

Finder _foreignCard(String name) =>
    find.byKey(ValueKey<String>('recipe-card:processing:$name'));

Finder _method(CraftMode mode, String name) =>
    find.byKey(ValueKey<String>('recipe-method:${mode.key}:$name'));

Finder _previewText(String value) => find.descendant(
  of: find.byKey(RecipeBookKeys.previewPanel),
  matching: find.text(value),
);

void _expectPreviewFits(WidgetTester tester) {
  final preview = find.byKey(RecipeBookKeys.previewPanel);
  expect(preview, findsOneWidget);
  final bounds = tester.getRect(preview);
  final viewport = tester.view.physicalSize / tester.view.devicePixelRatio;
  expect(bounds.left, greaterThanOrEqualTo(0));
  expect(bounds.top, greaterThanOrEqualTo(0));
  expect(bounds.right, lessThanOrEqualTo(viewport.width));
  expect(bounds.bottom, lessThanOrEqualTo(viewport.height));
  expect(tester.takeException(), isNull);
}

Future<void> _revealCard(WidgetTester tester, Finder card) async {
  await tester.scrollUntilVisible(
    card,
    250,
    scrollable: find
        .descendant(
          of: find.byKey(RecipeBookKeys.r10CardScroll),
          matching: find.byType(Scrollable),
        )
        .first,
  );
  await tester.pumpAndSettle();
}

Future<void> _capture(
  WidgetTester tester,
  String name, {
  bool panelOnly = false,
}) async {
  const captureDirectory = String.fromEnvironment('RECIPE_INGREDIENT_CAPTURES');
  if (captureDirectory.isEmpty &&
      Platform.environment['BSL_RECIPE_ROUTE_CAPTURES'] != '1') {
    return;
  }
  final captureContext = tester.element(
    find.byKey(const ValueKey('recipe-route-capture')),
  );
  final providers = tester
      .widgetList<Image>(find.byType(Image))
      .map((widget) => widget.image)
      .toSet();
  await tester.runAsync(
    () => Future.wait(
      providers.map((provider) => precacheImage(provider, captureContext)),
    ),
  );
  await tester.pumpAndSettle();
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(
      ValueKey(panelOnly ? 'recipe-preview-render' : 'recipe-route-capture'),
    ),
  );
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 1);
    try {
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      if (bytes == null) throw StateError('Could not render $name.');
      final directory = Directory(
        captureDirectory.isEmpty
            ? 'tmp/recipe-alternatives-visual'
            : captureDirectory,
      );
      await directory.create(recursive: true);
      await File('${directory.path}/$name.png').writeAsBytes(
        bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
      );
    } finally {
      image.dispose();
    }
  });
}

Future<void> _loadFonts() async {
  if (!Platform.isWindows) return;
  final windowsPath = Platform.environment['WINDIR'] ?? r'C:\Windows';
  var sdk = File(Platform.resolvedExecutable).parent;
  while (!Directory(
    '${sdk.path}/bin/cache/artifacts/material_fonts',
  ).existsSync()) {
    if (sdk.parent.path == sdk.path) {
      throw StateError('Flutter fonts not found.');
    }
    sdk = sdk.parent;
  }
  final materialFonts = '${sdk.path}/bin/cache/artifacts/material_fonts';
  for (final font in {
    'Segoe UI': [
      '$windowsPath/Fonts/segoeui.ttf',
      '$windowsPath/Fonts/seguisb.ttf',
      '$windowsPath/Fonts/segoeuib.ttf',
    ],
    'Georgia': [
      '$windowsPath/Fonts/georgia.ttf',
      '$windowsPath/Fonts/georgiab.ttf',
      '$windowsPath/Fonts/georgiai.ttf',
    ],
    'Roboto': [
      '$materialFonts/roboto-regular.ttf',
      '$materialFonts/roboto-bold.ttf',
    ],
    'MaterialIcons': ['$materialFonts/materialicons-regular.otf'],
  }.entries) {
    final loader = FontLoader(font.key);
    for (final path in font.value) {
      loader.addFont(File(path).readAsBytes().then(ByteData.sublistView));
    }
    await loader.load();
  }
}
