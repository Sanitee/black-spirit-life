import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:bdo_gathering_companion/services/gathering_market_service.dart';
import 'package:flutter_test/flutter_test.dart';

GatheringMarketHttpResponse marketResponse(String resultMessage) =>
    GatheringMarketHttpResponse(
      statusCode: HttpStatus.ok,
      body: jsonEncode({'resultCode': 0, 'resultMsg': resultMessage}),
    );

int requestedItemId(GatheringMarketHttpRequest request) =>
    (jsonDecode(request.body) as Map<String, dynamic>)['mainKey'] as int;

void main() {
  test(
    'posts the authoritative EU request and parses price and stock',
    () async {
      final requests = <GatheringMarketHttpRequest>[];
      final fetchedAt = DateTime.utc(2026, 9, 2, 12, 30);
      final service = GatheringMarketService(
        now: () => fetchedAt,
        transport: (request) async {
          requests.add(request);
          return marketResponse(
            '4998-0-0-3580000-0-275522848-1440000-7000000|',
          );
        },
      );

      final quotes = await service.fetchQuotes([4998]);

      expect(requests, hasLength(1));
      expect(requests.single.uri, GatheringMarketService.endpoint);
      expect(
        requests.single.uri.toString(),
        'https://eu-trade.naeu.playblackdesert.com/'
        'Trademarket/GetWorldMarketSubList',
      );
      expect(
        requests.single.headers[HttpHeaders.userAgentHeader],
        'BlackDesert',
      );
      expect(
        requests.single.headers[HttpHeaders.contentTypeHeader],
        'application/json',
      );
      expect(jsonDecode(requests.single.body), {'keyType': 0, 'mainKey': 4998});
      expect(quotes.keys, [4998]);
      expect(quotes[4998]!.price, 3580000);
      expect(quotes[4998]!.stock, 0);
      expect(quotes[4998]!.hasKnownStock, isTrue);
      expect(quotes[4998]!.fetchedAt, fetchedAt);
      expect(
        () => quotes[721003] = GatheringMarketQuote(
          itemId: 721003,
          price: 1,
          stock: null,
          fetchedAt: fetchedAt,
        ),
        throwsUnsupportedError,
      );
    },
  );

  test('decodes live order-book bytes and sums current preorders', () async {
    final requests = <GatheringMarketHttpRequest>[];
    final service = GatheringMarketService(
      transport: (request) async {
        requests.add(request);
        if (request.uri == GatheringMarketService.endpoint) {
          return marketResponse('4998-0-0-5400000-2770|');
        }
        expect(request.uri, GatheringMarketService.orderBookEndpoint);
        return GatheringMarketHttpResponse(
          statusCode: HttpStatus.ok,
          body: '',
          bodyBytes: Uint8List.fromList(_capturedOrderBookFixture),
        );
      },
    );

    final quotes = await service.fetchQuotes([4998], includePreorders: true);

    expect(requests, hasLength(2));
    expect(requests.last.uri, GatheringMarketService.orderBookEndpoint);
    expect(jsonDecode(requests.last.body), {
      'keyType': 0,
      'mainKey': 4998,
      'subKey': 0,
    });
    expect(
      requests.last.headers[HttpHeaders.acceptHeader],
      'application/octet-stream',
    );
    expect(quotes[4998]!.stock, 2770);
    expect(quotes[4998]!.preorders, 1627);
    expect(quotes[4998]!.hasKnownPreorders, isTrue);
  });

  test(
    'keeps the listing quote when the optional order book is malformed',
    () async {
      final service = GatheringMarketService(
        transport: (request) async =>
            request.uri == GatheringMarketService.endpoint
            ? marketResponse('4998-0-0-5400000-9|')
            : GatheringMarketHttpResponse(
                statusCode: HttpStatus.ok,
                body: '',
                bodyBytes: Uint8List.fromList(const [1, 2, 3]),
              ),
      );

      final quotes = await service.fetchQuotes([4998], includePreorders: true);

      expect(quotes[4998]!.price, 5400000);
      expect(quotes[4998]!.stock, 9);
      expect(quotes[4998]!.preorders, isNull);
      expect(quotes[4998]!.hasKnownPreorders, isFalse);
    },
  );

  test('filters invalid IDs and de-duplicates equivalent IDs', () async {
    final requests = <int>[];
    final service = GatheringMarketService(
      transport: (request) async {
        final id = requestedItemId(request);
        requests.add(id);
        return marketResponse('$id-0-0-120000-4|');
      },
    );

    final quotes = await service.fetchQuotes([
      null,
      0,
      -1,
      '',
      'not-an-id',
      4998,
      ' 4998 ',
      4998.0,
      4998.5,
      0x80000000,
    ]);

    expect(requests, [4998]);
    expect(quotes.keys, [4998]);
  });

  test(
    'UI loader accepts item metadata and returns canonical string keys',
    () async {
      final service = GatheringMarketService(
        transport: (request) async {
          final id = requestedItemId(request);
          return marketResponse('$id-0-0-120000-4|');
        },
      );

      final GatheringMarketLoader loader = service.fetch;
      final quotes = await loader({
        '004998': 'Sharp Black Crystal Shard',
        '721003': 'Caphras Stone',
        'invalid': 'Ignored',
      });

      expect(quotes.keys, ['4998', '721003']);
      expect(quotes['4998']!.price, 120000);
      expect(() => quotes.remove('4998'), throwsUnsupportedError);
    },
  );

  test('keeps successful quotes when sibling requests fail', () async {
    final service = GatheringMarketService(
      transport: (request) async {
        switch (requestedItemId(request)) {
          case 1:
            return marketResponse('1-0-0-900-12|');
          case 2:
            throw const SocketException('offline');
          case 3:
            return const GatheringMarketHttpResponse(
              statusCode: HttpStatus.serviceUnavailable,
              body: 'unavailable',
            );
          case 4:
            return const GatheringMarketHttpResponse(
              statusCode: HttpStatus.ok,
              body: '{malformed',
            );
          default:
            throw StateError('unexpected item');
        }
      },
    );

    final quotes = await service.fetchQuotes([1, 2, 3, 4]);

    expect(quotes.keys, [1]);
    expect(quotes[1]!.price, 900);
    expect(quotes[1]!.stock, 12);
  });

  test('runs at most four market requests concurrently', () async {
    var active = 0;
    var maximumActive = 0;
    final service = GatheringMarketService(
      transport: (request) async {
        active += 1;
        if (active > maximumActive) maximumActive = active;
        await Future<void>.delayed(const Duration(milliseconds: 10));
        active -= 1;
        final id = requestedItemId(request);
        return marketResponse('$id-0-0-1-1|');
      },
    );

    final quotes = await service.fetchQuotes(List.generate(17, (i) => i + 1));

    expect(quotes, hasLength(17));
    expect(maximumActive, GatheringMarketService.maximumConcurrency);
  });

  test('distinguishes unknown stock from a known zero stock', () async {
    final service = GatheringMarketService(
      transport: (request) async {
        final id = requestedItemId(request);
        return marketResponse(id == 10 ? '10-0-0-50-0|' : '11-0-0-75|');
      },
    );

    final quotes = await service.fetchQuotes([10, 11]);

    expect(quotes[10]!.stock, 0);
    expect(quotes[10]!.hasKnownStock, isTrue);
    expect(quotes[11]!.stock, isNull);
    expect(quotes[11]!.hasKnownStock, isFalse);
  });

  test('uses the requested item row and rejects an API error result', () async {
    final service = GatheringMarketService(
      transport: (request) async {
        final id = requestedItemId(request);
        if (id == 22) {
          return marketResponse('999-0-0-1-1|22-0-0-2200-8|');
        }
        return GatheringMarketHttpResponse(
          statusCode: HttpStatus.ok,
          body: jsonEncode({'resultCode': -1, 'resultMsg': '23-0-0-2300-9|'}),
        );
      },
    );

    final quotes = await service.fetchQuotes([22, 23]);

    expect(quotes.keys, [22]);
    expect(quotes[22]!.price, 2200);
    expect(quotes[22]!.stock, 8);
  });

  test('retains all six known zero-stock Nostos base quotes', () async {
    const ids = <int>[821348, 821349, 821350, 821351, 821352, 821353];
    final service = GatheringMarketService(
      transport: (request) async {
        final id = requestedItemId(request);
        return marketResponse('$id-0-0-2800000-0|');
      },
    );

    final batch = await service.fetchBaseQuotes(ids);

    expect(batch.quotes.keys, ids);
    expect(batch.quotes.values.map((quote) => quote.stock), everyElement(0));
    expect(batch.unavailableItemIds, isEmpty);
    expect(batch.failedItemIds, isEmpty);
  });

  test(
    'retries only failed base IDs and preserves batch classifications',
    () async {
      final attempts = <int, int>{};
      final delays = <Duration>[];
      final service = GatheringMarketService(
        baseRetryBaseDelay: const Duration(milliseconds: 3),
        baseRetrySpacing: const Duration(milliseconds: 2),
        delay: (duration) async => delays.add(duration),
        transport: (request) async {
          final id = requestedItemId(request);
          final attempt = attempts.update(
            id,
            (value) => value + 1,
            ifAbsent: () => 1,
          );
          if (id == 1) return marketResponse('1-0-0-100-4|');
          if (id == 2) return marketResponse('0');
          if (id == 3 && attempt == 2) {
            return marketResponse('3-0-0-300-0|');
          }
          return const GatheringMarketHttpResponse(
            statusCode: HttpStatus.serviceUnavailable,
            body: 'busy',
          );
        },
      );

      final batch = await service.fetchBaseQuotes([1, 2, 3, 4]);

      expect(batch.quotes.keys, [1, 3]);
      expect(batch.quotes[3]!.stock, 0);
      expect(batch.unavailableItemIds, {2});
      expect(batch.failedItemIds, {4});
      expect(attempts, {1: 1, 2: 1, 3: 2, 4: 2});
      expect(delays, const [
        Duration(milliseconds: 3),
        Duration(milliseconds: 2),
      ]);
    },
  );

  test(
    'retries preorder failures without losing the valid stock quote',
    () async {
      var orderBookAttempts = 0;
      final service = GatheringMarketService(
        preorderRequestSpacing: Duration.zero,
        preorderRetryBaseDelay: Duration.zero,
        transport: (request) async {
          if (request.uri == GatheringMarketService.endpoint) {
            return marketResponse('821351-0-0-2800000-0|');
          }
          orderBookAttempts += 1;
          return const GatheringMarketHttpResponse(
            statusCode: HttpStatus.serviceUnavailable,
            body: 'busy',
          );
        },
      );

      final quotes = await service.fetchQuotes([
        821351,
      ], includePreorders: true);

      expect(orderBookAttempts, 2);
      expect(quotes[821351]!.price, 2800000);
      expect(quotes[821351]!.stock, 0);
      expect(quotes[821351]!.preorders, isNull);
    },
  );

  test(
    'preorder work is paced, retried, and serialized across batches',
    () async {
      final requested = <int>[];
      final attempts = <int, int>{};
      final delays = <Duration>[];
      var active = 0;
      var maximumActive = 0;
      final service = GatheringMarketService(
        preorderRequestSpacing: const Duration(milliseconds: 2),
        preorderRetryBaseDelay: const Duration(milliseconds: 5),
        delay: (duration) async => delays.add(duration),
        transport: (request) async {
          final id = requestedItemId(request);
          requested.add(id);
          active += 1;
          maximumActive = math.max(maximumActive, active);
          await Future<void>.delayed(Duration.zero);
          active -= 1;
          final attempt = attempts.update(
            id,
            (value) => value + 1,
            ifAbsent: () => 1,
          );
          if (id == 1 && attempt == 1) {
            return const GatheringMarketHttpResponse(
              statusCode: HttpStatus.serviceUnavailable,
              body: 'busy',
            );
          }
          return marketResponse('100-0-${id == 1 ? 7 : 0}|');
        },
      );

      final batches = await Future.wait([
        service.fetchPreorderCounts([1]),
        service.fetchPreorderCounts([2]),
      ]);

      expect(requested, [1, 1, 2]);
      expect(maximumActive, 1);
      expect(batches[0].counts, {1: 7});
      expect(batches[1].counts, {2: 0});
      expect(delays, const [
        Duration(milliseconds: 5),
        Duration(milliseconds: 2),
        Duration(milliseconds: 2),
      ]);
    },
  );

  test('preorder circuit reports untouched IDs as deferred', () async {
    final requested = <int>[];
    final service = GatheringMarketService(
      maximumPreorderAttempts: 2,
      maximumConsecutivePreorderFailures: 3,
      preorderRequestSpacing: Duration.zero,
      preorderRetryBaseDelay: Duration.zero,
      transport: (request) async {
        requested.add(requestedItemId(request));
        return const GatheringMarketHttpResponse(
          statusCode: HttpStatus.tooManyRequests,
          body: 'busy',
        );
      },
    );

    final batch = await service.fetchPreorderCounts([1, 2, 3, 4]);

    expect(requested, [1, 1, 2]);
    expect(batch.failedItemIds, {1, 2});
    expect(batch.deferredItemIds, {3, 4});
    expect(batch.counts, isEmpty);
  });
}

/// Real EU `GetBiddingInfoList` response captured 2026-09-02 for item 4998.
/// It decodes to eight `price-sellers-buyers` rows containing 1,627 buyers.
const _capturedOrderBookFixture = <int>[
  155,
  0,
  0,
  0,
  0,
  0,
  0,
  0,
  12,
  0,
  0,
  0,
  16,
  0,
  0,
  0,
  45,
  0,
  0,
  0,
  56,
  0,
  0,
  0,
  48,
  0,
  0,
  0,
  4,
  0,
  0,
  0,
  49,
  0,
  0,
  0,
  3,
  0,
  0,
  0,
  50,
  0,
  0,
  0,
  2,
  0,
  0,
  0,
  51,
  0,
  0,
  0,
  2,
  0,
  0,
  0,
  52,
  0,
  0,
  0,
  11,
  0,
  0,
  0,
  53,
  0,
  0,
  0,
  3,
  0,
  0,
  0,
  54,
  0,
  0,
  0,
  3,
  0,
  0,
  0,
  55,
  0,
  0,
  0,
  2,
  0,
  0,
  0,
  56,
  0,
  0,
  0,
  1,
  0,
  0,
  0,
  57,
  0,
  0,
  0,
  8,
  0,
  0,
  0,
  124,
  0,
  0,
  0,
  20,
  1,
  0,
  0,
  35,
  0,
  0,
  0,
  111,
  0,
  0,
  0,
  31,
  170,
  103,
  113,
  30,
  168,
  196,
  59,
  134,
  190,
  152,
  89,
  24,
  174,
  12,
  61,
  22,
  209,
  74,
  224,
  227,
  211,
  117,
  112,
  127,
  166,
  117,
  112,
  111,
  162,
  85,
  195,
  127,
  85,
  112,
];
