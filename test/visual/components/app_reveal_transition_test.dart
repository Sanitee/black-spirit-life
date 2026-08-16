import 'package:bdo_craft_planner_flutter/visual/visual.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('reveals and dismisses a retained inline child', (tester) async {
    final visible = ValueNotifier<bool>(false);
    addTearDown(visible.dispose);

    await tester.pumpWidget(_host(visible: visible));
    expect(find.text('Ingredient details'), findsNothing);
    final stationaryRect = tester.getRect(find.text('Stationary control'));

    visible.value = true;
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 40));

    final reveal = find.byKey(const ValueKey<String>('test-reveal'));
    final fade = tester.widget<FadeTransition>(
      find.descendant(of: reveal, matching: find.byType(FadeTransition)),
    );
    final size = tester.widget<SizeTransition>(
      find.descendant(of: reveal, matching: find.byType(SizeTransition)),
    );
    expect(fade.opacity.value, inExclusiveRange(0, 1));
    expect(size.sizeFactor.value, inExclusiveRange(0, 1));
    expect(find.text('Ingredient details'), findsOneWidget);
    expect(tester.getRect(find.text('Stationary control')), stationaryRect);

    await tester.pumpAndSettle();
    expect(fade.opacity.value, 1);

    visible.value = false;
    await tester.pump();
    expect(find.text('Ingredient details'), findsOneWidget);
    expect(
      tester
          .widget<IgnorePointer>(
            find
                .descendant(of: reveal, matching: find.byType(IgnorePointer))
                .first,
          )
          .ignoring,
      isTrue,
    );
    expect(tester.getRect(find.text('Stationary control')), stationaryRect);

    await tester.pumpAndSettle();
    expect(find.text('Ingredient details'), findsNothing);
  });

  testWidgets('reduced motion applies visibility immediately', (tester) async {
    final visible = ValueNotifier<bool>(false);
    addTearDown(visible.dispose);

    await tester.pumpWidget(_host(visible: visible, reduceMotion: true));
    visible.value = true;
    await tester.pump();

    final reveal = find.byKey(const ValueKey<String>('test-reveal'));
    expect(find.text('Ingredient details'), findsOneWidget);
    expect(
      find.descendant(of: reveal, matching: find.byType(FadeTransition)),
      findsNothing,
    );
    expect(
      find.descendant(of: reveal, matching: find.byType(SizeTransition)),
      findsNothing,
    );

    visible.value = false;
    await tester.pump();
    expect(find.text('Ingredient details'), findsNothing);
  });
}

Widget _host({
  required ValueNotifier<bool> visible,
  bool reduceMotion = false,
}) => MaterialApp(
  theme: StandardSpec.theme.materialTheme(),
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(context).copyWith(disableAnimations: reduceMotion),
    child: child!,
  ),
  home: ThemeSpecScope(
    spec: StandardSpec.theme,
    child: Scaffold(
      body: ValueListenableBuilder<bool>(
        valueListenable: visible,
        builder: (context, isVisible, child) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            const Text('Stationary control'),
            AppRevealTransition(
              key: const ValueKey<String>('test-reveal'),
              visible: isVisible,
              expandVertically: true,
              child: isVisible ? const Text('Ingredient details') : null,
            ),
          ],
        ),
      ),
    ),
  ),
);
