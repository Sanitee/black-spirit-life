/// The user's Planner reading size, independent of theme and craft mode.
abstract final class PlannerContentScale {
  static const double defaultValue = 1;
  static const double minimum = 1;
  static const double maximum = 1.25;

  static double normalize(Object? value) {
    if (value is! num || !value.isFinite) return defaultValue;
    return value.toDouble().clamp(minimum, maximum);
  }
}
