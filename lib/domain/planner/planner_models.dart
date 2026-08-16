import 'dart:collection';

final class QualityTierRule {
  const QualityTierRule({required this.name, required this.ratio});

  final String name;
  final double ratio;
}

final class QualityConversionRule {
  const QualityConversionRule({this.high, this.special});

  final QualityTierRule? high;
  final QualityTierRule? special;
}

final class SpecialQualityRule {
  const SpecialQualityRule({required this.name, required this.ratio});

  final String name;
  final double ratio;
}

final class VendorSourceRule {
  const VendorSourceRule({
    this.vendor,
    this.role,
    this.location,
    this.price = 0,
  });

  final String? vendor;
  final String? role;
  final String? location;
  final double price;
}

final class ResolvedSourceInfo {
  const ResolvedSourceInfo({
    this.sourceNote,
    this.vendor,
    this.role,
    this.location,
    this.npcPrice = 0,
  });

  final String? sourceNote;
  final String? vendor;
  final String? role;
  final String? location;
  final double npcPrice;

  bool get hasDetails =>
      sourceNote != null ||
      vendor != null ||
      role != null ||
      location != null ||
      npcPrice > 0;
}

final class ItemAcquisitionRoute {
  const ItemAcquisitionRoute({
    required this.kind,
    required this.summary,
    required this.availability,
    required this.confidence,
  });

  final String kind;
  final String summary;
  final String availability;
  final String confidence;

  bool get isDisplayable =>
      summary.trim().isNotEmpty &&
      availability.trim().toLowerCase() != 'expired' &&
      confidence.trim().toLowerCase() != 'unverified';
}

final class ItemAcquisitionRule {
  ItemAcquisitionRule({
    required this.canonicalName,
    required this.itemId,
    required this.status,
    required this.reviewedAt,
    required Iterable<ItemAcquisitionRoute> routes,
  }) : routes = List.unmodifiable(routes);

  final String canonicalName;
  final int? itemId;
  final String status;
  final String reviewedAt;
  final List<ItemAcquisitionRoute> routes;

  List<String> get displayableSummaries {
    if (status.trim().toLowerCase() != 'reviewed') {
      return const <String>[];
    }
    return List<String>.unmodifiable(
      routes
          .where((route) => route.isDisplayable)
          .map((route) => route.summary.trim()),
    );
  }
}

final class PlannerRules {
  PlannerRules({
    Set<String> legacyUnavailableItems = const <String>{},
    Set<String> qualityIngredients = const <String>{},
    Map<String, QualityConversionRule> qualityConversions =
        const <String, QualityConversionRule>{},
    Map<String, String> blueElixirMap = const <String, String>{},
    Map<String, SpecialQualityRule> cookingSpecialMap =
        const <String, SpecialQualityRule>{},
    Map<String, String> marketIds = const <String, String>{},
    Map<String, String> marketNameAliases = const <String, String>{},
    Map<String, double> fallbackMarketPrices = const <String, double>{},
    Map<String, String> itemWeightIds = const <String, String>{},
    Map<String, double> itemWeightsLtById = const <String, double>{},
    Map<String, VendorSourceRule> vendorInfo =
        const <String, VendorSourceRule>{},
    Map<String, ItemAcquisitionRule> acquisitionInfo =
        const <String, ItemAcquisitionRule>{},
  }) : legacyUnavailableItems = Set.unmodifiable(legacyUnavailableItems),
       qualityIngredients = Set.unmodifiable(qualityIngredients),
       qualityConversions = UnmodifiableMapView(
         Map<String, QualityConversionRule>.from(qualityConversions),
       ),
       blueElixirMap = UnmodifiableMapView(
         Map<String, String>.from(blueElixirMap),
       ),
       cookingSpecialMap = UnmodifiableMapView(
         Map<String, SpecialQualityRule>.from(cookingSpecialMap),
       ),
       marketIds = UnmodifiableMapView(Map<String, String>.from(marketIds)),
       marketNameAliases = UnmodifiableMapView(
         Map<String, String>.from(marketNameAliases),
       ),
       fallbackMarketPrices = UnmodifiableMapView(
         Map<String, double>.from(fallbackMarketPrices),
       ),
       itemWeightIds = UnmodifiableMapView(
         Map<String, String>.from(itemWeightIds),
       ),
       itemWeightsLtById = UnmodifiableMapView(
         Map<String, double>.from(itemWeightsLtById),
       ),
       vendorInfo = UnmodifiableMapView(
         Map<String, VendorSourceRule>.from(vendorInfo),
       ),
       acquisitionInfo = UnmodifiableMapView(
         Map<String, ItemAcquisitionRule>.from(acquisitionInfo),
       );

  final Set<String> legacyUnavailableItems;
  final Set<String> qualityIngredients;
  final Map<String, QualityConversionRule> qualityConversions;
  final Map<String, String> blueElixirMap;
  final Map<String, SpecialQualityRule> cookingSpecialMap;
  final Map<String, String> marketIds;
  final Map<String, String> marketNameAliases;
  final Map<String, double> fallbackMarketPrices;
  final Map<String, String> itemWeightIds;
  final Map<String, double> itemWeightsLtById;
  final Map<String, VendorSourceRule> vendorInfo;
  final Map<String, ItemAcquisitionRule> acquisitionInfo;

  String? itemWeightIdFor(String itemName, {String? itemId}) {
    final explicitId = itemId?.trim();
    if (explicitId != null &&
        explicitId.isNotEmpty &&
        itemWeightsLtById.containsKey(explicitId)) {
      return explicitId;
    }
    final exactId = itemWeightIds[itemName];
    if (exactId != null) return exactId;
    final foldedName = itemName.trim().toLowerCase();
    if (foldedName.isEmpty) return null;
    for (final entry in itemWeightIds.entries) {
      if (entry.key.trim().toLowerCase() == foldedName) return entry.value;
    }
    return null;
  }

  double? itemWeightLtFor(String itemName, {String? itemId}) {
    final resolvedId = itemWeightIdFor(itemName, itemId: itemId);
    if (resolvedId == null) return null;
    final weight = itemWeightsLtById[resolvedId];
    return weight != null && weight.isFinite && weight > 0 ? weight : null;
  }
}

final class PlannerState {
  PlannerState({
    required this.target,
    this.want = 100,
    Map<String, double> inventory = const <String, double>{},
    Set<String> completedSteps = const <String>{},
    this.ignoreTargetInventory = true,
    this.ignoreIngredientInventory = true,
    this.alchemyMastery = 0,
    this.cookingMastery = 0,
    this.processingMastery = 0,
    this.useMassProcessing = false,
    Map<String, String> substituteChoices = const <String, String>{},
    Map<String, String> ingredientGrades = const <String, String>{},
    Map<String, String> recipeVariantChoices = const <String, String>{},
    Map<String, double> marketPrices = const <String, double>{},
    Map<String, double> marketStock = const <String, double>{},
  }) : inventory = UnmodifiableMapView(Map<String, double>.from(inventory)),
       completedSteps = Set.unmodifiable(completedSteps),
       substituteChoices = UnmodifiableMapView(
         Map<String, String>.from(substituteChoices),
       ),
       ingredientGrades = UnmodifiableMapView(
         Map<String, String>.from(ingredientGrades),
       ),
       recipeVariantChoices = UnmodifiableMapView(
         Map<String, String>.from(recipeVariantChoices),
       ),
       marketPrices = UnmodifiableMapView(
         Map<String, double>.from(marketPrices),
       ),
       marketStock = UnmodifiableMapView(Map<String, double>.from(marketStock));

  final String target;
  final int want;
  final Map<String, double> inventory;
  final Set<String> completedSteps;
  final bool ignoreTargetInventory;
  final bool ignoreIngredientInventory;
  final int alchemyMastery;
  final int cookingMastery;
  final int processingMastery;
  final bool useMassProcessing;
  final Map<String, String> substituteChoices;
  final Map<String, String> ingredientGrades;
  final Map<String, String> recipeVariantChoices;
  final Map<String, double> marketPrices;
  final Map<String, double> marketStock;
}

final class PlanStepIngredient {
  PlanStepIngredient({
    required this.key,
    required this.name,
    required this.original,
    required this.substituteGroup,
    required this.baseName,
    required this.grade,
    required Iterable<String> options,
    required this.parentName,
    required this.need,
    required this.have,
    required this.missing,
    required this.craftable,
  }) : options = List.unmodifiable(options);

  final String key;
  final String name;
  final String original;
  final String substituteGroup;
  final String baseName;
  final String grade;
  final List<String> options;
  final String parentName;
  final double need;
  final double have;
  final double missing;
  final bool craftable;

  Map<String, Object?> toJson() => <String, Object?>{
    'key': key,
    'name': name,
    'original': original,
    'substituteGroup': substituteGroup,
    'baseName': baseName,
    'grade': grade,
    'options': options,
    'parentName': parentName,
    'need': need,
    'have': have,
    'missing': missing,
    'craftable': craftable,
  };
}

final class PlanStep {
  PlanStep({
    required this.name,
    required this.index,
    required this.count,
    required this.batchCount,
    required this.batchSize,
    required this.produced,
    required this.demand,
    required this.net,
    required this.depth,
    required Iterable<PlanStepIngredient> ingredients,
  }) : ingredients = List.unmodifiable(ingredients);

  final String name;
  final int index;
  final double count;
  final double batchCount;
  final int batchSize;
  final double produced;
  final double demand;
  final double net;
  final int depth;
  final List<PlanStepIngredient> ingredients;

  Map<String, Object?> toJson() => <String, Object?>{
    'name': name,
    'index': index,
    'count': count,
    'batchCount': batchCount,
    'batchSize': batchSize,
    'produced': produced,
    'demand': demand,
    'net': net,
    'depth': depth,
    'ingredients': ingredients.map((item) => item.toJson()).toList(),
  };
}

final class ChoiceMeta {
  ChoiceMeta({
    required this.parentName,
    required this.original,
    required this.substituteGroup,
    required Iterable<String> options,
    required this.baseName,
  }) : options = List.unmodifiable(options);

  final String parentName;
  final String original;
  final String substituteGroup;
  final List<String> options;
  final String baseName;

  Map<String, Object?> toJson() => <String, Object?>{
    'parentName': parentName,
    'original': original,
    'substituteGroup': substituteGroup,
    'options': options,
    'baseName': baseName,
  };
}

final class MarketMaterialState {
  const MarketMaterialState({
    required this.marketable,
    required this.stock,
    required this.price,
    required this.buyable,
    required this.unavailable,
    required this.total,
    required this.status,
    required this.hasSourceInfo,
    this.stockKnown = true,
  });

  final bool marketable;
  final double stock;
  final double price;
  final double buyable;
  final double unavailable;
  final double total;
  final String status;
  final bool hasSourceInfo;
  final bool stockKnown;

  Map<String, Object?> toJson() => <String, Object?>{
    'marketable': marketable,
    'stock': stock,
    'price': price,
    'buyable': buyable,
    'unavailable': unavailable,
    'total': total,
    'status': status,
    'hasSourceInfo': hasSourceInfo,
    'stockKnown': stockKnown,
  };
}

final class MissingMaterial {
  const MissingMaterial({
    required this.name,
    required this.key,
    required this.category,
    required this.need,
    required this.have,
    required this.missing,
    required this.choice,
    required this.market,
  });

  final String name;
  final String key;
  final String category;
  final double need;
  final double have;
  final double missing;
  final ChoiceMeta? choice;
  final MarketMaterialState market;

  Map<String, Object?> toJson() => <String, Object?>{
    'name': name,
    'key': key,
    'category': category,
    'need': need,
    'have': have,
    'missing': missing,
    'choice': choice?.toJson(),
    'market': market.toJson(),
  };
}

final class PlanResult {
  PlanResult({
    required this.target,
    required this.want,
    required Iterable<PlanStep> steps,
    required Iterable<MissingMaterial> missing,
    required this.empty,
  }) : steps = List.unmodifiable(steps),
       missing = List.unmodifiable(missing);

  PlanResult.empty({required this.target, required this.want})
    : steps = const <PlanStep>[],
      missing = const <MissingMaterial>[],
      empty = true;

  final String target;
  final int want;
  final List<PlanStep> steps;
  final List<MissingMaterial> missing;
  final bool empty;

  Map<String, Object?> toJson() => <String, Object?>{
    'target': target,
    'want': want,
    'steps': steps.map((step) => step.toJson()).toList(),
    'missing': missing.map((item) => item.toJson()).toList(),
    'empty': empty,
  };
}
