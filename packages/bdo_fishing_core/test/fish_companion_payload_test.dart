import 'dart:convert';
import 'dart:io';

import 'package:bdo_fishing_core/bdo_fishing_core.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final packageRoot = Directory.current;
  final payloadRoot = Directory(
    _join(packageRoot.path, 'assets', 'fish_companion'),
  );

  test('runtime install marker tracks the pinned payload manifest', () {
    final integrity =
        jsonDecode(
              File(
                _join(
                  packageRoot.path,
                  'assets',
                  'fish_companion_integrity.json',
                ),
              ).readAsStringSync(),
            )
            as Map<String, dynamic>;

    expect(
      fishCompanionAcceptedPayloadVersion,
      '${integrity['sourceAggregateSha256']}:${integrity['serviceSha256']}',
    );
  });

  test('bundles the accepted standalone frontend and all internal pages', () {
    final html = File(
      _join(payloadRoot.path, 'static', 'index.html'),
    ).readAsStringSync();
    final script = File(
      _join(payloadRoot.path, 'static', 'app.js'),
    ).readAsStringSync();

    expect(html, contains('data-page="map"'));
    expect(html, contains('data-page="capture"'));
    expect(html, contains('data-page="journal"'));
    expect(html, contains('data-page="stats"'));
    expect(html, contains('id="profileButton"'));
    expect(html, contains('<title>BDO Fish Map</title>'));
    expect(html, contains('<link rel="icon" href="/fishystuff.png">'));
    expect(
      html,
      contains(
        '<div class="boot-mark"><img src="/fishystuff.png" alt=""></div>',
      ),
    );
    expect(
      html,
      contains('<strong>Fish Map</strong><small>Black Desert Online</small>'),
    );
    expect(html, isNot(contains('<strong>Fish Companion</strong>')));
    expect(
      html,
      contains('class="brand-icon-link" href="https://fishystuff.fish/map/"'),
    );
    expect(html, isNot(contains('class="source-brand-link"')));
    final brand = html.substring(
      html.indexOf('<div class="brand-cluster">'),
      html.indexOf('<nav class="primary-nav"'),
    );
    expect(RegExp('<img ').allMatches(brand), hasLength(1));
    expect(brand, contains('target="_blank" rel="noopener noreferrer"'));
    expect(brand, contains('class="brand" data-go="map"'));
    expect(brand, isNot(contains('/icon/8479.webp')));
    expect(html, contains('class="fishystuff-credit glass-panel"'));
    expect(html, contains('aria-label="Open FishyStuff fishing map source"'));
    expect(html, contains('<img src="/fishystuff.png" alt="">'));
    expect(
      File(_join(payloadRoot.path, 'static', 'fishystuff.png')).existsSync(),
      isTrue,
    );
    expect(script, contains('applyMapFilters'));
    expect(script, contains('renderJournal'));
    expect(script, contains('renderStats'));

    final appReveal = script.indexOf('els.app.classList.remove("is-hidden")');
    final refreshStart = script.indexOf(
      'request("/api/background-refresh", { method: "POST" })',
    );
    expect(appReveal, greaterThanOrEqualTo(0));
    expect(refreshStart, greaterThan(appReveal));
    expect(
      script.substring(appReveal, refreshStart),
      contains(
        'window.requestAnimationFrame(() => window.requestAnimationFrame(() =>',
      ),
    );
  });

  test(
    'legacy v0.1.7 aggregate helpers preserve totals without inventing fish',
    () async {
      final script = File(
        _join(payloadRoot.path, 'static', 'app.js'),
      ).readAsStringSync();
      final helperStart = script.indexOf('function sessionCatches(session)');
      final helperEnd = script.indexOf('function sessionBargainBonus(session)');
      expect(helperStart, greaterThanOrEqualTo(0));
      expect(helperEnd, greaterThan(helperStart));

      final program =
          '''
const state = { fishById: new Map() };
${script.substring(helperStart, helperEnd)}
const legacy = {
  source: "legacy-v017",
  totalFish: 81,
  legacyReceivedSilver: 2240000000,
  catches: [],
};
const modern = {
  totalFish: 999,
  legacyReceivedSilver: 123,
  catches: [{ itemId: 1, count: 2, price: 10 }],
};
process.stdout.write(JSON.stringify({
  legacy: isLegacyAggregateSession(legacy),
  legacyTotal: sessionTotal(legacy),
  legacyValue: sessionValue(legacy),
  legacyReceived: legacyReceivedSilver(legacy),
  modern: isLegacyAggregateSession(modern),
  modernTotal: sessionTotal(modern),
  modernValue: sessionValue(modern),
  modernReceived: legacyReceivedSilver(modern),
}));
''';
      final result = await Process.run(
        'node',
        <String>['-e', program],
        stdoutEncoding: utf8,
        stderrEncoding: utf8,
      );
      expect(result.exitCode, 0, reason: '${result.stderr}');
      final values =
          jsonDecode(result.stdout as String) as Map<String, dynamic>;
      expect(values, <String, dynamic>{
        'legacy': true,
        'legacyTotal': 81,
        'legacyValue': 0,
        'legacyReceived': 2240000000,
        'modern': false,
        'modernTotal': 2,
        'modernValue': 20,
        'modernReceived': null,
      });
    },
  );

  test(
    'legacy aggregate sessions cannot distort same-location personal stats',
    () async {
      final script = File(
        _join(payloadRoot.path, 'static', 'app.js'),
      ).readAsStringSync();
      final helperStart = script.indexOf('function buildPersonalStats()');
      final helperEnd = script.indexOf('function renderStats()');
      expect(helperStart, greaterThanOrEqualTo(0));
      expect(helperEnd, greaterThan(helperStart));

      final program =
          '''
const state = {
  method: { stats: "rod" },
  statsLocation: null,
  sessions: [
    {
      source: "legacy-v017",
      method: "rod",
      locationName: "Velia Beach",
      zoneName: "Balenos Coast",
      zoneRgb: 1,
      resourceLevel: "exhausted",
      durationMinutes: 600,
      catches: [],
    },
    {
      source: "capture",
      method: "rod",
      locationName: "Velia Beach",
      zoneName: "Balenos Coast",
      zoneRgb: 1,
      resourceLevel: "abundant",
      durationMinutes: 60,
      catches: [{ itemId: 1, name: "Fish", count: 60, price: 10, grade: "yellow" }],
    },
  ],
};
const field = value => ({ value });
const els = {
  statsProfile: field("all"),
  statsStyle: field("all"),
  statsEquipment: field("all"),
  statsMastery: field("all"),
  statsResource: field("all"),
};
const isLegacyAggregateSession = session => session.source === "legacy-v017";
const masteryMatches = () => true;
const statsLocationMatchesSession = () => true;
const normalizeRgb = value => Number(value);
const depthKey = () => "coast";
const sessionCatches = session => session.catches || [];
const statsGradeKey = () => "yellow";
const STATS_GRADE_DEFINITIONS = [{ key: "yellow", label: "Yellow fish" }];
const resourceLabel = value => value;
${script.substring(helperStart, helperEnd)}
const spot = buildPersonalStats()[0];
process.stdout.write(JSON.stringify({
  sessions: spot.sessions,
  totalFish: spot.totalFish,
  totalMinutes: spot.totalMinutes,
  fishPerHour: spot.fishPerHour,
  resourceSummary: spot.resourceSummary,
}));
''';
      final result = await Process.run(
        'node',
        <String>['-e', program],
        stdoutEncoding: utf8,
        stderrEncoding: utf8,
      );
      expect(result.exitCode, 0, reason: '${result.stderr}');
      expect(jsonDecode(result.stdout as String), <String, dynamic>{
        'sessions': 1,
        'totalFish': 60,
        'totalMinutes': 60,
        'fishPerHour': 60,
        'resourceSummary': 'abundant',
      });
    },
  );

  test('legacy journal and lossless profile recovery remain visible', () {
    final html = File(
      _join(payloadRoot.path, 'static', 'index.html'),
    ).readAsStringSync();
    final script = File(
      _join(payloadRoot.path, 'static', 'app.js'),
    ).readAsStringSync();
    final backendStore = File(
      _join(payloadRoot.path, 'backend', 'store.py'),
    ).readAsStringSync();
    final backendHttp = File(
      _join(payloadRoot.path, 'backend', 'http.py'),
    ).readAsStringSync();

    for (final id in <String>[
      'profileMigrationNotice',
      'profileMigrationTitle',
      'profileMigrationSummary',
      'profileMigrationPath',
      'profileMigrationCopy',
    ]) {
      expect(html, contains('id="$id"'), reason: id);
    }
    expect(script, contains('request("/api/migration-status")'));
    expect(script, contains('migration.backupRelativePath'));
    expect(script, contains('migration.preservedDeletedProfileCount'));
    expect(script, contains('profile you previously deleted stays'));
    expect(script, contains('Personal data folder ›'));
    expect(html, contains('id="profileName" type="text" maxlength="120"'));
    expect(
      html,
      contains('id="profileEquipmentText" type="text" maxlength="200"'),
    );
    expect(html, contains('id="profileNotes" maxlength="4000"'));
    expect(html, isNot(contains('id="profileMigrationRecreate"')));
    expect(script, contains('All \${number(importedCount)}'));
    expect(script, isNot(contains('Profile names must be unique.')));
    expect(backendStore, contains('MAX_FISHING_PROFILES = 1_016'));
    expect(
      backendStore,
      contains('filters, exclude_legacy_aggregates=True'),
    );
    expect(backendStore, contains('"legacySourceId"'));
    expect(script, contains('legacySourceId: existing?.legacySourceId ?? null'));
    expect(backendStore, contains('maximum=160'));
    expect(backendStore, contains('maximum=200'));
    expect(backendStore, contains('maximum=4_000'));
    expect(backendHttp, contains('MAX_JSON_BODY = 2 * 1024 * 1024'));
    expect(backendHttp, contains('MAX_PROFILE_JSON_BODY = 24 * 1024 * 1024'));
    expect(
      backendHttp,
      contains('self._read_json_body(MAX_PROFILE_JSON_BODY)'),
    );
    expect(script, contains('Legacy received'));
    expect(script, contains('journal-session-note'));
    expect(script, contains('session.notes'));
    expect(script, contains('journal-legacy-lock'));
    expect(script, contains('const actions = legacyAggregate'));
    expect(
      script,
      contains('\$(".journal-sale-button", row)?.addEventListener'),
    );
    expect(
      script,
      contains('Imported v0.1.7 aggregate hauls are preserved read-only.'),
    );
    expect(
      script,
      contains(
        'Imported v0.1.7 aggregate hauls cannot be recalculated or sold again.',
      ),
    );
    final windowsProfilePrefix = <String>['C:', 'Users', ''].join(r'\');
    expect(script, isNot(contains(windowsProfilePrefix)));
  });

  test(
    'duplicate legacy profile names get derived labels without mutation',
    () async {
      final script = File(
        _join(payloadRoot.path, 'static', 'app.js'),
      ).readAsStringSync();
      final helperStart = script.indexOf(
        'function profileDisplayLabels(profiles)',
      );
      final helperEnd = script.indexOf('function profileLabel(profile)');
      expect(helperStart, greaterThanOrEqualTo(0));
      expect(helperEnd, greaterThan(helperStart));
      final program =
          '''
const number = value => String(value);
${script.substring(helperStart, helperEnd)}
const profiles = [
  { id: " exact-id-1 ", name: "Night AFK", method: "rod", mastery: 2200 },
  { id: "exact-id-2", name: "night afk", method: "harpoon", mastery: 1800 },
  { id: "exact-id-3", name: "Day", method: "rod", mastery: 900 },
];
const before = JSON.stringify(profiles);
const labels = profileDisplayLabels(profiles);
process.stdout.write(JSON.stringify({
  first: labels.get(" exact-id-1 "),
  second: labels.get("exact-id-2"),
  third: labels.get("exact-id-3"),
  unchanged: before === JSON.stringify(profiles),
}));
''';
      final result = await Process.run(
        'node',
        <String>['-e', program],
        stdoutEncoding: utf8,
        stderrEncoding: utf8,
      );
      expect(result.exitCode, 0, reason: '${result.stderr}');
      expect(jsonDecode(result.stdout as String), <String, dynamic>{
        'first': 'Night AFK · Fishing · 2200 mastery · 1/2',
        'second': 'night afk · Harpooning · 1800 mastery · 2/2',
        'third': 'Day',
        'unchanged': true,
      });
    },
  );

  test(
    'saving an untouched migrated profile keeps calculation inputs unset',
    () async {
      final script = File(
        _join(payloadRoot.path, 'static', 'app.js'),
      ).readAsStringSync();
      final helperStart = script.indexOf('function profileFormValues()');
      final helperEnd = script.indexOf('async function saveProfile(event)');
      expect(helperStart, greaterThanOrEqualTo(0));
      expect(helperEnd, greaterThan(helperStart));
      final program =
          '''
const migrated = {
  id: "legacy-profile",
  name: "Legacy",
  method: "rod",
  equipment: "",
  mastery: 2200,
  fishingRank: null,
  fishingLevel: null,
  autoFishingReductionPercent: null,
  tradingRank: null,
  tradingLevel: null,
  notes: "legacy note",
  createdAtUtc: "2026-01-01T00:00:00Z",
  updatedAtUtc: "2026-01-02T00:00:00Z",
};
const state = {
  profileEditingId: migrated.id,
  fishingProfiles: [migrated],
  profileEditorBaseline: { id: migrated.id, name: "Legacy", equipment: "", notes: "legacy note" },
};
const field = value => ({ value });
const els = {
  profileForm: { reportValidity: () => true },
  profileMethod: field("rod"),
  profileName: field("Legacy"),
  profileEquipmentText: field(""),
  profileMastery: field("2200"),
  profileFishingRank: field(""),
  profileFishingLevel: field(""),
  profileAutoReductionPercent: field(""),
  profileTradingRank: field(""),
  profileTradingLevel: field(""),
  profileNotes: field("legacy note"),
};
const newProfileId = () => "unexpected-new-id";
${script.substring(helperStart, helperEnd)}
process.stdout.write(JSON.stringify(profileFormValues()));
''';
      final result = await Process.run(
        'node',
        <String>['-e', program],
        stdoutEncoding: utf8,
        stderrEncoding: utf8,
      );
      expect(result.exitCode, 0, reason: '${result.stderr}');
      final profile =
          jsonDecode(result.stdout as String) as Map<String, dynamic>;
      expect(profile['id'], 'legacy-profile');
      expect(profile['fishingRank'], isNull);
      expect(profile['fishingLevel'], isNull);
      expect(profile['autoFishingReductionPercent'], isNull);
      expect(profile['tradingRank'], isNull);
      expect(profile['tradingLevel'], isNull);
      expect(profile['createdAtUtc'], '2026-01-01T00:00:00Z');
      expect(profile['updatedAtUtc'], '2026-01-02T00:00:00Z');
    },
  );

  test('standalone source payload remains byte-exact', () async {
    final integrity =
        jsonDecode(
              File(
                _join(
                  packageRoot.path,
                  'assets',
                  'fish_companion_integrity.json',
                ),
              ).readAsStringSync(),
            )
            as Map<String, dynamic>;
    final roots = <String>['static', 'backend', 'recognizer', 'data'];
    final files = <File>[];
    for (final root in roots) {
      await for (final entity in Directory(
        _join(payloadRoot.path, root),
      ).list(recursive: true, followLinks: false)) {
        if (entity is! File) continue;
        final relative = _relative(payloadRoot, entity);
        if (_isGeneratedPythonCache(relative)) continue;
        files.add(entity);
      }
    }
    files.sort(
      (left, right) => _relative(
        payloadRoot,
        left,
      ).toLowerCase().compareTo(_relative(payloadRoot, right).toLowerCase()),
    );

    var byteCount = 0;
    final lines = <String>[];
    for (final file in files) {
      final bytes = await file.readAsBytes();
      byteCount += bytes.length;
      final relative = _relative(payloadRoot, file);
      lines.add('$relative|${bytes.length}|${sha256.convert(bytes)}');
    }
    final aggregate = sha256.convert(utf8.encode(lines.join('\n'))).toString();

    expect(files.length, integrity['sourceFileCount']);
    expect(byteCount, integrity['sourceByteCount']);
    expect(aggregate, integrity['sourceAggregateSha256']);
  });

  test('self-contained localhost service binary remains pinned', () async {
    final integrity =
        jsonDecode(
              File(
                _join(
                  packageRoot.path,
                  'assets',
                  'fish_companion_integrity.json',
                ),
              ).readAsStringSync(),
            )
            as Map<String, dynamic>;
    final executable = File(
      _join(payloadRoot.path, 'runtime', 'fish_companion_service.exe'),
    );
    final bytes = await executable.readAsBytes();

    expect(bytes.length, integrity['serviceByteCount']);
    expect(sha256.convert(bytes).toString(), integrity['serviceSha256']);
  });

  test(
    'critical install manifest and snapshot receipt pin real files',
    () async {
      final manifest =
          jsonDecode(
                File(
                  _join(
                    payloadRoot.path,
                    'data',
                    'install-critical-manifest.v1.json',
                  ),
                ).readAsStringSync(),
              )
              as Map<String, dynamic>;
      expect(manifest['schemaVersion'], 1);

      final immutable = (manifest['immutableFiles'] as List<dynamic>)
          .cast<Map<String, dynamic>>();
      final snapshot = (manifest['snapshotFiles'] as List<dynamic>)
          .cast<Map<String, dynamic>>();
      expect(immutable.map((record) => record['path']).toSet(), <String>{
        'static/index.html',
        'static/app.js',
        'static/app.css',
        'runtime/fish_companion_service.exe',
      });
      expect(snapshot.map((record) => record['path']).toSet(), <String>{
        'data/cache/fish.json',
        'data/cache/zones.json',
        'data/cache/meta.json',
        'data/cache/zone_mask.v8.bin',
        'data/cache/derived-index.v1.json',
      });
      for (final record in <Map<String, dynamic>>[...immutable, ...snapshot]) {
        final relative = record['path']! as String;
        final file = File(
          <String>[
            payloadRoot.path,
            ...relative.split('/'),
          ].join(Platform.pathSeparator),
        );
        final bytes = await file.readAsBytes();
        expect(bytes.length, record['byteCount'], reason: relative);
        expect(
          sha256.convert(bytes).toString(),
          record['sha256'],
          reason: relative,
        );
      }

      final receipt =
          jsonDecode(
                File(
                  <String>[
                    payloadRoot.path,
                    'data',
                    'cache',
                    'runtime-snapshot-integrity.v1.json',
                  ].join(Platform.pathSeparator),
                ).readAsStringSync(),
              )
              as Map<String, dynamic>;
      expect(receipt['schemaVersion'], 1);
      expect(receipt['files'], snapshot);
      final canonical = StringBuffer();
      for (final record in snapshot) {
        canonical.writeln(
          '${record['path']}|${record['byteCount']}|${record['sha256']}',
        );
      }
      expect(
        receipt['snapshotSha256'],
        sha256.convert(utf8.encode(canonical.toString())).toString(),
      );
    },
  );
}

String _relative(Directory root, File file) =>
    file.path.substring(root.path.length + 1).replaceAll('\\', '/');

bool _isGeneratedPythonCache(String relative) {
  final normalized = relative.replaceAll('\\', '/').toLowerCase();
  return normalized.endsWith('.pyc') ||
      normalized.split('/').contains('__pycache__');
}

String _join(String first, String second, [String? third]) {
  final base = first.endsWith(Platform.pathSeparator)
      ? '$first$second'
      : '$first${Platform.pathSeparator}$second';
  if (third == null) return base;
  return '$base${Platform.pathSeparator}$third';
}
