import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../../domain/catalog/enhanceable_market_items.dart';
import '../../domain/opportunities/opportunity_market_models.dart';
import '../persistence/atomic_file_store.dart';

/// Raw, independently dated market receipts. No account settings or calculated
/// profits are stored here. Expiration is enforced by the consuming controller.
final class OpportunityMarketCacheStore {
  OpportunityMarketCacheStore({
    required Directory directory,
    DateTime Function()? utcNow,
    AtomicFileCommitter committer = const RenameAtomicFileCommitter(),
  }) : _clock = utcNow ?? DateTime.now,
       _file = AtomicFileStore(
         directory: directory,
         fileName: 'opportunity-market-cache.json',
         utcNow: utcNow,
         committer: committer,
         preserveMalformedTarget: true,
       );

  static const _maxBytes = 64 * 1024 * 1024;
  static const _maxItems = 20000;
  static const _maxLevels = 10000;
  final DateTime Function() _clock;
  final AtomicFileStore _file;

  String get path => _file.targetPath;

  Future<Map<String, Map<String, OpportunityMarketItem>>> load() async {
    final file = File(path);
    if (!await file.exists()) return {};
    if (await file.length() > _maxBytes) {
      throw const FormatException('Market cache is too large');
    }
    final decoded = _decode(await file.readAsBytes());
    final now = _clock();
    // A future receipt must never become valid later merely by waiting. Keep a
    // valid other half of the item, but discard the future part on hydration.
    final result = <String, Map<String, OpportunityMarketItem>>{};
    for (final region in decoded.entries) {
      final items = <String, OpportunityMarketItem>{};
      for (final entry in region.value.entries) {
        final item = _withoutFuture(entry.value, now);
        if (item != null) items[entry.key] = item;
      }
      result[region.key] = items;
    }
    return result;
  }

  Future<void> save(
    Map<String, Map<String, OpportunityMarketItem>> regions,
  ) async {
    await _file.writeJson({
      'version': 1,
      'source': 'pearl-abyss',
      'regions': {
        for (final region in regions.entries)
          region.key: {
            for (final entry in region.value.entries)
              entry.key: _encode(entry.value),
          },
      },
    }, validate: _decode);
  }

  static Map<String, Object?> _encode(OpportunityMarketItem item) => {
    'itemId': item.itemId,
    'subId': item.subId,
    'basePrice': item.basePrice,
    'stock': item.stock,
    'aggregateStock': item.aggregateStock,
    'stockScope': item.aggregateStock == null ? 'item' : 'allEnhancements',
    'quoteFetchedAt': item.quoteFetchedAt?.millisecondsSinceEpoch,
    'asks': _encodeLevels(item.asks),
    'bids': _encodeLevels(item.bids),
    'bookFetchedAt': item.bookFetchedAt?.millisecondsSinceEpoch,
    'totalTrades': item.totalTrades,
    'lastSoldAt': item.lastSoldAt?.millisecondsSinceEpoch,
    'unlisted': item.unlisted,
  };

  static Object? _encodeLevels(List<OpportunityMarketLevel>? levels) =>
      levels == null
      ? null
      : [
          for (final level in levels) [level.price, level.quantity],
        ];

  static Map<String, Map<String, OpportunityMarketItem>> _decode(
    Uint8List bytes,
  ) {
    if (bytes.length > _maxBytes) {
      throw const FormatException('Market cache is too large');
    }
    final root = jsonDecode(utf8.decode(bytes));
    if (root is! Map ||
        root['version'] != 1 ||
        root['source'] != 'pearl-abyss' ||
        root['regions'] is! Map) {
      throw const FormatException('Unsupported market cache');
    }
    final regions = root['regions'] as Map;
    final result = <String, Map<String, OpportunityMarketItem>>{};
    var count = 0;
    for (final region in regions.entries) {
      if (!const ['eu', 'na'].contains(region.key) || region.value is! Map) {
        throw const FormatException('Invalid market cache region');
      }
      final items = region.value as Map;
      count += items.length;
      if (count > _maxItems) {
        throw const FormatException('Too many cached market items');
      }
      final decoded = <String, OpportunityMarketItem>{};
      for (final entry in items.entries) {
        final id = entry.key;
        final value = entry.value;
        if (id is! String ||
            !RegExp(r'^[1-9]\d*$').hasMatch(id) ||
            value is! Map ||
            value['itemId'] != id ||
            value['subId'] != 0 ||
            value['unlisted'] is! bool) {
          throw const FormatException('Invalid cached market identity');
        }
        final stock = _number(value['stock']);
        final aggregateStock = _number(value['aggregateStock']);
        final scope = value['stockScope'];
        if ((scope != null && scope != 'item' && scope != 'allEnhancements') ||
            (scope == 'item' && aggregateStock != null) ||
            (scope == 'allEnhancements' && stock != null) ||
            (scope == null && aggregateStock != null)) {
          throw const FormatException('Invalid cached market stock scope');
        }
        // Older caches did not distinguish bulk all-enhancement stock from a
        // scoped quote. Preserve that number as aggregate evidence, never as
        // verified base availability. A new explicitly scoped quote is kept.
        final legacyAggregate = scope == null && isEnhanceableMarketItemId(id);
        decoded[id] = OpportunityMarketItem(
          itemId: id,
          basePrice: _number(value['basePrice']),
          stock: legacyAggregate ? null : stock,
          aggregateStock: legacyAggregate ? stock : aggregateStock,
          quoteFetchedAt: _date(value['quoteFetchedAt']),
          asks: _levels(value['asks']),
          bids: _levels(value['bids']),
          bookFetchedAt: _date(value['bookFetchedAt']),
          totalTrades: _number(value['totalTrades']),
          lastSoldAt: _date(value['lastSoldAt']),
          unlisted: value['unlisted'] as bool,
        );
      }
      result[region.key as String] = decoded;
    }
    return result;
  }

  static int? _number(Object? value) {
    if (value == null) return null;
    if (value is! int || value < 0 || value > 9007199254740991) {
      throw const FormatException('Invalid cached market number');
    }
    return value;
  }

  static DateTime? _date(Object? value) {
    final milliseconds = _number(value);
    if (milliseconds == null) return null;
    if (milliseconds > 8640000000000000) {
      throw const FormatException('Invalid cached receipt date');
    }
    return DateTime.fromMillisecondsSinceEpoch(milliseconds, isUtc: true);
  }

  static List<OpportunityMarketLevel>? _levels(Object? value) {
    if (value == null) return null;
    if (value is! List || value.length > _maxLevels) {
      throw const FormatException('Invalid cached market depth');
    }
    return [
      for (final row in value)
        if (row is List && row.length == 2)
          _level(row)
        else
          throw const FormatException('Invalid cached market level'),
    ];
  }

  static OpportunityMarketLevel _level(List<dynamic> row) {
    final price = _number(row[0]);
    final quantity = _number(row[1]);
    if (price == null || price == 0 || quantity == null) {
      throw const FormatException('Invalid cached market level');
    }
    return OpportunityMarketLevel(price: price, quantity: quantity);
  }

  static OpportunityMarketItem? _withoutFuture(
    OpportunityMarketItem item,
    DateTime now,
  ) {
    final quote =
        item.quoteFetchedAt != null && !item.quoteFetchedAt!.isAfter(now);
    final book =
        item.bookFetchedAt != null && !item.bookFetchedAt!.isAfter(now);
    if (!quote && !book) return null;
    return OpportunityMarketItem(
      itemId: item.itemId,
      basePrice: quote ? item.basePrice : null,
      stock: quote ? item.stock : null,
      aggregateStock: quote ? item.aggregateStock : null,
      quoteFetchedAt: quote ? item.quoteFetchedAt : null,
      asks: book ? item.asks : null,
      bids: book ? item.bids : null,
      bookFetchedAt: book ? item.bookFetchedAt : null,
      totalTrades: quote ? item.totalTrades : null,
      lastSoldAt: quote && item.lastSoldAt?.isAfter(now) == false
          ? item.lastSoldAt
          : null,
      unlisted: quote && item.unlisted,
    );
  }
}
