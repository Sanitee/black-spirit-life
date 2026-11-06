import 'dart:convert';
import 'dart:io';

import 'package:bdo_craft_planner_flutter/app/planning/planner_assembly.dart';
import 'package:bdo_craft_planner_flutter/data/catalog/bundled_catalog_parser.dart';
import 'package:bdo_craft_planner_flutter/data/catalog/catalog_repository.dart';
import 'package:bdo_craft_planner_flutter/data/opportunities/exchange_catalog.dart';
import 'package:bdo_craft_planner_flutter/data/opportunities/exchange_item_details.dart';
import 'package:bdo_craft_planner_flutter/domain/catalog/temporarily_archived_items.dart';
import 'package:bdo_craft_planner_flutter/domain/models/catalog_models.dart';
import 'package:bdo_craft_planner_flutter/domain/models/craft_mode.dart';
import 'package:bdo_craft_planner_flutter/domain/planner/acquisition_recipe_resolution.dart';
import 'package:bdo_craft_planner_flutter/domain/planner/item_acquisition_resolution.dart';
import 'package:bdo_craft_planner_flutter/domain/planner/source_resolution.dart';
import 'package:bdo_craft_planner_flutter/features/recipe_book/item_source_index.dart';
import 'package:bdo_craft_planner_flutter/features/recipe_book/plain_item_information.dart';
import 'package:bdo_craft_planner_flutter/features/recipe_book/recipe_book_exact_buff_info.dart';
import 'package:bdo_craft_planner_flutter/features/recipe_book/recipe_book_exact_crystal_info.dart';
import 'package:bdo_craft_planner_flutter/features/recipe_book/recipe_book_exact_food_info.dart';
import 'package:bdo_craft_planner_flutter/features/recipe_book/recipe_book_item_info.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

RecipeBookItemInfo item(String name, List<String> notes) => RecipeBookItemInfo(
  title: name,
  kind: 'Material',
  summary: '',
  acquisitionNotes: notes,
);

void main() {
  test('weekly quest limit stays attached to its exact source', () {
    final result = withPlainItemInformation(
      item('Crystallized Energy of Endtimes', [
        'Weekly For the Throne and Purify quests for those four zones also award it.',
        'Only one For the Throne boss quest can be completed each week.',
      ]),
    );
    expect(result.acquisitionNotes, [
      'Weekly For the Throne and Purify quests for those four zones also award it. '
          'Only one For the Throne boss quest can be completed each week.',
    ]);
    expect(
      withPlainItemInformation(result).acquisitionNotes,
      result.acquisitionNotes,
    );
  });
  test(
    'bonus quest wording is exact, idempotent and leaves richer instructions intact',
    () {
      const old =
          'Deliver Cooking Boxes through Imperial Delivery and complete the resulting Bonus Quest.';
      const short = 'Imperial Cooking · Bonus quest reward (chance)';
      expect(plainAcquisitionLine(old), short);
      expect(plainAcquisitionLine(short), short);
      expect(
        plainAcquisitionLine('$old Requires a free quest slot.'),
        '$old Requires a free quest slot.',
      );
      const unknown = 'Deliver boxes to a different quest NPC.';
      expect(plainAcquisitionLine(unknown), unknown);
      final archived = item('Archived artifact', [
        old,
      ]).copyWith(isTemporarilyArchived: true);
      expect(withPlainItemInformation(archived), same(archived));
    },
  );
  test('adds worker types without pretending every node or grade works', () {
    final trace = withPlainItemInformation(
      item('Trace of Nature', ['Buy through the Central Market.']),
      itemId: '5960',
    );
    expect(trace.acquisitionNotes, [
      'Central Market',
      'Workers · Excavation nodes',
      "Exchange · 10 Fairy's Breath → 1 Trace of Nature with Dalishain",
    ]);
    expect(
      withPlainItemInformation(
        item('Egg', []),
        itemId: '9064',
      ).acquisitionNotes,
      ['Workers · Chicken farms'],
    );
    expect(
      withPlainItemInformation(
        item('Wheat', []),
        itemId: '7001',
      ).acquisitionNotes,
      [
        'Workers · Grain nodes',
        'Seeds · Gather dried thickets or bushes by hand or with a hoe (chance)',
        'Central Market · When in stock',
      ],
    );
    expect(
      withPlainItemInformation(
        item('Special Wheat', []),
        itemId: '7011',
      ).acquisitionNotes,
      [
        'Central Market · When in stock',
        'Seeds · Use Plant Breeding in your garden',
      ],
    );
    expect(
      withPlainItemInformation(
        item('Trace of Nature', []),
        itemId: '99999999',
      ).acquisitionNotes,
      isEmpty,
    );
    expect(
      withPlainItemInformation(item('Trace of Nature', [])).acquisitionNotes,
      isEmpty,
    );
  });
  test('keeps separate gathering and worker methods, rare drops and tools', () {
    final powder = withPlainItemInformation(
      item('Powder of Darkness', [
        'Mine rocks with a pickaxe for a small chance to obtain it.',
      ]),
      itemId: '4801',
    );
    expect(powder.acquisitionNotes, [
      'Mine rocks with a pickaxe (rare)',
      'Workers · Mining nodes',
      'Exchange · 10 Mysterious Catalyst → 200 Powder of Darkness with Dalishain',
      'Central Market · When in stock',
    ]);
    final sap = withPlainItemInformation(
      item('Maple Sap', ['Collect it from Maple Tree.']),
      itemId: '5002',
    );
    expect(sap.acquisitionNotes, [
      'Collect from Maple Tree (Fluid Collector)',
      'Workers · Timber nodes',
      'Central Market · When in stock',
    ]);
    expect(
      bundledItemSourceHints[5007]!.workers,
      containsAll(['Workers · Timber nodes', 'Workers · Gathering nodes']),
    );
  });
  test('only shortens reviewed unconditional node lists', () {
    const text =
        'Grow Wheat in a garden, or send workers to Costa Farm, Moretti Plantation, Northern Wheat Plantation.';
    final compact = withPlainItemInformation(
      item('Wheat', [text]),
      itemId: '7001',
      reviewedRoutes: [text],
    );
    expect(compact.acquisitionNotes, [
      'Garden · Grow Wheat',
      'Workers · Grain nodes',
      'Seeds · Gather dried thickets or bushes by hand or with a hoe (chance)',
      'Central Market · When in stock',
    ]);
    final custom = withPlainItemInformation(
      item('Wheat', [text]),
      itemId: '7001',
    );
    expect(custom.acquisitionNotes, contains(text));
    const condition =
        'Send workers to the mine only after the quest; rare drop.';
    expect(
      withPlainItemInformation(
        item('Iron Ore', [condition]),
        itemId: '4001',
        reviewedRoutes: [condition],
      ).acquisitionNotes,
      contains(condition),
    );
  });
  test('preserves exchanges, regions, grades, signs and unavailable facts', () {
    const facts = [
      'Exchange 10 items with Dalishain for 2 Sharps. Once per Family.',
      'Only after the quest. Price: 1.5 Silver. Max HP -300.',
      'Not sold on the Central Market.',
      'Buy from Waida in Sand Grain Bazaar or Yasum in Arehaza.',
      'Weekly reward, not guaranteed. Requires Master 1.',
      'No current acquisition source is verified for this item.',
      'Use a Fluid Collector on a special tree to obtain 2 items after a quest.',
    ];
    expect(
      withPlainItemInformation(item('Custom item', facts)).acquisitionNotes,
      facts,
    );
    final archived = item(
      'Old item',
      facts,
    ).copyWith(isTemporarilyArchived: true);
    expect(withPlainItemInformation(archived, itemId: '5960'), same(archived));
    expect(
      plainAcquisitionLine('Collect it from a quest reward.'),
      'Collect it from a quest reward.',
    );
    expect(
      plainAcquisitionLine(
        'Dry Angler in the Processing window during clear weather.',
      ),
      'Dry Angler · Clear weather, on land',
    );
  });
  test('farming facts and a cooking extra retain their exact meaning', () {
    expect(
      withPlainItemInformation(item('Special Garlic', [])).acquisitionNotes,
      ['Garden · Harvest the crop'],
    );
    expect(
      withPlainItemInformation(
        item('Special unknown thing', []),
      ).acquisitionNotes,
      isEmpty,
    );
    final beer = withPlainItemInformation(
      item('Cold Draft Beer', []),
      itemId: '9283',
    );
    expect(beer.acquisitionNotes, [
      'Cooking · Make Beer (rare extra, Skilled 1+)',
      'Central Market · When in stock',
    ]);
    expect(
      withPlainItemInformation(beer, itemId: '9283').acquisitionNotes,
      beer.acquisitionNotes,
    );
  });
  test(
    'source projection is idempotent and leaves calculations and effects alone',
    () {
      final before = item('Trace of Nature', [
        'Buy through the Central Market.',
      ]).copyWith(effects: ['Max HP +300'], notes: ['Once per Family.']);
      final after = withPlainItemInformation(before, itemId: '5960');
      expect(
        withPlainItemInformation(after, itemId: '5960').acquisitionNotes,
        after.acquisitionNotes,
      );
      expect(after.effects, same(before.effects));
      expect(after.acquisitionFormulas, same(before.acquisitionFormulas));
      expect(after.craftUses, same(before.craftUses));
      expect(after.notes, same(before.notes));
    },
  );
  test('every generated worker source matches exact bundled output IDs', () {
    final bytes = File(
      'packages/bdo_map_core/assets/data/resource_map.json',
    ).readAsBytesSync();
    expect(sha256.convert(bytes).toString(), bundledItemSourceMapSha256);
    final map = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
    final nodes = (map['workerNodes'] as List).cast<Map<String, dynamic>>();
    for (final entry in bundledItemSourceHints.entries) {
      if (entry.value.workers.isNotEmpty) {
        expect(
          nodes.any(
            (n) =>
                n['isResourceNode'] == true &&
                n['isProductionNode'] == true &&
                !['1826', '1827', '1828', '1829'].contains(n['id']) &&
                (n['outputs'] as List).cast<Map<String, dynamic>>().any(
                  (o) => o['gameItemId'] == entry.key,
                ),
          ),
          isTrue,
          reason: entry.value.name,
        );
      }
      expect(
        entry.value.workers.every((s) => s.startsWith('Workers · ')),
        isTrue,
      );
      expect(entry.value.workers.toSet().length, entry.value.workers.length);
    }
  });
  test(
    'audits every catalog output, ingredient, substitute and saved info entry',
    () {
      final raw =
          jsonDecode(File('assets/data/app-data.json').readAsStringSync())
              as Map<String, dynamic>;
      final catalog = const BundledCatalogParser().parse(
        File('assets/data/app-data.json').readAsStringSync(),
      );
      final repository = CatalogRepository(catalog);
      final rules = const PlannerAssembly().plannerRules(
        catalog.supportingData,
      );
      final byMode = {
        for (final mode in CraftMode.values) mode: catalog.forMode(mode).items,
      };
      final names = <String>{
        ...rules.acquisitionInfo.keys,
        ...(raw['vendorInfo'] as Map).keys.cast<String>(),
        ...exchangeItems.values.map((item) => item.name),
        ...exactBuffInfoByName.values.map((item) => item.title),
        ...exactCrystalInfoByName.values.map((item) => item.title),
        ...exactFoodInfoByName.values.map((item) => item.title),
      };
      final consumers = <String, List<Recipe>>{};
      for (final recipes in byMode.values) {
        names.addAll(recipes.keys);
        for (final recipe in recipes.values) {
          for (final ingredient in [
            ...recipe.ingredients,
            ...recipe.variants.expand((v) => v.ingredients),
          ]) {
            for (final n in {
              ingredient.name,
              ...ingredient.options,
              ...ingredient.substituteRatios.keys,
            }) {
              names.add(n);
              consumers.putIfAbsent(n.toLowerCase(), () => []).add(recipe);
            }
          }
        }
      }
      final report = <Map<String, Object?>>[];
      final sorted = names.toList()..sort();
      for (final name in sorted) {
        final resolved = resolveAcquisitionRecipe(
          name: name,
          currentMode: CraftMode.alchemy,
          recipesByMode: byMode,
        );
        final recipe = resolved?.recipe;
        final info = recipeBookInfoFor(
          name: name,
          recipe: recipe,
          searchTerms: [],
          consumerRecipes: consumers[name.toLowerCase()] ?? [],
        )!;
        var acquisition = resolveItemAcquisition(name: name, rules: rules);
        final candidateId =
            recipe?.marketId ?? repository.bundledMarketId(name);
        if (acquisition == null && candidateId != null) {
          final matches = rules.acquisitionInfo.values
              .where((a) => a.itemId?.toString() == candidateId)
              .toList();
          if (matches.length == 1) {
            acquisition = resolveItemAcquisition(
              name: matches.single.canonicalName,
              rules: rules,
            );
          }
        }
        final source = resolveSourceInfo(
          name: name,
          recipe: recipe,
          rules: rules,
        );
        final researched = withReadableRecipeBookSections(
          withResearchedAcquisition(
            info,
            acquisition?.displayableSummaries ?? [],
            vendor: source.vendor,
            location: source.location,
            sourceNote: source.sourceNote,
          ),
        );
        final id =
            recipe?.marketId ??
            repository.bundledMarketId(name) ??
            acquisition?.itemId?.toString();
        final result = withPlainItemInformation(
          researched,
          itemId: id,
          reviewedRoutes: acquisition?.displayableSummaries,
        );
        expect(result.effects, researched.effects, reason: name);
        expect(
          result.acquisitionFormulas,
          researched.acquisitionFormulas,
          reason: name,
        );
        expect(result.craftUses, researched.craftUses, reason: name);
        if (name == "Fairy's Breath" && id == '821371') {
          // This existing exchange restriction belongs in Notes, not among
          // independent acquisition routes. No other note may change.
          expect(result.notes, [
            ...researched.notes,
            "The current Fairy's Breath does not exchange for Sharps.",
          ]);
          expect(result.acquisitionNotes, ['Gathering']);
          expect(
            result.uses,
            contains(
              'Exchange 10 with Dalishain for one reward:\n'
              '30 Wild Grass\n20 Log\n12 Rough Stone\n'
              '1 Fruit of Nature\n1 Trace of Nature\n'
              '900 Contribution EXP and 30 Gathering EXP',
            ),
          );
        } else {
          expect(result.notes, researched.notes, reason: name);
        }
        if (isTemporarilyArchivedItem(name, itemId: id)) {
          expect(result.acquisitionNotes, isEmpty, reason: name);
        }
        final exchangeItem = exchangeItems.values
            .where((entry) => entry.name == name)
            .firstOrNull;
        final exchangeDetails = exchangeItemDetails[exchangeItem?.id];
        final currency = exchangeCatalog
            .where((entry) => entry.item.id == exchangeItem?.id)
            .firstOrNull;
        final exchangeRoutes = [
          for (final entry in exchangeCatalog)
            for (final route in entry.routes)
              if (!route.directVendorSale &&
                  (route.rewardContainer?.id == exchangeItem?.id &&
                          exchangeItem != null ||
                      route.rewards.any(
                        (reward) =>
                            exchangeItem != null &&
                            reward.item?.id == exchangeItem.id,
                      )))
                {
                  'currency': entry.item.name,
                  'cost': route.inputCount,
                  'location': route.location,
                  'limit': route.limit.kind.name,
                  'maximum': route.limit.maximum,
                  'requirements': route.requirements,
                  'notes': route.notes,
                },
        ];
        final hasKnownSource =
            result.howToObtain.isNotEmpty ||
            (exchangeDetails?.howToObtain.isNotEmpty ?? false) ||
            currency != null ||
            exchangeRoutes.isNotEmpty;
        report.add({
          'name': name,
          'id': id,
          'summary': result.summary,
          'before': researched.acquisitionNotes,
          'after': result.acquisitionNotes,
          'recipes': result.acquisitionFormulas.length,
          'archived': result.isTemporarilyArchived,
          'changed':
              jsonEncode(researched.acquisitionNotes) !=
                  jsonEncode(result.acquisitionNotes) ||
              researched.summary != result.summary,
          'hasSource': hasKnownSource,
          'hasDescription': result.summary.isNotEmpty,
          'displayDescription': recipeBookUseDescription(result),
          if (exchangeItem != null)
            'exchangeSurface': {
              'summary': currency?.sourceActivity ?? exchangeDetails?.summary,
              'sources': exchangeDetails?.howToObtain ?? [],
              'effects': exchangeDetails?.effects ?? [],
              'notes': currency?.notes ?? exchangeDetails?.notes ?? [],
              'routes': exchangeRoutes,
            },
        });
      }
      expect(names.length, greaterThan(1500));
      final out = Platform.environment['BSL_SOURCE_AUDIT_PATH'];
      if (out != null) {
        File(out).writeAsStringSync(
          const JsonEncoder.withIndent('  ').convert({
            'count': report.length,
            'acquisitionEntries': rules.acquisitionInfo.length,
            'exchangeDetailEntries': exchangeItemDetails.length,
            'changed': report.where((r) => r['changed'] == true).length,
            'withoutSource': report
                .where((r) => r['hasSource'] == false && r['archived'] == false)
                .map((r) => r['name'])
                .toList(),
            'items': report,
          }),
        );
      }
    },
  );
}
