import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../../domain/opportunities/opportunity_market_models.dart';
import '../persistence/atomic_file_store.dart';

/// A separate, bounded history of official cumulative sales counters.
/// Raw quotes/books have a separate cache. The profile directory is caller-owned.
final class OpportunityMarketObservationStore {
  OpportunityMarketObservationStore({
    required Directory directory,
    DateTime Function()? utcNow,
    AtomicFileCommitter committer = const RenameAtomicFileCommitter(),
  }) : _utcNow = utcNow ?? (() => DateTime.now().toUtc()),
       _file = AtomicFileStore(
         directory: directory,
         fileName: 'opportunity-market-observations.json',
         utcNow: utcNow,
         committer: committer,
       );

  static const _maxItems = 10000;
  static const _maxSamples = 128;
  static const _retention = Duration(days: 7);
  static const _spacing = Duration(minutes: 15);
  final AtomicFileStore _file;
  final DateTime Function() _utcNow;
  Map<String, List<_Observation>> _series = {};
  Future<void> _tail = Future<void>.value();

  String get path => _file.targetPath;

  Future<void> load() async {
    await _tail;
    final file = File(path);
    if (!await file.exists()) return;
    if (await file.length() > 64 * 1024 * 1024) {
      throw const FormatException('Market observation file is too large');
    }
    _series = _decode(await file.readAsBytes());
  }

  Future<void> record(String region, Iterable<OpportunityMarketItem> items) {
    final snapshot = items.toList(growable: false);
    final operation = _tail.then((_) async {
      final next = {
        for (final entry in _series.entries) entry.key: entry.value.toList(),
      };
      final now = _utcNow().toUtc();
      for (final item in snapshot) {
        final at = item.quoteFetchedAt;
        final count = item.totalTrades;
        if (at == null ||
            at.isAfter(now) ||
            count == null ||
            count < 0 ||
            item.unlisted) {
          continue;
        }
        final key = _key(region, item.itemId, item.subId);
        final history = next.putIfAbsent(key, () => []);
        if (history.isNotEmpty && !at.isAfter(history.last.at)) continue;
        if (history.isNotEmpty && count < history.last.count) history.clear();
        final observation = _Observation(at.toUtc(), count);
        // Keep the initial baseline, but coalesce repeated refreshes into one
        // recent observation so a busy session cannot erase the useful interval.
        if (history.length > 1 &&
            at.difference(history[history.length - 2].at) < _spacing) {
          history[history.length - 1] = observation;
        } else {
          history.add(observation);
        }
        history.removeWhere((entry) => now.difference(entry.at) > _retention);
        if (history.length > _maxSamples) {
          history.removeRange(0, history.length - _maxSamples);
        }
      }
      next.removeWhere(
        (_, history) =>
            history.isEmpty || now.difference(history.last.at) > _retention,
      );
      if (next.length > _maxItems) {
        final oldest = next.keys.toList()
          ..sort((a, b) => next[a]!.last.at.compareTo(next[b]!.last.at));
        for (final key in oldest.take(next.length - _maxItems)) {
          next.remove(key);
        }
      }
      await _file.writeJson({
        'version': 1,
        'source': 'pearl-abyss',
        'series': {
          for (final entry in next.entries)
            entry.key: [
              for (final point in entry.value)
                [point.at.millisecondsSinceEpoch, point.count],
            ],
        },
      }, validate: _decode);
      _series = next;
    });
    _tail = operation.then<void>(
      (_) => null,
      onError: (Object _, StackTrace _) => null,
    );
    return operation;
  }

  OpportunitySalesActivity? activityFor(
    String region,
    String itemId, {
    int subId = 0,
    DateTime? now,
    Duration minInterval = const Duration(hours: 1),
    Duration maxAge = const Duration(hours: 24),
  }) {
    final instant = (now ?? _utcNow()).toUtc();
    final history = _series[_key(region, itemId, subId)];
    if (history == null ||
        history.length < 2 ||
        minInterval <= Duration.zero ||
        maxAge < minInterval) {
      return null;
    }
    final points = history
        .where(
          (point) =>
              !point.at.isAfter(instant) &&
              instant.difference(point.at) <= maxAge,
        )
        .toList();
    if (points.length < 2) return null;
    final first = points.first;
    final last = points.last;
    if (last.at.difference(first.at) < minInterval ||
        last.count < first.count) {
      return null;
    }
    return OpportunitySalesActivity(
      soldCount: last.count - first.count,
      startedAt: first.at,
      endedAt: last.at,
    );
  }

  Map<String, OpportunityMarketItem> withActivity(
    String region,
    Map<String, OpportunityMarketItem> items, {
    DateTime? now,
  }) => Map.unmodifiable({
    for (final entry in items.entries)
      entry.key: entry.value.withSalesActivity(
        activityFor(
          region,
          entry.value.itemId,
          subId: entry.value.subId,
          now: now,
        ),
      ),
  });

  static String _key(String region, String id, int subId) =>
      '${region.toLowerCase()}:$id:$subId';

  static Map<String, List<_Observation>> _decode(Uint8List bytes) {
    if (bytes.length > 64 * 1024 * 1024) {
      throw const FormatException('Market observation file is too large');
    }
    final root = jsonDecode(utf8.decode(bytes));
    if (root is! Map ||
        root['version'] != 1 ||
        root['source'] != 'pearl-abyss' ||
        root['series'] is! Map) {
      throw const FormatException('Unsupported market observation file');
    }
    final result = <String, List<_Observation>>{};
    final rawSeries = root['series'] as Map;
    if (rawSeries.length > _maxItems) {
      throw const FormatException('Too many market observations');
    }
    for (final entry in rawSeries.entries) {
      if (entry.key is! String ||
          !RegExp(r'^(eu|na):[1-9]\d*:\d+$').hasMatch(entry.key as String) ||
          entry.value is! List) {
        throw const FormatException('Invalid market observation key');
      }
      final rows = entry.value as List;
      if (rows.isEmpty || rows.length > _maxSamples) {
        throw const FormatException('Invalid market history size');
      }
      final history = <_Observation>[];
      for (final row in rows) {
        if (row is! List ||
            row.length != 2 ||
            row[0] is! int ||
            row[1] is! int ||
            (row[0] as int) < 0 ||
            (row[1] as int) < 0) {
          throw const FormatException('Invalid market observation');
        }
        final point = _Observation(
          DateTime.fromMillisecondsSinceEpoch(row[0] as int, isUtc: true),
          row[1] as int,
        );
        if (history.isNotEmpty &&
            (!point.at.isAfter(history.last.at) ||
                point.count < history.last.count)) {
          throw const FormatException('Invalid market observation sequence');
        }
        history.add(point);
      }
      result[entry.key as String] = history;
    }
    return result;
  }
}

final class _Observation {
  const _Observation(this.at, this.count);
  final DateTime at;
  final int count;
}
