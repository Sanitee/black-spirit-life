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
    expect(builder, contains("\$Version = '0.1.6'"));
    expect(builder, contains("\$BuildNumber = '25'"));
    expect(builder, contains("\$PreviousStableVersion = '0.1.5'"));
    expect(builder, contains('8f600b3b6bbece1add1077a40a5fb1c5d56797f8'));
    expect(builder, contains("\$UpdateChannel = 'win-x64-stable'"));
    expect(builder, contains("docs\\releases\\0.1.6.md"));
    expect(builder, contains('tag --points-at HEAD'));
    expect(builder, contains('rev-list --count HEAD'));
    expect(builder, contains('Assert-PublicSourceBoundary'));
    for (final forbidden in <String>[
      r'packages\bdo_fishing_core',
      r'packages\bdo_gathering_companion',
      r'windows\session_import',
      'fish-journal',
      'garmoth_spot_catalog',
      r'\.sqlite3?',
      r'planner-state\.json',
      r'personal-data-',
    ]) {
      expect(builder, contains(forbidden));
    }
    expect(builder, contains('previousSourceTag'));
    expect(builder, contains("rev-parse 'HEAD^'"));
    expect(builder, contains('sourceParentCommit'));
    expect(builder, contains('PreviousStableCommit'));
    expect(builder, contains("\$sourceCommitCount -cne '5'"));
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
    expect(builder, contains('\$PreviousFeedBytes = 10230L'));
    expect(
      builder,
      contains(
        '7F9F995660AA450C80EA610DB041C82BD7C51EA35593C1B1B06FFE77FFA91FF0',
      ),
    );
    expect(builder, contains('\$PreviousFullPackageBytes = 217687337L'));
    expect(
      builder,
      contains(
        '9C3E9BEB7121B06BA7CE4D482546842866020DDA1C231601C4149B9E31302E28',
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
  });

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
