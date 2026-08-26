import 'lodging_data.dart';

/// Reviewed Storage capacity by house-service level.
///
/// Source: the BDO Codex house page for Storage (NPC 3107), reviewed on
/// 2026-08-20: https://bdocodex.com/us/npc/3107/
///
/// The bundled house graph records the maximum available Storage level for
/// each house. It does not record the player's active upgrade level, so an
/// owned house explicitly saved as Storage is treated as upgraded to that
/// recorded maximum. Callers must surface this assumption to the player.
const Map<int, int> storageSlotsByLevel = <int, int>{
  1: 3,
  2: 5,
  3: 8,
  4: 12,
  5: 16,
};

int storageSlotsForLevel(int level) {
  final slots = storageSlotsByLevel[level];
  if (slots == null) {
    throw ArgumentError.value(
      level,
      'level',
      'Storage capacity is reviewed only for levels 1 through 5.',
    );
  }
  return slots;
}

int storageSlotsForHouse(LodgingHouse house) {
  final storage = house.usagesByTypeId[2];
  if (storage == null) return 0;
  return storageSlotsForLevel(storage.level);
}

/// Exact minimum-incremental-CP plan for extra Storage slots in one town.
final class StorageHousePlan {
  StorageHousePlan({
    required this.townNodeId,
    required this.requestedAdditionalSlots,
    required this.existingStorageSlots,
    required this.addedStorageSlots,
    required this.incrementalContributionPoints,
    required this.isFeasible,
    required Iterable<String> selectedStorageHouseIds,
    required Iterable<String> prerequisiteHouseIds,
    required Iterable<String> fullHouseClosureIds,
    required Iterable<String> newlyRequiredHouseIds,
    required Iterable<String> ownedHouseIdsUsed,
    required Iterable<String> protectedOwnedHouseIds,
    required Iterable<String> unknownUseOwnedHouseIds,
  }) : selectedStorageHouseIds = _sortedIds(selectedStorageHouseIds),
       prerequisiteHouseIds = _sortedIds(prerequisiteHouseIds),
       fullHouseClosureIds = _sortedIds(fullHouseClosureIds),
       newlyRequiredHouseIds = _sortedIds(newlyRequiredHouseIds),
       ownedHouseIdsUsed = _sortedIds(ownedHouseIdsUsed),
       protectedOwnedHouseIds = _sortedIds(protectedOwnedHouseIds),
       unknownUseOwnedHouseIds = _sortedIds(unknownUseOwnedHouseIds);

  final String townNodeId;
  final int requestedAdditionalSlots;
  final int existingStorageSlots;
  final int addedStorageSlots;
  final int incrementalContributionPoints;
  final bool isFeasible;
  final List<String> selectedStorageHouseIds;
  final List<String> prerequisiteHouseIds;
  final List<String> fullHouseClosureIds;
  final List<String> newlyRequiredHouseIds;
  final List<String> ownedHouseIdsUsed;
  final List<String> protectedOwnedHouseIds;
  final List<String> unknownUseOwnedHouseIds;

  int get totalStorageSlots => existingStorageSlots + addedStorageSlots;
  int get slotShortfall => (requestedAdditionalSlots - addedStorageSlots).clamp(
    0,
    requestedAdditionalSlots,
  );
  int get slotOversupply => (addedStorageSlots - requestedAdditionalSlots)
      .clamp(0, addedStorageSlots);
}

/// Finds a cheapest connected house portfolio for requested extra slots.
///
/// Owned houses saved as Storage contribute capacity at their recorded maximum
/// Storage level. Owned houses saved to another use, and owned houses with no
/// saved use, remain protected: they may satisfy a prerequisite but are never
/// silently converted to Storage.
abstract final class StorageHouseOptimizer {
  static StorageHousePlan solve({
    required LodgingTown town,
    required int requestedAdditionalSlots,
    Set<String> currentOwnedHouseIds = const <String>{},
    Map<String, int> currentHouseUsageTypeIds = const <String, int>{},
  }) {
    if (requestedAdditionalSlots < 0) {
      throw ArgumentError.value(
        requestedAdditionalSlots,
        'requestedAdditionalSlots',
        'Requested extra Storage slots cannot be negative.',
      );
    }
    final owned = currentOwnedHouseIds
        .where(town.housesById.containsKey)
        .toSet();
    final protected = <String>{};
    final unknownUse = <String>{};
    var existingStorageSlots = 0;
    for (final house in town.houses.where(
      (entry) => owned.contains(entry.id),
    )) {
      final usageTypeId = currentHouseUsageTypeIds[house.id];
      if (usageTypeId == 2) {
        existingStorageSlots += storageSlotsForHouse(house);
      } else if (usageTypeId == null) {
        unknownUse.add(house.id);
      } else {
        protected.add(house.id);
      }
    }

    if (requestedAdditionalSlots == 0) {
      return StorageHousePlan(
        townNodeId: town.townNodeId,
        requestedAdditionalSlots: 0,
        existingStorageSlots: existingStorageSlots,
        addedStorageSlots: 0,
        incrementalContributionPoints: 0,
        isFeasible: true,
        selectedStorageHouseIds: const <String>[],
        prerequisiteHouseIds: const <String>[],
        fullHouseClosureIds: const <String>[],
        newlyRequiredHouseIds: const <String>[],
        ownedHouseIdsUsed: const <String>[],
        protectedOwnedHouseIds: protected,
        unknownUseOwnedHouseIds: unknownUse,
      );
    }

    final children = <String, List<String>>{};
    final roots = <String>[];
    for (final house in town.houses) {
      if (owned.contains(house.id)) continue;
      final prerequisiteId = house.prerequisiteHouseId;
      if (prerequisiteId == null || owned.contains(prerequisiteId)) {
        roots.add(house.id);
      } else {
        children.putIfAbsent(prerequisiteId, () => <String>[]).add(house.id);
      }
    }
    roots.sort(_compareHouseIds);
    for (final values in children.values) {
      values.sort(_compareHouseIds);
    }

    Map<int, _StorageCandidate> solveSubtree(String houseId) {
      final house = town.housesById[houseId]!;
      final acquired = _StorageCandidate(
        addedSlots: 0,
        incrementalCp: house.contributionPoints,
        selectedHouseIds: const <String>{},
        newlyRequiredHouseIds: <String>{houseId},
      );
      var options = <int, _StorageCandidate>{0: acquired};
      final slots = storageSlotsForHouse(house);
      if (slots > 0) {
        final selected = acquired.withSelected(house.id, slots);
        options[_slotKey(selected.addedSlots, requestedAdditionalSlots)] =
            selected;
      }
      for (final childId in children[houseId] ?? const <String>[]) {
        options = _mergeOptions(options, <int, _StorageCandidate>{
          0: _StorageCandidate.empty,
          ...solveSubtree(childId),
        }, requestedAdditionalSlots);
      }
      return <int, _StorageCandidate>{...options, 0: _StorageCandidate.empty};
    }

    var portfolio = <int, _StorageCandidate>{0: _StorageCandidate.empty};
    for (final rootId in roots) {
      portfolio = _mergeOptions(
        portfolio,
        solveSubtree(rootId),
        requestedAdditionalSlots,
      );
    }

    final isFeasible = portfolio.containsKey(requestedAdditionalSlots);
    final candidate = isFeasible
        ? portfolio[requestedAdditionalSlots]!
        : portfolio.entries.reduce((left, right) {
            if (right.key != left.key) {
              return right.key > left.key ? right : left;
            }
            return _isBetter(right.value, left.value) ? right : left;
          }).value;
    final fullClosure = <String>{};
    for (final selectedId in candidate.selectedHouseIds) {
      String? currentId = selectedId;
      while (currentId != null && fullClosure.add(currentId)) {
        currentId = town.housesById[currentId]!.prerequisiteHouseId;
      }
    }
    final prerequisites = <String>{...fullClosure}
      ..removeAll(candidate.selectedHouseIds);
    final ownedUsed = fullClosure.intersection(owned);

    return StorageHousePlan(
      townNodeId: town.townNodeId,
      requestedAdditionalSlots: requestedAdditionalSlots,
      existingStorageSlots: existingStorageSlots,
      addedStorageSlots: candidate.addedSlots,
      incrementalContributionPoints: candidate.incrementalCp,
      isFeasible: isFeasible,
      selectedStorageHouseIds: candidate.selectedHouseIds,
      prerequisiteHouseIds: prerequisites,
      fullHouseClosureIds: fullClosure,
      newlyRequiredHouseIds: candidate.newlyRequiredHouseIds,
      ownedHouseIdsUsed: ownedUsed,
      protectedOwnedHouseIds: protected,
      unknownUseOwnedHouseIds: unknownUse,
    );
  }
}

Map<int, _StorageCandidate> _mergeOptions(
  Map<int, _StorageCandidate> left,
  Map<int, _StorageCandidate> right,
  int slotTarget,
) {
  final merged = <int, _StorageCandidate>{};
  for (final leftCandidate in left.values) {
    for (final rightCandidate in right.values) {
      final candidate = leftCandidate.combine(rightCandidate);
      final key = _slotKey(candidate.addedSlots, slotTarget);
      final incumbent = merged[key];
      if (incumbent == null || _isBetter(candidate, incumbent)) {
        merged[key] = candidate;
      }
    }
  }
  return merged;
}

int _slotKey(int slots, int target) => slots.clamp(0, target);

bool _isBetter(_StorageCandidate candidate, _StorageCandidate incumbent) {
  if (candidate.incrementalCp != incumbent.incrementalCp) {
    return candidate.incrementalCp < incumbent.incrementalCp;
  }
  if (candidate.addedSlots != incumbent.addedSlots) {
    return candidate.addedSlots < incumbent.addedSlots;
  }
  if (candidate.newlyRequiredHouseIds.length !=
      incumbent.newlyRequiredHouseIds.length) {
    return candidate.newlyRequiredHouseIds.length <
        incumbent.newlyRequiredHouseIds.length;
  }
  final candidateIds = _sortedIds(candidate.selectedHouseIds);
  final incumbentIds = _sortedIds(incumbent.selectedHouseIds);
  for (
    var index = 0;
    index < candidateIds.length && index < incumbentIds.length;
    index += 1
  ) {
    final comparison = _compareHouseIds(
      candidateIds[index],
      incumbentIds[index],
    );
    if (comparison != 0) return comparison < 0;
  }
  return candidateIds.length < incumbentIds.length;
}

final class _StorageCandidate {
  _StorageCandidate({
    required this.addedSlots,
    required this.incrementalCp,
    required Set<String> selectedHouseIds,
    required Set<String> newlyRequiredHouseIds,
  }) : selectedHouseIds = Set<String>.unmodifiable(selectedHouseIds),
       newlyRequiredHouseIds = Set<String>.unmodifiable(newlyRequiredHouseIds);

  static final empty = _StorageCandidate(
    addedSlots: 0,
    incrementalCp: 0,
    selectedHouseIds: const <String>{},
    newlyRequiredHouseIds: const <String>{},
  );

  final int addedSlots;
  final int incrementalCp;
  final Set<String> selectedHouseIds;
  final Set<String> newlyRequiredHouseIds;

  _StorageCandidate withSelected(String houseId, int slots) {
    return _StorageCandidate(
      addedSlots: addedSlots + slots,
      incrementalCp: incrementalCp,
      selectedHouseIds: <String>{...selectedHouseIds, houseId},
      newlyRequiredHouseIds: newlyRequiredHouseIds,
    );
  }

  _StorageCandidate combine(_StorageCandidate other) {
    return _StorageCandidate(
      addedSlots: addedSlots + other.addedSlots,
      incrementalCp: incrementalCp + other.incrementalCp,
      selectedHouseIds: <String>{
        ...selectedHouseIds,
        ...other.selectedHouseIds,
      },
      newlyRequiredHouseIds: <String>{
        ...newlyRequiredHouseIds,
        ...other.newlyRequiredHouseIds,
      },
    );
  }
}

List<String> _sortedIds(Iterable<String> values) =>
    values.toSet().toList(growable: false)..sort(_compareHouseIds);

int _compareHouseIds(String left, String right) {
  final leftKey = int.tryParse(left.split(':').last);
  final rightKey = int.tryParse(right.split(':').last);
  if (leftKey != null && rightKey != null && leftKey != rightKey) {
    return leftKey.compareTo(rightKey);
  }
  return left.compareTo(right);
}
