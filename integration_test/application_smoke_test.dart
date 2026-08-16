import 'dart:convert';
import 'dart:io';

import 'package:bdo_craft_planner_flutter/app/app.dart';
import 'package:bdo_craft_planner_flutter/app/application_bootstrap.dart';
import 'package:bdo_craft_planner_flutter/app/window/window_host_service.dart';
import 'package:bdo_craft_planner_flutter/data/catalog/bundled_data_service.dart';
import 'package:bdo_craft_planner_flutter/data/persistence/planner_state_repository.dart';
import 'package:bdo_craft_planner_flutter/domain/market/market_cancellation.dart';
import 'package:bdo_craft_planner_flutter/domain/market/market_price_gateway.dart';
import 'package:bdo_craft_planner_flutter/domain/market/market_price_models.dart';
import 'package:bdo_craft_planner_flutter/domain/models/catalog_models.dart';
import 'package:bdo_craft_planner_flutter/domain/models/craft_mode.dart';
import 'package:bdo_craft_planner_flutter/features/appearance/appearance_view.dart';
import 'package:bdo_craft_planner_flutter/features/data/data_view.dart';
import 'package:bdo_craft_planner_flutter/features/editor/editor.dart';
import 'package:bdo_craft_planner_flutter/features/inventory/inventory.dart';
import 'package:bdo_craft_planner_flutter/features/planner/planner.dart';
import 'package:bdo_craft_planner_flutter/features/recipe_book/recipe_book.dart';
import 'package:bdo_craft_planner_flutter/features/shell/shell.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

const MethodChannel _windowChannel = MethodChannel(
  'com.bdocraftplanner.flutter/window',
);

const String _onePixelPngData =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8A'
    'AQUBAScY42YAAAAASUVORK5CYII=';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late CatalogSnapshot catalog;
  setUpAll(() async {
    catalog = await BundledDataService().load();
  });

  testWidgets(
    'first launch Import Copy is explicit, source-safe, and one-shot in isolated APPDATA',
    (tester) async {
      final profile = await _IsolatedProfile.create('migration');
      final legacy = profile.paths.legacyStateFile;
      await legacy.parent.create(recursive: true);
      await File(
        'test/fixtures/migration/avalonia-planner-state-synthetic.json',
      ).copy(legacy.path);
      final sourceBefore = await legacy.readAsBytes();
      final sourceHashBefore = sha256.convert(sourceBefore).toString();
      final bootstrap = const ApplicationBootstrapService(
        applicationVersion: 'windows-integration-test',
      );
      final pending = await bootstrap.load(
        catalogFuture: Future<CatalogSnapshot>.value(catalog),
        pathPolicy: profile.paths,
      );

      try {
        expect(
          pending.stateLoad.origin,
          PlannerStateLoadOrigin.awaitingMigration,
        );
        expect(pending.firstLaunchMigration, isNotNull);
        expect(await pending.stateRepository.nativeStateFile.exists(), isFalse);

        await tester.pumpWidget(
          BdoCraftPlannerApp(
            applicationFuture: Future<ApplicationBundle>.value(pending),
            marketGateway: const _EmptyMarketGateway(),
          ),
        );
        await _pumpFrames(tester);
        expect(
          find.bySemanticsLabel('First launch Avalonia migration preview'),
          findsOneWidget,
        );

        final importCopy = find.byKey(
          const ValueKey<String>('migration-import-copy'),
        );
        await tester.ensureVisible(importCopy);
        await tester.tap(importCopy);
        await _pumpFrames(tester, count: 2);
        expect(find.text('Confirm state import'), findsOneWidget);

        // Cancellation proves that merely opening the choice is still read-only.
        await tester.tap(
          find.byKey(const ValueKey<String>('migration-confirm-cancel')),
        );
        await _pumpFrames(tester, count: 2);
        expect(await pending.stateRepository.nativeStateFile.exists(), isFalse);
        expect(
          sha256.convert(await legacy.readAsBytes()).toString(),
          sourceHashBefore,
        );

        await tester.ensureVisible(importCopy);
        await tester.tap(importCopy);
        await _pumpFrames(tester, count: 2);
        await tester.tap(
          find.byKey(const ValueKey<String>('migration-confirm-import')),
        );
        await _waitForCondition(
          tester,
          () => find
              .byKey(const ValueKey<String>('migration-report-title'))
              .evaluate()
              .isNotEmpty,
          description: 'the first-launch migration report',
        );

        expect(await pending.stateRepository.nativeStateFile.exists(), isTrue);
        expect(
          sha256.convert(await legacy.readAsBytes()).toString(),
          sourceHashBefore,
        );
        final archives = await Directory(
          '${profile.paths.applicationDirectory.path}${Platform.pathSeparator}migration',
        ).list().where((entity) => entity is File).cast<File>().toList();
        expect(archives, hasLength(1));
        expect(
          await archives.single.readAsBytes(),
          orderedEquals(sourceBefore),
        );

        final continueToPlanner = find.byKey(
          const ValueKey<String>('migration-report-continue'),
        );
        await tester.ensureVisible(continueToPlanner);
        await tester.tap(continueToPlanner);
        await _pumpFrames(tester);
        await _skipVersionSetupIfVisible(tester);
        expect(find.byType(PlannerView), findsOneWidget);

        await tester.pumpWidget(const SizedBox.shrink());
        await _pumpFrames(tester, count: 2);
        final restarted = await bootstrap.load(
          catalogFuture: Future<CatalogSnapshot>.value(catalog),
          pathPolicy: profile.paths,
        );
        expect(restarted.firstLaunchMigration, isNull);
        expect(restarted.stateLoad.origin, PlannerStateLoadOrigin.native);
        expect(restarted.controller.activeMode.value, CraftMode.cooking);
        expect(restarted.controller.active.state.value.target, 'Beer');
        expect(restarted.controller.active.state.value.inventory, isNotEmpty);
        await restarted.controller.dispose();
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await _pumpFrames(tester, count: 2);
        await pending.controller.dispose();
        await profile.dispose();
      }
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );

  testWidgets(
    'native Windows workflow persists planning, book, inventory, editor, data, appearance, clipboard and open-file dialog bridges',
    (tester) async {
      final profile = await _IsolatedProfile.create('workspace');
      final bootstrap = const ApplicationBootstrapService(
        applicationVersion: 'windows-integration-test',
      );
      final first = await bootstrap.load(
        catalogFuture: Future<CatalogSnapshot>.value(catalog),
        pathPolicy: profile.paths,
      );
      final sourceIcon = File(
        '${profile.root.path}${Platform.pathSeparator}integration-icon.png',
      );
      await sourceIcon.writeAsBytes(
        base64Decode(_onePixelPngData),
        flush: true,
      );
      final dialogCalls = <MethodCall>[];
      var dialogBridgeInstalled = false;

      try {
        expect(first.stateLoad.origin, PlannerStateLoadOrigin.fresh);
        await tester.pumpWidget(
          BdoCraftPlannerApp(
            applicationFuture: Future<ApplicationBundle>.value(first),
            marketGateway: const _EmptyMarketGateway(),
          ),
        );
        await _pumpFrames(tester);
        await _skipVersionSetupIfVisible(tester);
        expect(find.byType(PlannerView), findsOneWidget);

        await _exerciseNativeMaximizeRestore(tester);

        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(_windowChannel, (call) async {
              dialogCalls.add(call);
              return switch (call.method) {
                'pickOpenFile' => sourceIcon.path,
                'isMaximized' || 'toggleMaximize' => false,
                _ => null,
              };
            });
        dialogBridgeInstalled = true;

        final amountField = find.descendant(
          of: find.byKey(PlannerActionKeys.p02),
          matching: find.byType(TextField),
        );
        await tester.enterText(amountField, '3');
        await tester.testTextInput.receiveAction(TextInputAction.done);
        await _pumpFrames(tester, count: 2);
        expect(first.controller.active.state.value.want, 3);
        final clearLiquidInitiallyFavorite = first
            .controller
            .active
            .state
            .value
            .favoriteRecipes
            .contains('Clear Liquid Reagent');

        await tester.tap(find.byKey(PlannerActionKeys.p03));
        await _pumpFrames(tester);
        expect(find.byKey(RecipeBookKeys.modal), findsOneWidget);
        final recipeSearch = find.descendant(
          of: find.byKey(RecipeBookKeys.r03Search),
          matching: find.byType(TextField),
        );
        await tester.enterText(recipeSearch, 'Clear Liquid Reagent');
        await _pumpFrames(tester, count: 2);
        await tester.tap(
          find.byKey(RecipeBookKeys.r12Favorite('Clear Liquid Reagent')),
        );
        await _pumpFrames(tester, count: 2);
        await tester.tap(
          find.byKey(RecipeBookKeys.r13Details('Clear Liquid Reagent')),
        );
        await _pumpFrames(tester);
        expect(
          find.byKey(RecipeBookKeys.r14ClosePreview('Clear Liquid Reagent')),
          findsOneWidget,
        );
        await tester.tap(
          find.byKey(RecipeBookKeys.r14ClosePreview('Clear Liquid Reagent')),
        );
        await _pumpFrames(tester, count: 2);
        await tester.tap(
          find.byKey(RecipeBookKeys.r11Target('Clear Liquid Reagent')),
        );
        await _pumpFrames(tester);
        expect(find.byKey(RecipeBookKeys.modal), findsNothing);
        expect(
          first.controller.active.state.value.target,
          'Clear Liquid Reagent',
        );
        expect(
          first.controller.active.state.value.favoriteRecipes.contains(
            'Clear Liquid Reagent',
          ),
          !clearLiquidInitiallyFavorite,
        );

        final plannerCopy = find.byKey(
          PlannerActionKeys.row('P10', 'Clear Liquid Reagent'),
        );
        await tester.ensureVisible(plannerCopy);
        await tester.tap(plannerCopy);
        await _pumpFrames(tester, count: 2);
        final clipboard = await Clipboard.getData(Clipboard.kTextPlain);
        expect(clipboard?.text, 'Clear Liquid Reagent');

        await _navigate(tester, ShellDestination.inventory);
        expect(find.byType(InventoryView), findsOneWidget);
        final sunriseCategory = InventoryProjection.assemble(
          first.controller.active,
        ).items.singleWhere((item) => item.name == 'Sunrise Herb').category;
        await tester.tap(
          find.byKey(InventoryActionKeys.group(sunriseCategory)),
        );
        await _pumpFrames(tester, count: 2);
        await tester.enterText(
          find.byKey(InventoryActionKeys.i01),
          'Sunrise Herb',
        );
        await _pumpFrames(tester, count: 2);
        final inventoryAmount = find.byKey(
          InventoryActionKeys.row('I10', 'Sunrise Herb'),
        );
        await tester.ensureVisible(inventoryAmount);
        await tester.enterText(inventoryAmount, '4');
        await tester.testTextInput.receiveAction(TextInputAction.done);
        await _pumpFrames(tester, count: 2);
        expect(
          first.controller.active.state.value.inventory['Sunrise Herb'],
          4,
        );

        await _navigate(tester, ShellDestination.recipeEditor);
        expect(find.byType(RecipeEditorView), findsOneWidget);
        await tester.tap(find.byKey(EditorActionKeys.e03));
        await _pumpFrames(tester, count: 2);
        await tester.enterText(
          _editableFor(EditorActionKeys.e04),
          'Integration Catalyst',
        );
        await tester.enterText(_editableFor(EditorActionKeys.e05), '2');
        final ingredientName = _editableFor(EditorActionKeys.ingredientItem(0));
        await tester.ensureVisible(ingredientName);
        await tester.enterText(ingredientName, 'Sunrise Herb');
        await _pumpFrames(tester, count: 2);
        // Select the exact painted RawAutocomplete option. The first keyboard
        // highlight is the related High-Quality item, while a broad text finder
        // can match virtualized editor rows outside the popup.
        final exactIngredientOption = find
            .ancestor(
              of: find.text('Sunrise Herb'),
              matching: find.byType(InkWell),
            )
            .hitTestable();
        expect(exactIngredientOption, findsOneWidget);
        await tester.tap(exactIngredientOption);
        await _pumpFrames(tester, count: 2);
        expect(
          tester.widget<EditableText>(ingredientName).controller.text,
          'Sunrise Herb',
        );
        await tester.enterText(
          _editableFor(EditorActionKeys.ingredientQuantity(0)),
          '2.5',
        );
        final chooseIcon = find.byKey(EditorActionKeys.e11);
        await tester.ensureVisible(chooseIcon);
        await tester.tap(chooseIcon);
        await _waitForCondition(
          tester,
          () => find
              .textContaining('normalized, and staged for Save')
              .evaluate()
              .isNotEmpty,
          description: 'custom icon normalization',
        );
        await _pumpFrames(tester, count: 2);
        final saveRecipe = find.byKey(EditorActionKeys.e17);
        await tester.ensureVisible(saveRecipe);
        await tester.pump();
        final saveCenter = tester.getCenter(saveRecipe);
        final saveHitPath = tester
            .hitTestOnBinding(saveCenter)
            .path
            .map((entry) => entry.target.runtimeType)
            .join(' > ');
        printOnFailure('Save center: $saveCenter; hit path: $saveHitPath');
        await tester.tap(saveRecipe);
        await _waitForCondition(
          tester,
          () => first.controller.active.state.value.recipeEdits.containsKey(
            'Integration Catalyst',
          ),
          description: 'the custom recipe durable save',
        );
        final savedRecipe = first
            .controller
            .active
            .state
            .value
            .recipeEdits['Integration Catalyst'];
        expect(savedRecipe, isNotNull);
        expect(savedRecipe!.ingredients.single.name, 'Sunrise Herb');
        expect(savedRecipe.ingredients.single.quantity, 2.5);
        expect(
          first.controller.active.state.value.customIcons,
          contains('Integration Catalyst'),
        );

        await _navigate(tester, ShellDestination.data);
        expect(find.byType(DataView), findsOneWidget);
        await _enterDataNumber(tester, 'D01', '888');
        expect(first.controller.documentSnapshot.alchemy.alchemyMastery, 888);

        final imageDialog = dialogCalls.singleWhere(
          (call) => call.method == 'pickOpenFile',
        );
        expect(imageDialog.arguments, <String, Object?>{'kind': 'image'});
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(_windowChannel, null);
        dialogBridgeInstalled = false;

        await _navigate(tester, ShellDestination.appearance);
        expect(find.byType(AppearanceView), findsOneWidget);
        final ledger = find.byKey(const ValueKey<String>('A02'));
        await tester.ensureVisible(ledger);
        await tester.tap(ledger);
        await _pumpFrames(tester);
        for (final mode in CraftMode.values) {
          expect(
            first.controller.documentSnapshot
                .forMode(mode)
                .appearance
                .background,
            'illuminated-ledger',
          );
        }
        expect(first.controller.active.state.value.appearance.tabFade, isTrue);
        final transitions = find.byKey(const ValueKey<String>('A09'));
        await tester.ensureVisible(transitions);
        await tester.tap(transitions);
        await _pumpFrames(tester, count: 2);
        final transitionOffLabel = find.text('Off').last;
        expect(transitionOffLabel, findsOneWidget);
        await tester.tap(transitionOffLabel);
        await _pumpFrames(tester, count: 2);
        expect(first.controller.active.state.value.appearance.tabFade, isFalse);

        await first.controller.flush();
        expect(first.controller.saveError.value, isNull);
        expect(await first.stateRepository.nativeStateFile.exists(), isTrue);

        await tester.pumpWidget(const SizedBox.shrink());
        await _pumpFrames(tester, count: 2);
        await first.controller.dispose();

        final restarted = await bootstrap.load(
          catalogFuture: Future<CatalogSnapshot>.value(catalog),
          pathPolicy: profile.paths,
        );
        try {
          expect(restarted.stateLoad.origin, PlannerStateLoadOrigin.native);
          final restoredAlchemy = restarted.controller.documentSnapshot.alchemy;
          // Saving a custom recipe does not implicitly replace the planner
          // target selected through the recipe book.
          expect(restoredAlchemy.target, 'Clear Liquid Reagent');
          expect(restoredAlchemy.want, 3);
          expect(restoredAlchemy.inventory['Sunrise Herb'], 4);
          expect(
            restoredAlchemy.favoriteRecipes.contains('Clear Liquid Reagent'),
            !clearLiquidInitiallyFavorite,
          );
          expect(restoredAlchemy.recipeEdits, contains('Integration Catalyst'));
          expect(restoredAlchemy.customIcons, contains('Integration Catalyst'));
          expect(restoredAlchemy.alchemyMastery, 888);
          expect(restoredAlchemy.appearance.background, 'illuminated-ledger');
          expect(restoredAlchemy.view, 'appearance');

          await tester.pumpWidget(
            BdoCraftPlannerApp(
              applicationFuture: Future<ApplicationBundle>.value(restarted),
              marketGateway: const _EmptyMarketGateway(),
            ),
          );
          await _pumpFrames(tester);
          await _skipVersionSetupIfVisible(tester);
          expect(find.byType(AppearanceView), findsOneWidget);
          await tester.tap(
            find.byKey(ShellActionKeys.mode(CraftMode.processing)),
          );
          await _pumpFrames(tester);
          expect(restarted.controller.activeMode.value, CraftMode.processing);
          expect(
            restarted.controller.active.state.value.appearance.background,
            'illuminated-ledger',
          );
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          await _pumpFrames(tester, count: 2);
          await restarted.controller.dispose();
        }
      } finally {
        if (dialogBridgeInstalled) {
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
              .setMockMethodCallHandler(_windowChannel, null);
        }
        await tester.pumpWidget(const SizedBox.shrink());
        await _pumpFrames(tester, count: 2);
        await first.controller.dispose();
        await profile.dispose();
      }
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );
}

Finder _editableFor(Key key) =>
    find.descendant(of: find.byKey(key), matching: find.byType(EditableText));

Future<void> _navigate(
  WidgetTester tester,
  ShellDestination destination,
) async {
  await tester.tap(find.byKey(destination.actionKey));
  await _pumpFrames(tester);
}

Future<void> _enterDataNumber(
  WidgetTester tester,
  String actionId,
  String value,
) async {
  final action = find.byKey(ValueKey<String>(actionId));
  await tester.ensureVisible(action);
  final editable = find.descendant(
    of: action,
    matching: find.byType(EditableText),
  );
  await tester.enterText(editable, value);
  expect(tester.widget<EditableText>(editable).controller.text, value);
  await tester.testTextInput.receiveAction(TextInputAction.done);
  await _pumpFrames(tester, count: 2);
  // On the live Windows binding, Done closes the test text-input connection
  // while focusedEditable still points at this field. Move the integration
  // binding to the adjacent field so a later edit reopens the real connection.
  final alternateActionId = actionId == 'D01' ? 'D02' : 'D01';
  final alternateEditable = find.descendant(
    of: find.byKey(ValueKey<String>(alternateActionId)),
    matching: find.byType(EditableText),
  );
  await tester.showKeyboard(alternateEditable);
  await tester.pump();
}

Future<void> _exerciseNativeMaximizeRestore(WidgetTester tester) async {
  if (!Platform.isWindows) return;
  const windowHost = WindowHostService();
  final initial = await windowHost.isMaximized();
  final captionButton = find.byTooltip('Maximize or restore');
  expect(captionButton, findsOneWidget);

  await tester.tap(captionButton);
  await _waitForNativeMaximized(tester, !initial);
  await tester.tap(captionButton);
  await _waitForNativeMaximized(tester, initial);
}

Future<void> _waitForNativeMaximized(WidgetTester tester, bool expected) async {
  const windowHost = WindowHostService();
  for (var attempt = 0; attempt < 40; attempt++) {
    await tester.pump(const Duration(milliseconds: 50));
    if (await windowHost.isMaximized() == expected) return;
  }
  fail('Native Windows maximize state did not become $expected.');
}

Future<void> _skipVersionSetupIfVisible(WidgetTester tester) async {
  final skip = find.byKey(const ValueKey<String>('first-run-setup-skip'));
  if (skip.evaluate().isEmpty) return;
  await tester.ensureVisible(skip);
  await tester.tap(skip);
  await _waitForCondition(
    tester,
    () => skip.evaluate().isEmpty,
    description: 'the workspace after dismissing the Beta version setup',
  );
}

Future<void> _waitForCondition(
  WidgetTester tester,
  bool Function() condition, {
  required String description,
}) async {
  for (var attempt = 0; attempt < 100; attempt++) {
    if (condition()) return;
    // File persistence and custom-icon validation use real filesystem and
    // isolate work. Give those queues wall-clock time to progress as well as
    // advancing the Flutter test clock.
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 25)),
    );
    await tester.pump(const Duration(milliseconds: 60));
  }
  final visibleText = tester
      .widgetList<Text>(find.byType(Text))
      .map((widget) => widget.data)
      .whereType<String>()
      .where((value) => value.trim().isNotEmpty)
      .join(' | ');
  expect(
    condition(),
    isTrue,
    reason: 'Timed out waiting for $description. Visible text: $visibleText',
  );
}

Future<void> _pumpFrames(WidgetTester tester, {int count = 5}) async {
  for (var index = 0; index < count; index++) {
    await tester.pump(const Duration(milliseconds: 80));
  }
}

final class _IsolatedProfile {
  const _IsolatedProfile({required this.root, required this.paths});

  final Directory root;
  final PlannerStatePathPolicy paths;

  static Future<_IsolatedProfile> create(String label) async {
    final root = await Directory.systemTemp.createTemp(
      'bdo-windows-integration-$label-',
    );
    final roaming = Directory(
      '${root.path}${Platform.pathSeparator}AppData${Platform.pathSeparator}Roaming',
    );
    final paths = PlannerStatePathPolicy.fromEnvironment(<String, String>{
      'APPDATA': roaming.path,
    });
    expect(paths.applicationDirectory.path, startsWith(roaming.path));
    expect(paths.legacyStateFile.path, startsWith(roaming.path));
    return _IsolatedProfile(root: root, paths: paths);
  }

  Future<void> dispose() async {
    if (await root.exists()) await root.delete(recursive: true);
  }
}

final class _EmptyMarketGateway implements MarketPriceGateway {
  const _EmptyMarketGateway();

  @override
  Future<MarketPriceFetchResult> fetch(
    Iterable<MarketPriceRequest> requests, {
    MarketCancellationToken? cancellationToken,
  }) async => MarketPriceFetchResult(
    region: 'eu',
    language: 'en-US',
    fetchedAt: DateTime.utc(2026, 7, 20, 12),
    items: const <MarketPriceRow>[],
    attemptedSources: const <MarketPriceSource>[],
  );
}
