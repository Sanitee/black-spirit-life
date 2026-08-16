import 'dart:io';

import 'package:bdo_craft_planner_flutter/data/catalog/bundled_catalog_parser.dart';
import 'package:bdo_craft_planner_flutter/domain/models/craft_mode.dart';
import 'package:bdo_craft_planner_flutter/domain/state/planner_state.dart';
import 'package:bdo_craft_planner_flutter/domain/state/state_copy.dart';
import 'package:bdo_craft_planner_flutter/features/editor/editor.dart';
import 'package:bdo_craft_planner_flutter/visual/components/app_button.dart';
import 'package:bdo_craft_planner_flutter/visual/components/app_form_controls.dart';
import 'package:bdo_craft_planner_flutter/visual/components/app_surface.dart';
import 'package:bdo_craft_planner_flutter/visual/components/app_vector_glyph.dart';
import 'package:bdo_craft_planner_flutter/visual/foundations/theme_spec.dart';
import 'package:bdo_craft_planner_flutter/visual/illuminated_ledger/ledger_spec.dart';
import 'package:bdo_craft_planner_flutter/visual/sakura_night_garden/sakura_spec.dart';
import 'package:bdo_craft_planner_flutter/visual/standard/standard_spec.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../inventory/inventory_test_fixture.dart';
import 'editor_test_fixture.dart';

const MethodChannel _windowChannel = MethodChannel(
  'com.bdocraftplanner.flutter/window',
);

void main() {
  testWidgets(
    'Recipe Editor harness initializes',
    (tester) async {
      final harness = EditorTestHarness();
      await tester.pumpWidget(harness.host());
      await tester.pump();
      expect(find.byType(RecipeEditorView), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      await harness.dispose();
    },
    timeout: const Timeout(Duration(seconds: 10)),
  );

  testWidgets(
    'Recipe Editor Tab order enters the next field and dropdown arrows select',
    (tester) async {
      final harness = EditorTestHarness();
      await pumpEditor(tester, harness, size: const Size(1500, 940));

      final output = tester.widget<EditableText>(
        editorForKey(EditorActionKeys.e05),
      );
      final marketId = tester.widget<EditableText>(
        editorForKey(EditorActionKeys.e06),
      );
      output.focusNode.requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      expect(marketId.focusNode.hasFocus, isTrue);

      final categoryHost = find.byKey(EditorActionKeys.e08);
      final category = tester.widget<AppSelect<String>>(
        find.descendant(
          of: categoryHost,
          matching: find.byType(AppSelect<String>),
        ),
      );
      final categoryFocus = tester
          .widget<FocusableActionDetector>(
            find.descendant(
              of: categoryHost,
              matching: find.byType(FocusableActionDetector),
            ),
          )
          .focusNode!;
      final currentIndex = category.items.indexOf(category.value);
      final moveDown = currentIndex + 1 < category.items.length;
      final expected =
          category.items[moveDown ? currentIndex + 1 : currentIndex - 1];

      categoryFocus.requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(
        moveDown ? LogicalKeyboardKey.arrowDown : LogicalKeyboardKey.arrowUp,
      );
      await tester.pump();

      final updatedCategory = tester.widget<AppSelect<String>>(
        find.descendant(
          of: categoryHost,
          matching: find.byType(AppSelect<String>),
        ),
      );
      expect(updatedCategory.value, expected);
      expect(categoryFocus.hasFocus, isTrue);
      expect(tester.takeException(), isNull);
      await finishEditor(tester, harness);
    },
  );

  testWidgets(
    'long category and method names stay complete in closed editor selectors',
    (tester) async {
      const category = 'Rare Expedition Alchemy Ingredients';
      const method = 'Traditional Cheetah Dragon Blood Preparation';
      final base = editorDeepDocument();
      final existing = base.alchemy.recipeEdits['Clear Liquid Reagent']!;
      final harness = EditorTestHarness(
        initialState: base.copyWith(
          alchemy: base.alchemy.copyWith(
            customCategories: <String>[
              ...base.alchemy.customCategories,
              category,
            ],
            ingredientMeta: <String, IngredientMetadata>{
              ...base.alchemy.ingredientMeta,
              'Clear Liquid Reagent': IngredientMetadata(category: category),
            },
            recipeEdits: <String, RecipeState?>{
              ...base.alchemy.recipeEdits,
              'Clear Liquid Reagent': existing.copyWith(
                group: category,
                method: method,
              ),
            },
          ),
        ),
      );
      await pumpEditor(tester, harness, size: const Size(1200, 752));

      for (final entry in <Key, String>{
        EditorActionKeys.e08: category,
        EditorActionKeys.e09: method,
      }.entries) {
        final owner = find.byKey(entry.key);
        final label = find.descendant(
          of: owner,
          matching: find.text(entry.value),
        );
        expect(label, findsOneWidget);
        final paragraph = tester.renderObject<RenderParagraph>(label);
        expect(paragraph.didExceedMaxLines, isFalse);
        expect(paragraph.text.style?.fontSize, isNot(lessThan(12)));
      }
      final categoryRect = tester.getRect(find.byKey(EditorActionKeys.e08));
      final methodRect = tester.getRect(find.byKey(EditorActionKeys.e09));
      expect(methodRect.top, greaterThan(categoryRect.bottom));
      expect(tester.takeException(), isNull);
      await finishEditor(tester, harness);
    },
  );

  testWidgets('Ledger editor list matches selected row contrast and geometry', (
    tester,
  ) async {
    final harness = EditorTestHarness();
    await pumpEditor(
      tester,
      harness,
      size: const Size(1500, 940),
      spec: IlluminatedLedgerSpec.theme,
    );

    final selectedRow = find.byKey(
      EditorActionKeys.item('Clear Liquid Reagent'),
    );
    final item = find.descendant(
      of: selectedRow,
      matching: find.text('Clear Liquid Reagent'),
    );
    final itemText = tester.widget<Text>(item);
    expect(itemText.style!.color, const Color(0xFFF7EAC7));
    expect(itemText.style!.fontFamily, 'Georgia');
    expect(itemText.style!.height, 1.16);
    final selectedMeta = tester.widget<Text>(
      find.descendant(
        of: selectedRow,
        matching: find.byWidgetPredicate(
          (widget) => widget is Text && (widget.data?.contains(' / ') ?? false),
        ),
      ),
    );
    expect(selectedMeta.style!.color, const Color(0xFFF7EAC7));
    expect(selectedMeta.style!.height, 1.16);
    expect(
      tester
          .widget<AppButton>(
            find.descendant(of: selectedRow, matching: find.byType(AppButton)),
          )
          .role,
      AppButtonRole.modeSelector,
    );

    final regularRow = find.byKey(EditorActionKeys.item('Pure Powder Reagent'));
    final regularText = tester.widget<Text>(
      find.descendant(
        of: regularRow,
        matching: find.text('Pure Powder Reagent'),
      ),
    );
    expect(regularText.style!.color, IlluminatedLedgerSpec.palette.text);

    final selectedIcon = find.descendant(
      of: selectedRow,
      matching: find.byWidgetPredicate(
        (widget) =>
            widget is Semantics &&
            widget.properties.label == 'Clear Liquid Reagent icon',
      ),
    );
    expect(
      tester.getRect(item).left - tester.getRect(selectedIcon).right,
      closeTo(15, .01),
    );
    final heading = tester.widget<Text>(find.text('RECIPE EDITOR'));
    expect(heading.style!.color, IlluminatedLedgerSpec.palette.primary);
    expect(find.text('Recipe Editor'), findsNothing);

    await finishEditor(tester, harness);
  });

  testWidgets(
    'Ledger new draft uses lapis type, fallback tile, and full-width add action',
    (tester) async {
      final harness = EditorTestHarness();
      await pumpEditor(
        tester,
        harness,
        size: const Size(1500, 940),
        spec: IlluminatedLedgerSpec.theme,
      );

      AppButton typeButton(String type) => tester.widget<AppButton>(
        find.descendant(
          of: find.byKey(EditorActionKeys.type(type)),
          matching: find.byType(AppButton),
        ),
      );

      expect(typeButton('alchemy').selected, isTrue);
      expect(typeButton('alchemy').role, AppButtonRole.modeSelector);
      expect(typeButton('simple_alchemy').selected, isFalse);
      expect(typeButton('simple_alchemy').role, AppButtonRole.navigation);
      final selectedTypeDecoration =
          tester
                  .widget<AnimatedContainer>(
                    find.descendant(
                      of: find.byKey(EditorActionKeys.type('alchemy')),
                      matching: find.byKey(AppButton.materialKey),
                    ),
                  )
                  .decoration!
              as BoxDecoration;
      expect(
        (selectedTypeDecoration.gradient! as LinearGradient).colors,
        const <Color>[Color(0xFF174D7E), Color(0xFF0A2744)],
      );
      expect(
        find.descendant(
          of: find.byKey(EditorActionKeys.type('alchemy')),
          matching: find.byWidgetPredicate(
            (widget) =>
                widget is DefaultTextStyle &&
                widget.style.color == const Color(0xFFFFF1BD),
          ),
        ),
        findsOneWidget,
      );

      await tester.tap(find.byKey(EditorActionKeys.e03));
      await tester.pump();
      await tester.ensureVisible(find.byKey(EditorActionKeys.e15));
      await tester.pump();

      final addIngredient = tester.widget<AppButton>(
        find.byKey(EditorActionKeys.e15),
      );
      expect(addIngredient.role, AppButtonRole.primary);
      expect(
        tester.getSize(find.byKey(EditorActionKeys.e15)).width,
        greaterThan(700),
      );

      final fallbackIcon = find.byWidgetPredicate(
        (widget) =>
            widget is Semantics && widget.properties.label == 'New Recipe icon',
        skipOffstage: false,
      );
      final fallbackTile = tester.widget<Container>(
        find.descendant(
          of: fallbackIcon,
          matching: find.byWidgetPredicate(
            (widget) =>
                widget is Container &&
                widget.constraints?.maxWidth == 54 &&
                widget.constraints?.maxHeight == 54,
          ),
          skipOffstage: false,
        ),
      );
      final decoration = fallbackTile.decoration! as BoxDecoration;
      final gradient = decoration.gradient! as LinearGradient;
      expect(gradient.colors, const <Color>[
        Color(0xFF174D7E),
        Color(0xFF0A2744),
      ]);
      expect(decoration.border!.top.color, const Color(0xFFC3A04B));
      expect(decoration.border!.top.width, 1.3);
      expect(decoration.borderRadius, BorderRadius.circular(1));
      expect(decoration.boxShadow, const <BoxShadow>[
        BoxShadow(
          color: Color(0x44352516),
          blurRadius: 5,
          offset: Offset(0, 2),
        ),
      ]);
      expect(
        tester
            .widget<Text>(
              find.descendant(
                of: fallbackIcon,
                matching: find.text('NR', skipOffstage: false),
                skipOffstage: false,
              ),
            )
            .style!
            .color,
        const Color(0xFFEAD8A4),
      );

      await finishEditor(tester, harness);
    },
  );

  testWidgets('editor actions use Avalonia-authored vector glyphs and sizes', (
    tester,
  ) async {
    final harness = EditorTestHarness();
    await pumpEditor(tester, harness, size: const Size(1500, 940));

    AppVectorGlyph actionGlyph(Key key) => tester.widget<AppVectorGlyph>(
      find.descendant(
        of: find.byKey(key),
        matching: find.byType(AppVectorGlyph),
      ),
    );

    expect(actionGlyph(EditorActionKeys.e17).name, 'check');
    expect(actionGlyph(EditorActionKeys.e17).size, 16);
    expect(actionGlyph(EditorActionKeys.e18).name, 'trash');
    expect(actionGlyph(EditorActionKeys.e18).size, 16);
    expect(actionGlyph(EditorActionKeys.e11).name, 'image');
    expect(actionGlyph(EditorActionKeys.e11).size, 16);
    expect(actionGlyph(EditorActionKeys.e12).name, 'trash');
    expect(actionGlyph(EditorActionKeys.e12).size, 16);
    expect(actionGlyph(EditorActionKeys.e15).name, 'add');
    expect(actionGlyph(EditorActionKeys.e15).size, 13);
    expect(actionGlyph(EditorActionKeys.e16).name, 'trash');
    expect(actionGlyph(EditorActionKeys.e16).size, 23);

    await tester.ensureVisible(find.byKey(EditorActionKeys.e12));
    await tester.tap(find.byKey(EditorActionKeys.e12));
    await tester.pump();
    final info = tester.widget<AppVectorGlyph>(
      find.byWidgetPredicate(
        (widget) =>
            widget is AppVectorGlyph &&
            widget.name == 'info' &&
            widget.size == 17,
      ),
    );
    expect(info.name, 'info');

    await tester.enterText(editorForKey(EditorActionKeys.e05), '0');
    await tester.tap(find.byKey(EditorActionKeys.e17));
    await tester.pump();
    final error = tester.widget<AppVectorGlyph>(
      find.byWidgetPredicate(
        (widget) =>
            widget is AppVectorGlyph &&
            widget.name == 'error' &&
            widget.size == 17,
      ),
    );
    expect(error.name, 'error');

    await tester.tap(find.byKey(EditorActionKeys.e03));
    await tester.pump();
    final fallbackIcon = find.byWidgetPredicate(
      (widget) =>
          widget is Semantics && widget.properties.label == 'New Recipe icon',
      skipOffstage: false,
    );
    expect(
      find.descendant(
        of: fallbackIcon,
        matching: find.text('NR', skipOffstage: false),
        skipOffstage: false,
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: fallbackIcon,
        matching: find.byType(Icon, skipOffstage: false),
        skipOffstage: false,
      ),
      findsNothing,
    );

    await finishEditor(tester, harness);
  });

  testWidgets(
    'E01-E03 filter ordered real items and keep a new draft unsaved',
    (tester) async {
      final harness = EditorTestHarness();
      await pumpEditor(tester, harness);

      final craftableTop = tester.getTopLeft(
        find.byKey(EditorActionKeys.item('Clear Liquid Reagent')),
      );
      final leafTop = tester.getTopLeft(
        find.byKey(EditorActionKeys.item('Blood Wolf Blood')),
      );
      expect(craftableTop.dy, lessThan(leafTop.dy));

      await tester.enterText(editorForKey(EditorActionKeys.e01), 'Sunrise');
      await tester.pump(const Duration(milliseconds: 140));
      expect(find.byKey(EditorActionKeys.item('Sunrise Herb')), findsOneWidget);
      expect(
        find.byKey(EditorActionKeys.item('Clear Liquid Reagent')),
        findsNothing,
      );

      final editsBefore = harness.controller.active.state.value.recipeEdits;
      await tester.tap(find.byKey(EditorActionKeys.e03));
      await tester.pump();
      expect(editorForKey(EditorActionKeys.e04), findsOneWidget);
      expect(
        (tester.widget<EditableText>(
          editorForKey(EditorActionKeys.e04),
        )).controller.text,
        'New Recipe',
      );
      expect(
        find.descendant(
          of: find.bySemanticsLabel('Recipe Editor draft form'),
          matching: find.byWidgetPredicate(
            (widget) => widget is Text && widget.data == 'New Recipe',
          ),
        ),
        findsOneWidget,
      );
      expect(find.text('New draft'), findsNothing);
      expect(find.text('Base Items'), findsWidgets);
      expect(
        tester.widget<AppButton>(find.byKey(EditorActionKeys.e18)).onPressed,
        isNotNull,
      );
      expect(
        tester.widget<AppButton>(find.byKey(EditorActionKeys.e12)).onPressed,
        isNotNull,
      );
      await tester.enterText(editorForKey(EditorActionKeys.e04), '');
      await tester.tap(find.byKey(EditorActionKeys.e17));
      await tester.pump();
      expect(find.textContaining('Enter a nonempty recipe name'), findsNothing);
      expect(
        harness.controller.active.state.value.recipeEdits,
        same(editsBefore),
      );
      await finishEditor(tester, harness);
    },
    timeout: const Timeout(Duration(seconds: 10)),
  );

  testWidgets('fresh-draft host API accepts Inventory category navigation', (
    tester,
  ) async {
    final harness = EditorTestHarness();
    await pumpEditor(tester, harness, size: const Size(1500, 940));

    harness.session.openFreshDraft(
      mode: CraftMode.alchemy,
      initialCategory: '  Expedition   Kit  ',
    );
    await tester.pump();

    expect(editorForSemantics('Custom recipe category'), findsOneWidget);
    expect(
      tester
          .widget<EditableText>(editorForSemantics('Custom recipe category'))
          .controller
          .text,
      'Expedition Kit',
    );
    expect(harness.controller.active.state.value.recipeEdits, isEmpty);
    await finishEditor(tester, harness);
  });

  testWidgets(
    'bundled market fallback and selected editor actions match Avalonia',
    (tester) async {
      final catalog = const BundledCatalogParser().parse(
        File('assets/data/app-data.json').readAsStringSync(),
      );
      final base = inventoryDocument(showDeleteTools: true);
      final harness = EditorTestHarness(
        catalog: catalog,
        initialState: base.copyWith(
          alchemy: base.alchemy.copyWith(
            target: 'Harmony Draught - Edania',
            view: 'editor',
          ),
        ),
      );
      await pumpEditor(tester, harness, size: const Size(1500, 940));

      expect(
        tester
            .widget<EditableText>(editorForKey(EditorActionKeys.e06))
            .controller
            .text,
        '1407',
      );
      expect(
        tester.widget<AppButton>(find.byKey(EditorActionKeys.e18)).onPressed,
        isNotNull,
      );
      expect(
        tester.widget<AppButton>(find.byKey(EditorActionKeys.e12)).onPressed,
        isNotNull,
      );
      await tester.tap(find.byKey(EditorActionKeys.e12));
      await tester.pump();
      expect(find.textContaining('staged for Save'), findsOneWidget);
      await finishEditor(tester, harness);
    },
  );

  testWidgets('saving another recipe preserves the Planner target', (
    tester,
  ) async {
    final harness = EditorTestHarness();
    await pumpEditor(tester, harness, size: const Size(1500, 940));

    final targetBefore = harness.controller.active.state.value.target;
    final marketBefore = harness.controller.active.state.value.market.selected;
    await tester.tap(find.byKey(EditorActionKeys.item('Pure Powder Reagent')));
    await tester.pump();
    await tester.tap(find.byKey(EditorActionKeys.e17));
    await _waitForEditorWork(tester);

    final state = harness.controller.active.state.value;
    expect(state.target, targetBefore);
    expect(state.market.selected, marketBefore);
    expect(find.text('Pure Powder Reagent saved.'), findsNothing);
    expect(
      harness.transactionNotices.single.message,
      'Pure Powder Reagent saved.',
    );
    expect(
      find.textContaining("Instance of '_ValidatedEditorDraft'"),
      findsNothing,
    );
    await finishEditor(tester, harness);
  });

  testWidgets(
    'E02 E04-E10 E17 deep save preserves extensions and migrates every key',
    (tester) async {
      final harness = EditorTestHarness(initialState: editorDeepDocument());
      await pumpEditor(tester, harness, size: const Size(1500, 940));

      expect(
        tester
            .widget<EditableText>(editorForKey(EditorActionKeys.e06))
            .controller
            .text,
        '999999999999999999999999999',
      );
      expect(
        tester
            .widget<EditableText>(
              editorForKey(EditorActionKeys.ingredientQuantity(0)),
            )
            .controller
            .text,
        '2.5',
      );

      await tester.enterText(
        editorForKey(EditorActionKeys.e04),
        'Verdant Liquid Reagent',
      );
      await tester.enterText(editorForKey(EditorActionKeys.e05), '2,25');
      await tester.enterText(editorForSemantics('Recipe vendor'), 'Dalishain');
      await tester.enterText(editorForSemantics('Recipe NPC price'), '12,5');
      await tester.enterText(
        editorForSemantics('Recipe source location'),
        'Velia',
      );
      await tester.enterText(
        editorForSemantics('Recipe source note'),
        'Craft beside an alchemy tool.',
      );
      await tester.enterText(
        editorForSemantics('Recipe search keywords'),
        'verdant catalyst',
      );
      await tester.tap(find.byKey(EditorActionKeys.type('processing')));
      await tester.pump();
      expect(find.byKey(EditorActionKeys.e09), findsOneWidget);
      await tester.tap(find.byKey(EditorActionKeys.e09));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Grinding').last);
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(EditorActionKeys.e17));
      await tester.pumpAndSettle();

      final state = harness.controller.active.state.value;
      final recipe = state.recipeEdits['Verdant Liquid Reagent'];
      expect(recipe, isNotNull);
      expect(recipe!.baseOutput, 2.25);
      expect(recipe.type, 'processing');
      expect(recipe.method, 'Grinding');
      expect(recipe.outputMinimum, isNull);
      expect(recipe.outputMaximum, isNull);
      expect(recipe.marketId, '999999999999999999999999999');
      expect(recipe.extensions['futureRecipeRule'], <String, Object?>{
        'enabled': true,
      });
      expect(recipe.ingredients.single.options, <String>[
        'Sunrise Herb',
        'Silver Azalea',
        'Verdant Liquid Reagent',
      ]);
      expect(recipe.ingredients.single.substituteGroup, 'wild-herb');
      expect(recipe.ingredients.single.substituteRatios, <String, double>{
        'Sunrise Herb': 1,
        'Silver Azalea': 1.5,
        'Verdant Liquid Reagent': 2,
      });
      expect(
        recipe.ingredients.single.extensions['futureIngredientRule'],
        <String, Object?>{'rank': 7},
      );
      expect(
        state
            .ingredientMeta['Verdant Liquid Reagent']
            ?.extensions['futureMetaRule'],
        <String, Object?>{'color': 'verdant'},
      );
      expect(state.target, 'Verdant Liquid Reagent');
      expect(state.inventory['Verdant Liquid Reagent'], 9);
      expect(state.favoriteRecipes, contains('Verdant Liquid Reagent'));
      expect(state.market.prices['Verdant Liquid Reagent'], 12500);
      expect(state.market.stock['Verdant Liquid Reagent'], 44);
      expect(state.market.selected, 'Verdant Liquid Reagent');
      expect(state.completedSteps, contains('Verdant Liquid Reagent'));
      expect(
        state.recipeEdits['Custom Elixir']?.ingredients.single.name,
        'Verdant Liquid Reagent',
      );
      expect(
        state.substituteChoices.keys.single,
        contains('Verdant Liquid Reagent'),
      );
      expect(
        state.ingredientGrades.keys.single,
        contains('Verdant Liquid Reagent'),
      );
      expect(state.extensions['futureModeRule'], <String, Object?>{
        'kept': true,
      });
      expect(state.recipeEdits['Clear Liquid Reagent'], isNull);
      expect(harness.transactionNotices.single.operation, 'rename-recipe');
      await finishEditor(tester, harness);
    },
  );

  testWidgets(
    'E05 processing output edits discard stale bounds and change the plan',
    (tester) async {
      final base = inventoryDocument(showDeleteTools: true);
      final harness = EditorTestHarness(
        initialState: base.copyWith(
          activeMode: CraftMode.processing,
          processing: base.processing.copyWith(
            target: 'Wheat Flour',
            want: 10,
            view: 'editor',
          ),
        ),
      );
      await pumpEditor(tester, harness, size: const Size(1500, 940));

      final before = harness.controller.active.plan.value.steps.single;
      expect(before.count, 10);
      expect(before.produced, 10);

      await tester.enterText(editorForKey(EditorActionKeys.e05), '2');
      await tester.tap(find.byKey(EditorActionKeys.e17));
      await _waitForEditorWork(tester);

      final saved =
          harness.controller.active.state.value.recipeEdits['Wheat Flour'];
      expect(saved, isNotNull);
      expect(saved!.baseOutput, 2);
      expect(saved.outputMinimum, isNull);
      expect(saved.outputMaximum, isNull);
      final after = harness.controller.active.plan.value.steps.single;
      expect(after.count, 2);
      expect(after.produced, 10);
      await finishEditor(tester, harness);
    },
  );

  testWidgets('E10 processing metadata edits preserve curated output bounds', (
    tester,
  ) async {
    final base = inventoryDocument(showDeleteTools: true);
    final harness = EditorTestHarness(
      initialState: base.copyWith(
        activeMode: CraftMode.processing,
        processing: base.processing.copyWith(
          target: 'Wheat Flour',
          want: 10,
          view: 'editor',
        ),
      ),
    );
    await pumpEditor(tester, harness, size: const Size(1500, 940));

    await tester.enterText(
      editorForSemantics('Recipe source note'),
      'Ground from grain.',
    );
    await tester.tap(find.byKey(EditorActionKeys.e17));
    await _waitForEditorWork(tester);

    final saved =
        harness.controller.active.state.value.recipeEdits['Wheat Flour'];
    expect(saved, isNotNull);
    expect(saved!.baseOutput, 1);
    expect(saved.outputMinimum, 1);
    expect(saved.outputMaximum, 1);
    final plan = harness.controller.active.plan.value.steps.single;
    expect(plan.count, 10);
    expect(plan.produced, 10);
    await finishEditor(tester, harness);
  });

  testWidgets('E13-E17 validate numbers and edit exact ingredient rows', (
    tester,
  ) async {
    final harness = EditorTestHarness();
    await pumpEditor(tester, harness, size: const Size(1500, 940));

    await tester.tap(find.byKey(EditorActionKeys.e03));
    await tester.pump();
    await tester.enterText(
      editorForKey(EditorActionKeys.e04),
      'Field Catalyst',
    );
    await tester.enterText(editorForKey(EditorActionKeys.e05), '0');
    await tester.tap(find.byKey(EditorActionKeys.e17));
    await tester.pump();
    expect(find.textContaining('Base output must'), findsOneWidget);
    expect(
      harness.controller.active.state.value.recipeEdits,
      isNot(contains('Field Catalyst')),
    );

    await tester.enterText(editorForKey(EditorActionKeys.e05), '1.5');
    await tester.enterText(
      editorForKey(EditorActionKeys.ingredientItem(0)),
      'Sunrise Herb',
    );
    await tester.pump();
    final exactIngredient = find
        .ancestor(of: find.text('Sunrise Herb'), matching: find.byType(InkWell))
        .hitTestable();
    expect(exactIngredient, findsOneWidget);
    await tester.tap(exactIngredient);
    await tester.enterText(
      editorForKey(EditorActionKeys.ingredientQuantity(0)),
      '3',
    );
    await tester.ensureVisible(find.byKey(EditorActionKeys.e15));
    await tester.pump();
    await tester.tap(find.byKey(EditorActionKeys.e15));
    await tester.pump();
    await tester.ensureVisible(find.byKey(EditorActionKeys.ingredientItem(1)));
    await tester.pump();
    await tester.enterText(
      editorForKey(EditorActionKeys.ingredientItem(1)),
      'Salt',
    );
    await tester.pump();
    await tester.tap(find.text('Salt').last);
    await tester.enterText(
      editorForKey(EditorActionKeys.ingredientQuantity(1)),
      '2,5',
    );
    await tester.tap(find.byKey(EditorActionKeys.removeIngredient(0)));
    await tester.pump();

    expect(editorForKey(EditorActionKeys.ingredientItem(0)), findsOneWidget);
    expect(
      tester
          .widget<EditableText>(
            editorForKey(EditorActionKeys.ingredientItem(0)),
          )
          .controller
          .text,
      'Salt',
    );
    await tester.ensureVisible(find.byKey(EditorActionKeys.e17));
    await tester.pump();
    await tester.tap(find.byKey(EditorActionKeys.e17));
    await _waitForEditorWork(tester);

    final saved =
        harness.controller.active.state.value.recipeEdits['Field Catalyst'];
    expect(saved, isNotNull);
    expect(saved!.ingredients, hasLength(1));
    expect(saved.ingredients.single.name, 'Salt');
    expect(saved.ingredients.single.quantity, 2.5);
    await finishEditor(tester, harness);
  });

  testWidgets('E11-E12 stage, save, and physically remove normalized icons', (
    tester,
  ) async {
    final harness = EditorTestHarness();
    final source = File(
      '${harness.applicationDirectory.path}${Platform.pathSeparator}source.png',
    )..writeAsBytesSync(onePixelPngBytes);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_windowChannel, (call) async {
          if (call.method == 'pickOpenFile') return source.path;
          return null;
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(_windowChannel, null),
    );
    await pumpEditor(tester, harness, size: const Size(1500, 940));

    await tester.tap(find.byKey(EditorActionKeys.e11));
    for (var attempt = 0; attempt < 30; attempt++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();
      if (find.text('Working…').evaluate().isEmpty) break;
    }
    expect(find.textContaining('normalized'), findsWidgets);
    expect(
      harness.controller.active.state.value.customIcons,
      isNot(contains('Clear Liquid Reagent')),
    );

    await tester.tap(find.byKey(EditorActionKeys.e17));
    await _waitForEditorWork(tester);
    final reference = harness
        .controller
        .active
        .state
        .value
        .customIcons['Clear Liquid Reagent'];
    expect(reference, isNotNull);
    final normalizedFile = File(
      '${harness.applicationDirectory.path}${Platform.pathSeparator}${reference!.relativePath.replaceAll('/', Platform.pathSeparator)}',
    );
    expect(normalizedFile.existsSync(), isTrue);

    await tester.tap(find.byKey(EditorActionKeys.e12));
    await tester.pump();
    expect(
      harness.controller.active.state.value.customIcons,
      contains('Clear Liquid Reagent'),
    );
    await tester.tap(find.byKey(EditorActionKeys.e17));
    await _waitForEditorWork(tester);
    expect(
      harness.controller.active.state.value.customIcons,
      isNot(contains('Clear Liquid Reagent')),
    );
    await tester.runAsync(harness.controller.flush);
    await tester.pump();
    for (
      var attempt = 0;
      attempt < 20 && normalizedFile.existsSync();
      attempt++
    ) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 25)),
      );
      await tester.pump();
    }
    expect(normalizedFile.existsSync(), isFalse);
    await finishEditor(tester, harness);
  });

  testWidgets('E17 write failure rolls the recipe back without success', (
    tester,
  ) async {
    final harness = EditorTestHarness(
      initialState: editorDeepDocument(),
      saveState: (_) async =>
          throw const FileSystemException('injected editor save failure'),
    );
    await pumpEditor(tester, harness, size: const Size(1500, 940));

    await tester.enterText(
      editorForKey(EditorActionKeys.e04),
      'Unpersisted Reagent',
    );
    await tester.tap(find.byKey(EditorActionKeys.e17));
    await _waitForEditorWork(tester);

    expect(
      harness.controller.active.state.value.recipeEdits,
      contains('Clear Liquid Reagent'),
    );
    expect(
      harness.controller.active.state.value.recipeEdits,
      isNot(contains('Unpersisted Reagent')),
    );
    expect(harness.transactionNotices, isEmpty);
    expect(find.textContaining('Recipe save failed'), findsOneWidget);
    expect(find.textContaining('injected editor save failure'), findsOneWidget);
    await finishEditor(tester, harness);
  });

  testWidgets('E18 write failure keeps the item and offers no undo', (
    tester,
  ) async {
    final harness = EditorTestHarness(
      saveState: (_) async =>
          throw const FileSystemException('injected editor delete failure'),
    );
    await pumpEditor(tester, harness, size: const Size(1500, 940));

    await tester.tap(find.byKey(EditorActionKeys.e18));
    await _waitForEditorWork(tester);

    expect(
      harness.controller.active.state.value.recipeEdits,
      isNot(contains('Clear Liquid Reagent')),
    );
    expect(harness.controller.active.state.value.hiddenItems, isEmpty);
    expect(harness.transactionNotices, isEmpty);
    expect(harness.undoOffers, isEmpty);
    expect(find.textContaining('Could not remove'), findsOneWidget);
    expect(
      find.textContaining('injected editor delete failure'),
      findsOneWidget,
    );
    await finishEditor(tester, harness);
  });

  testWidgets('E18 confirms, reports dependency conflicts, and restores undo', (
    tester,
  ) async {
    final initial = editorDeepDocument();
    final harness = EditorTestHarness(initialState: initial)
      ..deleteApprovals.addAll(<bool>[false, true, true]);
    await pumpEditor(tester, harness, size: const Size(1500, 940));

    await tester.tap(find.byKey(EditorActionKeys.e18));
    await tester.pump();
    expect(
      harness.controller.active.state.value.target,
      'Clear Liquid Reagent',
    );

    await tester.tap(find.byKey(EditorActionKeys.e18));
    await tester.pump();
    expect(find.textContaining('Custom Elixir'), findsWidgets);
    expect(harness.undoOffers, isEmpty);

    harness.controller.active.updateState((state) {
      final edits = Map<String, RecipeState?>.of(state.recipeEdits)
        ..remove('Custom Elixir');
      return state.copyWith(recipeEdits: edits);
    }, immediate: true);
    await tester.pump();
    await tester.tap(find.byKey(EditorActionKeys.e18));
    await tester.pumpAndSettle();
    expect(
      harness.controller.active.state.value.recipeEdits['Clear Liquid Reagent'],
      isNull,
    );
    expect(harness.undoOffers, hasLength(1));
    expect(
      find.textContaining('Undo is available for this session'),
      findsNothing,
    );
    expect(find.text(harness.undoOffers.single.message), findsNothing);

    final undo = await harness.undoOffers.single.undo();
    await tester.pumpAndSettle();
    expect(undo.restored, isTrue);
    expect(
      harness.controller.active.state.value.recipeEdits['Clear Liquid Reagent'],
      isNotNull,
    );
    expect(harness.undoResults.single.restored, isTrue);
    await finishEditor(tester, harness);
  });

  testWidgets('responsive semantic form renders at both launch baselines', (
    tester,
  ) async {
    for (final size in const <Size>[Size(1200, 752), Size(1500, 940)]) {
      final harness = EditorTestHarness();
      await pumpEditor(tester, harness, size: size);

      final browser = find.bySemanticsLabel('Recipe Editor item browser');
      final detail = find.bySemanticsLabel('Recipe Editor draft form');
      final browserBounds = tester.getRect(browser);
      final detailBounds = tester.getRect(detail);

      expect(browserBounds.width, 350);
      expect(detailBounds.left - browserBounds.right, 20);
      expect(detailBounds.top, browserBounds.top);
      expect(find.text('Items'), findsNothing);
      expect(editorForSemantics('Search Recipe Editor items'), findsOneWidget);
      expect(editorForSemantics('Recipe name'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await finishEditor(tester, harness);
    }
  });

  testWidgets(
    'Ledger keeps both editor panes scrollable without visible scrollbars',
    (tester) async {
      final harness = EditorTestHarness();
      await pumpEditor(
        tester,
        harness,
        size: const Size(1200, 752),
        spec: IlluminatedLedgerSpec.theme,
      );

      final browser = find.bySemanticsLabel('Recipe Editor item browser');
      final itemList = find.byKey(EditorActionKeys.e02);
      final formScrollView = find.byType(SingleChildScrollView);
      final visibleScrollbar = find.byWidgetPredicate(
        (widget) => widget is RawScrollbar,
      );
      expect(itemList, findsOneWidget);
      expect(formScrollView, findsOneWidget);
      expect(visibleScrollbar, findsNothing);

      final browserRect = tester.getRect(browser);
      final newRecipeRect = tester.getRect(find.byKey(EditorActionKeys.e03));
      expect(newRecipeRect.width, closeTo(browserRect.width - 24, .01));

      final saveBefore = tester.getRect(find.byKey(EditorActionKeys.e17));
      final formViewport = tester.getRect(formScrollView);
      final recipePanel = find.byWidgetPredicate(
        (widget) =>
            widget is AppSurface &&
            widget.semanticLabel == 'Recipe editor section',
      );
      final recipeBefore = tester.getRect(recipePanel);
      expect(formViewport.top - saveBefore.bottom, closeTo(24, .01));
      expect(formViewport.top, closeTo(recipeBefore.top, .01));

      final itemScrollable = find.descendant(
        of: itemList,
        matching: find.byType(Scrollable),
      );
      expect(itemScrollable, findsWidgets);
      final itemPosition = tester
          .state<ScrollableState>(itemScrollable.first)
          .position;
      expect(itemPosition.maxScrollExtent, greaterThan(0));
      final itemBefore = itemPosition.pixels;
      await tester.drag(itemList, const Offset(0, -160));
      await tester.pumpAndSettle();
      expect(itemPosition.pixels, greaterThan(itemBefore));

      final formScrollable = find.descendant(
        of: formScrollView,
        matching: find.byType(Scrollable),
      );
      expect(formScrollable, findsWidgets);
      final formPosition = tester
          .state<ScrollableState>(formScrollable.first)
          .position;
      expect(formPosition.maxScrollExtent, greaterThan(0));
      final formBefore = formPosition.pixels;
      await tester.drag(formScrollView, const Offset(0, -240));
      await tester.pumpAndSettle();
      expect(formPosition.pixels, greaterThan(formBefore));
      expect(tester.getRect(find.byKey(EditorActionKeys.e17)), saveBefore);
      expect(tester.getRect(recipePanel).top, lessThan(recipeBefore.top));
      expect(visibleScrollbar, findsNothing);
      await finishEditor(tester, harness);
    },
  );

  testWidgets(
    'Ledger field focus preserves geometry and uses the measured text inset',
    (tester) async {
      final harness = EditorTestHarness();
      await pumpEditor(
        tester,
        harness,
        size: const Size(1200, 752),
        spec: IlluminatedLedgerSpec.theme,
      );

      final nameField = find.descendant(
        of: find.byKey(EditorActionKeys.e04),
        matching: find.byType(AnimatedContainer),
      );
      final textFieldFinder = find.descendant(
        of: find.byKey(EditorActionKeys.e04),
        matching: find.byType(TextField),
      );
      final beforeRect = tester.getRect(nameField);
      final beforeDecoration =
          tester.widget<AnimatedContainer>(nameField).decoration!
              as BoxDecoration;
      expect(beforeDecoration.border!.top.width, 1);
      expect(
        beforeDecoration.color,
        IlluminatedLedgerSpec.palette.surfaceRaised.withAlpha(212),
      );

      final textField = tester.widget<TextField>(textFieldFinder);
      expect(textField.textAlignVertical, TextAlignVertical.center);
      expect(
        textField.decoration!.contentPadding,
        const EdgeInsets.fromLTRB(10, 12, 10, 0),
      );
      final nameLabel = tester.widget<Text>(
        find.descendant(
          of: find.byKey(EditorActionKeys.e04),
          matching: find.text('NAME'),
        ),
      );
      expect(nameLabel.style!.color, const Color(0xFF806633));

      await tester.tap(editorForKey(EditorActionKeys.e04));
      await tester.pump(const Duration(milliseconds: 100));
      final focusedDecoration =
          tester.widget<AnimatedContainer>(nameField).decoration!
              as BoxDecoration;
      expect(tester.getRect(nameField), beforeRect);
      expect(focusedDecoration.color, const Color(0xFFFFFCF4));
      expect(focusedDecoration.border!.top.color, const Color(0xFF0078D4));
      expect(focusedDecoration.border!.top.width, 2);

      // A real Windows resize can rebuild the responsive field subtree while
      // the supplied FocusNode remains focused. The visual state must be
      // derived from that node instead of falling back to an unfocused frame.
      tester.view.physicalSize = const Size(1500, 940);
      await tester.pumpAndSettle();
      final resizedNameField = find.descendant(
        of: find.byKey(EditorActionKeys.e04),
        matching: find.byType(AnimatedContainer),
      );
      final resizedDecoration =
          tester.widget<AnimatedContainer>(resizedNameField).decoration!
              as BoxDecoration;
      expect(resizedDecoration.color, const Color(0xFFFFFCF4));
      expect(resizedDecoration.border!.top.color, const Color(0xFF0078D4));
      expect(resizedDecoration.border!.top.width, 2);
      expect(tester.takeException(), isNull);
      await finishEditor(tester, harness);
    },
  );

  testWidgets(
    'Standard editor fields use authored heights and optical text inset',
    (tester) async {
      final harness = EditorTestHarness();
      await pumpEditor(tester, harness, size: const Size(1500, 940));

      Finder materialInside(Finder owner) => find
          .descendant(of: owner, matching: find.byType(AnimatedContainer))
          .first;
      Finder textFieldInside(Finder owner) =>
          find.descendant(of: owner, matching: find.byType(TextField)).first;
      RenderEditable editableInside(Finder owner) {
        final matches = <RenderEditable>[];
        void visit(RenderObject object) {
          if (object is RenderEditable) matches.add(object);
          object.visitChildren(visit);
        }

        visit(tester.renderObject(materialInside(owner)));
        return matches.single;
      }

      final nameOwner = find.byKey(EditorActionKeys.e04);
      final itemOwner = find.byKey(EditorActionKeys.ingredientItem(0));
      final quantityOwner = find.byKey(EditorActionKeys.ingredientQuantity(0));
      await tester.ensureVisible(itemOwner);
      await tester.pumpAndSettle();

      final cases = <(Finder, double, double, double)>[
        (nameOwner, 32, 8, 1),
        (itemOwner, 38, 11.5, 1.5),
        (quantityOwner, 38, 11.5, 1.5),
      ];
      for (final (owner, height, topInset, targetCenter) in cases) {
        expect(tester.getSize(materialInside(owner)).height, height);
        final field = tester.widget<TextField>(textFieldInside(owner));
        expect(field.textAlignVertical, TextAlignVertical.center);
        expect(
          field.decoration!.contentPadding,
          EdgeInsets.fromLTRB(10, topInset, 10, 0),
        );
        final editableFinder = find
            .descendant(of: owner, matching: find.byType(EditableText))
            .first;
        final editableWidget = tester.widget<EditableText>(editableFinder);
        final editable = editableInside(owner);
        final selectionBox = editable
            .getBoxesForSelection(
              TextSelection(
                baseOffset: 0,
                extentOffset: editableWidget.controller.text.length,
              ),
            )
            .first;
        final selectionCenter = editable
            .localToGlobal(
              Offset(0, (selectionBox.top + selectionBox.bottom) / 2),
            )
            .dy;
        final hostCenter = tester.getRect(materialInside(owner)).center.dy;
        expect(
          selectionCenter - hostCenter,
          closeTo(targetCenter, 0.75),
          reason:
              '${editableWidget.controller.text} optical center in '
              '${height}px host',
        );
      }
      expect(tester.takeException(), isNull);
      await finishEditor(tester, harness);
    },
  );

  testWidgets(
    'ingredient item and quantity fields share rendered geometry at both widths',
    (tester) async {
      for (final testCase in <({Size size, ThemeSpec spec, double height})>[
        (size: const Size(1200, 752), spec: StandardSpec.theme, height: 38),
        (size: const Size(1500, 940), spec: StandardSpec.theme, height: 38),
        (
          size: const Size(1200, 752),
          spec: IlluminatedLedgerSpec.theme,
          height: 34,
        ),
        (
          size: const Size(1500, 940),
          spec: IlluminatedLedgerSpec.theme,
          height: 34,
        ),
      ]) {
        final harness = EditorTestHarness();
        await pumpEditor(
          tester,
          harness,
          size: testCase.size,
          spec: testCase.spec,
        );

        final itemOwner = find.byKey(EditorActionKeys.ingredientItem(0));
        final quantityOwner = find.byKey(
          EditorActionKeys.ingredientQuantity(0),
        );
        await tester.ensureVisible(itemOwner);
        await tester.pumpAndSettle();

        Finder renderedField(Finder owner) => find
            .descendant(of: owner, matching: find.byType(AnimatedContainer))
            .first;
        RenderEditable editableInside(Finder owner) {
          final matches = <RenderEditable>[];
          void visit(RenderObject object) {
            if (object is RenderEditable) matches.add(object);
            object.visitChildren(visit);
          }

          visit(tester.renderObject(renderedField(owner)));
          return matches.single;
        }

        double opticalCenterOffset(Finder owner) {
          final editableWidget = tester.widget<EditableText>(
            find
                .descendant(of: owner, matching: find.byType(EditableText))
                .first,
          );
          final editable = editableInside(owner);
          final box = editable
              .getBoxesForSelection(
                TextSelection(
                  baseOffset: 0,
                  extentOffset: editableWidget.controller.text.length,
                ),
              )
              .first;
          final center = editable.localToGlobal(
            Offset(0, (box.top + box.bottom) / 2),
          );
          return center.dy - tester.getRect(renderedField(owner)).center.dy;
        }

        final itemRect = tester.getRect(renderedField(itemOwner));
        final quantityRect = tester.getRect(renderedField(quantityOwner));
        expect(itemRect.height, testCase.height);
        expect(quantityRect.height, testCase.height);
        expect(quantityRect.top, closeTo(itemRect.top, .01));
        expect(
          opticalCenterOffset(quantityOwner),
          closeTo(opticalCenterOffset(itemOwner), .75),
        );
        expect(tester.takeException(), isNull);
        await finishEditor(tester, harness);
      }
    },
  );

  testWidgets('Ledger header keeps draft meta beside actions at both widths', (
    tester,
  ) async {
    final wide = EditorTestHarness();
    await pumpEditor(
      tester,
      wide,
      size: const Size(1500, 940),
      spec: IlluminatedLedgerSpec.theme,
    );
    await tester.tap(find.byKey(EditorActionKeys.e03));
    await tester.pump();
    Finder headerMeta() => find.byWidgetPredicate(
      (widget) =>
          widget is Text &&
          widget.data == 'New Recipe' &&
          widget.style?.fontSize == 13 &&
          widget.style?.fontWeight == FontWeight.w600,
    );
    var meta = headerMeta();
    var metaRect = tester.getRect(meta);
    var saveRect = tester.getRect(find.byKey(EditorActionKeys.e17));
    expect(saveRect.left - metaRect.right, closeTo(8, .01));
    await finishEditor(tester, wide);

    final compact = EditorTestHarness();
    await pumpEditor(
      tester,
      compact,
      size: const Size(1000, 752),
      spec: IlluminatedLedgerSpec.theme,
    );
    await tester.tap(find.byKey(EditorActionKeys.e03));
    await tester.pump();
    meta = headerMeta();
    final title = find.text('RECIPE EDITOR');
    metaRect = tester.getRect(meta);
    saveRect = tester.getRect(find.byKey(EditorActionKeys.e17));
    final titleRect = tester.getRect(title);
    expect(metaRect.top, greaterThan(titleRect.bottom));
    expect(metaRect.center.dy, closeTo(saveRect.center.dy, .01));
    expect(metaRect.left, closeTo(titleRect.left, .01));
    expect(metaRect.right, lessThan(saveRect.left));
    await finishEditor(tester, compact);
  });

  testWidgets(
    'Ledger type panel wraps 2+2+1 below 1480 and retains its wide layout',
    (tester) async {
      const types = <String>[
        'alchemy',
        'simple_alchemy',
        'cooking',
        'processing',
        'gathered',
      ];
      Rect recipePanelRect() => tester.getRect(
        find.byWidgetPredicate(
          (widget) =>
              widget is AppSurface &&
              widget.semanticLabel == 'Recipe editor section',
        ),
      );
      Rect fieldRect(Key key) => tester.getRect(
        find.descendant(
          of: find.byKey(key),
          matching: find.byType(AnimatedContainer),
        ),
      );
      Rect categoryControlRect() => tester.getRect(
        find.descendant(
          of: find.byKey(EditorActionKeys.e08),
          matching: find.byType(AppSelect<String>),
        ),
      );
      Rect methodControlRect() => tester.getRect(
        find.descendant(
          of: find.byKey(EditorActionKeys.e09),
          matching: find.byType(AppSelect<String>),
        ),
      );

      final compact = EditorTestHarness();
      await pumpEditor(
        tester,
        compact,
        size: const Size(1200, 752),
        spec: IlluminatedLedgerSpec.theme,
      );

      final compactPanel = find.byKey(EditorActionKeys.e07);
      expect(tester.getSize(compactPanel).width, 324);
      final compactButtons = <Rect>[
        for (final type in types)
          tester.getRect(find.byKey(EditorActionKeys.type(type))),
      ];
      expect(compactButtons[0].top, compactButtons[1].top);
      expect(compactButtons[2].top, compactButtons[3].top);
      expect(compactButtons[2].top, greaterThan(compactButtons[0].bottom));
      expect(compactButtons[4].top, greaterThan(compactButtons[2].bottom));
      expect(compactButtons[2].left, compactButtons[0].left);
      expect(compactButtons[4].left, compactButtons[0].left);
      for (final button in compactButtons) {
        expect(button.height, 42);
      }
      expect(compactButtons[2].top - compactButtons[0].top, 50);
      expect(compactButtons[4].top - compactButtons[2].top, 50);

      final recipePanel = recipePanelRect();
      final nameField = fieldRect(EditorActionKeys.e04);
      final outputField = fieldRect(EditorActionKeys.e05);
      final categoryControl = categoryControlRect();
      final methodControl = methodControlRect();
      expect(recipePanel.height, closeTo(474, 1));
      expect(nameField.top - recipePanel.top, closeTo(59, 1));
      expect(outputField.top - nameField.top, closeTo(61, 1));
      expect(compactButtons[0].top - outputField.top, closeTo(61, 1));
      expect(categoryControl.top - compactButtons[0].top, closeTo(177, 1));
      expect(methodControl.top, greaterThan(categoryControl.bottom));
      expect(recipePanel.bottom - methodControl.bottom, closeTo(12, 1));
      await finishEditor(tester, compact);

      final wide = EditorTestHarness();
      await pumpEditor(
        tester,
        wide,
        size: const Size(1500, 940),
        spec: IlluminatedLedgerSpec.theme,
      );

      final widePanel = find.byKey(EditorActionKeys.e07);
      expect(tester.getSize(widePanel).width, greaterThan(324));
      final wideButtons = <Rect>[
        for (final type in types)
          tester.getRect(find.byKey(EditorActionKeys.type(type))),
      ];
      expect(wideButtons[0].top, wideButtons[1].top);
      expect(wideButtons[1].top, wideButtons[2].top);
      expect(wideButtons[2].top, wideButtons[3].top);
      expect(wideButtons[4].top, greaterThan(wideButtons[0].bottom));
      for (final button in wideButtons) {
        expect(button.height, 42);
      }
      expect(wideButtons[4].top - wideButtons[0].top, 50);

      final wideRecipePanel = recipePanelRect();
      final wideNameField = fieldRect(EditorActionKeys.e04);
      final wideOutputField = fieldRect(EditorActionKeys.e05);
      final wideCategoryControl = categoryControlRect();
      expect(wideNameField.top - wideRecipePanel.top, closeTo(59, 1));
      expect(wideOutputField.top - wideNameField.top, closeTo(61, 1));
      expect(wideButtons[0].top - wideOutputField.top, closeTo(61, 1));
      expect(wideCategoryControl.top - wideButtons[0].top, closeTo(127, 1));
      await finishEditor(tester, wide);

      final standard = EditorTestHarness();
      await pumpEditor(tester, standard, size: const Size(1200, 752));
      expect(
        tester.getSize(find.byKey(EditorActionKeys.e07)).width,
        greaterThan(324),
      );
      await finishEditor(tester, standard);
    },
  );

  testWidgets(
    'dense editor browser breathes while Sakura type labels stay contained',
    (tester) async {
      const cases = <(ThemeSpec, Size)>[
        (IlluminatedLedgerSpec.theme, Size(1200, 752)),
        (IlluminatedLedgerSpec.theme, Size(1500, 940)),
        (SakuraNightGardenSpec.theme, Size(1200, 752)),
        (SakuraNightGardenSpec.theme, Size(1500, 940)),
      ];
      for (final testCase in cases) {
        final harness = EditorTestHarness();
        await pumpEditor(tester, harness, size: testCase.$2, spec: testCase.$1);

        final search = tester.getRect(find.byKey(EditorActionKeys.e01));
        final newRecipe = tester.getRect(find.byKey(EditorActionKeys.e03));
        final firstRecipe = tester.getRect(
          find.byKey(EditorActionKeys.item('Clear Liquid Reagent')),
        );
        expect(newRecipe.top - search.bottom, closeTo(6, .01));
        expect(firstRecipe.top - newRecipe.bottom, closeTo(8, .01));

        for (final entry in const <String, String>{
          'alchemy': 'Residence Alchemy',
          'simple_alchemy': 'Simple Alchemy',
          'cooking': 'Residence Cooking',
          'processing': 'Processing',
          'gathered': 'Base Item',
        }.entries) {
          final button = find.byKey(EditorActionKeys.type(entry.key));
          final buttonRect = tester.getRect(button);
          expect(buttonRect.size, const Size(154, 42));
          if (testCase.$1.isSakuraNightGarden) {
            final labelRect = tester.getRect(
              find.descendant(of: button, matching: find.text(entry.value)),
            );
            expect(labelRect.left, greaterThanOrEqualTo(buttonRect.left + 6));
            expect(labelRect.right, lessThanOrEqualTo(buttonRect.right - 6));
            expect(labelRect.top, greaterThan(buttonRect.top));
            expect(labelRect.bottom, lessThan(buttonRect.bottom));
          }
        }
        expect(tester.takeException(), isNull);
        await finishEditor(tester, harness);
      }
    },
  );

  testWidgets('200% text stacks the editor heading and flexible actions', (
    tester,
  ) async {
    final harness = EditorTestHarness();
    await pumpEditor(
      tester,
      harness,
      size: const Size(1500, 940),
      textScaler: TextScaler.linear(2),
    );

    final title = tester.getRect(find.text('Recipe Editor'));
    final save = tester.getRect(find.byKey(EditorActionKeys.e17));
    expect(save.top, greaterThan(title.bottom));
    expect(save.height, greaterThan(38));
    expect(tester.takeException(), isNull);
    await finishEditor(tester, harness);
  });
}

Future<void> _waitForEditorWork(WidgetTester tester) async {
  for (var attempt = 0; attempt < 60; attempt++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 25)),
    );
    await tester.pump();
    if (find.text('Working…').evaluate().isEmpty) return;
  }
}
