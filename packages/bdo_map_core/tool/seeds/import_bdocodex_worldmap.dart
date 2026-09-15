import 'dart:convert';
import 'dart:io';

const _expectedNodeCount = 1052;
const _expectedExplorationCount = 610;
const _expectedProductionCount = 442;
const _expectedLinkedProductionCount = 425;
const _expectedExplorationLinkCount = 667;
const _expectedProductionLinkCount = 426;
const _expectedProductCount = 285;
const _reviewedProductionParentCorrections = <int, int>{
  206: 66,
  207: 72,
  208: 72,
  209: 63,
  1677: 1668,
  1678: 1668,
  1717: 1704,
  1720: 1704,
  1734: 1007,
  1735: 1008,
  1736: 1099,
  1737: 1100,
};

Future<void> main(List<String> arguments) async {
  final sourcePath = _option(arguments, '--source');
  final outputPath = _option(arguments, '--output');
  final retrievedAt = _option(arguments, '--retrieved-at');
  if (sourcePath == null || outputPath == null || retrievedAt == null) {
    stderr.writeln(
      'Usage: dart run tool/seeds/import_bdocodex_worldmap.dart '
      '--source <raw-response.json> --output <seed.json> '
      '--retrieved-at <UTC ISO-8601>',
    );
    exitCode = 64;
    return;
  }
  final retrieved = DateTime.tryParse(retrievedAt)?.toUtc();
  if (retrieved == null || !retrievedAt.endsWith('Z')) {
    throw const FormatException('--retrieved-at must be an ISO-8601 UTC time.');
  }

  final decoded =
      jsonDecode(await File(sourcePath).readAsString()) as Map<String, dynamic>;
  final data = decoded['data'];
  if (decoded['result'] != 1 || data is! Map<String, dynamic>) {
    throw const FormatException('The BDO Codex world-map response failed.');
  }
  final rawNodes = _map(data['nodes'], 'data.nodes');
  final rawProducts = _map(data['products'], 'data.products');
  final rawLinks = _list(data['links'], 'data.links');
  final rawProductionLinks = _list(data['plinks'], 'data.plinks');
  if (rawNodes.length != _expectedNodeCount ||
      rawLinks.length != _expectedExplorationLinkCount ||
      rawProductionLinks.length != _expectedProductionLinkCount ||
      rawProducts.length != _expectedProductCount) {
    throw FormatException(
      'The live response shape changed: '
      '${rawNodes.length} nodes, ${rawLinks.length} links, '
      '${rawProductionLinks.length} production links, '
      '${rawProducts.length} products.',
    );
  }

  final products = <int, _Product>{};
  final productsByName = <String, _Product>{};
  for (final entry in rawProducts.entries) {
    final itemId = int.tryParse(entry.key);
    final row = _map(entry.value, 'product ${entry.key}');
    final productData = _list(row['data'], 'product ${entry.key}.data');
    if (itemId == null || productData.length < 2) {
      throw FormatException('Invalid product ${entry.key}.');
    }
    final iconPath = productData[0];
    final name = productData[1];
    if (iconPath is! String || name is! String || name.trim().isEmpty) {
      throw FormatException('Invalid product ${entry.key} metadata.');
    }
    final product = _Product(
      itemId: itemId,
      name: _decodeHtml(name).trim(),
      iconPath: iconPath,
    );
    final key = _nameKey(product.name);
    final previous = productsByName[key];
    if (previous != null && previous.itemId != product.itemId) {
      throw FormatException(
        'Product name "${product.name}" maps to both '
        '${previous.itemId} and ${product.itemId}.',
      );
    }
    products[itemId] = product;
    productsByName[key] = product;
  }

  final nodes = <int, _Node>{};
  final nodesByCoordinate = <String, List<_Node>>{};
  for (final entry in rawNodes.entries) {
    final id = int.tryParse(entry.key);
    final row = _list(entry.value, 'node ${entry.key}');
    if (id == null || row.length != 7) {
      throw FormatException('Invalid node ${entry.key}.');
    }
    final pixel = _list(row[0], 'node ${entry.key} coordinates');
    final pixelX = _number(pixel.elementAtOrNull(0));
    final pixelY = _number(pixel.elementAtOrNull(1));
    final rawName = row[1];
    final iconType = _integer(row[2]);
    final layerFlag = _integer(row[3]);
    final embeddedId = _integer(row[4]);
    final contributionPoints = _integer(row[5]);
    final outputHtml = row[6];
    if (pixel.length != 2 ||
        pixelX == null ||
        pixelY == null ||
        !pixelX.isFinite ||
        !pixelY.isFinite ||
        rawName is! String ||
        rawName.trim().isEmpty ||
        iconType == null ||
        layerFlag == null ||
        embeddedId != id ||
        contributionPoints == null ||
        outputHtml is! String) {
      throw FormatException('Invalid node ${entry.key} fields.');
    }
    final outputs = _parseOutputs(
      outputHtml,
      productsByName: productsByName,
      nodeId: id,
    );
    final node = _Node(
      id: id,
      rawName: _decodeHtml(rawName).trim(),
      iconType: iconType,
      sourceLayerFlag: layerFlag,
      pixelX: pixelX,
      pixelY: pixelY,
      contributionPoints: contributionPoints,
      outputs: outputs,
    );
    node.isProductionNode = layerFlag == 0;
    if (nodes[id] != null) {
      throw FormatException('Duplicate node ID $id.');
    }
    nodes[id] = node;
    (nodesByCoordinate[_coordinateKey(pixelX, pixelY)] ??= <_Node>[]).add(node);
  }

  final rawLayerZeroCount = nodes.values
      .where((node) => node.sourceLayerFlag == 0)
      .length;
  final rawLayerOneCount = nodes.values
      .where((node) => node.sourceLayerFlag == 1)
      .length;
  if (rawLayerZeroCount != _expectedProductionCount ||
      rawLayerOneCount != _expectedExplorationCount) {
    throw FormatException(
      'The source layer distribution changed: '
      '$rawLayerOneCount / $rawLayerZeroCount.',
    );
  }

  var ignoredExplorationSelfLinkCount = 0;
  for (final rawLink in rawLinks) {
    final endpoints = _endpoints(rawLink, 'exploration link');
    final first = _resolveEndpoint(
      nodesByCoordinate,
      endpoints.$1,
      expectedLayerFlag: 1,
    );
    final second = _resolveEndpoint(
      nodesByCoordinate,
      endpoints.$2,
      expectedLayerFlag: 1,
    );
    if (first.id == second.id) {
      ignoredExplorationSelfLinkCount += 1;
      continue;
    }
    first.linkIds.add(second.id);
    second.linkIds.add(first.id);
  }

  final productionIds = <int>{};
  var repairedProductionParentCount = 0;
  for (final rawLink in rawProductionLinks) {
    final endpoints = _endpoints(rawLink, 'production link');
    final firstCandidates =
        nodesByCoordinate[_coordinateKey(endpoints.$1.$1, endpoints.$1.$2)] ??
        const <_Node>[];
    final secondCandidates =
        nodesByCoordinate[_coordinateKey(endpoints.$2.$1, endpoints.$2.$2)] ??
        const <_Node>[];
    final firstProduction = firstCandidates
        .where((node) => node.sourceLayerFlag == 0)
        .toList(growable: false);
    final secondProduction = secondCandidates
        .where((node) => node.sourceLayerFlag == 0)
        .toList(growable: false);
    final firstExploration = firstCandidates
        .where((node) => node.sourceLayerFlag == 1)
        .toList(growable: false);
    final secondExploration = secondCandidates
        .where((node) => node.sourceLayerFlag == 1)
        .toList(growable: false);

    if (firstExploration.isEmpty && secondExploration.isEmpty) {
      repairedProductionParentCount += 1;
      continue;
    }
    late final _Node production;
    _Node? parent;
    if (firstProduction.isNotEmpty && secondExploration.isNotEmpty) {
      production = _preferredNode(firstProduction);
      parent = _preferredNode(secondExploration);
    } else if (secondProduction.isNotEmpty && firstExploration.isNotEmpty) {
      production = _preferredNode(secondProduction);
      parent = _preferredNode(firstExploration);
    } else {
      final productionCandidates = <_Node>{
        ...firstProduction,
        ...secondProduction,
      };
      if (productionCandidates.isEmpty) {
        throw FormatException('Ambiguous BDO Codex production link.');
      }
      production = _preferredNode(productionCandidates);
    }
    if (!productionIds.add(production.id)) {
      throw FormatException(
        'Production node ${production.id} has more than one parent link.',
      );
    }
    if (parent == null) {
      throw FormatException(
        'Production node ${production.id} has no factual parent endpoint.',
      );
    }
    _attachParent(production, parent);
    production.isProductionNode = true;
  }
  if (productionIds.length != _expectedLinkedProductionCount) {
    throw FormatException(
      'Expected $_expectedLinkedProductionCount unique parent-linked '
      'production nodes; '
      'found ${productionIds.length}.',
    );
  }

  final unlinkedLayerZeroNodes = nodes.values
      .where((node) => node.sourceLayerFlag == 0 && node.parentId == null)
      .toList(growable: false);
  if (unlinkedLayerZeroNodes.length != 17 ||
      repairedProductionParentCount != 1 ||
      ignoredExplorationSelfLinkCount != 1) {
    throw FormatException(
      'The pinned link-repair boundary changed: '
      '${unlinkedLayerZeroNodes.length} unlinked layer-zero nodes and '
      '$repairedProductionParentCount malformed production links and '
      '$ignoredExplorationSelfLinkCount malformed exploration links.',
    );
  }

  var reviewedProductionParentCorrectionCount = 0;
  for (final correction in _reviewedProductionParentCorrections.entries) {
    final production = nodes[correction.key];
    final parent = nodes[correction.value];
    if (production == null ||
        parent == null ||
        production.sourceLayerFlag != 0 ||
        parent.sourceLayerFlag != 1 ||
        production.parentId != null ||
        !productionIds.add(production.id)) {
      throw FormatException(
        'Reviewed parent correction ${correction.key} / '
        '${correction.value} no longer matches the source snapshot.',
      );
    }
    _attachParent(production, parent);
    reviewedProductionParentCorrectionCount += 1;
  }
  final remainingUnlinkedLayerZeroNodes = nodes.values
      .where((node) => node.sourceLayerFlag == 0 && node.parentId == null)
      .toList(growable: false);
  if (reviewedProductionParentCorrectionCount !=
          _reviewedProductionParentCorrections.length ||
      remainingUnlinkedLayerZeroNodes.length != 5) {
    throw const FormatException(
      'The reviewed production-parent correction boundary changed.',
    );
  }

  for (final node in nodes.values) {
    node.nodeType = _nodeType(node);
    if (node.sourceLayerFlag == 0) {
      final parentId = node.parentId;
      node.name = parentId == null
          ? node.rawName.toLowerCase() == 'unknown'
                ? 'Unlinked map record ${node.id}'
                : '${node.rawName} · Unlinked map record ${node.id}'
          : '${nodes[parentId]!.rawName} - ${node.rawName}';
    } else {
      node.name = node.rawName;
    }
  }

  final explorationCount = nodes.values
      .where((node) => node.sourceLayerFlag == 1)
      .length;
  final productionCount = nodes.values
      .where((node) => node.sourceLayerFlag == 0)
      .length;
  if (explorationCount != _expectedExplorationCount ||
      productionCount != _expectedProductionCount) {
    throw FormatException(
      'Expected $_expectedExplorationCount exploration and '
      '$_expectedProductionCount production-layer nodes; '
      'found $explorationCount and $productionCount.',
    );
  }
  _validateNodeLinks(nodes);
  for (final node in nodes.values.where(
    (node) => productionIds.contains(node.id),
  )) {
    final parent = nodes[node.parentId];
    if (parent == null || !node.linkIds.contains(parent.id)) {
      throw FormatException(
        'Production node ${node.id} has no resolved parent link.',
      );
    }
  }

  final normalized = <String, Object?>{
    'schemaVersion': 1,
    'status': 'privateNoncommercialCandidate',
    'sourceReview': <String, Object?>{
      'provider': 'BDO Codex',
      'url': 'https://bdocodex.com/us/worldmap/',
      'endpoint': 'https://bdocodex.com/ajax.php?l=us',
      'locale': 'us',
      'retrievedAt': retrieved.toIso8601String(),
      'reuseStatus': 'Unconfirmed',
      'distributionBoundary':
          'Private candidate only; do not publish or redistribute this '
          'snapshot or its derived current-node records without permission.',
      'rawLayerOneCount': rawLayerOneCount,
      'rawLayerZeroCount': rawLayerZeroCount,
      'explorationLinkCount': rawLinks.length,
      'productionLinkCount': rawProductionLinks.length,
      'unlinkedLayerZeroCount': unlinkedLayerZeroNodes.length,
      'repairedMalformedProductionParentCount': repairedProductionParentCount,
      'reviewedProductionParentCorrectionCount':
          reviewedProductionParentCorrectionCount,
      'remainingUnlinkedLayerZeroCount': remainingUnlinkedLayerZeroNodes.length,
      'ignoredMalformedExplorationSelfLinkCount':
          ignoredExplorationSelfLinkCount,
    },
    'coordinateTransform': <String, String>{
      'gameX': '(pixelX - 68600) * 25',
      'gameZ': '(72200 - pixelY) * 25',
    },
    'counts': <String, int>{
      'nodes': nodes.length,
      'exploration': explorationCount,
      'production': productionCount,
      'linkedProduction': productionIds.length,
      'products': products.length,
    },
    'products':
        products.values
            .map(
              (product) => <String, Object?>{
                'itemId': product.itemId,
                'name': product.name,
                'iconPath': product.iconPath,
              },
            )
            .toList(growable: false)
          ..sort(
            (first, second) =>
                (first['itemId']! as int).compareTo(second['itemId']! as int),
          ),
    'nodes': nodes.values.map((node) => node.toJson()).toList(growable: false)
      ..sort(
        (first, second) =>
            (first['id']! as int).compareTo(second['id']! as int),
      ),
  };
  final output = File(outputPath);
  await output.parent.create(recursive: true);
  const encoder = JsonEncoder.withIndent('  ');
  await output.writeAsString('${encoder.convert(normalized)}\n');
  stdout.writeln(
    'Wrote ${output.path}: ${nodes.length} nodes '
    '($_expectedExplorationCount exploration / '
    '$_expectedProductionCount production), ${products.length} products.',
  );
}

List<_Output> _parseOutputs(
  String html, {
  required Map<String, _Product> productsByName,
  required int nodeId,
}) {
  if (html.trim().isEmpty) {
    return const <_Output>[];
  }
  final result = <_Output>[];
  for (final fragment in html.split(
    RegExp(r'<br\s*/?>', caseSensitive: false),
  )) {
    final text = _decodeHtml(
      fragment.replaceAll(RegExp(r'<[^>]*>'), ' '),
    ).replaceAll(RegExp(r'\s+'), ' ').trim();
    if (text.isEmpty) {
      continue;
    }
    final product = productsByName[_nameKey(text)];
    if (product == null) {
      throw FormatException(
        'Node $nodeId output "$text" has no structured product record.',
      );
    }
    result.add(
      _Output(
        itemId: product.itemId,
        name: product.name,
        isPrimary: result.isEmpty,
      ),
    );
  }
  return List<_Output>.unmodifiable(result);
}

((double, double), (double, double)) _endpoints(Object? raw, String label) {
  final pair = _list(raw, label);
  if (pair.length != 2) {
    throw FormatException('$label must contain two endpoints.');
  }
  (double, double) point(Object? value) {
    final rawPoint = _list(value, '$label endpoint');
    final x = _number(rawPoint.elementAtOrNull(0));
    final y = _number(rawPoint.elementAtOrNull(1));
    if (rawPoint.length != 2 || x == null || y == null) {
      throw FormatException('$label contains an invalid endpoint.');
    }
    return (x, y);
  }

  return (point(pair[0]), point(pair[1]));
}

_Node _resolveEndpoint(
  Map<String, List<_Node>> nodesByCoordinate,
  (double, double) endpoint, {
  required int expectedLayerFlag,
}) {
  final candidates =
      nodesByCoordinate[_coordinateKey(endpoint.$1, endpoint.$2)] ??
      const <_Node>[];
  final matches = candidates
      .where((node) => node.sourceLayerFlag == expectedLayerFlag)
      .toList(growable: false);
  if (matches.isEmpty) {
    throw FormatException(
      'Endpoint ${endpoint.$1},${endpoint.$2} resolved to '
      '${matches.length} layer-$expectedLayerFlag nodes.',
    );
  }
  return _preferredNode(matches);
}

_Node _preferredNode(Iterable<_Node> candidates) {
  return candidates.reduce((first, second) {
    final firstUnknown = first.rawName.toLowerCase() == 'unknown';
    final secondUnknown = second.rawName.toLowerCase() == 'unknown';
    if (firstUnknown != secondUnknown) {
      return firstUnknown ? second : first;
    }
    return first.id < second.id ? first : second;
  });
}

void _attachParent(_Node production, _Node parent) {
  if (production.id == parent.id) {
    throw FormatException('Node ${production.id} cannot parent itself.');
  }
  production.parentId = parent.id;
  production.linkIds.add(parent.id);
  parent.linkIds.add(production.id);
}

void _validateNodeLinks(Map<int, _Node> nodes) {
  for (final node in nodes.values) {
    for (final linkId in node.linkIds) {
      final linked = nodes[linkId];
      if (linked == null) {
        throw FormatException('Node ${node.id} links to unknown node $linkId.');
      }
      if (!linked.linkIds.contains(node.id)) {
        throw FormatException('Node link ${node.id} / $linkId is asymmetric.');
      }
    }
  }
}

String _nodeType(_Node node) {
  if (node.sourceLayerFlag == 1) {
    return switch (node.iconType) {
      0 => 'Connection',
      1 => 'Town',
      2 => 'City',
      3 => 'Gateway',
      5 => 'Trading Post',
      9 => 'Dangerous',
      _ => throw FormatException(
        'Unknown exploration icon ${node.iconType} on node ${node.id}.',
      ),
    };
  }
  final name = node.rawName.toLowerCase();
  if (name.contains('investment bank')) return 'Bank';
  if (name.contains('specialties')) return 'Specialty';
  if (name.contains('workshop')) return 'Workshop';
  if (name.contains('fish drying yard')) return 'Fish Drying Yard';
  if (name.contains('mushroom')) return 'Mushrooms';
  if (name.contains('lumbering')) return 'Lumbering';
  if (name.contains('excavation')) return 'Excavation';
  if (name.contains('mining') || name.contains('quarry')) return 'Mining';
  if (name.contains('gathering')) return 'Gathering';
  if (name == 'unknown') return 'Connection';
  if (name.contains('farming') ||
      name.contains('production') ||
      const <String>{
        'date palm',
        'fig',
        'freekeh',
        'grapes',
        'nutmeg',
        'olives',
        'pistachio',
        'silk culture',
        'star anise',
        'teff',
      }.contains(name)) {
    return 'Farm';
  }
  return switch (node.iconType) {
    4 || 14 => 'Farm',
    6 => 'Gathering',
    7 => 'Mining',
    8 => 'Lumbering',
    11 => 'Fish Drying Yard',
    15 => 'Excavation',
    _ => throw FormatException(
      'Unknown production type "${node.rawName}" '
      '(icon ${node.iconType}) on node ${node.id}.',
    ),
  };
}

String _decodeHtml(String value) {
  var result = value
      .replaceAll('&amp;', '&')
      .replaceAll('&quot;', '"')
      .replaceAll('&#39;', "'")
      .replaceAll('&#039;', "'")
      .replaceAll('&apos;', "'")
      .replaceAll('&nbsp;', ' ')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>');
  result = result.replaceAllMapped(RegExp(r'&#(x?[0-9a-fA-F]+);'), (match) {
    final raw = match.group(1)!;
    final radix = raw.startsWith('x') ? 16 : 10;
    final digits = raw.startsWith('x') ? raw.substring(1) : raw;
    final codePoint = int.tryParse(digits, radix: radix);
    return codePoint == null ? match.group(0)! : String.fromCharCode(codePoint);
  });
  return result;
}

String _nameKey(String value) =>
    value.toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim();

String _coordinateKey(double x, double y) =>
    '${x.toStringAsFixed(6)},${y.toStringAsFixed(6)}';

Map<String, dynamic> _map(Object? value, String label) {
  if (value is! Map<String, dynamic>) {
    throw FormatException('$label must be a JSON object.');
  }
  return value;
}

List<dynamic> _list(Object? value, String label) {
  if (value is! List<dynamic>) {
    throw FormatException('$label must be a JSON list.');
  }
  return value;
}

double? _number(Object? value) => switch (value) {
  int integer => integer.toDouble(),
  double number => number,
  _ => null,
};

int? _integer(Object? value) => switch (value) {
  int integer => integer,
  num number => number.round(),
  _ => null,
};

String? _option(List<String> arguments, String name) {
  final index = arguments.indexOf(name);
  if (index < 0 || index + 1 >= arguments.length) {
    return null;
  }
  return arguments[index + 1];
}

class _Product {
  const _Product({
    required this.itemId,
    required this.name,
    required this.iconPath,
  });

  final int itemId;
  final String name;
  final String iconPath;
}

class _Output {
  const _Output({
    required this.itemId,
    required this.name,
    required this.isPrimary,
  });

  final int itemId;
  final String name;
  final bool isPrimary;

  Map<String, Object?> toJson() => <String, Object?>{
    'itemId': itemId,
    'name': name,
    'isPrimary': isPrimary,
  };
}

class _Node {
  _Node({
    required this.id,
    required this.rawName,
    required this.iconType,
    required this.sourceLayerFlag,
    required this.pixelX,
    required this.pixelY,
    required this.contributionPoints,
    required this.outputs,
  });

  final int id;
  final String rawName;
  final int iconType;
  final int sourceLayerFlag;
  final double pixelX;
  final double pixelY;
  final int contributionPoints;
  final List<_Output> outputs;
  final Set<int> linkIds = <int>{};
  int? parentId;
  bool isProductionNode = false;
  String name = '';
  String nodeType = '';

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'name': name,
    'rawName': rawName,
    'nodeType': nodeType,
    'iconType': iconType,
    'sourceLayerFlag': sourceLayerFlag,
    'pixelX': pixelX,
    'pixelY': pixelY,
    'contributionPoints': contributionPoints,
    'linkIds': linkIds.toList()..sort(),
    'outputs': outputs.map((output) => output.toJson()).toList(growable: false),
    'isProductionNode': isProductionNode,
    'parentId': parentId,
  };
}

extension<T> on List<T> {
  T? elementAtOrNull(int index) => index < length ? this[index] : null;
}
