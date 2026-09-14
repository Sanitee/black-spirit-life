import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../../domain/market/market_request_pause.dart';
import '../persistence/atomic_file_store.dart';

/// Server pauses are operational state, not prices or evidence of zero stock.
/// Keep them separate so a restart cannot shorten a server's waiting period.
final class MarketPauseStore {
  MarketPauseStore({
    required Directory directory,
    DateTime Function()? utcNow,
    AtomicFileCommitter committer = const RenameAtomicFileCommitter(),
  }) : _file = AtomicFileStore(
         directory: directory,
         fileName: 'market-request-pauses.json',
         utcNow: utcNow,
         committer: committer,
       );

  static const _maxBytes = 16384;
  final AtomicFileStore _file;
  String get path => _file.targetPath;

  Future<Map<String, MarketRequestPause>> load() async {
    final file = File(path);
    if (!await file.exists()) return {};
    if (await file.length() > _maxBytes) {
      throw const FormatException('Market pause file is too large');
    }
    return _decode(await file.readAsBytes());
  }

  Future<void> save(Map<String, MarketRequestPause> pauses) => _file.writeJson({
    'version': 1,
    'source': 'pearl-abyss',
    'regions': {
      for (final entry in pauses.entries)
        entry.key: {
          'reason': entry.value.reason.name,
          'retryAt': entry.value.retryAt.millisecondsSinceEpoch,
        },
    },
  }, validate: _decode);

  static Map<String, MarketRequestPause> _decode(Uint8List bytes) {
    if (bytes.length > _maxBytes) {
      throw const FormatException('Market pause file is too large');
    }
    final decoded = jsonDecode(utf8.decode(bytes));
    if (decoded is! Map ||
        decoded['version'] != 1 ||
        decoded['source'] != 'pearl-abyss' ||
        decoded['regions'] is! Map) {
      throw const FormatException('Unsupported market pause file');
    }
    final regions = decoded['regions'] as Map;
    if (regions.length > 2) {
      throw const FormatException('Too many market pause regions');
    }
    final result = <String, MarketRequestPause>{};
    for (final entry in regions.entries) {
      final row = entry.value;
      if (!const ['eu', 'na'].contains(entry.key) || row is! Map) {
        throw const FormatException('Invalid market pause region');
      }
      final reason = MarketRequestPauseReason.values
          .where((reason) => reason.name == row['reason'])
          .firstOrNull;
      final at = row['retryAt'];
      if (reason == null || at is! int || at < 0 || at > 8640000000000000) {
        throw const FormatException('Invalid market pause');
      }
      // Expiring a local timer is not proof that a protective denial ended.
      // Preserve both kinds; the caller decides whether resumption is allowed.
      result[entry.key as String] = MarketRequestPause(
        reason: reason,
        retryAt: DateTime.fromMillisecondsSinceEpoch(at, isUtc: true),
      );
    }
    return result;
  }
}
