part of 'recipe_book_item_info_view.dart';

List<RecipeBookIngredientChoice> _referenceChoices(
  RecipeBookController book,
  RecipeBookFormula formula,
  CraftMode mode, {
  bool includeAlternatives = false,
}) {
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
          vendorHint: npcVendorHint(controller, choice.name),
          marketable: identity.marketId != null,
          stock: null,
          preorders: null,
        ),
      );
    }
  }
  if (includeAlternatives) return result;
  return [
    for (final ingredient in formula.ingredients)
      result
              .where(
                (row) =>
                    identical(row.ingredient, ingredient) &&
                    row.name.toLowerCase() ==
                        book
                            .referenceIngredientName(formula, ingredient)
                            ?.toLowerCase(),
              )
              .firstOrNull ??
          result.firstWhere((row) => identical(row.ingredient, ingredient)),
  ];
}

double _referenceTableWidth(
  BuildContext context,
  RecipeBookController book,
  RecipeBookFormula formula,
  CraftMode mode, {
  OpportunityMarketItem? Function(String)? marketFor,
  DateTime? now,
}) {
  final rows = _referenceChoices(book, formula, mode);
  final alternatives = _referenceChoices(
    book,
    formula,
    mode,
    includeAlternatives: true,
  );
  return RecipeIngredientTable.contentWidth(
    context,
    rows: rows,
    marketFor: marketFor,
    now: now,
    fitBadges: true,
    switchWidth: (row) => RecipeIngredientChoiceButton.widthFor(
      context,
      book,
      alternatives
          .where((other) => identical(other.ingredient, row.ingredient))
          .toList(),
    ),
    hasSwitch: (row) =>
        alternatives
            .where((other) => identical(other.ingredient, row.ingredient))
            .length >
        1,
  );
}

/// One ingredient per row. Alternatives use the same chooser as Recipe Book cards.
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
    listenable: book,
    builder: (context, _) {
      final rows = _referenceChoices(book, formula, mode);
      if (rows.isEmpty) return const SizedBox.shrink();
      List<RecipeBookIngredientChoice> choices(Ingredient ingredient) =>
          _referenceChoices(
            book,
            formula,
            mode,
            includeAlternatives: true,
          ).where((row) => identical(row.ingredient, ingredient)).toList();
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: RecipeIngredientTable(
          controller: book,
          fitBadges: true,
          minimumContentWidth: _referenceTableWidth(
            context,
            book,
            formula,
            mode,
            marketFor: marketFor,
            now: now,
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
              key: RecipeBookKeys.itemInfoMaterial(
                formula.outputName,
                formula.variantId,
                row.name,
              ),
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
                Flexible(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(
                        child: ItemNameWithNpc(
                          npc: row.displaysNpc,
                          vendorHint: row.vendorHint,
                          markerKey: ValueKey(
                            '${row.marketable ? 'reference-npc' : 'reference-source'}:${row.name}',
                          ),
                          child: _ReferenceItemName(
                            name: row.name,
                            style: ItemDetailStyle.ingredient(
                              context.visualTheme,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '×${_displayQuantity(row.quantity)}',
                        style: ItemDetailStyle.meta(context.visualTheme),
                      ),
                    ],
                  ),
                ),
                if (choices(row.ingredient).length > 1)
                  RecipeIngredientChoiceButton(
                    controller: book,
                    parent: formula.outputName,
                    mode: mode,
                    ingredient: row.ingredient,
                    identity:
                        'reference-choices:${formula.mode?.key}:${formula.outputName}:${formula.variantId}:${formula.routeId}:${formula.batchMultiplier}:$index',
                    choices: () => choices(row.ingredient),
                    selectedName: () =>
                        book.referenceIngredientName(formula, row.ingredient) ??
                        row.name,
                    onChoose: (choice) =>
                        book.selectReferenceIngredient(formula, choice),
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
