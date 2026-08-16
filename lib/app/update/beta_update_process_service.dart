import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';

import '../../app_identity.dart';
import 'beta_update.dart';

enum BetaUpdaterHelperOperation { status, check, download, prepareApply }

@immutable
class BetaUpdaterHelperRequest {
  const BetaUpdaterHelperRequest({
    required this.operation,
    required this.source,
    required this.currentVersion,
    this.targetVersion = '',
    this.plannerProcessId = 0,
  });

  final BetaUpdaterHelperOperation operation;
  final String source;
  final String currentVersion;
  final String targetVersion;
  final int plannerProcessId;
}

abstract interface class BetaUpdaterHelperClient {
  Future<BetaUpdateSnapshot> run(
    BetaUpdaterHelperRequest request, {
    required ValueChanged<BetaUpdateSnapshot> onSnapshot,
  });

  Future<void> dispose();
}

class WindowsBetaUpdaterHelperClient implements BetaUpdaterHelperClient {
  WindowsBetaUpdaterHelperClient({
    String? helperPath,
    this.shortOperationTimeout = const Duration(seconds: 30),
    this.downloadTimeout = const Duration(minutes: 30),
  }) : helperPath =
           helperPath ??
           _join(
             File(Platform.resolvedExecutable).parent.path,
             AppIdentity.windowsUpdaterHelperName,
           );

  static const int protocolVersion = 1;
  static const int _maximumOutputLineLength = 256 * 1024;
  static const int _maximumErrorLength = 16 * 1024;
  static const List<int> _magic = <int>[
    0x42,
    0x53,
    0x4c,
    0x55,
    0x50,
    0x44,
    0x31,
    0,
  ];

  final String helperPath;
  final Duration shortOperationTimeout;
  final Duration downloadTimeout;
  Process? _activeProcess;
  bool _disposed = false;

  @override
  Future<BetaUpdateSnapshot> run(
    BetaUpdaterHelperRequest request, {
    required ValueChanged<BetaUpdateSnapshot> onSnapshot,
  }) async {
    if (_disposed) throw StateError('The updater helper is closed.');
    if (!Platform.isWindows) {
      return const BetaUpdateSnapshot(
        phase: BetaUpdatePhase.unsupported,
        message: 'Updates are available on Windows only.',
      );
    }
    final helper = File(helperPath);
    if (!await helper.exists()) {
      throw StateError(
        '${AppIdentity.windowsUpdaterHelperName} is missing from the '
        'application folder.',
      );
    }

    final requestDirectory = await Directory.systemTemp.createTemp(
      'black-spirit-life-update-',
    );
    final requestFile = File(_join(requestDirectory.path, 'request.bin'));
    try {
      await requestFile.writeAsBytes(_encodeRequest(request), flush: true);
      final process = await Process.start(
        helper.path,
        <String>['--request', requestFile.path],
        workingDirectory: helper.parent.path,
        runInShell: false,
        mode: ProcessStartMode.normal,
      );
      if (_disposed) {
        process.kill();
        throw StateError('The updater helper is closed.');
      }
      _activeProcess = process;
      BetaUpdateSnapshot? latest;
      Object? outputError;
      final outputDone = Completer<void>();
      final errorOutput = StringBuffer();
      var errorLength = 0;

      final outputSubscription = process.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen(
            (line) {
              if (outputError != null) return;
              try {
                if (line.length > _maximumOutputLineLength) {
                  throw const FormatException(
                    'The updater helper returned an oversized response.',
                  );
                }
                final decoded = jsonDecode(line);
                if (decoded is! Map ||
                    decoded['protocolVersion'] != protocolVersion) {
                  throw const FormatException(
                    'The updater helper returned an unknown response.',
                  );
                }
                final snapshot = BetaUpdateSnapshot.fromMap(decoded);
                latest = snapshot;
                onSnapshot(snapshot);
              } on Object catch (error) {
                outputError = error;
                process.kill();
              }
            },
            onError: (Object error) {
              outputError ??= error;
              process.kill();
            },
            onDone: outputDone.complete,
          );
      final errorSubscription = process.stderr.listen((bytes) {
        if (errorLength >= _maximumErrorLength) return;
        final remaining = _maximumErrorLength - errorLength;
        final kept = bytes.length <= remaining
            ? bytes
            : bytes.sublist(0, remaining);
        errorOutput.write(utf8.decode(kept, allowMalformed: true));
        errorLength += kept.length;
      });

      final timeout = request.operation == BetaUpdaterHelperOperation.download
          ? downloadTimeout
          : shortOperationTimeout;
      int exitCode;
      try {
        exitCode = await process.exitCode.timeout(timeout);
      } on TimeoutException {
        process.kill();
        await process.exitCode;
        throw TimeoutException('The updater did not finish in time.', timeout);
      } finally {
        if (identical(_activeProcess, process)) _activeProcess = null;
      }
      await outputDone.future;
      await outputSubscription.cancel();
      await errorSubscription.cancel();
      if (outputError case final error?) throw error;
      if (exitCode != 0) {
        final detail = errorOutput.toString().trim();
        throw ProcessException(
          helper.path,
          const <String>[],
          detail.isEmpty
              ? 'The isolated updater stopped unexpectedly.'
              : detail,
          exitCode,
        );
      }
      return latest ??
          (throw const FormatException(
            'The updater helper returned no result.',
          ));
    } finally {
      try {
        if (await requestDirectory.exists()) {
          await requestDirectory.delete(recursive: true);
        }
      } on FileSystemException {
        // The request contains no user settings. Windows can retain a locked
        // temporary file until a later operating-system cleanup.
      }
    }
  }

  Uint8List _encodeRequest(BetaUpdaterHelperRequest request) {
    final source = request.source.trim();
    final currentVersion = request.currentVersion.trim();
    final targetVersion = request.targetVersion.trim();
    if (source.isEmpty || utf8.encode(source).length > 16 * 1024) {
      throw const FormatException('The update source is invalid.');
    }
    if (currentVersion.isEmpty || currentVersion.length > 128) {
      throw const FormatException('The current version is invalid.');
    }
    if (targetVersion.length > 128 || request.plannerProcessId < 0) {
      throw const FormatException('The requested update is invalid.');
    }
    final bytes = BytesBuilder(copy: false)..add(_magic);
    void addUint32(int value) {
      final data = ByteData(4)..setUint32(0, value, Endian.little);
      bytes.add(data.buffer.asUint8List());
    }

    void addString(String value) {
      final encoded = utf8.encode(value);
      addUint32(encoded.length);
      bytes.add(encoded);
    }

    addUint32(protocolVersion);
    addUint32(request.operation.index + 1);
    addUint32(request.plannerProcessId);
    addString(source);
    addString(AppIdentity.installerPackageId);
    addString(AppIdentity.releaseChannel);
    addString(currentVersion);
    addString(targetVersion);
    return bytes.takeBytes();
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    final process = _activeProcess;
    if (process != null) {
      process.kill();
      await process.exitCode;
      if (identical(_activeProcess, process)) _activeProcess = null;
    }
  }

  static String _join(String directory, String child) =>
      directory.endsWith(Platform.pathSeparator)
      ? '$directory$child'
      : '$directory${Platform.pathSeparator}$child';
}

class ProcessBetaUpdateService implements BetaUpdateService {
  ProcessBetaUpdateService({
    required String source,
    BetaUpdaterHelperClient? helperClient,
    this.currentVersion = AppIdentity.applicationVersion,
    int? plannerProcessId,
  }) : source = source.trim(),
       plannerProcessId = plannerProcessId ?? pid,
       _helperClient = helperClient ?? WindowsBetaUpdaterHelperClient(),
       _ownsHelperClient = helperClient == null;

  final String source;
  final String currentVersion;
  final int plannerProcessId;
  final BetaUpdaterHelperClient _helperClient;
  final bool _ownsHelperClient;
  final StreamController<BetaUpdateSnapshot> _snapshots =
      StreamController<BetaUpdateSnapshot>.broadcast(sync: true);
  String _targetVersion = '';
  bool _disposed = false;

  @override
  Stream<BetaUpdateSnapshot> get snapshots => _snapshots.stream;

  @override
  Future<BetaUpdateSnapshot> currentStatus() =>
      _run(BetaUpdaterHelperOperation.status);

  @override
  Future<BetaUpdateSnapshot> checkForUpdates(String requestedSource) {
    if (requestedSource.trim() != source) {
      throw StateError('The update source changed unexpectedly.');
    }
    // A feed may advance between retries. Never constrain a fresh check to the
    // target selected by an older failed or interrupted operation.
    _targetVersion = '';
    return _run(BetaUpdaterHelperOperation.check);
  }

  @override
  Future<BetaUpdateSnapshot> downloadUpdate() {
    if (_targetVersion.isEmpty) {
      throw StateError('Check for an update before downloading.');
    }
    return _run(BetaUpdaterHelperOperation.download);
  }

  @override
  Future<BetaUpdateSnapshot> restartAndApply() {
    if (_targetVersion.isEmpty) {
      throw StateError('No downloaded update is ready.');
    }
    return _run(BetaUpdaterHelperOperation.prepareApply);
  }

  Future<BetaUpdateSnapshot> _run(BetaUpdaterHelperOperation operation) async {
    if (_disposed) throw StateError('The updater is closed.');
    final snapshot = await _helperClient.run(
      BetaUpdaterHelperRequest(
        operation: operation,
        source: source,
        currentVersion: currentVersion,
        targetVersion: _targetVersion,
        plannerProcessId: operation == BetaUpdaterHelperOperation.prepareApply
            ? plannerProcessId
            : 0,
      ),
      onSnapshot: _publish,
    );
    _rememberTarget(snapshot);
    return snapshot;
  }

  void _publish(BetaUpdateSnapshot snapshot) {
    if (_disposed) return;
    _rememberTarget(snapshot);
    _snapshots.add(snapshot);
  }

  void _rememberTarget(BetaUpdateSnapshot snapshot) {
    final target = snapshot.targetVersion.trim();
    if (target.isNotEmpty &&
        (snapshot.phase == BetaUpdatePhase.available ||
            snapshot.phase == BetaUpdatePhase.downloading ||
            snapshot.phase == BetaUpdatePhase.ready ||
            snapshot.phase == BetaUpdatePhase.applying)) {
      _targetVersion = target;
      return;
    }
    if (snapshot.phase != BetaUpdatePhase.checking) _targetVersion = '';
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    if (_ownsHelperClient) await _helperClient.dispose();
    await _snapshots.close();
  }
}
