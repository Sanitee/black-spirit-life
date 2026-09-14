import 'dart:convert';
import 'dart:typed_data';

import '../../domain/catalog/enhanceable_market_items.dart';
import '../../domain/opportunities/opportunity_market_models.dart';

final class OpportunityBulkQuotes {
  OpportunityBulkQuotes({
    required Map<String, OpportunityMarketItem> items,
    required Map<String, String> failures,
  }) : items = Map.unmodifiable(items),
       failures = Map.unmodifiable(failures);

  final Map<String, OpportunityMarketItem> items;
  final Map<String, String> failures;
}

/// PA's GetWorldMarketSearchList returns id-stock-basePrice-totalTrades.
/// Verified against a complete 200-ID, 999-character EU request on 2026-09-11.
/// This summary has no order levels or last-sale time; neither is inferred from
/// stock or trades. Request packing also respects the separate string bound.
OpportunityBulkQuotes decodeOpportunityBulkQuotes({
  required Uint8List bytes,
  required Iterable<String> requestedIds,
  required DateTime fetchedAt,
}) {
  if (bytes.isEmpty || bytes.length > 1024 * 1024) {
    throw const FormatException('Invalid bulk quote size');
  }
  final root = jsonDecode(utf8.decode(bytes));
  if (root is! Map || root['resultCode'] != 0 || root['resultMsg'] is! String) {
    throw const FormatException('Market returned an unsuccessful response');
  }
  final requested = requestedIds.toSet();
  final items = <String, OpportunityMarketItem>{};
  final failures = <String, String>{
    for (final id in requested) id: 'Price unavailable',
  };
  final seen = <String>{};
  for (final row in (root['resultMsg'] as String).split('|')) {
    if (row.isEmpty) continue;
    final fields = row.split('-');
    final id = fields.first;
    if (!requested.contains(id)) continue;
    if (!seen.add(id)) {
      items.remove(id);
      failures[id] = 'Price unavailable';
      continue;
    }
    if (fields.length != 4) continue;
    final stock = _nonnegative(fields[1]);
    final price = _nonnegative(fields[2]);
    final trades = _nonnegative(fields[3]);
    if (stock == null || price == null || price == 0 || trades == null) {
      continue;
    }
    items[id] = OpportunityMarketItem(
      itemId: id,
      stock: isEnhanceableMarketItemId(id) ? null : stock,
      aggregateStock: isEnhanceableMarketItemId(id) ? stock : null,
      basePrice: price,
      totalTrades: trades,
      quoteFetchedAt: fetchedAt.toUtc(),
    );
    failures.remove(id);
  }
  return OpportunityBulkQuotes(items: items, failures: failures);
}

int? _nonnegative(String text) {
  if (!RegExp(r'^\d+$').hasMatch(text)) return null;
  final value = int.tryParse(text);
  return value != null && value >= 0 ? value : null;
}
