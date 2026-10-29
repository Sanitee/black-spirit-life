import 'dart:async';
import 'dart:math' as math;

import 'package:bdo_craft_planner_flutter/visual/components/app_tooltip.dart';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';

import '../../data/opportunities/exchange_catalog.dart';
import '../../data/opportunities/exchange_item_details.dart';
import '../../data/opportunities/market_eligibility.dart';
import '../../domain/formatting/planner_formatters.dart';
import '../../domain/market/market_calculations.dart';
import '../../domain/market/market_price_models.dart'
    show normalizeNumericMarketId;
import '../../domain/models/catalog_models.dart';
import '../../domain/models/craft_mode.dart';
import '../../domain/opportunities/exchange_models.dart';
import '../../domain/opportunities/opportunity_best_use.dart';
import '../../domain/opportunities/opportunity_calculator.dart';
import '../../domain/opportunities/opportunity_card_reading.dart';
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
import '../recipe_book/recipe_book_item_info.dart';
import '../recipe_book/recipe_book_item_info_view.dart';
import '../shared/mode_item_icon.dart';
import '../shared/profile_game_icon.dart';
import 'opportunities_content_viewport.dart';
import 'opportunities_controller.dart';
import 'opportunities_item_actions.dart';
import 'opportunities_theme.dart';
import 'opportunities_visuals.dart';
import 'opportunity_craft_card_material.dart';
import 'opportunity_glass_finish.dart';
import 'opportunity_inventory_input.dart';
import 'opportunity_market_progress.dart';
import 'opportunity_recipe_controls.dart';
import 'opportunity_refresh_control.dart';
import 'opportunity_silver_amount.dart';

part 'opportunity_substitutes.dart';
part 'opportunity_detail_inputs.dart';
part 'opportunity_crafting_toolbar.dart';
part 'opportunity_best_use_pane.dart';
part 'opportunity_best_use_details.dart';
part 'opportunity_exchange_items.dart';
part 'opportunity_content_fit.dart';
part 'opportunity_expanding_card.dart';

class OpportunitiesWorkspace extends StatefulWidget {
  const OpportunitiesWorkspace({
    required this.controller,
    this.active = true,
    this.theme,
    this.onContentMaximumChanged,
    super.key,
  });
  final OpportunitiesController controller;
  final bool active;
  final ValueListenable<ThemeSpec>? theme;
  final ValueChanged<double>? onContentMaximumChanged;

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
  Widget build(BuildContext context) => OpportunitiesTheme(
    theme: widget.theme,
    child: AppOverlayCoordinatorHost(
      onEscapeUnhandled: () => _navigator.currentState?.maybePop(),
      child: Navigator(
        key: _navigator,
        onGenerateRoute: (settings) => MaterialPageRoute<void>(
          settings: settings,
          builder: (_) => _OpportunitiesContent(
            controller: widget.controller,
            onContentMaximumChanged: widget.onContentMaximumChanged,
          ),
        ),
      ),
    ),
  );
}

class _OpportunitiesContent extends StatelessWidget {
  const _OpportunitiesContent({
    required this.controller,
    this.onContentMaximumChanged,
  });
  final OpportunitiesController controller;
  final ValueChanged<double>? onContentMaximumChanged;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    builder: (context, _) => ScrollConfiguration(
      behavior: const AppScrollBehavior(),
      child: _OpportunityBody(
        controller: controller,
        onContentMaximumChanged: onContentMaximumChanged,
      ),
    ),
  );
}

class _OpportunityBody extends StatefulWidget {
  const _OpportunityBody({
    required this.controller,
    this.onContentMaximumChanged,
  });
  final OpportunitiesController controller;
  final ValueChanged<double>? onContentMaximumChanged;

  @override
  State<_OpportunityBody> createState() => _OpportunityBodyState();
}

class _OpportunityBodyState extends State<_OpportunityBody> {
  // Reparent the same live panes at the rail breakpoint: keep search focus,
  // scroll positions and the lazy market-interest owners intact on resize.
  final _panes = GlobalKey();
  final _contentFitCache = _OpportunityFitCache();
  OpportunitiesController get controller => widget.controller;

  @override
  Widget build(BuildContext context) {
    if (controller.loading) {
      return const Center(child: CircularProgressIndicator());
    }
    final p = controller.preferences;
    final spec = context.visualTheme;
    final choices = <(String, bool, VoidCallback)>[
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
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
        final rail = constraints.maxWidth >= 1120 * scale;
        final content = KeyedSubtree(
          key: _panes,
          child: OpportunitiesContentViewport(
            scale: controller.contentScale,
            onMaximumChanged: widget.onContentMaximumChanged,
            maximumFor: (size) => _opportunitiesMaximum(
              context,
              controller,
              size,
              _contentFitCache,
              rail: rail,
            ),
            child: IndexedStack(
              key: const ValueKey('opportunities-panes'),
              index: switch (p.section) {
                'exchanges' => 1,
                'best-use' => 2,
                _ => 0,
              },
              children: [
                _CraftingPane(controller: controller, showModeTabs: !rail),
                _ExchangePane(controller: controller),
                _BestUsePane(controller: controller, showSortControl: !rail),
              ],
            ),
          ),
        );
        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Wrap(
                key: const ValueKey('opportunities-header'),
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 20,
                runSpacing: 10,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Image.asset(
                        'assets/opportunities/items/66771.webp',
                        key: const ValueKey('opportunities-brand-icon'),
                        width: 30,
                        height: 30,
                        filterQuality: FilterQuality.high,
                      ),
                      const SizedBox(width: 10),
                      Text('Opportunities', style: spec.typography.display),
                    ],
                  ),
                  Wrap(
                    spacing: 10,
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
                          horizontal: 10,
                          vertical: 6,
                        ),
                        onPressed: () => _taxDialog(context, controller),
                      ),
                      OpportunityRefreshControl(controller: controller),
                    ],
                  ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.only(top: 8, bottom: 12),
                child: Row(
                  children: [
                    Expanded(
                      child: Divider(
                        height: 1,
                        color: spec.palette.trim.withAlpha(100),
                      ),
                    ),
                    const SizedBox(width: 12),
                    _marketTimestamp(context, controller),
                  ],
                ),
              ),
              Column(
                key: const ValueKey('opportunities-market-progress'),
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  OpportunityMarketProgress(
                    status: controller.summaryStatus,
                    showLoading: false,
                    label: controller.summaryStatus.loading
                        ? 'Loading prices'
                        : 'Prices',
                  ),
                  OpportunityMarketProgress(
                    status: controller.detailStatus,
                    showLoading: false,
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
                      padding: const EdgeInsets.only(bottom: 8),
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
              Expanded(
                child: rail
                    ? Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          SizedBox(
                            key: const ValueKey('opportunities-sidebar'),
                            width: 134 * scale,
                            child: SingleChildScrollView(
                              child: _WorkbenchNavigation(
                                choices: choices,
                                controller: controller,
                              ),
                            ),
                          ),
                          const SizedBox(width: 22),
                          Expanded(child: content),
                        ],
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _DeskTabs(choices: choices),
                          const SizedBox(height: 12),
                          Expanded(child: content),
                        ],
                      ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _WorkbenchNavigation extends StatelessWidget {
  const _WorkbenchNavigation({required this.choices, required this.controller});
  final List<(String, bool, VoidCallback)> choices;
  final OpportunitiesController controller;

  @override
  Widget build(BuildContext context) {
    final spec = context.visualTheme;
    return Column(
      key: const ValueKey('opportunities-sections'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (index, choice) in choices.indexed) ...[
          if (index > 0) const SizedBox(height: 8),
          OpportunityButton(
            key: ValueKey('opportunities-section-${choice.$1.toLowerCase()}'),
            role: AppButtonRole.infoChip,
            selected: choice.$2,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
            onPressed: choice.$3,
            child: Row(
              children: [
                Icon(
                  switch (index) {
                    0 => Icons.auto_awesome_outlined,
                    1 => Icons.swap_horiz_rounded,
                    _ => Icons.diamond_outlined,
                  },
                  size: 19,
                  color: choice.$2
                      ? spec.palette.primary
                      : spec.palette.textMuted,
                ),
                const SizedBox(width: 10),
                Expanded(child: Text(choice.$1)),
              ],
            ),
          ),
        ],
        if (controller.preferences.section == 'crafting') ...[
          const SizedBox(height: 20),
          Divider(height: 1, color: spec.palette.trim.withAlpha(90)),
          const SizedBox(height: 12),
          _CraftModeTabs(controller: controller, vertical: true),
        ],
        if (controller.preferences.section != 'exchanges') ...[
          const SizedBox(height: 20),
          Divider(height: 1, color: spec.palette.trim.withAlpha(90)),
          const SizedBox(height: 12),
          _CraftSortControl(controller: controller, vertical: true),
        ],
      ],
    );
  }
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

class _CraftingPane extends StatefulWidget {
  const _CraftingPane({required this.controller, required this.showModeTabs});
  final OpportunitiesController controller;
  final bool showModeTabs;
  @override
  State<_CraftingPane> createState() => _CraftingPaneState();
}

class _CraftingPaneState extends State<_CraftingPane> {
  (CraftMode, String)? _expanded;
  OpportunitiesController get controller => widget.controller;

  @override
  Widget build(BuildContext context) {
    final p = controller.preferences;
    final spec = context.visualTheme;
    final rows = controller.visibleQuotes;
    return _cardList(
      context,
      count: rows.length,
      keyName: 'craft-opportunities',
      minimumCardWidth: OpportunityCraftCardLayout.minimumWidth,
      maximumCardWidth: OpportunityCraftCardLayout.maximumWidth,
      maximumColumns: OpportunityCraftCardLayout.maximumColumns,
      independentColumns: true,
      header: Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _CraftingToolbar(
              controller: controller,
              showModeTabs: widget.showModeTabs,
              showSortControl: widget.showModeTabs,
            ),
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
                  p.useInventory
                      ? 'Profit from crafting compares crafting and selling with selling the owned ingredients instead. Only the ingredients used for this craft count.'
                      : 'Profit is the main product’s sale price after tax, minus the cost of buying the ingredients.',
                  'Card amounts are per expected main item, using the selected recipe’s average output. Costs include entered extra expenses and, with inventory, the sale value of owned ingredients consumed.',
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
      builder: (index) => _CraftCard(
        key: ValueKey('craft:${p.mode.name}:${rows[index].recipeName}'),
        controller: controller,
        quote: rows[index],
        expanded: _expanded == (p.mode, rows[index].recipeName),
        onToggle: () => setState(() {
          final selection = (p.mode, rows[index].recipeName);
          _expanded = _expanded == selection ? null : selection;
        }),
      ),
    );
  }
}

class _CraftCard extends StatefulWidget {
  const _CraftCard({
    required this.controller,
    required this.quote,
    this.bestUse,
    this.expanded = false,
    this.onToggle,
    super.key,
  });
  final OpportunitiesController controller;
  final OpportunityQuote quote;
  final OpportunityBestUseQuote? bestUse;
  final bool expanded;
  final VoidCallback? onToggle;

  @override
  State<_CraftCard> createState() => _CraftCardState();
}

class _CraftCardState extends State<_CraftCard> {
  OpportunitiesController get controller => widget.controller;
  OpportunityQuote get quote => widget.quote;
  bool _bestUseExpanded = false;

  @override
  void initState() {
    super.initState();
    _registerMarketInterest();
  }

  @override
  void didUpdateWidget(covariant _CraftCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.quote.recipeName != quote.recipeName ||
        oldWidget.bestUse?.quote.selectedVariantId !=
            widget.bestUse?.quote.selectedVariantId) {
      _bestUseExpanded = false;
    }
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
    if (widget.bestUse == null) {
      return _ExpandingCraftCard(
        controller: controller,
        quote: quote,
        expanded: widget.expanded,
        onToggle: widget.onToggle!,
      );
    }
    final spec = context.visualTheme;
    final use = widget.bestUse;
    final resolvedUse = use!;
    void open() =>
        _craftDetails(context, controller, quote, bestUse: resolvedUse);
    void toggleCalculation() =>
        setState(() => _bestUseExpanded = !_bestUseExpanded);
    return OpportunityItemRegion(
      controller: controller,
      name: quote.recipeName,
      stableId: 'craft-card:${quote.recipeName}',
      plannerMode: use.mode,
      plannerVariantId: quote.selectedVariantId,
      onViewRecipe: open,
      childHandlesFocus: true,
      child: OpportunityCardMotion(
        child: OpportunitySurface(
          key: ValueKey('craft-card:${quote.recipeName}'),
          role: AppSurfaceRole.card,
          padding: EdgeInsets.zero,
          decoration: OpportunityGlassFinish.of(context).card,
          child: OpportunityCraftCardFinish(
            artworkRail: false,
            child: InkWell(
              onTap: toggleCalculation,
              borderRadius: BorderRadius.circular(8),
              hoverColor: spec.palette.primary.withAlpha(12),
              focusColor: spec.palette.primary.withAlpha(28),
              child: Padding(
                padding: const EdgeInsets.all(
                  OpportunitiesVisualSpec.craftCardPadding,
                ),
                child: _bestUseCardContent(
                  context,
                  controller,
                  resolvedUse,
                  expanded: _bestUseExpanded,
                  onToggle: toggleCalculation,
                ),
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

Widget _craftSummary(
  BuildContext context,
  OpportunitiesController controller,
  OpportunityQuote quote, {
  Key? key,
  bool showDetails = false,
  OpportunityRecipeInspection? inspection,
}) {
  final palette = context.visualTheme.palette;
  final total = quote.cashProfitFor(controller.craftSaleMode);
  return KeyedSubtree(
    key: key,
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ...[
          Row(
            children: [
              Expanded(
                child: Text(
                  'Craft & sell',
                  style: context.visualTheme.typography.body.copyWith(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              OpportunityButton.icon(
                key: const ValueKey('craft-calculation-info'),
                icon: const Icon(Icons.info_outline, size: 17),
                semanticLabel: 'About this calculation',
                onPressed: () => _craftAbout(
                  context,
                  controller,
                  quote,
                  inspection: inspection,
                ),
              ),
            ],
          ),
          Text(
            'After tax and investment',
            style: context.visualTheme.typography.meta,
          ),
          const SizedBox(height: 8),
        ],
        _MetricColumns(
          children: [
            _metric(
              context,
              '',
              _estimateValue(_silver(total), quote.hasEstimatedInputs),
              silverAmount: total,
              estimateExplanation: _quoteEstimateExplanation(quote),
              color: total == null
                  ? palette.textMuted
                  : total > 0
                  ? palette.success
                  : palette.danger,
              large: true,
              valueFontSize: 18,
            ),
            _market(
              context,
              inspection == null
                  ? controller.outputMarketFor(quote.recipeName)
                  : quote.outputMarket,
              controller.clock(),
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
                                    ? controller.outputMarketFor(
                                        quote.recipeName,
                                      )
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
      ],
    ),
  );
}

class _ExchangePane extends StatelessWidget {
  const _ExchangePane({required this.controller});
  final OpportunitiesController controller;
  @override
  Widget build(BuildContext context) {
    final spec = context.visualTheme;
    final currency = controller.currency;
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
              child: _exchangeIcon(controller, currency.item, 48),
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
          width: 150 * MediaQuery.textScalerOf(context).scale(14) / 14,
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
    return ListView(
      key: PageStorageKey('exchange-${currency.id}'),
      children: [
        OpportunitySurface(
          key: const ValueKey('exchange-toolbar'),
          role: AppSurfaceRole.panel,
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              identity,
              const SizedBox(height: 10),
              Align(
                alignment: Alignment.centerLeft,
                child: _ExchangeCurrencyChooser(controller: controller),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        _DeskSection(
          title: 'Repeatable',
          meta: '${repeatable.length}',
          trailing: _info(context, 'Exchange value', [
            'Each card is a different way to use the same items. Do not add their values together.',
            'Value is what you receive after selling the reward. It is not crafting profit.',
            'Values are per item. Enter a balance only if you want totals.',
            'Only whole exchanges count. Leftover items stay in your balance.',
            'Market rewards use the listing price after tax. NPC rewards use their shop value.',
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

class _ExchangeCurrencyChooser extends StatelessWidget {
  const _ExchangeCurrencyChooser({required this.controller});
  final OpportunitiesController controller;

  @override
  Widget build(BuildContext context) => AnchoredPopover(
    overlayId: 'exchange-currency',
    preferredWidth: 440,
    maximumHeight: 510,
    popoverBuilder: (context, close) => AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final search = controller.preferences.exchangeSearch
            .trim()
            .toLowerCase();
        final items = exchangeCatalog
            .where(
              (currency) =>
                  search.isEmpty ||
                  currency.item.name.toLowerCase().contains(search),
            )
            .toList();
        return OpportunitySurface(
          role: AppSurfaceRole.popup,
          padding: const EdgeInsets.all(10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _TextInput(
                key: const ValueKey('exchange-search'),
                label: 'Find an exchange item',
                value: controller.preferences.exchangeSearch,
                onChanged: (value) =>
                    controller.change((p) => p.exchangeSearch = value),
                prefix: const Icon(Icons.search, size: 18),
              ),
              const SizedBox(height: 10),
              Flexible(
                child: ListView.separated(
                  key: const ValueKey('exchange-currency-picker'),
                  shrinkWrap: true,
                  itemCount: items.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 4),
                  itemBuilder: (context, index) {
                    final currency = items[index];
                    return OpportunityButton(
                      key: ValueKey('exchange-currency-${currency.id}'),
                      role: AppButtonRole.infoChip,
                      selected: currency.id == controller.currency.id,
                      semanticLabel: currency.item.name,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 8,
                      ),
                      onPressed: () {
                        controller.change((p) => p.currencyId = currency.id);
                        close();
                      },
                      child: Row(
                        children: [
                          _exchangeIcon(controller, currency.item, 36),
                          const SizedBox(width: 12),
                          Expanded(child: Text(currency.item.name)),
                          if (currency.id == controller.currency.id)
                            const Icon(Icons.check, size: 18),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    ),
    anchorBuilder: (context, toggle, showing) => OpportunityButton(
      key: const ValueKey('exchange-choose-item'),
      role: AppButtonRole.infoChip,
      selected: showing,
      onPressed: toggle,
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('Change item'),
          SizedBox(width: 8),
          Icon(Icons.expand_more, size: 18),
        ],
      ),
    ),
  );
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
    final hasValue = _showExchangeValue(quote);
    final hasStock =
        marketReward?.marketable == true &&
        controller.market.items['${marketReward!.id}']?.stockFor(
              controller.clock(),
              controller.cachedMarketMaxAge,
            ) !=
            null;
    void open() => _exchangeDetails(context, controller, quote);
    return OpportunityCardMotion(
      child: OpportunitySurface(
        role: AppSurfaceRole.card,
        decoration: OpportunityGlassFinish.of(
          context,
        ).card.copyWith(boxShadow: const []),
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
                                  OpportunityItemMount(
                                    size: 56,
                                    child: _exchangeIcon(
                                      controller,
                                      container,
                                      48,
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: _exchangeName(
                                      controller,
                                      container,
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
                                    OpportunityItemMount(
                                      size: 56,
                                      child: _exchangeIcon(
                                        controller,
                                        item,
                                        48,
                                      ),
                                    )
                                  else
                                    Icon(
                                      Icons.auto_awesome_outlined,
                                      size: 30,
                                      color: spec.palette.textMuted,
                                    ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: reward.item == null
                                        ? OpportunityCopyName(name: reward.name)
                                        : _exchangeName(
                                            controller,
                                            reward.item!,
                                            displayLabel:
                                                '${route.rewardContainer != null ? 'Contains ' : ''}${reward.quantity > 1 ? '${_quantity(reward.quantity.toDouble())}× ' : ''}${reward.name}',
                                            style: spec.typography.body
                                                .copyWith(
                                                  fontSize:
                                                      OpportunitiesVisualSpec
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
                  _exchangeName(
                    controller,
                    quote.currency.item,
                    displayLabel:
                        '${_quantity(route.inputCount.toDouble())} ${quote.currency.item.name}',
                    style: spec.typography.meta.copyWith(
                      fontSize: OpportunitiesVisualSpec.cardLabelFontSize,
                    ),
                  ),
                if (hasValue || hasStock) ...[
                  const SizedBox(height: 14),
                  _MetricColumns(
                    children: [
                      if (hasValue)
                        _metric(
                          context,
                          quote.isReference ? 'Value' : 'Total value',
                          _silver(display.netProceeds),
                          large: true,
                          valueFontSize:
                              OpportunitiesVisualSpec.cardPrimaryValueFontSize,
                          valueFontWeight: FontWeight.w600,
                          labelFontSize:
                              OpportunitiesVisualSpec.cardLabelFontSize,
                          color: display.isRankable
                              ? spec.palette.success
                              : spec.palette.textMuted,
                          estimateExplanation: _exchangeValueHelp(quote),
                        ),
                      if (hasValue)
                        _metric(
                          context,
                          _exchangeUnitLabel(quote.currency),
                          _silver(display.valuePerCurrency),
                          valueFontSize: OpportunitiesVisualSpec
                              .cardSecondaryValueFontSize,
                          labelFontSize:
                              OpportunitiesVisualSpec.cardLabelFontSize,
                        ),
                      if (hasStock)
                        _market(
                          context,
                          controller.market.items['${marketReward.id}'],
                          controller.clock(),
                          maxAge: controller.cachedMarketMaxAge,
                        ),
                    ],
                  ),
                ],
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
    ExchangeAvailability.available => null,
    ExchangeAvailability.confirmationNeeded => null,
    ExchangeAvailability.limitReached => 'None remaining',
    ExchangeAvailability.notEnoughCurrency => 'Not enough items',
    ExchangeAvailability.marketUnknown => null,
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
    fit: BoxFit.contain,
  );
  final preview = RecipeBookItemInfoHover(
    controller: controller.itemInfoController,
    name: name,
    mode: mode ?? controller.modeController.mode,
    child: artwork,
  );
  return framed
      ? Padding(
          key: ValueKey('craft-artwork-frame:$name'),
          padding: const EdgeInsets.all(9),
          child: preview,
        )
      : preview;
}

Widget _exchangeIcon(
  OpportunitiesController controller,
  ExchangeItem item,
  double size,
) => _exchangeItemRegion(
  controller,
  item,
  child: _exchangeArtwork(controller, item, size),
);

Widget _exchangeArtwork(
  OpportunitiesController controller,
  ExchangeItem item,
  double size,
) => ItemIconFrame(
  size: size,
  grade:
      controller.catalog.itemIconGradeById(item.id) ??
      controller.catalog.itemIconGrade(item.name),
  child: Image.asset(
    item.iconAsset,
    fit: BoxFit.contain,
    filterQuality: FilterQuality.high,
    semanticLabel: item.name,
  ),
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
    : '${_quantity(ingredient.estimatedMarketQuantity)} estimated at ${_quantity(ingredient.estimatedUnitPrice!)} silver each. ${ingredient.estimatedFromPreorder
          ? 'Highest current preorder; waiting for sellers.'
          : ingredient.estimateKind == OpportunityInputEstimateKind.uncheckedDepth
          ? 'Available sell orders have not been checked.'
          : 'There is not enough stock for this quantity.'}';

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
  double? silverAmount,
}) => _MetricValue(
  label: label,
  value: silverAmount == null
      ? value
      : '${value.startsWith('≈ ') ? '≈ ' : ''}${formatCompactOpportunitySilver(silverAmount)}',
  silverAmount: silverAmount,
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
    this.silverAmount,
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
  final double? silverAmount;

  TextStyle valueStyle(BuildContext context) =>
      context.visualTheme.typography.body.copyWith(
        fontSize: valueFontSize ?? 18,
        fontWeight:
            valueFontWeight ??
            (large && label != 'Stock' ? FontWeight.w700 : FontWeight.w500),
        color: color == null
            ? context.visualTheme.palette.text
            : OpportunitiesVisualSpec.readableValueColor(
                context.visualTheme,
                color!,
              ),
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
      if (label.isNotEmpty)
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
              Semantics(
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
            ],
          ],
        ),
      if (label.isNotEmpty) const SizedBox(height: 3),
      _estimateHint(
        value == '—' ? null : estimateExplanation,
        silverAmount != null
            ? OpportunitySilverAmount(
                value: silverAmount,
                estimated: value.startsWith('≈ '),
                style: valueStyle(context),
              )
            : Text(value, style: valueStyle(context)),
      ),
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
      for (final value in children) {
        if (value is _MetricValue) {
          minimumWidth = math.max(minimumWidth, value.minimumWidth(context));
        }
        if (value is _MarketStockBadge) {
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
  final negative = stock == 0 && bids != null && bids > 0;
  final text = negative
      ? '−${_quantity(bids)}'
      : stock == null
      ? '—'
      : _quantity(stock);
  return (text, negative);
}

_MarketStockBadge _market(
  BuildContext context,
  OpportunityMarketItem? item,
  DateTime now, {
  VoidCallback? onDetails,
  Duration maxAge = OpportunitiesController.maxMarketAge,
}) {
  final spec = context.visualTheme;
  final (text, negative) = _marketReading(item, now, maxAge);
  final stock = item?.stockFor(now, maxAge);
  final preorders = item?.bookIsFresh(now, maxAge) == true
      ? item?.preorderCount
      : null;
  return _MarketStockBadge(
    text: text,
    color: negative
        ? spec.palette.danger
        : stock != null && stock > 0
        ? spec.palette.success
        : spec.palette.textMuted,
    semanticDescription:
        'Stock: ${stock == null ? 'Not checked' : _quantity(stock)}\nPreorders: ${preorders == null ? 'Not checked' : _quantity(preorders)}${negative ? '\nThe red negative count shows preorders when nothing is listed.' : ''}',
    onDetails: onDetails,
  );
}

// One content-sized stock treatment for outputs, ingredients and substitutes.
class _MarketStockBadge extends StatelessWidget {
  const _MarketStockBadge({
    required this.text,
    required this.color,
    required this.semanticDescription,
    this.textKey,
    this.onDetails,
  });
  final String text;
  final Color color;
  final String semanticDescription;
  final Key? textKey;
  final VoidCallback? onDetails;
  TextStyle _valueStyle(BuildContext context) =>
      context.visualTheme.typography.body.copyWith(
        fontSize: 16,
        fontWeight: FontWeight.w700,
        color: OpportunitiesVisualSpec.readableValueColor(
          context.visualTheme,
          color,
        ),
      );
  double minimumWidth(BuildContext context) {
    final painter = TextPainter(
      text: TextSpan(text: 'Stock $text', style: _valueStyle(context)),
      textScaler: MediaQuery.textScalerOf(context),
      textDirection: Directionality.of(context),
    )..layout();
    final width =
        painter.width.ceilToDouble() + 18 + (onDetails == null ? 0 : 27);
    painter.dispose();
    return width;
  }

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      widthFactor: 1,
      child: DecoratedBox(
        key: const ValueKey('market-stock-badge'),
        decoration: BoxDecoration(
          color: color.withAlpha(25),
          border: Border.all(color: color.withAlpha(95)),
          borderRadius: BorderRadius.circular(5),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Wrap(
            spacing: 4,
            runSpacing: 2,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Semantics(
                label: semanticDescription,
                excludeSemantics: true,
                child: Text(
                  'Stock $text',
                  key: textKey,
                  style: _valueStyle(context),
                ),
              ),
              if (onDetails != null)
                Semantics(
                  button: true,
                  label: 'Market details',
                  child: InkResponse(
                    key: const ValueKey('craft-market-details'),
                    onTap: onDetails,
                    radius: 16,
                    child: Padding(
                      padding: const EdgeInsets.all(3),
                      child: Icon(
                        Icons.info_outline,
                        size: 17,
                        color: OpportunitiesVisualSpec.readableValueColor(
                          context.visualTheme,
                          color,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
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
  return AppTooltip(
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
  bool independentColumns = false,
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
    return FocusTraversalGroup(
      policy: OrderedTraversalPolicy(),
      child: CustomScrollView(
        key: PageStorageKey(keyName),
        slivers: [
          SliverToBoxAdapter(child: header),
          SliverPadding(
            padding: EdgeInsets.fromLTRB(sidePadding, 1, sidePadding, 20),
            sliver: independentColumns && gridColumns > 0
                ? SliverCrossAxisGroup(
                    slivers: [
                      for (var column = 0; column < gridColumns; column++) ...[
                        if (column > 0)
                          const SliverConstrainedCrossAxis(
                            maxExtent: 14,
                            sliver: SliverToBoxAdapter(
                              child: SizedBox.shrink(),
                            ),
                          ),
                        SliverCrossAxisExpanded(
                          flex: 1,
                          sliver: SliverList.builder(
                            itemCount: ((count - column) / columns).ceil(),
                            itemBuilder: (context, row) {
                              final index = row * columns + column;
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 14),
                                child: Semantics(
                                  sortKey: OrdinalSortKey(index.toDouble()),
                                  child: FocusTraversalOrder(
                                    order: NumericFocusOrder(index.toDouble()),
                                    child: builder(index),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ],
                    ],
                  )
                : SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, row) => Padding(
                        padding: const EdgeInsets.only(bottom: 14),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            for (
                              var column = 0;
                              column < gridColumns;
                              column++
                            ) ...[
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
                                          child: builder(
                                            row * columns + column,
                                          ),
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
      ),
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
      if (widget.numeric)
        _OpportunityNumberInput(
          label: widget.label,
          controller: text,
          focusNode: focus,
          onChanged: _changed,
          inputFormatters: [
            FilteringTextInputFormatter.allow(
              RegExp(widget.integer ? r'[0-9]' : r'[0-9.,]'),
            ),
          ],
        )
      else
        OpportunityTextField(
          controller: text,
          focusNode: focus,
          hintText: !focus.hasFocus ? widget.label : null,
          semanticLabel: widget.label,
          flat: true,
          prefixIcon: widget.prefix,
          onChanged: _changed,
          keyboardType: TextInputType.text,
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
                            ? Text(title, style: ItemDetailStyle.title(spec))
                            : OpportunityCopyName(
                                name: copyTitleName,
                                displayLabel: title,
                                style: ItemDetailStyle.title(spec),
                              )),
                  ),
                  OpportunityButton.icon(
                    icon: const Icon(Icons.close, size: 20),
                    semanticLabel: 'Close',
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const SizedBox(height: ItemDetailStyle.sectionGap),
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
  Recipe? rootRecipe,
  bool rareOutput = false,
}) async {
  final pages = ValueNotifier<List<_IngredientRecipe>>([]);
  final edits = ValueNotifier<int>(0);
  final rootPage = _IngredientRecipe(
    initial.recipeName,
    bestUse?.recipe ?? rootRecipe ?? controller.recipes[initial.recipeName]!,
    root: true,
    rare: rareOutput,
    bestUse: bestUse,
  );
  if (bestUse != null || rootRecipe != null) {
    rootPage.variantId = initial.selectedVariantId;
  }
  if (bestUse != null) {
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
        selectedVariantId: rootPage.formulaChosen
            ? rootPage.variantId
            : rootPage.variantId ?? quote.selectedVariantId,
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
                  edits: edits,
                  allowInventory: bestUse == null,
                  compact: bestUse != null,
                ),
              ),
            );
          },
        ),
      ),
      scrollBody: false,
      maxWidth: bestUse == null ? 1280 : 1000,
      onBack: goBack,
      titleBuilder: (context) =>
          ValueListenableBuilder<List<_IngredientRecipe>>(
            valueListenable: pages,
            builder: (context, history, _) => AnimatedBuilder(
              animation: edits,
              builder: (context, _) {
                final page = history.lastOrNull ?? rootPage;
                final spec = context.visualTheme;
                final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
                final title = Row(
                  children: [
                    if (history.isNotEmpty) ...[
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
                        name: page.itemName,
                        stableId: 'opportunity-title:${page.itemName}',
                        resolvePlannerTarget: () =>
                            _ingredientPlannerTarget(controller, page),
                        child: Row(
                          children: [
                            _itemIcon(
                              controller,
                              page.itemName,
                              48,
                              mode: _recipeMode(page.recipe),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: OpportunityCopyName(
                                name: page.itemName,
                                style: ItemDetailStyle.title(spec),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                );
                final controls = Wrap(
                  key: ValueKey('recipe-detail-inputs:${page.itemName}'),
                  spacing: 10,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.start,
                  children: [
                    _OpportunityCraftAmount(
                      value: page.crafts ?? 1,
                      onChanged: (value) {
                        page.crafts = value;
                        page.allocations.clear();
                        edits.value++;
                      },
                    ),
                    if (!page.rare)
                      _OpportunityCustomSalePrice(
                        value: page.customSalePrice,
                        onChanged: (value) {
                          page.customSalePrice = value;
                          edits.value++;
                        },
                      ),
                  ],
                );
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    LayoutBuilder(
                      builder: (context, constraints) {
                        if (constraints.maxWidth >= 800 * scale) {
                          return Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(child: title),
                              const SizedBox(width: 20),
                              controls,
                            ],
                          );
                        }
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            title,
                            const SizedBox(height: 12),
                            Align(
                              alignment: Alignment.centerRight,
                              child: controls,
                            ),
                          ],
                        );
                      },
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
          ),
    );
  } finally {
    closed = true;
    controller.removeListener(queueInspectionUpdate);
    controller.setInspectedRecipe(null);
    pages.dispose();
    edits.dispose();
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
  bool allowInventory = true,
  bool compact = false,
  OpportunityBestUseQuote? bestUse,
}) {
  final spec = context.visualTheme;
  final revenue = _craftRevenue(controller, quote);
  final comparison = bestUse == null
      ? null
      : calculateOpportunityBestUseComparison(
          quote: quote,
          itemName: bestUse.itemName,
          selectedItemId: bestUse.selectedItemId,
          marketTax: controller.appController.marketTax.value,
          now: controller.clock(),
          maxMarketAge: controller.cachedMarketMaxAge,
        );
  final selectedMarketId = normalizeNumericMarketId(
    bestUse?.selectedItemId ?? '',
  );
  bool selectedMaterial(OpportunityIngredientQuote ingredient) =>
      bestUse != null &&
      (bestUse.selectedItemId == null
          ? ingredient.name.trim().toLowerCase() ==
                bestUse.itemName.trim().toLowerCase()
          : selectedMarketId != null &&
                normalizeNumericMarketId(ingredient.itemId ?? '') ==
                    selectedMarketId);
  final ingredients = Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 12,
        runSpacing: 6,
        children: [
          Text(
            'Ingredients',
            style: spec.typography.body.copyWith(
              fontWeight: FontWeight.w700,
              fontSize: 18,
            ),
          ),
          if (allowInventory)
            _InventoryMenuChoice(
              key: const ValueKey('detail-use-inventory'),
              label: 'Use inventory',
              selected: controller.preferences.useInventory,
              onPressed: () =>
                  controller.change((p) => p.useInventory = !p.useInventory),
            ),
        ],
      ),
      const SizedBox(height: 10),
      _ingredientGrid(context, [
        for (final ingredient in quote.ingredients)
          OpportunitySurface(
            role: AppSurfaceRole.row,
            padding: EdgeInsets.all(compact ? 12 : 14),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(color: spec.palette.trim.withAlpha(90)),
              ),
            ),
            child: _ingredientRecipeLink(
              controller,
              ingredient.name,
              onOpen,
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      OpportunityInventoryInput(
                        key: ValueKey(
                          'ingredient-inventory:${ingredient.name}',
                        ),
                        controller:
                            controller.appController.modes[inspection
                                    ?.sourceMode ??
                                controller.preferences.mode]!,
                        itemName: ingredient.name,
                        iconBuilder: (size) => _itemIcon(
                          controller,
                          ingredient.name,
                          size,
                          mode: inspection?.sourceMode,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Wrap(
                              spacing: 6,
                              runSpacing: 3,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                OpportunityCopyName(
                                  name: ingredient.name,
                                  style: spec.typography.body.copyWith(
                                    fontSize: compact ? 16 : 18,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                Text(
                                  '×${_quantity(ingredient.quantityPerCraft)}',
                                  key: ValueKey(
                                    'ingredient-per-craft:${ingredient.name}',
                                  ),
                                  style: spec.typography.meta,
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
                                    onPressed: () => onSubstitutes(ingredient),
                                  ),
                                ],
                              ],
                            ),
                            const SizedBox(height: 3),
                            Wrap(
                              spacing: 5,
                              runSpacing: 3,
                              children: [
                                Text(
                                  _ingredientQuantityLabel(ingredient),
                                  key: ValueKey(
                                    'ingredient-quantity:${ingredient.name}',
                                  ),
                                  style: spec.typography.meta,
                                ),
                                if (_ingredientHasMarket(ingredient))
                                  Text(
                                    '· Marketplace',
                                    style: spec.typography.meta.copyWith(
                                      color:
                                          OpportunitiesVisualSpec.informationColor(
                                            spec,
                                          ),
                                    ),
                                  ),
                              ],
                            ),
                            if (_ingredientHasMarket(ingredient)) ...[
                              SizedBox(height: compact ? 6 : 8),
                              _ingredientStockBadge(
                                context,
                                controller,
                                ingredient,
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                  if (!_ingredientIsNonMarket(ingredient) ||
                      ingredient.npcUnitPrice != null) ...[
                    Padding(
                      padding: EdgeInsets.symmetric(vertical: compact ? 8 : 12),
                      child: Divider(
                        height: 1,
                        color: spec.palette.trim.withAlpha(120),
                      ),
                    ),
                    Wrap(
                      spacing: 16,
                      runSpacing: 8,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        if (selectedMaterial(ingredient)) ...[
                          KeyedSubtree(
                            key: ValueKey(
                              'best-use-selected-input:${ingredient.name}',
                            ),
                            child: _ingredientPrice(
                              context,
                              'Raw sale',
                              _silver(
                                comparison?.rawSalePerUnit == null
                                    ? null
                                    : comparison!.rawSalePerUnit! *
                                          ingredient.quantity,
                              ),
                              silverAmount: comparison?.rawSalePerUnit == null
                                  ? null
                                  : comparison!.rawSalePerUnit! *
                                        ingredient.quantity,
                              primary: true,
                            ),
                          ),
                          _ingredientPrice(
                            context,
                            'Each after tax',
                            _silver(comparison?.rawSalePerUnit),
                            silverAmount: comparison?.rawSalePerUnit,
                          ),
                        ] else ...[
                          _ingredientPrice(
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
                            silverAmount: ingredient.costForCalculation,
                            primary: true,
                          ),
                          if (ingredient.npcUnitPrice != null)
                            _ingredientPrice(
                              context,
                              'NPC each',
                              _quantity(ingredient.npcUnitPrice!),
                              silverAmount: ingredient.npcUnitPrice,
                            )
                          else if (ingredient.buyCost != null &&
                              ingredient.purchaseQuantity > 0)
                            _ingredientPrice(
                              context,
                              'Avg. each',
                              _quantity(
                                ingredient.buyCost! /
                                    ingredient.purchaseQuantity,
                              ),
                              silverAmount:
                                  ingredient.buyCost! /
                                  ingredient.purchaseQuantity,
                            ),
                          if (ingredient.npcUnitPrice != null &&
                              _ingredientHasMarket(ingredient))
                            _ingredientPrice(
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
                              silverAmount: ingredient.marketUnitPrice,
                            ),
                        ],
                      ],
                    ),
                  ],
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
  return Column(
    key: const ValueKey('craft-reader-columns'),
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (bestUse != null && inspection != null)
        _BestUseDetailsSummary(
          controller: controller,
          inspection: inspection,
          itemName: bestUse.itemName,
          comparison: comparison,
        )
      else
        LayoutBuilder(
          builder: (context, constraints) {
            final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
            final available = constraints.maxWidth;
            return Align(
              alignment: Alignment.centerLeft,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: math.min(
                    available,
                    (quote.usesInventory ? 1230 : 900) * scale,
                  ),
                ),
                child: OpportunitySurface(
                  key: const ValueKey('craft-money-summary'),
                  role: AppSurfaceRole.panel,
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _marketDepthStatus(context, controller),
                      Wrap(
                        spacing: 28,
                        runSpacing: 18,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          SizedBox(
                            width: math.min(310 * scale, available - 32),
                            child: _craftSummary(
                              context,
                              controller,
                              quote,
                              key: ValueKey('craft-result:${quote.recipeName}'),
                              showDetails: true,
                              inspection: inspection,
                            ),
                          ),
                          SizedBox(
                            width: math.min(170 * scale, available - 32),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _mathLine(
                                  context,
                                  'Sale after tax',
                                  revenue,
                                  stacked: true,
                                ),
                                const SizedBox(height: 8),
                                _mathLine(
                                  context,
                                  'Investment',
                                  quote.totalCost,
                                  minus: true,
                                  stacked: true,
                                  estimateExplanation:
                                      _quoteEstimateExplanation(quote),
                                ),
                              ],
                            ),
                          ),
                          for (final choice in _saleChoices(
                            context,
                            controller,
                            quote,
                          ))
                            SizedBox(
                              width: math.min(250 * scale, available - 32),
                              child: choice,
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      SizedBox(height: compact ? 14 : 22),
      ingredients,
    ],
  );
}

List<Widget> _saleChoices(
  BuildContext context,
  OpportunitiesController controller,
  OpportunityQuote quote,
) {
  final spec = context.visualTheme;
  final difference = quote.profitFor(controller.craftSaleMode);
  return [
    _rawIngredientSalesSummary(context, controller, quote),
    if (quote.usesInventory) ...[
      OpportunitySurface(
        key: const ValueKey('crafting-difference'),
        role: AppSurfaceRole.card,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color:
              (difference == null || difference == 0
                      ? spec.palette.surfaceRaised
                      : difference > 0
                      ? spec.palette.success
                      : spec.palette.danger)
                  .withAlpha(18),
          border: Border.all(
            color:
                (difference == null || difference == 0
                        ? spec.palette.trim
                        : difference > 0
                        ? spec.palette.success
                        : spec.palette.danger)
                    .withAlpha(140),
          ),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Profit from crafting',
              style: spec.typography.body.copyWith(
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            OpportunitySilverAmount(
              value: difference,
              estimated: quote.hasEstimatedInputs,
              showPlus: true,
              silverSuffix: true,
              textKey: const ValueKey('crafting-difference-value'),
              style: spec.typography.body.copyWith(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: difference == null || difference == 0
                    ? spec.palette.textMuted
                    : difference > 0
                    ? spec.palette.success
                    : spec.palette.danger,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              difference == null
                  ? 'Compared to selling ingredients'
                  : difference > 0
                  ? 'More than selling ingredients'
                  : difference < 0
                  ? 'Less than selling ingredients'
                  : 'Same as selling ingredients',
              style: spec.typography.meta,
            ),
          ],
        ),
      ),
    ],
  ];
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
    ownedOnly: quote.usesInventory,
  );
  return OpportunitySurface(
    key: const ValueKey('raw-ingredient-sales'),
    role: AppSurfaceRole.layout,
    padding: EdgeInsets.zero,
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          quote.usesInventory
              ? 'Sell owned ingredients'
              : 'Raw ingredient sales',
          style: spec.typography.body.copyWith(
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 6),
        Text('After tax', style: spec.typography.meta),
        const SizedBox(height: 4),
        OpportunitySilverAmount(
          value: sales.afterTax,
          estimated: true,
          silverSuffix: true,
          textKey: const ValueKey('raw-ingredient-sales-value'),
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
      ],
    ),
  );
}

Widget _ingredientPrice(
  BuildContext context,
  String label,
  String value, {
  double? silverAmount,
  String? estimateExplanation,
  bool primary = false,
}) {
  final spec = context.visualTheme;
  final style = spec.typography.body.copyWith(
    fontSize: primary ? 16 : 13,
    fontWeight: primary ? FontWeight.w700 : FontWeight.w400,
    color: primary ? spec.palette.text : spec.palette.textMuted,
  );
  final content = Wrap(
    spacing: 5,
    crossAxisAlignment: WrapCrossAlignment.center,
    children: [
      Text(label, style: style),
      if (silverAmount != null)
        OpportunitySilverAmount(
          value: silverAmount,
          estimated: value.startsWith('≈ '),
          style: style,
        )
      else
        Text(value, style: style),
    ],
  );
  return _estimateHint(estimateExplanation, content);
}

Widget _ingredientStockBadge(
  BuildContext context,
  OpportunitiesController controller,
  OpportunityIngredientQuote ingredient,
) {
  final spec = context.visualTheme;
  final now = controller.clock();
  final stock = ingredient.market?.stockFor(now, controller.cachedMarketMaxAge);
  final (text, negative) = _marketReading(
    ingredient.market,
    now,
    controller.cachedMarketMaxAge,
  );
  final color = negative
      ? spec.palette.danger
      : stock == null
      ? spec.palette.textMuted
      : stock == 0
      ? spec.palette.danger
      : _ingredientStockShortage(controller, ingredient)
      ? spec.palette.warning
      : spec.palette.success;
  final preorders =
      ingredient.market?.bookIsFresh(now, controller.cachedMarketMaxAge) == true
      ? ingredient.market?.preorderCount
      : null;
  return _MarketStockBadge(
    text: text,
    color: color,
    textKey: ValueKey('ingredient-stock:${ingredient.name}'),
    semanticDescription: stock == null
        ? 'Current stock has not been checked.'
        : 'Stock: ${_quantity(stock)}${preorders == null ? '' : '\nPreorders: ${_quantity(preorders)}'}',
  );
}

bool _ingredientStockShortage(
  OpportunitiesController controller,
  OpportunityIngredientQuote ingredient,
) {
  if (!_ingredientHasMarket(ingredient)) return false;
  final marketNeeded = ingredient.purchaseQuantity - ingredient.npcQuantity;
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
  final needed = 'Need ${_quantity(ingredient.quantity)}';
  if (ingredient.ownedQuantity > 0) {
    return ingredient.purchaseQuantity == 0
        ? '$needed · Covered'
        : '$needed · Buy ${_quantity(ingredient.purchaseQuantity)}';
  }
  if (ingredient.npcQuantity == ingredient.quantity) return '$needed · NPC';
  if (_ingredientHasMarket(ingredient) &&
      ingredient.marketQuantity == ingredient.quantity) {
    return needed;
  }
  return '$needed'
      '${ingredient.npcQuantity > 0 ? ' · ${_quantity(ingredient.npcQuantity)} from NPC' : ''}';
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
        quote.usesInventory
            ? 'Investment covers only missing ingredients. Profit from crafting also subtracts what the owned ingredients used here would sell for after tax.'
            : 'All ingredients are priced as bought, even if you already have them.',
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
  Recipe recipe;
  final bool rare;
  final bool root;
  final OpportunityBestUseQuote? bestUse;
  String? variantId;
  bool formulaChosen = false;
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
        : Semantics(
            button: true,
            label: 'View recipe for $name',
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
    required this.edits,
    required this.allowInventory,
    this.compact = false,
    super.key,
  });
  final OpportunitiesController controller;
  final _IngredientRecipe selected;
  final ValueChanged<String> onOpen;
  final ValueNotifier<int> edits;
  final bool allowInventory;
  final bool compact;

  @override
  State<_IngredientRecipeView> createState() => _IngredientRecipeViewState();
}

class _IngredientRecipeViewState extends State<_IngredientRecipeView> {
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: Listenable.merge([widget.controller, widget.edits]),
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
      if (selected.root &&
          current == null &&
          widget.controller.liveRecipeFor(selected.recipe.name) == null) {
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
        selectedVariantId: selected.formulaChosen
            ? selected.variantId
            : selected.variantId ?? current?.selectedVariantId,
        crafts: selected.crafts ?? current?.crafts ?? 1,
        customSalePrice: selected.customSalePrice,
        useInventory:
            widget.allowInventory && widget.controller.preferences.useInventory,
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
          OpportunityRecipeControls(
            routes: widget.controller.recipeRoutesFor(selected.recipe),
            recipe: recipe,
            variantId: inspection.quote.selectedVariantId,
            onSelected: (formula) {
              if (formula.recipe.type == selected.recipe.type &&
                  formula.variantId == inspection.quote.selectedVariantId) {
                return;
              }
              setState(() {
                selected.recipe = formula.recipe;
                selected.variantId = formula.variantId;
                selected.formulaChosen = true;
                selected.choices.clear();
                selected.allocations.clear();
              });
              widget.edits.value++;
              widget.controller.setInspectedRecipe(
                selected.recipe,
                itemName: selected.itemName,
                selectedVariantId: selected.variantId,
              );
            },
          ),
          _craftCalculationBody(
            context,
            widget.controller,
            inspection.quote,
            widget.onOpen,
            inspection: inspection,
            allowInventory: widget.allowInventory,
            compact: widget.compact,
            bestUse: selected.bestUse,
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
                if (changed && mounted) {
                  widget.edits.value++;
                  setState(() {});
                }
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
              OpportunitySilverAmount(
                value: value == null ? null : (minus ? -value : value),
                estimated: estimateExplanation != null,
                silverSuffix: true,
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
            Flexible(
              child: _estimateHint(
                estimateExplanation,
                OpportunitySilverAmount(
                  value: value == null ? null : (minus ? -value : value),
                  estimated: estimateExplanation != null,
                  silverSuffix: true,
                  style: context.visualTheme.typography.body.copyWith(
                    fontSize: 18,
                    fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
              ),
            ),
          ],
        ),
);

Widget _estimateHint(String? explanation, Widget child) =>
    explanation == null ? child : Semantics(hint: explanation, child: child);

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
          _MarketStockBadge(
            text: stock == null ? '—' : _quantity(stock),
            color: stock != null && stock > 0
                ? spec.palette.success
                : spec.palette.textMuted,
            semanticDescription:
                'Listed stock: ${stock == null ? 'Not checked' : _quantity(stock)}',
          ),
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
  return AppTooltip(
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
        final hasValue = _showExchangeValue(quote);
        final hasStock =
            marketReward?.marketable == true &&
            controller.market.items['${marketReward!.id}']?.stockFor(
                  controller.clock(),
                  controller.cachedMarketMaxAge,
                ) !=
                null;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _marketDepthStatus(context, controller),
            Text(
              route.directVendorSale ? 'Sell' : 'Give',
              style: ItemDetailStyle.section(spec),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                _exchangeIcon(
                  controller,
                  quote.currency.item,
                  ItemDetailStyle.ingredientIcon,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: route.directVendorSale
                      ? Text(
                          'Sell to NPC',
                          style: ItemDetailStyle.ingredient(spec),
                        )
                      : _exchangeName(
                          controller,
                          quote.currency.item,
                          displayLabel:
                              '${quote.currency.item.name} ×${_quantity(route.inputCount)}',
                          style: ItemDetailStyle.ingredient(spec),
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
              const SizedBox(height: ItemDetailStyle.sectionGap),
              Text('Receive', style: ItemDetailStyle.section(spec)),
              const SizedBox(height: 10),
              for (final reward in route.rewards)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    children: [
                      if (reward.item case final item?)
                        _exchangeIcon(
                          controller,
                          item,
                          ItemDetailStyle.recipeIcon,
                        ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: reward.item == null
                            ? OpportunityCopyName(
                                name: reward.name,
                                displayLabel:
                                    '${reward.name} ×${_quantity(reward.quantity)}',
                                style: ItemDetailStyle.recipe(spec),
                              )
                            : _exchangeName(
                                controller,
                                reward.item!,
                                displayLabel:
                                    '${reward.name} ×${_quantity(reward.quantity)}',
                                style: ItemDetailStyle.recipe(spec),
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
                style: ItemDetailStyle.ingredient(
                  spec,
                ).copyWith(fontWeight: FontWeight.w700),
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
            if (hasValue || hasStock) ...[
              const SizedBox(height: 20),
              OpportunitySurface(
                key: const ValueKey('exchange-detail-summary'),
                role: AppSurfaceRole.card,
                padding: const EdgeInsets.all(16),
                child: _MetricColumns(
                  children: [
                    if (hasValue)
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
                    if (hasValue)
                      _metric(
                        context,
                        _exchangeUnitLabel(quote.currency),
                        _silver(display.valuePerCurrency),
                      ),
                    if (hasStock)
                      _market(
                        context,
                        controller.market.items['${marketReward.id}'],
                        controller.clock(),
                        maxAge: controller.cachedMarketMaxAge,
                      ),
                  ],
                ),
              ),
            ],
            for (final reward in route.rewards)
              if (reward.item?.marketable == true &&
                  _hasExchangePreorders(controller, reward.item!))
                Padding(
                  padding: const EdgeInsets.only(top: 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (route.rewards.length > 1) ...[
                        OpportunityCopyName(
                          name: reward.name,
                          style: ItemDetailStyle.ingredient(
                            spec,
                          ).copyWith(fontWeight: FontWeight.w700),
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
            _ExchangeReferenceDetails(controller: controller, quote: quote),
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
        ? _exchangeIcon(
            controller,
            initial.route.rewardContainer!,
            ItemDetailStyle.headerIcon,
          )
        : initial.route.rewards.length == 1 &&
              initial.route.rewards.single.item != null
        ? _exchangeIcon(
            controller,
            initial.route.rewards.single.item!,
            ItemDetailStyle.headerIcon,
          )
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
