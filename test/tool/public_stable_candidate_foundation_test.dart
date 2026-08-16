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
    expect(builder, contains("\$Version = '0.1.3'"));
    expect(builder, contains("\$BuildNumber = '22'"));
    expect(builder, contains("\$UpdateChannel = 'win-x64-stable'"));
    expect(builder, contains("docs\\releases\\0.1.3.md"));
    expect(builder, contains('tag --points-at HEAD'));
    expect(builder, contains('rev-list --count HEAD'));
    expect(builder, contains('sourceTag = \$sourceTag'));
    expect(builder, contains('publicCandidate = \$true'));
    expect(builder, contains('localOnly = \$false'));
    expect(builder, contains('\$installerInfo.FileVersion'));
    expect(builder, contains('previousStableVersion = \$null'));
    expect(builder, contains('expectedForFirstVersion = \$false'));
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
      expect(manifest['datasetVersion'], '2026.08.16-stable-v1');
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
