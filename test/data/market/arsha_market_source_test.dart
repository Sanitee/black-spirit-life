import 'dart:convert';

import 'package:bdo_craft_planner_flutter/data/market/arsha_market_source.dart';
import 'package:bdo_craft_planner_flutter/data/market/market_http_transport.dart';
import 'package:bdo_craft_planner_flutter/data/market/market_service_configuration.dart';
import 'package:bdo_craft_planner_flutter/domain/market/market_price_models.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/recording_market_http_transport.dart';

void main() {
  final fixedTime = DateTime.utc(2026, 7, 29, 10);

  group('ArshaMarketSource market evidence', () {
    test(
      'batch keeps listed stock and never treats cumulative trades as stock',
      () async {
        final transport = RecordingMarketHttpTransport((request) async {
          expect(request.uri.path, '/v2/eu/GetWorldMarketSubList');
          return MarketHttpResponse(
            statusCode: 200,
            body: jsonEncode(<Object?>[
              <String, Object?>{
                'id': 1,
                'basePrice': 100,
                'amountListed': 7,
                'totalTrades': 9001,
                'totalTradeCount': 9002,
                'lastSoldTime': 1785346251,
              },
              <String, Object?>{
                'id': 2,
                'basePrice': 200,
                'totalTrades': 8001,
                'totalTradeCount': 8002,
              },
              <String, Object?>{
                'id': 3,
                'basePrice': 300,
                'currentStock': 6,
                'totalTrades': 7001,
              },
              <String, Object?>{
                'id': 4,
                'basePrice': 400,
                'stock': 5,
                'totalTradeCount': 6001,
              },
            ]),
          );
        });
        final source = _source(transport, fixedTime);

        final rows = await source.fetchBatch(_requests(4));

        expect(rows.map((row) => row.stock), <int?>[7, null, 6, 5]);
        expect(rows.map((row) => row.totalTrades), <int?>[
          9001,
          8001,
          7001,
          6001,
        ]);
        expect(rows.map((row) => row.lastSoldAtEpochSeconds), <int?>[
          1785346251,
          null,
          null,
          null,
        ]);
      },
    );

    test(
      'single keeps listed count and ignores trade counts when alone',
      () async {
        final transport = RecordingMarketHttpTransport((request) async {
          expect(request.uri.path, '/v1/eu/price');
          final id = request.headers['id']!;
          final payload = switch (id) {
            '1' => <String, Object?>{
              'mainKey': id,
              'minPrice': 100,
              'count': 4,
              'totalTrades': 9001,
              'totalTradeCount': 9002,
              'lastSoldTime': 1785346251,
            },
            '2' => <String, Object?>{
              'mainKey': id,
              'minPrice': 200,
              'totalTrades': 8001,
              'totalTradeCount': 8002,
            },
            _ => <String, Object?>{
              'mainKey': id,
              'minPrice': 300,
              'amountListed': 3,
              'totalTradeCount': 7001,
            },
          };
          return MarketHttpResponse(
            statusCode: 200,
            body: jsonEncode(<Object?>[payload]),
          );
        });
        final source = _source(transport, fixedTime);

        final rows = await source.fetchSingles(_requests(3));

        expect(rows.map((row) => row.stock), <int?>[4, null, 3]);
        expect(rows.map((row) => row.totalTrades), <int?>[9001, 8001, 7001]);
        expect(rows.first.lastSoldAtEpochSeconds, 1785346251);
      },
    );
  });
}

ArshaMarketSource _source(
  RecordingMarketHttpTransport transport,
  DateTime fixedTime,
) => ArshaMarketSource(
  executor: MarketHttpExecutor(transport),
  configuration: const MarketServiceConfiguration(),
  clock: () => fixedTime,
  delay: (duration, cancellationToken) async {},
);

List<MarketPriceRequest> _requests(int count) =>
    List<MarketPriceRequest>.generate(
      count,
      (index) =>
          MarketPriceRequest(name: 'Item ${index + 1}', id: '${index + 1}'),
      growable: false,
    );
