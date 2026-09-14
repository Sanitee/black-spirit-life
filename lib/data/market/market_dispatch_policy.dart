import 'dart:collection';

/// Application safeguards, not a claimed rate allowance from the provider.
/// A few unrelated failures cannot permanently collapse the whole session.
final class MarketDispatchPolicy {
  MarketDispatchPolicy({required this.maximumConcurrency})
    : effectiveConcurrency = maximumConcurrency;

  final int maximumConcurrency;
  int effectiveConcurrency;
  DateTime? blockedUntil;
  DateTime? _lastChange;
  int _successStreak = 0;
  final Queue<(DateTime, bool)> _outcomes = Queue();

  bool isBlocked(DateTime now) => blockedUntil?.isAfter(now) ?? false;

  void record(DateTime now, {required bool transientFailure}) {
    _outcomes.addLast((now, transientFailure));
    while (_outcomes.isNotEmpty &&
        now.difference(_outcomes.first.$1) > const Duration(seconds: 10)) {
      _outcomes.removeFirst();
    }
    while (_outcomes.length > 100) {
      _outcomes.removeFirst();
    }
    _successStreak = transientFailure ? 0 : _successStreak + 1;
    final failures = _outcomes.where((entry) => entry.$2).length;
    final mayChange =
        _lastChange == null ||
        now.difference(_lastChange!) >= const Duration(seconds: 3);
    if (mayChange &&
        _outcomes.length >= 20 &&
        failures >= 6 &&
        failures / _outcomes.length >= .25) {
      final floor = maximumConcurrency < 4 ? maximumConcurrency : 4;
      effectiveConcurrency = (effectiveConcurrency ~/ 2).clamp(
        floor,
        maximumConcurrency,
      );
      _lastChange = now;
      _outcomes.clear();
      _successStreak = 0;
    } else if (mayChange &&
        _successStreak >= 32 &&
        effectiveConcurrency < maximumConcurrency) {
      effectiveConcurrency = (effectiveConcurrency + 4).clamp(
        1,
        maximumConcurrency,
      );
      _lastChange = now;
      _successStreak = 0;
      _outcomes.clear();
    }
  }

  void rateLimited(DateTime now, Duration? retryAfter) {
    final delay = retryAfter ?? const Duration(seconds: 30);
    final until = now.add(delay.isNegative ? Duration.zero : delay);
    if (blockedUntil == null || until.isAfter(blockedUntil!)) {
      blockedUntil = until;
    }
    _outcomes.clear();
    _successStreak = 0;
  }
}
