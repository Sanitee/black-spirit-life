import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:bdo_craft_planner_flutter/app/window/native_inventory_ocr_service.dart';
import 'package:bdo_craft_planner_flutter/data/catalog/bundled_catalog_parser.dart';
import 'package:bdo_craft_planner_flutter/features/inventory/inventory_action_keys.dart';
import 'package:bdo_craft_planner_flutter/features/inventory/inventory_screenshot_recognition.dart';
import 'package:bdo_craft_planner_flutter/visual/components/app_form_controls.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image;

import '../features/inventory/inventory_test_fixture.dart';

void main() {
  final helperPath = Platform.environment['BSL_STORAGE_OCR_HELPER']?.trim();
  final screenshotPath = Platform.environment['BSL_STORAGE_OCR_DIAGNOSTIC']
      ?.trim();
  final quantityFilter =
      Platform.environment['BSL_STORAGE_OCR_DIAGNOSTIC_QUANTITIES']
          ?.split(',')
          .map((value) => int.tryParse(value.trim()))
          .whereType<int>()
          .toSet() ??
      const <int>{};
  final repeatCount =
      int.tryParse(
        Platform.environment['BSL_STORAGE_OCR_DIAGNOSTIC_REPEAT'] ?? '',
      )?.clamp(1, 10) ??
      1;
  final timingOnly =
      Platform.environment['BSL_STORAGE_OCR_DIAGNOSTIC_TIMING_ONLY'] == '1';
  final prewarm =
      Platform.environment['BSL_STORAGE_OCR_DIAGNOSTIC_PREWARM'] == '1';
  final legacyArtwork =
      Platform.environment['BSL_STORAGE_OCR_DIAGNOSTIC_LEGACY_ARTWORK'] == '1';
  final enabled =
      helperPath?.isNotEmpty == true && screenshotPath?.isNotEmpty == true;
  final rawIconBox = Platform.environment['BSL_STORAGE_OCR_ICON_BOX']?.trim();
  final rawIconCandidates = Platform
      .environment['BSL_STORAGE_OCR_ICON_CANDIDATES']
      ?.trim();
  final iconDiagnosticEnabled =
      screenshotPath?.isNotEmpty == true &&
      rawIconBox?.isNotEmpty == true &&
      rawIconCandidates?.isNotEmpty == true;

  test(
    'prints the complete reviewed recognition for a user storage screenshot',
    () async {
      final catalog = const BundledCatalogParser().parse(
        File('assets/data/app-data.json').readAsStringSync(),
      );
      var timedScan = 1;
      final service = NativeInventoryOcrService(
        helperPath: helperPath,
        usePreprocessedArtworkCache: !legacyArtwork,
        timingObserver: (stage, elapsed) {
          stdout.writeln(
            'OCR_SCAN_${timedScan}_${stage.toUpperCase()}_MS='
            '${elapsed.inMilliseconds}',
          );
          if (stage == 'total') timedScan += 1;
        },
      );
      try {
        if (prewarm) {
          final stopwatch = Stopwatch()..start();
          await service.prewarm(catalog: catalog);
          stopwatch.stop();
          stdout.writeln('OCR_PREWARM_MS=${stopwatch.elapsedMilliseconds}');
        }
        late InventoryScreenshotAnalysis analysis;
        for (var scan = 0; scan < repeatCount; scan += 1) {
          final stopwatch = Stopwatch()..start();
          analysis = await service.scanPath(screenshotPath!, catalog: catalog);
          stopwatch.stop();
          stdout.writeln(
            'OCR_SCAN_${scan + 1}_MS=${stopwatch.elapsedMilliseconds}',
          );
        }
        if (timingOnly) return;
        for (final row in analysis.draft.allRows) {
          if (quantityFilter.isNotEmpty &&
              !quantityFilter.contains(row.quantity)) {
            continue;
          }
          stdout.writeln(
            jsonEncode(<String, Object?>{
              'slot': row.slotId,
              'crop': <String, int>{
                'x': row.crop.left,
                'y': row.crop.top,
                'width': row.crop.width,
                'height': row.crop.height,
              },
              'quantity': row.quantity,
              'selected': row.selectedName,
              'relevance': row.relevance.name,
              'uncertain': row.itemSuggestionUncertain,
              'matches': <Object?>[
                for (final match in row.matches.take(64))
                  <String, Object?>{
                    'name': match.name,
                    'id': match.itemId,
                    'score': match.confidence,
                    'sourceScore': match.sourceVisualConfidence,
                    'artwork': match.artworkKey,
                    'group': match.orderGroupKey,
                    'shared': match.sharedArtwork,
                  },
              ],
            }),
          );
        }
      } finally {
        service.dispose();
      }
    },
    skip: !enabled,
    timeout: const Timeout(Duration(minutes: 2)),
  );

  testWidgets(
    'prints the final review selections for a user storage screenshot',
    (tester) async {
      final catalog = const BundledCatalogParser().parse(
        File('assets/data/app-data.json').readAsStringSync(),
      );
      final service = NativeInventoryOcrService(helperPath: helperPath);
      final analysis = await service.scanPath(
        screenshotPath!,
        catalog: catalog,
      );
      final harness = InventoryTestHarness(
        pasteScreenshot: () async => analysis,
      );
      try {
        await pumpInventory(tester, harness, size: const Size(1500, 940));
        await tester.tap(find.byKey(InventoryActionKeys.pasteScreenshot));
        await tester.pumpAndSettle();
        for (final chooser in tester.widgetList<AppSearchSelect<String>>(
          find.byType(AppSearchSelect<String>),
        )) {
          stdout.writeln('REVIEW ${chooser.value ?? '<blank>'}');
        }
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        harness.dispose();
        service.dispose();
      }
    },
    skip: !enabled,
  );

  test(
    'prints app-resolution reranking for an exact screenshot crop',
    () {
      final bytes = File(screenshotPath!).readAsBytesSync();
      final decodedImage = image.decodeImage(bytes);
      expect(decodedImage, isNotNull);
      final box = rawIconBox!
          .split(',')
          .map((value) => int.parse(value.trim()))
          .toList(growable: false);
      expect(box, hasLength(4));

      final catalog = const BundledCatalogParser().parse(
        File('assets/data/app-data.json').readAsStringSync(),
      );
      final recipeBook =
          jsonDecode(
                File(
                  'windows/storage_ocr/BlackSpiritStorageOcr/Assets/RecipeBook/recipes.json',
                ).readAsStringSync(),
              )
              as Map<String, Object?>;
      final items = recipeBook['items']! as Map<String, Object?>;
      final iconsByName = <String, String>{};
      for (final raw in items.values.whereType<Map<String, Object?>>()) {
        final name = raw['name'];
        final icon = raw['icon'];
        if (name is String && icon is String) iconsByName[name] = icon;
      }
      final candidateNames = rawIconCandidates!
          .split(',')
          .map((value) => value.trim())
          .where((value) => value.isNotEmpty)
          .toList(growable: false);
      final nativeArtworkBytes = <String, Uint8List>{};
      for (final name in candidateNames) {
        final path = iconsByName[name];
        if (path == null) continue;
        final file = File(
          'windows/storage_ocr/BlackSpiritStorageOcr/Assets/RecipeBook/$path',
        );
        if (file.existsSync()) {
          nativeArtworkBytes[path] = file.readAsBytesSync();
        }
      }
      final materialCatalog = InventoryOcrMaterialCatalog.fromRecipeBookJson(
        catalog: catalog,
        recipeBookJson: jsonEncode(recipeBook),
        recipeBookIconIndexJson: File(
          'windows/storage_ocr/BlackSpiritStorageOcr/Assets/RecipeBook/ocr/icon-index.json',
        ).readAsStringSync(),
      );
      final row = const InventoryScreenshotResultSanitizer()
          .sanitize(
            rawResult: <String, Object?>{
              'imageFingerprint': List<String>.filled(64, 'a').join(),
              'width': decodedImage!.width,
              'height': decodedImage.height,
              'grid': <String, Object?>{
                'columns': 1,
                'rows': 1,
                'confidence': 1,
              },
              'slots': <Object?>[
                <String, Object?>{
                  'id': 'r0c0',
                  'row': 0,
                  'column': 0,
                  'box': <String, Object?>{
                    'x': box[0],
                    'y': box[1],
                    'width': box[2],
                    'height': box[3],
                  },
                  'iconCandidates': <Object?>[
                    for (var index = 0; index < candidateNames.length; index++)
                      <String, Object?>{
                        'icon': iconsByName[candidateNames[index]],
                        'score': .90 - index * .01,
                        'materialEligible': true,
                      },
                  ],
                  'iconMaterialEligible': true,
                  'iconMaterialConfidence': .9,
                  'iconMaterialMargin': .2,
                  'borderGrade': 0,
                  'borderGradeConfidence': .9,
                  'quantityText': '1000',
                  'quantityValue': 1000,
                  'quantitySuggestedValue': null,
                  'quantityApproximate': false,
                  'quantityConfidence': .99,
                  'quantityAssumedOne': false,
                },
              ],
              'warnings': <Object?>[],
            },
            screenshotBytes: bytes,
            catalog: materialCatalog,
            nativeArtworkBytes: nativeArtworkBytes,
          )
          .rows
          .single;
      stdout.writeln(
        jsonEncode(<String, Object?>{
          'selected': row.selectedName,
          'matches': <Object?>[
            for (final match in row.matches.take(12))
              <String, Object?>{'name': match.name, 'score': match.confidence},
          ],
        }),
      );
    },
    skip: iconDiagnosticEnabled
        ? false
        : 'Set screenshot, icon box, and candidate environment variables.',
  );
}
