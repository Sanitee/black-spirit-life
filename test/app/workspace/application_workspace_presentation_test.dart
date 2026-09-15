import 'package:bdo_craft_planner_flutter/app/appearance/appearance_actions.dart';
import 'package:bdo_craft_planner_flutter/app/window/app_title_bar_visual.dart';
import 'package:bdo_craft_planner_flutter/app/workspace/application_workspace_presentation.dart';
import 'package:bdo_craft_planner_flutter/domain/models/craft_mode.dart';
import 'package:bdo_craft_planner_flutter/features/opportunities/opportunities_visuals.dart';
import 'package:bdo_craft_planner_flutter/visual/visual.dart';
import 'package:bdo_map_core/bdo_map_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/application_test_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'all destinations use their own palette without changing appearance',
    () async {
      final h = await ApplicationTestHarness.create(
        backgroundId: 'sakura-night-garden',
      );
      final presentation = ApplicationWorkspacePresentationController(
        h.bundle.controller,
      );
      try {
        final original = h.bundle.controller.documentSnapshot;
        expect(presentation.value.spec, same(SakuraNightGardenSpec.theme));
        expect(presentation.value.titleVisual, isNull);
        for (final (destination, visual) in [
          (
            ApplicationWorkspaceDestination.opportunities,
            AppTitleBarVisual.opportunities,
          ),
          (
            ApplicationWorkspaceDestination.resourceMap,
            AppTitleBarVisual.resourceMap,
          ),
          (
            ApplicationWorkspaceDestination.gathering,
            AppTitleBarVisual.gathering,
          ),
          (ApplicationWorkspaceDestination.fishMap, AppTitleBarVisual.fishMap),
        ]) {
          presentation.select(destination);
          final value = presentation.value;
          expect(value.titleVisual, same(visual));
          expect(value.spec.palette.text, visual.foreground);
          expect(value.spec.palette.primary, visual.tabAccent);
          expect(value.spec.geometry.titleStripHeight, 40);
          expect(value.standardSettings.rainbow, isFalse);
          expect(value.spec.motion.supportsOrnament, isFalse);
          expect(
            (value.spec.materials.surfaceRaised as LinearGradient).colors.every(
              (color) => color.a == 1,
            ),
            isTrue,
          );
          expect(h.bundle.controller.documentSnapshot, same(original));
        }
        presentation.select(ApplicationWorkspaceDestination.opportunities);
        expect(
          presentation.value.spec.palette,
          same(OpportunitiesVisualSpec.palette),
        );
        expect(
          presentation.value.spec.materials.surfaceRaised,
          OpportunitiesVisualSpec.overlay,
        );
        presentation.select(ApplicationWorkspaceDestination.planner);
        expect(presentation.value.spec, same(SakuraNightGardenSpec.theme));
        expect(h.bundle.controller.documentSnapshot, same(original));
      } finally {
        presentation.dispose();
        await h.dispose();
      }
    },
  );

  test(
    'live appearance and map tint update only the active shell presentation',
    () async {
      final h = await ApplicationTestHarness.create(
        backgroundId: 'sakura-night-garden',
      );
      final app = h.bundle.controller;
      final presentation = ApplicationWorkspacePresentationController(app);
      try {
        var changes = 0;
        presentation.addListener(() => changes++);
        app.active.commitAmount('123');
        expect(changes, 0, reason: 'Planning changes must not rebuild chrome.');
        presentation.select(ApplicationWorkspaceDestination.opportunities);
        changes = 0;
        app.updateDocument(
          (document) => AppearanceActions.selectSharedBackground(
            document,
            'illuminated-ledger',
          ),
        );
        app.setResourceMapInterfaceStyle(ResourceMapInterfaceStyle.ghostLedger);
        app.setResourceMapUiOpacity(0);
        expect(changes, 0);
        expect(
          presentation.value.titleVisual,
          same(AppTitleBarVisual.opportunities),
        );
        presentation.select(ApplicationWorkspaceDestination.resourceMap);
        expect(
          presentation.value.titleVisual,
          same(AppTitleBarVisual.resourceMapGhost),
        );
        expect(
          presentation.value.spec.palette.primary,
          ResourceMapChromeThemeData.ghostLedger.primary,
        );
        final mapPresentation = presentation.value;
        app.setResourceMapUiOpacity(1);
        expect(
          presentation.value,
          same(mapPresentation),
          reason: 'Reading chrome does not inherit map transparency.',
        );
        app.setResourceMapInterfaceStyle(ResourceMapInterfaceStyle.glassDock);
        expect(
          presentation.value.titleVisual,
          same(AppTitleBarVisual.resourceMap),
        );
        presentation.select(ApplicationWorkspaceDestination.planner);
        expect(presentation.value.spec, same(IlluminatedLedgerSpec.theme));
        app.updateDocument(
          (document) => AppearanceActions.selectSharedBackground(
            document,
            'sakura-night-garden',
          ),
        );
        expect(presentation.value.spec, same(SakuraNightGardenSpec.theme));
        app.switchMode(CraftMode.cooking);
        expect(presentation.value.spec, same(SakuraNightGardenSpec.theme));
      } finally {
        presentation.dispose();
        await h.dispose();
      }
    },
  );
}
