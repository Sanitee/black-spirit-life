import 'package:bdo_map_core/bdo_map_core.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  BdoGatherChecklistDemand demand(
    String source,
    String material,
    double amount,
  ) => BdoGatherChecklistDemand(
    sourceId: source,
    sourceLabel: source,
    materialKey: material,
    materialName: material,
    neededQuantity: amount,
  );

  test('v1 completion and saved IDs survive quantity migration', () {
    final old = BdoGatherChecklist.fromJson({
      'schemaVersion': 1,
      'entries': [
        {'resourceId': 'saved-id', 'completed': true},
      ],
      'selectedResourceId': 'saved-id',
    });
    expect(old.entries.single.neededQuantity, isNull);
    final next = old.addResource(
      resourceId: 'saved-id',
      demands: [demand('recipe', 'herb', 12)],
    );
    expect(next.entries.single.isCompleted, isTrue);
    expect(next.selectedResourceId, 'saved-id');
    expect(BdoGatherChecklist.fromJson(next.toJson()), next);
    expect(next.toJson()['schemaVersion'], 2);
  });

  test('same source replaces, distinct sources and materials coexist', () {
    final list = BdoGatherChecklist()
        .addResource(resourceId: 'one', demands: [demand('recipe', 'herb', 5)])
        .addResource(
          resourceId: 'one',
          demands: [demand('recipe', 'herb', 9), demand('second', 'herb', 4)],
        )
        .addResource(resourceId: 'two', demands: [demand('recipe', 'ore', 3)]);
    expect(list.entries.first.demands, hasLength(2));
    expect(list.entries.first.neededQuantity, 13);
    expect(list.entries.last.neededQuantity, 3);
    final checked = list.toggleCompletion('one');
    expect(checked.entries.first.demands, list.entries.first.demands);
    expect(() => list.entries.first.demands.clear(), throwsUnsupportedError);
  });

  test('malformed demand skipped independently, known zero remains known', () {
    final good = demand('a', 'herb', 0).toJson();
    final list = BdoGatherChecklist.fromJson({
      'entries': [
        {
          'resourceId': 'one',
          'demands': [
            good,
            {...good, 'neededQuantity': -1},
            {...good, 'neededQuantity': 'bad'},
            null,
          ],
        },
      ],
    });
    expect(list.entries.single.demands, hasLength(1));
    expect(list.entries.single.neededQuantity, 0);
    expect(const BdoGatherChecklistQuantity(needed: 5, owned: 9).remaining, 0);
    expect(const BdoGatherChecklistQuantity(owned: 9).remaining, isNull);
  });
}
