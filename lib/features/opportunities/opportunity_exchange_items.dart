part of 'opportunities_workspace.dart';

RecipeBookItemInfo _exchangeItemInfo(
  OpportunitiesController controller,
  ExchangeItem item,
) {
  final base =
      controller.itemInfoController.itemInfoFor(
        item.name,
        mode: controller.modeController.mode,
      ) ??
      RecipeBookItemInfo(title: item.name, kind: 'Item', summary: '');
  final details = exchangeItemDetails[item.id];
  final currency = exchangeCatalog
      .where((c) => c.item.id == item.id)
      .firstOrNull;
  if (currency != null) {
    final locations = currency.routes
        .where((r) => !r.directVendorSale)
        .map((r) => r.location)
        .toSet();
    return base.copyWith(
      kind: 'Exchange item',
      summary: currency.sourceActivity,
      uses: [for (final location in locations) 'Exchange at $location.'],
      notes: currency.notes,
    );
  }
  if (details != null) {
    return base.copyWith(
      kind: details.kind,
      summary: details.summary,
      uses: {...base.uses, ...details.uses}.toList(),
      effects: base.effects.isEmpty ? details.effects : base.effects,
      acquisitionNotes: {
        ...base.acquisitionNotes,
        ...details.howToObtain,
      }.toList(),
      craftUses: [
        ...base.craftUses,
        for (final recipe in details.recipes)
          if (!base.craftUses.any((use) => use.output == recipe.output))
            RecipeBookCraftUse(
              output: recipe.output,
              formulas: [
                RecipeBookFormula(
                  outputName: recipe.output,
                  type: 'Crafted',
                  method: recipe.method,
                  baseOutput: 1,
                  ingredients: [
                    for (final input in recipe.ingredients.entries)
                      Ingredient(
                        name: input.key,
                        quantity: input.value,
                        options: const [],
                        substituteGroup: null,
                        substituteRatios: const {},
                      ),
                  ],
                ),
              ],
            ),
      ],
      notes: {...base.notes, ...details.notes}.toList(),
    );
  }
  final valks = RegExp(r'^Advice of Valks \(\+(\d+)\)$').firstMatch(item.name);
  if (valks != null) {
    return base.copyWith(
      kind: 'Enhancement',
      summary: 'Grants a +${valks[1]} Enhancement Chance.',
      notes: ['Use when your current Enhancement Chance is 0.'],
    );
  }
  if (item.name.startsWith('[Title] ')) {
    return base.copyWith(
      kind: 'Title',
      summary: 'Unlocks the ${item.name.substring(8)} title.',
    );
  }
  return base;
}

/// Facts belong inside the open exchange, not behind its item's hover menu.
/// The surrounding dialog already owns the title, surface and scrolling.
class _ExchangeReferenceDetails extends StatelessWidget {
  const _ExchangeReferenceDetails({
    required this.controller,
    required this.quote,
  });

  final OpportunitiesController controller;
  final ExchangeQuote quote;

  @override
  Widget build(BuildContext context) {
    final route = quote.route;
    final items = <int, ExchangeItem>{
      for (final item in <ExchangeItem?>[
        route.rewardContainer,
        ...route.rewards.map((reward) => reward.item),
      ].whereType<ExchangeItem>())
        item.id: item,
    };
    final titleItem =
        route.rewardContainer ??
        (route.rewards.length == 1 ? route.rewards.single.item : null);
    final spec = context.visualTheme;
    final openPlanner = OpportunityItemActionsScope.maybeOf(
      context,
    )?.openPlannerTarget;
    final children = <Widget>[];
    for (final item in items.values) {
      final original = _exchangeItemInfo(controller, item);
      final info = withReadableRecipeBookSections(
        original.copyWith(
          // Only the exact route shown by Give/Receive is redundant. Keep other
          // recipes and all researched NPC, gathering and availability facts.
          acquisitionFormulas: original.acquisitionFormulas
              .where((formula) {
                final reward = route.rewards
                    .where((reward) => reward.item?.id == item.id)
                    .firstOrNull;
                return !(reward != null &&
                    formula.method == 'NPC Exchange' &&
                    formula.outputName == item.name &&
                    formula.baseOutput == reward.quantity &&
                    formula.ingredients.length == 1 &&
                    formula.ingredients.single.name ==
                        quote.currency.item.name &&
                    formula.ingredients.single.quantity == route.inputCount);
              })
              .toList(growable: false),
        ),
      );
      if (info.summary.isEmpty &&
          info.effects.isEmpty &&
          info.uses.isEmpty &&
          info.craftUses.isEmpty &&
          info.acquisitionFormulas.isEmpty &&
          info.acquisitionNotes.isEmpty &&
          (info.example?.isEmpty ?? true) &&
          info.notes.isEmpty) {
        continue;
      }
      if (titleItem?.id != item.id) {
        children.add(
          Padding(
            padding: const EdgeInsets.only(top: ItemDetailStyle.sectionGap),
            child: Row(
              children: [
                _exchangeIcon(controller, item, ItemDetailStyle.recipeIcon),
                const SizedBox(width: 10),
                Expanded(
                  child: _exchangeName(
                    controller,
                    item,
                    style: ItemDetailStyle.recipe(spec),
                  ),
                ),
              ],
            ),
          ),
        );
      }
      children.add(
        ItemReferenceSections(
          key: ValueKey('exchange-reference:${item.id}'),
          controller: controller.itemInfoController,
          mode: controller.modeController.mode,
          name: item.name,
          info: info,
          spec: spec,
          onCopyItemName: (name) => copyOpportunityItemName(context, name),
          onRecipeActivated: () => Navigator.of(context).pop(),
          onUseFormula: openPlanner == null
              ? null
              : (formula) async {
                  final navigator = Navigator.of(context);
                  final route = ModalRoute.of(context);
                  navigator.pop();
                  // Finish the closing animation before the retained workspace
                  // disables its tickers on the switch back to Planner.
                  await route?.completed;
                  if (!navigator.mounted) return;
                  openPlanner(
                    PlannerTargetRequest(
                      exactName: formula.outputName,
                      mode: formula.mode!,
                      variantId: formula.variantId,
                    ),
                  );
                },
        ),
      );
    }
    if (children.isEmpty) return const SizedBox.shrink();
    return SelectionArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      ),
    );
  }
}

Widget _exchangeItemRegion(
  OpportunitiesController controller,
  ExchangeItem item, {
  required Widget child,
  String anchor = 'icon',
}) => Builder(
  builder: (context) {
    final info = _exchangeItemInfo(controller, item);
    final selected = _ingredientRecipe(controller, item.name);
    return OpportunityItemRegion(
      controller: controller,
      name: item.name,
      stableId: 'exchange-$anchor:${item.id}',
      primaryOpensItemInfo: anchor == 'icon',
      itemInfo: info,
      itemInfoIcon: _exchangeArtwork(controller, item, 36),
      resolvePlannerTarget: () => selected == null
          ? null
          : _ingredientPlannerTarget(controller, selected),
      onViewRecipe: selected == null
          ? null
          : () {
              final inspection = controller.inspectRecipe(
                recipe: selected.recipe,
                itemName: selected.itemName,
                selectedVariantId: selected.variantId,
              );
              unawaited(
                _craftDetails(
                  context,
                  controller,
                  inspection.quote,
                  rootRecipe: selected.recipe,
                  rareOutput: selected.rare,
                ),
              );
            },
      child: anchor == 'icon'
          ? RecipeBookItemInfoHover(
              controller: controller.itemInfoController,
              name: item.name,
              info: info,
              referenceIcon: _exchangeArtwork(controller, item, 36),
              // Long references can overlap the icon. Keep primary and secondary
              // clicks available; clicking the icon opens the interactive card.
              interactivePreview: false,
              child: child,
            )
          : child,
    );
  },
);

Widget _exchangeName(
  OpportunitiesController controller,
  ExchangeItem item, {
  String? displayLabel,
  TextStyle? style,
}) => _exchangeItemRegion(
  controller,
  item,
  anchor: 'name',
  child: OpportunityCopyName(
    name: item.name,
    displayLabel: displayLabel,
    style: style,
  ),
);

bool _hasExchangePreorders(
  OpportunitiesController controller,
  ExchangeItem item,
) {
  final quote = controller.market.items['${item.id}'];
  return quote?.bookIsFresh(
            controller.clock(),
            controller.cachedMarketMaxAge,
          ) ==
          true &&
      quote!.bids!.any((level) => level.quantity > 0);
}

bool _showExchangeValue(ExchangeQuote quote) =>
    quote.displayQuote.netProceeds != null &&
    (quote.route.directVendorSale ||
        quote.route.rewards.every(
          (reward) =>
              reward.item?.marketable == true ||
              (reward.item?.name.startsWith('Gold Bar ') == true &&
                  reward.item?.vendorSellPrice != null),
        ));
