import 'package:bdo_craft_planner_flutter/data/opportunities/market_eligibility.dart';
import 'package:bdo_craft_planner_flutter/domain/catalog/temporarily_archived_items.dart';
import 'package:bdo_craft_planner_flutter/features/recipe_book/plain_item_information.dart';
import 'package:bdo_craft_planner_flutter/features/recipe_book/recipe_book_item_info.dart';
import 'package:bdo_craft_planner_flutter/features/recipe_book/reviewed_item_source_additions.dart';
import 'package:flutter_test/flutter_test.dart';

RecipeBookItemInfo info(String title, {List<String> notes = const []}) =>
    RecipeBookItemInfo(
      title: title,
      kind: 'Material',
      summary: '',
      acquisitionNotes: notes,
    );

void main() {
  test('starter seeds and crop exchange are distinct from buying the crop', () {
    final pepper = withPlainItemInformation(
      info('Hot Pepper', notes: ['Grow Hot Pepper in a garden.']),
      itemId: '7305',
    );
    expect(pepper.acquisitionNotes, [
      'Garden · Grow Hot Pepper',
      'Seeds · Buy normal seeds from Ahr in Calpheon',
      'Exchange · 1 Special Hot Pepper → 4 Hot Pepper at a Seed Vendor',
      'Central Market · When in stock',
    ]);
    final high = withPlainItemInformation(
      info('High-quality Hot Pepper'),
      itemId: '7327',
    );
    expect(
      high.acquisitionNotes,
      contains(
        'Exchange · 1 Special Hot Pepper → 2 High-Quality Hot Pepper at a Seed Vendor',
      ),
    );
    expect(high.acquisitionNotes.any((s) => s.contains('Ahr')), isFalse);
  });
  test(
    'Bean Sprouts and fermented ingredients use workers, not NPC purchases',
    () {
      for (final entry in {
        9073: 'Bean Sprouts',
        9076: 'Soybean Paste',
        9078: 'Meju',
      }.entries) {
        final result = withPlainItemInformation(
          info(entry.value, notes: ['Buy through the Central Market.']),
          itemId: '${entry.key}',
        );
        expect(result.acquisitionNotes, [
          'Central Market',
          'Workers · Jangdok Platform (Donghae / Seoul)',
        ]);
        expect(result.acquisitionFormulas, isEmpty);
      }
      final sauce = withPlainItemInformation(info('Soy Sauce'), itemId: '9075');
      expect(
        sauce.acquisitionNotes.single,
        'Workers · Extra from Soybean Paste at a Jangdok Platform (Donghae / Seoul)',
      );
    },
  );
  test('milk, weeds and gathering byproduct routes preserve amounts', () {
    final milk = withPlainItemInformation(
      info('Milk'),
      itemId: '9065',
    ).acquisitionNotes;
    expect(
      milk,
      containsAll([
        'Gather · Milk cows (10 Energy per try)',
        'Garden · Raise cows with a Haystack',
        "Exchange · 10 Witch's Delicacy → 120 Milk with Liana",
      ]),
    );
    expect(
      withPlainItemInformation(info('Weeds'), itemId: '5600').acquisitionNotes,
      contains('Gather · Pick bushes and thickets by hand'),
    );
    expect(
      withPlainItemInformation(
        info('Fruit of Nature'),
        itemId: '5205',
      ).acquisitionNotes,
      contains(
        "Exchange · 10 Fairy's Breath → 1 Fruit of Nature with Dalishain",
      ),
    );
  });
  test(
    'same ID legacy aliases and same name different IDs get no extra facts',
    () {
      expect(
        withPlainItemInformation(
          info('Trace of Despair'),
          itemId: '5960',
        ).acquisitionNotes.any((s) => s.startsWith('Exchange')),
        isFalse,
      );
      expect(
        withPlainItemInformation(
          info('Hot Pepper'),
          itemId: '999999',
        ).acquisitionNotes,
        isEmpty,
      );
      expect(
        withPlainItemInformation(
          info('Custom pepper'),
          itemId: '7305',
        ).acquisitionNotes,
        isEmpty,
      );
      expect(
        withPlainItemInformation(info('Hot Pepper')).acquisitionNotes,
        isEmpty,
      );
    },
  );
  test('market restrictions survive and market sources do not duplicate', () {
    const note = 'Not sold on the Central Market.';
    final result = withPlainItemInformation(
      info('Hot Pepper', notes: [note]),
      itemId: '7305',
    );
    expect(result.acquisitionNotes.where((s) => s.contains('Market')), [note]);
    expect(
      withPlainItemInformation(result, itemId: '7305').acquisitionNotes,
      result.acquisitionNotes,
    );
  });
  test('milk guidance is short, keeps its energy cost and appears once', () {
    final result = withPlainItemInformation(
      info(
        'Milk',
        notes: [
          'Interact with a Dairy Cow, choose the milking interaction, and complete the minigame. Each attempt consumes 10 Energy.',
        ],
      ),
      itemId: '9065',
    );
    expect(result.acquisitionNotes.where((s) => s.startsWith('Gather')), [
      'Gather · Milk cows (10 Energy per try)',
    ]);
    expect(
      result.acquisitionNotes.any((s) => s.startsWith('Interact')),
      isFalse,
    );
  });
  test(
    'registry keeps archived, nonmarketable and unknown IDs out of markets',
    () {
      expect(reviewedItemSourceAdditions.length, greaterThan(400));
      for (final entry in reviewedItemSourceAdditions.entries) {
        expect(
          temporarilyArchivedItemsById.containsKey('${entry.key}'),
          isFalse,
        );
        expect(removedPcItemsById.containsKey('${entry.key}'), isFalse);
        if (entry.value.lines.any((s) => s.startsWith('Central Market'))) {
          expect(
            reviewedNonMarketableOpportunityIds.contains('${entry.key}'),
            isFalse,
            reason: entry.value.name,
          );
        }
        expect(entry.value.lines.toSet().length, entry.value.lines.length);
        expect(
          entry.value.lines.every((s) => s.length < 115),
          isTrue,
          reason: entry.value.name,
        );
      }
      expect(reviewedItemSourceAdditions.containsKey(9001), isFalse);
      expect(reviewedItemSourceAdditions.containsKey(16002), isFalse);
    },
  );
  test('every addition is idempotent and preserves non-source information', () {
    for (final entry in reviewedItemSourceAdditions.entries) {
      final before = info(
        entry.value.name,
      ).copyWith(effects: ['Max HP +10'], notes: ['Requires Master 1.']);
      final after = withPlainItemInformation(before, itemId: '${entry.key}');
      expect(
        withPlainItemInformation(
          after,
          itemId: '${entry.key}',
        ).acquisitionNotes,
        after.acquisitionNotes,
        reason: entry.value.name,
      );
      expect(after.effects, same(before.effects));
      expect(after.notes, same(before.notes));
      expect(after.acquisitionFormulas, same(before.acquisitionFormulas));
      expect(after.craftUses, same(before.craftUses));
    }
  });
  test(
    'rare foods explain their parent dish and keep the skill requirement',
    () {
      expect(
        withPlainItemInformation(
          info('Chewy Cheese Gratin'),
          itemId: '9282',
        ).acquisitionNotes,
        contains('Cooking · Make Cheese Gratin (rare extra, Professional 3+)'),
      );
    },
  );
  test('mushroom grades do not inherit each others gathering source', () {
    final big = withPlainItemInformation(
      info('Big Fog Mushroom'),
      itemId: '5434',
    );
    final special = withPlainItemInformation(
      info('Special Fog Mushroom'),
      itemId: '5478',
    );
    expect(
      big.acquisitionNotes,
      contains(
        'Gather · Fog Mushrooms (hands or hoe; depends on Gathering level)',
      ),
    );
    expect(
      special.acquisitionNotes,
      contains('Hyphae · Use Plant Breeding in your garden'),
    );
    expect(
      special.acquisitionNotes.any((s) => s.startsWith('Gather')),
      isFalse,
    );
  });
}
