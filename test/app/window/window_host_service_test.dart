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
    'installing a close guard is ready for an immediate native replay',
    () async {
      final calls = <MethodCall>[];
      final replayApproved = Completer<bool>();
      var guardCalls = 0;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls.add(call);
            if (call.method == 'closeHandlerReady') {
              final response = Completer<ByteData?>();
              await TestDefaultBinaryMessengerBinding
                  .instance
                  .defaultBinaryMessenger
                  .handlePlatformMessage(
                    channel.name,
                    channel.codec.encodeMethodCall(
                      const MethodCall('closeRequested'),
                    ),
                    response.complete,
                  );
              replayApproved.complete(
                channel.codec.decodeEnvelope((await response.future)!) as bool,
              );
            }
            return null;
          });

      service.installCloseRequestHandler(() async {
        guardCalls += 1;
      });

      expect(await replayApproved.future, isTrue);
      expect(guardCalls, 1);
      expect(calls.map((call) => call.method), contains('closeHandlerReady'));
    },
  );

  test(
    'Windows retains only unhandled startup closes and replays them once',
    () {
      final nativeSource = File(
        'windows/runner/flutter_window.cpp',
      ).readAsStringSync().replaceAll('\r\n', '\n');
      final replayBlock = _sourceBetween(
        nativeSource,
        'void FlutterWindow::ReplayDeferredCloseRequest()',
        'bool FlutterWindow::QueueBottomInset',
      );
      expect(
        replayBlock.indexOf('close_requested_before_handler_ = false;'),
        lessThan(replayBlock.indexOf('PostMessage(window, WM_CLOSE, 0, 0)')),
      );
      expect(
        replayBlock,
        contains(
          'if (PostMessage(window, WM_CLOSE, 0, 0) == 0) {\n'
          '    ScheduleDeferredCloseRetry();',
        ),
      );

      final retryBlock = _sourceBetween(
        nativeSource,
        'void FlutterWindow::ScheduleDeferredCloseRetry()',
        'void FlutterWindow::ReplayDeferredCloseRequest()',
      );
      expect(retryBlock, contains('close_requested_before_handler_ = true;'));
      expect(retryBlock, contains('kDeferredCloseRetryLimit'));
      expect(
        retryBlock,
        contains(
          'SetTimer(window, kDeferredCloseRetryTimerId, delay, nullptr)',
        ),
      );

      final readyBlock = _sourceBetween(
        nativeSource,
        'call.method_name() == "closeHandlerReady"',
        'call.method_name() == "requestClose"',
      );
      expect(readyBlock, contains('close_handler_generation_ += 1;'));
      expect(readyBlock, contains('ReplayDeferredCloseRequest();'));

      final channelRegistration = _sourceBetween(
        nativeSource,
        'window_channel_->SetMethodCallHandler(',
        'flutter_view_window_ =',
      );
      expect(
        channelRegistration.trimRight(),
        endsWith('ReplayDeferredCloseRequest();'),
      );

      final closeBlock = _sourceBetween(
        nativeSource,
        'case WM_CLOSE:',
        'case kApplyBottomInsetMessage:',
      );
      expect(closeBlock, isNot(contains('dart_close_handler_ready_')));
      expect(
        closeBlock,
        contains(
          'if (window_channel_ == nullptr) {\n'
          '        ScheduleDeferredCloseRetry();',
        ),
      );
      expect(
        nativeSource.indexOf('case WM_CLOSE:'),
        lessThan(nativeSource.indexOf('HandleTopLevelWindowProc(')),
      );
      expect(
        closeBlock.indexOf('close_requested_before_handler_ = false;'),
        lessThan(closeBlock.indexOf('window_channel_->InvokeMethod(')),
      );

      final successCallback = _sourceBetween(
        closeBlock,
        '[this](const flutter::EncodableValue* result)',
        '[this](const std::string&, const std::string&,',
      );
      expect(
        successCallback,
        contains('approved == nullptr || !*approved || GetHandle() == nullptr'),
      );
      expect(successCallback, contains('native_close_allowed_ = true;'));
      expect(
        successCallback,
        contains('PostMessage(GetHandle(), WM_CLOSE, 0, 0)'),
      );
      expect(
        successCallback,
        isNot(contains('close_requested_before_handler_')),
      );
      expect(successCallback, isNot(contains('ReplayDeferredCloseRequest')));
      expect(successCallback, isNot(contains('ScheduleDeferredCloseRetry')));

      final errorCallback = _sourceBetween(
        closeBlock,
        '[this](const std::string&, const std::string&,',
        '[this, close_handler_generation]()',
      );
      expect(errorCallback, contains('close_request_pending_ = false;'));
      expect(errorCallback, isNot(contains('close_requested_before_handler_')));
      expect(errorCallback, isNot(contains('ReplayDeferredCloseRequest')));
      expect(errorCallback, isNot(contains('ScheduleDeferredCloseRetry')));

      final unhandledCallback = _sourceBetween(
        closeBlock,
        '[this, close_handler_generation]()',
        '}));',
      );
      expect(unhandledCallback, contains('ScheduleDeferredCloseRetry();'));
      expect(
        unhandledCallback,
        contains('close_handler_generation_ != close_handler_generation'),
      );
      expect(unhandledCallback, contains('ReplayDeferredCloseRequest();'));
      expect(
        closeBlock,
        contains(
          'case WM_TIMER:\n'
          '      if (wparam == kDeferredCloseRetryTimerId)',
        ),
      );
      final destroyBlock = _sourceBetween(
        nativeSource,
        'void FlutterWindow::OnDestroy()',
        'FlutterWindow::MessageHandler',
      );
      expect(destroyBlock, contains('CancelDeferredCloseRetry();'));
    },
  );

  test('startup close waits for the installed Fish teardown', () async {
    final gate = Completer<void>();
    installStartupWindowCloseHandler(
      windowHost: service,
      beforeClose: () => gate.future,
    );

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
  });

  test('startup caption close uses the guarded native request', () async {
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          return null;
        });

    await service.requestClose();

    expect(calls, hasLength(1));
    expect(calls.single.method, 'requestClose');
    expect(
      File('windows/runner/flutter_window.cpp').readAsStringSync(),
      contains('call.method_name() == "requestClose"'),
    );
    final bootstrap = File('lib/app/bootstrap.dart').readAsStringSync();
    expect(
      bootstrap.indexOf(
        'beforeClose: '
        'fishCompanionRuntimeHost.freezeAndFlushForApplicationExit',
      ),
      lessThan(bootstrap.indexOf('fishCompanionRuntimeHost.prewarm()')),
    );
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

String _sourceBetween(String source, String start, String end) {
  final startIndex = source.indexOf(start);
  expect(startIndex, isNonNegative, reason: 'Missing source marker: $start');
  final endIndex = source.indexOf(end, startIndex + start.length);
  expect(endIndex, isNonNegative, reason: 'Missing source marker: $end');
  return source.substring(startIndex, endIndex);
}
