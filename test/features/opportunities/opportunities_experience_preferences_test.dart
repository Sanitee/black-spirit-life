import 'dart:convert';

import 'package:bdo_craft_planner_flutter/features/opportunities/opportunities_preferences.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'older preferences keep their sort and default to including unknown EXP',
    () {
      final result = OpportunitiesPreferences.fromJson({
        'version': 1,
        'craftSort': 'preorders',
        'readyOnly': true,
      });
      expect(result.craftSort, 'preorders');
      expect(result.craftAscending, isFalse);
      expect(result.unknownExpFilter, 'include');
      expect(result.readyOnly, isTrue);
    },
  );

  test('EXP filter and each independent direction survive a save', () {
    for (final filter in ['include', 'hide', 'only']) {
      final original = OpportunitiesPreferences()
        ..craftSort = 'exp'
        ..unknownExpFilter = filter
        ..craftSortAscending['exp'] = true
        ..craftSortAscending['profit'] = true;
      final result = OpportunitiesPreferences.fromJson(
        jsonDecode(jsonEncode(original.toJson())),
      );
      expect(result.craftSort, 'exp');
      expect(result.unknownExpFilter, filter);
      expect(result.craftAscending, isTrue);
      result.craftSort = 'preorders';
      expect(result.craftAscending, isFalse);
      result.craftSort = 'profit';
      expect(result.craftAscending, isTrue);
    }
  });

  test(
    'invalid filter or direction values cannot reset other valid settings',
    () {
      final result = OpportunitiesPreferences.fromJson({
        'version': 1,
        'craftSort': 'exp',
        'unknownExpFilter': 'not a filter',
        'craftSortAscending': {
          'exp': 'true',
          'profit': true,
          'preorders': 1,
          'unexpected': true,
        },
      });
      expect(result.unknownExpFilter, 'include');
      expect(result.craftSortAscending, {
        'profit': true,
        'preorders': false,
        'exp': false,
      });
      for (final invalid in [null, [], 9, 'ascending']) {
        final restored = OpportunitiesPreferences.fromJson({
          'version': 1,
          'craftSortAscending': invalid,
        });
        expect(restored.craftSortAscending.values, everyElement(isFalse));
      }
    },
  );

  test(
    'serialized direction map is a snapshot, not a live mutable setting',
    () {
      final preferences = OpportunitiesPreferences();
      final saved = preferences.toJson();
      preferences.craftSortAscending['exp'] = true;
      expect((saved['craftSortAscending']! as Map)['exp'], isFalse);
    },
  );
}
