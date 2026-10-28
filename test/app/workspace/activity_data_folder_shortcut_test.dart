import 'dart:io';

import 'package:bdo_craft_planner_flutter/app/window/app_title_bar.dart';
import 'package:bdo_craft_planner_flutter/app/workspace/application_workspace.dart';
import 'package:bdo_craft_planner_flutter/features/data/data.dart';
import 'package:bdo_craft_planner_flutter/features/gathering/gathering_workspace.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/application_test_harness.dart';

void main() {
  testWidgets(
    'activity save-folder shortcut appears only on Gathering and Fish Map',
    (tester) async {
      configureApplicationTestSurface(tester, const Size(1200, 752));
      final harness = await _createHarness(tester);
      await _pumpApplication(tester, harness);

      final shortcut = find.byKey(
        ApplicationWorkspace.activityDataFolderShortcutKey,
      );
      expect(shortcut, findsNothing);

      await tester.tap(_workspaceTab('Fish Map'));
      await tester.pump();
      expect(shortcut, findsOneWidget);

      await tester.tap(_workspaceTab('Craft Planner'));
      await tester.pump();
      expect(shortcut, findsNothing);

      await tester.tap(_workspaceTab('Gathering'));
      await tester.pump();
      expect(shortcut, findsOneWidget);
      final gathering = tester.widget<GatheringWorkspace>(
        find.byType(GatheringWorkspace),
      );
      expect(
        gathering.dataDirectory.path,
        '${harness.bundle.personalDataLocation.applicationDirectory.path}'
        '${Platform.pathSeparator}gathering',
      );
      final gatheringElement = tester.element(find.byType(GatheringWorkspace));
      await tester.tap(shortcut);
      await tester.pump();
      expect(find.byTooltip('Back to Gathering'), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 250));
      await tester.tap(find.byKey(AppTitleTabStrip.returnButtonKey));
      await tester.pump();
      expect(_selectedWorkspaceTab(tester, 'Gathering'), isTrue);
      expect(
        tester.element(find.byType(GatheringWorkspace)),
        same(gatheringElement),
      );
      expect(find.byKey(AppTitleTabStrip.returnButtonKey), findsNothing);
      expect(tester.takeException(), isNull);

      await _disposeWidgetHarness(tester, harness);
    },
  );

  testWidgets(
    'activity save-folder shortcut identifies the current path and opens Data',
    (tester) async {
      configureApplicationTestSurface(tester, const Size(1200, 752));
      final harness = await _createHarness(tester);
      await _pumpApplication(tester, harness);

      final back = find.byKey(AppTitleTabStrip.returnButtonKey);
      expect(back, findsNothing);
      await tester.tap(_workspaceTab('Fish Map'));
      await tester.pump();
      expect(back, findsNothing);
      final fishElement = tester.element(
        find.byKey(const ValueKey('test-fish-map-workspace')),
      );

      final path =
          harness.bundle.personalDataLocation.applicationDirectory.path;
      final label =
          'Save folder for Gathering sessions and Fishing hauls. '
          'Current folder: $path. Open Craft Planner > Data.';
      final shortcut = find.byKey(
        ApplicationWorkspace.activityDataFolderShortcutKey,
      );
      final semantics = tester.widget<Semantics>(shortcut);
      expect(semantics.properties.label, label);
      expect(find.byTooltip(label), findsOneWidget);

      await tester.tap(shortcut);
      await tester.pump();

      expect(_selectedWorkspaceTab(tester, 'Craft Planner'), isTrue);
      expect(find.byType(DataView), findsOneWidget);
      expect(find.text('Personal data'), findsOneWidget);
      expect(shortcut, findsNothing);
      expect(find.byTooltip('Back to Fish Map'), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 250));
      await tester.tap(back);
      await tester.pump();
      expect(_selectedWorkspaceTab(tester, 'Fish Map'), isTrue);
      expect(
        tester.element(find.byKey(const ValueKey('test-fish-map-workspace'))),
        same(fishElement),
      );
      expect(back, findsNothing);

      // Clicking even the active tab clears the shortcut trail.
      await tester.tap(shortcut);
      await tester.pump();
      expect(back, findsOneWidget);
      await tester.tap(_workspaceTab('Craft Planner'));
      await tester.pump();
      expect(back, findsNothing);
      expect(tester.takeException(), isNull);

      await _disposeWidgetHarness(tester, harness);
    },
  );
}

Finder _workspaceTab(String label) => find.descendant(
  of: find.byKey(AppTitleTabStrip.semanticsKey),
  matching: find.byWidgetPredicate(
    (widget) =>
        widget is Semantics &&
        widget.properties.button == true &&
        widget.properties.label == label,
  ),
);

bool? _selectedWorkspaceTab(WidgetTester tester, String label) =>
    tester.widget<Semantics>(_workspaceTab(label)).properties.selected;

Future<ApplicationTestHarness> _createHarness(WidgetTester tester) async {
  var harness = (await tester.runAsync(ApplicationTestHarness.create))!;
  await tester.runAsync(harness.disposeControllerOnly);
  harness = harness.rebindControllerInCurrentZone();
  return harness;
}

Future<void> _pumpApplication(
  WidgetTester tester,
  ApplicationTestHarness harness,
) async {
  await tester.pumpWidget(
    MaterialApp(
      home: ApplicationWorkspace(
        enableOpportunityAutoCheck: false,
        bundle: harness.bundle,
        marketGateway: const EmptyMarketGateway(),
        fishMapWorkspace: const ColoredBox(
          key: ValueKey<String>('test-fish-map-workspace'),
          color: Colors.black,
        ),
        enableBetaUpdates: false,
      ),
    ),
  );
  for (var index = 0; index < 4; index++) {
    await tester.pump(const Duration(milliseconds: 80));
  }
}

Future<void> _disposeWidgetHarness(
  WidgetTester tester,
  ApplicationTestHarness harness,
) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump();
  await harness.bundle.controller.dispose();
  await tester.runAsync(() async {
    if (await harness.temporaryDirectory.exists()) {
      await harness.temporaryDirectory.delete(recursive: true);
    }
  });
}
