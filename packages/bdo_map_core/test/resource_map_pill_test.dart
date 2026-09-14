import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:bdo_map_core/src/widgets/resource_map_chrome_theme.dart';
import 'package:bdo_map_core/src/widgets/resource_map_panel_metrics.dart';
import 'package:bdo_map_core/src/widgets/resource_map_pill.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/map_menu_capture.dart';

const _first = ValueKey('first-pill');
const _second = ValueKey('second-pill');
const _capture = ValueKey('pill-capture');
const _background = Color(0xff63816b);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final opacity in [0.0, .25, .6, 1.0]) {
    testWidgets('opacity $opacity changes backing, never the foreground', (
      tester,
    ) async {
      await _open(tester, opacity: opacity);
      final strength = math.max(.02, opacity);
      final decoration = _fill(tester);
      final gradient = decoration.gradient! as LinearGradient;
      expect(gradient.colors[0].a, closeTo(.96 * strength, .00001));
      expect(gradient.colors[1].a, closeTo(.98 * strength, .00001));
      expect(decoration.border!.top.color.a, closeTo(.34 * strength, .00001));
      expect(_shadow(tester).color.a, closeTo(.22 * strength, .00001));
      final backdrop = tester.widget<BackdropFilter>(
        find.descendant(
          of: find.byKey(_first),
          matching: find.byType(BackdropFilter),
        ),
      );
      final sigma = 14.0 * math.min(1.0, strength / .6);
      expect(
        backdrop.filter,
        ui.ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
        reason:
            'Below 60%, blur fades too instead of leaving a solid-looking plate.',
      );

      final paragraph = tester.widget<RichText>(
        find.descendant(
          of: find.text('Iron Ore'),
          matching: find.byType(RichText),
        ),
      );
      final style = (paragraph.text as TextSpan).style!;
      expect(style.color, ResourceMapChromeThemeData.glassDock.readingInk);
      expect(style.color!.a, 1);
      expect(style.fontSize, ResourceMapPanelMetrics.optionLabel);
      expect(style.fontWeight, FontWeight.w700);
      expect(
        tester.widget<Icon>(find.byIcon(Icons.chevron_right).first).color!.a,
        1,
      );
      expect(
        find.descendant(
          of: find.byType(ResourceMapPill),
          matching: find.byType(Opacity),
        ),
        findsNothing,
        reason: 'Only glass changes opacity; descendants must stay readable.',
      );
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('each option owns its own clipped material and clear gap', (
    tester,
  ) async {
    await _open(tester, gap: 48);
    expect(find.byType(ResourceMapPill), findsNWidgets(2));
    expect(find.byType(BackdropFilter), findsNWidgets(2));
    for (final key in [_first, _second]) {
      expect(
        find.descendant(of: find.byKey(key), matching: find.byType(ClipRRect)),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(key),
          matching: find.byType(AnimatedContainer),
        ),
        findsOneWidget,
      );
    }
    final first = tester.getRect(find.byKey(_first));
    final second = tester.getRect(find.byKey(_second));
    expect(second.top - first.bottom, 48);
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(_capture),
    );
    final origin = tester.getTopLeft(find.byKey(_capture));
    final centerGap =
        Offset(first.center.dx, (first.bottom + second.top) / 2) - origin;
    final pixel = await tester.runAsync(() async {
      final image = await boundary.toImage();
      try {
        final bytes = (await image.toByteData(
          format: ui.ImageByteFormat.rawRgba,
        ))!;
        final index =
            (centerGap.dy.round() * image.width + centerGap.dx.round()) * 4;
        return List<int>.generate(4, (i) => bytes.getUint8(index + i));
      } finally {
        image.dispose();
      }
    });
    expect(pixel, [
      0x63,
      0x81,
      0x6b,
      0xff,
    ], reason: 'There is no shared painted list box.');
  });

  testWidgets('pointer and keyboard keep both child actions and semantics', (
    tester,
  ) async {
    final activated = <String>[];
    final firstFocus = FocusNode();
    final secondFocus = FocusNode();
    addTearDown(firstFocus.dispose);
    addTearDown(secondFocus.dispose);
    await _open(
      tester,
      opacity: 0,
      onPressed: activated.add,
      firstFocus: firstFocus,
      secondFocus: secondFocus,
    );
    final semantics = tester.ensureSemantics();
    expect(find.bySemanticsLabel('Iron Ore'), findsOneWidget);
    expect(find.bySemanticsLabel('Houses'), findsOneWidget);
    await tester.tap(find.text('Iron Ore'));
    await tester.pumpAndSettle();
    expect(activated, ['Iron Ore']);
    firstFocus.requestFocus();
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pumpAndSettle();
    expect(secondFocus.hasFocus, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pumpAndSettle();
    expect(activated, ['Iron Ore', 'Iron Ore', 'Houses']);
    semantics.dispose();
    expect(tester.takeException(), isNull);
  });

  testWidgets('hover and focus are visible and return to the idle opacity', (
    tester,
  ) async {
    final focus = FocusNode();
    addTearDown(focus.dispose);
    await _open(tester, opacity: 0, firstFocus: focus);
    final idle = _fill(tester);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: const Offset(700, 500));
    await mouse.moveTo(tester.getCenter(find.byKey(_first)));
    await tester.pumpAndSettle();
    expect(_firstFillAlpha(tester), greaterThan(_firstColorAlpha(idle)));
    expect(
      _fill(tester).border!.top.color.a,
      greaterThan(idle.border!.top.color.a),
    );
    await mouse.moveTo(const Offset(700, 500));
    await tester.pumpAndSettle();
    expect(_fill(tester), idle);
    focus.requestFocus();
    await tester.pumpAndSettle();
    expect(_firstFillAlpha(tester), greaterThan(_firstColorAlpha(idle)));
    expect(_fill(tester).border!.top.color.a, greaterThan(.5));
    focus.unfocus();
    await tester.pumpAndSettle();
    expect(_fill(tester), idle);
    await mouse.removePointer();
  });

  testWidgets('reduced motion removes the pill transition but not hover', (
    tester,
  ) async {
    await _open(tester, opacity: 0, reducedMotion: true);
    expect(_container(tester).duration, Duration.zero);
    final before = _firstFillAlpha(tester);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: const Offset(700, 500));
    await mouse.moveTo(tester.getCenter(find.byKey(_first)));
    await tester.pump();
    expect(_firstFillAlpha(tester), greaterThan(before));
    // InkWell owns its own feedback. The pill backing itself must already
    // paint the final decoration after one frame, without interpolation.
    final paintedFill = tester
        .widgetList<DecoratedBox>(
          find.descendant(
            of: find.byKey(_first),
            matching: find.byType(DecoratedBox),
          ),
        )
        .map((widget) => widget.decoration)
        .whereType<BoxDecoration>()
        .singleWhere((decoration) => decoration.gradient != null);
    expect(paintedFill, _fill(tester));
    await mouse.removePointer();
    await tester.pumpAndSettle();
  });

  testWidgets('ordinary motion is short and settles without a pending ticker', (
    tester,
  ) async {
    await _open(tester, opacity: .6);
    expect(_container(tester).duration, const Duration(milliseconds: 150));
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: const Offset(700, 500));
    await mouse.moveTo(tester.getCenter(find.byKey(_first)));
    await tester.pump();
    expect(tester.hasRunningAnimations, isTrue);
    await tester.pump(const Duration(milliseconds: 200));
    expect(tester.hasRunningAnimations, isFalse);
    await mouse.removePointer();
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox.shrink());
    expect(tester.takeException(), isNull);
  });

  testWidgets('selected option remains distinct without fading child artwork', (
    tester,
  ) async {
    await _open(tester, opacity: 0, selected: true);
    expect(_firstFillAlpha(tester), greaterThan(.02));
    expect(_fill(tester).border!.top.color.a, greaterThan(.5));
    expect(_shadow(tester).color.a, closeTo(.22 * .02, .00001));
    final asset = tester.widget<Image>(
      find.byKey(const ValueKey('Iron Ore-artwork')),
    );
    expect(asset.opacity, isNull);
    expect(asset.color, isNull);
    expect(asset.width, ResourceMapPanelMetrics.optionArtwork);
  });

  testWidgets('real-font two-option opacity review', (tester) async {
    await tester.runAsync(loadMapMenuCaptureFonts);
    for (final opacity in [1.0, .6, 0.0]) {
      await _open(tester, opacity: opacity, patterned: true);
      await captureMapMenu(
        tester,
        boundary: find.byKey(_capture),
        name: 'separate-pills-opacity-${(opacity * 100).round()}',
      );
      expect(tester.takeException(), isNull);
    }
  });
}

Future<void> _open(
  WidgetTester tester, {
  double opacity = 1,
  double gap = ResourceMapPanelMetrics.optionGap,
  bool reducedMotion = false,
  bool selected = false,
  bool patterned = false,
  ValueChanged<String>? onPressed,
  FocusNode? firstFocus,
  FocusNode? secondFocus,
}) async {
  final chrome = ResourceMapChromeThemeData.glassDock.withUiOpacity(opacity);
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(fontFamily: 'Segoe UI'),
      home: MediaQuery(
        data: MediaQueryData(disableAnimations: reducedMotion),
        child: ResourceMapChromeTheme(
          data: chrome,
          child: Align(
            alignment: Alignment.topLeft,
            child: RepaintBoundary(
              key: _capture,
              child: SizedBox(
                width: 360,
                height: 220,
                child: CustomPaint(
                  painter: _BackgroundPainter(patterned: patterned),
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _option(
                          chrome,
                          key: _first,
                          label: 'Iron Ore',
                          asset: 'iron_ore',
                          selected: selected,
                          focus: firstFocus,
                          onPressed: onPressed,
                        ),
                        SizedBox(height: gap),
                        _option(
                          chrome,
                          key: _second,
                          label: 'Houses',
                          asset: 'house',
                          focus: secondFocus,
                          onPressed: onPressed,
                        ),
                      ],
                    ),
                  ),
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

Widget _option(
  ResourceMapChromeThemeData chrome, {
  required Key key,
  required String label,
  required String asset,
  bool selected = false,
  FocusNode? focus,
  ValueChanged<String>? onPressed,
}) => SizedBox(
  width: ResourceMapPanelMetrics.menuWidth,
  child: ResourceMapPill(
    key: key,
    selected: selected,
    child: InkWell(
      focusNode: focus,
      onTap: () => onPressed?.call(label),
      child: SizedBox(
        height: ResourceMapPanelMetrics.optionHeight,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Row(
            children: [
              Image.asset(
                'assets/images/menu_artwork/$asset.webp',
                key: ValueKey('$label-artwork'),
                package: 'bdo_map_core',
                width: ResourceMapPanelMetrics.optionArtwork,
                height: ResourceMapPanelMetrics.optionArtwork,
                excludeFromSemantics: true,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    color: chrome.readingInk,
                    fontSize: ResourceMapPanelMetrics.optionLabel,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Icon(Icons.chevron_right, color: chrome.readingInk, size: 19),
            ],
          ),
        ),
      ),
    ),
  ),
);

AnimatedContainer _container(WidgetTester tester) =>
    tester.widget<AnimatedContainer>(
      find.descendant(
        of: find.byKey(_first),
        matching: find.byType(AnimatedContainer),
      ),
    );

BoxDecoration _fill(WidgetTester tester) =>
    _container(tester).decoration! as BoxDecoration;

double _firstColorAlpha(BoxDecoration decoration) =>
    (decoration.gradient! as LinearGradient).colors.first.a;

double _firstFillAlpha(WidgetTester tester) => _firstColorAlpha(_fill(tester));

BoxShadow _shadow(WidgetTester tester) => tester
    .widgetList<DecoratedBox>(
      find.descendant(
        of: find.byKey(_first),
        matching: find.byType(DecoratedBox),
      ),
    )
    .map((widget) => widget.decoration)
    .whereType<BoxDecoration>()
    .firstWhere((decoration) => decoration.boxShadow?.isNotEmpty ?? false)
    .boxShadow!
    .single;

class _BackgroundPainter extends CustomPainter {
  const _BackgroundPainter({required this.patterned});
  final bool patterned;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = _background);
    if (!patterned) return;
    for (var x = -size.height; x < size.width; x += 35) {
      canvas.drawLine(
        Offset(x, 0),
        Offset(x + size.height, size.height),
        Paint()
          ..color = const Color(0xff304e54)
          ..strokeWidth = 17,
      );
    }
  }

  @override
  bool shouldRepaint(_BackgroundPainter oldDelegate) =>
      patterned != oldDelegate.patterned;
}
