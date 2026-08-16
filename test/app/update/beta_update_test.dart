import 'dart:async';

import 'package:bdo_craft_planner_flutter/app/update/beta_update.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('BetaUpdateSnapshot', () {
    test('decodes the native contract and clamps progress', () {
      final snapshot = BetaUpdateSnapshot.fromMap(<String, Object?>{
        'status': 'available',
        'installed': true,
        'portable': false,
        'currentVersion': '0.1.0-beta.1',
        'appId': 'com.example.blackspiritlife.beta',
        'targetVersion': '0.1.0-beta.2',
        'releaseNotesMarkdown': 'Private test notes',
        'downloadSizeBytes': 4096,
        'fullSizeBytes': 65536,
        'deltaCount': 1,
        'progress': 4.2,
        'message': 'Ready to download.',
      });

      expect(snapshot.phase, BetaUpdatePhase.available);
      expect(snapshot.installed, isTrue);
      expect(snapshot.portable, isFalse);
      expect(snapshot.currentVersion, '0.1.0-beta.1');
      expect(snapshot.targetVersion, '0.1.0-beta.2');
      expect(snapshot.sizeBytes, 4096);
      expect(snapshot.fullSizeBytes, 65536);
      expect(snapshot.deltaCount, 1);
      expect(snapshot.usesDelta, isTrue);
      expect(snapshot.progress, 1);
      expect(snapshot.showsIndicator, isTrue);
      expect(snapshot.testOnly, isFalse);
    });

    test('unknown native phases remain safely idle and hidden', () {
      final snapshot = BetaUpdateSnapshot.fromMap(<String, Object?>{
        'status': 'futureState',
      });

      expect(snapshot.phase, BetaUpdatePhase.idle);
      expect(snapshot.showsIndicator, isFalse);
    });

    test('only an available or active update shows the update strip', () {
      for (final phase in <BetaUpdatePhase>[
        BetaUpdatePhase.idle,
        BetaUpdatePhase.checking,
        BetaUpdatePhase.upToDate,
        BetaUpdatePhase.offline,
        BetaUpdatePhase.error,
        BetaUpdatePhase.unsupported,
        BetaUpdatePhase.notConfigured,
      ]) {
        expect(
          BetaUpdateSnapshot(phase: phase).showsIndicator,
          isFalse,
          reason: '${phase.name} without a known update must stay silent',
        );
      }

      for (final phase in <BetaUpdatePhase>[
        BetaUpdatePhase.available,
        BetaUpdatePhase.downloading,
        BetaUpdatePhase.ready,
        BetaUpdatePhase.applying,
      ]) {
        expect(
          BetaUpdateSnapshot(phase: phase).showsIndicator,
          isTrue,
          reason: '${phase.name} is part of an active update',
        );
      }

      expect(
        const BetaUpdateSnapshot(
          phase: BetaUpdatePhase.error,
          targetVersion: '0.1.1',
        ).showsIndicator,
        isFalse,
        reason: 'Failures use non-strip feedback even for a known update',
      );
    });
  });

  group('BetaUpdateSource', () {
    test('prefers a compiled private source over the process environment', () {
      expect(
        BetaUpdateSource.resolve(
          compiledValue: r' C:\private-feed ',
          process: const <String, String>{
            BetaUpdateSource.environmentKey: r'C:\other-feed',
          },
        ),
        r'C:\private-feed',
      );
    });

    test('uses the private process override when no source is compiled', () {
      expect(
        BetaUpdateSource.resolve(
          compiledValue: '',
          process: const <String, String>{
            BetaUpdateSource.environmentKey: r' C:\local-beta-feed ',
          },
        ),
        r'C:\local-beta-feed',
      );
    });
  });

  group('BetaUpdateController', () {
    test('disabled controller ignores every updater operation', () async {
      final service = _FakeBetaUpdateService(
        checkResult: const BetaUpdateSnapshot(phase: BetaUpdatePhase.available),
      );
      final controller = BetaUpdateController(
        service: service,
        source: r'C:\private-feed',
        enabled: false,
      );

      await controller.checkOnce();
      await controller.retry();
      await controller.download();
      expect(await controller.prepareRestart(), isFalse);

      expect(controller.snapshot.phase, BetaUpdatePhase.unsupported);
      expect(controller.snapshot.showsIndicator, isFalse);
      expect(service.currentStatusCalls, 0);
      expect(service.checkCalls, 0);
      expect(service.downloadCalls, 0);
      expect(service.applyCalls, 0);
      controller.dispose();
      await service.dispose();
    });

    test('developer update demo never invokes the updater service', () async {
      final service = _FakeBetaUpdateService();
      final controller = BetaUpdateController(
        service: service,
        source: '',
        enabled: false,
      );
      final phases = <BetaUpdatePhase>[];
      controller.addListener(() => phases.add(controller.snapshot.phase));

      expect(controller.showTestUpdate(currentVersion: '0.1.0-beta.6'), isTrue);
      expect(controller.snapshot.phase, BetaUpdatePhase.available);
      expect(controller.snapshot.testOnly, isTrue);
      expect(
        await controller.runTestUpdateDemo(stepDuration: Duration.zero),
        isTrue,
      );

      expect(phases, contains(BetaUpdatePhase.downloading));
      expect(phases, contains(BetaUpdatePhase.ready));
      expect(controller.snapshot.phase, BetaUpdatePhase.upToDate);
      expect(controller.snapshot.testOnly, isFalse);
      expect(service.currentStatusCalls, 0);
      expect(service.checkCalls, 0);
      expect(service.downloadCalls, 0);
      expect(service.applyCalls, 0);
      controller.dispose();
      await service.dispose();
    });

    test(
      'does not call native code when no private source is configured',
      () async {
        final service = _FakeBetaUpdateService();
        final controller = BetaUpdateController(service: service, source: '');

        await controller.checkOnce();
        await controller.checkOnce();

        expect(controller.snapshot.phase, BetaUpdatePhase.notConfigured);
        expect(service.currentStatusCalls, 0);
        expect(service.checkCalls, 0);
        controller.dispose();
        await service.dispose();
      },
    );

    test(
      'checks exactly once automatically and caches session state',
      () async {
        final service = _FakeBetaUpdateService(
          checkResult: const BetaUpdateSnapshot(
            phase: BetaUpdatePhase.checking,
            message: 'Checking.',
          ),
        );
        final controller = BetaUpdateController(
          service: service,
          source: r'C:\private-feed',
        );

        await controller.checkOnce();
        await controller.checkOnce();
        service.emit(
          const BetaUpdateSnapshot(
            phase: BetaUpdatePhase.available,
            currentVersion: '0.1.0-beta.1',
            targetVersion: '0.1.0-beta.2',
          ),
        );

        expect(service.currentStatusCalls, 1);
        expect(service.checkCalls, 1);
        expect(service.lastSource, r'C:\private-feed');
        expect(controller.snapshot.phase, BetaUpdatePhase.available);
        controller.dispose();
        await service.dispose();
      },
    );

    test('a downloaded pending update skips another feed check', () async {
      final service = _ReadyStatusUpdateService();
      final controller = BetaUpdateController(
        service: service,
        source: r'C:\private-feed',
      );

      await controller.checkOnce();

      expect(controller.snapshot.phase, BetaUpdatePhase.ready);
      expect(service.currentStatusCalls, 1);
      expect(service.checkCalls, 0);
      controller.dispose();
      await service.dispose();
    });

    test('tracks download progress and only applies a ready update', () async {
      final service = _FakeBetaUpdateService(
        checkResult: const BetaUpdateSnapshot(
          phase: BetaUpdatePhase.available,
          targetVersion: '0.1.0-beta.2',
        ),
        downloadResult: const BetaUpdateSnapshot(
          phase: BetaUpdatePhase.downloading,
          targetVersion: '0.1.0-beta.2',
        ),
        applyResult: const BetaUpdateSnapshot(
          phase: BetaUpdatePhase.applying,
          targetVersion: '0.1.0-beta.2',
        ),
      );
      final controller = BetaUpdateController(
        service: service,
        source: r'C:\private-feed',
      );

      expect(await controller.prepareRestart(), isFalse);
      await controller.checkOnce();
      await controller.download();
      service.emit(
        const BetaUpdateSnapshot(
          phase: BetaUpdatePhase.downloading,
          targetVersion: '0.1.0-beta.2',
          progress: .62,
        ),
      );
      expect(controller.snapshot.progress, .62);
      expect(await controller.prepareRestart(), isFalse);

      service.emit(
        const BetaUpdateSnapshot(
          phase: BetaUpdatePhase.ready,
          targetVersion: '0.1.0-beta.2',
          progress: 1,
        ),
      );
      expect(await controller.prepareRestart(), isTrue);
      expect(service.downloadCalls, 1);
      expect(service.applyCalls, 1);
      controller.dispose();
      await service.dispose();
    });

    test('startup check failures become nonblocking hidden state', () async {
      final service = _FakeBetaUpdateService(
        checkError: PlatformException(
          code: 'offline',
          message: 'The private source is offline.',
        ),
      );
      final controller = BetaUpdateController(
        service: service,
        source: 'https://private.invalid/beta',
      );

      await controller.checkOnce();

      expect(controller.snapshot.phase, BetaUpdatePhase.offline);
      expect(controller.snapshot.message, contains('offline'));
      expect(controller.snapshot.showsIndicator, isFalse);
      controller.dispose();
      await service.dispose();
    });

    test('serializes download and restart operations', () async {
      final service = _DeferredActionUpdateService();
      final controller = BetaUpdateController(
        service: service,
        source: r'C:\private-feed',
      );

      await controller.checkOnce();
      final firstDownload = controller.download();
      final secondDownload = controller.download();
      expect(controller.operationPending, isTrue);
      expect(service.downloadCalls, 1);
      service.completeDownload();
      await Future.wait(<Future<void>>[firstDownload, secondDownload]);
      expect(controller.operationPending, isFalse);

      service.emit(_DeferredActionUpdateService.ready);
      final firstApply = controller.prepareRestart();
      final secondApply = controller.prepareRestart();
      expect(controller.operationPending, isTrue);
      expect(service.applyCalls, 1);
      expect(await secondApply, isFalse);
      service.completeApply();
      expect(await firstApply, isTrue);
      expect(controller.operationPending, isFalse);

      controller.dispose();
      await service.dispose();
    });

    test('does not continue a deferred check after disposal', () async {
      final service = _DeferredStatusUpdateService();
      final controller = BetaUpdateController(
        service: service,
        source: r'C:\private-feed',
      );

      final check = controller.checkOnce();
      expect(service.currentStatusCalls, 1);
      controller.dispose();
      service.completeCurrentStatus();
      await check;

      expect(service.checkCalls, 0);
      await service.dispose();
    });
  });

  group('NativeBetaUpdateService', () {
    const channel = MethodChannel('com.blackspiritlife/updates');
    final calls = <MethodCall>[];

    setUp(() {
      calls.clear();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls.add(call);
            return <String, Object?>{
              'status': call.method == 'restartAndApply'
                  ? 'applying'
                  : call.method == 'downloadUpdate'
                  ? 'downloading'
                  : 'checking',
              'portable': false,
              'installed': true,
            };
          });
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    test(
      'uses the private update bridge methods and decodes callbacks',
      () async {
        final service = NativeBetaUpdateService(channel: channel);
        final events = <BetaUpdateSnapshot>[];
        final subscription = service.snapshots.listen(events.add);

        await service.currentStatus();
        await service.checkForUpdates(r'C:\private-feed');
        await service.downloadUpdate();
        await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .handlePlatformMessage(
              channel.name,
              channel.codec.encodeMethodCall(
                const MethodCall('statusChanged', <String, Object?>{
                  'status': 'ready',
                  'targetVersion': '0.1.0-beta.2',
                  'progress': 1.0,
                }),
              ),
              (_) {},
            );
        await service.restartAndApply();

        expect(calls.map((call) => call.method), <String>[
          'getUpdateStatus',
          'checkForUpdates',
          'downloadUpdate',
          'restartAndApply',
        ]);
        expect(
          (calls[1].arguments as Map<Object?, Object?>)['source'],
          r'C:\private-feed',
        );
        expect(
          events,
          contains(
            predicate<BetaUpdateSnapshot>((snapshot) {
              return snapshot.phase == BetaUpdatePhase.ready &&
                  snapshot.targetVersion == '0.1.0-beta.2';
            }),
          ),
        );

        await subscription.cancel();
        await service.dispose();
      },
    );
  });
}

class _DeferredActionUpdateService implements BetaUpdateService {
  final StreamController<BetaUpdateSnapshot> _controller =
      StreamController<BetaUpdateSnapshot>.broadcast(sync: true);
  final Completer<BetaUpdateSnapshot> _download =
      Completer<BetaUpdateSnapshot>();
  final Completer<BetaUpdateSnapshot> _apply = Completer<BetaUpdateSnapshot>();
  int downloadCalls = 0;
  int applyCalls = 0;

  static const available = BetaUpdateSnapshot(
    phase: BetaUpdatePhase.available,
    targetVersion: '0.1.0-beta.2',
  );
  static const ready = BetaUpdateSnapshot(
    phase: BetaUpdatePhase.ready,
    targetVersion: '0.1.0-beta.2',
    progress: 1,
  );

  @override
  Stream<BetaUpdateSnapshot> get snapshots => _controller.stream;

  void emit(BetaUpdateSnapshot snapshot) => _controller.add(snapshot);

  void completeDownload() => _download.complete(
    const BetaUpdateSnapshot(
      phase: BetaUpdatePhase.downloading,
      targetVersion: '0.1.0-beta.2',
    ),
  );

  void completeApply() => _apply.complete(
    const BetaUpdateSnapshot(
      phase: BetaUpdatePhase.applying,
      targetVersion: '0.1.0-beta.2',
    ),
  );

  @override
  Future<BetaUpdateSnapshot> currentStatus() async =>
      const BetaUpdateSnapshot();

  @override
  Future<BetaUpdateSnapshot> checkForUpdates(String source) async => available;

  @override
  Future<BetaUpdateSnapshot> downloadUpdate() {
    downloadCalls += 1;
    return _download.future;
  }

  @override
  Future<BetaUpdateSnapshot> restartAndApply() {
    applyCalls += 1;
    return _apply.future;
  }

  @override
  Future<void> dispose() => _controller.close();
}

class _ReadyStatusUpdateService implements BetaUpdateService {
  final StreamController<BetaUpdateSnapshot> _controller =
      StreamController<BetaUpdateSnapshot>.broadcast(sync: true);
  int currentStatusCalls = 0;
  int checkCalls = 0;

  @override
  Stream<BetaUpdateSnapshot> get snapshots => _controller.stream;

  @override
  Future<BetaUpdateSnapshot> currentStatus() async {
    currentStatusCalls += 1;
    return const BetaUpdateSnapshot(
      phase: BetaUpdatePhase.ready,
      targetVersion: '0.1.0-beta.2',
    );
  }

  @override
  Future<BetaUpdateSnapshot> checkForUpdates(String source) async {
    checkCalls += 1;
    return const BetaUpdateSnapshot(phase: BetaUpdatePhase.available);
  }

  @override
  Future<BetaUpdateSnapshot> downloadUpdate() async =>
      const BetaUpdateSnapshot(phase: BetaUpdatePhase.ready);

  @override
  Future<BetaUpdateSnapshot> restartAndApply() async =>
      const BetaUpdateSnapshot(phase: BetaUpdatePhase.applying);

  @override
  Future<void> dispose() => _controller.close();
}

class _DeferredStatusUpdateService implements BetaUpdateService {
  final StreamController<BetaUpdateSnapshot> _controller =
      StreamController<BetaUpdateSnapshot>.broadcast(sync: true);
  final Completer<BetaUpdateSnapshot> _current =
      Completer<BetaUpdateSnapshot>();
  int currentStatusCalls = 0;
  int checkCalls = 0;

  @override
  Stream<BetaUpdateSnapshot> get snapshots => _controller.stream;

  void completeCurrentStatus() => _current.complete(const BetaUpdateSnapshot());

  @override
  Future<BetaUpdateSnapshot> currentStatus() {
    currentStatusCalls += 1;
    return _current.future;
  }

  @override
  Future<BetaUpdateSnapshot> checkForUpdates(String source) async {
    checkCalls += 1;
    return const BetaUpdateSnapshot(phase: BetaUpdatePhase.upToDate);
  }

  @override
  Future<BetaUpdateSnapshot> downloadUpdate() async =>
      const BetaUpdateSnapshot(phase: BetaUpdatePhase.downloading);

  @override
  Future<BetaUpdateSnapshot> restartAndApply() async =>
      const BetaUpdateSnapshot(phase: BetaUpdatePhase.applying);

  @override
  Future<void> dispose() => _controller.close();
}

class _FakeBetaUpdateService implements BetaUpdateService {
  _FakeBetaUpdateService({
    this.checkResult = const BetaUpdateSnapshot(
      phase: BetaUpdatePhase.upToDate,
    ),
    this.downloadResult = const BetaUpdateSnapshot(
      phase: BetaUpdatePhase.downloading,
    ),
    this.applyResult = const BetaUpdateSnapshot(
      phase: BetaUpdatePhase.applying,
    ),
    this.checkError,
  });

  final StreamController<BetaUpdateSnapshot> _controller =
      StreamController<BetaUpdateSnapshot>.broadcast(sync: true);
  final BetaUpdateSnapshot checkResult;
  final BetaUpdateSnapshot downloadResult;
  final BetaUpdateSnapshot applyResult;
  final Object? checkError;
  int currentStatusCalls = 0;
  int checkCalls = 0;
  int downloadCalls = 0;
  int applyCalls = 0;
  String? lastSource;

  @override
  Stream<BetaUpdateSnapshot> get snapshots => _controller.stream;

  void emit(BetaUpdateSnapshot snapshot) => _controller.add(snapshot);

  @override
  Future<BetaUpdateSnapshot> currentStatus() async {
    currentStatusCalls += 1;
    return const BetaUpdateSnapshot();
  }

  @override
  Future<BetaUpdateSnapshot> checkForUpdates(String source) async {
    checkCalls += 1;
    lastSource = source;
    if (checkError case final error?) throw error;
    return checkResult;
  }

  @override
  Future<BetaUpdateSnapshot> downloadUpdate() async {
    downloadCalls += 1;
    return downloadResult;
  }

  @override
  Future<BetaUpdateSnapshot> restartAndApply() async {
    applyCalls += 1;
    return applyResult;
  }

  @override
  Future<void> dispose() => _controller.close();
}
