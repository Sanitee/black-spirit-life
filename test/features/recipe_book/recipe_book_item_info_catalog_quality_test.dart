import 'dart:io';

import 'package:bdo_craft_planner_flutter/data/catalog/bundled_catalog_parser.dart';
import 'package:bdo_craft_planner_flutter/domain/models/catalog_models.dart';
import 'package:bdo_craft_planner_flutter/domain/models/craft_mode.dart';
import 'package:bdo_craft_planner_flutter/domain/planner/acquisition_recipe_resolution.dart';
import 'package:bdo_craft_planner_flutter/features/recipe_book/recipe_book_item_info.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'every catalog output and ingredient reference has concise useful item info',
    () {
      final snapshot = const BundledCatalogParser().parse(
        File('assets/data/app-data.json').readAsStringSync(),
      );
      final catalogs = <CraftMode, ModeCatalog>{
        CraftMode.alchemy: snapshot.alchemy,
        CraftMode.cooking: snapshot.cooking,
        CraftMode.processing: snapshot.processing,
      };
      final recipesByMode = <CraftMode, Map<String, Recipe>>{
        for (final entry in catalogs.entries) entry.key: entry.value.items,
      };
      final candidates = <String, _CatalogCandidate>{};
      final consumers = <String, List<Recipe>>{};
      final enumerationCounts = <String, int>{
        'outputs': 0,
        'base ingredients': 0,
        'variant ingredients': 0,
        'options': 0,
        'substitutes': 0,
      };
      final failures = <String, Set<String>>{};

      void addFailure(String group, String detail) {
        failures.putIfAbsent(group, () => <String>{}).add(detail);
      }

      void addCandidate({
        required String name,
        required CraftMode mode,
        required String source,
        Recipe? outputRecipe,
        Recipe? consumer,
      }) {
        final trimmed = name.trim();
        if (trimmed.isEmpty) {
          addFailure(
            'enumeration',
            '${mode.key}: blank item name from $source',
          );
          return;
        }
        final folded = _fold(trimmed);
        final candidate = candidates.putIfAbsent(
          folded,
          () => _CatalogCandidate(name: trimmed),
        );
        candidate
          ..modes.add(mode)
          ..sources.add('${mode.key}:$source');
        if (outputRecipe != null) {
          candidate.outputRecipes.add(outputRecipe);
          candidate.isCraftableOutput =
              candidate.isCraftableOutput || outputRecipe.isCraftable;
        }
        if (consumer != null) {
          consumers.putIfAbsent(folded, () => <Recipe>[]).add(consumer);
          candidate.isConsumedByProduction =
              candidate.isConsumedByProduction || consumer.isCraftable;
        }
      }

      void addIngredient({
        required Ingredient ingredient,
        required Recipe consumer,
        required CraftMode mode,
        required String source,
      }) {
        enumerationCounts[source] = enumerationCounts[source]! + 1;
        addCandidate(
          name: ingredient.name,
          mode: mode,
          source: source,
          consumer: consumer,
        );
        for (final option in ingredient.options) {
          enumerationCounts['options'] = enumerationCounts['options']! + 1;
          addCandidate(
            name: option,
            mode: mode,
            source: '$source option',
            consumer: consumer,
          );
        }
        for (final substitute in ingredient.substituteRatios.keys) {
          enumerationCounts['substitutes'] =
              enumerationCounts['substitutes']! + 1;
          addCandidate(
            name: substitute,
            mode: mode,
            source: '$source substitute',
            consumer: consumer,
          );
        }
      }

      for (final catalogEntry in catalogs.entries) {
        final mode = catalogEntry.key;
        for (final recipeEntry in catalogEntry.value.items.entries) {
          final recipe = recipeEntry.value;
          enumerationCounts['outputs'] = enumerationCounts['outputs']! + 1;
          addCandidate(
            name: recipeEntry.key,
            mode: mode,
            source: 'output',
            outputRecipe: recipe,
          );
          for (final ingredient in recipe.ingredients) {
            addIngredient(
              ingredient: ingredient,
              consumer: recipe,
              mode: mode,
              source: 'base ingredients',
            );
          }
          for (final variant in recipe.variants) {
            for (final ingredient in variant.ingredients) {
              addIngredient(
                ingredient: ingredient,
                consumer: recipe,
                mode: mode,
                source: 'variant ingredients',
              );
            }
          }
        }
      }

      for (final requiredSource in enumerationCounts.entries) {
        if (requiredSource.value == 0) {
          addFailure('enumeration', 'No ${requiredSource.key} were exercised.');
        }
      }
      for (final mode in CraftMode.values) {
        if (!candidates.values.any(
          (candidate) => candidate.modes.contains(mode),
        )) {
          addFailure('enumeration', 'No ${mode.key} items were exercised.');
        }
      }

      final processingAliases = <String, String>{
        for (final entry in snapshot.processing.searchAliases.entries)
          _fold(entry.key): entry.value,
      };
      final sortedCandidates = candidates.values.toList(growable: false)
        ..sort((left, right) => _fold(left.name).compareTo(_fold(right.name)));

      for (final candidate in sortedCandidates) {
        final currentMode = candidate.modes.first;
        final resolved = resolveAcquisitionRecipe(
          name: candidate.name,
          currentMode: currentMode,
          recipesByMode: recipesByMode,
        );
        final info = recipeBookInfoFor(
          name: resolved?.name ?? candidate.name,
          recipe: resolved?.recipe,
          searchTerms: <String>[?processingAliases[_fold(candidate.name)]],
          consumerRecipes: consumers[_fold(candidate.name)] ?? const <Recipe>[],
        );
        final context = candidate.context;

        if (info == null) {
          addFailure('empty cards', '${candidate.name} [$context]: null');
          continue;
        }
        if (info.title.trim().isEmpty) {
          addFailure('empty cards', '${candidate.name} [$context]: no title');
        }
        if (info.kind.trim().isEmpty) {
          addFailure('empty cards', '${candidate.name} [$context]: no kind');
        }
        if (!info.hasBody) {
          addFailure('empty cards', '${candidate.name} [$context]: no body');
        }

        final displayedLines = _displayedLines(info);
        for (final line in displayedLines) {
          final banned = _bannedReason(line.text);
          if (banned != null) {
            addFailure(
              'vague or internal copy',
              '${candidate.name} [$context] ${line.section}: '
                  '"${line.text}" ($banned)',
            );
          }
        }

        final requiresPurpose =
            candidate.isCraftableOutput || candidate.isConsumedByProduction;
        final hasVerifiedExplanation =
            _hasUsefulPurpose(info) || info.howToObtain.any(_isSpecificText);
        if (requiresPurpose && !hasVerifiedExplanation) {
          addFailure(
            'missing purpose',
            '${candidate.name} [$context]: craftable output or consumed '
                'ingredient has no verified effect, use, recipe destination, '
                'or acquisition formula',
          );
        }
        if (requiresPurpose) {
          final derived = recipeBookUseDescription(info).trim();
          final banned = _bannedReason(derived);
          if (derived.isNotEmpty &&
              (banned != null || !_isSpecificText(derived))) {
            addFailure(
              'missing purpose',
              '${candidate.name} [$context]: derived description '
                  '"$derived"${banned == null ? '' : ' ($banned)'}',
            );
          }
        }

        for (final craftUse in info.craftUses) {
          if (_fold(craftUse.output) == _fold(candidate.name)) {
            addFailure(
              'self use',
              '${candidate.name} [$context] is listed as its own output',
            );
          }
        }
        for (final duplicate in _obviousDuplicates(info)) {
          addFailure(
            'duplicate information',
            '${candidate.name} [$context]: $duplicate',
          );
        }
      }

      if (failures.isNotEmpty) {
        fail(
          _formatFailures(
            failures,
            candidateCount: candidates.length,
            enumerationCounts: enumerationCounts,
          ),
        );
      }
    },
  );
}

final class _CatalogCandidate {
  _CatalogCandidate({required this.name});

  final String name;
  final Set<CraftMode> modes = <CraftMode>{};
  final Set<String> sources = <String>{};
  final List<Recipe> outputRecipes = <Recipe>[];
  bool isCraftableOutput = false;
  bool isConsumedByProduction = false;

  String get context {
    final roles = <String>[
      if (outputRecipes.isNotEmpty) 'output',
      if (isCraftableOutput) 'craftable',
      if (isConsumedByProduction) 'consumed',
      ...sources.where(
        (source) =>
            source.contains('variant') ||
            source.contains('option') ||
            source.contains('substitute'),
      ),
    ];
    return roles.toSet().join(', ');
  }
}

final class _InfoLine {
  const _InfoLine(this.section, this.text);

  final String section;
  final String text;
}

List<_InfoLine> _displayedLines(RecipeBookItemInfo info) => <_InfoLine>[
  if (info.summary.trim().isNotEmpty)
    _InfoLine('description', info.summary.trim()),
  for (final effect in info.effects)
    if (effect.trim().isNotEmpty) _InfoLine('effects', effect.trim()),
  for (final use in info.uses)
    if (use.trim().isNotEmpty) _InfoLine('used for', use.trim()),
  for (final craftUse in info.craftUses)
    for (final recipe in craftUse.recipes)
      if (recipe.trim().isNotEmpty)
        _InfoLine('used for ${craftUse.output}', recipe.trim()),
  for (final route in info.howToObtain)
    if (route.trim().isNotEmpty) _InfoLine('how to obtain', route.trim()),
  if (info.example?.trim().isNotEmpty ?? false)
    _InfoLine('example', info.example!.trim()),
  for (final note in info.notes)
    if (note.trim().isNotEmpty) _InfoLine('notes', note.trim()),
];

String? _bannedReason(String value) {
  final folded = _fold(value);
  if (folded.isEmpty) return null;

  const bannedFragments = <String, String>{
    'basic recipe material': 'generic fallback',
    'gear progression material': 'generic fallback',
    'gear crystal or crystal material': 'ambiguous item type',
    'relevant to': 'search-alias-derived wording',
    'related to:': 'search-alias-derived wording',
    'shows here because': 'search-result explanation',
    'appears near': 'search-result explanation',
    'easy to mix up by name': 'search-result explanation',
    'reliable acquisition details have not been added':
        'unfinished acquisition copy',
    'imported from': 'import provenance',
    'bdolytics': 'import provenance',
    'bdo codex': 'research provenance',
    'buff focus:': 'placeholder effect',
    'crystal focus:': 'placeholder effect',
    'lightstone focus:': 'placeholder effect',
    'material focus:': 'placeholder effect',
    'used in some ': 'unspecific purpose',
    'specialized essence variance': 'unexplained jargon',
    'specialized essence variant': 'unexplained jargon',
    "planner's recipe catalog": 'internal catalog fallback',
    'matching gear system': 'name-derived enhancement guess',
    'matching enhancement system': 'category-derived enhancement guess',
    'matching gear enhancement or reform path':
        'category-derived enhancement guess',
    'component used in crystal or lightstone crafting':
        'name-derived crystal guess',
    'processed textile or leather material': 'name-derived textile guess',
    'processed gemstone': 'name-derived gemstone guess',
  };
  for (final entry in bannedFragments.entries) {
    if (folded.contains(entry.key)) return entry.value;
  }
  if (RegExp(r'\bunknown\b', caseSensitive: false).hasMatch(value)) {
    return 'unknown placeholder';
  }
  if (RegExp(r'\betc\.', caseSensitive: false).hasMatch(value)) {
    return 'open-ended list';
  }

  final sentence = _semanticText(value);
  const genericSentences = <String, String>{
    'crafting material': 'generic fallback',
    'processed crafting material': 'generic fallback',
    'material used for gear progression': 'generic fallback',
    'recipe material': 'generic fallback',
  };
  return genericSentences[sentence];
}

bool _hasUsefulPurpose(RecipeBookItemInfo info) {
  if (info.effects.any(_isSpecificText)) return true;
  if (info.uses.any(_isSpecificText)) return true;
  if (info.craftUses.any(
    (use) => use.output.trim().isNotEmpty && use.recipes.any(_isSpecificText),
  )) {
    return true;
  }
  return _isSpecificText(info.summary) && _bannedReason(info.summary) == null;
}

bool _isSpecificText(String value) {
  final semantic = _semanticText(value);
  if (semantic.length < 10) return false;
  const generic = <String>{
    'alchemy item',
    'alchemy material',
    'blood material',
    'cooking material',
    'crystal material',
    'dish',
    'enhancement material',
    'gathered crafting material',
    'gathering material',
    'gear material',
    'lightstone material',
    'processing material',
    'recipe material',
    'wood material',
  };
  return !generic.contains(semantic);
}

List<String> _obviousDuplicates(RecipeBookItemInfo info) {
  final failures = <String>[];
  for (final use in info.uses) {
    if (_samePurposeMeaning(info.summary, use)) {
      failures.add('used for repeats description: "${use.trim()}"');
    }
  }
  final seenLines = <String, String>{};
  final nonCraftLines = <_InfoLine>[
    if (info.summary.trim().isNotEmpty) _InfoLine('description', info.summary),
    for (final value in info.effects) _InfoLine('effects', value),
    for (final value in info.uses) _InfoLine('used for', value),
    for (final value in info.howToObtain) _InfoLine('how to obtain', value),
    if (info.example?.trim().isNotEmpty ?? false)
      _InfoLine('example', info.example!),
    for (final value in info.notes) _InfoLine('notes', value),
  ];
  for (final line in nonCraftLines) {
    final normalized = _semanticText(line.text);
    if (normalized.isEmpty) continue;
    final previous = seenLines[normalized];
    if (previous != null) {
      failures.add('${line.section} repeats $previous: "${line.text.trim()}"');
    } else {
      seenLines[normalized] = line.section;
    }
  }

  final seenOutputs = <String>{};
  for (final craftUse in info.craftUses) {
    final output = _fold(craftUse.output);
    if (output.isEmpty) continue;
    if (!seenOutputs.add(output)) {
      failures.add('Used For repeats output "${craftUse.output}"');
    }
    final seenRecipes = <String>{};
    for (final recipe in craftUse.recipes) {
      final normalized = _semanticText(recipe);
      if (normalized.isNotEmpty && !seenRecipes.add(normalized)) {
        failures.add(
          'Used For ${craftUse.output} repeats recipe "${recipe.trim()}"',
        );
      }
    }
    for (final use in info.uses) {
      if (_isObviousDuplicateUse(use, craftUse.output)) {
        failures.add(
          'explicit use "${use.trim()}" repeats recipe output '
          '"${craftUse.output}"',
        );
      }
    }
  }
  return failures;
}

bool _samePurposeMeaning(String left, String right) {
  final leftTerms = _purposeTerms(left);
  final rightTerms = _purposeTerms(right);
  return rightTerms.length >= 3 && leftTerms.containsAll(rightTerms);
}

Set<String> _purposeTerms(String value) {
  const ignored = <String>{
    'a',
    'an',
    'and',
    'another',
    'for',
    'from',
    'in',
    'into',
    'is',
    'it',
    'its',
    'listed',
    'named',
    'of',
    'on',
    'one',
    'same',
    'the',
    'this',
    'through',
    'to',
    'use',
    'used',
    'uses',
    'with',
  };
  return _fold(value)
      .split(RegExp(r'[^a-z0-9]+'))
      .where((term) => term.isNotEmpty && !ignored.contains(term))
      .map((term) {
        if (term.startsWith('enhanc')) return 'enhance';
        if (term.startsWith('equip')) return 'equip';
        if (term.startsWith('craft')) return 'craft';
        if (term.startsWith('infus')) return 'infuse';
        if (term.startsWith('appl')) return 'apply';
        if (term.startsWith('consum')) return 'consume';
        if (term.length > 4 && term.endsWith('s')) {
          return term.substring(0, term.length - 1);
        }
        return term;
      })
      .toSet();
}

bool _isObviousDuplicateUse(String use, String output) {
  var normalized = _semanticText(use);
  final normalizedOutput = _semanticText(output);
  for (final prefix in <RegExp>[
    RegExp(r'^used to (?:make|craft|create|produce|process into) '),
    RegExp(r'^used for (?:making|crafting|creating|producing) '),
    RegExp(r'^(?:makes|crafts|creates|produces|processes into) '),
  ]) {
    normalized = normalized.replaceFirst(prefix, '');
  }
  return normalized == normalizedOutput ||
      normalized == 'the $normalizedOutput';
}

String _formatFailures(
  Map<String, Set<String>> failures, {
  required int candidateCount,
  required Map<String, int> enumerationCounts,
}) {
  const exampleLimit = 35;
  final buffer = StringBuffer()
    ..writeln(
      'Recipe Book item-info catalog quality failed for '
      '$candidateCount unique reachable names.',
    )
    ..writeln(
      'Enumerated: ${enumerationCounts.entries.map((entry) => '${entry.key}=${entry.value}').join(', ')}.',
    );
  final groups = failures.keys.toList()..sort();
  for (final group in groups) {
    final entries = failures[group]!.toList()..sort();
    buffer
      ..writeln()
      ..writeln('$group (${entries.length})');
    for (final entry in entries.take(exampleLimit)) {
      buffer.writeln('  - $entry');
    }
    if (entries.length > exampleLimit) {
      buffer.writeln('  - ... ${entries.length - exampleLimit} more');
    }
  }
  return buffer.toString();
}

String _semanticText(String value) => _fold(value)
    .replaceAll(RegExp(r'^[\s\u2022\-]+'), '')
    .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();

String _fold(String value) =>
    value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
