import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../domain/models.dart';
import 'session_store.dart';

/// Receives only app-owned prepared-session receipts. No browser or Garmoth
/// account data is read; all history writes go through the existing store.
class SessionImportInbox {
  SessionImportInbox({
    required this.store,
    required this.catalog,
    required this.onChanged,
  });

  final SessionStore store;
  final Catalog catalog;
  final void Function() onChanged;
  String get directoryPath =>
      '${store.directory.absolute.path}${Platform.pathSeparator}session-import-inbox';
  String? get lastError => _lastError;
  String? _lastError;
  Timer? _timer;
  Future<void>? _draining;
  bool _disposed = false;
  static const maximumReceiptBytes = 64 * 1024;
  static final _fileName = RegExp(r'^([0-9a-f]{32})-([0-9]{10})\.json$');

  void start() {
    if (_disposed || _timer != null) return;
    unawaited(drain());
    _timer = Timer.periodic(
      const Duration(seconds: 2),
      (_) => unawaited(drain()),
    );
  }

  Future<void> drain() {
    if (_disposed) return Future<void>.value();
    return _draining ??= _drain().whenComplete(() => _draining = null);
  }

  /// Stops polling and waits for any receipt already being inspected. The
  /// inbox can be started again after a cancelled lifecycle operation.
  Future<void> pause() async {
    _timer?.cancel();
    _timer = null;
    await _draining;
  }

  Future<void> _drain() async {
    var changed = false;
    String? error;
    try {
      final directory = Directory(directoryPath);
      if (await FileSystemEntity.isLink(directoryPath)) {
        throw const FileSystemException('The session inbox cannot be a link.');
      }
      if (!await directory.exists()) return;
      final files = <File>[];
      await for (final entry in directory.list(followLinks: false)) {
        if (entry is File && _fileName.hasMatch(_basename(entry.path))) {
          files.add(entry);
        }
      }
      // Each immutable revision has its own file. Newest-first means an older
      // outstanding handoff can never temporarily roll back a newer session.
      files.sort((a, b) => b.path.compareTo(a.path));
      for (final file in files) {
        if (_disposed) break;
        try {
          final stat = await file.stat();
          if (stat.type != FileSystemEntityType.file ||
              stat.size <= 0 ||
              stat.size > maximumReceiptBytes) {
            throw const FormatException(
              'The local session receipt has an invalid size.',
            );
          }
          final contents = await file.readAsBytes();
          if (contents.length > maximumReceiptBytes) {
            throw const FormatException(
              'The local session receipt is too large.',
            );
          }
          final decoded = jsonDecode(utf8.decode(contents));
          if (decoded is! Map<String, dynamic>) {
            throw const FormatException(
              'The local session receipt is invalid.',
            );
          }
          final receipt = SessionImportMetadata.fromJson(decoded);
          final expected =
              '${receipt.importId.replaceAll('-', '')}-${receipt.revision.toString().padLeft(10, '0')}.json';
          if (_basename(file.path) != expected) {
            throw const FormatException(
              'The local session receipt identity does not match its file.',
            );
          }
          if (_disposed) break;
          changed =
              await store.upsertImported(
                sessionFromReceipt(receipt, catalog),
              ) ||
              changed;
          // Deletion is the acknowledgement, only after durable history save.
          // If cleanup fails, the same revision is harmless on the next drain.
          await file.delete();
        } catch (_) {
          error =
              'A prepared session could not be saved locally. Its receipt is kept for retry.';
        }
      }
    } catch (_) {
      error =
          'Local session history is temporarily unavailable. Prepared receipts are kept for retry.';
    }
    final errorChanged = _lastError != error;
    _lastError = error;
    if (!_disposed && (changed || errorChanged)) onChanged();
  }

  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _timer = null;
  }
}

String _basename(String path) => path.split(RegExp(r'[/\\]')).last;

/// Catalog mapping is optional. Unsupported activities remain honest history
/// records, never default to the first Gathering method or an invented price.
GatheringSession sessionFromReceipt(
  SessionImportMetadata receipt,
  Catalog catalog,
) {
  final linked = catalog.spots
      .where(
        (spot) => receipt.linkedSourceIds.any(
          (id) => id == spot.id || id == 'companion:${spot.id}',
        ),
      )
      .toList();
  final methodIds = <String>{};
  for (final id in receipt.methodIds) {
    if (catalog.methods.any((method) => method.id == id)) methodIds.add(id);
  }
  if (linked.length == 1) methodIds.addAll(linked.single.methodIds);
  const observedMethods = {
    'garmoth:meat': 'butcher',
    'garmoth:blood': 'fluid',
    'garmoth:sap': 'fluid',
    'garmoth:herb': 'hoe',
    'garmoth:stone': 'mining',
    'garmoth:timber': 'lumbering',
    'garmoth:tanning': 'tanning',
  };
  for (final id in receipt.methodIds) {
    final mapped = observedMethods[id];
    if (mapped != null) methodIds.add(mapped);
  }
  final methods = catalog.methods
      .where(
        (method) =>
            methodIds.contains(method.id) &&
            (method.activity == receipt.activity ||
                receipt.activity == 'hunting' && method.activity == 'sniper'),
      )
      .toList();
  final method = methods.length == 1 ? methods.single : null;
  final methodId = receipt.activity == 'grinding'
      ? 'grinding'
      : method?.id ?? receipt.activity;
  final methodLabel = receipt.activity == 'grinding'
      ? 'Grinding'
      : method?.label ??
            (receipt.activity == 'hunting' ? 'Hunting' : 'Gathering');
  return GatheringSession(
    id: receipt.sessionId,
    createdAt: receipt.importedAtUtc,
    methodId: methodId,
    methodLabel: methodLabel,
    methodIcon: receipt.activity == 'grinding' ? '' : method?.icon ?? '',
    spotId: linked.length == 1 ? linked.single.id : 'garmoth:${receipt.spotId}',
    spotName: receipt.spotName,
    durationSeconds: receipt.durationSeconds,
    loot: [
      for (final item in receipt.items)
        LootEntry(
          // Keep enhancement/name-only identities separate; they are not base IDs.
          id: item.itemId == null
              ? 'session-import-item:${item.identity}'
              : item.subKey == 0
              ? item.itemId!
              : '${item.itemId}:${item.subKey}',
          name: item.name,
          icon: item.itemId == null
              ? ''
              : catalog.items
                        .where((entry) => entry.id == item.itemId)
                        .firstOrNull
                        ?.icon ??
                    '',
          overrideTotal: item.quantity,
        ),
    ],
    buffs: const [],
    buffTotals: const {},
    catalogDate: catalog.reviewedAt,
    sessionImport: receipt,
  );
}
