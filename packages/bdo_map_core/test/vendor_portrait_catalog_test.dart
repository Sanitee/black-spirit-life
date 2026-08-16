import 'dart:convert';
import 'dart:io';

import 'package:bdo_map_core/bdo_map_core.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const manifestPath = '../../docs/vendor-npc-portrait-provenance.json';
  const packageAssetPrefix = 'packages/bdo_map_core/';

  test('pins the complete active NPC portrait bundle', () {
    final manifest =
        jsonDecode(File(manifestPath).readAsStringSync())
            as Map<String, dynamic>;
    final portraits = (manifest['portraits']! as List<dynamic>)
        .cast<Map<String, dynamic>>();
    final mappings = (manifest['vendorMappings']! as List<dynamic>)
        .cast<Map<String, dynamic>>();

    expect(manifest['schemaVersion'], 1);
    expect(manifest['status'], 'publicNoncommercialFanContent');
    expect(manifest['owner'], 'Pearl Abyss Corp.');
    expect(portraits, hasLength(231));
    expect(mappings, hasLength(251));
    expect(bdoBundledVendorPortraitAssets, hasLength(251));
    expect(
      bdoBundledVendorPortraitAsset('npc:46022:1'),
      'packages/bdo_map_core/assets/images/vendor_portraits/ic_01248.webp',
      reason: 'Siemo must use the reviewed character portrait.',
    );
    expect(
      bdoBundledVendorPortraitAsset('npc:47763:26'),
      isNull,
      reason: 'The empty 40x40 source placeholder must not be enlarged.',
    );

    final portraitsByAsset = <String, Map<String, dynamic>>{
      for (final portrait in portraits)
        portrait['assetName']! as String: portrait,
    };
    for (final entry in bdoBundledVendorPortraitAssets.entries) {
      expect(entry.value, startsWith(packageAssetPrefix));
      expect(entry.value, isNot(contains('://')));
      final assetName = entry.value.split('/').last;
      expect(portraitsByAsset, contains(assetName));
      expect(
        mappings,
        contains(
          predicate<Map<String, dynamic>>(
            (mapping) =>
                mapping['sourceVendorId'] == entry.key &&
                mapping['assetName'] == assetName,
          ),
        ),
      );
    }

    for (final portrait in portraits) {
      final assetName = portrait['assetName']! as String;
      final asset = File('assets/images/vendor_portraits/$assetName');
      expect(asset.existsSync(), isTrue, reason: assetName);
      final bytes = asset.readAsBytesSync();
      expect(bytes, hasLength(portrait['bytes']! as int), reason: assetName);
      expect(
        sha256.convert(bytes).toString(),
        portrait['sha256'],
        reason: assetName,
      );
    }
  });

  test('keeps remote portrait details outside the runtime map payload', () {
    final mapJson = File('assets/data/resource_map.json').readAsStringSync();

    expect(mapJson, isNot(contains('sourcePortraitPath')));
    expect(mapJson, isNot(contains('/items/ui_artwork/')));
    expect(mapJson, isNot(contains('data:image')));
  });
}
