import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Velopack lifecycle runs before console, COM, and Flutter startup', () {
    final source = File('windows/runner/main.cpp').readAsStringSync();

    final autoApply = source.indexOf(
      'vpkc_app_set_auto_apply_on_startup(false)',
    );
    final lifecycle = source.indexOf('vpkc_app_run(nullptr)');
    final console = source.indexOf('AttachConsole');
    final com = source.indexOf('CoInitializeEx');
    final flutter = source.indexOf('flutter::DartProject project');

    expect(autoApply, greaterThanOrEqualTo(0));
    expect(lifecycle, greaterThan(autoApply));
    expect(console, greaterThan(lifecycle));
    expect(com, greaterThan(lifecycle));
    expect(flutter, greaterThan(lifecycle));
    expect(source, contains('BetaMaintenanceGate startup_gate'));
    expect(source, contains('startup_gate.Release()'));
  });

  test('Windows bundle pins and installs the exact Velopack 1.2.0 runtime', () {
    final rootCmake = File('windows/CMakeLists.txt').readAsStringSync();
    final runnerCmake = File(
      'windows/runner/CMakeLists.txt',
    ).readAsStringSync();
    final provenance = File(
      'windows/third_party/velopack/1.2.0/README.md',
    ).readAsStringSync();
    final importLibrary = File(
      'windows/third_party/velopack/1.2.0/lib/x64/'
      'velopack_libc_win_x64_msvc.dll.lib',
    ).readAsBytesSync();
    final importLibraryText = String.fromCharCodes(importLibrary);

    expect(rootCmake, contains('third_party/velopack/1.2.0'));
    expect(rootCmake, contains('verify_pinned_file'));
    expect(
      rootCmake,
      contains(
        'c36d8b984639a8af9d3397088d3ffb8213fe1bd0917f555cf0c6e33f014403ec',
      ),
    );
    expect(rootCmake, contains('install(FILES "\${VELOPACK_DLL}"'));
    expect(
      rootCmake,
      contains('set(VELOPACK_RUNTIME_BUNDLE_NAME "velopack_libc.dll")'),
    );
    expect(rootCmake, contains('RENAME "\${VELOPACK_RUNTIME_BUNDLE_NAME}"'));
    expect(importLibraryText, contains('velopack_libc.dll'));
    expect(runnerCmake, isNot(contains('"velopack_update_bridge.cpp"')));
    expect(runnerCmake, contains('BlackSpiritLifeUpdater'));
    expect(rootCmake, contains('install(TARGETS BlackSpiritLifeUpdater'));
    expect(runnerCmake, contains('"\${VELOPACK_IMPORT_LIBRARY}"'));
    expect(provenance, contains('Velopack C/C++ runtime 1.2.0'));
  });

  test(
    'Velopack manager operations exist only in the isolated helper target',
    () {
      final source = File(
        'windows/runner/beta_updater_main.cpp',
      ).readAsStringSync();
      final windowSource = File(
        'windows/runner/flutter_window.cpp',
      ).readAsStringSync();
      final runnerCmake = File(
        'windows/runner/CMakeLists.txt',
      ).readAsStringSync();

      expect(source, contains('vpkc_new_update_manager'));
      expect(source, contains('vpkc_check_for_updates'));
      expect(source, contains('vpkc_download_updates'));
      expect(source, contains('vpkc_unsafe_apply_updates'));
      expect(source, isNot(contains('vpkc_wait_exit_then_apply_updates')));
      expect(source, contains('BlackSpiritLife.App'));
      expect(source, contains('win-x64-stable'));
      expect(source, contains('options.AllowVersionDowngrade = false'));
      expect(source, contains('options.MaximumDeltasBeforeFallback = 10'));
      expect(source, contains('BetaMaintenanceGate maintenance_gate'));
      expect(windowSource, isNot(contains('VelopackUpdateBridge')));
      expect(windowSource, isNot(contains('vpkc_new_update_manager')));
      expect(runnerCmake, contains('add_executable(BlackSpiritLifeUpdater'));
      expect(
        runnerCmake,
        contains('target_link_libraries(BlackSpiritLifeUpdater PRIVATE'),
      );
    },
  );

  test('isolated helper guards Velopack 1.2.0 string output buffers', () {
    final source = File(
      'windows/runner/beta_updater_main.cpp',
    ).readAsStringSync();

    expect(source, contains("std::vector<char> buffer(required + 1, '\\0');"));
    expect(
      source,
      contains('vpkc_get_app_id(manager, buffer.data(), required)'),
    );
    expect(
      source,
      contains('vpkc_get_current_version(manager, buffer.data(), required)'),
    );
    expect(
      source,
      contains("std::vector<char> buffer(logical_capacity + 1, '\\0');"),
    );
    expect(
      source,
      contains('vpkc_get_last_error(buffer.data(), logical_capacity)'),
    );
    expect(source, isNot(contains('std::vector<char> buffer(required,')));
  });

  test('GitHub releases use the provider-specific public source', () {
    final helper = File(
      'windows/runner/beta_updater_main.cpp',
    ).readAsStringSync().replaceAll('\r\n', '\n');

    expect(helper, contains('IsGithubRepositorySource(request.source)'));
    expect(
      helper,
      contains(
        'vpkc_new_source_github(request.source.c_str(), nullptr, false)',
      ),
    );
    expect(helper, contains('vpkc_new_update_manager_with_source('));
    expect(
      helper,
      contains(
        'vpkc_new_update_manager(\n'
        '        request.source.c_str(), &options, nullptr, &manager)',
      ),
    );
  });

  test('release foundation contains no uploader or derived GitHub URL', () {
    final files = <File>[
      File('windows/runner/beta_updater_main.cpp'),
      File('lib/app/update/beta_update.dart'),
      File('lib/app/update/beta_update_process_service.dart'),
      File('windows/third_party/velopack/1.2.0/README.md'),
    ];
    final source = files.map((file) => file.readAsStringSync()).join('\n');

    expect(source, isNot(contains('vpk upload')));
    expect(source, isNot(contains('api.github.com')));
    expect(source, isNot(contains('github.com/repos/')));
    expect(source, isNot(contains('releases/latest/download')));
  });
}
