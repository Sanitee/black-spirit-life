import 'planner_formatters.dart';

/// Display only. Never use an abbreviated value for arithmetic or persistence.
String formatCompactSilver(num value) {
  if (!value.isFinite) return '—';
  var magnitude = value.abs().toDouble();
  var unit = 0;
  const suffixes = ['', 'k', 'm', 'b', 't'];
  while (magnitude >= 1000 && unit < suffixes.length - 1) {
    magnitude /= 1000;
    unit++;
  }
  magnitude = unit == 0
      ? magnitude.roundToDouble()
      : (magnitude * 10).roundToDouble() / 10;
  if (magnitude >= 1000 && unit < suffixes.length - 1) {
    magnitude /= 1000;
    unit++;
  }
  final signed = value < 0 && magnitude != 0 ? -magnitude : magnitude;
  return '${formatQuantity(signed)}${suffixes[unit]}';
}
