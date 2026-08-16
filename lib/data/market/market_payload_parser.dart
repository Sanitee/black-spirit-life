import 'dart:convert';

import '../../domain/market/market_price_models.dart';

final class ParsedMarketItem {
  const ParsedMarketItem({
    required this.id,
    required this.price,
    required this.stock,
    required this.apiName,
    this.totalTrades,
    this.lastSoldAtEpochSeconds,
  });

  final String id;
  final int price;
  final int? stock;
  final String apiName;
  final int? totalTrades;
  final int? lastSoldAtEpochSeconds;
}

/// Pure response parsing shared by the saved-fixture tests and HTTP adapters.
abstract final class MarketPayloadParser {
  static ParsedMarketItem? parsePearlAbyssItem(
    String responseBody,
    String requestedId,
  ) {
    final decoded = jsonDecode(responseBody);
    if (decoded is! Map<Object?, Object?> || decoded['resultMsg'] is! String) {
      throw const FormatException('Missing Pearl Abyss resultMsg');
    }

    final normalizedRequestId = normalizeNumericMarketId(requestedId);
    if (normalizedRequestId == null) {
      throw const FormatException('Invalid requested market ID');
    }

    final raw = decoded['resultMsg']! as String;
    for (final record in raw.split('|')) {
      if (record.trim() == '') {
        continue;
      }
      final fields = record.split('-');
      if (fields.length < 5 ||
          normalizeNumericMarketId(fields[0]) != normalizedRequestId) {
        continue;
      }
      return ParsedMarketItem(
        id: normalizedRequestId,
        price: _nonnegativeInt(fields[3]) ?? 0,
        stock: _nonnegativeInt(fields[4]) ?? 0,
        apiName: '',
      );
    }
    return null;
  }

  static List<ParsedMarketItem> parseArshaItems(
    String responseBody, {
    List<String> stockFieldNames = const <String>['currentStock', 'stock'],
  }) {
    final decoded = jsonDecode(responseBody);
    final objects = flatten(decoded);
    final items = <ParsedMarketItem>[];
    for (final object in objects) {
      final id = _marketIdFrom(object, const <String>['id', 'mainKey']);
      if (id == null) {
        continue;
      }
      items.add(
        ParsedMarketItem(
          id: id,
          price:
              _firstNonnegativeInt(object, const <String>[
                'basePrice',
                'currentPrice',
                'price',
                'lastSoldPrice',
                'minPrice',
              ]) ??
              0,
          stock: _firstNonnegativeInt(object, stockFieldNames),
          apiName: _stringValue(object['name']),
          totalTrades: _firstStrictNonnegativeInt(object, const <String>[
            'totalTrades',
            'totalTradeCount',
          ]),
          lastSoldAtEpochSeconds: _firstPositiveInt(object, const <String>[
            'lastSoldTime',
            'lastSoldAt',
          ]),
        ),
      );
    }
    return items;
  }

  /// Flattens arrays, JSON-string envelopes, and common object wrappers.
  ///
  /// `resultMsg` remains strict: a non-empty string must contain JSON. That
  /// matches the audited Arsha adapter's failure/fallback boundary.
  static List<Map<String, Object?>> flatten(Object? value) {
    final output = <Map<String, Object?>>[];

    void visit(Object? node) {
      if (node is List<Object?>) {
        for (final item in node) {
          visit(item);
        }
        return;
      }

      if (node is String) {
        if (node.trim() == '') {
          return;
        }
        visit(jsonDecode(node));
        return;
      }

      if (node is! Map<Object?, Object?>) {
        return;
      }

      final object = <String, Object?>{
        for (final entry in node.entries) entry.key.toString(): entry.value,
      };

      if (object.containsKey('resultMsg')) {
        final result = object['resultMsg'];
        if (result is String && result.trim() == '') {
          return;
        }
        visit(result);
        return;
      }

      const wrapperKeys = <String>[
        'data',
        'result',
        'items',
        'rows',
        'payload',
      ];
      var traversedWrapper = false;
      for (final key in wrapperKeys) {
        final nested = object[key];
        if (nested is List<Object?> ||
            nested is Map<Object?, Object?> ||
            nested is String && nested.trim() != '') {
          traversedWrapper = true;
          visit(nested);
        }
      }

      if (_marketIdFrom(object, const <String>['id', 'mainKey']) != null ||
          !traversedWrapper) {
        output.add(object);
      }
    }

    visit(value);
    return output;
  }

  static String? _marketIdFrom(
    Map<String, Object?> object,
    List<String> names,
  ) {
    for (final name in names) {
      final value = object[name];
      if (value is String) {
        final normalized = normalizeNumericMarketId(value);
        if (normalized != null) {
          return normalized;
        }
      } else if (value is int && value > 0) {
        return value.toString();
      } else if (value is double &&
          value.isFinite &&
          value > 0 &&
          value == value.truncateToDouble()) {
        return value.toInt().toString();
      }
    }
    return null;
  }

  static int? _firstNonnegativeInt(
    Map<String, Object?> object,
    List<String> names,
  ) {
    for (final name in names) {
      if (object.containsKey(name)) {
        final parsed = _nonnegativeInt(object[name]);
        if (parsed != null) {
          return parsed;
        }
      }
    }
    return null;
  }

  static int? _firstPositiveInt(
    Map<String, Object?> object,
    List<String> names,
  ) {
    final value = _firstNonnegativeInt(object, names);
    return value == null || value <= 0 ? null : value;
  }

  static int? _firstStrictNonnegativeInt(
    Map<String, Object?> object,
    List<String> names,
  ) {
    for (final name in names) {
      if (!object.containsKey(name)) continue;
      num? number;
      final value = object[name];
      if (value is num) {
        number = value;
      } else if (value is String) {
        number = num.tryParse(value.trim());
      }
      if (number != null && number.isFinite && number >= 0) {
        return number.floor().clamp(0, 0x7FFFFFFFFFFFFFFF);
      }
    }
    return null;
  }

  static int? _nonnegativeInt(Object? value) {
    num? number;
    if (value is num) {
      number = value;
    } else if (value is String) {
      number = num.tryParse(value.trim());
    }
    if (number == null || !number.isFinite) {
      return null;
    }
    return number.floor().clamp(0, 0x7FFFFFFFFFFFFFFF);
  }

  static String _stringValue(Object? value) => value is String ? value : '';
}
