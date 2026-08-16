import 'dart:math' as math;

import '../domain/models/craft_mode.dart';
import '../domain/planner/mastery_yields.dart';
import '../domain/state/planner_state.dart';
import '../domain/state/state_copy.dart';

const String firstRunSetupExtensionKey = 'blackSpiritLifeSetup';
const String firstRunSetupCompletedKey = 'setupCompleted';
const String firstRunSetupSchemaVersionKey = 'setupSchemaVersion';
const String firstRunSetupCompletedBetaVersionsKey = 'completedBetaVersions';
const String _formerNativeImportExtensionKey =
    'blackSpiritLifeFormerNativeImport';

enum FirstRunSetupGroup {
  masteryAndOutput(introducedInVersion: 1, title: 'Mastery'),
  afkLoad(introducedInVersion: 2, title: 'AFK Load'),
  marketSales(introducedInVersion: 1, title: 'Market sales');

  const FirstRunSetupGroup({
    required this.introducedInVersion,
    required this.title,
  });

  final int introducedInVersion;
  final String title;
}

abstract final class FirstRunSetupSchema {
  static const int currentVersion = 2;
  static const List<FirstRunSetupGroup> groups = FirstRunSetupGroup.values;
}

final class FirstRunSetupProgress {
  const FirstRunSetupProgress({
    required this.completed,
    required this.savedSchemaVersion,
    required this.pendingGroups,
  });

  factory FirstRunSetupProgress.fromDocument(
    PlannerState document, {
    String repeatForApplicationVersion = '',
  }) {
    final metadata = _setupMetadata(document);
    final completed = metadata[firstRunSetupCompletedKey] == true;
    final savedSchemaVersion = _nonNegativeInt(
      metadata[firstRunSetupSchemaVersionKey],
    );
    final completedBetaVersions = _completedBetaVersions(metadata);
    if (savedSchemaVersion > FirstRunSetupSchema.currentVersion) {
      return FirstRunSetupProgress(
        completed: completed,
        savedSchemaVersion: savedSchemaVersion,
        pendingGroups: const <FirstRunSetupGroup>[],
      );
    }

    final requestedApplicationVersion = repeatForApplicationVersion.trim();
    var pending =
        requestedApplicationVersion.isNotEmpty &&
            completed &&
            !completedBetaVersions.containsKey(requestedApplicationVersion)
        ? List<FirstRunSetupGroup>.unmodifiable(FirstRunSetupSchema.groups)
        : FirstRunSetupSchema.groups
              .where((group) => group.introducedInVersion > savedSchemaVersion)
              .toList(growable: false);
    if (!completed && pending.isEmpty) {
      pending = List<FirstRunSetupGroup>.unmodifiable(
        FirstRunSetupSchema.groups,
      );
    }
    return FirstRunSetupProgress(
      completed: completed,
      savedSchemaVersion: savedSchemaVersion,
      pendingGroups: pending,
    );
  }

  final bool completed;
  final int savedSchemaVersion;
  final List<FirstRunSetupGroup> pendingGroups;

  bool get shouldShow =>
      savedSchemaVersion <= FirstRunSetupSchema.currentVersion &&
      pendingGroups.isNotEmpty;
}

final class FirstRunSetupAnswers {
  const FirstRunSetupAnswers({
    required this.alchemyMastery,
    required this.cookingMastery,
    required this.processingMastery,
    required this.useMassProcessing,
    required this.maximumWeightLt,
    required this.currentCarriedWeightLt,
    required this.safetyBufferLt,
    required this.featheryStepsLevel,
    required this.valuePack,
    required this.merchantRing,
    required this.familyFameBonus,
  });

  factory FirstRunSetupAnswers.fromDocument(PlannerState document) =>
      FirstRunSetupAnswers(
        alchemyMastery: document.alchemy.alchemyMastery,
        cookingMastery: document.cooking.cookingMastery,
        processingMastery: document.processing.processingMastery,
        useMassProcessing: document.processing.useMassProcessing,
        maximumWeightLt: document.afkWeightProfile.maximumWeightLt,
        currentCarriedWeightLt:
            document.afkWeightProfile.currentCarriedWeightLt,
        safetyBufferLt: document.afkWeightProfile.safetyBufferLt,
        featheryStepsLevel: document.afkWeightProfile.featheryStepsLevel,
        valuePack: document.marketTax.valuePack,
        merchantRing: document.marketTax.merchantRing,
        familyFameBonus: document.marketTax.familyFameBonus,
      );

  /// Uses zeroes for the unconfirmed defaults written by the first private
  /// Beta, while retaining every imported or user-touched profile value.
  factory FirstRunSetupAnswers.forInitialDisplay(PlannerState document) {
    final answers = FirstRunSetupAnswers.fromDocument(document).normalized();
    final setupCompleted = FirstRunSetupProgress.fromDocument(
      document,
    ).completed;
    final importedProfile =
        document.origin != null ||
        document.extensions.containsKey(_formerNativeImportExtensionKey);
    final legacyFreshDefaults =
        answers.alchemyMastery ==
            alchemyMasteryForExpectedOutput(
              document.alchemy.compatibility.alchemyYield,
            ) &&
        answers.cookingMastery == 0 &&
        answers.processingMastery == 2;
    if (setupCompleted || importedProfile || !legacyFreshDefaults) {
      return answers;
    }
    return FirstRunSetupAnswers(
      alchemyMastery: 0,
      cookingMastery: 0,
      processingMastery: 0,
      useMassProcessing: answers.useMassProcessing,
      maximumWeightLt: answers.maximumWeightLt,
      currentCarriedWeightLt: answers.currentCarriedWeightLt,
      safetyBufferLt: answers.safetyBufferLt,
      featheryStepsLevel: answers.featheryStepsLevel,
      valuePack: answers.valuePack,
      merchantRing: answers.merchantRing,
      familyFameBonus: answers.familyFameBonus,
    );
  }

  final int alchemyMastery;
  final int cookingMastery;
  final int processingMastery;
  final bool useMassProcessing;
  final double maximumWeightLt;
  final double currentCarriedWeightLt;
  final double safetyBufferLt;
  final int featheryStepsLevel;
  final bool valuePack;
  final bool merchantRing;
  final double familyFameBonus;

  FirstRunSetupAnswers normalized() => FirstRunSetupAnswers(
    alchemyMastery: alchemyMastery.clamp(0, 3000),
    cookingMastery: cookingMastery.clamp(0, 3000),
    processingMastery: processingMastery.clamp(0, 3000),
    useMassProcessing: useMassProcessing,
    maximumWeightLt: _nonNegativeFinite(maximumWeightLt),
    currentCarriedWeightLt: _nonNegativeFinite(currentCarriedWeightLt),
    safetyBufferLt: _nonNegativeFinite(safetyBufferLt),
    featheryStepsLevel: featheryStepsLevel.clamp(0, 5),
    valuePack: valuePack,
    merchantRing: merchantRing,
    familyFameBonus: familyFameBonus.isFinite ? familyFameBonus : 0,
  );
}

PlannerState completeFirstRunSetupDocument(
  PlannerState document,
  FirstRunSetupAnswers answers, {
  required Iterable<FirstRunSetupGroup> groups,
  String completedForApplicationVersion = '',
}) {
  final normalized = answers.normalized();
  final submittedGroups = Set<FirstRunSetupGroup>.of(groups);
  final savedVersion = FirstRunSetupProgress.fromDocument(
    document,
  ).savedSchemaVersion;
  final submittedVersion = submittedGroups.fold<int>(
    savedVersion,
    (version, group) => math.max(version, group.introducedInVersion),
  );
  final includesMastery = submittedGroups.contains(
    FirstRunSetupGroup.masteryAndOutput,
  );
  final includesAfkLoad = submittedGroups.contains(FirstRunSetupGroup.afkLoad);
  final includesMarket = submittedGroups.contains(
    FirstRunSetupGroup.marketSales,
  );
  final completed = document.copyWith(
    alchemy: includesMastery
        ? normalized.alchemyMastery == document.alchemy.alchemyMastery
              ? document.alchemy
              : document.alchemy.copyWith(
                  alchemyMastery: normalized.alchemyMastery,
                  compatibility: document.alchemy.compatibility.copyWith(
                    alchemyYield: alchemyExpectedOutput(
                      normalized.alchemyMastery.toDouble(),
                      1,
                      4,
                    ),
                  ),
                )
        : document.alchemy,
    cooking: includesMastery
        ? normalized.cookingMastery == document.cooking.cookingMastery
              ? document.cooking
              : document.cooking.copyWith(
                  cookingMastery: normalized.cookingMastery,
                )
        : document.cooking,
    processing: includesMastery
        ? normalized.processingMastery ==
                      document.processing.processingMastery &&
                  normalized.useMassProcessing ==
                      document.processing.useMassProcessing
              ? document.processing
              : document.processing.copyWith(
                  processingMastery: normalized.processingMastery,
                  useMassProcessing: normalized.useMassProcessing,
                )
        : document.processing,
    afkWeightProfile: includesAfkLoad
        ? normalized.maximumWeightLt ==
                      document.afkWeightProfile.maximumWeightLt &&
                  normalized.currentCarriedWeightLt ==
                      document.afkWeightProfile.currentCarriedWeightLt &&
                  normalized.safetyBufferLt ==
                      document.afkWeightProfile.safetyBufferLt &&
                  normalized.featheryStepsLevel ==
                      document.afkWeightProfile.featheryStepsLevel
              ? document.afkWeightProfile
              : document.afkWeightProfile.copyWith(
                  maximumWeightLt: normalized.maximumWeightLt,
                  currentCarriedWeightLt: normalized.currentCarriedWeightLt,
                  safetyBufferLt: normalized.safetyBufferLt,
                  featheryStepsLevel: normalized.featheryStepsLevel,
                )
        : document.afkWeightProfile,
    marketTax: includesMarket
        ? normalized.valuePack == document.marketTax.valuePack &&
                  normalized.merchantRing == document.marketTax.merchantRing &&
                  normalized.familyFameBonus ==
                      document.marketTax.familyFameBonus
              ? document.marketTax
              : document.marketTax.copyWith(
                  valuePack: normalized.valuePack,
                  merchantRing: normalized.merchantRing,
                  familyFameBonus: normalized.familyFameBonus,
                )
        : document.marketTax,
    extensions: _withSetupMetadata(
      document,
      completed: true,
      schemaVersion: submittedVersion,
      completedForApplicationVersion: completedForApplicationVersion,
    ),
  );
  final activeModeState = completed.forMode(completed.activeMode);
  if (activeModeState.view == 'plan') return completed;
  return switch (completed.activeMode) {
    CraftMode.alchemy => completed.copyWith(
      alchemy: activeModeState.copyWith(view: 'plan'),
    ),
    CraftMode.cooking => completed.copyWith(
      cooking: activeModeState.copyWith(view: 'plan'),
    ),
    CraftMode.processing => completed.copyWith(
      processing: activeModeState.copyWith(view: 'plan'),
    ),
  };
}

double _nonNegativeFinite(double value) {
  if (!value.isFinite || value <= 0) return 0;
  return value;
}

/// Skipping dismisses setup only for the running session. In particular, a
/// repeated private-Beta setup must not erase a prior schema completion or its
/// completed-version history.
PlannerState deferFirstRunSetupDocument(PlannerState document) => document;

Map<String, Object?> _withSetupMetadata(
  PlannerState document, {
  required bool completed,
  required int schemaVersion,
  String completedForApplicationVersion = '',
}) {
  final extensions = Map<String, Object?>.of(document.extensions);
  final metadata = _setupMetadata(document);
  metadata[firstRunSetupCompletedKey] = completed;
  metadata[firstRunSetupSchemaVersionKey] = schemaVersion;
  final normalizedApplicationVersion = completedForApplicationVersion.trim();
  if (normalizedApplicationVersion.isNotEmpty) {
    final completedBetaVersions = _completedBetaVersions(metadata);
    completedBetaVersions[normalizedApplicationVersion] = schemaVersion;
    metadata[firstRunSetupCompletedBetaVersionsKey] = completedBetaVersions;
  }
  extensions[firstRunSetupExtensionKey] = metadata;
  return extensions;
}

Map<String, Object?> _setupMetadata(PlannerState document) {
  final value = document.extensions[firstRunSetupExtensionKey];
  if (value is! Map) return <String, Object?>{};
  return <String, Object?>{
    for (final entry in value.entries) entry.key.toString(): entry.value,
  };
}

Map<String, Object?> _completedBetaVersions(Map<String, Object?> metadata) {
  final value = metadata[firstRunSetupCompletedBetaVersionsKey];
  if (value is! Map) return <String, Object?>{};
  return <String, Object?>{
    for (final entry in value.entries) entry.key.toString(): entry.value,
  };
}

int _nonNegativeInt(Object? value) {
  if (value is int) return math.max(0, value);
  if (value is num && value.isFinite && value == value.roundToDouble()) {
    return math.max(0, value.toInt());
  }
  return 0;
}
