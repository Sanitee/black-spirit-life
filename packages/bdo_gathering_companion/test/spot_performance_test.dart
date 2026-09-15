import 'package:bdo_gathering_companion/domain/models.dart';
import 'package:bdo_gathering_companion/domain/spot_performance.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  GatheringSession session({
    required String id,
    required String spot,
    required String method,
    required int seconds,
    required List<LootEntry> loot,
  }) => GatheringSession(
    id: id,
    createdAt: DateTime.utc(2026, 9, 2),
    methodId: method,
    methodLabel: method,
    methodIcon: '',
    spotId: spot,
    spotName: spot,
    durationSeconds: seconds,
    loot: loot,
    buffs: const [],
    buffTotals: const {},
    catalogDate: '2026-09-02',
  );

  test('keeps methods separate and calculates item rates', () {
    final result = aggregateSpotPerformance(<GatheringSession>[
      session(
        id: 'a',
        spot: 'wolves',
        method: 'tanning',
        seconds: 1800,
        loot: <LootEntry>[
          LootEntry(id: '4998', name: 'Sharp', overrideTotal: 10),
        ],
      ),
      session(
        id: 'b',
        spot: 'wolves',
        method: 'tanning',
        seconds: 1800,
        loot: <LootEntry>[
          LootEntry(id: '4998', name: 'Sharp', overrideTotal: 20),
        ],
      ),
      session(
        id: 'c',
        spot: 'wolves',
        method: 'butcher',
        seconds: 3600,
        loot: <LootEntry>[
          LootEntry(id: '4998', name: 'Sharp', overrideTotal: 5),
        ],
      ),
    ]);

    expect(result, hasLength(2));
    final tanning = result.singleWhere((row) => row.methodId == 'tanning');
    expect(tanning.sessionCount, 2);
    expect(tanning.hours, 1);
    expect(tanning.itemsPerHour('4998'), 30);
    expect(
      result
          .singleWhere((row) => row.methodId == 'butcher')
          .itemsPerHour('4998'),
      5,
    );
  });

  test('calculates after-tax market value and preserves approximation', () {
    final result = aggregateSpotPerformance(<GatheringSession>[
      session(
        id: 'a',
        spot: 'herbs',
        method: 'hoe',
        seconds: 7200,
        loot: <LootEntry>[
          LootEntry(
            id: '4998',
            name: 'Sharp',
            overrideTotal: 4,
            isApproximate: true,
          ),
          LootEntry(id: '721003', name: 'Caphras', overrideTotal: 10),
        ],
      ),
    ]).single;

    expect(result.containsApproximateLoot, isTrue);
    expect(
      result.afterTaxSilverPerHour(<String, int>{'4998': 100, '721003': 20}),
      closeTo(253.5, 0.001),
    );
  });
}
