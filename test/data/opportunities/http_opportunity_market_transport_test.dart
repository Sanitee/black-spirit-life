import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:bdo_craft_planner_flutter/data/market/market_response_guard.dart';
import 'package:bdo_craft_planner_flutter/data/market/shared_market_repository.dart';
import 'package:bdo_craft_planner_flutter/data/opportunities/opportunity_market_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

void main() {
  for (final (status, headers) in [
    (429, <String, String>{}),
    (429, {'retry-after': '90'}),
    (503, {'Retry-After': '90'}),
  ]) {
    test(
      '$status pause does not wait for an unending response body: $headers',
      () async {
        var cancelled = false;
        final cancellation = Completer<void>();
        final body = StreamController<List<int>>(
          onCancel: () {
            cancelled = true;
            return cancellation.future;
          },
        );
        final client = _Client(
          (_) async =>
              http.StreamedResponse(body.stream, status, headers: headers),
        );
        final transport = HttpOpportunityMarketTransport(client: client);
        addTearDown(transport.close);
        final response = await _post(
          transport,
        ).timeout(const Duration(seconds: 1));
        expect(response.statusCode, status);
        expect(response.headers, headers);
        expect(response.bytes, isEmpty);
        // Headers are available before the bounded classification completes.
        expect(cancelled, isFalse);
        expect(response.protectionBytes, isNotNull);
        expect(
          await response.protectionBytes!.timeout(const Duration(seconds: 2)),
          isEmpty,
        );
        expect(cancelled, isTrue);
        cancellation.complete();
        await body.close();
      },
    );
  }

  test(
    'throttle headers stop the shared queue before the body arrives',
    () async {
      var cancelled = false;
      final body = StreamController<List<int>>(
        onCancel: () => cancelled = true,
      );
      final client = _Client(
        (_) async => http.StreamedResponse(
          body.stream,
          429,
          headers: {'retry-after': '90'},
        ),
      );
      final repository = SharedMarketRepository(
        transport: HttpOpportunityMarketTransport(client: client),
        concurrency: 1,
        requestSpacing: Duration.zero,
      );
      addTearDown(repository.close);
      final batch = await repository
          .fetch(
            bookKeys: [
              for (final id in ['1', '2', '3'])
                SharedMarketKey(region: 'eu', itemId: id),
            ],
          )
          .timeout(const Duration(seconds: 1));
      expect(client.requests, hasLength(1));
      expect(cancelled, isTrue);
      expect(batch.failures, hasLength(3));
      expect(
        repository.pauseFor('eu')?.reason,
        MarketRequestPauseReason.throttled,
      );
      expect(
        repository
            .pauseFor('eu')!
            .retryAt
            .difference(DateTime.now().toUtc())
            .inSeconds,
        greaterThanOrEqualTo(88),
      );
      await body.close();
    },
  );

  for (final status in [429, 503]) {
    test(
      '$status pauses at headers and upgrades split HTML even with Retry-After zero',
      () async {
        var cancelled = false;
        var now = DateTime.utc(2026, 9, 11);
        final body = StreamController<List<int>>(
          onCancel: () => cancelled = true,
        );
        final client = _Client(
          (_) async => http.StreamedResponse(
            body.stream,
            status,
            headers: {'retry-after': '0', 'content-type': 'text/html'},
          ),
        );
        final repository = SharedMarketRepository(
          transport: HttpOpportunityMarketTransport(client: client),
          concurrency: 2,
          requestSpacing: Duration.zero,
          primeSession: true,
          utcNow: () => now,
        );
        addTearDown(repository.close);
        final loading = repository.fetch(
          bookKeys: [for (var id = 1; id <= 3; id++) _key('$id')],
        );
        await _until(() => repository.pauseFor('eu') != null);
        expect(repository.pauseFor('eu')!.retryAt, now);
        expect(
          repository.pauseFor('eu')!.reason,
          status == 429
              ? MarketRequestPauseReason.throttled
              : MarketRequestPauseReason.serverUnavailable,
        );
        expect(cancelled, isFalse);
        // A zero server deadline cannot reopen the origin during inspection,
        // including an explicit overlapping caller.
        final overlapping = await repository.fetch(
          bookKeys: [_key('4')],
          forceRefresh: true,
          userInitiated: true,
        );
        expect(overlapping.rateLimited, isTrue);
        expect(client.requests, hasLength(1));
        body.add(utf8.encode('<html><iframe src="/_Incap'));
        body.add(utf8.encode('sula_Resource?test"></iframe></html>'));
        final batch = await loading.timeout(const Duration(seconds: 2));
        expect(batch.failures, hasLength(3));
        expect(batch.retryableFailures, isEmpty);
        expect(batch.pauses['eu']!.reason, MarketRequestPauseReason.protected);
        expect(
          repository.pauseFor('eu')!.reason,
          MarketRequestPauseReason.protected,
        );
        expect(repository.pauseFor('eu')!.retryAt, now);
        expect(cancelled, isTrue);
        now = now.add(const Duration(hours: 1));
        final afterDeadline = await repository.fetch(bookKeys: [_key('5')]);
        expect(afterDeadline.rateLimited, isTrue);
        expect(
          afterDeadline.pauses['eu']!.reason,
          MarketRequestPauseReason.protected,
        );
        expect(client.requests, hasLength(1));
        await body.close();
      },
    );

    test(
      '$status legacy client also upgrades the header pause to protected',
      () async {
        var cancelled = false;
        final body = StreamController<List<int>>(
          onCancel: () => cancelled = true,
        );
        final client = _Client(
          (_) async => http.StreamedResponse(
            body.stream,
            status,
            headers: {'retry-after': '0'},
          ),
        );
        final service = OpportunityMarketService(
          transport: HttpOpportunityMarketTransport(client: client),
          concurrency: 1,
          requestSpacing: Duration.zero,
        );
        addTearDown(service.close);
        final headersPaused = Completer<void>();
        final loading = service.fetchMarket(
          quoteIds: const [],
          bookIds: ['1', '2', '3'],
          onRateLimited: headersPaused.complete,
        );
        await headersPaused.future.timeout(const Duration(seconds: 2));
        expect(service.pause, isNotNull);
        expect(cancelled, isFalse);
        body.add(utf8.encode('<html>Incapsula incident ID: synthetic</html>'));
        final batch = await loading.timeout(const Duration(seconds: 2));
        expect(batch.pause!.reason, MarketRequestPauseReason.protected);
        expect(batch.retryableBookFailures, isEmpty);
        expect(batch.retryableQuoteFailures, isEmpty);
        expect(cancelled, isTrue);
        final denied = await service.fetchMarket(
          quoteIds: const [],
          bookIds: ['4'],
        );
        expect(denied.pause!.reason, MarketRequestPauseReason.protected);
        expect(client.requests, hasLength(1));
        await body.close();
      },
    );
  }

  test('bounded ordinary 503 HTML keeps its timed server pause', () async {
    var cancelled = false;
    final body = StreamController<List<int>>(onCancel: () => cancelled = true);
    final client = _Client(
      (_) async => http.StreamedResponse(
        body.stream,
        503,
        headers: {'retry-after': '90', 'content-type': 'text/html'},
      ),
    );
    final now = DateTime.utc(2026, 9, 11);
    final repository = SharedMarketRepository(
      transport: HttpOpportunityMarketTransport(client: client),
      concurrency: 1,
      requestSpacing: Duration.zero,
      utcNow: () => now,
    );
    addTearDown(repository.close);
    final loading = repository.fetch(bookKeys: [_key('1'), _key('2')]);
    await _until(() => repository.pauseFor('eu') != null);
    body.add(utf8.encode('<html>Scheduled maintenance</html>'));
    // The stream deliberately never closes; classification must be bounded.
    final batch = await loading.timeout(const Duration(seconds: 2));
    expect(
      batch.pauses['eu']!.reason,
      MarketRequestPauseReason.serverUnavailable,
    );
    expect(batch.pauses['eu']!.retryAt, now.add(const Duration(seconds: 90)));
    expect(batch.retryableFailures, hasLength(2));
    expect(cancelled, isTrue);
    expect(client.requests, hasLength(1));
    await body.close();
  });

  test(
    'denial headers abort sibling work before body classification',
    () async {
      final firstHeaders = Completer<http.StreamedResponse>();
      final body = StreamController<List<int>>();
      final aborted = <String>{};
      final client = _Client((request) {
        final decoded =
            jsonDecode((request as http.Request).body) as Map<String, dynamic>;
        final id = '${decoded['mainKey']}';
        if (id == '1') return firstHeaders.future;
        final pending = Completer<http.StreamedResponse>();
        (request as http.AbortableRequest).abortTrigger!.then((_) {
          aborted.add(id);
          pending.complete(
            http.StreamedResponse(const Stream<List<int>>.empty(), 200),
          );
        });
        return pending.future;
      });
      final repository = SharedMarketRepository(
        transport: HttpOpportunityMarketTransport(client: client),
        concurrency: 3,
        requestSpacing: Duration.zero,
      );
      addTearDown(repository.close);
      final loading = repository.fetch(
        bookKeys: [for (var id = 1; id <= 5; id++) _key('$id')],
      );
      await _until(() => client.requests.length == 3);
      firstHeaders.complete(
        http.StreamedResponse(body.stream, 503, headers: {'retry-after': '90'}),
      );
      await _until(() => aborted.length == 2);
      expect(
        repository.pauseFor('eu')!.reason,
        MarketRequestPauseReason.serverUnavailable,
      );
      expect(aborted, {'2', '3'});
      expect(client.requests, hasLength(3));
      body.add(utf8.encode('<html>Incapsula incident ID: synthetic</html>'));
      final batch = await loading.timeout(const Duration(seconds: 2));
      expect(batch.failures, hasLength(5));
      expect(batch.retryableFailures, isEmpty);
      expect(batch.pauses['eu']!.reason, MarketRequestPauseReason.protected);
      expect(repository.snapshot('eu').items, isEmpty);
      expect(client.requests, hasLength(3));
      await body.close();
    },
  );

  for (final shared in [true, false]) {
    test(
      '${shared ? 'shared' : 'legacy'} retains already-received sibling protection after a header pause',
      () async {
        final transport = _ControlledTransport();
        final now = DateTime.utc(2026, 9, 11);
        final repository = shared
            ? SharedMarketRepository(
                transport: transport,
                concurrency: 2,
                requestSpacing: Duration.zero,
                utcNow: () => now,
              )
            : null;
        final service = shared
            ? null
            : OpportunityMarketService(
                transport: transport,
                concurrency: 2,
                requestSpacing: Duration.zero,
                utcNow: () => now,
              );
        addTearDown(() async {
          await repository?.close();
          service?.close();
        });
        final loading = shared
            ? repository!
                  .fetch(bookKeys: [_key('1'), _key('2'), _key('3')])
                  .then(
                    (batch) => (
                      pause: batch.pauses['eu'],
                      retryable: batch.retryableFailures.length,
                      items: batch.items.length,
                    ),
                  )
            : service!
                  .fetchMarket(quoteIds: const [], bookIds: ['1', '2', '3'])
                  .then(
                    (batch) => (
                      pause: batch.pause,
                      retryable: batch.retryableBookFailures.length,
                      items: batch.items.length,
                    ),
                  );
        await _until(() => transport.responses.length == 2);
        final firstEvidence = Completer<Uint8List>();
        // Both responses have arrived before cancellation can take effect.
        // The ordinary header pause is processed first and cancels its sibling.
        transport.responses[0].complete(
          OpportunityHttpResponse(
            statusCode: 503,
            bytes: Uint8List(0),
            headers: const {'retry-after': '90'},
            protectionBytes: firstEvidence.future,
          ),
        );
        transport.responses[1].complete(
          OpportunityHttpResponse(
            statusCode: 200,
            bytes: Uint8List.fromList(
              utf8.encode('<html>Incapsula incident ID: synthetic</html>'),
            ),
          ),
        );
        await _until(
          () =>
              (repository?.pauseFor('eu') ?? service?.pause)?.reason ==
              MarketRequestPauseReason.protected,
        );
        firstEvidence.complete(Uint8List(0));
        final batch = await loading.timeout(const Duration(seconds: 2));
        expect(batch.pause!.reason, MarketRequestPauseReason.protected);
        expect(batch.pause!.retryAt, now.add(const Duration(seconds: 90)));
        expect(batch.retryable, 0);
        expect(batch.items, 0);
        expect(transport.responses, hasLength(2));
      },
    );
  }

  test(
    'Stop during a denial probe preserves its already received pause',
    () async {
      var cancelled = false;
      final body = StreamController<List<int>>(
        onCancel: () => cancelled = true,
      );
      final client = _Client(
        (_) async => http.StreamedResponse(
          body.stream,
          429,
          headers: {'retry-after': '90'},
        ),
      );
      final repository = SharedMarketRepository(
        transport: HttpOpportunityMarketTransport(client: client),
        concurrency: 1,
        requestSpacing: Duration.zero,
      );
      addTearDown(repository.close);
      final cancellation = MarketCancellationController();
      final loading = repository.fetch(
        bookKeys: [_key('1'), _key('2')],
        cancellationToken: cancellation.token,
      );
      final stopped = expectLater(
        loading,
        throwsA(isA<MarketFetchCancelledException>()),
      );
      await _until(() => repository.pauseFor('eu') != null);
      final pause = repository.pauseFor('eu');
      cancellation.cancel();
      await stopped;
      // A fake client does not implement abort; the probe still ends by itself.
      await _until(() => cancelled);
      expect(repository.pauseFor('eu'), same(pause));
      expect(repository.snapshot('eu').items, isEmpty);
      expect(repository.diagnostics.queuedParts, 0);
      expect(client.requests, hasLength(1));
      await body.close();
    },
  );

  test(
    'recognizes split protective HTML without waiting for the rest',
    () async {
      var cancelled = false;
      final body = StreamController<List<int>>(
        onCancel: () => cancelled = true,
      );
      final transport = HttpOpportunityMarketTransport(
        client: _Client((_) async => http.StreamedResponse(body.stream, 200)),
      );
      addTearDown(transport.close);
      final pending = _post(transport);
      body.add(utf8.encode('<html><body><iframe src="/_Incap'));
      body.add(utf8.encode('sula_Resource?test">'));
      final response = await pending.timeout(const Duration(seconds: 1));
      expect(
        isProtectedMarketResponse(
          bytes: response.bytes,
          headers: response.headers,
        ),
        isTrue,
      );
      expect(response.statusCode, 200);
      expect(cancelled, isTrue);
      await body.close();
    },
  );

  test(
    'ordinary maintenance HTML is not cut short or mislabeled as protection',
    () async {
      final body = StreamController<List<int>>();
      final transport = HttpOpportunityMarketTransport(
        client: _Client(
          (_) async => http.StreamedResponse(
            body.stream,
            503,
            headers: {'content-type': 'text/html'},
          ),
        ),
      );
      addTearDown(transport.close);
      var completed = false;
      final pending = _post(transport).then((value) {
        completed = true;
        return value;
      });
      body.add(utf8.encode('<html><body>Maintenance'));
      await Future<void>.delayed(Duration.zero);
      expect(completed, isFalse);
      body.add(utf8.encode('</body></html>'));
      await body.close();
      final response = await pending;
      expect(
        utf8.decode(response.bytes),
        '<html><body>Maintenance</body></html>',
      );
      expect(
        isProtectedMarketResponse(
          bytes: response.bytes,
          headers: response.headers,
        ),
        isFalse,
      );
    },
  );

  test('healthy binary and JSON body bytes remain unchanged', () async {
    final original = Uint8List.fromList([0, 255, 123, 34, 9, 10, 200, 100]);
    final client = _Client(
      (_) async => http.StreamedResponse(
        Stream.fromIterable([original.sublist(0, 3), original.sublist(3)]),
        200,
      ),
    );
    final transport = HttpOpportunityMarketTransport(client: client);
    final response = await _post(transport);
    expect(response.bytes, original);
    expect(client.requests.single, isA<http.AbortableRequest>());
    expect(client.requests.single.followRedirects, isFalse);
    transport.close();
    expect(client.closed, isTrue);
  });

  test('redirects remain non-success and cannot establish a session', () async {
    var first = true;
    final client = _Client((_) async {
      final redirect = first;
      first = false;
      return http.StreamedResponse(
        const Stream<List<int>>.empty(),
        redirect ? 303 : 200,
        headers: redirect
            ? {
                'location': 'https://other.market.test/redirect',
                'set-cookie': 'redirect=must-not-be-used; Path=/; Secure',
              }
            : {},
      );
    });
    final transport = HttpOpportunityMarketTransport(client: client);
    addTearDown(transport.close);
    final redirect = await _post(transport);
    expect(redirect.statusCode, 303);
    expect(client.requests.single.followRedirects, isFalse);
    await _post(transport);
    expect(client.requests.last.headers['cookie'], isNull);
    expect(transport.requestsWithSessionCookies, 0);
  });

  test('non-protection response size bound remains enforced', () async {
    var cancelled = false;
    final body = StreamController<List<int>>(onCancel: () => cancelled = true);
    final transport = HttpOpportunityMarketTransport(
      client: _Client((_) async => http.StreamedResponse(body.stream, 200)),
    );
    addTearDown(transport.close);
    final pending = expectLater(_post(transport), throwsFormatException);
    body.add(Uint8List(1024 * 1024 + 1));
    await pending;
    expect(cancelled, isTrue);
    await body.close();
  });

  test('healthy server session is returned only to the same origin', () async {
    final client = _Client(
      (request) async => http.StreamedResponse(
        Stream.value(
          utf8.encode('{"resultCode":0,"resultMsg":"1-0-0-100-10-1000"}'),
        ),
        200,
        headers: {
          'set-cookie': 'session=server-issued; Path=/; Secure; HttpOnly',
        },
      ),
    );
    final transport = HttpOpportunityMarketTransport(client: client);
    addTearDown(transport.close);
    Future<void> read(String host) async => transport.post(
      Uri.https(host, '/Trademarket/GetWorldMarketSubList'),
      headers: const {},
      body: '{}',
    );
    await read('eu-trade.naeu.playblackdesert.com');
    await read('eu-trade.naeu.playblackdesert.com');
    await read('na-trade.naeu.playblackdesert.com');
    expect(client.requests[0].headers['cookie'], isNull);
    expect(client.requests[1].headers['cookie'], 'session=server-issued');
    expect(client.requests[2].headers['cookie'], isNull);
    expect(transport.requestsWithSessionCookies, 1);
  });

  for (final denial in [200, 403, 429, 503]) {
    test('does not acquire session cookies from denial $denial', () async {
      var count = 0;
      final client = _Client((_) async {
        final first = count++ == 0;
        return http.StreamedResponse(
          Stream.value(
            utf8.encode(
              first
                  ? '<html><iframe src="/_Incapsula_Resource?test"></iframe></html>'
                  : '{"resultCode":0,"resultMsg":"ok"}',
            ),
          ),
          first ? denial : 200,
          headers: first
              ? {
                  'set-cookie': 'challenge=must-not-be-used; Path=/; Secure',
                  'content-type': 'text/html',
                  if (denial == 503) 'retry-after': '120',
                }
              : {},
        );
      });
      final transport = HttpOpportunityMarketTransport(client: client);
      addTearDown(transport.close);
      // Transport-only synthetic fixture; the real repository latches denials
      // and never issues this follow-up while access is blocked.
      final denialResponse = await _post(transport);
      final evidence = await denialResponse.protectionBytes;
      expect(
        isProtectedMarketResponse(
          bytes: evidence ?? denialResponse.bytes,
          headers: denialResponse.headers,
        ),
        isTrue,
      );
      await _post(transport);
      expect(client.requests.last.headers['cookie'], isNull);
      expect(transport.requestsWithSessionCookies, 0);
    });
  }

  test(
    'large initial protective chunk is recognized without body completion',
    () async {
      var cancelled = false;
      final body = StreamController<List<int>>(
        onCancel: () => cancelled = true,
      );
      final client = _Client(
        (_) async => http.StreamedResponse(body.stream, 200),
      );
      final transport = HttpOpportunityMarketTransport(client: client);
      addTearDown(transport.close);
      final pending = _post(transport);
      body.add(
        utf8.encode(
          '<html><iframe src="/_Incapsula_Resource?test">${' ' * 70000}',
        ),
      );
      final result = await pending.timeout(const Duration(seconds: 1));
      expect(isProtectedMarketResponse(bytes: result.bytes), isTrue);
      expect(cancelled, isTrue);
      await body.close();
    },
  );
}

SharedMarketKey _key(String itemId) =>
    SharedMarketKey(region: 'eu', itemId: itemId);

Future<void> _until(bool Function() completed) async {
  final deadline = DateTime.now().add(const Duration(seconds: 2));
  while (!completed() && DateTime.now().isBefore(deadline)) {
    await Future<void>.delayed(const Duration(milliseconds: 1));
  }
  expect(
    completed(),
    isTrue,
    reason: 'The expected asynchronous state did not arrive',
  );
}

Future<OpportunityHttpResponse> _post(OpportunityMarketTransport transport) =>
    transport.post(
      Uri.https('market.test', '/orders'),
      headers: const {'Content-Type': 'application/json'},
      body: '{}',
    );

final class _Client extends http.BaseClient {
  _Client(this.respond);
  final Future<http.StreamedResponse> Function(http.BaseRequest) respond;
  final requests = <http.BaseRequest>[];
  bool closed = false;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    requests.add(request);
    return respond(request);
  }

  @override
  void close() => closed = true;
}

final class _ControlledTransport implements OpportunityMarketTransport {
  final responses = <Completer<OpportunityHttpResponse>>[];

  @override
  Future<OpportunityHttpResponse> post(
    Uri uri, {
    required Map<String, String> headers,
    required String body,
    Future<void>? abortTrigger,
  }) {
    final response = Completer<OpportunityHttpResponse>();
    responses.add(response);
    return response.future;
  }

  @override
  void close() {}
}
