import 'dart:convert';
import 'dart:io';

import 'package:bdo_craft_planner_flutter/app/planning/planner_assembly.dart';
import 'package:bdo_craft_planner_flutter/data/catalog/bundled_catalog_parser.dart';
import 'package:bdo_craft_planner_flutter/domain/models/catalog_models.dart';
import 'package:bdo_craft_planner_flutter/domain/models/craft_mode.dart';
import 'package:bdo_craft_planner_flutter/domain/planner/acquisition_recipe_resolution.dart';
import 'package:bdo_craft_planner_flutter/domain/planner/item_acquisition_resolution.dart';
import 'package:bdo_craft_planner_flutter/domain/planner/planner_models.dart';
import 'package:bdo_craft_planner_flutter/domain/planner/source_resolution.dart';
import 'package:bdo_craft_planner_flutter/domain/state/planner_state.dart';
import 'package:bdo_craft_planner_flutter/domain/state/user_source_notes.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const assembly = PlannerAssembly();
  late Map<String, Object?> rawCatalog;
  late CatalogSnapshot catalog;
  late PlannerRules rules;
  late Map<CraftMode, Map<String, Recipe>> recipesByMode;

  setUpAll(() {
    final source = File('assets/data/app-data.json').readAsStringSync();
    rawCatalog = _objectMap(jsonDecode(source));
    catalog = const BundledCatalogParser().parse(source);
    rules = assembly.plannerRules(catalog.supportingData);
    recipesByMode = <CraftMode, Map<String, Recipe>>{
      for (final mode in CraftMode.values)
        mode: assembly.assembleRecipes(
          catalog: catalog.forMode(mode),
          state: _defaultModeState(mode),
          supportingData: catalog.supportingData,
          sharedMetadata: catalog.alchemy.metadata,
          mode: mode,
        ),
    };
  });

  test('every acquisition entry is reviewed and cites two valid sources', () {
    final acquisitionInfo = _objectMap(rawCatalog['acquisitionInfo']);
    expect(
      acquisitionInfo,
      isNotEmpty,
      reason: 'The production catalog must contain reviewed acquisition data.',
    );

    final failures = <String>[];
    for (final entry in acquisitionInfo.entries) {
      final item = _objectMap(entry.value);
      if (_text(item['status']).toLowerCase() != 'reviewed') {
        failures.add('${entry.key}: status is not reviewed');
      }
      final routes = _list(item['routes']);
      if (routes.isEmpty) {
        failures.add('${entry.key}: has no acquisition routes');
        continue;
      }
      for (var index = 0; index < routes.length; index++) {
        final route = _objectMap(routes[index]);
        final routeLabel = '${entry.key}: route ${index + 1}';
        if (_text(route['summary']).isEmpty) {
          failures.add('$routeLabel has no summary');
        }
        final sources = _list(route['sources']);
        final validSources = sources.where(_isValidResearchSource).length;
        if (validSources < 2) {
          failures.add(
            '$routeLabel has $validSources valid sources; at least 2 required',
          );
        }
        if (sources.any((source) => !_isValidResearchSource(source))) {
          failures.add('$routeLabel contains an invalid source record');
        }
      }
    }

    expect(
      failures,
      isEmpty,
      reason: failures.isEmpty
          ? null
          : 'Acquisition research validation failed:\n'
                '${failures.join('\n')}',
    );
  });

  test('every reachable bundled queue ingredient has a user-facing route', () {
    final reachable = <String>{};
    for (final recipes in recipesByMode.values) {
      for (final recipe in recipes.values.where(
        (candidate) => candidate.isCraftable,
      )) {
        for (final ingredient in recipe.ingredients) {
          _addName(reachable, ingredient.name);
          for (final option in ingredient.options) {
            _addName(reachable, option);
          }
          for (final option in ingredient.substituteRatios.keys) {
            _addName(reachable, option);
          }
        }
      }
    }

    final uncovered = <String>[];
    for (final name in reachable) {
      final recipe = resolveAcquisitionRecipe(
        name: name,
        currentMode: CraftMode.alchemy,
        recipesByMode: recipesByMode,
      );
      if (recipe?.recipe.isCraftable ?? false) continue;

      final acquisition = resolveItemAcquisition(name: name, rules: rules);
      if (acquisition?.displayableSummaries.isNotEmpty ?? false) continue;

      var hasVendorOrNpcRoute = false;
      var hasDisplayableSourceNote = false;
      for (final candidate in _recipesNamed(recipesByMode, name)) {
        final source = resolveSourceInfo(
          name: name,
          recipe: candidate,
          rules: rules,
        );
        hasVendorOrNpcRoute =
            hasVendorOrNpcRoute || _hasVendorOrNpcRoute(source);
        hasDisplayableSourceNote =
            hasDisplayableSourceNote ||
            sanitizeDisplayableSourceNote(source.sourceNote) != null;
      }
      if (!hasVendorOrNpcRoute && !hasDisplayableSourceNote) {
        final vendorFallback = resolveSourceInfo(
          name: name,
          recipe: null,
          rules: rules,
        );
        hasVendorOrNpcRoute = _hasVendorOrNpcRoute(vendorFallback);
      }
      if (!hasVendorOrNpcRoute && !hasDisplayableSourceNote) {
        uncovered.add(name);
      }
    }
    uncovered.sort(_compareNames);

    expect(reachable, isNotEmpty);
    expect(
      uncovered,
      isEmpty,
      reason: uncovered.isEmpty
          ? null
          : 'Reachable queue ingredients without a craft recipe, reviewed '
                'acquisition route, vendor/NPC route, or sanitized '
                'user-facing source note:\n${uncovered.join('\n')}',
    );
  });

  test("Sea Monster's Ooze names its established sea-monster sources", () {
    final acquisition = resolveItemAcquisition(
      name: "Sea Monster's Ooze",
      rules: rules,
    );
    final guidance =
        acquisition?.displayableSummaries.join(' ').toLowerCase() ?? '';

    expect(acquisition?.status, 'reviewed');
    expect(guidance, contains('hekaru'));
    expect(guidance, contains('ocean stalker'));
  });

  test('Crystallized Energy of Endtimes uses practical acquisition routes '
      'instead of HAN Dawn Crystal salvage', () {
    const name = 'Crystallized Energy of Endtimes';
    final recipe = catalog.processing.items[name];
    expect(recipe, isNotNull);
    expect(recipe?.role, RecipeRole.salvage);
    expect(recipe?.isCraftable, isFalse);

    final result = assembly.build(
      catalog: catalog,
      mode: CraftMode.processing,
      state: _defaultModeState(CraftMode.processing),
      targetOverride: name,
      wantOverride: 13000,
    );

    expect(result.steps.where((step) => step.name == name), isEmpty);
    expect(
      result.steps
          .expand((step) => step.ingredients)
          .map((ingredient) => ingredient.name),
      isNot(contains(startsWith('HAN Dawn Crystal'))),
    );
    expect(result.missing, hasLength(1));
    expect(result.missing.single.name, name);
    expect(result.missing.single.need, 13000);

    final acquisition = resolveItemAcquisition(name: name, rules: rules);
    final guidance =
        acquisition?.displayableSummaries.join(' ').toLowerCase() ?? '';
    expect(acquisition?.status, 'reviewed');
    expect(guidance, contains('central market'));
    expect(guidance, contains('nymphamar'));
    expect(guidance, contains('orbita'));
    expect(guidance, contains('tenebraum'));
    expect(guidance, contains('zephyros'));
    expect(guidance, contains('for the throne'));
    expect(guidance, contains('purify'));
    expect(guidance, isNot(contains('aetherion')));
    expect(guidance, isNot(contains('han dawn crystal')));
    expect(guidance, isNot(contains('heat')));
  });

  test('practical production formulas replace importer-selected recovery '
      'variants', () {
    final recipes = catalog.processing.items;

    final flax = recipes['Flax Fabric']!;
    expect(flax.role, RecipeRole.production);
    expect(flax.method, 'Grinding');
    expect(flax.baseOutput, 1);
    expect(flax.outputMinimum, 1);
    expect(flax.outputMaximum, 4);
    expect(_ingredientQuantities(flax), const <String, double>{
      'Flax Thread': 10,
    });
    expect(
      _references(flax).where(
        (name) =>
            name.contains('Fortuna') ||
            name.contains('Hercules') ||
            name.contains('Heve'),
      ),
      isEmpty,
    );

    final concentrated = recipes['Concentrated Magical Black Stone']!;
    expect(concentrated.role, RecipeRole.production);
    expect(concentrated.baseOutput, 0.4);
    expect(concentrated.outputMinimum, 1);
    expect(concentrated.outputMaximum, 1);
    expect(_ingredientQuantities(concentrated), const <String, double>{
      'Sharp Black Crystal Shard': 1,
      'Black Stone': 2,
    });
    expect(
      _references(concentrated).where((name) => name.contains('Reform Stone')),
      isEmpty,
    );

    final blackStonePowder = recipes['Black Stone Powder']!;
    expect(blackStonePowder.role, RecipeRole.production);
    expect(blackStonePowder.method, 'Grinding');
    expect(blackStonePowder.baseOutput, 32);
    expect(blackStonePowder.outputMinimum, 60);
    expect(blackStonePowder.outputMaximum, 100);
    expect(_ingredientQuantities(blackStonePowder), const <String, double>{
      'Black Stone': 1,
    });
    expect(
      _references(blackStonePowder).where((name) => name.contains('Crystal')),
      isEmpty,
    );

    final magicalShard = recipes['Magical Shard']!;
    expect(magicalShard.role, RecipeRole.production);
    expect(magicalShard.method, 'Heating');
    expect(magicalShard.ingredients, hasLength(1));
    expect(magicalShard.ingredients.single.name, 'Sealed Black Magic Crystal');
    expect(
      magicalShard.ingredients.single.options.first,
      'Sealed Black Magic Crystal',
    );
    expect(
      magicalShard.ingredients.single.options,
      contains('Black Magic Crystal - Precision'),
    );

    for (final entry in const <String, String>{
      "Khan's Heart: Destruction": 'Destruction Spirit Stone',
      "Khan's Heart: Life": 'Life Spirit Stone',
      "Khan's Heart: Protection": 'Guardian Spirit Stone',
    }.entries) {
      final heart = recipes[entry.key]!;
      expect(heart.role, RecipeRole.production);
      expect(heart.baseOutput, 0.4);
      expect(heart.outputMinimum, 1);
      expect(heart.outputMaximum, 1);
      expect(_ingredientQuantities(heart), <String, double>{
        'Magical Shard': 200,
        'Trace of Nature': 100,
        'Alchemy Stone Shard': 400,
        "Khan's Concentrated Magic": 1,
        entry.value: 1,
      });
      expect(
        _references(heart).where(
          (name) =>
              name.startsWith('Resplendent Khan') ||
              name.startsWith('Splendid Khan') ||
              name.startsWith('Shining Khan'),
        ),
        isEmpty,
      );
    }

    final alchemyShards = recipes['Alchemy Stone Shard']!;
    expect(alchemyShards.role, RecipeRole.production);
    expect(alchemyShards.ingredients, hasLength(1));
    expect(alchemyShards.ingredients.single.options, const <String>[
      'Imperfect Alchemy Stone of Destruction',
      'Imperfect Alchemy Stone of Protection',
      'Imperfect Alchemy Stone of Life',
    ]);
    expect(
      _references(
        alchemyShards,
      ).where((name) => name.startsWith('Shining Alchemy Stone')),
      isEmpty,
    );
  });

  test('legacy materials are removed from current recipes and market '
      'identity', () {
    const legacy = 'Concentrated Magical Black Stone (Armor)';
    final references = catalog.processing.items.values
        .expand(_references)
        .toList(growable: false);
    expect(references.where((name) => name == legacy), isEmpty);
    expect(
      references.where((name) => name == 'Concentrated Magical Black Stone'),
      hasLength(65),
    );

    final marketIds = _objectMap(catalog.supportingData['marketIds']);
    for (final name in const <String>[
      'Black Stone (Armor)',
      'Hard Black Crystal Shard',
      legacy,
      'Trace of Despair',
    ]) {
      expect(catalog.processing.items[name]?.isReferenceOnly, isTrue);
      expect(catalog.processing.items[name]?.marketId, isNull);
      expect(marketIds, isNot(contains(name)));
    }
  });

  test('reference-only conversions remain missing and never consume expensive '
      'finished items', () {
    for (final name in const <String>[
      'Essence of Dawn',
      'Essence of Dawn - Damage Reduction',
      'Mass of Pure Magic',
      'Purified Lightstone',
      'Oquilla Earth Crystal',
      'Oquilla Sky Crystal',
      'Piece of Edana',
      "Kydict's Heirloom",
    ]) {
      final recipe = catalog.processing.items[name]!;
      expect(recipe.isReferenceOnly, isTrue, reason: name);
      expect(recipe.isCraftable, isFalse, reason: name);

      final result = assembly.build(
        catalog: catalog,
        mode: CraftMode.processing,
        state: _defaultModeState(CraftMode.processing),
        targetOverride: name,
        wantOverride: 1,
      );
      expect(result.steps, isEmpty, reason: name);
      expect(result.missing, hasLength(1), reason: name);
      expect(result.missing.single.name, name);
      expect(result.missing.single.need, 1);
    }
  });

  test('every practical reference route has reviewed concise guidance', () {
    for (final name in const <String>[
      'Memory Fragment',
      'Mass of Pure Magic',
      'Purified Lightstone',
      'Essence of Dawn',
      'Essence of Dawn - Accuracy',
      "Essence of Dawn - Black Spirit's Rage",
      'Essence of Dawn - Damage Reduction',
      'Essence of Dawn - Evasion',
      'Oquilla Sky Crystal',
      'Oquilla Earth Crystal',
      'Flame of the Primordial',
      'Piece of Edana',
      "Kydict's Heirloom",
      'Ancient Spirit Dust',
      'Sharp Black Crystal Shard',
      'Fragment of All Creations',
      'Melody of the Stars',
      'Trace of Despair',
      'Translucent Crystal',
      'Violet Crystal',
      'Origin of Eltro',
      'Origin of Margoria',
      'Origin of Rusalka',
      'Origin of Serni',
      'Legacy of the Ancient',
      'Alchemy Stone Shard',
      'Black Gem Fragment',
      'Embers of the Primordial',
    ]) {
      final acquisition = resolveItemAcquisition(name: name, rules: rules);
      expect(acquisition?.status, 'reviewed', reason: name);
      expect(
        acquisition?.displayableSummaries,
        isNotEmpty,
        reason: '$name needs a practical route',
      );
    }

    String guidance(String name) => resolveItemAcquisition(
      name: name,
      rules: rules,
    )!.displayableSummaries.join(' ').toLowerCase();

    expect(guidance('Essence of Dawn'), contains('black shrine'));
    expect(guidance('Essence of Dawn'), isNot(contains('dawn crystal')));
    expect(guidance('Mass of Pure Magic'), contains('manage currency'));
    expect(
      guidance('Mass of Pure Magic'),
      isNot(contains('grind black stone')),
    );
    expect(guidance('Oquilla Earth Crystal'), contains('jetina'));
    expect(guidance('Oquilla Earth Crystal'), isNot(contains('reform stone')));
    expect(guidance('Flame of the Primordial'), contains('100 embers'));
    expect(
      guidance('Flame of the Primordial'),
      isNot(contains('primordial glow')),
    );
    expect(guidance('Embers of the Primordial'), contains('world boss'));
    expect(guidance('Black Gem Fragment'), contains('gathering'));
    expect(
      guidance('Black Gem Fragment'),
      contains('manual reference choices'),
    );
    expect(guidance('Piece of Edana'), contains('for the throne'));
    expect(guidance('Piece of Edana'), isNot(contains("edana's black stone")));
    expect(guidance('Ancient Spirit Dust'), contains('gathering'));
    expect(
      guidance('Ancient Spirit Dust'),
      contains('leaves that conversion manual'),
    );
    expect(guidance('Ancient Spirit Dust'), isNot(contains('central market')));
    expect(guidance('Black Stone Powder'), contains('grind black stone'));
    expect(guidance('Black Stone Powder'), contains('central market'));
    expect(guidance('Magical Shard'), contains('sealed black magic crystal'));
    expect(guidance('Trace of Despair'), contains('legacy'));
    expect(guidance('Trace of Despair'), contains('trace of nature'));
    expect(guidance('Trace of Despair'), isNot(contains('central market')));
  });

  test('automatic destructive conversions expose only reviewed low-cost '
      'inputs', () {
    final fragment = catalog.processing.items['Fragment of All Creations']!;
    expect(fragment.role, RecipeRole.production);
    expect(fragment.isCraftable, isTrue);
    expect(fragment.ingredients, hasLength(1));
    expect(fragment.ingredients.single.name, "Sicil's Necklace");
    expect(fragment.ingredients.single.options, const <String>[
      "Sicil's Necklace",
      'Forest Ronaros Ring',
      "Serap's Necklace",
      'Ring of Crescent Guardian',
      "Basilisk's Belt",
      'Eye of the Ruins Ring',
      'Narc Ear Accessory',
      "Orkinrad's Belt",
      'Valtarra Eclipsed Belt',
    ]);
    expect(
      fragment.ingredients.single.options,
      isNot(
        contains(
          anyOf(
            'Deboreka Necklace',
            'Dawn Earring',
            'Black Distortion Earring',
            'Tungrad Necklace',
            "Turo's Belt",
          ),
        ),
      ),
    );

    final legacy = catalog.processing.items['Legacy of the Ancient']!;
    expect(legacy.role, RecipeRole.production);
    expect(legacy.isCraftable, isTrue);
    expect(legacy.ingredients.single.options, const <String>[
      'Combined Magic Crystal - Gervish',
      'Combined Magic Crystal - Hoom',
    ]);
    expect(
      legacy.ingredients.single.options,
      isNot(contains('Combined Magic Crystal - Macalod')),
    );

    for (final entry in <String, String>{
      'Fragment of All Creations': "Sicil's Necklace",
      'Legacy of the Ancient': 'Combined Magic Crystal - Gervish',
    }.entries) {
      final result = assembly.build(
        catalog: catalog,
        mode: CraftMode.processing,
        state: _defaultModeState(CraftMode.processing),
        targetOverride: entry.key,
        wantOverride: 1,
      );
      expect(
        result.steps.map((step) => step.name),
        contains(entry.key),
        reason: entry.key,
      );
      expect(result.missing, hasLength(1), reason: entry.key);
      expect(result.missing.single.name, entry.value, reason: entry.key);
      expect(result.missing.single.need, 1, reason: entry.key);
    }
  });

  test('automatic recipe graphs contain no self-loop or production cycle', () {
    final failures = <String>[];
    for (final entry in recipesByMode.entries) {
      for (final cycle in _productionCycles(entry.value)) {
        failures.add('${entry.key.key}: ${cycle.join(' -> ')}');
      }
    }
    expect(
      failures,
      isEmpty,
      reason: failures.isEmpty
          ? null
          : 'Automatic acquisition cycles remain:\n${failures.join('\n')}',
    );
  });

  test('previously vague acquisition routes are now actionable', () {
    final acquisitionInfo = _objectMap(rawCatalog['acquisitionInfo']);

    String guidanceFor(String name) =>
        _list(_objectMap(acquisitionInfo[name])['routes'])
            .map(_objectMap)
            .map((route) => _text(route['summary']))
            .join(' ')
            .toLowerCase();

    expect(guidanceFor('Energy Potion (Extra Large)'), contains('200 energy'));
    expect(guidanceFor('Blue Reagent'), contains('material vendor'));
    expect(guidanceFor('Blue Reagent'), isNot(contains('npc vendor')));
    expect(guidanceFor('Fire Horn'), contains('animal carcasses'));
    expect(
      guidanceFor('Black Spirit Crystal'),
      contains('awakened black spirit'),
    );
    expect(
      guidanceFor("Valtarra Spirit's Crystal"),
      contains('scarlet stigma'),
    );
    expect(
      guidanceFor('Distorted Fragment of Origin'),
      allOf(contains('aetherion castle'), contains('zephyros castle')),
    );
    expect(
      guidanceFor('Silent Fragment of Origin'),
      allOf(contains('nymphamaré castle'), contains('tenebraum castle')),
    );
    expect(
      guidanceFor('Rusalka Sea Crystal'),
      allOf(contains('right-click'), contains('simple alchemy')),
    );

    final allGuidance = acquisitionInfo.values
        .expand(
          (entry) => _list(
            _objectMap(entry)['routes'],
          ).map(_objectMap).map((route) => _text(route['summary'])),
        )
        .join('\n')
        .toLowerCase();
    for (final stalePhrase in <String>[
      'reliable acquisition details have not been added',
      'talk to npc alustin or dalishain',
      'butchering or tanning.',
      'use rusalka crystals.',
      'complete the relevant black spirit quest',
      'defeat certain monsters or content',
    ]) {
      expect(allGuidance, isNot(contains(stalePhrase)));
    }
  });

  test('Elixir of Life uses the corrected production ingredients', () {
    final recipe = catalog.alchemy.items['Elixir of Life'];
    expect(recipe, isNotNull);
    final quantities = <String, double>{
      for (final ingredient in recipe!.ingredients)
        ingredient.name: ingredient.quantity,
    };

    expect(quantities['Pure Powder Reagent'], 1);
    expect(quantities['HP Potion (Small)'], 3);
    expect(quantities['Silver Azalea'], 3);
    expect(quantities['Fox Blood'], 5);
    expect(quantities, isNot(contains('HP Pot')));
    expect(quantities, isNot(contains('Marmot Blood')));
  });
}

ModeState _defaultModeState(CraftMode mode) => ModeState(
  target: '',
  bonusTarget: '',
  market: MarketState(),
  appearance: AppearanceSettings.defaultsFor(mode),
);

Iterable<Recipe?> _recipesNamed(
  Map<CraftMode, Map<String, Recipe>> recipesByMode,
  String name,
) sync* {
  final folded = _fold(name);
  for (final recipes in recipesByMode.values) {
    final exact = recipes[name];
    if (exact != null) {
      yield exact;
      continue;
    }
    for (final entry in recipes.entries) {
      if (_fold(entry.key) == folded) {
        yield entry.value;
        break;
      }
    }
  }
}

bool _hasVendorOrNpcRoute(ResolvedSourceInfo source) =>
    _hasText(source.vendor) || _hasText(source.location) || source.npcPrice > 0;

bool _isValidResearchSource(Object? value) {
  final source = _objectMap(value);
  final title = _text(source['title']);
  final url = _text(source['url']);
  final uri = Uri.tryParse(url);
  final supports = _list(
    source['supports'],
  ).map(_text).where((item) => item.isNotEmpty);
  return title.isNotEmpty &&
      uri != null &&
      (uri.scheme == 'https' || uri.scheme == 'http') &&
      uri.host.isNotEmpty &&
      supports.isNotEmpty;
}

Map<String, Object?> _objectMap(Object? value) {
  if (value is! Map) return const <String, Object?>{};
  return value.map((key, item) => MapEntry(key.toString(), item));
}

List<Object?> _list(Object? value) =>
    value is List ? List<Object?>.from(value) : const <Object?>[];

String _text(Object? value) => value?.toString().trim() ?? '';

bool _hasText(String? value) => value?.trim().isNotEmpty ?? false;

void _addName(Set<String> names, String value) {
  final name = value.trim();
  if (name.isNotEmpty) names.add(name);
}

String _fold(String value) =>
    value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

int _compareNames(String left, String right) =>
    left.toLowerCase().compareTo(right.toLowerCase());

Map<String, double> _ingredientQuantities(Recipe recipe) => <String, double>{
  for (final ingredient in recipe.ingredients)
    ingredient.name: ingredient.quantity,
};

Iterable<String> _references(Recipe recipe) sync* {
  for (final ingredient in recipe.ingredients) {
    yield ingredient.name;
    yield* ingredient.options;
    yield* ingredient.substituteRatios.keys;
  }
}

List<List<String>> _productionCycles(Map<String, Recipe> recipes) {
  final canonical = <String, String>{
    for (final name in recipes.keys) _fold(name): name,
  };
  final graph = <String, Set<String>>{
    for (final entry in recipes.entries)
      if (entry.value.isCraftable)
        entry.key: {
          for (final reference in _references(entry.value))
            if (canonical[_fold(reference)] case final target?
                when recipes[target]?.isCraftable ?? false)
              target,
        },
  };
  final state = <String, int>{};
  final stack = <String>[];
  final cycles = <List<String>>[];
  final seenCycles = <String>{};

  void visit(String name) {
    state[name] = 1;
    stack.add(name);
    for (final next in graph[name] ?? const <String>{}) {
      if (state[next] == 1) {
        final start = stack.indexOf(next);
        final cycle = <String>[...stack.sublist(start), next];
        final key = cycle.map(_fold).join(' -> ');
        if (seenCycles.add(key)) cycles.add(cycle);
      } else if (state[next] != 2) {
        visit(next);
      }
    }
    stack.removeLast();
    state[name] = 2;
  }

  for (final name in graph.keys) {
    if (state[name] == null) visit(name);
  }
  return cycles;
}
