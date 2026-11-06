import 'dart:io';
import 'dart:ui' as ui;

import 'package:bdo_craft_planner_flutter/app/workspace/application_workspace.dart';
import 'package:bdo_craft_planner_flutter/data/market/shared_market_repository.dart';
import 'package:bdo_craft_planner_flutter/domain/models/craft_mode.dart';
import 'package:bdo_craft_planner_flutter/domain/state/state_copy.dart';
import 'package:bdo_craft_planner_flutter/features/planner/planner.dart';
import 'package:bdo_craft_planner_flutter/features/recipe_book/recipe_book_item_info_view.dart';
import 'package:bdo_craft_planner_flutter/visual/visual.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/application_test_harness.dart';
import '../../support/availability_badge_finders.dart';
import '../../support/choice_market_transport.dart';
import 'planner_choice_market_test.dart' show settle;

void main() {
  setUpAll(_loadFonts);
  for (final spec in [
    SakuraNightGardenSpec.theme,
    StandardSpec.theme,
    IlluminatedLedgerSpec.theme,
  ]) {
    for (final example in [
      (
        CraftMode.cooking,
        'Bean Sprout Salad',
        'Bean Sprouts',
        'Workers · Jangdok Platform (Donghae / Seoul)',
        1.0,
      ),
      (
        CraftMode.cooking,
        'Stir-Fried Vegetables',
        'Hot Pepper',
        'Seeds · Buy normal seeds from Ahr in Calpheon',
        1.0,
      ),
      (
        CraftMode.cooking,
        'Bean Sprout Salad',
        'Bean Sprouts',
        'Workers · Jangdok Platform (Donghae / Seoul)',
        2.0,
      ),
      (
        CraftMode.cooking,
        'Stir-Fried Vegetables',
        'Hot Pepper',
        'Seeds · Buy normal seeds from Ahr in Calpheon',
        2.0,
      ),
    ]) {
      final (craftMode, target, name, source, scale) = example;
      testWidgets('market source $name ${spec.id} text $scale', (tester) async {
        const size = Size(1200, 752);
        configureApplicationTestSurface(tester, size, textScaleFactor: scale);
        final original = (await tester.runAsync(
          () => ApplicationTestHarness.create(
            backgroundId: spec.isStandard ? 'greenhouse' : spec.id,
            activeMode: craftMode,
          ),
        ))!;
        final harness = original.rebindControllerInCurrentZone();
        await tester.runAsync(original.disposeControllerOnly);
        final mode = harness.bundle.controller.active;
        expect(mode.selectTarget(target), isTrue);
        mode.updateState((state) => state.copyWith(want: 100), immediate: true);
        final before = mode.state.value.toJson();
        final transport = ChoiceMarketTransport();
        final id = mode.recipes[name]!.marketId!;
        transport.values[id] = (
          price: 100,
          stock: name == 'Bean Sprouts' ? 12594 : 0,
          preorders: 84,
        );
        final broker = SharedMarketRepository(
          transport: transport,
          requestSpacing: Duration.zero,
        );
        try {
          await tester.pumpWidget(
            RepaintBoundary(
              key: const ValueKey('source-capture'),
              child: MaterialApp(
                debugShowCheckedModeBanner: false,
                home: ApplicationWorkspace(
                  bundle: harness.bundle,
                  sharedMarket: broker,
                  fishMapWorkspace: const SizedBox.shrink(),
                  enableBetaUpdates: false,
                  enableOpportunityAutoCheck: false,
                  marketGateway: const EmptyMarketGateway(),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          final anchor = find.byKey(
            PlannerActionKeys.row('P22', '$target:$name'),
          );
          final queue = find
              .descendant(
                of: find.byKey(
                  const PageStorageKey<String>('planner-craft-queue'),
                ),
                matching: find.byType(Scrollable),
              )
              .first;
          if (anchor.evaluate().isEmpty) {
            final expand = find.byKey(PlannerActionKeys.row('P09', target));
            await tester.scrollUntilVisible(expand, 180, scrollable: queue);
            await tester.ensureVisible(expand);
            await tester.pumpAndSettle();
            await tester.tap(expand);
            await tester.pumpAndSettle();
          }
          await tester.scrollUntilVisible(anchor, 160, scrollable: queue);
          await tester.ensureVisible(anchor);
          await tester.pumpAndSettle();
          await tester.tap(anchor);
          await tester.pumpAndSettle();
          await settle(tester, broker);
          final popup = find.byType(ItemReferenceCard);
          expect(find.text('Central Market'), findsOneWidget);
          expect(
            stockBadgeText(name == 'Bean Sprouts' ? '12.594' : '0'),
            findsOneWidget,
          );
          expect(find.text('Orders 84'), findsOneWidget);
          expect(find.textContaining('When in stock'), findsNothing);
          expect(popup, findsOneWidget);
          expect(
            find.descendant(of: popup, matching: find.text(source)),
            findsOneWidget,
          );
          if (name == 'Powder of Darkness') {
            expect(
              find.text('Mine rocks with a pickaxe (rare)'),
              findsOneWidget,
            );
          }
          final rect = tester.getRect(popup);
          expect(rect.left, greaterThanOrEqualTo(0));
          expect(rect.right, lessThanOrEqualTo(size.width));
          expect(rect.top, greaterThanOrEqualTo(0));
          expect(rect.bottom, lessThanOrEqualTo(size.height));
          await _capture(
            tester,
            '${name.toLowerCase().replaceAll(' ', '-')}-${spec.id}-${scale.toInt()}',
          );
          final used = find.byKey(
            const ValueKey('attached-reference-tab:used'),
          );
          if (used.evaluate().isNotEmpty) {
            await tester.tap(used);
            await tester.pumpAndSettle();
            await tester.tap(
              find.byKey(const ValueKey('attached-reference-tab:recipe')),
            );
            await tester.pumpAndSettle();
            expect(find.text(source), findsOneWidget);
          }
          expect(mode.state.value.toJson(), before);
          expect(tester.takeException(), isNull);
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          await broker.close();
          await harness.disposeControllerOnly();
          await tester.runAsync(
            () => harness.temporaryDirectory.delete(recursive: true),
          );
        }
      });
    }
  }
}

Future<void> _capture(WidgetTester tester, String name) async {
  final output = Platform.environment['BSL_SOURCE_STOCK_CAPTURE_DIR'];
  if (output == null || output.isEmpty) return;
  await tester.runAsync(() async {
    await Future.wait([
      for (final element in find.byType(Image).evaluate())
        precacheImage((element.widget as Image).image, element),
    ]);
  });
  await tester.pumpAndSettle();
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(const ValueKey('source-capture')),
  );
  await tester.runAsync(() async {
    await Directory(output).create(recursive: true);
    final image = await boundary.toImage();
    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      await File('$output/$name.png').writeAsBytes(data!.buffer.asUint8List());
    } finally {
      image.dispose();
    }
  });
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
  for (final family in {
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
    final loader = FontLoader(family.key);
    for (final file in family.value) {
      loader.addFont(File(file).readAsBytes().then(ByteData.sublistView));
    }
    await loader.load();
  }
}
