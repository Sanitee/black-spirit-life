import 'dart:io';
import 'dart:ui' as ui;

import 'package:bdo_craft_planner_flutter/data/catalog/catalog_repository.dart';
import 'package:bdo_craft_planner_flutter/data/opportunities/opportunity_market_cache_store.dart';
import 'package:bdo_craft_planner_flutter/data/opportunities/opportunity_market_service.dart';
import 'package:bdo_craft_planner_flutter/domain/models/craft_mode.dart';
import 'package:bdo_craft_planner_flutter/domain/opportunities/opportunity_market_models.dart';
import 'package:bdo_craft_planner_flutter/features/opportunities/opportunities_controller.dart';
import 'package:bdo_craft_planner_flutter/features/opportunities/opportunities_item_actions.dart';
import 'package:bdo_craft_planner_flutter/features/opportunities/opportunities_theme.dart';
import 'package:bdo_craft_planner_flutter/features/opportunities/opportunities_workspace.dart';
import 'package:bdo_craft_planner_flutter/features/planner/planner_contracts.dart';
import 'package:bdo_craft_planner_flutter/features/recipe_book/recipe_book_item_info.dart';
import 'package:bdo_craft_planner_flutter/features/recipe_book/recipe_book_item_info_view.dart';
import 'package:bdo_craft_planner_flutter/features/recipe_book/recipe_book_keys.dart';
import 'package:bdo_craft_planner_flutter/features/shared/mode_item_icon.dart';
import 'package:bdo_craft_planner_flutter/visual/visual.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/application_test_harness.dart';

const _crystal = 'JIN Dawn Crystal - Accuracy';
const _essence = 'Essence of Dawn - Accuracy';
const _capture = ValueKey('opportunity-item-info-hover-capture');

void main() {
  setUpAll(_loadFonts);

  testWidgets(
    'shared card hides blank sections and puts real acquisition before long recipes',
    (tester) async {
      final fixture = await _fixture(tester);
      final book = fixture.controller.itemInfoController;
      final original = book.itemInfoFor(
        'Magical Shard',
        mode: CraftMode.processing,
      )!;
      await tester.pumpWidget(
        _host(
          fixture,
          child: Builder(
            builder: (context) => Align(
              alignment: Alignment.topCenter,
              child: SizedBox(
                height: 650,
                child: ItemReferenceCard(
                  controller: book,
                  mode: CraftMode.processing,
                  name: 'Magical Shard',
                  info: original,
                  maxWidth: 440,
                  spec: context.visualTheme,
                ),
              ),
            ),
          ),
        ),
      );
      await _settleImages(tester);
      expect(find.text('How to Obtain'), findsOneWidget);
      expect(find.text('Buy from the Central Market.'), findsOneWidget);
      expect(
        find.text(
          'Heat a Sealed Black Magic Crystal, or buy Magical Shards through the Central Market.',
        ),
        findsNothing,
      );
      expect(
        tester.getTopLeft(find.text('How to Obtain')).dy,
        lessThan(tester.getTopLeft(find.text('Recipe & materials')).dy),
      );
      expect(
        find.text(
          'Heat a Sealed Black Magic Crystal or another yellow-grade Black Magic Crystal.',
        ),
        findsNothing,
      );
      await _captureImage(tester, 'magical-shard-clean-acquisition');
      await tester.pumpWidget(
        _host(
          fixture,
          child: Builder(
            builder: (context) => ItemReferenceCard(
              controller: book,
              mode: CraftMode.processing,
              name: 'Magical Shard',
              maxWidth: 440,
              spec: context.visualTheme,
              info: const RecipeBookItemInfo(
                title: 'Magical Shard',
                kind: 'Material',
                summary: '',
                effects: [' '],
                uses: ['\n'],
                acquisitionNotes: ['\t'],
                notes: [''],
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      for (final heading in [
        'Effects',
        'Used For',
        'How to Obtain',
        'Notes',
        'Recipe & materials',
      ]) {
        expect(find.text(heading), findsNothing, reason: heading);
      }
      expect(tester.takeException(), isNull);
      await _dispose(tester, fixture);
    },
  );

  testWidgets(
    'Opportunities hover uses the exact Recipe Book information panel',
    (tester) async {
      final fixture = await _fixture(tester);
      final book = fixture.controller.itemInfoController;
      expect(identical(book, fixture.controller.itemInfoController), isTrue);
      expect(
        book.itemInfoFor(_essence, mode: CraftMode.processing)?.hasBody,
        isTrue,
      );
      await tester.pumpWidget(
        _host(
          fixture,
          child: Center(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                RecipeBookItemIcon(
                  key: const ValueKey('original-book-icon'),
                  controller: book,
                  name: _essence,
                  size: 48,
                  mode: CraftMode.processing,
                  anchorId: 'reference',
                ),
                const SizedBox(width: 80),
                RecipeBookItemInfoHover(
                  key: const ValueKey('shared-hover-icon'),
                  controller: book,
                  name: _essence,
                  mode: CraftMode.processing,
                  child: const SizedBox(width: 48, height: 48),
                ),
              ],
            ),
          ),
        ),
      );
      await _settleImages(tester);
      final mouse = await _mouse(tester);
      await _hover(
        tester,
        mouse,
        find.byKey(const ValueKey('original-book-icon')),
      );
      final originalPanelType = tester.widget(_panel(_essence)).runtimeType;
      final originalText = _panelText(tester, _essence);
      expect(originalText.join(' '), contains('Heating'));
      expect(originalText.join(' '), contains('Magical Shard'));
      expect(originalText.join(' '), contains('How to Obtain'));
      expect(originalText.join(' '), contains('Used For'));
      await _leave(tester, mouse);
      await _hover(
        tester,
        mouse,
        find.byKey(const ValueKey('shared-hover-icon')),
      );
      expect(tester.widget(_panel(_essence)).runtimeType, originalPanelType);
      expect(_panelText(tester, _essence), originalText);
      expect(fixture.transport.requests, isEmpty);
      await _leave(tester, mouse);
      await _dispose(tester, fixture);
    },
  );

  testWidgets(
    'unknown item keeps the Recipe Book neutral fallback and child action',
    (tester) async {
      final fixture = await _fixture(tester);
      const unknown = 'Unknown hover regression material';
      final info = fixture.controller.itemInfoController.itemInfoFor(unknown)!;
      expect(info.kind, isNotEmpty);
      expect(info.summary, isEmpty);
      expect(info.acquisitionFormulas, isEmpty);
      expect(info.effects, isEmpty);
      var taps = 0;
      await tester.pumpWidget(
        _host(
          fixture,
          child: Center(
            child: RecipeBookItemInfoHover(
              controller: fixture.controller.itemInfoController,
              name: unknown,
              child: TextButton(
                onPressed: () => taps++,
                child: const Text(unknown),
              ),
            ),
          ),
        ),
      );
      final mouse = await _mouse(tester);
      await mouse.moveTo(tester.getCenter(find.text(unknown)));
      await tester.pump(const Duration(seconds: 1));
      await _settleImages(tester);
      expect(_panel(unknown), findsOneWidget);
      expect(_panelText(tester, unknown), [
        info.kind,
        unknown,
        'No source details recorded yet.',
      ]);
      await tester.tap(find.widgetWithText(TextButton, unknown));
      expect(taps, 1);
      expect(fixture.transport.requests, isEmpty);
      await _dispose(tester, fixture);
    },
  );

  testWidgets(
    'craft hover preserves name copy and icon body recipe navigation',
    (tester) async {
      final fixture = await _fixture(tester);
      await tester.pumpWidget(_host(fixture));
      await _settleImages(tester);
      final card = _region('craft-card:$_crystal');
      final mouse = await _mouse(tester);
      await _hover(tester, mouse, _icon(card, _crystal));
      expect(_panel(_crystal), findsOneWidget);
      expect(find.byType(Dialog), findsNothing);
      expect(fixture.transport.requests, isEmpty);
      await _leave(tester, mouse);
      await tester.tap(
        find.descendant(
          of: card,
          matching: find.byKey(
            const ValueKey('opportunity-copy-name:$_crystal'),
          ),
        ),
      );
      await tester.pump();
      expect(fixture.copied, [_crystal]);
      expect(find.byType(Dialog), findsNothing);
      await tester.tap(_icon(card, _crystal));
      await _settleImages(tester);
      expect(find.byType(Dialog), findsOneWidget);
      expect(_region('opportunity-title:$_crystal'), findsOneWidget);
      await _hover(
        tester,
        mouse,
        _icon(_region('opportunity-title:$_crystal'), _crystal),
      );
      expect(find.byType(Dialog), findsOneWidget);
      await _leave(tester, mouse);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byType(Dialog), findsNothing);
      final cardRect = tester.getRect(card);
      await tester.tapAt(Offset(cardRect.center.dx, cardRect.bottom - 18));
      await _settleImages(tester);
      expect(find.byType(Dialog), findsOneWidget);
      expect(fixture.transport.requests, isEmpty);
      await _dispose(tester, fixture);
    },
  );

  testWidgets(
    'ingredient hover keeps exact-name copy drilldown and context menu',
    (tester) async {
      final fixture = await _fixture(tester);
      await tester.pumpWidget(_host(fixture));
      await _settleImages(tester);
      await _openCrystal(tester);
      final ingredient = _region('ingredient:$_essence');
      final mouse = await _mouse(tester);
      await _hover(tester, mouse, _icon(ingredient, _essence));
      expect(_panel(_essence), findsOneWidget);
      expect(_region('opportunity-title:$_crystal'), findsOneWidget);
      expect(find.byType(Dialog), findsOneWidget);
      await _leave(tester, mouse);
      await tester.tap(
        find.descendant(
          of: ingredient,
          matching: find.byKey(
            const ValueKey('opportunity-copy-name:$_essence'),
          ),
        ),
      );
      await tester.pump();
      expect(fixture.copied, [_essence]);
      expect(_region('opportunity-title:$_crystal'), findsOneWidget);
      await tester.tap(
        _icon(ingredient, _essence),
        buttons: kSecondaryMouseButton,
        kind: ui.PointerDeviceKind.mouse,
      );
      await tester.pumpAndSettle();
      expect(find.text('Item info'), findsOneWidget);
      expect(find.text('View recipe'), findsNothing);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(_region('opportunity-title:$_crystal'), findsOneWidget);
      await tester.longPress(_icon(ingredient, _essence));
      await tester.pumpAndSettle();
      expect(find.text('Item info'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      // Essence remains reference-only, exactly as before this hover change.
      // Magical Shard is a real navigable ingredient in this same bundled recipe.
      const nestedName = 'Magical Shard';
      final nested = _region('ingredient:$nestedName');
      expect(
        find.byKey(const ValueKey('ingredient-recipe-$nestedName')),
        findsOneWidget,
      );
      await tester.tap(_icon(nested, nestedName));
      await _settleImages(tester);
      expect(_region('opportunity-title:$nestedName'), findsOneWidget);
      expect(find.byType(Dialog), findsOneWidget);
      await _hover(
        tester,
        mouse,
        _icon(_region('opportunity-title:$nestedName'), nestedName),
      );
      expect(_panel(nestedName), findsOneWidget);
      await _leave(tester, mouse);
      await tester.tap(find.byKey(const ValueKey('ingredient-recipe-back')));
      await _settleImages(tester);
      final quantity = find.byKey(
        const ValueKey('ingredient-quantity:$nestedName'),
      );
      await tester.ensureVisible(quantity);
      await tester.tap(quantity);
      await _settleImages(tester);
      expect(_region('opportunity-title:$nestedName'), findsOneWidget);
      expect(fixture.transport.requests, isEmpty);
      await _dispose(tester, fixture);
    },
  );

  for (final scenario in [
    (name: 'normal-100', size: const Size(1200, 752), scale: 1.0),
    (name: 'narrow-200', size: const Size(760, 752), scale: 2.0),
    (name: 'large-100', size: const Size(1500, 940), scale: 1.0),
  ]) {
    testWidgets('Essence hover complete formula and spacing ${scenario.name}', (
      tester,
    ) async {
      final fixture = await _fixture(
        tester,
        size: scenario.size,
        scale: scenario.scale,
      );
      await tester.pumpWidget(_host(fixture));
      await _settleImages(tester);
      await _openCrystal(tester);
      final ingredient = _region('ingredient:$_essence');
      final mouse = await _mouse(tester);
      await _hover(tester, mouse, _icon(ingredient, _essence));
      final panel = _panel(_essence);
      final rect = tester.getRect(panel);
      final scroller = tester.state<ScrollableState>(
        find.descendant(of: panel, matching: find.byType(Scrollable)).first,
      );
      expect(scroller.position.pixels, 0, reason: 'Hover opens at its title.');
      await _captureImage(tester, 'essence-ingredient-hover-${scenario.name}');
      expect(rect.left, greaterThanOrEqualTo(0));
      expect(rect.top, greaterThanOrEqualTo(0));
      expect(rect.right, lessThanOrEqualTo(scenario.size.width));
      expect(rect.bottom, lessThanOrEqualTo(scenario.size.height));
      _expectCompleteFormula(tester, panel);
      _expectSectionSpacing(tester, panel, scenario.scale);
      _expectCompactFormulaGeometry(tester, panel);
      _expectConcreteCrystalEffects(tester, panel);
      if (scenario.scale > 1) {
        expect(rect.width, greaterThan(440));
      }
      expect(
        find.descendant(of: panel, matching: find.text(_essence)),
        findsWidgets,
      );
      expect(fixture.transport.requests, isEmpty);
      expect(tester.takeException(), isNull);
      if (scroller.position.maxScrollExtent > 0) {
        final parent = tester.state<ScrollableState>(
          find
              .descendant(
                of: find.byType(Dialog),
                matching: find.byType(Scrollable),
              )
              .first,
        );
        final parentOffset = parent.position.pixels;
        await mouse.moveTo(tester.getCenter(panel));
        await tester.sendEventToBinding(
          PointerScrollEvent(
            position: tester.getCenter(panel),
            scrollDelta: const Offset(0, 140),
          ),
        );
        await tester.pumpAndSettle();
        expect(scroller.position.pixels, greaterThan(0));
        expect(parent.position.pixels, parentOffset);
      }
      await _leave(tester, mouse);
      await _dispose(tester, fixture);
    });
  }

  testWidgets('same ingredient formula does not stretch with a larger window', (
    tester,
  ) async {
    final fixture = await _fixture(tester);
    final book = fixture.controller.itemInfoController;
    final mouse = await _mouse(tester);
    final widths = <double>[];
    for (final size in [const Size(1200, 752), const Size(1500, 940)]) {
      tester.view.physicalSize = size;
      await tester.pumpWidget(
        _host(
          fixture,
          child: Center(
            child: RecipeBookItemInfoHover(
              controller: book,
              name: _essence,
              mode: CraftMode.processing,
              child: const SizedBox(
                key: ValueKey('intrinsic-formula-anchor'),
                width: 48,
                height: 48,
              ),
            ),
          ),
        ),
      );
      await _settleImages(tester);
      await _hover(
        tester,
        mouse,
        find.byKey(const ValueKey('intrinsic-formula-anchor')),
      );
      final panel = _panel(_essence);
      widths.add(tester.getSize(_essenceFormula(panel)).width);
      _expectCompactFormulaGeometry(tester, panel);
      expect(tester.takeException(), isNull);
      await _leave(tester, mouse);
    }
    expect(
      widths.last,
      closeTo(widths.first, .6),
      reason:
          'The same short recipe keeps its measured width, not the window width.',
    );
    await _dispose(tester, fixture);
  });

  testWidgets('long shared hover scrolls without dropping recipe information', (
    tester,
  ) async {
    final fixture = await _fixture(
      tester,
      size: const Size(760, 420),
      scale: 2,
    );
    const name = 'Harmony Draught - Human';
    final book = fixture.controller.itemInfoController;
    final info = book.itemInfoFor(name, mode: CraftMode.alchemy)!;
    expect(info.effects, isNotEmpty);
    await tester.pumpWidget(
      _host(
        fixture,
        child: Center(
          child: RecipeBookItemInfoHover(
            controller: book,
            name: name,
            mode: CraftMode.alchemy,
            child: const SizedBox(
              key: ValueKey('long-hover-anchor'),
              width: 48,
              height: 48,
            ),
          ),
        ),
      ),
    );
    await _settleImages(tester);
    final mouse = await _mouse(tester);
    await _hover(
      tester,
      mouse,
      find.byKey(const ValueKey('long-hover-anchor')),
    );
    final panel = _panel(name);
    final position = tester
        .state<ScrollableState>(
          find.descendant(of: panel, matching: find.byType(Scrollable)).first,
        )
        .position;
    expect(position.pixels, 0);
    expect(position.maxScrollExtent, greaterThan(0));
    final rect = tester.getRect(panel);
    expect(rect.top, greaterThanOrEqualTo(0));
    expect(rect.bottom, lessThanOrEqualTo(420));
    final content = _panelText(tester, name).join(' ');
    for (final effect in info.effects) {
      expect(content, contains(effect));
    }
    await mouse.moveTo(tester.getCenter(panel));
    await tester.sendEventToBinding(
      PointerScrollEvent(
        position: tester.getCenter(panel),
        scrollDelta: const Offset(0, 180),
      ),
    );
    await tester.pumpAndSettle();
    expect(position.pixels, greaterThan(0));
    expect(fixture.transport.requests, isEmpty);
    expect(tester.takeException(), isNull);
    await _leave(tester, mouse);
    await _dispose(tester, fixture);
  });

  testWidgets(
    'constrained enlarged formula wraps long names without shrinking',
    (tester) async {
      final fixture = await _fixture(
        tester,
        size: const Size(460, 752),
        scale: 2,
      );
      await tester.pumpWidget(
        _host(
          fixture,
          child: Center(
            child: RecipeBookItemInfoHover(
              controller: fixture.controller.itemInfoController,
              name: _essence,
              mode: CraftMode.processing,
              child: const SizedBox(
                key: ValueKey('wrapped-formula-anchor'),
                width: 48,
                height: 48,
              ),
            ),
          ),
        ),
      );
      await _settleImages(tester);
      final mouse = await _mouse(tester);
      await _hover(
        tester,
        mouse,
        find.byKey(const ValueKey('wrapped-formula-anchor')),
      );
      final panel = _panel(_essence);
      final formula = _essenceFormula(panel);
      _expectCompactFormulaGeometry(tester, panel);
      final row = find.descendant(
        of: formula,
        matching: find.byKey(
          RecipeBookKeys.itemInfoMaterial(_crystal, null, _essence),
        ),
      );
      final name = find.descendant(of: row, matching: find.text(_essence));
      final paragraph = tester.renderObject<RenderParagraph>(name);
      final painter = TextPainter(
        text: paragraph.text,
        textDirection: paragraph.textDirection,
        textScaler: paragraph.textScaler,
      )..layout(maxWidth: paragraph.size.width);
      expect(painter.computeLineMetrics().length, greaterThan(1));
      painter.dispose();
      expect(paragraph.textScaler.scale(12.5), 25);
      expect(paragraph.maxLines, isNull);
      expect(paragraph.overflow, isNot(TextOverflow.ellipsis));
      final quantity = find.descendant(of: row, matching: find.text('×450'));
      expect(
        tester.getRect(quantity).right,
        lessThanOrEqualTo(tester.getRect(formula).right),
      );
      final position = tester
          .state<ScrollableState>(
            find.descendant(of: panel, matching: find.byType(Scrollable)).first,
          )
          .position;
      position.jumpTo(position.maxScrollExtent);
      await tester.pumpAndSettle();
      final viewport = tester.getRect(
        find
            .descendant(of: panel, matching: find.byType(SingleChildScrollView))
            .first,
      );
      expect(tester.getRect(row).bottom, lessThanOrEqualTo(viewport.bottom));
      await _captureImage(tester, 'essence-formula-wrapped-200');
      expect(fixture.transport.requests, isEmpty);
      expect(tester.takeException(), isNull);
      await _leave(tester, mouse);
      await _dispose(tester, fixture);
    },
  );
}

Finder _essenceFormula(Finder panel) => find.descendant(
  of: panel,
  matching: find.byKey(RecipeBookKeys.itemInfoFormula(_crystal, null, 1)),
);

double _naturalTextWidth(WidgetTester tester, Finder text) {
  final paragraph = tester.renderObject<RenderParagraph>(text);
  final painter = TextPainter(
    text: paragraph.text,
    textDirection: paragraph.textDirection,
    textScaler: paragraph.textScaler,
  )..layout();
  try {
    return painter.width;
  } finally {
    painter.dispose();
  }
}

void _expectCompactFormulaGeometry(WidgetTester tester, Finder panel) {
  final formula = _essenceFormula(panel);
  final formulaRect = tester.getRect(formula);
  final viewport = tester.getRect(
    find
        .descendant(of: panel, matching: find.byType(SingleChildScrollView))
        .first,
  );
  expect(
    formulaRect.center.dx,
    closeTo(viewport.center.dx, .6),
    reason: 'The recipe block is centered within the reading card.',
  );

  final names = <double>[];
  final quantities = <double>[];
  final gaps = <double>[];
  final quantityRightEdges = <double>[];
  for (final material in [('Magical Shard', '×300'), (_essence, '×450')]) {
    final row = find.descendant(
      of: formula,
      matching: find.byKey(
        RecipeBookKeys.itemInfoMaterial(_crystal, null, material.$1),
      ),
    );
    final name = find.descendant(of: row, matching: find.text(material.$1));
    final quantity = find.descendant(of: row, matching: find.text(material.$2));
    final naturalName = _naturalTextWidth(tester, name);
    names.add(naturalName);
    quantities.add(_naturalTextWidth(tester, quantity));
    gaps.add(
      tester.getRect(quantity).left - tester.getRect(name).left - naturalName,
    );
    quantityRightEdges.add(tester.getRect(quantity).right);
  }
  expect(
    quantityRightEdges.last,
    closeTo(quantityRightEdges.first, .6),
    reason: 'Quantities share one compact, aligned column.',
  );
  final longestName = names.reduce((a, b) => a > b ? a : b);
  final widestQuantity = quantities.reduce((a, b) => a > b ? a : b);
  final measuredRowWidth = 24 + 24 + 8 + longestName + 12 + widestQuantity;
  expect(
    formulaRect.width,
    lessThanOrEqualTo(measuredRowWidth + 6),
    reason: 'No window-sized empty area is added after the short recipe rows.',
  );
  if (formulaRect.width >= measuredRowWidth - 2) {
    for (var index = 0; index < names.length; index++) {
      expect(gaps[index], greaterThanOrEqualTo(9));
      expect(
        gaps[index],
        lessThanOrEqualTo(
          longestName - names[index] + widestQuantity - quantities[index] + 18,
        ),
        reason:
            'Only the shared label-column difference separates name and quantity.',
      );
    }
  }
}

void _expectConcreteCrystalEffects(WidgetTester tester, Finder panel) {
  final content = tester
      .widgetList<Text>(find.descendant(of: panel, matching: find.byType(Text)))
      .map((widget) => widget.data ?? widget.textSpan!.toPlainText())
      .toList();
  for (final effect in ['All AP -14', 'All Accuracy +84', 'Max Stamina +50']) {
    expect(content, contains(effect));
  }
  expect(content.join('\n').toLowerCase(), isNot(contains('equip for')));
  expect(content.join('\n').toLowerCase(), isNot(contains('listed stats')));
}

void _expectCompleteFormula(WidgetTester tester, Finder panel) {
  final viewport = tester.getRect(
    find
        .descendant(of: panel, matching: find.byType(SingleChildScrollView))
        .first,
  );
  final formula = find.descendant(
    of: panel,
    matching: find.byKey(RecipeBookKeys.itemInfoFormula(_crystal, null, 1)),
  );
  expect(formula, findsOneWidget);
  final rect = tester.getRect(formula);
  expect(rect.left, greaterThanOrEqualTo(viewport.left));
  expect(rect.top, greaterThanOrEqualTo(viewport.top));
  expect(rect.right, lessThanOrEqualTo(viewport.right));
  expect(
    rect.bottom,
    lessThanOrEqualTo(viewport.bottom),
    reason:
        'The entire two-ingredient recipe, including its lower border, must be '
        'visible before scrolling. Formula: $rect; viewport: $viewport.',
  );
  for (final material in [('Magical Shard', '×300'), (_essence, '×450')]) {
    final row = find.descendant(
      of: formula,
      matching: find.byKey(
        RecipeBookKeys.itemInfoMaterial(_crystal, null, material.$1),
      ),
    );
    expect(row, findsOneWidget);
    expect(
      find.descendant(of: row, matching: find.text(material.$1)),
      findsOneWidget,
    );
    expect(
      find.descendant(of: row, matching: find.text(material.$2)),
      findsOneWidget,
    );
    expect(
      find.descendant(of: row, matching: find.byType(ModeItemIcon)),
      findsOneWidget,
    );
    final rect = tester.getRect(row);
    expect(rect.top, greaterThanOrEqualTo(viewport.top));
    expect(rect.bottom, lessThanOrEqualTo(viewport.bottom));
  }
}

void _expectSectionSpacing(WidgetTester tester, Finder panel, double scale) {
  Finder text(String name) =>
      find.descendant(of: panel, matching: find.text(name));
  final obtain = tester.getRect(text('How to Obtain'));
  final note = tester.getRect(
    find.descendant(
      of: panel,
      matching: find.byWidgetPredicate(
        (widget) =>
            widget is Text &&
            widget.data?.startsWith('Chance from Essence of Dawn Boxes') ==
                true,
      ),
    ),
  );
  final usedFor = tester.getRect(text('Used For'));
  final output = tester.getRect(text(_crystal));
  final gapScale = scale.clamp(1.0, 1.5);
  expect(note.top - obtain.bottom, greaterThanOrEqualTo(8 * gapScale - .1));
  expect(usedFor.top - note.bottom, greaterThanOrEqualTo(20 * gapScale - .1));
  expect(output.top - usedFor.bottom, greaterThanOrEqualTo(8 * gapScale - .1));
  final paragraph = tester.renderObject<RenderParagraph>(text('How to Obtain'));
  expect(
    paragraph.textScaler.scale(12),
    closeTo(12 * scale, .01),
    reason: 'Adaptive width must not shrink the requested text size.',
  );
}

Finder _region(String id) => find.byKey(ValueKey('opportunity-item:$id'));
Finder _panel(String name) => find.byKey(RecipeBookKeys.itemInfo(name));
Finder _icon(Finder scope, String name) => find
    .descendant(
      of: scope,
      matching: find.byWidgetPredicate(
        (widget) => widget is ModeItemIcon && widget.name == name,
      ),
    )
    .first;
List<String> _panelText(WidgetTester tester, String name) => tester
    .widgetList<Text>(
      find.descendant(of: _panel(name), matching: find.byType(Text)),
    )
    .map((widget) => widget.data ?? widget.textSpan!.toPlainText())
    .toList();

Future<TestGesture> _mouse(WidgetTester tester) async {
  final mouse = await tester.createGesture(kind: ui.PointerDeviceKind.mouse);
  await mouse.addPointer(location: Offset.zero);
  addTearDown(mouse.removePointer);
  return mouse;
}

Future<void> _hover(
  WidgetTester tester,
  TestGesture mouse,
  Finder target,
) async {
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
  await mouse.moveTo(tester.getCenter(target));
  await tester.pump(const Duration(milliseconds: 500));
  await _settleImages(tester);
}

Future<void> _leave(WidgetTester tester, TestGesture mouse) async {
  await mouse.moveTo(const Offset(2, 2));
  await tester.pump(const Duration(milliseconds: 600));
  await tester.pumpAndSettle();
  expect(find.byKey(RecipeBookKeys.itemInfo(_essence)), findsNothing);
  expect(find.byKey(RecipeBookKeys.itemInfo(_crystal)), findsNothing);
}

Future<void> _openCrystal(WidgetTester tester) async {
  final icon = _icon(_region('craft-card:$_crystal'), _crystal);
  await tester.ensureVisible(icon);
  await tester.pumpAndSettle();
  expect(icon.hitTestable(), findsOneWidget);
  await tester.tap(icon);
  await _settleImages(tester);
  expect(_region('ingredient:$_essence'), findsOneWidget);
}

Widget _host(_Fixture fixture, {Widget? child}) => RepaintBoundary(
  key: _capture,
  child: OpportunityItemActionsScope(
    externalActions: PlannerExternalActions(
      openRecipeBook: (_) {},
      copyName: (name) async => fixture.copied.add(name),
      checkPrices: (_) async => throw StateError('Hover must not check prices'),
    ),
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      home: child == null
          ? Scaffold(
              body: OpportunitiesWorkspace(controller: fixture.controller),
            )
          : OpportunitiesTheme(child: Scaffold(body: child)),
    ),
  ),
);

class _Fixture {
  _Fixture(this.harness, this.controller, this.transport);
  final ApplicationTestHarness harness;
  final OpportunitiesController controller;
  final _NoNetwork transport;
  final copied = <String>[];
  bool disposed = false;
}

Future<_Fixture> _fixture(
  WidgetTester tester, {
  Size size = const Size(1200, 752),
  double scale = 1,
}) async {
  configureApplicationTestSurface(tester, size, textScaleFactor: scale);
  final fixture = (await tester.runAsync(() async {
    final harness = await ApplicationTestHarness.create(
      activeMode: CraftMode.processing,
    );
    final catalog = CatalogRepository(harness.bundle.catalog);
    final now = DateTime.utc(2026, 9, 12, 3);
    final directory = Directory(
      '${harness.temporaryDirectory.path}/opportunities',
    );
    final transport = _NoNetwork();
    final ids = <String>{
      ...(harness.bundle.catalog.supportingData['marketIds']! as Map).values
          .map((id) => '$id'),
      for (final mode in harness.bundle.controller.modes.values)
        for (final recipe in mode.recipes.values)
          if (recipe.marketId != null) recipe.marketId!,
    };
    await OpportunityMarketCacheStore(
      directory: directory,
      utcNow: () => now,
    ).save({
      'eu': {
        for (final id in ids)
          id: OpportunityMarketItem(
            itemId: id,
            basePrice: 1000,
            stock: 100000,
            quoteFetchedAt: now,
            bookFetchedAt: now,
            asks: const [OpportunityMarketLevel(price: 1000, quantity: 100000)],
            bids: const [OpportunityMarketLevel(price: 1000, quantity: 100000)],
          ),
      },
    });
    final controller = OpportunitiesController(
      appController: harness.bundle.controller,
      catalog: catalog,
      directory: directory,
      clock: () => now,
      serviceFactory: (region) => OpportunityMarketService(
        region: region,
        transport: transport,
        utcNow: () => now,
      ),
    );
    await controller.ready;
    controller.change((preferences) {
      preferences.mode = CraftMode.processing;
      preferences.craftSearch = _crystal;
      preferences.profitableOnly = false;
    });
    await controller.calculationSettled;
    expect(
      controller.recipes[_crystal]!.ingredients.map(
        (ingredient) => ingredient.name,
      ),
      contains(_essence),
    );
    return _Fixture(harness, controller, transport);
  }))!;
  addTearDown(() => _dispose(tester, fixture));
  return fixture;
}

Future<void> _dispose(WidgetTester tester, _Fixture fixture) async {
  if (fixture.disposed) return;
  fixture.disposed = true;
  Tooltip.dismissAllToolTips();
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.runAsync(() async {
    await fixture.controller.flush();
    fixture.controller.dispose();
    await fixture.harness.dispose();
  });
}

class _NoNetwork implements OpportunityMarketTransport {
  final requests = <Uri>[];
  @override
  Future<OpportunityHttpResponse> post(
    Uri uri, {
    required Map<String, String> headers,
    required String body,
    Future<void>? abortTrigger,
  }) async {
    requests.add(uri);
    throw StateError('All market data is preloaded; no requests are expected.');
  }

  @override
  void close() {}
}

Future<void> _settleImages(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 200));
  for (final element in find.byType(Image).evaluate().toList()) {
    await tester.runAsync(
      () => precacheImage((element.widget as Image).image, element),
    );
  }
  await tester.pump(const Duration(milliseconds: 200));
}

Future<void> _captureImage(WidgetTester tester, String name) async {
  final directory = Platform.environment['OPPORTUNITY_HOVER_CAPTURE_DIR'];
  if (directory == null || directory.isEmpty) return;
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(_capture),
  );
  await tester.runAsync(() async {
    final image = await boundary.toImage();
    try {
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      await File(
        '$directory/$name.png',
      ).writeAsBytes(bytes!.buffer.asUint8List());
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
    'Segoe UI': [
      '$win/Fonts/segoeui.ttf',
      '$win/Fonts/seguisb.ttf',
      '$win/Fonts/segoeuib.ttf',
    ],
    'Georgia': ['$win/Fonts/georgia.ttf', '$win/Fonts/georgiab.ttf'],
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
