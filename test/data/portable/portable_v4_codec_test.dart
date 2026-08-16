import 'dart:convert';

import 'package:bdo_craft_planner_flutter/data/portable/portable_v4_codec.dart';
import 'package:bdo_craft_planner_flutter/domain/models/craft_mode.dart';
import 'package:bdo_craft_planner_flutter/domain/state/inventory_storage.dart';
import 'package:bdo_craft_planner_flutter/domain/state/planner_state.dart';
import 'package:bdo_craft_planner_flutter/domain/state/state_copy.dart';
import 'package:bdo_craft_planner_flutter/visual/sakura_night_garden/sakura_spec.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../domain/state/state_test_fixture.dart';

const _iconDataUri = 'data:image/png;base64,AA==';

void main() {
  const codec = PortableV4Codec();

  group('portable v4 export contract', () {
    const cases =
        <
          ({
            String name,
            PortableScopes scopes,
            Set<String> modeKeys,
            Set<String> extraDataKeys,
            bool includeMarketTax,
          })
        >[
          (
            name: 'recipes',
            scopes: PortableScopes(recipes: true),
            modeKeys: {
              'recipeEdits',
              'customIcons',
              'iconAliases',
              'ingredientMeta',
              'customCategories',
              'hiddenItems',
            },
            extraDataKeys: {},
            includeMarketTax: false,
          ),
          (
            name: 'inventory',
            scopes: PortableScopes(inventory: true),
            modeKeys: {'inv'},
            extraDataKeys: {},
            includeMarketTax: false,
          ),
          (
            name: 'plans',
            scopes: PortableScopes(plans: true),
            modeKeys: {'target', 'want', 'bonusTarget', 'bonusWant'},
            extraDataKeys: {},
            includeMarketTax: false,
          ),
          (
            name: 'choices',
            scopes: PortableScopes(choices: true),
            modeKeys: {
              'substituteChoices',
              'ingredientGrades',
              'recipeVariantChoices',
            },
            extraDataKeys: {},
            includeMarketTax: false,
          ),
          (
            name: 'market',
            scopes: PortableScopes(market: true),
            modeKeys: {'market'},
            extraDataKeys: {'marketTax'},
            includeMarketTax: true,
          ),
          (
            name: 'settings',
            scopes: PortableScopes(settings: true),
            modeKeys: {
              'alchemyMastery',
              'alchemyYield',
              'cookingMastery',
              'processingMastery',
              'useMassProcessing',
              'ignoreTargetInventory',
              'ignoreIngredientInventory',
              'appearance',
            },
            extraDataKeys: {
              'processingYields',
              'marketTax',
              'afkWeightProfile',
            },
            includeMarketTax: false,
          ),
          (
            name: 'completed',
            scopes: PortableScopes(completed: true),
            modeKeys: {'completedSteps', 'afkCraftProgress', 'done'},
            extraDataKeys: {},
            includeMarketTax: false,
          ),
          (
            name: 'layout',
            scopes: PortableScopes(layout: true),
            modeKeys: {
              'view',
              'bookFavoritesOnly',
              'bookSearchIngredients',
              'bookSearchRelatedItems',
            },
            extraDataKeys: {},
            includeMarketTax: false,
          ),
        ];

    for (final entry in cases) {
      test('${entry.name} emits only its exact fields', () {
        final document =
            jsonDecode(
                  codec.export(
                    buildStateFixture(),
                    scopes: entry.scopes,
                    includeMarketTax: entry.includeMarketTax,
                    iconExporter: (_) => _iconDataUri,
                  ),
                )
                as Map<String, Object?>;

        expect(
          document.keys,
          unorderedEquals({'type', 'version', 'app', 'included', 'data'}),
        );
        expect(document['type'], 'bdo-tool-portable');
        expect(document['version'], 4);
        expect(document['app'], 'BDO Craft Planner');
        expect(document['included'], entry.scopes.toJson());
        final data = document['data']! as Map<String, Object?>;
        expect(
          data.keys,
          unorderedEquals({
            'alchemy',
            'cooking',
            'processing',
            ...entry.extraDataKeys,
          }),
        );
        for (final mode in CraftMode.values) {
          final modeData = data[mode.key]! as Map<String, Object?>;
          expect(modeData.keys, unorderedEquals(entry.modeKeys));
        }
      });
    }

    test(
      'market tax is absent unless the market preview explicitly includes it',
      () {
        final document =
            jsonDecode(
                  codec.export(
                    buildStateFixture(),
                    scopes: const PortableScopes(market: true),
                  ),
                )
                as Map<String, Object?>;
        final data = document['data']! as Map<String, Object?>;
        expect(data, isNot(contains('marketTax')));
      },
    );
  });

  group('portable v4 import', () {
    test('market scope round-trips cumulative and measured trade data', () {
      final source = buildStateFixture();
      final current = _baselineFrom(source);

      final exported = codec.export(
        source,
        scopes: const PortableScopes(market: true),
        includeMarketTax: true,
      );
      final result = codec.import(current, exported);

      for (final mode in CraftMode.values) {
        expect(
          result.state.forMode(mode).market.toJson(),
          source.forMode(mode).market.toJson(),
        );
      }
    });

    test('settings round-trip retains Sakura for every workstation', () {
      final original = buildStateFixture();
      AppearanceSettings sakura() => AppearanceSettings(
        background: SakuraNightGardenSpec.backgroundId,
        particleStyle: 'petals',
        particleMinSize: .68,
        particleMaxSize: 1.5,
        particleHue: 341,
        buttonEffect: 'glow',
        buttonEffectHue: 341,
        accentHue: 341,
        tabTransitionSpeed: 'slow',
      );
      final source = original.copyWith(
        alchemy: original.alchemy.copyWith(appearance: sakura()),
        cooking: original.cooking.copyWith(appearance: sakura()),
        processing: original.processing.copyWith(appearance: sakura()),
      );
      final current = _baselineFrom(original);

      final exported = codec.export(
        source,
        scopes: const PortableScopes(settings: true),
      );
      final result = codec.import(current, exported);

      for (final mode in CraftMode.values) {
        expect(
          result.state.forMode(mode).appearance.background,
          SakuraNightGardenSpec.backgroundId,
        );
        expect(
          result.state.forMode(mode).appearance.tabTransitionSpeed,
          'slow',
        );
      }
      expect(result.state.marketTax.enabled, source.marketTax.enabled);
      expect(result.state.marketTax.valuePack, source.marketTax.valuePack);
      expect(
        result.state.marketTax.merchantRing,
        source.marketTax.merchantRing,
      );
      expect(
        result.state.marketTax.familyFameBonus,
        source.marketTax.familyFameBonus,
        reason: 'sale-tax modifiers are part of durable user settings',
      );
      expect(
        result.state.afkWeightProfile.maximumWeightLt,
        source.afkWeightProfile.maximumWeightLt,
      );
      expect(
        result.state.afkWeightProfile.currentCarriedWeightLt,
        source.afkWeightProfile.currentCarriedWeightLt,
      );
      expect(
        result.state.afkWeightProfile.safetyBufferLt,
        source.afkWeightProfile.safetyBufferLt,
      );
      expect(
        result.state.afkWeightProfile.featheryStepsLevel,
        source.afkWeightProfile.featheryStepsLevel,
      );
      expect(
        result.state.afkWeightProfile.extensions,
        isEmpty,
        reason: 'portable exports deliberately omit native extension buckets',
      );
    });

    test('round-trips all scoped fields after normalization', () {
      final source = buildStateFixture();
      final current = _baselineFrom(source);
      final exported = codec.export(
        source,
        scopes: const PortableScopes.all(),
        includeMarketTax: true,
        iconExporter: (_) => _iconDataUri,
      );

      final result = codec.import(
        current,
        exported,
        iconImporter: (icon) =>
            source.forMode(icon.mode).customIcons[icon.itemName]!,
      );
      final reexported = codec.export(
        result.state,
        scopes: const PortableScopes.all(),
        includeMarketTax: true,
        iconExporter: (_) => _iconDataUri,
      );

      expect(jsonDecode(reexported), jsonDecode(exported));
      expect(result.scopes.toJson(), const PortableScopes.all().toJson());
      expect(result.legacyFullReplacement, isFalse);
      expect(
        result.state.alchemy.favoriteRecipes,
        current.alchemy.favoriteRecipes,
        reason: 'favorites are not assigned to any dossier portable scope',
      );
      expect(
        result.state.alchemy.compatibility.planSearch,
        current.alchemy.compatibility.planSearch,
        reason: 'retired planSearch is not in a portable scope',
      );
    });

    test('completed scope carries explicit AFK round progress only', () {
      final source = buildStateFixture();
      final current = _baselineFrom(source);

      final result = codec.import(
        current,
        codec.export(source, scopes: const PortableScopes(completed: true)),
      );

      for (final mode in CraftMode.values) {
        expect(
          result.state
              .forMode(mode)
              .afkCraftProgress
              .map((key, value) => MapEntry(key, value.toJson())),
          source
              .forMode(mode)
              .afkCraftProgress
              .map(
                (key, value) => MapEntry(
                  key,
                  Map<String, Object?>.of(value.toJson())..remove('extensions'),
                ),
              ),
        );
      }
      expect(
        result.state.alchemy.afkCraftProgress['Old%20Item']?.completedAttempts,
        12,
      );
    });

    test('merges only the selected scope into supplied modes', () {
      final source = buildStateFixture();
      final current = _baselineFrom(source);
      final exported = codec.export(
        source,
        scopes: const PortableScopes(inventory: true),
      );

      final result = codec.import(current, exported);

      for (final mode in CraftMode.values) {
        expect(
          result.state.forMode(mode).inventory,
          source.forMode(mode).inventory,
        );
        expect(result.state.forMode(mode).target, current.forMode(mode).target);
        expect(
          result.state.forMode(mode).recipeEdits,
          current.forMode(mode).recipeEdits,
        );
      }
      expect(result.state.processingYields, current.processingYields);
      expect(result.state.marketTax.toJson(), current.marketTax.toJson());
      expect(
        result.state.afkWeightProfile.toJson(),
        current.afkWeightProfile.toJson(),
      );
    });

    test('inventory scope round-trips named storage locations', () {
      final original = buildStateFixture();
      final ensured = InventoryStorageState.fromModeState(
        original.alchemy,
      ).ensureLocation('Calpheon City Storage');
      final storage = ensured.state
          .setQuantity(
            locationId: ensured.location.id,
            itemName: 'Sunrise Herb',
            quantity: 139900,
          )
          .select(ensured.location.id);
      final source = original.copyWith(
        alchemy: storage.applyTo(original.alchemy),
      );
      final current = _baselineFrom(original);

      final exported = codec.export(
        source,
        scopes: const PortableScopes(inventory: true),
      );
      final document = jsonDecode(exported) as Map<String, Object?>;
      final data = document['data']! as Map<String, Object?>;
      final alchemy = data['alchemy']! as Map<String, Object?>;
      expect(alchemy, contains(inventoryStorageExtensionKey));

      final result = codec.import(current, exported);
      final restored = InventoryStorageState.fromModeState(
        result.state.alchemy,
      );
      expect(restored.selectedLocation.name, 'Calpheon City Storage');
      expect(
        restored.quantityAt('calpheon-city-storage', 'Sunrise Herb'),
        139900,
      );
      expect(restored.aggregate, source.alchemy.inventory);
    });

    test('older settings payload preserves the current AFK weight profile', () {
      final source = buildStateFixture();
      final current = _baselineFrom(source).copyWith(
        afkWeightProfile: AfkWeightProfile(
          maximumWeightLt: 1800,
          currentCarriedWeightLt: 90,
          safetyBufferLt: 30,
          featheryStepsLevel: 3,
        ),
      );
      final portable =
          jsonDecode(
                codec.export(
                  source,
                  scopes: const PortableScopes(settings: true),
                ),
              )
              as Map<String, Object?>;
      final data = portable['data']! as Map<String, Object?>;
      data.remove('afkWeightProfile');

      final result = codec.import(current, jsonEncode(portable));

      expect(
        result.state.afkWeightProfile.toJson(),
        current.afkWeightProfile.toJson(),
      );
    });

    test('rejects an invalid portable Feathery Steps rank', () {
      final current = buildStateFixture();
      final portable =
          jsonDecode(
                codec.export(
                  current,
                  scopes: const PortableScopes(settings: true),
                ),
              )
              as Map<String, Object?>;
      final data = portable['data']! as Map<String, Object?>;
      final profile = data['afkWeightProfile']! as Map<String, Object?>;
      profile['featheryStepsLevel'] = 6;

      expect(
        () => codec.import(current, jsonEncode(portable)),
        throwsA(
          isA<PortableFormatException>().having(
            (error) => error.path,
            'path',
            r'$.data.afkWeightProfile.featheryStepsLevel',
          ),
        ),
      );
    });

    test('choices scope round-trips saved recipe variant selections', () {
      final source = buildStateFixture();
      final current = _baselineFrom(source);
      final exported = codec.export(
        source,
        scopes: const PortableScopes(choices: true),
      );

      final result = codec.import(current, exported);

      for (final mode in CraftMode.values) {
        expect(
          result.state.forMode(mode).recipeVariantChoices,
          source.forMode(mode).recipeVariantChoices,
        );
        expect(
          result.state.forMode(mode).recipeEdits,
          current.forMode(mode).recipeEdits,
          reason: 'choices import must not replace recipe definitions',
        );
      }
    });

    test('accepts case-insensitive scope and data keys', () {
      final current = _baselineFrom(buildStateFixture());
      final source = jsonEncode({
        'TYPE': 'bdo-tool-portable',
        'VERSION': 4,
        'APP': 'BDO Craft Planner',
        'INCLUDED': {'InVeNtOrY': true},
        'DATA': {
          'ALCHEMY': {
            'Inv': {'Imported Item': 4},
          },
        },
      });

      final result = codec.import(current, source);

      expect(result.scopes.inventory, isTrue);
      expect(result.state.alchemy.inventory, {'Imported Item': 4});
      expect(result.state.cooking.toJson(), current.cooking.toJson());
    });

    test('rejects ambiguous case-insensitive scope duplicates', () {
      final current = _baselineFrom(buildStateFixture());
      final source = jsonEncode({
        'type': 'bdo-tool-portable',
        'version': 4,
        'app': 'BDO Craft Planner',
        'included': {'recipes': true, 'RECIPES': false},
        'data': <String, Object?>{},
      });

      expect(
        () => codec.import(current, source),
        throwsA(
          isA<PortableFormatException>().having(
            (error) => error.path,
            'path',
            r'$.included',
          ),
        ),
      );
    });

    test('validates fully before returning a replacement state', () {
      final current = _baselineFrom(buildStateFixture());
      final before = current.toJson();
      final invalid = jsonEncode({
        'type': 'bdo-tool-portable',
        'version': 4,
        'app': 'BDO Craft Planner',
        'included': {'inventory': true},
        'data': <String, Object?>{},
        'unexpected': true,
      });

      expect(
        () => codec.import(current, invalid),
        throwsA(isA<PortableFormatException>()),
      );
      expect(current.toJson(), before);
    });

    test('requires confirmation for legacy whole-mode replacement', () {
      final current = _baselineFrom(buildStateFixture());
      final legacy = jsonEncode({
        'type': 'bdo-tool-portable',
        'version': 4,
        'app': 'BDO Craft Planner',
        'included': <String, bool>{},
        'data': {
          'alchemy': {
            'target': 'Legacy Target',
            'want': 6,
            'inv': {'Legacy Material': 3},
          },
        },
      });

      expect(
        () => codec.import(current, legacy),
        throwsA(isA<PortableFormatException>()),
      );

      final result = codec.import(
        current,
        legacy,
        confirmLegacyFullReplacement: true,
      );
      expect(result.legacyFullReplacement, isTrue);
      expect(result.state.alchemy.target, 'Legacy Target');
      expect(result.state.alchemy.want, 6);
      expect(result.state.alchemy.inventory, {'Legacy Material': 3});
      expect(result.state.alchemy.favoriteRecipes, isEmpty);
      expect(result.state.cooking.toJson(), current.cooking.toJson());
    });
  });
}

PlannerState _baselineFrom(PlannerState source) {
  ModeState baseline(ModeState mode) => mode.copyWith(
    target: 'Baseline Target',
    want: 1,
    bonusTarget: 'Baseline Bonus',
    bonusWant: 2,
    inventory: const {'Baseline Material': 1},
    view: 'plan',
    recipeEdits: const {},
    iconAliases: const {},
    customIcons: const {},
    ingredientMeta: const {},
    customCategories: const [],
    substituteChoices: const {},
    ingredientGrades: const {},
    recipeVariantChoices: const {},
    favoriteRecipes: const ['Baseline Favorite'],
    hiddenItems: const ['Baseline Hidden'],
    bookFavoritesOnly: false,
    bookSearchIngredients: false,
    market: mode.market.copyWith(
      prices: const {'Baseline Material': 11},
      stock: const {'Baseline Material': 5},
      search: 'Baseline Search',
      selected: 'Baseline Material',
      fetchedAt: 7,
    ),
    ignoreTargetInventory: true,
    ignoreIngredientInventory: true,
    alchemyMastery: 1,
    cookingMastery: 2,
    processingMastery: 3,
    useMassProcessing: false,
    completedSteps: const [],
    afkCraftProgress: const {},
    compatibility: mode.compatibility.copyWith(
      done: const {},
      planSearch: 'Baseline Search',
      bookSearchRelatedItems: false,
      alchemyYield: 1.5,
    ),
  );

  return source.copyWith(
    alchemy: baseline(source.alchemy),
    cooking: baseline(source.cooking),
    processing: baseline(source.processing),
    processingYields: const {'baseline': 1},
    marketTax: MarketTax(),
  );
}
