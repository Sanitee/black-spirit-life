import 'package:flutter/services.dart';

/// Fifteen whole-silver digits, also exactly representable by a double.
const int maxSilverPrice = 999999999999999;

/// Parses a positive whole-silver price without guessing decimal separators.
/// Plain digits, dot grouping and space grouping are accepted; zero is invalid.
int? parseSilverPrice(String text) {
  final digits = _strictDigits(text);
  if (digits == null) return null;
  final value = _boundedValue(digits);
  return value != null && value > 0 ? value : null;
}

/// Formats an editable whole-silver value; zero remains available for validation.
String formatSilverPrice(int value) {
  RangeError.checkValueInInterval(value, 0, maxSilverPrice, 'value');
  return _group(value.toString());
}

/// Groups whole-silver input without changing the meaning of invalid paste.
///
/// Existing separators may move during a local digit edit. A newly pasted
/// separator must instead belong to a valid grouped whole number. Selection
/// endpoints follow their digit positions, not the changing text length.
final class SilverPriceInputFormatter extends TextInputFormatter {
  const SilverPriceInputFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    if (_composing(newValue)) return newValue;
    if (newValue.text.isEmpty) return newValue;
    final separatorDeletion = _deleteAcrossSeparator(oldValue, newValue);
    if (separatorDeletion != null) {
      return _formattedValue(
        separatorDeletion,
        separatorDeletion.text.replaceAll('.', ''),
      );
    }
    var digits = _strictDigits(newValue.text);
    if (digits == null && _isLocalDigitEdit(oldValue, newValue)) {
      digits = newValue.text.replaceAll('.', '');
    }
    if (digits == null || _boundedValue(digits) == null) {
      // IME composition is never rewritten mid-composition. If its committed
      // text is invalid, keep that text visible for field validation rather
      // than resurrecting a composing range or silently extracting digits.
      return _composing(oldValue) ? newValue : oldValue;
    }
    return _formattedValue(newValue, digits);
  }
}

final _digitsOnly = RegExp(r'^[0-9]+$');
final _dotGrouped = RegExp(r'^[1-9][0-9]{0,2}(?:\.[0-9]{3})+$');
final _spaceGrouped = RegExp(r'^[1-9][0-9]{0,2}(?: [0-9]{3})+$');

String? _strictDigits(String text) {
  final trimmed = text.trim();
  if (_digitsOnly.hasMatch(trimmed)) return trimmed;
  if (_dotGrouped.hasMatch(trimmed)) return trimmed.replaceAll('.', '');
  final spaced = trimmed.replaceAll('\u00a0', ' ').replaceAll('\u202f', ' ');
  if (_spaceGrouped.hasMatch(spaced)) return spaced.replaceAll(' ', '');
  return null;
}

int? _boundedValue(String digits) {
  final significant = _withoutLeadingZeros(digits);
  if (significant.length > 15) return null;
  final value = int.tryParse(significant);
  return value != null && value >= 0 && value <= maxSilverPrice ? value : null;
}

String _withoutLeadingZeros(String digits) =>
    digits.replaceFirst(RegExp(r'^0+(?=[0-9])'), '');

String _group(String digits) {
  final result = StringBuffer();
  for (var index = 0; index < digits.length; index++) {
    if (index > 0 && (digits.length - index) % 3 == 0) result.write('.');
    result.write(digits[index]);
  }
  return result.toString();
}

bool _composing(TextEditingValue value) =>
    value.composing.isValid && !value.composing.isCollapsed;

bool _canonical(TextEditingValue value) {
  final digits = _strictDigits(value.text);
  return digits != null && _group(_withoutLeadingZeros(digits)) == value.text;
}

bool _isLocalDigitEdit(TextEditingValue oldValue, TextEditingValue newValue) {
  final selection = oldValue.selection;
  if (!_canonical(oldValue) ||
      !selection.isValid ||
      selection.end > oldValue.text.length) {
    return false;
  }
  final before = oldValue.text;
  final after = newValue.text;
  final prefix = before.substring(0, selection.start);
  final suffix = before.substring(selection.end);
  final insertedLength = after.length - prefix.length - suffix.length;
  if (insertedLength >= 0 &&
      after.startsWith(prefix) &&
      after.endsWith(suffix)) {
    final inserted = after.substring(
      prefix.length,
      prefix.length + insertedLength,
    );
    return inserted.isEmpty || _digitsOnly.hasMatch(inserted);
  }
  if (!selection.isCollapsed || after.length >= before.length) return false;
  final removed = before.length - after.length;
  final caret = selection.extentOffset;
  return (caret >= removed &&
          before.replaceRange(caret - removed, caret, '') == after) ||
      (caret + removed <= before.length &&
          before.replaceRange(caret, caret + removed, '') == after);
}

TextEditingValue? _deleteAcrossSeparator(
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
  final caret = oldValue.selection.extentOffset;
  final text = oldValue.text;
  int? start;
  int? end;
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

TextEditingValue _formattedValue(TextEditingValue value, String digits) {
  final significant = _withoutLeadingZeros(digits);
  final grouped = _group(significant);
  if (value.text == grouped) return value;
  final removedZeros = digits.length - significant.length;
  int offset(int rawOffset) {
    if (rawOffset < 0) return rawOffset;
    final safe = rawOffset.clamp(0, value.text.length);
    final before = value.text
        .substring(0, safe)
        .codeUnits
        .where(_isDigit)
        .length;
    final wanted = (before - removedZeros).clamp(0, significant.length);
    if (wanted == 0) return 0;
    var seen = 0;
    for (var index = 0; index < grouped.length; index++) {
      if (_isDigit(grouped.codeUnitAt(index))) seen++;
      if (seen == wanted) {
        final wasAfterSeparator =
            safe > 0 && !_isDigit(value.text.codeUnitAt(safe - 1));
        return wasAfterSeparator &&
                index + 1 < grouped.length &&
                grouped[index + 1] == '.'
            ? index + 2
            : index + 1;
      }
    }
    return grouped.length;
  }

  return value.copyWith(
    text: grouped,
    selection: TextSelection(
      baseOffset: offset(value.selection.baseOffset),
      extentOffset: offset(value.selection.extentOffset),
      affinity: value.selection.affinity,
      isDirectional: value.selection.isDirectional,
    ),
    composing: TextRange.empty,
  );
}

bool _isDigit(int code) => code >= 48 && code <= 57;
