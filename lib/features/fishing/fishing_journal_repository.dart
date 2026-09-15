import 'dart:convert';
import 'dart:io';

import '../../data/persistence/atomic_file_store.dart';
import 'fishing_models.dart';

class FishingJournalRepository {
  FishingJournalRepository(Directory personalDataRoot)
    : directory = Directory(_join(personalDataRoot.path, directoryName)),
      _store = AtomicFileStore(
        directory: Directory(_join(personalDataRoot.path, directoryName)),
        fileName: fileName,
      );

  static const String directoryName = 'fishing';
  static const String fileName = 'fishing-journal.json';

  final Directory directory;
  final AtomicFileStore _store;
  Future<void> _pendingWrite = Future<void>.value();

  String get path => _store.targetPath;

  /// A missing journal is an empty journal. This method deliberately does not
  /// create a directory and does not search any legacy or alternate location.
  Future<FishingJournal> load() async {
    final target = File(path);
    if (!await target.exists()) return FishingJournal();
    return FishingJournal.fromJson(jsonDecode(await target.readAsString()));
  }

  Future<void> save(FishingJournal journal) {
    final operation = _store
        .writeJson(
          journal.toJson(),
          validate: (bytes) {
            FishingJournal.fromJson(jsonDecode(utf8.decode(bytes)));
          },
        )
        .then<void>((_) {});
    _pendingWrite = operation;
    return operation;
  }

  /// Completes after the newest write issued through this repository.
  Future<void> flush() => _pendingWrite;
}

String _join(String parent, String child) {
  final separator = Platform.pathSeparator;
  return parent.endsWith(separator)
      ? '$parent$child'
      : '$parent$separator$child';
}
