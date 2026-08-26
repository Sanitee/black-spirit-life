import 'dart:io';
import 'dart:typed_data';

import 'package:bdo_craft_planner_flutter/app/window/native_inventory_ocr_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'loads the full normalized eligible gallery and skips unusable paths',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'native-inventory-ocr-gallery-',
      );
      addTearDown(() => root.delete(recursive: true));

      final helper = File(
        '${root.path}${Platform.pathSeparator}storage_ocr'
        '${Platform.pathSeparator}BlackSpiritStorageOcr.exe',
      );
      await helper.parent.create(recursive: true);
      await helper.writeAsBytes(const <int>[0]);

      const helperCandidateHash =
          'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
      const galleryOnlyHash =
          'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';
      const missingHash =
          'cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc';
      const emptyHash =
          'dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd';
      const helperCandidatePath = 'icons/items/$helperCandidateHash.webp';
      const galleryOnlyPath = 'icons/items/$galleryOnlyHash.webp';
      const missingPath = 'icons/items/$missingHash.webp';
      const emptyPath = 'icons/items/$emptyHash.webp';

      final artworkDirectory = Directory(
        '${helper.parent.path}${Platform.pathSeparator}Assets'
        '${Platform.pathSeparator}RecipeBook'
        '${Platform.pathSeparator}icons'
        '${Platform.pathSeparator}items',
      );
      await artworkDirectory.create(recursive: true);
      await File(
        '${artworkDirectory.path}${Platform.pathSeparator}'
        '$helperCandidateHash.webp',
      ).writeAsBytes(const <int>[1, 2, 3]);
      await File(
        '${artworkDirectory.path}${Platform.pathSeparator}'
        '$galleryOnlyHash.webp',
      ).writeAsBytes(const <int>[4, 5, 6, 7]);
      await File(
        '${artworkDirectory.path}${Platform.pathSeparator}$emptyHash.webp',
      ).writeAsBytes(const <int>[]);

      const helperCandidatePaths = <String>{helperCandidatePath};
      final loaded = await loadNativeInventoryArtworkGalleryForTesting(
        helper: helper,
        eligibleArtworkPaths: <String>[
          ' ICONS\\ITEMS\\${helperCandidateHash.toUpperCase()}.WEBP ',
          galleryOnlyPath,
          galleryOnlyPath,
          missingPath,
          emptyPath,
          '../icons/items/$galleryOnlyHash.webp',
          'icons/items/not-a-sha.webp',
          'icons/items/$missingHash.png',
        ],
      );

      expect(helperCandidatePaths, isNot(contains(galleryOnlyPath)));
      expect(loaded.keys, <String>[helperCandidatePath, galleryOnlyPath]);
      expect(loaded[helperCandidatePath], Uint8List.fromList(<int>[1, 2, 3]));
      expect(loaded[galleryOnlyPath], Uint8List.fromList(<int>[4, 5, 6, 7]));
      expect(loaded, isNot(contains(missingPath)));
      expect(loaded, isNot(contains(emptyPath)));
      expect(() => loaded[missingPath] = Uint8List(1), throwsUnsupportedError);
    },
  );
}
