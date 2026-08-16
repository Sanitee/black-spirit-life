import 'package:bdo_map_core/bdo_map_core.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('BdoActiveNodeListMatcher', () {
    test('accepts a unique exact site and activity label', () {
      final result = BdoActiveNodeListMatcher.match(
        frames: <BdoActiveNodeOcrFrame>[
          _frame(0, 120, "Pilgrim's Sanctum: Sincerity - Excavation"),
        ],
        productionNodes: <BdoWorkerNode>[
          _node('sincerity', "Pilgrim's Sanctum: Sincerity", 'Excavation'),
          _node('behr', 'Behr Riverhead', 'Mining'),
        ],
      );

      expect(result.matches, hasLength(1));
      final match = result.matches.single;
      expect(match.disposition, BdoActiveNodeMatchDisposition.accepted);
      expect(match.canonicalName, "Pilgrim's Sanctum: Sincerity");
      expect(match.canonicalActivity, 'Excavation');
      expect(match.candidateNodeIds, <String>['sincerity']);
      expect(match.confidence, 1);
      expect(match.canApplyWithoutChoice, isTrue);
    });

    test('ignores non-resource pseudo-production records', () {
      final result = BdoActiveNodeListMatcher.match(
        frames: <BdoActiveNodeOcrFrame>[
          _frame(0, 120, 'Behr Riverhead - Mining'),
        ],
        productionNodes: <BdoWorkerNode>[
          _bankNode(),
          _node('behr', 'Behr Riverhead', 'Mining'),
        ],
      );

      expect(result.matches, hasLength(1));
      expect(result.matches.single.candidateNodeIds, <String>['behr']);
      expect(result.rejected, isEmpty);
    });

    test('uses the full in-game activity suffix from each node name', () {
      final result = BdoActiveNodeListMatcher.match(
        frames: <BdoActiveNodeOcrFrame>[
          _frame(0, 100, 'Bartali Farm - Chicken Meat Production'),
          _frame(1, 200, 'Finto Farm - Potato Farming'),
          _frame(2, 300, 'Orffs Island - Fish Drying Yard 2'),
          _frame(3, 400, 'Northern Wheat Plantation - Barley Farming'),
        ],
        productionNodes: <BdoWorkerNode>[
          _node('bartali-chicken', 'Bartali Farm', 'Chicken Meat Production'),
          _node('finto-potato', 'Finto Farm', 'Potato Farming'),
          _node('orffs-yard-2', 'Orffs Island', 'Fish Drying Yard 2'),
          _node(
            'northern-wheat-barley',
            'Northern Wheat Plantation',
            'Barley Farming',
          ),
        ],
      );

      expect(result.matches, hasLength(4));
      expect(
        result.matches.map((match) => match.canonicalActivity),
        containsAll(<String>[
          'Chicken Meat Production',
          'Potato Farming',
          'Fish Drying Yard 2',
          'Barley Farming',
        ]),
      );
      expect(
        result.matches.every(
          (match) =>
              match.disposition == BdoActiveNodeMatchDisposition.accepted,
        ),
        isTrue,
      );
    });

    test('keeps a real truncated activity suffix behind review', () {
      final result = BdoActiveNodeListMatcher.match(
        frames: <BdoActiveNodeOcrFrame>[
          _frame(0, 100, 'Northern Wheat Plantation - Bar...'),
        ],
        productionNodes: <BdoWorkerNode>[
          _node(
            'northern-wheat-barley',
            'Northern Wheat Plantation',
            'Barley Farming',
          ),
        ],
      );

      final match = result.matches.single;
      expect(match.canonicalActivity, 'Barley Farming');
      expect(match.disposition, BdoActiveNodeMatchDisposition.review);
      expect(
        match.reviewReasons,
        contains(BdoActiveNodeReviewReason.truncatedText),
      );
    });

    test('keeps fuzzy and truncated OCR behind review', () {
      final result = BdoActiveNodeListMatcher.match(
        frames: <BdoActiveNodeOcrFrame>[
          _frame(0, 120, "Pilgrim's Sanctum: Sincerity - Ex..."),
          _frame(1, 430, 'Behr Riverhed - Mining'),
        ],
        productionNodes: <BdoWorkerNode>[
          _node('sincerity', "Pilgrim's Sanctum: Sincerity", 'Excavation'),
          _node('behr', 'Behr Riverhead', 'Mining'),
        ],
      );

      expect(result.matches, hasLength(2));
      expect(
        result.matches.every(
          (match) => match.disposition == BdoActiveNodeMatchDisposition.review,
        ),
        isTrue,
      );
      final truncated = result.matches.firstWhere(
        (match) => match.canonicalName!.contains('Sincerity'),
      );
      expect(
        truncated.reviewReasons,
        contains(BdoActiveNodeReviewReason.truncatedText),
      );
      expect(truncated.canApplyWithoutChoice, isFalse);
    });

    test('deduplicates overlapping frames and keeps the sharpest reading', () {
      final result = BdoActiveNodeListMatcher.match(
        frames: <BdoActiveNodeOcrFrame>[
          _frame(0, 100, 'Behr Riverhed - Mining', sharpness: 0.06),
          _frame(1, 420, 'Behr Riverhead - Mining', sharpness: 0.22),
          _frame(2, 740, 'Behr Riverhead - Mining', sharpness: 0.18),
        ],
        productionNodes: <BdoWorkerNode>[
          _node('behr', 'Behr Riverhead', 'Mining'),
        ],
      );

      expect(result.matches, hasLength(1));
      final match = result.matches.single;
      expect(match.sightingCount, 3);
      expect(match.sourceFrameIndex, 1);
      expect(match.firstTimestampMilliseconds, 100);
      expect(match.lastTimestampMilliseconds, 740);
      expect(match.disposition, BdoActiveNodeMatchDisposition.accepted);
    });

    test('never guesses between duplicate in-game labels', () {
      final result = BdoActiveNodeListMatcher.match(
        frames: <BdoActiveNodeOcrFrame>[
          _frame(0, 100, 'Godu Village - Farming'),
        ],
        productionNodes: <BdoWorkerNode>[
          _node('godu-wheat', 'Godu Village', 'Farming'),
          _node('godu-rice', 'Godu Village', 'Farming'),
        ],
      );

      final match = result.matches.single;
      expect(match.disposition, BdoActiveNodeMatchDisposition.review);
      expect(match.candidateNodeIds, <String>['godu-rice', 'godu-wheat']);
      expect(
        match.reviewReasons,
        contains(BdoActiveNodeReviewReason.ambiguousNodeIds),
      );
      expect(match.canApplyWithoutChoice, isFalse);
    });

    test('reports unmatched OCR text without mutating any setup', () {
      final result = BdoActiveNodeListMatcher.match(
        frames: <BdoActiveNodeOcrFrame>[
          _frame(0, 100, 'Completely Unknown Place - Mining'),
        ],
        productionNodes: <BdoWorkerNode>[
          _node('behr', 'Behr Riverhead', 'Mining'),
        ],
      );

      expect(result.matches, isEmpty);
      expect(result.rejected, hasLength(1));
      expect(
        result.rejected.single.reviewReasons,
        contains(BdoActiveNodeReviewReason.noProductionNodeMatch),
      );
      expect(result.rejected.single.candidateNodeIds, isEmpty);
    });

    test('ignores list chrome such as Activated count', () {
      final result = BdoActiveNodeListMatcher.match(
        frames: <BdoActiveNodeOcrFrame>[
          _frame(0, 100, 'Production Node Status'),
          _frame(0, 100, 'Activated (80)'),
          _frame(0, 100, 'Deactivated (9)'),
        ],
        productionNodes: <BdoWorkerNode>[
          _node('behr', 'Behr Riverhead', 'Mining'),
        ],
      );

      expect(result.matches, isEmpty);
      expect(result.rejected, isEmpty);
    });
  });
}

BdoActiveNodeOcrFrame _frame(
  int frameIndex,
  int timestampMilliseconds,
  String text, {
  double sharpness = 0.2,
}) => BdoActiveNodeOcrFrame(
  frameIndex: frameIndex,
  timestampMilliseconds: timestampMilliseconds,
  sharpness: sharpness,
  lines: <BdoActiveNodeOcrLine>[
    BdoActiveNodeOcrLine(
      text: text,
      frameIndex: frameIndex,
      timestampMilliseconds: timestampMilliseconds,
      frameSharpness: sharpness,
    ),
  ],
);

BdoWorkerNode _node(String id, String site, String activity) => BdoWorkerNode(
  id: id,
  name: '$site - $activity',
  nodeType: switch (activity) {
    'Excavation' => 'Excavation',
    'Farming' => 'Farm',
    'Mining' => 'Mining',
    _ => 'Gathering',
  },
  region: 'Test',
  location: const BdoWorldPoint(0, 0),
  contributionPoints: 1,
  linkIds: const <String>[],
  outputs: const <BdoNodeOutput>[],
  isResourceNode: true,
  isProductionNode: true,
);

BdoWorkerNode _bankNode() => BdoWorkerNode(
  id: '102',
  name: 'Velia - Santo Manzi Investment Bank',
  nodeType: 'Bank',
  region: 'Balenos',
  location: const BdoWorldPoint(0, 0),
  contributionPoints: 1,
  linkIds: const <String>[],
  outputs: const <BdoNodeOutput>[],
  isResourceNode: false,
  isProductionNode: true,
);
