import 'package:bdo_craft_planner_flutter/domain/models/catalog_models.dart';
import 'package:bdo_craft_planner_flutter/features/recipe_book/recipe_book_item_info.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Dawn box guidance stays factual, concise, and idempotent', () {
    const original =
        'Open Essence of Dawn Boxes from eligible Black Shrine rewards for a '
        'chance at this specialized essence, or buy it through the Central Market.';
    const concise =
        'Chance from Essence of Dawn Boxes (Black Shrine rewards), or buy it on '
        'the Central Market.';
    const separateCondition = 'Available only after the quest.';
    const info = RecipeBookItemInfo(
      title: 'Essence of Dawn - Accuracy',
      kind: 'Recipe material',
      summary: '',
    );

    final result = withResearchedAcquisition(info, const [
      original,
      concise,
      separateCondition,
    ]);
    expect(result.acquisitionNotes, [concise, separateCondition]);
    expect(withResearchedAcquisition(result, const [original]), same(result));
  });

  test('researched acquisition keeps exchanged item and quantity roles', () {
    const info = RecipeBookItemInfo(
      title: 'Wild Grass',
      kind: 'Material',
      summary: '',
      notes: ["Exchange 10 Wild Grass for 30 Fairy's Breath."],
    );

    final result = withResearchedAcquisition(info, const [
      "Exchange 10 Fairy's Breath for 30 Wild Grass.",
    ]);

    expect(result.acquisitionNotes, [
      "Exchange 10 Fairy's Breath for 30 Wild Grass.",
    ]);
  });

  test('researched acquisition keeps each seller attached to its location', () {
    const info = RecipeBookItemInfo(
      title: 'Purified Water',
      kind: 'Material',
      summary: '',
      notes: ['Buy from Waida in Valencia or Yasum in Sand Grain Bazaar.'],
    );

    final result = withResearchedAcquisition(info, const [
      'Buy from Waida in Sand Grain Bazaar or Yasum in Valencia.',
    ]);

    expect(result.acquisitionNotes, [
      'Buy from Waida in Sand Grain Bazaar or Yasum in Valencia.',
    ]);
  });

  test('separate references cannot absorb a unique acquisition condition', () {
    const info = RecipeBookItemInfo(
      title: 'Material',
      kind: 'Material',
      summary: 'Buy from Waida in Sand Grain Bazaar.',
      notes: ['Buy from Yasum only after the quest.'],
    );
    final result = withResearchedAcquisition(info, const [
      'Buy from Waida in Sand Grain Bazaar only after the quest.',
    ]);
    expect(result.acquisitionNotes, [
      'Buy from Waida in Sand Grain Bazaar only after the quest.',
    ]);
  });

  test('numeric prices and their signs stay exact', () {
    const info = RecipeBookItemInfo(
      title: 'Material',
      kind: 'Material',
      summary: '',
      notes: ['Price: 1.5 silver.', 'Max HP +300.'],
    );
    final result = withResearchedAcquisition(info, const [
      'Price: 15 silver.',
      'Max HP -300.',
    ]);
    expect(result.acquisitionNotes, ['Price: 15 silver.', 'Max HP -300.']);
  });

  test('exact sentence references deduplicate without losing a new fact', () {
    const info = RecipeBookItemInfo(
      title: 'Material',
      kind: 'Material',
      summary: '',
      notes: ['Buy from Waida in Sand Grain Bazaar. Price: 5,000 Silver each.'],
    );
    final result = withResearchedAcquisition(info, const [
      ' BUY FROM Waida in Sand Grain Bazaar.\n'
          'Price: 5,000 Silver each.\n'
          'Available only after the quest.',
    ]);
    expect(result.acquisitionNotes, ['Available only after the quest.']);
  });

  test('structured reform removes only the matching inputs and exact effect', () {
    final info = _reformInfo();
    final result = withResearchedAcquisition(info, const [
      'Reform Ekleta Necklace with Cup of Destined Dawn to gain Max HP +300.',
      'Reform Cup of Destined Dawn with Ekleta Necklace to gain Max HP +300.',
      'Reform Ekleta Necklace with Cup of Destined Dawn to gain Max HP -300.',
      'Reform 2 Ekleta Necklace with Cup of Destined Dawn to gain Max HP +300.',
      'Reform Ekleta Necklace with Cup of Destined Dawn to gain Max HP +300 '
          'after completing the quest.',
    ]);
    expect(result.acquisitionNotes, [
      'Reform Cup of Destined Dawn with Ekleta Necklace to gain Max HP +300.',
      'Reform Ekleta Necklace with Cup of Destined Dawn to gain Max HP -300.',
      'Reform 2 Ekleta Necklace with Cup of Destined Dawn to gain Max HP +300.',
      'Reform Ekleta Necklace with Cup of Destined Dawn to gain Max HP +300 '
          'after completing the quest.',
    ]);
  });

  test('different recorded reform quantities cannot absorb one-item prose', () {
    final result = withResearchedAcquisition(
      _reformInfo(cupQuantity: 2),
      const [
        'Reform Ekleta Necklace with Cup of Destined Dawn to gain Max HP +300.',
      ],
    );
    expect(result.acquisitionNotes, [
      'Reform Ekleta Necklace with Cup of Destined Dawn to gain Max HP +300.',
    ]);
  });
}

RecipeBookItemInfo _reformInfo({double cupQuantity = 1}) => RecipeBookItemInfo(
  title: 'Dawnbound Ekleta Necklace',
  kind: 'Reformed accessory',
  summary: '',
  effects: const ['Max HP +300'],
  acquisitionFormulas: [
    RecipeBookFormula(
      outputName: 'Dawnbound Ekleta Necklace',
      type: 'processing',
      method: 'Item Reform',
      baseOutput: 1,
      ingredients: [
        Ingredient(
          name: 'Ekleta Necklace',
          quantity: 1,
          options: const [],
          substituteGroup: null,
          substituteRatios: const {},
        ),
        Ingredient(
          name: 'Cup of Destined Dawn',
          quantity: cupQuantity,
          options: const [],
          substituteGroup: null,
          substituteRatios: const {},
        ),
      ],
    ),
  ],
);
