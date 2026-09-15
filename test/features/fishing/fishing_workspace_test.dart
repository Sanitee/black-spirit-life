import 'dart:io';

import 'package:bdo_craft_planner_flutter/features/fishing/fishing.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory temporaryDirectory;

  setUp(() async {
    temporaryDirectory = await Directory.systemTemp.createTemp(
      'black-spirit-life-fishing-workspace-test-',
    );
  });

  tearDown(() async {
    if (await temporaryDirectory.exists()) {
      await temporaryDirectory.delete(recursive: true);
    }
  });

  testWidgets('fresh selected folder presents an empty local journal', (
    tester,
  ) async {
    await _pump(tester, temporaryDirectory);

    expect(find.text('Fishing journal'), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('fishing-empty-loadouts')),
      findsOneWidget,
    );
    expect(find.textContaining(temporaryDirectory.path), findsOneWidget);
    final fileExists = await tester.runAsync(
      () => File(FishingJournalRepository(temporaryDirectory).path).exists(),
    );
    expect(fileExists, isFalse);
  });

  testWidgets('loadouts support create, edit, delete, and reload', (
    tester,
  ) async {
    final controller = FishingWorkspaceController();
    await _pump(
      tester,
      temporaryDirectory,
      controller: controller,
      now: DateTime.utc(2026, 9, 15, 14),
    );

    await tester.tap(find.byKey(FishingWorkspace.addLoadoutKey));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(FishingWorkspace.loadoutNameFieldKey),
      'Ocean setup',
    );
    await tester.enterText(
      find.byKey(FishingWorkspace.loadoutMasteryFieldKey),
      '1750',
    );
    await tester.tap(find.byKey(FishingWorkspace.saveLoadoutKey));
    await _pumpUntil(tester, find.text('Fishing loadout saved locally.'));

    var persisted = await _loadJournal(tester, temporaryDirectory);
    expect(persisted.loadouts.single.name, 'Ocean setup');
    expect(persisted.loadouts.single.mastery, 1750);
    final id = persisted.loadouts.single.id;

    await tester.tap(find.byKey(ValueKey<String>('fishing-edit-loadout-$id')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(FishingWorkspace.loadoutNameFieldKey),
      'Edited ocean setup',
    );
    await tester.tap(find.byKey(FishingWorkspace.saveLoadoutKey));
    await _pumpUntil(tester, find.text('Fishing loadout updated.'));

    await tester.runAsync(controller.reload);
    await _pumpUntil(tester, find.text('Edited ocean setup'));
    persisted = await _loadJournal(tester, temporaryDirectory);
    expect(persisted.loadouts.single.id, id);
    expect(persisted.loadouts.single.name, 'Edited ocean setup');

    await tester.tap(
      find.byKey(ValueKey<String>('fishing-delete-loadout-$id')),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey<String>('fishing-confirm-delete')),
    );
    await _pumpUntil(tester, find.text('Fishing loadout removed.'));

    expect((await _loadJournal(tester, temporaryDirectory)).loadouts, isEmpty);
  });

  testWidgets('sessions support create, edit, delete, and disk persistence', (
    tester,
  ) async {
    final controller = FishingWorkspaceController();
    await _pump(
      tester,
      temporaryDirectory,
      controller: controller,
      now: DateTime.utc(2026, 9, 15, 16, 30),
    );
    await tester.tap(find.text('Sessions (0)'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(FishingWorkspace.addSessionKey));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(FishingWorkspace.sessionLocationFieldKey),
      'Velia coast',
    );
    await tester.enterText(
      find.byKey(FishingWorkspace.sessionDurationFieldKey),
      '45',
    );
    await tester.ensureVisible(find.byKey(FishingWorkspace.saveSessionKey));
    await tester.tap(find.byKey(FishingWorkspace.saveSessionKey));
    await _pumpUntil(tester, find.text('Fishing session saved locally.'));

    var persisted = await _loadJournal(tester, temporaryDirectory);
    expect(persisted.sessions.single.location, 'Velia coast');
    expect(persisted.sessions.single.durationMinutes, 45);
    final id = persisted.sessions.single.id;

    await tester.tap(find.byKey(ValueKey<String>('fishing-edit-session-$id')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(FishingWorkspace.sessionLocationFieldKey),
      'Heidel river',
    );
    await tester.ensureVisible(find.byKey(FishingWorkspace.saveSessionKey));
    await tester.tap(find.byKey(FishingWorkspace.saveSessionKey));
    await _pumpUntil(tester, find.text('Fishing session updated.'));

    await tester.runAsync(controller.flush);
    persisted = await _loadJournal(tester, temporaryDirectory);
    expect(persisted.sessions.single.id, id);
    expect(persisted.sessions.single.location, 'Heidel river');

    await tester.tap(
      find.byKey(ValueKey<String>('fishing-delete-session-$id')),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey<String>('fishing-confirm-delete')),
    );
    await _pumpUntil(tester, find.text('Fishing session removed.'));

    expect((await _loadJournal(tester, temporaryDirectory)).sessions, isEmpty);
  });

  testWidgets('freeze blocks edits until a failed folder switch resumes', (
    tester,
  ) async {
    final controller = FishingWorkspaceController();
    await _pump(tester, temporaryDirectory, controller: controller);

    await tester.runAsync(controller.freezeAndFlush);
    await tester.pump();
    var addButton = tester.widget<FilledButton>(
      find.byKey(FishingWorkspace.addLoadoutKey),
    );
    expect(addButton.onPressed, isNull);

    controller.resumeAfterFailedSwitch();
    await tester.pump();
    addButton = tester.widget<FilledButton>(
      find.byKey(FishingWorkspace.addLoadoutKey),
    );
    expect(addButton.onPressed, isNotNull);
  });
}

Future<void> _pump(
  WidgetTester tester,
  Directory directory, {
  FishingWorkspaceController? controller,
  DateTime? now,
}) async {
  tester.view.physicalSize = const Size(1280, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      home: SizedBox(
        width: 1280,
        height: 1000,
        child: FishingWorkspace(
          personalDataDirectory: directory,
          controller: controller,
          utcNow: now == null ? null : () => now,
        ),
      ),
    ),
  );
  await _pumpUntil(tester, find.text('Fishing journal'));
}

Future<void> _pumpUntil(WidgetTester tester, Finder finder) async {
  for (var attempt = 0; attempt < 60; attempt++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump(const Duration(milliseconds: 20));
    if (finder.evaluate().isNotEmpty) return;
  }
  throw TestFailure('Timed out waiting for the requested widget.');
}

Future<FishingJournal> _loadJournal(
  WidgetTester tester,
  Directory directory,
) async {
  final journal = await tester.runAsync(
    () => FishingJournalRepository(directory).load(),
  );
  return journal!;
}
