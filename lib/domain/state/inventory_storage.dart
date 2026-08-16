import 'planner_state.dart';
import 'state_copy.dart';

const inventoryStorageExtensionKey = 'inventoryStorageV1';
const inventoryUnassignedLocationId = 'unassigned';

/// One named BDO storage or character inventory.
///
/// Quantities are deliberately kept mode-local for the first release. That
/// preserves the planner's existing Alchemy/Cooking/Processing totals while
/// still allowing each mode to remember where its materials are stored.
final class InventoryStorageLocation {
  InventoryStorageLocation({
    required this.id,
    required this.name,
    Map<String, double> quantities = const <String, double>{},
  }) : quantities = Map<String, double>.unmodifiable(quantities);

  final String id;
  final String name;
  final Map<String, double> quantities;

  bool get isUnassigned => id == inventoryUnassignedLocationId;

  InventoryStorageLocation copyWith({
    String? name,
    Map<String, double>? quantities,
  }) => InventoryStorageLocation(
    id: id,
    name: name ?? this.name,
    quantities: quantities ?? this.quantities,
  );

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'name': name,
    'quantities': quantities,
  };
}

/// Versioned named-location inventory stored in [ModeState.extensions].
///
/// [ModeState.inventory] remains the planner-facing aggregate. Every mutation
/// in this class writes both representations together. Older Beta builds keep
/// this extension opaque and continue using the aggregate map.
final class InventoryStorageState {
  InventoryStorageState._({
    required List<InventoryStorageLocation> locations,
    required this.selectedLocationId,
    required this.hadPersistedLedger,
    required this.recoveredFromMismatch,
  }) : locations = List<InventoryStorageLocation>.unmodifiable(locations);

  factory InventoryStorageState.fromModeState(ModeState mode) {
    final raw = mode.extensions[inventoryStorageExtensionKey];
    if (raw == null) {
      return InventoryStorageState._legacy(mode.inventory);
    }
    try {
      final parsed = InventoryStorageState._fromJson(raw);
      if (!_sameQuantities(parsed.aggregate, mode.inventory)) {
        return InventoryStorageState._legacy(
          mode.inventory,
          hadPersistedLedger: true,
          recoveredFromMismatch: true,
        );
      }
      return parsed;
    } on FormatException {
      return InventoryStorageState._legacy(
        mode.inventory,
        hadPersistedLedger: true,
        recoveredFromMismatch: true,
      );
    }
  }

  factory InventoryStorageState._legacy(
    Map<String, double> inventory, {
    bool hadPersistedLedger = false,
    bool recoveredFromMismatch = false,
  }) => InventoryStorageState._(
    locations: <InventoryStorageLocation>[
      InventoryStorageLocation(
        id: inventoryUnassignedLocationId,
        name: 'Unassigned',
        quantities: _validatedQuantities(inventory),
      ),
    ],
    selectedLocationId: inventoryUnassignedLocationId,
    hadPersistedLedger: hadPersistedLedger,
    recoveredFromMismatch: recoveredFromMismatch,
  );

  factory InventoryStorageState._fromJson(Object? value) {
    if (value is! Map) {
      throw const FormatException('Inventory storage must be an object.');
    }
    final json = <String, Object?>{
      for (final entry in value.entries) entry.key.toString(): entry.value,
    };
    if (json['schemaVersion'] != 1) {
      throw const FormatException('Unsupported inventory storage version.');
    }
    final rawLocations = json['locations'];
    if (rawLocations is! List || rawLocations.isEmpty) {
      throw const FormatException('Inventory storage locations are missing.');
    }
    final locations = <InventoryStorageLocation>[];
    final ids = <String>{};
    final names = <String>{};
    for (final rawLocation in rawLocations) {
      if (rawLocation is! Map) {
        throw const FormatException('Inventory storage location is invalid.');
      }
      final source = <String, Object?>{
        for (final entry in rawLocation.entries)
          entry.key.toString(): entry.value,
      };
      final id = _nonBlankString(source['id']);
      final name = _nonBlankString(source['name']);
      if (id == null || name == null || !_validLocationId(id)) {
        throw const FormatException('Inventory storage identity is invalid.');
      }
      if (!ids.add(_fold(id)) || !names.add(_fold(name))) {
        throw const FormatException('Inventory storage locations collide.');
      }
      final rawQuantities = source['quantities'];
      if (rawQuantities is! Map) {
        throw const FormatException(
          'Inventory storage quantities are invalid.',
        );
      }
      locations.add(
        InventoryStorageLocation(
          id: id,
          name: name,
          quantities: _validatedQuantities(<String, Object?>{
            for (final entry in rawQuantities.entries)
              entry.key.toString(): entry.value,
          }),
        ),
      );
    }
    if (!ids.contains(inventoryUnassignedLocationId)) {
      throw const FormatException('The Unassigned storage is missing.');
    }
    final requested = _nonBlankString(json['selectedLocationId']);
    final selected = requested != null && ids.contains(_fold(requested))
        ? locations.firstWhere((location) => _same(location.id, requested)).id
        : inventoryUnassignedLocationId;
    return InventoryStorageState._(
      locations: locations,
      selectedLocationId: selected,
      hadPersistedLedger: true,
      recoveredFromMismatch: false,
    );
  }

  final List<InventoryStorageLocation> locations;
  final String selectedLocationId;
  final bool hadPersistedLedger;
  final bool recoveredFromMismatch;

  InventoryStorageLocation get selectedLocation => locations.firstWhere(
    (location) => _same(location.id, selectedLocationId),
    orElse: () => locations.first,
  );

  Map<String, double> get aggregate {
    final values = <String, double>{};
    final canonical = <String, String>{};
    for (final location in locations) {
      for (final entry in location.quantities.entries) {
        final folded = _fold(entry.key);
        final key = canonical.putIfAbsent(folded, () => entry.key);
        values[key] = (values[key] ?? 0) + entry.value;
      }
    }
    values.removeWhere((_, value) => value <= 0);
    return Map<String, double>.unmodifiable(values);
  }

  double quantityAt(String locationId, String itemName) {
    final location = locationById(locationId);
    if (location == null) return 0;
    final entry = _matchingEntry(location.quantities, itemName);
    return entry?.value ?? 0;
  }

  double totalFor(String itemName) =>
      _matchingEntry(aggregate, itemName)?.value ?? 0;

  InventoryStorageLocation? locationById(String id) {
    for (final location in locations) {
      if (_same(location.id, id)) return location;
    }
    return null;
  }

  ({InventoryStorageState state, InventoryStorageLocation location})
  ensureLocation(String requestedName) {
    final name = _normalizeName(requestedName);
    if (name.isEmpty || _same(name, 'Unassigned')) {
      return (state: this, location: locations.first);
    }
    for (final location in locations) {
      if (_same(location.name, name)) {
        return (state: select(location.id), location: location);
      }
    }
    final used = locations.map((location) => _fold(location.id)).toSet();
    final base = _slug(name);
    var id = base;
    var suffix = 2;
    while (used.contains(_fold(id))) {
      id = '$base-$suffix';
      suffix += 1;
    }
    final location = InventoryStorageLocation(id: id, name: name);
    return (
      state: InventoryStorageState._(
        locations: <InventoryStorageLocation>[...locations, location],
        selectedLocationId: id,
        hadPersistedLedger: true,
        recoveredFromMismatch: false,
      ),
      location: location,
    );
  }

  InventoryStorageState select(String locationId) {
    final location = locationById(locationId);
    if (location == null || location.id == selectedLocationId) return this;
    return InventoryStorageState._(
      locations: locations,
      selectedLocationId: location.id,
      hadPersistedLedger: true,
      recoveredFromMismatch: false,
    );
  }

  InventoryStorageState renameLocation(String locationId, String requested) {
    final location = locationById(locationId);
    final name = _normalizeName(requested);
    if (location == null || location.isUnassigned || name.isEmpty) return this;
    if (locations.any(
      (other) => other.id != location.id && _same(other.name, name),
    )) {
      throw const FormatException('A storage with that name already exists.');
    }
    return _replaceLocation(location.copyWith(name: name));
  }

  InventoryStorageState removeLocation(String locationId) {
    final location = locationById(locationId);
    if (location == null || location.isUnassigned) return this;
    final unassigned = locations.firstWhere(
      (candidate) => candidate.isUnassigned,
    );
    final merged = Map<String, double>.of(unassigned.quantities);
    for (final entry in location.quantities.entries) {
      final existing = _matchingEntry(merged, entry.key);
      final key = existing?.key ?? entry.key;
      merged[key] = (existing?.value ?? 0) + entry.value;
    }
    return InventoryStorageState._(
      locations: <InventoryStorageLocation>[
        unassigned.copyWith(quantities: merged),
        for (final candidate in locations)
          if (!candidate.isUnassigned && candidate.id != location.id) candidate,
      ],
      selectedLocationId: selectedLocationId == location.id
          ? inventoryUnassignedLocationId
          : selectedLocationId,
      hadPersistedLedger: true,
      recoveredFromMismatch: false,
    );
  }

  InventoryStorageState setQuantity({
    required String locationId,
    required String itemName,
    required double quantity,
  }) {
    if (!quantity.isFinite || quantity < 0) {
      throw const FormatException('Inventory quantities must be nonnegative.');
    }
    final location = locationById(locationId);
    final name = _normalizeName(itemName);
    if (location == null || name.isEmpty) return this;
    final quantities = Map<String, double>.of(location.quantities);
    final existing = _matchingEntry(quantities, name);
    if (existing != null) quantities.remove(existing.key);
    if (quantity > 0) quantities[existing?.key ?? name] = quantity;
    return _replaceLocation(location.copyWith(quantities: quantities));
  }

  InventoryStorageState addQuantity({
    required String locationId,
    required String itemName,
    required double quantity,
  }) {
    if (!quantity.isFinite || quantity <= 0) return this;
    return setQuantity(
      locationId: locationId,
      itemName: itemName,
      quantity: quantityAt(locationId, itemName) + quantity,
    );
  }

  /// Replaces only the recognized items at one location. Items absent from a
  /// partial screenshot remain untouched. A confirmed zero removes only that
  /// location's amount.
  InventoryStorageState applyReviewedScreenshot({
    required String locationId,
    required Map<String, double> quantities,
    bool replaceMatchingUnassigned = false,
  }) {
    var next = this;
    for (final entry in quantities.entries) {
      next = next.setQuantity(
        locationId: locationId,
        itemName: entry.key,
        quantity: entry.value,
      );
      if (replaceMatchingUnassigned &&
          locationId != inventoryUnassignedLocationId) {
        next = next.setQuantity(
          locationId: inventoryUnassignedLocationId,
          itemName: entry.key,
          quantity: 0,
        );
      }
    }
    return next.select(locationId);
  }

  InventoryStorageState renameItem(String oldName, String newName) {
    final normalized = _normalizeName(newName);
    if (normalized.isEmpty || _same(oldName, normalized)) return this;
    var next = this;
    for (final location in locations) {
      final oldEntry = _matchingEntry(location.quantities, oldName);
      if (oldEntry == null) continue;
      final existing = _matchingEntry(location.quantities, normalized);
      final quantities = Map<String, double>.of(location.quantities)
        ..remove(oldEntry.key);
      if (existing != null) quantities.remove(existing.key);
      quantities[normalized] = oldEntry.value + (existing?.value ?? 0);
      next = next._replaceLocation(location.copyWith(quantities: quantities));
    }
    return next;
  }

  InventoryStorageState removeItem(String itemName) {
    var next = this;
    for (final location in locations) {
      final existing = _matchingEntry(location.quantities, itemName);
      if (existing == null) continue;
      final quantities = Map<String, double>.of(location.quantities)
        ..remove(existing.key);
      next = next._replaceLocation(location.copyWith(quantities: quantities));
    }
    return next;
  }

  InventoryStorageState clearQuantities() => InventoryStorageState._(
    locations: <InventoryStorageLocation>[
      for (final location in locations)
        location.copyWith(quantities: const <String, double>{}),
    ],
    selectedLocationId: selectedLocationId,
    hadPersistedLedger: true,
    recoveredFromMismatch: false,
  );

  ModeState applyTo(ModeState mode) {
    final extensions = Map<String, Object?>.of(mode.extensions)
      ..[inventoryStorageExtensionKey] = toJson();
    return mode.copyWith(inventory: aggregate, extensions: extensions);
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'schemaVersion': 1,
    'selectedLocationId': selectedLocationId,
    'locations': <Object?>[for (final location in locations) location.toJson()],
  };

  InventoryStorageState _replaceLocation(
    InventoryStorageLocation replacement,
  ) => InventoryStorageState._(
    locations: <InventoryStorageLocation>[
      for (final location in locations)
        if (location.id == replacement.id) replacement else location,
    ],
    selectedLocationId: selectedLocationId,
    hadPersistedLedger: true,
    recoveredFromMismatch: false,
  );
}

Map<String, double> _validatedQuantities(Map<String, Object?> source) {
  final result = <String, double>{};
  final names = <String>{};
  for (final entry in source.entries) {
    final name = _normalizeName(entry.key);
    final value = entry.value;
    if (name.isEmpty || value is! num || !value.isFinite || value < 0) {
      throw const FormatException('Inventory quantity is invalid.');
    }
    if (!names.add(_fold(name))) {
      throw const FormatException('Inventory item names collide.');
    }
    if (value > 0) result[name] = value.toDouble();
  }
  return result;
}

MapEntry<String, double>? _matchingEntry(
  Map<String, double> values,
  String name,
) {
  for (final entry in values.entries) {
    if (_same(entry.key, name)) return entry;
  }
  return null;
}

bool _sameQuantities(Map<String, double> left, Map<String, double> right) {
  if (left.length != right.length) return false;
  for (final entry in left.entries) {
    final other = _matchingEntry(right, entry.key);
    if (other == null || other.value != entry.value) return false;
  }
  return true;
}

String? _nonBlankString(Object? value) {
  if (value is! String) return null;
  final normalized = _normalizeName(value);
  return normalized.isEmpty ? null : normalized;
}

String _normalizeName(String value) => value
    .trim()
    .split(RegExp(r'\s+'))
    .where((part) => part.isNotEmpty)
    .join(' ');

bool _validLocationId(String value) =>
    RegExp(r'^[a-z0-9]+(?:-[a-z0-9]+)*$').hasMatch(value);

String _slug(String value) {
  final slug = _fold(
    value,
  ).replaceAll(RegExp(r'[^a-z0-9]+'), '-').replaceAll(RegExp(r'^-+|-+$'), '');
  return slug.isEmpty ? 'storage' : slug;
}

bool _same(String left, String right) => _fold(left) == _fold(right);
String _fold(String value) => value.trim().toLowerCase();
