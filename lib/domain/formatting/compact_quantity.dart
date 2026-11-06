import 'compact_silver.dart';
import 'planner_formatters.dart';

/// Display only: share silver's comma-decimal k/m/b/t notation for large counts,
/// while retaining the existing quantity precision for small fractional values.
/// Never parse this label back into inventory, calculations or saved state.
String formatCompactQuantity(num value) {
  if (!value.isFinite) return '—';
  return value.abs() < 1000
      ? formatQuantity(value.toDouble())
      : formatCompactSilver(value);
}
