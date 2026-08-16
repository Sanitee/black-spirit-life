import 'worker_capacity_assessment.dart';
import '../model/map_visual_style.dart';
import '../royal_workshop/royal_workshop_models.dart';

/// Persisted user choices for the worker-node planner and map display.
///
/// A null [rootNodeIds] value means that every mapped zero-CP City and Town
/// may be used as a free starting point. An explicit set limits the optimizer
/// to the towns the user actually wants to dispatch workers from.
class BdoNodeNetworkPreferences {
  BdoNodeNetworkPreferences({
    this.contributionPointBudget = defaultContributionPointBudget,
    Map<String, int> desiredResourceNodeCounts = const <String, int>{},
    Set<String> currentNodeIds = const <String>{},
    Set<String> currentOwnedHouseIds = const <String>{},
    Map<String, int> currentHouseUsageTypeIds = const <String, int>{},
    Set<String>? rootNodeIds,
    double onlineHoursPerDay = defaultOnlineHoursPerDay,
    double resourceAvailabilityPercent = defaultResourceAvailabilityPercent,
    this.useObservedTradeVolume = defaultUseObservedTradeVolume,
    this.showCitiesAndTowns = defaultShowCitiesAndTowns,
    this.showGatewayHubs = defaultShowGatewayHubs,
    this.showAllMapNodes = defaultShowAllMapNodes,
    this.showAllNodeConnections = defaultShowAllNodeConnections,
    this.showWorkerOutputIcons = defaultShowWorkerOutputIcons,
    this.mapVisualStyle = BdoMapVisualStyle.vivid,
    Map<String, BdoTownWorkerCapacity> townWorkerCapacitiesByNodeId =
        const <String, BdoTownWorkerCapacity>{},
    BdoRoyalWorkshopPlan? royalWorkshopPlan,
  }) : desiredResourceNodeCounts = Map<String, int>.unmodifiable(
         _normalizedCounts(desiredResourceNodeCounts),
       ),
       currentNodeIds = Set<String>.unmodifiable(
         _normalizedIds(currentNodeIds),
       ),
       currentOwnedHouseIds = Set<String>.unmodifiable(
         _normalizedIds(currentOwnedHouseIds),
       ),
       currentHouseUsageTypeIds = Map<String, int>.unmodifiable(
         _normalizedHouseUsages(
           currentHouseUsageTypeIds,
           _normalizedIds(currentOwnedHouseIds),
         ),
       ),
       rootNodeIds = rootNodeIds == null
           ? null
           : Set<String>.unmodifiable(_normalizedIds(rootNodeIds)),
       onlineHoursPerDay = _normalizedOnlineHoursPerDay(onlineHoursPerDay),
       resourceAvailabilityPercent = _normalizedResourceAvailabilityPercent(
         resourceAvailabilityPercent,
       ),
       townWorkerCapacitiesByNodeId =
           Map<String, BdoTownWorkerCapacity>.unmodifiable(
             _normalizedTownWorkerCapacities(townWorkerCapacitiesByNodeId),
           ),
       royalWorkshopPlan = royalWorkshopPlan ?? BdoRoyalWorkshopPlan();

  static const int schemaVersion = 10;
  static const int defaultContributionPointBudget = 400;
  static const double defaultOnlineHoursPerDay = 8;
  static const double defaultResourceAvailabilityPercent = 100;
  static const bool defaultUseObservedTradeVolume = false;
  static const bool defaultShowCitiesAndTowns = true;
  static const bool defaultShowGatewayHubs = true;
  static const bool defaultShowAllMapNodes = true;
  static const bool defaultShowAllNodeConnections = true;
  static const bool defaultShowWorkerOutputIcons = true;

  final int contributionPointBudget;

  /// Desired number of distinct production nodes for each canonical resource.
  final Map<String, int> desiredResourceNodeCounts;

  /// The node IDs the user has confirmed as active in game.
  final Set<String> currentNodeIds;

  /// House IDs the user has confirmed as already invested in.
  ///
  /// This lets lodging recommendations calculate only the additional CP and
  /// prerequisite houses required for the proposed worker setup.
  final Set<String> currentOwnedHouseIds;

  /// The active in-game usage selected for an owned house.
  ///
  /// Owning a house is enough to satisfy a prerequisite chain, but it only
  /// contributes lodging capacity when its selected usage is Lodging
  /// (Workerman usage type 1). Keeping ownership and usage separate prevents
  /// storage, stable, and workshop houses from being counted as worker slots.
  final Map<String, int> currentHouseUsageTypeIds;

  /// Null uses every zero-CP City and Town in the dataset as a root.
  final Set<String>? rootNodeIds;

  /// Online worker time used for daily and weekly income estimates.
  ///
  /// Invalid values are normalized to [defaultOnlineHoursPerDay].
  final double onlineHoursPerDay;

  /// The Resource Amount setting applied to workload estimates.
  ///
  /// This is always finite and between 0 and 100 inclusive. Invalid values
  /// are normalized to [defaultResourceAvailabilityPercent].
  final double resourceAvailabilityPercent;

  /// Whether sufficiently observed trade volume may cap optimistic income.
  final bool useObservedTradeVolume;

  /// Whether city and town landmarks are visible on the map.
  final bool showCitiesAndTowns;

  /// Whether gateway-hub landmarks are visible on the map.
  final bool showGatewayHubs;

  /// Whether the complete map-node orientation layer is visible.
  final bool showAllMapNodes;

  /// Whether the complete neutral node-connection layer is visible.
  final bool showAllNodeConnections;

  /// Whether item artwork is shown above worker production nodes.
  final bool showWorkerOutputIcons;

  /// The player's preferred treatment for the existing basemap tiles.
  ///
  /// New profiles default to the vivid treatment. An explicitly saved
  /// [BdoMapVisualStyle.standard] choice remains distinct from an absent key
  /// and therefore survives application restarts.
  final BdoMapVisualStyle mapVisualStyle;

  /// Current worker setup entered for verified worker-hiring towns.
  ///
  /// The map is keyed by map node ID. Verification against the current
  /// worker-economics dataset remains the caller's responsibility so a future
  /// dataset can stop recognizing an old saved town without losing its entry.
  /// Legacy entries retain their free-worker and empty-slot values. New
  /// entries also retain hired-worker and bonus-lodging inputs so callers can
  /// combine them with current town and housing data. Counts are normalized to
  /// non-negative values.
  final Map<String, BdoTownWorkerCapacity> townWorkerCapacitiesByNodeId;

  /// The player's distinct Seoul Royal Workshop setup.
  ///
  /// This is not treated as an ordinary production-node selection because it
  /// has its own 5 CP access investment, daily rolls, and Yukjo-only workers.
  final BdoRoyalWorkshopPlan royalWorkshopPlan;

  bool get isDefault =>
      contributionPointBudget == defaultContributionPointBudget &&
      desiredResourceNodeCounts.isEmpty &&
      currentNodeIds.isEmpty &&
      currentOwnedHouseIds.isEmpty &&
      currentHouseUsageTypeIds.isEmpty &&
      rootNodeIds == null &&
      onlineHoursPerDay == defaultOnlineHoursPerDay &&
      resourceAvailabilityPercent == defaultResourceAvailabilityPercent &&
      useObservedTradeVolume == defaultUseObservedTradeVolume &&
      showCitiesAndTowns == defaultShowCitiesAndTowns &&
      showGatewayHubs == defaultShowGatewayHubs &&
      showAllMapNodes == defaultShowAllMapNodes &&
      showAllNodeConnections == defaultShowAllNodeConnections &&
      showWorkerOutputIcons == defaultShowWorkerOutputIcons &&
      mapVisualStyle == BdoMapVisualStyle.vivid &&
      townWorkerCapacitiesByNodeId.isEmpty &&
      royalWorkshopPlan.sameValuesAs(BdoRoyalWorkshopPlan());

  BdoNodeNetworkPreferences copyWith({
    int? contributionPointBudget,
    Map<String, int>? desiredResourceNodeCounts,
    Set<String>? currentNodeIds,
    Set<String>? currentOwnedHouseIds,
    Map<String, int>? currentHouseUsageTypeIds,
    Set<String>? rootNodeIds,
    bool useDefaultRootNodes = false,
    double? onlineHoursPerDay,
    double? resourceAvailabilityPercent,
    bool? useObservedTradeVolume,
    bool? showCitiesAndTowns,
    bool? showGatewayHubs,
    bool? showAllMapNodes,
    bool? showAllNodeConnections,
    bool? showWorkerOutputIcons,
    BdoMapVisualStyle? mapVisualStyle,
    Map<String, BdoTownWorkerCapacity>? townWorkerCapacitiesByNodeId,
    BdoRoyalWorkshopPlan? royalWorkshopPlan,
  }) {
    return BdoNodeNetworkPreferences(
      contributionPointBudget:
          contributionPointBudget ?? this.contributionPointBudget,
      desiredResourceNodeCounts:
          desiredResourceNodeCounts ?? this.desiredResourceNodeCounts,
      currentNodeIds: currentNodeIds ?? this.currentNodeIds,
      currentOwnedHouseIds: currentOwnedHouseIds ?? this.currentOwnedHouseIds,
      currentHouseUsageTypeIds:
          currentHouseUsageTypeIds ?? this.currentHouseUsageTypeIds,
      rootNodeIds: useDefaultRootNodes ? null : rootNodeIds ?? this.rootNodeIds,
      onlineHoursPerDay: onlineHoursPerDay ?? this.onlineHoursPerDay,
      resourceAvailabilityPercent:
          resourceAvailabilityPercent ?? this.resourceAvailabilityPercent,
      useObservedTradeVolume:
          useObservedTradeVolume ?? this.useObservedTradeVolume,
      showCitiesAndTowns: showCitiesAndTowns ?? this.showCitiesAndTowns,
      showGatewayHubs: showGatewayHubs ?? this.showGatewayHubs,
      showAllMapNodes: showAllMapNodes ?? this.showAllMapNodes,
      showAllNodeConnections:
          showAllNodeConnections ?? this.showAllNodeConnections,
      showWorkerOutputIcons:
          showWorkerOutputIcons ?? this.showWorkerOutputIcons,
      mapVisualStyle: mapVisualStyle ?? this.mapVisualStyle,
      townWorkerCapacitiesByNodeId:
          townWorkerCapacitiesByNodeId ?? this.townWorkerCapacitiesByNodeId,
      royalWorkshopPlan: royalWorkshopPlan ?? this.royalWorkshopPlan,
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'schemaVersion': schemaVersion,
    'contributionPointBudget': contributionPointBudget,
    'onlineHoursPerDay': onlineHoursPerDay,
    'resourceAvailabilityPercent': resourceAvailabilityPercent,
    'useObservedTradeVolume': useObservedTradeVolume,
    if (!showCitiesAndTowns) 'showCitiesAndTowns': false,
    if (!showGatewayHubs) 'showGatewayHubs': false,
    if (!showAllMapNodes) 'showAllMapNodes': false,
    if (!showAllNodeConnections) 'showAllNodeConnections': false,
    if (!showWorkerOutputIcons) 'showWorkerOutputIcons': false,
    if (mapVisualStyle != BdoMapVisualStyle.vivid)
      'mapVisualStyle': mapVisualStyle.name,
    if (desiredResourceNodeCounts.isNotEmpty)
      'desiredResourceNodeCounts': <String, int>{
        for (final id in desiredResourceNodeCounts.keys.toList()..sort())
          id: desiredResourceNodeCounts[id]!,
      },
    if (currentNodeIds.isNotEmpty)
      'currentNodeIds': currentNodeIds.toList()..sort(_compareNodeIds),
    if (currentOwnedHouseIds.isNotEmpty)
      'currentOwnedHouseIds': currentOwnedHouseIds.toList()
        ..sort(_compareNodeIds),
    if (currentHouseUsageTypeIds.isNotEmpty)
      'currentHouseUsageTypeIds': <String, int>{
        for (final id
            in currentHouseUsageTypeIds.keys.toList()..sort(_compareNodeIds))
          id: currentHouseUsageTypeIds[id]!,
      },
    if (rootNodeIds case final ids?)
      'rootNodeIds': ids.toList()..sort(_compareNodeIds),
    if (townWorkerCapacitiesByNodeId.isNotEmpty)
      'townWorkerCapacitiesByNodeId': <String, Object?>{
        for (final id
            in townWorkerCapacitiesByNodeId.keys.toList()
              ..sort(_compareNodeIds))
          id: <String, int>{
            'availableWorkerCount':
                townWorkerCapacitiesByNodeId[id]!.availableWorkerCount,
            'freeLodgingSlotCount':
                townWorkerCapacitiesByNodeId[id]!.freeLodgingSlotCount,
            'hiredWorkerCount':
                ?townWorkerCapacitiesByNodeId[id]!.hiredWorkerCount,
            'bonusLodgingSlotCount':
                ?townWorkerCapacitiesByNodeId[id]!.bonusLodgingSlotCount,
            'pearlLodgingPurchasedCount':
                ?townWorkerCapacitiesByNodeId[id]!.pearlLodgingPurchasedCount,
            'loyaltyLodgingPurchasedCount':
                ?townWorkerCapacitiesByNodeId[id]!.loyaltyLodgingPurchasedCount,
            'otherBonusLodgingSlotCount':
                ?townWorkerCapacitiesByNodeId[id]!.otherBonusLodgingSlotCount,
          },
      },
    if (!royalWorkshopPlan.sameValuesAs(BdoRoyalWorkshopPlan()))
      'royalWorkshopPlan': royalWorkshopPlan.toJson(),
  };

  factory BdoNodeNetworkPreferences.fromJson(Object? json) {
    if (json is! Map) {
      return BdoNodeNetworkPreferences();
    }
    final budgetValue = json['contributionPointBudget'];
    final budget = budgetValue is num
        ? budgetValue.toInt()
        : int.tryParse('$budgetValue');
    final rawCounts = json['desiredResourceNodeCounts'];
    final counts = <String, int>{};
    if (rawCounts is Map) {
      for (final entry in rawCounts.entries) {
        final id = entry.key.toString().trim();
        final value = entry.value;
        final count = value is num ? value.toInt() : int.tryParse('$value');
        if (id.isNotEmpty && count != null && count > 0) {
          counts[id] = count;
        }
      }
    }
    final rawTownCapacities = json['townWorkerCapacitiesByNodeId'];
    final townCapacities = <String, BdoTownWorkerCapacity>{};
    if (rawTownCapacities is Map) {
      for (final entry in rawTownCapacities.entries) {
        final id = entry.key.toString().trim();
        final rawCapacity = entry.value;
        if (id.isEmpty || rawCapacity is! Map) continue;
        townCapacities[id] = BdoTownWorkerCapacity(
          availableWorkerCount:
              _nonNegativeIntFromJson(rawCapacity['availableWorkerCount']) ?? 0,
          freeLodgingSlotCount:
              _nonNegativeIntFromJson(rawCapacity['freeLodgingSlotCount']) ?? 0,
          hiredWorkerCount: rawCapacity.containsKey('hiredWorkerCount')
              ? _nonNegativeIntFromJson(rawCapacity['hiredWorkerCount']) ?? 0
              : null,
          bonusLodgingSlotCount:
              rawCapacity.containsKey('bonusLodgingSlotCount')
              ? _nonNegativeIntFromJson(rawCapacity['bonusLodgingSlotCount']) ??
                    0
              : null,
          pearlLodgingPurchasedCount:
              rawCapacity.containsKey('pearlLodgingPurchasedCount')
              ? _nonNegativeIntFromJson(
                      rawCapacity['pearlLodgingPurchasedCount'],
                    ) ??
                    0
              : null,
          loyaltyLodgingPurchasedCount:
              rawCapacity.containsKey('loyaltyLodgingPurchasedCount')
              ? _nonNegativeIntFromJson(
                      rawCapacity['loyaltyLodgingPurchasedCount'],
                    ) ??
                    0
              : null,
          otherBonusLodgingSlotCount:
              rawCapacity.containsKey('otherBonusLodgingSlotCount')
              ? _nonNegativeIntFromJson(
                      rawCapacity['otherBonusLodgingSlotCount'],
                    ) ??
                    0
              : null,
        );
      }
    }
    final rawHouseUsages = json['currentHouseUsageTypeIds'];
    final houseUsages = <String, int>{};
    if (rawHouseUsages is Map) {
      for (final entry in rawHouseUsages.entries) {
        final id = entry.key.toString().trim();
        final rawTypeId = entry.value;
        final typeId = rawTypeId is num
            ? rawTypeId.toInt()
            : int.tryParse('$rawTypeId');
        if (id.isNotEmpty && typeId != null && typeId >= 0) {
          houseUsages[id] = typeId;
        }
      }
    }
    return BdoNodeNetworkPreferences(
      contributionPointBudget: budget != null && budget >= 0
          ? budget
          : defaultContributionPointBudget,
      desiredResourceNodeCounts: counts,
      currentNodeIds: _idsFromJson(json['currentNodeIds']),
      currentOwnedHouseIds: _idsFromJson(json['currentOwnedHouseIds']),
      currentHouseUsageTypeIds: houseUsages,
      rootNodeIds: json.containsKey('rootNodeIds')
          ? _idsFromJson(json['rootNodeIds'])
          : null,
      onlineHoursPerDay:
          _finiteDoubleFromJson(json['onlineHoursPerDay']) ??
          defaultOnlineHoursPerDay,
      resourceAvailabilityPercent:
          _finiteDoubleFromJson(json['resourceAvailabilityPercent']) ??
          defaultResourceAvailabilityPercent,
      useObservedTradeVolume: json['useObservedTradeVolume'] is bool
          ? json['useObservedTradeVolume'] as bool
          : defaultUseObservedTradeVolume,
      showCitiesAndTowns: _boolFromJson(
        json,
        'showCitiesAndTowns',
        defaultValue: defaultShowCitiesAndTowns,
      ),
      showGatewayHubs: _boolFromJson(
        json,
        'showGatewayHubs',
        defaultValue: defaultShowGatewayHubs,
      ),
      showAllMapNodes: _boolFromJson(
        json,
        'showAllMapNodes',
        defaultValue: defaultShowAllMapNodes,
      ),
      showAllNodeConnections: _boolFromJson(
        json,
        'showAllNodeConnections',
        defaultValue: defaultShowAllNodeConnections,
      ),
      showWorkerOutputIcons: _boolFromJson(
        json,
        'showWorkerOutputIcons',
        defaultValue: defaultShowWorkerOutputIcons,
      ),
      mapVisualStyle: json.containsKey('mapVisualStyle')
          ? BdoMapVisualStyle.fromJson(json['mapVisualStyle'])
          : BdoMapVisualStyle.vivid,
      townWorkerCapacitiesByNodeId: townCapacities,
      royalWorkshopPlan: BdoRoyalWorkshopPlan.fromJson(
        json['royalWorkshopPlan'],
      ),
    );
  }

  bool sameValuesAs(BdoNodeNetworkPreferences other) {
    return contributionPointBudget == other.contributionPointBudget &&
        _mapsEqual(
          desiredResourceNodeCounts,
          other.desiredResourceNodeCounts,
        ) &&
        _setsEqual(currentNodeIds, other.currentNodeIds) &&
        _setsEqual(currentOwnedHouseIds, other.currentOwnedHouseIds) &&
        _mapsEqual(currentHouseUsageTypeIds, other.currentHouseUsageTypeIds) &&
        _nullableSetsEqual(rootNodeIds, other.rootNodeIds) &&
        onlineHoursPerDay == other.onlineHoursPerDay &&
        resourceAvailabilityPercent == other.resourceAvailabilityPercent &&
        useObservedTradeVolume == other.useObservedTradeVolume &&
        showCitiesAndTowns == other.showCitiesAndTowns &&
        showGatewayHubs == other.showGatewayHubs &&
        showAllMapNodes == other.showAllMapNodes &&
        showAllNodeConnections == other.showAllNodeConnections &&
        showWorkerOutputIcons == other.showWorkerOutputIcons &&
        mapVisualStyle == other.mapVisualStyle &&
        _townCapacityMapsEqual(
          townWorkerCapacitiesByNodeId,
          other.townWorkerCapacitiesByNodeId,
        ) &&
        royalWorkshopPlan.sameValuesAs(other.royalWorkshopPlan);
  }
}

bool _boolFromJson(
  Map<dynamic, dynamic> json,
  String key, {
  required bool defaultValue,
}) {
  final value = json[key];
  return value is bool ? value : defaultValue;
}

Map<String, int> _normalizedCounts(Map<String, int> values) {
  final normalized = <String, int>{};
  for (final entry in values.entries) {
    final id = entry.key.trim();
    if (id.isNotEmpty && entry.value > 0) {
      normalized[id] = entry.value;
    }
  }
  return normalized;
}

Set<String> _normalizedIds(Iterable<String> values) => <String>{
  for (final value in values)
    if (value.trim().isNotEmpty) value.trim(),
};

Map<String, int> _normalizedHouseUsages(
  Map<String, int> values,
  Set<String> ownedHouseIds,
) {
  final normalized = <String, int>{};
  for (final entry in values.entries) {
    final id = entry.key.trim();
    if (id.isNotEmpty && ownedHouseIds.contains(id) && entry.value >= 0) {
      normalized[id] = entry.value;
    }
  }
  return normalized;
}

Set<String> _idsFromJson(Object? value) {
  if (value is! Iterable || value is String) {
    return const <String>{};
  }
  return _normalizedIds(value.map((entry) => entry.toString()));
}

Map<String, BdoTownWorkerCapacity> _normalizedTownWorkerCapacities(
  Map<String, BdoTownWorkerCapacity> values,
) {
  final normalized = <String, BdoTownWorkerCapacity>{};
  for (final entry in values.entries) {
    final id = entry.key.trim();
    if (id.isEmpty) continue;
    normalized[id] = BdoTownWorkerCapacity(
      availableWorkerCount: entry.value.availableWorkerCount < 0
          ? 0
          : entry.value.availableWorkerCount,
      freeLodgingSlotCount: entry.value.freeLodgingSlotCount < 0
          ? 0
          : entry.value.freeLodgingSlotCount,
      hiredWorkerCount: entry.value.hiredWorkerCount == null
          ? null
          : entry.value.hiredWorkerCount! < 0
          ? 0
          : entry.value.hiredWorkerCount,
      bonusLodgingSlotCount: entry.value.bonusLodgingSlotCount == null
          ? null
          : entry.value.bonusLodgingSlotCount! < 0
          ? 0
          : entry.value.bonusLodgingSlotCount,
      pearlLodgingPurchasedCount: entry.value.pearlLodgingPurchasedCount == null
          ? null
          : entry.value.pearlLodgingPurchasedCount! < 0
          ? 0
          : entry.value.pearlLodgingPurchasedCount,
      loyaltyLodgingPurchasedCount:
          entry.value.loyaltyLodgingPurchasedCount == null
          ? null
          : entry.value.loyaltyLodgingPurchasedCount! < 0
          ? 0
          : entry.value.loyaltyLodgingPurchasedCount,
      otherBonusLodgingSlotCount: entry.value.otherBonusLodgingSlotCount == null
          ? null
          : entry.value.otherBonusLodgingSlotCount! < 0
          ? 0
          : entry.value.otherBonusLodgingSlotCount,
    );
  }
  return normalized;
}

double _normalizedOnlineHoursPerDay(double value) =>
    value.isFinite && value > 0 && value <= 24
    ? value
    : BdoNodeNetworkPreferences.defaultOnlineHoursPerDay;

double _normalizedResourceAvailabilityPercent(double value) =>
    value.isFinite && value >= 0 && value <= 100
    ? (value == 0 ? 0 : value)
    : BdoNodeNetworkPreferences.defaultResourceAvailabilityPercent;

double? _finiteDoubleFromJson(Object? value) {
  final parsed = value is num ? value.toDouble() : double.tryParse('$value');
  return parsed != null && parsed.isFinite ? parsed : null;
}

int? _nonNegativeIntFromJson(Object? value) {
  if (value is int) return value >= 0 ? value : null;
  if (value is num) {
    if (!value.isFinite) return null;
    final parsed = value.toInt();
    return value == parsed && parsed >= 0 ? parsed : null;
  }
  final parsed = int.tryParse('$value');
  return parsed != null && parsed >= 0 ? parsed : null;
}

bool _mapsEqual(Map<String, int> left, Map<String, int> right) {
  if (left.length != right.length) return false;
  for (final entry in left.entries) {
    if (right[entry.key] != entry.value) return false;
  }
  return true;
}

bool _setsEqual(Set<String> left, Set<String> right) =>
    left.length == right.length && left.containsAll(right);

bool _nullableSetsEqual(Set<String>? left, Set<String>? right) =>
    identical(left, right) ||
    (left != null && right != null && _setsEqual(left, right));

bool _townCapacityMapsEqual(
  Map<String, BdoTownWorkerCapacity> left,
  Map<String, BdoTownWorkerCapacity> right,
) {
  if (left.length != right.length) return false;
  for (final entry in left.entries) {
    final other = right[entry.key];
    if (other == null ||
        entry.value.availableWorkerCount != other.availableWorkerCount ||
        entry.value.freeLodgingSlotCount != other.freeLodgingSlotCount ||
        entry.value.hiredWorkerCount != other.hiredWorkerCount ||
        entry.value.bonusLodgingSlotCount != other.bonusLodgingSlotCount ||
        entry.value.pearlLodgingPurchasedCount !=
            other.pearlLodgingPurchasedCount ||
        entry.value.loyaltyLodgingPurchasedCount !=
            other.loyaltyLodgingPurchasedCount ||
        entry.value.otherBonusLodgingSlotCount !=
            other.otherBonusLodgingSlotCount) {
      return false;
    }
  }
  return true;
}

int _compareNodeIds(String left, String right) {
  final leftNumber = int.tryParse(left);
  final rightNumber = int.tryParse(right);
  if (leftNumber != null && rightNumber != null) {
    final byNumber = leftNumber.compareTo(rightNumber);
    if (byNumber != 0) return byNumber;
  }
  return left.compareTo(right);
}
