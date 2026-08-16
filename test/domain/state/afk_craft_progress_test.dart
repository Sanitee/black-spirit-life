import 'package:bdo_craft_planner_flutter/domain/state/planner_state.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  AfkCraftProgress progress({
    int totalAttempts = 17,
    int attemptsPerRound = 6,
    int completedAttempts = 0,
  }) => AfkCraftProgress(
    stepKey: 'Clear Liquid Reagent',
    targetName: 'Elixir of Will',
    targetAmount: 100,
    recipeName: 'Clear Liquid Reagent',
    planSignature: 'clear-liquid:v1:normal',
    totalAttempts: totalAttempts,
    attemptsPerRound: attemptsPerRound,
    completedAttempts: completedAttempts,
  );

  test('derives numbered rounds from sequential confirmed attempts', () {
    final session = progress(completedAttempts: 12);

    expect(session.totalRounds, 3);
    expect(session.attemptsInRound(1), 6);
    expect(session.attemptsInRound(2), 6);
    expect(session.attemptsInRound(3), 5);
    expect(session.completedRoundCount, 2);
    expect(session.isRoundCompleted(1), isTrue);
    expect(session.isRoundCompleted(2), isTrue);
    expect(session.completedAttemptsInRound(3), 0);
    expect(session.remainingAttempts, 5);
    expect(session.isComplete, isFalse);
  });

  test('marking and undoing a round keeps progress sequential', () {
    final first = progress().markRoundCompleted(2);

    expect(first.completedAttempts, 12);
    expect(first.completedRoundCount, 2);
    expect(first.markRoundCompleted(1), same(first));

    final undone = first.markRoundIncomplete(2);
    expect(undone.completedAttempts, 6);
    expect(undone.completedRoundCount, 1);
    expect(undone.markRoundIncomplete(3), same(undone));
  });

  test('capacity changes preserve attempts and expose a partial new round', () {
    final session = progress(completedAttempts: 12);

    final reconciled = session.reconcile(
      stepKey: session.stepKey,
      targetName: session.targetName,
      targetAmount: session.targetAmount,
      recipeName: session.recipeName,
      planSignature: session.planSignature,
      totalAttempts: 17,
      attemptsPerRound: 5,
    );

    expect(reconciled.completedAttempts, 12);
    expect(reconciled.completedRoundCount, 2);
    expect(reconciled.completedAttemptsInRound(3), 2);
    expect(reconciled.isRoundPartiallyCompleted(3), isTrue);
  });

  test(
    'exact calculated load endpoints do not snap to new round boundaries',
    () {
      final reconciled = progress(
        totalAttempts: 100,
        attemptsPerRound: 30,
        completedAttempts: 40,
      );

      final completed = reconciled.completeThrough(70);

      expect(completed.completedAttempts, 70);
      expect(completed.remainingAttempts, 30);
      expect(completed.completeThrough(60), same(completed));
    },
  );

  test('queue-size changes preserve and safely clamp confirmed attempts', () {
    final session = progress(completedAttempts: 12);

    final reconciled = session.reconcile(
      stepKey: session.stepKey,
      targetName: session.targetName,
      targetAmount: session.targetAmount,
      recipeName: session.recipeName,
      planSignature: session.planSignature,
      totalAttempts: 9,
      attemptsPerRound: 5,
    );

    expect(reconciled.completedAttempts, 9);
    expect(reconciled.isComplete, isTrue);
  });

  test('a changed target or recipe definition starts a fresh session', () {
    final session = progress(completedAttempts: 12);

    final changedTarget = session.reconcile(
      stepKey: session.stepKey,
      targetName: session.targetName,
      targetAmount: 200,
      recipeName: session.recipeName,
      planSignature: session.planSignature,
      totalAttempts: 34,
      attemptsPerRound: 6,
    );
    final changedRecipe = session.reconcile(
      stepKey: session.stepKey,
      targetName: session.targetName,
      targetAmount: session.targetAmount,
      recipeName: session.recipeName,
      planSignature: 'clear-liquid:v2:special',
      totalAttempts: 17,
      attemptsPerRound: 6,
    );

    expect(changedTarget.completedAttempts, 0);
    expect(changedRecipe.completedAttempts, 0);
  });

  test('checking invalid rounds cannot claim that crafting happened', () {
    final session = progress();

    expect(session.markRoundCompleted(0), same(session));
    expect(session.markRoundCompleted(4), same(session));
    expect(session.completedAttempts, 0);
  });

  test('extreme targets expose O(1) round counts without allocating a set', () {
    final session = progress(
      totalAttempts: 0x7fffffff,
      attemptsPerRound: 1,
      completedAttempts: 0x7ffffffe,
    );

    expect(session.totalRounds, 0x7fffffff);
    expect(session.completedRoundCount, 0x7ffffffe);
    expect(session.isRoundCompleted(0x7ffffffe), isTrue);
    expect(session.isRoundCompleted(0x7fffffff), isFalse);
  });
}
