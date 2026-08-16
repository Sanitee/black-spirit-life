import 'dart:convert';

import 'package:bdo_craft_planner_flutter/app/first_run_setup.dart';
import 'package:bdo_craft_planner_flutter/domain/models/craft_mode.dart';
import 'package:bdo_craft_planner_flutter/domain/planner/mastery_yields.dart';
import 'package:bdo_craft_planner_flutter/domain/state/planner_state_json_codec.dart';
import 'package:bdo_craft_planner_flutter/domain/state/state_copy.dart';
import 'package:flutter_test/flutter_test.dart';

import '../domain/state/state_test_fixture.dart';

void main() {
  test('fresh and incomplete profiles show every current setup group', () {
    final document = buildStateFixture();

    final progress = FirstRunSetupProgress.fromDocument(document);

    expect(progress.completed, isFalse);
    expect(progress.savedSchemaVersion, 0);
    expect(progress.shouldShow, isTrue);
    expect(progress.pendingGroups, FirstRunSetupSchema.groups);
  });

  test(
    'legacy unconfirmed defaults display as zero without masking imports',
    () {
      final source = buildStateFixture();
      final sourceJson = Map<String, Object?>.of(source.toJson())
        ..remove('origin');
      final withoutOrigin = const PlannerStateJsonCodec().decode(
        jsonEncode(sourceJson),
      );
      final legacyFresh = withoutOrigin.copyWith(
        alchemy: source.alchemy.copyWith(
          alchemyMastery: alchemyMasteryForExpectedOutput(
            source.alchemy.compatibility.alchemyYield,
          ),
        ),
        cooking: source.cooking.copyWith(cookingMastery: 0),
        processing: source.processing.copyWith(processingMastery: 2),
      );

      final displayed = FirstRunSetupAnswers.forInitialDisplay(legacyFresh);

      expect(displayed.alchemyMastery, 0);
      expect(displayed.cookingMastery, 0);
      expect(displayed.processingMastery, 0);

      final deferred = deferFirstRunSetupDocument(legacyFresh);
      final redisplayed = FirstRunSetupAnswers.forInitialDisplay(deferred);
      expect(redisplayed.alchemyMastery, 0);
      expect(redisplayed.cookingMastery, 0);
      expect(redisplayed.processingMastery, 0);

      final importedExtensions = Map<String, Object?>.of(legacyFresh.extensions)
        ..['blackSpiritLifeFormerNativeImport'] = <String, Object?>{
          'version': 1,
        };
      final imported = legacyFresh.copyWith(extensions: importedExtensions);
      final preserved = FirstRunSetupAnswers.forInitialDisplay(imported);

      expect(preserved.alchemyMastery, legacyFresh.alchemy.alchemyMastery);
      expect(preserved.cookingMastery, 0);
      expect(preserved.processingMastery, 2);
    },
  );

  test(
    'current completion hides setup and future metadata is not downgraded',
    () {
      final document = buildStateFixture();
      final completed = completeFirstRunSetupDocument(
        document,
        FirstRunSetupAnswers.fromDocument(document),
        groups: FirstRunSetupSchema.groups,
      );
      final current = FirstRunSetupProgress.fromDocument(completed);
      expect(current.completed, isTrue);
      expect(current.savedSchemaVersion, FirstRunSetupSchema.currentVersion);
      expect(current.shouldShow, isFalse);

      final futureExtensions = Map<String, Object?>.of(document.extensions)
        ..[firstRunSetupExtensionKey] = <String, Object?>{
          firstRunSetupCompletedKey: false,
          firstRunSetupSchemaVersionKey: FirstRunSetupSchema.currentVersion + 1,
          'futureSetupField': 'kept',
        };
      final future = FirstRunSetupProgress.fromDocument(
        document.copyWith(extensions: futureExtensions),
      );
      expect(future.shouldShow, isFalse);
      expect(future.pendingGroups, isEmpty);
    },
  );

  test('successful setup opens Planner without changing inactive views', () {
    final fixture = buildStateFixture();
    final document = fixture.copyWith(
      activeMode: CraftMode.cooking,
      alchemy: fixture.alchemy.copyWith(view: 'editor'),
      cooking: fixture.cooking.copyWith(view: 'data'),
      processing: fixture.processing.copyWith(view: 'book'),
    );

    final completed = completeFirstRunSetupDocument(
      document,
      FirstRunSetupAnswers.fromDocument(document),
      groups: FirstRunSetupSchema.groups,
      completedForApplicationVersion: '0.1.0-beta.7',
    );

    expect(completed.activeMode, CraftMode.cooking);
    expect(completed.cooking.view, 'plan');
    expect(completed.alchemy.view, 'editor');
    expect(completed.processing.view, 'book');
  });

  test('private Beta repeats every setup group once per app version', () {
    final document = buildStateFixture();
    final completedForBetaFive = completeFirstRunSetupDocument(
      document,
      FirstRunSetupAnswers.fromDocument(document),
      groups: FirstRunSetupSchema.groups,
      completedForApplicationVersion: '0.1.0-beta.5',
    );

    final sameVersion = FirstRunSetupProgress.fromDocument(
      completedForBetaFive,
      repeatForApplicationVersion: '0.1.0-beta.5',
    );
    expect(sameVersion.shouldShow, isFalse);

    final nextVersion = FirstRunSetupProgress.fromDocument(
      completedForBetaFive,
      repeatForApplicationVersion: '0.1.0-beta.6',
    );
    expect(nextVersion.shouldShow, isTrue);
    expect(nextVersion.pendingGroups, FirstRunSetupSchema.groups);

    final completedForBetaSix = completeFirstRunSetupDocument(
      completedForBetaFive,
      FirstRunSetupAnswers.fromDocument(completedForBetaFive),
      groups: nextVersion.pendingGroups,
      completedForApplicationVersion: '0.1.0-beta.6',
    );
    final metadata =
        completedForBetaSix.extensions[firstRunSetupExtensionKey] as Map;
    expect(
      (metadata[firstRunSetupCompletedBetaVersionsKey] as Map)['0.1.0-beta.6'],
      FirstRunSetupSchema.currentVersion,
    );
    expect(
      FirstRunSetupProgress.fromDocument(
        completedForBetaSix,
        repeatForApplicationVersion: '0.1.0-beta.6',
      ).shouldShow,
      isFalse,
    );
    expect(
      FirstRunSetupProgress.fromDocument(completedForBetaSix).shouldShow,
      isFalse,
      reason: 'Stable keeps schema-based setup behavior.',
    );
    expect(
      FirstRunSetupProgress.fromDocument(
        completedForBetaSix,
        repeatForApplicationVersion: '0.1.0-beta.5',
      ).shouldShow,
      isFalse,
      reason: 'Rollback and re-upgrade do not repeat an already tested Beta.',
    );
  });

  test('unchanged repeated Beta setup only updates setup metadata', () {
    final fixture = buildStateFixture();
    final source = completeFirstRunSetupDocument(
      fixture.copyWith(
        alchemy: fixture.alchemy.copyWith(
          alchemyMastery: 1937,
          compatibility: fixture.alchemy.compatibility.copyWith(
            alchemyYield: 3.14159,
          ),
        ),
        cooking: fixture.cooking.copyWith(cookingMastery: 842),
        processing: fixture.processing.copyWith(
          processingMastery: 1264,
          useMassProcessing: true,
        ),
        afkWeightProfile: fixture.afkWeightProfile.copyWith(
          maximumWeightLt: 1750.125,
          currentCarriedWeightLt: 80.25,
          safetyBufferLt: 25.5,
          featheryStepsLevel: 2,
        ),
        marketTax: fixture.marketTax.copyWith(
          enabled: false,
          valuePack: false,
          merchantRing: true,
          familyFameBonus: .0125,
        ),
      ),
      FirstRunSetupAnswers.fromDocument(fixture),
      groups: const <FirstRunSetupGroup>[],
      completedForApplicationVersion: '0.1.0-beta.5',
    );

    final repeated = completeFirstRunSetupDocument(
      source,
      FirstRunSetupAnswers.fromDocument(source),
      groups: FirstRunSetupSchema.groups,
      completedForApplicationVersion: '0.1.0-beta.6',
    );

    expect(identical(repeated.alchemy, source.alchemy), isTrue);
    expect(identical(repeated.cooking, source.cooking), isTrue);
    expect(identical(repeated.processing, source.processing), isTrue);
    expect(
      identical(repeated.afkWeightProfile, source.afkWeightProfile),
      isTrue,
    );
    expect(identical(repeated.marketTax, source.marketTax), isTrue);
    expect(repeated.alchemy.compatibility.alchemyYield, 3.14159);
    expect(repeated.marketTax.enabled, isFalse);
  });

  test('skip preserves answers and unknown extension data', () {
    final document = buildStateFixture();
    final extensions = Map<String, Object?>.of(document.extensions)
      ..[firstRunSetupExtensionKey] = <String, Object?>{
        firstRunSetupSchemaVersionKey: 0,
        'futureSetupField': <String>['alpha', 'beta'],
      };
    final source = document.copyWith(extensions: extensions);

    final deferred = deferFirstRunSetupDocument(source);

    expect(identical(deferred, source), isTrue);
    expect(identical(deferred.alchemy, source.alchemy), isTrue);
    expect(identical(deferred.cooking, source.cooking), isTrue);
    expect(identical(deferred.processing, source.processing), isTrue);
    expect(identical(deferred.marketTax, source.marketTax), isTrue);
    expect(
      identical(deferred.afkWeightProfile, source.afkWeightProfile),
      isTrue,
    );
    expect(deferred.extensions['rootFuture'], source.extensions['rootFuture']);
    final metadata = deferred.extensions[firstRunSetupExtensionKey] as Map;
    expect(metadata[firstRunSetupCompletedKey], isNull);
    expect(metadata[firstRunSetupSchemaVersionKey], 0);
    expect(metadata['futureSetupField'], <String>['alpha', 'beta']);
    expect(FirstRunSetupProgress.fromDocument(deferred).shouldShow, isTrue);
  });

  test(
    'skipping a repeated Beta setup preserves prior completion metadata',
    () {
      final document = buildStateFixture();
      final completed = completeFirstRunSetupDocument(
        document,
        FirstRunSetupAnswers.fromDocument(document),
        groups: FirstRunSetupSchema.groups,
        completedForApplicationVersion: '0.1.0-beta.5',
      );

      final deferred = deferFirstRunSetupDocument(completed);

      expect(identical(deferred, completed), isTrue);
      expect(FirstRunSetupProgress.fromDocument(deferred).completed, isTrue);
      expect(
        FirstRunSetupProgress.fromDocument(deferred).shouldShow,
        isFalse,
        reason: 'Stable/schema completion is not erased by a Beta skip.',
      );
      expect(
        FirstRunSetupProgress.fromDocument(
          deferred,
          repeatForApplicationVersion: '0.1.0-beta.6',
        ).shouldShow,
        isTrue,
        reason: 'The skipped Beta version remains pending next launch.',
      );
      final metadata = deferred.extensions[firstRunSetupExtensionKey] as Map;
      expect(
        (metadata[firstRunSetupCompletedBetaVersionsKey] as Map).keys,
        <Object?>['0.1.0-beta.5'],
      );
    },
  );

  test('finish clamps mastery, applies answers, and preserves other state', () {
    final document = buildStateFixture();
    final extensions = Map<String, Object?>.of(document.extensions)
      ..[firstRunSetupExtensionKey] = <String, Object?>{'futureSetupField': 42};
    final source = document.copyWith(extensions: extensions);

    final completed = completeFirstRunSetupDocument(
      source,
      const FirstRunSetupAnswers(
        alchemyMastery: 4000,
        cookingMastery: -10,
        processingMastery: 1275,
        useMassProcessing: false,
        maximumWeightLt: 1845.5,
        currentCarriedWeightLt: -10,
        safetyBufferLt: double.infinity,
        featheryStepsLevel: 9,
        valuePack: false,
        merchantRing: true,
        familyFameBonus: .0125,
      ),
      groups: FirstRunSetupSchema.groups,
    );

    expect(completed.alchemy.alchemyMastery, 3000);
    expect(
      completed.alchemy.compatibility.alchemyYield,
      alchemyExpectedOutput(3000, 1, 4),
    );
    expect(completed.cooking.cookingMastery, 0);
    expect(completed.processing.processingMastery, 1275);
    expect(completed.processing.useMassProcessing, isFalse);
    expect(completed.afkWeightProfile.maximumWeightLt, 1845.5);
    expect(completed.afkWeightProfile.currentCarriedWeightLt, 0);
    expect(completed.afkWeightProfile.safetyBufferLt, 0);
    expect(completed.afkWeightProfile.featheryStepsLevel, 5);
    expect(
      completed.afkWeightProfile.extensions,
      source.afkWeightProfile.extensions,
    );
    expect(completed.marketTax.enabled, isTrue);
    expect(completed.marketTax.valuePack, isFalse);
    expect(completed.marketTax.merchantRing, isTrue);
    expect(completed.marketTax.familyFameBonus, .0125);
    expect(completed.alchemy.target, source.alchemy.target);
    expect(completed.alchemy.inventory, source.alchemy.inventory);
    expect(completed.alchemy.extensions, source.alchemy.extensions);
    expect(completed.marketTax.extensions, source.marketTax.extensions);
    expect(completed.extensions['rootFuture'], source.extensions['rootFuture']);
    final metadata = completed.extensions[firstRunSetupExtensionKey] as Map;
    expect(metadata[firstRunSetupCompletedKey], isTrue);
    expect(
      metadata[firstRunSetupSchemaVersionKey],
      FirstRunSetupSchema.currentVersion,
    );
    expect(metadata['futureSetupField'], 42);
  });

  test('setup metadata survives native JSON persistence', () {
    const codec = PlannerStateJsonCodec();
    final source = buildStateFixture();
    final completed = completeFirstRunSetupDocument(
      source,
      FirstRunSetupAnswers.fromDocument(source),
      groups: FirstRunSetupSchema.groups,
    );

    final decoded = codec.decode(codec.encode(completed));

    final progress = FirstRunSetupProgress.fromDocument(decoded);
    expect(progress.completed, isTrue);
    expect(progress.savedSchemaVersion, FirstRunSetupSchema.currentVersion);
    expect(progress.shouldShow, isFalse);
    expect(decoded.extensions['rootFuture'], <int>[1, 2]);
  });

  test(
    'schema one completion asks only for AFK Load and preserves old groups',
    () {
      final document = buildStateFixture();
      final extensions = Map<String, Object?>.of(document.extensions)
        ..[firstRunSetupExtensionKey] = <String, Object?>{
          firstRunSetupCompletedKey: true,
          firstRunSetupSchemaVersionKey: 1,
          'futureSetupField': 'kept',
        };
      final source = document.copyWith(
        alchemy: document.alchemy.copyWith(
          alchemyMastery: 1937,
          compatibility: document.alchemy.compatibility.copyWith(
            alchemyYield: 3.14159,
          ),
        ),
        cooking: document.cooking.copyWith(cookingMastery: 842),
        processing: document.processing.copyWith(
          processingMastery: 1264,
          useMassProcessing: true,
        ),
        marketTax: document.marketTax.copyWith(
          enabled: false,
          valuePack: false,
          merchantRing: true,
          familyFameBonus: .0125,
        ),
        afkWeightProfile: document.afkWeightProfile.copyWith(
          extensions: const <String, Object?>{'futureAfkField': 'kept'},
        ),
        extensions: extensions,
      );
      final progress = FirstRunSetupProgress.fromDocument(source);

      expect(progress.shouldShow, isTrue);
      expect(progress.pendingGroups, const <FirstRunSetupGroup>[
        FirstRunSetupGroup.afkLoad,
      ]);

      final completed = completeFirstRunSetupDocument(
        source,
        const FirstRunSetupAnswers(
          alchemyMastery: 0,
          cookingMastery: 0,
          processingMastery: 0,
          useMassProcessing: false,
          maximumWeightLt: 2050.5,
          currentCarriedWeightLt: 112.25,
          safetyBufferLt: 35,
          featheryStepsLevel: 4,
          valuePack: true,
          merchantRing: false,
          familyFameBonus: 0,
        ),
        groups: progress.pendingGroups,
      );

      expect(completed.alchemy.view, 'plan');
      expect(completed.alchemy.alchemyMastery, source.alchemy.alchemyMastery);
      expect(
        completed.alchemy.compatibility.alchemyYield,
        source.alchemy.compatibility.alchemyYield,
      );
      expect(identical(completed.cooking, source.cooking), isTrue);
      expect(identical(completed.processing, source.processing), isTrue);
      expect(identical(completed.marketTax, source.marketTax), isTrue);
      expect(completed.afkWeightProfile.maximumWeightLt, 2050.5);
      expect(completed.afkWeightProfile.currentCarriedWeightLt, 112.25);
      expect(completed.afkWeightProfile.safetyBufferLt, 35);
      expect(completed.afkWeightProfile.featheryStepsLevel, 4);
      expect(completed.afkWeightProfile.extensions, const <String, Object?>{
        'futureAfkField': 'kept',
      });
      final completedProgress = FirstRunSetupProgress.fromDocument(completed);
      expect(completedProgress.completed, isTrue);
      expect(completedProgress.savedSchemaVersion, 2);
      expect(completedProgress.shouldShow, isFalse);
      final metadata = completed.extensions[firstRunSetupExtensionKey] as Map;
      expect(metadata['futureSetupField'], 'kept');
    },
  );
}
