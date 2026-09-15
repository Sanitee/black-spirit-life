import 'dart:io';
import 'dart:ui' as ui;

import 'package:bdo_craft_planner_flutter/app/state/planner_application_controller.dart';
import 'package:bdo_craft_planner_flutter/data/catalog/bundled_catalog_parser.dart';
import 'package:bdo_craft_planner_flutter/domain/formatting/planner_formatters.dart';
import 'package:bdo_craft_planner_flutter/domain/models/catalog_models.dart';
import 'package:bdo_craft_planner_flutter/domain/models/craft_mode.dart';
import 'package:bdo_craft_planner_flutter/domain/state/planner_state.dart';
import 'package:bdo_craft_planner_flutter/domain/state/state_copy.dart';
import 'package:bdo_craft_planner_flutter/features/planner/planner.dart';
import 'package:bdo_craft_planner_flutter/features/shared/recipe_variant_selector.dart';
import 'package:bdo_craft_planner_flutter/shared/overlays/anchored_popover.dart';
import 'package:bdo_craft_planner_flutter/visual/visual.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _target = 'Brimming Essence of Aether';
const _sharp = 'Sharp Black Crystal Shard';
const _oquilla = 'Oquilla Piece of the Old Moon';

void main() {
  late CatalogSnapshot catalog;
  setUpAll(() async {
    if (const bool.fromEnvironment('CAPTURE_NPC_ROUTE')) {
      await _loadCaptureFonts();
    }
    catalog = const BundledCatalogParser().parse(
      File('assets/data/app-data.json').readAsStringSync(),
    );
  });

  for (final width in [1200.0, 1500.0]) {
    testWidgets(
      'NPC recipe prices, Auto, and full loading quantities at $width',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = Size(width, width == 1200 ? 752 : 940);
        addTearDown(tester.view.reset);
        final controller = _controller(catalog);
        addTearDown(controller.dispose);
        final mode = controller.active;
        final npc = mode.plan.value.missing.single;
        expect(npc.name, _oquilla);
        expect(npc.missing, 80);
        expect(npc.market.price, 50000000);
        expect(npc.market.total, 4000000000);
        expect(npc.market.marketable, isFalse);
        expect(mode.selectedRecipeVariantId(_target), 'oquilla-pieces');
        expect(mode.resolveItemSource(_oquilla).vendor, isNotNull);
        PlannerMarketRequest? requested;
        final actions = PlannerExternalActions(
          openRecipeBook: (_) {},
          copyName: (_) async {},
          checkPrices: (request) async {
            requested = request;
            return const PlannerMarketRefresh(
              prices: {_sharp: 4000000},
              stock: {_sharp: 10000},
              unlistedItemNames: {},
              fetchedAt: 1788616800000,
              summary: 'Market updated.',
            );
          },
        );
        final captureKey = GlobalKey();
        await tester.pumpWidget(
          _host(
            controller: controller,
            actions: actions,
            captureKey: captureKey,
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('Auto'), findsOneWidget);
        expect(find.textContaining('NPC option saves'), findsOneWidget);
        expect(find.text('Stock —'), findsNothing);

        await tester.tap(find.byKey(PlannerActionKeys.p15));
        await tester.pumpAndSettle();
        expect(requested!.namesForRefresh, contains(_sharp));
        expect(mode.selectedRecipeVariantId(_target), 'sharp-shards');
        expect(mode.plan.value.missing.single.need, 800);
        if (const bool.fromEnvironment('CAPTURE_NPC_ROUTE')) {
          await _capture(tester, captureKey, 'market-count-${width.toInt()}');
        }

        await tester.tap(
          find.byKey(
            RecipeVariantSelector.routeChoiceKey(_target, 'oquilla-pieces'),
          ),
        );
        await tester.pumpAndSettle();
        _price(mode, 3000000);
        await tester.pumpAndSettle();
        expect(mode.selectedRecipeVariantId(_target), 'oquilla-pieces');
        expect(find.textContaining('Market option is'), findsOneWidget);
        expect(find.text('Vendor item'), findsOneWidget);
        expect(find.text('Stock —'), findsNothing);

        await tester.tap(
          find.byKey(RecipeVariantSelector.automaticChoiceKey(_target)),
        );
        await tester.pumpAndSettle();
        expect(mode.selectedRecipeVariantId(_target), 'sharp-shards');
        await tester.tap(
          find.byKey(RecipeVariantSelector.batchChoiceKey(_target, 10)),
        );
        await tester.pumpAndSettle();
        expect(mode.recipeRouteSelection(_target)!.isAutomatic, isTrue);
        expect(mode.selectedRecipeVariantId(_target), 'sharp-shards-10x');
        final step = mode.plan.value.steps.single;
        expect(step.count, 4);
        expect(step.produced, 40);
        expect(
          {for (final input in step.ingredients) input.name: input.need},
          {'Black Stone Powder': 4, _sharp: 800, 'Faint Essence of Aether': 40},
        );
        for (final entry in {
          'Black Stone Powder': '4',
          _sharp: '800',
          'Faint Essence of Aether': '40',
        }.entries) {
          final quantity = find.byKey(
            ValueKey('planner-ingredient-batch-quantity:$_target:${entry.key}'),
          );
          expect(tester.widget<Text>(quantity).data, entry.value);
        }
        expect(tester.takeException(), isNull);

        _price(mode, 6000000);
        await tester.pumpAndSettle();
        expect(mode.selectedRecipeVariantId(_target), 'oquilla-pieces-10x');
        expect(mode.recipeRouteSelection(_target)!.isAutomatic, isTrue);
        if (const bool.fromEnvironment('CAPTURE_NPC_ROUTE')) {
          await _capture(tester, captureKey, 'npc-route-${width.toInt()}');
        }
        final mouse = await tester.createGesture(
          kind: ui.PointerDeviceKind.mouse,
        );
        await mouse.addPointer(location: Offset.zero);
        await mouse.moveTo(
          tester.getCenter(find.byType(RecipeRouteCostComparison)),
        );
        await tester.pump(const Duration(seconds: 1));
        await tester.pump(const Duration(milliseconds: 200));
        expect(find.text('Buying missing materials'), findsOneWidget);
        expect(find.text('NPC shop'), findsOneWidget);
        expect(find.text('Stock ${formatQuantity(10000)}'), findsOneWidget);
        expect(find.text('Stock —'), findsNothing);
        expect(tester.takeException(), isNull);
        if (const bool.fromEnvironment('CAPTURE_NPC_ROUTE')) {
          await _capture(
            tester,
            captureKey,
            'npc-route-hover-${width.toInt()}',
          );
        }
        await mouse.moveTo(Offset.zero);
        await tester.pumpAndSettle();
        mode.updateState(
          (state) => state.copyWith(
            market: state.market.copyWith(stock: const {_oquilla: 0}),
          ),
          immediate: true,
        );
        await tester.pumpAndSettle();
        await mouse.moveTo(
          tester.getCenter(find.byType(RecipeRouteCostComparison)),
        );
        await tester.pump(const Duration(seconds: 1));
        await tester.pump(const Duration(milliseconds: 200));
        expect(find.text('Buying missing materials'), findsOneWidget);
        expect(find.text('Stock —'), findsOneWidget);
        expect(find.text('NPC shop'), findsOneWidget);
        expect(find.text('Stock ${formatQuantity(10000)}'), findsNothing);
        if (const bool.fromEnvironment('CAPTURE_NPC_ROUTE')) {
          await _capture(
            tester,
            captureKey,
            'npc-route-unknown-hover-${width.toInt()}',
          );
        }
        await mouse.removePointer();
        await tester.pumpAndSettle();
        _price(mode, 6000000);
        await tester.pumpAndSettle();

        final stateBeforePopup = mode.state.value.toJson();
        final needStableId = 'need:${mode.plan.value.missing.single.key}';
        await tester.tap(
          find.byKey(PlannerActionKeys.row('P22', needStableId)),
        );
        await tester.pumpAndSettle();
        _expectOquillaAcquisition(needStableId);
        if (const bool.fromEnvironment('CAPTURE_NPC_ROUTE')) {
          await _capture(
            tester,
            captureKey,
            'npc-acquisition-${width.toInt()}',
          );
          final card = find.byKey(
            ValueKey('planner-acquisition-card:$needStableId'),
          );
          final position = tester
              .state<ScrollableState>(
                find
                    .descendant(of: card, matching: find.byType(Scrollable))
                    .first,
              )
              .position;
          expect(position.maxScrollExtent, greaterThan(0));
          position.jumpTo(position.maxScrollExtent);
          await tester.pumpAndSettle();
          expect(position.pixels, position.maxScrollExtent);
          await _capture(
            tester,
            captureKey,
            'npc-acquisition-scrolled-${width.toInt()}',
          );
          position.jumpTo(0);
          await tester.pumpAndSettle();
          String? copiedName;
          tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
            SystemChannels.platform,
            (call) async {
              if (call.method == 'Clipboard.setData') {
                copiedName = (call.arguments as Map)['text'] as String;
              }
              return null;
            },
          );
          await tester.tap(
            find
                .descendant(
                  of: card,
                  matching: find.byKey(
                    const ValueKey('item-reference-copy:$_oquilla'),
                  ),
                )
                .first,
          );
          await tester.pumpAndSettle();
          expect(copiedName, _oquilla);
          tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
            SystemChannels.platform,
            null,
          );
        }
        await tester.tap(find.bySemanticsLabel('Close $_oquilla information'));
        await tester.pumpAndSettle();

        final queueIngredient = mode.plan.value.steps.single.ingredients
            .firstWhere((ingredient) => ingredient.name == _oquilla);
        final queueStableId = '$_target:${queueIngredient.key}';
        await tester.tap(
          find.byKey(PlannerActionKeys.row('P22', queueStableId)),
        );
        await tester.pumpAndSettle();
        _expectOquillaAcquisition(queueStableId);
        await tester.tap(find.bySemanticsLabel('Close $_oquilla information'));
        await tester.pumpAndSettle();
        expect(mode.state.value.toJson(), stateBeforePopup);
        expect(tester.takeException(), isNull);
      },
    );
  }
}

void _expectOquillaAcquisition(String stableId) {
  final card = find.byKey(ValueKey('planner-acquisition-card:$stableId'));
  expect(card, findsOneWidget);
  expect(
    find.descendant(
      of: card,
      matching: find.textContaining('Old Moon Manager'),
    ),
    findsOneWidget,
    reason:
        'Reviewed acquisition information must replace the generic vendor sentence.',
  );
  for (final line in const <String>[
    'Buy from an Old Moon Manager in major cities.',
    'Price: 50,000,000 Silver each.',
    'Cannot be registered on the Central Market.',
  ]) {
    expect(
      find.descendant(of: card, matching: find.text(line)),
      findsOneWidget,
      reason: 'Each acquisition fact should have its own readable row.',
    );
  }
}

void _price(ModeFeatureController mode, double price) =>
    mode.replaceMarketValues(
      prices: {_sharp: price},
      stock: {_sharp: 10000},
      unlistedItemNames: {},
      fetchedAt: 1788616800000,
      region: 'eu',
    );

PlannerApplicationController _controller(CatalogSnapshot catalog) {
  ModeState state(CraftMode mode) => ModeState(
    target: _target,
    want: 40,
    ignoreIngredientInventory: false,
    bonusTarget: '',
    bonusWant: 1,
    inventory: const {'Faint Essence of Aether': 40, 'Black Stone Powder': 4},
    market: MarketState(
      prices: const {_sharp: 6000000, _oquilla: 1},
      stock: const {_sharp: 10000, _oquilla: 0},
    ),
    appearance: AppearanceSettings.defaultsFor(mode),
  );
  return PlannerApplicationController(
    catalog: catalog,
    initialState: PlannerState(
      applicationVersion: 'test',
      lastSuccessfulWriteUtc: DateTime.utc(2026, 9, 5),
      activeMode: CraftMode.processing,
      alchemy: state(CraftMode.alchemy),
      cooking: state(CraftMode.cooking),
      processing: state(CraftMode.processing),
      processingYields: const {},
      marketTax: MarketTax(),
      showDeleteTools: false,
    ),
    saveState: (state) async => state,
    saveDebounce: Duration.zero,
  );
}

Widget _host({
  required PlannerApplicationController controller,
  required PlannerExternalActions actions,
  required GlobalKey captureKey,
}) {
  final spec = SakuraNightGardenSpec.theme;
  return RepaintBoundary(
    key: captureKey,
    child: AppOverlayCoordinatorHost(
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: spec.materialTheme(),
        home: ThemeSpecScope(
          spec: spec,
          child: Scaffold(
            body: ColoredBox(
              color: spec.palette.canvas,
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: PlannerView(
                  controller: controller.active,
                  externalActions: actions,
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

Future<void> _capture(WidgetTester tester, GlobalKey key, String name) async {
  await _settleCaptureImages(tester, find.byKey(key));
  final boundary =
      key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  await tester.runAsync(() async {
    final image = await boundary.toImage();
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    const directory = String.fromEnvironment(
      'NPC_CAPTURE_DIRECTORY',
      defaultValue: 'build/npc-route-evidence',
    );
    final file = File('$directory/$name.png');
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  });
}

Future<void> _settleCaptureImages(WidgetTester tester, Finder root) async {
  await tester.pump();
  final context = tester.element(root);
  await tester.runAsync(
    () => precacheImage(
      const AssetImage('assets/sakura/materials/charcoal-plum-lacquer.png'),
      context,
    ),
  );
  for (final element
      in find.descendant(of: root, matching: find.byType(Image)).evaluate()) {
    await tester.runAsync(
      () => precacheImage((element.widget as Image).image, element),
    );
  }
  await tester.pumpAndSettle();
}

Future<void> _loadCaptureFonts() async {
  if (!Platform.isWindows) {
    throw UnsupportedError('NPC route previews require Windows fonts.');
  }
  final windowsRoot =
      Platform.environment['WINDIR'] ??
      Platform.environment['SystemRoot'] ??
      r'C:\Windows';
  final windowsFonts = _childPath(windowsRoot, ['Fonts']);
  final materialFonts = _flutterMaterialFontsDirectory();
  final families = <String, List<String>>{
    'Segoe UI': [
      for (final name in [
        'segoeui.ttf',
        'seguisb.ttf',
        'segoeuib.ttf',
        'segoeuii.ttf',
      ])
        _childPath(windowsFonts, [name]),
    ],
    'Georgia': [
      for (final name in ['georgia.ttf', 'georgiab.ttf', 'georgiai.ttf'])
        _childPath(windowsFonts, [name]),
    ],
    'Roboto': [
      for (final name in ['roboto-regular.ttf', 'roboto-bold.ttf'])
        _childPath(materialFonts, [name]),
    ],
    'MaterialIcons': [
      _childPath(materialFonts, ['materialicons-regular.otf']),
    ],
  };
  for (final entry in families.entries) {
    final loader = FontLoader(entry.key);
    for (final path in entry.value) {
      loader.addFont(File(path).readAsBytes().then(ByteData.sublistView));
    }
    await loader.load();
  }
}

String _flutterMaterialFontsDirectory() {
  final candidates = <Directory>[];
  final configuredRoot = Platform.environment['FLUTTER_ROOT']?.trim();
  if (configuredRoot != null && configuredRoot.isNotEmpty) {
    candidates.add(Directory(configuredRoot));
  }
  var ancestor = File(Platform.resolvedExecutable).parent;
  while (true) {
    candidates.add(ancestor);
    final parent = ancestor.parent;
    if (parent.path == ancestor.path) break;
    ancestor = parent;
  }
  for (final candidate in candidates) {
    final path = _childPath(candidate.path, [
      'bin',
      'cache',
      'artifacts',
      'material_fonts',
    ]);
    if (Directory(path).existsSync()) return path;
  }
  throw StateError('Could not locate Flutter material fonts for the preview.');
}

String _childPath(String root, List<String> segments) =>
    [root, ...segments].join(Platform.pathSeparator);
