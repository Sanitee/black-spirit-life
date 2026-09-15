import 'package:bdo_gathering_companion/domain/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final spot = Spot({
    'id': 'wolves',
    'methodIds': ['butcher', 'tanning', 'fluid'],
    'materials': [
      {
        'itemId': 'meat',
        'name': 'Meat',
        'methodIds': ['butcher'],
      },
      {
        'itemId': 'hide',
        'name': 'Hide',
        'methodIds': ['tanning'],
      },
      {
        'itemId': 'blood',
        'name': 'Blood',
        'methodIds': ['fluid'],
      },
      {
        'name': 'Other rare materials',
        'methodIds': ['butcher'],
      },
      {'itemId': 'unspecified', 'name': 'No verified tool'},
    ],
  });
  final catalog = Catalog(
    methods: [],
    spots: [spot],
    buffs: [],
    items: [
      GameItem({'id': 'meat', 'name': 'Wolf Meat', 'icon': 'meat.webp'}),
    ],
    categories: [],
    stats: [],
    presets: [],
    stackingNotes: [],
    reviewedAt: '',
    commonLoot: [
      {
        'itemId': 'rare',
        'name': 'Rare',
        'methodIds': ['butcher', 'tanning'],
      },
      {
        'itemId': 'meat',
        'name': 'Duplicate meat',
        'methodIds': ['butcher'],
      },
      {
        'itemId': 'excluded',
        'name': 'Not here',
        'methodIds': ['butcher'],
        'excludedSpotIds': ['wolves'],
      },
      {
        'itemId': 'hunter',
        'name': 'Hunting drop',
        'methodIds': ['matchlock'],
      },
    ],
  );

  test('spot and tool restrict drops; identities deduplicate common loot', () {
    final butcher = catalog.lootForSpot(spot, 'butcher');
    expect(butcher.map((item) => item.id), ['meat', 'rare']);
    expect(butcher.first.name, 'Wolf Meat');
    expect(butcher.first.icon, 'meat.webp');
    expect(catalog.lootForSpot(spot, 'tanning').map((item) => item.id), [
      'hide',
      'rare',
    ]);
    expect(catalog.lootForSpot(spot, 'fluid').map((item) => item.id), [
      'blood',
    ]);
  });

  test('no guesses for an unselected spot or an incompatible tool', () {
    expect(catalog.lootForSpot(null, 'butcher'), isEmpty);
    expect(catalog.lootForSpot(spot, 'matchlock'), isEmpty);
  });

  test('maid deposits remain observations when an overall total is set', () {
    final entry = LootEntry(id: 'meat', name: 'Meat');
    entry.setStart(100);
    entry.recordMaidDeposit(600);
    entry.setSnapshot(400);
    expect(entry.total, 900);
    entry.overrideTotal = 1500;
    entry.recordMaidDeposit(200);
    expect(entry.sentAway, 800);
    expect(
      entry.total,
      1500,
      reason: 'The explicit whole-session total already includes deposits.',
    );
    entry.setSnapshot(500);
    expect(entry.overrideTotal, isNull);
    expect(
      entry.total,
      1200,
      reason: '500 remaining - 100 starting + 800 sent away.',
    );
    entry.setSnapshot(500);
    expect(
      entry.total,
      1200,
      reason: 'A repeated inventory snapshot is not another deposit.',
    );
  });
}
