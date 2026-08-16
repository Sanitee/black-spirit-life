import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import 'package:flutter/services.dart';

import '../../data/catalog/catalog_repository.dart';
import '../../domain/formatting/planner_formatters.dart';
import '../../domain/market/recipe_profitability.dart';
import '../../domain/models/catalog_models.dart';
import '../../shared/overlays/anchored_popover.dart';
import '../../shared/overlays/draggable_overlay_surface.dart';
import '../../visual/visual.dart';
import '../planner/planner_contracts.dart';
import '../planner/planner_map_quick_lookup.dart';
import '../shared/recipe_variant_selector.dart';
import 'recipe_book_controller.dart';
import 'recipe_book_item_info.dart';
import 'recipe_book_item_info_view.dart';
import 'recipe_book_keys.dart';
import 'recipe_book_models.dart';
import 'recipe_book_usage.dart';
import 'recipe_book_used_in_panel.dart';

Future<RecipeBookActivation?> showRecipeBookModal({
  required BuildContext context,
  required RecipeBookRequest request,
  required CatalogRepository catalogRepository,
  CheckPlannerPrices? checkPrices,
  DeleteRecipeBookSelection? deleteSelection,
  PlannerExternalActions? externalActions,
}) {
  final reduceMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
  final controller = RecipeBookController(
    modeController: request.controller,
    catalogRepository: catalogRepository,
    callingContext: request.context,
    allowedTargets: request.allowedTargets,
    checkPrices: checkPrices,
    deleteSelection: deleteSelection,
  );
  final result = showGeneralDialog<RecipeBookActivation>(
    context: context,
    barrierDismissible: false,
    barrierColor: Colors.transparent,
    barrierLabel: 'Recipe Book',
    transitionDuration: reduceMotion
        ? Duration.zero
        : const Duration(milliseconds: 150),
    transitionBuilder: (context, animation, secondaryAnimation, child) =>
        reduceMotion
        ? child
        : FadeTransition(
            opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
            child: child,
          ),
    pageBuilder: (dialogContext, animation, secondaryAnimation) =>
        RecipeBookModal(
          controller: controller,
          externalActions: externalActions,
          onClose: () => Navigator.of(dialogContext).pop(),
          onActivated: (activation) =>
              Navigator.of(dialogContext).pop(activation),
        ),
  );
  return result.whenComplete(controller.dispose);
}

class RecipeBookModal extends StatefulWidget {
  const RecipeBookModal({
    required this.controller,
    required this.onClose,
    required this.onActivated,
    this.externalActions,
    super.key,
  });

  final RecipeBookController controller;
  final VoidCallback onClose;
  final ValueChanged<RecipeBookActivation> onActivated;
  final PlannerExternalActions? externalActions;

  @override
  State<RecipeBookModal> createState() => _RecipeBookModalState();
}

class _RecipeBookModalState extends State<RecipeBookModal> {
  late final TextEditingController _search = TextEditingController(
    text: widget.controller.search,
  );
  late final ScrollController _scroll = ScrollController(
    initialScrollOffset: widget.controller.scrollOffset,
  )..addListener(_recordScroll);
  final FocusScopeNode _focusScope = FocusScopeNode(
    debugLabel: 'Recipe Book modal focus trap',
    traversalEdgeBehavior: TraversalEdgeBehavior.closedLoop,
  );
  final FocusNode _searchFocus = FocusNode(debugLabel: 'Recipe Book search');
  final FocusNode _previewCloseFocus = FocusNode(
    debugLabel: 'Recipe preview close',
  );
  int _scrollResetRevision = 0;
  String? _lastPreviewName;
  Offset? _previewAnchorGlobal;

  @override
  void initState() {
    super.initState();
    _scrollResetRevision = widget.controller.scrollResetRevision;
    _lastPreviewName = widget.controller.previewName;
    widget.controller.addListener(_controllerChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _searchFocus.requestFocus();
    });
  }

  @override
  void didUpdateWidget(RecipeBookModal oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller == widget.controller) return;
    oldWidget.controller.removeListener(_controllerChanged);
    widget.controller.addListener(_controllerChanged);
    _search.text = widget.controller.search;
    _scrollResetRevision = widget.controller.scrollResetRevision;
    _lastPreviewName = widget.controller.previewName;
  }

  @override
  void dispose() {
    widget.controller.removeListener(_controllerChanged);
    _scroll
      ..removeListener(_recordScroll)
      ..dispose();
    _search.dispose();
    _searchFocus.dispose();
    _previewCloseFocus.dispose();
    _focusScope.dispose();
    super.dispose();
  }

  void _recordScroll() {
    if (_scroll.hasClients) {
      widget.controller.recordScrollOffset(_scroll.offset);
    }
  }

  void _controllerChanged() {
    if (!mounted) return;
    final reset = widget.controller.scrollResetRevision;
    if (reset != _scrollResetRevision) {
      _scrollResetRevision = reset;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _scroll.hasClients) _scroll.jumpTo(0);
      });
    }
    final preview = widget.controller.previewName;
    if (preview != _lastPreviewName) {
      _lastPreviewName = preview;
      if (preview == null) _previewAnchorGlobal = null;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (preview == null) {
          _searchFocus.requestFocus();
        } else {
          _previewCloseFocus.requestFocus();
        }
      });
    }
    setState(() {});
  }

  void _closeBook() {
    widget.controller.closePreview();
    widget.onClose();
  }

  void _handleEscape(BuildContext overlayContext) {
    final overlays = AppOverlayCoordinatorScope.maybeOf(overlayContext);
    if (overlays?.dismissTop() ?? false) return;
    if (widget.controller.deleteConfirmationVisible) {
      widget.controller.cancelDeleteConfirmation();
      return;
    }
    if (widget.controller.previewName != null) {
      widget.controller.closePreview();
      return;
    }
    _closeBook();
  }

  void _activate(String name) {
    final activation = widget.controller.activate(name);
    if (activation != null) widget.onActivated(activation);
  }

  bool _activateUsedIn(RecipeBookUseEntry entry, String? variantId) {
    final activation = widget.controller.activateUsedIn(
      entry,
      variantId: variantId,
    );
    if (activation == null) return false;
    widget.onActivated(activation);
    return true;
  }

  void _openPreview(String name, Offset anchorGlobal) {
    _previewAnchorGlobal = anchorGlobal;
    widget.controller.openPreview(name);
  }

  @override
  Widget build(BuildContext context) {
    final spec = context.visualTheme;
    final snapshot = widget.controller.snapshot;
    return Material(
      type: MaterialType.transparency,
      child: AppOverlayCoordinatorHost(
        child: Builder(
          builder: (overlayContext) => CallbackShortcuts(
            bindings: <ShortcutActivator, VoidCallback>{
              const SingleActivator(LogicalKeyboardKey.escape): () =>
                  _handleEscape(overlayContext),
            },
            child: FocusScope.withExternalFocusNode(
              key: RecipeBookKeys.o04FocusTrap,
              focusScopeNode: _focusScope,
              child: Semantics(
                key: RecipeBookKeys.o02BookEscape,
                container: true,
                explicitChildNodes: true,
                scopesRoute: true,
                namesRoute: true,
                label:
                    '${widget.controller.modeController.mode.label} Recipe Book',
                child: Stack(
                  children: <Widget>[
                    Positioned.fill(
                      child: GestureDetector(
                        key: RecipeBookKeys.r01Backdrop,
                        behavior: HitTestBehavior.opaque,
                        onTap: _closeBook,
                        child: ColoredBox(color: spec.materials.modalScrim),
                      ),
                    ),
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final compactBonus =
                            widget.controller.callingContext ==
                                RecipeBookCallingContext.bonus &&
                            snapshot.poolCount <= 6;
                        final width = compactBonus
                            ? switch (widget.controller.density) {
                                RecipeBookDensity.fourByThree => 980.0,
                                _ => 900.0,
                              }.clamp(760.0, constraints.maxWidth - 92)
                            : (constraints.maxWidth - 92).clamp(760.0, 1220.0);
                        final height = compactBonus
                            ? switch (widget.controller.density) {
                                RecipeBookDensity.sixByFive => 386.0,
                                RecipeBookDensity.fiveByFour => 414.0,
                                RecipeBookDensity.fourByThree => 464.0,
                              }.clamp(300.0, constraints.maxHeight - 40)
                            : (constraints.maxHeight - 86).clamp(560.0, 820.0);
                        return DraggableOverlaySurface(
                          overlayId: 'recipe-book',
                          child: SizedBox(
                            key: RecipeBookKeys.modal,
                            width: width,
                            height: height,
                            child: GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTap: _focusScope.requestFocus,
                              child: AppSurface(
                                role: AppSurfaceRole.modal,
                                padding: const EdgeInsets.all(16),
                                clipBehavior: Clip.antiAlias,
                                semanticLabel: 'Recipe Book dialog',
                                child: _RecipeBookBody(
                                  controller: widget.controller,
                                  snapshot: snapshot,
                                  searchController: _search,
                                  searchFocus: _searchFocus,
                                  scrollController: _scroll,
                                  onClose: _closeBook,
                                  onActivate: _activate,
                                  onActivateUsedIn: _activateUsedIn,
                                  onPreview: _openPreview,
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                    Positioned.fill(
                      child: AppRevealTransition(
                        key: RecipeBookKeys.previewReveal,
                        visible: widget.controller.previewName != null,
                        child: widget.controller.previewName == null
                            ? null
                            : KeyedSubtree(
                                key: RecipeBookKeys.o01PreviewEscape,
                                child: _RecipePreviewOverlay(
                                  controller: widget.controller,
                                  externalActions: widget.externalActions,
                                  recipeName: widget.controller.previewName!,
                                  anchorGlobal: _previewAnchorGlobal,
                                  closeFocus: _previewCloseFocus,
                                  onActivate: _activate,
                                ),
                              ),
                      ),
                    ),
                    if (widget.controller.deleteConfirmationVisible)
                      Positioned.fill(
                        child: _DeleteConfirmationOverlay(
                          controller: widget.controller,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RecipeBookBody extends StatelessWidget {
  const _RecipeBookBody({
    required this.controller,
    required this.snapshot,
    required this.searchController,
    required this.searchFocus,
    required this.scrollController,
    required this.onClose,
    required this.onActivate,
    required this.onActivateUsedIn,
    required this.onPreview,
  });

  final RecipeBookController controller;
  final RecipeBookSnapshot snapshot;
  final TextEditingController searchController;
  final FocusNode searchFocus;
  final ScrollController scrollController;
  final VoidCallback onClose;
  final ValueChanged<String> onActivate;
  final bool Function(RecipeBookUseEntry, String?) onActivateUsedIn;
  final void Function(String name, Offset anchorGlobal) onPreview;

  @override
  Widget build(BuildContext context) {
    final spec = context.visualTheme;
    final ledger = spec.isIlluminatedLedger;
    final denseLayout = spec.usesDenseSplitLayout;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: DraggableOverlayDragRegion(
                key: RecipeBookKeys.bookDragRegion,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    ledger ? 'RECIPE BOOK' : 'Recipe Book',
                    style: spec.typography.display.copyWith(
                      fontSize: ledger ? 25 : 28,
                      fontWeight: ledger ? FontWeight.w600 : FontWeight.w700,
                      letterSpacing: ledger ? 1.3 : 0,
                    ),
                  ),
                ),
              ),
            ),
            AppButton(
              key: RecipeBookKeys.r02Close,
              role: ledger ? AppButtonRole.primary : AppButtonRole.optionPill,
              minimumSize: Size.square(denseLayout ? 34 : 30),
              padding: EdgeInsets.zero,
              semanticLabel: 'Close Recipe Book',
              tooltip: 'Close Recipe Book',
              onPressed: onClose,
              child: const AppVectorGlyph('close', size: 12),
            ),
          ],
        ),
        if (ledger) ...<Widget>[
          const SizedBox(height: 2),
          SizedBox(
            height: 7,
            child: Center(
              child: Container(
                height: 1,
                color: spec.palette.trim.withAlpha(142),
              ),
            ),
          ),
          const SizedBox(height: 10),
        ] else
          const SizedBox(height: 10),
        _RecipeBookToolbar(
          controller: controller,
          snapshot: snapshot,
          searchController: searchController,
          searchFocus: searchFocus,
        ),
        const SizedBox(height: 8),
        _RecipeBookMeta(controller: controller, snapshot: snapshot),
        const SizedBox(height: 8),
        Expanded(
          child: Stack(
            fit: StackFit.expand,
            children: <Widget>[
              if (snapshot.entries.isNotEmpty)
                _RecipeGrid(
                  controller: controller,
                  snapshot: snapshot,
                  scrollController: scrollController,
                  onActivate: onActivate,
                  onActivateUsedIn: onActivateUsedIn,
                  onPreview: onPreview,
                ),
              AppRevealTransition(
                key: RecipeBookKeys.emptyReveal,
                visible: snapshot.entries.isEmpty,
                child: _RecipeBookEmpty(controller: controller),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _RecipeBookToolbar extends StatelessWidget {
  const _RecipeBookToolbar({
    required this.controller,
    required this.snapshot,
    required this.searchController,
    required this.searchFocus,
  });

  final RecipeBookController controller;
  final RecipeBookSnapshot snapshot;
  final TextEditingController searchController;
  final FocusNode searchFocus;

  @override
  Widget build(BuildContext context) {
    final spec = context.visualTheme;
    final ledger = spec.isIlluminatedLedger;
    final searchLabelStyle = spec.typography.label.copyWith(
      color: ledger
          ? spec.palette.textMuted
          : spec.isSakuraNightGarden
          ? spec.palette.trimBright
          : const Color(0xFFD7C783),
      fontSize: 11,
      fontWeight: FontWeight.w700,
    );
    final search = LayoutBuilder(
      builder: (context, constraints) {
        final textScale = MediaQuery.textScalerOf(
          context,
        ).scale(1).clamp(1.0, 2.0).toDouble();
        final searchWidth = (constraints.maxWidth * .485)
            .clamp(500.0, 560.0)
            .toDouble()
            .clamp(0.0, constraints.maxWidth)
            .toDouble()
            .roundToDouble();
        final scopeWidth = (316 * textScale)
            .clamp(316.0, 632.0)
            .toDouble()
            .clamp(0.0, constraints.maxWidth)
            .toDouble()
            .roundToDouble();
        const horizontalGap = 14.0;
        final stackControls =
            textScale > 1.25 ||
            searchWidth + horizontalGap + scopeWidth > constraints.maxWidth;
        final searchControlHeight = textScale <= 1.25
            ? 42.0
            : 42 + (14 * (textScale - 1));

        Widget searchInput = AppTextField(
          key: RecipeBookKeys.r03Search,
          controller: searchController,
          focusNode: searchFocus,
          semanticLabel: controller.searchByIngredient
              ? 'Search recipes by ingredient'
              : 'Search recipes',
          hintText: controller.searchHint,
          minimumHeight: searchControlHeight,
          suffixIcon: controller.search.isEmpty
              ? null
              : Center(
                  widthFactor: 1,
                  heightFactor: 1,
                  child: SizedBox.square(
                    dimension: 30,
                    child: AppButton(
                      key: RecipeBookKeys.r03ClearSearch,
                      role: AppButtonRole.optionPill,
                      minimumSize: Size.zero,
                      padding: EdgeInsets.zero,
                      semanticLabel: 'Clear recipe search',
                      tooltip: 'Clear recipe search',
                      onPressed: () {
                        searchController.clear();
                        controller.setSearch('');
                      },
                      child: const AppVectorGlyph('close', size: 11),
                    ),
                  ),
                ),
          onChanged: controller.setSearch,
        );
        searchInput = SizedBox(height: searchControlHeight, child: searchInput);
        final searchField = SizedBox(
          width: searchWidth,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              ExcludeSemantics(
                child: Text('SEARCH RECIPES', style: searchLabelStyle),
              ),
              const SizedBox(height: 4),
              searchInput,
            ],
          ),
        );
        final searchScope = SizedBox(
          key: RecipeBookKeys.r05ScopeGroup,
          width: scopeWidth,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              ExcludeSemantics(
                child: Text('SEARCH BY', style: searchLabelStyle),
              ),
              const SizedBox(height: 8),
              _RecipeBookSearchScope(controller: controller),
            ],
          ),
        );

        if (stackControls) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              searchField,
              const SizedBox(height: 10),
              searchScope,
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            searchField,
            const SizedBox(width: horizontalGap),
            searchScope,
          ],
        );
      },
    );
    final favorites = AppFilterButton(
      key: RecipeBookKeys.r04FavoritesOnly,
      selected: controller.favoritesOnly,
      label: 'Favorites',
      semanticLabel: 'Favorites only',
      onChanged: controller.setFavoritesOnly,
    );
    final viewControls = <Widget>[
      if (controller.usesProcessingPaging)
        _ProcessingGroupSelect(controller: controller, snapshot: snapshot),
    ];
    final browseControls = <Widget>[
      if (viewControls.isNotEmpty)
        _RecipeBookControlGroup(children: viewControls),
      if (viewControls.isNotEmpty) const _RecipeBookToolbarDivider(),
      favorites,
    ];
    final deleteControls = <Widget>[
      if (controller.canShowHidden)
        AppFilterButton(
          key: RecipeBookKeys.r26ShowHidden,
          selected: controller.showHidden,
          label: 'Hidden (${controller.totalHiddenItemCount})',
          semanticLabel:
              'Show hidden recipes (${controller.totalHiddenItemCount})',
          onChanged: controller.setShowHidden,
        ),
      if (controller.deleteToolsEnabled && !controller.deleteSelectionMode)
        AppButton.label(
          'Select to Delete',
          key: RecipeBookKeys.r17SelectToDelete,
          role: AppButtonRole.danger,
          minimumSize: const Size(148, 40),
          onPressed: controller.beginDeleteSelection,
        ),
      if (controller.deleteSelectionMode) ...<Widget>[
        AppButton.label(
          'Cancel Delete',
          key: RecipeBookKeys.r18CancelDelete,
          minimumSize: const Size(126, 40),
          onPressed: controller.cancelDeleteSelection,
        ),
        AppButton.label(
          'Delete Selected (${controller.selectedForDeletionCount})',
          key: RecipeBookKeys.r20DeleteSelected,
          role: AppButtonRole.danger,
          minimumSize: const Size(172, 40),
          onPressed: controller.selectedForDeletionCount == 0
              ? null
              : controller.requestDeleteConfirmation,
        ),
      ],
    ];
    final browse = _RecipeBookControlGroup(children: browseControls);
    final deleteActions = _RecipeBookControlGroup(children: deleteControls);
    final layoutScale = MediaQuery.textScalerOf(
      context,
    ).scale(1).clamp(1.0, 2.0).toDouble();
    final estimatedBrowseWidth =
        (controller.usesProcessingPaging ? 420.0 : 156) * layoutScale;
    final estimatedDeleteWidth =
        (controller.deleteSelectionMode
            ? 478.0
            : controller.deleteToolsEnabled
            ? 322.0
            : controller.canShowHidden
            ? 168.0
            : 0.0) *
        layoutScale;
    final market = _RecipeBookMarketControls(controller: controller);

    Widget buildBrowseRow(double availableWidth) {
      if (deleteControls.isEmpty) {
        return Align(alignment: Alignment.centerLeft, child: browse);
      }
      if (availableWidth >= estimatedBrowseWidth + 16 + estimatedDeleteWidth) {
        return Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: <Widget>[
            Expanded(
              child: Align(alignment: Alignment.centerLeft, child: browse),
            ),
            const SizedBox(width: 16),
            deleteActions,
          ],
        );
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Align(alignment: Alignment.centerLeft, child: browse),
          const SizedBox(height: 7),
          Align(alignment: Alignment.centerRight, child: deleteActions),
        ],
      );
    }

    Widget buildSimpleActionRow(double availableWidth) {
      final primaryActions = _RecipeBookControlGroup(
        children: <Widget>[browse, const _RecipeBookToolbarDivider(), market],
      );
      if (deleteControls.isEmpty) {
        return Align(alignment: Alignment.centerLeft, child: primaryActions);
      }
      final estimatedMarketWidth = controller.marketControlsVisible
          ? 730.0
          : 124.0;
      final estimatedPrimaryWidth =
          estimatedBrowseWidth + 17 + estimatedMarketWidth * layoutScale;
      if (availableWidth < estimatedPrimaryWidth) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Align(alignment: Alignment.centerLeft, child: browse),
            const SizedBox(height: 7),
            Align(alignment: Alignment.centerLeft, child: market),
            if (deleteControls.isNotEmpty) ...<Widget>[
              const SizedBox(height: 7),
              Align(alignment: Alignment.centerRight, child: deleteActions),
            ],
          ],
        );
      }
      if (availableWidth >= estimatedPrimaryWidth + 16 + estimatedDeleteWidth) {
        return Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: <Widget>[
            Expanded(
              child: Align(
                alignment: Alignment.centerLeft,
                child: primaryActions,
              ),
            ),
            const SizedBox(width: 16),
            deleteActions,
          ],
        );
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Align(alignment: Alignment.centerLeft, child: primaryActions),
          const SizedBox(height: 7),
          Align(alignment: Alignment.centerRight, child: deleteActions),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        search,
        const SizedBox(height: 10),
        LayoutBuilder(
          builder: (context, constraints) => controller.usesProcessingPaging
              ? buildBrowseRow(constraints.maxWidth)
              : buildSimpleActionRow(constraints.maxWidth),
        ),
        if (controller.usesProcessingPaging) ...<Widget>[
          const SizedBox(height: 8),
          Align(alignment: Alignment.centerLeft, child: market),
        ],
      ],
    );
  }
}

class _RecipeBookSearchScope extends StatelessWidget {
  const _RecipeBookSearchScope({required this.controller});

  final RecipeBookController controller;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      label: 'Recipe search scope',
      child: Row(
        mainAxisSize: MainAxisSize.max,
        children: <Widget>[
          Expanded(
            flex: 11,
            child: _RecipeBookScopeOption(
              key: RecipeBookKeys.r05RecipeNameScope,
              selected: !controller.searchByIngredient,
              label: 'Recipe name',
              semanticLabel: 'Search by recipe name',
              onPressed: () => controller.setSearchByIngredient(false),
            ),
          ),
          const SizedBox(width: 4),
          Expanded(
            flex: 10,
            child: _RecipeBookScopeOption(
              key: RecipeBookKeys.r05SearchByIngredient,
              selected: controller.searchByIngredient,
              label: 'Ingredient',
              semanticLabel: 'Search by ingredient',
              onPressed: () => controller.setSearchByIngredient(true),
            ),
          ),
        ],
      ),
    );
  }
}

class _RecipeBookScopeOption extends StatelessWidget {
  const _RecipeBookScopeOption({
    required this.selected,
    required this.label,
    required this.semanticLabel,
    required this.onPressed,
    super.key,
  });

  final bool selected;
  final String label;
  final String semanticLabel;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => AppButton(
    role: AppButtonRole.optionPill,
    selected: selected,
    minimumSize: const Size(0, 38),
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
    semanticLabel: semanticLabel,
    onPressed: onPressed,
    child: DefaultTextStyle.merge(
      style: const TextStyle(
        fontSize: 11.5,
        fontWeight: FontWeight.w600,
        letterSpacing: .05,
        height: 1,
      ),
      child: ExcludeSemantics(child: Text(label, maxLines: 1, softWrap: false)),
    ),
  );
}

class _RecipeBookControlGroup extends StatelessWidget {
  const _RecipeBookControlGroup({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.center,
    children: <Widget>[
      for (var index = 0; index < children.length; index += 1) ...<Widget>[
        if (index > 0) const SizedBox(width: 6),
        children[index],
      ],
    ],
  );
}

class _RecipeBookToolbarDivider extends StatelessWidget {
  const _RecipeBookToolbarDivider();

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 11,
    height: 22,
    child: Center(
      child: SizedBox(
        width: 1,
        height: 20,
        child: ColoredBox(
          color: context.visualTheme.palette.trim.withAlpha(88),
        ),
      ),
    ),
  );
}

class _RecipeBookMarketControls extends StatelessWidget {
  const _RecipeBookMarketControls({required this.controller});

  final RecipeBookController controller;

  @override
  Widget build(BuildContext context) {
    final spec = context.visualTheme;
    final status = controller.marketLoading
        ? null
        : _conciseMarketStatus(controller.marketMessage);
    final marketToggle = SizedBox(
      height: 40,
      child: AppButton.label(
        controller.marketControlsVisible ? 'Hide Market' : 'Check Market',
        key: RecipeBookKeys.r21CheckMarket,
        role: controller.marketControlsVisible
            ? AppButtonRole.primary
            : AppButtonRole.secondary,
        minimumSize: const Size(124, 40),
        onPressed: controller.marketLoading
            ? null
            : controller.marketControlsVisible
            ? controller.hideMarket
            : controller.checkMarket,
      ),
    );
    final commandControls = <Widget>[
      marketToggle,
      if (controller.marketControlsVisible) ...<Widget>[
        _MarketRefreshButton(
          loading: controller.marketLoading,
          onPressed: controller.checkMarket,
        ),
        AppFilterButton(
          key: RecipeBookKeys.r22OutOfStockOnly,
          selected: controller.outOfStockOnly,
          label: 'Out of stock',
          semanticLabel: 'Out of stock only',
          onChanged: controller.setOutOfStockOnly,
        ),
        Tooltip(
          message:
              'Only show recipes with a positive direct-buy estimate. '
              'Every selected ingredient is priced as bought; owned stock is '
              'not deducted.',
          child: AppFilterButton(
            key: RecipeBookKeys.r28ProfitableOnly,
            selected: controller.profitableOnly,
            label: 'Profitable',
            semanticLabel:
                'Show profitable recipes only, assuming all ingredients are bought',
            onChanged: controller.setProfitableOnly,
          ),
        ),
        SizedBox(
          key: RecipeBookKeys.r23MarketSort,
          width: 142,
          height: 40,
          child: AppSelect<RecipeBookMarketSort>(
            value: controller.marketSort,
            items: RecipeBookMarketSort.values
                .where((sort) => controller.profitableOnly || !sort.sortsProfit)
                .toList(growable: false),
            labelFor: (sort) => sort.label,
            semanticLabel: 'Recipe Book market sort',
            onChanged: (sort) {
              if (sort != null) controller.setMarketSort(sort);
            },
          ),
        ),
      ],
    ];
    final statusText = status == null
        ? null
        : Semantics(
            liveRegion: true,
            label: status,
            child: Text(
              status,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: spec.typography.meta.copyWith(color: spec.palette.warning),
            ),
          );
    return Semantics(
      container: true,
      label: controller.marketControlsVisible
          ? 'Recipe Book market controls'
          : 'Recipe Book market command',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          _RecipeBookMarketControlWrap(
            key: controller.marketControlsVisible
                ? RecipeBookKeys.r25MarketControls
                : null,
            children: commandControls,
          ),
          if (statusText != null) ...<Widget>[
            const SizedBox(height: 4),
            statusText,
          ],
        ],
      ),
    );
  }
}

class _RecipeBookMarketControlWrap extends StatelessWidget {
  const _RecipeBookMarketControlWrap({required this.children, super.key});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 6,
    runSpacing: 6,
    crossAxisAlignment: WrapCrossAlignment.center,
    children: children,
  );
}

String? _conciseMarketStatus(String? message) {
  final value = message?.trim();
  if (value == null || value.isEmpty) return null;
  final folded = value.toLowerCase();
  if (folded.contains('no market-listed')) {
    return 'No market-listed recipes to check.';
  }
  if (folded.contains('unavailable')) return 'Market check unavailable.';
  if (folded.contains('cancelled')) return 'Market check cancelled.';
  if (folded.contains('failed') || folded.contains('no usable')) {
    return 'Some market data could not be loaded.';
  }
  if (folded.contains('market id')) {
    return 'Some recipes have no market listing.';
  }
  return null;
}

class _MarketRefreshButton extends StatefulWidget {
  const _MarketRefreshButton({required this.loading, required this.onPressed});

  final bool loading;
  final Future<void> Function() onPressed;

  @override
  State<_MarketRefreshButton> createState() => _MarketRefreshButtonState();
}

class _MarketRefreshButtonState extends State<_MarketRefreshButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _rotation = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 650),
  );

  @override
  void initState() {
    super.initState();
    _syncAnimation();
  }

  @override
  void didUpdateWidget(_MarketRefreshButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.loading != widget.loading) _syncAnimation();
  }

  void _syncAnimation() {
    if (widget.loading) {
      _rotation.repeat();
      return;
    }
    _rotation
      ..stop()
      ..value = 0;
  }

  @override
  void dispose() {
    _rotation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 40,
    height: 40,
    child: AppButton(
      key: RecipeBookKeys.r24RefreshMarket,
      role: AppButtonRole.icon,
      minimumSize: const Size.square(40),
      padding: EdgeInsets.zero,
      semanticLabel: widget.loading
          ? 'Refreshing Recipe Book market stock'
          : 'Refresh Recipe Book market stock',
      tooltip: widget.loading
          ? 'Refreshing market stock'
          : 'Refresh market stock',
      onPressed: widget.loading ? null : widget.onPressed,
      child: RotationTransition(
        key: RecipeBookKeys.r24RefreshGlyph,
        turns: _rotation,
        child: const AppVectorGlyph('reset', size: 16),
      ),
    ),
  );
}

class _ProcessingGroupSelect extends StatelessWidget {
  const _ProcessingGroupSelect({
    required this.controller,
    required this.snapshot,
  });

  final RecipeBookController controller;
  final RecipeBookSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final counts = <ProcessingRecipeGroup, int>{
      for (final value in snapshot.groupCounts) value.group: value.count,
    };
    final groups = snapshot.groupCounts.map((value) => value.group).toList();
    return SizedBox(
      key: RecipeBookKeys.r07Groups,
      width: 238,
      height: 40,
      child: AppSelect<ProcessingRecipeGroup>(
        value: controller.group,
        items: groups,
        labelFor: (group) {
          final count = counts[group] ?? 0;
          final label = group == ProcessingRecipeGroup.all
              ? 'All recipes'
              : group.label;
          return '$label ($count)';
        },
        semanticLabel: 'Recipe category',
        onChanged: (group) {
          if (group != null) controller.setGroup(group);
        },
      ),
    );
  }
}

class _RecipeBookMeta extends StatelessWidget {
  const _RecipeBookMeta({required this.controller, required this.snapshot});

  final RecipeBookController controller;
  final RecipeBookSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final spec = context.visualTheme;
    final noun = controller.favoritesOnly ? 'favorites' : 'recipes';
    final count = Text(
      '${snapshot.filteredCount} $noun',
      style: spec.usesDenseSplitLayout
          ? spec.typography.body.copyWith(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              height: 1,
            )
          : spec.typography.label,
    );
    final statusText = controller.deletionError ?? controller.statusMessage;
    final status = statusText == null
        ? const SizedBox.shrink()
        : Semantics(
            liveRegion: true,
            child: Text(
              statusText,
              style: spec.typography.meta.copyWith(
                color: controller.deletionError == null
                    ? spec.palette.success
                    : spec.palette.danger,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          );
    return Row(
      children: <Widget>[
        Expanded(child: status),
        if (controller.canUndoDeletion) ...<Widget>[
          const SizedBox(width: 8),
          AppButton.label(
            'Undo',
            key: RecipeBookKeys.r20Undo,
            minimumSize: const Size(70, 34),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            onPressed: controller.deletionInProgress
                ? null
                : controller.undoLastDeletion,
          ),
        ],
        const SizedBox(width: 10),
        count,
      ],
    );
  }
}

class _RecipeGrid extends StatelessWidget {
  const _RecipeGrid({
    required this.controller,
    required this.snapshot,
    required this.scrollController,
    required this.onActivate,
    required this.onActivateUsedIn,
    required this.onPreview,
  });

  final RecipeBookController controller;
  final RecipeBookSnapshot snapshot;
  final ScrollController scrollController;
  final ValueChanged<String> onActivate;
  final bool Function(RecipeBookUseEntry, String?) onActivateUsedIn;
  final void Function(String name, Offset anchorGlobal) onPreview;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final spec = context.visualTheme;
      final denseLayout = spec.usesDenseSplitLayout;
      final metrics = _RecipeCardMetrics.resolve(
        processing: controller.usesProcessingPaging,
        denseLayout: denseLayout,
        density: controller.density,
      );
      final compactBonus =
          controller.callingContext == RecipeBookCallingContext.bonus &&
          snapshot.poolCount <= 6;
      final fittedMetrics = denseLayout && !compactBonus
          ? metrics.fitDenseWidth(
              availableWidth: constraints.maxWidth,
              columns: controller.density.columns,
            )
          : metrics;
      final outerCardWidth = fittedMetrics.cardWidth + fittedMetrics.margin * 2;
      final columns = (constraints.maxWidth / outerCardWidth)
          .floor()
          .clamp(1, controller.density.columns)
          .toInt();
      final rowExtent = fittedMetrics.cardHeight + fittedMetrics.margin * 2;
      final scrollView = GridView.builder(
        controller: scrollController,
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: columns,
          mainAxisExtent: rowExtent,
        ),
        itemCount: snapshot.entries.length,
        semanticChildCount: snapshot.entries.length,
        scrollCacheExtent: ScrollCacheExtent.pixels(rowExtent * 2),
        itemBuilder: (context, index) => Align(
          alignment: compactBonus ? Alignment.topCenter : Alignment.topLeft,
          child: Padding(
            padding: EdgeInsets.all(fittedMetrics.margin),
            child: SizedBox(
              width: fittedMetrics.cardWidth,
              height: fittedMetrics.cardHeight,
              child: _RecipeCard(
                key: RecipeBookKeys.card(snapshot.entries[index].name),
                controller: controller,
                entry: snapshot.entries[index],
                metrics: fittedMetrics,
                onActivate: onActivate,
                onActivateUsedIn: onActivateUsedIn,
                onPreview: onPreview,
              ),
            ),
          ),
        ),
      );
      return Listener(
        key: RecipeBookKeys.r10CardScroll,
        onPointerDown: (event) =>
            controller.beginPointer(event.position.dx, event.position.dy),
        onPointerMove: (event) =>
            controller.updatePointer(event.position.dx, event.position.dy),
        onPointerUp: (_) => controller.endPointer(),
        onPointerCancel: (_) => controller.endPointer(),
        child: ScrollConfiguration(
          behavior: const _RecipeBookScrollBehavior(),
          child: scrollView,
        ),
      );
    },
  );
}

class _RecipeCard extends StatelessWidget {
  const _RecipeCard({
    required this.controller,
    required this.entry,
    required this.metrics,
    required this.onActivate,
    required this.onActivateUsedIn,
    required this.onPreview,
    super.key,
  });

  final RecipeBookController controller;
  final RecipeBookEntry entry;
  final _RecipeCardMetrics metrics;
  final ValueChanged<String> onActivate;
  final bool Function(RecipeBookUseEntry, String?) onActivateUsedIn;
  final void Function(String name, Offset anchorGlobal) onPreview;

  void _cardAction() {
    if (controller.activationSuppressed ||
        entry.hidden ||
        isBrowsableRecipeBookReference(entry.recipe)) {
      return;
    }
    if (controller.deleteSelectionMode) {
      controller.toggleDeleteSelection(entry.name);
    } else {
      onActivate(entry.name);
    }
  }

  @override
  Widget build(BuildContext context) {
    final spec = context.visualTheme;
    final ledger = spec.isIlluminatedLedger;
    final sakura = spec.isSakuraNightGarden;
    final denseLayout = spec.usesDenseSplitLayout;
    final compactDensity = controller.density == RecipeBookDensity.sixByFive;
    final compactProcessing =
        controller.usesProcessingPaging &&
        controller.density != RecipeBookDensity.fourByThree;
    final compactProcessingSix =
        controller.usesProcessingPaging && compactDensity;
    final displayedRecipe = controller.recipeFor(entry.name) ?? entry.recipe;
    final productionMethod = _recipeProductionMethodLabel(displayedRecipe);
    final actionSize = compactProcessingSix
        ? 26.0
        : compactProcessing
        ? 30.0
        : 34.0;
    final activeName =
        controller.callingContext == RecipeBookCallingContext.bonus
        ? controller.modeController.state.value.bonusTarget
        : controller.modeController.state.value.target;
    final active = !entry.hidden && _sameRecipeName(entry.name, activeName);
    final deleteMode = controller.deleteSelectionMode;
    return Semantics(
      container: true,
      selected: entry.selectedForDeletion,
      label: entry.hidden
          ? '${entry.name} hidden recipe card'
          : '${entry.name} recipe card',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: entry.hidden ? null : _cardAction,
        child: DecoratedBox(
          position: DecorationPosition.foreground,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(
              ledger
                  ? 2
                  : sakura
                  ? spec.geometry.cardRadius
                  : 0,
            ),
            border: ledger || sakura
                ? Border.all(
                    color: entry.selectedForDeletion
                        ? spec.palette.danger
                        : entry.hidden
                        ? spec.palette.warning
                        : active
                        ? spec.palette.trimBright
                        : spec.palette.trim.withAlpha(142),
                  )
                : null,
          ),
          child: AppSurface(
            role: AppSurfaceRole.card,
            tone: entry.selectedForDeletion
                ? AppSurfaceTone.danger
                : entry.hidden
                ? AppSurfaceTone.warning
                : AppSurfaceTone.neutral,
            padding:
                compactDensity &&
                    (controller.usesProcessingPaging || !denseLayout)
                ? EdgeInsets.symmetric(horizontal: metrics.padding, vertical: 5)
                : EdgeInsets.all(metrics.padding),
            clipBehavior: Clip.antiAlias,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final stock = entry.marketStock;
                final profitability = entry.profitability;
                final targetRole = entry.hidden
                    ? AppButtonRole.secondary
                    : controller.deleteSelectionMode
                    ? ledger
                          ? entry.selectedForDeletion
                                ? AppButtonRole.primary
                                : AppButtonRole.secondary
                          : AppButtonRole.danger
                    : ledger
                    ? AppButtonRole.primary
                    : active
                    ? AppButtonRole.primary
                    : AppButtonRole.secondary;
                final targetButton =
                    isBrowsableRecipeBookReference(entry.recipe)
                    ? Semantics(
                        label: '${entry.name} reference information',
                        child: ExcludeSemantics(
                          child: Center(
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: <Widget>[
                                  const AppVectorGlyph('book', size: 13),
                                  if (!compactDensity) ...<Widget>[
                                    const SizedBox(width: 5),
                                    Text(
                                      'Reference',
                                      style: spec.typography.label.copyWith(
                                        color: spec.palette.textMuted,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ),
                        ),
                      )
                    : AppButton(
                        key: entry.hidden
                            ? RecipeBookKeys.r27RestoreHidden(entry.name)
                            : controller.deleteSelectionMode
                            ? RecipeBookKeys.r19DeleteSelection(entry.name)
                            : RecipeBookKeys.r11Target(entry.name),
                        role: targetRole,
                        selected: entry.selectedForDeletion,
                        minimumSize: denseLayout
                            ? Size.zero
                            : Size.fromHeight(metrics.buttonHeight),
                        padding: EdgeInsets.symmetric(
                          horizontal: denseLayout ? 2 : 8,
                          vertical: 2,
                        ),
                        semanticLabel: entry.hidden
                            ? 'Restore ${entry.name}'
                            : null,
                        onPressed:
                            entry.hidden &&
                                controller.restoringHiddenName != null
                            ? null
                            : entry.hidden
                            ? () => controller.restoreHiddenItem(entry.name)
                            : _cardAction,
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: <Widget>[
                              AppVectorGlyph(
                                entry.hidden
                                    ? 'reset'
                                    : controller.deleteSelectionMode
                                    ? entry.selectedForDeletion
                                          ? 'check'
                                          : 'add'
                                    : 'target',
                                size: 13,
                              ),
                              if (!compactDensity) ...<Widget>[
                                const SizedBox(width: 5),
                                Text(
                                  entry.hidden
                                      ? controller.restoringHiddenName ==
                                                entry.name
                                            ? 'Restoring...'
                                            : 'Restore'
                                      : controller.deleteSelectionMode
                                      ? entry.selectedForDeletion
                                            ? 'Selected'
                                            : 'Select'
                                      : 'Target',
                                ),
                              ],
                            ],
                          ),
                        ),
                      );
                final title = _RecipeCardTitle(
                  name: entry.name,
                  productionMethod: productionMethod,
                  nameSize: metrics.nameSize,
                  compact: compactDensity,
                );
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        RecipeBookItemIcon(
                          controller: controller,
                          name: entry.name,
                          size: metrics.iconSize,
                          anchorId: 'card:${entry.name}',
                        ),
                        if (entry.hidden)
                          const Expanded(
                            child: Padding(
                              padding: EdgeInsets.symmetric(horizontal: 7),
                              child: Align(
                                alignment: Alignment.centerLeft,
                                child: _HiddenRecipePill(),
                              ),
                            ),
                          )
                        else if (profitability != null)
                          Expanded(
                            child: Padding(
                              padding: EdgeInsets.only(
                                left: compactProcessing ? 5 : 7,
                              ),
                              child: Align(
                                alignment: Alignment.centerLeft,
                                child: _RecipeBookProfitabilityPill(
                                  key: RecipeBookKeys.profitPill(entry.name),
                                  quote: profitability,
                                  compact: compactProcessing,
                                ),
                              ),
                            ),
                          )
                        else if (stock != null)
                          if (compactProcessingSix)
                            const Spacer()
                          else
                            Expanded(
                              child: Padding(
                                padding: EdgeInsets.only(
                                  left: compactProcessing ? 5 : 7,
                                ),
                                child: Align(
                                  alignment: Alignment.centerLeft,
                                  child: _RecipeBookStockPill(stock: stock),
                                ),
                              ),
                            )
                        else
                          const Spacer(),
                        if (!entry.hidden &&
                            !isBrowsableRecipeBookReference(entry.recipe))
                          Tooltip(
                            message: entry.name,
                            waitDuration: const Duration(milliseconds: 450),
                            child: AppButton(
                              key: RecipeBookKeys.r12Favorite(entry.name),
                              role: AppButtonRole.optionPill,
                              selected: deleteMode
                                  ? entry.selectedForDeletion
                                  : entry.favorite,
                              minimumSize: Size.square(actionSize),
                              padding: EdgeInsets.zero,
                              semanticLabel: deleteMode
                                  ? '${entry.selectedForDeletion ? 'Deselect' : 'Select'} ${entry.name} for deletion'
                                  : '${entry.favorite ? 'Remove' : 'Add'} ${entry.name} favorite',
                              onPressed: deleteMode
                                  ? () => controller.toggleDeleteSelection(
                                      entry.name,
                                    )
                                  : () => controller.toggleFavorite(entry.name),
                              child: AppVectorGlyph(
                                deleteMode && entry.selectedForDeletion
                                    ? 'check'
                                    : deleteMode
                                    ? 'add'
                                    : 'star',
                                size: compactProcessing ? 12 : 15,
                                color: !deleteMode && entry.favorite
                                    ? spec.palette.warning
                                    : null,
                              ),
                            ),
                          ),
                      ],
                    ),
                    SizedBox(height: metrics.rowSpacing),
                    Expanded(
                      child:
                          (profitability != null || compactProcessingSix) &&
                              stock != null
                          ? Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: <Widget>[
                                Expanded(child: title),
                                const SizedBox(width: 4),
                                _RecipeBookStockPill(
                                  stock: stock,
                                  compact: compactProcessingSix,
                                ),
                              ],
                            )
                          : Align(alignment: Alignment.topLeft, child: title),
                    ),
                    SizedBox(height: metrics.rowSpacing),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: <Widget>[
                        SizedBox(
                          width: compactDensity ? 34 : 96,
                          height: actionSize,
                          child: targetButton,
                        ),
                        const Spacer(),
                        if (!deleteMode)
                          Builder(
                            builder: (buttonContext) => AppButton(
                              key: RecipeBookKeys.r13Details(entry.name),
                              role: ledger
                                  ? AppButtonRole.primary
                                  : sakura
                                  ? AppButtonRole.secondary
                                  : AppButtonRole.optionPill,
                              minimumSize: Size.square(actionSize),
                              padding: EdgeInsets.zero,
                              semanticLabel: 'Preview ${entry.name}',
                              tooltip: 'Preview ingredients',
                              onPressed: () {
                                final box = buttonContext.findRenderObject();
                                final anchor = box is RenderBox
                                    ? box.localToGlobal(
                                        box.size.center(Offset.zero),
                                      )
                                    : Offset.zero;
                                onPreview(entry.name, anchor);
                              },
                              child: AppVectorGlyph(
                                'book',
                                size: compactProcessing ? 12 : 14,
                              ),
                            ),
                          ),
                        if (!deleteMode && entry.usedInCount > 0) ...<Widget>[
                          SizedBox(width: compactProcessing ? 3 : 6),
                          AnchoredPopover(
                            overlayId: 'recipe-book-used-in:${entry.name}',
                            preferredWidth: 570,
                            maximumHeight: 610,
                            alignEnd: true,
                            placement: AnchoredPopoverPlacement.beside,
                            consumeOutsideTap: true,
                            anchorBuilder: (context, toggle, isShowing) => AppButton(
                              key: RecipeBookKeys.usedIn(entry.name),
                              role: isShowing
                                  ? AppButtonRole.primary
                                  : ledger
                                  ? AppButtonRole.primary
                                  : sakura
                                  ? AppButtonRole.secondary
                                  : AppButtonRole.optionPill,
                              selected: isShowing,
                              minimumSize: Size.square(actionSize),
                              padding: EdgeInsets.zero,
                              semanticLabel:
                                  '${entry.name} is used in ${entry.usedInCount} recipe ${entry.usedInCount == 1 ? 'path' : 'paths'}',
                              tooltip:
                                  'Used in ${entry.usedInCount} recipe ${entry.usedInCount == 1 ? 'path' : 'paths'}',
                              onPressed: toggle,
                              child: _UsedInActionGlyph(
                                count: entry.usedInCount,
                                compact: compactProcessing,
                              ),
                            ),
                            popoverBuilder: (context, close) =>
                                RecipeBookUsedInPanel(
                                  controller: controller,
                                  sourceName: entry.name,
                                  snapshot: controller.usedInFor(entry.name),
                                  onClose: close,
                                  onActivate: onActivateUsedIn,
                                ),
                          ),
                        ],
                      ],
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _RecipeCardTitle extends StatelessWidget {
  const _RecipeCardTitle({
    required this.name,
    required this.productionMethod,
    required this.nameSize,
    required this.compact,
  });

  final String name;
  final String productionMethod;
  final double nameSize;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final spec = context.visualTheme;
    final methodSize = (nameSize - (compact ? 2.3 : 2.8))
        .clamp(9.5, 12.5)
        .toDouble();
    final name = Text(
      this.name,
      style: spec.typography.label.copyWith(
        fontSize: nameSize,
        fontWeight: FontWeight.w700,
        height: compact ? 1 : 1.06,
      ),
      maxLines: compact ? 2 : 3,
      overflow: TextOverflow.ellipsis,
    );
    final method = Text(
      productionMethod,
      key: RecipeBookKeys.productionMethod(this.name),
      style: spec.typography.meta.copyWith(
        color: spec.palette.textMuted,
        fontSize: methodSize,
        fontWeight: FontWeight.w600,
        letterSpacing: .15,
        height: compact ? .92 : 1,
      ),
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        if (!constraints.maxHeight.isFinite) {
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              name,
              if (!compact) const SizedBox(height: 1),
              method,
            ],
          );
        }
        return SizedBox(
          height: constraints.maxHeight,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Flexible(child: name),
              if (!compact) const SizedBox(height: 1),
              method,
            ],
          ),
        );
      },
    );
  }
}

class _UsedInActionGlyph extends StatelessWidget {
  const _UsedInActionGlyph({required this.count, required this.compact});

  final int count;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final spec = context.visualTheme;
    final badgeSize = compact ? 12.0 : 15.0;
    return Stack(
      clipBehavior: Clip.none,
      alignment: Alignment.center,
      children: <Widget>[
        AppVectorGlyph('branch', size: compact ? 12 : 15),
        Positioned(
          right: compact ? -5 : -6,
          top: compact ? -5 : -6,
          child: Container(
            width: badgeSize,
            height: badgeSize,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: spec.palette.primary,
              shape: BoxShape.circle,
              border: Border.all(color: spec.palette.surfaceRaised, width: 1),
            ),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Padding(
                padding: const EdgeInsets.all(1),
                child: Text(
                  count > 99 ? '99+' : '$count',
                  style: spec.typography.meta.copyWith(
                    color: spec.palette.text,
                    fontSize: compact ? 7 : 8,
                    fontWeight: FontWeight.w900,
                    height: 1,
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _HiddenRecipePill extends StatelessWidget {
  const _HiddenRecipePill();

  @override
  Widget build(BuildContext context) {
    final spec = context.visualTheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: spec.palette.warning.withAlpha(62),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: spec.palette.warning.withAlpha(170)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        child: Text(
          'HIDDEN',
          style: spec.typography.meta.copyWith(
            color: spec.palette.text,
            fontSize: 9.5,
            fontWeight: FontWeight.w800,
            letterSpacing: .35,
            height: 1,
          ),
          maxLines: 1,
          overflow: TextOverflow.clip,
        ),
      ),
    );
  }
}

class _RecipeBookProfitabilityPill extends StatelessWidget {
  const _RecipeBookProfitabilityPill({
    required this.quote,
    this.compact = false,
    super.key,
  });

  final RecipeProfitabilityQuote quote;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final spec = context.visualTheme;
    final returnOnCostPercent = quote.returnOnCostPercent!;
    final profitPerPiece = quote.profitPerPiece!;
    final outputPerCraft = quote.outputPerCraft!;
    final ingredientCost = quote.ingredientCost!;
    final netRevenue = quote.netRevenue!;
    final netRate = quote.marketNetRate!;
    final roi = formatQuantity(
      returnOnCostPercent,
      fractionDigits: returnOnCostPercent.abs() >= 100 ? 0 : 1,
    );
    final profit = formatSilver(profitPerPiece);
    final label = '+$roi% · +$profit/ea';
    final details =
        'Estimated profit when every selected direct ingredient is bought.\n'
        'Expected output: ${formatQuantity(outputPerCraft)} per craft\n'
        'Ingredient cost: ${formatSilverLabel(ingredientCost)} per craft\n'
        'After-tax revenue: ${formatSilverLabel(netRevenue)} per craft '
        '(${formatQuantity(netRate * 100, fractionDigits: 1)}% net)\n'
        'Profit: ${formatSilverLabel(profitPerPiece)} per output '
        '($roi% return on ingredient cost)\n'
        'Excludes owned inventory, byproducts, time, energy, and utensils. '
        'Ingredient stock is not guaranteed.';
    return Semantics(
      label: '$label. $details',
      excludeSemantics: true,
      child: Tooltip(
        message: details,
        waitDuration: const Duration(milliseconds: 350),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: spec.palette.success.withAlpha(92),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: spec.palette.success.withAlpha(178)),
          ),
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: compact ? 5 : 7,
              vertical: 3,
            ),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                label,
                style: spec.typography.meta.copyWith(
                  color: spec.palette.text,
                  fontSize: compact ? 8.75 : 10.25,
                  fontWeight: FontWeight.w800,
                  height: 1,
                ),
                maxLines: 1,
                softWrap: false,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RecipeBookStockPill extends StatelessWidget {
  const _RecipeBookStockPill({required this.stock, this.compact = false});

  final double stock;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final spec = context.visualTheme;
    final empty = stock <= 0;
    return Tooltip(
      message: empty ? 'Out of stock' : '${formatQuantity(stock)} in stock',
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: empty
              ? spec.palette.danger.withAlpha(92)
              : spec.palette.success.withAlpha(86),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: empty
                ? spec.palette.danger.withAlpha(178)
                : spec.palette.success.withAlpha(165),
          ),
        ),
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: compact ? 5 : 7,
            vertical: 3,
          ),
          child: Text(
            compact
                ? formatQuantity(stock)
                : empty
                ? '0 stock'
                : '${formatQuantity(stock)} stock',
            style: spec.typography.meta.copyWith(
              color: spec.palette.text,
              fontSize: compact ? 9.5 : 10.5,
              fontWeight: FontWeight.w800,
              height: 1,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ),
    );
  }
}

@immutable
class _RecipeCardMetrics {
  const _RecipeCardMetrics({
    required this.cardWidth,
    required this.cardHeight,
    required this.iconSize,
    required this.margin,
    required this.padding,
    required this.nameSize,
    required this.buttonHeight,
    required this.rowSpacing,
  });

  final double cardWidth;
  final double cardHeight;
  final double iconSize;
  final double margin;
  final double padding;
  final double nameSize;
  final double buttonHeight;
  final double rowSpacing;

  _RecipeCardMetrics fitDenseWidth({
    required double availableWidth,
    required int columns,
  }) {
    if (columns <= 0 || !availableWidth.isFinite) return this;
    // Avalonia reserves 32 px inside the already padded modal for the themed
    // scrollbar and frame gutter before distributing the requested columns.
    final fittedWidth = (((availableWidth - 32) / columns) - margin * 2)
        .clamp(120.0, cardWidth)
        .ceilToDouble();
    if (fittedWidth >= cardWidth) return this;
    return _RecipeCardMetrics(
      cardWidth: fittedWidth,
      cardHeight: cardHeight,
      iconSize: iconSize,
      margin: margin,
      padding: padding,
      nameSize: nameSize,
      buttonHeight: buttonHeight,
      rowSpacing: rowSpacing,
    );
  }

  static _RecipeCardMetrics resolve({
    required bool processing,
    required bool denseLayout,
    required RecipeBookDensity density,
  }) {
    if (processing) {
      return switch (density) {
        RecipeBookDensity.sixByFive => const _RecipeCardMetrics(
          cardWidth: 190,
          cardHeight: 108,
          iconSize: 30,
          margin: 3,
          padding: 8,
          nameSize: 11,
          buttonHeight: 22,
          rowSpacing: 3,
        ),
        RecipeBookDensity.fiveByFour => const _RecipeCardMetrics(
          cardWidth: 228,
          cardHeight: 136,
          iconSize: 38,
          margin: 4,
          padding: 9,
          nameSize: 13,
          buttonHeight: 26,
          rowSpacing: 6,
        ),
        RecipeBookDensity.fourByThree => const _RecipeCardMetrics(
          cardWidth: 276,
          cardHeight: 170,
          iconSize: 50,
          margin: 5,
          padding: 12,
          nameSize: 15.5,
          buttonHeight: 30,
          rowSpacing: 8,
        ),
      };
    }
    if (denseLayout) {
      return switch (density) {
        RecipeBookDensity.sixByFive => const _RecipeCardMetrics(
          cardWidth: 194,
          cardHeight: 134,
          iconSize: 34,
          margin: 3,
          padding: 8,
          nameSize: 11.5,
          buttonHeight: 24,
          rowSpacing: 6,
        ),
        RecipeBookDensity.fiveByFour => const _RecipeCardMetrics(
          cardWidth: 230,
          cardHeight: 154,
          iconSize: 42,
          margin: 4,
          padding: 10,
          nameSize: 13.5,
          buttonHeight: 28,
          rowSpacing: 8,
        ),
        RecipeBookDensity.fourByThree => const _RecipeCardMetrics(
          cardWidth: 290,
          cardHeight: 198,
          iconSize: 54,
          margin: 5,
          padding: 12,
          nameSize: 15.5,
          buttonHeight: 32,
          rowSpacing: 9,
        ),
      };
    }
    return switch (density) {
      RecipeBookDensity.sixByFive => const _RecipeCardMetrics(
        cardWidth: 166,
        cardHeight: 120,
        iconSize: 30,
        margin: 3,
        padding: 8,
        nameSize: 11,
        buttonHeight: 22,
        rowSpacing: 5,
      ),
      RecipeBookDensity.fiveByFour => const _RecipeCardMetrics(
        cardWidth: 196,
        cardHeight: 148,
        iconSize: 40,
        margin: 4,
        padding: 9,
        nameSize: 13,
        buttonHeight: 26,
        rowSpacing: 8,
      ),
      RecipeBookDensity.fourByThree => const _RecipeCardMetrics(
        cardWidth: 236,
        cardHeight: 182,
        iconSize: 50,
        margin: 5,
        padding: 11,
        nameSize: 15.5,
        buttonHeight: 30,
        rowSpacing: 8,
      ),
    };
  }
}

bool _sameRecipeName(String left, String right) =>
    left.trim().toLowerCase() == right.trim().toLowerCase();

class _RecipeBookEmpty extends StatelessWidget {
  const _RecipeBookEmpty({required this.controller});

  final RecipeBookController controller;

  @override
  Widget build(BuildContext context) {
    final filters = <String>[
      if (controller.search.trim().isNotEmpty) 'search',
      if (controller.favoritesOnly) 'Favorites Only',
      if (controller.outOfStockOnly) 'Out of stock',
      if (controller.profitableOnly) 'Profitable',
      if (controller.usesProcessingPaging &&
          controller.group != ProcessingRecipeGroup.all)
        '${controller.group.label} group',
    ];
    final reason = filters.isEmpty
        ? 'No usable recipes are available for this calling context.'
        : 'No recipes match the current ${filters.join(', ')} ${filters.length == 1 ? 'filter' : 'filters'}.';
    return AppSurface(
      role: AppSurfaceRole.card,
      semanticLabel: 'Recipe Book has no matching recipes',
      child: Center(
        child: Text(
          reason,
          textAlign: TextAlign.center,
          style: context.visualTheme.typography.body,
        ),
      ),
    );
  }
}

class _RecipePreviewOverlay extends StatelessWidget {
  const _RecipePreviewOverlay({
    required this.controller,
    required this.externalActions,
    required this.recipeName,
    required this.anchorGlobal,
    required this.closeFocus,
    required this.onActivate,
  });

  final RecipeBookController controller;
  final PlannerExternalActions? externalActions;
  final String recipeName;
  final Offset? anchorGlobal;
  final FocusNode closeFocus;
  final ValueChanged<String> onActivate;

  @override
  Widget build(BuildContext context) {
    final spec = context.visualTheme;
    final recipe = controller.recipeFor(recipeName);
    if (recipe == null) return const SizedBox.shrink();
    final hidden = controller.isHiddenRecipe(recipeName);
    final ledger = spec.isIlluminatedLedger;
    final sakura = spec.isSakuraNightGarden;
    return LayoutBuilder(
      builder: (context, constraints) {
        final modalWidth = (constraints.maxWidth - 92).clamp(760.0, 1220.0);
        final modalHeight = (constraints.maxHeight - 86).clamp(560.0, 820.0);
        final modalLeft = (constraints.maxWidth - modalWidth) / 2;
        final modalTop = (constraints.maxHeight - modalHeight) / 2;
        final contentLeft = modalLeft + 16;
        final contentTop = modalTop + 16;
        final contentWidth = modalWidth - 32;
        final contentHeight = modalHeight - 32;
        final panelWidth = _previewPanelWidth(context, recipe, contentWidth);
        final availableHeight = contentHeight.clamp(260.0, 650.0);
        final panelHeight =
            (123 +
                    (recipe.hasRecipeVariants ? 39 : 0) +
                    (recipe.ingredients.isEmpty
                            ? 1
                            : recipe.ingredients.length) *
                        72)
                .clamp(195.0, availableHeight)
                .toDouble();
        final overlayBox = context.findRenderObject();
        final anchor = anchorGlobal == null
            ? Offset(
                contentLeft + contentWidth / 2,
                contentTop + contentHeight / 2,
              )
            : overlayBox is RenderBox
            ? overlayBox.globalToLocal(anchorGlobal!)
            : anchorGlobal!;
        final localX = anchor.dx - contentLeft;
        final localY = anchor.dy - contentTop;
        var panelLeft = localX + 18;
        if (panelLeft + panelWidth > contentWidth - 4) {
          panelLeft = localX - panelWidth - 18;
        }
        panelLeft = panelLeft
            .clamp(
              4.0,
              (contentWidth - panelWidth - 4).clamp(4.0, double.infinity),
            )
            .toDouble();
        final panelTop = (localY - panelHeight / 2)
            .clamp(
              4.0,
              (contentHeight - panelHeight - 4).clamp(4.0, double.infinity),
            )
            .toDouble();
        return Stack(
          children: <Widget>[
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: controller.closePreview,
                child: ColoredBox(
                  color: ledger
                      ? const Color(0x3B0A2744)
                      : sakura
                      ? spec.materials.modalScrim.withAlpha(116)
                      : const Color(0x01000000),
                ),
              ),
            ),
            DraggableOverlaySurface(
              overlayId: 'recipe-preview:$recipeName',
              initialPosition: (_, _) =>
                  Offset(contentLeft + panelLeft, contentTop + panelTop),
              margin: 12,
              child: SizedBox(
                width: panelWidth,
                height: panelHeight,
                child: GestureDetector(
                  key: RecipeBookKeys.previewPanel,
                  behavior: HitTestBehavior.opaque,
                  onTap: () => FocusScope.of(context).requestFocus(),
                  child: AppSurface(
                    role: AppSurfaceRole.modal,
                    padding: const EdgeInsets.all(14),
                    clipBehavior: Clip.antiAlias,
                    semanticLabel: '$recipeName recipe preview',
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        Row(
                          children: <Widget>[
                            RecipeBookItemIcon(
                              controller: controller,
                              name: recipeName,
                              size: 48,
                              anchorId: 'preview:$recipeName',
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: DraggableOverlayDragRegion(
                                key: RecipeBookKeys.previewDragRegion,
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: <Widget>[
                                    Text(
                                      recipeName,
                                      style: spec.typography.section.copyWith(
                                        fontSize: 18,
                                        height: 1,
                                      ),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    const SizedBox(height: 3),
                                    Text(
                                      _previewMeta(recipe),
                                      style: spec.typography.meta.copyWith(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w700,
                                        height: 1,
                                      ),
                                    ),
                                    Text(
                                      '${controller.isEstimatedOutput(recipe.name) ? 'Estimated output' : 'Output'} ${_previewOutput(recipe)}',
                                      style: spec.typography.label.copyWith(
                                        color: spec.palette.warning,
                                        fontSize: 11,
                                        height: 1,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            if (hidden) ...<Widget>[
                              const _HiddenRecipePill(),
                              const SizedBox(width: 8),
                            ],
                            AppButton(
                              key: RecipeBookKeys.r14ClosePreview(recipeName),
                              focusNode: closeFocus,
                              role: ledger
                                  ? AppButtonRole.primary
                                  : AppButtonRole.optionPill,
                              minimumSize: const Size.square(30),
                              padding: EdgeInsets.zero,
                              semanticLabel: 'Close $recipeName preview',
                              tooltip: 'Close preview',
                              onPressed: controller.closePreview,
                              child: const AppVectorGlyph('close', size: 11),
                            ),
                          ],
                        ),
                        if (recipe.hasRecipeVariants) ...<Widget>[
                          const SizedBox(height: 10),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: RecipeVariantSelector(
                              recipe: recipe,
                              selectedVariantId: controller
                                  .selectedRecipeVariantId(recipeName),
                              compact: true,
                              onSelected: hidden
                                  ? null
                                  : (variantId) =>
                                        controller.selectRecipeVariant(
                                          recipeName,
                                          variantId,
                                        ),
                            ),
                          ),
                        ],
                        const SizedBox(height: 12),
                        Row(
                          children: <Widget>[
                            Expanded(
                              child: Text(
                                '${recipe.ingredients.length} ${recipe.ingredients.length == 1 ? 'ingredient' : 'ingredients'}',
                                style: spec.typography.label.copyWith(
                                  fontSize: 12,
                                ),
                              ),
                            ),
                            if (isBrowsableRecipeBookReference(recipe))
                              Semantics(
                                label: '$recipeName reference information',
                                child: ExcludeSemantics(
                                  child: SizedBox(
                                    width: 95,
                                    height: 38,
                                    child: Center(
                                      child: FittedBox(
                                        fit: BoxFit.scaleDown,
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: <Widget>[
                                            const AppVectorGlyph(
                                              'book',
                                              size: 13,
                                            ),
                                            const SizedBox(width: 5),
                                            Text(
                                              'Reference',
                                              style: spec.typography.label
                                                  .copyWith(
                                                    color:
                                                        spec.palette.textMuted,
                                                  ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              )
                            else
                              SizedBox(
                                key: hidden
                                    ? RecipeBookKeys.r27RestoreHidden(
                                        '$recipeName:preview',
                                      )
                                    : RecipeBookKeys.r11Target(
                                        '$recipeName:preview',
                                      ),
                                width: 95,
                                height: 38,
                                child: AppButton(
                                  role: hidden
                                      ? AppButtonRole.secondary
                                      : AppButtonRole.primary,
                                  minimumSize: Size.zero,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 3,
                                  ),
                                  onPressed:
                                      hidden &&
                                          controller.restoringHiddenName != null
                                      ? null
                                      : hidden
                                      ? () => controller.restoreHiddenItem(
                                          recipeName,
                                        )
                                      : () => onActivate(recipeName),
                                  child: FittedBox(
                                    fit: BoxFit.scaleDown,
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: <Widget>[
                                        AppVectorGlyph(
                                          hidden ? 'reset' : 'target',
                                          size: 13,
                                        ),
                                        const SizedBox(width: 5),
                                        Text(hidden ? 'Restore' : 'Target'),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Expanded(
                          child: recipe.ingredients.isEmpty
                              ? Center(
                                  child: Text(
                                    'No recipe ingredients recorded.',
                                    style: spec.typography.body,
                                  ),
                                )
                              : ListView.separated(
                                  padding: const EdgeInsets.only(
                                    right: 8,
                                    bottom: 10,
                                  ),
                                  itemCount: recipe.ingredients.length,
                                  separatorBuilder: (_, _) =>
                                      const SizedBox(height: 8),
                                  itemBuilder: (context, index) =>
                                      _PreviewIngredientRow(
                                        controller: controller,
                                        externalActions: externalActions,
                                        parentName: recipeName,
                                        ingredient: recipe.ingredients[index],
                                        ingredientIndex: index,
                                      ),
                                ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  String _previewMeta(Recipe recipe) {
    final category = switch (recipe.group?.trim()) {
      final group? when group.isNotEmpty => group,
      _ => recipe.hasRecordedRecipe ? 'Crafted' : 'Base Items',
    };
    return '$category / ${_recipeTypeLabel(recipe.type)}';
  }

  String _previewOutput(Recipe recipe) {
    final minimum = recipe.outputMinimum;
    final maximum = recipe.outputMaximum;
    if (recipe.type.trim().toLowerCase() == 'processing' && minimum != null) {
      if (maximum == null || maximum == minimum) {
        return formatQuantity(minimum);
      }
      return '${formatQuantity(minimum)}–${formatQuantity(maximum)}';
    }
    return formatQuantity(recipe.baseOutput);
  }

  double _previewPanelWidth(
    BuildContext context,
    Recipe recipe,
    double contentWidth,
  ) {
    final spec = context.visualTheme;
    final measurementStyle = spec.typography.body.copyWith(
      fontFamily: spec.isIlluminatedLedger
          ? 'Georgia'
          : spec.typography.body.fontFamily,
      fontWeight: FontWeight.w700,
    );
    var longestSubstitute = 0.0;
    for (final ingredient in recipe.ingredients) {
      for (final option in controller.substituteOptions(ingredient)) {
        final painter = TextPainter(
          text: TextSpan(text: option, style: measurementStyle),
          textDirection: Directionality.of(context),
          textScaler: MediaQuery.textScalerOf(context),
          maxLines: 1,
        )..layout();
        if (painter.width > longestSubstitute) {
          longestSubstitute = painter.width;
        }
      }
    }

    // The remaining width accounts for the panel and row padding, item icon,
    // selector affordance, scrollbar gutter, and up to three quality swatches.
    const selectorChrome = 236.0;
    final availableWidth = (contentWidth - 8).clamp(430.0, double.infinity);
    return (longestSubstitute + selectorChrome)
        .clamp(430.0, availableWidth)
        .toDouble();
  }
}

class _PreviewIngredientRow extends StatelessWidget {
  const _PreviewIngredientRow({
    required this.controller,
    required this.externalActions,
    required this.parentName,
    required this.ingredient,
    required this.ingredientIndex,
  });

  final RecipeBookController controller;
  final PlannerExternalActions? externalActions;
  final String parentName;
  final Ingredient ingredient;
  final int ingredientIndex;

  @override
  Widget build(BuildContext context) {
    final spec = context.visualTheme;
    final options = controller.substituteOptions(ingredient);
    final selected = controller.selectedSubstitute(parentName, ingredient);
    final ratio = controller.substituteRatio(ingredient, selected);
    final grades = controller.qualityGrades(
      parentName: parentName,
      ingredient: ingredient,
      selectedName: selected,
    );
    final selectedGrade = controller.selectedQuality(
      parentName: parentName,
      ingredient: ingredient,
      selectedName: selected,
    );
    final row = AppSurface(
      role: AppSurfaceRole.row,
      semanticLabel: '$selected preview ingredient',
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: <Widget>[
          SizedBox(
            width: 38,
            child: Align(
              child: RecipeBookItemIcon(
                controller: controller,
                name: selected,
                size: 34,
                anchorId:
                    'preview:$parentName:ingredient:$ingredientIndex:$selected',
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    if (options.length > 1)
                      Expanded(
                        key: RecipeBookKeys.r15Substitute(
                          parentName,
                          ingredient.name,
                        ),
                        child: SizedBox(
                          height: 28,
                          child: AppSelect<String>(
                            value: selected,
                            items: options,
                            labelFor: (value) => value,
                            semanticLabel:
                                'Substitute for ${ingredient.name} in $parentName',
                            onChanged: (value) {
                              if (value == null) return;
                              controller.selectSubstitute(
                                parentName: parentName,
                                ingredient: ingredient,
                                selection: value,
                              );
                            },
                          ),
                        ),
                      )
                    else
                      Expanded(
                        child: Text(
                          selected,
                          style: spec.typography.label.copyWith(fontSize: 13),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    if (grades.isNotEmpty) ...<Widget>[
                      const SizedBox(width: 7),
                      for (final grade in grades) ...<Widget>[
                        _PreviewQualitySwatch(
                          key: RecipeBookKeys.r16Quality(
                            parentName,
                            ingredient.name,
                            grade,
                          ),
                          grade: grade,
                          normalIsBlueFamily: grades.contains('blue'),
                          selected: selectedGrade == grade,
                          onPressed: () => controller.selectQuality(
                            parentName: parentName,
                            ingredient: ingredient,
                            grade: grade,
                          ),
                        ),
                        if (grade != grades.last) const SizedBox(width: 4),
                      ],
                    ],
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  'Need ${formatQuantity(ingredient.quantity * ratio)}',
                  style: spec.typography.meta.copyWith(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
    final actions = externalActions;
    if (actions == null) return row;
    final stableId = 'recipe-preview:$parentName:$ingredientIndex:$selected';
    return PlannerMapQuickLookupRegion(
      key: RecipeBookKeys.mapLookupRegion(
        parentName,
        ingredientIndex,
        selected,
      ),
      materialName: selected,
      stableId: stableId,
      externalActions: actions,
      child: row,
    );
  }
}

class _PreviewQualitySwatch extends StatelessWidget {
  const _PreviewQualitySwatch({
    required this.grade,
    required this.normalIsBlueFamily,
    required this.selected,
    required this.onPressed,
    super.key,
  });

  final String grade;
  final bool normalIsBlueFamily;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final spec = context.visualTheme;
    final ledger = spec.isIlluminatedLedger;
    final sakura = spec.isSakuraNightGarden;
    final denseLayout = spec.usesDenseSplitLayout;
    final (fill, outline, label) = switch (grade.toLowerCase()) {
      'high' => (
        const Color(0xAA6FC17A),
        const Color(0xB9A9E890),
        'High quality',
      ),
      'special' => (
        const Color(0xAA558FD5),
        const Color(0xB9A8C8FF),
        'Special quality',
      ),
      'blue' => (const Color(0xAA4D73D2), const Color(0xB9BBCDFF), 'Blue'),
      _ when normalIsBlueFamily => (
        const Color(0xAA4FAF72),
        const Color(0xB9A9E890),
        'Normal',
      ),
      _ => (const Color(0xAA909090), const Color(0xB9CBCBCB), 'Normal'),
    };
    return Tooltip(
      message: '$label grade',
      child: Semantics(
        button: true,
        selected: selected,
        label: '$label grade',
        child: SizedBox.square(
          dimension: denseLayout ? 26 : 22,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onPressed,
            child: Center(
              child: DecoratedBox(
                decoration: ledger
                    ? BoxDecoration(
                        gradient: spec.materials.surfaceRaised,
                        borderRadius: BorderRadius.circular(2),
                        border: Border.all(
                          color: selected
                              ? const Color(0xFFD2B15A)
                              : const Color(0x8A7A5B2A),
                        ),
                      )
                    : sakura
                    ? BoxDecoration(
                        gradient: spec.materials.surfaceRaised,
                        borderRadius: BorderRadius.circular(
                          spec.geometry.buttonRadius,
                        ),
                        border: Border.all(
                          color: selected
                              ? spec.palette.primaryBright
                              : spec.palette.trim.withAlpha(158),
                        ),
                      )
                    : const BoxDecoration(),
                child: SizedBox.square(
                  dimension: denseLayout ? 26 : 22,
                  child: Center(
                    child: Container(
                      width: ledger
                          ? 11
                          : sakura
                          ? 13
                          : 16,
                      height: ledger
                          ? 11
                          : sakura
                          ? 13
                          : 16,
                      decoration: BoxDecoration(
                        color: fill,
                        borderRadius: BorderRadius.circular(
                          ledger
                              ? 1
                              : sakura
                              ? 2
                              : 3,
                        ),
                        border: Border.all(
                          color: selected
                              ? ledger
                                    ? const Color(0xFF7C5B24)
                                    : sakura
                                    ? spec.palette.primaryBright
                                    : const Color(0xFFFFF0B9)
                              : outline,
                          width: selected ? 2 : 1,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DeleteConfirmationOverlay extends StatelessWidget {
  const _DeleteConfirmationOverlay({required this.controller});

  final RecipeBookController controller;

  @override
  Widget build(BuildContext context) {
    final spec = context.visualTheme;
    final count = controller.selectedForDeletionCount;
    final names = controller.selectedForDeletion.toList()..sort();
    return Stack(
      children: <Widget>[
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: controller.deletionInProgress
                ? null
                : controller.cancelDeleteConfirmation,
            child: ColoredBox(
              color: Color.alphaBlend(
                spec.palette.canvasDeep.withAlpha(188),
                spec.materials.modalScrim,
              ),
            ),
          ),
        ),
        DraggableOverlaySurface(
          overlayId: 'recipe-delete-confirmation',
          child: SizedBox(
            key: RecipeBookKeys.r20Confirmation,
            width: 480,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => FocusScope.of(context).requestFocus(),
              child: AppSurface(
                role: AppSurfaceRole.popup,
                tone: AppSurfaceTone.danger,
                semanticLabel: 'Confirm hiding $count processing recipes',
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    DraggableOverlayDragRegion(
                      key: RecipeBookKeys.confirmationDragRegion,
                      child: Text(
                        'Hide $count processing ${count == 1 ? 'recipe' : 'recipes'}?',
                        style: spec.typography.section,
                      ),
                    ),
                    const SizedBox(height: 7),
                    Text(
                      names.take(5).join(', ') +
                          (names.length > 5
                              ? ' and ${names.length - 5} more'
                              : ''),
                      style: spec.typography.body,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'The shared cleanup transaction will remove associated mode state. You can undo immediately after it completes.',
                      style: spec.typography.meta,
                    ),
                    if (controller.deletionError case final error?) ...<Widget>[
                      const SizedBox(height: 8),
                      Semantics(
                        liveRegion: true,
                        child: Text(
                          error,
                          style: spec.typography.meta.copyWith(
                            color: spec.palette.danger,
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 14),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: <Widget>[
                        AppButton.label(
                          'Cancel',
                          key: RecipeBookKeys.r20Cancel,
                          onPressed: controller.deletionInProgress
                              ? null
                              : controller.cancelDeleteConfirmation,
                        ),
                        const SizedBox(width: 8),
                        AppButton.label(
                          controller.deletionInProgress
                              ? 'Hiding $count...'
                              : 'Hide $count',
                          key: RecipeBookKeys.r20Confirm,
                          role: AppButtonRole.danger,
                          minimumSize: const Size(112, 38),
                          onPressed: controller.deletionInProgress
                              ? null
                              : controller.confirmDeleteSelection,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _RecipeBookScrollBehavior extends AppScrollBehavior {
  const _RecipeBookScrollBehavior();

  @override
  Widget buildScrollbar(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) => child;

  @override
  Set<PointerDeviceKind> get dragDevices => <PointerDeviceKind>{
    ...super.dragDevices,
    PointerDeviceKind.mouse,
  };
}

String _recipeTypeLabel(String type) => switch (type.trim().toLowerCase()) {
  'alchemy' => 'Residence Alchemy',
  'simple_alchemy' => 'Simple Alchemy',
  'cooking' => 'Residence Cooking',
  'simple_cooking' => 'Simple Cooking',
  'processing' => 'Processing',
  _ => 'Base Item',
};

String _recipeProductionMethodLabel(Recipe recipe) {
  final method = recipe.method?.trim();
  if (method != null && method.isNotEmpty) return method;
  return _recipeTypeLabel(recipe.type);
}
