import 'package:bdo_craft_planner_flutter/features/planner/planner_content_viewport.dart';
import 'package:bdo_craft_planner_flutter/visual/visual.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('fit limits retain existing command and panel layout branches', () {
    double fit(double width, bool dense, [double text = 1]) =>
        plannerContentMaximumScale(
          size: Size(width, 900),
          denseLayout: dense,
          textScale: text,
        );
    expect(fit(1282, true), 1.25);
    expect(fit(916, true), 1.05);
    expect(fit(1216, false), 1.07);
    expect(fit(720, true), 1);
    // The real row is already inline before its decorative safety margin.
    // Crossing that narrow gap must cap zoom, not disable its protection.
    expect(fit(1282, true, 1.5), 1);
    for (final dense in [false, true]) {
      for (final text in [1.0, 1.3, 2.0]) {
        for (var width = 760.0; width < 1900; width += 3) {
          final scaledWidth = width / fit(width, dense, text);
          expect(scaledWidth, greaterThanOrEqualTo(760));
          final thresholds = <double>[
            12 + (400 + (dense ? 44 : 24)) / (dense ? .52 : .46),
            12 + (60 + 350 * text + (dense ? 74 : 54)) / (dense ? .52 : .46),
          ];
          if (dense && text <= 1.25 && width >= 844) {
            thresholds.add(844);
          } else if (!dense && text <= 1.25 && width >= 1134) {
            thresholds.add(1134);
          } else if (text <= 1.5) {
            thresholds.add(1124);
          }
          for (final threshold in thresholds) {
            if (width >= threshold) {
              expect(scaledWidth, greaterThanOrEqualTo(threshold - .0001));
            }
          }
        }
      }
    }
  });

  test('content-dependent boundaries retain existing rows at the fit edge', () {
    double fit(double width) => plannerContentMaximumScale(
      size: Size(width, 900),
      denseLayout: true,
      textScale: 1,
      queueBreakpoints: const [1122.97, 1500],
    );
    expect(fit(1282), 1.14);
    expect(fit(1123), 1);
    expect(fit(1500), 1);
    expect(fit(1900), 1.25);
  });

  testWidgets('zoom retains focus, geometry, hit testing and scroll state', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1500, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final scale = ValueNotifier(1.0);
    final focus = FocusNode();
    final scroll = ScrollController(initialScrollOffset: 200);
    final text = TextEditingController(text: '123');
    addTearDown(scale.dispose);
    addTearDown(focus.dispose);
    addTearDown(scroll.dispose);
    addTearDown(text.dispose);
    var taps = 0;
    double? maximum;
    await tester.pumpWidget(
      MaterialApp(
        home: ThemeSpecScope(
          spec: SakuraNightGardenSpec.theme,
          child: Material(
            child: Row(
              children: [
                const SizedBox(width: 220, child: Text('Navigation')),
                Expanded(
                  child: PlannerContentViewport(
                    scale: scale,
                    onMaximumChanged: (value) => maximum = value,
                    child: Column(
                      children: [
                        SizedBox(
                          height: 50,
                          child: TextField(controller: text, focusNode: focus),
                        ),
                        SizedBox(
                          height: 40,
                          child: TextButton(
                            onPressed: () => taps++,
                            child: const Text('Action'),
                          ),
                        ),
                        Expanded(
                          child: ListView.builder(
                            controller: scroll,
                            itemExtent: 50,
                            itemCount: 1000,
                            itemBuilder: (_, i) => Text('Item $i'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(maximum, 1.25);
    await tester.tap(find.byType(TextField));
    final fieldState = tester.state(find.byType(EditableText));
    final nav = tester.getRect(find.text('Navigation'));
    final position = scroll.position;
    scale.value = 1.25;
    await tester.pump();
    expect(tester.state(find.byType(EditableText)), same(fieldState));
    expect(focus.hasFocus, isTrue);
    expect(scroll.position, same(position));
    expect(scroll.offset, 200);
    expect(tester.getRect(find.text('Navigation')), nav);
    expect(tester.getRect(find.byType(TextField)).height, closeTo(62.5, .1));
    await tester.tap(find.text('Action'));
    expect(taps, 1);
    expect(find.text('Item 900'), findsNothing);
    scale.value = 1;
    await tester.pump();
    expect(tester.state(find.byType(EditableText)), same(fieldState));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
