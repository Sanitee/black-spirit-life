import 'package:bdo_craft_planner_flutter/app/appearance/appearance_actions.dart';
import 'package:bdo_craft_planner_flutter/app/window/app_title_bar_visual.dart';
import 'package:bdo_craft_planner_flutter/app/workspace/application_appearance_theme.dart';
import 'package:bdo_craft_planner_flutter/app/workspace/application_workspace_presentation.dart';
import 'package:bdo_craft_planner_flutter/domain/models/craft_mode.dart';
import 'package:bdo_craft_planner_flutter/visual/foundations/application_theme.dart';
import 'package:bdo_craft_planner_flutter/visual/visual.dart';
import 'package:bdo_map_core/bdo_map_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/application_test_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'all non-Fish destinations follow Appearance without writing state',
    () async {
      final h = await ApplicationTestHarness.create(
        backgroundId: 'sakura-night-garden',
      );
      final app = h.bundle.controller;
      final presentation = ApplicationWorkspacePresentationController(app);
      try {
        for (final background in [
          'sakura-night-garden',
          'illuminated-ledger',
          'greenhouse',
          'hearth',
          'plain-rose',
        ]) {
          app.updateDocument(
            (document) =>
                AppearanceActions.selectSharedBackground(document, background),
          );
          final original = app.documentSnapshot;
          for (final destination in ApplicationWorkspaceDestination.values) {
            presentation.select(destination);
            final value = presentation.value;
            if (destination == ApplicationWorkspaceDestination.fishMap) {
              expect(value.titleVisual, same(AppTitleBarVisual.fishMap));
              expect(
                value.spec.palette.text,
                AppTitleBarVisual.fishMap.foreground,
              );
              expect(
                value.spec.palette.primary,
                AppTitleBarVisual.fishMap.tabAccent,
              );
              expect(
                value.spec.id,
                'application-chrome-${AppTitleBarVisual.fishMap.id}',
              );
            } else {
              expect(value.titleVisual, isNull);
              expect(value.standardSettings.backgroundId, background);
              final expected =
                  destination == ApplicationWorkspaceDestination.planner
                  ? RetainedThemeRegistry.resolve(backgroundId: background)
                  : applicationThemeForAppearance(
                      app.active.state.value.appearance,
                    );
              expect(value.spec, same(expected));
            }
            expect(app.documentSnapshot, same(original));
          }
        }
      } finally {
        presentation.dispose();
        await h.dispose();
      }
    },
  );

  test(
    'live appearance changes shell but planning and map preferences do not',
    () async {
      final h = await ApplicationTestHarness.create(
        backgroundId: 'sakura-night-garden',
      );
      final app = h.bundle.controller;
      final presentation = ApplicationWorkspacePresentationController(app);
      final theme = ApplicationAppearanceThemeController(app);
      try {
        var chromeChanges = 0, themeChanges = 0;
        presentation.addListener(() => chromeChanges++);
        theme.addListener(() => themeChanges++);
        app.active.commitAmount('123');
        expect(chromeChanges, 0);
        expect(themeChanges, 0);
        presentation.select(ApplicationWorkspaceDestination.opportunities);
        chromeChanges = 0;
        app.updateDocument(
          (document) => AppearanceActions.selectSharedBackground(
            document,
            'illuminated-ledger',
          ),
        );
        expect(chromeChanges, 1);
        expect(themeChanges, 1);
        expect(presentation.value.spec, same(IlluminatedLedgerSpec.theme));
        expect(theme.value, same(IlluminatedLedgerSpec.theme));
        app.setResourceMapInterfaceStyle(ResourceMapInterfaceStyle.ghostLedger);
        app.setResourceMapUiOpacity(0);
        expect(chromeChanges, 1);
        expect(themeChanges, 1);
        presentation.select(ApplicationWorkspaceDestination.fishMap);
        final fish = presentation.value;
        chromeChanges = 0;
        app.updateDocument(
          (document) =>
              AppearanceActions.selectSharedBackground(document, 'greenhouse'),
        );
        expect(presentation.value, same(fish));
        expect(chromeChanges, 0);
        expect(themeChanges, 2);
        app.switchMode(CraftMode.cooking);
        expect(presentation.value, same(fish));
        expect(themeChanges, 2);
        presentation.select(ApplicationWorkspaceDestination.gathering);
        expect(presentation.value.spec, same(theme.value));
        expect(
          presentation.value.spec.palette.primary,
          StandardSpec.accentBrush(158),
        );
      } finally {
        theme.dispose();
        presentation.dispose();
        await h.dispose();
      }
    },
  );

  test(
    'scene palette cache is bounded and keeps readable semantic roles',
    () async {
      final h = await ApplicationTestHarness.create(backgroundId: 'greenhouse');
      try {
        final original = h.bundle.controller.active.state.value.appearance;
        for (final background in [
          ...StandardSpec.scenes.keys,
          ...StandardSpec.plainBackgrounds.keys,
        ]) {
          final appearance = AppearanceActions.applySceneDefaults(
            original,
            background,
          );
          final spec = applicationThemeForAppearance(appearance);
          expect(applicationThemeForAppearance(appearance), same(spec));
          for (final surface in [
            spec.palette.surface,
            spec.palette.surfaceRaised,
            spec.palette.surfaceInset,
          ]) {
            expect(
              _contrast(spec.palette.text, surface),
              greaterThanOrEqualTo(4.5),
              reason: background,
            );
            expect(
              _contrast(spec.palette.textMuted, surface),
              greaterThanOrEqualTo(4.5),
              reason: '$background secondary',
            );
          }
        }
        final first = applicationThemeForAppearance(
          AppearanceActions.copyAppearance(original, accentHue: 1),
        );
        for (var hue = 2; hue < 40; hue++) {
          applicationThemeForAppearance(
            AppearanceActions.copyAppearance(
              original,
              accentHue: hue.toDouble(),
            ),
          );
        }
        final reloaded = applicationThemeForAppearance(
          AppearanceActions.copyAppearance(original, accentHue: 1),
        );
        expect(
          reloaded,
          isNot(same(first)),
          reason: 'Old slider colours leave the bounded cache.',
        );
        expect(reloaded.palette.primary, first.palette.primary);
        final rose = applicationThemeForAppearance(
          AppearanceActions.copyAppearance(original, background: 'plain-rose'),
        );
        final green = applicationThemeForAppearance(original);
        expect(rose.palette.surface, isNot(green.palette.surface));
      } finally {
        await h.dispose();
      }
    },
  );
}

double _contrast(Color first, Color second) {
  final a = first.computeLuminance(), b = second.computeLuminance();
  return a > b ? (a + .05) / (b + .05) : (b + .05) / (a + .05);
}
