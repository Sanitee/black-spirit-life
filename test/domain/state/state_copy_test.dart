import 'package:bdo_craft_planner_flutter/domain/state/planner_state.dart';
import 'package:bdo_craft_planner_flutter/domain/state/state_copy.dart';
import 'package:flutter_test/flutter_test.dart';

import 'state_test_fixture.dart';

void main() {
  test('AFK weight profile copyWith preserves settings and extension data', () {
    final original = AfkWeightProfile(
      maximumWeightLt: 1600,
      currentCarriedWeightLt: 100,
      safetyBufferLt: 20,
      featheryStepsLevel: 5,
      extensions: const {'futureField': true},
    );

    final changed = original.copyWith(currentCarriedWeightLt: 125);

    expect(changed.maximumWeightLt, 1600);
    expect(changed.currentCarriedWeightLt, 125);
    expect(changed.safetyBufferLt, 20);
    expect(changed.featheryStepsLevel, 5);
    expect(changed.penaltyMultiplier, 1.25);
    expect(changed.penaltyThresholdLt, 2000);
    expect(changed.safeLimitLt, 1855);
    expect(changed.extensions, original.extensions);
  });

  test('AFK progress helpers isolate contexts and keep storage bounded', () {
    var state = buildStateFixture().alchemy.copyWith(
      afkCraftProgress: const {},
    );
    final normalKey = AfkCraftProgress.sessionKeyFor(
      targetName: 'Goal A',
      recipeName: 'Shared Recipe',
    );
    final bonusKey = AfkCraftProgress.sessionKeyFor(
      targetName: 'Goal B',
      recipeName: 'Shared Recipe',
      bonus: true,
    );
    state = state
        .reconcileAfkCraftProgress(
          targetName: 'Goal A',
          targetAmount: 100,
          recipeName: 'Shared Recipe',
          planSignature: 'shared:v1',
          totalAttempts: 100,
          attemptsPerRound: 30,
          progressKey: normalKey,
        )
        .reconcileAfkCraftProgress(
          targetName: 'Goal B',
          targetAmount: 50,
          recipeName: 'Shared Recipe',
          planSignature: 'shared:v1',
          totalAttempts: 50,
          attemptsPerRound: 20,
          progressKey: bonusKey,
        )
        .completeAfkCraftThrough('Shared Recipe', 30, progressKey: normalKey);

    expect(state.afkCraftProgress, hasLength(2));
    expect(
      state
          .afkCraftProgressFor('Shared Recipe', progressKey: normalKey)
          ?.completedAttempts,
      30,
    );
    expect(
      state
          .afkCraftProgressFor('Shared Recipe', progressKey: bonusKey)
          ?.completedAttempts,
      0,
    );

    for (
      var index = 0;
      index < AfkCraftProgress.maximumStoredStepsPerMode + 3;
      index++
    ) {
      state = state.reconcileAfkCraftProgress(
        targetName: 'Goal $index',
        targetAmount: 1,
        recipeName: 'Recipe $index',
        planSignature: 'recipe:$index',
        totalAttempts: 1,
        attemptsPerRound: 1,
      );
    }
    expect(
      state.afkCraftProgress,
      hasLength(AfkCraftProgress.maximumStoredStepsPerMode),
    );
  });

  test('MarketTax copyWith preserves modifiers and extension data', () {
    final original = MarketTax(
      valuePack: true,
      merchantRing: true,
      familyFameBonus: .015,
      extensions: const <String, Object?>{
        'futureField': <String, Object?>{'enabled': true},
      },
    );

    final disabled = original.copyWith(enabled: false);

    expect(disabled.enabled, isFalse);
    expect(disabled.valuePack, isTrue);
    expect(disabled.merchantRing, isTrue);
    expect(disabled.familyFameBonus, .015);
    expect(disabled.extensions, original.extensions);

    final changedFame = disabled.copyWith(familyFameBonus: .005);
    expect(changedFame.enabled, isFalse);
    expect(changedFame.valuePack, isTrue);
    expect(changedFame.merchantRing, isTrue);
    expect(changedFame.familyFameBonus, .005);
    expect(changedFame.extensions, original.extensions);
  });

  test('MarketState copyWith preserves and can replace trade evidence', () {
    final original = MarketState(
      tradeMarketIds: const <String, String>{'Ore': '9'},
      totalTrades: const <String, int>{'Ore': 100},
      tradeObservedAt: const <String, int>{'Ore': 1000},
      observedDailyTrades: const <String, double>{'Ore': 24},
      tradeObservationHours: const <String, double>{'Ore': 8},
      lastSoldAtEpochSeconds: const <String, int>{'Ore': 900},
    );

    final changed = original.copyWith(
      totalTrades: const <String, int>{'Ore': 108},
      observedDailyTrades: const <String, double>{'Ore': 12},
    );

    expect(changed.tradeMarketIds, original.tradeMarketIds);
    expect(changed.totalTrades, const <String, int>{'Ore': 108});
    expect(changed.tradeObservedAt, original.tradeObservedAt);
    expect(changed.observedDailyTrades, const <String, double>{'Ore': 12});
    expect(changed.tradeObservationHours, original.tradeObservationHours);
    expect(changed.lastSoldAtEpochSeconds, original.lastSoldAtEpochSeconds);
  });
}
