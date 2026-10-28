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

const _enabled = bool.fromEnvironment(
  'BSL_DIAGNOSTIC_RESOURCE_LEGACY_CANVAS',
  defaultValue: false,
);

void main() {
  test('Sakura restores only the Resource canvas, not shared canvas roles', () {
    const palette = SakuraNightGardenSpec.palette;
    expect(palette.resourceMapCanvas, const Color(0xFF141218));
    expect(palette.canvasDeep, const Color(0xFF0D0B0F));
    expect(palette.canvas, const Color(0xFF151414));
    expect(
      SakuraNightGardenSpec.theme.materialTheme().scaffoldBackgroundColor,
      palette.canvas,
    );
    for (final style in ResourceMapInterfaceStyle.values) {
      expect(
        resourceMapChromeThemeForPlannerTheme(
          SakuraNightGardenSpec.theme,
          interfaceStyle: style,
        ).canvas,
        const Color(0xFF141218),
      );
    }
  });

  test(
    'other themes and scene-derived palettes keep their previous canvas',
    () {
      final specs = <ThemeSpec>[
        IlluminatedLedgerSpec.theme,
        StandardSpec.theme,
        for (final mode in CraftMode.values)
          applicationThemeForAppearance(
            AppearanceSettings.classicDefaultsFor(mode),
          ),
      ];
      for (final spec in specs) {
        expect(spec.palette.resourceMapCanvas, spec.palette.canvasDeep);
        if (!_enabled) {
          for (final style in ResourceMapInterfaceStyle.values) {
            expect(
              resourceMapChromeThemeForPlannerTheme(
                spec,
                interfaceStyle: style,
              ).canvas,
              spec.palette.canvasDeep,
            );
          }
        }
      }
    },
  );

  test('canvas comparison does not combine capture or redraw diagnostics', () {
    expect(
      const bool.fromEnvironment('BSL_DIAGNOSTIC_RESOURCE_FRAME_CAPTURE'),
      isFalse,
    );
    expect(
      const bool.fromEnvironment('BSL_DIAGNOSTIC_RESOURCE_REDRAW'),
      isFalse,
    );
    expect(
      const bool.fromEnvironment('BSL_DIAGNOSTIC_EARLIER_RESOURCE_PILL_PAINT'),
      isFalse,
    );
  });

  for (final style in ResourceMapInterfaceStyle.values) {
    for (final spec in <ThemeSpec>[
      SakuraNightGardenSpec.theme,
      IlluminatedLedgerSpec.theme,
      StandardSpec.theme,
    ]) {
      test('${style.name}/${spec.id}: only canvas may differ', () {
        final base = style == ResourceMapInterfaceStyle.glassDock
            ? ResourceMapChromeThemeData.glassDock
            : ResourceMapChromeThemeData.ghostLedger;
        final p = spec.palette;
        // Pre-correction palette: only its canvas may differ from the result.
        final ordinary = base.withPalette(
          canvas: p.canvasDeep,
          surface: p.surface,
          raised: p.surfaceRaised,
          inset: p.surfaceInset,
          foreground: p.text,
          secondaryForeground: p.textMuted,
          primary: p.primary,
          primaryBright: p.primaryBright,
          trim: p.trim,
          trimBright: p.trimBright,
          positive: p.success,
          warning: p.warning,
          error: p.danger,
          shadow: p.shadow,
        );
        final actual = resourceMapChromeThemeForPlannerTheme(
          spec,
          interfaceStyle: style,
        );
        expect(base.canvas, const Color(0xFF141218));
        expect(actual.canvas, _enabled ? base.canvas : p.resourceMapCanvas);
        for (final opacity in [0.0, .25, .7, 1.0]) {
          final material = actual.withUiOpacity(opacity);
          expect(material.canvas, actual.canvas);
          expect(material.canvas.a, 1);
          expect(
            _allRolesExceptCanvas(material),
            _allRolesExceptCanvas(ordinary.withUiOpacity(opacity)),
          );
        }
      });
    }
  }
}

// Every stored role except canvas, plus derived brightness/control roles.
List<Object?> _allRolesExceptCanvas(ResourceMapChromeThemeData c) => [
  c.uiOpacity,
  c.variant,
  c.inputInset,
  c.controlInset,
  c.brightness,
  c.materialOpacity,
  c.paper,
  c.paperRaised,
  c.ink,
  c.text,
  c.muted,
  c.warmOutline,
  c.softOutline,
  c.primary,
  c.deepAccent,
  c.onPrimary,
  c.accent,
  c.positive,
  c.warning,
  c.error,
  c.chromeBase,
  c.chromeRaised,
  c.chromeHighlight,
  c.modeStripFadeColor,
  c.trimDeep,
  c.trimLine,
  c.trimWash,
  c.idleControlGradient,
  c.idleCompactGradient,
  c.hoverControlGradient,
  c.selectedControlGradient,
  c.selectedModeGradient,
  c.selectedCompactGradient,
  c.selectedInlineGradient,
  c.idleInlineGradient,
  c.idleSearchGradient,
  c.focusedSearchGradient,
  c.surfaceGradient,
  c.subtleSurfaceGradient,
  c.taskStripGradient,
  c.readingSurfaceGradient,
  c.edgeFadeGradient,
  c.contourColor,
  c.fleckColor,
  c.readingInk,
  c.readingMuted,
  c.readingOutline,
  c.idleShadow,
  c.selectedShadow,
  c.hoverShadow,
  c.surfaceShadows,
  c.subtleSurfaceShadows,
  c.headingFontFamily,
  c.commandRadius,
  c.controlRadius,
  c.toolRadius,
  c.inlineRadius,
  c.keycapRadius,
  c.compactRadius,
  c.surfaceRadius,
];
