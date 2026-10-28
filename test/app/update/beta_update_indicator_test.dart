import 'dart:async';

import 'package:bdo_craft_planner_flutter/app/update/beta_update.dart';
import 'package:bdo_craft_planner_flutter/app/update/beta_update_indicator.dart';
import 'package:bdo_craft_planner_flutter/visual/foundations/theme_spec.dart';
import 'package:bdo_craft_planner_flutter/visual/standard/standard_spec.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('stays hidden when updates are not configured', (tester) async {
    final fixture = _Fixture(source: '');
    addTearDown(fixture.dispose);

    await tester.pumpWidget(_host(fixture.controller));

    expect(find.byKey(BetaUpdateIndicator.buttonKey), findsNothing);
  });

  testWidgets('shows the tight title-bar update control', (tester) async {
    final semantics = tester.ensureSemantics();
    final fixture = _Fixture();
    var updateCalls = 0;
    addTearDown(fixture.dispose);

    await tester.pumpWidget(
      _host(fixture.controller, onUpdateNow: () async => updateCalls += 1),
    );
    fixture.emit(
      const BetaUpdateSnapshot(
        phase: BetaUpdatePhase.available,
        currentVersion: '0.1.0-beta.5',
        targetVersion: '0.1.0-beta.6',
        sizeBytes: 2610822,
        fullSizeBytes: 66854193,
        deltaCount: 1,
      ),
    );
    await tester.pump();

    expect(find.text('Update'), findsOneWidget);
    expect(
      tester.getSize(find.byKey(BetaUpdateIndicator.buttonKey)),
      const Size(BetaUpdateIndicator.expandedWidth, 36),
    );
    expect(
      find.bySemanticsLabel(
        'Update to version 0.1.0-beta.6 · 2.5 MB patch · '
        'Installs and restarts automatically',
      ),
      findsOneWidget,
    );
    expect(find.byKey(BetaUpdateIndicator.petalRainKey), findsNothing);
    expect(find.byKey(BetaUpdateIndicator.savingsKey), findsNothing);
    expect(find.byKey(BetaUpdateIndicator.arrowKey), findsNothing);

    await tester.tap(find.byKey(BetaUpdateIndicator.buttonKey));
    await tester.pump();
    expect(updateCalls, 1);
    semantics.dispose();
  });

  testWidgets('breathes slowly while an update is available', (tester) async {
    final fixture = _Fixture();
    addTearDown(fixture.dispose);

    await tester.pumpWidget(_host(fixture.controller));
    fixture.emit(const BetaUpdateSnapshot(phase: BetaUpdatePhase.available));
    await tester.pump();

    final paintFinder = find.descendant(
      of: find.byKey(BetaUpdateIndicator.availableContentKey),
      matching: find.byType(CustomPaint),
    );
    final before = tester.widgetList<CustomPaint>(paintFinder).first.painter;
    await tester.pump(const Duration(milliseconds: 1300));
    final after = tester.widgetList<CustomPaint>(paintFinder).first.painter;

    expect(after, isNot(same(before)));
  });

  testWidgets('reduced motion keeps the glow still', (tester) async {
    final fixture = _Fixture();
    addTearDown(fixture.dispose);

    await tester.pumpWidget(_host(fixture.controller, disableAnimations: true));
    fixture.emit(const BetaUpdateSnapshot(phase: BetaUpdatePhase.available));
    await tester.pump();

    final paintFinder = find.descendant(
      of: find.byKey(BetaUpdateIndicator.availableContentKey),
      matching: find.byType(CustomPaint),
    );
    final before = tester.widgetList<CustomPaint>(paintFinder).first.painter;
    await tester.pump(const Duration(milliseconds: 2600));
    final after = tester.widgetList<CustomPaint>(paintFinder).first.painter;

    expect(after, same(before));
  });

  testWidgets('uses an icon-only compact control on narrow layouts', (
    tester,
  ) async {
    final fixture = _Fixture();
    addTearDown(fixture.dispose);

    await tester.pumpWidget(_host(fixture.controller, width: 360));
    fixture.emit(
      const BetaUpdateSnapshot(
        phase: BetaUpdatePhase.available,
        targetVersion: '0.1.0-beta.6',
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.text('Update'), findsNothing);
    expect(
      tester.getSize(find.byKey(BetaUpdateIndicator.buttonKey)),
      const Size(BetaUpdateIndicator.compactWidth, 36),
    );
    expect(find.byKey(BetaUpdateIndicator.iconKey), findsOneWidget);
  });

  testWidgets('hidden ticker mode pauses breathing and resumes when visible', (
    tester,
  ) async {
    final fixture = _Fixture();
    addTearDown(fixture.dispose);
    await tester.pumpWidget(_host(fixture.controller));
    fixture.emit(const BetaUpdateSnapshot(phase: BetaUpdatePhase.available));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pumpWidget(_host(fixture.controller, tickerEnabled: false));
    final paints = find.descendant(
      of: find.byKey(BetaUpdateIndicator.availableContentKey),
      matching: find.byType(CustomPaint),
    );
    final paused = tester.widgetList<CustomPaint>(paints).first.painter;
    await tester.pump(const Duration(seconds: 3));
    expect(tester.widgetList<CustomPaint>(paints).first.painter, same(paused));
    await tester.pumpWidget(_host(fixture.controller, tickerEnabled: true));
    final resumed = tester.widgetList<CustomPaint>(paints).first.painter;
    await tester.pump(const Duration(milliseconds: 2288));
    expect(
      tester.widgetList<CustomPaint>(paints).first.painter,
      isNot(same(resumed)),
    );
    fixture.emit(const BetaUpdateSnapshot(phase: BetaUpdatePhase.upToDate));
    await tester.pumpAndSettle();
    expect(find.byKey(BetaUpdateIndicator.buttonKey), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    expect(tester.takeException(), isNull);
  });

  testWidgets('uses compact mode at enlarged text scale', (tester) async {
    final fixture = _Fixture();
    addTearDown(fixture.dispose);

    await tester.pumpWidget(
      _host(
        fixture.controller,
        width: 900,
        textScaler: const TextScaler.linear(1.5),
      ),
    );
    fixture.emit(const BetaUpdateSnapshot(phase: BetaUpdatePhase.available));
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(
      tester.getSize(find.byKey(BetaUpdateIndicator.buttonKey)),
      const Size(BetaUpdateIndicator.compactWidth, 36),
    );
  });

  testWidgets('shows progress without accepting another click', (tester) async {
    final fixture = _Fixture();
    var updateCalls = 0;
    addTearDown(fixture.dispose);

    await tester.pumpWidget(
      _host(fixture.controller, onUpdateNow: () async => updateCalls += 1),
    );
    fixture.emit(
      const BetaUpdateSnapshot(
        phase: BetaUpdatePhase.downloading,
        progress: .42,
        targetVersion: '0.1.0-beta.6',
      ),
    );
    await tester.pump();

    expect(find.text('42%'), findsOneWidget);
    expect(find.byKey(BetaUpdateIndicator.progressKey), findsOneWidget);
    expect(
      tester.widget<InkWell>(find.byKey(BetaUpdateIndicator.buttonKey)).onTap,
      isNull,
    );
    expect(updateCalls, 0);
  });

  testWidgets('ready is actionable and applying is visible but disabled', (
    tester,
  ) async {
    final fixture = _Fixture();
    var updateCalls = 0;
    addTearDown(fixture.dispose);

    await tester.pumpWidget(
      _host(fixture.controller, onUpdateNow: () async => updateCalls += 1),
    );
    fixture.emit(
      const BetaUpdateSnapshot(
        phase: BetaUpdatePhase.ready,
        targetVersion: '0.1.0-beta.6',
      ),
    );
    await tester.pump();
    expect(find.text('Restart'), findsOneWidget);
    await tester.tap(find.byKey(BetaUpdateIndicator.buttonKey));
    await tester.pump();
    expect(updateCalls, 1);

    fixture.emit(
      const BetaUpdateSnapshot(
        phase: BetaUpdatePhase.applying,
        targetVersion: '0.1.0-beta.6',
      ),
    );
    await tester.pump();
    expect(find.text('Updating'), findsOneWidget);
    expect(
      tester.widget<InkWell>(find.byKey(BetaUpdateIndicator.buttonKey)).onTap,
      isNull,
    );
  });

  testWidgets('ignores a second activation while the first is pending', (
    tester,
  ) async {
    final fixture = _Fixture();
    final pending = Completer<void>();
    var updateCalls = 0;
    addTearDown(() async {
      if (!pending.isCompleted) pending.complete();
      await fixture.dispose();
    });

    await tester.pumpWidget(
      _host(
        fixture.controller,
        onUpdateNow: () async {
          updateCalls += 1;
          await pending.future;
        },
      ),
    );
    fixture.emit(const BetaUpdateSnapshot(phase: BetaUpdatePhase.available));
    await tester.pump();

    await tester.tap(find.byKey(BetaUpdateIndicator.buttonKey));
    await tester.pump();
    await tester.tap(
      find.byKey(BetaUpdateIndicator.buttonKey),
      warnIfMissed: false,
    );
    expect(updateCalls, 1);

    pending.complete();
    await tester.pump();
  });
}

Widget _host(
  BetaUpdateController controller, {
  bool disableAnimations = false,
  bool tickerEnabled = true,
  double width = 900,
  TextScaler textScaler = TextScaler.noScaling,
  Future<void> Function()? onUpdateNow,
}) {
  const spec = StandardSpec.theme;
  return MaterialApp(
    theme: spec.materialTheme(),
    home: MediaQuery(
      data: MediaQueryData(
        size: Size(width, 600),
        disableAnimations: disableAnimations,
        textScaler: textScaler,
      ),
      child: ThemeSpecScope(
        spec: spec,
        child: Scaffold(
          body: Align(
            alignment: Alignment.topRight,
            child: TickerMode(
              enabled: tickerEnabled,
              child: BetaUpdateIndicator(
                controller: controller,
                onUpdateNow: onUpdateNow ?? () async {},
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

class _Fixture {
  _Fixture({String source = r'C:\private-feed'}) {
    service = _IndicatorService();
    controller = BetaUpdateController(service: service, source: source);
  }

  late final _IndicatorService service;
  late final BetaUpdateController controller;

  void emit(BetaUpdateSnapshot snapshot) => service.emit(snapshot);

  Future<void> dispose() async {
    controller.dispose();
    await service.dispose();
  }
}

class _IndicatorService implements BetaUpdateService {
  final StreamController<BetaUpdateSnapshot> _controller =
      StreamController<BetaUpdateSnapshot>.broadcast(sync: true);

  @override
  Stream<BetaUpdateSnapshot> get snapshots => _controller.stream;

  void emit(BetaUpdateSnapshot snapshot) => _controller.add(snapshot);

  @override
  Future<BetaUpdateSnapshot> currentStatus() async =>
      const BetaUpdateSnapshot();

  @override
  Future<BetaUpdateSnapshot> checkForUpdates(String source) async =>
      const BetaUpdateSnapshot(phase: BetaUpdatePhase.checking);

  @override
  Future<BetaUpdateSnapshot> downloadUpdate() async =>
      const BetaUpdateSnapshot(phase: BetaUpdatePhase.downloading);

  @override
  Future<BetaUpdateSnapshot> restartAndApply() async =>
      const BetaUpdateSnapshot(phase: BetaUpdatePhase.applying);

  @override
  Future<void> dispose() => _controller.close();
}
