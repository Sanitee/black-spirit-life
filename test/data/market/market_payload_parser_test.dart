import 'dart:convert';

import 'package:bdo_craft_planner_flutter/data/market/market_payload_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('MarketPayloadParser', () {
    test('parses the Pearl Abyss delimited result payload', () {
      final parsed = MarketPayloadParser.parsePearlAbyssItem(
        jsonEncode(<String, Object?>{
          'resultMsg': '41-0-0-100-2|42-0-0-123456-0|',
        }),
        '00042',
      );

      expect(parsed, isNotNull);
      expect(parsed!.id, '42');
      expect(parsed.price, 123456);
      expect(parsed.stock, 0);
      expect(parsed.totalTrades, isNull);
      expect(parsed.lastSoldAtEpochSeconds, isNull);
    });

    test('flattens nested arrays, wrappers, and JSON resultMsg strings', () {
      final nested = jsonEncode(<Object?>[
        <String, Object?>{
          'data': <Object?>[
            <String, Object?>{
              'id': '101',
              'basePrice': '2500.9',
              'currentStock': '12',
              'name': 'One',
            },
          ],
        },
        <String, Object?>{
          'payload': <String, Object?>{
            'rows': <Object?>[
              <String, Object?>{
                'mainKey': 102,
                'lastSoldPrice': 3000,
                'stock': 0,
                'name': 'Two',
                'totalTradeCount': '9876',
                'lastSoldTime': '1785346251',
              },
            ],
          },
        },
      ]);
      final body = jsonEncode(<String, Object?>{'resultMsg': nested});

      final parsed = MarketPayloadParser.parseArshaItems(body);

      expect(parsed, hasLength(2));
      expect(parsed[0].id, '101');
      expect(parsed[0].price, 2500);
      expect(parsed[0].stock, 12);
      expect(parsed[1].id, '102');
      expect(parsed[1].price, 3000);
      expect(parsed[1].stock, 0);
      expect(parsed[1].totalTrades, 9876);
      expect(parsed[1].lastSoldAtEpochSeconds, 1785346251);
    });

    test('retains unknown stock as null', () {
      final parsed = MarketPayloadParser.parseArshaItems(
        '[{"id":"55","price":"900"}]',
      );

      expect(parsed.single.stock, isNull);
      expect(parsed.single.price, 900);
      expect(parsed.single.totalTrades, isNull);
      expect(parsed.single.lastSoldAtEpochSeconds, isNull);
    });

    test('prefers canonical cumulative trades and ignores empty sale time', () {
      final parsed = MarketPayloadParser.parseArshaItems(
        '[{"id":55,"price":900,"totalTrades":12,'
        '"totalTradeCount":99,"lastSoldTime":0}]',
      );

      expect(parsed.single.totalTrades, 12);
      expect(parsed.single.lastSoldAtEpochSeconds, isNull);
    });

    test(
      'does not turn an invalid negative trade counter into zero demand',
      () {
        final parsed = MarketPayloadParser.parseArshaItems(
          '[{"id":55,"price":900,"totalTrades":-1}]',
        );

        expect(parsed.single.totalTrades, isNull);
      },
    );

    test('rejects malformed JSON inside resultMsg', () {
      expect(
        () => MarketPayloadParser.parseArshaItems('{"resultMsg":"not-json"}'),
        throwsFormatException,
      );
    });
  });
}
