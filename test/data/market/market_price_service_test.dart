import 'dart:async';
import 'dart:convert';

import 'package:bdo_craft_planner_flutter/data/market/market_http_transport.dart';
import 'package:bdo_craft_planner_flutter/data/market/market_price_service.dart';
import 'package:bdo_craft_planner_flutter/data/market/market_service_configuration.dart';
import 'package:bdo_craft_planner_flutter/domain/market/market_cancellation.dart';
import 'package:bdo_craft_planner_flutter/domain/market/market_price_models.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/recording_market_http_transport.dart';

void main() {
  final fixedTime = DateTime.utc(2026, 7, 20, 9, 30);

  group('MarketPriceService source policy', () {
    test('trade-evidence enrichment is enabled by default', () {
      expect(const MarketServiceConfiguration().collectTradeEvidence, isTrue);
    });

    test(
      'enriches direct price and stock with batched trade evidence',
      () async {
        final transport = RecordingMarketHttpTransport((request) async {
          if (_isDirect(request)) {
            return const MarketHttpResponse(
              statusCode: 200,
              body: '{"resultMsg":"1-0-0-1500-4|"}',
            );
          }
          if (_isBatch(request)) {
            return const MarketHttpResponse(
              statusCode: 200,
              body:
                  '[{"id":1,"basePrice":9999,"currentStock":99,'
                  '"totalTrades":1200,"lastSoldTime":1785346251}]',
            );
          }
          fail('Trade evidence must not fall back to per-item requests.');
        });
        final service = MarketPriceService(
          transport: transport,
          configuration: _configuration(collectTradeEvidence: true),
          clock: () => fixedTime,
        );

        final result = await service.fetch(_requests(1));

        expect(transport.requests, hasLength(2));
        expect(result.items.single.price, 1500);
        expect(result.items.single.stock, 4);
        expect(
          result.items.single.source,
          MarketPriceSource.pearlAbyssCentralMarket,
        );
        expect(result.items.single.totalTrades, 1200);
        expect(result.items.single.lastSoldAtEpochSeconds, 1785346251);
        expect(result.attemptedSources, const <MarketPriceSource>[
          MarketPriceSource.pearlAbyssCentralMarket,
          MarketPriceSource.arshaV2Batch,
        ]);
      },
    );

    test('keeps a direct result when optional trade evidence fails', () async {
      final transport = RecordingMarketHttpTransport((request) async {
        if (_isDirect(request)) {
          return const MarketHttpResponse(
            statusCode: 200,
            body: '{"resultMsg":"1-0-0-1500-4|"}',
          );
        }
        if (_isBatch(request)) {
          return const MarketHttpResponse(statusCode: 503);
        }
        fail('Optional evidence failure must not invoke Arsha v1.');
      });
      final service = MarketPriceService(
        transport: transport,
        configuration: _configuration(collectTradeEvidence: true),
        clock: () => fixedTime,
      );

      final result = await service.fetch(_requests(1));

      expect(result.successCount, 1);
      expect(result.items.single.price, 1500);
      expect(result.items.single.stock, 4);
      expect(result.items.single.totalTrades, isNull);
      expect(transport.requests.where(_isBatch), hasLength(1));
      expect(transport.requests.where(_isSingle), isEmpty);
      expect(result.attemptedSources, const <MarketPriceSource>[
        MarketPriceSource.pearlAbyssCentralMarket,
        MarketPriceSource.arshaV2Batch,
      ]);
    });

    test(
      'uses the direct PA endpoint and keeps a huge ID as a string',
      () async {
        const hugeId = '123456789012345678901234567890';
        late MarketHttpRequest recorded;
        final transport = RecordingMarketHttpTransport((request) async {
          recorded = request;
          return MarketHttpResponse(
            statusCode: 200,
            body: jsonEncode(<String, Object?>{
              'resultMsg': '$hugeId-0-0-1500-4|',
            }),
          );
        });
        final service = MarketPriceService(
          transport: transport,
          configuration: _configuration(),
          clock: () => fixedTime,
        );

        final result = await service.fetch(const <MarketPriceRequest>[
          MarketPriceRequest(name: 'Huge item', id: hugeId),
        ]);

        expect(recorded.uri.host, 'eu-trade.naeu.playblackdesert.com');
        expect(recorded.uri.path, '/Trademarket/GetWorldMarketSubList');
        expect(recorded.headers['User-Agent'], 'BlackDesert');
        expect(recorded.body, '{"keyType":0,"mainKey":$hugeId}');
        expect(result.items.single.id, hugeId);
        expect(result.items.single.price, 1500);
        expect(result.items.single.stock, 4);
        expect(
          result.items.single.source,
          MarketPriceSource.pearlAbyssCentralMarket,
        );
        expect(result.items.single.fetchedAt, fixedTime);
        expect(result.attemptedSources, <MarketPriceSource>[
          MarketPriceSource.pearlAbyssCentralMarket,
        ]);
      },
    );

    test('retains a direct partial result and does not invoke Arsha', () async {
      final transport = RecordingMarketHttpTransport((request) async {
        if (request.body.contains('"mainKey":1')) {
          return const MarketHttpResponse(
            statusCode: 200,
            body: '{"resultMsg":"1-0-0-900-2|"}',
          );
        }
        return const MarketHttpResponse(
          statusCode: 200,
          body: '{"resultMsg":""}',
        );
      });
      final service = MarketPriceService(
        transport: transport,
        configuration: _configuration(),
        clock: () => fixedTime,
      );

      final result = await service.fetch(_requests(2));

      expect(transport.requests, hasLength(2));
      expect(
        transport.requests.where(
          (request) => request.uri.host == 'api.arsha.io',
        ),
        isEmpty,
      );
      expect(result.successCount, 1);
      expect(result.failureCount, 1);
      expect(result.hasPartialSuccess, isTrue);
      expect(result.items[1].diagnosticCode, MarketDiagnosticCode.itemMissing);
    });

    test(
      'refreshes every request in bounded batches without truncation',
      () async {
        final transport = RecordingMarketHttpTransport((request) async {
          expect(_isDirect(request), isTrue);
          await Future<void>.delayed(const Duration(milliseconds: 1));
          final id = RegExp(
            r'"mainKey":(\d+)',
          ).firstMatch(request.body)!.group(1)!;
          return MarketHttpResponse(
            statusCode: 200,
            body: jsonEncode(<String, Object?>{
              'resultMsg': '$id-0-0-${int.parse(id) * 100}-$id|',
            }),
          );
        });
        final service = MarketPriceService(
          transport: transport,
          configuration: _configuration(maximumRequests: 2),
          clock: () => fixedTime,
        );

        final result = await service.fetch(_requests(5));

        expect(result.items.map((row) => row.id), const <String>[
          '1',
          '2',
          '3',
          '4',
          '5',
        ]);
        expect(result.items.map((row) => row.stock), const <int?>[
          1,
          2,
          3,
          4,
          5,
        ]);
        expect(result.truncatedRequestCount, 0);
        expect(transport.requests, hasLength(5));
        expect(transport.maximumActiveRequests, 2);
        expect(result.attemptedSources, const <MarketPriceSource>[
          MarketPriceSource.pearlAbyssCentralMarket,
        ]);
      },
    );

    test(
      'partitions Arsha fallbacks into sequential bounded batches',
      () async {
        final batchBodies = <String>[];
        var activeBatchRequests = 0;
        var maximumActiveBatchRequests = 0;
        final transport = RecordingMarketHttpTransport((request) async {
          if (_isDirect(request)) {
            return const MarketHttpResponse(statusCode: 503);
          }
          if (_isBatch(request)) {
            batchBodies.add(request.body);
            activeBatchRequests++;
            if (activeBatchRequests > maximumActiveBatchRequests) {
              maximumActiveBatchRequests = activeBatchRequests;
            }
            try {
              await Future<void>.delayed(const Duration(milliseconds: 1));
              final ids = (jsonDecode(request.body) as List<Object?>)
                  .cast<int>();
              return MarketHttpResponse(
                statusCode: 200,
                body: jsonEncode(<Object?>[
                  for (final id in ids)
                    <String, Object?>{
                      'id': id,
                      'basePrice': id * 100,
                      'currentStock': id,
                    },
                ]),
              );
            } finally {
              activeBatchRequests--;
            }
          }
          fail('Arsha v1 must not be used after valid batch responses');
        });
        final service = MarketPriceService(
          transport: transport,
          configuration: _configuration(maximumRequests: 2),
          clock: () => fixedTime,
        );

        final result = await service.fetch(_requests(5));

        expect(batchBodies, const <String>['[1,2]', '[3,4]', '[5]']);
        expect(maximumActiveBatchRequests, 1);
        expect(result.items.map((row) => row.id), const <String>[
          '1',
          '2',
          '3',
          '4',
          '5',
        ]);
        expect(result.items.map((row) => row.price), const <int>[
          100,
          200,
          300,
          400,
          500,
        ]);
        expect(result.successCount, 5);
        expect(result.truncatedRequestCount, 0);
        expect(result.attemptedSources, const <MarketPriceSource>[
          MarketPriceSource.pearlAbyssCentralMarket,
          MarketPriceSource.arshaV2Batch,
        ]);
      },
    );

    test('uses Arsha v2 when direct has no successful rows', () async {
      final transport = RecordingMarketHttpTransport((request) async {
        if (_isDirect(request)) {
          return const MarketHttpResponse(statusCode: 503);
        }
        if (_isBatch(request)) {
          final nested = jsonEncode(<String, Object?>{
            'data': <Object?>[
              <String, Object?>{
                'id': '1',
                'basePrice': '1200',
                'currentStock': '5',
                'name': 'API one',
              },
              <String, Object?>{
                'id': 2,
                'currentPrice': 2200,
                'name': 'API two',
              },
            ],
          });
          return MarketHttpResponse(
            statusCode: 200,
            body: jsonEncode(<String, Object?>{'resultMsg': nested}),
          );
        }
        fail('Arsha v1 must not be used after a valid batch response');
      });
      final service = MarketPriceService(
        transport: transport,
        configuration: _configuration(),
        clock: () => fixedTime,
      );

      final result = await service.fetch(_requests(2));

      final batch = transport.requests.singleWhere(_isBatch);
      expect(batch.uri.path, '/v2/eu/GetWorldMarketSubList');
      expect(batch.uri.queryParameters['lang'], 'en');
      expect(batch.body, '[1,2]');
      expect(result.items.map((row) => row.price), <int>[1200, 2200]);
      expect(result.items[0].stock, 5);
      expect(result.items[1].stock, isNull);
      expect(result.items[1].apiName, 'API two');
      expect(result.attemptedSources, <MarketPriceSource>[
        MarketPriceSource.pearlAbyssCentralMarket,
        MarketPriceSource.arshaV2Batch,
      ]);
    });

    test('reports a partial v2 payload without silently invoking v1', () async {
      final transport = RecordingMarketHttpTransport((request) async {
        if (_isDirect(request)) {
          return const MarketHttpResponse(statusCode: 404);
        }
        if (_isBatch(request)) {
          return const MarketHttpResponse(
            statusCode: 200,
            body: '[{"id":"1","price":"500","stock":"0"}]',
          );
        }
        fail('A valid partial batch is retained, not replaced');
      });
      final service = MarketPriceService(
        transport: transport,
        configuration: _configuration(),
        clock: () => fixedTime,
      );

      final result = await service.fetch(_requests(2));

      expect(result.hasPartialSuccess, isTrue);
      expect(result.items[0].stock, 0);
      expect(result.items[1].diagnosticCode, MarketDiagnosticCode.itemMissing);
      expect(result.failureCountsByCode, <MarketDiagnosticCode, int>{
        MarketDiagnosticCode.itemMissing: 1,
      });
      expect(transport.requests.where(_isSingle), isEmpty);
    });

    test('retries only transient v2 statuses with audited backoff', () async {
      var batchAttempt = 0;
      final observedDelays = <Duration>[];
      final transport = RecordingMarketHttpTransport((request) async {
        if (_isDirect(request)) {
          return const MarketHttpResponse(statusCode: 404);
        }
        if (_isBatch(request)) {
          batchAttempt++;
          if (batchAttempt == 1) {
            return const MarketHttpResponse(statusCode: 503);
          }
          if (batchAttempt == 2) {
            return const MarketHttpResponse(statusCode: 429);
          }
          return const MarketHttpResponse(
            statusCode: 200,
            body: '[{"id":"1","price":"700","stock":"3"}]',
          );
        }
        fail('v1 should not be called after the third v2 attempt succeeds');
      });
      final service = MarketPriceService(
        transport: transport,
        configuration: _configuration(),
        clock: () => fixedTime,
        delay: (duration, cancellationToken) async {
          cancellationToken?.throwIfCancelled();
          observedDelays.add(duration);
        },
      );

      final result = await service.fetch(_requests(1));

      expect(result.successCount, 1);
      expect(batchAttempt, 3);
      expect(observedDelays, const <Duration>[
        Duration(milliseconds: 350),
        Duration(milliseconds: 700),
      ]);
    });

    test('does not retry a nontransient v2 status', () async {
      var batchAttempts = 0;
      final observedDelays = <Duration>[];
      final transport = RecordingMarketHttpTransport((request) async {
        if (_isDirect(request)) {
          return const MarketHttpResponse(statusCode: 404);
        }
        if (_isBatch(request)) {
          batchAttempts++;
          return const MarketHttpResponse(statusCode: 400);
        }
        return const MarketHttpResponse(
          statusCode: 200,
          body: '{"id":"1","basePrice":"800","name":"Single"}',
        );
      });
      final service = MarketPriceService(
        transport: transport,
        configuration: _configuration(),
        clock: () => fixedTime,
        delay: (duration, cancellationToken) async {
          observedDelays.add(duration);
        },
      );

      final result = await service.fetch(_requests(1));

      expect(result.successCount, 1);
      expect(batchAttempts, 1);
      expect(observedDelays, isEmpty);
      expect(result.items.single.source, MarketPriceSource.arshaV1Item);
    });

    test('falls back from malformed v2 to bounded v1 item requests', () async {
      final transport = RecordingMarketHttpTransport((request) async {
        if (_isDirect(request)) {
          return const MarketHttpResponse(statusCode: 404);
        }
        if (_isBatch(request)) {
          return const MarketHttpResponse(
            statusCode: 200,
            body: '{"resultMsg":"not-json"}',
          );
        }
        if (_isSingle(request)) {
          await Future<void>.delayed(const Duration(milliseconds: 1));
          final id = request.headers['id']!;
          return MarketHttpResponse(
            statusCode: 200,
            body:
                '[{"mainKey":"$id","minPrice":"$id"'
                ',"count":"2","name":"Single $id"}]',
          );
        }
        fail('Unexpected market request: ${request.uri}');
      });
      final service = MarketPriceService(
        transport: transport,
        configuration: _configuration(maximumConcurrency: 3),
        clock: () => fixedTime,
      );

      final result = await service.fetch(_requests(7));

      expect(result.successCount, 7);
      expect(transport.maximumActiveRequests, 3);
      expect(transport.requests.where(_isSingle), hasLength(7));
      expect(result.items.last.price, 7);
      expect(result.items.last.stock, 2);
      expect(result.attemptedSources, <MarketPriceSource>[
        MarketPriceSource.pearlAbyssCentralMarket,
        MarketPriceSource.arshaV2Batch,
        MarketPriceSource.arshaV1Item,
      ]);
    });
  });

  group('MarketPriceService failure and cancellation', () {
    test('turns timeouts into per-row failures after all fallbacks', () async {
      final transport = RecordingMarketHttpTransport((request) async {
        await request.abortTrigger;
        throw StateError('fixture transport observed abort');
      });
      final service = MarketPriceService(
        transport: transport,
        configuration: _configuration(
          maximumConcurrency: 1,
          requestTimeout: const Duration(milliseconds: 10),
        ),
        clock: () => fixedTime,
      );

      final result = await service.fetch(_requests(1));

      expect(result.successCount, 0);
      expect(result.failureCount, 1);
      expect(result.items.single.diagnosticCode, MarketDiagnosticCode.timeout);
      expect(result.items.single.source, MarketPriceSource.arshaV1Item);
      expect(result.attemptedSources, <MarketPriceSource>[
        MarketPriceSource.pearlAbyssCentralMarket,
        MarketPriceSource.arshaV2Batch,
        MarketPriceSource.arshaV1Item,
      ]);
    });

    test('cancellation aborts in-flight I/O and prevents fallback', () async {
      final started = Completer<void>();
      final transport = RecordingMarketHttpTransport((request) async {
        if (!started.isCompleted) {
          started.complete();
        }
        await request.abortTrigger;
        throw StateError('fixture transport observed cancellation');
      });
      final controller = MarketCancellationController();
      final service = MarketPriceService(
        transport: transport,
        configuration: _configuration(
          requestTimeout: const Duration(seconds: 1),
        ),
        clock: () => fixedTime,
      );

      final future = service.fetch(
        _requests(1),
        cancellationToken: controller.token,
      );
      final expectation = expectLater(
        future,
        throwsA(isA<MarketFetchCancelledException>()),
      );
      await started.future;
      controller.cancel();
      await expectation;

      expect(transport.requests, hasLength(1));
      expect(_isDirect(transport.requests.single), isTrue);
    });

    test('cancellation after one chunk prevents chunk two I/O', () async {
      final controller = MarketCancellationController();
      var clockCallCount = 0;
      final transport = RecordingMarketHttpTransport((request) async {
        expect(_isDirect(request), isTrue);
        final id = RegExp(
          r'"mainKey":(\d+)',
        ).firstMatch(request.body)!.group(1)!;
        return MarketHttpResponse(
          statusCode: 200,
          body: '{"resultMsg":"$id-0-0-900-2|"}',
        );
      });
      final service = MarketPriceService(
        transport: transport,
        configuration: _configuration(maximumRequests: 1),
        clock: () {
          clockCallCount++;
          if (clockCallCount == 1) controller.cancel();
          return fixedTime;
        },
      );

      await expectLater(
        service.fetch(_requests(2), cancellationToken: controller.token),
        throwsA(isA<MarketFetchCancelledException>()),
      );

      expect(transport.requests, hasLength(1));
      expect(transport.requests.single.body, '{"keyType":0,"mainKey":1}');
      expect(clockCallCount, 1);
    });

    test('empty normalized input performs no I/O and reports skips', () async {
      final transport = RecordingMarketHttpTransport((request) async {
        fail('No HTTP request should be emitted for invalid input');
      });
      final service = MarketPriceService(
        transport: transport,
        configuration: _configuration(),
        clock: () => fixedTime,
      );

      final result = await service.fetch(const <MarketPriceRequest>[
        MarketPriceRequest(name: '', id: '1'),
        MarketPriceRequest(name: 'Zero', id: '0'),
      ]);

      expect(result.items, isEmpty);
      expect(result.invalidRequestCount, 2);
      expect(result.skippedRequestCount, 2);
      expect(result.attemptedSources, isEmpty);
      expect(transport.requests, isEmpty);
    });
  });
}

MarketServiceConfiguration _configuration({
  int maximumRequests = 80,
  int maximumConcurrency = 16,
  Duration requestTimeout = const Duration(seconds: 3),
  bool collectTradeEvidence = false,
}) => MarketServiceConfiguration(
  maximumRequests: maximumRequests,
  maximumConcurrency: maximumConcurrency,
  requestTimeout: requestTimeout,
  collectTradeEvidence: collectTradeEvidence,
);

List<MarketPriceRequest> _requests(int count) =>
    List<MarketPriceRequest>.generate(
      count,
      (index) =>
          MarketPriceRequest(name: 'Item ${index + 1}', id: '${index + 1}'),
      growable: false,
    );

bool _isDirect(MarketHttpRequest request) =>
    request.uri.path == '/Trademarket/GetWorldMarketSubList';

bool _isBatch(MarketHttpRequest request) =>
    request.uri.path == '/v2/eu/GetWorldMarketSubList';

bool _isSingle(MarketHttpRequest request) => request.uri.path == '/v1/eu/price';
