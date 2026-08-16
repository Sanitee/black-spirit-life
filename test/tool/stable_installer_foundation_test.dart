import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final cmake = File('windows/installer/CMakeLists.txt').readAsStringSync();
  final mainSource = File('windows/installer/main.cpp').readAsStringSync();
  final model = File('windows/installer/installer_model.h').readAsStringSync();
  final resources = File(
    'windows/installer/installer_resources.rc',
  ).readAsStringSync();
  final manifest = File(
    'windows/installer/installer.manifest',
  ).readAsStringSync();
  final renderer = File(
    'windows/installer/installer_renderer.cpp',
  ).readAsStringSync();
  final rendererHeader = File(
    'windows/installer/installer_renderer.h',
  ).readAsStringSync();
  final engine = File(
    'windows/installer/install_engine.cpp',
  ).readAsStringSync();
  final payload = File(
    'windows/installer/embedded_payload.cpp',
  ).readAsStringSync();
  final locator = File(
    'windows/installer/installed_beta_locator.cpp',
  ).readAsStringSync();
  final pathPolicy = File(
    'windows/installer/install_path_policy.cpp',
  ).readAsStringSync();
  final maintenanceGate = File(
    'windows/shared/beta_maintenance_gate.cpp',
  ).readAsStringSync();
  final processGuard = File(
    'windows/installer/install_process_guard.cpp',
  ).readAsStringSync();
  final personalDataRemoval = File(
    'windows/installer/personal_data_removal.cpp',
  ).readAsStringSync();

  test('themed installer version surfaces stay synchronized', () {
    expect(cmake, contains('BSL_INSTALLER_VERSION "0.1.3"'));
    expect(cmake, contains('BSL_INSTALLER_BUILD_NUMBER "22"'));
    expect(cmake, contains('BSL_INSTALLER_VERSION_MAJOR'));
    expect(model, contains('version = L"0.1.3"'));
    expect(
      resources,
      contains(
        'FILEVERSION @BSL_INSTALLER_VERSION_MAJOR@,'
        '@BSL_INSTALLER_VERSION_MINOR@,'
        '@BSL_INSTALLER_VERSION_PATCH@,@BSL_INSTALLER_BUILD_NUMBER@',
      ),
    );
    expect(
      resources,
      contains(
        'VALUE "FileVersion", '
        '"@BSL_INSTALLER_VERSION@.@BSL_INSTALLER_BUILD_NUMBER@\\0"',
      ),
    );
    expect(
      manifest,
      contains(
        'version="@BSL_INSTALLER_VERSION_MAJOR@.'
        '@BSL_INSTALLER_VERSION_MINOR@.'
        '@BSL_INSTALLER_VERSION_PATCH@.@BSL_INSTALLER_BUILD_NUMBER@"',
      ),
    );
  });

  test('themed installer embeds and verifies the unchanged Velopack Setup', () {
    expect(cmake, contains('BSL_INSTALLER_ENGINE_SHA256'));
    expect(cmake, contains('IDR_VELOPACK_SETUP RCDATA'));
    expect(cmake, contains('BlackSpiritLife.App'));
    expect(cmake, contains('win-x64-stable'));
    expect(payload, contains('FindResourceW'));
    expect(payload, contains('BCRYPT_SHA256_ALGORITHM'));
    expect(payload, contains('VerifyEmbeddedPayload'));
    expect(payload, contains('Sha256FileHandle'));
    expect(payload, contains('executable_handle'));
    expect(payload, contains('directory_handle'));
    expect(payload, contains('ReleaseLocks'));
    expect(payload, contains('The embedded installation engine failed'));
    expect(mainSource, contains('--verify-payload'));
  });

  test(
    'themed shell delegates installation without changing update identity',
    () {
      expect(engine, contains(' --silent --log '));
      expect(engine, contains(' --installto '));
      expect(engine, contains('CREATE_NO_WINDOW'));
      expect(engine, contains('BetaMaintenanceGate'));
      expect(engine, contains('EnsureNoRunningBetaProcess'));
      expect(engine, contains('ValidateInstallRootPersonalDataSafety'));
      expect(processGuard, contains('CreateToolhelp32Snapshot'));
      expect(processGuard, contains('QueryFullProcessImageNameW'));
      expect(processGuard, contains('ERROR_NO_MORE_FILES'));
      expect(processGuard, contains('IsUniqueBetaProcessName'));
      expect(processGuard, contains('IsVelopackUpdateProcessName'));
      expect(processGuard, contains('L"Update.exe"'));
      expect(processGuard, contains('PathIsWithin'));
      expect(engine, contains('AcquireFresh'));
      expect(
        engine,
        isNot(contains('root_lease.Acquire(install_root, fresh_install')),
      );
      expect(maintenanceGate, contains('MaintenanceGate.v1'));
      expect(engine, contains('VerifyInstalledBetaRoot'));
      expect(engine, contains('ExistingInstallLaunchLease'));
      expect(engine, contains('CurrentModulePath'));
      expect(engine, contains('SameOrChildPhysicalPath'));
      expect(engine, contains('SetCurrentDirectoryW'));
      expect(locator, contains('build_config::kPackageId'));
      expect(locator, contains('build_config::kChannel'));
      expect(locator, contains('BlackSpiritLife.exe'));
      expect(mainSource, contains('CompareSemanticVersions'));
      expect(mainSource, contains('will not downgrade it'));
      expect(mainSource, isNot(contains('http://')));
      expect(mainSource, isNot(contains('https://')));
    },
  );

  test('fresh paths fail closed around settings, cache, and owned folders', () {
    expect(pathPolicy, contains('DRIVE_FIXED'));
    expect(pathPolicy, contains('FILE_ATTRIBUTE_REPARSE_POINT'));
    expect(pathPolicy, contains('InspectDirectoryContents'));
    expect(pathPolicy, contains('DirectoryContents::unreadable'));
    expect(pathPolicy, contains('ERROR_NO_MORE_FILES'));
    expect(pathPolicy, contains('Black Spirit Life Beta'));
    expect(pathPolicy, contains('BDO Craft Planner Map Candidate'));
    expect(pathPolicy, contains('ProgramFiles'));
    expect(pathPolicy, contains('Choose a new or empty '));
    expect(pathPolicy, contains('L"folder."'));
    expect(mainSource, contains('ValidateFreshInstallPath'));
  });

  test(
    'fresh paths fail closed around the committed custom personal-data profile',
    () {
      expect(pathPolicy, contains('personal-data-location.json'));
      expect(pathPolicy, contains('personal-data-location.committed.json'));
      expect(pathPolicy, contains('personal-data-move-journal.json'));
      expect(pathPolicy, contains('BlackSpiritLife.App.Removal'));
      expect(pathPolicy, contains('ReadCommittedPersonalDataLocation'));
      expect(pathPolicy, contains('ReadPendingPersonalDataMove'));
      expect(pathPolicy, contains('CanonicalPhysicalPath'));
      expect(pathPolicy, contains('GetFinalPathNameByHandleW'));
      expect(pathPolicy, contains('VOLUME_NAME_NT'));
      expect(pathPolicy, contains('schemaVersion'));
      expect(pathPolicy, contains('build_config::kPackageId'));
      expect(pathPolicy, contains('build_config::kChannel'));
      expect(pathPolicy, contains('primary.state != LocatorCopyState::valid'));
      expect(pathPolicy, contains('mirror.state != LocatorCopyState::valid'));
      expect(pathPolicy, contains('primary.directory.c_str()'));
      expect(
        pathPolicy,
        contains('saved personal-data location or pending move could not be'),
      );
      expect(pathPolicy, contains('protected_roots.push_back'));
      expect(pathPolicy, contains('committed_location.directory'));
      expect(pathPolicy, contains('pending_move.protected_directories'));
      expect(
        engine,
        contains('selected folder may contain incomplete application files'),
      );
    },
  );

  test('custom shell is compact and exposes only useful maintenance actions', () {
    for (final phase in <String>[
      'ready',
      'installing',
      'succeeded',
      'failed',
      'blocked',
    ]) {
      expect(model, contains(phase));
    }
    expect(model, contains('Open Black Spirit Life'));
    expect(model, contains('InstallerIntent'));
    expect(model, contains('L"Uninstall"'));
    expect(model, contains('L"Back"'));
    expect(model, contains('remove_personal_data = false'));
    expect(model, contains('intent == InstallerIntent::uninstall &&'));
    expect(model, contains('phase == InstallerPhase::ready'));
    expect(renderer, contains('Also delete my planner data'));
    expect(
      renderer,
      contains(
        'layout.remove_personal_data = {318.0F, 260.0F, width_dip - 44.0F, 292.0F}',
      ),
    );
    expect(renderer, isNot(contains('Mastery, recipes, favorites, checklist')));
    expect(model, contains('sent to the Recycle Bin'));
    expect(model, isNot(contains('Personal data is preserved')));
    expect(model, isNot(contains('card_title')));
    expect(model, isNot(contains('card_detail')));
    expect(renderer, isNot(contains('preservation_y')));
    expect(renderer, contains('height_dip < 370.0F'));
    expect(renderer, contains('browse_rect.X + 23.0F'));
    expect(renderer, contains('browse_rect.Y + 10.5F'));
    expect(renderer, contains('browse_rect.X + 52.0F'));
    expect(renderer, isNot(contains('Current folder')));
    expect(rendererHeader, contains('kPreviewHeight = 400.0F'));
    expect(mainSource, contains('kCompactPreviewHeight = 370.0F'));
    expect(mainSource, contains('--preview-intent'));
    expect(mainSource, contains('--preview-remove-personal-data'));
    expect(mainSource, contains('InteractiveElement::secondary'));
    expect(mainSource, contains('InteractiveElement::remove_personal_data'));
    expect(model, isNot(contains('Cancel')));
    expect(renderer, isNot(contains('Cancel')));
    expect(mainSource, contains('kInstallFinishedMessage'));
    expect(mainSource, contains('kInstallProgressMessage'));
    expect(mainSource, contains('RenderBufferedInstaller'));
    expect(mainSource, contains('CreateCompatibleDC'));
    expect(mainSource, contains('CreateCompatibleBitmap'));
    expect(mainSource, contains('BitBlt'));
    expect(mainSource, contains('SRCCOPY'));
    final paintHandler = RegExp(
      r'case WM_PAINT:[\s\S]*?case WM_MOUSEMOVE:',
    ).firstMatch(mainSource)?.group(0);
    expect(paintHandler, isNotNull);
    expect(paintHandler, contains('RenderBufferedInstaller'));
    expect(paintHandler, isNot(contains('state->renderer.Render')));
    expect(mainSource, contains('FitWindowToWorkArea'));
    expect(mainSource, contains('MonitorWorkAreaForRect'));
    expect(renderer, contains('browse_focused'));
    expect(renderer, contains('primary_focused'));
    expect(renderer, contains('close_focused'));
    expect(
      mainSource,
      contains('state->model.phase == InstallerPhase::installing'),
    );
  });

  test('verified install success opens the packaged current application', () {
    final launchHelper = RegExp(
      r'bool OpenInstalledApplication[\s\S]*?void Activate',
    ).firstMatch(mainSource)?.group(0);
    expect(launchHelper, isNotNull);
    expect(launchHelper, contains('VerifyInstalledBetaRoot'));
    expect(launchHelper, contains('CompareSemanticVersions'));
    expect(launchHelper, contains('L"current"'));
    expect(launchHelper, contains('L"BlackSpiritLife.exe"'));
    expect(launchHelper, contains('CreateProcessW'));
    expect(launchHelper, contains('DestroyWindow(window)'));
    expect(launchHelper, isNot(contains('ShellExecuteW')));

    final finishedHandler = RegExp(
      r'case kInstallFinishedMessage:[\s\S]*?case WM_CLOSE:',
    ).firstMatch(mainSource)?.group(0);
    expect(finishedHandler, isNotNull);
    expect(finishedHandler, contains('matching_success'));
    expect(
      finishedHandler,
      contains('!uninstalling && OpenInstalledApplication(*state, window)'),
    );
    expect(finishedHandler, contains('return 0'));
  });

  test('uninstall uses the verified pinned updater and preserves profiles', () {
    expect(cmake, contains('version'));
    expect(engine, contains('RunUninstallEngine'));
    expect(engine, contains('VerifyVelopackUpdaterVersion'));
    expect(engine, contains('L"Velopack 1.2.0"'));
    expect(engine, contains('QuoteArgument(updater_path)'));
    expect(engine, contains('L" --uninstall --silent"'));
    expect(engine, contains('VerifyRegisteredRoot'));
    expect(engine, contains('UninstallPostconditionSatisfied'));
    expect(engine, contains('IsPathAbsent'));
    expect(engine, contains('BlackSpiritLifeUpdater.exe'));
    expect(engine, isNot(contains('complete_files_remain')));
    expect(engine, contains('ValidateInstallRootPersonalDataSafety'));
    expect(engine, contains('EnsureNoRunningBetaProcess'));
    expect(engine, isNot(contains('RegDelete')));
    expect(engine, isNot(contains('RemoveDirectoryW(expected.root')));
    expect(locator, contains('QueryRegisteredInstallLocation'));
    expect(mainSource, contains('OpenUninstallConfirmation'));
    expect(mainSource, contains('RestoreMaintenanceScreen'));
    expect(mainSource, contains('StartUninstallation'));
  });

  test('personal-data removal is explicit, recoverable, and retryable', () {
    expect(cmake, contains('personal_data_removal.cpp'));
    expect(engine, contains('PreparePersonalDataRemoval'));
    expect(engine, contains('MarkPersonalDataApplicationRemoved'));
    expect(engine, contains('FinalizePersonalDataRemoval'));
    expect(engine, contains('RunPendingPersonalDataCleanup'));
    expect(mainSource, contains('DetectPendingPersonalDataRemoval'));
    expect(mainSource, contains('CancelPreparedPersonalDataRemoval'));
    expect(personalDataRemoval, contains('FOFX_RECYCLEONDELETE'));
    expect(personalDataRemoval, contains('GetAnyOperationsAborted'));
    expect(
      personalDataRemoval,
      contains('.black-spirit-life-intentional-reset.json'),
    );
    expect(personalDataRemoval, contains('personal-data-location.json'));
    expect(
      personalDataRemoval,
      contains('personal-data-location.committed.json'),
    );
    expect(personalDataRemoval, contains('personal-data-move-journal.json'));
    expect(personalDataRemoval, contains('BDO Craft Planner Map Candidate'));
    expect(personalDataRemoval, contains('BDO Craft Planner Avalonia'));
    expect(personalDataRemoval, contains('retained_quarantine'));
    expect(personalDataRemoval, isNot(contains('SHFileOperationW')));
    expect(personalDataRemoval, isNot(contains('std::filesystem::remove_all')));
  });
}
