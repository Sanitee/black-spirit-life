import 'dart:io';
import 'dart:typed_data';

import 'package:bdo_craft_planner_flutter/data/catalog/bundled_catalog_parser.dart';
import 'package:bdo_craft_planner_flutter/features/inventory/inventory_screenshot_recognition.dart';
import 'package:crypto/crypto.dart';

Future<void> main(List<String> arguments) async {
  final verifyOnly = arguments.contains('--verify');
  final recipeBookRoot = Directory(
    'windows/storage_ocr/BlackSpiritStorageOcr/Assets/RecipeBook',
  );
  final recipeBookFile = File('${recipeBookRoot.path}/recipes.json');
  final iconIndexFile = File('${recipeBookRoot.path}/ocr/icon-index.json');
  final catalog = const BundledCatalogParser().parse(
    await File('assets/data/app-data.json').readAsString(),
  );
  final materialCatalog = InventoryOcrMaterialCatalog.fromRecipeBookJson(
    catalog: catalog,
    recipeBookJson: await recipeBookFile.readAsString(),
    recipeBookIconIndexJson: await iconIndexFile.readAsString(),
  );

  final nativeArtwork = <String, Uint8List>{};
  final paths = materialCatalog.nativeArtworkPaths.toList(growable: false)
    ..sort();
  for (final path in paths) {
    final file = File('${recipeBookRoot.path}/${path.replaceAll('/', '\\')}');
    if (!await file.exists()) continue;
    nativeArtwork[path] = await file.readAsBytes();
  }
  final artifact = buildInventoryOcrTemplateCache(
    catalog: materialCatalog,
    nativeArtworkBytes: nativeArtwork,
  );
  final outputDirectory = Directory('${recipeBookRoot.path}/AppMatcher');
  final indexFile = File(
    '${outputDirectory.path}/inventory-ocr-templates.json',
  );
  final rgbFile = File('${outputDirectory.path}/inventory-ocr-templates.rgb');

  if (verifyOnly) {
    if (!await indexFile.exists() || !await rgbFile.exists()) {
      stderr.writeln('The generated inventory OCR artwork cache is missing.');
      exitCode = 1;
      return;
    }
    final actualIndex = await indexFile.readAsString();
    final actualRgb = await rgbFile.readAsBytes();
    if (actualIndex != artifact.indexJson ||
        !_bytesEqual(actualRgb, artifact.rgbBytes)) {
      stderr.writeln('The generated inventory OCR artwork cache is stale.');
      exitCode = 1;
      return;
    }
  } else {
    await outputDirectory.create(recursive: true);
    await indexFile.writeAsString(artifact.indexJson, flush: true);
    await rgbFile.writeAsBytes(artifact.rgbBytes, flush: true);
  }

  stdout.writeln(
    'Inventory OCR artwork cache: ${artifact.rgbBytes.length} bytes, '
    'SHA-256 ${sha256.convert(artifact.rgbBytes)}',
  );
}

bool _bytesEqual(List<int> left, List<int> right) {
  if (left.length != right.length) return false;
  for (var index = 0; index < left.length; index += 1) {
    if (left[index] != right[index]) return false;
  }
  return true;
}
