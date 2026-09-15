import 'dart:convert';
import 'dart:typed_data';

import 'package:bdo_craft_planner_flutter/data/market/shared_market_price_gateway.dart';
import 'package:bdo_craft_planner_flutter/data/market/shared_market_repository.dart';
import 'package:bdo_craft_planner_flutter/data/opportunities/opportunity_market_service.dart';
import 'package:bdo_craft_planner_flutter/domain/market/market_price_models.dart';
import 'package:bdo_craft_planner_flutter/features/gathering/shared_gathering_market_loader.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final adapter in [
    'Planner/Map',
    'Gathering Value',
    'Gathering Demand',
  ]) {
    test(
      '$adapter preserves automatic versus manual intent and server wait',
      () async {
        var now = DateTime.utc(2026, 9, 10, 12);
        final transport = _Transport();
        final repository = SharedMarketRepository(
          transport: transport,
          requestSpacing: Duration.zero,
          utcNow: () => now,
        );
        addTearDown(repository.close);
        final initial = await repository.fetch(
          quoteKeys: [SharedMarketKey(region: 'eu', itemId: '999')],
        );
        expect(initial.pause!.reason, MarketRequestPauseReason.protected);
        expect(transport.calls, 1);
        Future<bool> load(bool force) async {
          if (adapter == 'Planner/Map') {
            final result =
                await SharedMarketPriceGateway(
                  repository: repository,
                ).fetchProgressive(
                  const [MarketPriceRequest(name: 'Item', id: '1')],
                  region: 'eu',
                  forceRefresh: force,
                );
            return result.items.single.ok;
          }
          final result =
              await SharedGatheringMarketLoader(repository: repository).load(
                {'1': 'Item'},
                includePreorders: adapter == 'Gathering Demand',
                forceRefresh: force,
                onItem: (_) {},
              );
          return result.priceFailures.isEmpty &&
              result.preorderFailures.isEmpty;
        }

        expect(await load(false), isFalse);
        now = now.add(const Duration(seconds: 30));
        expect(await load(true), isFalse);
        expect(transport.calls, 1);
        now = now.add(const Duration(seconds: 31));
        expect(await load(false), isFalse);
        expect(transport.calls, 1);
        expect(await load(true), isTrue);
        expect(transport.calls, adapter == 'Planner/Map' ? 2 : 3);
        expect(repository.pauseFor('eu'), isNull);
      },
    );
  }
}

final class _Transport implements OpportunityMarketTransport {
  int calls = 0;
  @override
  Future<OpportunityHttpResponse> post(
    Uri uri, {
    required Map<String, String> headers,
    required String body,
    Future<void>? abortTrigger,
  }) async {
    calls++;
    if (calls == 1) {
      return OpportunityHttpResponse(
        statusCode: 200,
        headers: {'content-type': 'text/html', 'retry-after': '60'},
        bytes: Uint8List.fromList(
          utf8.encode(
            '<html><iframe src="/_Incapsula_Resource"></iframe></html>',
          ),
        ),
      );
    }
    final request = jsonDecode(body) as Map;
    final book = uri.path.endsWith('GetBiddingInfoList');
    return OpportunityHttpResponse(
      statusCode: 200,
      bytes: Uint8List.fromList(
        utf8.encode(
          jsonEncode({
            'resultCode': 0,
            'resultMsg': book
                ? '100-0-7'
                : '${request['mainKey']}-0-0-100-0-1000',
          }),
        ),
      ),
    );
  }

  @override
  void close() {}
}
