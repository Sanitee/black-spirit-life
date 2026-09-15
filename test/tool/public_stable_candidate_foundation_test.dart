import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final wrapper = File(
    'tool/build_public_stable_candidate.ps1',
  ).readAsStringSync().replaceAll('\r\n', '\n');
  final builder = File(
    'tool/build_stable_release_candidate.ps1',
  ).readAsStringSync().replaceAll('\r\n', '\n');
  final productionVerifier = File(
    'tool/verify_production_source.ps1',
  ).readAsStringSync().replaceAll('\r\n', '\n');
  final mapWidget = File(
    'packages/bdo_map_core/lib/src/widgets/bdo_resource_map.dart',
  ).readAsStringSync().replaceAll('\r\n', '\n');
  final tileSource = File(
    'packages/bdo_map_core/lib/src/model/tile_source.dart',
  ).readAsStringSync().replaceAll('\r\n', '\n');
  final mapDataText = File(
    'packages/bdo_map_core/assets/data/resource_map.json',
  ).readAsStringSync();
  final lodgingText = File(
    'packages/bdo_map_core/assets/data/lodging_houses.json',
  ).readAsStringSync();
  final economicsText = File(
    'packages/bdo_map_core/assets/data/worker_economics.json',
  ).readAsStringSync();

  test('public candidate requires the permanent GitHub stable identity', () {
    expect(wrapper, contains('[string]\$PublicGitHubRepository'));
    expect(
      wrapper,
      contains('PublicGitHubRepository = \$PublicGitHubRepository'),
    );
    expect(builder, contains('https://github.com/OWNER/REPOSITORY'));
    expect(builder, isNot(contains('Sanitee')));
    expect(wrapper, isNot(contains('Sanitee')));
    expect(builder, contains("\$Version = '0.1.7'"));
    expect(builder, contains("\$BuildNumber = '26'"));
    expect(builder, contains("\$PreviousStableVersion = '0.1.6'"));
    expect(builder, contains('bebc1a03815303df25fdfc939edfd840d9cbbe0c'));
    expect(builder, contains("\$UpdateChannel = 'win-x64-stable'"));
    expect(builder, contains("docs\\releases\\0.1.7.md"));
    expect(builder, contains('tag --points-at HEAD'));
    expect(builder, contains('rev-list --count HEAD'));
    expect(builder, contains('Assert-PublicSourceBoundary'));
    for (final forbidden in <String>[
      r'packages\bdo_fishing_core',
      r'packages\bdo_gathering_companion',
      r'windows\session_import',
      r'lib\features\gathering',
      r'lib\features\fishing',
      'fishy',
      'garmoth',
      'bairog',
      'python',
      'webview',
      'sessions?',
      'journals?',
      'loadouts?',
      r'user[ _-]?settings',
      r'\.(?:db|sqlite3?)',
      r'planner-state\.json',
      r'personal-data-',
    ]) {
      expect(builder, contains(forbidden));
    }
    expect(builder, contains('previousSourceTag'));
    expect(builder, contains("rev-parse 'HEAD^'"));
    expect(builder, contains('sourceParentCommit'));
    expect(builder, contains('PreviousStableCommit'));
    expect(builder, contains("\$sourceCommitCount -cne '6'"));
    expect(builder, contains('sourceTag = \$sourceTag'));
    expect(builder, contains('publicCandidate = \$true'));
    expect(builder, contains('localOnly = \$false'));
    expect(builder, contains('\$installerInfo.FileVersion'));
    expect(
      builder,
      contains('previousStableVersion = \$PreviousStableVersion'),
    );
    expect(builder, contains('publishedPreviousFeed'));
    expect(builder, contains('publishedPreviousAssets'));
    expect(builder, contains('\$PreviousFeedBytes = 14322L'));
    expect(
      builder,
      contains(
        'A8DD060274DF561F8523D7F34FA2870402CBF5810428D814726957CD47ACC8BF',
      ),
    );
    expect(builder, contains('\$PreviousFullPackageBytes = 218730095L'));
    expect(
      builder,
      contains(
        '956B3E3184894EDBA8EBDE9D8727575542C5402F591C8FF1E3A8178EA50C0042',
      ),
    );
    expect(builder, contains('deltaPackageName'));
    expect(builder, contains("\$feedAssets.Count -ne 3"));
    expect(builder, contains("\$_.Type -ceq 'Delta'"));
    expect(builder, contains('delta-package'));
    expect(builder, contains('\$deltaItem.Length -ge \$fullItem.Length'));
    expect(
      builder,
      contains('generated delta package must be smaller than the full package'),
    );
    expect(builder, contains('publicUploadArtifacts'));
    expect(builder, contains('expected = \$true'));
    expect(builder, contains('generated = \$true'));
    expect(builder, contains('verificationRequiredBeforePublication = \$true'));
    expect(
      builder,
      contains("\$InstallerName = 'BlackSpiritLifeInstaller.exe'"),
    );
    expect(builder, contains('fresh-clone privacy and release-artifact scan'));
    expect(builder, contains('verify_production_source.ps1'));
    expect(
      builder,
      contains(r'& $productionVerifier -ProjectRoot $ProjectRoot'),
    );
    expect(
      RegExp(
        r'\$_\.FullName -match \$ForbiddenPackagedArtifactPattern',
      ).allMatches(builder),
      hasLength(2),
      reason:
          'Both the application bundle and Velopack package must be scanned.',
    );
    expect(builder, contains('function Reset-VerifiedBuildBundle'));
    expect(
      builder,
      contains("Join-Path \$ProjectRoot 'build\\windows\\x64\\runner'"),
    );
    expect(builder, contains('Refusing to clean an unexpected Flutter build'));
    expect(builder, contains('FileAttributes]::ReparsePoint'));
    expect(builder, contains("'windows', 'x64', 'runner', 'Release'"));
    expect(
      builder,
      contains('Remove-Item -LiteralPath \$resolvedBundle -Recurse -Force'),
    );
    expect(
      builder.indexOf('Reset-VerifiedBuildBundle `'),
      lessThan(builder.indexOf('& \$FlutterPath build windows --release')),
      reason: 'The exact release bundle must be cleared before Flutter builds.',
    );
  });

  test('production verifier keeps restored features native and data-free', () {
    expect(productionVerifier, contains('[string]\$ProjectRoot'));
    for (final required in <String>[
      r'lib\features\gathering',
      r'lib\features\fishing',
      r'packages\bdo_fishing_core',
      r'packages\bdo_gathering_companion',
      'browser-runtime artifact is forbidden',
      'Python runtime/source artifact is forbidden',
      'FishyStuff/Garmoth/Bairog',
      'bundled personal-data artifact is forbidden',
      'native feature directories may contain Dart source only',
      'sessions?',
      'journals?',
      'loadouts?',
      r'user[ _-]?settings',
      r'\.(?:db|sqlite3?)',
    ]) {
      expect(productionVerifier, contains(required));
    }
  });

  test(
    'production verifier rejects representative private artifacts',
    () async {
      if (!Platform.isWindows) return;
      final verifier = File('tool/verify_production_source.ps1').absolute.path;

      final clean = await _productionBoundaryFixture();
      addTearDown(() async {
        if (await clean.exists()) await clean.delete(recursive: true);
      });
      expect(
        (await _runProductionVerifier(verifier, clean)).exitCode,
        0,
        reason: 'A native-only fixture must pass the production source gate.',
      );

      for (final artifact in <({String path, String contents})>[
        (
          path: 'lib/features/fishing/fish-journal.sqlite3',
          contents: 'private journal bytes',
        ),
        (
          path: 'lib/features/gathering/sessions.json',
          contents: '{"sessions":[]}',
        ),
        (
          path: 'lib/features/fishing/loadouts.json',
          contents: '{"loadouts":[]}',
        ),
        (
          path: 'lib/features/fishing/user-settings.json',
          contents: '{"opacity":85}',
        ),
        (
          path: 'lib/features/fishing/fishystuff.png',
          contents: 'copied artwork',
        ),
        (path: 'assets/garmoth/spot-cache.json', contents: '{"spots":[]}'),
        (path: 'assets/bairog/calculator-cache.json', contents: '{"rates":[]}'),
        (
          path: 'lib/features/gathering/backend.py',
          contents: 'print("runtime")',
        ),
        (path: 'assets/python312.dll', contents: 'runtime binary'),
        (path: 'assets/player.html', contents: '<html></html>'),
        (
          path: 'packages/bdo_fishing_core/lib/runtime.dart',
          contents: 'const bundledCompanion = true;',
        ),
        (
          path: 'lib/features/fishing/embedded_surface.dart',
          contents: 'const forbiddenRuntime = "WebView2";',
        ),
      ]) {
        final fixture = await _productionBoundaryFixture();
        addTearDown(() async {
          if (await fixture.exists()) await fixture.delete(recursive: true);
        });
        final file = File('${fixture.path}/${artifact.path}');
        await file.parent.create(recursive: true);
        await file.writeAsString(artifact.contents);
        final result = await _runProductionVerifier(verifier, fixture);
        expect(
          result.exitCode,
          isNot(0),
          reason:
              '${artifact.path} must be rejected.\n'
              '${result.stdout}\n${result.stderr}',
        );
      }
    },
  );

  test('public candidate prepares artifacts but never publishes', () {
    expect(wrapper, contains('ConfirmPublicCandidateOnly'));
    expect(
      builder,
      isNot(
        contains(
          '[Parameter(Mandatory = \$true)]\n'
          '    [switch]\$ConfirmLocalPreviewOnly',
        ),
      ),
    );
    expect(wrapper, contains('never publishes them'));
    expect(builder, isNot(contains('127.0.0.1')));
    expect(builder, isNot(contains('ConfirmLocalPreviewOnly')));
    expect(wrapper, isNot(contains('git push')));
    expect(wrapper, isNot(contains('gh release')));
    expect(wrapper, isNot(contains('vpk upload')));
    expect(builder, isNot(contains('api.github.com')));
    expect(builder, isNot(contains('releases/latest/download')));
  });

  test(
    'public map data and visible source notice match the owner decision',
    () {
      final mapData = jsonDecode(mapDataText) as Map<String, dynamic>;
      final manifest = mapData['manifest']! as Map<String, dynamic>;
      expect(manifest['datasetVersion'], '2026.09.09-beta-v4');
      for (final text in <String>[mapDataText, lodgingText, economicsText]) {
        expect(text, isNot(contains('Redistribution permission unconfirmed')));
        expect(text, isNot(contains('Do not publish or redistribute')));
        expect(text, isNot(contains('private noncommercial candidate')));
      }
      expect(lodgingText, contains('Project-owner approved'));
      expect(economicsText, contains('project-owner approved'));
      expect(mapWidget, contains('this.showSourceNotice = true'));
      expect(
        mapWidget,
        contains('Unofficial, free and noncommercial fan-project map.'),
      );
      expect(mapWidget, isNot(contains('Candidate-build policy')));
      expect(mapWidget, isNot(contains('gated on written permission')));
      expect(tileSource, contains('bounded, removable local cache'));
      expect(tileSource, isNot(contains('local development cache')));
    },
  );

  test('public candidate PowerShell remains syntactically valid', () {
    if (!Platform.isWindows) return;
    for (final file in <String>[
      'tool/build_stable_release_candidate.ps1',
      'tool/build_public_stable_candidate.ps1',
    ]) {
      final scriptPath = File(file).absolute.path.replaceAll("'", "''");
      final result = Process.runSync('powershell', <String>[
        '-NoProfile',
        '-NonInteractive',
        '-Command',
        r'$tokens=$null; $errors=$null; '
            "[System.Management.Automation.Language.Parser]::ParseFile('$scriptPath', "
            r'[ref]$tokens, [ref]$errors) | Out-Null; '
            r'if ($errors.Count -ne 0) { $errors | ForEach-Object { $_.Message }; exit 1 }',
      ]);
      expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
    }
  });
}

Future<Directory> _productionBoundaryFixture() async {
  final root = await Directory.systemTemp.createTemp('bsl-native-gate-');
  for (final path in <String>[
    'lib/features/gathering',
    'lib/features/fishing',
    'windows/runner',
    'packages/bdo_map_core/lib',
    'assets',
  ]) {
    await Directory('${root.path}/$path').create(recursive: true);
  }
  for (final entry in <({String path, String contents})>[
    (path: 'lib/app.dart', contents: 'const productionValue = 1;'),
    (
      path: 'lib/features/gathering/gathering_workspace.dart',
      contents: 'const gatheringValue = 1;',
    ),
    (
      path: 'lib/features/fishing/fishing_workspace.dart',
      contents: 'const fishingValue = 1;',
    ),
    (path: 'windows/runner/main.cpp', contents: 'int main() { return 0; }'),
    (
      path: 'packages/bdo_map_core/lib/map.dart',
      contents: 'const mapValue = 1;',
    ),
    (path: 'pubspec.yaml', contents: 'name: boundary_fixture\n'),
    (path: 'pubspec.lock', contents: 'packages: {}\n'),
    (
      path: 'packages/bdo_map_core/pubspec.yaml',
      contents: 'name: bdo_map_core\n',
    ),
  ]) {
    await File('${root.path}/${entry.path}').writeAsString(entry.contents);
  }
  return root;
}

Future<ProcessResult> _runProductionVerifier(String verifier, Directory root) =>
    Process.run('powershell', <String>[
      '-NoProfile',
      '-NonInteractive',
      '-ExecutionPolicy',
      'Bypass',
      '-File',
      verifier,
      '-ProjectRoot',
      root.path,
    ]);
