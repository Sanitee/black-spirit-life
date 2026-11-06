import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:bdo_craft_planner_flutter/data/opportunities/opportunity_market_service.dart';

/// Entirely synthetic receipts. Never contacts a market or reads a profile.
class ChoiceMarketTransport implements OpportunityMarketTransport {
  final requests = <({String region, bool book, List<String> ids})>[];
  final values = <String, ({int price, int stock, int preorders})>{};
  Completer<void>? hold;
  bool aborted = false;
  @override
  Future<OpportunityHttpResponse> post(
    Uri uri, {
    required Map<String, String> headers,
    required String body,
    Future<void>? abortTrigger,
  }) async {
    final payload = jsonDecode(body) as Map<String, dynamic>;
    final bulk = payload['searchResult'] is String;
    final ids = bulk
        ? (payload['searchResult'] as String).split(',')
        : ['${payload['mainKey']}'];
    final book = uri.path.endsWith('GetBiddingInfoList');
    requests.add((
      region: uri.host.startsWith('eu-') ? 'eu' : 'na',
      book: book,
      ids: ids,
    ));
    if (hold != null) {
      await Future.any([
        hold!.future,
        if (abortTrigger != null)
          abortTrigger.then((_) {
            aborted = true;
            throw const MarketFetchCancelledException();
          }),
      ]);
    }
    ({int price, int stock, int preorders}) item(String id) =>
        values[id] ?? (price: 480, stock: 12594, preorders: 0);
    final value = item(ids.first);
    final result = book
        ? '${value.price}-${value.stock}-${value.preorders}'
        : bulk
        ? ids
              .map((id) {
                final v = item(id);
                return '$id-${v.stock}-${v.price}-100000';
              })
              .join('|')
        : '${ids.single}-0-0-${value.price}-${value.stock}-100000';
    return OpportunityHttpResponse(
      statusCode: 200,
      bytes: Uint8List.fromList(
        utf8.encode(jsonEncode({'resultCode': 0, 'resultMsg': result})),
      ),
    );
  }

  @override
  void close() {}
}
