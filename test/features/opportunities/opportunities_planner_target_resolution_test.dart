import 'dart:convert';
import 'dart:io';

import 'package:bdo_craft_planner_flutter/data/catalog/catalog_repository.dart';
import 'package:bdo_craft_planner_flutter/data/opportunities/opportunity_market_service.dart';
import 'package:bdo_craft_planner_flutter/domain/models/catalog_models.dart';
import 'package:bdo_craft_planner_flutter/domain/models/craft_mode.dart';
import 'package:bdo_craft_planner_flutter/domain/state/planner_state.dart';
import 'package:bdo_craft_planner_flutter/domain/state/state_copy.dart';
import 'package:bdo_craft_planner_flutter/features/opportunities/opportunities_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/application_test_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late ApplicationTestHarness harness;
  late OpportunitiesController opportunities;
  late _NoNetwork transport;

  setUp(() async {
    harness = await ApplicationTestHarness.create();
    transport = _NoNetwork();
    opportunities = OpportunitiesController(
      appController: harness.bundle.controller,
      catalog: CatalogRepository(harness.bundle.catalog),
      directory: Directory('${harness.temporaryDirectory.path}/opportunities'),
      serviceFactory: (region) =>
          OpportunityMarketService(region: region, transport: transport),
    );
    await opportunities.ready;
    opportunities.change((preferences) => preferences.mode = CraftMode.alchemy);
    await opportunities.calculationSettled;
  });

  tearDown(() async {
    expect(transport.requests, isEmpty, reason: 'Target lookup is local only.');
    await opportunities.flush();
    opportunities.dispose();
    await harness.dispose();
  });

  Future<void> edit(
    CraftMode mode,
    ModeState Function(ModeState) update,
  ) async {
    harness.bundle.controller.modes[mode]!.updateState(update);
    await opportunities.calculationSettled;
  }

  test(
    'bundled cross-mode name resolves exactly without selecting a target',
    () {
      expect(opportunities.preferences.mode, CraftMode.alchemy);
      final request = opportunities.plannerTargetFor('  bEeR  ');
      expect(request, isNotNull);
      expect(request!.exactName, 'Beer');
      expect(request.mode, CraftMode.cooking);
      expect(request.variantId, isNull);
      expect(opportunities.preferences.mode, CraftMode.alchemy);
      expect(harness.bundle.controller.activeMode.value, CraftMode.alchemy);
      expect(
        opportunities.plannerTargetFor('Beer', mode: CraftMode.alchemy),
        isNull,
      );
      expect(opportunities.plannerTargetFor('  '), isNull);
      expect(opportunities.plannerTargetFor('Unknown target material'), isNull);
    },
  );

  test(
    'new live custom recipes are discovered without a cached bundled list',
    () async {
      const name = 'My Small-Batch Tonic';
      expect(opportunities.plannerTargetFor(name), isNull);
      await edit(
        CraftMode.alchemy,
        (state) => state.copyWith(
          recipeEdits: {...state.recipeEdits, name: _craftRecipe()},
        ),
      );
      final request = opportunities.plannerTargetFor(' my small-batch tonic ');
      expect(request!.exactName, name);
      expect(request.mode, CraftMode.alchemy);
      await edit(
        CraftMode.alchemy,
        (state) =>
            state.copyWith(recipeEdits: {...state.recipeEdits, name: null}),
      );
      expect(opportunities.plannerTargetFor(name), isNull);
    },
  );

  test(
    'hidden and deleted bundled targets never reappear from catalog fallback',
    () async {
      expect(opportunities.plannerTargetFor('Beer'), isNotNull);
      await edit(
        CraftMode.cooking,
        (state) => state.copyWith(hiddenItems: {...state.hiddenItems, 'Beer'}),
      );
      expect(opportunities.plannerTargetFor('beer'), isNull);
      await edit(
        CraftMode.cooking,
        (state) => state.copyWith(
          hiddenItems: state.hiddenItems.where((name) => name != 'Beer'),
          recipeEdits: {...state.recipeEdits, 'Beer': null},
        ),
      );
      expect(opportunities.plannerTargetFor('Beer'), isNull);
      expect(harness.bundle.catalog.cooking.items.containsKey('Beer'), isTrue);
    },
  );

  test(
    'live noncraftable edits override formerly craftable bundled recipes',
    () async {
      for (final replacement in [
        RecipeState(type: 'gathered'),
        _craftRecipe(role: RecipeRole.manualConversion),
        _craftRecipe(role: RecipeRole.salvage),
      ]) {
        await edit(
          CraftMode.cooking,
          (state) => state.copyWith(
            recipeEdits: {...state.recipeEdits, 'Beer': replacement},
          ),
        );
        expect(opportunities.plannerTargetFor('Beer'), isNull);
      }
      await edit(
        CraftMode.cooking,
        (state) => state.copyWith(
          recipeEdits: {...state.recipeEdits, 'Beer': _craftRecipe()},
        ),
      );
      expect(opportunities.plannerTargetFor('Beer')!.exactName, 'Beer');
    },
  );

  test('rare-result lookup does not silently target its normal recipe', () {
    final cooking = harness.bundle.controller.modes[CraftMode.cooking]!;
    final rare = cooking.recipes.values.firstWhere(
      (recipe) =>
          recipe.qualityBase != null &&
          !recipe.isCraftable &&
          cooking.recipeDefinition(recipe.qualityBase!)?.isCraftable == true,
    );
    expect(
      opportunities.plannerTargetFor(rare.name, mode: CraftMode.cooking),
      isNull,
    );
    expect(
      opportunities
          .plannerTargetFor(rare.qualityBase!, mode: CraftMode.cooking)!
          .exactName,
      rare.qualityBase,
    );
    expect(opportunities.plannerTargetFor('Mineral Water'), isNull);
  });

  test(
    'archived identity stays unavailable even with a custom formula',
    () async {
      await edit(
        CraftMode.alchemy,
        (state) => state.copyWith(
          recipeEdits: {
            ...state.recipeEdits,
            'Monkey Blood': _craftRecipe(),
            'Archived identity alias': _craftRecipe(marketId: '6211'),
          },
        ),
      );
      for (final name in ['Monkey Blood', 'Archived identity alias']) {
        expect(
          harness.bundle.controller.modes[CraftMode.alchemy]!
              .recipeDefinition(name)
              ?.isCraftable,
          isTrue,
          reason:
              'The archive policy, not a missing formula, rejects this target.',
        );
      }
      expect(opportunities.plannerTargetFor('Monkey Blood'), isNull);
      expect(opportunities.plannerTargetFor('Archived identity alias'), isNull);
    },
  );

  test(
    'duplicate custom names prefer active opportunity mode and honor explicit mode',
    () async {
      const name = 'Cross-mode custom target';
      for (final mode in CraftMode.values) {
        await edit(
          mode,
          (state) => state.copyWith(
            recipeEdits: {...state.recipeEdits, name: _craftRecipe()},
          ),
        );
      }
      opportunities.change(
        (preferences) => preferences.mode = CraftMode.processing,
      );
      await opportunities.calculationSettled;
      expect(opportunities.plannerTargetFor(name)!.mode, CraftMode.processing);
      for (final mode in CraftMode.values) {
        expect(opportunities.plannerTargetFor(name, mode: mode)!.mode, mode);
      }
      await edit(
        CraftMode.processing,
        (state) => state.copyWith(hiddenItems: {...state.hiddenItems, name}),
      );
      expect(
        opportunities.plannerTargetFor(name, mode: CraftMode.processing),
        isNull,
      );
      expect(
        opportunities.plannerTargetFor(name)!.mode,
        isNot(CraftMode.processing),
      );
    },
  );

  test('explicit variants must belong to the resolved live recipe', () async {
    final owner = harness.bundle.controller.modes.values.firstWhere(
      (controller) => controller.recipes.values.any(
        (recipe) => recipe.isCraftable && recipe.variants.length > 1,
      ),
    );
    final recipe = owner.recipes.values.firstWhere(
      (recipe) => recipe.isCraftable && recipe.variants.length > 1,
    );
    final variant = recipe.variants.last;
    await edit(
      owner.mode,
      (state) => state.copyWith(
        recipeVariantChoices: {
          ...state.recipeVariantChoices,
          recipe.name: variant.id,
        },
      ),
    );
    final before = owner.state.value;
    final explicit = opportunities.plannerTargetFor(
      recipe.name,
      mode: owner.mode,
      variantId: variant.id,
    );
    expect(explicit!.exactName, recipe.name);
    expect(explicit.variantId, variant.id);
    expect(
      opportunities.plannerTargetFor(recipe.name, mode: owner.mode)!.variantId,
      isNull,
    );
    for (final invalid in ['', 'missing-variant-id']) {
      expect(
        opportunities.plannerTargetFor(
          recipe.name,
          mode: owner.mode,
          variantId: invalid,
        ),
        isNull,
      );
    }
    expect(identical(owner.state.value, before), isTrue);
    expect(owner.selectedRecipeVariantId(recipe.name), variant.id);
    expect(
      opportunities.plannerTargetFor(
        'Beer',
        mode: CraftMode.cooking,
        variantId: 'unrelated-variant',
      ),
      isNull,
    );
  });

  test(
    'read-only resolution does not mutate navigation, plan, inventory or preferences',
    () {
      final application = harness.bundle.controller;
      final before = jsonEncode(application.documentSnapshot.toJson());
      final preferences = jsonEncode(opportunities.preferences.toJson());
      final states = {
        for (final entry in application.modes.entries)
          entry.key: entry.value.state.value,
      };
      final plans = {
        for (final entry in application.modes.entries)
          entry.key: entry.value.plan.value,
      };
      var notifications = 0;
      opportunities.addListener(() => notifications++);
      for (final name in [
        'Beer',
        'Clear Liquid Reagent',
        'Mineral Water',
        '',
        'Unknown',
      ]) {
        opportunities.plannerTargetFor(name);
        for (final mode in CraftMode.values) {
          opportunities.plannerTargetFor(name, mode: mode);
          opportunities.plannerTargetFor(
            name,
            mode: mode,
            variantId: 'invalid',
          );
        }
      }
      expect(jsonEncode(application.documentSnapshot.toJson()), before);
      expect(jsonEncode(opportunities.preferences.toJson()), preferences);
      for (final entry in application.modes.entries) {
        expect(identical(entry.value.state.value, states[entry.key]), isTrue);
        expect(identical(entry.value.plan.value, plans[entry.key]), isTrue);
      }
      expect(notifications, 0);
      expect(transport.requests, isEmpty);
    },
  );
}

RecipeState _craftRecipe({
  RecipeRole role = RecipeRole.production,
  String? marketId,
}) => RecipeState(
  type: 'processing',
  role: role,
  marketId: marketId,
  ingredients: [IngredientState(name: 'Mineral Water', quantity: 1)],
);

class _NoNetwork implements OpportunityMarketTransport {
  final requests = <Uri>[];
  @override
  Future<OpportunityHttpResponse> post(
    Uri uri, {
    required Map<String, String> headers,
    required String body,
    Future<void>? abortTrigger,
  }) async {
    requests.add(uri);
    throw StateError('Planner-target resolution must not request market data.');
  }

  @override
  void close() {}
}
