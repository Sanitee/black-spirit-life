import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:bdo_craft_planner_flutter/domain/models/craft_mode.dart';
import 'package:bdo_craft_planner_flutter/domain/state/planner_state.dart';
import 'package:bdo_craft_planner_flutter/features/gathering/gathering_workspace.dart';
import 'package:bdo_craft_planner_flutter/features/resource_map/resource_map_theme_adapter.dart';
import 'package:bdo_craft_planner_flutter/visual/foundations/application_theme.dart';
import 'package:bdo_craft_planner_flutter/visual/foundations/theme_spec.dart';
import 'package:bdo_craft_planner_flutter/visual/illuminated_ledger/ledger_spec.dart';
import 'package:bdo_craft_planner_flutter/visual/sakura_night_garden/sakura_spec.dart';
import 'package:bdo_gathering_companion/src/ui/theme.dart';
import 'package:bdo_map_core/src/widgets/resource_map_copper_finish.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final themes = <String, ThemeSpec>{
    'sakura': SakuraNightGardenSpec.theme,
    'ledger': IlluminatedLedgerSpec.theme,
    'forest': applicationThemeForAppearance(
      AppearanceSettings.classicDefaultsFor(CraftMode.alchemy),
    ),
  };
  final contrastRows = <Map<String, Object>>[];

  for (final entry in themes.entries) {
    test('${entry.key}: both tabs use the same copper pigments and roles', () {
      final spec = entry.value;
      for (final percent in [0, 25, 60, 70, 100]) {
        final chrome = resourceMapChromeThemeForPlannerTheme(
          spec,
        ).withUiOpacity(percent / 100);
        final glass = CompanionGlassTheme.fromPercent(
          percent,
          visualPalette: gatheringPaletteForTheme(spec),
        );
        for (final selected in [false, true]) {
          final source = selected
              ? glass.selectedGradient
              : glass.controlGradient;
          final resource = resourceMapCopperFace(chrome, source);
          final gathering = glass.copperCardGradient(selected: selected);
          final resourceBay = resourceMapCopperBay(chrome, source);
          final gatheringBay = glass.copperBayGradient(source);
          final resourceHighlight = resourceMapCopperBay(
            chrome,
            source,
            highlighted: true,
          );
          final gatheringHighlight = glass.copperBayGradient(
            source,
            reflection: .85,
          );
          for (var index = 0; index <= 100; index++) {
            final t = index / 100;
            _sameRgb(_at(resource, t), _at(gathering, t));
            _sameRgb(_at(resourceBay, t), _at(gatheringBay, t));
            _sameRgb(_at(resourceHighlight, t), _at(gatheringHighlight, t));
            // New colour must not change either source's opacity response.
            expect(_at(resource, t).a, closeTo(_at(source, t).a, 1e-9));
            expect(_at(gathering, t).a, closeTo(_at(source, t).a, 1e-9));
            expect(_at(gatheringBay, t).a, closeTo(_at(source, t).a, 1e-9));
            expect(
              _at(resourceHighlight, t).a,
              closeTo(_at(resourceBay, t).a, 1e-9),
            );
          }
          expect(resourceBay.begin, gatheringBay.begin);
          expect(resourceBay.end, gatheringBay.end);
        }
        expect(chrome.canvas, spec.palette.resourceMapCanvas);
        expect(chrome.ink, spec.palette.text);
        expect(glass.colors.ink, spec.palette.text);
        expect(
          glass.colors.muted,
          Color.lerp(spec.palette.textMuted, spec.palette.text, .27),
        );
        expect(glass.colors.ink.a, 1);
        expect(glass.colors.muted.a, 1);
      }
    });

    test('${entry.key}: copper reading contrast is recorded honestly', () {
      final spec = entry.value;
      for (final percent in [60, 70, 100]) {
        final glass = CompanionGlassTheme.fromPercent(
          percent,
          visualPalette: gatheringPaletteForTheme(spec),
        );
        for (final backdrop in <String, Color>{
          'dark': const Color(0xFF141218),
          'teal': const Color(0xFF286967),
          'sand': const Color(0xFFE2CCA2),
        }.entries) {
          var nameContrast = double.infinity;
          var captionContrast = double.infinity;
          final gradient = glass.copperCardGradient();
          // Reading area excludes the narrow top rim and bottom return.
          for (var sample = 20; sample <= 82; sample++) {
            final colour = Color.alphaBlend(
              _at(gradient, sample / 100),
              backdrop.value,
            );
            nameContrast = math.min(
              nameContrast,
              _contrast(glass.colors.ink, colour),
            );
            captionContrast = math.min(
              captionContrast,
              _contrast(glass.colors.muted, colour),
            );
          }
          contrastRows.add({
            'theme': entry.key,
            'opacityPercent': percent,
            'backdrop': backdrop.key,
            'minimumNameContrast': nameContrast,
            'minimumCaptionContrast': captionContrast,
          });
          if (percent == 100) {
            expect(nameContrast, greaterThanOrEqualTo(4.5));
            expect(captionContrast, greaterThanOrEqualTo(4.5));
          }
        }
      }
    });
  }

  tearDownAll(() async {
    final directory = Platform.environment['OPPORTUNITIES_THEME_CAPTURE_DIR'];
    if (directory == null) return;
    await Directory(directory).create(recursive: true);
    await File('$directory/copper-inlay-reading-contrast.json').writeAsString(
      const JsonEncoder.withIndent('  ').convert({
        'note':
            'Representative compositing samples, not a guarantee for every '
            'terrain colour or user-selected opacity. Opaque reading areas '
            'are checked at 4.5:1; transparent values are reported, not hidden.',
        'results': contrastRows,
      }),
    );
  });
}

Color _at(LinearGradient gradient, double t) {
  final stops =
      gradient.stops ??
      [
        for (var i = 0; i < gradient.colors.length; i++)
          i / (gradient.colors.length - 1),
      ];
  for (var i = 1; i < stops.length; i++) {
    if (t <= stops[i]) {
      return Color.lerp(
        gradient.colors[i - 1],
        gradient.colors[i],
        (t - stops[i - 1]) / (stops[i] - stops[i - 1]),
      )!;
    }
  }
  return gradient.colors.last;
}

void _sameRgb(Color a, Color b) {
  for (final difference in [
    (a.r - b.r).abs(),
    (a.g - b.g).abs(),
    (a.b - b.b).abs(),
  ]) {
    // The hosts insert their own alpha stops into the baked reflection. Their
    // piecewise interpolation can differ fractionally, but never by a pixel
    // channel step in the visible pigment.
    expect(difference, lessThanOrEqualTo(1 / 255));
  }
}

double _contrast(Color a, Color b) {
  final first = a.computeLuminance(), second = b.computeLuminance();
  return (math.max(first, second) + .05) / (math.min(first, second) + .05);
}
