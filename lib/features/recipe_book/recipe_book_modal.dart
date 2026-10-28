import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import 'package:flutter/services.dart';

import '../../data/catalog/catalog_repository.dart';
import '../../domain/formatting/planner_formatters.dart';
import '../../domain/market/recipe_profitability.dart';
import '../../domain/models/catalog_models.dart';
import '../../domain/models/craft_mode.dart';
import '../../shared/overlays/anchored_popover.dart';
import '../../shared/overlays/draggable_overlay_surface.dart';
import '../../visual/components/app_interaction_frame.dart';
import '../../visual/visual.dart';
import '../planner/planner_contracts.dart';
import '../planner/planner_map_quick_lookup.dart';
import '../shared/recipe_variant_selector.dart';
import '../shared/workshop_presentation.dart';
import 'recipe_book_controller.dart';
import 'recipe_book_item_info.dart';
import 'recipe_book_item_info_view.dart';
import 'recipe_book_keys.dart';
import 'recipe_book_models.dart';
import 'recipe_book_usage.dart';
import 'recipe_book_used_in_panel.dart';
import 'recipe_ingredient_line.dart';

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
  RecipeBookActivation? _handledRouteActivation;

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
    final activation = widget.controller.lastRouteActivation;
    if (activation != null && !identical(activation, _handledRouteActivation)) {
      _handledRouteActivation = activation;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) widget.onActivated(activation);
      });
    }
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

  void _activate(String name, CraftMode mode) {
    final activation = widget.controller.activateInMode(name, mode);
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

  void _openPreview(String name, Offset anchorGlobal, CraftMode mode) {
    _previewAnchorGlobal = anchorGlobal;
    widget.controller.openPreview(name, mode: mode);
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
                                  controller:
                                      widget.controller.previewController,
                                  externalActions: widget.externalActions,
                                  recipeName: widget.controller.previewName!,
                                  anchorGlobal: _previewAnchorGlobal,
                                  closeFocus: _previewCloseFocus,
                                  onActivate: (name) => _activate(
                                    name,
                                    widget
                                        .controller
                                        .previewController
                                        .modeController
                                        .mode,
                                  ),
                                  onMethodChanged: (mode) =>
                                      widget.controller.openPreview(
                                        widget.controller.previewName!,
                                        mode: mode,
                                      ),
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
  final void Function(String, CraftMode) onActivate;
  final bool Function(RecipeBookUseEntry, String?) onActivateUsedIn;
  final void Function(String name, Offset anchorGlobal, CraftMode mode)
  onPreview;

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
  final void Function(String, CraftMode) onActivate;
  final bool Function(RecipeBookUseEntry, String?) onActivateUsedIn;
  final void Function(String name, Offset anchorGlobal, CraftMode mode)
  onPreview;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final compactBonus =
          controller.callingContext == RecipeBookCallingContext.bonus &&
          snapshot.poolCount <= 6;
      final textScale = MediaQuery.textScalerOf(context).scale(16) / 16;
      final preferredWidth = switch (controller.density) {
        RecipeBookDensity.sixByFive => 320.0,
        RecipeBookDensity.fiveByFour => 370.0,
        RecipeBookDensity.fourByThree => 410.0,
      };
      final columns = (constraints.maxWidth / (preferredWidth * textScale))
          .floor()
          .clamp(1, controller.density.columns);
      final fittedMetrics = _RecipeCardMetrics(
        cardWidth: (constraints.maxWidth / columns - 12).clamp(0, 560),
      );
      final scrollView = CustomScrollView(
        controller: scrollController,
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        semanticChildCount: snapshot.entries.length,
        scrollCacheExtent: ScrollCacheExtent.pixels(360 * textScale),
        slivers: [
          SliverList.builder(
            itemCount: (snapshot.entries.length + columns - 1) ~/ columns,
            addSemanticIndexes: false,
            itemBuilder: (context, row) => Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var column = 0; column < columns; column++)
                  Expanded(
                    child: row * columns + column >= snapshot.entries.length
                        ? const SizedBox.shrink()
                        : Builder(
                            builder: (context) {
                              final index = row * columns + column;
                              final entry = snapshot.entries[index];
                              final mode =
                                  entry.mode ?? controller.modeController.mode;
                              return IndexedSemantics(
                                index: index,
                                child: Padding(
                                  padding: EdgeInsets.all(fittedMetrics.margin),
                                  child: Align(
                                    alignment: compactBonus
                                        ? Alignment.topCenter
                                        : Alignment.topLeft,
                                    heightFactor: 1,
                                    child: SizedBox(
                                      width: fittedMetrics.cardWidth,
                                      child: _RecipeCard(
                                        key:
                                            entry.mode ==
                                                controller.modeController.mode
                                            ? RecipeBookKeys.card(entry.name)
                                            : ValueKey(
                                                'recipe-card:${entry.mode?.key}:${entry.name}',
                                              ),
                                        controller: controller
                                            .controllerForMode(mode),
                                        entry: entry,
                                        metrics: fittedMetrics,
                                        onActivate: (name) =>
                                            onActivate(name, mode),
                                        onActivateUsedIn: onActivateUsedIn,
                                        onPreview: (name, anchor) =>
                                            onPreview(name, anchor, mode),
                                      ),
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                  ),
              ],
            ),
          ),
        ],
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
    final reference = isBrowsableRecipeBookReference(entry.recipe);
    final deleteMode = controller.deleteSelectionMode;
    final displayedRecipe = controller.recipeFor(entry.name) ?? entry.recipe;
    final activeName =
        controller.callingContext == RecipeBookCallingContext.bonus
        ? controller.modeController.state.value.bonusTarget
        : controller.modeController.state.value.target;
    final active = !entry.hidden && _sameRecipeName(entry.name, activeName);
    final actionLabel = entry.hidden
        ? controller.restoringHiddenName == entry.name
              ? 'Restoring...'
              : 'Restore'
        : deleteMode
        ? entry.selectedForDeletion
              ? 'Selected'
              : 'Select'
        : 'Target';
    final target = reference
        ? Padding(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 8),
            child: Text('Reference', style: spec.typography.meta),
          )
        : AppTextAction(
            fontSize: 14,
            key: entry.hidden
                ? RecipeBookKeys.r27RestoreHidden(entry.name)
                : deleteMode
                ? RecipeBookKeys.r19DeleteSelection(entry.name)
                : RecipeBookKeys.r11Target(entry.name),
            selected: active || entry.selectedForDeletion,
            semanticLabel: entry.hidden
                ? 'Restore ${entry.name}'
                : '$actionLabel ${entry.name}',
            onPressed: entry.hidden && controller.restoringHiddenName != null
                ? null
                : entry.hidden
                ? () => controller.restoreHiddenItem(entry.name)
                : _cardAction,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                AppVectorGlyph(
                  entry.hidden
                      ? 'reset'
                      : deleteMode
                      ? entry.selectedForDeletion
                            ? 'check'
                            : 'add'
                      : 'target',
                  size: 14,
                ),
                const SizedBox(width: 4),
                Text(actionLabel),
              ],
            ),
          );
    return Semantics(
      container: true,
      selected: entry.selectedForDeletion,
      label: entry.hidden
          ? '${entry.name} hidden recipe card'
          : '${entry.name} recipe card',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: entry.hidden ? null : _cardAction,
        child: AppInteractionFrame(
          enabled: !entry.hidden || controller.restoringHiddenName == null,
          selected: active || entry.selectedForDeletion,
          radius: 7,
          child: DecoratedBox(
            key: ValueKey('recipe-soft-card:${entry.name}'),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color.lerp(
                    spec.palette.surface,
                    active ? spec.palette.trim : spec.palette.surfaceRaised,
                    active ? .18 : .12,
                  )!,
                  Color.lerp(
                    spec.palette.surface,
                    spec.palette.surfaceInset,
                    .3,
                  )!,
                ],
              ),
              borderRadius: BorderRadius.circular(7),
              border: entry.selectedForDeletion || entry.hidden
                  ? Border.all(
                      color: entry.selectedForDeletion
                          ? spec.palette.danger
                          : spec.palette.warning,
                    )
                  : null,
              boxShadow: [
                BoxShadow(
                  color: spec.palette.shadow.withValues(alpha: .12),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Padding(
              padding: metrics.padding,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      WorkshopItemMount(
                        child: RecipeBookItemIcon(
                          key: ValueKey('recipe-card-icon:${entry.name}'),
                          controller: controller,
                          name: entry.name,
                          size: metrics.iconSize,
                          anchorId: 'card:${entry.name}',
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Tooltip(
                                        message: entry.name,
                                        child: Text(
                                          entry.name,
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                          style: spec.typography.label.copyWith(
                                            fontSize: metrics.nameSize,
                                            fontWeight: FontWeight.w700,
                                            height: 1.25,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        _recipeProductionMethodLabel(
                                          displayedRecipe,
                                        ),
                                        key: RecipeBookKeys.productionMethod(
                                          entry.name,
                                        ),
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: spec.typography.meta.copyWith(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w400,
                                          height: 1.4,
                                          color: spec.palette.textMuted,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                if (!entry.hidden && !reference)
                                  AppTextAction(
                                    key: RecipeBookKeys.r12Favorite(entry.name),
                                    selected: deleteMode
                                        ? entry.selectedForDeletion
                                        : entry.favorite,
                                    color: !deleteMode && entry.favorite
                                        ? spec.palette.warning
                                        : null,
                                    semanticLabel: deleteMode
                                        ? '${entry.selectedForDeletion ? 'Deselect' : 'Select'} ${entry.name} for deletion'
                                        : '${entry.favorite ? 'Remove' : 'Add'} ${entry.name} favorite',
                                    tooltip: deleteMode
                                        ? 'Select for deletion'
                                        : 'Favorite',
                                    onPressed: deleteMode
                                        ? () => controller
                                              .toggleDeleteSelection(entry.name)
                                        : () => controller.toggleFavorite(
                                            entry.name,
                                          ),
                                    child: AppVectorGlyph(
                                      deleteMode
                                          ? entry.selectedForDeletion
                                                ? 'check'
                                                : 'add'
                                          : 'star',
                                      size: 18,
                                    ),
                                  ),
                              ],
                            ),
                            const Padding(
                              padding: EdgeInsets.only(top: 9, bottom: 8),
                              child: WorkshopSectionRule(),
                            ),
                            Transform.translate(
                              offset: const Offset(-5, 0),
                              child: Wrap(
                                key: ValueKey('recipe-actions:${entry.name}'),
                                spacing: 14,
                                runSpacing: 10,
                                children: [
                                  target,
                                  if (!deleteMode)
                                    Builder(
                                      builder: (buttonContext) => AppTextAction(
                                        fontSize: 14,
                                        key: RecipeBookKeys.r13Details(
                                          entry.name,
                                        ),
                                        semanticLabel: 'Preview ${entry.name}',
                                        tooltip: 'Preview ingredients',
                                        onPressed: () {
                                          final box = buttonContext
                                              .findRenderObject();
                                          final anchor = box is RenderBox
                                              ? box.localToGlobal(
                                                  box.size.center(Offset.zero),
                                                )
                                              : Offset.zero;
                                          onPreview(entry.name, anchor);
                                        },
                                        child: const Text('Details'),
                                      ),
                                    ),
                                  if (!deleteMode && entry.usedInCount > 0)
                                    AnchoredPopover(
                                      overlayId:
                                          'recipe-book-used-in:${entry.name}',
                                      preferredWidth: 570,
                                      maximumHeight: itemReferenceCardHeight(
                                        context,
                                      ),
                                      alignEnd: true,
                                      placement:
                                          AnchoredPopoverPlacement.beside,
                                      consumeOutsideTap: true,
                                      anchorBuilder:
                                          (
                                            context,
                                            toggle,
                                            isShowing,
                                          ) => AppTextAction(
                                            fontSize: 14,
                                            key: RecipeBookKeys.usedIn(
                                              entry.name,
                                            ),
                                            selected: isShowing,
                                            semanticLabel:
                                                '${entry.name} is used in ${entry.usedInCount} recipe ${entry.usedInCount == 1 ? 'path' : 'paths'}',
                                            tooltip:
                                                'Used in ${entry.usedInCount} recipe ${entry.usedInCount == 1 ? 'path' : 'paths'}',
                                            onPressed: toggle,
                                            child: Text(
                                              'Used for ${entry.usedInCount}',
                                            ),
                                          ),
                                      popoverBuilder: (context, close) =>
                                          RecipeBookUsedInPanel(
                                            controller: controller,
                                            sourceName: entry.name,
                                            snapshot: controller.usedInFor(
                                              entry.name,
                                            ),
                                            onClose: close,
                                            onActivate: onActivateUsedIn,
                                          ),
                                    ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  if (entry.hidden ||
                      entry.profitability != null ||
                      controller.showsMarketStockFor(entry.name)) ...[
                    const SizedBox(height: 10),
                    Padding(
                      padding: EdgeInsets.only(left: metrics.iconSize + 16),
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        children: [
                          if (entry.hidden) const _HiddenRecipePill(),
                          if (!entry.hidden && entry.profitability != null)
                            _RecipeBookProfitabilityPill(
                              key: RecipeBookKeys.profitPill(entry.name),
                              quote: entry.profitability!,
                              compact: false,
                            ),
                          if (!entry.hidden &&
                              controller.showsMarketStockFor(entry.name))
                            _RecipeBookStockPill(stock: entry.marketStock),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
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
  const _RecipeBookStockPill({required this.stock});

  final double? stock;
  @override
  Widget build(BuildContext context) {
    final spec = context.visualTheme;
    return Tooltip(
      message: stock == null
          ? 'Stock has not been checked.'
          : '${formatQuantity(stock!)} listed on the Central Market.',
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: spec.palette.surfaceRaised.withAlpha(86),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: spec.palette.textMuted.withAlpha(165)),
        ),
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 7, vertical: 3),
          child: Text(
            stock == null ? 'Stock —' : 'Stock ${formatQuantity(stock!)}',
            style: spec.typography.meta.copyWith(
              color: spec.palette.text,
              fontSize: 10.5,
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
  const _RecipeCardMetrics({required this.cardWidth});
  final double cardWidth;
  final double iconSize = 50;
  final double margin = 6;
  final EdgeInsets padding = const EdgeInsets.symmetric(
    horizontal: 15,
    vertical: 17,
  );
  final double nameSize = 18;
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
    required this.onMethodChanged,
  });

  final RecipeBookController controller;
  final PlannerExternalActions? externalActions;
  final String recipeName;
  final Offset? anchorGlobal;
  final FocusNode closeFocus;
  final ValueChanged<String> onActivate;
  final ValueChanged<CraftMode> onMethodChanged;

  @override
  Widget build(BuildContext context) {
    final spec = context.visualTheme;
    final recipe = controller.recipeFor(recipeName);
    if (recipe == null) return const SizedBox.shrink();
    final hidden = controller.isHiddenRecipe(recipeName);
    final methods = {
      for (final route in controller.previewRoutesFor(recipeName))
        route.mode: route.label,
    };
    final previewAction = isBrowsableRecipeBookReference(recipe)
        ? Semantics(
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
                        const AppVectorGlyph('book', size: 13),
                        const SizedBox(width: 5),
                        Text(
                          'Reference',
                          style: spec.typography.label.copyWith(
                            color: spec.palette.textMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          )
        : SizedBox(
            key: hidden
                ? RecipeBookKeys.r27RestoreHidden('$recipeName:preview')
                : RecipeBookKeys.r11Target('$recipeName:preview'),
            width: 95,
            height: 38,
            child: AppButton(
              role: hidden ? AppButtonRole.secondary : AppButtonRole.primary,
              minimumSize: Size.zero,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              onPressed: hidden && controller.restoringHiddenName != null
                  ? null
                  : hidden
                  ? () => controller.restoreHiddenItem(recipeName)
                  : () => onActivate(recipeName),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    AppVectorGlyph(hidden ? 'reset' : 'target', size: 13),
                    const SizedBox(width: 5),
                    Text(hidden ? 'Restore' : 'Target'),
                  ],
                ),
              ),
            ),
          );
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
        // Reading previews can outgrow the book beneath them. Keep their
        // content-sized layout, but use the viewport before adding scrolling.
        final availableHeight = (constraints.maxHeight - 32).clamp(
          0.0,
          double.infinity,
        );
        final panelHeight =
            (123 +
                    (methods.length > 1
                        ? 48 *
                              MediaQuery.textScalerOf(
                                context,
                              ).scale(1).clamp(1, 2)
                        : 0) +
                    (recipe.hasRecipeVariants ? 39 : 0) +
                    (recipe.ingredients.isEmpty
                            ? 1
                            : recipe.ingredients.length) *
                        72)
                .clamp(0.0, availableHeight)
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
                child: RepaintBoundary(
                  key: const ValueKey('recipe-preview-render'),
                  child: GestureDetector(
                    key: RecipeBookKeys.previewPanel,
                    behavior: HitTestBehavior.opaque,
                    onTap: () => FocusScope.of(context).requestFocus(),
                    child: AppSurface(
                      role: AppSurfaceRole.modal,
                      padding: const EdgeInsets.all(14),
                      clipBehavior: Clip.antiAlias,
                      semanticLabel: '$recipeName recipe preview',
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          maxHeight: (availableHeight - 28).clamp(
                            0.0,
                            double.infinity,
                          ),
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: <Widget>[
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: <Widget>[
                                RecipeBookItemIcon(
                                  controller: controller,
                                  name: recipeName,
                                  size: ItemDetailStyle.headerIcon,
                                  anchorId: 'preview:$recipeName',
                                ),
                                const SizedBox(width: ItemDetailStyle.itemGap),
                                Expanded(
                                  child: DraggableOverlayDragRegion(
                                    key: RecipeBookKeys.previewDragRegion,
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: <Widget>[
                                        Text(
                                          recipeName,
                                          style: ItemDetailStyle.title(spec),
                                        ),
                                        const SizedBox(height: 6),
                                        Wrap(
                                          spacing: 8,
                                          runSpacing: 4,
                                          crossAxisAlignment:
                                              WrapCrossAlignment.center,
                                          children: [
                                            Text(
                                              _recipeProductionMethodLabel(
                                                recipe,
                                              ),
                                              style: ItemDetailStyle.meta(spec),
                                            ),
                                            Text(
                                              '${controller.isEstimatedOutput(recipe.name) ? 'Estimated output' : 'Output'} ${_previewOutput(recipe)}',
                                              style: ItemDetailStyle.meta(spec)
                                                  .copyWith(
                                                    color:
                                                        ItemDetailStyle.accent(
                                                          spec,
                                                        ),
                                                  ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                                if (hidden) ...<Widget>[
                                  const _HiddenRecipePill(),
                                  const SizedBox(width: 8),
                                ],
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    AppButton(
                                      key: RecipeBookKeys.r14ClosePreview(
                                        recipeName,
                                      ),
                                      focusNode: closeFocus,
                                      role: ledger
                                          ? AppButtonRole.primary
                                          : AppButtonRole.optionPill,
                                      minimumSize: const Size.square(30),
                                      padding: EdgeInsets.zero,
                                      semanticLabel:
                                          'Close $recipeName preview',
                                      tooltip: 'Close preview',
                                      onPressed: controller.closePreview,
                                      child: const AppVectorGlyph(
                                        'close',
                                        size: 11,
                                      ),
                                    ),
                                    const SizedBox(height: 10),
                                    previewAction,
                                  ],
                                ),
                              ],
                            ),
                            if (methods.length > 1) ...<Widget>[
                              const SizedBox(height: 10),
                              Wrap(
                                spacing: 6,
                                runSpacing: 6,
                                children: [
                                  for (final entry in methods.entries)
                                    AppFilterButton(
                                      key: ValueKey(
                                        'recipe-method:${entry.key.key}:$recipeName',
                                      ),
                                      label: entry.value,
                                      selected:
                                          entry.key ==
                                          controller.modeController.mode,
                                      onChanged: (_) =>
                                          onMethodChanged(entry.key),
                                    ),
                                ],
                              ),
                            ],
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
                            const SizedBox(height: 24),
                            Text(
                              'Ingredients',
                              key: const ValueKey(
                                'recipe-preview-ingredients-heading',
                              ),
                              style: ItemDetailStyle.section(spec),
                            ),
                            const SizedBox(height: 12),
                            Flexible(
                              child: recipe.ingredients.isEmpty
                                  ? Center(
                                      child: Text(
                                        'No recipe ingredients recorded.',
                                        style: spec.typography.body,
                                      ),
                                    )
                                  : ListView.separated(
                                      shrinkWrap: true,
                                      padding: const EdgeInsets.only(bottom: 4),
                                      itemCount: recipe.ingredients.length,
                                      separatorBuilder: (_, _) => Divider(
                                        height: 12,
                                        thickness: 1,
                                        color: spec.palette.trim.withValues(
                                          alpha: .2,
                                        ),
                                      ),
                                      itemBuilder: (context, index) =>
                                          _PreviewIngredientRow(
                                            controller: controller,
                                            externalActions: externalActions,
                                            parentName: recipeName,
                                            ingredient:
                                                recipe.ingredients[index],
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
              ),
            ),
          ],
        );
      },
    );
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
    final row = RecipeIngredientLine(
      semanticLabel: '$selected preview ingredient',
      name: selected,
      quantity: ingredient.quantity * ratio,
      quantityKey: RecipeBookKeys.previewQuantity(parentName, ingredient.name),
      icon: RecipeBookItemIcon(
        controller: controller,
        name: selected,
        size: ItemDetailStyle.ingredientIcon,
        anchorId: 'preview:$parentName:ingredient:$ingredientIndex:$selected',
      ),
      nameControl: options.length > 1
          ? AppSelect<String>(
              key: RecipeBookKeys.r15Substitute(parentName, ingredient.name),
              inline: true,
              value: selected,
              items: options,
              labelFor: (value) => value,
              semanticLabel: 'Substitute for ${ingredient.name} in $parentName',
              onChanged: (value) {
                if (value == null) return;
                controller.selectSubstitute(
                  parentName: parentName,
                  ingredient: ingredient,
                  selection: value,
                );
              },
            )
          : null,
      controls: [
        for (final grade in grades) ...<Widget>[
          _PreviewQualitySwatch(
            key: RecipeBookKeys.r16Quality(parentName, ingredient.name, grade),
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
      resolveGatherDemand: () => PlannerGatherDemand(
        sourceId:
            'recipe-book:${controller.modeController.mode.key}:$parentName:$ingredientIndex',
        sourceLabel: parentName,
        materialName: selected,
        neededQuantity: ingredient.quantity * ratio,
      ),
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
