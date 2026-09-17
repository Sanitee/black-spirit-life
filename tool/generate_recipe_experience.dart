// Run from the project root with the external research directory as argument.
// This intentionally consumes audited coverage summaries, not raw site dumps.
import 'dart:convert';
import 'dart:io';

import 'package:bdo_craft_planner_flutter/app/planning/planner_assembly.dart';
import 'package:bdo_craft_planner_flutter/data/catalog/bundled_catalog_parser.dart';
import 'package:bdo_craft_planner_flutter/domain/models/catalog_models.dart';
import 'package:bdo_craft_planner_flutter/domain/models/craft_mode.dart';
import 'package:bdo_craft_planner_flutter/domain/opportunities/recipe_experience.dart';
import 'package:bdo_craft_planner_flutter/domain/state/planner_state.dart';

const _auditedCatalogSha =
    '962880c1ed1821066ed6f25a22114de229b734595749094e2bc61851626fa440';
const _bdolyticsSource =
    'https://bdolytics.com/api/trpc/calculator.getCraftingRecipes';

void main(List<String> arguments) {
  if (arguments.length != 1) {
    throw ArgumentError('Pass the external recipe-exp-research directory.');
  }
  if (productionCatalogSha256 != _auditedCatalogSha) {
    throw StateError(
      'Catalog changed: audit formula coverage before regenerating.',
    );
  }
  final snapshot = const BundledCatalogParser().parse(
    File('assets/data/app-data.json').readAsStringSync(),
  );
  final raw = <CraftMode, Map<String, Recipe>>{
    for (final mode in CraftMode.values) mode: snapshot.forMode(mode).items,
  };
  // Clean assembly legitimately adds shared substitution metadata. Register
  // this form as well as raw reference recipes, never user-edited snapshots.
  final assembled = <CraftMode, Map<String, Recipe>>{
    for (final mode in CraftMode.values)
      mode: const PlannerAssembly().assembleRecipes(
        catalog: snapshot.forMode(mode),
        state: ModeState(
          target: '',
          bonusTarget: '',
          market: MarketState(),
          appearance: AppearanceSettings.defaultsFor(mode),
        ),
        supportingData: snapshot.supportingData,
        sharedMetadata: snapshot.alchemy.metadata,
        mode: mode,
        processingRecipes: snapshot.processing.items,
      ),
  };
  final generated = <String, RecipeExperience>{};
  final names = <String, bool>{};

  void register(
    CraftMode mode,
    String name,
    double xp,
    String source, {
    bool estimated = false,
    String? variantId,
  }) {
    if (!xp.isFinite || xp <= 0) throw StateError('Invalid EXP for $name');
    for (final recipes in <Map<String, Recipe>>[raw[mode]!, assembled[mode]!]) {
      final base = recipes[name];
      if (base == null) throw StateError('Missing audited recipe $name');
      final recipe = variantId == null ? base : base.resolveVariant(variantId);
      if (variantId != null && base.variantById(variantId) == null) {
        throw StateError('Missing audited variant $name/$variantId');
      }
      if (!recipe.isCraftable) throw StateError('Not craftable: $name');
      final skill = experienceSkillFor(recipe);
      if (skill == null) throw StateError('Unsupported skill: $name');
      final key =
          '${mode.key}|${name.trim().toLowerCase()}|'
          '${recipeExperienceSignature(recipe)}';
      final old = generated[key];
      if (old != null &&
          (old.value != xp ||
              old.estimated != estimated ||
              old.skill != skill)) {
        throw StateError('Conflicting EXP references: $name/$variantId');
      }
      generated[key] =
          old ??
          RecipeExperience(
            value: xp,
            estimated: estimated,
            skill: skill,
            sourceReference: source,
          );
      names['${mode.key}|$name'] = estimated;
    }
  }

  final research = Directory(arguments.single);
  Map<String, Object?> read(String name) =>
      jsonDecode(File('${research.path}/$name').readAsStringSync())
          as Map<String, Object?>;
  final cookingAlchemy = read('cooking-alchemy-codex-bdolytics-coverage.json');
  for (final rawRow in cookingAlchemy['coverage'] as List<Object?>) {
    final row = rawRow! as Map<String, Object?>;
    final status = row['status'];
    final primary = status == 'codex_primary';
    final gapfill = status == 'bdolytics_gapfill_candidate';
    if (!primary && !gapfill) continue;
    if (row['disagreement'] == true) {
      throw StateError('Unresolved source conflict');
    }
    final value = (row['candidateXp'] as num).toDouble();
    if (gapfill &&
        (row['formulaMatch'] != true ||
            (row['exactFormulaRecipeKeys'] as List).isEmpty)) {
      throw StateError('Unaudited BDOLytics formula ${row['name']}');
    }
    final source = primary
        ? (row['codexUrls'] as List).join(' ')
        : '$_bdolyticsSource recipes='
              '${(row['exactFormulaRecipeKeys'] as List).join(',')}';
    register(
      CraftMode.values.byName(row['mode'] as String),
      row['name'] as String,
      value,
      source,
    );
  }

  final processing = read('processing-bdolytics-formula-coverage.json');
  for (final rawRow in processing['records'] as List<Object?>) {
    final row = rawRow! as Map<String, Object?>;
    for (final rawRoute in <Object?>[
      row['default'],
      ...row['variants']! as List<Object?>,
    ]) {
      final route = rawRoute! as Map<String, Object?>;
      if (route['status'] != 'positive') continue;
      final values = route['xp'] as List;
      final keys = route['keys'] as List;
      if (values.length != 1 || keys.isEmpty) {
        throw StateError('Ambiguous Processing EXP for ${row['name']}');
      }
      register(
        CraftMode.processing,
        row['name'] as String,
        (values.single as num).toDouble(),
        '$_bdolyticsSource recipes=${keys.join(',')}',
        variantId: route['id'] == 'default' ? null : route['id'] as String,
      );
    }
  }

  // Explicitly approved comparisons. None is a verified base-EXP assertion;
  // no estimate propagates to another item, edited formula, or alternate batch.
  for (final entry in _alchemyEstimates.entries) {
    register(
      CraftMode.alchemy,
      entry.key,
      entry.value.$1,
      entry.value.$2,
      estimated: true,
    );
  }
  for (final entry in _processingEstimates.entries) {
    register(
      CraftMode.processing,
      entry.key,
      entry.value.$1,
      entry.value.$2,
      estimated: true,
    );
  }

  final keys = generated.keys.toList()..sort();
  String quote(String text) => jsonEncode(text).replaceAll(r'$', r'\$');
  final output = StringBuffer()
    ..writeln(
      '// GENERATED by tool/generate_recipe_experience.dart. Do not hand edit.',
    )
    ..writeln('// Audited 2026-09-17; catalog SHA-256: $_auditedCatalogSha')
    ..writeln(
      '// Only positive sourced EXP and explicitly marked comparisons are stored.',
    )
    ..writeln("part of 'recipe_experience.dart';")
    ..writeln()
    ..writeln(
      'const _recipeExperienceReferences = <String, RecipeExperience>{',
    );
  for (final key in keys) {
    final value = generated[key]!;
    output
      ..writeln('  ${quote(key)}: RecipeExperience(')
      ..writeln('    value: ${value.value}, estimated: ${value.estimated},')
      ..writeln('    skill: ${quote(value.skill)},')
      ..writeln('    sourceReference: ${quote(value.sourceReference)},')
      ..writeln('  ),');
  }
  output.writeln('};');
  File(
    'lib/domain/opportunities/recipe_experience_data.dart',
  ).writeAsStringSync(output.toString());
  stdout.writeln('Generated ${generated.length} guarded formula records.');
  for (final mode in CraftMode.values) {
    final rows = names.entries.where(
      (entry) => entry.key.startsWith('${mode.key}|'),
    );
    stdout.writeln(
      '${mode.key}: ${rows.where((entry) => !entry.value).length} '
      'sourced recipes + ${rows.where((entry) => entry.value).length} estimates',
    );
  }
}

const _alchemyEstimates = <String, (double, String)>{
  'Elixir of Edania': (
    920,
    'Estimate: race-damage elixirs; https://bdocodex.com/us/recipe/4/ '
        'https://bdocodex.com/us/recipe/8/ https://bdocodex.com/us/recipe/217/',
  ),
  'Perfume of Insight': (
    2000,
    'Estimate: seven covered perfumes all 2000; '
        'https://bdolytics.com/en/EU/alchemy/market',
  ),
  'Perfume of Verdure': (
    2000,
    'Estimate: seven covered perfumes all 2000; Alchemy Tool route only; '
        'https://bdolytics.com/en/EU/alchemy/market',
  ),
  'Oil of Enchantment': (
    1400,
    'Estimate: six covered intermediate oils all 1400; '
        'https://bdocodex.com/us/recipes/alchemy/',
  ),
  'Elixir of Persistence': (
    1610,
    'Estimate: conventional one-oil elixirs; counterexamples exist; '
        'https://bdocodex.com/us/recipe/5/ https://bdocodex.com/us/recipe/7/',
  ),
  'Elixir of Brawn': (
    1610,
    'Estimate: conventional one-oil elixirs; counterexamples exist; '
        'https://bdocodex.com/us/recipe/7/',
  ),
};

const _processingEstimates = <String, (double, String)>{
  'Rice Flour': (
    70,
    'Estimate: seven grain x1 flour formulas all 70; $_bdolyticsSource',
  ),
  'Snowfield Cedar Plank': (
    200,
    'Estimate: fifteen timber x5 plank formulas all 200; $_bdolyticsSource',
  ),
  'Pure Gold Crystal': (
    1500,
    'Estimate: source 4256:c1484d38c2b1 uses solvent x1, local x2; $_bdolyticsSource',
  ),
  'Pure Platinum Crystal': (
    1500,
    'Estimate: source 4259:a9b56e0748ce uses solvent x1, local x2; $_bdolyticsSource',
  ),
  'Pure Silver Crystal': (
    1500,
    'Estimate: source 4253:fe1386681ef4 uses solvent x1, local x2; $_bdolyticsSource',
  ),
};
