import '../models/catalog_models.dart';
import 'planner_models.dart';

/// Resolves source metadata using the audited precedence:
/// assembled item metadata, bundled vendor information, then a verified
/// cross-mode NPC purchase price.
///
/// The assembly step has already overlaid user IngredientMeta on the bundled
/// recipe, so this resolver completes the source fallback without
/// leaking catalog-shape knowledge into widgets.
ResolvedSourceInfo resolveSourceInfo({
  required String name,
  required Recipe? recipe,
  required PlannerRules rules,
}) {
  final vendorRule = _vendorRule(name, rules);
  final npcPrice =
      _positivePrice(recipe?.npcPrice) ??
      _positivePrice(vendorRule?.price) ??
      _positivePrice(_sourceRule(rules.npcPurchasePrices, name, rules)) ??
      0;
  return ResolvedSourceInfo(
    sourceNote: _trimmed(recipe?.sourceNote),
    vendor: _firstNonBlank(recipe?.vendor, vendorRule?.vendor),
    role: _trimmed(vendorRule?.role),
    location: _firstNonBlank(recipe?.location, vendorRule?.location),
    npcPrice: npcPrice,
  );
}

VendorSourceRule? _vendorRule(String name, PlannerRules rules) {
  return _sourceRule(rules.vendorInfo, name, rules);
}

T? _sourceRule<T>(Map<String, T> values, String name, PlannerRules rules) {
  final direct = _exactOrFolded(values, name);
  if (direct != null) return direct;
  final alias = _exactOrFolded(rules.marketNameAliases, name);
  return alias == null ? null : _exactOrFolded(values, alias);
}

double? _positivePrice(double? value) =>
    value != null && value.isFinite && value > 0 ? value : null;

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
