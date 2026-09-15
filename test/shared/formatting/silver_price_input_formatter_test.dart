import 'package:bdo_craft_planner_flutter/domain/opportunities/opportunity_calculator.dart';
import 'package:bdo_craft_planner_flutter/shared/formatting/silver_price_input_formatter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _formatter = SilverPriceInputFormatter();

TextEditingValue _value(String text, {int? caret, int? base, int? extent}) =>
    TextEditingValue(
      text: text,
      selection: base != null
          ? TextSelection(baseOffset: base, extentOffset: extent!)
          : TextSelection.collapsed(offset: caret ?? text.length),
    );

TextEditingValue _paste(String text) =>
    _formatter.formatEditUpdate(_value(''), _value(text));

void main() {
  group('whole-silver parsing and formatting', () {
    for (final entry in <String, int>{
      '1': 1,
      '1234': 1234,
      '0001234': 1234,
      '1.234': 1234,
      '123.456.789': 123456789,
      '1 234 567': 1234567,
      '1\u00a0234\u00a0567': 1234567,
      '1\u202f234\u202f567': 1234567,
      '  1.234  ': 1234,
      '999999999999999': maxSilverPrice,
      '999.999.999.999.999': maxSilverPrice,
    }.entries) {
      test('accepts ${entry.key}', () {
        expect(parseSilverPrice(entry.key), entry.value);
        expect(_paste(entry.key).text, formatSilverPrice(entry.value));
      });
    }
    for (final text in [
      '',
      ' ',
      '0',
      '000',
      '-1',
      '+1',
      '−1',
      '1,5',
      '1.5',
      '12.34',
      '1.234,00',
      '1,234',
      '1,234,567',
      '0.123',
      '01.234',
      '1.000.00',
      '.123',
      '123.',
      '1..234',
      '1 23',
      '1  234',
      '1.234 567',
      '1\n234',
      '1\t234',
      '10 silver',
      'silver 10',
      '1e3',
      'NaN',
      'Infinity',
      '１２３',
      '١٢٣',
      '1000000000000000',
      '999.999.999.999.999.999',
    ]) {
      test(
        'does not parse invalid positive price ${text.replaceAll('\n', r'\n')}',
        () {
          expect(parseSilverPrice(text), isNull);
        },
      );
    }
    test(
      'zero is editable, blank stays blank and out-of-range format fails',
      () {
        expect(_paste('').text, '');
        expect(_paste('000').text, '0');
        expect(formatSilverPrice(0), '0');
        expect(formatSilverPrice(1000), '1.000');
        expect(maxSilverPrice.toDouble().toInt(), maxSilverPrice);
        expect(maxSilverPrice, OpportunityCalculator.maxCustomSalePrice);
        expect(() => formatSilverPrice(-1), throwsRangeError);
        expect(() => formatSilverPrice(maxSilverPrice + 1), throwsRangeError);
      },
    );
  });

  test('incremental digits regroup automatically and keep the end caret', () {
    var value = _value('');
    for (final digit in '123456789012345'.split('')) {
      value = _formatter.formatEditUpdate(value, _value('${value.text}$digit'));
      expect(value.selection.extentOffset, value.text.length);
      expect(
        value.text,
        formatSilverPrice(int.parse(value.text.replaceAll('.', ''))),
      );
    }
    expect(value.text, '123.456.789.012.345');
    expect(_formatter.formatEditUpdate(value, _value('${value.text}6')), value);
  });

  test('invalid paste never silently extracts a different positive price', () {
    final old = _value('12.345', base: 0, extent: 6);
    for (final raw in [
      '-1',
      '1,5',
      '1.5',
      '12.34',
      '30 silver',
      '1  000',
      '1000000000000000',
    ]) {
      expect(_formatter.formatEditUpdate(old, _value(raw)), old, reason: raw);
    }
  });

  test('middle insertion can temporarily disturb existing grouping', () {
    final next = _formatter.formatEditUpdate(
      _value('1.234', caret: 2),
      _value('1.9234', caret: 3),
    );
    expect(next.text, '19.234');
    expect(next.selection, const TextSelection.collapsed(offset: 2));
    final next2 = _formatter.formatEditUpdate(
      _value('12.345', caret: 4),
      _value('12.3945', caret: 5),
    );
    expect(next2.text, '123.945');
    expect(next2.selection.extentOffset, 5);
  });

  test('selection endpoints, direction and affinity survive regrouping', () {
    const raw = TextEditingValue(
      text: '1234567',
      selection: TextSelection(
        baseOffset: 6,
        extentOffset: 1,
        affinity: TextAffinity.upstream,
        isDirectional: true,
      ),
    );
    final result = _formatter.formatEditUpdate(_value(''), raw);
    expect(result.text, '1.234.567');
    expect(
      result.selection,
      const TextSelection(
        baseOffset: 8,
        extentOffset: 1,
        affinity: TextAffinity.upstream,
        isDirectional: true,
      ),
    );
    final moved = _value('1.234', base: 2, extent: 5);
    expect(_formatter.formatEditUpdate(_value('1.234'), moved), moved);
  });

  test('range replacement and deletion preserve the intended digits', () {
    final replaced = _formatter.formatEditUpdate(
      _value('1.234.567', base: 2, extent: 6),
      _value('1.9567', caret: 3),
    );
    expect(replaced.text, '19.567');
    expect(replaced.selection.extentOffset, 2);
    final deleted = _formatter.formatEditUpdate(
      _value('1.234.567', base: 2, extent: 6),
      _value('1.567', caret: 2),
    );
    expect(deleted.text, '1.567');
    expect(deleted.selection.extentOffset, 2);
    final all = _formatter.formatEditUpdate(
      _value('1.234', base: 5, extent: 0),
      _value(''),
    );
    expect(all, _value(''));
  });

  test('backspace across a separator deletes the digit to its left', () {
    final result = _formatter.formatEditUpdate(
      _value('1.234', caret: 2),
      _value('1234', caret: 1),
    );
    expect(result, _value('234', caret: 0));
    final result2 = _formatter.formatEditUpdate(
      _value('12.345', caret: 3),
      _value('12345', caret: 2),
    );
    expect(result2, _value('1.345', caret: 1));
  });

  test('delete across a separator deletes the digit to its right', () {
    final result = _formatter.formatEditUpdate(
      _value('1.234', caret: 1),
      _value('1234', caret: 1),
    );
    expect(result, _value('134', caret: 1));
    final result2 = _formatter.formatEditUpdate(
      _value('12.345', caret: 2),
      _value('12345', caret: 2),
    );
    expect(result2, _value('1.245', caret: 3));
  });

  test('deleting a selected separator does not delete an unselected digit', () {
    final result = _formatter.formatEditUpdate(
      _value('1.234', base: 1, extent: 2),
      _value('1234', caret: 1),
    );
    expect(result, _value('1.234', caret: 1));
  });

  test(
    'all middle digit insertions and single-key deletions remain usable',
    () {
      for (final amount in [1234, 12345, 1234567, 1000000]) {
        final text = formatSilverPrice(amount);
        for (var caret = 0; caret <= text.length; caret++) {
          final inserted =
              '${text.substring(0, caret)}9${text.substring(caret)}';
          final result = _formatter.formatEditUpdate(
            _value(text, caret: caret),
            _value(inserted, caret: caret + 1),
          );
          expect(
            result.text,
            formatSilverPrice(int.parse(inserted.replaceAll('.', ''))),
            reason: 'insert $text at $caret',
          );
          expect(
            result.selection.extentOffset,
            inInclusiveRange(0, result.text.length),
          );
          if (caret > 0) {
            final start = text[caret - 1] == '.' ? caret - 2 : caret - 1;
            final expected = text
                .replaceRange(start, caret, '')
                .replaceAll('.', '');
            final backspace = _formatter.formatEditUpdate(
              _value(text, caret: caret),
              _value(text.replaceRange(caret - 1, caret, ''), caret: caret - 1),
            );
            expect(
              backspace.text,
              expected.isEmpty ? '' : formatSilverPrice(int.parse(expected)),
              reason: 'backspace $text at $caret',
            );
          }
          if (caret < text.length) {
            final end = text[caret] == '.' ? caret + 2 : caret + 1;
            final expected = text
                .replaceRange(caret, end, '')
                .replaceAll('.', '');
            final deleted = _formatter.formatEditUpdate(
              _value(text, caret: caret),
              _value(text.replaceRange(caret, caret + 1, ''), caret: caret),
            );
            expect(
              deleted.text,
              expected.isEmpty ? '' : formatSilverPrice(int.parse(expected)),
              reason: 'delete $text at $caret',
            );
          }
        }
      }
    },
  );

  test('leading zeros and invalid selections do not jump beyond the text', () {
    final result = _formatter.formatEditUpdate(
      _value(''),
      _value('0001234', base: 3, extent: 7),
    );
    expect(result.text, '1.234');
    expect(
      result.selection,
      const TextSelection(baseOffset: 0, extentOffset: 5),
    );
    final noSelection = _formatter.formatEditUpdate(
      TextEditingValue.empty,
      const TextEditingValue(text: '1234'),
    );
    expect(noSelection.text, '1.234');
    expect(noSelection.selection, const TextSelection.collapsed(offset: -1));
  });

  test('IME text is untouched while composing and grouped only on commit', () {
    const composing = TextEditingValue(
      text: '1234',
      selection: TextSelection.collapsed(offset: 4),
      composing: TextRange(start: 0, end: 4),
    );
    expect(_formatter.formatEditUpdate(_value(''), composing), composing);
    final committed = _formatter.formatEditUpdate(
      composing,
      composing.copyWith(composing: TextRange.empty),
    );
    expect(committed, _value('1.234'));
    const invalid = TextEditingValue(
      text: '-1',
      selection: TextSelection.collapsed(offset: 2),
      composing: TextRange(start: 0, end: 2),
    );
    final rejectedMeaning = _formatter.formatEditUpdate(
      invalid,
      invalid.copyWith(composing: TextRange.empty),
    );
    expect(rejectedMeaning.text, '-1');
    expect(rejectedMeaning.composing, TextRange.empty);
    expect(parseSilverPrice(rejectedMeaning.text), isNull);
  });

  testWidgets(
    'TextField paste groups and caret movement retains grouped selection',
    (tester) async {
      final controller = TextEditingController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TextField(
              controller: controller,
              inputFormatters: const [_formatter],
            ),
          ),
        ),
      );
      await tester.enterText(find.byType(TextField), '1234567');
      expect(controller.text, '1.234.567');
      expect(controller.selection.extentOffset, 9);
      controller.selection = const TextSelection(
        baseOffset: 2,
        extentOffset: 6,
      );
      await tester.pump();
      expect(
        controller.selection,
        const TextSelection(baseOffset: 2, extentOffset: 6),
      );
      tester.testTextInput.updateEditingValue(_value('1.9567', caret: 3));
      await tester.pump();
      expect(controller.text, '19.567');
      expect(controller.selection.extentOffset, 2);
      tester.testTextInput.updateEditingValue(_value('-1'));
      await tester.pump();
      expect(controller.text, '19.567');
    },
  );
}
