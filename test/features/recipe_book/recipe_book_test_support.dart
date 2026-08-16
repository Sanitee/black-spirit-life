import 'package:bdo_craft_planner_flutter/app/state/planner_application_controller.dart';
import 'package:bdo_craft_planner_flutter/data/catalog/catalog_repository.dart';
import 'package:bdo_craft_planner_flutter/domain/models/catalog_models.dart';
import 'package:bdo_craft_planner_flutter/domain/models/craft_mode.dart';
import 'package:bdo_craft_planner_flutter/domain/state/planner_state.dart';

const String testIconDataUri =
    'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=';

final class RecipeBookTestEnvironment {
  RecipeBookTestEnvironment({
    required this.application,
    required this.catalogRepository,
  });

  final PlannerApplicationController application;
  final CatalogRepository catalogRepository;

  Future<void> dispose() => application.dispose();
}

RecipeBookTestEnvironment buildRecipeBookTestEnvironment({
  CraftMode activeMode = CraftMode.alchemy,
  bool showDeleteTools = false,
  Set<String> omittedAlchemyIcons = const <String>{},
  SavePlannerState? saveState,
  bool includeRecipeVariants = false,
  bool includeUsedInVariantFixture = false,
  bool includeLongSubstituteFixture = false,
  bool includeNpcPurchaseFixture = false,
  bool includeEdaniaReferenceFixture = false,
}) {
  final catalog = buildRecipeBookCatalog(
    omittedAlchemyIcons: omittedAlchemyIcons,
    includeRecipeVariants: includeRecipeVariants,
    includeUsedInVariantFixture: includeUsedInVariantFixture,
    includeLongSubstituteFixture: includeLongSubstituteFixture,
    includeNpcPurchaseFixture: includeNpcPurchaseFixture,
    includeEdaniaReferenceFixture: includeEdaniaReferenceFixture,
  );
  final state = PlannerState(
    applicationVersion: 'recipe-book-test',
    lastSuccessfulWriteUtc: DateTime.utc(2026, 7, 20),
    activeMode: activeMode,
    alchemy: _modeState(
      CraftMode.alchemy,
      target: 'Clear Liquid Reagent',
      bonusTarget: 'Elixir of Life',
    ),
    cooking: _modeState(
      CraftMode.cooking,
      target: 'Beer',
      bonusTarget: 'Pickled Vegetables',
    ),
    processing: _modeState(
      CraftMode.processing,
      target: 'Black Stone Batch 01',
      bonusTarget: '',
    ),
    processingYields: const <String, double>{'defaultYield': 2.5},
    marketTax: MarketTax(),
    showDeleteTools: showDeleteTools,
  );
  final application = PlannerApplicationController(
    catalog: catalog,
    initialState: state,
    saveDebounce: Duration.zero,
    saveState: saveState ?? (value) async => value,
  );
  return RecipeBookTestEnvironment(
    application: application,
    catalogRepository: CatalogRepository(catalog),
  );
}

CatalogSnapshot buildRecipeBookCatalog({
  Set<String> omittedAlchemyIcons = const <String>{},
  bool includeRecipeVariants = false,
  bool includeUsedInVariantFixture = false,
  bool includeLongSubstituteFixture = false,
  bool includeNpcPurchaseFixture = false,
  bool includeEdaniaReferenceFixture = false,
}) {
  final alchemy = <String, Recipe>{
    'Clear Liquid Reagent': _recipe(
      'Clear Liquid Reagent',
      CraftMode.alchemy,
      group: 'Reagents',
      ingredients: <Ingredient>[
        Ingredient(
          name: 'Wild Grass',
          quantity: 1,
          options: const <String>['Wild Grass', 'Weed'],
          substituteGroup: 'Wild Plants',
          substituteRatios: const <String, double>{'Wild Grass': 1, 'Weed': 5},
        ),
        _ingredient('Sunflower', 2),
      ],
      variants: includeRecipeVariants
          ? <RecipeVariant>[
              RecipeVariant(
                id: 'wild-plants',
                label: 'Wild Plants',
                type: CraftMode.alchemy.key,
                baseOutput: 1,
                method: null,
                ingredients: <Ingredient>[
                  Ingredient(
                    name: 'Wild Grass',
                    quantity: 1,
                    options: const <String>['Wild Grass', 'Weed'],
                    substituteGroup: 'Wild Plants',
                    substituteRatios: const <String, double>{
                      'Wild Grass': 1,
                      'Weed': 5,
                    },
                  ),
                  _ingredient('Sunflower', 2),
                ],
                outputMinimum: 1,
                outputMaximum: 1,
              ),
              RecipeVariant(
                id: 'trace-route',
                label: 'Trace Route',
                type: CraftMode.alchemy.key,
                baseOutput: 1,
                method: null,
                ingredients: <Ingredient>[_ingredient('Trace of Earth', 3)],
                outputMinimum: 1,
                outputMaximum: 1,
              ),
            ]
          : const <RecipeVariant>[],
      defaultVariantId: includeRecipeVariants ? 'wild-plants' : null,
    ),
    'Pure Powder Reagent': _recipe(
      'Pure Powder Reagent',
      CraftMode.alchemy,
      group: 'Reagents',
    ),
    'Elixir of Life': _recipe(
      'Elixir of Life',
      CraftMode.alchemy,
      group: 'Elixirs',
      ingredients: includeUsedInVariantFixture
          ? <Ingredient>[
              _ingredient('Clear Liquid Reagent', 2),
              _ingredient('Sunflower', 3),
            ]
          : null,
      variants: includeUsedInVariantFixture
          ? <RecipeVariant>[
              _variant(
                id: 'classic-1x',
                label: 'Classic',
                routeId: 'classic',
                mode: CraftMode.alchemy,
                ingredients: <Ingredient>[
                  _ingredient('Clear Liquid Reagent', 2),
                  _ingredient('Sunflower', 3),
                ],
              ),
              _variant(
                id: 'classic-10x',
                label: 'Classic',
                routeId: 'classic',
                mode: CraftMode.alchemy,
                batchMultiplier: 10,
                output: 10,
                ingredients: <Ingredient>[
                  _ingredient('Clear Liquid Reagent', 20),
                  _ingredient('Sunflower', 30),
                ],
              ),
              _variant(
                id: 'concentrated-1x',
                label: 'Concentrated',
                routeId: 'concentrated',
                mode: CraftMode.alchemy,
                ingredients: <Ingredient>[
                  _ingredient('Clear Liquid Reagent', 1),
                  _ingredient('Pure Powder Reagent', 2),
                ],
              ),
              _variant(
                id: 'concentrated-10x',
                label: 'Concentrated',
                routeId: 'concentrated',
                mode: CraftMode.alchemy,
                batchMultiplier: 10,
                output: 10,
                ingredients: <Ingredient>[
                  _ingredient('Clear Liquid Reagent', 10),
                  _ingredient('Pure Powder Reagent', 20),
                ],
              ),
            ]
          : const <RecipeVariant>[],
      defaultVariantId: includeUsedInVariantFixture ? 'classic-1x' : null,
    ),
    'Wild Grass': _leaf('Wild Grass'),
    'Weed': _leaf('Weed'),
    'Sunflower': _leaf('Sunflower'),
    'High-Quality Sunflower': _leaf('High-Quality Sunflower'),
    'Special Sunflower': _leaf('Special Sunflower'),
    'Trace of Earth': _leaf('Trace of Earth'),
  };
  if (includeLongSubstituteFixture) {
    alchemy.addAll(<String, Recipe>{
      "Clown's Blood": _recipe(
        "Clown's Blood",
        CraftMode.alchemy,
        group: 'Bloods',
        ingredients: <Ingredient>[
          Ingredient(
            name: 'Cheetah Dragon Blood',
            quantity: 2,
            options: const <String>[
              'Wolf Blood',
              'Flamingo Blood',
              'Rhino Blood',
              'Cheetah Dragon Blood',
            ],
            substituteGroup: 'Blood Group',
            substituteRatios: const <String, double>{
              'Wolf Blood': 1,
              'Flamingo Blood': 1,
              'Rhino Blood': 1,
              'Cheetah Dragon Blood': 1,
            },
          ),
          _ingredient('Clear Liquid Reagent', 1),
        ],
      ),
      'Wolf Blood': _leaf('Wolf Blood'),
      'Flamingo Blood': _leaf('Flamingo Blood'),
      'Rhino Blood': _leaf('Rhino Blood'),
      'Cheetah Dragon Blood': _leaf('Cheetah Dragon Blood'),
    });
  }
  final cooking = <String, Recipe>{
    'Beer': _recipe('Beer', CraftMode.cooking, group: 'Meals'),
    'Grilled Bird Meat': _recipe(
      'Grilled Bird Meat',
      CraftMode.cooking,
      group: 'Meals',
    ),
    'Pickled Vegetables': _recipe(
      'Pickled Vegetables',
      CraftMode.cooking,
      group: 'Meals',
    ),
    'Cooking Ingredient': _leaf('Cooking Ingredient'),
  };
  final processing = <String, Recipe>{};
  for (var index = 1; index <= 36; index++) {
    final number = index.toString().padLeft(2, '0');
    final name = switch (index % 9) {
      0 => 'Mystic Beast Fragment $number',
      1 => 'Black Stone Batch $number',
      2 => 'Crystal Shard $number',
      3 =>
        index == 3
            ? 'Lightstone Fragment $number'
            : 'Elixir Concentrate $number',
      4 => 'Wheat Flour $number',
      5 => 'Cedar Plywood $number',
      6 => 'Iron Ingot $number',
      7 => 'Cotton Fabric $number',
      _ => 'Processed Material $number',
    };
    processing[name] = _recipe(
      name,
      CraftMode.processing,
      group: 'Processing',
      method: index.isEven ? 'Heating' : 'Grinding',
      ingredients: <Ingredient>[_ingredient('Raw Material $number', 2)],
    );
    processing['Raw Material $number'] = _leaf('Raw Material $number');
  }
  if (includeNpcPurchaseFixture) {
    processing['Mystical Parchment'] = _leaf('Mystical Parchment');
  }
  if (includeEdaniaReferenceFixture) {
    processing.addAll(<String, Recipe>{
      'Dawnbound Ekleta Necklace': _recipe(
        'Dawnbound Ekleta Necklace',
        CraftMode.processing,
        group: 'Reference - Accessory Reform',
        method: 'Item Reform',
        role: RecipeRole.manualConversion,
        ingredients: <Ingredient>[
          _ingredient('Ekleta Necklace', 1),
          _ingredient('Cup of Destined Dawn', 1),
        ],
      ),
      'Legacy Manual Record': _recipe(
        'Legacy Manual Record',
        CraftMode.processing,
        group: 'Reference',
        method: 'Manual Conversion',
        role: RecipeRole.manualConversion,
      ),
      'Polished Marble': _recipe(
        'Polished Marble',
        CraftMode.processing,
        group: 'Processing - Grinding',
        method: 'Grinding',
        outputMinimum: 1,
        outputMaximum: 4,
        ingredients: <Ingredient>[_ingredient('Rough Marble', 5)],
      ),
    });
  }

  ModeCatalog modeCatalog(
    CraftMode mode,
    Map<String, Recipe> items, {
    Map<String, String> aliases = const <String, String>{},
  }) => ModeCatalog(
    mode: mode,
    items: items,
    iconDataUris: <String, String>{
      for (final name in items.keys)
        if (mode != CraftMode.alchemy || !omittedAlchemyIcons.contains(name))
          name: testIconDataUri,
    },
    defaults: const <String, Object?>{},
    metadata: const <String, Object?>{},
    searchAliases: aliases,
  );

  return CatalogSnapshot(
    sourceSha256: 'recipe-book-fixture',
    sourceByteCount: 1,
    alchemy: modeCatalog(CraftMode.alchemy, alchemy),
    cooking: modeCatalog(CraftMode.cooking, cooking),
    processing: modeCatalog(
      CraftMode.processing,
      processing,
      aliases: const <String, String>{
        'Black Stone Batch 01': 'sovereign weapon enhancement',
      },
    ),
    supportingData: <String, Object?>{
      'marketIds': <String, String>{'Clear Liquid Reagent': '5301'},
      'qualityIngredients': <String>['Sunflower'],
      'qualityConversions': <String, Object?>{
        'Sunflower': <String, Object?>{
          'high': <String, Object?>{
            'name': 'High-Quality Sunflower',
            'ratio': 3,
          },
          'special': <String, Object?>{'name': 'Special Sunflower', 'ratio': 5},
        },
      },
      if (includeNpcPurchaseFixture)
        'acquisitionInfo': <String, Object?>{
          'Mystical Parchment': <String, Object?>{
            'canonicalName': 'Mystical Parchment',
            'itemId': 820901,
            'status': 'reviewed',
            'reviewedAt': '2026-07-24',
            'routes': <Object?>[
              <String, Object?>{
                'kind': 'npc_purchase',
                'summary':
                    'Purchase from:\nSealus\nLebyos\nLylina\nVerosi\n'
                    'Vatputa\nTalishia\nSiemo\nKesharu\nVatu',
                'availability': 'permanent',
                'confidence': 'high',
              },
            ],
          },
        },
      if (includeEdaniaReferenceFixture)
        'edaniaPartIiReview': <String, Object?>{
          'inferredProcessingOutputs': <Object?>[
            <String, Object?>{
              'name': 'Polished Marble',
              'outputMin': 1,
              'outputMax': 4,
            },
          ],
        },
    },
    collisions: const <CaseCollision>[],
  );
}

ModeState _modeState(
  CraftMode mode, {
  required String target,
  required String bonusTarget,
}) => ModeState(
  target: target,
  bonusTarget: bonusTarget,
  market: MarketState(),
  appearance: AppearanceSettings.defaultsFor(mode),
);

Recipe _recipe(
  String name,
  CraftMode mode, {
  String? group,
  String? method,
  List<Ingredient>? ingredients,
  List<RecipeVariant> variants = const <RecipeVariant>[],
  String? defaultVariantId,
  RecipeRole role = RecipeRole.production,
  double outputMinimum = 1,
  double outputMaximum = 1,
}) => Recipe(
  name: name,
  type: mode.key,
  baseOutput: 1,
  group: group,
  method: method,
  ingredients: ingredients ?? <Ingredient>[_ingredient('Trace of Earth', 1)],
  marketId: null,
  sourceNote: null,
  vendor: null,
  location: null,
  npcPrice: 0,
  qualityBase: null,
  qualityGrade: null,
  outputMinimum: outputMinimum,
  outputMaximum: outputMaximum,
  role: role,
  variants: variants,
  defaultVariantId: defaultVariantId,
);

Ingredient _ingredient(String name, double quantity) => Ingredient(
  name: name,
  quantity: quantity,
  options: const <String>[],
  substituteGroup: null,
  substituteRatios: const <String, double>{},
);

RecipeVariant _variant({
  required String id,
  required String label,
  required String routeId,
  required CraftMode mode,
  required List<Ingredient> ingredients,
  int batchMultiplier = 1,
  double output = 1,
}) => RecipeVariant(
  id: id,
  label: label,
  routeId: routeId,
  batchMultiplier: batchMultiplier,
  type: mode.key,
  baseOutput: output,
  method: mode == CraftMode.processing ? 'Heating' : mode.label,
  ingredients: ingredients,
  outputMinimum: output,
  outputMaximum: output,
);

Recipe _leaf(String name) => Recipe(
  name: name,
  type: 'gathered',
  baseOutput: 1,
  group: 'Materials',
  method: null,
  ingredients: const <Ingredient>[],
  marketId: null,
  sourceNote: null,
  vendor: null,
  location: null,
  npcPrice: 0,
  qualityBase: null,
  qualityGrade: null,
  outputMinimum: null,
  outputMaximum: null,
);
