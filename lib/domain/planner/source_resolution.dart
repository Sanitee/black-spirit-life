import '../models/catalog_models.dart';
import 'planner_models.dart';

/// Resolves source metadata using the audited precedence:
/// assembled item metadata first, then bundled vendor information.
///
/// The assembly step has already overlaid user IngredientMeta on the bundled
/// recipe, so this resolver completes the final vendor fallback without
/// leaking catalog-shape knowledge into widgets.
ResolvedSourceInfo resolveSourceInfo({
  required String name,
  required Recipe? recipe,
  required PlannerRules rules,
}) {
  final vendorRule = _vendorRule(name, rules);
  final recipeNpcPrice = recipe?.npcPrice ?? 0;
  return ResolvedSourceInfo(
    sourceNote: _trimmed(recipe?.sourceNote),
    vendor: _firstNonBlank(recipe?.vendor, vendorRule?.vendor),
    role: _trimmed(vendorRule?.role),
    location: _firstNonBlank(recipe?.location, vendorRule?.location),
    npcPrice: recipeNpcPrice > 0
        ? recipeNpcPrice
        : (vendorRule?.price ?? 0) > 0
        ? vendorRule!.price
        : 0,
  );
}

VendorSourceRule? _vendorRule(String name, PlannerRules rules) {
  final direct = _exactOrFolded(rules.vendorInfo, name);
  if (direct != null) return direct;
  final alias = _exactOrFolded(rules.marketNameAliases, name);
  return alias == null ? null : _exactOrFolded(rules.vendorInfo, alias);
}

T? _exactOrFolded<T>(Map<String, T> values, String name) {
  final exact = values[name];
  if (exact != null) return exact;
  final folded = name.trim().toLowerCase();
  final matches =
      values.entries
          .where((entry) => entry.key.trim().toLowerCase() == folded)
          .toList(growable: false)
        ..sort((left, right) => left.key.compareTo(right.key));
  return matches.isEmpty ? null : matches.first.value;
}

String? _firstNonBlank(String? first, String? second) =>
    _trimmed(first) ?? _trimmed(second);

String? _trimmed(String? value) {
  final result = value?.trim();
  return result == null || result.isEmpty ? null : result;
}
