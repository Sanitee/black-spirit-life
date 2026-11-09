import 'package:flutter/services.dart';

/// Keep existing validation filters before the shared display formatter.
List<TextInputFormatter>? groupedNumberFormatters(
  List<TextInputFormatter>? existing, {
  bool enabled = true,
}) => !enabled
    ? existing
    : [
        ...?existing,
        if (!(existing?.any((f) => f is GroupedNumberInputFormatter) ?? false))
          const GroupedNumberInputFormatter(),
      ];

/// Dotted groups while typing, with comma decimals and stable selections.
/// Field validators keep ownership of bounds and whether fractions are allowed.
/// Invalid text is left intact: pasting text must never extract a different value.
final class GroupedNumberInputFormatter extends TextInputFormatter {
  const GroupedNumberInputFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    if (newValue.composing.isValid && !newValue.composing.isCollapsed) {
      return newValue;
    }
    if (newValue.text.isEmpty) return newValue;
    final deletion = _deleteSeparator(oldValue, newValue);
    final value = deletion ?? newValue;
    final text = value.text;
    if (!RegExp(r'^[+\-]?[0-9.,\s]*$').hasMatch(text)) return value;
    if (text == '-' || text == '+') return value;
    final local = deletion != null || _localDigitEdit(oldValue, newValue);
    final comma = text.lastIndexOf(',');
    final dot = text.lastIndexOf('.');
    int decimal = -1;
    if (local) {
      decimal = comma;
    } else if (comma >= 0 && dot >= 0) {
      decimal = comma > dot ? comma : dot;
    } else if (comma >= 0) {
      if (text.indexOf(',') == comma || !_grouped(text, ',')) decimal = comma;
    } else if (dot >= 0 && !_grouped(text, '.')) {
      decimal = dot;
    }
    final sign = text.startsWith('-') || text.startsWith('+') ? text[0] : '';
    final start = sign.length;
    if (decimal >= 0 && decimal < start) return value;
    final integerSource = text.substring(
      start,
      decimal < 0 ? text.length : decimal,
    );
    final fraction = decimal < 0 ? '' : text.substring(decimal + 1);
    if (!RegExp(r'^[0-9]*$').hasMatch(fraction)) return value;
    // Multiple decimal separators are not repaired into a valid number.
    if (decimal >= 0 &&
        integerSource.contains(text[decimal]) &&
        !(text[decimal] == '.' && _grouped(integerSource, '.'))) {
      return value;
    }
    if (!local && decimal >= 0) {
      final other = text[decimal] == ',' ? '.' : ',';
      if (integerSource.contains(other) && !_grouped(integerSource, other)) {
        return value;
      }
    }
    final digits = integerSource.replaceAll(RegExp(r'[.,\s]'), '');
    if (digits.isEmpty && decimal < 0) return value;
    final significant = digits.isEmpty
        ? '0'
        : digits.replaceFirst(RegExp(r'^0+(?=\d)'), '');
    final removedZeros = digits.length - significant.length;
    final integer = _group(significant);
    final formatted = '$sign$integer${decimal < 0 ? '' : ',$fraction'}';
    if (formatted == text) return value;

    int offset(int rawOffset) {
      if (rawOffset < 0) return rawOffset;
      final safe = rawOffset.clamp(0, text.length);
      if (safe <= start) return safe;
      if (decimal >= 0 && safe > decimal) {
        return (sign.length + integer.length + 1 + safe - decimal - 1).clamp(
          0,
          formatted.length,
        );
      }
      final count = text.substring(start, safe).codeUnits.where(_digit).length;
      final wanted = (count - removedZeros).clamp(0, significant.length);
      if (wanted == 0) return sign.length;
      var seen = 0;
      for (var i = 0; i < integer.length; i++) {
        if (_digit(integer.codeUnitAt(i))) seen++;
        if (seen == wanted) {
          final afterGroup =
              safe > 0 && text[safe - 1] == '.' && safe - 1 != decimal;
          return sign.length +
              i +
              (afterGroup && i + 1 < integer.length && integer[i + 1] == '.'
                  ? 2
                  : 1);
        }
      }
      return sign.length + integer.length;
    }

    return value.copyWith(
      text: formatted,
      selection: TextSelection(
        baseOffset: offset(value.selection.baseOffset),
        extentOffset: offset(value.selection.extentOffset),
        affinity: value.selection.affinity,
        isDirectional: value.selection.isDirectional,
      ),
      composing: TextRange.empty,
    );
  }
}

bool _digit(int code) => code >= 48 && code <= 57;
bool _grouped(String text, String separator) {
  final value = text.replaceFirst(RegExp(r'^[+\-]'), '');
  final groups = value.split(separator);
  return groups.length > 1 &&
      groups.first.isNotEmpty &&
      groups.first.length <= 3 &&
      groups.first != '0' &&
      groups.first.codeUnits.every(_digit) &&
      groups.skip(1).every((g) => g.length == 3 && g.codeUnits.every(_digit));
}

String _group(String digits) {
  final result = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) result.write('.');
    result.write(digits[i]);
  }
  return result.toString();
}

bool _canonical(TextEditingValue value) => RegExp(
  r'^[+\-]?(?:0|[1-9][0-9]{0,2}(?:\.[0-9]{3})*)(?:,[0-9]*)?$',
).hasMatch(value.text);
bool _localDigitEdit(TextEditingValue oldValue, TextEditingValue newValue) {
  final selection = oldValue.selection;
  if (!_canonical(oldValue) ||
      !selection.isValid ||
      selection.end > oldValue.text.length) {
    return false;
  }
  final before = oldValue.text, after = newValue.text;
  final prefix = before.substring(0, selection.start),
      suffix = before.substring(selection.end);
  final insertedLength = after.length - prefix.length - suffix.length;
  if (insertedLength >= 0 &&
      after.startsWith(prefix) &&
      after.endsWith(suffix)) {
    return RegExp(
      r'^[0-9]*$',
    ).hasMatch(after.substring(prefix.length, prefix.length + insertedLength));
  }
  if (!selection.isCollapsed || after.length >= before.length) return false;
  final removed = before.length - after.length, caret = selection.extentOffset;
  return (caret >= removed &&
          before.replaceRange(caret - removed, caret, '') == after) ||
      (caret + removed <= before.length &&
          before.replaceRange(caret, caret + removed, '') == after);
}

TextEditingValue? _deleteSeparator(
  TextEditingValue oldValue,
  TextEditingValue newValue,
) {
  if (!_canonical(oldValue) ||
      !oldValue.selection.isValid ||
      !oldValue.selection.isCollapsed ||
      !newValue.selection.isCollapsed ||
      newValue.text.length != oldValue.text.length - 1) {
    return null;
  }
  final caret = oldValue.selection.extentOffset, text = oldValue.text;
  int? start, end;
  if (caret >= 2 &&
      caret <= text.length &&
      text[caret - 1] == '.' &&
      newValue.selection.extentOffset == caret - 1 &&
      text.replaceRange(caret - 1, caret, '') == newValue.text) {
    start = caret - 2;
    end = caret;
  } else if (caret >= 0 &&
      caret + 1 < text.length &&
      text[caret] == '.' &&
      newValue.selection.extentOffset == caret &&
      text.replaceRange(caret, caret + 1, '') == newValue.text) {
    start = caret;
    end = caret + 2;
  }
  if (start == null || end == null) return null;
  return newValue.copyWith(
    text: text.replaceRange(start, end, ''),
    selection: TextSelection.collapsed(
      offset: start,
      affinity: newValue.selection.affinity,
    ),
  );
}
