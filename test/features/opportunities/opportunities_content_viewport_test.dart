import 'dart:math' as math;
import 'package:bdo_craft_planner_flutter/features/opportunities/opportunities_content_viewport.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Exchange at 924 with 0.8 text keeps two columns after rounding', () {
    final maximum = opportunitiesContentMaximumScale(
      size: const Size(924, 800),
      section: 'exchanges',
      textScale: .8,
    );
    expect(maximum, 1.09);
    expect((924 / maximum / 420).floor(), 2);

    final exactMaximum = opportunitiesContentMaximumScale(
      size: const Size(1050, 800),
      section: 'exchanges',
      textScale: .8,
    );
    expect(exactMaximum, 1.25);
    expect(1050 / exactMaximum, 840);
    expect((1050 / exactMaximum / 420).floor(), 2);
  });

  test('compact toolbar at760 keeps search/modes and sort/filter runs', () {
    final top = opportunitiesWrapMinimumWidth(
      [280, 312],
      available: 760,
      spacing: 16,
    );
    final bottom =
        opportunitiesWrapMinimumWidth([240, 430], available: 744, spacing: 12) +
        16;
    final maximum = opportunitiesContentMaximumScale(
      size: const Size(760, 800),
      section: 'crafting',
      textScale: 1,
      cardBreakpoints: const [470],
      paneBreakpoints: [top, bottom],
    );
    expect(top, 608);
    expect(bottom, 698);
    expect(maximum, 1.08);
    final logical = 760 / maximum;
    expect(
      opportunitiesWrapMinimumWidth(
        [280, 312],
        available: logical,
        spacing: 16,
      ),
      top,
    );
    expect(
      opportunitiesWrapMinimumWidth(
            [240, 430],
            available: logical - 16,
            spacing: 12,
          ) +
          16,
      bottom,
    );
    expect(
      opportunitiesWrapMinimumWidth(
        [200, 200, 200],
        available: 500,
        spacing: 8,
      ),
      408,
    );
  });

  test('whole-percent fit preserves grids and all supplied card branches', () {
    for (final section in ['crafting', 'best-use', 'exchanges']) {
      for (final text in [0.8, 1.0, 1.3, 2.0]) {
        final breaks = section == 'best-use'
            ? [280 * text, 430 * text, 495 * text]
            : section == 'crafting'
            ? [180 * text, 240 * text, 280 * text]
            : [192 * text, 294 * text, 425 * text];
        for (var width = 360.0; width < 2400; width += 3) {
          final max = opportunitiesContentMaximumScale(
            size: Size(width, 800),
            section: section,
            textScale: text,
            cardBreakpoints: breaks,
          );
          expect(max, inInclusiveRange(1, 1.25));
          expect(max * 100, closeTo((max * 100).roundToDouble(), .0001));
          final end = width / max;
          int columns(double w) => section == 'exchanges'
              ? (w / (420 * text.clamp(1, 2))).floor().clamp(1, 3)
              : section == 'crafting'
              ? ((w + 16) / (300 * text + 16)).floor().clamp(1, 6)
              : ((w + 16) / (380 * text + 16)).floor().clamp(1, 3);
          double inner(double w) => section == 'exchanges'
              ? math.min(
                      560 * text.clamp(1, 2),
                      (w - (columns(w) - 1) * 12) / columns(w),
                    ) -
                    28
              : math.min(
                      (section == 'crafting' ? 332 : 640) * text,
                      (w - 5 - (columns(w) - 1) * 16) / columns(w),
                    ) -
                    28;
          expect(columns(end), columns(width), reason: '$section $text $width');
          for (final threshold in breaks) {
            expect(
              inner(end) >= threshold - .00001,
              inner(width) >= threshold - .00001,
              reason: '$section $text $width threshold$threshold max$max',
            );
          }
          if (section == 'exchanges') {
            expect(end >= 680 * text + 28, width >= 680 * text + 28);
          }
        }
      }
    }
  });

  testWidgets(
    'preview retains child, focus, scroll, hit testing and unscaled navigation',
    (tester) async {
      tester.view.physicalSize = const Size(1600, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final scale = ValueNotifier(1.0);
      final focus = FocusNode();
      final scroll = ScrollController(initialScrollOffset: 200);
      final text = TextEditingController(text: 'Beer');
      addTearDown(scale.dispose);
      addTearDown(focus.dispose);
      addTearDown(scroll.dispose);
      addTearDown(text.dispose);
      var builds = 0;
      var fits = 0;
      var taps = 0;
      final child = Builder(
        builder: (context) {
          builds++;
          return Column(
            children: [
              TextField(
                key: const ValueKey('search'),
                focusNode: focus,
                controller: text,
              ),
              TextButton(onPressed: () => taps++, child: const Text('Action')),
              Expanded(
                child: ListView.builder(
                  controller: scroll,
                  itemExtent: 50,
                  itemCount: 1000,
                  itemBuilder: (_, i) => Text('Item $i'),
                ),
              ),
            ],
          );
        },
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Material(
            child: Row(
              children: [
                const SizedBox(
                  key: ValueKey('nav'),
                  width: 180,
                  child: Text('Navigation'),
                ),
                Expanded(
                  child: OpportunitiesContentViewport(
                    scale: scale,
                    maximumFor: (_) {
                      fits++;
                      return 1.25;
                    },
                    child: child,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      final nav = tester.getRect(find.byKey(const ValueKey('nav')));
      focus.requestFocus();
      await tester.pump();
      final buildBefore = builds;
      final fitBefore = fits;
      final state = tester.state(find.byType(EditableText));
      for (var i = 101; i <= 125; i++) {
        scale.value = i / 100;
        await tester.pump();
      }
      expect(builds, buildBefore);
      expect(fits, fitBefore);
      expect(tester.state(find.byType(EditableText)), same(state));
      expect(focus.hasFocus, isTrue);
      expect(text.text, 'Beer');
      expect(scroll.offset, 200);
      expect(tester.getRect(find.byKey(const ValueKey('nav'))), nav);
      await tester.tap(find.text('Action'));
      await tester.pump();
      expect(taps, 1);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
