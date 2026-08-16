import 'package:bdo_map_core/src/checklist/gather_checklist.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('BdoGatherChecklistEntry', () {
    test('normalizes metadata and has immutable value semantics', () {
      final entry = BdoGatherChecklistEntry(
        resourceId: '  snake-meat ',
        displayName: '  Snake Meat  ',
        sourceKind: BdoGatherChecklistSourceKind.manualGathering,
      );
      final equalEntry = BdoGatherChecklistEntry(
        resourceId: 'snake-meat',
        displayName: 'Snake Meat',
        sourceKind: BdoGatherChecklistSourceKind.manualGathering,
      );

      expect(entry, equalEntry);
      expect(entry.hashCode, equalEntry.hashCode);
      expect(entry.resourceId, 'snake-meat');
      expect(entry.displayName, 'Snake Meat');
      expect(entry.toJson(), <String, Object?>{
        'resourceId': 'snake-meat',
        'displayName': 'Snake Meat',
        'sourceKind': 'manualGathering',
      });
    });

    test('rejects an empty resource identity', () {
      expect(
        () => BdoGatherChecklistEntry(resourceId: '  '),
        throwsArgumentError,
      );
    });
  });

  group('BdoGatherChecklist operations', () {
    test('adds by ID idempotently and enriches existing metadata', () {
      final first = BdoGatherChecklist().addResource(
        resourceId: 'snake-meat',
        displayName: 'Snake Meat',
      );
      final repeated = first.addResource(
        resourceId: ' snake-meat ',
        sourceKind: BdoGatherChecklistSourceKind.manualGathering,
      );
      final unchanged = repeated.addResource(
        resourceId: 'snake-meat',
        sourceKind: BdoGatherChecklistSourceKind.manualGathering,
      );

      expect(repeated.entries, hasLength(1));
      expect(repeated.entries.single.displayName, 'Snake Meat');
      expect(
        repeated.entries.single.sourceKind,
        BdoGatherChecklistSourceKind.manualGathering,
      );
      expect(identical(unchanged, repeated), isTrue);
    });

    test('reorders safely and preserves selection', () {
      final checklist = _threeItems().select('b');

      final moved = checklist.reorder(0, 99);
      final clampedToStart = moved.moveResource('a', -12);

      expect(moved.entries.map((entry) => entry.resourceId), <String>[
        'b',
        'c',
        'a',
      ]);
      expect(clampedToStart.entries.map((entry) => entry.resourceId), <String>[
        'a',
        'b',
        'c',
      ]);
      expect(moved.selectedResourceId, 'b');
      expect(identical(checklist.reorder(-1, 2), checklist), isTrue);
      expect(identical(checklist.reorder(7, 0), checklist), isTrue);
      expect(
        identical(checklist.moveResource('missing', 0), checklist),
        isTrue,
      );
    });

    test('toggles, sets, and clears completed entries', () {
      final checklist = _threeItems()
          .select('b')
          .toggleCompletion('a')
          .setCompletion('b', true)
          .setCompletion('b', true);

      expect(checklist.completedCount, 2);
      expect(checklist.remainingCount, 1);
      expect(checklist.currentEntry?.resourceId, 'b');

      final cleared = checklist.clearCompleted();

      expect(cleared.entries.map((entry) => entry.resourceId), <String>['c']);
      expect(cleared.selectedResourceId, isNull);
      expect(identical(cleared.clearCompleted(), cleared), isTrue);
    });

    test('selection ignores stale IDs and can be explicitly cleared', () {
      final selected = _threeItems().select(' b ');

      expect(selected.selectedEntry?.resourceId, 'b');
      expect(identical(selected.select('missing'), selected), isTrue);
      expect(selected.clearSelection().selectedResourceId, isNull);
      expect(_threeItems().currentEntry?.resourceId, 'a');
    });

    test('finds and selects the next incomplete item in user order', () {
      final checklist = _threeItems().setCompletion('b', true).select('a');

      expect(checklist.nextIncompleteEntry(afterId: 'a')?.resourceId, 'c');
      expect(checklist.nextIncompleteEntry(afterId: 'c')?.resourceId, 'a');
      expect(checklist.nextIncompleteEntry(afterId: 'c', wrap: false), isNull);
      expect(checklist.selectNextIncomplete().selectedResourceId, 'c');

      final allDone = checklist
          .setCompletion('a', true)
          .setCompletion('c', true)
          .selectNextIncomplete();
      expect(allDone.firstIncompleteEntry, isNull);
      expect(allDone.selectedResourceId, isNull);
    });

    test('exposes an unmodifiable ordered entry list', () {
      final checklist = _threeItems();

      expect(
        () => checklist.entries.add(BdoGatherChecklistEntry(resourceId: 'd')),
        throwsUnsupportedError,
      );
    });
  });

  group('BdoGatherChecklist persistence', () {
    test(
      'round-trips ordered entries, metadata, completion, and selection',
      () {
        final checklist = BdoGatherChecklist(
          entries: <BdoGatherChecklistEntry>[
            BdoGatherChecklistEntry(
              resourceId: 'snake-meat',
              displayName: 'Snake Meat',
              sourceKind: BdoGatherChecklistSourceKind.manualGathering,
              isCompleted: true,
            ),
            BdoGatherChecklistEntry(
              resourceId: 'fish-roe',
              displayName: 'Fish Roe',
              sourceKind: BdoGatherChecklistSourceKind.fishing,
            ),
          ],
          selectedResourceId: 'fish-roe',
        );

        final restored = BdoGatherChecklist.fromJson(checklist.toJson());

        expect(restored, checklist);
        expect(restored.hashCode, checklist.hashCode);
        expect(restored.toJson()['schemaVersion'], 1);
      },
    );

    test('migrates aliases and skips malformed entries independently', () {
      final restored = BdoGatherChecklist.fromJson(<String, Object?>{
        'items': <Object?>[
          ' snake-meat ',
          <String, Object?>{
            'materialId': 'snake-meat',
            'name': 'Snake Meat',
            'route': 'gathering',
            'done': 'yes',
          },
          <String, Object?>{
            'itemId': 8201,
            'label': 'Rusalka Crystal',
            'source': 'worker_node',
            'isCompleted': 0,
          },
          <String, Object?>{'name': 'Missing ID'},
          null,
          true,
          const <Object?>['not', 'an', 'entry'],
        ],
        'currentItemId': 8201,
      });

      expect(restored.entries, hasLength(2));
      expect(
        restored.entries.first,
        BdoGatherChecklistEntry(
          resourceId: 'snake-meat',
          displayName: 'Snake Meat',
          sourceKind: BdoGatherChecklistSourceKind.manualGathering,
          isCompleted: true,
        ),
      );
      expect(restored.entries.last.resourceId, '8201');
      expect(
        restored.entries.last.sourceKind,
        BdoGatherChecklistSourceKind.workerNode,
      );
      expect(restored.selectedResourceId, '8201');
    });

    test('accepts legacy keyed maps and conservative defaults', () {
      final restored = BdoGatherChecklist.fromJson(<String, Object?>{
        'resources': <String, Object?>{
          'thuja-sap': <String, Object?>{
            'displayName': 'Thuja Sap',
            'completed': 'not-a-boolean',
          },
          'trout': true,
          'ash-timber': 'Ash Timber',
          'bad': const <Object?>[],
          ' ': true,
        },
        'selectedResourceId': 'does-not-exist',
      });

      expect(restored.entries.map((entry) => entry.resourceId), <String>[
        'thuja-sap',
        'trout',
        'ash-timber',
      ]);
      expect(restored.entries[0].isCompleted, isFalse);
      expect(restored.entries[1].isCompleted, isTrue);
      expect(restored.entries[2].displayName, 'Ash Timber');
      expect(restored.selectedResourceId, isNull);
    });

    test('malformed top-level data safely restores an empty checklist', () {
      expect(BdoGatherChecklist.fromJson(null), BdoGatherChecklist());
      expect(BdoGatherChecklist.fromJson('invalid'), BdoGatherChecklist());
      expect(
        BdoGatherChecklist.fromJson(<String, Object?>{'entries': 'not a list'}),
        BdoGatherChecklist(),
      );
    });
  });
}

BdoGatherChecklist _threeItems() => BdoGatherChecklist(
  entries: <BdoGatherChecklistEntry>[
    BdoGatherChecklistEntry(resourceId: 'a', displayName: 'A'),
    BdoGatherChecklistEntry(resourceId: 'b', displayName: 'B'),
    BdoGatherChecklistEntry(resourceId: 'c', displayName: 'C'),
  ],
);
