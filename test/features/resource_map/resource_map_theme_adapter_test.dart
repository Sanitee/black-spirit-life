import 'package:bdo_craft_planner_flutter/domain/models/craft_mode.dart';
import 'package:bdo_craft_planner_flutter/domain/state/planner_state.dart';
import 'package:bdo_craft_planner_flutter/features/resource_map/resource_map_theme_adapter.dart';
import 'package:bdo_craft_planner_flutter/visual/foundations/application_theme.dart';
import 'package:bdo_craft_planner_flutter/visual/foundations/theme_spec.dart';
import 'package:bdo_craft_planner_flutter/visual/illuminated_ledger/ledger_spec.dart';
import 'package:bdo_craft_planner_flutter/visual/sakura_night_garden/sakura_spec.dart';
import 'package:bdo_craft_planner_flutter/visual/standard/standard_spec.dart';
import 'package:bdo_map_core/bdo_map_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final style in ResourceMapInterfaceStyle.values) {
    for (final spec in <ThemeSpec>[
      SakuraNightGardenSpec.theme,
      IlluminatedLedgerSpec.theme,
      StandardSpec.theme,
    ]) {
      test(
        '${style.name} follows ${spec.id}, preserving geometry and alpha',
        () {
          final base = style == ResourceMapInterfaceStyle.glassDock
              ? ResourceMapChromeThemeData.glassDock
              : ResourceMapChromeThemeData.ghostLedger;
          final chrome = resourceMapChromeThemeForPlannerTheme(
            spec,
            interfaceStyle: style,
          );
          expect(chrome.primary, spec.palette.primary);
          expect(chrome.ink, spec.palette.text);
          expect(chrome.readingInk, spec.palette.text);
          expect(chrome.chromeRaised, spec.palette.surfaceRaised);
          expect(chrome.controlInset, spec.palette.surfaceInset);
          final a = chrome.primary.computeLuminance() + .05;
          final b = chrome.onPrimary.computeLuminance() + .05;
          expect(a > b ? a / b : b / a, greaterThanOrEqualTo(4.5));
          expect(chrome.variant, base.variant);
          expect(chrome.headingFontFamily, base.headingFontFamily);
          expect(chrome.surfaceRadius, base.surfaceRadius);
          expect(chrome.controlRadius, base.controlRadius);
          expect(chrome.idleShadow.blurRadius, base.idleShadow.blurRadius);
          for (final opacity in [0.0, .25, .6, 1.0]) {
            final material = chrome.withUiOpacity(opacity);
            final original = base.withUiOpacity(opacity);
            expect(
              material.surfaceGradient.colors.map((c) => c.a),
              original.surfaceGradient.colors.map((c) => c.a),
            );
            expect(
              material.readingSurfaceGradient.colors.map((c) => c.a),
              original.readingSurfaceGradient.colors.map((c) => c.a),
            );
            expect(material.ink.a, 1);
            expect(material.readingInk, spec.palette.text);
            expect(material.withUiOpacity(1).chromeRaised.a, 1);
          }
        },
      );
    }
  }
  test('Ledger uses light Material; Sakura and Standard remain dark', () {
    expect(
      resourceMapChromeThemeForPlannerTheme(
        IlluminatedLedgerSpec.theme,
      ).brightness,
      Brightness.light,
    );
    expect(
      resourceMapChromeThemeForPlannerTheme(
        SakuraNightGardenSpec.theme,
      ).brightness,
      Brightness.dark,
    );
    expect(
      resourceMapChromeThemeForPlannerTheme(StandardSpec.theme).brightness,
      Brightness.dark,
    );
  });
  test('Standard map colours use shared scene-aware appearance', () {
    final appearance = AppearanceSettings.classicDefaultsFor(CraftMode.alchemy);
    final spec = applicationThemeForAppearance(appearance);
    final chrome = resourceMapChromeThemeForPlannerTheme(spec);
    expect(chrome.chromeBase, spec.palette.surface);
    expect(chrome.primary, spec.palette.primary);
    expect(
      chrome.chromeBase,
      isNot(ResourceMapChromeThemeData.fieldAtlas.chromeBase),
    );
  });
}
