import 'dart:async';

import 'package:bdo_craft_planner_flutter/features/resource_map/diagnostics/resource_map_redraw_diagnostic.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _channel = MethodChannel('com.bdocraftplanner.flutter/window');
const _start = 'diagnosticResourceRedrawStart';
const _cancel = 'diagnosticResourceRedrawCancel';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late List<String> calls;
  late Completer<Object?> completion;
  setUp(() {
    calls = [];
    completion = Completer<Object?>();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, (call) {
          calls.add(call.method);
          return call.method == _start ? completion.future : Future.value();
        });
  });
  tearDown(() {
    if (!completion.isCompleted) completion.complete({'status': 'cancelled'});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, null);
  });

  testWidgets('mount and idle never start or schedule diagnostic work', (
    tester,
  ) async {
    await _mount(tester);
    await tester.pump(const Duration(seconds: 3));
    expect(calls, isEmpty);
    expect(tester.binding.hasScheduledFrame, isFalse);
    expect(find.byType(SnackBar), findsNothing);
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets(
    'F8 works with sibling focus and keeps view and editing unchanged',
    (tester) async {
      final focus = FocusNode();
      final text = TextEditingController(text: 'unchanged query');
      final scroll = ScrollController(initialScrollOffset: 24);
      addTearDown(() {
        focus.dispose();
        text.dispose();
        scroll.dispose();
      });
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                TextField(focusNode: focus, controller: text),
                ResourceMapRedrawDiagnostic(
                  active: true,
                  child: SizedBox(
                    key: const ValueKey('map-body'),
                    width: 320,
                    height: 180,
                    child: ListView(
                      controller: scroll,
                      children: const [SizedBox(height: 1000)],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      focus.requestFocus();
      text.selection = const TextSelection(baseOffset: 1, extentOffset: 5);
      await tester.pump();
      final rect = tester.getRect(find.byKey(const ValueKey('map-body')));
      final offset = scroll.offset;
      final selection = text.selection;
      await _f8(tester);
      expect(calls, [_start]);
      expect(focus.hasFocus, isTrue);
      expect(text.selection, selection);
      expect(scroll.offset, offset);
      expect(tester.getRect(find.byKey(const ValueKey('map-body'))), rect);
      completion.complete({'status': 'completed', 'redrawRequests': 60});
      await tester.pump();
      expect(calls, [_start]);
      expect(focus.hasFocus, isTrue);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('one attempt; repeats and a second press cannot extend it', (
    tester,
  ) async {
    await _mount(tester);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.f8);
    await tester.sendKeyRepeatEvent(LogicalKeyboardKey.f8);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.f8);
    await tester.pump();
    await _f8(tester);
    expect(calls, [_start]);
    completion.complete({'status': 'completed', 'redrawRequests': 60});
    await tester.pump();
    await _f8(tester);
    expect(calls, [_start]);
  });

  for (final modifier in [
    LogicalKeyboardKey.shiftLeft,
    LogicalKeyboardKey.controlLeft,
    LogicalKeyboardKey.altLeft,
    LogicalKeyboardKey.metaLeft,
  ]) {
    testWidgets('modified F8 is ignored: ${modifier.keyLabel}', (tester) async {
      await _mount(tester);
      await tester.sendKeyDownEvent(modifier);
      await _f8(tester);
      await tester.sendKeyUpEvent(modifier);
      expect(calls, isEmpty);
      await _f8(tester);
      expect(calls, [_start]);
    });
  }

  testWidgets('inactive Resource cannot consume the attempt', (tester) async {
    await _mount(tester, active: false);
    await _f8(tester);
    expect(calls, isEmpty);
    await _mount(tester);
    await _f8(tester);
    expect(calls, [_start]);
  });

  for (final action in [
    'tab',
    'ticker',
    'lifecycle',
    'metrics',
    'dispose',
    'pointer',
    'key',
  ]) {
    testWidgets('$action cancels a pending burst and never restarts it', (
      tester,
    ) async {
      await _mount(tester);
      await _f8(tester);
      expect(calls, [_start]);
      switch (action) {
        case 'tab':
          await _mount(tester, active: false);
        case 'ticker':
          await _mount(tester, ticker: false);
        case 'lifecycle':
          tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.inactive,
          );
          await tester.pump();
        case 'metrics':
          tester.binding.handleMetricsChanged();
          await tester.pump();
        case 'dispose':
          await tester.pumpWidget(const SizedBox.shrink());
        case 'pointer':
          tester.binding.handlePointerEvent(
            const PointerScrollEvent(
              position: Offset(30, 30),
              scrollDelta: Offset(0, 120),
            ),
          );
          await tester.pump();
        case 'key':
          await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
          await tester.pump();
      }
      expect(calls, [_start, _cancel]);
      completion.complete({'status': 'cancelled', 'redrawRequests': 1});
      await tester.pump();
      if (action != 'dispose') {
        await _mount(tester);
        await _f8(tester);
        expect(calls, [_start, _cancel]);
      }
    });
  }

  testWidgets('a key held before F8 cancels on its next repeat', (
    tester,
  ) async {
    await _mount(tester);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowRight);
    await _f8(tester);
    expect(calls, [_start]);
    await tester.sendKeyRepeatEvent(LogicalKeyboardKey.arrowRight);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(calls, [_start, _cancel]);
  });

  for (final event in <PointerEvent>[
    const PointerUpEvent(),
    const PointerCancelEvent(),
    const PointerPanZoomUpdateEvent(),
    const PointerPanZoomEndEvent(),
  ]) {
    testWidgets('existing interaction cancels on ${event.runtimeType}', (
      tester,
    ) async {
      await _mount(tester);
      await _f8(tester);
      tester.binding.pointerRouter.route(event);
      await tester.pump();
      expect(calls, [_start, _cancel]);
    });
  }

  testWidgets('covered route rejects F8 then cancels an in-flight attempt', (
    tester,
  ) async {
    final navigator = GlobalKey<NavigatorState>();
    await _mount(tester, navigator: navigator);
    final context = tester.element(find.byType(ResourceMapRedrawDiagnostic));
    unawaited(
      showDialog<void>(
        context: context,
        builder: (_) => const AlertDialog(content: Text('Fixture')),
      ),
    );
    await tester.pumpAndSettle();
    await _f8(tester);
    expect(calls, isEmpty);
    navigator.currentState!.pop();
    await tester.pumpAndSettle();
    await _f8(tester);
    expect(calls, [_start]);
    unawaited(
      showDialog<void>(
        context: context,
        builder: (_) => const AlertDialog(content: Text('Fixture')),
      ),
    );
    await tester.pumpAndSettle();
    expect(calls, [_start, _cancel]);
  });

  for (final failure in ['missing', 'platform']) {
    testWidgets('$failure host failure is consumed without UI or retry', (
      tester,
    ) async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(_channel, (call) async {
            calls.add(call.method);
            if (failure == 'missing') throw MissingPluginException();
            throw PlatformException(code: 'unavailable');
          });
      await _mount(tester);
      await _f8(tester);
      await _f8(tester);
      expect(calls, [_start]);
      expect(tester.takeException(), isNull);
      expect(find.byType(SnackBar), findsNothing);
      expect(find.byType(AlertDialog), findsNothing);
    });
  }
}

Future<void> _mount(
  WidgetTester tester, {
  bool active = true,
  bool ticker = true,
  GlobalKey<NavigatorState>? navigator,
}) async {
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  await tester.pumpWidget(
    MaterialApp(
      navigatorKey: navigator,
      home: TickerMode(
        enabled: ticker,
        child: ResourceMapRedrawDiagnostic(
          active: active,
          child: const SizedBox(width: 200, height: 100),
        ),
      ),
    ),
  );
  await tester.pump();
}

Future<void> _f8(WidgetTester tester) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.f8);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.f8);
  await tester.pump();
}
