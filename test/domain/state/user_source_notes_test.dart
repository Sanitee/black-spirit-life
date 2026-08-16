import 'package:bdo_craft_planner_flutter/domain/models/craft_mode.dart';
import 'package:bdo_craft_planner_flutter/domain/state/planner_state.dart';
import 'package:bdo_craft_planner_flutter/domain/state/user_source_notes.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('custom IngredientMeta note is trimmed and preferred', () {
    final state = _mode(
      ingredientMeta: <String, IngredientMetadata>{
        'Sunrise Herb': IngredientMetadata(
          sourceNote: '  Gathered beside the northern road.  ',
        ),
      },
      recipeEdits: <String, RecipeState?>{
        'sunrise herb': RecipeState(
          type: 'gathered',
          baseOutput: 1,
          sourceNote: 'Older recipe note',
        ),
      },
    );

    expect(
      displayableUserSourceNote(state, 'SUNRISE HERB'),
      'Gathered beside the northern road.',
    );
  });

  test('persisted RecipeEdit note is used when metadata has no note', () {
    final state = _mode(
      recipeEdits: <String, RecipeState?>{
        'Sunrise Herb': RecipeState(
          type: 'gathered',
          baseOutput: 1,
          sourceNote: 'My saved gathering route',
        ),
      },
    );

    expect(
      displayableUserSourceNote(state, 'sunrise herb'),
      'My saved gathering route',
    );
  });

  test('known BDO import provenance is not a displayable user note', () {
    for (final note in <String>[
      'Imported from BDOLytics recipe 9077; icons and item IDs checked through BDO Codex.',
      'Imported from BDO Codex mrecipe 981. 2 of 2 variants fit this planner recipe; remaining variants stay in import metadata.',
      'Icons and item IDs checked through BDO Codex.',
    ]) {
      expect(sanitizeDisplayableSourceNote(note), isNull, reason: note);
    }
  });

  test('provenance metadata falls through to a real RecipeEdit note', () {
    final state = _mode(
      ingredientMeta: <String, IngredientMetadata>{
        'Sunrise Herb': IngredientMetadata(
          sourceNote:
              'Imported from BDOLytics recipe 575; icons and item IDs checked through BDO Codex.',
        ),
      },
      recipeEdits: <String, RecipeState?>{
        'Sunrise Herb': RecipeState(
          type: 'gathered',
          baseOutput: 1,
          sourceNote: 'Use the node west of Heidel.',
        ),
      },
    );

    expect(
      displayableUserSourceNote(state, 'Sunrise Herb'),
      'Use the node west of Heidel.',
    );
  });
}

ModeState _mode({
  Map<String, IngredientMetadata> ingredientMeta =
      const <String, IngredientMetadata>{},
  Map<String, RecipeState?> recipeEdits = const <String, RecipeState?>{},
}) => ModeState(
  target: 'Target',
  bonusTarget: 'Target',
  recipeEdits: recipeEdits,
  ingredientMeta: ingredientMeta,
  market: MarketState(),
  appearance: AppearanceSettings.defaultsFor(CraftMode.alchemy),
);
