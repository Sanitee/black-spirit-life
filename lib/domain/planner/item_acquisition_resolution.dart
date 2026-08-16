import 'planner_models.dart';

/// Resolves reviewed acquisition guidance without treating a planner leaf as
/// evidence that the item is literally gathered.
ItemAcquisitionRule? resolveItemAcquisition({
  required String name,
  required PlannerRules rules,
}) {
  final direct = _exactOrFolded(rules.acquisitionInfo, name);
  if (direct != null) return direct;
  final alias = _exactOrFolded(rules.marketNameAliases, name);
  return alias == null ? null : _exactOrFolded(rules.acquisitionInfo, alias);
}

T? _exactOrFolded<T>(Map<String, T> values, String name) {
  final exact = values[name];
  if (exact != null) return exact;
  final folded = _fold(name);
  final matches =
      values.entries
          .where((entry) => _fold(entry.key) == folded)
          .toList(growable: false)
        ..sort((left, right) => left.key.compareTo(right.key));
  return matches.isEmpty ? null : matches.first.value;
}

String _fold(String value) =>
    value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
