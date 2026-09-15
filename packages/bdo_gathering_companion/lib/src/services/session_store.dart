import 'dart:async';
import 'dart:convert';
import 'dart:io';
import '../domain/gathering_preparation.dart';
import '../domain/models.dart';
import 'stable_v017_migration.dart';

class SessionStore {
  SessionStore({Directory? directory})
    : directory =
          directory ??
          Directory(
            '${Platform.environment['APPDATA'] ?? Directory.current.path}${Platform.pathSeparator}BDO Gathering Companion',
          );
  final Directory directory;
  final List<GatheringSession> sessions = [];
  Map<String, dynamic> preferences = {};
  bool recoveredBackup = false;
  bool _writing = false;
  Future<void> _operations = Future<void>.value();
  final Object _operationZone = Object();
  bool _mutationsFrozen = false;
  Object? _lastPersistenceError;
  StackTrace? _lastPersistenceStack;

  bool get mutationsFrozen => _mutationsFrozen;

  /// Rejects mutations submitted after this call. Already accepted operations
  /// remain queued and can be awaited with [flush].
  void freezeNewMutations() => _mutationsFrozen = true;

  void resumeMutations() => _mutationsFrozen = false;

  void _ensureMutationAllowed() {
    if (_mutationsFrozen && Zone.current[_operationZone] != true) {
      throw StateError('Gathering data is temporarily frozen.');
    }
  }

  /// Waits for all serialized work and surfaces the latest persistence error.
  Future<void> flush() async {
    await _operations;
    final error = _lastPersistenceError;
    if (error != null) {
      Error.throwWithStackTrace(
        error,
        _lastPersistenceStack ?? StackTrace.current,
      );
    }
  }

  // Mutations and their rollback snapshots share one queue, including imports.
  // Keep calling virtual save() so existing in-memory/test stores retain their
  // persistence contract. A save inside its owning operation must not requeue.
  Future<T> _serialize<T>(Future<T> Function() action) {
    final next = _operations.then(
      (_) => runZoned(action, zoneValues: {_operationZone: true}),
    );
    final settled = Completer<void>();
    _operations = settled.future;
    unawaited(
      next.then<void>(
        (_) => settled.complete(),
        onError: (Object _, StackTrace _) => settled.complete(),
      ),
    );
    return next;
  }

  File get file =>
      File('${directory.path}${Platform.pathSeparator}sessions.json');
  Future<void> load() => _serialize(_load);
  Future<void> _load() async {
    if (!await file.exists()) return;
    try {
      _decode(await file.readAsString());
    } catch (error) {
      final backup = File('${file.path}.bak');
      if (!await backup.exists()) rethrow;
      _decode(await backup.readAsString());
      recoveredBackup = true;
    }
  }

  void _decode(String text) {
    final j = objectMap(jsonDecode(text));
    if (j['schemaVersion'] != 1 || j['sessions'] is! List) {
      throw const FormatException(
        'Session file has an unsupported format. No data was changed.',
      );
    }
    final records = j['sessions'] as List;
    if (records.any((s) => s is! Map)) {
      throw const FormatException(
        'Session history contains a damaged record. No data was changed.',
      );
    }
    final parsed = objectList(
      j['sessions'],
    ).map(GatheringSession.fromJson).toList();
    if (parsed.map((s) => s.id).toSet().length != parsed.length) {
      throw const FormatException(
        'Session history contains duplicate records. No data was changed.',
      );
    }
    sessions
      ..clear()
      ..addAll(parsed);
    final prefs = objectMap(j['preferences']);
    final stableMigrationMarker =
        prefs.containsKey(stableV017GatheringMigrationPreferenceKey)
        ? readStableV017GatheringMigrationMarker(
            prefs[stableV017GatheringMigrationPreferenceKey],
          )
        : null;
    final stableLoadoutNotes =
        prefs.containsKey(stableV017GatheringLoadoutNotesPreferenceKey)
        ? readStableV017GatheringLoadoutNotes(
            prefs[stableV017GatheringLoadoutNotesPreferenceKey],
          )
        : null;
    preferences = {
      for (final key in ['methodId', 'spotId'])
        if (prefs[key] is String) key: prefs[key],
      if (prefs['glassOpacityPercent'] case final num opacity
          when opacity.isFinite)
        'glassOpacityPercent': opacity.round().clamp(0, 100),
      if (prefs['gatheringEstimateSetup'] is Map)
        'gatheringEstimateSetup': objectMap(prefs['gatheringEstimateSetup']),
      if (prefs[gatheringPreparationPreferenceKey] is Map)
        gatheringPreparationPreferenceKey: objectMap(
          prefs[gatheringPreparationPreferenceKey],
        ),
      stableV017GatheringMigrationPreferenceKey: ?stableMigrationMarker,
      stableV017GatheringLoadoutNotesPreferenceKey: ?stableLoadoutNotes,
    };
  }

  Future<void> save() {
    if (Zone.current[_operationZone] == true) return _save();
    _ensureMutationAllowed();
    return _serialize(_save);
  }

  Future<void> _save() async {
    if (_writing) throw StateError('Another save is still in progress.');
    _writing = true;
    try {
      final stableMigrationMarker =
          preferences.containsKey(stableV017GatheringMigrationPreferenceKey)
          ? readStableV017GatheringMigrationMarker(
              preferences[stableV017GatheringMigrationPreferenceKey],
            )
          : null;
      final stableLoadoutNotes =
          preferences.containsKey(stableV017GatheringLoadoutNotesPreferenceKey)
          ? readStableV017GatheringLoadoutNotes(
              preferences[stableV017GatheringLoadoutNotesPreferenceKey],
            )
          : null;
      await directory.create(recursive: true);
      final contents = const JsonEncoder.withIndent('  ').convert({
        'schemaVersion': 1,
        'sessions': sessions.map((s) => s.toJson()).toList(),
        'preferences': {
          for (final key in ['methodId', 'spotId'])
            if (preferences[key] is String) key: preferences[key],
          if (preferences['glassOpacityPercent'] case final num opacity
              when opacity.isFinite)
            'glassOpacityPercent': opacity.round().clamp(0, 100),
          if (preferences['gatheringEstimateSetup'] is Map)
            'gatheringEstimateSetup': objectMap(
              preferences['gatheringEstimateSetup'],
            ),
          if (preferences[gatheringPreparationPreferenceKey] is Map)
            gatheringPreparationPreferenceKey: objectMap(
              preferences[gatheringPreparationPreferenceKey],
            ),
          stableV017GatheringMigrationPreferenceKey: ?stableMigrationMarker,
          stableV017GatheringLoadoutNotesPreferenceKey: ?stableLoadoutNotes,
        },
      });
      final temporary = File('${file.path}.tmp');
      await temporary.writeAsString(contents, flush: true);
      // A single bounded backup; input screenshots are never part of this file.
      if (await file.exists() && !recoveredBackup) {
        await file.copy('${file.path}.bak');
      }
      await temporary.rename(file.path);
      recoveredBackup = false;
      _lastPersistenceError = null;
      _lastPersistenceStack = null;
    } catch (error, stack) {
      _lastPersistenceError = error;
      _lastPersistenceStack = stack;
      rethrow;
    } finally {
      _writing = false;
    }
  }

  Future<void> upsert(GatheringSession session) {
    _ensureMutationAllowed();
    return _serialize(() => _upsert(session));
  }

  Future<void> _upsert(
    GatheringSession session, {
    bool replacingImport = false,
  }) async {
    final current = sessions.where((row) => row.id == session.id).firstOrNull;
    if (!replacingImport &&
        current?.sessionImport != null &&
        jsonEncode(current!.sessionImport!.toJson()) !=
            jsonEncode(session.sessionImport?.toJson())) {
      throw StateError(
        'This imported session was updated. Reopen it before saving edits.',
      );
    }
    final previous = List<GatheringSession>.from(sessions);
    sessions.removeWhere((s) => s.id == session.id);
    sessions.insert(0, session);
    try {
      await save();
    } catch (_) {
      sessions
        ..clear()
        ..addAll(previous);
      rethrow;
    }
  }

  /// A stable import replaces its earlier revision, never a manual session.
  /// Duplicate/older receipts need no write; conflicting equal revisions fail.
  Future<bool> upsertImported(GatheringSession session) {
    _ensureMutationAllowed();
    return _serialize(() async {
      final incoming = session.sessionImport;
      if (incoming == null || session.id != incoming.sessionId) {
        throw const FormatException(
          'The imported session identity is invalid.',
        );
      }
      final existing = sessions
          .where((row) => row.id == session.id)
          .firstOrNull;
      if (existing != null) {
        final previous = existing.sessionImport;
        if (previous == null ||
            previous.importId != incoming.importId ||
            previous.importedAtUtc != incoming.importedAtUtc) {
          throw const FormatException(
            'The imported session conflicts with existing history.',
          );
        }
        if (previous.revision > incoming.revision) return false;
        if (previous.revision == incoming.revision) {
          if (jsonEncode(previous.toJson()) != jsonEncode(incoming.toJson())) {
            throw const FormatException(
              'The imported session revision has changed.',
            );
          }
          return false;
        }
      }
      final updated = existing == null
          ? session
          : GatheringSession.fromJson({
              ...session.toJson(),
              // The native receipt owns reviewed inputs, not local annotations or
              // recorded preparation. Keep them, including their historical values.
              'notes': existing.notes,
              'createdAt': existing.createdAt.toUtc().toIso8601String(),
              'mastery': existing.mastery,
              'buffs': existing.toJson()['buffs'],
              'pets': existing.toJson()['pets'],
              'buffTotals': existing.buffTotals,
              'preparationSnapshot': existing.preparationSnapshot,
              'catalogDate': existing.catalogDate,
            });
      await _upsert(updated, replacingImport: true);
      return true;
    });
  }

  Future<void> remove(String id) {
    _ensureMutationAllowed();
    return _serialize(() => _remove(id));
  }

  Future<void> _remove(String id) async {
    final previous = List<GatheringSession>.from(sessions);
    sessions.removeWhere((s) => s.id == id);
    try {
      await save();
    } catch (_) {
      sessions
        ..clear()
        ..addAll(previous);
      rethrow;
    }
  }
}
