import 'dart:io';

import 'package:bdo_craft_planner_flutter/data/opportunities/opportunity_market_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// Optional read-only contract check. Never runs in the deterministic suite.
void main() {
  test(
    'official EU quote and binary depth contract',
    () async {
      final service = OpportunityMarketService();
      addTearDown(service.close);
      final quotes = await service.fetchQuotes(['4998', '50804']);
      expect(quotes.failures, isEmpty);
      final books = await service.fetchOrderBooks(['4998', '50804']);
      expect(books.failures, isEmpty);
      for (final id in ['4998', '50804']) {
        final item = quotes.items[id]!.mergeFrom(books.items[id]!);
        expect(item.basePrice, greaterThan(0));
        expect(item.totalTrades, greaterThanOrEqualTo(0));
        expect(item.asks, isNotNull);
        expect(item.bids, isNotNull);
        expect(item.quoteFetchedAt, isNotNull);
        expect(item.bookFetchedAt, isNotNull);
        // A contract capture, not a fixture used in calculations.
        // ignore: avoid_print
        print(
          '$id ${item.quoteFetchedAt!.toIso8601String()} '
          'price=${item.basePrice} stock=${item.stock} '
          'orders=${item.preorderCount} asks=${item.asks!.length} '
          'bids=${item.bids!.length} trades=${item.totalTrades}',
        );
      }
    },
    skip: Platform.environment['OPPORTUNITY_MARKET_LIVE_TEST'] != '1',
  );
}
