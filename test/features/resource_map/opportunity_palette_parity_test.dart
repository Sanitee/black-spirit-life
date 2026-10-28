import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:bdo_craft_planner_flutter/domain/models/craft_mode.dart';
import 'package:bdo_craft_planner_flutter/domain/state/planner_state.dart';
import 'package:bdo_craft_planner_flutter/features/gathering/gathering_workspace.dart';
import 'package:bdo_craft_planner_flutter/features/opportunities/opportunities_glass_material.dart';
import 'package:bdo_craft_planner_flutter/features/opportunities/opportunities_visuals.dart';
import 'package:bdo_craft_planner_flutter/features/opportunities/opportunity_glass_finish.dart';
import 'package:bdo_craft_planner_flutter/features/resource_map/resource_map_theme_adapter.dart';
import 'package:bdo_craft_planner_flutter/visual/components/app_surface.dart';
import 'package:bdo_craft_planner_flutter/visual/foundations/application_theme.dart';
import 'package:bdo_craft_planner_flutter/visual/foundations/theme_spec.dart';
import 'package:bdo_craft_planner_flutter/visual/illuminated_ledger/ledger_spec.dart';
import 'package:bdo_craft_planner_flutter/visual/sakura_night_garden/sakura_spec.dart';
import 'package:bdo_gathering_companion/src/ui/theme.dart';
import 'package:bdo_map_core/bdo_map_core.dart';
import 'package:bdo_map_core/src/widgets/resource_map_atlas_shell.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _captureKey = ValueKey('opportunity-palette-parity-capture');
const _art = 'packages/bdo_map_core/assets/images/menu_artwork/iron_ore.webp';
const _samples = <String, Color>{
  'dark': Color(0xFF141218),
  'teal': Color(0xFF286967),
  'sand': Color(0xFFE2CCA2),
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final themes = <String, ThemeSpec>{
    'sakura': SakuraNightGardenSpec.theme,
    'ledger': IlluminatedLedgerSpec.theme,
    'forest': applicationThemeForAppearance(
      AppearanceSettings.classicDefaultsFor(CraftMode.alchemy),
    ),
  };

  setUpAll(() async {
    final directory = Platform.environment['OPPORTUNITIES_THEME_CAPTURE_DIR'];
    if (directory != null) {
      await Directory(directory).create(recursive: true);
      await File('$directory/gathering-palettes.json').writeAsString(
        jsonEncode({
          for (final entry in themes.entries)
            entry.key: gatheringPaletteForTheme(entry.value).encode(),
        }),
      );
    }
  });

  for (final entry in themes.entries) {
    final spec = entry.value;
    final finish = OpportunityGlassFinish.forSpec(
      OpportunitiesVisualSpec.forAppearance(spec),
    );
    test('${entry.key}: opaque reading faces match actual Opportunities', () {
      final chrome = resourceMapChromeThemeForPlannerTheme(spec);
      final gathering = CompanionGlassTheme.fromPercent(
        100,
        visualPalette: gatheringPaletteForTheme(spec),
      );
      final resource = resourceMapRaisedSurfaceGradient(
        chrome,
        const LinearGradient(colors: [Colors.black, Colors.black]),
      );
      for (final t in [0.0, .08, .16, .35, .55, .8, 1.0]) {
        final expected = _at(finish.cardSurface, t);
        _nearRgb(_at(resource, t), expected, 'Resource t=$t');
        _nearRgb(_at(gathering.controlGradient, t), expected, 'Gathering t=$t');
      }
      expect(gathering.colors.rim, spec.palette.trimBright);
      expect(chrome.accent, spec.palette.trimBright);
      expect(chrome.canvas, spec.palette.resourceMapCanvas);
      expect(chrome.ink, spec.palette.text);
      expect(chrome.muted, spec.palette.textMuted);
      expect(gathering.colors.ink, spec.palette.text);
      expect(
        gathering.colors.muted,
        Color.lerp(spec.palette.textMuted, spec.palette.text, .27),
      );
    });

    test(
      '${entry.key}: stronger material retains saved opacity and foreground',
      () {
        for (final percent in [0, 25, 60, 70, 100]) {
          final gathering = CompanionGlassTheme.fromPercent(
            percent,
            visualPalette: gatheringPaletteForTheme(spec),
          );
          final original = CompanionGlassTheme.fromPercent(percent);
          expect(gathering.opacityPercent, percent);
          for (final material in [
            (gathering.controlGradient, original.controlGradient),
            (gathering.selectedGradient, original.selectedGradient),
            (gathering.hoverGradient, original.hoverGradient),
          ]) {
            for (final t in [0.0, .12, .16, .5, .55, .72, 1.0]) {
              expect(
                _at(material.$1, t).a,
                greaterThanOrEqualTo(_at(material.$2, t).a - .000001),
              );
              expect(_at(material.$1, t).a, lessThanOrEqualTo(1));
            }
          }
          expect(gathering.colors.ink.a, 1);
          expect(gathering.colors.muted.a, 1);
          for (final style in ResourceMapInterfaceStyle.values) {
            final chrome = resourceMapChromeThemeForPlannerTheme(
              spec,
              interfaceStyle: style,
            ).withUiOpacity(percent / 100);
            for (final source in [
              chrome.readingSurfaceGradient,
              chrome.idleControlGradient,
              chrome.selectedControlGradient,
            ]) {
              final rendered = resourceMapRaisedSurfaceGradient(chrome, source);
              for (final t in [0.0, .12, .16, .5, .55, .72, 1.0]) {
                expect(_at(rendered, t).a, closeTo(_at(source, t).a, .000001));
              }
            }
            expect(chrome.canvas, spec.palette.resourceMapCanvas);
            expect(chrome.ink, spec.palette.text);
            expect(chrome.muted, spec.palette.textMuted);
            expect(chrome.ink.a, 1);
            expect(chrome.muted.a, 1);
          }
        }
      },
    );

    test(
      '${entry.key}: transparent faces retain the exact reference pigments',
      () {
        final chrome = resourceMapChromeThemeForPlannerTheme(spec);
        for (final opacity in [.6, .7, .9, 1.0]) {
          final gathering = CompanionGlassTheme.fromPercent(
            (opacity * 100).round(),
            visualPalette: gatheringPaletteForTheme(spec),
          );
          final resource = resourceMapRaisedSurfaceGradient(
            chrome,
            LinearGradient(
              colors: [
                Colors.black.withValues(alpha: opacity),
                Colors.black.withValues(alpha: opacity),
              ],
            ),
          );
          for (final t in [0.0, .16, .55, 1.0]) {
            final target = _at(finish.cardSurface, t);
            for (final sample in <(String, Color, Color)>[
              (
                'Resource',
                _at(resource, t),
                chrome.brightness == Brightness.light
                    ? chrome.chromeBase.withAlpha(255)
                    : chrome.canvas,
              ),
              (
                'Gathering',
                _at(gathering.controlGradient, t),
                spec.palette.canvas,
              ),
            ]) {
              final before = Color.alphaBlend(
                target.withValues(alpha: sample.$2.a),
                sample.$3,
              );
              final after = Color.alphaBlend(sample.$2, sample.$3);
              _nearRgb(sample.$2, target, '${sample.$1} pigment t=$t');
              expect(
                _distance(after, target),
                lessThanOrEqualTo(_distance(before, target) + 2 / 255),
                reason: '${sample.$1}, alpha=${sample.$2.a}, t=$t',
              );
            }
          }
        }
      },
    );
  }

  test('Ledger transparent resource paper retains its warm chroma', () {
    final spec = themes['ledger']!;
    final chrome = resourceMapChromeThemeForPlannerTheme(spec);
    final target = _at(
      OpportunityGlassFinish.forSpec(
        OpportunitiesVisualSpec.forAppearance(spec),
      ).cardSurface,
      .55,
    );
    for (final alpha in [.6, .7]) {
      final pigment = resourceMapMaterialPigment(chrome, target, alpha);
      expect(pigment.a, closeTo(alpha, .000001));
      expect(pigment.r - pigment.b, greaterThanOrEqualTo(.10));
      expect(pigment.g - pigment.b, greaterThanOrEqualTo(.05));
      expect(pigment.withAlpha(255), isNot(Colors.white));
      final backdrop = chrome.chromeBase.withAlpha(255);
      final before = Color.alphaBlend(
        target.withValues(alpha: alpha),
        backdrop,
      );
      final after = Color.alphaBlend(pigment, backdrop);
      expect(
        _distance(after, target),
        lessThanOrEqualTo(_distance(before, target) + 2 / 255),
      );
      expect(chrome.canvas, spec.palette.resourceMapCanvas);
    }
    _nearRgb(
      resourceMapMaterialPigment(chrome, target, 1),
      target,
      'Opaque Ledger',
    );
  });

  test(
    'default-opacity terrain contrasts are recorded without an AA claim',
    () async {
      final spec = themes['sakura']!;
      final finish = OpportunityGlassFinish.forSpec(
        OpportunitiesVisualSpec.forAppearance(spec),
      );
      final chrome = resourceMapChromeThemeForPlannerTheme(
        spec,
      ).withUiOpacity(.7);
      final gathering = CompanionGlassTheme.fromPercent(
        60,
        visualPalette: gatheringPaletteForTheme(spec),
      );
      final resourceParent = resourceMapRaisedSurfaceGradient(
        chrome,
        chrome.surfaceGradient,
      );
      final rows = <Map<String, Object>>[];
      for (final backdrop in _samples.entries) {
        for (final state in ['normal', 'selected', 'hover']) {
          final active = state != 'normal';
          final alpha = chrome.materialOpacity * (active ? .66 : .48);
          final source = LinearGradient(
            colors: [
              Colors.black.withValues(alpha: alpha * .96),
              Colors.black.withValues(alpha: alpha * .98),
            ],
          );
          final mapFace = resourceMapRaisedSurfaceGradient(chrome, source);
          final gatherFace = state == 'selected'
              ? gathering.selectedGradient
              : state == 'hover'
              ? gathering.hoverGradient
              : gathering.controlGradient;
          final gatherBaseline = _uncompensatedGatheringFace(gathering, state);
          for (final feature in ['Resource', 'Gathering']) {
            var minimumName = double.infinity;
            var minimumCaption = double.infinity;
            var minimumBaselineCaption = double.infinity;
            for (var step = 0; step <= 20; step++) {
              final t = step / 20;
              final parent = feature == 'Resource'
                  ? _at(resourceParent, t)
                  : Colors.transparent;
              final face = _at(feature == 'Resource' ? mapFace : gatherFace, t);
              final composed = Color.alphaBlend(
                face,
                Color.alphaBlend(parent, backdrop.value),
              );
              final oldTarget = _at(
                feature == 'Resource' ? finish.cardSurface : gatherBaseline,
                t,
              );
              final baseline = Color.alphaBlend(
                oldTarget.withValues(alpha: face.a),
                Color.alphaBlend(
                  _at(finish.cardSurface, t).withValues(alpha: parent.a),
                  backdrop.value,
                ),
              );
              minimumName = math.min(
                minimumName,
                _contrast(spec.palette.text, composed),
              );
              minimumCaption = math.min(
                minimumCaption,
                _contrast(
                  feature == 'Gathering'
                      ? gathering.colors.muted
                      : spec.palette.textMuted,
                  composed,
                ),
              );
              minimumBaselineCaption = math.min(
                minimumBaselineCaption,
                _contrast(spec.palette.textMuted, baseline),
              );
            }
            rows.add({
              'feature': feature,
              'opacity': feature == 'Resource' ? .7 : .6,
              'state': state,
              'backdrop': backdrop.key,
              'captionForeground':
                  (feature == 'Gathering'
                          ? gathering.colors.muted
                          : spec.palette.textMuted)
                      .toARGB32()
                      .toRadixString(16),
              'nameContrast': minimumName,
              'captionContrast': minimumCaption,
              'uncompensatedStateCaptionContrast': minimumBaselineCaption,
              'nameMeets7': minimumName >= 7,
              'captionMeets4_5': minimumCaption >= 4.5,
            });
          }
        }
      }
      final directory = Platform.environment['OPPORTUNITIES_THEME_CAPTURE_DIR'];
      if (directory != null) {
        await File('$directory/terrain-contrast-audit.json').writeAsString(
          const JsonEncoder.withIndent('  ').convert({
            'note':
                'Paint-model audit: actual FieldDesk surface recipe plus its nested pill; Gathering spot control directly over terrain. Hosted surfaces now use direct Opportunities pigments and denser intermediate alpha, preserving saved opacity and endpoints. Gathering captions use a 27% blend toward main text for readability. The reference comparison uses original muted text at the same new material alpha, not a historical screenshot. Arbitrary terrain and minimum opacity cannot guarantee contrast. Full production home captures are checked separately.',
            'rows': rows,
          }),
        );
      }
      for (final row in rows) {
        final before = row['uncompensatedStateCaptionContrast']! as double;
        final after = row['captionContrast']! as double;
        expect(after, greaterThanOrEqualTo(before - .01), reason: '$row');
        if (before >= 4.5) {
          expect(after, greaterThanOrEqualTo(4.5), reason: '$row');
        }
      }
      for (final row in rows.where((row) => row['backdrop'] == 'teal')) {
        expect(
          row['captionContrast'],
          greaterThanOrEqualTo(4.5),
          reason: '$row',
        );
      }
      final dark = rows.where((row) => row['backdrop'] == 'dark');
      for (final row in dark) {
        expect(row['nameContrast'], greaterThanOrEqualTo(7), reason: '$row');
        expect(
          row['captionContrast'],
          greaterThanOrEqualTo(4.5),
          reason: '$row',
        );
      }
    },
  );

  test('all themed Gathering captions retain contrast on sampled terrain', () {
    final results = <Map<String, Object>>[];
    for (final entry in themes.entries) {
      final glass = CompanionGlassTheme.fromPercent(
        60,
        visualPalette: gatheringPaletteForTheme(entry.value),
      );
      final foreground = Color(glass.colors.muted.toARGB32());
      for (final state in {
        'normal': glass.controlGradient,
        'hover': glass.hoverGradient,
        'selected': glass.selectedGradient,
      }.entries) {
        for (final backdrop in _samples.entries) {
          var minimum = double.infinity;
          for (var step = 0; step <= 100; step++) {
            final surface = Color(
              Color.alphaBlend(
                _at(state.value, step / 100),
                backdrop.value,
              ).toARGB32(),
            );
            minimum = math.min(minimum, _contrast(foreground, surface));
          }
          final result = <String, Object>{
            'theme': entry.key,
            'state': state.key,
            'terrain': backdrop.key,
            'captionContrast': minimum,
          };
          results.add(result);
          expect(minimum, greaterThanOrEqualTo(4.5), reason: '$result');
        }
      }
    }
    final directory = Platform.environment['OPPORTUNITIES_THEME_CAPTURE_DIR'];
    if (directory != null) {
      File('$directory/gathering-caption-contrast.json').writeAsStringSync(
        const JsonEncoder.withIndent('  ').convert({
          'note':
              '8-bit compositing model at default 60% opacity on three representative terrain colours; not a guarantee for arbitrary terrain or lower user-selected opacity.',
          'results': results,
        }),
      );
    }
  });

  for (final entry in themes.entries) {
    for (final state in ['normal', 'selected', 'hover']) {
      testWidgets('${entry.key}: production material comparison $state', (
        tester,
      ) async {
        await tester.runAsync(_fonts);
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(1200, 780);
        addTearDown(tester.view.reset);
        await tester.pumpWidget(_comparison(entry.value, state));
        await tester.runAsync(() async {
          await Future<void>.delayed(const Duration(milliseconds: 100));
        });
        await tester.pumpAndSettle();
        final devices = <int>[];
        addTearDown(() async {
          for (final device in devices) {
            await tester.sendEventToBinding(
              PointerRemovedEvent(
                kind: PointerDeviceKind.mouse,
                device: device,
              ),
            );
          }
        });
        if (state == 'hover') {
          var device = 10;
          for (final sample in _samples.keys) {
            for (final feature in ['opportunity', 'resource']) {
              final position = tester.getCenter(
                find.byKey(ValueKey('$feature-$sample')),
              );
              devices.add(device);
              await tester.sendEventToBinding(
                PointerAddedEvent(
                  kind: PointerDeviceKind.mouse,
                  device: device,
                  position: position,
                ),
              );
              await tester.sendEventToBinding(
                PointerHoverEvent(
                  kind: PointerDeviceKind.mouse,
                  device: device,
                  position: position,
                ),
              );
              device++;
            }
          }
          await tester.pumpAndSettle();
        }
        expect(tester.takeException(), isNull);
        expect(find.byType(Image), findsNWidgets(9));
        for (final image in tester.widgetList<Image>(find.byType(Image))) {
          expect(image.color, isNull);
        }
        await _capture(tester, '${entry.key}-$state');
      });
    }
  }
}

Widget _comparison(ThemeSpec spec, String state) {
  final opportunity = OpportunitiesVisualSpec.forAppearance(spec);
  final finish = OpportunityGlassFinish.forSpec(opportunity);
  final chrome = resourceMapChromeThemeForPlannerTheme(spec).withUiOpacity(.7);
  final palette = gatheringPaletteForTheme(spec);
  return MaterialApp(
    theme: spec.materialTheme(),
    home: Scaffold(
      backgroundColor: spec.palette.canvas,
      body: RepaintBoundary(
        key: _captureKey,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Production material comparison · ${spec.displayName} · $state',
                style: TextStyle(
                  color: spec.palette.text,
                  fontFamily: 'Segoe UI',
                  fontSize: 18,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'Same sample content. Existing production widgets; not a proposed screen layout.',
                style: TextStyle(color: spec.palette.textMuted, fontSize: 13),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  for (final heading in [
                    'Opportunities · opaque',
                    'Resource · 70%',
                    'Gathering · 60%',
                  ])
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Text(
                          heading,
                          style: TextStyle(
                            color: spec.palette.text,
                            fontWeight: FontWeight.w600,
                            fontSize: 16,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              for (final sample in _samples.entries) ...[
                Text(
                  '${sample.key} backdrop',
                  style: TextStyle(color: spec.palette.textMuted, fontSize: 12),
                ),
                const SizedBox(height: 6),
                SizedBox(
                  height: 160,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _tile(
                        sample.value,
                        ThemeSpecScope(
                          spec: opportunity,
                          child: OpportunityCardMotion(
                            key: ValueKey('opportunity-${sample.key}'),
                            child: OpportunitySurface(
                              decoration: finish.card,
                              padding: EdgeInsets.zero,
                              role: AppSurfaceRole.card,
                              child: CustomPaint(
                                painter: OpportunityCraftCardRelief(
                                  finish: finish,
                                  artworkWidth: 56,
                                ),
                                child: _content(
                                  spec.palette.text,
                                  spec.palette.textMuted,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      _tile(
                        sample.value,
                        ResourceMapChromeTheme(
                          data: chrome,
                          child: ResourceMapJourneySurface(
                            title: 'Materials',
                            child: ResourceMapPill(
                              key: ValueKey('resource-${sample.key}'),
                              selected: state == 'selected',
                              leadingWidth: 56,
                              child: _content(chrome.ink, chrome.muted),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      _tile(
                        sample.value,
                        Theme(
                          data: companionTheme(
                            opacityPercent: 60,
                            visualPalette: palette,
                          ),
                          child: GlassControl(
                            selected: state == 'selected',
                            hovered: state == 'hover',
                            leadingWidth: 56,
                            child: _content(palette.ink, palette.muted),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
              ],
            ],
          ),
        ),
      ),
    ),
  );
}

Widget _tile(Color backdrop, Widget child) => Expanded(
  child: ColoredBox(
    color: backdrop,
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Center(child: child),
    ),
  ),
);

Widget _content(Color ink, Color muted) => SizedBox(
  height: 74,
  child: Row(
    children: [
      SizedBox(
        width: 56,
        child: Center(
          child: Image.asset(_art, width: 36, height: 36, fit: BoxFit.contain),
        ),
      ),
      const SizedBox(width: 10),
      Expanded(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Iron Ore',
              style: TextStyle(
                color: ink,
                fontFamily: 'Segoe UI',
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              'Sample secondary text',
              style: TextStyle(
                color: muted,
                fontFamily: 'Segoe UI',
                fontSize: 12.5,
              ),
            ),
          ],
        ),
      ),
      const SizedBox(width: 8),
    ],
  ),
);

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

// The baseline paint recipe before materialPigment is applied. The selected
// and hover states have different source tints; comparing all of them to the
// normal card face would falsely attribute their existing contrast to this edit.
LinearGradient _uncompensatedGatheringFace(
  CompanionGlassTheme glass,
  String state,
) {
  final accented = state != 'normal';
  final top =
      (state == 'selected'
              ? glass.active
              : state == 'hover'
              ? glass.hover
              : glass.row)
          .withAlpha(255);
  final middle = state == 'selected'
      ? glass.active.withAlpha(255)
      : state == 'hover'
      ? glass.panel.withAlpha(255)
      : glass.colors.surface;
  return LinearGradient(
    stops: const [0, .16, .55, 1],
    colors: [
      Color.alphaBlend(glass.colors.ink.withAlpha(accented ? 8 : 20), top),
      Color.alphaBlend(glass.colors.ink.withAlpha(accented ? 4 : 10), top),
      Color.lerp(middle, top, .48)!,
      Color.lerp(glass.colors.inset, middle, .70)!,
    ],
  );
}

double _distance(Color a, Color b) =>
    math.max((a.r - b.r).abs(), math.max((a.g - b.g).abs(), (a.b - b.b).abs()));
void _nearRgb(Color a, Color b, String reason) => expect(
  _distance(a, b),
  lessThanOrEqualTo(2 / 255),
  reason: '$reason: $a versus $b',
);
double _contrast(Color a, Color b) {
  final first = a.computeLuminance(), second = b.computeLuminance();
  return (math.max(first, second) + .05) / (math.min(first, second) + .05);
}

Future<void> _capture(WidgetTester tester, String name) async {
  final directory = Platform.environment['OPPORTUNITIES_THEME_CAPTURE_DIR'];
  if (directory == null) return;
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(_captureKey),
  );
  await tester.runAsync(() async {
    final image = await boundary.toImage();
    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      await File(
        '$directory/opportunity-parity-$name.png',
      ).writeAsBytes(data!.buffer.asUint8List());
    } finally {
      image.dispose();
    }
  });
}

Future<void> _fonts() async {
  if (!Platform.isWindows) return;
  final win = Platform.environment['WINDIR'] ?? r'C:\Windows';
  var sdk = File(Platform.resolvedExecutable).parent;
  while (!Directory(
    '${sdk.path}/bin/cache/artifacts/material_fonts',
  ).existsSync()) {
    if (sdk.parent.path == sdk.path) {
      throw StateError('Flutter fonts not found');
    }
    sdk = sdk.parent;
  }
  for (final family in <String, List<String>>{
    'Segoe UI': [
      '$win/Fonts/segoeui.ttf',
      '$win/Fonts/seguisb.ttf',
      '$win/Fonts/segoeuib.ttf',
    ],
    'Georgia': ['$win/Fonts/georgia.ttf', '$win/Fonts/georgiab.ttf'],
    'Roboto': [
      '${sdk.path}/bin/cache/artifacts/material_fonts/roboto-regular.ttf',
    ],
    'MaterialIcons': [
      '${sdk.path}/bin/cache/artifacts/material_fonts/materialicons-regular.otf',
    ],
  }.entries) {
    final loader = FontLoader(family.key);
    for (final file in family.value) {
      loader.addFont(File(file).readAsBytes().then(ByteData.sublistView));
    }
    await loader.load();
  }
}
