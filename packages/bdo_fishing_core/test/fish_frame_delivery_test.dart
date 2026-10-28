import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webview_flutter_windows/webview_flutter_windows.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const plugin = MethodChannel('io.jns.webview.win');
  const instance = MethodChannel('io.jns.webview.win/73');
  const events = MethodChannel('io.jns.webview.win/73/events');
  final calls = <MethodCall>[];
  final pluginCalls = <MethodCall>[];

  setUp(() {
    calls.clear();
    pluginCalls.clear();
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(plugin, (call) async {
      pluginCalls.add(call);
      return call.method == 'initialize' ? {'textureId': 73} : null;
    });
    messenger.setMockMethodCallHandler(instance, (call) async {
      calls.add(call);
      return null;
    });
    messenger.setMockMethodCallHandler(events, (_) async => null);
  });

  tearDown(() {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    for (final channel in [plugin, instance, events]) {
      messenger.setMockMethodCallHandler(channel, null);
    }
  });

  Widget host(
    WebviewController controller, {
    required bool visible,
    bool pause = true,
    Size size = const Size(800, 600),
  }) => MaterialApp(
    home: Offstage(
      offstage: !visible,
      child: TickerMode(
        enabled: visible,
        child: Align(
          child: SizedBox.fromSize(
            size: size,
            child: Webview(
              controller,
              key: const ValueKey('retained-fish'),
              pauseFrameDeliveryWhenOffstage: pause,
            ),
          ),
        ),
      ),
    ),
  );

  List<bool> deliveryCalls() => calls
      .where((call) => call.method == 'setFrameDeliveryEnabled')
      .map((call) => call.arguments as bool)
      .toList();

  testWidgets('hidden mount disables capture before initial sizing', (
    tester,
  ) async {
    final controller = WebviewController();
    await tester.runAsync(controller.initialize);
    await tester.pumpWidget(host(controller, visible: false));
    await tester.pump();
    expect(deliveryCalls(), [false]);
    final disableIndex = calls.indexWhere(
      (call) => call.method == 'setFrameDeliveryEnabled',
    );
    final sizeIndex = calls.indexWhere((call) => call.method == 'setSize');
    expect(sizeIndex, greaterThan(disableIndex));
    expect(calls.where((call) => call.method == 'suspend'), isEmpty);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.runAsync(controller.dispose);
  });

  testWidgets('tab changes retain page and texture; idle rebuilds stay quiet', (
    tester,
  ) async {
    final controller = WebviewController();
    await tester.runAsync(controller.initialize);
    await tester.pumpWidget(host(controller, visible: false));
    final state = tester.state(find.byType(Webview, skipOffstage: false));
    await tester.pumpWidget(host(controller, visible: true));
    final texture = tester.widget<Texture>(find.byType(Texture));
    expect(texture.textureId, 73);
    await tester.pumpWidget(host(controller, visible: false));
    await tester.pumpWidget(host(controller, visible: true));
    await tester.pumpWidget(host(controller, visible: true));
    await tester.pump(const Duration(seconds: 5));
    expect(deliveryCalls(), [false, true, false, true]);
    expect(tester.state(find.byType(Webview)), same(state));
    expect(tester.widget<Texture>(find.byType(Texture)).textureId, 73);
    expect(
      pluginCalls.where((call) => call.method == 'initialize'),
      hasLength(1),
    );
    expect(
      calls.where(
        (call) =>
            ['suspend', 'resume', 'loadUrl', 'reload'].contains(call.method),
      ),
      isEmpty,
    );
    expect(tester.binding.hasScheduledFrame, isFalse);
    await tester.pumpWidget(const SizedBox.shrink());
    expect(deliveryCalls().last, isFalse);
    await tester.runAsync(controller.dispose);
  });

  testWidgets('hidden size changes do not request frame delivery', (
    tester,
  ) async {
    final controller = WebviewController();
    await tester.runAsync(controller.initialize);
    await tester.pumpWidget(host(controller, visible: false));
    await tester.pumpWidget(
      host(controller, visible: false, size: const Size(500, 400)),
    );
    await tester.pump();
    expect(deliveryCalls(), [false]);
    final sizes = calls
        .where((call) => call.method == 'setSize')
        .map((call) => call.arguments)
        .toList();
    expect(
      sizes,
      containsAllInOrder([
        [800.0, 600.0, tester.view.devicePixelRatio],
        [500.0, 400.0, tester.view.devicePixelRatio],
      ]),
    );
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.runAsync(controller.dispose);
  });

  testWidgets('other Webview hosts retain their default capture behavior', (
    tester,
  ) async {
    final controller = WebviewController();
    await tester.runAsync(controller.initialize);
    await tester.pumpWidget(host(controller, visible: false, pause: false));
    await tester.pumpWidget(host(controller, visible: true, pause: false));
    expect(deliveryCalls(), isEmpty);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.runAsync(controller.dispose);
  });

  testWidgets('turning the opt-in off restores normal frame delivery', (
    tester,
  ) async {
    final controller = WebviewController();
    await tester.runAsync(controller.initialize);
    await tester.pumpWidget(host(controller, visible: false));
    await tester.pumpWidget(host(controller, visible: false, pause: false));
    expect(deliveryCalls(), [false, true]);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.runAsync(controller.dispose);
  });

  test('disposed controller does not send capture commands', () async {
    final controller = WebviewController();
    await controller.initialize();
    await controller.dispose();
    await controller.setFrameDeliveryEnabled(true);
    expect(deliveryCalls(), isEmpty);
  });

  test('Fish disables delivery before offstage prewarm can start capture', () {
    final source = File(
      'lib/src/widgets/fish_companion_view.dart',
    ).readAsStringSync();
    final initialize = source.substring(
      source.indexOf('Future<void> _initialize()'),
      source.indexOf('Future<void> _handleSourceLinkMessage'),
    );
    expect(
      initialize.indexOf('controller.setFrameDeliveryEnabled(false)'),
      allOf(
        greaterThanOrEqualTo(0),
        lessThan(initialize.indexOf('_primeHeadlessSurfaceSize(controller)')),
      ),
    );
    expect(source, contains('pauseFrameDeliveryWhenOffstage: true'));
    expect(source, isNot(contains('controller.suspend(')));
    expect(source, isNot(contains('controller.resume(')));
  });
}
