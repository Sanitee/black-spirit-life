part of 'opportunities_workspace.dart';

/// The header owns the item bay; opening details never moves that artwork.
class _ExpandingCraftCard extends StatefulWidget {
  const _ExpandingCraftCard({
    required this.controller,
    required this.quote,
    required this.expanded,
    required this.onToggle,
  });
  final OpportunitiesController controller;
  final OpportunityQuote quote;
  final bool expanded;
  final VoidCallback onToggle;

  @override
  State<_ExpandingCraftCard> createState() => _ExpandingCraftCardState();
}

class _ExpandingCraftCardState extends State<_ExpandingCraftCard> {
  bool _recipe = false;
  bool _allOwned = false;
  OpportunitiesController get controller => widget.controller;
  OpportunityQuote get quote => widget.quote;

  @override
  void didUpdateWidget(_ExpandingCraftCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.expanded || oldWidget.quote.recipeName != quote.recipeName) {
      _recipe = false;
      _allOwned = false;
    }
  }

  void _inspect() => _craftDetails(context, controller, quote);

  void _togglePanel({required bool recipe}) {
    if (widget.expanded && _recipe == recipe) {
      widget.onToggle();
      return;
    }
    setState(() {
      _recipe = recipe;
      _allOwned = false;
    });
    if (!widget.expanded) widget.onToggle();
  }

  @override
  Widget build(BuildContext context) {
    final spec = context.visualTheme;
    final finish = OpportunityGlassFinish.of(context);
    final comparison = OpportunityCraftComparison(
      quote,
      controller.craftSaleMode,
    );
    final profit = _allOwned
        ? comparison.allOwnedProfit
        : comparison.inventoryProfit;
    final decision = OpportunityCraftComparison.decision(profit);
    final stock = OpportunityCardStock(
      controller.outputMarketFor(quote.recipeName),
      controller.clock(),
      controller.cachedMarketMaxAge,
    );
    final material = OpportunityCraftCardMaterial.forSpec(spec, stock.tone);
    final profitColor = profit == null || profit.round() == 0
        ? material.mutedInk
        : profit < 0
        ? material.lossInk
        : spec.palette.text;
    final experience = controller.preferences.craftSort == 'exp'
        ? controller.experienceForQuote(quote)
        : null;
    final target = controller.plannerTargetFor(
      quote.recipeName,
      variantId: quote.selectedVariantId,
    );
    final openPlanner = OpportunityItemActionsScope.maybeOf(
      context,
    )?.openPlannerTarget;
    final explanation = [
      'Per expected main item, rounded to whole silver. Rare results and byproducts are excluded.',
      if (quote.hasEstimatedInputs)
        'Some ingredients use current-price estimates, not confirmed buyable stock.',
      if (quote.usesInventory)
        'Cost includes the after-tax sale value of owned ingredients used.',
      if (quote.hasCustomSalePrice) 'Uses your custom sale price after tax.',
      if (_allOwned) 'Hypothetical: every required ingredient already owned.',
    ].join('\n');

    Widget amount(double? value, {bool headline = false, Key? textKey}) =>
        OpportunitySilverAmount(
          value: value,
          textKey: textKey,
          initiallyExpanded: true,
          wholeSilver: true,
          unicodeMinus: true,
          showPlus: headline,
          style: spec.typography.body.copyWith(
            fontSize: headline ? 20 : 15,
            fontWeight: FontWeight.w600,
            color: headline ? profitColor : spec.palette.text,
          ),
        );

    Widget silver(double size) => ExcludeSemantics(
      child: ModeItemIcon(
        controller: controller.modeController,
        catalogRepository: controller.catalog,
        name: 'Silver',
        size: size,
        showFrame: false,
      ),
    );

    Widget financialRow(
      String label,
      double? value, {
      bool withSilver = false,
    }) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(
              label,
              style: spec.typography.body.copyWith(
                fontSize: 13,
                color: spec.palette.textMuted,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Flexible(
            child: Align(
              alignment: Alignment.centerRight,
              child: Wrap(
                spacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  if (withSilver) silver(17),
                  amount(
                    value,
                    textKey: ValueKey(
                      'craft-per-item-$label:${quote.recipeName}',
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );

    return OpportunityItemRegion(
      controller: controller,
      name: quote.recipeName,
      stableId: 'craft-card:${quote.recipeName}',
      plannerMode: controller.preferences.mode,
      plannerVariantId: quote.selectedVariantId,
      onViewRecipe: _inspect,
      childHandlesFocus: true,
      child: OpportunityCardMotion(
        child: OpportunitySurface(
          key: ValueKey('craft-card:${quote.recipeName}'),
          role: AppSurfaceRole.card,
          padding: EdgeInsets.zero,
          decoration: finish.card.copyWith(
            border: Border.all(
              color: widget.expanded
                  ? spec.palette.primaryBright
                  : material.border,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              DecoratedBox(
                key: ValueKey('craft-header:${quote.recipeName}'),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.vertical(
                    top: const Radius.circular(7),
                    bottom: Radius.zero,
                  ),
                  gradient: material.headerWash,
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.vertical(
                    top: const Radius.circular(7),
                    bottom: Radius.zero,
                  ),
                  child: Stack(
                    children: [
                      Positioned.fill(
                        right: null,
                        child: IgnorePointer(
                          child: SizedBox(
                            width: 62,
                            child: DecoratedBox(
                              key: ValueKey(
                                'craft-colour-bay:${quote.recipeName}',
                              ),
                              decoration: BoxDecoration(
                                color: material.bay,
                                border: Border(
                                  right: BorderSide(
                                    color: material.glow.withAlpha(66),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      Material(
                        type: MaterialType.transparency,
                        child: Semantics(
                          expanded: widget.expanded,
                          child: InkWell(
                            key: ValueKey('craft-expand:${quote.recipeName}'),
                            onTap: widget.onToggle,
                            borderRadius: BorderRadius.circular(7),
                            hoverColor: spec.palette.primary.withAlpha(12),
                            focusColor: spec.palette.primary.withAlpha(28),
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(0, 11, 16, 11),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  SizedBox(
                                    width: 62,
                                    child: Center(
                                      child: OpportunityItemMount(
                                        key: ValueKey(
                                          'craft-artwork-rail:${quote.recipeName}',
                                        ),
                                        size: 46,
                                        child: _itemIcon(
                                          controller,
                                          quote.recipeName,
                                          40,
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      key: ValueKey(
                                        'craft-summary:${quote.recipeName}',
                                      ),
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        OpportunityCopyName(
                                          name: quote.recipeName,
                                          style: spec.typography.body.copyWith(
                                            fontSize: 17,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                        const SizedBox(height: 6),
                                        _CraftMarketCounts(
                                          stock: stock,
                                          color: material.badgeInk,
                                          fill: material.badgeFill,
                                          name: quote.recipeName,
                                        ),
                                        const SizedBox(height: 9),
                                        Semantics(
                                          hint: explanation,
                                          child: Wrap(
                                            spacing: 7,
                                            runSpacing: 2,
                                            crossAxisAlignment:
                                                WrapCrossAlignment.center,
                                            children: [
                                              ExcludeSemantics(
                                                child: ModeItemIcon(
                                                  controller:
                                                      controller.modeController,
                                                  catalogRepository:
                                                      controller.catalog,
                                                  name: 'Silver',
                                                  size: 22,
                                                  showFrame: false,
                                                ),
                                              ),
                                              amount(
                                                profit,
                                                headline: true,
                                                textKey: ValueKey(
                                                  'craft-per-item-profit:${quote.recipeName}',
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        if (experience != null) ...[
                                          const SizedBox(height: 5),
                                          Text(
                                            'EXP ${experience.estimated ? '~' : ''}${_quantity(experience.value)}',
                                            key: ValueKey(
                                              'craft-exp:${quote.recipeName}',
                                            ),
                                            style: spec.typography.meta.copyWith(
                                              color:
                                                  OpportunitiesVisualSpec.informationColor(
                                                    spec,
                                                  ),
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 7, 14, 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    financialRow(
                      'Sell ingredients',
                      comparison.allSales,
                      withSilver: true,
                    ),
                    Divider(
                      height: 10,
                      color: spec.palette.trim.withAlpha(110),
                    ),
                    Row(
                      children: [
                        for (final recipe in [false, true]) ...[
                          if (recipe) const SizedBox(width: 6),
                          Expanded(
                            child: Semantics(
                              expanded: widget.expanded && _recipe == recipe,
                              child: OpportunityButton(
                                key: ValueKey(
                                  '${recipe ? 'craft-recipe-button' : 'craft-expand-button'}:${quote.recipeName}',
                                ),
                                selected: widget.expanded && _recipe == recipe,
                                minimumSize: const Size(0, 38),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 8,
                                ),
                                onPressed: () => _togglePanel(recipe: recipe),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      recipe
                                          ? Icons.menu_book_outlined
                                          : Icons.balance,
                                      size: 16,
                                    ),
                                    const SizedBox(width: 6),
                                    Flexible(
                                      child: Text(
                                        recipe ? 'Recipe' : 'Craft or sell',
                                        textAlign: TextAlign.center,
                                        style: spec.typography.body.copyWith(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 4),
                                    Icon(
                                      widget.expanded && _recipe == recipe
                                          ? Icons.expand_less
                                          : Icons.expand_more,
                                      size: 14,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              if (widget.expanded && !_recipe)
                Container(
                  key: ValueKey('craft-inline-details:${quote.recipeName}'),
                  padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
                  decoration: BoxDecoration(
                    color: material.wash.withValues(alpha: .06),
                    border: Border(
                      top: BorderSide(color: spec.palette.trim.withAlpha(110)),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          for (final all in [false, true]) ...[
                            if (all) const SizedBox(width: 6),
                            Expanded(
                              child: OpportunityButton.label(
                                all
                                    ? 'All owned'
                                    : quote.usesInventory
                                    ? 'Your inventory'
                                    : 'Buy ingredients',
                                key: ValueKey(
                                  'craft-scenario-${all ? 'all' : 'inventory'}:${quote.recipeName}',
                                ),
                                selected: _allOwned == all,
                                minimumSize: const Size(0, 40),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 9,
                                ),
                                onPressed: () =>
                                    setState(() => _allOwned = all),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Sales after tax',
                        style: spec.typography.meta.copyWith(
                          fontSize: 12,
                          color: material.mutedInk,
                        ),
                      ),
                      if (_allOwned) ...[
                        const SizedBox(height: 6),
                        Text(
                          'If you already had every ingredient',
                          style: spec.typography.meta.copyWith(
                            fontSize: 12,
                            color: material.mutedInk,
                          ),
                        ),
                      ],
                      const SizedBox(height: 6),
                      financialRow(quote.recipeName, comparison.sale),
                      if (!_allOwned)
                        financialRow(
                          'Buy missing materials',
                          comparison.purchases == null
                              ? null
                              : -comparison.purchases!,
                        ),
                      if ((comparison.extraCosts ?? 0) > 0)
                        financialRow('Extra costs', -comparison.extraCosts!),
                      if (!_allOwned || (comparison.extraCosts ?? 0) > 0) ...[
                        Divider(
                          height: 12,
                          color: spec.palette.trim.withAlpha(110),
                        ),
                        financialRow(
                          _allOwned ? 'After costs' : 'After purchases',
                          _allOwned
                              ? comparison.allOwnedReturn
                              : comparison.afterPurchases,
                        ),
                      ],
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 7),
                        child: Row(
                          children: [
                            Expanded(
                              child: Divider(
                                color: spec.palette.trim.withAlpha(110),
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                              ),
                              child: Text('or', style: spec.typography.meta),
                            ),
                            Expanded(
                              child: Divider(
                                color: spec.palette.trim.withAlpha(110),
                              ),
                            ),
                          ],
                        ),
                      ),
                      financialRow(
                        _allOwned
                            ? 'Sell all materials'
                            : 'Sell owned materials',
                        _allOwned ? comparison.allSales : comparison.ownedSales,
                      ),
                      const SizedBox(height: 10),
                      Container(
                        key: ValueKey('craft-verdict:${quote.recipeName}'),
                        padding: const EdgeInsets.all(12),
                        decoration: finish.card.copyWith(
                          border: Border.all(color: spec.palette.trim),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              switch (decision) {
                                OpportunityCraftDecision.craft =>
                                  'Crafting is more profitable',
                                OpportunityCraftDecision.sell =>
                                  'Selling ingredients is more profitable',
                                OpportunityCraftDecision.equal =>
                                  'About the same',
                                OpportunityCraftDecision.unknown =>
                                  'Comparison unavailable',
                              },
                              style: spec.typography.body.copyWith(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            if (decision == OpportunityCraftDecision.craft ||
                                decision == OpportunityCraftDecision.sell) ...[
                              const SizedBox(height: 6),
                              Wrap(
                                spacing: 6,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                children: [
                                  silver(20),
                                  amount(
                                    profit!.abs(),
                                    textKey: ValueKey(
                                      'craft-comparison-gain:${quote.recipeName}',
                                    ),
                                  ),
                                  Text('more', style: spec.typography.meta),
                                ],
                              ),
                            ],
                          ],
                        ),
                      ),
                      if (decision == OpportunityCraftDecision.unknown)
                        Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(
                            'Missing current sale or ingredient prices',
                            style: spec.typography.meta.copyWith(
                              color: spec.palette.warning,
                            ),
                          ),
                        ),
                      if (!_allOwned && quote.hasEstimatedInputs)
                        Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(
                            'Estimated purchases',
                            style: spec.typography.meta.copyWith(
                              color: spec.palette.warning,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),

              if (widget.expanded && _recipe)
                Container(
                  key: ValueKey('craft-inline-recipe:${quote.recipeName}'),
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(bottom: 7),
                        child: Text('Per craft', style: spec.typography.meta),
                      ),
                      for (final ingredient in quote.ingredients)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 7),
                          child: _CraftIngredientInlay(
                            controller: controller,
                            recipeName: quote.recipeName,
                            ingredient: ingredient,
                          ),
                        ),
                    ],
                  ),
                ),
              if (widget.expanded)
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 8, 14, 12),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      ValueListenableBuilder<ModeState>(
                        valueListenable: controller.modeController.state,
                        builder: (context, state, _) {
                          final favorite = state.favoriteRecipes.any(
                            (name) =>
                                name.toLowerCase() ==
                                quote.recipeName.toLowerCase(),
                          );
                          return OpportunityButton(
                            key: ValueKey(
                              'craft-favourite:${quote.recipeName}',
                            ),
                            role: AppButtonRole.icon,
                            semanticLabel:
                                '${favorite ? 'Remove' : 'Add'} favourite ${quote.recipeName}',
                            selected: favorite,
                            onPressed: () => controller.modeController
                                .toggleFavorite(quote.recipeName),
                            child: Icon(
                              favorite ? Icons.star : Icons.star_border,
                              size: 18,
                            ),
                          );
                        },
                      ),
                      if (target != null && openPlanner != null)
                        OpportunityButton.label(
                          'Planner',
                          key: ValueKey('craft-planner:${quote.recipeName}'),
                          minimumSize: const Size(0, 32),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 9,
                            vertical: 6,
                          ),
                          onPressed: () => openPlanner(target),
                        ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CraftMarketCounts extends StatelessWidget {
  const _CraftMarketCounts({
    required this.stock,
    required this.color,
    required this.fill,
    required this.name,
    this.npc = false,
  });
  final bool npc;
  final OpportunityCardStock stock;
  final Color color;
  final Color fill;
  final String name;

  @override
  Widget build(BuildContext context) {
    final labels = <(IconData, String)>[
      if (npc)
        (Icons.person_outline, 'NPC')
      else ...[
        (
          stock.stock == null
              ? Icons.help_outline
              : stock.stock! > 0
              ? Icons.check
              : Icons.remove,
          'Stock ${stock.stock == null ? '—' : _quantity(stock.stock!)}',
        ),
        if ((stock.preorders ?? 0) > 0)
          (
            Icons.shopping_basket_outlined,
            'Preorders ${_quantity(stock.preorders!)}',
          ),
      ],
    ];
    return Semantics(
      label: npc
          ? 'Available from an NPC'
          : 'Stock: ${stock.stock == null ? 'not checked' : _quantity(stock.stock!)}\nPreorders: ${stock.preorders == null ? 'not checked' : _quantity(stock.preorders!)}',
      child: Wrap(
        key: ValueKey('craft-market-counts:$name'),
        spacing: 6,
        runSpacing: 4,
        children: [
          for (final entry in labels)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
              decoration: BoxDecoration(
                color: fill,
                border: Border.all(color: color.withAlpha(100)),
                borderRadius: BorderRadius.circular(3),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(entry.$1, size: 13, color: color),
                  const SizedBox(width: 4),
                  Flexible(
                    child: Text(
                      entry.$2,
                      style: context.visualTheme.typography.meta.copyWith(
                        fontSize: 12,
                        color: color,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// Availability describes the source, never ownership or profitability.
class _CraftIngredientInlay extends StatelessWidget {
  const _CraftIngredientInlay({
    required this.controller,
    required this.recipeName,
    required this.ingredient,
  });
  final OpportunitiesController controller;
  final String recipeName;
  final OpportunityIngredientQuote ingredient;

  @override
  Widget build(BuildContext context) {
    final spec = context.visualTheme;
    final stock = OpportunityCardStock(
      ingredient.market,
      controller.clock(),
      controller.cachedMarketMaxAge,
    );
    final npc = (ingredient.npcUnitPrice ?? 0) > 0;
    final material = OpportunityCraftCardMaterial.forSpec(
      spec,
      npc ? OpportunityStockTone.available : stock.tone,
    );
    final npcInk = material.readable(spec.palette.warning, badge: true);
    return OpportunityItemRegion(
      controller: controller,
      name: ingredient.name,
      stableId: 'craft-inline-input:$recipeName:${ingredient.name}',
      child: ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: DecoratedBox(
          key: ValueKey('craft-recipe-row:$recipeName:${ingredient.name}'),
          decoration: BoxDecoration(
            gradient: OpportunityGlassFinish.of(context).cardSurface,
            border: Border.all(color: spec.palette.trim.withAlpha(150)),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Stack(
            children: [
              Positioned(
                top: 1,
                bottom: 1,
                left: 1,
                width: 43,
                child: DecoratedBox(
                  key: ValueKey(
                    'craft-ingredient-bay:$recipeName:${ingredient.name}',
                  ),
                  decoration: BoxDecoration(color: material.bay),
                  child: Center(
                    child: _itemIcon(controller, ingredient.name, 32),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(53, 9, 9, 9),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          flex: 3,
                          child: OpportunityCopyName(
                            name: ingredient.name,
                            style: spec.typography.body.copyWith(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Align(
                            alignment: Alignment.topRight,
                            child: Text(
                              '×${_quantity(ingredient.quantityPerCraft)}',
                              textAlign: TextAlign.right,
                              style: spec.typography.meta.copyWith(
                                fontSize: 14,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 5),
                    _CraftMarketCounts(
                      stock: stock,
                      npc: npc,
                      color: npc ? npcInk : material.badgeInk,
                      fill: npc
                          ? npcInk.withValues(alpha: .07)
                          : material.badgeFill,
                      name: '$recipeName:${ingredient.name}',
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
