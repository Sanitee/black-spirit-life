// Narrow audited substitution migration: retain EXP only when all other
// formula fields match the captured baseline. Never add a name-only fallback.
import 'dart:convert';
import 'dart:io';
import 'package:bdo_craft_planner_flutter/app/planning/planner_assembly.dart';
import 'package:bdo_craft_planner_flutter/data/catalog/bundled_catalog_parser.dart';
import 'package:bdo_craft_planner_flutter/domain/models/catalog_models.dart';
import 'package:bdo_craft_planner_flutter/domain/models/craft_mode.dart';
import 'package:bdo_craft_planner_flutter/domain/opportunities/recipe_experience.dart';
import 'package:bdo_craft_planner_flutter/domain/state/planner_state.dart';

Map<String, Object?> shape(Recipe r) => {
  'name': r.name,
  'type': r.type,
  'method': r.method,
  'id': r.marketId,
  'baseOutput': r.baseOutput,
  'min': r.outputMinimum,
  'max': r.outputMaximum,
  'ingredients': [
    for (final i in r.ingredients)
      {
        'name': i.name,
        'quantity': i.quantity,
        'options': i.options,
        'group': i.substituteGroup,
        'ratios': i.substituteRatios,
      },
  ],
};
void main(List<String> args) {
  if (args.length != 3 || !['capture', 'verify'].contains(args[0])) {
    throw ArgumentError('capture/verify, exact evidence file, mapping file');
  }
  final mapping =
      jsonDecode(File(args[2]).readAsStringSync()) as Map<String, dynamic>;
  final names = (mapping['candidates'] as List)
      .cast<Map<String, dynamic>>()
      .map((r) => r['name'] as String)
      .toSet();
  final catalog = const BundledCatalogParser().parse(
    File('assets/data/app-data.json').readAsStringSync(),
  );
  final assembled = const PlannerAssembly().assembleRecipes(
    catalog: catalog.processing,
    state: ModeState(
      target: '',
      bonusTarget: '',
      market: MarketState(),
      appearance: AppearanceSettings.defaultsFor(CraftMode.processing),
    ),
    supportingData: catalog.supportingData,
    sharedMetadata: catalog.alchemy.metadata,
    mode: CraftMode.processing,
    processingRecipes: catalog.processing.items,
  );
  final current = <String, Recipe>{};
  for (final source in {
    'raw': catalog.processing.items,
    'assembled': assembled,
  }.entries) {
    for (final name in names) {
      final recipe = source.value[name]!;
      current['${source.key}|$name|base'] = recipe;
      for (final v in recipe.variants) {
        current['${source.key}|$name|${v.id}'] = recipe.resolveVariant(v.id);
      }
    }
  }
  if (args[0] == 'capture') {
    final file = File(args[1]);
    if (file.existsSync()) {
      throw StateError('Do not overwrite baseline evidence');
    }
    file.writeAsStringSync(
      '${const JsonEncoder.withIndent('  ').convert({
        'catalog': catalog.sourceSha256,
        'rows': {
          for (final e in current.entries) e.key: {
              'shape': shape(e.value),
              'signature': recipeExperienceSignature(e.value),
              'experience': switch (experienceFor(e.value, CraftMode.processing)) {
                final RecipeExperience x => {'value': x.value, 'estimated': x.estimated, 'skill': x.skill, 'source': x.sourceReference},
                _ => null,
              },
            },
        },
      })}\n',
    );
    stdout.writeln('Captured ${current.length} formula views.');
    return;
  }
  final baseline =
      jsonDecode(File(args[1]).readAsStringSync()) as Map<String, dynamic>;
  final rows = baseline['rows'] as Map<String, dynamic>;
  var missing = 0;
  for (final e in current.entries) {
    final old = rows[e.key] as Map<String, dynamic>;
    final normalized = shape(e.value);
    final ingredients = normalized['ingredients'] as List;
    for (final change
        in (mapping['candidates'] as List).cast<Map<String, dynamic>>()) {
      final suffix = e.key.split('|');
      if (suffix[1] != change['name'] || suffix[2] != change['variant']) {
        continue;
      }
      final i = ingredients.cast<Map<String, Object?>>().singleWhere(
        (i) => i['name'] == change['input'],
      );
      if (i['quantity'] != change['qty']) {
        throw StateError('Input quantity changed');
      }
      final ratios = i['ratios'] as Map<String, double>;
      if ((ratios[change['alternative']] ?? -1) != change['ratio']) {
        throw StateError('Unreviewed ratio');
      }
      i['options'] = <String>[];
      i['group'] = null;
      i['ratios'] = <String, double>{};
    }
    if (jsonEncode(normalized) != jsonEncode(old['shape'])) {
      throw StateError('Unreviewed formula change: ${e.key}');
    }
    final xp = old['experience'] as Map<String, dynamic>?;
    if (xp != null || experienceFor(e.value, CraftMode.processing) != null) {
      throw StateError('Unexpected experience value: ${e.key}');
    }
    missing++;
  }
  stdout.writeln(
    '$missing formula views verified unchanged except reviewed alternatives; previously unknown EXP remains unknown.',
  );
}
