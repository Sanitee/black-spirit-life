import 'dart:collection';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:image/image.dart' as image;

import '../../domain/models/catalog_models.dart';
import '../../domain/models/craft_mode.dart';

const int inventoryScreenshotMaximumQuantity = 999999999999;
const int inventoryScreenshotMaximumSlots = 192;
// The native helper returns at most this many candidate artworks. One artwork
// can intentionally represent many BDO items (especially dried fish), so the
// app must not apply this limit again after expanding artwork to item names.
const int inventoryScreenshotMaximumIconCandidates = 64;

const double _credibleItemScore = .70;
const double _sourceRescueItemScore = .50;
const double _automaticItemScore = .82;
const double _automaticItemGap = .08;
const double _nativeRerankWindow = .02;
const double _trustedBorderConfidence = .70;
const double _qualityAlternativeScoreFactor = .72;

final class InventoryScreenshotRect {
  const InventoryScreenshotRect({
    required this.left,
    required this.top,
    required this.width,
    required this.height,
  });

  final int left;
  final int top;
  final int width;
  final int height;
}

enum InventoryOcrMaterialRelevance { relevant, uncertain, irrelevant }

final class InventoryItemMatch {
  const InventoryItemMatch({
    required this.name,
    required this.confidence,
    required this.sharedArtwork,
    required this.grade,
    this.itemId,
    this.artworkKey,
    this.orderGroupKey,
    this.qualityConflict = false,
    this.nativeMaterialEligible,
    this.primaryIngredientUseCount = 0,
    this.sourceVisualConfidence,
  });

  final String name;
  final double confidence;
  final bool sharedArtwork;
  final int? grade;
  final int? itemId;
  final String? artworkKey;

  /// Reviewed catalog family used only to improve Auto Arrange ordering.
  ///
  /// This is deliberately separate from [artworkKey]: a real BDO family such
  /// as Dried Fish can remain in one item-ID sequence while its icons change.
  final String? orderGroupKey;
  final bool qualityConflict;
  final bool? nativeMaterialEligible;

  /// Number of reviewed recipes that name this exact item as their primary
  /// ingredient rather than only as an alternative or result.
  ///
  /// This is used only as a conservative tie-breaker for a singleton,
  /// visually identical artwork family (for example Salt versus Sun-Dried
  /// Salt). It never overrides image evidence or a multi-row item-ID run.
  final int primaryIngredientUseCount;

  /// Full-resolution visual evidence retained for a reviewed catalogue
  /// fallback. [confidence] stays at the conservative review floor so a
  /// missing helper identity is never presented as certain; order optimization
  /// may still distinguish which fallback actually resembles this slot.
  final double? sourceVisualConfidence;
}

final class InventoryScreenshotRow {
  const InventoryScreenshotRow({
    required this.id,
    required this.slotId,
    required this.row,
    required this.column,
    required this.crop,
    required this.quantityText,
    required this.quantity,
    required this.quantitySuggested,
    required this.quantityApproximate,
    required this.quantityAssumedOne,
    required this.quantityConfidence,
    bool? quantitySuggestionUncertain,
    required this.matches,
    required this.selectedName,
    required this.relevance,
    required this.reviewRequired,
    this.itemSuggestionUncertain = false,
    required this.reviewReasons,
    required this.previewPng,
  }) : quantitySuggestionUncertain =
           quantitySuggestionUncertain ??
           (quantitySuggested != null || quantityAssumedOne);

  final String id;
  final String slotId;
  final int row;
  final int column;
  final InventoryScreenshotRect crop;
  final String quantityText;
  final int? quantity;
  final int? quantitySuggested;
  final bool quantityApproximate;
  final bool quantityAssumedOne;
  final double quantityConfidence;
  final bool quantitySuggestionUncertain;
  final List<InventoryItemMatch> matches;
  final String? selectedName;
  final InventoryOcrMaterialRelevance relevance;
  final bool reviewRequired;
  final bool itemSuggestionUncertain;
  final List<String> reviewReasons;
  final Uint8List previewPng;

  bool get hiddenByDefault =>
      relevance == InventoryOcrMaterialRelevance.irrelevant;
}

final class InventoryScreenshotDraft {
  const InventoryScreenshotDraft({
    required this.imageFingerprint,
    required this.sourceWidth,
    required this.sourceHeight,
    required this.gridColumns,
    required this.gridRows,
    required this.gridConfidence,
    required this.rows,
    required this.hiddenRows,
    required this.warnings,
  });

  final String imageFingerprint;
  final int sourceWidth;
  final int sourceHeight;
  final int gridColumns;
  final int gridRows;
  final double gridConfidence;
  final List<InventoryScreenshotRow> rows;
  final List<InventoryScreenshotRow> hiddenRows;
  final List<String> warnings;

  List<InventoryScreenshotRow> get allRows =>
      List<InventoryScreenshotRow>.unmodifiable(<InventoryScreenshotRow>[
        ...rows,
        ...hiddenRows,
      ]);
}

final class InventoryScreenshotAnalysis {
  const InventoryScreenshotAnalysis({
    required this.fileName,
    required this.mimeType,
    required this.sourceByteCount,
    required this.screenshotBytes,
    required this.plannerItemNames,
    required this.draft,
    this.plannerItemIds = const <String, int>{},
    this.plannerItemOrderGroups = const <String, String>{},
  });

  final String fileName;
  final String mimeType;
  final int sourceByteCount;
  final Uint8List screenshotBytes;
  final List<String> plannerItemNames;
  final Map<String, int> plannerItemIds;
  final Map<String, String> plannerItemOrderGroups;
  final InventoryScreenshotDraft draft;
}

final class InventoryOcrMaterialCatalog {
  InventoryOcrMaterialCatalog._({
    required this.names,
    required this.itemIds,
    required this.itemOrderGroups,
    required Map<String, List<_OcrMaterial>> materialsByIcon,
    required Map<String, List<_AppIconTemplate>> templatesByName,
    required List<_SupplementalMaterial> supplementalMaterials,
    required Set<String> knownOutOfScopeIcons,
    required Set<String> namesWithNativeArtwork,
  }) : _materialsByIcon = UnmodifiableMapView<String, List<_OcrMaterial>>(
         materialsByIcon,
       ),
       _templatesByName = UnmodifiableMapView<String, List<_AppIconTemplate>>(
         templatesByName,
       ),
       _supplementalMaterials = List<_SupplementalMaterial>.unmodifiable(
         supplementalMaterials,
       ),
       _knownOutOfScopeIcons = Set<String>.unmodifiable(knownOutOfScopeIcons),
       _namesWithNativeArtwork = Set<String>.unmodifiable(
         namesWithNativeArtwork,
       );

  factory InventoryOcrMaterialCatalog.fromRecipeBookJson({
    required CatalogSnapshot catalog,
    required String recipeBookJson,
    String? recipeBookIconIndexJson,
  }) {
    final eligibleNames = <String, String>{};
    final eligibleNamesByItemId = <int, String>{};
    final itemIds = <String, int>{};
    final qualityGrades = <String, int?>{};
    final primaryIngredientUseCounts = <String, int>{};

    final catalogItemIds = _catalogItemIds(catalog);

    void addEligibleName(String name, {int? itemId, int? qualityGrade}) {
      final trimmed = name.trim();
      if (trimmed.isNotEmpty) {
        final folded = _fold(trimmed);
        final resolvedId = itemId ?? catalogItemIds[folded];
        final canonical = eligibleNames.putIfAbsent(folded, () => trimmed);
        if (resolvedId != null) {
          if (itemId != null) {
            // An explicit recipe output ID is authoritative. It must replace
            // an earlier ingredient-name fallback or pricing alias rather
            // than allowing one item to inherit another item's identity.
            eligibleNamesByItemId[resolvedId] = canonical;
          } else {
            eligibleNamesByItemId.putIfAbsent(resolvedId, () => canonical);
          }
          if (itemId != null || !itemIds.containsKey(folded)) {
            itemIds[folded] = resolvedId;
          }
        }
        if (qualityGrade != null || !qualityGrades.containsKey(folded)) {
          qualityGrades[folded] = qualityGrade ?? qualityGrades[folded];
        }
      }
    }

    void addIngredient(Ingredient ingredient) {
      addEligibleName(ingredient.name);
      primaryIngredientUseCounts.update(
        _fold(ingredient.name),
        (count) => count + 1,
        ifAbsent: () => 1,
      );
      for (final name in ingredient.options) {
        addEligibleName(name);
      }
    }

    bool isReferenceOnly(Recipe recipe) => recipe.isReferenceOnly;

    for (final mode in CraftMode.values) {
      for (final recipe in catalog.forMode(mode).items.values) {
        if (isReferenceOnly(recipe)) continue;
        for (final ingredient in recipe.ingredients) {
          addIngredient(ingredient);
        }
        for (final variant in recipe.variants) {
          for (final ingredient in variant.ingredients) {
            addIngredient(ingredient);
          }
        }
      }
    }

    for (final mode in CraftMode.values) {
      for (final recipe in catalog.forMode(mode).items.values) {
        if (isReferenceOnly(recipe)) continue;
        // Every real Cooking, Alchemy, and Processing result belongs in the
        // shared inventory, including meals, elixirs, draughts, intermediate
        // materials, and special-quality results. Structured reference-only
        // records are documentation rather than inventory craft results; keep
        // one only when another real formula consumes it.
        addEligibleName(
          recipe.name,
          itemId: int.tryParse(recipe.marketId ?? ''),
        );
      }
    }

    // Quality crops are generated as planner materials during assembly rather
    // than appearing in every raw recipe. Keep those exact planner names in the
    // OCR catalog so a trusted quality border can distinguish, for example,
    // Special Sunflower from the normal crop even though both share an icon.
    final qualityConversions = catalog.supportingData['qualityConversions'];
    final qualityIngredients = catalog.supportingData['qualityIngredients'];
    final qualityBases = <String>{};
    final uncoloredWorthTierNames = <String>{
      for (final mode in CraftMode.values)
        for (final recipe in catalog.forMode(mode).items.values)
          if (_fold(recipe.group ?? '') == 'mushrooms' &&
              recipe.qualityBase != null)
            _fold(recipe.name),
    };
    if (qualityIngredients is Iterable<Object?>) {
      for (final value in qualityIngredients.whereType<String>()) {
        qualityBases.add(value);
      }
    }
    if (qualityConversions is Map<Object?, Object?>) {
      qualityBases.addAll(qualityConversions.keys.whereType<String>());
    }
    for (final sourceBase in qualityBases) {
      final baseName = eligibleNames[_fold(sourceBase)];
      if (baseName == null) continue;
      Map<Object?, Object?> conversion = const <Object?, Object?>{};
      if (qualityConversions is Map<Object?, Object?>) {
        for (final entry in qualityConversions.entries) {
          if (entry.key is String && _same(entry.key! as String, sourceBase)) {
            final value = entry.value;
            if (value is Map<Object?, Object?>) conversion = value;
            break;
          }
        }
      }

      String tierName(String tier, String fallback) {
        final rawTier = conversion[tier];
        if (rawTier is Map<Object?, Object?>) {
          final rawName = rawTier['name'];
          if (rawName is String && rawName.trim().isNotEmpty) {
            return rawName;
          }
        }
        return fallback;
      }

      final highName = tierName('high', 'High-Quality $baseName');
      addEligibleName(
        highName,
        // Big mushrooms have greater recipe worth but retain a normal item
        // border. Their structured Mushroom recipe records distinguish that
        // substitution tier from genuinely green High-Quality crops.
        qualityGrade: uncoloredWorthTierNames.contains(_fold(highName)) ? 0 : 1,
      );
      addEligibleName(
        tierName('special', 'Special $baseName'),
        qualityGrade: 2,
      );
    }

    final decoded = jsonDecode(recipeBookJson);
    if (decoded is! Map<String, Object?>) {
      throw const FormatException('The storage OCR item catalog is invalid.');
    }
    final rawItems = decoded['items'];
    if (rawItems is! Map<String, Object?>) {
      throw const FormatException('The storage OCR item catalog has no items.');
    }

    final eligibleHelperIcons = _eligibleHelperIconPaths(
      recipeBookIconIndexJson,
    );
    final lifeSkillRoles = _lifeSkillRecipeRoles(decoded['recipes']);

    // The shared Recipe Book contains a small number of current, explicit
    // life-skill ingredients that our planner formula snapshot does not yet
    // name. Admit them by item ID + structured recipe/description evidence,
    // never by a guess based on the display name.
    if (eligibleHelperIcons.isNotEmpty) {
      for (final rawEntry in rawItems.entries) {
        final rawItem = rawEntry.value;
        if (rawItem is! Map<String, Object?>) continue;
        final sourceName = rawItem['name'];
        final sourceIcon = rawItem['icon'];
        if (sourceName is! String || sourceIcon is! String) continue;
        final itemId = int.tryParse(rawEntry.key);
        final icon = _normalizeIconPath(sourceIcon);
        if (itemId == null ||
            icon == null ||
            !eligibleHelperIcons.contains(icon)) {
          continue;
        }
        final description = rawItem['description'];
        final usedAsInput = lifeSkillRoles.inputs.contains(itemId);
        final usefulOutput =
            lifeSkillRoles.outputs.contains(itemId) &&
            !_declaresLifeSkillByproduct(description);
        if (!usedAsInput &&
            !usefulOutput &&
            !_declaresLifeSkillIngredient(description)) {
          continue;
        }
        if (eligibleNamesByItemId.containsKey(itemId)) continue;
        final gradeValue = rawItem['grade'];
        // Overlay/helper-only records may use reserved synthetic IDs. When
        // the app catalogue already knows the current canonical item ID, keep
        // that identity for ordering and duplicate reconciliation. The helper
        // ID remains useful only for locating its artwork/recipe record.
        addEligibleName(
          sourceName,
          itemId: catalogItemIds[_fold(sourceName)] ?? itemId,
          qualityGrade: gradeValue is num ? gradeValue.toInt() : null,
        );
      }
    }

    final materialsByIcon = <String, List<_OcrMaterial>>{};
    final orderGroupsByName = _inventoryOcrOrderGroups(catalog);
    final allAppIcons = _catalogIconDataUris(catalog);
    final iconUrisByName = <String, List<String>>{};
    for (final entry in eligibleNames.entries) {
      final uris = allAppIcons[entry.key];
      if (uris != null) {
        iconUrisByName[entry.key] = List<String>.from(uris);
      }
    }
    for (final rawEntry in rawItems.entries) {
      final rawItem = rawEntry.value;
      if (rawItem is! Map<String, Object?>) continue;
      final sourceName = rawItem['name'];
      final sourceIcon = rawItem['icon'];
      if (sourceName is! String || sourceIcon is! String) continue;
      final icon = _normalizeIconPath(sourceIcon);
      final itemId = int.tryParse(rawEntry.key);
      final eligible = itemId == null
          ? eligibleNames[_fold(sourceName)]
          : eligibleNamesByItemId[itemId] ?? eligibleNames[_fold(sourceName)];
      if (eligible == null || icon == null) continue;
      final gradeValue = rawItem['grade'];
      final helperGrade = gradeValue is num ? gradeValue.toInt() : null;
      final grade = qualityGrades[_fold(eligible)] ?? helperGrade;
      final canonicalItemId = itemIds[_fold(eligible)] ?? itemId;
      final material = _OcrMaterial(
        name: eligible,
        icon: icon,
        grade: grade,
        itemId: canonicalItemId,
        orderGroupKey: orderGroupsByName[_fold(eligible)],
        primaryIngredientUseCount:
            primaryIngredientUseCounts[_fold(eligible)] ?? 0,
      );
      if (canonicalItemId != null) {
        itemIds.putIfAbsent(_fold(eligible), () => canonicalItemId);
      }
      final sourceIconUris = allAppIcons[_fold(sourceName)];
      if (sourceIconUris != null) {
        final aliases = iconUrisByName.putIfAbsent(
          _fold(eligible),
          () => <String>[],
        );
        for (final uri in sourceIconUris) {
          if (!aliases.contains(uri)) aliases.add(uri);
        }
      }
      final family = materialsByIcon.putIfAbsent(icon, () => <_OcrMaterial>[]);
      if (!family.any((candidate) => _same(candidate.name, eligible))) {
        family.add(material);
      }
    }

    for (final family in materialsByIcon.values) {
      family.sort(_compareMaterials);
    }
    final appTemplates = <String, _AppIconTemplate>{};
    final templatesByName = <String, List<_AppIconTemplate>>{};
    final namesByAppArtwork = <String, Set<String>>{};
    for (final entry in iconUrisByName.entries) {
      final templates = <_AppIconTemplate>[];
      for (final uri in entry.value) {
        final template = appTemplates.putIfAbsent(
          uri,
          () => _AppIconTemplate.fromDataUri(uri),
        );
        if (template.isUsable && !templates.contains(template)) {
          templates.add(template);
          namesByAppArtwork
              .putIfAbsent(template.artworkKey, () => <String>{})
              .add(entry.key);
        }
      }
      if (templates.isNotEmpty) templatesByName[entry.key] = templates;
    }

    // The sealed RecipeBook atlas does not contain every current member of
    // the planner's reviewed substitute families. The app catalogue does,
    // and several missing members use byte-identical artwork (for example
    // Marmot/Fox blood, Ogre/Bear blood, Worm/Lizard blood and Cobra/Kuku
    // Bird blood). Bridge only an exact app-artwork match inside the same
    // authoritative family. This expands the native visual family without
    // guessing from names or allowing an unrelated look-alike into it.
    for (final nativeFamily in materialsByIcon.values) {
      final seeds = List<_OcrMaterial>.of(nativeFamily);
      for (final seed in seeds) {
        final orderGroup = seed.orderGroupKey;
        if (orderGroup == null || orderGroup.isEmpty) continue;
        final templates = templatesByName[_fold(seed.name)];
        if (templates == null) continue;
        for (final template in templates) {
          for (final aliasKey
              in namesByAppArtwork[template.artworkKey] ?? const <String>{}) {
            if (orderGroupsByName[aliasKey] != orderGroup ||
                nativeFamily.any(
                  (material) => _fold(material.name) == aliasKey,
                )) {
              continue;
            }
            final aliasName = eligibleNames[aliasKey];
            if (aliasName == null) continue;
            nativeFamily.add(
              _OcrMaterial(
                name: aliasName,
                icon: seed.icon,
                grade: qualityGrades[aliasKey] ?? seed.grade,
                itemId: itemIds[aliasKey],
                orderGroupKey: orderGroup,
                primaryIngredientUseCount:
                    primaryIngredientUseCounts[aliasKey] ?? 0,
              ),
            );
          }
        }
      }
      nativeFamily.sort(_compareMaterials);
    }

    final supplementalMaterials = <_SupplementalMaterial>[];
    final supplementalArtworkCounts = <String, int>{};
    for (final entry in eligibleNames.entries) {
      for (final template
          in templatesByName[entry.key] ?? const <_AppIconTemplate>[]) {
        supplementalMaterials.add(
          _SupplementalMaterial(
            name: entry.value,
            itemId: itemIds[entry.key],
            grade: qualityGrades[entry.key],
            orderGroupKey: orderGroupsByName[entry.key],
            primaryIngredientUseCount:
                primaryIngredientUseCounts[entry.key] ?? 0,
            template: template,
          ),
        );
        supplementalArtworkCounts.update(
          template.artworkKey,
          (count) => count + 1,
          ifAbsent: () => 1,
        );
      }
    }
    for (final material in supplementalMaterials) {
      material.sharedArtwork =
          (supplementalArtworkCounts[material.template.artworkKey] ?? 0) > 1;
    }
    final knownOutOfScopeIcons = <String>{};
    for (final rawEntry in rawItems.entries) {
      final rawItem = rawEntry.value;
      if (rawItem is! Map<String, Object?>) continue;
      final sourceName = rawItem['name'];
      final sourceIcon = rawItem['icon'];
      if (sourceName is! String || sourceIcon is! String) continue;
      final icon = _normalizeIconPath(sourceIcon);
      if (icon == null || materialsByIcon.containsKey(icon)) continue;
      final itemId = int.tryParse(rawEntry.key);
      final eligible = itemId == null
          ? eligibleNames[_fold(sourceName)]
          : eligibleNamesByItemId[itemId] ?? eligibleNames[_fold(sourceName)];
      if (eligible == null) knownOutOfScopeIcons.add(icon);
    }
    // Keep the complete planner ingredient set available for manual correction,
    // even if an older helper catalog cannot propose one of those items yet.
    final names = eligibleNames.values.toList()..sort(_compareNames);
    if (names.isEmpty || materialsByIcon.isEmpty) {
      throw const FormatException(
        'The storage OCR item catalog does not match this planner catalog.',
      );
    }
    return InventoryOcrMaterialCatalog._(
      names: List<String>.unmodifiable(names),
      itemIds: UnmodifiableMapView<String, int>(itemIds),
      itemOrderGroups: UnmodifiableMapView<String, String>(orderGroupsByName),
      materialsByIcon: <String, List<_OcrMaterial>>{
        for (final entry in materialsByIcon.entries)
          entry.key: List<_OcrMaterial>.unmodifiable(entry.value),
      },
      templatesByName: <String, List<_AppIconTemplate>>{
        for (final entry in templatesByName.entries)
          entry.key: List<_AppIconTemplate>.unmodifiable(entry.value),
      },
      supplementalMaterials: supplementalMaterials,
      knownOutOfScopeIcons: knownOutOfScopeIcons,
      namesWithNativeArtwork: <String>{
        for (final family in materialsByIcon.values)
          for (final material in family) _fold(material.name),
      },
    );
  }

  final List<String> names;

  /// Canonical BDO item IDs, keyed by a folded display name.
  final Map<String, int> itemIds;
  final Map<String, String> itemOrderGroups;
  final Map<String, List<_OcrMaterial>> _materialsByIcon;
  final Map<String, List<_AppIconTemplate>> _templatesByName;
  final List<_SupplementalMaterial> _supplementalMaterials;
  final Set<String> _knownOutOfScopeIcons;
  final Set<String> _namesWithNativeArtwork;

  /// Installed-client artwork paths that belong to at least one admitted
  /// planner item. The complete set is intentionally exposed to the native
  /// bridge so source-resolution matching is not limited to the helper's
  /// low-resolution top-N result.
  Iterable<String> get nativeArtworkPaths => _materialsByIcon.keys;

  bool _isKnownOutOfScopeIcon(String icon) =>
      _knownOutOfScopeIcons.contains(icon);

  List<InventoryItemMatch> _matchesFor(
    List<InventoryOcrIconCandidate> candidates, {
    required int? borderGrade,
    required double borderConfidence,
    List<_InventoryIconFeature> sourceFeatures =
        const <_InventoryIconFeature>[],
    Map<String, _AppIconTemplate> nativeArtworkTemplates =
        const <String, _AppIconTemplate>{},
    Map<String, _AppIconTemplate> appArtworkTemplates =
        const <String, _AppIconTemplate>{},
    required List<_SupplementalMaterial> visualMaterials,
    bool allowSupplemental = true,
    bool forceSupplemental = false,
  }) {
    final mapped = <InventoryItemMatch>[];
    final reviewedFallbackVisualScores = <String, double>{};
    for (final candidate in candidates) {
      final hasSourceArtwork = nativeArtworkTemplates.containsKey(
        candidate.icon,
      );
      if (candidate.score <
          (hasSourceArtwork ? _sourceRescueItemScore : _credibleItemScore)) {
        continue;
      }
      final family = _materialsByIcon[candidate.icon];
      if (family == null || family.isEmpty) continue;
      var plausible = family;
      var qualityConflict = false;
      var qualityAlternatives = const <_OcrMaterial>[];
      if (borderGrade != null && borderConfidence >= _trustedBorderConfidence) {
        final matchingGrade = family
            .where((material) => material.grade == borderGrade)
            .toList(growable: false);
        if (matchingGrade.isNotEmpty) {
          plausible = matchingGrade;
          qualityAlternatives = family
              .where((material) => material.grade != borderGrade)
              .toList(growable: false);
        } else if (family.any((material) => material.grade != null)) {
          qualityConflict = true;
        }
      }

      void addMatches(
        List<_OcrMaterial> materials, {
        required double confidence,
        required bool conflict,
      }) {
        final shared = materials.length > 1;
        for (final material in materials) {
          final existing = mapped.indexWhere(
            (match) => _same(match.name, material.name),
          );
          final next = InventoryItemMatch(
            name: material.name,
            confidence: confidence,
            sharedArtwork: shared,
            grade: material.grade,
            itemId: material.itemId,
            artworkKey: candidate.icon,
            orderGroupKey: material.orderGroupKey,
            qualityConflict: conflict,
            nativeMaterialEligible: candidate.materialEligible,
            primaryIngredientUseCount: material.primaryIngredientUseCount,
          );
          if (existing < 0) {
            mapped.add(next);
          } else if (mapped[existing].confidence < next.confidence) {
            mapped[existing] = next;
          }
        }
      }

      addMatches(
        plausible,
        confidence: qualityConflict ? candidate.score * .9 : candidate.score,
        conflict: qualityConflict,
      );
      if (qualityAlternatives.isNotEmpty) {
        addMatches(
          qualityAlternatives,
          confidence: candidate.score * _qualityAlternativeScoreFactor,
          conflict: true,
        );
      }
    }
    if (sourceFeatures.isNotEmpty) {
      final original = List<InventoryItemMatch>.of(mapped);
      final sourceScores = <int, double>{};
      final templateScores = <String, double?>{};
      final alignedTemplateScores = <String, double?>{};

      double? scoreTemplates(
        List<_AppIconTemplate>? templates, {
        required bool aligned,
      }) {
        if (templates == null || templates.isEmpty) return null;
        final key = templates
            .map((template) => template.artworkKey)
            .join('\u001f');
        final cache = aligned ? alignedTemplateScores : templateScores;
        if (cache.containsKey(key)) return cache[key];
        final score = aligned
            ? _bestAlignedTemplateScore(sourceFeatures, templates)
            : _bestTemplateScore(sourceFeatures, templates);
        cache[key] = score;
        return score;
      }

      double? bestSourceScore;
      for (var index = 0; index < original.length; index += 1) {
        final current = original[index];
        final nativeArtwork = current.artworkKey == null
            ? null
            : nativeArtworkTemplates[current.artworkKey];
        final sourceScore = scoreTemplates(
          nativeArtwork == null
              ? _resolvedAppTemplatesForName(current.name, appArtworkTemplates)
              : <_AppIconTemplate>[nativeArtwork],
          aligned: false,
        );
        if (sourceScore == null) continue;
        final adjustedSource = current.qualityConflict
            ? sourceScore * _qualityAlternativeScoreFactor
            : sourceScore;
        sourceScores[index] = adjustedSource;
        if (bestSourceScore == null || adjustedSource > bestSourceScore) {
          bestSourceScore = adjustedSource;
        }
      }
      final basicBest = bestSourceScore;
      if (sourceScores.isNotEmpty && basicBest != null) {
        final ranked = sourceScores.entries.toList(growable: false)
          ..sort((left, right) => right.value.compareTo(left.value));
        final runnerUp = ranked.skip(1).firstOrNull?.value;
        final ambiguous = runnerUp != null && basicBest - runnerUp < .22;
        final alignmentLimit = ambiguous ? 12 : 4;
        // Always verify a bounded leading set at source resolution. A confident
        // 20 px atlas winner can still be the wrong near-identical flour, sap,
        // oil, hide, or mushroom; ambiguity merely expands the verification set.
        for (final entry in ranked.take(alignmentLimit)) {
          final current = original[entry.key];
          final nativeArtwork = current.artworkKey == null
              ? null
              : nativeArtworkTemplates[current.artworkKey];
          final aligned = scoreTemplates(
            nativeArtwork == null
                ? _resolvedAppTemplatesForName(
                    current.name,
                    appArtworkTemplates,
                  )
                : <_AppIconTemplate>[nativeArtwork],
            aligned: true,
          );
          if (aligned == null) continue;
          final refined = aligned * .70 + entry.value * .30;
          sourceScores[entry.key] = current.qualityConflict
              ? refined * _qualityAlternativeScoreFactor
              : refined;
        }
        bestSourceScore = sourceScores.values.reduce(math.max);
      }
      if (sourceScores.isNotEmpty) {
        final bestByNativeArtwork = <String, ({double score, int index})>{};
        for (final entry in sourceScores.entries) {
          final artwork = original[entry.key].artworkKey;
          if (artwork == null || !nativeArtworkTemplates.containsKey(artwork)) {
            continue;
          }
          final previous = bestByNativeArtwork[artwork];
          if (previous == null || entry.value > previous.score) {
            bestByNativeArtwork[artwork] = (
              score: entry.value,
              index: entry.key,
            );
          }
        }
        final rankedArtwork = bestByNativeArtwork.entries.toList(
          growable: false,
        )..sort((left, right) => right.value.score.compareTo(left.value.score));
        final leadingArtwork = rankedArtwork.firstOrNull;
        final artworkGap = leadingArtwork == null
            ? 0.0
            : leadingArtwork.value.score -
                  (rankedArtwork.skip(1).firstOrNull?.value.score ?? 0);
        if (leadingArtwork != null &&
            leadingArtwork.value.score >= .90 &&
            artworkGap >= .04) {
          // A decisive match against the installed client's full-resolution
          // artwork may rescue a low-scoring 20 px atlas candidate. Promote
          // the artwork family—not one arbitrary member—so truly shared icons
          // remain yellow/ambiguous while unique identities become reviewable.
          for (var index = 0; index < original.length; index += 1) {
            if (original[index].artworkKey != leadingArtwork.key) continue;
            final current = mapped[index];
            mapped[index] = InventoryItemMatch(
              name: current.name,
              confidence: math
                  .max(current.confidence, _credibleItemScore)
                  .toDouble(),
              sharedArtwork: current.sharedArtwork,
              grade: current.grade,
              itemId: current.itemId,
              artworkKey: current.artworkKey,
              orderGroupKey: current.orderGroupKey,
              qualityConflict: current.qualityConflict,
              nativeMaterialEligible: current.nativeMaterialEligible,
              primaryIngredientUseCount: current.primaryIngredientUseCount,
            );
          }
        }
      }
      // The installed-client matcher owns the absolute identity score. The
      // app artwork may promote a different close candidate only when its
      // source-resolution evidence is decisive; it must never erase a correct
      // native winner merely because catalog artwork has different framing.
      if (bestSourceScore != null && sourceScores.length > 1) {
        final rankedSource = sourceScores.entries.toList(growable: false)
          ..sort((left, right) => right.value.compareTo(left.value));
        final sourceWinner = rankedSource.first;
        final sourceGap = sourceWinner.value - rankedSource[1].value;
        final nativeRanking = List<int>.generate(original.length, (i) => i)
          ..sort(
            (left, right) =>
                original[right].confidence.compareTo(original[left].confidence),
          );
        final nativeWinner = nativeRanking.first;
        final sourceWinnerNativeRank = nativeRanking.indexOf(sourceWinner.key);
        final closeNativeCandidate =
            sourceWinnerNativeRank >= 0 &&
            sourceWinnerNativeRank < 3 &&
            original[nativeWinner].confidence -
                    original[sourceWinner.key].confidence <=
                _nativeRerankWindow;
        final winnerArtwork = original[sourceWinner.key].artworkKey;
        final decisiveSourceCandidate =
            winnerArtwork != null &&
            nativeArtworkTemplates.containsKey(winnerArtwork) &&
            sourceWinner.value >= .90 &&
            sourceGap >= .04;
        if (sourceGap >= .01 &&
            sourceWinner.key != nativeWinner &&
            (closeNativeCandidate || decisiveSourceCandidate)) {
          final winner = mapped[sourceWinner.key];
          final nativeConfidence = original[nativeWinner].confidence;
          mapped[sourceWinner.key] = InventoryItemMatch(
            name: winner.name,
            confidence: math
                .max(
                  winner.confidence,
                  (nativeConfidence + .002).clamp(0.0, 1.0),
                )
                .toDouble(),
            sharedArtwork: winner.sharedArtwork,
            grade: winner.grade,
            itemId: winner.itemId,
            artworkKey: winner.artworkKey,
            orderGroupKey: winner.orderGroupKey,
            qualityConflict: winner.qualityConflict,
            nativeMaterialEligible: winner.nativeMaterialEligible,
            primaryIngredientUseCount: winner.primaryIngredientUseCount,
          );
        }

        // Never manufacture visual certainty inside a byte-identical installed-
        // client artwork family. App-owned copies can have different borders,
        // scaling, or backgrounds; those packaging differences do not identify
        // the item in a storage slot. Shared families remain shared and are
        // resolved with authoritative catalogue/use/order context instead.
      }

      // Retain the full-resolution score for every mapped identity, not only
      // catalogue fallbacks. The review sequence optimizer can then weigh the
      // actual pixels/colour of each slot instead of falling back to the 20 px
      // helper confidence whenever two ordered families are close.
      for (final entry in sourceScores.entries) {
        if (entry.key < 0 || entry.key >= mapped.length) continue;
        final current = mapped[entry.key];
        mapped[entry.key] = InventoryItemMatch(
          name: current.name,
          confidence: current.confidence,
          sharedArtwork: current.sharedArtwork,
          grade: current.grade,
          itemId: current.itemId,
          artworkKey: current.artworkKey,
          orderGroupKey: current.orderGroupKey,
          qualityConflict: current.qualityConflict,
          nativeMaterialEligible: current.nativeMaterialEligible,
          primaryIngredientUseCount: current.primaryIngredientUseCount,
          sourceVisualConfidence: entry.value,
        );
      }

      final originalSorted = List<InventoryItemMatch>.of(original)
        ..sort((left, right) => right.confidence.compareTo(left.confidence));
      final originalTop = originalSorted.firstOrNull;
      InventoryItemMatch? structuredOriginalTop;
      for (final match in originalSorted) {
        if (match.orderGroupKey != null && match.orderGroupKey!.isNotEmpty) {
          structuredOriginalTop = match;
          break;
        }
      }
      final protectsStructuredOriginal =
          originalTop != null &&
          structuredOriginalTop != null &&
          originalTop.confidence - structuredOriginalTop.confidence <= .12;
      final supplementalOrderGroup =
          !forceSupplemental &&
              protectsStructuredOriginal &&
              structuredOriginalTop.orderGroupKey == 'blood:all'
          ? structuredOriginalTop.orderGroupKey
          : null;
      // Every admitted item gets a cheap global check. A confidently wrong
      // low-resolution helper result must not prevent the correct current app
      // artwork from ever being considered. Only the bounded multimodal
      // shortlist below reaches the expensive full-resolution comparison.
      final shouldScanSupplemental = allowSupplemental;
      if (shouldScanSupplemental) {
        final eligibleSupplemental = <_SupplementalMaterial>[];
        for (final material in visualMaterials) {
          if (supplementalOrderGroup != null &&
              material.orderGroupKey != supplementalOrderGroup) {
            continue;
          }
          if (borderGrade != null &&
              borderConfidence >= _trustedBorderConfidence &&
              material.grade != null &&
              material.grade != borderGrade) {
            continue;
          }
          eligibleSupplemental.add(material);
        }

        // A full-resolution comparison against every app icon for every slot
        // is wasteful and used to add many weak look-alikes. A small 8x6
        // structure/chroma signature cheaply keeps a deliberately generous
        // shortlist; the existing pixel and translated comparisons still make
        // every final decision. Native candidates are always retained in the
        // shortlist so this optimization cannot discard helper evidence.
        final coarseScores = <_AppIconTemplate, double>{};
        final coarseShapeScores = <_AppIconTemplate, double>{};
        final coarseColorScores = <_AppIconTemplate, double>{};
        for (final material in eligibleSupplemental) {
          if (coarseScores.containsKey(material.template)) continue;
          final feature = material.template.feature;
          if (feature == null) continue;
          var bestCombined = double.negativeInfinity;
          var bestShape = double.negativeInfinity;
          var bestColor = double.negativeInfinity;
          for (final source in sourceFeatures) {
            // Shape and colour used to be recomputed for the blended,
            // shape-only, and colour-only rankings. Calculate each modality
            // once per source/template pair while preserving the three exact
            // maxima and therefore the identical shortlist and decisions.
            final shape = _compareCoarseIconShape(source, feature);
            final color = _compareCoarseIconColor(source, feature);
            bestCombined = math.max(bestCombined, shape * .78 + color * .22);
            bestShape = math.max(bestShape, shape);
            bestColor = math.max(bestColor, color);
          }
          coarseScores[material.template] = bestCombined;
          coarseShapeScores[material.template] = bestShape;
          coarseColorScores[material.template] = bestColor;
        }
        final rankedCoarse = coarseScores.entries.toList(growable: false)
          ..sort((left, right) => right.value.compareTo(left.value));
        final rankedShape = coarseShapeScores.entries.toList(growable: false)
          ..sort((left, right) => right.value.compareTo(left.value));
        final rankedColor = coarseColorScores.entries.toList(growable: false)
          ..sort((left, right) => right.value.compareTo(left.value));
        final shortlistedTemplates = <_AppIconTemplate>{
          // Unioning independent rankings prevents either a similar silhouette
          // or a similar palette from pruning the true icon before the joint
          // pixel+colour matcher sees it.
          for (final entry in rankedCoarse.take(112)) entry.key,
          for (final entry in rankedShape.take(48)) entry.key,
          for (final entry in rankedColor.take(48)) entry.key,
        };
        final mappedNames = <String>{
          for (final match in mapped) _fold(match.name),
        };
        for (final material in eligibleSupplemental) {
          if (mappedNames.contains(_fold(material.name))) {
            shortlistedTemplates.add(material.template);
          }
        }

        final supplementalScores = <_AppIconTemplate, double>{};
        for (final material in eligibleSupplemental) {
          if (!shortlistedTemplates.contains(material.template)) continue;
          final feature = material.template.feature;
          if (feature == null) continue;
          supplementalScores.putIfAbsent(
            material.template,
            () => sourceFeatures
                .map((source) => _compareIconFeatures(source, feature))
                .reduce(math.max),
          );
        }

        // The helper's 20 px atlas is deliberately fast, while the app owns
        // higher-resolution artwork for every admitted planner identity. Run
        // the expensive translated comparison only for the closest app
        // templates. This lets a missing/low-ranked valid identity such as
        // Ash Sap, a Big mushroom, or a newer blood member recover without
        // changing the sealed helper or comparing every template at every
        // offset.
        final rankedTemplates = supplementalScores.entries.toList()
          ..sort((left, right) => right.value.compareTo(left.value));
        if (rankedTemplates.isNotEmpty) {
          final runnerUp = rankedTemplates.skip(1).firstOrNull?.value;
          final ambiguous =
              runnerUp != null && rankedTemplates.first.value - runnerUp < .22;
          final alignmentLimit = ambiguous ? 12 : 4;
          for (final entry in rankedTemplates.take(alignmentLimit)) {
            final scaleVariantsAreAppOnly = eligibleSupplemental
                .where((material) => identical(material.template, entry.key))
                .every(
                  (material) =>
                      !_namesWithNativeArtwork.contains(_fold(material.name)),
                );
            final aligned = _bestAlignedTemplateScore(
              sourceFeatures,
              <_AppIconTemplate>[entry.key],
              useScaleVariants: scaleVariantsAreAppOnly,
            );
            if (aligned == null) continue;
            supplementalScores[entry.key] = aligned * .70 + entry.value * .30;
          }
        }

        for (final material in eligibleSupplemental) {
          final score = supplementalScores[material.template];
          if (score == null) continue;
          reviewedFallbackVisualScores.update(
            _fold(material.name),
            (previous) => math.max(previous, score),
            ifAbsent: () => score,
          );
        }

        // Rank visual identities, not encoded template files. One item can
        // legitimately have both an app PNG and an installed-client WebP; if
        // those two representations are counted as competitors, their near-
        // identical scores erase the margin and prevent a missing true item
        // from ever entering the review. Conversely, genuinely shared art
        // still contributes one tied identity per member and therefore stays
        // ambiguous.
        final bestByName =
            <String, ({double score, _AppIconTemplate template})>{};
        for (final material in eligibleSupplemental) {
          final score = supplementalScores[material.template];
          if (score == null) continue;
          final nameKey = _fold(material.name);
          final previous = bestByName[nameKey];
          if (previous == null || score > previous.score) {
            bestByName[nameKey] = (score: score, template: material.template);
          }
        }
        final rankedIdentities = bestByName.entries.toList(
          growable: false,
        )..sort((left, right) => right.value.score.compareTo(left.value.score));
        final bestIdentity = rankedIdentities.firstOrNull;
        final runnerUpIdentity = rankedIdentities.skip(1).firstOrNull;
        final bestArtwork = bestIdentity == null
            ? null
            : MapEntry<String, double>(
                bestIdentity.value.template.artworkKey,
                bestIdentity.value.score,
              );
        final bestArtworkGap = bestArtwork == null
            ? 0.0
            : bestArtwork.value - (runnerUpIdentity?.value.score ?? 0);
        final admitsNewArtwork =
            bestArtwork != null &&
            bestArtwork.value >= .88 &&
            bestArtworkGap >= .012;
        final promotesNewArtwork =
            bestArtwork != null &&
            bestArtwork.value >= .90 &&
            bestArtworkGap >= .04;
        final nativeTopConfidence = originalTop?.confidence ?? 0;

        for (final material in eligibleSupplemental) {
          var score = supplementalScores[material.template] ?? 0;
          if (score < _credibleItemScore) continue;
          final qualityConflict =
              borderGrade != null &&
              borderConfidence >= _trustedBorderConfidence &&
              material.grade != null &&
              material.grade != borderGrade;
          if (qualityConflict) score *= _qualityAlternativeScoreFactor;
          final existing = mapped.indexWhere(
            (match) => _same(match.name, material.name),
          );
          final isBestArtwork =
              bestArtwork?.key == material.template.artworkKey;
          final promotesWithinReviewedFamily =
              isBestArtwork &&
              bestArtwork!.value >= .88 &&
              bestArtworkGap >= .04 &&
              material.orderGroupKey != null &&
              material.orderGroupKey == structuredOriginalTop?.orderGroupKey;
          final shouldPromoteArtwork =
              isBestArtwork &&
              (promotesNewArtwork || promotesWithinReviewedFamily);
          if (existing < 0 && (!admitsNewArtwork || !isBestArtwork)) {
            continue;
          }
          if (existing >= 0 && originalTop != null) {
            InventoryItemMatch? nativeCandidate;
            for (final candidate in original) {
              if (_same(candidate.name, material.name)) {
                nativeCandidate = candidate;
                break;
              }
            }
            if (nativeCandidate?.sharedArtwork == true &&
                nativeCandidate?.artworkKey?.isNotEmpty == true) {
              // The installed client says these items use the exact same icon.
              // App-owned copies can have different frames or backgrounds, but
              // that is not evidence that the storage slot contains a specific
              // member of the family. Preserve the native artwork identity so
              // fish, meat, blood, and other true shared-icon families remain
              // grouped and are resolved only with catalogue/order context.
              continue;
            }
            if (nativeCandidate != null &&
                originalTop.confidence - nativeCandidate.confidence >
                    _nativeRerankWindow) {
              // Source-resolution artwork is a tie-breaker for the helper's
              // genuinely close candidates, not a replacement for a much
              // stronger native match. This protects captures whose app icon
              // has different framing (for example Thuja versus Thornwood Sap)
              // while still correcting near-ties such as oil, flour, and dough.
              continue;
            }
          }
          // A high-resolution app template may sharpen a close native family,
          // but it must not promote a weaker unrelated helper candidate above
          // credible structured evidence. This previously let Herbal Juice
          // displace visually matched blood rows simply because its app icon
          // scored a few points higher. A genuinely missing app-owned identity
          // (for example Big Tiger Mushroom) is still admitted through the
          // stricter new-artwork score and margin gate above.
          if (existing >= 0 &&
              protectsStructuredOriginal &&
              material.orderGroupKey != structuredOriginalTop.orderGroupKey &&
              !shouldPromoteArtwork) {
            continue;
          }
          if (shouldPromoteArtwork &&
              (originalTop?.orderGroupKey == null ||
                  originalTop?.orderGroupKey == material.orderGroupKey)) {
            score = math
                .max(score, (nativeTopConfidence + .002).clamp(0.0, 1.0))
                .toDouble();
          }
          final next = InventoryItemMatch(
            name: material.name,
            confidence: score,
            sharedArtwork: material.sharedArtwork,
            grade: material.grade,
            itemId: material.itemId,
            artworkKey: material.template.artworkKey,
            orderGroupKey: material.orderGroupKey,
            qualityConflict: qualityConflict,
            nativeMaterialEligible: null,
            primaryIngredientUseCount: material.primaryIngredientUseCount,
            sourceVisualConfidence: score,
          );
          // Existing native identities were already compared above, with the
          // installed-client artwork preferred when available. The broad app
          // scan may add a genuinely missing planner identity, but must never
          // overwrite stronger native evidence. That unsafe overwrite caused
          // Acacia -> Elder, Fox Hide -> Raccoon Hide, and Maple/Ash -> Loopy.
          if (existing < 0) mapped.add(next);
        }
      }
    }
    mapped.removeWhere(
      (match) =>
          match.confidence < _credibleItemScore && !match.qualityConflict,
    );
    _appendReviewedOrderFamilyFallbacks(
      mapped,
      _supplementalMaterials,
      reviewedFallbackVisualScores,
    );
    mapped.sort((left, right) {
      final score = right.confidence.compareTo(left.confidence);
      if (score != 0) return score;
      final id = (right.itemId ?? -1).compareTo(left.itemId ?? -1);
      return id != 0 ? id : _compareNames(left.name, right.name);
    });
    return List<InventoryItemMatch>.unmodifiable(mapped);
  }

  List<_SupplementalMaterial> _visualMaterialsFor(
    Map<String, _AppIconTemplate> nativeArtworkTemplates,
    Map<String, _AppIconTemplate> appArtworkTemplates,
  ) {
    final materials = <_SupplementalMaterial>[
      for (final material in _supplementalMaterials)
        _SupplementalMaterial(
          name: material.name,
          itemId: material.itemId,
          grade: material.grade,
          orderGroupKey: material.orderGroupKey,
          primaryIngredientUseCount: material.primaryIngredientUseCount,
          template:
              appArtworkTemplates[material.template.artworkKey] ??
              material.template,
        )..sharedArtwork = material.sharedArtwork,
    ];
    // Search every authoritative installed-client icon that maps to an
    // admitted item, not only the paths returned by the 20 px helper
    // shortlist. Build this stable view once per screenshot rather than once
    // for every slot; no score, ordering, or eligibility decision changes.
    for (final entry in nativeArtworkTemplates.entries) {
      final family = _materialsByIcon[entry.key];
      if (family == null || family.isEmpty) continue;
      for (final material in family) {
        final supplemental = _SupplementalMaterial(
          name: material.name,
          itemId: material.itemId,
          grade: material.grade,
          orderGroupKey: material.orderGroupKey,
          primaryIngredientUseCount: material.primaryIngredientUseCount,
          template: entry.value,
        )..sharedArtwork = family.length > 1;
        materials.add(supplemental);
      }
    }
    return List<_SupplementalMaterial>.unmodifiable(materials);
  }

  List<_AppIconTemplate>? _resolvedAppTemplatesForName(
    String name,
    Map<String, _AppIconTemplate> appArtworkTemplates,
  ) {
    final templates = _templatesByName[_fold(name)];
    if (templates == null || templates.isEmpty || appArtworkTemplates.isEmpty) {
      return templates;
    }
    return <_AppIconTemplate>[
      for (final template in templates)
        appArtworkTemplates[template.artworkKey] ?? template,
    ];
  }

  void _appendReviewedOrderFamilyFallbacks(
    List<InventoryItemMatch> matches,
    List<_SupplementalMaterial> materials,
    Map<String, double> visualScores,
  ) {
    final nativeOrderFamily = matches
        .where(
          (match) =>
              match.artworkKey?.startsWith('icons/items/') == true &&
              _expandedOrderCandidateGroups.contains(match.orderGroupKey),
        )
        .fold<InventoryItemMatch?>(
          null,
          (best, match) =>
              best == null || match.confidence > best.confidence ? match : best,
        )
        ?.orderGroupKey;
    if (nativeOrderFamily == null) return;

    final existingNames = <String>{
      for (final match in matches) _fold(match.name),
    };
    for (final material in materials) {
      if (material.orderGroupKey != nativeOrderFamily ||
          !existingNames.add(_fold(material.name))) {
        continue;
      }
      // These candidates complete a reviewed order family for mouse correction
      // and bounded Auto Arrange. Their floor score deliberately cannot claim
      // visual certainty or outrank an observed native artwork family.
      matches.add(
        InventoryItemMatch(
          name: material.name,
          confidence: _credibleItemScore,
          sharedArtwork: material.sharedArtwork,
          grade: material.grade,
          itemId: material.itemId,
          artworkKey: material.template.artworkKey,
          orderGroupKey: material.orderGroupKey,
          nativeMaterialEligible: null,
          primaryIngredientUseCount: material.primaryIngredientUseCount,
          sourceVisualConfidence: visualScores[_fold(material.name)],
        ),
      );
    }
  }

  double? _bestTemplateScore(
    List<_InventoryIconFeature> sources,
    List<_AppIconTemplate>? templates,
  ) {
    if (templates == null || templates.isEmpty) return null;
    double? best;
    for (final template in templates) {
      final feature = template.feature;
      if (feature == null) continue;
      for (final source in sources) {
        final score = _compareIconFeatures(source, feature);
        if (best == null || score > best) best = score;
      }
    }
    return best;
  }

  double? _bestAlignedTemplateScore(
    List<_InventoryIconFeature> sources,
    List<_AppIconTemplate>? templates, {
    bool useScaleVariants = false,
  }) {
    if (templates == null || templates.isEmpty) return null;
    double? best;
    for (final template in templates) {
      final primary = template.feature;
      final features = useScaleVariants
          ? template.alignedFeatures
          : primary == null
          ? const <_InventoryIconFeature>[]
          : <_InventoryIconFeature>[primary];
      for (final feature in features) {
        for (final source in sources) {
          final score = _compareAlignedIconFeatures(source, feature);
          if (best == null || score > best) best = score;
        }
      }
    }
    return best;
  }
}

final class InventoryScreenshotResultSanitizer {
  const InventoryScreenshotResultSanitizer();

  InventoryScreenshotDraft sanitize({
    required Object? rawResult,
    required Uint8List screenshotBytes,
    required InventoryOcrMaterialCatalog catalog,
    Map<String, Uint8List> nativeArtworkBytes = const <String, Uint8List>{},
  }) => InventoryScreenshotPostProcessor(
    catalog: catalog,
    nativeArtworkBytes: nativeArtworkBytes,
  ).sanitize(rawResult: rawResult, screenshotBytes: screenshotBytes);

  InventoryScreenshotDraft _sanitizePrepared({
    required Object? rawResult,
    required Uint8List screenshotBytes,
    required InventoryOcrMaterialCatalog catalog,
    required Map<String, _AppIconTemplate> nativeArtworkTemplates,
    required Map<String, _AppIconTemplate> appArtworkTemplates,
    required List<_SupplementalMaterial> visualMaterials,
  }) {
    final root = _requiredMap(rawResult, 'recognition result');
    final fingerprint = _requiredString(root, 'imageFingerprint');
    if (!RegExp(r'^[a-fA-F0-9]{64}$').hasMatch(fingerprint)) {
      throw const FormatException(
        'Storage OCR returned an invalid image fingerprint.',
      );
    }
    final width = _requiredInt(root, 'width', minimum: 1, maximum: 7680);
    final height = _requiredInt(root, 'height', minimum: 1, maximum: 4320);
    if (width * height > 24000000) {
      throw const FormatException('Storage OCR returned an oversized image.');
    }
    final decodedImage = image.decodeImage(screenshotBytes);
    if (decodedImage == null ||
        decodedImage.width != width ||
        decodedImage.height != height) {
      throw const FormatException(
        'Storage OCR returned dimensions that do not match the image.',
      );
    }

    final grid = _requiredMap(root['grid'], 'grid');
    final columns = _requiredInt(grid, 'columns', minimum: 1, maximum: 16);
    final gridRows = _requiredInt(grid, 'rows', minimum: 1, maximum: 32);
    final gridConfidence = _requiredDouble(
      grid,
      'confidence',
      minimum: 0,
      maximum: 1,
    );
    final rawSlots = _requiredList(root, 'slots');
    if (rawSlots.length > inventoryScreenshotMaximumSlots) {
      throw const FormatException('Storage OCR returned too many slots.');
    }

    final visible = <InventoryScreenshotRow>[];
    final hidden = <InventoryScreenshotRow>[];
    final seenIds = <String>{};
    for (final rawSlot in rawSlots) {
      final slot = _requiredMap(rawSlot, 'slot');
      final slotId = _requiredString(slot, 'id');
      if (slotId.length > 80 || !seenIds.add(slotId)) {
        throw const FormatException(
          'Storage OCR returned duplicate or invalid slot IDs.',
        );
      }
      final row = _requiredInt(slot, 'row', minimum: 0, maximum: 31);
      final column = _requiredInt(slot, 'column', minimum: 0, maximum: 15);
      if (row >= gridRows || column >= columns) {
        throw const FormatException(
          'Storage OCR returned a slot outside the grid.',
        );
      }
      final box = _requiredMap(slot['box'], 'slot box');
      final left = _requiredInt(box, 'x', minimum: 0, maximum: width - 1);
      final top = _requiredInt(box, 'y', minimum: 0, maximum: height - 1);
      final cropWidth = _requiredInt(box, 'width', minimum: 1, maximum: width);
      final cropHeight = _requiredInt(
        box,
        'height',
        minimum: 1,
        maximum: height,
      );
      if (left + cropWidth > width || top + cropHeight > height) {
        throw const FormatException(
          'Storage OCR returned a crop outside the image.',
        );
      }

      final nativeCandidates = <InventoryOcrIconCandidate>[];
      for (final rawCandidate in _requiredList(
        slot,
        'iconCandidates',
      ).take(inventoryScreenshotMaximumIconCandidates)) {
        final candidate = _requiredMap(rawCandidate, 'icon candidate');
        final icon = _normalizeIconPath(_requiredString(candidate, 'icon'));
        if (icon == null) continue;
        nativeCandidates.add(
          InventoryOcrIconCandidate(
            icon: icon,
            score: _requiredDouble(candidate, 'score', minimum: 0, maximum: 1),
            materialEligible: _nullableBool(candidate['materialEligible']),
          ),
        );
      }

      final borderGrade = _nullableInt(
        slot['borderGrade'],
        minimum: 0,
        maximum: 9,
      );
      final borderConfidence = _requiredDouble(
        slot,
        'borderGradeConfidence',
        minimum: 0,
        maximum: 1,
      );
      final nativeMaterial = _nullableBool(slot['iconMaterialEligible']);
      final matches = catalog._matchesFor(
        nativeCandidates,
        borderGrade: borderGrade,
        borderConfidence: borderConfidence,
        sourceFeatures: _sourceIconFeatures(
          decodedImage,
          left: left,
          top: top,
          width: cropWidth,
          height: cropHeight,
        ),
        nativeArtworkTemplates: nativeArtworkTemplates,
        appArtworkTemplates: appArtworkTemplates,
        visualMaterials: visualMaterials,
        allowSupplemental: true,
        forceSupplemental: nativeMaterial == false,
      );
      final quantityText = _optionalString(
        slot['quantityText'],
        maximumLength: 32,
      );
      final confirmed = _nullableInt(
        slot['quantityValue'],
        minimum: 1,
        maximum: inventoryScreenshotMaximumQuantity,
      );
      final suggestedRaw = _nullableInt(
        slot['quantitySuggestedValue'],
        minimum: 1,
        maximum: inventoryScreenshotMaximumQuantity,
      );
      final approximate = _requiredBool(slot, 'quantityApproximate');
      final assumedOne = _requiredBool(slot, 'quantityAssumedOne');
      final quantityConfidence = _requiredDouble(
        slot,
        'quantityConfidence',
        minimum: 0,
        maximum: 1,
      );
      final quantityReadStatus = _optionalString(
        slot['quantityReadStatus'],
        maximumLength: 40,
      );
      final quantitySuggestionEvidence = _optionalString(
        slot['quantitySuggestionEvidence'],
        maximumLength: 40,
      );
      final quantitySuggestionConfidence = _nullableDouble(
        slot['quantitySuggestionConfidence'],
        minimum: 0,
        maximum: 1,
      );
      final parsedText = parseStrictStorageQuantity(quantityText);
      final suggested =
          confirmed == null &&
              !assumedOne &&
              suggestedRaw != null &&
              parsedText == suggestedRaw
          ? suggestedRaw
          : null;
      // The sealed recognizer can expose one complete, trusted token while
      // declining to mark it confirmed. Prefill that exact visible token for
      // review instead of hiding a useful read such as `1060` or `177.0K`.
      // `approximate` describes BDO's abbreviated K/M display, not an OCR
      // failure. Lower-confidence strict text remains visibly yellow so the
      // user can compare it without retyping the whole amount.
      final visibleStrictSuggestion =
          confirmed == null && suggested == null && !assumedOne
          ? parsedText
          : null;
      // Character recovery belongs in the native recognizer, where the model
      // probabilities and all calibrated image views are available. The app
      // only accepts a strict displayed token whose numeric suggestion agrees;
      // it never rewrites malformed OCR text by item-specific heuristics.
      final quantity = confirmed ?? suggested ?? visibleStrictSuggestion;
      final reviewSuggestion = suggested ?? visibleStrictSuggestion;
      final quantitySuggestionUncertain =
          assumedOne ||
          (confirmed == null &&
              reviewSuggestion != null &&
              !(quantityReadStatus == 'reviewLowConsensus' &&
                  quantitySuggestionEvidence == 'mainDirectAgreement' &&
                  quantitySuggestionConfidence != null &&
                  quantitySuggestionConfidence >= .50));

      final topMatch = matches.firstOrNull;
      final runnerUp = matches
          .skip(1)
          .firstWhereOrNull(
            (match) => !_same(match.name, topMatch?.name ?? ''),
          );
      final gap = topMatch == null
          ? 0.0
          : runnerUp == null
          ? 1.0
          : topMatch.confidence - runnerUp.confidence;
      final topHasCredibleSharedArtworkAlternative =
          topMatch != null &&
          topMatch.sharedArtwork &&
          matches
              .skip(1)
              .any(
                (match) =>
                    match.artworkKey == topMatch.artworkKey &&
                    !match.qualityConflict &&
                    match.confidence >= _credibleItemScore &&
                    topMatch.confidence - match.confidence < _automaticItemGap,
              );
      // A few genuine consumables in the sealed catalog are conservatively
      // marked non-material. If the proposed artwork itself has that flag,
      // the app's reviewed A/C/P recipe role is stronger evidence. A native
      // rejection paired with a different material artwork remains a hard
      // veto (for example a stuffed trophy resembling Elephant Hide).
      final nativeTop = nativeCandidates.firstOrNull;
      final reviewedOutputOverridesConservativeFlag =
          nativeMaterial == false &&
          nativeTop != null &&
          nativeTop.score >= _credibleItemScore &&
          nativeTop.materialEligible == false &&
          topMatch?.artworkKey == nativeTop.icon &&
          topMatch?.nativeMaterialEligible == false;
      final decisiveAppArtworkOverride =
          nativeMaterial == false &&
          topMatch != null &&
          topMatch.artworkKey?.startsWith('app:') == true &&
          !topHasCredibleSharedArtworkAlternative &&
          !topMatch.qualityConflict &&
          topMatch.confidence >= .88 &&
          gap >= .10;
      // A known non-planner top icon must not leak back into review merely
      // because one of the helper's lower visual candidates happens to map to
      // a planner material. App-owned artwork can still rescue a genuinely
      // missing planner identity, but only through the strict, decisive match
      // above (for example an app-only Big mushroom).
      final exactKnownOutOfScope =
          nativeTop != null &&
          nativeTop.score >= _credibleItemScore &&
          catalog._isKnownOutOfScopeIcon(nativeTop.icon) &&
          !decisiveAppArtworkOverride;
      final explicitTopCandidateRejection =
          nativeTop != null &&
          nativeTop.score >= _credibleItemScore &&
          nativeTop.materialEligible == false &&
          !reviewedOutputOverridesConservativeFlag &&
          !decisiveAppArtworkOverride;
      final nativeRejected =
          (nativeMaterial == false &&
              !reviewedOutputOverridesConservativeFlag &&
              !decisiveAppArtworkOverride) ||
          exactKnownOutOfScope ||
          explicitTopCandidateRejection;
      final relevance = nativeRejected
          ? InventoryOcrMaterialRelevance.irrelevant
          : nativeMaterial == true && matches.isNotEmpty
          ? InventoryOcrMaterialRelevance.relevant
          : InventoryOcrMaterialRelevance.uncertain;
      final selectedName =
          relevance != InventoryOcrMaterialRelevance.irrelevant &&
              topMatch != null &&
              topMatch.confidence >= _credibleItemScore
          ? topMatch.name
          : null;
      final itemSuggestionUncertain =
          selectedName != null &&
          (topHasCredibleSharedArtworkAlternative ||
              topMatch!.qualityConflict ||
              topMatch.confidence < _automaticItemScore ||
              gap < _automaticItemGap ||
              relevance != InventoryOcrMaterialRelevance.relevant);

      final reasons = <String>[];
      if (selectedName == null &&
          relevance != InventoryOcrMaterialRelevance.irrelevant) {
        reasons.add(
          matches.isEmpty
              ? 'Choose the item.'
              : topMatch?.qualityConflict == true
              ? 'The item quality border does not match; confirm it.'
              : topHasCredibleSharedArtworkAlternative
              ? 'Several planner items use this artwork.'
              : 'Confirm the suggested item.',
        );
      } else if (itemSuggestionUncertain) {
        reasons.add(
          topMatch.qualityConflict
              ? 'The item quality border does not match; check the highlighted suggestion.'
              : topHasCredibleSharedArtworkAlternative
              ? 'Several planner items use this artwork; check the highlighted suggestion.'
              : 'Check the highlighted item suggestion.',
        );
      }
      if (quantity == null) {
        reasons.add('Enter the visible amount.');
      } else if (quantitySuggestionUncertain) {
        reasons.add(
          assumedOne
              ? 'The amount was assumed to be 1; check it.'
              : 'Check the highlighted amount.',
        );
      }
      // A decisive non-material result is not an inventory row. Keep the
      // sealed recognizer's classification authoritative instead of inviting
      // a visually similar material (for example Elephant Hide) to be saved.
      if (nativeRejected) continue;

      final leftContext = (cropWidth * .24).round().clamp(0, left).toInt();
      final preview = image.copyCrop(
        decodedImage,
        x: left - leftContext,
        y: top,
        width: cropWidth + leftContext,
        height: cropHeight,
      );
      final mapped = InventoryScreenshotRow(
        id: '$fingerprint:$slotId',
        slotId: slotId,
        row: row,
        column: column,
        crop: InventoryScreenshotRect(
          left: left,
          top: top,
          width: cropWidth,
          height: cropHeight,
        ),
        quantityText: quantityText,
        quantity: quantity,
        quantitySuggested: reviewSuggestion,
        quantityApproximate: approximate,
        quantityAssumedOne: assumedOne,
        quantityConfidence: quantityConfidence,
        quantitySuggestionUncertain: quantitySuggestionUncertain,
        matches: matches,
        selectedName: selectedName,
        relevance: relevance,
        reviewRequired: reasons.isNotEmpty,
        itemSuggestionUncertain: itemSuggestionUncertain,
        reviewReasons: List<String>.unmodifiable(reasons),
        // Review thumbnails are transient and already tiny. Fast lossless PNG
        // compression preserves every pixel while avoiding expensive default
        // compression work across a full 90-slot storage.
        previewPng: Uint8List.fromList(image.encodePng(preview, level: 1)),
      );
      (mapped.hiddenByDefault ? hidden : visible).add(mapped);
    }

    int byGridPosition(
      InventoryScreenshotRow left,
      InventoryScreenshotRow right,
    ) {
      final rowOrder = left.row.compareTo(right.row);
      return rowOrder != 0 ? rowOrder : left.column.compareTo(right.column);
    }

    visible.sort(byGridPosition);
    hidden.sort(byGridPosition);
    return InventoryScreenshotDraft(
      imageFingerprint: fingerprint.toLowerCase(),
      sourceWidth: width,
      sourceHeight: height,
      gridColumns: columns,
      gridRows: gridRows,
      gridConfidence: gridConfidence,
      rows: List<InventoryScreenshotRow>.unmodifiable(visible),
      hiddenRows: List<InventoryScreenshotRow>.unmodifiable(hidden),
      warnings: List<String>.unmodifiable(
        _requiredList(root, 'warnings')
            .whereType<String>()
            .map((warning) => warning.trim())
            .where((warning) => warning.isNotEmpty)
            .take(12),
      ),
    );
  }
}

/// Build-time artifact containing the exact normalized RGB tiles used by the
/// source-resolution inventory matcher.
///
/// Keeping these pixels in one file replaces thousands of small WebP/data-URI
/// decodes at first use. It does not change any matching score or threshold.
final class InventoryOcrTemplateCacheArtifact {
  const InventoryOcrTemplateCacheArtifact({
    required this.indexJson,
    required this.rgbBytes,
  });

  final String indexJson;
  final Uint8List rgbBytes;
}

final class InventoryOcrPreprocessedTemplateCache {
  InventoryOcrPreprocessedTemplateCache._(this._rgbBytes, this._templates);

  factory InventoryOcrPreprocessedTemplateCache.decode({
    required String indexJson,
    required Uint8List rgbBytes,
  }) {
    final decoded = jsonDecode(indexJson);
    if (decoded is! Map<String, Object?> ||
        decoded['schema'] != 1 ||
        decoded['extent'] != _refinedIconExtent ||
        decoded['channels'] != 3) {
      throw const FormatException(
        'The inventory OCR artwork cache has an unsupported format.',
      );
    }
    final expectedHash = decoded['rgbSha256'];
    if (expectedHash is! String ||
        expectedHash != sha256.convert(rgbBytes).toString()) {
      throw const FormatException(
        'The inventory OCR artwork cache failed verification.',
      );
    }
    final rawEntries = decoded['entries'];
    if (rawEntries is! List<Object?>) {
      throw const FormatException(
        'The inventory OCR artwork cache index is invalid.',
      );
    }
    const tileBytes = _refinedIconExtent * _refinedIconExtent * 3;
    final templates = <String, _AppIconTemplate>{};
    for (final rawEntry in rawEntries) {
      if (rawEntry is! Map<String, Object?>) {
        throw const FormatException(
          'The inventory OCR artwork cache entry is invalid.',
        );
      }
      final key = rawEntry['key'];
      final firstTile = rawEntry['firstTile'];
      final tileCount = rawEntry['tileCount'];
      if (key is! String ||
          key.isEmpty ||
          key.length > 160 ||
          firstTile is! int ||
          firstTile < 0 ||
          tileCount is! int ||
          tileCount < 1 ||
          tileCount > 3 ||
          templates.containsKey(key)) {
        throw const FormatException(
          'The inventory OCR artwork cache entry is invalid.',
        );
      }
      final firstByte = firstTile * tileBytes;
      final lastByte = (firstTile + tileCount) * tileBytes;
      if (lastByte > rgbBytes.length) {
        throw const FormatException(
          'The inventory OCR artwork cache is truncated.',
        );
      }
      templates[key] = _AppIconTemplate.fromNormalizedRgbTiles(key, <Uint8List>[
        for (var offset = firstByte; offset < lastByte; offset += tileBytes)
          Uint8List.sublistView(rgbBytes, offset, offset + tileBytes),
      ]);
    }
    if (templates.isEmpty || rgbBytes.length % tileBytes != 0) {
      throw const FormatException(
        'The inventory OCR artwork cache is empty or misaligned.',
      );
    }
    return InventoryOcrPreprocessedTemplateCache._(
      rgbBytes,
      Map<String, _AppIconTemplate>.unmodifiable(templates),
    );
  }

  // Retain the backing buffer for the lifetime of every zero-copy tile view.
  // ignore: unused_field
  final Uint8List _rgbBytes;
  final Map<String, _AppIconTemplate> _templates;

  _AppIconTemplate? _templateFor(String artworkKey) => _templates[artworkKey];
}

InventoryOcrTemplateCacheArtifact buildInventoryOcrTemplateCache({
  required InventoryOcrMaterialCatalog catalog,
  required Map<String, Uint8List> nativeArtworkBytes,
}) {
  final templates = <String, _AppIconTemplate>{
    for (final entry in nativeArtworkBytes.entries)
      entry.key: _AppIconTemplate.fromEncodedBytes(entry.key, entry.value),
  };
  for (final family in catalog._templatesByName.values) {
    for (final template in family) {
      if (template.isUsable) {
        templates.putIfAbsent(template.artworkKey, () => template);
      }
    }
  }
  final keys = templates.keys.toList(growable: false)..sort();
  final output = BytesBuilder(copy: false);
  final entries = <Map<String, Object>>[];
  var nextTile = 0;
  for (final key in keys) {
    final template = templates[key]!;
    final tiles = template._normalizedRgbTilesForCache();
    if (tiles.isEmpty) continue;
    entries.add(<String, Object>{
      'key': key,
      'firstTile': nextTile,
      'tileCount': tiles.length,
    });
    for (final tile in tiles) {
      output.add(tile);
      nextTile += 1;
    }
  }
  final rgbBytes = output.takeBytes();
  if (entries.isEmpty) {
    throw const FormatException(
      'No inventory OCR artwork could be normalized.',
    );
  }
  return InventoryOcrTemplateCacheArtifact(
    indexJson: jsonEncode(<String, Object>{
      'schema': 1,
      'extent': _refinedIconExtent,
      'channels': 3,
      'tileCount': nextTile,
      'rgbSha256': sha256.convert(rgbBytes).toString(),
      'entries': entries,
    }),
    rgbBytes: rgbBytes,
  );
}

/// Retains decoded icon templates and their pixel features between storage
/// screenshots. Production owns one of these inside its background isolate;
/// the one-shot sanitizer above remains available for focused tests.
final class InventoryScreenshotPostProcessor {
  InventoryScreenshotPostProcessor({
    required this._catalog,
    required Map<String, Uint8List> nativeArtworkBytes,
    InventoryOcrPreprocessedTemplateCache? preprocessedTemplateCache,
  }) : _nativeArtworkTemplates = <String, _AppIconTemplate>{
         for (final icon in _catalog.nativeArtworkPaths)
           if (preprocessedTemplateCache?._templateFor(icon) != null)
             icon: preprocessedTemplateCache!._templateFor(icon)!,
         for (final entry in nativeArtworkBytes.entries)
           if (preprocessedTemplateCache?._templateFor(entry.key) == null)
             entry.key: _AppIconTemplate.fromEncodedBytes(
               entry.key,
               entry.value,
             ),
       },
       _appArtworkTemplates = <String, _AppIconTemplate>{
         if (preprocessedTemplateCache != null)
           for (final entry in preprocessedTemplateCache._templates.entries)
             if (entry.key.startsWith('app:')) entry.key: entry.value,
       } {
    _visualMaterials = _catalog._visualMaterialsFor(
      _nativeArtworkTemplates,
      _appArtworkTemplates,
    );
  }

  final InventoryOcrMaterialCatalog _catalog;
  final Map<String, _AppIconTemplate> _nativeArtworkTemplates;
  final Map<String, _AppIconTemplate> _appArtworkTemplates;
  late final List<_SupplementalMaterial> _visualMaterials;

  /// Builds the same first-pass feature planes recognition would build on the
  /// first screenshot, but does so ahead of time in the background worker.
  /// No matcher result, threshold, or ordering is changed.
  void prewarm() {
    final seen = <_AppIconTemplate>{};
    for (final template in _nativeArtworkTemplates.values) {
      if (seen.add(template)) template.feature;
    }
    for (final template in _appArtworkTemplates.values) {
      if (seen.add(template)) template.feature;
    }
    for (final material in _visualMaterials) {
      if (seen.add(material.template)) material.template.feature;
    }
  }

  InventoryScreenshotDraft sanitize({
    required Object? rawResult,
    required Uint8List screenshotBytes,
  }) => const InventoryScreenshotResultSanitizer()._sanitizePrepared(
    rawResult: rawResult,
    screenshotBytes: screenshotBytes,
    catalog: _catalog,
    nativeArtworkTemplates: _nativeArtworkTemplates,
    appArtworkTemplates: _appArtworkTemplates,
    visualMaterials: _visualMaterials,
  );
}

int? parseStrictStorageQuantity(String value) {
  final normalized = value.trim();
  if (normalized.isEmpty) return null;
  if (RegExp(r'^[1-9]\d{0,4}$').hasMatch(normalized)) {
    return int.tryParse(normalized);
  }
  if (RegExp(r'^[1-9]\d{0,2}(?:,\d{3})+$').hasMatch(normalized)) {
    return int.tryParse(normalized.replaceAll(',', ''));
  }
  final abbreviated = RegExp(
    r'^([1-9]\d{0,2})\.(\d)([KM])$',
  ).firstMatch(normalized);
  if (abbreviated == null) return null;
  final whole = int.parse(abbreviated.group(1)!);
  final fraction = int.parse(abbreviated.group(2)!);
  final scale = abbreviated.group(3) == 'M' ? 1000000 : 1000;
  final parsed = whole * scale + fraction * (scale ~/ 10);
  return parsed <= inventoryScreenshotMaximumQuantity ? parsed : null;
}

final class _OcrMaterial {
  const _OcrMaterial({
    required this.name,
    required this.icon,
    required this.grade,
    required this.itemId,
    required this.orderGroupKey,
    required this.primaryIngredientUseCount,
  });

  final String name;
  final String icon;
  final int? grade;
  final int? itemId;
  final String? orderGroupKey;
  final int primaryIngredientUseCount;
}

final class _SupplementalMaterial {
  _SupplementalMaterial({
    required this.name,
    required this.itemId,
    required this.grade,
    required this.orderGroupKey,
    required this.primaryIngredientUseCount,
    required this.template,
  });

  final String name;
  final int? itemId;
  final int? grade;
  final String? orderGroupKey;
  final int primaryIngredientUseCount;
  final _AppIconTemplate template;
  bool sharedArtwork = false;
}

final class _AppIconTemplate {
  _AppIconTemplate._(
    this.artworkKey,
    this._dataUri,
    this._encodedBytes,
    this._normalizedRgbTiles,
    this._useAlignedScaleVariants,
  );

  factory _AppIconTemplate.fromDataUri(String dataUri) {
    if (!dataUri.startsWith('data:image/') || !dataUri.contains(';base64,')) {
      return _AppIconTemplate._('', null, null, null, false);
    }
    return _AppIconTemplate._(
      'app:${sha256.convert(utf8.encode(dataUri))}',
      dataUri,
      null,
      null,
      true,
    );
  }

  factory _AppIconTemplate.fromEncodedBytes(
    String artworkKey,
    Uint8List encodedBytes,
  ) => _AppIconTemplate._(
    artworkKey,
    null,
    Uint8List.fromList(encodedBytes),
    null,
    false,
  );

  factory _AppIconTemplate.fromNormalizedRgbTiles(
    String artworkKey,
    List<Uint8List> tiles,
  ) => _AppIconTemplate._(
    artworkKey,
    null,
    null,
    List<Uint8List>.unmodifiable(tiles),
    tiles.length > 1,
  );

  final String artworkKey;
  final String? _dataUri;
  final Uint8List? _encodedBytes;
  final List<Uint8List>? _normalizedRgbTiles;
  final bool _useAlignedScaleVariants;
  late final List<_InventoryIconFeature> alignedFeatures =
      _normalizedRgbTiles == null
      ? _decodeTemplateFeaturesWithInsets(
          _encodedBytes ??
              (_dataUri == null ? null : _decodeImageDataUri(_dataUri)),
          includeInsets: _useAlignedScaleVariants,
        )
      : <_InventoryIconFeature>[
          for (final tile in _normalizedRgbTiles)
            _extractIconFeatureFromRgb(tile),
        ];
  _InventoryIconFeature? get feature => alignedFeatures.firstOrNull;

  List<Uint8List> _normalizedRgbTilesForCache() {
    final cached = _normalizedRgbTiles;
    if (cached != null) return cached;
    return _decodeTemplateRgbTilesWithInsets(
      _encodedBytes ??
          (_dataUri == null ? null : _decodeImageDataUri(_dataUri)),
      includeInsets: _useAlignedScaleVariants,
    );
  }

  bool get isUsable =>
      artworkKey.isNotEmpty &&
      (_dataUri != null ||
          _encodedBytes != null ||
          _normalizedRgbTiles != null);
}

_InventoryIconFeature? _decodeTemplateFeature(Uint8List? bytes) {
  return _decodeTemplateFeatures(bytes).firstOrNull;
}

List<_InventoryIconFeature> _decodeTemplateFeatures(Uint8List? bytes) {
  return _decodeTemplateFeaturesWithInsets(bytes, includeInsets: true);
}

List<_InventoryIconFeature> _decodeTemplateFeaturesWithInsets(
  Uint8List? bytes, {
  required bool includeInsets,
}) {
  if (bytes == null) return const <_InventoryIconFeature>[];
  return <_InventoryIconFeature>[
    for (final tile in _decodeTemplateRgbTilesWithInsets(
      bytes,
      includeInsets: includeInsets,
    ))
      _extractIconFeatureFromRgb(tile),
  ];
}

List<Uint8List> _decodeTemplateRgbTilesWithInsets(
  Uint8List? bytes, {
  required bool includeInsets,
}) {
  if (bytes == null) return const <Uint8List>[];
  final decoded = image.decodeImage(bytes);
  if (decoded == null || decoded.width < 4 || decoded.height < 4) {
    return const <Uint8List>[];
  }
  final shortestSide = math.min(decoded.width, decoded.height);
  final insets = <int>{
    0,
    if (includeInsets && shortestSide >= 24) (shortestSide * .0625).round(),
    if (includeInsets && shortestSide >= 32) (shortestSide * .095).round(),
  }.where((inset) => shortestSide - inset * 2 >= 4);
  return <Uint8List>[
    for (final inset in insets)
      _inventoryRgbFromImage(_compositeTemplateCrop(decoded, inset: inset)),
  ];
}

image.Image _compositeTemplateCrop(image.Image decoded, {required int inset}) {
  final canvas = image.Image(
    width: _refinedIconExtent,
    height: _refinedIconExtent,
    numChannels: 4,
  );
  image.fill(
    canvas,
    color: image.ColorRgba8(
      _iconBackgroundRed,
      _iconBackgroundGreen,
      _iconBackgroundBlue,
      255,
    ),
  );
  final cropped = inset == 0
      ? decoded
      : image.copyCrop(
          decoded,
          x: inset,
          y: inset,
          width: decoded.width - inset * 2,
          height: decoded.height - inset * 2,
        );
  image.compositeImage(
    canvas,
    image.copyResize(
      cropped,
      width: _refinedIconExtent,
      height: _refinedIconExtent,
      interpolation: image.Interpolation.cubic,
    ),
  );
  return canvas;
}

/// Deterministic source-resolution artwork comparison used by regression
/// tests for visually similar inventory icons.
///
/// Item recognition still applies catalogue, quality-border, material, and
/// confidence gates around these raw visual scores.
({double pixel, double aligned})? compareInventoryOcrArtworkForTesting(
  Uint8List left,
  Uint8List right,
) {
  final leftFeature = _decodeTemplateFeature(left);
  final rightFeature = _decodeTemplateFeature(right);
  if (leftFeature == null || rightFeature == null) return null;
  return (
    pixel: _compareIconFeatures(leftFeature, rightFeature),
    aligned: _compareAlignedIconFeatures(leftFeature, rightFeature),
  );
}

final class _InventoryIconFeature {
  const _InventoryIconFeature({
    required this.centeredRgb,
    required this.centeredLuminance,
    required this.softForegroundMask,
    required this.horizontalGradient,
    required this.verticalGradient,
    required this.centeredLabA,
    required this.centeredLabB,
    required this.luminance,
    required this.gradient,
    required this.coarseLuminance,
    required this.chroma,
    required this.spatialChroma,
  });

  final Int16List centeredRgb;
  final Int16List centeredLuminance;
  final Uint8List softForegroundMask;
  final Int16List horizontalGradient;
  final Int16List verticalGradient;
  final Int16List centeredLabA;
  final Int16List centeredLabB;
  final Float32List luminance;
  final Float32List gradient;
  final Float32List coarseLuminance;
  final Float32List? chroma;
  final Float32List spatialChroma;
}

const int _refinedIconExtent = 40;
const int _refinedComparedRows = 28;
const int _iconBackgroundRed = 22;
const int _iconBackgroundGreen = 23;
const int _iconBackgroundBlue = 27;

final Float64List _softMaskUnit = Float64List.fromList(
  List<double>.generate(256, (value) => value / 255, growable: false),
);
final ({Float64List intersection, Float64List union, Float64List minimum})
_softMaskPairs = _buildSoftMaskPairs();
final List<Int32List> _alignedPixelPairs = _buildAlignedPixelPairs();

({Float64List intersection, Float64List union, Float64List minimum})
_buildSoftMaskPairs() {
  final intersection = Float64List(256 * 256);
  final union = Float64List(256 * 256);
  final minimum = Float64List(256 * 256);
  for (var source = 0; source < 256; source += 1) {
    final sourceValue = source / 255;
    for (var template = 0; template < 256; template += 1) {
      final templateValue = template / 255;
      final index = (source << 8) | template;
      intersection[index] = math.sqrt(sourceValue * templateValue);
      union[index] = math.max(sourceValue, templateValue);
      minimum[index] = math.min(sourceValue, templateValue);
    }
  }
  return (intersection: intersection, union: union, minimum: minimum);
}

List<Int32List> _buildAlignedPixelPairs() {
  final result = <Int32List>[];
  for (var shiftY = -4; shiftY <= 4; shiftY += 1) {
    for (var shiftX = -4; shiftX <= 4; shiftX += 1) {
      final pairs = <int>[];
      for (
        var templateY = 2;
        templateY < _refinedComparedRows - 1;
        templateY += 1
      ) {
        final sourceY = templateY + shiftY;
        if (sourceY < 2 || sourceY >= _refinedComparedRows - 1) continue;
        for (
          var templateX = 2;
          templateX < _refinedIconExtent - 2;
          templateX += 1
        ) {
          final sourceX = templateX + shiftX;
          if (sourceX < 2 || sourceX >= _refinedIconExtent - 2) continue;
          pairs
            ..add(templateY * _refinedIconExtent + templateX)
            ..add(sourceY * _refinedIconExtent + sourceX);
        }
      }
      result.add(Int32List.fromList(pairs));
    }
  }
  return List<Int32List>.unmodifiable(result);
}

// A 6-bit/channel CIE Lab lookup keeps aligned perceptual-colour comparisons
// cheap enough for a full storage. Values are stored at quarter-Lab units in
// signed 16-bit planes; raw RGB remains a separate signal.
final ({Int16List a, Int16List b}) _labChromaLookup = _buildLabChromaLookup();

Map<String, int> _catalogItemIds(CatalogSnapshot catalog) {
  final result = <String, int>{};
  // `marketIds` also contains pricing proxies (an ingredient may intentionally
  // use a different market listing), so it is not an identity map. Only the
  // exact name/ID table and explicit recipe IDs are safe for OCR ordering and
  // canonical aliases.
  final rawMarketIds = catalog.supportingData['marketNameIds'];
  if (rawMarketIds is Map<Object?, Object?>) {
    for (final entry in rawMarketIds.entries) {
      final name = entry.key;
      final rawId = entry.value;
      if (name is! String) continue;
      final itemId = switch (rawId) {
        final int value => value,
        final num value when value.isFinite && value == value.roundToDouble() =>
          value.toInt(),
        final String value => int.tryParse(value.trim()),
        _ => null,
      };
      if (itemId != null) result.putIfAbsent(_fold(name), () => itemId);
    }
  }
  for (final mode in CraftMode.values) {
    for (final recipe in catalog.forMode(mode).items.values) {
      final itemId = int.tryParse(recipe.marketId ?? '');
      if (itemId != null) {
        result[_fold(recipe.name)] = itemId;
      }
    }
  }
  return Map<String, int>.unmodifiable(result);
}

Map<String, List<String>> _catalogIconDataUris(CatalogSnapshot catalog) {
  final collected = <String, List<String>>{};
  for (final mode in CraftMode.values) {
    for (final entry in catalog.forMode(mode).iconDataUris.entries) {
      final dataUri = entry.value.trim();
      if (dataUri.isEmpty) continue;
      final values = collected.putIfAbsent(_fold(entry.key), () => <String>[]);
      if (!values.contains(dataUri)) values.add(dataUri);
    }
  }

  final result = <String, List<String>>{};
  for (final entry in collected.entries) {
    var bestArea = -1;
    final preferred = <String>[];
    for (final dataUri in entry.value) {
      final bytes = _decodeImageDataUri(dataUri);
      final header = bytes == null ? null : _decodeImageHeader(bytes);
      if (header == null || header.width <= 0 || header.height <= 0) continue;
      final area = header.width * header.height;
      if (area > bestArea) {
        bestArea = area;
        preferred
          ..clear()
          ..add(dataUri);
      } else if (area == bestArea) {
        preferred.add(dataUri);
      }
    }
    if (preferred.isNotEmpty) result[entry.key] = preferred;
  }
  return result;
}

Set<String> _eligibleHelperIconPaths(String? source) {
  if (source == null || source.trim().isEmpty) return const <String>{};
  final decoded = jsonDecode(source);
  if (decoded is! Map<String, Object?>) {
    throw const FormatException('The storage OCR icon index is invalid.');
  }
  final rawIcons = decoded['icons'];
  if (rawIcons is! List<Object?>) {
    throw const FormatException('The storage OCR icon index has no icons.');
  }
  final result = <String>{};
  for (final rawIcon in rawIcons) {
    if (rawIcon is! Map<String, Object?> ||
        rawIcon['materialEligible'] != true ||
        rawIcon['icon'] is! String) {
      continue;
    }
    final icon = _normalizeIconPath(rawIcon['icon']! as String);
    if (icon != null) result.add(icon);
  }
  return Set<String>.unmodifiable(result);
}

({Set<int> inputs, Set<int> outputs}) _lifeSkillRecipeRoles(
  Object? rawRecipes,
) {
  if (rawRecipes is! List<Object?>) {
    return (inputs: const <int>{}, outputs: const <int>{});
  }
  const types = <String>{
    'ALCHEMY',
    'COOK',
    'DRY',
    'FIREWOOD',
    'GRIND',
    'HEAT',
    'SHAKE',
    'SIMPLE_ALCHEMY',
    'SIMPLE_COOK',
    'THINNING',
  };
  final inputs = <int>{};
  final outputs = <int>{};
  for (final rawRecipe in rawRecipes) {
    if (rawRecipe is! Map<String, Object?> ||
        !types.contains(rawRecipe['type'])) {
      continue;
    }
    final output = rawRecipe['outputId'];
    if (output is num && output.isFinite && output == output.roundToDouble()) {
      outputs.add(output.toInt());
    }
    final rawInputs = rawRecipe['inputs'];
    if (rawInputs is! List<Object?>) continue;
    for (final rawInput in rawInputs) {
      if (rawInput is! Map<String, Object?>) continue;
      final itemId = rawInput['itemId'];
      if (itemId is num &&
          itemId.isFinite &&
          itemId == itemId.roundToDouble()) {
        inputs.add(itemId.toInt());
      }
    }
  }
  return (
    inputs: Set<int>.unmodifiable(inputs),
    outputs: Set<int>.unmodifiable(outputs),
  );
}

bool _declaresLifeSkillIngredient(Object? rawDescription) {
  if (rawDescription is! String) return false;
  final description = _fold(rawDescription);
  return description.contains('used in alchemy or cooking') ||
      description.contains('used as an alchemy and cooking ingredient') ||
      description.contains('used as a cooking ingredient') ||
      description.contains('used as an alchemy ingredient') ||
      description.contains('a cooking ingredient') ||
      description.contains('an alchemy ingredient');
}

bool _declaresLifeSkillByproduct(Object? rawDescription) {
  if (rawDescription is! String) return false;
  final description = _fold(rawDescription);
  return description.contains('byproduct of alchemy') ||
      description.contains('by-product of alchemy') ||
      description.contains('byproduct of cooking') ||
      description.contains('by-product of cooking');
}

Uint8List? _decodeImageDataUri(String value) {
  final separator = value.indexOf(',');
  if (separator <= 0 ||
      !value.substring(0, separator).toLowerCase().contains(';base64')) {
    return null;
  }
  try {
    return base64Decode(value.substring(separator + 1));
  } on FormatException {
    return null;
  }
}

image.DecodeInfo? _decodeImageHeader(Uint8List bytes) {
  try {
    return image.findDecoderForData(bytes)?.startDecode(bytes);
  } catch (_) {
    return null;
  }
}

List<_InventoryIconFeature> _sourceIconFeatures(
  image.Image screenshot, {
  required int left,
  required int top,
  required int width,
  required int height,
}) {
  // Keep the exact native slot crop as well as two border-free zooms. Some
  // current-client assets are transparent 44 px icons while others are 64 px
  // framed catalogue images. Dropping the untrimmed view forced the latter to
  // compare against an already-zoomed source and could make a wrong sibling
  // look closer purely because its scale happened to match.
  final insets = width > 12 && height > 12
      ? const <int>[0, 2, 4]
      : const <int>[0];
  return <_InventoryIconFeature>[
    for (final inset in insets)
      _extractIconFeature(
        image.copyResize(
          image.copyCrop(
            screenshot,
            x: left + inset,
            y: top + inset,
            width: width - inset * 2,
            height: height - inset * 2,
          ),
          width: _refinedIconExtent,
          height: _refinedIconExtent,
          interpolation: image.Interpolation.cubic,
        ),
      ),
  ];
}

_InventoryIconFeature _extractIconFeature(image.Image source) {
  return _extractIconFeatureFromRgb(_inventoryRgbFromImage(source));
}

Uint8List _inventoryRgbFromImage(image.Image source) {
  final rgb = Uint8List(_refinedIconExtent * _refinedIconExtent * 3);
  for (var y = 0; y < _refinedIconExtent; y += 1) {
    for (var x = 0; x < _refinedIconExtent; x += 1) {
      final pixel = source.getPixel(x, y);
      final offset = (y * _refinedIconExtent + x) * 3;
      rgb[offset] = pixel.r.toInt().clamp(0, 255).toInt();
      rgb[offset + 1] = pixel.g.toInt().clamp(0, 255).toInt();
      rgb[offset + 2] = pixel.b.toInt().clamp(0, 255).toInt();
    }
  }
  return rgb;
}

_InventoryIconFeature _extractIconFeatureFromRgb(Uint8List rgb) {
  if (rgb.length != _refinedIconExtent * _refinedIconExtent * 3) {
    throw const FormatException('The inventory OCR template tile is invalid.');
  }
  final pixelLuminance = Uint8List(_refinedIconExtent * _refinedIconExtent);
  final labA = Int16List(pixelLuminance.length);
  final labB = Int16List(pixelLuminance.length);
  for (var index = 0; index < pixelLuminance.length; index += 1) {
    final offset = index * 3;
    pixelLuminance[index] = _iconLuminance(rgb, offset);
    final lab = _lookupLabChroma(rgb[offset], rgb[offset + 1], rgb[offset + 2]);
    labA[index] = lab.$1;
    labB[index] = lab.$2;
  }
  final background = _estimateIconBackground(rgb);
  final backgroundLab = _lookupLabChroma(
    background.red,
    background.green,
    background.blue,
  );
  final centeredRgb = Int16List(rgb.length);
  final centeredLuminance = Int16List(pixelLuminance.length);
  final softForegroundMask = Uint8List(pixelLuminance.length);
  final horizontalGradient = Int16List(pixelLuminance.length);
  final verticalGradient = Int16List(pixelLuminance.length);
  final centeredLabA = Int16List(pixelLuminance.length);
  final centeredLabB = Int16List(pixelLuminance.length);
  for (var y = 0; y < _refinedIconExtent; y += 1) {
    for (var x = 0; x < _refinedIconExtent; x += 1) {
      final index = y * _refinedIconExtent + x;
      final centered = pixelLuminance[index] - background.luminance;
      centeredLuminance[index] = centered;
      final offset = index * 3;
      final redDelta = rgb[offset] - background.red;
      final greenDelta = rgb[offset + 1] - background.green;
      final blueDelta = rgb[offset + 2] - background.blue;
      centeredRgb[offset] = redDelta;
      centeredRgb[offset + 1] = greenDelta;
      centeredRgb[offset + 2] = blueDelta;
      final rgbDistance = math.sqrt(
        redDelta * redDelta + greenDelta * greenDelta + blueDelta * blueDelta,
      );
      final labADelta = labA[index] - backgroundLab.$1;
      final labBDelta = labB[index] - backgroundLab.$2;
      centeredLabA[index] = labADelta;
      centeredLabB[index] = labBDelta;
      final labChromaDistance =
          math.sqrt(labADelta * labADelta + labBDelta * labBDelta) / 4;
      final foregroundStrength = math.max(
        centered.abs() / 64,
        math.max(rgbDistance / 96, labChromaDistance / 48),
      );
      final soft = (foregroundStrength.clamp(0.0, 1.0) * 255).round();
      softForegroundMask[index] = soft;
      if (x > 0 && x < _refinedIconExtent - 1) {
        horizontalGradient[index] =
            pixelLuminance[index + 1] - pixelLuminance[index - 1];
      }
      if (y > 0 && y < _refinedIconExtent - 1) {
        verticalGradient[index] =
            pixelLuminance[index + _refinedIconExtent] -
            pixelLuminance[index - _refinedIconExtent];
      }
    }
  }
  final structural = _extractIconStructuralFeatures(pixelLuminance);
  return _InventoryIconFeature(
    centeredRgb: centeredRgb,
    centeredLuminance: centeredLuminance,
    softForegroundMask: softForegroundMask,
    horizontalGradient: horizontalGradient,
    verticalGradient: verticalGradient,
    centeredLabA: centeredLabA,
    centeredLabB: centeredLabB,
    luminance: structural.luminance,
    gradient: structural.gradient,
    coarseLuminance: _extractCoarseLuminance(centeredLuminance),
    chroma: _extractBrightChroma(rgb),
    spatialChroma: _extractSpatialChroma(rgb),
  );
}

Float32List _extractCoarseLuminance(Int16List centeredLuminance) {
  const columns = 8;
  const rows = 6;
  final sums = List<double>.filled(columns * rows, 0);
  final counts = List<int>.filled(columns * rows, 0);
  for (var y = 1; y < _refinedComparedRows; y += 1) {
    final cellY = ((y - 1) * rows ~/ (_refinedComparedRows - 1)).clamp(
      0,
      rows - 1,
    );
    for (var x = 1; x < _refinedIconExtent - 1; x += 1) {
      final cellX = ((x - 1) * columns ~/ (_refinedIconExtent - 2)).clamp(
        0,
        columns - 1,
      );
      final cell = cellY * columns + cellX;
      sums[cell] += centeredLuminance[y * _refinedIconExtent + x];
      counts[cell] += 1;
    }
  }
  for (var index = 0; index < sums.length; index += 1) {
    final count = counts[index];
    if (count > 0) sums[index] /= count;
  }
  return _normalizeZeroMean(sums);
}

double _compareCoarseIconShape(
  _InventoryIconFeature source,
  _InventoryIconFeature template,
) =>
    _compareNormalizedVectors(source.coarseLuminance, template.coarseLuminance);

double _compareCoarseIconColor(
  _InventoryIconFeature source,
  _InventoryIconFeature template,
) => _compareNormalizedVectors(source.spatialChroma, template.spatialChroma);

({int red, int green, int blue, int luminance}) _estimateIconBackground(
  Uint8List rgb,
) {
  final red = <int>[];
  final green = <int>[];
  final blue = <int>[];
  for (var y = 0; y < 4; y += 1) {
    for (var x = 0; x < _refinedIconExtent; x += 1) {
      if (x >= 3 && x < _refinedIconExtent - 3) continue;
      final offset = (y * _refinedIconExtent + x) * 3;
      red.add(rgb[offset]);
      green.add(rgb[offset + 1]);
      blue.add(rgb[offset + 2]);
    }
  }
  red.sort();
  green.sort();
  blue.sort();
  final backgroundRed = red.isEmpty ? _iconBackgroundRed : red[red.length ~/ 2];
  final backgroundGreen = green.isEmpty
      ? _iconBackgroundGreen
      : green[green.length ~/ 2];
  final backgroundBlue = blue.isEmpty
      ? _iconBackgroundBlue
      : blue[blue.length ~/ 2];
  return (
    red: backgroundRed,
    green: backgroundGreen,
    blue: backgroundBlue,
    luminance:
        (backgroundRed * 30 + backgroundGreen * 59 + backgroundBlue * 11) ~/
        100,
  );
}

({Float32List luminance, Float32List gradient}) _extractIconStructuralFeatures(
  Uint8List pixelLuminance,
) {
  final luminance = <double>[];
  for (var y = 1; y < _refinedComparedRows; y += 1) {
    for (var x = 1; x < _refinedIconExtent - 1; x += 1) {
      luminance.add(pixelLuminance[y * _refinedIconExtent + x].toDouble());
    }
  }
  final normalizedLuminance = _normalizeZeroMean(luminance);

  final gradient = <double>[];
  for (var y = 2; y < _refinedComparedRows - 1; y += 1) {
    for (var x = 2; x < _refinedIconExtent - 2; x += 1) {
      gradient
        ..add(
          (pixelLuminance[y * _refinedIconExtent + x + 1] -
                  pixelLuminance[y * _refinedIconExtent + x - 1])
              .toDouble(),
        )
        ..add(
          (pixelLuminance[(y + 1) * _refinedIconExtent + x] -
                  pixelLuminance[(y - 1) * _refinedIconExtent + x])
              .toDouble(),
        );
    }
  }
  final normalizedGradient = _normalizeLength(gradient);
  return (luminance: normalizedLuminance, gradient: normalizedGradient);
}

Float32List _normalizeZeroMean(List<double> source) {
  if (source.isEmpty) return Float32List(0);
  final mean = source.reduce((left, right) => left + right) / source.length;
  return _normalizeLength(source.map((value) => value - mean).toList());
}

Float32List _normalizeLength(List<double> source) {
  var squaredLength = 0.0;
  for (final value in source) {
    squaredLength += value * value;
  }
  if (squaredLength <= 1e-12) return Float32List(0);
  final inverseLength = 1 / math.sqrt(squaredLength);
  return Float32List.fromList(
    source.map((value) => value * inverseLength).toList(growable: false),
  );
}

Float32List? _extractBrightChroma(List<int> rgb) {
  var red = 0.0;
  var green = 0.0;
  var blue = 0.0;
  var count = 0;
  for (var y = 18; y < _refinedIconExtent; y += 1) {
    for (var x = 4; x < _refinedIconExtent - 4; x += 1) {
      final offset = (y * _refinedIconExtent + x) * 3;
      final r = rgb[offset];
      final g = rgb[offset + 1];
      final b = rgb[offset + 2];
      final maximum = math.max(r, math.max(g, b));
      final minimum = math.min(r, math.min(g, b));
      // Quantity text is bright but nearly neutral. Keeping only bright,
      // colourful pixels exposes subtle material differences underneath it,
      // such as golden Deep Frying Oil versus green Olive Oil.
      if (maximum < 120 || maximum - minimum < 25) continue;
      red += r;
      green += g;
      blue += b;
      count += 1;
    }
  }
  if (count < 6) return null;
  return Float32List.fromList(<double>[
    red / count,
    green / count,
    blue / count,
  ]);
}

Float32List _extractSpatialChroma(List<int> rgb) {
  const columns = 4;
  const rows = 4;
  final values = List<double>.filled(columns * rows * 3, 0);
  final counts = List<int>.filled(columns * rows, 0);
  for (var y = 1; y < _refinedComparedRows; y += 1) {
    final cellY = (y * rows ~/ _refinedComparedRows).clamp(0, rows - 1);
    for (var x = 1; x < _refinedIconExtent - 1; x += 1) {
      final offset = (y * _refinedIconExtent + x) * 3;
      final red = rgb[offset];
      final green = rgb[offset + 1];
      final blue = rgb[offset + 2];
      final maximum = math.max(red, math.max(green, blue));
      final minimum = math.min(red, math.min(green, blue));
      if (maximum < 55 || maximum - minimum < 16) continue;
      final cellX = (x * columns ~/ _refinedIconExtent).clamp(0, columns - 1);
      final cell = cellY * columns + cellX;
      final target = cell * 3;
      values[target] += (red - green) / 255;
      values[target + 1] += (blue - green) / 255;
      values[target + 2] += (maximum - minimum) / 255;
      counts[cell] += 1;
    }
  }
  for (var cell = 0; cell < counts.length; cell += 1) {
    final count = counts[cell];
    if (count == 0) continue;
    final target = cell * 3;
    values[target] /= count;
    values[target + 1] /= count;
    values[target + 2] = values[target + 2] / count + count / 180;
  }
  return _normalizeLength(values);
}

double _compareIconFeatures(
  _InventoryIconFeature source,
  _InventoryIconFeature template,
) {
  var squaredError = 0.0;
  var weightTotal = 0.0;
  for (var y = 1; y < _refinedComparedRows; y += 1) {
    for (var x = 1; x < _refinedIconExtent - 1; x += 1) {
      final pixelIndex = y * _refinedIconExtent + x;
      final offset = pixelIndex * 3;
      final templateForeground =
          (template.centeredLuminance[pixelIndex].abs() / 80)
              .clamp(.08, 1.0)
              .toDouble();
      final sourceForeground = (source.centeredLuminance[pixelIndex].abs() / 80)
          .clamp(.08, 1.0)
          .toDouble();
      final weight = templateForeground > sourceForeground
          ? templateForeground
          : sourceForeground;
      final tr = template.centeredRgb[offset];
      final tg = template.centeredRgb[offset + 1];
      final tb = template.centeredRgb[offset + 2];
      final sr = source.centeredRgb[offset];
      final sg = source.centeredRgb[offset + 1];
      final sb = source.centeredRgb[offset + 2];
      squaredError +=
          weight *
          ((tr - sr) * (tr - sr) +
              (tg - sg) * (tg - sg) +
              (tb - sb) * (tb - sb)) /
          3;
      weightTotal += weight;
    }
  }
  final rmse = weightTotal <= 0 ? 255.0 : math.sqrt(squaredError / weightTotal);
  final color = (1 - rmse / 150).clamp(0.0, 1.0).toDouble();
  final luminance = _compareNormalizedVectors(
    source.luminance,
    template.luminance,
  );
  final gradient = _compareNormalizedVectors(
    source.gradient,
    template.gradient,
  );
  final structural = color * .40 + luminance * .35 + gradient * .25;
  final chroma = _compareChroma(source.chroma, template.chroma);
  final spatialChroma = _compareNormalizedVectors(
    source.spatialChroma,
    template.spatialChroma,
  );
  final colorEvidence = chroma == null
      ? spatialChroma
      : spatialChroma * .72 + chroma * .28;
  if (colorEvidence < .35) {
    return structural.clamp(0.0, 1.0).toDouble();
  }

  // Colour is extremely useful for icons with almost identical silhouettes
  // (for example golden Deep Frying Oil versus green Olive Oil), but it must
  // not overpower the actual drawing. A colour-heavy average previously let
  // a brown dried fish narrowly beat the structurally exact Big Tiger
  // Mushroom. Requiring both signals to agree preserves the subtle colour
  // distinction while strongly rejecting a different shape with a similar
  // palette.
  final weakerSignal = math.min(structural, colorEvidence);
  final strongerSignal = math.max(structural, colorEvidence);
  return (weakerSignal * .75 + strongerSignal * .25).clamp(0.0, 1.0).toDouble();
}

double _compareAlignedIconFeatures(
  _InventoryIconFeature source,
  _InventoryIconFeature template,
) {
  var best = 0.0;
  for (final pixelPairs in _alignedPixelPairs) {
    var sourceSum = 0.0;
    var templateSum = 0.0;
    var sourceSquared = 0.0;
    var templateSquared = 0.0;
    var product = 0.0;
    var correlationWeight = 0.0;
    var sourceForeground = 0.0;
    var templateForeground = 0.0;
    var foregroundIntersection = 0.0;
    var sourceGradientSquared = 0.0;
    var templateGradientSquared = 0.0;
    var gradientProduct = 0.0;
    var colorSquaredError = 0.0;
    var colorWeight = 0.0;
    var labSquaredError = 0.0;
    var labWeight = 0.0;
    for (var pair = 0; pair < pixelPairs.length; pair += 2) {
      final templateIndex = pixelPairs[pair];
      final sourceIndex = pixelPairs[pair + 1];
      final templateValue = template.centeredLuminance[templateIndex];
      final sourceValue = source.centeredLuminance[sourceIndex];
      final sourceMaskByte = source.softForegroundMask[sourceIndex];
      final templateMaskByte = template.softForegroundMask[templateIndex];
      final maskPair = (sourceMaskByte << 8) | templateMaskByte;
      final sourceMask = _softMaskUnit[sourceMaskByte];
      final templateMask = _softMaskUnit[templateMaskByte];
      final intersectionWeight = _softMaskPairs.intersection[maskPair];
      final unionWeight = _softMaskPairs.union[maskPair];
      // Keep a very small background contribution so that two sparse icons
      // cannot correlate perfectly on a handful of pixels, while allowing
      // actual artwork to dominate the alignment.
      final luminanceWeight = math.max(.02, intersectionWeight);
      sourceSum += luminanceWeight * sourceValue;
      templateSum += luminanceWeight * templateValue;
      sourceSquared += luminanceWeight * sourceValue * sourceValue;
      templateSquared += luminanceWeight * templateValue * templateValue;
      product += luminanceWeight * sourceValue * templateValue;
      correlationWeight += luminanceWeight;

      sourceForeground += sourceMask;
      templateForeground += templateMask;
      foregroundIntersection += _softMaskPairs.minimum[maskPair];

      final sourceDx = source.horizontalGradient[sourceIndex];
      final sourceDy = source.verticalGradient[sourceIndex];
      final templateDx = template.horizontalGradient[templateIndex];
      final templateDy = template.verticalGradient[templateIndex];
      sourceGradientSquared +=
          luminanceWeight * (sourceDx * sourceDx + sourceDy * sourceDy);
      templateGradientSquared +=
          luminanceWeight * (templateDx * templateDx + templateDy * templateDy);
      gradientProduct +=
          luminanceWeight * (sourceDx * templateDx + sourceDy * templateDy);

      // Compare RGB residuals at the same translated coordinates used by
      // the silhouette and edge pass. Per-channel background subtraction
      // removes capture tint without erasing the real green/blue/brown
      // differences between otherwise similar material icons.
      final templateOffset = templateIndex * 3;
      final sourceOffset = sourceIndex * 3;
      final weight = math.max(.04, unionWeight);
      final tr = template.centeredRgb[templateOffset];
      final tg = template.centeredRgb[templateOffset + 1];
      final tb = template.centeredRgb[templateOffset + 2];
      final sr = source.centeredRgb[sourceOffset];
      final sg = source.centeredRgb[sourceOffset + 1];
      final sb = source.centeredRgb[sourceOffset + 2];
      colorSquaredError +=
          weight *
          ((tr - sr) * (tr - sr) +
              (tg - sg) * (tg - sg) +
              (tb - sb) * (tb - sb)) /
          3;
      colorWeight += weight;

      // Lab a*/b* residuals retain subtle perceptual hue differences even
      // when two icons have nearly identical brightness and silhouette.
      // They are evaluated at the same translated coordinates as the raw
      // pixels, so frame/background colours cannot decide alignment alone.
      final templateLabA = template.centeredLabA[templateIndex];
      final templateLabB = template.centeredLabB[templateIndex];
      final sourceLabA = source.centeredLabA[sourceIndex];
      final sourceLabB = source.centeredLabB[sourceIndex];
      final labADifference = templateLabA - sourceLabA;
      final labBDifference = templateLabB - sourceLabB;
      labSquaredError +=
          weight *
          (labADifference * labADifference + labBDifference * labBDifference) /
          2;
      labWeight += weight;
    }
    if (pixelPairs.isEmpty || correlationWeight <= 1e-9) continue;

    final covariance = product - sourceSum * templateSum / correlationWeight;
    final sourceVariance =
        sourceSquared - sourceSum * sourceSum / correlationWeight;
    final templateVariance =
        templateSquared - templateSum * templateSum / correlationWeight;
    final luminanceDenominator = math.sqrt(
      math.max(0.0, sourceVariance) * math.max(0.0, templateVariance),
    );
    final luminanceCorrelation = luminanceDenominator <= 1e-9
        ? 0.0
        : ((covariance / luminanceDenominator) + 1) / 2;
    final maskTotal = sourceForeground + templateForeground;
    final maskDice = maskTotal == 0
        ? 0.0
        : foregroundIntersection * 2 / maskTotal;
    final gradientDenominator = math.sqrt(
      sourceGradientSquared * templateGradientSquared,
    );
    final gradientCorrelation = gradientDenominator <= 1e-9
        ? 0.0
        : ((gradientProduct / gradientDenominator) + 1) / 2;
    final structural =
        luminanceCorrelation.clamp(0.0, 1.0) * .48 +
        maskDice.clamp(0.0, 1.0) * .27 +
        gradientCorrelation.clamp(0.0, 1.0) * .25;
    final colorRmse = colorWeight <= 0
        ? 255.0
        : math.sqrt(colorSquaredError / colorWeight);
    final rawColor = (1 - colorRmse / 150).clamp(0.0, 1.0).toDouble();
    final labRmse = labWeight <= 0
        ? 512.0
        : math.sqrt(labSquaredError / labWeight);
    final perceptualColor = (1 - labRmse / 220).clamp(0.0, 1.0).toDouble();
    final color = rawColor * .55 + perceptualColor * .45;
    // Neither a matching palette nor a matching silhouette may overwhelm a
    // disagreement in the other. This keeps differently shaped brown items
    // apart while making subtle sap/oil/crop colours useful evidence.
    final weakerSignal = math.min(structural, color);
    final strongerSignal = math.max(structural, color);
    final score = weakerSignal * .72 + strongerSignal * .28;
    if (score > best) best = score;
  }
  return best.clamp(0.0, 1.0).toDouble();
}

double? _compareChroma(Float32List? left, Float32List? right) {
  if (left == null || right == null || left.length != 3 || right.length != 3) {
    return null;
  }
  var squaredDistance = 0.0;
  for (var index = 0; index < 3; index += 1) {
    final difference = left[index] - right[index];
    squaredDistance += difference * difference;
  }
  return (1 - math.sqrt(squaredDistance) / 90).clamp(0.0, 1.0).toDouble();
}

({Int16List a, Int16List b}) _buildLabChromaLookup() {
  const side = 64;
  final a = Int16List(side * side * side);
  final b = Int16List(side * side * side);
  final linear = List<double>.generate(side, (value) {
    final encoded = (value * 4 + 2).clamp(0, 255) / 255;
    return encoded <= .04045
        ? encoded / 12.92
        : math.pow((encoded + .055) / 1.055, 2.4).toDouble();
  }, growable: false);

  double labCurve(double value) => value > .008856
      ? math.pow(value, 1 / 3).toDouble()
      : 7.787 * value + 16 / 116;

  for (var red = 0; red < side; red += 1) {
    for (var green = 0; green < side; green += 1) {
      for (var blue = 0; blue < side; blue += 1) {
        final r = linear[red];
        final g = linear[green];
        final bl = linear[blue];
        final x = (r * .4124564 + g * .3575761 + bl * .1804375) / .95047;
        final y = r * .2126729 + g * .7151522 + bl * .072175;
        final z = (r * .0193339 + g * .1191920 + bl * .9503041) / 1.08883;
        final fx = labCurve(x);
        final fy = labCurve(y);
        final fz = labCurve(z);
        final index = (red << 12) | (green << 6) | blue;
        a[index] = (500 * (fx - fy) * 4).round().clamp(-32768, 32767).toInt();
        b[index] = (200 * (fy - fz) * 4).round().clamp(-32768, 32767).toInt();
      }
    }
  }
  return (a: a, b: b);
}

(int, int) _lookupLabChroma(int red, int green, int blue) {
  final index = ((red >> 2) << 12) | ((green >> 2) << 6) | (blue >> 2);
  return (_labChromaLookup.a[index], _labChromaLookup.b[index]);
}

int _iconLuminance(List<int> rgb, int offset) =>
    (rgb[offset] * 30 + rgb[offset + 1] * 59 + rgb[offset + 2] * 11) ~/ 100;

double _compareNormalizedVectors(List<double> left, List<double> right) {
  if (left.isEmpty || left.length != right.length) return 0;
  var product = 0.0;
  for (var index = 0; index < left.length; index += 1) {
    product += left[index] * right[index];
  }
  return ((product + 1) / 2).clamp(0.0, 1.0).toDouble();
}

Map<String, String> _inventoryOcrOrderGroups(CatalogSnapshot catalog) {
  final groups = <String, String>{};

  void assign(String name, String group, {bool authoritative = false}) {
    final folded = _fold(name);
    if (folded.isEmpty) return;
    if (authoritative) {
      groups[folded] = group;
    } else {
      groups.putIfAbsent(folded, () => group);
    }
  }

  void assignIngredientFamily(CraftMode mode, Ingredient ingredient) {
    final catalogGroup = _fold(ingredient.substituteGroup ?? '');
    final orderGroup = switch (catalogGroup) {
      'blood group 1' ||
      'blood group 2' ||
      'blood group 3' ||
      'blood group 4' ||
      'blood group 5' => 'blood:all',
      'red meat' || 'bird meat' || 'bdo group 11' => 'meat:all',
      'dried fish' when mode == CraftMode.cooking => 'dried-fish',
      'bdo group 6' when mode == CraftMode.cooking => 'dried-fish',
      'grain flour' when mode == CraftMode.cooking => 'grain:flour',
      'bdo group 5' when mode == CraftMode.cooking => 'grain:flour',
      'dough' when mode == CraftMode.cooking => 'grain:dough',
      'grain dough' when mode == CraftMode.cooking => 'grain:dough',
      'bdo group 2' when mode == CraftMode.cooking => 'grain:dough',
      'dried fish' || 'bdo group 6' => null,
      _ => null,
    };
    if (orderGroup == null) return;
    final authoritative =
        orderGroup == 'dried-fish' ||
        orderGroup == 'grain:flour' ||
        orderGroup == 'grain:dough' ||
        orderGroup.startsWith('blood:') ||
        orderGroup.startsWith('meat:');
    for (final name in <String>[ingredient.name, ...ingredient.options]) {
      assign(name, orderGroup, authoritative: authoritative);
    }
  }

  for (final mode in CraftMode.values) {
    for (final recipe in catalog.forMode(mode).items.values) {
      if (_fold(recipe.group ?? '') == 'mushrooms' &&
          _fold(recipe.qualityGrade ?? '') == 'high' &&
          int.tryParse(recipe.marketId ?? '') != null) {
        // The game's Big mushrooms are reviewed high-tier mushroom items with
        // their own consecutive canonical IDs. They are visually distinct at
        // source resolution but small enough that the sealed 20 px atlas can
        // confuse one with another material. Keeping this structured family
        // lets Auto Arrange repair the sequence just like dried fish, meats,
        // and bloods without inferring anything from the display name.
        assign(recipe.name, 'mushroom:big', authoritative: true);
      }
      if (mode == CraftMode.cooking &&
          _fold(recipe.group ?? '') == 'npc items') {
        assign(recipe.name, 'cooking:npc-items', authoritative: true);
      }
      if (mode == CraftMode.cooking &&
          _fold(recipe.group ?? '') == 'dried fish') {
        assign(recipe.name, 'dried-fish', authoritative: true);
      }
      for (final ingredient in recipe.ingredients) {
        assignIngredientFamily(mode, ingredient);
      }
      for (final variant in recipe.variants) {
        for (final ingredient in variant.ingredients) {
          assignIngredientFamily(mode, ingredient);
        }
      }
    }
  }

  // Auto Arrange places the reviewed blood members in one canonical item-ID
  // run even when they belong to different substitution groups and use
  // different bottle artwork. The visual family still constrains each row;
  // this key only carries the descending ID bounds across adjacent bloods.
  final rawBloodGroups = catalog.alchemy.metadata['bloodGroups'];
  if (rawBloodGroups is Map<Object?, Object?>) {
    for (final entry in rawBloodGroups.entries) {
      final label = entry.key;
      final members = entry.value;
      if (label is! String || members is! Iterable<Object?>) continue;
      for (final member in members.whereType<String>()) {
        assign(member, 'blood:all', authoritative: true);
      }
    }
  }

  // These are reviewed canonical client item IDs, not display-name guesses.
  // Artwork remains the primary identity evidence; the order key only lets the
  // review screen reject a visually proposed item that violates an established
  // adjacent Auto Arrange run.
  final catalogItemIds = _catalogItemIds(catalog);
  for (final entry in catalogItemIds.entries) {
    if (_reviewedTreeSapItemIds.contains(entry.value)) {
      assign(entry.key, 'sap:tree', authoritative: true);
    }
    if (_reviewedRawHideItemIds.contains(entry.value)) {
      assign(entry.key, 'hide:raw', authoritative: true);
    }
  }

  return Map<String, String>.unmodifiable(groups);
}

const Set<String> _expandedOrderCandidateGroups = <String>{'blood:all'};

const Set<int> _reviewedTreeSapItemIds = <int>{
  5001,
  5002,
  5003,
  5004,
  5009,
  5010,
  5012,
  5013,
  5014,
  5015,
  5016,
  5017,
  5018,
  5020,
  5023,
  5024,
  5025,
};

const Set<int> _reviewedRawHideItemIds = <int>{
  6001,
  6002,
  6003,
  6004,
  6005,
  6006,
  6007,
  6008,
  6009,
  6010,
  6011,
  6012,
  6013,
  6014,
  6015,
  6016,
  6020,
  6021,
  6022,
  6023,
  6026,
  6027,
  6028,
  6029,
  6030,
};

final class InventoryOcrIconCandidate {
  const InventoryOcrIconCandidate({
    required this.icon,
    required this.score,
    required this.materialEligible,
  });

  final String icon;
  final double score;
  final bool? materialEligible;
}

Map<String, Object?> _requiredMap(Object? value, String label) {
  if (value is! Map) {
    throw FormatException('Storage OCR returned an invalid $label.');
  }
  return value.map((key, entryValue) => MapEntry(key.toString(), entryValue));
}

List<Object?> _requiredList(Map<String, Object?> map, String name) {
  final value = map[name];
  if (value is! List) {
    throw FormatException('Storage OCR returned an invalid $name list.');
  }
  return List<Object?>.from(value);
}

String _requiredString(Map<String, Object?> map, String name) {
  final value = map[name];
  if (value is! String || value.trim().isEmpty) {
    throw FormatException('Storage OCR returned an invalid $name.');
  }
  return value.trim();
}

String _optionalString(Object? value, {required int maximumLength}) {
  if (value == null) return '';
  if (value is! String || value.length > maximumLength) {
    throw const FormatException('Storage OCR returned invalid text.');
  }
  return value.trim();
}

int _requiredInt(
  Map<String, Object?> map,
  String name, {
  required int minimum,
  required int maximum,
}) {
  final value = map[name];
  if (value is! num || !value.isFinite || value != value.roundToDouble()) {
    throw FormatException('Storage OCR returned an invalid $name.');
  }
  final parsed = value.toInt();
  if (parsed < minimum || parsed > maximum) {
    throw FormatException('Storage OCR returned an out-of-range $name.');
  }
  return parsed;
}

int? _nullableInt(Object? value, {required int minimum, required int maximum}) {
  if (value == null) return null;
  if (value is! num || !value.isFinite || value != value.roundToDouble()) {
    throw const FormatException('Storage OCR returned an invalid integer.');
  }
  final parsed = value.toInt();
  if (parsed < minimum || parsed > maximum) {
    throw const FormatException(
      'Storage OCR returned an out-of-range integer.',
    );
  }
  return parsed;
}

double _requiredDouble(
  Map<String, Object?> map,
  String name, {
  required double minimum,
  required double maximum,
}) {
  final value = map[name];
  if (value is! num || !value.isFinite) {
    throw FormatException('Storage OCR returned an invalid $name.');
  }
  final parsed = value.toDouble();
  if (parsed < minimum || parsed > maximum) {
    throw FormatException('Storage OCR returned an out-of-range $name.');
  }
  return parsed;
}

double? _nullableDouble(
  Object? value, {
  required double minimum,
  required double maximum,
}) {
  if (value == null) return null;
  if (value is! num || !value.isFinite) {
    throw const FormatException('Storage OCR returned an invalid number.');
  }
  final parsed = value.toDouble();
  if (parsed < minimum || parsed > maximum) {
    throw const FormatException('Storage OCR returned an out-of-range number.');
  }
  return parsed;
}

bool _requiredBool(Map<String, Object?> map, String name) {
  final value = map[name];
  if (value is! bool) {
    throw FormatException('Storage OCR returned an invalid $name.');
  }
  return value;
}

bool? _nullableBool(Object? value) {
  if (value == null) return null;
  if (value is! bool) {
    throw const FormatException('Storage OCR returned an invalid flag.');
  }
  return value;
}

String? _normalizeIconPath(String value) {
  final normalized = value.trim().replaceAll('\\', '/');
  if (normalized.isEmpty ||
      normalized.length > 180 ||
      normalized.startsWith('/') ||
      normalized.contains('..') ||
      !RegExp(r'^icons/items/[a-fA-F0-9]{64}\.webp$').hasMatch(normalized)) {
    return null;
  }
  return normalized.toLowerCase();
}

String _fold(String value) => value.trim().toLowerCase();
bool _same(String left, String right) => _fold(left) == _fold(right);

int _compareNames(String left, String right) {
  final folded = _fold(left).compareTo(_fold(right));
  return folded != 0 ? folded : left.compareTo(right);
}

int _compareMaterials(_OcrMaterial left, _OcrMaterial right) {
  final id = (right.itemId ?? -1).compareTo(left.itemId ?? -1);
  return id != 0 ? id : _compareNames(left.name, right.name);
}

extension _IterableFirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;

  T? firstWhereOrNull(bool Function(T value) predicate) {
    for (final value in this) {
      if (predicate(value)) return value;
    }
    return null;
  }
}
