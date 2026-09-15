import 'dart:async';
import 'dart:io';

import 'package:bdo_gathering_companion/bdo_gathering_companion.dart';
import 'package:bdo_gathering_companion/domain/models.dart';
import 'package:bdo_gathering_companion/src/services/native_bridge.dart';
import 'package:bdo_gathering_companion/services/session_store.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _nativeChannel = MethodChannel('bdo_gathering/native');

GatheringSession _session(String id) => GatheringSession(
  id: id,
  createdAt: DateTime.utc(2026, 9, 15),
  methodId: 'mining',
  methodLabel: 'Mining',
  methodIcon: '',
  spotId: 'synthetic',
  spotName: 'Synthetic fixture',
  durationSeconds: 60,
  loot: const [],
  buffs: const [],
  buffTotals: const {},
  catalogDate: '2026-09-15',
);

class _BlockingStore extends SessionStore {
  _BlockingStore(Directory directory) : super(directory: directory);

  final enteredSave = Completer<void>();
  final allowSave = Completer<void>();

  @override
  Future<void> save() async {
    if (!enteredSave.isCompleted) enteredSave.complete();
    await allowSave.future;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'freeze rejects new mutations and waits for accepted serialized work',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'gathering-freeze-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final store = _BlockingStore(directory);
      final events = <String>[];
      final controller = GatheringDurabilityController()
        ..attach(
          store: store,
          releaseTransientResources: () async => events.add('release'),
          resumeTransientResources: () async => events.add('resume'),
        );

      final accepted = store.upsert(_session('accepted'));
      await store.enteredSave.future;
      var finished = false;
      final freezing = controller.freezeAndFlush().then((_) => finished = true);
      await Future<void>.delayed(Duration.zero);
      expect(controller.isFrozen, isTrue);
      expect(store.mutationsFrozen, isTrue);
      expect(events, ['release']);
      expect(finished, isFalse);
      expect(() => store.upsert(_session('rejected')), throwsStateError);

      store.allowSave.complete();
      await accepted;
      await freezing;
      expect(store.sessions.map((session) => session.id), ['accepted']);

      await controller.resume();
      expect(controller.isFrozen, isFalse);
      expect(store.mutationsFrozen, isFalse);
      expect(events, ['release', 'resume']);
    },
  );

  test('flush propagates the last durable-write failure', () async {
    final root = await Directory.systemTemp.createTemp('gathering-failure-');
    addTearDown(() => root.delete(recursive: true));
    final blocker = File(
      '${root.path}${Platform.pathSeparator}not-a-directory',
    );
    await blocker.writeAsString('fixture');
    final store = SessionStore(directory: Directory(blocker.path));
    final controller = GatheringDurabilityController()..attach(store: store);

    await expectLater(
      store.upsert(_session('failed')),
      throwsA(isA<FileSystemException>()),
    );
    await expectLater(controller.flush(), throwsA(isA<FileSystemException>()));
  });

  test(
    'freeze awaits native helper shutdown before confirming durability',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'gathering-lifecycle-',
      );
      addTearDown(() => root.delete(recursive: true));
      final controller = GatheringDurabilityController();
      final shutdownEntered = Completer<void>();
      final allowShutdown = Completer<void>();
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(_nativeChannel, (call) async {
        expect(call.method, 'shutdownSessionImport');
        if (!shutdownEntered.isCompleted) shutdownEntered.complete();
        await allowShutdown.future;
        return true;
      });
      addTearDown(
        () => messenger.setMockMethodCallHandler(_nativeChannel, null),
      );
      controller.attach(
        store: SessionStore(directory: root),
        releaseTransientResources: NativeBridge.shutdownSessionImport,
      );

      var finished = false;
      final freezing = Future<void>(() async {
        await controller.freezeAndFlush();
        finished = true;
      });
      await shutdownEntered.future;
      expect(controller.isFrozen, isTrue);
      expect(finished, isFalse);
      allowShutdown.complete();
      await freezing;
      expect(finished, isTrue);
    },
  );

  test(
    'native shutdown rejection propagates and leaves mutations frozen',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'gathering-shutdown-rejected-',
      );
      addTearDown(() => root.delete(recursive: true));
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(_nativeChannel, (_) async => false);
      addTearDown(
        () => messenger.setMockMethodCallHandler(_nativeChannel, null),
      );
      final store = SessionStore(directory: root);
      final controller = GatheringDurabilityController()
        ..attach(
          store: store,
          releaseTransientResources: NativeBridge.shutdownSessionImport,
        );

      await expectLater(
        controller.freezeAndFlush(),
        throwsA(isA<StateError>()),
      );
      expect(controller.isFrozen, isTrue);
      expect(store.mutationsFrozen, isTrue);
    },
  );
}
