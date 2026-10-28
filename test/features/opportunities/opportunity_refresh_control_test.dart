import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:bdo_craft_planner_flutter/data/market/shared_market_repository.dart';
import 'package:bdo_craft_planner_flutter/data/opportunities/opportunity_market_service.dart';
import 'package:bdo_craft_planner_flutter/domain/models/catalog_models.dart';
import 'package:bdo_craft_planner_flutter/features/opportunities/opportunities_controller.dart';
import 'package:bdo_craft_planner_flutter/features/opportunities/opportunities_theme.dart';
import 'package:bdo_craft_planner_flutter/features/opportunities/opportunities_visuals.dart';
import 'package:bdo_craft_planner_flutter/features/opportunities/opportunity_refresh_control.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _buttonKey = ValueKey('opportunities-refresh');
const _marketKey = ValueKey('market-control');

void main() {
  setUpAll(_loadFonts);

  testWidgets(
    'counter is inside the disabled button and never refreshes itself',
    (tester) async {
      final controller = _Controller(tester.binding.clock.now, seconds: 2);
      await tester.pumpWidget(_host(controller));
      expect(find.text('0:02'), findsOneWidget);
      final button = tester.widget<OpportunityButton>(find.byKey(_buttonKey));
      expect(button.onPressed, isNull);
      final plate = tester.getRect(find.byKey(_buttonKey));
      expect(plate.contains(tester.getCenter(find.text('0:02'))), isTrue);
      expect(find.text('Refresh'), findsNothing);
      await tester.tap(find.byKey(_buttonKey));
      expect(controller.refreshCalls, 0);
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('0:01'), findsOneWidget);
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('Refresh'), findsOneWidget);
      expect(controller.refreshCalls, 0);
      await tester.tap(find.byKey(_buttonKey));
      expect(controller.refreshCalls, 1);
      await tester.pumpWidget(const SizedBox.shrink());
      controller.dispose();
    },
  );

  testWidgets('Stop remains enabled during cooldown and returns to counter', (
    tester,
  ) async {
    final controller = _Controller(tester.binding.clock.now, seconds: 60)
      ..scanning = true;
    await tester.pumpWidget(_host(controller));
    expect(find.text('Stop check'), findsOneWidget);
    expect(find.text('Refresh in'), findsNothing);
    await tester.tap(find.byKey(_buttonKey));
    expect(controller.cancelCalls, 1);
    await tester.pump();
    expect(find.text('1:00'), findsOneWidget);
    expect(
      tester.widget<OpportunityButton>(find.byKey(_buttonKey)).onPressed,
      isNull,
    );
    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
  });

  _captureTestWidgets(
    'queued scan wait counts down without disabling Stop or changing height',
    (tester) async {
      _captureSurface(tester, const Size(360, 140));
      final controller = _Controller(tester.binding.clock.now, seconds: 60)
        ..scanning = true
        ..dispatchUntil = tester.binding.clock.now().add(
          const Duration(seconds: 3),
        );
      await tester.pumpWidget(_host(controller));
      expect(find.text('Stop check'), findsOneWidget);
      expect(find.text('0:03'), findsOneWidget);
      expect(find.text('Waiting · resumes in'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(_buttonKey),
          matching: find.text('0:03'),
        ),
        findsNothing,
      );
      await _captureWait(tester, 'active-scan-wait-normal');
      expect(find.text('Refresh in'), findsNothing);
      final height = tester.getSize(find.byKey(_buttonKey)).height;
      expect(height, 40);
      expect(height, tester.getSize(find.byKey(_marketKey)).height);
      expect(
        tester.widget<OpportunityButton>(find.byKey(_buttonKey)).onPressed,
        isNotNull,
      );
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('0:02'), findsOneWidget);
      await tester.pump(const Duration(seconds: 2));
      expect(
        find.byKey(const ValueKey('opportunities-dispatch-countdown')),
        findsNothing,
      );
      expect(find.text('Stop check'), findsOneWidget);
      expect(find.text('Waiting · resumes in'), findsNothing);
      expect(tester.getSize(find.byKey(_buttonKey)).height, height);
      expect(controller.refreshCalls, 0);
      await tester.tap(find.byKey(_buttonKey));
      expect(controller.cancelCalls, 1);
      await tester.pump();
      expect(find.text('0:57'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      controller.dispose();
    },
  );

  testWidgets('sub-second pacing does not flash a scan countdown', (
    tester,
  ) async {
    final controller = _Controller(tester.binding.clock.now, seconds: 60)
      ..scanning = true;
    await tester.pumpWidget(_host(controller));
    for (final milliseconds in [40, 250, 999]) {
      controller.dispatchUntil = tester.binding.clock.now().add(
        Duration(milliseconds: milliseconds),
      );
      controller.changed();
      await tester.pump();
      expect(find.text('Stop check'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('opportunities-dispatch-countdown')),
        findsNothing,
      );
      expect(
        tester.widget<OpportunityButton>(find.byKey(_buttonKey)).onPressed,
        isNotNull,
      );
    }
    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
  });

  testWidgets('active wait stops ticking offstage and after disposal', (
    tester,
  ) async {
    final controller = _Controller(tester.binding.clock.now)
      ..scanning = true
      ..dispatchUntil = tester.binding.clock.now().add(
        const Duration(seconds: 60),
      );
    await tester.pumpWidget(_host(controller));
    await tester.pumpWidget(_host(controller, visible: false));
    final reads = controller.dispatchReads;
    await tester.pump(const Duration(seconds: 10));
    expect(controller.dispatchReads, reads);
    await tester.pumpWidget(_host(controller));
    expect(find.text('0:50'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    final disposedReads = controller.dispatchReads;
    await tester.pump(const Duration(seconds: 10));
    expect(controller.dispatchReads, disposedReads);
    controller.dispose();
  });

  _captureTestWidgets(
    'enlarged active wait retains readable timer and Stop action',
    (tester) async {
      _captureSurface(tester, const Size(520, 200));
      final controller = _Controller(tester.binding.clock.now)
        ..scanning = true
        ..dispatchUntil = tester.binding.clock.now().add(
          const Duration(seconds: 3661),
        );
      await tester.pumpWidget(_host(controller, textScale: 2));
      await _captureWait(tester, 'active-scan-wait-enlarged-200');
      final plate = tester.getRect(find.byKey(_buttonKey));
      for (final label in ['Stop check']) {
        final rect = tester.getRect(find.text(label));
        expect(plate.contains(rect.topLeft), isTrue);
        expect(plate.contains(rect.bottomRight), isTrue);
      }
      final timer = tester.getRect(find.text('1:01:01'));
      expect(timer.right, lessThanOrEqualTo(520));
      expect(timer.bottom, lessThanOrEqualTo(200));
      expect(find.text('Waiting · resumes in'), findsOneWidget);
      expect(plate.height, tester.getSize(find.byKey(_marketKey)).height);
      await tester.tap(find.byKey(_buttonKey));
      expect(controller.cancelCalls, 1);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      controller.dispose();
    },
  );

  testWidgets('rounds remaining time up and supports a long provider pause', (
    tester,
  ) async {
    final controller = _Controller(tester.binding.clock.now, seconds: 3661)
      ..providerPaused = true;
    await tester.pumpWidget(_host(controller));
    expect(find.text('1:01:01'), findsOneWidget);
    expect(
      tester.widget<OpportunityButton>(find.byKey(_buttonKey)).tooltip,
      contains('market asked us to wait'),
    );
    controller.until = tester.binding.clock.now().add(
      const Duration(microseconds: 1),
    );
    controller.changed();
    await tester.pump();
    expect(find.text('0:01'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
  });

  testWidgets('initializing and pending work cannot be clicked', (
    tester,
  ) async {
    final controller = _Controller(tester.binding.clock.now)
      ..initializing = true;
    await tester.pumpWidget(_host(controller));
    expect(find.text('Please wait'), findsOneWidget);
    final height = tester.getSize(find.byKey(_buttonKey)).height;
    expect(height, 40);
    expect(height, tester.getSize(find.byKey(_marketKey)).height);
    await tester.tap(find.byKey(_buttonKey));
    expect(controller.refreshCalls, 0);
    controller
      ..initializing = false
      ..pendingWork = true
      ..changed();
    await tester.pump();
    expect(tester.getSize(find.byKey(_buttonKey)).height, height);
    expect(
      tester.widget<OpportunityButton>(find.byKey(_buttonKey)).onPressed,
      isNull,
    );
    controller
      ..pendingWork = false
      ..changed();
    await tester.pump();
    expect(find.text('Refresh'), findsOneWidget);
    expect(tester.getSize(find.byKey(_buttonKey)).height, height);
    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
  });

  testWidgets('timer pauses offstage and recomputes immediately when visible', (
    tester,
  ) async {
    final controller = _Controller(tester.binding.clock.now, seconds: 60);
    await tester.pumpWidget(_host(controller));
    await tester.pumpWidget(_host(controller, visible: false));
    final reads = controller.reads;
    await tester.pump(const Duration(seconds: 10));
    expect(controller.reads, reads);
    await tester.pumpWidget(_host(controller));
    expect(find.text('0:50'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    final disposedReads = controller.reads;
    await tester.pump(const Duration(seconds: 10));
    expect(controller.reads, disposedReads);
    expect(controller.hasControlListener, isFalse);
    controller.dispose();
  });

  testWidgets('timer pauses in background and resumes without stale counter', (
    tester,
  ) async {
    final controller = _Controller(tester.binding.clock.now, seconds: 60);
    await tester.pumpWidget(_host(controller));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    final reads = controller.reads;
    await tester.pump(const Duration(seconds: 10));
    expect(controller.reads, reads);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(find.text('0:50'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
  });

  testWidgets('changing controller detaches the old listener and timer', (
    tester,
  ) async {
    final first = _Controller(tester.binding.clock.now, seconds: 60);
    final second = _Controller(tester.binding.clock.now);
    await tester.pumpWidget(_host(first));
    await tester.pumpWidget(_host(second));
    expect(first.hasControlListener, isFalse);
    expect(find.text('Refresh'), findsOneWidget);
    await tester.tap(find.byKey(_buttonKey));
    expect(first.refreshCalls, 0);
    expect(second.refreshCalls, 1);
    await tester.pumpWidget(const SizedBox.shrink());
    first.dispose();
    second.dispose();
  });

  for (final scale in [1.0, 2.0]) {
    _captureTestWidgets('all action states match Market height at $scale', (
      tester,
    ) async {
      _captureSurface(
        tester,
        scale == 1 ? const Size(430, 140) : const Size(720, 200),
      );
      final controller = _Controller(tester.binding.clock.now);
      await tester.pumpWidget(_host(controller, textScale: scale));
      final marketHeight = tester.getSize(find.byKey(_marketKey)).height;
      if (scale == 1) expect(marketHeight, 40);
      for (final state in [
        (name: 'ready', seconds: 0, scanning: false, dispatch: 0),
        (name: 'cooldown', seconds: 48, scanning: false, dispatch: 0),
        (name: 'checking', seconds: 48, scanning: true, dispatch: 0),
        (name: 'queued', seconds: 48, scanning: true, dispatch: 48),
        (name: 'provider-pause', seconds: 3661, scanning: false, dispatch: 0),
      ]) {
        controller
          ..until = tester.binding.clock.now().add(
            Duration(seconds: state.seconds),
          )
          ..scanning = state.scanning
          ..dispatchUntil = tester.binding.clock.now().add(
            Duration(seconds: state.dispatch),
          )
          ..providerPaused = state.name == 'provider-pause'
          ..changed();
        await tester.pump();
        final plate = tester.getRect(find.byKey(_buttonKey));
        expect(
          plate.height,
          closeTo(marketHeight, .000001),
          reason: state.name,
        );
        for (final key in [
          'opportunities-refresh-countdown',
          'opportunities-dispatch-countdown',
        ]) {
          final timer = find.byKey(ValueKey(key));
          if (timer.evaluate().isEmpty) continue;
          final rect = tester.getRect(timer);
          if (key == 'opportunities-refresh-countdown') {
            expect(plate.contains(rect.topLeft), isTrue);
            expect(plate.contains(rect.bottomRight), isTrue);
          } else {
            expect(plate.overlaps(rect), isFalse);
            expect(find.text('Waiting · resumes in'), findsOneWidget);
          }
        }
        await _captureWait(
          tester,
          'refresh-compact-${state.name}-${(scale * 100).round()}',
        );
        expect(tester.takeException(), isNull);
      }
      expect(controller.refreshCalls, 0);
      expect(controller.cancelCalls, 0);
      await tester.pumpWidget(const SizedBox.shrink());
      controller.dispose();
    });
  }

  testWidgets('compact actions retain keyboard and accessible waiting state', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final controller = _Controller(tester.binding.clock.now);
    await tester.pumpWidget(_host(controller));
    await tester.pump(const Duration(milliseconds: 300));
    final button = find.byKey(_buttonKey);
    final actionSemantics = find.descendant(
      of: button,
      matching: find.byWidgetPredicate(
        (widget) => widget is Semantics && widget.properties.button == true,
      ),
    );
    final detector = find.descendant(
      of: button,
      matching: find.byType(FocusableActionDetector),
    );
    tester.widget<FocusableActionDetector>(detector).focusNode!.requestFocus();
    await tester.pump();
    expect(
      tester.getSemantics(actionSemantics).getSemanticsData().label,
      'Refresh',
    );
    expect(
      tester
          .getSemantics(actionSemantics)
          .getSemanticsData()
          .hasAction(ui.SemanticsAction.tap),
      isTrue,
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    expect(controller.refreshCalls, 1);

    controller
      ..scanning = true
      ..until = tester.binding.clock.now().add(const Duration(seconds: 48))
      ..dispatchUntil = controller.until
      ..changed();
    await tester.pump();
    expect(
      tester.getSemantics(actionSemantics).getSemanticsData().label,
      'Stop check. Waiting 0:48 before queued market requests.',
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    expect(controller.cancelCalls, 1);
    await tester.pump();
    final blocked = tester.getSemantics(actionSemantics).getSemanticsData();
    expect(blocked.label, 'Refresh in 0:48');
    expect(blocked.hasAction(ui.SemanticsAction.tap), isFalse);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    expect(controller.refreshCalls, 1);
    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
    semantics.dispose();
  });

  testWidgets('shared activity updates readiness without a controller event', (
    tester,
  ) async {
    final broker = SharedMarketRepository(
      transport: _OfflineTransport(),
      requestSpacing: Duration.zero,
      orderBookRequestSpacing: Duration.zero,
    );
    await broker.ready;
    final controller = _Controller(tester.binding.clock.now)..broker = broker;
    await tester.pumpWidget(_host(controller));
    expect(find.text('Refresh'), findsOneWidget);
    controller.until = tester.binding.clock.now().add(
      const Duration(seconds: 40),
    );
    final request = broker.fetch(
      bookKeys: [SharedMarketKey(region: 'eu', itemId: '1')],
    );
    await tester.pump();
    await request;
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('0:40'), findsOneWidget);
    expect(
      tester.widget<OpportunityButton>(find.byKey(_buttonKey)).onPressed,
      isNull,
    );
    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
    await broker.close();
    await tester.pump(const Duration(seconds: 1));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'enlarged text fits without hiding the counter or market action',
    (tester) async {
      final controller = _Controller(tester.binding.clock.now, seconds: 3661);
      await tester.pumpWidget(_host(controller, textScale: 2));
      final plate = tester.getRect(find.byKey(_buttonKey));
      final timer = tester.getRect(find.text('1:01:01'));
      expect(plate.contains(timer.topLeft), isTrue);
      expect(plate.contains(timer.bottomRight), isTrue);
      expect(find.text('Market · EU'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      controller.dispose();
    },
  );

  testWidgets('dark countdown plate uses the actual Opportunities theme', (
    tester,
  ) async {
    final previousShadows = debugDisableShadows;
    debugDisableShadows = false;
    tester.view.physicalSize = const Size(360, 140);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller = _Controller(tester.binding.clock.now, seconds: 42);
    try {
      await tester.pumpWidget(_host(controller));
      await tester.pump(const Duration(milliseconds: 300));
      await expectLater(
        find.byKey(const ValueKey('refresh-preview')),
        matchesGoldenFile('goldens/opportunity_refresh_countdown.png'),
      );
      await tester.pumpWidget(const SizedBox.shrink());
      controller.dispose();
    } finally {
      debugDisableShadows = previousShadows;
    }
  });
}

Widget _host(
  _Controller controller, {
  bool visible = true,
  double textScale = 1,
}) => MaterialApp(
  debugShowCheckedModeBanner: false,
  home: RepaintBoundary(
    key: const ValueKey('refresh-preview'),
    child: OpportunitiesTheme(
      child: MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
        child: TickerMode(
          enabled: visible,
          child: Offstage(
            offstage: !visible,
            child: Center(
              child: Wrap(
                spacing: 10,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.end,
                children: [
                  OpportunityButton.label(
                    'Market · EU',
                    key: _marketKey,
                    minimumSize: const Size(0, 40),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    onPressed: () {},
                  ),
                  OpportunityRefreshControl(controller: controller),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  ),
);

class _Controller extends ChangeNotifier implements OpportunitiesController {
  _Controller(this.now, {int seconds = 0})
    : until = now().add(Duration(seconds: seconds));

  final DateTime Function() now;
  DateTime until;
  DateTime? dispatchUntil;
  int reads = 0;
  int dispatchReads = 0;
  int refreshCalls = 0;
  int cancelCalls = 0;
  bool initializing = false;
  bool pendingWork = false;
  bool providerPaused = false;
  SharedMarketRepository? broker;

  bool get hasControlListener => hasListeners;

  @override
  bool scanning = false;

  @override
  SharedMarketRepository? get sharedMarket => broker;

  @override
  Duration get activeDispatchWait {
    dispatchReads++;
    final wait = dispatchUntil?.difference(now()) ?? Duration.zero;
    return scanning && wait > Duration.zero ? wait : Duration.zero;
  }

  @override
  SharedMarketRefreshReadiness get refreshReadiness {
    reads++;
    final wait = until.difference(now());
    return SharedMarketRefreshReadiness(
      wait: wait.isNegative ? Duration.zero : wait,
      initializing: initializing,
      pendingWork: pendingWork,
      providerPaused: providerPaused,
      requestCount: 98,
      windowLimit: 98,
    );
  }

  void changed() => notifyListeners();

  @override
  Future<void> refresh({
    Recipe? recipe,
    bool onlyStale = false,
    Duration automaticMaxAge = OpportunitiesController.automaticMarketAge,
  }) async {
    refreshCalls++;
  }

  @override
  void cancel() {
    cancelCalls++;
    scanning = false;
    notifyListeners();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _OfflineTransport implements OpportunityMarketTransport {
  @override
  Future<OpportunityHttpResponse> post(
    Uri uri, {
    required Map<String, String> headers,
    required String body,
    Future<void>? abortTrigger,
  }) async => OpportunityHttpResponse(
    statusCode: 200,
    bytes: Uint8List.fromList(
      utf8.encode(jsonEncode({'resultCode': 0, 'resultMsg': '100-3-0|90-0-7'})),
    ),
  );

  @override
  void close() {}
}

Future<void> _loadFonts() async {
  if (!Platform.isWindows) return;
  final windows = Platform.environment['WINDIR'] ?? r'C:\Windows';
  final loader = FontLoader('Segoe UI');
  for (final name in ['segoeui.ttf', 'seguisb.ttf', 'segoeuib.ttf']) {
    loader.addFont(
      File('$windows/Fonts/$name').readAsBytes().then(ByteData.sublistView),
    );
  }
  await loader.load();
}

void _captureSurface(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void _captureTestWidgets(String description, WidgetTesterCallback body) {
  testWidgets(description, (tester) async {
    final previousShadows = debugDisableShadows;
    debugDisableShadows = false;
    try {
      await body(tester);
    } finally {
      debugDisableShadows = previousShadows;
    }
  });
}

Future<void> _captureWait(WidgetTester tester, String name) async {
  final directory = Platform.environment['REFRESH_CONTROL_CAPTURE_DIR'];
  if (directory == null) return;
  await tester.pump(const Duration(milliseconds: 300));
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(const ValueKey('refresh-preview')),
  );
  await tester.runAsync(() async {
    await Directory(directory).create(recursive: true);
    final image = await boundary.toImage();
    try {
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      await File(
        '$directory/$name.png',
      ).writeAsBytes(bytes!.buffer.asUint8List());
    } finally {
      image.dispose();
    }
  });
}
