import 'dart:convert';
import 'dart:io';

import 'package:bdo_craft_planner_flutter/domain/migration/avalonia_v1_migration.dart';
import 'package:bdo_craft_planner_flutter/domain/migration/migration_report.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  AvaloniaV1Migration migration() => AvaloniaV1Migration(
    defaults: AvaloniaMigrationDefaults.schemaFallback(
      applicationVersion: 'test-version',
    ),
    utcNow: () => DateTime.utc(2026, 7, 20, 10),
  );

  test('normalizes Avalonia v1 while preserving compatibility evidence', () {
    final source = <String, Object?>{
      'VeRsIoN': 1,
      'ACTIVEmode': 'COOKING',
      'ALCHEMY': {
        'VERSION': 1,
        'TARGET': 42,
        'want': 0,
        'bonusTarget': null,
        'inv': {'Kept': 2, 'Zero': 0, 'Bad': '4'},
        'view': 'market',
        'recipeEdits': {
          'User Recipe': {
            'type': 'alchemy',
            'baseOutput': 0,
            'group': true,
            'marketId': 9007199254740991,
            'ingredients': [
              {
                'name': 'Leaf',
                'qty': 2,
                'options': ['Leaf', 'Leaf', ''],
                'substituteGroup': false,
                'substituteRatios': {'Leaf': 1},
              },
            ],
          },
        },
        'customIcons': {'User Recipe': 'data:image/png;base64,AA=='},
        'favoriteRecipes': [' beta ', 'Alpha', 'ALPHA', ''],
        'ingredientGrades': {
          'good': '  HiGh ',
          'blue': '\tBLUE\n',
          'bad': 'rainbow',
        },
        'recipeVariantChoices': {'User Recipe': 'preferred-low-cost'},
        'market': {
          'prices': {'Kept': 0, 'Bad': -1},
          'stock': {'Kept': 4},
        },
        'appearance': {
          'background': 'abyssal-tideglass',
          'tabTransitionSpeed': ' SLOW ',
          'particleHue': 0,
          'buttonEffectHue': 0,
          'accentHue': 0,
          'presets': [
            {
              'name': 'Nested',
              'settings': {'background': 'moonstone-astrarium'},
            },
          ],
        },
        'futureModeField': {'kept': true},
      },
      'cooking': null,
      'processing': {'processingMastery': 0},
      'processingYields': {'DEFAULTYIELD': -2, 'Grinding': 3.5},
      'marketTax': {'familyFameBonus': 0.01},
      'futureRootField': [1, 2, 3],
    };

    final result = migration().decodeUtf8(utf8.encode(jsonEncode(source)));

    expect(result.succeeded, isTrue);
    final state = result.state!;
    expect(state.activeMode.key, 'cooking');
    expect(state.alchemy.target, '42');
    expect(state.alchemy.want, 1);
    expect(state.alchemy.bonusTarget, '42');
    expect(state.alchemy.inventory, {'Kept': 2});
    expect(state.alchemy.view, 'plan');
    expect(state.alchemy.favoriteRecipes, ['Alpha', 'beta']);
    expect(state.alchemy.ingredientGrades, {'good': 'high', 'blue': 'blue'});
    expect(state.alchemy.recipeVariantChoices, {
      'User Recipe': 'preferred-low-cost',
    });
    expect(state.alchemy.market.prices, {'Kept': 0});
    expect(state.alchemy.appearance.background, 'tide');
    expect(state.alchemy.appearance.particleHue, 0);
    expect(state.alchemy.appearance.buttonEffectHue, 0);
    expect(state.alchemy.appearance.accentHue, 0);
    expect(state.alchemy.appearance.tabTransitionSpeed, 'slow');
    expect(state.cooking.appearance.tabTransitionSpeed, 'normal');
    expect(
      state.alchemy.appearance.presets.first!.settings.background,
      'orrery',
    );
    expect(state.alchemy.extensions, contains('futureModeField'));
    expect(state.extensions, contains('futureRootField'));
    expect(state.processing.processingMastery, 2);
    expect(state.processingYields['defaultYield'], 2.5);
    expect(state.processingYields['Grinding'], 3.5);
    expect(result.pendingCustomIcons, hasLength(1));

    final recipe = state.alchemy.recipeEdits['User Recipe']!;
    expect(recipe.baseOutput, .0001);
    expect(recipe.group, 'true');
    expect(recipe.marketId, '9007199254740991');
    expect(recipe.ingredients.single.options, ['Leaf', 'Leaf', '']);
    expect(recipe.ingredients.single.substituteGroup, 'false');

    expect(
      result.report.diagnostics,
      contains(
        isA<MigrationDiagnostic>().having(
          (value) => value.path,
          'path',
          r'$.alchemy.inv.Bad',
        ),
      ),
    );
    expect(result.report.counts['unknownFields'], 2);
  });

  test('rejects a source schema newer than the isolated v1 adapter', () {
    final result = migration().decodeUtf8(
      utf8.encode(jsonEncode({'version': 2})),
    );

    expect(result.state, isNull);
    expect(result.report.hasErrors, isTrue);
    expect(
      result.report.diagnostics
          .singleWhere((value) => value.code == 'unsupported-source-version')
          .severity,
      MigrationDiagnosticSeverity.error,
    );
  });

  test('canonicalizes Sakura IDs in modes and nested presets', () {
    final source = <String, Object?>{
      'version': 1,
      'alchemy': {
        'appearance': {
          'background': '  SAKURA  ',
          'presets': [
            {
              'name': 'Night',
              'settings': {'background': 'sakura-night'},
            },
          ],
        },
      },
      'cooking': {
        'appearance': {'background': 'sakura-night'},
      },
      'processing': {
        'appearance': {'background': 'SAKURA-NIGHT-GARDEN'},
      },
    };

    final result = migration().decodeUtf8(utf8.encode(jsonEncode(source)));

    expect(result.succeeded, isTrue);
    final state = result.state!;
    expect([
      state.alchemy.appearance.background,
      state.cooking.appearance.background,
      state.processing.appearance.background,
    ], everyElement('sakura-night-garden'));
    expect(
      state.alchemy.appearance.presets.first!.settings.background,
      'sakura-night-garden',
    );
    expect(
      result.report.diagnostics.where(
        (diagnostic) => diagnostic.code == 'unknown-background',
      ),
      isEmpty,
    );
  });

  test('migrates the synthetic checkpoint fixture exactly', () async {
    final sourceBytes = await File(
      'test/fixtures/migration/avalonia-planner-state-synthetic.json',
    ).readAsBytes();

    final result = migration().decodeUtf8(sourceBytes);

    expect(result.succeeded, isTrue);
    expect(result.report.sourceByteCount, 5214);
    expect(
      result.report.sourceSha256,
      '25A90E6F494187435DBF58E3F7D52658DD2DF4805378DFB37CC1D3091DD532B7',
    );
    expect(result.pendingCustomIcons, isEmpty);
    final state = result.state!;
    expect(state.activeMode.key, 'cooking');
    expect(state.alchemy.target, 'Clear Liquid Reagent');
    expect(state.alchemy.inventory, hasLength(2));
    expect(state.alchemy.favoriteRecipes, hasLength(2));
    expect(state.alchemy.ingredientGrades, hasLength(1));
    expect(state.alchemy.recipeVariantChoices, isEmpty);
    expect(state.alchemy.market.prices, hasLength(2));
    expect(state.alchemy.market.stock, hasLength(2));
    expect(state.cooking.target, 'Beer');
    expect(state.cooking.favoriteRecipes, hasLength(1));
    expect(state.cooking.substituteChoices, hasLength(1));
    expect(state.processing.target, 'Wheat Flour');
    expect(state.processing.view, 'appearance');
    expect(state.processing.processingMastery, 2);
    expect(state.processingYields, hasLength(11));
    expect([
      state.alchemy.appearance.background,
      state.cooking.appearance.background,
      state.processing.appearance.background,
    ], everyElement('illuminated-ledger'));
    expect([
      state.alchemy.appearance.tabTransitionSpeed,
      state.cooking.appearance.tabTransitionSpeed,
      state.processing.appearance.tabTransitionSpeed,
    ], everyElement('normal'));
  });
}
