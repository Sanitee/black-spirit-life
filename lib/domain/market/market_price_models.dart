import 'dart:collection';

enum MarketPriceSource {
  pearlAbyssCentralMarket('Pearl Abyss Central Market'),
  arshaV2Batch('Arsha v2'),
  arshaV1Item('Arsha v1');

  const MarketPriceSource(this.label);

  final String label;
}

/// Stable, presentation-safe categories for market failures.
enum MarketDiagnosticCode {
  none,
  unsupportedRegion,
  httpStatus,
  timeout,
  network,
  malformedResponse,
  itemMissing,
  unusablePrice,
}

final class MarketPriceRequest {
  const MarketPriceRequest({required this.name, required this.id});

  final String name;
  final String id;
}

final class MarketPriceRow {
  MarketPriceRow({
    required this.name,
    required this.id,
    required this.ok,
    required this.price,
    required this.stock,
    required this.source,
    required this.fetchedAt,
    required this.diagnosticCode,
    this.apiName = '',
    this.httpStatus,
    this.totalTrades,
    this.lastSoldAtEpochSeconds,
  }) : assert(id != ''),
       assert(price >= 0),
       assert(stock == null || stock >= 0),
       assert(totalTrades == null || totalTrades >= 0),
       assert(lastSoldAtEpochSeconds == null || lastSoldAtEpochSeconds >= 0),
       assert(ok == (diagnosticCode == MarketDiagnosticCode.none));

  final String name;
  final String id;
  final bool ok;
  final int price;

  /// Null means the source did not assert stock. Zero is known out-of-stock.
  final int? stock;
  final MarketPriceSource source;
  final DateTime fetchedAt;
  final MarketDiagnosticCode diagnosticCode;
  final String apiName;
  final int? httpStatus;

  /// Cumulative completed trades asserted by the source.
  ///
  /// This is deliberately separate from [stock]. A single cumulative value
  /// is only a baseline; demand can be estimated after a later observation.
  final int? totalTrades;

  /// Source-reported Unix timestamp, in seconds, for the most recent sale.
  final int? lastSoldAtEpochSeconds;
}

final class MarketPriceFetchResult {
  MarketPriceFetchResult({
    required this.region,
    required this.language,
    required this.fetchedAt,
    required List<MarketPriceRow> items,
    required List<MarketPriceSource> attemptedSources,
    this.invalidRequestCount = 0,
    this.duplicateRequestCount = 0,
    this.truncatedRequestCount = 0,
  }) : items = List<MarketPriceRow>.unmodifiable(items),
       attemptedSources = List<MarketPriceSource>.unmodifiable(
         attemptedSources,
       );

  final String region;
  final String language;
  final DateTime fetchedAt;
  final List<MarketPriceRow> items;
  final List<MarketPriceSource> attemptedSources;
  final int invalidRequestCount;
  final int duplicateRequestCount;
  final int truncatedRequestCount;

  int get successCount => items.where((item) => item.ok).length;

  int get failureCount => items.length - successCount;

  int get skippedRequestCount =>
      invalidRequestCount + duplicateRequestCount + truncatedRequestCount;

  bool get hasAnySuccess => successCount > 0;

  bool get hasPartialSuccess => successCount > 0 && failureCount > 0;

  bool get allSucceeded => items.isNotEmpty && failureCount == 0;

  Map<MarketDiagnosticCode, int> get failureCountsByCode {
    final counts = <MarketDiagnosticCode, int>{};
    for (final item in items.where((row) => !row.ok)) {
      counts.update(
        item.diagnosticCode,
        (count) => count + 1,
        ifAbsent: () => 1,
      );
    }
    return UnmodifiableMapView<MarketDiagnosticCode, int>(counts);
  }
}

final class MarketRequestNormalization {
  MarketRequestNormalization({
    required List<MarketPriceRequest> requests,
    required this.invalidCount,
    required this.duplicateCount,
    required this.truncatedCount,
  }) : requests = List<MarketPriceRequest>.unmodifiable(requests);

  final List<MarketPriceRequest> requests;
  final int invalidCount;
  final int duplicateCount;
  final int truncatedCount;
}

/// Returns a canonical positive decimal identifier without numeric coercion.
///
/// This deliberately supports identifiers larger than a platform integer.
String? normalizeNumericMarketId(String value) {
  final trimmed = value.trim();
  if (trimmed == '' || !RegExp(r'^\d+$').hasMatch(trimmed)) {
    return null;
  }

  final canonical = trimmed.replaceFirst(RegExp(r'^0+'), '');
  return canonical == '' ? null : canonical;
}

MarketRequestNormalization normalizeMarketPriceRequests(
  Iterable<MarketPriceRequest> requests, {
  int? maximumRequests,
}) {
  if (maximumRequests != null && maximumRequests <= 0) {
    throw ArgumentError.value(
      maximumRequests,
      'maximumRequests',
      'must be positive',
    );
  }

  final unique = <String, MarketPriceRequest>{};
  var invalidCount = 0;
  var duplicateCount = 0;
  for (final request in requests) {
    final id = normalizeNumericMarketId(request.id);
    final name = request.name.trim();
    if (id == null || name == '') {
      invalidCount++;
      continue;
    }
    if (unique.containsKey(id)) {
      duplicateCount++;
      continue;
    }
    unique[id] = MarketPriceRequest(name: name, id: id);
  }

  final accepted = maximumRequests == null
      ? unique.values.toList(growable: false)
      : unique.values.take(maximumRequests).toList(growable: false);
  return MarketRequestNormalization(
    requests: accepted,
    invalidCount: invalidCount,
    duplicateCount: duplicateCount,
    truncatedCount: maximumRequests == null
        ? 0
        : unique.length - accepted.length,
  );
}
