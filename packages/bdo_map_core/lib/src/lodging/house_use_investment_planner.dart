import 'dart:math' as math;

import 'lodging_data.dart';

/// An exact, minimum-incremental-CP plan for adding one house-use type.
///
/// [selectedUseHouseIds] contains only newly acquired houses that can be set to
/// the exact requested [usageTypeId] at [minimumLevel] or higher. Existing
/// houses never satisfy the requested *additional* facility count and are
/// never silently converted; they can only satisfy prerequisites at zero
/// incremental CP.
final class HouseUseInvestmentPlan {
  HouseUseInvestmentPlan({
    required this.townNodeId,
    required this.usageTypeId,
    required this.minimumLevel,
    required this.requestedAdditionalFacilityCount,
    required this.selectedFacilityCount,
    required this.selectedCapability,
    required this.incrementalContributionPoints,
    required this.isFeasible,
    required Iterable<String> selectedUseHouseIds,
    required Iterable<String> newPrerequisiteHouseIds,
    required Iterable<String> fullHouseClosureIds,
    required Iterable<String> newlyRequiredHouseIds,
    required Iterable<String> ownedPrerequisiteHouseIds,
    required Iterable<String> protectedOwnedHouseIds,
    required Iterable<String> unknownUseOwnedHouseIds,
  }) : selectedUseHouseIds = _sortedHouseIds(selectedUseHouseIds),
       newPrerequisiteHouseIds = _sortedHouseIds(newPrerequisiteHouseIds),
       fullHouseClosureIds = _sortedHouseIds(fullHouseClosureIds),
       newlyRequiredHouseIds = _sortedHouseIds(newlyRequiredHouseIds),
       ownedPrerequisiteHouseIds = _sortedHouseIds(ownedPrerequisiteHouseIds),
       protectedOwnedHouseIds = _sortedHouseIds(protectedOwnedHouseIds),
       unknownUseOwnedHouseIds = _sortedHouseIds(unknownUseOwnedHouseIds);

  final String townNodeId;
  final int usageTypeId;
  final int minimumLevel;
  final int requestedAdditionalFacilityCount;
  final int selectedFacilityCount;

  /// Sum of the requested usage levels on [selectedUseHouseIds].
  ///
  /// This is used only after CP and newly required house count when resolving
  /// equally cheap plans. It does not cause a house with the wrong type id to
  /// match, even when that house has the same display label.
  final int selectedCapability;

  final int incrementalContributionPoints;
  final bool isFeasible;
  final List<String> selectedUseHouseIds;

  /// Newly acquired houses used only to unlock a selected facility.
  final List<String> newPrerequisiteHouseIds;

  /// Selected facilities and every house on their prerequisite paths.
  final List<String> fullHouseClosureIds;

  /// Every unowned house in [fullHouseClosureIds], targets included.
  final List<String> newlyRequiredHouseIds;

  /// Already owned houses encountered on selected prerequisite paths.
  final List<String> ownedPrerequisiteHouseIds;

  /// All recognized owned houses in this town, none of which may be converted.
  final List<String> protectedOwnedHouseIds;

  /// Protected owned houses for which the caller has not saved an active use.
  final List<String> unknownUseOwnedHouseIds;

  int get facilityShortfall =>
      math.max(0, requestedAdditionalFacilityCount - selectedFacilityCount);
}

/// Finds an exact cheapest prerequisite-closed portfolio for a house use.
///
/// A facility matches by numeric [usageTypeId], never by its display label.
/// Plans are ordered deterministically by incremental CP, fewer newly required
/// houses, greater summed usage level, and finally stable house id.
abstract final class HouseUseInvestmentPlanner {
  static HouseUseInvestmentPlan solve({
    required LodgingTown town,
    required int usageTypeId,
    int minimumLevel = 1,
    required int requestedAdditionalFacilityCount,
    Set<String> currentOwnedHouseIds = const <String>{},
    Map<String, int> currentHouseUsageTypeIds = const <String, int>{},
  }) {
    if (usageTypeId < 0) {
      throw ArgumentError.value(
        usageTypeId,
        'usageTypeId',
        'House usage type ids cannot be negative.',
      );
    }
    if (minimumLevel <= 0) {
      throw ArgumentError.value(
        minimumLevel,
        'minimumLevel',
        'The minimum facility level must be positive.',
      );
    }
    if (requestedAdditionalFacilityCount < 0) {
      throw ArgumentError.value(
        requestedAdditionalFacilityCount,
        'requestedAdditionalFacilityCount',
        'The requested additional facility count cannot be negative.',
      );
    }

    final ownedHouseIds = currentOwnedHouseIds
        .where(town.housesById.containsKey)
        .toSet();
    final unknownUseOwnedHouseIds = ownedHouseIds
        .where((houseId) => !currentHouseUsageTypeIds.containsKey(houseId))
        .toSet();

    if (requestedAdditionalFacilityCount == 0) {
      return _createPlan(
        town: town,
        usageTypeId: usageTypeId,
        minimumLevel: minimumLevel,
        requestedAdditionalFacilityCount: 0,
        candidate: _HouseUseCandidate.empty,
        isFeasible: true,
        ownedHouseIds: ownedHouseIds,
        unknownUseOwnedHouseIds: unknownUseOwnedHouseIds,
      );
    }

    final eligibleNewHouseCount = town.houses.where((house) {
      final usage = house.usagesByTypeId[usageTypeId];
      return !ownedHouseIds.contains(house.id) &&
          usage != null &&
          usage.level >= minimumLevel;
    }).length;
    final facilityLimit = math.min(
      requestedAdditionalFacilityCount,
      eligibleNewHouseCount,
    );

    final childrenByHouseId = <String, List<String>>{};
    final rootHouseIds = <String>[];
    for (final house in town.houses) {
      final prerequisiteId = house.prerequisiteHouseId;
      if (prerequisiteId == null) {
        rootHouseIds.add(house.id);
      } else {
        childrenByHouseId
            .putIfAbsent(prerequisiteId, () => <String>[])
            .add(house.id);
      }
    }
    rootHouseIds.sort(_compareHouseIds);
    for (final children in childrenByHouseId.values) {
      children.sort(_compareHouseIds);
    }

    Map<int, _HouseUseCandidate> solveSubtree(String houseId) {
      final house = town.housesById[houseId]!;
      final isOwned = ownedHouseIds.contains(houseId);
      final acquired = _HouseUseCandidate(
        selectedFacilityCount: 0,
        selectedCapability: 0,
        incrementalContributionPoints: isOwned ? 0 : house.contributionPoints,
        selectedUseHouseIds: const <String>{},
        fullHouseClosureIds: <String>{houseId},
        newlyRequiredHouseIds: isOwned ? const <String>{} : <String>{houseId},
      );
      var options = <int, _HouseUseCandidate>{0: acquired};
      final usage = house.usagesByTypeId[usageTypeId];
      if (!isOwned && usage != null && usage.level >= minimumLevel) {
        final selected = acquired.withSelected(houseId, usage.level);
        options[1] = selected;
      }

      for (final childId in childrenByHouseId[houseId] ?? const <String>[]) {
        options = _mergeOptions(options, <int, _HouseUseCandidate>{
          0: _HouseUseCandidate.empty,
          ...solveSubtree(childId),
        }, facilityLimit);
      }
      return <int, _HouseUseCandidate>{...options, 0: _HouseUseCandidate.empty};
    }

    var portfolio = <int, _HouseUseCandidate>{0: _HouseUseCandidate.empty};
    for (final rootId in rootHouseIds) {
      portfolio = _mergeOptions(portfolio, solveSubtree(rootId), facilityLimit);
    }

    final isFeasible =
        requestedAdditionalFacilityCount <= eligibleNewHouseCount &&
        portfolio.containsKey(requestedAdditionalFacilityCount);
    final candidate = isFeasible
        ? portfolio[requestedAdditionalFacilityCount]!
        : portfolio.entries.reduce((left, right) {
            if (left.key != right.key) {
              return left.key > right.key ? left : right;
            }
            return _isBetterCandidate(left.value, right.value) ? left : right;
          }).value;

    return _createPlan(
      town: town,
      usageTypeId: usageTypeId,
      minimumLevel: minimumLevel,
      requestedAdditionalFacilityCount: requestedAdditionalFacilityCount,
      candidate: candidate,
      isFeasible: isFeasible,
      ownedHouseIds: ownedHouseIds,
      unknownUseOwnedHouseIds: unknownUseOwnedHouseIds,
    );
  }
}

HouseUseInvestmentPlan _createPlan({
  required LodgingTown town,
  required int usageTypeId,
  required int minimumLevel,
  required int requestedAdditionalFacilityCount,
  required _HouseUseCandidate candidate,
  required bool isFeasible,
  required Set<String> ownedHouseIds,
  required Set<String> unknownUseOwnedHouseIds,
}) {
  final prerequisiteHouseIds = <String>{...candidate.fullHouseClosureIds}
    ..removeAll(candidate.selectedUseHouseIds);
  return HouseUseInvestmentPlan(
    townNodeId: town.townNodeId,
    usageTypeId: usageTypeId,
    minimumLevel: minimumLevel,
    requestedAdditionalFacilityCount: requestedAdditionalFacilityCount,
    selectedFacilityCount: candidate.selectedFacilityCount,
    selectedCapability: candidate.selectedCapability,
    incrementalContributionPoints: candidate.incrementalContributionPoints,
    isFeasible: isFeasible,
    selectedUseHouseIds: candidate.selectedUseHouseIds,
    newPrerequisiteHouseIds: prerequisiteHouseIds.difference(ownedHouseIds),
    fullHouseClosureIds: candidate.fullHouseClosureIds,
    newlyRequiredHouseIds: candidate.newlyRequiredHouseIds,
    ownedPrerequisiteHouseIds: prerequisiteHouseIds.intersection(ownedHouseIds),
    protectedOwnedHouseIds: ownedHouseIds,
    unknownUseOwnedHouseIds: unknownUseOwnedHouseIds,
  );
}

Map<int, _HouseUseCandidate> _mergeOptions(
  Map<int, _HouseUseCandidate> left,
  Map<int, _HouseUseCandidate> right,
  int facilityLimit,
) {
  final merged = <int, _HouseUseCandidate>{};
  for (final leftCandidate in left.values) {
    for (final rightCandidate in right.values) {
      final candidate = leftCandidate.combine(rightCandidate);
      if (candidate.selectedFacilityCount > facilityLimit) continue;
      final incumbent = merged[candidate.selectedFacilityCount];
      if (incumbent == null || _isBetterCandidate(candidate, incumbent)) {
        merged[candidate.selectedFacilityCount] = candidate;
      }
    }
  }
  return merged;
}

bool _isBetterCandidate(
  _HouseUseCandidate candidate,
  _HouseUseCandidate incumbent,
) {
  if (candidate.incrementalContributionPoints !=
      incumbent.incrementalContributionPoints) {
    return candidate.incrementalContributionPoints <
        incumbent.incrementalContributionPoints;
  }
  if (candidate.newlyRequiredHouseIds.length !=
      incumbent.newlyRequiredHouseIds.length) {
    return candidate.newlyRequiredHouseIds.length <
        incumbent.newlyRequiredHouseIds.length;
  }
  if (candidate.selectedCapability != incumbent.selectedCapability) {
    return candidate.selectedCapability > incumbent.selectedCapability;
  }
  final selectedComparison = _compareHouseIdLists(
    candidate.selectedUseHouseIds,
    incumbent.selectedUseHouseIds,
  );
  if (selectedComparison != 0) return selectedComparison < 0;
  return _compareHouseIdLists(
        candidate.fullHouseClosureIds,
        incumbent.fullHouseClosureIds,
      ) <
      0;
}

final class _HouseUseCandidate {
  _HouseUseCandidate({
    required this.selectedFacilityCount,
    required this.selectedCapability,
    required this.incrementalContributionPoints,
    required Set<String> selectedUseHouseIds,
    required Set<String> fullHouseClosureIds,
    required Set<String> newlyRequiredHouseIds,
  }) : selectedUseHouseIds = Set<String>.unmodifiable(selectedUseHouseIds),
       fullHouseClosureIds = Set<String>.unmodifiable(fullHouseClosureIds),
       newlyRequiredHouseIds = Set<String>.unmodifiable(newlyRequiredHouseIds);

  static final empty = _HouseUseCandidate(
    selectedFacilityCount: 0,
    selectedCapability: 0,
    incrementalContributionPoints: 0,
    selectedUseHouseIds: const <String>{},
    fullHouseClosureIds: const <String>{},
    newlyRequiredHouseIds: const <String>{},
  );

  final int selectedFacilityCount;
  final int selectedCapability;
  final int incrementalContributionPoints;
  final Set<String> selectedUseHouseIds;
  final Set<String> fullHouseClosureIds;
  final Set<String> newlyRequiredHouseIds;

  _HouseUseCandidate withSelected(String houseId, int capability) {
    return _HouseUseCandidate(
      selectedFacilityCount: selectedFacilityCount + 1,
      selectedCapability: selectedCapability + capability,
      incrementalContributionPoints: incrementalContributionPoints,
      selectedUseHouseIds: <String>{...selectedUseHouseIds, houseId},
      fullHouseClosureIds: fullHouseClosureIds,
      newlyRequiredHouseIds: newlyRequiredHouseIds,
    );
  }

  _HouseUseCandidate combine(_HouseUseCandidate other) {
    return _HouseUseCandidate(
      selectedFacilityCount:
          selectedFacilityCount + other.selectedFacilityCount,
      selectedCapability: selectedCapability + other.selectedCapability,
      incrementalContributionPoints:
          incrementalContributionPoints + other.incrementalContributionPoints,
      selectedUseHouseIds: <String>{
        ...selectedUseHouseIds,
        ...other.selectedUseHouseIds,
      },
      fullHouseClosureIds: <String>{
        ...fullHouseClosureIds,
        ...other.fullHouseClosureIds,
      },
      newlyRequiredHouseIds: <String>{
        ...newlyRequiredHouseIds,
        ...other.newlyRequiredHouseIds,
      },
    );
  }
}

int _compareHouseIdLists(Iterable<String> left, Iterable<String> right) {
  final leftIds = _sortedHouseIds(left);
  final rightIds = _sortedHouseIds(right);
  final commonLength = math.min(leftIds.length, rightIds.length);
  for (var index = 0; index < commonLength; index += 1) {
    final comparison = _compareHouseIds(leftIds[index], rightIds[index]);
    if (comparison != 0) return comparison;
  }
  return leftIds.length.compareTo(rightIds.length);
}

List<String> _sortedHouseIds(Iterable<String> values) =>
    values.toSet().toList(growable: false)..sort(_compareHouseIds);

int _compareHouseIds(String left, String right) {
  final leftKey = int.tryParse(left.split(':').last);
  final rightKey = int.tryParse(right.split(':').last);
  if (leftKey != null && rightKey != null && leftKey != rightKey) {
    return leftKey.compareTo(rightKey);
  }
  return left.compareTo(right);
}
