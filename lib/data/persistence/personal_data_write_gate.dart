import 'dart:async';

/// Coordinates feature-local writes with application shutdown and personal
/// data folder moves.
///
/// Work accepted before [freezeAndFlush] is allowed to finish. Work attempted
/// after the gate is frozen is rejected, so the verified folder snapshot
/// cannot race a late session or loadout save.
class PersonalDataWriteGate {
  Future<void> _tail = Future<void>.value();
  bool _frozen = false;
  Object? _lastError;
  StackTrace? _lastStackTrace;

  bool get mutationsFrozen => _frozen;

  Future<T> run<T>(Future<T> Function() write) {
    if (_frozen) {
      return Future<T>.error(
        StateError('Personal data is being moved or the app is closing.'),
      );
    }

    final operation = _tail.then<T>((_) => write());
    _tail = operation.then<void>(
      (_) {
        _lastError = null;
        _lastStackTrace = null;
      },
      onError: (Object error, StackTrace stackTrace) {
        _lastError = error;
        _lastStackTrace = stackTrace;
      },
    );
    return operation;
  }

  Future<void> flush() async {
    await _tail;
    if (_lastError case final error?) {
      Error.throwWithStackTrace(error, _lastStackTrace ?? StackTrace.current);
    }
  }

  Future<void> freezeAndFlush() async {
    _frozen = true;
    await flush();
  }

  void resumeAfterMoveFailure() {
    _frozen = false;
  }
}
