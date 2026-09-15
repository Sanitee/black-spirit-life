/// Immutable, validated original inputs from an explicitly prepared import.
/// This does not contain browser data or assert a final Garmoth Save.
class SessionImportMetadata {
  SessionImportMetadata._({
    required this.importId,
    required this.revision,
    required this.importedAtUtc,
    required this.spotId,
    required this.spotName,
    required this.activity,
    required this.methodIds,
    required this.linkedSourceIds,
    required this.durationSeconds,
    required this.items,
    required this.matchedCount,
    required this.notesCount,
    required this.skippedCount,
    this.agrisActive,
    this.agrisUsed,
    this.additionalDropRate,
    this.additionalDropAmount,
  });

  final String importId, spotId, spotName, activity;
  final int revision, durationSeconds, matchedCount, notesCount, skippedCount;
  final DateTime importedAtUtc;
  final List<String> methodIds, linkedSourceIds;
  final List<SessionImportItem> items;
  final bool? agrisActive;
  final int? agrisUsed;
  final double? additionalDropRate, additionalDropAmount;
  String get sessionId => 'session-import:$importId';

  factory SessionImportMetadata.fromJson(Map<String, dynamic> json) {
    _keys(json, const {
      'schemaVersion',
      'provider',
      'status',
      'importId',
      'revision',
      'importedAtUtc',
      'target',
      'session',
      'preparation',
    });
    if (json['schemaVersion'] != 1 ||
        json['provider'] != 'garmoth' ||
        json['status'] != 'prepared') {
      _invalid();
    }
    final id = _text(json['importId'], 36);
    if (!RegExp(
          r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
        ).hasMatch(id) ||
        id == '00000000-0000-0000-0000-000000000000') {
      _invalid();
    }
    final dateText = _text(json['importedAtUtc'], 40);
    final date = DateTime.tryParse(dateText);
    if (date == null || !date.isUtc) _invalid();
    final target = _map(json['target']);
    _keys(target, const {
      'spotId',
      'spotName',
      'activity',
      'methodIds',
      'linkedSourceIds',
    });
    final activity = _text(target['activity'], 16);
    if (!const {'gathering', 'hunting', 'grinding'}.contains(activity)) {
      _invalid();
    }
    final session = _map(json['session']);
    _keys(session, const {
      'durationSeconds',
      'items',
      'agrisActive',
      'agrisUsed',
      'additionalDropRate',
      'additionalDropAmount',
    });
    final rawItems = session['items'];
    if (rawItems is! List || rawItems.isEmpty || rawItems.length > 160) {
      _invalid();
    }
    final items = rawItems
        .map((value) => SessionImportItem.fromJson(_map(value)))
        .toList();
    if (items.map((item) => item.identity).toSet().length != items.length) {
      _invalid();
    }
    final prep = _map(json['preparation']);
    _keys(prep, const {
      'matchedCount',
      'notesCount',
      'skippedCount',
      'submitted',
    });
    final matched = _integer(prep['matchedCount'], 1, 160);
    final skipped = _integer(prep['skippedCount'], 0, 160);
    final notes = _integer(prep['notesCount'], 0, skipped);
    if (matched + skipped != items.length || prep['submitted'] != false) {
      _invalid();
    }
    final active = session['agrisActive'];
    if (active != null && active is! bool) _invalid();
    return SessionImportMetadata._(
      importId: id,
      revision: _integer(json['revision'], 1, 2147483647),
      importedAtUtc: date,
      spotId: _text(target['spotId'], 160),
      spotName: _text(target['spotName'], 240),
      activity: activity,
      methodIds: _strings(target['methodIds'], 16),
      linkedSourceIds: _strings(target['linkedSourceIds'], 32),
      durationSeconds: _integer(session['durationSeconds'], 1, 604800),
      items: List.unmodifiable(items),
      matchedCount: matched,
      notesCount: notes,
      skippedCount: skipped,
      agrisActive: active as bool?,
      agrisUsed: session['agrisUsed'] == null
          ? null
          : _integer(session['agrisUsed'], 0, 10000000000),
      additionalDropRate: _rate(session['additionalDropRate']),
      additionalDropAmount: _rate(session['additionalDropAmount']),
    );
  }

  Map<String, dynamic> toJson() => {
    'schemaVersion': 1,
    'provider': 'garmoth',
    'status': 'prepared',
    'importId': importId,
    'revision': revision,
    'importedAtUtc': importedAtUtc.toUtc().toIso8601String(),
    'target': {
      'spotId': spotId,
      'spotName': spotName,
      'activity': activity,
      'methodIds': methodIds,
      'linkedSourceIds': linkedSourceIds,
    },
    'session': {
      'durationSeconds': durationSeconds,
      'items': items.map((item) => item.toJson()).toList(),
      if (agrisActive != null) 'agrisActive': agrisActive,
      if (agrisUsed != null) 'agrisUsed': agrisUsed,
      if (additionalDropRate != null) 'additionalDropRate': additionalDropRate,
      if (additionalDropAmount != null)
        'additionalDropAmount': additionalDropAmount,
    },
    'preparation': {
      'matchedCount': matchedCount,
      'notesCount': notesCount,
      'skippedCount': skippedCount,
      'submitted': false,
    },
  };
}

class SessionImportItem {
  SessionImportItem._(this.itemId, this.subKey, this.name, this.quantity);
  final String? itemId;
  final int subKey, quantity;
  final String name;
  String get identity =>
      '${itemId == null ? 'name:${name.toLowerCase()}' : 'id:$itemId'}:$subKey';

  factory SessionImportItem.fromJson(Map<String, dynamic> json) {
    _keys(json, const {'itemId', 'subKey', 'name', 'quantity'});
    return SessionImportItem._(
      json['itemId'] == null ? null : _text(json['itemId'], 80),
      _integer(json['subKey'], 0, 1000000),
      _text(json['name'], 160),
      _integer(json['quantity'], 1, 9007199254740991),
    );
  }

  Map<String, dynamic> toJson() => {
    'itemId': itemId,
    'subKey': subKey,
    'name': name,
    'quantity': quantity,
  };
}

Never _invalid() =>
    throw const FormatException('The local session receipt is invalid.');
Map<String, dynamic> _map(Object? value) {
  if (value is! Map || value.keys.any((key) => key is! String)) _invalid();
  return Map<String, dynamic>.from(value);
}

void _keys(Map<String, dynamic> value, Set<String> allowed) {
  if (value.keys.any((key) => !allowed.contains(key))) _invalid();
}

String _text(Object? value, int limit) {
  if (value is! String ||
      value.isEmpty ||
      value.length > limit ||
      value.trim() != value ||
      RegExp(r'[\x00-\x1f\x7f]').hasMatch(value)) {
    _invalid();
  }
  return value;
}

int _integer(Object? value, int minimum, int maximum) {
  if (value is! num ||
      !value.isFinite ||
      value < minimum ||
      value > maximum ||
      value != value.truncateToDouble()) {
    _invalid();
  }
  return value.toInt();
}

List<String> _strings(Object? value, int maximum) {
  if (value is! List || value.length > maximum) _invalid();
  return List.unmodifiable(value.map((item) => _text(item, 160)));
}

double? _rate(Object? value) {
  if (value == null) return null;
  if (value is! num ||
      !value.isFinite ||
      value < 0 ||
      value > 10000 ||
      (value * 100 - (value * 100).round()).abs() > 0.0000001) {
    _invalid();
  }
  return value.toDouble();
}
