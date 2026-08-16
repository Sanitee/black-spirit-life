import 'lodging_data.dart';

final class LodgingPlan {
  LodgingPlan({
    required this.townNodeId,
    required this.requiredCapacity,
    required this.existingCapacity,
    required this.addedCapacity,
    required this.incrementalContributionPoints,
    required this.isFeasible,
    required Iterable<String> selectedLodgingHouseIds,
    required Iterable<String> prerequisiteHouseIds,
    required Iterable<String> fullHouseClosureIds,
    required Iterable<String> newlyRequiredHouseIds,
    required Iterable<String> ownedHouseIdsUsed,
  }) : selectedLodgingHouseIds = _sortedIds(selectedLodgingHouseIds),
       prerequisiteHouseIds = _sortedIds(prerequisiteHouseIds),
       fullHouseClosureIds = _sortedIds(fullHouseClosureIds),
       newlyRequiredHouseIds = _sortedIds(newlyRequiredHouseIds),
       ownedHouseIdsUsed = _sortedIds(ownedHouseIdsUsed);

  final String townNodeId;
  final int requiredCapacity;
  final int existingCapacity;
  final int addedCapacity;
  final int incrementalContributionPoints;
  final bool isFeasible;
  final List<String> selectedLodgingHouseIds;

  /// Every source prerequisite of a selected lodging house, including owned
  /// houses and ancestors beyond an already-owned prerequisite.
  final List<String> prerequisiteHouseIds;
  final List<String> fullHouseClosureIds;

  /// Houses that must be newly purchased. An already-owned prerequisite ends
  /// the acquisition chain and costs no additional CP.
  final List<String> newlyRequiredHouseIds;
  final List<String> ownedHouseIdsUsed;

  int get totalCapacity => existingCapacity + addedCapacity;
  int get capacityShortfall =>
      (requiredCapacity - totalCapacity).clamp(0, requiredCapacity);
  int get capacityOversupply =>
      (totalCapacity - requiredCapacity).clamp(0, totalCapacity);
}

abstract final class LodgingOptimizer {
  /// Finds an exact minimum-incremental-CP lodging plan for one town.
  ///
  /// [existingCapacity] is authoritative and must already include the free
  /// town slot and every currently active lodging slot. Owned houses therefore
  /// reduce acquisition cost but never add capacity a second time.
  ///
  /// A blocked lodging house may still be acquired as a prerequisite, but it
  /// cannot be selected as a lodging source.
  static LodgingPlan solve({
    required LodgingTown town,
    required int requiredCapacity,
    required int existingCapacity,
    Set<String> currentOwnedHouseIds = const <String>{},
    Set<String> blockedHouseIds = const <String>{},
  }) {
    if (requiredCapacity < 0 || existingCapacity < 0) {
      throw ArgumentError('Worker capacities cannot be negative.');
    }
    final additionalRequired = (requiredCapacity - existingCapacity).clamp(
      0,
      requiredCapacity,
    );
    if (additionalRequired == 0) {
      return LodgingPlan(
        townNodeId: town.townNodeId,
        requiredCapacity: requiredCapacity,
        existingCapacity: existingCapacity,
        addedCapacity: 0,
        incrementalContributionPoints: 0,
        isFeasible: true,
        selectedLodgingHouseIds: const <String>[],
        prerequisiteHouseIds: const <String>[],
        fullHouseClosureIds: const <String>[],
        newlyRequiredHouseIds: const <String>[],
        ownedHouseIdsUsed: const <String>[],
      );
    }

    final owned = currentOwnedHouseIds
        .where(town.housesById.containsKey)
        .toSet();
    final blocked = blockedHouseIds.where(town.housesById.containsKey).toSet();
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

    Map<int, _Candidate> solveSubtree(String houseId) {
      final house = town.housesById[houseId]!;
      final acquired = _Candidate(
        addedCapacity: 0,
        incrementalCp: house.contributionPoints,
        selectedHouseIds: const <String>{},
        newlyRequiredHouseIds: <String>{houseId},
      );
      var options = <int, _Candidate>{0: acquired};
      if (house.isLodging && !blocked.contains(houseId)) {
        final selected = acquired.withSelected(houseId, house.lodgingSpaces);
        options[_capacityKey(selected.addedCapacity, additionalRequired)] =
            selected;
      }
      for (final childId in children[houseId] ?? const <String>[]) {
        options = _mergeOptions(options, <int, _Candidate>{
          0: _Candidate.empty,
          ...solveSubtree(childId),
        }, additionalRequired);
      }
      return <int, _Candidate>{...options, 0: _Candidate.empty};
    }

    var portfolio = <int, _Candidate>{0: _Candidate.empty};
    for (final rootId in roots) {
      portfolio = _mergeOptions(
        portfolio,
        solveSubtree(rootId),
        additionalRequired,
      );
    }

    final isFeasible = portfolio.containsKey(additionalRequired);
    final candidate = isFeasible
        ? portfolio[additionalRequired]!
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

    return LodgingPlan(
      townNodeId: town.townNodeId,
      requiredCapacity: requiredCapacity,
      existingCapacity: existingCapacity,
      addedCapacity: candidate.addedCapacity,
      incrementalContributionPoints: candidate.incrementalCp,
      isFeasible: isFeasible,
      selectedLodgingHouseIds: candidate.selectedHouseIds,
      prerequisiteHouseIds: prerequisites,
      fullHouseClosureIds: fullClosure,
      newlyRequiredHouseIds: candidate.newlyRequiredHouseIds,
      ownedHouseIdsUsed: ownedUsed,
    );
  }
}

Map<int, _Candidate> _mergeOptions(
  Map<int, _Candidate> left,
  Map<int, _Candidate> right,
  int capacityTarget,
) {
  final merged = <int, _Candidate>{};
  for (final leftCandidate in left.values) {
    for (final rightCandidate in right.values) {
      final candidate = leftCandidate.combine(rightCandidate);
      final key = _capacityKey(candidate.addedCapacity, capacityTarget);
      final incumbent = merged[key];
      if (incumbent == null || _isBetter(candidate, incumbent)) {
        merged[key] = candidate;
      }
    }
  }
  return merged;
}

int _capacityKey(int capacity, int target) => capacity.clamp(0, target);

bool _isBetter(_Candidate candidate, _Candidate incumbent) {
  if (candidate.incrementalCp != incumbent.incrementalCp) {
    return candidate.incrementalCp < incumbent.incrementalCp;
  }
  if (candidate.addedCapacity != incumbent.addedCapacity) {
    return candidate.addedCapacity < incumbent.addedCapacity;
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

final class _Candidate {
  _Candidate({
    required this.addedCapacity,
    required this.incrementalCp,
    required Set<String> selectedHouseIds,
    required Set<String> newlyRequiredHouseIds,
  }) : selectedHouseIds = Set<String>.unmodifiable(selectedHouseIds),
       newlyRequiredHouseIds = Set<String>.unmodifiable(newlyRequiredHouseIds);

  static final empty = _Candidate(
    addedCapacity: 0,
    incrementalCp: 0,
    selectedHouseIds: const <String>{},
    newlyRequiredHouseIds: const <String>{},
  );

  final int addedCapacity;
  final int incrementalCp;
  final Set<String> selectedHouseIds;
  final Set<String> newlyRequiredHouseIds;

  _Candidate withSelected(String houseId, int capacity) {
    return _Candidate(
      addedCapacity: addedCapacity + capacity,
      incrementalCp: incrementalCp,
      selectedHouseIds: <String>{...selectedHouseIds, houseId},
      newlyRequiredHouseIds: newlyRequiredHouseIds,
    );
  }

  _Candidate combine(_Candidate other) {
    return _Candidate(
      addedCapacity: addedCapacity + other.addedCapacity,
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
