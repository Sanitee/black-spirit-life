import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:bdo_gathering_companion/src/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

const _viewport = Size(800, 600);
const _roles = [
  'input',
  'row',
  'active',
  'hover',
  'selection',
  'popup',
  'group',
  'iconWell',
  'header',
];
const _foregrounds = {
  'ink': ink,
  'muted': muted,
  'blue': accent,
  'positive': positive,
};

void main() {
  for (final percent in [0, 60, 100]) {
    for (final modal in [false, true]) {
      final mode = modal ? 'dialog' : 'main';
      testWidgets('$mode glass retains readable text at $percent% opacity', (
        tester,
      ) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = _viewport;
        addTearDown(tester.view.reset);
        final captureKey = GlobalKey();
        final hostKey = GlobalKey();
        await tester.pumpWidget(
          RepaintBoundary(
            key: captureKey,
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: companionTheme(opacityPercent: percent),
              builder: companionBackdropBuilder,
              home: Scaffold(
                key: hostKey,
                body: Padding(
                  padding: const EdgeInsets.all(8),
                  // Reading overlays must also protect text over the bright
                  // underlying action when the user's map glass is fully clear.
                  child: const _ProbeSurface(id: 'main'),
                ),
              ),
            ),
          ),
        );
        if (modal) {
          unawaited(
            showDialog<void>(
              context: hostKey.currentContext!,
              barrierDismissible: false,
              builder: (context) => const Dialog(
                insetPadding: EdgeInsets.all(8),
                backgroundColor: Colors.transparent,
                elevation: 0,
                child: _ProbeSurface(id: 'dialog'),
              ),
            ),
          );
        }
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);

        final pixels = (await tester.runAsync(() async {
          final boundary =
              captureKey.currentContext!.findRenderObject()!
                  as RenderRepaintBoundary;
          final image = await boundary.toImage(pixelRatio: 1);
          try {
            final bytes = await image.toByteData(
              format: ui.ImageByteFormat.rawRgba,
            );
            return _Pixels(image.width, bytes!);
          } finally {
            image.dispose();
          }
        }))!;

        final excluded = <Rect>[];
        final samples = <String, _Sample>{};
        for (var column = 0; column < 3; column++) {
          for (final role in _roles) {
            final rect = tester.getRect(
              find.byKey(ValueKey('$mode-$column-$role')),
            );
            excluded.add(rect.inflate(3));
            samples['$role/$column'] = pixels.brightest(rect.deflate(5));
          }
        }
        final artworkSamples = <Color>[];
        for (final role in ['toolPlate', 'toolPlateSelected']) {
          final rect = tester.getRect(find.byKey(ValueKey('$mode-$role')));
          excluded.add(rect.inflate(3));
          artworkSamples.add(pixels.at(rect.center));
        }
        final primaryRect = tester.getRect(
          find.byKey(ValueKey('$mode-primary')),
        );
        excluded.add(primaryRect.inflate(3));
        final primaryBase = pixels.brightest(
          primaryRect.deflate(5),
          darkest: true,
        );
        expect(
          _contrast(const Color(0xFF071013), primaryBase.color),
          greaterThanOrEqualTo(4.5),
          reason:
              '$mode $percent% primary action text on ${_hex(primaryBase.color)}',
        );
        for (final entry in _foregrounds.entries) {
          final rect = tester.getRect(
            find.byKey(ValueKey('$mode-${entry.key}')),
          );
          excluded.add(rect.inflate(3));
          expect(
            pixels.at(rect.center).toARGB32(),
            entry.value.toARGB32(),
            reason:
                '$mode $percent% must preserve the selected ${entry.key} foreground',
          );
        }
        final panel = tester.getRect(find.byKey(ValueKey('$mode-panel')));
        samples['panel'] = pixels.brightest(
          panel.deflate(10),
          excluding: excluded,
        );
        if (percent >= defaultGlassOpacityPercent) {
          final panelBase = pixels.at(const Offset(750, 530));
          expect(
            artworkSamples.first.computeLuminance() -
                panelBase.computeLuminance(),
            greaterThan(.035),
            reason:
                'Original dark tools need a visibly lighter artwork plate than the reading panel',
          );
          expect(
            artworkSamples.last.computeLuminance(),
            greaterThan(artworkSamples.first.computeLuminance()),
            reason: 'The selected artwork plate keeps a separate raised state',
          );
        }
        if (percent == defaultGlassOpacityPercent) {
          // Blank shoulders avoid the bright glow peak and foreground controls.
          // Lock the expedition panel's light-to-dark face, not only its
          // contrast. Exact opaque preview tones are separately palette-tested;
          // these rendered default tones include native blur and modal layering.
          final expectedShades = modal
              ? const [Color(0xFF231D26), Color(0xFF211C24), Color(0xFF1F1A23)]
              : const [Color(0xFF261F26), Color(0xFF221C24), Color(0xFF201A22)];
          const points = [Offset(750, 60), Offset(750, 230), Offset(750, 420)];
          debugPrint(
            '$mode panel shades: ${points.map((p) => _hex(pixels.at(p))).join(', ')}',
          );
          for (var index = 0; index < points.length; index++) {
            final actual = pixels.at(points[index]);
            final expected = expectedShades[index];
            for (final shift in [16, 8, 0]) {
              final channel = (actual.toARGB32() >> shift) & 0xff;
              final target = (expected.toARGB32() >> shift) & 0xff;
              expect(
                (channel - target).abs(),
                lessThanOrEqualTo(4),
                reason:
                    '$mode default blank panel at ${points[index]} rendered '
                    '${_hex(actual)}; expected the reviewed ${_hex(expected)} '
                    'within four channel values, including its brightness',
              );
            }
          }
          for (final role in ['row', 'selection']) {
            final rect = tester.getRect(find.byKey(ValueKey('$mode-1-$role')));
            final upper = pixels.at(
              Offset(
                role == 'selection' ? rect.left + 6 : rect.center.dx,
                rect.top + 6,
              ),
            );
            final lower = pixels.at(
              Offset(
                role == 'selection' ? rect.right - 6 : rect.center.dx,
                rect.bottom - 6,
              ),
            );
            expect(
              upper.computeLuminance() - lower.computeLuminance(),
              greaterThan(.006),
              reason:
                  '$mode $role must retain a visibly lit gradient face, not regress to a flat fill',
            );
          }
        }

        final failures = <String>[];
        final minimums = <String, double>{};
        for (final entry in samples.entries) {
          for (final foreground in _foregrounds.entries) {
            final ratio = _contrast(foreground.value, entry.value.color);
            final previous = minimums[foreground.key];
            if (previous == null || ratio < previous) {
              minimums[foreground.key] = ratio;
            }
            if (ratio < 4.5) {
              failures.add(
                '${entry.key}: ${foreground.key} ${ratio.toStringAsFixed(3)}:1 '
                'over ${_hex(entry.value.color)} at ${entry.value.position}',
              );
            }
          }
        }
        // Rendered samples deliberately include the real blur, modal barrier,
        // nested alpha, and clearcoat. Raw tint contrast is not a substitute.
        debugPrint(
          '$mode $percent% rendered minima: '
          '${minimums.entries.map((e) => '${e.key}=${e.value.toStringAsFixed(3)}').join(', ')}; '
          'brightest panel ${_hex(samples['panel']!.color)} at ${samples['panel']!.position}',
        );
        expect(failures, isEmpty, reason: failures.join('\n'));
      });
    }
  }
}

class _ProbeSurface extends StatelessWidget {
  const _ProbeSurface({required this.id});
  final String id;

  @override
  Widget build(BuildContext context) => GlassSurface(
    reading: id == 'dialog',
    child: Builder(builder: _content),
  );

  Widget _content(BuildContext context) {
    final glass = context.glass;
    final paints = {
      'input': glass.row,
      'active': glass.active,
      'popup': glass.popup,
    };
    return SizedBox.expand(
      key: ValueKey('$id-panel'),
      child: Stack(
        children: [
          for (var column = 0; column < 3; column++)
            for (var row = 0; row < _roles.length; row++)
              Positioned(
                left: 40 + column * 245,
                top: 32 + row * 52,
                width: 160,
                height: 40,
                child: SizedBox.expand(
                  key: ValueKey('$id-$column-${_roles[row]}'),
                  child: switch (_roles[row]) {
                    'row' => const GlassControl(
                      radius: 8,
                      child: SizedBox.expand(),
                    ),
                    'hover' => const GlassControl(
                      radius: 8,
                      hovered: true,
                      child: SizedBox.expand(),
                    ),
                    'selection' => const GlassControl(
                      radius: 8,
                      selected: true,
                      child: SizedBox.expand(),
                    ),
                    'iconWell' => const GlassArtworkWell(
                      child: SizedBox.expand(),
                    ),
                    'group' => DecoratedBox(
                      decoration: BoxDecoration(gradient: glass.groupGradient),
                    ),
                    'header' => GlassSurface(
                      gradient: glass.headerGradient,
                      radius: 8,
                      child: const SizedBox.expand(),
                    ),
                    final role => Material(
                      color: paints[role],
                      borderRadius: BorderRadius.circular(8),
                      child: role == 'active'
                          ? const GlassSheen(
                              radius: 8,
                              child: SizedBox.expand(),
                            )
                          : const SizedBox.expand(),
                    ),
                  },
                ),
              ),
          for (var index = 0; index < 2; index++)
            Positioned(
              left: 40 + index * 104,
              top: 510,
              width: 88,
              height: 28,
              child: SizedBox.expand(
                key: ValueKey(
                  '$id-${index == 0 ? 'toolPlate' : 'toolPlateSelected'}',
                ),
                child: index == 0
                    ? const GlassArtworkWell(
                        tool: true,
                        child: SizedBox.expand(),
                      )
                    : ColoredBox(color: glass.toolPlateSelected),
              ),
            ),
          Positioned(
            left: 260,
            top: 510,
            width: 160,
            height: 40,
            child: GlassControl(
              key: ValueKey('$id-primary'),
              primary: true,
              child: const SizedBox.expand(),
            ),
          ),
          for (var index = 0; index < _foregrounds.length; index++)
            Positioned(
              left: 40 + index * 28,
              top: 548,
              width: 12,
              height: 12,
              child: ColoredBox(
                key: ValueKey('$id-${_foregrounds.keys.elementAt(index)}'),
                color: _foregrounds.values.elementAt(index),
              ),
            ),
        ],
      ),
    );
  }
}

class _Pixels {
  const _Pixels(this.width, this.bytes);
  final int width;
  final ByteData bytes;

  Color at(Offset point) {
    final offset = (point.dy.floor() * width + point.dx.floor()) * 4;
    return Color.fromARGB(
      bytes.getUint8(offset + 3),
      bytes.getUint8(offset),
      bytes.getUint8(offset + 1),
      bytes.getUint8(offset + 2),
    );
  }

  _Sample brightest(
    Rect rect, {
    List<Rect> excluding = const [],
    bool darkest = false,
  }) {
    _Sample? result;
    for (var y = rect.top.ceil(); y < rect.bottom.floor(); y += 2) {
      for (var x = rect.left.ceil(); x < rect.right.floor(); x += 2) {
        final point = Offset(x.toDouble(), y.toDouble());
        if (excluding.any((excluded) => excluded.contains(point))) continue;
        final color = at(point);
        if (result == null ||
            (darkest
                ? color.computeLuminance() < result.color.computeLuminance()
                : color.computeLuminance() > result.color.computeLuminance())) {
          result = _Sample(point, color);
        }
      }
    }
    return result!;
  }
}

class _Sample {
  const _Sample(this.position, this.color);
  final Offset position;
  final Color color;
}

double _contrast(Color foreground, Color background) {
  final first = foreground.computeLuminance();
  final second = background.computeLuminance();
  return first >= second
      ? (first + .05) / (second + .05)
      : (second + .05) / (first + .05);
}

String _hex(Color color) =>
    '#${(color.toARGB32() & 0xffffff).toRadixString(16).padLeft(6, '0').toUpperCase()}';
