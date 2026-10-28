import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:bdo_craft_planner_flutter/domain/models/craft_mode.dart';
import 'package:bdo_craft_planner_flutter/domain/state/planner_state.dart';
import 'package:bdo_craft_planner_flutter/features/gathering/gathering_workspace.dart';
import 'package:bdo_craft_planner_flutter/features/resource_map/resource_map_theme_adapter.dart';
import 'package:bdo_craft_planner_flutter/visual/foundations/application_theme.dart';
import 'package:bdo_craft_planner_flutter/visual/illuminated_ledger/ledger_spec.dart';
import 'package:bdo_craft_planner_flutter/visual/sakura_night_garden/sakura_spec.dart';
import 'package:bdo_gathering_companion/src/ui/field_desk_materials.dart';
import 'package:bdo_gathering_companion/src/ui/theme.dart';
import 'package:bdo_map_core/src/widgets/resource_map_atlas_shell.dart';
import 'package:bdo_map_core/src/widgets/resource_map_chrome_theme.dart';
import 'package:bdo_map_core/src/widgets/resource_map_pill.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../packages/bdo_map_core/test/support/map_menu_capture.dart';

const _capture = ValueKey('map-gathering-material-capture');
const _panelKeys = ['map-material', 'gathering-map-material', 'desk-material'];
const _panelSize = Size(320, 360);

void main() {
  testWidgets('bounded shared-theme map and Gathering material cost', (
    tester,
  ) async {
    final directory = Platform.environment['MAP_GATHERING_MATERIAL_AUDIT_DIR'];
    final phase =
        Platform.environment['MAP_GATHERING_MATERIAL_PHASE'] ?? 'unspecified';
    final results = <Map<String, Object?>>[];
    final oldShadows = debugDisableShadows;
    debugDisableShadows = false;
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1088, 420);
    addTearDown(tester.view.reset);
    try {
      if (directory != null) {
        await tester.runAsync(loadMapMenuCaptureFonts);
      }
      for (final (name, spec) in [
        ('sakura', SakuraNightGardenSpec.theme),
        ('ledger', IlluminatedLedgerSpec.theme),
        (
          'greenhouse',
          applicationThemeForAppearance(
            AppearanceSettings.classicDefaultsFor(CraftMode.alchemy),
          ),
        ),
      ]) {
        for (final percent in [0, 60, 100]) {
          var taps = 0;
          final chrome = resourceMapChromeThemeForPlannerTheme(
            spec,
          ).withUiOpacity(percent / 100);
          final gathering = companionTheme(
            opacityPercent: percent,
            visualPalette: gatheringPaletteForTheme(spec),
          );
          Widget content(String title, bool map) => Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: spec.palette.text,
                    fontFamily: 'Georgia',
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    decoration: TextDecoration.none,
                  ),
                ),
                const SizedBox(height: 14),
                for (final item in [
                  'Iron Ore',
                  'Pine Timber',
                  'Wolf',
                  'Beef',
                ]) ...[
                  if (item != 'Iron Ore') const SizedBox(height: 10),
                  Builder(
                    builder: (context) {
                      final child = InkWell(
                        onTap: () => taps++,
                        child: SizedBox(
                          height: 50,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: Text(
                                item,
                                style: TextStyle(
                                  color: spec.palette.text,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ),
                        ),
                      );
                      return map
                          ? ResourceMapPill(child: child)
                          : GlassControl(child: child);
                    },
                  ),
                ],
              ],
            ),
          );

          await tester.pumpWidget(
            MaterialApp(
              theme: spec.materialTheme(),
              home: MediaQuery(
                data: const MediaQueryData(disableAnimations: true),
                child: RepaintBoundary(
                  key: _capture,
                  child: ColoredBox(
                    color: const Color(0xFF63745B),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          ResourceMapChromeTheme(
                            data: chrome,
                            child: SizedBox.fromSize(
                              key: ValueKey(_panelKeys[0]),
                              size: _panelSize,
                              child: ResourceMapAtlasPalette(
                                width: 308,
                                child: content('Map controls', true),
                              ),
                            ),
                          ),
                          const SizedBox(width: 32),
                          Theme(
                            data: gathering,
                            child: SizedBox.fromSize(
                              key: ValueKey(_panelKeys[1]),
                              size: _panelSize,
                              child: GlassSurface(
                                child: content('Gathering glass', false),
                              ),
                            ),
                          ),
                          const SizedBox(width: 32),
                          Theme(
                            data: gathering,
                            child: SizedBox.fromSize(
                              key: ValueKey(_panelKeys[2]),
                              size: _panelSize,
                              child: FieldDeskPanel(
                                child: content('Gathering desk', false),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          for (final item in find.text('Iron Ore').evaluate()) {
            await tester.tap(find.byElementPredicate((value) => value == item));
          }
          await tester.pumpAndSettle();
          expect(taps, 3);
          expect(tester.binding.transientCallbackCount, 0);
          expect(find.byType(Opacity), findsNothing);
          // GlassSurface has one pre-existing blur. The paint-only benchmark
          // below deliberately excludes it, as well as text, images and ink.
          expect(find.byType(BackdropFilter), findsOneWidget);
          final scenes = [
            for (final key in _panelKeys)
              _MaterialScene.capture(tester.element(find.byKey(ValueKey(key)))),
          ];
          for (final key in _panelKeys) {
            expect(tester.getSize(find.byKey(ValueKey(key))), _panelSize);
          }
          final records = <double>[];
          final rasters = <double>[];
          ui.Picture record() {
            final recorder = ui.PictureRecorder();
            final canvas = Canvas(recorder)
              ..drawColor(const Color(0xFF63745B), BlendMode.src);
            for (var i = 0; i < scenes.length; i++) {
              canvas.save();
              canvas.translate(16 + i * 352.0, 16);
              scenes[i].paint(canvas);
              canvas.restore();
            }
            return recorder.endRecording();
          }

          try {
            await tester.runAsync(() async {
              for (var i = 0; i < 50; i++) {
                final watch = Stopwatch()..start();
                final picture = record();
                watch.stop();
                if (i >= 10) records.add(watch.elapsedMicroseconds.toDouble());
                picture.dispose();
              }
              final picture = record();
              try {
                for (var i = 0; i < 25; i++) {
                  final watch = Stopwatch()..start();
                  final image = await picture.toImage(1088, 420);
                  watch.stop();
                  if (i >= 5) rasters.add(watch.elapsedMicroseconds.toDouble());
                  image.dispose();
                }
              } finally {
                picture.dispose();
              }
            });
            final recordStats = _statistics(records);
            final rasterStats = _statistics(rasters);
            expect(recordStats['medianMicroseconds'], lessThan(1000000));
            expect(rasterStats['medianMicroseconds'], lessThan(5000000));
            results.add({
              'theme': name,
              'opacityPercent': percent,
              'boxPainters': scenes.fold<int>(
                0,
                (sum, scene) => sum + scene.boxes.length,
              ),
              'customPainters': scenes.fold<int>(
                0,
                (sum, scene) => sum + scene.customPainters,
              ),
              'record': recordStats,
              'raster': rasterStats,
            });
            if (directory != null) {
              final boundary = tester.renderObject<RenderRepaintBoundary>(
                find.byKey(_capture),
              );
              await tester.runAsync(() async {
                await Directory(directory).create(recursive: true);
                final image = await boundary.toImage();
                try {
                  final bytes = (await image.toByteData(
                    format: ui.ImageByteFormat.png,
                  ))!;
                  await File(
                    '$directory/material-$phase-$name-opacity$percent.png',
                  ).writeAsBytes(bytes.buffer.asUint8List());
                } finally {
                  image.dispose();
                }
              });
            }
          } finally {
            for (final scene in scenes) {
              scene.dispose();
            }
          }
          expect(tester.binding.transientCallbackCount, 0);
          expect(tester.takeException(), isNull);
        }
      }
      if (directory != null) {
        await tester.runAsync(() async {
          await File('$directory/material-$phase-benchmark.json').writeAsString(
            const JsonEncoder.withIndent('  ').convert({
              'phase': phase,
              'scene': {
                'panels': 3,
                'controls': 12,
                'panelSize': [320, 360],
                'rasterSize': [1088, 420],
              },
              'recordWarmups': 10,
              'rasterWarmups': 5,
              'samples': results,
              'method':
                  'Production BoxPainter and CustomPainter instances extracted from ResourceMapAtlasPalette/Pill and Gathering GlassSurface/GlassControl/FieldDeskPanel. Real app shared-theme adapters at 0, 60 and 100 percent. Display-list recording and awaited offscreen rasterization measured separately; actual rounded clipping retained.',
              'limitations':
                  'Headless Flutter test/debug diagnostic, not GPU frame time, desktop FPS or release performance. Material-only timings exclude existing Gathering backdrop blur, text, images, ink reactions, widget layout, controllers and network. Raster timing includes scheduling/image transfer and system noise. Saved PNGs are real component fixtures, not whole application screens.',
            }),
          );
        });
      }
    } finally {
      debugDisableShadows = oldShadows;
      await tester.pumpWidget(const SizedBox.shrink());
    }
  });
}

class _MaterialScene {
  final commands = <void Function(Canvas)>[];
  final boxes = <BoxPainter>[];
  var customPainters = 0;

  static _MaterialScene capture(Element root) {
    final scene = _MaterialScene();
    final rootBox = root.findRenderObject()! as RenderBox;
    void walk(Element element) {
      final widget = element.widget;
      final render = element.findRenderObject();
      if (render is! RenderBox || !render.hasSize) {
        element.visitChildren(walk);
        return;
      }
      final offset = render.localToGlobal(Offset.zero, ancestor: rootBox);
      final size = render.size;
      void decoration(Decoration value) {
        final painter = value.createBoxPainter();
        scene.boxes.add(painter);
        scene.commands.add(
          (canvas) => painter.paint(
            canvas,
            offset,
            ImageConfiguration(size: size, textDirection: TextDirection.ltr),
          ),
        );
      }

      void custom(CustomPainter? painter) {
        if (painter == null) return;
        scene.customPainters++;
        scene.commands.add((canvas) {
          canvas.save();
          canvas.translate(offset.dx, offset.dy);
          painter.paint(canvas, size);
          canvas.restore();
        });
      }

      if (widget is ClipRRect && widget.clipBehavior != Clip.none) {
        final rect = widget.borderRadius
            .resolve(TextDirection.ltr)
            .toRRect(offset & size);
        scene.commands.add((canvas) {
          canvas.save();
          canvas.clipRRect(
            rect,
            doAntiAlias: widget.clipBehavior != Clip.hardEdge,
          );
        });
      }
      if (widget is DecoratedBox &&
          widget.position == DecorationPosition.background) {
        decoration(widget.decoration);
      }
      if (widget is Ink && widget.decoration != null) {
        decoration(widget.decoration!);
      }
      if (widget is CustomPaint) custom(widget.painter);
      element.visitChildren(walk);
      if (widget is CustomPaint) custom(widget.foregroundPainter);
      if (widget is DecoratedBox &&
          widget.position == DecorationPosition.foreground) {
        decoration(widget.decoration);
      }
      if (widget is ClipRRect && widget.clipBehavior != Clip.none) {
        scene.commands.add((canvas) => canvas.restore());
      }
    }

    walk(root);
    return scene;
  }

  void paint(Canvas canvas) {
    for (final command in commands) {
      command(canvas);
    }
  }

  void dispose() {
    for (final painter in boxes) {
      painter.dispose();
    }
  }
}

Map<String, Object> _statistics(List<double> values) {
  final sorted = values.toList()..sort();
  double percentile(double p) => sorted[((sorted.length - 1) * p).round()];
  return {
    'sampleCount': sorted.length,
    'medianMicroseconds': percentile(.5),
    'p95Microseconds': percentile(.95),
    'minimumMicroseconds': sorted.first,
    'maximumMicroseconds': sorted.last,
    'rawMicroseconds': values,
  };
}
