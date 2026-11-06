import 'item_source_index.dart';
import 'recipe_book_item_info.dart';
import 'recipe_book_item_purpose.dart';
import 'reviewed_gathering_wording.dart';
import 'reviewed_item_source_additions.dart';

/// Read-only wording projection. Never changes a recipe, effect or saved note.
/// Additional sources require an exact item ID from the bundled catalog.
RecipeBookItemInfo withPlainItemInformation(
  RecipeBookItemInfo info, {
  String? itemId,
  Iterable<String>? reviewedRoutes,
}) {
  if (info.isTemporarilyArchived) return info;
  final hints = bundledItemSourceHints[int.tryParse(itemId ?? '')];
  final workers = hints?.workers ?? const <String>[];
  final original = info.acquisitionNotes;
  final lines = <String>[];
  var uses = info.uses;
  var notes = info.notes;
  var summary = info.summary;
  for (final line in original) {
    if (info.title == 'Primordial Hammer' &&
        line == 'Limited-event reward from hammer selection boxes.') {
      // Keep its permanent Atoraxxion source, not an unspecified past event.
      continue;
    }
    final gathering = reviewedGatheringWording[info.title]?[line];
    if (gathering != null) {
      lines.add(gathering);
      continue;
    }
    // These exact imported sentences describe spending the item, not obtaining
    // it. Retain the information under Used for; never rewrite arbitrary notes.
    if ((info.title == 'Embers of the Primordial' &&
            line == 'Heat 100 Embers to make a Flame of the Primordial.') ||
        (info.title == "Nadia Rowen's Special Sauce" &&
            line == 'Used once when processing a 10x Cron Meal batch.') ||
        (info.title == 'Primordial Hammer' &&
            line ==
                'If you already own one, Heating converts it into Cron Stone x1,000.')) {
      uses = {...uses, line}.toList();
      continue;
    }
    if (const {
      'Embers of Ynix - Armor',
      'Embers of Ynix - Helmet',
      'Embers of Ynix - Gloves',
      'Embers of Ynix - Shoes',
    }.contains(info.title)) {
      if (RegExp(
        r'^A (armor|helmet|gloves|shoes)-part Godslayer exchange material\.$',
      ).hasMatch(line)) {
        if (summary.isEmpty) summary = 'Exchange material for Godslayer gear.';
        continue;
      }
      if (RegExp(
        r"^Collect 100 and exchange them with the Ynix Remnant for Edana - Godslayer's (Abstinence|Courage|Justice|Wisdom) Box\.$",
      ).hasMatch(line)) {
        uses = {
          ...uses.where(
            (s) =>
                s !=
                'Exchange 100 with the Ynix Remnant for the matching Edana Godslayer box.',
          ),
          line,
        }.toList();
        lines.add(
          'Inner Edania · Open matching Broken Vestiges or weekly boss reward chests',
        );
        continue;
      }
    }
    if (const {
      'Eltro Sea Crystal',
      'Serni Sea Crystal',
      'Margoria Sea Crystal',
    }.contains(info.title)) {
      final crystal = info.title.replaceFirst(' Sea Crystal', ' Crystal');
      if (line == 'Use ${crystal}s obtained from defeating sea monsters.') {
        lines.add(
          'Right-click a $crystal (from sea monsters) for a random Sea Crystal.',
        );
        continue;
      }
    }
    if (info.title == 'Crystallized Energy of Endtimes' &&
        line ==
            'Only one For the Throne boss quest can be completed each week.' &&
        lines.isNotEmpty &&
        lines.last ==
            'Weekly For the Throne and Purify quests for those four zones also award it.') {
      // Keep this exact weekly limit attached to the route it qualifies.
      lines[lines.length - 1] = '${lines.last} $line';
      continue;
    }
    // This paragraph explains spending Fairy's Breath, not obtaining it.
    // Preserve the exact recorded rewards, but put them in Used for.
    if ((itemId == null || itemId == '821371') &&
        info.title == "Fairy's Breath" &&
        line.startsWith(
          'Obtained while Gathering. Exchange 10 with Dalishain for one reward:',
        )) {
      const rewards =
          'Exchange 10 with Dalishain for one reward:\n'
          '30 Wild Grass\n20 Log\n12 Rough Stone\n1 Fruit of Nature\n'
          '1 Trace of Nature\n900 Contribution EXP and 30 Gathering EXP';
      lines.add('Gathering');
      uses = {
        ...uses.where((s) => s != 'Exchange at Dalishain · major cities.'),
        rewards,
      }.toList();
      notes = {
        ...notes,
        "The current Fairy's Breath does not exchange for Sharps.",
      }.toList();
      continue;
    }
    // Research status belongs in audit files, never item instructions. Remove
    // only these exact inherited audit statements; do not invent a source or
    // discard real restrictions, user notes or calculation limitations.
    if ((itemId == '4996' &&
            info.title == 'Black Essence' &&
            line ==
                'No current acquisition route is verified for generic Black Essence (item 4996).') ||
        (itemId == '12207' &&
            info.title == 'Rhutum Belt' &&
            line ==
                'No current acquisition source is verified for the base Rhutum Belt (item 12207).')) {
      continue;
    }
    // Only replace the old, unconditional worker-location list. Never discard
    // a mixed reward, quest, price, chance, unlock or region condition.
    final mixed = RegExp(
      r'^(.+), or send (?:a worker|workers) to ([^.?!;]+)\.$',
    ).firstMatch(line);
    final workerOnly = RegExp(
      r'^Send (?:a worker|workers) to ([^.?!;]+)\.$',
    ).hasMatch(line);
    if (workers.isNotEmpty &&
        (reviewedRoutes?.contains(line) ?? false) &&
        (mixed != null || workerOnly) &&
        !RegExp(
          r'\b(only|after|before|requires?|chance|rare|quest|weekly|daily|cost)\b',
          caseSensitive: false,
        ).hasMatch(line)) {
      if (mixed != null) lines.add(plainAcquisitionLine('${mixed[1]}.'));
      lines.addAll(workers);
    } else {
      lines.add(plainAcquisitionLine(line));
    }
  }
  lines.addAll(workers);
  if ((info.title == 'Beef' && (itemId == null || itemId == '7906')) ||
      (info.title == 'Ox Hide' && (itemId == null || itemId == '6006'))) {
    lines.add('Garden · Harvest Haystacks (chance)');
  }
  if (isReviewedQualityFarmMaterial(info.title) &&
      !original.any(
        (line) => RegExp(
          r'\b(garden|harvest|farming)\b',
          caseSensitive: false,
        ).hasMatch(line),
      )) {
    lines.add('Garden · Harvest the crop');
  }
  // Current PC item 9283, reviewed 2026-10-31:
  // https://bdocodex.com/us/item/9283/ (Skilled 1 is required for this extra).
  if (itemId == '9283' && !original.any((line) => line.contains('Skilled 1'))) {
    lines.add('Cooking · Make Beer (rare extra, Skilled 1+)');
  }
  // A broad existing gathering route already tells users the source type.
  // Do not turn a concise card into a long list of every mapped tree/animal.
  final hasGathering = original.any(
    (line) => RegExp(
      r'\b(gather|gathering|collect|collecting|lumber|lumbering|mine|mining|butcher|butchering|tan|tanning|hunt|hunting|milk)\b',
      caseSensitive: false,
    ).hasMatch(line),
  );
  if (!hasGathering && hints != null) {
    lines.addAll(
      hints.gathering.map((line) {
        final tool = RegExp(
          r'^Use a (Fluid Collector|Lumbering Axe|Butcher Knife|Tanning Knife) on (.+) to obtain (.+)\.$',
        ).firstMatch(line);
        // Only omit the known output name from an exact, indexed field fact.
        if (tool != null && tool[3] == hints.name) {
          return '${tool[1]} · ${tool[2]}';
        }
        return plainAcquisitionLine(line);
      }),
    );
  }
  final additions = reviewedItemSourceAdditions[int.tryParse(itemId ?? '')];
  String identity(String value) => value
      .trim()
      .toLowerCase()
      .replaceAll('-', ' ')
      .replaceAll(RegExp(r'\s+'), ' ');
  // Legacy aliases can share a replacement item's ID. Do not transfer its
  // current sources to an old item or a user-defined same-ID reference.
  if (additions != null &&
      [
        additions.name,
        ...additions.aliases,
      ].any((name) => identity(name) == identity(info.title))) {
    for (final line in additions.lines) {
      // Keep a richer market condition (or a prohibition) instead of appending
      // a generic market line. Never turn eligibility into a stock promise.
      if (line.startsWith('Central Market') &&
          lines.any((value) => value.toLowerCase().contains('market'))) {
        continue;
      }
      lines.add(line);
    }
  }
  final unique = <String>[];
  final seen = <String>{};
  for (final line in lines) {
    final text = line.trim();
    final identity = text.toLowerCase().replaceFirst(RegExp(r'\.$'), '');
    if (text.isNotEmpty && seen.add(identity)) unique.add(text);
  }
  return info.copyWith(
    summary: plainItemDescription(summary),
    acquisitionNotes: compactReviewedAcquisitionSources(info.title, unique),
    uses: uses,
    notes: notes,
  );
}

/// Keep qualifications, numbers, signs, named targets and tools intact.
/// Unrecognized or complex copy stays verbatim instead of being guessed away.
String plainAcquisitionLine(String line) {
  const exact = <String, String>{
    'Optional: shoot beehives from trees in Balenos Forest with a matchlock. Collect them, then use Processing → Grinding on 3 Wild Beehives.':
        'Shoot beehives in Balenos Forest with a matchlock, collect them, then grind 3 Wild Beehives.',
    'Shoot beehives from trees in Balenos Forest with a matchlock, then collect them. Grind 3 Wild Beehives into Cooking Honey.':
        'Shoot beehives in Balenos Forest with a matchlock, then collect them.',
    // The bonus quest is chance-based, not guaranteed by each delivery.
    // Official PC source/type evidence: docs/reviewed-artifact-quest-sources.json.
    'Deliver Medicine Boxes through Imperial Delivery and complete the resulting Bonus Quest.':
        'Imperial Alchemy · Bonus quest reward (chance)',
    'Deliver Cooking Boxes through Imperial Delivery and complete the resulting Bonus Quest.':
        'Imperial Cooking · Bonus quest reward (chance)',
    'Deliver fish through Imperial Fishing Delivery and complete the resulting Bonus Quest.':
        'Imperial Fishing · Bonus quest reward (chance)',
    'Deliver horses through Imperial Horse Delivery and complete the resulting Bonus Quest.':
        'Imperial Horse Delivery · Bonus quest reward (chance)',
    'Deliver Medicine/Cooking Boxes or processed trade goods through Imperial Delivery and complete the resulting Bonus Quest.':
        'Imperial Delivery · Cooking/medicine boxes or processed trade goods (bonus quest chance)',
    'Sell trade goods and complete the resulting Bonus Quest.':
        'Trading · Bonus quest when selling trade goods (chance)',
    'Curated to the standard ore heating route; gear-melting variants are intentionally excluded from the planner.':
        'Heating · Ore (equipment recycling not planned)',
    'Curated to the standard ingot + metal solvent route; gear-melting variants are intentionally excluded from the planner.':
        'Heating · Ingots + Metal Solvent (equipment recycling not planned)',
    'Grinding eligible blue accessories is possible, but prices and stock vary enough that the planner leaves that conversion manual.':
        'Grinding · Some blue accessories (not included in planning)',
    'Defeat monsters in Kamasylvia.': 'Monster drops · Kamasylvia',
    'Buy through the Central Market.': 'Central Market',
    'Buy from the Central Market.': 'Central Market',
    'Buy it through the Central Market when listed.':
        'Central Market · When listed',
    'Buy through the Central Market when stock is available.':
        'Central Market · When in stock',
    'Buy from a Food Vendor or Innkeeper.': 'NPC · Food Vendor or Innkeeper',
    'Buy from a Material Vendor.': 'NPC · Material Vendor',
    'Purchase from a General Goods Vendor.': 'NPC · General Goods Vendor',
    'Purchase from the Old Moon Manager in town.': 'NPC · Old Moon Manager',
    'Purchase from Old Moon Manager shops in town.': 'NPC · Old Moon Manager',
    "Old Moon Manager's shop.": 'NPC · Old Moon Manager',
    'Obtain as a monster drop; use Monster Zone Info to see the current zones.':
        'Monster drops · Check Monster Zone Info',
    'Mine rocks with a pickaxe for a small chance to obtain it.':
        'Mine rocks with a pickaxe (rare)',
    'Lumber rarely from trees for a chance to obtain it.': 'Chop trees (rare)',
    'Lumber trees.': 'Chop trees',
    'Interact with a Dairy Cow, choose the milking interaction, and complete the minigame. Each attempt consumes 10 Energy.':
        'Gather · Milk cows (10 Energy per try)',
    'Node production (Areha Palm Forest).': 'Workers · Timber nodes',
    'Craft with an Alchemy Tool in a residence (Alchemy Apprentice 1+); see Crafting Notes for the ingredient list.':
        'Alchemy Tool at home · Apprentice 1+ (recipe in Crafting Notes)',
    'Use Simple Alchemy with the recipe shown in Crafting Notes; the result is chance-based.':
        'Simple Alchemy · Random result (recipe in Crafting Notes)',
    'Produce Alchemy Stones with an Alchemy Tool; the resulting type and grade depend on the alchemy-stone result.':
        'Alchemy Tool · Random stone type and grade',
    'Use the Processing method listed in Crafting Notes.':
        'Processing · See Crafting Notes',
    'Obtain it as a chance-based byproduct when an Alchemy Tool successfully completes a recipe.':
        'Alchemy Tool · Extra drop from a successful craft (chance)',
  };
  final known = exact[line];
  if (known != null) return known;
  final drying = RegExp(
    r'^Dry (.+) in the Processing window during clear weather\.$',
  ).firstMatch(line);
  if (drying != null) return 'Dry ${drying[1]} · Clear weather, on land';
  final grow = RegExp(r'^Grow (.+) in a garden\.$').firstMatch(line);
  if (grow != null) return 'Garden · Grow ${grow[1]}';
  final chop = RegExp(r'^Lumber ([A-Za-z ]+ [Tt]rees?)\.$').firstMatch(line);
  if (chop != null) return 'Chop ${chop[1]}';
  const sapTargets = <String>{
    'Acacia Tree',
    'Ash Tree',
    'Birch',
    'Cactus',
    'Caphras Tree',
    'Cedar Trees',
    'Elder Tree',
    'Fir',
    'Loopy Tree',
    'Maple Tree',
    'Moss Tree',
    'Palm Tree',
    'Pine Tree',
    'Snowfield Cedar Tree',
    'Thornwood',
    'Thuja',
    'White Cedar',
  };
  for (final target in sapTargets) {
    if (line == 'Collect it from $target.') {
      return 'Collect from $target (Fluid Collector)';
    }
  }
  final rare = RegExp(r'^Obtain it at a low chance (.+)\.$').firstMatch(line);
  if (rare != null) return 'Rare drop ${rare[1]}';
  return line;
}

String plainItemDescription(String description) => switch (description) {
  'A Trace material used in alchemy and equipment recipes.' =>
    'Used in alchemy and equipment recipes.',
  'A processed Lyngbakr material used for Epheria Carrack and Panokseon equipment.' =>
    'Used for Epheria Carrack and Panokseon equipment. Made from Lyngbakr materials.',
  'A hunting trophy obtained from Griffons.' => 'A hunting drop from Griffons.',
  'A tool consumed by a blacksmith when extracting a crystal from the Crystal Inventory.' =>
    'Lets a blacksmith remove a crystal from the Crystal Inventory. Used up on extraction.',
  _ => description,
};
