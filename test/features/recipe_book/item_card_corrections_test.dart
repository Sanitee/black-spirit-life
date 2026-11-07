import 'dart:io';
import 'dart:ui' as ui;

import 'package:bdo_craft_planner_flutter/data/catalog/bundled_catalog_parser.dart';
import 'package:bdo_craft_planner_flutter/data/catalog/catalog_repository.dart';
import 'package:bdo_craft_planner_flutter/data/market/shared_market_repository.dart';
import 'package:bdo_craft_planner_flutter/domain/models/catalog_models.dart';
import 'package:bdo_craft_planner_flutter/domain/models/craft_mode.dart';
import 'package:bdo_craft_planner_flutter/features/planner/planner_choice_market.dart';
import 'package:bdo_craft_planner_flutter/features/planner/planner_contracts.dart';
import 'package:bdo_craft_planner_flutter/features/recipe_book/recipe_book.dart';
import 'package:bdo_craft_planner_flutter/visual/visual.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/availability_badge_finders.dart';
import '../../support/choice_market_transport.dart';
import '../planner/planner_choice_market_test.dart' show settle;
import '../planner/planner_review_projection_test.dart' as fixture;

void main() {
  late CatalogSnapshot catalog;
  setUpAll(() async {
    catalog = const BundledCatalogParser().parse(
      File('assets/data/app-data.json').readAsStringSync(),
    );
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
      for (final file in entry.value) {
        loader.addFont(File(file).readAsBytes().then(ByteData.sublistView));
      }
      await loader.load();
    }
  });
  for (final width in [1400.0, 640.0]) {
    testWidgets('actual popup widens safely at $width', (tester) async {
      tester.view.physicalSize = Size(width, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final app = fixture.controller(
        catalog,
        CraftMode.cooking,
        'Eilton Sandwich',
        100,
      );
      final book = RecipeBookController(
        modeController: app.active,
        catalogRepository: CatalogRepository.cached(catalog),
        callingContext: RecipeBookCallingContext.planner,
        allowedTargets: const [],
      );
      await tester.pumpWidget(
        MaterialApp(
          home: ThemeSpecScope(
            spec: SakuraNightGardenSpec.theme,
            child: Scaffold(
              body: Center(
                child: RecipeBookItemIcon(
                  controller: book,
                  name: 'Eilton Sandwich',
                  size: 48,
                  anchorId: 'resize-test',
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(
          RecipeBookKeys.itemInfoAnchor('Eilton Sandwich', 'resize-test'),
        ),
      );
      await tester.pumpAndSettle();
      final card = find.byType(ItemReferenceCard);
      expect(card, findsOneWidget);
      final rect = tester.getRect(card);
      expect(rect.width, greaterThan(480));
      expect(rect.left, greaterThanOrEqualTo(0));
      expect(rect.right, lessThanOrEqualTo(width));
      expect(find.text('or 2 High-Quality Tomato'), findsOneWidget);
      final horizontal = find.descendant(
        of: card,
        matching: find.byWidgetPredicate(
          (w) => w is Scrollable && w.axisDirection == AxisDirection.right,
        ),
      );
      if (width == 640) {
        // Enlarged text still remains one line per grade, reachable by scrolling.
        await tester.pumpWidget(
          MaterialApp(
            home: ThemeSpecScope(
              spec: SakuraNightGardenSpec.theme,
              child: MediaQuery(
                data: MediaQueryData(
                  size: Size(width, 1000),
                  textScaler: const TextScaler.linear(2),
                ),
                child: Scaffold(
                  body: Builder(
                    builder: (context) => ItemReferenceCard(
                      controller: book,
                      mode: CraftMode.cooking,
                      name: 'Eilton Sandwich',
                      info: book.itemInfoFor('Eilton Sandwich')!,
                      maxWidth: itemReferenceCardWidth(
                        context,
                        controller: book,
                        info: book.itemInfoFor('Eilton Sandwich'),
                      ),
                      spec: SakuraNightGardenSpec.theme,
                      onClose: () {},
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(
          tester
              .stateList<ScrollableState>(horizontal)
              .any((s) => s.position.maxScrollExtent > 0),
          isTrue,
        );
      }
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      book.dispose();
      await app.dispose();
    });
  }
  for (final spec in RetainedThemeRegistry.themes) {
    for (final scale in [1.0, 2.0]) {
      for (final name in [
        'Eilton Sandwich',
        'Red Pepper Powder',
        'Cooking Honey',
        'High-Quality Hot Pepper',
      ]) {
        testWidgets('corrected card $name ${spec.id} $scale', (tester) async {
          tester.view.physicalSize = const Size(1400, 1000);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final app = fixture.controller(
            catalog,
            CraftMode.cooking,
            'Eilton Sandwich',
            100,
          );
          final before = app.documentSnapshot.toJson();
          final book = RecipeBookController(
            modeController: app.active,
            catalogRepository: CatalogRepository.cached(catalog),
            callingContext: RecipeBookCallingContext.planner,
            allowedTargets: const [],
          );
          final transport = ChoiceMarketTransport();
          transport.values['7327'] = (price: 12000, stock: 1234, preorders: 12);
          final broker = SharedMarketRepository(
            transport: transport,
            requestSpacing: Duration.zero,
          );
          final info = book.itemInfoFor(name)!;
          final copies = <String>[];
          await tester.pumpWidget(
            MaterialApp(
              home: ThemeSpecScope(
                spec: spec,
                child: MediaQuery(
                  data: MediaQueryData(
                    size: const Size(1400, 1000),
                    textScaler: TextScaler.linear(scale),
                  ),
                  child: PlannerChoiceMarketScope(
                    repository: broker,
                    child: Scaffold(
                      backgroundColor: const Color(0xff171416),
                      body: Center(
                        child: Builder(
                          builder: (context) => RepaintBoundary(
                            key: const ValueKey('capture'),
                            child: ItemReferenceCard(
                              controller: book,
                              mode: CraftMode.cooking,
                              name: name,
                              info: info,
                              maxWidth: itemReferenceCardWidth(
                                context,
                                controller: book,
                                info: info,
                                mode: CraftMode.cooking,
                              ),
                              spec: spec,
                              onClose: () {},
                              onCopyItemName: copies.add,
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
          await settle(tester, broker);
          Finder badge(String n) => find.byKey(ValueKey('reference-source:$n'));
          if (name == 'Red Pepper Powder') {
            for (final n in [
              'Hot Pepper',
              'High-Quality Hot Pepper',
              'Special Hot Pepper',
            ]) {
              expect(badge(n), findsOneWidget);
            }
            expect(
              find.descendant(
                of: badge('High-Quality Hot Pepper'),
                matching: stockBadgeText('1,2k'),
              ),
              findsOneWidget,
            );
            expect(transport.requests.expand((r) => r.ids), contains('7327'));
            if (scale == 1) {
              final label = find.text('or 2 High-Quality Hot Pepper');
              expect(
                tester.getRect(badge('High-Quality Hot Pepper')).left,
                greaterThan(tester.getRect(label).right),
              );
              expect(
                (tester.getRect(badge('High-Quality Hot Pepper')).center.dy -
                        tester.getRect(label).center.dy)
                    .abs(),
                lessThan(2),
              );
            }
          }
          if (name == 'Eilton Sandwich') {
            expect(badge('Cabbage'), findsOneWidget);
            expect(badge('High-Quality Cabbage'), findsNothing);
            expect(badge('Special Cabbage'), findsNothing);
            for (final base in ['Paprika', 'Tomato', 'Pumpkin', 'Olive']) {
              for (final n in [base, 'High-Quality $base', 'Special $base']) {
                expect(badge(n), findsOneWidget, reason: n);
              }
              expect(find.text('or 2 High-Quality $base'), findsOneWidget);
              expect(find.text('or 1 Special $base'), findsOneWidget);
            }
            final tomato = find.text('or 5 Tomato');
            final high = find.text('or 2 High-Quality Tomato');
            final special = find.text('or 1 Special Tomato');
            expect(
              tester.getRect(tomato).top,
              lessThan(tester.getRect(high).top),
            );
            expect(
              tester.getRect(tomato).top,
              lessThan(tester.getRect(special).top),
            );
            expect(
              tester.getRect(badge('High-Quality Tomato')).left,
              greaterThan(tester.getRect(high).right),
            );
            expect(
              tester.getRect(badge('High-Quality Tomato')).center.dy,
              closeTo(tester.getRect(high).center.dy, 1),
            );
            if (scale == 1) {
              expect(
                tester.getRect(find.byType(ItemReferenceCard)).width,
                greaterThan(480),
              );
              await tester.ensureVisible(high);
              await tester.tap(high);
              expect(copies, ['High-Quality Tomato']);
            }
          }
          if (name == 'Cooking Honey') {
            expect(
              info.acquisitionNotes.where((s) => s.contains('beehives')),
              hasLength(1),
            );
            expect(
              info.acquisitionNotes.firstWhere((s) => s.contains('beehives')),
              contains('then grind 3 Wild Beehives'),
            );
            expect(
              info.acquisitionNotes.where((s) => s.startsWith('Collect them')),
              isEmpty,
            );
          }
          if (name == 'High-Quality Hot Pepper') {
            expect(find.text('When eaten raw'), findsNothing);
            expect(find.text('Duration: 30 sec.'), findsNothing);
            expect(info.effects, isEmpty);
          }
          expect(tester.takeException(), isNull);
          expect(app.documentSnapshot.toJson(), before);
          await tester.pumpAndSettle();
          await tester.runAsync(() async {
            await Future.wait([
              for (final element in find.byType(Image).evaluate())
                precacheImage((element.widget as Image).image, element),
            ]);
          });
          await tester.pumpAndSettle();
          final boundary = tester.renderObject<RenderRepaintBoundary>(
            find.byKey(const ValueKey('capture')),
          );
          await tester.runAsync(() async {
            final image = await boundary.toImage(pixelRatio: 1);
            final bytes = await image.toByteData(
              format: ui.ImageByteFormat.png,
            );
            final file = File(
              'tmp/item-card-corrections/${spec.id}-$scale-${name.replaceAll(' ', '-')}.png',
            );
            await file.parent.create(recursive: true);
            await file.writeAsBytes(bytes!.buffer.asUint8List());
            image.dispose();
          });
          await tester.pumpWidget(const SizedBox());
          await broker.close();
          book.dispose();
          await app.dispose();
        });
      }
    }
  }
}
