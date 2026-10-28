part of 'opportunities_workspace.dart';

String _bestUseSilver(num? value, {bool signed = false}) {
  if (value == null || !value.isFinite) return '—';
  return '${signed && value > 0 ? '+' : ''}${formatCompactOpportunitySilver(value)}';
}

Widget _bestUseCardContent(
  BuildContext context,
  OpportunitiesController controller,
  OpportunityBestUseQuote use, {
  required bool expanded,
  required VoidCallback onToggle,
}) {
  final spec = context.visualTheme;
  final name = use.quote.recipeName;
  final quote = use.quote;
  final perItem = OpportunityPerItemQuote(quote, OpportunitySaleMode.listing);
  final sale = _bestUsePerCraft(quote.listingRevenue, quote);
  final ingredients = _bestUseIngredientsPerCraft(quote);
  final profit = _bestUsePerCraft(
    quote.profitFor(OpportunitySaleMode.listing),
    quote,
  );
  final output = quote.outputPerCraft;
  final stockBadge = _market(
    context,
    controller.outputMarketFor(name, mode: use.mode),
    controller.clock(),
    maxAge: controller.cachedMarketMaxAge,
  );
  final stock = KeyedSubtree(
    key: ValueKey('best-use-stock:$name'),
    child: stockBadge,
  );
  final title = OpportunityCopyName(
    name: name,
    style: spec.typography.section.copyWith(
      fontSize: OpportunitiesVisualSpec.cardNameFontSize,
      fontWeight: FontWeight.w700,
    ),
  );
  return KeyedSubtree(
    key: ValueKey('craft-summary:$name'),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LayoutBuilder(
          key: ValueKey('best-use-card-header:$name'),
          builder: (context, constraints) {
            final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
            // Keep long stock counts from squeezing the name into fragments.
            // The fixed room covers the mount, gaps and 40-pixel open action.
            final inlineStock =
                constraints.maxWidth - stockBadge.minimumWidth(context) - 122 >=
                150 * scale;
            return Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                OpportunityItemMount(
                  key: ValueKey('craft-artwork-rail:$name'),
                  size: 56,
                  child: _itemIcon(controller, name, 48, mode: use.mode),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: inlineStock
                      ? title
                      : Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [title, const SizedBox(height: 6), stock],
                        ),
                ),
                if (inlineStock) ...[const SizedBox(width: 10), stock],
              ],
            );
          },
        ),
        const SizedBox(height: 7),
        _BestUseOutputStrip(
          key: ValueKey('best-use-output-strip:$name'),
          controller: controller,
          use: use,
          output: output,
        ),
        const SizedBox(height: 8),
        _BestUseEquationRibbon(
          key: ValueKey('best-use-equation:$name'),
          controller: controller,
          use: use,
          sale: sale,
          ingredients: ingredients,
          profit: profit,
        ),
        const SizedBox(height: 7),
        DecoratedBox(
          decoration: BoxDecoration(
            border: Border(
              top: BorderSide(color: spec.palette.trim.withAlpha(82)),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.only(top: 7),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    'After tax · per craft',
                    style: spec.typography.meta.copyWith(fontSize: 11.5),
                  ),
                ),
                Semantics(
                  expanded: expanded,
                  child: OpportunityButton(
                    key: ValueKey('best-use-calculation:$name'),
                    compact: true,
                    semanticLabel:
                        '${expanded ? 'Hide' : 'Show'} calculation for $name',
                    onPressed: onToggle,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        const Icon(Icons.calculate_outlined, size: 15),
                        const SizedBox(width: 6),
                        const Text('Calculation'),
                        const SizedBox(width: 5),
                        Icon(
                          expanded ? Icons.expand_less : Icons.expand_more,
                          size: 17,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        if (expanded) ...<Widget>[
          const SizedBox(height: 10),
          _BestUseInlineCalculation(
            key: ValueKey('best-use-inline-calculation:$name'),
            output: output,
            salePerItem: perItem.saleAfterTax,
            sale: sale,
            ingredients: ingredients,
            profit: profit,
            estimated: use.isEstimated,
          ),
        ],
      ],
    ),
  );
}

double? _bestUsePerCraft(double? value, OpportunityQuote quote) =>
    value == null || !value.isFinite || quote.crafts <= 0
    ? null
    : value / quote.crafts;

double? _bestUseIngredientsPerCraft(OpportunityQuote quote) {
  final cost = quote.totalCost;
  final owned = quote.usesInventory ? quote.ownedIngredientSales : 0.0;
  if (cost == null || owned == null || quote.crafts <= 0) return null;
  final value = (cost + owned) / quote.crafts;
  return value.isFinite ? value : null;
}

class _BestUseOutputStrip extends StatelessWidget {
  const _BestUseOutputStrip({
    required this.controller,
    required this.use,
    required this.output,
    super.key,
  });

  final OpportunitiesController controller;
  final OpportunityBestUseQuote use;
  final double? output;

  @override
  Widget build(BuildContext context) {
    final spec = context.visualTheme;
    final name = use.quote.recipeName;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: <Color>[
            spec.palette.primary.withAlpha(34),
            spec.palette.surfaceInset.withAlpha(204),
          ],
        ),
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: spec.palette.primaryBright.withAlpha(82)),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: spec.palette.primaryBright.withAlpha(20),
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        child: Row(
          children: <Widget>[
            _itemIcon(controller, name, 25, mode: use.mode),
            const SizedBox(width: 9),
            Text(
              'Makes ${output == null || !output!.isFinite ? '—' : '~${_quantity(output!)}'} / craft',
              style: spec.typography.meta.copyWith(
                fontSize: 12,
                color: spec.palette.textMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BestUseEquationRibbon extends StatelessWidget {
  const _BestUseEquationRibbon({
    required this.controller,
    required this.use,
    required this.sale,
    required this.ingredients,
    required this.profit,
    super.key,
  });

  final OpportunitiesController controller;
  final OpportunityBestUseQuote use;
  final double? sale;
  final double? ingredients;
  final double? profit;

  @override
  Widget build(BuildContext context) {
    final spec = context.visualTheme;
    final name = use.quote.recipeName;
    final cells = <Widget>[
      _BestUseEquationCell(
        key: ValueKey('best-use-sale:$name'),
        label: 'Sale',
        value: _bestUseSilver(sale),
        art: _itemIcon(controller, name, 38, mode: use.mode),
      ),
      _BestUseEquationCell(
        key: ValueKey('best-use-ingredients:$name'),
        label: 'Ingredients',
        value: _bestUseSilver(ingredients),
        art: _BestUseIngredientArt(controller: controller, use: use),
      ),
      _BestUseEquationCell(
        key: ValueKey('best-use-profit:$name'),
        label: 'Profit',
        value: _bestUseSilver(profit, signed: true),
        valueColor: profit == null || profit == 0
            ? spec.palette.textMuted
            : OpportunitiesVisualSpec.readableValueColor(
                spec,
                profit! > 0 ? spec.palette.success : spec.palette.danger,
              ),
        art: ModeItemIcon(
          controller: controller.modeController,
          catalogRepository: controller.catalog,
          name: 'Silver',
          size: 38,
          showFrame: false,
        ),
      ),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
        final stacked = constraints.maxWidth < 330 * scale;
        return DecoratedBox(
          decoration: BoxDecoration(
            color: spec.palette.surfaceInset.withAlpha(150),
            borderRadius: BorderRadius.circular(7),
            border: Border.all(
              color: spec.palette.primaryBright.withAlpha(112),
            ),
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: Colors.black.withAlpha(76),
                offset: const Offset(0, 3),
                blurRadius: 5,
              ),
            ],
          ),
          child: stacked
              ? Column(
                  children: <Widget>[
                    cells[0],
                    _BestUseEquationOperator('−', horizontal: true),
                    cells[1],
                    _BestUseEquationOperator('=', horizontal: true),
                    cells[2],
                  ],
                )
              : Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: <Widget>[
                    Expanded(child: cells[0]),
                    const _BestUseEquationOperator('−'),
                    Expanded(child: cells[1]),
                    const _BestUseEquationOperator('='),
                    Expanded(child: cells[2]),
                  ],
                ),
        );
      },
    );
  }
}

class _BestUseEquationCell extends StatelessWidget {
  const _BestUseEquationCell({
    required this.label,
    required this.value,
    required this.art,
    this.valueColor,
    super.key,
  });

  final String label;
  final String value;
  final Widget art;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    final spec = context.visualTheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(7, 8, 7, 9),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Container(
            width: 48,
            height: 38,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: const Alignment(-.7, -.9),
                radius: 1.3,
                colors: <Color>[
                  spec.palette.primary.withAlpha(32),
                  spec.palette.surfaceInset,
                ],
              ),
              borderRadius: BorderRadius.circular(5),
              border: Border.all(
                color: spec.palette.primaryBright.withAlpha(86),
              ),
              boxShadow: <BoxShadow>[
                BoxShadow(
                  color: Colors.black.withAlpha(112),
                  blurRadius: 4,
                  offset: const Offset(0, 1),
                  blurStyle: BlurStyle.inner,
                ),
              ],
            ),
            child: art,
          ),
          const SizedBox(height: 5),
          Text(
            label,
            textAlign: TextAlign.center,
            style: spec.typography.meta.copyWith(fontSize: 11.5),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.fade,
            softWrap: false,
            textAlign: TextAlign.center,
            style: spec.typography.body.copyWith(
              color: valueColor ?? spec.palette.text,
              fontSize: 18.5,
              fontWeight: FontWeight.w700,
              letterSpacing: -.2,
            ),
          ),
        ],
      ),
    );
  }
}

class _BestUseEquationOperator extends StatelessWidget {
  const _BestUseEquationOperator(this.value, {this.horizontal = false});

  final String value;
  final bool horizontal;

  @override
  Widget build(BuildContext context) {
    final spec = context.visualTheme;
    final badge = Container(
      width: 20,
      height: 20,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: spec.palette.surface,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: spec.palette.primaryBright.withAlpha(96)),
      ),
      child: Text(
        value,
        style: spec.typography.meta.copyWith(
          color: spec.palette.primaryBright,
          fontSize: 13,
          height: 1,
        ),
      ),
    );
    if (horizontal) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Center(child: badge),
      );
    }
    return SizedBox(width: 20, child: Center(child: badge));
  }
}

class _BestUseIngredientArt extends StatelessWidget {
  const _BestUseIngredientArt({required this.controller, required this.use});

  final OpportunitiesController controller;
  final OpportunityBestUseQuote use;

  @override
  Widget build(BuildContext context) {
    final ingredients = use.quote.ingredients.take(4).toList(growable: false);
    return SizedBox(
      width: 46,
      child: Wrap(
        spacing: 1,
        runSpacing: 1,
        alignment: WrapAlignment.center,
        children: <Widget>[
          for (final ingredient in ingredients)
            _itemIcon(controller, ingredient.name, 22, mode: use.mode),
        ],
      ),
    );
  }
}

class _BestUseInlineCalculation extends StatelessWidget {
  const _BestUseInlineCalculation({
    required this.output,
    required this.salePerItem,
    required this.sale,
    required this.ingredients,
    required this.profit,
    required this.estimated,
    super.key,
  });

  final double? output;
  final double? salePerItem;
  final double? sale;
  final double? ingredients;
  final double? profit;
  final bool estimated;

  @override
  Widget build(BuildContext context) {
    final spec = context.visualTheme;
    final outputText = output == null || !output!.isFinite
        ? '—'
        : '~${_quantity(output!)} / craft';
    final multiplication = output == null || salePerItem == null
        ? 'Sale after tax'
        : '${_bestUseSilver(salePerItem)} × ${_quantity(output!)}';
    return DecoratedBox(
      decoration: BoxDecoration(
        color: spec.palette.surfaceInset.withAlpha(184),
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: spec.palette.trim.withAlpha(100)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Column(
          children: <Widget>[
            _BestUseCalculationRow('Average output', outputText),
            _BestUseCalculationRow(multiplication, _bestUseSilver(sale)),
            _BestUseCalculationRow(
              'Ingredients',
              ingredients == null ? '—' : '−${_bestUseSilver(ingredients)}',
            ),
            Divider(color: spec.palette.trim.withAlpha(78), height: 12),
            _BestUseCalculationRow(
              'Profit per craft',
              _bestUseSilver(profit, signed: true),
              prominent: true,
              estimated: estimated,
            ),
          ],
        ),
      ),
    );
  }
}

class _BestUseCalculationRow extends StatelessWidget {
  const _BestUseCalculationRow(
    this.label,
    this.value, {
    this.prominent = false,
    this.estimated = false,
  });

  final String label;
  final String value;
  final bool prominent;
  final bool estimated;

  @override
  Widget build(BuildContext context) {
    final spec = context.visualTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: <Widget>[
          Expanded(child: Text(label, style: spec.typography.meta)),
          const SizedBox(width: 12),
          Text(
            estimated && value != '—' ? '~$value' : value,
            style: spec.typography.body.copyWith(
              fontSize: prominent ? 14 : 12.5,
              fontWeight: prominent ? FontWeight.w700 : FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _BestUsePane extends StatelessWidget {
  const _BestUsePane({required this.controller, required this.showSortControl});

  final OpportunitiesController controller;
  final bool showSortControl;

  @override
  Widget build(BuildContext context) {
    if (controller.preferences.section != 'best-use') {
      return const SizedBox.shrink();
    }
    final spec = context.visualTheme;
    final p = controller.preferences;
    final rows = controller.visibleBestUseQuotes;
    return _cardList(
      context,
      count: rows.length,
      keyName: 'best-use-opportunities',
      minimumCardWidth: 380,
      maximumCardWidth: 640,
      maximumColumns: 3,
      header: Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _BestUseToolbar(
              controller: controller,
              showSortControl: showSortControl,
            ),
            const SizedBox(height: 8),
            if (p.bestUseItem.isNotEmpty)
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 16,
                runSpacing: 8,
                children: [
                  Text(
                    '${rows.length} ${rows.length == 1 ? 'recipe' : 'recipes'}'
                    '${p.demandOnly && controller.bestUseDemandPendingCount > 0 ? ' · ${controller.bestUseDemandPendingCount} demand unchecked' : ''}',
                    style: spec.typography.meta,
                  ),
                  Text(
                    'Compared with selling 1 ${p.bestUseItem} · after tax',
                    key: const ValueKey('best-use-basis'),
                    style: spec.typography.meta,
                  ),
                ],
              ),
            if (rows.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 28),
                child: controller.calculatingBestUse
                    ? const Center(child: CircularProgressIndicator())
                    : _empty(
                        context,
                        p.bestUseItem.isEmpty ? 'Choose an item' : 'No matches',
                        p.bestUseItem.isEmpty
                            ? 'Find its best direct crafting uses.'
                            : p.demandOnly &&
                                  controller.bestUseDemandPendingCount > 0
                            ? 'Demand has not been checked for all recipes.'
                            : 'Change the item or filters.',
                      ),
              ),
          ],
        ),
      ),
      builder: (index) => _CraftCard(
        controller: controller,
        quote: rows[index].quote,
        bestUse: rows[index],
      ),
    );
  }
}

class _BestUseToolbar extends StatelessWidget {
  const _BestUseToolbar({
    required this.controller,
    required this.showSortControl,
  });

  final OpportunitiesController controller;
  final bool showSortControl;

  @override
  Widget build(BuildContext context) {
    final spec = context.visualTheme;
    final p = controller.preferences;
    final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
    return LayoutBuilder(
      builder: (context, constraints) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 16,
            runSpacing: 12,
            children: [
              SizedBox(
                width: math.min(480 * scale, constraints.maxWidth),
                child: Row(
                  children: [
                    Text('Best use for', style: spec.typography.button),
                    const SizedBox(width: 12),
                    Expanded(
                      child: LayoutBuilder(
                        builder: (context, fieldConstraints) =>
                            PlannerTargetChooser(
                              controller: controller.modeController,
                              allowEmptySelection: true,
                              target: PlannerCommandTarget(
                                value: p.bestUseItem,
                                names: controller.bestUseItems,
                                onSelected: (name) {
                                  if (name.trim().isEmpty) {
                                    controller.selectBestUseItem('');
                                    return true;
                                  }
                                  final selected = controller.bestUseItems
                                      .where(
                                        (item) =>
                                            item.toLowerCase() ==
                                            name.trim().toLowerCase(),
                                      )
                                      .firstOrNull;
                                  if (selected == null) return false;
                                  controller.selectBestUseItem(selected);
                                  return true;
                                },
                              ),
                              actionKey: const ValueKey('best-use-item'),
                              semanticLabel: 'Best use for item',
                              hintText: 'Find an item',
                              emptyText: 'No matching items',
                              controlHeight: math.max(40, 24 * scale + 16),
                              popupWidth: fieldConstraints.maxWidth,
                              popupMaxHeight:
                                  (MediaQuery.sizeOf(context).height - 400)
                                      .clamp(120, 420)
                                      .toDouble(),
                              fieldBuilder:
                                  (
                                    context,
                                    text,
                                    focus,
                                    onChanged,
                                    onTap,
                                    onSubmitted,
                                    onKeyEvent,
                                    onClear,
                                  ) => OpportunityTextField(
                                    flat: true,
                                    controller: text,
                                    focusNode: focus,
                                    semanticLabel: 'Best use for item',
                                    hintText: 'Find an item',
                                    textStyle: spec.typography.button,
                                    onChanged: onChanged,
                                    onTap: onTap,
                                    onSubmitted: onSubmitted,
                                    onKeyEvent: onKeyEvent,
                                    suffixIcon:
                                        ValueListenableBuilder<
                                          TextEditingValue
                                        >(
                                          valueListenable: text,
                                          builder: (context, value, _) => Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              if (value.text.isNotEmpty ||
                                                  p.bestUseItem.isNotEmpty)
                                                OpportunityButton.icon(
                                                  key: const ValueKey(
                                                    'best-use-clear',
                                                  ),
                                                  icon: const Icon(
                                                    Icons.close,
                                                    size: 18,
                                                  ),
                                                  semanticLabel:
                                                      'Clear best use item',
                                                  onPressed: onClear,
                                                ),
                                              const SizedBox(
                                                width: 34,
                                                child: Icon(
                                                  Icons.expand_more,
                                                  size: 20,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                  ),
                              optionBuilder:
                                  (
                                    context,
                                    name,
                                    selected,
                                    onSelected,
                                  ) => OpportunityButton(
                                    selected: selected,
                                    role: AppButtonRole.infoChip,
                                    minimumSize: const Size.fromHeight(48),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 8,
                                    ),
                                    semanticLabel: 'Select $name',
                                    onPressed: onSelected,
                                    child: Row(
                                      children: [
                                        ModeItemIcon(
                                          catalogRepository: controller.catalog,
                                          controller: controller.modeController,
                                          name: name,
                                          size: 36,
                                          searchAcrossModes: true,
                                          fit: BoxFit.contain,
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Text(
                                            name,
                                            style: spec.typography.body
                                                .copyWith(
                                                  fontSize: 16,
                                                  fontWeight: FontWeight.w600,
                                                ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                              itemIconBuilder: (context, name) => ModeItemIcon(
                                catalogRepository: controller.catalog,
                                controller: controller.modeController,
                                name: name,
                                size: 36,
                                searchAcrossModes: true,
                                fit: BoxFit.contain,
                              ),
                            ),
                      ),
                    ),
                  ],
                ),
              ),
              if (showSortControl) _CraftSortControl(controller: controller),
            ],
          ),
          const SizedBox(height: 12),
          DecoratedBox(
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(color: spec.palette.trim.withAlpha(70)),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 16,
                runSpacing: 12,
                children: [
                  Text(
                    'Cooking · Alchemy · Processing',
                    style: spec.typography.meta,
                  ),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _CraftFilterPill(
                        controlKey: const ValueKey('best-use-out-of-stock'),
                        label: 'Out of stock',
                        selected: p.demandOnly,
                        onSelected: (value) =>
                            controller.change((p) => p.demandOnly = value),
                      ),
                      _CraftFilterPill(
                        controlKey: const ValueKey(
                          'best-use-ingredients-available',
                        ),
                        label: 'Ingredients available',
                        selected: p.readyOnly,
                        onSelected: (value) =>
                            controller.change((p) => p.readyOnly = value),
                      ),
                      _CraftFilterPill(
                        controlKey: const ValueKey('best-use-profitable'),
                        label: 'Profitable',
                        selected: p.profitableOnly,
                        onSelected: (value) =>
                            controller.change((p) => p.profitableOnly = value),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
