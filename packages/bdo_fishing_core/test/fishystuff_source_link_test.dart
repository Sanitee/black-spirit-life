import 'dart:async';

import 'package:bdo_fishing_core/bdo_fishing_core.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('bdo_gathering/native');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test('source header opens only the fixed HTTPS FishyStuff address', () async {
    final calls = <MethodCall>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return true;
    });
    final link = FishyStuffSourceLink();
    for (final message in <Object?>[
      null,
      'https://fishystuff.fish/map/',
      'javascript:alert(1)',
      'fishystuff:open-source?url=https://example.com',
      {'type': fishyStuffSourceMessage, 'url': 'file:///C:/private'},
    ]) {
      expect(await link.handleMessage(message), isNull);
    }
    expect(calls, isEmpty);
    expect(await link.handleMessage(fishyStuffSourceMessage), isTrue);
    expect(calls, hasLength(1));
    expect(calls.single.method, 'openExternal');
    expect(calls.single.arguments, {'url': 'https://fishystuff.fish/map/'});
  });

  test(
    'repeated clicks share the pending open and allow a later retry',
    () async {
      var calls = 0;
      final pending = Completer<bool>();
      messenger.setMockMethodCallHandler(channel, (_) {
        calls++;
        return calls == 1 ? pending.future : Future.value(true);
      });
      final link = FishyStuffSourceLink();
      final first = link.handleMessage(fishyStuffSourceMessage);
      await Future<void>.delayed(Duration.zero);
      expect(await link.handleMessage(fishyStuffSourceMessage), isNull);
      expect(calls, 1);
      pending.complete(false);
      expect(await first, isFalse);
      expect(await link.handleMessage(fishyStuffSourceMessage), isTrue);
      expect(calls, 2);
    },
  );

  test(
    'launcher errors return a recoverable failure and do not stick busy',
    () async {
      var calls = 0;
      messenger.setMockMethodCallHandler(channel, (_) async {
        calls++;
        if (calls == 1) throw PlatformException(code: 'open_failed');
        return null;
      });
      final link = FishyStuffSourceLink();
      expect(await link.handleMessage(fishyStuffSourceMessage), isFalse);
      expect(await link.handleMessage(fishyStuffSourceMessage), isFalse);
      expect(calls, 2);
    },
  );

  test(
    'anchor bridge keeps standalone behavior and only handles header clicks',
    () {
      expect(
        fishyStuffSourceLinkScript,
        contains('!window.chrome?.webview?.postMessage'),
      );
      expect(fishyStuffSourceLinkScript, contains("addEventListener('click'"));
      expect(
        fishyStuffSourceLinkScript,
        contains("closest('a.brand-icon-link')"),
      );
      expect(
        fishyStuffSourceLinkScript,
        contains("link.href !== '$fishyStuffSourceUrl'"),
      );
      expect(
        fishyStuffSourceLinkScript,
        contains("postMessage('$fishyStuffSourceMessage')"),
      );
      expect(fishyStuffSourceLinkScript, isNot(contains('keydown')));
    },
  );
}
