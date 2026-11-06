import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:bdo_craft_planner_flutter/data/catalog/bundled_catalog_parser.dart';
import 'package:bdo_craft_planner_flutter/features/inventory/inventory_screenshot_recognition.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'October unique artwork is recognized; shared Khalk artwork stays manual',
    () async {
      final source = const BundledCatalogParser().parse(
        File('assets/data/app-data.json').readAsStringSync(),
      );
      const base =
          'windows/storage_ocr/BlackSpiritStorageOcr/Assets/RecipeBook';
      final catalog = InventoryOcrMaterialCatalog.fromRecipeBookJson(
        catalog: source,
        recipeBookJson: File('$base/recipes.json').readAsStringSync(),
        recipeBookIconIndexJson: File(
          '$base/ocr/icon-index.json',
        ).readAsStringSync(),
      );
      final cache = InventoryOcrPreprocessedTemplateCache.decode(
        indexJson: File(
          '$base/AppMatcher/inventory-ocr-templates.json',
        ).readAsStringSync(),
        rgbBytes: File(
          '$base/AppMatcher/inventory-ocr-templates.rgb',
        ).readAsBytesSync(),
      );
      final artwork = source.supportingData['itemIconArtwork']! as Map;
      for (final cached in [false, true]) {
        final processor = InventoryScreenshotPostProcessor(
          catalog: catalog,
          nativeArtworkBytes: const {},
          preprocessedTemplateCache: cached ? cache : null,
        );
        for (final item in const <(String, int)>[
          ('Perfume of Resolve', 1418),
          ("Immortal: Perfume of Resolve", 1419),
          ('Khalk Blood', 6360),
          ('Tainted Khalk Fluid', 821472),
        ]) {
          expect(catalog.names, contains(item.$1));
          expect(catalog.itemIds[item.$1.toLowerCase()], item.$2);
          final uri = artwork[item.$1.toLowerCase()]! as String;
          // Use Flutter's independent image decoder to construct the input. The
          // recognition path must not be its own image-decoding test oracle.
          final codec = await ui.instantiateImageCodec(
            base64Decode(uri.substring(uri.indexOf(',') + 1)),
          );
          final frame = await codec.getNextFrame();
          final png = await frame.image.toByteData(
            format: ui.ImageByteFormat.png,
          );
          final decoded = image.decodePng(png!.buffer.asUint8List())!;
          frame.image.dispose();
          codec.dispose();
          final screenshot = image.Image(
            width: decoded.width,
            height: decoded.height,
            numChannels: 4,
          );
          image.fill(screenshot, color: image.ColorRgba8(22, 23, 27, 255));
          image.compositeImage(screenshot, decoded);
          final draft = processor.sanitize(
            screenshotBytes: Uint8List.fromList(image.encodePng(screenshot)),
            rawResult: {
              'imageFingerprint': 'a' * 64,
              'width': decoded.width,
              'height': decoded.height,
              'grid': {'columns': 1, 'rows': 1, 'confidence': .99},
              'slots': [
                {
                  'id': 'r0c0',
                  'row': 0,
                  'column': 0,
                  'box': {
                    'x': 0,
                    'y': 0,
                    'width': decoded.width,
                    'height': decoded.height,
                  },
                  'iconCandidates': <Object?>[],
                  'iconMaterialEligible': null,
                  'iconMaterialConfidence': 0,
                  'iconMaterialMargin': 0,
                  'borderGradeConfidence': 0,
                  'quantityText': '45',
                  'quantityValue': 45,
                  'quantitySuggestedValue': null,
                  'quantityApproximate': false,
                  'quantityConfidence': .98,
                  'quantityAssumedOne': false,
                },
              ],
              'warnings': <Object?>[],
            },
          );
          final row = draft.rows.single;
          if (item.$2 == 6360) {
            // Known coverage limitation: the sealed helper has neither identity;
            // both use an identical legacy WebP that the app matcher cannot decode.
            // Both remain eligible for manual correction, never falsely assigned.
            expect(
              catalog.names,
              containsAll(['Khalk Blood', 'Dinosaur Blood']),
            );
            expect(row.matches, isEmpty);
            expect(row.selectedName, isNull);
            expect(row.quantity, 45);
            continue;
          }
          expect(row.matches, isNotEmpty, reason: '${item.$1}, cached=$cached');
          expect(row.matches.first.name, item.$1, reason: 'cached=$cached');
          expect(row.matches.first.itemId, item.$2);
          expect(row.selectedName, item.$1);
          expect(row.quantity, 45);
        }
      }
    },
  );
}
