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
  Object? _projectionRecipes;
  Object? _projectionStorage;
  Map<String, double>? _projectionInventory;
  List<String>? _projectionCategories;
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
    widget.controller.plan.addListener(_planChanged);
    widget.controller.owner.deleteToolsEnabled.addListener(_deleteToolsChanged);
  }

  @override
  void didUpdateWidget(InventoryView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.controller, widget.controller)) {
      oldWidget.controller.state.removeListener(_modeStateChanged);
      oldWidget.controller.plan.removeListener(_planChanged);
      oldWidget.controller.owner.deleteToolsEnabled.removeListener(
        _deleteToolsChanged,
      );
      _renderedState = widget.controller.state.value;
      widget.controller.state.addListener(_modeStateChanged);
      widget.controller.plan.addListener(_planChanged);
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
    final state = widget.controller.state.value;
    final recipes = widget.controller.recipes;
    final cached = _projectionCache;
    if (cached != null &&
        identical(_projectionRecipes, recipes) &&
        identical(
          _projectionStorage,
          state.extensions[inventoryStorageExtensionKey],
        ) &&
        mapEquals(_projectionInventory, state.inventory) &&
        listEquals(_projectionCategories, state.customCategories)) {
      return cached;
    }
    final projection = InventoryProjection.assemble(widget.controller);
    _projectionRecipes = recipes;
    _projectionStorage = state.extensions[inventoryStorageExtensionKey];
    _projectionInventory = state.inventory;
    _projectionCategories = state.customCategories;
    return _projectionCache = projection;
  }

  @override
  void dispose() {
    _searchTimer?.cancel();
    widget.controller.state.removeListener(_modeStateChanged);
    widget.controller.plan.removeListener(_planChanged);
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

  Future<void> _clearInventory() async {
    final modeController = widget.controller;
    if (modeController.state.value.inventory.isEmpty) return;
    try {
      await modeController.owner.updateDocumentDurably((document) {
        final before = document.forMode(modeController.mode);
        return _replaceMode(
          document,
          modeController.mode,
          InventoryStorageState.fromModeState(
            before,
          ).clearQuantities().applyTo(before),
        );
      });
    } on Object catch (error) {
      _setStatus(
        'Inventory was not cleared because the change could not be saved. $error',
        error: true,
      );
      return;
    }
    if (!mounted || !identical(modeController, widget.controller)) return;
    setState(() {
      _invalidateUndo();
      _status = null;
      _statusIsError = false;
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
    if (!identical(widget.controller.state.value, snapshot.after)) {
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
        (document) =>
            _replaceMode(document, widget.controller.mode, snapshot.before),
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
    required double itemExtent,
  }) {
    final target = (fromIndex + delta).clamp(0, rows.length - 1);
    if (target == fromIndex) return;
    final name = rows[target].name;
    _session.selectedItem = name;
    final controller = _session.itemScrollController;
    if (controller.hasClients) {
      final offset = (target * itemExtent).clamp(
        controller.position.minScrollExtent,
        controller.position.maxScrollExtent,
      );
      controller.jumpTo(offset);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _rowFocusNodes[name]?.requestFocus();
      if (mounted) setState(() {});
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = _renderedState;
    final projection = _projection();
    final repaired = projection.repairCategory(_session.selectedCategory);
    if (_session.selectedCategory != repaired) {
      _session.selectedCategory = repaired;
      if (!_renameFocus.hasFocus) _renameGroupText.text = repaired;
    }
    final storage = InventoryStorageState.fromModeState(state);
    final currentPlanNames = _currentPlanItemNames();
    final filtered = projection.items
        .where((item) {
          if (!item.matches(_session.search)) return false;
          return switch (_session.displayFilter) {
            InventoryDisplayFilter.materials =>
              _session.search.isNotEmpty || !item.equipmentLike,
            InventoryDisplayFilter.owned => storage.totalFor(item.name) > 0,
            InventoryDisplayFilter.currentPlan => currentPlanNames.contains(
              _fold(item.name),
            ),
            InventoryDisplayFilter.all => true,
          };
        })
        .toList(growable: false);
    final originalCounts = <String, int>{};
    for (final item in filtered) {
      originalCounts[item.smartGroup] =
          (originalCounts[item.smartGroup] ?? 0) + 1;
    }
    String displayGroup(InventoryItemRecord item) =>
        (originalCounts[item.smartGroup] ?? 0) < 2
        ? 'Miscellaneous'
        : item.smartGroup;
    final groupCounts = <String, int>{};
    for (final item in filtered) {
      final group = displayGroup(item);
      groupCounts[group] = (groupCounts[group] ?? 0) + 1;
    }
    final families = groupCounts.keys.toList()..sort(_compareNames);
    if (_session.selectedSmartGroup != 'All materials' &&
        !families.any((family) => _same(family, _session.selectedSmartGroup))) {
      _session.selectedSmartGroup = 'All materials';
    }
    final rows = filtered
        .where(
          (item) =>
              _same(_session.selectedSmartGroup, 'All materials') ||
              _same(displayGroup(item), _session.selectedSmartGroup),
        )
        .toList(growable: false);
    return Semantics(
      container: true,
      explicitChildNodes: true,
      label: '${widget.controller.mode.label} Inventory',
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 900;
          final storageRail = _buildStorageRail(
            context,
            storage: storage,
            compact: compact,
          );
          final items = _buildStorageItemsPane(
            context,
            state: state,
            projection: projection,
            storage: storage,
            families: families,
            groupCounts: groupCounts,
            rows: rows,
          );
          if (compact) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                storageRail,
                const SizedBox(height: 10),
                Expanded(child: items),
              ],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              SizedBox(width: 244, child: storageRail),
              const SizedBox(width: 16),
              Expanded(child: items),
            ],
          );
        },
      ),
    );
  }

  Set<String> _currentPlanItemNames() {
    final plan = widget.controller.plan.value;
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

  Widget _buildStorageRail(
    BuildContext context, {
    required InventoryStorageState storage,
    required bool compact,
  }) {
    Widget locationButton(InventoryStorageLocation location) {
      final selected = location.id == storage.selectedLocation.id;
      final itemCount = location.quantities.values
          .where((quantity) => quantity > 0)
          .length;
      return AppButton(
        key: InventoryActionKeys.storage(location.id),
        role: AppButtonRole.navigation,
        selected: selected,
        showNavigationOrnament: false,
        minimumSize: Size(compact ? 168 : 0, 50),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        semanticLabel:
            '${location.name}, $itemCount saved ${itemCount == 1 ? 'item' : 'items'}',
        onPressed: () =>
            widget.controller.selectInventoryStorageLocation(location.id),
        child: Row(
          children: <Widget>[
            const Icon(Icons.warehouse_outlined, size: 19),
            const SizedBox(width: 9),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    location.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    '$itemCount ${itemCount == 1 ? 'item' : 'items'}',
                    style: context.visualTheme.typography.meta.copyWith(
                      fontStyle: FontStyle.normal,
                    ),
                  ),
                ],
              ),
            ),
            if (selected && _session.groupToolsOpen && !location.isUnassigned)
              AppButton.icon(
                icon: const AppVectorGlyph('edit', size: 14),
                semanticLabel: 'Rename ${location.name}',
                tooltip: 'Rename storage',
                onPressed: () => unawaited(_renameStorage(location)),
              ),
          ],
        ),
      );
    }

    final locations = <Widget>[
      for (final location in storage.locations) locationButton(location),
    ];
    return AppSurface(
      role: AppSurfaceRole.layout,
      semanticLabel: 'Inventory storage locations',
      padding: const EdgeInsets.all(11),
      child: compact
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        'Storage locations',
                        style: context.visualTheme.typography.body.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    AppButton.label(
                      'Add storage',
                      key: InventoryActionKeys.addStorage,
                      role: AppButtonRole.secondary,
                      minimumSize: const Size(0, 36),
                      onPressed: () => unawaited(_addStorage()),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: <Widget>[
                      for (
                        var index = 0;
                        index < locations.length;
                        index++
                      ) ...[
                        if (index > 0) const SizedBox(width: 8),
                        locations[index],
                      ],
                    ],
                  ),
                ),
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Text(
                  'Storage locations',
                  style: context.visualTheme.typography.body.copyWith(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 9),
                Expanded(
                  child: ListView.separated(
                    controller: _session.categoryScrollController,
                    itemCount: locations.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 7),
                    itemBuilder: (_, index) => locations[index],
                  ),
                ),
                const SizedBox(height: 9),
                AppButton.label(
                  'Add storage',
                  key: InventoryActionKeys.addStorage,
                  role: AppButtonRole.secondary,
                  onPressed: () => unawaited(_addStorage()),
                ),
              ],
            ),
    );
  }

  Widget _buildStorageItemsPane(
    BuildContext context, {
    required ModeState state,
    required InventoryProjection projection,
    required InventoryStorageState storage,
    required List<String> families,
    required Map<String, int> groupCounts,
    required List<InventoryItemRecord> rows,
  }) {
    final selectedLocation = storage.selectedLocation;
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
          const SizedBox(height: 8),
          LayoutBuilder(
            builder: (context, constraints) {
              final largeText = MediaQuery.textScalerOf(context).scale(14) > 20;
              final heading = Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      selectedLocation.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.visualTheme.typography.body.copyWith(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  if (_screenshotBusy)
                    const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                ],
              );
              if (largeText || constraints.maxWidth < 560) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    heading,
                    if (actionButtons.isNotEmpty) ...<Widget>[
                      const SizedBox(height: 8),
                      Align(
                        alignment: Alignment.centerRight,
                        child: Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          alignment: WrapAlignment.end,
                          children: actionButtons,
                        ),
                      ),
                    ],
                  ],
                );
              }
              return Row(
                children: <Widget>[
                  Expanded(child: heading),
                  if (actionButtons.isNotEmpty) const SizedBox(width: 9),
                  Wrap(spacing: 8, runSpacing: 8, children: actionButtons),
                ],
              );
            },
          ),
          const SizedBox(height: 10),
          Row(
            children: <Widget>[
              Expanded(
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
              ),
              const SizedBox(width: 10),
              AppButton(
                key: InventoryActionKeys.i04,
                role: AppButtonRole.secondary,
                selected: _session.groupToolsOpen,
                minimumSize: const Size(0, 38),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                semanticLabel:
                    '${_session.groupToolsOpen ? 'Hide' : 'Show'} Editor settings',
                onPressed: _toggleGroupTools,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    const AppVectorGlyph('edit', size: 16),
                    const SizedBox(width: 7),
                    Text(
                      _session.groupToolsOpen
                          ? 'Hide editor settings'
                          : 'Editor settings',
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 9),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: <Widget>[
                for (
                  var index = 0;
                  index < InventoryDisplayFilter.values.length;
                  index++
                ) ...<Widget>[
                  if (index > 0) const SizedBox(width: 7),
                  AppChoiceChip(
                    key: InventoryActionKeys.filter(
                      InventoryDisplayFilter.values[index].name,
                    ),
                    label: InventoryDisplayFilter.values[index].label,
                    selected:
                        _session.displayFilter ==
                        InventoryDisplayFilter.values[index],
                    onSelected: (_) {
                      setState(() {
                        _session.displayFilter =
                            InventoryDisplayFilter.values[index];
                        _session.selectedSmartGroup = 'All materials';
                        _session.selectedItem = null;
                      });
                    },
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: <Widget>[
                AppChoiceChip(
                  key: InventoryActionKeys.smartGroup('All materials'),
                  label: 'All materials',
                  selected: _same(_session.selectedSmartGroup, 'All materials'),
                  onSelected: (_) => setState(
                    () => _session.selectedSmartGroup = 'All materials',
                  ),
                ),
                for (final family in families) ...<Widget>[
                  const SizedBox(width: 7),
                  AppChoiceChip(
                    key: InventoryActionKeys.smartGroup(family),
                    label: '$family (${groupCounts[family]})',
                    selected: _same(_session.selectedSmartGroup, family),
                    onSelected: (_) =>
                        setState(() => _session.selectedSmartGroup = family),
                  ),
                ],
              ],
            ),
          ),
          if (_session.groupToolsOpen) ...<Widget>[
            const SizedBox(height: 10),
            _buildEditorSettings(context, state: state, projection: projection),
          ],
          if (_status != null || _session.undo != null) ...<Widget>[
            const SizedBox(height: 8),
            _buildStatus(context),
          ],
          const SizedBox(height: 8),
          Expanded(
            child: rows.isEmpty
                ? _InventoryEmptyState(
                    category: _session.selectedSmartGroup,
                    search: _session.search,
                  )
                : FocusTraversalGroup(
                    policy: OrderedTraversalPolicy(),
                    child: ListView.separated(
                      key: InventoryActionKeys.i14,
                      controller: _session.itemScrollController,
                      keyboardDismissBehavior:
                          ScrollViewKeyboardDismissBehavior.onDrag,
                      itemCount: rows.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 6),
                      itemBuilder: (context, index) {
                        final item = rows[index];
                        return InventoryStorageItemRow(
                          key: ValueKey<String>(
                            'inventory-storage-row:${selectedLocation.id}:${item.name}',
                          ),
                          controller: widget.controller,
                          item: item,
                          locationName: selectedLocation.name,
                          locationAmount: storage.quantityAt(
                            selectedLocation.id,
                            item.name,
                          ),
                          totalAmount: storage.totalFor(item.name),
                          index: index,
                          selected: _same(
                            _session.selectedItem ?? '',
                            item.name,
                          ),
                          onSelected: _selectRow,
                          onMoveFocus: (delta) => _moveRowFocus(
                            rows: rows,
                            fromIndex: index,
                            delta: delta,
                            itemExtent: 72,
                          ),
                          onRegisterFocus: _registerRowFocus,
                          onUnregisterFocus: _unregisterRowFocus,
                          onCopy: _copyName,
                          onCommitAmount: (text) {
                            _invalidateUndo();
                            return widget.controller
                                .setInventoryStorageQuantity(
                                  locationId: selectedLocation.id,
                                  itemName: item.name,
                                  text: text,
                                );
                          },
                          onEdit: _session.groupToolsOpen
                              ? () =>
                                    unawaited(_showItemEditor(item, projection))
                              : null,
                        );
                      },
                    ),
                  ),
          ),
        ],
      ),
    );
  }

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
        Row(
          children: <Widget>[
            SizedBox(
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
            const Spacer(),
            AppButton(
              key: InventoryActionKeys.i03,
              role: AppButtonRole.danger,
              minimumSize: const Size(0, 38),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              semanticLabel: 'I03 Clear all inventory amounts',
              onPressed: state.inventory.isEmpty ? null : _clearInventory,
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  AppVectorGlyph('reset', size: 16),
                  SizedBox(width: 7),
                  Text('Clear all amounts'),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        _buildGroupTools(context, state: state, projection: projection),
      ],
    );
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
      );
      if (!mounted || review == null) return;
      final modeController = widget.controller;
      final before = modeController.state.value;
      await modeController.owner.updateDocumentDurably((document) {
        final modeState = document.forMode(modeController.mode);
        final current = InventoryStorageState.fromModeState(modeState);
        final ensured = current.ensureLocation(review.locationName);
        final next = ensured.state.applyReviewedScreenshot(
          locationId: ensured.location.id,
          quantities: review.quantities,
          replaceMatchingUnassigned: !current.hadPersistedLedger,
        );
        return _replaceMode(
          document,
          modeController.mode,
          next.applyTo(modeState),
        );
      });
      if (!mounted || !identical(modeController, widget.controller)) return;
      final after = modeController.state.value;
      final count = review.quantities.length;
      final message =
          '$count ${count == 1 ? 'item' : 'items'} saved to ${review.locationName.trim()}.';
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

  Future<void> _addStorage() async {
    try {
      final name = await showDialog<String>(
        context: context,
        builder: (context) => const _InventoryNameDialog(
          title: 'Add storage',
          semanticLabel: 'Add storage location',
          fieldSemanticLabel: 'Storage or character name',
          hintText: 'Example: Calpheon City Storage',
          primaryLabel: 'Add',
        ),
      );
      if (!mounted || name == null || name.trim().isEmpty) return;
      widget.controller.ensureInventoryStorageLocation(name);
      _setStatus('${name.trim()} selected.');
    } on Object catch (error) {
      _setStatus('The storage was not added. $error', error: true);
    }
  }

  Future<void> _renameStorage(InventoryStorageLocation location) async {
    try {
      final name = await showDialog<String>(
        context: context,
        builder: (context) => _InventoryNameDialog(
          title: 'Rename storage',
          semanticLabel: 'Rename storage location',
          fieldSemanticLabel: 'Storage name',
          primaryLabel: 'Save',
          initialValue: location.name,
        ),
      );
      if (!mounted || name == null || name.trim().isEmpty) return;
      widget.controller.renameInventoryStorageLocation(location.id, name);
      _setStatus('Storage renamed to ${name.trim()}.');
    } on Object catch (error) {
      _setStatus('The storage was not renamed. $error', error: true);
    }
  }

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
                onPressed: _clearInventory,
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
                                  itemExtent: itemExtent,
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
  Widget build(BuildContext context) => Semantics(
    container: true,
    liveRegion: true,
    label: search.isEmpty
        ? '$category currently has no visible items.'
        : 'No $category items match "$search".',
    child: const SizedBox.expand(),
  );
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

int _compareNames(String left, String right) {
  final folded = _fold(left).compareTo(_fold(right));
  return folded != 0 ? folded : left.compareTo(right);
}

final class _InventoryNameDialog extends StatefulWidget {
  const _InventoryNameDialog({
    required this.title,
    required this.semanticLabel,
    required this.fieldSemanticLabel,
    required this.primaryLabel,
    this.hintText,
    this.initialValue = '',
  });

  final String title;
  final String semanticLabel;
  final String fieldSemanticLabel;
  final String primaryLabel;
  final String? hintText;
  final String initialValue;

  @override
  State<_InventoryNameDialog> createState() => _InventoryNameDialogState();
}

final class _InventoryNameDialogState extends State<_InventoryNameDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initialValue,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit([String? value]) =>
      Navigator.of(context).pop((value ?? _controller.text).trim());

  @override
  Widget build(BuildContext context) {
    final maximumHeight = (MediaQuery.sizeOf(context).height - 40).clamp(
      240.0,
      720.0,
    );
    return Dialog(
      backgroundColor: Colors.transparent,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 440, maxHeight: maximumHeight),
        child: AppSurface(
          role: AppSurfaceRole.modal,
          semanticLabel: widget.semanticLabel,
          padding: const EdgeInsets.all(16),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                SectionHeader(title: widget.title),
                const SizedBox(height: 12),
                AppTextField(
                  controller: _controller,
                  semanticLabel: widget.fieldSemanticLabel,
                  hintText: widget.hintText,
                  onSubmitted: _submit,
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
                      widget.primaryLabel,
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
