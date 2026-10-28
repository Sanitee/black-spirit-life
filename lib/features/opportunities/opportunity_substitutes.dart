part of 'opportunities_workspace.dart';

class _OpportunityCraftAmount extends StatefulWidget {
  const _OpportunityCraftAmount({required this.value, required this.onChanged});
  final int value;
  final ValueChanged<int> onChanged;

  @override
  State<_OpportunityCraftAmount> createState() =>
      _OpportunityCraftAmountState();
}

class _OpportunityCraftAmountState extends State<_OpportunityCraftAmount> {
  late final text = TextEditingController(text: '${widget.value}');
  final focus = FocusNode();
  bool invalid = false;
  @override
  void initState() {
    super.initState();
    focus.addListener(_focusChanged);
  }

  void _focusChanged() {
    if (!focus.hasFocus && invalid) {
      setState(() {
        text.text = '${widget.value}';
        invalid = false;
      });
    }
  }

  @override
  void didUpdateWidget(_OpportunityCraftAmount oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value &&
        int.tryParse(text.text) != widget.value) {
      text.text = '${widget.value}';
    }
  }

  @override
  void dispose() {
    focus.removeListener(_focusChanged);
    focus.dispose();
    text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 124 * (MediaQuery.textScalerOf(context).scale(14) / 14),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _OpportunityNumberInput(
          key: const ValueKey('opportunity-detail-crafts'),
          controller: text,
          focusNode: focus,
          label: 'Crafts',
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          onChanged: (value) {
            final count = int.tryParse(value);
            setState(
              () => invalid = count == null || count <= 0 || count > 1000000000,
            );
            if (count != null && count > 0 && count <= 1000000000) {
              widget.onChanged(count);
            }
          },
        ),
        if (invalid)
          Text(
            'Enter 1–1B',
            style: context.visualTheme.typography.meta.copyWith(
              color: context.visualTheme.palette.danger,
            ),
          ),
      ],
    ),
  );
}

Future<bool> _chooseOpportunitySubstitutes(
  BuildContext context,
  OpportunitiesController controller,
  _IngredientRecipe selected,
  OpportunityRecipeInspection inspection,
  String original,
  List<OpportunityIngredientQuote> candidates,
) async {
  var applied = false;
  await _dialog(
    context,
    'Substitutes',
    (context) => _OpportunitySubstituteChooser(
      controller: controller,
      selected: selected,
      inspection: inspection,
      original: original,
      candidates: candidates,
      onApplied: () {
        applied = true;
        Navigator.of(context).pop();
      },
    ),
    maxWidth: 740,
    scrollBody: false,
  );
  return applied;
}

class _OpportunitySubstituteChooser extends StatefulWidget {
  const _OpportunitySubstituteChooser({
    required this.controller,
    required this.selected,
    required this.inspection,
    required this.original,
    required this.candidates,
    required this.onApplied,
  });
  final OpportunitiesController controller;
  final _IngredientRecipe selected;
  final OpportunityRecipeInspection inspection;
  final String original;
  final List<OpportunityIngredientQuote> candidates;
  final VoidCallback onApplied;
  @override
  State<_OpportunitySubstituteChooser> createState() =>
      _OpportunitySubstituteChooserState();
}

class _OpportunitySubstituteChooserState
    extends State<_OpportunitySubstituteChooser> {
  late int crafts = widget.inspection.quote.crafts;
  late bool split = widget.selected.allocations.containsKey(widget.original);
  late final allocated = <String, int>{
    ...?widget.selected.allocations[widget.original],
  };
  final expandedPrices = <String>{};
  final counts = <String, TextEditingController>{};
  final invalidCounts = <String>{};
  List<(OpportunityIngredientQuote, OpportunityQuote)>? _rows;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_marketChanged);
  }

  void _marketChanged() {
    if (mounted) setState(() => _rows = null);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_marketChanged);
    for (final controller in counts.values) {
      controller.dispose();
    }
    super.dispose();
  }

  OpportunityQuote evaluate({String? choice, Map<String, int>? allocation}) {
    final selections = {...widget.selected.choices}..remove(widget.original);
    if (choice != null) selections[widget.original] = choice;
    final allocations = <String, Map<String, int>>{
      if (crafts == widget.inspection.quote.crafts)
        ...widget.selected.allocations,
    }..remove(widget.original);
    if (allocation != null) allocations[widget.original] = allocation;
    return widget.controller
        .inspectRecipe(
          recipe: widget.inspection.recipe,
          itemName: widget.selected.itemName,
          selectedVariantId: widget.inspection.quote.selectedVariantId,
          crafts: crafts,
          customSalePrice: widget.selected.customSalePrice,
          ingredientChoices: selections,
          ingredientAllocations: allocations,
          extraCostPerRun: widget.inspection.quote.extraCostPerRun,
          extraCostPerCraft: widget.inspection.quote.extraCostPerCraft,
          useInventory: widget.inspection.quote.usesInventory,
        )
        .quote;
  }

  List<(OpportunityIngredientQuote, OpportunityQuote)> get rows => _rows ??=
      [
        for (final candidate in widget.candidates)
          (candidate, evaluate(choice: candidate.name)),
      ]..sort((a, b) {
        final covered = (a.$2.marketReady ? 0 : 1).compareTo(
          b.$2.marketReady ? 0 : 1,
        );
        if (covered != 0) return covered;
        final cost = (a.$2.totalCost ?? double.infinity).compareTo(
          b.$2.totalCost ?? double.infinity,
        );
        return cost == 0 ? a.$1.name.compareTo(b.$1.name) : cost;
      });

  void apply({String? choice, Map<String, int>? allocation}) {
    final selected = widget.selected;
    if (crafts != widget.inspection.quote.crafts) selected.allocations.clear();
    selected.crafts = crafts;
    selected.variantId = widget.inspection.quote.selectedVariantId;
    selected.choices.remove(widget.original);
    selected.allocations.remove(widget.original);
    if (choice != null) selected.choices[widget.original] = choice;
    if (allocation != null) {
      selected.allocations[widget.original] = Map.of(allocation);
    }
    widget.onApplied();
  }

  void setCount(String name, int value) {
    setState(() {
      invalidCounts.remove(name);
      if (value == 0) {
        allocated.remove(name);
      } else {
        allocated[name] = value;
      }
      final field = counts[name];
      if (field != null && int.tryParse(field.text) != value) {
        field.text = '$value';
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final spec = context.visualTheme;
    final assigned = allocated.values.fold<int>(0, (sum, count) => sum + count);
    final complete =
        assigned == crafts && allocated.isNotEmpty && invalidCounts.isEmpty;
    final splitQuote = split && complete
        ? evaluate(allocation: allocated)
        : null;
    return Column(
      key: const ValueKey('opportunity-substitute-chooser'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 10,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            _OpportunityCraftAmount(
              value: crafts,
              onChanged: (value) => setState(() {
                crafts = value;
                _rows = null;
              }),
            ),
            OpportunityButton.label('Automatic', onPressed: () => apply()),
            OpportunityButton.label(
              'Split batch',
              selected: split,
              onPressed: () => setState(() => split = !split),
            ),
            if (split)
              Text(
                invalidCounts.isEmpty
                    ? '$assigned / $crafts crafts'
                    : 'Invalid amount',
                style: spec.typography.body.copyWith(
                  color: complete ? spec.palette.success : spec.palette.warning,
                ),
              ),
          ],
        ),
        if (split)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    splitQuote == null
                        ? 'Choose crafts below'
                        : 'Profit ${_estimateValue(_silver(splitQuote.profitFor(widget.controller.craftSaleMode)), splitQuote.hasEstimatedInputs)}',
                    style: spec.typography.body,
                  ),
                ),
                OpportunityButton.label(
                  'Apply split',
                  key: const ValueKey('apply-substitute-split'),
                  onPressed:
                      complete &&
                          splitQuote != null &&
                          !splitQuote.issues.contains(
                            OpportunityIssue.invalidSubstitute,
                          )
                      ? () => apply(allocation: allocated)
                      : null,
                ),
              ],
            ),
          ),
        const SizedBox(height: 12),
        Flexible(
          child: SingleChildScrollView(
            key: const ValueKey('substitute-options-scroll'),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final (candidate, quote) in rows) ...[
                  _option(context, candidate, quote),
                  const SizedBox(height: 8),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _option(
    BuildContext context,
    OpportunityIngredientQuote candidate,
    OpportunityQuote quote,
  ) {
    final spec = context.visualTheme;
    final input = quote.ingredients
        .where(
          (input) =>
              input.name == candidate.name ||
              candidate.itemId != null && input.itemId == candidate.itemId,
        )
        .firstOrNull;
    final source = input ?? candidate;
    final hasMarket = _ingredientHasMarket(source);
    final nonMarket = _ingredientIsNonMarket(source);
    final stock = input?.availableQuantity;
    final unitNeed = candidate.quantityPerCraft;
    // The final calculation aggregates shared IDs. A local fill helper cannot
    // reserve their stock independently, so overlapping inputs/aliases remain
    // manual rather than promising the same units twice.
    final independentStock =
        input != null &&
        input.originalNames.length == 1 &&
        (candidate.itemId == null ||
            widget.candidates
                    .where((option) => option.itemId == candidate.itemId)
                    .length ==
                1);
    final capacity =
        hasMarket &&
            input?.depthKnown == true &&
            stock != null &&
            independentStock
        ? (stock / unitNeed).floor()
        : null;
    final profit = quote.profitFor(widget.controller.craftSaleMode);
    final levels =
        hasMarket &&
            input?.market?.bookIsFresh(
                  widget.controller.clock(),
                  widget.controller.cachedMarketMaxAge,
                ) ==
                true
        ? ((input!.market!.asks ?? const <OpportunityMarketLevel>[])
              .where((level) => level.price > 0 && level.quantity > 0)
              .toList()
            ..sort((a, b) => a.price.compareTo(b.price)))
        : const <OpportunityMarketLevel>[];
    return OpportunitySurface(
      key: ValueKey('substitute-option:${candidate.name}'),
      role: AppSurfaceRole.row,
      padding: const EdgeInsets.all(10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              _itemIcon(widget.controller, candidate.name, 32),
              const SizedBox(width: 8),
              Expanded(
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: OpportunityCopyName(
                    name: candidate.name,
                    style: spec.typography.body.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              if (!split)
                OpportunityButton.label(
                  'Use',
                  key: ValueKey('use-substitute:${candidate.name}'),
                  onPressed: () => apply(choice: candidate.name),
                ),
            ],
          ),
          const SizedBox(height: 8),
          if (!split)
            _MetricColumns(
              children: [
                if (hasMarket)
                  _ingredientStockBadge(context, widget.controller, source)
                else if (source.npcUnitPrice != null)
                  _metric(context, 'NPC each', _quantity(source.npcUnitPrice!)),
                _metric(
                  context,
                  'Needed',
                  input == null ? '—' : _quantity(input.quantity),
                  color:
                      hasMarket &&
                          input?.depthKnown == true &&
                          input?.coversRequest != true
                      ? spec.palette.danger
                      : null,
                ),
                _metric(
                  context,
                  'Batch cost',
                  quote.totalCost == null
                      ? '—'
                      : _estimateValue(
                          _silver(quote.totalCost!),
                          quote.hasEstimatedInputs,
                        ),
                ),
                _metric(
                  context,
                  'Batch profit',
                  profit == null
                      ? '—'
                      : _estimateValue(
                          _silver(profit),
                          quote.hasEstimatedInputs,
                        ),
                  color: profit == null
                      ? null
                      : profit < 0
                      ? spec.palette.danger
                      : spec.palette.success,
                ),
              ],
            ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (split && hasMarket)
                _ingredientStockBadge(context, widget.controller, source),
              if (split && nonMarket && source.npcUnitPrice != null)
                Text(
                  'NPC each ${_quantity(source.npcUnitPrice!)}',
                  style: spec.typography.meta,
                ),
              if (split)
                SizedBox(
                  width:
                      115 * (MediaQuery.textScalerOf(context).scale(14) / 14),
                  child: _OpportunityNumberInput(
                    key: ValueKey('split-crafts:${candidate.name}'),
                    controller: counts.putIfAbsent(
                      candidate.name,
                      () => TextEditingController(
                        text: '${allocated[candidate.name] ?? 0}',
                      ),
                    ),
                    label: 'Crafts',
                    textStyle: spec.typography.body.copyWith(
                      color:
                          hasMarket &&
                              stock != null &&
                              stock <
                                  (allocated[candidate.name] ?? 0) * unitNeed
                          ? spec.palette.danger
                          : null,
                    ),
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    onChanged: (value) {
                      final count = int.tryParse(value.isEmpty ? '0' : value);
                      if (count != null && count <= 1000000000) {
                        invalidCounts.remove(candidate.name);
                        setCount(candidate.name, count);
                      } else {
                        setState(() => invalidCounts.add(candidate.name));
                      }
                    },
                  ),
                ),
              if (capacity != null && capacity > 0)
                OpportunityButton.label(
                  split ? 'Fill remaining' : 'Check $capacity crafts',
                  key: ValueKey('use-substitute-stock:${candidate.name}'),
                  role: AppButtonRole.infoChip,
                  onPressed: () {
                    if (split) {
                      final others = allocated.entries
                          .where((entry) => entry.key != candidate.name)
                          .fold<int>(0, (sum, entry) => sum + entry.value);
                      setCount(
                        candidate.name,
                        math.min(capacity, math.max(0, crafts - others)),
                      );
                    } else {
                      setState(() {
                        crafts = math.min(capacity, 1000000000);
                        _rows = null;
                      });
                    }
                  },
                ),
              if (levels.isNotEmpty)
                OpportunityButton.label(
                  'Prices',
                  role: AppButtonRole.infoChip,
                  selected: expandedPrices.contains(candidate.name),
                  onPressed: () => setState(() {
                    if (!expandedPrices.add(candidate.name)) {
                      expandedPrices.remove(candidate.name);
                    }
                  }),
                ),
            ],
          ),
          if (levels.isNotEmpty && expandedPrices.contains(candidate.name)) ...[
            const SizedBox(height: 8),
            for (final level in levels)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Wrap(
                  spacing: 16,
                  runSpacing: 4,
                  children: [
                    Text(
                      '${_quantity(level.quantity)} × ${_quantity(level.price)} silver',
                      style: spec.typography.meta,
                    ),
                    // Exact tier margin is possible for a single direct input.
                    // For several inputs, their changing depth cannot safely be
                    // replaced with an average and called per-craft profit.
                    if (quote.ingredients.length == 1 &&
                        quote.listingRevenue != null &&
                        (quote.hasCustomSalePrice ||
                            widget.controller.craftSaleMode ==
                                OpportunitySaleMode.listing) &&
                        input != null &&
                        input.npcUnitPrice == null)
                      _tierMargin(
                        context,
                        quote,
                        input.quantityPerCraft,
                        level.price,
                      ),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }

  Widget _tierMargin(
    BuildContext context,
    OpportunityQuote quote,
    double units,
    int price,
  ) {
    final margin =
        quote.listingRevenue! / quote.crafts -
        units * price -
        quote.extraCost / quote.crafts;
    return Text(
      '${_silver(margin)} / craft',
      style: context.visualTheme.typography.meta.copyWith(
        color: margin < 0
            ? context.visualTheme.palette.danger
            : context.visualTheme.palette.success,
      ),
    );
  }
}
