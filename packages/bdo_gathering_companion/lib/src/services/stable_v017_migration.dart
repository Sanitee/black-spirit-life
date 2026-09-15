import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

import '../domain/bairog_calculator.dart';
import '../domain/gathering_preparation.dart';
import '../domain/models.dart';

const stableV017GatheringMigrationPreferenceKey =
    'migration.stable-v0.1.7.gathering';
const stableV017GatheringLoadoutNotesPreferenceKey =
    'migration.stable-v0.1.7.gathering.loadoutNotes';
const stableV017GatheringMigrationVersion = 'stable-v0.1.7-gathering-v1';

const _knownMethodIds = <String, String>{
  'Butchering': 'butcher',
  'Fluid collecting': 'fluid',
  'Hoe gathering': 'hoe',
  'Lumbering': 'lumbering',
  'Mining': 'mining',
  'Tanning': 'tanning',
  'Hunting': 'hunting',
};

/// Converts the selected stable v0.1.7 Gathering file into the current
/// companion store. Existing current data always wins and is never merged or
/// overwritten. The stable source remains in place and is also archived byte
/// for byte before the converted destination is committed.
Future<bool> migrateStableV017GatheringData({
  required Directory directory,
  DateTime Function()? nowUtc,
}) async {
  final source = File(_join(directory.path, 'gathering-state.json'));
  final destination = File(_join(directory.path, 'sessions.json'));
  if (!await source.exists() || await destination.exists()) return false;

  final sourceBytes = await source.readAsBytes();
  final sourceData = _StableV017GatheringData.fromBytes(sourceBytes);
  final sourceSha256 = sha256.convert(sourceBytes).toString();
  final archiveRelativePath =
      'migration-archive/v0.1.7/gathering-state.$sourceSha256.json';
  final archive = File(
    _join(
      directory.parent.path,
      _join(
        'migration-archive',
        _join('v0.1.7', 'gathering-state.$sourceSha256.json'),
      ),
    ),
  );

  await _ensureExactArchive(archive, sourceBytes);
  final currentSourceBytes = await source.readAsBytes();
  if (!_sameBytes(sourceBytes, currentSourceBytes)) {
    throw const FileSystemException(
      'The stable v0.1.7 Gathering file changed during migration.',
    );
  }

  final migratedAt = (nowUtc?.call() ?? DateTime.now()).toUtc();
  final converted = _convertedDocument(
    sourceData,
    sourceSha256: sourceSha256,
    archiveRelativePath: archiveRelativePath,
    migratedAt: migratedAt,
  );
  final destinationBytes = utf8.encode(
    const JsonEncoder.withIndent('  ').convert(converted),
  );
  _validateConvertedDocument(destinationBytes);

  return _writeNewFileAtomically(destination, destinationBytes);
}

Map<String, dynamic> readStableV017GatheringMigrationMarker(Object? value) {
  if (value is! Map) {
    throw const FormatException(
      'The stable v0.1.7 Gathering migration marker is damaged.',
    );
  }
  final marker = Map<String, dynamic>.from(value);
  final sourceSha256 = marker['sourceSha256'];
  final archiveRelativePath = marker['archiveRelativePath'];
  final sessionCount = marker['sessionCount'];
  final migratedAtText = marker['migratedAtUtc'];
  final migratedAt = migratedAtText is String
      ? DateTime.tryParse(migratedAtText)
      : null;
  if (marker['schemaVersion'] != 1 ||
      marker['migrationVersion'] != stableV017GatheringMigrationVersion ||
      sourceSha256 is! String ||
      !RegExp(r'^[0-9a-f]{64}$').hasMatch(sourceSha256) ||
      archiveRelativePath !=
          'migration-archive/v0.1.7/gathering-state.$sourceSha256.json' ||
      sessionCount is! int ||
      sessionCount < 0 ||
      sessionCount > 10000 ||
      migratedAt == null ||
      !migratedAt.isUtc) {
    throw const FormatException(
      'The stable v0.1.7 Gathering migration marker is damaged.',
    );
  }
  return marker;
}

String readStableV017GatheringLoadoutNotes(Object? value) {
  if (value is! String || value.length > 4000) {
    throw const FormatException(
      'The stable v0.1.7 Gathering loadout notes are damaged.',
    );
  }
  return value;
}

Map<String, dynamic> _convertedDocument(
  _StableV017GatheringData data, {
  required String sourceSha256,
  required String archiveRelativePath,
  required DateTime migratedAt,
}) {
  final preparation = GatheringPreparation(
    baseSettings: BairogCalculatorSettings(
      mastery: data.profileMastery,
      gatheringDropRatePercent: 0,
      minigameMode: BairogMinigameMode.none,
      hedgehogTier: BairogHedgehogTier.none,
      agrisEnabled: false,
      enabledExpenseItemIds: const {},
      displayMode: BairogDisplayMode.silverPerHour,
      yourEnergy: 0,
      naturalEnergyRecoveryPerThreeMinutes: 0,
      includeAfuaru: false,
      includeChest: false,
      includeChestX10: false,
      includeFeverTime: false,
      includeEvergreenShard: false,
      showTaxed: false,
      marketNetRate: 1,
      dropTaxed: const {},
      hiddenDropItemTypeIds: const {},
      customGathersPerHour: const {},
      customItemPrices: const {},
    ),
    statsConfirmed: true,
  );
  return <String, dynamic>{
    'schemaVersion': 1,
    'sessions': data.sessions.map(_convertedSession).toList(growable: false),
    'preferences': <String, dynamic>{
      gatheringPreparationPreferenceKey: preparation.toJson(),
      stableV017GatheringLoadoutNotesPreferenceKey: data.loadoutNotes,
      stableV017GatheringMigrationPreferenceKey: <String, dynamic>{
        'schemaVersion': 1,
        'migrationVersion': stableV017GatheringMigrationVersion,
        'sourceSha256': sourceSha256,
        'archiveRelativePath': archiveRelativePath,
        'sessionCount': data.sessions.length,
        'migratedAtUtc': migratedAt.toIso8601String(),
      },
    },
  };
}

Map<String, dynamic> _convertedSession(_StableV017GatheringSession session) =>
    <String, dynamic>{
      'id': session.id,
      'createdAt': session.recordedAtUtc.toIso8601String(),
      'methodId': _methodId(session.method),
      'methodLabel': session.method,
      'methodIcon': '',
      'spotId': 'custom',
      'spotName': session.location.isEmpty
          ? 'Unspecified location'
          : session.location,
      'durationSeconds': session.durationMinutes * 60,
      'mastery': session.mastery,
      'notes': session.notes,
      // Preserve the exact legacy value, including an intentionally blank
      // location, and durably identify this no-loot record as history-only.
      'stableV017Location': session.location,
      'loot': <Object?>[],
      'buffs': <Object?>[],
      'pets': <Object?>[],
      'buffTotals': <String, double>{},
      'catalogDate': '',
    };

String _methodId(String method) =>
    _knownMethodIds[method] ??
    'legacy-v017-${sha256.convert(utf8.encode(method)).toString().substring(0, 16)}';

void _validateConvertedDocument(List<int> bytes) {
  final decoded = jsonDecode(utf8.decode(bytes));
  if (decoded is! Map) {
    throw const FormatException('Converted Gathering data is not an object.');
  }
  final document = Map<String, dynamic>.from(decoded);
  if (document['schemaVersion'] != 1 || document['sessions'] is! List) {
    throw const FormatException(
      'Converted Gathering data has an unsupported format.',
    );
  }
  final sessions = document['sessions'] as List;
  if (sessions.any((session) => session is! Map)) {
    throw const FormatException('Converted Gathering history is damaged.');
  }
  final parsed = sessions
      .map(
        (session) => GatheringSession.fromJson(
          Map<String, dynamic>.from(session as Map),
        ),
      )
      .toList(growable: false);
  if (parsed.map((session) => session.id).toSet().length != parsed.length) {
    throw const FormatException(
      'Converted Gathering history contains duplicate records.',
    );
  }
  if (document['preferences'] is! Map) {
    throw const FormatException('Converted Gathering preferences are damaged.');
  }
  final preferences = Map<String, dynamic>.from(document['preferences'] as Map);
  GatheringPreparation.fromPreferences(preferences);
  readStableV017GatheringMigrationMarker(
    preferences[stableV017GatheringMigrationPreferenceKey],
  );
  readStableV017GatheringLoadoutNotes(
    preferences[stableV017GatheringLoadoutNotesPreferenceKey],
  );
}

Future<void> _ensureExactArchive(File archive, List<int> sourceBytes) async {
  if (!await _writeNewFileAtomically(archive, sourceBytes)) {
    final archivedBytes = await archive.readAsBytes();
    if (!_sameBytes(archivedBytes, sourceBytes)) {
      throw const FileSystemException(
        'The stable v0.1.7 Gathering archive does not match its source.',
      );
    }
  }
}

Future<bool> _writeNewFileAtomically(File target, List<int> bytes) async {
  await target.parent.create(recursive: true);
  if (await target.exists()) return false;
  final temporary = File('${target.path}.stable-v017.tmp');
  try {
    await temporary.writeAsBytes(bytes, flush: true);
    if (await target.exists()) return false;
    await temporary.rename(target.path);
    return true;
  } on FileSystemException {
    if (await target.exists()) return false;
    rethrow;
  } finally {
    if (await temporary.exists()) await temporary.delete();
  }
}

bool _sameBytes(List<int> left, List<int> right) {
  if (left.length != right.length) return false;
  for (var index = 0; index < left.length; index++) {
    if (left[index] != right[index]) return false;
  }
  return true;
}

class _StableV017GatheringData {
  const _StableV017GatheringData({
    required this.profileMastery,
    required this.loadoutNotes,
    required this.sessions,
  });

  factory _StableV017GatheringData.fromBytes(List<int> bytes) {
    final decoded = jsonDecode(utf8.decode(bytes));
    if (decoded is! Map) {
      throw const FormatException('Unrecognized Gathering personal data.');
    }
    final document = Map<String, dynamic>.from(decoded);
    if (document['version'] != 1 || document['profile'] is! Map) {
      throw const FormatException('Unrecognized Gathering personal data.');
    }
    final profile = Map<String, dynamic>.from(document['profile'] as Map);
    final profileMastery = _boundedInteger(
      profile['mastery'],
      'Gathering mastery',
      minimum: 0,
      maximum: 3000,
    );
    final loadoutNotes = _boundedText(
      profile['loadoutNotes'],
      'Gathering loadout notes',
      maximumLength: 4000,
      allowEmpty: true,
    );
    final sessionsValue = document['sessions'];
    if (sessionsValue is! List || sessionsValue.length > 10000) {
      throw const FormatException('Gathering sessions must be a valid list.');
    }
    final sessions = sessionsValue
        .map(_StableV017GatheringSession.fromJson)
        .toList(growable: false);
    if (sessions.map((session) => session.id).toSet().length !=
        sessions.length) {
      throw const FormatException('Gathering session ids must be unique.');
    }
    return _StableV017GatheringData(
      profileMastery: profileMastery,
      loadoutNotes: loadoutNotes,
      sessions: sessions,
    );
  }

  final int profileMastery;
  final String loadoutNotes;
  final List<_StableV017GatheringSession> sessions;
}

class _StableV017GatheringSession {
  const _StableV017GatheringSession({
    required this.id,
    required this.recordedAtUtc,
    required this.method,
    required this.location,
    required this.durationMinutes,
    required this.mastery,
    required this.notes,
  });

  factory _StableV017GatheringSession.fromJson(Object? value) {
    if (value is! Map) {
      throw const FormatException('Gathering session must be an object.');
    }
    final session = Map<String, dynamic>.from(value);
    final id = _boundedText(session['id'], 'Session id', maximumLength: 160);
    final recordedAtText = _boundedText(
      session['recordedAtUtc'],
      'Session timestamp',
      maximumLength: 64,
    );
    final recordedAtUtc = DateTime.tryParse(recordedAtText);
    if (recordedAtUtc == null || !recordedAtUtc.isUtc) {
      throw const FormatException('Session timestamp must be UTC.');
    }
    return _StableV017GatheringSession(
      id: id,
      recordedAtUtc: recordedAtUtc,
      method: _boundedText(
        session['method'],
        'Gathering method',
        maximumLength: 80,
      ),
      location: _boundedText(
        session['location'],
        'Gathering location',
        maximumLength: 160,
        allowEmpty: true,
      ),
      durationMinutes: _boundedInteger(
        session['durationMinutes'],
        'Session duration',
        minimum: 1,
        maximum: 10080,
      ),
      mastery: _boundedInteger(
        session['mastery'],
        'Session mastery',
        minimum: 0,
        maximum: 3000,
      ),
      notes: _boundedText(
        session['notes'],
        'Session notes',
        maximumLength: 12000,
        allowEmpty: true,
      ),
    );
  }

  final String id;
  final DateTime recordedAtUtc;
  final String method;
  final String location;
  final int durationMinutes;
  final int mastery;
  final String notes;
}

int _boundedInteger(
  Object? value,
  String label, {
  required int minimum,
  required int maximum,
}) {
  if (value is! int || value < minimum || value > maximum) {
    throw FormatException('$label is invalid.');
  }
  return value;
}

String _boundedText(
  Object? value,
  String label, {
  required int maximumLength,
  bool allowEmpty = false,
}) {
  if (value is! String ||
      (!allowEmpty && value.trim().isEmpty) ||
      value.length > maximumLength) {
    throw FormatException('$label is invalid.');
  }
  return value;
}

String _join(String parent, String child) =>
    parent.endsWith(Platform.pathSeparator)
    ? '$parent$child'
    : '$parent${Platform.pathSeparator}$child';
