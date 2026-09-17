import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../catalog/temporarily_archived_items.dart';
import '../models/catalog_models.dart';
import '../models/craft_mode.dart';

part 'recipe_experience_data.dart';

/// Base experience for one successful execution of an audited recipe formula.
///
/// This is not experience per produced item, per hour, or mastery-adjusted EXP.
/// Missing and unverified source zeroes deliberately have no record.
final class RecipeExperience {
  const RecipeExperience({
    required this.value,
    required this.estimated,
    required this.skill,
    required this.sourceReference,
  });

  final double value;
  final bool estimated;
  final String skill;

  /// Internal reference/estimate provenance; not an additional UI tooltip.
  final String sourceReference;
}

/// Returns EXP only for the active, audited formula. Resolve selected variants
/// before calling: a different batch, method or edited ingredient is not assumed
/// to award the same experience merely because its product has the same name.
RecipeExperience? experienceFor(Recipe recipe, CraftMode mode) {
  if (!recipe.isCraftable ||
      _obsoleteRecipeNames.contains(_fold(recipe.name)) ||
      _obsoleteRecipeIds.contains(recipe.marketId) ||
      isTemporarilyArchivedItem(recipe.name, itemId: recipe.marketId)) {
    return null;
  }
  final reference =
      _recipeExperienceReferences['${mode.key}|${_fold(recipe.name)}|${recipeExperienceSignature(recipe)}'];
  if (reference == null || reference.skill != experienceSkillFor(recipe)) {
    return null;
  }
  return reference;
}

/// The life skill rewarded by the active method, independent of the tab that
/// contains it. Worker/refinery and unsupported production methods are omitted.
String? experienceSkillFor(Recipe recipe) {
  if (!recipe.isCraftable) return null;
  final method = _fold(recipe.method ?? '').replaceAll(RegExp(r'[\s_-]+'), '');
  if (method.startsWith('simplealchemy')) return 'alchemy';
  if (method.startsWith('simplecooking')) return 'cooking';
  if (_processingMethods.contains(method)) return 'processing';
  final type = _fold(recipe.type);
  if (type == 'alchemy' || type == 'simple_alchemy') return 'alchemy';
  if (type == 'cooking' || type == 'simple_cooking') return 'cooking';
  return null;
}

const _processingMethods = <String>{
  'chopping',
  'drying',
  'filtering',
  'grinding',
  'heating',
  'shaking',
  'manufacture',
};

// Removed from the game in September 2026. Historical values are not current
// crafting choices, even while older reference catalog entries remain present.
const _obsoleteRecipeNames = <String>{
  'tenacious origin of life',
  'rough opulent crystal',
  'flawless spirit stone',
};
const _obsoleteRecipeIds = <String>{'5303', '5304', '5305'};

/// Stable formula identity shared with the reference generator. It includes
/// substitution semantics and output bounds, but not presentation metadata.
/// Adding source coverage requires an audited regeneration, not a name-only
/// fallback that would silently assign EXP to user-authored formulas.
String recipeExperienceSignature(Recipe recipe) {
  final ingredients = recipe.ingredients.map((ingredient) {
    final options = ingredient.options.map(_fold).toSet().toList()..sort();
    final ratios =
        ingredient.substituteRatios.entries
            .map((entry) => <Object>[_fold(entry.key), entry.value.toDouble()])
            .toList()
          ..sort((a, b) => (a.first as String).compareTo(b.first as String));
    return <String, Object?>{
      'name': _fold(ingredient.name),
      'quantity': ingredient.quantity.toDouble(),
      'options': options,
      'group': ingredient.substituteGroup == null
          ? null
          : _fold(ingredient.substituteGroup!),
      'ratios': ratios,
    };
  }).toList()..sort((a, b) => jsonEncode(a).compareTo(jsonEncode(b)));
  return sha256
      .convert(
        utf8.encode(
          jsonEncode(<String, Object?>{
            'type': _fold(recipe.type),
            'method': recipe.method == null ? null : _fold(recipe.method!),
            'baseOutput': recipe.baseOutput.toDouble(),
            'outputMinimum': recipe.outputMinimum?.toDouble(),
            'outputMaximum': recipe.outputMaximum?.toDouble(),
            'marketId': recipe.marketId,
            'ingredients': ingredients,
          }),
        ),
      )
      .toString();
}

String _fold(String value) => value.trim().toLowerCase();
