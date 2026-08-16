/// A planner-owned material shortage projected into the resource map.
///
/// The map package deliberately receives this small immutable snapshot instead
/// of depending on the craft planner's domain models. Item IDs are preferred
/// when available; [name] remains the compatibility key for older catalog
/// records and user-authored items.
class BdoPlannerMaterialNeed {
  const BdoPlannerMaterialNeed({
    required this.name,
    required this.missingQuantity,
    required this.marketable,
    required this.stockKnown,
    required this.stock,
    required this.marketRegion,
    required this.marketFetchedAt,
    this.gameItemId,
    this.vendorPurchaseAvailable = false,
    this.reviewedWorkerRoute = false,
  });

  final int? gameItemId;
  final String name;
  final double missingQuantity;
  final bool marketable;
  final bool stockKnown;
  final double stock;
  final String marketRegion;
  final DateTime? marketFetchedAt;

  /// Whether the planner's resolved source data offers this item directly
  /// from an NPC vendor.
  ///
  /// Vendor-direct materials remain searchable on the map, but are not useful
  /// manual-gathering recommendations for the current-plan shortlist.
  final bool vendorPurchaseAvailable;

  /// Whether the planner's reviewed acquisition catalog names a worker-node
  /// route. The map also checks its own concrete worker links, which can be
  /// newer or more complete than the prose acquisition catalog.
  final bool reviewedWorkerRoute;
}
