import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../../domain/models/catalog_models.dart';
import 'bundled_catalog_parser.dart';

class BundledDataService {
  BundledDataService({AssetBundle? bundle}) : bundle = bundle ?? rootBundle;

  final AssetBundle bundle;

  Future<CatalogSnapshot> load() async {
    final source = await bundle.loadString('assets/data/app-data.json');
    return compute(_parseProductionCatalog, source);
  }
}

CatalogSnapshot _parseProductionCatalog(String source) =>
    const BundledCatalogParser().parse(source);
