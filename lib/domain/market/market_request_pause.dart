enum MarketRequestPauseReason { throttled, protected, serverUnavailable }

/// Operational server pause, never a market receipt or an item availability fact.
final class MarketRequestPause {
  const MarketRequestPause({required this.reason, required this.retryAt});

  final MarketRequestPauseReason reason;
  final DateTime retryAt;

  bool isActive(DateTime now) => retryAt.isAfter(now);
}
