import 'dart:io';

import 'package:bdo_craft_planner_flutter/app/window/native_inventory_ocr_service.dart';
import 'package:bdo_craft_planner_flutter/data/catalog/bundled_catalog_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final helperPath = Platform.environment['BSL_STORAGE_OCR_HELPER']?.trim();
  final fixturePath = Platform.environment['BSL_STORAGE_OCR_FIXTURE']?.trim();
  final dwarfFixturePath = Platform.environment['BSL_STORAGE_OCR_DWARF_FIXTURE']
      ?.trim();
  final enabled =
      helperPath?.isNotEmpty == true && fixturePath?.isNotEmpty == true;
  final dwarfEnabled =
      helperPath?.isNotEmpty == true && dwarfFixturePath?.isNotEmpty == true;

  test(
    'shared native OCR reaches the planner review model',
    () async {
      final catalog = const BundledCatalogParser().parse(
        File('assets/data/app-data.json').readAsStringSync(),
      );
      final service = NativeInventoryOcrService(helperPath: helperPath);
      final firstScan = service.scanPath(fixturePath!, catalog: catalog);
      await expectLater(
        service.scanPath(fixturePath, catalog: catalog),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            contains('already being recognized'),
          ),
        ),
      );
      final analysis = await firstScan;

      expect(analysis.fileName, 'full-45.png');
      expect(analysis.mimeType, 'image/png');
      expect(analysis.plannerItemNames, contains('Wolf Blood'));
      expect(analysis.draft.sourceWidth, 469);
      expect(analysis.draft.sourceHeight, 520);
      expect(analysis.draft.gridColumns, 9);
      expect(analysis.draft.gridRows, 10);
      expect(
        analysis.draft.allRows,
        hasLength(88),
        reason:
            'The two stuffed Shadow Lion trophy slots are decisively '
            'non-material and must not enter Inventory review.',
      );
      expect(
        analysis.draft.allRows.where((row) => row.quantity != null).length,
        greaterThanOrEqualTo(84),
      );
      expect(
        analysis.draft.allRows.any((row) => row.quantity == 25060),
        isTrue,
      );
      final sunflower = analysis.draft.allRows.singleWhere(
        (row) => row.slotId == 'r1c1',
      );
      expect(sunflower.quantityText, '1060');
      expect(sunflower.quantity, 1060);
      expect(sunflower.quantitySuggested, 1060);
      expect(analysis.draft.rows, isNotEmpty);
      expect(analysis.draft.hiddenRows, isEmpty);

      service.dispose();
      await expectLater(
        service.scanPath(fixturePath, catalog: catalog),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            contains('closed'),
          ),
        ),
      );
    },
    skip: enabled
        ? false
        : 'Set BSL_STORAGE_OCR_HELPER and BSL_STORAGE_OCR_FIXTURE.',
  );

  test(
    'native numeric grammar reaches the planner as a strict review suggestion',
    () async {
      final catalog = const BundledCatalogParser().parse(
        File('assets/data/app-data.json').readAsStringSync(),
      );
      final service = NativeInventoryOcrService(helperPath: helperPath);
      final analysis = await service.scanPath(
        dwarfFixturePath!,
        catalog: catalog,
      );
      final row = analysis.draft.allRows.single;

      expect(row.quantityText, '177.1K');
      expect(row.quantity, 177100);
      expect(row.quantitySuggested, 177100);
      expect(row.quantityApproximate, isTrue);

      service.dispose();
    },
    skip: dwarfEnabled
        ? false
        : 'Set BSL_STORAGE_OCR_HELPER and BSL_STORAGE_OCR_DWARF_FIXTURE.',
  );
}
