import 'dart:async';
import 'dart:math' as math;
import 'package:bdo_map_core/bdo_map_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'recipe_worker_catalog.dart';
import 'recipe_worker_controller.dart';

typedef RecipeItemArtwork = Widget Function(String name, double size);

class RecipeWorkerPanel extends StatefulWidget {
  const RecipeWorkerPanel({
    required this.controller,
    required this.artwork,
    this.onGathering,
    this.checklist = false,
    this.hasSpot,
    this.onSpot,
    this.onClose,
    this.onSetup,
    this.onNode,
    this.hosted = false,
    super.key,
  });
  final RecipeWorkerController controller;
  final RecipeItemArtwork artwork;
  final VoidCallback? onGathering;
  final bool checklist;
  final bool Function(String name)? hasSpot;
  final ValueChanged<String>? onSpot;
  final VoidCallback? onClose, onSetup;
  final ValueChanged<String>? onNode;
  final bool hosted;
  @override
  State<RecipeWorkerPanel> createState() => _RecipeWorkerPanelState();
}

class _RecipeWorkerPanelState extends State<RecipeWorkerPanel> {
  late final _budget = TextEditingController(
    text: '${widget.controller.budget}',
  );
  Timer? _debounce;
  bool _pendingBudget = false;
  bool _pickerOpen = false, _investedOpen = false;
  bool _recipesExpanded = false;
  String _recipeQuery = '';
  String? _editingRecipe;
  final _collapsedGroups = <String>{};
  final _scrolls = <String, ScrollController>{};
  final _recipeSearchAnchor = GlobalKey();
  final _denied = <String, int>{};
  ScrollController _scroll(String key) => _scrolls.putIfAbsent(key, () {
    final value = ScrollController(
      initialScrollOffset: widget.controller.scrollOffsets[key] ?? 0,
    );
    value.addListener(
      () => widget.controller.scrollOffsets[key] = value.offset,
    );
    return value;
  });
  void _deny(String key) =>
      setState(() => _denied[key] = (_denied[key] ?? 0) + 1);
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(widget.controller.load());
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _budget.dispose();
    for (final controller in _scrolls.values) {
      controller.dispose();
    }
    super.dispose();
  }

  List<RecipeWorkerLeaf> get _manual => widget.controller.leaves.where((leaf) {
    if (leaf.vendor) return false;
    final data = widget.controller.data;
    final resource = data == null
        ? null
        : RecipeWorkerCatalog.resourceFor(leaf, data);
    if (resource != null &&
        data!.workerNodesForResource(resource.id).isNotEmpty) {
      return false;
    }
    return leaf.manual ||
        widget.hasSpot?.call(leaf.name) == true ||
        resource?.acquisitionModes.any(
              (m) => m != BdoAcquisitionMode.workerNode,
            ) ==
            true;
  }).toList();

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.controller,
    builder: (context, _) {
      final c = widget.controller;
      final p = context.mapChrome;
      final page = widget.checklist ? RecipeWorkerPage.recipe : c.page;
      final manual = widget.checklist ? _manual : const <RecipeWorkerLeaf>[];
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (widget.checklist ||
              (!widget.hosted && page != RecipeWorkerPage.recipe)) ...[
            _header(context, page, manual),
            const SizedBox(height: 10),
          ],
          if (!widget.checklist) ...[
            _budgetRow(context, page),
            const SizedBox(height: 12),
          ],
          if (!widget.checklist && page == RecipeWorkerPage.recipe) ...[
            _planActions(context),
            const SizedBox(height: 6),
          ],
          // These controls are outside the scrolling list, even in long plans.
          if (!widget.checklist && page == RecipeWorkerPage.nodes) ...[
            _investmentTabs(context),
            const SizedBox(height: 10),
          ],
          Flexible(
            fit: FlexFit.loose,
            child: ListView(
              key: ValueKey(
                'recipe-panel-${widget.checklist ? 'checklist' : page.name}-${page == RecipeWorkerPage.nodes ? _investedOpen : ''}',
              ),
              controller: _scroll(
                widget.checklist
                    ? 'checklist'
                    : page == RecipeWorkerPage.nodes
                    ? 'nodes-$_investedOpen'
                    : page.name,
              ),
              shrinkWrap: true,
              primary: false,
              padding: const EdgeInsets.all(4),
              children: [
                if (page == RecipeWorkerPage.recipe) ...[
                  if (widget.checklist)
                    _recipeShelf(context)
                  else if (_recipesExpanded)
                    _expandedRecipes(context),
                  if (_pickerOpen) _recipePicker(context),
                  if (widget.checklist || _recipesExpanded || _pickerOpen)
                    const SizedBox(height: 12),
                ],
                if (c.busy)
                  const Padding(
                    padding: EdgeInsets.only(bottom: 10),
                    child: LinearProgressIndicator(minHeight: 2),
                  ),
                if (c.error case final error?) ...[
                  Text(error, style: TextStyle(color: p.error)),
                  TextButton.icon(
                    onPressed: c.busy ? null : () => unawaited(c.reset()),
                    icon: const Icon(Icons.refresh, size: 18),
                    label: const Text('Try again'),
                  ),
                ],
                if (!widget.checklist && page == RecipeWorkerPage.items) ...[
                  TextFormField(
                    key: const ValueKey('recipe-workers-item-search'),
                    initialValue: c.itemQuery,
                    decoration: const InputDecoration(
                      hintText: 'Search items',
                      prefixIcon: Icon(Icons.search),
                    ),
                    onChanged: (v) => setState(() => c.itemQuery = v),
                  ),
                  const SizedBox(height: 10),
                  for (final r in c.addableItems.where(
                    (r) => r.name.toLowerCase().contains(
                      c.itemQuery.toLowerCase(),
                    ),
                  ))
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: _DeniedCard(
                        attempt: _denied[r.id] ?? 0,
                        child: _frame(
                          context,
                          child: Row(
                            children: [
                              _bay(context, r.name),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  r.name,
                                  style: TextStyle(
                                    color: p.text,
                                    fontSize: 15,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              IconButton(
                                key: ValueKey('recipe-extra-${r.id}'),
                                tooltip: 'Add ${r.name} node',
                                onPressed:
                                    c.busy || _pendingBudget || c.plan == null
                                    ? null
                                    : () async {
                                        final added = await c.addItem(r.id);
                                        if (mounted && !added) _deny(r.id);
                                      },
                                icon: const Icon(
                                  Icons.add_circle_outline,
                                  size: 20,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                ] else if (!widget.checklist &&
                    page == RecipeWorkerPage.nodes) ...[
                  for (final node in c.investmentNodes.where(
                    (n) => c.investedNodeIds.contains(n.id) == _investedOpen,
                  ))
                    _nodeRow(context, node),
                  if (!c.busy &&
                      !c.investmentNodes.any(
                        (n) =>
                            c.investedNodeIds.contains(n.id) == _investedOpen,
                      ))
                    Padding(
                      padding: const EdgeInsets.all(12),
                      child: Text(
                        _investedOpen
                            ? 'No invested nodes.'
                            : c.investmentNodes.isEmpty
                            ? 'No nodes selected.'
                            : 'All checked.',
                        style: TextStyle(color: p.muted),
                      ),
                    ),
                ] else if (widget.checklist)
                  for (final leaf in manual) _gatherRow(context, leaf)
                else ...[for (final group in c.groups) _group(context, group)],
                if (page == RecipeWorkerPage.recipe &&
                    !c.busy &&
                    c.targets.isNotEmpty &&
                    (widget.checklist ? manual.isEmpty : c.demands.isEmpty))
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 18),
                    child: Text(
                      widget.checklist
                          ? 'No hand-gathering ingredients.'
                          : 'No worker-node ingredients.',
                      style: TextStyle(color: p.muted, fontSize: 13),
                    ),
                  ),
              ],
            ),
          ),
          if (!widget.checklist && page == RecipeWorkerPage.recipe)
            Wrap(
              alignment: WrapAlignment.end,
              spacing: 8,
              children: [
                if (widget.onGathering != null)
                  TextButton.icon(
                    key: const ValueKey('recipe-workers-gathering'),
                    onPressed: widget.onGathering,
                    icon: const Icon(Icons.checklist_rounded, size: 19),
                    label: const Text('Gathering checklist'),
                  ),
                if (widget.onSetup != null)
                  IconButton(
                    tooltip: 'Worker settings',
                    onPressed: widget.onSetup,
                    icon: const Icon(Icons.settings_outlined, size: 19),
                  ),
              ],
            ),
        ],
      );
    },
  );

  Widget _header(
    BuildContext context,
    RecipeWorkerPage page,
    List<RecipeWorkerLeaf> manual,
  ) {
    final c = widget.controller, p = context.mapChrome;
    return Row(
      children: [
        if (page != RecipeWorkerPage.recipe)
          IconButton(
            tooltip: 'Back',
            onPressed: c.back,
            icon: const Icon(Icons.arrow_back, size: 20),
          )
        else
          Icon(Icons.checklist_rounded, size: 21, color: p.accent),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            widget.checklist ? 'Checklist' : c.pageTitle,
            style: TextStyle(
              fontSize: 19,
              fontWeight: FontWeight.w700,
              color: p.text,
            ),
          ),
        ),
        if (widget.checklist)
          Text(
            '${manual.where((l) => c.checkedItems.contains(l.name)).length} / ${manual.length}',
            style: TextStyle(fontSize: 13, color: p.muted),
          ),
        if (widget.checklist && widget.onClose != null)
          IconButton(
            tooltip: 'Close checklist',
            onPressed: widget.onClose,
            icon: const Icon(Icons.close, size: 20),
          ),
      ],
    );
  }

  Widget _budgetRow(BuildContext context, RecipeWorkerPage page) =>
      LayoutBuilder(
        builder: (context, constraints) {
          final c = widget.controller, p = context.mapChrome;
          final width = math.min(
            88 * MediaQuery.textScalerOf(context).scale(1),
            (constraints.maxWidth - 10) / 2,
          );
          final hasRecipes = page == RecipeWorkerPage.recipe;
          final inlineRecipes = constraints.maxWidth >= 2 * width + 20 + 76;
          final fields = <Widget>[
            SizedBox(
              width: width,
              child: _cpField(
                context,
                'CP budget',
                TextField(
                  key: const ValueKey('recipe-workers-budget'),
                  controller: _budget,
                  textAlign: TextAlign.center,
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(6),
                  ],
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: p.text,
                  ),
                  decoration: const InputDecoration(
                    isDense: true,
                    contentPadding: EdgeInsets.zero,
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    filled: false,
                  ),
                  onChanged: (text) {
                    _debounce?.cancel();
                    setState(() => _pendingBudget = true);
                    final value = int.tryParse(text);
                    if (value != null) {
                      _debounce = Timer(const Duration(milliseconds: 300), () {
                        if (!mounted) return;
                        setState(() => _pendingBudget = false);
                        unawaited(c.setBudget(value));
                      });
                    }
                  },
                  onTapOutside: (_) {
                    if (_budget.text.isEmpty) {
                      _budget.text = '${c.budget}';
                      setState(() => _pendingBudget = false);
                    }
                  },
                ),
              ),
            ),
            const SizedBox(width: 10),
            SizedBox(
              width: width,
              child: _cpField(
                context,
                'CP left',
                Text(
                  c.busy || _pendingBudget
                      ? '…'
                      : '${c.plan?.remaining ?? c.budget}',
                  key: const ValueKey('recipe-workers-remaining'),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: p.text,
                  ),
                ),
              ),
            ),
          ];
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  ...fields,
                  const Spacer(),
                  if (hasRecipes && inlineRecipes) _recipeSummary(context),
                ],
              ),
              if (hasRecipes && !inlineRecipes)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: _recipeSummary(context),
                  ),
                ),
            ],
          );
        },
      );

  Widget _recipeSummary(BuildContext context) {
    final c = widget.controller, p = context.mapChrome;
    final label = c.targets.isEmpty
        ? 'No recipes selected'
        : _recipesExpanded
        ? 'Hide recipes'
        : 'Show recipes';
    final enabled = c.catalog != null && !c.busy && !_pendingBudget;
    final buttonStyle = TextButton.styleFrom(
      padding: EdgeInsets.zero,
      minimumSize: Size.zero,
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      foregroundColor: p.accent,
    );
    return SizedBox(
      key: const ValueKey('recipe-workers-framed-pair'),
      width: 76,
      child: ResourceMapPill(
        selected: _recipesExpanded,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Semantics(
              expanded: _recipesExpanded,
              child: Tooltip(
                message: [label, ...c.targets].join('\n'),
                child: SizedBox(
                  height: 38,
                  child: TextButton(
                    key: const ValueKey('recipe-workers-summary'),
                    style: buttonStyle.copyWith(
                      shape: const WidgetStatePropertyAll(
                        RoundedRectangleBorder(
                          borderRadius: BorderRadius.vertical(
                            top: Radius.circular(7),
                          ),
                        ),
                      ),
                    ),
                    onPressed: c.targets.isEmpty ? null : _toggleRecipes,
                    child: Semantics(
                      label: [label, ...c.targets].join(', '),
                      excludeSemantics: true,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              if (c.targets.isEmpty)
                                Icon(
                                  Icons.menu_book_outlined,
                                  color: p.accent,
                                  size: 24,
                                ),
                              for (
                                var i = 0;
                                i < math.min(2, c.targets.length);
                                i++
                              ) ...[
                                if (i != 0) const SizedBox(width: 4),
                                widget.artwork(c.targets[i], 30),
                              ],
                            ],
                          ),
                          if (c.targets.length > 2)
                            Positioned(
                              right: 1,
                              bottom: 0,
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  color: p.controlInset,
                                  border: Border.all(color: p.accent),
                                  borderRadius: BorderRadius.circular(3),
                                ),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 2,
                                  ),
                                  child: Text(
                                    '+${c.targets.length - 2}',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: p.text,
                                    ),
                                  ),
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
            Divider(height: 1, thickness: 1, color: p.divider),
            Tooltip(
              message: 'Add recipe',
              child: SizedBox(
                height: 22,
                child: TextButton(
                  key: const ValueKey('recipe-workers-picker'),
                  style: buttonStyle.copyWith(
                    shape: const WidgetStatePropertyAll(
                      RoundedRectangleBorder(
                        borderRadius: BorderRadius.vertical(
                          bottom: Radius.circular(7),
                        ),
                      ),
                    ),
                  ),
                  onPressed: enabled ? _openRecipePicker : null,
                  child: const Icon(
                    Icons.add,
                    size: 17,
                    semanticLabel: 'Add recipe',
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _planActions(BuildContext context) {
    final c = widget.controller, p = context.mapChrome;
    final style = TextButton.styleFrom(
      minimumSize: const Size(0, 32),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      textStyle: Theme.of(context).textTheme.labelLarge?.copyWith(
        fontSize: 13,
        fontWeight: FontWeight.w600,
      ),
    );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Divider(height: 1, color: p.divider),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: Wrap(
              key: const ValueKey('recipe-workers-actions'),
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 6,
              runSpacing: 6,
              children: [
                ResourceMapPill(
                  child: TextButton.icon(
                    key: const ValueKey('recipe-workers-nodes'),
                    style: style,
                    onPressed: () => c.showPage(RecipeWorkerPage.nodes),
                    icon: const Icon(Icons.checklist_rounded, size: 17),
                    label: const Text('Nodes'),
                  ),
                ),
                TextButton.icon(
                  key: const ValueKey('recipe-workers-auto'),
                  style: style,
                  onPressed: c.busy || _pendingBudget || c.targets.isEmpty
                      ? null
                      : () => unawaited(c.reset()),
                  icon: const Icon(Icons.restart_alt, size: 17),
                  label: const Text('Auto'),
                ),
                TextButton.icon(
                  key: const ValueKey('recipe-workers-add-items'),
                  style: style,
                  onPressed: c.plan == null || c.busy || _pendingBudget
                      ? null
                      : () => c.showPage(RecipeWorkerPage.items),
                  icon: const Icon(Icons.add, size: 17),
                  label: const Text('Add items'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _expandedRecipes(BuildContext context) {
    final c = widget.controller, p = context.mapChrome;
    final enabled = c.catalog != null && !c.busy && !_pendingBudget;
    return Column(
      key: const ValueKey('recipe-workers-expanded'),
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final name in c.targets)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _frame(
              context,
              child: Row(
                key: ValueKey('recipe-shelf-$name'),
                children: [
                  _bay(context, name),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 9,
                      ),
                      child: Text(
                        name,
                        style: TextStyle(
                          color: p.text,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: IconButton(
                      key: ValueKey('recipe-remove-$name'),
                      tooltip: 'Remove $name from selection',
                      constraints: const BoxConstraints(
                        minWidth: 32,
                        minHeight: 32,
                      ),
                      padding: const EdgeInsets.all(6),
                      onPressed: enabled
                          ? () {
                              setState(() {
                                _pickerOpen = false;
                                _editingRecipe = null;
                                if (c.targets.length == 1) {
                                  _recipesExpanded = false;
                                }
                              });
                              unawaited(c.removeRecipe(name));
                            }
                          : null,
                      icon: const Icon(Icons.close, size: 18),
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _investmentTabs(BuildContext context) {
    final c = widget.controller;
    final done = c.investmentNodes
        .where((n) => c.investedNodeIds.contains(n.id))
        .length;
    return Row(
      children: [
        for (final invested in [false, true])
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(right: invested ? 0 : 6),
              child: ResourceMapPill(
                selected: _investedOpen == invested,
                child: TextButton(
                  key: ValueKey(
                    invested
                        ? 'recipe-workers-invested'
                        : 'recipe-workers-to-invest',
                  ),
                  onPressed: () => setState(() => _investedOpen = invested),
                  child: Text(
                    invested
                        ? 'Invested $done'
                        : 'To invest ${c.investmentNodes.length - done}',
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  void _revealRecipeControls({bool picker = false}) {
    if (widget.checklist) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final search = _recipeSearchAnchor.currentContext;
      if (picker && search != null) {
        unawaited(Scrollable.ensureVisible(search));
        return;
      }
      final scroll = _scrolls[RecipeWorkerPage.recipe.name];
      if (scroll != null && scroll.hasClients) scroll.jumpTo(0);
    });
  }

  void _toggleRecipes() {
    setState(() {
      _recipesExpanded = !_recipesExpanded;
      _pickerOpen = false;
      _editingRecipe = null;
    });
    if (_recipesExpanded) _revealRecipeControls();
  }

  void _openRecipePicker([String? replacing]) {
    setState(() {
      _pickerOpen = !_pickerOpen || _editingRecipe != replacing;
      _editingRecipe = replacing;
      _recipeQuery = '';
    });
    if (_pickerOpen) _revealRecipeControls(picker: true);
  }

  Widget _recipeShelf(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final c = widget.controller, p = context.mapChrome;
      final columns =
          (constraints.maxWidth /
                  (108 * MediaQuery.textScalerOf(context).scale(1)))
              .floor()
              .clamp(1, 3);
      final width = (constraints.maxWidth - (columns - 1) * 8) / columns;
      final enabled = c.catalog != null && !c.busy && !_pendingBudget;
      final labelStyle = TextStyle(
        color: p.text,
        fontSize: 13,
        fontWeight: FontWeight.w600,
      );
      var labelHeight = 0.0;
      for (final name in c.targets) {
        final measure = TextPainter(
          text: TextSpan(
            text: name,
            style: DefaultTextStyle.of(context).style.merge(labelStyle),
          ),
          textDirection: Directionality.of(context),
          textScaler: MediaQuery.textScalerOf(context),
        )..layout(maxWidth: width - 16);
        labelHeight = math.max(labelHeight, measure.height);
        measure.dispose();
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Divider(height: 12, color: p.divider),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final name in c.targets)
                SizedBox(
                  width: width,
                  child: _frame(
                    context,
                    leadingWidth: null,
                    child: Stack(
                      children: [
                        InkWell(
                          key: ValueKey('recipe-shelf-$name'),
                          onTap: enabled ? () => _openRecipePicker(name) : null,
                          borderRadius: BorderRadius.circular(7),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Container(
                                decoration: BoxDecoration(
                                  color: p.accent.withValues(
                                    alpha: .12 * p.materialOpacity,
                                  ),
                                  borderRadius: const BorderRadius.vertical(
                                    top: Radius.circular(7),
                                  ),
                                ),
                                padding: const EdgeInsets.symmetric(
                                  vertical: 9,
                                ),
                                alignment: Alignment.center,
                                child: widget.artwork(name, 34),
                              ),
                              Padding(
                                padding: const EdgeInsets.fromLTRB(8, 8, 8, 10),
                                child: SizedBox(
                                  height: labelHeight,
                                  child: Center(
                                    child: Text(
                                      name,
                                      textAlign: TextAlign.center,
                                      style: labelStyle,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        Positioned(
                          top: 0,
                          right: 0,
                          child: IconButton(
                            key: ValueKey('recipe-remove-$name'),
                            tooltip: 'Remove $name',
                            constraints: const BoxConstraints(
                              minWidth: 28,
                              minHeight: 28,
                            ),
                            padding: const EdgeInsets.all(4),
                            onPressed: enabled
                                ? () {
                                    setState(() => _pickerOpen = false);
                                    unawaited(c.removeRecipe(name));
                                  }
                                : null,
                            icon: const Icon(Icons.close, size: 15),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: SizedBox(
              width: math.min(
                168 * MediaQuery.textScalerOf(context).scale(1),
                constraints.maxWidth,
              ),
              child: OutlinedButton.icon(
                key: const ValueKey('recipe-workers-picker'),
                style: OutlinedButton.styleFrom(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(7),
                  ),
                ),
                onPressed: enabled ? _openRecipePicker : null,
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Add recipe'),
              ),
            ),
          ),
          Divider(height: 20, color: p.divider),
        ],
      );
    },
  );

  Widget _recipePicker(BuildContext context) {
    final c = widget.controller;
    final choices = (c.catalog?.targets ?? <String>[])
        .where(
          (name) =>
              (!c.targets.contains(name) || name == _editingRecipe) &&
              name.toLowerCase().contains(_recipeQuery.toLowerCase()),
        )
        .toList();
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            key: _recipeSearchAnchor,
            child: TextField(
              key: const ValueKey('recipe-workers-recipe-search'),
              decoration: InputDecoration(
                hintText: 'Find a recipe',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: IconButton(
                  tooltip: 'Close recipe choices',
                  onPressed: () => setState(() => _pickerOpen = false),
                  icon: const Icon(Icons.close),
                ),
              ),
              onChanged: (v) => setState(() => _recipeQuery = v),
            ),
          ),
          SizedBox(
            height: math.min(
              240,
              choices.length * 64.0 * MediaQuery.textScalerOf(context).scale(1),
            ),
            child: ListView.builder(
              key: const ValueKey('recipe-workers-inline-recipes'),
              primary: false,
              itemCount: choices.length,
              itemBuilder: (context, index) {
                final name = choices[index];
                return ListTile(
                  leading: widget.artwork(name, 32),
                  title: Text(name),
                  onTap: c.busy || _pendingBudget
                      ? null
                      : () {
                          final oldName = _editingRecipe;
                          setState(() => _pickerOpen = false);
                          unawaited(
                            oldName == null
                                ? c.addRecipe(name)
                                : c.replaceRecipe(oldName, name),
                          );
                        },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _group(BuildContext context, RecipeWorkerGroup group) {
    final p = context.mapChrome;
    final collapsed = _collapsedGroups.contains(group.id);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Semantics(
            expanded: !collapsed,
            child: InkWell(
              key: ValueKey('recipe-group-${group.id}'),
              onTap: () => setState(() {
                if (!_collapsedGroups.remove(group.id)) {
                  _collapsedGroups.add(group.id);
                }
              }),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Row(
                  children: [
                    if (group.id.startsWith('recipe:'))
                      widget.artwork(group.title, 25)
                    else
                      Icon(
                        group.id == 'shared'
                            ? Icons.layers_outlined
                            : Icons.add,
                        size: 21,
                        color: p.accent,
                      ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        group.title,
                        style: TextStyle(
                          color: p.text,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    if (group.id == 'shared')
                      Flexible(
                        child: Wrap(
                          spacing: 3,
                          runSpacing: 3,
                          children: [
                            for (final name in group.recipes)
                              Tooltip(
                                message: name,
                                child: widget.artwork(name, 23),
                              ),
                          ],
                        ),
                      ),
                    const SizedBox(width: 8),
                    Text(
                      '${group.demands.length}',
                      style: TextStyle(color: p.muted, fontSize: 12),
                    ),
                    const SizedBox(width: 4),
                    Icon(
                      collapsed ? Icons.chevron_right : Icons.expand_more,
                      color: p.muted,
                      size: 20,
                    ),
                  ],
                ),
              ),
            ),
          ),
          Divider(height: 1, color: p.divider),
          if (!collapsed) ...[
            const SizedBox(height: 8),
            for (final demand in group.demands)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _workerRow(context, demand),
              ),
          ],
        ],
      ),
    );
  }

  Widget _gatherRow(BuildContext context, RecipeWorkerLeaf leaf) {
    final c = widget.controller, p = context.mapChrome;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: _frame(
        context,
        child: Row(
          children: [
            _bay(context, leaf.name),
            Checkbox(
              value: c.checkedItems.contains(leaf.name),
              onChanged: (_) => c.toggle(leaf.name),
            ),
            Expanded(
              child: Text(
                leaf.name,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: p.text,
                ),
              ),
            ),
            if (_gardenNotes.containsKey(leaf.name))
              IconButton(
                tooltip: 'Plant in garden',
                onPressed: () => showDialog<void>(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: Text(leaf.name),
                    content: Text(_gardenNotes[leaf.name]!),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Close'),
                      ),
                    ],
                  ),
                ),
                icon: Image.asset(
                  'assets/app/gardening-reference.png',
                  width: 23,
                  height: 23,
                ),
              ),
            IconButton(
              tooltip: widget.hasSpot?.call(leaf.name) == true
                  ? 'Show gathering spot'
                  : 'No mapped spot',
              onPressed: widget.hasSpot?.call(leaf.name) == true
                  ? () => widget.onSpot?.call(leaf.name)
                  : null,
              icon: const Icon(Icons.location_on_outlined, size: 20),
            ),
          ],
        ),
      ),
    );
  }

  Widget _nodeRow(BuildContext context, BdoWorkerNode node) {
    final c = widget.controller;
    final p = context.mapChrome;
    final primaryOutputs = node.outputs
        .where((o) => o.isPrimary)
        .map((o) => o.name)
        .join(', ');
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: _frame(
        context,
        leadingWidth: null,
        child: Row(
          children: [
            Checkbox(
              key: ValueKey('recipe-invest-${node.id}'),
              value: c.investedNodeIds.contains(node.id),
              onChanged: (_) => c.toggleInvested(node.id),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      node.name,
                      style: TextStyle(
                        color: p.text,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      primaryOutputs.isEmpty ? node.nodeType : primaryOutputs,
                      style: TextStyle(color: p.muted, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ),
            Text(
              '${node.contributionPoints} CP',
              style: TextStyle(color: p.muted, fontSize: 12),
            ),
            if (widget.onNode != null)
              IconButton(
                tooltip: 'Show node',
                onPressed: () => widget.onNode!(node.id),
                icon: const Icon(Icons.location_on_outlined, size: 20),
              ),
            const SizedBox(width: 8),
          ],
        ),
      ),
    );
  }

  Widget _workerRow(
    BuildContext context,
    BdoWorkerRecipeDemand demand,
  ) => LayoutBuilder(
    builder: (context, constraints) {
      final c = widget.controller;
      final p = context.mapChrome;
      final stacked =
          constraints.maxWidth <
          255 * MediaQuery.textScalerOf(context).scale(1);
      final controls = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            key: ValueKey('recipe-workers-minus-${demand.id}'),
            tooltip: 'Remove ${demand.name} node',
            constraints: const BoxConstraints(minWidth: 32, minHeight: 36),
            padding: EdgeInsets.zero,
            onPressed: !_pendingBudget && c.canRemove(demand.id)
                ? () => unawaited(c.adjust(demand.id, add: false))
                : null,
            icon: const Icon(Icons.remove, size: 18),
          ),
          SizedBox(
            width: 26 * MediaQuery.textScalerOf(context).scale(1),
            child: Text(
              '${c.plan?.nodesFor(demand.id).length ?? 0}',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: p.text,
              ),
            ),
          ),
          GestureDetector(
            onTap:
                !_pendingBudget &&
                    !c.busy &&
                    !c.canAdd(demand.id) &&
                    (c.plan?.nodesFor(demand.id).length ?? 0) <
                        c.available(demand.id)
                ? () => _deny(demand.id)
                : null,
            child: IconButton(
              key: ValueKey('recipe-workers-plus-${demand.id}'),
              tooltip: c.canAdd(demand.id)
                  ? 'Add ${demand.name} node'
                  : c.plan?.nodesFor(demand.id).length == c.available(demand.id)
                  ? 'All available nodes selected'
                  : 'Not enough CP for another node',
              constraints: const BoxConstraints(minWidth: 32, minHeight: 36),
              padding: EdgeInsets.zero,
              onPressed: !_pendingBudget && c.canAdd(demand.id)
                  ? () => unawaited(c.adjust(demand.id, add: true))
                  : null,
              icon: const Icon(Icons.add, size: 18),
            ),
          ),
        ],
      );
      return _DeniedCard(
        attempt: _denied[demand.id] ?? 0,
        child: _frame(
          context,
          child: Row(
            children: [
              _bay(context, demand.name),
              const SizedBox(width: 10),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        demand.name,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: p.text,
                        ),
                      ),
                      Text(
                        c.available(demand.id) == 0
                            ? 'No baseline data'
                            : '${c.available(demand.id)} nodes available',
                        style: TextStyle(fontSize: 12, color: p.muted),
                      ),
                      if (stacked)
                        Align(
                          alignment: Alignment.centerRight,
                          child: controls,
                        ),
                    ],
                  ),
                ),
              ),
              if (!stacked) controls,
              const SizedBox(width: 5),
            ],
          ),
        ),
      );
    },
  );

  Widget _cpField(
    BuildContext context,
    String label,
    Widget value,
  ) => LayoutBuilder(
    builder: (context, constraints) {
      final style = DefaultTextStyle.of(
        context,
      ).style.copyWith(fontSize: 12, color: context.mapChrome.muted);
      final measure = TextPainter(
        text: TextSpan(text: 'CP budget', style: style),
        textDirection: Directionality.of(context),
        textScaler: MediaQuery.textScalerOf(context),
      )..layout(maxWidth: constraints.maxWidth);
      final labelHeight = measure.height;
      measure.dispose();
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: labelHeight,
            child: Align(
              alignment: Alignment.bottomLeft,
              child: Tooltip(
                message: label == 'CP budget'
                    ? 'CP for production nodes and their connections. Worker lodging is separate in Worker settings.'
                    : 'CP remaining after these nodes and connections.',
                child: Text(label, style: style),
              ),
            ),
          ),
          const SizedBox(height: 6),
          _frame(
            context,
            leadingWidth: null,
            child: SizedBox(
              key: ValueKey('recipe-workers-cp-field-$label'),
              height: 38 * MediaQuery.textScalerOf(context).scale(1),
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: value,
                ),
              ),
            ),
          ),
        ],
      );
    },
  );
  Widget _frame(
    BuildContext context, {
    required Widget child,
    double? leadingWidth = 52,
  }) => ResourceMapPill(leadingWidth: leadingWidth, child: child);

  Widget _bay(BuildContext context, String name) {
    return Container(
      width: 52,
      constraints: const BoxConstraints(minHeight: 58),
      alignment: Alignment.center,
      child: widget.artwork(name, 36),
    );
  }
}

const _gardenNotes = {
  'Amanita Mushroom': 'Plant Amanita Mushroom Hypha in a fenced garden.',
  'Ancient Mushroom': 'Plant Ancient Mushroom Hypha in a fenced garden.',
  'Bluffer Mushroom': 'Plant Bluffer Mushroom Hypha in a fenced garden.',
  'Hump Mushroom': 'Plant Hump Mushroom Hypha in a fenced garden.',
  'Truffle Mushroom':
      'Plant Truffle Mushroom Hypha in a fenced garden. Harvest only; this crop cannot be bred for more hypha.',
};

class _DeniedCard extends StatelessWidget {
  const _DeniedCard({required this.attempt, required this.child});
  final int attempt;
  final Widget child;
  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
    key: ValueKey(attempt),
    tween: Tween(begin: attempt == 0 ? 0 : 1, end: 0),
    duration: const Duration(milliseconds: 360),
    child: child,
    builder: (context, value, child) => Transform.translate(
      offset: Offset(
        MediaQuery.disableAnimationsOf(context)
            ? 0
            : math.sin(value * math.pi * 6) * value * 3,
        0,
      ),
      child: DecoratedBox(
        position: DecorationPosition.foreground,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: context.mapChrome.error.withValues(alpha: value),
            width: 1.5,
          ),
        ),
        child: child,
      ),
    ),
  );
}
