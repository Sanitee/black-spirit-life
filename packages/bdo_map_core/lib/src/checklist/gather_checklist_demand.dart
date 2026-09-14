/// A persisted requirement from one plan or recipe. Inventory is deliberately
/// not stored here: all sources share the application's live inventory.
class BdoGatherChecklistDemand {
  BdoGatherChecklistDemand({
    required this.sourceId,
    required this.sourceLabel,
    required this.materialKey,
    required this.materialName,
    required this.neededQuantity,
    this.plannerMode,
    this.plannerTarget,
    this.bonusPlan = false,
  }) {
    if ([
          sourceId,
          sourceLabel,
          materialKey,
          materialName,
        ].any((s) => s.trim().isEmpty) ||
        !neededQuantity.isFinite ||
        neededQuantity < 0) {
      throw ArgumentError(
        'A gather requirement needs an identity and a finite quantity.',
      );
    }
  }

  final String sourceId;
  final String sourceLabel;
  final String materialKey;
  final String materialName;
  final double neededQuantity;
  final String? plannerMode;
  final String? plannerTarget;
  final bool bonusPlan;

  String get identity => '${sourceId.length}:$sourceId$materialKey';

  BdoGatherChecklistDemand withQuantity(double quantity) =>
      BdoGatherChecklistDemand(
        sourceId: sourceId,
        sourceLabel: sourceLabel,
        materialKey: materialKey,
        materialName: materialName,
        neededQuantity: quantity,
        plannerMode: plannerMode,
        plannerTarget: plannerTarget,
        bonusPlan: bonusPlan,
      );

  Map<String, Object?> toJson() => {
    'sourceId': sourceId,
    'sourceLabel': sourceLabel,
    'materialKey': materialKey,
    'materialName': materialName,
    'neededQuantity': neededQuantity,
    'plannerMode': ?plannerMode,
    'plannerTarget': ?plannerTarget,
    if (bonusPlan) 'bonusPlan': true,
  };

  static BdoGatherChecklistDemand? fromJson(Object? value) {
    if (value is! Map || value['neededQuantity'] is! num) return null;
    final quantity = (value['neededQuantity'] as num).toDouble();
    final strings = [
      for (final key in [
        'sourceId',
        'sourceLabel',
        'materialKey',
        'materialName',
      ])
        value[key],
    ];
    if (strings.any((s) => s is! String || s.trim().isEmpty) ||
        !quantity.isFinite ||
        quantity < 0) {
      return null;
    }
    return BdoGatherChecklistDemand(
      sourceId: strings[0] as String,
      sourceLabel: strings[1] as String,
      materialKey: strings[2] as String,
      materialName: strings[3] as String,
      neededQuantity: quantity,
      plannerMode: value['plannerMode'] is String
          ? value['plannerMode'] as String
          : null,
      plannerTarget: value['plannerTarget'] is String
          ? value['plannerTarget'] as String
          : null,
      bonusPlan: value['bonusPlan'] == true,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is BdoGatherChecklistDemand &&
      sourceId == other.sourceId &&
      sourceLabel == other.sourceLabel &&
      materialKey == other.materialKey &&
      materialName == other.materialName &&
      neededQuantity == other.neededQuantity &&
      plannerMode == other.plannerMode &&
      plannerTarget == other.plannerTarget &&
      bonusPlan == other.bonusPlan;

  @override
  int get hashCode => Object.hash(
    sourceId,
    sourceLabel,
    materialKey,
    materialName,
    neededQuantity,
    plannerMode,
    plannerTarget,
    bonusPlan,
  );
}

class BdoGatherChecklistQuantity {
  const BdoGatherChecklistQuantity({
    this.needed,
    this.owned,
    this.canRecord = false,
  });
  final double? needed;
  final double? owned;
  final bool canRecord;
  double? get remaining => needed == null || owned == null
      ? null
      : (needed! - owned!).clamp(0, double.infinity).toDouble();
}

/// Returned only after the explicit inventory transaction is durable.
class BdoGatherChecklistReceipt {
  const BdoGatherChecklistReceipt({required this.undo});
  final Future<void> Function() undo;
}

typedef BdoRecordGathered =
    Future<BdoGatherChecklistReceipt> Function(
      String resourceId,
      double quantity,
    );
