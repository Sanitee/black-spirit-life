part of 'recipe_book_item_info_view.dart';

/// Cards and substitute pickers deliberately share this exact column layout.
class RecipeIngredientTable extends StatelessWidget {
  const RecipeIngredientTable({
    required this.controller,
    required this.parent,
    required this.rows,
    required this.marketFor,
    required this.now,
    this.onChoose,
    this.selectedName,
    this.labelBuilder,
    this.switchBuilder,
    this.rowKeyBuilder,
    this.labelWrapper,
    this.iconMode,
    this.iconAnchorBuilder,
    this.minimumContentWidth = 0,
    this.fitBadges = false,
    super.key,
  });
  static double minimumWidth(BuildContext context) =>
      RecipeIngredientWidths.measure(context).minimumWidth;

  /// Fit the actual labels and controls, without stretching to a preset width.
  /// Hosts cap this at the viewport; the table scrolls if it cannot fit there.
  static double contentWidth(
    BuildContext context, {
    required List<RecipeBookIngredientChoice> rows,
    OpportunityMarketItem? Function(String)? marketFor,
    DateTime? now,
    bool Function(RecipeBookIngredientChoice)? hasSwitch,
    double Function(RecipeBookIngredientChoice)? switchWidth,
    bool fitBadges = false,
  }) {
    final spec = context.visualTheme;
    final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
    final widths = RecipeIngredientWidths.measure(
      context,
      rows: rows,
      marketFor: marketFor,
      now: now,
      fitBadges: fitBadges,
    );
    var labelWidth = 190 * scale;
    for (final row in rows) {
      final painter = TextPainter(
        text: TextSpan(
          style: DefaultTextStyle.of(context).style,
          children: [
            TextSpan(
              text: itemDisplayName(row.name),
              style: spec.typography.label.copyWith(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                height: 1.3,
              ),
            ),
            TextSpan(
              text: '  ×${formatQuantity(row.quantity)}',
              style: spec.typography.meta.copyWith(fontSize: 14),
            ),
          ],
        ),
        textDirection: Directionality.of(context),
        textScaler: MediaQuery.textScalerOf(context),
        maxLines: 1,
      )..layout();
      labelWidth = math.max(
        labelWidth,
        42 * scale.clamp(1, 1.35) +
            10 +
            painter.width.ceilToDouble() +
            (hasSwitch?.call(row) == true
                ? (switchWidth?.call(row) ?? 44)
                : 0) +
            4,
      );
      painter.dispose();
    }
    return widths.minimumWidth - 190 * scale + labelWidth;
  }

  final RecipeBookController controller;
  final String parent;
  final List<RecipeBookIngredientChoice> rows;
  final OpportunityMarketItem? Function(String) marketFor;
  final DateTime now;
  final ValueChanged<RecipeBookIngredientChoice>? onChoose;
  final String? selectedName;
  final Widget Function(BuildContext, RecipeBookIngredientChoice, int)?
  labelBuilder;
  final Widget Function(RecipeBookIngredientChoice)? switchBuilder;
  final LocalKey Function(int)? rowKeyBuilder;
  final Widget Function(RecipeBookIngredientChoice, int, Widget)? labelWrapper;
  final double minimumContentWidth;
  final bool fitBadges;
  final CraftMode? iconMode;
  final String Function(RecipeBookIngredientChoice, int)? iconAnchorBuilder;

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
        final widths = RecipeIngredientWidths.measure(
          context,
          rows: rows,
          marketFor: marketFor,
          now: now,
          fitBadges: fitBadges,
        );
        final width = math.max(
          constraints.maxWidth,
          math.max(widths.minimumWidth, minimumContentWidth),
        );
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
                  key:
                      rowKeyBuilder?.call(index) ??
                      ValueKey(
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
                    cell(
                      _wrappedLabel(context, rows[index], index),
                      left: true,
                    ),
                    const SizedBox.shrink(),
                    cell(
                      rows[index].npc
                          ? MarketCountBadges(
                              key: ValueKey(
                                '${rows[index].marketable ? 'reference-npc' : 'reference-source'}:${rows[index].name}',
                              ),
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
                              key: ValueKey(
                                'reference-source:${rows[index].name}',
                              ),
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

  Widget _wrappedLabel(
    BuildContext context,
    RecipeBookIngredientChoice row,
    int index,
  ) {
    final label =
        labelBuilder?.call(context, row, index) ?? _label(context, row, index);
    return labelWrapper?.call(row, index, label) ?? label;
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
          mode: iconMode,
          name: row.name,
          size:
              42 *
              (MediaQuery.textScalerOf(context).scale(14) / 14).clamp(1, 1.35),
          anchorId:
              iconAnchorBuilder?.call(row, index) ??
              'availability:$parent:${onChoose == null ? 'card' : 'choice'}:$index:${row.name}',
        ),
        const SizedBox(width: 10),
        Flexible(
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
        if (onChoose == null && _hasAlternatives(row) && switchBuilder != null)
          switchBuilder!(row),
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
class RecipeIngredientWidths {
  const RecipeIngredientWidths(
    this.npc,
    this.inventory,
    this.stock,
    this.orders,
    this.scale,
  );
  final double npc, inventory, stock, orders, scale;
  double get ingredientGap => 32 * scale;
  double get market => stock + (orders > 0 ? 7 + orders : 0);
  double get minimumWidth =>
      190 * scale + ingredientGap + 24 * scale + npc + inventory + market;

  static RecipeIngredientWidths measure(
    BuildContext context, {
    List<RecipeBookIngredientChoice> rows = const [],
    OpportunityMarketItem? Function(String)? marketFor,
    DateTime? now,
    bool fitBadges = false,
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
    var inventory = InventoryCountBadge(
      density: MarketBadgeDensity.comfortable,
      owned: fitBadges ? 0 : 999900,
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
    var stock = stockWidth(fitBadges ? null : 999900);
    var orders = fitBadges ? 0.0 : orderWidth(999900);
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
      final preorder =
          !fitBadges ||
              item?.bookIsFresh(now ?? DateTime.now(), sharedMarketFreshness) ==
                  true
          ? item?.preorderCount
          : null;
      if (preorder != null && preorder > 0) {
        final width = orderWidth(preorder);
        if (width > orders) orders = width;
      }
    }
    return RecipeIngredientWidths(
      npc + 2,
      inventory + 2,
      stock + 2,
      orders > 0 ? orders + 2 : 0,
      scale,
    );
  }
}
