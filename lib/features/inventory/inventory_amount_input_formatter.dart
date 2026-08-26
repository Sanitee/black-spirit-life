import 'package:flutter/services.dart';

/// Keeps Inventory amounts readable while they are being typed.
///
/// Inventory uses German-style grouping (`1.000`) and accepts a comma when a
/// fractional amount is needed. Dots typed or pasted into the field are
/// treated as grouping separators.
final class InventoryAmountInputFormatter extends TextInputFormatter {
  const InventoryAmountInputFormatter();

  static const int _maximumIntegerDigits = 12;
  static const int _maximumFractionDigits = 4;

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    if (newValue.composing.isValid && !newValue.composing.isCollapsed) {
      return newValue;
    }
    final raw = newValue.text;
    if (raw.isEmpty) return newValue;
    // Keep an explicitly negative edit visible so the field's normal
    // validation can explain why it is not accepted.
    if (raw.startsWith('-')) return newValue;

    final comma = raw.indexOf(',');
    final hasComma = comma >= 0;
    final integerSource = hasComma ? raw.substring(0, comma) : raw;
    final fractionSource = hasComma ? raw.substring(comma + 1) : '';
    var integerDigits = integerSource.replaceAll(RegExp(r'[^0-9]'), '');
    var fractionDigits = fractionSource.replaceAll(RegExp(r'[^0-9]'), '');

    if (integerDigits.length > _maximumIntegerDigits) return oldValue;
    if (fractionDigits.length > _maximumFractionDigits) {
      fractionDigits = fractionDigits.substring(0, _maximumFractionDigits);
    }
    if (integerDigits.isEmpty) {
      if (!hasComma) {
        return const TextEditingValue(
          selection: TextSelection.collapsed(offset: 0),
        );
      }
      integerDigits = '0';
    }
    integerDigits = integerDigits.replaceFirst(RegExp(r'^0+(?=\d)'), '');

    final grouped = _group(integerDigits);
    final formatted = hasComma ? '$grouped,$fractionDigits' : grouped;
    final caret = _caretOffset(
      raw: raw,
      rawOffset: newValue.selection.extentOffset,
      groupedInteger: grouped,
      formattedLength: formatted.length,
    );
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: caret),
    );
  }

  static String _group(String digits) {
    final buffer = StringBuffer();
    for (var index = 0; index < digits.length; index += 1) {
      if (index > 0 && (digits.length - index) % 3 == 0) buffer.write('.');
      buffer.write(digits[index]);
    }
    return buffer.toString();
  }

  static int _caretOffset({
    required String raw,
    required int rawOffset,
    required String groupedInteger,
    required int formattedLength,
  }) {
    final safeOffset = rawOffset.clamp(0, raw.length).toInt();
    final comma = raw.indexOf(',');
    if (comma >= 0 && safeOffset > comma) {
      final fractionBeforeCaret = raw
          .substring(comma + 1, safeOffset)
          .replaceAll(RegExp(r'[^0-9]'), '')
          .length
          .clamp(0, _maximumFractionDigits)
          .toInt();
      return (groupedInteger.length + 1 + fractionBeforeCaret)
          .clamp(0, formattedLength)
          .toInt();
    }

    final digitsBeforeCaret = raw
        .substring(0, safeOffset)
        .replaceAll(RegExp(r'[^0-9]'), '')
        .length;
    if (digitsBeforeCaret == 0) return 0;
    var seen = 0;
    for (var index = 0; index < groupedInteger.length; index += 1) {
      final code = groupedInteger.codeUnitAt(index);
      if (code >= 48 && code <= 57) seen += 1;
      if (seen == digitsBeforeCaret) return index + 1;
    }
    return groupedInteger.length;
  }
}
