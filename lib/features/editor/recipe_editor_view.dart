import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/state/planner_application_controller.dart';
import '../../app/window/native_file_dialog_service.dart';
import '../../data/catalog/catalog_repository.dart';
import '../../data/icons/custom_icon_store.dart';
import '../../domain/models/craft_mode.dart';
import '../../domain/state/planner_state.dart';
import '../../domain/state/state_copy.dart';
import '../../domain/state/transactions/state_transactions.dart';
import '../../domain/state/user_source_notes.dart';
import '../../visual/visual.dart';
import 'editor_action_keys.dart';
import 'editor_contracts.dart';
import 'editor_models.dart';
import 'editor_projection.dart';
import 'editor_session.dart';

bool _usesDenseEditorGeometry(BuildContext context) =>
    context.visualTheme.usesDenseSplitLayout;

bool _usesCompactDenseTypePanel(BuildContext context) =>
    _usesDenseEditorGeometry(context) &&
    MediaQuery.sizeOf(context).width < 1480;

class RecipeEditorView extends StatefulWidget {
  const RecipeEditorView({
    required this.controller,
    required this.externalActions,
    required this.fileDialogs,
    required this.iconStore,
    this.sessionController,
    this.transactions = const PlannerStateTransactions(),
    this.searchDebounce = const Duration(milliseconds: 120),
    super.key,
  });

  final ModeFeatureController controller;
  final EditorExternalActions externalActions;
  final NativeFileDialogService fileDialogs;
  final CustomIconStore iconStore;
  final RecipeEditorSessionController? sessionController;
  final PlannerStateTransactions transactions;
  final Duration searchDebounce;

  @override
  State<RecipeEditorView> createState() => _RecipeEditorViewState();
}

class _RecipeEditorViewState extends State<RecipeEditorView> {
  late RecipeEditorSessionController _sessions;
  late bool _ownsSessions;
  late CatalogRepository _catalogRepository;
  late final TextEditingController _searchText = TextEditingController();
  late final TextEditingController _nameText = TextEditingController();
  late final TextEditingController _outputText = TextEditingController();
  late final TextEditingController _marketIdText = TextEditingController();
  late final TextEditingController _customCategoryText =
      TextEditingController();
  late final TextEditingController _customMethodText = TextEditingController();
  late final TextEditingController _vendorText = TextEditingController();
  late final TextEditingController _npcPriceText = TextEditingController();
  late final TextEditingController _locationText = TextEditingController();
  late final TextEditingController _sourceNoteText = TextEditingController();
  late final TextEditingController _searchKeywordsText =
      TextEditingController();
  late final FocusNode _searchFocus = FocusNode();
  late final FocusNode _nameFocus = FocusNode();
  late final ScrollController _itemScroll = ScrollController();
  late final ScrollController _formScroll = ScrollController();
  final ValueNotifier<String> _renameImpact = ValueNotifier<String>('');
  final List<_IngredientFields> _ingredientFields = <_IngredientFields>[];
  Timer? _searchTimer;
  RecipeEditorDraft? _draft;
  String? _status;
  bool _statusIsError = false;
  bool _busy = false;
  bool _syncing = false;

  RecipeEditorModeSession get _session =>
      _sessions.forMode(widget.controller.mode);

  @override
  void initState() {
    super.initState();
    _catalogRepository = CatalogRepository(widget.controller.owner.catalog);
    _installSessions(widget.sessionController);
    _syncSessionSearch();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _initializeDraft();
    });
  }

  @override
  void didUpdateWidget(RecipeEditorView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(
      oldWidget.controller.owner.catalog,
      widget.controller.owner.catalog,
    )) {
      _catalogRepository = CatalogRepository(widget.controller.owner.catalog);
    }
    if (!identical(oldWidget.sessionController, widget.sessionController)) {
      oldWidget.sessionController?.removeListener(_onSessionRequest);
      if (_ownsSessions) _sessions.dispose();
      _installSessions(widget.sessionController);
    }
    if (!identical(oldWidget.controller, widget.controller) ||
        oldWidget.controller.mode != widget.controller.mode) {
      _searchTimer?.cancel();
      _cleanupUncommittedIcon();
      _syncSessionSearch();
      _initializeDraft();
    }
  }

  void _installSessions(RecipeEditorSessionController? supplied) {
    _ownsSessions = supplied == null;
    _sessions = supplied ?? RecipeEditorSessionController();
    _sessions.addListener(_onSessionRequest);
  }

  void _onSessionRequest() {
    if (!mounted) return;
    final request = _sessions.takeFreshDraft(widget.controller.mode);
    if (request == null) return;
    _startNewRecipe(initialCategory: request.initialCategory);
  }

  void _initializeDraft() {
    final request = _sessions.takeFreshDraft(widget.controller.mode);
    if (request != null) {
      _startNewRecipe(initialCategory: request.initialCategory);
      return;
    }
    final projection = RecipeEditorProjection.fromController(widget.controller);
    if (projection.items.isEmpty) {
      _startNewRecipe();
      return;
    }
    final selected = _session.selectedName;
    final target = projection.canonicalItemName(
      selected ?? widget.controller.state.value.target,
    );
    _loadItem(target ?? projection.items.first.name);
  }

  void _syncSessionSearch() {
    _searchText.value = TextEditingValue(
      text: _session.search,
      selection: TextSelection.collapsed(offset: _session.search.length),
    );
  }

  @override
  void dispose() {
    _searchTimer?.cancel();
    _sessions.removeListener(_onSessionRequest);
    _cleanupUncommittedIcon();
    for (final fields in _ingredientFields) {
      fields.dispose();
    }
    _ingredientFields.clear();
    _searchText.dispose();
    _nameText.dispose();
    _outputText.dispose();
    _marketIdText.dispose();
    _customCategoryText.dispose();
    _customMethodText.dispose();
    _vendorText.dispose();
    _npcPriceText.dispose();
    _locationText.dispose();
    _sourceNoteText.dispose();
    _searchKeywordsText.dispose();
    _searchFocus.dispose();
    _nameFocus.dispose();
    _itemScroll.dispose();
    _formScroll.dispose();
    _renameImpact.dispose();
    if (_ownsSessions) _sessions.dispose();
    super.dispose();
  }

  void _onSearchChanged(String _) {
    _searchTimer?.cancel();
    _searchTimer = Timer(widget.searchDebounce, () {
      if (!mounted) return;
      final value = _searchText.text.trim();
      if (_session.search == value) return;
      setState(() => _session.search = value);
    });
  }

  void _loadItem(String name) {
    final projection = RecipeEditorProjection.fromController(widget.controller);
    final canonical = projection.canonicalItemName(name);
    if (canonical == null) return;
    final record = projection.items.firstWhere(
      (item) => sameEditorName(item.name, canonical),
    );
    final state = widget.controller.state.value;
    final edit = foldedEntry(state.recipeEdits, canonical);
    final recipeState = edit?.value ?? stateFromRecipe(record.recipe);
    final metadata =
        foldedEntry(state.ingredientMeta, canonical)?.value ??
        IngredientMetadata();
    final currentCategory = normalizeEditorCategory(
      metadata.category ?? recipeState.group ?? record.category,
    );
    final category = foldedValue(projection.categories, currentCategory);
    final currentMethod = recipeState.method?.trim() ?? '';
    final method = foldedValue(projection.methods, currentMethod);
    final icon = foldedEntry(state.customIcons, canonical)?.value;
    final marketAlias = foldedEntry(
      widget.controller.owner.plannerRules.marketNameAliases,
      canonical,
    )?.value;
    final bundledMarketId = _catalogRepository.bundledMarketId(
      canonical,
      aliases: <String>[?marketAlias],
    );
    final draft = RecipeEditorDraft(
      originalName: canonical,
      isNew: false,
      name: canonical,
      baseOutputText: formatEditorNumber(recipeState.baseOutput),
      marketId: _firstNonBlankEditorValue(<String?>[
        metadata.marketId,
        recipeState.marketId,
        bundledMarketId,
      ]),
      type:
          projection.typeChoices.any(
            (choice) => choice.value == recipeState.type,
          )
          ? recipeState.type
          : projection.typeChoices.first.value,
      category: category ?? '',
      categoryIsCustom: category == null && currentCategory.isNotEmpty,
      customCategory: category == null ? currentCategory : '',
      method: method ?? '',
      methodIsCustom: method == null && currentMethod.isNotEmpty,
      customMethod: method == null ? currentMethod : '',
      vendor: metadata.vendor ?? recipeState.vendor ?? '',
      npcPriceText: formatEditorNumber(
        metadata.npcPrice > 0 ? metadata.npcPrice : recipeState.npcPrice,
      ),
      location: metadata.location ?? recipeState.location ?? '',
      sourceNote: displayableUserSourceNote(state, canonical) ?? '',
      searchKeywords: metadata.searchKeywords ?? '',
      ingredients: <EditorIngredientDraft>[
        for (final ingredient in recipeState.ingredients)
          EditorIngredientDraft.fromState(ingredient),
      ],
      sourceRecipe: recipeState,
      sourceMetadata: metadata,
      originalIcon: icon,
      icon: icon,
    );
    if (draft.ingredients.isEmpty) {
      draft.ingredients.add(EditorIngredientDraft.empty());
    }
    _replaceDraft(draft);
    _session.selectedName = canonical;
  }

  void _startNewRecipe({String initialCategory = ''}) {
    _cleanupUncommittedIcon();
    final projection = RecipeEditorProjection.fromController(widget.controller);
    final normalizedCategory = normalizeEditorCategory(
      initialCategory.trim().isEmpty ? 'Base Items' : initialCategory,
    );
    final category = foldedValue(projection.categories, normalizedCategory);
    final type = projection.typeChoices.first.value;
    final source = RecipeState(type: type, baseOutput: 1);
    final draft = RecipeEditorDraft(
      originalName: null,
      isNew: true,
      name: 'New Recipe',
      baseOutputText: '1',
      marketId: '',
      type: type,
      category: category ?? '',
      categoryIsCustom: category == null && normalizedCategory.isNotEmpty,
      customCategory: category == null ? normalizedCategory : '',
      method: '',
      methodIsCustom: false,
      customMethod: '',
      vendor: '',
      npcPriceText: '0',
      location: '',
      sourceNote: '',
      searchKeywords: '',
      ingredients: <EditorIngredientDraft>[EditorIngredientDraft.empty()],
      sourceRecipe: source,
      sourceMetadata: IngredientMetadata(),
      originalIcon: null,
      icon: null,
    );
    _session.selectedName = null;
    _replaceDraft(draft);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _nameFocus.requestFocus();
    });
  }

  void _replaceDraft(RecipeEditorDraft draft) {
    _cleanupUncommittedIcon();
    _syncing = true;
    _draft = draft;
    _nameText.text = draft.name;
    _outputText.text = draft.baseOutputText;
    _marketIdText.text = draft.marketId;
    _customCategoryText.text = draft.customCategory;
    _customMethodText.text = draft.customMethod;
    _vendorText.text = draft.vendor;
    _npcPriceText.text = draft.npcPriceText;
    _locationText.text = draft.location;
    _sourceNoteText.text = draft.sourceNote;
    _searchKeywordsText.text = draft.searchKeywords;
    for (final fields in _ingredientFields) {
      fields.dispose();
    }
    _ingredientFields
      ..clear()
      ..addAll(draft.ingredients.map(_IngredientFields.new));
    _syncing = false;
    _updateRenameImpact();
    if (mounted) {
      setState(() {
        _status = null;
        _statusIsError = false;
      });
    }
  }

  void _markDirty() {
    if (_syncing || _draft == null) return;
    _draft!.dirty = true;
  }

  void _updateRenameImpact() {
    final draft = _draft;
    if (draft == null) {
      _renameImpact.value = '';
      return;
    }
    final nextName = _nameText.text.trim();
    if (nextName.isEmpty) {
      _renameImpact.value = 'A nonempty item name is required before saving.';
      return;
    }
    final projection = RecipeEditorProjection.fromController(widget.controller);
    final collision = projection.itemNames.where(
      (candidate) =>
          sameEditorName(candidate, nextName) &&
          (draft.originalName == null ||
              !sameEditorName(candidate, draft.originalName!)),
    );
    if (collision.isNotEmpty) {
      _renameImpact.value = 'Name conflicts with ${collision.first}.';
      return;
    }
    if (draft.originalName == null) {
      _renameImpact.value =
          'This draft creates a new ${widget.controller.mode.label} item.';
    } else if (draft.originalName != nextName) {
      _renameImpact.value =
          'Saving renames ${draft.originalName} and migrates its inventory, favorites, icons, metadata, market data, recipe links, and choices.';
    } else {
      _renameImpact.value = 'Changes remain in this draft until Save.';
    }
  }

  void _setStatus(String message, {bool error = false}) {
    if (!mounted) return;
    setState(() {
      _status = message;
      _statusIsError = error;
    });
  }

  void _selectType(String type) {
    final draft = _draft;
    if (draft == null || draft.type == type) return;
    setState(() {
      draft.type = type;
      draft.dirty = true;
    });
  }

  void _selectCategory(String? value) {
    final draft = _draft;
    if (draft == null || value == null) return;
    setState(() {
      draft.categoryIsCustom = value == editorCustomChoice;
      if (!draft.categoryIsCustom) draft.category = value;
      draft.dirty = true;
    });
    if (value == editorCustomChoice) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        FocusScope.of(context).nextFocus();
      });
    }
  }

  void _selectMethod(String? value) {
    final draft = _draft;
    if (draft == null || value == null) return;
    setState(() {
      draft.methodIsCustom = value == editorCustomChoice;
      if (!draft.methodIsCustom) draft.method = value;
      draft.dirty = true;
    });
  }

  void _addIngredient() {
    final draft = _draft;
    if (draft == null) return;
    final row = EditorIngredientDraft.empty();
    final fields = _IngredientFields(row);
    setState(() {
      draft.ingredients.add(row);
      _ingredientFields.add(fields);
      draft.dirty = true;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) fields.nameFocus.requestFocus();
    });
  }

  void _removeIngredient(int index) {
    final draft = _draft;
    if (draft == null || index < 0 || index >= draft.ingredients.length) return;
    setState(() {
      draft.ingredients.removeAt(index);
      _ingredientFields.removeAt(index).dispose();
      draft.dirty = true;
    });
  }

  Future<void> _chooseIcon() async {
    final draft = _draft;
    if (draft == null || _busy) return;
    setState(() => _busy = true);
    try {
      final path = await widget.fileDialogs.pickImageToOpen();
      if (!mounted || path == null) return;
      final imported = await widget.iconStore.importFile(File(path));
      if (!mounted) return;
      final previous = draft.icon;
      draft
        ..icon = imported
        ..iconChanged = true
        ..dirty = true;
      setState(() {});
      if (previous != null &&
          !_sameIcon(previous, draft.originalIcon) &&
          !_stateReferencesIcon(
            widget.controller.owner.documentSnapshot,
            previous,
          )) {
        unawaited(_safeRemoveIcon(previous));
      }
      _setStatus('Custom icon validated, normalized, and staged for Save.');
    } on CustomIconValidationException catch (error) {
      _setStatus(error.message, error: true);
    } on Object catch (error) {
      _setStatus('Could not import the selected icon. $error', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _removeIcon() {
    final draft = _draft;
    if (draft == null) return;
    final previous = draft.icon;
    setState(() {
      draft
        ..icon = null
        ..iconChanged = true
        ..dirty = true;
    });
    if (previous != null &&
        !_sameIcon(previous, draft.originalIcon) &&
        !_stateReferencesIcon(
          widget.controller.owner.documentSnapshot,
          previous,
        )) {
      unawaited(_safeRemoveIcon(previous));
    }
    _setStatus('Custom icon removal is staged for Save.');
  }

  Future<void> _save() async {
    final draft = _draft;
    if (draft == null || _busy) return;
    // Avalonia treats a blank recipe name as a silent no-op.
    if (_nameText.text.trim().isEmpty) return;
    final projection = RecipeEditorProjection.fromController(widget.controller);
    final validation = _validateDraft(draft, projection);
    if (validation case _EditorValidationFailure(:final message)) {
      _setStatus(message, error: true);
      return;
    }
    final valid = validation as _ValidatedEditorDraft;
    setState(() => _busy = true);
    final owner = widget.controller.owner;
    final mode = widget.controller.mode;
    final before = owner.documentSnapshot;
    final beforeIcon = draft.originalName == null
        ? null
        : foldedEntry(
            before.forMode(mode).customIcons,
            draft.originalName!,
          )?.value;
    try {
      StateTransactionResult? transaction;
      PlannerState nextDocument;
      final oldName = draft.originalName;
      if (oldName != null && oldName != valid.name) {
        transaction = widget.transactions.renameItem(
          state: before,
          mode: mode,
          oldName: oldName,
          newName: valid.name,
          existingItemNames: _allPersistentNames(widget.controller),
          bundledItem: _isBundled(widget.controller, oldName),
          replacementRecipe: valid.recipe,
        );
        final renamedRecipe =
            foldedEntry(
              transaction.state.forMode(mode).recipeEdits,
              valid.name,
            )?.value ??
            valid.recipe;
        nextDocument = _applySavedFields(
          transaction.state,
          mode: mode,
          name: valid.name,
          recipe: renamedRecipe,
          metadata: valid.metadata,
          icon: draft.icon,
          customCategory: valid.customCategory,
        );
      } else {
        nextDocument = _saveWithoutRename(
          before,
          mode: mode,
          name: valid.name,
          recipe: valid.recipe,
          metadata: valid.metadata,
          icon: draft.icon,
          customCategory: valid.customCategory,
        );
      }

      await owner.updateDocumentDurably((_) => nextDocument);
      await _invalidateUndo();

      if (beforeIcon != null &&
          !_sameIcon(beforeIcon, draft.icon) &&
          !_stateReferencesIcon(owner.documentSnapshot, beforeIcon)) {
        await WidgetsBinding.instance.endOfFrame;
        await _safeRemoveIcon(beforeIcon);
      }
      _session.selectedName = valid.name;
      _loadItem(valid.name);
      final operation = oldName == null
          ? 'create-recipe'
          : oldName != valid.name
          ? 'rename-recipe'
          : 'update-recipe';
      final message = '${valid.name} saved.';
      widget.externalActions.reportTransaction(
        EditorTransactionNotice(
          operation: operation,
          message: message,
          result: transaction,
        ),
      );
    } on StateTransactionFailure catch (error) {
      _setStatus(_transactionMessage(error), error: true);
    } on Object catch (error) {
      _setStatus('Recipe save failed. $error', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete() async {
    final draft = _draft;
    final selectedName = draft?.originalName;
    if (draft == null || _busy) return;
    if (selectedName == null) {
      final projection = RecipeEditorProjection.fromController(
        widget.controller,
      );
      final fallback = projection.canonicalItemName(
        widget.controller.state.value.target,
      );
      if (fallback != null) _loadItem(fallback);
      return;
    }
    final mode = widget.controller.mode;
    final document = widget.controller.owner.documentSnapshot;
    final dependent = _dependentRecipes(document.forMode(mode), selectedName);
    final bundled = _isBundled(widget.controller, selectedName);
    final approved = await widget.externalActions.confirmDelete(
      EditorDeleteRequest(
        mode: mode,
        itemName: selectedName,
        bundledItem: bundled,
        dependentRecipes: dependent,
      ),
    );
    if (!mounted || !approved) return;
    final fallback = _fallbackTarget(widget.controller, selectedName);
    if (fallback == null) {
      _setStatus(
        'No valid craftable target is available to repair this mode.',
        error: true,
      );
      return;
    }
    setState(() => _busy = true);
    final removedIcon = foldedEntry(
      document.forMode(mode).customIcons,
      selectedName,
    )?.value;
    try {
      final result = widget.transactions.deleteOrHideItem(
        state: document,
        mode: mode,
        itemName: selectedName,
        bundledItem: bundled,
        fallbackTarget: fallback,
      );
      await widget.controller.owner.updateDocumentDurably((_) => result.state);
      await _invalidateUndo();
      final verb = bundled ? 'hidden' : 'deleted';
      final message = '$selectedName $verb.';
      final snapshot = EditorUndoSnapshot(
        operation: result.impact.operation,
        message: message,
        before: document,
        selectedName: selectedName,
        icon: removedIcon,
      );
      _session.undo = snapshot;
      widget.externalActions.reportTransaction(
        EditorTransactionNotice(
          operation: result.impact.operation,
          message: message,
          result: result,
        ),
      );
      widget.externalActions.offerUndo(
        EditorUndoOffer(
          operation: result.impact.operation,
          message: message,
          undo: () => _undoDelete(snapshot),
        ),
      );
      final nextProjection = RecipeEditorProjection.fromController(
        widget.controller,
      );
      final nextName = nextProjection.canonicalItemName(
        result.state.forMode(mode).target,
      );
      if (nextName != null) {
        _loadItem(nextName);
      } else if (nextProjection.items.isNotEmpty) {
        _loadItem(nextProjection.items.first.name);
      } else {
        _startNewRecipe();
      }
    } on StateTransactionFailure catch (error) {
      _setStatus(_transactionMessage(error), error: true);
    } on Object catch (error) {
      _setStatus('Could not remove $selectedName. $error', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<EditorUndoResult> _undoDelete(EditorUndoSnapshot snapshot) async {
    if (!identical(_session.undo, snapshot)) {
      final result = EditorUndoResult(
        operation: snapshot.operation,
        restored: false,
        message: 'This Recipe Editor undo is no longer available.',
      );
      widget.externalActions.reportUndo(result);
      return result;
    }
    try {
      await widget.controller.owner.updateDocumentDurably(
        (_) => snapshot.before,
      );
    } on Object catch (error) {
      final result = EditorUndoResult(
        operation: snapshot.operation,
        restored: false,
        message:
            'The recipe could not be restored because the undo was not saved. $error',
      );
      widget.externalActions.reportUndo(result);
      return result;
    }
    _session.undo = null;
    if (mounted) _loadItem(snapshot.selectedName);
    final result = EditorUndoResult(
      operation: snapshot.operation,
      restored: true,
      message: '${snapshot.message} Undo complete.',
    );
    widget.externalActions.reportUndo(result);
    if (mounted) _setStatus(result.message);
    return result;
  }

  Future<void> _invalidateUndo() async {
    final previous = _session.undo;
    _session.undo = null;
    final icon = previous?.icon;
    if (icon != null &&
        !_stateReferencesIcon(widget.controller.owner.documentSnapshot, icon)) {
      await _safeRemoveIcon(icon);
    }
  }

  _EditorValidation _validateDraft(
    RecipeEditorDraft draft,
    RecipeEditorProjection projection,
  ) {
    final name = _nameText.text.trim();
    if (name.isEmpty) {
      return const _EditorValidationFailure('Enter a nonempty recipe name.');
    }
    final collision = _allPersistentNames(widget.controller).where(
      (candidate) =>
          sameEditorName(candidate, name) &&
          (draft.originalName == null ||
              !sameEditorName(candidate, draft.originalName!)),
    );
    if (collision.isNotEmpty) {
      return _EditorValidationFailure(
        'The name $name conflicts with ${collision.first}.',
      );
    }
    final output = parseEditorNumber(_outputText.text);
    if (output == null || output <= 0) {
      return const _EditorValidationFailure(
        'Base output must be a finite number greater than zero.',
      );
    }
    final npcPrice = parseEditorNumber(_npcPriceText.text);
    if (npcPrice == null || npcPrice < 0) {
      return const _EditorValidationFailure(
        'NPC price must be a finite nonnegative number.',
      );
    }
    if (!projection.typeChoices.any((choice) => choice.value == draft.type)) {
      return const _EditorValidationFailure(
        'Choose a recipe type supported by this mode.',
      );
    }

    final ingredients = <IngredientState>[];
    for (var index = 0; index < draft.ingredients.length; index++) {
      final row = draft.ingredients[index];
      final typedName = _ingredientFields[index].nameText.text.trim();
      final quantityText = _ingredientFields[index].quantityText.text.trim();
      if (typedName.isEmpty && quantityText.isEmpty) continue;
      if (typedName.isEmpty) {
        if (quantityText == '1' && row.name.trim().isEmpty) continue;
        return _EditorValidationFailure(
          'Ingredient ${index + 1} needs an item selection.',
        );
      }
      final canonical = projection.canonicalItemName(typedName);
      if (canonical == null) {
        return _EditorValidationFailure(
          'Ingredient ${index + 1} must select an existing item; "$typedName" was not found.',
        );
      }
      final quantity = parseEditorNumber(quantityText);
      if (quantity == null || quantity <= 0) {
        return _EditorValidationFailure(
          'Ingredient ${index + 1} quantity must be greater than zero.',
        );
      }
      ingredients.add(
        row.toState(canonicalName: canonical, quantity: quantity),
      );
    }

    var category = normalizeEditorCategory(
      draft.categoryIsCustom ? _customCategoryText.text : draft.category,
    );
    final canonicalCategory = foldedValue(projection.categories, category);
    if (canonicalCategory != null) category = canonicalCategory;
    var method = (draft.methodIsCustom ? _customMethodText.text : draft.method)
        .trim();
    final canonicalMethod = foldedValue(projection.methods, method);
    if (canonicalMethod != null) method = canonicalMethod;

    final sourceType = draft.sourceRecipe.type.trim().toLowerCase();
    final targetType = draft.type.trim().toLowerCase();
    final crossesProcessingBoundary =
        sourceType != targetType &&
        (sourceType == 'processing' || targetType == 'processing');
    final changesProcessingOutput =
        targetType == 'processing' &&
        (draft.isNew ||
            crossesProcessingBoundary ||
            (output - draft.sourceRecipe.baseOutput).abs() > .0000001);
    final preserveOutputBounds =
        !crossesProcessingBoundary && !changesProcessingOutput;

    final recipe = RecipeState(
      type: draft.type,
      baseOutput: output,
      role: draft.sourceRecipe.role,
      group: category.isEmpty ? null : category,
      method: method.isEmpty ? null : method,
      ingredients: ingredients,
      marketId: trimmedOrNull(_marketIdText.text),
      sourceNote: trimmedOrNull(_sourceNoteText.text),
      vendor: trimmedOrNull(_vendorText.text),
      location: trimmedOrNull(_locationText.text),
      npcPrice: npcPrice,
      qualityBase: draft.sourceRecipe.qualityBase,
      qualityGrade: draft.sourceRecipe.qualityGrade,
      outputMinimum: preserveOutputBounds
          ? draft.sourceRecipe.outputMinimum
          : null,
      outputMaximum: preserveOutputBounds
          ? draft.sourceRecipe.outputMaximum
          : null,
      extensions: draft.sourceRecipe.extensions,
    );
    final metadata = IngredientMetadata(
      category: category.isEmpty ? null : category,
      npcPrice: npcPrice,
      sourceNote: trimmedOrNull(_sourceNoteText.text),
      searchKeywords: trimmedOrNull(_searchKeywordsText.text),
      vendor: trimmedOrNull(_vendorText.text),
      location: trimmedOrNull(_locationText.text),
      marketId: trimmedOrNull(_marketIdText.text),
      qualityBase: draft.sourceMetadata.qualityBase,
      qualityTier: draft.sourceMetadata.qualityTier,
      extensions: draft.sourceMetadata.extensions,
    );
    return _ValidatedEditorDraft(
      name: name,
      recipe: recipe,
      metadata: metadata,
      customCategory: draft.categoryIsCustom && category.isNotEmpty
          ? category
          : null,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Shortcuts(
      shortcuts: const <ShortcutActivator, Intent>{
        SingleActivator(LogicalKeyboardKey.keyN, control: true):
            _NewRecipeIntent(),
        SingleActivator(LogicalKeyboardKey.keyS, control: true):
            _SaveRecipeIntent(),
      },
      child: Actions(
        actions: <Type, Action<Intent>>{
          _NewRecipeIntent: CallbackAction<_NewRecipeIntent>(
            onInvoke: (_) {
              _startNewRecipe();
              return null;
            },
          ),
          _SaveRecipeIntent: CallbackAction<_SaveRecipeIntent>(
            onInvoke: (_) {
              unawaited(_save());
              return null;
            },
          ),
        },
        child: FocusTraversalGroup(
          policy: ReadingOrderTraversalPolicy(),
          child: ValueListenableBuilder<ModeState>(
            valueListenable: widget.controller.state,
            builder: (context, _, _) => LayoutBuilder(
              builder: (context, constraints) {
                final stacked = constraints.maxWidth < 760;
                final list = _buildItemPane(stacked: stacked);
                final detail = _buildDetailPane();
                if (stacked) {
                  return Column(
                    children: <Widget>[
                      SizedBox(height: 220, child: list),
                      const SizedBox(height: 12),
                      Expanded(child: detail),
                    ],
                  );
                }
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    SizedBox(width: 350, child: list),
                    const SizedBox(width: 20),
                    Expanded(child: detail),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildItemPane({required bool stacked}) {
    final spec = context.visualTheme;
    final ledger = spec.isIlluminatedLedger;
    final sakura = spec.isSakuraNightGarden;
    final denseLayout = spec.usesDenseSplitLayout;
    final projection = RecipeEditorProjection.fromController(widget.controller);
    final filtered = projection.filtered(_session.search);
    final newRecipeButton = AppButton(
      key: EditorActionKeys.e03,
      role: AppButtonRole.primary,
      onPressed: _busy ? null : _startNewRecipe,
      semanticLabel: 'Create a new unsaved recipe draft',
      child: const Text('New Recipe'),
    );
    final list = ListView.separated(
      key: EditorActionKeys.e02,
      controller: _itemScroll,
      padding: EdgeInsets.zero,
      itemCount: filtered.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final item = filtered[index];
        final selected =
            _session.selectedName != null &&
            sameEditorName(_session.selectedName!, item.name);
        return _EditorRecipeButton(
          key: EditorActionKeys.item(item.name),
          selected: selected,
          onPressed: _busy ? null : () => _loadItem(item.name),
          semanticLabel:
              'Edit ${item.name}, ${item.craftable ? 'craftable' : 'base item'}, ${item.category}',
          child: Row(
            children: <Widget>[
              SizedBox(
                width: 42,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: _EditorIcon(
                    controller: widget.controller,
                    iconStore: widget.iconStore,
                    name: item.name,
                    size: 36,
                  ),
                ),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(
                      item.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: ledger
                            ? selected
                                  ? const Color(0xFFF7EAC7)
                                  : spec.palette.text
                            : sakura
                            ? spec.palette.text
                            : const Color(0xFFFFF0CD),
                        fontFamily: ledger
                            ? 'Georgia'
                            : spec.typography.body.fontFamily,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        height: denseLayout ? 1.16 : 1.1,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${item.category} / ${_typeLabel(item.recipe.type)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: ledger
                            ? selected
                                  ? const Color(0xFFF7EAC7)
                                  : spec.palette.text
                            : sakura
                            ? spec.palette.textMuted
                            : const Color(0xFFAFC1BA),
                        fontFamily: ledger
                            ? 'Georgia'
                            : spec.typography.meta.fontFamily,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        height: denseLayout ? 1.16 : 1.1,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
    return Semantics(
      container: true,
      label: 'Recipe Editor item browser',
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            _EditorTextField(
              key: EditorActionKeys.e01,
              controller: _searchText,
              focusNode: _searchFocus,
              hintText: 'Search editor',
              accented: true,
              height: 33,
              onChanged: _onSearchChanged,
              onSubmitted: (_) {
                _searchTimer?.cancel();
                final value = _searchText.text.trim();
                if (_session.search != value) {
                  setState(() => _session.search = value);
                }
              },
              semanticLabel: 'Search Recipe Editor items',
            ),
            if (denseLayout) const SizedBox(height: 6),
            if (denseLayout)
              SizedBox(width: double.infinity, child: newRecipeButton)
            else
              Align(alignment: Alignment.centerLeft, child: newRecipeButton),
            if (denseLayout) const SizedBox(height: 8),
            Expanded(
              child: filtered.isEmpty
                  ? Center(
                      child: Text(
                        'No items match this search.',
                        style: spec.typography.body.copyWith(
                          color: spec.palette.textMuted,
                        ),
                      ),
                    )
                  : _withoutPlatformScrollbar(list),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailPane() {
    final draft = _draft;
    final spec = context.visualTheme;
    if (draft == null) {
      return Semantics(
        label: 'Recipe Editor draft form',
        child: Center(
          child: Text('Preparing Recipe Editor…', style: spec.typography.body),
        ),
      );
    }
    if (spec.usesDenseSplitLayout) {
      final scrollingForm = SingleChildScrollView(
        controller: _formScroll,
        padding: EdgeInsets.zero,
        child: LayoutBuilder(
          builder: (context, constraints) =>
              _buildEditorForm(draft, constraints.maxWidth),
        ),
      );
      return Semantics(
        container: true,
        label: 'Recipe Editor draft form',
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              _buildEditorHeader(draft),
              const SizedBox(height: 24),
              Expanded(child: _withoutPlatformScrollbar(scrollingForm)),
            ],
          ),
        ),
      );
    }
    final form = SingleChildScrollView(
      controller: _formScroll,
      padding: EdgeInsets.zero,
      child: LayoutBuilder(
        builder: (context, constraints) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            _buildEditorHeader(draft),
            const SizedBox(height: 24),
            _buildEditorForm(draft, constraints.maxWidth),
          ],
        ),
      ),
    );
    return Semantics(
      container: true,
      label: 'Recipe Editor draft form',
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: _withoutPlatformScrollbar(form),
      ),
    );
  }

  Widget _withoutPlatformScrollbar(Widget child) => ScrollConfiguration(
    behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
    child: child,
  );

  Widget _buildEditorHeader(RecipeEditorDraft draft) {
    final spec = context.visualTheme;
    final ledger = spec.isIlluminatedLedger;
    final denseLayout = spec.usesDenseSplitLayout;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        LayoutBuilder(
          builder: (context, constraints) {
            final enlargedText =
                MediaQuery.textScalerOf(context).scale(1) > 1.25;
            final compact =
                enlargedText || (denseLayout && constraints.maxWidth < 610);
            final meta = draft.originalName ?? 'New Recipe';
            final actions = Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                AppButton(
                  key: EditorActionKeys.e17,
                  role: AppButtonRole.primary,
                  semanticLabel: 'Save recipe',
                  onPressed: _busy ? null : () => unawaited(_save()),
                  child: const _EditorButtonContent(
                    glyph: 'check',
                    label: 'Save',
                  ),
                ),
                const SizedBox(width: 8),
                AppButton(
                  key: EditorActionKeys.e18,
                  semanticLabel: 'Delete or hide selected recipe',
                  onPressed: _busy ? null : () => unawaited(_delete()),
                  child: const _EditorButtonContent(
                    glyph: 'trash',
                    label: 'Delete',
                  ),
                ),
              ],
            );
            if (denseLayout && compact) {
              final metaText = Text(
                meta,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: spec.palette.text,
                  fontFamily: ledger
                      ? 'Georgia'
                      : spec.typography.meta.fontFamily,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              );
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  const SectionHeader(title: 'Recipe Editor'),
                  const SizedBox(height: 8),
                  if (enlargedText) ...<Widget>[
                    metaText,
                    const SizedBox(height: 8),
                    Align(alignment: Alignment.centerRight, child: actions),
                  ] else
                    Row(
                      children: <Widget>[
                        Expanded(child: metaText),
                        const SizedBox(width: 8),
                        actions,
                      ],
                    ),
                ],
              );
            }
            if (compact) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  SectionHeader(title: 'Recipe Editor', meta: meta),
                  const SizedBox(height: 8),
                  Align(alignment: Alignment.centerRight, child: actions),
                ],
              );
            }
            return _EditorHeading(meta: meta, actions: actions);
          },
        ),
        if (_status != null) ...<Widget>[
          const SizedBox(height: 9),
          Semantics(
            liveRegion: true,
            label: _status,
            child: AppSurface(
              role: AppSurfaceRole.tooltip,
              tone: _statusIsError
                  ? AppSurfaceTone.danger
                  : AppSurfaceTone.info,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              child: Row(
                children: <Widget>[
                  AppVectorGlyph(
                    _statusIsError ? 'error' : 'info',
                    size: 17,
                    color: _statusIsError
                        ? spec.palette.danger
                        : spec.palette.primaryBright,
                  ),
                  const SizedBox(width: 8),
                  Expanded(child: Text(_status!, style: spec.typography.meta)),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildEditorForm(RecipeEditorDraft draft, double width) {
    final wide = width >= 760;
    final recipeOuterWidth = wide ? width - 392 : width;
    final recipeContentWidth =
        recipeOuterWidth - (context.visualTheme.isStandard ? 28 : 24);
    final recipe = _editorCard(
      'Recipe',
      _buildRecipeFields(draft, recipeContentWidth),
      denseGeometry: _usesDenseEditorGeometry(context),
    );
    final source = _editorCard('Source', _buildSourceFields(draft));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        if (wide)
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Expanded(child: recipe),
                const SizedBox(width: 12),
                SizedBox(width: 380, child: source),
              ],
            ),
          )
        else ...<Widget>[recipe, const SizedBox(height: 12), source],
        const SizedBox(height: 12),
        _editorCard('Icon', _buildIconFields(draft)),
        const SizedBox(height: 12),
        _editorCard('Ingredients', _buildIngredientFields(draft)),
      ],
    );
  }

  Widget _buildRecipeFields(RecipeEditorDraft draft, double availableWidth) {
    final projection = RecipeEditorProjection.fromController(widget.controller);
    final denseGeometry = _usesDenseEditorGeometry(context);
    final compactDenseTypePanel = _usesCompactDenseTypePanel(context);
    final typeChoices = Wrap(
      key: EditorActionKeys.e07,
      spacing: 8,
      runSpacing: 8,
      children: <Widget>[
        for (final choice in projection.typeChoices)
          _EditorTypeButton(
            key: EditorActionKeys.type(choice.value),
            label: choice.label,
            selected: draft.type == choice.value,
            onPressed: _busy ? null : () => _selectType(choice.value),
          ),
      ],
    );
    final categoryValue = draft.categoryIsCustom
        ? editorCustomChoice
        : (foldedValue(projection.categories, draft.category) ??
              (projection.categories.isEmpty
                  ? editorCustomChoice
                  : projection.categories.first));
    final categoryValues = <String>[
      ...projection.categories,
      editorCustomChoice,
    ];
    String categoryLabel(String value) =>
        value == editorCustomChoice ? '+ Add new category' : value;
    final methodValue = draft.methodIsCustom
        ? editorCustomChoice
        : (foldedValue(projection.methods, draft.method) ??
              editorNoMethodChoice);
    final methodValues = <String>[
      editorNoMethodChoice,
      ...projection.methods,
      editorCustomChoice,
    ];
    String methodLabel(String value) => switch (value) {
      editorCustomChoice => '+ Add new method',
      editorNoMethodChoice => '(none)',
      _ => value,
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _EditorTextField(
          key: EditorActionKeys.e04,
          controller: _nameText,
          focusNode: _nameFocus,
          label: 'Name',
          onChanged: (value) {
            draft.name = value;
            _markDirty();
            _updateRenameImpact();
          },
          semanticLabel: 'Recipe name',
        ),
        SizedBox(height: denseGeometry ? 9 : 12),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            SizedBox(
              width: 100,
              child: _EditorTextField(
                key: EditorActionKeys.e05,
                controller: _outputText,
                label: 'Output',
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                inputFormatters: <TextInputFormatter>[
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9.,+\-]')),
                ],
                onChanged: (value) {
                  draft.baseOutputText = value;
                  _markDirty();
                },
                semanticLabel: 'Recipe base output',
              ),
            ),
            const SizedBox(width: 12),
            SizedBox(
              width: 118,
              child: _EditorTextField(
                key: EditorActionKeys.e06,
                controller: _marketIdText,
                label: 'Market ID',
                onChanged: (value) {
                  draft.marketId = value;
                  _markDirty();
                },
                semanticLabel: 'Recipe market ID',
              ),
            ),
          ],
        ),
        SizedBox(height: denseGeometry ? 8 : 12),
        _EditorFieldShell(
          label: 'Type',
          child: Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: compactDenseTypePanel
                ? Align(
                    alignment: Alignment.centerLeft,
                    child: SizedBox(width: 324, child: typeChoices),
                  )
                : typeChoices,
          ),
        ),
        SizedBox(height: denseGeometry ? 9 : 10),
        _EditorSelectPair(
          availableWidth: availableWidth,
          leftValues: categoryValues,
          leftLabelFor: categoryLabel,
          rightValues: methodValues,
          rightLabelFor: methodLabel,
          left: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              _EditorSelect(
                key: EditorActionKeys.e08,
                label: 'Category',
                semanticLabel: 'Recipe category',
                value: categoryValue,
                values: categoryValues,
                labelFor: categoryLabel,
                onChanged: _selectCategory,
              ),
              if (draft.categoryIsCustom) ...<Widget>[
                const SizedBox(height: 7),
                _EditorTextField(
                  controller: _customCategoryText,
                  onChanged: (value) {
                    draft.customCategory = value;
                    _markDirty();
                  },
                  semanticLabel: 'Custom recipe category',
                ),
              ],
            ],
          ),
          right: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              _EditorSelect(
                key: EditorActionKeys.e09,
                label: 'Method',
                semanticLabel: 'Recipe processing method',
                value: methodValue,
                values: methodValues,
                labelFor: methodLabel,
                onChanged: _selectMethod,
              ),
              if (draft.methodIsCustom) ...<Widget>[
                const SizedBox(height: 7),
                _EditorTextField(
                  controller: _customMethodText,
                  onChanged: (value) {
                    draft.customMethod = value;
                    _markDirty();
                  },
                  semanticLabel: 'Custom processing method',
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSourceFields(RecipeEditorDraft draft) => KeyedSubtree(
    key: EditorActionKeys.e10,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Expanded(
              child: _EditorTextField(
                controller: _vendorText,
                label: 'Vendor',
                onChanged: (value) {
                  draft.vendor = value;
                  _markDirty();
                },
                semanticLabel: 'Recipe vendor',
              ),
            ),
            const SizedBox(width: 10),
            SizedBox(
              width: 150,
              child: _EditorTextField(
                controller: _npcPriceText,
                label: 'NPC price',
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                inputFormatters: <TextInputFormatter>[
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9.,+\-]')),
                ],
                onChanged: (value) {
                  draft.npcPriceText = value;
                  _markDirty();
                },
                semanticLabel: 'Recipe NPC price',
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        _EditorTextField(
          controller: _locationText,
          label: 'Location',
          onChanged: (value) {
            draft.location = value;
            _markDirty();
          },
          semanticLabel: 'Recipe source location',
        ),
        const SizedBox(height: 10),
        _EditorTextField(
          controller: _sourceNoteText,
          label: 'Source note',
          height: 72,
          multiline: true,
          onChanged: (value) {
            draft.sourceNote = value;
            _markDirty();
          },
          semanticLabel: 'Recipe source note',
        ),
        const SizedBox(height: 10),
        _EditorTextField(
          controller: _searchKeywordsText,
          label: 'Search keywords',
          height: 42,
          multiline: true,
          onChanged: (value) {
            draft.searchKeywords = value;
            _markDirty();
          },
          semanticLabel: 'Recipe search keywords',
        ),
      ],
    ),
  );

  Widget _buildIconFields(RecipeEditorDraft draft) {
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 10,
      runSpacing: 9,
      children: <Widget>[
        _EditorIcon(
          controller: widget.controller,
          iconStore: widget.iconStore,
          name: draft.originalName ?? _nameText.text,
          customReference: draft.icon,
          size: 54,
        ),
        AppButton(
          key: EditorActionKeys.e11,
          onPressed: _busy ? null : () => unawaited(_chooseIcon()),
          semanticLabel: 'Choose and normalize a custom recipe icon',
          child: _EditorButtonContent(
            glyph: 'image',
            label: _busy ? 'Working…' : 'Choose Icon',
          ),
        ),
        AppButton(
          key: EditorActionKeys.e12,
          onPressed: _busy ? null : _removeIcon,
          semanticLabel: 'Stage custom recipe icon removal',
          child: const _EditorButtonContent(glyph: 'trash', label: 'Remove'),
        ),
      ],
    );
  }

  Widget _buildIngredientFields(RecipeEditorDraft draft) {
    final projection = RecipeEditorProjection.fromController(widget.controller);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        for (
          var index = 0;
          index < draft.ingredients.length;
          index++
        ) ...<Widget>[
          _IngredientEditorRow(
            key: ValueKey<EditorIngredientDraft>(draft.ingredients[index]),
            index: index,
            fields: _ingredientFields[index],
            itemNames: projection.itemNames,
            onChanged: () {
              draft.ingredients[index]
                ..name = _ingredientFields[index].nameText.text
                ..quantityText = _ingredientFields[index].quantityText.text;
              _markDirty();
            },
            onRemove: _busy ? null : () => _removeIngredient(index),
          ),
          if (index < draft.ingredients.length - 1) const SizedBox(height: 9),
        ],
        const SizedBox(height: 10),
        if (context.visualTheme.usesDenseSplitLayout)
          SizedBox(
            width: double.infinity,
            child: AppButton(
              key: EditorActionKeys.e15,
              role: context.visualTheme.isIlluminatedLedger
                  ? AppButtonRole.primary
                  : AppButtonRole.secondary,
              onPressed: _busy ? null : _addIngredient,
              semanticLabel: 'Append a new editable ingredient row',
              child: const Align(
                alignment: Alignment.centerLeft,
                child: _EditorButtonContent(glyph: 'add', label: 'Ingredient'),
              ),
            ),
          )
        else
          Align(
            alignment: Alignment.centerLeft,
            child: AppButton(
              key: EditorActionKeys.e15,
              onPressed: _busy ? null : _addIngredient,
              semanticLabel: 'Append a new editable ingredient row',
              child: const _EditorButtonContent(
                glyph: 'add',
                label: 'Ingredient',
              ),
            ),
          ),
      ],
    );
  }

  Widget _editorCard(String title, Widget child, {bool denseGeometry = false}) {
    final spec = context.visualTheme;
    final ledger = spec.isIlluminatedLedger;
    final sakura = spec.isSakuraNightGarden;
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(
          title,
          style: TextStyle(
            color: spec.isStandard
                ? const Color(0xFFFFF1BB)
                : spec.palette.text,
            fontFamily: ledger
                ? 'Georgia'
                : sakura
                ? spec.typography.section.fontFamily
                : 'Segoe UI',
            fontSize: 17,
            fontWeight: FontWeight.w700,
            height: 1.12,
          ),
        ),
        SizedBox(height: denseGeometry ? 10 : 14),
        child,
      ],
    );
    if (!spec.isStandard) {
      return AppSurface(
        role: AppSurfaceRole.card,
        padding: const EdgeInsets.all(12),
        semanticLabel: '$title editor section',
        child: content,
      );
    }
    final standard = context.standardVisual;
    return Semantics(
      container: true,
      label: '$title editor section',
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: StandardSpec.plannerCardFill(
            standard.backgroundId,
            AppSurfaceTone.neutral,
          ),
          borderRadius: BorderRadius.circular(9),
          border: Border.all(
            color: StandardSpec.accentBrush(
              standard.accentHue,
              alpha: .28,
              neon: standard.neon,
            ),
          ),
        ),
        child: content,
      ),
    );
  }

  void _cleanupUncommittedIcon() {
    final draft = _draft;
    final icon = draft?.icon;
    if (icon == null || _sameIcon(icon, draft?.originalIcon)) return;
    if (!_stateReferencesIcon(widget.controller.owner.documentSnapshot, icon)) {
      unawaited(_safeRemoveIcon(icon));
    }
  }

  Future<void> _safeRemoveIcon(CustomIconReference icon) async {
    final relative = icon.relativePath.replaceAll(
      RegExp(r'[/\\]+'),
      Platform.pathSeparator,
    );
    final file = File(
      '${widget.iconStore.applicationDirectory.path}${Platform.pathSeparator}$relative',
    );
    Object? lastError;
    for (var attempt = 0; attempt < 6; attempt++) {
      await FileImage(file).evict();
      try {
        await widget.iconStore.remove(icon);
        return;
      } on FileSystemException catch (error) {
        lastError = error;
        if (attempt < 5) {
          await Future<void>.delayed(
            Duration(milliseconds: 35 * (attempt + 1)),
          );
        }
      } on Object catch (error) {
        lastError = error;
        break;
      }
    }
    if (lastError != null) {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: lastError,
          library: 'Black Spirit Life Recipe Editor',
          context: ErrorDescription(
            'while removing an unreferenced app-owned custom icon',
          ),
        ),
      );
    }
  }
}

final class _IngredientFields {
  _IngredientFields(EditorIngredientDraft row)
    : nameText = TextEditingController(text: row.name),
      quantityText = TextEditingController(text: row.quantityText);

  final TextEditingController nameText;
  final TextEditingController quantityText;
  final FocusNode nameFocus = FocusNode();
  final FocusNode quantityFocus = FocusNode();

  void dispose() {
    nameText.dispose();
    quantityText.dispose();
    nameFocus.dispose();
    quantityFocus.dispose();
  }
}

class _EditorButtonContent extends StatelessWidget {
  const _EditorButtonContent({required this.glyph, required this.label});

  final String glyph;
  final String label;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: <Widget>[
      AppVectorGlyph(glyph, size: glyph == 'add' ? 13 : 16),
      const SizedBox(width: 7),
      Text(label),
    ],
  );
}

class _EditorHeading extends StatelessWidget {
  const _EditorHeading({required this.meta, required this.actions});

  final String meta;
  final Widget actions;

  @override
  Widget build(BuildContext context) {
    final spec = context.visualTheme;
    final ledger = spec.isIlluminatedLedger;
    final sakura = spec.isSakuraNightGarden;
    if (spec.usesDenseSplitLayout) {
      return SizedBox(
        height: 38,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: <Widget>[
            Expanded(
              child: Text(
                ledger ? 'RECIPE EDITOR' : 'Recipe Editor',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: ledger ? spec.palette.primary : spec.palette.text,
                  fontFamily: ledger
                      ? 'Georgia'
                      : spec.typography.section.fontFamily,
                  fontSize: 28,
                  fontWeight: FontWeight.w700,
                  letterSpacing: sakura ? .35 : null,
                  height: 1.08,
                ),
              ),
            ),
            const SizedBox(width: 12),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 240),
              child: Text(
                meta,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.end,
                style: TextStyle(
                  color: ledger ? spec.palette.text : spec.palette.trimBright,
                  fontFamily: ledger
                      ? 'Georgia'
                      : spec.typography.meta.fontFamily,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(width: 8),
            actions,
          ],
        ),
      );
    }
    return SizedBox(
      height: 38,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: <Widget>[
          Expanded(
            child: Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    'Recipe Editor',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: const Color(0xFFFFF1BB),
                      fontFamily: 'Georgia',
                      fontSize: 28,
                      fontWeight: FontWeight.w700,
                      height: 1.08,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Flexible(
                  child: Text(
                    meta,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.end,
                    style: TextStyle(
                      color: const Color(0xFFAEEEDF),
                      fontFamily: 'Segoe UI',
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          actions,
        ],
      ),
    );
  }
}

class _EditorFieldShell extends StatelessWidget {
  const _EditorFieldShell({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final spec = context.visualTheme;
    final ledger = spec.isIlluminatedLedger;
    final sakura = spec.isSakuraNightGarden;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(
          label.toUpperCase(),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: ledger
                ? const Color(0xFF806633)
                : sakura
                ? spec.palette.trimBright
                : const Color(0xFFD7C783),
            fontFamily: ledger ? 'Georgia' : spec.typography.label.fontFamily,
            fontSize: 12,
            fontWeight: FontWeight.w700,
            height: 1.2,
          ),
        ),
        const SizedBox(height: 4),
        child,
      ],
    );
  }
}

class _EditorTextField extends StatefulWidget {
  const _EditorTextField({
    this.controller,
    this.focusNode,
    this.label,
    this.hintText,
    this.onChanged,
    this.onSubmitted,
    this.keyboardType,
    this.inputFormatters,
    this.semanticLabel,
    this.accented = false,
    this.multiline = false,
    this.height,
    this.standardSingleLineTopInset = 8,
    super.key,
  });

  final TextEditingController? controller;
  final FocusNode? focusNode;
  final String? label;
  final String? hintText;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final TextInputType? keyboardType;
  final List<TextInputFormatter>? inputFormatters;
  final String? semanticLabel;
  final bool accented;
  final bool multiline;
  final double? height;
  final double standardSingleLineTopInset;

  @override
  State<_EditorTextField> createState() => _EditorTextFieldState();
}

class _EditorTextFieldState extends State<_EditorTextField> {
  bool _focused = false;
  bool _hovered = false;

  @override
  void initState() {
    super.initState();
    _focused = widget.focusNode?.hasFocus ?? false;
    widget.focusNode?.addListener(_syncExternalFocusNode);
  }

  @override
  void didUpdateWidget(covariant _EditorTextField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.focusNode == widget.focusNode) return;
    oldWidget.focusNode?.removeListener(_syncExternalFocusNode);
    widget.focusNode?.addListener(_syncExternalFocusNode);
    _syncExternalFocusNode();
  }

  void _syncExternalFocusNode() {
    final focused = widget.focusNode?.hasFocus ?? false;
    if (_focused != focused && mounted) setState(() => _focused = focused);
  }

  @override
  void dispose() {
    widget.focusNode?.removeListener(_syncExternalFocusNode);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final spec = context.visualTheme;
    final ledger = spec.isIlluminatedLedger;
    final sakura = spec.isSakuraNightGarden;
    final denseLayout = spec.usesDenseSplitLayout;
    final standard = spec.isStandard ? context.standardVisual : null;
    final fieldHeight = widget.height ?? (denseLayout ? 34.0 : 32.0);
    final borderColor = _focused
        ? ledger
              ? const Color(0xFF0078D4)
              : sakura
              ? spec.palette.primaryBright
              : spec.palette.primaryBright
        : _hovered
        ? spec.palette.trimBright.withAlpha(220)
        : sakura
        ? (widget.accented
              ? spec.palette.primary.withAlpha(166)
              : spec.palette.trim.withAlpha(164))
        : widget.accented && !ledger
        ? StandardSpec.accentBrush(
            standard!.accentHue,
            alpha: .32,
            neon: standard.neon,
          )
        : ledger
        ? spec.palette.trim.withAlpha(138)
        : const Color(0xFF5D7F70);
    final field = AnimatedContainer(
      duration: spec.motion.interactionDuration,
      height: fieldHeight,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: ledger
            ? _focused
                  ? const Color(0xFFFFFCF4)
                  : spec.palette.surfaceRaised.withAlpha(212)
            : sakura
            ? spec.palette.surfaceInset.withAlpha(232)
            : null,
        gradient: ledger
            ? null
            : sakura
            ? spec.materials.surfaceRaised
            : widget.accented
            ? StandardSpec.accentGlass(
                standard!.accentHue,
                topAlpha: 54,
                bottomAlpha: 18,
                neon: standard.neon,
              )
            : StandardSpec.glassGradient(topAlpha: 70, bottomAlpha: 28),
        borderRadius: BorderRadius.circular(
          ledger ? 2 : spec.geometry.fieldRadius,
        ),
        border: Border.all(
          color: borderColor,
          width: denseLayout && _focused ? 2 : 1,
        ),
      ),
      child: TextField(
        controller: widget.controller,
        focusNode: widget.focusNode,
        onChanged: widget.onChanged,
        onSubmitted: widget.onSubmitted,
        keyboardType: widget.keyboardType,
        inputFormatters: widget.inputFormatters,
        expands: widget.multiline,
        maxLines: widget.multiline ? null : 1,
        minLines: null,
        textAlignVertical: widget.multiline
            ? TextAlignVertical.top
            : TextAlignVertical.center,
        cursorColor: spec.palette.primaryBright,
        style: TextStyle(
          color: spec.isStandard ? const Color(0xFFFFF4D8) : spec.palette.text,
          fontFamily: ledger ? 'Georgia' : spec.typography.body.fontFamily,
          fontSize: 13,
          fontWeight: FontWeight.w600,
          height: 1.15,
        ),
        decoration: InputDecoration(
          isDense: true,
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          disabledBorder: InputBorder.none,
          hintText: widget.hintText,
          hintStyle: TextStyle(
            color: spec.palette.textMuted.withAlpha(185),
            fontFamily: ledger ? 'Georgia' : spec.typography.body.fontFamily,
            fontSize: 13,
            fontWeight: FontWeight.w500,
          ),
          contentPadding: widget.multiline
              ? const EdgeInsets.fromLTRB(10, 7, 10, 6)
              : ledger
              ? const EdgeInsets.fromLTRB(10, 12, 10, 0)
              : sakura
              ? const EdgeInsets.fromLTRB(10, 10, 10, 0)
              : EdgeInsets.fromLTRB(
                  10,
                  widget.standardSingleLineTopInset,
                  10,
                  0,
                ),
        ),
      ),
    );
    Widget result = Focus(
      skipTraversal: true,
      onFocusChange: (value) {
        if (_focused != value) setState(() => _focused = value);
      },
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: field,
      ),
    );
    if (widget.semanticLabel != null) {
      result = Semantics(
        textField: true,
        label: widget.semanticLabel,
        child: result,
      );
    }
    return widget.label == null
        ? result
        : _EditorFieldShell(label: widget.label!, child: result);
  }
}

class _EditorRecipeButton extends StatelessWidget {
  const _EditorRecipeButton({
    required this.selected,
    required this.onPressed,
    required this.semanticLabel,
    required this.child,
    super.key,
  });

  final bool selected;
  final VoidCallback? onPressed;
  final String semanticLabel;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final spec = context.visualTheme;
    if (!spec.isStandard) {
      return AppButton(
        role: selected ? AppButtonRole.modeSelector : AppButtonRole.navigation,
        selected: selected,
        minimumSize: const Size(0, 50),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        onPressed: onPressed,
        semanticLabel: semanticLabel,
        child: child,
      );
    }
    final standard = context.standardVisual;
    return Semantics(
      button: true,
      selected: selected,
      enabled: onPressed != null,
      label: semanticLabel,
      child: Opacity(
        opacity: onPressed == null ? .48 : 1,
        child: Container(
          constraints: const BoxConstraints(minHeight: 50),
          decoration: BoxDecoration(
            gradient: StandardSpec.accentGlass(
              standard.accentHue,
              topAlpha: selected ? 112 : 52,
              bottomAlpha: selected ? 42 : 16,
              neon: standard.neon,
            ),
            borderRadius: BorderRadius.circular(9),
            border: Border.all(
              color: StandardSpec.accentBrush(
                standard.accentHue,
                alpha: selected ? .9 : .24,
                neon: standard.neon,
              ),
            ),
          ),
          child: Material(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(9),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: onPressed,
              overlayColor: WidgetStatePropertyAll(
                StandardSpec.accentBrush(
                  standard.accentHue,
                  alpha: .09,
                  neon: standard.neon,
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                child: child,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _EditorTypeButton extends StatelessWidget {
  const _EditorTypeButton({
    required this.label,
    required this.selected,
    required this.onPressed,
    super.key,
  });

  final String label;
  final bool selected;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final spec = context.visualTheme;
    if (!spec.isStandard) {
      return SizedBox(
        width: 154,
        child: AppButton(
          role: selected
              ? AppButtonRole.modeSelector
              : AppButtonRole.navigation,
          selected: selected,
          minimumSize: const Size(154, 42),
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 9),
          onPressed: onPressed,
          semanticLabel: label,
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
        ),
      );
    }
    final standard = context.standardVisual;
    final accent = StandardSpec.accentBrush(
      standard.accentHue,
      neon: standard.neon,
    );
    final fill = accent.withAlpha((.86 * 255).round());
    return Semantics(
      button: true,
      selected: selected,
      enabled: onPressed != null,
      label: label,
      child: Opacity(
        opacity: onPressed == null ? .48 : 1,
        child: Container(
          width: 154,
          height: 42,
          decoration: BoxDecoration(
            gradient: selected
                ? LinearGradient(colors: <Color>[fill, fill])
                : StandardSpec.accentGlass(
                    standard.accentHue,
                    topAlpha: 52,
                    bottomAlpha: 16,
                    neon: standard.neon,
                  ),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: StandardSpec.accentBrush(
                standard.accentHue,
                alpha: selected ? 1 : .28,
                neon: standard.neon,
              ),
            ),
          ),
          child: Material(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: onPressed,
              overlayColor: WidgetStatePropertyAll(
                StandardSpec.accentBrush(
                  standard.accentHue,
                  alpha: .1,
                  neon: standard.neon,
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 11,
                  vertical: 9,
                ),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    label,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: selected
                          ? const Color(0xFF03120E)
                          : const Color(0xFFFFF0D0),
                      fontFamily: 'Segoe UI',
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      height: 1.08,
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

class _IngredientEditorRow extends StatelessWidget {
  const _IngredientEditorRow({
    required this.index,
    required this.fields,
    required this.itemNames,
    required this.onChanged,
    required this.onRemove,
    super.key,
  });

  final int index;
  final _IngredientFields fields;
  final List<String> itemNames;
  final VoidCallback onChanged;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final denseLayout = context.visualTheme.usesDenseSplitLayout;
    final ingredientFieldHeight = denseLayout ? null : 38.0;
    return Semantics(
      container: true,
      label: 'Ingredient ${index + 1}',
      child: LayoutBuilder(
        builder: (context, constraints) {
          const fixedTrailingWidth = 96.0 + 8 + 46;
          final itemWidth = constraints.maxWidth >= 518
              ? 360.0
              : (constraints.maxWidth - fixedTrailingWidth - 8).clamp(
                  180.0,
                  360.0,
                );
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              SizedBox(
                width: itemWidth,
                child: KeyedSubtree(
                  key: index == 0 ? EditorActionKeys.e13 : null,
                  child: RawAutocomplete<String>(
                    key: EditorActionKeys.ingredientItem(index),
                    textEditingController: fields.nameText,
                    focusNode: fields.nameFocus,
                    optionsViewOpenDirection: OptionsViewOpenDirection.up,
                    displayStringForOption: (value) => value,
                    optionsBuilder: (value) {
                      final query = value.text.trim().toLowerCase();
                      final exact = foldedValue(itemNames, value.text);
                      return itemNames
                          .where(
                            (name) =>
                                query.isEmpty ||
                                name.toLowerCase().contains(query),
                          )
                          .where(
                            (name) =>
                                exact == null ||
                                name != exact ||
                                query.isNotEmpty,
                          )
                          .take(80);
                    },
                    onSelected: (value) {
                      fields.nameText.value = TextEditingValue(
                        text: value,
                        selection: TextSelection.collapsed(
                          offset: value.length,
                        ),
                      );
                      onChanged();
                      fields.quantityFocus.requestFocus();
                    },
                    fieldViewBuilder:
                        (context, controller, focusNode, onSubmitted) =>
                            _EditorTextField(
                              controller: controller,
                              focusNode: focusNode,
                              height: ingredientFieldHeight,
                              standardSingleLineTopInset: 11.5,
                              label: 'Item',
                              onChanged: (_) => onChanged(),
                              onSubmitted: (_) {
                                final canonical = foldedValue(
                                  itemNames,
                                  controller.text,
                                );
                                if (canonical != null) {
                                  controller.value = TextEditingValue(
                                    text: canonical,
                                    selection: TextSelection.collapsed(
                                      offset: canonical.length,
                                    ),
                                  );
                                }
                                onSubmitted();
                                onChanged();
                              },
                              semanticLabel: 'Ingredient ${index + 1} item',
                            ),
                    optionsViewBuilder: (context, onSelected, options) {
                      final values = options.toList(growable: false);
                      return Align(
                        alignment: Alignment.topLeft,
                        child: Material(
                          color: Colors.transparent,
                          elevation: 12,
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(
                              minWidth: 280,
                              maxWidth: 430,
                              maxHeight: 310,
                            ),
                            child: AppSurface(
                              role: AppSurfaceRole.popup,
                              padding: EdgeInsets.zero,
                              child: ListView.builder(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 6,
                                ),
                                itemCount: values.length,
                                itemBuilder: (context, optionIndex) {
                                  final option = values[optionIndex];
                                  final highlighted =
                                      AutocompleteHighlightedOption.of(
                                        context,
                                      ) ==
                                      optionIndex;
                                  return InkWell(
                                    onTap: () => onSelected(option),
                                    child: Container(
                                      color: highlighted
                                          ? context.visualTheme.palette.primary
                                                .withAlpha(72)
                                          : null,
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 12,
                                        vertical: 9,
                                      ),
                                      child: Text(
                                        option,
                                        style:
                                            context.visualTheme.typography.body,
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 96,
                child: KeyedSubtree(
                  key: index == 0 ? EditorActionKeys.e14 : null,
                  child: Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: _EditorTextField(
                      key: EditorActionKeys.ingredientQuantity(index),
                      controller: fields.quantityText,
                      focusNode: fields.quantityFocus,
                      label: 'Qty',
                      height: ingredientFieldHeight,
                      standardSingleLineTopInset: 11.5,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      inputFormatters: <TextInputFormatter>[
                        FilteringTextInputFormatter.allow(
                          RegExp(r'[0-9.,+\-]'),
                        ),
                      ],
                      onChanged: (_) => onChanged(),
                      onSubmitted: (_) => onChanged(),
                      semanticLabel: 'Ingredient ${index + 1} quantity',
                    ),
                  ),
                ),
              ),
              SizedBox(
                width: 46,
                height: 54,
                child: Center(
                  child: KeyedSubtree(
                    key: index == 0 ? EditorActionKeys.e16 : null,
                    child: AppButton.icon(
                      key: EditorActionKeys.removeIngredient(index),
                      icon: const AppVectorGlyph('trash', size: 23),
                      onPressed: onRemove,
                      semanticLabel: 'Remove ingredient ${index + 1}',
                      tooltip: 'Remove ingredient',
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _EditorSelect extends StatelessWidget {
  const _EditorSelect({
    required this.label,
    required this.semanticLabel,
    required this.value,
    required this.values,
    required this.labelFor,
    required this.onChanged,
    super.key,
  });

  final String label;
  final String semanticLabel;
  final String value;
  final List<String> values;
  final String Function(String value) labelFor;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    final distinct = <String>[];
    final seen = <String>{};
    for (final candidate in values) {
      final key = candidate == editorCustomChoice
          ? candidate
          : candidate.toLowerCase();
      if (seen.add(key)) distinct.add(candidate);
    }
    final selected = distinct.contains(value) ? value : distinct.first;
    return Semantics(
      label: semanticLabel,
      child: _EditorFieldShell(
        label: label,
        child: SizedBox(
          height: 38,
          child: AppSelect<String>(
            value: selected,
            items: distinct,
            labelFor: labelFor,
            semanticLabel: semanticLabel,
            onChanged: onChanged,
          ),
        ),
      ),
    );
  }
}

class _EditorSelectPair extends StatelessWidget {
  const _EditorSelectPair({
    required this.availableWidth,
    required this.leftValues,
    required this.leftLabelFor,
    required this.rightValues,
    required this.rightLabelFor,
    required this.left,
    required this.right,
  });

  final double availableWidth;
  final List<String> leftValues;
  final String Function(String value) leftLabelFor;
  final List<String> rightValues;
  final String Function(String value) rightLabelFor;
  final Widget left;
  final Widget right;

  @override
  Widget build(BuildContext context) {
    final available = availableWidth;
    final leftWidth = AppSelect.readableWidthFor<String>(
      context,
      items: leftValues,
      labelFor: leftLabelFor,
      minimumWidth: 150,
      maximumWidth: available,
    );
    final rightWidth = AppSelect.readableWidthFor<String>(
      context,
      items: rightValues,
      labelFor: rightLabelFor,
      minimumWidth: 150,
      maximumWidth: available,
    );
    final halfWidth = (available - 12) / 2;
    if (leftWidth <= halfWidth && rightWidth <= halfWidth) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Expanded(child: left),
          const SizedBox(width: 12),
          Expanded(child: right),
        ],
      );
    }
    if (leftWidth + rightWidth + 12 <= available) {
      final spare = (available - leftWidth - rightWidth - 12) / 2;
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(width: leftWidth + spare, child: left),
          const SizedBox(width: 12),
          SizedBox(width: rightWidth + spare, child: right),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[left, const SizedBox(height: 9), right],
    );
  }
}

class _EditorIcon extends StatelessWidget {
  const _EditorIcon({
    required this.controller,
    required this.iconStore,
    required this.name,
    required this.size,
    this.customReference,
  });

  final ModeFeatureController controller;
  final CustomIconStore iconStore;
  final String name;
  final double size;
  final CustomIconReference? customReference;

  @override
  Widget build(BuildContext context) {
    final spec = context.visualTheme;
    final ledger = spec.isIlluminatedLedger;
    final sakura = spec.isSakuraNightGarden;
    final stateReference = foldedEntry(
      controller.state.value.customIcons,
      name,
    )?.value;
    final reference = customReference ?? stateReference;
    final iconUri = foldedEntry(
      controller.owner.catalog.forMode(controller.mode).iconDataUris,
      name,
    )?.value;
    final bytes = iconUri == null
        ? null
        : _EditorIconCache.instance.resolve(iconUri);
    Widget content;
    if (reference != null) {
      final relative = reference.relativePath.replaceAll(
        RegExp(r'[/\\]+'),
        Platform.pathSeparator,
      );
      final customBytes = _EditorCustomIconCache.instance.resolve(
        File(
          '${iconStore.applicationDirectory.path}${Platform.pathSeparator}$relative',
        ),
        reference,
      );
      content = customBytes == null
          ? _fallback(spec)
          : Image.memory(
              customBytes,
              fit: BoxFit.cover,
              gaplessPlayback: true,
              filterQuality: FilterQuality.medium,
              errorBuilder: (_, _, _) => _fallback(spec),
            );
    } else if (bytes != null) {
      content = Image.memory(
        bytes,
        fit: BoxFit.cover,
        gaplessPlayback: true,
        filterQuality: FilterQuality.medium,
        errorBuilder: (_, _, _) => _fallback(spec),
      );
    } else {
      content = _fallback(spec);
    }
    return Semantics(
      image: true,
      label: name.trim().isEmpty ? 'New recipe icon' : '$name icon',
      child: Container(
        width: size,
        height: size,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: spec.palette.surfaceInset,
          gradient: ledger
              ? const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: <Color>[Color(0xFF174D7E), Color(0xFF0A2744)],
                )
              : null,
          borderRadius: BorderRadius.circular(
            ledger ? 1 : spec.geometry.fieldRadius,
          ),
          border: Border.all(
            color: ledger
                ? const Color(0xFFC3A04B)
                : spec.palette.trimBright.withAlpha(130),
            width: ledger ? 1.3 : 1,
          ),
          boxShadow: ledger
              ? const <BoxShadow>[
                  BoxShadow(
                    color: Color(0x44352516),
                    blurRadius: 5,
                    offset: Offset(0, 2),
                  ),
                ]
              : sakura
              ? spec.materials.lowShadow
              : null,
        ),
        child: content,
      ),
    );
  }

  Widget _fallback(ThemeSpec spec) {
    final ledger = spec.isIlluminatedLedger;
    final initials = _editorInitials(name);
    return Center(
      child: Text(
        initials,
        textAlign: TextAlign.center,
        style: TextStyle(
          color: ledger
              ? const Color(0xFFEAD8A4)
              : spec.isSakuraNightGarden
              ? spec.palette.primaryBright
              : const Color(0xFFFFE9A8),
          fontFamily: ledger ? 'Georgia' : spec.typography.body.fontFamily,
          fontSize: size * .28 < 10 ? 10 : size * .28,
          fontWeight: FontWeight.bold,
          height: 1,
        ),
      ),
    );
  }
}

String _editorInitials(String name) {
  final parts = name
      .trim()
      .split(RegExp(r'\s+'))
      .where((part) => part.isNotEmpty);
  final initials = parts.take(2).map((part) => part[0]).join().toUpperCase();
  return initials.isEmpty ? '?' : initials;
}

final class _EditorCustomIconCache {
  _EditorCustomIconCache._();
  static final _EditorCustomIconCache instance = _EditorCustomIconCache._();
  static const int _limit = 64;
  final LinkedHashMap<String, Uint8List> _values =
      LinkedHashMap<String, Uint8List>();

  Uint8List? resolve(File file, CustomIconReference reference) {
    final key = '${reference.sha256}:${reference.byteCount}';
    final cached = _values.remove(key);
    if (cached != null) {
      _values[key] = cached;
      return cached;
    }
    try {
      final bytes = file.readAsBytesSync();
      if (bytes.length != reference.byteCount) return null;
      _values[key] = bytes;
      if (_values.length > _limit) _values.remove(_values.keys.first);
      return bytes;
    } on FileSystemException {
      return null;
    }
  }
}

final class _EditorIconCache {
  _EditorIconCache._();
  static final _EditorIconCache instance = _EditorIconCache._();
  static const int _limit = 192;
  final LinkedHashMap<String, Uint8List> _values =
      LinkedHashMap<String, Uint8List>();

  Uint8List? resolve(String uri) {
    final cached = _values.remove(uri);
    if (cached != null) {
      _values[uri] = cached;
      return cached;
    }
    final comma = uri.indexOf(',');
    if (comma < 0 || !uri.substring(0, comma).contains(';base64')) return null;
    try {
      final decoded = base64Decode(uri.substring(comma + 1));
      _values[uri] = decoded;
      if (_values.length > _limit) _values.remove(_values.keys.first);
      return decoded;
    } on FormatException {
      return null;
    }
  }
}

sealed class _EditorValidation {
  const _EditorValidation();
}

final class _EditorValidationFailure extends _EditorValidation {
  const _EditorValidationFailure(this.message);
  final String message;
}

final class _ValidatedEditorDraft extends _EditorValidation {
  const _ValidatedEditorDraft({
    required this.name,
    required this.recipe,
    required this.metadata,
    required this.customCategory,
  });
  final String name;
  final RecipeState recipe;
  final IngredientMetadata metadata;
  final String? customCategory;
}

final class _NewRecipeIntent extends Intent {
  const _NewRecipeIntent();
}

final class _SaveRecipeIntent extends Intent {
  const _SaveRecipeIntent();
}

PlannerState _saveWithoutRename(
  PlannerState document, {
  required CraftMode mode,
  required String name,
  required RecipeState recipe,
  required IngredientMetadata metadata,
  required CustomIconReference? icon,
  required String? customCategory,
}) {
  final source = document.forMode(mode);
  final edits = Map<String, RecipeState?>.of(source.recipeEdits);
  _removeFoldedKeys(edits, name);
  edits[name] = recipe;
  final nextMode = _applyModeSavedFields(
    source.copyWith(recipeEdits: edits),
    name: name,
    metadata: metadata,
    icon: icon,
    customCategory: customCategory,
  );
  return _replaceMode(document, mode, nextMode);
}

PlannerState _applySavedFields(
  PlannerState document, {
  required CraftMode mode,
  required String name,
  required RecipeState recipe,
  required IngredientMetadata metadata,
  required CustomIconReference? icon,
  required String? customCategory,
}) {
  final source = document.forMode(mode);
  final edits = Map<String, RecipeState?>.of(source.recipeEdits);
  _removeFoldedKeys(edits, name);
  edits[name] = recipe;
  final nextMode = _applyModeSavedFields(
    source.copyWith(recipeEdits: edits),
    name: name,
    metadata: metadata,
    icon: icon,
    customCategory: customCategory,
  );
  return _replaceMode(document, mode, nextMode);
}

ModeState _applyModeSavedFields(
  ModeState source, {
  required String name,
  required IngredientMetadata metadata,
  required CustomIconReference? icon,
  required String? customCategory,
}) {
  final meta = Map<String, IngredientMetadata>.of(source.ingredientMeta);
  _removeFoldedKeys(meta, name);
  if (!_metadataIsEmpty(metadata)) meta[name] = metadata;
  final icons = Map<String, CustomIconReference>.of(source.customIcons);
  _removeFoldedKeys(icons, name);
  if (icon != null) icons[name] = icon;
  final categories = List<String>.of(source.customCategories);
  if (customCategory != null && !containsFolded(categories, customCategory)) {
    categories.add(customCategory);
    categories.sort(compareEditorNames);
  }
  return source.copyWith(
    recipeEdits: source.recipeEdits,
    ingredientMeta: meta,
    customIcons: icons,
    customCategories: categories,
  );
}

PlannerState _replaceMode(
  PlannerState source,
  CraftMode mode,
  ModeState state,
) => switch (mode) {
  CraftMode.alchemy => source.copyWith(alchemy: state),
  CraftMode.cooking => source.copyWith(cooking: state),
  CraftMode.processing => source.copyWith(processing: state),
};

void _removeFoldedKeys<T>(Map<String, T> values, String name) {
  values.removeWhere((key, _) => sameEditorName(key, name));
}

String _firstNonBlankEditorValue(Iterable<String?> values) {
  for (final value in values) {
    final trimmed = value?.trim();
    if (trimmed != null && trimmed.isNotEmpty) return trimmed;
  }
  return '';
}

bool _metadataIsEmpty(IngredientMetadata value) =>
    value.category == null &&
    value.npcPrice <= 0 &&
    value.sourceNote == null &&
    value.searchKeywords == null &&
    value.vendor == null &&
    value.location == null &&
    value.marketId == null &&
    value.qualityBase == null &&
    value.qualityTier == null &&
    value.extensions.isEmpty;

Iterable<String> _allPersistentNames(ModeFeatureController controller) sync* {
  final seen = <String>{};
  for (final name
      in controller.owner.catalog.forMode(controller.mode).items.keys) {
    if (seen.add(name.toLowerCase())) yield name;
  }
  for (final entry in controller.state.value.recipeEdits.entries) {
    if (entry.value != null && seen.add(entry.key.toLowerCase())) {
      yield entry.key;
    }
  }
}

bool _isBundled(ModeFeatureController controller, String name) =>
    containsFolded(
      controller.owner.catalog.forMode(controller.mode).items.keys,
      name,
    );

String? _fallbackTarget(ModeFeatureController controller, String removedName) {
  final recipes = controller.recipes;
  final current = foldedEntry(recipes, controller.state.value.target);
  if (current != null &&
      !sameEditorName(current.key, removedName) &&
      current.value.isCraftable) {
    return current.key;
  }
  final candidates =
      recipes.entries
          .where(
            (entry) =>
                !sameEditorName(entry.key, removedName) &&
                entry.value.isCraftable,
          )
          .map((entry) => entry.key)
          .toList()
        ..sort(compareEditorNames);
  return candidates.firstOrNull;
}

List<String> _dependentRecipes(ModeState state, String itemName) {
  final result = <String>[];
  for (final entry in state.recipeEdits.entries) {
    if (entry.value == null || sameEditorName(entry.key, itemName)) continue;
    final depends = entry.value!.ingredients.any(
      (ingredient) =>
          sameEditorName(ingredient.name, itemName) ||
          ingredient.options.any(
            (option) => sameEditorName(option, itemName),
          ) ||
          ingredient.substituteRatios.keys.any(
            (option) => sameEditorName(option, itemName),
          ),
    );
    if (depends) result.add(entry.key);
  }
  result.sort(compareEditorNames);
  return result;
}

bool _stateReferencesIcon(PlannerState state, CustomIconReference reference) =>
    CraftMode.values.any(
      (mode) => state
          .forMode(mode)
          .customIcons
          .values
          .any(
            (value) =>
                value.relativePath.replaceAll('\\', '/') ==
                reference.relativePath.replaceAll('\\', '/'),
          ),
    );

bool _sameIcon(CustomIconReference? left, CustomIconReference? right) =>
    left?.relativePath.replaceAll('\\', '/') ==
        right?.relativePath.replaceAll('\\', '/') &&
    left?.sha256.toLowerCase() == right?.sha256.toLowerCase();

String _transactionMessage(StateTransactionFailure error) {
  if (error.conflicts.isEmpty) return error.message;
  return '${error.message} Conflicts: ${error.conflicts.join(', ')}.';
}

String _typeLabel(String type) => switch (type) {
  'alchemy' => 'Residence Alchemy',
  'simple_alchemy' => 'Simple Alchemy',
  'cooking' => 'Residence Cooking',
  'processing' => 'Processing',
  _ => 'Base Item',
};
