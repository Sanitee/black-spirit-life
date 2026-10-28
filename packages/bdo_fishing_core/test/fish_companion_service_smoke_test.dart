import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'compiled service serves the accepted shell and API on localhost',
    () async {
      if (!Platform.isWindows) return;

      final packageRoot = Directory.current;
      final payloadRoot = Directory(
        _path(packageRoot.path, 'assets', 'fish_companion'),
      );
      final scratch = await Directory.systemTemp.createTemp(
        'fish-companion-service-smoke-',
      );
      final appRoot = Directory(_path(scratch.path, 'app'));
      final personalRoot = Directory(_path(scratch.path, 'personal'));
      final referenceRoot = Directory(_path(scratch.path, 'reference-cache'));
      const apiToken = 'fish-companion-smoke-test-token-0001';
      Process? process;
      try {
        await _copyTree(
          Directory(_path(payloadRoot.path, 'static')),
          Directory(_path(appRoot.path, 'static')),
        );
        await _copyTree(
          Directory(_path(payloadRoot.path, 'recognizer')),
          Directory(_path(appRoot.path, 'recognizer')),
        );
        await _copyTree(
          Directory(_path(payloadRoot.path, 'backend')),
          Directory(_path(appRoot.path, 'backend')),
        );
        final cache = Directory(_path(appRoot.path, 'data', 'cache'));
        await cache.create(recursive: true);
        for (final name in <String>[
          'fish.json',
          'zone-loot-facts.json',
          'zones.json',
          'meta.json',
          'tileset.json',
          'zone_mask.v8.bin',
          'zone-evidence-points.json',
          'regions.bin',
          'regions.meta.json',
          'region-groups.bin',
          'region-groups.meta.json',
          'region-nodes.geojson',
          'source-state.json',
          'derived-index.v1.json',
        ]) {
          await File(
            _path(payloadRoot.path, 'data', 'cache', name),
          ).copy(_path(cache.path, name));
        }
        await _copyTree(
          Directory(_path(payloadRoot.path, 'data', 'cache', 'zone-details')),
          Directory(_path(cache.path, 'zone-details')),
        );
        final derivedIndex = File(_path(cache.path, 'derived-index.v1.json'));
        final cacheHitSentinel = DateTime.utc(2001, 1, 2, 3, 4, 5);
        await derivedIndex.setLastModified(cacheHitSentinel);
        expect(
          File(
            _path(personalRoot.path, 'fishing', 'fish-journal.sqlite3'),
          ).existsSync(),
          isFalse,
        );

        final port = await _availablePort();
        final executable = File(
          _path(payloadRoot.path, 'runtime', 'fish_companion_service.exe'),
        );
        process = await Process.start(executable.path, <String>[
          '--root',
          appRoot.path,
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
        ], workingDirectory: appRoot.path);

        final origin = Uri.parse('http://127.0.0.1:$port/');
        final health = await _getWhenReady(
          origin.resolve('/api/health'),
          apiToken,
        );
        expect(health.statusCode, HttpStatus.ok);
        final healthJson = jsonDecode(health.body) as Map<String, dynamic>;
        expect(healthJson, containsPair('service', 'BDO Fish Companion'));
        expect(healthJson['recognition'], containsPair('available', true));

        final shell = await _get(origin);
        expect(shell.statusCode, HttpStatus.ok);
        expect(shell.body, contains('data-page="capture"'));
        expect(shell.body, contains('data-page="journal"'));
        expect(shell.body, contains('data-page="stats"'));

        final bootstrap = await _get(
          origin.resolve('/api/bootstrap'),
          apiToken: apiToken,
        );
        expect(bootstrap.statusCode, HttpStatus.ok);
        final bootstrapJson =
            jsonDecode(bootstrap.body) as Map<String, dynamic>;
        expect(bootstrapJson['zones'], isNotEmpty);
        expect(bootstrapJson['fish'], isNotEmpty);
        expect(
          (await derivedIndex.lastModified()).millisecondsSinceEpoch,
          cacheHitSentinel.millisecondsSinceEpoch,
        );

        final firstRefresh = await _post(
          origin.resolve('/api/background-refresh'),
          apiToken: apiToken,
        );
        final repeatedRefresh = await _post(
          origin.resolve('/api/background-refresh'),
          apiToken: apiToken,
        );
        expect(firstRefresh.statusCode, HttpStatus.ok);
        expect(jsonDecode(firstRefresh.body), containsPair('started', true));
        expect(repeatedRefresh.statusCode, HttpStatus.ok);
        expect(
          jsonDecode(repeatedRefresh.body),
          containsPair('started', false),
        );
        expect(
          File(
            _path(personalRoot.path, 'fishing', 'fish-journal.sqlite3'),
          ).existsSync(),
          isTrue,
        );
      } finally {
        if (process != null) {
          await Process.run('taskkill', <String>[
            '/PID',
            '${process.pid}',
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

Future<void> _copyTree(Directory source, Directory destination) async {
  await destination.create(recursive: true);
  await for (final entity in source.list(recursive: true, followLinks: false)) {
    final relative = entity.path.substring(source.path.length + 1);
    final target = _path(destination.path, relative);
    if (entity is Directory) {
      await Directory(target).create(recursive: true);
    } else if (entity is File) {
      await File(target).parent.create(recursive: true);
      await entity.copy(target);
    }
  }
}

Future<int> _availablePort() async {
  for (var port = 18925; port <= 18955; port++) {
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
  throw StateError('No smoke-test port is available.');
}

Future<_Response> _getWhenReady(Uri uri, String apiToken) async {
  final deadline = DateTime.now().add(const Duration(seconds: 30));
  while (DateTime.now().isBefore(deadline)) {
    try {
      return await _get(uri, apiToken: apiToken);
    } on SocketException {
      await Future<void>.delayed(const Duration(milliseconds: 150));
    }
  }
  throw StateError('Compiled Fish Companion service did not become ready.');
}

Future<_Response> _get(Uri uri, {String? apiToken}) async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 3);
  try {
    final request = await client.getUrl(uri);
    if (apiToken != null) request.headers.set('X-BSL-API-Token', apiToken);
    final response = await request.close();
    return _Response(
      statusCode: response.statusCode,
      body: await utf8.decodeStream(response),
    );
  } finally {
    client.close(force: true);
  }
}

Future<_Response> _post(Uri uri, {required String apiToken}) async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 3);
  try {
    final request = await client.postUrl(uri);
    request.headers.set('X-BSL-API-Token', apiToken);
    request.contentLength = 0;
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

String _path(
  String first, [
  String? second,
  String? third,
  String? fourth,
  String? fifth,
]) => <String?>[
  first,
  second,
  third,
  fourth,
  fifth,
].whereType<String>().join(Platform.pathSeparator);
