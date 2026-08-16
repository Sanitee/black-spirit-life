import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import '../lodging/lodging_data.dart';
import '../model/map_geometry.dart';
import '../model/resource_map_data.dart';
import '../network/node_network_preferences.dart';

/// The kind of known map record sampled from an aligned in-game screenshot.
enum BdoScreenshotTargetKind { workerNode, house }

/// The visual state suggested by a screenshot marker region.
///
/// Results are recommendations for an import review screen. The analyzer does
/// not mutate a node network or housing setup.
enum BdoScreenshotTargetState { active, inactive, uncertain, outsideViewport }

enum BdoScreenshotAlignmentKind { similarity, affine }

/// Explains why a screenshot suggestion still needs attention.
enum BdoScreenshotReviewReason {
  lowAlignmentConfidence,
  lowConfidence,
  insufficientVisualEvidence,
  conflictingVisualEvidence,
  overlappingTargets,
  ambiguousHouseUsage,
}

/// An RGBA screenshot decoded by the application host.
final class BdoScreenshotRaster {
  BdoScreenshotRaster({
    required this.width,
    required this.height,
    required Uint8List rgbaBytes,
  }) : rgbaBytes = Uint8List.fromList(rgbaBytes) {
    if (width <= 0 || height <= 0) {
      throw ArgumentError('Screenshot dimensions must be positive.');
    }
    final expectedLength = width * height * 4;
    if (this.rgbaBytes.length != expectedLength) {
      throw ArgumentError.value(
        this.rgbaBytes.length,
        'rgbaBytes',
        'must contain exactly $expectedLength RGBA bytes',
      );
    }
  }

  final int width;
  final int height;
  final Uint8List rgbaBytes;

  Rect get bounds => Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble());
}

/// One known map point paired with its center in the screenshot.
final class BdoScreenshotAlignmentAnchor {
  const BdoScreenshotAlignmentAnchor({
    required this.mapPoint,
    required this.imagePoint,
  });

  final BdoMapPoint mapPoint;
  final Offset imagePoint;
}

/// A deterministic map-to-screenshot transform fitted from explicit anchors.
///
/// Similarity alignment is preferred for ordinary north-up map snippets.
/// Affine alignment is available for dense town views where the in-game map
/// projection has slightly different horizontal and vertical scale.
final class BdoScreenshotAlignment {
  const BdoScreenshotAlignment._({
    required this.kind,
    required this.m11,
    required this.m12,
    required this.m21,
    required this.m22,
    required this.translateX,
    required this.translateY,
    required this.anchorCount,
    required this.rootMeanSquareErrorPixels,
    required this.maximumErrorPixels,
    required this.confidence,
  });

  final BdoScreenshotAlignmentKind kind;
  final double m11;
  final double m12;
  final double m21;
  final double m22;
  final double translateX;
  final double translateY;
  final int anchorCount;
  final double rootMeanSquareErrorPixels;
  final double maximumErrorPixels;
  final double confidence;

  double get determinant => m11 * m22 - m12 * m21;

  double get approximateScale => math.sqrt(determinant.abs());

  Offset project(BdoMapPoint point) => Offset(
    m11 * point.x + m12 * point.y + translateX,
    m21 * point.x + m22 * point.y + translateY,
  );

  /// Fits uniform scale, rotation, and translation.
  factory BdoScreenshotAlignment.fitSimilarity(
    Iterable<BdoScreenshotAlignmentAnchor> anchors, {
    double residualTolerancePixels = 6,
  }) {
    final values = List<BdoScreenshotAlignmentAnchor>.unmodifiable(anchors);
    _validateAnchors(values, minimumCount: 2);
    if (!residualTolerancePixels.isFinite || residualTolerancePixels <= 0) {
      throw ArgumentError.value(
        residualTolerancePixels,
        'residualTolerancePixels',
        'must be finite and positive',
      );
    }

    final mapCenter = _mapCentroid(values);
    final imageCenter = _imageCentroid(values);
    var denominator = 0.0;
    var numeratorA = 0.0;
    var numeratorB = 0.0;
    for (final anchor in values) {
      final x = anchor.mapPoint.x - mapCenter.x;
      final y = anchor.mapPoint.y - mapCenter.y;
      final u = anchor.imagePoint.dx - imageCenter.dx;
      final v = anchor.imagePoint.dy - imageCenter.dy;
      denominator += x * x + y * y;
      numeratorA += x * u + y * v;
      numeratorB += x * v - y * u;
    }
    if (denominator <= 1e-9) {
      throw ArgumentError('Similarity anchors must span distinct map points.');
    }
    final a = numeratorA / denominator;
    final b = numeratorB / denominator;
    final scale = math.sqrt(a * a + b * b);
    if (!scale.isFinite || scale <= 1e-12) {
      throw ArgumentError('Similarity anchors produce an invalid scale.');
    }
    final translateX = imageCenter.dx - a * mapCenter.x + b * mapCenter.y;
    final translateY = imageCenter.dy - b * mapCenter.x - a * mapCenter.y;
    return _fromMatrix(
      kind: BdoScreenshotAlignmentKind.similarity,
      anchors: values,
      m11: a,
      m12: -b,
      m21: b,
      m22: a,
      translateX: translateX,
      translateY: translateY,
      residualTolerancePixels: residualTolerancePixels,
    );
  }

  /// Fits a six-parameter affine transform from at least three anchors.
  factory BdoScreenshotAlignment.fitAffine(
    Iterable<BdoScreenshotAlignmentAnchor> anchors, {
    double residualTolerancePixels = 6,
  }) {
    final values = List<BdoScreenshotAlignmentAnchor>.unmodifiable(anchors);
    _validateAnchors(values, minimumCount: 3);
    if (!residualTolerancePixels.isFinite || residualTolerancePixels <= 0) {
      throw ArgumentError.value(
        residualTolerancePixels,
        'residualTolerancePixels',
        'must be finite and positive',
      );
    }

    var xx = 0.0;
    var xy = 0.0;
    var x1 = 0.0;
    var yy = 0.0;
    var y1 = 0.0;
    var ux = 0.0;
    var uy = 0.0;
    var u1 = 0.0;
    var vx = 0.0;
    var vy = 0.0;
    var v1 = 0.0;
    for (final anchor in values) {
      final x = anchor.mapPoint.x;
      final y = anchor.mapPoint.y;
      final u = anchor.imagePoint.dx;
      final v = anchor.imagePoint.dy;
      xx += x * x;
      xy += x * y;
      x1 += x;
      yy += y * y;
      y1 += y;
      ux += u * x;
      uy += u * y;
      u1 += u;
      vx += v * x;
      vy += v * y;
      v1 += v;
    }
    final normal = <List<double>>[
      <double>[xx, xy, x1],
      <double>[xy, yy, y1],
      <double>[x1, y1, values.length.toDouble()],
    ];
    final horizontal = _solveThreeByThree(normal, <double>[ux, uy, u1]);
    final vertical = _solveThreeByThree(normal, <double>[vx, vy, v1]);
    final determinant =
        horizontal[0] * vertical[1] - horizontal[1] * vertical[0];
    if (!determinant.isFinite || determinant <= 1e-12) {
      throw ArgumentError(
        'Affine anchors must be non-collinear and preserve map orientation.',
      );
    }
    return _fromMatrix(
      kind: BdoScreenshotAlignmentKind.affine,
      anchors: values,
      m11: horizontal[0],
      m12: horizontal[1],
      m21: vertical[0],
      m22: vertical[1],
      translateX: horizontal[2],
      translateY: vertical[2],
      residualTolerancePixels: residualTolerancePixels,
    );
  }

  static BdoScreenshotAlignment _fromMatrix({
    required BdoScreenshotAlignmentKind kind,
    required List<BdoScreenshotAlignmentAnchor> anchors,
    required double m11,
    required double m12,
    required double m21,
    required double m22,
    required double translateX,
    required double translateY,
    required double residualTolerancePixels,
  }) {
    var squaredError = 0.0;
    var maximumError = 0.0;
    for (final anchor in anchors) {
      final projected = Offset(
        m11 * anchor.mapPoint.x + m12 * anchor.mapPoint.y + translateX,
        m21 * anchor.mapPoint.x + m22 * anchor.mapPoint.y + translateY,
      );
      final error = (projected - anchor.imagePoint).distance;
      squaredError += error * error;
      maximumError = math.max(maximumError, error);
    }
    final rootMeanSquareError = math.sqrt(squaredError / anchors.length);
    final anchorStrength = _anchorStrength(kind, anchors.length);
    final normalizedError = rootMeanSquareError / residualTolerancePixels;
    final residualConfidence = 1 / (1 + normalizedError * normalizedError);
    return BdoScreenshotAlignment._(
      kind: kind,
      m11: m11,
      m12: m12,
      m21: m21,
      m22: m22,
      translateX: translateX,
      translateY: translateY,
      anchorCount: anchors.length,
      rootMeanSquareErrorPixels: rootMeanSquareError,
      maximumErrorPixels: maximumError,
      confidence: (anchorStrength * residualConfidence).clamp(0, 1),
    );
  }
}

/// A known node or house expected at [mapPoint].
final class BdoScreenshotImportTarget {
  BdoScreenshotImportTarget({
    required this.id,
    required this.label,
    required this.kind,
    required this.mapPoint,
    Iterable<String> linkedTargetIds = const <String>[],
    this.parentTargetId,
    Iterable<int> possibleHouseUsageTypeIds = const <int>[],
  }) : linkedTargetIds = Set<String>.unmodifiable(linkedTargetIds),
       possibleHouseUsageTypeIds = Set<int>.unmodifiable(
         possibleHouseUsageTypeIds,
       ) {
    if (id.trim().isEmpty || label.trim().isEmpty) {
      throw ArgumentError('Screenshot targets require an id and label.');
    }
    if (kind != BdoScreenshotTargetKind.house &&
        this.possibleHouseUsageTypeIds.isNotEmpty) {
      throw ArgumentError(
        'Only house targets can provide house usage choices.',
      );
    }
  }

  factory BdoScreenshotImportTarget.workerNode(BdoWorkerNode node) =>
      BdoScreenshotImportTarget(
        id: node.id,
        label: node.name,
        kind: BdoScreenshotTargetKind.workerNode,
        mapPoint: node.location.mapPoint,
        linkedTargetIds: node.linkIds,
        parentTargetId: node.parentId,
      );

  factory BdoScreenshotImportTarget.house(LodgingHouse house) =>
      BdoScreenshotImportTarget(
        id: house.id,
        label: house.name,
        kind: BdoScreenshotTargetKind.house,
        mapPoint: BdoWorldPoint(house.position.x, house.position.z).mapPoint,
        possibleHouseUsageTypeIds: house.usages.map((usage) => usage.typeId),
      );

  final String id;
  final String label;
  final BdoScreenshotTargetKind kind;
  final BdoMapPoint mapPoint;
  final Set<String> linkedTargetIds;
  final String? parentTargetId;
  final Set<int> possibleHouseUsageTypeIds;
}

/// Chooses a small, spatially distributed set of named alignment guides.
///
/// These are expected map references, never recognition results. Keeping the
/// set deliberately small makes a regional screenshot possible to align
/// without covering it in hundreds of indistinguishable circles.
abstract final class BdoScreenshotAlignmentGuides {
  static List<BdoScreenshotImportTarget> select(
    Iterable<BdoScreenshotImportTarget> targets, {
    int maximumCount = 8,
  }) {
    if (maximumCount <= 0) {
      throw ArgumentError.value(
        maximumCount,
        'maximumCount',
        'must be positive',
      );
    }
    final values = List<BdoScreenshotImportTarget>.unmodifiable(targets);
    if (values.length <= maximumCount) return values;
    final selected = <BdoScreenshotImportTarget>[values.first];
    while (selected.length < maximumCount) {
      BdoScreenshotImportTarget? best;
      var bestDistance = -1.0;
      for (final candidate in values) {
        if (selected.contains(candidate)) continue;
        final nearest = selected
            .map(
              (entry) =>
                  _mapPointDistanceSquared(entry.mapPoint, candidate.mapPoint),
            )
            .reduce(math.min);
        if (nearest > bestDistance) {
          best = candidate;
          bestDistance = nearest;
        }
      }
      if (best == null) break;
      selected.add(best);
    }
    return List<BdoScreenshotImportTarget>.unmodifiable(selected);
  }
}

/// A normalized local appearance descriptor used for one-time calibration.
final class BdoScreenshotPatchDescriptor {
  BdoScreenshotPatchDescriptor._({
    required List<double> values,
    required this.visibleFraction,
    required this.markerContrast,
  }) : values = List<double>.unmodifiable(values);

  final List<double> values;
  final double visibleFraction;
  final double markerContrast;

  double distanceTo(BdoScreenshotPatchDescriptor other) {
    if (values.length != other.values.length) {
      throw ArgumentError('Patch descriptors must use the same feature set.');
    }
    var squared = 0.0;
    for (var index = 0; index < values.length; index++) {
      final delta = values[index] - other.values[index];
      squared += delta * delta;
    }
    return math.sqrt(squared / values.length);
  }
}

/// A decoded marker image and the marker center within that image.
///
/// Hosts can create a reusable profile directly from the bundled active and
/// gray marker artwork. No labels need to be collected from each screenshot.
final class BdoScreenshotPatchReference {
  const BdoScreenshotPatchReference({
    required this.raster,
    required this.center,
  });

  final BdoScreenshotRaster raster;
  final Offset center;
}

/// Visual reference for active and inactive markers of one target kind.
///
/// A profile can be calibrated once from labelled icon samples and persisted
/// by the host. Node and house profiles remain separate because their in-game
/// marker palettes and silhouettes differ.
final class BdoScreenshotStateProfile {
  const BdoScreenshotStateProfile({
    required this.kind,
    required this.activePrototype,
    required this.inactivePrototype,
    required this.sampleRadiusPixels,
    this.minimumMarkerContrast = 0.015,
    this.maximumPrototypeDistance = 0.18,
    this.minimumDistanceMargin = 0.012,
    this.minimumDecisionConfidence = 0.34,
    this.highConfidenceThreshold = 0.82,
    this.graphAwareWorkerEvidence = false,
  }) : assert(sampleRadiusPixels >= 4),
       assert(minimumMarkerContrast >= 0),
       assert(maximumPrototypeDistance > 0),
       assert(minimumDistanceMargin >= 0),
       assert(minimumDecisionConfidence >= 0),
       assert(minimumDecisionConfidence <= 1),
       assert(highConfidenceThreshold >= 0),
       assert(highConfidenceThreshold <= 1);

  /// Builds a reusable profile from decoded active and inactive marker art.
  ///
  /// Multiple references may be supplied to cover different node silhouettes
  /// while retaining one deterministic profile for subsequent imports.
  factory BdoScreenshotStateProfile.fromMarkerReferences({
    required BdoScreenshotTargetKind kind,
    required Iterable<BdoScreenshotPatchReference> activeReferences,
    required Iterable<BdoScreenshotPatchReference> inactiveReferences,
    double sampleRadiusPixels = 18,
    bool graphAwareWorkerEvidence = false,
    double highConfidenceThreshold = 0.82,
  }) {
    _validateRadius(sampleRadiusPixels);
    final active = List<BdoScreenshotPatchReference>.unmodifiable(
      activeReferences,
    );
    final inactive = List<BdoScreenshotPatchReference>.unmodifiable(
      inactiveReferences,
    );
    if (active.isEmpty || inactive.isEmpty) {
      throw ArgumentError(
        'Marker references require active and inactive artwork.',
      );
    }
    final activePrototype = _meanDescriptor(
      active
          .map(
            (reference) => _describePatch(
              reference.raster,
              reference.center,
              sampleRadiusPixels,
            ),
          )
          .toList(growable: false),
    );
    final inactivePrototype = _meanDescriptor(
      inactive
          .map(
            (reference) => _describePatch(
              reference.raster,
              reference.center,
              sampleRadiusPixels,
            ),
          )
          .toList(growable: false),
    );
    final weakestReferenceContrast = math.min(
      activePrototype.markerContrast,
      inactivePrototype.markerContrast,
    );
    return BdoScreenshotStateProfile(
      kind: kind,
      activePrototype: activePrototype,
      inactivePrototype: inactivePrototype,
      sampleRadiusPixels: sampleRadiusPixels,
      minimumMarkerContrast: math.max(0.012, weakestReferenceContrast * 0.3),
      graphAwareWorkerEvidence: graphAwareWorkerEvidence,
      highConfidenceThreshold: highConfidenceThreshold,
    );
  }

  /// Default Black Desert worker-node palette classification.
  ///
  /// This separates saturated teal and gold invested markers from neutral
  /// gray inactive markers without requiring per-import labelling.
  factory BdoScreenshotStateProfile.bdoWorkerNodes() =>
      _builtInStateProfile(BdoScreenshotTargetKind.workerNode);

  /// Default Black Desert house-ownership palette classification.
  ///
  /// Blue and yellow owned markers are separated from gray unowned markers.
  /// The profile deliberately does not infer storage, lodging, or workshop
  /// usage from color alone.
  factory BdoScreenshotStateProfile.bdoOwnedHouses() =>
      _builtInStateProfile(BdoScreenshotTargetKind.house);

  final BdoScreenshotTargetKind kind;
  final BdoScreenshotPatchDescriptor activePrototype;
  final BdoScreenshotPatchDescriptor inactivePrototype;
  final double sampleRadiusPixels;
  final double minimumMarkerContrast;
  final double maximumPrototypeDistance;
  final double minimumDistanceMargin;
  final double minimumDecisionConfidence;
  final double highConfidenceThreshold;
  final bool graphAwareWorkerEvidence;
}

final class BdoScreenshotTargetAnalysis {
  BdoScreenshotTargetAnalysis({
    required this.target,
    required this.imagePoint,
    required this.state,
    required this.confidence,
    required this.activeDistance,
    required this.inactiveDistance,
    required Iterable<BdoScreenshotReviewReason> reviewReasons,
    required this.suggestedHouseUsageTypeId,
  }) : reviewReasons = Set<BdoScreenshotReviewReason>.unmodifiable(
         reviewReasons,
       );

  final BdoScreenshotImportTarget target;
  final Offset imagePoint;
  final BdoScreenshotTargetState state;
  final double confidence;
  final double? activeDistance;
  final double? inactiveDistance;
  final Set<BdoScreenshotReviewReason> reviewReasons;

  /// Always null for screenshot imports.
  ///
  /// Ownership color does not prove the selected storage, lodging, stable, or
  /// workshop usage, even when the current dataset lists one known choice.
  final int? suggestedHouseUsageTypeId;

  bool get isHighConfidence =>
      state != BdoScreenshotTargetState.uncertain &&
      state != BdoScreenshotTargetState.outsideViewport &&
      reviewReasons.isEmpty;

  bool get requiresReview => reviewReasons.isNotEmpty;
}

final class BdoScreenshotAnalysisResult {
  BdoScreenshotAnalysisResult({
    required this.alignment,
    required Iterable<BdoScreenshotTargetAnalysis> targets,
  }) : targets = List<BdoScreenshotTargetAnalysis>.unmodifiable(targets),
       targetsById = Map<String, BdoScreenshotTargetAnalysis>.unmodifiable(
         <String, BdoScreenshotTargetAnalysis>{
           for (final target in targets) target.target.id: target,
         },
       );

  final BdoScreenshotAlignment alignment;
  final List<BdoScreenshotTargetAnalysis> targets;
  final Map<String, BdoScreenshotTargetAnalysis> targetsById;

  Iterable<BdoScreenshotTargetAnalysis> get activeSuggestions => targets.where(
    (target) => target.state == BdoScreenshotTargetState.active,
  );

  Iterable<BdoScreenshotTargetAnalysis> get reviewItems =>
      targets.where((target) => target.requiresReview);
}

/// Combined evidence for one map target seen in one or more screenshots.
///
/// Repeated moderate active readings may reinforce each other. A weak gray
/// reading does not cancel a clear active marker; only strong opposing
/// readings are reported as a conflict. The caller still keeps final review
/// choices editable.
final class BdoScreenshotEvidenceSummary {
  const BdoScreenshotEvidenceSummary({
    required this.primary,
    required this.confidence,
    required this.supportCount,
    required this.conflict,
    required this.highConfidence,
  });

  final BdoScreenshotTargetAnalysis primary;
  final double confidence;
  final int supportCount;
  final bool conflict;
  final bool highConfidence;
}

abstract final class BdoScreenshotEvidence {
  static BdoScreenshotEvidenceSummary? summarize(
    Iterable<BdoScreenshotTargetAnalysis> observations,
  ) {
    final visible = observations
        .where(
          (value) => value.state != BdoScreenshotTargetState.outsideViewport,
        )
        .toList(growable: false);
    if (visible.isEmpty) return null;

    final active =
        visible
            .where((value) => value.state == BdoScreenshotTargetState.active)
            .toList(growable: false)
          ..sort((left, right) => right.confidence.compareTo(left.confidence));
    final inactive =
        visible
            .where((value) => value.state == BdoScreenshotTargetState.inactive)
            .toList(growable: false)
          ..sort((left, right) => right.confidence.compareTo(left.confidence));
    final uncertain =
        visible
            .where((value) => value.state == BdoScreenshotTargetState.uncertain)
            .toList(growable: false)
          ..sort((left, right) => right.confidence.compareTo(left.confidence));
    final candidates = active.isNotEmpty ? active : uncertain;
    if (candidates.isEmpty) return null;

    final primary = candidates.first;
    final supporting = active
        .where((value) => value.confidence >= .55)
        .toList(growable: false);
    var confidence = primary.confidence;
    for (final evidence in supporting.skip(1).take(3)) {
      confidence += evidence.confidence * .20;
    }
    confidence = confidence.clamp(0, .97);

    final strongestInactive = inactive.firstOrNull?.confidence ?? 0;
    final conflict =
        active.isNotEmpty &&
        active.first.confidence >= .72 &&
        strongestInactive >= .72;
    final blockingReasons = primary.reviewReasons.where(
      (reason) =>
          reason != BdoScreenshotReviewReason.ambiguousHouseUsage &&
          reason != BdoScreenshotReviewReason.lowConfidence &&
          !(supporting.length >= 2 &&
              reason == BdoScreenshotReviewReason.insufficientVisualEvidence),
    );
    final highConfidence =
        primary.state == BdoScreenshotTargetState.active &&
        (primary.confidence >= .82 ||
            (supporting.length >= 2 &&
                primary.confidence >= .62 &&
                confidence >= .78)) &&
        blockingReasons.isEmpty &&
        !conflict;

    return BdoScreenshotEvidenceSummary(
      primary: primary,
      confidence: confidence,
      supportCount: supporting.length,
      conflict: conflict,
      highConfidence: highConfidence,
    );
  }
}

/// Additive application of screenshot choices to persisted planner settings.
final class BdoScreenshotImportMergeResult {
  BdoScreenshotImportMergeResult({
    required this.preferences,
    required Iterable<String> addedNodeIds,
    required Iterable<String> addedHouseIds,
    required Iterable<String> addedPrerequisiteHouseIds,
  }) : addedNodeIds = Set<String>.unmodifiable(addedNodeIds),
       addedHouseIds = Set<String>.unmodifiable(addedHouseIds),
       addedPrerequisiteHouseIds = Set<String>.unmodifiable(
         addedPrerequisiteHouseIds,
       );

  final BdoNodeNetworkPreferences preferences;
  final Set<String> addedNodeIds;
  final Set<String> addedHouseIds;
  final Set<String> addedPrerequisiteHouseIds;
}

/// Safely merges user-confirmed screenshot results into the current setup.
///
/// Imports only add records. Existing nodes, houses, and house usage choices
/// remain intact. Confirmed houses automatically include their complete
/// prerequisite chain, while imported house usage remains unset.
abstract final class BdoScreenshotImportMerge {
  static BdoScreenshotImportMergeResult mergeConfirmedActiveTargets({
    required BdoNodeNetworkPreferences current,
    required BdoScreenshotAnalysisResult analysis,
    required Iterable<String> confirmedActiveTargetIds,
    required LodgingDataset lodgingDataset,
  }) {
    final confirmedIds = confirmedActiveTargetIds
        .map((id) => id.trim())
        .where((id) => id.isNotEmpty)
        .toSet();
    final unknownIds = confirmedIds.difference(
      analysis.targetsById.keys.toSet(),
    );
    if (unknownIds.isNotEmpty) {
      throw ArgumentError.value(
        unknownIds.toList()..sort(),
        'confirmedActiveTargetIds',
        'contains targets absent from the screenshot analysis',
      );
    }

    final rejectedStates = <String, BdoScreenshotTargetState>{};
    for (final id in confirmedIds) {
      final state = analysis.targetsById[id]!.state;
      if (state == BdoScreenshotTargetState.inactive ||
          state == BdoScreenshotTargetState.outsideViewport) {
        rejectedStates[id] = state;
      }
    }
    if (rejectedStates.isNotEmpty) {
      throw ArgumentError.value(
        rejectedStates,
        'confirmedActiveTargetIds',
        'cannot confirm inactive or out-of-view targets as active',
      );
    }

    final nodeIds = current.currentNodeIds.toSet();
    final ownedHouseIds = current.currentOwnedHouseIds.toSet();
    final directlyAddedHouseIds = <String>{};
    final prerequisiteIds = <String>{};
    for (final id in confirmedIds) {
      final target = analysis.targetsById[id]!.target;
      if (target.kind == BdoScreenshotTargetKind.workerNode) {
        nodeIds.add(target.id);
        continue;
      }
      final house = lodgingDataset.housesById[target.id];
      if (house == null) {
        throw ArgumentError.value(
          target.id,
          'confirmedActiveTargetIds',
          'does not identify a house in the lodging dataset',
        );
      }
      if (ownedHouseIds.add(house.id)) {
        directlyAddedHouseIds.add(house.id);
      }
      var prerequisiteId = house.prerequisiteHouseId;
      final visited = <String>{house.id};
      while (prerequisiteId != null) {
        if (!visited.add(prerequisiteId)) {
          throw StateError('House prerequisite chain contains a cycle.');
        }
        final prerequisite = lodgingDataset.housesById[prerequisiteId];
        if (prerequisite == null) {
          throw StateError(
            'House prerequisite $prerequisiteId is missing from the dataset.',
          );
        }
        if (ownedHouseIds.add(prerequisite.id)) {
          prerequisiteIds.add(prerequisite.id);
        }
        prerequisiteId = prerequisite.prerequisiteHouseId;
      }
    }

    final addedNodeIds = nodeIds.difference(current.currentNodeIds);
    final preferences = current.copyWith(
      currentNodeIds: nodeIds,
      currentOwnedHouseIds: ownedHouseIds,
      currentHouseUsageTypeIds: current.currentHouseUsageTypeIds,
    );
    return BdoScreenshotImportMergeResult(
      preferences: preferences,
      addedNodeIds: addedNodeIds,
      addedHouseIds: directlyAddedHouseIds,
      addedPrerequisiteHouseIds: prerequisiteIds,
    );
  }
}

/// Offline screenshot sampler for explicitly aligned map snippets.
abstract final class BdoScreenshotMapImportEngine {
  /// Builds a state profile from labelled icon centers in one screenshot.
  static BdoScreenshotStateProfile calibrateProfile({
    required BdoScreenshotRaster raster,
    required BdoScreenshotTargetKind kind,
    required Iterable<Offset> activeSampleCenters,
    required Iterable<Offset> inactiveSampleCenters,
    double sampleRadiusPixels = 18,
  }) {
    _validateRadius(sampleRadiusPixels);
    final activeCenters = List<Offset>.unmodifiable(activeSampleCenters);
    final inactiveCenters = List<Offset>.unmodifiable(inactiveSampleCenters);
    if (activeCenters.isEmpty || inactiveCenters.isEmpty) {
      throw ArgumentError(
        'Calibration requires active and inactive reference markers.',
      );
    }
    return BdoScreenshotStateProfile.fromMarkerReferences(
      kind: kind,
      activeReferences: activeCenters.map(
        (center) => BdoScreenshotPatchReference(raster: raster, center: center),
      ),
      inactiveReferences: inactiveCenters.map(
        (center) => BdoScreenshotPatchReference(raster: raster, center: center),
      ),
      sampleRadiusPixels: sampleRadiusPixels,
    );
  }

  static BdoScreenshotPatchDescriptor describePatch({
    required BdoScreenshotRaster raster,
    required Offset center,
    required double radiusPixels,
  }) {
    _validateRadius(radiusPixels);
    return _describePatch(raster, center, radiusPixels);
  }

  /// Samples every target without mutating application state.
  ///
  /// [contentBounds] should exclude the game title bar, panels, and other UI.
  /// Targets whose complete marker circle is not inside that rectangle are
  /// returned as [BdoScreenshotTargetState.outsideViewport].
  static BdoScreenshotAnalysisResult analyze({
    required BdoScreenshotRaster raster,
    required BdoScreenshotAlignment alignment,
    required BdoScreenshotStateProfile profile,
    required Iterable<BdoScreenshotImportTarget> targets,
    Rect? contentBounds,
    double minimumAlignmentConfidenceForDecision = 0.45,
  }) {
    if (minimumAlignmentConfidenceForDecision < 0 ||
        minimumAlignmentConfidenceForDecision > 1) {
      throw ArgumentError.value(
        minimumAlignmentConfidenceForDecision,
        'minimumAlignmentConfidenceForDecision',
        'must be between zero and one',
      );
    }
    final values = List<BdoScreenshotImportTarget>.unmodifiable(targets);
    if (values.any((target) => target.kind != profile.kind)) {
      throw ArgumentError(
        'Every target must match the screenshot state profile kind.',
      );
    }
    final ids = values.map((target) => target.id).toSet();
    if (ids.length != values.length) {
      throw ArgumentError('Screenshot targets must have unique ids.');
    }
    final viewport = (contentBounds ?? raster.bounds).intersect(raster.bounds);
    if (viewport.isEmpty) {
      throw ArgumentError('The screenshot content bounds are empty.');
    }
    final projected = <String, Offset>{
      for (final target in values)
        target.id: alignment.project(target.mapPoint),
    };
    final workerEvidenceByTargetId =
        profile.kind == BdoScreenshotTargetKind.workerNode
        ? _workerEvidenceByTargetId(
            raster: raster,
            targets: values,
            projected: projected,
            sampleRadiusPixels: profile.sampleRadiusPixels,
          )
        : const <String, _WorkerNodeVisualEvidence>{};
    final overlapping = _overlappingTargetIds(
      values,
      projected,
      profile.sampleRadiusPixels * 0.65,
      canShareMarker: _sameWorkerNodeSite,
    );
    final analyses = <BdoScreenshotTargetAnalysis>[];
    for (final target in values) {
      final imagePoint = projected[target.id]!;
      final completeSampleBounds = Rect.fromCircle(
        center: imagePoint,
        radius: profile.sampleRadiusPixels,
      );
      if (!viewport.contains(completeSampleBounds.topLeft) ||
          !viewport.contains(completeSampleBounds.bottomRight)) {
        analyses.add(
          _nonVisualResult(
            target: target,
            imagePoint: imagePoint,
            state: BdoScreenshotTargetState.outsideViewport,
            reason: BdoScreenshotReviewReason.insufficientVisualEvidence,
          ),
        );
        continue;
      }
      if (overlapping.contains(target.id)) {
        analyses.add(
          _nonVisualResult(
            target: target,
            imagePoint: imagePoint,
            state: BdoScreenshotTargetState.uncertain,
            reason: BdoScreenshotReviewReason.overlappingTargets,
          ),
        );
        continue;
      }
      final descriptor = _describePatch(
        raster,
        imagePoint,
        profile.sampleRadiusPixels,
      );
      final activeDistance = descriptor.distanceTo(profile.activePrototype);
      final inactiveDistance = descriptor.distanceTo(profile.inactivePrototype);
      final bestDistance = math.min(activeDistance, inactiveDistance);
      final distanceMargin = (activeDistance - inactiveDistance).abs();
      final workerEvidence = workerEvidenceByTargetId[target.id];
      final hasWorkerActiveEvidence = workerEvidence?.isActive ?? false;
      final reasons = <BdoScreenshotReviewReason>{};
      if (alignment.confidence < minimumAlignmentConfidenceForDecision) {
        reasons.add(BdoScreenshotReviewReason.lowAlignmentConfidence);
      }
      if (descriptor.visibleFraction < 0.9 ||
          descriptor.markerContrast < profile.minimumMarkerContrast ||
          bestDistance > profile.maximumPrototypeDistance) {
        reasons.add(BdoScreenshotReviewReason.insufficientVisualEvidence);
      }
      if (distanceMargin < profile.minimumDistanceMargin) {
        reasons.add(BdoScreenshotReviewReason.conflictingVisualEvidence);
      }
      if (hasWorkerActiveEvidence) {
        // Worker markers have several in-game silhouettes. Production-node
        // view in particular uses warm gold/brown marker art that is unlike
        // the teal city prototype. Graph-aligned color and route evidence is
        // strong enough to resolve those markers without searching arbitrary
        // circles elsewhere in the screenshot.
        reasons
          ..remove(BdoScreenshotReviewReason.insufficientVisualEvidence)
          ..remove(BdoScreenshotReviewReason.conflictingVisualEvidence);
      }

      final prototypeFit =
          1 - (bestDistance / profile.maximumPrototypeDistance).clamp(0.0, 1.0);
      final separation =
          (distanceMargin /
                  math.max(
                    profile.minimumDistanceMargin * 5,
                    profile.maximumPrototypeDistance * 0.25,
                  ))
              .clamp(0.0, 1.0);
      var visualConfidence = prototypeFit * 0.55 + separation * 0.45;
      if (workerEvidence != null) {
        visualConfidence = math.max(
          visualConfidence,
          workerEvidence.decisionConfidence,
        );
      }
      final confidence =
          (alignment.confidence * descriptor.visibleFraction * visualConfidence)
              .clamp(0.0, 1.0);
      var state = hasWorkerActiveEvidence
          ? BdoScreenshotTargetState.active
          : profile.graphAwareWorkerEvidence &&
                profile.kind == BdoScreenshotTargetKind.workerNode
          ? activeDistance < inactiveDistance
                ? BdoScreenshotTargetState.uncertain
                : BdoScreenshotTargetState.inactive
          : activeDistance < inactiveDistance
          ? BdoScreenshotTargetState.active
          : BdoScreenshotTargetState.inactive;
      if (reasons.contains(
            BdoScreenshotReviewReason.insufficientVisualEvidence,
          ) ||
          reasons.contains(
            BdoScreenshotReviewReason.conflictingVisualEvidence,
          ) ||
          confidence < profile.minimumDecisionConfidence) {
        state = BdoScreenshotTargetState.uncertain;
      }
      if (confidence < profile.highConfidenceThreshold &&
          state != BdoScreenshotTargetState.uncertain) {
        reasons.add(BdoScreenshotReviewReason.lowConfidence);
      }

      if (target.kind == BdoScreenshotTargetKind.house &&
          state == BdoScreenshotTargetState.active) {
        reasons.add(BdoScreenshotReviewReason.ambiguousHouseUsage);
      }
      analyses.add(
        BdoScreenshotTargetAnalysis(
          target: target,
          imagePoint: imagePoint,
          state: state,
          confidence: confidence,
          activeDistance: activeDistance,
          inactiveDistance: inactiveDistance,
          reviewReasons: reasons,
          suggestedHouseUsageTypeId: null,
        ),
      );
    }
    return BdoScreenshotAnalysisResult(alignment: alignment, targets: analyses);
  }
}

BdoScreenshotStateProfile _builtInStateProfile(BdoScreenshotTargetKind kind) {
  const radius = 18.0;
  final colors = switch (kind) {
    BdoScreenshotTargetKind.workerNode => (
      active: const <Color>[
        Color(0xff00aaa4),
        Color(0xfff5c02b),
        Color(0xff182325),
      ],
      inactive: const <Color>[
        Color(0xffd0d0d0),
        Color(0xff777777),
        Color(0xff252525),
      ],
    ),
    BdoScreenshotTargetKind.house => (
      active: const <Color>[
        Color(0xff0097db),
        Color(0xffffcd2a),
        Color(0xff34383b),
      ],
      inactive: const <Color>[
        Color(0xffbabec1),
        Color(0xff777b7e),
        Color(0xff2d3032),
      ],
    ),
  };
  final activeRaster = _paletteMarkerRaster(colors.active);
  final inactiveRaster = _paletteMarkerRaster(colors.inactive);
  const center = Offset(32, 32);
  return BdoScreenshotStateProfile.fromMarkerReferences(
    kind: kind,
    activeReferences: <BdoScreenshotPatchReference>[
      BdoScreenshotPatchReference(raster: activeRaster, center: center),
    ],
    inactiveReferences: <BdoScreenshotPatchReference>[
      BdoScreenshotPatchReference(raster: inactiveRaster, center: center),
    ],
    sampleRadiusPixels: radius,
    graphAwareWorkerEvidence: kind == BdoScreenshotTargetKind.workerNode,
    highConfidenceThreshold: kind == BdoScreenshotTargetKind.workerNode
        ? 0.70
        : 0.82,
  );
}

BdoScreenshotRaster _paletteMarkerRaster(List<Color> palette) {
  const width = 64;
  const height = 64;
  const centerX = 32.0;
  const centerY = 32.0;
  final bytes = Uint8List(width * height * 4);
  const terrain = Color(0xff4b4438);
  const outline = Color(0xff141718);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final distance = math.sqrt(
        math.pow(x + 0.5 - centerX, 2) + math.pow(y + 0.5 - centerY, 2),
      );
      Color color;
      if (distance > 13) {
        color = terrain;
      } else if (distance > 10.5) {
        color = outline;
      } else {
        final normalizedX = (x + 0.5 - (centerX - 10.5)) / 21;
        color = normalizedX < 0.56
            ? palette[0]
            : normalizedX < 0.82
            ? palette[1]
            : palette[2];
      }
      final offset = (y * width + x) * 4;
      bytes[offset] = _colorChannel(color.r);
      bytes[offset + 1] = _colorChannel(color.g);
      bytes[offset + 2] = _colorChannel(color.b);
      bytes[offset + 3] = 255;
    }
  }
  return BdoScreenshotRaster(width: width, height: height, rgbaBytes: bytes);
}

int _colorChannel(double value) {
  final channel = (value * 255).round();
  if (channel < 0) return 0;
  if (channel > 255) return 255;
  return channel;
}

BdoScreenshotTargetAnalysis _nonVisualResult({
  required BdoScreenshotImportTarget target,
  required Offset imagePoint,
  required BdoScreenshotTargetState state,
  required BdoScreenshotReviewReason reason,
}) => BdoScreenshotTargetAnalysis(
  target: target,
  imagePoint: imagePoint,
  state: state,
  confidence: 0,
  activeDistance: null,
  inactiveDistance: null,
  reviewReasons: <BdoScreenshotReviewReason>{reason},
  suggestedHouseUsageTypeId: null,
);

BdoScreenshotPatchDescriptor _describePatch(
  BdoScreenshotRaster raster,
  Offset center,
  double radiusPixels,
) {
  const histogramBins = 16;
  final inner = List<double>.filled(histogramBins, 0);
  final outer = List<double>.filled(histogramBins, 0);
  var innerWeight = 0.0;
  var outerWeight = 0.0;
  var expectedWeight = 0.0;
  var visibleWeight = 0.0;
  var edgeTotal = 0.0;
  var edgeWeight = 0.0;
  final minimumX = (center.dx - radiusPixels).floor();
  final maximumX = (center.dx + radiusPixels).ceil();
  final minimumY = (center.dy - radiusPixels).floor();
  final maximumY = (center.dy + radiusPixels).ceil();
  final innerRadius = radiusPixels * 0.68;
  final outerRadius = radiusPixels * 0.78;
  for (var y = minimumY; y <= maximumY; y++) {
    for (var x = minimumX; x <= maximumX; x++) {
      final dx = x + 0.5 - center.dx;
      final dy = y + 0.5 - center.dy;
      final distance = math.sqrt(dx * dx + dy * dy);
      if (distance > radiusPixels) continue;
      final weight = 1 - distance / (radiusPixels * 2.5);
      expectedWeight += weight;
      if (x < 0 || y < 0 || x >= raster.width || y >= raster.height) {
        continue;
      }
      final offset = (y * raster.width + x) * 4;
      final alpha = raster.rgbaBytes[offset + 3];
      if (alpha < 64) continue;
      visibleWeight += weight;
      final red = raster.rgbaBytes[offset];
      final green = raster.rgbaBytes[offset + 1];
      final blue = raster.rgbaBytes[offset + 2];
      final bin = _colorHistogramBin(red, green, blue);
      if (distance <= innerRadius) {
        inner[bin] += weight;
        innerWeight += weight;
        if (x + 1 < raster.width && y + 1 < raster.height) {
          final rightOffset = offset + 4;
          final downOffset = offset + raster.width * 4;
          final luma = _luma(red, green, blue);
          final rightLuma = _luma(
            raster.rgbaBytes[rightOffset],
            raster.rgbaBytes[rightOffset + 1],
            raster.rgbaBytes[rightOffset + 2],
          );
          final downLuma = _luma(
            raster.rgbaBytes[downOffset],
            raster.rgbaBytes[downOffset + 1],
            raster.rgbaBytes[downOffset + 2],
          );
          edgeTotal +=
              ((luma - rightLuma).abs() + (luma - downLuma).abs()) /
              (255 * 2) *
              weight;
          edgeWeight += weight;
        }
      } else if (distance >= outerRadius) {
        outer[bin] += weight;
        outerWeight += weight;
      }
    }
  }
  if (innerWeight > 0) {
    for (var index = 0; index < histogramBins; index++) {
      inner[index] /= innerWeight;
    }
  }
  if (outerWeight > 0) {
    for (var index = 0; index < histogramBins; index++) {
      outer[index] /= outerWeight;
    }
  }
  var contrast = 0.0;
  final values = <double>[];
  for (var index = 0; index < histogramBins; index++) {
    final difference = inner[index] - outer[index];
    contrast += difference.abs();
    values.add(inner[index] * 0.35);
  }
  for (var index = 0; index < histogramBins; index++) {
    values.add((inner[index] - outer[index]) * 0.65);
  }
  values.add(edgeWeight <= 0 ? 0 : edgeTotal / edgeWeight * 0.45);
  return BdoScreenshotPatchDescriptor._(
    values: values,
    visibleFraction: expectedWeight <= 0 ? 0 : visibleWeight / expectedWeight,
    markerContrast: contrast / 2,
  );
}

int _colorHistogramBin(int red, int green, int blue) {
  final maximum = math.max(red, math.max(green, blue)).toDouble();
  final minimum = math.min(red, math.min(green, blue)).toDouble();
  final delta = maximum - minimum;
  final saturation = maximum <= 0 ? 0.0 : delta / maximum;
  if (saturation < 0.17 || delta <= 0) {
    final valueBin = ((maximum / 256) * 4).floor().clamp(0, 3);
    return 12 + valueBin;
  }
  double hue;
  if (maximum == red) {
    hue = ((green - blue) / delta) % 6;
  } else if (maximum == green) {
    hue = (blue - red) / delta + 2;
  } else {
    hue = (red - green) / delta + 4;
  }
  hue *= 60;
  if (hue < 0) hue += 360;
  return ((hue / 360) * 12).floor().clamp(0, 11);
}

double _luma(int red, int green, int blue) =>
    red * 0.2126 + green * 0.7152 + blue * 0.0722;

BdoScreenshotPatchDescriptor _meanDescriptor(
  List<BdoScreenshotPatchDescriptor> descriptors,
) {
  final length = descriptors.first.values.length;
  final values = List<double>.filled(length, 0);
  var visibleFraction = 0.0;
  var markerContrast = 0.0;
  for (final descriptor in descriptors) {
    if (descriptor.values.length != length) {
      throw ArgumentError('Calibration descriptors use different features.');
    }
    for (var index = 0; index < length; index++) {
      values[index] += descriptor.values[index];
    }
    visibleFraction += descriptor.visibleFraction;
    markerContrast += descriptor.markerContrast;
  }
  for (var index = 0; index < length; index++) {
    values[index] /= descriptors.length;
  }
  return BdoScreenshotPatchDescriptor._(
    values: values,
    visibleFraction: visibleFraction / descriptors.length,
    markerContrast: markerContrast / descriptors.length,
  );
}

Set<String> _overlappingTargetIds(
  List<BdoScreenshotImportTarget> targets,
  Map<String, Offset> projected,
  double threshold, {
  bool Function(
    BdoScreenshotImportTarget first,
    BdoScreenshotImportTarget second,
  )?
  canShareMarker,
}) {
  if (threshold <= 0) return const <String>{};
  final buckets = <(int, int), List<BdoScreenshotImportTarget>>{};
  final result = <String>{};
  for (final target in targets) {
    final point = projected[target.id]!;
    final bucketX = (point.dx / threshold).floor();
    final bucketY = (point.dy / threshold).floor();
    for (var y = bucketY - 1; y <= bucketY + 1; y++) {
      for (var x = bucketX - 1; x <= bucketX + 1; x++) {
        for (final other in buckets[(x, y)] ?? const []) {
          if ((point - projected[other.id]!).distance < threshold &&
              !(canShareMarker?.call(target, other) ?? false)) {
            result
              ..add(target.id)
              ..add(other.id);
          }
        }
      }
    }
    (buckets[(bucketX, bucketY)] ??= <BdoScreenshotImportTarget>[]).add(target);
  }
  return Set<String>.unmodifiable(result);
}

bool _sameWorkerNodeSite(
  BdoScreenshotImportTarget first,
  BdoScreenshotImportTarget second,
) {
  if (first.kind != BdoScreenshotTargetKind.workerNode ||
      second.kind != BdoScreenshotTargetKind.workerNode) {
    return false;
  }
  return first.parentTargetId == second.id ||
      second.parentTargetId == first.id ||
      (first.parentTargetId != null &&
          first.parentTargetId == second.parentTargetId);
}

final class _WorkerNodeVisualEvidence {
  const _WorkerNodeVisualEvidence({
    required this.markerStrength,
    required this.routeStrength,
  });

  final double markerStrength;
  final double routeStrength;

  double get activeStrength => math.max(markerStrength, routeStrength);

  bool get isActive => activeStrength >= 0.45;

  double get decisionConfidence =>
      (0.52 + activeStrength * 0.46).clamp(0.0, 0.98);
}

Map<String, _WorkerNodeVisualEvidence> _workerEvidenceByTargetId({
  required BdoScreenshotRaster raster,
  required List<BdoScreenshotImportTarget> targets,
  required Map<String, Offset> projected,
  required double sampleRadiusPixels,
}) {
  final groups = <String, List<BdoScreenshotImportTarget>>{};
  for (final target in targets) {
    final groupId = target.parentTargetId ?? target.id;
    (groups[groupId] ??= <BdoScreenshotImportTarget>[]).add(target);
  }
  final localEvidence = <String, _WorkerNodeVisualEvidence>{};
  for (final target in targets) {
    localEvidence[target.id] = _describeWorkerNodeVisualEvidence(
      raster: raster,
      target: target,
      center: projected[target.id]!,
      projected: projected,
      sampleRadiusPixels: sampleRadiusPixels,
    );
  }
  final result = <String, _WorkerNodeVisualEvidence>{};
  for (final members in groups.values) {
    var markerStrength = 0.0;
    var routeStrength = 0.0;
    for (final member in members) {
      final evidence = localEvidence[member.id]!;
      markerStrength = math.max(markerStrength, evidence.markerStrength);
      routeStrength = math.max(routeStrength, evidence.routeStrength);
    }
    final combined = _WorkerNodeVisualEvidence(
      markerStrength: markerStrength,
      routeStrength: routeStrength,
    );
    for (final member in members) {
      result[member.id] = combined;
    }
  }
  return Map<String, _WorkerNodeVisualEvidence>.unmodifiable(result);
}

_WorkerNodeVisualEvidence _describeWorkerNodeVisualEvidence({
  required BdoScreenshotRaster raster,
  required BdoScreenshotImportTarget target,
  required Offset center,
  required Map<String, Offset> projected,
  required double sampleRadiusPixels,
}) {
  final marker = _workerMarkerColorEvidence(raster, center, sampleRadiusPixels);
  final warmContrast = math.max(0.0, marker.innerWarm - marker.outerWarm);
  final tealContrast = math.max(0.0, marker.innerTeal - marker.outerTeal);
  final warmPresence = ((marker.innerWarm - 0.10) / 0.25).clamp(0.0, 1.0);
  final tealPresence = ((marker.innerTeal - 0.18) / 0.25).clamp(0.0, 1.0);
  final warmMarker =
      ((warmContrast - 0.025) / 0.16).clamp(0.0, 1.0) * warmPresence;
  final tealMarker =
      ((tealContrast - 0.08) / 0.22).clamp(0.0, 1.0) * tealPresence;
  final routeWarm = _warmRouteEvidence(
    raster: raster,
    center: center,
    linkedTargetIds: target.linkedTargetIds,
    projected: projected,
    sampleRadiusPixels: sampleRadiusPixels,
  );
  final routeLine = ((routeWarm - 0.012) / 0.055).clamp(0.0, 1.0);
  final routeStrength = routeLine <= 0 || warmPresence <= 0
      ? 0.0
      : routeLine * 0.72 + warmPresence * 0.28;
  return _WorkerNodeVisualEvidence(
    markerStrength: math.max(warmMarker, tealMarker),
    routeStrength: routeStrength,
  );
}

({double innerWarm, double outerWarm, double innerTeal, double outerTeal})
_workerMarkerColorEvidence(
  BdoScreenshotRaster raster,
  Offset center,
  double sampleRadiusPixels,
) {
  final innerRadius = sampleRadiusPixels * 0.68;
  final outerMinimum = sampleRadiusPixels * 0.83;
  final outerMaximum = sampleRadiusPixels * 1.22;
  var innerCount = 0;
  var outerCount = 0;
  var innerWarm = 0;
  var outerWarm = 0;
  var innerTeal = 0;
  var outerTeal = 0;
  final minimumX = (center.dx - outerMaximum).floor();
  final maximumX = (center.dx + outerMaximum).ceil();
  final minimumY = (center.dy - outerMaximum).floor();
  final maximumY = (center.dy + outerMaximum).ceil();
  for (var y = minimumY; y <= maximumY; y++) {
    for (var x = minimumX; x <= maximumX; x++) {
      if (x < 0 || y < 0 || x >= raster.width || y >= raster.height) {
        continue;
      }
      final dx = x + 0.5 - center.dx;
      final dy = y + 0.5 - center.dy;
      final distance = math.sqrt(dx * dx + dy * dy);
      final inner = distance <= innerRadius;
      final outer = distance >= outerMinimum && distance <= outerMaximum;
      if (!inner && !outer) continue;
      final offset = (y * raster.width + x) * 4;
      if (raster.rgbaBytes[offset + 3] < 64) continue;
      final red = raster.rgbaBytes[offset];
      final green = raster.rgbaBytes[offset + 1];
      final blue = raster.rgbaBytes[offset + 2];
      if (inner) {
        innerCount += 1;
        if (_isWarmInvestedPixel(red, green, blue)) innerWarm += 1;
        if (_isTealInvestedPixel(red, green, blue)) innerTeal += 1;
      } else {
        outerCount += 1;
        if (_isWarmInvestedPixel(red, green, blue)) outerWarm += 1;
        if (_isTealInvestedPixel(red, green, blue)) outerTeal += 1;
      }
    }
  }
  return (
    innerWarm: innerCount == 0 ? 0 : innerWarm / innerCount,
    outerWarm: outerCount == 0 ? 0 : outerWarm / outerCount,
    innerTeal: innerCount == 0 ? 0 : innerTeal / innerCount,
    outerTeal: outerCount == 0 ? 0 : outerTeal / outerCount,
  );
}

double _warmRouteEvidence({
  required BdoScreenshotRaster raster,
  required Offset center,
  required Set<String> linkedTargetIds,
  required Map<String, Offset> projected,
  required double sampleRadiusPixels,
}) {
  var strongest = 0.0;
  for (final linkedTargetId in linkedTargetIds) {
    final end = projected[linkedTargetId];
    if (end == null) continue;
    final delta = end - center;
    final length = delta.distance;
    final startDistance = math.max(14.0, sampleRadiusPixels * 0.84);
    final endDistance = math.min(55.0, length * 0.48);
    if (endDistance <= startDistance + 3) continue;
    final direction = delta / length;
    final perpendicular = Offset(-direction.dy, direction.dx);
    var centerWarm = 0;
    var centerSamples = 0;
    var flankWarm = 0;
    var flankSamples = 0;
    for (
      var distance = startDistance;
      distance <= endDistance;
      distance += 1.5
    ) {
      for (var across = -2.5; across <= 2.5; across += 1.0) {
        final point = center + direction * distance + perpendicular * across;
        final x = point.dx.round();
        final y = point.dy.round();
        if (x < 0 || y < 0 || x >= raster.width || y >= raster.height) {
          continue;
        }
        final offset = (y * raster.width + x) * 4;
        if (raster.rgbaBytes[offset + 3] < 64) continue;
        centerSamples += 1;
        if (_isWarmInvestedPixel(
          raster.rgbaBytes[offset],
          raster.rgbaBytes[offset + 1],
          raster.rgbaBytes[offset + 2],
        )) {
          centerWarm += 1;
        }
      }
      for (final flankCenter in const <double>[-7, 7]) {
        for (var across = -1.5; across <= 1.5; across += 1.0) {
          final point =
              center +
              direction * distance +
              perpendicular * (flankCenter + across);
          final x = point.dx.round();
          final y = point.dy.round();
          if (x < 0 || y < 0 || x >= raster.width || y >= raster.height) {
            continue;
          }
          final offset = (y * raster.width + x) * 4;
          if (raster.rgbaBytes[offset + 3] < 64) continue;
          flankSamples += 1;
          if (_isWarmInvestedPixel(
            raster.rgbaBytes[offset],
            raster.rgbaBytes[offset + 1],
            raster.rgbaBytes[offset + 2],
          )) {
            flankWarm += 1;
          }
        }
      }
    }
    if (centerSamples > 0 && flankSamples > 0) {
      final centerFraction = centerWarm / centerSamples;
      final flankFraction = flankWarm / flankSamples;
      strongest = math.max(
        strongest,
        math.max(0.0, centerFraction - flankFraction),
      );
    }
  }
  return strongest;
}

bool _isWarmInvestedPixel(int red, int green, int blue) {
  final maximum = math.max(red, math.max(green, blue));
  final minimum = math.min(red, math.min(green, blue));
  final saturation = maximum <= 0 ? 0.0 : (maximum - minimum) / maximum;
  return red >= 75 &&
      red >= green * 0.98 &&
      green >= blue * 1.08 &&
      saturation >= 0.10;
}

bool _isTealInvestedPixel(int red, int green, int blue) {
  final maximum = math.max(red, math.max(green, blue));
  final minimum = math.min(red, math.min(green, blue));
  final saturation = maximum <= 0 ? 0.0 : (maximum - minimum) / maximum;
  return green >= 70 &&
      green > red * 1.10 &&
      green >= blue * 0.92 &&
      saturation >= 0.12;
}

double _mapPointDistanceSquared(BdoMapPoint first, BdoMapPoint second) {
  final dx = first.x - second.x;
  final dy = first.y - second.y;
  return dx * dx + dy * dy;
}

void _validateRadius(double radiusPixels) {
  if (!radiusPixels.isFinite || radiusPixels < 4) {
    throw ArgumentError.value(
      radiusPixels,
      'radiusPixels',
      'must be finite and at least four pixels',
    );
  }
}

void _validateAnchors(
  List<BdoScreenshotAlignmentAnchor> anchors, {
  required int minimumCount,
}) {
  if (anchors.length < minimumCount) {
    throw ArgumentError('At least $minimumCount alignment anchors are needed.');
  }
  for (final anchor in anchors) {
    if (!anchor.mapPoint.x.isFinite ||
        !anchor.mapPoint.y.isFinite ||
        !anchor.imagePoint.dx.isFinite ||
        !anchor.imagePoint.dy.isFinite) {
      throw ArgumentError('Alignment anchors must use finite coordinates.');
    }
  }
}

BdoMapPoint _mapCentroid(List<BdoScreenshotAlignmentAnchor> anchors) =>
    BdoMapPoint(
      anchors.fold<double>(0, (sum, anchor) => sum + anchor.mapPoint.x) /
          anchors.length,
      anchors.fold<double>(0, (sum, anchor) => sum + anchor.mapPoint.y) /
          anchors.length,
    );

Offset _imageCentroid(List<BdoScreenshotAlignmentAnchor> anchors) => Offset(
  anchors.fold<double>(0, (sum, anchor) => sum + anchor.imagePoint.dx) /
      anchors.length,
  anchors.fold<double>(0, (sum, anchor) => sum + anchor.imagePoint.dy) /
      anchors.length,
);

double _anchorStrength(BdoScreenshotAlignmentKind kind, int count) {
  return switch ((kind, count)) {
    (BdoScreenshotAlignmentKind.similarity, 2) => 0.62,
    (BdoScreenshotAlignmentKind.similarity, 3) => 0.82,
    (BdoScreenshotAlignmentKind.similarity, 4) => 0.92,
    (BdoScreenshotAlignmentKind.similarity, 5) => 0.96,
    (BdoScreenshotAlignmentKind.similarity, _) => 0.98,
    (BdoScreenshotAlignmentKind.affine, 3) => 0.68,
    (BdoScreenshotAlignmentKind.affine, 4) => 0.84,
    (BdoScreenshotAlignmentKind.affine, 5) => 0.92,
    (BdoScreenshotAlignmentKind.affine, _) => 0.97,
  };
}

List<double> _solveThreeByThree(
  List<List<double>> matrix,
  List<double> values,
) {
  final augmented = <List<double>>[
    for (var row = 0; row < 3; row++) <double>[...matrix[row], values[row]],
  ];
  var largestCoefficient = 0.0;
  for (final row in matrix) {
    for (final value in row) {
      largestCoefficient = math.max(largestCoefficient, value.abs());
    }
  }
  final pivotFloor = math.max(largestCoefficient * 1e-12, 1e-12);
  for (var column = 0; column < 3; column++) {
    var pivotRow = column;
    for (var row = column + 1; row < 3; row++) {
      if (augmented[row][column].abs() > augmented[pivotRow][column].abs()) {
        pivotRow = row;
      }
    }
    if (augmented[pivotRow][column].abs() <= pivotFloor) {
      throw ArgumentError('Affine alignment anchors are collinear.');
    }
    final swap = augmented[column];
    augmented[column] = augmented[pivotRow];
    augmented[pivotRow] = swap;
    final pivot = augmented[column][column];
    for (var index = column; index < 4; index++) {
      augmented[column][index] /= pivot;
    }
    for (var row = 0; row < 3; row++) {
      if (row == column) continue;
      final factor = augmented[row][column];
      for (var index = column; index < 4; index++) {
        augmented[row][index] -= factor * augmented[column][index];
      }
    }
  }
  return <double>[augmented[0][3], augmented[1][3], augmented[2][3]];
}
