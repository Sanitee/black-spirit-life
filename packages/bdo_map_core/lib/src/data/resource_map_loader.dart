import 'dart:convert';

import 'package:flutter/services.dart';

import '../model/resource_map_data.dart';

class BdoResourceMapLoader {
  const BdoResourceMapLoader._();

  static const bundledAsset =
      'packages/bdo_map_core/assets/data/resource_map.json';

  static Future<BdoResourceMapDataset> loadBundled({
    AssetBundle? bundle,
  }) async {
    final jsonText = await (bundle ?? rootBundle).loadString(bundledAsset);
    return parse(jsonText);
  }

  static BdoResourceMapDataset parse(String jsonText) {
    final decoded = jsonDecode(jsonText);
    if (decoded is! Map<String, Object?>) {
      throw const FormatException('Resource-map root must be a JSON object.');
    }
    final dataset = BdoResourceMapDataset.fromJson(decoded);
    if (dataset.manifest.schemaVersion != 1) {
      throw FormatException(
        'Unsupported resource-map schema '
        '${dataset.manifest.schemaVersion}; expected 1.',
      );
    }
    return dataset;
  }
}
