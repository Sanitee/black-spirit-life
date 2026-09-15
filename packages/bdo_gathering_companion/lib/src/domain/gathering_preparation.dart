import 'dart:convert';
import 'dart:math' as math;

import 'bairog_calculator.dart';
import 'models.dart';

const gatheringPreparationPreferenceKey = 'gatheringPreparation';
const _legacyEstimatePreferenceKey = 'gatheringEstimateSetup';

/// These are the exact existing calculator expense records, not new recovery
/// formulas. In particular, the catalog's Mellow tick value is not substituted
/// for Bairog's reviewed hourly expense assumptions.
const _herbalExpenses = <String, int>{
  'buff-820150': 820150,
  'buff-821144': 821144,
  'buff-821145': 821145,
};
const gatheringExtraProcPetIds = <String>{
  'hedgehog',
  'golden-hedgehog',
  'pwudgy-llama',
};

/// One durable preparation profile. Mastery and drop rate in [baseSettings]
/// explicitly exclude selected buffs; gear, artifacts and crystals are already
/// part of those user-entered base values. Other calculator inputs are retained.
class GatheringPreparation {
  GatheringPreparation({
    BairogCalculatorSettings baseSettings = const BairogCalculatorSettings(
      enabledExpenseItemIds: {},
    ),
    Iterable<String> buffIds = const [],
    Iterable<String> petIds = const [],
    this.statsConfirmed = false,
  }) : baseSettings = _immutableSettings(baseSettings),
       buffIds = _immutableIds(buffIds),
       petIds = _immutableIds(petIds);

  static const schemaVersion = 1;

  final BairogCalculatorSettings baseSettings;
  final Set<String> buffIds;
  final Set<String> petIds;
  final bool statsConfirmed;

  factory GatheringPreparation.fromPreferences(
    Map<String, dynamic> preferences, {
    Catalog? catalog,
  }) {
    final profile = preferences[gatheringPreparationPreferenceKey];
    if (profile != null) {
      if (profile is! Map) {
        throw const FormatException('Gathering preparation must be an object.');
      }
      return GatheringPreparation.fromJson(Map<String, dynamic>.from(profile));
    }
    final legacy = preferences[_legacyEstimatePreferenceKey];
    final base = legacy is Map
        ? BairogCalculatorSettings.fromJson(Map<String, dynamic>.from(legacy))
        : const BairogCalculatorSettings(enabledExpenseItemIds: {});
    // Legacy totals may already include buffs. Never select a starter preset or
    // infer which mastery/drop bonuses to subtract. Only an already-enabled,
    // energy-only expense can be represented without altering those totals.
    final energyOnly = <String>{};
    if (legacy is Map && catalog != null) {
      for (final buff in catalog.buffs) {
        final expense = _herbalExpenses[buff.id];
        if (expense != null &&
            base.enabledExpenseItemIds.contains(expense) &&
            !buff.referenceOnly &&
            buff.effects.isNotEmpty &&
            buff.effects.keys.every((key) => key == 'energyRecovery')) {
          energyOnly.add(buff.id);
        }
      }
    }
    return GatheringPreparation(baseSettings: base, buffIds: energyOnly);
  }

  factory GatheringPreparation.fromJson(Map<String, dynamic> json) {
    if (json['baseSettings'] is! Map ||
        (json['statsConfirmed'] != null && json['statsConfirmed'] is! bool)) {
      throw const FormatException(
        'Gathering preparation has damaged base stats.',
      );
    }
    return GatheringPreparation(
      baseSettings: BairogCalculatorSettings.fromJson(
        Map<String, dynamic>.from(json['baseSettings'] as Map),
      ),
      buffIds: _readIds(json['buffIds'], 'buff'),
      petIds: _readIds(json['petIds'], 'pet'),
      statsConfirmed: json['statsConfirmed'] == true,
    );
  }

  Map<String, dynamic> toJson() => {
    'schemaVersion': schemaVersion,
    'baseSettings': baseSettings.toJson(),
    'buffIds': buffIds.toList(),
    'petIds': petIds.toList(),
    'statsConfirmed': statsConfirmed,
  };

  GatheringPreparation copyWith({
    BairogCalculatorSettings? baseSettings,
    Iterable<String>? buffIds,
    Iterable<String>? petIds,
    bool? statsConfirmed,
  }) => GatheringPreparation(
    baseSettings: baseSettings ?? this.baseSettings,
    buffIds: buffIds ?? this.buffIds,
    petIds: petIds ?? this.petIds,
    statsConfirmed: statsConfirmed ?? this.statsConfirmed,
  );

  bool hasSameValuesAs(GatheringPreparation other) =>
      identical(this, other) ||
      jsonEncode(toJson()) == jsonEncode(other.toJson());

  /// Unknown/reference-only IDs never contribute. A malformed saved selection
  /// cannot stack mutually exclusive buffs; catalog priority and ID make the
  /// resolution independent of JSON/set insertion order. The saved IDs remain
  /// available until an explicit edit normalizes them.
  Set<String> activeBuffIds(Catalog catalog) =>
      _acceptedBuffIds(catalog, buffIds);

  Map<String, double> buffTotals(Catalog catalog) =>
      Map.unmodifiable(catalog.sumBuffs(activeBuffIds(catalog)));

  /// Pet identity is provenance, not a tier or an additive drop-rate bonus.
  Set<String> get extraProcPetIds =>
      _immutableIds(petIds.where(gatheringExtraProcPetIds.contains));

  BairogCalculatorSettings effectiveSettings(Catalog catalog) {
    final totals = buffTotals(catalog);
    final masteryBonus =
        (totals['lifeMastery'] ?? 0) + (totals['gatheringMastery'] ?? 0);
    final expenses = <int>{...baseSettings.enabledExpenseItemIds};
    for (final id in activeBuffIds(catalog)) {
      final expense = _herbalExpenses[id];
      if (expense != null) expenses.add(expense);
    }
    return _immutableSettings(
      baseSettings.copyWith(
        mastery: (baseSettings.mastery + masteryBonus).round().clamp(0, 3000),
        gatheringDropRatePercent: math.max(
          0,
          baseSettings.gatheringDropRatePercent +
              (totals['gatheringItemDropPct'] ?? 0),
        ),
        enabledExpenseItemIds: expenses,
      ),
    );
  }

  /// Explicit buff edits own the three mapped herbal expense bits, so removing
  /// a herb also removes its calculator expense/recovery assumption.
  GatheringPreparation withBuffIds(Set<String> ids, Catalog catalog) {
    final accepted = _acceptedBuffIds(catalog, ids);
    final expenses = baseSettings.enabledExpenseItemIds
        .where((id) => !_herbalExpenses.values.contains(id))
        .toSet();
    for (final id in accepted) {
      final expense = _herbalExpenses[id];
      if (expense != null) expenses.add(expense);
    }
    return copyWith(
      buffIds: accepted,
      baseSettings: baseSettings.copyWith(enabledExpenseItemIds: expenses),
    );
  }

  /// The advanced expense checkboxes edit that same selection in the opposite
  /// direction. Non-energy selections and all unrelated calculator flags survive.
  GatheringPreparation withBaseSettings(
    BairogCalculatorSettings settings,
    Catalog catalog, {
    bool? statsConfirmed,
  }) {
    final selected = buffIds
        .where((id) => !_herbalExpenses.containsKey(id))
        .toSet();
    for (final entry in _herbalExpenses.entries) {
      if (settings.enabledExpenseItemIds.contains(entry.value)) {
        selected.add(entry.key);
      }
    }
    return copyWith(
      baseSettings: settings,
      statsConfirmed: statsConfirmed,
    ).withBuffIds(selected, catalog);
  }

  /// Choosing a species never guesses a tier. Removing the last explicitly
  /// selected extra-gather pet turns off its effect; untouched legacy/manual
  /// tiers are retained until the user actually changes that pet selection.
  GatheringPreparation withPetIds(Set<String> ids) {
    final removedLast =
        extraProcPetIds.isNotEmpty &&
        !ids.any(gatheringExtraProcPetIds.contains);
    return copyWith(
      petIds: ids,
      baseSettings: removedLast
          ? baseSettings.copyWith(hedgehogTier: BairogHedgehogTier.none)
          : baseSettings,
    );
  }

  /// Frozen history stores both inputs and their derived values. A future
  /// catalog update must not recalculate an existing session's preparation.
  Map<String, dynamic> snapshot(Catalog catalog, {required String methodId}) =>
      immutablePreparationSnapshot({
        'schemaVersion': schemaVersion,
        'profile': toJson(),
        'effectiveSettings': effectiveSettings(catalog).toJson(),
        'buffTotals': buffTotals(catalog),
        'activeBuffIds': activeBuffIds(catalog).toList(),
        'extraProcPetIds': extraProcPetIds.toList(),
        'statsConfirmed': statsConfirmed,
        'methodId': methodId,
        'catalogDate': catalog.reviewedAt,
      });
}

Set<String> _acceptedBuffIds(Catalog catalog, Iterable<String> ids) {
  final selected = ids.toSet();
  final candidates =
      catalog.buffs
          .where((buff) => selected.contains(buff.id) && !buff.referenceOnly)
          .toList()
        ..sort((a, b) {
          final priority = a.priority.compareTo(b.priority);
          return priority != 0 ? priority : a.id.compareTo(b.id);
        });
  final accepted = <Buff>[];
  for (final candidate in candidates) {
    if (!accepted.any(candidate.conflictsWith)) accepted.add(candidate);
  }
  return _immutableIds(accepted.map((buff) => buff.id));
}

Set<String> _immutableIds(Iterable<String> ids) =>
    Set.unmodifiable(ids.toSet().toList()..sort());

Iterable<String> _readIds(Object? value, String kind) {
  if (value == null) return const [];
  if (value is! List || value.any((id) => id is! String || id.isEmpty)) {
    throw FormatException(
      'Gathering preparation has a damaged $kind selection.',
    );
  }
  return value.cast<String>();
}

BairogCalculatorSettings _immutableSettings(
  BairogCalculatorSettings settings,
) => settings.copyWith(
  enabledExpenseItemIds: Set.unmodifiable(settings.enabledExpenseItemIds),
  dropTaxed: Map.unmodifiable(settings.dropTaxed),
  hiddenDropItemTypeIds: Set.unmodifiable(settings.hiddenDropItemTypeIds),
  customGathersPerHour: Map.unmodifiable(settings.customGathersPerHour),
  customItemPrices: Map.unmodifiable(settings.customItemPrices),
);
