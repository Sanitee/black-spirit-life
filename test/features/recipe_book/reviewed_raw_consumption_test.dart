import 'package:bdo_craft_planner_flutter/features/recipe_book/recipe_book_item_info.dart';
import 'package:bdo_craft_planner_flutter/features/recipe_book/reviewed_raw_consumption.dart';
import 'package:bdo_craft_planner_flutter/features/recipe_book/reviewed_reference_facts.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'client-only raw chains never add usability claims or timers to any identity',
    () {
      expect(reviewedRawConsumption, hasLength(100));
      for (final entry in reviewedRawConsumption.entries) {
        final before = RecipeBookItemInfo(
          title: entry.value.name,
          kind: 'Material',
          summary: 'Keep summary',
          acquisitionNotes: const ['Keep source'],
          uses: const ['Keep use'],
        );
        final after = withReviewedReferenceFacts(
          before,
          itemId: '${entry.key}',
        );
        expect(after.effectsTitle, 'Effects', reason: entry.value.name);
        expect(after.effects, isEmpty, reason: entry.value.name);
        expect(after.notes, isNot(contains('Duration: 30 sec.')));
        expect(after.notes, isNot(contains('Cooldown: 10 min.')));
        expect(after.summary, before.summary);
        expect(after.acquisitionNotes, contains('Keep source'));
        expect(after.uses, before.uses);
        expect(after.acquisitionFormulas, isEmpty);
        expect(
          withReviewedRawConsumption(after, itemId: '${entry.key}').effects,
          after.effects,
        );
        expect(withReviewedRawConsumption(before, itemId: null), same(before));
        final wrongName = before.copyWith(title: 'Unrelated item');
        expect(
          withReviewedRawConsumption(wrongName, itemId: '${entry.key}'),
          same(wrongName),
        );
        final archived = before.copyWith(isTemporarilyArchived: true);
        expect(
          withReviewedRawConsumption(archived, itemId: '${entry.key}'),
          same(archived),
        );
      }
    },
  );
  test(
    'negative effects remain negative; warnings are next to raw effects',
    () {
      expect(
        reviewedRawConsumption[7304]!.effects,
        contains('Casting Speed -1'),
      );
      expect(
        reviewedRawConsumption[7304]!.effects.last,
        contains('causes pain'),
      );
      expect(
        reviewedRawConsumption[5419]!.effects.last,
        contains('May poison'),
      );
      expect(reviewedRawConsumption[5406]!.effects.last, 'May poison you.');
      expect(reviewedRawConsumption[5462], isNull);
      expect(reviewedRawConsumption[5482], isNull);
      expect(reviewedRawConsumption[15117], isNull);
      expect(reviewedRawConsumption[757032], isNull);
    },
  );
  test(
    'Stonetail food cannot masquerade as raw food or unconditional Health EXP',
    () {
      const input = RecipeBookItemInfo(
        title: "Stonetail Wind's Meal",
        kind: 'Food',
        summary: '',
      );
      final result = withReviewedReferenceFacts(input, itemId: '757032');
      expect(result.effectsTitle, 'Effects');
      expect(result.kind, 'Food');
      expect(
        result.effects,
        containsAll([
          'Mount EXP +10%',
          'Training EXP +20%',
          'All Life Skill Mastery +25',
          'Health EXP +150 (instant; not while Satiated)',
        ]),
      );
      expect(
        result.notes,
        containsAll([
          'Duration: 600 min.',
          'Cooldown: 30 min.',
          'Replaces other food effects, except Health EXP.',
          'Only the last high-quality food applies; effects do not stack.',
        ]),
      );
      expect(result.acquisitionFormulas, isEmpty);
      expect(withReviewedReferenceFacts(input, itemId: '757099'), same(input));
    },
  );
}
