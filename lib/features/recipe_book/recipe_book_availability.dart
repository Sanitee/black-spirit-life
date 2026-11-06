part of 'recipe_book_controller.dart';

/// One real attempt, resolved by the Planner, not a second set of grade ratios.
class RecipeBookIngredientChoice {
  const RecipeBookIngredientChoice({
    required this.ingredient,
    required this.name,
    required this.baseName,
    required this.grade,
    required this.quantity,
    required this.owned,
    required this.npc,
    required this.marketable,
    required this.stock,
    required this.preorders,
  });
  final Ingredient ingredient;
  final String name, baseName, grade;
  final double quantity, owned;
  final bool npc, marketable;
  final int? stock, preorders;
}

class RecipeBookAvailability {
  const RecipeBookAvailability(
    this.ingredients,
    this.canCraft,
    this.ownedTypes,
    this.buyableTypes,
    this.unknownTypes,
    this.missing,
  );
  final List<RecipeBookIngredientChoice> ingredients;
  final int canCraft, ownedTypes, buyableTypes, unknownTypes;
  final Map<String, double> missing;
  int get totalTypes => ingredients.length;
  bool get fullyOwned => totalTypes > 0 && canCraft > 0;
  bool get canBuyMissing =>
      totalTypes > 0 && ownedTypes + buyableTypes == totalTypes;

  /// Full inventory, partial inventory, purchasable, unknown, then unavailable.
  /// Fractions compare recipes with different numbers of ingredient types fairly.
  int compareTo(RecipeBookAvailability other) {
    int tier(RecipeBookAvailability value) => value.fullyOwned
        ? 0
        : value.ownedTypes > 0
        ? 1
        : value.canBuyMissing
        ? 2
        : value.unknownTypes > 0
        ? 3
        : 4;
    var order = tier(this).compareTo(tier(other));
    if (order != 0) return order;
    final own = totalTypes == 0 ? 0.0 : ownedTypes / totalTypes;
    final theirs = other.totalTypes == 0
        ? 0.0
        : other.ownedTypes / other.totalTypes;
    order = theirs.compareTo(own);
    if (order != 0) return order;
    final buy = totalTypes == 0
        ? 0.0
        : (ownedTypes + buyableTypes) / totalTypes;
    final theirBuy = other.totalTypes == 0
        ? 0.0
        : (other.ownedTypes + other.buyableTypes) / other.totalTypes;
    return theirBuy.compareTo(buy);
  }
}

extension RecipeBookAvailabilityController on RecipeBookController {
  ModeState get _cardState =>
      modeController.state.value.copyWith(ignoreIngredientInventory: false);

  ModeState _cardStateFor(String name) {
    final state = _cardState;
    final recipe = recipeDefinitionFor(name);
    final match = recipe == null ? null : _ingredientSearchMatch(name, recipe);
    if (match == null || recipe == null) return state;
    final selections = _targetIngredientSelections(name, recipe, match);
    final choices = {...state.substituteChoices};
    final grades = {...state.ingredientGrades};
    for (final selection in selections) {
      final ingredient = recipe
          .resolveVariant(match.variantId)
          .ingredients
          .where((row) => _sameName(row.name, selection.ingredientName))
          .firstOrNull;
      if (ingredient == null) continue;
      choices[_substituteDocumentKey(name, ingredient)] =
          selection.selectedIngredientName;
      grades[const PlannerEngine().gradeChoiceKey(name, ingredient.name)] =
          selection.grade;
    }
    return state.copyWith(substituteChoices: choices, ingredientGrades: grades);
  }

  // Activation and explicit market refresh must carry the displayed choices.
  ModeState _pricingStateFor(String name) {
    final state = _cardStateFor(name);
    final choices = {...state.substituteChoices};
    final grades = {...state.ingredientGrades};
    for (final row in availabilityFor(name).ingredients) {
      choices[_substituteDocumentKey(name, row.ingredient)] = row.baseName;
      grades[const PlannerEngine().gradeChoiceKey(name, row.ingredient.name)] =
          row.grade;
    }
    return state.copyWith(substituteChoices: choices, ingredientGrades: grades);
  }

  void _prepareAvailability() {
    final state = modeController.state.value;
    final recipes = modeController.recipes;
    if (identical(state, _availabilityState) &&
        identical(recipes, _availabilityRecipes) &&
        _ingredientPreview != null) {
      return;
    }
    _availabilityState = state;
    _availabilityRecipes = recipes;
    _availabilityCache.clear();
    _profitCache.clear();
    _selectionCache.clear();
    _alternativesCache.clear();
    _identityCache.clear();
    _marketDependents.clear();
    _ingredientPreview = const PlannerEngine().prepareIngredientPreview(
      recipes: recipes,
      state: modeController.owner.assembly.plannerState(_cardState),
      rules: modeController.owner.plannerRules,
    );
  }

  void connectAvailabilityMarket(SharedMarketRepository? repository) {
    if (identical(repository, _availabilityMarket)) return;
    _availabilitySubscription?.cancel();
    _availabilityExpiry?.cancel();
    _availabilityMarket = repository;
    _availabilityCache.clear();
    _profitCache.clear();
    if (repository == null) return;
    _availabilitySubscription = repository.receipts.listen((receipt) {
      // Remounting a virtualized card emits cached receipts too. They are not
      // changes and must never trigger a full-book resort while scrolling.
      if (receipt.fromCache) return;
      final names = _marketDependents[receipt.key];
      if (names == null || names.isEmpty) return;
      bool affected(String key) =>
          names.any((name) => key.startsWith('$name:'));
      _availabilityCache.removeWhere((key, _) => affected(key));
      _profitCache.removeWhere((key, _) => affected(key));
      _scheduleMarketRefresh();
    });
    _availabilityExpiry = Timer.periodic(const Duration(seconds: 30), (_) {
      _availabilityCache.clear();
      _profitCache.clear();
      _scheduleMarketRefresh();
    });
  }

  void _scheduleMarketRefresh() {
    if (_disposed) return;
    _marketRefreshPending = true;
    _availabilityRefresh ??= Timer(const Duration(milliseconds: 250), () {
      _availabilityRefresh = null;
      _flushMarketRefresh();
    });
  }

  void _flushMarketRefresh() {
    if (_disposed || !_marketRefreshPending || _scrollIdle != null) return;
    _marketRefreshPending = false;
    if (_marketSort.sortsAvailability ||
        _marketSort.sortsProfit ||
        _profitableOnly) {
      _availabilityChanged();
    }
  }

  ({Recipe? recipe, bool npc, String? marketId}) _cardIdentity(String name) =>
      _identityCache.putIfAbsent(
        name,
        () => choiceMarketIdentity(modeController, name, acrossModes: true),
      );

  OpportunityMarketItem? availabilityMarketFor(
    String name, {
    String? dependent,
  }) {
    final identity = _cardIdentity(name);
    final region = modeController.state.value.market.region.toLowerCase();
    if (identity.marketId == null || !const {'eu', 'na'}.contains(region)) {
      return null;
    }
    final key = SharedMarketKey(region: region, itemId: identity.marketId!);
    if (dependent != null) (_marketDependents[key] ??= {}).add(dependent);
    return _availabilityMarket?.cachedItem(key);
  }

  double? _cardMarketPrice(String name, {required String dependent}) {
    if (_cardIdentity(name).marketId == null) return null;
    final now = DateTime.now();
    final item = availabilityMarketFor(name, dependent: dependent);
    if (item != null) {
      return recipeMarketUnitPrice(item, now, sharedMarketFreshness);
    }
    final market = modeController.state.value.market;
    final observed = _foldedValue(market.preorderObservedAt, name) ?? 0;
    bool fresh(int stamp) =>
        stamp > 0 &&
        now.millisecondsSinceEpoch >= stamp &&
        now.millisecondsSinceEpoch - stamp <=
            sharedMarketFreshness.inMilliseconds;
    final bid = _foldedValue(market.preorderPrices, name);
    if (_foldedValue(market.stock, name) == 0 &&
        fresh(observed) &&
        bid != null &&
        bid.isFinite &&
        bid > 0) {
      return bid;
    }
    // Legacy/offline callers keep their saved-price behaviour. A live card
    // never promotes an old cache to a fresh market observation.
    if (_availabilityMarket != null && !fresh(market.fetchedAt)) return null;
    final price = _foldedValue(market.prices, name);
    return price != null && price.isFinite && price > 0 ? price : null;
  }

  RecipeCraftComparison craftComparisonFor(String name) {
    final availability = availabilityFor(name);
    final quote = profitabilityFor(name);
    final tax = modeController.owner.marketTax.value;
    final outputPrice = _cardMarketPrice(name, dependent: name);
    final output = quote?.outputPerCraft;
    return RecipeCraftComparison.calculate(
      outputNetRevenue: output == null || outputPrice == null
          ? null
          : marketNetProceeds(output * outputPrice, tax),
      netRate: marketNetRate(tax),
      inputs: [
        for (final row in availability.ingredients)
          RecipeCraftValueInput(
            name: row.name,
            quantity: row.quantity,
            owned: row.owned,
            buyPrice: row.npc
                ? modeController
                      .resolveItemSource(
                        row.name,
                        recipe: _cardIdentity(row.name).recipe,
                      )
                      .npcPrice
                : _cardMarketPrice(row.name, dependent: name),
            sellPrice: _cardMarketPrice(row.name, dependent: name),
            marketable: row.marketable,
          ),
      ],
    );
  }

  bool cardOutputCanBeSold(String name) => _cardIdentity(name).marketId != null;

  RecipeBookIngredientChoice _choice(
    Ingredient ingredient,
    planning.PlanStepIngredient pick,
  ) {
    final identity = _cardIdentity(pick.name);
    final market = availabilityMarketFor(pick.name);
    final now = DateTime.now();
    final owned =
        _foldedValue(modeController.state.value.inventory, pick.name) ?? 0;
    return RecipeBookIngredientChoice(
      ingredient: ingredient,
      name: pick.name,
      baseName: pick.baseName,
      grade: pick.grade,
      quantity: pick.need,
      owned: owned.isFinite ? math.max(0, owned) : 0,
      npc: identity.npc,
      marketable: identity.marketId != null,
      stock: market?.stockFor(now, sharedMarketFreshness),
      preorders: market?.bookIsFresh(now, sharedMarketFreshness) == true
          ? market?.preorderCount
          : null,
    );
  }

  RecipeBookAvailability availabilityFor(String name) {
    _prepareAvailability();
    final variant = selectedRecipeVariantId(name);
    final key = '$name:$variant:$searchByIngredient:$_search';
    return _availabilityCache.putIfAbsent(key, () {
      final recipe = recipeFor(name);
      if (recipe == null || !recipe.isCraftable) {
        return const RecipeBookAvailability([], 0, 0, 0, 0, {});
      }
      final state = modeController.owner.assembly.plannerState(
        _cardStateFor(name),
      );
      final selection = _selectionCache.putIfAbsent(
        key,
        () => [
          for (final ingredient in recipe.ingredients)
            _choice(
              ingredient,
              _ingredientPreview!.preview(
                state: state,
                parentName: name,
                ingredient: ingredient,
              ),
            ),
        ],
      );
      // Market receipts update availability, not the Planner's selection.
      // Reuse the exact resolved ingredients across quote/badge repaint bursts.
      final now = DateTime.now();
      final rows = [
        for (final row in selection)
          RecipeBookIngredientChoice(
            ingredient: row.ingredient,
            name: row.name,
            baseName: row.baseName,
            grade: row.grade,
            quantity: row.quantity,
            owned: row.owned,
            npc: row.npc,
            marketable: row.marketable,
            stock: availabilityMarketFor(
              row.name,
              dependent: name,
            )?.stockFor(now, sharedMarketFreshness),
            preorders:
                availabilityMarketFor(
                      row.name,
                    )?.bookIsFresh(now, sharedMarketFreshness) ==
                    true
                ? availabilityMarketFor(row.name)?.preorderCount
                : null,
          ),
      ];
      // Aggregate identical selected inputs before calculating craft capacity.
      final totals = <String, double>{};
      final owned = <String, double>{};
      for (final row in rows) {
        final id = _fold(row.name);
        totals[id] = (totals[id] ?? 0) + row.quantity;
        owned[id] = row.owned;
      }
      var crafts = rows.isEmpty ? 0 : 0x7fffffff;
      for (final entry in totals.entries) {
        if (entry.value <= 0 || !entry.value.isFinite) {
          crafts = 0;
          continue;
        }
        crafts = math.min(crafts, (owned[entry.key]! / entry.value).floor());
      }
      final remainingOwned = {...owned};
      final remainingMarket = <String, double>{};
      var haveTypes = 0, buyTypes = 0, unknownTypes = 0;
      final missing = <String, double>{};
      for (final row in rows) {
        final id = _fold(row.name);
        final have = math.min(row.quantity, remainingOwned[id] ?? 0);
        remainingOwned[id] = (remainingOwned[id] ?? 0) - have;
        final need = row.quantity - have;
        if (need <= 0) {
          haveTypes++;
          continue;
        }
        missing[row.name] = (missing[row.name] ?? 0) + need;
        final stock = remainingMarket.putIfAbsent(
          id,
          () => (row.stock ?? 0).toDouble(),
        );
        if (row.npc || stock >= need) {
          buyTypes++;
          if (!row.npc) remainingMarket[id] = stock - need;
        } else if (row.marketable && row.stock == null) {
          unknownTypes++;
        }
      }
      return RecipeBookAvailability(
        List.unmodifiable(rows),
        crafts,
        haveTypes,
        buyTypes,
        unknownTypes,
        Map.unmodifiable(missing),
      );
    });
  }

  List<RecipeBookIngredientChoice> ingredientChoices(
    String parent,
    Ingredient ingredient,
  ) {
    _prepareAvailability();
    final engine = const PlannerEngine();
    final choices = <RecipeBookIngredientChoice>[];
    final seen = <String>{};
    for (final base in substituteOptions(ingredient)) {
      final grades = qualityGrades(
        parentName: parent,
        ingredient: ingredient,
        selectedName: base,
      );
      for (final grade in {
        'normal',
        ...grades.where((grade) => grade != 'auto'),
      }) {
        final forced = _cardState.copyWith(
          substituteChoices: {
            ..._cardState.substituteChoices,
            engine.substituteChoiceKey(parent, ingredient): base,
          },
          ingredientGrades: {
            ..._cardState.ingredientGrades,
            engine.gradeChoiceKey(parent, ingredient.name): grade,
          },
        );
        final pick = _ingredientPreview!.preview(
          state: modeController.owner.assembly.plannerState(forced),
          parentName: parent,
          ingredient: ingredient,
        );
        if (seen.add(_fold(pick.name))) choices.add(_choice(ingredient, pick));
      }
    }
    return choices;
  }

  bool hasIngredientAlternatives(
    String parent,
    RecipeBookIngredientChoice row,
  ) {
    _prepareAvailability();
    return _alternativesCache.putIfAbsent(
      (parent, row.ingredient, row.baseName),
      () =>
          substituteOptions(row.ingredient).length > 1 ||
          qualityGrades(
                parentName: parent,
                ingredient: row.ingredient,
                selectedName: row.baseName,
              ).length >
              1,
    );
  }

  void selectIngredientChoice(
    String parent,
    RecipeBookIngredientChoice choice,
  ) {
    selectSubstitute(
      parentName: parent,
      ingredient: choice.ingredient,
      selection: choice.baseName,
    );
    selectQuality(
      parentName: parent,
      ingredient: choice.ingredient,
      grade: choice.grade,
    );
  }
}
