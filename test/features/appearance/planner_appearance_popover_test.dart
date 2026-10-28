import 'package:bdo_craft_planner_flutter/features/appearance/planner_appearance_popover.dart';
import 'package:bdo_craft_planner_flutter/shared/overlays/anchored_popover.dart';
import 'package:bdo_craft_planner_flutter/visual/visual.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'slider previews live and commits on pointer and keyboard release',
    (tester) async {
      var requested = 1.0;
      var commits = 0;
      late StateSetter rebuild;
      await tester.pumpWidget(
        _themeHost(
          StatefulBuilder(
            builder: (context, setState) {
              rebuild = setState;
              return _panel(
                value: requested,
                onChanged: (value) => setState(() => requested = value),
                onChangeEnd: () => commits++,
                onReset: () => setState(() => requested = 1),
              );
            },
          ),
        ),
      );
      await tester.pump();
      final slider = find.byKey(PlannerAppearancePopover.sliderKey);
      await tester.tapAt(
        tester.getRect(slider).centerRight - const Offset(12, 0),
      );
      await tester.pump();
      expect(requested, 1.25);
      expect(find.text('125%'), findsOneWidget);
      expect(commits, greaterThan(0));

      final previousCommits = commits;
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pump();
      expect(requested, 1.24);
      expect(commits, greaterThan(previousCommits));

      rebuild(() => requested = 1.12);
      await tester.pump();
      await tester.tap(find.byKey(PlannerAppearancePopover.resetKey));
      await tester.pump();
      expect(requested, 1);
      expect(find.text('100%'), findsOneWidget);
      expect(
        tester
            .widget<AppButton>(find.byKey(PlannerAppearancePopover.resetKey))
            .onPressed,
        isNull,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('fit cap is effective value without overwriting requested zoom', (
    tester,
  ) async {
    var previews = 0;
    var resets = 0;
    await tester.pumpWidget(
      _themeHost(
        _panel(
          value: 1.25,
          maximum: 1,
          onChanged: (_) => previews++,
          onReset: () => resets++,
        ),
      ),
    );
    await tester.pump();
    final slider = tester.widget<AppSlider>(
      find.byKey(PlannerAppearancePopover.sliderKey),
    );
    expect(slider.value, 100);
    expect(slider.max, 100);
    expect(slider.onChanged, isNull);
    expect(find.text('100%'), findsOneWidget);
    expect(previews, 0);
    await tester.tap(find.byKey(PlannerAppearancePopover.resetKey));
    expect(resets, 1, reason: 'A capped saved preference can still be reset.');

    await tester.pumpWidget(_themeHost(_panel(value: 1.25, maximum: 1.08)));
    await tester.pump();
    final capped = tester.widget<AppSlider>(
      find.byKey(PlannerAppearancePopover.sliderKey),
    );
    expect(capped.value, 108);
    expect(capped.max, 108);
    expect(capped.divisions, 8);
    expect(find.text('108%'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Escape closes the popup without an extra settings action', (
    tester,
  ) async {
    var closes = 0;
    await tester.pumpWidget(_themeHost(_panel(onClose: () => closes++)));
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(closes, 1);
    expect(find.text('Full appearance settings'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the anchored host owns outside dismissal', (tester) async {
    var closes = 0;
    var activations = 0;
    await tester.pumpWidget(
      _themeHost(
        Row(
          children: [
            SizedBox(
              width: 214,
              child: PlannerAppearancePopover(
                value: 1,
                maximum: 1.25,
                onChanged: (_) {},
                onChangeEnd: () {},
                onReset: () {},
                onClose: () => closes++,
              ),
            ),
            TextButton(
              onPressed: () => activations++,
              child: const Text('Planner control'),
            ),
          ],
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.text('Planner control'));
    expect(closes, 0);
    expect(activations, 1);
    expect(tester.takeException(), isNull);
  });

  for (final theme in [
    SakuraNightGardenSpec.theme,
    IlluminatedLedgerSpec.theme,
    StandardSpec.theme,
  ]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets(
        '${theme.id} popup is content-sized at ${scale * 100}% text',
        (tester) async {
          await tester.pumpWidget(
            _themeHost(_panel(value: 1.15), theme: theme, textScale: scale),
          );
          await tester.pump();
          final bounds = tester.getRect(
            find.byKey(PlannerAppearancePopover.surfaceKey),
          );
          expect(bounds.width, lessThanOrEqualTo(260));
          expect(bounds.height, lessThan(360));
          final backing = tester.widget<DecoratedBox>(
            find.byKey(PlannerAppearancePopover.backingKey),
          );
          expect(
            (backing.decoration as BoxDecoration).color!.a,
            theme.isStandard ? 1 : 0,
            reason: 'Standard must hide Planner text beneath the popup.',
          );
          expect(
            find.byKey(PlannerAppearancePopover.resetKey).hitTestable(),
            findsOneWidget,
          );
          expect(find.text('Full appearance settings'), findsNothing);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
}

Widget _panel({
  double value = 1,
  double maximum = 1.25,
  ValueChanged<double>? onChanged,
  VoidCallback? onChangeEnd,
  VoidCallback? onReset,
  VoidCallback? onClose,
}) => ConstrainedBox(
  constraints: const BoxConstraints.tightFor(
    width: 260,
  ).copyWith(maxHeight: 360),
  child: PlannerAppearancePopover(
    value: value,
    maximum: maximum,
    onChanged: onChanged ?? (_) {},
    onChangeEnd: onChangeEnd ?? () {},
    onReset: onReset ?? () {},
    onClose: onClose ?? () {},
  ),
);

Widget _themeHost(
  Widget child, {
  ThemeSpec theme = SakuraNightGardenSpec.theme,
  double textScale = 1,
}) => MaterialApp(
  theme: theme.materialTheme(),
  home: ThemeSpecScope(
    spec: theme,
    child: MediaQuery(
      data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
      child: AppOverlayCoordinatorHost(
        child: Scaffold(body: Center(child: child)),
      ),
    ),
  ),
);
