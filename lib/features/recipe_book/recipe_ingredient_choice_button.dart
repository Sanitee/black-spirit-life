part of 'recipe_book_item_info_view.dart';

/// Shared substitute control for cards, details and item references.
class RecipeIngredientChoiceButton extends StatelessWidget {
  const RecipeIngredientChoiceButton({
    required this.controller,
    required this.parent,
    required this.ingredient,
    required this.choices,
    required this.selectedName,
    required this.onChoose,
    this.mode,
    this.identity,
    super.key,
  });

  final RecipeBookController controller;
  final String parent;
  final Ingredient ingredient;
  final List<RecipeBookIngredientChoice> Function() choices;
  final String? Function() selectedName;
  final ValueChanged<RecipeBookIngredientChoice> onChoose;
  final CraftMode? mode;
  final String? identity;

  static ({RecipeBookIngredientChoice green, RecipeBookIngredientChoice blue})?
  elixirGrades(
    RecipeBookController controller,
    List<RecipeBookIngredientChoice> rows,
  ) {
    if (rows.length != 2) return null;
    final catalog = controller.catalogRepository;
    final green = rows
        .where((r) => catalog.itemIconGrade(r.name) == 1)
        .firstOrNull;
    final blue = rows
        .where((r) => catalog.itemIconGrade(r.name) == 2)
        .firstOrNull;
    if (green == null ||
        blue == null ||
        green.quantity <= 0 ||
        blue.quantity <= 0 ||
        catalog
                .recipe(CraftMode.alchemy, green.name)
                ?.type
                .trim()
                .toLowerCase() !=
            'alchemy' ||
        (green.quantity - blue.quantity * 3).abs() > .000001) {
      return null;
    }
    return (green: green, blue: blue);
  }

  static double widthFor(
    BuildContext context,
    RecipeBookController controller,
    List<RecipeBookIngredientChoice> rows,
  ) => elixirGrades(controller, rows) == null
      ? 44
      : 8 + QualityGradeButton.sizeFor(context) * 2 + 4;

  @override
  Widget build(BuildContext context) {
    final rows = choices();
    final grades = elixirGrades(controller, rows);
    if (grades != null) {
      final selected = selectedName() ?? rows.first.name;
      return Padding(
        padding: const EdgeInsets.only(left: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final entry in [
              (grades.green, 'normal', 'Green'),
              (grades.blue, 'blue', 'Blue'),
            ]) ...[
              if (entry.$2 == 'blue') const SizedBox(width: 4),
              QualityGradeButton(
                key: ValueKey(
                  'recipe-grade:$parent:${ingredient.name}:${entry.$2}',
                ),
                label: entry.$3,
                grade: entry.$2,
                normalIsBlueFamily: true,
                selected: selected.toLowerCase() == entry.$1.name.toLowerCase(),
                onPressed: () => onChoose(entry.$1),
              ),
            ],
          ],
        ),
      );
    }
    return AnchoredPopover(
      overlayId: identity ?? 'recipe-choices:$parent:${ingredient.name}',
      preferredWidthBuilder: (context) =>
          (RecipeIngredientTable.contentWidth(
                    context,
                    rows: choices(),
                    marketFor: controller.availabilityMarketFor,
                  ) +
                  32)
              .clamp(
                0,
                (MediaQuery.sizeOf(context).width - 48).clamp(
                  0,
                  double.infinity,
                ),
              ),
      maximumHeight: MediaQuery.sizeOf(context).height * .75,
      consumeOutsideTap: true,
      placement: AnchoredPopoverPlacement.beside,
      onOpenChanged: (open) {
        if (!open) return;
        // A child overlay covers the artwork preview's mouse region. Keep that
        // already-open rich reference alive while its chooser is being used.
        final preview = context.findAncestorStateOfType<TooltipState>();
        if (preview == null) return;
        WidgetsBinding.instance.endOfFrame.then((_) {
          if (context.mounted && preview.mounted) {
            preview.ensureTooltipVisible();
          }
        });
      },
      anchorBuilder: (context, toggle, showing) => AppTextAction(
        key: ValueKey('recipe-substitutes:$parent:${ingredient.name}'),
        semanticLabel:
            'Substitutes for ${ingredient.substituteGroup ?? ingredient.name}',
        selected: showing,
        onPressed: toggle,
        child: const AppVectorGlyph('swap', size: 20),
      ),
      popoverBuilder: (context, close) => ListenableBuilder(
        listenable: controller,
        builder: (context, _) {
          final rows = choices();
          return PlannerChoiceMarket(
            controller: controller
                .modeController
                .owner
                .modes[mode ?? controller.modeController.mode]!,
            resolveAcrossModes: true,
            names: rows.map((row) => row.name).toList(),
            builder: (context, marketFor, now) => MouseRegion(
              onEnter: (_) => context
                  .findAncestorStateOfType<TooltipState>()
                  ?.ensureTooltipVisible(),
              onHover: (_) => context
                  .findAncestorStateOfType<TooltipState>()
                  ?.ensureTooltipVisible(),
              child: FocusScope(
                autofocus: true,
                child: SculptedPanel(
                  title: ingredient.substituteGroup ?? ingredient.name,
                  onClose: close,
                  body: Padding(
                    padding: const EdgeInsets.all(14),
                    child: SingleChildScrollView(
                      child: RecipeIngredientTable(
                        minimumContentWidth: RecipeIngredientTable.contentWidth(
                          context,
                          rows: rows,
                          marketFor: marketFor,
                          now: now,
                        ),
                        controller: controller,
                        parent: parent,
                        iconMode: mode,
                        rows: rows,
                        marketFor: marketFor,
                        now: now,
                        selectedName: selectedName(),
                        onChoose: (choice) {
                          onChoose(choice);
                          close();
                        },
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
