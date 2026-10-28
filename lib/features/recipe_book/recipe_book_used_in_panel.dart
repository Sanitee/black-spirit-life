import 'dart:async';
import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/material.dart';

import '../../domain/formatting/planner_formatters.dart';
import '../../domain/models/craft_mode.dart';
import '../../shared/overlays/anchored_popover.dart';
import '../../visual/components/app_interaction_frame.dart';
import '../../visual/visual.dart';
import '../shared/recipe_variant_selector.dart';
import '../shared/workshop_presentation.dart';
import 'recipe_book_controller.dart';
import 'recipe_book_item_info_view.dart';
import 'recipe_book_keys.dart';
import 'recipe_book_preview_routes.dart';
import 'recipe_book_usage.dart';
import 'recipe_ingredient_line.dart';

class RecipeBookUsedInPanel extends StatefulWidget {
  const RecipeBookUsedInPanel({
    required this.controller,
    required this.sourceName,
    required this.snapshot,
    required this.onClose,
    required this.onActivate,
    super.key,
  });

  final RecipeBookController controller;
  final String sourceName;
  final RecipeBookUseSnapshot snapshot;
  final VoidCallback onClose;
  final bool Function(RecipeBookUseEntry, String?) onActivate;

  @override
  State<RecipeBookUsedInPanel> createState() => _RecipeBookUsedInPanelState();
}

class _RecipeBookUsedInPanelState extends State<RecipeBookUsedInPanel> {
  final ScrollController _scroll = ScrollController();
  final TextEditingController _search = TextEditingController();
  final Set<String> _expanded = <String>{};
  final Map<String, String?> _selectedVariants = <String, String?>{};

  @override
  void dispose() {
    _scroll.dispose();
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final spec = context.visualTheme;
    final visibleEntries = _visibleEntries();
    final parentOverlays = AppOverlayCoordinatorScope.maybeOf(context);
    return AppOverlayCoordinatorHost(
      onEscapeUnhandled: () => parentOverlays?.dismissTop(),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final height = constraints.maxHeight.isFinite
              ? constraints.maxHeight
              : itemReferenceCardHeight(context);
          return ConstrainedBox(
            key: RecipeBookKeys.usedInPanel(widget.sourceName),
            constraints: BoxConstraints(maxHeight: height),
            child: AppSurface(
              role: AppSurfaceRole.modal,
              padding: const EdgeInsets.all(16),
              clipBehavior: Clip.antiAlias,
              semanticLabel: '${widget.sourceName} used in recipes',
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  _header(context, spec),
                  const Padding(
                    padding: EdgeInsets.symmetric(
                      vertical: (ItemDetailStyle.sectionGap - 1) / 2,
                    ),
                    child: WorkshopSectionRule(emphasis: true),
                  ),
                  if (widget.snapshot.entries.length >= 12) ...<Widget>[
                    SizedBox(
                      height: 40,
                      child: AppTextField(
                        key: RecipeBookKeys.usedInSearch(widget.sourceName),
                        controller: _search,
                        hintText: 'Filter these recipes',
                        semanticLabel:
                            'Filter recipes that use ${widget.sourceName}',
                        minimumHeight: 40,
                        onChanged: (_) => setState(() {}),
                        suffixIcon: _search.text.isEmpty
                            ? null
                            : AppButton(
                                role: AppButtonRole.optionPill,
                                minimumSize: const Size.square(28),
                                padding: EdgeInsets.zero,
                                semanticLabel: 'Clear Used In filter',
                                tooltip: 'Clear',
                                onPressed: () => setState(_search.clear),
                                child: const AppVectorGlyph('close', size: 10),
                              ),
                      ),
                    ),
                    const SizedBox(height: 10),
                  ],
                  Flexible(
                    child: visibleEntries.isEmpty
                        ? _empty(context, filtered: _search.text.isNotEmpty)
                        : ScrollConfiguration(
                            behavior: const _UsedInScrollBehavior(),
                            child: ListView.separated(
                              shrinkWrap: true,
                              key: RecipeBookKeys.usedInScroll(
                                widget.sourceName,
                              ),
                              controller: _scroll,
                              padding: EdgeInsets.zero,
                              itemCount: visibleEntries.length,
                              separatorBuilder: (_, _) => Divider(
                                height: 25,
                                thickness: 1,
                                color: spec.palette.trim.withAlpha(90),
                              ),
                              itemBuilder: (context, index) {
                                final entry = visibleEntries[index];
                                final entryKey = _entryKey(entry);
                                return _UsedInResultCard(
                                  key: RecipeBookKeys.usedInResult(
                                    widget.sourceName,
                                    entry.mode.key,
                                    entry.name,
                                  ),
                                  controller: widget.controller,
                                  sourceName: widget.sourceName,
                                  entry: entry,
                                  showWorkstation:
                                      widget.snapshot.entries
                                          .where(
                                            (candidate) =>
                                                candidate.name == entry.name,
                                          )
                                          .length >
                                      1,
                                  expanded: _expanded.contains(entryKey),
                                  selectedVariantId: _selectedVariantFor(entry),
                                  onToggleExpanded: () => setState(() {
                                    if (!_expanded.add(entryKey)) {
                                      _expanded.remove(entryKey);
                                    }
                                  }),
                                  onSelectVariant: (variantId) => setState(() {
                                    _selectedVariants[entryKey] = variantId;
                                  }),
                                  onActivate: (variantId) {
                                    if (widget.onActivate(entry, variantId)) {
                                      widget.onClose();
                                    }
                                  },
                                );
                              },
                            ),
                          ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _header(BuildContext context, ThemeSpec spec) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: <Widget>[
      WorkshopItemMount(
        child: RecipeBookItemIcon(
          controller: widget.controller,
          name: widget.sourceName,
          size: ItemDetailStyle.headerIcon,
          anchorId: 'used-in:${widget.sourceName}:header',
        ),
      ),
      const SizedBox(width: ItemDetailStyle.itemGap),
      Expanded(
        child: AnchoredPopoverDragRegion(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(widget.sourceName, style: ItemDetailStyle.title(spec)),
              const SizedBox(height: 5),
              Text(
                _resultSummary(widget.snapshot),
                style: ItemDetailStyle.meta(spec),
              ),
            ],
          ),
        ),
      ),
      const SizedBox(width: 8),
      AppButton(
        key: RecipeBookKeys.closeUsedIn(widget.sourceName),
        role: AppButtonRole.optionPill,
        minimumSize: const Size.square(30),
        padding: EdgeInsets.zero,
        semanticLabel: 'Close Used In for ${widget.sourceName}',
        tooltip: 'Close',
        onPressed: widget.onClose,
        child: const AppVectorGlyph('close', size: 11),
      ),
    ],
  );

  Widget _empty(BuildContext context, {required bool filtered}) {
    final spec = context.visualTheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 30),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            AppVectorGlyph('branch', size: 32, color: spec.palette.textMuted),
            const SizedBox(height: 10),
            Text(
              filtered
                  ? 'No matching recipes in this Used In list.'
                  : 'No other recorded recipe uses this item.',
              style: spec.typography.label.copyWith(fontSize: 13),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  List<RecipeBookUseEntry> _visibleEntries() {
    final query = _search.text.trim().toLowerCase();
    if (query.isEmpty) return widget.snapshot.entries;
    return widget.snapshot.entries
        .where((entry) {
          if (entry.name.toLowerCase().contains(query) ||
              entry.mode.label.toLowerCase().contains(query) ||
              entry.kinds.any(
                (kind) => kind.label.toLowerCase().contains(query),
              )) {
            return true;
          }
          return entry.routes.any(
            (route) =>
                (route.method ?? '').toLowerCase().contains(query) ||
                route.type.toLowerCase().contains(query) ||
                route.routeLabel.toLowerCase().contains(query),
          );
        })
        .toList(growable: false);
  }

  String? _selectedVariantFor(RecipeBookUseEntry entry) {
    final entryKey = _entryKey(entry);
    if (_selectedVariants.containsKey(entryKey)) {
      final selected = _selectedVariants[entryKey];
      if (entry.routes.any(
        (route) => _fold(route.variantId ?? '') == _fold(selected ?? ''),
      )) {
        return selected;
      }
      _selectedVariants.remove(entryKey);
    }
    final destination =
        widget.controller.modeController.owner.modes[entry.mode]!;
    return entry
        .preferredRoute(destination.selectedRecipeVariantId(entry.name))
        ?.variantId;
  }
}

class _UsedInResultCard extends StatelessWidget {
  const _UsedInResultCard({
    required this.controller,
    required this.sourceName,
    required this.entry,
    required this.showWorkstation,
    required this.expanded,
    required this.selectedVariantId,
    required this.onToggleExpanded,
    required this.onSelectVariant,
    required this.onActivate,
    super.key,
  });

  final RecipeBookController controller;
  final String sourceName;
  final RecipeBookUseEntry entry;
  final bool showWorkstation;
  final bool expanded;
  final String? selectedVariantId;
  final VoidCallback onToggleExpanded;
  final ValueChanged<String> onSelectVariant;
  final ValueChanged<String?> onActivate;

  RecipeBookUseRoute? get _selectedRoute {
    final selected = _fold(selectedVariantId ?? '');
    if (selected.isNotEmpty) {
      for (final route in entry.routes) {
        if (_fold(route.variantId ?? '') == selected) return route;
      }
    }
    return entry.preferredRoute(selectedVariantId);
  }

  @override
  Widget build(BuildContext context) {
    final spec = context.visualTheme;
    final canActivate = controller.canActivateUsedIn(entry);
    final method = _entryMethod(entry);
    final selectedRoute = _selectedRoute;
    final identity = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        RecipeBookItemIcon(
          controller: controller,
          mode: entry.mode,
          name: entry.name,
          size: ItemDetailStyle.recipeIcon,
          anchorId:
              'used-in:$sourceName:${entry.mode.key}:${entry.name}:output',
        ),
        const SizedBox(width: ItemDetailStyle.itemGap),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(entry.name, style: ItemDetailStyle.recipe(spec)),
              const SizedBox(height: 6),
              Wrap(
                spacing: 12,
                runSpacing: 4,
                children: [
                  if (method.isNotEmpty)
                    Text(method, style: ItemDetailStyle.meta(spec)),
                  if (showWorkstation)
                    Text(
                      '${entry.mode.label} recipes',
                      style: ItemDetailStyle.meta(spec),
                    ),
                  for (final kind in _sortedKinds(entry.kinds))
                    if (kind != RecipeBookUseKind.requiredIngredient)
                      Text(kind.label, style: ItemDetailStyle.meta(spec)),
                  if (entry.hidden)
                    Text(
                      'Hidden',
                      style: ItemDetailStyle.meta(
                        spec,
                      ).copyWith(color: spec.palette.warning),
                    ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
    final actions = Wrap(
      spacing: 12,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        AppButton(
          key: RecipeBookKeys.targetUsedInResult(
            sourceName,
            entry.mode.key,
            entry.name,
          ),
          role: AppButtonRole.optionPill,
          minimumSize: const Size(0, 34),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          tooltip: _targetTooltip(controller, entry),
          onPressed: entry.hidden
              ? controller.restoringHiddenName == null
                    ? () => unawaited(
                        controller.restoreHiddenItem(
                          entry.name,
                          mode: entry.mode,
                        ),
                      )
                    : null
              : canActivate
              ? () => onActivate(selectedVariantId)
              : null,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              AppVectorGlyph(entry.hidden ? 'reset' : 'target', size: 14),
              const SizedBox(width: 6),
              Text(
                entry.hidden ? 'Restore' : 'Target',
                style: ItemDetailStyle.body(spec),
              ),
            ],
          ),
        ),
        AppTextAction(
          key: RecipeBookKeys.expandUsedInResult(
            sourceName,
            entry.mode.key,
            entry.name,
          ),
          semanticLabel:
              '${expanded ? 'Hide' : 'Show'} ${entry.name} ingredients',
          tooltip: expanded ? 'Hide ingredients' : 'Preview ingredients',
          onPressed: onToggleExpanded,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Ingredients', style: ItemDetailStyle.meta(spec)),
              const SizedBox(width: 6),
              AppVectorGlyph(
                expanded ? 'chevron-up' : 'chevron-down',
                size: 12,
              ),
            ],
          ),
        ),
      ],
    );
    return Semantics(
      container: true,
      explicitChildNodes: true,
      label: '${entry.name}, ${entry.mode.label}, used in recipe result',
      child: AppInteractionFrame(
        selected: expanded,
        radius: 6,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              LayoutBuilder(
                builder: (context, constraints) {
                  final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
                  if (constraints.maxWidth >= 580 * scale) {
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: identity),
                        const SizedBox(width: 16),
                        actions,
                      ],
                    );
                  }
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      identity,
                      const SizedBox(height: 12),
                      Padding(
                        padding: const EdgeInsets.only(
                          left:
                              ItemDetailStyle.recipeIcon +
                              ItemDetailStyle.itemGap,
                        ),
                        child: actions,
                      ),
                    ],
                  );
                },
              ),
              if (expanded) ...[
                const SizedBox(height: 16),
                ItemDetailGroup(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (_showsVariantSelector(entry)) ...[
                        RecipeVariantSelector(
                          recipe: entry.recipe,
                          selectedVariantId: selectedVariantId,
                          onSelected: onSelectVariant,
                          compact: true,
                          allowedVariantIds: entry.routes
                              .map((route) => route.variantId)
                              .whereType<String>()
                              .toSet(),
                          showSingleAllowedIdentity: true,
                          keyNamespace: _selectorNamespace(sourceName, entry),
                        ),
                        const SizedBox(height: 12),
                      ],
                      if (selectedRoute != null)
                        _FormulaRoute(
                          controller: controller,
                          sourceName: sourceName,
                          mode: entry.mode,
                          outputName: entry.name,
                          route: selectedRoute,
                          showMethod: method == 'Multiple methods',
                        ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _FormulaRoute extends StatelessWidget {
  const _FormulaRoute({
    required this.controller,
    required this.sourceName,
    required this.mode,
    required this.outputName,
    required this.route,
    required this.showMethod,
  });

  final RecipeBookController controller;
  final String sourceName;
  final CraftMode mode;
  final String outputName;
  final RecipeBookUseRoute route;
  final bool showMethod;

  @override
  Widget build(BuildContext context) {
    final spec = context.visualTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        if (showMethod && _routeMethod(route).isNotEmpty) ...<Widget>[
          Text(_routeMethod(route), style: ItemDetailStyle.meta(spec)),
          const SizedBox(height: 6),
        ],
        Text(
          'Output ×${_routeOutput(route)}',
          style: ItemDetailStyle.meta(
            spec,
          ).copyWith(color: ItemDetailStyle.accent(spec)),
        ),
        const SizedBox(height: 20),
        for (
          var ingredientIndex = 0;
          ingredientIndex < route.ingredients.length;
          ingredientIndex++
        ) ...<Widget>[
          _FormulaIngredientRow(
            controller: controller,
            sourceName: sourceName,
            mode: mode,
            outputName: outputName,
            route: route,
            ingredientIndex: ingredientIndex,
          ),
          if (ingredientIndex + 1 < route.ingredients.length)
            Divider(
              height: 12,
              thickness: 1,
              color: spec.palette.trim.withValues(alpha: .2),
            ),
        ],
      ],
    );
  }
}

class _FormulaIngredientRow extends StatelessWidget {
  const _FormulaIngredientRow({
    required this.controller,
    required this.sourceName,
    required this.mode,
    required this.outputName,
    required this.route,
    required this.ingredientIndex,
  });

  final RecipeBookController controller;
  final String sourceName;
  final CraftMode mode;
  final String outputName;
  final RecipeBookUseRoute route;
  final int ingredientIndex;

  @override
  Widget build(BuildContext context) {
    final ingredient = route.ingredients[ingredientIndex];
    RecipeBookUseMatch? match;
    for (final candidate in route.matches) {
      if (_fold(candidate.ingredientName) == _fold(ingredient.name)) {
        match = candidate;
        break;
      }
    }
    final name = match?.sourceName ?? ingredient.name;
    final quantity = match?.sourceQuantity ?? ingredient.quantity;
    final substitution =
        match != null && match.kind != RecipeBookUseKind.requiredIngredient
        ? ', substitutes for ${match.ingredientName}'
        : '';
    return RecipeIngredientLine(
      semanticLabel: '$name, Need ${formatQuantity(quantity)}$substitution',
      name: name,
      quantity: quantity,
      icon: RecipeBookItemIcon(
        controller: controller,
        mode: mode,
        name: name,
        size: ItemDetailStyle.ingredientIcon,
        anchorId:
            'used-in:$sourceName:${mode.key}:$outputName:'
            '${route.id}:ingredient:$ingredientIndex:$name',
      ),
    );
  }
}

String _entryKey(RecipeBookUseEntry entry) =>
    '${entry.mode.key}:${entry.name.toLowerCase()}';

String _selectorNamespace(String sourceName, RecipeBookUseEntry entry) =>
    'used-in:$sourceName:${entry.mode.key}:${entry.name}';

bool _showsVariantSelector(RecipeBookUseEntry entry) {
  if (!entry.recipe.hasRecipeVariants) return false;
  final allowed = entry.routes
      .map((route) => _fold(route.variantId ?? ''))
      .where((id) => id.isNotEmpty)
      .toSet();
  if (allowed.isEmpty) return false;
  final availableCount = entry.recipe.variants
      .where((variant) => allowed.contains(_fold(variant.id)))
      .length;
  if (availableCount >= 2) return true;
  return availableCount == 1 &&
      (entry.recipe.hasRecipeRouteChoices ||
          entry.recipe.hasRecipeBatchChoices);
}

String _resultSummary(RecipeBookUseSnapshot snapshot) {
  return 'Used in ${snapshot.recipeCount} ${snapshot.recipeCount == 1 ? 'recipe' : 'recipes'}';
}

List<RecipeBookUseKind> _sortedKinds(Set<RecipeBookUseKind> kinds) =>
    kinds.toList()..sort((left, right) => left.index.compareTo(right.index));

String _routeMethod(RecipeBookUseRoute? route) {
  if (route == null) return '';
  final method = route.method?.trim() ?? '';
  return recipeBookPreviewMethodLabel(
    method.isNotEmpty ? method : _typeLabel(route.type),
  );
}

String _entryMethod(RecipeBookUseEntry entry) {
  final methods = entry.routes
      .map(_routeMethod)
      .where((method) => method.isNotEmpty)
      .toSet();
  if (methods.length > 1) return 'Multiple methods';
  return methods.isEmpty ? '' : methods.single;
}

String _routeOutput(RecipeBookUseRoute route) {
  final minimum = route.outputMinimum;
  final maximum = route.outputMaximum;
  return _fold(route.type) == 'processing' && minimum != null
      ? maximum == null || maximum == minimum
            ? formatQuantity(minimum)
            : '${formatQuantity(minimum)}–${formatQuantity(maximum)}'
      : formatQuantity(route.baseOutput);
}

String _targetTooltip(
  RecipeBookController controller,
  RecipeBookUseEntry entry,
) {
  if (entry.hidden) return 'Restore this hidden recipe';
  if (controller.canActivateUsedIn(entry)) {
    return entry.mode == controller.modeController.mode
        ? 'Use this recipe as the target'
        : 'Switch to ${entry.mode.label} and target this recipe';
  }
  return 'Open this result from the Planner Recipe Book to switch workstations';
}

String _typeLabel(String type) => type
    .split('_')
    .where((part) => part.isNotEmpty)
    .map((part) => '${part[0].toUpperCase()}${part.substring(1)}')
    .join(' ');

String _fold(String value) => value.trim().toLowerCase();

class _UsedInScrollBehavior extends AppScrollBehavior {
  const _UsedInScrollBehavior();

  @override
  Widget buildScrollbar(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) => child;

  @override
  Set<PointerDeviceKind> get dragDevices => const <PointerDeviceKind>{
    PointerDeviceKind.mouse,
    PointerDeviceKind.touch,
    PointerDeviceKind.trackpad,
  };
}
