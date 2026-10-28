import 'dart:io';
import 'dart:ui' as ui;

import 'package:bdo_craft_planner_flutter/app/state/planner_application_controller.dart';
import 'package:bdo_craft_planner_flutter/data/catalog/bundled_catalog_parser.dart';
import 'package:bdo_craft_planner_flutter/data/catalog/catalog_repository.dart';
import 'package:bdo_craft_planner_flutter/domain/models/catalog_models.dart';
import 'package:bdo_craft_planner_flutter/domain/models/craft_mode.dart';
import 'package:bdo_craft_planner_flutter/domain/state/planner_state.dart';
import 'package:bdo_craft_planner_flutter/features/planner/planner_contracts.dart';
import 'package:bdo_craft_planner_flutter/features/recipe_book/recipe_book_controller.dart';
import 'package:bdo_craft_planner_flutter/features/recipe_book/recipe_book_item_info_view.dart';
import 'package:bdo_craft_planner_flutter/features/recipe_book/recipe_book_keys.dart';
import 'package:bdo_craft_planner_flutter/features/recipe_book/recipe_book_used_in_panel.dart';
import 'package:bdo_craft_planner_flutter/features/shared/mode_item_icon.dart';
import 'package:bdo_craft_planner_flutter/visual/visual.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _catalyst = 'Concentrated Spellbound Catalyst';
const _capture = ValueKey('reference-layout-capture');

void main() {
  late CatalogSnapshot snapshot;
  late CatalogRepository catalog;
  setUpAll(() async {
    snapshot = const BundledCatalogParser().parse(
      File('assets/data/app-data.json').readAsStringSync(),
    );
    catalog = CatalogRepository(snapshot);
    await _loadFonts();
  });

  testWidgets(
    'all catalogue items, variants and substitutes have decodable bundled artwork',
    (tester) async {
      final artwork = <String, String>{};
      for (final mode in CraftMode.values) {
        final data = snapshot.forMode(mode);
        final names = <String>{...data.items.keys, ...data.iconDataUris.keys};
        for (final recipe in data.items.values) {
          for (final ingredient in [
            ...recipe.ingredients,
            for (final variant in recipe.variants) ...variant.ingredients,
          ]) {
            names.addAll([
              ingredient.name,
              ...ingredient.options,
              ...ingredient.substituteRatios.keys,
            ]);
          }
        }
        for (final name in names) {
          final uri = catalog.iconDataUriAcrossModes(
            mode,
            name,
            preferCleanArtwork: true,
          );
          expect(uri, isNotNull, reason: '${mode.key}: $name');
          artwork[uri!] = name;
        }
      }
      await tester.runAsync(() async {
        for (final entry in artwork.entries) {
          final codec = await ui.instantiateImageCodec(
            UriData.parse(entry.key).contentAsBytes(),
          );
          try {
            final frame = await codec.getNextFrame();
            expect(frame.image.width, greaterThan(0), reason: entry.value);
            expect(frame.image.height, greaterThan(0), reason: entry.value);
            frame.image.dispose();
          } finally {
            codec.dispose();
          }
        }
      });
    },
  );

  testWidgets(
    'recipe and inventory icon defaults find category-missing artwork',
    (tester) async {
      final app = _application(snapshot);
      addTearDown(app.dispose);
      for (final mode in CraftMode.values) {
        final data = snapshot.forMode(mode);
        final names = <String>{...data.items.keys};
        for (final recipe in data.items.values) {
          for (final ingredient in [
            ...recipe.ingredients,
            for (final variant in recipe.variants) ...variant.ingredients,
          ]) {
            names.addAll([
              ingredient.name,
              ...ingredient.options,
              ...ingredient.substituteRatios.keys,
            ]);
          }
        }
        final previouslyMissing = names.where(
          (name) => catalog.iconDataUri(mode, name) == null,
        );
        final book = _book(app, catalog, mode);
        for (final name in previouslyMissing) {
          expect(book.iconDataUriForMode(mode, name), isNotNull, reason: name);
          await tester.pumpWidget(
            MaterialApp(
              home: ThemeSpecScope(
                spec: StandardSpec.theme,
                child: Center(
                  child: ModeItemIcon(
                    controller: app.modes[mode]!,
                    catalogRepository: catalog,
                    name: name,
                    size: 36,
                  ),
                ),
              ),
            ),
          );
          expect(find.byKey(ModeItemIconKeys.image(name)), findsOneWidget);
          expect(find.byKey(ModeItemIconKeys.failure(name)), findsNothing);
        }
        book.dispose();
      }
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  for (final theme in {
    'Sakura': SakuraNightGardenSpec.theme,
    'Green': StandardSpec.theme,
    'Ledger': IlluminatedLedgerSpec.theme,
  }.entries) {
    for (final scale in [1.0, 1.5, 2.0]) {
      testWidgets(
        '${theme.key} Used In shares reference hierarchy at $scale text',
        (tester) async {
          tester.view.devicePixelRatio = 1;
          tester.view.physicalSize = const Size(1200, 1000);
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final app = _application(snapshot);
          final book = _book(app, catalog, CraftMode.alchemy);
          addTearDown(book.dispose);
          addTearDown(app.dispose);
          const name = 'Adaptation Draught';
          final usage = book.usedInFor(name);
          expect(usage.entries, isNotEmpty);
          await tester.pumpWidget(
            MaterialApp(
              theme: theme.value.materialTheme(),
              home: ThemeSpecScope(
                spec: theme.value,
                child: Material(
                  child: MediaQuery(
                    data: MediaQueryData(
                      size: const Size(1200, 1000),
                      textScaler: TextScaler.linear(scale),
                    ),
                    child: Align(
                      alignment: Alignment.topLeft,
                      child: Builder(
                        builder: (context) => RepaintBoundary(
                          key: _capture,
                          child: SizedBox(
                            width: ItemDetailStyle.width(context),
                            child: RecipeBookUsedInPanel(
                              controller: book,
                              sourceName: name,
                              snapshot: usage,
                              onClose: () {},
                              onActivate: (_, _) => true,
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
          await _settleImages(tester);
          expect(tester.takeException(), isNull);
          final title = tester.widget<Text>(find.text(name).first);
          expect(
            title.style!.fontSize,
            ItemDetailStyle.title(theme.value).fontSize,
          );
          final icons = tester
              .widgetList<ModeItemIcon>(find.byType(ModeItemIcon))
              .toList();
          expect(icons.first.size, ItemDetailStyle.headerIcon);
          expect(
            icons
                .skip(1)
                .every((icon) => icon.size == ItemDetailStyle.recipeIcon),
            isTrue,
          );
          expect(find.byIcon(Icons.broken_image_outlined), findsNothing);
          final panel = find.byKey(RecipeBookKeys.usedInPanel(name));
          final last = usage.entries.last;
          final lastRow = find.byKey(
            RecipeBookKeys.usedInResult(name, last.mode.key, last.name),
          );
          expect(
            tester.getRect(panel).bottom - tester.getRect(lastRow).bottom,
            lessThanOrEqualTo(22),
          );
          await _captureImage(tester, '${theme.key}-used-in-$scale');
          final first = usage.entries.first;
          final expand = find.byKey(
            RecipeBookKeys.expandUsedInResult(name, first.mode.key, first.name),
          );
          await tester.tap(expand);
          await _settleImages(tester);
          expect(tester.takeException(), isNull);
          expect(find.byType(ItemDetailGroup), findsOneWidget);
          expect(tester.getRect(panel).bottom, lessThanOrEqualTo(1000));
          await _captureImage(tester, '${theme.key}-used-in-expanded-$scale');
          await tester.tap(expand);
          await tester.pumpAndSettle();
          expect(find.byType(ItemDetailGroup), findsNothing);
          await tester.pumpWidget(const SizedBox.shrink());
        },
      );
      testWidgets('${theme.key} shared reference hierarchy fits at $scale text', (
        tester,
      ) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(1200, 1000);
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final app = _application(snapshot);
        final book = _book(app, catalog, CraftMode.alchemy);
        addTearDown(book.dispose);
        addTearDown(app.dispose);
        for (final name in [
          _catalyst,
          'Essence of Dawn - Accuracy',
          'Perfume of Tenacity',
          'Milk',
        ]) {
          final info = book.itemInfoFor(name)!;
          await tester.pumpWidget(
            MaterialApp(
              theme: theme.value.materialTheme(),
              builder: (context, child) => Material(child: child),
              home: ThemeSpecScope(
                spec: theme.value,
                child: Builder(
                  builder: (context) => MediaQuery(
                    data: MediaQuery.of(
                      context,
                    ).copyWith(textScaler: TextScaler.linear(scale)),
                    child: Align(
                      alignment: Alignment.topLeft,
                      child: Builder(
                        builder: (context) => RepaintBoundary(
                          key: _capture,
                          child: ItemReferenceCard(
                            key: ValueKey(name),
                            controller: book,
                            mode: CraftMode.alchemy,
                            name: name,
                            info: info,
                            maxWidth: itemReferenceCardWidth(context),
                            spec: theme.value,
                            onClose: () {},
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
          await _settleImages(tester);
          final title = tester.widget<Text>(find.text(info.title).first);
          expect(title.style!.fontSize, 20);
          final icons = tester
              .widgetList<ModeItemIcon>(find.byType(ModeItemIcon))
              .toList();
          expect(icons.first.size, 48);
          expect(icons.where((icon) => icon.name == name).first.size, 48);
          expect(find.byIcon(Icons.broken_image_outlined), findsNothing);
          final panel = tester.getRect(find.byType(ItemReferenceCard));
          expect(panel.right, lessThanOrEqualTo(1200));
          expect(panel.bottom, lessThanOrEqualTo(1000));
          if (name == _catalyst) {
            final heading = tester.widget<Text>(
              find.text('Recipe & materials'),
            );
            expect(heading.style!.fontSize, 15);
            final exchange = find.byKey(
              RecipeBookKeys.itemInfoFormula(name, null, 1),
            );
            expect(
              tester.getRect(exchange).left,
              closeTo(tester.getRect(find.text('Recipe & materials')).left, .5),
            );
            expect(find.text('100× batch'), findsOneWidget);
            expect(find.text('10× batch'), findsNothing);
            final catalystRecipe = find.byKey(
              RecipeBookKeys.itemInfoFormula(
                'Fury Draught',
                'simple-alchemy-100x',
                100,
              ),
            );
            expect(catalystRecipe, findsOneWidget);
            expect(
              find.descendant(
                of: catalystRecipe,
                matching: find.text(_catalyst),
              ),
              findsOneWidget,
            );
          }
          expect(tester.takeException(), isNull);
          await _captureImage(
            tester,
            '${theme.key}-${name.replaceAll(RegExp('[^a-zA-Z0-9]+'), '-')}-$scale',
          );
          if (name == _catalyst && theme.key == 'Sakura' && scale == 1.0) {
            tester.view.physicalSize = const Size(1200, 1400);
            await tester.pumpAndSettle();
            tester.element(find.byType(ItemReferenceCard)).markNeedsBuild();
            await tester.pumpAndSettle();
            await _captureImage(tester, 'Sakura-catalyst-complete');
            tester.view.physicalSize = const Size(1200, 1000);
            await tester.pumpAndSettle();
          }
        }
        await tester.pumpWidget(const SizedBox.shrink());
      });
    }
  }
}

PlannerApplicationController _application(CatalogSnapshot catalog) =>
    PlannerApplicationController(
      catalog: catalog,
      initialState: PlannerState(
        applicationVersion: 'reference-layout-test',
        lastSuccessfulWriteUtc: DateTime.utc(2026, 9, 26),
        activeMode: CraftMode.alchemy,
        alchemy: _state(CraftMode.alchemy, 'Clear Liquid Reagent'),
        cooking: _state(CraftMode.cooking, 'Beer'),
        processing: _state(CraftMode.processing, 'Wheat Flour'),
        processingYields: const {},
        marketTax: MarketTax(),
        showDeleteTools: false,
      ),
      saveState: (value) async => value,
    );
ModeState _state(CraftMode mode, String name) => ModeState(
  target: name,
  want: 1,
  bonusTarget: name,
  market: MarketState(),
  appearance: AppearanceSettings.defaultsFor(mode),
);
RecipeBookController _book(
  PlannerApplicationController app,
  CatalogRepository catalog,
  CraftMode mode,
) => RecipeBookController(
  modeController: app.modes[mode]!,
  catalogRepository: catalog,
  callingContext: RecipeBookCallingContext.planner,
  allowedTargets: app.modes[mode]!.craftableNames,
);

Future<void> _settleImages(WidgetTester tester) async {
  await tester.pumpAndSettle();
  final context = tester.element(find.byKey(_capture));
  final images = tester
      .widgetList<Image>(find.byType(Image))
      .map((image) => image.image)
      .toSet();
  await tester.runAsync(
    () => Future.wait(images.map((image) => precacheImage(image, context))),
  );
  await tester.pumpAndSettle();
}

Future<void> _captureImage(WidgetTester tester, String name) async {
  const directory = String.fromEnvironment('REFERENCE_LAYOUT_CAPTURES');
  if (directory.isEmpty) return;
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(_capture),
  );
  await tester.runAsync(() async {
    final image = await boundary.toImage();
    try {
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      await Directory(directory).create(recursive: true);
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
