part of 'recipe_book_item_info_view.dart';

// Use the same quality conversions and whole-item rounding as the planner.
// Processing only accepts its explicitly recorded alternatives, never a
// residence-Cooking/Alchemy quality inference.
List<List<_FormulaAlternative>> _qualityChoiceRows(
  RecipeBookController book,
  RecipeBookFormula formula,
  Ingredient ingredient,
  CraftMode fallbackMode,
) {
  if (formula.type.toLowerCase() == 'processing') return const [];
  final mode = formula.mode ?? fallbackMode;
  final recipes = book.modeController.owner.modes[mode]!.recipes;
  final rows = <List<_FormulaAlternative>>[];
  final bases = [
    _FormulaAlternative(name: ingredient.name, quantity: ingredient.quantity),
    ..._formulaAlternatives(ingredient, recipes: recipes),
  ];
  final seen = <String>{};
  var hasQuality = false;
  for (final base in bases) {
    if (!seen.add(base.name.toLowerCase())) continue;
    final row = <_FormulaAlternative>[base];
    for (final quality in ingredientQualityAlternatives(
      rules: book.modeController.owner.plannerRules,
      ingredientName: base.name,
    )) {
      final id = book.catalogRepository.bundledMarketId(quality.name);
      // Do not manufacture a grade that has no actual reference identity.
      if (id == null || isTemporarilyArchivedItem(quality.name, itemId: id)) {
        continue;
      }
      if (!seen.add(quality.name.toLowerCase())) continue;
      final explicit = bases
          .where((b) => b.name.toLowerCase() == quality.name.toLowerCase())
          .firstOrNull;
      row.add(
        explicit ??
            _FormulaAlternative(
              name: quality.name,
              quantity: quality.requiredQuantityFor(base.quantity),
            ),
      );
      hasQuality = true;
    }
    rows.add(row);
  }
  return hasQuality ? rows : const [];
}

List<String> _referenceFormulaNames(
  RecipeBookController book,
  RecipeBookFormula formula,
  CraftMode mode,
) => <String>{
  for (final ingredient in formula.ingredients) ...[
    ingredient.name,
    for (final choice in _formulaAlternatives(
      ingredient,
      recipes: book.modeController.owner.modes[formula.mode ?? mode]!.recipes,
    ))
      choice.name,
    for (final row in _qualityChoiceRows(book, formula, ingredient, mode))
      for (final choice in row) choice.name,
  ],
}.toList();

String _qualityLabel(_FormulaAlternative choice, bool first) => first
    ? '${choice.name} ×${_displayQuantity(choice.quantity)}'
    : 'or ${_displayQuantity(choice.quantity)} ${choice.name}';

List<double> _qualityColumnWidths(
  BuildContext context,
  List<List<_FormulaAlternative>> rows,
) {
  final count = rows.map((r) => r.length).reduce(math.max);
  final widths = List<double>.filled(count, 0);
  final style = ItemDetailStyle.meta(context.visualTheme);
  final scale = MediaQuery.textScalerOf(context);
  double measure(String value, TextStyle textStyle) {
    final painter = TextPainter(
      text: TextSpan(text: value, style: textStyle),
      textDirection: Directionality.of(context),
      textScaler: scale,
    )..layout();
    final width = painter.width;
    painter.dispose();
    return width;
  }

  for (var r = 0; r < rows.length; r++) {
    for (var c = 0; c < rows[r].length; c++) {
      // The first label is two different text styles with an 8px gap, not a
      // single string. Measure its actual layout, including fractional widths.
      final width = r == 0 && c == 0
          ? measure(
                  rows[r][c].name,
                  ItemDetailStyle.ingredient(context.visualTheme),
                ) +
                8 +
                measure('×${_displayQuantity(rows[r][c].quantity)}', style)
          : measure(_qualityLabel(rows[r][c], false), style);
      widths[c] = math.max(
        widths[c],
        math.max(width.ceilToDouble() + 2, scale.scale(150)),
      );
    }
  }
  return widths;
}

double _qualitySeparatorWidth(BuildContext context) {
  final painter = TextPainter(
    text: TextSpan(text: '|', style: ItemDetailStyle.meta(context.visualTheme)),
    textDirection: Directionality.of(context),
    textScaler: MediaQuery.textScalerOf(context),
  )..layout();
  final width = painter.width.ceilToDouble() + 20;
  painter.dispose();
  return width;
}

class _ReferenceQualityChoices extends StatefulWidget {
  const _ReferenceQualityChoices({
    required this.book,
    required this.formula,
    required this.ingredient,
    required this.mode,
    required this.marketFor,
    required this.now,
  });
  final RecipeBookController book;
  final RecipeBookFormula formula;
  final Ingredient ingredient;
  final CraftMode mode;
  final OpportunityMarketItem? Function(String) marketFor;
  final DateTime now;
  @override
  State<_ReferenceQualityChoices> createState() =>
      _ReferenceQualityChoicesState();
}

class _ReferenceQualityChoicesState extends State<_ReferenceQualityChoices> {
  final _scroll = ScrollController();
  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final rows = _qualityChoiceRows(
      widget.book,
      widget.formula,
      widget.ingredient,
      widget.mode,
    );
    final widths = _qualityColumnWidths(context, rows);
    return Scrollbar(
      controller: _scroll,
      child: SingleChildScrollView(
        controller: _scroll,
        scrollDirection: Axis.horizontal,
        child: Padding(
          padding: const EdgeInsets.only(bottom: 5),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var r = 0; r < rows.length; r++)
                Padding(
                  padding: EdgeInsets.only(top: r == 0 ? 0 : 12),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (var c = 0; c < rows[r].length; c++) ...[
                        if (c > 0)
                          SizedBox(
                            width: _qualitySeparatorWidth(context),
                            child: Center(
                              child: Text(
                                '|',
                                style: ItemDetailStyle.meta(
                                  context.visualTheme,
                                ),
                              ),
                            ),
                          ),
                        SizedBox(
                          width: widths[c],
                          child: _referenceIngredientSourceLine(
                            book: widget.book,
                            mode: widget.mode,
                            name: rows[r][c].name,
                            market: widget.marketFor(rows[r][c].name),
                            now: widget.now,
                            label: r == 0 && c == 0
                                ? Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      _ReferenceItemName(
                                        name: rows[r][c].name,
                                        style: ItemDetailStyle.ingredient(
                                          context.visualTheme,
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        '×${_displayQuantity(rows[r][c].quantity)}',
                                        style: ItemDetailStyle.meta(
                                          context.visualTheme,
                                        ),
                                      ),
                                    ],
                                  )
                                : _ReferenceItemName(
                                    name: rows[r][c].name,
                                    label: _qualityLabel(
                                      rows[r][c],
                                      r == 0 && c == 0,
                                    ),
                                    style: r == 0 && c == 0
                                        ? ItemDetailStyle.ingredient(
                                            context.visualTheme,
                                          )
                                        : ItemDetailStyle.meta(
                                            context.visualTheme,
                                          ),
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
    );
  }
}
