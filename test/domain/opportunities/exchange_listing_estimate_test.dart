import 'package:bdo_craft_planner_flutter/domain/opportunities/exchange_calculator.dart';
import 'package:bdo_craft_planner_flutter/domain/opportunities/exchange_models.dart';
import 'package:bdo_craft_planner_flutter/domain/opportunities/opportunity_market_models.dart';
import 'package:flutter_test/flutter_test.dart';

final _now = DateTime.utc(2026, 9, 9, 2);
const _currencyItem = ExchangeItem(id: 1, name: 'Coin', iconAsset: 'coin.webp');
const _crystal = ExchangeItem(
  id: 2,
  name: 'Crystal',
  iconAsset: 'crystal.webp',
  marketable: true,
);
const _route = ExchangeRoute(
  id: 'crystal',
  inputCount: 10,
  rewards: [ExchangeReward.item(_crystal, quantity: 2)],
  location: 'NPC',
);

OpportunityMarketItem _market({
  int price = 100,
  List<OpportunityMarketLevel>? bids = const [],
  DateTime? quoteAt,
  DateTime? bookAt,
  bool unlisted = false,
}) => OpportunityMarketItem(
  itemId: '2',
  basePrice: price,
  stock: 100,
  quoteFetchedAt: quoteAt ?? _now,
  asks: const [OpportunityMarketLevel(price: 100, quantity: 100)],
  bids: bids,
  bookFetchedAt: bookAt ?? _now,
  unlisted: unlisted,
);

ExchangeQuote _calculate({
  OpportunityMarketItem? market,
  int owned = 25,
  double tax = .845,
  ExchangeRoute route = _route,
  Map<String, int> limits = const {},
  Set<String> requirements = const {},
  bool reference = false,
}) {
  final currency = ExchangeCurrency(
    id: 'coin',
    item: _currencyItem,
    sourceActivity: 'Example',
    routes: [route],
  );
  final snapshot = OpportunityMarketSnapshot(
    region: 'eu',
    items: {'2': market ?? _market()},
  );
  return reference
      ? calculateExchangeReferenceOptions(
          currency: currency,
          market: snapshot,
          now: _now,
          saleMode: ExchangeSaleMode.immediate,
          taxMultiplier: tax,
          remainingLimitedExchanges: limits,
          confirmedRequirementRoutes: requirements,
        ).single
      : calculateExchangeOptions(
          currency: currency,
          owned: owned,
          market: snapshot,
          now: _now,
          saleMode: ExchangeSaleMode.immediate,
          taxMultiplier: tax,
          remainingLimitedExchanges: limits,
          confirmedRequirementRoutes: requirements,
        ).single;
}

void main() {
  test('known no buyers shows a separate taxed listing estimate', () {
    final quote = _calculate();
    expect(quote.availability, ExchangeAvailability.notEnoughBuyers);
    expect(quote.exchanges, 0);
    expect(quote.consumed, 0);
    expect(quote.netProceeds, isNull);
    expect(quote.valuePerCurrency, isNull);
    expect(quote.isRankable, isFalse);
    expect(quote.rewardQuotes.single.soldQuantity, 0);
    expect(quote.hasListingEstimate, isTrue);
    final display = quote.displayQuote;
    expect(display.saleMode, ExchangeSaleMode.listing);
    expect(display.exchanges, 2);
    expect(display.consumed, 20);
    expect(display.remainder, 5);
    expect(display.netProceeds, closeTo(338, .000001));
    expect(display.valuePerCurrency, closeTo(16.9, .000001));
    expect(display.rewardQuotes.single.quantity, 4);
    expect(display.hasListingEstimate, isFalse);
  });

  test('partial buyer fills stay distinct from full listing estimate', () {
    final quote = _calculate(
      market: _market(
        bids: const [OpportunityMarketLevel(price: 80, quantity: 3)],
      ),
    );
    expect(quote.availability, ExchangeAvailability.available);
    expect(quote.exchanges, 1); // two crystals: cannot exchange half a batch.
    expect(quote.netProceeds, closeTo(135.2, .000001));
    expect(quote.rewardQuotes.single.quantity, 2);
    expect(quote.hasListingEstimate, isTrue);
    expect(quote.displayQuote.exchanges, 2);
    expect(quote.displayQuote.netProceeds, closeTo(338, .000001));
  });

  test('fully covered bids retain their exact proceeds with no fallback', () {
    final quote = _calculate(
      market: _market(
        bids: const [OpportunityMarketLevel(price: 80, quantity: 10)],
      ),
    );
    expect(quote.hasListingEstimate, isFalse);
    expect(identical(quote.displayQuote, quote), isTrue);
    expect(quote.netProceeds, closeTo(270.4, .000001));
  });

  test('listing estimate uses supplied sale tax, including ring and fame', () {
    final quote = _calculate(tax: .8775);
    expect(quote.displayQuote.netProceeds, 351);
  });

  test(
    'unknown stale future and unlisted evidence never gains an estimate',
    () {
      final old = _now.subtract(const Duration(minutes: 16));
      final future = _now.add(const Duration(seconds: 1));
      for (final item in [
        _market(bids: null),
        _market(bookAt: old),
        _market(quoteAt: old),
        _market(bookAt: future),
        _market(quoteAt: future),
        _market(price: 0),
        _market(unlisted: true),
        _market(bids: const [OpportunityMarketLevel(price: -1, quantity: 1)]),
      ]) {
        final quote = _calculate(market: item);
        expect(quote.hasListingEstimate, isFalse);
        expect(quote.netProceeds, isNull);
      }
    },
  );

  test(
    'reference comparison estimates one exchange without inventing owned funds',
    () {
      final quote = _calculate(reference: true);
      expect(quote.isReference, isTrue);
      expect(quote.displayQuote.isReference, isTrue);
      expect(quote.owned, 10);
      expect(quote.displayQuote.exchanges, 1);
      expect(quote.displayQuote.netProceeds, closeTo(169, .000001));
    },
  );

  test('no currency or unconfirmed limits/requirements never gets valued', () {
    expect(_calculate(owned: 0).hasListingEstimate, isFalse);
    expect(_calculate(owned: 9).hasListingEstimate, isFalse);
    const limited = ExchangeRoute(
      id: 'limited',
      inputCount: 10,
      rewards: [ExchangeReward.item(_crystal, quantity: 2)],
      location: 'NPC',
      limit: ExchangeLimit.weekly(1),
    );
    expect(_calculate(route: limited).hasListingEstimate, isFalse);
    expect(
      _calculate(route: limited, limits: {'limited': 0}).hasListingEstimate,
      isFalse,
    );
    const required = ExchangeRoute(
      id: 'required',
      inputCount: 10,
      rewards: [ExchangeReward.item(_crystal, quantity: 2)],
      location: 'NPC',
      requirements: ['Quest'],
    );
    expect(_calculate(route: required).hasListingEstimate, isFalse);
    final confirmed = _calculate(route: required, requirements: {'required'});
    expect(confirmed.hasListingEstimate, isTrue);
  });

  test(
    'confirmed limits constrain estimate and do not imply missing buyers',
    () {
      const limited = ExchangeRoute(
        id: 'limited',
        inputCount: 10,
        rewards: [ExchangeReward.item(_crystal, quantity: 2)],
        location: 'NPC',
        limit: ExchangeLimit.weekly(1),
      );
      final estimate = _calculate(
        route: limited,
        owned: 100,
        limits: {'limited': 1},
      );
      expect(estimate.displayQuote.exchanges, 1);
      expect(estimate.displayQuote.netProceeds, closeTo(169, .000001));
      final covered = _calculate(
        route: limited,
        owned: 100,
        limits: {'limited': 1},
        market: _market(
          bids: const [OpportunityMarketLevel(price: 80, quantity: 2)],
        ),
      );
      expect(covered.exchanges, 1);
      expect(covered.hasListingEstimate, isFalse);
    },
  );

  test('NPC proceeds are never market-taxed or estimated', () {
    const npc = ExchangeItem(
      id: 3,
      name: 'Gold',
      iconAsset: 'gold.webp',
      vendorSellPrice: 100,
    );
    const vendorRoute = ExchangeRoute(
      id: 'gold',
      inputCount: 10,
      rewards: [ExchangeReward.item(npc)],
      location: 'NPC',
    );
    final quote = _calculate(route: vendorRoute, tax: .1);
    expect(quote.netProceeds, 200);
    expect(quote.hasListingEstimate, isFalse);
    expect(quote.rewardQuotes.single.vendorSale, isTrue);
  });

  test(
    'unpriced utility mixed with market rewards never becomes full value',
    () {
      const utilityRoute = ExchangeRoute(
        id: 'mixed',
        inputCount: 10,
        rewards: [ExchangeReward.item(_crystal), ExchangeReward.utility('EXP')],
        location: 'NPC',
      );
      final quote = _calculate(route: utilityRoute);
      expect(quote.netProceeds, isNull);
      expect(quote.listingEstimate, isNull);
    },
  );
}
