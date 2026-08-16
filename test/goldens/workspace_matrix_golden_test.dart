import 'package:bdo_craft_planner_flutter/app/app.dart';
import 'package:bdo_craft_planner_flutter/domain/models/craft_mode.dart';
import 'package:bdo_craft_planner_flutter/visual/illuminated_ledger/ledger_spec.dart';
import 'package:bdo_craft_planner_flutter/visual/sakura_night_garden/sakura_spec.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/application_test_harness.dart';

typedef _ScreenCase = ({CraftMode mode, String view, String name});

void main() {
  const goldenRoot = ValueKey<String>('matrix-golden-workspace-root');
  const screens = <_ScreenCase>[
    (mode: CraftMode.alchemy, view: 'plan', name: 'alchemy_planner'),
    (mode: CraftMode.alchemy, view: 'bonus', name: 'alchemy_bonus'),
    (mode: CraftMode.alchemy, view: 'inventory', name: 'alchemy_inventory'),
    (mode: CraftMode.alchemy, view: 'editor', name: 'alchemy_editor'),
    (mode: CraftMode.alchemy, view: 'appearance', name: 'alchemy_appearance'),
    (mode: CraftMode.alchemy, view: 'data', name: 'alchemy_data'),
    (mode: CraftMode.cooking, view: 'plan', name: 'cooking_planner'),
    (mode: CraftMode.cooking, view: 'bonus', name: 'cooking_bonus'),
    (mode: CraftMode.cooking, view: 'inventory', name: 'cooking_inventory'),
    (mode: CraftMode.cooking, view: 'editor', name: 'cooking_editor'),
    (mode: CraftMode.cooking, view: 'appearance', name: 'cooking_appearance'),
    (mode: CraftMode.cooking, view: 'data', name: 'cooking_data'),
    (mode: CraftMode.processing, view: 'plan', name: 'processing_planner'),
    (
      mode: CraftMode.processing,
      view: 'inventory',
      name: 'processing_inventory',
    ),
    (mode: CraftMode.processing, view: 'editor', name: 'processing_editor'),
    (
      mode: CraftMode.processing,
      view: 'appearance',
      name: 'processing_appearance',
    ),
    (mode: CraftMode.processing, view: 'data', name: 'processing_data'),
  ];
  const families = <({String name, String? background})>[
    (name: 'standard', background: null),
    (name: 'ledger', background: IlluminatedLedgerSpec.backgroundId),
    (name: 'sakura', background: SakuraNightGardenSpec.backgroundId),
  ];
  const sizes = <Size>[Size(1200, 752), Size(1500, 940)];

  for (final family in families) {
    for (final screen in screens) {
      for (final size in sizes) {
        testWidgets(
          '${family.name} ${screen.name} ${size.width}x${size.height} visual baseline',
          (tester) async {
            configureApplicationTestSurface(tester, size);
            final harness = (await tester.runAsync(
              () => ApplicationTestHarness.create(
                backgroundId:
                    family.background ??
                    switch (screen.mode) {
                      CraftMode.alchemy => 'greenhouse',
                      CraftMode.cooking => 'hearth',
                      CraftMode.processing => 'tide',
                    },
                activeMode: screen.mode,
                view: screen.view,
                showDeleteTools: true,
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
              await _pumpFrames(tester);
              // Image-heavy screens always receive a decode window so a cold
              // focused run and the complete warm-cache matrix capture the same
              // finished frame.
              if (family.background == IlluminatedLedgerSpec.backgroundId ||
                  family.background == SakuraNightGardenSpec.backgroundId ||
                  (family.background == null &&
                      (screen.view == 'inventory' ||
                          screen.view == 'editor' ||
                          screen.view == 'data' ||
                          screen.view == 'appearance'))) {
                await tester.runAsync(
                  () => Future<void>.delayed(const Duration(milliseconds: 500)),
                );
                await _pumpFrames(tester);
              }
              await expectLater(
                find.byKey(goldenRoot),
                matchesGoldenFile(
                  'matrix_${family.name}_${screen.name}_${size.width.toInt()}x${size.height.toInt()}.png',
                ),
              );
            } finally {
              await tester.pumpWidget(const SizedBox.shrink());
              await tester.pump();
              await tester.runAsync(harness.dispose);
            }
          },
        );
      }
    }
  }
}

Future<void> _pumpFrames(WidgetTester tester) async {
  for (var index = 0; index < 5; index++) {
    await tester.pump(const Duration(milliseconds: 80));
  }
}
