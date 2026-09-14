import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../persistence/atomic_file_store.dart';

/// An application allowance, not a published provider rate limit. Short gaps
/// alone do not constrain the number of requests in a rolling time window.
final class MarketRequestWindow {
  MarketRequestWindow({
    required this.limit,
    required this.window,
    DateTime Function()? utcNow,
    Duration Function()? elapsed,
  }) : _clock = utcNow ?? (() => DateTime.now().toUtc()),
       _elapsed = elapsed ?? (Stopwatch()..start()).elapsedGetter {
    if (limit < 1 || limit > 1000 || window <= Duration.zero) {
      throw ArgumentError('Invalid market request window');
    }
  }

  final int limit;
  final Duration window;
  final DateTime Function() _clock;
  final Duration Function() _elapsed;
  final _starts = <Duration>[];

  void restore(Iterable<DateTime> starts) {
    final now = _clock();
    final elapsed = _elapsed();
    _starts.clear();
    for (final at in starts) {
      final age = now.difference(at);
      if (age < window) {
        // A clock correction cannot erase a previously spent request.
        _starts.add(elapsed - (age.isNegative ? Duration.zero : age));
      }
    }
    _starts.sort();
    if (_starts.length > limit) _starts.removeRange(0, _starts.length - limit);
  }

  Duration get remainingDelay => delayForStarts(1);

  /// Wait until [count] starts fit together in this shared allowance.
  /// This observes the current budget without reserving or spending any slots.
  Duration delayForStarts(int count) {
    if (count < 0 || count > limit) {
      throw ArgumentError.value(count, 'count', 'Must be between 0 and $limit');
    }
    final elapsed = _elapsed();
    _starts.removeWhere((at) => elapsed - at >= window);
    final expirationsNeeded = _starts.length + count - limit;
    if (expirationsNeeded <= 0) return Duration.zero;
    return _starts[expirationsNeeded - 1] + window - elapsed;
  }

  void started() {
    if (remainingDelay > Duration.zero) throw StateError('Request window full');
    _starts.add(_elapsed());
  }

  List<DateTime> snapshot() {
    remainingDelay;
    final now = _clock();
    final elapsed = _elapsed();
    return [for (final at in _starts) now.subtract(elapsed - at)];
  }
}

extension on Stopwatch {
  Duration elapsedGetter() => elapsed;
}

final class MarketRequestWindowStore {
  MarketRequestWindowStore({required Directory directory})
    : _file = AtomicFileStore(
        directory: directory,
        fileName: 'market-request-window.json',
        preserveMalformedTarget: true,
      );
  final AtomicFileStore _file;

  Future<List<DateTime>> load() async {
    final file = File(_file.targetPath);
    if (!await file.exists()) return [];
    if (await file.length() > 65536) {
      throw const FormatException('Request window too large');
    }
    return _decode(await file.readAsBytes());
  }

  Future<void> save(List<DateTime> starts) => _file.writeJson({
    'version': 1,
    'source': 'application-request-budget',
    'starts': starts.map((at) => at.millisecondsSinceEpoch).toList(),
  }, validate: _decode);

  static List<DateTime> _decode(Uint8List bytes) {
    if (bytes.length > 65536) {
      throw const FormatException('Request window too large');
    }
    final root = jsonDecode(utf8.decode(bytes));
    if (root is! Map ||
        root['version'] != 1 ||
        root['source'] != 'application-request-budget' ||
        root['starts'] is! List) {
      throw const FormatException('Invalid request window');
    }
    final starts = root['starts'] as List;
    if (starts.length > 1000 ||
        starts.any((at) => at is! int || at < 0 || at > 8640000000000000)) {
      throw const FormatException('Invalid request start time');
    }
    return [
      for (final at in starts)
        DateTime.fromMillisecondsSinceEpoch(at as int, isUtc: true),
    ];
  }
}
