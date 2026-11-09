import 'dart:io';
import 'dart:ui' as ui;
import 'package:bdo_craft_planner_flutter/data/catalog/bundled_catalog_parser.dart';
import 'package:bdo_craft_planner_flutter/data/catalog/catalog_repository.dart';
import 'package:bdo_craft_planner_flutter/data/market/shared_market_repository.dart';
import 'package:bdo_craft_planner_flutter/domain/models/catalog_models.dart';
import 'package:bdo_craft_planner_flutter/domain/models/craft_mode.dart';
import 'package:bdo_craft_planner_flutter/domain/state/state_copy.dart';
import 'package:bdo_craft_planner_flutter/features/planner/planner_choice_market.dart';
import 'package:bdo_craft_planner_flutter/features/planner/planner_contracts.dart';
import 'package:bdo_craft_planner_flutter/features/recipe_book/recipe_book.dart';
import 'package:bdo_craft_planner_flutter/features/recipe_book/recipe_book_used_in_panel.dart';
import 'package:bdo_craft_planner_flutter/shared/overlays/anchored_popover.dart';
import 'package:bdo_craft_planner_flutter/visual/visual.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import '../../support/choice_market_transport.dart';
import '../../support/substitute_chooser_helpers.dart';
import '../planner/planner_choice_market_test.dart' show settle;
import '../planner/planner_review_projection_test.dart' as fixture;
import 'recipe_book_availability_test.dart'
    show checkColumnAlignment, checkBadgeLines;

void main() {
  final catalog = const BundledCatalogParser().parse(
    File('assets/data/app-data.json').readAsStringSync(),
  );
  final repo = CatalogRepository.cached(catalog);
  setUpAll(() async {
    for (final e in {
      'Segoe UI': [
        'C:/Windows/Fonts/segoeui.ttf',
        'C:/Windows/Fonts/seguisb.ttf',
      ],
      'Georgia': [
        'C:/Windows/Fonts/georgia.ttf',
        'C:/Windows/Fonts/georgiab.ttf',
      ],
      'MaterialIcons': [
        'D:/Tools/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
      ],
    }.entries) {
      final loader = FontLoader(e.key);
      for (final p in e.value) {
        loader.addFont(File(p).readAsBytes().then(ByteData.sublistView));
      }
      await loader.load();
    }
  });
  for (final spec in RetainedThemeRegistry.themes) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('Used for availability ${spec.id} $scale', (tester) async {
        await verify(tester, spec, scale, 1440, catalog, repo);
      });
    }
  }
  testWidgets('Used for narrow viewport scrolls rather than clipping names', (
    tester,
  ) async {
    await verify(
      tester,
      RetainedThemeRegistry.sakuraNightGarden,
      2,
      720,
      catalog,
      repo,
    );
  });
}

Future<void> verify(
  WidgetTester tester,
  ThemeSpec spec,
  double scale,
  double width,
  CatalogSnapshot catalog,
  CatalogRepository repo,
) async {
  tester.view.physicalSize = Size(width, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final app = fixture.controller(catalog, CraftMode.cooking, 'Aloe Cookie', 1);
  final book = RecipeBookController(
    modeController: app.active,
    catalogRepository: repo,
    callingContext: RecipeBookCallingContext.planner,
    allowedTargets: ['Aloe Cookie'],
  );
  app.active.updateState(
    (s) => s.copyWith(
      inventory: {
        'Aloe': 120,
        'Corn Dough': 45,
        'Sugar': 0,
        'Cooking Honey': 60,
      },
    ),
    immediate: true,
  );
  final entry = book
      .usedInFor('Aloe')
      .entries
      .firstWhere((e) => e.name == 'Aloe Cookie');
  final transport = ChoiceMarketTransport();
  transport.values[repo.bundledMarketId('Corn Dough')!] = (
    price: 480,
    stock: 0,
    preorders: 28500,
  );
  final broker = SharedMarketRepository(
    transport: transport,
    requestSpacing: Duration.zero,
  );
  addTearDown(book.dispose);
  addTearDown(app.dispose);
  addTearDown(broker.dispose);
  await tester.pumpWidget(
    MaterialApp(
      theme: spec.materialTheme(),
      home: ThemeSpecScope(
        spec: spec,
        child: PlannerChoiceMarketScope(
          repository: broker,
          child: MediaQuery(
            data: MediaQueryData(
              size: Size(width, 1000),
              textScaler: TextScaler.linear(scale),
            ),
            child: Scaffold(
              body: Align(
                alignment: Alignment.topLeft,
                child: Padding(
                  padding: const EdgeInsets.all(30),
                  child: AnchoredPopover(
                    overlayId: 'test-used',
                    contentSizedWidth: true,
                    preferredWidth: width - 24,
                    maximumHeight: 976,
                    placement: AnchoredPopoverPlacement.beside,
                    anchorBuilder: (context, toggle, isOpen) => TextButton(
                      onPressed: toggle,
                      child: const Text('Used for'),
                    ),
                    popoverBuilder: (context, close) => RepaintBoundary(
                      key: const ValueKey('used-capture'),
                      child: RecipeBookUsedInPanel(
                        controller: book,
                        sourceName: 'Aloe',
                        snapshot: RecipeBookUseSnapshot(
                          itemName: 'Aloe',
                          entries: [entry],
                        ),
                        onClose: close,
                        onActivate: (selected, variant) =>
                            book.activateUsedIn(selected, variantId: variant) !=
                            null,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('Used for'));
  await tester.pumpAndSettle();
  final panel = find.byKey(RecipeBookKeys.usedInPanel('Aloe'));
  expect(find.byType(RecipeIngredientTable), findsOneWidget);
  expect(
    find.byKey(
      RecipeBookKeys.expandUsedInResult('Aloe', entry.mode.key, entry.name),
    ),
    findsNothing,
  );
  await settle(tester, broker);
  await tester.pumpAndSettle();
  final table = tester.widget<RecipeIngredientTable>(
    find.byType(RecipeIngredientTable),
  );
  expect(
    table.rows.map((r) => r.name),
    entry.routes.first.ingredients.map((i) => i.name),
  );
  expect(
    table.rows.map((r) => r.quantity),
    entry.routes.first.ingredients.map((i) => i.quantity),
  );
  expect(table.rows.map((r) => r.owned), [120, 45, 0, 60]);
  expect(table.rows.where((r) => r.npc).map((r) => r.name), ['Sugar']);
  expect(
    table.marketFor('Corn Dough')?.stockFor(table.now, sharedMarketFreshness),
    0,
  );
  expect(table.marketFor('Corn Dough')?.preorderCount, 28500);
  checkColumnAlignment(tester);
  checkBadgeLines(tester);
  final rect = tester.getRect(panel);
  expect(rect.left, greaterThanOrEqualTo(12));
  expect(rect.right, lessThanOrEqualTo(width - 12));
  expect(rect.top, greaterThanOrEqualTo(12));
  expect(rect.bottom, lessThanOrEqualTo(988));
  if (scale == 1) expect(rect.width, lessThan(850));
  for (final element
      in find
          .descendant(
            of: find.byType(RecipeIngredientTable),
            matching: find.byType(RichText),
          )
          .evaluate()) {
    final paragraph = element.renderObject;
    if (paragraph is! RenderParagraph) continue;
    final value = paragraph.text.toPlainText();
    if (!value.contains('×')) continue;
    final boxes = paragraph.getBoxesForSelection(
      TextSelection(baseOffset: 0, extentOffset: value.length),
      boxHeightStyle: ui.BoxHeightStyle.max,
    );
    expect(boxes.map((b) => b.top).toSet().length, 1, reason: value);
  }
  await tester.runAsync(() async {
    for (final image in tester.widgetList<Image>(find.byType(Image))) {
      await precacheImage(image.image, tester.element(panel));
    }
  });
  await tester.pumpAndSettle();
  expect(tester.takeException(), isNull);
  await tester.runAsync(() async {
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(const ValueKey('used-capture')),
    );
    final image = await boundary.toImage(pixelRatio: 1);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    final file = File(
      'build/used-for-captures/${spec.id}-$scale-${width.toInt()}.png',
    );
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  });
  app.active.commitInventory('Corn Dough', '777');
  await tester.pumpAndSettle();
  expect(
    tester
        .widget<RecipeIngredientTable>(find.byType(RecipeIngredientTable))
        .rows[1]
        .owned,
    777,
  );
  final unchanged = app.active.state.value;
  await openSubstitutes(
    tester,
    entry.name,
    entry.routes.first.ingredients[1].name,
  );
  checkColumnAlignment(tester);
  checkBadgeLines(tester);
  final chooser = tester.widget<RecipeIngredientTable>(substituteChooser());
  expect(chooser.rows.any((r) => r.name == 'Potato Dough'), isTrue);
  await chooseSubstitute(tester, entry.name, 'Potato Dough');
  expect(identical(app.active.state.value, unchanged), isTrue);
  expect(
    tester
        .widget<RecipeIngredientTable>(find.byType(RecipeIngredientTable))
        .rows[1]
        .name,
    'Potato Dough',
  );
  final target = find.byKey(
    RecipeBookKeys.targetUsedInResult('Aloe', entry.mode.key, entry.name),
  );
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
  await tester.tap(target);
  await tester.pumpAndSettle();
  expect(panel, findsNothing);
  expect(book.availabilityFor(entry.name).ingredients[1].name, 'Potato Dough');
  expect(tester.takeException(), isNull);
  book.connectAvailabilityMarket(null);
  await tester.pumpWidget(const SizedBox());
  await tester.pumpAndSettle();
}
