import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:bdo_craft_planner_flutter/app/app.dart';
import 'package:bdo_craft_planner_flutter/app/window/window_host_service.dart';
import 'package:bdo_craft_planner_flutter/domain/models/craft_mode.dart';
import 'package:bdo_craft_planner_flutter/features/appearance/planner_size_title_action.dart';
import 'package:bdo_craft_planner_flutter/features/opportunities/opportunities_controller.dart';
import 'package:bdo_craft_planner_flutter/features/opportunities/opportunities_workspace.dart';
import 'package:bdo_craft_planner_flutter/visual/visual.dart';
import 'package:bdo_map_core/bdo_map_core.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/application_test_harness.dart';

const _captureKey = ValueKey('opportunities-zoom-shell-capture');
const _trigger = ValueKey('opportunities-size-title-action');
const _popup = ValueKey('opportunities-appearance-popover');
const _slider = ValueKey('opportunities-appearance-zoom-slider');
const _reset = ValueKey('opportunities-appearance-zoom-reset');
const _transform = ValueKey('opportunities-content-transform');

void main() {
  setUpAll(_loadFonts);
  for (final background in [
    'sakura-night-garden',
    'illuminated-ledger',
    'greenhouse',
  ]) {
    for (final textScale in [1.0, 2.0]) {
      testWidgets(
        '$background Opportunities title zoom retains shell at ${textScale * 100}% text',
        (tester) async {
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
          await tester.runAsync(BdoResourceMapLoader.loadBundled);
          await tester.runAsync(BdoWorkerEconomicsLoader.loadBundled);
          final window = _Window();
          final previousShadows = debugDisableShadows;
          debugDisableShadows = false;
          try {
            final planner = harness.bundle.controller;
            await tester.pumpWidget(
              RepaintBoundary(
                key: _captureKey,
                child: BdoCraftPlannerApp(
                  applicationFuture: Future.value(harness.bundle),
                  marketGateway: const EmptyMarketGateway(),
                  windowHost: window,
                  enableOpportunityAutoCheck: false,
                  enableBetaUpdates: false,
                ),
              ),
            );
            await _settle(tester);
            final plannerTrigger = tester.getRect(
              find.byKey(PlannerSizeTitleAction.triggerKey),
            );
            final plannerDocument = planner.documentSnapshot;
            final plannerScale = planner.plannerContentScale.value;
            final plan = planner.active.plan.value;
            await tester.tap(_tab('opportunities'));
            await tester.pump();
            final workspace = find.byType(OpportunitiesWorkspace);
            final OpportunitiesController controller = tester
                .widget<OpportunitiesWorkspace>(workspace)
                .controller;
            await _completeIo(tester, controller.ready);
            controller.cancel();
            controller.change((preferences) {
              preferences.mode = CraftMode.cooking;
              preferences.readyOnly = false;
              preferences.demandOnly = false;
              preferences.profitableOnly = false;
            }, assemble: true);
            controller.cancel();
            await _completeIo(tester, controller.calculationSettled);
            await _completeIo(tester, controller.flush());
            await _settle(tester);
            final element = tester.element(workspace);
            final panes = tester.element(
              find.byKey(const ValueKey('opportunities-panes')),
            );
            final header = tester.getRect(
              find.byKey(const ValueKey('opportunities-header')),
            );
            final navigation = tester.getRect(find.text('Crafting'));
            final quotes = controller.quotes;
            final firstCard = _cards().first;
            final firstKey = tester.widget(firstCard).key!;
            final rowBefore = _firstRowCount(tester);
            final sidebar = find.byKey(const ValueKey('opportunities-sidebar'));
            final sidebarBounds = sidebar.evaluate().isEmpty
                ? null
                : tester.getRect(sidebar);
            expect(tester.getRect(find.byKey(_trigger)), plannerTrigger);
            await _capture(tester, '$background-text${textScale.toInt()}-100');

            await tester.tap(find.byKey(_trigger));
            await _settle(tester);
            final popup = tester.getRect(find.byKey(_popup));
            final trigger = tester.getRect(find.byKey(_trigger));
            expect(popup.right, closeTo(trigger.right, 10));
            expect(popup.top, greaterThanOrEqualTo(trigger.bottom));
            expect(popup.height, lessThan(360));
            expect(popup.right, lessThanOrEqualTo(1566));
            final slider = tester.widget<AppSlider>(find.byKey(_slider));
            final chosen = slider.max / 100;
            if (background == 'sakura-night-garden' && textScale == 1) {
              await _previewFrames(tester, controller, chosen);
            }
            if (slider.onChanged != null) {
              await tester.tapAt(
                tester.getRect(find.byKey(_slider)).centerRight -
                    const Offset(12, 0),
              );
              await _settle(tester);
              expect(controller.contentScale.value, closeTo(chosen, .00001));
              expect(controller.preferences.contentScale, chosen);
            }
            final transform = tester.widget<Transform>(find.byKey(_transform));
            await _capture(tester, '$background-text${textScale.toInt()}-zoom');
            expect(transform.transform.storage[0], closeTo(chosen, .00001));
            expect(tester.element(workspace), same(element));
            expect(
              tester.element(find.byKey(const ValueKey('opportunities-panes'))),
              same(panes),
            );
            expect(controller.quotes, same(quotes));
            expect(_firstRowCount(tester), rowBefore);
            expect(find.byKey(firstKey), findsOneWidget);
            expect(
              tester.getRect(
                find.byKey(const ValueKey('opportunities-header')),
              ),
              header,
            );
            expect(
              tester.getRect(find.text('Crafting')),
              navigation,
              reason:
                  'notice=${controller.notice}; saveError=${controller.saveError}; summary=${controller.summaryStatus.loading}; detail=${controller.detailStatus.loading}',
            );
            if (sidebarBounds != null) {
              expect(tester.getRect(sidebar), sidebarBounds);
            }
            expect(planner.documentSnapshot, same(plannerDocument));
            expect(planner.plannerContentScale.value, plannerScale);
            expect(planner.active.plan.value, same(plan));
            await _capture(tester, '$background-text${textScale.toInt()}-zoom');
            await tester.sendKeyEvent(LogicalKeyboardKey.escape);
            await _settle(tester);
            expect(find.byKey(_popup), findsNothing);

            // Card hit-testing must follow the scaled artwork, not its old box.
            await tester.tap(find.byKey(firstKey));
            await _settle(tester);
            final name = (firstKey as ValueKey<String>).value.substring(
              'craft-card:'.length,
            );
            expect(
              find.byKey(ValueKey('craft-inline-details:$name')),
              findsOneWidget,
            );
            expect(find.byType(Dialog), findsNothing);
            final cardHeader = find.byKey(ValueKey('craft-expand:$name'));
            await tester.ensureVisible(cardHeader);
            await _settle(tester);
            await tester.tapAt(
              tester.getCenter(cardHeader),
              buttons: kSecondaryMouseButton,
            );
            // The real item menu resolves bundled map-source availability
            // before opening. Let that file/isolate work finish in this test.
            for (
              var attempt = 0;
              attempt < 1000 && find.text('View recipe').evaluate().isEmpty;
              attempt++
            ) {
              await tester.runAsync(
                () => Future<void>.delayed(const Duration(milliseconds: 10)),
              );
              await tester.pump();
            }
            await _settle(tester);
            await tester.tap(find.text('View recipe'));
            await _settle(tester);
            expect(find.byType(Dialog), findsOneWidget);
            await tester.sendKeyEvent(LogicalKeyboardKey.escape);
            await _settle(tester);
            expect(find.byType(Dialog), findsNothing);
            await tester.tap(_tab('planner'));
            await _settle(tester);
            expect(
              find.byKey(PlannerSizeTitleAction.triggerKey),
              findsOneWidget,
            );
            expect(planner.plannerContentScale.value, plannerScale);
            await tester.tap(_tab('opportunities'));
            await _settle(tester);
            expect(tester.element(workspace), same(element));
            expect(controller.contentScale.value, chosen);
            await tester.tap(find.byKey(_trigger));
            await _settle(tester);
            if (chosen > 1) {
              await tester.tap(find.byKey(_reset));
              await _settle(tester);
            }
            expect(controller.contentScale.value, 1);
            expect(controller.preferences.contentScale, 1);
            expect(_firstRowCount(tester), rowBefore);
            if (textScale == 1) {
              await tester.sendKeyEvent(LogicalKeyboardKey.escape);
              await _settle(tester);
              for (final section in ['exchanges', 'best-use']) {
                controller.change((preferences) {
                  preferences.section = section;
                  preferences.bestUseItem = 'Aloe';
                });
                controller.cancel();
                await _completeIo(tester, controller.calculationSettled);
                await _completeIo(tester, controller.flush());
                await _settle(tester);
                if (section == 'best-use') {
                  expect(controller.visibleBestUseQuotes, isNotEmpty);
                } else {
                  expect(controller.exchangeQuotes, isNotEmpty);
                }
                final beforeNavigation = tester.getRect(find.text('Crafting'));
                await tester.tap(find.byKey(_trigger));
                await _settle(tester);
                final sectionSlider = tester.widget<AppSlider>(
                  find.byKey(_slider),
                );
                if (sectionSlider.onChanged != null) {
                  await tester.tapAt(
                    tester.getRect(find.byKey(_slider)).centerRight -
                        const Offset(12, 0),
                  );
                  await _settle(tester);
                }
                expect(tester.getRect(find.text('Crafting')), beforeNavigation);
                expect(tester.element(workspace), same(element));
                expect(
                  tester.element(
                    find.byKey(const ValueKey('opportunities-panes')),
                  ),
                  same(panes),
                );
                expect(
                  tester
                      .widget<Transform>(find.byKey(_transform))
                      .transform
                      .storage[0],
                  closeTo(sectionSlider.max / 100, .00001),
                );
                await _capture(tester, '$background-$section-zoom');
                await tester.sendKeyEvent(LogicalKeyboardKey.escape);
                await _settle(tester);
                controller.commitContentScale(1);
                await _settle(tester);
                expect(tester.takeException(), isNull);
              }
            }
            expect(tester.takeException(), isNull);
          } finally {
            if (window.beforeClose != null) {
              await _completeIo(tester, window.beforeClose!());
            }
            await tester.pumpWidget(const SizedBox.shrink());
            await _completeIo(tester, harness.dispose());
            debugDisableShadows = previousShadows;
          }
        },
      );
    }
  }
}

Finder _cards() => find.byWidgetPredicate(
  (widget) =>
      widget.key is ValueKey<String> &&
      (widget.key! as ValueKey<String>).value.startsWith('craft-card:'),
);

int _firstRowCount(WidgetTester tester) {
  final cards = _cards().evaluate().toList();
  // Expanded cards stack independently; cached first children need not share
  // a top edge after scrolling to an action. Count the occupied columns.
  return cards
      .map((card) => tester.getTopLeft(find.byKey(card.widget.key!)).dx.round())
      .toSet()
      .length;
}

Finder _tab(String name) => find.byKey(ValueKey('top-workspace-tab-$name'));

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

Future<void> _completeIo(WidgetTester tester, Future<void> work) async {
  var complete = false;
  Object? failure;
  unawaited(
    work.then(
      (_) => complete = true,
      onError: (Object error) {
        failure = error;
        complete = true;
      },
    ),
  );
  for (var i = 0; i < 1000 && !complete; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump();
  }
  expect(complete, isTrue);
  if (failure != null) throw failure!;
}

Future<void> _capture(WidgetTester tester, String name) async {
  final directory = Platform.environment['OPPORTUNITIES_ZOOM_CAPTURE_DIR'];
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

Future<void> _previewFrames(
  WidgetTester tester,
  OpportunitiesController controller,
  double maximum,
) async {
  final quotes = controller.quotes;
  final saved = controller.preferences.contentScale;
  final builds = <String, int>{};
  final samples = <int>[];
  final previousRebuild = debugOnRebuildDirtyWidget;
  debugOnRebuildDirtyWidget = (element, _) {
    final name = element.widget.runtimeType.toString();
    if (name == 'OpportunitiesWorkspace' ||
        name == '_OpportunityBody' ||
        name == '_OpportunitiesContent') {
      builds.update(name, (count) => count + 1, ifAbsent: () => 1);
    }
  };
  try {
    for (var i = 0; i < 40; i++) {
      final watch = Stopwatch()..start();
      controller.previewContentScale(1 + (maximum - 1) * (i % 25) / 24);
      await tester.pump(const Duration(milliseconds: 16));
      watch.stop();
      samples.add(watch.elapsedMicroseconds);
      expect(controller.preferences.contentScale, saved);
      expect(controller.quotes, same(quotes));
    }
  } finally {
    debugOnRebuildDirtyWidget = previousRebuild;
    controller.previewContentScale(saved);
    await tester.pump();
  }
  expect(builds, isEmpty);
  final directory = Platform.environment['OPPORTUNITIES_ZOOM_CAPTURE_DIR'];
  if (directory == null) return;
  final sorted = [...samples]..sort();
  await tester.runAsync(() async {
    await File('$directory/zoom-preview-performance.json').writeAsString(
      const JsonEncoder.withIndent('  ').convert({
        'productionQuotes': quotes.length,
        'previewUpdates': 40,
        'maximum': maximum,
        'featureBuilds': builds,
        'headlessPumpMedianUs': sorted[20],
        'headlessPumpP95Us': sorted[38],
        'rawMicroseconds': samples,
        'savedDuringPreview': false,
        'quotesRetained': true,
        'limitation':
            'Headless debug widget/layout diagnostic with reduced motion; not native FPS or release GPU frame time.',
      }),
    );
  });
}

class _Window extends WindowHostService {
  Future<void> Function()? beforeClose;
  @override
  void installCloseRequestHandler(Future<void> Function()? handler) =>
      beforeClose = handler;
  @override
  void removeCloseRequestHandler() => beforeClose = null;
  @override
  Future<bool> isMaximized() async => false;
  @override
  Future<void> setBottomInset(double inset) async {}
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
  for (final family in <String, List<String>>{
    'Segoe UI': [
      '$windows/Fonts/segoeui.ttf',
      '$windows/Fonts/seguisb.ttf',
      '$windows/Fonts/segoeuib.ttf',
    ],
    'Georgia': ['$windows/Fonts/georgia.ttf', '$windows/Fonts/georgiab.ttf'],
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
