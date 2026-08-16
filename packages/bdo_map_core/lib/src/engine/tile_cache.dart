import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import '../model/tile_source.dart';

/// A bounded, provider-namespaced disk cache for encoded map tiles.
class BdoMapDiskCache {
  BdoMapDiskCache({
    required Directory rootDirectory,
    required String sourceNamespace,
    this.maximumBytes = 64 * 1024 * 1024,
  }) : assert(maximumBytes > 0),
       directory = Directory(
         _join(rootDirectory.path, _safeNamespace(sourceNamespace)),
       );

  final Directory directory;
  final int maximumBytes;
  Future<void>? _initialization;
  Future<void> _mutationTail = Future<void>.value();
  int _writesSincePrune = 0;
  int? _knownBytes;

  Future<void> initialize() {
    return _initialization ??= _initialize();
  }

  Future<void> _initialize() async {
    await directory.create(recursive: true);
    await _serializeMutation(() async {
      _knownBytes = await _pruneUnlocked();
    });
  }

  Future<Uint8List?> read(
    BdoTileCoordinate coordinate, {
    required String extension,
  }) async {
    final safeExtension = _safeExtension(extension);
    try {
      await initialize();
      final file = _fileFor(coordinate, safeExtension);
      if (!await file.exists()) {
        return null;
      }
      final bytes = await file.readAsBytes();
      if (bytes.isEmpty) {
        await file.delete();
        return null;
      }
      try {
        await file.setLastAccessed(DateTime.now());
      } on FileSystemException {
        // Access-time updates are an optimization and can be disabled by the OS.
      }
      return bytes;
    } on FileSystemException {
      return null;
    }
  }

  Future<void> write(
    BdoTileCoordinate coordinate,
    Uint8List bytes, {
    required String extension,
  }) async {
    final safeExtension = _safeExtension(extension);
    if (bytes.isEmpty) {
      return;
    }
    // A single entry can never fit while preserving the configured invariant.
    // Do not evict useful existing entries for a payload that cannot be cached.
    if (bytes.length > maximumBytes) {
      return;
    }
    try {
      await initialize();
      await _serializeMutation(() async {
        final destination = _fileFor(coordinate, safeExtension);
        if (await destination.exists()) {
          return;
        }
        final knownBytes = _knownBytes ?? await _pruneUnlocked();
        if (knownBytes + bytes.length > maximumBytes) {
          // Leave headroom so normal tile streaming does not rescan the cache
          // for every subsequent write once it first reaches the limit.
          final targetAfterWrite = (maximumBytes * 88) ~/ 100;
          final targetBeforeWrite = targetAfterWrite > bytes.length
              ? targetAfterWrite - bytes.length
              : 0;
          _knownBytes = await _pruneUnlocked(targetBytes: targetBeforeWrite);
          // Locked or otherwise undeletable files must not let a new entry
          // push the provider namespace beyond its configured cap.
          if (_knownBytes! + bytes.length > maximumBytes) {
            return;
          }
        }
        final temporary = File(
          '${destination.path}.${pid}_${DateTime.now().microsecondsSinceEpoch}.tmp',
        );
        try {
          await temporary.writeAsBytes(bytes, flush: false);
          if (await destination.exists()) {
            await temporary.delete();
          } else {
            await temporary.rename(destination.path);
          }
        } on FileSystemException {
          try {
            if (await temporary.exists()) {
              await temporary.delete();
            }
          } on FileSystemException {
            // A failed cache write must never make the map unusable.
          }
          return;
        }
        _knownBytes = (_knownBytes ?? 0) + bytes.length;
        _writesSincePrune += 1;
        if (_writesSincePrune >= 32) {
          _writesSincePrune = 0;
          _knownBytes = await _pruneUnlocked();
        }
      });
    } on FileSystemException {
      // Disk caching is optional; network rendering must remain available.
    }
  }

  Future<int> byteSize() async {
    try {
      await initialize();
      return _serializeMutation(() async {
        _knownBytes = await _pruneUnlocked();
        return _knownBytes!;
      });
    } on FileSystemException {
      return 0;
    }
  }

  Future<void> prune() async {
    try {
      await initialize();
      await _serializeMutation(() async {
        _knownBytes = await _pruneUnlocked();
      });
    } on FileSystemException {
      // Pruning is best-effort.
    }
  }

  Future<int> _pruneUnlocked({int? targetBytes}) async {
    assert(targetBytes == null || targetBytes >= 0);
    await directory.create(recursive: true);
    final files = <({File file, int length, DateTime usedAt})>[];
    var total = 0;
    await for (final entity in directory.list()) {
      if (entity is! File) {
        continue;
      }
      if (entity.path.endsWith('.tmp')) {
        try {
          final stat = await entity.stat();
          if (DateTime.now().difference(stat.modified) >
              const Duration(hours: 1)) {
            await entity.delete();
          }
        } on FileSystemException {
          // Ignore files concurrently removed by another instance.
        }
        continue;
      }
      try {
        final stat = await entity.stat();
        total += stat.size;
        files.add((
          file: entity,
          length: stat.size,
          usedAt: stat.accessed.isAfter(stat.modified)
              ? stat.accessed
              : stat.modified,
        ));
      } on FileSystemException {
        // Ignore files concurrently removed by another instance.
      }
    }
    final requestedTarget = targetBytes;
    if (requestedTarget == null && total <= maximumBytes) {
      return total;
    }
    if (requestedTarget != null && total <= requestedTarget) {
      return total;
    }
    files.sort((a, b) => a.usedAt.compareTo(b.usedAt));
    final target = requestedTarget ?? (maximumBytes * 0.88).round();
    for (final entry in files) {
      if (total <= target) {
        break;
      }
      try {
        await entry.file.delete();
        total -= entry.length;
      } on FileSystemException {
        // Continue pruning the remaining candidates.
      }
    }
    return total;
  }

  /// Removes only this provider namespace and leaves the cache root intact.
  ///
  /// Mutations are serialized so a tile write that started before this call
  /// cannot reappear after the clear operation completes.
  Future<int> clear() async {
    try {
      await initialize();
      return _serializeMutation(() async {
        var removedBytes = 0;
        await for (final entity in directory.list()) {
          if (entity is! File) {
            continue;
          }
          try {
            final length = await entity.length();
            await entity.delete();
            removedBytes += length;
          } on FileSystemException {
            // Continue clearing the remaining provider-owned cache files.
          }
        }
        _writesSincePrune = 0;
        // A locked file may have survived the best-effort deletion loop.
        // Recount it so a later write cannot understate the cache size.
        _knownBytes = await _pruneUnlocked(targetBytes: 0);
        return removedBytes;
      });
    } on FileSystemException {
      return 0;
    }
  }

  /// Invalidates one unreadable cache entry so a later request can use the
  /// network instead of repeatedly loading poisoned bytes.
  Future<void> remove(
    BdoTileCoordinate coordinate, {
    required String extension,
  }) async {
    final safeExtension = _safeExtension(extension);
    try {
      await initialize();
      await _serializeMutation(() async {
        final file = _fileFor(coordinate, safeExtension);
        if (await file.exists()) {
          final length = await file.length();
          await file.delete();
          final knownBytes = _knownBytes;
          if (knownBytes != null) {
            final remaining = knownBytes - length;
            _knownBytes = remaining < 0 ? 0 : remaining;
          }
        }
      });
    } on FileSystemException {
      // Invalidation is best-effort.
    }
  }

  Future<T> _serializeMutation<T>(Future<T> Function() operation) {
    final result = _mutationTail.then((_) => operation());
    _mutationTail = result.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {
        // Keep the serialization chain usable after the caller sees the error.
      },
    );
    return result;
  }

  File _fileFor(BdoTileCoordinate coordinate, String extension) {
    return File(
      _join(
        directory.path,
        '${coordinate.zoom}_${coordinate.x}_${coordinate.y}.$extension',
      ),
    );
  }

  static String _join(String first, String second) {
    final separator = Platform.pathSeparator;
    if (first.endsWith(separator)) {
      return '$first$second';
    }
    return '$first$separator$second';
  }

  static String _safeNamespace(String sourceNamespace) {
    final trimmed = sourceNamespace.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError.value(
        sourceNamespace,
        'sourceNamespace',
        'must not be empty',
      );
    }
    final sanitized = trimmed.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
    // Dot-only names have special path semantics on supported desktop file
    // systems. Reject all of them rather than allowing "." or ".." to select
    // the cache root or its parent.
    if (RegExp(r'^\.+$').hasMatch(sanitized)) {
      throw ArgumentError.value(
        sourceNamespace,
        'sourceNamespace',
        'must identify a provider-specific child directory',
      );
    }
    return sanitized;
  }

  static String _safeExtension(String extension) {
    final trimmed = extension.trim();
    if (!RegExp(r'^[a-zA-Z0-9]{1,16}$').hasMatch(trimmed)) {
      throw ArgumentError.value(
        extension,
        'extension',
        'must contain 1 to 16 ASCII letters or digits',
      );
    }
    return trimmed;
  }
}
