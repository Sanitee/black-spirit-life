import 'dart:async';

import 'package:bdo_craft_planner_flutter/app/update/beta_update.dart';
import 'package:bdo_craft_planner_flutter/app/update/beta_update_indicator.dart';
import 'package:bdo_craft_planner_flutter/visual/foundations/theme_spec.dart';
import 'package:bdo_craft_planner_flutter/visual/standard/standard_spec.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('stays hidden when private updates are not configured', (
    tester,
  ) async {
    final service = _IndicatorService();
    final controller = BetaUpdateController(service: service, source: '');
    addTearDown(() async {
      controller.dispose();
      await service.dispose();
    });

    await tester.pumpWidget(_host(controller));

    expect(find.byKey(BetaUpdateIndicator.buttonKey), findsNothing);
  });

  testWidgets('shows an animated one-click patch line when available', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final service = _IndicatorService();
    final controller = BetaUpdateController(
      service: service,
      source: r'C:\private-feed',
    );
    var updateCalls = 0;
    addTearDown(() async {
      controller.dispose();
      await service.dispose();
    });

    await tester.pumpWidget(
      _host(controller, onUpdateNow: () async => updateCalls += 1),
    );
    service.emit(
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

    expect(
      find.text('Update available  ·  0.1.0-beta.6  ·  2.5 MB patch'),
      findsOneWidget,
    );
    expect(find.text('Update now'), findsOneWidget);
    expect(
      find.bySemanticsLabel(
        'Update available  ·  0.1.0-beta.6  ·  2.5 MB patch. Update now',
      ),
      findsOneWidget,
    );
    expect(find.byKey(BetaUpdateIndicator.sweepKey), findsOneWidget);
    expect(find.byKey(BetaUpdateIndicator.arrowKey), findsOneWidget);
    final transformBefore = tester.widget<Transform>(
      find.descendant(
        of: find.byKey(BetaUpdateIndicator.iconKey),
        matching: find.byType(Transform),
      ),
    );
    final sweepBefore = tester.widget<Align>(
      find.byKey(BetaUpdateIndicator.sweepKey),
    );
    final arrowBefore = tester.widget<Transform>(
      find.byKey(BetaUpdateIndicator.arrowKey),
    );
    await tester.pump(const Duration(milliseconds: 500));
    final transformAfter = tester.widget<Transform>(
      find.descendant(
        of: find.byKey(BetaUpdateIndicator.iconKey),
        matching: find.byType(Transform),
      ),
    );
    final sweepAfter = tester.widget<Align>(
      find.byKey(BetaUpdateIndicator.sweepKey),
    );
    final arrowAfter = tester.widget<Transform>(
      find.byKey(BetaUpdateIndicator.arrowKey),
    );
    expect(transformAfter.transform, isNot(transformBefore.transform));
    expect(sweepAfter.alignment, isNot(sweepBefore.alignment));
    expect(arrowAfter.transform, isNot(arrowBefore.transform));

    tester.semantics.tap(
      find.semantics.byLabel(
        'Update available  ·  0.1.0-beta.6  ·  2.5 MB patch. Update now',
      ),
    );
    await tester.pump();
    expect(updateCalls, 1);
    semantics.dispose();
  });

  testWidgets('reduced motion keeps the available symbol still', (
    tester,
  ) async {
    final service = _IndicatorService();
    final controller = BetaUpdateController(
      service: service,
      source: r'C:\private-feed',
    );
    addTearDown(() async {
      controller.dispose();
      await service.dispose();
    });

    await tester.pumpWidget(_host(controller, disableAnimations: true));
    service.emit(const BetaUpdateSnapshot(phase: BetaUpdatePhase.available));
    await tester.pump();
    expect(find.byKey(BetaUpdateIndicator.sweepKey), findsNothing);
    final transformBefore = tester.widget<Transform>(
      find.descendant(
        of: find.byKey(BetaUpdateIndicator.iconKey),
        matching: find.byType(Transform),
      ),
    );
    final arrowBefore = tester.widget<Transform>(
      find.byKey(BetaUpdateIndicator.arrowKey),
    );
    await tester.pump(const Duration(seconds: 2));
    final transformAfter = tester.widget<Transform>(
      find.descendant(
        of: find.byKey(BetaUpdateIndicator.iconKey),
        matching: find.byType(Transform),
      ),
    );
    final arrowAfter = tester.widget<Transform>(
      find.byKey(BetaUpdateIndicator.arrowKey),
    );

    expect(transformAfter.transform, transformBefore.transform);
    expect(arrowAfter.transform, arrowBefore.transform);
  });

  testWidgets('shows download progress without accepting another click', (
    tester,
  ) async {
    final service = _IndicatorService();
    final controller = BetaUpdateController(
      service: service,
      source: r'C:\private-feed',
    );
    var updateCalls = 0;
    addTearDown(() async {
      controller.dispose();
      await service.dispose();
    });

    await tester.pumpWidget(
      _host(controller, onUpdateNow: () async => updateCalls += 1),
    );
    service.emit(
      const BetaUpdateSnapshot(
        phase: BetaUpdatePhase.downloading,
        progress: .42,
      ),
    );
    await tester.pump();

    expect(find.text('Downloading update  ·  42%'), findsOneWidget);
    expect(find.byKey(BetaUpdateIndicator.progressKey), findsOneWidget);
    expect(find.byKey(BetaUpdateIndicator.sweepKey), findsNothing);
    expect(find.byKey(BetaUpdateIndicator.arrowKey), findsNothing);
    await tester.tap(find.byKey(BetaUpdateIndicator.buttonKey));
    await tester.pump();
    expect(updateCalls, 0);
  });

  testWidgets('ready is actionable while startup errors stay hidden', (
    tester,
  ) async {
    final service = _IndicatorService();
    final controller = BetaUpdateController(
      service: service,
      source: r'C:\private-feed',
    );
    var updateCalls = 0;
    addTearDown(() async {
      controller.dispose();
      await service.dispose();
    });

    await tester.pumpWidget(
      _host(controller, onUpdateNow: () async => updateCalls += 1),
    );
    service.emit(
      const BetaUpdateSnapshot(
        phase: BetaUpdatePhase.ready,
        targetVersion: '0.1.0-beta.6',
        progress: 1,
      ),
    );
    await tester.pump();
    expect(find.text('Update ready'), findsOneWidget);
    expect(find.text('Restart to install'), findsOneWidget);
    expect(find.byKey(BetaUpdateIndicator.sweepKey), findsNothing);
    final readyIconBefore = tester.widget<Transform>(
      find.descendant(
        of: find.byKey(BetaUpdateIndicator.iconKey),
        matching: find.byType(Transform),
      ),
    );
    final readyArrowBefore = tester.widget<Transform>(
      find.byKey(BetaUpdateIndicator.arrowKey),
    );
    await tester.pump(const Duration(milliseconds: 2500));
    final readyIconAfter = tester.widget<Transform>(
      find.descendant(
        of: find.byKey(BetaUpdateIndicator.iconKey),
        matching: find.byType(Transform),
      ),
    );
    final readyArrowAfter = tester.widget<Transform>(
      find.byKey(BetaUpdateIndicator.arrowKey),
    );
    expect(readyIconAfter.transform, readyIconBefore.transform);
    expect(readyArrowAfter.transform, readyArrowBefore.transform);
    await tester.tap(find.byKey(BetaUpdateIndicator.buttonKey));
    await tester.pump();

    service.emit(const BetaUpdateSnapshot(phase: BetaUpdatePhase.error));
    await tester.pump();
    expect(find.text('Update could not be checked'), findsNothing);
    expect(find.text('Try again'), findsNothing);
    expect(find.byKey(BetaUpdateIndicator.buttonKey), findsNothing);

    expect(updateCalls, 1);
  });

  testWidgets('applying is visible but not actionable', (tester) async {
    final service = _IndicatorService();
    final controller = BetaUpdateController(
      service: service,
      source: r'C:\private-feed',
    );
    var updateCalls = 0;
    addTearDown(() async {
      controller.dispose();
      await service.dispose();
    });

    await tester.pumpWidget(
      _host(controller, onUpdateNow: () async => updateCalls += 1),
    );
    service.emit(
      const BetaUpdateSnapshot(
        phase: BetaUpdatePhase.applying,
        targetVersion: '0.1.0-beta.6',
      ),
    );
    await tester.pump();

    expect(find.text('Applying update'), findsOneWidget);
    expect(find.text('Restarting'), findsOneWidget);
    expect(
      tester.widget<InkWell>(find.byKey(BetaUpdateIndicator.buttonKey)).onTap,
      isNull,
    );
    expect(updateCalls, 0);
  });

  testWidgets('ignores a second click while one-click update is pending', (
    tester,
  ) async {
    final service = _IndicatorService();
    final controller = BetaUpdateController(
      service: service,
      source: r'C:\private-feed',
    );
    final pending = Completer<void>();
    var updateCalls = 0;
    addTearDown(() async {
      if (!pending.isCompleted) pending.complete();
      controller.dispose();
      await service.dispose();
    });

    await tester.pumpWidget(
      _host(
        controller,
        onUpdateNow: () async {
          updateCalls += 1;
          await pending.future;
        },
      ),
    );
    service.emit(const BetaUpdateSnapshot(phase: BetaUpdatePhase.available));
    await tester.pump();

    await tester.tap(find.byKey(BetaUpdateIndicator.buttonKey));
    await tester.pump();
    await tester.tap(find.byKey(BetaUpdateIndicator.buttonKey));
    expect(updateCalls, 1);

    pending.complete();
    await tester.pump();
  });
}

Widget _host(
  BetaUpdateController controller, {
  bool disableAnimations = false,
  Future<void> Function()? onUpdateNow,
}) {
  const spec = StandardSpec.theme;
  return MaterialApp(
    theme: spec.materialTheme(),
    home: MediaQuery(
      data: MediaQueryData(disableAnimations: disableAnimations),
      child: ThemeSpecScope(
        spec: spec,
        child: Scaffold(
          body: Align(
            alignment: Alignment.bottomCenter,
            child: BetaUpdateIndicator(
              controller: controller,
              onUpdateNow: onUpdateNow ?? () async {},
            ),
          ),
        ),
      ),
    ),
  );
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
