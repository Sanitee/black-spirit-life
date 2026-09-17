import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:bdo_craft_planner_flutter/app/app.dart';
import 'package:bdo_craft_planner_flutter/app/state/planner_application_controller.dart';
import 'package:bdo_craft_planner_flutter/domain/formatting/planner_formatters.dart';
import 'package:bdo_craft_planner_flutter/domain/models/craft_mode.dart';
import 'package:bdo_craft_planner_flutter/domain/planner/planner_models.dart';
import 'package:bdo_craft_planner_flutter/domain/state/planner_state_json_codec.dart';
import 'package:bdo_craft_planner_flutter/domain/state/state_copy.dart';
import 'package:bdo_craft_planner_flutter/features/planner/planner.dart';
import 'package:bdo_craft_planner_flutter/features/planner/planner_quantity_layout.dart';
import 'package:bdo_craft_planner_flutter/features/shared/recipe_variant_selector.dart';
import 'package:bdo_craft_planner_flutter/shared/overlays/anchored_popover.dart';
import 'package:bdo_craft_planner_flutter/visual/visual.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/application_test_harness.dart';
import 'planner_test_fixture.dart';

const _removedToggleKey = ValueKey('planner-readability-preview-toggle');
const _themes = <ThemeSpec>[
  SakuraNightGardenSpec.theme,
  IlluminatedLedgerSpec.theme,
  StandardSpec.theme,
];

Finder _summary(String name) =>
    find.byKey(ValueKey('planner-step-summary:$name'));

Finder _needQuantity(String stableId, String label) =>
    find.byKey(ValueKey('planner-need-quantity:$stableId:$label'));

Finder _quantity(String recipe, String ingredient, {bool perCraft = false}) =>
    find.byKey(
      ValueKey(
        'planner-ingredient-${perCraft ? 'per-craft' : 'batch'}-quantity:'
        '$recipe:$ingredient',
      ),
    );

void main() {
  testWidgets(
    'quantity layout is default across modes, themes, navigation, and reload without extra saves',
    (tester) async {
      await setPlannerTestSize(tester, const Size(1500, 940));
      final semantics = tester.ensureSemantics();
      final harness = PlannerTestHarness();
      addTearDown(harness.controller.dispose);
      var saves = 0;
      final application = PlannerApplicationController(
        catalog: harness.controller.catalog,
        initialState: harness.controller.documentSnapshot,
        saveState: (state) async {
          saves += 1;
          return state;
        },
        saveDebounce: Duration.zero,
      );
      addTearDown(application.dispose);
      const codec = PlannerStateJsonCodec();
      for (final mode in CraftMode.values) {
        application.switchMode(mode);
        await application.flush();
        final originalDocument = codec.encode(application.documentSnapshot);
        final originalPlan = jsonEncode(application.active.plan.value.toJson());
        final originalSaves = saves;
        if (mode == CraftMode.alchemy) expect(originalSaves, 0);
        final step = application.active.plan.value.steps.first;
        final ingredient = step.ingredients.single.original;
        for (final spec in _themes) {
          await tester.pumpWidget(
            _host(harness, application: application, spec: spec),
          );
          await tester.pumpAndSettle();
          _expectNoTrialControls();
          _expectNoBroadRedesign();
          _expectMatchingQuantityBadges(
            tester,
            _quantity(step.name, ingredient, perCraft: true),
            _quantity(step.name, ingredient),
            spec: spec,
          );
          _expectNeedQuantities(
            tester,
            application.active.plan.value.missing.single,
            spec: spec,
          );
          _expectSummary(
            tester,
            step,
            processing: mode == CraftMode.processing,
          );
          await application.flush();
          expect(codec.encode(application.documentSnapshot), originalDocument);
          expect(
            jsonEncode(application.active.plan.value.toJson()),
            originalPlan,
          );
          expect(saves, originalSaves);
        }

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpWidget(_host(harness, application: application));
        await tester.pumpAndSettle();
        _expectNoTrialControls();
        _expectMatchingQuantityBadges(
          tester,
          _quantity(step.name, ingredient, perCraft: true),
          _quantity(step.name, ingredient),
        );

        var reloadSaves = 0;
        final reloaded = PlannerApplicationController(
          catalog: application.catalog,
          initialState: codec.decode(originalDocument),
          saveState: (state) async {
            reloadSaves += 1;
            return state;
          },
          saveDebounce: Duration.zero,
        );
        addTearDown(reloaded.dispose);
        await tester.pumpWidget(_host(harness, application: reloaded));
        await tester.pumpAndSettle();
        _expectNoTrialControls();
        _expectMatchingQuantityBadges(
          tester,
          _quantity(step.name, ingredient, perCraft: true),
          _quantity(step.name, ingredient),
        );
        _expectNeedQuantities(
          tester,
          reloaded.active.plan.value.missing.single,
        );
        await reloaded.flush();
        expect(jsonEncode(reloaded.active.plan.value.toJson()), originalPlan);
        expect(codec.encode(reloaded.documentSnapshot), originalDocument);
        expect(reloadSaves, 0);
      }

      await tester.pumpWidget(harness.bonusHost());
      await tester.pumpAndSettle();
      _expectNoTrialControls();
      expect(find.byType(PlannerNeedQuantities), findsNothing);
      expect(
        tester
            .widget<Text>(
              _quantity('Intermediate Reagent', 'Sunrise Herb', perCraft: true),
            )
            .style
            ?.fontSize,
        13,
      );
      _expectOriginalTotalColumn(
        tester,
        _quantity('Intermediate Reagent', 'Sunrise Herb'),
      );
      expect(
        find.byKey(const ValueKey('planner-step-summary:Intermediate Reagent')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      semantics.dispose();
    },
  );

  for (final spec in _themes) {
    for (final size in const [Size(916, 674), Size(1216, 862)]) {
      for (final scale in [1.0, 1.5, 2.0]) {
        testWidgets(
          'default quantities ${spec.id} at $size and ${scale}x text keep long rows readable',
          (tester) async {
            await setPlannerTestSize(tester, const Size(1500, 940));
            final harness = PlannerTestHarness(includeLightstoneNeed: true);
            addTearDown(harness.controller.dispose);
            harness.controller.active.commitAmount('13709');
            await tester.pumpWidget(
              _host(harness, spec: spec, size: size, scale: scale),
            );
            await tester.pumpAndSettle();
            const recipe = 'Purified Lightstone of Flora';
            const ingredient = 'Imperfect Lightstone of Flora';
            _expectSummary(
              tester,
              harness.controller.active.plan.value.steps.single,
            );
            final formula = _quantity(recipe, ingredient, perCraft: true);
            final total = _quantity(recipe, ingredient);
            expect(tester.widget<Text>(formula).data, 'x4');
            expect(tester.widget<Text>(formula).style?.fontSize, 16);
            expect(
              tester.widget<Text>(formula).style?.fontWeight,
              FontWeight.w600,
            );
            expect(tester.widget<Text>(total).data, '54.836');
            _expectMatchingQuantityBadges(
              tester,
              formula,
              total,
              spec: spec,
              scale: scale,
            );
            _expectNeedQuantities(
              tester,
              harness.controller.active.plan.value.missing.single,
              spec: spec,
            );
            _expectNoBroadRedesign();
            expect(
              tester.getRect(formula).overlaps(tester.getRect(total)),
              isFalse,
            );
            expect(find.byType(Scrollbar), findsNothing);
            expect(find.byType(RawScrollbar), findsNothing);
            expect(tester.takeException(), isNull);
          },
        );
      }
    }
  }

  for (final mode in CraftMode.values) {
    testWidgets(
      'default ${mode.name} quantities follow target and owned changes',
      (tester) async {
        await setPlannerTestSize(tester, const Size(1500, 940));
        final harness = PlannerTestHarness(activeMode: mode);
        addTearDown(harness.controller.dispose);
        await tester.pumpWidget(_host(harness));
        await tester.pumpAndSettle();
        _expectNoTrialControls();
        final recipe = switch (mode) {
          CraftMode.alchemy => 'Intermediate Reagent',
          CraftMode.cooking => 'Beer',
          CraftMode.processing => 'Wheat Flour',
        };
        final ingredient = mode == CraftMode.alchemy ? 'Sunrise Herb' : 'Wheat';
        final perCraft = switch (mode) {
          CraftMode.alchemy => 'x2',
          CraftMode.cooking => 'x5',
          CraftMode.processing => 'x1',
        };
        for (final want in ['10', '13709']) {
          final input = find.descendant(
            of: find.byKey(PlannerActionKeys.p02),
            matching: find.byType(EditableText),
          );
          await tester.enterText(input, want);
          await tester.testTextInput.receiveAction(TextInputAction.done);
          await tester.pumpAndSettle();
          final step = harness.controller.active.plan.value.steps.firstWhere(
            (step) => step.name == recipe,
          );
          _expectSummary(
            tester,
            step,
            processing: mode == CraftMode.processing,
          );
          expect(
            tester
                .widget<Text>(_quantity(recipe, ingredient, perCraft: true))
                .data,
            perCraft,
          );
          expect(
            tester.widget<Text>(_quantity(recipe, ingredient)).data,
            formatQuantity(step.ingredients.single.need),
          );
          _expectNeedQuantities(
            tester,
            harness.controller.active.plan.value.missing.single,
          );
        }
        harness.controller.active.updateState(
          (state) => state.copyWith(
            ignoreIngredientInventory: false,
            inventory: {ingredient: 100000},
          ),
          immediate: true,
        );
        await tester.pumpAndSettle();
        final step = harness.controller.active.plan.value.steps.firstWhere(
          (step) => step.name == recipe,
        );
        expect(step.ingredients.single.missing, 0);
        expect(
          tester.widget<Text>(_quantity(recipe, ingredient)).data,
          formatQuantity(step.ingredients.single.need),
        );
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'default Need First reflects Add and retains drafts across responsive layouts',
    (tester) async {
      await setPlannerTestSize(tester, const Size(1500, 940));
      final harness = PlannerTestHarness(includeLightstoneNeed: true);
      addTearDown(harness.controller.dispose);
      const ingredient = 'Imperfect Lightstone of Flora';
      await tester.pumpWidget(_host(harness, size: const Size(916, 674)));
      await tester.pumpAndSettle();
      _expectNoTrialControls();
      _expectNeedQuantities(
        tester,
        harness.controller.active.plan.value.missing.single,
      );
      final ownedField = find.descendant(
        of: find.byKey(PlannerActionKeys.row('P18', ingredient)),
        matching: find.byType(TextField),
      );
      await tester.ensureVisible(ownedField);
      await tester.enterText(ownedField, '12');
      final quantities = find.byType(PlannerNeedQuantities);
      expect(
        tester.getRect(ownedField).top,
        greaterThan(tester.getRect(quantities).bottom),
      );
      await tester.pumpWidget(_host(harness));
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(ownedField).controller!.text, '12');
      expect(
        harness.controller.active.state.value.inventory[ingredient],
        isNull,
      );
      await tester.pumpWidget(_host(harness, size: const Size(916, 674)));
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(ownedField).controller!.text, '12');
      expect(
        tester.getRect(ownedField).top,
        greaterThan(tester.getRect(quantities).bottom),
      );
      await _tap(tester, find.byKey(PlannerActionKeys.row('P19', ingredient)));
      expect(harness.controller.active.state.value.inventory[ingredient], 12);
      expect(
        harness.controller.active.state.value.ignoreIngredientInventory,
        isFalse,
      );
      final afterAdd = harness.controller.active.plan.value.missing.single;
      expect(afterAdd.need, 40);
      expect(afterAdd.have, 12);
      expect(afterAdd.missing, 28);
      _expectNeedQuantities(tester, afterAdd);
      expect(tester.widget<TextField>(ownedField).controller!.text, '0');
      await tester.pumpWidget(_host(harness));
      await tester.pumpAndSettle();
      _expectNeedQuantities(tester, afterAdd);
      expect(harness.controller.active.state.value.inventory[ingredient], 12);
      await tester.ensureVisible(ownedField);
      await tester.enterText(ownedField, '28');
      await _tap(tester, find.byKey(PlannerActionKeys.row('P19', ingredient)));
      expect(harness.controller.active.state.value.inventory[ingredient], 40);
      expect(harness.controller.active.plan.value.missing, isEmpty);
      expect(find.byType(PlannerNeedQuantities), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'default quantities preserve the original mass-processing summary',
    (tester) async {
      await setPlannerTestSize(tester, const Size(1500, 940));
      final harness = PlannerTestHarness(activeMode: CraftMode.processing);
      addTearDown(harness.controller.dispose);
      harness.controller.active.updateState(
        (state) => state.copyWith(
          want: 13709,
          useMassProcessing: true,
          processingMastery: 600,
        ),
        immediate: true,
      );
      await tester.pumpWidget(_host(harness));
      await tester.pumpAndSettle();
      final step = harness.controller.active.plan.value.steps.single;
      expect(step.count, 13709);
      expect(step.batchSize, 40);
      expect(step.batchCount, 343);
      _expectSummary(tester, step, processing: true);
      expect(
        tester.widget<Text>(_summary(step.name)).data,
        'Craft 13.709 | Mass batches 343 x40 | Results in 13.709 | Need 13.709',
      );
      _expectNoBroadRedesign();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'default quantities preserve substitute, quality, copy, map, and completion actions',
    (tester) async {
      await setPlannerTestSize(tester, const Size(1500, 940));
      final harness = PlannerTestHarness(
        resolveMapLookup: (name) async => PlannerMapLookupAvailability(
          materialName: name,
          hasManualGathering: true,
          manualResourceId: 'sunrise-herb',
          manualLocationCount: 1,
          hasWorkerNodes: false,
        ),
      );
      addTearDown(harness.controller.dispose);
      await tester.pumpWidget(
        _host(harness, spec: SakuraNightGardenSpec.theme),
      );
      await tester.pumpAndSettle();
      final mapRegion = find.byKey(
        PlannerActionKeys.mapLookupRegion(
          'queue:Intermediate Reagent:Sunrise Herb',
        ),
      );
      await tester.ensureVisible(mapRegion);
      await tester.tap(
        mapRegion,
        buttons: kSecondaryMouseButton,
        kind: PointerDeviceKind.mouse,
      );
      await tester.pumpAndSettle();
      await _tap(
        tester,
        find.byKey(
          PlannerActionKeys.mapLookupAction(
            'queue:Intermediate Reagent:Sunrise Herb',
            PlannerMapLookupSource.manualGathering.name,
          ),
        ),
      );
      expect(harness.mapLookupRequests.single.materialName, 'Sunrise Herb');
      await _tap(
        tester,
        find.byKey(PlannerActionKeys.row('P10', 'Intermediate Reagent')),
      );
      expect(harness.copied, ['Intermediate Reagent']);
      final expansion = find.byKey(
        PlannerActionKeys.row('P09', 'Intermediate Reagent'),
      );
      await _tap(tester, expansion);
      expect(_quantity('Intermediate Reagent', 'Sunrise Herb'), findsNothing);
      await _tap(tester, expansion);
      await _tap(
        tester,
        find.byKey(
          PlannerActionKeys.row('P12', 'step:Intermediate Reagent:Wild Herbs'),
        ),
      );
      await _tap(
        tester,
        find.byKey(PlannerActionKeys.row('P13', 'Silver Azalea')),
      );
      expect(
        harness.controller.active.state.value.substituteChoices.values,
        contains('Silver Azalea'),
      );
      expect(
        tester
            .widget<Text>(
              _quantity('Intermediate Reagent', 'Sunrise Herb', perCraft: true),
            )
            .data,
        'x4',
      );
      expect(
        tester
            .widget<Text>(_quantity('Intermediate Reagent', 'Sunrise Herb'))
            .data,
        '40',
      );
      final quality = find.descendant(
        of: find.byKey(
          PlannerActionKeys.row('P14', 'Intermediate Reagent:Sunrise Herb'),
        ),
        matching: find.byType(InkWell),
      );
      await _tap(tester, quality.last);
      expect(
        harness.controller.active.state.value.ingredientGrades.values,
        contains('special'),
      );
      expect(
        tester
            .widget<Text>(
              _quantity('Intermediate Reagent', 'Sunrise Herb', perCraft: true),
            )
            .data,
        'x1',
      );
      expect(
        tester
            .widget<Text>(_quantity('Intermediate Reagent', 'Sunrise Herb'))
            .data,
        '8',
      );
      await _tap(tester, find.byKey(PlannerActionKeys.p15));
      expect(harness.marketRequest, isNotNull);
      expect(
        harness.controller.active.state.value.market.prices['Sunrise Herb'],
        1200,
      );
      await _tap(
        tester,
        find.byKey(PlannerActionKeys.row('P08', 'Clear Liquid Reagent')),
      );
      expect(
        harness.controller.active.state.value.completedSteps,
        contains('Clear Liquid Reagent'),
      );
      expect(harness.controller.active.plan.value.steps, isEmpty);
      await _tap(tester, find.byKey(PlannerActionKeys.p07));
      expect(harness.controller.active.state.value.completedSteps, isEmpty);
      expect(_summary('Intermediate Reagent'), findsOneWidget);
      expect(_summary('Clear Liquid Reagent'), findsOneWidget);
      _expectNeedQuantities(
        tester,
        harness.controller.active.plan.value.missing.single,
        spec: SakuraNightGardenSpec.theme,
      );
      _expectNoTrialControls();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('default quantities follow recipe route and batch choices', (
    tester,
  ) async {
    await setPlannerTestSize(tester, const Size(1500, 940));
    final harness = PlannerTestHarness(includeRecipeVariants: true);
    addTearDown(harness.controller.dispose);
    await tester.pumpWidget(_host(harness, spec: IlluminatedLedgerSpec.theme));
    await tester.pumpAndSettle();
    await _tap(
      tester,
      find.byKey(
        RecipeVariantSelector.choiceKey('Clear Liquid Reagent', 'herb-route'),
      ),
    );
    await _tap(
      tester,
      find.byKey(
        RecipeVariantSelector.batchChoiceKey('Clear Liquid Reagent', 10),
      ),
    );
    expect(
      harness.controller.active.selectedRecipeVariantId('Clear Liquid Reagent'),
      'herb-route-10x',
    );
    final expansion = find.byKey(
      PlannerActionKeys.row('P09', 'Clear Liquid Reagent'),
    );
    if (_quantity('Clear Liquid Reagent', 'Silver Azalea').evaluate().isEmpty) {
      await _tap(tester, expansion);
    }
    expect(
      tester
          .widget<Text>(
            _quantity('Clear Liquid Reagent', 'Silver Azalea', perCraft: true),
          )
          .data,
      'x40',
    );
    expect(
      tester
          .widget<Text>(_quantity('Clear Liquid Reagent', 'Silver Azalea'))
          .data,
      '40',
    );
    _expectSummary(tester, harness.controller.active.plan.value.steps.single);
    expect(tester.takeException(), isNull);
  });

  const capture = bool.fromEnvironment('CAPTURE_PLANNER_QUANTITIES');
  if (capture) {
    setUpAll(_loadCaptureFonts);
    for (final spec in _themes) {
      for (final size in const [Size(1200, 752), Size(1500, 940)]) {
        testWidgets(
          'capture default quantities ${spec.id} $size full real-catalog workspace',
          (tester) async {
            configureApplicationTestSurface(tester, size);
            final original = (await tester.runAsync(
              () => ApplicationTestHarness.create(
                backgroundId: spec.isStandard ? 'greenhouse' : spec.id,
              ),
            ))!;
            final harness = original.rebindControllerInCurrentZone();
            await tester.runAsync(original.disposeControllerOnly);
            final controller = harness.bundle.controller;
            controller.active.selectTarget('Clear Liquid Reagent');
            controller.active.commitAmount('34272');
            const root = ValueKey('planner-quantity-capture-root');
            try {
              await tester.pumpWidget(
                RepaintBoundary(
                  key: root,
                  child: BdoCraftPlannerApp(
                    enableOpportunityAutoCheck: false,
                    applicationFuture: Future.value(harness.bundle),
                    marketGateway: const EmptyMarketGateway(),
                  ),
                ),
              );
              await tester.pumpAndSettle();
              for (final element in find.byType(Image).evaluate()) {
                await tester.runAsync(
                  () => precacheImage((element.widget as Image).image, element),
                );
              }
              await tester.pumpAndSettle();
              expect(tester.takeException(), isNull);
              expect(find.byType(PlannerNeedQuantities), findsWidgets);
              expect(find.byType(PlannerQuantityBadge), findsWidgets);
              _expectNoTrialControls();
              _expectNoBroadRedesign();
              _expectVisibleNeedRowsUseThreeColumns(tester);
              for (final element in find.byWidgetPredicate((widget) {
                final key = widget.key;
                return widget is Text &&
                    key is ValueKey<String> &&
                    key.value.startsWith('planner-ingredient-batch-quantity:');
              }).evaluate()) {
                final key = element.widget.key! as ValueKey<String>;
                final stableId = key.value.substring(
                  'planner-ingredient-batch-quantity:'.length,
                );
                _expectMatchingQuantityBadges(
                  tester,
                  find.byKey(
                    ValueKey('planner-ingredient-per-craft-quantity:$stableId'),
                  ),
                  find.byKey(key),
                  spec: spec,
                  expectInline: true,
                );
              }
              final boundary = tester.renderObject<RenderRepaintBoundary>(
                find.byKey(root),
              );
              await tester.runAsync(() async {
                final image = await boundary.toImage(pixelRatio: 1);
                try {
                  final bytes = await image.toByteData(
                    format: ui.ImageByteFormat.png,
                  );
                  const directory = String.fromEnvironment(
                    'PLANNER_QUANTITY_CAPTURE_DIRECTORY',
                    defaultValue: 'tmp/planner-quantity-default',
                  );
                  final file = File(
                    '$directory/${spec.id}-${size.width.toInt()}x${size.height.toInt()}.png',
                  );
                  await file.parent.create(recursive: true);
                  await file.writeAsBytes(
                    bytes!.buffer.asUint8List(),
                    flush: true,
                  );
                } finally {
                  image.dispose();
                }
              });
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
}

Widget _host(
  PlannerTestHarness harness, {
  PlannerApplicationController? application,
  ThemeSpec spec = StandardSpec.theme,
  Size size = const Size(1216, 862),
  double scale = 1,
}) => AppOverlayCoordinatorHost(
  child: MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: spec.materialTheme(),
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(
        context,
      ).copyWith(textScaler: TextScaler.linear(scale)),
      child: child!,
    ),
    home: ThemeSpecScope(
      spec: spec,
      child: Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: SizedBox.fromSize(
            size: size,
            child: PlannerView(
              controller: (application ?? harness.controller).active,
              externalActions: harness.actions,
            ),
          ),
        ),
      ),
    ),
  ),
);

Future<void> _tap(WidgetTester tester, Finder target) async {
  await tester.ensureVisible(target);
  await tester.tap(target);
  await tester.pumpAndSettle();
}

void _expectSummary(
  WidgetTester tester,
  PlanStep step, {
  bool processing = false,
}) {
  final expected = processing && step.batchSize == 1
      ? '${formatQuantity(step.count)} ${step.count == 1 ? 'batch' : 'batches'} · '
            'Makes ${formatQuantity(step.produced)} · '
            'Need ${formatQuantity(step.demand)}'
      : step.batchSize > 1
      ? 'Craft ${formatQuantity(step.count)} | '
            'Mass batches ${formatQuantity(step.batchCount)} x${step.batchSize} | '
            'Results in ${formatQuantity(step.produced)} | '
            'Need ${formatQuantity(step.demand)}'
      : 'Craft ${formatQuantity(step.count)} | '
            'Results in ${formatQuantity(step.produced)} | '
            'Need ${formatQuantity(step.demand)}';
  expect(tester.widget<Text>(_summary(step.name)).data, expected);
}

void _expectNoBroadRedesign() {
  expect(
    find.byWidgetPredicate(
      (widget) =>
          widget.runtimeType.toString() == 'PlannerPreviewStepSummary' ||
          widget.runtimeType.toString() == 'PlannerPreviewIngredientBand',
    ),
    findsNothing,
  );
  expect(find.text('Per craft'), findsNothing);
}

void _expectNoTrialControls() {
  expect(find.byKey(_removedToggleKey), findsNothing);
  expect(find.text('Try quantity B'), findsNothing);
  expect(find.text('Quantity B · Use original'), findsNothing);
  expect(
    find.bySemanticsLabel(
      RegExp('Try Planner quantity layout B|Use original Planner layout'),
    ),
    findsNothing,
  );
}

void _expectOriginalTotalColumn(WidgetTester tester, Finder total) {
  final fitted = find.ancestor(of: total, matching: find.byType(FittedBox));
  expect(fitted, findsOneWidget);
  expect(tester.widget<FittedBox>(fitted).fit, BoxFit.scaleDown);
  expect(tester.widget<FittedBox>(fitted).alignment, Alignment.centerRight);
  expect(
    find.ancestor(
      of: total,
      matching: find.byWidgetPredicate(
        (widget) => widget is SizedBox && widget.width == 86,
      ),
    ),
    findsOneWidget,
  );
}

void _expectMatchingQuantityBadges(
  WidgetTester tester,
  Finder formula,
  Finder total, {
  ThemeSpec spec = StandardSpec.theme,
  double scale = 1,
  bool expectInline = false,
}) {
  final formulaStyle = tester.widget<Text>(formula).style!;
  expect(tester.widget<Text>(total).style, formulaStyle);
  expect(formulaStyle.fontSize, 16);
  expect(formulaStyle.fontWeight, FontWeight.w600);
  expect(formulaStyle.fontStyle, FontStyle.normal);
  expect(formulaStyle.fontFeatures, const [FontFeature.tabularFigures()]);
  expect(formulaStyle.color, spec.palette.text);
  if (expectInline) {
    final identityBounds = tester.getRect(
      find.ancestor(
        of: formula,
        matching: find.byType(PlannerIngredientIdentity),
      ),
    );
    final totalBounds = tester.getRect(total);
    expect(totalBounds.top, lessThan(identityBounds.bottom));
    expect(totalBounds.bottom, greaterThan(identityBounds.top));
  }
  BoxDecoration? firstDecoration;
  EdgeInsetsGeometry? firstPadding;
  for (final quantity in [formula, total]) {
    final badge = find.ancestor(
      of: quantity,
      matching: find.byType(PlannerQuantityBadge),
    );
    expect(badge, findsOneWidget);
    final decoration =
        tester
                .widget<DecoratedBox>(
                  find.descendant(
                    of: badge,
                    matching: find.byType(DecoratedBox),
                  ),
                )
                .decoration
            as BoxDecoration;
    final padding = tester
        .widget<Padding>(
          find.descendant(of: badge, matching: find.byType(Padding)),
        )
        .padding;
    firstDecoration ??= decoration;
    firstPadding ??= padding;
    expect(decoration, firstDecoration);
    expect(padding, firstPadding);
    expect(decoration.color, spec.palette.text.withValues(alpha: 0.09));
    expect(decoration.borderRadius, BorderRadius.circular(3));
    expect(padding, const EdgeInsets.symmetric(horizontal: 6, vertical: 2));
    expect(
      find.ancestor(of: quantity, matching: find.byType(FittedBox)),
      findsNothing,
    );
    final paragraph = tester.renderObject<RenderParagraph>(quantity);
    expect(paragraph.textScaler.scale(16), closeTo(16 * scale, 0.01));
    final origin = paragraph.localToGlobal(Offset.zero);
    final horizontal = paragraph.localToGlobal(const Offset(10, 0));
    final vertical = paragraph.localToGlobal(const Offset(0, 10));
    expect((horizontal - origin).distance, closeTo(10, 0.01));
    expect((vertical - origin).distance, closeTo(10, 0.01));
    final textBounds = tester.getRect(quantity);
    final badgeBounds = tester.getRect(badge);
    expect(badgeBounds.width, closeTo(textBounds.width + 12, 0.01));
    expect(badgeBounds.height, closeTo(textBounds.height + 4, 0.01));
  }
}

void _expectVisibleNeedRowsUseThreeColumns(WidgetTester tester) {
  final viewport = Offset.zero & tester.view.physicalSize;
  var visibleRows = 0;
  for (final widget in tester.widgetList<PlannerNeedQuantities>(
    find.byType(PlannerNeedQuantities),
  )) {
    final root = find.byKey(widget.key!);
    if (!tester.getRect(root).overlaps(viewport)) continue;
    visibleRows += 1;
    Rect? firstLabel;
    Rect? firstValue;
    Rect? previousValue;
    for (final label in ['Need', 'Have', 'Missing']) {
      final labelBounds = tester.getRect(
        find.descendant(of: root, matching: find.text(label)),
      );
      final valueBounds = tester.getRect(_needQuantity(widget.stableId, label));
      firstLabel ??= labelBounds;
      firstValue ??= valueBounds;
      expect(
        labelBounds.top,
        closeTo(firstLabel.top, 0.01),
        reason: '${widget.stableId}: quantity labels must share one row',
      );
      expect(
        valueBounds.top,
        closeTo(firstValue.top, 0.01),
        reason: '${widget.stableId}: quantity values must share one row',
      );
      expect(valueBounds.top, greaterThan(labelBounds.bottom));
      if (previousValue != null) {
        expect(valueBounds.left, greaterThan(previousValue.right));
      }
      previousValue = valueBounds;
    }
  }
  expect(visibleRows, greaterThan(0));
}

void _expectNeedQuantities(
  WidgetTester tester,
  MissingMaterial row, {
  ThemeSpec spec = StandardSpec.theme,
}) {
  final root = find.byKey(ValueKey('planner-need-quantities:${row.key}'));
  expect(root, findsOneWidget);
  final rootBounds = tester.getRect(root);
  final bounds = <Rect>[];
  for (final entry in {
    'Need': row.need,
    'Have': row.have,
    'Missing': row.missing,
  }.entries) {
    final finder = _needQuantity(row.key, entry.key);
    final text = tester.widget<Text>(finder);
    expect(text.data, formatQuantity(entry.value));
    expect(text.style?.fontSize, entry.key == 'Need' ? 16 : 15);
    expect(
      text.style?.fontWeight,
      entry.key == 'Need' ? FontWeight.w700 : FontWeight.w500,
    );
    expect(
      text.style?.color,
      entry.key == 'Need' ? spec.palette.text : spec.palette.textMuted,
    );
    final label = tester.widget<Text>(
      find.descendant(of: root, matching: find.text(entry.key)),
    );
    expect(label.style?.fontSize, 12.5);
    final valueBounds = tester.getRect(finder);
    expect(valueBounds.left, greaterThanOrEqualTo(rootBounds.left));
    expect(valueBounds.right, lessThanOrEqualTo(rootBounds.right + 0.01));
    expect(valueBounds.top, greaterThanOrEqualTo(rootBounds.top));
    expect(valueBounds.bottom, lessThanOrEqualTo(rootBounds.bottom + 0.01));
    for (final previous in bounds) {
      expect(previous.overlaps(valueBounds), isFalse);
    }
    bounds.add(valueBounds);
  }
}

Future<void> _loadCaptureFonts() async {
  final windowsRoot = Platform.environment['WINDIR'] ?? r'C:\Windows';
  var flutterRoot = File(Platform.resolvedExecutable).parent;
  while (!Directory(
    '${flutterRoot.path}/bin/cache/artifacts/material_fonts',
  ).existsSync()) {
    if (flutterRoot.parent.path == flutterRoot.path) {
      throw StateError('Flutter font directory not found.');
    }
    flutterRoot = flutterRoot.parent;
  }
  final materialFonts =
      '${flutterRoot.path}/bin/cache/artifacts/material_fonts';
  for (final entry in {
    'Segoe UI': [
      '$windowsRoot/Fonts/segoeui.ttf',
      '$windowsRoot/Fonts/seguisb.ttf',
      '$windowsRoot/Fonts/segoeuib.ttf',
    ],
    'Georgia': [
      '$windowsRoot/Fonts/georgia.ttf',
      '$windowsRoot/Fonts/georgiab.ttf',
      '$windowsRoot/Fonts/georgiai.ttf',
    ],
    'Roboto': [
      '$materialFonts/roboto-regular.ttf',
      '$materialFonts/roboto-bold.ttf',
    ],
    'MaterialIcons': ['$materialFonts/materialicons-regular.otf'],
  }.entries) {
    final loader = FontLoader(entry.key);
    for (final path in entry.value) {
      loader.addFont(File(path).readAsBytes().then(ByteData.sublistView));
    }
    await loader.load();
  }
}
