import 'shared_market_models.dart';

/// Releases no-longer-needed parts of one fetch without cancelling its other
/// work. Releases are permanent for this scope; a later fetch uses a new scope.
/// Whole-call cancellation remains separate, for Stop and owner disposal.
final class SharedMarketRequestScope {
  final _released = <SharedMarketPartKey>{};
  final _listeners = <void Function(Set<SharedMarketPartKey>)>{};

  bool isReleased(SharedMarketPartKey part) => _released.contains(part);

  void release(Iterable<SharedMarketPartKey> parts) {
    final added = parts.where((part) => !_released.contains(part)).toSet();
    if (added.isEmpty) return;
    _released.addAll(added);
    final immutable = Set<SharedMarketPartKey>.unmodifiable(added);
    // Synchronous notification prunes queued work before another dispatch.
    for (final listener in _listeners.toList()) {
      if (_listeners.contains(listener)) listener(immutable);
    }
  }

  void addListener(void Function(Set<SharedMarketPartKey>) listener) =>
      _listeners.add(listener);

  void removeListener(void Function(Set<SharedMarketPartKey>) listener) =>
      _listeners.remove(listener);
}
