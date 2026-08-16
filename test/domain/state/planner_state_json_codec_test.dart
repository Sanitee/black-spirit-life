import 'dart:convert';
import 'dart:typed_data';

import 'package:bdo_craft_planner_flutter/domain/models/catalog_models.dart';
import 'package:bdo_craft_planner_flutter/domain/state/planner_state_json_codec.dart';
import 'package:flutter_test/flutter_test.dart';

import 'state_test_fixture.dart';

void main() {
  const codec = PlannerStateJsonCodec();

  test('round-trips the complete native schema without losing extensions', () {
    final state = buildStateFixture();

    final decoded = codec.decode(codec.encode(state));

    expect(decoded.toJson(), state.toJson());
    expect(decoded.extensions['rootFuture'], [1, 2]);
    expect(decoded.afkWeightProfile.extensions['weightFuture'], isTrue);
    expect(decoded.alchemy.extensions['modeFuture'], {'enabled': true});
    expect(decoded.alchemy.market.unlistedItemNames, {
      'old item',
      'second item',
    });
    expect(decoded.alchemy.market.totalTrades['Old Item'], 1200);
    expect(decoded.alchemy.market.observedDailyTrades['Old Item'], 48);
    expect(decoded.alchemy.market.tradeObservationHours['Old Item'], 6);
    expect(decoded.alchemy.recipeVariantChoices, {
      'Old Item': 'preferred-low-cost',
    });
    expect(
      () => decoded.alchemy.recipeVariantChoices['Other Item'] = 'variant',
      throwsUnsupportedError,
    );
    expect(
      decoded
          .alchemy
          .recipeEdits['Old Item']!
          .ingredients
          .single
          .extensions['ingredientFuture'],
      isTrue,
    );
  });

  test('older native state defaults missing AFK weight profile safely', () {
    final document =
        jsonDecode(codec.encode(buildStateFixture())) as Map<String, Object?>;
    document.remove('afkWeightProfile');

    final decoded = codec.decode(jsonEncode(document));

    expect(decoded.afkWeightProfile.maximumWeightLt, 0);
    expect(decoded.afkWeightProfile.currentCarriedWeightLt, 0);
    expect(decoded.afkWeightProfile.safetyBufferLt, 20);
    expect(decoded.afkWeightProfile.featheryStepsLevel, 0);
    final reencoded = jsonDecode(codec.encode(decoded)) as Map<String, Object?>;
    expect(reencoded['afkWeightProfile'], {
      'maximumWeightLt': 0,
      'currentCarriedWeightLt': 0,
      'safetyBufferLt': 20,
      'featheryStepsLevel': 0,
    });
  });

  test('rejects invalid AFK weight values with precise paths', () {
    final document =
        jsonDecode(codec.encode(buildStateFixture())) as Map<String, Object?>;
    final profile = document['afkWeightProfile']! as Map<String, Object?>;

    profile['safetyBufferLt'] = -1;
    expect(
      () => codec.decode(jsonEncode(document)),
      throwsA(
        isA<PlannerStateFormatException>().having(
          (error) => error.path,
          'path',
          r'$.afkWeightProfile.safetyBufferLt',
        ),
      ),
    );

    profile['safetyBufferLt'] = 20;
    profile['featheryStepsLevel'] = 6;
    expect(
      () => codec.decode(jsonEncode(document)),
      throwsA(
        isA<PlannerStateFormatException>().having(
          (error) => error.path,
          'path',
          r'$.afkWeightProfile.featheryStepsLevel',
        ),
      ),
    );
  });

  test('older native market state defaults later market evidence safely', () {
    final document =
        jsonDecode(codec.encode(buildStateFixture())) as Map<String, Object?>;
    const laterFields = <String>[
      'unlistedItemNames',
      'tradeMarketIds',
      'totalTrades',
      'tradeObservedAt',
      'observedDailyTrades',
      'tradeObservationHours',
      'lastSoldAtEpochSeconds',
    ];
    for (final mode in const <String>['alchemy', 'cooking', 'processing']) {
      final modeState = document[mode]! as Map<String, Object?>;
      final market = modeState['market']! as Map<String, Object?>;
      for (final field in laterFields) {
        market.remove(field);
      }
    }

    final decoded = codec.decode(jsonEncode(document));

    expect(decoded.alchemy.market.unlistedItemNames, isEmpty);
    expect(decoded.cooking.market.unlistedItemNames, isEmpty);
    expect(decoded.processing.market.unlistedItemNames, isEmpty);
    expect(decoded.alchemy.market.tradeMarketIds, isEmpty);
    expect(decoded.alchemy.market.totalTrades, isEmpty);
    expect(decoded.alchemy.market.tradeObservedAt, isEmpty);
    expect(decoded.alchemy.market.observedDailyTrades, isEmpty);
    expect(decoded.alchemy.market.tradeObservationHours, isEmpty);
    expect(decoded.alchemy.market.lastSoldAtEpochSeconds, isEmpty);
    expect(
      codec.decode(codec.encode(decoded)).alchemy.market.unlistedItemNames,
      isEmpty,
    );
  });

  test('rejects negative persisted trade counters and rates', () {
    final document =
        jsonDecode(codec.encode(buildStateFixture())) as Map<String, Object?>;
    final alchemy = document['alchemy']! as Map<String, Object?>;
    final market = alchemy['market']! as Map<String, Object?>;

    market['totalTrades'] = <String, Object?>{'Old Item': -1};
    expect(
      () => codec.decode(jsonEncode(document)),
      throwsA(
        isA<PlannerStateFormatException>().having(
          (error) => error.path,
          'path',
          r'$.alchemy.market.totalTrades.Old Item',
        ),
      ),
    );

    market['totalTrades'] = <String, Object?>{'Old Item': 1};
    market['observedDailyTrades'] = <String, Object?>{'Old Item': -0.1};
    expect(
      () => codec.decode(jsonEncode(document)),
      throwsA(
        isA<PlannerStateFormatException>().having(
          (error) => error.path,
          'path',
          r'$.alchemy.market.observedDailyTrades.Old Item',
        ),
      ),
    );
  });

  test('older native state defaults missing recipe variant choices safely', () {
    final document =
        jsonDecode(codec.encode(buildStateFixture())) as Map<String, Object?>;
    for (final mode in const <String>['alchemy', 'cooking', 'processing']) {
      final modeState = document[mode]! as Map<String, Object?>;
      modeState.remove('recipeVariantChoices');
    }

    final decoded = codec.decode(jsonEncode(document));

    expect(decoded.alchemy.recipeVariantChoices, isEmpty);
    expect(decoded.cooking.recipeVariantChoices, isEmpty);
    expect(decoded.processing.recipeVariantChoices, isEmpty);
    final reencoded = jsonDecode(codec.encode(decoded)) as Map<String, Object?>;
    for (final mode in const <String>['alchemy', 'cooking', 'processing']) {
      final modeState = reencoded[mode]! as Map<String, Object?>;
      expect(modeState['recipeVariantChoices'], <String, String>{});
    }
  });

  test('older native state defaults missing AFK craft progress safely', () {
    final document =
        jsonDecode(codec.encode(buildStateFixture())) as Map<String, Object?>;
    for (final mode in const <String>['alchemy', 'cooking', 'processing']) {
      final modeState = document[mode]! as Map<String, Object?>;
      modeState.remove('afkCraftProgress');
    }

    final decoded = codec.decode(jsonEncode(document));

    expect(decoded.alchemy.afkCraftProgress, isEmpty);
    expect(decoded.cooking.afkCraftProgress, isEmpty);
    expect(decoded.processing.afkCraftProgress, isEmpty);
  });

  test('rejects AFK progress that can overclaim completed crafting', () {
    final document =
        jsonDecode(codec.encode(buildStateFixture())) as Map<String, Object?>;
    final alchemy = document['alchemy']! as Map<String, Object?>;
    final progress = alchemy['afkCraftProgress']! as Map<String, Object?>;
    final session = progress['Old%20Item']! as Map<String, Object?>;
    session['completedAttempts'] = 18;

    expect(
      () => codec.decode(jsonEncode(document)),
      throwsA(
        isA<PlannerStateFormatException>().having(
          (error) => error.path,
          'path',
          r'$.alchemy.afkCraftProgress.Old%20Item.completedAttempts',
        ),
      ),
    );
  });

  test('older native appearance defaults missing transition speed safely', () {
    final document =
        jsonDecode(codec.encode(buildStateFixture())) as Map<String, Object?>;
    for (final mode in const <String>['alchemy', 'cooking', 'processing']) {
      final modeState = document[mode]! as Map<String, Object?>;
      final appearance = modeState['appearance']! as Map<String, Object?>;
      appearance.remove('tabTransitionSpeed');
    }

    final decoded = codec.decode(jsonEncode(document));

    expect(decoded.alchemy.appearance.tabTransitionSpeed, 'normal');
    expect(decoded.cooking.appearance.tabTransitionSpeed, 'normal');
    expect(decoded.processing.appearance.tabTransitionSpeed, 'normal');
    final reencoded = jsonDecode(codec.encode(decoded)) as Map<String, Object?>;
    for (final mode in const <String>['alchemy', 'cooking', 'processing']) {
      final modeState = reencoded[mode]! as Map<String, Object?>;
      final appearance = modeState['appearance']! as Map<String, Object?>;
      expect(appearance['tabTransitionSpeed'], 'normal');
    }
  });

  test('captures unknown native fields in the nearest extension bucket', () {
    final document =
        jsonDecode(codec.encode(buildStateFixture())) as Map<String, Object?>;
    document['futureRootField'] = {'revision': 2};
    final alchemy = document['alchemy']! as Map<String, Object?>;
    alchemy['futureModeField'] = ['alpha', 'beta'];
    final market = alchemy['market']! as Map<String, Object?>;
    market['futureMarketField'] = 99;

    final state = codec.decode(jsonEncode(document));

    expect(state.extensions['futureRootField'], {'revision': 2});
    expect(state.alchemy.extensions['futureModeField'], ['alpha', 'beta']);
    expect(state.alchemy.market.extensions['futureMarketField'], 99);
    expect(
      codec.decode(codec.encode(state)).toJson(),
      state.toJson(),
      reason: 'captured extensions must survive the next native write',
    );
  });

  test('normalizes flexible recipe and metadata IDs to strings', () {
    final document =
        jsonDecode(codec.encode(buildStateFixture())) as Map<String, Object?>;
    final alchemy = document['alchemy']! as Map<String, Object?>;
    final edits = alchemy['recipeEdits']! as Map<String, Object?>;
    final recipe = edits['Old Item']! as Map<String, Object?>;
    recipe['marketId'] = 9007199254740991;
    final metadata = alchemy['ingredientMeta']! as Map<String, Object?>;
    final oldMetadata = metadata['Old Item']! as Map<String, Object?>;
    oldMetadata['marketId'] = true;

    final state = codec.decode(jsonEncode(document));

    expect(state.alchemy.recipeEdits['Old Item']!.marketId, '9007199254740991');
    expect(state.alchemy.ingredientMeta['Old Item']!.marketId, 'true');
  });

  test('persists reference-only recipe roles and rejects unknown roles', () {
    final document =
        jsonDecode(codec.encode(buildStateFixture())) as Map<String, Object?>;
    final alchemy = document['alchemy']! as Map<String, Object?>;
    final edits = alchemy['recipeEdits']! as Map<String, Object?>;
    final recipe = edits['Old Item']! as Map<String, Object?>;
    recipe['recipeRole'] = 'manual_conversion';

    final state = codec.decode(jsonEncode(document));
    expect(
      state.alchemy.recipeEdits['Old Item']?.role,
      RecipeRole.manualConversion,
    );
    final encoded = jsonDecode(codec.encode(state)) as Map<String, Object?>;
    final encodedAlchemy = encoded['alchemy']! as Map<String, Object?>;
    final encodedEdits = encodedAlchemy['recipeEdits']! as Map<String, Object?>;
    final encodedRecipe = encodedEdits['Old Item']! as Map<String, Object?>;
    expect(encodedRecipe['recipeRole'], 'manual_conversion');

    recipe['recipeRole'] = 'maybe_automatic';
    expect(
      () => codec.decode(jsonEncode(document)),
      throwsA(
        isA<PlannerStateFormatException>().having(
          (error) => error.path,
          'path',
          r'$.alchemy.recipeEdits.Old Item.recipeRole',
        ),
      ),
    );
  });

  test('normalizes recognized ingredient grades during native ingest', () {
    final document =
        jsonDecode(codec.encode(buildStateFixture())) as Map<String, Object?>;
    final alchemy = document['alchemy']! as Map<String, Object?>;
    alchemy['ingredientGrades'] = {
      'recipe:Old Item:Old Item': '  HiGh ',
      'blue-grade': '\tBLUE\n',
      'future-grade': ' rainbow ',
    };

    final state = codec.decode(jsonEncode(document));

    expect(state.alchemy.ingredientGrades, {
      'recipe:Old Item:Old Item': 'high',
      'blue-grade': 'blue',
      'future-grade': ' rainbow ',
    });
    expect(
      codec.decode(codec.encode(state)).alchemy.ingredientGrades,
      state.alchemy.ingredientGrades,
      reason: 'canonical grades and unknown future values must round-trip',
    );
  });

  test('round-trips the canonical Sakura background in every native mode', () {
    final document =
        jsonDecode(codec.encode(buildStateFixture())) as Map<String, Object?>;
    for (final mode in const <String>['alchemy', 'cooking', 'processing']) {
      final modeState = document[mode]! as Map<String, Object?>;
      final appearance = modeState['appearance']! as Map<String, Object?>;
      appearance['background'] = 'sakura-night-garden';
    }

    final decoded = codec.decode(jsonEncode(document));
    expect([
      decoded.alchemy.appearance.background,
      decoded.cooking.appearance.background,
      decoded.processing.appearance.background,
    ], everyElement('sakura-night-garden'));

    final redecoded = codec.decode(codec.encode(decoded));
    expect([
      redecoded.alchemy.appearance.background,
      redecoded.cooking.appearance.background,
      redecoded.processing.appearance.background,
    ], everyElement('sakura-night-garden'));
    expect(redecoded.toJson(), decoded.toJson());
  });

  test('rejects unsupported schemas and absent required native fields', () {
    final document =
        jsonDecode(codec.encode(buildStateFixture())) as Map<String, Object?>;
    for (final version in [0, 2]) {
      document['schemaVersion'] = version;
      expect(
        () => codec.decode(jsonEncode(document)),
        throwsA(
          isA<PlannerStateFormatException>().having(
            (error) => error.path,
            'path',
            r'$.schemaVersion',
          ),
        ),
      );
    }

    document['schemaVersion'] = 1;
    document.remove('alchemy');
    expect(
      () => codec.decode(jsonEncode(document)),
      throwsA(
        isA<PlannerStateFormatException>().having(
          (error) => error.path,
          'path',
          r'$.alchemy',
        ),
      ),
    );
  });

  test('rejects unknown fields on objects without extension storage', () {
    final document =
        jsonDecode(codec.encode(buildStateFixture())) as Map<String, Object?>;
    final alchemy = document['alchemy']! as Map<String, Object?>;
    final icons = alchemy['customIcons']! as Map<String, Object?>;
    final icon = icons['Old Item']! as Map<String, Object?>;
    icon['futureIconField'] = true;

    expect(
      () => codec.decode(jsonEncode(document)),
      throwsA(
        isA<PlannerStateFormatException>().having(
          (error) => error.path,
          'path',
          r'$.alchemy.customIcons.Old Item.futureIconField',
        ),
      ),
    );
  });

  test('exposes a byte validator suitable for AtomicFileStore', () {
    final encoded = codec.encode(buildStateFixture());
    expect(
      () => codec.validateBytes(Uint8List.fromList(utf8.encode(encoded))),
      returnsNormally,
    );
    expect(
      () => codec.validateBytes(Uint8List.fromList([0xff])),
      throwsA(isA<PlannerStateFormatException>()),
    );
  });
}
