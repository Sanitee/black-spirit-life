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
              RecipeIngredientTable(
                controller: controller,
                parent: name,
                rows: availability.ingredients,
                switchBuilder: (row) => _RecipeIngredientSwitch(
                  controller: controller,
                  parent: name,
                  row: row,
                ),
                marketFor: marketFor,
                now: now,
              ),
              const SizedBox(height: 8),
              const WorkshopSectionRule(),
              const SizedBox(height: 10),
              if (availability.canCraft > 0)
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
              if (availability.missing.isNotEmpty) ...[
                const SizedBox(height: 4),
                Wrap(
                  key: ValueKey('recipe-missing:$name'),
                  spacing: 12,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      'Missing',
                      style: spec.typography.meta.copyWith(fontSize: 14),
                    ),
                    for (final entry in availability.missing.entries)
                      Semantics(
                        key: ValueKey('recipe-missing-item:$name:${entry.key}'),
                        label:
                            'Missing ${formatQuantity(entry.value)} ${itemDisplayName(entry.key)}',
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            RecipeBookItemIcon(
                              controller: controller,
                              name: entry.key,
                              size: 36,
                              anchorId: 'recipe-missing:$name:${entry.key}',
                            ),
                            const SizedBox(width: 7),
                            Text(
                              '×${formatQuantity(entry.value)}',
                              style: spec.typography.label.copyWith(
                                fontSize: 15,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
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
        'Estimated silver per craft, after tax. '
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
    preferredWidthBuilder: (context) =>
        (RecipeIngredientTable.contentWidth(
                  context,
                  rows: controller.ingredientChoices(parent, row.ingredient),
                  marketFor: controller.availabilityMarketFor,
                ) +
                32)
            .clamp(
              0,
              (MediaQuery.sizeOf(context).width - 48).clamp(0, double.infinity),
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
                child: RecipeIngredientTable(
                  minimumContentWidth: RecipeIngredientTable.contentWidth(
                    context,
                    rows: choices,
                    marketFor: marketFor,
                    now: now,
                  ),
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
