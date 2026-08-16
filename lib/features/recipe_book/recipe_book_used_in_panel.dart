import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/material.dart';

import '../../domain/formatting/planner_formatters.dart';
import '../../domain/models/craft_mode.dart';
import '../../shared/overlays/anchored_popover.dart';
import '../../visual/visual.dart';
import '../shared/recipe_variant_selector.dart';
import 'recipe_book_controller.dart';
import 'recipe_book_item_info_view.dart';
import 'recipe_book_keys.dart';
import 'recipe_book_usage.dart';

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
              : 610.0;
          return SizedBox(
            key: RecipeBookKeys.usedInPanel(widget.sourceName),
            height: _desiredHeight(height, visibleEntries),
            child: AppSurface(
              role: AppSurfaceRole.modal,
              padding: const EdgeInsets.all(14),
              clipBehavior: Clip.antiAlias,
              semanticLabel: '${widget.sourceName} used in recipes',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  _header(context, spec),
                  const SizedBox(height: 12),
                  if (widget.snapshot.modeCounts.isNotEmpty) ...<Widget>[
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: <Widget>[
                        for (final mode in CraftMode.values)
                          if (widget.snapshot.modeCounts[mode]
                              case final count?)
                            _UseBadge(
                              label: '${mode.label} $count',
                              emphasized:
                                  mode == widget.controller.modeController.mode,
                            ),
                      ],
                    ),
                    const SizedBox(height: 10),
                  ],
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
                  Divider(
                    height: 1,
                    thickness: 1,
                    color: spec.palette.trim.withAlpha(116),
                  ),
                  const SizedBox(height: 10),
                  Expanded(
                    child: visibleEntries.isEmpty
                        ? _empty(context, filtered: _search.text.isNotEmpty)
                        : ScrollConfiguration(
                            behavior: const _UsedInScrollBehavior(),
                            child: ListView.separated(
                              key: RecipeBookKeys.usedInScroll(
                                widget.sourceName,
                              ),
                              controller: _scroll,
                              padding: const EdgeInsets.only(
                                right: 10,
                                bottom: 4,
                              ),
                              itemCount: visibleEntries.length,
                              separatorBuilder: (_, _) =>
                                  const SizedBox(height: 8),
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
      RecipeBookItemIcon(
        controller: widget.controller,
        name: widget.sourceName,
        size: 48,
        anchorId: 'used-in:${widget.sourceName}:header',
      ),
      const SizedBox(width: 11),
      Expanded(
        child: AnchoredPopoverDragRegion(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                'Used In',
                style: spec.typography.meta.copyWith(
                  color: spec.palette.warning,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: .55,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                widget.sourceName,
                style: spec.typography.section.copyWith(
                  fontSize: 19,
                  height: 1.05,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 5),
              Text(
                _resultSummary(widget.snapshot),
                style: spec.typography.body.copyWith(
                  color: spec.palette.textMuted,
                  fontSize: 11.5,
                ),
              ),
            ],
          ),
        ),
      ),
      const SizedBox(width: 8),
      AppButton(
        key: RecipeBookKeys.closeUsedIn(widget.sourceName),
        role: spec.isIlluminatedLedger
            ? AppButtonRole.primary
            : AppButtonRole.optionPill,
        minimumSize: const Size.square(32),
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

  double _desiredHeight(
    double maximumHeight,
    List<RecipeBookUseEntry> visibleEntries,
  ) {
    var desired = 28.0 + 68 + 12 + 25 + 10 + 1 + 10;
    if (widget.snapshot.entries.length >= 12) desired += 50;
    if (visibleEntries.isEmpty) {
      desired += 118;
    } else {
      for (final entry in visibleEntries) {
        desired += entry.routes.length > 1 ? 102 : 88;
        if (_expanded.contains(_entryKey(entry))) {
          final ingredientCount = entry.routes.fold<int>(
            1,
            (maximum, route) => math.max(maximum, route.ingredients.length),
          );
          desired += 42 + ingredientCount * 58;
          if (_showsVariantSelector(entry)) desired += 36;
        }
      }
      desired += math.max(0, visibleEntries.length - 1) * 8;
    }
    final minimumHeight = math.min(230.0, maximumHeight);
    return desired.clamp(minimumHeight, maximumHeight).toDouble();
  }
}

class _UsedInResultCard extends StatelessWidget {
  const _UsedInResultCard({
    required this.controller,
    required this.sourceName,
    required this.entry,
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
    return AppSurface(
      role: AppSurfaceRole.card,
      tone: entry.hidden ? AppSurfaceTone.warning : AppSurfaceTone.neutral,
      padding: const EdgeInsets.all(10),
      clipBehavior: Clip.antiAlias,
      semanticLabel:
          '${entry.name}, ${entry.mode.label}, used in recipe result',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              RecipeBookItemIcon(
                controller: controller,
                mode: entry.mode,
                name: entry.name,
                size: 40,
                anchorId:
                    'used-in:$sourceName:${entry.mode.key}:'
                    '${entry.name}:output',
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      entry.name,
                      style: spec.typography.label.copyWith(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        height: 1.1,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 5),
                    Wrap(
                      spacing: 5,
                      runSpacing: 5,
                      children: <Widget>[
                        _UseBadge(label: entry.mode.label, emphasized: true),
                        if (method.isNotEmpty) _UseBadge(label: method),
                        for (final kind in _sortedKinds(entry.kinds))
                          _UseBadge(label: kind.label),
                        if (entry.hidden)
                          const _UseBadge(label: 'Hidden', warning: true),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Tooltip(
                    message: _targetTooltip(controller, entry),
                    child: SizedBox(
                      width: 88,
                      height: 34,
                      child: AppButton(
                        key: RecipeBookKeys.targetUsedInResult(
                          sourceName,
                          entry.mode.key,
                          entry.name,
                        ),
                        role: entry.hidden
                            ? AppButtonRole.secondary
                            : AppButtonRole.primary,
                        minimumSize: Size.zero,
                        padding: const EdgeInsets.symmetric(horizontal: 7),
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
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: <Widget>[
                              AppVectorGlyph(
                                entry.hidden ? 'reset' : 'target',
                                size: 12,
                              ),
                              const SizedBox(width: 5),
                              Text(entry.hidden ? 'Restore' : 'Target'),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  AppButton(
                    key: RecipeBookKeys.expandUsedInResult(
                      sourceName,
                      entry.mode.key,
                      entry.name,
                    ),
                    role: expanded
                        ? AppButtonRole.primary
                        : AppButtonRole.optionPill,
                    selected: expanded,
                    minimumSize: const Size.square(34),
                    padding: EdgeInsets.zero,
                    semanticLabel:
                        '${expanded ? 'Hide' : 'Show'} ${entry.name} ingredients',
                    tooltip: expanded
                        ? 'Hide ingredients'
                        : 'Preview ingredients',
                    onPressed: onToggleExpanded,
                    child: AppVectorGlyph(
                      expanded ? 'chevron-up' : 'book',
                      size: 13,
                    ),
                  ),
                ],
              ),
            ],
          ),
          if (expanded) ...<Widget>[
            const SizedBox(height: 10),
            Divider(
              height: 1,
              thickness: 1,
              color: spec.palette.trim.withAlpha(105),
            ),
            const SizedBox(height: 9),
            if (_showsVariantSelector(entry)) ...<Widget>[
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
              const SizedBox(height: 9),
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
        ],
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
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 5,
            runSpacing: 5,
            children: <Widget>[_UseBadge(label: _routeMethod(route))],
          ),
          const SizedBox(height: 6),
        ],
        Text(
          'Makes ${_routeOutput(route)} $outputName',
          style: spec.typography.meta.copyWith(
            color: spec.palette.textMuted,
            fontSize: 10.5,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 7),
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
            const SizedBox(height: 6),
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
    final spec = context.visualTheme;
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
    return AppSurface(
      role: AppSurfaceRole.row,
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 8),
      semanticLabel: '$name, Need ${formatQuantity(quantity)}$substitution',
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: <Widget>[
          SizedBox(
            width: 38,
            child: Align(
              child: RecipeBookItemIcon(
                controller: controller,
                mode: mode,
                name: name,
                size: 34,
                anchorId:
                    'used-in:$sourceName:${mode.key}:$outputName:'
                    '${route.id}:ingredient:$ingredientIndex:$name',
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  name,
                  style: spec.typography.label.copyWith(fontSize: 13),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 3),
                Text(
                  'Need ${formatQuantity(quantity)}',
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
  }
}

class _UseBadge extends StatelessWidget {
  const _UseBadge({
    required this.label,
    this.emphasized = false,
    this.warning = false,
  });

  final String label;
  final bool emphasized;
  final bool warning;

  @override
  Widget build(BuildContext context) {
    final spec = context.visualTheme;
    final color = warning
        ? spec.palette.warning
        : emphasized
        ? spec.palette.primary
        : spec.palette.trim;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color.withAlpha(emphasized ? 70 : 38),
        borderRadius: BorderRadius.circular(spec.isIlluminatedLedger ? 1 : 999),
        border: Border.all(color: color.withAlpha(150)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        child: Text(
          label,
          style: spec.typography.meta.copyWith(
            color: spec.palette.text,
            fontSize: 9.5,
            fontWeight: FontWeight.w800,
            height: 1,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
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
  final recipes =
      '${snapshot.recipeCount} recipe ${snapshot.recipeCount == 1 ? 'path' : 'paths'}';
  final routes = snapshot.entries.fold<int>(
    0,
    (sum, entry) => sum + entry.routes.length,
  );
  if (routes <= snapshot.recipeCount) return recipes;
  return '$recipes · $routes formula routes';
}

List<RecipeBookUseKind> _sortedKinds(Set<RecipeBookUseKind> kinds) =>
    kinds.toList()..sort((left, right) => left.index.compareTo(right.index));

String _routeMethod(RecipeBookUseRoute? route) {
  if (route == null) return '';
  final method = route.method?.trim() ?? '';
  return method.isNotEmpty ? method : _typeLabel(route.type);
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
