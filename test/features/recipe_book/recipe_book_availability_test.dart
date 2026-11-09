import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:bdo_craft_planner_flutter/app/state/planner_application_controller.dart';
import 'package:bdo_craft_planner_flutter/data/catalog/bundled_catalog_parser.dart';
import 'package:bdo_craft_planner_flutter/data/catalog/catalog_repository.dart';
import 'package:bdo_craft_planner_flutter/data/market/shared_market_repository.dart';
import 'package:bdo_craft_planner_flutter/domain/models/craft_mode.dart';
import 'package:bdo_craft_planner_flutter/domain/state/planner_state.dart';
import 'package:bdo_craft_planner_flutter/domain/state/state_copy.dart';
import 'package:bdo_craft_planner_flutter/features/planner/planner_choice_market.dart';
import 'package:bdo_craft_planner_flutter/features/planner/planner_contracts.dart';
import 'package:bdo_craft_planner_flutter/features/recipe_book/recipe_book.dart';
import 'package:bdo_craft_planner_flutter/features/shared/inventory_count_badge.dart';
import 'package:bdo_craft_planner_flutter/features/shared/market_count_badges.dart';
import 'package:bdo_craft_planner_flutter/features/shared/npc_source_marker.dart';
import 'package:bdo_craft_planner_flutter/shared/overlays/anchored_popover.dart';
import 'package:bdo_craft_planner_flutter/visual/visual.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/availability_badge_finders.dart';
import '../../support/choice_market_transport.dart';
import '../planner/planner_choice_market_test.dart' show settle;
import '../planner/planner_review_projection_test.dart' as fixture;

void main() {
  final catalog = const BundledCatalogParser().parse(
    File('assets/data/app-data.json').readAsStringSync(),
  );
  final repository = CatalogRepository.cached(catalog);
  RecipeBookController bookFor(PlannerApplicationController app) =>
      RecipeBookController(
        modeController: app.active,
        catalogRepository: repository,
        callingContext: RecipeBookCallingContext.planner,
        allowedTargets: app.active.craftableNames,
      );

  test(
    'inventory capacity uses real quantities, not the Planner ignore switch',
    () async {
      final app = fixture.controller(catalog, CraftMode.cooking, 'Beer', 1);
      final book = bookFor(app);
      addTearDown(book.dispose);
      addTearDown(app.dispose);
      final initial = book.availabilityFor('Beer');
      expect(initial.canCraft, 0);
      final inputs = initial.ingredients;
      for (final row in inputs) {
        book.selectIngredientChoice('Beer', row);
      }
      app.active.updateState(
        (state) => state.copyWith(
          ignoreIngredientInventory: true,
          inventory: {for (final row in inputs) row.name: row.quantity * 7},
        ),
        immediate: true,
      );
      final before = jsonEncode(app.documentSnapshot.toJson());
      final owned = book.availabilityFor('Beer');
      expect(owned.canCraft, 7);
      expect(owned.ownedTypes, owned.totalTypes);
      expect(owned.missing, isEmpty);
      expect(jsonEncode(app.documentSnapshot.toJson()), before);
      app.active.commitInventory(
        inputs.first.name,
        '${inputs.first.quantity - 1}',
      );
      final partial = book.availabilityFor('Beer');
      expect(partial.canCraft, 0);
      expect(partial.missing[inputs.first.name], 1);
      expect(partial.ownedTypes, partial.totalTypes - 1);
      expect(owned.compareTo(partial), lessThan(0));
    },
  );

  test(
    'all supported quality choices have inventory and exact availability identities',
    () async {
      final app = fixture.controller(catalog, CraftMode.cooking, 'Beer', 1);
      final book = bookFor(app);
      addTearDown(book.dispose);
      addTearDown(app.dispose);
      final grain = app.active.recipes['Beer']!.ingredients.firstWhere(
        (i) => i.options.contains('Wheat'),
      );
      final choices = book.ingredientChoices('Beer', grain);
      final hq = choices.firstWhere(
        (row) => row.name.toLowerCase() == 'high-quality wheat',
      );
      final special = choices.firstWhere((row) => row.name == 'Special Wheat');
      expect(hq.marketable, isTrue);
      expect(special.marketable, isTrue);
      expect(hq.stock, isNull);
      expect(special.stock, isNull);
      expect(hq.quantity, 2);
      expect(special.quantity, 1);
      app.active.commitInventory(hq.name, '40');
      book.selectIngredientChoice('Beer', hq);
      final selected = book
          .availabilityFor('Beer')
          .ingredients
          .firstWhere((row) => row.ingredient == grain);
      expect(selected.name, hq.name);
      expect(selected.quantity, 2);
      expect(selected.owned, 40);
      final activation = book.activate('Beer');
      expect(activation, isNotNull);
      final planner = app.active.previewIngredientSelection(
        parentName: 'Beer',
        ingredient: grain,
      );
      expect(planner.name, hq.name);
      expect(planner.need, selected.quantity);
    },
  );

  test(
    'availability sorting is available immediately and never hides recipes',
    () async {
      final app = fixture.controller(catalog, CraftMode.cooking, 'Beer', 1);
      final book = bookFor(app);
      addTearDown(book.dispose);
      addTearDown(app.dispose);
      final inputs = book.availabilityFor('Beer').ingredients;
      for (final row in inputs) {
        book.selectIngredientChoice('Beer', row);
      }
      app.active.updateState(
        (state) => state.copyWith(
          inventory: {for (final row in inputs) row.name: row.quantity * 8},
        ),
        immediate: true,
      );
      final count = book.snapshot.filteredCount;
      expect(book.marketControlsVisible, isFalse);
      book.setMarketSort(RecipeBookMarketSort.availability);
      expect(book.marketSort, RecipeBookMarketSort.availability);
      final sorted = book.snapshot.entries;
      expect(sorted.length, count);
      expect(book.availabilityFor(sorted.first.name).fullyOwned, isTrue);
      for (var i = 1; i < sorted.length; i++) {
        expect(
          book
              .availabilityFor(sorted[i - 1].name)
              .compareTo(book.availabilityFor(sorted[i].name)),
          lessThanOrEqualTo(0),
        );
      }
      book.setMarketSort(RecipeBookMarketSort.availabilityProfit);
      expect(book.snapshot.filteredCount, count);
    },
  );

  test('duplicate inputs share one inventory pool', () async {
    final app = fixture.controller(catalog, CraftMode.cooking, 'Beer', 1);
    app.active.updateState(
      (state) => state.copyWith(
        recipeEdits: {
          ...state.recipeEdits,
          'Duplicate Test': RecipeState(
            type: 'cooking',
            ingredients: [
              IngredientState(name: 'Sugar', quantity: 3),
              IngredientState(name: 'Sugar', quantity: 2),
            ],
          ),
        },
        inventory: {'Sugar': 9},
      ),
      immediate: true,
    );
    final book = bookFor(app);
    addTearDown(book.dispose);
    addTearDown(app.dispose);
    expect(book.availabilityFor('Duplicate Test').canCraft, 1);
    app.active.commitInventory('Sugar', '4');
    final result = book.availabilityFor('Duplicate Test');
    expect(result.canCraft, 0);
    expect(result.ownedTypes, 1);
    expect(result.missing, {'Sugar': 1});
    expect(result.canBuyMissing, isTrue);
  });

  test(
    'profit and activation use the exact inventory-aware automatic choices',
    () async {
      final app = fixture.controller(catalog, CraftMode.cooking, 'Beer', 1);
      app.active.updateState(
        (state) => state.copyWith(
          inventory: {'Special Wheat': 12},
          market: state.market.copyWith(
            prices: {
              'Beer': 10000,
              'Wheat': 1,
              'Special Wheat': 900,
              'High-Quality Wheat': 500,
            },
          ),
        ),
        immediate: true,
      );
      final book = bookFor(app);
      addTearDown(book.dispose);
      addTearDown(app.dispose);
      final availability = book.availabilityFor('Beer');
      expect(availability.ingredients.first.name, 'Special Wheat');
      final quote = book.profitabilityFor('Beer')!;
      expect(quote.isAvailable, isTrue);
      expect(
        quote.ingredientCosts.map((row) => (row.selectedName, row.quantity)),
        availability.ingredients.map((row) => (row.name, row.quantity)),
      );
      expect(
        quote.ingredientCosts.first.total,
        900,
        reason: 'Owned is not free in a direct-buy profit estimate.',
      );
      book.activate('Beer', useDisplayedIngredients: true);
      final grain = app.active.recipes['Beer']!.ingredients.first;
      expect(
        app.active
            .previewIngredientSelection(parentName: 'Beer', ingredient: grain)
            .name,
        'Special Wheat',
      );
    },
  );

  setUpAll(() async {
    for (final entry in {
      'Segoe UI': [
        'C:/Windows/Fonts/segoeui.ttf',
        'C:/Windows/Fonts/seguisb.ttf',
      ],
      'Georgia': [
        'C:/Windows/Fonts/georgia.ttf',
        'C:/Windows/Fonts/georgiab.ttf',
      ],
      'MaterialIcons': [
        'D:/Tools/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
      ],
    }.entries) {
      final loader = FontLoader(entry.key);
      for (final file in entry.value) {
        loader.addFont(File(file).readAsBytes().then(ByteData.sublistView));
      }
      await loader.load();
    }
  });

  for (final spec in RetainedThemeRegistry.themes) {
    for (final layout in [
      (scale: 1.0, width: 1464.0),
      (scale: 1.35, width: 1464.0),
      (scale: 2.0, width: 1464.0),
      (scale: 1.0, width: 1920.0),
    ]) {
      final scale = layout.scale;
      final viewport = Size(layout.width, 900);
      final captureName = '${spec.id}-$scale-${layout.width.toInt()}';
      testWidgets('ingredient cards and picker $captureName', (tester) async {
        tester.view.physicalSize = viewport;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final app = fixture.controller(catalog, CraftMode.cooking, 'Beer', 1);
        final book = RecipeBookController(
          modeController: app.active,
          catalogRepository: repository,
          callingContext: RecipeBookCallingContext.planner,
          allowedTargets: const [
            'Beer',
            'Vinegar',
            'Citron Juice',
            'Grilled Bird Meat',
          ],
        );
        for (final name in [
          'Beer',
          'Vinegar',
          'Citron Juice',
          'Grilled Bird Meat',
        ]) {
          book.toggleFavorite(name);
        }
        book.setFavoritesOnly(true);
        final inputs = book.availabilityFor('Beer').ingredients;
        for (final row in inputs) {
          book.selectIngredientChoice('Beer', row);
        }
        app.active.updateState(
          (state) => state.copyWith(
            market: state.market.copyWith(
              prices: {'Beer': 10000, for (final row in inputs) row.name: 480},
            ),
            inventory: {
              for (final row in inputs) row.name: row.quantity * 12000,
              'High-Quality Wheat': 294600,
              'Special Wheat': 1500000,
            },
          ),
          immediate: true,
        );
        final transport = ChoiceMarketTransport();
        transport.values[repository.bundledMarketId('Beer')!] = (
          price: 10000000,
          stock: 12594,
          preorders: 0,
        );
        transport.values[repository.bundledMarketId('High-Quality Wheat')!] = (
          price: 100,
          stock: 432100,
          preorders: 95500,
        );
        transport.values[repository.bundledMarketId('Wheat')!] = (
          price: 2500000,
          stock: 0,
          preorders: 28800,
        );
        transport.values[repository.bundledMarketId('Citron')!] = (
          price: 100,
          stock: 32200,
          preorders: 95500,
        );
        transport.values[repository.bundledMarketId('Cooking Honey')!] = (
          price: 100,
          stock: 27800,
          preorders: 5000,
        );
        final broker = SharedMarketRepository(
          transport: transport,
          requestSpacing: Duration.zero,
        );
        await tester.pumpWidget(
          RepaintBoundary(
            key: const ValueKey('capture-root'),
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: spec.materialTheme(),
              home: ThemeSpecScope(
                spec: spec,
                child: MediaQuery(
                  data: MediaQueryData(
                    size: viewport,
                    textScaler: TextScaler.linear(scale),
                  ),
                  child: PlannerChoiceMarketScope(
                    repository: broker,
                    child: Scaffold(
                      body: RepaintBoundary(
                        key: const ValueKey('capture'),
                        child: AppOverlayCoordinatorHost(
                          child: RecipeBookModal(
                            controller: book,
                            onClose: () {},
                            onActivated: (_) {},
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await settle(tester, broker);
        await tester.pumpAndSettle();
        expect(find.byKey(RecipeBookKeys.r23MarketSort), findsOneWidget);
        expect(find.byType(InventoryCountBadge), findsNothing);
        expect(find.textContaining('Can craft'), findsNothing);
        expect(transport.requests, isEmpty);
        final card =
            tester
                    .widget<DecoratedBox>(
                      find.byKey(const ValueKey('recipe-soft-card:Beer')),
                    )
                    .decoration
                as BoxDecoration;
        expect(card.border, isNotNull);
        expect(card.boxShadow!.first.blurRadius, greaterThanOrEqualTo(10));
        expect(
          tester
              .getSize(find.byKey(const ValueKey('recipe-card-icon:Beer')))
              .width,
          greaterThanOrEqualTo(60),
        );
        await capture(tester, '$captureName-normal');
        await tester.tap(find.byKey(RecipeBookKeys.r23MarketSort));
        await tester.pumpAndSettle();
        final pendingQuotes = Completer<void>();
        transport.hold = pendingQuotes;
        await tester.tap(find.text('Availability').last);
        await tester.pumpAndSettle();
        await book.checkMarket();
        await tester.pumpAndSettle();
        checkOutputStockAlignment(tester);
        expect(
          find.descendant(
            of: find.byKey(const ValueKey('recipe-output-stock:Beer')),
            matching: stockBadgeText('—'),
          ),
          findsOneWidget,
        );
        checkColumnAlignment(tester);
        checkValueAlignment(tester, 'Beer');
        await capture(tester, '$captureName-unknown');
        transport.hold = null;
        pendingQuotes.complete();
        await settle(tester, broker);
        await tester.pumpAndSettle();
        app.active.updateState(
          (state) => state.copyWith(
            market: state.market.copyWith(stock: {'Beer': 12594, 'Vinegar': 0}),
          ),
          immediate: true,
        );
        await tester.pumpAndSettle();
        checkOutputStockAlignment(tester);
        expect(
          find.descendant(
            of: find.byKey(const ValueKey('recipe-output-stock:Beer')),
            matching: stockBadgeText('12.594'),
          ),
          findsOneWidget,
        );
        expect(find.byType(InventoryCountBadge), findsWidgets);
        expect(find.text('Can craft 12k'), findsWidgets);
        for (final badge in tester.widgetList<InventoryCountBadge>(
          find.byType(InventoryCountBadge),
        )) {
          expect(badge.showLabel, isFalse);
          expect(badge.density, MarketBadgeDensity.comfortable);
        }
        checkBadgeLines(tester);
        checkColumnAlignment(tester);
        checkValueAlignment(tester, 'Beer');
        expect(
          transport.requests.any(
            (request) =>
                request.ids.contains(repository.bundledMarketId('Beer')),
          ),
          isTrue,
          reason:
              'The card must fetch its output price, not only ingredient stock.',
        );
        expect(book.debugCachedItemInfoCount, 0);
        final ingredientIcons = tester
            .widgetList<RecipeBookItemIcon>(find.byType(RecipeBookItemIcon))
            .where((icon) => icon.anchorId.startsWith('availability:'));
        expect(ingredientIcons, isNotEmpty);
        expect(ingredientIcons.every((icon) => icon.size >= 42), isTrue);
        if (layout.width == 1920) {
          final beer = tester.getRect(find.byKey(RecipeBookKeys.card('Beer')));
          final vinegar = tester.getRect(
            find.byKey(RecipeBookKeys.card('Vinegar')),
          );
          expect(beer.top, closeTo(vinegar.top, .1));
          expect(beer.right, lessThan(vinegar.left));
        }
        expect(tester.takeException(), isNull);
        await capture(tester, '$captureName-cards');
        await Scrollable.ensureVisible(
          tester.element(find.text('Sale value').first),
          alignment: 1,
        );
        await tester.pumpAndSettle();
        checkValueAlignment(tester, 'Beer');
        await capture(tester, '$captureName-values');
        final switchButton = find.byKey(
          ValueKey('recipe-substitutes:Beer:${inputs.first.ingredient.name}'),
        );
        await tester.ensureVisible(switchButton);
        await tester.pumpAndSettle();
        await tester.tap(switchButton);
        await settle(tester, broker);
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('recipe-choose:Beer:High-Quality Wheat')),
          findsOneWidget,
        );
        expect(find.text('For 1 craft'), findsNothing);
        checkBadgeLines(tester);
        checkColumnAlignment(tester);
        expect(tester.takeException(), isNull);
        await capture(tester, '$captureName-substitutes');
        final hq = find.byKey(
          const ValueKey('recipe-choose:Beer:High-Quality Wheat'),
        );
        await tester.ensureVisible(hq);
        await tester.tap(hq);
        await tester.pumpAndSettle();
        expect(
          book
              .availabilityFor('Beer')
              .ingredients
              .any((r) => r.name == 'High-Quality Wheat'),
          isTrue,
        );
        expect(tester.takeException(), isNull);
        for (final sort in RecipeBookMarketSort.values) {
          book.setMarketSort(sort);
          await tester.pumpAndSettle();
          checkOutputStockAlignment(tester);
          expect(
            find.byType(InventoryCountBadge),
            sort.sortsAvailability ? findsWidgets : findsNothing,
            reason:
                'Ingredient tables are opt-in through availability sorting only.',
          );
        }
        await tester.pumpWidget(const SizedBox());
        book.dispose();
        await broker.dispose();
        await app.dispose();
      });
    }
  }
}

void checkValueAlignment(WidgetTester tester, String name) {
  final labels = [
    for (final id in ['all', 'missing', 'owned'])
      tester.getRect(find.byKey(ValueKey('recipe-value-label:$name:$id'))),
  ];
  final values = [
    for (final id in ['all', 'missing', 'owned'])
      tester.getRect(find.byKey(ValueKey('recipe-value:$name:$id'))),
  ];
  if ((labels.first.top - labels.last.top).abs() < 1) {
    for (var i = 0; i < 3; i++) {
      expect(values[i].left, closeTo(labels[i].left, .1));
      expect(values[i].top, closeTo(values.first.top, .1));
      expect(values[i].top, greaterThan(labels[i].bottom));
      if (i > 0) expect(labels[i].left, greaterThan(labels[i - 1].right));
    }
  } else {
    for (var i = 0; i < 3; i++) {
      expect(labels[i].left, closeTo(labels.first.left, .1));
      expect(values[i].right, closeTo(values.first.right, .1));
      expect(values[i].left, greaterThan(labels[i].right));
      if (i > 0) expect(values[i].top, greaterThan(values[i - 1].bottom));
    }
  }
}

void checkColumnAlignment(WidgetTester tester) {
  for (final element in find.byType(Table).evaluate()) {
    Finder within(Finder matching) {
      final candidates = matching.evaluate().toSet();
      return find.byElementPredicate((candidate) {
        if (!candidates.contains(candidate)) return false;
        Element? nearestTable;
        candidate.visitAncestorElements((ancestor) {
          if (ancestor.widget is Table) {
            nearestTable = ancestor;
            return false;
          }
          return true;
        });
        return identical(nearestTable, element);
      });
    }

    if (within(find.text('Inventory')).evaluate().isEmpty) continue;
    final inventoryCenter = tester
        .getCenter(within(find.text('Inventory')).first)
        .dx;
    final heading = within(find.text('Inventory')).first;
    final paragraph = tester.renderObject<RenderParagraph>(
      find.descendant(of: heading, matching: find.byType(RichText)).first,
    );
    expect(
      paragraph.getBoxesForSelection(
        const TextSelection(baseOffset: 0, extentOffset: 9),
      ),
      hasLength(1),
      reason: 'Inventory must not split mid-word at enlarged text sizes.',
    );
    final header = (element.widget as Table).children.first;
    expect(header.children, hasLength(5));
    final marketCenter = tester.getCenter(within(find.text('Market')).first).dx;
    for (final inventory in within(
      find.byType(InventoryCountBadge),
    ).evaluate()) {
      expect(
        tester.getCenter(find.byWidget(inventory.widget)).dx,
        closeTo(inventoryCenter, .1),
        reason: 'Inventory badges must be centered under Inventory.',
      );
    }
    double? preorderLeft;
    for (final badgeElement in within(
      find.byType(MarketCountBadges),
    ).evaluate()) {
      final badge = badgeElement.widget as MarketCountBadges;
      final boxes = find.descendant(
        of: find.byElementPredicate(
          (candidate) => identical(candidate, badgeElement),
        ),
        matching: find.byWidgetPredicate(
          (widget) => widget is Container && widget.decoration is BoxDecoration,
        ),
      );
      expect(badge.npc, isFalse, reason: 'NPC is beside the ingredient name.');
      final stockRect = tester.getRect(boxes.first);
      expect(
        stockRect.center.dx,
        closeTo(marketCenter, .1),
        reason:
            'Actual badge centers must match their heading, including unknown stock.',
      );
      if (!badge.npc && boxes.evaluate().length > 1) {
        final orders = tester.getRect(boxes.at(1));
        preorderLeft ??= orders.left;
        expect(orders.left, closeTo(preorderLeft, .1));
        expect(orders.center.dy, closeTo(stockRect.center.dy, .1));
        expect(orders.left, greaterThan(stockRect.right));
      }
    }
    for (final row in (element.widget as Table).children.skip(1)) {
      final ingredient = tester.getRect(find.byWidget(row.children.first));
      final inventory = tester.getRect(find.byWidget(row.children[2]));
      final market = tester.getRect(find.byWidget(row.children[4]));
      final scale = MediaQuery.textScalerOf(element).scale(14) / 14;
      expect(
        inventory.left - ingredient.right,
        greaterThanOrEqualTo(32 * scale - .1),
        reason:
            'Keep a dedicated gap after the full ingredient/quantity/switch cell.',
      );
      expect(
        market.left - inventory.right,
        greaterThanOrEqualTo(14 * scale - .1),
      );
      expect(ingredient.center.dy, closeTo(inventory.center.dy, .1));
      for (final label
          in find
              .descendant(
                of: find.byWidget(row.children.first),
                matching: find.byType(ItemNameWithNpc),
              )
              .evaluate()) {
        final identity = label.widget as ItemNameWithNpc;
        if (!identity.npc) continue;
        final marker = find.descendant(
          of: find.byWidget(identity),
          matching: find.byType(NpcSourceMarker),
        );
        final name = tester.getRect(find.byWidget(identity.child));
        final npc = tester.getRect(marker);
        expect(npc.left - name.right, closeTo(12, .1));
        expect(npc.center.dy, closeTo(name.center.dy, .1));
        expect(npc.right, lessThanOrEqualTo(ingredient.right));
      }
    }
  }
}

void checkBadgeLines(WidgetTester tester) {
  for (final badge in find.byType(InventoryCountBadge).evaluate()) {
    final paragraph = find.descendant(
      of: find.byWidget(badge.widget),
      matching: find.byType(RichText),
    );
    expect(
      tester.renderObject<RenderParagraph>(paragraph.first).didExceedMaxLines,
      isFalse,
    );
  }
  for (final element in find.byType(MarketCountBadges).evaluate()) {
    final badge = element.widget as MarketCountBadges;
    if (!badge.singleLine) continue;
    final texts = find.descendant(
      of: find.byElementPredicate((candidate) => identical(candidate, element)),
      matching: find.byType(Text),
    );
    final rects = texts
        .evaluate()
        .map((element) => tester.getRect(find.byWidget(element.widget)))
        .toList();
    for (final rect in rects.skip(1)) {
      expect(rect.center.dy, closeTo(rects.first.center.dy, .1));
    }
    for (final text in texts.evaluate()) {
      final paragraph = find.descendant(
        of: find.byWidget(text.widget),
        matching: find.byType(RichText),
      );
      expect(
        tester.renderObject<RenderParagraph>(paragraph.first).didExceedMaxLines,
        isFalse,
      );
    }
  }
}

void checkOutputStockAlignment(WidgetTester tester) {
  final outputs = find.byWidgetPredicate(
    (widget) =>
        widget.key is ValueKey<String> &&
        (widget.key! as ValueKey<String>).value.startsWith(
          'recipe-output-stock:',
        ),
  );
  expect(outputs, findsWidgets);
  for (final element in outputs.evaluate()) {
    final key = element.widget.key! as ValueKey<String>;
    final name = key.value.substring('recipe-output-stock:'.length);
    final output = find.byKey(key);
    expect(
      output,
      findsOneWidget,
      reason: 'No duplicate output badge in the footer.',
    );
    final badge = tester.getRect(output);
    final method = tester.getRect(
      find.byKey(RecipeBookKeys.productionMethod(name)),
    );
    final actions = tester.getRect(
      find.byKey(ValueKey('recipe-actions:$name')),
    );
    final card = tester.getRect(find.byKey(RecipeBookKeys.card(name)));
    expect(badge.left, closeTo(method.left, .1));
    expect(badge.top - method.bottom, greaterThanOrEqualTo(7.9));
    expect(badge.bottom, lessThan(actions.top));
    expect(badge.right, lessThanOrEqualTo(card.right));
    final target = tester.getRect(find.byKey(RecipeBookKeys.r11Target(name)));
    expect(target.left + 5, closeTo(badge.left, .1));
    final footer = find.byKey(ValueKey('recipe-can-craft:$name'));
    if (footer.evaluate().isNotEmpty) {
      expect(badge.bottom, lessThan(tester.getRect(footer).top));
    }
  }
}

Future<void> capture(WidgetTester tester, String name) async {
  final images = tester.widgetList<Image>(find.byType(Image)).toList();
  await tester.runAsync(() async {
    for (final image in images) {
      await precacheImage(
        image.image,
        tester.element(find.byKey(const ValueKey('capture'))),
      );
    }
  });
  await tester.pumpAndSettle();
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(const ValueKey('capture-root')),
  );
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 1);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    final dir = Directory('build/recipe-book-alignment-captures')
      ..createSync(recursive: true);
    File('${dir.path}/$name.png').writeAsBytesSync(data!.buffer.asUint8List());
    image.dispose();
  });
}
