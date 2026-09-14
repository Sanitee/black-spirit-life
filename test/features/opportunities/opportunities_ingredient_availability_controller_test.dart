import 'dart:convert';
import 'dart:typed_data';

import 'package:bdo_craft_planner_flutter/data/catalog/catalog_repository.dart';
import 'package:bdo_craft_planner_flutter/data/market/shared_market_repository.dart';
import 'package:bdo_craft_planner_flutter/data/opportunities/opportunity_market_service.dart';
import 'package:bdo_craft_planner_flutter/domain/models/craft_mode.dart';
import 'package:bdo_craft_planner_flutter/domain/opportunities/opportunity_calculator.dart';
import 'package:bdo_craft_planner_flutter/domain/state/planner_state.dart';
import 'package:bdo_craft_planner_flutter/domain/state/state_copy.dart';
import 'package:bdo_craft_planner_flutter/features/opportunities/opportunities_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../domain/opportunities/opportunity_calculator_test.dart' as recipes;
import '../../support/application_test_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'cold ingredient summaries qualify without output prices or hidden-row book loading',
    () async {
      final f = await _Fixture.create(seed: false);
      addTearDown(f.dispose);
      await f.toggle(true);
      expect(f.names, {'NPC recipe'});
      expect(f.transport.requests, isEmpty);
      await f.seed();
      expect(f.names, {'Available', 'Choice', 'Variants', 'NPC recipe'});
      expect(f.transport.requests, hasLength(2));
      expect(
        f.transport.requests.any(
          (uri) => uri.path.endsWith('GetBiddingInfoList'),
        ),
        isFalse,
      );
      final quote = f.quote('Available');
      expect(quote.outputMarket, isNull);
      expect(quote.marketReady, isFalse);
      expect(quote.hasUncheckedInputDepth, isTrue);
      expect(quote.inputCost, isNull);
      expect(quote.ingredientsAvailable, isTrue);
      final before = f.controller.market.items['3']!.quoteFetchedAt;
      await f.toggle(false);
      await f.toggle(true);
      expect(f.transport.requests, hasLength(2));
      expect(f.controller.market.items['3']!.quoteFetchedAt, before);
    },
  );

  test(
    'toggle recomputes supply-aware choices and restores ordinary selection when off',
    () async {
      final f = await _Fixture.create();
      addTearDown(f.dispose);
      final document = f.harness.bundle.controller.documentSnapshot;
      expect(f.quote('Choice').ingredients.single.name, 'Ore');
      expect(f.quote('Variants').selectedVariantId, 'cheap');
      expect(f.quote('Choice').ingredientsAvailable, isFalse);
      final count = f.transport.requests.length;
      await f.toggle(true);
      expect(f.quote('Choice').ingredients.single.name, 'Fine Ore');
      expect(f.quote('Variants').selectedVariantId, 'stocked');
      expect(f.names, isNot(contains('Unavailable')));
      final child = f.controller.inspectRecipe(
        recipe: f.controller.recipes['Choice']!,
      );
      expect(child.quote.ingredients.single.name, 'Fine Ore');
      final variant = f.controller.inspectRecipe(
        recipe: f.controller.recipes['Variants']!,
      );
      expect(variant.quote.selectedVariantId, 'stocked');
      expect(variant.recipe.ingredients.single.name, 'Fine Ore');
      final locked = f.controller.inspectRecipe(
        recipe: f.controller.recipes['Variants']!,
        selectedVariantId: 'cheap',
      );
      expect(locked.quote.selectedVariantId, 'cheap');
      expect(locked.quote.ingredientsAvailable, isFalse);
      await f.toggle(false);
      expect(f.quote('Choice').ingredients.single.name, 'Ore');
      expect(f.quote('Variants').selectedVariantId, 'cheap');
      expect(f.names, contains('Unavailable'));
      expect(f.transport.requests, hasLength(count));
      expect(f.harness.bundle.controller.documentSnapshot, same(document));
    },
  );

  test(
    'overview ignores retired counts while detail quantity still controls availability',
    () async {
      final f = await _Fixture.create();
      addTearDown(f.dispose);
      await f.toggle(true);
      f.controller.change((p) {
        p.crafts = 10;
        p.craftSort = 'preorders';
        p.craftSearch = 'Available';
      });
      await f.settle();
      expect(f.names, {'Available'});
      expect(f.quote('Available').crafts, 1);
      final recipe = f.controller.recipes['Available']!;
      expect(
        f.controller
            .inspectRecipe(recipe: recipe, crafts: 10)
            .quote
            .ingredientsAvailable,
        isTrue,
      );
      expect(
        f.controller
            .inspectRecipe(recipe: recipe, crafts: 11)
            .quote
            .ingredientsAvailable,
        isFalse,
      );
      final overview = f.quote('Available');
      f.controller.change((p) => p.crafts = 11);
      await f.settle();
      expect(f.names, {'Available'});
      expect(f.quote('Available'), same(overview));
      expect(f.controller.preferences.crafts, 11);
      f.controller.change((p) => p.craftSearch = 'NPC');
      await f.settle();
      expect(f.names, {'NPC recipe'});
      expect(f.transport.requests, hasLength(2));
    },
  );

  test(
    'stock expiration removes unavailable rows without automatic network expansion',
    () async {
      final f = await _Fixture.create();
      addTearDown(f.dispose);
      await f.toggle(true);
      final count = f.transport.requests.length;
      f.now = f.now.add(
        OpportunitiesController.maxMarketAge + const Duration(milliseconds: 1),
      );
      f.controller.recalculate();
      await f.settle();
      expect(f.names, {'NPC recipe'});
      expect(f.transport.requests, hasLength(count));
      expect(f.controller.market.items['3']!.quoteFetchedAt, isNot(f.now));
    },
  );
}

final class _Fixture {
  _Fixture(this.harness);
  final ApplicationTestHarness harness;
  DateTime now = DateTime.utc(2026, 9, 13, 8);
  late final _Transport transport;
  late final SharedMarketRepository broker;
  late final OpportunitiesController controller;

  static Future<_Fixture> create({bool seed = true}) async {
    final f = _Fixture(await ApplicationTestHarness.create());
    f.harness.bundle.controller.modes[CraftMode.processing]!.updateState(
      (state) => state.copyWith(
        recipeEdits: {
          ...state.recipeEdits,
          'Ore': RecipeState(marketId: '2'),
          'Fine Ore': RecipeState(marketId: '3'),
          'NPC material': RecipeState(npcPrice: 10),
        },
      ),
    );
    f.transport = _Transport(() => f.now);
    f.broker = SharedMarketRepository(
      transport: f.transport,
      utcNow: () => f.now,
      quoteBatchSize: 1,
      requestSpacing: Duration.zero,
      recoveryRequestSpacing: Duration.zero,
    );
    f.controller = OpportunitiesController(
      appController: f.harness.bundle.controller,
      catalog: CatalogRepository(f.harness.bundle.catalog),
      directory: f.harness.temporaryDirectory,
      sharedMarket: f.broker,
      clock: () => f.now,
    );
    await f.controller.ready;
    f.controller.change((p) {
      p.mode = CraftMode.processing;
      p.profitableOnly = false;
    }, assemble: true);
    await f.controller.calculationSettled;
    f.controller.recipes = {
      'Available': recipes.recipe(
        'Available',
        ingredients: [recipes.ingredient('Fine Ore', 1)],
      ),
      'Unavailable': recipes.recipe('Unavailable'),
      'Choice': recipes.recipe(
        'Choice',
        ingredients: [
          recipes.ingredient('Ore', 1, options: ['Ore', 'Fine Ore']),
        ],
      ),
      'Variants': recipes.recipe(
        'Variants',
        variants: [
          recipes.variant('cheap', [recipes.ingredient('Ore', 1)]),
          recipes.variant('stocked', [recipes.ingredient('Fine Ore', 1)]),
        ],
      ),
      'NPC recipe': recipes.recipe(
        'NPC recipe',
        ingredients: [recipes.ingredient('NPC material', 1)],
      ),
      'Ore': recipes.leaf('Ore', id: '2'),
      'Fine Ore': recipes.leaf('Fine Ore', id: '3'),
      'NPC material': recipes.leaf('NPC material', npc: 10),
    };
    f.controller.recalculate();
    await f.controller.calculationSettled;
    if (seed) await f.seed();
    return f;
  }

  Set<String> get names =>
      controller.visibleQuotes.map((quote) => quote.recipeName).toSet();
  OpportunityQuote quote(String name) =>
      controller.quotes.singleWhere((quote) => quote.recipeName == name);
  Future<void> toggle(bool value) async {
    controller.change((p) => p.readyOnly = value);
    await settle();
  }

  Future<void> seed() async {
    await broker.fetch(
      quoteKeys: [
        for (final id in ['2', '3']) SharedMarketKey(region: 'eu', itemId: id),
      ],
    );
    await settle();
  }

  Future<void> settle() async {
    await Future<void>.delayed(const Duration(milliseconds: 250));
    await controller.calculationSettled;
  }

  Future<void> dispose() async {
    controller.cancel();
    await broker.close();
    await controller.flush();
    controller.dispose();
    await harness.dispose();
  }
}

final class _Transport implements OpportunityMarketTransport {
  _Transport(this.now);
  final DateTime Function() now;
  final List<Uri> requests = [];
  @override
  Future<OpportunityHttpResponse> post(
    Uri uri, {
    required Map<String, String> headers,
    required String body,
    Future<void>? abortTrigger,
  }) async {
    requests.add(uri);
    if (uri.path.endsWith('GetBiddingInfoList')) {
      throw StateError('The availability filter must not load order books.');
    }
    final id = '${(jsonDecode(body) as Map)['mainKey']}';
    final stock = id == '2' ? 0 : 10;
    final price = id == '2' ? 10 : 20;
    final message =
        '$id-0-0-$price-$stock-1000-1-10000-$price-${now().millisecondsSinceEpoch ~/ 1000}|';
    return OpportunityHttpResponse(
      statusCode: 200,
      bytes: Uint8List.fromList(
        utf8.encode(jsonEncode({'resultCode': 0, 'resultMsg': message})),
      ),
    );
  }

  @override
  void close() {}
}
