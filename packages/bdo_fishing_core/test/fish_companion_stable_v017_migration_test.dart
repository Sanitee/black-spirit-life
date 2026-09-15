import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'compiled backend migrates every v0.1.7 session field without invention',
    () async {
      if (!Platform.isWindows) return;

      final payloadRoot = Directory(
        _path(Directory.current.path, 'assets', 'fish_companion'),
      );
      final executable = File(
        _path(payloadRoot.path, 'runtime', 'fish_companion_service.exe'),
      );
      final scratch = await Directory.systemTemp.createTemp(
        'fish-companion-v017-migration-',
      );
      final personalRoot = Directory(_path(scratch.path, 'personal'));
      final fishingRoot = Directory(_path(personalRoot.path, 'fishing'));
      final referenceRoot = Directory(_path(scratch.path, 'reference-cache'));
      final source = File(_path(fishingRoot.path, 'fishing-journal.json'));
      final database = File(_path(fishingRoot.path, 'fish-journal.sqlite3'));
      const apiToken = 'fish-companion-v017-migration-test-0001';
      Process? service;
      try {
        await fishingRoot.create(recursive: true);
        await referenceRoot.create(recursive: true);
        final legacyJournal = _legacyJournal();
        final sourceBytes = utf8.encode(jsonEncode(legacyJournal));
        await source.writeAsBytes(sourceBytes, flush: true);
        final sourceSha256 = sha256.convert(sourceBytes).toString();

        final firstMigration = await Process.run(executable.path, <String>[
          '--migrate-v017-json',
          source.path,
          '--database',
          database.path,
        ], workingDirectory: payloadRoot.path);
        expect(firstMigration.exitCode, 0, reason: '${firstMigration.stderr}');
        final firstResult =
            jsonDecode(firstMigration.stdout as String) as Map<String, dynamic>;
        expect(firstResult['status'], 'migrated');
        expect(firstResult['sourceSha256'], sourceSha256);
        expect(firstResult['loadoutCount'], 1000);
        expect(firstResult['importedProfileCount'], 1000);
        expect(firstResult['preservedDeletedProfileCount'], 0);
        expect(firstResult['archiveOnlyLoadoutCount'], 0);
        expect(firstResult['sessionCount'], 1);

        final backupRelative = firstResult['backupRelativePath'] as String;
        expect(
          backupRelative,
          'migration-archive/v0.1.7/fishing-journal.$sourceSha256.json',
        );
        final backup = File(
          _pathAll(<String>[personalRoot.path, ...backupRelative.split('/')]),
        );
        expect(await backup.readAsBytes(), sourceBytes);

        final repeatedMigration = await Process.run(executable.path, <String>[
          '--migrate-v017-json',
          source.path,
          '--database',
          database.path,
        ], workingDirectory: payloadRoot.path);
        expect(
          repeatedMigration.exitCode,
          0,
          reason: '${repeatedMigration.stderr}',
        );
        expect(
          jsonDecode(repeatedMigration.stdout as String),
          containsPair('status', 'already-migrated'),
        );

        final port = await _availablePort();
        service = await Process.start(executable.path, <String>[
          '--root',
          payloadRoot.path,
          '--personal-data-root',
          personalRoot.path,
          '--reference-cache-root',
          referenceRoot.path,
          '--port',
          '$port',
          '--parent-pid',
          '$pid',
          '--api-token',
          apiToken,
        ], workingDirectory: payloadRoot.path);
        final origin = Uri.parse('http://127.0.0.1:$port/');
        final health = await _getWhenReady(
          origin.resolve('/api/health'),
          apiToken,
        );
        expect(health.statusCode, HttpStatus.ok);

        final sessionsResponse = await _get(
          origin.resolve('/api/sessions'),
          apiToken,
        );
        expect(sessionsResponse.statusCode, HttpStatus.ok);
        final sessionsPayload =
            jsonDecode(sessionsResponse.body) as Map<String, dynamic>;
        final sessions = (sessionsPayload['sessions'] as List<dynamic>)
            .cast<Map<String, dynamic>>();
        expect(sessions, hasLength(1));
        final session = sessions.single;
        expect(session['id'], 'synthetic-session-1');
        expect(session['createdAt'], '2026-01-02T03:04:06Z');
        expect(session['caughtAt'], '2026-01-02T03:04:05Z');
        expect(session['startedAt'], '2026-01-02T03:04:05Z');
        expect(session['endedAt'], '2026-01-02T11:04:05Z');
        expect(session['durationMinutes'], 480);
        expect(session['zoneName'], 'Synthetic Coast');
        expect(session['locationName'], 'Synthetic Coast');
        expect(session['method'], 'rod');
        expect(session['style'], isNull);
        expect(session['setupId'], 'synthetic-profile-1');
        expect(session['setupName'], 'Duplicate Profile');
        expect(session['mastery'], 1234);
        expect(session['equipment'], 'Balenos Rod');
        expect(session['totalFish'], 81);
        expect(session['totalValue'], 0);
        expect(session['source'], 'legacy-v017');
        expect(session['verificationStatus'], 'legacy-aggregate-only');
        expect(session['updatedAt'], '2026-01-03T04:05:06Z');
        expect(session['notes'], 'Synthetic session note\nSecond line');
        expect(session['legacyReceivedSilver'], 2240000000);
        expect(session['legacyAggregateOnly'], isTrue);
        expect(session['catches'], isEmpty);
        expect(session['sale'], isNull);

        final unfilteredStatsResponse = await _get(
          origin.resolve('/api/stats'),
          apiToken,
        );
        final unfilteredStats =
            jsonDecode(unfilteredStatsResponse.body) as Map<String, dynamic>;
        expect(unfilteredStatsResponse.statusCode, HttpStatus.ok);
        expect(unfilteredStats['spots'], isEmpty);
        expect(unfilteredStats['totals'], <String, dynamic>{
          'sessions': 0,
          'fish': 0,
          'value': 0,
          'durationMinutes': null,
          'durationSessions': 0,
          'fishPerHour': null,
          'valuePerHour': null,
        });

        final afkSessionsResponse = await _get(
          origin.resolve('/api/sessions?style=afk'),
          apiToken,
        );
        final afkSessions =
            (jsonDecode(afkSessionsResponse.body)
                    as Map<String, dynamic>)['sessions']
                as List<dynamic>;
        expect(afkSessions, isEmpty);
        final afkStatsResponse = await _get(
          origin.resolve('/api/stats?style=afk'),
          apiToken,
        );
        final afkStats =
            jsonDecode(afkStatsResponse.body) as Map<String, dynamic>;
        expect((afkStats['totals'] as Map<String, dynamic>)['sessions'], 0);

        final profilesResponse = await _get(
          origin.resolve('/api/profiles'),
          apiToken,
        );
        final profilesPayload =
            jsonDecode(profilesResponse.body) as Map<String, dynamic>;
        expect(profilesPayload['activeProfileId'], isNull);
        final profiles = (profilesPayload['profiles'] as List<dynamic>)
            .cast<Map<String, dynamic>>();
        expect(profiles, hasLength(1000));
        final firstProfile = profiles.firstWhere(
          (profile) => profile['id'] == 'synthetic-profile-1',
        );
        expect(firstProfile['name'], 'Duplicate Profile');
        expect(firstProfile['method'], 'rod');
        expect(firstProfile['mastery'], 1234);
        expect(firstProfile['equipment'], 'Balenos Rod');
        expect(firstProfile['notes'], 'Synthetic profile note');
        expect(firstProfile['createdAtUtc'], '2026-01-01T01:02:03Z');
        expect(firstProfile['updatedAtUtc'], '2026-01-02T01:02:03Z');
        expect(firstProfile['fishingRank'], isNull);
        expect(firstProfile['fishingLevel'], isNull);
        expect(firstProfile['autoFishingReductionPercent'], isNull);
        expect(firstProfile['autoFishingDelaySeconds'], isNull);
        expect(firstProfile['tradingRank'], isNull);
        expect(firstProfile['tradingLevel'], isNull);
        expect(firstProfile['bargainBonusPercent'], 0.0);

        final duplicateProfile = profiles.firstWhere(
          (profile) => profile['id'] == _longProfileId,
        );
        expect(duplicateProfile['name'], 'duplicate profile');
        expect(duplicateProfile['method'], 'harpoon');
        expect(duplicateProfile['equipment'], '');
        expect(duplicateProfile['notes'], 'Blank tool remains intentional');
        expect(duplicateProfile['createdAtUtc'], '2026-01-01T02:03:04+01:00');
        expect(duplicateProfile['updatedAtUtc'], '2026-01-02T02:03:04+01:00');

        final maximumProfile = profiles.firstWhere(
          (profile) => profile['id'] == _maximumProfileId,
        );
        expect(maximumProfile['id'], hasLength(160));
        expect(maximumProfile['name'], _maximumProfileName);
        expect(maximumProfile['name'], hasLength(120));
        expect(maximumProfile['equipment'], _maximumProfileTool);
        expect(maximumProfile['equipment'], hasLength(200));
        expect(maximumProfile['notes'], hasLength(4000));

        final roundTripResponse = await _put(
          origin.resolve('/api/profiles'),
          apiToken,
          <String, dynamic>{
            'profiles': profiles,
            'activeProfileId': _longProfileId,
          },
        );
        expect(roundTripResponse.statusCode, HttpStatus.ok);
        final roundTrip =
            jsonDecode(roundTripResponse.body) as Map<String, dynamic>;
        expect(roundTrip['activeProfileId'], _longProfileId);
        final roundTripProfiles = (roundTrip['profiles'] as List<dynamic>)
            .cast<Map<String, dynamic>>();
        expect(roundTripProfiles, hasLength(1000));
        final roundTripDuplicate = roundTripProfiles.firstWhere(
          (profile) => profile['id'] == _longProfileId,
        );
        expect(roundTripDuplicate['name'], 'duplicate profile');
        expect(roundTripDuplicate['equipment'], '');
        expect(roundTripDuplicate['notes'], 'Blank tool remains intentional');
        expect(roundTripDuplicate['createdAtUtc'], '2026-01-01T02:03:04+01:00');
        expect(roundTripDuplicate['updatedAtUtc'], '2026-01-02T02:03:04+01:00');

        final statusResponse = await _get(
          origin.resolve('/api/migration-status'),
          apiToken,
        );
        final statusPayload =
            jsonDecode(statusResponse.body) as Map<String, dynamic>;
        final status = statusPayload['legacyV017'] as Map<String, dynamic>;
        expect(status['backupRelativePath'], backupRelative);
        expect(status['loadoutCount'], 1000);
        expect(status['importedProfileCount'], 1000);
        expect(status['preservedDeletedProfileCount'], 0);
        expect(status['archiveOnlyLoadoutCount'], 0);
        expect(status['sessionCount'], 1);
        expect(jsonEncode(status), isNot(contains(personalRoot.path)));
      } finally {
        if (service != null) {
          await Process.run('taskkill', <String>[
            '/PID',
            '${service.pid}',
            '/T',
            '/F',
          ]);
        }
        if (await scratch.exists()) await scratch.delete(recursive: true);
      }
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );
}

final String _longProfileId = 'profile-${_repeat('x', 72)}';
final String _maximumProfileId = ' ${_repeat('i', 158)} ';
final String _maximumProfileName = ' ${_repeat('N', 118)} ';
final String _maximumProfileTool = ' ${_repeat('T', 198)} ';

Map<String, dynamic> _legacyJournal() {
  final loadouts = <Map<String, dynamic>>[
    <String, dynamic>{
      'id': 'synthetic-profile-1',
      'name': 'Duplicate Profile',
      'method': 'fishing',
      'mastery': 1234,
      'tool': 'Balenos Rod',
      'notes': 'Synthetic profile note',
      'createdAtUtc': '2026-01-01T01:02:03Z',
      'updatedAtUtc': '2026-01-02T01:02:03Z',
    },
    <String, dynamic>{
      'id': _longProfileId,
      'name': 'duplicate profile',
      'method': 'harpooning',
      'mastery': 987,
      'tool': '',
      'notes': 'Blank tool remains intentional',
      'createdAtUtc': '2026-01-01T02:03:04+01:00',
      'updatedAtUtc': '2026-01-02T02:03:04+01:00',
    },
    <String, dynamic>{
      'id': _maximumProfileId,
      'name': _maximumProfileName,
      'method': 'fishing',
      'mastery': 3000,
      'tool': _maximumProfileTool,
      'notes': _repeat('m', 4000),
      'createdAtUtc': '2026-02-01T02:03:04Z',
      'updatedAtUtc': '2026-02-02T02:03:04Z',
    },
    for (var index = 3; index < 1000; index++)
      <String, dynamic>{
        'id': 'synthetic-profile-$index',
        'name': 'Synthetic profile $index',
        'method': index.isEven ? 'fishing' : 'harpooning',
        'mastery': index % 3001,
        'tool': index.isEven ? 'Balenos Rod' : 'Thin Harpoon',
        'notes': _repeat('n', 2200),
        'createdAtUtc': '2026-03-01T00:00:00Z',
        'updatedAtUtc': '2026-03-02T00:00:00Z',
      },
  ];
  return <String, dynamic>{
    'version': 1,
    'loadouts': loadouts,
    'sessions': <Map<String, dynamic>>[
      <String, dynamic>{
        'id': 'synthetic-session-1',
        'startedAtUtc': '2026-01-02T03:04:05Z',
        'durationMinutes': 480,
        'location': 'Synthetic Coast',
        'method': 'fishing',
        'loadoutId': 'synthetic-profile-1',
        'loadoutName': 'Duplicate Profile',
        'mastery': 1234,
        'tool': 'Balenos Rod',
        'retainedFishCount': 81,
        'silverReceived': 2240000000,
        'notes': 'Synthetic session note\nSecond line',
        'createdAtUtc': '2026-01-02T03:04:06Z',
        'updatedAtUtc': '2026-01-03T04:05:06Z',
      },
    ],
  };
}

Future<int> _availablePort() async {
  for (var port = 18900; port <= 18930; port++) {
    try {
      final socket = await ServerSocket.bind(
        InternetAddress.loopbackIPv4,
        port,
      );
      await socket.close();
      return port;
    } on SocketException {
      continue;
    }
  }
  throw StateError('No migration-test port is available.');
}

Future<_Response> _getWhenReady(Uri uri, String apiToken) async {
  final deadline = DateTime.now().add(const Duration(seconds: 30));
  while (DateTime.now().isBefore(deadline)) {
    try {
      return await _get(uri, apiToken);
    } on SocketException {
      await Future<void>.delayed(const Duration(milliseconds: 150));
    }
  }
  throw StateError('Compiled Fish Companion service did not become ready.');
}

Future<_Response> _get(Uri uri, String apiToken) async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 3);
  try {
    final request = await client.getUrl(uri);
    request.headers.set('X-BSL-API-Token', apiToken);
    final response = await request.close();
    return _Response(
      statusCode: response.statusCode,
      body: await utf8.decodeStream(response),
    );
  } finally {
    client.close(force: true);
  }
}

Future<_Response> _put(
  Uri uri,
  String apiToken,
  Map<String, dynamic> payload,
) async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 3);
  try {
    final request = await client.putUrl(uri);
    request.headers.contentType = ContentType.json;
    request.headers.set('X-BSL-API-Token', apiToken);
    final body = utf8.encode(jsonEncode(payload));
    request.contentLength = body.length;
    request.add(body);
    final response = await request.close();
    return _Response(
      statusCode: response.statusCode,
      body: await utf8.decodeStream(response),
    );
  } finally {
    client.close(force: true);
  }
}

class _Response {
  const _Response({required this.statusCode, required this.body});

  final int statusCode;
  final String body;
}

String _path(String first, [String? second, String? third]) => <String?>[
  first,
  second,
  third,
].whereType<String>().join(Platform.pathSeparator);

String _pathAll(List<String> parts) => parts.join(Platform.pathSeparator);

String _repeat(String value, int count) =>
    List<String>.filled(count, value).join();
