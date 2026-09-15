import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

typedef AtomicFileValidator = FutureOr<void> Function(Uint8List bytes);

abstract interface class AtomicFileCommitter {
  Future<void> replace(File stagedFile, File targetFile);
}

class RenameAtomicFileCommitter implements AtomicFileCommitter {
  const RenameAtomicFileCommitter();

  @override
  Future<void> replace(File stagedFile, File targetFile) async {
    await stagedFile.rename(targetFile.path);
  }
}

class AtomicWriteResult {
  const AtomicWriteResult({
    required this.targetPath,
    required this.sha256,
    required this.byteCount,
    this.backupPath,
  });

  final String targetPath;
  final String sha256;
  final int byteCount;
  final String? backupPath;
}

class AtomicFileStore {
  AtomicFileStore({
    required this.directory,
    required String fileName,
    this.committer = const RenameAtomicFileCommitter(),
    DateTime Function()? utcNow,
    this.backupsToKeep = 3,
    this.preserveMalformedTarget = false,
  }) : _fileName = _validateLeafName(fileName),
       _utcNow = utcNow ?? (() => DateTime.now().toUtc()) {
    if (backupsToKeep < 1) {
      throw ArgumentError.value(
        backupsToKeep,
        'backupsToKeep',
        'Must be positive.',
      );
    }
  }

  final Directory directory;
  final String _fileName;
  final AtomicFileCommitter committer;
  final DateTime Function() _utcNow;
  final int backupsToKeep;

  /// Disposable caches may retain an invalid original before replacing it.
  /// Settings and other authoritative state keep the strict default.
  final bool preserveMalformedTarget;
  Future<void> _tail = Future<void>.value();
  int _sequence = 0;

  String get targetPath => _join(directory.path, _fileName);

  Future<AtomicWriteResult> writeJson(
    Object? value, {
    required AtomicFileValidator validate,
  }) => writeBytes(
    Uint8List.fromList(utf8.encode(jsonEncode(value))),
    validate: validate,
  );

  Future<AtomicWriteResult> writeBytes(
    Uint8List bytes, {
    required AtomicFileValidator validate,
  }) {
    final snapshot = Uint8List.fromList(bytes);
    final operation = _tail.then(
      (_) => _writeBytes(snapshot, validate: validate),
    );
    _tail = operation.then<void>(
      (_) => null,
      // A failed write must not poison serialization of later recovery writes.
      onError: (_, _) => null,
    );
    return operation;
  }

  Future<AtomicWriteResult> _writeBytes(
    Uint8List bytes, {
    required AtomicFileValidator validate,
  }) async {
    await directory.create(recursive: true);
    final token = _token();
    final staged = File(_join(directory.path, '.$_fileName.$token.tmp'));
    File? backup;

    try {
      await _writeAndFlush(staged, bytes);
      final stagedBytes = await staged.readAsBytes();
      await Future<void>.sync(() => validate(stagedBytes));
      final stagedHash = sha256.convert(stagedBytes).toString().toUpperCase();
      final target = File(targetPath);

      if (await target.exists()) {
        final previousBytes = await target.readAsBytes();
        var malformed = false;
        try {
          await Future<void>.sync(() => validate(previousBytes));
        } on FormatException {
          if (!preserveMalformedTarget) rethrow;
          malformed = true;
        }
        if (malformed) {
          // Keep the active target in place until the validated replacement
          // commits. In particular, a request ledger must never disappear
          // between quarantine and replacement after a crash.
          final preserved = await _createPreservedOriginal(token);
          await _writeAndFlush(preserved, previousBytes);
          final preservedBytes = await preserved.readAsBytes();
          if (preservedBytes.length != previousBytes.length ||
              sha256.convert(preservedBytes) != sha256.convert(previousBytes)) {
            throw const FileSystemException(
              'Could not preserve the malformed cache original.',
            );
          }
        } else {
          final backupName = '$_fileName.backup-$token';
          backup = File(_join(directory.path, backupName));
          await _writeAndFlush(backup, previousBytes);
        }
      }

      await committer.replace(staged, target);
      final committedBytes = await target.readAsBytes();
      await Future<void>.sync(() => validate(committedBytes));
      final committedHash = sha256
          .convert(committedBytes)
          .toString()
          .toUpperCase();
      if (committedHash != stagedHash ||
          committedBytes.length != stagedBytes.length) {
        await _restoreBackupIfPossible(target, backup, validate);
        throw const FileSystemException(
          'Committed state did not match the validated staged bytes.',
        );
      }

      await _rotateBackups();
      return AtomicWriteResult(
        targetPath: target.path,
        sha256: committedHash,
        byteCount: committedBytes.length,
        backupPath: backup?.path,
      );
    } finally {
      if (await staged.exists()) {
        await staged.delete();
      }
    }
  }

  Future<void> _restoreBackupIfPossible(
    File target,
    File? backup,
    AtomicFileValidator validate,
  ) async {
    if (backup == null || !await backup.exists()) return;
    final recoveryBytes = await backup.readAsBytes();
    await Future<void>.sync(() => validate(recoveryBytes));
    final recovery = File(
      _join(directory.path, '.$_fileName.${_token()}.recovery.tmp'),
    );
    try {
      await _writeAndFlush(recovery, recoveryBytes);
      await committer.replace(recovery, target);
    } finally {
      if (await recovery.exists()) await recovery.delete();
    }
  }

  Future<void> _writeAndFlush(File file, List<int> bytes) async {
    final handle = await file.open(mode: FileMode.writeOnly);
    try {
      await handle.writeFrom(bytes);
      await handle.flush();
    } finally {
      await handle.close();
    }
  }

  Future<File> _createPreservedOriginal(String token) async {
    for (var suffix = 0; ; suffix++) {
      final file = File(
        _join(directory.path, '$_fileName.corrupt-$token-$suffix'),
      );
      try {
        return await file.create(exclusive: true);
      } on FileSystemException {
        if (await FileSystemEntity.type(file.path) ==
            FileSystemEntityType.notFound) {
          rethrow;
        }
      }
    }
  }

  Future<void> _rotateBackups() async {
    final backups = await directory
        .list(followLinks: false)
        .where((entity) {
          if (entity is! File) return false;
          final name = entity.uri.pathSegments.last;
          return name.startsWith('$_fileName.backup-');
        })
        .cast<File>()
        .toList();
    backups.sort((left, right) => right.path.compareTo(left.path));
    for (final oldBackup in backups.skip(backupsToKeep)) {
      await oldBackup.delete();
    }
  }

  String _token() {
    final timestamp = _utcNow().toUtc().microsecondsSinceEpoch;
    return '$timestamp-${_sequence++}';
  }

  static String _validateLeafName(String value) {
    if (value.isEmpty ||
        value == '.' ||
        value == '..' ||
        value.contains('/') ||
        value.contains('\\')) {
      throw ArgumentError.value(
        value,
        'fileName',
        'Must be a single file name.',
      );
    }
    return value;
  }

  static String _join(String parent, String child) {
    final separator = Platform.pathSeparator;
    return parent.endsWith(separator)
        ? '$parent$child'
        : '$parent$separator$child';
  }
}
