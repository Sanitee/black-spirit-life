import 'dart:async';
import 'dart:math' as math;

import 'package:bdo_craft_planner_flutter/visual/components/app_tooltip.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../domain/catalog/temporarily_archived_items.dart';
import '../../domain/models/catalog_models.dart';
import '../../domain/models/craft_mode.dart';
import '../../shared/overlays/anchored_popover.dart';
import '../../visual/visual.dart';
import '../shared/mode_item_icon.dart';
import '../shared/workshop_presentation.dart';
import 'recipe_book_controller.dart';
import 'recipe_book_item_info.dart';
import 'recipe_book_keys.dart';
import 'recipe_book_preview_routes.dart';

/// The Recipe Book's reference preview, without taking over its child's clicks.
class RecipeBookItemInfoHover extends StatelessWidget {
  const RecipeBookItemInfoHover({
    required this.controller,
    required this.name,
    required this.child,
    this.mode,
    this.info,
    this.referenceIcon,
    this.interactivePreview = true,
    super.key,
  });

  final RecipeBookController controller;
  final String name;
  final Widget child;
  final CraftMode? mode;
  final RecipeBookItemInfo? info;
  final Widget? referenceIcon;
  final bool interactivePreview;

  @override
  Widget build(BuildContext context) {
    final itemMode = mode ?? controller.modeController.mode;
    final info = this.info ?? controller.itemInfoFor(name, mode: itemMode);
    if (info == null || !info.hasBody) return child;
    return _RecipeBookItemInfoTooltip(
      controller: controller,
      name: name,
      mode: itemMode,
      info: info,
      referenceIcon: referenceIcon,
      interactivePreview: interactivePreview,
      triggerMode: TooltipTriggerMode.manual,
      child: child,
    );
  }
}

class _RecipeBookItemInfoTooltip extends StatelessWidget {
  const _RecipeBookItemInfoTooltip({
    required this.controller,
    required this.name,
    required this.mode,
    required this.info,
    required this.child,
    this.triggerMode,
    this.referenceIcon,
    this.interactivePreview = true,
  });

  final RecipeBookController controller;
  final String name;
  final CraftMode mode;
  final RecipeBookItemInfo info;
  final Widget child;
  final TooltipTriggerMode? triggerMode;
  final Widget? referenceIcon;
  final bool interactivePreview;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final width = itemReferenceCardWidth(context);
    // The panel scales its own text. Do not also scale the entire WidgetSpan,
    // which would double-enlarge the card and push it outside the viewport.
    return MediaQuery(
      data: media.copyWith(textScaler: TextScaler.noScaling),
      child: AppTooltip(
        // The user requested rich reference previews on item artwork only.
        approvedHover: true,
        triggerMode: triggerMode,
        waitDuration: const Duration(milliseconds: 350),
        showDuration: const Duration(seconds: 12),
        exitDuration: const Duration(milliseconds: 300),
        preferBelow: false,
        ignorePointer: !interactivePreview,
        decoration: BoxDecoration(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(6),
        ),
        padding: EdgeInsets.zero,
        constraints: BoxConstraints(maxWidth: width),
        richMessage: WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: MediaQuery(
            data: media,
            child: ItemReferenceCard(
              key: RecipeBookKeys.itemInfo(name),
              controller: controller,
              mode: mode,
              name: name,
              info: info,
              maxWidth: width,
              spec: context.visualTheme,
              icon: referenceIcon,
            ),
          ),
        ),
        child: MediaQuery(data: media, child: child),
      ),
    );
  }
}

double itemReferenceCardWidth(BuildContext context) =>
    ItemDetailStyle.width(context);

double itemReferenceCardHeight(BuildContext context) {
  final overlay = Overlay.maybeOf(context)?.context.findRenderObject();
  final screenHeight = MediaQuery.sizeOf(context).height;
  final available = overlay is RenderBox && overlay.hasSize
      ? math.min(screenHeight, overlay.size.height)
      : screenHeight;
  return (available - 32).clamp(0.0, double.infinity);
}

double _itemInfoSpacing(BuildContext context, double value) =>
    value * (MediaQuery.textScalerOf(context).scale(14) / 14).clamp(1.0, 1.5);

// Accents must remain readable on every theme's raised reading surface.
Color _referenceAccent(ThemeSpec spec) {
  return ItemDetailStyle.accent(spec);
}

List<RecipeBookFormula> _distinctReferenceFormulas(
  Iterable<RecipeBookFormula> formulas,
) {
  final seen = <String>{};
  return formulas
      .where((formula) => seen.add(recipeBookPreviewFormulaIdentity(formula)))
      .toList(growable: false);
}

class RecipeBookItemIcon extends StatefulWidget {
  const RecipeBookItemIcon({
    required this.controller,
    required this.name,
    required this.size,
    required this.anchorId,
    this.mode,
    super.key,
  });

  final RecipeBookController controller;
  final String name;
  final double size;
  final String anchorId;
  final CraftMode? mode;

  @override
  State<RecipeBookItemIcon> createState() => _RecipeBookItemIconState();
}

class _RecipeBookItemIconState extends State<RecipeBookItemIcon> {
  late final FocusNode _focusNode = FocusNode(
    debugLabel: 'RecipeBookItemIcon(${widget.anchorId}:${widget.name})',
  );

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final name = widget.name;
    final anchorId = widget.anchorId;
    final itemMode = widget.mode ?? controller.modeController.mode;
    final itemModeController = controller.modeController.owner.modes[itemMode]!;
    final icon = ModeItemIcon(
      controller: itemModeController,
      catalogRepository: controller.catalogRepository,
      name: name,
      size: widget.size,
    );
    final info = controller.itemInfoFor(name, mode: itemMode);
    if (info == null || !info.hasBody) return icon;
    final spec = context.visualTheme;
    final panelWidth = itemReferenceCardWidth(context);
    return AnchoredPopover(
      overlayId: 'recipe-book-item-info:$anchorId:$name',
      preferredWidth: panelWidth,
      maximumHeight: itemReferenceCardHeight(context),
      alignEnd: false,
      placement: AnchoredPopoverPlacement.beside,
      consumeOutsideTap: true,
      anchorBuilder: (context, toggle, isShowing) => Semantics(
        button: true,
        label: isShowing
            ? 'Close pinned information for $name'
            : 'Pin information for $name',
        child: FocusableActionDetector(
          focusNode: _focusNode,
          mouseCursor: SystemMouseCursors.click,
          shortcuts: const <ShortcutActivator, Intent>{
            SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
            SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
          },
          actions: <Type, Action<Intent>>{
            ActivateIntent: CallbackAction<ActivateIntent>(
              onInvoke: (_) {
                toggle();
                return null;
              },
            ),
          },
          child: GestureDetector(
            key: RecipeBookKeys.itemInfoAnchor(name, anchorId),
            behavior: HitTestBehavior.opaque,
            onTapDown: (_) => _focusNode.requestFocus(),
            onTap: toggle,
            child: TooltipVisibility(
              visible: !isShowing,
              child: _RecipeBookItemInfoTooltip(
                controller: controller,
                name: name,
                mode: itemMode,
                info: info,
                child: icon,
              ),
            ),
          ),
        ),
      ),
      popoverBuilder: (context, close) => ItemReferenceCard(
        key: RecipeBookKeys.pinnedItemInfo(name, anchorId),
        controller: controller,
        mode: itemMode,
        name: name,
        info: info,
        maxWidth: panelWidth,
        spec: spec,
        onClose: close,
        closeKey: RecipeBookKeys.closePinnedItemInfo(name, anchorId),
      ),
    );
  }
}

/// One item-reference surface for previews and pinned views in every workspace.
class ItemReferenceCard extends StatefulWidget {
  const ItemReferenceCard({
    required this.controller,
    required this.mode,
    required this.name,
    required this.info,
    required this.maxWidth,
    required this.spec,
    this.onClose,
    this.closeKey,
    this.headerDragKey,
    this.onCopyItemName,
    this.onUseFormula,
    this.icon,
    super.key,
  });

  final RecipeBookController controller;
  final CraftMode mode;
  final String name;
  final RecipeBookItemInfo info;
  final double maxWidth;
  final ThemeSpec spec;
  final VoidCallback? onClose;
  final Key? closeKey;
  final Key? headerDragKey;
  final ValueChanged<String>? onCopyItemName;
  final ValueChanged<RecipeBookFormula>? onUseFormula;
  final Widget? icon;

  @override
  State<ItemReferenceCard> createState() => _ItemReferenceCardState();
}

class _ItemReferenceCardState extends State<ItemReferenceCard> {
  // A preview must not restore the enclosing recipe's saved scroll position.
  final _scrollController = ScrollController(keepScrollOffset: false);

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final mode = widget.mode;
    final name = widget.name;
    final info = withReadableRecipeBookSections(widget.info);
    final maxWidth = widget.maxWidth;
    final spec = widget.spec;
    final onClose = widget.onClose;
    final closeKey = widget.closeKey;
    final heading = ItemDetailStyle.title(spec);
    final meta = ItemDetailStyle.meta(spec);
    final body = ItemDetailStyle.body(spec);
    final maxHeight = itemReferenceCardHeight(context);
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth, maxHeight: maxHeight),
      child: _ItemReferenceCopyScope(
        onCopyItemName: widget.onCopyItemName,
        onRecipeActivated: onClose,
        onUseFormula: widget.onUseFormula,
        child: AppSurface(
          role: AppSurfaceRole.tooltip,
          tone: AppSurfaceTone.info,
          padding: const EdgeInsets.all(16),
          child: ScrollConfiguration(
            behavior: const _RecipeBookItemInfoScrollBehavior(),
            child: SingleChildScrollView(
              controller: _scrollController,
              primary: false,
              physics: const ClampingScrollPhysics(),
              child: _ReferenceSelection(
                enabled: onClose != null,
                child: DefaultTextStyle(
                  style: body,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          WorkshopItemMount(
                            child:
                                widget.icon ??
                                ModeItemIcon(
                                  controller: controller
                                      .modeController
                                      .owner
                                      .modes[mode]!,
                                  catalogRepository:
                                      controller.catalogRepository,
                                  name: name,
                                  size: ItemDetailStyle.headerIcon,
                                  searchAcrossModes: true,
                                ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: AnchoredPopoverDragRegion(
                              key: widget.headerDragKey,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: <Widget>[
                                  _ReferenceItemName(
                                    name: name,
                                    label: info.title,
                                    style: heading,
                                  ),
                                  SizedBox(
                                    height: _itemInfoSpacing(context, 6),
                                  ),
                                  Text(info.kind, style: meta),
                                ],
                              ),
                            ),
                          ),
                          if (onClose != null) ...<Widget>[
                            const SizedBox(width: 8),
                            AppButton(
                              key: closeKey,
                              role: AppButtonRole.optionPill,
                              minimumSize: const Size.square(30),
                              padding: EdgeInsets.zero,
                              semanticLabel: 'Close $name information',
                              tooltip: 'Close information',
                              onPressed: onClose,
                              child: const AppVectorGlyph('close', size: 9),
                            ),
                          ],
                        ],
                      ),
                      ..._itemReferenceSectionWidgets(
                        context,
                        controller: controller,
                        mode: mode,
                        name: name,
                        info: info,
                        spec: spec,
                      ),
                      if (info.summary.trim().isEmpty &&
                          info.effects.isEmpty &&
                          info.acquisitionFormulas.isEmpty &&
                          info.acquisitionNotes.isEmpty &&
                          info.uses.isEmpty &&
                          info.craftUses.isEmpty &&
                          info.notes.isEmpty) ...[
                        SizedBox(height: _itemInfoSpacing(context, 20)),
                        Text('No source details recorded yet.', style: body),
                      ],
                    ],
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

/// The same structured item facts used by hover and pinned reference cards,
/// without adding a second header, surface, scroll view or empty-state copy.
class ItemReferenceSections extends StatelessWidget {
  const ItemReferenceSections({
    required this.controller,
    required this.mode,
    required this.name,
    required this.info,
    required this.spec,
    this.onCopyItemName,
    this.onRecipeActivated,
    this.onUseFormula,
    super.key,
  });

  final RecipeBookController controller;
  final CraftMode mode;
  final String name;
  final RecipeBookItemInfo info;
  final ThemeSpec spec;
  final ValueChanged<String>? onCopyItemName;

  /// Dismiss the enclosing view before the existing recipe activation runs.
  final VoidCallback? onRecipeActivated;

  /// Hosts with their own navigation may route the action instead of invoking
  /// the reference controller. The default close-then-activate path is retained
  /// when no override is provided.
  final ValueChanged<RecipeBookFormula>? onUseFormula;

  @override
  Widget build(BuildContext context) {
    final children = _itemReferenceSectionWidgets(
      context,
      controller: controller,
      mode: mode,
      name: name,
      info: withReadableRecipeBookSections(info),
      spec: spec,
    );
    if (children.isEmpty) return const SizedBox.shrink();
    final inherited = context
        .dependOnInheritedWidgetOfExactType<_ItemReferenceCopyScope>();
    return _ItemReferenceCopyScope(
      onCopyItemName: onCopyItemName ?? inherited?.onCopyItemName,
      onRecipeActivated: onRecipeActivated ?? inherited?.onRecipeActivated,
      onUseFormula: onUseFormula ?? inherited?.onUseFormula,
      child: DefaultTextStyle(
        style: ItemDetailStyle.body(spec),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: children,
        ),
      ),
    );
  }
}

List<Widget> _itemReferenceSectionWidgets(
  BuildContext context, {
  required RecipeBookController controller,
  required CraftMode mode,
  required String name,
  required RecipeBookItemInfo info,
  required ThemeSpec spec,
}) {
  final body = ItemDetailStyle.body(spec);
  final accent = body.copyWith(
    color: _referenceAccent(spec),
    fontWeight: FontWeight.w500,
  );
  return <Widget>[
    if (info.summary.trim().isNotEmpty) ...<Widget>[
      SizedBox(height: _itemInfoSpacing(context, 24)),
      _InfoSectionHeading(title: 'Description', spec: spec),
      SizedBox(height: _itemInfoSpacing(context, 8)),
      Text(info.summary, style: body),
    ],
    if (info.effects.isNotEmpty)
      _InfoSection(
        title: info.effectsTitle,
        values: info.effects,
        style: accent,
      ),
    if (info.acquisitionNotes.isNotEmpty)
      _InfoSection(
        title: 'How to Obtain',
        values: info.acquisitionNotes,
        style: body,
      ),
    if (info.acquisitionFormulas.isNotEmpty)
      _FormulaSection(
        controller: controller,
        mode: mode,
        title: 'Recipe & materials',
        formulas: info.acquisitionFormulas,
        style: body,
      ),
    if (info.uses.isNotEmpty || info.craftUses.isNotEmpty)
      _UsedForSection(
        controller: controller,
        mode: mode,
        sourceName: name,
        values: info.uses,
        craftUses: info.craftUses,
        style: body,
      ),
    if (info.example?.trim().isNotEmpty ?? false)
      _InfoSection(
        title: 'Example',
        values: <String>[info.example!.trim()],
        style: body,
      ),
    if (info.notes.isNotEmpty)
      _InfoSection(title: 'Notes', values: info.notes, style: body),
  ];
}

class _ReferenceSelection extends StatelessWidget {
  const _ReferenceSelection({required this.enabled, required this.child});
  final bool enabled;
  final Widget child;

  @override
  Widget build(BuildContext context) =>
      enabled ? SelectionArea(child: child) : child;
}

class _ItemReferenceCopyScope extends InheritedWidget {
  const _ItemReferenceCopyScope({
    required this.onCopyItemName,
    required this.onRecipeActivated,
    this.onUseFormula,
    required super.child,
  });

  final ValueChanged<String>? onCopyItemName;
  final VoidCallback? onRecipeActivated;
  final ValueChanged<RecipeBookFormula>? onUseFormula;

  @override
  bool updateShouldNotify(_ItemReferenceCopyScope oldWidget) =>
      onCopyItemName != oldWidget.onCopyItemName ||
      onRecipeActivated != oldWidget.onRecipeActivated ||
      onUseFormula != oldWidget.onUseFormula;
}

class _ReferenceItemName extends StatelessWidget {
  const _ReferenceItemName({
    required this.name,
    required this.style,
    this.label,
  });
  final String name;
  final TextStyle style;
  final String? label;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: 'Copy $name',
    value: label != null && label != name ? label : null,
    child: InkWell(
      key: ValueKey('item-reference-copy:$name'),
      hoverColor: Colors.transparent,
      splashFactory: NoSplash.splashFactory,
      borderRadius: BorderRadius.circular(4),
      onTap: () {
        final copy = context
            .dependOnInheritedWidgetOfExactType<_ItemReferenceCopyScope>()
            ?.onCopyItemName;
        if (copy != null) {
          copy(name);
        } else {
          unawaited(_copyReferenceName(context, name));
        }
      },
      child: ExcludeSemantics(child: Text(label ?? name, style: style)),
    ),
  );
}

Future<void> _copyReferenceName(BuildContext context, String name) async {
  try {
    await Clipboard.setData(ClipboardData(text: name));
    if (!context.mounted) return;
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(
        content: Text('Copied $name'),
        duration: const Duration(milliseconds: 1350),
      ),
    );
  } on Object {
    if (!context.mounted) return;
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      const SnackBar(content: Text('Could not copy the name. Try again.')),
    );
  }
}

class _RecipeBookItemInfoScrollBehavior extends AppScrollBehavior {
  const _RecipeBookItemInfoScrollBehavior();

  @override
  Widget buildScrollbar(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) => child;
}

class _FormulaSection extends StatelessWidget {
  const _FormulaSection({
    required this.controller,
    required this.mode,
    required this.title,
    required this.formulas,
    required this.style,
  });

  final RecipeBookController controller;
  final CraftMode mode;
  final String title;
  final List<RecipeBookFormula> formulas;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    final spec = context.visualTheme;
    final formulas = _distinctReferenceFormulas(this.formulas);
    final routeIds = formulas
        .map((formula) => (formula.routeId ?? formula.routeLabel ?? '').trim())
        .where((value) => value.isNotEmpty)
        .map((value) => value.toLowerCase())
        .toSet();
    final showRouteLabel = routeIds.length > 1;
    final showBatchLabel = formulas.any(
      (formula) => formula.batchMultiplier != 1,
    );
    return Padding(
      padding: EdgeInsets.only(top: _itemInfoSpacing(context, 20)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _InfoSectionHeading(title: title, spec: spec),
          SizedBox(height: _itemInfoSpacing(context, 8)),
          for (var index = 0; index < formulas.length; index++) ...<Widget>[
            if (index > 0) SizedBox(height: _itemInfoSpacing(context, 12)),
            _FormulaCard(
              controller: controller,
              mode: mode,
              formula: formulas[index],
              style: style,
              showRouteLabel: showRouteLabel,
              showBatchLabel: showBatchLabel,
            ),
          ],
        ],
      ),
    );
  }
}

class _FormulaCard extends StatelessWidget {
  const _FormulaCard({
    required this.controller,
    required this.mode,
    required this.formula,
    required this.style,
    required this.showRouteLabel,
    required this.showBatchLabel,
  });

  final RecipeBookController controller;
  final CraftMode mode;
  final RecipeBookFormula formula;
  final TextStyle style;
  final bool showRouteLabel;
  final bool showBatchLabel;

  @override
  Widget build(BuildContext context) {
    final spec = context.visualTheme;
    final formulaMode = formula.mode ?? mode;
    final canActivate =
        formula.mode != null && controller.canActivateFormula(formula);
    final routeLabel = formula.routeLabel?.trim() ?? '';
    final tags = <String>[
      if (showRouteLabel && routeLabel.isNotEmpty) routeLabel,
      if (showBatchLabel) '${formula.batchMultiplier}× batch',
    ];
    final meta = spec.typography.meta.copyWith(
      color: spec.palette.textMuted,
      fontSize: 13,
      fontWeight: FontWeight.w500,
      height: 1.3,
    );
    final output = _formulaOutputLabel(formula);
    return LayoutBuilder(
      builder: (context, constraints) => Align(
        alignment: Alignment.centerLeft,
        child: SizedBox(
          width: math.min(
            constraints.maxWidth,
            _formulaContentWidth(
              context,
              controller,
              formulaMode,
              formula,
              style,
              meta,
              showUseRecipe: canActivate,
            ),
          ),
          child: Semantics(
            container: true,
            explicitChildNodes: true,
            child: ItemDetailGroup(
              key: RecipeBookKeys.itemInfoFormula(
                formula.outputName,
                formula.variantId,
                formula.batchMultiplier,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Semantics(
                    label: <String>[formula.method, ...tags, output].join(', '),
                    explicitChildNodes: true,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        Text(
                          formula.method,
                          style: style.copyWith(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        SizedBox(height: _itemInfoSpacing(context, 6)),
                        Wrap(
                          spacing: 14,
                          runSpacing: 4,
                          children: [
                            for (final tag in tags) Text(tag, style: meta),
                            _ReferenceItemName(
                              name: formula.outputName,
                              label: output,
                              style: meta.copyWith(
                                color: _referenceAccent(spec),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  SizedBox(height: _itemInfoSpacing(context, 12)),
                  for (
                    var index = 0;
                    index < formula.ingredients.length;
                    index++
                  )
                    _FormulaMaterialRow(
                      controller: controller,
                      mode: formulaMode,
                      formula: formula,
                      ingredient: formula.ingredients[index],
                      style: style,
                      topSpacing: _itemInfoSpacing(
                        context,
                        index == 0 ? 0 : 12,
                      ),
                    ),
                  if (canActivate) ...<Widget>[
                    SizedBox(height: _itemInfoSpacing(context, 14)),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: AppButton(
                        key: ValueKey<String>(
                          'item-info-use-recipe:${formulaMode.key}:'
                          '${formula.outputName}:${formula.variantId ?? 'base'}:'
                          '${formula.batchMultiplier}',
                        ),
                        role: AppButtonRole.optionPill,
                        minimumSize: const Size(0, 34),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 5,
                        ),
                        semanticLabel:
                            'Use ${formula.outputName}, ${formula.method}'
                            '${tags.isEmpty ? '' : ', ${tags.join(', ')}'}',
                        onPressed: () {
                          if (!controller.canActivateFormula(formula)) return;
                          final scope = context
                              .dependOnInheritedWidgetOfExactType<
                                _ItemReferenceCopyScope
                              >();
                          Tooltip.dismissAllToolTips();
                          final onUseFormula = scope?.onUseFormula;
                          if (onUseFormula != null) {
                            onUseFormula(formula);
                          } else {
                            scope?.onRecipeActivated?.call();
                            controller.activateFormula(formula);
                          }
                        },
                        child: const Text('Use recipe'),
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

double _formulaContentWidth(
  BuildContext context,
  RecipeBookController controller,
  CraftMode mode,
  RecipeBookFormula formula,
  TextStyle style,
  TextStyle meta, {
  required bool showUseRecipe,
}) {
  double textWidth(String value, TextStyle textStyle) {
    final painter = TextPainter(
      text: TextSpan(text: value, style: textStyle),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
      locale: Localizations.maybeLocaleOf(context),
    )..layout();
    final width = painter.width;
    painter.dispose();
    return width;
  }

  final nameStyle = style.copyWith(fontSize: 15, fontWeight: FontWeight.w600);
  final quantityStyle = style.copyWith(
    fontSize: 13,
    fontWeight: FontWeight.w500,
  );
  final alternativeStyle = style.copyWith(fontSize: 13, height: 1.35);
  var width = math.max(
    textWidth(
      formula.method,
      style.copyWith(fontSize: 15, fontWeight: FontWeight.w600),
    ),
    textWidth(_formulaOutputLabel(formula), meta),
  );
  if (showUseRecipe) {
    width = math.max(
      width,
      textWidth('Use recipe', context.visualTheme.typography.label) + 20,
    );
  }
  for (final ingredient in formula.ingredients) {
    var labelWidth = textWidth(ingredient.name, nameStyle);
    for (final alternative in _formulaAlternatives(
      ingredient,
      recipes: controller.modeController.owner.modes[mode]!.recipes,
    )) {
      labelWidth = math.max(
        labelWidth,
        textWidth(
          'or ${_displayQuantity(alternative.quantity)} ${alternative.name}',
          alternativeStyle,
        ),
      );
    }
    width = math.max(
      width,
      36 +
          12 +
          labelWidth +
          12 +
          textWidth('×${_displayQuantity(ingredient.quantity)}', quantityStyle),
    );
  }
  // Include the content insets and the leading rule. The width is
  // independent of the outer description, while bounded layouts still wrap.
  return (width + 28).ceilToDouble();
}

class _FormulaMaterialRow extends StatelessWidget {
  const _FormulaMaterialRow({
    required this.controller,
    required this.mode,
    required this.formula,
    required this.ingredient,
    required this.style,
    required this.topSpacing,
  });

  final RecipeBookController controller;
  final CraftMode mode;
  final RecipeBookFormula formula;
  final Ingredient ingredient;
  final TextStyle style;
  final double topSpacing;

  @override
  Widget build(BuildContext context) {
    final spec = context.visualTheme;
    final alternatives = _formulaAlternatives(
      ingredient,
      recipes: controller.modeController.owner.modes[mode]!.recipes,
    );
    final quantity = _displayQuantity(ingredient.quantity);
    final semanticLabel = <String>[
      '$quantity ${ingredient.name}',
      for (final alternative in alternatives)
        'or ${_displayQuantity(alternative.quantity)} ${alternative.name}',
    ].join(', ');
    final alternateStyle = style.copyWith(
      color: spec.palette.textMuted,
      fontSize: 13,
      height: 1.35,
    );
    return Padding(
      padding: EdgeInsets.only(top: topSpacing),
      child: Semantics(
        container: true,
        label: semanticLabel,
        explicitChildNodes: true,
        child: Row(
          key: RecipeBookKeys.itemInfoMaterial(
            formula.outputName,
            formula.variantId,
            ingredient.name,
          ),
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            ModeItemIcon(
              controller: controller.modeController.owner.modes[mode]!,
              catalogRepository: controller.catalogRepository,
              name: ingredient.name,
              size: ItemDetailStyle.ingredientIcon,
              searchAcrossModes: true,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(
                        child: _ReferenceItemName(
                          name: ingredient.name,
                          style: style.copyWith(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '×$quantity',
                        style: style.copyWith(
                          color: spec.palette.textMuted,
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                  for (final alternative in alternatives)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: _ReferenceItemName(
                        name: alternative.name,
                        label:
                            'or ${_displayQuantity(alternative.quantity)} '
                            '${alternative.name}',
                        style: alternateStyle,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

final class _FormulaAlternative {
  const _FormulaAlternative({required this.name, required this.quantity});

  final String name;
  final double quantity;
}

List<_FormulaAlternative> _formulaAlternatives(
  Ingredient ingredient, {
  required Map<String, Recipe> recipes,
}) {
  final candidates = <String>[
    ...ingredient.options,
    ...ingredient.substituteRatios.keys,
  ];
  final seen = <String>{ingredient.name.trim().toLowerCase()};
  final result = <_FormulaAlternative>[];
  for (final candidate in candidates) {
    final name = candidate.trim();
    final identity = name.toLowerCase();
    if (name.isEmpty ||
        isTemporarilyArchivedItem(name, itemId: recipes[name]?.marketId) ||
        !seen.add(identity)) {
      continue;
    }
    var ratio = 1.0;
    for (final entry in ingredient.substituteRatios.entries) {
      if (entry.key.trim().toLowerCase() == identity && entry.value > 0) {
        ratio = entry.value;
        break;
      }
    }
    result.add(
      _FormulaAlternative(name: name, quantity: ingredient.quantity * ratio),
    );
  }
  return result;
}

String _formulaOutputLabel(RecipeBookFormula formula) {
  final outputLabel = formula.outputEstimated ? 'Estimated output' : 'Output';
  final minimum = formula.outputMinimum;
  final maximum = formula.outputMaximum;
  if (minimum != null && maximum != null) {
    if (minimum == maximum) {
      return '$outputLabel ×${_displayQuantity(minimum)}';
    }
    return '$outputLabel ×${_displayQuantity(minimum)}–'
        '${_displayQuantity(maximum)}';
  }
  final prefix =
      !formula.outputEstimated && formula.type.trim().toLowerCase() == 'alchemy'
      ? 'Base output'
      : outputLabel;
  return '$prefix ×${_displayQuantity(formula.baseOutput)}';
}

String _displayQuantity(double value) {
  if (value == value.roundToDouble()) return value.toInt().toString();
  return value
      .toStringAsFixed(3)
      .replaceFirst(RegExp(r'0+$'), '')
      .replaceFirst(RegExp(r'\.$'), '');
}

class _UsedForSection extends StatelessWidget {
  const _UsedForSection({
    required this.controller,
    required this.mode,
    required this.sourceName,
    required this.values,
    required this.craftUses,
    required this.style,
  });

  final RecipeBookController controller;
  final CraftMode mode;
  final String sourceName;
  final List<String> values;
  final List<RecipeBookCraftUse> craftUses;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    final spec = context.visualTheme;
    final readable = values.where((value) => value.trim().isNotEmpty).toList();
    if (readable.isEmpty && craftUses.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: EdgeInsets.only(top: _itemInfoSpacing(context, 20)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          _InfoSectionHeading(title: 'Used For', spec: spec),
          SizedBox(height: _itemInfoSpacing(context, 8)),
          for (final value in readable) _InfoBullet(value: value, style: style),
          for (var index = 0; index < craftUses.length; index++)
            _CraftUseEntry(
              controller: controller,
              mode: mode,
              sourceName: sourceName,
              craftUse: craftUses[index],
              style: style,
              topSpacing: index == 0 && values.isEmpty
                  ? 0
                  : _itemInfoSpacing(context, 16),
            ),
        ],
      ),
    );
  }
}

class _CraftUseEntry extends StatelessWidget {
  const _CraftUseEntry({
    required this.controller,
    required this.mode,
    required this.sourceName,
    required this.craftUse,
    required this.style,
    required this.topSpacing,
  });

  final RecipeBookController controller;
  final CraftMode mode;
  final String sourceName;
  final RecipeBookCraftUse craftUse;
  final TextStyle style;
  final double topSpacing;

  @override
  Widget build(BuildContext context) {
    final spec = context.visualTheme;
    final source = sourceName.trim().toLowerCase();
    final matching = craftUse.formulas
        .where(
          (formula) => formula.ingredients.any(
            (ingredient) => [
              ingredient.name,
              ...ingredient.options,
              ...ingredient.substituteRatios.keys,
            ].any((name) => name.trim().toLowerCase() == source),
          ),
        )
        .toList(growable: false);
    // Curated indirect uses may have no exact input match; keep those intact.
    // Direct material references should not lead with a batch using another item.
    final formulas = _distinctReferenceFormulas(
      matching.isEmpty ? craftUse.formulas : matching,
    );
    final outputInfo = controller.itemInfoFor(craftUse.output, mode: mode);
    final effects = outputInfo?.effects ?? const <String>[];
    final effectHeading = outputInfo?.effectsTitle ?? 'Effects';
    final description =
        outputInfo == null || (effects.isNotEmpty && effectHeading == 'Effects')
        ? ''
        : recipeBookUseDescription(outputInfo);
    final example = outputInfo?.example?.trim() ?? '';
    final contextStyle = style.copyWith(
      color: spec.palette.textMuted,
      fontSize: (style.fontSize ?? 12.5) - .5,
    );
    final routeIds = formulas
        .map((formula) => (formula.routeId ?? formula.routeLabel ?? '').trim())
        .where((value) => value.isNotEmpty)
        .map((value) => value.toLowerCase())
        .toSet();
    final showRouteLabel = routeIds.length > 1;
    final showBatchLabel = formulas.any(
      (formula) => formula.batchMultiplier != 1,
    );
    return Padding(
      padding: EdgeInsets.only(top: topSpacing),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: <Widget>[
              ModeItemIcon(
                controller: controller.modeController.owner.modes[mode]!,
                catalogRepository: controller.catalogRepository,
                name: craftUse.output,
                size: ItemDetailStyle.recipeIcon,
                searchAcrossModes: true,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _ReferenceItemName(
                  name: craftUse.output,
                  style: style.copyWith(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          if (description.isNotEmpty) ...<Widget>[
            SizedBox(height: _itemInfoSpacing(context, 6)),
            Text(description, style: contextStyle),
          ],
          if (effects.isNotEmpty) ...<Widget>[
            SizedBox(height: _itemInfoSpacing(context, 6)),
            if (effectHeading != 'Effects') ...[
              _InfoSectionHeading(title: effectHeading, spec: spec),
              SizedBox(height: _itemInfoSpacing(context, 4)),
            ],
            for (final effect in effects)
              _InfoBullet(
                value: effect,
                style: style.copyWith(
                  color: spec.palette.textMuted,
                  fontWeight: FontWeight.w400,
                  height: 1.4,
                ),
              ),
          ],
          if (example.isNotEmpty) ...<Widget>[
            const SizedBox(height: 3),
            Text.rich(
              TextSpan(
                children: <InlineSpan>[
                  TextSpan(
                    text: 'Example: ',
                    style: contextStyle.copyWith(
                      color: spec.palette.text,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  TextSpan(text: example, style: contextStyle),
                ],
              ),
            ),
          ],
          if (formulas.isNotEmpty)
            SizedBox(height: _itemInfoSpacing(context, 12)),
          for (var index = 0; index < formulas.length; index++) ...<Widget>[
            if (index > 0) SizedBox(height: _itemInfoSpacing(context, 12)),
            _FormulaCard(
              controller: controller,
              mode: mode,
              formula: formulas[index],
              style: style,
              showRouteLabel: showRouteLabel,
              showBatchLabel: showBatchLabel,
            ),
          ],
        ],
      ),
    );
  }
}

class _InfoSection extends StatelessWidget {
  const _InfoSection({
    required this.title,
    required this.values,
    required this.style,
  });

  final String title;
  final List<String> values;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    final spec = context.visualTheme;
    final readable = values.where((value) => value.trim().isNotEmpty).toList();
    if (readable.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: EdgeInsets.only(top: _itemInfoSpacing(context, 20)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          _InfoSectionHeading(title: title, spec: spec),
          SizedBox(height: _itemInfoSpacing(context, 8)),
          for (final value in readable) _InfoBullet(value: value, style: style),
        ],
      ),
    );
  }
}

class _InfoSectionHeading extends StatelessWidget {
  const _InfoSectionHeading({required this.title, required this.spec});

  final String title;
  final ThemeSpec spec;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      header: true,
      child: Row(
        children: [
          Flexible(child: Text(title, style: ItemDetailStyle.section(spec))),
          const SizedBox(width: 12),
          const Expanded(child: WorkshopSectionRule()),
        ],
      ),
    );
  }
}

class _InfoBullet extends StatelessWidget {
  const _InfoBullet({required this.value, required this.style});

  final String value;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    final lines = value
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList(growable: false);
    if (lines.length > 1) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Semantics(
          container: true,
          label: lines.join(', '),
          child: ExcludeSemantics(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text('\u2022', style: style),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        lines.first,
                        style: style.copyWith(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                for (final line in lines.skip(1))
                  Padding(
                    padding: const EdgeInsets.only(left: 18, bottom: 3),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text('\u2022', style: style),
                        const SizedBox(width: 6),
                        Expanded(child: Text(line, style: style)),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Semantics(
        container: true,
        label: lines.isEmpty ? value : lines.single,
        child: ExcludeSemantics(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text('\u2022', style: style),
              const SizedBox(width: 6),
              Expanded(
                child: Text(lines.isEmpty ? value : lines.single, style: style),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
