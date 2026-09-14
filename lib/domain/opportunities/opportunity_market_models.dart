/// A read-only market snapshot. Keys are canonical decimal item IDs, not names.
final class OpportunityMarketSnapshot {
  OpportunityMarketSnapshot({
    required this.region,
    required Map<String, OpportunityMarketItem> items,
  }) : items = Map.unmodifiable(items);

  final String region;
  final Map<String, OpportunityMarketItem> items;

  OpportunityMarketSnapshot merge(Map<String, OpportunityMarketItem> updates) =>
      OpportunityMarketSnapshot(
        region: region,
        items: {
          ...items,
          for (final entry in updates.entries)
            entry.key: items[entry.key]?.mergeFrom(entry.value) ?? entry.value,
        },
      );
}

final class OpportunityMarketItem {
  OpportunityMarketItem({
    required this.itemId,
    this.subId = 0,
    this.basePrice,
    this.stock,
    this.aggregateStock,
    this.quoteFetchedAt,
    List<OpportunityMarketLevel>? asks,
    List<OpportunityMarketLevel>? bids,
    this.bookFetchedAt,
    this.totalTrades,
    this.lastSoldAt,
    this.salesActivity,
    this.unlisted = false,
  }) : asks = asks == null ? null : List.unmodifiable(asks),
       bids = bids == null ? null : List.unmodifiable(bids);

  final String itemId;
  final int subId;
  final int? basePrice;

  /// Stock for this item's requested enhancement level, never an all-level sum.
  final int? stock;

  /// Search-summary stock across enhancement levels. This is not base stock.
  /// Its receipt time is [quoteFetchedAt], independently of the scoped book.
  final int? aggregateStock;
  final DateTime? quoteFetchedAt;

  /// Null is unknown; an empty list is a successfully checked empty side.
  final List<OpportunityMarketLevel>? asks;
  final List<OpportunityMarketLevel>? bids;
  final DateTime? bookFetchedAt;
  final int? totalTrades;
  final DateTime? lastSoldAt;
  final OpportunitySalesActivity? salesActivity;
  final bool unlisted;

  bool quoteIsFresh(DateTime now, Duration maxAge) =>
      basePrice != null &&
      basePrice! > 0 &&
      _fresh(quoteFetchedAt, now, maxAge);

  bool bookIsFresh(DateTime now, Duration maxAge) =>
      asks != null && bids != null && _fresh(bookFetchedAt, now, maxAge);

  /// Returns genuine stock for this enhancement level without mixing dates.
  /// Uses the latest fresh scoped observation, retaining the quote on equal
  /// receipt times. A fresh same-level book can also fill unknown quote stock.
  /// All-enhancement summaries never assert stock for this enhancement level.
  int? stockFor(DateTime now, Duration maxAge) {
    final freshBook = bookIsFresh(now, maxAge);
    if (aggregateStock == null &&
        stock != null &&
        quoteIsFresh(now, maxAge) &&
        (!freshBook || !bookFetchedAt!.isAfter(quoteFetchedAt!))) {
      return stock;
    }
    return freshBook
        ? asks!.fold<int>(0, (sum, level) => sum + level.quantity)
        : null;
  }

  int? get preorderCount =>
      bids?.fold<int>(0, (sum, level) => sum + level.quantity);

  /// Merge only the parts actually fetched, never refreshing an old book when
  /// a quote arrives. Older responses cannot overwrite newer observations.
  OpportunityMarketItem mergeFrom(OpportunityMarketItem update) {
    if (itemId != update.itemId || subId != update.subId) {
      throw ArgumentError('Cannot merge different market items');
    }
    final useQuote =
        update.quoteFetchedAt != null &&
        (quoteFetchedAt == null ||
            !update.quoteFetchedAt!.isBefore(quoteFetchedAt!));
    final useBook =
        update.bookFetchedAt != null &&
        (bookFetchedAt == null ||
            !update.bookFetchedAt!.isBefore(bookFetchedAt!));
    final quote = useQuote ? update : this;
    final book = useBook ? update : this;
    return OpportunityMarketItem(
      itemId: itemId,
      subId: subId,
      basePrice: quote.basePrice,
      stock: quote.stock,
      aggregateStock: quote.aggregateStock,
      quoteFetchedAt: quote.quoteFetchedAt,
      asks: book.asks,
      bids: book.bids,
      bookFetchedAt: book.bookFetchedAt,
      totalTrades: quote.totalTrades,
      lastSoldAt: quote.lastSoldAt,
      salesActivity: useQuote ? update.salesActivity : salesActivity,
      unlisted: quote.unlisted,
    );
  }

  OpportunityMarketItem withSalesActivity(OpportunitySalesActivity? activity) =>
      OpportunityMarketItem(
        itemId: itemId,
        subId: subId,
        basePrice: basePrice,
        stock: stock,
        aggregateStock: aggregateStock,
        quoteFetchedAt: quoteFetchedAt,
        asks: asks,
        bids: bids,
        bookFetchedAt: bookFetchedAt,
        totalTrades: totalTrades,
        lastSoldAt: lastSoldAt,
        salesActivity: activity,
        unlisted: unlisted,
      );
}

bool _fresh(DateTime? fetchedAt, DateTime now, Duration maxAge) =>
    fetchedAt != null &&
    !fetchedAt.isAfter(now) &&
    !maxAge.isNegative &&
    now.difference(fetchedAt) <= maxAge;

final class OpportunityMarketLevel {
  const OpportunityMarketLevel({required this.price, required this.quantity});
  final int price;
  final int quantity;
}

final class OpportunitySalesActivity {
  const OpportunitySalesActivity({
    required this.soldCount,
    required this.startedAt,
    required this.endedAt,
  });
  final int soldCount;
  final DateTime startedAt;
  final DateTime endedAt;
  Duration get interval => endedAt.difference(startedAt);
}

final class OpportunityMarketFill {
  const OpportunityMarketFill({
    required this.requestedQuantity,
    required this.filledQuantity,
    required this.totalSilver,
  });
  final int requestedQuantity;
  final int filledQuantity;
  final int totalSilver;
  int get remainingQuantity => requestedQuantity - filledQuantity;
  bool get isComplete => remainingQuantity == 0;
}

/// Estimate a fill against the returned price levels, not against base price.
/// The caller checks freshness and applies tax. This never places an order.
OpportunityMarketFill fillMarketDepth({
  required List<OpportunityMarketLevel> levels,
  required int quantity,
  required bool buying,
}) {
  if (quantity < 0) throw ArgumentError.value(quantity, 'quantity');
  final sorted = levels.toList();
  if (sorted.any((level) => level.price <= 0 || level.quantity < 0)) {
    throw ArgumentError(
      'Market levels must have positive prices and nonnegative quantities',
    );
  }
  sorted.sort(
    (a, b) => buying ? a.price.compareTo(b.price) : b.price.compareTo(a.price),
  );
  var remaining = quantity;
  var silver = 0;
  for (final level in sorted) {
    final filled = remaining < level.quantity ? remaining : level.quantity;
    silver += filled * level.price;
    remaining -= filled;
    if (remaining == 0) break;
  }
  return OpportunityMarketFill(
    requestedQuantity: quantity,
    filledQuantity: quantity - remaining,
    totalSilver: silver,
  );
}
