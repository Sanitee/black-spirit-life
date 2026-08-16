import 'dart:convert';

import 'package:flutter/services.dart';

final class LodgingDataManifest {
  LodgingDataManifest({
    required this.datasetVersion,
    required this.generatedAt,
    required this.sourceRepository,
    required this.sourceCommit,
    required this.sourceLicenseExpression,
    required this.permittedUse,
    required Map<String, String> sourceSha256,
    required this.townCount,
    required this.workerTownCount,
    required this.lodgingHouseCount,
    required this.nonLodgingHouseCount,
    required this.houseCount,
    required Iterable<String> assumptions,
  }) : sourceSha256 = Map<String, String>.unmodifiable(sourceSha256),
       assumptions = List<String>.unmodifiable(assumptions);

  final String datasetVersion;
  final DateTime generatedAt;
  final Uri sourceRepository;
  final String sourceCommit;
  final String sourceLicenseExpression;
  final String permittedUse;
  final Map<String, String> sourceSha256;
  final int townCount;
  final int workerTownCount;
  final int lodgingHouseCount;
  final int nonLodgingHouseCount;
  final int houseCount;
  final List<String> assumptions;

  @Deprecated('Use nonLodgingHouseCount for the complete housing graph.')
  int get prerequisiteOnlyHouseCount => nonLodgingHouseCount;

  factory LodgingDataManifest.fromJson(Map<String, Object?> json) {
    return LodgingDataManifest(
      datasetVersion: _requiredString(json, 'datasetVersion'),
      generatedAt: DateTime.parse(_requiredString(json, 'generatedAt')).toUtc(),
      sourceRepository: Uri.parse(_requiredString(json, 'sourceRepository')),
      sourceCommit: _requiredString(json, 'sourceCommit'),
      sourceLicenseExpression: _requiredString(json, 'sourceLicenseExpression'),
      permittedUse: _requiredString(json, 'permittedUse'),
      sourceSha256: _stringMap(json['sourceSha256'], 'sourceSha256'),
      townCount: _requiredInt(json, 'townCount'),
      workerTownCount: _requiredInt(json, 'workerTownCount'),
      lodgingHouseCount: _requiredInt(json, 'lodgingHouseCount'),
      nonLodgingHouseCount: _requiredInt(json, 'nonLodgingHouseCount'),
      houseCount: _requiredInt(json, 'houseCount'),
      assumptions: _stringList(json['assumptions'], 'assumptions'),
    );
  }
}

final class LodgingPosition {
  const LodgingPosition({required this.x, required this.y, required this.z});

  final double x;
  final double y;
  final double z;

  factory LodgingPosition.fromJson(Map<String, Object?> json) {
    return LodgingPosition(
      x: _requiredDouble(json, 'x'),
      y: _requiredDouble(json, 'y'),
      z: _requiredDouble(json, 'z'),
    );
  }
}

final class HouseUsage {
  const HouseUsage({
    required this.typeId,
    required this.label,
    required this.level,
  });

  final int typeId;
  final String label;
  final int level;

  factory HouseUsage.fromJson(Map<String, Object?> json) {
    final usage = HouseUsage(
      typeId: _requiredInt(json, 'typeId'),
      label: _requiredString(json, 'label'),
      level: _requiredInt(json, 'level'),
    );
    if (usage.typeId < 0 || usage.level <= 0) {
      throw const FormatException(
        'House usage ids cannot be negative and levels must be positive.',
      );
    }
    return usage;
  }
}

final class LodgingHouse {
  LodgingHouse({
    required this.id,
    required this.sourceKey,
    required this.name,
    required this.regionId,
    required this.townNodeId,
    required this.parentNodeId,
    required this.contributionPoints,
    required this.lodgingSpaces,
    required this.isLodging,
    Iterable<HouseUsage> usages = const <HouseUsage>[],
    required this.prerequisiteHouseId,
    required this.position,
  }) : usages = List<HouseUsage>.unmodifiable(usages),
       usagesByTypeId = Map<int, HouseUsage>.unmodifiable(<int, HouseUsage>{
         for (final usage in usages) usage.typeId: usage,
       });

  final String id;
  final int sourceKey;
  final String name;
  final int regionId;
  final String townNodeId;
  final String parentNodeId;
  final int contributionPoints;
  final int lodgingSpaces;
  final bool isLodging;
  final List<HouseUsage> usages;
  final Map<int, HouseUsage> usagesByTypeId;
  final String? prerequisiteHouseId;
  final LodgingPosition position;

  bool supportsUsage(int typeId) => usagesByTypeId.containsKey(typeId);

  factory LodgingHouse.fromJson(Map<String, Object?> json) {
    final prerequisite = json['prerequisiteHouseId'];
    if (prerequisite != null &&
        (prerequisite is! String || prerequisite.trim().isEmpty)) {
      throw const FormatException(
        'prerequisiteHouseId must be null or a non-empty string.',
      );
    }
    final house = LodgingHouse(
      id: _requiredString(json, 'id'),
      sourceKey: _requiredInt(json, 'sourceKey'),
      name: _requiredString(json, 'name'),
      regionId: _requiredInt(json, 'regionId'),
      townNodeId: _requiredString(json, 'townNodeId'),
      parentNodeId: _requiredString(json, 'parentNodeId'),
      contributionPoints: _requiredInt(json, 'contributionPoints'),
      lodgingSpaces: _requiredInt(json, 'lodgingSpaces'),
      isLodging: _requiredBool(json, 'isLodging'),
      usages: _objectList(
        json['usages'],
        '${json['id']}.usages',
      ).map(HouseUsage.fromJson),
      prerequisiteHouseId: (prerequisite as String?)?.trim(),
      position: LodgingPosition.fromJson(
        _object(json['position'], '${json['id']}.position'),
      ),
    );
    if (house.id != 'house:${house.sourceKey}') {
      throw FormatException(
        'House id ${house.id} does not match source key ${house.sourceKey}.',
      );
    }
    if (house.contributionPoints < 0 ||
        house.lodgingSpaces < 0 ||
        house.isLodging != (house.lodgingSpaces > 0)) {
      throw FormatException('Invalid lodging values for ${house.id}.');
    }
    if (house.usages.isEmpty ||
        house.usagesByTypeId.length != house.usages.length ||
        house.isLodging != house.supportsUsage(1)) {
      throw FormatException('Invalid house usage metadata for ${house.id}.');
    }
    if (house.prerequisiteHouseId == house.id) {
      throw FormatException('${house.id} cannot require itself.');
    }
    return house;
  }
}

final class LodgingTown {
  LodgingTown({
    required this.regionId,
    required this.townNodeId,
    required this.name,
    this.isWorkerTown = true,
    required this.baseWorkerSlots,
    required this.position,
    required Iterable<LodgingHouse> houses,
  }) : houses = List<LodgingHouse>.unmodifiable(houses),
       housesById = Map<String, LodgingHouse>.unmodifiable(
         <String, LodgingHouse>{for (final house in houses) house.id: house},
       );

  final int regionId;
  final String townNodeId;
  final String name;
  final bool isWorkerTown;
  final int baseWorkerSlots;
  final LodgingPosition position;
  final List<LodgingHouse> houses;
  final Map<String, LodgingHouse> housesById;

  Iterable<LodgingHouse> get lodgingHouses =>
      houses.where((house) => house.isLodging);

  Iterable<LodgingHouse> get nonLodgingHouses =>
      houses.where((house) => !house.isLodging);

  @Deprecated('Use nonLodgingHouses for the complete housing graph.')
  Iterable<LodgingHouse> get prerequisiteOnlyHouses => nonLodgingHouses;

  factory LodgingTown.fromJson(Map<String, Object?> json) {
    final houseRows = _objectList(
      json['houses'],
      '${json['townNodeId']}.houses',
    ).map(LodgingHouse.fromJson).toList(growable: false);
    final town = LodgingTown(
      regionId: _requiredInt(json, 'regionId'),
      townNodeId: _requiredString(json, 'townNodeId'),
      name: _requiredString(json, 'name'),
      isWorkerTown: _requiredBool(json, 'isWorkerTown'),
      baseWorkerSlots: _requiredInt(json, 'baseWorkerSlots'),
      position: LodgingPosition.fromJson(
        _object(json['position'], '${json['townNodeId']}.position'),
      ),
      houses: houseRows,
    );
    if (town.baseWorkerSlots < 0) {
      throw FormatException(
        '${town.townNodeId} has a negative base worker capacity.',
      );
    }
    if (!town.isWorkerTown &&
        (town.baseWorkerSlots != 0 || town.lodgingHouses.isNotEmpty)) {
      throw FormatException(
        '${town.townNodeId} is housing-only but has worker capacity.',
      );
    }
    if (town.housesById.length != town.houses.length) {
      throw FormatException('${town.townNodeId} has duplicate house ids.');
    }
    for (final house in town.houses) {
      if (house.regionId != town.regionId ||
          house.townNodeId != town.townNodeId) {
        throw FormatException(
          '${house.id} is assigned to the wrong lodging town.',
        );
      }
      final prerequisiteId = house.prerequisiteHouseId;
      if (prerequisiteId != null &&
          !town.housesById.containsKey(prerequisiteId)) {
        throw FormatException(
          '${house.id} references missing or cross-town prerequisite '
          '$prerequisiteId.',
        );
      }
    }
    _validateAcyclic(town);
    return town;
  }
}

final class LodgingDataset {
  LodgingDataset({
    required this.schemaVersion,
    required this.manifest,
    required Iterable<LodgingTown> towns,
  }) : towns = List<LodgingTown>.unmodifiable(towns),
       townsByNodeId = Map<String, LodgingTown>.unmodifiable(
         <String, LodgingTown>{for (final town in towns) town.townNodeId: town},
       ),
       townsByRegionId = Map<int, LodgingTown>.unmodifiable(<int, LodgingTown>{
         for (final town in towns) town.regionId: town,
       }),
       housesById = Map<String, LodgingHouse>.unmodifiable(
         <String, LodgingHouse>{
           for (final town in towns)
             for (final house in town.houses) house.id: house,
         },
       );

  final int schemaVersion;
  final LodgingDataManifest manifest;
  final List<LodgingTown> towns;
  final Map<String, LodgingTown> townsByNodeId;
  final Map<int, LodgingTown> townsByRegionId;
  final Map<String, LodgingHouse> housesById;

  factory LodgingDataset.fromJson(Object? value) {
    final json = _object(value, 'lodging dataset');
    final schemaVersion = _requiredInt(json, 'schemaVersion');
    if (schemaVersion != 2) {
      throw FormatException(
        'Unsupported lodging schema version $schemaVersion.',
      );
    }
    final manifest = LodgingDataManifest.fromJson(
      _object(json['manifest'], 'manifest'),
    );
    final towns = _objectList(
      json['towns'],
      'towns',
    ).map(LodgingTown.fromJson).toList(growable: false);
    final dataset = LodgingDataset(
      schemaVersion: schemaVersion,
      manifest: manifest,
      towns: towns,
    );
    if (dataset.townsByNodeId.length != towns.length ||
        dataset.townsByRegionId.length != towns.length) {
      throw const FormatException(
        'Lodging towns must have unique region and map-node ids.',
      );
    }
    final lodgingCount = dataset.housesById.values
        .where((house) => house.isLodging)
        .length;
    final nonLodgingCount = dataset.housesById.length - lodgingCount;
    final workerTownCount = towns.where((town) => town.isWorkerTown).length;
    if (manifest.townCount != towns.length ||
        manifest.workerTownCount != workerTownCount ||
        manifest.houseCount != dataset.housesById.length ||
        manifest.lodgingHouseCount != lodgingCount ||
        manifest.nonLodgingHouseCount != nonLodgingCount) {
      throw const FormatException(
        'Lodging manifest counts do not match the parsed records.',
      );
    }
    return dataset;
  }

  factory LodgingDataset.fromJsonString(String source) =>
      LodgingDataset.fromJson(jsonDecode(source));
}

abstract final class LodgingDataLoader {
  static const bundledAssetPath =
      'packages/bdo_map_core/assets/data/lodging_houses.json';

  static Future<LodgingDataset> loadBundled({AssetBundle? bundle}) async {
    final source = await (bundle ?? rootBundle).loadString(bundledAssetPath);
    return LodgingDataset.fromJsonString(source);
  }
}

void _validateAcyclic(LodgingTown town) {
  final visiting = <String>{};
  final finished = <String>{};

  void visit(String houseId) {
    if (finished.contains(houseId)) return;
    if (!visiting.add(houseId)) {
      throw FormatException(
        '${town.townNodeId} has a prerequisite cycle at $houseId.',
      );
    }
    final prerequisite = town.housesById[houseId]!.prerequisiteHouseId;
    if (prerequisite != null) visit(prerequisite);
    visiting.remove(houseId);
    finished.add(houseId);
  }

  for (final houseId in town.housesById.keys) {
    visit(houseId);
  }
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
