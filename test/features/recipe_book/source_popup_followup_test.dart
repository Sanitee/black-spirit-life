import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:bdo_craft_planner_flutter/data/catalog/bundled_catalog_parser.dart';
import 'package:bdo_craft_planner_flutter/data/catalog/catalog_repository.dart';
import 'package:bdo_craft_planner_flutter/domain/models/catalog_models.dart';
import 'package:bdo_craft_planner_flutter/domain/models/craft_mode.dart';
import 'package:bdo_craft_planner_flutter/features/planner/planner_contracts.dart';
import 'package:bdo_craft_planner_flutter/features/recipe_book/plain_item_information.dart';
import 'package:bdo_craft_planner_flutter/features/recipe_book/recipe_book.dart';
import 'package:bdo_craft_planner_flutter/features/recipe_book/recipe_book_item_info.dart';
import 'package:bdo_craft_planner_flutter/features/recipe_book/reviewed_gathering_wording.dart';
import 'package:bdo_craft_planner_flutter/visual/visual.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
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
  for (final entry in reviewedGatheringWording.entries) {
    test('exact gathering wording is scoped and idempotent: ${entry.key}', () {
      final raw = RecipeBookItemInfo(
        title: entry.key,
        kind: 'Material',
        summary: '',
        acquisitionNotes: entry.value.keys.toList(),
      );
      final result = withPlainItemInformation(raw);
      for (final value in entry.value.values) {
        expect(result.acquisitionNotes, contains(value));
      }
      expect(
        withPlainItemInformation(result).acquisitionNotes,
        result.acquisitionNotes,
      );
      final custom = raw.copyWith(
        acquisitionNotes: ['Custom route: ${entry.value.keys.first}'],
      );
      expect(
        withPlainItemInformation(custom).acquisitionNotes,
        contains(custom.acquisitionNotes.single),
      );
      final archived = raw.copyWith(isTemporarilyArchived: true);
      expect(withPlainItemInformation(archived), same(archived));
    });
  }
  for (final mode in CraftMode.values) {
    test('real shared source projection ${mode.name}', () async {
      final app = fixture.controller(catalog, mode, 'Eilton Sandwich', 100);
      final book = RecipeBookController(
        modeController: app.active,
        catalogRepository: CatalogRepository.cached(catalog),
        callingContext: RecipeBookCallingContext.planner,
        allowedTargets: const [],
      );
      final before = jsonEncode(app.documentSnapshot.toJson());
      for (final entry in reviewedGatheringWording.entries) {
        final info = book.itemInfoFor(entry.key, mode: mode);
        if (info == null || info.isTemporarilyArchived) continue;
        for (final old in entry.value.keys) {
          expect(
            info.acquisitionNotes,
            isNot(contains(old)),
            reason: entry.key,
          );
        }
      }
      for (final name in ['Beef', 'Ox Hide']) {
        final info = book.itemInfoFor(name, mode: mode)!;
        expect(
          info.acquisitionNotes,
          contains('Garden · Harvest Haystacks (chance)'),
        );
        expect(info.acquisitionNotes.join(' '), contains('wild bison'));
      }
      final milk = book.itemInfoFor('Milk', mode: mode)!;
      expect(milk.acquisitionNotes.join(' '), contains('Milk cows'));
      expect(milk.acquisitionNotes.join(' '), isNot(contains('butcher')));
      for (final name in [
        'Embers of the Primordial',
        "Nadia Rowen's Special Sauce",
        'Primordial Hammer',
      ]) {
        final info = book.itemInfoFor(name, mode: mode)!;
        expect(
          info.acquisitionNotes.any(
            (s) =>
                s.startsWith('Heat 100 Embers') ||
                s.startsWith('Used once') ||
                s.startsWith('If you already own'),
          ),
          isFalse,
        );
        expect(info.uses, isNotEmpty);
      }
      for (final part in ['Armor', 'Helmet', 'Gloves', 'Shoes']) {
        final info = book.itemInfoFor('Embers of Ynix - $part', mode: mode)!;
        expect(
          info.acquisitionNotes,
          contains(
            'Inner Edania · Open matching Broken Vestiges or weekly boss reward chests',
          ),
        );
        expect(
          info.acquisitionNotes.any((s) => s.startsWith('Collect 100')),
          isFalse,
        );
        expect(info.uses.any((s) => s.startsWith('Collect 100')), isTrue);
      }
      expect(jsonEncode(app.documentSnapshot.toJson()), before);
      book.dispose();
      await app.dispose();
    });
  }
  for (final spec in RetainedThemeRegistry.themes) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('active popup width ${spec.id} $scale', (tester) async {
        tester.view.physicalSize = const Size(1600, 1100);
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
        final capture = GlobalKey();
        await tester.pumpWidget(
          MaterialApp(
            home: ThemeSpecScope(
              spec: spec,
              child: MediaQuery(
                data: MediaQueryData(
                  size: const Size(1600, 1100),
                  textScaler: TextScaler.linear(scale),
                ),
                child: RepaintBoundary(
                  key: capture,
                  child: Scaffold(
                    body: Align(
                      alignment: Alignment.bottomRight,
                      child: RecipeBookItemIcon(
                        controller: book,
                        name: 'Beef',
                        size: 48,
                        anchorId: 'active-tab-width',
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(RecipeBookKeys.itemInfoAnchor('Beef', 'active-tab-width')),
        );
        await tester.pumpAndSettle();
        final card = find.byType(ItemReferenceCard);
        final detailsWidth = tester.getSize(card).width;
        expect(detailsWidth, closeTo(480 * scale, 1));
        Future<void> captureCard(String tab) async {
          for (final element in find.byType(Image).evaluate()) {
            await tester.runAsync(
              () => precacheImage((element.widget as Image).image, element),
            );
          }
          await tester.pumpAndSettle();
          await tester.runAsync(() async {
            final boundary = tester.renderObject<RenderRepaintBoundary>(
              find
                  .ancestor(of: card, matching: find.byType(RepaintBoundary))
                  .first,
            );
            final image = await boundary.toImage();
            final bytes = await image.toByteData(
              format: ui.ImageByteFormat.png,
            );
            final file = File(
              'tmp/source-popup-followup/${spec.id}-$scale-$tab.png',
            );
            await file.parent.create(recursive: true);
            await file.writeAsBytes(bytes!.buffer.asUint8List());
            image.dispose();
          });
        }

        await captureCard('details');
        final drag = await tester.startGesture(
          tester.getTopLeft(card) + const Offset(130, 25),
        );
        await drag.moveBy(const Offset(-180, -70));
        await drag.up();
        await tester.pumpAndSettle();
        await tester.tap(find.text('Used for'));
        await tester.pumpAndSettle();
        expect(tester.getSize(card).width, greaterThanOrEqualTo(detailsWidth));
        var rect = tester.getRect(card);
        expect(rect.right, lessThanOrEqualTo(1600));
        expect(rect.left, greaterThanOrEqualTo(0));
        await captureCard('used-for');
        await tester.tap(find.text('Details'));
        await tester.pumpAndSettle();
        expect(tester.getSize(card).width, closeTo(detailsWidth, 1));
        // A resize must not keep the earlier wide tab's stale tight constraints.
        tester.view.physicalSize = const Size(700, 1000);
        await tester.pumpAndSettle();
        rect = tester.getRect(card);
        expect(rect.width, lessThanOrEqualTo(700));
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        book.dispose();
        await app.dispose();
      });
    }
  }
}
