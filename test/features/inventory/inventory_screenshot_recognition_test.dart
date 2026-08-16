import 'dart:convert';
import 'dart:typed_data';

import 'package:bdo_craft_planner_flutter/app/window/native_still_image_ocr_service.dart';
import 'package:bdo_craft_planner_flutter/domain/models/catalog_models.dart';
import 'package:bdo_craft_planner_flutter/domain/models/craft_mode.dart';
import 'package:bdo_craft_planner_flutter/features/inventory/inventory_screenshot_recognition.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image;

void main() {
  test('uses the visible minimum for abbreviated BDO amounts', () {
    expect(parseVisibleInventoryAmount('139.9K'), 139900);
    expect(parseVisibleInventoryAmount('1.8M'), 1800000);
    expect(parseVisibleInventoryAmount('100.8K'), 100800);
    expect(parseVisibleInventoryAmount('13.460'), 13460);
    expect(parseVisibleInventoryAmount('-2966'), 2966);
    expect(parseVisibleInventoryAmount('lO4'), 104);
    expect(parseVisibleInventoryAmount('+15'), isNull);
    expect(parseVisibleInventoryAmount('113/161'), isNull);
  });

  test(
    'finds a storage title, visible slots, quantities and icon candidates',
    () {
      final red = _solidIcon(205, 43, 51);
      final green = _solidIcon(35, 176, 88);
      final blue = _solidIcon(38, 103, 205);
      final catalog = _catalog(<String, String>{
        'Wolf Blood': red.dataUri,
        'Sheep Blood': red.dataUri,
        'Fir Timber': green.dataUri,
        'Iron Ore': blue.dataUri,
      });
      final screenshot = image.Image(width: 190, height: 120, numChannels: 4);
      image.fill(screenshot, color: image.ColorRgba8(25, 26, 29, 255));
      _paintCell(screenshot, 15, 45, red.image);
      _paintCell(screenshot, 70, 45, green.image);
      _paintCell(screenshot, 125, 45, blue.image);
      final png = Uint8List.fromList(image.encodePng(screenshot));
      const ocr = StillImageOcrResult(
        sourceWidth: 190,
        sourceHeight: 120,
        ocrLanguage: 'en-US',
        diagnostics: <String>[],
        lines: <StillImageOcrLine>[
          StillImageOcrLine(
            text: 'Calpheon',
            left: 10,
            top: 8,
            width: 46,
            height: 10,
          ),
          StillImageOcrLine(
            text: 'City',
            left: 60,
            top: 8,
            width: 24,
            height: 10,
          ),
          StillImageOcrLine(
            text: 'Storage',
            left: 88,
            top: 8,
            width: 42,
            height: 10,
          ),
          StillImageOcrLine(
            text: '139.9K',
            left: 19,
            top: 84,
            width: 42,
            height: 9,
          ),
          StillImageOcrLine(
            text: '500',
            left: 82,
            top: 84,
            width: 24,
            height: 9,
          ),
          StillImageOcrLine(
            text: '1.8M',
            left: 137,
            top: 84,
            width: 28,
            height: 9,
          ),
        ],
      );

      final draft = InventoryScreenshotRecognizer.fromCatalog(
        catalog,
      ).recognize(screenshotPng: png, ocr: ocr);

      expect(draft.suggestedLocationName, 'Calpheon City Storage');
      expect(draft.rows, hasLength(3));
      expect(draft.rows.map((row) => row.quantity), <int>[
        139900,
        500,
        1800000,
      ]);
      expect(
        draft.rows.first.matches.take(2).map((match) => match.name).toSet(),
        <String>{'Sheep Blood', 'Wolf Blood'},
      );
      expect(draft.rows.first.needsReview, isTrue);
      expect(draft.rows[1].matches.first.name, 'Fir Timber');
      expect(draft.rows[2].matches.first.name, 'Iron Ore');
    },
  );

  test('merges enlarged-pass duplicates and split amount glyphs', () {
    final red = _solidIcon(205, 43, 51);
    final green = _solidIcon(35, 176, 88);
    final blue = _solidIcon(38, 103, 205);
    final catalog = _catalog(<String, String>{
      'Wolf Blood': red.dataUri,
      'Fir Timber': green.dataUri,
      'Iron Ore': blue.dataUri,
    });
    final screenshot = image.Image(width: 190, height: 120, numChannels: 4);
    image.fill(screenshot, color: image.ColorRgba8(25, 26, 29, 255));
    _paintCell(screenshot, 15, 45, red.image);
    _paintCell(screenshot, 70, 45, green.image);
    _paintCell(screenshot, 125, 45, blue.image);
    final png = Uint8List.fromList(image.encodePng(screenshot));
    const ocr = StillImageOcrResult(
      sourceWidth: 190,
      sourceHeight: 120,
      ocrLanguage: 'en-US',
      diagnostics: <String>[],
      lines: <StillImageOcrLine>[
        StillImageOcrLine(
          text: 'Calpheon',
          left: 10,
          top: 8,
          width: 46,
          height: 10,
        ),
        StillImageOcrLine(
          text: 'Calpheon',
          left: 10.4,
          top: 8.2,
          width: 45.8,
          height: 9.8,
        ),
        StillImageOcrLine(
          text: 'City Storage',
          left: 60,
          top: 8,
          width: 70,
          height: 10,
        ),
        StillImageOcrLine(text: '2', left: 20, top: 84, width: 7, height: 9),
        StillImageOcrLine(text: '04', left: 28, top: 84, width: 14, height: 9),
        StillImageOcrLine(text: '500', left: 82, top: 84, width: 24, height: 9),
        StillImageOcrLine(
          text: '1.8M',
          left: 137,
          top: 84,
          width: 28,
          height: 9,
        ),
        StillImageOcrLine(
          text: '900',
          left: 82.2,
          top: 84.1,
          width: 23.8,
          height: 8.9,
        ),
      ],
    );

    final draft = InventoryScreenshotRecognizer.fromCatalog(
      catalog,
    ).recognize(screenshotPng: png, ocr: ocr);

    expect(draft.suggestedLocationName, 'Calpheon City Storage');
    expect(draft.rows.map((row) => row.quantity), <int>[204, 500, 1800000]);
  });
}

({image.Image image, String dataUri}) _solidIcon(int r, int g, int b) {
  final icon = image.Image(width: 48, height: 48, numChannels: 4);
  image.fill(icon, color: image.ColorRgba8(r, g, b, 255));
  final bytes = image.encodePng(icon);
  return (image: icon, dataUri: 'data:image/png;base64,${base64Encode(bytes)}');
}

void _paintCell(image.Image target, int x, int y, image.Image icon) {
  image.compositeImage(target, icon, dstX: x, dstY: y);
}

CatalogSnapshot _catalog(Map<String, String> icons) {
  ModeCatalog mode(CraftMode mode) => ModeCatalog(
    mode: mode,
    items: <String, Recipe>{for (final name in icons.keys) name: _leaf(name)},
    iconDataUris: icons,
    defaults: const <String, Object?>{},
    metadata: const <String, Object?>{},
    searchAliases: const <String, String>{},
  );

  return CatalogSnapshot(
    sourceSha256: 'inventory-screenshot-test',
    sourceByteCount: 1,
    alchemy: mode(CraftMode.alchemy),
    cooking: mode(CraftMode.cooking),
    processing: mode(CraftMode.processing),
    supportingData: const <String, Object?>{},
    collisions: const <CaseCollision>[],
  );
}

Recipe _leaf(String name) => Recipe(
  name: name,
  type: 'material',
  baseOutput: 1,
  group: 'Materials',
  method: null,
  ingredients: const <Ingredient>[],
  marketId: null,
  sourceNote: null,
  vendor: null,
  location: null,
  npcPrice: 0,
  qualityBase: null,
  qualityGrade: null,
  outputMinimum: null,
  outputMaximum: null,
);
