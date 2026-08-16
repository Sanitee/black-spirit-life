import 'dart:convert';
import 'dart:io';

import 'package:bdo_craft_planner_flutter/app_identity.dart';
import 'package:bdo_craft_planner_flutter/data/persistence/planner_state_repository.dart';
import 'package:bdo_craft_planner_flutter/domain/models/catalog_models.dart';
import 'package:bdo_craft_planner_flutter/domain/models/craft_mode.dart';
import 'package:bdo_craft_planner_flutter/domain/planner/mastery_yields.dart';
import 'package:bdo_craft_planner_flutter/domain/state/planner_state.dart';
import 'package:bdo_craft_planner_flutter/domain/state/state_copy.dart';
import 'package:bdo_craft_planner_flutter/visual/sakura_night_garden/sakura_spec.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory temp;
  late Directory appDirectory;
  late Directory formerNativeDirectory;
  late File legacyState;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('bdo-state-repository-');
    appDirectory = Directory('${temp.path}${Platform.pathSeparator}flutter');
    formerNativeDirectory = Directory(
      '${temp.path}${Platform.pathSeparator}map-candidate',
    );
    legacyState = File(
      '${temp.path}${Platform.pathSeparator}legacy${Platform.pathSeparator}planner-state.json',
    );
  });

  tearDown(() async {
    if (await temp.exists()) await temp.delete(recursive: true);
  });

  test(
    'public environment policy starts clean and keeps former profiles separate',
    () {
      final paths = PlannerStatePathPolicy.fromEnvironment({
        'APPDATA': temp.path,
      });

      expect(
        paths.applicationDirectory.path,
        '${temp.path}${Platform.pathSeparator}'
        '${AppIdentity.stateDirectoryName}',
      );
      expect(paths.formerNativeApplicationDirectory, isNull);
      expect(paths.allowLegacyMigration, isFalse);
      expect(
        paths.legacyStateFile.path,
        '${temp.path}${Platform.pathSeparator}BDO Craft Planner Avalonia'
        '${Platform.pathSeparator}planner-state.json',
      );
      expect(
        paths.applicationDirectory.path,
        isNot('${temp.path}${Platform.pathSeparator}BDO Craft Planner Flutter'),
      );
      expect(AppIdentity.importFormerProfilesOnFirstLaunch, isFalse);
    },
  );

  test(
    'public first start ignores valid former and legacy personal profiles',
    () async {
      final paths = PlannerStatePathPolicy.fromEnvironment({
        'APPDATA': temp.path,
      });
      final formerDirectory = Directory(
        '${temp.path}${Platform.pathSeparator}'
        '${AppIdentity.formerStateDirectoryName}',
      );
      final formerRepository = _repository(
        formerDirectory,
        File('${temp.path}${Platform.pathSeparator}unused-former-legacy.json'),
      );
      final former = await formerRepository.load(_catalog());
      await formerRepository.save(
        former.state.copyWith(
          alchemy: former.state.alchemy.copyWith(
            alchemyMastery: 2345,
            inventory: const <String, double>{'Base': 42},
            favoriteRecipes: const <String>['Former favorite'],
          ),
        ),
      );
      final formerBytes = await formerRepository.nativeStateFile.readAsBytes();
      final legacyBytes = await _writeSyntheticLegacy(paths.legacyStateFile);
      final repository = PlannerStateRepository(
        paths: paths,
        applicationVersion: 'test',
        utcNow: () => DateTime.utc(2026, 7, 20, 12),
      );

      final result = await repository.load(_catalog());

      expect(result.origin, PlannerStateLoadOrigin.fresh);
      expect(result.migrationPreview, isNull);
      for (final mode in CraftMode.values) {
        final state = result.state.forMode(mode);
        expect(state.inventory, isEmpty);
        expect(state.favoriteRecipes, isEmpty);
        expect(state.completedSteps, isEmpty);
        expect(state.recipeEdits, isEmpty);
        expect(state.customIcons, isEmpty);
      }
      expect(result.state.alchemy.alchemyMastery, 0);
      expect(result.state.cooking.cookingMastery, 0);
      expect(result.state.processing.processingMastery, 0);
      expect(await formerRepository.nativeStateFile.readAsBytes(), formerBytes);
      expect(await paths.legacyStateFile.readAsBytes(), legacyBytes);
    },
  );

  test(
    'first Beta start copies former native state and leaves source untouched',
    () async {
      final formerRepository = _repository(formerNativeDirectory, legacyState);
      final former = await formerRepository.load(_catalog());
      await formerRepository.save(
        former.state.copyWith(
          activeMode: CraftMode.cooking,
          cooking: former.state.cooking.copyWith(
            cookingMastery: 1777,
            inventory: const <String, double>{'Base': 42},
          ),
        ),
      );
      final sourceBytes = await formerRepository.nativeStateFile.readAsBytes();
      final sourceHash = sha256.convert(sourceBytes).toString();
      final repository = _repository(
        appDirectory,
        legacyState,
        formerNative: formerNativeDirectory,
      );

      final imported = await repository.load(_catalog());

      expect(imported.origin, PlannerStateLoadOrigin.importedFormerNative);
      expect(imported.state.activeMode, CraftMode.cooking);
      expect(imported.state.cooking.cookingMastery, 1777);
      expect(imported.state.cooking.inventory['Base'], 42);
      expect(imported.sourceUnchangedAfterMigration, isTrue);
      expect(
        sha256
            .convert(await formerRepository.nativeStateFile.readAsBytes())
            .toString(),
        sourceHash,
      );
      expect(
        imported.state.extensions[PlannerStateRepository
            .formerNativeImportMarkerKey],
        isA<Map<String, Object?>>(),
      );
      final archives = await _migrationArchives(appDirectory);
      expect(
        archives.map((file) => file.uri.pathSegments.last),
        contains('map-candidate-native-$sourceHash.json'),
      );

      final restarted = await repository.load(_catalog());
      expect(restarted.origin, PlannerStateLoadOrigin.native);
      expect(restarted.state.cooking.cookingMastery, 1777);
    },
  );

  test(
    'intentional uninstall reset starts empty and never reimports former data',
    () async {
      final formerRepository = _repository(formerNativeDirectory, legacyState);
      final former = await formerRepository.load(_catalog());
      await formerRepository.save(
        former.state.copyWith(
          alchemy: former.state.alchemy.copyWith(
            alchemyMastery: 2345,
            inventory: const <String, double>{'Pure Powder Reagent': 99},
            favoriteRecipes: const <String>['Former favorite'],
          ),
        ),
      );
      final sourceBytes = await formerRepository.nativeStateFile.readAsBytes();
      await appDirectory.create(recursive: true);
      await File(
        '${appDirectory.path}${Platform.pathSeparator}'
        '${AppIdentity.intentionalResetMarkerFileName}',
      ).writeAsString(
        jsonEncode(const <String, Object?>{
          'schemaVersion': 1,
          'packageId': AppIdentity.installerPackageId,
          'releaseChannel': AppIdentity.releaseChannel,
          'intentionalReset': true,
          'transactionId': 'reset-test',
        }),
        flush: true,
      );

      final repository = _repository(
        appDirectory,
        legacyState,
        formerNative: formerNativeDirectory,
      );
      final result = await repository.load(_catalog());

      expect(result.origin, PlannerStateLoadOrigin.fresh);
      expect(result.state.alchemy.alchemyMastery, 0);
      expect(result.state.alchemy.inventory, isEmpty);
      expect(result.state.alchemy.favoriteRecipes, isEmpty);
      expect(await formerRepository.nativeStateFile.readAsBytes(), sourceBytes);
      expect(
        result.notices,
        contains(
          'Started with empty planner data after the previous uninstall '
          'explicitly removed its personal files.',
        ),
      );
      expect(
        (await repository.load(_catalog())).origin,
        PlannerStateLoadOrigin.native,
      );
    },
  );

  test('existing Beta state always wins over the former profile', () async {
    final formerRepository = _repository(formerNativeDirectory, legacyState);
    final former = await formerRepository.load(_catalog());
    await formerRepository.save(
      former.state.copyWith(
        cooking: former.state.cooking.copyWith(cookingMastery: 1111),
      ),
    );
    final repository = _repository(
      appDirectory,
      legacyState,
      formerNative: formerNativeDirectory,
    );
    final beta = await PlannerStateRepository(
      paths: PlannerStatePathPolicy(
        applicationDirectory: appDirectory,
        legacyStateFile: legacyState,
      ),
      applicationVersion: 'test',
    ).load(_catalog());
    await repository.save(
      beta.state.copyWith(
        cooking: beta.state.cooking.copyWith(cookingMastery: 2222),
      ),
    );

    final loaded = await repository.load(_catalog());

    expect(loaded.origin, PlannerStateLoadOrigin.native);
    expect(loaded.state.cooking.cookingMastery, 2222);
  });

  test(
    'invalid former native state never creates or edits a Beta profile',
    () async {
      final formerFile = File(
        '${formerNativeDirectory.path}${Platform.pathSeparator}'
        '${PlannerStateRepository.stateFileName}',
      );
      await formerFile.parent.create(recursive: true);
      const invalidBytes = <int>[0x7b, 0x62, 0x61, 0x64, 0x7d];
      await formerFile.writeAsBytes(invalidBytes, flush: true);
      final repository = _repository(
        appDirectory,
        legacyState,
        formerNative: formerNativeDirectory,
      );

      await expectLater(repository.load(_catalog()), throwsFormatException);

      expect(await repository.nativeStateFile.exists(), isFalse);
      expect(await formerFile.readAsBytes(), invalidBytes);
      expect(await _migrationArchives(appDirectory), isEmpty);
    },
  );

  test('fresh state is committed to the distinct Flutter path', () async {
    final repository = _repository(appDirectory, legacyState);
    final result = await repository.load(_catalog());

    expect(result.origin, PlannerStateLoadOrigin.fresh);
    expect(result.state.alchemy.target, 'Alchemy Target');
    expect(result.state.alchemy.alchemyMastery, 0);
    expect(
      result.state.alchemy.compatibility.alchemyYield,
      alchemyExpectedOutput(0, 1, 4),
    );
    expect(result.state.cooking.cookingMastery, 0);
    expect(result.state.processing.processingMastery, 0);
    expect(result.state.afkWeightProfile.maximumWeightLt, 0);
    expect(result.state.afkWeightProfile.currentCarriedWeightLt, 0);
    expect(result.state.afkWeightProfile.safetyBufferLt, 0);
    expect(result.state.afkWeightProfile.featheryStepsLevel, 0);
    for (final mode in CraftMode.values) {
      final modeState = result.state.forMode(mode);
      expect(modeState.inventory, isEmpty);
      expect(modeState.favoriteRecipes, isEmpty);
      expect(modeState.completedSteps, isEmpty);
      final appearance = result.state.forMode(mode).appearance;
      expect(appearance.background, SakuraNightGardenSpec.backgroundId);
      expect(appearance.particleStyle, 'petals');
      expect(appearance.accentHue, 341);
    }
    expect(
      result.state.extensions[PlannerStateRepository
          .sakuraDefaultMigrationMarkerKey],
      PlannerStateRepository.sakuraDefaultMigrationVersion,
    );
    expect(await repository.nativeStateFile.exists(), isTrue);
    expect(await legacyState.exists(), isFalse);
  });

  test('fresh state never copies bundled personal defaults', () async {
    final repository = _repository(appDirectory, legacyState);
    final result = await repository.load(
      CatalogSnapshot(
        sourceSha256: 'personal-default-fixture',
        sourceByteCount: 1,
        alchemy: _mode(
          CraftMode.alchemy,
          'Alchemy Target',
          3.2,
          defaultInventory: const <String, double>{'Bundled Alchemy': 42},
        ),
        cooking: _mode(
          CraftMode.cooking,
          'Cooking Target',
          1,
          defaultInventory: const <String, double>{'Bundled Cooking': 24},
        ),
        processing: _mode(
          CraftMode.processing,
          'Processing Target',
          1,
          defaultInventory: const <String, double>{'Bundled Processing': 12},
        ),
        supportingData: const {},
        collisions: const [],
      ),
    );

    for (final mode in CraftMode.values) {
      final modeState = result.state.forMode(mode);
      expect(modeState.inventory, isEmpty);
      expect(modeState.favoriteRecipes, isEmpty);
    }
  });

  test('native save and restart retain Sakura for all workstations', () async {
    final repository = _repository(appDirectory, legacyState);
    final fresh = await repository.load(_catalog());
    AppearanceSettings sakura() => AppearanceSettings(
      background: SakuraNightGardenSpec.backgroundId,
      particleStyle: 'petals',
      particleMinSize: .68,
      particleMaxSize: 1.5,
      particleHue: 341,
      buttonEffect: 'glow',
      buttonEffectHue: 341,
      accentHue: 341,
    );
    final themed = fresh.state.copyWith(
      alchemy: fresh.state.alchemy.copyWith(appearance: sakura()),
      cooking: fresh.state.cooking.copyWith(appearance: sakura()),
      processing: fresh.state.processing.copyWith(appearance: sakura()),
    );

    await repository.save(themed);
    final restarted = await repository.load(_catalog());

    expect(restarted.origin, PlannerStateLoadOrigin.native);
    for (final mode in CraftMode.values) {
      expect(
        restarted.state.forMode(mode).appearance.background,
        SakuraNightGardenSpec.backgroundId,
      );
    }
  });

  test('native save and restart retain explicit AFK craft progress', () async {
    final repository = _repository(appDirectory, legacyState);
    final fresh = await repository.load(_catalog());
    final key = AfkCraftProgress.storageKeyFor('Alchemy Target');
    final progress = AfkCraftProgress(
      stepKey: key,
      targetName: 'Alchemy Target',
      targetAmount: 100,
      recipeName: 'Alchemy Target',
      planSignature: 'alchemy-target:v1',
      totalAttempts: 100,
      attemptsPerRound: 30,
      completedAttempts: 70,
    );

    await repository.save(
      fresh.state.copyWith(
        alchemy: fresh.state.alchemy.copyWith(
          afkCraftProgress: {key: progress},
        ),
      ),
    );
    final restarted = await repository.load(_catalog());

    expect(restarted.origin, PlannerStateLoadOrigin.native);
    expect(
      restarted.state.alchemy.afkCraftProgress[key]?.toJson(),
      progress.toJson(),
    );
  });

  test(
    'one-time native migration upgrades an unmarked all-Greenhouse appearance',
    () async {
      final repository = _repository(appDirectory, legacyState);
      final fresh = await repository.load(_catalog());
      final greenhouse = AppearanceSettings.classicDefaultsFor(
        CraftMode.alchemy,
      );
      final legacyNative = _withoutSakuraMigrationMarker(
        fresh.state.copyWith(
          alchemy: fresh.state.alchemy.copyWith(appearance: greenhouse),
          cooking: fresh.state.cooking.copyWith(appearance: greenhouse),
          processing: fresh.state.processing.copyWith(appearance: greenhouse),
        ),
      );
      await repository.nativeStateFile.writeAsString(
        repository.codec.encode(legacyNative),
        flush: true,
      );

      final upgraded = await repository.load(_catalog());

      expect(upgraded.origin, PlannerStateLoadOrigin.native);
      for (final mode in CraftMode.values) {
        final appearance = upgraded.state.forMode(mode).appearance;
        expect(appearance.background, SakuraNightGardenSpec.backgroundId);
        expect(appearance.particleStyle, 'petals');
        expect(appearance.accentHue, 341);
      }
      expect(
        upgraded.state.extensions[PlannerStateRepository
            .sakuraDefaultMigrationMarkerKey],
        PlannerStateRepository.sakuraDefaultMigrationVersion,
      );
      expect(
        upgraded.notices,
        contains(
          'Updated the unmarked all-Greenhouse appearance to Sakura '
          'Night Garden while preserving its custom controls. This '
          'one-time update will not replace later theme choices.',
        ),
      );
    },
  );

  test(
    'custom all-Greenhouse controls survive the Sakura identity upgrade',
    () async {
      final repository = _repository(appDirectory, legacyState);
      final fresh = await repository.load(_catalog());
      final customAlchemy = _customGreenhouseAppearance(1);
      final customCooking = _customGreenhouseAppearance(2);
      final customProcessing = _customGreenhouseAppearance(3);
      final legacyNative = _withoutSakuraMigrationMarker(
        fresh.state.copyWith(
          alchemy: fresh.state.alchemy.copyWith(appearance: customAlchemy),
          cooking: fresh.state.cooking.copyWith(appearance: customCooking),
          processing: fresh.state.processing.copyWith(
            appearance: customProcessing,
          ),
        ),
      );
      final controlsBefore = <CraftMode, Map<String, Object?>>{
        for (final mode in CraftMode.values)
          mode: _withoutSakuraIdentity(legacyNative.forMode(mode).appearance),
      };
      await repository.nativeStateFile.writeAsString(
        repository.codec.encode(legacyNative),
        flush: true,
      );

      final loaded = await repository.load(_catalog());

      for (final mode in CraftMode.values) {
        final appearance = loaded.state.forMode(mode).appearance;
        expect(appearance.background, SakuraNightGardenSpec.backgroundId);
        expect(appearance.particleStyle, 'petals');
        expect(appearance.accentHue, 341);
        expect(_withoutSakuraIdentity(appearance), controlsBefore[mode]);
      }
      expect(
        loaded.state.extensions[PlannerStateRepository
            .sakuraDefaultMigrationMarkerKey],
        PlannerStateRepository.sakuraDefaultMigrationVersion,
      );
      expect(
        loaded.notices,
        contains(
          'Updated the unmarked all-Greenhouse appearance to Sakura '
          'Night Garden while preserving its custom controls. This '
          'one-time update will not replace later theme choices.',
        ),
      );
    },
  );

  test('mixed-background profiles are marked but preserved exactly', () async {
    final repository = _repository(appDirectory, legacyState);
    final fresh = await repository.load(_catalog());
    final legacyNative = _withoutSakuraMigrationMarker(
      fresh.state.copyWith(
        alchemy: fresh.state.alchemy.copyWith(
          appearance: _customGreenhouseAppearance(1),
        ),
        cooking: fresh.state.cooking.copyWith(
          appearance: AppearanceSettings.defaultsFor(CraftMode.cooking),
        ),
        processing: fresh.state.processing.copyWith(
          appearance: _customGreenhouseAppearance(3),
        ),
      ),
    );
    final before = <CraftMode, Map<String, Object?>>{
      for (final mode in CraftMode.values)
        mode: legacyNative.forMode(mode).appearance.toJson(),
    };
    await repository.nativeStateFile.writeAsString(
      repository.codec.encode(legacyNative),
      flush: true,
    );

    final loaded = await repository.load(_catalog());

    for (final mode in CraftMode.values) {
      expect(loaded.state.forMode(mode).appearance.toJson(), before[mode]);
    }
    expect(
      loaded.state.extensions[PlannerStateRepository
          .sakuraDefaultMigrationMarkerKey],
      PlannerStateRepository.sakuraDefaultMigrationVersion,
    );
    expect(
      loaded.notices,
      isNot(
        contains(
          'Updated the unmarked all-Greenhouse appearance to Sakura '
          'Night Garden while preserving its custom controls.',
        ),
      ),
    );
  });

  test(
    'completed migration never replaces a later deliberate Greenhouse choice',
    () async {
      final repository = _repository(appDirectory, legacyState);
      final fresh = await repository.load(_catalog());
      final greenhouse = AppearanceSettings.classicDefaultsFor(
        CraftMode.alchemy,
      );
      final legacyNative = _withoutSakuraMigrationMarker(
        fresh.state.copyWith(
          alchemy: fresh.state.alchemy.copyWith(appearance: greenhouse),
          cooking: fresh.state.cooking.copyWith(appearance: greenhouse),
          processing: fresh.state.processing.copyWith(appearance: greenhouse),
        ),
      );
      await repository.nativeStateFile.writeAsString(
        repository.codec.encode(legacyNative),
        flush: true,
      );
      final upgraded = await repository.load(_catalog());
      final deliberatelyGreenhouse = upgraded.state.copyWith(
        alchemy: upgraded.state.alchemy.copyWith(appearance: greenhouse),
        cooking: upgraded.state.cooking.copyWith(appearance: greenhouse),
        processing: upgraded.state.processing.copyWith(appearance: greenhouse),
      );
      await repository.save(deliberatelyGreenhouse);

      final restarted = await repository.load(_catalog());

      for (final mode in CraftMode.values) {
        expect(
          restarted.state.forMode(mode).appearance.background,
          'greenhouse',
        );
      }
      expect(restarted.notices, isEmpty);
    },
  );

  test(
    'previews read-only then imports an exact copy only after approval',
    () async {
      final bytes = await _writeSyntheticLegacy(legacyState);
      final before = await legacyState.readAsBytes();
      final repository = _repository(appDirectory, legacyState);

      final previewed = await repository.load(_catalog());

      expect(previewed.origin, PlannerStateLoadOrigin.awaitingMigration);
      expect(previewed.state.alchemy.target, 'Alchemy Target');
      expect(previewed.migrationPreview, isNotNull);
      expect(previewed.migrationPreview!.canImport, isTrue);
      expect(previewed.migrationPreview!.sourcePath, legacyState.path);
      expect(
        previewed.migrationPreview!.targetPath,
        repository.nativeStateFile.path,
      );
      expect(await repository.nativeStateFile.exists(), isFalse);
      expect(await _migrationArchives(appDirectory), isEmpty);
      expect(await legacyState.readAsBytes(), before);

      final result = await repository.commitMigration(
        previewed.migrationPreview!,
      );

      expect(result.origin, PlannerStateLoadOrigin.migratedAvalonia);
      expect(result.state.alchemy.inventory, hasLength(2));
      for (final mode in CraftMode.values) {
        expect(
          result.state.forMode(mode).appearance.background,
          'illuminated-ledger',
        );
      }
      expect(
        result.state.extensions[PlannerStateRepository
            .sakuraDefaultMigrationMarkerKey],
        PlannerStateRepository.sakuraDefaultMigrationVersion,
      );
      expect(result.sourceUnchangedAfterMigration, isTrue);
      expect(await legacyState.readAsBytes(), before);
      final relative = result.state.origin!.archiveRelativePath!;
      final archive = File(
        '${appDirectory.path}${Platform.pathSeparator}${relative.replaceAll('/', Platform.pathSeparator)}',
      );
      expect(await archive.readAsBytes(), before);
      final targetBytes = await repository.nativeStateFile.readAsBytes();
      expect(result.migrationReport!.targetByteCount, targetBytes.length);
      expect(
        result.migrationReport!.targetSha256,
        sha256.convert(targetBytes).toString().toUpperCase(),
      );

      final restarted = await repository.load(_catalog());
      expect(restarted.origin, PlannerStateLoadOrigin.native);
      expect(restarted.migrationPreview, isNull);
      expect(restarted.state.alchemy.inventory, hasLength(2));
      expect(await legacyState.readAsBytes(), bytes);
    },
  );

  test(
    'start fresh leaves the source untouched and never offers again',
    () async {
      final bytes = await _writeSyntheticLegacy(legacyState);
      final repository = _repository(appDirectory, legacyState);

      final previewed = await repository.load(_catalog());
      final result = await repository.commitFresh(previewed.migrationPreview!);

      expect(result.origin, PlannerStateLoadOrigin.fresh);
      expect(result.state.alchemy.target, 'Alchemy Target');
      expect(result.state.alchemy.alchemyMastery, 0);
      expect(
        result.state.alchemy.compatibility.alchemyYield,
        alchemyExpectedOutput(0, 1, 4),
      );
      expect(result.state.cooking.cookingMastery, 0);
      expect(result.state.processing.processingMastery, 0);
      expect(result.state.origin, isNull);
      for (final mode in CraftMode.values) {
        final modeState = result.state.forMode(mode);
        expect(modeState.inventory, isEmpty);
        expect(modeState.favoriteRecipes, isEmpty);
        expect(
          modeState.appearance.background,
          SakuraNightGardenSpec.backgroundId,
        );
      }
      expect(
        result.state.extensions[PlannerStateRepository
            .sakuraDefaultMigrationMarkerKey],
        PlannerStateRepository.sakuraDefaultMigrationVersion,
      );
      expect(result.sourceUnchangedAfterMigration, isTrue);
      expect(await legacyState.readAsBytes(), bytes);
      expect(await _migrationArchives(appDirectory), isEmpty);
      final targetBytes = await repository.nativeStateFile.readAsBytes();
      expect(result.migrationReport!.targetByteCount, targetBytes.length);
      expect(
        result.migrationReport!.targetSha256,
        sha256.convert(targetBytes).toString().toUpperCase(),
      );

      final restarted = await repository.load(_catalog());
      expect(restarted.origin, PlannerStateLoadOrigin.native);
      expect(restarted.migrationPreview, isNull);
      expect(restarted.state.alchemy.target, 'Alchemy Target');
    },
  );

  test('invalid source can only be declined and is never modified', () async {
    await legacyState.parent.create(recursive: true);
    const invalid = '{not valid json';
    await legacyState.writeAsString(invalid, flush: true);
    final before = await legacyState.readAsBytes();
    final repository = _repository(appDirectory, legacyState);

    final previewed = await repository.load(_catalog());

    expect(previewed.origin, PlannerStateLoadOrigin.awaitingMigration);
    expect(previewed.migrationPreview!.canImport, isFalse);
    expect(previewed.migrationPreview!.migratedState, isNull);
    expect(await repository.nativeStateFile.exists(), isFalse);
    await expectLater(
      repository.commitMigration(previewed.migrationPreview!),
      throwsStateError,
    );
    expect(await repository.nativeStateFile.exists(), isFalse);
    expect(await legacyState.readAsBytes(), before);

    final fresh = await repository.commitFresh(previewed.migrationPreview!);
    expect(fresh.origin, PlannerStateLoadOrigin.fresh);
    expect(fresh.sourceUnchangedAfterMigration, isTrue);
    expect(await legacyState.readAsBytes(), before);
    final restarted = await repository.load(_catalog());
    expect(restarted.origin, PlannerStateLoadOrigin.native);
    expect(restarted.migrationPreview, isNull);
  });

  test('changed source blocks approval without any target writes', () async {
    await _writeSyntheticLegacy(legacyState);
    final repository = _repository(appDirectory, legacyState);
    final previewed = await repository.load(_catalog());
    final changed = await legacyState.readAsString();
    await legacyState.writeAsString('$changed\n', flush: true);

    await expectLater(
      repository.commitMigration(previewed.migrationPreview!),
      throwsStateError,
    );

    expect(await repository.nativeStateFile.exists(), isFalse);
    expect(await _migrationArchives(appDirectory), isEmpty);
    expect(await legacyState.readAsString(), '$changed\n');
  });

  test('failed target write rolls back a new archive and can retry', () async {
    final bytes = await _writeSyntheticLegacy(legacyState);
    final repository = _repository(appDirectory, legacyState);
    final previewed = await repository.load(_catalog());
    final blockingTarget = Directory(repository.nativeStateFile.path);
    await blockingTarget.create(recursive: true);

    await expectLater(
      repository.commitMigration(previewed.migrationPreview!),
      throwsA(isA<Object>()),
    );

    expect(await repository.nativeStateFile.exists(), isFalse);
    expect(await _migrationArchives(appDirectory), isEmpty);
    expect(await legacyState.readAsBytes(), bytes);

    await blockingTarget.delete();
    final retried = await repository.commitMigration(
      previewed.migrationPreview!,
    );
    expect(retried.origin, PlannerStateLoadOrigin.migratedAvalonia);
    expect(retried.sourceUnchangedAfterMigration, isTrue);
  });

  test('recovers a valid backup when the native file is corrupt', () async {
    final repository = _repository(appDirectory, legacyState);
    final first = await repository.load(_catalog());
    await repository.save(first.state);
    const corrupt = '{broken';
    await repository.nativeStateFile.writeAsString(corrupt, flush: true);

    final recovered = await repository.load(_catalog());

    expect(recovered.origin, PlannerStateLoadOrigin.recoveredBackup);
    expect(recovered.recoveredFromPath, isNotNull);
    expect(recovered.state.alchemy.target, 'Alchemy Target');
    expect(
      await repository.nativeStateFile.readAsString(),
      isNot(contains(corrupt)),
    );
    final quarantined = appDirectory
        .listSync()
        .whereType<File>()
        .where((file) => file.path.contains('planner-state.json.invalid-'))
        .single;
    expect(await quarantined.readAsString(), corrupt);

    final edited = await repository.save(
      recovered.state.copyWith(
        alchemy: recovered.state.alchemy.copyWith(target: 'Edited Target'),
      ),
    );
    expect(edited.alchemy.target, 'Edited Target');
    final restarted = await repository.load(_catalog());
    expect(restarted.origin, PlannerStateLoadOrigin.native);
    expect(restarted.state.alchemy.target, 'Edited Target');
  });

  test(
    'quarantines corrupt state without a backup and commits fresh state',
    () async {
      await appDirectory.create(recursive: true);
      final native = File(
        '${appDirectory.path}${Platform.pathSeparator}${PlannerStateRepository.stateFileName}',
      );
      const corrupt = 'not-json-at-all';
      await native.writeAsString(corrupt, flush: true);
      final repository = _repository(appDirectory, legacyState);

      final result = await repository.load(_catalog());

      expect(result.origin, PlannerStateLoadOrigin.fresh);
      expect(result.state.alchemy.target, 'Alchemy Target');
      expect(await repository.nativeStateFile.exists(), isTrue);
      final quarantined = appDirectory
          .listSync()
          .whereType<File>()
          .where((file) => file.path.contains('planner-state.json.invalid-'))
          .single;
      expect(await quarantined.readAsString(), corrupt);
    },
  );

  test(
    'configured custom profile recovers when only a valid backup remains',
    () async {
      final repository = _repository(appDirectory, legacyState);
      final fresh = await repository.load(_catalog());
      final edited = fresh.state.copyWith(
        alchemy: fresh.state.alchemy.copyWith(
          target: 'Recovered custom target',
        ),
      );
      await repository.save(edited);
      await repository.save(edited);
      await repository.nativeStateFile.delete();

      final recovered = await repository.load(
        _catalog(),
        requireExistingProfile: true,
      );

      expect(recovered.origin, PlannerStateLoadOrigin.recoveredBackup);
      expect(recovered.state.alchemy.target, 'Recovered custom target');
      expect(await repository.nativeStateFile.exists(), isTrue);
    },
  );

  test('configured custom profile never falls back to a fresh profile', () async {
    await appDirectory.create(recursive: true);
    await File(
      '${appDirectory.path}${Platform.pathSeparator}${PlannerStateRepository.stateFileName}',
    ).writeAsString('not-json-at-all', flush: true);
    final repository = _repository(appDirectory, legacyState);

    await expectLater(
      repository.load(_catalog(), requireExistingProfile: true),
      throwsA(isA<FileSystemException>()),
    );

    expect(await repository.nativeStateFile.exists(), isFalse);
    expect(
      appDirectory.listSync().whereType<File>().any(
        (file) => file.path.contains('planner-state.json.invalid-'),
      ),
      isTrue,
    );
  });
}

AppearanceSettings _customGreenhouseAppearance(int seed) => AppearanceSettings(
  background: 'greenhouse',
  liveBackdrop: seed.isEven,
  motionIntensity: .31 + seed * .1,
  motionSpeed: .38 + seed * .08,
  particleStyle: 'fumes',
  particleDensity: .41 + seed * .1,
  particleOpacity: .52 + seed * .08,
  particleMinSize: .64 + seed * .02,
  particleMaxSize: 1.5 + seed * .05,
  particleSize: .85 + seed * .05,
  particleBlur: .1 + seed * .03,
  particleCustomColor: true,
  particleHue: 70 + seed.toDouble(),
  particleNeon: seed.isEven,
  buttonEffect: seed.isEven ? 'sweep' : 'glow',
  buttonEffectIntensity: .47 + seed * .08,
  buttonEffectSpeed: .36 + seed * .09,
  buttonEffectBlur: .08 + seed * .03,
  buttonEffectActiveOnly: seed.isOdd,
  buttonEffectCustomColor: true,
  buttonEffectHue: 40 + seed.toDouble(),
  buttonEffectNeon: seed.isOdd,
  accentHue: 158,
  rainbow: seed.isEven,
  neon: seed.isOdd,
  backdropBlur: seed.toDouble(),
  tabFade: seed.isEven,
  tabTransition: seed.isEven ? 'fade' : 'slide',
  tabTransitionSpeed: seed.isEven ? 'fast' : 'slow',
  presets: <AppearancePreset?>[
    AppearancePreset(
      name: 'Saved $seed',
      settings: AppearanceSettings.defaultsFor(CraftMode.cooking),
      extensions: <String, Object?>{'slot': seed},
    ),
    null,
  ],
  extensions: <String, Object?>{
    'customControl': seed,
    'nested': <String, Object?>{'kept': true},
  },
);

Map<String, Object?> _withoutSakuraIdentity(AppearanceSettings appearance) {
  final controls = Map<String, Object?>.from(appearance.toJson());
  controls
    ..remove('background')
    ..remove('particleStyle')
    ..remove('accentHue');
  return controls;
}

PlannerState _withoutSakuraMigrationMarker(PlannerState state) =>
    state.copyWith(
      extensions: <String, Object?>{
        for (final entry in state.extensions.entries)
          if (entry.key !=
              PlannerStateRepository.sakuraDefaultMigrationMarkerKey)
            entry.key: entry.value,
      },
    );

Future<List<File>> _migrationArchives(Directory applicationDirectory) async {
  final directory = Directory(
    '${applicationDirectory.path}${Platform.pathSeparator}migration',
  );
  if (!await directory.exists()) return const <File>[];
  return directory
      .list(followLinks: false)
      .where((entity) => entity is File)
      .cast<File>()
      .toList();
}

Future<List<int>> _writeSyntheticLegacy(File legacyState) async {
  await legacyState.parent.create(recursive: true);
  final bytes = await File(
    'test/fixtures/migration/avalonia-planner-state-synthetic.json',
  ).readAsBytes();
  await legacyState.writeAsBytes(bytes, flush: true);
  return bytes;
}

PlannerStateRepository _repository(
  Directory directory,
  File legacy, {
  Directory? formerNative,
}) => PlannerStateRepository(
  paths: PlannerStatePathPolicy(
    applicationDirectory: directory,
    legacyStateFile: legacy,
    formerNativeApplicationDirectory: formerNative,
  ),
  applicationVersion: 'test',
  utcNow: () => DateTime.utc(2026, 7, 20, 12),
);

CatalogSnapshot _catalog() => CatalogSnapshot(
  sourceSha256: 'fixture',
  sourceByteCount: 1,
  alchemy: _mode(CraftMode.alchemy, 'Alchemy Target', 3.2),
  cooking: _mode(CraftMode.cooking, 'Cooking Target', 1),
  processing: _mode(CraftMode.processing, 'Processing Target', 1),
  supportingData: const {},
  collisions: const [],
);

ModeCatalog _mode(
  CraftMode mode,
  String target,
  double yield, {
  Map<String, double> defaultInventory = const <String, double>{},
}) => ModeCatalog(
  mode: mode,
  items: {target: _recipe(target, mode)},
  iconDataUris: const {},
  defaults: {
    'target': target,
    'want': 100,
    'yieldMult': yield,
    'inv': defaultInventory,
    'favoriteRecipes': <String>[target],
  },
  metadata: const {},
  searchAliases: const {},
);

Recipe _recipe(String name, CraftMode mode) => Recipe(
  name: name,
  type: mode.key,
  baseOutput: 1,
  group: null,
  method: null,
  ingredients: [
    Ingredient(
      name: 'Base',
      quantity: 1,
      options: const [],
      substituteGroup: null,
      substituteRatios: const {},
    ),
  ],
  marketId: null,
  sourceNote: null,
  vendor: null,
  location: null,
  npcPrice: 0,
  qualityBase: null,
  qualityGrade: null,
  outputMinimum: 1,
  outputMaximum: 1,
);
