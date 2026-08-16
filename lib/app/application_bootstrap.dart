import 'dart:io';

import '../app_identity.dart';
import '../data/catalog/bundled_data_service.dart';
import '../data/icons/custom_icon_store.dart';
import '../data/persistence/personal_data_location_service.dart';
import '../data/persistence/planner_state_repository.dart';
import '../domain/models/catalog_models.dart';
import '../domain/models/craft_mode.dart';
import '../domain/state/planner_state.dart';
import '../domain/state/state_copy.dart';
import 'state/planner_application_controller.dart';

final class ApplicationBundle {
  const ApplicationBundle({
    required this.catalog,
    required this.stateLoad,
    required this.stateRepository,
    required this.personalDataLocation,
    required this.controller,
    this.startupNotices = const <String>[],
    this.firstLaunchMigration,
  });

  final CatalogSnapshot catalog;
  final PlannerStateLoadResult stateLoad;
  final PlannerStateRepository stateRepository;
  final PersonalDataLocationManager personalDataLocation;
  final PlannerApplicationController controller;
  final List<String> startupNotices;
  final ApplicationFirstLaunchMigration? firstLaunchMigration;
}

/// Explicit first-launch choice. The repository has only inspected an
/// in-memory copy while this object is present; neither choice has been
/// persisted and the Avalonia source has not been modified.
final class ApplicationFirstLaunchMigration {
  factory ApplicationFirstLaunchMigration({
    required PlannerStateMigrationPreview preview,
    required Future<ApplicationBundle> Function() accept,
    required Future<ApplicationBundle> Function() startFresh,
  }) => ApplicationFirstLaunchMigration._(preview, accept, startFresh);

  ApplicationFirstLaunchMigration._(
    this.preview,
    this._accept,
    this._startFresh,
  );

  final PlannerStateMigrationPreview preview;
  final Future<ApplicationBundle> Function() _accept;
  final Future<ApplicationBundle> Function() _startFresh;
  Future<ApplicationBundle>? _inFlight;
  bool _resolved = false;

  Future<ApplicationBundle> accept() => _resolve(_accept);

  Future<ApplicationBundle> startFresh() => _resolve(_startFresh);

  Future<ApplicationBundle> _resolve(
    Future<ApplicationBundle> Function() operation,
  ) async {
    if (_resolved) {
      throw StateError('The first-launch migration choice is already saved.');
    }
    if (_inFlight case final pending?) return pending;
    final pending = operation();
    _inFlight = pending;
    try {
      final bundle = await pending;
      _resolved = true;
      return bundle;
    } finally {
      _inFlight = null;
    }
  }
}

final class ApplicationBootstrapService {
  const ApplicationBootstrapService({
    this.applicationVersion = AppIdentity.applicationVersion,
  });

  final String applicationVersion;

  Future<ApplicationBundle> load({
    Future<CatalogSnapshot>? catalogFuture,
    PlannerStatePathPolicy? pathPolicy,
    PersonalDataLocationManager? personalDataLocation,
  }) async {
    final catalog = await (catalogFuture ?? BundledDataService().load());
    final basePaths =
        pathPolicy ??
        PlannerStatePathPolicy.fromEnvironment(Platform.environment);
    Directory? formerApplicationDirectory =
        pathPolicy != null || AppIdentity.importFormerProfilesOnFirstLaunch
        ? basePaths.formerNativeApplicationDirectory
        : null;
    Object? formerResolutionError;
    StackTrace? formerResolutionStackTrace;
    if (AppIdentity.importFormerProfilesOnFirstLaunch &&
        pathPolicy == null &&
        personalDataLocation == null) {
      try {
        formerApplicationDirectory =
            await const FormerPersonalDataProfileResolver().resolve(
              Platform.environment,
            );
      } on Object catch (error, stackTrace) {
        formerResolutionError = error;
        formerResolutionStackTrace = stackTrace;
      }
    }
    final location =
        personalDataLocation ??
        (pathPolicy == null
            ? PersonalDataLocationService.fromEnvironment(
                Platform.environment,
                additionalProtectedDirectories: <Directory>[
                  ?formerApplicationDirectory,
                ],
              )
            : PersonalDataLocationService.fixed(
                basePaths.applicationDirectory,
              ));
    final activeDirectory = await location.resolveApplicationDirectory();
    if (formerResolutionError != null) {
      final currentState = File(
        '${activeDirectory.path}${Platform.pathSeparator}${PlannerStateRepository.stateFileName}',
      );
      final resetMarker = File(
        '${activeDirectory.path}${Platform.pathSeparator}${AppIdentity.intentionalResetMarkerFileName}',
      );
      final existingPublicProfile =
          location.requiresExistingProfile ||
          await currentState.exists() ||
          await resetMarker.exists();
      if (!existingPublicProfile) {
        Error.throwWithStackTrace(
          formerResolutionError,
          formerResolutionStackTrace ?? StackTrace.current,
        );
      }
      if (location is PersonalDataLocationService) {
        location.addStartupNotice(
          'The former test profile could not be inspected safely, so it was not imported or modified. Your existing Black Spirit Life profile was opened instead.',
        );
      }
    }
    final paths = PlannerStatePathPolicy(
      applicationDirectory: activeDirectory,
      legacyStateFile: basePaths.legacyStateFile,
      formerNativeApplicationDirectory: formerApplicationDirectory,
      allowLegacyMigration: basePaths.allowLegacyMigration,
    );
    final repository = PlannerStateRepository(
      paths: paths,
      applicationVersion: applicationVersion,
    );
    final stateLoad = await repository.load(
      catalog,
      requireExistingProfile: location.requiresExistingProfile,
    );
    final startupState = _withEditorToolsDisabled(stateLoad.state);
    final controller = PlannerApplicationController(
      catalog: catalog,
      initialState: startupState,
      saveState: repository.save,
    );
    final preview = stateLoad.migrationPreview;
    if (preview != null) {
      return ApplicationBundle(
        catalog: catalog,
        stateLoad: stateLoad,
        stateRepository: repository,
        personalDataLocation: location,
        controller: controller,
        startupNotices: _personalDataStartupNotices(location),
        firstLaunchMigration: ApplicationFirstLaunchMigration(
          preview: preview,
          accept: () => _acceptMigration(
            catalog: catalog,
            repository: repository,
            personalDataLocation: location,
            preview: preview,
            pendingController: controller,
          ),
          startFresh: () => _startFresh(
            catalog: catalog,
            repository: repository,
            personalDataLocation: location,
            preview: preview,
            pendingController: controller,
          ),
        ),
      );
    }
    return ApplicationBundle(
      catalog: catalog,
      stateLoad: stateLoad,
      stateRepository: repository,
      personalDataLocation: location,
      controller: controller,
      startupNotices: _personalDataStartupNotices(location),
    );
  }

  Future<ApplicationBundle> _acceptMigration({
    required CatalogSnapshot catalog,
    required PlannerStateRepository repository,
    required PersonalDataLocationManager personalDataLocation,
    required PlannerStateMigrationPreview preview,
    required PlannerApplicationController pendingController,
  }) async {
    if (!preview.canImport) {
      throw StateError(
        'The inspected Avalonia state contains migration errors and cannot be imported.',
      );
    }
    final store = CustomIconStore(
      applicationDirectory: repository.paths.applicationDirectory,
    );
    final materialized = await _materializeMigratedIcons(
      preview: preview,
      store: store,
    );
    final PlannerStateLoadResult stateLoad;
    try {
      stateLoad = await repository.commitMigration(
        preview,
        materializedState: materialized.state,
        notices: materialized.notices,
      );
    } on Object catch (error, stackTrace) {
      final cleanupFailures = await _rollbackCreatedIcons(
        store,
        materialized.createdIcons,
      );
      if (cleanupFailures.isNotEmpty) {
        throw StateError(
          'Migration commit failed: $error App-owned icon rollback also failed: ${cleanupFailures.join('; ')}',
        );
      }
      Error.throwWithStackTrace(error, stackTrace);
    }
    await pendingController.dispose();
    return _resolvedBundle(
      catalog: catalog,
      repository: repository,
      personalDataLocation: personalDataLocation,
      stateLoad: stateLoad,
    );
  }

  Future<ApplicationBundle> _startFresh({
    required CatalogSnapshot catalog,
    required PlannerStateRepository repository,
    required PersonalDataLocationManager personalDataLocation,
    required PlannerStateMigrationPreview preview,
    required PlannerApplicationController pendingController,
  }) async {
    final stateLoad = await repository.commitFresh(preview);
    await pendingController.dispose();
    return _resolvedBundle(
      catalog: catalog,
      repository: repository,
      personalDataLocation: personalDataLocation,
      stateLoad: stateLoad,
    );
  }

  ApplicationBundle _resolvedBundle({
    required CatalogSnapshot catalog,
    required PlannerStateRepository repository,
    required PersonalDataLocationManager personalDataLocation,
    required PlannerStateLoadResult stateLoad,
  }) => ApplicationBundle(
    catalog: catalog,
    stateLoad: stateLoad,
    stateRepository: repository,
    personalDataLocation: personalDataLocation,
    startupNotices: _personalDataStartupNotices(personalDataLocation),
    controller: PlannerApplicationController(
      catalog: catalog,
      initialState: _withEditorToolsDisabled(stateLoad.state),
      saveState: repository.save,
    ),
  );

  PlannerState _withEditorToolsDisabled(PlannerState state) =>
      state.showDeleteTools ? state.copyWith(showDeleteTools: false) : state;

  Future<_MaterializedMigration> _materializeMigratedIcons({
    required PlannerStateMigrationPreview preview,
    required CustomIconStore store,
  }) async {
    var state = preview.migratedState!;
    final notices = <String>[];
    final existingFiles = <String>{};
    if (await store.iconDirectory.exists()) {
      await for (final entity in store.iconDirectory.list(followLinks: false)) {
        if (entity is File) existingFiles.add(entity.path.toLowerCase());
      }
    }
    final createdIcons = <CustomIconReference>[];
    var importedCount = 0;
    try {
      for (final pending in preview.pendingCustomIcons) {
        final reference = await store.importDataUri(
          pending.dataUri,
          sourceName: pending.itemName,
          fit: CustomIconFit.contain,
        );
        final filePath = File(
          '${store.applicationDirectory.path}${Platform.pathSeparator}${reference.relativePath.replaceAll('/', Platform.pathSeparator)}',
        ).path.toLowerCase();
        if (!existingFiles.contains(filePath) &&
            !createdIcons.any(
              (candidate) => candidate.relativePath == reference.relativePath,
            )) {
          createdIcons.add(reference);
        }
        final modeState = state.forMode(pending.mode);
        state = _replaceMode(
          state,
          pending.mode,
          modeState.copyWith(
            customIcons: <String, CustomIconReference>{
              ...modeState.customIcons,
              pending.itemName: reference,
            },
          ),
        );
        importedCount++;
      }
    } on Object catch (error, stackTrace) {
      final cleanupFailures = await _rollbackCreatedIcons(store, createdIcons);
      if (cleanupFailures.isNotEmpty) {
        throw StateError(
          'Custom icon materialization failed: $error App-owned icon '
          'rollback also failed: ${cleanupFailures.join('; ')}',
        );
      }
      Error.throwWithStackTrace(error, stackTrace);
    }
    if (importedCount > 0) {
      notices.add('Imported $importedCount custom icon file(s).');
    }
    return _MaterializedMigration(
      state: state,
      notices: notices,
      createdIcons: createdIcons,
    );
  }
}

List<String> _personalDataStartupNotices(
  PersonalDataLocationManager location,
) => location is PersonalDataLocationService
    ? location.startupNotices
    : const <String>[];

Future<List<Object>> _rollbackCreatedIcons(
  CustomIconStore store,
  Iterable<CustomIconReference> references,
) async {
  final failures = <Object>[];
  for (final reference in references) {
    try {
      await store.remove(reference);
    } on Object catch (error) {
      failures.add(error);
    }
  }
  return failures;
}

final class _MaterializedMigration {
  const _MaterializedMigration({
    required this.state,
    required this.notices,
    required this.createdIcons,
  });

  final PlannerState state;
  final List<String> notices;
  final List<CustomIconReference> createdIcons;
}

PlannerState _replaceMode(
  PlannerState source,
  CraftMode mode,
  ModeState state,
) => switch (mode) {
  CraftMode.alchemy => source.copyWith(alchemy: state),
  CraftMode.cooking => source.copyWith(cooking: state),
  CraftMode.processing => source.copyWith(processing: state),
};
