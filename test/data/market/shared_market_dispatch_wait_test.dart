import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:bdo_craft_planner_flutter/data/market/market_request_pacer.dart';
import 'package:bdo_craft_planner_flutter/data/market/shared_market_repository.dart';
import 'package:bdo_craft_planner_flutter/data/opportunities/opportunity_market_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'active wait belongs only to queued region and exact scan parts',
    () async {
      final transport = _Transport();
      final broker = SharedMarketRepository(
        transport: transport,
        requestSpacing: Duration.zero,
        requestWindowLimit: 1,
        requestWindowDuration: const Duration(seconds: 2),
      );
      addTearDown(broker.close);
      final work = broker.fetch(bookKeys: [_key('1'), _key('2')]);
      await _turn();
      expect(transport.starts, 1);
      expect(broker.diagnostics.queuedParts, 1);
      final wait = broker.activeDispatchWait(region: 'eu', parts: [_book('2')]);
      expect(wait, greaterThan(Duration.zero));
      expect(wait, lessThanOrEqualTo(const Duration(seconds: 2)));
      expect(broker.activeDispatchWait(region: 'na'), Duration.zero);
      expect(
        broker.activeDispatchWait(region: 'eu', parts: [_book('1')]),
        Duration.zero,
      );
      expect(broker.activeDispatchWait(region: 'eu', parts: []), Duration.zero);
      expect(transport.starts, 1);
      final result = await work;
      expect(result.failures, isEmpty);
      expect(transport.starts, 2);
      expect(broker.activeDispatchWait(region: 'eu'), Duration.zero);
    },
  );

  test(
    'cache freshness and new-refresh admission are not active queue waits',
    () async {
      final broker = SharedMarketRepository(
        transport: _Transport(),
        requestSpacing: Duration.zero,
        minimumBookRefreshAge: const Duration(minutes: 1),
        requestWindowLimit: 1,
      );
      addTearDown(broker.close);
      await broker.fetch(bookKeys: [_key('1')]);
      expect(
        broker.refreshReadiness(region: 'eu', bookKeys: [_key('1')]).wait,
        greaterThan(Duration.zero),
      );
      expect(broker.activeDispatchWait(region: 'eu'), Duration.zero);
      await broker.fetch(bookKeys: [_key('1')], forceRefresh: true);
      expect(broker.diagnostics.startedRequests, 1);
      expect(broker.activeDispatchWait(region: 'eu'), Duration.zero);
    },
  );

  test(
    'releasing a queued part clears its countdown without dispatching it',
    () async {
      final scope = SharedMarketRequestScope();
      final transport = _Transport();
      final broker = SharedMarketRepository(
        transport: transport,
        requestSpacing: Duration.zero,
        requestWindowLimit: 1,
        requestWindowDuration: const Duration(seconds: 10),
      );
      addTearDown(broker.close);
      final work = broker.fetch(bookKeys: [_key('1'), _key('2')], scope: scope);
      await _turn();
      expect(
        broker.activeDispatchWait(region: 'eu'),
        greaterThan(Duration.zero),
      );
      scope.release([_book('2')]);
      await work;
      expect(broker.activeDispatchWait(region: 'eu'), Duration.zero);
      expect(transport.starts, 1);
    },
  );

  test(
    'held HTTP has no invented countdown when no timed gate blocks it',
    () async {
      final held = Completer<OpportunityHttpResponse>();
      final broker = SharedMarketRepository(
        transport: _Transport(
          response: (index) async => index == 1 ? held.future : _success(),
        ),
        concurrency: 1,
        requestSpacing: Duration.zero,
      );
      addTearDown(broker.close);
      final work = broker.fetch(bookKeys: [_key('1'), _key('2')]);
      await _turn();
      expect(broker.diagnostics.activeRequests, 1);
      expect(broker.diagnostics.queuedParts, 1);
      expect(broker.activeDispatchWait(region: 'eu'), Duration.zero);
      held.complete(_success());
      await work;
    },
  );

  test(
    'queued provider deadline is visible only until that queue is failed',
    () async {
      final evidence = Completer<Uint8List>();
      final broker = SharedMarketRepository(
        transport: _Transport(
          response: (_) async => OpportunityHttpResponse(
            statusCode: 503,
            bytes: Uint8List(0),
            headers: const {'retry-after': '10'},
            protectionBytes: evidence.future,
          ),
        ),
        concurrency: 1,
        requestSpacing: Duration.zero,
      );
      addTearDown(broker.close);
      final work = broker.fetch(bookKeys: [_key('1'), _key('2')]);
      await _turn();
      expect(broker.pauseFor('eu'), isNotNull);
      expect(
        broker.activeDispatchWait(region: 'eu'),
        greaterThan(const Duration(seconds: 9)),
      );
      evidence.complete(Uint8List(0));
      await work;
      expect(broker.pauseFor('eu'), isNotNull);
      expect(broker.activeDispatchWait(region: 'eu'), Duration.zero);
    },
  );

  test('pacer observation includes next, previous and shared-window waits', () {
    var windowWait = Duration.zero;
    var wakes = 0;
    final pacer = MarketRequestPacer(
      const Duration(milliseconds: 40),
      requestWindowDelay: () => windowWait,
      onReady: () => wakes++,
    );
    addTearDown(pacer.close);
    expect(pacer.remainingDelayFor(const Duration(seconds: 1)), Duration.zero);
    pacer.started(minimumInterval: const Duration(seconds: 2));
    expect(
      pacer.remainingDelayFor(Duration.zero),
      greaterThan(const Duration(seconds: 1)),
    );
    expect(
      pacer.remainingDelayFor(const Duration(seconds: 4)),
      greaterThan(const Duration(seconds: 3)),
    );
    windowWait = const Duration(seconds: 20);
    expect(pacer.remainingDelayFor(Duration.zero), windowWait);
    expect(wakes, 0);
    pacer.close();
    expect(pacer.remainingDelayFor(Duration.zero), Duration.zero);
  });
}

SharedMarketKey _key(String id) => SharedMarketKey(region: 'eu', itemId: id);
SharedMarketPartKey _book(String id) =>
    SharedMarketPartKey(_key(id), SharedMarketPart.orderBook);
Future<void> _turn() => Future<void>.delayed(Duration.zero);
OpportunityHttpResponse _success() => OpportunityHttpResponse(
  statusCode: 200,
  bytes: Uint8List.fromList(
    utf8.encode(jsonEncode({'resultCode': 0, 'resultMsg': '100-3-0|90-0-7'})),
  ),
);

class _Transport implements OpportunityMarketTransport {
  _Transport({this.response});
  final Future<OpportunityHttpResponse> Function(int)? response;
  int starts = 0;
  @override
  Future<OpportunityHttpResponse> post(
    Uri uri, {
    required Map<String, String> headers,
    required String body,
    Future<void>? abortTrigger,
  }) async {
    starts++;
    return response == null ? _success() : response!(starts);
  }

  @override
  void close() {}
}
