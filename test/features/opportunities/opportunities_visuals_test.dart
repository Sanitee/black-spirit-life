import 'dart:ui' as ui;

import 'package:bdo_craft_planner_flutter/domain/state/planner_state.dart';
import 'package:bdo_craft_planner_flutter/features/opportunities/opportunities_glass_material.dart';
import 'package:bdo_craft_planner_flutter/features/opportunities/opportunities_theme.dart';
import 'package:bdo_craft_planner_flutter/features/opportunities/opportunities_visuals.dart';
import 'package:bdo_craft_planner_flutter/features/opportunities/opportunity_glass_finish.dart';
import 'package:bdo_craft_planner_flutter/visual/foundations/application_theme.dart';
import 'package:bdo_craft_planner_flutter/visual/visual.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'artwork relief is paint-only and leaves the reading plane clear',
    (tester) async {
      await tester.runAsync(() async {
        for (final finish in OpportunityGlassFinish.values) {
          final painter = OpportunityCraftCardRelief(finish: finish);
          final recorder = ui.PictureRecorder();
          final canvas = Canvas(recorder)
            ..drawColor(finish.middle, BlendMode.src);
          painter.paint(canvas, const Size(400, 140));
          final picture = recorder.endRecording();
          final image = await picture.toImage(400, 140);
          final pixels = (await image.toByteData())!;
          Color at(int x, int y) {
            final offset = (y * 400 + x) * 4;
            return Color.fromARGB(
              pixels.getUint8(offset + 3),
              pixels.getUint8(offset),
              pixels.getUint8(offset + 1),
              pixels.getUint8(offset + 2),
            );
          }

          expect(at(10, 10), isNot(finish.middle));
          expect(at(180, 90), finish.middle);
          expect(at(300, 18), finish.middle);
          expect(painter.hitTest(const Offset(20, 20)), isFalse);
          expect(painter.shouldRepaint(painter), isFalse);
          expect(
            painter.shouldRepaint(
              OpportunityCraftCardRelief(finish: finish, artworkWidth: 76),
            ),
            isTrue,
          );
          image.dispose();
          picture.dispose();
        }
      });
    },
  );

  testWidgets('artwork relief retains card dimensions and pointer actions', (
    tester,
  ) async {
    var taps = 0;
    await tester.pumpWidget(
      _host(
        child: OpportunityCraftCardFinish(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => taps++,
            child: const SizedBox(
              key: ValueKey('unchanged-card'),
              width: 400,
              height: 140,
            ),
          ),
        ),
      ),
    );
    final card = find.byKey(const ValueKey('unchanged-card'));
    expect(tester.getSize(card), const Size(400, 140));
    await tester.tapAt(tester.getRect(card).topLeft + const Offset(20, 20));
    expect(taps, 1);
    expect(find.byType(BackdropFilter), findsNothing);
    expect(tester.binding.transientCallbackCount, 0);
  });

  test('display mounts are static and never intercept item actions', () {
    const mount = OpportunityItemMountPainter(
      finish: OpportunityGlassFinish.bronze,
    );
    expect(mount.hitTest(const Offset(32, 32)), isFalse);
    expect(mount.shouldRepaint(mount), isFalse);
    expect(
      mount.shouldRepaint(
        const OpportunityItemMountPainter(finish: OpportunityGlassFinish.moon),
      ),
      isTrue,
    );
  });

  test('financial values keep semantic hues with readable cached contrast', () {
    for (final background in [
      'sakura-night-garden',
      'illuminated-ledger',
      'greenhouse',
      'plain-cobalt',
    ]) {
      final spec = _appearanceSpec(background: background);
      for (final original in [
        spec.palette.success,
        spec.palette.danger,
        spec.palette.warning,
      ]) {
        final color = OpportunitiesVisualSpec.readableValueColor(
          spec,
          original,
        );
        expect(
          OpportunitiesVisualSpec.readableValueColor(spec, original),
          same(color),
        );
        for (final surface in [
          spec.palette.surface,
          spec.palette.surfaceRaised,
          ...spec.materials.surface.colors,
          ...spec.materials.surfaceRaised.colors,
          ...OpportunityGlassFinish.forSpec(spec).cardSurface.colors,
          spec.brightness == Brightness.light
              ? Color.lerp(spec.palette.surfaceRaised, Colors.white, .28)!
              : Color.alphaBlend(
                  spec.palette.primaryBright.withAlpha(18),
                  spec.palette.surfaceRaised,
                ),
        ]) {
          for (final plane in [
            surface,
            Color.alphaBlend(original.withAlpha(25), surface),
          ]) {
            final a = color.computeLuminance(), b = plane.computeLuminance();
            expect(
              a > b ? (a + .05) / (b + .05) : (b + .05) / (a + .05),
              greaterThanOrEqualTo(4.5),
              reason: background,
            );
          }
        }
      }
    }
  });

  for (final background in [
    'sakura-night-garden',
    'illuminated-ledger',
    'greenhouse',
    'plain-cobalt',
  ]) {
    test('shared Appearance card surface stays readable $background', () {
      final spec = _appearanceSpec(background: background);
      final finish = OpportunityGlassFinish.forSpec(spec);
      expect(OpportunityGlassFinish.forSpec(spec), same(finish));
      expect(finish.card.gradient, finish.cardSurface);
      for (final surface in finish.cardSurface.colors) {
        expect(surface.a, 1, reason: '$background reading plane is opaque.');
        for (final foreground in [spec.palette.text, spec.palette.textMuted]) {
          expect(
            _contrast(foreground, surface),
            greaterThanOrEqualTo(4.5),
            reason: '$background body and secondary copy on $surface',
          );
        }
        for (final semantic in [
          spec.palette.success,
          spec.palette.danger,
          spec.palette.warning,
        ]) {
          final value = OpportunitiesVisualSpec.readableValueColor(
            spec,
            semantic,
          );
          expect(
            OpportunitiesVisualSpec.readableValueColor(spec, semantic),
            same(value),
          );
          for (final plane in [
            surface,
            Color.alphaBlend(semantic.withAlpha(25), surface),
          ]) {
            expect(
              _contrast(value, plane),
              greaterThanOrEqualTo(4.5),
              reason: '$background semantic value on actual card surface',
            );
          }
        }
      }
    });

    testWidgets(
      'shared Appearance relief separates the rail without changing content $background',
      (tester) async {
        late OpportunityGlassFinish finish;
        var taps = 0;
        await tester.pumpWidget(
          _host(
            outerBackground: background,
            child: Builder(
              builder: (context) {
                finish = OpportunityGlassFinish.of(context);
                expect(
                  finish,
                  same(
                    OpportunityGlassFinish.forSpec(
                      OpportunitiesVisualSpec.of(context),
                    ),
                  ),
                );
                return OpportunityCraftCardFinish(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => taps++,
                    child: const SizedBox(
                      key: ValueKey('shared-material-card'),
                      width: 400,
                      height: 140,
                    ),
                  ),
                );
              },
            ),
          ),
        );
        final card = find.byKey(const ValueKey('shared-material-card'));
        expect(tester.getSize(card), const Size(400, 140));
        final bounds = tester.getRect(card);
        await tester.tapAt(bounds.topLeft + const Offset(30, 70));
        await tester.tapAt(bounds.topLeft + const Offset(180, 70));
        expect(taps, 2);
        expect(find.byType(BackdropFilter), findsNothing);
        expect(tester.binding.transientCallbackCount, 0);

        await tester.runAsync(() async {
          const size = Size(400, 140);
          final painter = OpportunityCraftCardRelief(
            finish: finish,
            artworkWidth: OpportunitiesVisualSpec.craftArtworkRailWidth,
          );
          Future<ui.Image> render({required bool relief}) async {
            final recorder = ui.PictureRecorder();
            final canvas = Canvas(recorder);
            final rect = Offset.zero & size;
            canvas.drawRect(
              rect,
              Paint()..shader = finish.cardSurface.createShader(rect),
            );
            if (relief) painter.paint(canvas, size);
            final picture = recorder.endRecording();
            try {
              return await picture.toImage(400, 140);
            } finally {
              picture.dispose();
            }
          }

          final baseImage = await render(relief: false);
          final reliefImage = await render(relief: true);
          try {
            final base = (await baseImage.toByteData())!;
            final relief = (await reliefImage.toByteData())!;
            Color at(bool raised, int x, int y) {
              final pixels = raised ? relief : base;
              final offset = (y * 400 + x) * 4;
              return Color.fromARGB(
                pixels.getUint8(offset + 3),
                pixels.getUint8(offset),
                pixels.getUint8(offset + 1),
                pixels.getUint8(offset + 2),
              );
            }

            expect(
              _contrast(at(true, 30, 70), at(true, 180, 70)),
              greaterThan(_contrast(at(false, 30, 70), at(false, 180, 70))),
              reason:
                  'The rail is more distinct than the untouched card plane.',
            );
            for (final point in [
              const Offset(180, 70),
              const Offset(300, 18),
              const Offset(300, 120),
            ]) {
              expect(
                at(true, point.dx.toInt(), point.dy.toInt()),
                at(false, point.dx.toInt(), point.dy.toInt()),
                reason: 'Relief must not wash over the reading column.',
              );
            }
            expect(painter.hitTest(const Offset(30, 70)), isFalse);
            expect(
              painter.shouldRepaint(
                OpportunityCraftCardRelief(
                  finish: finish,
                  artworkWidth: OpportunitiesVisualSpec.craftArtworkRailWidth,
                ),
              ),
              isFalse,
            );
          } finally {
            baseImage.dispose();
            reliefImage.dispose();
          }
        });
        expect(tester.getRect(card), bounds);
        expect(tester.binding.transientCallbackCount, 0);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'glass bevel lights the rim without washing out the reading plane',
    (tester) async {
      await tester.runAsync(() async {
        for (final finish in OpportunityGlassFinish.values) {
          final bevel = OpportunityGlassBevel(light: finish.accent);
          final recorder = ui.PictureRecorder();
          final canvas = Canvas(recorder)
            ..drawColor(finish.middle, BlendMode.src);
          bevel.paint(canvas, const Size(300, 180));
          final picture = recorder.endRecording();
          final image = await picture.toImage(300, 180);
          final pixels = (await image.toByteData())!;
          Color at(int x, int y) {
            final i = (y * 300 + x) * 4;
            return Color.fromARGB(
              pixels.getUint8(i + 3),
              pixels.getUint8(i),
              pixels.getUint8(i + 1),
              pixels.getUint8(i + 2),
            );
          }

          expect(
            at(80, 0).computeLuminance(),
            greaterThan(finish.middle.computeLuminance() * 2),
          );
          expect(
            at(80, 179).computeLuminance(),
            lessThan(finish.middle.computeLuminance() * .7),
          );
          expect(
            at(150, 90),
            finish.middle,
            reason: 'No shine or texture over content.',
          );
          expect(bevel.hitTest(const Offset(1, 1)), isFalse);
          expect(
            bevel.shouldRepaint(OpportunityGlassBevel(light: finish.accent)),
            isFalse,
          );
          expect(
            bevel.shouldRepaint(
              OpportunityGlassBevel(light: finish.accent, inset: true),
            ),
            isTrue,
          );
          expect(finish.card.boxShadow, hasLength(2));
          image.dispose();
          picture.dispose();
        }
      });
    },
  );

  test('artwork lustre stays static and never owns pointer input', () {
    const bronze = OpportunityArtworkLustre(
      finish: OpportunityGlassFinish.bronze,
    );
    const moon = OpportunityArtworkLustre(finish: OpportunityGlassFinish.moon);
    expect(bronze.hitTest(const Offset(10, 20)), isFalse);
    expect(bronze.shouldRepaint(bronze), isFalse);
    expect(bronze.shouldRepaint(moon), isTrue);
  });

  test('raised bevel options invalidate changed material inputs', () {
    const baseline = OpportunityGlassBevel(light: Colors.cyan);
    const raised = OpportunityGlassBevel(light: Colors.cyan, raisedLip: true);
    const lightRaised = OpportunityGlassBevel(
      light: Colors.cyan,
      raisedLip: true,
      lightSurface: true,
    );
    expect(raised.shouldRepaint(baseline), isTrue);
    expect(baseline.shouldRepaint(raised), isTrue);
    expect(lightRaised.shouldRepaint(raised), isTrue);
    expect(raised.shouldRepaint(lightRaised), isTrue);
    expect(
      lightRaised.shouldRepaint(
        const OpportunityGlassBevel(
          light: Colors.cyan,
          raisedLip: true,
          lightSurface: true,
        ),
      ),
      isFalse,
    );
    for (final painter in [baseline, raised, lightRaised]) {
      expect(painter.hitTest(const Offset(1, 1)), isFalse);
      expect(painter.hitTest(const Offset(150, 90)), isFalse);
    }
  });

  testWidgets(
    'raised bevel keeps rounded corners and reading plane clear',
    (tester) async {
      await tester.runAsync(() async {
        const width = 308, height = 188;
        const untouched = Color(0xFF38424A);
        for (final background in [
          'sakura-night-garden',
          'illuminated-ledger',
          'greenhouse',
        ]) {
          final spec = _appearanceSpec(background: background);
          Future<ui.Image> render({
            required bool raisedLip,
            bool inset = false,
          }) async {
            final recorder = ui.PictureRecorder();
            final canvas = Canvas(recorder)
              ..drawColor(untouched, BlendMode.src)
              ..translate(4, 4);
            OpportunityGlassBevel(
              light: spec.palette.trimBright,
              radius: spec.geometry.cardRadius,
              raisedLip: raisedLip,
              lightSurface: spec.brightness == Brightness.light,
              inset: inset,
            ).paint(canvas, const Size(300, 180));
            final picture = recorder.endRecording();
            try {
              return await picture.toImage(width, height);
            } finally {
              picture.dispose();
            }
          }

          final plain = await render(raisedLip: false);
          final raised = await render(raisedLip: true);
          final inset = await render(raisedLip: false, inset: true);
          final insetRaised = await render(raisedLip: true, inset: true);
          try {
            final plainPixels = (await plain.toByteData())!;
            final raisedPixels = (await raised.toByteData())!;
            Color at(int x, int y) {
              final offset = (y * width + x) * 4;
              return Color.fromARGB(
                raisedPixels.getUint8(offset + 3),
                raisedPixels.getUint8(offset),
                raisedPixels.getUint8(offset + 1),
                raisedPixels.getUint8(offset + 2),
              );
            }

            for (var y = 0; y < height; y++) {
              for (var x = 0; x < width; x++) {
                if (x < 4 || x >= 304 || y < 4 || y >= 184) {
                  expect(at(x, y), untouched, reason: '$background bounds');
                }
              }
            }
            for (final point in [
              const Offset(4, 4),
              const Offset(303, 4),
              const Offset(4, 183),
              const Offset(303, 183),
              const Offset(24, 24),
              const Offset(154, 94),
              const Offset(284, 164),
            ]) {
              expect(
                at(point.dx.toInt(), point.dy.toInt()),
                untouched,
                reason: '$background rounded corner or reading plane',
              );
            }
            expect(
              raisedPixels.buffer.asUint8List(),
              isNot(orderedEquals(plainPixels.buffer.asUint8List())),
              reason: 'A raised lip visibly changes only the static rim.',
            );
            expect(
              (await insetRaised.toByteData())!.buffer.asUint8List(),
              orderedEquals((await inset.toByteData())!.buffer.asUint8List()),
              reason: 'The raised option must not alter recessed fields.',
            );
          } finally {
            plain.dispose();
            raised.dispose();
            inset.dispose();
            insetRaised.dispose();
          }
        }
      });
      expect(tester.binding.transientCallbackCount, 0);
    },
  );

  test('both glass finishes preserve readable opaque surfaces', () {
    for (final finish in OpportunityGlassFinish.values) {
      final spec = OpportunitiesVisualSpec.forFinish(finish.key);
      for (final background in [
        ...spec.materials.surface.colors,
        ...spec.materials.surfaceRaised.colors,
      ]) {
        expect(background.a, 1);
        for (final foreground in [
          spec.palette.text,
          spec.palette.textMuted,
          spec.palette.success,
          spec.palette.danger,
        ]) {
          final contrast =
              (foreground.computeLuminance() + .05) /
              (background.computeLuminance() + .05);
          expect(
            contrast,
            greaterThanOrEqualTo(4.5),
            reason: '${finish.name}: $foreground / $background',
          );
        }
      }
    }
  });

  test('Appearance adapter preserves palette, geometry and cache identity', () {
    for (final background in [
      'sakura-night-garden',
      'illuminated-ledger',
      'greenhouse',
      'plain-cobalt',
      'plain-rose',
    ]) {
      final source = applicationThemeForAppearance(
        _appearanceSettings(background: background, accentHue: 275),
      );
      final adapted = OpportunitiesVisualSpec.forAppearance(source);
      expect(adapted.palette, same(source.palette));
      expect(adapted.materials, same(source.materials));
      expect(adapted.brightness, source.brightness);
      expect(adapted.geometry, same(OpportunitiesVisualSpec.geometry));
      expect(adapted.typography.body.fontSize, 16);
      expect(adapted.typography.display.fontFamily, 'Georgia');
      expect(OpportunitiesVisualSpec.forAppearance(source), same(adapted));
      expect(OpportunitiesVisualSpec.forAppearance(adapted), same(adapted));
    }
  });
  test(
    'EXP and Marketplace blue stays readable on light and dark Appearance',
    () {
      for (final background in [
        'sakura-night-garden',
        'illuminated-ledger',
        'greenhouse',
        'plain-cobalt',
        'plain-rose',
      ]) {
        final spec = _appearanceSpec(background: background);
        final foreground = OpportunitiesVisualSpec.informationColor(spec);
        for (final surface in [
          spec.palette.surface,
          spec.palette.surfaceRaised,
          ...spec.materials.surface.colors,
          ...spec.materials.surfaceRaised.colors,
        ]) {
          final a = foreground.computeLuminance();
          final b = surface.computeLuminance();
          final contrast = a > b
              ? (a + .05) / (b + .05)
              : (b + .05) / (a + .05);
          expect(contrast, greaterThanOrEqualTo(4.5), reason: background);
        }
      }
    },
  );

  test('workbench figures are prominent and labels remain secondary', () {
    expect(OpportunitiesVisualSpec.cardNameFontSize, 18);
    expect(OpportunitiesVisualSpec.cardPrimaryValueFontSize, 22);
    expect(
      OpportunitiesVisualSpec.cardPrimaryValueFontSize,
      greaterThan(OpportunitiesVisualSpec.cardNameFontSize),
    );
    expect(OpportunitiesVisualSpec.cardLabelFontSize, 12);
    expect(OpportunitiesVisualSpec.cardSecondaryValueFontSize, 15);
  });

  test('workbench uses a serif title with readable UI text hierarchy', () {
    const type = OpportunitiesVisualSpec.typography;
    final styles = [
      type.display,
      type.section,
      type.body,
      type.meta,
      type.label,
      type.button,
    ];
    expect(type.display.fontFamily, 'Georgia');
    expect(styles.skip(1).map((style) => style.fontFamily).toSet(), {
      'Segoe UI',
    });
    expect(styles.map((style) => style.fontSize), [26, 18, 16, 13, 14, 16]);
    expect(type.label.fontWeight, FontWeight.w500);
    expect(type.button.fontWeight, FontWeight.w500);
    expect(type.section.fontWeight, FontWeight.w600);
    expect(type.body.fontWeight, isNot(FontWeight.w600));
  });

  testWidgets('glass reading surfaces use one border and opaque gradients', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        child: const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            OpportunitySurface(
              key: ValueKey('header'),
              role: AppSurfaceRole.commandBand,
              child: Text('Opportunities'),
            ),
            OpportunitySurface(
              key: ValueKey('toolbar'),
              role: AppSurfaceRole.panel,
              child: Text('Cooking'),
            ),
            OpportunitySurface(
              key: ValueKey('body-card'),
              role: AppSurfaceRole.card,
              child: Text('Beer'),
            ),
          ],
        ),
      ),
    );
    BoxDecoration decoration(String key) =>
        tester
                .widget<DecoratedBox>(
                  find.descendant(
                    of: find.byKey(ValueKey(key)),
                    matching: find.byKey(AppSurface.materialKey),
                  ),
                )
                .decoration
            as BoxDecoration;
    expect(decoration('header').border, isNull);
    expect(decoration('header').gradient, isNull);
    expect(decoration('header').color, Colors.transparent);
    expect(
      decoration('toolbar').gradient,
      _appearanceSpec().materials.surfaceRaised,
    );
    expect(
      decoration('body-card').gradient,
      _appearanceSpec().materials.surface,
    );
    for (final key in ['toolbar', 'body-card']) {
      final surface = decoration(key);
      expect(surface.gradient, isNotNull);
      expect(surface.gradient!.colors.every((color) => color.a == 1), isTrue);
      expect(surface.border, isA<Border>());
      expect((surface.border! as Border).top.width, 1);
      expect(surface.borderRadius, BorderRadius.circular(8));
      final host = tester.widget<DecoratedBox>(
        find.descendant(
          of: find.byKey(ValueKey(key)),
          matching: find.byKey(AppSurface.materialKey),
        ),
      );
      expect(host.child, isA<Material>());
      final material = host.child! as Material;
      expect(material.type, MaterialType.transparency);
      expect(material.elevation, 0);
    }
    expect(find.byType(BackdropFilter), findsNothing);
    expect(tester.binding.transientCallbackCount, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('static backdrop remains dark and does not hit test', (
    tester,
  ) async {
    await tester.runAsync(() async {
      const painter = OpportunityGlassBackdrop();
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      painter.paint(canvas, const Size(300, 180));
      final picture = recorder.endRecording();
      final image = await picture.toImage(300, 180);
      final pixels = (await image.toByteData())!;
      final colours = <int>{};
      for (var y = 0; y < 180; y += 10) {
        for (var x = 0; x < 300; x += 10) {
          final index = (y * 300 + x) * 4;
          final red = pixels.getUint8(index);
          final green = pixels.getUint8(index + 1);
          final blue = pixels.getUint8(index + 2);
          final alpha = pixels.getUint8(index + 3);
          final colour = Color.fromARGB(alpha, red, green, blue);
          expect(alpha, 255);
          expect(colour.computeLuminance(), lessThan(.09));
          colours.add(colour.toARGB32());
        }
      }
      expect(colours.length, greaterThan(8), reason: 'Keep subtle atmosphere.');
      expect(painter.hitTest(const Offset(130, 50)), isFalse);
      expect(painter.shouldRepaint(painter), isFalse);
      image.dispose();
      picture.dispose();
    });
  });

  testWidgets('direction B card materials do not change other reading roles', (
    tester,
  ) async {
    var taps = 0;
    for (final background in [
      'greenhouse',
      SakuraNightGardenSpec.backgroundId,
    ]) {
      await tester.pumpWidget(
        _host(
          outerBackground: background,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              OpportunitySurface(
                key: const ValueKey('direction-b-card'),
                role: AppSurfaceRole.card,
                padding: EdgeInsets.zero,
                decoration: OpportunitiesVisualSpec.recipeCard,
                child: InkWell(
                  onTap: () => taps++,
                  child: const SizedBox(
                    width: 400,
                    height: 150,
                    child: Text('Gem Polisher'),
                  ),
                ),
              ),
              const OpportunitySurface(
                key: ValueKey('unchanged-panel'),
                role: AppSurfaceRole.panel,
                child: Text('Calculation'),
              ),
            ],
          ),
        ),
      );
      final card = tester.widget<DecoratedBox>(
        find.descendant(
          of: find.byKey(const ValueKey('direction-b-card')),
          matching: find.byKey(AppSurface.materialKey),
        ),
      );
      expect(card.decoration, OpportunitiesVisualSpec.recipeCard);
      final material = card.decoration as BoxDecoration;
      expect(material.color, const Color(0xFF162A3A));
      expect(material.gradient, isNull);
      expect(material.borderRadius, BorderRadius.circular(12));
      expect(material.boxShadow, hasLength(1));
      expect(material.boxShadow!.single.blurRadius, 18);
      expect(material.boxShadow!.single.color, const Color(0x24030A10));
      final panel = tester.widget<DecoratedBox>(
        find.descendant(
          of: find.byKey(const ValueKey('unchanged-panel')),
          matching: find.byKey(AppSurface.materialKey),
        ),
      );
      expect(
        (panel.decoration as BoxDecoration).gradient,
        _appearanceSpec(background: background).materials.surfaceRaised,
      );
      expect(
        (panel.decoration as BoxDecoration).boxShadow,
        _appearanceSpec(background: background).materials.lowShadow,
      );
      await tester.tap(find.text('Gem Polisher'));
      expect(tester.takeException(), isNull);
    }
    expect(taps, 2);
    expect(OpportunitiesVisualSpec.recipeArtworkRail.gradient, isNotNull);
    expect(OpportunitiesVisualSpec.recipeArtworkRail.gradient!.colors, [
      const Color(0xFF223F4B),
      const Color(0xFF193140),
    ]);
    expect(OpportunitiesVisualSpec.recipeFooter.color, const Color(0xFF132635));
    final footerBorder = OpportunitiesVisualSpec.recipeFooter.border! as Border;
    expect(footerBorder.top.width, 1);
    expect(footerBorder.left, BorderSide.none);
    expect(footerBorder.right, BorderSide.none);
    expect(footerBorder.bottom, BorderSide.none);
  });

  testWidgets('overlay roles and tooltips use an opaque reading plane', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final role in [
              AppSurfaceRole.modal,
              AppSurfaceRole.popup,
              AppSurfaceRole.tooltip,
            ])
              OpportunitySurface(
                key: ValueKey(role),
                role: role,
                child: Text(role.name),
              ),
          ],
        ),
      ),
    );
    for (final role in [
      AppSurfaceRole.modal,
      AppSurfaceRole.popup,
      AppSurfaceRole.tooltip,
    ]) {
      final box = tester.widget<DecoratedBox>(
        find.descendant(
          of: find.byKey(ValueKey(role)),
          matching: find.byKey(AppSurface.materialKey),
        ),
      );
      final decoration = box.decoration as BoxDecoration;
      expect(decoration.gradient, isNotNull);
      expect(
        decoration.gradient!.colors.every((color) => color.a == 1),
        isTrue,
      );
      expect(decoration.boxShadow, _appearanceSpec().materials.lowShadow);
    }
    final context = tester.element(find.byType(OpportunitySurface).first);
    final tooltip = Theme.of(context).tooltipTheme;
    expect(tooltip.textStyle!.fontSize, 16);
    expect(
      (tooltip.decoration! as BoxDecoration).gradient,
      _appearanceSpec().materials.surfaceRaised,
    );
    expect(OpportunitiesVisualSpec.overlay.colors.toSet(), {
      OpportunitiesVisualSpec.palette.surfaceRaised,
    });
    expect(tester.takeException(), isNull);
  });

  testWidgets('all controls keep a comfortable target at either text size', (
    tester,
  ) async {
    for (final scale in [1.0, 2.0]) {
      await tester.pumpWidget(
        _host(
          scale: scale,
          child: SizedBox(
            width: 300,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                OpportunityButton.label(
                  'Refresh',
                  key: const ValueKey('ordinary'),
                  onPressed: () {},
                ),
                OpportunityButton.label(
                  'Filters',
                  key: const ValueKey('compact'),
                  minimumSize: const Size(0, 38),
                  onPressed: () {},
                ),
                OpportunityButton.icon(
                  key: const ValueKey('icon'),
                  icon: const Icon(Icons.info_outline),
                  semanticLabel: 'Details',
                  onPressed: () {},
                ),
                const OpportunityTextField(label: 'Extra costs'),
              ],
            ),
          ),
        ),
      );
      expect(
        tester.getSize(find.byKey(const ValueKey('ordinary'))).height,
        greaterThanOrEqualTo(40),
      );
      expect(
        tester.getSize(find.byKey(const ValueKey('compact'))).height,
        greaterThanOrEqualTo(40),
      );
      final icon = tester.getSize(find.byKey(const ValueKey('icon')));
      expect(icon.width, greaterThanOrEqualTo(40));
      expect(icon.height, greaterThanOrEqualTo(40));
      expect(
        tester.getSize(find.byType(TextField)).height,
        greaterThanOrEqualTo(40),
      );
      if (scale == 1) {
        expect(
          tester.getSize(find.byKey(const ValueKey('ordinary'))).height,
          40,
        );
        expect(
          tester.getSize(find.byKey(const ValueKey('compact'))).height,
          40,
        );
        expect(icon, const Size.square(40));
      } else {
        expect(
          tester.getSize(find.byKey(const ValueKey('ordinary'))).height,
          greaterThan(40),
        );
        expect(tester.getSize(find.byType(TextField)).height, greaterThan(40));
      }
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('comparison finish stays open and preserves row input and size', (
    tester,
  ) async {
    var taps = 0;
    await tester.pumpWidget(
      _host(
        child: Material(
          type: MaterialType.transparency,
          child: OpportunityComparisonRowFinish(
            key: const ValueKey('row-finish'),
            alternate: true,
            child: InkWell(
              onTap: () => taps++,
              child: const SizedBox(
                width: 400,
                height: 84,
                child: Text('Beer'),
              ),
            ),
          ),
        ),
      ),
    );
    final row = find.byKey(const ValueKey('row-finish'));
    expect(tester.getSize(row), const Size(400, 84));
    final ink = tester.widget<Ink>(
      find.descendant(of: row, matching: find.byType(Ink)),
    );
    final border = (ink.decoration! as BoxDecoration).border! as Border;
    expect(border.left, BorderSide.none);
    expect(border.right, BorderSide.none);
    expect(border.top, BorderSide.none);
    expect(border.bottom.width, 1);
    expect((ink.decoration! as BoxDecoration).gradient, isNull);
    expect((ink.decoration! as BoxDecoration).boxShadow, isNull);
    await tester.tap(find.text('Beer'));
    expect(taps, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'local fields, cards and controls follow Appearance without changing geometry',
    (tester) async {
      BoxDecoration? firstCard;
      BoxDecoration? firstButton;
      InputDecoration? firstField;
      for (final settings in [
        (background: 'greenhouse', hue: 310.0, neon: true),
        (
          background: SakuraNightGardenSpec.backgroundId,
          hue: 80.0,
          neon: false,
        ),
      ]) {
        await tester.pumpWidget(
          _host(
            outerBackground: settings.background,
            hue: settings.hue,
            neon: settings.neon,
            child: SizedBox(
              width: 280,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  OpportunitySurface(
                    key: const ValueKey('card'),
                    child: Builder(
                      builder: (context) {
                        expect(
                          context.visualTheme,
                          same(
                            _appearanceSpec(
                              background: settings.background,
                              hue: settings.hue,
                              neon: settings.neon,
                            ),
                          ),
                        );
                        return const Text('Investment');
                      },
                    ),
                  ),
                  OpportunityFilterButton(
                    key: const ValueKey('filter'),
                    selected: true,
                    label: 'Ingredients available',
                    onChanged: (_) {},
                  ),
                  const OpportunityTextField(
                    label: 'Extra costs',
                    hintText: '0',
                  ),
                ],
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final card =
            tester
                    .widget<DecoratedBox>(
                      find.descendant(
                        of: find.byKey(const ValueKey('card')),
                        matching: find.byKey(AppSurface.materialKey),
                      ),
                    )
                    .decoration
                as BoxDecoration;
        final button =
            tester
                    .widget<AnimatedContainer>(
                      find.descendant(
                        of: find.byKey(const ValueKey('filter')),
                        matching: find.byKey(AppButton.materialKey),
                      ),
                    )
                    .decoration
                as BoxDecoration;
        final field = tester
            .widget<TextField>(find.byType(TextField))
            .decoration!;
        expect(card.image, isNull);
        expect(
          field.fillColor,
          _appearanceSpec(
            background: settings.background,
            hue: settings.hue,
            neon: settings.neon,
          ).palette.surfaceInset,
        );
        expect(
          (field.focusedBorder! as OutlineInputBorder).borderSide.color,
          _appearanceSpec(
            background: settings.background,
            hue: settings.hue,
            neon: settings.neon,
          ).palette.primaryBright,
        );
        if (firstCard == null) {
          firstCard = card;
          firstButton = button;
          firstField = field;
        } else {
          expect(card.gradient, isNot(firstCard.gradient));
          expect(button.gradient, isNot(firstButton!.gradient));
          expect(field.fillColor, isNot(firstField!.fillColor));
          expect(card.borderRadius, firstCard.borderRadius);
          expect(button.borderRadius, firstButton.borderRadius);
        }
      }
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'local button keeps pointer, keyboard, focus and semantic actions',
    (tester) async {
      final focus = FocusNode();
      addTearDown(focus.dispose);
      var count = 0;
      await tester.pumpWidget(
        _host(
          child: OpportunityButton.label(
            'Check prices',
            key: const ValueKey('button'),
            focusNode: focus,
            semanticLabel: 'Check current prices',
            onPressed: () => count++,
          ),
        ),
      );
      final button = find.byKey(const ValueKey('button'));
      final initialSize = tester.getSize(button);
      expect(tester.widget(button), isA<AppButton>());
      final semantics = tester.ensureSemantics();
      final node = tester.getSemantics(button);
      expect(node.label, 'Check current prices');
      expect(node.getSemanticsData().flagsCollection.isButton, isTrue);
      semantics.dispose();
      await tester.tap(button);
      expect(count, 1);
      focus.requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pumpAndSettle();
      expect(count, 3);
      expect(
        tester.getSize(button),
        initialSize,
        reason: 'Focus must not move surrounding controls.',
      );
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      await mouse.moveTo(tester.getCenter(button));
      await tester.pumpAndSettle();
      expect(tester.getSize(button), initialSize);
      await mouse.removePointer();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'disabled button never activates and filter remains a real toggle',
    (tester) async {
      var changed = false;
      await tester.pumpWidget(
        _host(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              OpportunityButton.label('Unavailable', onPressed: null),
              OpportunityFilterButton(
                label: 'Only profitable',
                selected: false,
                onChanged: (value) => changed = value,
              ),
            ],
          ),
        ),
      );
      await tester.tap(find.text('Unavailable'));
      expect(changed, isFalse);
      await tester.tap(find.text('Only profitable'));
      expect(changed, isTrue);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('selected glass button keeps light text and a clear focus edge', (
    tester,
  ) async {
    final focus = FocusNode();
    addTearDown(focus.dispose);
    await tester.pumpWidget(
      _host(
        child: OpportunityButton.label(
          'Crafting',
          selected: true,
          focusNode: focus,
          onPressed: () {},
        ),
      ),
    );
    final context = tester.element(find.text('Crafting'));
    expect(
      DefaultTextStyle.of(context).style.color,
      _appearanceSpec().palette.text,
    );
    expect(DefaultTextStyle.of(context).style.fontWeight, FontWeight.w600);
    focus.requestFocus();
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    focus.requestFocus();
    await tester.pumpAndSettle();
    final material = tester.widget<AnimatedContainer>(
      find.byKey(AppButton.materialKey),
    );
    final decoration = material.decoration! as BoxDecoration;
    expect(decoration.gradient, isNotNull);
    expect(decoration.boxShadow, hasLength(1));
    expect(
      decoration.boxShadow!.every((shadow) => shadow.blurRadius <= 12),
      isTrue,
    );
    for (final background in decoration.gradient!.colors) {
      expect(
        (DefaultTextStyle.of(context).style.color!.computeLuminance() + .05) /
            (background.computeLuminance() + .05),
        greaterThanOrEqualTo(4.5),
      );
    }
    expect(
      decoration.color,
      Color.alphaBlend(
        _appearanceSpec().palette.primary.withAlpha(32),
        _appearanceSpec().palette.surfaceInset,
      ),
    );
    expect(material.transform, isNull);
    expect(
      (decoration.border! as Border).top.color,
      _appearanceSpec().palette.primaryBright,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'field preserves editing, formatter and keyboard callbacks at 200 percent',
    (tester) async {
      final controller = TextEditingController();
      addTearDown(controller.dispose);
      var submitted = '';
      var keyCount = 0;
      await tester.pumpWidget(
        _host(
          scale: 2,
          child: SizedBox(
            width: 280,
            child: OpportunityTextField(
              controller: controller,
              label: 'Extra costs',
              minimumHeight: 38,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              onSubmitted: (value) => submitted = value,
              onKeyEvent: (_, event) {
                if (event is KeyDownEvent &&
                    event.logicalKey == LogicalKeyboardKey.f2) {
                  keyCount++;
                  return KeyEventResult.handled;
                }
                return KeyEventResult.ignored;
              },
            ),
          ),
        ),
      );
      final field = find.byType(TextField);
      final decoration = tester.widget<TextField>(field).decoration!;
      expect(decoration.labelStyle!.fontSize, 14);
      expect(decoration.floatingLabelStyle!.fontSize! * .75, 14);
      await tester.enterText(field, '12a3');
      expect(controller.text, '123');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      expect(submitted, '123');
      await tester.tap(field);
      await tester.sendKeyEvent(LogicalKeyboardKey.f2);
      expect(keyCount, 1);
      expect(tester.getSize(field).height, greaterThanOrEqualTo(52));
      expect(tester.takeException(), isNull);
    },
  );

  for (final background in [
    'sakura-night-garden',
    'illuminated-ledger',
    'plain-cobalt',
  ]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets(
        'floating label has no continuous hover rim in $background at $scale',
        (tester) async {
          final text = TextEditingController(text: '150');
          final focus = FocusNode();
          addTearDown(text.dispose);
          addTearDown(focus.dispose);
          await tester.pumpWidget(
            _host(
              outerBackground: background,
              scale: scale,
              disableAnimations: false,
              child: SizedBox(
                width: 280 * scale,
                child: OpportunityTextField(
                  key: const ValueKey('labelled-input'),
                  controller: text,
                  focusNode: focus,
                  label: 'Extra costs',
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          final owner = find.byKey(const ValueKey('labelled-input'));
          final field = find.descendant(
            of: owner,
            matching: find.byType(TextField),
          );
          final bounds = tester.getRect(field);
          void expectSingleBorder() {
            expect(
              find.descendant(
                of: owner,
                matching: find.byType(OpportunityCardMotion),
              ),
              findsNothing,
              reason: 'A continuous outer rim would cross the label gap.',
            );
            final decoration = tester.widget<TextField>(field).decoration!;
            expect(decoration.labelText, 'Extra costs');
            expect(decoration.focusedBorder, isA<OutlineInputBorder>());
            expect(tester.getRect(field), bounds);
            expect(tester.takeException(), isNull);
          }

          expectSingleBorder();
          final mouse = await tester.createGesture(
            kind: PointerDeviceKind.mouse,
          );
          await mouse.addPointer(location: Offset.zero);
          await mouse.moveTo(tester.getCenter(field));
          await tester.pumpAndSettle();
          expectSingleBorder();
          await tester.sendKeyEvent(LogicalKeyboardKey.tab);
          await tester.pumpAndSettle();
          expect(focus.hasFocus, isTrue);
          expectSingleBorder();
          await tester.enterText(field, '750');
          await tester.pumpAndSettle();
          expect(text.text, '750');
          expectSingleBorder();
          await mouse.removePointer();
        },
      );
    }
  }

  testWidgets('reduced motion skips entrance and control transitions', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(child: OpportunityButton.label('Refresh', onPressed: () {})),
    );
    final entrance = tester.widget<FadeTransition>(
      find.descendant(
        of: find.byType(OpportunityEntrance),
        matching: find.byType(FadeTransition),
      ),
    );
    expect(entrance.opacity.value, 1);
    final material = tester.widget<AnimatedContainer>(
      find.byKey(AppButton.materialKey),
    );
    expect(material.duration, Duration.zero);
    expect(tester.binding.transientCallbackCount, 0);
  });

  testWidgets('entrance runs once and leaves no idle animation ticker', (
    tester,
  ) async {
    Widget host(String label) =>
        _host(disableAnimations: false, child: Text(label));
    await tester.pumpWidget(host('First result'));
    await tester.pump(const Duration(milliseconds: 250));
    expect(tester.binding.transientCallbackCount, 0);
    await tester.pumpWidget(host('New market result'));
    final fade = tester.widget<FadeTransition>(
      find.descendant(
        of: find.byType(OpportunityEntrance),
        matching: find.byType(FadeTransition),
      ),
    );
    expect(fade.opacity.value, 1);
    expect(tester.binding.transientCallbackCount, 0);
  });

  test('text and figures stay readable across surfaces and selected fills', () {
    const p = OpportunitiesVisualSpec.palette;
    double contrast(Color a, Color b) {
      final first = a.computeLuminance();
      final second = b.computeLuminance();
      return first > second
          ? (first + .05) / (second + .05)
          : (second + .05) / (first + .05);
    }

    for (final surface in [
      p.surface,
      p.surfaceRaised,
      p.surfaceInset,
      ...OpportunitiesVisualSpec.overlay.colors,
      for (final color in [
        ...OpportunitiesVisualSpec.materials.surface.colors,
        ...OpportunitiesVisualSpec.materials.surfaceRaised.colors,
      ])
        // Even a bright underlying scene cannot wash out the text.
        Color.alphaBlend(color, Colors.white),
    ]) {
      for (final foreground in [
        p.text,
        p.textMuted,
        p.success,
        p.danger,
        p.warning,
      ]) {
        expect(
          contrast(foreground, surface),
          greaterThanOrEqualTo(4.5),
          reason: '$foreground on $surface',
        );
      }
    }
    for (final color in [
      ...OpportunitiesVisualSpec.materials.primary.colors,
      ...OpportunitiesVisualSpec.materials.secondary.colors,
      Color.alphaBlend(p.primary.withAlpha(32), p.surfaceInset),
      Color.alphaBlend(p.primary.withAlpha(45), p.surfaceInset),
    ]) {
      expect(
        contrast(p.text, Color.alphaBlend(color, Colors.white)),
        greaterThanOrEqualTo(4.5),
      );
    }
    expect(contrast(p.canvasDeep, p.primary), greaterThanOrEqualTo(7));
  });
}

double _contrast(Color a, Color b) {
  final first = a.computeLuminance(), second = b.computeLuminance();
  return first > second
      ? (first + .05) / (second + .05)
      : (second + .05) / (first + .05);
}

Widget _host({
  required Widget child,
  String outerBackground = 'greenhouse',
  double hue = 158,
  bool neon = false,
  bool disableAnimations = true,
  double scale = 1,
}) => MaterialApp(
  debugShowCheckedModeBanner: false,
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(context).copyWith(
      disableAnimations: disableAnimations,
      textScaler: TextScaler.linear(scale),
    ),
    child: child!,
  ),
  home: ThemeSpecScope(
    spec: applicationThemeForAppearance(
      _appearanceSettings(
        background: outerBackground,
        accentHue: hue,
        neon: neon,
      ),
    ),
    child: StandardVisualScope(
      settings: StandardVisualSettings(
        backgroundId: outerBackground,
        accentHue: hue,
        neon: neon,
        rainbow: neon,
      ),
      child: OpportunitiesTheme(child: Center(child: child)),
    ),
  ),
);

ThemeSpec _appearanceSpec({
  String background = 'greenhouse',
  double hue = 158,
  bool neon = false,
}) => OpportunitiesVisualSpec.forAppearance(
  applicationThemeForAppearance(
    _appearanceSettings(background: background, accentHue: hue, neon: neon),
  ),
);

AppearanceSettings _appearanceSettings({
  required String background,
  double accentHue = 158,
  bool neon = false,
}) => AppearanceSettings(
  background: background,
  accentHue: accentHue,
  neon: neon,
  particleStyle: 'none',
  particleMinSize: 1,
  particleMaxSize: 1,
  particleHue: accentHue,
  buttonEffect: 'glow',
  buttonEffectHue: accentHue,
);
