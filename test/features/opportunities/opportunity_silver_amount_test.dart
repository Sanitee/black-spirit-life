import 'package:bdo_craft_planner_flutter/features/opportunities/opportunity_silver_amount.dart';
import 'package:bdo_craft_planner_flutter/features/shared/shared_silver_amount.dart';
import 'package:bdo_craft_planner_flutter/features/shared/silver_amount_content.dart';
import 'package:bdo_craft_planner_flutter/visual/visual.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final theme in RetainedThemeRegistry.themes) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('silver icon alignment and exact values ${theme.id} $scale', (
        tester,
      ) async {

        await tester.pumpWidget(
          MaterialApp(
            theme: theme.materialTheme(),
            home: ThemeSpecScope(
              spec: theme,
              child: Scaffold(
                body: MediaQuery(
                  data: MediaQueryData(textScaler: TextScaler.linear(scale)),
                  child: Center(
                    child: SizedBox(
                      width: 340,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          OpportunitySilverAmount(
                            value: -40148062.5,
                            style: const TextStyle(fontSize: 18),
                            showIcon: true,
                            estimated: true,
                            unicodeMinus: true,
                            silverSuffix: true,
                            textKey: const ValueKey('icon-amount'),
                          ),
                          const SharedSilverAmount(
                            value: 1200,
                            style: TextStyle(fontSize: 18),
                            textKey: ValueKey('existing-shared'),
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
        expect(find.text('≈ −40,1m'), findsOneWidget);
        expect(find.textContaining(' silver'), findsNothing);
        expect(find.byType(SilverAmountContent), findsNWidgets(2));
        expect(find.byType(Image), findsNWidgets(2));
        final amount = find.byKey(const ValueKey('icon-amount'));
        final firstIcon = find.byType(Image).first;
        expect(
          tester.getRect(amount).left - tester.getRect(firstIcon).right,
          closeTo(5, .01),
        );
        expect(
          tester.getRect(amount).center.dy,
          closeTo(tester.getRect(firstIcon).center.dy, .01),
        );
        final semantics = find.byWidgetPredicate(
          (w) =>
              w is Semantics && w.properties.value == '≈ −40.148.062,5 silver',
        );
        expect(semantics, findsOneWidget);
        await tester.tap(amount);
        await tester.pump();
        expect(find.text('≈ −40.148.062,5'), findsOneWidget);
        await tester.tap(amount);
        await tester.pump();
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pump();
        expect(find.text('≈ −40.148.062,5'), findsOneWidget);
        expect(find.byType(Tooltip), findsNothing);
        expect(tester.takeException(), isNull);
      });
    }
  }
  for (final value in <double?>[
    null,
    double.nan,
    double.infinity,
    0,
    2400.49,
    -2400.49,
  ]) {
    testWidgets(
      'silver icon preserves unknown, zero and signed whole amounts $value',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: OpportunitySilverAmount(
                value: value,
                style: const TextStyle(fontSize: 18),
                showIcon: true,
                wholeSilver: true,
                initiallyExpanded: true,
                showPlus: true,
                unicodeMinus: true,
              ),
            ),
          ),
        );
        final expected = value == null || !value.isFinite
            ? '—'
            : value == 0
            ? '0'
            : value > 0
            ? '+2.400'
            : '−2.400';
        expect(find.text(expected), findsOneWidget);
        expect(find.byType(Image), findsOneWidget);
        if (value == null || !value.isFinite) {
          expect(find.byType(InkWell), findsNothing);
          expect(
            find.byWidgetPredicate(
              (w) =>
                  w is Semantics &&
                  w.properties.label == 'Silver amount unavailable',
            ),
            findsOneWidget,
          );
        }
        expect(tester.takeException(), isNull);
      },
    );
  }

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
  test('compact silver rounds and carries to the next unit', () {
    for (final (amount, expected) in <(num, String)>[
      (40148062.5, '40,1m'),
      (40999999, '41m'),
      (999999, '1m'),
      (999949, '999,9k'),
      (999950, '1m'),
      (1000000, '1m'),
      (1000000000, '1b'),
      (1999, '2k'),
      (999.99, '1k'),
      (1100000000, '1,1b'),
      (1100000000000, '1,1t'),
      (-8118, '-8,1k'),
      (-0.01, '0'),
      (0, '0'),
      (-40148062.5, '-40,1m'),
    ]) {
      expect(formatCompactOpportunitySilver(amount), expected);
    }
    expect(formatCompactOpportunitySilver(double.nan), '—');
    expect(formatCompactOpportunitySilver(double.infinity), '—');
  });

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
