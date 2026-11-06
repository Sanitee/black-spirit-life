import '../../data/opportunities/exchange_catalog.dart';
import '../../data/opportunities/exchange_item_details.dart';
import '../../domain/models/catalog_models.dart';
import '../../domain/opportunities/exchange_models.dart';
import 'recipe_book_item_info.dart';
import 'reviewed_reference_facts.dart';

/// Share the already-reviewed exchange facts; do not invent another catalog or
/// silently drop limits, requirements, box identity or legacy status.
RecipeBookItemInfo withExchangeReferenceInformation(
  RecipeBookItemInfo base,
  ExchangeItem item,
) {
  if (base.isTemporarilyArchived ||
      base.title.trim().toLowerCase() != item.name.trim().toLowerCase()) {
    return base;
  }
  final details = exchangeItemDetails[item.id];
  final currency = exchangeCatalog
      .where((c) => c.item.id == item.id)
      .firstOrNull;
  final sources = <String>{...base.acquisitionNotes};
  if (currency != null && !currency.legacy) {
    sources.add(currency.sourceActivity);
  }
  for (final source in exchangeCatalog.where((c) => !c.legacy)) {
    for (final route in source.routes) {
      if (route.directVendorSale) continue;
      final rewards = route.rewards.where(
        (reward) => reward.item?.id == item.id,
      );
      final container = route.rewardContainer;
      final isContainer = container?.id == item.id;
      if (!isContainer && rewards.isEmpty) continue;
      // Explicitly say when the exchanged box must be opened. A bundle's
      // contents are not separate NPC choices or additional free rewards.
      final count = isContainer ? 1 : rewards.first.quantity;
      final extra = <String>[
        if (!route.limit.isRepeatable) route.limit.label,
        ...route.requirements,
        ...route.notes,
      ];
      sources.add(
        'Exchange · ${route.inputCount} ${source.item.name} → '
        '$count ${item.name}${container != null && !isContainer ? ' (from ${container.name})' : ''}'
        ' · ${route.location}${extra.isEmpty ? '' : ' · ${extra.join('; ')}'}',
      );
    }
  }
  if (details != null) sources.addAll(details.howToObtain);
  final valks = RegExp(r'^Advice of Valks \(\+(\d+)\)$').firstMatch(item.name);
  final title = item.name.startsWith('[Title] ');
  return withReviewedReferenceFacts(
    base.copyWith(
      kind: currency != null
          ? 'Exchange item'
          : details?.kind ??
                (valks != null
                    ? 'Enhancement'
                    : title
                    ? 'Title'
                    : base.kind),
      summary:
          currency?.sourceActivity ??
          details?.summary ??
          (valks != null
              ? 'Grants a +${valks[1]} Enhancement Chance.'
              : title
              ? 'Unlocks the ${item.name.substring(8)} title.'
              : base.summary),
      acquisitionNotes: sources.toList(),
      effects: base.effects.isEmpty
          ? details?.effects ?? base.effects
          : base.effects,
      uses: {
        ...base.uses,
        ...?details?.uses,
        if (currency != null)
          for (final location
              in currency.routes
                  .where((r) => !r.directVendorSale)
                  .map((r) => r.location)
                  .toSet())
            'Exchange at $location.',
      }.toList(),
      notes: {
        ...base.notes,
        ...?details?.notes,
        ...?currency?.notes,
        if (valks != null) 'Use when your current Enhancement Chance is 0.',
      }.toList(),
      craftUses: [
        ...base.craftUses,
        if (details != null)
          for (final recipe in details.recipes)
            if (!base.craftUses.any((use) => use.output == recipe.output))
              RecipeBookCraftUse(
                output: recipe.output,
                formulas: [
                  RecipeBookFormula(
                    outputName: recipe.output,
                    type: 'Crafted',
                    method: recipe.method,
                    baseOutput: 1,
                    ingredients: [
                      for (final input in recipe.ingredients.entries)
                        Ingredient(
                          name: input.key,
                          quantity: input.value,
                          options: const [],
                          substituteGroup: null,
                          substituteRatios: const {},
                        ),
                    ],
                  ),
                ],
              ),
      ],
    ),
    itemId: item.id.toString(),
  );
}
