import 'dart:math' as math;

import 'map_geometry.dart';

enum BdoAcquisitionMode { workerNode, fieldGathering, hunting }

enum BdoGatheringVerification {
  independentSurvey,
  crossChecked,
  communityReported,
  stale,
}

enum BdoSearchKind {
  resource,
  fieldSource,
  workerNode,
  gatheringSpot,
  gatheringRoute,
}

enum BdoResourceSection {
  plantsWood,
  oresMinerals,
  meat,
  bloodHides,
  mushrooms,
  seafoodMarine,
  other,
}

enum BdoWorkerActivity {
  mining,
  farming,
  lumbering,
  gathering,
  fishing,
  excavation,
}

extension BdoWorkerActivityPresentation on BdoWorkerActivity {
  String get label => switch (this) {
    BdoWorkerActivity.mining => 'Mining',
    BdoWorkerActivity.farming => 'Farming',
    BdoWorkerActivity.lumbering => 'Lumbering',
    BdoWorkerActivity.gathering => 'Gathering',
    BdoWorkerActivity.fishing => 'Fishing',
    BdoWorkerActivity.excavation => 'Excavation',
  };
}

class BdoDatasetManifest {
  const BdoDatasetManifest({
    required this.schemaVersion,
    required this.datasetVersion,
    required this.generatedAt,
    required this.coordinateReference,
    required this.provenance,
  });

  final int schemaVersion;
  final String datasetVersion;
  final DateTime generatedAt;
  final String coordinateReference;
  final List<BdoProvenanceRecord> provenance;

  factory BdoDatasetManifest.fromJson(Map<String, Object?> json) {
    return BdoDatasetManifest(
      schemaVersion: json['schemaVersion']! as int,
      datasetVersion: json['datasetVersion']! as String,
      generatedAt: DateTime.parse(json['generatedAt']! as String),
      coordinateReference: json['coordinateReference']! as String,
      provenance: _jsonList(
        json['provenance'],
      ).map(BdoProvenanceRecord.fromJson).toList(growable: false),
    );
  }
}

class BdoProvenanceRecord {
  const BdoProvenanceRecord({
    required this.id,
    required this.title,
    required this.url,
    required this.license,
    required this.permittedUse,
    required this.attribution,
  });

  final String id;
  final String title;
  final Uri url;
  final String license;
  final String permittedUse;
  final String attribution;

  factory BdoProvenanceRecord.fromJson(Map<String, Object?> json) {
    return BdoProvenanceRecord(
      id: json['id']! as String,
      title: json['title']! as String,
      url: Uri.parse(json['url']! as String),
      license: json['license']! as String,
      permittedUse: json['permittedUse']! as String,
      attribution: json['attribution']! as String,
    );
  }
}

class BdoResourceDefinition {
  const BdoResourceDefinition({
    required this.id,
    required this.name,
    required this.category,
    required this.section,
    required this.aliases,
    required this.acquisitionModes,
    this.gameItemId,
  });

  final String id;
  final int? gameItemId;
  final String name;
  final String category;
  final BdoResourceSection section;
  final List<String> aliases;
  final Set<BdoAcquisitionMode> acquisitionModes;

  factory BdoResourceDefinition.fromJson(Map<String, Object?> json) {
    return BdoResourceDefinition(
      id: json['id']! as String,
      gameItemId: json['gameItemId'] as int?,
      name: json['name']! as String,
      category: json['category']! as String,
      section: _resourceSectionFromJson(json['section']! as String),
      aliases: _stringList(json['aliases']),
      acquisitionModes: _stringList(
        json['acquisitionModes'],
      ).map(_acquisitionModeFromJson).toSet(),
    );
  }
}

class BdoNodeOutput {
  const BdoNodeOutput({
    required this.resourceId,
    required this.name,
    required this.isPrimary,
    this.gameItemId,
  });

  final String resourceId;
  final int? gameItemId;
  final String name;
  final bool isPrimary;

  factory BdoNodeOutput.fromJson(Map<String, Object?> json) {
    return BdoNodeOutput(
      resourceId: json['resourceId']! as String,
      gameItemId: json['gameItemId'] as int?,
      name: json['name']! as String,
      isPrimary: json['isPrimary'] as bool? ?? false,
    );
  }
}

class BdoWorkerNode {
  const BdoWorkerNode({
    required this.id,
    required this.name,
    required this.nodeType,
    required this.region,
    required this.location,
    required this.contributionPoints,
    required this.linkIds,
    required this.outputs,
    required this.isResourceNode,
    this.isProductionNode = false,
    this.sourceIconType,
    this.sourceLayerFlag,
    this.parentId,
    this.workload,
    this.provenanceId,
  });

  final String id;
  final String name;
  final String nodeType;
  final String region;
  final BdoWorldPoint location;
  final int contributionPoints;
  final List<String> linkIds;
  final List<BdoNodeOutput> outputs;
  final bool isResourceNode;
  final bool isProductionNode;
  final int? sourceIconType;
  final int? sourceLayerFlag;
  final String? parentId;
  final String? workload;
  final String? provenanceId;

  Iterable<String> get resourceIds =>
      outputs.map((output) => output.resourceId);

  factory BdoWorkerNode.fromJson(Map<String, Object?> json) {
    return BdoWorkerNode(
      id: json['id']! as String,
      name: json['name']! as String,
      nodeType: json['nodeType']! as String,
      region: json['region'] as String? ?? '',
      location: BdoWorldPoint(
        (json['x']! as num).toDouble(),
        (json['z']! as num).toDouble(),
      ),
      contributionPoints: json['contributionPoints'] as int? ?? 0,
      linkIds: _stringList(json['linkIds']),
      outputs: _jsonList(
        json['outputs'],
      ).map(BdoNodeOutput.fromJson).toList(growable: false),
      isResourceNode: json['isResourceNode'] as bool? ?? false,
      isProductionNode: json['isProductionNode'] as bool? ?? false,
      sourceIconType: json['sourceIconType'] as int?,
      sourceLayerFlag: json['sourceLayerFlag'] as int?,
      parentId: json['parentId'] as String?,
      workload: json['workload'] as String?,
      provenanceId: json['provenanceId'] as String?,
    );
  }
}

const int bdoNodeIconTypeMinimum = 0;
const int bdoNodeIconTypeMaximum = 15;
const String bdoNodeIconAssetDirectory = 'assets/images/node_icons';

const Set<String> _topologyOnlyWorkerNodeTypes = <String>{
  'City',
  'Connection',
  'Dangerous',
  'Gateway',
  'Town',
  'Trading Post',
};

String bdoNodeIconAssetPath(
  int sourceIconType, {
  required bool active,
  bool highlighted = false,
}) {
  if (sourceIconType < bdoNodeIconTypeMinimum ||
      sourceIconType > bdoNodeIconTypeMaximum) {
    throw RangeError.range(
      sourceIconType,
      bdoNodeIconTypeMinimum,
      bdoNodeIconTypeMaximum,
      'sourceIconType',
    );
  }
  final highlightDirectory = highlighted ? 'highlighted/' : '';
  final stateDirectory = active ? '' : 'gray/';
  return '$bdoNodeIconAssetDirectory/'
      '$highlightDirectory$stateDirectory$sourceIconType.png';
}

extension BdoWorkerNodePresentation on BdoWorkerNode {
  int? get supportedSourceIconType {
    final value = sourceIconType;
    return value != null &&
            value >= bdoNodeIconTypeMinimum &&
            value <= bdoNodeIconTypeMaximum
        ? value
        : null;
  }

  String? nodeIconAssetPath({required bool active, bool highlighted = false}) {
    final type = supportedSourceIconType;
    return type == null
        ? null
        : bdoNodeIconAssetPath(type, active: active, highlighted: highlighted);
  }

  bool get isNaturalWorkerRoot =>
      contributionPoints == 0 && (nodeType == 'City' || nodeType == 'Town');

  bool get _isKnownTopologyOnlyNode =>
      !isResourceNode &&
      !isProductionNode &&
      outputs.isEmpty &&
      _topologyOnlyWorkerNodeTypes.contains(nodeType);

  BdoWorkerActivity get activity => switch (nodeType) {
    'Excavation' => BdoWorkerActivity.excavation,
    'Farm' => BdoWorkerActivity.farming,
    'Fish Drying Yard' || 'Fishing' => BdoWorkerActivity.fishing,
    'Forest' || 'Lumbering' => BdoWorkerActivity.lumbering,
    'Gathering' || 'Mushrooms' => BdoWorkerActivity.gathering,
    'Mining' => BdoWorkerActivity.mining,
    'Mine' => _legacyMineActivity,
    // Topology-only nodes do not perform worker production. Some shared
    // presentation surfaces still need a non-null activity style, so use the
    // existing neutral-looking layers treatment without relabelling the node.
    // The strict flags/output gate keeps malformed production data fail-closed.
    _ when _isKnownTopologyOnlyNode => BdoWorkerActivity.excavation,
    _ => throw FormatException(
      'Unknown worker-node type "$nodeType" for node "$id" ($name).',
    ),
  };

  BdoWorkerActivity get _legacyMineActivity {
    final separator = name.lastIndexOf(' - ');
    final productionType = separator < 0
        ? name.trim()
        : name.substring(separator + 3).trim();
    return switch (productionType) {
      'Excavation' => BdoWorkerActivity.excavation,
      'Mining' || 'Titanium' || 'Vanadium' => BdoWorkerActivity.mining,
      _ => throw FormatException(
        'Unknown Mine activity "$productionType" for node "$id" ($name).',
      ),
    };
  }

  String get siteName {
    final separator = name.lastIndexOf(' - ');
    return separator <= 0 ? name : name.substring(0, separator).trim();
  }

  String get activityLabel =>
      _isKnownTopologyOnlyNode ? nodeType : activity.label;
}

class BdoGatheringTarget {
  const BdoGatheringTarget({
    required this.name,
    required this.tool,
    required this.resourceIds,
    this.gameNpcIds = const <int>[],
  });

  final String name;
  final String tool;
  final List<String> resourceIds;
  final List<int> gameNpcIds;

  factory BdoGatheringTarget.fromJson(Map<String, Object?> json) {
    return BdoGatheringTarget(
      name: json['name']! as String,
      tool: json['tool']! as String,
      resourceIds: _stringList(json['resourceIds']),
      gameNpcIds: (json['gameNpcIds'] as List<Object?>? ?? const <Object?>[])
          .cast<int>(),
    );
  }
}

class BdoGatheringWaypoint {
  const BdoGatheringWaypoint({
    required this.order,
    required this.location,
    required this.kind,
    required this.label,
    required this.targets,
  });

  final int order;
  final BdoWorldPoint location;
  final String kind;
  final String label;
  final List<String> targets;

  factory BdoGatheringWaypoint.fromJson(Map<String, Object?> json) {
    return BdoGatheringWaypoint(
      order: json['order']! as int,
      location: BdoWorldPoint(
        (json['x']! as num).toDouble(),
        (json['z']! as num).toDouble(),
      ),
      kind: json['kind']! as String,
      label: json['label'] as String? ?? '',
      targets: _stringList(json['targets']),
    );
  }
}

class BdoGatheringSpot {
  const BdoGatheringSpot({
    required this.id,
    required this.name,
    required this.region,
    required this.nearestNode,
    required this.location,
    required this.resourceIds,
    required this.targets,
    required this.quality,
    required this.summary,
    required this.verification,
    required this.provenanceId,
    this.fieldSourceIds = const <String>[],
    this.radiusWorld,
    this.verifiedAt,
  }) : assert(radiusWorld == null || radiusWorld > 0);

  final String id;
  final String name;
  final String region;
  final String nearestNode;
  final BdoWorldPoint location;
  final List<String> resourceIds;
  final List<BdoGatheringTarget> targets;
  final String quality;
  final String summary;
  final BdoGatheringVerification verification;
  final String provenanceId;
  final List<String> fieldSourceIds;
  final double? radiusWorld;
  final DateTime? verifiedAt;

  BdoMapBounds? get areaBounds {
    final radius = radiusWorld;
    if (radius == null) {
      return null;
    }
    final center = location.mapPoint;
    return BdoMapBounds(
      left: center.x - radius,
      top: center.y - radius,
      right: center.x + radius,
      bottom: center.y + radius,
    );
  }

  factory BdoGatheringSpot.fromJson(Map<String, Object?> json) {
    return BdoGatheringSpot(
      id: json['id']! as String,
      name: json['name']! as String,
      region: json['region']! as String,
      nearestNode: json['nearestNode'] as String? ?? '',
      location: BdoWorldPoint(
        (json['x']! as num).toDouble(),
        (json['z']! as num).toDouble(),
      ),
      resourceIds: _stringList(json['resourceIds']),
      targets: _jsonList(
        json['targets'],
      ).map(BdoGatheringTarget.fromJson).toList(growable: false),
      quality: json['quality'] as String? ?? 'alternative',
      summary: json['summary'] as String? ?? '',
      verification: _verificationFromJson(json['verification']! as String),
      provenanceId: json['provenanceId']! as String,
      fieldSourceIds: _stringList(json['fieldSourceIds']),
      verifiedAt: json['verifiedAt'] == null
          ? null
          : DateTime.parse(json['verifiedAt']! as String),
      radiusWorld: (json['radiusWorld'] as num?)?.toDouble(),
    );
  }
}

class BdoGatheringPoint {
  const BdoGatheringPoint({
    required this.id,
    required this.location,
    required this.resourceIds,
    required this.target,
    required this.kind,
    required this.label,
    required this.verification,
    required this.provenanceId,
    this.fieldSourceIds = const <String>[],
    this.areaId,
    this.verifiedAt,
  });

  final String id;
  final BdoWorldPoint location;
  final List<String> resourceIds;
  final String target;
  final String kind;
  final String label;
  final BdoGatheringVerification verification;
  final String provenanceId;
  final List<String> fieldSourceIds;
  final String? areaId;
  final DateTime? verifiedAt;

  factory BdoGatheringPoint.fromJson(Map<String, Object?> json) {
    return BdoGatheringPoint(
      id: json['id']! as String,
      location: BdoWorldPoint(
        (json['x']! as num).toDouble(),
        (json['z']! as num).toDouble(),
      ),
      resourceIds: _stringList(json['resourceIds']),
      target: json['target']! as String,
      kind: json['kind']! as String,
      label: json['label']! as String,
      verification: _verificationFromJson(json['verification']! as String),
      provenanceId: json['provenanceId']! as String,
      fieldSourceIds: _stringList(json['fieldSourceIds']),
      areaId: json['areaId'] as String?,
      verifiedAt: json['verifiedAt'] == null
          ? null
          : DateTime.parse(json['verifiedAt']! as String),
    );
  }
}

class BdoGatheringRoute {
  const BdoGatheringRoute({
    required this.id,
    required this.spotId,
    required this.name,
    required this.region,
    required this.resourceIds,
    required this.tool,
    required this.loop,
    required this.summary,
    required this.waypoints,
    required this.verification,
    required this.provenanceId,
    this.verifiedAt,
  });

  final String id;
  final String spotId;
  final String name;
  final String region;
  final List<String> resourceIds;
  final String tool;
  final bool loop;
  final String summary;
  final List<BdoGatheringWaypoint> waypoints;
  final BdoGatheringVerification verification;
  final String provenanceId;
  final DateTime? verifiedAt;

  BdoMapBounds get bounds {
    final points = waypoints.map((point) => point.location.mapPoint).toList();
    if (points.isEmpty) {
      return const BdoMapBounds(left: -1, top: -1, right: 1, bottom: 1);
    }
    var left = points.first.x;
    var top = points.first.y;
    var right = points.first.x;
    var bottom = points.first.y;
    for (final point in points.skip(1)) {
      left = math.min(left, point.x);
      top = math.min(top, point.y);
      right = math.max(right, point.x);
      bottom = math.max(bottom, point.y);
    }
    if (left == right) {
      left -= 1;
      right += 1;
    }
    if (top == bottom) {
      top -= 1;
      bottom += 1;
    }
    return BdoMapBounds(left: left, top: top, right: right, bottom: bottom);
  }

  factory BdoGatheringRoute.fromJson(Map<String, Object?> json) {
    return BdoGatheringRoute(
      id: json['id']! as String,
      spotId: json['spotId']! as String,
      name: json['name']! as String,
      region: json['region']! as String,
      resourceIds: _stringList(json['resourceIds']),
      tool: json['tool']! as String,
      loop: json['loop'] as bool? ?? true,
      summary: json['summary'] as String? ?? '',
      waypoints: _jsonList(
        json['waypoints'],
      ).map(BdoGatheringWaypoint.fromJson).toList(growable: false),
      verification: _verificationFromJson(json['verification']! as String),
      provenanceId: json['provenanceId']! as String,
      verifiedAt: json['verifiedAt'] == null
          ? null
          : DateTime.parse(json['verifiedAt']! as String),
    );
  }
}

class BdoFieldProduct {
  const BdoFieldProduct({
    required this.resourceId,
    required this.method,
    required this.tool,
    required this.instruction,
  });

  final String resourceId;
  final String method;
  final String tool;
  final String instruction;

  factory BdoFieldProduct.fromJson(Map<String, Object?> json) {
    return BdoFieldProduct(
      resourceId: json['resourceId']! as String,
      method: json['method']! as String,
      tool: json['tool']! as String,
      instruction: json['instruction']! as String,
    );
  }
}

class BdoFieldSource {
  const BdoFieldSource({
    required this.id,
    required this.name,
    required this.category,
    required this.aliases,
    required this.summary,
    required this.note,
    required this.products,
  });

  final String id;
  final String name;
  final String category;
  final List<String> aliases;
  final String summary;
  final String note;
  final List<BdoFieldProduct> products;

  Iterable<String> get resourceIds =>
      products.map((product) => product.resourceId).toSet();

  factory BdoFieldSource.fromJson(Map<String, Object?> json) {
    return BdoFieldSource(
      id: json['id']! as String,
      name: json['name']! as String,
      category: json['category']! as String,
      aliases: _stringList(json['aliases']),
      summary: json['summary'] as String? ?? '',
      note: json['note'] as String? ?? '',
      products: _jsonList(
        json['products'],
      ).map(BdoFieldProduct.fromJson).toList(growable: false),
    );
  }
}

class BdoSearchResult {
  const BdoSearchResult({
    required this.kind,
    required this.id,
    required this.title,
    required this.subtitle,
    required this.searchText,
    this.location,
    this.bounds,
    this.resourceId,
    this.fieldSourceId,
  });

  final BdoSearchKind kind;
  final String id;
  final String title;
  final String subtitle;
  final String searchText;
  final BdoWorldPoint? location;
  final BdoMapBounds? bounds;
  final String? resourceId;
  final String? fieldSourceId;
}

class BdoVendorNpc {
  const BdoVendorNpc({
    required this.id,
    required this.sourceVendorId,
    required this.gameNpcId,
    required this.spawnId,
    required this.name,
    required this.role,
    required this.location,
    required this.sourceUrl,
    required this.reviewedAt,
    required this.verification,
    required this.provenanceId,
  });

  final String id;
  final String sourceVendorId;
  final int gameNpcId;
  final int spawnId;
  final String name;
  final String role;
  final BdoWorldPoint location;
  final Uri sourceUrl;
  final DateTime reviewedAt;
  final String verification;
  final String provenanceId;

  factory BdoVendorNpc.fromJson(Map<String, Object?> json) {
    return BdoVendorNpc(
      id: json['id']! as String,
      sourceVendorId: json['sourceVendorId']! as String,
      gameNpcId: json['gameNpcId']! as int,
      spawnId: json['spawnId']! as int,
      name: json['name']! as String,
      role: json['role']! as String,
      location: BdoWorldPoint(
        (json['x']! as num).toDouble(),
        (json['z']! as num).toDouble(),
      ),
      sourceUrl: Uri.parse(json['sourceUrl']! as String),
      reviewedAt: DateTime.parse(json['reviewedAt']! as String),
      verification: json['verification']! as String,
      provenanceId: json['provenanceId']! as String,
    );
  }
}

class BdoVendorListing {
  const BdoVendorListing({
    required this.itemId,
    required this.itemName,
    required this.vendorId,
    required this.priceSilver,
    required this.provenanceId,
  });

  final int itemId;
  final String itemName;
  final String vendorId;
  final int priceSilver;
  final String provenanceId;

  factory BdoVendorListing.fromJson(Map<String, Object?> json) {
    return BdoVendorListing(
      itemId: json['itemId']! as int,
      itemName: json['itemName']! as String,
      vendorId: json['vendorId']! as String,
      priceSilver: json['priceSilver']! as int,
      provenanceId: json['provenanceId']! as String,
    );
  }
}

class BdoResourceMapDataset {
  BdoResourceMapDataset({
    required this.manifest,
    required this.resources,
    required this.workerNodes,
    required this.gatheringSpots,
    required this.gatheringRoutes,
    this.gatheringPoints = const <BdoGatheringPoint>[],
    this.fieldSources = const <BdoFieldSource>[],
    this.vendorNpcs = const <BdoVendorNpc>[],
    this.vendorListings = const <BdoVendorListing>[],
  }) : resourcesById = <String, BdoResourceDefinition>{
         for (final resource in resources) resource.id: resource,
       },
       workerNodesById = <String, BdoWorkerNode>{
         for (final node in workerNodes) node.id: node,
       },
       gatheringSpotsById = <String, BdoGatheringSpot>{
         for (final spot in gatheringSpots) spot.id: spot,
       },
       gatheringPointsById = <String, BdoGatheringPoint>{
         for (final point in gatheringPoints) point.id: point,
       },
       gatheringRoutesById = <String, BdoGatheringRoute>{
         for (final route in gatheringRoutes) route.id: route,
       },
       fieldSourcesById = <String, BdoFieldSource>{
         for (final source in fieldSources) source.id: source,
       },
       vendorNpcsById = <String, BdoVendorNpc>{
         for (final vendor in vendorNpcs) vendor.id: vendor,
       } {
    _workerNodesByResource = _buildResourceIndex(
      workerNodes.where((node) => node.isResourceNode),
      (node) => node.outputs.map((output) => output.resourceId),
    );
    _gatheringSpotsByResource = _buildResourceIndex(
      gatheringSpots,
      (spot) => spot.resourceIds,
    );
    _gatheringSpotsByFieldSource = <String, List<BdoGatheringSpot>>{
      for (final source in fieldSources)
        source.id: List<BdoGatheringSpot>.unmodifiable(
          gatheringSpots.where(
            (spot) => spot.fieldSourceIds.contains(source.id),
          ),
        ),
    };
    _gatheringPointsByResource = _buildResourceIndex(
      gatheringPoints,
      (point) => point.resourceIds,
    );
    _gatheringRoutesByResource = _buildResourceIndex(
      gatheringRoutes,
      (route) => route.resourceIds,
    );
    _fieldSourcesByResource = _buildResourceIndex(
      fieldSources,
      (source) => source.resourceIds,
    );
    _gatheringPointsByFieldSource = <String, List<BdoGatheringPoint>>{
      for (final source in fieldSources)
        source.id: List<BdoGatheringPoint>.unmodifiable(
          gatheringPoints
              .where((point) => point.fieldSourceIds.contains(source.id))
              .toList(growable: false),
        ),
    };
    _resourcesBySection =
        Map<BdoResourceSection, List<BdoResourceDefinition>>.unmodifiable(
          _buildResourceIndex(
            resources,
            (resource) => <String>[resource.section.name],
          ).map(
            (section, resources) =>
                MapEntry(BdoResourceSection.values.byName(section), resources),
          ),
        );
    _vendorListingsByItemId = _buildResourceIndex(
      vendorListings,
      (listing) => <String>[listing.itemId.toString()],
    ).map((itemId, listings) => MapEntry(int.parse(itemId), listings));
    _vendorListingsByItemName = _buildResourceIndex(
      vendorListings,
      (listing) => <String>[_normalize(listing.itemName)],
    );
    _vendorListingsByVendorId = _buildResourceIndex(
      vendorListings,
      (listing) => <String>[listing.vendorId],
    );
    for (final listing in vendorListings) {
      if (!vendorNpcsById.containsKey(listing.vendorId)) {
        throw FormatException(
          'Vendor listing ${listing.itemName} references missing vendor '
          '${listing.vendorId}.',
        );
      }
    }
    _searchIndex = _buildSearchIndex();
  }

  final BdoDatasetManifest manifest;
  final List<BdoResourceDefinition> resources;
  final List<BdoWorkerNode> workerNodes;
  final List<BdoGatheringSpot> gatheringSpots;
  final List<BdoGatheringPoint> gatheringPoints;
  final List<BdoGatheringRoute> gatheringRoutes;
  final List<BdoFieldSource> fieldSources;
  final List<BdoVendorNpc> vendorNpcs;
  final List<BdoVendorListing> vendorListings;
  final Map<String, BdoResourceDefinition> resourcesById;
  final Map<String, BdoWorkerNode> workerNodesById;
  final Map<String, BdoGatheringSpot> gatheringSpotsById;
  final Map<String, BdoGatheringPoint> gatheringPointsById;
  final Map<String, BdoGatheringRoute> gatheringRoutesById;
  final Map<String, BdoFieldSource> fieldSourcesById;
  final Map<String, BdoVendorNpc> vendorNpcsById;
  late final Map<String, List<BdoWorkerNode>> _workerNodesByResource;
  late final Map<String, List<BdoGatheringSpot>> _gatheringSpotsByResource;
  late final Map<String, List<BdoGatheringSpot>> _gatheringSpotsByFieldSource;
  late final Map<String, List<BdoGatheringPoint>> _gatheringPointsByResource;
  late final Map<String, List<BdoGatheringRoute>> _gatheringRoutesByResource;
  late final Map<String, List<BdoFieldSource>> _fieldSourcesByResource;
  late final Map<String, List<BdoGatheringPoint>> _gatheringPointsByFieldSource;
  late final Map<BdoResourceSection, List<BdoResourceDefinition>>
  _resourcesBySection;
  late final Map<int, List<BdoVendorListing>> _vendorListingsByItemId;
  late final Map<String, List<BdoVendorListing>> _vendorListingsByItemName;
  late final Map<String, List<BdoVendorListing>> _vendorListingsByVendorId;
  late final List<BdoSearchResult> _searchIndex;

  factory BdoResourceMapDataset.fromJson(Map<String, Object?> json) {
    return BdoResourceMapDataset(
      manifest: BdoDatasetManifest.fromJson(
        json['manifest']! as Map<String, Object?>,
      ),
      resources: _jsonList(
        json['resources'],
      ).map(BdoResourceDefinition.fromJson).toList(growable: false),
      workerNodes: _jsonList(
        json['workerNodes'],
      ).map(BdoWorkerNode.fromJson).toList(growable: false),
      gatheringSpots: _jsonList(
        json['gatheringSpots'],
      ).map(BdoGatheringSpot.fromJson).toList(growable: false),
      gatheringPoints: _jsonList(
        json['gatheringPoints'],
      ).map(BdoGatheringPoint.fromJson).toList(growable: false),
      gatheringRoutes: _jsonList(
        json['gatheringRoutes'],
      ).map(BdoGatheringRoute.fromJson).toList(growable: false),
      fieldSources: _jsonList(
        json['fieldSources'],
      ).map(BdoFieldSource.fromJson).toList(growable: false),
      vendorNpcs: _jsonList(
        json['vendorNpcs'],
      ).map(BdoVendorNpc.fromJson).toList(growable: false),
      vendorListings: _jsonList(
        json['vendorListings'],
      ).map(BdoVendorListing.fromJson).toList(growable: false),
    );
  }

  List<BdoVendorListing> vendorListingsForItem(String itemName, {int? itemId}) {
    final byId = itemId == null ? null : _vendorListingsByItemId[itemId];
    if (byId != null && byId.isNotEmpty) {
      return byId;
    }
    return _vendorListingsByItemName[_normalize(itemName)] ??
        const <BdoVendorListing>[];
  }

  List<BdoVendorNpc> vendorNpcsForItem(String itemName, {int? itemId}) {
    final seen = <String>{};
    return <BdoVendorNpc>[
      for (final listing in vendorListingsForItem(itemName, itemId: itemId))
        if (seen.add(listing.vendorId)) vendorNpcsById[listing.vendorId]!,
    ];
  }

  List<BdoVendorListing> vendorListingsForVendor(String vendorId) {
    return _vendorListingsByVendorId[vendorId] ?? const <BdoVendorListing>[];
  }

  Iterable<BdoWorkerNode> workerNodesForResource(String resourceId) {
    return _workerNodesByResource[resourceId] ?? const <BdoWorkerNode>[];
  }

  Iterable<BdoGatheringSpot> gatheringSpotsForResource(String resourceId) {
    return _gatheringSpotsByResource[resourceId] ?? const <BdoGatheringSpot>[];
  }

  Iterable<BdoGatheringSpot> gatheringSpotsForFieldSource(String sourceId) {
    return _gatheringSpotsByFieldSource[sourceId] ?? const <BdoGatheringSpot>[];
  }

  Iterable<BdoGatheringPoint> gatheringPointsForResource(String resourceId) {
    return _gatheringPointsByResource[resourceId] ??
        const <BdoGatheringPoint>[];
  }

  Iterable<BdoGatheringRoute> gatheringRoutesForResource(String resourceId) {
    return _gatheringRoutesByResource[resourceId] ??
        const <BdoGatheringRoute>[];
  }

  Iterable<BdoFieldSource> fieldSourcesForResource(String resourceId) {
    return _fieldSourcesByResource[resourceId] ?? const <BdoFieldSource>[];
  }

  Iterable<BdoGatheringPoint> gatheringPointsForFieldSource(String sourceId) {
    return _gatheringPointsByFieldSource[sourceId] ??
        const <BdoGatheringPoint>[];
  }

  List<BdoResourceDefinition> resourcesForSection(BdoResourceSection section) {
    return _resourcesBySection[section] ?? const <BdoResourceDefinition>[];
  }

  bool hasMappedManualSource(String resourceId) {
    return _gatheringSpotsByResource.containsKey(resourceId) ||
        _gatheringPointsByResource.containsKey(resourceId) ||
        _gatheringRoutesByResource.containsKey(resourceId);
  }

  bool hasWorkerSource(String resourceId) {
    return _workerNodesByResource.containsKey(resourceId);
  }

  List<BdoSearchResult> search(
    String query, {
    int limit = 40,
    bool includeWorkerNodes = true,
    bool includeFieldSources = true,
    bool includeGatheringSpots = true,
    bool includeGatheringRoutes = true,
  }) {
    final normalized = _normalize(query);
    if (normalized.isEmpty) {
      return const <BdoSearchResult>[];
    }
    final tokens = normalized
        .split(' ')
        .where((token) => token.isNotEmpty)
        .toList(growable: false);
    final scored = <({BdoSearchResult result, int score})>[];
    for (final result in _searchIndex) {
      if (!includeFieldSources && result.kind == BdoSearchKind.fieldSource) {
        continue;
      }
      if (!includeWorkerNodes && result.kind == BdoSearchKind.workerNode) {
        continue;
      }
      if (!includeGatheringSpots &&
          result.kind == BdoSearchKind.gatheringSpot) {
        continue;
      }
      if (!includeGatheringRoutes &&
          result.kind == BdoSearchKind.gatheringRoute) {
        continue;
      }
      final text = result.searchText;
      var score = 0;
      if (text == normalized) {
        score += 1000;
      } else if (text.startsWith(normalized)) {
        score += 600;
      } else if (text.contains(normalized)) {
        score += 350;
      }
      if (!tokens.every(text.contains)) {
        continue;
      }
      score += tokens.length * 35;
      if (result.kind == BdoSearchKind.resource) {
        score += 60;
      } else if (result.kind == BdoSearchKind.fieldSource) {
        score += 380;
      }
      scored.add((result: result, score: score));
    }
    scored.sort((a, b) {
      final byScore = b.score.compareTo(a.score);
      return byScore != 0 ? byScore : a.result.title.compareTo(b.result.title);
    });
    return scored.take(limit).map((entry) => entry.result).toList();
  }

  List<BdoSearchResult> _buildSearchIndex() {
    final index = <BdoSearchResult>[];
    for (final resource in resources) {
      final workerCount = workerNodesForResource(resource.id).length;
      final gatheringCount = gatheringSpotsForResource(resource.id).length;
      final gatheringPointCount = gatheringPointsForResource(
        resource.id,
      ).length;
      index.add(
        BdoSearchResult(
          kind: BdoSearchKind.resource,
          id: resource.id,
          title: resource.name,
          subtitle: _resourceSubtitle(
            workerCount,
            gatheringCount,
            gatheringPointCount,
          ),
          searchText: _normalize(
            <String>[
              resource.name,
              ...resource.aliases,
              resource.category,
            ].join(' '),
          ),
          resourceId: resource.id,
        ),
      );
    }
    for (final source in fieldSources) {
      final sourcePoints = gatheringPointsForFieldSource(source.id).length;
      final productNames = source.products
          .map((product) => resourcesById[product.resourceId]?.name)
          .whereType<String>()
          .toSet()
          .toList(growable: false);
      index.add(
        BdoSearchResult(
          kind: BdoSearchKind.fieldSource,
          id: source.id,
          title: source.name,
          subtitle: <String>[
            if (productNames.isNotEmpty) productNames.join(', '),
            if (sourcePoints > 0)
              '$sourcePoints recorded '
                  '${sourcePoints == 1 ? 'location' : 'locations'}',
          ].join(' · '),
          searchText: _normalize(
            <String>[
              source.name,
              ...source.aliases,
              source.category,
              source.summary,
              source.note,
              for (final product in source.products) ...<String>[
                resourcesById[product.resourceId]?.name ?? product.resourceId,
                ...?resourcesById[product.resourceId]?.aliases,
                product.method,
                product.tool,
                product.instruction,
              ],
            ].join(' '),
          ),
          fieldSourceId: source.id,
        ),
      );
    }
    for (final node in workerNodes) {
      index.add(
        BdoSearchResult(
          kind: BdoSearchKind.workerNode,
          id: node.id,
          title: _workerNodeSearchTitle(node),
          subtitle: <String>[
            if (node.region.isNotEmpty) node.region,
            node.outputs.map((output) => output.name).join(', '),
          ].join(' · '),
          searchText: _normalize(
            <String>[
              node.name,
              node.siteName,
              if (node.isResourceNode) node.activityLabel,
              node.region,
              node.nodeType,
              ...node.outputs.map((output) => output.name),
            ].join(' '),
          ),
          location: node.location,
        ),
      );
    }
    for (final spot in gatheringSpots) {
      index.add(
        BdoSearchResult(
          kind: BdoSearchKind.gatheringSpot,
          id: spot.id,
          title: spot.name,
          subtitle:
              '${spot.region} · ${spot.targets.map((e) => e.name).join(', ')}',
          searchText: _normalize(
            <String>[
              spot.name,
              spot.region,
              spot.nearestNode,
              ...spot.targets.map((target) => target.name),
              ...spot.resourceIds.map((id) => resourcesById[id]?.name ?? id),
            ].join(' '),
          ),
          location: spot.areaBounds == null ? spot.location : null,
          bounds: spot.areaBounds,
        ),
      );
    }
    for (final route in gatheringRoutes) {
      index.add(
        BdoSearchResult(
          kind: BdoSearchKind.gatheringRoute,
          id: route.id,
          title: route.name,
          subtitle: '${route.region} · ${route.tool}',
          searchText: _normalize(
            <String>[
              route.name,
              route.region,
              route.tool,
              ...route.resourceIds.map((id) => resourcesById[id]?.name ?? id),
            ].join(' '),
          ),
          bounds: route.bounds,
        ),
      );
    }
    return List<BdoSearchResult>.unmodifiable(index);
  }
}

String _resourceSubtitle(
  int workerCount,
  int gatheringCount,
  int gatheringPointCount,
) {
  final parts = <String>[
    if (workerCount > 0)
      '$workerCount worker ${workerCount == 1 ? 'node' : 'nodes'}',
    if (gatheringCount > 0)
      '$gatheringCount gathering ${gatheringCount == 1 ? 'area' : 'areas'}',
    if (gatheringPointCount > 0)
      '$gatheringPointCount exact gathering '
          '${gatheringPointCount == 1 ? 'location' : 'locations'}',
  ];
  return parts.isEmpty ? 'Resource' : parts.join(' · ');
}

String _workerNodeSearchTitle(BdoWorkerNode node) {
  for (final output in node.outputs) {
    if (output.isPrimary) {
      return '${output.name} · ${node.siteName}';
    }
  }
  return node.outputs.isEmpty
      ? node.isResourceNode
            ? '${node.siteName} · ${node.activityLabel}'
            : node.name
      : '${node.outputs.first.name} · ${node.siteName}';
}

String _normalize(String value) {
  return value
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'[àáâãäåāăą]'), 'a')
      .replaceAll('æ', 'ae')
      .replaceAll(RegExp(r'[çćč]'), 'c')
      .replaceAll(RegExp(r'[ďđ]'), 'd')
      .replaceAll(RegExp(r'[èéêëēėę]'), 'e')
      .replaceAll(RegExp(r'[ìíîïīį]'), 'i')
      .replaceAll('ł', 'l')
      .replaceAll(RegExp(r'[ñń]'), 'n')
      .replaceAll(RegExp(r'[òóôõöøō]'), 'o')
      .replaceAll('œ', 'oe')
      .replaceAll('ř', 'r')
      .replaceAll(RegExp(r'[śšş]'), 's')
      .replaceAll('ß', 'ss')
      .replaceAll('ť', 't')
      .replaceAll(RegExp(r'[ùúûüū]'), 'u')
      .replaceAll(RegExp(r'[ýÿ]'), 'y')
      .replaceAll(RegExp(r'[žźż]'), 'z')
      .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ');
}

List<Map<String, Object?>> _jsonList(Object? value) {
  return (value as List<Object?>? ?? const <Object?>[])
      .cast<Map<String, Object?>>();
}

List<String> _stringList(Object? value) {
  return (value as List<Object?>? ?? const <Object?>[]).cast<String>();
}

Map<String, List<T>> _buildResourceIndex<T>(
  Iterable<T> records,
  Iterable<String> Function(T record) resourceIdsFor,
) {
  final mutableIndex = <String, List<T>>{};
  for (final record in records) {
    for (final resourceId in resourceIdsFor(record).toSet()) {
      (mutableIndex[resourceId] ??= <T>[]).add(record);
    }
  }
  return Map<String, List<T>>.unmodifiable(<String, List<T>>{
    for (final entry in mutableIndex.entries)
      entry.key: List<T>.unmodifiable(entry.value),
  });
}

BdoAcquisitionMode _acquisitionModeFromJson(String value) {
  return switch (value) {
    'workerNode' => BdoAcquisitionMode.workerNode,
    'fieldGathering' => BdoAcquisitionMode.fieldGathering,
    'hunting' => BdoAcquisitionMode.hunting,
    _ => throw FormatException('Unknown acquisition mode: $value'),
  };
}

BdoResourceSection _resourceSectionFromJson(String value) {
  return switch (value) {
    'plantsWood' => BdoResourceSection.plantsWood,
    'oresMinerals' => BdoResourceSection.oresMinerals,
    'meat' => BdoResourceSection.meat,
    'bloodHides' => BdoResourceSection.bloodHides,
    'mushrooms' => BdoResourceSection.mushrooms,
    'seafoodMarine' => BdoResourceSection.seafoodMarine,
    'other' => BdoResourceSection.other,
    _ => throw FormatException('Unknown resource section: $value'),
  };
}

BdoGatheringVerification _verificationFromJson(String value) {
  return switch (value) {
    'independentSurvey' => BdoGatheringVerification.independentSurvey,
    'crossChecked' => BdoGatheringVerification.crossChecked,
    'communityReported' => BdoGatheringVerification.communityReported,
    'stale' => BdoGatheringVerification.stale,
    _ => throw FormatException('Unknown verification status: $value'),
  };
}
