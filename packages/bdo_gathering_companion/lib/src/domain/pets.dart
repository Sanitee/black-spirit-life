import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../assets.dart';

List<String> _strings(Object? value) =>
    value is List ? List.unmodifiable(value.whereType<String>()) : const [];

/// Informational pet recommendations, separate from selected session buffs.
class PetRecommendation {
  PetRecommendation.fromJson(Map<String, dynamic> json)
    : id = json['id'] as String? ?? '',
      name = json['name'] as String? ?? '',
      icon = json['icon'] as String? ?? '',
      exclusiveAbilityGroup = json['exclusiveAbilityGroup'] as String? ?? '',
      methodIds = _strings(json['methodIds']),
      summary = json['summary'] as String? ?? '',
      details = _strings(json['details']),
      hoverDetails = _strings(json['hoverDetails']),
      sourceUrls = _strings(json['sourceUrls']),
      spotIdsByMethod = Map.unmodifiable({
        if (json['spotIdsByMethod'] case final Map restrictions)
          for (final entry in restrictions.entries)
            if (entry.key is String) entry.key as String: _strings(entry.value),
      });

  final String id, name, icon, summary, exclusiveAbilityGroup;
  final List<String> methodIds, details, hoverDetails, sourceUrls;

  /// A listed method requires a selected, explicitly verified spot.
  /// An empty allowlist intentionally permits no spots for that method.
  final Map<String, List<String>> spotIdsByMethod;

  bool appliesTo({required String methodId, String? spotId}) {
    if (!methodIds.contains(methodId)) return false;
    final allowedSpots = spotIdsByMethod[methodId];
    // Hunting support is species-specific. Missing data must not recommend a
    // gathering quantity bonus for every hunted animal.
    if (exclusiveAbilityGroup == 'gathering-extra-proc' &&
        (methodId == 'hunting' || methodId == 'sniper')) {
      return spotId != null && (allowedSpots?.contains(spotId) ?? false);
    }
    return allowedSpots == null ||
        (spotId != null && allowedSpots.contains(spotId));
  }
}

/// Pet IDs that can be shown or recorded for the current activity and spot.
Set<String> applicablePetIds({
  required Iterable<PetRecommendation> pets,
  required String methodId,
  String? spotId,
}) => Set.unmodifiable({
  for (final pet in pets)
    if (pet.appliesTo(methodId: methodId, spotId: spotId)) pet.id,
});

/// Removes unknown or inapplicable IDs before a session is recorded.
///
/// Callers can compare this result with [selectedIds] and explain any removed
/// choices when the activity or spot changes. This does not choose a tier or
/// turn informational pet effects into buff totals.
Set<String> reconcileSelectedPetIds({
  required Iterable<String> selectedIds,
  required Iterable<PetRecommendation> pets,
  required String methodId,
  String? spotId,
}) {
  final allowed = applicablePetIds(
    pets: pets,
    methodId: methodId,
    spotId: spotId,
  );
  return Set.unmodifiable(selectedIds.where(allowed.contains));
}

/// Reads a small bundled catalog once. No user preferences or files are written.
class PetCatalog {
  static List<PetRecommendation>? _cache;
  static Future<List<PetRecommendation>>? _loading;

  static Future<List<PetRecommendation>> load() {
    final cached = _cache;
    if (cached != null) return SynchronousFuture(cached);
    return _loading ??= _read().then((pets) {
      _cache = pets;
      return pets;
    });
  }

  static Future<List<PetRecommendation>> _read() async {
    final json = jsonDecode(
      await rootBundle.loadString(
        gatheringBundleAsset('assets/data/pets.json'),
      ),
    );
    final rows = json is Map ? json['pets'] : null;
    return List.unmodifiable([
      if (rows is List)
        for (final row in rows)
          if (row is Map)
            PetRecommendation.fromJson(Map<String, dynamic>.from(row)),
    ]);
  }
}
