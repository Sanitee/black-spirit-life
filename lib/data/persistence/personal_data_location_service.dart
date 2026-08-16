import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';

import '../../app_identity.dart';
import '../../domain/state/planner_state_json_codec.dart';
import 'atomic_file_store.dart';

enum PersonalDataMoveCheckpoint {
  copiedAndVerified,
  destinationPromoted,
  locatorSwitched,
  beforeSourceCleanup,
  sourceRemovedBeforeJournalCleanup,
}

typedef PersonalDataMoveCheckpointHook =
    FutureOr<void> Function(PersonalDataMoveCheckpoint checkpoint);
typedef PersonalDataSourceCleanup = Future<void> Function(Directory source);
typedef PersonalDataPhysicalPathResolver = Future<String> Function(String path);

final class PersonalDataMoveResult {
  const PersonalDataMoveResult({
    required this.fromPath,
    required this.toPath,
    required this.cleanupPending,
  });

  final String fromPath;
  final String toPath;
  final bool cleanupPending;
}

final class PersonalDataMoveException implements Exception {
  const PersonalDataMoveException(
    this.message, {
    required this.locationSwitched,
  });

  final String message;
  final bool locationSwitched;

  @override
  String toString() => message;
}

abstract interface class PersonalDataLocationManager {
  Directory get applicationDirectory;
  bool get moveSupported;
  bool get requiresExistingProfile;

  Future<Directory> resolveApplicationDirectory();
  Future<PersonalDataMoveResult> moveTo(String destinationPath);
}

/// Resolves the last private test profile as a read-only first-launch source.
///
/// Its package/channel identity is intentionally hard-coded instead of using
/// [AppIdentity], because the public application must never accept one of its
/// own locator files as a former profile. The committed mirror is authoritative
/// when present. An unfinished move or unreadable authoritative locator fails
/// closed so stale personal data is never imported silently.
final class FormerPersonalDataProfileResolver {
  const FormerPersonalDataProfileResolver();

  static const _formerPackageId = 'BlackSpiritLife.App.Beta';
  static const _formerReleaseChannel = 'win-x64-beta';
  static const _formerDirectoryName = 'Black Spirit Life Beta';
  static const _stateFileName = 'planner-state.json';
  static const _maximumIdentityBytes = 64 * 1024;

  Future<Directory> resolve(Map<String, String> environment) async {
    final roaming = environment['APPDATA']?.trim();
    final local = environment['LOCALAPPDATA']?.trim();
    if (roaming == null || roaming.isEmpty) {
      throw const FileSystemException(
        'APPDATA is unavailable; the former personal-data folder cannot be resolved.',
      );
    }
    if (local == null || local.isEmpty) {
      throw const FileSystemException(
        'LOCALAPPDATA is unavailable; the former personal-data locator cannot be resolved.',
      );
    }

    final defaultDirectory = Directory(_join(roaming, _formerDirectoryName));
    final controlDirectory = Directory(
      _join(
        _join(local, _formerDirectoryName),
        PersonalDataLocationService.bootstrapDirectoryName,
      ),
    );
    final journal = File(
      _join(controlDirectory.path, PersonalDataLocationService.journalFileName),
    );
    if (await FileSystemEntity.type(journal.path, followLinks: false) !=
        FileSystemEntityType.notFound) {
      throw FileSystemException(
        'The former test installation has an unfinished personal-data move. Open it once to complete recovery before importing it.',
        journal.path,
      );
    }

    final primary = await _readLocator(
      File(
        _join(
          controlDirectory.path,
          PersonalDataLocationService.locatorFileName,
        ),
      ),
    );
    final mirror = await _readLocator(
      File(
        _join(
          controlDirectory.path,
          PersonalDataLocationService.locatorMirrorFileName,
        ),
      ),
    );

    final Directory selected;
    if (mirror.directory case final committed?) {
      selected = committed;
    } else if (mirror.exists) {
      throw FileSystemException(
        'The committed former personal-data location is unreadable. No fallback profile was selected.',
        controlDirectory.path,
      );
    } else if (primary.directory case final legacy?) {
      selected = legacy;
    } else if (primary.exists) {
      throw FileSystemException(
        'The former personal-data location is unreadable. No fallback profile was selected.',
        controlDirectory.path,
      );
    } else {
      selected = defaultDirectory;
    }

    final type = await FileSystemEntity.type(selected.path, followLinks: false);
    if (type == FileSystemEntityType.notFound) return selected;
    if (type != FileSystemEntityType.directory) {
      throw FileSystemException(
        'The former personal-data location is not a normal folder.',
        selected.path,
      );
    }
    await _rejectLinksInAncestors(selected);
    await _rejectLinksInTree(selected);

    if (!_samePath(selected.path, defaultDirectory.path)) {
      await _verifyOwnedCustomProfile(selected);
      final state = File(_join(selected.path, _stateFileName));
      if (await FileSystemEntity.type(state.path, followLinks: false) !=
          FileSystemEntityType.file) {
        throw FileSystemException(
          'The former custom personal-data folder has no valid planner state to import.',
          state.path,
        );
      }
    }
    return selected;
  }

  Future<_FormerLocatorCopy> _readLocator(File file) async {
    final type = await FileSystemEntity.type(file.path, followLinks: false);
    if (type == FileSystemEntityType.notFound) {
      return const _FormerLocatorCopy.missing();
    }
    if (type != FileSystemEntityType.file) {
      return const _FormerLocatorCopy.invalid();
    }
    try {
      final decoded = await _readFormerIdentity(file);
      final value = decoded['applicationDirectory'];
      if (value is! String ||
          !RegExp(r'^[A-Za-z]:[\\/]').hasMatch(value.trim()) ||
          value.trim().startsWith(r'\\') ||
          value.trim().startsWith('\\\\?\\')) {
        throw const FormatException();
      }
      final normalized = _normalizeAbsolute(value.trim());
      if (_isRootPath(normalized)) throw const FormatException();
      return _FormerLocatorCopy.valid(Directory(normalized));
    } on Object {
      return const _FormerLocatorCopy.invalid();
    }
  }

  Future<void> _verifyOwnedCustomProfile(Directory directory) async {
    final marker = File(
      _join(directory.path, PersonalDataLocationService.profileMarkerFileName),
    );
    final decoded = await _readFormerIdentity(marker);
    final profileId = decoded['profileId'];
    final transactionId = decoded['transactionId'];
    final identity = RegExp(r'^[a-z]+-[a-f0-9]+-[a-f0-9]{32}$');
    if (decoded['profile'] != true ||
        profileId is! String ||
        transactionId is! String ||
        !identity.hasMatch(profileId) ||
        !identity.hasMatch(transactionId)) {
      throw FileSystemException(
        'The former custom personal-data folder has no valid ownership marker.',
        marker.path,
      );
    }
  }

  Future<Map<String, Object?>> _readFormerIdentity(File file) async {
    final type = await FileSystemEntity.type(file.path, followLinks: false);
    if (type != FileSystemEntityType.file ||
        await file.length() > _maximumIdentityBytes) {
      throw FileSystemException(
        'The former Black Spirit Life identity record is invalid.',
        file.path,
      );
    }
    final decoded = jsonDecode(utf8.decode(await file.readAsBytes()));
    if (decoded is! Map ||
        decoded['schemaVersion'] != PersonalDataLocationService.schemaVersion ||
        decoded['packageId'] != _formerPackageId ||
        decoded['releaseChannel'] != _formerReleaseChannel) {
      throw FileSystemException(
        'The former Black Spirit Life identity record is invalid.',
        file.path,
      );
    }
    return decoded.map((key, value) => MapEntry(key.toString(), value));
  }

  Future<void> _rejectLinksInAncestors(Directory directory) async {
    var current = directory;
    while (true) {
      if (await FileSystemEntity.type(current.path, followLinks: false) ==
          FileSystemEntityType.link) {
        throw FileSystemException(
          'The former personal-data path passes through a link or junction.',
          current.path,
        );
      }
      final parent = current.parent;
      if (_samePath(parent.path, current.path)) break;
      current = parent;
    }
  }

  Future<void> _rejectLinksInTree(Directory directory) async {
    await for (final entity in directory.list(
      recursive: true,
      followLinks: false,
    )) {
      if (await FileSystemEntity.type(entity.path, followLinks: false) ==
          FileSystemEntityType.link) {
        throw FileSystemException(
          'The former personal-data folder contains a link or junction.',
          entity.path,
        );
      }
    }
  }
}

final class _FormerLocatorCopy {
  const _FormerLocatorCopy._({required this.exists, this.directory});

  const _FormerLocatorCopy.missing() : this._(exists: false);
  const _FormerLocatorCopy.invalid() : this._(exists: true);
  const _FormerLocatorCopy.valid(Directory directory)
    : this._(exists: true, directory: directory);

  final bool exists;
  final Directory? directory;
}

/// Resolves and safely relocates the complete private per-PC profile.
///
/// The locator and move journal live outside the movable profile and outside
/// Velopack's install root. A move copies and hashes every profile file before
/// switching the locator. The source is removed only after the destination and
/// its planner document reopen successfully.
final class PersonalDataLocationService implements PersonalDataLocationManager {
  PersonalDataLocationService({
    required this.defaultDirectory,
    required this.controlDirectory,
    Iterable<Directory> protectedDirectories = const <Directory>[],
    this.moveSupported = true,
    DateTime Function()? utcNow,
    this.checkpointHook,
    PersonalDataSourceCleanup? sourceCleanup,
    PersonalDataPhysicalPathResolver? physicalPathResolver,
    AtomicFileCommitter locatorCommitter = const RenameAtomicFileCommitter(),
  }) : protectedDirectories = List<Directory>.unmodifiable(
         protectedDirectories,
       ),
       _utcNow = utcNow ?? (() => DateTime.now().toUtc()),
       _sourceCleanup = sourceCleanup ?? _deletePersonalDataSource,
       _physicalPathResolver = physicalPathResolver ?? _resolvePhysicalPath,
       _locatorStore = AtomicFileStore(
         directory: controlDirectory,
         fileName: locatorFileName,
         backupsToKeep: 2,
         utcNow: utcNow,
         committer: locatorCommitter,
       ),
       _locatorMirrorStore = AtomicFileStore(
         directory: controlDirectory,
         fileName: locatorMirrorFileName,
         backupsToKeep: 2,
         utcNow: utcNow,
       ),
       _journalStore = AtomicFileStore(
         directory: controlDirectory,
         fileName: journalFileName,
         backupsToKeep: 2,
         utcNow: utcNow,
       );

  factory PersonalDataLocationService.fromEnvironment(
    Map<String, String> environment, {
    String? resolvedExecutable,
    Iterable<Directory> additionalProtectedDirectories = const <Directory>[],
  }) {
    final roaming = environment['APPDATA']?.trim();
    final local = environment['LOCALAPPDATA']?.trim();
    if (roaming == null || roaming.isEmpty) {
      throw const FileSystemException(
        'APPDATA is unavailable; the personal-data folder cannot be resolved.',
      );
    }
    if (local == null || local.isEmpty) {
      throw const FileSystemException(
        'LOCALAPPDATA is unavailable; the personal-data locator cannot be resolved.',
      );
    }
    final defaultDirectory = Directory(
      _join(roaming, AppIdentity.stateDirectoryName),
    );
    final localIdentityRoot = Directory(
      _join(local, AppIdentity.localCacheDirectoryName),
    );
    final executableDirectory = File(
      resolvedExecutable ?? Platform.resolvedExecutable,
    ).parent;
    final velopackInstallRoot = _velopackInstallRoot(executableDirectory);
    final protected = <Directory>[
      localIdentityRoot,
      Directory(_join(local, AppIdentity.installerPackageId)),
      Directory(_join(roaming, AppIdentity.formerStateDirectoryName)),
      ...additionalProtectedDirectories,
      executableDirectory,
      ?velopackInstallRoot,
      for (final key in const <String>[
        'WINDIR',
        'ProgramFiles',
        'ProgramFiles(x86)',
        'ProgramData',
      ])
        if (environment[key]?.trim() case final value? when value.isNotEmpty)
          Directory(value),
    ];
    return PersonalDataLocationService(
      defaultDirectory: defaultDirectory,
      controlDirectory: Directory(
        _join(localIdentityRoot.path, bootstrapDirectoryName),
      ),
      protectedDirectories: protected,
    );
  }

  factory PersonalDataLocationService.fixed(Directory applicationDirectory) =>
      PersonalDataLocationService(
        defaultDirectory: applicationDirectory,
        controlDirectory: Directory(
          _join(applicationDirectory.parent.path, '.bsl-fixed-bootstrap'),
        ),
        moveSupported: false,
      );

  static const int schemaVersion = 1;
  static const String bootstrapDirectoryName = 'Bootstrap';
  static const String locatorFileName = 'personal-data-location.json';
  static const String locatorMirrorFileName =
      'personal-data-location.committed.json';
  static const String journalFileName = 'personal-data-move-journal.json';
  static const String profileMarkerFileName = '.black-spirit-life-profile.json';
  static const String moveManifestFileName =
      '.black-spirit-life-move-manifest.json';
  static const String moveSourceSentinelFileName =
      '.black-spirit-life-move-source.json';
  static const String moveStageSentinelFileName =
      '.black-spirit-life-move-stage.json';

  final Directory defaultDirectory;
  final Directory controlDirectory;
  final List<Directory> protectedDirectories;
  @override
  final bool moveSupported;
  final DateTime Function() _utcNow;
  final PersonalDataMoveCheckpointHook? checkpointHook;
  final PersonalDataSourceCleanup _sourceCleanup;
  final PersonalDataPhysicalPathResolver _physicalPathResolver;
  final AtomicFileStore _locatorStore;
  final AtomicFileStore _locatorMirrorStore;
  final AtomicFileStore _journalStore;

  Directory? _resolvedDirectory;
  bool _moveInProgress = false;
  bool _requiresExistingProfile = false;
  final List<String> _startupNotices = <String>[];
  final Random _secureRandom = Random.secure();

  @override
  Directory get applicationDirectory => _resolvedDirectory ?? defaultDirectory;

  @override
  bool get requiresExistingProfile => _requiresExistingProfile;

  List<String> get startupNotices => List<String>.unmodifiable(_startupNotices);

  void addStartupNotice(String notice) {
    final normalized = notice.trim();
    if (normalized.isNotEmpty && !_startupNotices.contains(normalized)) {
      _startupNotices.add(normalized);
    }
  }

  File get locatorFile => File(_locatorStore.targetPath);
  File get locatorMirrorFile => File(_locatorMirrorStore.targetPath);
  File get journalFile => File(_journalStore.targetPath);

  @override
  Future<Directory> resolveApplicationDirectory() async {
    _startupNotices.clear();
    final recovered = await _recoverInterruptedMove();
    if (recovered != null) {
      _requiresExistingProfile = await _readLocator() != null;
      await _verifyConfiguredDirectoryIdentity(recovered);
      return _resolvedDirectory = recovered;
    }
    final configured = await _readLocator();
    if (configured == null) {
      _requiresExistingProfile = false;
      return _resolvedDirectory = Directory(
        _normalizeAbsolute(defaultDirectory.path),
      );
    }
    _requiresExistingProfile = true;
    await _verifyConfiguredDirectoryIdentity(configured);
    return _resolvedDirectory = configured;
  }

  @override
  Future<PersonalDataMoveResult> moveTo(String destinationPath) async {
    if (!moveSupported) {
      throw const PersonalDataMoveException(
        'Changing the personal-data folder is unavailable in this session.',
        locationSwitched: false,
      );
    }
    if (_moveInProgress) {
      throw const PersonalDataMoveException(
        'A personal-data move is already in progress.',
        locationSwitched: false,
      );
    }
    _moveInProgress = true;
    var locatorSwitched = false;
    Directory? staging;
    Directory? destination;
    var destinationExistedEmpty = false;
    String? profileId;
    String? transactionId;
    try {
      final source = await resolveApplicationDirectory();
      _validateCurrentSourceLocation(source);
      if (await journalFile.exists()) {
        throw const FileSystemException(
          'A previous personal-data move still needs recovery or cleanup before another move can start.',
        );
      }
      destination = Directory(_validateDestination(source, destinationPath));
      await _verifySourceProfile(source);
      await _rejectLinksInExistingAncestors(destination);
      await _rejectLinksInExistingAncestors(source);
      destination = Directory(await _physicalPathResolver(destination.path));
      await _validatePhysicalMovePaths(
        source: source,
        destination: destination,
      );
      destinationExistedEmpty = await _validateDestinationContents(destination);

      final token = _utcNow().microsecondsSinceEpoch;
      profileId = await _profileIdForSource(source) ?? _newIdentity('profile');
      transactionId = _newIdentity('move');
      staging = Directory('${destination.path}.bsl-move-stage-$token');
      if (await FileSystemEntity.type(staging.path, followLinks: false) !=
          FileSystemEntityType.notFound) {
        throw const FileSystemException(
          'The temporary move folder already exists.',
        );
      }

      await _writeTransactionSentinel(
        source,
        fileName: moveSourceSentinelFileName,
        profileId: profileId,
        transactionId: transactionId,
        kind: 'source',
      );
      await _writeJournal(
        phase: 'copying',
        source: source,
        destination: destination,
        staging: staging,
        destinationExistedEmpty: destinationExistedEmpty,
        profileId: profileId,
        transactionId: transactionId,
      );
      await staging.create(recursive: true);
      await _writeTransactionSentinel(
        staging,
        fileName: moveStageSentinelFileName,
        profileId: profileId,
        transactionId: transactionId,
        kind: 'staging',
      );
      final manifest = await _copyProfile(source, staging);
      await _writeProfileMarker(staging, profileId, transactionId);
      await _writeMoveManifest(
        staging,
        manifest,
        profileId: profileId,
        transactionId: transactionId,
      );
      await _verifyOwnedDestination(staging, profileId, transactionId);
      await _writeJournal(
        phase: 'copiedAndVerified',
        source: source,
        destination: destination,
        staging: staging,
        destinationExistedEmpty: destinationExistedEmpty,
        profileId: profileId,
        transactionId: transactionId,
      );
      await _checkpoint(PersonalDataMoveCheckpoint.copiedAndVerified);

      final targetDirectory = destination;
      final stagingDirectory = staging;
      if (destinationExistedEmpty) await targetDirectory.delete();
      try {
        destination = await stagingDirectory.rename(targetDirectory.path);
      } on Object {
        if (destinationExistedEmpty && !await targetDirectory.exists()) {
          await targetDirectory.create(recursive: true);
        }
        rethrow;
      }
      staging = null;
      await _verifyOwnedDestination(destination, profileId, transactionId);
      await _writeJournal(
        phase: 'destinationPromoted',
        source: source,
        destination: destination,
        staging: null,
        destinationExistedEmpty: destinationExistedEmpty,
        profileId: profileId,
        transactionId: transactionId,
      );
      await _checkpoint(PersonalDataMoveCheckpoint.destinationPromoted);

      try {
        await _writeLocator(destination);
        locatorSwitched = true;
      } on Object catch (error) {
        final outcome = await _locatorCommitOutcome(
          source: source,
          destination: destination,
        );
        if (outcome == _LocatorCommitOutcome.destination) {
          locatorSwitched = true;
        } else if (outcome == _LocatorCommitOutcome.ambiguous) {
          locatorSwitched = true;
          throw StateError(
            'The personal-data location switch has an unknown commit state. Both verified copies and the recovery journal were preserved. $error',
          );
        } else {
          rethrow;
        }
      }
      _resolvedDirectory = destination;
      _requiresExistingProfile = true;
      await _writeJournal(
        phase: 'locatorSwitched',
        source: source,
        destination: destination,
        staging: null,
        destinationExistedEmpty: destinationExistedEmpty,
        profileId: profileId,
        transactionId: transactionId,
      );
      await _checkpoint(PersonalDataMoveCheckpoint.locatorSwitched);
      await _verifyOwnedDestination(destination, profileId, transactionId);
      await _checkpoint(PersonalDataMoveCheckpoint.beforeSourceCleanup);

      var cleanupPending = false;
      try {
        if (await source.exists()) {
          await _requireTransactionSentinel(
            source,
            fileName: moveSourceSentinelFileName,
            profileId: profileId,
            transactionId: transactionId,
            kind: 'source',
          );
          await _sourceCleanup(source);
        }
      } on FileSystemException {
        cleanupPending = true;
      }
      if (!cleanupPending) {
        await _checkpoint(
          PersonalDataMoveCheckpoint.sourceRemovedBeforeJournalCleanup,
        );
        await _removeJournal();
        try {
          await _removeMoveMetadata(destination);
        } on FileSystemException {
          // The locator is committed and the recovery journal is gone. Move
          // metadata is harmless and can remain if best-effort cleanup fails.
        }
      }
      return PersonalDataMoveResult(
        fromPath: source.path,
        toPath: destination.path,
        cleanupPending: cleanupPending,
      );
    } on PersonalDataMoveException {
      rethrow;
    } on Object catch (error) {
      if (!locatorSwitched) {
        await _rollbackBeforeLocatorSwitch(
          source: _resolvedDirectory,
          staging: staging,
          destination: destination,
          destinationExistedEmpty: destinationExistedEmpty,
          profileId: profileId,
          transactionId: transactionId,
        );
      }
      throw PersonalDataMoveException(
        'The personal-data folder was not moved. $error',
        locationSwitched: locatorSwitched,
      );
    } finally {
      _moveInProgress = false;
    }
  }

  Future<Directory?> _recoverInterruptedMove() async {
    if (!await journalFile.exists()) return null;
    final journal = await _readIdentityJson(journalFile, kind: 'move journal');
    final phase = _requiredMovePhase(journal);
    final profileId = _requiredIdentity(journal, 'profileId');
    final transactionId = _requiredIdentity(journal, 'transactionId');
    final source = Directory(_requiredPath(journal, 'sourcePath'));
    final destination = Directory(_requiredPath(journal, 'destinationPath'));
    final stagingValue = journal['stagingPath'];
    final staging = stagingValue is String && stagingValue.trim().isNotEmpty
        ? Directory(_normalizeAbsolute(stagingValue))
        : null;
    final destinationExistedEmpty = journal['destinationExistedEmpty'] == true;
    // A previously selected custom profile may point into an application,
    // bootstrap, cache, or system tree. Refuse the recovery before it can
    // delete even a transaction sentinel from that source.
    _validateCurrentSourceLocation(source);
    _validateRecoveryPaths(
      source: source,
      destination: destination,
      staging: staging,
    );
    await _rejectLinksInExistingAncestors(source);
    await _rejectLinksInExistingAncestors(destination);
    if (staging != null) await _rejectLinksInExistingAncestors(staging);
    await _validatePhysicalMovePaths(
      source: source,
      destination: destination,
      staging: staging,
    );
    final configured = await _readLocator();
    if (configured != null && _samePath(configured.path, destination.path)) {
      if (phase != 'destinationPromoted' && phase != 'locatorSwitched') {
        throw const FileSystemException(
          'The personal-data recovery journal phase conflicts with the committed location. No folder was changed.',
        );
      }
      await _verifyOwnedDestination(destination, profileId, transactionId);
      try {
        if (await source.exists()) {
          await _requireTransactionSentinel(
            source,
            fileName: moveSourceSentinelFileName,
            profileId: profileId,
            transactionId: transactionId,
            kind: 'source',
          );
          await _sourceCleanup(source);
        }
      } on FileSystemException {
        _startupNotices.add(
          'Personal data is safely using ${destination.path}. The previous folder at ${source.path} could not be removed yet; keep it available and cleanup will retry next start.',
        );
        return destination;
      }
      try {
        await _removeJournal();
      } on FileSystemException {
        _startupNotices.add(
          'Personal data is safely using ${destination.path}. Final move cleanup is still pending and will retry next start.',
        );
        return destination;
      }
      try {
        await _removeMoveMetadata(destination);
      } on FileSystemException {
        // The active profile remains valid; only internal move metadata is
        // left behind after the authoritative journal was removed.
      }
      return destination;
    }

    final expectedSource = configured ?? defaultDirectory;
    if (!_samePath(expectedSource.path, source.path)) {
      throw const FileSystemException(
        'The personal-data recovery journal does not match the active source. No folder was changed.',
      );
    }
    await _rollbackBeforeLocatorSwitch(
      source: source,
      staging: staging,
      destination: destination,
      destinationExistedEmpty: destinationExistedEmpty,
      profileId: profileId,
      transactionId: transactionId,
    );
    if (await journalFile.exists()) {
      throw const FileSystemException(
        'The interrupted personal-data move could not be cleaned up safely. No profile was selected.',
      );
    }
    return configured;
  }

  Future<List<_ProfileFileRecord>> _copyProfile(
    Directory source,
    Directory staging,
  ) async {
    await staging.create(recursive: true);
    final records = <_ProfileFileRecord>[];
    await for (final entity in source.list(
      recursive: true,
      followLinks: false,
    )) {
      final type = await FileSystemEntity.type(entity.path, followLinks: false);
      if (type == FileSystemEntityType.link) {
        throw FileSystemException(
          'Personal data contains a link or junction and cannot be moved safely.',
          entity.path,
        );
      }
      final relative = _relativePath(source.path, entity.path);
      if (relative == profileMarkerFileName ||
          relative == moveManifestFileName ||
          relative == moveSourceSentinelFileName ||
          relative == moveStageSentinelFileName) {
        continue;
      }
      final targetPath = _join(staging.path, relative);
      if (type == FileSystemEntityType.directory) {
        await Directory(targetPath).create(recursive: true);
        continue;
      }
      if (type != FileSystemEntityType.file) continue;
      final input = File(entity.path);
      final output = File(targetPath);
      await output.parent.create(recursive: true);
      await _copyFileAndFlush(input, output);
      records.add(
        _ProfileFileRecord(
          relativePath: relative,
          byteCount: await input.length(),
          sha256: await _sha256File(input),
        ),
      );
    }
    records.sort(
      (left, right) => left.relativePath.compareTo(right.relativePath),
    );
    return List<_ProfileFileRecord>.unmodifiable(records);
  }

  Future<void> _verifyCopiedProfile(
    Directory directory,
    List<_ProfileFileRecord> manifest,
  ) async {
    final expectedFiles = manifest
        .map((record) => record.relativePath.toLowerCase())
        .toSet();
    await for (final entity in directory.list(
      recursive: true,
      followLinks: false,
    )) {
      final type = await FileSystemEntity.type(entity.path, followLinks: false);
      if (type == FileSystemEntityType.link) {
        throw FileSystemException(
          'The copied personal-data folder contains a link or junction.',
          entity.path,
        );
      }
      if (type != FileSystemEntityType.file) continue;
      final relative = _relativePath(directory.path, entity.path).toLowerCase();
      if (relative == profileMarkerFileName.toLowerCase() ||
          relative == moveManifestFileName.toLowerCase() ||
          relative == moveStageSentinelFileName.toLowerCase()) {
        continue;
      }
      if (!expectedFiles.contains(relative)) {
        throw FileSystemException(
          'The copied personal-data folder contains an unexpected file.',
          entity.path,
        );
      }
    }
    for (final record in manifest) {
      final file = File(_join(directory.path, record.relativePath));
      if (!await file.exists() || await file.length() != record.byteCount) {
        throw FileSystemException(
          'A copied personal-data file is missing or has the wrong size.',
          file.path,
        );
      }
      if (await _sha256File(file) != record.sha256) {
        throw FileSystemException(
          'A copied personal-data file failed verification.',
          file.path,
        );
      }
    }
    await _verifyProfileDocument(directory);
  }

  Future<void> _verifySourceProfile(Directory source) async {
    if (!await source.exists()) {
      throw FileSystemException(
        'The current personal-data folder is missing.',
        source.path,
      );
    }
    await _rejectLinksInProfileTree(source);
    await _verifyProfileDocument(source);
  }

  Future<void> _verifyRollbackSource(
    Directory source,
    String profileId,
    String transactionId,
  ) async {
    if (!await source.exists()) {
      throw FileSystemException(
        'The original personal-data folder is unavailable. The verified move copy was preserved.',
        source.path,
      );
    }
    await _rejectLinksInExistingAncestors(source);
    await _requireTransactionSentinel(
      source,
      fileName: moveSourceSentinelFileName,
      profileId: profileId,
      transactionId: transactionId,
      kind: 'source',
    );
    await _rejectLinksInProfileTree(source);
    await _verifyRecoverableProfileDocument(source);
  }

  Future<void> _verifyRecoverableProfileDocument(Directory directory) async {
    final candidates = <File>[
      File(_join(directory.path, 'planner-state.json')),
      ...await directory
          .list(followLinks: false)
          .where(
            (entity) =>
                entity is File &&
                entity.uri.pathSegments.last.startsWith(
                  'planner-state.json.backup-',
                ),
          )
          .cast<File>()
          .toList(),
    ];
    candidates.sort((left, right) {
      final leftMain = left.uri.pathSegments.last == 'planner-state.json';
      final rightMain = right.uri.pathSegments.last == 'planner-state.json';
      if (leftMain != rightMain) return leftMain ? -1 : 1;
      return right.path.compareTo(left.path);
    });
    for (final candidate in candidates) {
      if (!await candidate.exists()) continue;
      try {
        const PlannerStateJsonCodec().decode(await candidate.readAsString());
        return;
      } on Object {
        // Keep looking for the newest valid retained backup.
      }
    }
    throw FileSystemException(
      'The original personal-data folder has no recoverable planner state. The verified move copy was preserved.',
      directory.path,
    );
  }

  Future<void> _verifyConfiguredDirectoryIdentity(Directory directory) async {
    if (!await directory.exists()) {
      throw FileSystemException(
        'The configured personal-data folder is unavailable. Reconnect it or restore the folder before starting Black Spirit Life.',
        directory.path,
      );
    }
    await _rejectLinksInExistingAncestors(directory);
    await _validatePhysicalCurrentSourceLocation(directory);
    await _rejectLinksInProfileTree(directory);
    if (!_samePath(directory.path, defaultDirectory.path) &&
        !await _hasOwnedProfileMarker(directory)) {
      throw FileSystemException(
        'The configured folder is not a verified Black Spirit Life profile.',
        directory.path,
      );
    }
  }

  Future<void> _verifyProfileDocument(Directory directory) async {
    final file = File(_join(directory.path, 'planner-state.json'));
    if (!await file.exists()) {
      throw FileSystemException(
        'The personal-data folder has no planner state.',
        file.path,
      );
    }
    try {
      const PlannerStateJsonCodec().decode(await file.readAsString());
    } on Object catch (error) {
      throw FileSystemException(
        'The personal-data folder contains an invalid planner state: $error',
        file.path,
      );
    }
  }

  Future<void> _rejectLinksInProfileTree(Directory directory) async {
    if (!await directory.exists()) return;
    await for (final entity in directory.list(
      recursive: true,
      followLinks: false,
    )) {
      if (await FileSystemEntity.type(entity.path, followLinks: false) ==
          FileSystemEntityType.link) {
        throw FileSystemException(
          'The personal-data folder contains a link or junction.',
          entity.path,
        );
      }
    }
  }

  Future<bool> _validateDestinationContents(Directory destination) async {
    final type = await FileSystemEntity.type(
      destination.path,
      followLinks: false,
    );
    if (type == FileSystemEntityType.notFound) return false;
    if (type == FileSystemEntityType.link) {
      throw FileSystemException(
        'Choose a normal local folder, not a link or junction.',
        destination.path,
      );
    }
    if (type != FileSystemEntityType.directory) {
      throw FileSystemException(
        'The selected personal-data path is not a folder.',
        destination.path,
      );
    }
    if (await destination.list(followLinks: false).isEmpty) return true;
    throw FileSystemException(
      'Choose a new or empty folder so unrelated files are never overwritten.',
      destination.path,
    );
  }

  void _validateCurrentSourceLocation(Directory source) {
    for (final protected in <Directory>[
      controlDirectory,
      ...protectedDirectories,
    ]) {
      if (_pathsOverlap(protected.path, source.path)) {
        throw FileSystemException(
          'The current personal-data folder overlaps an application, cache, bootstrap, or system location. It was not copied or changed.',
          source.path,
        );
      }
    }
  }

  Future<void> _validatePhysicalCurrentSourceLocation(Directory source) async {
    final physicalSource = await _requiredPhysicalPath(source);
    for (final protected in <Directory>[
      controlDirectory,
      ...protectedDirectories,
    ]) {
      final physicalProtected = await _requiredPhysicalPath(protected);
      if (_pathsOverlap(physicalProtected, physicalSource)) {
        throw FileSystemException(
          'The current personal-data folder resolves inside an application, cache, bootstrap, or system location. It was not copied or changed.',
          source.path,
        );
      }
    }
  }

  Future<void> _validatePhysicalMovePaths({
    required Directory source,
    required Directory destination,
    Directory? staging,
  }) async {
    final physicalSource = await _requiredPhysicalPath(source);
    final physicalDestination = await _requiredPhysicalPath(destination);
    if (_pathsOverlap(physicalSource, physicalDestination)) {
      throw const FileSystemException(
        'Choose a folder outside the current personal-data folder.',
      );
    }
    await _validatePhysicalCurrentSourceLocation(source);
    for (final protected in <Directory>[
      controlDirectory,
      ...protectedDirectories,
    ]) {
      final physicalProtected = await _requiredPhysicalPath(protected);
      if (_pathsOverlap(physicalProtected, physicalDestination)) {
        throw FileSystemException(
          'That folder resolves inside an application, cache, or system location.',
          destination.path,
        );
      }
    }
    if (staging == null) return;
    final physicalStaging = await _requiredPhysicalPath(staging);
    if (_pathsOverlap(physicalSource, physicalStaging) ||
        _pathsOverlap(physicalDestination, physicalStaging)) {
      throw const FileSystemException(
        'The personal-data recovery staging path resolves to an unsafe folder.',
      );
    }
    for (final protected in <Directory>[
      controlDirectory,
      ...protectedDirectories,
    ]) {
      final physicalProtected = await _requiredPhysicalPath(protected);
      if (_pathsOverlap(physicalProtected, physicalStaging)) {
        throw const FileSystemException(
          'The personal-data recovery staging path resolves inside a protected folder.',
        );
      }
    }
  }

  Future<String> _requiredPhysicalPath(Directory directory) async {
    try {
      final resolved = await _physicalPathResolver(directory.path);
      if (resolved.trim().isEmpty) throw const FormatException();
      return _trimPath(resolved);
    } on Object catch (error) {
      throw FileSystemException(
        'Windows could not verify the physical folder location: $error',
        directory.path,
      );
    }
  }

  String _validateDestination(Directory source, String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty ||
        trimmed.startsWith(r'\\') ||
        trimmed.startsWith(r'\\?\') ||
        !RegExp(r'^[A-Za-z]:[\\/]').hasMatch(trimmed)) {
      throw const FileSystemException(
        'Choose an absolute local folder on this PC.',
      );
    }
    final destination = _normalizeAbsolute(trimmed);
    if (_isRootPath(destination)) {
      throw const FileSystemException(
        'A drive root cannot be used as the personal-data folder.',
      );
    }
    _validateWindowsSegments(destination);
    if (_pathsOverlap(source.path, destination)) {
      throw const FileSystemException(
        'Choose a folder outside the current personal-data folder.',
      );
    }
    for (final protected in <Directory>[
      controlDirectory,
      ...protectedDirectories,
    ]) {
      if (_pathsOverlap(protected.path, destination)) {
        throw FileSystemException(
          'That folder overlaps an application, cache, or system location.',
          destination,
        );
      }
    }
    return destination;
  }

  Future<void> _rejectLinksInExistingAncestors(Directory directory) async {
    var current = directory;
    while (true) {
      final type = await FileSystemEntity.type(
        current.path,
        followLinks: false,
      );
      if (type == FileSystemEntityType.link) {
        throw FileSystemException(
          'The selected path passes through a link or junction.',
          current.path,
        );
      }
      final parent = current.parent;
      if (_samePath(parent.path, current.path)) break;
      current = parent;
    }
  }

  Future<void> _writeLocator(Directory directory) async {
    // The committed mirror is written first and is the authoritative recovery
    // copy. The ordinary locator is then refreshed. The source profile and
    // move journal remain in place unless both writes can be read back.
    await _writeLocatorCopy(_locatorMirrorStore, directory);
    await _writeLocatorCopy(_locatorStore, directory);
  }

  Future<void> _writeLocatorCopy(AtomicFileStore store, Directory directory) =>
      store.writeJson(
        _identityJson(<String, Object?>{
          'applicationDirectory': _normalizeAbsolute(directory.path),
        }),
        validate: (bytes) {
          final value = _decodeIdentityBytes(bytes, kind: 'location');
          _requiredPath(value, 'applicationDirectory');
        },
      );

  Future<Directory?> _readLocator() async {
    final primary = await _readLocatorCopy(locatorFile);
    final mirror = await _readLocatorCopy(locatorMirrorFile);
    final authoritative = mirror.directory;
    if (authoritative != null) {
      if (primary.directory == null ||
          !_samePath(primary.directory!.path, authoritative.path)) {
        await _repairLocatorCopy(
          _locatorStore,
          locatorFile,
          primary,
          authoritative,
        );
      }
      return authoritative;
    }
    final legacyPrimary = primary.directory;
    if (legacyPrimary != null) {
      await _repairLocatorCopy(
        _locatorMirrorStore,
        locatorMirrorFile,
        mirror,
        legacyPrimary,
      );
      return legacyPrimary;
    }
    if (!primary.exists && !mirror.exists) return null;
    throw FileSystemException(
      'The personal-data location records are unreadable. No fallback profile was selected.',
      controlDirectory.path,
    );
  }

  Future<_LocatorCopy> _readLocatorCopy(File file) async {
    final type = await FileSystemEntity.type(file.path, followLinks: false);
    if (type == FileSystemEntityType.notFound) {
      return const _LocatorCopy.missing();
    }
    if (type != FileSystemEntityType.file) {
      return const _LocatorCopy.invalid();
    }
    try {
      final value = await _readIdentityJson(file, kind: 'location');
      return _LocatorCopy.valid(
        Directory(_requiredPath(value, 'applicationDirectory')),
      );
    } on Object {
      return const _LocatorCopy.invalid();
    }
  }

  Future<void> _repairLocatorCopy(
    AtomicFileStore store,
    File file,
    _LocatorCopy existing,
    Directory directory,
  ) async {
    if (existing.exists && existing.directory == null && await file.exists()) {
      final timestamp = _utcNow().microsecondsSinceEpoch;
      var sequence = 0;
      File preserved;
      do {
        final suffix = sequence == 0 ? '' : '-$sequence';
        preserved = File('${file.path}.invalid-$timestamp$suffix');
        sequence += 1;
      } while (await preserved.exists());
      await file.rename(preserved.path);
    }
    await _writeLocatorCopy(store, directory);
  }

  Future<void> _writeJournal({
    required String phase,
    required Directory source,
    required Directory destination,
    required Directory? staging,
    required bool destinationExistedEmpty,
    required String profileId,
    required String transactionId,
  }) => _journalStore.writeJson(
    _identityJson(<String, Object?>{
      'phase': phase,
      'profileId': profileId,
      'transactionId': transactionId,
      'sourcePath': _normalizeAbsolute(source.path),
      'destinationPath': _normalizeAbsolute(destination.path),
      'stagingPath': staging == null ? null : _normalizeAbsolute(staging.path),
      'destinationExistedEmpty': destinationExistedEmpty,
    }),
    validate: (bytes) {
      final value = _decodeIdentityBytes(bytes, kind: 'move journal');
      _requiredMovePhase(value);
      _requiredIdentity(value, 'profileId');
      _requiredIdentity(value, 'transactionId');
      _requiredPath(value, 'sourcePath');
      _requiredPath(value, 'destinationPath');
    },
  );

  Future<void> _writeProfileMarker(
    Directory directory,
    String profileId,
    String transactionId,
  ) async {
    final file = File(_join(directory.path, profileMarkerFileName));
    await file.writeAsString(
      jsonEncode(
        _identityJson(<String, Object?>{
          'profile': true,
          'profileId': profileId,
          'transactionId': transactionId,
        }),
      ),
      flush: true,
    );
  }

  Future<bool> _hasOwnedProfileMarker(Directory directory) async {
    return await _readProfileMarker(directory) != null;
  }

  Future<_OwnedIdentity?> _readProfileMarker(Directory directory) async {
    final file = File(_join(directory.path, profileMarkerFileName));
    if (!await file.exists()) return null;
    try {
      final value = await _readIdentityJson(file, kind: 'profile marker');
      if (value['profile'] != true) return null;
      return _OwnedIdentity(
        profileId: _requiredIdentity(value, 'profileId'),
        transactionId: _requiredIdentity(value, 'transactionId'),
      );
    } on Object {
      return null;
    }
  }

  Future<String?> _profileIdForSource(Directory source) async =>
      (await _readProfileMarker(source))?.profileId;

  Future<void> _writeMoveManifest(
    Directory directory,
    List<_ProfileFileRecord> records, {
    required String profileId,
    required String transactionId,
  }) async {
    final file = File(_join(directory.path, moveManifestFileName));
    await file.writeAsString(
      jsonEncode(
        _identityJson(<String, Object?>{
          'profileId': profileId,
          'transactionId': transactionId,
          'files': records.map((record) => record.toJson()).toList(),
        }),
      ),
      flush: true,
    );
  }

  Future<List<_ProfileFileRecord>> _readMoveManifest(
    Directory directory,
    String profileId,
    String transactionId,
  ) async {
    final file = File(_join(directory.path, moveManifestFileName));
    if (!await file.exists()) {
      throw FileSystemException(
        'The verified personal-data move manifest is missing.',
        file.path,
      );
    }
    final value = await _readIdentityJson(file, kind: 'move manifest');
    if (_requiredIdentity(value, 'profileId') != profileId ||
        _requiredIdentity(value, 'transactionId') != transactionId) {
      throw FileSystemException(
        'The personal-data move manifest belongs to another transaction.',
        file.path,
      );
    }
    final files = value['files'];
    if (files is! List) {
      throw FileSystemException(
        'The personal-data move manifest has no valid file list.',
        file.path,
      );
    }
    final records = <_ProfileFileRecord>[];
    for (final entry in files) {
      records.add(_ProfileFileRecord.fromJson(entry));
    }
    final paths = records
        .map((record) => record.relativePath.toLowerCase())
        .toList();
    if (paths.toSet().length != paths.length) {
      throw FileSystemException(
        'The personal-data move manifest contains duplicate paths.',
        file.path,
      );
    }
    return List<_ProfileFileRecord>.unmodifiable(records);
  }

  Future<void> _verifyOwnedDestination(
    Directory directory,
    String profileId,
    String transactionId,
  ) async {
    await _requireOwnedProfileMarker(directory, profileId, transactionId);
    await _requireTransactionSentinel(
      directory,
      fileName: moveStageSentinelFileName,
      profileId: profileId,
      transactionId: transactionId,
      kind: 'staging',
    );
    final manifest = await _readMoveManifest(
      directory,
      profileId,
      transactionId,
    );
    await _verifyCopiedProfile(directory, manifest);
  }

  Future<void> _removeMoveManifest(Directory directory) async {
    final file = File(_join(directory.path, moveManifestFileName));
    if (await file.exists()) await file.delete();
  }

  Future<void> _removeMoveMetadata(Directory directory) async {
    await _removeMoveManifest(directory);
    final stageSentinel = File(
      _join(directory.path, moveStageSentinelFileName),
    );
    if (await stageSentinel.exists()) await stageSentinel.delete();
  }

  Future<void> _writeTransactionSentinel(
    Directory directory, {
    required String fileName,
    required String profileId,
    required String transactionId,
    required String kind,
  }) async {
    await directory.create(recursive: true);
    final file = File(_join(directory.path, fileName));
    await file.writeAsString(
      jsonEncode(
        _identityJson(<String, Object?>{
          'kind': kind,
          'profileId': profileId,
          'transactionId': transactionId,
        }),
      ),
      flush: true,
    );
  }

  Future<void> _requireOwnedProfileMarker(
    Directory directory,
    String profileId,
    String transactionId,
  ) async {
    final marker = await _readProfileMarker(directory);
    if (marker == null ||
        marker.profileId != profileId ||
        marker.transactionId != transactionId) {
      throw FileSystemException(
        'The personal-data folder is not owned by this move transaction.',
        directory.path,
      );
    }
  }

  Future<void> _requireTransactionSentinel(
    Directory directory, {
    required String fileName,
    required String profileId,
    required String transactionId,
    required String kind,
  }) async {
    final file = File(_join(directory.path, fileName));
    if (!await file.exists()) {
      throw FileSystemException(
        'The personal-data $kind transaction marker is missing.',
        file.path,
      );
    }
    try {
      final value = await _readIdentityJson(file, kind: '$kind marker');
      if (value['kind'] != kind ||
          _requiredIdentity(value, 'profileId') != profileId ||
          _requiredIdentity(value, 'transactionId') != transactionId) {
        throw const FormatException('Transaction identity mismatch.');
      }
    } on Object catch (error) {
      throw FileSystemException(
        'The personal-data $kind transaction marker is invalid: $error',
        file.path,
      );
    }
  }

  Future<void> _removeTransactionSentinelIfOwned(
    Directory directory, {
    required String fileName,
    required String profileId,
    required String transactionId,
    required String kind,
  }) async {
    final file = File(_join(directory.path, fileName));
    if (!await file.exists()) return;
    await _requireTransactionSentinel(
      directory,
      fileName: fileName,
      profileId: profileId,
      transactionId: transactionId,
      kind: kind,
    );
    await file.delete();
  }

  void _validateRecoveryPaths({
    required Directory source,
    required Directory destination,
    required Directory? staging,
  }) {
    final validatedDestination = _validateDestination(source, destination.path);
    if (!_samePath(validatedDestination, destination.path)) {
      throw const FileSystemException(
        'The personal-data recovery destination is not canonical.',
      );
    }
    if (staging == null) return;
    final normalizedDestination = _normalizeAbsolute(destination.path);
    final normalizedStaging = _normalizeAbsolute(staging.path);
    final prefix = '$normalizedDestination.bsl-move-stage-';
    final suffix = normalizedStaging.length > prefix.length
        ? normalizedStaging.substring(prefix.length)
        : '';
    if (!normalizedStaging.toLowerCase().startsWith(prefix.toLowerCase()) ||
        suffix.isEmpty ||
        suffix.contains('/') ||
        suffix.contains('\\')) {
      throw const FileSystemException(
        'The personal-data recovery staging path is invalid.',
      );
    }
  }

  Future<_LocatorCommitOutcome> _locatorCommitOutcome({
    required Directory source,
    required Directory destination,
  }) async {
    try {
      final locator = await _readLocator();
      if (locator == null) return _LocatorCommitOutcome.source;
      if (_samePath(locator.path, destination.path)) {
        return _LocatorCommitOutcome.destination;
      }
      if (_samePath(locator.path, source.path)) {
        return _LocatorCommitOutcome.source;
      }
      return _LocatorCommitOutcome.ambiguous;
    } on Object {
      return _LocatorCommitOutcome.ambiguous;
    }
  }

  String _newIdentity(String kind) {
    final timestamp = _utcNow().microsecondsSinceEpoch.toRadixString(16);
    final entropy = List<String>.generate(
      4,
      (_) =>
          _secureRandom.nextInt(0x100000000).toRadixString(16).padLeft(8, '0'),
    ).join();
    return '$kind-$timestamp-$entropy';
  }

  String _requiredIdentity(Map<String, Object?> value, String key) {
    final identity = value[key];
    if (identity is! String ||
        !RegExp(r'^[a-z]+-[a-f0-9]+-[a-f0-9]{32}$').hasMatch(identity)) {
      throw FormatException(
        'The Black Spirit Life identity "$key" is invalid.',
      );
    }
    return identity;
  }

  String _requiredMovePhase(Map<String, Object?> value) {
    final phase = value['phase'];
    if (phase is! String ||
        !const <String>{
          'copying',
          'copiedAndVerified',
          'destinationPromoted',
          'locatorSwitched',
        }.contains(phase)) {
      throw const FormatException(
        'The Black Spirit Life move journal phase is invalid.',
      );
    }
    return phase;
  }

  Future<void> _rollbackBeforeLocatorSwitch({
    required Directory? source,
    required Directory? staging,
    required Directory? destination,
    required bool destinationExistedEmpty,
    required String? profileId,
    required String? transactionId,
  }) async {
    if (profileId == null || transactionId == null) return;
    try {
      if (source == null) {
        throw const FileSystemException(
          'The original personal-data folder could not be identified. The verified move copy was preserved.',
        );
      }
      // Prove that the original profile is still the authoritative,
      // recoverable copy before removing any transaction-owned copy. A drive
      // can disappear between promotion and rollback, and the destination may
      // then be the only complete profile left.
      await _verifyRollbackSource(source, profileId, transactionId);
      if (staging != null && await staging.exists()) {
        await _requireTransactionSentinel(
          staging,
          fileName: moveStageSentinelFileName,
          profileId: profileId,
          transactionId: transactionId,
          kind: 'staging',
        );
        await staging.delete(recursive: true);
      }
      if (destination != null && await destination.exists()) {
        final marker = await _readProfileMarker(destination);
        final owned =
            marker?.profileId == profileId &&
            marker?.transactionId == transactionId;
        if (owned) {
          await _requireTransactionSentinel(
            destination,
            fileName: moveStageSentinelFileName,
            profileId: profileId,
            transactionId: transactionId,
            kind: 'staging',
          );
          await destination.delete(recursive: true);
        } else if (!destinationExistedEmpty ||
            !await destination.list(followLinks: false).isEmpty) {
          throw FileSystemException(
            'The move destination is not owned by this transaction.',
            destination.path,
          );
        }
      }
      if (destinationExistedEmpty &&
          destination != null &&
          !await destination.exists()) {
        await destination.create(recursive: true);
      }
      await _removeTransactionSentinelIfOwned(
        source,
        fileName: moveSourceSentinelFileName,
        profileId: profileId,
        transactionId: transactionId,
        kind: 'source',
      );
      await _removeJournal();
    } on FileSystemException {
      // The source remains authoritative. Keep the journal so startup can
      // retry cleanup without ever adopting an unverified destination.
    }
  }

  Future<void> _removeJournal() async {
    if (await journalFile.exists()) await journalFile.delete();
  }

  Future<void> _checkpoint(PersonalDataMoveCheckpoint checkpoint) async {
    final hook = checkpointHook;
    if (hook != null) await hook(checkpoint);
  }

  Map<String, Object?> _identityJson(Map<String, Object?> values) =>
      <String, Object?>{
        'schemaVersion': schemaVersion,
        'packageId': AppIdentity.installerPackageId,
        'releaseChannel': AppIdentity.releaseChannel,
        ...values,
      };

  Future<Map<String, Object?>> _readIdentityJson(
    File file, {
    required String kind,
  }) async => _decodeIdentityBytes(await file.readAsBytes(), kind: kind);

  Map<String, Object?> _decodeIdentityBytes(
    List<int> bytes, {
    required String kind,
  }) {
    final decoded = jsonDecode(utf8.decode(bytes));
    if (decoded is! Map ||
        decoded['schemaVersion'] != schemaVersion ||
        decoded['packageId'] != AppIdentity.installerPackageId ||
        decoded['releaseChannel'] != AppIdentity.releaseChannel) {
      throw FormatException('The Black Spirit Life $kind is invalid.');
    }
    return decoded.map((key, value) => MapEntry(key.toString(), value));
  }

  String _requiredPath(Map<String, Object?> value, String key) {
    final path = value[key];
    if (path is! String || path.trim().isEmpty) {
      throw FormatException('The Black Spirit Life path "$key" is invalid.');
    }
    return _normalizeAbsolute(path);
  }
}

final class _ProfileFileRecord {
  const _ProfileFileRecord({
    required this.relativePath,
    required this.byteCount,
    required this.sha256,
  });

  factory _ProfileFileRecord.fromJson(Object? value) {
    if (value is! Map) {
      throw const FormatException('A move-manifest file record is invalid.');
    }
    final relativePath = value['relativePath'];
    final byteCount = value['byteCount'];
    final hash = value['sha256'];
    if (relativePath is! String ||
        !_isSafeManifestRelativePath(relativePath) ||
        byteCount is! int ||
        byteCount < 0 ||
        hash is! String ||
        !RegExp(r'^[A-Fa-f0-9]{64}$').hasMatch(hash)) {
      throw const FormatException('A move-manifest file record is invalid.');
    }
    return _ProfileFileRecord(
      relativePath: relativePath,
      byteCount: byteCount,
      sha256: hash.toLowerCase(),
    );
  }

  final String relativePath;
  final int byteCount;
  final String sha256;

  Map<String, Object?> toJson() => <String, Object?>{
    'relativePath': relativePath,
    'byteCount': byteCount,
    'sha256': sha256,
  };
}

final class _OwnedIdentity {
  const _OwnedIdentity({required this.profileId, required this.transactionId});

  final String profileId;
  final String transactionId;
}

enum _LocatorCommitOutcome { source, destination, ambiguous }

final class _LocatorCopy {
  const _LocatorCopy._({required this.exists, required this.directory});

  const _LocatorCopy.missing() : this._(exists: false, directory: null);

  const _LocatorCopy.invalid() : this._(exists: true, directory: null);

  const _LocatorCopy.valid(Directory value)
    : this._(exists: true, directory: value);

  final bool exists;
  final Directory? directory;
}

Future<void> _copyFileAndFlush(File source, File destination) async {
  final output = await destination.open(mode: FileMode.writeOnly);
  try {
    await for (final chunk in source.openRead()) {
      await output.writeFrom(chunk);
    }
    await output.flush();
  } finally {
    await output.close();
  }
}

Future<String> _sha256File(File file) async =>
    (await sha256.bind(file.openRead()).first).toString();

bool _isSafeManifestRelativePath(String value) {
  if (value.isEmpty ||
      value.startsWith('/') ||
      value.startsWith('\\') ||
      RegExp(r'^[A-Za-z]:').hasMatch(value)) {
    return false;
  }
  final segments = value.split(RegExp(r'[\\/]'));
  if (segments.any(
    (segment) => segment.isEmpty || segment == '.' || segment == '..',
  )) {
    return false;
  }
  final lower = value.toLowerCase();
  return lower !=
          PersonalDataLocationService.profileMarkerFileName.toLowerCase() &&
      lower != PersonalDataLocationService.moveManifestFileName.toLowerCase() &&
      lower !=
          PersonalDataLocationService.moveSourceSentinelFileName
              .toLowerCase() &&
      lower !=
          PersonalDataLocationService.moveStageSentinelFileName.toLowerCase();
}

String _relativePath(String root, String child) {
  final normalizedRoot = _normalizeAbsolute(root);
  final normalizedChild = _normalizeAbsolute(child);
  final prefix = normalizedRoot.endsWith(Platform.pathSeparator)
      ? normalizedRoot
      : '$normalizedRoot${Platform.pathSeparator}';
  if (!normalizedChild.toLowerCase().startsWith(prefix.toLowerCase())) {
    throw FileSystemException(
      'A personal-data entry escaped its source folder.',
      child,
    );
  }
  final relative = normalizedChild.substring(prefix.length);
  if (relative.isEmpty ||
      relative == '.' ||
      relative == '..' ||
      relative.split(RegExp(r'[\\/]')).contains('..')) {
    throw FileSystemException('An unsafe personal-data path was found.', child);
  }
  return relative;
}

String _normalizeAbsolute(String value) {
  final absolute = Directory(value).absolute.path;
  return Uri.file(
    absolute,
    windows: Platform.isWindows,
  ).normalizePath().toFilePath(windows: Platform.isWindows);
}

Future<String> _resolvePhysicalPath(String value) async {
  var current = Directory(_normalizeAbsolute(value));
  final missingSegments = <String>[];
  while (true) {
    final type = await FileSystemEntity.type(current.path, followLinks: false);
    if (type != FileSystemEntityType.notFound) {
      if (type != FileSystemEntityType.directory &&
          type != FileSystemEntityType.link) {
        throw FileSystemException(
          'The folder path resolves through a non-directory entry.',
          current.path,
        );
      }
      break;
    }
    final parent = current.parent;
    if (_samePath(parent.path, current.path)) {
      throw FileSystemException(
        'No existing folder ancestor could be resolved.',
        value,
      );
    }
    missingSegments.insert(0, _pathLeafName(current.path));
    current = parent;
  }
  var resolved = await current.resolveSymbolicLinks();
  for (final segment in missingSegments) {
    resolved = _join(resolved, segment);
  }
  return _normalizeAbsolute(resolved);
}

bool _samePath(String left, String right) =>
    _trimPath(left).toLowerCase() == _trimPath(right).toLowerCase();

bool _pathsOverlap(String left, String right) {
  final normalizedLeft = _trimPath(left).toLowerCase();
  final normalizedRight = _trimPath(right).toLowerCase();
  if (normalizedLeft == normalizedRight) return true;
  final separator = Platform.pathSeparator;
  return normalizedLeft.startsWith('$normalizedRight$separator') ||
      normalizedRight.startsWith('$normalizedLeft$separator');
}

Directory? _velopackInstallRoot(Directory executableDirectory) {
  final current = Directory(_normalizeAbsolute(executableDirectory.path));
  if (_pathLeafName(current.path).toLowerCase() != 'current') return null;
  final installRoot = current.parent;
  if (_samePath(installRoot.path, current.path) ||
      _isRootPath(installRoot.path)) {
    return null;
  }
  return installRoot;
}

String _pathLeafName(String path) {
  final normalized = _trimPath(path);
  final separator = max(
    normalized.lastIndexOf('\\'),
    normalized.lastIndexOf('/'),
  );
  return normalized.substring(separator + 1);
}

String _trimPath(String value) {
  var normalized = _normalizeAbsolute(value);
  while (normalized.length > 3 &&
      (normalized.endsWith('\\') || normalized.endsWith('/'))) {
    normalized = normalized.substring(0, normalized.length - 1);
  }
  return normalized;
}

bool _isRootPath(String path) {
  final directory = Directory(path);
  return _samePath(directory.path, directory.parent.path);
}

void _validateWindowsSegments(String path) {
  const reserved = <String>{
    'con',
    'prn',
    'aux',
    'nul',
    'com1',
    'com2',
    'com3',
    'com4',
    'com5',
    'com6',
    'com7',
    'com8',
    'com9',
    'lpt1',
    'lpt2',
    'lpt3',
    'lpt4',
    'lpt5',
    'lpt6',
    'lpt7',
    'lpt8',
    'lpt9',
  };
  final segments = path.split(RegExp(r'[\\/]')).skip(1);
  for (final segment in segments) {
    if (segment.isEmpty) continue;
    final leaf = segment.split('.').first.toLowerCase();
    if (segment.endsWith(' ') ||
        segment.endsWith('.') ||
        reserved.contains(leaf)) {
      throw FileSystemException(
        'The selected folder uses a Windows-reserved name.',
        path,
      );
    }
  }
}

String _join(String parent, String child) {
  final separator = Platform.pathSeparator;
  return parent.endsWith(separator)
      ? '$parent$child'
      : '$parent$separator$child';
}

Future<void> _deletePersonalDataSource(Directory source) =>
    source.delete(recursive: true);
