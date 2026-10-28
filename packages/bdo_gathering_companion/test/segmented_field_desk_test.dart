import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:bdo_gathering_companion/src/ui/field_desk_materials.dart';
import 'package:bdo_gathering_companion/src/ui/theme.dart';
import 'package:bdo_gathering_companion/src/ui/visual_palette.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _size = Size(260, 96);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final palette = CompanionVisualPalette.decode(
    const String.fromEnvironment('GATHERING_VISUAL_PALETTE'),
  );

  for (final percent in [0, 60, 100]) {
    for (final partial in [false, true]) {
      test(
        'segmented fill preserves alpha and body ($percent / $partial)',
        () async {
          final glass = CompanionGlassTheme.fromPercent(
            percent,
            visualPalette: palette,
          );
          final base = BoxDecoration(
            gradient: glass.surfaceGradient,
            borderRadius: BorderRadius.circular(10),
          );
          final segmented =
              glass.segmentedDecoration(
                    base,
                    leadingWidth: 60,
                    leadingHeight: partial ? 56 : null,
                    trailingWidth: 38,
                  )
                  as SegmentedGlassDecoration;
          final original = await _pixels(base);
          final result = await _pixels(segmented);
          for (var y = 4; y < _size.height - 4; y++) {
            for (var x = 4; x < _size.width - 4; x++) {
              // The only alpha additions are the intentional one-pixel seams.
              if ((x - 60).abs() <= 1 || (x - 222).abs() <= 1) continue;
              final at = (y * _size.width.toInt() + x) * 4;
              expect(
                (result[at + 3] - original[at + 3]).abs(),
                lessThanOrEqualTo(1),
                reason: 'Material alpha changed at $x,$y',
              );
              if (x > 62 && x < 220 || partial && y > 58 && x < 58) {
                for (var channel = 0; channel < 3; channel++) {
                  expect(
                    (result[at + channel] - original[at + channel]).abs(),
                    lessThanOrEqualTo(1),
                    reason: 'Reading face changed at $x,$y',
                  );
                }
              }
            }
          }
          expect(
            result[3],
            0,
            reason: 'Rounded top corner remains transparent.',
          );
          final art = (24 * _size.width.toInt() + 24) * 4;
          expect(
            result.sublist(art, art + 3),
            isNot(original.sublist(art, art + 3)),
            reason:
                'The artwork lane must be a distinct material, not an inert option.',
          );
          expect(segmented.base, same(base));
          expect(segmented.leadingHeight, partial ? 56 : null);
        },
      );
    }
  }

  testWidgets(
    'segmented controls retain editors, focus, actions and idle bounds',
    (tester) async {
      final percent = ValueNotifier(60);
      final controller = TextEditingController(text: '1800');
      final focus = FocusNode();
      addTearDown(percent.dispose);
      addTearDown(controller.dispose);
      addTearDown(focus.dispose);
      var taps = 0;
      await tester.pumpWidget(
        ValueListenableBuilder<int>(
          valueListenable: percent,
          builder: (context, value, _) => MaterialApp(
            theme: companionTheme(
              opacityPercent: value,
              visualPalette: palette,
            ),
            home: Scaffold(
              body: Center(
                child: SizedBox(
                  width: 280,
                  child: GlassControl(
                    key: const ValueKey('segmented-control'),
                    leadingWidth: 60,
                    trailingWidth: 40,
                    child: Row(
                      children: [
                        const SizedBox(
                          width: 60,
                          child: Icon(Icons.inventory_2_outlined),
                        ),
                        Expanded(
                          child: TextField(
                            controller: controller,
                            focusNode: focus,
                          ),
                        ),
                        SizedBox(
                          width: 40,
                          child: IconButton(
                            onPressed: () => taps++,
                            icon: const Icon(Icons.check),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final control = find.byKey(const ValueKey('segmented-control'));
      final bounds = tester.getRect(control);
      final editor = tester.element(find.byType(TextField));
      await tester.enterText(find.byType(TextField), '1875');
      for (final value in [0, 100, 60]) {
        percent.value = value;
        await tester.pumpAndSettle();
        expect(tester.element(find.byType(TextField)), same(editor));
        expect(controller.text, '1875');
        expect(focus.hasFocus, isTrue);
        expect(tester.getRect(control), bounds);
      }
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      await mouse.moveTo(bounds.center);
      await tester.pumpAndSettle();
      expect(tester.getRect(control), bounds);
      await tester.tap(find.byType(IconButton));
      await tester.pumpAndSettle();
      expect(taps, 1);
      expect(
        find.descendant(of: control, matching: find.byType(BackdropFilter)),
        findsNothing,
      );
      expect(
        find.descendant(of: control, matching: find.byType(Opacity)),
        findsNothing,
      );
      expect(tester.binding.hasScheduledFrame, isFalse);
      await mouse.removePointer();
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('segmented desk opts in without altering plain panels', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: companionTheme(visualPalette: palette),
        home: const Scaffold(
          body: Column(
            children: [
              FieldDeskPanel(
                key: ValueKey('plain-desk'),
                child: SizedBox(width: 260, height: 64),
              ),
              FieldDeskPanel(
                key: ValueKey('crafted-desk'),
                leadingWidth: 60,
                child: SizedBox(width: 260, height: 64),
              ),
            ],
          ),
        ),
      ),
    );
    for (final (key, split) in [
      ('plain-desk', false),
      ('crafted-desk', true),
    ]) {
      final surface = find.byKey(ValueKey(key));
      final container = tester.widget<AnimatedContainer>(
        find.descendant(of: surface, matching: find.byType(AnimatedContainer)),
      );
      expect(container.decoration is SegmentedGlassDecoration, split);
      expect(tester.getSize(surface), const Size(262, 66));
    }
    await tester.pumpAndSettle();
    expect(tester.binding.hasScheduledFrame, isFalse);
    expect(tester.takeException(), isNull);
  });

  test('bounded plain versus segmented eighteen-card paint cost', () async {
    final glass = CompanionGlassTheme.fromPercent(60, visualPalette: palette);
    final base = BoxDecoration(
      gradient: glass.controlGradient,
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: glass.line),
    );
    final results = <String, Object>{};
    for (final (name, decoration) in [
      ('plain', base),
      (
        'segmented',
        glass.segmentedDecoration(base, leadingWidth: 60, trailingWidth: 38),
      ),
    ]) {
      final painter = decoration.createBoxPainter();
      final record = <int>[], raster = <int>[];
      for (var pass = 0; pass < 12; pass++) {
        final watch = Stopwatch()..start();
        final recorder = ui.PictureRecorder();
        final canvas = Canvas(recorder);
        for (var i = 0; i < 18; i++) {
          painter.paint(
            canvas,
            Offset((i % 3) * 280.0, (i ~/ 3) * 72.0),
            const ImageConfiguration(
              size: Size(260, 64),
              textDirection: TextDirection.ltr,
            ),
          );
        }
        final picture = recorder.endRecording();
        final recorded = watch.elapsedMicroseconds;
        watch.reset();
        final image = await picture.toImage(840, 432);
        final rasterized = watch.elapsedMicroseconds;
        if (pass >= 3) {
          record.add(recorded);
          raster.add(rasterized);
        }
        image.dispose();
        picture.dispose();
      }
      painter.dispose();
      record.sort();
      raster.sort();
      results[name] = {
        'recordMedianUs': record[4],
        'recordP95Us': record.last,
        'rasterMedianUs': raster[4],
        'rasterP95Us': raster.last,
      };
      expect(record[4], lessThan(1000000));
      expect(raster[4], lessThan(5000000));
    }
    final directory = Platform.environment['CODEX_GATHERING_CAPTURE_DIR'];
    if (directory != null) {
      await Directory(directory).create(recursive: true);
      await File(
        '$directory/segmented-paint-cost.json',
      ).writeAsString(const JsonEncoder.withIndent('  ').convert(results));
    }
    // Diagnostic comparison, not a release-mode FPS claim.
    debugPrint('Gathering segmented material cost: ${jsonEncode(results)}');
  });
}

Future<Uint8List> _pixels(Decoration decoration) async {
  final recorder = ui.PictureRecorder();
  final painter = decoration.createBoxPainter();
  painter.paint(
    Canvas(recorder),
    Offset.zero,
    const ImageConfiguration(size: _size, textDirection: TextDirection.ltr),
  );
  final picture = recorder.endRecording();
  final image = await picture.toImage(
    _size.width.toInt(),
    _size.height.toInt(),
  );
  final bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  final result = Uint8List.fromList(bytes!.buffer.asUint8List());
  image.dispose();
  picture.dispose();
  painter.dispose();
  return result;
}
