/// The acquisition route that led to a gather-checklist entry.
///
/// This is optional metadata rather than checklist identity. A resource may be
/// added without choosing a route, and its route can be refined later without
/// moving or duplicating the entry.
enum BdoGatherChecklistSourceKind { manualGathering, workerNode, fishing }

/// One immutable, ordered item in the gather checklist.
class BdoGatherChecklistEntry {
  factory BdoGatherChecklistEntry({
    required String resourceId,
    String? displayName,
    BdoGatherChecklistSourceKind? sourceKind,
    bool isCompleted = false,
  }) {
    final normalizedId = _normalizedId(resourceId);
    if (normalizedId == null) {
      throw ArgumentError.value(
        resourceId,
        'resourceId',
        'A checklist resource ID cannot be empty.',
      );
    }
    return BdoGatherChecklistEntry._(
      resourceId: normalizedId,
      displayName: _normalizedOptionalText(displayName),
      sourceKind: sourceKind,
      isCompleted: isCompleted,
    );
  }

  const BdoGatherChecklistEntry._({
    required this.resourceId,
    required this.displayName,
    required this.sourceKind,
    required this.isCompleted,
  });

  /// The stable material/resource key. This is the entry's identity.
  final String resourceId;

  /// A display snapshot for useful offline rendering.
  ///
  /// The resource catalog remains authoritative; this value may be omitted.
  final String? displayName;

  /// The route the user chose when adding this entry, when known.
  final BdoGatherChecklistSourceKind? sourceKind;

  final bool isCompleted;

  BdoGatherChecklistEntry copyWith({
    String? displayName,
    bool clearDisplayName = false,
    BdoGatherChecklistSourceKind? sourceKind,
    bool clearSourceKind = false,
    bool? isCompleted,
  }) {
    return BdoGatherChecklistEntry._(
      resourceId: resourceId,
      displayName: clearDisplayName
          ? null
          : _normalizedOptionalText(displayName) ?? this.displayName,
      sourceKind: clearSourceKind ? null : sourceKind ?? this.sourceKind,
      isCompleted: isCompleted ?? this.isCompleted,
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'resourceId': resourceId,
    'displayName': ?displayName,
    if (sourceKind case final kind?) 'sourceKind': _sourceKindName(kind),
    if (isCompleted) 'completed': true,
  };

  @override
  bool operator ==(Object other) =>
      other is BdoGatherChecklistEntry &&
      resourceId == other.resourceId &&
      displayName == other.displayName &&
      sourceKind == other.sourceKind &&
      isCompleted == other.isCompleted;

  @override
  int get hashCode =>
      Object.hash(resourceId, displayName, sourceKind, isCompleted);

  @override
  String toString() =>
      'BdoGatherChecklistEntry('
      '$resourceId, displayName: $displayName, '
      'sourceKind: $sourceKind, completed: $isCompleted)';
}

/// Immutable state and operations for the user's ordered gather checklist.
class BdoGatherChecklist {
  factory BdoGatherChecklist({
    Iterable<BdoGatherChecklistEntry> entries =
        const <BdoGatherChecklistEntry>[],
    String? selectedResourceId,
  }) {
    final normalizedEntries = _mergeEntries(entries);
    final normalizedSelection = _normalizedId(selectedResourceId);
    return BdoGatherChecklist._(
      entries: List<BdoGatherChecklistEntry>.unmodifiable(normalizedEntries),
      selectedResourceId:
          normalizedSelection != null &&
              normalizedEntries.any(
                (entry) => entry.resourceId == normalizedSelection,
              )
          ? normalizedSelection
          : null,
    );
  }

  const BdoGatherChecklist._({
    required this.entries,
    required this.selectedResourceId,
  });

  static const int schemaVersion = 1;

  final List<BdoGatherChecklistEntry> entries;

  /// The entry the user most recently chose to inspect on the map.
  ///
  /// Selection is independent of completion so a completed location may still
  /// be revisited. It is always null or the ID of an existing entry.
  final String? selectedResourceId;

  bool get isEmpty => entries.isEmpty;
  bool get isNotEmpty => entries.isNotEmpty;
  int get completedCount => entries.where((entry) => entry.isCompleted).length;
  int get remainingCount => entries.length - completedCount;

  BdoGatherChecklistEntry? get selectedEntry =>
      _entryWithId(selectedResourceId);

  /// Explicit selection when present, otherwise the first unfinished entry.
  BdoGatherChecklistEntry? get currentEntry =>
      selectedEntry ?? firstIncompleteEntry;

  BdoGatherChecklistEntry? get firstIncompleteEntry {
    for (final entry in entries) {
      if (!entry.isCompleted) {
        return entry;
      }
    }
    return null;
  }

  bool contains(String resourceId) => _indexOf(resourceId) != -1;

  /// Adds [entry] once, preserving the original position and completion state.
  ///
  /// A repeated add may enrich the existing display/source metadata, but never
  /// creates a duplicate or silently marks a completed item unfinished.
  BdoGatherChecklist add(BdoGatherChecklistEntry entry, {bool select = false}) {
    final existingIndex = _indexOf(entry.resourceId);
    if (existingIndex == -1) {
      final nextEntries = <BdoGatherChecklistEntry>[...entries, entry];
      return BdoGatherChecklist(
        entries: nextEntries,
        selectedResourceId: select ? entry.resourceId : selectedResourceId,
      );
    }

    final existing = entries[existingIndex];
    final merged = _mergeEntry(existing, entry);
    final nextSelection = select ? existing.resourceId : selectedResourceId;
    if (merged == existing && nextSelection == selectedResourceId) {
      return this;
    }

    final nextEntries = entries.toList();
    nextEntries[existingIndex] = merged;
    return BdoGatherChecklist(
      entries: nextEntries,
      selectedResourceId: nextSelection,
    );
  }

  BdoGatherChecklist addResource({
    required String resourceId,
    String? displayName,
    BdoGatherChecklistSourceKind? sourceKind,
    bool select = false,
  }) {
    return add(
      BdoGatherChecklistEntry(
        resourceId: resourceId,
        displayName: displayName,
        sourceKind: sourceKind,
      ),
      select: select,
    );
  }

  BdoGatherChecklist remove(String resourceId) {
    final index = _indexOf(resourceId);
    if (index == -1) {
      return this;
    }
    final removedId = entries[index].resourceId;
    final nextEntries = entries.toList()..removeAt(index);
    return BdoGatherChecklist(
      entries: nextEntries,
      selectedResourceId: selectedResourceId == removedId
          ? null
          : selectedResourceId,
    );
  }

  /// Moves the entry at [fromIndex] to the requested final [toIndex].
  ///
  /// An invalid source index is ignored. The destination is clamped to the
  /// remaining valid range, allowing drag gestures to safely overshoot.
  BdoGatherChecklist reorder(int fromIndex, int toIndex) {
    if (fromIndex < 0 || fromIndex >= entries.length || entries.length < 2) {
      return this;
    }
    final safeDestination = toIndex.clamp(0, entries.length - 1);
    if (safeDestination == fromIndex) {
      return this;
    }
    final nextEntries = entries.toList();
    final moved = nextEntries.removeAt(fromIndex);
    nextEntries.insert(safeDestination, moved);
    return BdoGatherChecklist(
      entries: nextEntries,
      selectedResourceId: selectedResourceId,
    );
  }

  BdoGatherChecklist moveResource(String resourceId, int toIndex) {
    final fromIndex = _indexOf(resourceId);
    return fromIndex == -1 ? this : reorder(fromIndex, toIndex);
  }

  BdoGatherChecklist toggleCompletion(String resourceId) {
    final index = _indexOf(resourceId);
    if (index == -1) {
      return this;
    }
    return setCompletion(
      entries[index].resourceId,
      !entries[index].isCompleted,
    );
  }

  BdoGatherChecklist setCompletion(String resourceId, bool isCompleted) {
    final index = _indexOf(resourceId);
    if (index == -1 || entries[index].isCompleted == isCompleted) {
      return this;
    }
    final nextEntries = entries.toList();
    nextEntries[index] = nextEntries[index].copyWith(isCompleted: isCompleted);
    return BdoGatherChecklist(
      entries: nextEntries,
      selectedResourceId: selectedResourceId,
    );
  }

  BdoGatherChecklist clearCompleted() {
    if (completedCount == 0) {
      return this;
    }
    final nextEntries = entries
        .where((entry) => !entry.isCompleted)
        .toList(growable: false);
    return BdoGatherChecklist(
      entries: nextEntries,
      selectedResourceId: selectedResourceId,
    );
  }

  /// Selects an existing entry. Null clears the explicit selection.
  ///
  /// Unknown IDs are ignored so a stale UI event cannot unexpectedly discard
  /// a valid current selection.
  BdoGatherChecklist select(String? resourceId) {
    if (resourceId == null) {
      return clearSelection();
    }
    final index = _indexOf(resourceId);
    if (index == -1) {
      return this;
    }
    final normalizedId = entries[index].resourceId;
    if (normalizedId == selectedResourceId) {
      return this;
    }
    return BdoGatherChecklist(
      entries: entries,
      selectedResourceId: normalizedId,
    );
  }

  BdoGatherChecklist clearSelection() {
    if (selectedResourceId == null) {
      return this;
    }
    return BdoGatherChecklist(entries: entries);
  }

  /// Finds the next unfinished entry in user-defined order.
  ///
  /// With no anchor this returns the first unfinished entry. With [afterId],
  /// searching begins after that entry and optionally wraps to the beginning.
  BdoGatherChecklistEntry? nextIncompleteEntry({
    String? afterId,
    bool wrap = true,
  }) {
    if (entries.isEmpty) {
      return null;
    }
    final anchorIndex = afterId == null ? -1 : _indexOf(afterId);
    if (anchorIndex == -1) {
      return firstIncompleteEntry;
    }
    for (var index = anchorIndex + 1; index < entries.length; index += 1) {
      if (!entries[index].isCompleted) {
        return entries[index];
      }
    }
    if (wrap) {
      for (var index = 0; index <= anchorIndex; index += 1) {
        if (!entries[index].isCompleted) {
          return entries[index];
        }
      }
    }
    return null;
  }

  /// Advances selection to the next unfinished entry.
  ///
  /// If all entries are complete, the explicit selection is cleared.
  BdoGatherChecklist selectNextIncomplete({bool wrap = true}) {
    final next = nextIncompleteEntry(afterId: selectedResourceId, wrap: wrap);
    return next == null ? clearSelection() : select(next.resourceId);
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'schemaVersion': schemaVersion,
    'entries': entries.map((entry) => entry.toJson()).toList(growable: false),
    'selectedResourceId': ?selectedResourceId,
  };

  /// Restores current schema data and tolerant legacy list/map shapes.
  ///
  /// Malformed entries are skipped independently. Duplicate IDs keep their
  /// first position, merge useful metadata, and retain any completed state.
  factory BdoGatherChecklist.fromJson(Object? json) {
    if (json is Iterable && json is! String) {
      return BdoGatherChecklist(entries: _entriesFromJson(json));
    }
    if (json is! Map) {
      return BdoGatherChecklist();
    }

    final rawEntries = json['entries'] ?? json['items'] ?? json['resources'];
    final selectedId = _normalizedId(
      json['selectedResourceId'] ??
          json['currentResourceId'] ??
          json['currentItemId'],
    );
    return BdoGatherChecklist(
      entries: _entriesFromJson(rawEntries),
      selectedResourceId: selectedId,
    );
  }

  int _indexOf(Object? resourceId) {
    final normalizedId = _normalizedId(resourceId);
    if (normalizedId == null) {
      return -1;
    }
    return entries.indexWhere((entry) => entry.resourceId == normalizedId);
  }

  BdoGatherChecklistEntry? _entryWithId(Object? resourceId) {
    final index = _indexOf(resourceId);
    return index == -1 ? null : entries[index];
  }

  @override
  bool operator ==(Object other) =>
      other is BdoGatherChecklist &&
      selectedResourceId == other.selectedResourceId &&
      _listsEqual(entries, other.entries);

  @override
  int get hashCode => Object.hash(selectedResourceId, Object.hashAll(entries));

  @override
  String toString() =>
      'BdoGatherChecklist(entries: ${entries.length}, '
      'selectedResourceId: $selectedResourceId)';
}

List<BdoGatherChecklistEntry> _mergeEntries(
  Iterable<BdoGatherChecklistEntry> entries,
) {
  final result = <BdoGatherChecklistEntry>[];
  final indexes = <String, int>{};
  for (final entry in entries) {
    final index = indexes[entry.resourceId];
    if (index == null) {
      indexes[entry.resourceId] = result.length;
      result.add(entry);
    } else {
      result[index] = _mergeEntry(result[index], entry);
    }
  }
  return result;
}

BdoGatherChecklistEntry _mergeEntry(
  BdoGatherChecklistEntry existing,
  BdoGatherChecklistEntry incoming,
) {
  assert(existing.resourceId == incoming.resourceId);
  return existing.copyWith(
    displayName: incoming.displayName,
    sourceKind: incoming.sourceKind,
    isCompleted: existing.isCompleted || incoming.isCompleted,
  );
}

Iterable<BdoGatherChecklistEntry> _entriesFromJson(Object? value) sync* {
  if (value is Map) {
    for (final rawEntry in value.entries) {
      final decoded = _entryFromJson(
        rawEntry.value,
        fallbackResourceId: rawEntry.key,
      );
      if (decoded != null) {
        yield decoded;
      }
    }
    return;
  }
  if (value is! Iterable || value is String) {
    return;
  }
  for (final rawEntry in value) {
    final decoded = _entryFromJson(rawEntry);
    if (decoded != null) {
      yield decoded;
    }
  }
}

BdoGatherChecklistEntry? _entryFromJson(
  Object? value, {
  Object? fallbackResourceId,
}) {
  if (value is String || value is num) {
    final id = _normalizedId(fallbackResourceId ?? value);
    if (id == null) {
      return null;
    }
    return BdoGatherChecklistEntry(
      resourceId: id,
      displayName: fallbackResourceId == null ? null : '$value',
    );
  }
  if (value is bool && fallbackResourceId != null) {
    final id = _normalizedId(fallbackResourceId);
    return id == null
        ? null
        : BdoGatherChecklistEntry(resourceId: id, isCompleted: value);
  }
  if (value is! Map) {
    return null;
  }
  final id = _normalizedId(
    value['resourceId'] ??
        value['materialId'] ??
        value['itemId'] ??
        value['id'] ??
        fallbackResourceId,
  );
  if (id == null) {
    return null;
  }
  return BdoGatherChecklistEntry(
    resourceId: id,
    displayName: _normalizedOptionalText(
      value['displayName'] ?? value['name'] ?? value['label'],
    ),
    sourceKind: _sourceKindFromJson(
      value['sourceKind'] ?? value['source'] ?? value['route'],
    ),
    isCompleted: _boolFromJson(
      value['completed'] ?? value['isCompleted'] ?? value['done'],
    ),
  );
}

String? _normalizedId(Object? value) {
  if (value is! String && value is! num) {
    return null;
  }
  final normalized = value.toString().trim();
  return normalized.isEmpty ? null : normalized;
}

String? _normalizedOptionalText(Object? value) {
  if (value is! String) {
    return null;
  }
  final normalized = value.trim();
  return normalized.isEmpty ? null : normalized;
}

bool _boolFromJson(Object? value) {
  if (value is bool) {
    return value;
  }
  if (value is num) {
    return value != 0;
  }
  if (value is String) {
    switch (value.trim().toLowerCase()) {
      case '1':
      case 'true':
      case 'yes':
      case 'done':
      case 'completed':
        return true;
      case '0':
      case 'false':
      case 'no':
      case 'pending':
        return false;
    }
  }
  return false;
}

BdoGatherChecklistSourceKind? _sourceKindFromJson(Object? value) {
  if (value is! String) {
    return null;
  }
  switch (value.trim().toLowerCase().replaceAll(RegExp(r'[^a-z]'), '')) {
    case 'manual':
    case 'gather':
    case 'gathering':
    case 'manualgathering':
      return BdoGatherChecklistSourceKind.manualGathering;
    case 'worker':
    case 'node':
    case 'workernode':
      return BdoGatherChecklistSourceKind.workerNode;
    case 'fish':
    case 'fishing':
      return BdoGatherChecklistSourceKind.fishing;
  }
  return null;
}

String _sourceKindName(BdoGatherChecklistSourceKind sourceKind) =>
    switch (sourceKind) {
      BdoGatherChecklistSourceKind.manualGathering => 'manualGathering',
      BdoGatherChecklistSourceKind.workerNode => 'workerNode',
      BdoGatherChecklistSourceKind.fishing => 'fishing',
    };

bool _listsEqual(
  List<BdoGatherChecklistEntry> left,
  List<BdoGatherChecklistEntry> right,
) {
  if (left.length != right.length) {
    return false;
  }
  for (var index = 0; index < left.length; index += 1) {
    if (left[index] != right[index]) {
      return false;
    }
  }
  return true;
}
