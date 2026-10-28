import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:bdo_craft_planner_flutter/features/opportunities/opportunities_glass_material.dart';
import 'package:bdo_craft_planner_flutter/features/opportunities/opportunities_visuals.dart';
import 'package:bdo_craft_planner_flutter/features/opportunities/opportunity_glass_finish.dart';
import 'package:bdo_craft_planner_flutter/visual/visual.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void _exchangeShadowBenchmark() {
  testWidgets('bounded rejected Exchange contact shadow diagnostic', (
    tester,
  ) async {
    final reportDirectory =
        Platform.environment['OPPORTUNITY_MATERIAL_REPORT_DIR'];
    final phase =
        Platform.environment['OPPORTUNITY_MATERIAL_PHASE'] ?? 'unspecified';
    final results = <Map<String, Object?>>[];
    final previousShadows = debugDisableShadows;
    debugDisableShadows = false;
    try {
      for (final background in [
        'sakura-night-garden',
        'illuminated-ledger',
        'greenhouse',
      ]) {
        final theme = OpportunitiesVisualSpec.forAppearance(
          RetainedThemeRegistry.resolve(backgroundId: background),
        );
        late OpportunityGlassFinish finish;
        await tester.pumpWidget(
          MaterialApp(
            home: ThemeSpecScope(
              spec: theme,
              child: Scaffold(
                body: Center(
                  child: Builder(
                    builder: (context) {
                      finish = OpportunityGlassFinish.of(context);
                      return SizedBox(
                        width: 400,
                        height: 160,
                        child: OpportunitySurface(
                          role: AppSurfaceRole.card,
                          decoration: finish.card.copyWith(boxShadow: const []),
                          padding: EdgeInsets.zero,
                          child: const Stack(
                            children: [
                              Positioned(
                                left: 14,
                                top: 14,
                                child: OpportunityItemMount(
                                  size: 56,
                                  child: SizedBox.square(dimension: 48),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pump();
        final customPaints = tester.widgetList<CustomPaint>(
          find.byType(CustomPaint),
        );
        final mount = customPaints
            .map((widget) => widget.painter)
            .whereType<OpportunityItemMountPainter>()
            .single;
        final bevel = customPaints
            .map((widget) => widget.foregroundPainter)
            .whereType<OpportunityGlassBevel>()
            .single;
        final decoration =
            tester
                    .widget<DecoratedBox>(find.byKey(AppSurface.materialKey))
                    .decoration
                as BoxDecoration;
        expect(decoration.boxShadow, isEmpty);
        final painters = [
          decoration.createBoxPainter(),
          decoration
              .copyWith(boxShadow: [finish.contactShadow])
              .createBoxPainter(),
        ];
        final recordTimes = [<double>[], <double>[]];
        final rasterTimes = [<double>[], <double>[]];
        ui.Picture recordScene(int variant) {
          final recorder = ui.PictureRecorder();
          final canvas = Canvas(recorder);
          canvas.drawColor(finish.canvas, BlendMode.src);
          for (var index = 0; index < 18; index++) {
            canvas.save();
            canvas.translate(
              16 + (index % 3) * 416.0,
              16 + (index ~/ 3) * 176.0,
            );
            painters[variant].paint(
              canvas,
              Offset.zero,
              const ImageConfiguration(size: Size(400, 160)),
            );
            canvas.save();
            canvas.translate(14, 14);
            mount.paint(canvas, const Size(56, 56));
            canvas.restore();
            bevel.paint(canvas, const Size(400, 160));
            canvas.restore();
          }
          return recorder.endRecording();
        }

        await tester.runAsync(() async {
          for (var sample = 0; sample < 70; sample++) {
            for (final variant in sample.isEven ? [0, 1] : [1, 0]) {
              final timer = Stopwatch()..start();
              final picture = recordScene(variant);
              timer.stop();
              if (sample >= 10) {
                recordTimes[variant].add(timer.elapsedMicroseconds.toDouble());
              }
              picture.dispose();
            }
          }
          final pictures = [recordScene(0), recordScene(1)];
          try {
            for (var sample = 0; sample < 35; sample++) {
              for (final variant in sample.isEven ? [0, 1] : [1, 0]) {
                final timer = Stopwatch()..start();
                final image = await pictures[variant].toImage(1280, 1080);
                timer.stop();
                if (sample >= 5) {
                  rasterTimes[variant].add(
                    timer.elapsedMicroseconds.toDouble(),
                  );
                }
                image.dispose();
              }
            }
          } finally {
            for (final picture in pictures) {
              picture.dispose();
            }
          }
        });
        for (final painter in painters) {
          painter.dispose();
        }
        for (var variant = 0; variant < 2; variant++) {
          final record = _statistics(recordTimes[variant]);
          final raster = _statistics(rasterTimes[variant]);
          expect(record['medianMicroseconds'], lessThan(1000000));
          expect(raster['medianMicroseconds'], lessThan(5000000));
          results.add({
            'theme': background,
            'variant': variant == 0
                ? 'production-no-shadow'
                : 'rejected-hypothetical-contact-shadow',
            'record': record,
            'raster': raster,
          });
        }
        expect(tester.takeException(), isNull);
      }
      if (reportDirectory != null) {
        await tester.runAsync(() async {
          await Directory(reportDirectory).create(recursive: true);
          await File(
            '$reportDirectory/material-depth-$phase-exchange-shadow-benchmark.json',
          ).writeAsString(
            const JsonEncoder.withIndent('  ').convert({
              'phase': phase,
              'scene': {
                'cards': 18,
                'cardSize': [400, 160],
                'rasterSize': [1280, 1080],
              },
              'recordWarmups': 10,
              'rasterWarmups': 5,
              'samples': results,
              'method':
                  'Production no-shadow Exchange surface decoration, item mount and bevel. Alternating paired samples compare it with an identical hypothetical contact-shadow variant rejected for performance. Materials only, no rail, text, controller, layout or network work.',
              'limitations':
                  'Isolates incremental contact-shadow cost, not a historical whole-screen baseline or actual scrolling. Headless Flutter test/debug; raster includes scheduling and image transfer. Not desktop FPS, GPU frame-time or release-mode application performance; differences are diagnostic and subject to system noise.',
            }),
          );
        });
      }
    } finally {
      debugDisableShadows = previousShadows;
      await tester.pumpWidget(const SizedBox.shrink());
    }
  });
}

void main() {
  testWidgets('bounded eighteen-card material record and offscreen raster cost', (
    tester,
  ) async {
    final reportDirectory =
        Platform.environment['OPPORTUNITY_MATERIAL_REPORT_DIR'];
    final phase =
        Platform.environment['OPPORTUNITY_MATERIAL_PHASE'] ?? 'unspecified';
    final results = <Map<String, Object?>>[];
    final previousShadows = debugDisableShadows;
    debugDisableShadows = false;
    try {
      for (final background in [
        'sakura-night-garden',
        'illuminated-ledger',
        'greenhouse',
      ]) {
        final theme = OpportunitiesVisualSpec.forAppearance(
          RetainedThemeRegistry.resolve(backgroundId: background),
        );
        late OpportunityGlassFinish finish;
        await tester.pumpWidget(
          MaterialApp(
            home: ThemeSpecScope(
              spec: theme,
              child: Scaffold(
                body: Center(
                  child: Builder(
                    builder: (context) {
                      finish = OpportunityGlassFinish.of(context);
                      return SizedBox(
                        width: 400,
                        height: 160,
                        child: OpportunitySurface(
                          decoration: finish.card,
                          role: AppSurfaceRole.card,
                          padding: EdgeInsets.zero,
                          child: const OpportunityCraftCardFinish(
                            child: Stack(
                              children: [
                                Positioned(
                                  left: 14,
                                  top: 48,
                                  child: OpportunityItemMount(
                                    child: SizedBox.square(dimension: 56),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pump();
        final customPaints = tester.widgetList<CustomPaint>(
          find.byType(CustomPaint),
        );
        final relief = customPaints
            .map((w) => w.painter)
            .whereType<OpportunityCraftCardRelief>()
            .single;
        final mount = customPaints
            .map((w) => w.painter)
            .whereType<OpportunityItemMountPainter>()
            .single;
        final bevel = customPaints
            .map((w) => w.foregroundPainter)
            .whereType<OpportunityGlassBevel>()
            .single;
        final decoration = tester
            .widget<DecoratedBox>(find.byKey(AppSurface.materialKey))
            .decoration;
        final boxPainter = decoration.createBoxPainter();
        final recordTimes = <double>[];
        final rasterTimes = <double>[];
        ui.Picture recordScene() {
          final recorder = ui.PictureRecorder();
          final canvas = Canvas(recorder);
          canvas.drawColor(finish.canvas, BlendMode.src);
          for (var index = 0; index < 18; index++) {
            canvas.save();
            canvas.translate(
              16 + (index % 3) * 416.0,
              16 + (index ~/ 3) * 176.0,
            );
            boxPainter.paint(
              canvas,
              Offset.zero,
              const ImageConfiguration(size: Size(400, 160)),
            );
            relief.paint(canvas, const Size(400, 160));
            canvas.save();
            canvas.translate(14, 48);
            mount.paint(canvas, const Size(64, 64));
            canvas.restore();
            bevel.paint(canvas, const Size(400, 160));
            canvas.restore();
          }
          return recorder.endRecording();
        }

        await tester.runAsync(() async {
          for (var i = 0; i < 70; i++) {
            final timer = Stopwatch()..start();
            final picture = recordScene();
            timer.stop();
            if (i >= 10) recordTimes.add(timer.elapsedMicroseconds.toDouble());
            picture.dispose();
          }
          final picture = recordScene();
          try {
            for (var i = 0; i < 35; i++) {
              final timer = Stopwatch()..start();
              final image = await picture.toImage(1280, 1080);
              timer.stop();
              if (i >= 5) rasterTimes.add(timer.elapsedMicroseconds.toDouble());
              image.dispose();
            }
          } finally {
            picture.dispose();
          }
        });
        boxPainter.dispose();
        final record = _statistics(recordTimes);
        final raster = _statistics(rasterTimes);
        expect(record['medianMicroseconds'], lessThan(1000000));
        expect(raster['medianMicroseconds'], lessThan(5000000));
        expect(tester.takeException(), isNull);
        results.add({'theme': background, 'record': record, 'raster': raster});
      }
      if (reportDirectory != null) {
        await tester.runAsync(() async {
          await Directory(reportDirectory).create(recursive: true);
          await File(
            '$reportDirectory/material-depth-$phase-benchmark.json',
          ).writeAsString(
            const JsonEncoder.withIndent('  ').convert({
              'phase': phase,
              'scene': {
                'cards': 18,
                'cardSize': [400, 160],
                'rasterSize': [1280, 1080],
              },
              'recordWarmups': 10,
              'rasterWarmups': 5,
              'samples': results,
              'method':
                  'Cached production BoxPainter and actual CustomPainter instances extracted from OpportunitySurface + OpportunityCraftCardFinish + OpportunityItemMount. Display-list recording is timed separately from awaited offscreen rasterization. Materials only: no text, item asset, controller, layout or network cost.',
              'limitations':
                  'Headless Flutter test/debug environment; warm cached scene; raster timing includes scheduling and image transfer overhead. Not desktop FPS, GPU frame-time or release-mode application performance. Differences are diagnostic and subject to system noise.',
            }),
          );
        });
      }
    } finally {
      debugDisableShadows = previousShadows;
      await tester.pumpWidget(const SizedBox.shrink());
    }
  });
  _exchangeShadowBenchmark();
}

Map<String, Object> _statistics(List<double> samples) {
  final sorted = samples.toList()..sort();
  double percentile(double p) => sorted[((sorted.length - 1) * p).round()];
  return {
    'sampleCount': sorted.length,
    'medianMicroseconds': percentile(.5),
    'p95Microseconds': percentile(.95),
    'minimumMicroseconds': sorted.first,
    'maximumMicroseconds': sorted.last,
    'rawMicroseconds': samples,
  };
}
