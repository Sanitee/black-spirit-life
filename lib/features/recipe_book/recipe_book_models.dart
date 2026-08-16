import '../../domain/market/recipe_profitability.dart';
import '../../domain/models/catalog_models.dart';
import '../../domain/models/craft_mode.dart';
import '../planner/planner_contracts.dart';

enum RecipeBookDensity {
  fourByThree(columns: 4, rows: 3, label: '4 x 3'),
  fiveByFour(columns: 5, rows: 4, label: '5 x 4'),
  sixByFive(columns: 6, rows: 5, label: '6 x 5');

  const RecipeBookDensity({
    required this.columns,
    required this.rows,
    required this.label,
  });

  final int columns;
  final int rows;
  final String label;
  int get pageSize => columns * rows;
}

enum ProcessingRecipeGroup {
  all('', 'All'),
  enhancement('enhancement', 'Enhancement'),
  buffs('buffs', 'Buffs'),
  crystals('crystals', 'Crystals'),
  lightstones('lightstones', 'Lightstones'),
  alchemy('alchemy', 'Alchemy'),
  cooking('cooking', 'Cooking'),
  metals('metals', 'Metals'),
  wood('wood', 'Wood'),
  cloth('cloth', 'Cloth'),
  other('other', 'Other');

  const ProcessingRecipeGroup(this.key, this.label);

  final String key;
  final String label;
}

enum RecipeBookMarketSort {
  none('Sort ↕'),
  stockLowToHigh('Stock ↑'),
  stockHighToLow('Stock ↓'),
  profitLowToHigh('Profit/ea ↑'),
  profitHighToLow('Profit/ea ↓');

  const RecipeBookMarketSort(this.label);

  final String label;

  bool get sortsProfit =>
      this == RecipeBookMarketSort.profitLowToHigh ||
      this == RecipeBookMarketSort.profitHighToLow;
}

final class RecipeBookGroupCount {
  const RecipeBookGroupCount({required this.group, required this.count});

  final ProcessingRecipeGroup group;
  final int count;
}

final class RecipeBookEntry {
  const RecipeBookEntry({
    required this.name,
    required this.recipe,
    required this.favorite,
    required this.selectedForDeletion,
    required this.hidden,
    required this.processingGroup,
    required this.usedInCount,
    this.marketStock,
    this.profitability,
  });

  final String name;
  final Recipe recipe;
  final bool favorite;
  final bool selectedForDeletion;
  final bool hidden;
  final ProcessingRecipeGroup processingGroup;
  final int usedInCount;
  final double? marketStock;
  final RecipeProfitabilityQuote? profitability;
}

final class RecipeBookSnapshot {
  const RecipeBookSnapshot({
    required this.entries,
    required this.filteredCount,
    required this.poolCount,
    required this.page,
    required this.pageCount,
    required this.groupCounts,
  });

  final List<RecipeBookEntry> entries;
  final int filteredCount;
  final int poolCount;
  final int page;
  final int pageCount;
  final List<RecipeBookGroupCount> groupCounts;

  bool get hasPreviousPage => page > 0;
  bool get hasNextPage => page + 1 < pageCount;
}

final class RecipeBookActivation {
  const RecipeBookActivation({
    required this.exactName,
    required this.context,
    required this.mode,
    this.variantId,
  });

  final String exactName;
  final RecipeBookCallingContext context;
  final CraftMode mode;
  final String? variantId;
}

final class RecipeBookDeletionRequest {
  const RecipeBookDeletionRequest({
    required this.exactNames,
    required this.expectedCount,
  });

  final List<String> exactNames;
  final int expectedCount;
}

typedef UndoRecipeBookDeletion = Future<void> Function();

final class RecipeBookDeletionOutcome {
  const RecipeBookDeletionOutcome({
    required this.hiddenNames,
    required this.undo,
    required this.message,
  });

  final List<String> hiddenNames;
  final UndoRecipeBookDeletion undo;
  final String message;

  int get hiddenCount => hiddenNames.length;
}

typedef DeleteRecipeBookSelection =
    Future<RecipeBookDeletionOutcome> Function(
      RecipeBookDeletionRequest request,
    );
