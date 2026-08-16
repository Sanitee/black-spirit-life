import '../illuminated_ledger/ledger_spec.dart';
import '../sakura_night_garden/sakura_spec.dart';
import '../standard/standard_spec.dart';
import 'theme_spec.dart';

/// Stable registry for retained visual identities and persisted background IDs.
abstract final class RetainedThemeRegistry {
  static const ThemeSpec standard = StandardSpec.theme;
  static const ThemeSpec illuminatedLedger = IlluminatedLedgerSpec.theme;
  static const ThemeSpec sakuraNightGarden = SakuraNightGardenSpec.theme;

  static const List<ThemeSpec> themes = <ThemeSpec>[
    sakuraNightGarden,
    illuminatedLedger,
    standard,
  ];

  static final Map<String, ThemeSpec> _themesById =
      Map<String, ThemeSpec>.unmodifiable(<String, ThemeSpec>{
        for (final theme in themes) theme.id: theme,
      });

  static ThemeSpec byId(String id) => _themesById[id] ?? sakuraNightGarden;

  static const Map<String, ThemeSpec> _fullThemesByBackgroundId =
      <String, ThemeSpec>{
        IlluminatedLedgerSpec.backgroundId: illuminatedLedger,
        SakuraNightGardenSpec.backgroundId: sakuraNightGarden,
      };

  /// Full-theme background IDs resolve to their dedicated component systems.
  /// Atmospheric and plain backgrounds continue to share Standard components.
  static ThemeSpec resolve({required String backgroundId}) =>
      _fullThemesByBackgroundId[backgroundId] ??
      (StandardSpec.scenes.containsKey(backgroundId) ||
              StandardSpec.plainBackgrounds.containsKey(backgroundId)
          ? standard
          : sakuraNightGarden);

  static bool isKnownBackground(String backgroundId) =>
      _fullThemesByBackgroundId.containsKey(backgroundId) ||
      StandardSpec.scenes.containsKey(backgroundId) ||
      StandardSpec.plainBackgrounds.containsKey(backgroundId);
}
