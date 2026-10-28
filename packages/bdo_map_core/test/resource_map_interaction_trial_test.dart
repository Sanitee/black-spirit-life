import 'package:bdo_map_core/src/widgets/resource_map_atlas_shell.dart';
import 'package:bdo_map_core/src/widgets/resource_map_chrome_theme.dart';
import 'package:bdo_map_core/src/widgets/resource_map_pill.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _app(Widget child, {bool reduced = false}) => MaterialApp(
  home: MediaQuery(
    data: MediaQueryData(disableAnimations: reduced),
    child: ResourceMapChromeTheme(
      data: ResourceMapChromeThemeData.glassDock.withUiOpacity(.6),
      child: Scaffold(body: Center(child: child)),
    ),
  ),
);

void main() {
  for (final reduced in [false, true]) {
    testWidgets(
      'search finish preserves editor identity and focus ($reduced)',
      (tester) async {
        final controller = TextEditingController();
        final focus = FocusNode();
        addTearDown(controller.dispose);
        addTearDown(focus.dispose);
        await tester.pumpWidget(
          _app(
            SizedBox(
              width: 290,
              child: ResourceMapAtlasSearch(
                controller: controller,
                focusNode: focus,
                hintText: 'Search the map',
                onChanged: (_) {},
                onSubmitted: (_) {},
                onTap: () {},
                onClear: controller.clear,
              ),
            ),
            reduced: reduced,
          ),
        );
        final editor = tester.element(find.byType(TextField));
        final bounds = tester.getRect(find.byType(ResourceMapAtlasSearch));
        await tester.enterText(find.byType(TextField), 'Acacia');
        await tester.pumpAndSettle();
        expect(tester.element(find.byType(TextField)), same(editor));
        expect(FocusManager.instance.primaryFocus, same(focus));
        expect(controller.text, 'Acacia');
        expect(tester.getRect(find.byType(ResourceMapAtlasSearch)), bounds);
        final finish = tester.widget<TweenAnimationBuilder<double>>(
          find.byKey(const ValueKey('resource-map-search-focus-finish')),
        );
        expect(finish.tween.end, 1);
        expect(
          finish.duration,
          reduced ? Duration.zero : ResourceMapAtlasMotion.quick,
        );
        focus.unfocus();
        await tester.pumpAndSettle();
        expect(tester.binding.hasScheduledFrame, isFalse);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('pill press is paint-only, cancellable and disabled-aware', (
    tester,
  ) async {
    var taps = 0;
    Future<void> open({bool enabled = true}) => tester.pumpWidget(
      _app(
        ResourceMapPill(
          child: InkWell(
            onTap: enabled ? () => taps++ : null,
            child: const SizedBox(
              width: 150,
              height: 50,
              child: Text('Workers'),
            ),
          ),
        ),
      ),
    );
    BoxDecoration finish() =>
        tester
                .widget<AnimatedContainer>(find.byType(AnimatedContainer))
                .decoration!
            as BoxDecoration;
    await open();
    await tester.pumpAndSettle();
    final bounds = tester.getRect(find.byType(ResourceMapPill));
    final normal = finish();
    final pointer = await tester.startGesture(bounds.center);
    await tester.pumpAndSettle();
    expect(finish().gradient, isNot(normal.gradient));
    expect(tester.getRect(find.byType(ResourceMapPill)), bounds);
    await pointer.cancel();
    await tester.pumpAndSettle();
    expect(finish().gradient, normal.gradient);
    expect(taps, 0);
    await tester.tap(find.text('Workers'));
    await tester.pumpAndSettle();
    expect(taps, 1);
    await open(enabled: false);
    await tester.pumpAndSettle();
    final disabled = finish();
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(bounds.center);
    await mouse.down(bounds.center);
    await tester.pumpAndSettle();
    expect(finish(), disabled);
    await mouse.up();
    await tester.pumpAndSettle();
    expect(taps, 1);
    expect(tester.binding.hasScheduledFrame, isFalse);
  });

  testWidgets('task utilities retain keyboard activation and settle', (
    tester,
  ) async {
    var back = 0;
    await tester.pumpWidget(
      _app(
        SizedBox(
          width: 340,
          height: 200,
          child: ResourceMapJourneySurface(
            title: 'Workers',
            onBack: () => back++,
            child: const Text('Current task'),
          ),
        ),
      ),
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(back, 1);
    expect(tester.binding.hasScheduledFrame, isFalse);
    expect(find.byType(BackdropFilter), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
