import 'dart:math' as math;

import 'exchange_models.dart';
import 'opportunity_market_models.dart';

/// Price one whole exchange per alternative, without requiring or changing an
/// owned balance. The returned basis quantity is not user inventory. Limited
/// routes and quest requirements still need the same explicit confirmations.
List<ExchangeQuote> calculateExchangeReferenceOptions({
  required ExchangeCurrency currency,
  required OpportunityMarketSnapshot market,
  required DateTime now,
  required ExchangeSaleMode saleMode,
  required double taxMultiplier,
  Duration maxMarketAge = const Duration(minutes: 15),
  Map<String, int> remainingLimitedExchanges = const {},
  Set<String> confirmedRequirementRoutes = const {},
}) => List.unmodifiable(
  currency.routes.map((route) {
    final quote = calculateExchangeOptions(
      currency: ExchangeCurrency(
        id: currency.id,
        item: currency.item,
        sourceActivity: currency.sourceActivity,
        routes: [route],
        notes: currency.notes,
        sources: currency.sources,
        legacy: currency.legacy,
      ),
      owned: route.inputCount,
      market: market,
      now: now,
      saleMode: saleMode,
      taxMultiplier: taxMultiplier,
      maxMarketAge: maxMarketAge,
      remainingLimitedExchanges: remainingLimitedExchanges,
      confirmedRequirementRoutes: confirmedRequirementRoutes,
    ).single;
    return ExchangeQuote(
      currency: currency,
      route: route,
      owned: quote.owned,
      possibleExchanges: quote.possibleExchanges,
      exchanges: quote.exchanges,
      rewardQuotes: quote.rewardQuotes,
      availability: quote.availability,
      netProceeds: quote.netProceeds,
      saleMode: quote.saleMode,
      isReference: true,
      listingEstimate: quote.listingEstimate == null
          ? null
          : _referenceQuote(quote.listingEstimate!, currency),
    );
  }),
);

/// Evaluate each alternative independently. This never spends currency,
/// modifies inventory, places orders or adds alternative rewards together.
List<ExchangeQuote> calculateExchangeOptions({
  required ExchangeCurrency currency,
  required int owned,
  required OpportunityMarketSnapshot market,
  required DateTime now,
  required ExchangeSaleMode saleMode,
  required double taxMultiplier,
  Duration maxMarketAge = const Duration(minutes: 15),
  Map<String, int> remainingLimitedExchanges = const {},
  Set<String> confirmedRequirementRoutes = const {},
}) {
  if (owned < 0) {
    throw ArgumentError.value(owned, 'owned', 'Must be nonnegative');
  }
  if (!taxMultiplier.isFinite || taxMultiplier < 0 || taxMultiplier > 1) {
    throw ArgumentError.value(taxMultiplier, 'taxMultiplier');
  }
  if (maxMarketAge.isNegative) {
    throw ArgumentError.value(maxMarketAge, 'maxMarketAge');
  }

  return List.unmodifiable(
    currency.routes.map((route) {
      if (route.inputCount <= 0 ||
          route.rewards.isEmpty ||
          route.rewards.any((reward) => reward.quantity <= 0)) {
        throw ArgumentError('Exchange ${route.id} has invalid quantities');
      }
      final possible = owned ~/ route.inputCount;
      var exchanges = possible;
      var availability = ExchangeAvailability.available;

      if (!route.limit.isRepeatable) {
        final remaining = remainingLimitedExchanges[route.id];
        if (remaining == null) {
          exchanges = 0;
          availability = ExchangeAvailability.confirmationNeeded;
        } else if (remaining <= 0) {
          exchanges = 0;
          availability = ExchangeAvailability.limitReached;
        } else {
          exchanges = math.min(
            exchanges,
            math.min(remaining, route.limit.maximum!),
          );
        }
      }
      if (route.requirements.isNotEmpty &&
          !confirmedRequirementRoutes.contains(route.id)) {
        exchanges = 0;
        availability = ExchangeAvailability.confirmationNeeded;
      }
      if (availability == ExchangeAvailability.available && possible == 0) {
        availability = ExchangeAvailability.notEnoughCurrency;
      }
      final eligibleExchanges = exchanges;

      // Aggregate equal outputs before checking depth so duplicate rows cannot
      // reuse the same buyers. Utility and NPC-only items need no market book.
      final marketQuantities = <int, int>{};
      if (!route.directVendorSale) {
        for (final reward in route.rewards) {
          final item = reward.item;
          if (item != null && item.marketable) {
            marketQuantities.update(
              item.id,
              (value) => value + reward.quantity,
              ifAbsent: () => reward.quantity,
            );
          }
        }
      }
      if (availability == ExchangeAvailability.available) {
        for (final entry in marketQuantities.entries) {
          final quote = market.items[entry.key.toString()];
          final validIdentity =
              quote != null &&
              quote.itemId == entry.key.toString() &&
              quote.subId == 0 &&
              !quote.unlisted;
          final fresh =
              validIdentity &&
              (saleMode == ExchangeSaleMode.immediate
                  ? quote.bookIsFresh(now, maxMarketAge)
                  : quote.quoteIsFresh(now, maxMarketAge));
          final validBook =
              saleMode != ExchangeSaleMode.immediate ||
              (fresh &&
                  quote.bids!.every(
                    (level) => level.price > 0 && level.quantity >= 0,
                  ));
          if (!fresh || !validBook) {
            exchanges = 0;
            availability = ExchangeAvailability.marketUnknown;
            break;
          }
          if (saleMode == ExchangeSaleMode.immediate) {
            final capacity = quote.bids!.fold<int>(
              0,
              (sum, level) => sum + level.quantity,
            );
            exchanges = math.min(exchanges, capacity ~/ entry.value);
          }
        }
        if (exchanges == 0 &&
            availability == ExchangeAvailability.available &&
            possible > 0) {
          availability = ExchangeAvailability.notEnoughBuyers;
        }
      }

      final totalsByItem = <int, double>{};
      if (exchanges > 0) {
        for (final entry in marketQuantities.entries) {
          final quote = market.items[entry.key.toString()]!;
          final quantity = exchanges * entry.value;
          final gross = saleMode == ExchangeSaleMode.immediate
              ? fillMarketDepth(
                  levels: quote.bids!,
                  quantity: quantity,
                  buying: false,
                ).totalSilver
              : quote.basePrice! * quantity;
          totalsByItem[entry.key] = gross * taxMultiplier;
        }
      }

      final rewardQuotes = <ExchangeRewardQuote>[];
      for (final reward in route.rewards) {
        final quantity = exchanges * reward.quantity;
        final item = reward.item;
        double? proceeds;
        var vendorSale = false;
        if (exchanges > 0) {
          if (route.directVendorSale) {
            final price = currency.item.vendorSellPrice;
            if (price != null && price > 0) {
              proceeds = (exchanges * route.inputCount * price).toDouble();
              vendorSale = true;
            }
          } else if (item != null && item.marketable) {
            proceeds =
                totalsByItem[item.id]! *
                reward.quantity /
                marketQuantities[item.id]!;
          } else if (item?.vendorSellPrice != null &&
              item!.vendorSellPrice! > 0) {
            proceeds = (quantity * item.vendorSellPrice!).toDouble();
            vendorSale = true;
          }
        }
        rewardQuotes.add(
          ExchangeRewardQuote(
            reward: reward,
            quantity: quantity,
            netProceeds: proceeds,
            soldQuantity: proceeds == null ? 0 : quantity,
            vendorSale: vendorSale,
          ),
        );
      }
      final allPriced = rewardQuotes.every(
        (reward) => reward.netProceeds != null,
      );
      final total = allPriced && exchanges > 0
          ? rewardQuotes.fold<double>(
              0,
              (sum, reward) => sum + reward.netProceeds!,
            )
          : null;
      ExchangeQuote? listingEstimate;
      if (saleMode == ExchangeSaleMode.immediate &&
          eligibleExchanges > exchanges &&
          (availability == ExchangeAvailability.available ||
              availability == ExchangeAvailability.notEnoughBuyers)) {
        final listing = calculateExchangeOptions(
          currency: ExchangeCurrency(
            id: currency.id,
            item: currency.item,
            sourceActivity: currency.sourceActivity,
            routes: [route],
            notes: currency.notes,
            sources: currency.sources,
            legacy: currency.legacy,
          ),
          owned: owned,
          market: market,
          now: now,
          saleMode: ExchangeSaleMode.listing,
          taxMultiplier: taxMultiplier,
          maxMarketAge: maxMarketAge,
          remainingLimitedExchanges: remainingLimitedExchanges,
          confirmedRequirementRoutes: confirmedRequirementRoutes,
        ).single;
        if (listing.isRankable) listingEstimate = listing;
      }
      return ExchangeQuote(
        currency: currency,
        route: route,
        owned: owned,
        possibleExchanges: possible,
        exchanges: exchanges,
        rewardQuotes: List.unmodifiable(rewardQuotes),
        availability: availability,
        netProceeds: total,
        saleMode: saleMode,
        listingEstimate: listingEstimate,
      );
    }),
  );
}

ExchangeQuote _referenceQuote(ExchangeQuote quote, ExchangeCurrency currency) =>
    ExchangeQuote(
      currency: currency,
      route: quote.route,
      owned: quote.owned,
      possibleExchanges: quote.possibleExchanges,
      exchanges: quote.exchanges,
      rewardQuotes: quote.rewardQuotes,
      availability: quote.availability,
      netProceeds: quote.netProceeds,
      saleMode: quote.saleMode,
      isReference: true,
    );

/// Only comparable, fully valued alternatives enter a silver ranking. Limited
/// routes are kept separate from ordinary repeatable opportunities by default.
List<ExchangeQuote> rankExchangeOptions(
  Iterable<ExchangeQuote> quotes, {
  bool includeLimited = false,
}) =>
    quotes
        .where(
          (quote) =>
              quote.isRankable &&
              (includeLimited || quote.route.limit.isRepeatable),
        )
        .toList()
      ..sort((a, b) {
        final value = b.valuePerCurrency!.compareTo(a.valuePerCurrency!);
        return value != 0 ? value : a.route.id.compareTo(b.route.id);
      });
