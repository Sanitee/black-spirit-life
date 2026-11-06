part of 'recipe_book_item_info_view.dart';

SourceAvailabilityBadges? _referenceIngredientBadge({
  required RecipeBookController book,
  required CraftMode mode,
  required String name,
  required OpportunityMarketItem? market,
  required DateTime now,
}) {
  final identity = choiceMarketIdentity(
    book.modeController.owner.modes[mode]!,
    name,
    acrossModes: true,
  );
  if (!identity.npc && identity.marketId == null) return null;
  return SourceAvailabilityBadges(
    key: ValueKey('reference-source:$name'),
    stock: market?.stockFor(now, sharedMarketFreshness),
    preorders: market?.bookIsFresh(now, sharedMarketFreshness) == true
        ? market?.preorderCount
        : null,
    npc: identity.npc,
    showMarket: identity.marketId != null,
  );
}

Widget _referenceIngredientSourceLine({
  required RecipeBookController book,
  required CraftMode mode,
  required String name,
  required OpportunityMarketItem? market,
  required DateTime now,
  required Widget label,
  bool inline = false,
}) {
  final badge = _referenceIngredientBadge(
    book: book,
    mode: mode,
    name: name,
    market: market,
    now: now,
  );
  return badge == null
      ? label
      : inline
      ? Wrap(
          spacing: 10,
          runSpacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [label, badge],
        )
      : SourceAvailabilityBelowLabel(label: label, badge: badge);
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
