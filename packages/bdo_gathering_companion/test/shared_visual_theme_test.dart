import 'dart:convert';
import 'dart:ui' as ui;

import 'package:bdo_gathering_companion/src/reference_feature.dart';
import 'package:bdo_gathering_companion/src/services/native_bridge.dart';
import 'package:bdo_gathering_companion/src/ui/reference_window.dart';
import 'package:bdo_gathering_companion/src/ui/theme.dart';
import 'package:bdo_gathering_companion/src/ui/visual_palette.dart';
import 'package:bdo_gathering_companion/src/widgets/spot_video_player.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const palette = CompanionVisualPalette.fieldDesk;
  test('glass keeps the reference pigment at every material alpha', () {
    final glass = CompanionGlassTheme.fromPercent(60, visualPalette: palette);
    const face = Color(0xFF3A2F36);
    for (final opacity in [.02, .25, .6, .7, .9, 1.0]) {
      final corrected = glass.materialPigment(face, opacity);
      expect(corrected.a, opacity);
      expect(corrected.withAlpha(255), face);
      expect(
        corrected.r.isFinite && corrected.g.isFinite && corrected.b.isFinite,
        isTrue,
      );
      for (final foreground in [palette.ink, palette.muted]) {
        final a = foreground.computeLuminance() + .05;
        final b = corrected.computeLuminance() + .05;
        expect(a > b ? a / b : b / a, greaterThanOrEqualTo(4.5));
      }
    }
    expect(glass.materialPigment(face, 1), face);
    expect(
      glass.materialPigment(face, .02).withAlpha(255),
      glass.materialPigment(face, .6).withAlpha(255),
    );
    final standalone = CompanionGlassTheme.fromPercent(60);
    expect(standalone.materialPigment(face, .6), face.withValues(alpha: .6));
  });

  test(
    'hosted density is smooth and preserves saved percentage and endpoints',
    () {
      double density(double alpha) {
        final unit = ((alpha - .02) / .98).clamp(0.0, 1.0);
        return .02 + .98 * (1 - (1 - unit) * (1 - unit));
      }

      var previous = .02;
      for (var percent = 0; percent <= 100; percent++) {
        final legacy = CompanionGlassTheme.fromPercent(percent);
        final hosted = CompanionGlassTheme.fromPercent(
          percent,
          visualPalette: palette,
        );
        expect(hosted.opacityPercent, percent);
        expect(
          hosted.surfaceOpacity,
          closeTo(density(legacy.surfaceOpacity), 1e-9),
        );
        expect(
          hosted.controlOpacity,
          closeTo(density(legacy.controlOpacity), 1e-9),
        );
        expect(
          hosted.selectedOpacity,
          closeTo(density(legacy.selectedOpacity), 1e-9),
        );
        expect(hosted.surfaceOpacity, greaterThanOrEqualTo(previous));
        expect(hosted.effectStrength, legacy.effectStrength);
        expect(hosted.backdropOpacity, legacy.backdropOpacity);
        previous = hosted.surfaceOpacity;
      }
      expect(
        CompanionGlassTheme.fromPercent(
          0,
          visualPalette: palette,
        ).surfaceOpacity,
        .02,
      );
      expect(
        CompanionGlassTheme.fromPercent(
          100,
          visualPalette: palette,
        ).surfaceOpacity,
        1,
      );
      final hosted = CompanionGlassTheme.fromPercent(
        60,
        visualPalette: palette,
      );
      expect(hosted.surfaceOpacity, closeTo(.836734693877551, 1e-9));
      expect(hosted.controlOpacity, inExclusiveRange(.89, .90));
      expect(CompanionGlassTheme.fromPercent(60).surfaceOpacity, .60);
    },
  );

  test('hosted header and artwork use the actual satin material roles', () {
    final hosted = CompanionGlassTheme.fromPercent(60, visualPalette: palette);
    expect(hosted.headerGradient, hosted.surfaceGradient);
    expect(hosted.headerGradient.begin, Alignment.topCenter);
    expect(hosted.headerGradient.end, Alignment.bottomCenter);
    expect(
      hosted.headerGradient.colors.first.withAlpha(255).toARGB32(),
      Color.alphaBlend(palette.ink.withAlpha(20), palette.raised).toARGB32(),
    );
    final decoration =
        hosted.segmentedDecoration(
              BoxDecoration(gradient: hosted.controlGradient),
              leadingWidth: 59,
            )
            as SegmentedGlassDecoration;
    expect(decoration.leadingWidth, 59);
    expect(decoration.bayLocalCoordinates, isTrue);
    expect(decoration.bayReliefStrength, hosted.effectStrength);
    expect(decoration.bay.begin, const Alignment(-1, -.45));
    expect(decoration.bay.end, const Alignment(1, .80));
    expect(decoration.bay.colors.every((c) => c.a > .89 && c.a < .90), isTrue);
    final standalone = CompanionGlassTheme.fromPercent(60);
    final oldDecoration =
        standalone.segmentedDecoration(
              BoxDecoration(gradient: standalone.controlGradient),
              leadingWidth: 59,
            )
            as SegmentedGlassDecoration;
    expect(oldDecoration.bayLocalCoordinates, isFalse);
    expect(oldDecoration.bayReliefStrength, 0);
    expect(oldDecoration.bay.begin, standalone.controlGradient.begin);
  });

  test('hosted interaction keeps the satin body instead of recolouring it', () {
    final hosted = CompanionGlassTheme.fromPercent(60, visualPalette: palette);
    final normal = hosted.controlGradient;
    for (final (gradient, tint) in [
      (hosted.hoverGradient, 3),
      (hosted.selectedGradient, 8),
    ]) {
      expect(gradient.stops, normal.stops);
      expect(gradient.begin, normal.begin);
      expect(gradient.end, normal.end);
      for (var index = 0; index < normal.colors.length; index++) {
        expect(
          gradient.colors[index].withAlpha(255).toARGB32(),
          Color.alphaBlend(
            palette.accent.withAlpha(tint),
            normal.colors[index].withAlpha(255),
          ).toARGB32(),
        );
        expect(
          gradient.colors[index].a,
          closeTo(normal.colors[index].a, 1e-12),
        );
      }
    }
  });

  test('copper is opt-in and retains every existing material alpha', () {
    Color sample(LinearGradient gradient, double position) {
      final stops = gradient.stops!;
      for (var i = 1; i < stops.length; i++) {
        if (position <= stops[i]) {
          return Color.lerp(
            gradient.colors[i - 1],
            gradient.colors[i],
            (position - stops[i - 1]) / (stops[i] - stops[i - 1]),
          )!;
        }
      }
      return gradient.colors.last;
    }

    for (final percent in [0, 25, 60, 100]) {
      final standalone = CompanionGlassTheme.fromPercent(percent);
      expect(standalone.copperCardGradient(), standalone.controlGradient);
      expect(
        standalone.copperCardGradient(selected: true),
        standalone.selectedGradient,
      );
      final glass = CompanionGlassTheme.fromPercent(
        percent,
        visualPalette: palette,
      );
      for (final selected in [false, true]) {
        final source = selected
            ? glass.selectedGradient
            : glass.controlGradient;
        final face = glass.copperCardGradient(selected: selected);
        expect(face.begin, Alignment.topCenter);
        expect(face.end, Alignment.bottomCenter);
        expect(face.stops, containsAll([0.0, .12, .44, .76, .92, 1.0]));
        expect(
          sample(face, .12).withAlpha(255).toARGB32(),
          Color.lerp(palette.raised, palette.accent, .26)!.toARGB32(),
        );
        for (final reflection in [.65, .85]) {
          final bay = glass.copperBayGradient(face, reflection: reflection);
          expect(bay.begin, const Alignment(-.84, -1));
          expect(bay.end, const Alignment(.84, 1));
          for (var step = 0; step <= 100; step++) {
            final t = step / 100;
            expect(sample(face, t).a, closeTo(sample(source, t).a, 1e-12));
            expect(sample(bay, t).a, closeTo(sample(source, t).a, 1e-12));
          }
          expect(
            bay.colors.map((c) => c.withAlpha(255)).toSet().length,
            greaterThanOrEqualTo(6),
          );
        }
        final idle = glass.copperBayGradient(face);
        final active = glass.copperBayGradient(face, reflection: .85);
        expect(
          sample(active, .31).computeLuminance(),
          greaterThan(sample(idle, .31).computeLuminance()),
        );
        expect(sample(active, .77), sample(idle, .77));
      }
    }
  });

  testWidgets('copper hover and focus change only the bay and upper rim', (
    tester,
  ) async {
    final focus = FocusNode();
    addTearDown(focus.dispose);
    var taps = 0;
    Future<void> show({bool reduced = false, bool hosted = true}) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: companionTheme(visualPalette: hosted ? palette : null),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(disableAnimations: reduced),
            child: child!,
          ),
          home: Scaffold(
            body: Center(
              child: RepaintBoundary(
                key: const ValueKey('copper-press-capture'),
                child: SizedBox(
                  width: 312,
                  height: 60,
                  child: GlassControl(
                    key: const ValueKey('copper-card'),
                    leadingWidth: 68,
                    radius: 8,
                    copperInlay: true,
                    child: InkWell(
                      focusNode: focus,
                      hoverColor: Colors.transparent,
                      focusColor: Colors.transparent,
                      onTap: () => taps++,
                      child: const SizedBox.expand(),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    SegmentedGlassDecoration finish() =>
        tester
                .widget<TweenAnimationBuilder<Decoration>>(
                  find.byKey(const ValueKey('glass-control-finish')),
                )
                .tween
                .end!
            as SegmentedGlassDecoration;
    BoxDecoration shadow() =>
        tester
                .widget<AnimatedContainer>(
                  find
                      .descendant(
                        of: find.byKey(const ValueKey('copper-card')),
                        matching: find.byType(AnimatedContainer),
                      )
                      .first,
                )
                .decoration!
            as BoxDecoration;
    void stationary() {
      expect(
        tester.getSize(find.byKey(const ValueKey('copper-card'))),
        const Size(312, 60),
      );
      expect(
        tester
            .widget<TweenAnimationBuilder<double>>(
              find.byKey(const ValueKey('glass-control-lift')),
            )
            .tween
            .end,
        0,
      );
      expect(tester.widget<AnimatedScale>(find.byType(AnimatedScale)).scale, 1);
    }

    Future<List<int>> rimPixels() async => (await tester.runAsync(() async {
      final boundary = tester.renderObject<RenderRepaintBoundary>(
        find.byKey(const ValueKey('copper-press-capture')),
      );
      final image = await boundary.toImage();
      final bytes = (await image.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      ))!.buffer.asUint8List();
      // The upper bevel, beyond the artwork bay, provides visible pressed
      // feedback without moving or tinting the reading content.
      final result = <int>[];
      for (var y = 0; y < 4; y++) {
        for (var x = 90; x < 290; x++) {
          final offset = (y * image.width + x) * 4;
          result.addAll(bytes.sublist(offset, offset + 4));
        }
      }
      image.dispose();
      return result;
    }))!;

    await show();
    final normal = finish();
    final normalShadow = shadow();
    expect(normal.leadingWidth, 68);
    final mouse = await tester.createGesture(kind: ui.PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(
      tester.getCenter(find.byKey(const ValueKey('copper-card'))),
    );
    await tester.pumpAndSettle();
    expect(finish().base.gradient, normal.base.gradient);
    expect(finish().bay, isNot(normal.bay));
    expect(shadow().boxShadow, normalShadow.boxShadow);
    expect(
      tester
          .widget<TweenAnimationBuilder<Decoration>>(
            find.byKey(const ValueKey('glass-control-finish')),
          )
          .duration,
      const Duration(milliseconds: 140),
    );
    stationary();
    await mouse.moveTo(Offset.zero);
    await tester.pumpAndSettle();
    expect(finish().bay, normal.bay);
    focus.requestFocus();
    await tester.pumpAndSettle();
    expect(focus.hasFocus, isTrue);
    expect(finish().base.gradient, normal.base.gradient);
    expect(finish().bay, isNot(normal.bay));
    expect(shadow().boxShadow, normalShadow.boxShadow);
    stationary();
    final releasedPixels = await rimPixels();
    final press = await tester.startGesture(
      tester.getCenter(find.byKey(const ValueKey('copper-card'))),
    );
    await tester.pump(const Duration(milliseconds: 80));
    stationary();
    expect(
      await rimPixels(),
      isNot(orderedEquals(releasedPixels)),
      reason: 'Held pointer reverses the bevel light without lift/scale.',
    );
    expect(tester.widget<InkWell>(find.byType(InkWell)).onTap, isNotNull);
    await press.up();
    await tester.pumpAndSettle();
    expect(taps, 1);
    expect(await rimPixels(), orderedEquals(releasedPixels));
    await mouse.removePointer();
    await show(reduced: true);
    expect(
      tester
          .widget<TweenAnimationBuilder<Decoration>>(
            find.byKey(const ValueKey('glass-control-finish')),
          )
          .duration,
      Duration.zero,
    );
    expect(
      tester
          .widget<TweenAnimationBuilder<double>>(
            find.byKey(const ValueKey('copper-rim-highlight')),
          )
          .duration,
      Duration.zero,
    );
    await tester.pumpWidget(const SizedBox.shrink());
    await show(hosted: false);
    final legacy = CompanionGlassTheme.fromPercent(60);
    expect(finish().base.gradient, legacy.controlGradient);
    final legacyRim = tester.widget<TweenAnimationBuilder<double>>(
      find.byKey(const ValueKey('copper-rim-highlight')),
    );
    expect(legacyRim.duration, Duration.zero);
    expect(legacyRim.tween.end, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('copper opt-in retains editable child state and focus', (
    tester,
  ) async {
    final focus = FocusNode();
    addTearDown(focus.dispose);
    Future<void> show(bool copper) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: companionTheme(visualPalette: palette),
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 312,
                height: 60,
                child: GlassControl(
                  key: const ValueKey('retained-copper-control'),
                  leadingWidth: 68,
                  copperInlay: copper,
                  child: TextField(
                    key: const ValueKey('retained-copper-editor'),
                    focusNode: focus,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    await show(false);
    final editor = find.byKey(const ValueKey('retained-copper-editor'));
    await tester.enterText(editor, 'Keep my entry');
    focus.requestFocus();
    await tester.pump();
    final state = tester.state(editor);
    for (final copper in [true, false, true]) {
      await show(copper);
      expect(tester.state(editor), same(state));
      expect(find.text('Keep my entry'), findsOneWidget);
      expect(focus.hasFocus, isTrue);
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('hosted compact cards retain raised edges and external contact', (
    tester,
  ) async {
    final oldShadows = debugDisableShadows;
    debugDisableShadows = false;
    try {
      var taps = 0;
      final paintedRims = <(int, bool), Color>{};
      final paintedGlints = <int, double>{};
      final paintedShadows = <int, double>{};
      final shadowDecorations = <int, Decoration>{};
      Future<List<int>> paintDecoration(Decoration decoration) async =>
          (await tester.runAsync(() async {
            final recorder = ui.PictureRecorder();
            final painter = decoration.createBoxPainter();
            painter.paint(
              Canvas(recorder),
              const Offset(16, 12),
              const ImageConfiguration(size: Size(312, 60)),
            );
            final picture = recorder.endRecording();
            final image = await picture.toImage(344, 92);
            final bytes = (await image.toByteData(
              format: ui.ImageByteFormat.rawRgba,
            ))!;
            final result = bytes.buffer.asUint8List().toList();
            image.dispose();
            picture.dispose();
            painter.dispose();
            return result;
          }))!;
      for (final (percent, selected) in [
        (0, false),
        (60, false),
        (60, true),
        (100, false),
        (100, true),
      ]) {
        await tester.pumpWidget(
          MaterialApp(
            theme: companionTheme(
              opacityPercent: percent,
              visualPalette: palette,
            ),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(disableAnimations: true),
              child: child!,
            ),
            home: Center(
              child: RepaintBoundary(
                key: const ValueKey('raised-card-paint'),
                child: SizedBox(
                  width: 344,
                  height: 92,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Positioned(
                        left: 16,
                        top: 12,
                        width: 312,
                        height: 60,
                        child: GlassControl(
                          key: const ValueKey('raised-card'),
                          radius: 8,
                          selected: selected,
                          leadingWidth: 59,
                          child: InkWell(
                            onTap: () => taps++,
                            child: const SizedBox.expand(),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final card = find.byKey(const ValueKey('raised-card'));
        expect(tester.getSize(card), const Size(312, 60));
        expect(tester.widget<GlassControl>(card).leadingWidth, 59);
        final boundary = tester.renderObject<RenderRepaintBoundary>(
          find.byKey(const ValueKey('raised-card-paint')),
        );
        final image = (await tester.runAsync(
          () => boundary.toImage(pixelRatio: 1),
        ))!;
        final bytes = (await tester.runAsync(
          () => image.toByteData(format: ui.ImageByteFormat.rawRgba),
        ))!;
        Color pixel(int x, int y) {
          final offset = (y * image.width + x) * 4;
          return Color.fromARGB(
            bytes.getUint8(offset + 3),
            bytes.getUint8(offset),
            bytes.getUint8(offset + 1),
            bytes.getUint8(offset + 2),
          );
        }

        final shadow = tester
            .widget<AnimatedContainer>(
              find.descendant(
                of: card,
                matching: find.byType(AnimatedContainer),
              ),
            )
            .decoration!;
        if (!selected) {
          shadowDecorations[percent] = shadow;
        }
        final shadowBytes = await paintDecoration(shadow);
        final finish = tester.widget<TweenAnimationBuilder<Decoration>>(
          find.byKey(const ValueKey('glass-control-finish')),
        );
        final referenceBytes = await paintDecoration(finish.tween.end!);
        for (final x in [40, 130]) {
          final offset = (42 * 344 + x) * 4;
          expect(
            shadowBytes[offset + 3],
            0,
            reason:
                'Contact paint may not fill the artwork bay or reading face.',
          );
          for (var channel = 0; channel < 4; channel++) {
            expect(
              bytes.getUint8(offset + channel),
              closeTo(referenceBytes[offset + channel], 1),
              reason: 'The actual face must match its no-shadow composite.',
            );
          }
        }
        if (percent > 0) {
          expect(shadowBytes[(76 * 344 + 130) * 4 + 3], greaterThan(0));
        }
        paintedRims[(percent, selected)] = pixel(327, 42);
        if (!selected) {
          paintedGlints[percent] = pixel(130, 12).a;
          paintedShadows[percent] = pixel(130, 76).a;
        }
        if (percent > 0) {
          expect(
            pixel(130, 12).computeLuminance(),
            greaterThan(pixel(130, 42).computeLuminance()),
            reason: 'The upper glint must read above the satin body.',
          );
          expect(
            pixel(130, 70).computeLuminance(),
            lessThan(pixel(130, 42).computeLuminance()),
            reason:
                'The lower lip must be a contact cut, not another bright rim.',
          );
        }
        if (percent > 0) {
          expect(
            pixel(130, 76).a,
            greaterThan(0),
            reason: 'Contact shadow must survive outside the 60px card.',
          );
        }
        image.dispose();
        expect(
          find.descendant(of: card, matching: find.byType(BackdropFilter)),
          findsNothing,
        );
        expect(
          find.descendant(of: card, matching: find.byType(Opacity)),
          findsNothing,
        );
        await tester.tap(card);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      }
      for (final percent in [60, 100]) {
        expect(
          paintedRims[(percent, true)],
          isNot(paintedRims[(percent, false)]),
          reason: 'The active semantic rim must remain distinct from idle.',
        );
      }
      expect(paintedGlints[0]!, lessThan(paintedGlints[60]!));
      expect(paintedShadows[0]!, lessThan(paintedShadows[60]!));
      for (final t in [.25, .5, .75]) {
        final tween = DecorationTween(
          begin: shadowDecorations[0],
          end: shadowDecorations[100],
        );
        final bytes = await paintDecoration(tween.lerp(t));
        expect(
          bytes[(42 * 344 + 130) * 4 + 3],
          0,
          reason:
              'AnimatedContainer interpolation must retain exterior clipping.',
        );
        expect(bytes[(76 * 344 + 130) * 4 + 3], greaterThan(0));
      }
      expect(taps, 5);
    } finally {
      debugDisableShadows = oldShadows;
    }
  });

  testWidgets(
    'recessed spot artwork is opt-in and retains its original bounds',
    (tester) async {
      for (final hosted in [false, true]) {
        await tester.pumpWidget(
          MaterialApp(
            theme: companionTheme(visualPalette: hosted ? palette : null),
            home: const Center(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  GameIcon('', key: ValueKey('ordinary-icon'), size: 44),
                  GameIcon(
                    '',
                    key: ValueKey('spot-icon'),
                    size: 44,
                    recessed: true,
                  ),
                ],
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        for (final key in ['ordinary-icon', 'spot-icon']) {
          expect(tester.getSize(find.byKey(ValueKey(key))), const Size(44, 44));
        }
        expect(
          find.byKey(const ValueKey('gathering-recessed-icon-well')),
          hosted ? findsOneWidget : findsNothing,
        );
        expect(
          find.descendant(
            of: find.byKey(const ValueKey('ordinary-icon')),
            matching: find.byKey(
              const ValueKey('gathering-recessed-icon-well'),
            ),
          ),
          findsNothing,
        );
        expect(tester.takeException(), isNull);
      }
    },
  );

  test('helper palette codec rejects malformed or oversized arguments', () {
    expect(
      CompanionVisualPalette.decode(palette.encode())?.encode(),
      palette.encode(),
    );
    for (final invalid in [null, '', '*', 'a' * 8193, 'abc=', 'AA', 'a']) {
      expect(CompanionVisualPalette.decode(invalid), isNull);
    }
    final json =
        jsonDecode(
              utf8.decode(
                base64Url.decode(base64Url.normalize(palette.encode())),
              ),
            )
            as Map<String, dynamic>;
    String payload() =>
        base64Url.encode(utf8.encode(jsonEncode(json))).replaceAll('=', '');
    json['version'] = 2;
    expect(CompanionVisualPalette.decode(payload()), isNull);
    json['version'] = 1;
    json['brightness'] = 'transparent';
    expect(CompanionVisualPalette.decode(payload()), isNull);
    json['brightness'] = 'dark';
    (json['colors'] as Map<String, dynamic>)['ink'] = 0x00FFFFFF;
    expect(CompanionVisualPalette.decode(payload()), isNull);
    expect(
      gatheringReferenceVisualPalette([
        '--reference',
        '--gathering-theme=${palette.encode()}',
      ])?.encode(),
      palette.encode(),
    );
    expect(gatheringReferenceVisualPalette(['--reference']), isNull);
  });

  test('native reference action carries only presentation data', () async {
    MethodCall? received;
    const channel = MethodChannel('bdo_gathering/native');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          received = call;
          return true;
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null),
    );
    expect(
      await NativeBridge.openReferenceWindow(
        glassOpacityPercent: 25,
        visualPalette: palette,
      ),
      isTrue,
    );
    expect(received!.method, 'openReferenceWindow');
    expect(received!.arguments, {
      'glassOpacityPercent': 25,
      'visualPalette': palette.encode(),
    });
  });

  testWidgets(
    'reading surfaces keep shared palette and independent opacity floors',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: companionTheme(opacityPercent: 25, visualPalette: palette),
          home: GlassSurface(
            reading: true,
            child: Builder(
              builder: (context) {
                expect(context.glass.visualPalette, same(palette));
                expect(context.glass.opacityPercent, 96);
                expect(context.glass.popup.a, greaterThanOrEqualTo(.98));
                expect(context.gatheringColors.ink.a, 1);
                return const Text('Reading');
              },
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'media placeholder stays legible on intentionally black video in light theme',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.light(),
          home: const Scaffold(
            body: SpotVideoPlayer(videoUrl: 'invalid', title: 'Video'),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final text = find.text('This is not a supported YouTube video link.');
      expect(text, findsOneWidget);
      expect(
        DefaultTextStyle.of(tester.element(text)).style.color,
        Colors.white,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('reference image plane uses semantic inset without tinting image', (
    tester,
  ) async {
    final data = await rootBundle.load(
      'packages/bdo_gathering_companion/assets/icons/sources/minigame_helper.png',
    );
    const channel = MethodChannel('bdo_gathering/native');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          channel,
          (call) async => call.method == 'readClipboardImage'
              ? data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes)
              : true,
        );
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null),
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: companionTheme(visualPalette: palette),
        home: const ReferenceWindow(),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('reference-paste')));
    await tester.pumpAndSettle();
    final imagePlane = find
        .ancestor(
          of: find.byType(InteractiveViewer),
          matching: find.byType(ColoredBox),
        )
        .first;
    expect(tester.widget<ColoredBox>(imagePlane).color, palette.inset);
    expect(tester.widget<Image>(find.byType(Image)).color, isNull);
    expect(tester.takeException(), isNull);
  });
}
