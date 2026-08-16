/// Locale choices supported by the planner's deterministic domain formatters.
///
/// These formatters deliberately avoid the process locale. Golden tests and
/// exported text therefore stay stable on every Windows installation.
enum PlannerNumberLocale { deDe, invariant }

String formatQuantity(
  double value, {
  PlannerNumberLocale locale = PlannerNumberLocale.deDe,
  int? fractionDigits,
}) {
  if (!value.isFinite) return '0';
  final digits = fractionDigits ?? (_isCloseToInteger(value) ? 0 : 1);
  final safeDigits = digits.clamp(0, 12).toInt();
  var result = _formatFixed(value, safeDigits, locale: locale, grouped: true);
  if (fractionDigits == null && safeDigits > 0) {
    result = _trimFraction(result, locale);
  }
  return result;
}

/// A compact invariant representation suitable for editable numeric fields.
///
/// Unlike [formatQuantity], this never inserts grouping separators and keeps
/// enough precision for stored inventory values.
String formatEditableQuantity(double value, {int fractionDigits = 4}) {
  if (!value.isFinite) return '0';
  final safeDigits = fractionDigits.clamp(0, 12).toInt();
  return _trimFraction(
    _formatFixed(
      value,
      safeDigits,
      locale: PlannerNumberLocale.invariant,
      grouped: false,
    ),
    PlannerNumberLocale.invariant,
  );
}

/// A grouped `de-DE` representation that remains safe to place back into an
/// editable field. It keeps stored precision while making long amounts such
/// as `10000` immediately readable as `10.000`.
String formatGroupedEditableQuantity(double value, {int fractionDigits = 4}) {
  if (!value.isFinite) return '0';
  final safeDigits = fractionDigits.clamp(0, 12).toInt();
  return _trimFraction(
    _formatFixed(
      value,
      safeDigits,
      locale: PlannerNumberLocale.deDe,
      grouped: true,
    ),
    PlannerNumberLocale.deDe,
  );
}

/// Parses invariant input as well as common `de-DE` decimal/grouping forms.
double? parsePlannerNumber(String text) {
  final trimmed = text.trim().replaceAll(RegExp(r'\s+'), '');
  if (trimmed.isEmpty) return null;
  final comma = trimmed.lastIndexOf(',');
  final dot = trimmed.lastIndexOf('.');
  String normalized;
  if (comma >= 0 && dot >= 0) {
    final decimalIndex = comma > dot ? comma : dot;
    final decimal = trimmed[decimalIndex];
    final grouping = decimal == ',' ? '.' : ',';
    normalized = trimmed.replaceAll(grouping, '');
    if (decimal == ',') normalized = normalized.replaceAll(',', '.');
  } else if (comma >= 0) {
    // A lone comma is the de-DE decimal separator. Repeated commas can only
    // be an invariant grouped integer (for example `1,234,567`).
    normalized =
        trimmed.indexOf(',') != comma && _isGroupedInteger(trimmed, ',')
        ? trimmed.replaceAll(',', '')
        : trimmed.replaceAll(',', '.');
  } else if (dot >= 0 && _isGroupedInteger(trimmed, '.')) {
    // Values rendered by [formatQuantity] use a dot for de-DE grouping. This
    // branch is what makes an editable `1.900` round-trip as 1900 instead of
    // silently corrupting it to 1.9. Dot decimals such as `12.75` and `0.125`
    // remain decimal input.
    normalized = trimmed.replaceAll('.', '');
  } else {
    normalized = trimmed;
  }
  final value = double.tryParse(normalized);
  return value != null && value.isFinite ? value : null;
}

bool _isGroupedInteger(String value, String separator) {
  final unsigned = value.startsWith('-') || value.startsWith('+')
      ? value.substring(1)
      : value;
  final groups = unsigned.split(separator);
  if (groups.length < 2 ||
      groups.first.isEmpty ||
      groups.first.length > 3 ||
      groups.first == '0') {
    return false;
  }
  return groups.first.codeUnits.every(_isAsciiDigit) &&
      groups
          .skip(1)
          .every(
            (group) =>
                group.length == 3 && group.codeUnits.every(_isAsciiDigit),
          );
}

bool _isAsciiDigit(int codeUnit) => codeUnit >= 0x30 && codeUnit <= 0x39;

String formatSilver(
  double value, {
  PlannerNumberLocale locale = PlannerNumberLocale.deDe,
}) {
  if (!value.isFinite) return '0';
  final rounded = _roundToEven(value);
  final absolute = rounded.abs();
  if (absolute >= 1000000000) {
    return '${_compact(rounded / 1000000000)}B';
  }
  if (absolute >= 1000000) {
    return '${_compact(rounded / 1000000)}M';
  }
  return _formatInteger(rounded, locale: locale, grouped: true);
}

String formatSilverLabel(
  double value, {
  PlannerNumberLocale locale = PlannerNumberLocale.deDe,
}) => '${formatSilver(value, locale: locale)} silver';

/// Formats an instant in UTC so output does not depend on the host time zone.
String formatPlannerDateTime(
  DateTime value, {
  PlannerNumberLocale locale = PlannerNumberLocale.deDe,
  bool includeSeconds = false,
}) {
  final utc = value.toUtc();
  final year = utc.year.toString().padLeft(4, '0');
  final month = utc.month.toString().padLeft(2, '0');
  final day = utc.day.toString().padLeft(2, '0');
  final hour = utc.hour.toString().padLeft(2, '0');
  final minute = utc.minute.toString().padLeft(2, '0');
  final seconds = includeSeconds
      ? ':${utc.second.toString().padLeft(2, '0')}'
      : '';
  return switch (locale) {
    PlannerNumberLocale.deDe => '$day.$month.$year, $hour:$minute$seconds UTC',
    PlannerNumberLocale.invariant =>
      '$year-$month-$day $hour:$minute$seconds UTC',
  };
}

String formatMarketFetchedAt(
  int millisecondsSinceEpoch, {
  PlannerNumberLocale locale = PlannerNumberLocale.deDe,
}) {
  if (millisecondsSinceEpoch <= 0) return 'Never';
  return formatPlannerDateTime(
    DateTime.fromMillisecondsSinceEpoch(millisecondsSinceEpoch, isUtc: true),
    locale: locale,
  );
}

bool _isCloseToInteger(double value) =>
    (value - value.roundToDouble()).abs() < .001;

String _compact(double value) => _trimFraction(
  _formatFixed(value, 1, locale: PlannerNumberLocale.invariant, grouped: false),
  PlannerNumberLocale.invariant,
);

String _formatFixed(
  double value,
  int fractionDigits, {
  required PlannerNumberLocale locale,
  required bool grouped,
}) {
  var factor = 1;
  for (var index = 0; index < fractionDigits; index++) {
    factor *= 10;
  }
  final rounded = _roundToEven(value * factor);
  final negative = rounded < 0 || (rounded == 0 && value.isNegative);
  final absolute = rounded.abs();
  final integer = absolute ~/ factor;
  var formattedInteger = _formatInteger(
    integer,
    locale: locale,
    grouped: grouped,
  );
  if (negative) {
    formattedInteger = '-$formattedInteger';
  }
  if (fractionDigits == 0) return formattedInteger;
  final decimal = locale == PlannerNumberLocale.deDe ? ',' : '.';
  final fraction = (absolute % factor).toString().padLeft(fractionDigits, '0');
  return '$formattedInteger$decimal$fraction';
}

int _roundToEven(double value) {
  final lower = value.floor();
  final fraction = value - lower;
  if (fraction < .5) return lower;
  if (fraction > .5) return lower + 1;
  return lower.isEven ? lower : lower + 1;
}

String _formatInteger(
  int value, {
  required PlannerNumberLocale locale,
  required bool grouped,
}) {
  final negative = value < 0;
  final digits = value.abs().toString();
  if (!grouped || digits.length <= 3) return '${negative ? '-' : ''}$digits';
  final separator = locale == PlannerNumberLocale.deDe ? '.' : ',';
  final buffer = StringBuffer(negative ? '-' : '');
  for (var index = 0; index < digits.length; index++) {
    if (index > 0 && (digits.length - index) % 3 == 0) {
      buffer.write(separator);
    }
    buffer.write(digits[index]);
  }
  return buffer.toString();
}

String _trimFraction(String value, PlannerNumberLocale locale) {
  final decimal = locale == PlannerNumberLocale.deDe ? ',' : '.';
  if (!value.contains(decimal)) return value;
  return value
      .replaceFirst(RegExp(r'0+$'), '')
      .replaceFirst(RegExp('${RegExp.escape(decimal)}\$'), '');
}
