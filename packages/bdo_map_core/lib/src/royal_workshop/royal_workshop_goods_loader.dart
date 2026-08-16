import 'dart:convert';

import 'package:flutter/services.dart';

import 'royal_workshop_models.dart';

class BdoRoyalWorkshopGoodsLoader {
  const BdoRoyalWorkshopGoodsLoader();

  static const String assetPath =
      'packages/bdo_map_core/assets/data/royal_workshop_goods.json';

  Future<List<BdoRoyalWorkshopGood>> load({AssetBundle? bundle}) async {
    final text = await (bundle ?? rootBundle).loadString(assetPath);
    final decoded = jsonDecode(text);
    if (decoded is! Map || decoded['goods'] is! List) {
      throw const FormatException('Invalid Royal Workshop goods dataset.');
    }
    return <BdoRoyalWorkshopGood>[
      for (final raw in decoded['goods'] as List)
        if (raw is Map)
          BdoRoyalWorkshopGood.fromJson(Map<Object?, Object?>.from(raw)),
    ];
  }
}
