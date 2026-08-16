import '../model/planner_material_need.dart';
import '../model/resource_map_data.dart';
import 'recipe_node_recommendation.dart';

/// A stable reference to one planner material inside one recipe-mode group.
///
/// The two-part key avoids collisions when Cooking and Alchemy both require
/// the same material. IDs are supplied by the planner so they can remain
/// stable when labels, quantities, or list order change.
class BdoPlannerNeedKey {
  const BdoPlannerNeedKey({required this.groupId, required this.materialId});

  final String groupId;
  final String materialId;

  @override
  bool operator ==(Object other) =>
      other is BdoPlannerNeedKey &&
      groupId == other.groupId &&
      materialId == other.materialId;

  @override
  int get hashCode => Object.hash(groupId, materialId);

  @override
  String toString() => '$groupId:$materialId';
}

/// One independently selectable planner shortage.
///
/// [need] is retained intact. In particular, market evidence, item IDs,
/// vendor-route facts, and worker-route review state are not projected into a
/// second lossy model.
class BdoPlannerNeedMaterial {
  BdoPlannerNeedMaterial({
    required this.id,
    required this.need,
    this.selectedByDefault = true,
  }) {
    if (id.trim().isEmpty) {
      throw ArgumentError.value(id, 'id', 'A stable material ID is required.');
    }
  }

  final String id;
  final BdoPlannerMaterialNeed need;
  final bool selectedByDefault;
}

/// A UI-ready group such as Cooking or Alchemy.
///
/// Group order is retained for presentation. Selection and recommendation
/// order use stable IDs, so rebuilding the same groups in another display
/// order cannot change the network request.
class BdoPlannerNeedGroup {
  BdoPlannerNeedGroup({
    required this.id,
    required this.label,
    required Iterable<BdoPlannerNeedMaterial> materials,
  }) : materials = List<BdoPlannerNeedMaterial>.unmodifiable(materials) {
    if (id.trim().isEmpty) {
      throw ArgumentError.value(id, 'id', 'A stable group ID is required.');
    }
    if (label.trim().isEmpty) {
      throw ArgumentError.value(label, 'label', 'A group label is required.');
    }
    final materialIds = <String>{};
    for (final material in this.materials) {
      if (!materialIds.add(material.id)) {
        throw ArgumentError.value(
          material.id,
          'materials',
          'Material IDs must be unique inside group "$id".',
        );
      }
    }
  }

  final String id;
  final String label;
  final List<BdoPlannerNeedMaterial> materials;
}

/// Aggregate checkbox state for one planner-need group.
enum BdoPlannerNeedGroupSelectionState { none, partial, all }

/// Immutable Cooking/Alchemy material selection.
///
/// Call [withMaterialSelected] or [withGroupSelected] to produce the next
/// state. When [selectedMaterialKeys] is omitted, each material's
/// [BdoPlannerNeedMaterial.selectedByDefault] value is used.
class BdoPlannerNeedSelection {
  factory BdoPlannerNeedSelection({
    required Iterable<BdoPlannerNeedGroup> groups,
    Iterable<BdoPlannerNeedKey>? selectedMaterialKeys,
  }) {
    final groupList = List<BdoPlannerNeedGroup>.unmodifiable(groups);
    final groupIds = <String>{};
    final materialsByKey = <BdoPlannerNeedKey, BdoPlannerNeedMaterial>{};
    final defaultKeys = <BdoPlannerNeedKey>{};

    for (final group in groupList) {
      if (!groupIds.add(group.id)) {
        throw ArgumentError.value(
          group.id,
          'groups',
          'Group IDs must be unique.',
        );
      }
      for (final material in group.materials) {
        final key = BdoPlannerNeedKey(
          groupId: group.id,
          materialId: material.id,
        );
        materialsByKey[key] = material;
        if (material.selectedByDefault) {
          defaultKeys.add(key);
        }
      }
    }

    final requestedKeys = selectedMaterialKeys == null
        ? defaultKeys
        : Set<BdoPlannerNeedKey>.of(selectedMaterialKeys);
    final knownSelectedKeys = requestedKeys
        .where(materialsByKey.containsKey)
        .toSet();

    return BdoPlannerNeedSelection._(
      groups: groupList,
      materialsByKey:
          Map<BdoPlannerNeedKey, BdoPlannerNeedMaterial>.unmodifiable(
            materialsByKey,
          ),
      selectedMaterialKeys: Set<BdoPlannerNeedKey>.unmodifiable(
        knownSelectedKeys,
      ),
    );
  }

  const BdoPlannerNeedSelection._({
    required this.groups,
    required this._materialsByKey,
    required this.selectedMaterialKeys,
  });

  final List<BdoPlannerNeedGroup> groups;
  final Map<BdoPlannerNeedKey, BdoPlannerNeedMaterial> _materialsByKey;
  final Set<BdoPlannerNeedKey> selectedMaterialKeys;

  int get totalMaterialCount => _materialsByKey.length;
  int get selectedMaterialCount => selectedMaterialKeys.length;

  int get selectedPositiveMaterialCount => selectedPositivePlannerNeeds.length;

  /// Selected, positive shortages in stable group/material-ID order.
  ///
  /// Identical materials in different groups intentionally remain separate
  /// here. The existing recipe recommendation service combines their
  /// quantities into one canonical resource target, which both preserves the
  /// original planner snapshots and lets Cooking and Alchemy share one route.
  List<BdoPlannerMaterialNeed> get selectedPositivePlannerNeeds {
    final keys = selectedMaterialKeys.toList()..sort(_compareNeedKeys);
    return List<BdoPlannerMaterialNeed>.unmodifiable(
      keys
          .map((key) => _materialsByKey[key]!.need)
          .where(
            (need) => need.missingQuantity.isFinite && need.missingQuantity > 0,
          ),
    );
  }

  /// Selected positive shortages that should be supplied by workers.
  ///
  /// A direct NPC-vendor item can still remain visible in the craft planner
  /// and normal map search, but it must not consume CP in a recipe worker
  /// network.
  List<BdoPlannerMaterialNeed> get selectedPositiveWorkerPlannerNeeds =>
      List<BdoPlannerMaterialNeed>.unmodifiable(
        selectedPositivePlannerNeeds.where(
          (need) => !need.vendorPurchaseAvailable,
        ),
      );

  bool isMaterialSelected({
    required String groupId,
    required String materialId,
  }) => selectedMaterialKeys.contains(
    BdoPlannerNeedKey(groupId: groupId, materialId: materialId),
  );

  BdoPlannerNeedGroupSelectionState groupSelectionState(String groupId) {
    final group = _group(groupId);
    if (group.materials.isEmpty) {
      return BdoPlannerNeedGroupSelectionState.none;
    }
    final selectedCount = group.materials
        .where(
          (material) => selectedMaterialKeys.contains(
            BdoPlannerNeedKey(groupId: group.id, materialId: material.id),
          ),
        )
        .length;
    if (selectedCount == 0) {
      return BdoPlannerNeedGroupSelectionState.none;
    }
    if (selectedCount == group.materials.length) {
      return BdoPlannerNeedGroupSelectionState.all;
    }
    return BdoPlannerNeedGroupSelectionState.partial;
  }

  BdoPlannerNeedSelection withMaterialSelected({
    required String groupId,
    required String materialId,
    required bool selected,
  }) {
    final key = BdoPlannerNeedKey(groupId: groupId, materialId: materialId);
    _requireMaterial(key);
    final nextKeys = Set<BdoPlannerNeedKey>.of(selectedMaterialKeys);
    selected ? nextKeys.add(key) : nextKeys.remove(key);
    return BdoPlannerNeedSelection(
      groups: groups,
      selectedMaterialKeys: nextKeys,
    );
  }

  BdoPlannerNeedSelection toggleMaterial({
    required String groupId,
    required String materialId,
  }) => withMaterialSelected(
    groupId: groupId,
    materialId: materialId,
    selected: !isMaterialSelected(groupId: groupId, materialId: materialId),
  );

  BdoPlannerNeedSelection withGroupSelected({
    required String groupId,
    required bool selected,
  }) {
    final group = _group(groupId);
    final nextKeys = Set<BdoPlannerNeedKey>.of(selectedMaterialKeys);
    for (final material in group.materials) {
      final key = BdoPlannerNeedKey(groupId: group.id, materialId: material.id);
      selected ? nextKeys.add(key) : nextKeys.remove(key);
    }
    return BdoPlannerNeedSelection(
      groups: groups,
      selectedMaterialKeys: nextKeys,
    );
  }

  BdoPlannerNeedSelection toggleGroup(String groupId) => withGroupSelected(
    groupId: groupId,
    selected:
        groupSelectionState(groupId) != BdoPlannerNeedGroupSelectionState.all,
  );

  BdoPlannerNeedGroup _group(String groupId) {
    for (final group in groups) {
      if (group.id == groupId) {
        return group;
      }
    }
    throw ArgumentError.value(groupId, 'groupId', 'Unknown planner group.');
  }

  void _requireMaterial(BdoPlannerNeedKey key) {
    if (!_materialsByKey.containsKey(key)) {
      throw ArgumentError.value(key, 'materialId', 'Unknown planner material.');
    }
  }
}

/// Combined network inputs for the currently checked Cooking/Alchemy needs.
class BdoGroupedRecipeNodeRecommendationRequest {
  BdoGroupedRecipeNodeRecommendationRequest({
    required this.selection,
    required this.contributionPointBudget,
    Iterable<BdoRecipeNodeMaterialTarget> materialTargets =
        const <BdoRecipeNodeMaterialTarget>[],
    Set<String> currentNodeIds = const <String>{},
    Set<String>? rootNodeIds,
    this.maxExactTerminalNodes = 10,
    this.maxExactSelectionCombinations = 256,
  }) : materialTargets = List<BdoRecipeNodeMaterialTarget>.unmodifiable(
         materialTargets,
       ),
       currentNodeIds = Set<String>.unmodifiable(currentNodeIds),
       rootNodeIds = rootNodeIds == null
           ? null
           : Set<String>.unmodifiable(rootNodeIds);

  final BdoPlannerNeedSelection selection;
  final int contributionPointBudget;
  final List<BdoRecipeNodeMaterialTarget> materialTargets;
  final Set<String> currentNodeIds;
  final Set<String>? rootNodeIds;
  final int maxExactTerminalNodes;
  final int maxExactSelectionCombinations;

  BdoRecipeNodeRecommendationRequest toRecipeRequest() =>
      BdoRecipeNodeRecommendationRequest.fromPlannerNeeds(
        contributionPointBudget: contributionPointBudget,
        needs: selection.selectedPositiveWorkerPlannerNeeds,
        materialTargets: materialTargets,
        currentNodeIds: currentNodeIds,
        rootNodeIds: rootNodeIds,
        maxExactTerminalNodes: maxExactTerminalNodes,
        maxExactSelectionCombinations: maxExactSelectionCombinations,
      );
}

/// A combined recommendation plus compact counts suitable for the picker UI.
class BdoGroupedRecipeNodeRecommendationResult {
  const BdoGroupedRecipeNodeRecommendationResult({
    required this.selection,
    required this.recommendation,
  });

  final BdoPlannerNeedSelection selection;
  final BdoRecipeNodeRecommendation recommendation;

  int get totalMaterialCount => selection.totalMaterialCount;
  int get selectedMaterialCount => selection.selectedMaterialCount;
  int get selectedPositiveMaterialCount =>
      selection.selectedPositiveWorkerPlannerNeeds.length;

  /// Selected input rows that resolved to a mapped worker-node resource.
  ///
  /// This remains an input-row count even when Cooking and Alchemy share the
  /// same canonical resource.
  int get mappedSelectedMaterialCount => recommendation.coverageTargets.fold(
    0,
    (total, target) => total + target.recipeShortageInputCount,
  );

  int get unmappedSelectedMaterialCount =>
      selectedPositiveMaterialCount - mappedSelectedMaterialCount;

  /// Number of distinct canonical worker-node resources after deduplication.
  int get mappedResourceCount => recommendation.coverageTargets.length;

  bool get mapsEverySelectedMaterial =>
      unmappedSelectedMaterialCount == 0 &&
      recommendation.uncoveredMaterials
          .where((item) => item.missingQuantity != null)
          .isEmpty;
}

/// Delegates a grouped selection to the existing shared-route optimizer.
///
/// No network logic is duplicated here. All selected positive needs are sent
/// in one request so Cooking and Alchemy can reuse common connection nodes.
class BdoGroupedRecipeNodeRecommendationService {
  const BdoGroupedRecipeNodeRecommendationService({
    this.recommendationService = const BdoRecipeNodeRecommendationService(),
  });

  final BdoRecipeNodeRecommendationService recommendationService;

  BdoGroupedRecipeNodeRecommendationResult recommend({
    required BdoResourceMapDataset data,
    required BdoGroupedRecipeNodeRecommendationRequest request,
  }) {
    final recommendation = recommendationService.recommend(
      data: data,
      request: request.toRecipeRequest(),
    );
    return BdoGroupedRecipeNodeRecommendationResult(
      selection: request.selection,
      recommendation: recommendation,
    );
  }
}

int _compareNeedKeys(BdoPlannerNeedKey left, BdoPlannerNeedKey right) {
  final byGroup = left.groupId.compareTo(right.groupId);
  return byGroup != 0 ? byGroup : left.materialId.compareTo(right.materialId);
}
