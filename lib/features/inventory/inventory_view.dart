import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../app/state/planner_application_controller.dart';
import '../../domain/models/craft_mode.dart';
import '../../domain/state/inventory_storage.dart';
import '../../domain/state/planner_state.dart';
import '../../domain/state/state_copy.dart';
import '../../domain/state/transactions/state_transactions.dart';
import '../../visual/visual.dart';
import 'inventory_action_keys.dart';
import 'inventory_contracts.dart';
import 'inventory_item_row.dart';
import 'inventory_projection.dart';
import 'inventory_screenshot_import_dialog.dart';
import 'inventory_screenshot_recognition.dart';
import 'inventory_session.dart';
import 'inventory_storage_item_row.dart';

class InventoryView extends StatefulWidget {
  const InventoryView({
    required this.controller,
    required this.externalActions,
    this.sessionController,
    this.transactions = const PlannerStateTransactions(),
    this.searchDebounce = const Duration(milliseconds: 160),
    this.sourceNoteDebounce = const Duration(milliseconds: 280),
    super.key,
  });

  final ModeFeatureController controller;
  final InventoryExternalActions externalActions;
  final InventorySessionController? sessionController;
  final PlannerStateTransactions transactions;
  final Duration searchDebounce;
  final Duration sourceNoteDebounce;

  @override
  State<InventoryView> createState() => _InventoryViewState();
}

class _InventoryViewState extends State<InventoryView> {
  late InventorySessionController _sessions;
  late bool _ownsSessions;
  late final TextEditingController _searchText = TextEditingController();
  late final TextEditingController _newGroupText = TextEditingController();
  late final TextEditingController _renameGroupText = TextEditingController();
  late final TextEditingController _groupItemText = TextEditingController();
  late final FocusNode _searchFocus = FocusNode()
    ..addListener(_searchFocusLost);
  late final FocusNode _renameFocus = FocusNode();
  final Map<String, FocusNode> _rowFocusNodes = <String, FocusNode>{};
  Timer? _searchTimer;
  String? _status;
  bool _statusIsError = false;
  InventoryProjection? _projectionCache;
  List<Object?>? _projectionRecipes;
  List<Object?>? _projectionStates;
  late ModeState _renderedState;
  bool _screenshotBusy = false;

  InventoryModeSession get _session =>
      _sessions.forMode(widget.controller.mode);

  @override
  void initState() {
    super.initState();
    _installSessions(widget.sessionController);
    _syncModeFields();
    _renderedState = widget.controller.state.value;
    widget.controller.state.addListener(_modeStateChanged);
    _listenToPlans(widget.controller.owner, add: true);
    widget.controller.owner.deleteToolsEnabled.addListener(_deleteToolsChanged);
    final prewarm = widget.externalActions.prewarmScreenshotRecognition;
    if (prewarm != null) {
      unawaited(prewarm().catchError((Object _) {}));
    }
  }

  @override
  void didUpdateWidget(InventoryView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.controller, widget.controller)) {
      oldWidget.controller.state.removeListener(_modeStateChanged);
      _listenToPlans(oldWidget.controller.owner, add: false);
      oldWidget.controller.owner.deleteToolsEnabled.removeListener(
        _deleteToolsChanged,
      );
      _renderedState = widget.controller.state.value;
      widget.controller.state.addListener(_modeStateChanged);
      _listenToPlans(widget.controller.owner, add: true);
      widget.controller.owner.deleteToolsEnabled.addListener(
        _deleteToolsChanged,
      );
    }
    if (!identical(oldWidget.sessionController, widget.sessionController)) {
      if (_ownsSessions) _sessions.dispose();
      _installSessions(widget.sessionController);
    }
    if (oldWidget.controller.mode != widget.controller.mode) {
      _searchTimer?.cancel();
      _syncModeFields();
      _rowFocusNodes.clear();
    }
  }

  void _modeStateChanged() {
    final next = widget.controller.state.value;
    final changed = !_sameInventoryPresentation(_renderedState, next);
    _renderedState = next;
    if (changed && mounted) setState(() {});
  }

  void _deleteToolsChanged() {
    if (mounted) setState(() {});
  }

  void _planChanged() {
    if (mounted) setState(() {});
  }

  void _listenToPlans(PlannerApplicationController owner, {required bool add}) {
    for (final modeController in owner.modes.values) {
      if (add) {
        modeController.plan.addListener(_planChanged);
      } else {
        modeController.plan.removeListener(_planChanged);
      }
    }
  }

  void _installSessions(InventorySessionController? supplied) {
    _ownsSessions = supplied == null;
    _sessions = supplied ?? InventorySessionController();
  }

  void _syncModeFields() {
    final modeSession = _session;
    _searchText.value = TextEditingValue(
      text: modeSession.search,
      selection: TextSelection.collapsed(offset: modeSession.search.length),
    );
    _renameGroupText.text = modeSession.selectedCategory;
    _newGroupText.clear();
    final groupItemText =
        modeSession.groupItemSelection ?? modeSession.groupItemQuery;
    _groupItemText.value = TextEditingValue(
      text: groupItemText,
      selection: TextSelection.collapsed(offset: groupItemText.length),
    );
  }

  InventoryProjection _projection() {
    final recipes = <Object?>[
      for (final mode in CraftMode.values)
        widget.controller.owner.modes[mode]!.recipes,
    ];
    final states = <Object?>[
      for (final mode in CraftMode.values)
        widget.controller.owner.modes[mode]!.state.value,
    ];
    final cached = _projectionCache;
    if (cached != null &&
        listEquals(_projectionRecipes, recipes) &&
        listEquals(_projectionStates, states)) {
      return cached;
    }
    final projection = InventoryProjection.assemble(widget.controller);
    _projectionRecipes = recipes;
    _projectionStates = states;
    return _projectionCache = projection;
  }

  @override
  void dispose() {
    _searchTimer?.cancel();
    widget.controller.state.removeListener(_modeStateChanged);
    _listenToPlans(widget.controller.owner, add: false);
    widget.controller.owner.deleteToolsEnabled.removeListener(
      _deleteToolsChanged,
    );
    _searchFocus
      ..removeListener(_searchFocusLost)
      ..dispose();
    _renameFocus.dispose();
    _searchText.dispose();
    _newGroupText.dispose();
    _renameGroupText.dispose();
    _groupItemText.dispose();
    if (_ownsSessions) _sessions.dispose();
    super.dispose();
  }

  void _setStatus(String message, {bool error = false}) {
    if (!mounted) return;
    setState(() {
      _status = message;
      _statusIsError = error;
    });
  }

  void _clearStatus() {
    if (_status == null) return;
    setState(() {
      _status = null;
      _statusIsError = false;
    });
  }

  void _onSearchChanged(String _) {
    _searchTimer?.cancel();
    _searchTimer = Timer(widget.searchDebounce, _commitSearch);
  }

  void _searchFocusLost() {
    if (!_searchFocus.hasFocus) _commitSearch();
  }

  void _commitSearch([String? _]) {
    _searchTimer?.cancel();
    _searchTimer = null;
    final value = _searchText.text.trim();
    if (_session.search == value) return;
    setState(() => _session.search = value);
  }

  void _selectCategory(String category) {
    final normalized = normalizeInventoryCategory(category);
    if (normalized.isEmpty) return;
    setState(() {
      _session.selectedCategory = normalized;
      _session.selectedItem = null;
      _status = null;
      _statusIsError = false;
      if (!_renameFocus.hasFocus) {
        _renameGroupText.value = TextEditingValue(
          text: normalized,
          selection: TextSelection.collapsed(offset: normalized.length),
        );
      }
    });
  }

  void _toggleGroupTools() {
    setState(() => _session.groupToolsOpen = !_session.groupToolsOpen);
  }

  Future<void> _addGroup(InventoryProjection projection) async {
    final value = normalizeInventoryCategory(_newGroupText.text);
    if (value.isEmpty) return;
    final existing = projection.groups.where(
      (group) => _same(group.name, value),
    );
    if (existing.isNotEmpty) {
      _selectCategory(existing.first.name);
      _setStatus('${existing.first.name} already exists and is now selected.');
      return;
    }
    try {
      final result = widget.transactions.addCategory(
        state: widget.controller.owner.documentSnapshot,
        mode: widget.controller.mode,
        category: value,
      );
      if (result.changed) {
        await widget.controller.owner.updateDocumentDurably(
          (_) => result.state,
        );
      }
      if (!mounted) return;
      _invalidateUndo();
      _newGroupText.clear();
      _selectCategory(result.selectedCategory);
      final message = 'Group ${result.selectedCategory} added.';
      widget.externalActions.reportTransaction(
        InventoryTransactionNotice(operation: 'add-category', message: message),
      );
      _setStatus(message);
    } on StateTransactionFailure catch (error) {
      _setStatus(error.message, error: true);
    } on Object catch (error) {
      _setStatus(
        'The group was not added because it could not be saved. $error',
        error: true,
      );
    }
  }

  Future<void> _renameGroup(ModeState state) async {
    final oldValue = _session.selectedCategory;
    if (!_isCustomCategory(state, oldValue)) {
      _setStatus(
        'Only custom groups can be renamed. Use item categories to override a built-in group.',
        error: true,
      );
      return;
    }
    final newValue = normalizeInventoryCategory(_renameGroupText.text);
    try {
      final result = widget.transactions.renameCategory(
        state: widget.controller.owner.documentSnapshot,
        mode: widget.controller.mode,
        oldCategory: oldValue,
        newCategory: newValue,
      );
      if (result.changed) {
        await widget.controller.owner.updateDocumentDurably(
          (_) => result.state,
        );
      }
      if (!mounted) return;
      _invalidateUndo();
      _selectCategory(result.selectedCategory);
      final message = 'Group renamed to ${result.selectedCategory}.';
      widget.externalActions.reportTransaction(
        InventoryTransactionNotice(
          operation: 'rename-category',
          message: message,
        ),
      );
      _setStatus(message);
    } on StateTransactionFailure catch (error) {
      _setStatus(error.message, error: true);
    } on Object catch (error) {
      _setStatus(
        'The group was not renamed because it could not be saved. $error',
        error: true,
      );
    }
  }

  Future<void> _resetOverrides() async {
    try {
      final result = widget.transactions.resetCategoryOverrides(
        state: widget.controller.owner.documentSnapshot,
        mode: widget.controller.mode,
        category: _session.selectedCategory,
      );
      final count = result.impact.affectedReferences.length;
      if (count > 0) {
        await widget.controller.owner.updateDocumentDurably(
          (_) => result.state,
        );
      }
      if (!mounted) return;
      _invalidateUndo();
      final message = count == 0
          ? 'No category overrides were set for this group.'
          : '$count category ${count == 1 ? 'override' : 'overrides'} reset.';
      widget.externalActions.reportTransaction(
        InventoryTransactionNotice(
          operation: result.impact.operation,
          message: message,
          result: result,
        ),
      );
      _setStatus(message);
    } on StateTransactionFailure catch (error) {
      _setStatus(error.message, error: true);
    } on Object catch (error) {
      _setStatus(
        'The category overrides were not reset because the change could not be saved. $error',
        error: true,
      );
    }
  }

  void _groupItemQueryChanged(String query) {
    final selected = _session.groupItemSelection;
    final clearSelection = selected != null && !_same(selected, query);
    if (_session.groupItemQuery == query && !clearSelection) return;
    setState(() {
      _session.groupItemQuery = query;
      if (clearSelection) _session.groupItemSelection = null;
    });
  }

  void _selectGroupItem(String itemName) {
    setState(() {
      _session.groupItemQuery = itemName;
      _session.groupItemSelection = itemName;
    });
  }

  Future<void> _addItemToSelectedGroup(InventoryProjection projection) async {
    final requested = _session.groupItemSelection ?? _groupItemText.text.trim();
    if (requested.isEmpty) return;
    InventoryItemRecord? selected;
    for (final item in projection.items) {
      if (_same(item.name, requested)) {
        selected = item;
        break;
      }
    }
    if (selected == null) return;
    final moved = await _changeCategory(
      selected,
      _session.selectedCategory,
      announce: false,
    );
    if (!mounted || !moved) return;
    setState(() {
      _session.groupItemQuery = '';
      _session.groupItemSelection = null;
      _groupItemText.clear();
    });
  }

  Future<void> _copyName(String name) async {
    try {
      await widget.externalActions.copyName(name);
    } on Object catch (error) {
      _setStatus('Could not copy $name. $error', error: true);
    }
  }

  bool _commitOwned(InventoryItemRecord item, String text) {
    _invalidateUndo();
    final accepted = widget.controller.commitInventory(item.name, text);
    // Avalonia keeps routine amount commits inside the row. Invalid text is
    // rejected by the controller and surfaced by InventoryItemRow's stable
    // field decoration; successful edits do not insert a status surface that
    // shifts every row below it.
    return accepted;
  }

  Future<bool> _changeCategory(
    InventoryItemRecord item,
    String category, {
    bool announce = true,
  }) async {
    final normalized = normalizeInventoryCategory(category);
    if (normalized.isEmpty || _same(normalized, item.category)) return false;
    final modeController = widget.controller;
    try {
      await modeController.owner.updateDocumentDurably((document) {
        final state = document.forMode(modeController.mode);
        final metadata = Map<String, IngredientMetadata>.of(
          state.ingredientMeta,
        );
        final entry = _metadataEntry(metadata, item.name);
        if (entry != null) metadata.remove(entry.key);
        metadata[item.name] = (entry?.value ?? IngredientMetadata()).copyWith(
          category: normalized,
        );
        return _replaceMode(
          document,
          modeController.mode,
          state.copyWith(ingredientMeta: metadata),
        );
      });
    } on Object catch (error) {
      _setStatus(
        '${item.name} was not moved because the category change could not be saved. $error',
        error: true,
      );
      return false;
    }
    if (!mounted || !identical(modeController, widget.controller)) {
      return false;
    }
    _invalidateUndo();
    if (announce) _setStatus('${item.name} moved to $normalized.');
    return true;
  }

  void _commitSourceNote(InventoryItemRecord item, String text) {
    _invalidateUndo();
    widget.controller.updateState((state) {
      final metadata = Map<String, IngredientMetadata>.of(state.ingredientMeta);
      final entry = _metadataEntry(metadata, item.name);
      if (entry != null) metadata.remove(entry.key);
      final source = entry?.value ?? IngredientMetadata();
      final trimmed = text.trim();
      final next = source.copyWith(
        sourceNote: trimmed.isEmpty ? null : trimmed,
      );
      if (!_metadataIsEmpty(next)) metadata[item.name] = next;
      return state.copyWith(ingredientMeta: metadata);
    });
    _setStatus('Source note updated for ${item.name}.');
  }

  Future<void> _hideOrDelete(InventoryItemRecord item) async {
    final modeController = widget.controller;
    try {
      final result = widget.transactions.hideInventoryItem(
        state: modeController.owner.documentSnapshot,
        mode: modeController.mode,
        itemName: item.name,
      );
      await modeController.owner.updateDocumentDurably((_) => result.state);
      if (!mounted || !identical(modeController, widget.controller)) return;
      setState(() {
        _invalidateUndo();
        if (_session.selectedItem != null &&
            _same(_session.selectedItem!, item.name)) {
          _session.selectedItem = null;
        }
        _status = null;
        _statusIsError = false;
      });
    } on StateTransactionFailure catch (error) {
      final conflicts = error.conflicts.isEmpty
          ? ''
          : ' Used by ${error.conflicts.join(', ')}.';
      _setStatus('${error.message}$conflicts', error: true);
    } on Object catch (error) {
      _setStatus(
        '${item.name} was not hidden because the change could not be saved. $error',
        error: true,
      );
    }
  }

  void _invalidateUndo() {
    _session.undo = null;
  }

  Future<InventoryUndoResult> _undoInline() async {
    final snapshot = _session.undo;
    if (snapshot == null) {
      return const InventoryUndoResult(
        operation: 'none',
        restored: false,
        message: 'No Inventory action is available to undo.',
      );
    }
    if (!identical(widget.controller.owner.documentSnapshot, snapshot.after)) {
      _session.undo = null;
      final result = InventoryUndoResult(
        operation: snapshot.operation,
        restored: false,
        message: 'This undo is no longer available after another change.',
      );
      widget.externalActions.reportUndo(result);
      _setStatus(result.message, error: true);
      return result;
    }
    try {
      await widget.controller.owner.updateDocumentDurably(
        (_) => snapshot.before,
      );
    } on Object catch (error) {
      final result = InventoryUndoResult(
        operation: snapshot.operation,
        restored: false,
        message:
            'Undo could not be saved, so the Inventory change remains in place. $error',
      );
      widget.externalActions.reportUndo(result);
      _setStatus(result.message, error: true);
      return result;
    }
    _session.selectedCategory = snapshot.selectedCategory;
    _session.undo = null;
    final result = InventoryUndoResult(
      operation: snapshot.operation,
      restored: true,
      message: '${snapshot.message} Undo complete.',
    );
    widget.externalActions.reportUndo(result);
    setState(() {
      _status = result.message;
      _statusIsError = false;
    });
    return result;
  }

  void _registerRowFocus(String name, FocusNode node) {
    _rowFocusNodes[name] = node;
  }

  void _unregisterRowFocus(String name, FocusNode node) {
    if (identical(_rowFocusNodes[name], node)) _rowFocusNodes.remove(name);
  }

  void _selectRow(String name) {
    if (!mounted) return;
    if (_same(_session.selectedItem ?? '', name)) return;
    setState(() => _session.selectedItem = name);
  }

  void _moveRowFocus({
    required List<InventoryItemRecord> rows,
    required int fromIndex,
    required int delta,
  }) {
    final target = (fromIndex + delta).clamp(0, rows.length - 1);
    if (target == fromIndex) return;
    final name = rows[target].name;
    _session.selectedItem = name;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final node = _rowFocusNodes[name];
      node?.requestFocus();
      if (node?.context case final rowContext?) {
        unawaited(
          Scrollable.ensureVisible(
            rowContext,
            alignment: 0.5,
            duration: const Duration(milliseconds: 140),
            curve: Curves.easeOutCubic,
          ),
        );
      }
      if (mounted) setState(() {});
    });
  }

  @override
  Widget build(BuildContext context) {
    final projection = _projection();
    final repaired = projection.repairCategory(_session.selectedCategory);
    if (_session.selectedCategory != repaired) {
      _session.selectedCategory = repaired;
      if (!_renameFocus.hasFocus) _renameGroupText.text = repaired;
    }
    final alchemyPlanNames = _planItemNames(CraftMode.alchemy);
    final cookingPlanNames = _planItemNames(CraftMode.cooking);
    final processingPlanNames = _planItemNames(CraftMode.processing);
    final filters = _session.displayFilters;
    final filtered = projection.items
        .where((item) {
          if (!item.matches(_session.search)) return false;
          if (item.equipmentLike) return false;
          if (filters.contains(InventoryDisplayFilter.all)) return true;
          if (filters.contains(InventoryDisplayFilter.owned)) {
            return item.owned > 0;
          }
          final foldedName = _fold(item.name);
          return (filters.contains(InventoryDisplayFilter.alchemyPlan) &&
                  alchemyPlanNames.contains(foldedName)) ||
              (filters.contains(InventoryDisplayFilter.cookingPlan) &&
                  cookingPlanNames.contains(foldedName)) ||
              (filters.contains(InventoryDisplayFilter.processingPlan) &&
                  processingPlanNames.contains(foldedName));
        })
        .toList(growable: false);
    return Semantics(
      container: true,
      explicitChildNodes: true,
      label: 'Inventory',
      child: _buildInventoryItemsPane(
        context,
        projection: projection,
        rows: filtered,
      ),
    );
  }

  Set<String> _planItemNames(CraftMode mode) {
    final plan = widget.controller.owner.modes[mode]!.plan.value;
    final names = <String>{};
    void add(String value) {
      final folded = _fold(value);
      if (folded.isNotEmpty) names.add(folded);
    }

    add(plan.target);
    for (final step in plan.steps) {
      add(step.name);
      for (final ingredient in step.ingredients) {
        add(ingredient.name);
      }
    }
    for (final missing in plan.missing) {
      add(missing.name);
    }
    return names;
  }

  void _toggleDisplayFilter(InventoryDisplayFilter filter) {
    setState(() {
      final selected = _session.displayFilters;
      if (filter == InventoryDisplayFilter.owned ||
          filter == InventoryDisplayFilter.all) {
        _session.displayFilters = <InventoryDisplayFilter>{filter};
      } else {
        selected
          ..remove(InventoryDisplayFilter.owned)
          ..remove(InventoryDisplayFilter.all);
        if (!selected.add(filter)) selected.remove(filter);
        if (selected.isEmpty) {
          selected.add(InventoryDisplayFilter.all);
        }
      }
      _session.selectedItem = null;
    });
  }

  Widget _buildInventoryItemsPane(
    BuildContext context, {
    required InventoryProjection projection,
    required List<InventoryItemRecord> rows,
  }) {
    final actionButtons = <Widget>[
      if (widget.externalActions.pasteScreenshot != null)
        AppButton(
          key: InventoryActionKeys.pasteScreenshot,
          role: AppButtonRole.primary,
          minimumSize: const Size(0, 38),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          semanticLabel: 'Paste and review inventory screenshot',
          onPressed: _screenshotBusy
              ? null
              : () => unawaited(
                  _runScreenshotImport(widget.externalActions.pasteScreenshot!),
                ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(Icons.content_paste_go_outlined, size: 18),
              SizedBox(width: 7),
              Text('Paste screenshot'),
            ],
          ),
        ),
      if (widget.externalActions.chooseScreenshot != null)
        AppButton(
          key: InventoryActionKeys.chooseScreenshot,
          role: AppButtonRole.secondary,
          minimumSize: const Size(0, 38),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          semanticLabel: 'Choose and review inventory screenshot',
          onPressed: _screenshotBusy
              ? null
              : () => unawaited(
                  _runScreenshotImport(
                    widget.externalActions.chooseScreenshot!,
                  ),
                ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(Icons.image_outlined, size: 18),
              SizedBox(width: 7),
              Text('Choose image'),
            ],
          ),
        ),
    ];
    return AppSurface(
      role: AppSurfaceRole.layout,
      semanticLabel: 'Inventory item list',
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          SectionHeader(title: 'Inventory'),
          const SizedBox(height: 10),
          LayoutBuilder(
            builder: (context, constraints) {
              final largeText = MediaQuery.textScalerOf(context).scale(14) > 20;
              final search = ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 360),
                child: AppTextField(
                  key: InventoryActionKeys.i01,
                  controller: _searchText,
                  focusNode: _searchFocus,
                  semanticLabel: 'Search inventory items',
                  hintText: 'Search items',
                  suffixIcon: _searchText.text.isEmpty
                      ? null
                      : Center(
                          widthFactor: 1,
                          child: AppButton.icon(
                            icon: const AppVectorGlyph('close', size: 11),
                            semanticLabel: 'Clear inventory search',
                            tooltip: 'Clear inventory search',
                            onPressed: () {
                              _searchText.clear();
                              _commitSearch();
                            },
                          ),
                        ),
                  onChanged: _onSearchChanged,
                  onSubmitted: _commitSearch,
                ),
              );
              final actions = Wrap(
                spacing: 8,
                runSpacing: 8,
                alignment: WrapAlignment.end,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: <Widget>[
                  ...actionButtons,
                  if (_screenshotBusy)
                    Semantics(
                      liveRegion: true,
                      label: 'Reading screenshot',
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        child: const SizedBox.square(
                          dimension: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      ),
                    ),
                ],
              );
              if (largeText || constraints.maxWidth < 760) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    SizedBox(width: double.infinity, child: search),
                    const SizedBox(height: 9),
                    Align(alignment: Alignment.centerRight, child: actions),
                  ],
                );
              }
              return Row(
                children: <Widget>[
                  Expanded(
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: search,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Align(alignment: Alignment.centerRight, child: actions),
                ],
              );
            },
          ),
          const SizedBox(height: 9),
          Wrap(
            spacing: 7,
            runSpacing: 7,
            children: <Widget>[
              for (final filter in InventoryDisplayFilter.values)
                SizedBox(
                  width: _displayFilterWidth(context, filter),
                  child: AppChoiceChip(
                    key: InventoryActionKeys.filter(filter.name),
                    label: filter.label,
                    selected: _session.displayFilters.contains(filter),
                    onSelected: (_) => _toggleDisplayFilter(filter),
                  ),
                ),
            ],
          ),
          if (_status != null || _session.undo != null) ...<Widget>[
            const SizedBox(height: 8),
            _buildStatus(context),
          ],
          const SizedBox(height: 8),
          Expanded(
            child: rows.isEmpty
                ? _InventoryEmptyState(
                    category: _activeFilterLabel(),
                    search: _session.search,
                  )
                : _buildGroupedInventoryItems(context, rows: rows),
          ),
        ],
      ),
    );
  }

  double _displayFilterWidth(
    BuildContext context,
    InventoryDisplayFilter filter,
  ) {
    final textScale = (MediaQuery.textScalerOf(context).scale(13) / 13).clamp(
      1.0,
      2.0,
    );
    final baseWidth = switch (filter) {
      InventoryDisplayFilter.owned || InventoryDisplayFilter.all => 94.0,
      InventoryDisplayFilter.alchemyPlan ||
      InventoryDisplayFilter.cookingPlan => 128.0,
      InventoryDisplayFilter.processingPlan => 142.0,
    };
    return baseWidth * textScale;
  }

  String _activeFilterLabel() {
    final filters = _session.displayFilters;
    if (filters.contains(InventoryDisplayFilter.owned)) return 'Owned items';
    if (filters.contains(InventoryDisplayFilter.all)) return 'Inventory items';
    final plans = <String>[
      if (filters.contains(InventoryDisplayFilter.alchemyPlan)) 'Alchemy plan',
      if (filters.contains(InventoryDisplayFilter.cookingPlan)) 'Cooking plan',
      if (filters.contains(InventoryDisplayFilter.processingPlan))
        'Processing plan',
    ];
    return plans.join(' and ');
  }

  Widget _buildGroupedInventoryItems(
    BuildContext context, {
    required List<InventoryItemRecord> rows,
  }) {
    final sections = _inventorySections(rows);
    return LayoutBuilder(
      builder: (context, constraints) {
        final largeText = MediaQuery.textScalerOf(context).scale(14) > 18;
        final columnCount = largeText
            ? 1
            : constraints.maxWidth >= 1160
            ? 3
            : constraints.maxWidth >= 720
            ? 2
            : 1;
        const columnSpacing = 8.0;

        Widget buildRow(InventoryItemRecord item, int index) =>
            InventoryStorageItemRow(
              key: ValueKey<String>('inventory-row:${item.name}'),
              controller: widget.controller,
              item: item,
              amount: item.owned,
              index: index,
              selected: _same(_session.selectedItem ?? '', item.name),
              onSelected: _selectRow,
              onMoveFocus: (delta) => _moveRowFocus(
                rows: rows,
                fromIndex: index,
                delta: delta * columnCount,
              ),
              onRegisterFocus: _registerRowFocus,
              onUnregisterFocus: _unregisterRowFocus,
              onCopy: _copyName,
              onCommitAmount: (text) {
                _invalidateUndo();
                return widget.controller.commitInventory(item.name, text);
              },
              onRemove: item.owned <= 0
                  ? null
                  : () => unawaited(_removeInventoryItem(itemName: item.name)),
            );

        var rowIndex = 0;
        final slivers = <Widget>[];
        for (final section in sections) {
          slivers.add(
            SliverToBoxAdapter(
              child: _InventorySectionHeading(
                key: ValueKey<String>('inventory-section:${section.name}'),
                title: section.name,
                itemCount: section.itemCount,
              ),
            ),
          );
          for (final subsection in section.subsections) {
            slivers.add(
              SliverToBoxAdapter(
                child: _InventorySubsectionHeading(
                  key: ValueKey<String>(
                    'inventory-subsection:${section.name}:${subsection.name}',
                  ),
                  title: subsection.name,
                  itemCount: subsection.items.length,
                ),
              ),
            );
            final firstIndex = rowIndex;
            rowIndex += subsection.items.length;
            final gridRowCount =
                (subsection.items.length + columnCount - 1) ~/ columnCount;
            slivers.add(
              SliverPadding(
                padding: const EdgeInsets.only(bottom: 10),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate((context, gridRowIndex) {
                    final rowStart = gridRowIndex * columnCount;
                    return Padding(
                      padding: EdgeInsets.only(
                        bottom: gridRowIndex == gridRowCount - 1 ? 0 : 6,
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          for (
                            var columnIndex = 0;
                            columnIndex < columnCount;
                            columnIndex++
                          ) ...<Widget>[
                            if (columnIndex > 0)
                              const SizedBox(width: columnSpacing),
                            Expanded(
                              child:
                                  rowStart + columnIndex <
                                      subsection.items.length
                                  ? buildRow(
                                      subsection.items[rowStart + columnIndex],
                                      firstIndex + rowStart + columnIndex,
                                    )
                                  : const SizedBox.shrink(),
                            ),
                          ],
                        ],
                      ),
                    );
                  }, childCount: gridRowCount),
                ),
              ),
            );
          }
        }
        if (widget
            .controller
            .owner
            .documentSnapshot
            .alchemy
            .inventory
            .isNotEmpty) {
          slivers.add(
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.only(top: 4, bottom: 2),
                child: Align(
                  alignment: Alignment.centerRight,
                  child: AppButton.label(
                    'Empty inventory',
                    key: InventoryActionKeys.emptyInventory,
                    role: AppButtonRole.danger,
                    onPressed: () => unawaited(_emptyInventory()),
                  ),
                ),
              ),
            ),
          );
        }
        return FocusTraversalGroup(
          policy: OrderedTraversalPolicy(),
          child: CustomScrollView(
            key: InventoryActionKeys.i14,
            controller: _session.itemScrollController,
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            slivers: slivers,
          ),
        );
      },
    );
  }

  // Retained for the dormant advanced editor flow; it is intentionally absent
  // from the primary Inventory page.
  // ignore: unused_element
  Widget _buildEditorSettings(
    BuildContext context, {
    required ModeState state,
    required InventoryProjection projection,
  }) {
    final categories = projection.groups
        .map((group) => group.name)
        .toList(growable: false);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Align(
          alignment: Alignment.centerLeft,
          child: SizedBox(
            width: 260,
            child: AppSelect<String>(
              value: _session.selectedCategory,
              items: categories,
              labelFor: (value) => value,
              semanticLabel: 'Editor group',
              onChanged: (value) {
                if (value != null) _selectCategory(value);
              },
            ),
          ),
        ),
        const SizedBox(height: 8),
        _buildGroupTools(context, state: state, projection: projection),
      ],
    );
  }

  Future<void> _removeInventoryItem({required String itemName}) async {
    final modeController = widget.controller;
    final before = modeController.owner.documentSnapshot;
    double? current;
    for (final entry in before.alchemy.inventory.entries) {
      if (_same(entry.key, itemName)) {
        current = entry.value;
        break;
      }
    }
    if (current == null || current <= 0) return;
    try {
      await modeController.owner.updateDocumentDurably(
        (document) =>
            setSharedInventoryAmounts(document, <String, double>{itemName: 0}),
      );
    } on Object catch (error) {
      _setStatus(
        '$itemName was not removed because the change could not be written. $error',
        error: true,
      );
      return;
    }
    if (!mounted || !identical(modeController, widget.controller)) return;
    final message = '$itemName removed from Inventory.';
    _offerInventoryUndo(
      operation: 'remove-inventory-item',
      message: message,
      before: before,
      after: modeController.owner.documentSnapshot,
    );
  }

  Future<void> _emptyInventory() async {
    final modeController = widget.controller;
    final before = modeController.owner.documentSnapshot;
    final itemCount = before.alchemy.inventory.length;
    if (itemCount == 0) return;
    final approved = await showDialog<bool>(
      context: context,
      builder: (context) => _EmptyInventoryDialog(itemCount: itemCount),
    );
    if (!mounted || approved != true) return;

    try {
      await modeController.owner.updateDocumentDurably(clearSharedInventory);
    } on Object catch (error) {
      _setStatus(
        'Inventory was not emptied because the change could not be written. $error',
        error: true,
      );
      return;
    }
    if (!mounted || !identical(modeController, widget.controller)) return;
    final message =
        '$itemCount ${itemCount == 1 ? 'item' : 'items'} removed from Inventory.';
    _offerInventoryUndo(
      operation: 'empty-inventory',
      message: message,
      before: before,
      after: modeController.owner.documentSnapshot,
    );
  }

  void _offerInventoryUndo({
    required String operation,
    required String message,
    required PlannerState before,
    required PlannerState after,
  }) {
    _session.undo = InventoryUndoSnapshot(
      operation: operation,
      message: message,
      before: before,
      after: after,
      selectedCategory: _session.selectedCategory,
    );
    widget.externalActions.offerUndo(
      InventoryUndoOffer(
        operation: operation,
        message: message,
        undo: _undoInline,
      ),
    );
    _setStatus(message);
  }

  Future<void> _runScreenshotImport(AcquireInventoryScreenshot acquire) async {
    if (_screenshotBusy) return;
    setState(() {
      _screenshotBusy = true;
      _status = null;
      _statusIsError = false;
    });
    InventoryScreenshotAnalysis? analysis;
    try {
      analysis = await acquire();
    } on Object catch (error) {
      if (mounted && _screenshotBusy) {
        setState(() => _screenshotBusy = false);
      }
      _setStatus('The screenshot could not be read. $error', error: true);
      return;
    }
    try {
      if (!mounted || analysis == null) return;
      setState(() => _screenshotBusy = false);
      final review = await showInventoryScreenshotImportDialog(
        context,
        controller: widget.controller,
        analysis: analysis,
        pasteAnother: widget.externalActions.pasteScreenshot,
        chooseAnother: widget.externalActions.chooseScreenshot,
      );
      if (!mounted || review == null) return;
      final modeController = widget.controller;
      final before = modeController.owner.documentSnapshot;
      await modeController.owner.updateDocumentDurably((document) {
        if (review.saveMode == InventoryScreenshotSaveMode.add) {
          return setSharedInventoryAmounts(
            document,
            review.quantities,
            add: true,
          );
        }
        return setSharedInventoryAmounts(
          clearSharedInventory(document),
          review.quantities,
        );
      });
      if (!mounted || !identical(modeController, widget.controller)) return;
      final after = modeController.owner.documentSnapshot;
      final count = review.quantities.length;
      final action = review.saveMode == InventoryScreenshotSaveMode.add
          ? 'added to Inventory'
          : 'saved in Inventory';
      final message = '$count ${count == 1 ? 'item' : 'items'} $action.';
      _session.undo = InventoryUndoSnapshot(
        operation: 'inventory-screenshot-import',
        message: message,
        before: before,
        after: after,
        selectedCategory: _session.selectedCategory,
      );
      widget.externalActions.offerUndo(
        InventoryUndoOffer(
          operation: 'inventory-screenshot-import',
          message: message,
          undo: _undoInline,
        ),
      );
      _setStatus(message);
    } on Object catch (error) {
      _setStatus(
        'The recognized items were not saved. Your previous amounts are unchanged. $error',
        error: true,
      );
    } finally {
      if (mounted && _screenshotBusy) {
        setState(() => _screenshotBusy = false);
      }
    }
  }

  // Retained for the dormant advanced editor flow; the compact Inventory page
  // uses direct amount editing instead.
  // ignore: unused_element
  Future<void> _showItemEditor(
    InventoryItemRecord item,
    InventoryProjection projection,
  ) async {
    final result = await showDialog<_InventoryItemEditorResult>(
      context: context,
      builder: (context) => _InventoryItemEditorDialog(
        itemName: item.name,
        initialCategory: item.category,
        initialSourceNote: item.sourceNote ?? '',
        categories: projection.groups
            .map((group) => group.name)
            .toList(growable: false),
      ),
    );
    if (!mounted || result == null) return;
    await _saveItemEditor(item, result);
  }

  Future<void> _saveItemEditor(
    InventoryItemRecord item,
    _InventoryItemEditorResult result,
  ) async {
    final modeController = widget.controller;
    try {
      await modeController.owner.updateDocumentDurably((document) {
        final state = document.forMode(modeController.mode);
        final metadata = Map<String, IngredientMetadata>.of(
          state.ingredientMeta,
        );
        final entry = _metadataEntry(metadata, item.name);
        if (entry != null) metadata.remove(entry.key);
        final category = normalizeInventoryCategory(result.category);
        final source = result.sourceNote.trim();
        final next = (entry?.value ?? IngredientMetadata()).copyWith(
          category: _same(category, item.bundledCategory) ? null : category,
          sourceNote: source.isEmpty ? null : source,
        );
        if (!_metadataIsEmpty(next)) metadata[item.name] = next;
        return _replaceMode(
          document,
          modeController.mode,
          state.copyWith(ingredientMeta: metadata),
        );
      });
      if (!mounted || !identical(modeController, widget.controller)) return;
      _setStatus('${item.name} settings saved.');
    } on Object catch (error) {
      _setStatus('${item.name} settings were not saved. $error', error: true);
    }
  }

  // Retained temporarily for the editor-only legacy group surface while the
  // compact storage layout settles.
  // ignore: unused_element
  Widget _buildCategoryRail(
    BuildContext context, {
    required InventoryProjection projection,
    required String selected,
  }) => AppSurface(
    role: AppSurfaceRole.layout,
    semanticLabel: 'Inventory category rail',
    padding: const EdgeInsets.all(12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Builder(
          builder: (context) {
            final referenceGeometry =
                MediaQuery.textScalerOf(context).scale(1) <= 1.25;
            final search = SizedBox(
              height: referenceGeometry ? 38 : null,
              child: AppTextField(
                key: InventoryActionKeys.i01,
                controller: _searchText,
                focusNode: _searchFocus,
                minimumHeight: referenceGeometry ? 38 : null,
                semanticLabel: 'I01 Search inventory names and metadata',
                hintText: 'Search inventory',
                suffixIcon: _searchText.text.isEmpty
                    ? null
                    : Center(
                        widthFactor: 1,
                        heightFactor: 1,
                        child: SizedBox.square(
                          dimension: 30,
                          child: AppButton(
                            role: AppButtonRole.optionPill,
                            minimumSize: Size.zero,
                            padding: EdgeInsets.zero,
                            semanticLabel: 'Clear inventory search',
                            tooltip: 'Clear inventory search',
                            onPressed: () {
                              _searchText.clear();
                              _commitSearch();
                            },
                            child: const AppVectorGlyph('close', size: 11),
                          ),
                        ),
                      ),
                onChanged: _onSearchChanged,
                onSubmitted: _commitSearch,
              ),
            );
            final clear = SizedBox(
              width: referenceGeometry ? 91 : null,
              height: referenceGeometry ? 38 : null,
              child: AppButton(
                key: InventoryActionKeys.i03,
                role: AppButtonRole.secondary,
                minimumSize: referenceGeometry
                    ? const Size(91, 38)
                    : const Size(0, 0),
                semanticLabel: 'I03 Clear Inventory',
                onPressed: () => unawaited(_emptyInventory()),
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    AppVectorGlyph('reset', size: 17),
                    SizedBox(width: 7),
                    Flexible(
                      child: Text(
                        'Clear',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            );
            if (!referenceGeometry) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[search, const SizedBox(height: 8), clear],
              );
            }
            return Row(
              children: <Widget>[
                Expanded(child: search),
                const SizedBox(width: 8),
                clear,
              ],
            );
          },
        ),
        const SizedBox(height: 12),
        Expanded(
          child: ScrollConfiguration(
            behavior: ScrollConfiguration.of(
              context,
            ).copyWith(scrollbars: false),
            child: ListView.builder(
              key: const PageStorageKey<String>('inventory-category-list'),
              controller: _session.categoryScrollController,
              itemCount: projection.groups.length,
              itemBuilder: (context, index) {
                final group = projection.groups[index];
                final active = _same(group.name, selected);
                final spec = context.visualTheme;
                final ledger = spec.isIlluminatedLedger;
                final denseLayout = spec.usesDenseSplitLayout;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: AppButton(
                    key: InventoryActionKeys.group(group.name),
                    role: AppButtonRole.navigation,
                    selected: active,
                    showNavigationOrnament: false,
                    minimumSize: const Size(0, 56),
                    padding: EdgeInsets.symmetric(
                      horizontal: 13,
                      vertical: denseLayout ? 7 : 10,
                    ),
                    semanticLabel:
                        'I02 Select ${group.name}, ${group.itemCount} items',
                    onPressed: () => _selectCategory(group.name),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          if (denseLayout)
                            SizedBox(
                              width: double.infinity,
                              height: 18,
                              child: FittedBox(
                                alignment: Alignment.centerLeft,
                                fit: BoxFit.scaleDown,
                                child: Text(
                                  group.name,
                                  maxLines: 1,
                                  style: spec.typography.body.copyWith(
                                    fontFamily: ledger
                                        ? 'Georgia'
                                        : spec.typography.body.fontFamily,
                                    fontSize: 16,
                                    fontWeight: FontWeight.w700,
                                    height: 1.1,
                                  ),
                                ),
                              ),
                            )
                          else
                            Text(
                              group.name,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: spec.typography.body.copyWith(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          const SizedBox(height: 3),
                          Text(
                            '${group.itemCount} items',
                            style: spec.typography.meta.copyWith(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              fontStyle: FontStyle.normal,
                              height: denseLayout ? 1.1 : null,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ],
    ),
  );

  // ignore: unused_element
  Widget _buildItemsPane(
    BuildContext context, {
    required ModeState state,
    required InventoryProjection projection,
    required List<InventoryItemRecord> rows,
    required bool compact,
  }) => AppSurface(
    role: AppSurfaceRole.layout,
    semanticLabel: 'Inventory item list',
    padding: const EdgeInsets.all(12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Builder(
          builder: (context) {
            final denseLayout = context.visualTheme.usesDenseSplitLayout;
            final toggle = AppButton(
              key: InventoryActionKeys.i04,
              role: AppButtonRole.secondary,
              minimumSize: const Size(0, 38),
              padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
              semanticLabel:
                  'I04 ${_session.groupToolsOpen ? 'Hide' : 'Show'} Group Tools',
              onPressed: _toggleGroupTools,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  AppVectorGlyph(
                    _session.groupToolsOpen ? 'reset' : 'edit',
                    size: 17,
                  ),
                  const SizedBox(width: 7),
                  Text(
                    _session.groupToolsOpen
                        ? 'Hide group tools'
                        : 'Group tools',
                  ),
                ],
              ),
            );
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                SectionHeader(
                  title: 'Inventory',
                  trailing: denseLayout ? null : toggle,
                ),
                if (denseLayout) ...<Widget>[
                  const SizedBox(height: 5),
                  Align(alignment: Alignment.centerRight, child: toggle),
                ],
              ],
            );
          },
        ),
        if (_session.groupToolsOpen) ...<Widget>[
          const SizedBox(height: 10),
          _buildGroupTools(context, state: state, projection: projection),
        ],
        if (_status != null || _session.undo != null) ...<Widget>[
          const SizedBox(height: 8),
          _buildStatus(context),
        ],
        const SizedBox(height: 5),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final spec = context.visualTheme;
              final denseLayout = spec.usesDenseSplitLayout;
              final categories = projection.groups
                  .map((group) => group.name)
                  .toList(growable: false);
              final categoryWidth = AppSelect.readableWidthFor<String>(
                context,
                items: categories,
                labelFor: (value) => value,
                minimumWidth: 190,
                maximumWidth: 320,
              );
              final categoryGrowth = categoryWidth - 190;
              final maximumListWidth =
                  (denseLayout ? 870.0 : 710.0) + categoryGrowth;
              final contentWidth = constraints.maxWidth < maximumListWidth
                  ? constraints.maxWidth
                  : maximumListWidth;
              final textScale = MediaQuery.textScalerOf(context).scale(1);
              final rowCompact =
                  contentWidth < (denseLayout ? 660.0 : 710.0) ||
                  textScale > 1.25;
              final fixedStandardColumns = !denseLayout && !rowCompact;
              final scaledLineGrowth =
                  (MediaQuery.textScalerOf(context).scale(16) - 16).clamp(
                    0.0,
                    24.0,
                  );
              final itemExtent = switch ((rowCompact, fixedStandardColumns)) {
                (true, _) => 184.0 + scaledLineGrowth * 4.5,
                (false, true) => 114.0 + scaledLineGrowth * 3.25,
                _ => 116.0 + scaledLineGrowth * 3.25,
              };
              final rowBottomGap = rowCompact
                  ? 8.0
                  : fixedStandardColumns
                  ? 23.0
                  : 20.0;
              final Widget list = rows.isEmpty
                  ? _InventoryEmptyState(
                      category: _session.selectedCategory,
                      search: _session.search,
                    )
                  : FocusTraversalGroup(
                      policy: OrderedTraversalPolicy(),
                      child: ScrollConfiguration(
                        behavior: ScrollConfiguration.of(
                          context,
                        ).copyWith(scrollbars: false),
                        child: ListView.builder(
                          key: InventoryActionKeys.i14,
                          controller: _session.itemScrollController,
                          itemExtent: itemExtent,
                          itemCount: rows.length,
                          keyboardDismissBehavior:
                              ScrollViewKeyboardDismissBehavior.onDrag,
                          itemBuilder: (context, index) {
                            final item = rows[index];
                            return Padding(
                              padding: EdgeInsets.only(bottom: rowBottomGap),
                              child: InventoryItemRow(
                                key: ValueKey<String>(
                                  'inventory-row:${item.name}',
                                ),
                                controller: widget.controller,
                                item: item,
                                categories: projection.groups
                                    .map((group) => group.name)
                                    .toList(growable: false),
                                categoryWidth: categoryWidth,
                                index: index,
                                compact: rowCompact,
                                fixedStandardColumns: fixedStandardColumns,
                                selected: _same(
                                  _session.selectedItem ?? '',
                                  item.name,
                                ),
                                showDeleteTool: widget
                                    .controller
                                    .owner
                                    .documentSnapshot
                                    .showDeleteTools,
                                sourceNoteDebounce: widget.sourceNoteDebounce,
                                onRegisterFocus: _registerRowFocus,
                                onUnregisterFocus: _unregisterRowFocus,
                                onSelected: _selectRow,
                                onMoveFocus: (delta) => _moveRowFocus(
                                  rows: rows,
                                  fromIndex: index,
                                  delta: delta,
                                ),
                                onCopy: _copyName,
                                onCommitOwned: (text) =>
                                    _commitOwned(item, text),
                                onCategoryChanged: (category) =>
                                    _changeCategory(item, category),
                                onSourceNoteCommitted: (text) =>
                                    _commitSourceNote(item, text),
                                onHideOrDelete: () => _hideOrDelete(item),
                              ),
                            );
                          },
                        ),
                      ),
                    );
              return Align(
                alignment: Alignment.topLeft,
                child: SizedBox(
                  width: contentWidth,
                  height: constraints.maxHeight,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      if (!rowCompact)
                        _InventoryColumnHeader(
                          fixedStandardColumns: fixedStandardColumns,
                          categoryWidth: categoryWidth,
                        ),
                      Expanded(child: list),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    ),
  );

  Widget _buildGroupTools(
    BuildContext context, {
    required ModeState state,
    required InventoryProjection projection,
  }) {
    final custom = _isCustomCategory(state, _session.selectedCategory);
    final spec = context.visualTheme;
    final itemNames = projection.items.map((item) => item.name).toList()
      ..sort((left, right) {
        final folded = left.toLowerCase().compareTo(right.toLowerCase());
        return folded != 0 ? folded : left.compareTo(right);
      });
    Widget fieldLabel(String value) => Text(
      value.toUpperCase(),
      style: spec.typography.label.copyWith(
        color: spec.palette.textMuted,
        fontStyle: FontStyle.normal,
      ),
    );
    Widget iconLabel(String glyph, String label) => Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        AppVectorGlyph(glyph, size: 17),
        const SizedBox(width: 7),
        Flexible(
          child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
        ),
      ],
    );
    final renameField = SizedBox(
      height: 38,
      child: AppTextField(
        controller: _renameGroupText,
        focusNode: _renameFocus,
        semanticLabel: 'Rename selected inventory group',
        enabled: custom,
        onSubmitted: custom ? (_) => _renameGroup(state) : null,
      ),
    );
    final newGroupField = SizedBox(
      height: 38,
      child: AppTextField(
        controller: _newGroupText,
        hintText: 'Example: My daily cooking',
        semanticLabel: 'New inventory group name',
        onSubmitted: (_) => _addGroup(projection),
      ),
    );
    final addItemField = SizedBox(
      height: 38,
      child: AppSearchSelect<String>(
        key: InventoryActionKeys.i08Selector,
        controller: _groupItemText,
        items: itemNames,
        value: _session.groupItemSelection,
        labelFor: (item) => item,
        hintText: 'Search recipes and items',
        semanticLabel:
            'Select existing item to add to ${_session.selectedCategory}',
        onQueryChanged: _groupItemQueryChanged,
        onSelected: _selectGroupItem,
      ),
    );
    final renameButton = SizedBox(
      width: 116,
      height: 38,
      child: AppButton(
        key: InventoryActionKeys.i06,
        semanticLabel: custom
            ? 'I06 Rename selected custom group'
            : 'I06 Rename unavailable for built-in group',
        onPressed: custom ? () => _renameGroup(state) : null,
        minimumSize: const Size(116, 38),
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 7),
        child: iconLabel('edit', 'Rename'),
      ),
    );
    final resetButton = SizedBox(
      width: 166,
      height: 38,
      child: AppButton(
        key: InventoryActionKeys.i07,
        semanticLabel: 'I07 Reset selected category overrides',
        onPressed: _resetOverrides,
        minimumSize: const Size(166, 38),
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 7),
        child: iconLabel('reset', 'Reset overrides'),
      ),
    );
    final addGroupButton = SizedBox(
      width: 116,
      height: 38,
      child: AppButton(
        key: InventoryActionKeys.i05,
        semanticLabel: 'I05 Add normalized distinct group',
        role: AppButtonRole.primary,
        onPressed: () => _addGroup(projection),
        minimumSize: const Size(116, 38),
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 7),
        child: iconLabel('add', 'Add'),
      ),
    );
    final addItemButton = SizedBox(
      width: 116,
      height: 38,
      child: AppButton(
        key: InventoryActionKeys.i08,
        semanticLabel:
            'I08 Add selected existing item to ${_session.selectedCategory}',
        role: AppButtonRole.primary,
        onPressed: () => _addItemToSelectedGroup(projection),
        minimumSize: const Size(116, 38),
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 7),
        child: iconLabel('add', 'Add Item'),
      ),
    );
    return AppSurface(
      role: AppSurfaceRole.card,
      semanticLabel: 'Selected group tools',
      padding: const EdgeInsets.all(10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(
            'Selected Group',
            style: spec.typography.body.copyWith(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              height: 1.1,
            ),
          ),
          const SizedBox(height: 7),
          fieldLabel('Group name'),
          const SizedBox(height: 3),
          Row(
            children: <Widget>[
              Expanded(child: renameField),
              const SizedBox(width: 10),
              renameButton,
              const SizedBox(width: 10),
              resetButton,
            ],
          ),
          const SizedBox(height: 7),
          fieldLabel('New group'),
          const SizedBox(height: 3),
          Row(
            children: <Widget>[
              Expanded(child: newGroupField),
              const SizedBox(width: 10),
              addGroupButton,
              const SizedBox(width: 176),
            ],
          ),
          const SizedBox(height: 7),
          fieldLabel('Add item to this group'),
          const SizedBox(height: 3),
          Row(
            children: <Widget>[
              Expanded(child: addItemField),
              const SizedBox(width: 10),
              addItemButton,
              const SizedBox(width: 176),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatus(BuildContext context) {
    final undo = _session.undo;
    final tone = _statusIsError
        ? AppSurfaceTone.danger
        : undo == null
        ? AppSurfaceTone.info
        : AppSurfaceTone.success;
    return AppSurface(
      role: AppSurfaceRole.row,
      tone: tone,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      semanticLabel: _statusIsError
          ? 'Inventory error: $_status'
          : 'Inventory status: $_status',
      child: Row(
        children: <Widget>[
          Icon(
            _statusIsError
                ? Icons.error_outline
                : undo == null
                ? Icons.info_outline
                : Icons.undo,
            size: 18,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _status ?? undo?.message ?? '',
              style: context.visualTheme.typography.meta,
            ),
          ),
          if (undo != null)
            AppButton.label(
              'Undo',
              semanticLabel: 'Undo ${undo.operation}',
              onPressed: () => unawaited(_undoInline()),
              minimumSize: const Size(68, 32),
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
            )
          else
            AppButton.icon(
              icon: const Icon(Icons.close, size: 16),
              semanticLabel: 'Dismiss Inventory status',
              onPressed: _clearStatus,
            ),
        ],
      ),
    );
  }
}

List<_InventorySection> _inventorySections(List<InventoryItemRecord> items) {
  final grouped = <String, Map<String, List<InventoryItemRecord>>>{};
  for (final item in items) {
    grouped
        .putIfAbsent(item.section, () => <String, List<InventoryItemRecord>>{})
        .putIfAbsent(item.subsection, () => <InventoryItemRecord>[])
        .add(item);
  }
  return <_InventorySection>[
    for (final section in grouped.entries)
      _InventorySection(section.key, <_InventorySubsection>[
        for (final subsection in section.value.entries)
          _InventorySubsection(subsection.key, subsection.value),
      ]),
  ];
}

final class _InventorySection {
  const _InventorySection(this.name, this.subsections);

  final String name;
  final List<_InventorySubsection> subsections;

  int get itemCount => subsections.fold<int>(
    0,
    (total, subsection) => total + subsection.items.length,
  );
}

final class _InventorySubsection {
  const _InventorySubsection(this.name, this.items);

  final String name;
  final List<InventoryItemRecord> items;
}

class _InventorySectionHeading extends StatelessWidget {
  const _InventorySectionHeading({
    required this.title,
    required this.itemCount,
    super.key,
  });

  final String title;
  final int itemCount;

  @override
  Widget build(BuildContext context) {
    final spec = context.visualTheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 10, 2, 7),
      child: Row(
        children: <Widget>[
          Text(
            title,
            style: spec.typography.section.copyWith(
              fontSize: 20,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Divider(color: spec.palette.trim.withValues(alpha: 0.66)),
          ),
          const SizedBox(width: 9),
          Text(
            '$itemCount',
            style: spec.typography.meta.copyWith(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              fontStyle: FontStyle.normal,
            ),
          ),
        ],
      ),
    );
  }
}

class _InventorySubsectionHeading extends StatelessWidget {
  const _InventorySubsectionHeading({
    required this.title,
    required this.itemCount,
    super.key,
  });

  final String title;
  final int itemCount;

  @override
  Widget build(BuildContext context) {
    final spec = context.visualTheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(3, 3, 3, 6),
      child: Row(
        children: <Widget>[
          Text(
            title,
            style: spec.typography.body.copyWith(
              fontSize: 15,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(width: 7),
          Text(
            '$itemCount ${itemCount == 1 ? 'item' : 'items'}',
            style: spec.typography.meta.copyWith(fontStyle: FontStyle.normal),
          ),
        ],
      ),
    );
  }
}

class _InventoryColumnHeader extends StatelessWidget {
  const _InventoryColumnHeader({
    required this.fixedStandardColumns,
    required this.categoryWidth,
  });

  final bool fixedStandardColumns;
  final double categoryWidth;

  @override
  Widget build(BuildContext context) {
    final style = context.visualTheme.typography.label.copyWith(
      color: fixedStandardColumns
          ? const Color(0xFFBFAE72)
          : context.visualTheme.palette.secondary,
      fontSize: 11,
      fontWeight: FontWeight.w700,
    );
    Widget label(String value) => Align(
      alignment: Alignment.centerLeft,
      child: Text(value, maxLines: 1, style: style),
    );

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: <Widget>[
          const SizedBox(width: 64),
          if (fixedStandardColumns)
            SizedBox(width: 250, child: label('ITEM'))
          else
            Expanded(child: label('ITEM')),
          const SizedBox(width: 14),
          SizedBox(
            width: fixedStandardColumns ? 100 : 104,
            child: label('OWNED'),
          ),
          const SizedBox(width: 14),
          SizedBox(width: categoryWidth, child: label('GROUP')),
          const SizedBox(width: 60),
        ],
      ),
    );
  }
}

class _InventoryEmptyState extends StatelessWidget {
  const _InventoryEmptyState({required this.category, required this.search});

  final String category;
  final String search;

  @override
  Widget build(BuildContext context) {
    final scope = category.toLowerCase().endsWith('items')
        ? category
        : '$category items';
    return Semantics(
      container: true,
      liveRegion: true,
      label: search.isEmpty
          ? '$scope are currently empty.'
          : 'No $scope match "$search".',
      child: const SizedBox.expand(),
    );
  }
}

PlannerState _replaceMode(
  PlannerState document,
  CraftMode mode,
  ModeState state,
) => switch (mode) {
  CraftMode.alchemy => document.copyWith(alchemy: state),
  CraftMode.cooking => document.copyWith(cooking: state),
  CraftMode.processing => document.copyWith(processing: state),
};

MapEntry<String, IngredientMetadata>? _metadataEntry(
  Map<String, IngredientMetadata> values,
  String name,
) {
  for (final entry in values.entries) {
    if (_same(entry.key, name)) return entry;
  }
  return null;
}

bool _metadataIsEmpty(IngredientMetadata value) =>
    _blank(value.category) &&
    value.npcPrice <= 0 &&
    _blank(value.sourceNote) &&
    _blank(value.searchKeywords) &&
    _blank(value.vendor) &&
    _blank(value.location) &&
    _blank(value.marketId) &&
    _blank(value.qualityBase) &&
    _blank(value.qualityTier) &&
    value.extensions.isEmpty;

bool _blank(String? value) => value == null || value.trim().isEmpty;

bool _sameInventoryPresentation(ModeState left, ModeState right) =>
    mapEquals(left.inventory, right.inventory) &&
    identical(
      left.extensions[inventoryStorageExtensionKey],
      right.extensions[inventoryStorageExtensionKey],
    ) &&
    mapEquals(left.recipeEdits, right.recipeEdits) &&
    mapEquals(left.iconAliases, right.iconAliases) &&
    mapEquals(left.customIcons, right.customIcons) &&
    mapEquals(left.ingredientMeta, right.ingredientMeta) &&
    listEquals(left.customCategories, right.customCategories) &&
    setEquals(left.hiddenItems, right.hiddenItems);

bool _isCustomCategory(ModeState state, String category) =>
    state.customCategories.any((value) => _same(value, category));

bool _same(String left, String right) =>
    left.trim().toLowerCase() == right.trim().toLowerCase();

String _fold(String value) => value.trim().toLowerCase();

// Retained by the dormant category tools kept outside the primary page.
// ignore: unused_element
int _compareNames(String left, String right) {
  final folded = _fold(left).compareTo(_fold(right));
  return folded != 0 ? folded : left.compareTo(right);
}

final class _EmptyInventoryDialog extends StatelessWidget {
  const _EmptyInventoryDialog({required this.itemCount});

  final int itemCount;

  @override
  Widget build(BuildContext context) => Dialog(
    backgroundColor: Colors.transparent,
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 460),
      child: AppSurface(
        role: AppSurfaceRole.modal,
        semanticLabel: 'Confirm emptying Inventory',
        padding: const EdgeInsets.all(18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            const SectionHeader(title: 'Empty inventory?'),
            const SizedBox(height: 12),
            Text(
              'Remove all $itemCount saved ${itemCount == 1 ? 'item' : 'items'}?',
              style: context.visualTheme.typography.body.copyWith(fontSize: 15),
            ),
            const SizedBox(height: 16),
            Wrap(
              alignment: WrapAlignment.end,
              spacing: 8,
              runSpacing: 8,
              children: <Widget>[
                AppButton.label(
                  'Cancel',
                  onPressed: () => Navigator.of(context).pop(false),
                ),
                AppButton.label(
                  'Empty inventory',
                  key: InventoryActionKeys.confirmEmptyInventory,
                  role: AppButtonRole.danger,
                  onPressed: () => Navigator.of(context).pop(true),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}

final class _InventoryItemEditorDialog extends StatefulWidget {
  const _InventoryItemEditorDialog({
    required this.itemName,
    required this.initialCategory,
    required this.initialSourceNote,
    required this.categories,
  });

  final String itemName;
  final String initialCategory;
  final String initialSourceNote;
  final List<String> categories;

  @override
  State<_InventoryItemEditorDialog> createState() =>
      _InventoryItemEditorDialogState();
}

final class _InventoryItemEditorDialogState
    extends State<_InventoryItemEditorDialog> {
  late final TextEditingController _source = TextEditingController(
    text: widget.initialSourceNote,
  );
  late String _category = widget.initialCategory;

  @override
  void dispose() {
    _source.dispose();
    super.dispose();
  }

  void _submit() => Navigator.of(context).pop(
    _InventoryItemEditorResult(category: _category, sourceNote: _source.text),
  );

  @override
  Widget build(BuildContext context) {
    final maximumHeight = (MediaQuery.sizeOf(context).height - 40).clamp(
      280.0,
      760.0,
    );
    return Dialog(
      backgroundColor: Colors.transparent,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 540, maxHeight: maximumHeight),
        child: AppSurface(
          role: AppSurfaceRole.modal,
          semanticLabel: 'Edit ${widget.itemName}',
          padding: const EdgeInsets.all(16),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                const SectionHeader(title: 'Item settings'),
                const SizedBox(height: 10),
                Text(
                  widget.itemName,
                  style: context.visualTheme.typography.body.copyWith(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 12),
                AppSelect<String>(
                  value: _category,
                  items: widget.categories,
                  labelFor: (value) => value,
                  semanticLabel: 'Group for ${widget.itemName}',
                  onChanged: (value) {
                    if (value != null) setState(() => _category = value);
                  },
                ),
                const SizedBox(height: 10),
                AppTextField(
                  controller: _source,
                  semanticLabel: 'Source note for ${widget.itemName}',
                  hintText: 'Optional source note',
                ),
                const SizedBox(height: 14),
                Wrap(
                  alignment: WrapAlignment.end,
                  spacing: 8,
                  runSpacing: 8,
                  children: <Widget>[
                    AppButton.label(
                      'Cancel',
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                    AppButton.label(
                      'Save',
                      role: AppButtonRole.primary,
                      onPressed: _submit,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

final class _InventoryItemEditorResult {
  const _InventoryItemEditorResult({
    required this.category,
    required this.sourceNote,
  });

  final String category;
  final String sourceNote;
}
