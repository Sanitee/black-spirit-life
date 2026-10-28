import 'dart:io';
import 'dart:ui' as ui;

import 'package:bdo_craft_planner_flutter/app/app.dart';
import 'package:bdo_craft_planner_flutter/domain/models/craft_mode.dart';
import 'package:bdo_craft_planner_flutter/features/appearance/appearance.dart';
import 'package:bdo_craft_planner_flutter/features/appearance/planner_appearance_popover.dart';
import 'package:bdo_craft_planner_flutter/features/appearance/planner_size_title_action.dart';
import 'package:bdo_craft_planner_flutter/features/planner/planner.dart';
import 'package:bdo_craft_planner_flutter/features/shell/shell.dart';
import 'package:bdo_craft_planner_flutter/visual/visual.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/application_test_harness.dart';

const _captureKey = ValueKey('planner-appearance-integration-capture');

void main() {
  setUpAll(_loadFonts);
  for (final background in [
    'sakura-night-garden',
    'illuminated-ledger',
    'greenhouse',
  ]) {
    for (final textScale in [1.0, 2.0]) {
      testWidgets(
        '$background size popup anchors to the title icon at ${textScale * 100}% text',
        (tester) async {
          final harness = await _open(
            tester,
            background: background,
            textScale: textScale,
          );
          try {
            final app = harness.bundle.controller;
            final planner = find.byType(PlannerView).evaluate().single;
            final plan = app.active.plan.value;
            final originalSidebar = tester.getRect(
              find.byKey(WorkspaceShellKeys.sidebar),
            );
            final originalContent = tester.getRect(
              find.byKey(WorkspaceShellKeys.contentHost),
            );
            await tester.tap(find.byKey(PlannerSizeTitleAction.triggerKey));
            await _settle(tester);
            expect(app.active.state.value.view, 'plan');
            expect(find.byType(AppearanceView), findsNothing);
            expect(find.byType(PlannerView).evaluate().single, same(planner));
            final popup = tester.getRect(
              find.byKey(PlannerAppearancePopover.surfaceKey),
            );
            final trigger = tester.getRect(
              find.byKey(PlannerSizeTitleAction.triggerKey),
            );
            expect(popup.left, greaterThan(originalSidebar.right));
            expect(popup.right, lessThanOrEqualTo(1566));
            expect(popup.right, closeTo(trigger.right, 10));
            expect(popup.top, greaterThanOrEqualTo(trigger.bottom));
            expect(popup.height, lessThan(360));
            expect(find.text('Full appearance settings'), findsNothing);
            final slider = tester.widget<AppSlider>(
              find.byKey(PlannerAppearancePopover.sliderKey),
            );
            if (slider.onChanged != null) {
              await tester.tapAt(
                tester
                        .getRect(find.byKey(PlannerAppearancePopover.sliderKey))
                        .centerRight -
                    const Offset(12, 0),
              );
              await _settle(tester);
              expect(
                app.plannerContentScale.value,
                closeTo(slider.max / 100, .00001),
              );
              expect(
                app.documentSnapshot.plannerContentScale,
                app.plannerContentScale.value,
              );
            }
            expect(app.active.plan.value, same(plan));
            expect(find.byType(PlannerView).evaluate().single, same(planner));
            expect(
              tester.getRect(find.byKey(WorkspaceShellKeys.sidebar)),
              originalSidebar,
            );
            expect(
              tester.getRect(find.byKey(WorkspaceShellKeys.contentHost)),
              originalContent,
            );
            await _capture(
              tester,
              '$background-text${(textScale * 100).round()}',
            );
            if (slider.onChanged != null) {
              final previous = app.plannerContentScale.value;
              await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
              await _settle(tester);
              expect(
                app.plannerContentScale.value,
                closeTo(previous - .01, .00001),
              );
              expect(
                app.documentSnapshot.plannerContentScale,
                app.plannerContentScale.value,
              );
              expect(app.active.plan.value, same(plan));
            }
            await tester.sendKeyEvent(LogicalKeyboardKey.escape);
            await _settle(tester);
            expect(
              find.byKey(PlannerAppearancePopover.surfaceKey),
              findsNothing,
            );
            expect(app.active.state.value.view, 'plan');
            expect(tester.takeException(), isNull);
          } finally {
            await _dispose(tester, harness);
          }
        },
      );
    }
  }

  for (final (textScale, requestedScale) in [
    (1.0, 1.0),
    (1.0, 1.25),
    (2.0, 1.0),
    (2.0, 1.25),
  ]) {
    testWidgets(
      'scaled Planner overlays anchor and select correctly at ${textScale * 100}% text and ${requestedScale * 100}% requested zoom',
      (tester) async {
        final harness = await _open(tester, textScale: textScale);
        try {
          final app = harness.bundle.controller;
          app.commitPlannerContentScale(requestedScale);
          await _settle(tester);
          final transform = tester.widget<Transform>(
            find.byKey(const ValueKey('planner-content-transform')),
          );
          expect(
            transform.transform.storage[0],
            requestedScale == 1 ? equals(1) : greaterThan(1),
          );

          final sourceButton = find.byWidgetPredicate(
            (widget) =>
                widget is AppButton &&
                widget.semanticLabel ==
                    'Source information for Purified Water, closed',
          );
          expect(sourceButton.hitTestable(), findsOneWidget);
          await tester.tap(sourceButton);
          await _settle(tester);
          final source = find.byKey(const ValueKey('planner-source-info-card'));
          final sourceBounds = tester.getRect(source);
          expect(sourceBounds.left, greaterThanOrEqualTo(0));
          expect(sourceBounds.top, greaterThanOrEqualTo(0));
          expect(sourceBounds.right, lessThanOrEqualTo(1566));
          expect(sourceBounds.bottom, lessThanOrEqualTo(991));
          expect(source.hitTestable(), findsOneWidget);
          if (requestedScale > 1) {
            await _capture(
              tester,
              'scaled-source-text${(textScale * 100).round()}',
            );
          }
          await tester.tap(
            find.byKey(const ValueKey('planner-source-info-close')),
          );
          await _settle(tester);
          expect(source, findsNothing);

          final target = find.descendant(
            of: find.byKey(PlannerActionKeys.p01),
            matching: find.byType(TextField),
          );
          await tester.tap(target);
          await tester.enterText(target, 'Pure Powder');
          await _settle(tester);
          final choices = find.byWidgetPredicate(
            (widget) =>
                widget is AppSurface &&
                widget.semanticLabel == 'Choose recipe choices',
          );
          expect(choices, findsOneWidget);
          final choicesBounds = tester.getRect(choices);
          final targetBounds = tester.getRect(target);
          expect(choicesBounds.top, greaterThanOrEqualTo(targetBounds.bottom));
          expect(choicesBounds.left, closeTo(targetBounds.left, 1));
          expect(choicesBounds.right, lessThanOrEqualTo(1566));
          expect(choicesBounds.bottom, lessThanOrEqualTo(991));
          final option = find.byWidgetPredicate(
            (widget) =>
                widget is AppButton &&
                widget.semanticLabel == 'Select Pure Powder Reagent',
          );
          expect(option.hitTestable(), findsOneWidget);
          if (requestedScale > 1) {
            await _capture(
              tester,
              'scaled-target-dropdown-text${(textScale * 100).round()}',
            );
          }
          final mouse = await tester.startGesture(
            tester.getCenter(option),
            kind: ui.PointerDeviceKind.mouse,
          );
          await tester.pump();
          await mouse.up();
          await _settle(tester);
          expect(app.active.state.value.target, 'Pure Powder Reagent');
          expect(choices, findsNothing);
          expect(
            tester.widget<TextField>(target).controller!.text,
            'Pure Powder Reagent',
          );
          expect(app.documentSnapshot.plannerContentScale, requestedScale);
          expect(tester.takeException(), isNull);
        } finally {
          await _dispose(tester, harness);
        }
      },
    );
  }

  testWidgets(
    'open popup follows resized fit caps without losing requested zoom',
    (tester) async {
      final harness = await _open(tester);
      try {
        final app = harness.bundle.controller;
        final plan = app.active.plan.value;
        app.commitPlannerContentScale(1.25);
        await _settle(tester);
        await tester.tap(find.byKey(PlannerSizeTitleAction.triggerKey));
        await _settle(tester);

        tester.view.physicalSize = const Size(1000, 900);
        await _settle(tester);
        final capped = tester.widget<AppSlider>(
          find.byKey(PlannerAppearancePopover.sliderKey),
        );
        expect(capped.value, 100);
        expect(capped.max, 100);
        expect(capped.onChanged, isNull);
        expect(app.plannerContentScale.value, 1.25);
        expect(app.documentSnapshot.plannerContentScale, 1.25);
        final popup = tester.getRect(
          find.byKey(PlannerAppearancePopover.surfaceKey),
        );
        expect(popup.left, greaterThanOrEqualTo(0));
        expect(popup.right, lessThanOrEqualTo(1000));
        expect(popup.top, greaterThanOrEqualTo(40));
        expect(popup.bottom, lessThanOrEqualTo(900));

        tester.view.physicalSize = const Size(1800, 1000);
        await _settle(tester);
        final enlarged = tester.widget<AppSlider>(
          find.byKey(PlannerAppearancePopover.sliderKey),
        );
        expect(enlarged.max, greaterThan(100));
        expect(enlarged.value, enlarged.max);
        expect(enlarged.onChanged, isNotNull);
        expect(app.plannerContentScale.value, 1.25);
        expect(app.documentSnapshot.plannerContentScale, 1.25);
        expect(app.active.plan.value, same(plan));
        await tester.tap(find.byKey(PlannerAppearancePopover.closeKey));
        await _settle(tester);
        expect(app.documentSnapshot.plannerContentScale, 1.25);
        expect(tester.takeException(), isNull);
      } finally {
        await _dispose(tester, harness);
      }
    },
  );

  testWidgets(
    'Appearance opens directly from Planner, including with size controls open',
    (tester) async {
      final harness = await _open(tester);
      try {
        final app = harness.bundle.controller;
        await tester.tap(find.byKey(ShellDestination.appearance.actionKey));
        await _settle(tester);
        expect(find.byKey(PlannerAppearancePopover.surfaceKey), findsNothing);
        expect(find.byType(AppearanceView), findsOneWidget);
        expect(app.active.state.value.view, 'appearance');
        expect(find.byKey(PlannerSizeTitleAction.triggerKey), findsNothing);
        await tester.tap(
          find.byKey(ShellDestination.planner.actionKey).hitTestable().first,
        );
        await _settle(tester);
        await tester.tap(find.byKey(PlannerSizeTitleAction.triggerKey));
        await _settle(tester);
        expect(find.byKey(PlannerAppearancePopover.surfaceKey), findsOneWidget);
        await tester.tap(find.byKey(ShellDestination.appearance.actionKey));
        await _settle(tester);
        expect(find.byKey(PlannerAppearancePopover.surfaceKey), findsNothing);
        expect(find.byType(AppearanceView), findsOneWidget);
        expect(app.active.state.value.view, 'appearance');
        await tester.tap(
          find.byKey(ShellDestination.inventory.actionKey).hitTestable().first,
        );
        await _settle(tester);
        await tester.tap(
          find.byKey(ShellDestination.appearance.actionKey).hitTestable().first,
        );
        await _settle(tester);
        expect(find.byKey(PlannerAppearancePopover.surfaceKey), findsNothing);
        expect(find.byType(AppearanceView), findsOneWidget);
        expect(app.active.state.value.view, 'appearance');
        expect(tester.takeException(), isNull);
      } finally {
        await _dispose(tester, harness);
      }
    },
  );

  testWidgets(
    'navigation dismisses preview and reopening retains the chosen zoom',
    (tester) async {
      final harness = await _open(tester);
      try {
        final app = harness.bundle.controller;
        await tester.tap(find.byKey(PlannerSizeTitleAction.triggerKey));
        await _settle(tester);
        final slider = tester.widget<AppSlider>(
          find.byKey(PlannerAppearancePopover.sliderKey),
        );
        final selected = slider.max / 100;
        slider.onChanged!(slider.max);
        await tester.pump();
        await tester.tap(find.byKey(ShellActionKeys.mode(CraftMode.cooking)));
        await _settle(tester);
        expect(find.byKey(PlannerAppearancePopover.surfaceKey), findsNothing);
        expect(app.documentSnapshot.plannerContentScale, selected);
        await tester.tap(find.byKey(ShellActionKeys.mode(CraftMode.alchemy)));
        await _settle(tester);
        await tester.tap(find.byKey(PlannerSizeTitleAction.triggerKey));
        await _settle(tester);
        expect(app.plannerContentScale.value, selected);
        await tester.tap(find.byKey(PlannerAppearancePopover.resetKey));
        await _settle(tester);
        expect(app.plannerContentScale.value, 1);
        expect(app.documentSnapshot.plannerContentScale, 1);
        await tester.tap(find.byKey(PlannerAppearancePopover.closeKey));
        await _settle(tester);
        expect(find.byKey(PlannerAppearancePopover.surfaceKey), findsNothing);
        expect(tester.takeException(), isNull);
      } finally {
        await _dispose(tester, harness);
      }
    },
  );
}

Future<ApplicationTestHarness> _open(
  WidgetTester tester, {
  String background = 'sakura-night-garden',
  double textScale = 1,
}) async {
  configureApplicationTestSurface(
    tester,
    const Size(1566, 991),
    textScaleFactor: textScale,
  );
  final original = (await tester.runAsync(
    () => ApplicationTestHarness.create(backgroundId: background),
  ))!;
  final harness = original.rebindControllerInCurrentZone();
  await tester.runAsync(original.disposeControllerOnly);
  harness.bundle.controller.active.selectTarget('Adaptation Draught');
  harness.bundle.controller.active.commitAmount('100');
  await tester.pumpWidget(
    RepaintBoundary(
      key: _captureKey,
      child: BdoCraftPlannerApp(
        applicationFuture: Future.value(harness.bundle),
        marketGateway: const EmptyMarketGateway(),
        enableOpportunityAutoCheck: false,
        enableBetaUpdates: false,
      ),
    ),
  );
  await _settle(tester);
  return harness;
}

Future<void> _settle(WidgetTester tester) async {
  await tester.pumpAndSettle();
  await tester.runAsync(() async {
    await Future.wait([
      for (final element in find.byType(Image).evaluate())
        precacheImage((element.widget as Image).image, element),
    ]);
  });
  await tester.pumpAndSettle();
}

Future<void> _dispose(
  WidgetTester tester,
  ApplicationTestHarness harness,
) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await harness.disposeControllerOnly();
  await tester.runAsync(
    () => harness.temporaryDirectory.delete(recursive: true),
  );
}

Future<void> _capture(WidgetTester tester, String name) async {
  final directory = Platform.environment['PLANNER_APPEARANCE_CAPTURE_DIR'];
  if (directory == null || directory.isEmpty) return;
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(_captureKey),
  );
  await tester.runAsync(() async {
    final image = await boundary.toImage();
    try {
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      final file = File('$directory/$name.png');
      await file.parent.create(recursive: true);
      await file.writeAsBytes(bytes!.buffer.asUint8List());
    } finally {
      image.dispose();
    }
  });
}

Future<void> _loadFonts() async {
  if (!Platform.isWindows) return;
  final win = Platform.environment['WINDIR'] ?? r'C:\Windows';
  var sdk = File(Platform.resolvedExecutable).parent;
  while (!Directory(
    '${sdk.path}/bin/cache/artifacts/material_fonts',
  ).existsSync()) {
    if (sdk.parent.path == sdk.path) {
      throw StateError('Flutter fonts not found');
    }
    sdk = sdk.parent;
  }
  for (final family in <String, List<String>>{
    'Georgia': ['$win/Fonts/georgia.ttf', '$win/Fonts/georgiab.ttf'],
    'Segoe UI': [
      '$win/Fonts/segoeui.ttf',
      '$win/Fonts/seguisb.ttf',
      '$win/Fonts/segoeuib.ttf',
    ],
    'Roboto': [
      '${sdk.path}/bin/cache/artifacts/material_fonts/roboto-regular.ttf',
      '${sdk.path}/bin/cache/artifacts/material_fonts/roboto-bold.ttf',
    ],
    'MaterialIcons': [
      '${sdk.path}/bin/cache/artifacts/material_fonts/materialicons-regular.otf',
    ],
  }.entries) {
    final loader = FontLoader(family.key);
    for (final path in family.value) {
      loader.addFont(File(path).readAsBytes().then(ByteData.sublistView));
    }
    await loader.load();
  }
}
