import '../opportunities/opportunity_market_models.dart';
import 'market_price_models.dart';
import 'market_request_pause.dart';

export 'market_request_pause.dart';

/// Default shared/on-entry freshness. Opportunities reuses receipts for thirty
/// minutes while staying in that tab. Neither policy is a periodic timer.
const sharedMarketFreshness = Duration(minutes: 5);

/// Names belong to callers. Network identity never depends on a display name.
final class SharedMarketKey {
  factory SharedMarketKey({
    required String region,
    required String itemId,
    int subId = 0,
  }) {
    final normalizedRegion = region.trim().toLowerCase();
    final normalizedId = normalizeNumericMarketId(itemId);
    if (!const {'eu', 'na'}.contains(normalizedRegion) ||
        normalizedId == null ||
        int.tryParse(normalizedId) == null ||
        subId < 0) {
      throw ArgumentError('Invalid market identity');
    }
    return SharedMarketKey._(normalizedRegion, normalizedId, subId);
  }

  const SharedMarketKey._(this.region, this.itemId, this.subId);
  final String region;
  final String itemId;
  final int subId;

  @override
  bool operator ==(Object other) =>
      other is SharedMarketKey &&
      region == other.region &&
      itemId == other.itemId &&
      subId == other.subId;
  @override
  int get hashCode => Object.hash(region, itemId, subId);
  @override
  String toString() => '$region/$itemId/$subId';
}

enum SharedMarketPart { quote, orderBook }

final class SharedMarketPartKey {
  const SharedMarketPartKey(this.key, this.part);
  final SharedMarketKey key;
  final SharedMarketPart part;
  @override
  bool operator ==(Object other) =>
      other is SharedMarketPartKey && key == other.key && part == other.part;
  @override
  int get hashCode => Object.hash(key, part);
}

/// Only the indicated part is present. Cached delivery retains its original
/// receipt time and is never a new sales observation.
final class SharedMarketReceipt {
  const SharedMarketReceipt({
    required this.key,
    required this.item,
    required this.part,
    required this.fromCache,
  });
  final SharedMarketKey key;
  final OpportunityMarketItem item;
  final SharedMarketPart part;
  final bool fromCache;
}

final class SharedMarketBatch {
  SharedMarketBatch({
    required Map<SharedMarketKey, OpportunityMarketItem> items,
    required Map<SharedMarketPartKey, String> failures,
    this.rateLimited = false,
    Set<SharedMarketPartKey> retryableFailures = const {},
    Map<String, MarketRequestPause> pauses = const {},
  }) : items = Map.unmodifiable(items),
       failures = Map.unmodifiable(failures),
       retryableFailures = Set.unmodifiable(retryableFailures),
       pauses = Map.unmodifiable(pauses);
  final Map<SharedMarketKey, OpportunityMarketItem> items;
  final Map<SharedMarketPartKey, String> failures;
  final bool rateLimited;
  final Set<SharedMarketPartKey> retryableFailures;
  final Map<String, MarketRequestPause> pauses;

  /// Single-region callers get their pause; mixed callers retain the full map.
  /// Protection takes precedence over an ordinary temporary throttle.
  MarketRequestPause? get pause {
    int priority(MarketRequestPauseReason reason) => switch (reason) {
      MarketRequestPauseReason.protected => 2,
      MarketRequestPauseReason.throttled => 1,
      MarketRequestPauseReason.serverUnavailable => 0,
    };
    MarketRequestPause? result;
    for (final candidate in pauses.values) {
      if (result == null ||
          priority(candidate.reason) > priority(result.reason) ||
          (candidate.reason == result.reason &&
              candidate.retryAt.isAfter(result.retryAt))) {
        result = candidate;
      }
    }
    return result;
  }

  Set<SharedMarketKey> get quoteFailures => Set.unmodifiable(
    failures.keys
        .where((key) => key.part == SharedMarketPart.quote)
        .map((key) => key.key),
  );
  Set<SharedMarketKey> get bookFailures => Set.unmodifiable(
    failures.keys
        .where((key) => key.part == SharedMarketPart.orderBook)
        .map((key) => key.key),
  );
}

/// Read-only admission state for a genuinely fresh toolbar reload. Readiness
/// is not a reservation: later callers can still spend shared request slots.
final class SharedMarketRefreshReadiness {
  const SharedMarketRefreshReadiness({
    this.wait = Duration.zero,
    this.requestCount = 0,
    this.windowLimit,
    this.initializing = false,
    this.pendingWork = false,
    this.providerPaused = false,
  });

  final Duration wait;
  final int requestCount;
  final int? windowLimit;
  final bool initializing;
  final bool pendingWork;
  final bool providerPaused;
  bool get canRefresh => !initializing && !pendingWork && wait <= Duration.zero;
  bool get staged => windowLimit != null && requestCount > windowLimit!;
}

/// Session-only operational counters; no item names, account data or secrets.
final class SharedMarketDiagnostics {
  const SharedMarketDiagnostics({
    required this.startedRequests,
    required this.completedRequests,
    required this.failedRequests,
    required this.cacheHits,
    required this.coalescedParts,
    required this.activeRequests,
    required this.queuedParts,
    required this.peakActiveRequests,
    required this.effectiveConcurrencyByRegion,
  });
  final int startedRequests;
  final int completedRequests;
  final int failedRequests;
  final int cacheHits;
  final int coalescedParts;
  final int activeRequests;
  final int queuedParts;
  final int peakActiveRequests;
  final Map<String, int> effectiveConcurrencyByRegion;
}
