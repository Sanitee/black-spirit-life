import 'dart:async';

/// One relative timer between HTTP starts, shared by every worker/caller.
/// Independent of wall-clock corrections and injected market receipt dates.
final class MarketRequestPacer {
  MarketRequestPacer(this.interval, {this.onReady, this.requestWindowDelay});
  final Duration interval;
  final void Function()? onReady;
  final Duration Function()? requestWindowDelay;
  Timer? _timer;
  Completer<void>? _gate;
  final Stopwatch _elapsed = Stopwatch()..start();
  Duration? _lastStart;
  Duration _lastInterval = Duration.zero;
  Duration? _wakeAt;
  bool _closed = false;

  bool get canStart => canStartFor(interval);

  /// Observes the timed dispatch gate without arming a timer or spending a slot.
  Duration remainingDelayFor(Duration minimumInterval) {
    if (minimumInterval.isNegative) {
      throw ArgumentError.value(minimumInterval, 'minimumInterval');
    }
    if (_closed) return Duration.zero;
    var gap = interval;
    if (minimumInterval > gap) gap = minimumInterval;
    if (_lastInterval > gap) gap = _lastInterval;
    final last = _lastStart;
    var remaining = last == null
        ? Duration.zero
        : last + gap - _elapsed.elapsed;
    final allowance = requestWindowDelay?.call() ?? Duration.zero;
    if (allowance > remaining) remaining = allowance;
    return remaining > Duration.zero ? remaining : Duration.zero;
  }

  /// A joining recovery caller may raise the pending request's minimum gap.
  /// Both the previous and next request's constraints apply to the same clock.
  bool canStartFor(Duration minimumInterval) {
    if (minimumInterval.isNegative) {
      throw ArgumentError.value(minimumInterval, 'minimumInterval');
    }
    if (_closed) return false;
    final last = _lastStart;
    var gap = interval;
    if (minimumInterval > gap) gap = minimumInterval;
    if (_lastInterval > gap) gap = _lastInterval;
    final elapsed = _elapsed.elapsed;
    var remaining = last == null ? Duration.zero : last + gap - elapsed;
    final allowance = requestWindowDelay?.call() ?? Duration.zero;
    if (allowance > remaining) remaining = allowance;
    if (remaining <= Duration.zero) return true;
    final deadline = elapsed + remaining;
    if (_wakeAt != deadline) _arm(remaining, deadline);
    return false;
  }

  Future<void> get whenReady => _gate?.future ?? Future<void>.value();

  void started({Duration? minimumInterval}) {
    final gap = minimumInterval != null && minimumInterval > interval
        ? minimumInterval
        : interval;
    if (!canStartFor(gap)) throw StateError('Market dispatch is not ready');
    _lastStart = _elapsed.elapsed;
    _lastInterval = gap;
    _timer?.cancel();
    _wakeAt = null;
    final previous = _gate;
    _gate = null;
    if (previous != null && !previous.isCompleted) previous.complete();
    if (gap > Duration.zero) _arm(gap, _lastStart! + gap);
  }

  void _arm(Duration remaining, Duration deadline) {
    _timer?.cancel();
    _wakeAt = deadline;
    final gate = _gate ??= Completer<void>();
    _timer = Timer(remaining, () {
      _timer = null;
      _wakeAt = null;
      _gate = null;
      gate.complete();
      if (!_closed) onReady?.call();
    });
  }

  void close() {
    _closed = true;
    _timer?.cancel();
    _timer = null;
    _wakeAt = null;
    _elapsed.stop();
    final gate = _gate;
    _gate = null;
    if (gate != null && !gate.isCompleted) gate.complete();
  }
}
