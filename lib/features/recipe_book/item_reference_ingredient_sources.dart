part of 'recipe_book_item_info_view.dart';

List<RecipeBookIngredientChoice> _referenceChoices(
  RecipeBookController book,
  RecipeBookFormula formula,
  CraftMode mode,
) {
  final controller = book.modeController.owner.modes[mode]!;
  final inventory = controller.state.value.inventory;
  final result = <RecipeBookIngredientChoice>[];
  for (final ingredient in formula.ingredients) {
    final qualities = _qualityChoiceRows(book, formula, ingredient, mode);
    final choices = qualities.isNotEmpty
        ? qualities.expand((row) => row).toList()
        : [
            _FormulaAlternative(
              name: ingredient.name,
              quantity: ingredient.quantity,
            ),
            ..._formulaAlternatives(ingredient, recipes: controller.recipes),
          ];
    for (var index = 0; index < choices.length; index++) {
      final choice = choices[index];
      final identity = choiceMarketIdentity(
        controller,
        choice.name,
        acrossModes: true,
      );
      final owned =
          inventory[choice.name] ??
          inventory.entries
              .where(
                (entry) =>
                    entry.key.trim().toLowerCase() ==
                    choice.name.trim().toLowerCase(),
              )
              .firstOrNull
              ?.value ??
          0;
      result.add(
        RecipeBookIngredientChoice(
          ingredient: ingredient,
          name: choice.name,
          baseName: ingredient.name,
          grade: index == 0 ? 'normal' : 'alternative',
          quantity: choice.quantity,
          owned: owned.isFinite ? math.max(0, owned) : 0,
          npc: identity.npc,
          marketable: identity.marketId != null,
          stock: null,
          preorders: null,
        ),
      );
    }
  }
  return result;
}

String _referenceChoiceLabel(RecipeBookIngredientChoice row) =>
    row.grade == 'alternative'
    ? 'or ${_displayQuantity(row.quantity)} ${row.name}'
    : '${row.name} ×${_displayQuantity(row.quantity)}';

double _referenceTableWidth(
  BuildContext context,
  RecipeBookController book,
  RecipeBookFormula formula,
  CraftMode mode,
) {
  final rows = _referenceChoices(book, formula, mode);
  if (rows.isEmpty) return 0;
  final widths = RecipeIngredientWidths.measure(context, rows: rows);
  final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
  var labelWidth = 190 * scale;
  for (final row in rows) {
    final painter = TextPainter(
      text: TextSpan(
        text: itemDisplayLabel(row.name, _referenceChoiceLabel(row)),
        style: ItemDetailStyle.ingredient(context.visualTheme),
      ),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
    )..layout();
    labelWidth = math.max(
      labelWidth,
      painter.width.ceilToDouble() + 54 * scale.clamp(1, 1.35),
    );
    painter.dispose();
  }
  return widths.minimumWidth - 190 * scale + labelWidth + 8;
}

/// The same striped, aligned table as Recipe Book cards and substitute pickers.
/// Owned is informational: it never changes the formula or selected substitute.
class _ReferenceIngredientsTable extends StatelessWidget {
  const _ReferenceIngredientsTable({
    required this.book,
    required this.formula,
    required this.mode,
    required this.marketFor,
    required this.now,
  });
  final RecipeBookController book;
  final RecipeBookFormula formula;
  final CraftMode mode;
  final OpportunityMarketItem? Function(String) marketFor;
  final DateTime now;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: book.modeController.owner.modes[mode]!.state,
    builder: (context, _) {
      final rows = _referenceChoices(book, formula, mode);
      if (rows.isEmpty) return const SizedBox.shrink();
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: RecipeIngredientTable(
          controller: book,
          minimumContentWidth: _referenceTableWidth(
            context,
            book,
            formula,
            mode,
          ),
          parent: formula.outputName,
          rows: rows,
          marketFor: marketFor,
          now: now,
          labelBuilder: (context, row, index) => Semantics(
            container: true,
            explicitChildNodes: true,
            label: '${_displayQuantity(row.quantity)} ${row.name}',
            child: Row(
              key: row.grade == 'normal'
                  ? RecipeBookKeys.itemInfoMaterial(
                      formula.outputName,
                      formula.variantId,
                      row.name,
                    )
                  : null,
              children: [
                ModeItemIcon(
                  controller: book.modeController.owner.modes[mode]!,
                  catalogRepository: book.catalogRepository,
                  name: row.name,
                  size:
                      42 *
                      (MediaQuery.textScalerOf(context).scale(14) / 14).clamp(
                        1,
                        1.35,
                      ),
                  searchAcrossModes: true,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: row.grade == 'normal'
                      ? Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Flexible(
                              child: _ReferenceItemName(
                                name: row.name,
                                style: ItemDetailStyle.ingredient(
                                  context.visualTheme,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              '×${_displayQuantity(row.quantity)}',
                              style: ItemDetailStyle.meta(context.visualTheme),
                            ),
                          ],
                        )
                      : _ReferenceItemName(
                          name: row.name,
                          label: _referenceChoiceLabel(row),
                          style: ItemDetailStyle.meta(
                            context.visualTheme,
                          ).copyWith(fontSize: 14, height: 1.3),
                        ),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}

class _ReferenceFormulaMarket extends StatelessWidget {
  const _ReferenceFormulaMarket({
    required this.book,
    required this.mode,
    required this.formula,
    required this.child,
  });
  final RecipeBookController book;
  final CraftMode mode;
  final RecipeBookFormula formula;
  final Widget child;

  @override
  Widget build(BuildContext context) => PlannerChoiceMarket(
    controller: book.modeController.owner.modes[mode]!,
    resolveAcrossModes: true,
    names: [..._referenceFormulaNames(book, formula, mode)],
    builder: (context, marketFor, now) => _ReferenceFormulaMarketData(
      marketFor: marketFor,
      now: now,
      child: child,
    ),
  );
}

class _ReferenceFormulaMarketData extends InheritedWidget {
  const _ReferenceFormulaMarketData({
    required this.marketFor,
    required this.now,
    required super.child,
  });
  final OpportunityMarketItem? Function(String) marketFor;
  final DateTime now;
  static _ReferenceFormulaMarketData of(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<_ReferenceFormulaMarketData>()!;
  @override
  bool updateShouldNotify(_ReferenceFormulaMarketData oldWidget) => true;
}
