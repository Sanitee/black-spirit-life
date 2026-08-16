import 'package:bdo_craft_planner_flutter/domain/market/market_price_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('market request normalization', () {
    test('keeps positive IDs as strings and reports every skipped request', () {
      const hugeId = '1234567890123456789012345678901234567890';
      final result = normalizeMarketPriceRequests(const <MarketPriceRequest>[
        MarketPriceRequest(name: '  First  ', id: '00042'),
        MarketPriceRequest(name: 'Duplicate', id: '42'),
        MarketPriceRequest(name: 'Huge', id: hugeId),
        MarketPriceRequest(name: 'Blank id', id: '  '),
        MarketPriceRequest(name: 'Zero', id: '000'),
        MarketPriceRequest(name: 'Nonnumeric', id: '4.2'),
        MarketPriceRequest(name: '  ', id: '99'),
        MarketPriceRequest(name: 'Truncated', id: '100'),
      ], maximumRequests: 2);

      expect(result.requests.map((request) => request.id), <String>[
        '42',
        hugeId,
      ]);
      expect(result.requests.first.name, 'First');
      expect(result.invalidCount, 4);
      expect(result.duplicateCount, 1);
      expect(result.truncatedCount, 1);
    });

    test('does not coerce a very large numeric-looking ID', () {
      const id = '999999999999999999999999999999999999999999999';
      expect(normalizeNumericMarketId(id), id);
    });
  });
}
