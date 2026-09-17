import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/opportunities/exchange_catalog.dart';
import '../../data/opportunities/market_eligibility.dart';
import '../../domain/formatting/planner_formatters.dart';
import '../../domain/market/market_calculations.dart';
import '../../domain/models/catalog_models.dart';
import '../../domain/models/craft_mode.dart';
import '../../domain/opportunities/exchange_models.dart';
import '../../domain/opportunities/opportunity_best_use.dart';
import '../../domain/opportunities/opportunity_calculator.dart';
import '../../domain/opportunities/opportunity_market_models.dart';
import '../../domain/opportunities/raw_ingredient_sales.dart';
import '../../domain/planner/ingredient_quality.dart';
import '../../domain/state/planner_state.dart';
import '../../domain/state/state_copy.dart';
import '../../shared/formatting/silver_price_input_formatter.dart';
import '../../shared/overlays/anchored_popover.dart';
import '../../visual/visual.dart';
import '../data/market_bonus_icon.dart';
import '../planner/planner_contracts.dart'
    show PlannerTargetRequest, PlannerGatherDemand;
import '../planner/planner_shared.dart'
    show PlannerTargetChooser, PlannerCommandTarget;
import '../recipe_book/recipe_book_item_info_view.dart';
import '../shared/mode_item_icon.dart';
import 'opportunities_controller.dart';
import 'opportunities_item_actions.dart';
import 'opportunities_theme.dart';
import 'opportunities_visuals.dart';
import 'opportunity_inventory_input.dart';
import 'opportunity_refresh_control.dart';

part 'opportunity_substitutes.dart';
part 'opportunity_detail_inputs.dart';
part 'opportunity_crafting_toolbar.dart';
part 'opportunity_best_use_pane.dart';

class OpportunitiesWorkspace extends StatefulWidget {
  const OpportunitiesWorkspace({
    required this.controller,
    this.active = true,
    super.key,
  });
  final OpportunitiesController controller;
  final bool active;

  @override
  State<OpportunitiesWorkspace> createState() => _OpportunitiesWorkspaceState();
}

class _OpportunitiesWorkspaceState extends State<OpportunitiesWorkspace> {
  final _navigator = GlobalKey<NavigatorState>();

  @override
  void didUpdateWidget(OpportunitiesWorkspace oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!oldWidget.active && widget.active) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !widget.active) return;
        final navigator = _navigator.currentState;
        if (navigator != null && navigator.canPop()) {
          navigator.focusNode.requestFocus();
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) => AppOverlayCoordinatorHost(
    onEscapeUnhandled: () => _navigator.currentState?.maybePop(),
    child: Navigator(
      key: _navigator,
      onGenerateRoute: (settings) => MaterialPageRoute<void>(
        settings: settings,
        builder: (_) => _OpportunitiesContent(controller: widget.controller),
      ),
    ),
  );
}

class _OpportunitiesContent extends StatelessWidget {
  const _OpportunitiesContent({required this.controller});
  final OpportunitiesController controller;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    builder: (context, _) => OpportunitiesTheme(
      child: Builder(
        builder: (context) {
          final spec = context.visualTheme;
          return TooltipTheme(
            data: TooltipThemeData(
              decoration: BoxDecoration(
                gradient: OpportunitiesVisualSpec.overlay,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: spec.palette.trim),
              ),
              textStyle: spec.typography.body.copyWith(
                color: spec.palette.text,
              ),
              padding: const EdgeInsets.all(12),
              constraints: const BoxConstraints(maxWidth: 340),
              waitDuration: const Duration(milliseconds: 450),
            ),
            child: ScrollConfiguration(
              behavior: const AppScrollBehavior(),
              child: _OpportunityBody(controller: controller),
            ),
          );
        },
      ),
    ),
  );
}

class _OpportunityBody extends StatelessWidget {
  const _OpportunityBody({required this.controller});
  final OpportunitiesController controller;

  @override
  Widget build(BuildContext context) {
    if (controller.loading) {
      return const Center(child: CircularProgressIndicator());
    }
    final p = controller.preferences;
    final spec = context.visualTheme;
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            key: const ValueKey('opportunities-header'),
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 24,
            runSpacing: 12,
            children: [
              Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 32,
                runSpacing: 8,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Image.asset(
                        'assets/opportunities/items/66771.webp',
                        key: const ValueKey('opportunities-brand-icon'),
                        width: 32,
                        height: 32,
                        filterQuality: FilterQuality.high,
                      ),
                      const SizedBox(width: 12),
                      Text('Opportunities', style: spec.typography.display),
                    ],
                  ),
                  _DeskTabs(
                    choices: [
                      (
                        'Crafting',
                        p.section == 'crafting',
                        () => controller.change((p) => p.section = 'crafting'),
                      ),
                      (
                        'Exchanges',
                        p.section == 'exchanges',
                        () => controller.change((p) => p.section = 'exchanges'),
                      ),
                      (
                        'Best use',
                        p.section == 'best-use',
                        () => controller.change((p) => p.section = 'best-use'),
                      ),
                    ],
                  ),
                ],
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Wrap(
                    spacing: 12,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      if (p.section == 'crafting')
                        _CraftMasteryControl(controller: controller),
                      OpportunityButton.label(
                        'Market · ${p.region.toUpperCase()}',
                        key: const ValueKey('opportunities-market'),
                        minimumSize: const Size(0, 40),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        onPressed: () => _taxDialog(context, controller),
                      ),
                      OpportunityRefreshControl(controller: controller),
                    ],
                  ),
                  const SizedBox(height: 8),
                  _marketTimestamp(context, controller),
                ],
              ),
            ],
          ),
          Column(
            key: const ValueKey('opportunities-market-progress'),
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _marketLoadProgress(
                context,
                controller.summaryStatus,
                label: controller.summaryStatus.loading
                    ? 'Loading prices'
                    : 'Prices',
              ),
              _marketLoadProgress(
                context,
                controller.detailStatus,
                label:
                    p.section != 'exchanges' &&
                        (p.craftSort == 'preorders' || p.demandOnly)
                    ? 'Preorders'
                    : 'Market details',
              ),
              for (final message in <String?>[
                controller.saveError,
                controller.notice,
              ].whereType<String>().toSet())
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Semantics(
                    liveRegion: true,
                    child: Text(
                      message,
                      style: spec.typography.meta.copyWith(
                        color: spec.palette.warning,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          SizedBox(height: p.section != 'exchanges' ? 16 : 24),
          Expanded(
            // A single layout at every width preserves both panes and their
            // editing/scroll state when the header wraps.
            child: IndexedStack(
              key: const ValueKey('opportunities-panes'),
              index: switch (p.section) {
                'exchanges' => 1,
                'best-use' => 2,
                _ => 0,
              },
              children: [
                _CraftingPane(controller: controller),
                _ExchangePane(controller: controller),
                _BestUsePane(controller: controller),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

Widget _marketLoadProgress(
  BuildContext context,
  OpportunityMarketLoadStatus status, {
  required String label,
}) {
  if (!status.loading && status.failed == 0 && !status.blocked) {
    return const SizedBox.shrink();
  }
  final spec = context.visualTheme;
  return Padding(
    padding: const EdgeInsets.only(top: 8),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '$label · ${status.loaded} / ${status.total}'
          '${status.failed > 0 ? ' · ${status.failed} failed' : ''}',
          style: spec.typography.meta.copyWith(
            color: status.failed > 0 || status.blocked
                ? spec.palette.warning
                : null,
          ),
        ),
        if (status.loading) ...[
          const SizedBox(height: 4),
          LinearProgressIndicator(
            value: status.total == 0 ? null : status.loaded / status.total,
            minHeight: 2,
            semanticsLabel:
                '$label: ${status.loaded} of ${status.total} loaded',
          ),
        ],
      ],
    ),
  );
}

class _DeskTabs extends StatelessWidget {
  const _DeskTabs({required this.choices});
  final List<(String, bool, VoidCallback)> choices;

  @override
  Widget build(BuildContext context) => Wrap(
    key: const ValueKey('opportunities-sections'),
    spacing: 8,
    runSpacing: 8,
    children: [
      for (final choice in choices)
        OpportunityButton.label(
          choice.$1,
          key: ValueKey('opportunities-section-${choice.$1.toLowerCase()}'),
          role: AppButtonRole.infoChip,
          selected: choice.$2,
          minimumSize: const Size(0, 40),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          onPressed: choice.$3,
        ),
    ],
  );
}

class _CraftingPane extends StatelessWidget {
  const _CraftingPane({required this.controller});
  final OpportunitiesController controller;
  @override
  Widget build(BuildContext context) {
    final p = controller.preferences;
    final spec = context.visualTheme;
    final rows = controller.visibleQuotes;
    return _cardList(
      context,
      count: rows.length,
      keyName: 'craft-opportunities',
      minimumCardWidth: 400,
      maximumCardWidth: rows.length <= 2 ? 480 : 560,
      maximumColumns: 4,
      header: Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _CraftingToolbar(controller: controller),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${rows.length} ${rows.length == 1 ? 'recipe' : 'recipes'}'
                    '${p.demandOnly && controller.demandPendingCount > 0 ? ' · ${controller.demandPendingCount} demand unchecked' : ''}',
                    style: spec.typography.meta,
                  ),
                ),
                _info(context, 'Crafting profit', [
                  'Buy the ingredients shown, then make the recipe. Nothing is crafted further down the chain.',
                  'Profit is the main product’s sale price after tax, minus ingredients. Items you own are still priced as bought.',
                  'Rare results, byproducts, tool and buff costs are not included.',
                  'Check the recipe’s level and knowledge requirements in game. The estimate assumes successful crafts.',
                  'A high price does not guarantee a sale.',
                  'Shared across tabs. Reused for five minutes; checked again when needed.',
                ]),
              ],
            ),
            if (rows.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 28),
                child: controller.calculating
                    ? const Center(child: CircularProgressIndicator())
                    : _empty(
                        context,
                        'No matches',
                        p.demandOnly && controller.demandPendingCount > 0
                            ? 'Demand has not been checked for all recipes.'
                            : 'Change the search or filters.',
                      ),
              ),
          ],
        ),
      ),
      builder: (index) =>
          _CraftCard(controller: controller, quote: rows[index]),
    );
  }
}

class _CraftCard extends StatefulWidget {
  const _CraftCard({
    required this.controller,
    required this.quote,
    this.bestUse,
  });
  final OpportunitiesController controller;
  final OpportunityQuote quote;
  final OpportunityBestUseQuote? bestUse;

  @override
  State<_CraftCard> createState() => _CraftCardState();
}

class _CraftCardState extends State<_CraftCard> {
  OpportunitiesController get controller => widget.controller;
  OpportunityQuote get quote => widget.quote;

  @override
  void initState() {
    super.initState();
    _registerMarketInterest();
  }

  @override
  void didUpdateWidget(covariant _CraftCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != controller) {
      oldWidget.controller.releaseCardMarketInterest(this);
    }
    _registerMarketInterest();
  }

  void _registerMarketInterest() => controller.setCardMarketInterest(
    this,
    recipeName: quote.recipeName,
    mode: widget.bestUse?.mode ?? controller.preferences.mode,
  );

  @override
  void dispose() {
    controller.releaseCardMarketInterest(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final spec = context.visualTheme;
    final use = widget.bestUse;
    final showExperience =
        use == null && controller.preferences.craftSort == 'exp';
    final experience = showExperience
        ? controller.experienceForQuote(quote)
        : null;
    final total = use == null
        ? quote.profitFor(controller.craftSaleMode)
        : use.extraProfitPerUnit;
    final estimated = use?.isEstimated ?? quote.hasEstimatedInputs;
    final note = use != null && total == null
        ? 'Some prices are missing'
        : _craftCardNote(controller, quote, recipe: use?.recipe);
    final scope = _craftScope(controller, quote, recipe: use?.recipe);
    const artworkRailWidth = 76.0;
    void open() => _craftDetails(context, controller, quote, bestUse: use);
    return OpportunityItemRegion(
      controller: controller,
      name: quote.recipeName,
      stableId: 'craft-card:${quote.recipeName}',
      plannerMode: use?.mode ?? controller.preferences.mode,
      plannerVariantId: quote.selectedVariantId,
      onViewRecipe: open,
      childHandlesFocus: true,
      child: OpportunityCardMotion(
        child: OpportunitySurface(
          key: ValueKey('craft-card:${quote.recipeName}'),
          role: AppSurfaceRole.card,
          padding: EdgeInsets.zero,
          decoration: OpportunitiesVisualSpec.recipeCard,
          child: InkWell(
            onTap: open,
            borderRadius: BorderRadius.circular(12),
            hoverColor: spec.palette.primary.withAlpha(12),
            focusColor: spec.palette.primary.withAlpha(28),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Stack(
                children: [
                  Positioned.fill(
                    right: null,
                    child: SizedBox(
                      key: ValueKey('craft-artwork-rail:${quote.recipeName}'),
                      width: artworkRailWidth,
                      child: DecoratedBox(
                        decoration: OpportunitiesVisualSpec.recipeArtworkRail,
                        child: Center(
                          child: _itemIcon(
                            controller,
                            quote.recipeName,
                            40,
                            framed: true,
                            mode: use?.mode,
                          ),
                        ),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(left: artworkRailWidth),
                    child: KeyedSubtree(
                      key: ValueKey('craft-summary:${quote.recipeName}'),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          OpportunityCopyName(
                                            name: quote.recipeName,
                                            style: spec.typography.section
                                                .copyWith(
                                                  fontSize:
                                                      OpportunitiesVisualSpec
                                                          .cardNameFontSize,
                                                  fontWeight: FontWeight.w700,
                                                ),
                                          ),
                                          if (scope.isNotEmpty) ...[
                                            const SizedBox(height: 4),
                                            Text(
                                              scope,
                                              style: spec.typography.meta,
                                            ),
                                          ],
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    ExcludeFocus(
                                      child: OpportunityButton.icon(
                                        icon: const Icon(
                                          Icons.arrow_forward,
                                          size: 18,
                                        ),
                                        semanticLabel:
                                            'Calculation for ${quote.recipeName}',
                                        onPressed: open,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 7),
                                _MetricColumns(
                                  children: [
                                    _metric(
                                      context,
                                      use == null
                                          ? 'Profit'
                                          : 'Extra profit / item',
                                      _estimateValue(_silver(total), estimated),
                                      large: true,
                                      valueFontSize: OpportunitiesVisualSpec
                                          .cardPrimaryValueFontSize,
                                      valueFontWeight: FontWeight.w600,
                                      labelFontSize: OpportunitiesVisualSpec
                                          .cardLabelFontSize,
                                      color: total == null
                                          ? spec.palette.textMuted
                                          : total > 0
                                          ? spec.palette.success
                                          : spec.palette.danger,
                                    ),
                                    if (showExperience)
                                      experience == null
                                          ? SizedBox.shrink(
                                              key: ValueKey(
                                                'craft-unknown-exp:${quote.recipeName}',
                                              ),
                                            )
                                          : _metric(
                                              context,
                                              'EXP',
                                              '${experience.estimated ? '~' : ''}${_quantity(experience.value)}',
                                              valueFontSize: 18,
                                              valueFontWeight: FontWeight.w600,
                                              labelFontSize:
                                                  OpportunitiesVisualSpec
                                                      .cardLabelFontSize,
                                              color: OpportunitiesVisualSpec
                                                  .experienceColor,
                                            ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          DecoratedBox(
                            key: ValueKey('craft-footer:${quote.recipeName}'),
                            decoration: OpportunitiesVisualSpec.recipeFooter,
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(16, 7, 16, 10),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  _MetricColumns(
                                    children: [
                                      _market(
                                        context,
                                        controller.outputMarketFor(
                                          quote.recipeName,
                                          mode: use?.mode,
                                        ),
                                        controller.clock(),
                                        maxAge: controller.cachedMarketMaxAge,
                                        valueFontSize: OpportunitiesVisualSpec
                                            .cardSecondaryValueFontSize,
                                        labelFontSize: OpportunitiesVisualSpec
                                            .cardLabelFontSize,
                                      ),
                                      _metric(
                                        context,
                                        use == null
                                            ? 'Investment'
                                            : 'Other costs / item',
                                        _estimateValue(
                                          _silver(
                                            use == null
                                                ? quote.totalCost
                                                : use.otherInputCost == null
                                                ? null
                                                : use.otherInputCost! /
                                                      use.selectedQuantity,
                                          ),
                                          estimated,
                                        ),
                                        valueFontSize: OpportunitiesVisualSpec
                                            .cardSecondaryValueFontSize,
                                        labelFontSize: OpportunitiesVisualSpec
                                            .cardLabelFontSize,
                                        color: spec.palette.textMuted,
                                      ),
                                    ],
                                  ),
                                  if (note != null) ...[
                                    const SizedBox(height: 12),
                                    Text(
                                      note,
                                      style: spec.typography.meta.copyWith(
                                        fontSize: OpportunitiesVisualSpec
                                            .cardLabelFontSize,
                                        color: spec.palette.warning,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

double? _craftRevenue(
  OpportunitiesController controller,
  OpportunityQuote quote,
) =>
    quote.hasCustomSalePrice ||
        controller.craftSaleMode == OpportunitySaleMode.listing
    ? quote.listingRevenue
    : quote.buyerRevenue;

String _craftScope(
  OpportunitiesController controller,
  OpportunityQuote quote, {
  Recipe? recipe,
}) {
  final formula = (recipe ?? controller.recipes[quote.recipeName])
      ?.resolveVariant(quote.selectedVariantId);
  final batch = quote.batchMultiplier > 1 || (formula?.baseOutput ?? 1) > 1;
  final output = quote.expectedOutput == null
      ? '—'
      : _quantity(quote.expectedOutput!);
  if (quote.crafts > 1) {
    return '${quote.crafts} ${batch ? 'batches' : 'crafts'} · $output items';
  }
  return batch ? '$output items per batch' : '';
}

String? _craftCardNote(
  OpportunitiesController controller,
  OpportunityQuote quote, {
  Recipe? recipe,
}) {
  final outputId =
      recipe?.marketId ??
      controller.recipes[quote.recipeName]?.marketId ??
      controller.catalog.bundledMarketId(quote.recipeName);
  if (outputId != null && !isOpportunityMarketRequestEligible(outputId)) {
    return 'Not sold on the market';
  }
  if (quote.profitFor(controller.craftSaleMode) == null) {
    if (quote.issues.contains(OpportunityIssue.invalidSalePrice)) return null;
    if (quote.issues.contains(OpportunityIssue.outputUnlisted)) {
      return 'Cannot list this item';
    }
    if (quote.ingredients.any((item) => item.costForCalculation == null)) {
      if (quote.ingredients.any(
        (item) =>
            item.costForCalculation == null && _ingredientIsNonMarket(item),
      )) {
        return 'Some ingredients are not sold on the market';
      }
      return 'Some prices are missing';
    }
    return 'Check prices';
  }

  return null;
}

Widget _craftSummary(
  BuildContext context,
  OpportunitiesController controller,
  OpportunityQuote quote, {
  Key? key,
  bool showDetails = false,
  OpportunityRecipeInspection? inspection,
}) {
  final palette = context.visualTheme.palette;
  final total = quote.profitFor(controller.craftSaleMode);
  return KeyedSubtree(
    key: key,
    child: _MetricColumns(
      children: [
        _metric(
          context,
          'Profit',
          _estimateValue(_silver(total), quote.hasEstimatedInputs),
          estimateExplanation: _quoteEstimateExplanation(quote),
          color: total == null
              ? palette.textMuted
              : total > 0
              ? palette.success
              : palette.danger,
          large: true,
          detailsKey: const ValueKey('craft-calculation-info'),
          detailsLabel: 'About this calculation',
          onDetails: showDetails
              ? () => _craftAbout(
                  context,
                  controller,
                  quote,
                  inspection: inspection,
                )
              : null,
        ),
        _market(
          context,
          inspection == null
              ? controller.outputMarketFor(quote.recipeName)
              : quote.outputMarket,
          controller.clock(),
          large: true,
          maxAge: controller.cachedMarketMaxAge,
          onDetails: showDetails
              ? () => _withMarketDepth(
                  controller,
                  [
                    ?(inspection == null
                            ? controller.outputMarketFor(quote.recipeName)
                            : quote.outputMarket)
                        ?.itemId,
                  ],
                  () => _dialog(
                    context,
                    'Market details',
                    (context) => AnimatedBuilder(
                      animation: controller,
                      builder: (context, _) => Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _marketDepthStatus(context, controller),
                          _bookDetails(
                            context,
                            inspection == null
                                ? controller.outputMarketFor(quote.recipeName)
                                : controller
                                      .inspectRecipe(
                                        recipe: inspection.recipe,
                                        itemName: inspection.itemName,
                                        selectedVariantId:
                                            quote.selectedVariantId,
                                      )
                                      .quote
                                      .outputMarket,
                            controller.clock(),
                            maxAge: controller.cachedMarketMaxAge,
                          ),
                        ],
                      ),
                    ),
                  ),
                )
              : null,
        ),
      ],
    ),
  );
}

class _ExchangePane extends StatelessWidget {
  const _ExchangePane({required this.controller});
  final OpportunitiesController controller;
  @override
  Widget build(BuildContext context) {
    final p = controller.preferences;
    final spec = context.visualTheme;
    final currency = controller.currency;
    final search = p.exchangeSearch.trim().toLowerCase();
    final currencies = exchangeCatalog
        .where(
          (item) =>
              search.isEmpty || item.item.name.toLowerCase().contains(search),
        )
        .toList();
    final quotes = controller.exchangeQuotes;
    final repeatable =
        quotes.where((quote) => quote.route.limit.isRepeatable).toList()..sort(
          (a, b) => (b.displayQuote.valuePerCurrency ?? -1).compareTo(
            a.displayQuote.valuePerCurrency ?? -1,
          ),
        );
    final limited = quotes
        .where((quote) => !quote.route.limit.isRepeatable)
        .toList();
    final identity = LayoutBuilder(
      key: const ValueKey('exchange-identity'),
      builder: (context, constraints) {
        final heading = Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            OpportunityItemRegion(
              controller: controller,
              name: currency.item.name,
              stableId: 'exchange-selected:${currency.id}',
              child: _exchangeIcon(currency.item, 48),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  OpportunityCopyName(
                    name: currency.item.name,
                    style: spec.typography.section.copyWith(fontSize: 24),
                  ),
                  const SizedBox(height: 6),
                  Text(currency.sourceActivity, style: spec.typography.meta),
                ],
              ),
            ),
            const SizedBox(width: 8),
            _info(context, 'About ${currency.item.name}', [
              currency.sourceActivity,
              ...currency.notes,
              if (currency.item.vendorSellPrice case final price?)
                'You can sell this item to an NPC for ${_quantity(price.toDouble())} silver each.',
            ], sources: currency.sources),
          ],
        );
        final balance = _numberInput(
          'You have',
          controller.owned.toDouble(),
          (value) =>
              controller.change((p) => p.owned[currency.id] = value.toInt()),
          width: 150,
          integer: true,
        );
        if (constraints.maxWidth >=
            680 * MediaQuery.textScalerOf(context).scale(14) / 14) {
          return Row(
            children: [
              Expanded(child: heading),
              const SizedBox(width: 36),
              balance,
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [heading, const SizedBox(height: 18), balance],
        );
      },
    );
    final currencyPicker = Wrap(
      key: const ValueKey('exchange-currency-picker'),
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final item in currencies)
          Tooltip(
            message: item.item.name,
            child: SizedBox.square(
              dimension: 68,
              child: OpportunityButton(
                key: ValueKey('exchange-currency-${item.id}'),
                selected: item.id == currency.id,
                role: AppButtonRole.optionPill,
                semanticLabel: item.item.name,
                padding: const EdgeInsets.all(4),
                onPressed: () =>
                    controller.change((p) => p.currencyId = item.id),
                child: _exchangeIcon(item.item, 56),
              ),
            ),
          ),
      ],
    );
    final searchField = SizedBox(
      width: 230,
      child: _TextInput(
        key: const ValueKey('exchange-search'),
        label: 'Find an exchange item',
        value: p.exchangeSearch,
        onChanged: (value) =>
            controller.change((p) => p.exchangeSearch = value),
        prefix: const Icon(Icons.search, size: 18),
      ),
    );
    return ListView(
      key: PageStorageKey('exchange-${currency.id}'),
      children: [
        OpportunitySurface(
          key: const ValueKey('exchange-toolbar'),
          role: AppSurfaceRole.panel,
          padding: const EdgeInsets.all(14),
          child: LayoutBuilder(
            builder: (context, constraints) {
              if (constraints.maxWidth < 1060) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    searchField,
                    const SizedBox(height: 14),
                    currencyPicker,
                  ],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  searchField,
                  const SizedBox(width: 14),
                  Expanded(child: currencyPicker),
                ],
              );
            },
          ),
        ),
        const SizedBox(height: 12),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 12),
          child: identity,
        ),
        const SizedBox(height: 24),
        _DeskSection(
          title: 'Repeatable',
          meta: '${repeatable.length}',
          trailing: _info(context, 'Exchange value', [
            'Each card is a different way to use the same items. Do not add their values together.',
            'Value is what you receive after selling the reward. It is not crafting profit.',
            'Values are per item. Enter a balance only if you want totals.',
            'Only whole exchanges count. Leftover items stay in your balance.',
            'Market rewards use the listing price after tax. NPC rewards use their shop value.',
            'Some rewards cannot be sold. They stay visible, without an invented silver value.',
            'Limited exchanges need you to confirm how many are still available. The app cannot read your account.',
          ]),
        ),
        const SizedBox(height: 10),
        _wrappedCards(
          context,
          repeatable
              .map(
                (quote) => _ExchangeCard(controller: controller, quote: quote),
              )
              .toList(),
        ),
        if (limited.isNotEmpty) ...[
          const SizedBox(height: 12),
          _DeskSection(
            title: 'Limited',
            meta: 'Check your remaining exchanges',
          ),
          const SizedBox(height: 10),
          _wrappedCards(
            context,
            limited
                .map(
                  (quote) =>
                      _ExchangeCard(controller: controller, quote: quote),
                )
                .toList(),
          ),
        ],
        const SizedBox(height: 12),
      ],
    );
  }
}

class _DeskSection extends StatelessWidget {
  const _DeskSection({required this.title, required this.meta, this.trailing});
  final String title;
  final String meta;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Text(title, style: context.visualTheme.typography.section),
      const SizedBox(width: 12),
      Expanded(child: Text(meta, style: context.visualTheme.typography.meta)),
      ?trailing,
    ],
  );
}

class _ExchangeCard extends StatelessWidget {
  const _ExchangeCard({required this.controller, required this.quote});
  final OpportunitiesController controller;
  final ExchangeQuote quote;
  @override
  Widget build(BuildContext context) {
    final spec = context.visualTheme;
    final route = quote.route;
    final display = quote.displayQuote;
    final marketReward = route.rewards.length == 1
        ? route.rewards.single.item
        : null;
    final note = _exchangeCardNote(quote);
    void open() => _exchangeDetails(context, controller, quote);
    return OpportunityCardMotion(
      child: OpportunitySurface(
        role: AppSurfaceRole.card,
        padding: EdgeInsets.zero,
        child: InkWell(
          onTap: open,
          borderRadius: BorderRadius.circular(14),
          hoverColor: spec.palette.primary.withAlpha(12),
          focusColor: spec.palette.primary.withAlpha(28),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (route.rewardContainer case final container?)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 10),
                              child: Row(
                                children: [
                                  _exchangeIcon(container, 48),
                                  const SizedBox(width: 14),
                                  Expanded(
                                    child: OpportunityCopyName(
                                      name: container.name,
                                      style: spec.typography.body.copyWith(
                                        fontSize: OpportunitiesVisualSpec
                                            .cardNameFontSize,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          for (final reward in route.rewards)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 7),
                              child: Row(
                                children: [
                                  if (reward.item case final item?)
                                    _exchangeIcon(item, 48)
                                  else
                                    Icon(
                                      Icons.auto_awesome_outlined,
                                      size: 30,
                                      color: spec.palette.textMuted,
                                    ),
                                  const SizedBox(width: 14),
                                  Expanded(
                                    child: OpportunityCopyName(
                                      name: reward.name,
                                      displayLabel:
                                          '${route.rewardContainer != null ? 'Contains ' : ''}${reward.quantity > 1 ? '${_quantity(reward.quantity.toDouble())}× ' : ''}${reward.name}',
                                      style: spec.typography.body.copyWith(
                                        fontSize: OpportunitiesVisualSpec
                                            .cardNameFontSize,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),
                    ExcludeFocus(
                      child: OpportunityButton.icon(
                        icon: const Icon(Icons.arrow_forward, size: 20),
                        semanticLabel:
                            'Exchange details for ${route.rewards.first.name}',
                        onPressed: open,
                      ),
                    ),
                  ],
                ),
                if (route.directVendorSale)
                  Text(
                    'Sell to NPC',
                    style: spec.typography.meta.copyWith(
                      fontSize: OpportunitiesVisualSpec.cardLabelFontSize,
                    ),
                  )
                else
                  OpportunityCopyName(
                    name: quote.currency.item.name,
                    displayLabel:
                        '${_quantity(route.inputCount.toDouble())} ${quote.currency.item.name}',
                    style: spec.typography.meta.copyWith(
                      fontSize: OpportunitiesVisualSpec.cardLabelFontSize,
                    ),
                  ),
                const SizedBox(height: 14),
                _MetricColumns(
                  children: [
                    _metric(
                      context,
                      quote.isReference ? 'Value' : 'Total value',
                      _silver(display.netProceeds),
                      large: true,
                      valueFontSize:
                          OpportunitiesVisualSpec.cardPrimaryValueFontSize,
                      valueFontWeight: FontWeight.w600,
                      labelFontSize: OpportunitiesVisualSpec.cardLabelFontSize,
                      color: display.isRankable
                          ? spec.palette.success
                          : spec.palette.textMuted,
                      estimateExplanation: _exchangeValueHelp(quote),
                    ),
                    _metric(
                      context,
                      _exchangeUnitLabel(quote.currency),
                      _silver(display.valuePerCurrency),
                      valueFontSize:
                          OpportunitiesVisualSpec.cardSecondaryValueFontSize,
                      labelFontSize: OpportunitiesVisualSpec.cardLabelFontSize,
                    ),
                    if (marketReward?.marketable == true)
                      _market(
                        context,
                        controller.market.items['${marketReward!.id}'],
                        controller.clock(),
                        large: true,
                        maxAge: controller.cachedMarketMaxAge,
                        valueFontSize:
                            OpportunitiesVisualSpec.cardSecondaryValueFontSize,
                        labelFontSize:
                            OpportunitiesVisualSpec.cardLabelFontSize,
                      ),
                  ],
                ),
                if (!quote.isReference) ...[
                  const SizedBox(height: 10),
                  Text(
                    '${display.exchanges} exchange${display.exchanges == 1 ? '' : 's'}',
                    style: spec.typography.meta.copyWith(
                      fontSize: OpportunitiesVisualSpec.cardLabelFontSize,
                    ),
                  ),
                ],
                if (note != null) ...[
                  const SizedBox(height: 10),
                  Text(
                    note,
                    style: spec.typography.meta.copyWith(
                      fontSize: OpportunitiesVisualSpec.cardLabelFontSize,
                      color:
                          quote.hasListingEstimate ||
                              quote.availability !=
                                  ExchangeAvailability.available
                          ? spec.palette.warning
                          : spec.palette.textMuted,
                    ),
                  ),
                ],
                if (!route.limit.isRepeatable ||
                    route.requirements.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Text(
                    'Check availability',
                    style: spec.typography.meta.copyWith(
                      color: spec.palette.warning,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

String? _exchangeCardNote(ExchangeQuote quote) {
  if (quote.hasListingEstimate) return null;
  return switch (quote.availability) {
    ExchangeAvailability.available =>
      quote.hasUnpricedRewards ? 'Silver value unavailable' : null,
    ExchangeAvailability.confirmationNeeded => null,
    ExchangeAvailability.limitReached => 'None remaining',
    ExchangeAvailability.notEnoughCurrency => 'Not enough items',
    ExchangeAvailability.marketUnknown => 'Check prices',
    ExchangeAvailability.notEnoughBuyers => 'Would need to be listed',
  };
}

String _craftStatus(OpportunityQuote quote, OpportunitySaleMode mode) {
  if (quote.issues.contains(OpportunityIssue.insufficientInputs)) {
    return 'Not enough ingredients for this batch';
  }
  if (quote.issues.contains(OpportunityIssue.outputUnlisted)) {
    return 'Output cannot be listed';
  }
  if (quote.issues.any(
    (issue) => [
      OpportunityIssue.inputBookStale,
      OpportunityIssue.outputBookStale,
      OpportunityIssue.outputQuoteStale,
    ].contains(issue),
  )) {
    return 'Prices need a fresh check';
  }
  if (mode == OpportunitySaleMode.currentBuyers &&
      quote.issues.contains(OpportunityIssue.insufficientBuyers)) {
    return 'Would need to be listed';
  }
  return 'Market check needed';
}

String _exchangeUnitLabel(ExchangeCurrency currency) {
  final name = currency.item.name.toLowerCase();
  if (name.contains('coin') && !name.contains('chest')) return 'Per coin';
  if (name.contains('seal')) return 'Per seal';
  return 'Per item';
}

String _exchangeValueHelp(ExchangeQuote quote) {
  final display = quote.displayQuote;
  final basis = quote.isReference
      ? 'Reward value for one exchange.'
      : 'Reward value for ${display.exchanges} exchanges.';
  final sale = display.rewardQuotes.every((reward) => reward.vendorSale)
      ? 'NPC sale, with no market tax.'
      : 'After market tax, using the current selling price.';
  return '$basis $sale';
}

Widget _switches(
  BuildContext context,
  List<(String, bool, VoidCallback)> choices, {
  bool enabled = true,
  double minimumHeight = 38,
}) => Wrap(
  spacing: 6,
  runSpacing: 6,
  children: [
    for (final choice in choices)
      OpportunityButton.label(
        choice.$1,
        selected: choice.$2,
        role: AppButtonRole.optionPill,
        minimumSize: Size(0, minimumHeight),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        onPressed: enabled ? choice.$3 : null,
      ),
  ],
);

Widget _itemIcon(
  OpportunitiesController controller,
  String name,
  double size, {
  bool framed = false,
  CraftMode? mode,
}) {
  final artwork = ModeItemIcon(
    controller: mode == null
        ? controller.modeController
        : controller.appController.modes[mode]!,
    catalogRepository: controller.catalog,
    name: name,
    size: size,
    searchAcrossModes: true,
    showFrame: false,
    fit: framed ? BoxFit.contain : BoxFit.cover,
  );
  return RecipeBookItemInfoHover(
    controller: controller.itemInfoController,
    name: name,
    mode: mode ?? controller.modeController.mode,
    child: framed
        ? DecoratedBox(
            key: ValueKey('craft-artwork-frame:$name'),
            decoration: BoxDecoration(
              color: OpportunitiesVisualSpec.palette.surfaceInset,
              borderRadius: BorderRadius.circular(9),
            ),
            child: Padding(padding: const EdgeInsets.all(9), child: artwork),
          )
        : artwork,
  );
}

Widget _exchangeIcon(ExchangeItem item, double size) => Image.asset(
  item.iconAsset,
  width: size,
  height: size,
  filterQuality: FilterQuality.high,
  semanticLabel: item.name,
);

String _quantity(num value) => formatQuantity(value.toDouble());
String _percent(num value) =>
    formatGroupedEditableQuantity(value.toDouble(), fractionDigits: 4);
String _silver(num? value) {
  if (value == null || !value.isFinite) return '—';
  final abs = value.abs();
  if (abs >= 1000000000) return '${_quantity(value / 1000000000)}B';
  if (abs >= 1000000) return '${_quantity(value / 1000000)}M';
  if (abs >= 10000) return '${_quantity(value / 1000)}K';
  if (abs > 0 && abs < 100) {
    return formatGroupedEditableQuantity(
      value.toDouble(),
      fractionDigits: abs < 1 ? 4 : 2,
    );
  }
  return _quantity(value);
}

String _estimateValue(String value, bool estimated) =>
    estimated && value != '—' ? '≈ $value' : value;

String? _quoteEstimateExplanation(OpportunityQuote quote) =>
    !quote.hasEstimatedInputs
    ? null
    : quote.hasUncheckedInputDepth
    ? 'Estimate using current ingredient prices. Available sell orders have not been checked.'
    : 'Estimate using current prices for ingredients without enough stock.';

String? _inputEstimateExplanation(OpportunityIngredientQuote ingredient) =>
    ingredient.estimatedMarketQuantity <= 0
    ? null
    : '${_quantity(ingredient.estimatedMarketQuantity)} estimated at ${_quantity(ingredient.estimatedUnitPrice!)} silver each. ${ingredient.estimateKind == OpportunityInputEstimateKind.uncheckedDepth ? 'Available sell orders have not been checked.' : 'There is not enough stock for this quantity.'}';

Widget _metric(
  BuildContext context,
  String label,
  String value, {
  Color? color,
  bool large = false,
  double? valueFontSize,
  double? labelFontSize,
  FontWeight? valueFontWeight,
  Key? detailsKey,
  String? detailsLabel,
  VoidCallback? onDetails,
  String? estimateExplanation,
}) => _MetricValue(
  label: label,
  value: value,
  color: color,
  large: large,
  valueFontSize: valueFontSize,
  labelFontSize: labelFontSize,
  valueFontWeight: valueFontWeight,
  detailsKey: detailsKey,
  detailsLabel: detailsLabel,
  onDetails: onDetails,
  estimateExplanation: estimateExplanation,
);

class _MetricValue extends StatelessWidget {
  const _MetricValue({
    required this.label,
    required this.value,
    this.color,
    this.large = false,
    this.valueFontSize,
    this.labelFontSize,
    this.valueFontWeight,
    this.detailsKey,
    this.detailsLabel,
    this.onDetails,
    this.estimateExplanation,
  });
  final String label;
  final String value;
  final Color? color;
  final bool large;
  final double? valueFontSize, labelFontSize;
  final FontWeight? valueFontWeight;
  final Key? detailsKey;
  final String? detailsLabel;
  final VoidCallback? onDetails;
  final String? estimateExplanation;

  TextStyle valueStyle(BuildContext context) =>
      context.visualTheme.typography.body.copyWith(
        fontSize: valueFontSize ?? 18,
        fontWeight:
            valueFontWeight ??
            (large && label != 'Stock' ? FontWeight.w700 : FontWeight.w500),
        color: color ?? context.visualTheme.palette.text,
      );

  double minimumWidth(BuildContext context) {
    final painter = TextPainter(
      text: TextSpan(text: value, style: valueStyle(context)),
      textScaler: MediaQuery.textScalerOf(context),
      textDirection: Directionality.of(context),
    )..layout();
    final width = painter.width.ceilToDouble() + 2;
    painter.dispose();
    return width;
  }

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: Text(
              label,
              style: context.visualTheme.typography.body.copyWith(
                fontSize: labelFontSize,
                color: context.visualTheme.palette.textMuted,
              ),
            ),
          ),
          if (onDetails != null) ...[
            const SizedBox(width: 6),
            Tooltip(
              message: detailsLabel ?? label,
              child: Semantics(
                button: true,
                label: detailsLabel ?? label,
                child: InkResponse(
                  key: detailsKey,
                  onTap: onDetails,
                  radius: 16,
                  child: const Padding(
                    padding: EdgeInsets.all(3),
                    child: Icon(Icons.info_outline, size: 17),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
      const SizedBox(height: 3),
      if (estimateExplanation != null && value != '—')
        Tooltip(
          message: estimateExplanation!,
          child: Text(value, style: valueStyle(context)),
        )
      else
        Text(value, style: valueStyle(context)),
    ],
  );
}

class _MetricColumns extends StatelessWidget {
  const _MetricColumns({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      var minimumWidth = MediaQuery.textScalerOf(context).scale(90);
      for (final child in children) {
        final value = child is Tooltip ? child.child : child;
        if (value is _MetricValue) {
          minimumWidth = math.max(minimumWidth, value.minimumWidth(context));
        }
      }
      final columns = ((constraints.maxWidth + 12) / (minimumWidth + 12))
          .floor()
          .clamp(1, children.length);
      final width = (constraints.maxWidth - (columns - 1) * 12) / columns;
      return Wrap(
        spacing: 12,
        runSpacing: 8,
        children: [
          for (final child in children) SizedBox(width: width, child: child),
        ],
      );
    },
  );
}

Widget _ingredientGrid(BuildContext context, List<Widget> cards) =>
    LayoutBuilder(
      builder: (context, constraints) {
        final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
        final columns = constraints.maxWidth >= 680 * scale ? 2 : 1;
        final width = (constraints.maxWidth - (columns - 1) * 10) / columns;
        return Wrap(
          key: const ValueKey('craft-ingredient-grid'),
          spacing: 10,
          runSpacing: 10,
          children: [
            for (final card in cards) SizedBox(width: width, child: card),
          ],
        );
      },
    );

(String, bool) _marketReading(
  OpportunityMarketItem? item,
  DateTime now,
  Duration maxAge,
) {
  final stock = item?.stockFor(now, maxAge);
  final bids = item?.bookIsFresh(now, maxAge) == true
      ? item?.preorderCount
      : null;
  final negative = (stock == null || stock == 0) && bids != null && bids > 0;
  final text = negative
      ? '−${_quantity(bids)}'
      : stock == null
      ? '—'
      : _quantity(stock);
  return (text, negative);
}

Widget _market(
  BuildContext context,
  OpportunityMarketItem? item,
  DateTime now, {
  bool large = false,
  bool compact = false,
  double? valueFontSize,
  double? labelFontSize,
  VoidCallback? onDetails,
  Duration maxAge = OpportunitiesController.maxMarketAge,
}) {
  final spec = context.visualTheme;
  final (text, negative) = _marketReading(item, now, maxAge);
  final stock = item?.stockFor(now, maxAge);
  final preorders = item?.bookIsFresh(now, maxAge) == true
      ? item?.preorderCount
      : null;
  return Tooltip(
    message:
        'Stock: ${stock == null ? 'Not checked' : _quantity(stock)}\nPreorders: ${preorders == null ? 'Not checked' : _quantity(preorders)}${negative ? '\nThe red negative count shows preorders when nothing is listed.' : ''}',
    child: compact
        ? Semantics(
            label: 'Stock: $text',
            excludeSemantics: true,
            child: Text(
              text,
              style: spec.typography.body.copyWith(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: negative ? spec.palette.danger : spec.palette.textMuted,
              ),
            ),
          )
        : _metric(
            context,
            'Stock',
            text,
            color: negative ? spec.palette.danger : spec.palette.textMuted,
            large: large,
            valueFontSize: valueFontSize,
            labelFontSize: labelFontSize,
            detailsKey: const ValueKey('craft-market-details'),
            detailsLabel: 'Market details',
            onDetails: onDetails,
          ),
  );
}

Widget _sales(BuildContext context, OpportunityMarketItem? item, DateTime now) {
  final activity = item?.salesActivity;
  String text = 'Sales · not measured yet';
  if (activity != null &&
      now.difference(activity.endedAt) <= const Duration(hours: 24) &&
      !activity.endedAt.isAfter(now)) {
    final hours = activity.interval.inMinutes / 60;
    text = '${_quantity(activity.soldCount)} sold in ${_quantity(hours)}h';
  } else if (item?.lastSoldAt case final date?) {
    final age = now.difference(date);
    if (!age.isNegative) {
      text = age.inHours < 1
          ? 'Last sale ${age.inMinutes}m ago'
          : 'Last sale ${age.inHours}h ago';
    }
  }
  return Tooltip(
    message:
        'Sales activity needs two checks at least an hour apart. This is completed sales, not lifetime trades or a promise of future sales.',
    child: Text(
      text,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: context.visualTheme.typography.meta,
    ),
  );
}

Widget _empty(BuildContext context, String title, String description) => Center(
  child: Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(title, style: context.visualTheme.typography.section),
      const SizedBox(height: 8),
      Text(description),
    ],
  ),
);

Widget _cardList(
  BuildContext context, {
  required int count,
  required String keyName,
  required Widget Function(int) builder,
  required Widget header,
  double minimumCardWidth = 420,
  double maximumCardWidth = 560,
  int maximumColumns = 3,
}) => LayoutBuilder(
  builder: (context, constraints) {
    final scale = MediaQuery.textScalerOf(context).scale(16) / 16;
    final columns =
        ((constraints.maxWidth + 16) / (minimumCardWidth * scale + 16))
            .floor()
            .clamp(1, maximumColumns);
    // Keep the established column breakpoints, but reduce the actual card
    // footprint too: otherwise a smaller interior still fills the old box.
    final cardWidth =
        OpportunitiesVisualSpec.recipeCardScale *
        math.min(
          maximumCardWidth * scale,
          (constraints.maxWidth - 5 - (columns - 1) * 16) / columns,
        );
    // Center the occupied grid, keeping sparse results at the same card width
    // and incomplete rows aligned with the columns above them.
    final gridColumns = math.min(count, columns);
    final gridWidth =
        gridColumns * cardWidth + math.max(0, gridColumns - 1) * 14;
    final sidePadding = math.max(0.0, (constraints.maxWidth - gridWidth) / 2);
    return CustomScrollView(
      key: PageStorageKey(keyName),
      slivers: [
        SliverToBoxAdapter(child: header),
        SliverPadding(
          padding: EdgeInsets.fromLTRB(sidePadding, 1, sidePadding, 20),
          sliver: SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, row) => Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (var column = 0; column < gridColumns; column++) ...[
                      if (column > 0) const SizedBox(width: 14),
                      SizedBox(
                        width: cardWidth,
                        child: row * columns + column < count
                            ? Align(
                                alignment: Alignment.topLeft,
                                child: ConstrainedBox(
                                  constraints: BoxConstraints(
                                    maxWidth: maximumCardWidth * scale,
                                  ),
                                  child: builder(row * columns + column),
                                ),
                              )
                            : const SizedBox.shrink(),
                      ),
                    ],
                  ],
                ),
              ),
              childCount: (count / columns).ceil(),
            ),
          ),
        ),
      ],
    );
  },
);

Widget _wrappedCards(BuildContext context, List<Widget> cards) => LayoutBuilder(
  builder: (context, constraints) {
    final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
    final columns = (constraints.maxWidth / (420 * scale.clamp(1, 2)))
        .floor()
        .clamp(1, 3);
    final width = math.min(
      560.0 * scale.clamp(1, 2),
      (constraints.maxWidth - (columns - 1) * 12) / columns,
    );
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [for (final card in cards) SizedBox(width: width, child: card)],
    );
  },
);

Widget _numberInput(
  String label,
  double value,
  ValueChanged<double> onChanged, {
  double width = 130,
  bool integer = false,
  double minimum = 0,
  double maximum = 1000000000,
}) => SizedBox(
  width: width,
  child: _TextInput(
    key: ValueKey(label),
    label: label,
    value: formatEditableQuantity(value),
    numeric: true,
    integer: integer,
    minimum: minimum,
    maximum: maximum,
    onChanged: (text) {
      final number = double.tryParse(text.replaceAll(',', '.'));
      if (number != null &&
          number.isFinite &&
          number >= minimum &&
          number <= maximum &&
          (!integer || number == number.floorToDouble())) {
        onChanged(number);
      }
    },
  ),
);

class _TextInput extends StatefulWidget {
  const _TextInput({
    required this.label,
    required this.value,
    required this.onChanged,
    this.numeric = false,
    this.integer = false,
    this.minimum = 0,
    this.maximum = 1000000000,
    this.prefix,
    super.key,
  });
  final String label, value;
  final ValueChanged<String> onChanged;
  final bool numeric, integer;
  final double minimum, maximum;
  final Widget? prefix;
  @override
  State<_TextInput> createState() => _TextInputState();
}

class _TextInputState extends State<_TextInput> {
  late final TextEditingController text = TextEditingController(
    text: widget.value,
  );
  final focus = FocusNode();
  bool invalid = false;
  @override
  void initState() {
    super.initState();
    focus.addListener(_focusChanged);
  }

  void _focusChanged() {
    if (!widget.numeric) {
      setState(() {});
      return;
    }
    if (!focus.hasFocus && widget.numeric) {
      text.text = widget.value;
      if (invalid) setState(() => invalid = false);
    }
  }

  void _changed(String value) {
    final number = double.tryParse(value.replaceAll(',', '.'));
    final valid =
        !widget.numeric ||
        (number != null &&
            number.isFinite &&
            number >= widget.minimum &&
            number <= widget.maximum &&
            (!widget.integer || number == number.floorToDouble()));
    setState(() => invalid = !valid);
    if (valid) widget.onChanged(value);
  }

  @override
  void didUpdateWidget(_TextInput oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!focus.hasFocus && text.text != widget.value) text.text = widget.value;
  }

  @override
  void dispose() {
    text.dispose();
    focus.removeListener(_focusChanged);
    focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      OpportunityTextField(
        controller: text,
        focusNode: focus,
        label: widget.numeric ? widget.label : null,
        hintText: !widget.numeric && !focus.hasFocus ? widget.label : null,
        semanticLabel: widget.label,
        flat: !widget.numeric,
        prefixIcon: widget.prefix,
        onChanged: _changed,
        keyboardType: widget.numeric
            ? TextInputType.number
            : TextInputType.text,
        inputFormatters: widget.numeric
            ? [
                FilteringTextInputFormatter.allow(
                  RegExp(widget.integer ? r'[0-9]' : r'[0-9.,]'),
                ),
              ]
            : null,
        minimumHeight: 40,
      ),
      if (invalid)
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            'Use ${_quantity(widget.minimum)}–${_quantity(widget.maximum)}',
            style: context.visualTheme.typography.meta.copyWith(
              color: context.visualTheme.palette.danger,
              fontSize: 14,
            ),
          ),
        ),
    ],
  );
}

Widget _info(
  BuildContext context,
  String title,
  List<String> paragraphs, {
  List<ExchangeSource> sources = const [],
}) => OpportunityButton.icon(
  icon: const Icon(Icons.info_outline, size: 19),
  semanticLabel: title,
  onPressed: () => _dialog(
    context,
    title,
    (context) => Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final text in paragraphs)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(text),
          ),
        _sources(sources),
      ],
    ),
  ),
);

Widget _sources(List<ExchangeSource> sources) => Builder(
  builder: (context) => Wrap(
    spacing: 8,
    runSpacing: 8,
    children: [
      for (final source in sources)
        OpportunityButton.label(
          source.label,
          role: AppButtonRole.infoChip,
          onPressed: () => unawaited(_openSource(context, source.url)),
        ),
    ],
  ),
);

Future<void> _openSource(BuildContext context, String url) async {
  final uri = Uri.tryParse(url);
  if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) return;
  try {
    final opened = await const MethodChannel(
      'bdo_gathering/native',
    ).invokeMethod<bool>('openExternal', {'url': url});
    if (opened == true) return;
  } on PlatformException {
    // The link stays available below if Windows cannot open it.
  } on MissingPluginException {
    // The link stays available below on hosts without the native bridge.
  }
  if (context.mounted) {
    await _dialog(context, 'Source link', (context) => SelectableText(url));
  }
}

Future<void> _dialog(
  BuildContext context,
  String title,
  WidgetBuilder body, {
  Widget? icon,
  String? copyTitleName,
  Widget Function(BuildContext)? titleBuilder,
  VoidCallback? onBack,
  bool scrollBody = true,
  double maxWidth = 820,
}) => showDialog<void>(
  context: context,
  useRootNavigator: false,
  barrierColor: Colors.black.withAlpha(200),
  animationStyle: MediaQuery.disableAnimationsOf(context)
      ? AnimationStyle.noAnimation
      : const AnimationStyle(
          duration: Duration(milliseconds: 220),
          reverseDuration: Duration(milliseconds: 160),
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeInCubic,
        ),
  builder: (context) {
    final spec = context.visualTheme;
    final dialog = Dialog(
      backgroundColor: spec.palette.surfaceInset,
      surfaceTintColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: maxWidth,
          maxHeight: math.max(240, MediaQuery.sizeOf(context).height - 70),
        ),
        child: OpportunitySurface(
          role: AppSurfaceRole.modal,
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (icon != null && titleBuilder == null) ...[
                    icon,
                    const SizedBox(width: 12),
                  ],
                  Expanded(
                    child:
                        titleBuilder?.call(context) ??
                        (copyTitleName == null
                            ? Text(
                                title,
                                style: spec.typography.section.copyWith(
                                  fontSize: 26,
                                ),
                              )
                            : OpportunityCopyName(
                                name: copyTitleName,
                                displayLabel: title,
                                style: spec.typography.section.copyWith(
                                  fontSize: 26,
                                ),
                              )),
                  ),
                  OpportunityButton.icon(
                    icon: const Icon(Icons.close, size: 20),
                    semanticLabel: 'Close',
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              Flexible(
                child: scrollBody
                    ? SingleChildScrollView(child: body(context))
                    : body(context),
              ),
            ],
          ),
        ),
      ),
    );
    if (onBack == null) return dialog;
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.arrowLeft): onBack,
        const SingleActivator(LogicalKeyboardKey.arrowLeft, alt: true): onBack,
      },
      child: Focus(autofocus: true, child: dialog),
    );
  },
);

// Detailed calculations stay here, away from the compact cards.
Future<void> _craftDetails(
  BuildContext context,
  OpportunitiesController controller,
  OpportunityQuote initial, {
  OpportunityBestUseQuote? bestUse,
}) async {
  final pages = ValueNotifier<List<_IngredientRecipe>>([]);
  final rootPage = _IngredientRecipe(
    initial.recipeName,
    bestUse?.recipe ?? controller.recipes[initial.recipeName]!,
    root: true,
    bestUse: bestUse,
  );
  if (bestUse != null) {
    rootPage.variantId = initial.selectedVariantId;
    rootPage.choices.addAll(bestUse.ingredientChoices);
  }
  final scrollPositions = PageStorageBucket();
  var closed = false;
  var updateQueued = false;
  void updateInspection() {
    final selected = pages.value.lastOrNull;
    if (selected != null) {
      selected.variantId ??= controller
          .inspectRecipe(recipe: selected.recipe, itemName: selected.itemName)
          .quote
          .selectedVariantId;
      controller.setInspectedRecipe(
        selected.recipe,
        itemName: selected.itemName,
        selectedVariantId: selected.variantId,
      );
    } else {
      final quote =
          controller.quotes
              .where((quote) => quote.recipeName == initial.recipeName)
              .firstOrNull ??
          initial;
      controller.setInspectedRecipe(
        rootPage.recipe,
        itemName: initial.recipeName,
        selectedVariantId: rootPage.variantId ?? quote.selectedVariantId,
      );
    }
  }

  // The chosen root formula can change when a newly checked ingredient is
  // cheaper. Keep its inspection scoped to that formula, outside build.
  void queueInspectionUpdate() {
    if (closed || updateQueued) return;
    updateQueued = true;
    scheduleMicrotask(() {
      updateQueued = false;
      if (!closed) updateInspection();
    });
  }

  updateInspection();
  controller.addListener(queueInspectionUpdate);
  void goTo(int depth) {
    pages.value = pages.value.take(depth).toList();
    updateInspection();
  }

  void goBack() {
    if (pages.value.isNotEmpty) goTo(pages.value.length - 1);
  }

  void openRecipe(String name) {
    final next = _ingredientRecipe(
      controller,
      name,
      preferredMode: bestUse == null
          ? null
          : _recipeMode(pages.value.lastOrNull?.recipe ?? rootPage.recipe),
    );
    if (next == null) return;
    final identity = next.recipe.name.trim().toLowerCase();
    // Some reference conversions point back to an earlier recipe. Reuse that
    // page instead of growing a circular path forever.
    if (identity == initial.recipeName.trim().toLowerCase()) {
      goTo(0);
      return;
    }
    final previous = pages.value.indexWhere(
      (page) => page.recipe.name.trim().toLowerCase() == identity,
    );
    if (previous >= 0) {
      goTo(previous + 1);
    } else {
      pages.value = [...pages.value, next];
      updateInspection();
    }
  }

  try {
    await _dialog(
      context,
      initial.recipeName,
      (context) => PageStorage(
        bucket: scrollPositions,
        child: ValueListenableBuilder<List<_IngredientRecipe>>(
          valueListenable: pages,
          builder: (context, history, _) {
            final selected = history.lastOrNull;
            return OpportunityEntrance(
              key: ValueKey(selected?.itemName ?? initial.recipeName),
              child: SingleChildScrollView(
                key: PageStorageKey(selected?.itemName ?? initial.recipeName),
                child: _IngredientRecipeView(
                  key: ValueKey(selected?.itemName ?? initial.recipeName),
                  controller: controller,
                  selected: selected ?? rootPage,
                  onOpen: openRecipe,
                ),
              ),
            );
          },
        ),
      ),
      scrollBody: false,
      maxWidth: 1120,
      onBack: goBack,
      titleBuilder: (context) =>
          ValueListenableBuilder<List<_IngredientRecipe>>(
            valueListenable: pages,
            builder: (context, history, _) {
              final selected = history.lastOrNull;
              final name = selected?.itemName ?? initial.recipeName;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      if (selected != null) ...[
                        OpportunityButton.icon(
                          key: const ValueKey('ingredient-recipe-back'),
                          icon: const Icon(Icons.arrow_back, size: 22),
                          semanticLabel: 'Back to previous recipe',
                          tooltip: 'Back · Left arrow',
                          onPressed: goBack,
                        ),
                        const SizedBox(width: 8),
                      ],
                      Expanded(
                        child: OpportunityItemRegion(
                          controller: controller,
                          name: name,
                          stableId: 'opportunity-title:$name',
                          resolvePlannerTarget: () {
                            if (selected != null) {
                              return _ingredientPlannerTarget(
                                controller,
                                selected,
                              );
                            }
                            if (bestUse != null) {
                              return _ingredientPlannerTarget(
                                controller,
                                rootPage,
                              );
                            }
                            final current = controller.quotes
                                .where(
                                  (quote) =>
                                      quote.recipeName == initial.recipeName,
                                )
                                .firstOrNull;
                            if (current == null) return null;
                            return controller.plannerTargetFor(
                              name,
                              mode: controller.preferences.mode,
                              variantId:
                                  rootPage.variantId ??
                                  current.selectedVariantId,
                            );
                          },
                          child: Row(
                            children: [
                              _itemIcon(
                                controller,
                                name,
                                48,
                                mode: bestUse == null
                                    ? null
                                    : _recipeMode(
                                        selected?.recipe ?? rootPage.recipe,
                                      ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: OpportunityCopyName(
                                  name: name,
                                  style: context.visualTheme.typography.section
                                      .copyWith(fontSize: 26),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (history.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    _RecipeTrail(
                      names: [
                        initial.recipeName,
                        ...history.map((p) => p.itemName),
                      ],
                      onJump: goTo,
                    ),
                  ],
                ],
              );
            },
          ),
    );
  } finally {
    closed = true;
    controller.removeListener(queueInspectionUpdate);
    controller.setInspectedRecipe(null);
    pages.dispose();
  }
}

class _RecipeTrail extends StatelessWidget {
  const _RecipeTrail({required this.names, required this.onJump});
  final List<String> names;
  final ValueChanged<int> onJump;

  @override
  Widget build(BuildContext context) => ConstrainedBox(
    constraints: BoxConstraints(
      maxHeight: math.max(48, MediaQuery.sizeOf(context).height * .18),
    ),
    child: SingleChildScrollView(
      child: Wrap(
        key: const ValueKey('ingredient-recipe-trail'),
        spacing: 4,
        runSpacing: 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          for (var index = 0; index < names.length; index++) ...[
            if (index > 0)
              Icon(
                Icons.chevron_right,
                size: 16,
                color: context.visualTheme.palette.textMuted,
              ),
            Semantics(
              button: index < names.length - 1,
              selected: index == names.length - 1,
              child: InkWell(
                key: ValueKey('ingredient-recipe-crumb:$index'),
                onTap: index < names.length - 1 ? () => onJump(index) : null,
                borderRadius: BorderRadius.circular(4),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 6,
                  ),
                  child: Text(
                    names[index],
                    style: context.visualTheme.typography.body.copyWith(
                      fontSize: 14,
                      color: index < names.length - 1
                          ? context.visualTheme.palette.primaryBright
                          : context.visualTheme.palette.textMuted,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    ),
  );
}

Widget _craftCalculationBody(
  BuildContext context,
  OpportunitiesController controller,
  OpportunityQuote quote,
  ValueChanged<String> onOpen, {
  OpportunityRecipeInspection? inspection,
  Set<String> substituteGroups = const {},
  ValueChanged<OpportunityIngredientQuote>? onSubstitutes,
}) {
  final spec = context.visualTheme;
  final revenue = _craftRevenue(controller, quote);
  final note = inspection?.isRareOutput == true
      ? null
      : _craftCardNote(controller, quote, recipe: inspection?.recipe);
  final ingredients = Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(
        quote.ingredients.any(
              (item) =>
                  !_ingredientHasMarket(item) && item.npcUnitPrice == null,
            )
            ? 'Ingredients'
            : 'Buy these ingredients',
        style: spec.typography.body.copyWith(
          fontWeight: FontWeight.w700,
          fontSize: 18,
        ),
      ),
      const SizedBox(height: 10),
      _ingredientGrid(context, [
        for (final ingredient in quote.ingredients)
          OpportunitySurface(
            role: AppSurfaceRole.row,
            padding: const EdgeInsets.all(10),
            child: _ingredientRecipeLink(
              controller,
              ingredient.name,
              onOpen,
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      _itemIcon(
                        controller,
                        ingredient.name,
                        48,
                        mode: inspection?.sourceMode,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Flexible(
                                  child: Align(
                                    alignment: Alignment.centerLeft,
                                    widthFactor: 1,
                                    child: OpportunityCopyName(
                                      name: ingredient.name,
                                      style: spec.typography.body.copyWith(
                                        fontSize: 18,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ),
                                if (onSubstitutes != null &&
                                    ingredient.originalNames.any(
                                      substituteGroups.contains,
                                    )) ...[
                                  const SizedBox(width: 6),
                                  OpportunityButton.icon(
                                    key: ValueKey(
                                      'ingredient-substitutes:${ingredient.name}',
                                    ),
                                    icon: const Icon(
                                      Icons.swap_horiz,
                                      size: 19,
                                    ),
                                    semanticLabel:
                                        'Substitutes for ${ingredient.name}',
                                    tooltip: 'Substitutes',
                                    onPressed: () => onSubstitutes(ingredient),
                                  ),
                                ],
                              ],
                            ),
                            const SizedBox(height: 3),
                            Text(
                              _ingredientQuantityLabel(ingredient),
                              key: ValueKey(
                                'ingredient-quantity:${ingredient.name}',
                              ),
                              style: spec.typography.meta.copyWith(
                                color:
                                    _ingredientStockShortage(
                                      controller,
                                      ingredient,
                                    )
                                    ? spec.palette.danger
                                    : spec.typography.meta.color,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),
                      OpportunityInventoryInput(
                        key: ValueKey(
                          'ingredient-inventory:${ingredient.name}',
                        ),
                        controller: controller.modeController,
                        itemName: ingredient.name,
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  if (!_ingredientIsNonMarket(ingredient) ||
                      ingredient.npcUnitPrice != null)
                    _MetricColumns(
                      children: [
                        _metric(
                          context,
                          'Cost',
                          ingredient.costForCalculation == null
                              ? '—'
                              : _estimateValue(
                                  _quantity(ingredient.costForCalculation!),
                                  ingredient.estimatedMarketQuantity > 0,
                                ),
                          estimateExplanation: _inputEstimateExplanation(
                            ingredient,
                          ),
                        ),
                        if (ingredient.npcUnitPrice != null)
                          _metric(
                            context,
                            'NPC each',
                            _quantity(ingredient.npcUnitPrice!),
                          )
                        else if (ingredient.buyCost != null)
                          _metric(
                            context,
                            'Avg. each',
                            _quantity(
                              ingredient.buyCost! / ingredient.quantity,
                            ),
                          ),
                        if (ingredient.npcUnitPrice != null &&
                            _ingredientHasMarket(ingredient))
                          _metric(
                            context,
                            'Market each',
                            ingredient.marketUnitPrice == null
                                ? '—'
                                : _estimateValue(
                                    _quantity(ingredient.marketUnitPrice!),
                                    ingredient.marketUnitPriceEstimated,
                                  ),
                            estimateExplanation:
                                ingredient.marketUnitPriceEstimated
                                ? 'Current market price. Available stock may sell at a different price.'
                                : 'Lowest listed price. Stock at this price can be limited.',
                          ),
                        if (_ingredientHasMarket(ingredient))
                          _market(
                            context,
                            ingredient.market,
                            controller.clock(),
                            maxAge: controller.cachedMarketMaxAge,
                          ),
                      ],
                    ),
                  if (_ingredientIsNonMarket(ingredient) &&
                      ingredient.npcUnitPrice == null)
                    Text('Not sold on the market', style: spec.typography.meta),
                  if (_ingredientHasMarket(ingredient) &&
                      ingredient.npcUnitPrice == null &&
                      !ingredient.coversRequest &&
                      ingredient.estimatedMarketQuantity == 0)
                    Text(
                      ingredient.depthKnown
                          ? 'Not in stock'
                          : 'Stock needs checking',
                      style: spec.typography.meta.copyWith(
                        color: spec.palette.warning,
                      ),
                    ),
                ],
              ),
              preferredMode: inspection?.sourceMode,
              resolveGatherDemand: () => PlannerGatherDemand(
                sourceId:
                    'opportunity:${inspection?.sourceMode.key ?? controller.preferences.mode.key}:${quote.recipeName}:${quote.selectedVariantId ?? 'standard'}',
                sourceLabel: quote.recipeName,
                materialName: ingredient.name,
                neededQuantity: ingredient.quantity.toDouble(),
              ),
            ),
          ),
      ]),
    ],
  );
  return LayoutBuilder(
    builder: (context, constraints) {
      final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
      final wide = constraints.maxWidth >= 1020 * scale;
      final summary = OpportunitySurface(
        key: const ValueKey('craft-money-summary'),
        role: AppSurfaceRole.card,
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            _marketDepthStatus(context, controller),
            _craftSummary(
              context,
              controller,
              quote,
              key: ValueKey('craft-result:${quote.recipeName}'),
              showDetails: true,
              inspection: inspection,
            ),
            if (note != null) ...[
              const SizedBox(height: 10),
              Text(
                note,
                style: spec.typography.meta.copyWith(
                  color: spec.palette.warning,
                ),
              ),
            ],
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 14),
              child: Divider(
                height: 1,
                color: spec.palette.trim.withAlpha(140),
              ),
            ),
            _mathLine(context, 'Sale after tax', revenue, stacked: wide),
            const SizedBox(height: 6),
            _mathLine(
              context,
              quote.extraCost > 0 ? 'Ingredients + extras' : 'Ingredients',
              quote.totalCost,
              minus: true,
              stacked: wide,
              estimateExplanation: _quoteEstimateExplanation(quote),
            ),
          ],
        ),
      );
      if (wide) {
        return Row(
          key: const ValueKey('craft-reader-columns'),
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 260,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  summary,
                  const SizedBox(height: 12),
                  _rawIngredientSalesSummary(context, controller, quote),
                ],
              ),
            ),
            const SizedBox(width: 14),
            Expanded(child: ingredients),
          ],
        );
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          summary,
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerLeft,
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: 350 * scale),
              child: _rawIngredientSalesSummary(context, controller, quote),
            ),
          ),
          const SizedBox(height: 16),
          ingredients,
        ],
      );
    },
  );
}

Widget _rawIngredientSalesSummary(
  BuildContext context,
  OpportunitiesController controller,
  OpportunityQuote quote,
) {
  final spec = context.visualTheme;
  final sales = calculateRawIngredientSales(
    ingredients: quote.ingredients,
    tax: controller.appController.marketTax.value,
    now: controller.clock(),
    maxAge: controller.cachedMarketMaxAge,
    isMarketable: isOpportunityMarketRequestEligible,
  );
  return OpportunitySurface(
    key: const ValueKey('raw-ingredient-sales'),
    role: AppSurfaceRole.card,
    padding: const EdgeInsets.all(14),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Raw ingredient sales',
          style: spec.typography.body.copyWith(
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 6),
        Text('After tax · same batch', style: spec.typography.meta),
        const SizedBox(height: 4),
        Text(
          sales.afterTax == null
              ? '—'
              : '≈ ${_quantity(sales.afterTax!)} silver',
          key: const ValueKey('raw-ingredient-sales-value'),
          style: spec.typography.body.copyWith(
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
        if (sales.unpricedNames.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            'Price unavailable: ${sales.unpricedNames.join(', ')}',
            style: spec.typography.meta.copyWith(color: spec.palette.warning),
          ),
        ],
        if (sales.excludedNames.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            'Not market-sellable: ${sales.excludedNames.join(', ')}',
            style: spec.typography.meta,
          ),
        ],
      ],
    ),
  );
}

bool _ingredientStockShortage(
  OpportunitiesController controller,
  OpportunityIngredientQuote ingredient,
) {
  if (!_ingredientHasMarket(ingredient)) return false;
  final marketNeeded = ingredient.quantity - ingredient.npcQuantity;
  if (marketNeeded <= 0) return false;
  final stock = ingredient.market?.stockFor(
    controller.clock(),
    controller.cachedMarketMaxAge,
  );
  return stock != null && stock < marketNeeded;
}

bool _ingredientHasMarket(OpportunityIngredientQuote ingredient) =>
    ingredient.itemId != null &&
    isOpportunityMarketRequestEligible(ingredient.itemId!);

bool _ingredientIsNonMarket(OpportunityIngredientQuote ingredient) =>
    reviewedNonMarketableOpportunityIds.contains(ingredient.itemId);

String _ingredientQuantityLabel(OpportunityIngredientQuote ingredient) {
  final needed = '${_quantity(ingredient.quantity)} needed';
  if (ingredient.npcQuantity == ingredient.quantity) return '$needed · NPC';
  if (_ingredientHasMarket(ingredient) &&
      ingredient.marketQuantity == ingredient.quantity) {
    return '$needed · Market';
  }
  return '$needed'
      '${ingredient.npcQuantity > 0 ? ' · ${_quantity(ingredient.npcQuantity)} from NPC' : ''}'
      '${_ingredientHasMarket(ingredient) && ingredient.marketQuantity > 0 ? ' · ${_quantity(ingredient.marketQuantity)} from market' : ''}';
}

Future<void> _craftAbout(
  BuildContext context,
  OpportunitiesController controller,
  OpportunityQuote quote, {
  OpportunityRecipeInspection? inspection,
}) => _dialog(
  context,
  'About this calculation',
  (context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Wrap(
        spacing: 24,
        runSpacing: 12,
        children: [
          _metric(context, 'Complete crafts', '${quote.crafts}'),
          _metric(
            context,
            'Expected output',
            quote.expectedOutput == null
                ? '—'
                : _quantity(quote.expectedOutput!),
          ),
          _metric(
            context,
            'Mastery',
            '${inspection?.mastery ?? _mastery(controller)}',
          ),
          if (quote.variantLabel != null)
            _metric(
              context,
              'Recipe',
              '${quote.variantLabel}${quote.batchMultiplier > 1 ? ' · ${quote.batchMultiplier}×' : ''}',
            ),
        ],
      ),
      const SizedBox(height: 12),
      for (final text in [
        'These totals are for the whole batch, not one item.',
        if (inspection?.isRareOutput == true)
          '${inspection!.itemName} is a rare result of ${inspection.recipe.name}. These are the ingredient costs for ${quote.crafts == 1 ? 'one craft' : '${quote.crafts} complete crafts'}. Profit is left blank because its chance to appear is not known.'
        else
          'Rare results and byproducts are not included.',
        if (quote.extraCost > 0)
          '${_quantity(quote.extraCost)} silver in extra costs is included.',
        'All ingredients are priced as bought, even if you already have them.',
        'Crafts are assumed to succeed. Check the required level and knowledge in game.',
        if (quote.hasUncheckedInputDepth)
          '≈ uses current prices where available sell orders have not been checked. Every ingredient is included.',
        if (quote.hasEstimatedStockShortfall)
          '≈ uses current prices for the missing quantity where there is not enough stock.',
        if (inspection?.isRareOutput != true && quote.hasCustomSalePrice)
          'Uses your custom price per item, then applies market tax. This does not confirm a preorder fill at that price.'
        else if (inspection?.isRareOutput != true &&
            controller.craftSaleMode == OpportunitySaleMode.listing)
          'Uses the listing price after tax. The item may take time to sell.'
        else if (inspection?.isRareOutput != true && quote.buyersCoverOutput)
          'There are enough preorders for this batch. Prices and orders can change.'
        else if (inspection?.isRareOutput != true)
          _craftStatus(quote, controller.craftSaleMode),
      ])
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Text(text, style: context.visualTheme.typography.body),
        ),
    ],
  ),
);

final class _IngredientRecipe {
  _IngredientRecipe(
    this.itemName,
    this.recipe, {
    this.rare = false,
    this.root = false,
    this.bestUse,
  });
  final String itemName;
  final Recipe recipe;
  final bool rare;
  final bool root;
  final OpportunityBestUseQuote? bestUse;
  String? variantId;
  int? crafts;
  int? customSalePrice;
  final choices = <String, String>{};
  final allocations = <String, Map<String, int>>{};
}

CraftMode? _recipeMode(Recipe recipe) => CraftMode.values
    .where((mode) => mode.key == recipe.type.toLowerCase())
    .firstOrNull;

_IngredientRecipe? _ingredientRecipe(
  OpportunitiesController controller,
  String name, {
  CraftMode? preferredMode,
}) {
  final folded = name.trim().toLowerCase();
  Recipe? findRecipe(String name) {
    if (preferredMode != null) {
      return controller.liveRecipeFor(name, preferredMode: preferredMode);
    }
    final key = name.trim().toLowerCase();
    // A bought ingredient in this mode can still have a recipe in another.
    // Only actual formulas may win this reference lookup.
    return controller.recipes.values
            .where(
              (recipe) =>
                  recipe.name.trim().toLowerCase() == key && recipe.isCraftable,
            )
            .firstOrNull ??
        [
          for (final mode in CraftMode.values)
            controller.catalog.recipe(mode, name),
        ].nonNulls.where((recipe) => recipe.isCraftable).firstOrNull;
  }

  final direct = findRecipe(name);
  if (direct?.isCraftable == true) return _IngredientRecipe(name, direct!);
  final rules = controller.appController.plannerRules;
  final bases = <String>{
    ...rules.cookingSpecialMap.keys,
    ...rules.blueElixirMap.keys,
    'Oatmeal',
  };
  for (final base in bases) {
    if (ingredientQualityAlternatives(rules: rules, ingredientName: base).any(
      (alternative) =>
          alternative.grade == 'blue' &&
          alternative.name.toLowerCase() == folded,
    )) {
      final recipe = findRecipe(base);
      if (recipe?.isCraftable == true) {
        return _IngredientRecipe(name, recipe!, rare: true);
      }
    }
  }
  return null;
}

Widget _ingredientRecipeLink(
  OpportunitiesController controller,
  String name,
  ValueChanged<String> onOpen,
  Widget child, {
  CraftMode? preferredMode,
  PlannerGatherDemand? Function()? resolveGatherDemand,
}) {
  final hasRecipe =
      _ingredientRecipe(controller, name, preferredMode: preferredMode) != null;
  return OpportunityItemRegion(
    controller: controller,
    name: name,
    stableId: 'ingredient:$name',
    resolveGatherDemand: resolveGatherDemand,
    resolvePlannerTarget: () {
      final recipe = _ingredientRecipe(
        controller,
        name,
        preferredMode: preferredMode,
      );
      return recipe == null
          ? null
          : _ingredientPlannerTarget(controller, recipe);
    },
    onViewRecipe: hasRecipe ? () => onOpen(name) : null,
    child: !hasRecipe
        ? child
        : Tooltip(
            message: 'View recipe',
            child: InkWell(
              key: ValueKey('ingredient-recipe-$name'),
              onTap: () => onOpen(name),
              borderRadius: BorderRadius.circular(8),
              child: Row(
                children: [
                  Expanded(child: child),
                  const SizedBox(width: 8),
                  const Icon(Icons.chevron_right, size: 20),
                ],
              ),
            ),
          ),
  );
}

PlannerTargetRequest? _ingredientPlannerTarget(
  OpportunitiesController controller,
  _IngredientRecipe selected,
) {
  if (selected.rare) return null;
  final inspection = controller.inspectRecipe(
    recipe: selected.recipe,
    itemName: selected.itemName,
    selectedVariantId: selected.variantId,
  );
  return controller.plannerTargetFor(
    selected.itemName,
    mode: inspection.sourceMode,
    variantId: inspection.quote.selectedVariantId,
  );
}

class _IngredientRecipeView extends StatefulWidget {
  const _IngredientRecipeView({
    required this.controller,
    required this.selected,
    required this.onOpen,
    super.key,
  });
  final OpportunitiesController controller;
  final _IngredientRecipe selected;
  final ValueChanged<String> onOpen;

  @override
  State<_IngredientRecipeView> createState() => _IngredientRecipeViewState();
}

class _IngredientRecipeViewState extends State<_IngredientRecipeView> {
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.controller,
    builder: (context, _) {
      final selected = widget.selected;
      final current = selected.root
          ? selected.bestUse != null
                ? widget.controller.bestUseQuotes
                      .where(
                        (use) =>
                            use.recipe.name == selected.recipe.name &&
                            use.mode == selected.bestUse!.mode,
                      )
                      .firstOrNull
                      ?.quote
                : widget.controller.quotes
                      .where(
                        (quote) => quote.recipeName == selected.recipe.name,
                      )
                      .firstOrNull
          : null;
      if (selected.root && current == null) {
        return Text(
          widget.controller.calculating
              ? 'Updating calculation…'
              : 'This recipe is no longer in the current results.',
        );
      }
      final candidates = <String, Map<String, OpportunityIngredientQuote>>{};
      final inspection = widget.controller.inspectRecipe(
        recipe: selected.recipe,
        itemName: selected.itemName,
        selectedVariantId: selected.variantId ?? current?.selectedVariantId,
        crafts: selected.crafts ?? current?.crafts ?? 1,
        customSalePrice: selected.customSalePrice,
        ingredientChoices: selected.choices,
        ingredientAllocations: selected.allocations,
        extraCostPerRun: current?.extraCostPerRun ?? 0,
        extraCostPerCraft: current?.extraCostPerCraft ?? 0,
        onInputCandidate: (original, candidate) {
          (candidates[original] ??= {})[candidate.name] = candidate;
        },
      );
      final recipe = inspection.recipe;
      return Column(
        key: ValueKey(
          selected.root ? 'root-recipe-page' : 'ingredient-recipe-page',
        ),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.end,
            children: [
              if (recipe.variants.length > 1)
                for (final variant in recipe.variants)
                  OpportunityButton.label(
                    '${variant.label}${variant.batchMultiplier > 1 ? ' · ${variant.batchMultiplier}×' : ''}',
                    selected: inspection.quote.selectedVariantId == variant.id,
                    onPressed: () {
                      setState(() {
                        selected.variantId = variant.id;
                        selected.choices.clear();
                        selected.allocations.clear();
                      });
                      widget.controller.setInspectedRecipe(
                        recipe,
                        itemName: selected.itemName,
                        selectedVariantId: variant.id,
                      );
                    },
                  ),
              _OpportunityCraftAmount(
                value: inspection.quote.crafts,
                onChanged: (value) => setState(() {
                  selected.crafts = value;
                  selected.allocations.clear();
                }),
              ),
              if (!inspection.isRareOutput)
                _OpportunityCustomSalePrice(
                  value: selected.customSalePrice,
                  onChanged: (value) => setState(() {
                    selected.customSalePrice = value;
                  }),
                ),
            ],
          ),
          const SizedBox(height: 12),
          _craftCalculationBody(
            context,
            widget.controller,
            inspection.quote,
            widget.onOpen,
            inspection: selected.root && selected.bestUse == null
                ? null
                : inspection,
            substituteGroups: candidates.entries
                .where((entry) => entry.value.length > 1)
                .map((entry) => entry.key)
                .toSet(),
            onSubstitutes: (input) async {
              for (final original in input.originalNames.where(
                (name) => (candidates[name]?.length ?? 0) > 1,
              )) {
                final changed = await _chooseOpportunitySubstitutes(
                  context,
                  widget.controller,
                  selected,
                  inspection,
                  original,
                  candidates[original]!.values.toList(),
                );
                if (changed && mounted) setState(() {});
                break;
              }
            },
          ),
        ],
      );
    },
  );
}

Widget _mathLine(
  BuildContext context,
  String label,
  double? value, {
  bool minus = false,
  bool bold = false,
  bool stacked = false,
  VoidCallback? onEdit,
  String? estimateExplanation,
}) => Padding(
  padding: const EdgeInsets.symmetric(vertical: 5),
  child: stacked
      ? Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: context.visualTheme.typography.meta),
            const SizedBox(height: 4),
            _estimateHint(
              estimateExplanation,
              Text(
                value == null
                    ? '—'
                    : _estimateValue(
                        '${minus ? '−' : ''}${_quantity(value)} silver',
                        estimateExplanation != null,
                      ),
                style: context.visualTheme.typography.body.copyWith(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        )
      : Row(
          children: [
            Expanded(
              child: onEdit != null
                  ? Align(
                      alignment: Alignment.centerLeft,
                      child: OpportunityButton.label(
                        label,
                        role: AppButtonRole.infoChip,
                        onPressed: onEdit,
                      ),
                    )
                  : Text(
                      label,
                      style: context.visualTheme.typography.body.copyWith(
                        fontWeight: bold ? FontWeight.w700 : FontWeight.w400,
                      ),
                    ),
            ),
            _estimateHint(
              estimateExplanation,
              Text(
                value == null
                    ? '—'
                    : _estimateValue(
                        '${minus ? '−' : ''}${_quantity(value)} silver',
                        estimateExplanation != null,
                      ),
                style: context.visualTheme.typography.body.copyWith(
                  fontSize: 18,
                  fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
);

Widget _estimateHint(String? explanation, Widget child) =>
    explanation == null ? child : Tooltip(message: explanation, child: child);

Future<void> _withMarketDepth(
  OpportunitiesController controller,
  Iterable<String> itemIds,
  Future<void> Function() show,
) async {
  unawaited(controller.ensureMarketDepth(itemIds));
  try {
    await show();
  } finally {
    unawaited(controller.ensureMarketDepth(const []));
  }
}

Widget _marketDepthStatus(
  BuildContext context,
  OpportunitiesController controller,
) {
  final status = controller.detailStatus;
  final notice = controller.detailNotice;
  if (!status.loading && notice == null) return const SizedBox.shrink();
  return Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Text(
      notice ?? 'Checking market details · ${status.loaded} / ${status.total}',
      key: const ValueKey('opportunities-detail-status'),
      style: context.visualTheme.typography.meta.copyWith(
        color: notice == null ? null : context.visualTheme.palette.warning,
      ),
    ),
  );
}

Widget _bookDetails(
  BuildContext context,
  OpportunityMarketItem? item,
  DateTime now, {
  Duration maxAge = OpportunitiesController.maxMarketAge,
}) {
  final spec = context.visualTheme;
  if (item == null) {
    return Text('Prices not checked yet.', style: spec.typography.meta);
  }
  final freshBook = item.bookIsFresh(now, maxAge);
  final stock = item.stockFor(now, maxAge);
  final preorders = freshBook ? item.preorderCount : null;
  final asks = freshBook ? item.asks : null;
  final bids = freshBook ? item.bids : null;
  final prices = <int>{
    for (final level in asks ?? const <OpportunityMarketLevel>[]) level.price,
    for (final level in bids ?? const <OpportunityMarketLevel>[]) level.price,
  }.toList()..sort((a, b) => b.compareTo(a));
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _MetricColumns(
        children: [
          _metric(
            context,
            item.quoteIsFresh(now, maxAge) ? 'Price' : 'Earlier price',
            item.basePrice == null ? '—' : _quantity(item.basePrice!),
          ),
          _metric(context, 'Stock', stock == null ? '—' : _quantity(stock)),
          _metric(
            context,
            'Preorders',
            preorders == null ? '—' : _quantity(preorders),
            color: preorders != null && preorders > 0
                ? spec.palette.danger
                : spec.palette.textMuted,
          ),
        ],
      ),
      const SizedBox(height: 12),
      Text(
        _date(item.quoteFetchedAt) == _date(item.bookFetchedAt)
            ? 'Checked ${_date(item.quoteFetchedAt)}'
            : 'Price: ${_date(item.quoteFetchedAt)} · Orders: ${_date(item.bookFetchedAt)}',
        style: spec.typography.meta,
      ),
      if (prices.isNotEmpty)
        ExpansionTile(
          key: ValueKey('order-price-levels-${item.itemId}'),
          tilePadding: EdgeInsets.zero,
          childrenPadding: const EdgeInsets.only(bottom: 8),
          title: Text('Orders by price', style: spec.typography.body),
          children: [
            _sales(context, item, now),
            const SizedBox(height: 12),
            Table(
              columnWidths: const {
                0: FlexColumnWidth(2),
                1: FlexColumnWidth(),
                2: FlexColumnWidth(),
              },
              defaultVerticalAlignment: TableCellVerticalAlignment.middle,
              children: [
                TableRow(
                  children: [
                    for (final heading in ['Price', 'Stock', 'Preorders'])
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text(heading, style: spec.typography.meta),
                      ),
                  ],
                ),
                for (final price in prices)
                  TableRow(
                    children: [
                      for (final cell in [
                        (_quantity(price), spec.palette.text),
                        (
                          _quantity(
                            (asks ?? const <OpportunityMarketLevel>[])
                                .where((level) => level.price == price)
                                .fold<double>(
                                  0,
                                  (sum, level) => sum + level.quantity,
                                ),
                          ),
                          spec.palette.textMuted,
                        ),
                        (
                          _quantity(
                            (bids ?? const <OpportunityMarketLevel>[])
                                .where((level) => level.price == price)
                                .fold<double>(
                                  0,
                                  (sum, level) => sum + level.quantity,
                                ),
                          ),
                          spec.palette.danger,
                        ),
                      ])
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Text(
                            cell.$1,
                            style: spec.typography.body.copyWith(
                              color: cell.$1 == '0'
                                  ? spec.palette.textMuted
                                  : cell.$2,
                            ),
                          ),
                        ),
                    ],
                  ),
              ],
            ),
          ],
        ),
    ],
  );
}

Widget _exchangePreorders(
  BuildContext context,
  OpportunityMarketItem? item,
  DateTime now, {
  required Duration maxAge,
}) {
  final spec = context.visualTheme;
  final fresh = item?.bookIsFresh(now, maxAge) == true;
  final bids = fresh
      ? (item!.bids!.where((level) => level.quantity > 0).toList()
          ..sort((a, b) => b.price.compareTo(a.price)))
      : const <OpportunityMarketLevel>[];
  return Column(
    key: ValueKey('exchange-preorders-${item?.itemId ?? 'unknown'}'),
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(
        'Preorders',
        style: spec.typography.body.copyWith(fontWeight: FontWeight.w600),
      ),
      const SizedBox(height: 10),
      if (!fresh)
        Text('Preorders not checked yet.', style: spec.typography.meta)
      else if (bids.isEmpty)
        Text('No preorders', style: spec.typography.meta)
      else
        Table(
          columnWidths: const {0: FlexColumnWidth(), 1: FlexColumnWidth(2)},
          defaultVerticalAlignment: TableCellVerticalAlignment.middle,
          children: [
            TableRow(
              children: [
                for (final heading in ['Quantity', 'Price each'])
                  Padding(
                    padding: const EdgeInsets.fromLTRB(10, 0, 10, 7),
                    child: Text(
                      heading,
                      style: spec.typography.meta,
                      textAlign: heading == 'Price each'
                          ? TextAlign.right
                          : TextAlign.left,
                    ),
                  ),
              ],
            ),
            for (var index = 0; index < bids.length; index++)
              TableRow(
                decoration: BoxDecoration(
                  color: index.isEven
                      ? spec.palette.primary.withAlpha(9)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(6),
                ),
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 9,
                    ),
                    child: Text(
                      _quantity(bids[index].quantity),
                      style: spec.typography.body.copyWith(
                        color: spec.palette.danger,
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 9,
                    ),
                    child: Text(
                      _quantity(bids[index].price),
                      textAlign: TextAlign.right,
                      style: spec.typography.body.copyWith(
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
          ],
        ),
    ],
  );
}

String _date(DateTime? value) => value == null
    ? '—'
    : '${value.toLocal().day}.${value.toLocal().month}. ${value.toLocal().hour.toString().padLeft(2, '0')}:${value.toLocal().minute.toString().padLeft(2, '0')}';

Widget _marketTimestamp(
  BuildContext context,
  OpportunitiesController controller,
) {
  final now = controller.clock();
  DateTime? first;
  DateTime? last;
  for (final item in controller.market.items.values) {
    final time = item.quoteFetchedAt;
    if (time == null || time.isAfter(now)) continue;
    if (first == null || time.isBefore(first)) first = time;
    if (last == null || time.isAfter(last)) last = time;
  }
  return Tooltip(
    message: first == null
        ? 'Refresh to load prices and stock.'
        : 'Oldest price check: ${_date(first)}\nLatest price check: ${_date(last)}\nShared across tabs for five minutes. While you stay in Opportunities, data is reused for 30 minutes and checked only when needed. Buy/sell orders keep their own check date.',
    child: Text(
      first == null ? 'Prices not loaded' : 'Prices from ${_date(first)}',
      key: const ValueKey('opportunities-market-timestamp'),
      style: context.visualTheme.typography.meta,
    ),
  );
}

Future<void> _exchangeDetails(
  BuildContext context,
  OpportunitiesController controller,
  ExchangeQuote initial,
) => _withMarketDepth(
  controller,
  [
    for (final reward in initial.route.rewards)
      if (reward.item?.marketable == true) '${reward.item!.id}',
  ],
  () => _dialog(
    context,
    initial.route.rewardContainer?.name ??
        (initial.route.rewards.length == 1
            ? '${initial.route.rewards.single.quantity > 1 ? '${_quantity(initial.route.rewards.single.quantity)}× ' : ''}${initial.route.rewards.single.name}'
            : 'Exchange rewards'),
    (context) => AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final quote =
            controller.exchangeQuotes
                .where((q) => q.route.id == initial.route.id)
                .firstOrNull ??
            initial;
        final route = quote.route;
        final display = quote.displayQuote;
        final marketReward = route.rewards.length == 1
            ? route.rewards.single.item
            : null;
        final spec = context.visualTheme;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _marketDepthStatus(context, controller),
            Row(
              children: [
                _exchangeIcon(quote.currency.item, 32),
                const SizedBox(width: 10),
                Expanded(
                  child: route.directVendorSale
                      ? Text('Sell to NPC', style: spec.typography.body)
                      : OpportunityCopyName(
                          name: quote.currency.item.name,
                          displayLabel:
                              '${_quantity(route.inputCount)} ${quote.currency.item.name}',
                          style: spec.typography.body,
                        ),
                ),
              ],
            ),
            if (_exchangeCardNote(quote) case final note?) ...[
              const SizedBox(height: 10),
              Text(
                note,
                style: spec.typography.meta.copyWith(
                  color: spec.palette.warning,
                ),
              ),
            ],
            if (route.rewardContainer != null || route.rewards.length > 1) ...[
              const SizedBox(height: 16),
              for (final reward in route.rewards)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    children: [
                      if (reward.item case final item?) _exchangeIcon(item, 40),
                      const SizedBox(width: 10),
                      Expanded(
                        child: OpportunityCopyName(
                          name: reward.name,
                          displayLabel:
                              '${_quantity(reward.quantity)}× ${reward.name}',
                        ),
                      ),
                    ],
                  ),
                ),
            ],
            if (!route.limit.isRepeatable) ...[
              const SizedBox(height: 18),
              Text(
                'Remaining exchanges · ${route.limit.label}',
                style: spec.typography.body.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (
                    var count = 0;
                    count <= (route.limit.maximum ?? 1);
                    count++
                  )
                    OpportunityButton.label(
                      '$count',
                      selected:
                          controller.preferences.remainingLimits[route.id] ==
                          count,
                      onPressed: () => controller.change(
                        (p) => p.remainingLimits[route.id] = count,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Text('For this session', style: spec.typography.meta),
            ],
            if (route.requirements.isNotEmpty) ...[
              const SizedBox(height: 12),
              for (final requirement in route.requirements)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(requirement),
                ),
              OpportunityFilterButton(
                selected: controller.preferences.confirmedRequirements.contains(
                  route.id,
                ),
                label: 'Requirements met',
                onChanged: (value) => controller.change(
                  (p) => value
                      ? p.confirmedRequirements.add(route.id)
                      : p.confirmedRequirements.remove(route.id),
                ),
              ),
            ],
            const SizedBox(height: 20),
            OpportunitySurface(
              key: const ValueKey('exchange-detail-summary'),
              role: AppSurfaceRole.card,
              padding: const EdgeInsets.all(16),
              child: _MetricColumns(
                children: [
                  _metric(
                    context,
                    quote.isReference ? 'Value' : 'Total value',
                    _silver(display.netProceeds),
                    large: true,
                    color: display.isRankable
                        ? spec.palette.success
                        : spec.palette.textMuted,
                    estimateExplanation: _exchangeValueHelp(quote),
                  ),
                  _metric(
                    context,
                    _exchangeUnitLabel(quote.currency),
                    _silver(display.valuePerCurrency),
                  ),
                  if (marketReward?.marketable == true)
                    _market(
                      context,
                      controller.market.items['${marketReward!.id}'],
                      controller.clock(),
                      large: true,
                      maxAge: controller.cachedMarketMaxAge,
                    ),
                ],
              ),
            ),
            for (final reward in route.rewards)
              if (reward.item?.marketable == true)
                Padding(
                  padding: const EdgeInsets.only(top: 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (route.rewards.length > 1) ...[
                        OpportunityCopyName(
                          name: reward.name,
                          style: spec.typography.body.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 8),
                      ],
                      _exchangePreorders(
                        context,
                        controller.market.items['${reward.item!.id}'],
                        controller.clock(),
                        maxAge: controller.cachedMarketMaxAge,
                      ),
                    ],
                  ),
                ),
          ],
        );
      },
    ),
    maxWidth: 700,
    copyTitleName:
        initial.route.rewardContainer?.name ??
        (initial.route.rewards.length == 1
            ? initial.route.rewards.single.name
            : null),
    icon: initial.route.rewardContainer != null
        ? _exchangeIcon(initial.route.rewardContainer!, 52)
        : initial.route.rewards.length == 1 &&
              initial.route.rewards.single.item != null
        ? _exchangeIcon(initial.route.rewards.single.item!, 52)
        : null,
  ),
);

Future<void> _taxDialog(
  BuildContext context,
  OpportunitiesController controller,
) => _dialog(
  context,
  'Market settings',
  (context) => AnimatedBuilder(
    animation: Listenable.merge([
      controller,
      controller.appController.marketTax,
    ]),
    builder: (context, _) {
      final tax = controller.appController.marketTax.value;
      final spec = context.visualTheme;
      void update({bool? valuePack, bool? ring, double? fame}) =>
          controller.appController.updateDocument(
            (state) => state.copyWith(
              marketTax: MarketTax(
                enabled: tax.enabled,
                valuePack: valuePack ?? tax.valuePack,
                merchantRing: ring ?? tax.merchantRing,
                familyFameBonus: fame ?? tax.familyFameBonus,
                extensions: tax.extensions,
              ),
            ),
          );
      return Column(
        key: const ValueKey('market-settings-content'),
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 18,
            runSpacing: 10,
            children: [
              Text('Region', style: spec.typography.body),
              _switches(context, [
                (
                  'EU',
                  controller.preferences.region == 'eu',
                  () => controller.change((p) => p.region = 'eu'),
                ),
                (
                  'NA',
                  controller.preferences.region == 'na',
                  () => controller.change((p) => p.region = 'na'),
                ),
              ]),
            ],
          ),
          const SizedBox(height: 20),
          _MarketBonusSetting(
            artwork: MarketBonusArtwork.valuePack,
            label: 'Value Pack',
            selected: tax.valuePack,
            onChanged: (value) => update(valuePack: value),
          ),
          const SizedBox(height: 12),
          _MarketBonusSetting(
            artwork: MarketBonusArtwork.richMerchantsRing,
            label: 'Rich Merchant’s Ring',
            selected: tax.merchantRing,
            onChanged: (value) => update(ring: value),
          ),
          const SizedBox(height: 18),
          _numberInput(
            'Family Fame %',
            tax.familyFameBonus * 100,
            (value) {
              if (value <= 1.5) update(fame: value / 100);
            },
            width: 170 * MediaQuery.textScalerOf(context).scale(14) / 14,
            maximum: 1.5,
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: OpportunitySurface(
              key: const ValueKey('market-settings-receipt'),
              role: AppSurfaceRole.card,
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('You receive', style: spec.typography.meta),
                  const SizedBox(height: 6),
                  Text(
                    '${_percent(marketNetRate(tax) * 100)}% of each market sale',
                    style: spec.typography.body.copyWith(
                      fontSize: 22,
                      fontWeight: FontWeight.w600,
                      color: spec.palette.success,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Market tax · ${_percent((1 - marketNetRate(tax)) * 100)}%',
                    style: spec.typography.meta,
                  ),
                ],
              ),
            ),
          ),
        ],
      );
    },
  ),
  maxWidth: 520,
);

class _MarketBonusSetting extends StatelessWidget {
  const _MarketBonusSetting({
    required this.artwork,
    required this.label,
    required this.selected,
    required this.onChanged,
  });

  final MarketBonusArtwork artwork;
  final String label;
  final bool selected;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => Semantics(
    toggled: selected,
    child: OpportunityButton(
      key: ValueKey('market-setting-${artwork.name}'),
      selected: selected,
      semanticLabel: label,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      onPressed: () => onChanged(!selected),
      child: Row(
        children: [
          MarketBonusIcon(artwork: artwork, size: 44),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              label,
              style: context.visualTheme.typography.body.copyWith(
                fontSize: 17,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Icon(
            selected ? Icons.check_circle : Icons.circle_outlined,
            size: 22,
            color: selected
                ? context.visualTheme.palette.primaryBright
                : context.visualTheme.palette.textMuted,
          ),
        ],
      ),
    ),
  );
}

int _mastery(OpportunitiesController controller) =>
    switch (controller.preferences.mode) {
      CraftMode.cooking => controller.state.cookingMastery,
      CraftMode.alchemy => controller.state.alchemyMastery,
      CraftMode.processing => controller.state.processingMastery,
    };
