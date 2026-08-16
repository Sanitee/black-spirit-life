import 'dart:async';

import 'package:bdo_map_core/bdo_map_core.dart'
    show BdoGatherChecklist, BdoNodeNetworkPreferences;
import 'package:flutter/foundation.dart';

import '../../domain/formatting/planner_formatters.dart';
import '../../domain/models/catalog_models.dart';
import '../../domain/models/craft_mode.dart';
import '../../domain/planner/ingredient_quality.dart';
import '../../domain/planner/item_acquisition_resolution.dart' as acquisition;
import '../../domain/planner/planner_models.dart' as planning;
import '../../domain/planner/source_resolution.dart';
import '../../domain/state/inventory_storage.dart';
import '../../domain/state/planner_state.dart';
import '../../domain/state/state_copy.dart';
import '../../domain/state/user_source_notes.dart';
import '../first_run_setup.dart';
import '../planning/planner_assembly.dart';

typedef SavePlannerState = Future<PlannerState> Function(PlannerState state);

const _resourceMapExtensionKey = 'resourceMap';
const _resourceMapFavoriteIdsKey = 'favoriteResourceIds';
const _resourceMapNodeNetworkKey = 'nodeNetwork';
const _resourceMapGatherChecklistKey = 'gatherChecklist';

/// Coordinates mode-local controllers and serialized persistence. Each feature
/// listens only to the notifier it owns, so a quantity edit does not rebuild
/// the title bar, sidebar, other modes, or unrelated overlays.
final class PlannerApplicationController {
  PlannerApplicationController({
    required this.catalog,
    required PlannerState initialState,
    required this.saveState,
    this.saveDebounce = const Duration(milliseconds: 240),
    this.assembly = const PlannerAssembly(),
  }) : _document = initialState,
       activeMode = ValueNotifier(initialState.activeMode),
       deleteToolsEnabled = ValueNotifier(initialState.showDeleteTools),
       marketTax = ValueNotifier(initialState.marketTax),
       afkWeightProfile = ValueNotifier(initialState.afkWeightProfile),
       resourceMapFavoriteIds = ValueNotifier(
         _resourceMapFavoriteIdsFrom(initialState),
       ),
       resourceMapNodeNetworkPreferences = ValueNotifier(
         _resourceMapNodeNetworkPreferencesFrom(initialState),
       ),
       resourceMapGatherChecklist = ValueNotifier(
         _resourceMapGatherChecklistFrom(initialState),
       ) {
    modes = {
      for (final mode in CraftMode.values)
        mode: ModeFeatureController._(
          owner: this,
          mode: mode,
          initialState: initialState.forMode(mode),
        ),
    };
  }

  final CatalogSnapshot catalog;
  final PlannerAssembly assembly;
  late final planning.PlannerRules plannerRules = assembly.plannerRules(
    catalog.supportingData,
  );
  final Duration saveDebounce;
  final SavePlannerState saveState;
  final ValueNotifier<CraftMode> activeMode;
  final ValueNotifier<bool> deleteToolsEnabled;
  final ValueNotifier<MarketTax> marketTax;
  final ValueNotifier<AfkWeightProfile> afkWeightProfile;
  final ValueNotifier<Set<String>> resourceMapFavoriteIds;
  final ValueNotifier<BdoNodeNetworkPreferences>
  resourceMapNodeNetworkPreferences;
  final ValueNotifier<BdoGatherChecklist> resourceMapGatherChecklist;
  final ValueNotifier<bool> saving = ValueNotifier(false);
  final ValueNotifier<String?> saveError = ValueNotifier(null);
  late final Map<CraftMode, ModeFeatureController> modes;

  PlannerState _document;
  ({int revision, PlannerState state})? _pendingSave;
  int _saveRevision = 0;
  Timer? _saveTimer;
  Future<void>? _saveTail;
  Future<void>? _disposeFuture;
  bool _mutationsFrozen = false;
  bool _disposed = false;

  PlannerState get documentSnapshot => _document;
  ModeFeatureController get active => modes[activeMode.value]!;
  bool get mutationsFrozen => _mutationsFrozen;

  /// Prevents planner mutations while a prepared updater is waiting for this
  /// process to close. Existing pending state can still be flushed safely.
  void freezeMutationsForRestart() {
    if (_disposed) throw StateError('The planner controller is disposed.');
    _mutationsFrozen = true;
  }

  /// Re-enables edits when update preparation or restart was rejected.
  void resumeMutationsAfterRestartFailure() {
    if (_disposed) return;
    _mutationsFrozen = false;
  }

  void switchMode(CraftMode mode) {
    if (_disposed || _mutationsFrozen || activeMode.value == mode) return;
    final controller = modes[mode]!;
    if (mode == CraftMode.processing &&
        controller.state.value.view == 'bonus') {
      controller._replaceState(
        controller.state.value.copyWith(view: 'plan'),
        persist: false,
      );
      _document = _withMode(_document, mode, controller.state.value);
    }
    activeMode.value = mode;
    _document = _document.copyWith(activeMode: mode);
    _scheduleSave(immediate: true);
  }

  void updateDocument(
    PlannerState Function(PlannerState current) update, {
    bool immediate = false,
  }) {
    if (_disposed || _mutationsFrozen) return;
    final previous = _document;
    final next = update(previous);
    _document = next;
    if (next.activeMode != activeMode.value) {
      activeMode.value = next.activeMode;
    }
    if (next.showDeleteTools != deleteToolsEnabled.value) {
      deleteToolsEnabled.value = next.showDeleteTools;
    }
    if (!identical(next.marketTax, marketTax.value)) {
      marketTax.value = next.marketTax;
    }
    if (!identical(next.afkWeightProfile, afkWeightProfile.value)) {
      afkWeightProfile.value = next.afkWeightProfile;
    }
    _syncResourceMapFavoriteIds(next);
    _syncResourceMapNodeNetworkPreferences(next);
    _syncResourceMapGatherChecklist(next);
    final planningGlobalsChanged = !identical(
      previous.processingYields,
      next.processingYields,
    );
    for (final mode in CraftMode.values) {
      final oldMode = previous.forMode(mode);
      final newMode = next.forMode(mode);
      if (!identical(oldMode, newMode) || planningGlobalsChanged) {
        modes[mode]!._replaceState(newMode, persist: false);
      }
    }
    _scheduleSave(immediate: immediate);
  }

  void setResourceMapFavoriteIds(Set<String> favoriteIds) {
    if (_disposed) return;
    final normalized = _normalizedResourceMapFavoriteIds(favoriteIds);
    if (setEquals(resourceMapFavoriteIds.value, normalized)) return;
    updateDocument((document) {
      final extensions = Map<String, Object?>.of(document.extensions);
      final currentResourceMap = extensions[_resourceMapExtensionKey];
      final resourceMap = currentResourceMap is Map
          ? <String, Object?>{
              for (final entry in currentResourceMap.entries)
                entry.key.toString(): entry.value,
            }
          : <String, Object?>{};
      if (normalized.isEmpty) {
        resourceMap.remove(_resourceMapFavoriteIdsKey);
      } else {
        resourceMap[_resourceMapFavoriteIdsKey] = normalized.toList()..sort();
      }
      if (resourceMap.isEmpty) {
        extensions.remove(_resourceMapExtensionKey);
      } else {
        extensions[_resourceMapExtensionKey] = resourceMap;
      }
      return document.copyWith(extensions: extensions);
    }, immediate: true);
  }

  void setResourceMapNodeNetworkPreferences(
    BdoNodeNetworkPreferences preferences,
  ) {
    if (_disposed ||
        resourceMapNodeNetworkPreferences.value.sameValuesAs(preferences)) {
      return;
    }
    updateDocument((document) {
      final extensions = Map<String, Object?>.of(document.extensions);
      final currentResourceMap = extensions[_resourceMapExtensionKey];
      final resourceMap = currentResourceMap is Map
          ? <String, Object?>{
              for (final entry in currentResourceMap.entries)
                entry.key.toString(): entry.value,
            }
          : <String, Object?>{};
      if (preferences.isDefault) {
        resourceMap.remove(_resourceMapNodeNetworkKey);
      } else {
        resourceMap[_resourceMapNodeNetworkKey] = preferences.toJson();
      }
      if (resourceMap.isEmpty) {
        extensions.remove(_resourceMapExtensionKey);
      } else {
        extensions[_resourceMapExtensionKey] = resourceMap;
      }
      return document.copyWith(extensions: extensions);
    }, immediate: true);
  }

  void setResourceMapGatherChecklist(BdoGatherChecklist checklist) {
    if (_disposed || resourceMapGatherChecklist.value == checklist) return;
    updateDocument((document) {
      final extensions = Map<String, Object?>.of(document.extensions);
      final currentResourceMap = extensions[_resourceMapExtensionKey];
      final resourceMap = currentResourceMap is Map
          ? <String, Object?>{
              for (final entry in currentResourceMap.entries)
                entry.key.toString(): entry.value,
            }
          : <String, Object?>{};
      if (checklist.isEmpty) {
        resourceMap.remove(_resourceMapGatherChecklistKey);
      } else {
        resourceMap[_resourceMapGatherChecklistKey] = checklist.toJson();
      }
      if (resourceMap.isEmpty) {
        extensions.remove(_resourceMapExtensionKey);
      } else {
        extensions[_resourceMapExtensionKey] = resourceMap;
      }
      return document.copyWith(extensions: extensions);
    }, immediate: true);
  }

  /// Applies a document replacement only if its durable save succeeds.
  ///
  /// This is reserved for all-or-nothing operations such as portable imports.
  /// Ordinary field edits continue to use the debounced [updateDocument] path.
  Future<void> updateDocumentDurably(
    PlannerState Function(PlannerState current) update,
  ) async {
    if (_disposed) throw StateError('The planner controller is disposed.');
    if (_mutationsFrozen) {
      throw StateError('Planner edits are paused while an update restarts.');
    }
    final previous = _document;
    updateDocument(update, immediate: true);
    await flush();
    final error = saveError.value;
    if (error == null) return;

    _saveTimer?.cancel();
    _saveTimer = null;
    _pendingSave = (revision: ++_saveRevision, state: previous);
    _restoreDocument(previous);
    throw StateError('The planner state could not be saved: $error');
  }

  Future<void> finishFirstRunSetup(
    FirstRunSetupAnswers answers, {
    required Iterable<FirstRunSetupGroup> groups,
    String completedForApplicationVersion = '',
  }) => updateDocumentDurably(
    (document) => completeFirstRunSetupDocument(
      document,
      answers,
      groups: groups,
      completedForApplicationVersion: completedForApplicationVersion,
    ),
  );

  /// Dismisses setup for this process only.
  ///
  /// Skip must remain available even when the profile is read-only or the disk
  /// is full. The app owns the session-only dismissal flag; no state is
  /// rewritten here.
  Future<void> skipFirstRunSetup() async {
    if (_disposed) throw StateError('The planner controller is disposed.');
  }

  void updateAllModes(
    ModeState Function(CraftMode mode, ModeState current) update, {
    bool immediate = false,
  }) {
    updateDocument(
      (document) => document.copyWith(
        alchemy: update(CraftMode.alchemy, document.alchemy),
        cooking: update(CraftMode.cooking, document.cooking),
        processing: update(CraftMode.processing, document.processing),
      ),
      immediate: immediate,
    );
  }

  Future<void> flush() async {
    if (_disposed) return;
    _saveTimer?.cancel();
    _saveTimer = null;
    _enqueuePendingSave();
    final tail = _saveTail;
    if (tail != null) await tail;
  }

  void _replaceMode(CraftMode mode, ModeState next, {bool immediate = false}) {
    if (_disposed || _mutationsFrozen) return;
    _document = _withMode(_document, mode, next);
    modes[mode]!._replaceState(next, persist: false);
    _scheduleSave(immediate: immediate);
  }

  void _restoreDocument(PlannerState state) {
    _document = state;
    if (activeMode.value != state.activeMode) {
      activeMode.value = state.activeMode;
    }
    if (deleteToolsEnabled.value != state.showDeleteTools) {
      deleteToolsEnabled.value = state.showDeleteTools;
    }
    if (!identical(marketTax.value, state.marketTax)) {
      marketTax.value = state.marketTax;
    }
    if (!identical(afkWeightProfile.value, state.afkWeightProfile)) {
      afkWeightProfile.value = state.afkWeightProfile;
    }
    _syncResourceMapFavoriteIds(state);
    _syncResourceMapNodeNetworkPreferences(state);
    _syncResourceMapGatherChecklist(state);
    for (final mode in CraftMode.values) {
      modes[mode]!._replaceState(state.forMode(mode), persist: false);
    }
  }

  void _syncResourceMapFavoriteIds(PlannerState state) {
    final next = _resourceMapFavoriteIdsFrom(state);
    if (!setEquals(resourceMapFavoriteIds.value, next)) {
      resourceMapFavoriteIds.value = next;
    }
  }

  void _syncResourceMapNodeNetworkPreferences(PlannerState state) {
    final next = _resourceMapNodeNetworkPreferencesFrom(state);
    if (!resourceMapNodeNetworkPreferences.value.sameValuesAs(next)) {
      resourceMapNodeNetworkPreferences.value = next;
    }
  }

  void _syncResourceMapGatherChecklist(PlannerState state) {
    final next = _resourceMapGatherChecklistFrom(state);
    if (resourceMapGatherChecklist.value != next) {
      resourceMapGatherChecklist.value = next;
    }
  }

  void _scheduleSave({required bool immediate}) {
    _pendingSave = (revision: ++_saveRevision, state: _document);
    _saveTimer?.cancel();
    _saveTimer = null;
    if (immediate || saveDebounce == Duration.zero) {
      _enqueuePendingSave();
      return;
    }
    _saveTimer = Timer(saveDebounce, _enqueuePendingSave);
  }

  void _enqueuePendingSave() {
    if (_disposed && _pendingSave == null) return;
    final pending = _pendingSave;
    if (pending == null) return;
    _pendingSave = null;
    final previous = _saveTail ?? Future<void>.value();
    final next = previous.then((_) async {
      saving.value = true;
      try {
        final committed = await saveState(pending.state);
        saveError.value = null;
        if (identical(_document, pending.state)) _document = committed;
      } on Object catch (error) {
        saveError.value = '$error';
        if (_pendingSave == null && pending.revision == _saveRevision) {
          _pendingSave = pending;
        }
      } finally {
        saving.value = false;
      }
    });
    _saveTail = next;
    unawaited(
      next.whenComplete(() {
        if (identical(_saveTail, next)) _saveTail = null;
      }),
    );
  }

  Future<void> dispose() => _disposeFuture ??= _dispose();

  Future<void> _dispose() async {
    if (_disposed) return;
    await flush();
    _disposed = true;
    _saveTimer?.cancel();
    activeMode.dispose();
    deleteToolsEnabled.dispose();
    marketTax.dispose();
    afkWeightProfile.dispose();
    resourceMapFavoriteIds.dispose();
    resourceMapNodeNetworkPreferences.dispose();
    resourceMapGatherChecklist.dispose();
    saving.dispose();
    saveError.dispose();
    for (final controller in modes.values) {
      controller.dispose();
    }
  }
}

Set<String> _resourceMapFavoriteIdsFrom(PlannerState state) {
  final resourceMap = state.extensions[_resourceMapExtensionKey];
  if (resourceMap is! Map) return const <String>{};
  final favoriteIds = resourceMap[_resourceMapFavoriteIdsKey];
  if (favoriteIds is! Iterable || favoriteIds is String) {
    return const <String>{};
  }
  return _normalizedResourceMapFavoriteIds(favoriteIds.whereType<String>());
}

BdoNodeNetworkPreferences _resourceMapNodeNetworkPreferencesFrom(
  PlannerState state,
) {
  final resourceMap = state.extensions[_resourceMapExtensionKey];
  if (resourceMap is! Map) return BdoNodeNetworkPreferences();
  return BdoNodeNetworkPreferences.fromJson(
    resourceMap[_resourceMapNodeNetworkKey],
  );
}

BdoGatherChecklist _resourceMapGatherChecklistFrom(PlannerState state) {
  final resourceMap = state.extensions[_resourceMapExtensionKey];
  if (resourceMap is! Map) return BdoGatherChecklist();
  return BdoGatherChecklist.fromJson(
    resourceMap[_resourceMapGatherChecklistKey],
  );
}

Set<String> _normalizedResourceMapFavoriteIds(Iterable<String> favoriteIds) =>
    Set<String>.unmodifiable(
      favoriteIds.map((id) => id.trim()).where((id) => id.isNotEmpty),
    );

final class RecipeTargetIngredientSelection {
  const RecipeTargetIngredientSelection({
    required this.ingredientName,
    required this.selectedIngredientName,
    this.grade = 'normal',
  });

  final String ingredientName;
  final String selectedIngredientName;
  final String grade;
}

final class ModeFeatureController {
  ModeFeatureController._({
    required this.owner,
    required this.mode,
    required ModeState initialState,
  }) : state = ValueNotifier(initialState),
       expandedSteps = ValueNotifier(const <String>{}),
       priceRowsVisible = ValueNotifier(false) {
    plan = ValueNotifier(_buildPlan(initialState));
  }

  final PlannerApplicationController owner;
  final CraftMode mode;
  final ValueNotifier<ModeState> state;
  late final ValueNotifier<planning.PlanResult> plan;
  final ValueNotifier<Set<String>> expandedSteps;
  final ValueNotifier<bool> priceRowsVisible;

  Map<String, Recipe>? _recipesCache;
  Map<String, RecipeState?>? _recipeEditsSource;
  Map<String, IngredientMetadata>? _ingredientMetaSource;
  Set<String>? _hiddenItemsSource;
  Map<String, Recipe>? _craftableNamesRecipes;
  List<String>? _craftableNamesCache;

  Map<String, Recipe> get recipes => _recipesFor(state.value);

  Recipe? recipeDefinition(String name) {
    final key = _exactOrFolded(recipes, name);
    return key == null ? null : recipes[key];
  }

  Recipe? selectedRecipe(String name) {
    final recipe = recipeDefinition(name);
    if (recipe == null) return null;
    return recipe.resolveVariant(
      _foldedValue(state.value.recipeVariantChoices, recipe.name),
    );
  }

  /// Resolves one real recipe attempt with the same substitute and quality
  /// rules as the active plan. Presentation code uses this for learning labels
  /// instead of dividing a rounded multi-attempt total back down.
  planning.PlanStepIngredient previewIngredientSelection({
    required String parentName,
    required Ingredient ingredient,
  }) => owner.assembly.engine.previewIngredientSelection(
    recipes: recipes,
    state: owner.assembly.plannerState(state.value),
    parentName: parentName,
    ingredient: ingredient,
    rules: owner.plannerRules,
  );

  String? selectedRecipeVariantId(String name) {
    final recipe = recipeDefinition(name);
    if (recipe == null) return null;
    return recipe.resolvedVariantId(
      _foldedValue(state.value.recipeVariantChoices, recipe.name),
    );
  }

  List<String> get craftableNames {
    final assembled = recipes;
    if (identical(_craftableNamesRecipes, assembled)) {
      return _craftableNamesCache!;
    }
    final names =
        assembled.entries
            .where((entry) => entry.value.isCraftable)
            .map((entry) => entry.key)
            .toList()
          ..sort(_compareNames);
    _craftableNamesRecipes = assembled;
    return _craftableNamesCache = List<String>.unmodifiable(names);
  }

  planning.ResolvedSourceInfo resolveItemSource(String name, {Recipe? recipe}) {
    final assembled = recipe == null ? recipes : const <String, Recipe>{};
    final recipeKey = recipe == null ? _exactOrFolded(assembled, name) : null;
    final resolved = resolveSourceInfo(
      name: name,
      recipe: recipe ?? (recipeKey == null ? null : assembled[recipeKey]),
      rules: owner.plannerRules,
    );
    return planning.ResolvedSourceInfo(
      sourceNote: displayableUserSourceNote(state.value, name),
      vendor: resolved.vendor,
      role: resolved.role,
      location: resolved.location,
      npcPrice: resolved.npcPrice,
    );
  }

  planning.ItemAcquisitionRule? resolveItemAcquisition(String name) =>
      acquisition.resolveItemAcquisition(name: name, rules: owner.plannerRules);

  bool get advancedEditorEnabled => owner.deleteToolsEnabled.value;

  void navigate(String view) {
    const valid = {
      'plan',
      'bonus',
      'inventory',
      'editor',
      'appearance',
      'data',
    };
    var destination = valid.contains(view) ? view : 'plan';
    if (!advancedEditorEnabled &&
        (destination == 'inventory' || destination == 'editor')) {
      destination = 'plan';
    }
    if (mode == CraftMode.processing && destination == 'bonus') return;
    if (state.value.view == destination) return;
    _commit(state.value.copyWith(view: destination), immediate: true);
  }

  bool selectTarget(String name) {
    final match = _exactOrFolded(recipes, name);
    if (match == null || !recipes[match]!.isCraftable) return false;
    expandedSteps.value = const <String>{};
    _commit(
      state.value.copyWith(target: match, completedSteps: const <String>{}),
      immediate: true,
    );
    return true;
  }

  /// Selects a target and one of its complete recipe variants in one state
  /// commit. Used In results can therefore open a route or batch that actually
  /// contains the queried material instead of briefly targeting the saved
  /// default formula first.
  bool selectTargetVariant(
    String name, {
    String? variantId,
    bool bonus = false,
    Iterable<RecipeTargetIngredientSelection> ingredientSelections =
        const <RecipeTargetIngredientSelection>[],
  }) {
    final match = _exactOrFolded(recipes, name);
    if (match == null) return false;
    final recipe = recipes[match]!;
    if (!recipe.isCraftable) return false;

    RecipeVariant? selected;
    final requestedVariant = variantId?.trim();
    if (requestedVariant != null && requestedVariant.isNotEmpty) {
      selected = recipe.variantById(requestedVariant);
      if (selected == null) return false;
    }

    final choices = Map<String, String>.of(state.value.recipeVariantChoices)
      ..removeWhere((recipeName, _) => _fold(recipeName) == _fold(match));
    if (selected != null) choices[match] = selected.id;
    final effectiveRecipe = recipe.resolveVariant(selected?.id);
    final substitutes = Map<String, String>.of(state.value.substituteChoices);
    final grades = Map<String, String>.of(state.value.ingredientGrades);
    for (final requested in ingredientSelections) {
      Ingredient? ingredient;
      for (final candidate in effectiveRecipe.ingredients) {
        if (_fold(candidate.name) == _fold(requested.ingredientName)) {
          ingredient = candidate;
          break;
        }
      }
      if (ingredient == null) return false;

      final selectableNames = ingredient.options.isEmpty
          ? <String>[ingredient.name]
          : ingredient.options;
      String? selectedName;
      for (final candidate in selectableNames) {
        if (_fold(candidate) == _fold(requested.selectedIngredientName)) {
          selectedName = candidate;
          break;
        }
      }
      if (selectedName == null) return false;

      final substituteKey =
          'recipe:$match:${ingredient.substituteGroup ?? ingredient.name}';
      substitutes.removeWhere((key, _) => _fold(key) == _fold(substituteKey));
      if (ingredient.options.isNotEmpty) {
        substitutes[substituteKey] = selectedName;
      }

      final normalizedGrade = normalizeIngredientQualityGrade(requested.grade);
      final quality = ingredientQualityProfile(
        rules: owner.plannerRules,
        parentIsProcessing:
            effectiveRecipe.type.trim().toLowerCase() == 'processing',
        ingredientName: selectedName,
      );
      if (normalizedGrade != 'normal' &&
          !quality.grades.contains(normalizedGrade)) {
        return false;
      }
      final gradeKey = 'recipe:$match:${ingredient.name}';
      grades.removeWhere((key, _) => _fold(key) == _fold(gradeKey));
      if (normalizedGrade != 'normal') {
        grades[gradeKey] = normalizedGrade;
      }
    }
    expandedSteps.value = const <String>{};
    _commit(
      state.value.copyWith(
        target: bonus ? state.value.target : match,
        bonusTarget: bonus ? match : state.value.bonusTarget,
        recipeVariantChoices: choices,
        substituteChoices: substitutes,
        ingredientGrades: grades,
        completedSteps: bonus ? state.value.completedSteps : const <String>{},
      ),
      immediate: true,
    );
    return true;
  }

  bool commitAmount(String text, {bool bonus = false}) {
    final value = parsePlannerNumber(text);
    if (value == null) return false;
    final amount = value.floor().clamp(1, 0x7fffffff);
    expandedSteps.value = const <String>{};
    _commit(
      bonus
          ? state.value.copyWith(bonusWant: amount)
          : state.value.copyWith(
              want: amount,
              completedSteps: const <String>{},
              market: state.value.market.copyWith(amount: amount),
            ),
      immediate: true,
    );
    return true;
  }

  void setFullTargetAmount(bool fullAmount) => _commit(
    state.value.copyWith(ignoreTargetInventory: fullAmount),
    immediate: true,
  );

  void setIgnoreOwnedIngredients(bool ignore) => _commit(
    state.value.copyWith(ignoreIngredientInventory: ignore),
    immediate: true,
  );

  void resetCompleted() => _commit(
    state.value.copyWith(completedSteps: const <String>{}),
    immediate: true,
  );

  void toggleCompleted(String recipeName) {
    final completed = Set<String>.of(state.value.completedSteps);
    final existing = _foldedIn(completed, recipeName);
    if (existing == null) {
      completed.add(recipeName);
    } else {
      completed.remove(existing);
    }
    _commit(state.value.copyWith(completedSteps: completed), immediate: true);
  }

  void toggleIngredients(String recipeName) {
    final next = Set<String>.of(expandedSteps.value);
    final existing = _foldedIn(next, recipeName);
    if (existing == null) {
      next.add(recipeName);
    } else {
      next.remove(existing);
    }
    expandedSteps.value = Set.unmodifiable(next);
  }

  void selectSubstitute({
    required String parentName,
    required Ingredient ingredient,
    required String selection,
  }) {
    if (!ingredient.options.any(
      (option) => _fold(option) == _fold(selection),
    )) {
      return;
    }
    final choices = Map<String, String>.of(state.value.substituteChoices);
    choices['recipe:$parentName:${ingredient.substituteGroup ?? ingredient.name}'] =
        selection;
    _commit(state.value.copyWith(substituteChoices: choices), immediate: true);
  }

  bool selectRecipeVariant({
    required String recipeName,
    required String variantId,
  }) {
    final recipe = recipeDefinition(recipeName);
    final selected = recipe?.variantById(variantId);
    if (recipe == null || !recipe.hasRecipeVariants || selected == null) {
      return false;
    }
    final choices = Map<String, String>.of(state.value.recipeVariantChoices)
      ..removeWhere((name, _) => _fold(name) == _fold(recipe.name));
    choices[recipe.name] = selected.id;
    final completed = state.value.completedSteps
        .where((name) => _fold(name) != _fold(recipe.name))
        .toSet();
    _commit(
      state.value.copyWith(
        recipeVariantChoices: choices,
        completedSteps: completed,
      ),
      immediate: true,
    );
    return true;
  }

  void selectIngredientGrade({
    required String parentName,
    required String ingredientName,
    required String grade,
  }) {
    const allowed = {'normal', 'high', 'special', 'blue'};
    final normalized = grade.trim().toLowerCase();
    if (!allowed.contains(normalized)) return;
    final grades = Map<String, String>.of(state.value.ingredientGrades);
    grades['recipe:$parentName:$ingredientName'] = normalized;
    _commit(state.value.copyWith(ingredientGrades: grades), immediate: true);
  }

  IngredientQualityProfile qualityProfile({
    required String parentName,
    required String selectedName,
  }) {
    final parent = selectedRecipe(parentName);
    return ingredientQualityProfile(
      rules: owner.plannerRules,
      parentIsProcessing: parent?.type.trim().toLowerCase() == 'processing',
      ingredientName: selectedName,
    );
  }

  List<String> availableIngredientGrades({
    required String parentName,
    required String selectedName,
  }) =>
      qualityProfile(parentName: parentName, selectedName: selectedName).grades;

  String selectedIngredientGrade({
    required String parentName,
    required String ingredientName,
    required String selectedName,
  }) {
    final parent = selectedRecipe(parentName);
    return selectedIngredientQualityGrade(
      rules: owner.plannerRules,
      parentIsProcessing: parent?.type.trim().toLowerCase() == 'processing',
      parentName: parentName,
      originalIngredientName: ingredientName,
      selectedIngredientName: selectedName,
      savedGrades: state.value.ingredientGrades,
    );
  }

  bool commitInventory(String name, String text) {
    final value = parsePlannerNumber(text);
    if (value == null || value < 0) return false;
    final storage = InventoryStorageState.fromModeState(state.value)
        .setQuantity(
          locationId: inventoryUnassignedLocationId,
          itemName: name,
          quantity: value,
        );
    _commit(storage.applyTo(state.value));
    return true;
  }

  void addMissingAmount(String name, double amount) {
    if (!amount.isFinite || amount <= 0) return;
    final storage = InventoryStorageState.fromModeState(state.value)
        .addQuantity(
          locationId: inventoryUnassignedLocationId,
          itemName: name,
          quantity: amount,
        );
    _commit(storage.applyTo(state.value), immediate: true);
  }

  InventoryStorageState get inventoryStorage =>
      InventoryStorageState.fromModeState(state.value);

  String ensureInventoryStorageLocation(String name) {
    final ensured = inventoryStorage.ensureLocation(name);
    _commit(ensured.state.applyTo(state.value), immediate: true);
    return ensured.location.id;
  }

  void selectInventoryStorageLocation(String locationId) {
    final current = inventoryStorage;
    final next = current.select(locationId);
    if (identical(next, current)) return;
    _commit(next.applyTo(state.value));
  }

  bool setInventoryStorageQuantity({
    required String locationId,
    required String itemName,
    required String text,
  }) {
    final value = parsePlannerNumber(text);
    if (value == null || value < 0) return false;
    final next = inventoryStorage.setQuantity(
      locationId: locationId,
      itemName: itemName,
      quantity: value,
    );
    _commit(next.applyTo(state.value));
    return true;
  }

  void applyReviewedInventoryScreenshot({
    required String locationId,
    required Map<String, double> quantities,
    bool replaceMatchingUnassigned = false,
  }) {
    final next = inventoryStorage.applyReviewedScreenshot(
      locationId: locationId,
      quantities: quantities,
      replaceMatchingUnassigned: replaceMatchingUnassigned,
    );
    _commit(next.applyTo(state.value), immediate: true);
  }

  String applyReviewedInventoryScreenshotToLocation({
    required String locationName,
    required Map<String, double> quantities,
  }) {
    final current = inventoryStorage;
    final ensured = current.ensureLocation(locationName);
    final next = ensured.state.applyReviewedScreenshot(
      locationId: ensured.location.id,
      quantities: quantities,
      replaceMatchingUnassigned: !current.hadPersistedLedger,
    );
    _commit(next.applyTo(state.value), immediate: true);
    return ensured.location.id;
  }

  Future<String> applyReviewedInventoryScreenshotToLocationDurably({
    required String locationName,
    required Map<String, double> quantities,
  }) async {
    var locationId = inventoryUnassignedLocationId;
    await owner.updateDocumentDurably((document) {
      final modeState = document.forMode(mode);
      final current = InventoryStorageState.fromModeState(modeState);
      final ensured = current.ensureLocation(locationName);
      locationId = ensured.location.id;
      final next = ensured.state.applyReviewedScreenshot(
        locationId: locationId,
        quantities: quantities,
        replaceMatchingUnassigned: !current.hadPersistedLedger,
      );
      return _withMode(document, mode, next.applyTo(modeState));
    });
    return locationId;
  }

  void renameInventoryStorageLocation(String locationId, String name) {
    final next = inventoryStorage.renameLocation(locationId, name);
    _commit(next.applyTo(state.value), immediate: true);
  }

  void removeInventoryStorageLocation(String locationId) {
    final next = inventoryStorage.removeLocation(locationId);
    _commit(next.applyTo(state.value), immediate: true);
  }

  void clearInventoryStorage() {
    final next = inventoryStorage.clearQuantities();
    _commit(next.applyTo(state.value), immediate: true);
  }

  void replaceMarketValues({
    required Map<String, double> prices,
    required Map<String, double> stock,
    required Iterable<String> unlistedItemNames,
    required int fetchedAt,
    Map<String, String>? tradeMarketIds,
    Map<String, int>? totalTrades,
    Map<String, int>? tradeObservedAt,
    Map<String, double>? observedDailyTrades,
    Map<String, double>? tradeObservationHours,
    Map<String, int>? lastSoldAtEpochSeconds,
    String? region,
  }) => _commit(
    state.value.copyWith(
      market: state.value.market.copyWith(
        prices: prices,
        stock: stock,
        tradeMarketIds: tradeMarketIds,
        totalTrades: totalTrades,
        tradeObservedAt: tradeObservedAt,
        observedDailyTrades: observedDailyTrades,
        tradeObservationHours: tradeObservationHours,
        lastSoldAtEpochSeconds: lastSoldAtEpochSeconds,
        unlistedItemNames: unlistedItemNames,
        fetchedAt: fetchedAt,
        region: region ?? state.value.market.region,
      ),
    ),
    immediate: true,
  );

  void setPricesVisible(bool visible) => priceRowsVisible.value = visible;

  void toggleFavorite(String recipeName) {
    final favorites = Set<String>.of(state.value.favoriteRecipes);
    final existing = _foldedIn(favorites, recipeName);
    if (existing == null) {
      favorites.add(recipeName);
    } else {
      favorites.remove(existing);
    }
    final sorted = favorites.toList()..sort(_compareNames);
    _commit(state.value.copyWith(favoriteRecipes: sorted), immediate: true);
  }

  void useBonusAsTarget() {
    final bonusTarget = state.value.bonusTarget;
    if (bonusTarget.trim().isEmpty) return;
    expandedSteps.value = const <String>{};
    _commit(
      state.value.copyWith(
        target: bonusTarget,
        want: state.value.bonusWant,
        view: 'plan',
        completedSteps: const <String>{},
      ),
      immediate: true,
    );
  }

  void recalculate() => _replaceState(state.value, persist: false);

  void updateState(
    ModeState Function(ModeState current) update, {
    bool immediate = false,
  }) => _commit(update(state.value), immediate: immediate);

  void _commit(ModeState next, {bool immediate = false}) =>
      owner._replaceMode(mode, next, immediate: immediate);

  void _replaceState(ModeState next, {required bool persist}) {
    state.value = next;
    plan.value = _buildPlan(next);
    if (persist) owner._replaceMode(mode, next);
  }

  Map<String, Recipe> _recipesFor(ModeState source) {
    final cached = _recipesCache;
    if (cached != null &&
        mapEquals(_recipeEditsSource, source.recipeEdits) &&
        mapEquals(_ingredientMetaSource, source.ingredientMeta) &&
        setEquals(_hiddenItemsSource, source.hiddenItems)) {
      return cached;
    }
    final assembled = owner.assembly.assembleRecipes(
      catalog: owner.catalog.forMode(mode),
      state: source,
      supportingData: owner.catalog.supportingData,
      sharedMetadata: owner.catalog.alchemy.metadata,
      mode: mode,
    );
    _recipeEditsSource = source.recipeEdits;
    _ingredientMetaSource = source.ingredientMeta;
    _hiddenItemsSource = source.hiddenItems;
    _recipesCache = assembled;
    _craftableNamesRecipes = null;
    _craftableNamesCache = null;
    return assembled;
  }

  planning.PlanResult _buildPlan(ModeState source) =>
      owner.assembly.engine.buildPlan(
        mode: mode,
        recipes: _recipesFor(source),
        state: owner.assembly.plannerState(source),
        rules: owner.plannerRules,
      );

  void dispose() {
    state.dispose();
    plan.dispose();
    expandedSteps.dispose();
    priceRowsVisible.dispose();
  }
}

PlannerState _withMode(
  PlannerState document,
  CraftMode mode,
  ModeState value,
) => switch (mode) {
  CraftMode.alchemy => document.copyWith(alchemy: value),
  CraftMode.cooking => document.copyWith(cooking: value),
  CraftMode.processing => document.copyWith(processing: value),
};

String? _exactOrFolded<T>(Map<String, T> values, String name) {
  if (values.containsKey(name)) return name;
  for (final key in values.keys) {
    if (_fold(key) == _fold(name)) return key;
  }
  return null;
}

String? _foldedIn(Iterable<String> values, String name) {
  for (final value in values) {
    if (_fold(value) == _fold(name)) return value;
  }
  return null;
}

String _fold(String value) => value.trim().toLowerCase();

int _compareNames(String left, String right) =>
    left.toLowerCase().compareTo(right.toLowerCase());

T? _foldedValue<T>(Map<String, T> values, String name) {
  final exact = values[name];
  if (exact != null) return exact;
  for (final entry in values.entries) {
    if (_fold(entry.key) == _fold(name)) return entry.value;
  }
  return null;
}
