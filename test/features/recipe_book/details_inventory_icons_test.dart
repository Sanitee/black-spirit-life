// Synthetic regression coverage for approved Details and Inventory consistency.
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
import 'package:bdo_craft_planner_flutter/features/shared/availability_game_icon.dart';
import 'package:bdo_craft_planner_flutter/features/shared/source_availability_badges.dart';
import 'package:bdo_craft_planner_flutter/visual/visual.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import '../../support/choice_market_transport.dart';
import '../planner/planner_choice_market_test.dart' show settle;
import '../planner/planner_review_projection_test.dart' as fixture;
import 'recipe_book_availability_test.dart'
    show checkColumnAlignment, checkBadgeLines;

void main() {
  final catalog = const BundledCatalogParser().parse(
    File('assets/data/app-data.json').readAsStringSync(),
  );
  final repository = CatalogRepository.cached(catalog);

  setUpAll(() async {
    final fonts = '${Platform.environment['WINDIR'] ?? 'C:/Windows'}/Fonts';
    final artifacts = File(
      Platform.resolvedExecutable,
    ).parent.parent.parent.path;
    for (final entry in {
      'Segoe UI': ['$fonts/segoeui.ttf', '$fonts/seguisb.ttf'],
      'Georgia': ['$fonts/georgia.ttf', '$fonts/georgiab.ttf'],
      'MaterialIcons': ['$artifacts/material_fonts/MaterialIcons-Regular.otf'],
    }.entries) {
      if (!File(entry.value.first).existsSync()) continue;
      final loader = FontLoader(entry.key);
      for (final path in entry.value) {
        loader.addFont(File(path).readAsBytes().then(ByteData.sublistView));
      }
      await loader.load();
    }
  });
  for (final spec in RetainedThemeRegistry.themes) {
    for (final scale in [1.0, 2.0]) {
      final suffix = '${spec.id}-$scale';
      Future<void> save(WidgetTester tester, String name, Rect rect) async {
        final rootFinder = find.byKey(const ValueKey('preview-capture'));
        await tester.runAsync(() async {
          for (final image in tester.widgetList<Image>(find.byType(Image))) {
            await precacheImage(image.image, tester.element(rootFinder));
          }
        });
        await tester.pumpAndSettle();
        final root = tester.renderObject<RenderRepaintBoundary>(rootFinder);
        await tester.runAsync(() async {
          final image = await (root.debugLayer! as OffsetLayer).toImage(rect);
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          final file = File('build/details-inventory-icons/$name-$suffix.png');
          await file.parent.create(recursive: true);
          await file.writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }

      Widget host(Widget child) => RepaintBoundary(
        key: const ValueKey('preview-capture'),
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: spec.materialTheme(),
          home: ThemeSpecScope(
            spec: spec,
            child: MediaQuery(
              data: MediaQueryData(textScaler: TextScaler.linear(scale)),
              child: Scaffold(
                backgroundColor: spec.palette.canvas,
                body: child,
              ),
            ),
          ),
        ),
      );

      testWidgets('Details finished item badges $suffix', (tester) async {
        tester.view.physicalSize = const Size(1200, 1000);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final app = fixture.controller(
          catalog,
          CraftMode.cooking,
          'Aloe Cookie',
          1,
        );
        app.active.updateState(
          (s) => s.copyWith(
            inventory: {
              'Aloe': 120,
              'Wheat Dough': 45,
              'Sugar': 8,
              'Cooking Honey': 60,
            },
          ),
          immediate: true,
        );
        final book = RecipeBookController(
          modeController: app.active,
          catalogRepository: repository,
          callingContext: RecipeBookCallingContext.planner,
          allowedTargets: const ['Aloe Cookie'],
        );
        book.toggleFavorite('Aloe Cookie');
        book.setFavoritesOnly(true);
        final transport = ChoiceMarketTransport();
        for (final e in {
          'Aloe Cookie': (scale == 1 ? 11258 : 0, 84),
          'Aloe': (32100, 4900),
          'Wheat Dough': (0, 28500),
          'Cooking Honey': (585, 712),
        }.entries) {
          transport.values[repository.bundledMarketId(e.key)!] = (
            price: e.key == 'Aloe Cookie' ? 2000 : 480,
            stock: e.value.$1,
            preorders: e.value.$2,
          );
        }
        final broker = SharedMarketRepository(
          transport: transport,
          requestSpacing: Duration.zero,
        );
        await tester.pumpWidget(
          host(
            PlannerChoiceMarketScope(
              repository: broker,
              child: RecipeBookModal(
                controller: book,
                onClose: () {},
                onActivated: (_) {},
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(RecipeBookKeys.r13Details('Aloe Cookie')));
        await settle(tester, broker);
        await tester.pumpAndSettle();
        final panel = find.byKey(RecipeBookKeys.previewPanel);
        final panelRect = tester.getRect(panel);
        expect(panelRect.left, greaterThanOrEqualTo(0));
        expect(panelRect.right, lessThanOrEqualTo(1200));
        checkColumnAlignment(tester);
        checkBadgeLines(tester);
        expect(
          find.descendant(of: panel, matching: find.text('Orders 84')),
          findsOneWidget,
        );
        final outputBadge = find
            .descendant(
              of: panel,
              matching: find.byType(SourceAvailabilityBadges),
            )
            .first;
        final badge = tester.widget<SourceAvailabilityBadges>(outputBadge);
        expect(badge.stock, scale == 1 ? 11258 : 0);
        expect(badge.preorders, 84);
        final titleRect = tester.getRect(
          find.descendant(of: panel, matching: find.text('Aloe Cookie')).first,
        );
        final badgeRect = tester.getRect(outputBadge);
        expect(badgeRect.left, closeTo(titleRect.left, .1));
        expect(badgeRect.top, greaterThan(titleRect.bottom));
        expect(badgeRect.right, lessThanOrEqualTo(panelRect.right));
        expect(tester.takeException(), isNull);
        await save(tester, 'details', panelRect);
        book.connectAvailabilityMarket(null);
        await tester.pumpWidget(const SizedBox());
        await tester.pumpAndSettle();
        book.dispose();
        await broker.dispose();
        await app.dispose();
      });

      testWidgets('Inventory editable icon fields $suffix', (tester) async {
        tester.view.physicalSize = const Size(760, 600);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final app = fixture.controller(
          catalog,
          CraftMode.cooking,
          'Aloe Cookie',
          1,
        );
        final amounts = {'Aloe': 120.0, 'Sugar': 8.0, 'Cooking Honey': 6000.0};
        app.active.updateState(
          (s) => s.copyWith(inventory: amounts),
          immediate: true,
        );
        final items = InventoryProjection.assemble(app.active).items;
        String? committed;
        await tester.pumpWidget(
          host(
            Padding(
              padding: const EdgeInsets.all(16),
              child: SizedBox(
                width: 700,
                child: Column(
                  key: const ValueKey('inventory-preview'),
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final e in amounts.entries)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: InventoryStorageItemRow(
                          controller: app.active,
                          item: items.firstWhere((item) => item.name == e.key),
                          amount: e.value,
                          index: amounts.keys.toList().indexOf(e.key),
                          selected: false,
                          onSelected: (_) {},
                          onMoveFocus: (_) {},
                          onRegisterFocus: (_, _) {},
                          onUnregisterFocus: (_, _) {},
                          onCopy: (_) async {},
                          onCommitAmount: (text) {
                            committed = text;
                            return true;
                          },
                          onRemove: () {},
                          onEdit: () {},
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('Owned'), findsNothing);
        expect(find.byType(AvailabilityGameIcon), findsNWidgets(3));
        final amountRects = [
          for (final name in amounts.keys)
            tester.getRect(find.byKey(InventoryActionKeys.row('I10', name))),
        ];
        for (final rect in amountRects) {
          expect(rect.left, closeTo(amountRects.first.left, .1));
        }
        for (final name in amounts.keys) {
          final amount = tester.getRect(
            find.byKey(InventoryActionKeys.row('I10', name)),
          );
          final edit = tester.getRect(
            find.byKey(InventoryActionKeys.row('I11', name)),
          );
          final menu = tester.getRect(
            find.byKey(ValueKey('inventory-more:$name')),
          );
          expect(edit.center.dy, closeTo(amount.center.dy, .1));
          expect(menu.center.dy, closeTo(amount.center.dy, .1));
          expect(edit.left - amount.right, closeTo(10, .1));
        }
        expect(tester.takeException(), isNull);
        await save(
          tester,
          'inventory',
          tester
              .getRect(find.byKey(const ValueKey('inventory-preview')))
              .inflate(8),
        );
        await tester.enterText(
          find.byKey(InventoryActionKeys.row('I10', 'Sugar')),
          '12',
        );
        await tester.testTextInput.receiveAction(TextInputAction.done);
        await tester.pump();
        expect(committed, '12');
        await tester.pumpWidget(const SizedBox());
        await tester.pumpAndSettle();
        await app.dispose();
      });
    }
  }
}
