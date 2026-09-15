import 'dart:convert';
import 'dart:io';

import '../../data/persistence/atomic_file_store.dart';

const int gatheringPersonalDataVersion = 1;

class GatheringProfile {
  const GatheringProfile({this.mastery = 0, this.loadoutNotes = ''});

  factory GatheringProfile.fromJson(Object? value) {
    if (value is! Map<String, dynamic>) {
      throw const FormatException('Gathering profile must be an object.');
    }
    final mastery = value['mastery'];
    final loadoutNotes = value['loadoutNotes'];
    if (mastery is! int || mastery < 0 || mastery > 3000) {
      throw const FormatException(
        'Gathering mastery must be a whole number from 0 to 3000.',
      );
    }
    if (loadoutNotes is! String || loadoutNotes.length > 4000) {
      throw const FormatException(
        'Gathering loadout notes must be at most 4000 characters.',
      );
    }
    return GatheringProfile(mastery: mastery, loadoutNotes: loadoutNotes);
  }

  final int mastery;
  final String loadoutNotes;

  Map<String, Object?> toJson() => {
    'mastery': mastery,
    'loadoutNotes': loadoutNotes,
  };
}

class GatheringSession {
  const GatheringSession({
    required this.id,
    required this.recordedAtUtc,
    required this.method,
    required this.location,
    required this.durationMinutes,
    required this.mastery,
    required this.notes,
  });

  factory GatheringSession.fromJson(Object? value) {
    if (value is! Map<String, dynamic>) {
      throw const FormatException('Gathering session must be an object.');
    }
    final id = _boundedText(value['id'], 'Session id', maximumLength: 160);
    final recordedAtText = _boundedText(
      value['recordedAtUtc'],
      'Session timestamp',
      maximumLength: 64,
    );
    final recordedAt = DateTime.tryParse(recordedAtText);
    if (recordedAt == null || !recordedAt.isUtc) {
      throw const FormatException('Session timestamp must be UTC.');
    }
    final method = _boundedText(
      value['method'],
      'Gathering method',
      maximumLength: 80,
    );
    final location = _boundedText(
      value['location'],
      'Gathering location',
      maximumLength: 160,
      allowEmpty: true,
    );
    final durationMinutes = value['durationMinutes'];
    if (durationMinutes is! int ||
        durationMinutes < 1 ||
        durationMinutes > 10080) {
      throw const FormatException(
        'Session duration must be from 1 to 10080 minutes.',
      );
    }
    final mastery = value['mastery'];
    if (mastery is! int || mastery < 0 || mastery > 3000) {
      throw const FormatException(
        'Session mastery must be a whole number from 0 to 3000.',
      );
    }
    final notes = _boundedText(
      value['notes'],
      'Session notes',
      maximumLength: 12000,
      allowEmpty: true,
    );
    return GatheringSession(
      id: id,
      recordedAtUtc: recordedAt,
      method: method,
      location: location,
      durationMinutes: durationMinutes,
      mastery: mastery,
      notes: notes,
    );
  }

  final String id;
  final DateTime recordedAtUtc;
  final String method;
  final String location;
  final int durationMinutes;
  final int mastery;
  final String notes;

  Map<String, Object?> toJson() => {
    'id': id,
    'recordedAtUtc': recordedAtUtc.toUtc().toIso8601String(),
    'method': method,
    'location': location,
    'durationMinutes': durationMinutes,
    'mastery': mastery,
    'notes': notes,
  };
}

class GatheringPersonalData {
  const GatheringPersonalData({
    this.profile = const GatheringProfile(),
    this.sessions = const <GatheringSession>[],
  });

  factory GatheringPersonalData.fromJson(Object? value) {
    if (value is! Map<String, dynamic> ||
        value['version'] != gatheringPersonalDataVersion) {
      throw const FormatException('Unrecognized Gathering personal data.');
    }
    final sessionsValue = value['sessions'];
    if (sessionsValue is! List || sessionsValue.length > 10000) {
      throw const FormatException('Gathering sessions must be a valid list.');
    }
    final sessions = sessionsValue
        .map(GatheringSession.fromJson)
        .toList(growable: false);
    if (sessions.map((session) => session.id).toSet().length !=
        sessions.length) {
      throw const FormatException('Gathering session ids must be unique.');
    }
    return GatheringPersonalData(
      profile: GatheringProfile.fromJson(value['profile']),
      sessions: List<GatheringSession>.unmodifiable(sessions),
    );
  }

  final GatheringProfile profile;
  final List<GatheringSession> sessions;

  GatheringPersonalData copyWith({
    GatheringProfile? profile,
    List<GatheringSession>? sessions,
  }) => GatheringPersonalData(
    profile: profile ?? this.profile,
    sessions: List<GatheringSession>.unmodifiable(sessions ?? this.sessions),
  );

  Map<String, Object?> toJson() => {
    'version': gatheringPersonalDataVersion,
    'profile': profile.toJson(),
    'sessions': sessions.map((session) => session.toJson()).toList(),
  };
}

class GatheringPersonalStore {
  GatheringPersonalStore(Directory personalDataRoot)
    : directory = Directory(_join(personalDataRoot.path, directoryName)),
      _store = AtomicFileStore(
        directory: Directory(_join(personalDataRoot.path, directoryName)),
        fileName: fileName,
      );

  static const String directoryName = 'gathering';
  static const String fileName = 'gathering-state.json';

  final Directory directory;
  final AtomicFileStore _store;

  String get path => _store.targetPath;

  /// Returns a genuinely empty profile when this selected personal-data root
  /// has no Gathering file. No Beta, legacy app, or environment folder is
  /// searched or imported here.
  Future<GatheringPersonalData> load() async {
    final file = File(path);
    if (!await file.exists()) return const GatheringPersonalData();
    return GatheringPersonalData.fromJson(
      jsonDecode(await file.readAsString()),
    );
  }

  Future<void> save(GatheringPersonalData value) async {
    await _store.writeJson(
      value.toJson(),
      validate: (bytes) {
        GatheringPersonalData.fromJson(jsonDecode(utf8.decode(bytes)));
      },
    );
  }
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

String _join(String parent, String child) {
  final separator = Platform.pathSeparator;
  return parent.endsWith(separator)
      ? '$parent$child'
      : '$parent$separator$child';
}
