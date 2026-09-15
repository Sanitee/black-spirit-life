import 'dart:io';

import 'package:bdo_craft_planner_flutter/features/gathering/gathering_personal_store.dart';
import 'package:bdo_craft_planner_flutter/features/gathering/gathering_workspace.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory temporaryDirectory;

  setUp(() async {
    temporaryDirectory = await Directory.systemTemp.createTemp(
      'black-spirit-life-gathering-workspace-test-',
    );
  });

  tearDown(() async {
    if (await temporaryDirectory.exists()) {
      await temporaryDirectory.delete(recursive: true);
    }
  });

  testWidgets('fresh selected folder presents an empty Gathering journal', (
    tester,
  ) async {
    await _pump(tester, temporaryDirectory);

    expect(find.text('Gathering journal'), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('gathering-empty-sessions')),
      findsOneWidget,
    );
    expect(find.textContaining(temporaryDirectory.path), findsOneWidget);
    final fileExists = await tester.runAsync(
      () => File(GatheringPersonalStore(temporaryDirectory).path).exists(),
    );
    expect(fileExists, isFalse);
  });

  testWidgets('profile and session survive a workspace restart', (
    tester,
  ) async {
    final now = DateTime.utc(2026, 9, 15, 16, 45);
    await _pump(tester, temporaryDirectory, now: now);

    await tester.enterText(
      find.byKey(GatheringWorkspace.masteryFieldKey),
      '1775',
    );
    await tester.enterText(
      find.byKey(GatheringWorkspace.loadoutFieldKey),
      'My manos clothes and tool',
    );
    await tester.tap(find.byKey(GatheringWorkspace.saveProfileKey));
    await _pumpUntil(tester, find.text('Gathering profile saved locally.'));

    await tester.enterText(
      find.byKey(GatheringWorkspace.locationFieldKey),
      'Behr',
    );
    await tester.enterText(
      find.byKey(GatheringWorkspace.durationFieldKey),
      '40',
    );
    await tester.enterText(
      find.byKey(GatheringWorkspace.notesFieldKey),
      'Used 240 energy',
    );
    await tester.tap(find.byKey(GatheringWorkspace.saveSessionKey));
    await _pumpUntil(tester, find.text('Gathering session saved locally.'));

    final persisted = (await tester.runAsync(
      () => GatheringPersonalStore(temporaryDirectory).load(),
    ))!;
    expect(persisted.profile.mastery, 1775);
    expect(persisted.profile.loadoutNotes, 'My manos clothes and tool');
    expect(persisted.sessions, hasLength(1));
    expect(persisted.sessions.single.location, 'Behr');
    expect(persisted.sessions.single.notes, 'Used 240 energy');

    await _pump(
      tester,
      temporaryDirectory,
      now: now,
      key: const ValueKey<String>('restarted-gathering'),
    );

    expect(find.textContaining('Butchering · Behr'), findsOneWidget);
    expect(find.textContaining('40 min · 1775 mastery'), findsOneWidget);
    expect(find.text('Used 240 energy'), findsOneWidget);
  });
}

Future<void> _pump(
  WidgetTester tester,
  Directory directory, {
  DateTime? now,
  Key? key,
}) async {
  await tester.binding.setSurfaceSize(const Size(1200, 900));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      home: SizedBox(
        width: 1200,
        height: 900,
        child: GatheringWorkspace(
          key: key,
          personalDataDirectory: directory,
          utcNow: now == null ? null : () => now,
        ),
      ),
    ),
  );
  await _pumpUntil(tester, find.text('Gathering journal'));
}

Future<void> _pumpUntil(WidgetTester tester, Finder finder) async {
  for (var attempt = 0; attempt < 50; attempt++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump(const Duration(milliseconds: 20));
    if (finder.evaluate().isNotEmpty) return;
  }
  throw TestFailure('Timed out waiting for $finder.');
}
