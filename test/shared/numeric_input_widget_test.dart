import 'package:bdo_craft_planner_flutter/visual/visual.dart';
import 'package:bdo_number_format/bdo_number_format.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final spec in RetainedThemeRegistry.themes) {
    for (final scale in [1.0, 2.0]) {
      testWidgets(
        'numeric edits preserve values and alignment ${spec.id} $scale',
        (tester) async {
          final amount = TextEditingController();
          final search = TextEditingController();
          addTearDown(amount.dispose);
          addTearDown(search.dispose);
          String? submitted;
          await tester.pumpWidget(
            MaterialApp(
              home: MediaQuery(
                data: MediaQueryData(textScaler: TextScaler.linear(scale)),
                child: ThemeSpecScope(
                  spec: spec,
                  child: Scaffold(
                    body: Center(
                      child: SizedBox(
                        width: 380,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            AppTextField(
                              controller: amount,
                              semanticLabel: 'Amount',
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                    decimal: true,
                                  ),
                              onSubmitted: (text) => submitted = text,
                            ),
                            const SizedBox(height: 12),
                            AppTextField(
                              controller: search,
                              semanticLabel: 'Search',
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
          final fields = find.byType(TextField);
          final before = tester.getRect(fields.first);
          await tester.enterText(fields.first, '10000');
          expect(amount.text, '10.000');
          await tester.enterText(fields.first, '12345,67');
          expect(amount.text, '12.345,67');
          await tester.testTextInput.receiveAction(TextInputAction.done);
          expect(parsePlannerNumber(submitted!), 12345.67);
          await tester.showKeyboard(fields.first);
          amount.selection = const TextSelection.collapsed(offset: 3);
          tester.testTextInput.updateEditingValue(
            const TextEditingValue(
              text: '12.9345,67',
              selection: TextSelection.collapsed(offset: 4),
            ),
          );
          await tester.pump();
          expect(amount.text, '129.345,67');
          expect(amount.selection.baseOffset, 3);
          expect(tester.getRect(fields.first), before);
          await tester.enterText(fields.last, '10000');
          expect(search.text, '10000');
          final second = tester.getRect(fields.last);
          expect(second.left, before.left);
          expect(second.width, before.width);
          expect(second.top - before.bottom, 12);
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox());
        },
      );
    }
  }
}
