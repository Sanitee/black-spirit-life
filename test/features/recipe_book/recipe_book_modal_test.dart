import 'dart:async';
import 'dart:ui' show PointerDeviceKind;

import 'package:bdo_craft_planner_flutter/data/icons/custom_icon_store.dart';
import 'package:bdo_craft_planner_flutter/domain/models/craft_mode.dart';
import 'package:bdo_craft_planner_flutter/domain/state/planner_state.dart';
import 'package:bdo_craft_planner_flutter/domain/state/state_copy.dart';
import 'package:bdo_craft_planner_flutter/features/planner/planner_contracts.dart';
import 'package:bdo_craft_planner_flutter/features/planner/planner_keys.dart';
import 'package:bdo_craft_planner_flutter/features/recipe_book/recipe_book.dart';
import 'package:bdo_craft_planner_flutter/features/shared/custom_icon_store_scope.dart';
import 'package:bdo_craft_planner_flutter/features/shared/mode_item_icon.dart';
import 'package:bdo_craft_planner_flutter/features/shared/recipe_variant_selector.dart';
import 'package:bdo_craft_planner_flutter/shared/overlays/anchored_popover.dart';
import 'package:bdo_craft_planner_flutter/visual/visual.dart';
import 'package:flutter/gestures.dart'
    show PointerScrollEvent, kSecondaryMouseButton;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../shared/custom_icon_test_support.dart';
import 'recipe_book_test_support.dart';

void main() {
  testWidgets(
    'Recipe Book cards identify how Alchemy, Cooking, and Processing recipes are made',
    (tester) async {
      await _setSize(tester, const Size(1200, 752));
      const cases = <({CraftMode mode, String name, String method})>[
        (
          mode: CraftMode.alchemy,
          name: 'Clear Liquid Reagent',
          method: 'Residence Alchemy',
        ),
        (mode: CraftMode.cooking, name: 'Beer', method: 'Residence Cooking'),
        (
          mode: CraftMode.processing,
          name: 'Black Stone Batch 01',
          method: 'Grinding',
        ),
      ];

      for (final recipeCase in cases) {
        final environment = buildRecipeBookTestEnvironment(
          activeMode: recipeCase.mode,
        );
        final mode = environment.application.modes[recipeCase.mode]!;
        final book = RecipeBookController(
          modeController: mode,
          catalogRepository: environment.catalogRepository,
          callingContext: RecipeBookCallingContext.planner,
          allowedTargets: mode.craftableNames,
        );
        if (recipeCase.mode == CraftMode.processing) {
          book.setDensity(RecipeBookDensity.sixByFive);
        }
        await tester.pumpWidget(
          _host(
            RecipeBookModal(
              controller: book,
              onClose: () {},
              onActivated: (_) {},
            ),
          ),
        );
        await tester.pumpAndSettle();

        final card = find.byKey(RecipeBookKeys.card(recipeCase.name));
        final title = find.descendant(
          of: card,
          matching: find.text(recipeCase.name),
        );
        final method = find.descendant(
          of: card,
          matching: find.byKey(
            RecipeBookKeys.productionMethod(recipeCase.name),
          ),
        );
        expect(card, findsOneWidget);
        expect(title, findsOneWidget);
        expect(method, findsOneWidget);
        expect(tester.widget<Text>(method).data, recipeCase.method);
        expect(
          tester.widget<Text>(method).style!.fontSize!,
          lessThan(tester.widget<Text>(title).style!.fontSize!),
        );
        expect(
          tester.renderObject<RenderParagraph>(method).didExceedMaxLines,
          isFalse,
          reason: recipeCase.name,
        );
        expect(tester.takeException(), isNull);

        await tester.pumpWidget(const SizedBox.shrink());
        book.dispose();
        await environment.dispose();
      }
    },
  );

  testWidgets(
    'recipe preview ingredients use the source-aware planner map actions',
    (tester) async {
      await _setSize(tester, const Size(1200, 752));
      final environment = buildRecipeBookTestEnvironment();
      final mode = environment.application.modes[CraftMode.alchemy]!;
      final book = RecipeBookController(
        modeController: mode,
        catalogRepository: environment.catalogRepository,
        callingContext: RecipeBookCallingContext.planner,
        allowedTargets: mode.craftableNames,
      )..openPreview('Clear Liquid Reagent');
      addTearDown(book.dispose);
      addTearDown(environment.dispose);
      final resolvedNames = <String>[];
      final mapRequests = <PlannerMapLookupRequest>[];
      final checklistAdds = <PlannerMapLookupAvailability>[];
      final plannedNetworkAdds = <PlannerMapLookupAvailability>[];
      final actions = PlannerExternalActions(
        openRecipeBook: (_) {},
        copyName: (_) async {},
        checkPrices: (_) async => const PlannerMarketRefresh(
          prices: <String, double>{},
          stock: <String, double>{},
          unlistedItemNames: <String>{},
          fetchedAt: 0,
          summary: '',
        ),
        resolveMapLookup: (materialName) async {
          resolvedNames.add(materialName);
          return PlannerMapLookupAvailability(
            materialName: materialName,
            hasNpcVendors: true,
            npcVendorCount: 3,
            hasManualGathering: true,
            manualResourceId: 'item:wild-grass',
            manualLocationCount: 12,
          );
        },
        openMapLookup: mapRequests.add,
        addToGatherChecklist: checklistAdds.add,
        addToPlannedNetwork: plannedNetworkAdds.add,
      );

      await tester.pumpWidget(
        _host(
          RecipeBookModal(
            controller: book,
            externalActions: actions,
            onClose: () {},
            onActivated: (_) {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      const parentName = 'Clear Liquid Reagent';
      const selectedName = 'Wild Grass';
      const stableId = 'recipe-preview:$parentName:0:$selectedName';
      final region = find.byKey(
        RecipeBookKeys.mapLookupRegion(parentName, 0, selectedName),
      );
      expect(region, findsOneWidget);

      await tester.tap(
        region,
        buttons: kSecondaryMouseButton,
        kind: PointerDeviceKind.mouse,
      );
      await tester.pumpAndSettle();

      expect(resolvedNames, <String>[selectedName]);
      expect(find.text('Show NPC vendors'), findsOneWidget);
      expect(find.text('3 mapped vendor locations'), findsOneWidget);
      expect(find.text('Show gathering locations'), findsOneWidget);
      expect(find.text('12 mapped locations'), findsOneWidget);
      expect(find.text('Add to checklist'), findsOneWidget);
      expect(find.text('Add to planned network'), findsNothing);
      final manualAction = find.byKey(
        PlannerActionKeys.mapLookupAction(
          stableId,
          PlannerMapLookupSource.manualGathering.name,
        ),
      );
      final vendorAction = find.byKey(
        PlannerActionKeys.mapLookupAction(
          stableId,
          PlannerMapLookupSource.npcVendors.name,
        ),
      );
      final checklistAction = find.byKey(
        PlannerActionKeys.mapLookupAction(stableId, 'addToGatherChecklist'),
      );
      expect(
        find.descendant(
          of: vendorAction,
          matching: find.byIcon(Icons.storefront_rounded),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: manualAction,
          matching: find.byIcon(Icons.location_on_rounded),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: checklistAction,
          matching: find.byIcon(Icons.checklist_rounded),
        ),
        findsOneWidget,
      );
      expect(find.byType(PopupMenuDivider), findsOneWidget);

      await tester.tap(vendorAction);
      await tester.pumpAndSettle();

      expect(mapRequests, hasLength(1));
      expect(
        mapRequests.single,
        isA<PlannerMapLookupRequest>()
            .having(
              (request) => request.materialName,
              'materialName',
              selectedName,
            )
            .having((request) => request.resourceId, 'resourceId', isNull)
            .having(
              (request) => request.source,
              'source',
              PlannerMapLookupSource.npcVendors,
            ),
      );

      await tester.tap(
        region,
        buttons: kSecondaryMouseButton,
        kind: PointerDeviceKind.mouse,
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(
          PlannerActionKeys.mapLookupAction(
            stableId,
            PlannerMapLookupSource.manualGathering.name,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(mapRequests, hasLength(2));
      expect(
        mapRequests.last,
        isA<PlannerMapLookupRequest>()
            .having(
              (request) => request.materialName,
              'materialName',
              selectedName,
            )
            .having(
              (request) => request.resourceId,
              'resourceId',
              'item:wild-grass',
            )
            .having(
              (request) => request.source,
              'source',
              PlannerMapLookupSource.manualGathering,
            ),
      );
      expect(checklistAdds, isEmpty);
      expect(plannedNetworkAdds, isEmpty);
      expect(find.byKey(RecipeBookKeys.previewPanel), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Recipe Book grid hides scrollbar chrome and still wheel-scrolls',
    (tester) async {
      await _setSize(tester, const Size(1200, 752));
      final environment = buildRecipeBookTestEnvironment(
        activeMode: CraftMode.processing,
      );
      final mode = environment.application.modes[CraftMode.processing]!;
      final book = RecipeBookController(
        modeController: mode,
        catalogRepository: environment.catalogRepository,
        callingContext: RecipeBookCallingContext.planner,
        allowedTargets: mode.craftableNames,
      )..setDensity(RecipeBookDensity.sixByFive);
      addTearDown(book.dispose);
      addTearDown(environment.dispose);

      await tester.pumpWidget(
        _host(
          RecipeBookModal(
            controller: book,
            onClose: () {},
            onActivated: (_) {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      final grid = find.byKey(RecipeBookKeys.r10CardScroll);
      final scrollable = find.descendant(
        of: grid,
        matching: find.byType(Scrollable),
      );
      expect(grid, findsOneWidget);
      expect(scrollable, findsOneWidget);
      expect(
        find.descendant(of: grid, matching: find.byType(Scrollbar)),
        findsNothing,
      );
      expect(
        find.descendant(of: grid, matching: find.byType(RawScrollbar)),
        findsNothing,
      );
      final lazyCardGrid = tester.widget<GridView>(
        find.descendant(of: grid, matching: find.byType(GridView)),
      );
      expect(
        lazyCardGrid.childrenDelegate,
        isA<SliverChildBuilderDelegate>(),
        reason: 'Recipe cards should be built only around visible entries.',
      );
      expect(lazyCardGrid.semanticChildCount, book.snapshot.entries.length);

      final position = tester.state<ScrollableState>(scrollable).position;
      expect(position.maxScrollExtent, greaterThan(0));
      final before = position.pixels;
      await tester.sendEventToBinding(
        PointerScrollEvent(
          viewId: tester.view.viewId,
          kind: PointerDeviceKind.mouse,
          position: tester.getCenter(grid),
          scrollDelta: const Offset(0, 180),
        ),
      );
      await tester.pumpAndSettle();

      expect(position.pixels, greaterThan(before));
      expect(book.scrollOffset, greaterThan(0));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Recipe Book preview shares the saved complete-formula selector',
    (tester) async {
      await _setSize(tester, const Size(1200, 752));
      final environment = buildRecipeBookTestEnvironment(
        includeRecipeVariants: true,
      );
      final mode = environment.application.modes[CraftMode.alchemy]!;
      final book = RecipeBookController(
        modeController: mode,
        catalogRepository: environment.catalogRepository,
        callingContext: RecipeBookCallingContext.planner,
        allowedTargets: mode.craftableNames,
      );
      await tester.pumpWidget(
        _host(
          RecipeBookModal(
            controller: book,
            onClose: () {},
            onActivated: (_) {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(RecipeBookKeys.r13Details('Clear Liquid Reagent')),
      );
      await tester.pumpAndSettle();

      final alternate = find.byKey(
        RecipeVariantSelector.choiceKey('Clear Liquid Reagent', 'trace-route'),
      );
      expect(alternate, findsOneWidget);
      expect(find.text('Wild Grass'), findsWidgets);

      await tester.tap(alternate);
      await tester.pumpAndSettle();

      expect(mode.state.value.recipeVariantChoices, {
        'Clear Liquid Reagent': 'trace-route',
      });
      expect(find.text('Trace of Earth'), findsOneWidget);
      expect(
        find.byKey(
          RecipeBookKeys.r15Substitute('Clear Liquid Reagent', 'Wild Grass'),
        ),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
      book.dispose();
      await environment.dispose();
    },
  );

  testWidgets(
    'Recipe Book substitute selector shows every complete material name',
    (tester) async {
      await _setSize(tester, const Size(1200, 752));
      final environment = buildRecipeBookTestEnvironment(
        includeLongSubstituteFixture: true,
      );
      final mode = environment.application.modes[CraftMode.alchemy]!;
      final book = RecipeBookController(
        modeController: mode,
        catalogRepository: environment.catalogRepository,
        callingContext: RecipeBookCallingContext.planner,
        allowedTargets: mode.craftableNames,
      );
      addTearDown(book.dispose);
      addTearDown(environment.dispose);

      await tester.pumpWidget(
        _host(
          RecipeBookModal(
            controller: book,
            onClose: () {},
            onActivated: (_) {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(RecipeBookKeys.r13Details("Clown's Blood")));
      await tester.pumpAndSettle();

      final selector = find.byKey(
        RecipeBookKeys.r15Substitute("Clown's Blood", 'Cheetah Dragon Blood'),
      );
      expect(selector, findsOneWidget);
      expect(tester.getSize(selector).width, greaterThan(240));
      final selectedName = find.descendant(
        of: selector,
        matching: find.text('Cheetah Dragon Blood'),
      );
      expect(selectedName, findsOneWidget);
      expect(
        tester.renderObject<RenderParagraph>(selectedName).didExceedMaxLines,
        isFalse,
      );

      await tester.tap(selector);
      await tester.pumpAndSettle();
      for (final label in const <String>[
        'Wolf Blood',
        'Flamingo Blood',
        'Rhino Blood',
        'Cheetah Dragon Blood',
      ]) {
        final option = find.widgetWithText(MenuItemButton, label);
        expect(option, findsOneWidget);
        final text = find.descendant(of: option, matching: find.text(label));
        expect(
          tester.renderObject<RenderParagraph>(text).didExceedMaxLines,
          isFalse,
        );
        final optionRect = tester.getRect(option);
        expect(optionRect.left, greaterThanOrEqualTo(0));
        expect(optionRect.right, lessThanOrEqualTo(1200));
        expect(optionRect.top, greaterThanOrEqualTo(0));
        expect(optionRect.bottom, lessThanOrEqualTo(752));
      }
      await tester.tap(find.text('Flamingo Blood').last);
      await tester.pumpAndSettle();
      expect(
        find.descendant(of: selector, matching: find.text('Flamingo Blood')),
        findsOneWidget,
      );
      expect(
        tester
            .getSemantics(
              find.bySemanticsLabel(
                "Substitute for Cheetah Dragon Blood in Clown's Blood",
              ),
            )
            .value,
        'Flamingo Blood',
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('ingredient search shows and targets the searched substitute', (
    tester,
  ) async {
    await _setSize(tester, const Size(1200, 752));
    final environment = buildRecipeBookTestEnvironment(
      includeLongSubstituteFixture: true,
    );
    final mode = environment.application.modes[CraftMode.alchemy]!;
    final book = RecipeBookController(
      modeController: mode,
      catalogRepository: environment.catalogRepository,
      callingContext: RecipeBookCallingContext.planner,
      allowedTargets: mode.craftableNames,
    );
    final activations = <RecipeBookActivation>[];
    addTearDown(book.dispose);
    addTearDown(environment.dispose);

    await tester.pumpWidget(
      _host(
        RecipeBookModal(
          controller: book,
          onClose: () {},
          onActivated: activations.add,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(RecipeBookKeys.r05SearchByIngredient));
    final search = find.descendant(
      of: find.byKey(RecipeBookKeys.r03Search),
      matching: find.byType(TextField),
    );
    await tester.enterText(search, 'Wolf Blood');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(RecipeBookKeys.r13Details("Clown's Blood")));
    await tester.pumpAndSettle();

    final selector = find.byKey(
      RecipeBookKeys.r15Substitute("Clown's Blood", 'Cheetah Dragon Blood'),
    );
    expect(
      find.descendant(of: selector, matching: find.text('Wolf Blood')),
      findsOneWidget,
    );
    expect(mode.state.value.substituteChoices, isEmpty);

    await tester.tap(
      find.byKey(RecipeBookKeys.r11Target("Clown's Blood:preview")),
    );
    await tester.pump();

    expect(activations.single.exactName, "Clown's Blood");
    expect(mode.state.value.target, "Clown's Blood");
    expect(
      mode.state.value.substituteChoices["recipe:Clown's Blood:Blood Group"],
      'Wolf Blood',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('Recipe Book and preview move independently from their headers', (
    tester,
  ) async {
    await _setSize(tester, const Size(1200, 752));
    final environment = buildRecipeBookTestEnvironment();
    final mode = environment.application.modes[CraftMode.alchemy]!;
    final book = RecipeBookController(
      modeController: mode,
      catalogRepository: environment.catalogRepository,
      callingContext: RecipeBookCallingContext.planner,
      allowedTargets: mode.craftableNames,
    );
    addTearDown(book.dispose);
    addTearDown(environment.dispose);

    await tester.pumpWidget(
      _host(
        RecipeBookModal(controller: book, onClose: () {}, onActivated: (_) {}),
      ),
    );
    await tester.pumpAndSettle();

    final initialBook = tester.getRect(find.byKey(RecipeBookKeys.modal));
    await tester.drag(
      find.byKey(RecipeBookKeys.bookDragRegion),
      const Offset(20, 12),
    );
    await tester.pump();
    final movedBook = tester.getRect(find.byKey(RecipeBookKeys.modal));
    expect(movedBook.topLeft, initialBook.topLeft + const Offset(20, 12));

    await tester.tap(
      find.byKey(RecipeBookKeys.r13Details('Clear Liquid Reagent')),
    );
    await tester.pumpAndSettle();
    final initialPreview = tester.getRect(
      find.byKey(RecipeBookKeys.previewPanel),
    );
    await tester.drag(
      find.byKey(RecipeBookKeys.previewDragRegion),
      const Offset(-28, 20),
    );
    await tester.pump();
    final movedPreview = tester.getRect(
      find.byKey(RecipeBookKeys.previewPanel),
    );
    expect(
      movedPreview.topLeft,
      initialPreview.topLeft + const Offset(-28, 20),
    );
    expect(tester.getRect(find.byKey(RecipeBookKeys.modal)), movedBook);

    await tester.tap(
      find.byKey(RecipeBookKeys.r14ClosePreview('Clear Liquid Reagent')),
    );
    await tester.pumpAndSettle();
    expect(book.previewName, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('live resize keeps Recipe Book search and preview mounted', (
    tester,
  ) async {
    await _setSize(tester, const Size(1575, 987));
    final environment = buildRecipeBookTestEnvironment();
    final mode = environment.application.modes[CraftMode.alchemy]!;
    final book = RecipeBookController(
      modeController: mode,
      catalogRepository: environment.catalogRepository,
      callingContext: RecipeBookCallingContext.planner,
      allowedTargets: mode.craftableNames,
    );
    addTearDown(book.dispose);
    addTearDown(environment.dispose);

    await tester.pumpWidget(
      _host(
        RecipeBookModal(controller: book, onClose: () {}, onActivated: (_) {}),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.descendant(
        of: find.byKey(RecipeBookKeys.r03Search),
        matching: find.byType(TextField),
      ),
      'Clear Liquid',
    );
    await tester.pump();
    await tester.tap(
      find.byKey(RecipeBookKeys.r13Details('Clear Liquid Reagent')),
    );
    await tester.pumpAndSettle();

    for (final size in <Size>[
      const Size(1490, 934),
      const Size(1400, 877),
      const Size(1394, 873),
      const Size(1380, 865),
      const Size(1200, 752),
    ]) {
      tester.view.physicalSize = size;
      await tester.pump();
      expect(book.search, 'Clear Liquid');
      expect(book.previewName, 'Clear Liquid Reagent');
      expect(find.byKey(RecipeBookKeys.modal), findsOneWidget);
      expect(find.byKey(RecipeBookKeys.previewPanel), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets(
    '1200x752 live filters, favorites, preview choices, and Escape layer correctly',
    (tester) async {
      await _setSize(tester, const Size(1200, 752));
      final environment = buildRecipeBookTestEnvironment();
      final mode = environment.application.modes[CraftMode.alchemy]!;
      final book = RecipeBookController(
        modeController: mode,
        catalogRepository: environment.catalogRepository,
        callingContext: RecipeBookCallingContext.planner,
        allowedTargets: mode.craftableNames,
      );
      var closeCount = 0;
      final activations = <RecipeBookActivation>[];
      await tester.pumpWidget(
        _host(
          RecipeBookModal(
            controller: book,
            onClose: () => closeCount += 1,
            onActivated: activations.add,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(RecipeBookKeys.modal), findsOneWidget);
      expect(
        tester.getRect(find.byKey(RecipeBookKeys.modal)),
        const Rect.fromLTWH(46, 43, 1108, 666),
      );
      expect(
        tester.getSize(find.byKey(RecipeBookKeys.card('Clear Liquid Reagent'))),
        const Size(236, 182),
      );
      expect(find.text('3 recipes'), findsOneWidget);
      expect(tester.takeException(), isNull);
      final search = find.descendant(
        of: find.byKey(RecipeBookKeys.r03Search),
        matching: find.byType(TextField),
      );
      await tester.enterText(search, 'Wild Grass');
      await tester.pump();
      expect(
        find.byKey(RecipeBookKeys.card('Clear Liquid Reagent')),
        findsNothing,
      );
      final clearSearch = find.byTooltip('Clear recipe search');
      expect(clearSearch, findsOneWidget);
      expect(
        find.ancestor(of: clearSearch, matching: find.byType(AppButton)),
        findsOneWidget,
      );

      await tester.tap(find.byKey(RecipeBookKeys.r05SearchByIngredient));
      await tester.pump();
      expect(mode.state.value.bookSearchIngredients, isTrue);
      expect(
        find.byKey(RecipeBookKeys.card('Clear Liquid Reagent')),
        findsOneWidget,
      );

      await tester.tap(
        find.byKey(RecipeBookKeys.r12Favorite('Clear Liquid Reagent')),
      );
      await tester.pump();
      expect(mode.state.value.favoriteRecipes, const <String>[
        'Clear Liquid Reagent',
      ]);
      await tester.enterText(search, '');
      await tester.pump();
      await tester.tap(find.byKey(RecipeBookKeys.r04FavoritesOnly));
      await tester.pump();
      expect(book.snapshot.filteredCount, 1);
      expect(find.text('1 favorites'), findsOneWidget);

      await tester.tap(
        find.byKey(RecipeBookKeys.r13Details('Clear Liquid Reagent')),
      );
      await tester.pumpAndSettle();
      expect(book.previewName, 'Clear Liquid Reagent');
      expect(
        tester.getSize(find.byKey(RecipeBookKeys.previewPanel)),
        const Size(430, 267),
      );
      final previewRect = tester.getRect(
        find.byKey(RecipeBookKeys.previewPanel),
      );
      expect(previewRect.left, closeTo(293.8, .2));
      expect(previewRect.top, closeTo(263.3, .2));
      expect(
        tester.getSize(
          find.byKey(RecipeBookKeys.r11Target('Clear Liquid Reagent:preview')),
        ),
        const Size(95, 38),
      );
      expect(
        find.byKey(
          RecipeBookKeys.r15Substitute('Clear Liquid Reagent', 'Wild Grass'),
        ),
        findsOneWidget,
      );
      await tester.tap(
        find.byKey(
          RecipeBookKeys.r15Substitute('Clear Liquid Reagent', 'Wild Grass'),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Weed').last);
      await tester.pumpAndSettle();
      expect(
        mode
            .state
            .value
            .substituteChoices['recipe:Clear Liquid Reagent:Wild Plants'],
        'Weed',
      );
      expect(
        tester.getSize(
          find.byKey(
            RecipeBookKeys.r16Quality(
              'Clear Liquid Reagent',
              'Sunflower',
              'special',
            ),
          ),
        ),
        const Size.square(22),
      );
      await tester.tap(
        find.byKey(
          RecipeBookKeys.r16Quality(
            'Clear Liquid Reagent',
            'Sunflower',
            'special',
          ),
        ),
      );
      await tester.pump();
      expect(
        mode
            .state
            .value
            .ingredientGrades['recipe:Clear Liquid Reagent:Sunflower'],
        'special',
      );

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(book.previewName, isNull);
      expect(closeCount, 0);
      expect(book.search, '');
      expect(book.favoritesOnly, isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(closeCount, 1);
      expect(activations, isEmpty);

      await tester.pumpWidget(const SizedBox.shrink());
      book.dispose();
      await environment.dispose();
    },
  );

  testWidgets('R05 Processing exposes ingredient search without overflowing', (
    tester,
  ) async {
    await _setSize(tester, const Size(1200, 752));
    final environment = buildRecipeBookTestEnvironment(
      activeMode: CraftMode.processing,
    );
    final mode = environment.application.modes[CraftMode.processing]!;
    final book = RecipeBookController(
      modeController: mode,
      catalogRepository: environment.catalogRepository,
      callingContext: RecipeBookCallingContext.planner,
      allowedTargets: mode.craftableNames,
    );

    await tester.pumpWidget(
      _host(
        RecipeBookModal(controller: book, onClose: () {}, onActivated: (_) {}),
      ),
    );
    await tester.pumpAndSettle();

    final toggle = find.byKey(RecipeBookKeys.r05SearchByIngredient);
    expect(toggle, findsOneWidget);
    await tester.tap(toggle);
    await tester.pump();
    expect(mode.state.value.bookSearchIngredients, isTrue);

    final search = find.descendant(
      of: find.byKey(RecipeBookKeys.r03Search),
      matching: find.byType(TextField),
    );
    await tester.enterText(search, 'Raw Material 01');
    await tester.pump();

    expect(
      find.byKey(RecipeBookKeys.card('Black Stone Batch 01')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    book.dispose();
    await environment.dispose();
  });

  testWidgets('1500x940 Processing scroll, groups, and drag suppression work', (
    tester,
  ) async {
    await _setSize(tester, const Size(1500, 940));
    final environment = buildRecipeBookTestEnvironment(
      activeMode: CraftMode.processing,
    );
    final mode = environment.application.modes[CraftMode.processing]!;
    final book = RecipeBookController(
      modeController: mode,
      catalogRepository: environment.catalogRepository,
      callingContext: RecipeBookCallingContext.planner,
      allowedTargets: mode.craftableNames,
    );
    final activations = <RecipeBookActivation>[];
    await tester.pumpWidget(
      _host(
        RecipeBookModal(
          controller: book,
          onClose: () {},
          onActivated: activations.add,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      tester.getRect(find.byKey(RecipeBookKeys.modal)),
      const Rect.fromLTWH(140, 60, 1220, 820),
    );
    expect(book.snapshot.entries, hasLength(36));
    expect(find.textContaining('Page '), findsNothing);
    expect(find.byKey(RecipeBookKeys.r06Density), findsNothing);
    expect(find.byKey(RecipeBookKeys.r08Previous), findsNothing);
    expect(find.byKey(RecipeBookKeys.r09Next), findsNothing);
    expect(find.text('36 recipes'), findsOneWidget);

    final lastRecipe = book.snapshot.entries.last.name;
    await tester.scrollUntilVisible(
      find.byKey(RecipeBookKeys.card(lastRecipe)),
      420,
      scrollable: find.descendant(
        of: find.byKey(RecipeBookKeys.r10CardScroll),
        matching: find.byType(Scrollable),
      ),
    );
    expect(find.byKey(RecipeBookKeys.card(lastRecipe)), findsOneWidget);
    final metalsCount = book.snapshot.groupCounts
        .firstWhere((value) => value.group == ProcessingRecipeGroup.metals)
        .count;
    await tester.tap(find.byKey(RecipeBookKeys.r07Groups));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Metals ($metalsCount)').last);
    await tester.pumpAndSettle();
    expect(book.page, 0);
    expect(book.group, ProcessingRecipeGroup.metals);
    expect(
      book.snapshot.entries,
      everyElement(
        isA<RecipeBookEntry>().having(
          (entry) => entry.processingGroup,
          'group',
          ProcessingRecipeGroup.metals,
        ),
      ),
    );

    book.setGroup(ProcessingRecipeGroup.all);
    await tester.pumpAndSettle();
    final first = book.snapshot.entries.first.name;
    final originalTarget = mode.state.value.target;
    await tester.drag(
      find.byKey(RecipeBookKeys.card(first)),
      const Offset(0, -90),
    );
    await tester.pumpAndSettle();
    expect(mode.state.value.target, originalTarget);
    expect(activations, isEmpty);

    await tester.pumpWidget(const SizedBox.shrink());
    book.dispose();
    await environment.dispose();
  });

  testWidgets(
    'market controls stay grouped and refresh spins for the full request',
    (tester) async {
      await _setSize(tester, const Size(1200, 752));
      final environment = buildRecipeBookTestEnvironment();
      final mode = environment.application.modes[CraftMode.alchemy]!;
      mode.updateState(
        (state) => state.copyWith(
          ingredientMeta: <String, IngredientMetadata>{
            'Clear Liquid Reagent': IngredientMetadata(marketId: '5301'),
            'Pure Powder Reagent': IngredientMetadata(marketId: '5302'),
            'Elixir of Life': IngredientMetadata(marketId: '5303'),
          },
        ),
        immediate: true,
      );
      final refreshes = <Completer<PlannerMarketRefresh>>[
        Completer<PlannerMarketRefresh>(),
        Completer<PlannerMarketRefresh>(),
      ];
      var refreshCount = 0;
      final book = RecipeBookController(
        modeController: mode,
        catalogRepository: environment.catalogRepository,
        callingContext: RecipeBookCallingContext.planner,
        allowedTargets: mode.craftableNames,
        checkPrices: (request) {
          final refresh = refreshes[refreshCount];
          refreshCount += 1;
          return refresh.future;
        },
      );
      await tester.pumpWidget(
        _host(
          RecipeBookModal(
            controller: book,
            onClose: () {},
            onActivated: (_) {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(RecipeBookKeys.r25MarketControls), findsNothing);
      await tester.tap(find.byKey(RecipeBookKeys.r21CheckMarket));
      await tester.pump();

      expect(refreshCount, 0);
      expect(book.marketLoading, isTrue);
      expect(find.byKey(RecipeBookKeys.r25MarketControls), findsOneWidget);
      expect(find.byKey(RecipeBookKeys.r22OutOfStockOnly), findsOneWidget);
      expect(find.byKey(RecipeBookKeys.r28ProfitableOnly), findsOneWidget);
      expect(find.byKey(RecipeBookKeys.r23MarketSort), findsOneWidget);
      expect(find.text('Hide Market'), findsOneWidget);
      expect(find.text('Checking market...'), findsNothing);
      expect(find.text('MARKET STOCK'), findsNothing);
      expect(tester.takeException(), isNull);

      final marketToggleRect = tester.getRect(
        find.byKey(RecipeBookKeys.r21CheckMarket),
      );
      final refreshRect = tester.getRect(
        find.byKey(RecipeBookKeys.r24RefreshMarket),
      );
      final outOfStockRect = tester.getRect(
        find.byKey(RecipeBookKeys.r22OutOfStockOnly),
      );
      final profitableRect = tester.getRect(
        find.byKey(RecipeBookKeys.r28ProfitableOnly),
      );
      final stockSortRect = tester.getRect(
        find.byKey(RecipeBookKeys.r23MarketSort),
      );
      expect(marketToggleRect.right, lessThan(refreshRect.left));
      expect(refreshRect.right, lessThan(outOfStockRect.left));
      expect(outOfStockRect.right, lessThan(profitableRect.left));
      expect(profitableRect.right, lessThan(stockSortRect.left));
      for (final rect in <Rect>[
        refreshRect,
        outOfStockRect,
        profitableRect,
        stockSortRect,
      ]) {
        expect(
          (rect.center.dy - marketToggleRect.center.dy).abs(),
          lessThanOrEqualTo(2),
        );
      }

      final spinning = find.byKey(RecipeBookKeys.r24RefreshGlyph);
      final before = tester.widget<RotationTransition>(spinning).turns.value;
      await tester.pump(const Duration(milliseconds: 24));
      final during = tester.widget<RotationTransition>(spinning).turns.value;
      expect(during, isNot(equals(before)));
      expect(refreshCount, 0);
      await tester.pump(const Duration(milliseconds: 30));
      expect(refreshCount, 1);

      refreshes[0].complete(
        const PlannerMarketRefresh(
          prices: <String, double>{},
          stock: <String, double>{
            'Clear Liquid Reagent': 0,
            'Pure Powder Reagent': 12,
            'Elixir of Life': 3,
          },
          unlistedItemNames: <String>{},
          fetchedAt: 42,
          summary:
              'Market updated for 75 material(s); 500 request(s) failed and '
              '0 material(s) need a market ID.',
        ),
      );
      await tester.pump();
      await tester.pumpAndSettle();

      expect(book.marketLoading, isFalse);
      expect(find.text('Hide Market'), findsOneWidget);
      expect(
        find.text('Some market data could not be loaded.'),
        findsOneWidget,
      );
      expect(find.textContaining('500 request(s)'), findsNothing);
      expect(find.text('Sort ↕'), findsOneWidget);

      await tester.tap(find.byKey(RecipeBookKeys.r23MarketSort));
      await tester.pumpAndSettle();
      expect(find.text('Stock ↑'), findsOneWidget);
      expect(find.text('Stock ↓'), findsOneWidget);
      await tester.tap(find.text('Stock ↑'));
      await tester.pumpAndSettle();
      expect(book.marketSort, RecipeBookMarketSort.stockLowToHigh);

      final stopped = tester.widget<RotationTransition>(spinning).turns.value;
      await tester.pump(const Duration(milliseconds: 225));
      expect(tester.widget<RotationTransition>(spinning).turns.value, stopped);

      await tester.tap(find.byKey(RecipeBookKeys.r24RefreshMarket));
      await tester.pump();
      expect(book.marketLoading, isTrue);
      expect(refreshCount, 1);
      final refreshBefore = tester
          .widget<RotationTransition>(spinning)
          .turns
          .value;
      await tester.pump(const Duration(milliseconds: 24));
      final refreshDuring = tester
          .widget<RotationTransition>(spinning)
          .turns
          .value;
      expect(refreshDuring, isNot(equals(refreshBefore)));
      await tester.pump(const Duration(milliseconds: 30));
      expect(refreshCount, 2);
      refreshes[1].complete(
        const PlannerMarketRefresh(
          prices: <String, double>{},
          stock: <String, double>{
            'Clear Liquid Reagent': 4,
            'Pure Powder Reagent': 12,
            'Elixir of Life': 3,
          },
          unlistedItemNames: <String>{},
          fetchedAt: 43,
          summary: 'Market updated for 3 material(s).',
        ),
      );
      await tester.pump();
      await tester.pumpAndSettle();
      expect(book.marketLoading, isFalse);
      expect(find.text('Checking market...'), findsNothing);
      expect(find.textContaining('material(s)'), findsNothing);

      await tester.tap(find.byKey(RecipeBookKeys.r21CheckMarket));
      await tester.pumpAndSettle();
      expect(find.byKey(RecipeBookKeys.r25MarketControls), findsNothing);

      await tester.pumpWidget(const SizedBox.shrink());
      book.dispose();
      await environment.dispose();
    },
  );

  testWidgets(
    'market command row stays left-aligned and keeps editor actions separate',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      final themes = <ThemeSpec>[
        StandardSpec.theme,
        SakuraNightGardenSpec.theme,
        IlluminatedLedgerSpec.theme,
      ];
      for (final size in const <Size>[Size(1200, 752), Size(1500, 940)]) {
        tester.view.physicalSize = size;
        for (final spec in themes) {
          final environment = buildRecipeBookTestEnvironment(
            activeMode: CraftMode.processing,
            showDeleteTools: true,
          );
          final mode = environment.application.modes[CraftMode.processing]!;
          final book = RecipeBookController(
            modeController: mode,
            catalogRepository: environment.catalogRepository,
            callingContext: RecipeBookCallingContext.planner,
            allowedTargets: mode.craftableNames,
          );
          await tester.pumpWidget(
            _host(
              RecipeBookModal(
                controller: book,
                onClose: () {},
                onActivated: (_) {},
              ),
              spec: spec,
            ),
          );
          await tester.pumpAndSettle();

          final checkMarket = find.byKey(RecipeBookKeys.r21CheckMarket);
          final delete = find.byKey(RecipeBookKeys.r17SelectToDelete);
          final favorites = find.byKey(RecipeBookKeys.r04FavoritesOnly);
          expect(checkMarket, findsOneWidget);
          expect(delete, findsOneWidget);
          expect(find.byKey(RecipeBookKeys.r25MarketControls), findsNothing);
          expect(find.text('MARKET STOCK'), findsNothing);
          final closedMarketRect = tester.getRect(checkMarket);
          final deleteRect = tester.getRect(delete);
          expect(closedMarketRect.left, lessThan(deleteRect.left));
          expect(
            tester.getRect(favorites).bottom,
            lessThan(closedMarketRect.top),
          );
          final closedException = tester.takeException();
          expect(
            closedException,
            isNull,
            reason:
                '${spec.id} at ${size.width.toInt()}×'
                '${size.height.toInt()} closed market row must not overflow\n'
                '${closedException is FlutterError ? closedException.toStringDeep() : closedException}',
          );

          await tester.tap(checkMarket);
          await tester.pumpAndSettle();

          final ordered = <Rect>[
            tester.getRect(find.byKey(RecipeBookKeys.r21CheckMarket)),
            tester.getRect(find.byKey(RecipeBookKeys.r24RefreshMarket)),
            tester.getRect(find.byKey(RecipeBookKeys.r22OutOfStockOnly)),
            tester.getRect(find.byKey(RecipeBookKeys.r28ProfitableOnly)),
            tester.getRect(find.byKey(RecipeBookKeys.r23MarketSort)),
          ];
          for (var index = 1; index < ordered.length; index += 1) {
            expect(
              ordered[index - 1].right,
              lessThan(ordered[index].left),
              reason:
                  '${spec.id} at ${size.width.toInt()}×'
                  '${size.height.toInt()} keeps market commands ordered',
            );
            expect(
              (ordered[index].center.dy - ordered.first.center.dy).abs(),
              lessThanOrEqualTo(2),
              reason:
                  '${spec.id} at ${size.width.toInt()}×'
                  '${size.height.toInt()} vertically centers market commands',
            );
          }
          expect(ordered.first.left, closeTo(closedMarketRect.left, .1));
          expect(ordered.last.right, lessThan(deleteRect.left));
          expect(find.text('MARKET STOCK'), findsNothing);
          expect(
            tester.takeException(),
            isNull,
            reason:
                '${spec.id} at ${size.width.toInt()}×'
                '${size.height.toInt()} must not overflow',
          );

          await tester.pumpWidget(const SizedBox.shrink());
          book.dispose();
          await environment.dispose();
        }
      }
    },
  );

  testWidgets(
    'profitable mode shows compact per-piece estimates and combines with stock',
    (tester) async {
      await _setSize(tester, const Size(1200, 752));
      final environment = buildRecipeBookTestEnvironment();
      final mode = environment.application.modes[CraftMode.alchemy]!;
      const ids = <String, String>{
        'Clear Liquid Reagent': '5301',
        'Pure Powder Reagent': '5302',
        'Elixir of Life': '5303',
        'Wild Grass': '5304',
        'Sunflower': '5305',
        'Trace of Earth': '5306',
      };
      mode.updateState(
        (state) => state.copyWith(
          ingredientMeta: <String, IngredientMetadata>{
            for (final entry in ids.entries)
              entry.key: IngredientMetadata(marketId: entry.value),
          },
        ),
        immediate: true,
      );
      final book = RecipeBookController(
        modeController: mode,
        catalogRepository: environment.catalogRepository,
        callingContext: RecipeBookCallingContext.planner,
        allowedTargets: mode.craftableNames,
        checkPrices: (_) async => const PlannerMarketRefresh(
          prices: <String, double>{
            'Clear Liquid Reagent': 1000,
            'Pure Powder Reagent': 500,
            'Elixir of Life': 2000,
            'Wild Grass': 100,
            'Sunflower': 100,
            'Trace of Earth': 400,
          },
          stock: <String, double>{
            'Clear Liquid Reagent': 0,
            'Pure Powder Reagent': 12,
            'Elixir of Life': 3,
            'Wild Grass': 1000,
            'Sunflower': 1000,
            'Trace of Earth': 1000,
          },
          unlistedItemNames: <String>{},
          fetchedAt: 42,
          summary: 'Market stock updated.',
        ),
      );
      addTearDown(book.dispose);
      addTearDown(environment.dispose);
      await tester.pumpWidget(
        _host(
          RecipeBookModal(
            controller: book,
            onClose: () {},
            onActivated: (_) {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(RecipeBookKeys.r21CheckMarket));
      await tester.pumpAndSettle();
      expect(
        find.byKey(RecipeBookKeys.profitPill('Clear Liquid Reagent')),
        findsNothing,
      );

      await tester.tap(find.byKey(RecipeBookKeys.r28ProfitableOnly));
      await tester.pumpAndSettle();
      expect(book.profitableOnly, isTrue);
      expect(book.marketSort, RecipeBookMarketSort.profitHighToLow);
      expect(
        find.byKey(RecipeBookKeys.profitPill('Clear Liquid Reagent')),
        findsOneWidget,
      );
      expect(
        find.byKey(RecipeBookKeys.profitPill('Elixir of Life')),
        findsOneWidget,
      );
      expect(
        find.byKey(RecipeBookKeys.card('Pure Powder Reagent')),
        findsNothing,
      );
      for (final name in const <String>[
        'Clear Liquid Reagent',
        'Elixir of Life',
      ]) {
        expect(
          find.descendant(
            of: find.byKey(RecipeBookKeys.profitPill(name)),
            matching: find.textContaining('/ea'),
          ),
          findsOneWidget,
        );
      }
      expect(tester.takeException(), isNull);

      await tester.tap(find.byKey(RecipeBookKeys.r23MarketSort));
      await tester.pumpAndSettle();
      expect(find.text('Profit/ea ↑'), findsOneWidget);
      expect(find.text('Profit/ea ↓'), findsWidgets);
      await tester.tap(find.text('Profit/ea ↑'));
      await tester.pumpAndSettle();
      expect(book.marketSort, RecipeBookMarketSort.profitLowToHigh);

      await tester.tap(find.byKey(RecipeBookKeys.r22OutOfStockOnly));
      await tester.pumpAndSettle();
      expect(
        find.byKey(RecipeBookKeys.profitPill('Clear Liquid Reagent')),
        findsOneWidget,
      );
      expect(
        find.byKey(RecipeBookKeys.profitPill('Elixir of Life')),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'simple books keep filters and market actions in one clear row in every theme',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      final themes = <ThemeSpec>[
        StandardSpec.theme,
        SakuraNightGardenSpec.theme,
        IlluminatedLedgerSpec.theme,
      ];
      for (final size in const <Size>[Size(1200, 752), Size(1500, 940)]) {
        tester.view.physicalSize = size;
        for (final craftMode in const <CraftMode>[
          CraftMode.alchemy,
          CraftMode.cooking,
        ]) {
          for (final spec in themes) {
            final environment = buildRecipeBookTestEnvironment(
              activeMode: craftMode,
              showDeleteTools: true,
            );
            final mode = environment.application.modes[craftMode]!;
            final book = RecipeBookController(
              modeController: mode,
              catalogRepository: environment.catalogRepository,
              callingContext: RecipeBookCallingContext.planner,
              allowedTargets: mode.craftableNames,
            );
            await tester.pumpWidget(
              _host(
                RecipeBookModal(
                  controller: book,
                  onClose: () {},
                  onActivated: (_) {},
                ),
                spec: spec,
              ),
            );
            await tester.pumpAndSettle();

            final favorites = find.byKey(RecipeBookKeys.r04FavoritesOnly);
            final checkMarket = find.byKey(RecipeBookKeys.r21CheckMarket);
            final delete = find.byKey(RecipeBookKeys.r17SelectToDelete);
            final searchRect = tester.getRect(
              find.byKey(RecipeBookKeys.r03Search),
            );
            final scopeRect = tester.getRect(
              find.byKey(RecipeBookKeys.r05ScopeGroup),
            );
            final ingredientRect = tester.getRect(
              find.byKey(RecipeBookKeys.r05SearchByIngredient),
            );
            final favoritesRect = tester.getRect(favorites);
            final closedMarketRect = tester.getRect(checkMarket);
            final deleteRect = delete.evaluate().isEmpty
                ? null
                : tester.getRect(delete);
            expect(searchRect.width, inInclusiveRange(500, 560));
            expect(scopeRect.width, closeTo(316, .1));
            expect(scopeRect.left - searchRect.right, closeTo(14, .1));
            expect(
              (searchRect.bottom - ingredientRect.bottom).abs(),
              lessThanOrEqualTo(1),
            );
            expect(favoritesRect.right, lessThan(closedMarketRect.left));
            expect(
              (favoritesRect.center.dy - closedMarketRect.center.dy).abs(),
              lessThanOrEqualTo(2),
            );
            if (deleteRect != null) {
              expect(closedMarketRect.right, lessThan(deleteRect.left));
            }

            await tester.tap(checkMarket);
            await tester.pumpAndSettle();

            final ordered = <Rect>[
              tester.getRect(find.byKey(RecipeBookKeys.r21CheckMarket)),
              tester.getRect(find.byKey(RecipeBookKeys.r24RefreshMarket)),
              tester.getRect(find.byKey(RecipeBookKeys.r22OutOfStockOnly)),
              tester.getRect(find.byKey(RecipeBookKeys.r28ProfitableOnly)),
              tester.getRect(find.byKey(RecipeBookKeys.r23MarketSort)),
            ];
            expect(ordered.first.left, closeTo(closedMarketRect.left, .1));
            for (var index = 1; index < ordered.length; index += 1) {
              expect(ordered[index - 1].right, lessThan(ordered[index].left));
              expect(
                (ordered[index].center.dy - ordered.first.center.dy).abs(),
                lessThanOrEqualTo(2),
              );
            }
            expect(
              (favoritesRect.center.dy - ordered.first.center.dy).abs(),
              lessThanOrEqualTo(2),
            );
            if (deleteRect != null) {
              expect(ordered.last.right, lessThan(deleteRect.left));
            }
            expect(
              tester.takeException(),
              isNull,
              reason:
                  '${craftMode.name}/${spec.id} at '
                  '${size.width.toInt()}×${size.height.toInt()} must not '
                  'overflow',
            );

            await tester.pumpWidget(const SizedBox.shrink());
            book.dispose();
            await environment.dispose();
          }
        }
      }
    },
  );

  testWidgets(
    'physical-input query remains authoritative across modal refreshes',
    (tester) async {
      await _setSize(tester, const Size(1200, 752));
      final environment = buildRecipeBookTestEnvironment();
      final mode = environment.application.modes[CraftMode.alchemy]!;
      final book = RecipeBookController(
        modeController: mode,
        catalogRepository: environment.catalogRepository,
        callingContext: RecipeBookCallingContext.planner,
        allowedTargets: mode.craftableNames,
        initialSearch: 'Clear',
      );
      final modal = RecipeBookModal(
        controller: book,
        onClose: () {},
        onActivated: (_) {},
      );
      await tester.pumpWidget(_host(modal));
      await tester.pumpAndSettle();

      final search = find.descendant(
        of: find.byKey(RecipeBookKeys.r03Search),
        matching: find.byType(TextField),
      );
      await tester.tap(search);
      await tester.enterText(search, 'Clearzz');
      await tester.pump();
      await tester.pump();
      expect(book.search, 'Clearzz');
      expect(tester.widget<TextField>(search).controller!.text, 'Clearzz');
      expect(find.text('0 recipes'), findsOneWidget);

      // Persisted filter notifications and a parent-widget refresh must not
      // restore the search value captured when the modal first opened.
      book.setFavoritesOnly(true);
      await tester.pump();
      await tester.pumpWidget(_host(modal));
      await tester.pump();
      expect(book.search, 'Clearzz');
      expect(tester.widget<TextField>(search).controller!.text, 'Clearzz');
      expect(find.text('0 favorites'), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      book.dispose();
      await environment.dispose();
    },
  );

  testWidgets(
    'Illuminated Ledger book uses retained plate, card, action, and preview geometry',
    (tester) async {
      await _setSize(tester, const Size(1500, 940));
      final environment = buildRecipeBookTestEnvironment();
      final mode = environment.application.modes[CraftMode.alchemy]!;
      const adaptation = 'Adaptation Draught';
      mode.updateState(
        (state) => state.copyWith(
          recipeEdits: <String, RecipeState?>{
            ...state.recipeEdits,
            adaptation: RecipeState(
              type: 'simple_alchemy',
              baseOutput: 10,
              group: null,
              method: 'Simple Alchemy',
              ingredients: <IngredientState>[
                IngredientState(
                  name: 'Elixir of Life',
                  quantity: 30,
                  options: <String>[],
                  substituteGroup: null,
                  substituteRatios: <String, double>{},
                ),
                IngredientState(
                  name: 'Pure Powder Reagent',
                  quantity: 30,
                  options: <String>[],
                  substituteGroup: null,
                  substituteRatios: <String, double>{},
                ),
                IngredientState(
                  name: 'Wild Grass',
                  quantity: 30,
                  options: <String>[],
                  substituteGroup: null,
                  substituteRatios: <String, double>{},
                ),
                IngredientState(
                  name: 'Weed',
                  quantity: 30,
                  options: <String>[],
                  substituteGroup: null,
                  substituteRatios: <String, double>{},
                ),
                IngredientState(
                  name: 'Sunflower',
                  quantity: 10,
                  options: <String>[],
                  substituteGroup: null,
                  substituteRatios: <String, double>{},
                ),
              ],
              marketId: null,
              sourceNote: null,
              vendor: null,
              location: null,
              npcPrice: 0,
              qualityBase: null,
              qualityGrade: null,
              outputMinimum: null,
              outputMaximum: null,
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
      );
      await tester.pumpWidget(
        _host(
          RecipeBookModal(
            controller: book,
            onClose: () {},
            onActivated: (_) {},
          ),
          spec: IlluminatedLedgerSpec.theme,
        ),
      );
      await tester.pumpAndSettle();

      expect(
        tester.getSize(find.byKey(RecipeBookKeys.r04FavoritesOnly)).height,
        36,
      );
      expect(
        tester.getSize(find.byKey(RecipeBookKeys.r05SearchByIngredient)).height,
        38,
      );
      expect(
        tester
            .renderObject<RenderParagraph>(find.text('Favorites'))
            .didExceedMaxLines,
        isFalse,
      );
      expect(
        tester
            .renderObject<RenderParagraph>(find.text('Ingredient'))
            .didExceedMaxLines,
        isFalse,
      );
      expect(
        tester.getSize(find.byKey(RecipeBookKeys.card(adaptation))),
        const Size(279, 198),
      );
      final adaptationCard = find.byKey(RecipeBookKeys.card(adaptation));
      final adaptationMethod = find.descendant(
        of: adaptationCard,
        matching: find.byKey(RecipeBookKeys.productionMethod(adaptation)),
      );
      expect(adaptationMethod, findsOneWidget);
      expect(tester.widget<Text>(adaptationMethod).data, 'Simple Alchemy');
      expect(
        tester.getSize(find.byKey(RecipeBookKeys.r11Target(adaptation))),
        const Size(96, 34),
      );
      final cardRect = tester.getRect(
        find.byKey(RecipeBookKeys.card(adaptation)),
      );
      final targetRect = tester.getRect(
        find.byKey(RecipeBookKeys.r11Target(adaptation)),
      );
      final previewRect = tester.getRect(
        find.byKey(RecipeBookKeys.r13Details(adaptation)),
      );
      final favoriteRect = tester.getRect(
        find.byKey(RecipeBookKeys.r12Favorite(adaptation)),
      );
      expect(cardRect.contains(targetRect.bottomLeft), isTrue);
      expect(cardRect.contains(previewRect.bottomRight), isTrue);
      expect(cardRect.contains(favoriteRect.topRight), isTrue);
      expect(previewRect.left, greaterThan(targetRect.right));
      expect(previewRect.center.dy, closeTo(targetRect.center.dy, .1));
      expect(favoriteRect.center.dy, lessThan(previewRect.center.dy));
      expect(
        tester.widget<AppButton>(find.byKey(RecipeBookKeys.r02Close)).role,
        AppButtonRole.primary,
      );
      expect(
        tester
            .widget<AppButton>(
              find.byKey(RecipeBookKeys.r13Details(adaptation)),
            )
            .role,
        AppButtonRole.primary,
      );
      expect(
        tester
            .widget<AppButton>(find.byKey(RecipeBookKeys.r11Target(adaptation)))
            .role,
        AppButtonRole.primary,
      );

      await tester.tap(find.byKey(RecipeBookKeys.r13Details(adaptation)));
      await tester.pumpAndSettle();
      expect(find.text('Crafted / Simple Alchemy'), findsOneWidget);
      expect(
        tester
            .widget<AppButton>(
              find.byKey(RecipeBookKeys.r14ClosePreview(adaptation)),
            )
            .role,
        AppButtonRole.primary,
      );
      expect(
        find.byKey(
          RecipeBookKeys.previewQuantity(adaptation, 'Elixir of Life'),
        ),
        findsNothing,
      );
      expect(find.text('Need 30'), findsWidgets);
      expect(
        tester.getSize(
          find.byKey(
            RecipeBookKeys.r16Quality(adaptation, 'Sunflower', 'normal'),
          ),
        ),
        const Size.square(26),
      );

      await tester.pumpWidget(const SizedBox.shrink());
      book.dispose();
      await environment.dispose();
    },
  );

  testWidgets('Illuminated Ledger keeps four responsive columns at 1200x752', (
    tester,
  ) async {
    await _setSize(tester, const Size(1200, 752));
    final environment = buildRecipeBookTestEnvironment();
    final mode = environment.application.modes[CraftMode.alchemy]!;
    final book = RecipeBookController(
      modeController: mode,
      catalogRepository: environment.catalogRepository,
      callingContext: RecipeBookCallingContext.planner,
      allowedTargets: mode.craftableNames,
    );
    await tester.pumpWidget(
      _host(
        RecipeBookModal(controller: book, onClose: () {}, onActivated: (_) {}),
        spec: IlluminatedLedgerSpec.theme,
      ),
    );
    await tester.pumpAndSettle();

    expect(
      tester.getRect(find.byKey(RecipeBookKeys.modal)),
      const Rect.fromLTWH(46, 43, 1108, 666),
    );
    expect(
      tester.getSize(find.byKey(RecipeBookKeys.card('Clear Liquid Reagent'))),
      const Size(251, 198),
    );
    expect(
      tester.getSize(
        find.byKey(RecipeBookKeys.r11Target('Clear Liquid Reagent')),
      ),
      const Size(96, 34),
    );
    expect(
      tester
          .renderObject<RenderParagraph>(find.text('Favorites'))
          .didExceedMaxLines,
      isFalse,
    );
    expect(
      tester
          .renderObject<RenderParagraph>(find.text('Ingredient'))
          .didExceedMaxLines,
      isFalse,
    );
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    book.dispose();
    await environment.dispose();
  });

  for (final size in <Size>[const Size(1200, 752), const Size(1500, 940)]) {
    testWidgets('Recipe Book uses one clear control hierarchy at '
        '${size.width.toInt()}x${size.height.toInt()}', (tester) async {
      await _setSize(tester, size);
      for (final spec in <ThemeSpec>[
        StandardSpec.theme,
        SakuraNightGardenSpec.theme,
        IlluminatedLedgerSpec.theme,
      ]) {
        final environment = buildRecipeBookTestEnvironment(
          activeMode: CraftMode.processing,
          showDeleteTools: true,
        );
        final mode = environment.application.modes[CraftMode.processing]!;
        final hiddenName = mode.craftableNames.first;
        mode.updateState(
          (state) => state.copyWith(
            hiddenItems: <String>[hiddenName],
            recipeEdits: <String, RecipeState?>{
              ...state.recipeEdits,
              hiddenName: null,
            },
          ),
          immediate: true,
        );
        final book = RecipeBookController(
          modeController: mode,
          catalogRepository: environment.catalogRepository,
          callingContext: RecipeBookCallingContext.planner,
          allowedTargets: mode.craftableNames,
        );
        await tester.pumpWidget(
          _host(
            RecipeBookModal(
              controller: book,
              onClose: () {},
              onActivated: (_) {},
            ),
            spec: spec,
          ),
        );
        await tester.pumpAndSettle();

        final favorites = find.byKey(RecipeBookKeys.r04FavoritesOnly);
        final recipeNameScope = find.byKey(RecipeBookKeys.r05RecipeNameScope);
        final ingredientScope = find.byKey(
          RecipeBookKeys.r05SearchByIngredient,
        );
        final category = find.byKey(RecipeBookKeys.r07Groups);
        final showHidden = find.byKey(RecipeBookKeys.r26ShowHidden);
        final delete = find.byKey(RecipeBookKeys.r17SelectToDelete);
        final search = find.byKey(RecipeBookKeys.r03Search);

        for (final control in <Finder>[favorites, showHidden]) {
          expect(
            find.descendant(of: control, matching: find.byType(AppButton)),
            findsOneWidget,
          );
          expect(
            find.descendant(of: control, matching: find.byType(AppToggle)),
            findsNothing,
          );
          expect(tester.getSize(control).height, 36);
          expect(_checkGlyphsWithin(control), findsNothing);
        }
        for (final control in <Finder>[recipeNameScope, ingredientScope]) {
          expect(
            find.descendant(of: control, matching: find.byType(AppButton)),
            findsOneWidget,
          );
          expect(tester.getSize(control).height, 38);
        }
        for (final label in <String>[
          'Favorites',
          'Recipe name',
          'Ingredient',
          'Hidden (1)',
        ]) {
          expect(
            tester
                .renderObject<RenderParagraph>(find.text(label))
                .didExceedMaxLines,
            isFalse,
            reason:
                '$label must fit in ${spec.id} at '
                '${size.width.toInt()}x${size.height.toInt()}',
          );
        }

        final searchRect = tester.getRect(search);
        final scopeRect = tester.getRect(
          find.byKey(RecipeBookKeys.r05ScopeGroup),
        );
        final recipeNameScopeRect = tester.getRect(recipeNameScope);
        final ingredientScopeRect = tester.getRect(ingredientScope);
        expect(searchRect.width, inInclusiveRange(500, 560));
        expect(scopeRect.width, closeTo(316, .1));
        expect(scopeRect.left - searchRect.right, closeTo(14, .1));
        expect(searchRect.right, lessThan(recipeNameScopeRect.left));
        expect(
          (searchRect.bottom - ingredientScopeRect.bottom).abs(),
          lessThanOrEqualTo(1),
        );
        final searchHeadingRect = tester.getRect(find.text('SEARCH RECIPES'));
        final scopeHeadingRect = tester.getRect(find.text('SEARCH BY'));
        expect(
          (searchHeadingRect.top - scopeHeadingRect.top).abs(),
          lessThanOrEqualTo(1),
        );
        final categoryRect = tester.getRect(category);
        final favoritesRect = tester.getRect(favorites);
        final hiddenRect = tester.getRect(showHidden);
        final deleteRect = tester.getRect(delete);
        expect(categoryRect.right, lessThan(favoritesRect.left));
        expect(favoritesRect.right, lessThan(hiddenRect.left));
        expect(hiddenRect.right, lessThan(deleteRect.left));
        expect(ingredientScopeRect.bottom, lessThan(categoryRect.top));

        final favoritesSemantics = find.semantics.byLabel('Favorites only');
        expect(favoritesSemantics, findsOne);
        expect(
          favoritesSemantics.evaluate().single,
          isSemantics(
            label: 'Favorites only',
            isButton: true,
            hasEnabledState: true,
            isEnabled: true,
            hasToggledState: true,
            isToggled: false,
            hasTapAction: true,
          ),
        );

        await tester.tap(favorites);
        await tester.pump();
        expect(book.favoritesOnly, isTrue);
        expect(_checkGlyphsWithin(favorites), findsOneWidget);
        expect(
          favoritesSemantics.evaluate().single,
          isSemantics(
            label: 'Favorites only',
            isButton: true,
            hasEnabledState: true,
            isEnabled: true,
            hasToggledState: true,
            isToggled: true,
            hasTapAction: true,
          ),
        );

        expect(
          tester
              .widget<AppButton>(
                find.descendant(
                  of: recipeNameScope,
                  matching: find.byType(AppButton),
                ),
              )
              .selected,
          isTrue,
        );
        await tester.tap(ingredientScope);
        await tester.pump();
        expect(book.searchByIngredient, isTrue);
        expect(
          tester
              .widget<AppButton>(
                find.descendant(
                  of: ingredientScope,
                  matching: find.byType(AppButton),
                ),
              )
              .selected,
          isTrue,
        );
        await tester.tap(recipeNameScope);
        await tester.pump();
        expect(book.searchByIngredient, isFalse);

        await tester.tap(showHidden);
        await tester.pumpAndSettle();
        expect(book.showHidden, isTrue);
        expect(_checkGlyphsWithin(showHidden), findsOneWidget);

        await tester.tap(find.byKey(RecipeBookKeys.r21CheckMarket));
        await tester.pumpAndSettle();
        final outOfStock = find.byKey(RecipeBookKeys.r22OutOfStockOnly);
        expect(outOfStock, findsOneWidget);
        expect(
          find.descendant(of: outOfStock, matching: find.byType(AppButton)),
          findsOneWidget,
        );
        expect(
          find.descendant(of: outOfStock, matching: find.byType(AppToggle)),
          findsNothing,
        );
        expect(tester.getSize(outOfStock).height, 36);
        expect(
          tester
              .renderObject<RenderParagraph>(find.text('Out of stock'))
              .didExceedMaxLines,
          isFalse,
        );

        await tester.tap(outOfStock);
        await tester.pump();
        expect(book.outOfStockOnly, isTrue);
        expect(_checkGlyphsWithin(outOfStock), findsOneWidget);
        expect(
          tester.takeException(),
          isNull,
          reason:
              '${spec.id} at ${size.width.toInt()}x'
              '${size.height.toInt()} must not overflow',
        );

        await tester.pumpWidget(const SizedBox.shrink());
        book.dispose();
        await environment.dispose();
      }
    });
  }

  testWidgets('Recipe Book filter chips support Enter and Space', (
    tester,
  ) async {
    await _setSize(tester, const Size(1200, 752));
    final environment = buildRecipeBookTestEnvironment(
      activeMode: CraftMode.processing,
    );
    final mode = environment.application.modes[CraftMode.processing]!;
    final book = RecipeBookController(
      modeController: mode,
      catalogRepository: environment.catalogRepository,
      callingContext: RecipeBookCallingContext.planner,
      allowedTargets: mode.craftableNames,
    );
    await tester.pumpWidget(
      _host(
        RecipeBookModal(controller: book, onClose: () {}, onActivated: (_) {}),
      ),
    );
    await tester.pumpAndSettle();

    final favorites = find.byKey(RecipeBookKeys.r04FavoritesOnly);
    await tester.tap(favorites);
    await tester.pump();
    expect(book.favoritesOnly, isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump();
    expect(book.favoritesOnly, isFalse);

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(book.favoritesOnly, isTrue);
    expect(_checkGlyphsWithin(favorites), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    book.dispose();
    await environment.dispose();
  });

  testWidgets(
    'Recipe Book toolbar remains readable at enlarged text in every theme',
    (tester) async {
      await _setSize(tester, const Size(1200, 752));
      for (final textScale in const <double>[1.35, 2]) {
        for (final spec in <ThemeSpec>[
          StandardSpec.theme,
          SakuraNightGardenSpec.theme,
          IlluminatedLedgerSpec.theme,
        ]) {
          for (final craftMode in const <CraftMode>[
            CraftMode.alchemy,
            CraftMode.processing,
          ]) {
            final environment = buildRecipeBookTestEnvironment(
              activeMode: craftMode,
              showDeleteTools: true,
            );
            final processing =
                environment.application.modes[CraftMode.processing]!;
            final hiddenName = processing.craftableNames.first;
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
            final mode = environment.application.modes[craftMode]!;
            final book = RecipeBookController(
              modeController: mode,
              catalogRepository: environment.catalogRepository,
              callingContext: RecipeBookCallingContext.planner,
              allowedTargets: mode.craftableNames,
            );
            await tester.pumpWidget(
              _host(
                RecipeBookModal(
                  controller: book,
                  onClose: () {},
                  onActivated: (_) {},
                ),
                spec: spec,
                textScaler: TextScaler.linear(textScale),
              ),
            );
            await tester.pumpAndSettle();

            final search = find.byKey(RecipeBookKeys.r03Search);
            final searchRect = tester.getRect(search);
            final scopeRect = tester.getRect(
              find.byKey(RecipeBookKeys.r05ScopeGroup),
            );
            expect(searchRect.width, inInclusiveRange(500, 560));
            expect(searchRect.height, greaterThanOrEqualTo(42));
            if (textScale == 2 && spec.isStandard) {
              expect(searchRect.height, greaterThan(42));
            }
            expect(scopeRect.top, greaterThan(searchRect.bottom));
            expect(
              scopeRect.width,
              closeTo((316 * textScale).roundToDouble(), .1),
            );

            await tester.enterText(
              search,
              'a deliberately long recipe search query',
            );
            await tester.pump();
            expect(find.byKey(RecipeBookKeys.r03ClearSearch), findsOneWidget);
            await tester.tap(find.byKey(RecipeBookKeys.r03ClearSearch));
            await tester.pump();
            expect(book.search, isEmpty);

            await tester.tap(find.byKey(RecipeBookKeys.r21CheckMarket));
            await tester.pumpAndSettle();

            for (final label in <String>[
              'SEARCH RECIPES',
              'SEARCH BY',
              'Favorites',
              'Recipe name',
              'Ingredient',
              'Hidden (1)',
              'Hide Market',
              'Out of stock',
            ]) {
              expect(find.text(label), findsOneWidget);
              expect(
                tester
                    .renderObject<RenderParagraph>(find.text(label))
                    .didExceedMaxLines,
                isFalse,
                reason:
                    '$label must remain readable in '
                    '${craftMode.name}/${spec.id} at ${textScale}x',
              );
            }
            expect(
              tester.takeException(),
              isNull,
              reason:
                  '${craftMode.name}/${spec.id} must not overflow at '
                  '${textScale}x text',
            );

            await tester.pumpWidget(const SizedBox.shrink());
            book.dispose();
            await environment.dispose();
          }
        }
      }
    },
  );

  testWidgets('calling context activation and backdrop close are exact', (
    tester,
  ) async {
    await _setSize(tester, const Size(1200, 752));
    final environment = buildRecipeBookTestEnvironment();
    final mode = environment.application.modes[CraftMode.alchemy]!;
    final book = RecipeBookController(
      modeController: mode,
      catalogRepository: environment.catalogRepository,
      callingContext: RecipeBookCallingContext.bonus,
      allowedTargets: const <String>['Elixir of Life', 'Pure Powder Reagent'],
    );
    RecipeBookActivation? activation;
    var closed = false;
    await tester.pumpWidget(
      _host(
        RecipeBookModal(
          controller: book,
          onClose: () => closed = true,
          onActivated: (value) => activation = value,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(RecipeBookKeys.r11Target('Pure Powder Reagent')),
    );
    await tester.pump();
    expect(activation?.exactName, 'Pure Powder Reagent');
    expect(activation?.context, RecipeBookCallingContext.bonus);
    expect(mode.state.value.bonusTarget, 'Pure Powder Reagent');
    expect(mode.state.value.target, 'Clear Liquid Reagent');

    await tester.tapAt(const Offset(4, 4));
    await tester.pump();
    expect(closed, isTrue);
    await tester.pumpWidget(const SizedBox.shrink());
    book.dispose();
    await environment.dispose();
  });

  testWidgets('Processing delete tools gate, confirm exact count, and undo', (
    tester,
  ) async {
    await _setSize(tester, const Size(1500, 940));
    final disabledEnvironment = buildRecipeBookTestEnvironment(
      activeMode: CraftMode.processing,
    );
    final disabledMode =
        disabledEnvironment.application.modes[CraftMode.processing]!;
    final disabledBook = RecipeBookController(
      modeController: disabledMode,
      catalogRepository: disabledEnvironment.catalogRepository,
      callingContext: RecipeBookCallingContext.planner,
      allowedTargets: disabledMode.craftableNames,
    );
    await tester.pumpWidget(
      _host(
        RecipeBookModal(
          controller: disabledBook,
          onClose: () {},
          onActivated: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(RecipeBookKeys.r17SelectToDelete), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    disabledBook.dispose();
    await disabledEnvironment.dispose();

    final environment = buildRecipeBookTestEnvironment(
      activeMode: CraftMode.processing,
      showDeleteTools: true,
    );
    final mode = environment.application.modes[CraftMode.processing]!;
    final book = RecipeBookController(
      modeController: mode,
      catalogRepository: environment.catalogRepository,
      callingContext: RecipeBookCallingContext.planner,
      allowedTargets: mode.craftableNames,
    );
    await tester.pumpWidget(
      _host(
        RecipeBookModal(controller: book, onClose: () {}, onActivated: (_) {}),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(RecipeBookKeys.r17SelectToDelete));
    await tester.pump();
    final selected = book.snapshot.entries
        .take(2)
        .map((entry) => entry.name)
        .toList();
    for (final name in selected) {
      await tester.tap(find.byKey(RecipeBookKeys.r19DeleteSelection(name)));
      await tester.pump();
    }
    expect(book.selectedForDeletionCount, 2);
    await tester.tap(find.byKey(RecipeBookKeys.r20DeleteSelected));
    await tester.pump();
    expect(find.text('Hide 2 processing recipes?'), findsOneWidget);
    final confirmationBefore = tester.getRect(
      find.byKey(RecipeBookKeys.r20Confirmation),
    );
    await tester.drag(
      find.byKey(RecipeBookKeys.confirmationDragRegion),
      const Offset(30, 18),
    );
    await tester.pump();
    expect(
      tester.getRect(find.byKey(RecipeBookKeys.r20Confirmation)).topLeft,
      confirmationBefore.topLeft + const Offset(30, 18),
    );
    await tester.tap(find.byKey(RecipeBookKeys.r20Confirm));
    await tester.pumpAndSettle();
    expect(mode.state.value.hiddenItems, containsAll(selected));
    expect(book.deleteSelectionMode, isFalse);
    expect(find.byKey(RecipeBookKeys.r20Undo), findsOneWidget);

    await tester.tap(find.byKey(RecipeBookKeys.r20Undo));
    await tester.pumpAndSettle();
    expect(mode.state.value.hiddenItems, isEmpty);

    await tester.pumpWidget(const SizedBox.shrink());
    book.dispose();
    await environment.dispose();
  });

  testWidgets('Editor Options exposes hidden recipes as marked restore cards', (
    tester,
  ) async {
    await _setSize(tester, const Size(1200, 752));
    final environment = buildRecipeBookTestEnvironment(
      activeMode: CraftMode.processing,
      showDeleteTools: true,
    );
    final mode = environment.application.modes[CraftMode.processing]!;
    final hiddenName = mode.craftableNames.first;
    mode.updateState(
      (state) => state.copyWith(
        hiddenItems: <String>[hiddenName],
        recipeEdits: <String, RecipeState?>{
          ...state.recipeEdits,
          hiddenName: null,
        },
      ),
      immediate: true,
    );
    final book = RecipeBookController(
      modeController: mode,
      catalogRepository: environment.catalogRepository,
      callingContext: RecipeBookCallingContext.planner,
      allowedTargets: mode.craftableNames,
    );
    await tester.pumpWidget(
      _host(
        RecipeBookModal(controller: book, onClose: () {}, onActivated: (_) {}),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(RecipeBookKeys.r26ShowHidden), findsOneWidget);
    expect(
      find.byKey(RecipeBookKeys.r27RestoreHidden(hiddenName)),
      findsNothing,
    );

    await tester.tap(find.byKey(RecipeBookKeys.r26ShowHidden));
    await tester.pumpAndSettle();
    expect(find.text('HIDDEN'), findsOneWidget);
    expect(
      find.byKey(RecipeBookKeys.r27RestoreHidden(hiddenName)),
      findsOneWidget,
    );
    expect(find.byKey(RecipeBookKeys.r11Target(hiddenName)), findsNothing);

    await tester.tap(find.byKey(RecipeBookKeys.r27RestoreHidden(hiddenName)));
    await tester.pumpAndSettle();
    expect(mode.state.value.hiddenItems, isNot(contains(hiddenName)));
    expect(mode.state.value.recipeEdits, isNot(contains(hiddenName)));
    expect(find.byKey(RecipeBookKeys.r26ShowHidden), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    book.dispose();
    await environment.dispose();
  });

  testWidgets('Tab and Shift-Tab remain inside the modal focus scope', (
    tester,
  ) async {
    await _setSize(tester, const Size(1200, 752));
    final environment = buildRecipeBookTestEnvironment();
    final mode = environment.application.modes[CraftMode.alchemy]!;
    final book = RecipeBookController(
      modeController: mode,
      catalogRepository: environment.catalogRepository,
      callingContext: RecipeBookCallingContext.planner,
      allowedTargets: mode.craftableNames,
    );
    final outsideFocus = FocusNode();
    await tester.pumpWidget(
      _host(
        Stack(
          children: <Widget>[
            TextButton(
              focusNode: outsideFocus,
              onPressed: () {},
              child: const Text('Outside modal'),
            ),
            RecipeBookModal(
              controller: book,
              onClose: () {},
              onActivated: (_) {},
            ),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(outsideFocus.hasFocus, isFalse);
    for (var index = 0; index < 30; index++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      expect(outsideFocus.hasFocus, isFalse);
    }
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pump();
    expect(outsideFocus.hasFocus, isFalse);

    await tester.pumpWidget(const SizedBox.shrink());
    outsideFocus.dispose();
    book.dispose();
    await environment.dispose();
  });

  testWidgets('Recipe Book cards render saved custom icons and aliases', (
    tester,
  ) async {
    await _setSize(tester, const Size(1200, 752));
    final stored = (await tester.runAsync(StoredIconTestFixture.create))!;
    addTearDown(() => tester.runAsync(stored.dispose));
    final environment = buildRecipeBookTestEnvironment(
      omittedAlchemyIcons: const <String>{'Elixir of Life'},
    );
    final mode = environment.application.modes[CraftMode.alchemy]!;
    mode.updateState(
      (state) => state.copyWith(
        customIcons: <String, CustomIconReference>{
          'Clear Liquid Reagent': stored.reference,
        },
        iconAliases: const <String, String>{
          'Elixir of Life': 'Pure Powder Reagent',
        },
      ),
      immediate: true,
    );
    final book = RecipeBookController(
      modeController: mode,
      catalogRepository: environment.catalogRepository,
      callingContext: RecipeBookCallingContext.planner,
      allowedTargets: mode.craftableNames,
    );
    await tester.pumpWidget(
      _host(
        RecipeBookModal(controller: book, onClose: () {}, onActivated: (_) {}),
        iconStore: stored.store,
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));

    const customName = 'Clear Liquid Reagent';
    final customImage = find.descendant(
      of: find.byKey(RecipeBookKeys.card(customName)),
      matching: find.byKey(ModeItemIconKeys.image(customName)),
    );
    await pumpUntilIconState(tester, customImage);
    expect(customImage, findsOneWidget);
    expect(
      (tester.widget<Image>(customImage).image as MemoryImage).bytes,
      orderedEquals(stored.bytes),
    );

    const aliasName = 'Elixir of Life';
    final aliasCard = find.byKey(RecipeBookKeys.card(aliasName));
    expect(
      find.descendant(
        of: aliasCard,
        matching: find.byKey(ModeItemIconKeys.image(aliasName)),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: aliasCard,
        matching: find.byKey(ModeItemIconKeys.failure(aliasName)),
      ),
      findsNothing,
    );

    await tester.pumpWidget(const SizedBox.shrink());
    book.dispose();
    await environment.dispose();
  });

  testWidgets(
    'normal Recipe Book item info hovers stay available without delete tools',
    (tester) async {
      await _setSize(tester, const Size(1500, 940));
      final environment = buildRecipeBookTestEnvironment(
        activeMode: CraftMode.processing,
      );
      final mode = environment.application.modes[CraftMode.processing]!;
      final book = RecipeBookController(
        modeController: mode,
        catalogRepository: environment.catalogRepository,
        callingContext: RecipeBookCallingContext.planner,
        allowedTargets: mode.craftableNames,
        initialSearch: 'sov',
      );
      addTearDown(book.dispose);
      addTearDown(environment.dispose);
      await tester.pumpWidget(
        _host(
          RecipeBookModal(
            controller: book,
            onClose: () {},
            onActivated: (_) {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(RecipeBookKeys.card('Black Stone Batch 01')),
        findsOneWidget,
      );
      final tooltip = find.byWidgetPredicate(
        (widget) => widget is Tooltip && widget.richMessage != null,
      );
      expect(tooltip, findsOneWidget);
      tester.state<TooltipState>(tooltip).ensureTooltipVisible();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 180));
      final info = find.byKey(RecipeBookKeys.itemInfo('Black Stone Batch 01'));
      expect(info, findsOneWidget);
      expect(
        find.descendant(of: info, matching: find.text('Recipe & materials')),
        findsOneWidget,
      );
    },
  );

  testWidgets('simple recipe hover stays short and recipe-focused', (
    tester,
  ) async {
    await _setSize(tester, const Size(1200, 752));
    final environment = buildRecipeBookTestEnvironment(
      activeMode: CraftMode.processing,
      showDeleteTools: true,
    );
    final mode = environment.application.modes[CraftMode.processing]!;
    const name = 'Wheat Flour 04';
    final book = RecipeBookController(
      modeController: mode,
      catalogRepository: environment.catalogRepository,
      callingContext: RecipeBookCallingContext.planner,
      allowedTargets: mode.craftableNames,
      initialSearch: name,
    );
    await tester.pumpWidget(
      _host(
        RecipeBookModal(controller: book, onClose: () {}, onActivated: (_) {}),
      ),
    );
    await tester.pumpAndSettle();

    final card = find.byKey(RecipeBookKeys.card(name));
    final tooltip = find.descendant(
      of: card,
      matching: find.byWidgetPredicate(
        (widget) => widget is Tooltip && widget.richMessage != null,
      ),
    );
    expect(tooltip, findsOneWidget);
    tester.state<TooltipState>(tooltip).ensureTooltipVisible();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 180));

    final panel = find.byKey(RecipeBookKeys.itemInfo(name));
    expect(panel, findsOneWidget);
    expect(find.text('Processing material'), findsOneWidget);
    expect(find.text('Description'), findsNothing);
    expect(find.text('Recipe & materials'), findsOneWidget);
    final formula = find.byKey(RecipeBookKeys.itemInfoFormula(name, null, 1));
    final material = find.byKey(
      RecipeBookKeys.itemInfoMaterial(name, null, 'Raw Material 04'),
    );
    expect(formula, findsOneWidget);
    expect(material, findsOneWidget);
    expect(
      find.descendant(of: formula, matching: find.text('Heating')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: material, matching: find.text('×2')),
      findsOneWidget,
    );
    expect(find.text('Used For'), findsNothing);
    expect(tester.getRect(panel).height, lessThan(280));

    await tester.pumpWidget(const SizedBox.shrink());
    book.dispose();
    await environment.dispose();
  });

  testWidgets(
    'item info lays out complete route and batch formulas as readable rows',
    (tester) async {
      final semantics = tester.ensureSemantics();
      await _setSize(tester, const Size(1500, 940));
      final environment = buildRecipeBookTestEnvironment(
        activeMode: CraftMode.alchemy,
        includeUsedInVariantFixture: true,
      );
      addTearDown(environment.dispose);
      final mode = environment.application.modes[CraftMode.alchemy]!;
      const name = 'Elixir of Life';
      final book = RecipeBookController(
        modeController: mode,
        catalogRepository: environment.catalogRepository,
        callingContext: RecipeBookCallingContext.planner,
        allowedTargets: mode.craftableNames,
        initialSearch: name,
      );
      addTearDown(book.dispose);
      await tester.pumpWidget(
        _host(
          RecipeBookModal(
            controller: book,
            onClose: () {},
            onActivated: (_) {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      final card = find.byKey(RecipeBookKeys.card(name));
      final tooltip = find.descendant(
        of: card,
        matching: find.byWidgetPredicate(
          (widget) => widget is Tooltip && widget.richMessage != null,
        ),
      );
      tester.state<TooltipState>(tooltip).ensureTooltipVisible();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 180));

      for (final variant in const <(String, int)>[
        ('classic-1x', 1),
        ('classic-10x', 10),
        ('concentrated-1x', 1),
        ('concentrated-10x', 10),
      ]) {
        expect(
          find.byKey(
            RecipeBookKeys.itemInfoFormula(name, variant.$1, variant.$2),
          ),
          findsOneWidget,
        );
      }
      expect(find.text('Classic · 1× batch'), findsOneWidget);
      expect(find.text('Classic · 10× batch'), findsOneWidget);
      expect(find.text('Concentrated · 1× batch'), findsOneWidget);
      expect(find.text('Concentrated · 10× batch'), findsOneWidget);

      final firstMaterial = find.byKey(
        RecipeBookKeys.itemInfoMaterial(
          name,
          'classic-1x',
          'Clear Liquid Reagent',
        ),
      );
      final secondMaterial = find.byKey(
        RecipeBookKeys.itemInfoMaterial(name, 'classic-1x', 'Sunflower'),
      );
      expect(firstMaterial, findsOneWidget);
      expect(secondMaterial, findsOneWidget);
      expect(
        tester.getTopLeft(secondMaterial).dy,
        greaterThan(tester.getBottomLeft(firstMaterial).dy),
      );
      expect(find.bySemanticsLabel('2 Clear Liquid Reagent'), findsOneWidget);
      semantics.dispose();
    },
  );

  testWidgets(
    'click pins item info without activating its card and every dismissal works',
    (tester) async {
      await _setSize(tester, const Size(1200, 752));
      final environment = buildRecipeBookTestEnvironment();
      final mode = environment.application.modes[CraftMode.alchemy]!;
      const name = 'Clear Liquid Reagent';
      final book = RecipeBookController(
        modeController: mode,
        catalogRepository: environment.catalogRepository,
        callingContext: RecipeBookCallingContext.planner,
        allowedTargets: mode.craftableNames,
      );
      addTearDown(book.dispose);
      addTearDown(environment.dispose);
      var closeCount = 0;
      final activations = <RecipeBookActivation>[];
      await tester.pumpWidget(
        _host(
          RecipeBookModal(
            controller: book,
            onClose: () => closeCount += 1,
            onActivated: activations.add,
          ),
        ),
      );
      await tester.pumpAndSettle();

      final anchor = find.byKey(
        RecipeBookKeys.itemInfoAnchor(name, 'card:$name'),
      );
      final pinned = find.byKey(
        RecipeBookKeys.pinnedItemInfo(name, 'card:$name'),
      );
      final close = find.byKey(
        RecipeBookKeys.closePinnedItemInfo(name, 'card:$name'),
      );
      expect(anchor, findsOneWidget);

      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      addTearDown(mouse.removePointer);
      await mouse.addPointer(location: tester.getCenter(anchor));
      await mouse.down(tester.getCenter(anchor));
      await mouse.up();
      await tester.pump();
      expect(pinned, findsOneWidget);
      expect(close, findsOneWidget);
      expect(activations, isEmpty);
      expect(find.byKey(RecipeBookKeys.modal), findsOneWidget);

      await mouse.moveTo(const Offset(24, 24));
      await tester.pump(const Duration(seconds: 1));
      expect(pinned, findsOneWidget, reason: 'moving away must not unpin it');

      await tester.tap(close);
      await tester.pump();
      expect(pinned, findsNothing);

      await tester.tap(anchor);
      await tester.pump();
      expect(pinned, findsOneWidget);
      await tester.tapAt(const Offset(24, 24));
      await tester.pump();
      expect(pinned, findsNothing);
      expect(closeCount, 0);
      expect(activations, isEmpty);

      await tester.tap(anchor);
      await tester.pump();
      expect(pinned, findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(pinned, findsNothing);
      expect(find.byKey(RecipeBookKeys.modal), findsOneWidget);
      expect(closeCount, 0);
    },
  );

  testWidgets('duplicate-name item icons keep independent pinned anchors', (
    tester,
  ) async {
    await _setSize(tester, const Size(900, 520));
    final environment = buildRecipeBookTestEnvironment(showDeleteTools: true);
    final mode = environment.application.modes[CraftMode.alchemy]!;
    final book = RecipeBookController(
      modeController: mode,
      catalogRepository: environment.catalogRepository,
      callingContext: RecipeBookCallingContext.planner,
      allowedTargets: mode.craftableNames,
    );
    addTearDown(book.dispose);
    addTearDown(environment.dispose);
    const name = 'Harmony Draught - Human';

    await tester.pumpWidget(
      _host(
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: <Widget>[
            RecipeBookItemIcon(
              controller: book,
              name: name,
              size: 44,
              anchorId: 'duplicate:first',
            ),
            RecipeBookItemIcon(
              controller: book,
              name: name,
              size: 44,
              anchorId: 'duplicate:second',
            ),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();

    final firstAnchor = find.byKey(
      RecipeBookKeys.itemInfoAnchor(name, 'duplicate:first'),
    );
    final secondAnchor = find.byKey(
      RecipeBookKeys.itemInfoAnchor(name, 'duplicate:second'),
    );
    final firstPanel = find.byKey(
      RecipeBookKeys.pinnedItemInfo(name, 'duplicate:first'),
    );
    final secondPanel = find.byKey(
      RecipeBookKeys.pinnedItemInfo(name, 'duplicate:second'),
    );
    expect(firstAnchor, findsOneWidget);
    expect(secondAnchor, findsOneWidget);

    await tester.tap(firstAnchor);
    await tester.pump();
    expect(firstPanel, findsOneWidget);
    expect(secondPanel, findsNothing);
    await tester.tap(
      find.byKey(RecipeBookKeys.closePinnedItemInfo(name, 'duplicate:first')),
    );
    await tester.pump();

    await tester.tap(secondAnchor);
    await tester.pump();
    expect(firstPanel, findsNothing);
    expect(secondPanel, findsOneWidget);
  });

  testWidgets('long pinned info stays viewport-safe and remains scrollable', (
    tester,
  ) async {
    await _setSize(tester, const Size(800, 420));
    final environment = buildRecipeBookTestEnvironment(showDeleteTools: true);
    final mode = environment.application.modes[CraftMode.alchemy]!;
    final book = RecipeBookController(
      modeController: mode,
      catalogRepository: environment.catalogRepository,
      callingContext: RecipeBookCallingContext.planner,
      allowedTargets: mode.craftableNames,
    );
    addTearDown(book.dispose);
    addTearDown(environment.dispose);
    const name = 'Harmony Draught - Human';
    const anchorId = 'long-pinned-test';

    await tester.pumpWidget(
      _host(
        Center(
          child: RecipeBookItemIcon(
            controller: book,
            name: name,
            size: 44,
            anchorId: anchorId,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(RecipeBookKeys.itemInfoAnchor(name, anchorId)));
    await tester.pump();

    final panel = find.byKey(RecipeBookKeys.pinnedItemInfo(name, anchorId));
    expect(panel, findsOneWidget);
    final panelRect = tester.getRect(panel);
    expect(panelRect.left, greaterThanOrEqualTo(12));
    expect(panelRect.top, greaterThanOrEqualTo(12));
    expect(panelRect.right, lessThanOrEqualTo(788));
    expect(panelRect.bottom, lessThanOrEqualTo(408));

    final scrollable = find.descendant(
      of: panel,
      matching: find.byType(Scrollable),
    );
    expect(scrollable, findsOneWidget);
    expect(
      find.descendant(of: panel, matching: find.byType(Scrollbar)),
      findsNothing,
    );
    expect(
      find.descendant(of: panel, matching: find.byType(RawScrollbar)),
      findsNothing,
    );
    final position = tester.state<ScrollableState>(scrollable).position;
    expect(position.maxScrollExtent, greaterThan(0));
    final before = position.pixels;
    await tester.sendEventToBinding(
      PointerScrollEvent(
        viewId: tester.view.viewId,
        kind: PointerDeviceKind.mouse,
        position: panelRect.center,
        scrollDelta: const Offset(0, 160),
      ),
    );
    await tester.pumpAndSettle();
    expect(position.pixels, greaterThan(before));
    expect(panel, findsOneWidget);
  });

  testWidgets('NPC purchase locations render as separate readable rows', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await _setSize(tester, const Size(1200, 752));
    final environment = buildRecipeBookTestEnvironment(
      activeMode: CraftMode.processing,
      includeNpcPurchaseFixture: true,
    );
    final mode = environment.application.modes[CraftMode.processing]!;
    final book = RecipeBookController(
      modeController: mode,
      catalogRepository: environment.catalogRepository,
      callingContext: RecipeBookCallingContext.planner,
      allowedTargets: mode.craftableNames,
    );
    addTearDown(book.dispose);
    addTearDown(environment.dispose);
    const name = 'Mystical Parchment';
    const anchorId = 'npc-purchase-layout-test';

    await tester.pumpWidget(
      _host(
        Center(
          child: RecipeBookItemIcon(
            controller: book,
            name: name,
            size: 44,
            anchorId: anchorId,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(RecipeBookKeys.itemInfoAnchor(name, anchorId)));
    await tester.pump();

    final panel = find.byKey(RecipeBookKeys.pinnedItemInfo(name, anchorId));
    expect(panel, findsOneWidget);
    const rows = <String>[
      'Purchase from:',
      'Sealus',
      'Lebyos',
      'Lylina',
      'Verosi',
      'Vatputa',
      'Talishia',
      'Siemo',
      'Kesharu',
      'Vatu',
    ];
    var previousTop = -1.0;
    for (final row in rows) {
      final text = find.descendant(of: panel, matching: find.text(row));
      expect(text, findsOneWidget, reason: row);
      final top = tester.getTopLeft(text).dy;
      expect(top, greaterThan(previousTop), reason: row);
      previousTop = top;
    }
    expect(find.bySemanticsLabel(rows.join(', ')), findsOneWidget);
    expect(find.bySemanticsLabel('\u2022'), findsNothing);
    semantics.dispose();
  });

  testWidgets(
    'Edania references browse without target controls and inferred output is labeled',
    (tester) async {
      await _setSize(tester, const Size(1200, 752));
      final environment = buildRecipeBookTestEnvironment(
        activeMode: CraftMode.processing,
        includeEdaniaReferenceFixture: true,
      );
      final mode = environment.application.modes[CraftMode.processing]!;
      final book = RecipeBookController(
        modeController: mode,
        catalogRepository: environment.catalogRepository,
        callingContext: RecipeBookCallingContext.planner,
        allowedTargets: mode.craftableNames,
      );
      addTearDown(book.dispose);
      addTearDown(environment.dispose);
      final activations = <RecipeBookActivation>[];
      const reference = 'Dawnbound Ekleta Necklace';
      book.setSearch(reference);

      await tester.pumpWidget(
        _host(
          RecipeBookModal(
            controller: book,
            onClose: () {},
            onActivated: activations.add,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(RecipeBookKeys.card(reference)), findsOneWidget);
      expect(find.byKey(RecipeBookKeys.r11Target(reference)), findsNothing);
      expect(find.byKey(RecipeBookKeys.r12Favorite(reference)), findsNothing);
      expect(find.text('Reference'), findsOneWidget);

      await tester.tap(find.byKey(RecipeBookKeys.card(reference)));
      await tester.pump();
      expect(activations, isEmpty);
      expect(mode.state.value.target, 'Black Stone Batch 01');

      await tester.tap(find.byKey(RecipeBookKeys.r13Details(reference)));
      await tester.pumpAndSettle();
      expect(find.byKey(RecipeBookKeys.previewPanel), findsOneWidget);
      expect(
        find.byKey(RecipeBookKeys.r11Target('$reference:preview')),
        findsNothing,
      );
      expect(find.text('Ekleta Necklace'), findsOneWidget);
      expect(find.text('Cup of Destined Dawn'), findsOneWidget);

      book.closePreview();
      book.setSearch('Polished Marble');
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(RecipeBookKeys.r13Details('Polished Marble')),
      );
      await tester.pumpAndSettle();
      expect(find.text('Estimated output 1–4'), findsOneWidget);

      book.closePreview();
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(
          RecipeBookKeys.itemInfoAnchor(
            'Polished Marble',
            'card:Polished Marble',
          ),
        ),
      );
      await tester.pump();
      expect(find.text('Estimated output ×1–4'), findsOneWidget);
    },
  );

  testWidgets('long effect hover stays in the viewport and wheel-scrolls', (
    tester,
  ) async {
    await _setSize(tester, const Size(800, 420));
    final environment = buildRecipeBookTestEnvironment(showDeleteTools: true);
    final mode = environment.application.modes[CraftMode.alchemy]!;
    final book = RecipeBookController(
      modeController: mode,
      catalogRepository: environment.catalogRepository,
      callingContext: RecipeBookCallingContext.planner,
      allowedTargets: mode.craftableNames,
    );
    addTearDown(book.dispose);
    addTearDown(environment.dispose);
    const name = 'Harmony Draught - Human';

    await tester.pumpWidget(
      _host(
        Center(
          child: RecipeBookItemIcon(
            controller: book,
            name: name,
            size: 44,
            anchorId: 'long-effect-test',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final tooltip = find.byWidgetPredicate(
      (widget) => widget is Tooltip && widget.richMessage != null,
    );
    expect(tooltip, findsOneWidget);
    tester.state<TooltipState>(tooltip).ensureTooltipVisible();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 180));

    final panel = find.byKey(RecipeBookKeys.itemInfo(name));
    expect(panel, findsOneWidget);
    final panelRect = tester.getRect(panel);
    expect(panelRect.top, greaterThanOrEqualTo(0));
    expect(panelRect.bottom, lessThanOrEqualTo(420));
    expect(panelRect.height, lessThanOrEqualTo(356.01));

    final scrollView = find.descendant(
      of: panel,
      matching: find.byType(SingleChildScrollView),
    );
    expect(scrollView, findsOneWidget);
    expect(
      find.descendant(of: panel, matching: find.byType(Scrollbar)),
      findsNothing,
    );
    expect(
      find.descendant(of: panel, matching: find.byType(RawScrollbar)),
      findsNothing,
    );
    final scrollable = find.descendant(
      of: scrollView,
      matching: find.byType(Scrollable),
    );
    final position = tester.state<ScrollableState>(scrollable).position;
    expect(position.maxScrollExtent, greaterThan(0));

    final before = position.pixels;
    await tester.sendEventToBinding(
      PointerScrollEvent(
        viewId: tester.view.viewId,
        kind: PointerDeviceKind.mouse,
        position: tester.getCenter(panel),
        scrollDelta: const Offset(0, 160),
      ),
    );
    await tester.pumpAndSettle();
    expect(position.pixels, greaterThan(before));
    expect(panel, findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('curated buff recipes show actual effect item info', (
    tester,
  ) async {
    await _setSize(tester, const Size(1500, 940));
    final environment = buildRecipeBookTestEnvironment(showDeleteTools: true);
    final mode = environment.application.modes[CraftMode.alchemy]!;
    const name = 'Adaptation Draught';
    mode.updateState(
      (state) => state.copyWith(
        recipeEdits: <String, RecipeState?>{
          ...state.recipeEdits,
          name: RecipeState(
            type: 'simple_alchemy',
            baseOutput: 1,
            group: 'Draughts',
            method: 'Simple Alchemy',
            ingredients: <IngredientState>[
              IngredientState(
                name: 'Elixir of Life',
                quantity: 1,
                options: const <String>[],
                substituteGroup: null,
                substituteRatios: const <String, double>{},
              ),
            ],
            marketId: null,
            sourceNote: null,
            vendor: null,
            location: null,
            npcPrice: 0,
            qualityBase: null,
            qualityGrade: null,
            outputMinimum: null,
            outputMaximum: null,
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
      initialSearch: 'Adaptation',
    );
    await tester.pumpWidget(
      _host(
        RecipeBookModal(controller: book, onClose: () {}, onActivated: (_) {}),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(RecipeBookKeys.card(name)), findsOneWidget);
    expect(_richInfoTooltips(tester), hasLength(1));
    final info = book.itemInfoFor(name);
    expect(info?.effects, contains('All Damage Reduction +13'));
    expect(info?.notes, contains('Duration: 15 min.'));

    await tester.pumpWidget(const SizedBox.shrink());
    book.dispose();
    await environment.dispose();
  });

  testWidgets('material item hover renders How to Obtain guidance', (
    tester,
  ) async {
    await _setSize(tester, const Size(1500, 940));
    final environment = buildRecipeBookTestEnvironment(
      activeMode: CraftMode.processing,
      showDeleteTools: true,
    );
    final mode = environment.application.modes[CraftMode.processing]!;
    const name = 'Essence of Dawn';
    mode.updateState(
      (state) => state.copyWith(
        recipeEdits: <String, RecipeState?>{
          ...state.recipeEdits,
          name: RecipeState(
            type: 'processing',
            baseOutput: 12,
            group: 'Processing - Heating',
            method: 'Heating',
            ingredients: <IngredientState>[
              IngredientState(
                name: "Dawn's Aura",
                quantity: 1,
                options: const <String>[],
                substituteGroup: null,
                substituteRatios: const <String, double>{},
              ),
            ],
            marketId: '820979',
            sourceNote: null,
            vendor: null,
            location: null,
            npcPrice: 0,
            qualityBase: null,
            qualityGrade: null,
            outputMinimum: 30,
            outputMaximum: 30,
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
      initialSearch: name,
    );
    await tester.pumpWidget(
      _host(
        RecipeBookModal(controller: book, onClose: () {}, onActivated: (_) {}),
      ),
    );
    await tester.pumpAndSettle();

    final card = find.byKey(RecipeBookKeys.card(name));
    expect(card, findsOneWidget);
    expect(book.itemInfoFor(name)?.howToObtain, isNotEmpty);
    final tooltip = find.descendant(
      of: card,
      matching: find.byWidgetPredicate(
        (widget) => widget is Tooltip && widget.richMessage != null,
      ),
    );
    expect(tooltip, findsOneWidget);
    tester.state<TooltipState>(tooltip).ensureTooltipVisible();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 180));

    expect(find.byKey(RecipeBookKeys.itemInfo(name)), findsOneWidget);
    expect(find.text('How to Obtain'), findsOneWidget);
    expect(find.textContaining('Black Shrine'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    book.dispose();
    await environment.dispose();
  });

  testWidgets('recipe-style use renders output before ingredient recipe', (
    tester,
  ) async {
    await _setSize(tester, const Size(1500, 940));
    final environment = buildRecipeBookTestEnvironment(
      activeMode: CraftMode.processing,
      showDeleteTools: true,
    );
    final mode = environment.application.modes[CraftMode.processing]!;
    const name = 'Ancient Spirit Dust';
    mode.updateState(
      (state) => state.copyWith(
        recipeEdits: <String, RecipeState?>{
          ...state.recipeEdits,
          name: RecipeState(
            type: 'processing',
            baseOutput: 1,
            group: 'Processing',
            method: 'Processing',
            ingredients: <IngredientState>[
              IngredientState(
                name: 'Raw Material 01',
                quantity: 1,
                options: const <String>[],
                substituteGroup: null,
                substituteRatios: const <String, double>{},
              ),
            ],
            marketId: null,
            sourceNote: null,
            vendor: null,
            location: null,
            npcPrice: 0,
            qualityBase: null,
            qualityGrade: null,
            outputMinimum: null,
            outputMaximum: null,
          ),
          'Caphras Stone': RecipeState(
            type: 'simple_alchemy',
            baseOutput: 1,
            group: 'Simple Alchemy',
            method: 'Simple Alchemy',
            ingredients: <IngredientState>[
              IngredientState(
                name: 'Ancient Spirit Dust',
                quantity: 5,
                options: <String>[],
                substituteGroup: null,
                substituteRatios: <String, double>{},
              ),
              IngredientState(
                name: 'Black Stone',
                quantity: 1,
                options: <String>[],
                substituteGroup: null,
                substituteRatios: <String, double>{},
              ),
            ],
            marketId: null,
            sourceNote: null,
            vendor: null,
            location: null,
            npcPrice: 0,
            qualityBase: null,
            qualityGrade: null,
            outputMinimum: 1,
            outputMaximum: 1,
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
      initialSearch: name,
    );
    await tester.pumpWidget(
      _host(
        RecipeBookModal(controller: book, onClose: () {}, onActivated: (_) {}),
      ),
    );
    await tester.pumpAndSettle();

    final card = find.byKey(RecipeBookKeys.card(name));
    expect(card, findsOneWidget);
    final tooltip = find.descendant(
      of: card,
      matching: find.byWidgetPredicate(
        (widget) => widget is Tooltip && widget.richMessage != null,
      ),
    );
    expect(tooltip, findsOneWidget);
    tester.state<TooltipState>(tooltip).ensureTooltipVisible();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 180));

    final recipeSection = find.text('Recipe & materials');
    final acquisition = find.byKey(
      RecipeBookKeys.itemInfoFormula(name, null, 1),
    );
    final acquisitionMaterial = find.byKey(
      RecipeBookKeys.itemInfoMaterial(name, null, 'Raw Material 01'),
    );
    final usedFor = find.text('Used For');
    final output = find.text('Caphras Stone');
    final outputDescription = find.text(
      'Enhancement material used in several late-game recipes.',
    );
    final recipe = find.byKey(
      RecipeBookKeys.itemInfoFormula('Caphras Stone', null, 1),
    );
    final dustMaterial = find.byKey(
      RecipeBookKeys.itemInfoMaterial(
        'Caphras Stone',
        null,
        'Ancient Spirit Dust',
      ),
    );
    expect(recipeSection, findsOneWidget);
    expect(acquisition, findsOneWidget);
    expect(acquisitionMaterial, findsOneWidget);
    expect(usedFor, findsOneWidget);
    expect(output, findsOneWidget);
    expect(outputDescription, findsOneWidget);
    expect(recipe, findsOneWidget);
    expect(dustMaterial, findsOneWidget);
    expect(
      tester.getTopLeft(recipeSection).dy,
      lessThan(tester.getTopLeft(usedFor).dy),
    );
    expect(
      tester.getTopLeft(usedFor).dy - tester.getBottomLeft(acquisition).dy,
      greaterThanOrEqualTo(10),
    );
    expect(
      tester.getTopLeft(usedFor).dy,
      lessThan(tester.getTopLeft(output).dy),
    );
    expect(
      tester.getTopLeft(output).dy,
      lessThan(tester.getTopLeft(outputDescription).dy),
    );
    expect(
      tester.getTopLeft(outputDescription).dy,
      lessThan(tester.getTopLeft(recipe).dy),
    );
    expect(find.textContaining('->'), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    book.dispose();
    await environment.dispose();
  });

  testWidgets('opaque crafted outputs include a concrete example', (
    tester,
  ) async {
    await _setSize(tester, const Size(1200, 752));
    final environment = buildRecipeBookTestEnvironment(
      activeMode: CraftMode.processing,
      showDeleteTools: true,
    );
    final mode = environment.application.modes[CraftMode.processing]!;
    mode.updateState(
      (state) => state.copyWith(
        recipeEdits: <String, RecipeState?>{
          ...state.recipeEdits,
          'Exalted Soul Fragment': RecipeState(
            type: 'processing',
            baseOutput: 1,
            group: 'Processing - Heating',
            method: 'Heating',
            ingredients: <IngredientState>[
              IngredientState(
                name: 'Alchemy Stone Shard',
                quantity: 50,
                options: const <String>[],
                substituteGroup: null,
                substituteRatios: const <String, double>{},
              ),
            ],
            marketId: '8432',
            sourceNote: null,
            vendor: null,
            location: null,
            npcPrice: 0,
            qualityBase: null,
            qualityGrade: null,
            outputMinimum: 1,
            outputMaximum: 1,
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
    );
    await tester.pumpWidget(
      _host(
        Center(
          child: RecipeBookItemIcon(
            controller: book,
            name: 'Alchemy Stone Shard',
            size: 44,
            anchorId: 'craft-use-test',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final tooltip = find.byWidgetPredicate(
      (widget) => widget is Tooltip && widget.richMessage != null,
    );
    tester.state<TooltipState>(tooltip).ensureTooltipVisible();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 180));

    final output = find.text('Exalted Soul Fragment');
    final description = find.text(
      'Upgrades a Blessed alchemy stone to Exalted and adds All Damage Reduction +2.',
    );
    final example = find.text(
      "Example: Blessed Vell's Heart.",
      findRichText: true,
    );
    final recipe = find.byKey(
      RecipeBookKeys.itemInfoFormula('Exalted Soul Fragment', null, 1),
    );
    final material = find.byKey(
      RecipeBookKeys.itemInfoMaterial(
        'Exalted Soul Fragment',
        null,
        'Alchemy Stone Shard',
      ),
    );
    expect(output, findsOneWidget);
    expect(description, findsOneWidget);
    expect(example, findsOneWidget);
    expect(recipe, findsOneWidget);
    expect(material, findsOneWidget);
    expect(
      tester.getTopLeft(output).dy,
      lessThan(tester.getTopLeft(description).dy),
    );
    expect(
      tester.getTopLeft(description).dy,
      lessThan(tester.getTopLeft(example).dy),
    );
    expect(
      tester.getTopLeft(example).dy,
      lessThan(tester.getTopLeft(recipe).dy),
    );

    await tester.pumpWidget(const SizedBox.shrink());
    book.dispose();
    await environment.dispose();
  });

  testWidgets('buff item info includes blessings, perfumes, and elixirs', (
    tester,
  ) async {
    await _setSize(tester, const Size(1500, 940));

    final processingEnvironment = buildRecipeBookTestEnvironment(
      activeMode: CraftMode.processing,
      showDeleteTools: true,
    );
    final processingMode =
        processingEnvironment.application.modes[CraftMode.processing]!;
    const blessingName = 'Blessing of Mystic Beasts - All AP';
    processingMode.updateState(
      (state) => state.copyWith(
        recipeEdits: <String, RecipeState?>{
          ...state.recipeEdits,
          blessingName: RecipeState(
            type: 'simple_alchemy',
            baseOutput: 10,
            group: 'Processing - Simple Alchemy',
            method: 'Simple Alchemy',
            ingredients: <IngredientState>[
              IngredientState(
                name: 'Remnants of Mystic Beasts',
                quantity: 10,
                options: const <String>[],
                substituteGroup: null,
                substituteRatios: const <String, double>{},
              ),
            ],
            marketId: null,
            sourceNote: null,
            vendor: null,
            location: null,
            npcPrice: 0,
            qualityBase: null,
            qualityGrade: null,
            outputMinimum: null,
            outputMaximum: null,
          ),
        },
      ),
      immediate: true,
    );
    final blessingBook = RecipeBookController(
      modeController: processingMode,
      catalogRepository: processingEnvironment.catalogRepository,
      callingContext: RecipeBookCallingContext.planner,
      allowedTargets: processingMode.craftableNames,
      initialSearch: 'Blessing',
    );
    await tester.pumpWidget(
      _host(
        RecipeBookModal(
          controller: blessingBook,
          onClose: () {},
          onActivated: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(RecipeBookKeys.card(blessingName)), findsOneWidget);
    expect(_richInfoTooltips(tester), hasLength(1));
    expect(
      blessingBook.itemInfoFor(blessingName)?.effects,
      contains('All AP +15'),
    );
    await tester.pumpWidget(const SizedBox.shrink());
    blessingBook.dispose();
    await processingEnvironment.dispose();

    final alchemyEnvironment = buildRecipeBookTestEnvironment(
      showDeleteTools: true,
    );
    final alchemyMode =
        alchemyEnvironment.application.modes[CraftMode.alchemy]!;
    alchemyMode.updateState(
      (state) => state.copyWith(
        recipeEdits: <String, RecipeState?>{
          ...state.recipeEdits,
          'Perfume of Courage': RecipeState(
            type: 'alchemy',
            baseOutput: 1,
            group: 'Perfumes',
            method: 'Residence Alchemy',
            ingredients: <IngredientState>[
              IngredientState(
                name: 'Oil of Corruption',
                quantity: 1,
                options: const <String>[],
                substituteGroup: null,
                substituteRatios: const <String, double>{},
              ),
            ],
            marketId: null,
            sourceNote: null,
            vendor: null,
            location: null,
            npcPrice: 0,
            qualityBase: null,
            qualityGrade: null,
            outputMinimum: null,
            outputMaximum: null,
          ),
        },
      ),
      immediate: true,
    );
    final perfumeBook = RecipeBookController(
      modeController: alchemyMode,
      catalogRepository: alchemyEnvironment.catalogRepository,
      callingContext: RecipeBookCallingContext.planner,
      allowedTargets: alchemyMode.craftableNames,
      initialSearch: 'Perfume of Courage',
    );
    await tester.pumpWidget(
      _host(
        RecipeBookModal(
          controller: perfumeBook,
          onClose: () {},
          onActivated: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(RecipeBookKeys.card('Perfume of Courage')),
      findsOneWidget,
    );
    expect(_richInfoTooltips(tester), hasLength(1));
    expect(
      perfumeBook.itemInfoFor('Perfume of Courage')?.effects,
      contains('All AP +20'),
    );
    await tester.pumpWidget(const SizedBox.shrink());
    perfumeBook.dispose();
    await alchemyEnvironment.dispose();

    final elixirEnvironment = buildRecipeBookTestEnvironment(
      showDeleteTools: true,
    );
    final elixirMode = elixirEnvironment.application.modes[CraftMode.alchemy]!;
    elixirMode.updateState(
      (state) => state.copyWith(
        recipeEdits: <String, RecipeState?>{
          ...state.recipeEdits,
          'Elixir of Fury': RecipeState(
            type: 'alchemy',
            baseOutput: 1,
            group: 'Elixirs',
            method: 'Residence Alchemy',
            ingredients: <IngredientState>[
              IngredientState(
                name: 'Ash Sap',
                quantity: 1,
                options: const <String>[],
                substituteGroup: null,
                substituteRatios: const <String, double>{},
              ),
            ],
            marketId: null,
            sourceNote: null,
            vendor: null,
            location: null,
            npcPrice: 0,
            qualityBase: null,
            qualityGrade: null,
            outputMinimum: null,
            outputMaximum: null,
          ),
        },
      ),
      immediate: true,
    );
    final elixirBook = RecipeBookController(
      modeController: elixirMode,
      catalogRepository: elixirEnvironment.catalogRepository,
      callingContext: RecipeBookCallingContext.planner,
      allowedTargets: elixirMode.craftableNames,
      initialSearch: 'Elixir of Fury',
    );
    await tester.pumpWidget(
      _host(
        RecipeBookModal(
          controller: elixirBook,
          onClose: () {},
          onActivated: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(RecipeBookKeys.card('Elixir of Fury')), findsOneWidget);
    expect(_richInfoTooltips(tester), hasLength(1));
    expect(
      elixirBook.itemInfoFor('Elixir of Fury')?.effects,
      contains('All AP +5'),
    );

    await tester.pumpWidget(const SizedBox.shrink());
    elixirBook.dispose();
    await elixirEnvironment.dispose();
  });

  testWidgets('unverified buff recipes get compact info without fake effects', (
    tester,
  ) async {
    await _setSize(tester, const Size(1500, 940));
    final environment = buildRecipeBookTestEnvironment(showDeleteTools: true);
    final mode = environment.application.modes[CraftMode.alchemy]!;
    const name = 'Unwritten Draught';
    mode.updateState(
      (state) => state.copyWith(
        recipeEdits: <String, RecipeState?>{
          ...state.recipeEdits,
          name: RecipeState(
            type: 'simple_alchemy',
            baseOutput: 1,
            group: 'Draughts',
            method: 'Simple Alchemy',
            ingredients: <IngredientState>[
              IngredientState(
                name: 'Elixir of Life',
                quantity: 1,
                options: const <String>[],
                substituteGroup: null,
                substituteRatios: const <String, double>{},
              ),
            ],
            marketId: null,
            sourceNote: null,
            vendor: null,
            location: null,
            npcPrice: 0,
            qualityBase: null,
            qualityGrade: null,
            outputMinimum: null,
            outputMaximum: null,
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
      initialSearch: 'Unwritten',
    );
    await tester.pumpWidget(
      _host(
        RecipeBookModal(controller: book, onClose: () {}, onActivated: (_) {}),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(RecipeBookKeys.card(name)), findsOneWidget);
    expect(_richInfoTooltips(tester), hasLength(1));
    final info = book.itemInfoFor(name);
    expect(info, isNotNull);
    expect(info?.effects, isEmpty);
    expect(info?.howToObtain, const <String>[
      'Simple Alchemy: 1 Elixir of Life.',
    ]);

    await tester.pumpWidget(const SizedBox.shrink());
    book.dispose();
    await environment.dispose();
  });
}

Widget _host(
  Widget child, {
  CustomIconStore? iconStore,
  ThemeSpec spec = StandardSpec.theme,
  TextScaler textScaler = TextScaler.noScaling,
}) {
  final content = iconStore == null
      ? child
      : CustomIconStoreScope(store: iconStore, child: child);
  return MaterialApp(
    theme: spec.materialTheme(),
    builder: (context, appChild) => MediaQuery(
      data: MediaQuery.of(context).copyWith(textScaler: textScaler),
      child: appChild!,
    ),
    home: ThemeSpecScope(
      spec: spec,
      child: Scaffold(body: AppOverlayCoordinatorHost(child: content)),
    ),
  );
}

Future<void> _setSize(WidgetTester tester, Size size) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
}

List<Tooltip> _richInfoTooltips(WidgetTester tester) => tester
    .widgetList<Tooltip>(find.byType(Tooltip))
    .where((tooltip) => tooltip.richMessage != null)
    .toList(growable: false);

Finder _checkGlyphsWithin(Finder ancestor) => find.descendant(
  of: ancestor,
  matching: find.byWidgetPredicate(
    (widget) => widget is AppVectorGlyph && widget.name == 'check',
  ),
);
