import 'dart:async';
import 'dart:io';

import 'package:bdo_craft_planner_flutter/app/bootstrap.dart';
import 'package:bdo_craft_planner_flutter/app/window/window_host_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('com.bdocraftplanner.flutter/window');
  const service = WindowHostService(
    closeFlushTimeout: Duration(milliseconds: 20),
  );

  tearDown(() {
    service.removeCloseRequestHandler();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('bottom inset is sent as a bounded logical-pixel request', () async {
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          return null;
        });

    await service.setBottomInset(44);
    await service.setBottomInset(200);

    expect(calls, hasLength(2));
    expect(calls.first.method, 'setBottomInset');
    expect(calls.first.arguments, <String, Object?>{'logicalPixels': 44.0});
    expect(calls.last.arguments, <String, Object?>{'logicalPixels': 96.0});
  });

  test('Windows reports a failed programmatic close queue request', () {
    final source = File('windows/runner/flutter_window.cpp').readAsStringSync();

    expect(source, contains('if (PostMessage(window, WM_CLOSE, 0, 0) == 0)'));
    expect(source, contains('native_close_allowed_ = false;'));
    expect(source, contains('result->Error("window_close_failed"'));
    expect(
      source,
      contains('if (PostMessage(GetHandle(), WM_CLOSE, 0, 0) == 0)'),
    );
  });

  test('startup surfaces approve close before the workspace mounts', () async {
    installStartupWindowCloseHandler(windowHost: service);

    final completer = Completer<ByteData?>();
    await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage(
          channel.name,
          channel.codec.encodeMethodCall(const MethodCall('closeRequested')),
          completer.complete,
        );
    final envelope = await completer.future;

    expect(channel.codec.decodeEnvelope(envelope!), isTrue);
  });

  test(
    'native close request waits for the installed persistence callback',
    () async {
      final gate = Completer<void>();
      service.installCloseRequestHandler(() => gate.future);

      final response = TestDefaultBinaryMessengerBinding
          .instance
          .defaultBinaryMessenger
          .handlePlatformMessage(
            channel.name,
            channel.codec.encodeMethodCall(const MethodCall('closeRequested')),
            (data) {},
          );

      await Future<void>.delayed(Duration.zero);
      expect(gate.isCompleted, isFalse);
      gate.complete();
      await response;
    },
  );

  test('native close request surfaces a failed persistence callback', () async {
    service.installCloseRequestHandler(
      () => Future<void>.error(StateError('save failed')),
    );

    final completer = Completer<ByteData?>();
    await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage(
          channel.name,
          channel.codec.encodeMethodCall(const MethodCall('closeRequested')),
          completer.complete,
        );
    final envelope = await completer.future;
    expect(
      () => channel.codec.decodeEnvelope(envelope!),
      throwsA(isA<PlatformException>()),
    );
  });

  test('native close request has a bounded save wait', () async {
    service.installCloseRequestHandler(() => Completer<void>().future);

    final completer = Completer<ByteData?>();
    await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage(
          channel.name,
          channel.codec.encodeMethodCall(const MethodCall('closeRequested')),
          completer.complete,
        );
    final envelope = await completer.future.timeout(
      service.closeFlushTimeout + const Duration(seconds: 1),
    );
    expect(
      () => channel.codec.decodeEnvelope(envelope!),
      throwsA(isA<PlatformException>()),
    );
  });
}
