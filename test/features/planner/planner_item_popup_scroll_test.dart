import 'dart:io';
import 'dart:ui' as ui;

import 'package:bdo_craft_planner_flutter/app/app.dart';
import 'package:bdo_craft_planner_flutter/domain/models/craft_mode.dart';
import 'package:bdo_craft_planner_flutter/domain/state/state_copy.dart';
import 'package:bdo_craft_planner_flutter/features/planner/planner.dart';
import 'package:bdo_craft_planner_flutter/features/recipe_book/recipe_book_item_info_view.dart';
import 'package:bdo_craft_planner_flutter/visual/visual.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/application_test_harness.dart';

void main() {
  setUpAll(_loadFonts);
  for (final spec in [
    SakuraNightGardenSpec.theme,
    StandardSpec.theme,
    IlluminatedLedgerSpec.theme,
  ]) {
    for (final scenario in [
      (const Size(1200, 752), 1.0, 1.0),
      (const Size(1500, 940), 1.0, 1.25),
      (const Size(1200, 752), 2.0, 1.0),
    ]) {
      final (size, textScale, zoom) = scenario;
      testWidgets(
        'Planner popup ${spec.id} ${size.width} text $textScale zoom $zoom',
        (tester) async {
          configureApplicationTestSurface(
            tester,
            size,
            textScaleFactor: textScale,
          );
          final original = (await tester.runAsync(
            () => ApplicationTestHarness.create(
              backgroundId: spec.isStandard ? 'greenhouse' : spec.id,
              activeMode: CraftMode.alchemy,
            ),
          ))!;
          final harness = original.rebindControllerInCurrentZone();
          await tester.runAsync(original.disposeControllerOnly);
          harness.bundle.controller.previewPlannerContentScale(zoom);
          final mode = harness.bundle.controller.active;
          expect(mode.selectTarget("Tyrant's Blood"), isTrue);
          mode.updateState(
            (state) => state.copyWith(want: 100),
            immediate: true,
          );
          final beforeState = mode.state.value.toJson();
          try {
            await tester.pumpWidget(
              RepaintBoundary(
                key: const ValueKey('popup-scroll-capture'),
                child: BdoCraftPlannerApp(
                  enableOpportunityAutoCheck: false,
                  applicationFuture: Future.value(harness.bundle),
                  marketGateway: const EmptyMarketGateway(),
                ),
              ),
            );
            await tester.pumpAndSettle();
            final anchor = find.byKey(
              PlannerActionKeys.row(
                'P22',
                "Tyrant's Blood:Pure Powder Reagent",
              ),
            );
            final queue = find
                .descendant(
                  of: find.byKey(
                    const PageStorageKey<String>('planner-craft-queue'),
                  ),
                  matching: find.byType(Scrollable),
                )
                .first;
            final expand = find.byKey(
              PlannerActionKeys.row('P09', "Tyrant's Blood"),
            );
            if (anchor.evaluate().isEmpty) {
              await tester.scrollUntilVisible(expand, 180, scrollable: queue);
              await tester.pumpAndSettle();
              await tester.tap(expand);
              await tester.pumpAndSettle();
            }
            await tester.scrollUntilVisible(anchor, 180, scrollable: queue);
            expect(anchor, findsOneWidget);
            await tester.ensureVisible(anchor);
            await tester.pumpAndSettle();
            final background = tester
                .stateList<ScrollableState>(find.byType(Scrollable))
                .toList();
            final offsets = [
              for (final state in background) state.position.pixels,
            ];
            await tester.tap(anchor);
            await tester.pumpAndSettle();
            final popup = find.byType(ItemReferenceCard);
            expect(popup, findsOneWidget);
            final rect = tester.getRect(popup);
            expect(rect.top, greaterThanOrEqualTo(0));
            expect(rect.bottom, lessThanOrEqualTo(size.height));
            expect(rect.left, greaterThanOrEqualTo(0));
            expect(rect.right, lessThanOrEqualTo(size.width));
            final popupScroll = tester.state<ScrollableState>(
              find.descendant(of: popup, matching: find.byType(Scrollable)),
            );
            expect(popupScroll.position.maxScrollExtent, greaterThan(0));
            await _capture(
              tester,
              '${spec.id}-${size.width.toInt()}-text${textScale.toInt()}-top',
            );
            Future<void> wheel(Offset point, double delta) async {
              await tester.sendEventToBinding(
                PointerScrollEvent(
                  viewId: tester.view.viewId,
                  kind: PointerDeviceKind.mouse,
                  position: point,
                  scrollDelta: Offset(0, delta),
                ),
              );
              await tester.pumpAndSettle();
              expect(
                popup,
                findsOneWidget,
                reason: 'Scrolling the popup must not dismiss it.',
              );
              expect(
                [for (final state in background) state.position.pixels],
                offsets,
                reason: 'The popup must never scroll the underlying Planner.',
              );
            }

            await wheel(rect.center, 120);
            expect(popupScroll.position.pixels, greaterThan(0));
            final firstOffset = popupScroll.position.pixels;
            await wheel(rect.center, 120);
            expect(popupScroll.position.pixels, greaterThan(firstOffset));
            await wheel(rect.center, 100000);
            expect(
              popupScroll.position.pixels,
              popupScroll.position.maxScrollExtent,
            );
            final finalText = find
                .descendant(of: popup, matching: find.byType(Text))
                .last;
            expect(
              tester.getRect(finalText).bottom,
              lessThanOrEqualTo(rect.bottom),
            );
            await _capture(
              tester,
              '${spec.id}-${size.width.toInt()}-text${textScale.toInt()}-bottom',
            );
            await wheel(rect.center, 120);
            await wheel(rect.center, -100000);
            expect(popupScroll.position.pixels, 0);
            await wheel(rect.center, -120);
            await wheel(Offset(rect.left + 3, rect.center.dy), 120);
            await tester.drag(
              find.descendant(
                of: popup,
                matching: find.byType(SingleChildScrollView),
              ),
              const Offset(0, -120),
            );
            await tester.pumpAndSettle();
            expect(popup, findsOneWidget);
            expect(popupScroll.position.pixels, greaterThan(0));
            expect([
              for (final state in background) state.position.pixels,
            ], offsets);
            await tester.sendKeyEvent(LogicalKeyboardKey.escape);
            await tester.pumpAndSettle();
            expect(popup, findsNothing);
            // Closing a popup must not leave its owner locked or unable to scroll.
            final queuePosition = tester.state<ScrollableState>(queue).position;
            final beforeQueue = queuePosition.pixels;
            final delta = beforeQueue > 0 ? -120.0 : 120.0;
            await tester.sendEventToBinding(
              PointerScrollEvent(
                viewId: tester.view.viewId,
                kind: PointerDeviceKind.mouse,
                position: tester.getRect(queue).center,
                scrollDelta: Offset(0, delta),
              ),
            );
            await tester.pumpAndSettle();
            expect(queuePosition.pixels, isNot(beforeQueue));
            expect(mode.state.value.toJson(), beforeState);
            expect(tester.takeException(), isNull);
          } finally {
            await tester.pumpWidget(const SizedBox.shrink());
            await harness.disposeControllerOnly();
            await tester.runAsync(
              () => harness.temporaryDirectory.delete(recursive: true),
            );
          }
        },
      );
    }
  }
}

Future<void> _capture(WidgetTester tester, String name) async {
  final output = Platform.environment['POPUP_SCROLL_CAPTURE_DIR'];
  if (output == null || output.isEmpty) return;
  await tester.runAsync(() async {
    await Future.wait([
      for (final element in find.byType(Image).evaluate())
        precacheImage((element.widget as Image).image, element),
    ]);
  });
  await tester.pumpAndSettle();
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(const ValueKey('popup-scroll-capture')),
  );
  await tester.runAsync(() async {
    await Directory(output).create(recursive: true);
    final image = await boundary.toImage();
    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      await File('$output/$name.png').writeAsBytes(data!.buffer.asUint8List());
    } finally {
      image.dispose();
    }
  });
}

Future<void> _loadFonts() async {
  if (!Platform.isWindows) return;
  final windows = Platform.environment['WINDIR'] ?? r'C:\Windows';
  var sdk = File(Platform.resolvedExecutable).parent;
  while (!Directory(
    '${sdk.path}/bin/cache/artifacts/material_fonts',
  ).existsSync()) {
    if (sdk.parent.path == sdk.path) {
      throw StateError('Flutter fonts not found');
    }
    sdk = sdk.parent;
  }
  for (final family in {
    'Georgia': ['$windows/Fonts/georgia.ttf', '$windows/Fonts/georgiab.ttf'],
    'Segoe UI': [
      '$windows/Fonts/segoeui.ttf',
      '$windows/Fonts/seguisb.ttf',
      '$windows/Fonts/segoeuib.ttf',
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
    for (final file in family.value) {
      loader.addFont(File(file).readAsBytes().then(ByteData.sublistView));
    }
    await loader.load();
  }
}
