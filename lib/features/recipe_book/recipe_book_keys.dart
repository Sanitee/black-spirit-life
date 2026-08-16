import 'package:flutter/widgets.dart';

/// Stable action-contract keys for the Recipe Book vertical slice.
abstract final class RecipeBookKeys {
  static const Key modal = ValueKey<String>('recipe-book-modal');
  static const Key previewPanel = ValueKey<String>('recipe-preview-panel');
  static const Key previewReveal = ValueKey<String>('recipe-preview-reveal');
  static const Key emptyReveal = ValueKey<String>('recipe-book-empty-reveal');
  static const Key bookDragRegion = ValueKey<String>('recipe-book-drag-region');
  static const Key previewDragRegion = ValueKey<String>(
    'recipe-preview-drag-region',
  );
  static const Key confirmationDragRegion = ValueKey<String>(
    'recipe-confirmation-drag-region',
  );
  static const Key r01Backdrop = ValueKey<String>('R01');
  static const Key r02Close = ValueKey<String>('R02');
  static const Key r03Search = ValueKey<String>('R03');
  static const Key r03ClearSearch = ValueKey<String>('R03:clear');
  static const Key r04FavoritesOnly = ValueKey<String>('R04');
  static const Key r05SearchByIngredient = ValueKey<String>('R05');
  static const Key r05RecipeNameScope = ValueKey<String>('R05:recipe-name');
  static const Key r05ScopeGroup = ValueKey<String>('R05:scope-group');
  static const Key r06Density = ValueKey<String>('R06');
  static const Key r07Groups = ValueKey<String>('R07');
  static const Key r08Previous = ValueKey<String>('R08');
  static const Key r09Next = ValueKey<String>('R09');
  static const Key r10CardScroll = ValueKey<String>('R10');
  static const Key r17SelectToDelete = ValueKey<String>('R17');
  static const Key r18CancelDelete = ValueKey<String>('R18');
  static const Key r20DeleteSelected = ValueKey<String>('R20');
  static const Key r20Confirmation = ValueKey<String>('R20:confirmation');
  static const Key r20Confirm = ValueKey<String>('R20:confirm');
  static const Key r20Cancel = ValueKey<String>('R20:cancel');
  static const Key r20Undo = ValueKey<String>('R20:undo');
  static const Key r21CheckMarket = ValueKey<String>('R21');
  static const Key r22OutOfStockOnly = ValueKey<String>('R22');
  static const Key r23StockSort = ValueKey<String>('R23');
  static const Key r23MarketSort = r23StockSort;
  static const Key r24RefreshMarket = ValueKey<String>('R24');
  static const Key r24RefreshGlyph = ValueKey<String>('R24:glyph');
  static const Key r25MarketControls = ValueKey<String>('R25');
  static const Key r26ShowHidden = ValueKey<String>('R26');
  static const Key r28ProfitableOnly = ValueKey<String>('R28');
  static const Key o01PreviewEscape = ValueKey<String>('O01');
  static const Key o02BookEscape = ValueKey<String>('O02');
  static const Key o04FocusTrap = ValueKey<String>('O04');

  static Key r06DensityChoice(int pageSize) =>
      ValueKey<String>('R06:$pageSize');

  static Key r07Group(String group) =>
      ValueKey<String>('R07:${group.isEmpty ? 'all' : group.toLowerCase()}');

  static Key r11Target(String exactName) => ValueKey<String>('R11:$exactName');

  static Key r12Favorite(String exactName) =>
      ValueKey<String>('R12:$exactName');

  static Key r13Details(String exactName) => ValueKey<String>('R13:$exactName');

  static Key usedIn(String exactName) =>
      ValueKey<String>('recipe-book-used-in:$exactName');

  static Key usedInPanel(String exactName) =>
      ValueKey<String>('recipe-book-used-in-panel:$exactName');

  static Key closeUsedIn(String exactName) =>
      ValueKey<String>('recipe-book-used-in-close:$exactName');

  static Key usedInScroll(String exactName) =>
      ValueKey<String>('recipe-book-used-in-scroll:$exactName');

  static Key usedInSearch(String exactName) =>
      ValueKey<String>('recipe-book-used-in-search:$exactName');

  static Key usedInResult(String sourceName, String mode, String outputName) =>
      ValueKey<String>(
        'recipe-book-used-in-result:$sourceName:$mode:$outputName',
      );

  static Key expandUsedInResult(
    String sourceName,
    String mode,
    String outputName,
  ) => ValueKey<String>(
    'recipe-book-used-in-expand:$sourceName:$mode:$outputName',
  );

  static Key targetUsedInResult(
    String sourceName,
    String mode,
    String outputName,
  ) => ValueKey<String>(
    'recipe-book-used-in-target:$sourceName:$mode:$outputName',
  );

  static Key r14ClosePreview(String exactName) =>
      ValueKey<String>('R14:$exactName');

  static Key r15Substitute(String parentName, String ingredientName) =>
      ValueKey<String>('R15:$parentName:$ingredientName');

  static Key r16Quality(
    String parentName,
    String ingredientName,
    String grade,
  ) => ValueKey<String>('R16:$parentName:$ingredientName:$grade');

  static Key previewQuantity(String parentName, String ingredientName) =>
      ValueKey<String>('recipe-preview-quantity:$parentName:$ingredientName');

  static Key mapLookupRegion(
    String parentName,
    int ingredientIndex,
    String selectedName,
  ) => ValueKey<String>(
    'recipe-preview-map-lookup:$parentName:$ingredientIndex:$selectedName',
  );

  static Key r19DeleteSelection(String exactName) =>
      ValueKey<String>('R19:$exactName');

  static Key r27RestoreHidden(String exactName) =>
      ValueKey<String>('R27:$exactName');

  static Key profitPill(String exactName) =>
      ValueKey<String>('recipe-book-profit:$exactName');

  static Key card(String exactName) =>
      ValueKey<String>('recipe-book-card:$exactName');

  static Key productionMethod(String exactName) =>
      ValueKey<String>('recipe-book-production-method:$exactName');

  static Key itemInfo(String exactName) =>
      ValueKey<String>('recipe-book-item-info:$exactName');

  static Key itemInfoAnchor(String exactName, String anchorId) =>
      ValueKey<String>('recipe-book-item-info-anchor:$anchorId:$exactName');

  static Key pinnedItemInfo(String exactName, String anchorId) =>
      ValueKey<String>('recipe-book-item-info-pinned:$anchorId:$exactName');

  static Key closePinnedItemInfo(String exactName, String anchorId) =>
      ValueKey<String>('recipe-book-item-info-close:$anchorId:$exactName');

  static Key itemInfoFormula(
    String outputName,
    String? variantId,
    int batchMultiplier,
  ) => ValueKey<String>(
    'recipe-book-item-info-formula:$outputName:'
    '${variantId ?? 'base'}:$batchMultiplier',
  );

  static Key itemInfoMaterial(
    String outputName,
    String? variantId,
    String materialName,
  ) => ValueKey<String>(
    'recipe-book-item-info-material:$outputName:'
    '${variantId ?? 'base'}:$materialName',
  );
}
