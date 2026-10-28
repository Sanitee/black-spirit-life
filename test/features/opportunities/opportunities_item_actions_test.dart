import 'dart:io';
import 'dart:ui' as ui;

import 'package:bdo_craft_planner_flutter/data/catalog/catalog_repository.dart';
import 'package:bdo_craft_planner_flutter/domain/models/craft_mode.dart';
import 'package:bdo_craft_planner_flutter/features/opportunities/opportunities_controller.dart';
import 'package:bdo_craft_planner_flutter/features/opportunities/opportunities_item_actions.dart';
import 'package:bdo_craft_planner_flutter/features/opportunities/opportunities_theme.dart';
import 'package:bdo_craft_planner_flutter/features/planner/planner_contracts.dart';
import 'package:bdo_craft_planner_flutter/features/recipe_book/recipe_book_controller.dart';
import 'package:bdo_craft_planner_flutter/features/recipe_book/recipe_book_item_info.dart';
import 'package:bdo_craft_planner_flutter/features/recipe_book/recipe_book_item_info_view.dart';
import 'package:bdo_craft_planner_flutter/features/recipe_book/recipe_book_keys.dart';
import 'package:bdo_craft_planner_flutter/features/shared/mode_item_icon.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/application_test_harness.dart';

void main() {
  setUpAll(() async {
    if (Platform.environment['ITEM_REFERENCE_CAPTURE_DIR'] != null) {
      await _loadReferenceCaptureFonts();
    }
  });

  testWidgets(
    'direct reference icon opens the same rich hover card without a menu',
    (tester) async {
      final fixture = await _fixture(tester);
      const name = 'Iridescent Maehwa Liquor';
      final info = fixture.controller.itemInfoController.itemInfoFor(name)!;
      expect(info.summary, isNotEmpty);
      final before = fixture.harness.bundle.controller.documentSnapshot;
      var mapLookups = 0;
      var surroundingCardOpens = 0;
      final copied = <String>[];
      const artwork = SizedBox(
        key: ValueKey('direct-reference-artwork'),
        width: 36,
        height: 36,
      );
      await tester.pumpWidget(
        _host(
          fixture,
          OpportunityItemActionsScope(
            externalActions: _actions(
              copy: (value) async => copied.add(value),
              resolve: (_) async {
                mapLookups++;
                throw StateError(
                  'Opening reference facts does not need a lookup.',
                );
              },
            ),
            child: InkWell(
              onTap: () => surroundingCardOpens++,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _region(
                    fixture,
                    name: name,
                    primaryOpensItemInfo: true,
                    itemInfo: info,
                    itemInfoIcon: artwork,
                    child: RecipeBookItemInfoHover(
                      controller: fixture.controller.itemInfoController,
                      name: name,
                      info: info,
                      referenceIcon: artwork,
                      interactivePreview: false,
                      child: const SizedBox.square(dimension: 44),
                    ),
                  ),
                  const SizedBox(width: 12),
                  const OpportunityCopyName(name: name),
                  const SizedBox(width: 12),
                  const SizedBox(
                    key: ValueKey('surrounding-detail-action'),
                    width: 44,
                    height: 44,
                    child: ColoredBox(color: Colors.transparent),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      final hover = find.byWidgetPredicate(
        (widget) => widget is Tooltip && widget.richMessage != null,
      );
      tester.state<TooltipState>(hover).ensureTooltipVisible();
      await tester.pumpAndSettle();
      expect(
        tester.widget<ItemReferenceCard>(find.byType(ItemReferenceCard)).info,
        same(info),
      );

      await tester.tap(find.byKey(const ValueKey('opportunity-item:test')));
      await tester.pumpAndSettle();
      expect(find.text('Item info'), findsNothing);
      final card = tester.widget<ItemReferenceCard>(
        find.byType(ItemReferenceCard),
      );
      expect(card.info, same(info));
      expect(card.icon, same(artwork));
      expect(card.controller, same(fixture.controller.itemInfoController));
      expect(card.onClose, isNotNull);
      expect(find.text(info.summary), findsOneWidget);
      expect(find.text('No source details recorded yet.'), findsNothing);
      expect(mapLookups, 0);
      expect(surroundingCardOpens, 0);
      expect(fixture.harness.bundle.controller.documentSnapshot, same(before));

      await tester.tap(
        find.byKey(const ValueKey('item-reference-copy:$name')).first,
      );
      await tester.pumpAndSettle();
      expect(copied, [name]);
      await tester.tap(find.bySemanticsLabel('Close $name information'));
      await tester.pumpAndSettle();
      expect(find.byType(ItemReferenceCard), findsNothing);
      await tester.tap(
        find.byKey(const ValueKey('opportunity-copy-name:$name')),
      );
      await tester.pumpAndSettle();
      expect(copied, [name, name]);
      expect(surroundingCardOpens, 0);
      await tester.tap(find.byKey(const ValueKey('surrounding-detail-action')));
      expect(surroundingCardOpens, 1);
      expect(tester.takeException(), isNull);
      await _dispose(tester, fixture);
    },
  );

  for (final activationKey in [
    LogicalKeyboardKey.enter,
    LogicalKeyboardKey.space,
  ]) {
    testWidgets(
      'direct reference icon supports ${activationKey.keyLabel} and restores focus',
      (tester) async {
        final fixture = await _fixture(tester);
        final semantics = tester.ensureSemantics();
        await tester.pumpWidget(
          _host(
            fixture,
            _region(fixture, name: 'Paprika', primaryOpensItemInfo: true),
          ),
        );
        final region = find.byKey(const ValueKey('opportunity-item:test'));
        final detector = find
            .ancestor(
              of: region,
              matching: find.byType(FocusableActionDetector),
            )
            .first;
        final focus = tester
            .widget<FocusableActionDetector>(detector)
            .focusNode!;
        focus.requestFocus();
        await tester.pump();
        expect(focus.hasPrimaryFocus, isTrue);
        final node = tester.getSemantics(region);
        expect(node.label, contains('Show Paprika information'));
        expect(node.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
        await tester.sendKeyEvent(activationKey);
        await tester.pumpAndSettle();
        expect(find.byType(ItemReferenceCard), findsOneWidget);
        expect(find.text('Item info'), findsNothing);
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
        expect(find.byType(ItemReferenceCard), findsNothing);
        expect(focus.hasPrimaryFocus, isTrue);
        await tester.sendKeyEvent(LogicalKeyboardKey.contextMenu);
        await tester.pumpAndSettle();
        expect(find.text('Item info'), findsOneWidget);
        expect(find.text('Copy name'), findsOneWidget);
        expect(find.byType(ItemReferenceCard), findsNothing);
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
        expect(focus.hasPrimaryFocus, isTrue);
        expect(tester.takeException(), isNull);
        semantics.dispose();
        await _dispose(tester, fixture);
      },
    );
  }

  for (final name in const ['Essence of Dawn - Accuracy', 'Magical Shard']) {
    testWidgets(
      'shared item dialog fits, scrolls, copies and dismisses at 1200: $name',
      (tester) async {
        final fixture = await _fixture(tester);
        tester.view.physicalSize = const Size(1200, 752);
        final captureName = name == 'Magical Shard'
            ? 'opportunities-shard-info'
            : 'opportunities-item-info';
        final captureKey = GlobalKey();
        final copied = <String>[];
        await tester.pumpWidget(
          RepaintBoundary(
            key: captureKey,
            child: _host(
              fixture,
              OpportunityItemActionsScope(
                externalActions: _actions(
                  copy: (value) async => copied.add(value),
                ),
                child: _region(fixture, name: name),
              ),
            ),
          ),
        );
        await _rightClick(tester);
        await tester.tap(find.text('Item info'));
        await tester.pumpAndSettle();
        final card = find.byType(ItemReferenceCard);
        final rect = tester.getRect(card);
        expect(rect.left, greaterThanOrEqualTo(24));
        expect(rect.right, lessThanOrEqualTo(1176));
        expect(rect.top, greaterThanOrEqualTo(24));
        expect(rect.bottom, lessThanOrEqualTo(728));
        expect(
          tester.widget<ItemReferenceCard>(card).controller,
          same(fixture.controller.itemInfoController),
        );
        final headerIcon = find
            .descendant(of: card, matching: find.byType(ModeItemIcon))
            .first;
        expect(tester.widget<ModeItemIcon>(headerIcon).name, name);
        expect(
          tester.widget<ModeItemIcon>(headerIcon).searchAcrossModes,
          isTrue,
        );
        expect(
          find.descendant(
            of: headerIcon,
            matching: find.byKey(ModeItemIconKeys.image(name)),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: headerIcon,
            matching: find.byKey(ModeItemIconKeys.failure(name)),
          ),
          findsNothing,
        );
        await _captureReferenceDialog(
          tester,
          captureKey,
          '$captureName-1200-normal',
        );
        final position = tester
            .state<ScrollableState>(
              find
                  .descendant(of: card, matching: find.byType(Scrollable))
                  .first,
            )
            .position;
        if (name == 'Magical Shard') {
          expect(position.maxScrollExtent, greaterThan(0));
        }
        position.jumpTo(position.maxScrollExtent);
        await tester.pumpAndSettle();
        expect(position.pixels, position.maxScrollExtent);
        await _captureReferenceDialog(
          tester,
          captureKey,
          '$captureName-1200-scrolled',
        );
        position.jumpTo(0);
        await tester.pumpAndSettle();
        await tester.tap(
          find
              .descendant(
                of: card,
                matching: find.byKey(ValueKey('item-reference-copy:$name')),
              )
              .first,
        );
        await tester.pumpAndSettle();
        expect(copied, [name]);
        await tester.tap(find.bySemanticsLabel('Close $name information'));
        await tester.pumpAndSettle();
        expect(card, findsNothing);
        expect(tester.takeException(), isNull);
        await _dispose(tester, fixture);
      },
    );
  }

  testWidgets('item reference alternatives omit archived crystals', (
    tester,
  ) async {
    final fixture = await _fixture(tester);
    await tester.pumpWidget(
      _host(fixture, _region(fixture, name: 'Magical Shard')),
    );
    await _rightClick(tester);
    await tester.tap(find.text('Item info'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Black Magic Crystal - Precision'),
      findsWidgets,
    );
    for (final suffix in [
      'Power',
      'Patience',
      'Healing',
      'Resonance',
      'Endurance',
    ]) {
      expect(find.text('Black Magic Crystal - $suffix'), findsNothing);
    }
    expect(tester.takeException(), isNull);
    await _dispose(tester, fixture);
  });

  testWidgets(
    'archived item info explains the archive without a false source',
    (tester) async {
      final fixture = await _fixture(tester);
      await tester.pumpWidget(
        _host(fixture, _region(fixture, name: 'Monkey Blood')),
      );
      await _rightClick(tester);
      await tester.tap(find.text('Item info'));
      await tester.pumpAndSettle();
      expect(find.text('Temporarily archived'), findsOneWidget);
      expect(find.text('No current source confirmed.'), findsOneWidget);
      expect(find.text('How to Obtain'), findsNothing);
      expect(find.textContaining('hunting a Monkey'), findsNothing);
      expect(tester.takeException(), isNull);
      await _dispose(tester, fixture);
    },
  );
  testWidgets(
    'item info keeps multi-ingredient formulas as separate icon rows',
    (tester) async {
      final fixture = await _fixture(tester);
      final book = RecipeBookController(
        modeController: fixture.controller.modeController,
        catalogRepository: fixture.controller.catalog,
        callingContext: RecipeBookCallingContext.planner,
        allowedTargets: const [],
      );
      final info = book.itemInfoFor('Beer')!;
      book.dispose();
      expect(info.acquisitionFormulas.first.ingredients.length, greaterThan(2));
      await tester.pumpWidget(_host(fixture, _region(fixture, name: 'Beer')));
      await _rightClick(tester);
      await tester.tap(find.text('Item info'));
      await tester.pumpAndSettle();
      expect(find.text('Recipe & materials'), findsOneWidget);
      final card = tester.widget<ItemReferenceCard>(
        find.byType(ItemReferenceCard),
      );
      expect(card.controller, same(fixture.controller.itemInfoController));
      expect(card.info.acquisitionNotes, info.acquisitionNotes);
      expect(card.info.effects, info.effects);
      final formula = info.acquisitionFormulas.first;
      expect(
        find.byKey(
          RecipeBookKeys.itemInfoFormula(
            formula.outputName,
            formula.variantId,
            formula.batchMultiplier,
          ),
        ),
        findsOneWidget,
      );
      for (final ingredient in info.acquisitionFormulas.first.ingredients) {
        final row = find.byKey(
          RecipeBookKeys.itemInfoMaterial(
            formula.outputName,
            formula.variantId,
            ingredient.name,
          ),
        );
        expect(row, findsOneWidget);
        final icon = tester.widget<ModeItemIcon>(
          find.descendant(of: row, matching: find.byType(ModeItemIcon)),
        );
        expect(icon.name, ingredient.name);
        expect(icon.size, 36);
        expect(icon.searchAcrossModes, isTrue);
      }
      for (final formula in info.acquisitionFormulas) {
        expect(
          find.text(recipeBookFormulaSummary(formula)),
          findsNothing,
          reason:
              'A multi-material formula must not become one summary sentence.',
        );
      }
      expect(tester.takeException(), isNull);
      await _dispose(tester, fixture);
    },
  );

  testWidgets('unknown items still have info without changing primary click', (
    tester,
  ) async {
    final fixture = await _fixture(tester);
    var primaryClicks = 0;
    await tester.pumpWidget(
      _host(
        fixture,
        Builder(
          builder: (context) {
            return _region(
              fixture,
              name: 'Unresearched test material',
              child: TextButton(
                onPressed: () => primaryClicks++,
                child: const Text('Material'),
              ),
            );
          },
        ),
      ),
    );
    await tester.tap(find.text('Material'));
    expect(primaryClicks, 1);
    await _rightClick(tester);
    expect(find.text('Item info'), findsOneWidget);
    expect(find.text('View recipe'), findsNothing);
    expect(find.text('Show gathering locations'), findsNothing);
    await tester.tap(find.text('Item info'));
    await tester.pumpAndSettle();
    final card = tester.widget<ItemReferenceCard>(
      find.byType(ItemReferenceCard),
    );
    expect(card.info.title, 'Unresearched test material');
    expect(card.info.effects, isEmpty);
    expect(card.info.acquisitionFormulas, isEmpty);
    expect(card.info.acquisitionNotes, isEmpty);
    expect(find.text('Effects'), findsNothing);
    expect(primaryClicks, 1);
    expect(tester.takeException(), isNull);
    await _dispose(tester, fixture);
  });

  testWidgets('item info header and formula names copy only the exact name', (
    tester,
  ) async {
    final fixture = await _fixture(tester);
    final copied = <String>[];
    final book = RecipeBookController(
      modeController: fixture.controller.modeController,
      catalogRepository: fixture.controller.catalog,
      callingContext: RecipeBookCallingContext.planner,
      allowedTargets: const [],
    );
    final formula = book.itemInfoFor('Beer')!.acquisitionFormulas.first;
    book.dispose();
    await tester.pumpWidget(
      _host(
        fixture,
        OpportunityItemActionsScope(
          externalActions: _actions(copy: (name) async => copied.add(name)),
          child: _region(fixture, name: 'Beer'),
        ),
      ),
    );
    await _rightClick(tester);
    await tester.tap(find.text('Item info'));
    await tester.pumpAndSettle();
    final dialog = find.byKey(const ValueKey('opportunity-item-info:Beer'));
    final header = find
        .descendant(
          of: dialog,
          matching: find.byKey(const ValueKey('item-reference-copy:Beer')),
        )
        .first;
    expect(header, findsOneWidget);
    await tester.tap(header);
    await tester.pumpAndSettle();
    expect(copied, ['Beer']);

    final formulaRow = find.byKey(
      RecipeBookKeys.itemInfoFormula(
        formula.outputName,
        formula.variantId,
        formula.batchMultiplier,
      ),
    );
    final output = find.descendant(
      of: formulaRow,
      matching: find.byKey(
        ValueKey('item-reference-copy:${formula.outputName}'),
      ),
    );
    expect(output, findsOneWidget);
    await tester.ensureVisible(output);
    await tester.tap(output);
    await tester.pumpAndSettle();
    expect(copied, ['Beer', formula.outputName]);

    for (final ingredient in formula.ingredients) {
      final row = find.byKey(
        RecipeBookKeys.itemInfoMaterial(
          formula.outputName,
          formula.variantId,
          ingredient.name,
        ),
      );
      final name = find.descendant(
        of: row,
        matching: find.byKey(
          ValueKey('item-reference-copy:${ingredient.name}'),
        ),
      );
      await tester.ensureVisible(name);
      await tester.tap(name);
      await tester.pumpAndSettle();
    }
    expect(copied, [
      'Beer',
      formula.outputName,
      for (final ingredient in formula.ingredients) ingredient.name,
    ]);
    expect(dialog, findsOneWidget);
    expect(tester.takeException(), isNull);
    await _dispose(tester, fixture);
  });

  testWidgets('item info alternative copies its exact name without quantity', (
    tester,
  ) async {
    final fixture = await _fixture(tester);
    final copied = <String>[];
    await tester.pumpWidget(
      _host(
        fixture,
        OpportunityItemActionsScope(
          externalActions: _actions(copy: (name) async => copied.add(name)),
          child: _region(fixture, name: 'Magical Shard'),
        ),
      ),
    );
    await _rightClick(tester);
    await tester.tap(find.text('Item info'));
    await tester.pumpAndSettle();
    const exactName = 'Black Magic Crystal - Precision';
    final formula = fixture.controller.itemInfoController
        .itemInfoFor('Magical Shard')!
        .acquisitionFormulas
        .first;
    final name = find.descendant(
      of: find.byKey(
        RecipeBookKeys.itemInfoFormula(
          formula.outputName,
          formula.variantId,
          formula.batchMultiplier,
        ),
      ),
      matching: find.byKey(const ValueKey('item-reference-copy:$exactName')),
    );
    expect(name, findsOneWidget);
    await tester.ensureVisible(name);
    await tester.tap(name);
    await tester.pumpAndSettle();
    expect(copied, [exactName]);
    expect(
      find.byKey(const ValueKey('opportunity-item-info:Magical Shard')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
    await _dispose(tester, fixture);
  });

  testWidgets(
    'shared formula copy names expose working accessibility actions',
    (tester) async {
      final semantics = tester.ensureSemantics();
      try {
        final fixture = await _fixture(tester);
        final copied = <String>[];
        await tester.pumpWidget(
          _host(
            fixture,
            OpportunityItemActionsScope(
              externalActions: _actions(copy: (name) async => copied.add(name)),
              child: _region(fixture, name: 'Magical Shard'),
            ),
          ),
        );
        await _rightClick(tester);
        await tester.tap(find.text('Item info'));
        await tester.pumpAndSettle();
        final formula = fixture.controller.itemInfoController
            .itemInfoFor('Magical Shard')!
            .acquisitionFormulas
            .first;
        final formulaRow = find.byKey(
          RecipeBookKeys.itemInfoFormula(
            formula.outputName,
            formula.variantId,
            formula.batchMultiplier,
          ),
        );
        final exactNames = <String>[
          formula.outputName,
          formula.ingredients.first.name,
          'Black Magic Crystal - Precision',
        ];
        for (final name in exactNames) {
          final action = find.descendant(
            of: formulaRow,
            matching: find.byKey(ValueKey('item-reference-copy:$name')),
          );
          expect(action, findsOneWidget);
          await tester.ensureVisible(action);
          await tester.pumpAndSettle();
          final node = tester.getSemantics(action);
          expect(node.label, 'Copy $name');
          expect(
            node.getSemanticsData().hasAction(SemanticsAction.tap),
            isTrue,
            reason: 'A copy button flag without a tap action is not usable.',
          );
          node.owner!.performAction(node.id, SemanticsAction.tap);
          await tester.pumpAndSettle();
        }
        expect(copied, exactNames);
        expect(find.byType(ItemReferenceCard), findsOneWidget);
        expect(tester.takeException(), isNull);
        await _dispose(tester, fixture);
      } finally {
        semantics.dispose();
      }
    },
  );

  testWidgets('right-clicking a copy name opens only its item context menu', (
    tester,
  ) async {
    final fixture = await _fixture(tester);
    final copied = <String>[];
    var recipeOpens = 0;
    await tester.pumpWidget(
      _host(
        fixture,
        OpportunityItemActionsScope(
          externalActions: _actions(copy: (name) async => copied.add(name)),
          child: _region(
            fixture,
            onViewRecipe: () => recipeOpens++,
            child: InkWell(
              onTap: () => recipeOpens++,
              child: const Padding(
                padding: EdgeInsets.all(20),
                child: OpportunityCopyName(
                  name: 'Olivine',
                  displayLabel: '3× Olivine',
                ),
              ),
            ),
          ),
        ),
      ),
    );
    final name = find.byKey(const ValueKey('opportunity-copy-name:Olivine'));
    await tester.tap(
      name,
      buttons: kSecondaryMouseButton,
      kind: PointerDeviceKind.mouse,
    );
    await tester.pumpAndSettle();
    expect(find.text('Item info'), findsOneWidget);
    expect(find.text('View recipe'), findsOneWidget);
    expect(copied, isEmpty);
    expect(recipeOpens, 0);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(copied, isEmpty);
    expect(recipeOpens, 0);

    await tester.tap(name);
    await tester.pumpAndSettle();
    expect(copied, ['Olivine']);
    expect(recipeOpens, 0);
    await tester.tap(
      name,
      buttons: kSecondaryMouseButton,
      kind: PointerDeviceKind.mouse,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Copy name'));
    await tester.pumpAndSettle();
    expect(copied, ['Olivine', 'Olivine']);
    expect(recipeOpens, 0);
    await tester.tap(
      name,
      buttons: kSecondaryMouseButton,
      kind: PointerDeviceKind.mouse,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('View recipe'));
    await tester.pumpAndSettle();
    expect(copied, ['Olivine', 'Olivine']);
    expect(recipeOpens, 1);
    expect(tester.takeException(), isNull);
    await _dispose(tester, fixture);
  });

  testWidgets(
    'scoped worker action retains its dialog and does not change targets',
    (tester) async {
      final fixture = await _fixture(tester);
      final navigator = GlobalKey<NavigatorState>();
      final opened = <PlannerMapLookupRequest>[];
      var targetWrites = 0;
      final targets = fixture
          .harness
          .bundle
          .controller
          .resourceMapNodeNetworkPreferences
          .value;
      final actions = _actions(
        availability: const PlannerMapLookupAvailability(
          materialName: 'Cooking Honey',
          hasWorkerNodes: true,
          workerResourceId: 'item:7702',
          workerNodeCount: 2,
        ),
        open: (request) {
          expect(
            navigator.currentState!.canPop(),
            isTrue,
            reason:
                'The workspace retains its route while another tab is active.',
          );
          opened.add(request);
        },
        onTargetWrite: () => targetWrites++,
      );
      await tester.pumpWidget(
        _host(
          fixture,
          OpportunityItemActionsScope(
            externalActions: actions,
            child: Builder(
              builder: (context) => TextButton(
                onPressed: () => showDialog<void>(
                  context: context,
                  builder: (_) =>
                      Dialog(child: _region(fixture, name: 'Cooking Honey')),
                ),
                child: const Text('Open calculation'),
              ),
            ),
          ),
          navigator: navigator,
        ),
      );
      await tester.tap(find.text('Open calculation'));
      await tester.pumpAndSettle();
      await _rightClick(tester);
      expect(find.text('Show worker nodes'), findsOneWidget);
      expect(find.text('Add to planned network'), findsOneWidget);
      await tester.tap(find.text('Show worker nodes'));
      await tester.pumpAndSettle();
      expect(opened.single.source, PlannerMapLookupSource.workerNodes);
      expect(opened.single.resourceId, 'item:7702');
      expect(find.byType(Dialog), findsOneWidget);
      expect(targetWrites, 0);
      expect(
        fixture
            .harness
            .bundle
            .controller
            .resourceMapNodeNetworkPreferences
            .value,
        same(targets),
      );
      await _dispose(tester, fixture);
    },
  );

  testWidgets(
    'manual fallback uses its real material and NPC actions stay separate',
    (tester) async {
      final fixture = await _fixture(tester);
      final opened = <PlannerMapLookupRequest>[];
      final actions = _actions(
        availability: const PlannerMapLookupAvailability(
          materialName: 'Cooking Honey',
          hasNpcVendors: true,
          npcVendorCount: 1,
          hasManualGathering: true,
          manualLocationCount: 1,
          manualMaterialName: 'Wild Beehives',
          manualResourceId: 'item:7701',
        ),
        open: opened.add,
      );
      await tester.pumpWidget(
        _host(
          fixture,
          OpportunityItemActionsScope(
            externalActions: actions,
            child: _region(fixture, name: 'Cooking Honey'),
          ),
        ),
      );
      await _rightClick(tester);
      await tester.tap(find.text('Show Wild Beehives'));
      await tester.pumpAndSettle();
      expect(opened.single.materialName, 'Wild Beehives');
      expect(opened.single.resourceId, 'item:7701');
      expect(opened.single.source, PlannerMapLookupSource.manualGathering);
      await _rightClick(tester);
      await tester.tap(find.text('Show NPC vendors'));
      await tester.pumpAndSettle();
      expect(opened.last.materialName, 'Cooking Honey');
      expect(opened.last.source, PlannerMapLookupSource.npcVendors);
      expect(opened.last.resourceId, isNull);
      await _dispose(tester, fixture);
    },
  );

  testWidgets(
    'planner target action passes the exact live target without changing its amount',
    (tester) async {
      final fixture = await _fixture(tester);
      final requests = <PlannerTargetRequest>[];
      final before = fixture.harness.bundle.controller.documentSnapshot;
      await tester.pumpWidget(
        _host(
          fixture,
          OpportunityItemActionsScope(
            externalActions: _actions(plannerTarget: requests.add),
            child: _region(fixture, name: 'Cream'),
          ),
        ),
      );
      await _rightClick(tester);
      expect(find.text('Set planner target'), findsOneWidget);
      await tester.tap(find.text('Set planner target'));
      await tester.pumpAndSettle();
      expect(requests.single.exactName, 'Cream');
      expect(requests.single.mode, CraftMode.cooking);
      expect(fixture.harness.bundle.controller.documentSnapshot, same(before));
      await _dispose(tester, fixture);
    },
  );

  testWidgets('source additions use the existing callbacks only when mapped', (
    tester,
  ) async {
    final fixture = await _fixture(tester);
    var writes = 0;
    final opened = <PlannerMapLookupRequest>[];
    final before = fixture.harness.bundle.controller.documentSnapshot;
    await tester.pumpWidget(
      _host(
        fixture,
        OpportunityItemActionsScope(
          externalActions: _actions(
            availability: const PlannerMapLookupAvailability(
              materialName: 'Wheat',
              hasWorkerNodes: true,
              workerResourceId: 'item:7001',
            ),
            open: opened.add,
            onTargetWrite: () => writes++,
          ),
          child: _region(fixture, name: 'Wheat'),
        ),
      ),
    );
    await _rightClick(tester);
    expect(find.text('Set planner target'), findsNothing);
    await tester.tap(find.text('Add to to-do list'));
    await tester.pumpAndSettle();
    expect(writes, 1);
    expect(opened, isEmpty);
    await _rightClick(tester);
    await tester.tap(find.text('Add to planned network'));
    await tester.pumpAndSettle();
    expect(writes, 2);
    expect(opened, isEmpty);
    expect(fixture.harness.bundle.controller.documentSnapshot, same(before));
    await tester.pumpWidget(
      _host(
        fixture,
        OpportunityItemActionsScope(
          externalActions: _actions(onTargetWrite: () => writes++),
          child: _region(fixture),
        ),
      ),
    );
    await _rightClick(tester);
    expect(find.text('Add to to-do list'), findsNothing);
    expect(find.text('Add to planned network'), findsNothing);
    expect(writes, 2);
    await _dispose(tester, fixture);
  });

  testWidgets('long press, copy and keyboard menu preserve recipe callbacks', (
    tester,
  ) async {
    final fixture = await _fixture(tester);
    var recipeOpens = 0;
    final copied = <String>[];
    await tester.pumpWidget(
      _host(
        fixture,
        OpportunityItemActionsScope(
          externalActions: _actions(copy: (name) async => copied.add(name)),
          child: _region(fixture, onViewRecipe: () => recipeOpens++),
        ),
      ),
    );
    await tester.longPress(find.byKey(const ValueKey('opportunity-item:test')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('View recipe'));
    await tester.pumpAndSettle();
    expect(recipeOpens, 1);
    await _rightClick(tester);
    await tester.tap(find.text('Copy name'));
    await tester.pumpAndSettle();
    expect(copied, ['Olivine']);
    final focus = tester
        .widget<FocusableActionDetector>(
          find
              .ancestor(
                of: find.byKey(const ValueKey('opportunity-item:test')),
                matching: find.byType(FocusableActionDetector),
              )
              .first,
        )
        .focusNode!;
    focus.requestFocus();
    await tester.pump();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.f10);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pumpAndSettle();
    expect(find.text('Item info'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(recipeOpens, 1);
    await _dispose(tester, fixture);
  });

  testWidgets('a failed map lookup does not hide researched item information', (
    tester,
  ) async {
    final fixture = await _fixture(tester);
    final actions = _actions(
      resolve: (_) async => throw StateError('Unavailable'),
    );
    await tester.pumpWidget(
      _host(
        fixture,
        OpportunityItemActionsScope(
          externalActions: actions,
          child: _region(fixture, name: 'Magical Lightstone Crystal'),
        ),
      ),
    );
    await _rightClick(tester);
    await tester.tap(find.text('Item info'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Dalishain'), findsWidgets);
    expect(find.text('No source details recorded yet.'), findsNothing);
    expect(tester.takeException(), isNull);
    await _dispose(tester, fixture);
  });

  testWidgets('focusable primary action gets one Tab stop and keyboard menu', (
    tester,
  ) async {
    final fixture = await _fixture(tester);
    final before = FocusNode();
    final primary = FocusNode();
    final after = FocusNode();
    var primaryClicks = 0;
    var recipeOpens = 0;
    await tester.pumpWidget(
      _host(
        fixture,
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextButton(
              focusNode: before,
              onPressed: () {},
              child: const Text('Before'),
            ),
            _region(
              fixture,
              childHandlesFocus: true,
              onViewRecipe: () => recipeOpens++,
              child: InkWell(
                focusNode: primary,
                onTap: () => primaryClicks++,
                child: const Padding(
                  padding: EdgeInsets.all(20),
                  child: Text('Open calculation'),
                ),
              ),
            ),
            TextButton(
              focusNode: after,
              onPressed: () {},
              child: const Text('After'),
            ),
          ],
        ),
      ),
    );
    before.requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    expect(primary.hasPrimaryFocus, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    expect(after.hasPrimaryFocus, isTrue);
    primary.requestFocus();
    await tester.pump();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.f10);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pumpAndSettle();
    expect(find.text('Item info'), findsOneWidget);
    await tester.tap(find.text('View recipe'));
    await tester.pumpAndSettle();
    expect(recipeOpens, 1);
    expect(primary.hasPrimaryFocus, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(primaryClicks, 1);
    await _rightClick(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(primary.hasPrimaryFocus, isTrue);
    expect(primaryClicks, 1);
    expect(tester.takeException(), isNull);
    await _dispose(tester, fixture);
    before.dispose();
    primary.dispose();
    after.dispose();
  });
}

Widget _region(
  _Fixture fixture, {
  String name = 'Olivine',
  Widget? child,
  VoidCallback? onViewRecipe,
  bool childHandlesFocus = false,
  bool primaryOpensItemInfo = false,
  RecipeBookItemInfo? itemInfo,
  Widget? itemInfoIcon,
}) => OpportunityItemRegion(
  controller: fixture.controller,
  name: name,
  stableId: 'test',
  onViewRecipe: onViewRecipe,
  childHandlesFocus: childHandlesFocus,
  primaryOpensItemInfo: primaryOpensItemInfo,
  itemInfo: itemInfo,
  itemInfoIcon: itemInfoIcon,
  child:
      child ??
      const Padding(padding: EdgeInsets.all(28), child: Text('Material')),
);

Widget _host(
  _Fixture fixture,
  Widget child, {
  GlobalKey<NavigatorState>? navigator,
}) => MaterialApp(
  navigatorKey: navigator,
  debugShowCheckedModeBanner: false,
  home: OpportunitiesTheme(
    child: Scaffold(body: Center(child: child)),
  ),
);

PlannerExternalActions _actions({
  PlannerMapLookupAvailability availability =
      const PlannerMapLookupAvailability(materialName: 'Olivine'),
  OpenPlannerMapLookup? open,
  ResolvePlannerMapLookup? resolve,
  CopyPlannerName? copy,
  OpenPlannerTarget? plannerTarget,
  VoidCallback? onTargetWrite,
}) => PlannerExternalActions(
  openRecipeBook: (_) {},
  openPlannerTarget: plannerTarget,
  copyName: copy ?? (_) async {},
  checkPrices: (_) async => throw UnimplementedError(),
  resolveMapLookup: resolve ?? (_) async => availability,
  openMapLookup: open ?? (_) {},
  addToPlannedNetwork: (_) => onTargetWrite?.call(),
  addToGatherChecklist: (_) => onTargetWrite?.call(),
);

Future<void> _rightClick(WidgetTester tester) async {
  await tester.tap(
    find.byKey(const ValueKey('opportunity-item:test')),
    buttons: kSecondaryMouseButton,
    kind: PointerDeviceKind.mouse,
  );
  await tester.pumpAndSettle();
}

class _Fixture {
  _Fixture(this.harness, this.controller);
  final ApplicationTestHarness harness;
  final OpportunitiesController controller;
}

Future<_Fixture> _fixture(WidgetTester tester) async {
  configureApplicationTestSurface(tester, const Size(1200, 850));
  return (await tester.runAsync(() async {
    final harness = await ApplicationTestHarness.create();
    final controller = OpportunitiesController(
      appController: harness.bundle.controller,
      catalog: CatalogRepository(harness.bundle.catalog),
      directory: Directory('${harness.temporaryDirectory.path}/opportunities'),
    );
    await controller.ready;
    await controller.calculationSettled;
    return _Fixture(harness, controller);
  }))!;
}

Future<void> _dispose(WidgetTester tester, _Fixture fixture) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.runAsync(() async {
    fixture.controller.dispose();
    await fixture.harness.dispose();
  });
}

Future<void> _captureReferenceDialog(
  WidgetTester tester,
  GlobalKey key,
  String name,
) async {
  final directory = Platform.environment['ITEM_REFERENCE_CAPTURE_DIR'];
  if (directory == null || directory.isEmpty) return;
  for (final element in find.byType(Image).evaluate().toList()) {
    await tester.runAsync(
      () => precacheImage((element.widget as Image).image, element),
    );
  }
  await tester.pumpAndSettle();
  final boundary = tester.renderObject<RenderRepaintBoundary>(find.byKey(key));
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

Future<void> _loadReferenceCaptureFonts() async {
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
