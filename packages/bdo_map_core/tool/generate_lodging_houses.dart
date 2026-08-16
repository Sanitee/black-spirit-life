import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

const _sourceCommit = 'cb4965a5be4e68f231c4bbad7b7a87003e27038b';
const _expectedSourceSha256 = <String, String>{
  'houseinfo.json':
      '85ab96e968266f6e3a590cca18ea7df592959adfa8f512b781f7fa9021556ff4',
  'lodging_per_town.json':
      'c8a24856e1a3aa3acea8b8df5a59439b1bdc58970eca1e31dc23de018ba897ad',
  'loc.json':
      '284338684c006d3f78d7da1c148a952ef09d519af5b39a9cf5c6eb3933487a81',
  'exploration.json':
      '605a498d228b43478215766dbbccc17f833d1ab2c28f6399beb619db18349f7e',
};

Future<void> main(List<String> arguments) async {
  if (arguments.isEmpty) {
    stderr.writeln(
      'Pass the local shrddr/workermanjs repository as the first argument.',
    );
    exitCode = 64;
    return;
  }

  final sourceRepository = Directory(arguments.first).absolute;
  if (!sourceRepository.existsSync()) {
    throw StateError(
      'Workerman repository does not exist: ${sourceRepository.path}',
    );
  }
  final packageRoot = File.fromUri(Platform.script).parent.parent;
  final outputFile = File(
    arguments.length > 1
        ? arguments[1]
        : '${packageRoot.path}${Platform.pathSeparator}assets'
              '${Platform.pathSeparator}data'
              '${Platform.pathSeparator}lodging_houses.json',
  ).absolute;

  final sourceBytes = <String, List<int>>{};
  for (final entry in _expectedSourceSha256.entries) {
    final bytes = await _readGitBlob(
      sourceRepository.path,
      '$_sourceCommit:data/${entry.key}',
    );
    final actual = sha256.convert(bytes).toString();
    if (actual != entry.value) {
      throw StateError(
        '${entry.key} checksum mismatch.\n'
        'Expected: ${entry.value}\n'
        'Actual:   $actual',
      );
    }
    sourceBytes[entry.key] = bytes;
  }

  Map<String, Object?> decodeObject(String name) {
    final decoded = jsonDecode(utf8.decode(sourceBytes[name]!));
    return _object(decoded, name);
  }

  final allHouseInfo = decodeObject('houseinfo.json');
  final lodgingPerTown = decodeObject('lodging_per_town.json');
  final exploration = decodeObject('exploration.json');
  final localization = _object(decodeObject('loc.json')['en'], 'loc.json.en');
  final houseNames = _object(localization['char'], 'loc.json.en.char');
  final townNames = _object(localization['town'], 'loc.json.en.town');
  final nodeNames = _object(localization['node'], 'loc.json.en.node');
  final houseTypeNames = _object(
    localization['housetype'],
    'loc.json.en.housetype',
  );

  final lodgingHouseKeys = <int>{};
  for (final townEntry in lodgingPerTown.entries) {
    final regionId = int.parse(townEntry.key);
    final town = _object(townEntry.value, 'lodging_per_town.$regionId');
    for (final houseValue in _list(town['houses'], 'town $regionId houses')) {
      final house = _object(houseValue, 'town $regionId lodging house');
      final key = _integer(house['key'], 'house key');
      if (!lodgingHouseKeys.add(key)) {
        throw StateError('Lodging house $key occurs more than once.');
      }
    }
  }

  final includedHouseKeys = allHouseInfo.keys.map(int.parse).toSet();
  if (includedHouseKeys.length != 812) {
    throw StateError(
      'Expected the full 812-house graph, found ${includedHouseKeys.length}.',
    );
  }

  final housesByRegion = <int, List<Map<String, Object?>>>{};
  for (final key in includedHouseKeys) {
    final source = _object(allHouseInfo['$key'], 'houseinfo.$key');
    final regionId = _integer(source['affTown'], 'house $key affTown');
    final prerequisiteKey = _integer(
      source['needHouseKey'],
      'house $key prerequisite',
    );
    if (prerequisiteKey != 0 && !includedHouseKeys.contains(prerequisiteKey)) {
      throw StateError(
        'House $key references omitted prerequisite $prerequisiteKey.',
      );
    }
    if (prerequisiteKey != 0) {
      final prerequisite = _object(
        allHouseInfo['$prerequisiteKey'],
        'houseinfo.$prerequisiteKey',
      );
      final prerequisiteRegion = _integer(
        prerequisite['affTown'],
        'house $prerequisiteKey affTown',
      );
      if (prerequisiteRegion != regionId) {
        throw StateError(
          'Cross-town prerequisite: house $key in $regionId requires '
          '$prerequisiteKey in $prerequisiteRegion.',
        );
      }
    }

    final isLodging = lodgingHouseKeys.contains(key);
    var lodgingSpaces = 0;
    if (isLodging) {
      final town = _object(
        lodgingPerTown['$regionId'],
        'lodging_per_town.$regionId',
      );
      final lodgingSource = _list(town['houses'], 'town $regionId houses')
          .map((value) => _object(value, 'lodging house'))
          .singleWhere((house) => _integer(house['key'], 'house key') == key);
      lodgingSpaces = _integer(
        lodgingSource['lodgingSpaces'],
        'house $key lodgingSpaces',
      );
      _verifyMatchingHouseFields(key, source, lodgingSource);
    }
    final craftList = _object(source['CraftList'], 'house $key CraftList');
    final usages =
        craftList.entries
            .map(
              (entry) => <String, Object?>{
                'typeId': int.parse(entry.key),
                'label': _nonEmptyLocalizedName(
                  houseTypeNames[entry.key],
                  fallback: 'House usage ${entry.key}',
                ),
                'level': _integer(entry.value, 'house $key usage ${entry.key}'),
              },
            )
            .toList(growable: false)
          ..sort(
            (left, right) =>
                (left['typeId']! as int).compareTo(right['typeId']! as int),
          );
    if (isLodging != craftList.containsKey('1')) {
      throw StateError('House $key lodging table and usage metadata disagree.');
    }

    final house = <String, Object?>{
      'id': 'house:$key',
      'sourceKey': key,
      'name': _nonEmptyLocalizedName(
        houseNames['$key'],
        fallback: 'House $key',
      ),
      'regionId': regionId,
      'townNodeId': '',
      'parentNodeId': '${_integer(source['parentNode'], 'parentNode')}',
      'contributionPoints': _integer(source['CP'], 'house $key CP'),
      'lodgingSpaces': lodgingSpaces,
      'isLodging': isLodging,
      'usages': usages,
      'prerequisiteHouseId': prerequisiteKey == 0
          ? null
          : 'house:$prerequisiteKey',
      'position': <String, Object?>{
        'x': _number(source['x'], 'house $key x'),
        'y': _number(source['y'], 'house $key y'),
        'z': _number(source['z'], 'house $key z'),
      },
    };
    housesByRegion
        .putIfAbsent(regionId, () => <Map<String, Object?>>[])
        .add(house);
  }

  final towns = <Map<String, Object?>>[];
  final sortedRegionIds = housesByRegion.keys.toList()..sort();
  for (final regionId in sortedRegionIds) {
    final sourceTownValue = lodgingPerTown['$regionId'];
    final isWorkerTown = sourceTownValue != null;
    final houseRows = housesByRegion[regionId]!;
    houseRows.sort(
      (left, right) =>
          (left['sourceKey']! as int).compareTo(right['sourceKey']! as int),
    );
    final townNodeId = isWorkerTown
        ? _integer(
            _object(
              _object(sourceTownValue, 'lodging_per_town.$regionId')['region'],
              'town $regionId region',
            )['waypoint'],
            'town $regionId waypoint',
          )
        : _singleParentNodeId(regionId, houseRows);
    final explorationTown = _object(
      exploration['$townNodeId'],
      'exploration.$townNodeId',
    );
    for (final house in houseRows) {
      house['townNodeId'] = '$townNodeId';
    }
    final name = _nonEmptyLocalizedName(
      townNames['$regionId'],
      fallback: _nonEmptyLocalizedName(
        nodeNames['$townNodeId'],
        fallback: 'Town $regionId',
      ),
    );
    towns.add(<String, Object?>{
      'regionId': regionId,
      'townNodeId': '$townNodeId',
      'name': name,
      'isWorkerTown': isWorkerTown,
      'baseWorkerSlots': isWorkerTown ? 1 : 0,
      'position': <String, Object?>{
        'x': _number(
          _object(explorationTown['pos'], 'town $regionId pos')['x'],
          'town $regionId x',
        ),
        'y': _number(
          _object(explorationTown['pos'], 'town $regionId pos')['y'],
          'town $regionId y',
        ),
        'z': _number(
          _object(explorationTown['pos'], 'town $regionId pos')['z'],
          'town $regionId z',
        ),
      },
      'houses': houseRows,
    });
  }

  if (towns.length != 31) {
    throw StateError('Expected 31 housing towns, found ${towns.length}.');
  }
  final workerTownCount = towns
      .where((town) => town['isWorkerTown'] == true)
      .length;
  if (workerTownCount != 30) {
    throw StateError('Expected 30 worker towns, found $workerTownCount.');
  }
  if (lodgingHouseKeys.length != 225) {
    throw StateError(
      'Expected 225 lodging houses, found ${lodgingHouseKeys.length}.',
    );
  }
  final nonLodgingHouseCount =
      includedHouseKeys.length - lodgingHouseKeys.length;
  if (nonLodgingHouseCount != 587 || includedHouseKeys.length != 812) {
    throw StateError(
      'Expected 587 non-lodging / 812 total houses, found '
      '$nonLodgingHouseCount / ${includedHouseKeys.length}.',
    );
  }
  _validateAcyclic(towns);

  final output = <String, Object?>{
    'schemaVersion': 2,
    'manifest': <String, Object?>{
      'datasetVersion':
          '2026.07.30-workerman-${_sourceCommit.substring(0, 8)}-stable',
      'generatedAt': '2026-07-30T00:00:00.000Z',
      'sourceRepository': 'https://github.com/shrddr/workermanjs',
      'sourceCommit': _sourceCommit,
      'sourceLicenseExpression': 'NOASSERTION',
      'permittedUse':
          'Project-owner approved for attributed use in the completely free, '
          'noncommercial Black Spirit Life fan project. WorkermanJS is '
          'publicly shared and hosted for community use; no separate licence '
          'file was found. Retain credits and respond promptly to any '
          'substantiated correction or removal request from Shrddr.',
      'sourceSha256': _expectedSourceSha256,
      'townCount': towns.length,
      'workerTownCount': workerTownCount,
      'lodgingHouseCount': lodgingHouseKeys.length,
      'nonLodgingHouseCount': nonLodgingHouseCount,
      'houseCount': includedHouseKeys.length,
      'assumptions': <String>[
        'The source lists one free base worker slot per worker town.',
        'Only houses listed by lodging_per_town.json add lodging capacity.',
        'All source houses retain exact CP, coordinates, prerequisites, and '
            'available usage types; non-lodging houses add no capacity.',
        'House coordinates are unmodified game-world coordinates.',
      ],
    },
    'towns': towns,
  };

  outputFile.parent.createSync(recursive: true);
  final outputBytes = utf8.encode(
    '${const JsonEncoder.withIndent('  ').convert(output)}\n',
  );
  outputFile.writeAsBytesSync(outputBytes);
  stdout.writeln(
    const JsonEncoder.withIndent('  ').convert(<String, Object?>{
      'outputPath': outputFile.path,
      'bytes': outputBytes.length,
      'sha256': sha256.convert(outputBytes).toString(),
      'towns': towns.length,
      'workerTowns': workerTownCount,
      'lodgingHouses': lodgingHouseKeys.length,
      'nonLodgingHouses': nonLodgingHouseCount,
      'houses': includedHouseKeys.length,
      'hakinzaTownNodeId': towns.singleWhere(
        (town) => town['regionId'] == 1553,
      )['townNodeId'],
    }),
  );
}

int _singleParentNodeId(int regionId, List<Map<String, Object?>> houses) {
  final parentNodeIds = houses
      .map((house) => int.parse(house['parentNodeId']! as String))
      .toSet();
  if (parentNodeIds.length != 1) {
    throw StateError(
      'Housing-only region $regionId has no unambiguous town node: '
      '${parentNodeIds.join(', ')}.',
    );
  }
  return parentNodeIds.single;
}

Future<List<int>> _readGitBlob(String repository, String objectName) async {
  final result = await Process.run(
    'git',
    <String>['-C', repository, 'show', objectName],
    stdoutEncoding: null,
    stderrEncoding: utf8,
  );
  if (result.exitCode != 0) {
    throw StateError(
      'Unable to read $objectName from $repository:\n${result.stderr}',
    );
  }
  return List<int>.unmodifiable(result.stdout! as List<int>);
}

void _verifyMatchingHouseFields(
  int key,
  Map<String, Object?> full,
  Map<String, Object?> lodging,
) {
  for (final field in <String>[
    'CP',
    'parentNode',
    'affTown',
    'needHouseKey',
    'x',
    'y',
    'z',
  ]) {
    if ((full[field] as num).toDouble() != (lodging[field] as num).toDouble()) {
      throw StateError('House $key has conflicting $field values.');
    }
  }
}

void _validateAcyclic(List<Map<String, Object?>> towns) {
  for (final town in towns) {
    final houses = <String, Map<String, Object?>>{
      for (final value in town['houses']! as List<Object?>)
        (value! as Map<String, Object?>)['id']! as String:
            value as Map<String, Object?>,
    };
    final finished = <String>{};
    final visiting = <String>{};
    void visit(String id) {
      if (finished.contains(id)) return;
      if (!visiting.add(id)) {
        throw StateError('Prerequisite cycle at $id.');
      }
      final prerequisite = houses[id]!['prerequisiteHouseId'];
      if (prerequisite is String) {
        if (!houses.containsKey(prerequisite)) {
          throw StateError('$id references missing $prerequisite.');
        }
        visit(prerequisite);
      }
      visiting.remove(id);
      finished.add(id);
    }

    for (final id in houses.keys) {
      visit(id);
    }
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

List<Object?> _list(Object? value, String path) {
  if (value is! List) {
    throw FormatException('$path must be an array.');
  }
  return value;
}

int _integer(Object? value, String path) {
  if (value is int) return value;
  if (value is num &&
      value.isFinite &&
      value.toDouble() == value.truncateToDouble()) {
    return value.toInt();
  }
  throw FormatException('$path must be an integer.');
}

double _number(Object? value, String path) {
  if (value is! num || !value.isFinite) {
    throw FormatException('$path must be finite.');
  }
  return value.toDouble();
}

String _nonEmptyLocalizedName(Object? value, {required String fallback}) {
  if (value is String && value.trim().isNotEmpty) {
    return value.trim();
  }
  return fallback;
}
