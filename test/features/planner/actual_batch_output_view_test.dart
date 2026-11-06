import 'dart:io';
import 'dart:ui' as ui;

import 'package:bdo_craft_planner_flutter/app/app.dart';
import 'package:bdo_craft_planner_flutter/domain/models/craft_mode.dart';
import 'package:bdo_craft_planner_flutter/domain/state/planner_state.dart';
import 'package:bdo_craft_planner_flutter/domain/state/state_copy.dart';
import 'package:bdo_craft_planner_flutter/features/resource_map/resource_map_workspace.dart';
import 'package:bdo_craft_planner_flutter/visual/visual.dart';
import 'package:bdo_map_core/bdo_map_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../../support/application_test_harness.dart';

const _captureKey = ValueKey('actual-batch-capture');
Finder key(String value) => find.byKey(ValueKey('planner-afk-$value'));

void main() {
  setUpAll(() async {
    for (final entry in {
      'Segoe UI': [
        'C:/Windows/Fonts/segoeui.ttf',
        'C:/Windows/Fonts/seguisb.ttf',
      ],
      'Georgia': [
        'C:/Windows/Fonts/georgia.ttf',
        'C:/Windows/Fonts/georgiab.ttf',
      ],
      'MaterialIcons': [
        'D:/Tools/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
      ],
    }.entries) {
      final loader = FontLoader(entry.key);
      for (final path in entry.value) {
        if (File(path).existsSync()) {
          loader.addFont(File(path).readAsBytes().then(ByteData.sublistView));
        }
      }
      await loader.load();
    }
    await BdoResourceMapLoader.loadBundled();
    await BdoWorkerEconomicsLoader.loadBundled();
    await LodgingDataLoader.loadBundled();
  });

  for (final spec in RetainedThemeRegistry.themes) {
    for (final scenario in [
      (const Size(1200, 752), 1.0),
      (const Size(960, 600), 1.0),
      (const Size(1200, 752), 2.0),
    ]) {
      final (size, scale) = scenario;
      testWidgets('actual app ${spec.id} ${size.width} text $scale', (
        tester,
      ) async {
        configureApplicationTestSurface(tester, size, textScaleFactor: scale);
        final original = (await tester.runAsync(
          () => ApplicationTestHarness.create(
            activeMode: CraftMode.processing,
            backgroundId: spec.isStandard ? 'greenhouse' : spec.id,
          ),
        ))!;
        final harness = original.rebindControllerInCurrentZone();
        await tester.runAsync(original.disposeControllerOnly);
        final app = harness.bundle.controller;
        final mode = app.active;
        mode.selectTarget('Corn Flour');
        mode.commitAmount('2500');
        mode.commitInventory('Corn', '2000');
        app.updateDocument(
          (s) => s.copyWith(
            afkWeightProfile: AfkWeightProfile(
              maximumWeightLt: 5000,
              currentCarriedWeightLt: 0,
              safetyBufferLt: 100,
            ),
          ),
        );
        final client = MockClient(
          (_) async => http.Response('No networking', 503),
        );
        final name = '${spec.id}-${size.width.toInt()}-$scale';
        try {
          await tester.pumpWidget(
            RepaintBoundary(
              key: _captureKey,
              child: BdoCraftPlannerApp(
                applicationFuture: Future.value(harness.bundle),
                enableOpportunityAutoCheck: false,
                marketGateway: const EmptyMarketGateway(),
                resourceMapConfiguration: ResourceMapWorkspaceConfiguration(
                  cacheDirectory: Directory(
                    '${harness.temporaryDirectory.path}/map-cache',
                  ),
                  tileHttpClient: client,
                  showSourceNotice: false,
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          await tester.ensureVisible(key('load:processing:Corn Flour'));
          await tester.pumpAndSettle();
          await tester.tap(key('load:processing:Corn Flour'));
          await tester.pumpAndSettle();
          expect(key('actual-output'), findsOneWidget);
          expect(
            tester.widget<TextField>(key('actual-output')).controller!.text,
            isEmpty,
          );
          final before = mode.state.value.toJson();
          await withinPopup(tester, key('actual-output'));
          await tester.enterText(key('actual-output'), '2.480');
          await tester.testTextInput.receiveAction(TextInputAction.done);
          await tester.pumpAndSettle();
          expect(mode.state.value.toJson(), before);
          expect(key('output-warning'), findsNothing);
          if (scale == 1) {
            expect(
              tester.getSize(key('output-band')).height,
              tester.getSize(key('ingredient-band:Corn')).height,
            );
            expect(
              tester.widget<TextField>(key('actual-output')).style,
              tester.widget<Text>(key('total:Corn')).style,
            );
          }
          await capture(tester, '$name-actual');
          await press(tester, key('complete-round'));
          expect(mode.state.value.inventory['Corn Flour'], 2480);
          expect(mode.state.value.inventory['Corn'], 1000);
          expect(mode.plan.value.steps.single.count, 8);
          expect(mode.state.value.completedSteps, isEmpty);
          expect(
            tester.widget<TextField>(key('actual-output')).controller!.text,
            isEmpty,
          );
          await press(tester, key('undo-round'));
          expect(mode.state.value.inventory['Corn Flour'] ?? 0, 0);
          expect(mode.state.value.inventory['Corn'], 2000);
          await withinPopup(tester, key('actual-output'));
          await tester.enterText(key('actual-output'), '1500');
          await tester.pumpAndSettle();
          expect(key('output-warning'), findsNothing);
          await press(tester, key('complete-round'));
          expect(key('output-warning'), findsOneWidget);
          expect(mode.state.value.inventory['Corn'], 2000);
          await withinPopup(tester, key('output-confirm'));
          await capture(tester, '$name-warning');
          await press(tester, key('output-back'));
          expect(
            tester.widget<TextField>(key('actual-output')).controller!.text,
            '1500',
          );
          await press(tester, key('complete-round'));
          await press(tester, key('output-confirm'));
          expect(mode.state.value.inventory['Corn Flour'], 1500);
          expect(mode.state.value.inventory['Corn'], 1000);
          expect(mode.plan.value.steps.single.count, 400);
          await press(tester, key('undo-round'));
          await withinPopup(tester, key('actual-output'));
          await tester.enterText(key('actual-output'), '-20');
          await press(tester, key('complete-round'));
          expect(key('output-error'), findsOneWidget);
          expect(mode.state.value.inventory['Corn'], 2000);
          // A different capacity is a different batch; discard an old draft.
          app.updateDocument(
            (s) => s.copyWith(
              afkWeightProfile: s.afkWeightProfile.copyWith(
                safetyBufferLt: 200,
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(
            tester.widget<TextField>(key('actual-output')).controller!.text,
            isEmpty,
          );
          expect(key('output-error'), findsNothing);
          await withinPopup(tester, key('actual-output'));
          await tester.enterText(key('actual-output'), '0');
          await press(tester, key('complete-round'));
          expect(key('output-warning'), findsNothing);
          expect(mode.state.value.inventory['Corn Flour'], 2500);
          expect(mode.plan.value.steps, isEmpty);
          expect(mode.undoCompletion(), isTrue);
          expect(mode.state.value.inventory['Corn'], 2000);
          expect(tester.takeException(), isNull);
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          await harness.disposeControllerOnly();
          client.close();
          await tester.runAsync(
            () => harness.temporaryDirectory.delete(recursive: true),
          );
        }
      });
    }
  }
}

Future<void> withinPopup(WidgetTester tester, Finder finder) async {
  final element = tester.element(finder);
  final scroll = Scrollable.maybeOf(element);
  if (scroll != null) {
    await scroll.position.ensureVisible(element.findRenderObject()!);
  }
  await tester.pumpAndSettle();
  expect(finder.hitTestable(), findsOneWidget);
}

Future<void> press(WidgetTester tester, Finder finder) async {
  await withinPopup(tester, finder);
  await tester.tap(finder);
  await tester.pumpAndSettle();
  expect(tester.takeException(), isNull);
}

Future<void> capture(WidgetTester tester, String name) async {
  final folder = Platform.environment['BSL_ACTUAL_BATCH_CAPTURE_DIR'];
  if (folder == null) return;
  for (final element in find.byType(Image).evaluate()) {
    await tester.runAsync(
      () => precacheImage((element.widget as Image).image, element),
    );
  }
  await tester.pumpAndSettle();
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(_captureKey),
  );
  await tester.runAsync(() async {
    await Directory(folder).create(recursive: true);
    final image = await boundary.toImage(pixelRatio: 1);
    try {
      final bytes = (await image.toByteData(format: ui.ImageByteFormat.png))!;
      await File('$folder/$name.png').writeAsBytes(bytes.buffer.asUint8List());
    } finally {
      image.dispose();
    }
  });
}
