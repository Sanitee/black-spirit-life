import 'package:bdo_number_format/bdo_number_format.dart';
import 'package:bdo_number_input/bdo_number_input.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

TextEditingValue edit(String text, [int? caret]) => TextEditingValue(
  text: text,
  selection: TextSelection.collapsed(offset: caret ?? text.length),
);
void main() {
  const formatter = GroupedNumberInputFormatter();
  for (final (raw, expected) in [
    ('10000', '10.000'),
    ('123456789012345', '123.456.789.012.345'),
    ('10000,50', '10.000,50'),
    ('10000.50', '10.000,50'),
    ('1.234,5678', '1.234,5678'),
    ('1,234.56', '1.234,56'),
    ('1,234,567', '1.234.567'),
    ('2,500', '2,500'),
    ('-123456,25', '-123.456,25'),
    ('+10000', '+10.000'),
    ('00001000', '1.000'),
    (',5', '0,5'),
    ('0.125', '0,125'),
  ]) {
    test('paste $raw preserves the numeric value', () {
      final result = formatter.formatEditUpdate(
        TextEditingValue.empty,
        edit(raw),
      );
      expect(result.text, expected);
      expect(parsePlannerNumber(result.text), parsePlannerNumber(raw));
      expect(result.selection.extentOffset, result.text.length);
    });
  }
  test('successive typing and middle insertion keep the caret', () {
    var value = TextEditingValue.empty;
    for (final digit in '1234567'.split('')) {
      value = formatter.formatEditUpdate(value, edit('${value.text}$digit'));
    }
    expect(value.text, '1.234.567');
    expect(value.selection.extentOffset, 9);
    value = formatter.formatEditUpdate(edit('1.234', 3), edit('1.2934', 4));
    expect(value.text, '12.934');
    expect(value.selection.extentOffset, 4);
  });
  test('backspace and delete cross an inserted grouping dot', () {
    final back = formatter.formatEditUpdate(edit('1.234', 2), edit('1234', 1));
    expect(back.text, '234');
    expect(back.selection.extentOffset, 0);
    final forward = formatter.formatEditUpdate(
      edit('1.234', 1),
      edit('1234', 1),
    );
    expect(forward.text, '134');
    expect(forward.selection.extentOffset, 1);
  });
  test('decimal point after a grouped integer becomes the decimal comma', () {
    final value = formatter.formatEditUpdate(edit('1.234'), edit('1.234.'));
    expect(value.text, '1.234,');
    expect(value.selection.extentOffset, 6);
    final next = formatter.formatEditUpdate(value, edit('1.234,5'));
    expect(parsePlannerNumber(next.text), 1234.5);
  });
  test('selection direction survives added groups', () {
    final result = formatter.formatEditUpdate(
      TextEditingValue.empty,
      const TextEditingValue(
        text: '1234567',
        selection: TextSelection(
          baseOffset: 7,
          extentOffset: 1,
          isDirectional: true,
        ),
      ),
    );
    expect(result.selection.baseOffset, 9);
    expect(result.selection.extentOffset, 1);
    expect(result.selection.isDirectional, isTrue);
  });
  test(
    'composition and invalid paste are never converted to a different value',
    () {
      const composing = TextEditingValue(
        text: '10000',
        selection: TextSelection.collapsed(offset: 5),
        composing: TextRange(start: 0, end: 5),
      );
      expect(formatter.formatEditUpdate(edit('1'), composing), composing);
      for (final raw in ['abc1000', '1.2.3', '1,,2', '2e3', '-', '+']) {
        final value = edit(raw);
        expect(formatter.formatEditUpdate(edit('1.000'), value), value);
      }
    },
  );
}
