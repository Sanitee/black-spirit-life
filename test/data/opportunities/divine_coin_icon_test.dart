import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:bdo_craft_planner_flutter/data/opportunities/exchange_catalog.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'Divine Coin loads the reviewed October artwork without recolouring',
    () async {
      final item = exchangeItems[980170]!;
      expect(item.name, 'Divine Coin');
      expect(item.iconAsset, 'assets/opportunities/items/980170.webp');
      final data = await rootBundle.load(item.iconAsset);
      final bytes = data.buffer.asUint8List(
        data.offsetInBytes,
        data.lengthInBytes,
      );
      expect(bytes, hasLength(1850));
      expect(
        sha256.convert(bytes).toString(),
        'fd72f1c415cade51ce72c8d329011c26f319512486b10ede564b829a9f0768e5',
      );
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      expect(frame.image.width, 44);
      expect(frame.image.height, 44);
      final pixels = (await frame.image.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      ))!;
      expect(
        pixels.getUint8(3),
        0,
        reason: 'Preserve transparent icon corners.',
      );
      frame.image.dispose();
      codec.dispose();

      final provenance =
          jsonDecode(
                File(
                  'assets/opportunities/icon-provenance.json',
                ).readAsStringSync(),
              )
              as Map<String, dynamic>;
      final record = (provenance['icons'] as List<Object?>)
          .cast<Map<String, Object?>>()
          .singleWhere((icon) => icon['id'] == 980170);
      expect(record['asset'], item.iconAsset);
      expect(
        record['sha256'].toString().toLowerCase(),
        sha256.convert(bytes).toString(),
      );
      expect(record['officialReference'], contains('10678'));
    },
  );
}
