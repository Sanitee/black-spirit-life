import 'dart:io';
import 'dart:ui' as ui;

import 'package:bdo_craft_planner_flutter/data/catalog/bundled_catalog_parser.dart';
import 'package:bdo_craft_planner_flutter/data/catalog/catalog_repository.dart';
import 'package:bdo_craft_planner_flutter/data/market/shared_market_repository.dart';
import 'package:bdo_craft_planner_flutter/domain/models/craft_mode.dart';
import 'package:bdo_craft_planner_flutter/domain/state/state_copy.dart';
import 'package:bdo_craft_planner_flutter/features/inventory/inventory_action_keys.dart';
import 'package:bdo_craft_planner_flutter/features/inventory/inventory_projection.dart';
import 'package:bdo_craft_planner_flutter/features/inventory/inventory_storage_item_row.dart';
import 'package:bdo_craft_planner_flutter/features/planner/planner_choice_market.dart';
import 'package:bdo_craft_planner_flutter/features/planner/planner_contracts.dart';
import 'package:bdo_craft_planner_flutter/features/recipe_book/recipe_book.dart';
import 'package:bdo_craft_planner_flutter/features/shared/inventory_count_badge.dart';
import 'package:bdo_craft_planner_flutter/visual/visual.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/choice_market_transport.dart';
import '../../support/substitute_chooser_helpers.dart';
import '../planner/planner_choice_market_test.dart' show settle;
import '../planner/planner_review_projection_test.dart' as fixture;
import 'recipe_book_availability_test.dart'
    show capture, checkColumnAlignment, checkBadgeLines;

void main() {
  final catalog = const BundledCatalogParser().parse(
    File('assets/data/app-data.json').readAsStringSync(),
  );
  final repository = CatalogRepository.cached(catalog);
  setUpAll(() async {
    for (final entry in {
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
      final loader = FontLoader(entry.key);
      for (final path in entry.value) {
        loader.addFont(File(path).readAsBytes().then(ByteData.sublistView));
      }
      await loader.load();
    }
  });
  Future<void> host(
    WidgetTester tester,
    ThemeSpec spec,
    double scale,
    double width,
    Widget child, {
    SharedMarketRepository? broker,
  }) async {
    tester.view.physicalSize = Size(width, 960);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: spec.materialTheme(),
        home: ThemeSpecScope(
          spec: spec,
          child: PlannerChoiceMarketScope(
            repository: broker,
            child: MediaQuery(
              data: MediaQueryData(
                size: Size(width, 960),
                textScaler: TextScaler.linear(scale),
              ),
              child: RepaintBoundary(
                key: const ValueKey('capture-root'),
                child: Scaffold(
                  key: const ValueKey('capture'),
                  backgroundColor: spec.palette.canvas,
                  body: Padding(
                    padding: const EdgeInsets.all(24),
                    child: child,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    if (broker != null) {
      await settle(tester, broker);
      await tester.pumpAndSettle();
    }
  }

  for (final spec in RetainedThemeRegistry.themes) {
    for (final scale in [1.0, 2.0]) {
      for (final name in ['Wheat Flour', 'Eilton Sandwich']) {
        testWidgets('reference columns ${spec.id} $scale $name', (
          tester,
        ) async {
          final mode = name == 'Wheat Flour'
              ? CraftMode.processing
              : CraftMode.cooking;
          final app = fixture.controller(catalog, mode, name, 1);
          final book = RecipeBookController(
            modeController: app.active,
            catalogRepository: repository,
            callingContext: RecipeBookCallingContext.planner,
            allowedTargets: [name],
          );
          app.active.updateState(
            (state) => state.copyWith(
              inventory: {
                'Wheat': 120,
                'High-quality Wheat': 40,
                'Special Wheat': 0,
                'Paprika': 15,
                'Tomato': 30,
                'High-Quality Tomato': 8,
                'Special Tomato': 0,
              },
            ),
            immediate: true,
          );
          final transport = ChoiceMarketTransport();
          transport.values[repository.bundledMarketId('Wheat')!] = (
            price: 480,
            stock: 0,
            preorders: 28800,
          );
          final broker = SharedMarketRepository(
            transport: transport,
            requestSpacing: Duration.zero,
          );
          await host(
            tester,
            spec,
            scale,
            scale == 1 ? 1464 : 1000,
            Align(
              alignment: Alignment.topCenter,
              child: ItemReferenceCard(
                controller: book,
                mode: mode,
                name: name,
                info: book.itemInfoFor(name)!,
                maxWidth: 1900,
                spec: spec,
                onClose: () {},
              ),
            ),
            broker: broker,
          );
          expect(tester.takeException(), isNull);
          await openSubstitutes(
            tester,
            name,
            name == 'Wheat Flour' ? 'Wheat' : 'Paprika',
          );
          await settle(tester, broker);
          await tester.pumpAndSettle();
          final table = tester.widget<RecipeIngredientTable>(
            substituteChooser(),
          );
          expect(table.rows.length, greaterThan(2));
          if (name == 'Wheat Flour') {
            expect(table.rows.map((row) => row.owned), [120, 40, 0]);
            expect(table.rows.map((row) => row.quantity), [1, 1, 1]);
          } else {
            expect(
              table.rows.any((row) => row.name == 'High-Quality Tomato'),
              isTrue,
            );
            expect(
              table.rows.any((row) => row.name == 'Special Cabbage'),
              isFalse,
            );
            expect(
              table.rows.firstWhere((row) => row.name == 'Paprika').npc,
              isTrue,
            );
          }
          expect(
            find.descendant(
              of: substituteChooser(),
              matching: find.byType(InventoryCountBadge),
            ),
            findsNWidgets(table.rows.length),
          );
          checkColumnAlignment(tester);
          checkBadgeLines(tester);
          final rendered = tester.widget<Table>(
            find
                .descendant(
                  of: substituteChooser(),
                  matching: find.byType(Table),
                )
                .first,
          );
          expect(
            (rendered.children[1].decoration as BoxDecoration).color,
            isNot((rendered.children[2].decoration as BoxDecoration).color),
          );
          await capture(tester, 'approved-${spec.id}-$scale-$name');
          if (name == 'Wheat Flour') {
            app.active.updateState(
              (state) => state.copyWith(inventory: {'Wheat': 121}),
              immediate: true,
            );
            await tester.pumpAndSettle();
            expect(
              tester
                  .widget<RecipeIngredientTable>(substituteChooser())
                  .rows
                  .first
                  .owned,
              121,
            );
          }
          await tester.pumpWidget(const SizedBox());
          book.dispose();
          await broker.dispose();
          await app.dispose();
        });
      }
      for (final width in [420.0, 760.0]) {
        testWidgets('inventory aligned and quiet ${spec.id} $scale $width', (
          tester,
        ) async {
          final app = fixture.controller(catalog, CraftMode.cooking, 'Beer', 1);
          final item = InventoryProjection.assemble(
            app.active,
          ).items.firstWhere((row) => row.name == 'Wheat');
          await host(
            tester,
            spec,
            scale,
            width,
            Align(
              alignment: Alignment.topCenter,
              child: InventoryStorageItemRow(
                controller: app.active,
                item: item,
                amount: 120,
                index: 0,
                selected: false,
                onSelected: (_) {},
                onMoveFocus: (_) {},
                onRegisterFocus: (_, _) {},
                onUnregisterFocus: (_, _) {},
                onCopy: (_) async {},
                onCommitAmount: (_) => true,
                onRemove: () {},
                onEdit: () {},
              ),
            ),
          );
          final field = find.byKey(InventoryActionKeys.row('I10', 'Wheat'));
          final edit = find.byKey(InventoryActionKeys.row('I11', 'Wheat'));
          final more = find.byKey(const ValueKey('inventory-more:Wheat'));
          for (final invalid in [false, true]) {
            if (invalid) {
              await tester.enterText(field, '');
              await tester.testTextInput.receiveAction(TextInputAction.done);
              await tester.pumpAndSettle();
            }
            expect(
              tester.getCenter(edit).dy,
              closeTo(tester.getCenter(field).dy, .1),
            );
            expect(
              tester.getCenter(more).dy,
              closeTo(tester.getCenter(field).dy, .1),
            );
            expect(
              tester.getRect(edit).left - tester.getRect(field).right,
              greaterThanOrEqualTo(9.9),
            );
            expect(tester.takeException(), isNull);
          }
          final mouse = await tester.createGesture(
            kind: ui.PointerDeviceKind.mouse,
          );
          await mouse.addPointer(location: Offset.zero);
          await mouse.moveTo(tester.getCenter(more));
          await tester.pump(const Duration(seconds: 1));
          expect(find.text('Actions for Wheat'), findsNothing);
          final semantics = tester.ensureSemantics();
          await tester.pump();
          expect(find.bySemanticsLabel('Actions for Wheat'), findsOneWidget);
          semantics.dispose();
          await capture(tester, 'approved-inventory-${spec.id}-$scale-$width');
          await mouse.removePointer();
          await tester.pumpWidget(const SizedBox());
          await app.dispose();
        });
      }
    }
  }
}
