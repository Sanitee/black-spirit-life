import 'dart:io';
import 'dart:ui' as ui;

import 'package:bdo_craft_planner_flutter/app/app.dart';
import 'package:bdo_craft_planner_flutter/domain/models/craft_mode.dart';
import 'package:bdo_craft_planner_flutter/features/planner/planner.dart';
import 'package:bdo_craft_planner_flutter/features/planner/planner_map_menu_presentation.dart';
import 'package:bdo_craft_planner_flutter/features/resource_map/resource_map_workspace.dart';
import 'package:bdo_craft_planner_flutter/visual/visual.dart';
import 'package:bdo_map_core/bdo_map_core.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../../support/application_test_harness.dart';

void main() {
  setUpAll(() async {
    // The existing actual-app capture helper loads native Windows fonts.
    // This test has its own synthetic profile and never opens a desktop window.
    await _loadFonts();
    await BdoResourceMapLoader.loadBundled();
    await BdoWorkerEconomicsLoader.loadBundled();
    await LodgingDataLoader.loadBundled();
  });
  for (final spec in [
    SakuraNightGardenSpec.theme,
    StandardSpec.theme,
    IlluminatedLedgerSpec.theme,
  ]) {
    for (final scenario in [
      (const Size(1200, 752), 1.0),
      (const Size(960, 600), 1.0),
      (const Size(1200, 752), 2.0),
    ]) {
      final (size, scale) = scenario;
      testWidgets(
        'Open emblems actual app ${spec.id} ${size.width} text $scale',
        (tester) async {
          configureApplicationTestSurface(tester, size, textScaleFactor: scale);
          final original = (await tester.runAsync(
            () => ApplicationTestHarness.create(
              activeMode: CraftMode.cooking,
              backgroundId: spec.isStandard ? 'greenhouse' : spec.id,
            ),
          ))!;
          final harness = original.rebindControllerInCurrentZone();
          await tester.runAsync(original.disposeControllerOnly);
          final mode = harness.bundle.controller.active;
          expect(mode.selectTarget('Milk Tea'), isTrue);
          expect(mode.commitAmount('100'), isTrue);
          final client = MockClient(
            (_) async => http.Response('No test networking', 503),
          );
          try {
            await tester.pumpWidget(
              RepaintBoundary(
                key: const ValueKey('open-emblems-capture'),
                child: BdoCraftPlannerApp(
                  enableOpportunityAutoCheck: false,
                  applicationFuture: Future.value(harness.bundle),
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
            for (final (target, material) in [
              ('Milk Tea', 'Cooking Honey'),
              ('Beer', 'Sugar'),
            ]) {
              expect(mode.selectTarget(target), isTrue);
              expect(mode.commitAmount('100'), isTrue);
              await tester.pumpAndSettle();
              final state = mode.state.value.toJson();
              final row = find.byKey(
                PlannerActionKeys.mapLookupRegion('need:$material'),
              );
              final pane = find
                  .descendant(
                    of: find.byKey(
                      const PageStorageKey<String>('planner-need-first'),
                    ),
                    matching: find.byType(Scrollable),
                  )
                  .first;
              await tester.scrollUntilVisible(row, 120, scrollable: pane);
              await tester.ensureVisible(row);
              await tester.pumpAndSettle();
              await tester.tap(
                row,
                buttons: kSecondaryMouseButton,
                kind: PointerDeviceKind.mouse,
              );
              await tester.pump();
              await tester.runAsync(() => Future<void>.delayed(Duration.zero));
              await tester.pumpAndSettle();
              expect(find.byType(PlannerMapMenuLabel), findsWidgets);
              if (material == 'Sugar') {
                expect(find.text('Show NPC vendors'), findsOneWidget);
                expect(find.byType(PlannerMapActionEmblem), findsOneWidget);
                expect(
                  tester
                      .widget<PlannerMapActionEmblem>(
                        find.byType(PlannerMapActionEmblem),
                      )
                      .sourceRect,
                  const Rect.fromLTWH(141, 1, 34, 34),
                );
              }
              await _decodeImages(tester);
              for (final element
                  in find.byType(PlannerMapMenuLabel).evaluate()) {
                final rect = tester.getRect(find.byWidget(element.widget));
                expect(rect.left, greaterThanOrEqualTo(0));
                expect(rect.right, lessThanOrEqualTo(size.width));
                expect(
                  find.descendant(
                    of: find.byWidget(element.widget),
                    matching: find.byType(Tooltip),
                  ),
                  findsNothing,
                );
              }
              for (final element
                  in find
                      .descendant(
                        of: find.byType(PlannerMapMenuLabel),
                        matching: find.byType(RichText),
                      )
                      .evaluate()) {
                expect(
                  (element.renderObject! as RenderParagraph).didExceedMaxLines,
                  isFalse,
                );
              }
              await _capture(
                tester,
                '${spec.id}-${size.width.toInt()}-text$scale-${material.replaceAll(' ', '-')}',
              );
              final mouse = TestGesture(
                dispatcher: tester.sendEventToBinding,
                kind: PointerDeviceKind.mouse,
                pointer: 50,
                device: 50,
              );
              await mouse.addPointer(
                location: tester.getCenter(
                  find.byType(PlannerMapMenuLabel).first,
                ),
              );
              await tester.pump(const Duration(seconds: 2));
              expect(tester.takeException(), isNull);
              await mouse.removePointer();
              await tester.sendKeyEvent(LogicalKeyboardKey.escape);
              await tester.pumpAndSettle();
              expect(find.byType(PlannerMapMenuLabel), findsNothing);
              expect(mode.state.value.toJson(), state);
            }
            expect(tester.takeException(), isNull);
          } finally {
            await tester.pumpWidget(const SizedBox.shrink());
            await harness.disposeControllerOnly();
            client.close();
            await tester.runAsync(
              () => harness.temporaryDirectory.delete(recursive: true),
            );
          }
        },
      );
    }
  }
}

Future<void> _decodeImages(WidgetTester tester) async {
  await tester.runAsync(() async {
    for (final element in find.byType(Image).evaluate()) {
      Object? error;
      await precacheImage(
        (element.widget as Image).image,
        element,
        onError: (e, _) => error = e,
      );
      expect(error, isNull);
    }
  });
  await tester.pumpAndSettle();
}

Future<void> _capture(WidgetTester tester, String name) async {
  final output = Platform.environment['OPEN_EMBLEMS_CAPTURE_DIR'];
  if (output == null) return;
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(const ValueKey('open-emblems-capture')),
  );
  final rows = find
      .byType(PlannerMapMenuLabel)
      .evaluate()
      .map((element) => tester.getRect(find.byWidget(element.widget)));
  final menuBounds = rows.reduce((a, b) => a.expandToInclude(b)).inflate(18);
  await tester.runAsync(() async {
    await Directory(output).create(recursive: true);
    final image = await boundary.toImage();
    try {
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      await File('$output/$name.png').writeAsBytes(bytes!.buffer.asUint8List());
    } finally {
      image.dispose();
    }
    // Capture the same rendered layer at 2x for a legible detail view.
    // No mockup, recolouring, rescaling of controls or image compositing.
    final detail = await (boundary.debugLayer! as OffsetLayer).toImage(
      menuBounds,
      pixelRatio: 2,
    );
    try {
      final bytes = await detail.toByteData(format: ui.ImageByteFormat.png);
      await File(
        '$output/$name-detail.png',
      ).writeAsBytes(bytes!.buffer.asUint8List());
    } finally {
      detail.dispose();
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
