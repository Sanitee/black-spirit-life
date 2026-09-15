import 'dart:async';

import 'package:bdo_craft_planner_flutter/data/persistence/personal_data_write_gate.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'freeze waits for accepted writes and rejects later mutations',
    () async {
      final gate = PersonalDataWriteGate();
      final release = Completer<void>();
      var completed = false;

      final write = gate.run(() async {
        await release.future;
        completed = true;
      });
      final frozen = gate.freezeAndFlush();

      expect(gate.mutationsFrozen, isTrue);
      await expectLater(gate.run(() async {}), throwsA(isA<StateError>()));
      expect(completed, isFalse);

      release.complete();
      await write;
      await frozen;
      expect(completed, isTrue);
    },
  );

  test(
    'failed writes do not poison the queue and a failed move can resume',
    () async {
      final gate = PersonalDataWriteGate();

      await expectLater(
        gate.run<void>(() async => throw StateError('disk failure')),
        throwsStateError,
      );
      await expectLater(gate.flush(), throwsStateError);
      await expectLater(gate.freezeAndFlush(), throwsStateError);
      gate.resumeAfterMoveFailure();

      var saved = false;
      await gate.run(() async => saved = true);
      expect(saved, isTrue);
    },
  );
}
