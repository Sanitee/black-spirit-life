import 'package:bdo_craft_planner_flutter/features/inventory/inventory.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const formatter = InventoryAmountInputFormatter();

  TextEditingValue edit(String oldText, String newText, {int? caret}) =>
      formatter.formatEditUpdate(
        TextEditingValue(
          text: oldText,
          selection: TextSelection.collapsed(offset: oldText.length),
        ),
        TextEditingValue(
          text: newText,
          selection: TextSelection.collapsed(offset: caret ?? newText.length),
        ),
      );

  test('groups whole inventory amounts as they are typed', () {
    expect(edit('', '1').text, '1');
    expect(edit('1', '10').text, '10');
    expect(edit('10', '100').text, '100');
    expect(edit('100', '1000').text, '1.000');
    expect(edit('1.000', '10000').text, '10.000');
    expect(edit('10.000', '100000').text, '100.000');
    expect(edit('100.000', '1000000').text, '1.000.000');
  });

  test('keeps a German decimal comma and a stable end caret', () {
    final value = edit('1.234', '1234,5');
    expect(value.text, '1.234,5');
    expect(value.selection, const TextSelection.collapsed(offset: 7));
  });

  test('groups pasted values and rejects more than twelve whole digits', () {
    expect(edit('', '99999999').text, '99.999.999');
    expect(edit('1', '1234567890123').text, '1');
    expect(edit('10.000', '-5').text, '-5');
  });
}
