import 'dart:async';

/// Cooperative cancellation for a market refresh.
///
/// A controller is owned by the caller (typically a repository or feature
/// controller), while transports and adapters only receive the token.
final class MarketCancellationController {
  final Completer<void> _cancelled = Completer<void>();

  MarketCancellationToken get token => MarketCancellationToken._(_cancelled);

  bool get isCancelled => _cancelled.isCompleted;

  void cancel() {
    if (!_cancelled.isCompleted) {
      _cancelled.complete();
    }
  }
}

final class MarketCancellationToken {
  const MarketCancellationToken._(this._cancelled);

  final Completer<void> _cancelled;

  bool get isCancelled => _cancelled.isCompleted;

  Future<void> get whenCancelled => _cancelled.future;

  void throwIfCancelled() {
    if (isCancelled) {
      throw const MarketFetchCancelledException();
    }
  }
}

final class MarketFetchCancelledException implements Exception {
  const MarketFetchCancelledException();

  @override
  String toString() => 'Market refresh cancelled';
}
