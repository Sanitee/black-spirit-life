import 'dart:io';
import 'dart:ui' as ui;

import 'package:bdo_craft_planner_flutter/app/app.dart';
import 'package:bdo_craft_planner_flutter/app/workspace/application_copy_toast.dart';
import 'package:bdo_craft_planner_flutter/domain/models/craft_mode.dart';
import 'package:bdo_craft_planner_flutter/features/planner/planner_contracts.dart';
import 'package:bdo_craft_planner_flutter/features/planner/planner_keys.dart';
import 'package:bdo_craft_planner_flutter/features/recipe_book/recipe_book.dart';
import 'package:bdo_craft_planner_flutter/features/recipe_book/recipe_book_item_info.dart';
import 'package:bdo_craft_planner_flutter/features/shared/item_name_copy_scope.dart';
import 'package:bdo_craft_planner_flutter/visual/visual.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/application_test_harness.dart';
import 'recipe_book_scroll_support.dart';
import 'recipe_book_test_support.dart';

const _recipe = ValueKey('attached-reference-tab:recipe');
const _used = ValueKey('attached-reference-tab:used');
const _capture = ValueKey('consistent-item-capture');
const _name = 'Elixir of Detection';

void main() {
  setUpAll(_loadFonts);
  for (final spec in RetainedThemeRegistry.themes) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('nested real Recipe Book hover and pin ${spec.id} $scale', (
        tester,
      ) async {
        const size = Size(1200, 900);
        configureApplicationTestSurface(tester, size, textScaleFactor: scale);
        final original = (await tester.runAsync(
          () => ApplicationTestHarness.create(
            backgroundId: spec.isStandard ? 'greenhouse' : spec.id,
            activeMode: CraftMode.alchemy,
          ),
        ))!;
        final harness = original.rebindControllerInCurrentZone();
        await tester.runAsync(original.disposeControllerOnly);
        try {
          final before = harness.bundle.controller.active.state.value.toJson();
          await tester.pumpWidget(
            RepaintBoundary(
              key: _capture,
              child: BdoCraftPlannerApp(
                enableOpportunityAutoCheck: false,
                applicationFuture: Future.value(harness.bundle),
                marketGateway: const EmptyMarketGateway(),
              ),
            ),
          );
          await tester.pumpAndSettle();
          await tester.tap(find.byKey(PlannerActionKeys.p03));
          await tester.pumpAndSettle();
          final book = tester
              .widget<RecipeBookModal>(find.byType(RecipeBookModal))
              .controller;
          book.setSearch(_name);
          await tester.pumpAndSettle();
          await tapBookDetails(tester, _name);
          await tester.pumpAndSettle();
          final anchor = find
              .descendant(
                of: find.byKey(RecipeBookKeys.previewPanel),
                matching: find.byType(RecipeBookItemIcon),
              )
              .first;
          final background = tester
              .stateList<ScrollableState>(find.byType(Scrollable))
              .toList();
          final offsets = [for (final s in background) s.position.pixels];
          final mouse = await tester.createGesture(
            kind: ui.PointerDeviceKind.mouse,
          );
          await mouse.addPointer(location: Offset.zero);
          addTearDown(mouse.removePointer);
          await mouse.moveTo(tester.getCenter(anchor));
          await tester.pump(const Duration(milliseconds: 600));
          await tester.pumpAndSettle();
          final hover = find.byKey(RecipeBookKeys.itemInfo(_name));
          expect(hover, findsOneWidget);
          expect(find.byKey(_recipe), findsOneWidget);
          expect(find.byKey(_used), findsOneWidget);
          expect(find.text('Recipe & materials'), findsNothing);
          final info = book.itemInfoFor(_name)!;
          expect(info.effects, isNotEmpty);
          for (final effect in info.effects) {
            expect(
              find.descendant(of: hover, matching: find.text(effect)),
              findsOneWidget,
            );
          }
          final formula = info.acquisitionFormulas.first;
          final material = find.byKey(
            RecipeBookKeys.itemInfoMaterial(
              _name,
              formula.variantId,
              formula.ingredients.first.name,
            ),
          );
          final itemText = find.descendant(
            of: material,
            matching: find.text(formula.ingredients.first.name),
          );
          final amount = find.descendant(
            of: material,
            matching: find.text(
              '×${formula.ingredients.first.quantity.toInt()}',
            ),
          );
          expect(
            tester.getRect(amount).left - tester.getRect(itemText).right,
            closeTo(8, .1),
          );
          if (scale == 1) {
            final lastMaterial = find.byKey(
              RecipeBookKeys.itemInfoMaterial(
                _name,
                formula.variantId,
                formula.ingredients.last.name,
              ),
            );
            expect(
              tester.getRect(lastMaterial).bottom,
              lessThanOrEqualTo(
                tester
                    .getRect(
                      find.byKey(const ValueKey('attached-reference-scroll')),
                    )
                    .bottom,
              ),
              reason: 'One full recipe fits; additional notes may scroll.',
            );
          }
          final rect = tester.getRect(hover);
          expect(rect.left, greaterThanOrEqualTo(0));
          expect(rect.right, lessThanOrEqualTo(size.width));
          expect(rect.top, greaterThanOrEqualTo(0));
          expect(rect.bottom, lessThanOrEqualTo(size.height));
          await _captureImage(
            tester,
            '${spec.id}-${scale.toInt()}-hover-recipe',
          );
          // Copy from the deeply nested hover uses the shell's top toast,
          // above the Recipe Book barrier, without dismissing the reference.
          await mouse.moveTo(tester.getCenter(itemText));
          expect(
            ItemNameCopyScope.maybeOf(tester.element(itemText)),
            isNotNull,
          );
          final copies = <String>[];
          tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
            SystemChannels.platform,
            (call) async {
              if (call.method == 'Clipboard.setData') {
                copies.add((call.arguments as Map)['text'] as String);
              }
              return null;
            },
          );
          addTearDown(
            () => tester.binding.defaultBinaryMessenger
                .setMockMethodCallHandler(SystemChannels.platform, null),
          );
          await mouse.down(tester.getCenter(itemText));
          await mouse.up();
          await tester.pumpAndSettle();
          expect(copies, [formula.ingredients.first.name]);
          expect(find.byType(SnackBar), findsNothing);
          expect(
            find.text('Copied ${formula.ingredients.first.name}'),
            findsOneWidget,
          );
          final toast = find.byKey(ApplicationCopyToastKeys.surface);
          expect(tester.getRect(toast).top, lessThan(100));
          expect(tester.getSize(toast).width, lessThan(500));
          expect(toast.hitTestable(), findsNothing);
          expect(hover, findsOneWidget);
          await _captureImage(tester, '${spec.id}-${scale.toInt()}-copy');
          await tester.pump(const Duration(milliseconds: 1400));
          expect(toast, findsNothing);
          // Real mouse clicks, not controller calls: the tooltip must survive.
          await mouse.moveTo(tester.getCenter(find.byKey(_used)));
          await mouse.down(tester.getCenter(find.byKey(_used)));
          await mouse.up();
          await tester.pumpAndSettle();
          expect(hover, findsOneWidget);
          expect(find.text('Berserk Draught'), findsWidgets);
          await mouse.moveTo(
            tester.getCenter(
              find.byKey(const ValueKey('attached-reference-scroll')),
            ),
          );
          await tester.pump(const Duration(milliseconds: 600));
          expect(hover, findsOneWidget);
          final header = tester.getRect(find.byKey(_used));
          for (final delta in [100.0, 100000.0, -100000.0]) {
            await tester.sendEventToBinding(
              PointerScrollEvent(
                kind: ui.PointerDeviceKind.mouse,
                position: tester.getCenter(
                  find.byKey(const ValueKey('attached-reference-scroll')),
                ),
                scrollDelta: Offset(0, delta),
              ),
            );
            await tester.pumpAndSettle();
            expect(hover, findsOneWidget);
            expect(tester.getRect(find.byKey(_used)), header);
            expect([for (final s in background) s.position.pixels], offsets);
          }
          await _captureImage(tester, '${spec.id}-${scale.toInt()}-hover-used');
          await mouse.moveTo(const Offset(1, 1));
          await tester.pump(const Duration(milliseconds: 600));
          await tester.pumpAndSettle();
          expect(hover, findsNothing);
          await tester.tap(anchor);
          await tester.pumpAndSettle();
          expect(find.byType(ItemReferenceCard), findsOneWidget);
          expect(find.byKey(_used), findsOneWidget);
          expect(find.text('Recipe & materials'), findsNothing);
          await _captureImage(tester, '${spec.id}-${scale.toInt()}-pinned');
          final pinnedName = find.descendant(
            of: find.byType(ItemReferenceCard),
            matching: find.text(formula.ingredients.first.name),
          );
          await tester.tap(pinnedName);
          await tester.pumpAndSettle();
          expect(find.byKey(ApplicationCopyToastKeys.surface), findsOneWidget);
          expect(find.byType(SnackBar), findsNothing);
          // Disposing the app with a live toast is covered by the finally block.
          final secondName = formula.ingredients[1].name;
          await tester.tap(
            find.descendant(
              of: find.byType(ItemReferenceCard),
              matching: find.text(secondName),
            ),
          );
          await tester.pumpAndSettle();
          expect(find.byKey(ApplicationCopyToastKeys.surface), findsOneWidget);
          expect(find.text('Copied $secondName'), findsOneWidget);
          expect(
            find.text('Copied ${formula.ingredients.first.name}'),
            findsNothing,
          );
          expect(copies, [
            formula.ingredients.first.name,
            formula.ingredients.first.name,
            secondName,
          ]);
          await tester.sendKeyEvent(LogicalKeyboardKey.escape);
          await tester.pumpAndSettle();
          expect(find.byType(ItemReferenceCard), findsNothing);
          expect(find.byKey(RecipeBookKeys.previewPanel), findsOneWidget);
          expect(harness.bundle.controller.active.state.value.toJson(), before);
          expect(tester.takeException(), isNull);
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          await harness.disposeControllerOnly();
          await tester.runAsync(
            () => harness.temporaryDirectory.delete(recursive: true),
          );
        }
      });
    }
  }

  testWidgets(
    'passive custom-art previews keep all facts without dead controls',
    (tester) async {
      configureApplicationTestSurface(tester, const Size(1000, 900));
      final environment = buildRecipeBookTestEnvironment();
      addTearDown(environment.dispose);
      final book = RecipeBookController(
        modeController: environment.application.active,
        catalogRepository: environment.catalogRepository,
        callingContext: RecipeBookCallingContext.planner,
        allowedTargets: environment.application.active.craftableNames,
      );
      addTearDown(book.dispose);
      final formula = book
          .itemInfoFor('Clear Liquid Reagent')!
          .acquisitionFormulas
          .first;
      const iconKey = ValueKey('exact-exchange-art');
      const anchorKey = ValueKey('passive-artwork');
      await tester.pumpWidget(
        MaterialApp(
          home: ThemeSpecScope(
            spec: SakuraNightGardenSpec.theme,
            child: Scaffold(
              body: Center(
                child: RecipeBookItemInfoHover(
                  controller: book,
                  name: 'Clear Liquid Reagent',
                  interactivePreview: false,
                  referenceIcon: const SizedBox(
                    key: iconKey,
                    width: 36,
                    height: 36,
                  ),
                  info: RecipeBookItemInfo(
                    title: 'Exact exchange item',
                    kind: 'Material',
                    summary: 'Short description.',
                    acquisitionFormulas: [formula],
                    effects: ['Exact effect.'],
                    acquisitionNotes: ['Exact source.'],
                    uses: ['Exact use.'],
                    notes: ['Exact restriction.'],
                  ),
                  child: const SizedBox(key: anchorKey, width: 48, height: 48),
                ),
              ),
            ),
          ),
        ),
      );
      final mouse = await tester.createGesture(
        kind: ui.PointerDeviceKind.mouse,
      );
      await mouse.addPointer(location: Offset.zero);
      addTearDown(mouse.removePointer);
      await mouse.moveTo(tester.getCenter(find.byKey(anchorKey)));
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pumpAndSettle();
      expect(find.byKey(iconKey), findsOneWidget);
      for (final text in [
        'Short description.',
        'Exact effect.',
        'Exact source.',
        'Exact use.',
        'Exact restriction.',
      ]) {
        expect(find.text(text), findsOneWidget);
      }
      expect(find.byKey(_recipe), findsNothing);
      expect(find.byKey(_used), findsNothing);
      expect(find.text('Use recipe'), findsNothing);
      expect(
        find.byKey(const ValueKey('attached-reference-scroll')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'an open reference follows live theme changes without losing its tab',
    (tester) async {
      configureApplicationTestSurface(tester, const Size(900, 700));
      final environment = buildRecipeBookTestEnvironment();
      addTearDown(environment.dispose);
      final book = RecipeBookController(
        modeController: environment.application.active,
        catalogRepository: environment.catalogRepository,
        callingContext: RecipeBookCallingContext.planner,
        allowedTargets: environment.application.active.craftableNames,
      );
      addTearDown(book.dispose);
      const info = RecipeBookItemInfo(
        title: 'Material',
        kind: 'Material',
        summary: 'A source.',
        uses: ['A related recipe.'],
      );
      for (final spec in [
        ...RetainedThemeRegistry.themes,
        SakuraNightGardenSpec.theme,
      ]) {
        await tester.pumpWidget(
          MaterialApp(
            theme: spec.materialTheme(),
            home: ThemeSpecScope(
              spec: spec,
              child: Scaffold(
                body: Center(
                  child: ItemReferenceCard(
                    controller: book,
                    mode: CraftMode.alchemy,
                    name: info.title,
                    info: info,
                    maxWidth: 480,
                    spec: spec,
                    icon: const SizedBox.square(dimension: 44),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final material = tester.widget<Material>(
          find
              .descendant(
                of: find.byType(ItemReferenceCard),
                matching: find.byType(Material),
              )
              .first,
        );
        expect(
          material.color,
          spec.isSakuraNightGarden
              ? const Color(0xFF191619)
              : spec.palette.surfaceRaised,
        );
        await tester.tap(find.byKey(_used));
        await tester.pumpAndSettle();
        expect(find.text('A related recipe.'), findsOneWidget);
        expect(tester.takeException(), isNull);
      }
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
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
  for (final font in {
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
    final loader = FontLoader(font.key);
    for (final file in font.value) {
      loader.addFont(File(file).readAsBytes().then(ByteData.sublistView));
    }
    await loader.load();
  }
}

Future<void> _captureImage(WidgetTester tester, String name) async {
  final directory = Platform.environment['BSL_CONSISTENT_ITEM_CAPTURE_DIR'];
  if (directory == null) return;
  await tester.runAsync(() async {
    await Future.wait([
      for (final e in find.byType(Image).evaluate())
        precacheImage((e.widget as Image).image, e),
    ]);
  });
  await tester.pumpAndSettle();
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(_capture),
  );
  await tester.runAsync(() async {
    await Directory(directory).create(recursive: true);
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
