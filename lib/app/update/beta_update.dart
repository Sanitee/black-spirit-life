import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

enum BetaUpdatePhase {
  idle,
  checking,
  upToDate,
  available,
  downloading,
  ready,
  applying,
  offline,
  error,
  unsupported,
  notConfigured;

  static BetaUpdatePhase fromWire(String? value) => switch (value) {
    'checking' => checking,
    'upToDate' => upToDate,
    'available' => available,
    'downloading' => downloading,
    'ready' => ready,
    'applying' => applying,
    'offline' => offline,
    'error' => error,
    'unsupported' => unsupported,
    'notConfigured' => notConfigured,
    _ => idle,
  };
}

@immutable
class BetaUpdateSnapshot {
  const BetaUpdateSnapshot({
    this.phase = BetaUpdatePhase.idle,
    this.installed = false,
    this.portable = true,
    this.currentVersion = '',
    this.appId = '',
    this.targetVersion = '',
    this.releaseNotesMarkdown = '',
    this.sizeBytes = 0,
    this.fullSizeBytes = 0,
    this.deltaCount = 0,
    this.progress = 0,
    this.message = '',
    this.testOnly = false,
  });

  const BetaUpdateSnapshot.notConfigured()
    : this(
        phase: BetaUpdatePhase.notConfigured,
        message: 'No update source has been configured.',
      );

  const BetaUpdateSnapshot.paused()
    : this(
        phase: BetaUpdatePhase.unsupported,
        message: 'Update checks are temporarily paused.',
      );

  factory BetaUpdateSnapshot.fromMap(Object? value) {
    final map = value is Map ? value : const <Object?, Object?>{};
    String stringValue(String key) => map[key]?.toString() ?? '';
    bool boolValue(String key, {required bool fallback}) =>
        map[key] is bool ? map[key]! as bool : fallback;
    num numberValue(String key) => map[key] is num ? map[key]! as num : 0;

    return BetaUpdateSnapshot(
      phase: BetaUpdatePhase.fromWire(stringValue('status')),
      installed: boolValue('installed', fallback: false),
      portable: boolValue('portable', fallback: true),
      currentVersion: stringValue('currentVersion'),
      appId: stringValue('appId'),
      targetVersion: stringValue('targetVersion'),
      releaseNotesMarkdown: stringValue('releaseNotesMarkdown'),
      sizeBytes:
          (map.containsKey('downloadSizeBytes')
                  ? numberValue('downloadSizeBytes')
                  : numberValue('sizeBytes'))
              .toInt()
              .clamp(0, 0x7fffffffffffffff),
      fullSizeBytes: numberValue(
        'fullSizeBytes',
      ).toInt().clamp(0, 0x7fffffffffffffff),
      deltaCount: numberValue('deltaCount').toInt().clamp(0, 0x7fffffff),
      progress: numberValue('progress').toDouble().clamp(0, 1),
      message: stringValue('message'),
    );
  }

  final BetaUpdatePhase phase;
  final bool installed;
  final bool portable;
  final String currentVersion;
  final String appId;
  final String targetVersion;
  final String releaseNotesMarkdown;
  final int sizeBytes;
  final int fullSizeBytes;
  final int deltaCount;
  final double progress;
  final String message;
  final bool testOnly;

  bool get usesDelta => deltaCount > 0 && sizeBytes > 0;

  bool get showsIndicator => switch (phase) {
    BetaUpdatePhase.available ||
    BetaUpdatePhase.downloading ||
    BetaUpdatePhase.ready ||
    BetaUpdatePhase.applying => true,
    _ => false,
  };

  BetaUpdateSnapshot withFailure(BetaUpdatePhase failure, String detail) =>
      BetaUpdateSnapshot(
        phase: failure,
        installed: installed,
        portable: portable,
        currentVersion: currentVersion,
        appId: appId,
        targetVersion: targetVersion,
        releaseNotesMarkdown: releaseNotesMarkdown,
        sizeBytes: sizeBytes,
        fullSizeBytes: fullSizeBytes,
        deltaCount: deltaCount,
        progress: progress,
        message: detail,
        testOnly: testOnly,
      );

  BetaUpdateSnapshot copyWith({
    BetaUpdatePhase? phase,
    bool? installed,
    bool? portable,
    String? currentVersion,
    String? appId,
    String? targetVersion,
    String? releaseNotesMarkdown,
    int? sizeBytes,
    int? fullSizeBytes,
    int? deltaCount,
    double? progress,
    String? message,
    bool? testOnly,
  }) => BetaUpdateSnapshot(
    phase: phase ?? this.phase,
    installed: installed ?? this.installed,
    portable: portable ?? this.portable,
    currentVersion: currentVersion ?? this.currentVersion,
    appId: appId ?? this.appId,
    targetVersion: targetVersion ?? this.targetVersion,
    releaseNotesMarkdown: releaseNotesMarkdown ?? this.releaseNotesMarkdown,
    sizeBytes: sizeBytes ?? this.sizeBytes,
    fullSizeBytes: fullSizeBytes ?? this.fullSizeBytes,
    deltaCount: deltaCount ?? this.deltaCount,
    progress: progress ?? this.progress,
    message: message ?? this.message,
    testOnly: testOnly ?? this.testOnly,
  );
}

abstract interface class BetaUpdateService {
  Stream<BetaUpdateSnapshot> get snapshots;

  Future<BetaUpdateSnapshot> currentStatus();
  Future<BetaUpdateSnapshot> checkForUpdates(String source);
  Future<BetaUpdateSnapshot> downloadUpdate();
  Future<BetaUpdateSnapshot> restartAndApply();
  Future<void> dispose();
}

/// A Dart-only safety service used while native updater work is isolated from
/// the running planner. It never invokes the platform channel or creates an
/// update manager.
class PausedBetaUpdateService implements BetaUpdateService {
  const PausedBetaUpdateService();

  @override
  Stream<BetaUpdateSnapshot> get snapshots =>
      const Stream<BetaUpdateSnapshot>.empty();

  @override
  Future<BetaUpdateSnapshot> currentStatus() async =>
      const BetaUpdateSnapshot.paused();

  @override
  Future<BetaUpdateSnapshot> checkForUpdates(String source) async =>
      const BetaUpdateSnapshot.paused();

  @override
  Future<BetaUpdateSnapshot> downloadUpdate() async =>
      const BetaUpdateSnapshot.paused();

  @override
  Future<BetaUpdateSnapshot> restartAndApply() async =>
      const BetaUpdateSnapshot.paused();

  @override
  Future<void> dispose() async {}
}

@Deprecated('Use ProcessBetaUpdateService; in-process updates are unsafe.')
class NativeBetaUpdateService implements BetaUpdateService {
  NativeBetaUpdateService({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel('com.blackspiritlife/updates') {
    _channel.setMethodCallHandler(_handleNativeCall);
  }

  final MethodChannel _channel;
  final StreamController<BetaUpdateSnapshot> _snapshots =
      StreamController<BetaUpdateSnapshot>.broadcast(sync: true);
  bool _disposed = false;

  @override
  Stream<BetaUpdateSnapshot> get snapshots => _snapshots.stream;

  @override
  Future<BetaUpdateSnapshot> currentStatus() => _invoke('getUpdateStatus');

  @override
  Future<BetaUpdateSnapshot> checkForUpdates(String source) =>
      _invoke('checkForUpdates', <String, Object?>{'source': source});

  @override
  Future<BetaUpdateSnapshot> downloadUpdate() => _invoke('downloadUpdate');

  @override
  Future<BetaUpdateSnapshot> restartAndApply() => _invoke('restartAndApply');

  Future<Object?> _handleNativeCall(MethodCall call) async {
    if (call.method != 'statusChanged') {
      throw MissingPluginException('Unknown update callback ${call.method}.');
    }
    final snapshot = BetaUpdateSnapshot.fromMap(call.arguments);
    if (!_disposed) _snapshots.add(snapshot);
    return null;
  }

  Future<BetaUpdateSnapshot> _invoke(
    String method, [
    Map<String, Object?>? arguments,
  ]) async {
    final value = await _channel.invokeMethod<Object?>(method, arguments);
    final snapshot = BetaUpdateSnapshot.fromMap(value);
    if (!_disposed) _snapshots.add(snapshot);
    return snapshot;
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _channel.setMethodCallHandler(null);
    await _snapshots.close();
  }
}

abstract final class BetaUpdateSource {
  static const environmentKey = 'BLACK_SPIRIT_LIFE_UPDATE_SOURCE';
  static const compiled = String.fromEnvironment(environmentKey);

  static String resolve({String? compiledValue, Map<String, String>? process}) {
    final bakedIn = (compiledValue ?? compiled).trim();
    if (bakedIn.isNotEmpty) return bakedIn;
    return (process ?? Platform.environment)[environmentKey]?.trim() ?? '';
  }
}

class BetaUpdateController extends ChangeNotifier {
  BetaUpdateController({
    required this.service,
    required this.source,
    this.enabled = true,
  }) : _snapshot = !enabled
           ? const BetaUpdateSnapshot.paused()
           : source.trim().isEmpty
           ? const BetaUpdateSnapshot.notConfigured()
           : const BetaUpdateSnapshot() {
    _subscription = service.snapshots.listen(_adopt);
  }

  final BetaUpdateService service;
  final String source;
  final bool enabled;
  late final StreamSubscription<BetaUpdateSnapshot> _subscription;
  BetaUpdateSnapshot _snapshot;
  bool _checkStarted = false;
  bool _operationPending = false;
  bool _disposed = false;

  BetaUpdateSnapshot get snapshot => _snapshot;
  bool get operationPending => _operationPending;

  /// Shows the real update strip with an explicitly simulated offer.
  ///
  /// A genuine active update is never replaced, and no service method is
  /// called by this developer-only path.
  bool showTestUpdate({required String currentVersion}) {
    if (_disposed || _operationPending) return false;
    final realUpdateActive =
        !_snapshot.testOnly &&
        (_snapshot.phase == BetaUpdatePhase.available ||
            _snapshot.phase == BetaUpdatePhase.downloading ||
            _snapshot.phase == BetaUpdatePhase.ready ||
            _snapshot.phase == BetaUpdatePhase.applying);
    if (realUpdateActive) return false;
    _adopt(
      BetaUpdateSnapshot(
        phase: BetaUpdatePhase.available,
        installed: true,
        portable: false,
        currentVersion: currentVersion,
        targetVersion: 'test-patch',
        sizeBytes: 2610822,
        fullSizeBytes: 66854193,
        deltaCount: 1,
        message: 'Simulated locally; no package will be installed.',
        testOnly: true,
      ),
    );
    return true;
  }

  /// Exercises available -> downloading -> ready using only in-memory state.
  Future<bool> runTestUpdateDemo({
    Duration stepDuration = const Duration(milliseconds: 160),
  }) async {
    if (_disposed ||
        !_snapshot.testOnly ||
        _snapshot.phase != BetaUpdatePhase.available ||
        !_beginOperation()) {
      return false;
    }
    final offer = _snapshot;
    try {
      for (final progress in const <double>[.12, .38, .67, 1]) {
        _adopt(
          offer.copyWith(
            phase: BetaUpdatePhase.downloading,
            progress: progress,
          ),
        );
        await Future<void>.delayed(stepDuration);
        if (_disposed) return false;
      }
      _adopt(offer.copyWith(phase: BetaUpdatePhase.ready, progress: 1));
      await Future<void>.delayed(
        Duration(milliseconds: stepDuration.inMilliseconds * 2),
      );
      if (_disposed) return false;
      _adopt(
        BetaUpdateSnapshot(
          phase: BetaUpdatePhase.upToDate,
          currentVersion: offer.currentVersion,
          installed: true,
          portable: false,
          message: 'The update bar test completed.',
        ),
      );
      return true;
    } finally {
      _finishOperation();
    }
  }

  Future<void> checkOnce() async {
    if (_checkStarted || _disposed) return;
    _checkStarted = true;
    if (!enabled) {
      _adopt(const BetaUpdateSnapshot.paused());
      return;
    }
    if (source.trim().isEmpty) {
      _adopt(const BetaUpdateSnapshot.notConfigured());
      return;
    }
    await _check();
  }

  Future<void> retry() => _check();

  Future<void> _check() async {
    if (_disposed || !enabled || source.trim().isEmpty) return;
    if (_snapshot.phase == BetaUpdatePhase.checking || !_beginOperation()) {
      return;
    }
    try {
      final current = await service.currentStatus();
      if (_disposed) return;
      _adopt(current);
      if (current.phase == BetaUpdatePhase.ready ||
          current.phase == BetaUpdatePhase.applying) {
        return;
      }
      _adopt(await service.checkForUpdates(source.trim()));
    } on Object catch (error) {
      _adopt(_failure(error));
    } finally {
      _finishOperation();
    }
  }

  Future<void> download() async {
    if (_disposed ||
        !enabled ||
        _snapshot.phase != BetaUpdatePhase.available ||
        !_beginOperation()) {
      return;
    }
    try {
      _adopt(await service.downloadUpdate());
    } on Object catch (error) {
      _adopt(_failure(error));
    } finally {
      _finishOperation();
    }
  }

  Future<bool> prepareRestart() async {
    if (_disposed ||
        !enabled ||
        _snapshot.phase != BetaUpdatePhase.ready ||
        !_beginOperation()) {
      return false;
    }
    try {
      _adopt(await service.restartAndApply());
      return _snapshot.phase == BetaUpdatePhase.applying;
    } on Object catch (error) {
      _adopt(_failure(error));
      return false;
    } finally {
      _finishOperation();
    }
  }

  bool _beginOperation() {
    if (_disposed || _operationPending) return false;
    _operationPending = true;
    notifyListeners();
    return true;
  }

  void _finishOperation() {
    if (_disposed || !_operationPending) return;
    _operationPending = false;
    notifyListeners();
  }

  BetaUpdateSnapshot _failure(Object error) {
    final offline = error is PlatformException && error.code == 'offline';
    final message = error is PlatformException
        ? (error.message?.trim().isNotEmpty ?? false)
              ? error.message!.trim()
              : error.code
        : error.toString();
    return _snapshot.withFailure(
      offline ? BetaUpdatePhase.offline : BetaUpdatePhase.error,
      message,
    );
  }

  void _adopt(BetaUpdateSnapshot next) {
    if (_disposed) return;
    _snapshot = next;
    notifyListeners();
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    unawaited(_subscription.cancel());
    super.dispose();
  }
}
