import 'dart:convert';
import 'dart:ui' as ui;

import 'package:bdo_gathering_companion/domain/models.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Catalog catalog;
  late Map<String, dynamic> rawBuffs;
  late Map<String, dynamic> rawSpots;

  Buff item(int id) => catalog.buffs.singleWhere((b) => b.id == 'buff-$id');
  Map<String, dynamic> rawItem(int id) => objectList(
    rawBuffs['buffs'],
  ).map(objectMap).singleWhere((buff) => buff['id'] == 'buff-$id');

  void expectConflict(int a, int b, bool expected) {
    expect(
      item(a).conflictsWith(item(b)),
      expected,
      reason: '${item(a).name} versus ${item(b).name}',
    );
    expect(
      item(b).conflictsWith(item(a)),
      expected,
      reason: 'Selection order must not alter the stacking rule.',
    );
  }

  setUpAll(() async {
    catalog = await Catalog.load();
    rawBuffs = objectMap(
      jsonDecode(
        await rootBundle.loadString(
          'packages/bdo_gathering_companion/assets/data/buffs.json',
        ),
      ),
    );
    rawSpots = objectMap(
      jsonDecode(
        await rootBundle.loadString(
          'packages/bdo_gathering_companion/assets/data/spots.json',
        ),
      ),
    );
  });

  test('map mirror excludes the two erroneous sea nodes', () async {
    final map = objectMap(
      jsonDecode(
        await rootBundle.loadString(
          'packages/bdo_gathering_companion/assets/data/map_nodes.json',
        ),
      ),
    );
    final nodes = objectList(map['nodes']).map(objectMap).toList();
    expect(map['datasetVersion'], '2026.10.09-beta-v5');
    expect(nodes, hasLength(608));
    expect(nodes.any((node) => ['2113', '2114'].contains(node['id'])), isFalse);
    expect(nodes.any((node) => node['name'] == 'Epeiros Mountains'), isTrue);
    final ids = nodes.map((node) => node['id']).toSet();
    for (final node in nodes) {
      for (final link in node['links'] as List) {
        expect(ids, contains(link), reason: '${node['id']} -> $link');
      }
    }
  });

  test('spot identities use material art or original hunting portraits', () {
    final expected = {
      'stillcoral-rusalka-mining': 'assets/icons/items/821255.webp',
      'edania-marble-bunnygirl-guide': 'assets/icons/items/4016.webp',
      'edania-basalt-magnetite-bunnygirl-guide': 'assets/icons/items/4017.webp',
    };
    for (final spot in catalog.spots) {
      expect(spot.icon, isNot(contains('/tools/')), reason: spot.id);
      if (expected.containsKey(spot.id)) {
        expect(spot.icon, expected[spot.id]);
      }
      if (spot.methodIds.any(['hunting', 'sniper'].contains)) {
        expect(spot.icon, startsWith('assets/icons/spots/'), reason: spot.id);
      }
    }
  });

  test('current Fairy Breath loot details list each exchange choice', () {
    final fairyBreath = catalog.commonLoot.singleWhere(
      (entry) => textOf(entry, 'itemId') == '821371',
    );
    expect(textOf(fairyBreath, 'name'), "Fairy's Breath");
    expect(textOf(fairyBreath, 'conditionalNote').split('\n'), const [
      'Exchange 10 with Dalishain. Choose one:',
      '30 Wild Grass',
      '20 Log',
      '12 Rough Stone',
      '1 Fruit of Nature',
      '1 Trace of Nature',
      '900 Contribution EXP + 30 Gathering EXP',
    ]);
    expect(
      strings(fairyBreath['sourceUrls']),
      contains(
        'https://blackdesert.pearlabyss.com/Asia/en-us/News/Notice/Detail?_boardNo=13195',
      ),
    );
    expect(textOf(fairyBreath, 'conditionalNote'), isNot(contains('Sharp')));
    expect(
      catalog.commonLoot.where((entry) => textOf(entry, 'itemId') == '820014'),
      isEmpty,
      reason: 'Dormant copies must not appear as a current Gathering drop.',
    );
    final wolves = catalog.spots.singleWhere(
      (spot) => spot.id == 'imp-cave-wolves',
    );
    expect(
      catalog.lootForSpot(wolves, 'butcher').map((item) => item.id),
      contains('821371'),
      reason:
          'The reviewed common-loot note must be reachable in spot details.',
    );
  });

  test('Evergreen Shard uses the exact Sep. 3 client item and artwork', () async {
    final calculatorItem = catalog.bairogCalculatorData!.gatheringItemTypes
        .singleWhere((entry) => entry.item.id == 821469);
    expect(calculatorItem.id, 27);
    expect(calculatorItem.item.name, 'Evergreen Shard');
    expect(calculatorItem.globalDrop, isTrue);
    expect(
      objectList(
        rawSpots['commonLoot'],
      ).where((entry) => objectMap(entry)['itemId'] == 821469),
      hasLength(1),
    );
    expect(catalog.items.where((entry) => entry.id == '15278'), isEmpty);
    final item = catalog.items.singleWhere((entry) => entry.id == '821469');
    expect(item.name, 'Evergreen Shard');
    expect(item.icon, 'assets/icons/items/821469.webp');

    final provenance = objectMap(
      jsonDecode(
        await rootBundle.loadString(
          'packages/bdo_gathering_companion/assets/icons/items/provenance.json',
        ),
      ),
    );
    final record = objectList(
      provenance['items'],
    ).map(objectMap).singleWhere((entry) => entry['itemId'] == 821469);
    expect(
      record['clientIcon'],
      'New_Icon/03_ETC/07_ProductMaterial/00821469.dds',
    );
    expect(record['byteLength'], 2536);
    final data = await rootBundle.load(item.icon);
    final bytes = data.buffer.asUint8List(
      data.offsetInBytes,
      data.lengthInBytes,
    );
    expect(bytes.length, record['byteLength']);
    expect(sha256.convert(bytes).toString(), record['sha256']);
  });

  test('Flora: Paradise uses exact installed-client artwork', () async {
    final provenance = objectMap(
      jsonDecode(
        await rootBundle.loadString(
          'packages/bdo_gathering_companion/assets/icons/items/provenance.json',
        ),
      ),
    );
    final record = objectList(
      provenance['items'],
    ).map(objectMap).singleWhere((entry) => entry['itemId'] == 764002);
    expect(record['clientIcon'], 'New_Icon/03_ETC/00760005.dds');
    expect(record['byteLength'], 2536);
    final data = await rootBundle.load(
      'packages/bdo_gathering_companion/assets/icons/items/764002.webp',
    );
    final bytes = data.buffer.asUint8List(
      data.offsetInBytes,
      data.lengthInBytes,
    );
    expect(bytes.length, record['byteLength']);
    expect(sha256.convert(bytes).toString(), record['sha256']);
  });

  group('Audited current item effects', () {
    // NA/EU patch notes, 3 September 2026, groupContentNo=10550.
    test('Seafood Cron Meal uses the increased weight limit', () {
      final seafood = item(9691);
      final description = textOf(rawItem(9691), 'effectText');
      expect(seafood.effects['maxWeight'], 250);
      expect(description, contains('Weight Limit +250 LT'));
      expect(description, isNot(contains('Weight Limit +100 LT')));
    });

    test('Perfume of Swiftness uses the renamed alchemy material', () {
      final description = textOf(rawItem(735), 'effectText');
      expect(description, contains('Great Ocean Oil x1'));
      expect(description, isNot(contains('Blue Whale Oil')));
    });

    test('stone descriptions omit retired durability instructions', () {
      const stoneIds = [721092, 45302, 750472, 45514, 45298];
      const obsoleteText = [
        'Fuel:',
        'Mystical Spirit Powder',
        "Vell's Fine Powder",
        'Recharge/Polish/Grow',
        'Use Grinding',
        'cannot use Grinding',
        'spirit is used up',
        'essence is depleted',
      ];
      for (final stoneId in stoneIds) {
        final stone = rawItem(stoneId);
        final description = <String>[
          textOf(stone, 'effectText'),
          textOf(stone, 'notes'),
        ].join('\n');
        for (final obsolete in obsoleteText) {
          expect(
            description.toLowerCase(),
            isNot(contains(obsolete.toLowerCase())),
            reason:
                '${textOf(stone, 'name')} still contains retired stone instructions.',
          );
        }
        expect(
          description.toLowerCase(),
          isNot(contains('recharg')),
          reason:
              '${textOf(stone, 'name')} still describes the retired durability system.',
        );
      }
    });

    // Independent expected values: NA/EU patch notes, 13 August 2026,
    // groupContentNo=10451; checked against the 28 August game export.
    test('August 2026 upgrades have distinct mastery and EXP effects', () {
      final viridian = item(800);
      final perfume = item(890);
      expect(viridian.duration, 20);
      expect(perfume.duration, 20);
      expect(viridian.effects['lifeMastery'], 25);
      expect(viridian.effects['lifeExpPct'], 30);
      expect(viridian.effects['gatheringSpeed'], 3);
      expect(viridian.effects['maxWeight'], 300);
      expect(perfume.effects['lifeMastery'], 50);
      expect(perfume.effects['lifeExpPct'], 25);
      expect(perfume.effects['gatheringSpeed'], 5);
      expect(perfume.effects['maxWeight'], 300);
      expectConflict(800, 890, false);
      final sum = catalog.sumBuffs([viridian.id, perfume.id]);
      expect(sum['lifeMastery'], 75);
      expect(sum['lifeExpPct'], 55);
    });

    test(
      'Verdure uses the current 20-minute duration and signed reductions',
      () {
        expect(item(791).duration, 20);
        expect(item(791).effects['lifeExpPct'], 20);
        expect(item(791).effects['cookingTimeSeconds'], -1);
        expect(item(791).effects['alchemyTimeSeconds'], -1);
        expect(item(752047).duration, 60);
        expect(item(752047).effects, item(791).effects);
        expectConflict(791, 752047, true);
        expectConflict(791, 800, true);
      },
    );

    test('renamed perfume and current account EXP are retained', () {
      expect(item(781).name, 'Perfume of Spirits');
      expect(item(781).effects['criticalHit'], 5);
      expect(item(781).effects['resourceRecoveryOnHit'], 9);
      expect(item(17583).effects['lifeExpPct'], 30);
      expect(item(45514).effects['lifeExpPct'], 30);
      expect(
        item(45514).effects.containsKey('lifeMastery'),
        isFalse,
        reason: 'Do not restore the old guide-listed Khan mastery bonus.',
      );
    });
  });

  group('Food, elixir, and stone stacking', () {
    test('Cron excludes both ordinary food families, in either order', () {
      for (final cron in [9691, 9693]) {
        for (final ordinaryFood in [9216, 9301, 9408, 9452, 9456, 9458]) {
          expectConflict(cron, ordinaryFood, true);
        }
      }
      expectConflict(9691, 9693, true);
      expectConflict(9216, 9301, true);
      expectConflict(9408, 9452, true);
      expectConflict(9456, 9458, true);
    });

    test('Fig Pie and Whale Salad are valid together without a Cron Meal', () {
      expectConflict(9301, 9458, false);
      final sum = catalog.sumBuffs([item(9301).id, item(9458).id]);
      expect(sum['gatheringItemDropPct'], 3);
      expect(sum['lifeExpPct'], 15);
      expect(sum['maxEnergy'], 20);
      expect(
        sum.containsKey('energyRecovery'),
        isFalse,
        reason: 'Instant restoration from food is not a recovery-rate buff.',
      );
    });

    test('every ordinary elixir excludes a draught, regardless of order', () {
      final elixirs = catalog.buffs.where((b) => b.category == 'elixirs');
      final draughts = catalog.buffs.where((b) => b.category == 'draughts');
      expect(elixirs, isNotEmpty);
      expect(draughts, isNotEmpty);
      for (final elixir in elixirs) {
        for (final draught in draughts) {
          expect(
            elixir.conflictsWith(draught),
            isTrue,
            reason: '${elixir.name} cannot accompany ${draught.name}.',
          );
          expect(draught.conflictsWith(elixir), isTrue);
        }
      }
      expectConflict(1159, 750, false); // Labor plus Time.
      expectConflict(1159, 1156, true); // Two Labor tiers.
      expectConflict(750, 749, true); // Two Time tiers.
      expectConflict(1158, 1155, true); // Two Mastery tiers.
    });

    test('perfumes are exclusive but remain independent of draughts', () {
      expectConflict(735, 890, true);
      expectConflict(735, 781, true);
      expectConflict(735, 791, false);
      expectConflict(735, 1159, false);
    });

    test('a Life stone and a combat stone may coexist', () {
      expectConflict(721092, 45514, true);
      expectConflict(45302, 750472, true);
      expectConflict(721092, 45298, false);
      final sum = catalog.sumBuffs([item(721092).id, item(45298).id]);
      expect(sum['gatheringItemDropPct'], 10);
      expect(sum['lifeExpPct'], 30);
      expect(sum['attackSpeedPct'], 4);
      expect(
        sum.containsKey('attackSpeed'),
        isFalse,
        reason: 'Four percent speed must not become four ability levels.',
      );
      expect(catalog.statUnit('attackSpeed'), 'levels');
      expect(catalog.statUnit('attackSpeedPct'), '%');
    });
  });

  group('Scroll families and safe totals', () {
    test('Book and Extra EXP exclude each other; Mercenary is separate', () {
      // Client buff groups: Book/Extra=5680; Mercenary=7665.
      expectConflict(18926, 17562, true);
      expectConflict(768918, 768919, true);
      expectConflict(18926, 768919, false);
      expectConflict(17562, 768919, false);
      expectConflict(18926, 47003, false);
      expect(
        item(18926).duration,
        1440,
        reason: '24-hour activation, not the seven-day book lifetime.',
      );
      expect(
        catalog.sumBuffs([item(18926).id, item(768919).id])['lifeExpPct'],
        200,
      );
    });

    test(
      'Florin and Giovan stack, while tea is separate from ordinary food',
      () {
        expectConflict(768064, 750589, false);
        expectConflict(750490, 9691, false);
        final sum = catalog.sumBuffs([item(768064).id, item(750589).id]);
        expect(sum['lifeMastery'], 200);
        expect(sum['lifeExpPct'], 40);
      },
    );

    test('Kamasylve does not increase the gathering drop-rate total', () {
      final sum = catalog.sumBuffs([item(47002).id, item(43704).id]);
      expect(sum['energyRecovery'], 3);
      expect(sum.containsKey('gatheringItemDropPct'), isFalse);
      expect(catalog.statUnit('energyRecovery'), 'per recovery tick');
      expectConflict(43704, 761893, true);
    });

    test('Energy aids separate ongoing totals from instant references', () {
      final energy = catalog.buffs.where((buff) => buff.category == 'energy');
      expect(
        energy.map((buff) => buff.id),
        containsAll({
          'buff-47002',
          'buff-43704',
          'buff-761893',
          'buff-820150',
          'buff-821144',
          'buff-821145',
          'buff-820152',
          'buff-9408',
          'buff-9452',
          'buff-9456',
          'buff-9458',
          'buff-616409',
          'buff-761074',
        }),
      );
      expect(
        catalog.buffs.map((buff) => buff.id),
        isNot(contains('buff-refreshing-dream')),
      );
      final references = energy.where((buff) => buff.referenceOnly).toList();
      expect(references.map((buff) => buff.id).toSet(), {
        'buff-589',
        'buff-17503',
        'buff-17325',
        'buff-721032',
        'buff-27866',
      });
      expect(catalog.sumBuffs(references.map((buff) => buff.id)), isEmpty);
      expect(item(820150).effects, {'energyRecovery': 30.0});
      expect(item(820152).effects, {'maxEnergy': 50.0, 'energyRecovery': 1.0});
      expectConflict(821144, 821145, true);
      expect(
        energy
            .where((buff) => buff.name.startsWith('Energy Potion'))
            .map((buff) => buff.id),
        ['buff-589'],
      );
      expect(
        energy
            .where((buff) => buff.name.startsWith('Energy Tonic'))
            .map((buff) => buff.id),
        ['buff-17503', 'buff-17325'],
      );
      for (final buff in energy) {
        expect(buff.effectSummary, isNotEmpty, reason: buff.name);
        expect(buff.obtainSummary, isNotEmpty, reason: buff.name);
        final restored = Buff(buff.snapshot());
        expect(restored.effectSummary, buff.effectSummary);
        expect(restored.obtainSummary, buff.obtainSummary);
        expect(restored.referenceOnly, buff.referenceOnly);
        expect(
          restored.components.map((component) => component.snapshot()),
          buff.components.map((component) => component.snapshot()),
        );
      }
    });

    test('energy audit covers the retained event helpers', () async {
      final eventIds = {
        860435,
        752459,
        752460,
        790575,
        752740,
        767137,
        760681,
        46952,
        47110,
        767989,
        767990,
        1000408,
      };
      final audited = [item(17325), ...eventIds.map(item)];

      expect(item(17325).category, 'energy');
      expect(item(17325).referenceOnly, isTrue);
      expect(item(17325).effectSummary, contains('+100 Energy instantly'));
      expect(item(17325).effectSummary, contains('10 min cooldown'));
      expect(
        catalog.sumBuffs(['buff-17325', 'buff-752459', 'buff-752460']),
        isEmpty,
      );

      for (final id in eventIds) {
        final buff = item(id);
        expect(buff.category, 'events', reason: buff.name);
        expect(buff.recommendedFor, contains('gathering'), reason: buff.name);
      }
      final gourd = item(752459);
      expect(gourd.referenceOnly, isTrue);
      expect(gourd.effectSummary, '+100 Energy instantly · 10 min cooldown');
      expect(gourd.obtainSummary, 'Event reward.');
      expect(item(752460).referenceOnly, isTrue);
      expect(item(790575).referenceOnly, isTrue);

      expect(item(860435).duration, 60);
      expect(item(860435).effects, {
        'gatheringExpPct': 100.0,
        'gatheringMastery': 150.0,
        'energyRecovery': 15.0,
        'maxWeight': 150.0,
        'gatheringItemDropPct': 10.0,
      });
      expect(item(752740).effects, {
        'lifeExpPct': 30.0,
        'lifeMastery': 25.0,
        'gatheringItemDropPct': 5.0,
        'energyRecovery': 1.0,
      });
      expect(item(767137).effects['luck'], 5);
      expect(catalog.statUnit('luck'), 'levels');
      expect(item(760681).duration, 600);
      expect(item(760681).effects.containsKey('gatheringItemDropPct'), isFalse);
      expect(item(46952).effects, {'energyRecovery': 1.0});
      expect(item(46952).effectSummary, contains('+20 Energy instantly'));
      expect(item(47110).effects, {'energyRecovery': 2.0, 'lifeExpPct': 20.0});
      expectConflict(767989, 767990, true);
      expectConflict(767989, 790781, true);
      expect(item(1000408).effects, {
        'lifeMastery': 150.0,
        'lifeExpPct': 50.0,
        'maxWeight': 200.0,
        'energyRecovery': 5.0,
        'movementSpeed': 5.0,
        'luck': 5.0,
      });

      for (final buff in audited) {
        expect(buff.effectSummary, isNot(contains('How to get')));
        expect(buff.obtainSummary, isNot(startsWith('Get:')));
        final icon = await rootBundle.load(
          'packages/bdo_gathering_companion/${buff.icon}',
        );
        expect(icon.lengthInBytes, greaterThan(0), reason: buff.name);
      }
    });

    test('current gathering Lightstone sets keep exact recipes and effects', () {
      final yawning = catalog.buffs.singleWhere(
        (buff) => buff.id == 'buff-yawning-hedgehog',
      );
      expect(yawning.effects, {
        'gatheringItemDropPct': 10.0,
        'gatheringExpPct': 13.0,
        'lifeExpPct': 3.0,
        'gatheringMastery': 25.0,
        'gatheringSpeed': 1.0,
      });
      expect(yawning.effects, isNot(contains('energyRecovery')));
      expect(yawning.components.map((component) => component.itemId), [
        764011,
        764003,
        764001,
        766101,
      ]);

      final scurrying = catalog.buffs.singleWhere(
        (buff) => buff.id == 'buff-scurrying-weasel',
      );
      expect(scurrying.effects, {
        'gatheringItemDropPct': 5.0,
        'gatheringExpPct': 16.0,
        'gatheringMastery': 25.0,
        'gatheringSpeed': 1.0,
      });
      expect(scurrying.effects, isNot(contains('movementSpeed')));
      expect(scurrying.components.map((component) => component.itemId), [
        764011,
        764003,
        764011,
        766101,
      ]);
      expect(yawning.conflictsWith(scurrying), isTrue);

      final delotia = catalog.buffs.singleWhere(
        (buff) => buff.id == 'buff-delotia',
      );
      expect(delotia.effects, {'lifeExpPct': 26.0});
      expect(delotia.components.map((component) => component.itemId), [
        764001,
        764001,
        764001,
        766101,
      ]);

      final handOfManos = catalog.buffs.singleWhere(
        (buff) => buff.id == 'buff-hand-of-manos',
      );
      expect(handOfManos.effects, {'lifeMastery': 45.0});
      expect(handOfManos.components.map((component) => component.itemId), [
        764002,
        764002,
        764002,
        766101,
      ]);

      final fortress = catalog.buffs.singleWhere(
        (buff) => buff.id == 'buff-fortress-of-nature',
      );
      expect(fortress.effects, {'lifeExpPct': 18.0, 'lifeMastery': 25.0});
      expect(fortress.components.map((component) => component.itemId), [
        764001,
        764002,
        764001,
        766101,
      ]);

      final choice = catalog.buffs.singleWhere(
        (buff) => buff.id == 'buff-choice-focus-gathering',
      );
      expect(choice.effects, {
        'gatheringMastery': -500.0,
        'gatheringExpPct': 41.0,
        'lifeExpPct': 3.0,
      });
      expect(choice.components.map((component) => component.itemId), [
        764011,
        764011,
        764001,
        766101,
      ]);

      final gatheringSets = catalog.buffs
          .where((buff) => buff.category == 'lightstones')
          .toList(growable: false);
      expect(gatheringSets, hasLength(6));
      for (final set in gatheringSets) {
        expect(set.recommendedFor, contains('gathering'), reason: set.name);
        expect(
          set.components.map((component) => component.name),
          everyElement(
            anyOf(
              startsWith('Lightstone of Flora:'),
              equals('Iridescent Lightstone'),
            ),
          ),
          reason: '${set.name} must not retain Wind or Fire components.',
        );
        expect(
          set.sourceUrls.first,
          'https://blackdesert.pearlabyss.com/Asia/en-US/News/Notice/Detail?_boardNo=19773',
          reason: set.name,
        );
        expect(yawning.conflictsWith(set), set.id != yawning.id);
      }

      final ancient = item(616409);
      expect(ancient.duration, 60);
      expect(ancient.effects['lifeMastery'], 25);
      expect(ancient.effects['energyRecovery'], 2);
      expect(ancient.effects['maxWeight'], 250);
      expect(ancient.effects['healthExpPct'], 30);
      final fughar = item(761074);
      expect(fughar.duration, 600);
      expect(fughar.effects['energyRecovery'], 1);
      expect(fughar.effects['lifeMastery'], 25);
      expect(fughar.effects['mountSkillExpPct'], 20);
    });

    test('simple gathering preset sums unique effects without clamping', () {
      final preset = catalog.presets.singleWhere(
        (p) => p['id'] == 'gathering-simple',
      );
      final ids = strings(preset['buffIds']);
      final sum = catalog.sumBuffs(ids);
      // Seafood=10%, Verdure=20%, Treant=30%; repeated client modules
      // must not double these values. This is a selected-bonus summary.
      expect(sum['lifeExpPct'], 60);
      expect(sum['lifeMastery'], 25);
      expect(sum['maxWeight'], 500);
      expect(sum['gatheringItemDropPct'], 10);
      expect(sum['gatheringSpeed'], 7);
      expect(sum['movementSpeed'], 5);
      expect(sum['cookingTimeSeconds'], closeTo(-2.6, 0.000001));
      expect(
        catalog.sumBuffs([...ids, ...ids]),
        sum,
        reason: 'Selecting the same item twice must not double the bonus.',
      );
      expect(catalog.sumBuffs([]), isEmpty);
    });
  });

  group('Catalog and shipped asset integrity', () {
    test('Edania March additions remain in the matchlock loot tables', () {
      final snake = catalog.spots.singleWhere(
        (spot) => spot.id == 'edania-golden-leaf-hunting',
      );
      final sheep = catalog.spots.singleWhere(
        (spot) => spot.id == 'edania-cliffside-sheep-hunting',
      );
      // Official March 5, 2026 PC update added these specific rewards.
      expect(
        catalog.lootForSpot(snake, 'hunting').map((i) => i.id),
        contains('6019'),
      );
      expect(
        catalog.lootForSpot(sheep, 'hunting').map((i) => i.id),
        containsAll(['6202', '6002']),
      );
      for (final spot in [snake, sheep]) {
        expect(
          catalog.lootForSpot(spot, 'hunting').map((i) => i.id),
          isNot(contains('821371')),
        );
      }
    });

    test('Rock Elephant gathering and hunting do not mix their rewards', () {
      final hunt = catalog.spots.singleWhere(
        (spot) => spot.id == 'edania-rock-elephant-hunting',
      );
      final gather = catalog.spots.singleWhere(
        (spot) => spot.id == 'edania-rock-elephant-gathering',
      );
      // May 14, 2026 assigns each ordinary gathering reward to its tool,
      // while Broken Ivory belongs to hunting. February furniture is separate.
      final hunted = catalog.lootForSpot(hunt, 'hunting').map((i) => i.id);
      expect(
        hunted,
        containsAll(['7962', '6359', '6026', '44236', '25221', '25224']),
      );
      expect(hunted, isNot(contains('821371')));
      for (final pair in [
        ['butcher', '7962'],
        ['fluid', '6359'],
        ['tanning', '6026'],
      ]) {
        final gathered = catalog.lootForSpot(gather, pair.first);
        expect(gathered.first.id, pair.last);
        expect(
          gathered.map((i) => i.id),
          isNot(contains(anyOf('44236', '25221', '25224', '9799'))),
        );
        for (final other in ['7962', '6359', '6026']) {
          if (other != pair.last) {
            expect(gathered.map((i) => i.id), isNot(contains(other)));
          }
        }
      }
      final landmark = catalog.mapNodes.singleWhere((n) => n.id == '2001');
      for (final spot in [hunt, gather]) {
        expect(spot.mapPrecision, 'area anchor');
        expect(spot.x, landmark.x);
        expect(spot.z, landmark.z);
      }
      expect(hunt.media, isNotEmpty);
      for (final reference in hunt.media) {
        expect(reference.methodIds, ['hunting']);
      }
      expect(gather.media, isEmpty);
    });

    test('expanded gathering and Narcion guides keep verified identities', () {
      Spot spot(String id) => catalog.spots.singleWhere((row) => row.id == id);
      Map<String, String> materials(String id) => {
        for (final row in spot(id).materials)
          '${row['itemId']}': textOf(row, 'name'),
      };

      expect(materials('serene-spring-herbs')['5439'], 'Wild Grass');
      expect(materials('gorgo-cobras'), containsPair('7922', 'Snake Meat'));
      expect(materials('gorgo-cobras'), containsPair('6222', 'Cobra Blood'));
      expect(materials('gorgo-cobras'), containsPair('6019', 'Snake Skin'));
      final ash = materials('ash-forest-lumbering');
      expect(ash['4607'], 'Cedar Timber');
      expect(ash['4606'], 'Fir Timber');
      expect(ash['5008'], 'Old Tree Bark');
      expect(
        materials('lake-flondor-flowers').keys,
        containsAll(['5524', '5525', '5526', '5527']),
      );
      expect(
        materials('garmoth-dead-tree-essence')['5019'],
        'Dead Tree Essence',
      );
      expect(materials('snowfield-cedar')['5024'], 'Snowfield Cedar Sap');

      final narcion = [
        spot('narcion-grass-rhino-hunting'),
        spot('narcion-shadow-wolf-hunting'),
        spot('narcion-shadow-lion-hunting'),
      ];
      final narcionNode = catalog.mapNodes.singleWhere(
        (node) => node.id == '1695',
      );
      expect(narcion.map((row) => row.icon).toSet(), hasLength(3));
      for (final row in narcion) {
        expect(row.methodIds, ['hunting']);
        expect(row.x, narcionNode.x);
        expect(row.z, narcionNode.z);
        expect(row.mapPrecision, 'area anchor');
        expect(row.mapNote, isNotEmpty);
      }
      expect(materials(narcion[0].id)['7904'], 'Rhino Meat');
      expect(materials(narcion[1].id)['7913'], 'Wolf Meat');
      expect(materials(narcion[2].id)['7923'], 'Lion Meat');

      final rusalka = spot('stillcoral-rusalka-mining');
      expect(
        rusalka.media.map((entry) => entry.url),
        contains('https://www.youtube.com/watch?v=QsqkO9L4u10'),
      );
    });

    test('Morning Light includes conditional hides and rare-animal loot', () {
      final preserve = catalog.spots.singleWhere(
        (spot) => spot.id == 'loml-sniper-preserve',
      );
      final ids = catalog.lootForSpot(preserve, 'sniper').map((i) => i.id);
      expect(
        ids,
        containsAll([
          '820157', '820158', '820159', '820160', // Species Supreme Hides.
          '7959', '6356', '6039', '25198', // Rare tiger.
          '25201', '25202', // Ferocious boar and bear furniture.
        ]),
      );
      expect(
        ids,
        isNot(contains('9799')),
        reason: 'Sniper prey excludes Wildspark.',
      );
      expect(ids, isNot(contains('821371')));
      for (final row in preserve.materials.where(
        (m) => [
          820157,
          820158,
          820159,
          820160,
          7959,
          6356,
          6039,
          25198,
          25201,
          25202,
        ].contains(m['itemId']),
      )) {
        expect(textOf(row, 'conditionalNote'), isNotEmpty);
        expect(strings(row['methodIds']), ['sniper']);
      }
      expect(preserve.name, contains('Wild Game Preserve'));
      expect(preserve.name, contains('Marni sniper rifle'));
    });

    test(
      'animal spots use credited portraits rather than their meat icons',
      () async {
        final wolf = catalog.spots.singleWhere(
          (spot) => spot.id == 'imp-cave-wolves',
        );
        expect(wolf.displayName, 'Wolves');
        expect(wolf.nodeName, 'Imp Cave');
        for (final spot in catalog.spots) {
          expect(spot.displayName.trim(), isNotEmpty, reason: spot.id);
          if (const {
            'edania-marble-bunnygirl-guide',
            'edania-basalt-magnetite-bunnygirl-guide',
          }.contains(spot.id)) {
            // Creator descriptions establish the region, not a named map node.
            expect(spot.nodeName, isEmpty, reason: spot.id);
            expect(spot.x, isNull, reason: spot.id);
            expect(spot.z, isNull, reason: spot.id);
          } else {
            expect(spot.nodeName.trim(), isNotEmpty, reason: spot.id);
          }
        }
        final animals = objectList(rawSpots['spots'])
            .where((spot) => objectList(spot['targetPortraits']).isNotEmpty)
            .toList();
        expect(animals.length, greaterThanOrEqualTo(10));
        final portraitData = objectMap(
          jsonDecode(
            await rootBundle.loadString(
              'packages/bdo_gathering_companion/assets/icons/spots/provenance.json',
            ),
          ),
        );
        final records = {
          for (final record in objectList(portraitData['portraits']))
            textOf(record, 'icon'): record,
        };
        for (final spot in animals) {
          final path = textOf(spot, 'icon');
          if (textOf(spot, 'id') == 'stillcoral-rusalka-mining') {
            // The user chose the mined coral for this gathering spot; hunting
            // and its target portraits still use the original animal artwork.
            expect(path, 'assets/icons/items/821255.webp');
            for (final target in objectList(spot['targetPortraits'])) {
              expect(records, contains(textOf(target, 'icon')));
            }
            continue;
          }
          expect(
            path,
            startsWith('assets/icons/spots/'),
            reason: textOf(spot, 'id'),
          );
          expect(records, contains(path));
          final materialIcons = objectList(
            spot['materials'],
          ).map((m) => textOf(m, 'icon'));
          expect(
            materialIcons,
            isNot(contains(path)),
            reason: 'Animal identity must not become a loot item icon.',
          );
          for (final target in objectList(spot['targetPortraits'])) {
            expect(records, contains(textOf(target, 'icon')));
          }
        }
        for (final entry in records.entries) {
          final record = entry.value;
          expect(textOf(record, 'npcName'), isNotEmpty);
          expect(
            record['sourcePage'],
            'https://bdocodex.com/us/npc/${record['npcId']}/',
          );
          expect(
            textOf(record, 'sourceImage'),
            startsWith('https://bdocodex.com/items/ui_artwork/'),
          );
          final data = await rootBundle.load(entry.key);
          final bytes = data.buffer.asUint8List(
            data.offsetInBytes,
            data.lengthInBytes,
          );
          expect(
            sha256.convert(bytes).toString(),
            record['sha256'],
            reason: entry.key,
          );
          final codec = await ui.instantiateImageCodec(bytes);
          final frame = await codec.getNextFrame();
          expect(
            frame.image.width,
            greaterThanOrEqualTo(48),
            reason: entry.key,
          );
          expect(
            frame.image.height,
            greaterThanOrEqualTo(48),
            reason: entry.key,
          );
          frame.image.dispose();
          codec.dispose();
        }
      },
    );

    test(
      'all referenced spot, material and node artwork decodes from the bundle',
      () async {
        final paths = <String>{
          ...catalog.spots.map((spot) => spot.icon),
          ...catalog.mapNodes.map((node) => node.icon),
          ...catalog.spots
              .expand((spot) => spot.materials)
              .map((material) => textOf(material, 'icon')),
        }..remove('');
        // Forest Crystal and aggregate material labels may have no dedicated icon.
        // The guide deliberately falls back to a real tool icon for those entries.
        for (final path in paths) {
          expect(path, startsWith('assets/icons/'));
          final data = await rootBundle.load(path);
          final codec = await ui.instantiateImageCodec(
            data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
          );
          final frame = await codec.getNextFrame();
          expect(frame.image.width, greaterThan(0), reason: path);
          expect(frame.image.height, greaterThan(0), reason: path);
          frame.image.dispose();
          codec.dispose();
        }
      },
    );

    test('all editable presets reference valid, compatible activity buffs', () {
      final activities = catalog.methods.map((m) => m.activity).toSet();
      final byId = {for (final b in catalog.buffs) b.id: b};
      expect(byId.length, catalog.buffs.length);
      expect(catalog.presets, isNotEmpty);
      for (final preset in catalog.presets) {
        final ids = strings(preset['buffIds']);
        expect(activities, contains(preset['activity']));
        expect(ids.toSet().length, ids.length);
        expect(ids.every(byId.containsKey), isTrue);
        final selected = ids.map((id) => byId[id]!).toList();
        for (var i = 0; i < selected.length; i++) {
          expect(
            selected[i].recommendedFor,
            contains(preset['activity']),
            reason: '${selected[i].name} in ${preset['name']}',
          );
          for (var j = i + 1; j < selected.length; j++) {
            expect(
              selected[i].conflictsWith(selected[j]),
              isFalse,
              reason: '${preset['name']} contains incompatible buffs.',
            );
          }
        }
      }
    });

    test(
      'tool methods retain gathering, matchlock, and sniper distinctions',
      () {
        final methods = {for (final m in catalog.methods) m.id: m};
        expect(methods.length, catalog.methods.length);
        for (final id in [
          'butcher',
          'tanning',
          'fluid',
          'hoe',
          'lumbering',
          'mining',
        ]) {
          expect(methods[id]?.activity, 'gathering');
        }
        expect(methods['hunting']?.activity, 'hunting');
        expect(methods['sniper']?.activity, 'sniper');
        for (final spot in catalog.spots) {
          expect(spot.methodIds, isNotEmpty);
          expect(
            spot.methodIds.every(methods.containsKey),
            isTrue,
            reason: '${spot.name} has an unresolved gathering method.',
          );
        }
        for (final id in [763, 699, 697, 781]) {
          expect(
            item(id).recommendedFor,
            isNot(contains('sniper')),
            reason:
                'Matchlock critical/back-attack buffs are not sniper buffs.',
          );
        }
      },
    );

    test('categories, stat units, and source URLs remain reviewable', () {
      final categories = catalog.categories.map((c) => c['id']).toSet();
      final stats = catalog.stats.map((s) => s['id']).toSet();
      expect(
        categories,
        containsAll([
          'foods',
          'draughts',
          'elixirs',
          'perfumes',
          'scrolls',
          'stones',
          'lightstones',
          'energy',
          'other',
          'events',
        ]),
      );
      for (final buff in catalog.buffs) {
        expect(categories, contains(buff.category));
        if (buff.referenceOnly) {
          expect(buff.duration, isNull, reason: buff.name);
          expect(buff.effects, isEmpty, reason: buff.name);
        } else {
          expect(buff.effects, isNotEmpty, reason: buff.name);
          if (buff.components.isNotEmpty) {
            expect(buff.duration, isNull);
          } else {
            expect(buff.duration, greaterThan(0), reason: buff.name);
          }
        }
        expect(buff.effects.keys.every(stats.contains), isTrue);
        expect(buff.sourceUrls, isNotEmpty);
        for (final source in buff.sourceUrls) {
          final uri = Uri.parse(source);
          expect(uri.scheme, 'https');
          expect(uri.host, isNotEmpty);
        }
      }
      final foods = catalog.buffs.where((b) => b.category == 'foods').toList();
      final draughts = catalog.buffs
          .where((b) => b.category == 'draughts')
          .toList();
      expect(foods.first.id, 'buff-9691');
      expect(draughts.first.id, 'buff-791');
      expect(
        objectMap(rawBuffs['itemGradeProvenance'])['verifiedCount'],
        objectList(rawBuffs['buffs']).length,
      );
      expect(rawBuffs['ordering'], contains('not measured popularity'));
    });

    test(
      'all buff and tool icons are bundled decodable game WebP assets',
      () async {
        final paths = <String>{};
        for (final raw in objectList(rawBuffs['buffs'])) {
          final provenance = objectMap(raw['provenance']);
          expect(provenance['originalIcon'], startsWith('New_Icon/'));
          expect(provenance['originalIcon'], endsWith('.dds'));
          if (raw['itemId'] case final itemId?) {
            expect(raw['icon'], 'assets/icons/buffs/$itemId.webp');
          } else {
            expect(
              raw['id'],
              anyOf(
                'buff-yawning-hedgehog',
                'buff-scurrying-weasel',
                'buff-delotia',
                'buff-hand-of-manos',
                'buff-fortress-of-nature',
                'buff-choice-focus-gathering',
              ),
            );
            expect(raw['icon'], 'assets/icons/items/766101.webp');
          }
          for (final component in objectList(raw['components'])) {
            final itemId = component['itemId'];
            expect(itemId, isA<int>());
            expect(component['icon'], 'assets/icons/items/$itemId.webp');
            paths.add(component['icon'] as String);
          }
          paths.add(raw['icon'] as String);
        }
        for (final raw in objectList(rawSpots['methods'])) {
          expect(raw['toolItemId'], isA<int>());
          expect(textOf(raw, 'toolName'), isNotEmpty);
          paths.add(raw['icon'] as String);
          if (raw['secondaryToolIcon'] case final String path) paths.add(path);
        }
        for (final path in paths) {
          final data = await rootBundle.load(path);
          final bytes = data.buffer.asUint8List(
            data.offsetInBytes,
            data.lengthInBytes,
          );
          expect(ascii.decode(bytes.sublist(0, 4)), 'RIFF', reason: path);
          expect(ascii.decode(bytes.sublist(8, 12)), 'WEBP', reason: path);
          final codec = await ui.instantiateImageCodec(bytes);
          final frame = await codec.getNextFrame();
          expect(frame.image.width, greaterThanOrEqualTo(32), reason: path);
          expect(frame.image.height, greaterThanOrEqualTo(32), reason: path);
          frame.image.dispose();
          codec.dispose();
        }
      },
    );
  });
}
