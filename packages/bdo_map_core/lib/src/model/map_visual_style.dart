/// Player-selectable treatment applied to the existing basemap imagery.
///
/// Neither option changes, replaces, or fabricates map geography. [standard]
/// renders the source tiles conservatively, while [vivid] applies a lightweight
/// color treatment that deepens greens and blues and slightly improves local
/// contrast beneath the unchanged marker and route layers.
enum BdoMapVisualStyle {
  standard,
  vivid;

  String get playerLabel => switch (this) {
    standard => 'Standard map colors',
    vivid => 'Vivid map colors',
  };

  static BdoMapVisualStyle fromJson(Object? value) => switch (value) {
    'vivid' => vivid,
    _ => standard,
  };
}
