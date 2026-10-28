import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:bdo_craft_planner_flutter/data/opportunities/exchange_catalog.dart';
import 'package:bdo_craft_planner_flutter/domain/opportunities/exchange_calculator.dart';
import 'package:bdo_craft_planner_flutter/domain/opportunities/exchange_models.dart';
import 'package:bdo_craft_planner_flutter/domain/opportunities/opportunity_market_models.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final now = DateTime.utc(2026, 9, 8, 16);
  final empty = OpportunityMarketSnapshot(region: 'eu', items: {});
  ExchangeCurrency currency(String id) =>
      exchangeCatalog.singleWhere((currency) => currency.id == id);

  OpportunityMarketItem marketItem(
    int id, {
    int price = 10000,
    List<OpportunityMarketLevel>? bids = const [
      OpportunityMarketLevel(price: 10000, quantity: 10000),
    ],
    DateTime? fetchedAt,
    bool unlisted = false,
    String? returnedId,
    int subId = 0,
  }) => OpportunityMarketItem(
    itemId: returnedId ?? id.toString(),
    subId: subId,
    basePrice: price,
    stock: 2000,
    quoteFetchedAt: fetchedAt ?? now,
    asks: const [OpportunityMarketLevel(price: 11000, quantity: 2000)],
    bids: bids,
    bookFetchedAt: fetchedAt ?? now,
    unlisted: unlisted,
  );

  List<ExchangeQuote> evaluate(
    String id, {
    int owned = 100,
    OpportunityMarketSnapshot? market,
    ExchangeSaleMode mode = ExchangeSaleMode.listing,
    double tax = 0.845,
    Map<String, int> limits = const {},
    Set<String> requirements = const {},
  }) => calculateExchangeOptions(
    currency: currency(id),
    owned: owned,
    market: market ?? empty,
    now: now,
    saleMode: mode,
    taxMultiplier: tax,
    remainingLimitedExchanges: limits,
    confirmedRequirementRoutes: requirements,
  );

  ExchangeQuote route(List<ExchangeQuote> quotes, String id) =>
      quotes.singleWhere((quote) => quote.route.id == id);

  test(
    'catalog IDs, names, positive whole quantities and route IDs are unique',
    () {
      expect(exchangeCatalog, hasLength(27));
      expect(exchangeCatalog.map((item) => item.id).toSet(), hasLength(27));
      final routeIds = <String>{};
      for (final currency in exchangeCatalog) {
        expect(currency.sources, isNotEmpty);
        expect(currency.item.id, greaterThan(0));
        for (final route in currency.routes) {
          expect(routeIds.add(route.id), isTrue, reason: route.id);
          expect(route.inputCount, greaterThan(0));
          expect(route.rewards, isNotEmpty);
          for (final reward in route.rewards) {
            expect(reward.quantity, greaterThan(0));
            expect(reward.name, isNotEmpty);
          }
        }
      }
      expect(routeIds, hasLength(237));
    },
  );

  test('full reward lists retain the 24 selected consumable choices', () {
    final expected = <String, List<(int, int, int, int?)>>{
      'mornings-gratitude-token': [
        for (final id in [821143, 821141, 821145, 821137, 821139])
          (30000, id, 1, null),
      ],
      'seal-of-solare': [
        (15, 734, 1, null),
        (15, 748, 1, null),
        (15, 771, 1, null),
        (2, 732, 1, null),
        (1, 575, 3, null),
        (35, 1178, 3, 3),
        (20, 733, 5, 2),
        (20, 576, 25, 1),
      ],
      'energy-of-lakiaro': [(1, 735, 1, null), (10, 750490, 1, 5)],
      'medal-of-glory': [
        (1, 734, 1, null),
        (1, 771, 1, null),
        (10, 1178, 10, 1),
        (3, 576, 30, 1),
        (2, 733, 10, 1),
      ],
      'battlefield-token': [
        (3, 734, 1, 10),
        (3, 771, 1, 10),
        (1, 576, 5, 5),
        (1, 733, 2, 5),
      ],
    };
    expect(exchangeCatalog.skip(22).map((c) => c.id), expected.keys);
    expect(exchangeCatalog.skip(22).map((c) => c.item.id), [
      761321,
      65396,
      42497,
      767325,
      890002,
    ]);
    for (final entry in expected.entries) {
      final current = currency(entry.key);
      expect(current.item.marketable, isFalse);
      expect(current.item.vendorSellPrice, isNull);
      expect(current.legacy, isFalse);
      expect(
        current.routes.map(
          (r) => (
            r.inputCount,
            r.rewards.single.item!.id,
            r.rewards.single.quantity,
            r.limit.maximum,
          ),
        ),
        containsAll(entry.value),
        reason: entry.key,
      );
      for (final r in current.routes) {
        expect(r.directVendorSale, isFalse);
        expect(r.requirements, isEmpty);
        expect(r.sources, isNotEmpty);
        expect(
          r.location,
          entry.key == 'mornings-gratitude-token'
              ? 'Heo Seungwon · Yukjo Street'
              : 'Manage Currency',
        );
      }
    }
    expect(exchangeCatalog.any((c) => c.id.contains('agris')), isFalse);
  });

  test('all selected rewards keep reviewed quantities and limits', () {
    const repeat = ExchangeLimitKind.repeatable;
    const week = ExchangeLimitKind.weekly;
    const day = ExchangeLimitKind.daily;
    const family = ExchangeLimitKind.oncePerFamily;
    final additional = <String, List<(int, int, int, ExchangeLimitKind, int?)>>{
      'seal-of-solare': [
        for (final id in [320009, 320011, 320010]) (5000, id, 1, family, 1),
        (150, 890001, 1, week, 3),
        (30, 820022, 3, week, 5),
        (30, 45912, 1, week, 3),
        (30, 761018, 10, week, 5),
        (20, 17572, 3, week, 3),
        (20, 45162, 30, week, 3),
        (20, 768160, 10, week, 10),
        for (final id in [59858, 59859, 59860]) (5, id, 1, week, 10),
        for (final id in [45107, 45105]) (20, id, 1, day, 1),
        (10, 4, 1, repeat, null),
        (5, 45026, 1, repeat, null),
        (1, 3, 1, repeat, null),
      ],
      'energy-of-lakiaro': [
        (500, 820152, 1, family, 1),
        (100, 11017, 1, family, 1),
        (60, 752825, 1, week, 1),
        (30, 757004, 50, week, 1),
        (5, 757010, 1, week, 1),
        (10, 59861, 1, repeat, null),
        (4, 4917, 1, repeat, null),
        for (final id in [50815, 50816, 50817]) (2, id, 1, repeat, null),
        (1, 44195, 1, repeat, null),
      ],
      'medal-of-glory': [
        (500, 607185, 1, family, 1),
        (250, 289250, 1, family, 1),
        (150, 289200, 1, family, 1),
        (85, 289150, 1, family, 1),
        (50, 289100, 1, family, 1),
        for (final id in [1000509, 1000510, 1000511, 1000512, 1000513])
          (10, id, 1, family, 1),
        (30, 16080, 500, week, 2),
        (10, 45026, 50, week, 1),
        (10, 820022, 10, week, 1),
        (5, 17572, 5, week, 1),
        (10, 45124, 1, repeat, null),
      ],
      'battlefield-token': [
        (50, 890003, 1, week, 3),
        (3, 721003, 30, week, 7),
        (3, 820022, 1, week, 10),
        (3, 768160, 10, week, 10),
        (2, 45026, 5, week, 10),
        (1, 8042, 5, week, 1),
        for (final id in [59858, 59859, 59860]) (1, id, 1, week, 10),
        (50, 4989, 1, repeat, null),
        (1, 4, 1, repeat, null),
      ],
    };
    expect(exchangeCatalog.skip(22).map((c) => c.routes.length), [
      5,
      26,
      13,
      20,
      15,
    ]);
    for (final entry in additional.entries) {
      expect(
        currency(entry.key).routes.map(
          (r) => (
            r.inputCount,
            r.rewards.single.item!.id,
            r.rewards.single.quantity,
            r.limit.kind,
            r.limit.maximum,
          ),
        ),
        containsAll(entry.value),
        reason: entry.key,
      );
    }
    expect(const ExchangeLimit.daily(1).label, 'Up to 1 per day');
    expect(
      currency('energy-of-lakiaro').routes.any(
        (r) =>
            r.rewards.any((reward) => reward.name.contains('Vitality Tonic')),
      ),
      isFalse,
    );
    for (final id in [890001, 890003, 45124]) {
      expect(exchangeItems[id]!.marketable, isFalse);
      expect(
        exchangeItems[id]!.vendorSellPrice,
        isNull,
        reason: 'Random gold box contents do not have an invented average.',
      );
    }
  });

  test(
    'Morning token foods are alternatives, not a bundle or partial exchange',
    () {
      final market = OpportunityMarketSnapshot(
        region: 'eu',
        items: {
          for (final id in [821143, 821141, 821145, 821137, 821139])
            '$id': marketItem(id),
        },
      );
      for (final balance in [29999, 30000, 60001]) {
        final quotes = evaluate(
          'mornings-gratitude-token',
          owned: balance,
          market: market,
        );
        expect(quotes, hasLength(5));
        for (final quote in quotes) {
          expect(quote.exchanges, balance ~/ 30000);
          expect(quote.rewardQuotes.single.quantity, balance ~/ 30000);
          expect(quote.remainder, balance % 30000);
        }
      }
    },
  );

  test('selected daily weekly and family allowances stay independent', () {
    final market = OpportunityMarketSnapshot(
      region: 'eu',
      items: {
        for (final id
            in exchangeItems.values.where((i) => i.marketable).map((i) => i.id))
          '$id': marketItem(id),
      },
    );
    for (final id in [
      'seal-of-solare',
      'energy-of-lakiaro',
      'medal-of-glory',
      'battlefield-token',
    ]) {
      final limited = currency(id).routes.where((r) => !r.limit.isRepeatable);
      final unset = evaluate(id, owned: 1000000, market: market);
      final capped = evaluate(
        id,
        owned: 1000000,
        market: market,
        limits: {for (final r in limited) r.id: 1000},
      );
      for (final r in limited) {
        expect(
          route(unset, r.id).availability,
          ExchangeAvailability.confirmationNeeded,
        );
        expect(route(unset, r.id).exchanges, 0);
        expect(route(capped, r.id).exchanges, r.limit.maximum);
        expect(
          route(capped, r.id).rewardQuotes.single.quantity,
          r.limit.maximum! * r.rewards.single.quantity,
        );
        final exhausted = evaluate(
          id,
          owned: 1000000,
          market: market,
          limits: {
            for (final other in limited)
              other.id: other.id == r.id ? 0 : other.limit.maximum!,
          },
        );
        expect(
          route(exhausted, r.id).availability,
          ExchangeAvailability.limitReached,
        );
        for (final other in limited.where((other) => other.id != r.id)) {
          expect(route(exhausted, other.id).exchanges, other.limit.maximum);
        }
      }
    }
  });

  test(
    'Solare box values only three real potions; bound tea has no sale income',
    () {
      final box = route(
        evaluate(
          'seal-of-solare',
          owned: 2,
          market: OpportunityMarketSnapshot(
            region: 'eu',
            items: {
              '575': marketItem(575, price: 100000),
              '65401': marketItem(65401, price: 999999999),
            },
          ),
        ),
        'solare-potion-box',
      );
      expect(box.route.rewardContainer!.id, 65401);
      expect(box.route.rewardContainer!.marketable, isFalse);
      expect(box.rewardQuotes.single.reward.item!.id, 575);
      expect(box.rewardQuotes.single.quantity, 6);
      expect(box.netProceeds, closeTo(600000 * .845, .001));
      final tea = route(
        evaluate(
          'energy-of-lakiaro',
          owned: 50,
          limits: {'lakiaro-tea': 5},
          market: OpportunityMarketSnapshot(
            region: 'eu',
            items: {'750490': marketItem(750490, price: 999999999)},
          ),
        ),
        'lakiaro-tea',
      );
      expect(tea.exchanges, 5);
      expect(tea.rewardQuotes.single.quantity, 5);
      expect(tea.rewardQuotes.single.reward.item!.marketable, isFalse);
      expect(tea.hasUnpricedRewards, isTrue);
      expect(tea.netProceeds, isNull);
    },
  );

  test(
    'Divine Coin retains exact official identity, choices and source rows',
    () {
      final coin = currency('divine-coin');
      expect(coin.item.id, 980170);
      expect(coin.item.name, 'Divine Coin');
      expect(coin.item.marketable, isFalse);
      expect(coin.item.vendorSellPrice, isNull);
      expect(
        coin.routes.map(
          (r) => (
            r.inputCount,
            r.rewards.single.item!.id,
            r.rewards.single.quantity,
          ),
        ),
        [(10, 821344, 1), (10, 821347, 1), (10, 821182, 1), (1, 4, 1)],
      );
      expect(coin.routes.every((r) => r.limit.isRepeatable), isTrue);
      expect(coin.routes.every((r) => r.location == 'Manage Currency'), isTrue);
      expect(coin.routes.every((r) => !r.directVendorSale), isTrue);
      expect(
        coin.routes.every((r) => r.sources.single.url.contains('10577')),
        isTrue,
      );
      expect(
        coin.notes.first,
        contains('Lafi Bedmountain, Storage Keeper at Angavu Outpost'),
      );
      expect(coin.notes.skip(1).take(6), [
        '85 Branch of Abundance',
        '80 Black Crystal Fragment',
        "70 Elion Follower's Helmet",
        '65 Scorched Belt Ornament',
        "65 Elion Follower's Mark",
        '60 Broken Gloves of the Void',
      ]);
    },
  );

  test('10 Divine Coins give one chosen material OR 100M untaxed gold', () {
    final quotes = evaluate(
      'divine-coin',
      owned: 10,
      market: OpportunityMarketSnapshot(
        region: 'eu',
        items: {
          for (final id in [821344, 821347, 821182])
            '$id': marketItem(id, price: 200000000, bids: []),
        },
      ),
    );
    expect(quotes, hasLength(4));
    for (final quote in quotes.take(3)) {
      expect(quote.exchanges, 1);
      expect(quote.rewardQuotes.single.quantity, 1);
      expect(quote.netProceeds, 169000000);
      expect(quote.valuePerCurrency, 16900000);
      expect(
        quote.isRankable,
        isTrue,
        reason: 'Listing value does not need preorders.',
      );
    }
    final gold = route(quotes, 'divine-gold');
    expect(gold.exchanges, 10);
    expect(gold.rewardQuotes.single.quantity, 10);
    expect(gold.rewardQuotes.single.vendorSale, isTrue);
    expect(gold.netProceeds, 100000000);
    expect(gold.valuePerCurrency, 10000000);
    expect(
      gold.gainOverVendor,
      isNull,
      reason: 'Coins are not free inputs or a silver profit.',
    );
    expect(
      route(
        evaluate('divine-coin', owned: 10, tax: 0),
        'divine-gold',
      ).netProceeds,
      100000000,
    );
  });

  test('Divine Coin uses whole balances and never invents material prices', () {
    for (final balance in [0, 1, 9, 10, 25]) {
      final quotes = evaluate('divine-coin', owned: balance);
      for (final quote in quotes.take(3)) {
        expect(quote.possibleExchanges, balance ~/ 10);
        expect(quote.netProceeds, isNull);
      }
      final gold = route(quotes, 'divine-gold');
      expect(gold.netProceeds, balance == 0 ? null : balance * 10000000);
      expect(gold.remainder, 0);
    }
    final quotes = evaluate(
      'divine-coin',
      owned: 25,
      market: OpportunityMarketSnapshot(
        region: 'eu',
        items: {
          for (final id in [821344, 821347, 821182]) '$id': marketItem(id),
        },
      ),
    );
    for (final quote in quotes.take(3)) {
      expect(quote.exchanges, 2);
      expect(quote.consumed, 20);
      expect(quote.remainder, 5);
      expect(quote.rewardQuotes.single.quantity, 2);
    }
  });

  test(
    'current common currencies keep exact IDs and whole exchange ratios',
    () {
      final expected = <String, (int, List<(int, int, int)>)>{
        'imperial-cuisine-seal': (
          1017,
          [
            (10000, 705037, 1),
            (10000, 16486, 1),
            (10000, 16487, 1),
            (500, 3743, 1),
            (400, 4992, 1),
            (200, 16181, 1),
            (100, 5861, 1),
            (50, 9065, 50),
            (50, 9064, 100),
          ],
        ),
        'imperial-alchemy-seal': (
          1018,
          [
            (5000, 705047, 1),
            (5000, 16482, 1),
            (5000, 16479, 1),
            (250, 4994, 1),
            (100, 3744, 1),
            (100, 5862, 1),
            (80, 16181, 1),
            (40, 4918, 1),
            (50, 5960, 50),
          ],
        ),
        'imperial-training-seal': (
          1020,
          [
            (100, 705015, 1),
            (100, 705156, 1),
            (50, 52506, 1),
            (50, 52606, 1),
            (50, 52706, 1),
            (50, 52906, 1),
            (50, 52806, 1),
            (40, 757032, 1),
            (40, 757030, 1),
            (15, 50018, 1),
            (12, 66191, 1),
            (12, 4993, 1),
            (5, 50006, 1),
            (2, 16069, 1),
            (2, 8071, 1),
            (1, 50802, 1),
            (1, 50803, 1),
          ],
        ),
        'imperial-fishing-seal': (
          1019,
          [
            (2000, 705052, 1),
            (250, 4995, 1),
            (250, 4988, 1),
            (70, 44164, 1),
            (50, 49717, 1),
            (50, 49718, 1),
            (50, 49719, 1),
            (50, 49720, 1),
            (40, 49705, 1),
            (40, 49706, 1),
            (40, 49707, 1),
            (40, 49708, 1),
            (25, 50809, 1),
          ],
        ),
        'atanis-element': (
          752530,
          [
            (1, 5205, 15),
            (1, 3, 1),
            (20, 50801, 1),
            (1, 40752, 1),
            (1, 40754, 1),
            (1, 40756, 1),
            (1, 40758, 1),
            (1, 40760, 1),
            (1, 40762, 1),
          ],
        ),
        'dark-spirits-greed': (
          767887,
          [
            (50, 17849, 1),
            (30, 15616, 1),
            (30, 15712, 1),
            (30, 15714, 1),
            (15, 40258, 1),
            (5, 4, 1),
            (2, 42435, 1),
            (1, 752023, 10),
            (1, 3, 2),
          ],
        ),
      };
      for (final entry in expected.entries) {
        final current = currency(entry.key);
        expect(current.item.id, entry.value.$1);
        expect(
          current.routes
              .where((r) => r.limit.isRepeatable)
              .map(
                (r) => (
                  r.inputCount,
                  r.rewards.single.item!.id,
                  r.rewards.single.quantity,
                ),
              ),
          entry.value.$2,
          reason: entry.key,
        );
      }
      expect(exchangeCatalog.map((c) => c.item.id), isNot(contains(721023)));
      for (final retired in [890061, 890062, 890064]) {
        expect(exchangeCatalog.map((c) => c.item.id), isNot(contains(retired)));
      }
    },
  );

  test('Fishing seal gear uses ordinary NPC silver, not Crow Coins', () {
    final quotes = evaluate('imperial-fishing-seal', owned: 2000, tax: 0);
    expect(route(quotes, 'fishing-seal-705052').netProceeds, isNull);
    expect(route(quotes, 'fishing-seal-4995').netProceeds, isNull);
    expect(route(quotes, 'fishing-seal-4988').netProceeds, isNull);
    for (final entry in const {
      49705: (40, 2500000),
      49706: (40, 2750000),
      49707: (40, 2500000),
      49708: (40, 2000000),
      49717: (50, 3750000),
      49718: (50, 4125000),
      49719: (50, 3750000),
      49720: (50, 3000000),
    }.entries) {
      final quote = route(quotes, 'fishing-seal-${entry.key}');
      expect(quote.rewardQuotes.single.vendorSale, isTrue);
      expect(quote.netProceeds, 2000 ~/ entry.value.$1 * entry.value.$2);
      expect(exchangeItems[entry.key]!.marketable, isFalse);
    }
  });

  test(
    'guaranteed boxes retain actual artwork and value only their contents',
    () {
      final trace = route(
        evaluate(
          'imperial-alchemy-seal',
          owned: 149,
          market: OpportunityMarketSnapshot(
            region: 'eu',
            items: {'5960': marketItem(5960, price: 1000)},
          ),
        ),
        'alchemy-seal-trace-box',
      );
      expect(trace.route.rewardContainer!.id, 8072);
      expect(trace.route.rewardContainer!.name, 'Imperial Trace Box');
      expect(trace.exchanges, 2);
      expect(trace.rewardQuotes.single.quantity, 100);
      expect(trace.rewardQuotes.single.reward.item!.id, 5960);
      expect(trace.netProceeds, 84500);
      expect(trace.remainder, 49);
      expect(trace.route.notes.single, contains('50 Trace of Nature'));
      expect(trace.route.rewardContainer!.vendorSellPrice, isNull);
    },
  );

  test(
    'Crow boxes use current weekly limits and never turn Crow resale into silver',
    () {
      final crow = currency('crow-coin');
      expect(crow.item.id, 10);
      expect(crow.routes, hasLength(5));
      expect(crow.routes.every((r) => !r.limit.isRepeatable), isTrue);
      final expected = {
        'crow-box-752066': (200, 752066, 721003, 20, 10),
        'crow-box-752068': (200, 752068, 44195, 20, 10),
        'crow-box-752067': (200, 752067, 16080, 20, 10),
        'crow-box-890054': (150, 890054, 756001, 20, 10),
      };
      for (final entry in expected.entries) {
        final actual = crow.routes.singleWhere((r) => r.id == entry.key);
        expect(actual.inputCount, entry.value.$1);
        expect(actual.rewardContainer!.id, entry.value.$2);
        expect(actual.rewards.single.item!.id, entry.value.$3);
        expect(actual.rewards.single.quantity, entry.value.$4);
        expect(actual.limit.maximum, entry.value.$5);
        expect(actual.rewardContainer!.vendorSellPrice, isNull);
      }
      final unchecked = evaluate('crow-coin', owned: 10000);
      expect(
        unchecked.every(
          (q) => q.availability == ExchangeAvailability.confirmationNeeded,
        ),
        isTrue,
      );
      final checked = evaluate(
        'crow-coin',
        owned: 10000,
        limits: {for (final r in crow.routes) r.id: 99},
      );
      for (final id in [
        'crow-box-752067',
        'crow-box-890054',
        'crow-blue-sea-box',
      ]) {
        final utility = route(checked, id);
        expect(utility.netProceeds, isNull);
        expect(utility.isRankable, isFalse);
      }
      expect(route(checked, 'crow-blue-sea-box').route.limit.maximum, 3);
      expect(exchangeItems[756001]!.vendorSellPrice, isNull);
    },
  );

  test(
    'Greed weekly and multi-use family allowances stay separately confirmed',
    () {
      final greed = currency('dark-spirits-greed');
      expect(greed.routes, hasLength(22));
      final weekly = {
        50801: (20, 1, 2),
        17572: (5, 1, 3),
        45162: (3, 2, 5),
        54031: (2, 10, 2),
        734: (15, 1, 2),
        3743: (10, 1, 2),
        3744: (10, 1, 2),
      };
      for (final entry in weekly.entries) {
        final r = greed.routes.singleWhere(
          (r) => r.id == 'greed-weekly-${entry.key}',
        );
        expect((
          r.inputCount,
          r.rewards.single.quantity,
          r.limit.maximum,
        ), entry.value);
        expect(r.limit.kind, ExchangeLimitKind.weekly);
      }
      final specter = route(
        evaluate(
          'dark-spirits-greed',
          owned: 999,
          limits: {'greed-family-721044': 99, 'greed-family-desperate': 99},
        ),
        'greed-family-721044',
      );
      expect(specter.route.limit.label, 'Up to 3 per family');
      expect(specter.exchanges, 3);
      expect(specter.netProceeds, 90000000);
      final desperate = route(
        evaluate(
          'dark-spirits-greed',
          owned: 999,
          limits: {'greed-family-desperate': 99},
        ),
        'greed-family-desperate',
      );
      expect(desperate.route.inputCount, 5);
      expect(desperate.route.limit.label, 'Up to 10 per family');
      expect(desperate.exchanges, 10);
      expect(desperate.netProceeds, 100000000);
      final vera = route(
        evaluate(
          'imperial-training-seal',
          owned: 100,
          limits: {'training-seal-vera': 1},
        ),
        'training-seal-vera',
      );
      expect(vera.availability, ExchangeAvailability.confirmationNeeded);
      expect(vera.netProceeds, isNull);
    },
  );

  test('random boxes, Black Essences and potion pity pieces stay unpriced', () {
    for (final id in [
      8071,
      16069,
      16181,
      4992,
      4993,
      4994,
      40752,
      40754,
      40756,
      40758,
      40760,
      40762,
    ]) {
      expect(exchangeItems[id]!.marketable, isFalse);
      expect(exchangeItems[id]!.vendorSellPrice, isNull);
    }
    final quotes = evaluate('imperial-training-seal', owned: 10000);
    for (final id in [
      'training-seal-8071',
      'training-seal-16069',
      'training-seal-4993',
    ]) {
      expect(route(quotes, id).netProceeds, isNull);
      expect(route(quotes, id).isRankable, isFalse);
    }
    final fang = currency('sea-monster-fang');
    expect(fang.item.id, 756056);
    expect(fang.item.vendorSellPrice, 300000);
    expect(
      fang.routes
          .where((r) => !r.directVendorSale)
          .map(
            (r) => (
              r.inputCount,
              r.rewards.single.item!.id,
              r.rewards.single.quantity,
            ),
          ),
      [(1, 9727, 1), (1, 9729, 1)],
    );
    expect(
      route(
        evaluate('sea-monster-fang', owned: 2),
        'sea-monster-fang-vendor',
      ).netProceeds,
      600000,
    );
  });

  test(
    'reference rates need no owned balance and use one exchange of real buyer depth',
    () {
      final current = currency('atanis-element');
      final market = OpportunityMarketSnapshot(
        region: 'eu',
        items: {
          '5205': marketItem(
            5205,
            price: 1000,
            bids: const [
              OpportunityMarketLevel(price: 1000, quantity: 15),
              OpportunityMarketLevel(price: 100, quantity: 30),
            ],
          ),
        },
      );
      final references = calculateExchangeReferenceOptions(
        currency: current,
        market: market,
        now: now,
        saleMode: ExchangeSaleMode.immediate,
        taxMultiplier: 1,
      );
      final reference = route(references, 'atanis-fruit');
      expect(reference.isReference, isTrue);
      expect(reference.currency, same(current));
      expect(reference.exchanges, 1);
      expect(reference.valuePerCurrency, 15000);
      final actual = route(
        evaluate(
          'atanis-element',
          owned: 3,
          market: market,
          mode: ExchangeSaleMode.immediate,
          tax: 1,
        ),
        'atanis-fruit',
      );
      expect(actual.isReference, isFalse);
      expect(actual.exchanges, 3);
      expect(actual.valuePerCurrency, 6000);
      expect(
        route(
          evaluate('atanis-element', owned: 0, market: market),
          'atanis-fruit',
        ).valuePerCurrency,
        isNull,
      );
      expect(current.routes, hasLength(9));
      final limited = calculateExchangeReferenceOptions(
        currency: currency('crow-coin'),
        market: empty,
        now: now,
        saleMode: ExchangeSaleMode.immediate,
        taxMultiplier: 1,
      );
      expect(
        limited.every(
          (q) => q.availability == ExchangeAvailability.confirmationNeeded,
        ),
        isTrue,
      );
      expect(limited.every((q) => q.netProceeds == null), isTrue);
    },
  );

  test(
    'all item artwork decodes and matches untouched client hashes',
    () async {
      final provenance =
          jsonDecode(
                File(
                  'assets/opportunities/icon-provenance.json',
                ).readAsStringSync(),
              )
              as Map<String, dynamic>;
      final icons = provenance['icons'] as List<dynamic>;
      expect(icons, hasLength(exchangeItems.length));
      for (final item in exchangeItems.values) {
        final record = icons.cast<Map<String, dynamic>>().singleWhere(
          (entry) => entry['id'] == item.id,
        );
        expect(record['asset'], item.iconAsset);
        final bytes = File(item.iconAsset).readAsBytesSync();
        expect(
          sha256.convert(bytes).toString().toUpperCase(),
          record['sha256'],
        );
        final codec = await ui.instantiateImageCodec(bytes);
        final decoded = (await codec.getNextFrame()).image;
        expect(decoded.width, greaterThanOrEqualTo(32), reason: item.name);
        expect(decoded.height, greaterThanOrEqualTo(32), reason: item.name);
        decoded.dispose();
        codec.dispose();
      }
    },
  );

  test('Sangpyeong repeatable and family routes never share limits', () {
    final coin = currency('sangpyeong');
    expect(coin.item.id, 66771);
    expect(
      coin.routes.where((route) => route.limit.isRepeatable),
      hasLength(12),
    );
    expect(
      coin.routes.where((route) => !route.limit.isRepeatable),
      hasLength(4),
    );
    final expected = {
      'sangpyeong-harmony': (2000, 820035, 1),
      'sangpyeong-girin': (1500, 15734, 1),
      'sangpyeong-bonghwang': (1500, 15729, 1),
      'sangpyeong-haetae': (1500, 15731, 1),
      'sangpyeong-forest': (1000, 820036, 1),
      'sangpyeong-live-meat': (500, 820139, 1),
      'sangpyeong-cooking-tool': (100, 3749, 1),
      'sangpyeong-maehwa': (50, 820141, 1),
      'sangpyeong-rice': (10, 820140, 1),
      'sangpyeong-alchemy-tool': (100, 3750, 1),
      'sangpyeong-herb': (10, 820143, 1),
      'sangpyeong-plywood': (10, 820893, 1),
      'sangpyeong-hongik': (500, 65267, 30),
    };
    for (final entry in expected.entries) {
      final actual = coin.routes.singleWhere((route) => route.id == entry.key);
      expect(actual.inputCount, entry.value.$1);
      expect(actual.rewards.single.item!.id, entry.value.$2);
      expect(actual.rewards.single.quantity, entry.value.$3);
    }
    final chest = currency('sangpyeong-chest');
    expect(chest.item.id, 66783);
    expect(chest.routes.single.inputCount, 2);
    expect(chest.routes.single.limit.kind, ExchangeLimitKind.oncePerFamily);
    expect(coin.routes.any((route) => route.id.contains('chest')), isFalse);
  });

  test('current Fairy does not inherit the Dormant Sharp exchange', () {
    final current = currency('fairys-breath');
    expect(current.item.id, 821371);
    expect(current.legacy, isFalse);
    expect(
      current.routes
          .where((r) => !r.directVendorSale)
          .expand((r) => r.rewards)
          .where((r) => r.item != null)
          .map((r) => (r.item!.id, r.quantity)),
      [(5439, 30), (4605, 20), (4006, 12), (5205, 1), (5960, 1)],
    );
    final dormant = currency('dormant-fairys-breath');
    expect(dormant.item.id, 820014);
    expect(dormant.legacy, isTrue);
    expect(dormant.routes.first.rewards.single.item!.id, 4998);
    expect(dormant.routes.first.rewards.single.quantity, 2);
  });

  test(
    'known byproduct ratios and utility are retained without farming yields',
    () {
      expect(currency('mysterious-catalyst').routes, hasLength(9));
      expect(currency('blush-leaf').routes.first.inputCount, 20);
      expect(currency('blush-leaf').routes[1].rewards.single.quantity, 1);
      expect(currency('discarded-bottle').routes[1].inputCount, 5);
      expect(
        currency('discarded-bottle').routes[1].rewards.single.quantity,
        15,
      );
      expect(currency('wildspark').routes[1].rewards.single.item!.id, 4999);
      expect(currency('wildspark').routes[1].rewards.single.quantity, 5);
      for (final id in [9780, 9781, 9795, 9796, 9799, 821371]) {
        expect(exchangeItems[id]!.vendorSellPrice, 20000);
        expect(exchangeItems[id]!.marketable, isFalse);
      }
    },
  );

  test(
    'listing alternatives use whole exchanges, tax and retained remainder',
    () {
      final quotes = evaluate(
        'witchs-delicacy',
        owned: 25,
        market: OpportunityMarketSnapshot(
          region: 'eu',
          items: {
            '9213': marketItem(9213, price: 1000),
            '9065': marketItem(9065),
          },
        ),
      );
      final milk = route(quotes, 'witchs-delicacy-milk');
      expect(milk.exchanges, 2);
      expect(milk.consumed, 20);
      expect(milk.remainder, 5);
      expect(milk.rewardQuotes.single.quantity, 240);
      expect(milk.netProceeds, closeTo(2028000, 0.001));
      expect(milk.valuePerCurrency, closeTo(101400, 0.001));
      expect(milk.gainOverVendor, closeTo(1628000, 0.001));
      expect(route(quotes, 'witchs-delicacy-beer').netProceeds, 845000);
      expect(
        rankExchangeOptions(quotes).first.route.id,
        'witchs-delicacy-milk',
      );
      expect(route(quotes, 'witchs-delicacy-exp').netProceeds, isNull);
      expect(route(quotes, 'witchs-delicacy-exp').rewardQuotes, hasLength(2));
      expect(route(quotes, 'witchs-delicacy-exp').isRankable, isFalse);
    },
  );

  test(
    'immediate sale uses top bid tiers and caps full exchanges by buyers',
    () {
      final quotes = evaluate(
        'witchs-delicacy',
        owned: 1000,
        mode: ExchangeSaleMode.immediate,
        market: OpportunityMarketSnapshot(
          region: 'eu',
          items: {
            '9065': marketItem(
              9065,
              price: 999999,
              bids: const [
                OpportunityMarketLevel(price: 8000, quantity: 100),
                OpportunityMarketLevel(price: 10000, quantity: 200),
              ],
            ),
          },
        ),
      );
      final milk = route(quotes, 'witchs-delicacy-milk');
      expect(milk.possibleExchanges, 100);
      expect(milk.exchanges, 2);
      expect(milk.remainder, 980);
      expect(milk.netProceeds, closeTo((200 * 10000 + 40 * 8000) * .845, .001));
      expect(milk.rewardQuotes.single.remainingQuantity, 0);
    },
  );

  test(
    'known inadequate bids do not become stock, vendor sales or base-price income',
    () {
      final quotes = evaluate(
        'witchs-delicacy',
        mode: ExchangeSaleMode.immediate,
        market: OpportunityMarketSnapshot(
          region: 'eu',
          items: {
            '9065': marketItem(
              9065,
              bids: const [OpportunityMarketLevel(price: 10000, quantity: 119)],
            ),
            '9213': marketItem(9213, bids: const []),
          },
        ),
      );
      for (final id in ['witchs-delicacy-milk', 'witchs-delicacy-beer']) {
        final quote = route(quotes, id);
        expect(quote.availability, ExchangeAvailability.notEnoughBuyers);
        expect(quote.exchanges, 0);
        expect(quote.remainder, 100);
        expect(quote.netProceeds, isNull);
        expect(quote.rewardQuotes.single.vendorSale, isFalse);
      }
    },
  );

  test(
    'missing, stale, future, unlisted and wrong-ID evidence remains unknown',
    () {
      final cases = <OpportunityMarketItem?>[
        null,
        marketItem(9065, bids: null),
        marketItem(9065, fetchedAt: now.subtract(const Duration(minutes: 16))),
        marketItem(9065, fetchedAt: now.add(const Duration(seconds: 1))),
        marketItem(9065, unlisted: true),
        marketItem(9065, returnedId: '4998'),
        marketItem(9065, subId: 1),
        marketItem(
          9065,
          bids: const [OpportunityMarketLevel(price: -1, quantity: 10)],
        ),
      ];
      for (final item in cases) {
        final quotes = evaluate(
          'witchs-delicacy',
          mode: ExchangeSaleMode.immediate,
          market: OpportunityMarketSnapshot(
            region: 'eu',
            items: item == null ? {} : {'9065': item},
          ),
        );
        final milk = route(quotes, 'witchs-delicacy-milk');
        expect(milk.availability, ExchangeAvailability.marketUnknown);
        expect(milk.isRankable, isFalse);
        expect(milk.netProceeds, isNull);
      }
    },
  );

  test('fresh quote cannot refresh an old order book', () {
    final quote =
        marketItem(
          9065,
          fetchedAt: now.subtract(const Duration(hours: 1)),
        ).mergeFrom(
          OpportunityMarketItem(
            itemId: '9065',
            basePrice: 10000,
            stock: 1000,
            quoteFetchedAt: now,
          ),
        );
    final market = OpportunityMarketSnapshot(
      region: 'eu',
      items: {'9065': quote},
    );
    expect(
      route(
        evaluate('witchs-delicacy', market: market),
        'witchs-delicacy-milk',
      ).isRankable,
      isTrue,
    );
    expect(
      route(
        evaluate(
          'witchs-delicacy',
          market: market,
          mode: ExchangeSaleMode.immediate,
        ),
        'witchs-delicacy-milk',
      ).availability,
      ExchangeAvailability.marketUnknown,
    );
  });

  test('NPC sale is verified sell payout with no Marketplace tax', () {
    final gold = route(
      evaluate('morning-light-boss-token', owned: 3, tax: 0),
      'morning-token-gold',
    );
    expect(gold.netProceeds, 30000000);
    expect(gold.rewardQuotes.single.vendorSale, isTrue);
    final harmony = route(
      evaluate('sangpyeong', owned: 2000, tax: 0),
      'sangpyeong-harmony',
    );
    expect(harmony.netProceeds, 50000);
    expect(exchangeItems[820035]!.marketable, isFalse);
    final raw = route(
      evaluate('witchs-delicacy', owned: 25, tax: 0),
      'witchs-delicacy-vendor',
    );
    expect(raw.netProceeds, 500000);
    expect(raw.gainOverVendor, 0);
  });

  test('bound useful rewards remain visible and unpriced, not zero silver', () {
    final meat = route(
      evaluate('sangpyeong', owned: 500),
      'sangpyeong-live-meat',
    );
    expect(meat.exchanges, 1);
    expect(meat.rewardQuotes.single.quantity, 1);
    expect(meat.netProceeds, isNull);
    expect(meat.hasUnpricedRewards, isTrue);
    expect(meat.isRankable, isFalse);
  });

  test('weekly and family limits require confirmation and cap separately', () {
    final unknown = evaluate('morning-light-boss-token', owned: 10);
    final ember = route(unknown, 'morning-token-ember');
    expect(ember.availability, ExchangeAvailability.confirmationNeeded);
    expect(ember.exchanges, 0);
    expect(rankExchangeOptions(unknown).map((q) => q.route.id), [
      'morning-token-gold',
    ]);
    final confirmed = evaluate(
      'morning-light-boss-token',
      owned: 10,
      limits: {'morning-token-ember': 99, 'morning-token-crystal': 0},
    );
    expect(route(confirmed, 'morning-token-ember').exchanges, 4);
    expect(route(confirmed, 'morning-token-ember').remainder, 6);
    expect(
      route(confirmed, 'morning-token-crystal').availability,
      ExchangeAvailability.limitReached,
    );
    expect(
      rankExchangeOptions(
        confirmed,
      ).any((q) => q.route.id == 'morning-token-ember'),
      isFalse,
    );
    final family = route(
      evaluate('sangpyeong', owned: 5000, limits: {'sangpyeong-hongik': 20}),
      'sangpyeong-hongik',
    );
    expect(family.exchanges, 1);
    expect(family.netProceeds, 30000000);
  });

  test(
    'Laila prerequisites and random contents never produce imagined income',
    () {
      final initial = route(evaluate('lailas-petal', owned: 10), 'laila-wings');
      expect(initial.availability, ExchangeAvailability.confirmationNeeded);
      final confirmed = route(
        evaluate('lailas-petal', owned: 10, requirements: {'laila-wings'}),
        'laila-wings',
      );
      expect(confirmed.netProceeds, 5000000);
      expect(confirmed.rewardQuotes.single.reward.item!.id, 54033);
      expect(confirmed.rewardQuotes.single.quantity, 5);
      expect(confirmed.rewardQuotes.single.vendorSale, isTrue);
      expect(confirmed.gainOverVendor, 0);
    },
  );

  test('zero owned is not a pretend one-exchange balance', () {
    final quotes = evaluate('witchs-delicacy', owned: 0);
    expect(quotes.every((quote) => quote.exchanges == 0), isTrue);
    expect(quotes.every((quote) => quote.valuePerCurrency == null), isTrue);
    expect(rankExchangeOptions(quotes), isEmpty);
  });

  test('invalid counts and non-finite tax are rejected without coercion', () {
    expect(() => evaluate('witchs-delicacy', owned: -1), throwsArgumentError);
    for (final tax in [double.nan, double.infinity, -0.1, 1.1]) {
      expect(() => evaluate('witchs-delicacy', tax: tax), throwsArgumentError);
    }
  });
}
