import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:bdo_craft_planner_flutter/data/market/shared_market_repository.dart';
import 'package:bdo_craft_planner_flutter/data/opportunities/opportunity_market_service.dart';
import 'package:bdo_craft_planner_flutter/features/gathering/shared_gathering_market_loader.dart';
import 'package:bdo_gathering_companion/bdo_gathering_companion.dart';
import 'package:flutter_test/flutter_test.dart';

class _Transport implements OpportunityMarketTransport {
  final requests = <({Uri uri, Map<String, dynamic> body})>[];
  final stock = <String, int>{'1': 0, '2': 100};
  final gates = <String, Completer<void>>{};
  bool malformedBook = false;
  String bookMessage = '30000-0-123|';
  bool closed = false;

  @override
  Future<OpportunityHttpResponse> post(
    Uri uri, {
    required Map<String, String> headers,
    required String body,
    Future<void>? abortTrigger,
  }) async {
    final parsed = jsonDecode(body) as Map<String, dynamic>;
    requests.add((uri: uri, body: parsed));
    final id = '${parsed['mainKey']}';
    final book = uri.path.endsWith('GetBiddingInfoList');
    if (!book) await gates[id]?.future;
    final ids = parsed['searchResult']?.toString().split(',') ?? [id];
    final message = book
        ? (malformedBook ? 'invalid' : bookMessage)
        : ids.length > 1
        ? ids.map((id) => '$id-${stock[id] ?? 100}-30000-900|').join()
        : '$id-0-0-30000-${stock[id] ?? 100}-900|';
    return OpportunityHttpResponse(
      statusCode: 200,
      bytes: Uint8List.fromList(
        utf8.encode(jsonEncode({'resultCode': 0, 'resultMsg': message})),
      ),
    );
  }

  @override
  void close() => closed = true;
}

SharedMarketKey _key(String id, [String region = 'eu']) =>
    SharedMarketKey(region: region, itemId: id);

Future<void> _dispatch() async {
  for (var frame = 0; frame < 8; frame++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  for (final includePreorders in [false, true]) {
    for (final ageSeconds in [59, 60]) {
      final mode = includePreorders ? 'Demand' : 'Value';
      test(
        '$mode minute-policy Refresh at ${ageSeconds}s reuses only recent quotes and books',
        () async {
          final transport = _Transport()..bookMessage = '30000-0-0|';
          var now = DateTime.utc(2026, 9, 11, 12);
          final original = now;
          final repository = SharedMarketRepository(
            transport: transport,
            utcNow: () => now,
            requestSpacing: Duration.zero,
            minimumQuoteRefreshAge: const Duration(minutes: 1),
            minimumBookRefreshAge: const Duration(minutes: 1),
          );
          addTearDown(repository.close);
          final id = includePreorders ? '2' : '1';
          await repository.fetch(quoteKeys: [_key(id)], bookKeys: [_key(id)]);
          transport.requests.clear();
          transport.bookMessage = '30000-0-7|';
          now = now.add(Duration(seconds: ageSeconds));
          final receipts = <GatheringMarketReceipt>[];
          final result =
              await SharedGatheringMarketLoader(repository: repository).load(
                {id: 'Item'},
                includePreorders: includePreorders,
                forceRefresh: true,
                onItem: receipts.add,
              );
          final reused = ageSeconds < 60;
          expect(transport.requests, hasLength(reused ? 0 : 2));
          if (!reused) {
            expect(
              transport.requests.where(
                (request) => request.uri.path.endsWith('GetBiddingInfoList'),
              ),
              hasLength(1),
            );
          }
          expect(result.priceFailures, isEmpty);
          expect(result.preorderFailures, isEmpty);
          final quote = receipts.singleWhere(
            (receipt) => receipt.price != null,
          );
          final book = receipts.singleWhere(
            (receipt) => receipt.preorders != null,
          );
          expect(quote.quoteFetchedAt, reused ? original : now);
          expect(book.preorderFetchedAt, reused ? original : now);
          expect(book.preorders, reused ? 0 : 7);
          final stored = repository.snapshot('eu').items[id]!;
          expect(stored.quoteFetchedAt, reused ? original : now);
          expect(stored.bookFetchedAt, reused ? original : now);
        },
      );
    }
  }

  test(
    'recent Gathering quote does not conceal a missing failed book',
    () async {
      final transport = _Transport()..malformedBook = true;
      var now = DateTime.utc(2026, 9, 11, 12);
      final original = now;
      final repository = SharedMarketRepository(
        transport: transport,
        utcNow: () => now,
        requestSpacing: Duration.zero,
        minimumQuoteRefreshAge: const Duration(minutes: 1),
        minimumBookRefreshAge: const Duration(minutes: 1),
      );
      addTearDown(repository.close);
      await repository.fetch(quoteKeys: [_key('2')]);
      transport.requests.clear();
      now = now.add(const Duration(seconds: 30));
      final receipts = <GatheringMarketReceipt>[];
      final result = await SharedGatheringMarketLoader(repository: repository)
          .load(
            {'2': 'Item'},
            includePreorders: true,
            forceRefresh: true,
            onItem: receipts.add,
          );
      expect(transport.requests, hasLength(1));
      expect(
        transport.requests.single.uri.path.endsWith('GetBiddingInfoList'),
        isTrue,
      );
      expect(result.priceFailures, isEmpty);
      expect(result.preorderFailures, {'2'});
      expect(receipts.single.quoteFetchedAt, original);
      expect(receipts.single.preorders, isNull);
      expect(repository.snapshot('eu').items['2']!.bookFetchedAt, isNull);
    },
  );

  for (final includePreorders in [false, true]) {
    for (final ageMilliseconds in [59999, 60000, 61000]) {
      for (final buyers in [0, 123]) {
        final mode = includePreorders ? 'Demand' : 'Value';
        test(
          '$mode Refresh at ${ageMilliseconds}ms keeps accurate book age and $buyers buyers',
          () async {
            final transport = _Transport()..bookMessage = '30000-0-$buyers|';
            var now = DateTime.utc(2026, 9, 11, 12);
            final original = now;
            final repository = SharedMarketRepository(
              transport: transport,
              utcNow: () => now,
              requestSpacing: Duration.zero,
              minimumBookRefreshAge: const Duration(minutes: 1),
            );
            addTearDown(repository.close);
            // Value requests books for zero stock; Demand also requests them
            // for stocked items. Both must apply the shared reuse policy.
            final id = includePreorders ? '2' : '1';
            await repository.fetch(quoteKeys: [_key(id)], bookKeys: [_key(id)]);
            transport.requests.clear();
            transport.bookMessage = '30000-0-${buyers + 7}|';
            now = now.add(Duration(milliseconds: ageMilliseconds));
            final receipts = <GatheringMarketReceipt>[];
            final result =
                await SharedGatheringMarketLoader(repository: repository).load(
                  {id: 'Item'},
                  includePreorders: includePreorders,
                  forceRefresh: true,
                  onItem: receipts.add,
                );
            final reused = ageMilliseconds < 60000;
            expect(result.priceFailures, isEmpty);
            expect(result.preorderFailures, isEmpty);
            expect(
              transport.requests.where(
                (request) => !request.uri.path.endsWith('GetBiddingInfoList'),
              ),
              hasLength(1),
            );
            expect(
              transport.requests.where(
                (request) => request.uri.path.endsWith('GetBiddingInfoList'),
              ),
              hasLength(reused ? 0 : 1),
            );
            final quote = receipts.singleWhere(
              (receipt) => receipt.price != null,
            );
            final book = receipts.singleWhere(
              (receipt) => receipt.preorders != null,
            );
            expect(quote.quoteFetchedAt, now);
            expect(quote.stock, includePreorders ? 100 : 0);
            expect(book.preorders, reused ? buyers : buyers + 7);
            expect(book.preorderFetchedAt, reused ? original : now);
            expect(
              repository.snapshot('eu').items[id]!.bookFetchedAt,
              reused ? original : now,
            );
          },
        );
      }
    }
  }

  test(
    'archived historical session items are skipped without failure or mutation',
    () async {
      final transport = _Transport();
      final repository = SharedMarketRepository(
        transport: transport,
        requestSpacing: Duration.zero,
      );
      addTearDown(repository.close);
      final loader = SharedGatheringMarketLoader(repository: repository);
      final items = <String, String>{
        '006211': 'Historical Monkey Blood',
        '6011': 'Monkey Hide',
        '6007': 'Dinosaur Hide',
        '15202': 'Black Magic Crystal - Power',
        '15208': 'Black Magic Crystal - Patience',
        '15209': 'Black Magic Crystal - Healing',
        '15210': 'Black Magic Crystal - Resonance',
        '15215': 'Black Magic Crystal - Endurance',
      };
      final before = Map<String, String>.of(items);
      final receipts = <GatheringMarketReceipt>[];
      for (final force in [false, true]) {
        for (final includePreorders in [false, true]) {
          final result = await loader.load(
            items,
            includePreorders: includePreorders,
            forceRefresh: force,
            onItem: receipts.add,
          );
          expect(result.priceFailures, isEmpty);
          expect(result.preorderFailures, isEmpty);
        }
      }
      expect(transport.requests, isEmpty);
      expect(receipts, isEmpty);
      expect(items, before);
    },
  );

  test('archive skips exact IDs while live and custom remaps load', () async {
    final transport = _Transport();
    final repository = SharedMarketRepository(
      transport: transport,
      requestSpacing: Duration.zero,
    );
    addTearDown(repository.close);
    final receipts = <GatheringMarketReceipt>[];
    final result = await SharedGatheringMarketLoader(repository: repository)
        .load(
          {
            '6211': 'Saved alias',
            '7011': 'Monkey Blood',
            '999999999': 'Custom material',
          },
          includePreorders: true,
          forceRefresh: true,
          onItem: receipts.add,
        );
    expect(result.priceFailures, isEmpty);
    expect(result.preorderFailures, isEmpty);
    expect(receipts.map((receipt) => receipt.itemId).toSet(), {
      '7011',
      '999999999',
    });
    final requestedIds = {
      for (final request in transport.requests)
        ...(request.body['searchResult']?.toString().split(',') ??
            ['${request.body['mainKey']}']),
    };
    expect(requestedIds, {'7011', '999999999'});
  });

  test(
    'Value starts only zero-stock books before slower prices finish',
    () async {
      final transport = _Transport()..gates['2'] = Completer<void>();
      final repository = SharedMarketRepository(
        transport: transport,
        quoteBatchSize: 1,
        requestSpacing: Duration.zero,
      );
      addTearDown(repository.close);
      final loader = SharedGatheringMarketLoader(repository: repository);
      final receipts = <GatheringMarketReceipt>[];
      final loading = loader.load(
        {'1': 'First', '2': 'Second'},
        includePreorders: false,
        forceRefresh: false,
        onItem: receipts.add,
      );
      await _dispatch();
      expect(receipts.any((receipt) => receipt.preorders == 123), isTrue);
      expect(
        transport.requests
            .where((request) => request.uri.path.endsWith('GetBiddingInfoList'))
            .map((request) => request.body['mainKey']),
        [1],
      );
      transport.gates['2']!.complete();
      final result = await loading;
      expect(result.priceFailures, isEmpty);
      expect(result.preorderFailures, isEmpty);
      expect(
        receipts.where((receipt) => receipt.itemId == '2').single.stock,
        100,
      );
    },
  );

  test(
    'cached receipts retain original times and Refresh alone bypasses them',
    () async {
      final transport = _Transport();
      var now = DateTime.utc(2026, 9, 10, 9);
      final original = now;
      final repository = SharedMarketRepository(
        transport: transport,
        utcNow: () => now,
        requestSpacing: Duration.zero,
      );
      addTearDown(repository.close);
      await repository.fetch(quoteKeys: [_key('1')], bookKeys: [_key('1')]);
      final before = transport.requests.length;
      now = now.add(const Duration(hours: 2));
      final loader = SharedGatheringMarketLoader(repository: repository);
      final receipts = <GatheringMarketReceipt>[];
      await loader.load(
        {'1': 'First'},
        includePreorders: true,
        forceRefresh: false,
        onItem: receipts.add,
      );
      expect(transport.requests, hasLength(before));
      expect(
        receipts.singleWhere((receipt) => receipt.price != null).quoteFetchedAt,
        original,
      );
      expect(
        receipts
            .singleWhere((receipt) => receipt.preorders != null)
            .preorderFetchedAt,
        original,
      );
      await loader.load(
        {'1': 'First'},
        includePreorders: true,
        forceRefresh: true,
        onItem: (_) {},
      );
      expect(transport.requests, hasLength(before + 2));
    },
  );

  test(
    'Demand requests books for stocked items and preserves unknown failures',
    () async {
      final transport = _Transport()..malformedBook = true;
      final repository = SharedMarketRepository(
        transport: transport,
        requestSpacing: Duration.zero,
      );
      addTearDown(repository.close);
      final receipts = <GatheringMarketReceipt>[];
      final result = await SharedGatheringMarketLoader(repository: repository)
          .load(
            {'2': 'Second'},
            includePreorders: true,
            forceRefresh: false,
            onItem: receipts.add,
          );
      expect(result.priceFailures, isEmpty);
      expect(result.preorderFailures, {'2'});
      expect(receipts.single.stock, 100);
      expect(receipts.single.preorders, isNull);
      expect(
        transport.requests.where(
          (request) => request.uri.path.endsWith('GetBiddingInfoList'),
        ),
        hasLength(1),
      );
    },
  );

  test(
    'cancelling Gathering leaves an overlapping sibling request alive',
    () async {
      final gate = Completer<void>();
      final transport = _Transport()..gates['2'] = gate;
      final repository = SharedMarketRepository(
        transport: transport,
        requestSpacing: Duration.zero,
      );
      addTearDown(repository.close);
      final cancelled = Completer<void>();
      final gathering = SharedGatheringMarketLoader(repository: repository)
          .load(
            {'2': 'Second'},
            includePreorders: false,
            forceRefresh: false,
            cancelled: cancelled.future,
            onItem: (_) {},
          );
      final sibling = repository.fetch(quoteKeys: [_key('2')]);
      await _dispatch();
      final detached = expectLater(
        gathering,
        throwsA(isA<MarketFetchCancelledException>()),
      );
      cancelled.complete();
      await detached;
      expect(transport.closed, isFalse);
      gate.complete();
      expect((await sibling).items[_key('2')]?.basePrice, 30000);
      expect(transport.requests, hasLength(1));
    },
  );

  test(
    'sibling stream is region filtered and uses explicit base-item keys',
    () async {
      final transport = _Transport();
      final repository = SharedMarketRepository(
        transport: transport,
        requestSpacing: Duration.zero,
      );
      addTearDown(repository.close);
      final loader = SharedGatheringMarketLoader(
        repository: repository,
        region: 'EU',
      );
      final receipts = <GatheringMarketReceipt>[];
      final subscription = loader.updates.listen(receipts.add);
      addTearDown(subscription.cancel);
      await repository.fetch(quoteKeys: [_key('1', 'na')]);
      await repository.fetch(bookKeys: [_key('1')]);
      await _dispatch();
      expect(receipts, hasLength(1));
      expect(receipts.single.preorders, 123);
      expect(receipts.single.price, isNull);
      expect(transport.requests.last.body['subKey'], 0);
    },
  );
}
