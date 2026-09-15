import 'dart:async';

import 'session_store.dart';

typedef GatheringDurabilityCallback = Future<void> Function();

/// Coordinates safe root moves, updates, and close operations for Gathering.
///
/// [freezeAndFlush] immediately rejects new personal-data mutations, releases
/// transient resources, and then waits for every accepted serialized write.
/// Call [resume] if the outer operation is cancelled or fails.
class GatheringDurabilityController {
  SessionStore? _store;
  GatheringDurabilityCallback? _releaseTransientResources;
  GatheringDurabilityCallback? _resumeTransientResources;
  Future<void> _lifecycleQueue = Future<void>.value();
  bool _frozen = false;

  bool get isFrozen => _frozen;

  void attach({
    required SessionStore store,
    GatheringDurabilityCallback? releaseTransientResources,
    GatheringDurabilityCallback? resumeTransientResources,
  }) {
    _store = store;
    _releaseTransientResources = releaseTransientResources;
    _resumeTransientResources = resumeTransientResources;
    if (_frozen) store.freezeNewMutations();
  }

  void detach(SessionStore store) {
    if (!identical(_store, store)) return;
    _store = null;
    _releaseTransientResources = null;
    _resumeTransientResources = null;
  }

  Future<T> _serialize<T>(Future<T> Function() action) {
    final result = _lifecycleQueue.then((_) => action());
    _lifecycleQueue = result.then<void>((_) {}, onError: (_, _) {});
    return result;
  }

  /// Waits for accepted serialized writes without changing mutation state.
  Future<void> flush() => _serialize(() async {
    await _store?.flush();
  });

  /// Freezes new mutations, releases active inbox/video resources, and flushes.
  Future<void> freezeAndFlush() => _serialize(() async {
    _frozen = true;
    _store?.freezeNewMutations();
    await _releaseTransientResources?.call();
    await _store?.flush();
  });

  /// Re-enables mutations and restarts transient observers after cancellation.
  Future<void> resume() => _serialize(() async {
    _frozen = false;
    _store?.resumeMutations();
    await _resumeTransientResources?.call();
  });
}
