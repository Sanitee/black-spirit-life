import 'package:bdo_craft_planner_flutter/app/app.dart';
import 'package:bdo_craft_planner_flutter/visual/illuminated_ledger/ledger_spec.dart';
import 'package:bdo_craft_planner_flutter/visual/sakura_night_garden/sakura_spec.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/application_test_harness.dart';

typedef _Family = ({String name, String? background});

void main() {
  const families = <_Family>[
    (name: 'standard', background: null),
    (name: 'ledger', background: IlluminatedLedgerSpec.backgroundId),
    (name: 'sakura', background: SakuraNightGardenSpec.backgroundId),
  ];
  const sizes = <Size>[
    Size(1200, 752),
    Size(1340, 820),
    Size(1360, 820),
    Size(1380, 840),
    Size(1470, 900),
    Size(1490, 900),
    Size(1500, 940),
  ];

  for (final family in families) {
    for (final size in sizes) {
      testWidgets(
        '${family.name} workspace ${size.width}x${size.height}',
        (tester) => _capture(
          tester,
          family: family,
          logicalSize: size,
          fileName:
              'workspace_${family.name}_${size.width.toInt()}x${size.height.toInt()}.png',
        ),
      );
    }

    for (final dpr in const <double>[1.25, 1.5, 2]) {
      testWidgets(
        '${family.name} workspace at ${dpr}x Windows scale',
        (tester) => _capture(
          tester,
          family: family,
          logicalSize: const Size(1200, 752),
          devicePixelRatio: dpr,
          fileName:
              'workspace_${family.name}_1200x752_dpr${(dpr * 100).round()}.png',
        ),
      );
    }

    testWidgets(
      '${family.name} workspace at 200% text scale',
      (tester) => _capture(
        tester,
        family: family,
        logicalSize: const Size(1200, 752),
        textScaleFactor: 2,
        fileName: 'workspace_${family.name}_1200x752_text200.png',
      ),
    );
  }
}

Future<void> _capture(
  WidgetTester tester, {
  required _Family family,
  required Size logicalSize,
  required String fileName,
  double devicePixelRatio = 1,
  double textScaleFactor = 1,
}) async {
  const goldenRoot = ValueKey<String>('golden-workspace-root');
  configureApplicationTestSurface(
    tester,
    logicalSize,
    devicePixelRatio: devicePixelRatio,
    textScaleFactor: textScaleFactor,
  );
  final harness = (await tester.runAsync(
    () => ApplicationTestHarness.create(
      backgroundId: family.background ?? 'greenhouse',
    ),
  ))!;
  try {
    await tester.pumpWidget(
      RepaintBoundary(
        key: goldenRoot,
        child: BdoCraftPlannerApp(
          applicationFuture: Future.value(harness.bundle),
          marketGateway: const EmptyMarketGateway(),
        ),
      ),
    );
    await _pumpWorkspace(tester);
    if (family.background == IlluminatedLedgerSpec.backgroundId) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 160)),
      );
      await _pumpWorkspace(tester);
    }
    expect(tester.takeException(), isNull);
    await expectLater(find.byKey(goldenRoot), matchesGoldenFile(fileName));
  } finally {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await tester.runAsync(harness.dispose);
  }
}

Future<void> _pumpWorkspace(WidgetTester tester) async {
  for (var index = 0; index < 5; index++) {
    await tester.pump(const Duration(milliseconds: 80));
  }
}
