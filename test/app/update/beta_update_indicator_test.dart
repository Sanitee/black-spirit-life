import 'dart:async';

import 'package:bdo_craft_planner_flutter/app/update/beta_update.dart';
import 'package:bdo_craft_planner_flutter/app/update/beta_update_indicator.dart';
import 'package:bdo_craft_planner_flutter/visual/components/sakura_petal_rain.dart';
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

  testWidgets('shows a one-shot Sakura patch notice when available', (
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

    expect(find.text('DELTA UPDATE'), findsOneWidget);
    expect(find.text('61 MB smaller than the full download'), findsOneWidget);
    expect(find.text('Version 0.1.0-beta.6 is ready'), findsOneWidget);
    expect(
      find.text('2.5 MB patch  ·  installs and restarts automatically'),
      findsOneWidget,
    );
    expect(find.text('Update now'), findsOneWidget);
    expect(
      find.bySemanticsLabel(
        'Update available. Version 0.1.0-beta.6. 2.5 MB delta patch. '
        'Saves 61 MB compared with the full download. '
        'Installs and restarts automatically. Update now',
      ),
      findsOneWidget,
    );
    expect(find.byKey(BetaUpdateIndicator.petalRainKey), findsOneWidget);
    expect(find.byKey(BetaUpdateIndicator.arrowKey), findsOneWidget);
    final petalsBefore = tester.widget<CustomPaint>(
      find.byKey(BetaUpdateIndicator.petalRainKey),
    );
    final petalPainterBefore = petalsBefore.painter! as SakuraPetalRainPainter;
    final transformBefore = tester.widget<Transform>(
      find.descendant(
        of: find.byKey(BetaUpdateIndicator.iconKey),
        matching: find.byType(Transform),
      ),
    );
    final arrowBefore = tester.widget<Transform>(
      find.byKey(BetaUpdateIndicator.arrowKey),
    );
    await tester.pump(const Duration(milliseconds: 500));
    final petalsAfter = tester.widget<CustomPaint>(
      find.byKey(BetaUpdateIndicator.petalRainKey),
    );
    final petalPainterAfter = petalsAfter.painter! as SakuraPetalRainPainter;
    final transformAfter = tester.widget<Transform>(
      find.descendant(
        of: find.byKey(BetaUpdateIndicator.iconKey),
        matching: find.byType(Transform),
      ),
    );
    final arrowAfter = tester.widget<Transform>(
      find.byKey(BetaUpdateIndicator.arrowKey),
    );
    expect(
      petalPainterAfter.progress,
      greaterThan(petalPainterBefore.progress),
    );
    expect(transformAfter.transform, isNot(transformBefore.transform));
    expect(arrowAfter.transform, isNot(arrowBefore.transform));

    await tester.pump(const Duration(seconds: 11));
    final settledPainter =
        tester
                .widget<CustomPaint>(
                  find.byKey(BetaUpdateIndicator.petalRainKey),
                )
                .painter!
            as SakuraPetalRainPainter;
    expect(settledPainter.progress, 1);
    await tester.pump(const Duration(seconds: 2));
    final stillSettledPainter =
        tester
                .widget<CustomPaint>(
                  find.byKey(BetaUpdateIndicator.petalRainKey),
                )
                .painter!
            as SakuraPetalRainPainter;
    expect(stillSettledPainter.progress, 1);

    tester.semantics.tap(
      find.semantics.byLabel(
        'Update available. Version 0.1.0-beta.6. 2.5 MB delta patch. '
        'Saves 61 MB compared with the full download. '
        'Installs and restarts automatically. Update now',
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
    expect(find.byKey(BetaUpdateIndicator.petalRainKey), findsNothing);
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

    await tester.pumpWidget(_host(controller));
    await tester.pump();
    final consumedPainter =
        tester
                .widget<CustomPaint>(
                  find.byKey(BetaUpdateIndicator.petalRainKey),
                )
                .painter!
            as SakuraPetalRainPainter;
    expect(consumedPainter.progress, 1);
    await tester.pump(const Duration(milliseconds: 500));
    final stillConsumedPainter =
        tester
                .widget<CustomPaint>(
                  find.byKey(BetaUpdateIndicator.petalRainKey),
                )
                .painter!
            as SakuraPetalRainPainter;
    expect(stillConsumedPainter.progress, 1);
  });

  testWidgets('controller replacement preserves a visible matching offer', (
    tester,
  ) async {
    final firstService = _IndicatorService();
    final secondService = _IndicatorService();
    final firstController = BetaUpdateController(
      service: firstService,
      source: r'C:\private-feed',
    );
    final secondController = BetaUpdateController(
      service: secondService,
      source: r'C:\private-feed',
    );
    addTearDown(() async {
      firstController.dispose();
      secondController.dispose();
      await firstService.dispose();
      await secondService.dispose();
    });
    const offer = BetaUpdateSnapshot(
      phase: BetaUpdatePhase.available,
      currentVersion: '0.1.0-beta.5',
      targetVersion: '0.1.0-beta.6',
      sizeBytes: 2610822,
      fullSizeBytes: 66854193,
      deltaCount: 1,
    );

    await tester.pumpWidget(_host(firstController));
    firstService.emit(offer);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 900));
    final progressBeforeSwap =
        (tester
                    .widget<CustomPaint>(
                      find.byKey(BetaUpdateIndicator.petalRainKey),
                    )
                    .painter!
                as SakuraPetalRainPainter)
            .progress;
    expect(progressBeforeSwap, greaterThan(0));

    secondService.emit(offer);
    await tester.pumpWidget(_host(secondController));
    final progressAfterSwap =
        (tester
                    .widget<CustomPaint>(
                      find.byKey(BetaUpdateIndicator.petalRainKey),
                    )
                    .painter!
                as SakuraPetalRainPainter)
            .progress;
    expect(progressAfterSwap, progressBeforeSwap);
  });

  testWidgets('replays petals only when an offer is newly surfaced', (
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

    await tester.pumpWidget(_host(controller));
    const firstOffer = BetaUpdateSnapshot(
      phase: BetaUpdatePhase.available,
      currentVersion: '0.1.0-beta.5',
      targetVersion: '0.1.0-beta.6',
      sizeBytes: 2610822,
      fullSizeBytes: 66854193,
      deltaCount: 1,
    );
    service.emit(firstOffer);
    await tester.pump();
    await tester.pump(const Duration(seconds: 11));

    service.emit(firstOffer);
    await tester.pump();
    final duplicatePainter =
        tester
                .widget<CustomPaint>(
                  find.byKey(BetaUpdateIndicator.petalRainKey),
                )
                .painter!
            as SakuraPetalRainPainter;
    expect(duplicatePainter.progress, 1);

    const secondOffer = BetaUpdateSnapshot(
      phase: BetaUpdatePhase.available,
      currentVersion: '0.1.0-beta.5',
      targetVersion: '0.1.0-beta.7',
      sizeBytes: 3145728,
      fullSizeBytes: 68157440,
      deltaCount: 1,
    );
    service.emit(secondOffer);
    await tester.pump();
    final newOfferPainter =
        tester
                .widget<CustomPaint>(
                  find.byKey(BetaUpdateIndicator.petalRainKey),
                )
                .painter!
            as SakuraPetalRainPainter;
    expect(newOfferPainter.progress, 0);
    await tester.pump(const Duration(milliseconds: 500));
    final movingPainter =
        tester
                .widget<CustomPaint>(
                  find.byKey(BetaUpdateIndicator.petalRainKey),
                )
                .painter!
            as SakuraPetalRainPainter;
    expect(movingPainter.progress, greaterThan(0));

    service.emit(
      secondOffer.copyWith(phase: BetaUpdatePhase.downloading, progress: .1),
    );
    await tester.pump();
    expect(find.byKey(BetaUpdateIndicator.petalRainKey), findsNothing);

    service.emit(secondOffer);
    await tester.pump();
    final resurfacedPainter =
        tester
                .widget<CustomPaint>(
                  find.byKey(BetaUpdateIndicator.petalRainKey),
                )
                .painter!
            as SakuraPetalRainPainter;
    expect(resurfacedPainter.progress, 0);
  });

  testWidgets('keeps the update action readable in compact layouts', (
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

    await tester.pumpWidget(
      _host(controller, width: 360, textScaler: const TextScaler.linear(1.2)),
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

    expect(tester.takeException(), isNull);
    expect(find.text('Version 0.1.0-beta.6 is ready'), findsOneWidget);
    expect(find.text('Update'), findsOneWidget);
    expect(find.byKey(BetaUpdateIndicator.savingsKey), findsNothing);
    expect(
      tester.getSize(find.byKey(BetaUpdateIndicator.buttonKey)),
      const Size(360, BetaUpdateIndicator.height),
    );
  });

  testWidgets('simplifies compact content at accessibility text scale', (
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

    await tester.pumpWidget(
      _host(controller, width: 360, textScaler: const TextScaler.linear(2)),
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

    expect(tester.takeException(), isNull);
    expect(find.text('Version 0.1.0-beta.6 is ready'), findsOneWidget);
    expect(find.text('Update'), findsOneWidget);
    expect(find.text('DELTA UPDATE'), findsNothing);
    expect(find.text('2.5 MB patch  ·  saves 61 MB'), findsOneWidget);
    expect(
      tester.getSize(find.byKey(BetaUpdateIndicator.buttonKey)),
      const Size(360, 64),
    );
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
    expect(find.byKey(BetaUpdateIndicator.petalRainKey), findsNothing);
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
    expect(find.byKey(BetaUpdateIndicator.petalRainKey), findsNothing);
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
  double? width,
  TextScaler textScaler = TextScaler.noScaling,
  Future<void> Function()? onUpdateNow,
}) {
  const spec = StandardSpec.theme;
  return MaterialApp(
    theme: spec.materialTheme(),
    home: MediaQuery(
      data: MediaQueryData(
        disableAnimations: disableAnimations,
        textScaler: textScaler,
      ),
      child: ThemeSpecScope(
        spec: spec,
        child: Scaffold(
          body: Align(
            alignment: Alignment.bottomCenter,
            child: SizedBox(
              width: width ?? double.infinity,
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
