import 'dart:convert';

import 'package:flutter/services.dart';

import '../model/resource_map_data.dart';

/// Provenance and assumptions attached to the bundled worker-income inputs.
final class BdoWorkerEconomicsManifest {
  BdoWorkerEconomicsManifest({
    required this.datasetVersion,
    required this.generatedAt,
    required this.sourceRepository,
    required this.sourceCommit,
    required this.sourcePackageVersion,
    required this.sourceLicenseExpression,
    required this.upstreamWorkermanCommit,
    required this.permittedUse,
    required Map<String, String> sourceSha256,
    required Iterable<String> assumptions,
  }) : sourceSha256 = Map<String, String>.unmodifiable(sourceSha256),
       assumptions = List<String>.unmodifiable(assumptions);

  final String datasetVersion;
  final DateTime generatedAt;
  final Uri sourceRepository;
  final String sourceCommit;
  final String sourcePackageVersion;
  final String sourceLicenseExpression;
  final String upstreamWorkermanCommit;
  final String permittedUse;
  final Map<String, String> sourceSha256;
  final List<String> assumptions;

  factory BdoWorkerEconomicsManifest.fromJson(Map<String, Object?> json) {
    return BdoWorkerEconomicsManifest(
      datasetVersion: _requiredString(json, 'datasetVersion'),
      generatedAt: DateTime.parse(_requiredString(json, 'generatedAt')).toUtc(),
      sourceRepository: Uri.parse(_requiredString(json, 'sourceRepository')),
      sourceCommit: _requiredString(json, 'sourceCommit'),
      sourcePackageVersion: _requiredString(json, 'sourcePackageVersion'),
      sourceLicenseExpression: _requiredString(json, 'sourceLicenseExpression'),
      upstreamWorkermanCommit: _requiredString(json, 'upstreamWorkermanCommit'),
      permittedUse: _requiredString(json, 'permittedUse'),
      sourceSha256: _stringMap(json['sourceSha256'], 'sourceSha256'),
      assumptions: _stringList(json['assumptions'], 'assumptions'),
    );
  }
}

/// A data-backed arithmetic estimate of one level-40 worker profile.
///
/// Skill bonuses are intentionally absent. The bundled manifest records that
/// limitation so presentation code can call the result an estimate.
final class BdoWorkerProfileEstimate {
  const BdoWorkerProfileEstimate({
    required this.id,
    required this.label,
    required this.workerType,
    required this.characterKey,
    required this.isGiant,
    required this.workSpeed,
    required this.movementSpeed,
    required this.luck,
  });

  final String id;
  final String label;
  final int workerType;
  final int characterKey;
  final bool isGiant;
  final double workSpeed;
  final double movementSpeed;
  final double luck;

  factory BdoWorkerProfileEstimate.fromJson(Map<String, Object?> json) {
    final profile = BdoWorkerProfileEstimate(
      id: _requiredString(json, 'id'),
      label: _requiredString(json, 'label'),
      workerType: _requiredInt(json, 'workerType'),
      characterKey: _requiredInt(json, 'characterKey'),
      isGiant: _requiredBool(json, 'isGiant'),
      workSpeed: _requiredDouble(json, 'workSpeed'),
      movementSpeed: _requiredDouble(json, 'movementSpeed'),
      luck: _requiredDouble(json, 'luck'),
    );
    if (profile.workSpeed <= 0 ||
        profile.movementSpeed <= 0 ||
        profile.luck < 0 ||
        profile.luck > 100) {
      throw FormatException('Invalid worker profile ${profile.id}.');
    }
    return profile;
  }
}

/// One verified town that can house and dispatch workers.
final class BdoWorkerTownEconomics {
  BdoWorkerTownEconomics({
    required this.nodeId,
    required this.regionId,
    required this.baseWorkerSlots,
    required Iterable<BdoWorkerProfileEstimate> profiles,
  }) : profiles = List<BdoWorkerProfileEstimate>.unmodifiable(profiles);

  final String nodeId;
  final int regionId;

  /// The source's base capacity before lodging, paid slots, or reservations.
  final int baseWorkerSlots;
  final List<BdoWorkerProfileEstimate> profiles;

  factory BdoWorkerTownEconomics.fromJson(Map<String, Object?> json) {
    final profiles = _objectList(
      json['profiles'],
      'profiles',
    ).map(BdoWorkerProfileEstimate.fromJson).toList(growable: false);
    final town = BdoWorkerTownEconomics(
      nodeId: _requiredString(json, 'nodeId'),
      regionId: _requiredInt(json, 'regionId'),
      baseWorkerSlots: _requiredInt(json, 'baseWorkerSlots'),
      profiles: profiles,
    );
    if (town.baseWorkerSlots < 0 || town.profiles.isEmpty) {
      throw FormatException('Invalid worker-town record ${town.nodeId}.');
    }
    return town;
  }
}

/// Workload, expected drops, and worker-town distance inputs for one site.
final class BdoWorkerProductionEconomics {
  BdoWorkerProductionEconomics({
    required this.nodeId,
    required this.baseWorkload,
    required Iterable<int> workerTypes,
    required Map<int, double> standardYields,
    required Map<int, double> giantYields,
    required Map<int, double> luckyBonusYields,
    required Map<String, double> townDistances,
  }) : workerTypes = Set<int>.unmodifiable(workerTypes),
       standardYields = Map<int, double>.unmodifiable(standardYields),
       giantYields = Map<int, double>.unmodifiable(giantYields),
       luckyBonusYields = Map<int, double>.unmodifiable(luckyBonusYields),
       townDistances = Map<String, double>.unmodifiable(townDistances);

  final String nodeId;
  final double baseWorkload;
  final Set<int> workerTypes;
  final Map<int, double> standardYields;
  final Map<int, double> giantYields;
  final Map<int, double> luckyBonusYields;

  /// Round-trip calculation distance is derived from this one-way value.
  final Map<String, double> townDistances;

  Set<int> get outputItemIds => <int>{
    ...standardYields.keys,
    ...giantYields.keys,
    ...luckyBonusYields.keys,
  };

  factory BdoWorkerProductionEconomics.fromJson(Map<String, Object?> json) {
    final node = BdoWorkerProductionEconomics(
      nodeId: _requiredString(json, 'nodeId'),
      baseWorkload: _requiredDouble(json, 'baseWorkload'),
      workerTypes: _intList(json['workerTypes'], 'workerTypes'),
      standardYields: _intDoubleMap(json['standardYields'], 'standardYields'),
      giantYields: _intDoubleMap(json['giantYields'], 'giantYields'),
      luckyBonusYields: _intDoubleMap(
        json['luckyBonusYields'],
        'luckyBonusYields',
      ),
      townDistances: _doubleMap(json['townDistances'], 'townDistances'),
    );
    if (node.baseWorkload <= 0 ||
        node.townDistances.isEmpty ||
        node.workerTypes.isEmpty ||
        node.outputItemIds.isEmpty) {
      throw FormatException(
        'Invalid production economics record ${node.nodeId}.',
      );
    }
    return node;
  }

  double expectedQuantityPerCycle(
    int gameItemId,
    BdoWorkerProfileEstimate worker,
  ) {
    final base = worker.isGiant
        ? giantYields[gameItemId] ?? standardYields[gameItemId] ?? 0
        : standardYields[gameItemId] ?? 0;
    final lucky = luckyBonusYields[gameItemId] ?? 0;
    return base + lucky * (worker.luck / 100);
  }
}

/// Pinned worker-cycle and yield inputs for the private map candidate.
final class BdoWorkerEconomicsDataset {
  BdoWorkerEconomicsDataset({
    required this.schemaVersion,
    required this.manifest,
    required Map<String, BdoWorkerTownEconomics> townsByNodeId,
    required Map<String, BdoWorkerProductionEconomics> productionNodesById,
  }) : townsByNodeId = Map<String, BdoWorkerTownEconomics>.unmodifiable(
         townsByNodeId,
       ),
       productionNodesById =
           Map<String, BdoWorkerProductionEconomics>.unmodifiable(
             productionNodesById,
           );

  final int schemaVersion;
  final BdoWorkerEconomicsManifest manifest;
  final Map<String, BdoWorkerTownEconomics> townsByNodeId;
  final Map<String, BdoWorkerProductionEconomics> productionNodesById;

  Set<String> get workerTownNodeIds =>
      Set<String>.unmodifiable(townsByNodeId.keys);

  /// Connected worker towns that have both a verified travel distance and at
  /// least one compatible worker profile for [productionNodeId].
  Set<String> eligibleWorkerTownNodeIds({
    required String productionNodeId,
    required Iterable<String> connectedNodeIds,
  }) {
    final production = productionNodesById[productionNodeId];
    if (production == null) {
      return const <String>{};
    }
    return Set<String>.unmodifiable(<String>{
      for (final townNodeId in connectedNodeIds)
        if (production.townDistances.containsKey(townNodeId))
          if (townsByNodeId[townNodeId] case final town?)
            if (town.profiles.any(
              (profile) => production.workerTypes.contains(profile.workerType),
            ))
              townNodeId,
    });
  }

  /// Worker towns that are also free graph roots in the supplied map.
  ///
  /// Paid worker towns remain valid worker origins once their network node is
  /// connected, but they must not be treated as free solver roots.
  Set<String> verifiedFreeNetworkRootNodeIds(BdoResourceMapDataset map) {
    return Set<String>.unmodifiable(<String>{
      for (final nodeId in townsByNodeId.keys)
        if (map.workerNodesById[nodeId] case final node?
            when node.contributionPoints == 0 &&
                (node.nodeType == 'City' || node.nodeType == 'Town'))
          nodeId,
    });
  }

  factory BdoWorkerEconomicsDataset.fromJson(Object? value) {
    final json = _object(value, 'worker economics');
    final schemaVersion = _requiredInt(json, 'schemaVersion');
    if (schemaVersion != 1) {
      throw FormatException(
        'Unsupported worker economics schema version $schemaVersion.',
      );
    }
    final towns = _keyedObjects(
      json['towns'],
      'towns',
      BdoWorkerTownEconomics.fromJson,
    );
    final productionNodes = _keyedObjects(
      json['productionNodes'],
      'productionNodes',
      BdoWorkerProductionEconomics.fromJson,
    );
    for (final entry in towns.entries) {
      if (entry.key != entry.value.nodeId) {
        throw FormatException(
          'Worker-town key ${entry.key} does not match '
          '${entry.value.nodeId}.',
        );
      }
    }
    for (final entry in productionNodes.entries) {
      if (entry.key != entry.value.nodeId) {
        throw FormatException(
          'Production key ${entry.key} does not match '
          '${entry.value.nodeId}.',
        );
      }
      final unknownTownIds = entry.value.townDistances.keys
          .where((townId) => !towns.containsKey(townId))
          .toList(growable: false);
      if (unknownTownIds.isNotEmpty) {
        throw FormatException(
          'Production node ${entry.key} references unknown towns '
          '${unknownTownIds.join(', ')}.',
        );
      }
    }
    return BdoWorkerEconomicsDataset(
      schemaVersion: schemaVersion,
      manifest: BdoWorkerEconomicsManifest.fromJson(
        _object(json['manifest'], 'manifest'),
      ),
      townsByNodeId: towns,
      productionNodesById: productionNodes,
    );
  }

  factory BdoWorkerEconomicsDataset.fromJsonString(String source) =>
      BdoWorkerEconomicsDataset.fromJson(jsonDecode(source));
}

abstract final class BdoWorkerEconomicsLoader {
  static const String bundledAssetPath =
      'packages/bdo_map_core/assets/data/worker_economics.json';

  static Future<BdoWorkerEconomicsDataset> loadBundled({
    AssetBundle? bundle,
  }) async {
    final source = await (bundle ?? rootBundle).loadString(bundledAssetPath);
    return BdoWorkerEconomicsDataset.fromJsonString(source);
  }
}

Map<String, T> _keyedObjects<T>(
  Object? value,
  String path,
  T Function(Map<String, Object?>) convert,
) {
  final map = _object(value, path);
  return <String, T>{
    for (final entry in map.entries)
      entry.key: convert(_object(entry.value, '$path.${entry.key}')),
  };
}

Map<String, Object?> _object(Object? value, String path) {
  if (value is! Map) {
    throw FormatException('$path must be an object.');
  }
  return <String, Object?>{
    for (final entry in value.entries) entry.key.toString(): entry.value,
  };
}

List<Map<String, Object?>> _objectList(Object? value, String path) {
  if (value is! List) {
    throw FormatException('$path must be an array.');
  }
  return <Map<String, Object?>>[
    for (var index = 0; index < value.length; index++)
      _object(value[index], '$path[$index]'),
  ];
}

String _requiredString(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is! String || value.trim().isEmpty) {
    throw FormatException('$key must be a non-empty string.');
  }
  return value.trim();
}

int _requiredInt(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is int) return value;
  if (value is num && value.isFinite && value == value.truncateToDouble()) {
    return value.toInt();
  }
  throw FormatException('$key must be an integer.');
}

double _requiredDouble(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is! num || !value.isFinite) {
    throw FormatException('$key must be a finite number.');
  }
  return value.toDouble();
}

bool _requiredBool(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is! bool) {
    throw FormatException('$key must be a boolean.');
  }
  return value;
}

List<String> _stringList(Object? value, String path) {
  if (value is! List) {
    throw FormatException('$path must be an array.');
  }
  return <String>[
    for (var index = 0; index < value.length; index++)
      if (value[index] case final String item when item.trim().isNotEmpty)
        item.trim()
      else
        throw FormatException('$path[$index] must be a non-empty string.'),
  ];
}

Map<String, String> _stringMap(Object? value, String path) {
  final map = _object(value, path);
  return <String, String>{
    for (final entry in map.entries)
      entry.key:
          entry.value is String && (entry.value! as String).trim().isNotEmpty
          ? (entry.value! as String).trim()
          : throw FormatException(
              '$path.${entry.key} must be a non-empty string.',
            ),
  };
}

Map<String, double> _doubleMap(Object? value, String path) {
  final map = _object(value, path);
  return <String, double>{
    for (final entry in map.entries)
      entry.key: entry.value is num && (entry.value! as num).isFinite
          ? (entry.value! as num).toDouble()
          : throw FormatException(
              '$path.${entry.key} must be a finite number.',
            ),
  };
}

Map<int, double> _intDoubleMap(Object? value, String path) {
  final map = _object(value, path);
  final result = <int, double>{};
  for (final entry in map.entries) {
    final key = int.tryParse(entry.key);
    final quantity = entry.value;
    if (key == null ||
        key <= 0 ||
        quantity is! num ||
        !quantity.isFinite ||
        quantity < 0) {
      throw FormatException('$path.${entry.key} is invalid.');
    }
    result[key] = quantity.toDouble();
  }
  return result;
}

List<int> _intList(Object? value, String path) {
  if (value is! List) {
    throw FormatException('$path must be an array.');
  }
  final result = <int>[];
  for (var index = 0; index < value.length; index++) {
    final item = value[index];
    if (item is int) {
      result.add(item);
    } else if (item is num &&
        item.isFinite &&
        item == item.truncateToDouble()) {
      result.add(item.toInt());
    } else {
      throw FormatException('$path[$index] must be an integer.');
    }
  }
  return result;
}
