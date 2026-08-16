import 'package:bdo_craft_planner_flutter/app/window/native_clipboard_image_reader.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('com.bdocraftplanner.flutter/window');

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('returns PNG bytes from the native clipboard contract', () async {
    final calls = <MethodCall>[];
    final expected = Uint8List.fromList(<int>[137, 80, 78, 71, 13, 10, 26, 10]);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          return expected;
        });

    const reader = NativeClipboardImageReader();
    expect(await reader(), expected);
    expect(calls, hasLength(1));
    expect(calls.single.method, 'readClipboardImagePng');
    expect(calls.single.arguments, isNull);
  });

  test('returns null when the clipboard does not contain an image', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async => null);

    expect(await const NativeClipboardImageReader().readPng(), isNull);
  });

  test(
    'returns null when the native clipboard bridge is unavailable',
    () async {
      expect(await const NativeClipboardImageReader().readPng(), isNull);
    },
  );

  test('rejects an image above the configured import limit', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          channel,
          (_) async => Uint8List.fromList(<int>[1, 2, 3, 4]),
        );

    const reader = NativeClipboardImageReader(maximumBytes: 3);
    await expectLater(reader.readPng(), throwsA(isA<FormatException>()));
  });
}
