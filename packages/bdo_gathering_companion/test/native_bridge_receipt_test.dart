import 'package:bdo_gathering_companion/src/services/native_bridge.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('bdo_gathering/native');
  final calls = <MethodCall>[];
  setUp(() {
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          return true;
        });
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });
  test(
    'ordinary launch explicitly hands native only the selected local inbox',
    () async {
      expect(
        await NativeBridge.openSessionImport(
          receiptDirectory: r'C:\isolated test\gathering\session-import-inbox',
        ),
        true,
      );
      expect(calls.single.method, 'openSessionImport');
      expect(calls.single.arguments, {
        'receiptDirectory': r'C:\isolated test\gathering\session-import-inbox',
      });
    },
  );
  test(
    'durability shutdown is awaited and requires native confirmation',
    () async {
      await NativeBridge.shutdownSessionImport();
      expect(calls.single.method, 'shutdownSessionImport');

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async => false);
      await expectLater(
        NativeBridge.shutdownSessionImport(),
        throwsA(isA<StateError>()),
      );
    },
  );

  test('missing lifecycle method is safe for an older host', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    await expectLater(NativeBridge.shutdownSessionImport(), completes);
  });

  test('missing lifecycle method fails after a helper was launched', () async {
    expect(
      await NativeBridge.openSessionImport(
        receiptDirectory: r'C:\isolated test\gathering\session-import-inbox',
      ),
      isTrue,
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    await expectLater(
      NativeBridge.shutdownSessionImport(),
      throwsA(isA<StateError>()),
    );

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async => true);
    await NativeBridge.shutdownSessionImport();
  });
}
