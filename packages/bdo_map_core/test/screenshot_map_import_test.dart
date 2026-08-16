import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import 'package:bdo_map_core/bdo_map_core.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('screenshot alignment', () {
    test('similarity fit reproduces scale, rotation, and translation', () {
      const angle = math.pi / 6;
      const scale = 2.5;
      const translation = Offset(130, 74);
      Offset transform(BdoMapPoint point) => Offset(
        scale * (math.cos(angle) * point.x - math.sin(angle) * point.y) +
            translation.dx,
        scale * (math.sin(angle) * point.x + math.cos(angle) * point.y) +
            translation.dy,
      );

      final points = <BdoMapPoint>[
        const BdoMapPoint(0, 0),
        const BdoMapPoint(40, 0),
        const BdoMapPoint(0, 30),
        const BdoMapPoint(40, 30),
      ];
      final alignment = BdoScreenshotAlignment.fitSimilarity(
        points.map(
          (point) => BdoScreenshotAlignmentAnchor(
            mapPoint: point,
            imagePoint: transform(point),
          ),
        ),
      );

      expect(
        (alignment.project(const BdoMapPoint(12, 17)) -
                transform(const BdoMapPoint(12, 17)))
            .distance,
        lessThan(1e-8),
      );
      expect(alignment.approximateScale, closeTo(scale, 1e-10));
      expect(alignment.confidence, closeTo(0.92, 1e-10));
    });

    test('affine fit reproduces a nonuniform town-map projection', () {
      Offset transform(BdoMapPoint point) => Offset(
        1.7 * point.x + 0.2 * point.y + 28,
        0.15 * point.x + 1.25 * point.y + 43,
      );
      final points = <BdoMapPoint>[
        const BdoMapPoint(0, 0),
        const BdoMapPoint(50, 0),
        const BdoMapPoint(0, 40),
        const BdoMapPoint(50, 40),
      ];
      final alignment = BdoScreenshotAlignment.fitAffine(
        points.map(
          (point) => BdoScreenshotAlignmentAnchor(
            mapPoint: point,
            imagePoint: transform(point),
          ),
        ),
      );

      expect(
        (alignment.project(const BdoMapPoint(21, 13)) -
                transform(const BdoMapPoint(21, 13)))
            .distance,
        lessThan(1e-8),
      );
      expect(alignment.kind, BdoScreenshotAlignmentKind.affine);
      expect(
        () => BdoScreenshotAlignment.fitAffine(<BdoScreenshotAlignmentAnchor>[
          const BdoScreenshotAlignmentAnchor(
            mapPoint: BdoMapPoint(0, 0),
            imagePoint: Offset(0, 0),
          ),
          const BdoScreenshotAlignmentAnchor(
            mapPoint: BdoMapPoint(1, 1),
            imagePoint: Offset(2, 2),
          ),
          const BdoScreenshotAlignmentAnchor(
            mapPoint: BdoMapPoint(2, 2),
            imagePoint: Offset(4, 4),
          ),
        ]),
        throwsArgumentError,
      );
    });

    test('alignment references are capped at eight named guides', () {
      final targets = <BdoScreenshotImportTarget>[
        for (var index = 0; index < 40; index++)
          BdoScreenshotImportTarget(
            id: 'guide-$index',
            label: 'Named guide $index',
            kind: BdoScreenshotTargetKind.workerNode,
            mapPoint: BdoMapPoint((index % 8) * 100.0, (index ~/ 8) * 100.0),
          ),
      ];

      final guides = BdoScreenshotAlignmentGuides.select(targets);

      expect(guides, hasLength(8));
      expect(guides.map((guide) => guide.label), everyElement(isNotEmpty));
      expect(
        () => BdoScreenshotAlignmentGuides.select(targets, maximumCount: 0),
        throwsArgumentError,
      );
    });
  });

  group('marker recognition', () {
    test(
      'built-in node palette distinguishes invested and inactive markers',
      () {
        final raster = _markerScene(
          activeCenter: const Offset(40, 40),
          inactiveCenter: const Offset(90, 40),
          activePalette: const <Color>[
            Color(0xff00aaa4),
            Color(0xfff5c02b),
            Color(0xff182325),
          ],
          inactivePalette: const <Color>[
            Color(0xffd0d0d0),
            Color(0xff777777),
            Color(0xff252525),
          ],
        );
        final result = BdoScreenshotMapImportEngine.analyze(
          raster: raster,
          alignment: _sceneAlignment(),
          profile: BdoScreenshotStateProfile.bdoWorkerNodes(),
          targets: <BdoScreenshotImportTarget>[
            BdoScreenshotImportTarget(
              id: 'node-active',
              label: 'Active node',
              kind: BdoScreenshotTargetKind.workerNode,
              mapPoint: const BdoMapPoint(0, 0),
            ),
            BdoScreenshotImportTarget(
              id: 'node-inactive',
              label: 'Inactive node',
              kind: BdoScreenshotTargetKind.workerNode,
              mapPoint: const BdoMapPoint(50, 0),
            ),
          ],
        );

        expect(
          result.targetsById['node-active']!.state,
          BdoScreenshotTargetState.active,
        );
        expect(
          result.targetsById['node-inactive']!.state,
          BdoScreenshotTargetState.inactive,
        );
      },
    );

    test(
      'graph-aligned gold production markers share evidence with their site',
      () {
        final raster = _goldProductionNodeScene();
        final result = BdoScreenshotMapImportEngine.analyze(
          raster: raster,
          alignment: _sceneAlignment(),
          profile: BdoScreenshotStateProfile.bdoWorkerNodes(),
          targets: <BdoScreenshotImportTarget>[
            BdoScreenshotImportTarget(
              id: 'site',
              label: 'Production site',
              kind: BdoScreenshotTargetKind.workerNode,
              mapPoint: const BdoMapPoint(0, 0),
              linkedTargetIds: const <String>{'route-neighbor', 'child'},
            ),
            BdoScreenshotImportTarget(
              id: 'child',
              label: 'Production subnode',
              kind: BdoScreenshotTargetKind.workerNode,
              mapPoint: const BdoMapPoint(8, 0),
              linkedTargetIds: const <String>{'site'},
              parentTargetId: 'site',
            ),
            BdoScreenshotImportTarget(
              id: 'route-neighbor',
              label: 'Connected production site',
              kind: BdoScreenshotTargetKind.workerNode,
              mapPoint: const BdoMapPoint(50, 0),
              linkedTargetIds: const <String>{'site'},
            ),
            BdoScreenshotImportTarget(
              id: 'inactive',
              label: 'Inactive site',
              kind: BdoScreenshotTargetKind.workerNode,
              mapPoint: const BdoMapPoint(0, 35),
            ),
          ],
        );

        expect(
          result.targetsById['site']!.state,
          BdoScreenshotTargetState.active,
        );
        expect(
          result.targetsById['child']!.state,
          BdoScreenshotTargetState.active,
        );
        expect(
          result.targetsById['child']!.reviewReasons,
          isNot(contains(BdoScreenshotReviewReason.overlappingTargets)),
        );
        expect(
          result.targetsById['route-neighbor']!.state,
          BdoScreenshotTargetState.active,
        );
        expect(
          result.targetsById['inactive']!.state,
          isNot(BdoScreenshotTargetState.active),
        );
      },
    );

    test('warm terrain without a marker or route is never imported', () {
      final raster = _solidRaster(const Color(0xff8b7650));
      final result = BdoScreenshotMapImportEngine.analyze(
        raster: raster,
        alignment: _sceneAlignment(),
        profile: BdoScreenshotStateProfile.bdoWorkerNodes(),
        targets: <BdoScreenshotImportTarget>[
          BdoScreenshotImportTarget(
            id: 'terrain-a',
            label: 'Terrain A',
            kind: BdoScreenshotTargetKind.workerNode,
            mapPoint: const BdoMapPoint(0, 0),
            linkedTargetIds: const <String>{'terrain-b'},
          ),
          BdoScreenshotImportTarget(
            id: 'terrain-b',
            label: 'Terrain B',
            kind: BdoScreenshotTargetKind.workerNode,
            mapPoint: const BdoMapPoint(50, 0),
            linkedTargetIds: const <String>{'terrain-a'},
          ),
        ],
      );

      expect(
        result.targets.map((target) => target.state),
        everyElement(isNot(BdoScreenshotTargetState.active)),
      );
    });

    test('owned house stays usage-neutral even with one known usage', () {
      final raster = _markerScene(
        activeCenter: const Offset(40, 40),
        inactiveCenter: const Offset(90, 40),
        activePalette: const <Color>[
          Color(0xff0097db),
          Color(0xffffcd2a),
          Color(0xff34383b),
        ],
        inactivePalette: const <Color>[
          Color(0xffbabec1),
          Color(0xff777b7e),
          Color(0xff2d3032),
        ],
      );
      final result = BdoScreenshotMapImportEngine.analyze(
        raster: raster,
        alignment: _sceneAlignment(),
        profile: BdoScreenshotStateProfile.bdoOwnedHouses(),
        targets: <BdoScreenshotImportTarget>[
          BdoScreenshotImportTarget(
            id: 'house:3',
            label: 'House 3',
            kind: BdoScreenshotTargetKind.house,
            mapPoint: const BdoMapPoint(0, 0),
            possibleHouseUsageTypeIds: const <int>{1},
          ),
        ],
      );
      final house = result.targets.single;

      expect(house.state, BdoScreenshotTargetState.active);
      expect(house.suggestedHouseUsageTypeId, isNull);
      expect(
        house.reviewReasons,
        contains(BdoScreenshotReviewReason.ambiguousHouseUsage),
      );
    });

    test('overlapping house records are withheld for review', () {
      final raster = _markerScene(
        activeCenter: const Offset(40, 40),
        inactiveCenter: const Offset(90, 40),
        activePalette: const <Color>[
          Color(0xff0097db),
          Color(0xffffcd2a),
          Color(0xff34383b),
        ],
        inactivePalette: const <Color>[
          Color(0xffbabec1),
          Color(0xff777b7e),
          Color(0xff2d3032),
        ],
      );
      final result = BdoScreenshotMapImportEngine.analyze(
        raster: raster,
        alignment: _sceneAlignment(),
        profile: BdoScreenshotStateProfile.bdoOwnedHouses(),
        targets: <BdoScreenshotImportTarget>[
          for (final id in const <String>['house:a', 'house:b'])
            BdoScreenshotImportTarget(
              id: id,
              label: id,
              kind: BdoScreenshotTargetKind.house,
              mapPoint: const BdoMapPoint(0, 0),
            ),
        ],
      );

      expect(
        result.targets.map((target) => target.state),
        everyElement(BdoScreenshotTargetState.uncertain),
      );
      expect(
        result.targets.map((target) => target.reviewReasons),
        everyElement(contains(BdoScreenshotReviewReason.overlappingTargets)),
      );
    });
  });

  group('screenshot evidence aggregation', () {
    final target = BdoScreenshotImportTarget(
      id: 'node:evidence',
      label: 'Evidence node',
      kind: BdoScreenshotTargetKind.workerNode,
      mapPoint: const BdoMapPoint(0, 0),
    );

    test('two moderate active readings reinforce one clear suggestion', () {
      final summary = BdoScreenshotEvidence.summarize(
        <BdoScreenshotTargetAnalysis>[
          _analysis(
            target,
            state: BdoScreenshotTargetState.active,
            confidence: .66,
            reviewReasons: const <BdoScreenshotReviewReason>{
              BdoScreenshotReviewReason.lowConfidence,
              BdoScreenshotReviewReason.insufficientVisualEvidence,
            },
          ),
          _analysis(
            target,
            state: BdoScreenshotTargetState.active,
            confidence: .66,
            reviewReasons: const <BdoScreenshotReviewReason>{
              BdoScreenshotReviewReason.lowConfidence,
              BdoScreenshotReviewReason.insufficientVisualEvidence,
            },
          ),
        ],
      );

      expect(summary, isNotNull);
      expect(summary!.primary.state, BdoScreenshotTargetState.active);
      expect(summary.supportCount, 2);
      expect(summary.confidence, closeTo(.792, 1e-9));
      expect(summary.highConfidence, isTrue);
      expect(summary.conflict, isFalse);
    });

    test('weak inactive evidence does not cancel a clear active reading', () {
      final summary =
          BdoScreenshotEvidence.summarize(<BdoScreenshotTargetAnalysis>[
            _analysis(
              target,
              state: BdoScreenshotTargetState.active,
              confidence: .90,
            ),
            _analysis(
              target,
              state: BdoScreenshotTargetState.inactive,
              confidence: .25,
            ),
          ]);

      expect(summary, isNotNull);
      expect(summary!.highConfidence, isTrue);
      expect(summary.conflict, isFalse);
    });

    test('strong opposing readings remain a manual-review conflict', () {
      final summary =
          BdoScreenshotEvidence.summarize(<BdoScreenshotTargetAnalysis>[
            _analysis(
              target,
              state: BdoScreenshotTargetState.active,
              confidence: .90,
            ),
            _analysis(
              target,
              state: BdoScreenshotTargetState.inactive,
              confidence: .84,
            ),
          ]);

      expect(summary, isNotNull);
      expect(summary!.conflict, isTrue);
      expect(summary.highConfidence, isFalse);
    });
  });

  test('confirmed import merges additively and closes house prerequisites', () {
    final lodgingDataset = _lodgingDataset();
    final current = BdoNodeNetworkPreferences(
      currentNodeIds: const <String>{'existing-node'},
      currentOwnedHouseIds: const <String>{'house:existing'},
      currentHouseUsageTypeIds: const <String, int>{'house:existing': 2},
    );
    final alignment = _sceneAlignment();
    final analysis = BdoScreenshotAnalysisResult(
      alignment: alignment,
      targets: <BdoScreenshotTargetAnalysis>[
        _activeAnalysis(
          BdoScreenshotImportTarget(
            id: 'new-node',
            label: 'New node',
            kind: BdoScreenshotTargetKind.workerNode,
            mapPoint: const BdoMapPoint(0, 0),
          ),
        ),
        _activeAnalysis(
          BdoScreenshotImportTarget(
            id: 'house:3',
            label: 'House 3',
            kind: BdoScreenshotTargetKind.house,
            mapPoint: const BdoMapPoint(0, 0),
            possibleHouseUsageTypeIds: const <int>{1, 2},
          ),
        ),
      ],
    );

    final merged = BdoScreenshotImportMerge.mergeConfirmedActiveTargets(
      current: current,
      analysis: analysis,
      confirmedActiveTargetIds: const <String>{'new-node', 'house:3'},
      lodgingDataset: lodgingDataset,
    );

    expect(merged.preferences.currentNodeIds, const <String>{
      'existing-node',
      'new-node',
    });
    expect(merged.preferences.currentOwnedHouseIds, const <String>{
      'house:existing',
      'house:1',
      'house:2',
      'house:3',
    });
    expect(merged.preferences.currentHouseUsageTypeIds, const <String, int>{
      'house:existing': 2,
    });
    expect(merged.addedHouseIds, const <String>{'house:3'});
    expect(merged.addedPrerequisiteHouseIds, const <String>{
      'house:1',
      'house:2',
    });
  });
}

BdoScreenshotAlignment _sceneAlignment() =>
    BdoScreenshotAlignment.fitSimilarity(<BdoScreenshotAlignmentAnchor>[
      const BdoScreenshotAlignmentAnchor(
        mapPoint: BdoMapPoint(0, 0),
        imagePoint: Offset(40, 40),
      ),
      const BdoScreenshotAlignmentAnchor(
        mapPoint: BdoMapPoint(50, 0),
        imagePoint: Offset(90, 40),
      ),
      const BdoScreenshotAlignmentAnchor(
        mapPoint: BdoMapPoint(0, 50),
        imagePoint: Offset(40, 90),
      ),
      const BdoScreenshotAlignmentAnchor(
        mapPoint: BdoMapPoint(50, 50),
        imagePoint: Offset(90, 90),
      ),
    ]);

BdoScreenshotRaster _markerScene({
  required Offset activeCenter,
  required Offset inactiveCenter,
  required List<Color> activePalette,
  required List<Color> inactivePalette,
}) {
  const width = 140;
  const height = 100;
  final bytes = Uint8List(width * height * 4);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      var color = const Color(0xff4b4438);
      final activeDistance = (Offset(x + 0.5, y + 0.5) - activeCenter).distance;
      final inactiveDistance =
          (Offset(x + 0.5, y + 0.5) - inactiveCenter).distance;
      if (activeDistance <= 13) {
        color = _markerColor(
          x: x,
          center: activeCenter,
          distance: activeDistance,
          palette: activePalette,
        );
      } else if (inactiveDistance <= 13) {
        color = _markerColor(
          x: x,
          center: inactiveCenter,
          distance: inactiveDistance,
          palette: inactivePalette,
        );
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

BdoScreenshotRaster _goldProductionNodeScene() {
  const width = 140;
  const height = 100;
  final bytes = Uint8List(width * height * 4);
  void setPixel(int x, int y, Color color) {
    if (x < 0 || y < 0 || x >= width || y >= height) return;
    final offset = (y * width + x) * 4;
    bytes[offset] = _colorChannel(color.r);
    bytes[offset + 1] = _colorChannel(color.g);
    bytes[offset + 2] = _colorChannel(color.b);
    bytes[offset + 3] = 255;
  }

  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      setPixel(x, y, const Color(0xff343630));
    }
  }
  for (var x = 40; x <= 90; x++) {
    for (var y = 38; y <= 42; y++) {
      setPixel(x, y, const Color(0xffc89a4c));
    }
  }
  void marker(Offset center, List<Color> palette) {
    for (var y = (center.dy - 14).floor(); y <= (center.dy + 14); y++) {
      for (var x = (center.dx - 14).floor(); x <= (center.dx + 14); x++) {
        final distance = (Offset(x + 0.5, y + 0.5) - center).distance;
        if (distance > 13) continue;
        setPixel(
          x,
          y,
          _markerColor(
            x: x,
            center: center,
            distance: distance,
            palette: palette,
          ),
        );
      }
    }
  }

  const active = <Color>[
    Color(0xffa97d45),
    Color(0xfff0bf58),
    Color(0xff211d18),
  ];
  const inactive = <Color>[
    Color(0xffd0d0d0),
    Color(0xff777777),
    Color(0xff252525),
  ];
  marker(const Offset(40, 40), active);
  marker(const Offset(90, 40), active);
  marker(const Offset(40, 75), inactive);
  // A large warm distractor away from every expected graph point must never
  // create a result because the analyzer does not free-search for circles.
  marker(const Offset(119, 76), active);
  return BdoScreenshotRaster(width: width, height: height, rgbaBytes: bytes);
}

BdoScreenshotRaster _solidRaster(Color color) {
  const width = 140;
  const height = 100;
  final bytes = Uint8List(width * height * 4);
  for (var offset = 0; offset < bytes.length; offset += 4) {
    bytes[offset] = _colorChannel(color.r);
    bytes[offset + 1] = _colorChannel(color.g);
    bytes[offset + 2] = _colorChannel(color.b);
    bytes[offset + 3] = 255;
  }
  return BdoScreenshotRaster(width: width, height: height, rgbaBytes: bytes);
}

int _colorChannel(double value) {
  final channel = (value * 255).round();
  if (channel < 0) return 0;
  if (channel > 255) return 255;
  return channel;
}

Color _markerColor({
  required int x,
  required Offset center,
  required double distance,
  required List<Color> palette,
}) {
  if (distance > 10.5) return const Color(0xff141718);
  final normalizedX = (x + 0.5 - (center.dx - 10.5)) / 21;
  return normalizedX < 0.56
      ? palette[0]
      : normalizedX < 0.82
      ? palette[1]
      : palette[2];
}

BdoScreenshotTargetAnalysis _activeAnalysis(BdoScreenshotImportTarget target) =>
    _analysis(target, state: BdoScreenshotTargetState.active, confidence: 0.9);

BdoScreenshotTargetAnalysis _analysis(
  BdoScreenshotImportTarget target, {
  required BdoScreenshotTargetState state,
  required double confidence,
  Set<BdoScreenshotReviewReason> reviewReasons =
      const <BdoScreenshotReviewReason>{},
}) => BdoScreenshotTargetAnalysis(
  target: target,
  imagePoint: const Offset(40, 40),
  state: state,
  confidence: confidence,
  activeDistance: state == BdoScreenshotTargetState.active ? 0 : 1,
  inactiveDistance: state == BdoScreenshotTargetState.inactive ? 0 : 1,
  reviewReasons: reviewReasons,
  suggestedHouseUsageTypeId: null,
);

LodgingDataset _lodgingDataset() {
  LodgingHouse house(String id, {String? prerequisiteHouseId}) => LodgingHouse(
    id: id,
    sourceKey: int.tryParse(id.split(':').last) ?? 99,
    name: id,
    regionId: 1,
    townNodeId: 'town:1',
    parentNodeId: 'parent:1',
    contributionPoints: 1,
    lodgingSpaces: 0,
    isLodging: false,
    usages: const <HouseUsage>[
      HouseUsage(typeId: 2, label: 'Storage', level: 1),
    ],
    prerequisiteHouseId: prerequisiteHouseId,
    position: const LodgingPosition(x: 0, y: 0, z: 0),
  );
  final houses = <LodgingHouse>[
    house('house:1'),
    house('house:2', prerequisiteHouseId: 'house:1'),
    house('house:3', prerequisiteHouseId: 'house:2'),
    house('house:existing'),
  ];
  final town = LodgingTown(
    regionId: 1,
    townNodeId: 'town:1',
    name: 'Test town',
    baseWorkerSlots: 1,
    position: const LodgingPosition(x: 0, y: 0, z: 0),
    houses: houses,
  );
  return LodgingDataset(
    schemaVersion: 2,
    manifest: LodgingDataManifest(
      datasetVersion: 'test',
      generatedAt: DateTime.utc(2026),
      sourceRepository: Uri.parse('https://example.invalid'),
      sourceCommit: 'test',
      sourceLicenseExpression: 'test',
      permittedUse: 'test',
      sourceSha256: const <String, String>{},
      townCount: 1,
      workerTownCount: 1,
      lodgingHouseCount: 0,
      nonLodgingHouseCount: houses.length,
      houseCount: houses.length,
      assumptions: const <String>[],
    ),
    towns: <LodgingTown>[town],
  );
}
