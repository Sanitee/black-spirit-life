// Read-only audit of bundled reference relationships. No profiles or network.
import 'dart:convert';
import 'dart:io';

import 'package:bdo_craft_planner_flutter/data/catalog/bundled_catalog_parser.dart';
import 'package:bdo_craft_planner_flutter/domain/models/craft_mode.dart';
import 'package:bdo_craft_planner_flutter/domain/opportunities/recipe_experience.dart';

void main() {
  final catalog = const BundledCatalogParser().parse(
    File('assets/data/app-data.json').readAsStringSync(),
  );
  final references = File('lib/domain/opportunities/recipe_experience_data.dart')
      .readAsStringSync();
  final groups = <String>{};
  final missing = <Object?>[];
  final counts = <String, Object?>{};
  for (final mode in CraftMode.values) {
    var sourced = 0;
    var estimated = 0;
    for (final recipe in catalog.forMode(mode).items.values) {
      final xp = experienceFor(recipe, mode);
      if (xp != null) {
        xp.estimated ? estimated++ : sourced++;
      } else if (references.contains('${mode.key}|${recipe.name.toLowerCase()}|')) {
        missing.add({
          'mode': mode.key,
          'name': recipe.name,
          'signature': recipeExperienceSignature(recipe),
          'ingredients': [for (final i in recipe.ingredients) {
            'name': i.name, 'quantity': i.quantity, 'group': i.substituteGroup,
          }],
        });
      }
      for (final ingredient in [
        ...recipe.ingredients,
        for (final v in recipe.variants) ...v.ingredients,
      ]) {
        final group = ingredient.substituteGroup;
        if (group != null && group.toLowerCase().startsWith('bdo group ')) {
          groups.add(group);
        }
      }
    }
    counts[mode.key] = {'sourced': sourced, 'estimated': estimated};
  }
  stdout.writeln(const JsonEncoder.withIndent('  ').convert({
    'catalogSha256': productionCatalogSha256,
    'rawGroupIds': groups.toList()..sort(),
    'defaultExperienceCoverage': counts,
    'previouslyNamedButUnmatchedExperience': missing,
  }));
}
