enum FishingMethod {
  fishing('fishing', 'Fishing'),
  harpooning('harpooning', 'Harpooning');

  const FishingMethod(this.storageValue, this.label);

  final String storageValue;
  final String label;

  static FishingMethod fromStorage(Object? value) {
    for (final method in values) {
      if (method.storageValue == value) return method;
    }
    throw const FormatException('Fishing method is invalid.');
  }
}

class FishingLoadout {
  const FishingLoadout({
    required this.id,
    required this.name,
    required this.method,
    required this.mastery,
    required this.tool,
    required this.notes,
    required this.createdAtUtc,
    required this.updatedAtUtc,
  });

  factory FishingLoadout.fromJson(Object? value) {
    final object = _object(value, 'Fishing loadout');
    final createdAtUtc = _utcTimestamp(
      object['createdAtUtc'],
      'Loadout creation timestamp',
    );
    final updatedAtUtc = _utcTimestamp(
      object['updatedAtUtc'],
      'Loadout update timestamp',
    );
    if (updatedAtUtc.isBefore(createdAtUtc)) {
      throw const FormatException(
        'Loadout update timestamp cannot precede its creation timestamp.',
      );
    }
    return FishingLoadout(
      id: _boundedText(object['id'], 'Loadout id', maximumLength: 160),
      name: _boundedText(object['name'], 'Loadout name', maximumLength: 120),
      method: FishingMethod.fromStorage(object['method']),
      mastery: _boundedInteger(
        object['mastery'],
        'Fishing mastery',
        minimum: 0,
        maximum: 3000,
      ),
      tool: _boundedText(
        object['tool'],
        'Fishing tool',
        maximumLength: 200,
        allowEmpty: true,
      ),
      notes: _boundedText(
        object['notes'],
        'Loadout notes',
        maximumLength: 4000,
        allowEmpty: true,
      ),
      createdAtUtc: createdAtUtc,
      updatedAtUtc: updatedAtUtc,
    );
  }

  final String id;
  final String name;
  final FishingMethod method;
  final int mastery;
  final String tool;
  final String notes;
  final DateTime createdAtUtc;
  final DateTime updatedAtUtc;

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'name': name,
    'method': method.storageValue,
    'mastery': mastery,
    'tool': tool,
    'notes': notes,
    'createdAtUtc': createdAtUtc.toUtc().toIso8601String(),
    'updatedAtUtc': updatedAtUtc.toUtc().toIso8601String(),
  };
}

class FishingSession {
  const FishingSession({
    required this.id,
    required this.startedAtUtc,
    required this.durationMinutes,
    required this.location,
    required this.method,
    required this.loadoutId,
    required this.loadoutName,
    required this.mastery,
    required this.tool,
    required this.retainedFishCount,
    required this.silverReceived,
    required this.notes,
    required this.createdAtUtc,
    required this.updatedAtUtc,
  });

  factory FishingSession.fromJson(Object? value) {
    final object = _object(value, 'Fishing session');
    final createdAtUtc = _utcTimestamp(
      object['createdAtUtc'],
      'Session creation timestamp',
    );
    final updatedAtUtc = _utcTimestamp(
      object['updatedAtUtc'],
      'Session update timestamp',
    );
    if (updatedAtUtc.isBefore(createdAtUtc)) {
      throw const FormatException(
        'Session update timestamp cannot precede its creation timestamp.',
      );
    }
    final rawLoadoutId = object['loadoutId'];
    if (rawLoadoutId != null && rawLoadoutId is! String) {
      throw const FormatException('Session loadout id is invalid.');
    }
    final loadoutId = rawLoadoutId == null
        ? null
        : _boundedText(rawLoadoutId, 'Session loadout id', maximumLength: 160);
    return FishingSession(
      id: _boundedText(object['id'], 'Session id', maximumLength: 160),
      startedAtUtc: _utcTimestamp(
        object['startedAtUtc'],
        'Session start timestamp',
      ),
      durationMinutes: _boundedInteger(
        object['durationMinutes'],
        'Session duration',
        minimum: 1,
        maximum: 10080,
      ),
      location: _boundedText(
        object['location'],
        'Session location',
        maximumLength: 160,
        allowEmpty: true,
      ),
      method: FishingMethod.fromStorage(object['method']),
      loadoutId: loadoutId,
      loadoutName: _boundedText(
        object['loadoutName'],
        'Session loadout name',
        maximumLength: 120,
        allowEmpty: true,
      ),
      mastery: _boundedInteger(
        object['mastery'],
        'Session mastery',
        minimum: 0,
        maximum: 3000,
      ),
      tool: _boundedText(
        object['tool'],
        'Session tool',
        maximumLength: 200,
        allowEmpty: true,
      ),
      retainedFishCount: _boundedInteger(
        object['retainedFishCount'],
        'Retained fish count',
        minimum: 0,
        maximum: 1000000000,
      ),
      silverReceived: _boundedInteger(
        object['silverReceived'],
        'Silver received',
        minimum: 0,
        maximum: 9007199254740991,
      ),
      notes: _boundedText(
        object['notes'],
        'Session notes',
        maximumLength: 12000,
        allowEmpty: true,
      ),
      createdAtUtc: createdAtUtc,
      updatedAtUtc: updatedAtUtc,
    );
  }

  final String id;
  final DateTime startedAtUtc;
  final int durationMinutes;
  final String location;
  final FishingMethod method;

  /// Optional link to a current loadout. The snapshot fields below remain
  /// intact if that loadout is later edited or deleted.
  final String? loadoutId;
  final String loadoutName;
  final int mastery;
  final String tool;
  final int retainedFishCount;
  final int silverReceived;
  final String notes;
  final DateTime createdAtUtc;
  final DateTime updatedAtUtc;

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'startedAtUtc': startedAtUtc.toUtc().toIso8601String(),
    'durationMinutes': durationMinutes,
    'location': location,
    'method': method.storageValue,
    'loadoutId': loadoutId,
    'loadoutName': loadoutName,
    'mastery': mastery,
    'tool': tool,
    'retainedFishCount': retainedFishCount,
    'silverReceived': silverReceived,
    'notes': notes,
    'createdAtUtc': createdAtUtc.toUtc().toIso8601String(),
    'updatedAtUtc': updatedAtUtc.toUtc().toIso8601String(),
  };
}

class FishingJournal {
  FishingJournal({
    Iterable<FishingLoadout> loadouts = const <FishingLoadout>[],
    Iterable<FishingSession> sessions = const <FishingSession>[],
  }) : loadouts = List<FishingLoadout>.unmodifiable(loadouts),
       sessions = List<FishingSession>.unmodifiable(sessions);

  factory FishingJournal.fromJson(Object? value) {
    final object = _object(value, 'Fishing journal');
    if (object['version'] != schemaVersion) {
      throw const FormatException('Unrecognized Fishing journal version.');
    }
    final rawLoadouts = object['loadouts'];
    final rawSessions = object['sessions'];
    if (rawLoadouts is! List || rawLoadouts.length > 1000) {
      throw const FormatException('Fishing loadouts must be a valid list.');
    }
    if (rawSessions is! List || rawSessions.length > 10000) {
      throw const FormatException('Fishing sessions must be a valid list.');
    }
    final loadouts = rawLoadouts
        .map(FishingLoadout.fromJson)
        .toList(growable: false);
    final sessions = rawSessions
        .map(FishingSession.fromJson)
        .toList(growable: false);
    _requireUniqueIds(loadouts.map((entry) => entry.id), 'loadout');
    _requireUniqueIds(sessions.map((entry) => entry.id), 'session');
    return FishingJournal(loadouts: loadouts, sessions: sessions);
  }

  static const int schemaVersion = 1;

  final List<FishingLoadout> loadouts;
  final List<FishingSession> sessions;

  FishingJournal copyWith({
    Iterable<FishingLoadout>? loadouts,
    Iterable<FishingSession>? sessions,
  }) => FishingJournal(
    loadouts: loadouts ?? this.loadouts,
    sessions: sessions ?? this.sessions,
  );

  Map<String, Object?> toJson() => <String, Object?>{
    'version': schemaVersion,
    'loadouts': loadouts.map((entry) => entry.toJson()).toList(growable: false),
    'sessions': sessions.map((entry) => entry.toJson()).toList(growable: false),
  };
}

Map<String, dynamic> _object(Object? value, String label) {
  if (value is! Map<String, dynamic>) {
    throw FormatException('$label must be an object.');
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

DateTime _utcTimestamp(Object? value, String label) {
  if (value is! String) throw FormatException('$label is invalid.');
  final parsed = DateTime.tryParse(value);
  if (parsed == null || !parsed.isUtc) {
    throw FormatException('$label must be a UTC timestamp.');
  }
  return parsed;
}

void _requireUniqueIds(Iterable<String> ids, String label) {
  final values = ids.toList(growable: false);
  if (values.toSet().length != values.length) {
    throw FormatException('Fishing $label ids must be unique.');
  }
}
