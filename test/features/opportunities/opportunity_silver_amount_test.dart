import 'package:bdo_craft_planner_flutter/features/opportunities/opportunity_silver_amount.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'per-item whole silver has no approximation and retains click toggle',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: OpportunitySilverAmount(
              value: -2400.49,
              style: TextStyle(),
              initiallyExpanded: true,
              wholeSilver: true,
              unicodeMinus: true,
              showPlus: true,
            ),
          ),
        ),
      );
      expect(find.text('−2.400'), findsOneWidget);
      expect(find.textContaining('≈'), findsNothing);
      await tester.tap(find.byType(OpportunitySilverAmount));
      await tester.pump();
      expect(find.text('−2,4k'), findsOneWidget);
      await tester.tap(find.byType(OpportunitySilverAmount));
      await tester.pump();
      expect(find.text('−2.400'), findsOneWidget);
    },
  );
  test(
    'compact silver truncates rather than rounding into the next amount',
    () {
      for (final (amount, expected) in <(num, String)>[
        (40148062.5, '40,1m'),
        (40999999, '40,9m'),
        (999999, '999,9k'),
        (1000000, '1m'),
        (1000000000, '1b'),
        (1999, '1,9k'),
        (999.99, '999,9'),
        (0, '0'),
        (-40148062.5, '-40,1m'),
      ]) {
        expect(formatCompactOpportunitySilver(amount), expected);
      }
      expect(formatCompactOpportunitySilver(double.nan), '—');
    },
  );

  for (final scale in [1.0, 2.0]) {
    testWidgets(
      'silver toggles full and compact by click and keyboard $scale',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: MediaQuery(
                data: MediaQueryData(textScaler: TextScaler.linear(scale)),
                child: Center(
                  child: SizedBox(
                    width: 150,
                    child: OpportunitySilverAmount(
                      value: 40148062.5,
                      style: const TextStyle(fontSize: 18),
                      showPlus: true,
                      estimated: true,
                      silverSuffix: true,
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        expect(find.text('≈ +40,1m silver'), findsOneWidget);
        final amount = find.byType(OpportunitySilverAmount);
        final semantics = find.descendant(
          of: amount,
          matching: find.byWidgetPredicate(
            (w) => w is Semantics && w.properties.label == 'Show full amount',
          ),
        );
        expect(semantics, findsOneWidget);
        expect(
          tester.widget<Semantics>(semantics).properties.value,
          '≈ +40.148.062,5 silver',
        );
        final before = tester.getSize(amount);
        final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
        await mouse.addPointer(location: const Offset(1, 1));
        await mouse.moveTo(tester.getCenter(amount));
        await tester.pump(const Duration(milliseconds: 800));
        await tester.pump(const Duration(milliseconds: 250));
        expect(find.byType(Tooltip), findsNothing);
        expect(find.text('≈ +40.148.062,5 silver'), findsNothing);
        expect(tester.getSize(amount), before);
        await mouse.removePointer();
        await tester.tap(find.byType(OpportunitySilverAmount));
        await tester.pump();
        expect(find.text('≈ +40.148.062,5 silver'), findsOneWidget);
        await tester.tap(find.byType(OpportunitySilverAmount));
        await tester.pump();
        expect(find.text('≈ +40,1m silver'), findsOneWidget);
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pump();
        expect(find.text('≈ +40.148.062,5 silver'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
