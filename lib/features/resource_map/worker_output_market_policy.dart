import 'package:bdo_map_core/bdo_map_core.dart';

/// Central-Market policy for worker-node outputs with verified restrictions.
///
/// These item IDs are useful worker-node drops, but they are not raw-sale
/// products. Keeping this list ID-based prevents a bundled item catalog entry
/// or stale price-shaped evidence from assigning them a silver value.
abstract final class WorkerOutputMarketPolicy {
  static const nonCentralMarketItemIds = <int>{
    65267, // Embers of Hongik
    820035, // Crystal of Harmony
    820036, // Forest Crystal
    820039, // Crystal of Decimation
  };

  static bool isKnownNonCentralMarketItem(int? gameItemId) =>
      gameItemId != null && nonCentralMarketItemIds.contains(gameItemId);
}

MarketValueOutputInput resolveWorkerOutputMarketEvidence({
  required String resourceId,
  required String outputName,
  required int? gameItemId,
  required bool explicitlyUnlisted,
  required bool hasBundledMarketId,
  required double? currentUnitPrice,
  required int? listedStock,
  required double? observedDailyTradeVolume,
  required double? tradeObservationHours,
}) {
  final knownNonCentralMarket =
      WorkerOutputMarketPolicy.isKnownNonCentralMarketItem(gameItemId);
  return MarketValueOutputInput(
    outputId: resourceId,
    outputName: outputName,
    isMarketable:
        !knownNonCentralMarket &&
        !explicitlyUnlisted &&
        (hasBundledMarketId || currentUnitPrice != null || listedStock != null),
    currentUnitPrice: knownNonCentralMarket ? null : currentUnitPrice,
    listedStock: knownNonCentralMarket ? null : listedStock,
    observedDailyTradeVolume: knownNonCentralMarket
        ? null
        : observedDailyTradeVolume,
    tradeObservationHours: knownNonCentralMarket ? null : tradeObservationHours,
  );
}
