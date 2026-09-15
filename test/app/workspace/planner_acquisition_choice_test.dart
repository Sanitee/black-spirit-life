import 'dart:async';
import 'dart:io';

import 'package:bdo_craft_planner_flutter/app/state/planner_application_controller.dart';
import 'package:bdo_craft_planner_flutter/app/workspace/application_workspace.dart';
import 'package:bdo_craft_planner_flutter/domain/models/craft_mode.dart';
import 'package:bdo_craft_planner_flutter/domain/planner/reviewed_acquisition_choices.dart';
import 'package:bdo_craft_planner_flutter/domain/state/planner_state.dart';
import 'package:bdo_craft_planner_flutter/domain/state/planner_state_json_codec.dart';
import 'package:bdo_craft_planner_flutter/domain/state/state_copy.dart';
import 'package:bdo_craft_planner_flutter/features/planner/planner_keys.dart';
import 'package:bdo_craft_planner_flutter/visual/sakura_night_garden/sakura_spec.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/application_test_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(_loadFonts);

  test(
    'reviewed choices use exact Processing yields and preserve owned items',
    () async {
      final harness = await ApplicationTestHarness.create();
      addTearDown(harness.dispose);
      final cooking = harness.bundle.controller.modes[CraftMode.cooking]!;
      cooking.selectTarget('Oatmeal');
      cooking.commitAmount('10');
      cooking.updateState(
        (state) => state.copyWith(
          ignoreIngredientInventory: false,
          inventory: {'Cooking Honey': 3, 'Wild Beehive': 2},
          ingredientMeta: {
            'Cooking Honey': IngredientMetadata(
              marketId: '7702',
              sourceNote: 'My honey note',
            ),
          },
        ),
      );
      final before = cooking.plan.value.missing.firstWhere(
        (item) => item.name == 'Cooking Honey',
      );
      expect(before.need, 8);
      expect(before.have, 3);
      expect(before.missing, 5);
      expect(
        cooking.selectProcessingAcquisition('Cooking Honey', process: true),
        isTrue,
      );
      final step = cooking.plan.value.steps.firstWhere(
        (step) => step.name == 'Cooking Honey',
      );
      expect(step.net, 5);
      expect(step.count, 4);
      expect(step.produced, 6);
      expect(step.ingredients.single.name, 'Wild Beehive');
      expect(step.ingredients.single.need, 12);
      expect(
        cooking.plan.value.missing
            .firstWhere((item) => item.name == 'Wild Beehive')
            .missing,
        10,
      );
      expect(cooking.recipeDefinition('Cooking Honey')!.outputMinimum, 1);
      expect(cooking.recipeDefinition('Cooking Honey')!.outputMaximum, 2);
      expect(
        cooking.recipeDefinition('Cooking Honey')!.sourceNote,
        'My honey note',
      );
      expect(cooking.state.value.inventory, {
        'Cooking Honey': 3,
        'Wild Beehive': 2,
      });
      expect(cooking.optionalProcessingRecipe('Wheat Flour'), isNull);
      expect(
        cooking.selectProcessingAcquisition('Wheat Flour', process: false),
        isFalse,
      );
      expect(cooking.recipeDefinition('Wheat Flour')!.isCraftable, isTrue);

      final codec = const PlannerStateJsonCodec();
      final reopenedState = codec.decode(
        codec.encode(harness.bundle.controller.documentSnapshot),
      );
      final reopened = PlannerApplicationController(
        catalog: harness.bundle.catalog,
        initialState: reopenedState,
        saveState: (state) async => state,
      );
      addTearDown(reopened.dispose);
      final reopenedCooking = reopened.modes[CraftMode.cooking]!;
      expect(reopenedCooking.processesAcquisition('Cooking Honey'), isTrue);
      expect(
        reopenedCooking.plan.value.steps
            .firstWhere((item) => item.name == 'Cooking Honey')
            .produced,
        6,
      );
      expect(reopenedCooking.state.value.inventory['Cooking Honey'], 3);

      final progress = AfkCraftProgress(
        stepKey: 'honey-session',
        targetName: 'Oatmeal',
        targetAmount: 10,
        recipeName: 'Cooking Honey',
        planSignature: 'reviewed',
        totalAttempts: 4,
        attemptsPerRound: 2,
        completedAttempts: 2,
      );
      cooking.updateState(
        (state) => state.copyWith(
          completedSteps: {'Cooking Honey', 'Oatmeal'},
          recipeVariantChoices: {
            'Cooking Honey': 'stale',
            'Wheat Flour': 'keep',
          },
          afkCraftProgress: {'honey-session': progress},
        ),
      );
      final unchanged = cooking.state.value;
      cooking.selectProcessingAcquisition('Cooking Honey', process: true);
      expect(cooking.state.value, same(unchanged));
      cooking.selectProcessingAcquisition('Cooking Honey', process: false);
      expect(cooking.state.value.inventory, unchanged.inventory);
      expect(cooking.state.value.completedSteps, {'Oatmeal'});
      expect(cooking.state.value.recipeVariantChoices, {'Wheat Flour': 'keep'});
      expect(cooking.state.value.afkCraftProgress, isEmpty);
      expect(
        cooking.state.value.extensions.containsKey(
          processingAcquisitionChoicesKey,
        ),
        isFalse,
      );
      expect(cooking.recipeDefinition('Cooking Honey')!.isCraftable, isFalse);
      expect(
        cooking.recipeDefinition('Cooking Honey')!.sourceNote,
        'My honey note',
      );
    },
  );

  for (final mode in [CraftMode.cooking, CraftMode.alchemy]) {
    test(
      '${mode.label} Water choice is mode-local and uses bottled-water recipe',
      () async {
        final harness = await ApplicationTestHarness.create();
        addTearDown(harness.dispose);
        final controller = harness.bundle.controller.modes[mode]!;
        final target = harness.bundle.catalog
            .forMode(mode)
            .items
            .values
            .firstWhere(
              (recipe) =>
                  recipe.isCraftable &&
                  recipe.ingredients.any(
                    (ingredient) => ingredient.name == 'Purified Water',
                  ),
            );
        controller.selectTarget(target.name);
        controller.commitAmount('20');
        controller.updateState(
          (state) => state.copyWith(
            ignoreIngredientInventory: false,
            inventory: {'Purified Water': 1},
          ),
        );
        final missing = controller.plan.value.missing
            .firstWhere((item) => item.name == 'Purified Water')
            .missing;
        expect(
          controller.selectProcessingAcquisition(
            'Purified Water',
            process: true,
          ),
          isTrue,
        );
        final recipe = controller.recipeDefinition('Purified Water')!;
        expect(recipe.outputMinimum, 1);
        expect(recipe.outputMaximum, 4);
        expect(recipe.ingredients.single.quantity, 1);
        final step = controller.plan.value.steps.firstWhere(
          (item) => item.name == 'Purified Water',
        );
        expect(step.count, (missing / 2.5).ceil());
        expect(step.produced, step.count * 2.5);
        final other = mode == CraftMode.cooking
            ? CraftMode.alchemy
            : CraftMode.cooking;
        expect(
          harness.bundle.controller.modes[other]!.processesAcquisition(
            'Purified Water',
          ),
          isFalse,
        );
        controller.selectProcessingAcquisition(
          'Purified Water',
          process: false,
        );
        expect(
          controller.plan.value.steps.any(
            (item) => item.name == 'Purified Water',
          ),
          isFalse,
        );
        expect(controller.state.value.inventory['Purified Water'], 1);
      },
    );
  }

  testWidgets(
    'Need First arrow switches Honey to Processing and queue arrow switches back',
    (tester) async {
      configureApplicationTestSurface(tester, const Size(1500, 940));
      var harness = (await tester.runAsync(
        () => ApplicationTestHarness.create(
          activeMode: CraftMode.cooking,
          backgroundId: SakuraNightGardenSpec.backgroundId,
        ),
      ))!;
      await tester.runAsync(harness.disposeControllerOnly);
      harness = harness.rebindControllerInCurrentZone();
      final cooking = harness.bundle.controller.modes[CraftMode.cooking]!;
      cooking.selectTarget('Oatmeal');
      cooking.commitAmount('10');
      cooking.updateState(
        (state) => state.copyWith(
          ignoreIngredientInventory: false,
          inventory: {'Cooking Honey': 3},
        ),
      );
      await tester.pumpWidget(
        RepaintBoundary(
          key: const ValueKey('acquisition-capture'),
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            home: ApplicationWorkspace(
              bundle: harness.bundle,
              marketGateway: const EmptyMarketGateway(),
              enableOpportunityAutoCheck: false,
              enableBetaUpdates: false,
              fishMapWorkspace: const SizedBox.shrink(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final needArrow = find.byKey(
        PlannerActionKeys.row('P12', 'missing-acquisition:Cooking Honey'),
      );
      await tester.ensureVisible(needArrow);
      await tester.tap(needArrow);
      await tester.pumpAndSettle();
      final process = find.byKey(
        const ValueKey('acquisition-choice:Cooking Honey:process'),
      );
      expect(process, findsOneWidget);
      expect(
        find.byKey(const ValueKey('acquisition-choice:Cooking Honey:buy')),
        findsOneWidget,
      );
      if (Platform.isWindows) {
        await _settleWork(
          tester,
          Future.wait([
            for (final element in find.byType(Image).evaluate().toList())
              precacheImage((element.widget as Image).image, element),
          ]),
        );
        await tester.pumpAndSettle();
        await expectLater(
          find.byKey(const ValueKey('acquisition-capture')),
          matchesGoldenFile('goldens/honey_acquisition_choice_sakura.png'),
        );
      }
      await tester.tap(process);
      await tester.pumpAndSettle();
      expect(cooking.processesAcquisition('Cooking Honey'), isTrue);
      expect(
        cooking.plan.value.missing.any((item) => item.name == 'Wild Beehive'),
        isTrue,
      );
      final queueArrow = find.byKey(
        PlannerActionKeys.row('P12', 'queue-title:Cooking Honey'),
      );
      await tester.ensureVisible(queueArrow);
      await tester.tap(queueArrow);
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('acquisition-choice:Cooking Honey:buy')),
      );
      await tester.pumpAndSettle();
      expect(cooking.processesAcquisition('Cooking Honey'), isFalse);
      expect(
        cooking.plan.value.missing
            .firstWhere((item) => item.name == 'Cooking Honey')
            .missing,
        5,
      );
      expect(cooking.state.value.inventory['Cooking Honey'], 3);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await _settleWork(tester, harness.dispose());
    },
  );
}

Future<void> _settleWork(WidgetTester tester, Future<Object?> work) async {
  var done = false;
  Object? failure;
  unawaited(
    work.then(
      (_) => done = true,
      onError: (Object error) {
        failure = error;
        done = true;
      },
    ),
  );
  for (var i = 0; i < 1000 && !done; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump();
  }
  expect(failure, isNull);
  expect(done, isTrue, reason: 'Pending asset and save work must finish');
}

Future<void> _loadFonts() async {
  if (!Platform.isWindows) return;
  final windowsPath = Platform.environment['WINDIR'] ?? r'C:\Windows';
  var sdk = File(Platform.resolvedExecutable).parent;
  while (!Directory(
    '${sdk.path}/bin/cache/artifacts/material_fonts',
  ).existsSync()) {
    if (sdk.parent.path == sdk.path) {
      throw StateError('Flutter fonts not found');
    }
    sdk = sdk.parent;
  }
  for (final font in {
    'Segoe UI': [
      '$windowsPath/Fonts/segoeui.ttf',
      '$windowsPath/Fonts/seguisb.ttf',
      '$windowsPath/Fonts/segoeuib.ttf',
    ],
    'Georgia': [
      '$windowsPath/Fonts/georgia.ttf',
      '$windowsPath/Fonts/georgiab.ttf',
    ],
    'Roboto': [
      '${sdk.path}/bin/cache/artifacts/material_fonts/roboto-regular.ttf',
      '${sdk.path}/bin/cache/artifacts/material_fonts/roboto-bold.ttf',
    ],
    'MaterialIcons': [
      '${sdk.path}/bin/cache/artifacts/material_fonts/materialicons-regular.otf',
    ],
  }.entries) {
    final loader = FontLoader(font.key);
    for (final path in font.value) {
      loader.addFont(File(path).readAsBytes().then(ByteData.sublistView));
    }
    await loader.load();
  }
}
