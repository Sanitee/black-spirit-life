import 'dart:io';
import 'dart:ui' as ui;
import 'package:bdo_craft_planner_flutter/data/catalog/bundled_catalog_parser.dart';
import 'package:bdo_craft_planner_flutter/data/catalog/catalog_repository.dart';
import 'package:bdo_craft_planner_flutter/domain/models/craft_mode.dart';
import 'package:bdo_craft_planner_flutter/features/planner/planner_contracts.dart';
import 'package:bdo_craft_planner_flutter/features/recipe_book/recipe_book.dart';
import 'package:bdo_craft_planner_flutter/features/recipe_book/recipe_book_item_info.dart';
import 'package:bdo_craft_planner_flutter/shared/overlays/anchored_popover.dart';
import 'package:bdo_craft_planner_flutter/visual/visual.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import '../../support/substitute_chooser_helpers.dart';
import '../planner/planner_review_projection_test.dart' as fixture;

void main() {
  final catalog = const BundledCatalogParser().parse(
    File('assets/data/app-data.json').readAsStringSync(),
  );
  for (final host in ['inline', 'pinned', 'hover']) {
    testWidgets(
      '$host cross-mode substitute retains parent and exact activation',
      (tester) async {
        tester.view.physicalSize = const Size(1400, 1000);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final app = fixture.controller(catalog, CraftMode.cooking, 'Beer', 1);
        final book = RecipeBookController(
          modeController: app.active,
          catalogRepository: CatalogRepository.cached(catalog),
          callingContext: RecipeBookCallingContext.planner,
          allowedTargets: [],
        );
        addTearDown(book.dispose);
        addTearDown(app.dispose);
        final before = app.documentSnapshot.toJson();
        final routed = <RecipeBookFormula>[];
        await tester.pumpWidget(
          MaterialApp(
            home: ThemeSpecScope(
              spec: SakuraNightGardenSpec.theme,
              child: Scaffold(
                body: AppOverlayCoordinatorHost(
                  child: Center(
                    child: host == 'inline'
                        ? SizedBox(
                            width: 1000,
                            child: ItemReferenceSections(
                              controller: book,
                              mode: CraftMode.processing,
                              name: 'Wheat Flour',
                              info: book
                                  .itemInfoFor(
                                    'Wheat Flour',
                                    mode: CraftMode.processing,
                                  )!
                                  .copyWith(craftUses: [], uses: []),
                              spec: SakuraNightGardenSpec.theme,
                              onUseFormula: routed.add,
                            ),
                          )
                        : RecipeBookItemIcon(
                            controller: book,
                            mode: CraftMode.processing,
                            name: 'Wheat Flour',
                            size: 48,
                            anchorId: 'nested-test',
                          ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final anchor = find.byKey(
          RecipeBookKeys.itemInfoAnchor('Wheat Flour', 'nested-test'),
        );
        TestGesture? mouse;
        Future<void> click(Finder finder) async {
          await tester.ensureVisible(finder);
          await tester.pumpAndSettle();
          if (mouse == null) {
            await tester.tap(finder);
          } else {
            await mouse.moveTo(tester.getCenter(finder));
            await tester.pump();
            await mouse.down(tester.getCenter(finder));
            await mouse.up();
            await tester.pump();
          }
          await tester.pumpAndSettle();
        }

        Future<void> open() async {
          await click(
            find.byKey(const ValueKey('recipe-substitutes:Wheat Flour:Wheat')),
          );
          expect(substituteChooser(), findsOneWidget);
        }

        if (host == 'pinned') {
          await tester.tap(anchor);
          await tester.pumpAndSettle();
        } else if (host == 'hover') {
          mouse = await tester.createGesture(kind: ui.PointerDeviceKind.mouse);
          await mouse.addPointer(location: Offset.zero);
          addTearDown(mouse.removePointer);
          await mouse.moveTo(tester.getCenter(anchor));
          await tester.pump(const Duration(milliseconds: 600));
          await tester.pumpAndSettle();
        }
        await open();
        final rows = tester
            .widget<RecipeIngredientTable>(substituteChooser())
            .rows;
        expect(rows.map((r) => r.name), [
          'Wheat',
          'High-quality Wheat',
          'Special Wheat',
        ]);
        expect(rows.map((r) => r.quantity), [1, 1, 1]);
        await click(
          find.byKey(const ValueKey('recipe-choose:Wheat Flour:Special Wheat')),
        );
        expect(
          tester
              .widget<RecipeIngredientTable>(find.byType(RecipeIngredientTable))
              .rows
              .single
              .name,
          'Special Wheat',
        );
        expect(app.documentSnapshot.toJson(), before);
        // Escape dismisses the child first, leaving the parent usable.
        await open();
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
        expect(substituteChooser(), findsNothing);
        expect(find.text('Use recipe'), findsOneWidget);
        await tester.ensureVisible(find.text('Use recipe'));
        await click(find.text('Use recipe'));
        await tester.pumpAndSettle();
        if (host == 'inline') {
          expect(routed.single.ingredientChoiceNames, {
            'wheat': 'Special Wheat',
          });
          expect(app.documentSnapshot.toJson(), before);
          expect(book.activateFormula(routed.single), isNotNull);
        }
        expect(app.active.mode, CraftMode.processing);
        expect(app.active.state.value.target, 'Wheat Flour');
        expect(
          book
              .controllerForMode(CraftMode.processing)
              .availabilityFor('Wheat Flour')
              .ingredients
              .single
              .name,
          'Special Wheat',
        );
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
  test('invalid substitute cannot partly change target or mode', () async {
    final app = fixture.controller(catalog, CraftMode.cooking, 'Beer', 1);
    final book = RecipeBookController(
      modeController: app.active,
      catalogRepository: CatalogRepository.cached(catalog),
      callingContext: RecipeBookCallingContext.planner,
      allowedTargets: [],
    );
    addTearDown(book.dispose);
    addTearDown(app.dispose);
    final before = app.documentSnapshot.toJson();
    final formula = book.itemInfoFor('Wheat Flour')!.acquisitionFormulas.first;
    for (final selection in [
      {'wheat': 'Invalid material'},
      {'unknown': 'Wheat'},
    ]) {
      final invalid = formula.copyWith(ingredientChoiceNames: selection);
      expect(book.canActivateFormula(invalid), isFalse);
      expect(book.activateFormula(invalid), isNull);
      expect(app.documentSnapshot.toJson(), before);
    }
  });
}
