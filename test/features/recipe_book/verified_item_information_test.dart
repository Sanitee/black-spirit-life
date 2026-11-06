import 'dart:convert';
import 'dart:io';

import 'package:bdo_craft_planner_flutter/app/state/planner_application_controller.dart';
import 'package:bdo_craft_planner_flutter/data/catalog/bundled_catalog_parser.dart';
import 'package:bdo_craft_planner_flutter/data/catalog/catalog_repository.dart';
import 'package:bdo_craft_planner_flutter/data/opportunities/exchange_catalog.dart';
import 'package:bdo_craft_planner_flutter/data/opportunities/market_eligibility.dart';
import 'package:bdo_craft_planner_flutter/domain/catalog/item_name_presentation.dart';
import 'package:bdo_craft_planner_flutter/domain/catalog/temporarily_archived_items.dart';
import 'package:bdo_craft_planner_flutter/domain/market/recipe_profitability.dart';
import 'package:bdo_craft_planner_flutter/domain/models/catalog_models.dart';
import 'package:bdo_craft_planner_flutter/domain/models/craft_mode.dart';
import 'package:bdo_craft_planner_flutter/domain/opportunities/opportunity_recipe_routes.dart';
import 'package:bdo_craft_planner_flutter/domain/planner/mastery_yields.dart';
import 'package:bdo_craft_planner_flutter/domain/planner/planner_engine.dart';
import 'package:bdo_craft_planner_flutter/domain/planner/planner_models.dart'
    as plan;
import 'package:bdo_craft_planner_flutter/domain/state/planner_state.dart';
import 'package:bdo_craft_planner_flutter/features/planner/planner_contracts.dart';
import 'package:bdo_craft_planner_flutter/features/recipe_book/exchange_reference_information.dart';
import 'package:bdo_craft_planner_flutter/features/recipe_book/plain_item_information.dart';
import 'package:bdo_craft_planner_flutter/features/recipe_book/recipe_book.dart';
import 'package:bdo_craft_planner_flutter/features/recipe_book/recipe_book_item_info.dart';
import 'package:bdo_craft_planner_flutter/features/recipe_book/recipe_book_preview_routes.dart';
import 'package:bdo_craft_planner_flutter/features/recipe_book/reviewed_artifact_facts.dart';
import 'package:bdo_craft_planner_flutter/features/recipe_book/reviewed_container_quest_sources.dart';
import 'package:bdo_craft_planner_flutter/features/recipe_book/reviewed_lustrous_gem_sources.dart';
import 'package:bdo_craft_planner_flutter/features/recipe_book/reviewed_monster_quest_sources.dart';
import 'package:bdo_craft_planner_flutter/features/recipe_book/reviewed_random_crystal_sources.dart';
import 'package:bdo_craft_planner_flutter/features/recipe_book/reviewed_raw_consumption.dart';
import 'package:bdo_craft_planner_flutter/features/recipe_book/reviewed_reference_facts.dart';
import 'package:bdo_craft_planner_flutter/features/recipe_book/reviewed_reform_recycling.dart';
import 'package:bdo_craft_planner_flutter/features/recipe_book/reviewed_weapon_recycling_sources.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late CatalogSnapshot catalog;
  late CatalogRepository repository;
  late PlannerApplicationController app;
  late Map<CraftMode, RecipeBookController> books;
  setUpAll(() {
    catalog = const BundledCatalogParser().parse(
      File('assets/data/app-data.json').readAsStringSync(),
    );
    repository = CatalogRepository(catalog);
    ModeState state(CraftMode mode, String target) => ModeState(
      target: target,
      bonusTarget: target,
      market: MarketState(),
      appearance: AppearanceSettings.defaultsFor(mode),
    );
    app = PlannerApplicationController(
      catalog: catalog,
      initialState: PlannerState(
        applicationVersion: 'synthetic-information-regression',
        lastSuccessfulWriteUtc: DateTime.utc(2026, 11, 2),
        activeMode: CraftMode.alchemy,
        alchemy: state(CraftMode.alchemy, 'Clear Liquid Reagent'),
        cooking: state(CraftMode.cooking, 'Beer'),
        processing: state(CraftMode.processing, 'Red Pepper Powder'),
        processingYields: const {},
        marketTax: MarketTax(),
        showDeleteTools: false,
      ),
      saveState: (state) async => state,
      saveDebounce: Duration.zero,
    );
    books = {
      for (final mode in CraftMode.values)
        mode: RecipeBookController(
          modeController: app.modes[mode]!,
          catalogRepository: repository,
          callingContext: RecipeBookCallingContext.planner,
          allowedTargets: app.modes[mode]!.craftableNames,
        ),
    };
  });
  tearDownAll(() {
    for (final book in books.values) {
      book.dispose();
    }
    app.dispose();
  });

  test('compact Jangdok locations and the exact Academy recipe are shared', () {
    for (final book in books.values) {
      for (final name in ['Bean Sprouts', 'Soybean Paste']) {
        expect(
          book.itemInfoFor(name)!.acquisitionNotes,
          contains('Workers · Jangdok Platform (Donghae / Seoul)'),
          reason: name,
        );
      }
      expect(
        book.itemInfoFor('Soy Sauce')!.acquisitionNotes,
        contains(
          'Workers · Extra from Soybean Paste at a Jangdok Platform (Donghae / Seoul)',
        ),
      );
      // Exact current quest 2313/8 supports this case, not every dried fish/recipe.
      final salad = book.itemInfoFor('Fish Fillet Salad')!;
      final recipe = salad.acquisitionFormulas.single;
      expect(recipe.ingredients.map((i) => (i.name, i.quantity)), [
        ('Dried Mudskipper', 1),
        ('Onion', 3),
        ('Cheese', 2),
        ('Dressing', 2),
      ]);
    }
  });

  test(
    'practical alternatives and quest source are shared by every host mode',
    () {
      for (final book in books.values) {
        for (final suffix in ['Destruction', 'Protection', 'Life']) {
          final name = "Khan's Heart: $suffix";
          final formula = book.itemInfoFor(name)!.acquisitionFormulas.single;
          final input = formula.ingredients.singleWhere(
            (i) => i.name == "Khan's Concentrated Magic",
          );
          expect(input.options, [
            "Khan's Concentrated Magic",
            "Khan's Dim Magic",
          ]);
          expect(input.substituteRatios["Khan's Dim Magic"], 3);
          expect(
            book
                .itemInfoFor("Khan's Dim Magic")!
                .craftUses
                .map((u) => u.output),
            contains(name),
          );
        }
        final dim = book.itemInfoFor("Khan's Dim Magic")!;
        expect(dim.kind, 'Quest material');
        expect(
          dim.acquisitionNotes.join(' '),
          contains("Curio · Oquilla's Eye"),
        );
        expect(dim.acquisitionNotes.join(' '), contains('once per family'));
        expect(
          dim.acquisitionNotes.join(' '),
          isNot(contains('Central Market')),
        );
        for (final mode in CraftMode.values) {
          expect(
            repository.iconDataUri(mode, dim.title, preferCleanArtwork: true),
            isNotNull,
          );
        }
        for (final row in [
          ('Immortal: Perfume of Envy', 'Immortal: Perfume of Courage'),
          ('Immortal: Perfume of Tenacity', 'Immortal: Perfume of Deep Sea'),
        ]) {
          final info = book.itemInfoFor(row.$1)!;
          expect(info.acquisitionFormulas, hasLength(4));
          expect(
            info.acquisitionFormulas.where(
              (f) => f.routeId == 'immortal-perfume',
            ),
            hasLength(2),
          );
          expect(
            book.itemInfoFor(row.$2)!.craftUses.map((u) => u.output),
            contains(row.$1),
          );
          expect(
            info.notes,
            contains(
              "Batches using Ibellab's Essence require Alchemy Skilled 1+.",
            ),
          );
        }
        for (final row in [
          (
            'Sturdy Whale Tendon Elixir',
            'Tough Whale Tendon Elixir',
            'Whale Tendon Elixir',
            3.0,
          ),
          (
            'Sturdy Whale Tendon Potion',
            'Whale Tendon Potion',
            'Superior Whale Tendon Potion',
            1 / 3,
          ),
        ]) {
          final info = book.itemInfoFor(row.$1)!;
          expect(info.acquisitionFormulas, hasLength(2));
          for (final formula in info.acquisitionFormulas) {
            final input = formula.ingredients.singleWhere(
              (i) => i.name == row.$2,
            );
            expect(input.options, [row.$2, row.$3]);
            expect(input.substituteRatios[row.$3], row.$4);
          }
          expect(
            book.itemInfoFor(row.$3)!.craftUses.map((u) => u.output),
            contains(row.$1),
          );
        }
      }
    },
  );

  test(
    'practical source steps replace vague categories and preserve other sources',
    () {
      for (final book in books.values) {
        for (final row in [
          ('Blush Leaf', 'Farming', 'Breed crops'),
          ("Witch's Delicacy", 'Cooking', 'Cooking Utensil'),
          ('Mysterious Catalyst', 'Alchemy', 'Alchemy Tool'),
          ('Wildspark', 'Hunting', 'Hunting Mastery 250+'),
          (
            "Atanis' Element",
            'Combat in selected monster zones',
            'Monster Zone Info',
          ),
          ('Sangpyeong Coin', 'Land of the Morning Light', 'daily quests'),
          (
            "Sethra's Artifact - Gathering EXP",
            'All Gathering activities.',
            'not water scooping',
          ),
          (
            "Sethra's Artifact - Gathering Mastery",
            'All Gathering activities.',
            'not water scooping',
          ),
          (
            "Sethra's Artifact - Gathering Item Drop Rate",
            'All Gathering activities.',
            'not water scooping',
          ),
          (
            "Sethra's Artifact - Hunting EXP",
            'All Hunting activities.',
            'Butcher hunted',
          ),
          (
            "Sethra's Artifact - Hunting Mastery",
            'All Hunting activities.',
            'Butcher hunted',
          ),
          (
            "Sethra's Artifact - Life EXP",
            'All Life Skill activities.',
            'Imperial Delivery',
          ),
          (
            "Sethra's Artifact - Life Skill Mastery",
            'All Life Skill activities.',
            'Imperial Delivery',
          ),
        ]) {
          final info = book.itemInfoFor(row.$1)!;
          expect(
            info.acquisitionNotes,
            isNot(contains(row.$2)),
            reason: row.$1,
          );
          expect(
            info.acquisitionNotes.join(' '),
            contains(row.$3),
            reason: row.$1,
          );
        }
        for (final name in [
          "Sethra's Artifact - Life EXP",
          "Sethra's Artifact - Life Skill Mastery",
        ]) {
          final info = book.itemInfoFor(name)!;
          expect(info.acquisitionNotes.join(' '), contains('Hollow Maretta'));
          expect(
            info.notes,
            contains('Gathering: not barehanded, water scooping or shoveling.'),
          );
        }
      }
    },
  );

  test(
    'research status stays outside item windows without inventing sources',
    () {
      for (final book in books.values) {
        for (final name in [
          'Black Essence',
          'Rhutum Belt',
          "Hunter's Seal",
          'Sangpyeong Coin Chest',
        ]) {
          final info = book.itemInfoFor(name)!;
          expect(
            [...info.acquisitionNotes, ...info.notes].any(
              (s) =>
                  s.contains('is verified') ||
                  s.contains('verified current limit') ||
                  s.contains('differs between the old patch notes'),
            ),
            isFalse,
            reason: name,
          );
        }
        final chest = book.itemInfoFor('Sangpyeong Coin Chest')!;
        expect(chest.summary, isEmpty);
        expect(
          chest.acquisitionNotes,
          contains('Geowan (Byeot County) · 1,000 Sangpyeong Coins per chest'),
        );
        expect(
          chest.notes,
          contains("Two chests for Miss Myo's quest (once per family)."),
        );
        expect(chest.uses.join(' '), contains('Miss Myo'));
      }
    },
  );

  test(
    'Deep Blue Tidal shows both exact alternatives and reverse uses in every mode',
    () {
      for (final book in books.values) {
        final info = book.itemInfoFor('Deep Blue Tidal Draught')!;
        expect(
          info.acquisitionNotes,
          contains('Simple Alchemy · Processing (L)'),
        );
        expect(
          info.acquisitionNotes.any((n) => n.contains('Reviewed NA/EU')),
          isFalse,
        );
        expect(info.acquisitionFormulas, hasLength(1));
        final formula = info.acquisitionFormulas.single;
        expect(formula.outputMinimum, 1);
        expect(formula.outputMaximum, 1);
        final tidal = formula.ingredients.singleWhere(
          (i) => i.name == 'Tidal Draught',
        );
        expect(tidal.quantity, 4);
        expect(tidal.options, ['Tidal Draught', 'Blue Tidal Draught']);
        expect(tidal.substituteRatios['Blue Tidal Draught'], 0.5);
        expect(
          book
              .itemInfoFor('Blue Tidal Draught')!
              .craftUses
              .map((u) => u.output),
          contains('Deep Blue Tidal Draught'),
        );
      }
    },
  );

  test(
    'processing guidance is specific, short and preserves restrictions in every mode',
    () {
      for (final book in books.values) {
        expect(
          book.itemInfoFor('Black Gold Ingot')!.acquisitionNotes,
          contains(
            "Heat [Guild] Ocean Stalker's Skin ×10 + Pure Platinum Crystal ×2.",
          ),
        );
        expect(
          book.itemInfoFor('Black Magic Crystal - Addis')!.acquisitionNotes,
          contains(
            'Heat Black Essence: Addis ×1 + Ancient Magic Crystal - Addis ×1.',
          ),
        );
        final delotia = book.itemInfoFor('Delotia Powder')!;
        expect(delotia.acquisitionNotes, contains('Grinding · Delotia'));
        expect(delotia.acquisitionFormulas, hasLength(2));
        expect(
          delotia.acquisitionFormulas
              .expand((f) => f.ingredients)
              .map((i) => i.name),
          containsAll(['High-quality Delotia', 'Special Delotia']),
        );
        for (final name in ['Breath of All Creations', "Elion's Tear"]) {
          final info = book.itemInfoFor(name)!;
          expect(
            info.acquisitionNotes,
            contains('Simple Alchemy · Processing (L)'),
          );
          expect(
            info.acquisitionNotes.any((s) => s.contains('formula verified')),
            isFalse,
          );
        }
        expect(
          book.itemInfoFor('Melted Iron Shard')!.acquisitionNotes,
          contains('Heating · Ore (equipment recycling not planned)'),
        );
        for (final name in [
          'Fancy Feather',
          'Fine Fancy Feather',
          'Fine Lightweight Plume',
          'Lightweight Plume',
          'Purified Water',
        ]) {
          final info = book.itemInfoFor(name)!;
          expect(
            info.notes.where((s) => s == 'Filtering requires wind.'),
            hasLength(1),
          );
        }
        expect(
          book.itemInfoFor('Black Gold Ingot')!.notes,
          isNot(contains('Filtering requires wind.')),
        );
      }
    },
  );

  test('specific crafting sources replace vague directions in every mode', () {
    const crystals = ['Harphia', 'Cobelinus', 'Viper', 'Hystria', 'Carmae'];
    for (final book in books.values) {
      for (final type in [...crystals, 'Addis']) {
        final info = book.itemInfoFor('Black Magic Crystal - $type')!;
        expect(
          info.acquisitionNotes,
          contains(
            'Heat Black Essence: $type ×1 + Ancient Magic Crystal - $type ×1.',
          ),
        );
        expect(
          info.acquisitionNotes.any((s) => s.contains('Crafting Notes')),
          isFalse,
        );
        expect(info.acquisitionNotes.join(' '), contains('Rough Lustrous Gem'));
        expect(info.acquisitionNotes.join(' '), contains('Central Market'));
        expect(info.acquisitionFormulas, isEmpty);
      }
      final passion = book.itemInfoFor('Passion of Valtarra')!;
      expect(passion.acquisitionNotes, [
        "Simple Alchemy · Valtarra's Flame ×100 + Garmoth's Scale ×100",
      ]);
      expect(passion.acquisitionFormulas, isEmpty);
    }
  });

  test(
    'specific crafting hints never leak across identities or archived items',
    () {
      for (final id in [15628, 15629, 15630, 15631, 15632, 8125]) {
        final facts = reviewedReferenceFacts[id]!;
        final plain = RecipeBookItemInfo(
          title: facts.name,
          kind: 'Material',
          summary: '',
          acquisitionNotes: const ['Keep this other source'],
        );
        final updated = withReviewedReferenceFacts(plain, itemId: '$id');
        expect(
          updated.acquisitionNotes,
          containsAll(['Keep this other source', ...facts.sources]),
        );
        expect(
          withReviewedReferenceFacts(updated, itemId: '$id').acquisitionNotes,
          updated.acquisitionNotes,
        );
        expect(
          withReviewedReferenceFacts(plain, itemId: '999999').acquisitionNotes,
          plain.acquisitionNotes,
        );
        final wrongName = plain.copyWith(title: '[Event] ${facts.name}');
        expect(
          withReviewedReferenceFacts(wrongName, itemId: '$id').acquisitionNotes,
          wrongName.acquisitionNotes,
        );
        final archived = plain.copyWith(isTemporarilyArchived: true);
        expect(
          withReviewedReferenceFacts(archived, itemId: '$id').acquisitionNotes,
          archived.acquisitionNotes,
        );
      }
    },
  );

  test(
    'artifact bonus quest sources retain the trigger and chance qualification',
    () {
      const types = {
        'Alchemy EXP': 'Imperial Alchemy · Bonus quest reward (chance)',
        'Alchemy Mastery': 'Imperial Alchemy · Bonus quest reward (chance)',
        'Cooking EXP': 'Imperial Cooking · Bonus quest reward (chance)',
        'Cooking Mastery': 'Imperial Cooking · Bonus quest reward (chance)',
        'Fishing EXP': 'Imperial Fishing · Bonus quest reward (chance)',
        'Fishing Mastery': 'Imperial Fishing · Bonus quest reward (chance)',
        'Mount EXP': 'Imperial Horse Delivery · Bonus quest reward (chance)',
        'Training EXP': 'Imperial Horse Delivery · Bonus quest reward (chance)',
        'Training Mastery':
            'Imperial Horse Delivery · Bonus quest reward (chance)',
        'Processing EXP':
            'Imperial Delivery · Cooking/medicine boxes or processed trade goods (bonus quest chance)',
        'Processing Mastery':
            'Imperial Delivery · Cooking/medicine boxes or processed trade goods (bonus quest chance)',
        'Processing Success Rate':
            'Imperial Delivery · Cooking/medicine boxes or processed trade goods (bonus quest chance)',
        'Trading EXP':
            'Trading · Bonus quest when selling trade goods (chance)',
      };
      for (final book in books.values) {
        for (final entry in types.entries) {
          final info = book.itemInfoFor("Sethra's Artifact - ${entry.key}")!;
          expect(info.acquisitionNotes, [entry.value]);
          expect(info.acquisitionFormulas, isEmpty);
          expect(info.effects, isNotEmpty);
        }
      }
    },
  );

  test('common processing sources are specific without inventing yields', () {
    const sources = {
      'Polished Stone': 'Grind Rough Stone ×10.',
      'Fine Soft Hide': 'Dry Soft Hide ×10.',
      'Snowfield Cedar Plywood': 'Chop Snowfield Cedar Plank ×10.',
      'Melted Gold Shard': 'Heat Alluvial Gold (not included in planning).',
    };
    for (final book in books.values) {
      for (final entry in sources.entries) {
        final info = book.itemInfoFor(entry.key)!;
        expect(info.acquisitionNotes, contains(entry.value));
        expect(
          info.acquisitionNotes,
          isNot(contains('Processing · See Crafting Notes')),
        );
      }
      expect(book.itemInfoFor('Polished Stone')!.acquisitionFormulas, isEmpty);
      expect(
        book
            .itemInfoFor('Fine Soft Hide')!
            .acquisitionFormulas
            .single
            .ingredients
            .single
            .name,
        'Snow Leopard Hide',
      );
      expect(
        book
            .itemInfoFor('Snowfield Cedar Plywood')!
            .acquisitionFormulas
            .single
            .ingredients
            .single
            .name,
        'Snowfield Cedar Timber',
      );
      expect(
        book
            .itemInfoFor('Melted Gold Shard')!
            .acquisitionFormulas
            .single
            .ingredients
            .single
            .name,
        'Gold Ore',
      );
      for (final name in [
        'Cheese',
        'Fine Soft Hide',
        'Fine Thick Fur',
        'Fine Fancy Reptile Skin',
        'Moon Vein Flax Fabric',
      ]) {
        expect(
          book
              .itemInfoFor(name)!
              .notes
              .where((n) => n == 'Drying: clear weather, on land.'),
          hasLength(1),
        );
      }
      expect(
        book.itemInfoFor('Dried Amberjack')!.notes,
        isNot(contains('Drying: clear weather, on land.')),
      );
      expect(
        book.itemInfoFor('Polished Stone')!.notes,
        isNot(contains('Drying: clear weather, on land.')),
      );
    }
  });

  test(
    'drying source names use exact inputs and preserve weather restrictions',
    () {
      const inputs = {
        'Dried Pearl Oyster Flesh': 'Giant Pearl Clam',
        'Dried Silver Stripe Round Herring': 'Silver-Stripe Round Herring',
        'Dried Mullet': 'Mullet',
        'Dried Flower Icefish': 'Flower Icefish',
      };
      for (final book in books.values) {
        for (final entry in inputs.entries) {
          final info = book.itemInfoFor(entry.key)!;
          expect(
            info.acquisitionNotes,
            contains('Dry ${entry.value} · Clear weather, on land'),
          );
          expect(info.acquisitionNotes.join(' '), contains('Central Market'));
          expect(info.acquisitionFormulas, isEmpty);
        }
        expect(
          book
              .itemInfoFor('Dried Pearl Oyster Flesh')!
              .acquisitionNotes
              .join(' '),
          isNot(contains('Dry Pearl Oyster Flesh')),
        );
      }
    },
  );

  test(
    'Manos exchange references also explain manufacturing in every mode',
    () {
      const names = [
        "Manos Alchemist's Clothes",
        'Manos Butcher Knife',
        "Manos Cook's Clothes",
        "Manos Fisher's Clothes",
        'Manos Fluid Collector',
        'Manos Hoe',
        'Manos Riding Crop',
        'Manos Tanning Knife',
        "Manos Trainer's Clothes",
      ];
      for (final book in books.values) {
        for (final name in names) {
          final info = book.itemInfoFor(name)!;
          expect(
            info.acquisitionNotes,
            contains('Manufacture · Processing (L)'),
            reason: name,
          );
          expect(
            info.kind,
            name.endsWith('Clothes')
                ? 'Life skill clothing'
                : 'Life skill tool',
          );
          expect(info.acquisitionNotes.join(' '), contains('Golden Seal'));
          expect(info.acquisitionNotes.join(' '), contains('Central Market'));
          expect(info.isTemporarilyArchived, isFalse);
          expect(
            info.acquisitionFormulas,
            isEmpty,
            reason: 'Source guidance does not invent a gear planning recipe',
          );
        }
        final sugar = book.itemInfoFor('Lump of Raw Sugar')!;
        expect(
          sugar.acquisitionNotes,
          contains('Heat 10 Raw Sugar with 1 Mineral Water.'),
        );
      }
    },
  );

  test('additional seal sources distinguish current and legacy currencies', () {
    const expected = {
      'Black Essence: Addis': 80,
      'Black Essence: Carmae': 80,
      'Black Essence: Cobelinus': 80,
      'Black Essence: Hystria': 80,
      'Black Essence: Viper': 80,
      'Black Essence: Black Spirit Crystal': 20,
      'Spellbound Tool Box': 50,
    };
    for (final book in books.values) {
      for (final entry in expected.entries) {
        final info = book.itemInfoFor(entry.key)!;
        expect(
          info.acquisitionNotes,
          contains(
            'Exchange · ${entry.value} Golden Seal - [Imperial Conquest] · Manage Currency',
          ),
          reason: entry.key,
        );
        expect(info.isTemporarilyArchived, isFalse);
        expect(
          info.acquisitionNotes.join(' '),
          isNot(contains('Shiny Golden')),
        );
      }
      final spirit = book.itemInfoFor('Black Essence: Black Spirit Crystal')!;
      expect(
        spirit.acquisitionNotes,
        isNot(contains('Exchange Golden Seals via the Manage Currency UI.')),
      );
      final storm = book.itemInfoFor('Storm Horse Gear Box')!;
      expect(
        storm.acquisitionNotes,
        contains(
          'Exchange · 1,000 Golden Seal - [Work Supervisor] · Manage Currency',
        ),
      );
      expect(
        storm.acquisitionNotes.join(' '),
        contains('The reward inside is random'),
      );
      expect(
        storm.acquisitionNotes.join(' '),
        contains('2 Golden Seal - [Imperial Training]'),
      );
      expect(
        book.itemInfoFor('Black Essence: Viper')!.acquisitionNotes.join(' '),
        contains('12 Golden Seal - [Imperial Training]'),
      );
      expect(
        book
            .itemInfoFor('Imperfect Lightstone of Flora')!
            .acquisitionNotes
            .join(' '),
        contains('10,000 Golden Seal - [Work Supervisor]'),
      );
    }
  });

  test('unified boss sources preserve the two different Aura methods', () {
    for (final book in books.values) {
      final crystal = book.itemInfoFor('Concentrated Boss Crystal')!;
      expect(crystal.isTemporarilyArchived, isFalse);
      expect(crystal.acquisitionNotes, contains('Boss drops'));
      expect(
        crystal.acquisitionNotes,
        contains(
          'Jetina · Weekly Imperfect Beings quest or Latent Boss Aura exchange',
        ),
      );
      expect(
        crystal.acquisitionNotes.join(' '),
        isNot(contains('Defeat Boss through')),
      );
      final contained = book.itemInfoFor('Contained Boss Aura')!;
      expect(contained.isTemporarilyArchived, isFalse);
      expect(
        contained.acquisitionNotes,
        contains(
          'Simple Alchemy · Market-tradable boss gear, unenhanced to TRI (consumes the gear)',
        ),
      );
      expect(
        contained.notes,
        contains('Output: unenhanced 1, PRI 10, DUO 15, TRI 30.'),
      );
      expect(
        contained.acquisitionNotes.join(' '),
        isNot(contains('Concentrated Aura')),
      );
      final blackstar = book.itemInfoFor("Concentrated Boss's Aura")!;
      expect(blackstar.isTemporarilyArchived, isFalse);
      expect(
        blackstar.acquisitionNotes,
        contains('Heat unenhanced boss gear.'),
      );
      expect(
        blackstar.acquisitionNotes.join(' '),
        isNot(contains('Simple Alchemy')),
      );
    }
  });

  test(
    'all ten unified reform stones remain current after retiring old names',
    () {
      for (final slot in ['Weapon', 'Armor']) {
        for (final rank in ['I', 'II', 'III', 'IV', 'V']) {
          final name = 'Resplendent Boss $slot Reform Stone $rank';
          for (final book in books.values) {
            final info = book.itemInfoFor(name)!;
            expect(info.isTemporarilyArchived, isFalse, reason: name);
            expect(info.acquisitionFormulas, isNotEmpty, reason: name);
            expect(
              info.acquisitionFormulas
                  .expand((f) => f.ingredients)
                  .where((i) => isTemporarilyArchivedItem(i.name)),
              isEmpty,
            );
          }
          expect(
            app.modes[CraftMode.processing]!.craftableNames,
            contains(name),
          );
        }
      }
    },
  );

  for (final id in [59858, 59859, 59860, 59861, 17849, 17899]) {
    test(
      'guild and shrine sources $id share facts without changing exchanges',
      () {
        final facts = reviewedReferenceFacts[id]!;
        for (final book in books.values) {
          final info = book.itemInfoFor(facts.name)!;
          expect(info.acquisitionNotes, containsAll(facts.sources));
          expect(info.notes, containsAll(facts.notes));
          expect(
            info.acquisitionNotes.any((s) => s.startsWith('Exchange ·')),
            isTrue,
          );
          expect(info.acquisitionFormulas, isEmpty);
          final twice = withReviewedReferenceFacts(info, itemId: '$id');
          expect(twice.acquisitionNotes, info.acquisitionNotes);
          expect(twice.notes, info.notes);
          expect(twice.effects, info.effects);
        }
      },
    );
  }
  test(
    'Resplendent element rewards retain distinct rank and boss conditions',
    () {
      for (final book in books.values) {
        for (final (element, rank) in [
          ('Earth', 3),
          ('Wind', 10),
          ('Flora', 25),
        ]) {
          expect(
            book
                .itemInfoFor('Resplendent Lightstone of $element')!
                .acquisitionNotes
                .join(' '),
            contains('Hard, top $rank'),
          );
        }
        expect(
          book
              .itemInfoFor('Resplendent Lightstone of Wind')!
              .acquisitionNotes
              .any((s) => s.startsWith('Guild boss')),
          isFalse,
        );
        for (final id in [735351, 735352, 735365, 735374]) {
          expect(
            book.itemInfoFor(reviewedBasicArtifacts[id]!)!.acquisitionNotes,
            contains('Sea monster · Hollow Maretta in Margoria (chance)'),
          );
        }
        expect(
          book
              .itemInfoFor("Sethra's Artifact - Cooking EXP")!
              .acquisitionNotes
              .join(' '),
          isNot(contains('Maretta')),
        );
        final flora = book.itemInfoFor('Resplendent Lightstone of Flora')!;
        expect(
          flora.acquisitionNotes.join(' '),
          contains('10 Energy of Lakiaro'),
        );
        final advice = book.itemInfoFor('Advice of Valks (+100)')!;
        expect(advice.acquisitionNotes.join(' '), contains('Once per family'));
        expect(
          advice.notes,
          contains('Use when your current Enhancement Chance is 0.'),
        );
      }
    },
  );

  for (final id in [4052, 567, 568, 570, 571, 579]) {
    test(
      'processing chance source $id is informational and exact in all modes',
      () {
        final facts = reviewedReferenceFacts[id]!;
        for (final book in books.values) {
          final info = book.itemInfoFor(facts.name)!;
          expect(info.acquisitionNotes, contains(facts.sources.single));
          expect(facts.sources.single, contains('(chance)'));
          final enriched = withReviewedReferenceFacts(info, itemId: '$id');
          expect(enriched.acquisitionNotes, info.acquisitionNotes);
          expect(enriched.acquisitionFormulas, info.acquisitionFormulas);
          expect(enriched.effects, info.effects);
          expect(enriched.uses, info.uses);
        }
        final plain = RecipeBookItemInfo(
          title: facts.name,
          kind: 'Material',
          summary: '',
        );
        expect(
          withReviewedReferenceFacts(plain, itemId: '-1').acquisitionNotes,
          isEmpty,
        );
        final bound = plain.copyWith(title: '${facts.name} (Bound)');
        expect(
          withReviewedReferenceFacts(bound, itemId: '$id').acquisitionNotes,
          isEmpty,
        );
        final archived = plain.copyWith(isTemporarilyArchived: true);
        expect(
          withReviewedReferenceFacts(archived, itemId: '$id').acquisitionNotes,
          isEmpty,
        );
      },
    );
  }
  test(
    'chance source keeps raw-crop grade and does not guess Refined Grain route',
    () {
      expect(reviewedReferenceFacts[578], isNull);
      for (final id in [568, 571]) {
        expect(
          reviewedReferenceFacts[id]!.sources.single,
          contains('high-quality'),
        );
      }
      expect(
        reviewedReferenceFacts[579]!.sources.single,
        contains('Special herbs'),
      );
      for (final book in books.values) {
        final iron = book.itemInfoFor('Iron Ingot')!;
        expect(iron.acquisitionFormulas, hasLength(1));
        expect(
          iron.acquisitionFormulas.single.ingredients.single.name,
          'Melted Iron Shard',
        );
        expect(iron.acquisitionFormulas.single.ingredients.single.quantity, 10);
      }
    },
  );

  for (final entry in reviewedBasicArtifacts.entries) {
    test('${entry.value} shares exact artifact facts across all modes', () {
      for (final book in books.values) {
        final info = book.itemInfoFor(entry.value)!;
        expect(
          info.uses,
          contains(
            'Spare artifact (no Lightstones) · Dalishain → 2 Purified Lightstones',
          ),
        );
        if (entry.key < 735351) {
          expect(
            info.acquisitionNotes,
            contains('Monster drops · Kratuga Ancient Ruins and other zones'),
          );
          expect(
            info.acquisitionNotes,
            isNot(contains('Monster drops · Check Monster Zone Info')),
          );
        } else {
          expect(
            info.acquisitionNotes.any((s) => s.contains('Kratuga')),
            isFalse,
          );
        }
        if (entry.key == 735351 || entry.key == 735352) {
          expect(
            info.notes,
            contains(
              'Bonuses apply only to the Life Skill slot this is equipped in.',
            ),
          );
        }
        expect(info.acquisitionFormulas, isEmpty);
        final twice = withReviewedArtifactFacts(info, itemId: '${entry.key}');
        expect(twice.uses, info.uses);
        expect(twice.acquisitionNotes, info.acquisitionNotes);
        expect(twice.notes, info.notes);
        expect(twice.effects, info.effects);
        expect(withReviewedArtifactFacts(info, itemId: '-1'), same(info));
        final bound = info.copyWith(title: '${entry.value} (Bound)');
        expect(
          withReviewedArtifactFacts(bound, itemId: '${entry.key}'),
          same(bound),
        );
        final archived = info.copyWith(isTemporarilyArchived: true);
        expect(
          withReviewedArtifactFacts(archived, itemId: '${entry.key}'),
          same(archived),
        );
      }
    });
  }
  test(
    'artifact gifts retain family and story conditions, not automatic rewards',
    () {
      for (final book in books.values) {
        for (final (name, quest) in [
          ("Marsh's Artifact - Extra AP Against Monsters", 'I'),
          ("Lesha's Artifact - Monster Damage Reduction", 'IV'),
        ]) {
          final info = book.itemInfoFor(name)!;
          expect(
            info.acquisitionNotes,
            contains(
              'Black Spirit · A Gift for Leaping Forward $quest (once per family)',
            ),
          );
          expect(
            info.notes,
            contains('Gift quest unlocks through main-story progress.'),
          );
        }
      }
    },
  );
  test('artifact recycling never leaks to top-tier or Heralding artifacts', () {
    for (final book in books.values) {
      for (final name in [
        "Kabua's Artifact",
        "Margahan's Artifact",
        "Dehkia's Artifact - All Evasion",
        "Kabua's Heralding Artifact",
      ]) {
        final info = book.itemInfoFor(name)!;
        expect(info.uses.any((s) => s.contains('Spare artifact')), isFalse);
      }
      final lightstone = book.itemInfoFor('Purified Lightstone')!;
      expect(
        lightstone.acquisitionNotes,
        contains('Dalishain · Exchange 3 spare Lightstones → 1'),
      );
      expect(
        lightstone.notes,
        isNot(
          contains("Lightstone recycling needs 'Eureka! A New Discovery'."),
        ),
      );
      expect(lightstone.acquisitionFormulas, isEmpty);
      // NA/EU January 11, 2023 removed Guru 1 from the exchange only.
      // Keep it separate from residence Alchemy's still-required threshold.
      final magicalCrystal = book.itemInfoFor('Magical Lightstone Crystal')!;
      expect(magicalCrystal.acquisitionNotes.join(' '), contains('Dalishain'));
      expect(
        [...magicalCrystal.acquisitionNotes, ...magicalCrystal.notes].join(' '),
        isNot(contains('Guru')),
      );
      for (final element in ['Fire', 'Earth', 'Wind', 'Flora']) {
        final purified = book.itemInfoFor('Purified Lightstone of $element')!;
        expect(
          purified.acquisitionNotes,
          contains(
            'Dalishain · 1 Imperfect Lightstone of $element + 20m Silver → 1',
          ),
        );
        expect(purified.notes.any((s) => s.contains('Guru 1')), isTrue);
        expect(purified.acquisitionFormulas, isNotEmpty);
      }
    }
  });

  test('exact Kamasylvia wording compacts without dropping restrictions', () {
    expect(
      plainAcquisitionLine('Defeat monsters in Kamasylvia.'),
      'Monster drops · Kamasylvia',
    );
    const qualified = 'Defeat monsters in Kamasylvia. Event only.';
    expect(plainAcquisitionLine(qualified), qualified);
    const other = 'Defeat monsters in Valencia.';
    expect(plainAcquisitionLine(other), other);
  });

  for (final entry in reviewedWeaponRecyclingSources.entries) {
    test('${entry.value.$1} keeps verified weapon sources informational', () {
      for (final book in books.values) {
        final info = book.itemInfoFor(entry.value.$1)!;
        expect(info.acquisitionNotes, containsAll(entry.value.$2));
        expect(
          info.acquisitionNotes.where((s) => s.startsWith('Curated to')),
          isEmpty,
        );
        expect(
          info.acquisitionFormulas.any(
            (f) => f.ingredients.any((i) => i.name.contains('Florang')),
          ),
          isFalse,
        );
        if (entry.key != 5960) {
          expect(
            info.notes,
            contains('Planner uses the ingot + Metal Solvent recipe.'),
          );
          expect(info.acquisitionFormulas, hasLength(1));
          expect(
            info.acquisitionFormulas.single.ingredients.any(
              (i) => i.name == 'Metal Solvent',
            ),
            isTrue,
          );
        }
        final twice = withReviewedWeaponRecyclingSources(
          info,
          itemId: '${entry.key}',
        );
        expect(twice.acquisitionNotes, info.acquisitionNotes);
        expect(twice.notes, info.notes);
        expect(twice.acquisitionFormulas, info.acquisitionFormulas);
        expect(twice.craftUses, info.craftUses);
        expect(twice.effects, info.effects);
        expect(
          withReviewedWeaponRecyclingSources(info, itemId: '-1'),
          same(info),
        );
        expect(
          withReviewedWeaponRecyclingSources(info, itemId: null),
          same(info),
        );
        final wrong = info.copyWith(title: '${entry.value.$1} (Bound)');
        expect(
          withReviewedWeaponRecyclingSources(wrong, itemId: '${entry.key}'),
          same(wrong),
        );
        final archived = info.copyWith(isTemporarilyArchived: true);
        expect(
          withReviewedWeaponRecyclingSources(archived, itemId: '${entry.key}'),
          same(archived),
        );
        final restricted = info.copyWith(
          acquisitionNotes: ['Heating · Restricted event version only'],
        );
        expect(
          withReviewedWeaponRecyclingSources(
            restricted,
            itemId: '${entry.key}',
          ).acquisitionNotes,
          contains('Heating · Restricted event version only'),
        );
      }
    });
  }

  for (final entry in reviewedMonsterQuestSources.entries) {
    test('${entry.value.$1} has exact PC monster or main-quest sources', () {
      for (final book in books.values) {
        final info = book.itemInfoFor(entry.value.$1)!;
        expect(info.acquisitionNotes, containsAll(entry.value.$2));
        final twice = withReviewedMonsterQuestSources(
          info,
          itemId: '${entry.key}',
        );
        expect(twice.acquisitionNotes, info.acquisitionNotes);
        expect(twice.acquisitionFormulas, info.acquisitionFormulas);
        expect(twice.craftUses, info.craftUses);
        expect(twice.effects, info.effects);
        expect(withReviewedMonsterQuestSources(info, itemId: '-1'), same(info));
        final wrong = info.copyWith(title: '${entry.value.$1} (Bound)');
        expect(
          withReviewedMonsterQuestSources(wrong, itemId: '${entry.key}'),
          same(wrong),
        );
        final archived = info.copyWith(isTemporarilyArchived: true);
        expect(
          withReviewedMonsterQuestSources(archived, itemId: '${entry.key}'),
          same(archived),
        );
        if (const {44304, 44305, 44306, 44311}.contains(entry.key)) {
          expect(info.acquisitionNotes, contains('Monster drops · Kamasylvia'));
          expect(
            info.acquisitionNotes,
            isNot(contains('Defeat monsters in Kamasylvia.')),
          );
        }
      }
    });
  }

  test('removed Life EXP Dawn crystals never become active recycling advice', () {
    for (final book in books.values) {
      final info = book.itemInfoFor('Essence of Dawn')!;
      expect(
        info.howToObtain.where((line) => line.contains('Life EXP')),
        isEmpty,
      );
      expect(
        info.acquisitionNotes,
        contains(
          'Heating · 1 AP Dawn crystal gives 1 (WON), 10 (BON), or 30 (JIN/HAN)',
        ),
      );
      for (final name in [
        'JIN Dawn Crystal - Life EXP',
        'BON Dawn Crystal - Life EXP',
        'WON Dawn Crystal - Life EXP',
      ]) {
        expect(book.itemInfoFor(name)!.isTemporarilyArchived, isTrue);
      }
    }
  });

  test(
    'Taritas and Padix hints do not leak to same-name bound or costume IDs',
    () {
      for (final entry in const {
        714307: 'Taritas Armor',
        714326: 'Taritas Helmet',
        714327: 'Taritas Gloves',
        714328: 'Taritas Shoes',
      }.entries) {
        final info = books[CraftMode.alchemy]!
            .itemInfoFor(entry.value)!
            .copyWith(acquisitionNotes: []);
        expect(
          withReviewedContainerQuestSources(info, itemId: '${entry.key}'),
          same(info),
        );
      }
      final info = books[CraftMode.alchemy]!
          .itemInfoFor('Ethereal Earring')!
          .copyWith(acquisitionNotes: []);
      expect(
        withReviewedMonsterQuestSources(info, itemId: '741630'),
        same(info),
      );
    },
  );

  for (final entry in reviewedContainerQuestSources.entries) {
    test(
      '${entry.value.$1} has exact qualified container or quest sources',
      () {
        for (final book in books.values) {
          final info = book.itemInfoFor(entry.value.$1)!;
          expect(info.acquisitionNotes, containsAll(entry.value.$2));
          for (final source in entry.value.$2) {
            expect(
              info.acquisitionNotes.where((s) => s == source),
              hasLength(1),
            );
          }
          final twice = withReviewedContainerQuestSources(
            info,
            itemId: '${entry.key}',
          );
          expect(twice.acquisitionNotes, info.acquisitionNotes);
          expect(twice.acquisitionFormulas, info.acquisitionFormulas);
          expect(twice.craftUses, info.craftUses);
          expect(twice.effects, info.effects);
          expect(
            withReviewedContainerQuestSources(info, itemId: '-1'),
            same(info),
          );
          final wrong = info.copyWith(title: '${entry.value.$1} (Bound)');
          expect(
            withReviewedContainerQuestSources(wrong, itemId: '${entry.key}'),
            same(wrong),
          );
          final archived = info.copyWith(isTemporarilyArchived: true);
          expect(
            withReviewedContainerQuestSources(archived, itemId: '${entry.key}'),
            same(archived),
          );
        }
      },
    );
  }

  for (final entry in reviewedLustrousGemRewards.entries) {
    test('${entry.value.$1} has the current open-gem source in every mode', () {
      final (name, quantity, guaranteed) = entry.value;
      final suffix = guaranteed ? '' : ' (chance)';
      final expected =
          'Rough Lustrous Gem · Open for $quantity$suffix; found in Starlight Veins';
      for (final book in books.values) {
        final info = book.itemInfoFor(name)!;
        expect(
          info.acquisitionNotes.where((s) => s.contains('Rough Lustrous Gem')),
          [expected],
        );
        expect(
          withReviewedLustrousGemSources(
            info,
            itemId: '${entry.key}',
          ).acquisitionNotes,
          info.acquisitionNotes,
        );
        expect(
          identical(
            withReviewedLustrousGemSources(info, itemId: '65972'),
            info,
          ),
          isTrue,
        );
        expect(
          info.acquisitionFormulas.any(
            (f) => f.ingredients.any((i) => i.name == 'Rough Lustrous Gem'),
          ),
          isFalse,
        );
        expect(
          info.acquisitionNotes.any(
            (s) => s.contains('200 amity') || s.contains('NPC appraisal'),
          ),
          isFalse,
        );
      }
      final mismatched = RecipeBookItemInfo(
        title: '$name (Bound)',
        kind: 'Synthetic identity guard',
        summary: '',
      );
      expect(
        identical(
          withReviewedLustrousGemSources(mismatched, itemId: '${entry.key}'),
          mismatched,
        ),
        isTrue,
      );
    });
  }
  test('powder sources use short distinct routes and a real market line', () {
    for (final book in books.values) {
      final info = book.itemInfoFor('Black Stone Powder')!;
      expect(
        info.acquisitionNotes,
        containsAll([
          'Grinding · Black Stone or eligible Magic Crystals',
          'Workers · Refinery',
          'Central Market',
        ]),
      );
      expect(info.acquisitionNotes.any((s) => s.startsWith('Grind ')), isFalse);
      expect(
        info.acquisitionNotes.where((s) => s.contains('Central Market')),
        hasLength(1),
      );
      expect(info.acquisitionFormulas, hasLength(1));
      final formula = info.acquisitionFormulas.single;
      expect(formula.method, 'Grinding');
      expect(formula.ingredients.single.name, 'Black Stone');
      expect(formula.ingredients.single.quantity, 1);
    }
  });

  for (final type in [
    'Harphia',
    'Cobelinus',
    'Viper',
    'Hystria',
    'Carmae',
    'Addis',
  ]) {
    test('random crystal $type is never guaranteed WON production', () {
      final name = 'WON Magic Crystal - $type';
      final mode = app.modes[CraftMode.processing]!;
      final recipe = mode.recipes[name]!;
      expect(recipe.role, RecipeRole.manualConversion);
      expect(recipe.isCraftable, isFalse);
      expect(recipe.outputMinimum, isNull);
      expect(recipe.outputMaximum, isNull);
      expect(recipe.ingredients.map((i) => (i.name, i.quantity)), [
        ('Black Magic Crystal - $type', 1.0),
        ('Magical Shard', 10.0),
        ('Forest Fury', 1.0),
      ]);
      expect(mode.craftableNames, isNot(contains(name)));
      expect(opportunityRecipeRoutes([recipe]), isEmpty);
      final quote = const RecipeProfitabilityCalculator().calculate(
        recipe: recipe,
        recipes: mode.recipes,
        state: ModeState(
          target: name,
          bonusTarget: name,
          appearance: AppearanceSettings.defaultsFor(CraftMode.processing),
          market: MarketState(
            prices: {for (final n in mode.recipes.keys) n: 10},
          ),
        ),
        rules: plan.PlannerRules(),
        marketTax: MarketTax(),
      );
      expect(quote.isAvailable, isFalse);
      expect(quote.profitPerCraft, isNull);
      final result = const PlannerEngine().buildPlan(
        mode: CraftMode.processing,
        recipes: mode.recipes,
        state: plan.PlannerState(target: name, want: 10),
      );
      expect(result.steps, isEmpty);
    });
    for (final grade in ['JIN', 'BON', 'WON']) {
      test('random crystal $grade $type has qualified shared instructions', () {
        final name = '$grade Magic Crystal - $type';
        for (final book in books.values) {
          final info = book.itemInfoFor(name)!;
          expect(
            info.howToObtain,
            contains(
              'Simple Alchemy · Black Magic Crystal - $type ×1 + Forest Fury ×1 + Magical Shard ×10',
            ),
          );
          expect(
            info.howToObtain,
            contains('Result · 1 matching JIN, BON or WON crystal (random)'),
          );
          expect(
            info.howToObtain.any((s) => s.contains('Crafting Notes')),
            isFalse,
          );
          expect(
            info.howToObtain.any((s) => s.contains('Central Market')),
            isTrue,
          );
          expect(info.acquisitionFormulas, isEmpty);
          expect(info.effects, isNotEmpty);
          final id =
              15801 +
              reviewedRandomCrystalTypes.indexOf(type) * 3 +
              reviewedRandomCrystalGrades.indexOf(grade);
          final twice = withReviewedRandomCrystalSources(info, itemId: '$id');
          expect(twice.howToObtain, info.howToObtain);
          expect(twice.effects, info.effects);
          expect(twice.craftUses, info.craftUses);
          expect(
            withReviewedRandomCrystalSources(info, itemId: '768883'),
            same(info),
          );
          final wrong = info.copyWith(title: '$name (Bound)');
          expect(
            withReviewedRandomCrystalSources(wrong, itemId: '$id'),
            same(wrong),
          );
          final archived = info.copyWith(isTemporarilyArchived: true);
          expect(
            withReviewedRandomCrystalSources(archived, itemId: '$id'),
            same(archived),
          );
        }
      });
    }
  }

  test(
    'HAN recipes buy their selected WON crystal without random expansion',
    () {
      final mode = app.modes[CraftMode.processing]!;
      for (final type in ['Gervish', 'Hoom', 'Macalod']) {
        final name = 'HAN Combined Magic Crystal - $type';
        final recipe = mode.recipes[name]!;
        final crystal = recipe.ingredients.singleWhere(
          (i) => i.options.contains('WON Magic Crystal - Harphia'),
        );
        final result = const PlannerEngine().buildPlan(
          mode: CraftMode.processing,
          recipes: mode.recipes,
          state: plan.PlannerState(
            target: name,
            want: 2,
            substituteChoices: {
              'recipe:$name:${crystal.substituteGroup}':
                  'WON Magic Crystal - Harphia',
            },
          ),
        );
        final step = result.steps.singleWhere((s) => s.name == name);
        expect(step.produced, 2);
        expect(
          step.ingredients.any((i) => i.name == 'WON Magic Crystal - Harphia'),
          isTrue,
        );
        expect(
          result.steps.any((s) => s.name.startsWith('WON Magic Crystal - ')),
          isFalse,
        );
        expect(
          result.missing.any((m) => m.name == 'WON Magic Crystal - Harphia'),
          isTrue,
        );
      }
    },
  );

  test('random crystal ingredients retain a qualified usage hint', () {
    for (final entry in reviewedRandomCrystalInputs.entries) {
      for (final book in books.values) {
        final info = book.itemInfoFor(entry.value)!;
        expect(info.uses, contains(reviewedRandomCrystalUsage));
        expect(
          info.craftUses.any(
            (use) => use.output.startsWith('WON Magic Crystal - '),
          ),
          isFalse,
        );
        final twice = withReviewedRandomCrystalSources(
          info,
          itemId: '${entry.key}',
        );
        expect(twice.uses, info.uses);
        expect(twice.howToObtain, info.howToObtain);
        final wrong = info.copyWith(title: '${entry.value} (Bound)');
        expect(
          withReviewedRandomCrystalSources(wrong, itemId: '${entry.key}'),
          same(wrong),
        );
      }
    }
  });

  test('ordinary spirit stones share the verified monster source', () {
    for (final book in books.values) {
      for (final id in [45298, 45300, 45302]) {
        final facts = reviewedReferenceFacts[id]!;
        final info = book.itemInfoFor(facts.name)!;
        expect(info.acquisitionNotes, containsAll(facts.sources));
        expect(info.acquisitionNotes, contains('Central Market'));
        expect(info.acquisitionFormulas, isEmpty);
        expect(
          info.acquisitionNotes.any((line) => line.contains('100%')),
          isFalse,
        );
        expect(facts.effects, isEmpty);
        expect(facts.notes, isEmpty);
      }
    }
  });

  test('carrot sources keep exact grades and do not invent recipes', () {
    for (final book in books.values) {
      for (final id in [54004, 54005]) {
        final facts = reviewedReferenceFacts[id]!;
        final info = book.itemInfoFor(facts.name)!;
        expect(info.acquisitionNotes, containsAll(facts.sources));
        expect(info.acquisitionNotes, contains('Central Market'));
        expect(info.acquisitionFormulas, isEmpty);
        expect(info.effects, isEmpty);
        final wrong = info.copyWith(title: '${info.title} Seed');
        expect(withReviewedReferenceFacts(wrong, itemId: '$id'), same(wrong));
        expect(
          withReviewedReferenceFacts(info, itemId: '37256'),
          same(info),
          reason: 'The same-name knowledge item is not the crop.',
        );
      }
      final high = book.itemInfoFor('High-quality Carrot')!;
      expect(high.acquisitionNotes.any((s) => s.contains('Magical')), isFalse);
      final special = book.itemInfoFor('Special Carrot')!;
      expect(
        special.acquisitionNotes.any((s) => s.contains('Mysterious')),
        isTrue,
      );
    }
  });

  test('Wapra exchange sources agree in every item-reference mode', () {
    for (final book in books.values) {
      for (final name in [
        'Stonetail Fodder',
        'Breezy Conch Seaweed',
        'Deep Blue Hoof Root',
      ]) {
        final info = book.itemInfoFor(name)!;
        expect(
          info.acquisitionNotes,
          contains(
            'Exchange · 3 Royal Fern Root → 1 $name · Wapra · Stonetail Horse Ranch',
          ),
        );
        expect(
          info.acquisitionFormulas,
          isEmpty,
          reason: 'Exchange choices must not become free crafting recipes.',
        );
      }
      final hoof = book.itemInfoFor('Deep Blue Hoof Root')!;
      expect(hoof.acquisitionNotes, contains('Central Market'));
      expect(hoof.effects, isEmpty);
      final art = book.iconDataUriFor('Deep Blue Hoof Root');
      expect(art, isNotNull);
      expect(
        Uri.parse(art!).data!.contentAsBytes(),
        File('assets/opportunities/items/50810.png').readAsBytesSync(),
      );
      expect(repository.itemIconGrade('Deep Blue Hoof Root'), 1);
      final fern = book.itemInfoFor('Royal Fern Root')!;
      expect(fern.kind, 'Exchange item');
      expect(fern.notes, contains('Each row is a separate choice.'));
      expect(fern.uses, contains('Grind into Mythical Powder.'));
    }
  });

  test(
    'reviewed gathering sources stay qualified and preserve other facts',
    () {
      for (final book in books.values) {
        for (final id in [5960, 721003, 5000, 4987, 766107]) {
          final facts = reviewedReferenceFacts[id]!;
          final info = book.itemInfoFor(facts.name)!;
          expect(info.acquisitionNotes, containsAll(facts.sources));
          expect(info.notes, containsAll(facts.notes));
          expect(
            info.acquisitionNotes,
            isNot(
              contains('Life Skill activities according to a set probability.'),
            ),
          );
          final again = withReviewedReferenceFacts(info, itemId: '$id');
          expect(again.acquisitionNotes, info.acquisitionNotes);
          expect(again.effects, info.effects);
          expect(again.acquisitionFormulas, info.acquisitionFormulas);
          final wrong = info.copyWith(
            title: '${info.title} (Bound)',
            acquisitionNotes: ['Existing source'],
          );
          expect(withReviewedReferenceFacts(wrong, itemId: '$id'), same(wrong));
          final archived = info.copyWith(isTemporarilyArchived: true);
          expect(
            withReviewedReferenceFacts(archived, itemId: '$id'),
            same(archived),
          );
        }
      }
    },
  );

  test('Processing input restrictions are shared by all reference modes', () {
    for (final book in books.values) {
      final elixir = book.itemInfoFor('Elixir of Regeneration')!;
      for (final ingredient in elixir.acquisitionFormulas.single.ingredients) {
        expect(ingredient.options, isEmpty, reason: ingredient.name);
        expect(ingredient.substituteRatios, isEmpty, reason: ingredient.name);
      }
      for (final (name, prefix) in [
        ('Concentrated Herbal Juice', 'High-quality '),
        ('Highly Concentrated Herbal Juice', 'Special '),
      ]) {
        final info = book.itemInfoFor(name)!;
        final formula = info.acquisitionFormulas.first;
        final herb = formula.ingredients.first;
        expect(herb.options, hasLength(6));
        expect(herb.options, everyElement(startsWith(prefix)));
      }
    }
  });

  test('all four lightstone recipes share the exact 1:1 catalyst choice', () {
    for (final book in books.values) {
      for (final type in ['Fire', 'Earth', 'Wind', 'Flora']) {
        final info = book.itemInfoFor('Purified Lightstone of $type')!;
        final formula = info.acquisitionFormulas.single;
        expect(formula.ingredients, hasLength(5));
        final catalyst = formula.ingredients.singleWhere(
          (i) => i.name == 'Black Gem Fragment',
        );
        expect(catalyst.quantity, 10);
        expect(catalyst.options, [
          'Black Gem Fragment',
          'Magical Lightstone Crystal',
        ]);
        expect(catalyst.substituteRatios, {
          'Black Gem Fragment': 1.0,
          'Magical Lightstone Crystal': 1.0,
        });
        expect(catalyst.substituteGroup, 'Lightstone catalyst');
      }
      final crystal = book.itemInfoFor('Magical Lightstone Crystal')!;
      expect(
        crystal.craftUses.map((u) => u.output),
        containsAll([
          for (final type in ['Fire', 'Earth', 'Wind', 'Flora'])
            'Purified Lightstone of $type',
        ]),
      );
    }
  });

  for (final type in ['Fire', 'Earth', 'Wind', 'Flora']) {
    for (final choice in ['Black Gem Fragment', 'Magical Lightstone Crystal']) {
      test('Purified Lightstone of $type planner uses $choice exactly', () {
        final name = 'Purified Lightstone of $type';
        final result = const PlannerEngine().buildPlan(
          mode: CraftMode.alchemy,
          recipes: app.modes[CraftMode.alchemy]!.recipes,
          state: plan.PlannerState(
            target: name,
            want: 10,
            substituteChoices: {'recipe:$name:Lightstone catalyst': choice},
          ),
        );
        final step = result.steps.singleWhere((s) => s.name == name);
        final catalyst = step.ingredients.singleWhere((i) => i.name == choice);
        expect(step.count, 10);
        expect(step.produced, 10);
        expect(catalyst.need, step.count * 10);
        expect(step.ingredients, hasLength(5));
        expect(
          step.ingredients.where(
            (i) =>
                i.name ==
                (choice == 'Black Gem Fragment'
                    ? 'Magical Lightstone Crystal'
                    : 'Black Gem Fragment'),
          ),
          isEmpty,
        );
      });
    }
  }

  test(
    'reform recovery is exact shared information, never a reverse planning route',
    () {
      expect(reviewedReformMaterialSources, hasLength(15));
      expect(reviewedRecyclableReformStones, hasLength(10));
      for (final book in books.values) {
        for (final entry in reviewedReformMaterialSources.entries) {
          final info = book.itemInfoFor(entry.value.name)!;
          expect(
            info.acquisitionNotes.where((line) => line == entry.value.text),
            hasLength(1),
          );
          expect(
            info.acquisitionFormulas
                .expand((f) => f.ingredients)
                .any(
                  (i) => reviewedRecyclableReformStones.values.contains(i.name),
                ),
            isFalse,
          );
          final repeated = withReviewedReformRecycling(
            info,
            itemId: '${entry.key}',
          );
          expect(repeated.acquisitionNotes, info.acquisitionNotes);
          expect(repeated.acquisitionFormulas, info.acquisitionFormulas);
          expect(repeated.effects, info.effects);
          expect(repeated.craftUses, info.craftUses);
        }
        for (final entry in reviewedRecyclableReformStones.entries) {
          final info = book.itemInfoFor(entry.value)!;
          expect(
            info.notes.where((n) => n == reviewedReformRecyclingNote),
            hasLength(1),
          );
          expect(info.acquisitionFormulas, hasLength(1));
          expect(info.acquisitionFormulas.single.method, 'Heating');
          expect(info.acquisitionFormulas.single.ingredients, hasLength(5));
        }
      }
    },
  );

  test(
    'reform recovery never leaks to wrong identities, aliases or archived cards',
    () {
      for (final entry in reviewedReformMaterialSources.entries) {
        final info = books[CraftMode.processing]!.itemInfoFor(
          entry.value.name,
        )!;
        final stripped = info.copyWith(acquisitionNotes: ['Existing source']);
        for (final id in [null, '0', 'not-an-id']) {
          expect(
            withReviewedReformRecycling(stripped, itemId: id),
            same(stripped),
          );
        }
        final wrongTitle = stripped.copyWith(title: '${info.title} (Bound)');
        expect(
          withReviewedReformRecycling(wrongTitle, itemId: '${entry.key}'),
          same(wrongTitle),
        );
        final archived = stripped.copyWith(isTemporarilyArchived: true);
        expect(
          withReviewedReformRecycling(archived, itemId: '${entry.key}'),
          same(archived),
        );
      }
    },
  );

  test(
    'restored draughts share complete single/bulk routes and qualified skill requirement',
    () {
      for (final name in ["Beast's Draught", "Giant's Draught"]) {
        for (final book in books.values) {
          final info = book.itemInfoFor(name)!;
          expect(info.acquisitionFormulas, hasLength(4));
          expect(
            info.acquisitionFormulas.map((f) => f.batchMultiplier).toSet(),
            {1, 10},
          );
          expect(
            info.notes,
            contains(
              "Batches using Ibellab's Essence require Alchemy Skilled 1+.",
            ),
          );
          for (final f in info.acquisitionFormulas) {
            expect(
              f.ingredients.where((i) => i.options.length == 2),
              hasLength(
                f.ingredients.any((i) => i.name.startsWith('[Mix]')) ? 1 : 3,
              ),
            );
          }
        }
      }
      for (final book in books.values) {
        expect(
          book.itemInfoFor('Armor Draught')!.notes,
          contains(
            "Batches using Ibellab's Essence require Alchemy Skilled 1+.",
          ),
        );
        expect(
          book.itemInfoFor('Blue Tidal Draught')!.notes,
          isNot(
            contains(
              "Batches using Ibellab's Essence require Alchemy Skilled 1+.",
            ),
          ),
        );
      }
    },
  );

  test(
    'life-skill draughts are not mislabeled combat and Stonetail is food',
    () {
      for (final book in books.values) {
        for (final name in [
          'Tidal Draught',
          'Blue Tidal Draught',
          'Celerity Draught',
          'Verdure Draught',
        ]) {
          expect(book.itemInfoFor(name)!.summary, 'A temporary draught buff.');
        }
        expect(book.itemInfoFor("Stonetail Wind's Meal")!.kind, 'Food');
      }
    },
  );

  test(
    'reviewed draught alternatives reach every shared item-reference mode',
    () {
      final review =
          jsonDecode(
                File(
                  'docs/reviewed-draught-alternatives.json',
                ).readAsStringSync(),
              )
              as Map<String, dynamic>;
      for (final row
          in (review['changes'] as List).cast<Map<String, dynamic>>().where(
            (r) => r['variant'] == 'base',
          )) {
        for (final book in books.values) {
          final formulas = book.itemInfoFor(row['name'])!.acquisitionFormulas;
          final matches = formulas.where(
            (f) => f.ingredients.any(
              (i) => i.name == row['input'] && i.quantity == row['qty'],
            ),
          );
          expect(matches, isNotEmpty, reason: '${row['name']}/${row['input']}');
          for (final formula in matches) {
            final ingredient = formula.ingredients.singleWhere(
              (i) => i.name == row['input'],
            );
            expect(ingredient.options, contains(row['alternative']));
            expect(
              ingredient.substituteRatios[row['alternative']],
              row['ratio'],
            );
          }
        }
      }
    },
  );

  test(
    'sea-origin recycling and reward boxes keep their separate quantities and limits',
    () {
      for (final book in books.values) {
        for (final name in [
          'Origin of Margoria',
          'Origin of Zulatia',
          'Origin of Rusalka',
        ]) {
          final info = book.itemInfoFor(name)!;
          expect(
            info.acquisitionNotes.where(
              (line) => line.contains('Blue Sea Crystal Box'),
            ),
            [
              'Blue Sea Crystal Box · Crow Coin Shop; 5,000 Crow Coins, 3 boxes/week (chance of 1–2)',
            ],
          );
          expect(info.acquisitionFormulas, isEmpty);
        }
        final margoria = book.itemInfoFor('Origin of Margoria')!;
        expect(
          margoria.acquisitionNotes.where(
            (line) => line.contains('Simple Alchemy'),
          ),
          [
            'Simple Alchemy · 1 unwanted Margoria Sea Crystal → 1–2 Origins (consumes the crystal)',
          ],
        );
        expect(margoria.acquisitionNotes, contains('Chance of 1–3.'));
        final twice = withReviewedReferenceFacts(margoria, itemId: '8108');
        expect(twice.acquisitionNotes, margoria.acquisitionNotes);
      }
    },
  );
  for (final entry in const {
    'Origin of Eltro': (8105, 'Eltro', '1–2 Origins'),
    'Origin of Serni': (8106, 'Serni', '1–2 Origins'),
    'Origin of Zulatia': (8107, 'Zulatia', '1–2 Origins'),
    'Origin of Margoria': (8108, 'Margoria', '1–2 Origins'),
    'Origin of Rusalka': (821169, 'Rusalka', '1 Origin'),
  }.entries) {
    test(
      '${entry.key} has exact recycling guidance without automatic salvage',
      () {
        final (id, family, quantity) = entry.value;
        for (final book in books.values) {
          final info = book.itemInfoFor(entry.key)!;
          expect(
            info.acquisitionNotes.where((s) => s.contains('Simple Alchemy')),
            [
              'Simple Alchemy · 1 unwanted $family Sea Crystal → $quantity (consumes the crystal)',
            ],
          );
          expect(info.acquisitionFormulas, isEmpty);
          expect(
            info.acquisitionNotes.any(
              (s) => s.toLowerCase().contains('unopened'),
            ),
            isFalse,
          );
          expect(
            withReviewedReferenceFacts(info, itemId: '$id').acquisitionNotes,
            info.acquisitionNotes,
          );
          expect(
            identical(
              withReviewedReferenceFacts(info, itemId: '999999999'),
              info,
            ),
            isTrue,
          );
        }
        for (final mode in CraftMode.values) {
          final recipe = catalog.forMode(mode).items[entry.key];
          if (recipe != null) expect(recipe.isCraftable, isFalse);
        }
      },
    );
  }
  test(
    'reviewed conversion sources preserve enhancement and chance limits',
    () {
      for (final book in books.values) {
        final melody = book.itemInfoFor('Melody of the Stars')!;
        expect(
          melody.acquisitionNotes.join(' '),
          contains('PRI gives 1, DUO 5, TRI 25'),
        );
        expect(
          melody.acquisitionNotes.join(' '),
          contains('Eligible blue-grade'),
        );
        expect(
          melody.acquisitionNotes.join(' '),
          contains('accessory is consumed'),
        );
        expect(
          melody.acquisitionFormulas,
          isEmpty,
          reason: 'Do not offer a recipe consuming unenhanced accessories.',
        );
        expect(melody.uses.join(' '), contains('Old Moon Censer'));
        for (final name in ['Origin of Margoria', 'Origin of Rusalka']) {
          final info = book.itemInfoFor(name)!;
          expect(
            info.acquisitionNotes.join(' '),
            contains('Deep Sea Crystal Box'),
          );
          expect(info.acquisitionNotes.join(' '), contains('Chance of 1–3'));
          expect(
            info.acquisitionNotes.join(' '),
            contains('30 Wavelit Crystals'),
          );
          expect(info.acquisitionNotes.join(' '), contains('1 box/week'));
          expect(info.acquisitionNotes.join(' '), contains('Simple Alchemy'));
          expect(
            info.acquisitionFormulas,
            isEmpty,
            reason: 'Do not automatically destroy installed ship equipment.',
          );
        }
      }
      for (final name in [
        'Melody of the Stars',
        'Origin of Margoria',
        'Origin of Rusalka',
      ]) {
        expect(catalog.processing.items[name]!.isCraftable, isFalse);
      }
      for (final slot in ['Belt', 'Earring', 'Necklace', 'Ring']) {
        final name = 'Apeiron $slot';
        expect(catalog.processing.items[name]!.ingredients, isEmpty);
        for (final book in books.values) {
          expect(
            book.itemInfoFor(name)!.acquisitionFormulas,
            isEmpty,
            reason: 'September 17, 2026 removed the Twilight-to-Apeiron route.',
          );
        }
      }
    },
  );

  test(
    'supported additions reach every actual controller and remain idempotent',
    () {
      expect(reviewedReferenceFacts, hasLength(194));
      expect(reviewedReferenceFacts[5443]!.name, 'Insectivore Plant Root');
      for (final entry in reviewedReferenceFacts.entries) {
        for (final book in books.values) {
          final actual = book.itemInfoFor(entry.value.name)!;
          if (isRemovedPcItem(entry.value.name, itemId: '${entry.key}')) {
            expect(actual.effects, isEmpty);
            expect(actual.notes, isEmpty);
            expect(actual.acquisitionNotes, isEmpty);
            expect(
              identical(
                withReviewedReferenceFacts(actual, itemId: '${entry.key}'),
                actual,
              ),
              isTrue,
            );
            continue;
          }
          expect(
            actual.acquisitionNotes,
            containsAll(entry.value.sources),
            reason: entry.value.name,
          );
          expect(
            actual.effects,
            containsAll(entry.value.effects),
            reason: entry.value.name,
          );
          expect(
            actual.notes,
            containsAll(entry.value.notes),
            reason: entry.value.name,
          );
          final repeated = withReviewedReferenceFacts(
            actual,
            itemId: '${entry.key}',
          );
          expect(repeated.effects, actual.effects);
          expect(repeated.notes, actual.notes);
          expect(repeated.acquisitionNotes, actual.acquisitionNotes);
        }
      }
    },
  );
  test('spending a gathered material is a use, not an obtaining route', () {
    for (final book in books.values) {
      final fairy = book.itemInfoFor("Fairy's Breath")!;
      expect(fairy.acquisitionNotes, ['Gathering']);
      expect(
        fairy.uses,
        contains(
          'Exchange 10 with Dalishain for one reward:\n30 Wild Grass\n20 Log\n12 Rough Stone\n1 Fruit of Nature\n1 Trace of Nature\n900 Contribution EXP and 30 Gathering EXP',
        ),
      );
      expect(
        fairy.notes,
        contains("The current Fairy's Breath does not exchange for Sharps."),
      );
      final beehive = book.itemInfoFor('Wild Beehive')!;
      expect(beehive.acquisitionNotes.any((s) => s.contains('Grind')), isFalse);
      expect(beehive.craftUses.map((u) => u.output), contains('Cooking Honey'));
    }
  });
  test(
    'client-only raw consumption is absent in all real controller modes',
    () {
      for (final facts in reviewedRawConsumption.values) {
        for (final book in books.values) {
          final info = book.itemInfoFor(facts.name)!;
          expect(info.effectsTitle, 'Effects', reason: facts.name);
          expect(info.effects, isEmpty, reason: facts.name);
          expect(
            info.notes,
            isNot(contains('Duration: 30 sec.')),
            reason: facts.name,
          );
          expect(
            info.notes,
            isNot(contains('Cooldown: 10 min.')),
            reason: facts.name,
          );
        }
      }
      for (final book in books.values) {
        for (final name in [
          'High-Quality Amanita Mushroom',
          'Special Amanita Mushroom',
        ]) {
          final info = book.itemInfoFor(name)!;
          expect(
            info.effects.where((e) => e.contains('Fear Resistance')),
            isEmpty,
          );
          expect(info.effects.where((e) => e.contains('Knockdown')), isEmpty);
          expect(info.notes, isNot(contains('Eating it raw can poison you.')));
          expect(info.notes.where((n) => n.contains('Eating it raw')), isEmpty);
        }
      }
    },
  );
  test('Insectivore sources preserve the actual tool and mastery condition', () {
    for (final book in books.values) {
      final powder = book.itemInfoFor('Insectivore Plant Powder')!;
      final sap = book.itemInfoFor('Insectivore Plant Sap')!;
      expect(
        book.itemInfoFor('Insectivore Plant Root')!.acquisitionNotes,
        containsAll([
          'Monster drops · Poisonous Plants in Naga Marsh',
          'Central Market',
        ]),
      );
      for (final info in [powder, sap]) {
        expect(info.acquisitionFormulas, isNotEmpty);
        expect(
          info.acquisitionFormulas.every((f) => f.outputEstimated),
          isTrue,
        );
      }
      final leaves = powder.acquisitionFormulas.where(
        (f) => f.ingredients.any((i) => i.name == 'Insectivore Plant Leaf'),
      );
      expect(leaves, isNotEmpty);
      expect(
        leaves.map(recipeBookPreviewFormulaIdentity).toSet(),
        hasLength(1),
      );
      for (final formula in leaves) {
        expect(formula.ingredients, hasLength(1));
        expect(formula.ingredients.single.quantity, 5);
        expect(formula.variantId, 'leaves-and-fragments');
      }
      // Identical Alchemy/Processing catalog families share one preview, with
      // two real input choices inside it (not two duplicate method panels).
      final families = recipeBookPreviewRoutes(powder.acquisitionFormulas);
      expect(families, hasLength(1));
      expect(families.single.formulas, hasLength(2));
      expect(
        families.single.equivalentModes,
        containsAll([CraftMode.alchemy, CraftMode.processing]),
      );
      final roots = sap.acquisitionFormulas.where(
        (f) => f.variantId == 'roots',
      );
      expect(roots, hasLength(1));
      expect(roots.single.ingredients.single.name, 'Insectivore Plant Root');
      expect(roots.single.ingredients.single.quantity, 5);
      expect(
        book
            .itemInfoFor('Insectivore Plant Root')!
            .craftUses
            .map((u) => u.output),
        contains('Insectivore Plant Sap'),
      );
      expect(
        book
            .itemInfoFor('Tree Spirit Stone Fragment')!
            .craftUses
            .map((use) => use.output),
        isNot(contains('Insectivore Plant Powder')),
      );
      expect(
        powder.acquisitionNotes,
        contains(
          'Grinding · 5 Insectivore Plant Flower or 5 Insectivore Plant Leaf',
        ),
      );
      expect(
        sap.acquisitionNotes,
        contains(
          'Grinding · 5 Insectivore Plant Stalk or 5 Insectivore Plant Root',
        ),
      );
      for (final info in [powder, sap]) {
        final gathering = info.acquisitionNotes.where(
          (line) => line.startsWith('Gather ·'),
        );
        expect(gathering, hasLength(1));
        expect(gathering.single, contains('high Gathering Mastery required'));
        expect(
          gathering.single,
          contains(
            identical(info, powder) ? 'hands or hoe' : 'fluid collector',
          ),
        );
      }
      expect(
        powder.acquisitionNotes,
        isNot(contains('Gather Insectivore Plant with Bare Hands or a Hoe.')),
      );
      expect(
        sap.acquisitionNotes,
        isNot(contains('Fluid Collector · Insectivore Plant')),
      );
      for (final name in ['Sharp Black Crystal Shard', 'Mass of Pure Magic']) {
        final info = book.itemInfoFor(name)!;
        expect(
          info.acquisitionNotes.join(' '),
          contains("Pilgrim's Cracked Stone (Guild Drill; chance)"),
        );
        expect(
          info.acquisitionFormulas,
          isEmpty,
          reason:
              'Random Guild Drill results must not become a guaranteed recipe.',
        );
      }
    }
  });

  test(
    'new reference facts never leak to a different identity or archived item',
    () {
      for (final entry in reviewedReferenceFacts.entries) {
        final original = books[CraftMode.alchemy]!.itemInfoFor(
          entry.value.name,
        )!;
        for (final other in [
          original.copyWith(title: '[Event] ${original.title}'),
          original.copyWith(isTemporarilyArchived: true),
        ]) {
          expect(
            identical(
              withReviewedReferenceFacts(other, itemId: '${entry.key}'),
              other,
            ),
            isTrue,
          );
        }
        expect(
          identical(
            withReviewedReferenceFacts(original, itemId: '999999999'),
            original,
          ),
          isTrue,
        );
        expect(
          identical(
            withReviewedReferenceFacts(original, itemId: null),
            original,
          ),
          isTrue,
        );
      }
    },
  );
  test(
    'currency descriptions preserve the exchange step and conditional gauge',
    () {
      for (final book in books.values) {
        final coin = book.itemInfoFor('Divine Coin')!;
        expect(coin.summary, isEmpty);
        expect(
          coin.acquisitionNotes.where(
            (line) =>
                line ==
                'Exchange Inner Edania monster loot with Lafi Bedmountain',
          ),
          hasLength(1),
        );
        expect(
          coin.acquisitionNotes,
          isNot(contains('Inner Edania monster-zone loot')),
        );
        expect(coin.notes.join(' '), contains('85 Branch of Abundance'));
        final scroll = book.itemInfoFor('Item Collection Increase Scroll')!;
        expect(scroll.effects, [
          'Gauge level 1: Item Drop Rate +100%, Item Drop Amount +50%',
          'Gauge level 2: Item Drop Rate +100%, Item Drop Amount +100%',
        ]);
        expect(scroll.notes, contains('Gauge level 0: off.'));
      }
    },
  );
  test(
    'unlisted quest sources keep family restrictions and never assign market IDs',
    () {
      for (final book in books.values) {
        for (final entry in reviewedUnlistedReferenceSources.entries) {
          final actual = book.itemInfoFor(entry.key)!;
          expect(
            actual.acquisitionNotes,
            containsAll(entry.value),
            reason: entry.key,
          );
          expect(repository.bundledMarketId(entry.key), isNull);
          if (entry.key == 'Ancient Hammer' ||
              entry.key == 'Primordial Hammer') {
            expect(
              actual.notes,
              contains(
                'Finish all Atoraxxion story quests; choose Ancient or Primordial Hammer.',
              ),
            );
            expect(
              actual.acquisitionNotes.join(' '),
              contains('once per Family'),
            );
          }
          if (entry.key.endsWith('(Bound)')) {
            expect(actual.notes.join(' '), contains('300+ AP'));
            expect(actual.notes.join(' '), contains('cannot be sold'));
          }
          if (entry.key == "Dahn's Gloves (Bound)" ||
              entry.key == "Ator's Shoes (Bound)") {
            expect(
              actual.notes,
              contains('Reward choice: Damage Reduction or Evasion version.'),
            );
            // This is deliberately a family reference, not either tradable ID.
            expect(actual.effects, isEmpty);
            expect(actual.acquisitionFormulas, isEmpty);
          }
          expect(
            identical(
              withReviewedUnlistedReferenceSources(actual, recipe: null),
              actual,
            ),
            isTrue,
          );
        }
        for (final id in [64853, 64861, 64857]) {
          final actual = book.itemInfoFor(exchangeItems[id]!.name)!;
          expect(
            actual.acquisitionNotes.join(' '),
            contains('300 Sangpyeong Coin'),
          );
          expect(actual.notes.join(' '), contains('Once per Family'));
        }
      }
    },
  );
  test(
    'current party names find existing recipes and leave IDs and saved keys intact',
    () {
      final book = books[CraftMode.alchemy]!;
      final before = app.documentSnapshot.toJson();
      for (final name in reviewedPartyDraughtNames) {
        final display = itemDisplayName(name);
        book.setSearch(display);
        expect(book.snapshot.entries.map((e) => e.name), contains(name));
        expect(book.recipeFor(display)?.name, name);
        expect(
          book.itemInfoFor(display)?.effects,
          book.itemInfoFor(name)?.effects,
        );
        expect(catalog.alchemy.items.containsKey(display), isFalse);
      }
      book.setSearch('[Party] Harmony');
      expect(
        book.snapshot.entries.map((e) => e.name),
        containsAll(reviewedPartyDraughtNames),
      );
      book.setSearch('');
      expect(app.documentSnapshot.toJson(), before);
    },
  );
  test('reviewed repeated source facts stay compact in every calling mode', () {
    const exchangeNames = [
      'Beer',
      'Clear Liquid Reagent',
      'Fruit of Nature',
      'Log',
      'Milk',
      'Powder of Darkness',
      'Powder of Earth',
      'Powder of Flame',
      'Powder of Rifts',
      'Powder of Time',
      'Rough Stone',
      'Shining Powder',
      'Trace of Nature',
      'Wild Grass',
    ];
    for (final book in books.values) {
      for (final name in exchangeNames) {
        final sources = book.itemInfoFor(name)!.acquisitionNotes;
        expect(
          sources.any((line) => line.startsWith('Exchange ·')),
          isTrue,
          reason: name,
        );
        expect(
          sources.where(
            (line) => RegExp(r' with (Liana|Dalishain)$').hasMatch(line),
          ),
          isEmpty,
          reason: name,
        );
      }
      final milk = book.itemInfoFor('Milk')!.acquisitionNotes;
      expect(
        milk.where((line) => line.contains("Witch's Delicacy")),
        hasLength(1),
      );
      expect(milk.join(' '), contains('Nadia Rowen · Olvia'));
      expect(milk.join(' '), contains('10 Energy per try'));
      expect(
        book
            .itemInfoFor('Essence of Dawn')!
            .acquisitionNotes
            .where((s) => s.contains('Black Shrine')),
        hasLength(1),
      );
      for (final part in ['Flower', 'Leaf', 'Stalk']) {
        final sources = book
            .itemInfoFor('Insectivore Plant $part')!
            .acquisitionNotes;
        expect(sources.where((s) => s.contains('Naga Marsh')), hasLength(1));
        expect(
          sources.join(' '),
          contains('do not try to gather this drop with a tool'),
        );
      }
      final crystal = book
          .itemInfoFor('Magical Lightstone Crystal')!
          .acquisitionNotes;
      expect(crystal, hasLength(1));
      expect(
        crystal.single,
        contains('amount received depends on the lightstone'),
      );
      final mass = book.itemInfoFor('Mass of Pure Magic')!.acquisitionNotes;
      expect(
        mass.where((s) => s.contains("Dark Spirit's Greed")),
        hasLength(1),
      );
      expect(mass.join(' '), contains("5 Hunter's Seals"));
      final herbs = book.itemInfoFor('Pile of Sunrise Herbs')!.acquisitionNotes;
      expect(herbs.where((s) => s.contains('Wild Herbs')), hasLength(1));
      expect(herbs.join(' '), contains('depends on Gathering level'));
    }
  });

  for (final name in <String>[
    'Destruction Spirit Stone',
    'Guardian Spirit Stone',
    'Life Spirit Stone',
    for (final grade in ['Imperfect', 'Resplendent', 'Splendid', 'Shining'])
      for (final role in ['Destruction', 'Protection', 'Life'])
        '$grade Alchemy Stone of $role',
    for (final prefix in ['', 'Resplendent ', 'Splendid ', 'Shining ']) ...[
      "${prefix}Vell's Heart",
      for (final role in ['Destruction', 'Protection', 'Life'])
        "${prefix}Khan's Heart: $role",
    ],
  ]) {
    test('$name has current passive equipment facts in all three modes', () {
      final views = books.values.map((b) => b.itemInfoFor(name)!).toList();
      for (final info in views) {
        final prose = [info.summary, ...info.uses, ...info.notes].join(' ');
        expect(prose.toLowerCase(), contains('while equipped'));
        expect(
          RegExp(
            r'press U|activat|timed effect|Duration:|Cooldown:',
            caseSensitive: false,
          ).hasMatch(prose),
          isFalse,
          reason: '$name still describes retired activation mechanics: $prose',
        );
        expect(info.effects, views.first.effects);
        expect(info.uses, views.first.uses);
        expect(info.notes, views.first.notes);
        if (name.endsWith("Khan's Heart: Life")) {
          expect(
            info.effects.where((e) => e.contains('Mastery +25')).length,
            1,
          );
        }
        if (name == 'Destruction Spirit Stone') {
          expect(
            info.effects,
            containsAll(['Attack Speed +4%', 'Casting Speed +4%']),
          );
        }
        if (name.endsWith("Vell's Heart")) {
          expect(info.effects, contains('Displayed AP +3 (while equipped)'));
        } else if (name.endsWith("Khan's Heart: Destruction")) {
          expect(info.effects, contains('Displayed AP +2 (while equipped)'));
        } else if (name.endsWith("Khan's Heart: Protection")) {
          expect(info.effects, contains('Displayed DP +2 (while equipped)'));
        }
        if (name.startsWith('Resplendent ') ||
            name.startsWith('Splendid ') ||
            name.startsWith('Shining ')) {
          if (name.contains('Heart')) {
            expect(
              info.notes,
              contains(contains('Brimming Essence of Aether')),
            );
            expect(info.notes, contains(contains('has not been upgraded')));
          }
        }
      }
    });
  }

  test(
    'removed Splendid Spirit Stone is not presented as usable equipment',
    () {
      for (final book in books.values) {
        final info = book.itemInfoFor('Splendid Spirit Stone of Destruction')!;
        expect(info.kind, 'Removed item');
        expect(info.summary, contains('Removed in the September 3, 2026'));
        expect(info.effects, isEmpty);
        expect(
          info.notes,
          contains('Removed stones were compensated with Silver.'),
        );
        expect(
          info.notes.join(' '),
          isNot(contains('equivalent Alchemy Stone')),
        );
      }
    },
  );

  test(
    'all confirmed retired references have no active recipe or source in any mode',
    () {
      final before = app.documentSnapshot;
      final checkedCrystals = <String>{};
      for (final entry in removedPcItemsById.entries) {
        for (final book in books.values) {
          final info = book.itemInfoFor(entry.value);
          if (info == null) {
            expect(
              removedJanuary2024CrystalsById.containsKey(entry.key),
              isTrue,
            );
            continue; // Not every removed game identity is a bundled reference.
          }
          if (removedJanuary2024CrystalsById.containsKey(entry.key)) {
            checkedCrystals.add(
              '${book.modeController.mode.name}:${entry.value}',
            );
            expect(info.effects, isEmpty);
            expect(info.notes, isEmpty);
          }
          expect(
            info.kind,
            removedPcItemLabelFor(entry.value),
            reason: entry.value,
          );
          expect(
            info.summary,
            removedPcItemReasonFor(entry.value),
            reason: entry.value,
          );
          expect(info.notes, isNot(contains(temporarilyArchivedItemReason)));
          expect(info.isTemporarilyArchived, isTrue);
          expect(info.howToObtain, isEmpty, reason: entry.value);
          expect(info.craftUses, isEmpty, reason: entry.value);
          expect(book.activate(entry.value), isNull, reason: entry.value);
          expect(
            book.modeController.craftableNames,
            isNot(contains(entry.value)),
          );
          expect(book.modeController.selectTarget(entry.value), isFalse);
          expect(book.modeController.selectTargetVariant(entry.value), isFalse);
          expect(
            book.snapshot.entries.where((e) => e.name == entry.value),
            isEmpty,
          );
        }
      }
      //64 IDs have60 distinct names. Historical direct lookups work even for
      // names absent from the ordinary2263-reference browse inventory.
      expect(checkedCrystals, hasLength(180));
      for (final book in books.values) {
        for (final name in [
          'Alchemy Stone Shard',
          'Shining Powder',
          'Oil of Tranquility',
        ]) {
          expect(
            book
                .itemInfoFor(name)!
                .craftUses
                .where((u) => isRemovedPcItem(u.output)),
            isEmpty,
          );
        }
      }
      expect(identical(app.documentSnapshot, before), isTrue);
    },
  );

  test('cup extraction uses the August PC replacement in every shared mode', () {
    final before = app.documentSnapshot;
    for (final book in books.values) {
      for (final name in removedAugust2026CupMaterialsById.values) {
        final info = book.itemInfoFor(name)!;
        expect(info.kind, removedPcItemLabel);
        expect(info.summary, removedAugust2026CupMaterialReason);
        expect(info.effects, isEmpty);
        expect(info.uses, isEmpty);
        expect(info.craftUses, isEmpty);
        expect(info.acquisitionFormulas, isEmpty);
        expect(info.acquisitionNotes, isEmpty);
        expect(info.notes, [
          'Cups now use Mirror of Equilibrium for extraction.',
        ]);
      }
      for (final family in ['Ekleta', 'Apeiron']) {
        for (final slot in const {
          'Necklace': 'Dawnbound',
          'Earring': 'Moonhushed',
          'Ring': 'Sunstarved',
          'Belt': 'Duskborne',
        }.entries) {
          final name = '${slot.value} $family ${slot.key}';
          final info = book.itemInfoFor(name)!;
          expect(
            info.notes,
            contains(
              'Extract with Mirror of Equilibrium to recover the original accessory and cup.',
            ),
          );
          expect(
            [...info.howToObtain, ...info.notes, ...info.uses].join(' '),
            isNot(contains('Refined Essence of Emotions')),
          );
          expect(info.acquisitionFormulas, hasLength(1));
          expect(info.acquisitionFormulas.single.ingredients, hasLength(2));
        }
      }
      for (final name in [
        'Shard of the Furious Night',
        'Shard of the Tearful Night',
        'Shard of the Drained Night',
        'Forest Fury',
        'Magical Shard',
      ]) {
        final info = book.itemInfoFor(name)!;
        expect(
          info.craftUses.where(
            (use) =>
                removedAugust2026CupMaterialsById.values.contains(use.output),
          ),
          isEmpty,
        );
        expect(info.craftUses, isNotEmpty);
      }
      expect(
        book.itemInfoFor('Fused Crystal of Decimation')!.isTemporarilyArchived,
        isFalse,
      );
    }
    expect(identical(app.documentSnapshot, before), isTrue);
  });

  test(
    'October 29 perfumes retain exact single and bulk routes in every mode',
    () {
      for (final name in [
        'Perfume of Resolve',
        'Immortal: Perfume of Resolve',
      ]) {
        final recipe = catalog.processing.items[name]!;
        final id = name.startsWith('Immortal:') ? '1419' : '1418';
        expect(recipe.marketId, id);
        expect(recipe.variants.length, name.startsWith('Immortal:') ? 4 : 2);
        for (final variant in recipe.variants) {
          final selected = recipe.resolveVariant(variant.id);
          final bulk = variant.id.endsWith('-10x');
          expect(processingOutputPerCraft(recipe: selected), bulk ? 10 : 1);
          final essence = selected.ingredients.where(
            (i) => i.name == "Ibellab's Essence",
          );
          if (bulk) {
            expect(essence.single.quantity, 1);
          } else {
            expect(essence, isEmpty);
          }
          final standard = recipe.resolveVariant(
            variant.id.replaceAll('-10x', ''),
          );
          for (final ingredient in standard.ingredients) {
            expect(
              selected.ingredients
                  .singleWhere((i) => i.name == ingredient.name)
                  .quantity,
              ingredient.quantity * (bulk ? 10 : 1),
            );
          }
        }
        for (final book in books.values) {
          final info = book.itemInfoFor(name)!;
          expect(
            info.effects,
            containsAll([
              'All Resistance +10%',
              'All Damage Reduction +15',
              'Max HP +300',
              'Movement Speed +5%',
              'Max Stamina +300',
            ]),
          );
          expect(info.notes, contains('Duration: 20 min.'));
          expect(info.notes, contains('Cooldown: 10 sec.'));
          expect(info.acquisitionFormulas, isNotEmpty);
        }
      }
    },
  );

  test(
    'new hunting ingredients retain sources through all reference callers',
    () {
      for (final row in [
        ('Khalk Blood', '6360'),
        ('Tainted Khalk Fluid', '821472'),
      ]) {
        expect(catalog.alchemy.items[row.$1]!.marketId, row.$2);
        for (final book in books.values) {
          final info = book.itemInfoFor(row.$1)!;
          expect(
            info.howToObtain.join(' '),
            contains('Despair-Consumed Khalk'),
          );
          expect(info.howToObtain.join(' '), contains('Inner Edania'));
        }
      }
    },
  );

  test(
    'pure metal ranges agree across planner and all shared reference modes',
    () {
      const metals = [
        'Copper',
        'Gold',
        'Iron',
        'Lead',
        'Mythril',
        'Nickel',
        'Noc',
        'Platinum',
        'Silver',
        'Tin',
        'Titanium',
        'Vanadium',
        'Zinc',
      ];
      for (final metal in metals) {
        final name = 'Pure $metal Crystal';
        final recipe = app.modes[CraftMode.processing]!.recipes[name]!;
        expect(recipe.outputMinimum, 1);
        expect(recipe.outputMaximum, 3);
        expect(processingOutputPerCraft(recipe: recipe), 2);
        for (final book in books.values) {
          final info = book.itemInfoFor(name)!;
          expect(info.acquisitionFormulas, isNotEmpty);
          for (final formula in info.acquisitionFormulas) {
            expect(formula.outputMinimum, 1);
            expect(formula.outputMaximum, 3);
            expect(formula.outputEstimated, isTrue);
          }
        }
      }
      // No extrapolation to a newly introduced metal with different evidence.
      expect(
        processingOutputPerCraft(
          recipe: catalog.processing.items['Pure Magnetite Crystal']!,
        ),
        1,
      );
    },
  );

  test('reviewed starter and ordinary potion sources reach every mode', () {
    final evidence =
        jsonDecode(
              File(
                'docs/reviewed-source-supplement-20261102.json',
              ).readAsStringSync(),
            )
            as Map;
    final rows = evidence['records'] as List;
    expect(rows, hasLength(35));
    for (final row in rows.cast<Map>()) {
      final name = row['name'] as String;
      for (final book in books.values) {
        final info = book.itemInfoFor(name)!;
        for (final line in (row['lines'] as List).cast<String>()) {
          expect(
            info.acquisitionNotes,
            contains(line),
            reason: '$name / ${book.modeController.mode}',
          );
        }
      }
    }
  });

  test('Gauche reform information matches October 29 in every shared mode', () {
    for (final book in books.values) {
      final info = book.itemInfoFor("Gauche Rawr-Rawr's Heart")!;
      final text = [...info.uses, ...info.notes].join(' ');
      expect(text, contains('Max Durability +200'));
      expect(text, contains('Max Durability +250 (600 total)'));
      expect(text, isNot(contains('Max Durability +50')));
      expect(text, contains('Each reform uses 1 heart.'));
    }
  });

  test('all thirty rare-food source repairs reach each shared mode', () {
    final document =
        jsonDecode(
              File(
                'docs/reviewed-rare-food-sources-20261102.json',
              ).readAsStringSync(),
            )
            as Map<String, dynamic>;
    final rows = document['items'] as List<dynamic>;
    expect(rows, hasLength(30));
    for (final row in rows.cast<Map<String, dynamic>>()) {
      final name = row['name'] as String;
      for (final book in books.values) {
        final info = book.itemInfoFor(name)!;
        expect(info.howToObtain, contains(row['source']), reason: name);
        expect(
          info.howToObtain.where((line) => line == row['source']),
          hasLength(1),
        );
        expect(
          info.howToObtain.any((line) => line.contains('Central Market')),
          isTrue,
        );
        expect(
          info.acquisitionFormulas,
          isEmpty,
          reason:
              'A rare source hint must not become a guaranteed independent recipe: $name',
        );
      }
    }
    for (final book in books.values) {
      final normal = book.itemInfoFor('Chanterelle Risotto')!;
      expect(normal.howToObtain, contains('Cooking · Professional 1+'));
      expect(
        normal.howToObtain.any((line) => line.contains('rare extra')),
        isFalse,
      );
    }
  });

  test(
    'reviewed localized food parents keep exact rare skill and no recipe',
    () {
      const sources = {
        'Fresh White Kimchi':
            'Cooking · Make White Kimchi (rare extra, Skilled 9+)',
        'High-quality Eilton Sandwich':
            'Cooking · Make Eilton Sandwich (rare extra, Master 1+)',
      };
      for (final book in books.values) {
        for (final entry in sources.entries) {
          final info = book.itemInfoFor(entry.key)!;
          expect(info.howToObtain, contains(entry.value));
          expect(info.howToObtain.where((s) => s == entry.value), hasLength(1));
          expect(info.acquisitionFormulas, isEmpty);
          expect(
            info.howToObtain.any((s) => s.contains('Central Market')),
            isTrue,
          );
        }
        final normal = book.itemInfoFor('White Kimchi')!;
        expect(normal.howToObtain, contains('Cooking · Apprentice 1+'));
        expect(
          normal.howToObtain.any((s) => s.contains('rare extra')),
          isFalse,
        );
        expect(normal.notes, contains('Duration: 60 min.'));
        expect(
          book.itemInfoFor('Fresh White Kimchi')!.notes,
          contains('Duration: 90 min.'),
        );
        expect(
          book.itemInfoFor('High-quality Eilton Sandwich')!.notes,
          contains('Duration: 120 min.'),
        );
      }
    },
  );

  test('Dawn multiplication hints retain the seed and net output in every mode', () {
    for (final book in books.values) {
      for (final suffix in [
        "Black Spirit's Rage",
        'Accuracy',
        'Damage Reduction',
        'Evasion',
      ]) {
        final name = 'Essence of Dawn - $suffix';
        final info = book.itemInfoFor(name)!;
        expect(
          info.acquisitionNotes,
          containsAll([
            "Heating · Eligible enhanced accessories + Dawn's Aura",
            "Simple Alchemy · 1 of this essence + 1 Dark Bonghwang's Tear → 30 (net +29)",
            '10× batch · 10 of each input + 1 Black Stone Powder → 300 (net +290)',
          ]),
        );
        expect(
          info.acquisitionFormulas,
          isEmpty,
          reason:
              'Manual conversion must not expose incomplete/free-input Planner formulas.',
        );
      }
      expect(
        book
            .itemInfoFor('Essence of Dawn')!
            .howToObtain
            .any((s) => s.contains('net +29')),
        isFalse,
        reason:
            'The unqualified essence is not one of the four eligible inputs.',
      );
    }
  });

  test('reviewed shop sources reach all modes without implying silver sales', () {
    const costs = {
      'Moon Scale Plywood': 15,
      'Moon Vein Flax Fabric': 40,
      'Tide-Dyed Standardized Timber Square': 80,
      'Deep Tide-Dyed Standardized Timber Square': 80,
      'Wave Residue Adhesive': 300,
      'Tear of the Ocean': 400,
    };
    for (final book in books.values) {
      for (final entry in costs.entries) {
        final info = book.itemInfoFor(entry.key)!;
        expect(
          info.howToObtain,
          contains('Crow Coin Shop · ${entry.value} coins each'),
        );
        expect(info.howToObtain.any((s) => s.contains('Silver')), isFalse);
        expect(
          info.acquisitionFormulas,
          isNotEmpty,
          reason: 'Existing processing route must remain: ${entry.key}',
        );
      }
      final tea = book.itemInfoFor('Star Anise Tea')!;
      expect(
        tea.howToObtain,
        contains(
          'NPC · General Goods Vendors in Sand Grain Bazaar, Muiquun or Arehaza',
        ),
      );
      expect(tea.acquisitionFormulas, isNotEmpty);
      for (final name in ['Mythical Feather', 'Primordial Crystal']) {
        final info = book.itemInfoFor(name)!;
        expect(
          info.howToObtain,
          containsAll([
            'Patrigio · Random night-shop offer (22:00–07:00 game time)',
            'Secret Shop · 50 Energy per roll; Silver price varies',
          ]),
        );
        expect(
          info.howToObtain.where((s) => s.startsWith('NPC ·')),
          isEmpty,
          reason: 'A random night offer is not guaranteed ordinary NPC stock.',
        );
      }
      final crystal = book.itemInfoFor('Magic Crystal of Perfection')!;
      expect(
        crystal.howToObtain.any(
          (s) => RegExp(r'jeweler|NPC|shop', caseSensitive: false).hasMatch(s),
        ),
        isFalse,
        reason: 'The shop crystal 768715 is not processible market item 15021.',
      );
      for (final name in [
        "Khan's Scale",
        "Khan's Tendon",
        "Oquilla's Flower",
      ]) {
        final notes = book.itemInfoFor(name)!.howToObtain;
        expect(notes.any((s) => s.endsWith('Lv.')), isFalse, reason: name);
        expect(
          notes.any(
            (s) =>
                s.contains('Lv. ') &&
                (s.contains('Barter') || s.contains('sea trade goods')),
          ),
          isTrue,
          reason: name,
        );
      }
    }
  });

  test(
    'removed Patrigio entries and same-name shop crystals stay excluded',
    () {
      for (final book in books.values) {
        for (final name in [
          'Blue Whale Molar Earring',
          'Mark of Shadow',
          'Tree Spirit Belt',
          "Witch's Earring",
        ]) {
          final info = book.itemInfoFor(name)!;
          expect(
            info.howToObtain.any(
              (s) => RegExp(
                r'Patrigio|Secret Shop|night.shop',
                caseSensitive: false,
              ).hasMatch(s),
            ),
            isFalse,
            reason:
                'The PC revamp removed $name; retained native links are stale.',
          );
          expect(
            info.howToObtain.any((s) => s.startsWith('Central Market')),
            isTrue,
          );
          expect(info.effects, isNotEmpty);
        }
        final crystal = book.itemInfoFor('Magic Crystal of Perfection')!;
        expect(
          crystal.howToObtain,
          contains('Monster drops · Check Monster Zone Info'),
        );
        expect(
          crystal.howToObtain.any(
            (s) =>
                RegExp(r'jeweler|NPC|shop', caseSensitive: false).hasMatch(s),
          ),
          isFalse,
          reason:
              'The shop-only768715 must not supply a source for market15021.',
        );
      }
    },
  );

  test('five positively listed Edania identities reach all shared callers', () {
    for (final row in const <String, String>{
      'Rough Marble': '4016',
      'Polished Marble': '4096',
      'Magnetite Ore': '4017',
      'Melted Magnetite Shard': '4098',
      'Magnetite Ingot': '4099',
    }.entries) {
      expect(repository.bundledMarketId(row.key), row.value);
      expect(isOpportunityMarketRequestEligible(row.value), isTrue);
      for (final book in books.values) {
        final info = book.itemInfoFor(row.key)!;
        expect(info.howToObtain.join(' '), contains('Central Market'));
        expect(info.howToObtain.length, greaterThan(1));
      }
    }
  });

  test(
    'Rawr heart source is the permanent weekly reward, not direct/event loot',
    () {
      for (final book in books.values) {
        final info = book.itemInfoFor("Rawr-Rawr's Heart")!;
        final text = info.howToObtain.join(' ');
        expect(text, contains('Weekly Rawr-Rawr quest'));
        expect(text, contains('Narcion, Lv. 2+'));
        expect(text, contains('reward box (chance)'));
        expect(text, isNot(contains('Hunt Rawr-Rawr.')));
        expect(text, isNot(contains('Traces of Untamed Ferocity')));
      }
    },
  );

  // Independent expected values: official PC patch 2024-09-12 and the exact
  // PC item/recipe records cited in docs/verified-item-information.json.
  for (final row in [
    (CraftMode.processing, 'Gem of Twilight', 'Caphras Stone', 20000.0),
    (CraftMode.processing, 'Sunset Glow Crystal', 'Caphras Stone', 10000.0),
    (CraftMode.alchemy, 'Elixir of Perforation', 'Pine Sap', 5.0),
    (CraftMode.alchemy, 'Looney Elixir', 'Powder of Flame', 3.0),
    (CraftMode.alchemy, 'Defense Elixir', 'Ash Sap', 6.0),
    (CraftMode.cooking, 'Soft Bread', 'Corn Dough', 6.0),
    (CraftMode.cooking, 'Red Bean Sirutteok', 'Sugar', 1.0),
    (CraftMode.cooking, 'Red Bean Porridge', 'Spring Water', 1.0),
    (CraftMode.processing, 'Pure Gold Crystal', 'Metal Solvent', 1.0),
    (CraftMode.processing, 'Pure Silver Crystal', 'Metal Solvent', 1.0),
    (CraftMode.processing, 'Pure Platinum Crystal', 'Metal Solvent', 1.0),
  ]) {
    test(
      '${row.$2} has the reviewed ingredient in catalog, assembled planner and every card',
      () {
        for (final recipe in [
          catalog.forMode(row.$1).items[row.$2]!,
          app.modes[row.$1]!.recipes[row.$2]!,
        ]) {
          expect(
            recipe.ingredients.singleWhere((i) => i.name == row.$3).quantity,
            row.$4,
          );
        }
        for (final book in books.values) {
          final info = book.itemInfoFor(row.$2)!;
          expect(info.acquisitionFormulas, isNotEmpty);
          for (final formula in info.acquisitionFormulas) {
            expect(
              formula.ingredients.singleWhere((i) => i.name == row.$3).quantity,
              row.$4,
            );
          }
        }
      },
    );
  }
  test(
    'fixed-output equipment materials keep one item per craft and full cost basis',
    () {
      for (final (name, amount) in [
        ('Gem of Twilight', 20000.0),
        ('Sunset Glow Crystal', 10000.0),
      ]) {
        final recipe = app.modes[CraftMode.processing]!.recipes[name]!;
        final output = processingOutputPerCraft(recipe: recipe);
        expect(output, 1);
        // Ten desired outputs must consume 10 full input batches, not 10 stones.
        expect(
          (10 / output).ceil() *
              recipe.ingredients
                  .singleWhere((i) => i.name == 'Caphras Stone')
                  .quantity,
          10 * amount,
        );
        final result = const PlannerEngine().buildPlan(
          mode: CraftMode.processing,
          recipes: app.modes[CraftMode.processing]!.recipes,
          state: plan.PlannerState(target: name, want: 10),
        );
        final step = result.steps.singleWhere((s) => s.name == name);
        expect(step.count, 10);
        expect(
          step.ingredients
              .singleWhere((i) => i.original == 'Caphras Stone')
              .need,
          10 * amount,
        );
      }
    },
  );
  test(
    'current boss reform recipes use consolidated crystals and the correct gem',
    () {
      for (final level in ['I', 'II', 'III', 'IV']) {
        final r = app
            .modes[CraftMode.processing]!
            .recipes['Resplendent Boss Armor Reform Stone $level']!;
        expect(
          r.ingredients
              .singleWhere((i) => i.name == 'Concentrated Boss Crystal')
              .quantity,
          60,
        );
        expect(
          r.ingredients.any((i) => i.name == 'Concentrated Giath Crystal'),
          isFalse,
        );
        if (level == 'IV') {
          expect(
            r.ingredients
                .singleWhere((i) => i.name == 'Rough Diamond')
                .quantity,
            1,
          );
        }
      }
    },
  );
  test(
    'fallback identities agree with exact recipes, without touching other identities',
    () {
      for (final (name, id) in [
        ('Oatmeal', '9261'),
        ('Refined Oatmeal', '9276'),
        ('Organic Feed', '54018'),
        ('Caphras Essence', '821259'),
        ('Daybreak Blue Coral', '4479'),
        ('Good Feed', '54017'),
        ('Special Honey Jar', '54032'),
        ("Dark Spirit's Greed", '767887'),
        ('Millennial Wild Ginseng', '820152'),
        ('Carrot', '54001'),
      ]) {
        expect(repository.bundledMarketId(name), id);
        expect(repository.bundledMarketId(name.toLowerCase()), id);
      }
    },
  );
  for (final name in [
    'Barley Dough',
    'Barley Flour',
    'Butter',
    'Corn Dough',
    'Corn Flour',
    'Cream',
    'Melted Iron Shard',
    'Potato Dough',
    'Potato Flour',
    'Red Pepper Powder',
    'Sweet Potato Dough',
    'Sweet Potato Flour',
    'Wheat Dough',
    'Wheat Flour',
    'Rice Flour',
    'Teff Flour',
  ]) {
    test('$name is one equivalent formula family in all three tabs', () {
      for (final book in books.values) {
        final formulas = book.itemInfoFor(name)!.acquisitionFormulas;
        expect(
          formulas.map(recipeBookPreviewFormulaIdentity).toSet(),
          hasLength(1),
        );
        expect(recipeBookPreviewRoutes(formulas), hasLength(1));
      }
    });
  }
  test(
    'Red Pepper Powder preserves exact grade inputs and explicitly estimated yield',
    () {
      for (final book in books.values) {
        for (final formula
            in book.itemInfoFor('Red Pepper Powder')!.acquisitionFormulas) {
          expect(formula.outputEstimated, isTrue);
          final input = formula.ingredients.single;
          expect(input.quantity, 5);
          expect(
            input.quantity * input.substituteRatios['High-Quality Hot Pepper']!,
            2,
          );
          expect(
            input.quantity * input.substituteRatios['Special Hot Pepper']!,
            1,
          );
        }
      }
    },
  );
  test(
    'Used for includes all explicitly eligible catalog consumers, not just one',
    () {
      for (final book in books.values) {
        expect(
          book.itemInfoFor('Perilla')!.craftUses.map((u) => u.output),
          containsAll(['Bean Sprout Salad', 'Perilla Oil']),
        );
        expect(
          book.itemInfoFor('Red Pepper Powder')!.craftUses.map((u) => u.output),
          containsAll(['Bean Sprout Salad', 'Dalbeol Gukbap']),
        );
        final uses = book
            .itemInfoFor('Clear Liquid Reagent')!
            .craftUses
            .map((u) => u.output)
            .toList();
        expect(uses.length, greaterThan(10));
        expect(uses.toSet().length, uses.length);
      }
    },
  );
  test(
    'shared facts and sources no longer change with the calling crafting tab',
    () {
      for (final name in [
        'Perilla',
        'Elixir of Sharp Detection',
        'Cold Draft Beer',
        'Red Pepper Powder',
        'Ground Bird Meat',
        'Tiger Blood',
        'Pile of Sunrise Herbs',
      ]) {
        final infos = books.values.map((b) => b.itemInfoFor(name)!).toList();
        for (final info in infos.skip(1)) {
          expect(info.summary, infos.first.summary, reason: name);
          expect(info.kind, infos.first.kind, reason: name);
          expect(
            info.acquisitionNotes,
            infos.first.acquisitionNotes,
            reason: name,
          );
        }
        expect(
          infos.first.acquisitionNotes.join(' '),
          isNot(matches(r'BDO item|BDO material group|Reviewed against four')),
        );
      }
    },
  );
  test(
    'Perilla has short gathering, starter-seed and market guidance everywhere',
    () {
      for (final book in books.values) {
        final sources = book.itemInfoFor('Perilla')!.acquisitionNotes.join(' ');
        expect(sources, contains('Gather · Perilla plants in Morning Light'));
        expect(sources, contains('Noyoung'));
        expect(sources, contains('Central Market'));
        expect(sources, contains('Garden'));
      }
    },
  );
  test(
    'reviewed mushroom aliases preserve sources for canonical names too',
    () {
      for (final book in books.values) {
        for (final name in [
          'Fortune Mushroom',
          'Fortune Teller Mushroom',
          'Special Fortune Mushroom',
          'Special Fortune Teller Mushroom',
        ]) {
          final sources = book.itemInfoFor(name)!.acquisitionNotes.join(' ');
          expect(sources, contains('Central Market'), reason: name);
          expect(
            sources,
            contains(name.startsWith('Special') ? 'Garden' : 'Gather'),
            reason: name,
          );
        }
      }
    },
  );
  for (final name in [
    'Antidote Elixir',
    'Elixir of Burn Removal',
    'Elixir of Hemostasis',
  ]) {
    test('$name uses the PC client 10-second cooldown in every card', () {
      for (final book in books.values) {
        final notes = book.itemInfoFor(name)!.notes.join(' ');
        expect(notes, contains('Cooldown: 10 sec.'));
        expect(notes, isNot(contains('30 sec')));
      }
    });
  }

  test(
    'corrected Alchemy inputs reach the actual Opportunities cost calculator',
    () {
      final recipes = app.modes[CraftMode.alchemy]!.recipes;
      for (final (name, input, count) in [
        ('Elixir of Perforation', 'Pine Sap', 5.0),
        ('Looney Elixir', 'Powder of Flame', 3.0),
        ('Defense Elixir', 'Ash Sap', 6.0),
      ]) {
        final quote = const RecipeProfitabilityCalculator().calculate(
          recipe: recipes[name]!,
          recipes: recipes,
          state: ModeState(
            target: name,
            bonusTarget: name,
            appearance: AppearanceSettings.defaultsFor(CraftMode.alchemy),
            market: MarketState(prices: {for (final n in recipes.keys) n: 10}),
          ),
          rules: plan.PlannerRules(),
          marketTax: MarketTax(),
        );
        expect(quote.isAvailable, isTrue, reason: name);
        final cost = quote.ingredientCosts.singleWhere(
          (c) => c.originalName == input,
        );
        expect(cost.quantity, count);
        expect(cost.total, count * 10);
      }
    },
  );

  test(
    'exchange facts are shared, idempotent, and retain route qualifications',
    () {
      for (final name in [
        'Witch\'s Delicacy',
        'Mysterious Catalyst',
        "Dark Spirit's Greed",
      ]) {
        final item = exchangeCatalog
            .singleWhere((c) => c.item.name == name)
            .item;
        final info = books[CraftMode.alchemy]!.itemInfoFor(name)!;
        final repeated = withExchangeReferenceInformation(info, item);
        expect(
          info.acquisitionNotes,
          contains(
            reviewedReferenceFacts[item.id]?.sources.firstOrNull ??
                exchangeCatalog
                    .singleWhere((c) => c.item.name == name)
                    .sourceActivity,
          ),
        );
        expect(repeated.acquisitionNotes, info.acquisitionNotes);
        expect(repeated.notes, info.notes);
        for (final book in books.values) {
          expect(
            book.itemInfoFor(name)!.acquisitionNotes,
            info.acquisitionNotes,
          );
        }
      }
      final milk = books[CraftMode.cooking]!.itemInfoFor('Milk')!;
      expect(milk.acquisitionNotes.join(' '), contains('Witch\'s Delicacy'));
      expect(milk.acquisitionNotes.join(' '), contains('Exchange'));
      final ginseng = books[CraftMode.cooking]!.itemInfoFor(
        'Millennial Wild Ginseng',
      )!;
      expect(
        ginseng.acquisitionNotes.join(' '),
        contains('Gathering minigames'),
      );
      expect(ginseng.acquisitionNotes.join(' '), contains('Energy of Lakiaro'));
      expect(ginseng.acquisitionNotes.join(' '), contains('Central Market'));
      expect(ginseng.effects, contains('Max Energy +50'));
    },
  );
}
