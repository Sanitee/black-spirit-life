import 'dart:collection';

import 'models.dart';

const double centralMarketAfterTaxRate = 0.845;

/// Aggregated evidence from the player's own saved gathering sessions.
///
/// Keeping the method in the key matters: two tools used at the same map spot
/// can have very different yields.
final class SpotPerformance {
  SpotPerformance._({
    required this.spotId,
    required this.methodId,
    required this.durationSeconds,
    required this.sessionCount,
    required Map<String, int> itemTotals,
    required this.containsApproximateLoot,
  }) : itemTotals = UnmodifiableMapView(itemTotals);

  final String spotId;
  final String methodId;
  final int durationSeconds;
  final int sessionCount;
  final Map<String, int> itemTotals;
  final bool containsApproximateLoot;

  double get hours => durationSeconds / 3600;

  double itemsPerHour(String itemId) => durationSeconds <= 0
      ? 0
      : (itemTotals[itemId] ?? 0) * 3600 / durationSeconds;

  double afterTaxSilverPerHour(Map<String, int> prices) {
    if (durationSeconds <= 0) return 0;
    var value = 0.0;
    for (final entry in itemTotals.entries) {
      value += entry.value * (prices[entry.key] ?? 0);
    }
    return value * centralMarketAfterTaxRate * 3600 / durationSeconds;
  }
}

List<SpotPerformance> aggregateSpotPerformance(
  Iterable<GatheringSession> sessions,
) {
  final builders = <(String, String), _PerformanceBuilder>{};
  for (final session in sessions) {
    if (session.spotId.isEmpty ||
        session.methodId.isEmpty ||
        session.durationSeconds <= 0) {
      continue;
    }
    final builder = builders.putIfAbsent((
      session.spotId,
      session.methodId,
    ), () => _PerformanceBuilder(session.spotId, session.methodId));
    builder.durationSeconds += session.durationSeconds;
    builder.sessionCount++;
    for (final loot in session.loot) {
      if (loot.id.isEmpty || loot.total < 0) continue;
      builder.itemTotals.update(
        loot.id,
        (current) => current + loot.total,
        ifAbsent: () => loot.total,
      );
      builder.containsApproximateLoot |= loot.isApproximate;
    }
  }
  return builders.values
      .map(
        (builder) => SpotPerformance._(
          spotId: builder.spotId,
          methodId: builder.methodId,
          durationSeconds: builder.durationSeconds,
          sessionCount: builder.sessionCount,
          itemTotals: builder.itemTotals,
          containsApproximateLoot: builder.containsApproximateLoot,
        ),
      )
      .toList(growable: false);
}

final class _PerformanceBuilder {
  _PerformanceBuilder(this.spotId, this.methodId);

  final String spotId;
  final String methodId;
  int durationSeconds = 0;
  int sessionCount = 0;
  bool containsApproximateLoot = false;
  final Map<String, int> itemTotals = <String, int>{};
}
