import '../../domain/models/catalog_models.dart';
import '../../domain/models/craft_mode.dart';

class CatalogRepository {
  CatalogRepository(this.snapshot)
    : _itemIndexes = {
        for (final mode in CraftMode.values)
          mode: _NameIndex(snapshot.forMode(mode).items),
      },
      _iconIndexes = {
        for (final mode in CraftMode.values)
          mode: _NameIndex(snapshot.forMode(mode).iconDataUris),
      },
      _iconAliases = _NameIndex(
        _stringMap(snapshot.supportingData['iconAliases']),
      ),
      _marketIds = _NameIndex(_stringMap(snapshot.supportingData['marketIds'])),
      _normalizedMarketIds = _stringMap(
        snapshot.supportingData['marketNameIds'],
      );

  final CatalogSnapshot snapshot;
  final Map<CraftMode, _NameIndex<Recipe>> _itemIndexes;
  final Map<CraftMode, _NameIndex<String>> _iconIndexes;
  final _NameIndex<String> _iconAliases;
  final _NameIndex<String> _marketIds;
  final Map<String, String> _normalizedMarketIds;

  Recipe? recipe(CraftMode mode, String name) =>
      _itemIndexes[mode]!.resolve(name);

  String? iconDataUri(
    CraftMode mode,
    String name, {
    Iterable<String> aliases = const <String>[],
  }) {
    final direct = _iconDataUriForName(mode, name);
    if (direct != null) return direct;
    for (final alias in aliases) {
      final resolved = _iconDataUriForName(mode, alias);
      if (resolved != null) return resolved;
    }
    final catalogAlias = _iconAliases.resolve(name);
    return catalogAlias == null
        ? null
        : _iconDataUriForName(mode, catalogAlias);
  }

  /// Resolves artwork without letting the selected craft mode hide an
  /// otherwise bundled item icon.
  ///
  /// Mode-owned planner screens keep using [iconDataUri]. Shared surfaces
  /// such as the resource map may use this method because worker outputs are
  /// not inherently tied to Alchemy, Cooking, or Processing.
  String? iconDataUriAcrossModes(
    CraftMode preferredMode,
    String name, {
    Iterable<String> aliases = const <String>[],
  }) {
    final preferred = iconDataUri(preferredMode, name, aliases: aliases);
    if (preferred != null) return preferred;
    for (final mode in CraftMode.values) {
      if (mode == preferredMode) continue;
      final resolved = iconDataUri(mode, name, aliases: aliases);
      if (resolved != null) return resolved;
    }
    return null;
  }

  String? _iconDataUriForName(CraftMode mode, String name) {
    final icons = _iconIndexes[mode]!;
    final exact = icons.exact(name);
    if (exact != null) return exact;

    final candidates = icons.candidates(name);
    if (candidates.isEmpty) return null;
    final canonicalNames = _itemIndexes[mode]!.candidateNames(name);
    if (canonicalNames.isNotEmpty) {
      final canonicalIcon = icons.exact(canonicalNames.first);
      if (canonicalIcon != null) return canonicalIcon;
    }
    candidates.sort((left, right) => left.key.compareTo(right.key));
    return candidates.first.value;
  }

  String? bundledMarketId(String name, {Iterable<String> aliases = const []}) {
    final exact = _marketIds.exact(name);
    if (exact != null && exact.isNotEmpty) return exact;
    for (final alias in aliases) {
      final aliasExact = _marketIds.exact(alias);
      if (aliasExact != null && aliasExact.isNotEmpty) return aliasExact;
    }

    final normalized = _normalizedMarketIds[normalizeMarketName(name)];
    if (normalized != null && normalized.isNotEmpty) return normalized;
    for (final alias in aliases) {
      final aliasNormalized = _normalizedMarketIds[normalizeMarketName(alias)];
      if (aliasNormalized != null && aliasNormalized.isNotEmpty) {
        return aliasNormalized;
      }
    }
    return null;
  }
}

String normalizeMarketName(String value) =>
    value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

class _NameIndex<T> {
  _NameIndex(Map<String, T> source) : _exact = Map.unmodifiable(source) {
    for (final entry in source.entries) {
      _folded.putIfAbsent(_fold(entry.key), () => []).add(entry);
    }
  }

  final Map<String, T> _exact;
  final Map<String, List<MapEntry<String, T>>> _folded = {};

  T? exact(String name) => _exact[name];

  T? resolve(String name) {
    final exactValue = exact(name);
    if (exactValue != null) return exactValue;
    final matches = candidates(name);
    if (matches.isEmpty) return null;
    matches.sort((left, right) => left.key.compareTo(right.key));
    return matches.first.value;
  }

  List<MapEntry<String, T>> candidates(String name) =>
      List.of(_folded[_fold(name)] ?? const []);

  List<String> candidateNames(String name) =>
      candidates(name).map((entry) => entry.key).toList()..sort();
}

String _fold(String value) => value.toLowerCase();

Map<String, String> _stringMap(Object? value) {
  if (value is! Map) return const {};
  return value.map((key, item) => MapEntry(key.toString(), '$item'));
}
