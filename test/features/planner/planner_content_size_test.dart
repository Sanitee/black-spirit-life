import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:bdo_craft_planner_flutter/app/app.dart';
import 'package:bdo_craft_planner_flutter/domain/formatting/planner_formatters.dart';
import 'package:bdo_craft_planner_flutter/features/planner/planner.dart';
import 'package:bdo_craft_planner_flutter/features/planner/planner_content_fit.dart';
import 'package:bdo_craft_planner_flutter/features/planner/planner_content_viewport.dart';
import 'package:bdo_craft_planner_flutter/features/planner/planner_quantity_layout.dart';
import 'package:bdo_craft_planner_flutter/features/planner/planner_shared.dart';
import 'package:bdo_craft_planner_flutter/features/shell/shell_models.dart';
import 'package:bdo_craft_planner_flutter/visual/visual.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/application_test_harness.dart';

const _captureKey = ValueKey('planner-content-size-capture');
const _themes = [
  SakuraNightGardenSpec.theme,
  IlluminatedLedgerSpec.theme,
  StandardSpec.theme,
];
const _sizes = [Size(1200, 752), Size(1566, 991)];
final _successfulMatrixCases = <Map<String, Object>>[];
var _stateRetentionPassed = false;

void main() {
  setUpAll(_loadFonts);
  tearDownAll(_writeValidationReport);
  for (final spec in _themes) {
    for (final size in _sizes) {
      for (final textScale in [1.0, 1.25, 1.5, 2.0]) {
        for (final target in [
          'Adaptation Draught',
          if (spec.isSakuraNightGarden && size.width == 1566 && textScale == 1)
            'Harmony Draught',
        ]) {
          testWidgets(
            'live Planner size keeps ${spec.id} layout at $size and ${textScale}x OS text ($target)',
            (tester) async {
              final harness = await _openPlanner(
                tester,
                spec: spec,
                size: size,
                textScale: textScale,
                target: target,
              );
              try {
                final controller = harness.bundle.controller;
                final mode = controller.active;
                final plannerElement = find
                    .byType(PlannerView)
                    .evaluate()
                    .single;
                final columnsState = tester.state(
                  find.byType(PlannerPlanColumns),
                );
                final sidebar = _paintRect(
                  tester,
                  find.byKey(WorkspaceShellKeys.sidebar),
                );
                final viewport = _paintRect(
                  tester,
                  find.byKey(const ValueKey('planner-content-viewport')),
                );
                final before = _layoutSignature(tester);
                final qualityWidthsBefore = _qualityWidths(tester);
                _expectRealQuantities(tester);
                if (Platform.environment['PLANNER_CONTENT_SIZE_PROBE'] == '1') {
                  for (var percentage = 101; percentage <= 125; percentage++) {
                    controller.previewPlannerContentScale(percentage / 100);
                    await tester.pump();
                    final probe = _layoutSignature(tester);
                    final changed = before.entries.where(
                      (entry) =>
                          probe.containsKey(entry.key) &&
                          jsonEncode(probe[entry.key]) !=
                              jsonEncode(entry.value),
                    );
                    if (changed.isNotEmpty) {
                      debugPrint(
                        'First reflow ${spec.id} $size text$textScale: $percentage%, ${changed.map((entry) => entry.key).join(', ')}',
                      );
                      break;
                    }
                  }
                  controller.previewPlannerContentScale(1);
                  await tester.pump();
                }
                final plan = mode.plan.value;
                final state = mode.state.value;
                final expanded = mode.expandedSteps.value;
                var planNotifications = 0;
                var stateNotifications = 0;
                void onPlan() => planNotifications++;
                void onState() => stateNotifications++;
                mode.plan.addListener(onPlan);
                mode.state.addListener(onState);
                final name =
                    '${target == 'Harmony Draught' ? 'harmony-' : ''}${spec.id}-${size.width.toInt()}x${size.height.toInt()}-text${(textScale * 100).round()}';
                await _capture(tester, '$name-100');
                controller.previewPlannerContentScale(1.25);
                await _settle(tester);
                final maximum = plannerContentMaximumScale(
                  size: viewport.size,
                  denseLayout: spec.usesDenseSplitLayout,
                  textScale: textScale,
                  queueBreakpoints: plannerQueueFitBreakpoints(
                    tester.element(find.byType(PlannerContentViewport)),
                    mode,
                  ),
                );
                final transform = tester.widget<Transform>(
                  find.byKey(const ValueKey('planner-content-transform')),
                );
                if (target == 'Harmony Draught') {
                  expect(
                    maximum,
                    greaterThan(1),
                    reason:
                        'The user screenshot recipe must have useful enlargement.',
                  );
                }
                expect(
                  transform.transform.entry(0, 0),
                  closeTo(maximum, .00001),
                );
                expect(
                  transform.transform.entry(1, 1),
                  closeTo(maximum, .00001),
                );
                expect(
                  _paintRect(tester, find.byKey(WorkspaceShellKeys.sidebar)),
                  sidebar,
                );
                expect(
                  _paintRect(
                    tester,
                    find.byKey(const ValueKey('planner-content-viewport')),
                  ),
                  viewport,
                );
                expect(
                  find.byType(PlannerView).evaluate().single,
                  same(plannerElement),
                );
                expect(
                  tester.state(find.byType(PlannerPlanColumns)),
                  same(columnsState),
                );
                expect(mode.plan.value, same(plan));
                expect(mode.state.value, same(state));
                expect(mode.expandedSteps.value, same(expanded));
                expect(planNotifications, 0);
                expect(stateNotifications, 0);
                final after = _layoutSignature(tester);
                for (final entry in before.entries) {
                  // A shorter viewport may lazily release lower list rows.
                  if (after.containsKey(entry.key)) {
                    expect(
                      after[entry.key],
                      entry.value,
                      reason:
                          '${entry.key} changed layout at ${maximum * 100}%; '
                          'quality widths before $qualityWidthsBefore, after ${_qualityWidths(tester)}',
                    );
                  }
                }
                _expectColumns(tester);
                _expectRealQuantities(tester);
                expect(tester.takeException(), isNull);
                await _capture(tester, '$name-${(maximum * 100).round()}');
                await tester.runAsync(
                  () => _writeMetrics(name, {
                    'maximum': maximum,
                    'before': before,
                    'after': after,
                  }),
                );
                _successfulMatrixCases.add({
                  'recipe': target,
                  'theme': spec.id,
                  'width': size.width,
                  'height': size.height,
                  'osTextScale': textScale,
                  'requestedScale': 1.25,
                  'effectiveMaximum': maximum,
                  'baselineCapture': '$name-100.png',
                  'maximumCapture': '$name-${(maximum * 100).round()}.png',
                });
                mode.plan.removeListener(onPlan);
                mode.state.removeListener(onState);
              } finally {
                await _dispose(tester, harness);
              }
            },
          );
        }
      }
    }
  }

  testWidgets(
    'live Planner zoom retains focused inventory draft, lazy lists and scroll positions',
    (tester) async {
      final harness = await _openPlanner(
        tester,
        spec: SakuraNightGardenSpec.theme,
        size: const Size(1566, 991),
      );
      try {
        final controller = harness.bundle.controller;
        final mode = controller.active;
        final firstVisible = tester.widget<PlannerNeedQuantities>(
          find.byType(PlannerNeedQuantities).first,
        );
        final firstNeed = mode.plan.value.missing.firstWhere(
          (row) => row.key == firstVisible.stableId,
        );
        final actions = find.byKey(
          PlannerActionKeys.row('P18', firstNeed.name),
        );
        final input = find.descendant(
          of: actions,
          matching: find.byType(TextField),
        );
        await tester.enterText(input, '123');
        await tester.pump();
        final field = tester.widget<TextField>(input);
        final textController = field.controller!;
        final focus = field.focusNode!;
        expect(focus.hasFocus, isTrue);
        final queueFinder = find.byKey(
          const PageStorageKey<String>('planner-craft-queue'),
        );
        final needFinder = find.byKey(
          const PageStorageKey<String>('planner-need-first'),
        );
        final queue = tester.widget<ListView>(queueFinder).controller!;
        final need = tester.widget<ListView>(needFinder).controller!;
        queue.jumpTo(48);
        need.jumpTo(36);
        await tester.pump();
        final plan = mode.plan.value;
        final document = jsonEncode(controller.documentSnapshot.toJson());
        final expanded = mode.expandedSteps.value;
        var plannerBuilds = 0;
        debugOnRebuildDirtyWidget = (element, builtOnce) {
          if (element.widget is PlannerView) plannerBuilds++;
        };
        try {
          for (var i = 0; i <= 25; i++) {
            controller.previewPlannerContentScale(1 + i / 100);
            await tester.pump();
          }
        } finally {
          debugOnRebuildDirtyWidget = null;
        }
        expect(plannerBuilds, 0);
        expect(
          tester
              .widget<Transform>(
                find.byKey(const ValueKey('planner-content-transform')),
              )
              .transform
              .entry(0, 0),
          greaterThan(1),
          reason:
              'This fixture must exercise real painted zoom, not only a clamped notifier.',
        );
        expect(mode.plan.value, same(plan));
        expect(jsonEncode(controller.documentSnapshot.toJson()), document);
        expect(mode.expandedSteps.value, same(expanded));
        expect(tester.widget<ListView>(queueFinder).controller, same(queue));
        expect(tester.widget<ListView>(needFinder).controller, same(need));
        expect(queue.offset, closeTo(48, .01));
        expect(need.offset, closeTo(36, .01));
        expect(
          tester.widget<TextField>(input).controller,
          same(textController),
        );
        expect(textController.text, '123');
        expect(focus.hasFocus, isTrue);
        expect(
          find.byType(PlannerNeedQuantities).evaluate().length,
          lessThan(mode.plan.value.missing.length),
        );
        expect(tester.takeException(), isNull);

        // A real tap at the painted, scaled Add target must still hit that item.
        need.jumpTo(0);
        await tester.pump();
        final add = find.byKey(PlannerActionKeys.row('P19', firstNeed.name));
        await _capture(tester, 'focused-draft-before-add');
        expect(
          _paintRect(
            tester,
            find.byKey(const ValueKey('planner-content-viewport')),
          ).contains(_paintRect(tester, add).center),
          isTrue,
        );
        await tester.tapAt(_paintRect(tester, add).center);
        await tester.pumpAndSettle();
        expect(
          textController.text,
          '0',
          reason:
              'Add painted bounds ${_paintRect(tester, add)}; hit path '
              '${tester.hitTestOnBinding(_paintRect(tester, add).center).path.map((entry) => entry.target.runtimeType).toList()}',
        );
        expect(mode.plan.value, isNot(same(plan)));
        expect(tester.takeException(), isNull);
        _stateRetentionPassed = true;
      } finally {
        debugOnRebuildDirtyWidget = null;
        await _dispose(tester, harness);
      }
    },
  );
}

Future<ApplicationTestHarness> _openPlanner(
  WidgetTester tester, {
  required ThemeSpec spec,
  required Size size,
  double textScale = 1,
  String target = 'Adaptation Draught',
}) async {
  configureApplicationTestSurface(tester, size, textScaleFactor: textScale);
  final original = (await tester.runAsync(
    () => ApplicationTestHarness.create(
      backgroundId: spec.isStandard ? 'greenhouse' : spec.id,
    ),
  ))!;
  final harness = original.rebindControllerInCurrentZone();
  await tester.runAsync(original.disposeControllerOnly);
  final mode = harness.bundle.controller.active;
  expect(mode.selectTarget(target), isTrue);
  mode.commitAmount('100');
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
  expect(tester.takeException(), isNull);
  _expectColumns(tester);
  return harness;
}

Map<String, Object> _layoutSignature(WidgetTester tester) {
  final result = <String, Object>{};
  final command = find.byWidgetPredicate(
    (widget) => widget.runtimeType.toString() == '_PlannerCommandBand',
  );
  final commandLayout = find
      .descendant(of: command, matching: find.byType(LayoutBuilder))
      .first;
  final commandChildren = <Element>[];
  commandLayout.evaluate().single.visitChildren(commandChildren.add);
  result['command'] = commandChildren.single.widget.runtimeType.toString();
  final header = tester.widget<SectionHeader>(
    find.byWidgetPredicate(
      (widget) => widget is SectionHeader && widget.title == 'Need First',
    ),
  );
  result['need-header-inline'] = header.trailing != null;
  for (final element in find.byType(PlannerNeedQuantities).evaluate()) {
    final widget = element.widget as PlannerNeedQuantities;
    final layout = find
        .descendant(
          of: find.byWidget(widget),
          matching: find.byType(LayoutBuilder),
        )
        .first;
    final children = <Element>[];
    layout.evaluate().single.visitChildren(children.add);
    result['need:${widget.stableId}:add'] = children.single.widget.runtimeType
        .toString();
    final fieldRows = <double>[];
    for (final label in ['Need', 'Have', 'Missing']) {
      final field = find.byKey(
        ValueKey('planner-need-quantity:${widget.stableId}:$label'),
      );
      Element? inlineGroup;
      field.evaluate().single.visitAncestorElements((ancestor) {
        if (ancestor.widget is Wrap) {
          inlineGroup = ancestor;
          return false;
        }
        return true;
      });
      final box = inlineGroup!.findRenderObject()! as RenderBox;
      fieldRows.add(box.localToGlobal(box.size.center(Offset.zero)).dy);
    }
    result['need:${widget.stableId}:value-lines'] = [
      for (var i = 1; i < fieldRows.length; i++)
        (fieldRows[i] - fieldRows[i - 1]).abs() < .1,
    ];
  }
  for (final element in find.byType(PlannerIngredientRowLayout).evaluate()) {
    final widget = element.widget as PlannerIngredientRowLayout;
    final layout = find
        .descendant(
          of: find.byWidget(widget),
          matching: find.byType(LayoutBuilder),
        )
        .first;
    final children = <Element>[];
    layout.evaluate().single.visitChildren(children.add);
    result['ingredient:${widget.total.key}:total'] = children
        .single
        .widget
        .runtimeType
        .toString();
  }
  for (final element in find.byType(PlannerIngredientIdentity).evaluate()) {
    final widget = element.widget as PlannerIngredientIdentity;
    if (widget.quality == null) continue;
    final columns = find.descendant(
      of: find.byWidget(widget),
      matching: find.byType(Column),
    );
    final firstColumn = tester.widget<Column>(columns.first);
    final name = widget.name.key.toString();
    result['quality:$name:inline'] = firstColumn.children.length == 1;
  }
  for (final element in find.byType(PlannerCraftQuantities).evaluate()) {
    final step = (element.widget as PlannerCraftQuantities).step.name;
    final positions = <double>[
      for (final label in ['Craft', 'Results', 'Need'])
        _paintRect(
          tester,
          find.byKey(ValueKey('planner-craft-field:$step:$label')),
        ).top,
    ];
    result['summary:$step:lines'] = [
      for (var i = 1; i < positions.length; i++)
        (positions[i] - positions[i - 1]).abs() < .1,
    ];
  }
  return result;
}

void _expectColumns(WidgetTester tester) {
  final queue = _paintRect(
    tester,
    find.byKey(const PageStorageKey<String>('planner-craft-queue')),
  );
  final need = _paintRect(
    tester,
    find.byKey(const PageStorageKey<String>('planner-need-first')),
  );
  expect(queue.right, lessThan(need.left));
  expect(queue.top, lessThan(need.bottom));
  expect(need.top, lessThan(queue.bottom));
}

Map<String, double> _qualityWidths(WidgetTester tester) => {
  for (final element in find.byType(PlannerIngredientIdentity).evaluate())
    if ((element.widget as PlannerIngredientIdentity).quality != null)
      (element.widget as PlannerIngredientIdentity).name.key.toString():
          (element.findRenderObject()! as RenderBox).size.width,
};

void _expectRealQuantities(WidgetTester tester) {
  final step = tester
      .widget<PlannerCraftQuantities>(find.byType(PlannerCraftQuantities).first)
      .step;
  expect(step.count, greaterThan(0));
  expect(step.produced, greaterThan(0));
  expect(step.demand, greaterThan(0));
  for (final field in [
    ('Craft', step.count),
    ('Results', step.produced),
    ('Need', step.demand),
  ]) {
    expect(
      tester
          .widget<Text>(
            find.byKey(
              ValueKey('planner-craft-quantity:${step.name}:${field.$1}'),
            ),
          )
          .data,
      formatQuantity(field.$2),
    );
  }
  final need = tester.widget<PlannerNeedQuantities>(
    find.byType(PlannerNeedQuantities).first,
  );
  expect(need.need, greaterThan(0));
  for (final field in [
    ('Need', need.need),
    ('Have', need.have),
    ('Missing', need.missing),
  ]) {
    expect(
      tester
          .widget<Text>(
            find.byKey(
              ValueKey('planner-need-quantity:${need.stableId}:${field.$1}'),
            ),
          )
          .data,
      formatQuantity(field.$2),
    );
  }
}

Rect _paintRect(WidgetTester tester, Finder finder) {
  final box = tester.renderObject<RenderBox>(finder);
  return Rect.fromPoints(
    box.localToGlobal(Offset.zero),
    box.localToGlobal(box.size.bottomRight(Offset.zero)),
  );
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
  final directory = Platform.environment['PLANNER_CONTENT_SIZE_CAPTURE_DIR'];
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

Future<void> _writeMetrics(String name, Map<String, Object> metrics) async {
  final directory = Platform.environment['PLANNER_CONTENT_SIZE_CAPTURE_DIR'];
  if (directory == null || directory.isEmpty) return;
  final file = File('$directory/$name.json');
  await file.writeAsString(const JsonEncoder.withIndent('  ').convert(metrics));
}

Future<void> _writeValidationReport() async {
  final directory = Platform.environment['PLANNER_CONTENT_SIZE_CAPTURE_DIR'];
  if (directory == null || directory.isEmpty) return;
  final report = {
    'complete': _successfulMatrixCases.length == 25 && _stateRetentionPassed,
    'passedLayoutCases': _successfulMatrixCases.length,
    'expectedLayoutCases': 25,
    'stateFocusScrollLazyHitTestPassed': _stateRetentionPassed,
    'renderMethod':
        'Headless Flutter using production application, full bundled catalog and original game assets.',
    'nativeDesktopRun': false,
    'nativeDesktopBoundary':
        'No desktop or browser control, app launch or native timing validation was performed.',
    'preservedGroups': [
      'Command composition',
      'Two columns',
      'Need header controls',
      'Need Add controls',
      'Need/Have/Missing grouping',
      'Craft/Results/Need grouping',
      'Ingredient total position',
      'Ingredient quality control position',
    ],
    'cases': _successfulMatrixCases,
  };
  final file = File('$directory/planner-content-size-validation.json');
  await file.parent.create(recursive: true);
  await file.writeAsString(const JsonEncoder.withIndent('  ').convert(report));
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
