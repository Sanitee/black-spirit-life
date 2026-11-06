part of 'recipe_book_modal.dart';

class _RecipeCardIngredients extends StatelessWidget {
  const _RecipeCardIngredients({required this.controller, required this.name});
  final RecipeBookController controller;
  final String name;

  @override
  Widget build(BuildContext context) {
    final availability = controller.availabilityFor(name);
    if (availability.ingredients.isEmpty) return const SizedBox.shrink();
    return PlannerChoiceMarket(
      controller: controller.modeController,
      resolveAcrossModes: true,
      names: [name, ...availability.ingredients.map((row) => row.name)],
      builder: (context, marketFor, now) {
        final spec = context.visualTheme;
        final availability = controller.availabilityFor(name);
        return Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const WorkshopSectionRule(),
              const SizedBox(height: 8),
              _RecipeAvailabilityTable(
                controller: controller,
                parent: name,
                rows: availability.ingredients,
                marketFor: marketFor,
                now: now,
              ),
              const SizedBox(height: 8),
              const WorkshopSectionRule(),
              const SizedBox(height: 10),
              Wrap(
                spacing: 16,
                runSpacing: 6,
                children: [
                  Text(
                    'Can craft ${formatCompactQuantity(availability.canCraft)}',
                    key: ValueKey('recipe-can-craft:$name'),
                    style: spec.typography.label.copyWith(
                      fontSize: 16,
                      color: availability.fullyOwned
                          ? OpportunityCraftCardMaterial.forSpec(
                              spec,
                              OpportunityStockTone.available,
                            ).badgeInk
                          : spec.palette.text,
                    ),
                  ),
                  if (!availability.fullyOwned)
                    Text(
                      '${availability.ownedTypes}/${availability.totalTypes} ingredients owned',
                      style: spec.typography.meta.copyWith(fontSize: 14),
                    ),
                ],
              ),
              if (availability.missing.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  'Missing: ${availability.missing.entries.map((entry) => '${formatQuantity(entry.value)} ${itemDisplayName(entry.key)}').join(' · ')}',
                  key: ValueKey('recipe-missing:$name'),
                  style: spec.typography.meta.copyWith(
                    fontSize: 14,
                    height: 1.4,
                  ),
                ),
              ],
              const SizedBox(height: 8),
              _RecipeCraftValues(controller: controller, name: name),
            ],
          ),
        );
      },
    );
  }
}

class _RecipeCraftValues extends StatelessWidget {
  const _RecipeCraftValues({required this.controller, required this.name});
  final RecipeBookController controller;
  final String name;

  @override
  Widget build(BuildContext context) {
    final spec = context.visualTheme;
    final values = controller.craftComparisonFor(name);
    final material = OpportunityCraftCardMaterial.forSpec(
      spec,
      OpportunityStockTone.unknown,
    );
    final quote = controller.profitabilityFor(name);
    final outputUnknown =
        quote?.outputPerCraft == null || quote?.unavailableItemName == name;
    final records = [
      (
        id: 'all',
        label: 'Buy all',
        kind: 'Profit',
        value: values.buyAllProfit,
        tip:
            'Sell the expected output, minus the cost of buying every ingredient. Owned ingredients still have a cost here.',
        missing: quote?.unavailableItemName,
      ),
      (
        id: 'missing',
        label: 'Buy missing',
        kind: 'Cash return',
        value: values.buyMissingReturn,
        tip:
            'Sell the expected output, minus only the ingredients you need to buy. Does not subtract the value of ingredients you already own.',
        missing: outputUnknown ? name : values.missingBuyPrices.join(', '),
      ),
      (
        id: 'owned',
        label: 'Sell owned',
        kind: 'Sale value',
        value: values.sellOwnedProceeds,
        tip:
            'Sell the owned ingredients needed for one craft instead. Extra inventory and NPC-only ingredients are not included.',
        missing: values.missingSalePrices.join(', '),
      ),
    ];
    const basis =
        'Uses the displayed ingredients, expected yield and your market tax settings. '
        'At zero stock, uses the highest current preorder price when available; otherwise the latest market price. '
        'Estimates do not guarantee an immediate purchase or sale. Excludes byproducts, tools and time.';
    Widget label(int i) => Text(
      records[i].label,
      key: ValueKey('recipe-value-label:$name:${records[i].id}'),
      style: spec.typography.label.copyWith(
        fontSize: 14,
        color: spec.palette.text,
      ),
    );
    Widget value(int i) => Text(
      records[i].value == null ? '—' : formatCompactSilver(records[i].value!),
      key: ValueKey('recipe-value:$name:${records[i].id}'),
      style: spec.typography.label.copyWith(
        fontSize: 16,
        color: records[i].value == null
            ? spec.palette.textMuted
            : records[i].id == 'owned'
            ? spec.palette.text
            : records[i].value! >= 0
            ? material.readable(spec.palette.success)
            : material.lossInk,
      ),
    );
    Widget hint(int i) => Text(
      records[i].kind,
      style: spec.typography.meta.copyWith(fontSize: 12),
    );
    String tooltip(int i) =>
        '${records[i].tip}\n\n$basis'
        '${records[i].value == null
            ? i < 2 && !controller.cardOutputCanBeSold(name)
                  ? '\n\nNo Central Market sale price is available for this recipe result.'
                  : '\n\nPrice missing: ${(records[i].missing?.isNotEmpty ?? false) ? itemDisplayName(records[i].missing!) : 'selected ingredients'}.'
            : ''}';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Est. silver per craft · after tax',
          style: spec.typography.meta.copyWith(fontSize: 13),
        ),
        const SizedBox(height: 8),
        LayoutBuilder(
          builder: (context, constraints) {
            final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
            if (constraints.maxWidth < 510 * scale) {
              return Table(
                columnWidths: const {
                  0: FlexColumnWidth(),
                  1: IntrinsicColumnWidth(),
                },
                defaultVerticalAlignment: TableCellVerticalAlignment.middle,
                children: [
                  for (var i = 0; i < records.length; i++)
                    TableRow(
                      children: [
                        AppTooltip(
                          message: tooltip(i),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 6),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [label(i), hint(i)],
                            ),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.only(left: 16),
                          child: value(i),
                        ),
                      ],
                    ),
                ],
              );
            }
            return Table(
              defaultVerticalAlignment: TableCellVerticalAlignment.top,
              children: [
                TableRow(
                  children: [
                    for (var i = 0; i < records.length; i++)
                      AppTooltip(
                        message: tooltip(i),
                        child: Padding(
                          padding: EdgeInsets.only(
                            left: i == 0 ? 0 : 14,
                            right: i == 2 ? 0 : 14,
                          ),
                          child: label(i),
                        ),
                      ),
                  ],
                ),
                TableRow(
                  children: [
                    for (var i = 0; i < records.length; i++)
                      Padding(
                        padding: EdgeInsets.fromLTRB(
                          i == 0 ? 0 : 14,
                          5,
                          i == 2 ? 0 : 14,
                          2,
                        ),
                        child: value(i),
                      ),
                  ],
                ),
                TableRow(
                  children: [
                    for (var i = 0; i < records.length; i++)
                      Padding(
                        padding: EdgeInsets.only(left: i == 0 ? 0 : 14),
                        child: hint(i),
                      ),
                  ],
                ),
              ],
            );
          },
        ),
      ],
    );
  }
}

/// Cards and substitute pickers deliberately share this exact column layout.
class _RecipeAvailabilityTable extends StatelessWidget {
  const _RecipeAvailabilityTable({
    required this.controller,
    required this.parent,
    required this.rows,
    required this.marketFor,
    required this.now,
    this.onChoose,
    this.selectedName,
  });
  static double minimumWidth(BuildContext context) =>
      _RecipeAvailabilityWidths.measure(context).minimumWidth;
  final RecipeBookController controller;
  final String parent;
  final List<RecipeBookIngredientChoice> rows;
  final OpportunityMarketItem? Function(String) marketFor;
  final DateTime now;
  final ValueChanged<RecipeBookIngredientChoice>? onChoose;
  final String? selectedName;

  @override
  Widget build(BuildContext context) {
    final spec = context.visualTheme;
    final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
    Widget heading(String text) => Padding(
      padding: const EdgeInsets.only(bottom: 6, top: 2),
      child: Text(
        text,
        textAlign: text == 'Ingredients' ? TextAlign.left : TextAlign.center,
        style: spec.typography.meta.copyWith(
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
    Widget cell(Widget child, {bool left = false}) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Align(
        alignment: left ? Alignment.centerLeft : Alignment.center,
        child: child,
      ),
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final widths = _RecipeAvailabilityWidths.measure(
          context,
          rows: rows,
          marketFor: marketFor,
          now: now,
        );
        final width = constraints.maxWidth < widths.minimumWidth
            ? widths.minimumWidth
            : constraints.maxWidth;
        final table = SizedBox(
          width: width,
          child: Table(
            defaultVerticalAlignment: TableCellVerticalAlignment.middle,
            columnWidths: {
              0: const FlexColumnWidth(),
              1: FixedColumnWidth(widths.ingredientGap),
              2: FixedColumnWidth(widths.npc),
              3: FixedColumnWidth(10 * scale),
              4: FixedColumnWidth(widths.inventory),
              5: FixedColumnWidth(14 * scale),
              6: FixedColumnWidth(widths.market),
            },
            children: [
              TableRow(
                decoration: BoxDecoration(
                  color: spec.palette.surfaceInset.withAlpha(90),
                ),
                children: [
                  heading('Ingredients'),
                  const SizedBox.shrink(),
                  heading('NPC'),
                  const SizedBox.shrink(),
                  heading('Inventory'),
                  const SizedBox.shrink(),
                  // Preorders follow in their own optional slot. Keep the
                  // heading over the stock badges, not over unused space.
                  Align(
                    alignment: Alignment.centerLeft,
                    child: SizedBox(
                      width: widths.stock,
                      child: heading('Market'),
                    ),
                  ),
                ],
              ),
              for (var index = 0; index < rows.length; index++)
                TableRow(
                  key: ValueKey(
                    'recipe-ingredient:$parent:${rows[index].name}:$index',
                  ),
                  decoration: BoxDecoration(
                    color: selectedName == rows[index].name
                        ? spec.palette.trim.withAlpha(55)
                        : index.isEven
                        ? spec.palette.surfaceRaised.withAlpha(65)
                        : spec.palette.surfaceInset.withAlpha(30),
                    border: Border(
                      top: BorderSide(color: spec.palette.trim.withAlpha(65)),
                    ),
                  ),
                  children: [
                    cell(_label(context, rows[index], index), left: true),
                    const SizedBox.shrink(),
                    cell(
                      rows[index].npc
                          ? const MarketCountBadges(
                              density: MarketBadgeDensity.comfortable,
                              stock: null,
                              preorders: null,
                              npc: true,
                              showMarket: false,
                              singleLine: true,
                            )
                          : const SizedBox.shrink(),
                    ),
                    const SizedBox.shrink(),
                    cell(
                      InventoryCountBadge(
                        density: MarketBadgeDensity.comfortable,
                        owned: rows[index].owned,
                        showLabel: false,
                      ),
                    ),
                    const SizedBox.shrink(),
                    cell(
                      rows[index].marketable
                          ? MarketCountBadges(
                              density: MarketBadgeDensity.comfortable,
                              stock: marketFor(
                                rows[index].name,
                              )?.stockFor(now, sharedMarketFreshness),
                              preorders:
                                  marketFor(rows[index].name)?.bookIsFresh(
                                        now,
                                        sharedMarketFreshness,
                                      ) ==
                                      true
                                  ? marketFor(rows[index].name)?.preorderCount
                                  : null,
                              compactNumbers: true,
                              singleLine: true,
                              stockColumnWidth: widths.stock,
                              stockColumnAlignment: Alignment.center,
                            )
                          : const SizedBox.shrink(),
                      left: true,
                    ),
                  ],
                ),
            ],
          ),
        );
        if (width <= constraints.maxWidth) return table;
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: table,
        );
      },
    );
  }

  Widget _label(
    BuildContext context,
    RecipeBookIngredientChoice row,
    int index,
  ) {
    final spec = context.visualTheme;
    final label = Row(
      children: [
        RecipeBookItemIcon(
          controller: controller,
          name: row.name,
          size:
              42 *
              (MediaQuery.textScalerOf(context).scale(14) / 14).clamp(1, 1.35),
          anchorId:
              'availability:$parent:${onChoose == null ? 'card' : 'choice'}:$index:${row.name}',
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: itemDisplayName(row.name),
                  style: spec.typography.label.copyWith(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: spec.palette.text,
                    height: 1.3,
                  ),
                ),
                TextSpan(
                  text: '  ×${formatQuantity(row.quantity)}',
                  style: spec.typography.meta.copyWith(
                    fontSize: 14,
                    color: spec.palette.textMuted,
                  ),
                ),
              ],
            ),
          ),
        ),
        if (onChoose == null && _hasAlternatives(row))
          _RecipeIngredientSwitch(
            controller: controller,
            parent: parent,
            row: row,
          ),
      ],
    );
    if (onChoose == null) return label;
    return InkWell(
      key: ValueKey('recipe-choose:$parent:${row.name}'),
      onTap: () => onChoose!(row),
      child: label,
    );
  }

  bool _hasAlternatives(RecipeBookIngredientChoice row) =>
      controller.hasIngredientAlternatives(parent, row);
}

/// Reserve real single-line badge widths, including the active font and scale.
/// The same stock slot keeps preorder badges aligned even when stock is zero.
class _RecipeAvailabilityWidths {
  const _RecipeAvailabilityWidths(
    this.npc,
    this.inventory,
    this.stock,
    this.orders,
    this.scale,
  );
  final double npc, inventory, stock, orders, scale;
  double get ingredientGap => 32 * scale;
  double get market => stock + 7 + orders;
  double get minimumWidth =>
      190 * scale + ingredientGap + 24 * scale + npc + inventory + market;

  static _RecipeAvailabilityWidths measure(
    BuildContext context, {
    List<RecipeBookIngredientChoice> rows = const [],
    OpportunityMarketItem? Function(String)? marketFor,
    DateTime? now,
  }) {
    final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
    double headingWidth(String label) {
      final painter = TextPainter(
        text: TextSpan(
          text: label,
          style: DefaultTextStyle.of(context).style.merge(
            context.visualTheme.typography.meta.copyWith(
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        textDirection: Directionality.of(context),
        textScaler: MediaQuery.textScalerOf(context),
        maxLines: 1,
      )..layout();
      final width = painter.width;
      painter.dispose();
      return width;
    }

    var npc = const MarketCountBadges(
      density: MarketBadgeDensity.comfortable,
      stock: null,
      preorders: null,
      npc: true,
      showMarket: false,
    ).preferredWidth(context);
    var inventory = const InventoryCountBadge(
      density: MarketBadgeDensity.comfortable,
      owned: 999900,
      showLabel: false,
    ).preferredWidth(context);
    double stockWidth(int? value) => MarketCountBadges(
      density: MarketBadgeDensity.comfortable,
      stock: value,
      preorders: null,
      compactNumbers: true,
    ).preferredWidth(context);
    double orderWidth(int value) =>
        MarketCountBadges(
          density: MarketBadgeDensity.comfortable,
          stock: 0,
          preorders: value,
          compactNumbers: true,
        ).preferredWidth(context) -
        stockWidth(0) -
        7;
    var stock = stockWidth(999900);
    var orders = orderWidth(999900);
    if (headingWidth('Inventory') > inventory) {
      inventory = headingWidth('Inventory');
    }
    if (headingWidth('NPC') > npc) npc = headingWidth('NPC');
    if (headingWidth('Market') > stock) stock = headingWidth('Market');
    for (final row in rows) {
      final ownedWidth = InventoryCountBadge(
        density: MarketBadgeDensity.comfortable,
        owned: row.owned,
        showLabel: false,
      ).preferredWidth(context);
      if (ownedWidth > inventory) inventory = ownedWidth;
      final item = marketFor?.call(row.name);
      final width = stockWidth(
        item?.stockFor(now ?? DateTime.now(), sharedMarketFreshness),
      );
      if (width > stock) stock = width;
      final preorder = item?.preorderCount;
      if (preorder != null && preorder > 0) {
        final width = orderWidth(preorder);
        if (width > orders) orders = width;
      }
    }
    return _RecipeAvailabilityWidths(
      npc + 2,
      inventory + 2,
      stock + 2,
      orders + 2,
      scale,
    );
  }
}

class _RecipeIngredientSwitch extends StatelessWidget {
  const _RecipeIngredientSwitch({
    required this.controller,
    required this.parent,
    required this.row,
  });
  final RecipeBookController controller;
  final String parent;
  final RecipeBookIngredientChoice row;
  @override
  Widget build(BuildContext context) => AnchoredPopover(
    overlayId: 'recipe-choices:$parent:${row.ingredient.name}',
    preferredWidth: 860,
    preferredWidthBuilder: (context) =>
        (880 * MediaQuery.textScalerOf(context).scale(14) / 14).clamp(
          0,
          (MediaQuery.sizeOf(context).width - 48).clamp(0, 1600),
        ),
    maximumHeight: MediaQuery.sizeOf(context).height * .75,
    consumeOutsideTap: true,
    placement: AnchoredPopoverPlacement.beside,
    anchorBuilder: (context, toggle, showing) => AppTextAction(
      key: ValueKey('recipe-substitutes:$parent:${row.ingredient.name}'),
      semanticLabel:
          'Substitutes for ${row.ingredient.substituteGroup ?? row.ingredient.name}',
      tooltip: 'Substitutes',
      selected: showing,
      onPressed: toggle,
      child: const AppVectorGlyph('swap', size: 20),
    ),
    popoverBuilder: (context, close) => ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final choices = controller.ingredientChoices(parent, row.ingredient);
        final selected = controller
            .availabilityFor(parent)
            .ingredients
            .where((entry) => entry.ingredient == row.ingredient)
            .firstOrNull
            ?.name;
        return PlannerChoiceMarket(
          controller: controller.modeController,
          resolveAcrossModes: true,
          names: choices.map((choice) => choice.name).toList(),
          builder: (context, marketFor, now) => SculptedPanel(
            title: row.ingredient.substituteGroup ?? row.ingredient.name,
            onClose: close,
            body: Padding(
              padding: const EdgeInsets.all(14),
              child: SingleChildScrollView(
                child: _RecipeAvailabilityTable(
                  controller: controller,
                  parent: parent,
                  rows: choices,
                  marketFor: marketFor,
                  now: now,
                  selectedName: selected,
                  onChoose: (choice) {
                    controller.selectIngredientChoice(parent, choice);
                    close();
                  },
                ),
              ),
            ),
          ),
        );
      },
    ),
  );
}
