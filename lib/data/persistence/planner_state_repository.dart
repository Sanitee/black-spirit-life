import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import '../../app_identity.dart';
import '../../data/icons/custom_icon_store.dart';
import '../../domain/migration/avalonia_v1_migration.dart';
import '../../domain/migration/migration_report.dart';
import '../../domain/models/catalog_models.dart';
import '../../domain/models/craft_mode.dart';
import '../../domain/planner/mastery_yields.dart';
import '../../domain/state/planner_state.dart';
import '../../domain/state/planner_state_json_codec.dart';
import '../../domain/state/state_copy.dart';
import 'atomic_file_store.dart';

enum PlannerStateLoadOrigin {
  native,
  recoveredBackup,
  importedFormerNative,
  awaitingMigration,
  migratedAvalonia,
  fresh,
}

final class PlannerStateLoadResult {
  PlannerStateLoadResult({
    required this.state,
    required this.origin,
    required Iterable<String> notices,
    this.migrationReport,
    Iterable<PendingCustomIcon> pendingCustomIcons = const [],
    this.migrationPreview,
    this.sourceUnchangedAfterMigration,
    this.recoveredFromPath,
  }) : notices = List.unmodifiable(notices),
       pendingCustomIcons = List.unmodifiable(pendingCustomIcons);

  final PlannerState state;
  final PlannerStateLoadOrigin origin;
  final List<String> notices;
  final MigrationReport? migrationReport;
  final List<PendingCustomIcon> pendingCustomIcons;
  final PlannerStateMigrationPreview? migrationPreview;
  final bool? sourceUnchangedAfterMigration;
  final String? recoveredFromPath;
}

/// A read-only, in-memory first-launch proposal.
///
/// Merely creating this value never archives, edits, moves, or commits the
/// Avalonia source. The captured bytes are private and are only copied into
/// Flutter-owned storage after the user explicitly accepts the proposal.
final class PlannerStateMigrationPreview {
  PlannerStateMigrationPreview._(
    this._repositoryIdentity, {
    required this.sourcePath,
    required this.targetPath,
    required Uint8List sourceBytes,
    required this.freshState,
    required this.migratedState,
    required this.report,
    required Iterable<PendingCustomIcon> pendingCustomIcons,
  }) : _sourceBytes = Uint8List.fromList(sourceBytes),
       pendingCustomIcons = List<PendingCustomIcon>.unmodifiable(
         pendingCustomIcons,
       );

  final String sourcePath;
  final String targetPath;
  final PlannerState freshState;
  final PlannerState? migratedState;
  final MigrationReport report;
  final List<PendingCustomIcon> pendingCustomIcons;
  final Uint8List _sourceBytes;
  final Object _repositoryIdentity;

  bool get canImport => migratedState != null && !report.hasErrors;
  String get sourceSha256 => report.sourceSha256;
  int get sourceByteCount => report.sourceByteCount;
}

final class PlannerStatePathPolicy {
  const PlannerStatePathPolicy({
    required this.applicationDirectory,
    required this.legacyStateFile,
    this.formerNativeApplicationDirectory,
    this.allowLegacyMigration = true,
  });

  factory PlannerStatePathPolicy.fromEnvironment(
    Map<String, String> environment,
  ) {
    final roaming = environment['APPDATA'];
    if (roaming == null || roaming.trim().isEmpty) {
      throw const FileSystemException(
        'APPDATA is unavailable; the Windows state directory cannot be resolved.',
      );
    }
    return PlannerStatePathPolicy(
      applicationDirectory: Directory(
        _join(roaming, AppIdentity.stateDirectoryName),
      ),
      formerNativeApplicationDirectory:
          AppIdentity.importFormerProfilesOnFirstLaunch
          ? Directory(_join(roaming, AppIdentity.formerStateDirectoryName))
          : null,
      allowLegacyMigration: AppIdentity.importFormerProfilesOnFirstLaunch,
      legacyStateFile: File(
        _join(
          _join(roaming, 'BDO Craft Planner Avalonia'),
          'planner-state.json',
        ),
      ),
    );
  }

  final Directory applicationDirectory;
  final Directory? formerNativeApplicationDirectory;
  final File legacyStateFile;
  final bool allowLegacyMigration;
}

/// Owns the Flutter state path. The legacy Avalonia file is read only during
/// first-run migration and is archived byte-for-byte under the Flutter path.
final class PlannerStateRepository {
  PlannerStateRepository({
    required this.paths,
    this.applicationVersion = AppIdentity.applicationVersion,
    this.codec = const PlannerStateJsonCodec(),
    DateTime Function()? utcNow,
  }) : _utcNow = utcNow ?? (() => DateTime.now().toUtc()),
       _store = AtomicFileStore(
         directory: paths.applicationDirectory,
         fileName: stateFileName,
       );

  static const stateFileName = 'planner-state.json';
  static const sakuraDefaultMigrationMarkerKey =
      'mapCandidateSakuraDefaultMigrationVersion';
  static const sakuraDefaultMigrationVersion = 1;
  static const formerNativeImportMarkerKey =
      'blackSpiritLifeFormerNativeImport';
  static const formerNativeImportVersion = 1;

  final PlannerStatePathPolicy paths;
  final String applicationVersion;
  final PlannerStateJsonCodec codec;
  final DateTime Function() _utcNow;
  final AtomicFileStore _store;

  File get nativeStateFile => File(_store.targetPath);

  Future<PlannerStateLoadResult> load(
    CatalogSnapshot catalog, {
    bool requireExistingProfile = false,
  }) async {
    final notices = <String>[];
    var backupRecoveryAttempted = false;
    if (await nativeStateFile.exists()) {
      PlannerState? nativeState;
      try {
        nativeState = codec.decode(await nativeStateFile.readAsString());
      } on Object catch (error) {
        notices.add('The current Flutter state was invalid: $error');
        backupRecoveryAttempted = true;
        final recovered = await _recoverNewestBackup(notices);
        final quarantinePath = await _quarantineInvalidNative();
        notices.add(
          'Preserved the invalid Flutter state at $quarantinePath before recovery.',
        );
        if (recovered != null) {
          return _commitRecoveredBackup(recovered, notices);
        }
      }
      if (nativeState != null) {
        final migration = _migrateFormerGreenhouseDefault(nativeState);
        if (migration.requiresWrite) {
          nativeState = await save(migration.state);
          if (migration.upgradedAppearance) {
            notices.add(
              'Updated the unmarked all-Greenhouse appearance to Sakura '
              'Night Garden while preserving its custom controls. This '
              'one-time update will not replace later theme choices.',
            );
          }
        }
        return PlannerStateLoadResult(
          state: nativeState,
          origin: PlannerStateLoadOrigin.native,
          notices: notices,
        );
      }
    }

    if (requireExistingProfile) {
      if (!backupRecoveryAttempted) {
        final recovered = await _recoverNewestBackup(notices);
        if (recovered != null) {
          return _commitRecoveredBackup(recovered, notices);
        }
      }
      throw FileSystemException(
        'The configured personal-data folder has no recoverable planner state. Restore its planner-state.json or a valid backup before starting Black Spirit Life.',
        paths.applicationDirectory.path,
      );
    }

    if (await _hasIntentionalResetMarker()) {
      notices.add(
        'Started with empty planner data after the previous uninstall '
        'explicitly removed its personal files.',
      );
      return PlannerStateLoadResult(
        state: await save(_freshState(catalog)),
        origin: PlannerStateLoadOrigin.fresh,
        notices: notices,
      );
    }

    if (paths.allowLegacyMigration) {
      final formerNative = await _importFormerNativeState();
      if (formerNative != null) return formerNative;
    }

    final fresh = _freshState(catalog);
    if (paths.allowLegacyMigration && await paths.legacyStateFile.exists()) {
      final sourceBytes = await paths.legacyStateFile.readAsBytes();
      final migration = AvaloniaV1Migration(
        defaults: _migrationDefaults(catalog),
        utcNow: _utcNow,
      ).decodeUtf8(sourceBytes);
      notices.add(
        migration.succeeded
            ? 'An Avalonia planner state is available to preview. Nothing has been imported yet.'
            : 'The Avalonia planner state is invalid and cannot be imported. It remains untouched.',
      );
      return PlannerStateLoadResult(
        state: fresh,
        origin: PlannerStateLoadOrigin.awaitingMigration,
        notices: notices,
        migrationReport: migration.report,
        migrationPreview: PlannerStateMigrationPreview._(
          this,
          sourcePath: paths.legacyStateFile.path,
          targetPath: nativeStateFile.path,
          sourceBytes: sourceBytes,
          freshState: fresh,
          migratedState: migration.state,
          report: migration.report,
          pendingCustomIcons: migration.pendingCustomIcons,
        ),
      );
    }

    return PlannerStateLoadResult(
      state: await save(fresh),
      origin: PlannerStateLoadOrigin.fresh,
      notices: notices,
    );
  }

  Future<PlannerStateLoadResult> _commitRecoveredBackup(
    PlannerStateLoadResult recovered,
    List<String> notices,
  ) async {
    final migration = _migrateFormerGreenhouseDefault(recovered.state);
    final committed = await save(migration.state);
    if (migration.upgradedAppearance) {
      notices.add(
        'Updated the unmarked all-Greenhouse appearance to Sakura '
        'Night Garden while preserving its custom controls. This '
        'one-time update will not replace later theme choices.',
      );
    }
    notices.add(
      'Committed the recovered backup as the current writable state.',
    );
    return PlannerStateLoadResult(
      state: committed,
      origin: PlannerStateLoadOrigin.recoveredBackup,
      notices: notices,
      recoveredFromPath: recovered.recoveredFromPath,
    );
  }

  /// Commits an explicitly accepted first-launch migration into Flutter-owned
  /// storage. [materializedState] may only add validated app-owned icon
  /// references to the state represented by [preview].
  Future<PlannerStateLoadResult> commitMigration(
    PlannerStateMigrationPreview preview, {
    PlannerState? materializedState,
    Iterable<String> notices = const [],
  }) async {
    _validatePreview(preview);
    final source = preview.migratedState;
    if (!preview.canImport || source == null) {
      throw StateError('The Avalonia migration preview is not importable.');
    }
    if (await nativeStateFile.exists()) {
      throw StateError(
        'A Flutter planner state already exists; first-launch migration will not overwrite it.',
      );
    }
    final sourceBeforeCommit = await paths.legacyStateFile.readAsBytes();
    if (!_sameBytes(sourceBeforeCommit, preview._sourceBytes)) {
      throw StateError(
        'The Avalonia source changed after preview. Reopen the application to inspect a fresh copy.',
      );
    }
    final proposed = materializedState ?? source;
    if (proposed.origin?.sourceSha256 != preview.sourceSha256 ||
        proposed.origin?.sourceByteCount != preview.sourceByteCount) {
      throw StateError(
        'The proposed migration state does not match the previewed source copy.',
      );
    }
    final archive = await _archiveLegacy(preview._sourceBytes, preview.report);
    final origin = proposed.origin!;
    final migrated = proposed.copyWith(
      origin: MigrationOrigin(
        sourceKind: origin.sourceKind,
        sourceVersion: origin.sourceVersion,
        sourceModeVersions: origin.sourceModeVersions,
        sourceSha256: origin.sourceSha256,
        sourceByteCount: origin.sourceByteCount,
        migratedAtUtc: origin.migratedAtUtc,
        archiveRelativePath: archive.relativePath,
      ),
      applicationVersion: applicationVersion,
    );
    final _PlannerStateCommit commit;
    try {
      commit = await _saveWithReceipt(migrated);
    } on Object catch (error, stackTrace) {
      if (archive.created) {
        try {
          if (await archive.file.exists()) await archive.file.delete();
        } on Object catch (cleanupError) {
          throw StateError(
            'Migration state commit failed: $error The new source archive '
            'could not be rolled back: $cleanupError',
          );
        }
      }
      Error.throwWithStackTrace(error, stackTrace);
    }
    final completedReport = preview.report.withTarget(
      targetSha256: commit.write.sha256,
      targetByteCount: commit.write.byteCount,
    );
    bool? sourceUnchanged;
    try {
      sourceUnchanged = _sameBytes(
        await paths.legacyStateFile.readAsBytes(),
        preview._sourceBytes,
      );
    } on Object {
      sourceUnchanged = null;
    }
    return PlannerStateLoadResult(
      state: commit.state,
      origin: PlannerStateLoadOrigin.migratedAvalonia,
      notices: <String>[
        ...notices,
        'Imported the approved read-only Avalonia copy and archived its exact source bytes.',
        if (sourceUnchanged == true)
          'Confirmed that the Avalonia source bytes are unchanged.'
        else if (sourceUnchanged == false)
          'The Avalonia source changed outside this migration while the Flutter copy was being committed.'
        else
          'The Avalonia source could not be re-read for the final unchanged-byte confirmation.',
      ],
      migrationReport: completedReport,
      sourceUnchangedAfterMigration: sourceUnchanged,
    );
  }

  /// Persists the clean bundled profile selected from the first-launch gate.
  Future<PlannerStateLoadResult> commitFresh(
    PlannerStateMigrationPreview preview,
  ) async {
    _validatePreview(preview);
    if (await nativeStateFile.exists()) {
      throw StateError(
        'A Flutter planner state already exists; the first-launch choice is no longer applicable.',
      );
    }
    Uint8List? sourceBeforeCommit;
    try {
      sourceBeforeCommit = await paths.legacyStateFile.readAsBytes();
    } on Object {
      sourceBeforeCommit = null;
    }
    final commit = await _saveWithReceipt(preview.freshState);
    bool? sourceUnchanged;
    if (sourceBeforeCommit != null) {
      try {
        sourceUnchanged = _sameBytes(
          await paths.legacyStateFile.readAsBytes(),
          sourceBeforeCommit,
        );
      } on Object {
        sourceUnchanged = null;
      }
    }
    return PlannerStateLoadResult(
      state: commit.state,
      origin: PlannerStateLoadOrigin.fresh,
      notices: <String>[
        'Started with a clean Flutter profile. The Avalonia state was not imported or modified.',
        if (sourceUnchanged == true)
          'Confirmed that the Avalonia source bytes are unchanged.'
        else
          'The Avalonia source could not be confirmed byte-for-byte after the clean-profile choice.',
      ],
      migrationReport: preview.report.withTarget(
        targetSha256: commit.write.sha256,
        targetByteCount: commit.write.byteCount,
      ),
      sourceUnchangedAfterMigration: sourceUnchanged,
    );
  }

  void _validatePreview(PlannerStateMigrationPreview preview) {
    if (!identical(preview._repositoryIdentity, this) ||
        preview.sourcePath != paths.legacyStateFile.path) {
      throw StateError(
        'The migration preview belongs to a different state repository.',
      );
    }
  }

  Future<PlannerState> save(PlannerState state) async =>
      (await _saveWithReceipt(state)).state;

  Future<_PlannerStateCommit> _saveWithReceipt(PlannerState state) async {
    final next = _markSakuraDefaultMigrationComplete(state).copyWith(
      applicationVersion: applicationVersion,
      lastSuccessfulWriteUtc: _utcNow().toUtc(),
    );
    final write = await _store.writeBytes(
      Uint8List.fromList(utf8.encode(codec.encode(next))),
      validate: codec.validateBytes,
    );
    return _PlannerStateCommit(state: next, write: write);
  }

  Future<bool> _hasIntentionalResetMarker() async {
    final marker = File(
      _join(
        paths.applicationDirectory.path,
        AppIdentity.intentionalResetMarkerFileName,
      ),
    );
    if (!await marker.exists()) return false;
    try {
      final value = jsonDecode(await marker.readAsString());
      return value is Map &&
          value['schemaVersion'] == 1 &&
          value['packageId'] == AppIdentity.installerPackageId &&
          value['releaseChannel'] == AppIdentity.releaseChannel &&
          value['intentionalReset'] == true;
    } on Object {
      return false;
    }
  }

  Future<PlannerStateLoadResult?> _importFormerNativeState() async {
    final sourceDirectory = paths.formerNativeApplicationDirectory;
    if (sourceDirectory == null ||
        _samePath(sourceDirectory.path, paths.applicationDirectory.path)) {
      return null;
    }
    final sourceFile = File(_join(sourceDirectory.path, stateFileName));
    if (!await sourceFile.exists()) return null;

    final sourceBytes = await sourceFile.readAsBytes();
    final sourceSha256 = sha256.convert(sourceBytes).toString().toUpperCase();
    final PlannerState decoded;
    try {
      decoded = codec.decode(utf8.decode(sourceBytes));
    } on Object catch (error) {
      throw FormatException(
        'The former ${AppIdentity.formerStateDirectoryName} settings could '
        'not be copied into ${AppIdentity.displayName}. The original profile '
        'was left untouched. Details: $error',
      );
    }

    final migration = _migrateFormerGreenhouseDefault(decoded);
    final state = migration.state.copyWith(
      extensions: <String, Object?>{
        ...migration.state.extensions,
        formerNativeImportMarkerKey: <String, Object?>{
          'version': formerNativeImportVersion,
          'sourceDirectory': AppIdentity.formerStateDirectoryName,
          'sourceSha256': sourceSha256,
          'sourceByteCount': sourceBytes.length,
          'copiedAtUtc': _utcNow().toUtc().toIso8601String(),
        },
      },
    );

    final copiedIcons = <CustomIconReference>[];
    _FormerNativeArchive? archive;
    try {
      final destinationStore = CustomIconStore(
        applicationDirectory: paths.applicationDirectory,
      );
      try {
        for (final reference in _customIconReferences(state)) {
          final copy = await destinationStore.copyValidatedReferenceFrom(
            reference: reference,
            sourceApplicationDirectory: sourceDirectory,
          );
          if (copy.created) copiedIcons.add(reference);
        }
      } finally {
        destinationStore.dispose();
      }
      archive = await _archiveFormerNative(sourceBytes, sourceSha256);
      final commit = await _saveWithReceipt(state);
      final sourceUnchanged = await _sourceStillMatches(
        sourceFile,
        sourceBytes,
      );
      return PlannerStateLoadResult(
        state: commit.state,
        origin: PlannerStateLoadOrigin.importedFormerNative,
        notices: <String>[
          'Copied your ${AppIdentity.formerStateDirectoryName} settings into '
              '${AppIdentity.displayName}. The original profile remains '
              'untouched.',
          if (migration.upgradedAppearance)
            'Updated the unmarked all-Greenhouse appearance to Sakura Night '
                'Garden while preserving its custom controls.',
          if (sourceUnchanged == true)
            'Confirmed that the former profile bytes are unchanged.'
          else if (sourceUnchanged == false)
            'The former profile changed outside this copy while the new Black Spirit Life '
                'profile was being saved.'
          else
            'The former profile could not be re-read for a final unchanged-byte '
                'check.',
        ],
        sourceUnchangedAfterMigration: sourceUnchanged,
      );
    } on Object catch (error, stackTrace) {
      final cleanupErrors = <Object>[];
      for (final reference in copiedIcons.reversed) {
        try {
          final store = CustomIconStore(
            applicationDirectory: paths.applicationDirectory,
          );
          try {
            await store.remove(reference);
          } finally {
            store.dispose();
          }
        } on Object catch (cleanupError) {
          cleanupErrors.add(cleanupError);
        }
      }
      if (archive?.created == true) {
        try {
          if (await archive!.file.exists()) await archive.file.delete();
        } on Object catch (cleanupError) {
          cleanupErrors.add(cleanupError);
        }
      }
      if (cleanupErrors.isNotEmpty) {
        throw StateError(
          'Former profile copy failed: $error Cleanup also failed: '
          '${cleanupErrors.join('; ')}',
        );
      }
      Error.throwWithStackTrace(error, stackTrace);
    }
  }

  Future<_FormerNativeArchive> _archiveFormerNative(
    Uint8List sourceBytes,
    String sourceSha256,
  ) async {
    final archiveDirectory = Directory(
      _join(paths.applicationDirectory.path, 'migration'),
    );
    final archiveName =
        'map-candidate-native-${sourceSha256.toLowerCase()}.json';
    final archiveFile = File(_join(archiveDirectory.path, archiveName));
    if (await archiveFile.exists()) {
      if (!_sameBytes(await archiveFile.readAsBytes(), sourceBytes)) {
        throw const FileSystemException(
          'The existing former-profile archive does not match the source copy.',
        );
      }
      return _FormerNativeArchive(file: archiveFile, created: false);
    }
    final archive = AtomicFileStore(
      directory: archiveDirectory,
      fileName: archiveName,
    );
    await archive.writeBytes(sourceBytes, validate: codec.validateBytes);
    return _FormerNativeArchive(file: archiveFile, created: true);
  }

  Future<bool?> _sourceStillMatches(File source, Uint8List expected) async {
    try {
      return _sameBytes(await source.readAsBytes(), expected);
    } on Object {
      return null;
    }
  }

  Future<PlannerStateLoadResult?> _recoverNewestBackup(
    List<String> notices,
  ) async {
    if (!await paths.applicationDirectory.exists()) return null;
    final backups = await paths.applicationDirectory
        .list(followLinks: false)
        .where(
          (entity) =>
              entity is File &&
              entity.uri.pathSegments.last.startsWith('$stateFileName.backup-'),
        )
        .cast<File>()
        .toList();
    backups.sort((left, right) => right.path.compareTo(left.path));
    for (final backup in backups) {
      try {
        final state = codec.decode(await backup.readAsString());
        notices.add('Recovered the newest valid Flutter state backup.');
        return PlannerStateLoadResult(
          state: state,
          origin: PlannerStateLoadOrigin.recoveredBackup,
          notices: notices,
          recoveredFromPath: backup.path,
        );
      } on Object catch (error) {
        notices.add('${backup.path} was not a valid backup: $error');
      }
    }
    return null;
  }

  Future<String> _quarantineInvalidNative() async {
    if (!await nativeStateFile.exists()) {
      throw const FileSystemException(
        'The invalid native state disappeared before it could be preserved.',
      );
    }
    final timestamp = _utcNow().toUtc().microsecondsSinceEpoch;
    var sequence = 0;
    File destination;
    do {
      final suffix = sequence == 0 ? '' : '-$sequence';
      destination = File(
        _join(
          paths.applicationDirectory.path,
          '$stateFileName.invalid-$timestamp$suffix',
        ),
      );
      sequence++;
    } while (await destination.exists());
    final quarantined = await nativeStateFile.rename(destination.path);
    return quarantined.path;
  }

  Future<_LegacyArchive> _archiveLegacy(
    Uint8List sourceBytes,
    MigrationReport report,
  ) async {
    final archiveDirectory = Directory(
      _join(paths.applicationDirectory.path, 'migration'),
    );
    final archiveName = 'avalonia-v1-${report.sourceSha256.toLowerCase()}.json';
    final archiveFile = File(_join(archiveDirectory.path, archiveName));
    if (await archiveFile.exists()) {
      final existing = await archiveFile.readAsBytes();
      if (!_sameBytes(existing, sourceBytes)) {
        throw const FileSystemException(
          'The existing migration archive does not match the previewed source copy.',
        );
      }
      return _LegacyArchive(
        relativePath: 'migration/$archiveName',
        file: archiveFile,
        created: false,
      );
    }
    final archive = AtomicFileStore(
      directory: archiveDirectory,
      fileName: archiveName,
    );
    await archive.writeBytes(
      sourceBytes,
      validate: (bytes) {
        final validation = AvaloniaV1Migration(
          defaults: AvaloniaMigrationDefaults.schemaFallback(
            applicationVersion: applicationVersion,
          ),
          utcNow: _utcNow,
        ).decodeUtf8(bytes);
        if (!validation.succeeded) {
          throw const FormatException('Invalid Avalonia migration archive.');
        }
      },
    );
    return _LegacyArchive(
      relativePath: 'migration/$archiveName',
      file: archiveFile,
      created: true,
    );
  }

  AvaloniaMigrationDefaults _migrationDefaults(CatalogSnapshot catalog) =>
      AvaloniaMigrationDefaults(
        applicationVersion: applicationVersion,
        modes: {
          for (final mode in CraftMode.values)
            mode: _modeMigrationDefaults(catalog.forMode(mode), mode),
        },
      );

  ModeMigrationDefaults _modeMigrationDefaults(
    ModeCatalog catalog,
    CraftMode mode,
  ) {
    final values = catalog.defaults;
    final target = _string(values['target']) ?? _firstCraftable(catalog);
    final yield = _number(values['yieldMult']) ?? 1;
    return ModeMigrationDefaults(
      target: target,
      want: _positiveInt(values['want'], fallback: 100),
      inventory: _numberMap(values['inv']),
      favoriteRecipes: _stringList(values['favoriteRecipes']),
      alchemyMastery: mode == CraftMode.alchemy
          ? alchemyMasteryForExpectedOutput(yield)
          : 0,
      processingMastery: mode == CraftMode.processing ? 2 : 0,
      alchemyYield: mode == CraftMode.alchemy ? yield : 3.2,
    );
  }

  PlannerState _freshState(CatalogSnapshot catalog) {
    ModeState stateFor(CraftMode mode) {
      final defaults = _modeMigrationDefaults(catalog.forMode(mode), mode);
      return ModeState(
        target: defaults.target,
        want: defaults.want,
        bonusTarget: defaults.target,
        bonusWant: defaults.want,
        inventory: const <String, double>{},
        favoriteRecipes: const <String>[],
        market: MarketState(amount: defaults.want, selected: defaults.target),
        appearance: AppearanceSettings.sakuraDefaultsFor(mode),
        alchemyMastery: 0,
        cookingMastery: 0,
        processingMastery: 0,
        compatibility: LegacyModeState(
          alchemyYield: mode == CraftMode.alchemy
              ? alchemyExpectedOutput(0, 1, 4)
              : defaults.alchemyYield,
        ),
      );
    }

    return PlannerState(
      applicationVersion: applicationVersion,
      lastSuccessfulWriteUtc: DateTime.fromMillisecondsSinceEpoch(
        0,
        isUtc: true,
      ),
      activeMode: CraftMode.alchemy,
      alchemy: stateFor(CraftMode.alchemy),
      cooking: stateFor(CraftMode.cooking),
      processing: stateFor(CraftMode.processing),
      processingYields: const {
        'defaultYield': 2.5,
        'Shaking': 0,
        'Grinding': 0,
        'Chopping': 0,
        'Drying': 0,
        'Heating': 0,
        'Filtering': 0,
        'Thinning': 0,
        'Simple Alchemy': 0,
        'Simple Cooking': 0,
        'Other': 0,
      },
      marketTax: MarketTax(),
      afkWeightProfile: AfkWeightProfile(safetyBufferLt: 0),
    );
  }

  _SakuraDefaultMigration _migrateFormerGreenhouseDefault(PlannerState state) {
    if (_hasCompletedSakuraDefaultMigration(state)) {
      return _SakuraDefaultMigration(
        state: state,
        requiresWrite: false,
        upgradedAppearance: false,
      );
    }
    // Before Sakura became the default, the candidate stored Greenhouse as the
    // selected background in every workstation. An unmarked all-Greenhouse
    // profile receives this one-time theme-identity update even when its
    // intensity, motion, presets, or extension controls were customized.
    // Mixed-background profiles are deliberate choices and remain untouched.
    final isAllGreenhouse = CraftMode.values.every(
      (mode) => state.forMode(mode).appearance.background == 'greenhouse',
    );
    final next = isAllGreenhouse
        ? state.copyWith(
            alchemy: _withSakuraAppearance(state.alchemy),
            cooking: _withSakuraAppearance(state.cooking),
            processing: _withSakuraAppearance(state.processing),
          )
        : state;
    return _SakuraDefaultMigration(
      state: _markSakuraDefaultMigrationComplete(next),
      requiresWrite: true,
      upgradedAppearance: isAllGreenhouse,
    );
  }

  bool _hasCompletedSakuraDefaultMigration(PlannerState state) {
    final value = state.extensions[sakuraDefaultMigrationMarkerKey];
    return value is num && value >= sakuraDefaultMigrationVersion;
  }

  PlannerState _markSakuraDefaultMigrationComplete(PlannerState state) {
    if (_hasCompletedSakuraDefaultMigration(state)) return state;
    return state.copyWith(
      extensions: <String, Object?>{
        ...state.extensions,
        sakuraDefaultMigrationMarkerKey: sakuraDefaultMigrationVersion,
      },
    );
  }

  ModeState _withSakuraAppearance(ModeState state) {
    final source = state.appearance;
    return state.copyWith(
      appearance: AppearanceSettings(
        background: 'sakura-night-garden',
        liveBackdrop: source.liveBackdrop,
        motionIntensity: source.motionIntensity,
        motionSpeed: source.motionSpeed,
        particleStyle: 'petals',
        particleDensity: source.particleDensity,
        particleOpacity: source.particleOpacity,
        particleMinSize: source.particleMinSize,
        particleMaxSize: source.particleMaxSize,
        particleSize: source.particleSize,
        particleBlur: source.particleBlur,
        particleCustomColor: source.particleCustomColor,
        particleHue: !source.particleCustomColor && !source.particleRainbow
            ? 341
            : source.particleHue,
        particleRainbow: source.particleRainbow,
        particleNeon: source.particleNeon,
        buttonEffect: source.buttonEffect,
        buttonEffectIntensity: source.buttonEffectIntensity,
        buttonEffectSpeed: source.buttonEffectSpeed,
        buttonEffectBlur: source.buttonEffectBlur,
        buttonEffectActiveOnly: source.buttonEffectActiveOnly,
        buttonEffectCustomColor: source.buttonEffectCustomColor,
        buttonEffectHue:
            !source.buttonEffectCustomColor && !source.buttonEffectRainbow
            ? 341
            : source.buttonEffectHue,
        buttonEffectRainbow: source.buttonEffectRainbow,
        buttonEffectNeon: source.buttonEffectNeon,
        accentHue: 341,
        rainbow: source.rainbow,
        neon: source.neon,
        backdropBlur: source.backdropBlur,
        tabFade: source.tabFade,
        tabTransition: source.tabTransition,
        tabTransitionSpeed: source.tabTransitionSpeed,
        presets: source.presets,
        extensions: source.extensions,
      ),
    );
  }
}

final class _PlannerStateCommit {
  const _PlannerStateCommit({required this.state, required this.write});

  final PlannerState state;
  final AtomicWriteResult write;
}

final class _LegacyArchive {
  const _LegacyArchive({
    required this.relativePath,
    required this.file,
    required this.created,
  });

  final String relativePath;
  final File file;
  final bool created;
}

final class _FormerNativeArchive {
  const _FormerNativeArchive({required this.file, required this.created});

  final File file;
  final bool created;
}

final class _SakuraDefaultMigration {
  const _SakuraDefaultMigration({
    required this.state,
    required this.requiresWrite,
    required this.upgradedAppearance,
  });

  final PlannerState state;
  final bool requiresWrite;
  final bool upgradedAppearance;
}

Iterable<CustomIconReference> _customIconReferences(PlannerState state) sync* {
  final seen = <String>{};
  for (final mode in CraftMode.values) {
    for (final reference in state.forMode(mode).customIcons.values) {
      final key = '${reference.relativePath}\u0000${reference.sha256}';
      if (seen.add(key)) yield reference;
    }
  }
}

bool _samePath(String left, String right) {
  String normalize(String value) => File(value).absolute.path
      .replaceAll('/', Platform.pathSeparator)
      .replaceAll('\\', Platform.pathSeparator)
      .toLowerCase();
  return normalize(left) == normalize(right);
}

String _firstCraftable(ModeCatalog catalog) {
  final names =
      catalog.items.entries
          .where((entry) => entry.value.isCraftable)
          .map((entry) => entry.key)
          .toList()
        ..sort();
  return names.isEmpty ? '' : names.first;
}

Map<String, Object?> _map(Object? value) {
  if (value is! Map) return const {};
  return value.map((key, item) => MapEntry('$key', item));
}

Map<String, double> _numberMap(Object? value) {
  final result = <String, double>{};
  for (final entry in _map(value).entries) {
    final number = _number(entry.value);
    if (number != null && number > 0) result[entry.key] = number;
  }
  return result;
}

List<String> _stringList(Object? value) => value is Iterable
    ? value.map(_string).whereType<String>().toList()
    : const [];

String? _string(Object? value) {
  if (value == null) return null;
  if (value is String) return value;
  if (value is num || value is bool) return '$value';
  return null;
}

double? _number(Object? value) {
  final result = value is num ? value.toDouble() : double.tryParse('$value');
  return result != null && result.isFinite ? result : null;
}

int _positiveInt(Object? value, {required int fallback}) {
  final number = _number(value);
  return number == null || number <= 0 ? fallback : number.floor();
}

String _join(String parent, String child) {
  final separator = Platform.pathSeparator;
  return parent.endsWith(separator)
      ? '$parent$child'
      : '$parent$separator$child';
}

bool _sameBytes(List<int> left, List<int> right) {
  if (left.length != right.length) return false;
  for (var index = 0; index < left.length; index++) {
    if (left[index] != right[index]) return false;
  }
  return true;
}
