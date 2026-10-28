import 'dart:io';

import 'package:bdo_craft_planner_flutter/app/state/planner_application_controller.dart';
import 'package:bdo_craft_planner_flutter/data/catalog/bundled_catalog_parser.dart';
import 'package:bdo_craft_planner_flutter/data/catalog/catalog_repository.dart';
import 'package:bdo_craft_planner_flutter/domain/models/craft_mode.dart';
import 'package:bdo_craft_planner_flutter/domain/state/planner_state.dart';
import 'package:bdo_craft_planner_flutter/features/planner/planner_contracts.dart';
import 'package:bdo_craft_planner_flutter/features/recipe_book/recipe_book_controller.dart';
import 'package:bdo_craft_planner_flutter/features/recipe_book/recipe_book_item_info.dart';
import 'package:bdo_craft_planner_flutter/features/recipe_book/recipe_book_item_info_view.dart';
import 'package:bdo_craft_planner_flutter/visual/visual.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/application_test_harness.dart';
import 'recipe_book_test_support.dart';

const _inline = ValueKey('inline-item-facts');
const _card = ValueKey('existing-item-card');
const _facts = RecipeBookItemInfo(
  title: 'Reference title',
  kind: 'Reference category',
  summary: 'A concise description.',
  effects: ['All AP +5'],
  acquisitionNotes: ['Gather this material.'],
  uses: ['Used in a recipe.'],
  example: 'One example.',
  notes: ['A useful restriction.'],
);

void main() {
  for (final spec in RetainedThemeRegistry.themes) {
    for (final scale in [1.0, 2.0]) {
      testWidgets(
        '${spec.id} inline facts retain card typography and spacing at $scale',
        (tester) async {
          configureApplicationTestSurface(
            tester,
            const Size(1200, 2200),
            textScaleFactor: scale,
          );
          final environment = buildRecipeBookTestEnvironment();
          addTearDown(environment.dispose);
          final book = _book(environment);
          addTearDown(book.dispose);
          var inlineWidth = 408.0;
          Widget scene() => _host(
            spec,
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 440,
                  child: ItemReferenceCard(
                    key: _card,
                    controller: book,
                    mode: CraftMode.alchemy,
                    name: 'Clear Liquid Reagent',
                    info: _facts,
                    maxWidth: 440,
                    spec: spec,
                    icon: const SizedBox.square(dimension: 48),
                  ),
                ),
                const SizedBox(width: 32),
                SizedBox(
                  width: inlineWidth,
                  child: ItemReferenceSections(
                    key: _inline,
                    controller: book,
                    mode: CraftMode.alchemy,
                    name: 'Clear Liquid Reagent',
                    info: _facts,
                    spec: spec,
                  ),
                ),
              ],
            ),
          );
          await tester.pumpWidget(scene());
          await tester.pumpAndSettle();
          final original = find.byKey(_card);
          final inline = find.byKey(_inline);
          // The themed card border also consumes horizontal space. Match its
          // actual reading width rather than guessing that decoration inset.
          inlineWidth = tester
              .getSize(
                find.descendant(
                  of: original,
                  matching: find.text(_facts.summary),
                ),
              )
              .width;
          await tester.pumpWidget(scene());
          await tester.pumpAndSettle();
          expect(find.text(_facts.title), findsOneWidget);
          expect(find.text(_facts.kind), findsOneWidget);
          expect(
            find.descendant(of: inline, matching: find.byType(AppSurface)),
            findsNothing,
          );
          expect(
            find.descendant(
              of: inline,
              matching: find.byType(SingleChildScrollView),
            ),
            findsNothing,
          );
          final originalOrigin = tester.getTopLeft(
            find.descendant(of: original, matching: find.text('Description')),
          );
          final inlineOrigin = tester.getTopLeft(
            find.descendant(of: inline, matching: find.text('Description')),
          );
          for (final text in [
            'Description',
            _facts.summary,
            'Effects',
            ..._facts.effects,
            'How to Obtain',
            ..._facts.acquisitionNotes,
            'Used For',
            ..._facts.uses,
            'Example',
            _facts.example!,
            'Notes',
            ..._facts.notes,
          ]) {
            final a = find.descendant(of: original, matching: find.text(text));
            final b = find.descendant(of: inline, matching: find.text(text));
            expect(a, findsOneWidget);
            expect(b, findsOneWidget);
            expect(tester.widget<Text>(b).style, tester.widget<Text>(a).style);
            expect(tester.getSize(b), tester.getSize(a), reason: text);
            expect(
              ((tester.getTopLeft(b) - inlineOrigin) -
                      (tester.getTopLeft(a) - originalOrigin))
                  .distance,
              lessThan(0.000001),
              reason: text,
            );
          }
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox.shrink());
        },
      );
    }
  }

  testWidgets('empty inline facts collapse without a header or filler', (
    tester,
  ) async {
    final environment = buildRecipeBookTestEnvironment();
    addTearDown(environment.dispose);
    final book = _book(environment);
    addTearDown(book.dispose);
    const info = RecipeBookItemInfo(
      title: 'Unknown reward',
      kind: 'Item',
      summary: '  ',
      effects: [' '],
      acquisitionNotes: [' '],
      notes: [' '],
    );
    expect(info.hasBody, isTrue);
    await tester.pumpWidget(
      _host(
        StandardSpec.theme,
        SizedBox(
          width: 408,
          child: ItemReferenceSections(
            key: _inline,
            controller: book,
            mode: CraftMode.alchemy,
            name: info.title,
            info: info,
            spec: StandardSpec.theme,
          ),
        ),
      ),
    );
    expect(tester.getSize(find.byKey(_inline)).height, 0);
    expect(find.byType(Text), findsNothing);
    expect(find.byType(AppSurface), findsNothing);
    expect(tester.takeException(), isNull);

    // The original card retains its deliberate neutral-header/fallback state.
    await tester.pumpWidget(
      _host(
        StandardSpec.theme,
        ItemReferenceCard(
          controller: book,
          mode: CraftMode.alchemy,
          name: info.title,
          info: info,
          maxWidth: 440,
          spec: StandardSpec.theme,
          icon: const SizedBox.square(dimension: 48),
        ),
      ),
    );
    expect(find.text(info.title), findsOneWidget);
    expect(find.text('No source details recorded yet.'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('inline copy and default activation retain scoped behavior', (
    tester,
  ) async {
    final environment = buildRecipeBookTestEnvironment(
      includeRecipeVariants: true,
    );
    addTearDown(environment.dispose);
    final book = _book(environment);
    addTearDown(book.dispose);
    final mode = environment.application.active;
    final formula = recipeBookFormulas(
      mode.recipeDefinition('Clear Liquid Reagent'),
      mode: CraftMode.alchemy,
    ).last;
    final copied = <String>[];
    final events = <String>[];
    await tester.pumpWidget(
      _host(
        StandardSpec.theme,
        SizedBox(
          width: 440,
          child: _formulaSections(
            book,
            formula,
            onCopy: copied.add,
            onActivated: () {
              expect(book.lastRouteActivation, isNull);
              events.add('close');
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('item-reference-copy:Trace of Earth')),
    );
    expect(copied, ['Trace of Earth']);
    expect(book.lastRouteActivation, isNull);
    await tester.tap(find.text('Use recipe'));
    await tester.pumpAndSettle();
    expect(events, ['close']);
    expect(book.lastRouteActivation?.variantId, 'trace-route');
    expect(
      mode.state.value.recipeVariantChoices[formula.outputName],
      'trace-route',
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('host formula override does not duplicate default activation', (
    tester,
  ) async {
    final environment = buildRecipeBookTestEnvironment(
      includeRecipeVariants: true,
    );
    addTearDown(environment.dispose);
    final book = _book(environment);
    addTearDown(book.dispose);
    final mode = environment.application.active;
    final before = environment.application.documentSnapshot;
    final formula = recipeBookFormulas(
      mode.recipeDefinition('Clear Liquid Reagent'),
      mode: CraftMode.alchemy,
    ).last;
    final routed = <RecipeBookFormula>[];
    var defaultClosed = false;
    await tester.pumpWidget(
      _host(
        StandardSpec.theme,
        SizedBox(
          width: 440,
          child: _formulaSections(
            book,
            formula,
            onActivated: () => defaultClosed = true,
            onUseFormula: routed.add,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Use recipe'));
    await tester.pumpAndSettle();
    expect(routed, [same(formula)]);
    expect(defaultClosed, isFalse);
    expect(book.lastRouteActivation, isNull);
    expect(environment.application.documentSnapshot, same(before));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('bundled Maehwa facts keep the real liquor use and effects', (
    tester,
  ) async {
    configureApplicationTestSurface(tester, const Size(1200, 1400));
    final snapshot = (await tester.runAsync(() async {
      return const BundledCatalogParser().parse(
        await File('assets/data/app-data.json').readAsString(),
      );
    }))!;
    final app = PlannerApplicationController(
      catalog: snapshot,
      initialState: PlannerState(
        applicationVersion: 'item-reference-sections-test',
        lastSuccessfulWriteUtc: DateTime.utc(2026, 10, 17),
        activeMode: CraftMode.processing,
        alchemy: _state(CraftMode.alchemy, 'Clear Liquid Reagent'),
        cooking: _state(CraftMode.cooking, 'Beer'),
        processing: _state(CraftMode.processing, 'Wheat Flour'),
        processingYields: const {},
        marketTax: MarketTax(),
        showDeleteTools: false,
      ),
      saveState: (value) async => value,
    );
    addTearDown(app.dispose);
    final book = RecipeBookController(
      modeController: app.active,
      catalogRepository: CatalogRepository(snapshot),
      callingContext: RecipeBookCallingContext.planner,
      allowedTargets: const [],
      checkPrices: (_) => throw StateError('Reference views must not fetch.'),
    );
    addTearDown(book.dispose);
    const name = 'Iridescent Maehwa';
    const liquor = 'Iridescent Maehwa Liquor';
    final info = book.itemInfoFor(name)!;
    final before = app.documentSnapshot;
    expect(info.craftUses.map((use) => use.output), contains(liquor));
    expect(info.effects, isEmpty);
    final formula = info.craftUses
        .singleWhere((use) => use.output == liquor)
        .formulas
        .single;
    expect(
      {
        for (final material in formula.ingredients)
          material.name: material.quantity,
      },
      {'Leavening Agent': 2, 'Essence of Liquor': 5, 'Maehwa': 10, name: 10},
    );
    // The caller owns any exchange-specific projection; the shared view does
    // not discard remaining source facts or mutate the cached reference.
    final projected = info.copyWith(acquisitionFormulas: const []);
    await tester.pumpWidget(
      _host(
        SakuraNightGardenSpec.theme,
        SingleChildScrollView(
          child: SizedBox(
            width: 500,
            child: ItemReferenceSections(
              controller: book,
              mode: CraftMode.processing,
              name: name,
              info: projected,
              spec: SakuraNightGardenSpec.theme,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    for (final element in find.byType(Image).evaluate().toList()) {
      await tester.runAsync(
        () => precacheImage((element.widget as Image).image, element),
      );
    }
    await tester.pumpAndSettle();
    expect(find.text('Used For'), findsOneWidget);
    expect(find.text(liquor), findsOneWidget);
    for (final effect in [
      'All Damage Reduction +5',
      'All Resistance +5%',
      'Max HP +150',
    ]) {
      expect(find.text(effect), findsOneWidget);
    }
    expect(find.text('Use recipe'), findsOneWidget);
    expect(find.text('Recipe & materials'), findsNothing);
    expect(book.itemInfoFor(name), same(info));
    expect(app.documentSnapshot, same(before));
    expect(book.lastRouteActivation, isNull);
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
      checkPrices: (_) => throw StateError('Reference views must not fetch.'),
    );

Widget _formulaSections(
  RecipeBookController book,
  RecipeBookFormula formula, {
  ValueChanged<String>? onCopy,
  VoidCallback? onActivated,
  ValueChanged<RecipeBookFormula>? onUseFormula,
}) => ItemReferenceSections(
  controller: book,
  mode: CraftMode.alchemy,
  name: formula.outputName,
  info: RecipeBookItemInfo(
    title: formula.outputName,
    kind: 'Recipe',
    summary: '',
    acquisitionFormulas: [formula],
  ),
  spec: StandardSpec.theme,
  onCopyItemName: onCopy,
  onRecipeActivated: onActivated,
  onUseFormula: onUseFormula,
);

Widget _host(ThemeSpec spec, Widget child) => MaterialApp(
  theme: spec.materialTheme(),
  home: ThemeSpecScope(
    spec: spec,
    child: Scaffold(
      body: Align(alignment: Alignment.topLeft, child: child),
    ),
  ),
);

ModeState _state(CraftMode mode, String target) => ModeState(
  target: target,
  want: 1,
  bonusTarget: target,
  market: MarketState(),
  appearance: AppearanceSettings.defaultsFor(mode),
);
