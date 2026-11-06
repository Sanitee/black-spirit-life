import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../domain/state/planner_state_json_codec.dart';
import 'atomic_file_store.dart';

/// One version-independent writer lease, outside the movable personal folder.
/// The OS releases the byte-range lock on process exit, including a crash.
class SharedProfileGuard {
  SharedProfileGuard(this.controlDirectory);

  static const markerName = '.black-spirit-life-shared.json';
  static const formatVersion = 1;
  final Directory controlDirectory;
  RandomAccessFile? _lease;
  Future<void>? _pending;

  Future<void> acquire() async {
    if (_lease != null) return;
    if (_pending case final pending?) return pending;
    final pending = _acquire();
    _pending = pending;
    try {
      await pending;
    } finally {
      _pending = null;
    }
  }

  Future<void> _acquire() async {
    await controlDirectory.create(recursive: true);
    final file = File('${controlDirectory.path}/shared-writer.lock');
    final handle = await file.open(mode: FileMode.append);
    try {
      await handle.lock(FileLock.exclusive, 0, 1);
      _lease = handle;
    } on Object {
      await handle.close();
      throw const FileSystemException(
        'Another Black Spirit Life window is using your shared data. '
        'Close it before opening this version.',
      );
    }
  }

  Future<void> verify(Directory directory) async {
    final marker = File('${directory.path}/$markerName');
    final state = File('${directory.path}/planner-state.json');
    for (final file in [marker, state]) {
      final type = await FileSystemEntity.type(file.path, followLinks: false);
      if (type != FileSystemEntityType.notFound &&
          type != FileSystemEntityType.file) {
        throw FileSystemException(
          'Shared profile records must be normal files.',
          file.path,
        );
      }
    }
    if (!await marker.exists()) {
      if (await directory.exists() && !await directory.list().isEmpty) {
        throw FileSystemException(
          'This folder is not a verified shared Black Spirit Life profile. '
          'Its contents were left unchanged.',
          directory.path,
        );
      }
      await _writeMarker(directory, requiresState: false);
    }
    final decoded = jsonDecode(await marker.readAsString());
    if (decoded is! Map ||
        decoded['application'] != 'Black Spirit Life' ||
        decoded['formatVersion'] != formatVersion ||
        decoded['minimumReaderVersion'] != formatVersion ||
        decoded['minimumWriterVersion'] != formatVersion ||
        decoded['requiresExistingState'] is! bool) {
      throw const FileSystemException(
        'This shared profile needs a different Black Spirit Life version. '
        'No saved data was changed.',
      );
    }
    if (await state.exists()) {
      final saved = jsonDecode(await state.readAsString());
      if (saved is! Map || saved['schemaVersion'] != 1) {
        throw const FileSystemException(
          'This saved profile is not compatible with this version. '
          'No saved data was changed.',
        );
      }
    } else if (decoded['requiresExistingState'] == true) {
      throw const FileSystemException(
        'Your shared planner save is missing. Restore its backup before '
        'continuing; a blank profile has not been created.',
      );
    }
  }

  Future<void> markInitialized(Directory directory) async {
    await verify(directory);
    final marker = File('${directory.path}/$markerName');
    final data = jsonDecode(await marker.readAsString()) as Map;
    if (data['requiresExistingState'] == true) return;
    if (!await File('${directory.path}/planner-state.json').exists()) return;
    await _writeMarker(directory, requiresState: true);
  }

  /// Used only after the previous Stable location and its complete directory
  /// identity have been validated. Never overwrite an existing shared marker.
  Future<void> adoptExistingProfile(Directory directory) async {
    final marker = File('${directory.path}/$markerName');
    final type = await FileSystemEntity.type(marker.path, followLinks: false);
    if (type != FileSystemEntityType.notFound) {
      await verify(directory);
      return;
    }
    final state = File('${directory.path}/planner-state.json');
    if (await FileSystemEntity.type(state.path, followLinks: false) !=
        FileSystemEntityType.file) {
      throw const FileSystemException(
        'The existing Stable save is unavailable. No new profile was selected.',
      );
    }
    const PlannerStateJsonCodec().decode(await state.readAsString());
    await _writeMarker(directory, requiresState: true);
  }

  Future<void> _writeMarker(
    Directory directory, {
    required bool requiresState,
  }) => AtomicFileStore(directory: directory, fileName: markerName).writeJson({
    'application': 'Black Spirit Life',
    'formatVersion': formatVersion,
    'minimumReaderVersion': formatVersion,
    'minimumWriterVersion': formatVersion,
    'requiresExistingState': requiresState,
  }, validate: (bytes) => jsonDecode(utf8.decode(bytes)));

  /// Explicitly used by disposable tests; normal app ownership lasts to exit.
  Future<void> release() async {
    final handle = _lease;
    _lease = null;
    if (handle != null) await handle.close();
  }
}
