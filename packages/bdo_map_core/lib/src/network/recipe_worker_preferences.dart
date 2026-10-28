class BdoRecipeWorkerPreferences {
  BdoRecipeWorkerPreferences({
    String target = '',
    List<String>? targets,
    this.budget = 400,
    this.hasSelection = false,
    Set<String> nodeIds = const {},
    Set<String> checkedItems = const {},
    Set<String> extraResourceIds = const {},
    Set<String> manualNodeIds = const {},
    Set<String> investedNodeIds = const {},
  }) : targets = List.unmodifiable(
         (targets ?? [if (target.isNotEmpty) target])
             .where((s) => s.trim().isNotEmpty)
             .toSet(),
       ),
       nodeIds = Set.unmodifiable(nodeIds),
       extraResourceIds = Set.unmodifiable(extraResourceIds),
       manualNodeIds = Set.unmodifiable(manualNodeIds),
       investedNodeIds = Set.unmodifiable(investedNodeIds),
       checkedItems = Set.unmodifiable(checkedItems);
  final List<String> targets;
  // Keep the previous single-target field for older compatible readers.
  String get target => targets.isEmpty ? '' : targets.first;
  final int budget;
  final bool hasSelection;
  final Set<String> nodeIds;
  final Set<String> checkedItems;
  final Set<String> extraResourceIds, manualNodeIds, investedNodeIds;
  Map<String, Object?> toJson() => {
    'target': target,
    'targets': targets,
    'budget': budget,
    'hasSelection': hasSelection,
    // Preserve the investment order so shared routes replay deterministically.
    'nodeIds': nodeIds.toList(),
    'checkedItems': checkedItems.toList()..sort(),
    'extraResourceIds': extraResourceIds.toList()..sort(),
    'manualNodeIds': manualNodeIds.toList(),
    'investedNodeIds': investedNodeIds.toList()..sort(),
  };
  factory BdoRecipeWorkerPreferences.fromJson(Object? value) {
    if (value is! Map) return BdoRecipeWorkerPreferences();
    Set<String> ids(Object? raw) =>
        raw is List ? raw.whereType<String>().toSet() : {};
    final budget = value['budget'];
    return BdoRecipeWorkerPreferences(
      target: value['target'] is String ? value['target'] as String : '',
      targets: value['targets'] is List
          ? (value['targets'] as List).whereType<String>().toList()
          : null,
      budget: budget is int && budget >= 0 ? budget : 400,
      hasSelection: value['hasSelection'] == true,
      nodeIds: ids(value['nodeIds']),
      checkedItems: ids(value['checkedItems']),
      extraResourceIds: ids(value['extraResourceIds']),
      manualNodeIds: ids(value['manualNodeIds']),
      investedNodeIds: ids(value['investedNodeIds']),
    );
  }
  bool sameValuesAs(BdoRecipeWorkerPreferences other) =>
      target == other.target &&
      targets.length == other.targets.length &&
      Iterable.generate(
        targets.length,
      ).every((i) => targets[i] == other.targets[i]) &&
      budget == other.budget &&
      hasSelection == other.hasSelection &&
      nodeIds.length == other.nodeIds.length &&
      nodeIds.containsAll(other.nodeIds) &&
      extraResourceIds.length == other.extraResourceIds.length &&
      extraResourceIds.containsAll(other.extraResourceIds) &&
      manualNodeIds.length == other.manualNodeIds.length &&
      manualNodeIds.containsAll(other.manualNodeIds) &&
      investedNodeIds.length == other.investedNodeIds.length &&
      investedNodeIds.containsAll(other.investedNodeIds) &&
      checkedItems.length == other.checkedItems.length &&
      checkedItems.containsAll(other.checkedItems);
}
