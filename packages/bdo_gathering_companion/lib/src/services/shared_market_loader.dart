/// A host-supplied price or order-book receipt. Each part keeps the time at
/// which the market supplied it, including when it comes from a shared cache.
final class GatheringMarketReceipt {
  const GatheringMarketReceipt({
    required this.itemId,
    this.price,
    this.stock,
    this.quoteFetchedAt,
    this.preorders,
    this.preorderFetchedAt,
    this.unavailable = false,
  });

  final String itemId;
  final int? price;
  final int? stock;
  final DateTime? quoteFetchedAt;
  final int? preorders;
  final DateTime? preorderFetchedAt;
  final bool unavailable;
}

final class GatheringMarketLoadResult {
  const GatheringMarketLoadResult({
    this.priceFailures = const {},
    this.preorderFailures = const {},
  });

  final Set<String> priceFailures;
  final Set<String> preorderFailures;
}

/// Optional shared host service. Omitting this keeps standalone Gathering's
/// own service. Cancelling detaches this caller, not another screen's work.
typedef GatheringSharedMarketLoader =
    Future<GatheringMarketLoadResult> Function(
      Map<String, String> itemsById, {
      required bool includePreorders,
      required bool forceRefresh,
      required void Function(GatheringMarketReceipt receipt) onItem,
      Future<void>? cancelled,
    });
