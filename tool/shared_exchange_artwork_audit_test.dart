// Read-only audit of bundled exchange artwork versus shared reference lookup.
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:bdo_craft_planner_flutter/data/catalog/bundled_catalog_parser.dart';
import 'package:bdo_craft_planner_flutter/data/catalog/catalog_repository.dart';
import 'package:bdo_craft_planner_flutter/data/opportunities/exchange_catalog.dart';
import 'package:bdo_craft_planner_flutter/domain/models/craft_mode.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('enumerates exact shared exchange artwork coverage', () async {
    const target = String.fromEnvironment('BSL_ARTWORK_AUDIT_FILE');
    expect(target, isNotEmpty);
    final catalog = CatalogRepository(
      const BundledCatalogParser().parse(
        File('assets/data/app-data.json').readAsStringSync(),
      ),
    );
    final rows = [
      for (final item in exchangeItems.values)
        {
          'id': item.id,
          'name': item.name,
          'asset': item.iconAsset,
          'assetExists': File(item.iconAsset).existsSync(),
          'assetSha256': File(item.iconAsset).existsSync()
              ? sha256
                    .convert(File(item.iconAsset).readAsBytesSync())
                    .toString()
              : null,
          'sameNameIds': [
            for (final other in exchangeItems.values)
              if (other.name.toLowerCase() == item.name.toLowerCase()) other.id,
          ],
          'grade': catalog.itemIconGrade(item.name),
          'modes': {
            for (final mode in CraftMode.values)
              mode.key:
                  catalog.iconDataUri(
                    mode,
                    item.name,
                    preferCleanArtwork: true,
                  ) !=
                  null,
          },
        },
    ];
    for (final row in rows) {
      final bytes = File(row['asset'] as String).readAsBytesSync();
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      final image = frame.image;
      final rgba = (await image.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      ))!;
      row['dimensions'] = [image.width, image.height];
      row['cornerAlphas'] = [
        for (final offset in [
          0,
          image.width - 1,
          (image.height - 1) * image.width,
          image.height * image.width - 1,
        ])
          rgba.getUint8(offset * 4 + 3),
      ];
      image.dispose();
      codec.dispose();
    }
    File(target).writeAsStringSync(
      '${const JsonEncoder.withIndent('  ').convert(rows)}\n',
    );
  });
}
