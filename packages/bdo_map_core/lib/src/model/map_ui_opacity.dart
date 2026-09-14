/// Background opacity only; map imagery, text and artwork stay unchanged.
abstract final class ResourceMapUiOpacity {
  static const double minimum = 0;
  static const double defaultValue = 1;
  static const double minimumMaterial = .02;

  static double normalize(Object? value) => value is num && value.isFinite
      ? value.toDouble().clamp(minimum, 1)
      : defaultValue;

  /// Retain a faint material tint without changing the user's saved value.
  static double material(Object? value) =>
      normalize(value).clamp(minimumMaterial, 1);
}
