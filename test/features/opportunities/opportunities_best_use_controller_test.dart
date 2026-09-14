import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:bdo_craft_planner_flutter/data/catalog/catalog_repository.dart';
import 'package:bdo_craft_planner_flutter/data/market/shared_market_repository.dart';
import 'package:bdo_craft_planner_flutter/data/opportunities/opportunity_market_cache_store.dart';
import 'package:bdo_craft_planner_flutter/data/opportunities/opportunity_market_service.dart';
import 'package:bdo_craft_planner_flutter/domain/models/craft_mode.dart';
import 'package:bdo_craft_planner_flutter/domain/state/planner_state.dart';
import 'package:bdo_craft_planner_flutter/domain/state/state_copy.dart';
import 'package:bdo_craft_planner_flutter/features/opportunities/opportunities_controller.dart';
import 'package:bdo_craft_planner_flutter/features/opportunities/opportunities_preferences.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/application_test_harness.dart';

const _material = 'Best use test material';
const _other = 'Best use other input';
const _different = 'Different test material';
const _selectedId = '990111';
const _otherId = '990112';
const _differentId = '990120';
const _differentOutput = '990121';
final _outputIds = {
  for (final mode in CraftMode.values) mode: '${990101 + mode.index}',
};
String _name(CraftMode mode) => 'Direct ${mode.key} use';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'suggestions use live definitions in every mode without mutation or requests',
    () async {
      final f = await _Fixture.create();
      addTearDown(f.dispose);
      final before = jsonEncode(
        f.harness.bundle.controller.documentSnapshot.toJson(),
      );
      final crafting = f.controller.preferences.mode;
      expect(
        f.controller.bestUseItems,
        containsAll([_material, _other, _different]),
      );
      f.controller.selectBestUseItem('  ${_material.toUpperCase()}  ');
      await f.settle();
      expect(f.controller.preferences.bestUseItem, _material);
      expect(
        f.controller.bestUseQuotes.map((use) => use.mode),
        unorderedEquals(CraftMode.values),
      );
      expect(
        f.controller.bestUseQuotes.every(
          (use) => use.extraProfitPerUnit == null,
        ),
        isTrue,
      );
      expect(f.controller.preferences.mode, crafting);
      expect(
        jsonEncode(f.harness.bundle.controller.documentSnapshot.toJson()),
        before,
      );
      expect(f.transport.quoteIds, isEmpty);
      expect(f.transport.books, isEmpty);
    },
  );

  test(
    'prefetch-enabled Refresh remains bounded to direct uses and preserves source mastery',
    () async {
      final f = await _Fixture.create(prefetchAll: true);
      addTearDown(f.dispose);
      final before = jsonEncode(
        f.harness.bundle.controller.documentSnapshot.toJson(),
      );
      await f.controller.refresh();
      await f.settle();
      expect(f.transport.quoteIds, {
        ..._outputIds.values,
        _selectedId,
        _otherId,
      });
      expect(f.transport.quoteIds, isNot(contains(_differentOutput)));
      expect(f.transport.books, isEmpty);
      expect(f.controller.bestUseQuotes, hasLength(3));
      for (final use in f.controller.bestUseQuotes) {
        final inspection = f.controller.inspectRecipe(
          recipe: use.recipe,
          selectedVariantId: use.quote.selectedVariantId,
          ingredientChoices: use.ingredientChoices,
        );
        expect(inspection.sourceMode, use.mode);
        expect(inspection.mastery, switch (use.mode) {
          CraftMode.alchemy => 700,
          CraftMode.cooking => 1400,
          CraftMode.processing => 2100,
        });
        expect(inspection.quote.listingRevenue, use.quote.listingRevenue);
        expect(use.extraProfitPerUnit, isNotNull);
      }
      expect(
        jsonEncode(f.harness.bundle.controller.documentSnapshot.toJson()),
        before,
      );
      expect(f.controller.preferences.mode, CraftMode.cooking);
    },
  );

  test(
    'ready filter scans hidden candidates but ignores selected material stock',
    () async {
      final f = await _Fixture.create();
      addTearDown(f.dispose);
      f.transport.quoteStocks[_otherId] = 0;
      await f.controller.refresh();
      await f.settle();
      f.controller.change((p) => p.readyOnly = true);
      await f.settle();
      expect(f.controller.visibleBestUseQuotes, isEmpty);
      expect(f.transport.books, isEmpty);
      f.now = f.now.add(const Duration(milliseconds: 1));
      f.controller.setWorkspaceActive(true);
      await _until(
        () => f.controller.detailStatus.complete && !f.controller.scanning,
      );
      await f.settle();
      expect(f.transport.books, isNot(contains(_selectedId)));
      expect(f.transport.books.toSet(), {..._outputIds.values, _otherId});
      expect(f.controller.visibleBestUseQuotes, hasLength(3));
      expect(f.controller.market.items[_selectedId]!.stock, 0);
      expect(
        f.controller.bestUseQuotes.every(
          (use) => use.otherIngredientsAvailable,
        ),
        isTrue,
      );
    },
  );

  test(
    'out-of-stock and preorder ordering use current scoped output receipts',
    () async {
      final f = await _Fixture.create();
      addTearDown(f.dispose);
      final outputs = _outputIds.values.toList();
      f.transport.quoteStocks.addAll({
        outputs[0]: 10,
        outputs[1]: 0,
        outputs[2]: 0,
      });
      f.transport.bookStocks.addAll({
        outputs[0]: 10,
        outputs[1]: 0,
        outputs[2]: 0,
      });
      f.transport.demands.addAll({
        outputs[0]: 50,
        outputs[1]: 8,
        outputs[2]: 3,
      });
      await f.controller.refresh();
      await f.settle();
      f.controller.change((p) {
        p.demandOnly = true;
        p.craftSort = 'preorders';
      });
      f.controller.setWorkspaceActive(true);
      await _until(
        () => f.controller.detailStatus.complete && !f.controller.scanning,
      );
      await f.settle();
      expect(
        f.controller.visibleBestUseQuotes.map((use) => use.recipe.marketId),
        [outputs[1], outputs[2]],
      );
      expect(f.controller.bestUseDemandPendingCount, 0);
      expect(f.transport.books.toSet(), outputs.toSet());
      f.transport.bookStocks[outputs[1]] = 20;
      f.now = f.now.add(const Duration(milliseconds: 1));
      await f.broker.fetch(bookKeys: [f.key(outputs[1])], forceRefresh: true);
      expect(
        f.controller.visibleBestUseQuotes.map((use) => use.recipe.marketId),
        [outputs[2]],
        reason:
            'A newer stocked receipt cannot remain a zero-stock result while calculations catch up.',
      );
    },
  );

  test(
    'unknown demand remains pending and stopped work cannot restart on filters',
    () async {
      final f = await _Fixture.create(concurrency: 1);
      addTearDown(f.dispose);
      f.transport.heldId = _outputIds.values.first;
      f.controller.change((p) {
        p.demandOnly = true;
        p.craftSort = 'preorders';
      });
      await f.settle();
      expect(f.controller.bestUseDemandPendingCount, 3);
      expect(f.controller.visibleBestUseQuotes, isEmpty);
      f.controller.setWorkspaceActive(true);
      await _until(() => f.transport.books.isNotEmpty);
      f.controller.cancel();
      await _until(() => !f.controller.scanning);
      final requests = f.transport.books.length;
      f.controller.change((p) => p.readyOnly = true);
      f.controller.change((p) => p.readyOnly = false);
      f.controller.setWorkspaceActive(false);
      f.controller.setWorkspaceActive(true);
      await f.settle();
      expect(f.transport.books, hasLength(requests));
      expect(f.broker.diagnostics.queuedParts, 0);
    },
  );

  test(
    'selection debounce fetches only the latest material and no offstage scope',
    () async {
      final f = await _Fixture.create(autoCheck: true, prefetchAll: true);
      addTearDown(f.dispose);
      f.controller.setWorkspaceActive(true);
      f.controller.selectBestUseItem(_different);
      f.controller.selectBestUseItem(_material);
      f.controller.selectBestUseItem(_different);
      await _until(
        () => f.transport.quoteIds.isNotEmpty && !f.controller.scanning,
      );
      await f.settle();
      expect(f.transport.quoteIds, {_differentId, _differentOutput, _otherId});
      final before = Set<String>.of(f.transport.quoteIds);
      f.controller.selectBestUseItem(_material);
      f.controller.setWorkspaceActive(false);
      await Future<void>.delayed(const Duration(milliseconds: 500));
      expect(f.transport.quoteIds, before);
    },
  );

  test(
    'hidden and deleted direct uses disappear without resurrecting bundled definitions',
    () async {
      final f = await _Fixture.create();
      addTearDown(f.dispose);
      expect(
        f.controller
            .liveRecipeFor(
              _name(CraftMode.alchemy),
              preferredMode: CraftMode.cooking,
            )
            ?.type,
        'alchemy',
      );
      for (final mode in CraftMode.values) {
        f.harness.bundle.controller.modes[mode]!.updateState(
          (state) => state.copyWith(
            recipeEdits: {...state.recipeEdits, _name(mode): null},
          ),
        );
      }
      await f.settle();
      expect(f.controller.bestUseItems, isNot(contains(_material)));
      expect(f.controller.bestUseQuotes, isEmpty);
      expect(
        f.controller.liveRecipeFor(
          _name(CraftMode.alchemy),
          preferredMode: CraftMode.alchemy,
        ),
        isNull,
      );
      expect(f.transport.quoteIds, isEmpty);
    },
  );

  test(
    'canonical material includes cross-mode direct aliases sharing its market ID',
    () async {
      final f = await _Fixture.create();
      addTearDown(f.dispose);
      const alias = 'Alias of selected material';
      f.harness.bundle.controller.modes[CraftMode.processing]!.updateState(
        (state) => state.copyWith(
          recipeEdits: {
            ...state.recipeEdits,
            _material: null,
            alias: RecipeState(marketId: _selectedId),
            _name(CraftMode.processing): _recipe(
              CraftMode.processing,
              _outputIds[CraftMode.processing]!,
              alias,
            ),
          },
        ),
      );
      await f.settle();
      await f.controller.refresh();
      await f.settle();
      final result = f.controller.bestUseQuotes.singleWhere(
        (use) => use.mode == CraftMode.processing,
      );
      expect(result.itemName, _material);
      expect(result.ingredientChoices.values, contains(alias));
      expect(result.extraProfitPerUnit, isNotNull);
      expect(f.transport.quoteIds, {
        ..._outputIds.values,
        _selectedId,
        _otherId,
      });
    },
  );

  test(
    'cached known nonmarket output cannot enter the Best use consumer index',
    () async {
      final f = await _Fixture.create(cachedPrices: {'44449': 1000000});
      addTearDown(f.dispose);
      const name = 'Mutant Loah Flower Neutralizer';
      final recipe = f.controller.liveRecipeFor(
        name,
        preferredMode: CraftMode.alchemy,
      );
      expect(recipe, isNotNull);
      expect(recipe!.marketId, '44449');
      f.controller.selectBestUseItem('Trace of Nature');
      await f.settle();
      expect(f.controller.market.items['44449']!.basePrice, 1000000);
      expect(
        f.controller.bestUseQuotes.map((use) => use.recipe.name),
        isNot(contains(name)),
      );
      expect(f.transport.quoteIds, isEmpty);
      expect(f.transport.books, isEmpty);
    },
  );

  test(
    'cached known nonmarket material cannot create a direct-sale baseline',
    () async {
      final f = await _Fixture.create(
        cachedPrices: {
          '44449': 10,
          _otherId: 20,
          for (final id in _outputIds.values) id: 1000,
        },
      );
      addTearDown(f.dispose);
      for (final mode in CraftMode.values) {
        f.harness.bundle.controller.modes[mode]!.updateState(
          (state) => state.copyWith(
            recipeEdits: {
              ...state.recipeEdits,
              _material: RecipeState(marketId: '44449'),
            },
          ),
        );
      }
      await f.settle();
      expect(f.controller.market.items['44449']!.basePrice, 10);
      expect(f.controller.bestUseQuotes, hasLength(3));
      for (final use in f.controller.bestUseQuotes) {
        expect(use.extraProfitPerUnit, isNull);
        expect(use.otherInputCost, isNotNull);
        expect(use.quote.listingRevenue, isNotNull);
        expect(
          f.controller.inspectRecipe(recipe: use.recipe).quote.listingProfit,
          isNotNull,
          reason: 'Only Best use eligibility changes, not ordinary crafting.',
        );
      }
      expect(f.transport.quoteIds, isEmpty);
      expect(f.transport.books, isEmpty);
    },
  );

  test(
    'fresh receipts keep coherent rows while source-mode edits invalidate calculations',
    () async {
      final f = await _Fixture.create();
      addTearDown(f.dispose);
      await f.controller.refresh();
      await f.settle();
      final before = f.controller.bestUseQuotes;
      f.now = f.now.add(const Duration(milliseconds: 1));
      await f.broker.fetch(
        quoteKeys: [f.key(_outputIds[CraftMode.alchemy]!)],
        forceRefresh: true,
      );
      f.controller.recalculate(marketUpdate: true);
      expect(f.controller.bestUseQuotes, same(before));
      await f.controller.calculationSettled;
      f.harness.bundle.controller.modes[CraftMode.alchemy]!.updateState(
        (state) => state.copyWith(alchemyMastery: 2500),
      );
      await f.settle();
      final result = f.controller.bestUseQuotes.singleWhere(
        (use) => use.mode == CraftMode.alchemy,
      );
      final detail = f.controller.inspectRecipe(
        recipe: result.recipe,
        selectedVariantId: result.quote.selectedVariantId,
        ingredientChoices: result.ingredientChoices,
      );
      expect(detail.mastery, 2500);
      expect(detail.quote.listingRevenue, result.quote.listingRevenue);
      expect(f.controller.preferences.mode, CraftMode.cooking);
    },
  );

  test(
    'switching sections releases Best use books without changing crafting selection',
    () async {
      final f = await _Fixture.create(concurrency: 1);
      addTearDown(f.dispose);
      f.transport.heldId = _outputIds.values.first;
      f.controller.setWorkspaceActive(true);
      f.controller.change((p) => p.craftSort = 'preorders');
      await _until(() => f.transport.books.isNotEmpty);
      f.controller.change((p) => p.section = 'exchanges');
      await _until(() => !f.controller.scanning);
      expect(f.controller.detailStatus.requested, isFalse);
      expect(f.broker.diagnostics.queuedParts, 0);
      expect(f.controller.preferences.mode, CraftMode.cooking);
      expect(f.controller.preferences.bestUseItem, _material);
      expect(f.controller.preferences.craftSearch, 'preserved crafting search');
    },
  );
}

Future<void> _until(bool Function() predicate) async {
  final deadline = DateTime.now().add(const Duration(seconds: 15));
  while (!predicate()) {
    if (DateTime.now().isAfter(deadline)) fail('Best use work did not settle');
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

final class _Fixture {
  _Fixture(this.harness);
  final ApplicationTestHarness harness;
  DateTime now = DateTime.utc(2026, 9, 13, 21);
  late final _Transport transport;
  late final SharedMarketRepository broker;
  late final OpportunitiesController controller;

  static Future<_Fixture> create({
    bool autoCheck = false,
    bool prefetchAll = false,
    int concurrency = 10,
    Map<String, int> cachedPrices = const {},
  }) async {
    final f = _Fixture(await ApplicationTestHarness.create());
    for (final mode in CraftMode.values) {
      f.harness.bundle.controller.modes[mode]!.updateState(
        (state) => state.copyWith(
          alchemyMastery: 700,
          cookingMastery: 1400,
          processingMastery: 2100,
          recipeEdits: {
            ...state.recipeEdits,
            _material: RecipeState(marketId: _selectedId),
            _other: RecipeState(marketId: _otherId),
            _name(mode): _recipe(mode, _outputIds[mode]!, _material),
            if (mode == CraftMode.alchemy) ...{
              _different: RecipeState(marketId: _differentId),
              'Different direct use': _recipe(
                mode,
                _differentOutput,
                _different,
              ),
            },
          },
        ),
      );
    }
    f.transport = _Transport(() => f.now);
    final cache = cachedPrices.isEmpty
        ? null
        : OpportunityMarketCacheStore(
            directory: f.harness.temporaryDirectory,
            utcNow: () => f.now,
          );
    await cache?.save({
      'eu': {
        for (final entry in cachedPrices.entries)
          entry.key: OpportunityMarketItem(
            itemId: entry.key,
            basePrice: entry.value,
            stock: 100,
            quoteFetchedAt: f.now,
          ),
      },
    });
    f.broker = SharedMarketRepository(
      cacheStore: cache,
      transport: f.transport,
      utcNow: () => f.now,
      quoteBatchSize: 200,
      requestSpacing: Duration.zero,
      recoveryRequestSpacing: Duration.zero,
      concurrency: concurrency,
    );
    await OpportunitiesPreferenceStore(f.harness.temporaryDirectory).save(
      OpportunitiesPreferences()
        ..section = 'best-use'
        ..mode = CraftMode.cooking
        ..bestUseItem = _material
        ..profitableOnly = false
        ..craftSearch = 'preserved crafting search',
    );
    f.controller = OpportunitiesController(
      appController: f.harness.bundle.controller,
      catalog: CatalogRepository(f.harness.bundle.catalog),
      directory: f.harness.temporaryDirectory,
      sharedMarket: f.broker,
      clock: () => f.now,
      autoCheck: autoCheck,
      prefetchAll: prefetchAll,
    );
    await f.controller.ready;
    f.controller.change((p) {
      p.section = 'best-use';
      p.mode = CraftMode.cooking;
      p.bestUseItem = _material;
      p.profitableOnly = false;
      p.craftSearch = 'preserved crafting search';
    }, assemble: true);
    await f.settle();
    return f;
  }

  SharedMarketKey key(String id) => SharedMarketKey(region: 'eu', itemId: id);
  Future<void> settle() async {
    await Future<void>.delayed(const Duration(milliseconds: 280));
    await controller.calculationSettled;
  }

  Future<void> dispose() async {
    controller.cancel();
    if (!transport.release.isCompleted) transport.release.complete();
    await broker.close();
    await controller.flush();
    controller.dispose();
    await harness.dispose();
  }
}

RecipeState _recipe(CraftMode mode, String id, String material) => RecipeState(
  type: mode.key,
  marketId: id,
  baseOutput: 1,
  outputMinimum: mode == CraftMode.processing ? 2 : null,
  outputMaximum: mode == CraftMode.processing ? 2 : null,
  method: mode == CraftMode.processing ? 'Heating' : null,
  ingredients: [
    IngredientState(name: material, quantity: 2),
    IngredientState(name: _other, quantity: 1),
  ],
);

final class _Transport implements OpportunityMarketTransport {
  _Transport(this.now);
  final DateTime Function() now;
  final Set<String> quoteIds = {};
  final List<String> books = [];
  final Map<String, int> quoteStocks = {_selectedId: 0};
  final Map<String, int> bookStocks = {};
  final Map<String, int> demands = {};
  String? heldId;
  final release = Completer<void>();
  @override
  Future<OpportunityHttpResponse> post(
    Uri uri, {
    required Map<String, String> headers,
    required String body,
    Future<void>? abortTrigger,
  }) async {
    final data = jsonDecode(body) as Map;
    final ids = data['searchResult'] is String
        ? (data['searchResult'] as String).split(',')
        : ['${data['mainKey']}'];
    final book = uri.path.endsWith('GetBiddingInfoList');
    if (book) {
      books.add(ids.single);
      if (ids.single == heldId) {
        await Future.any([
          release.future,
          if (abortTrigger != null)
            abortTrigger.then(
              (_) => throw const MarketFetchCancelledException(),
            ),
        ]);
      }
    } else {
      quoteIds.addAll(ids);
    }
    int price(String id) => id == _selectedId || id == _differentId
        ? 10
        : id == _otherId
        ? 20
        : 1000 + (int.parse(id) - 990100) * 100;
    final text = ids.length > 1
        ? ids
              .map((id) => '$id-${quoteStocks[id] ?? 100}-${price(id)}-500000')
              .join('|')
        : book
        ? '${price(ids.single)}-${bookStocks[ids.single] ?? 100}-${demands[ids.single] ?? 3}|'
        : '${ids.single}-0-0-${price(ids.single)}-${quoteStocks[ids.single] ?? 100}-500000-1-1000000-${price(ids.single)}-${now().millisecondsSinceEpoch ~/ 1000}|';
    return OpportunityHttpResponse(
      statusCode: 200,
      bytes: Uint8List.fromList(
        utf8.encode(jsonEncode({'resultCode': 0, 'resultMsg': text})),
      ),
    );
  }

  @override
  void close() {}
}
