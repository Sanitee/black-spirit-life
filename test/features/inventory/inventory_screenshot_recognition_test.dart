import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:bdo_craft_planner_flutter/app/window/native_inventory_ocr_service.dart';
import 'package:bdo_craft_planner_flutter/data/catalog/bundled_catalog_parser.dart';
import 'package:bdo_craft_planner_flutter/domain/models/catalog_models.dart';
import 'package:bdo_craft_planner_flutter/domain/models/craft_mode.dart';
import 'package:bdo_craft_planner_flutter/features/inventory/inventory_screenshot_recognition.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image;

void main() {
  test('accepts only complete BDO quantity tokens', () {
    expect(parseStrictStorageQuantity('12,718'), 12718);
    expect(parseStrictStorageQuantity('219.8K'), 219800);
    expect(parseStrictStorageQuantity('1.3M'), 1300000);
    expect(parseStrictStorageQuantity('25060'), 25060);
    expect(parseStrictStorageQuantity('25.060'), isNull);
    expect(parseStrictStorageQuantity('-3'), isNull);
    expect(parseStrictStorageQuantity('73'), 73);
    expect(parseStrictStorageQuantity('113/161'), isNull);
    expect(parseStrictStorageQuantity('0'), isNull);
  });

  test('a reused post-processor stays identical to one-shot sanitizing', () {
    final screenshot = _png();
    final catalog = InventoryOcrMaterialCatalog.fromRecipeBookJson(
      catalog: _catalog(),
      recipeBookJson: _recipeBookJson(),
    );
    final artwork = <String, Uint8List>{
      'icons/items/${_digest('7')}.webp': screenshot,
    };
    Map<String, Object?> result(String fingerprint, int quantity) =>
        <String, Object?>{
          'imageFingerprint': fingerprint,
          'width': 64,
          'height': 64,
          'grid': <String, Object?>{'columns': 1, 'rows': 1, 'confidence': .99},
          'slots': <Object?>[
            _slot(
              id: 'r0c0',
              column: 0,
              icon: 'icons/items/${_digest('7')}.webp',
              quantity: quantity,
              borderGrade: 2,
            ),
          ],
          'warnings': <Object?>[],
        };

    final processor = InventoryScreenshotPostProcessor(
      catalog: catalog,
      nativeArtworkBytes: artwork,
    );
    for (final entry in <(String, int)>[
      (_digest('1'), 1060),
      (_digest('2'), 2000),
    ]) {
      final raw = result(entry.$1, entry.$2);
      final reused = processor
          .sanitize(rawResult: raw, screenshotBytes: screenshot)
          .rows
          .single;
      final oneShot = const InventoryScreenshotResultSanitizer()
          .sanitize(
            rawResult: raw,
            screenshotBytes: screenshot,
            catalog: catalog,
            nativeArtworkBytes: artwork,
          )
          .rows
          .single;

      expect(reused.selectedName, oneShot.selectedName);
      expect(reused.quantity, oneShot.quantity);
      expect(reused.itemSuggestionUncertain, oneShot.itemSuggestionUncertain);
      expect(
        reused.matches.map((match) => (match.name, match.confidence)),
        oneShot.matches.map((match) => (match.name, match.confidence)),
      );
    }
  });

  test('preprocessed artwork cache preserves exact recognition output', () {
    final screenshot = _png();
    final catalog = InventoryOcrMaterialCatalog.fromRecipeBookJson(
      catalog: _catalog(),
      recipeBookJson: _recipeBookJson(),
    );
    final icon = 'icons/items/${_digest('7')}.webp';
    final artwork = <String, Uint8List>{icon: screenshot};
    final artifact = buildInventoryOcrTemplateCache(
      catalog: catalog,
      nativeArtworkBytes: artwork,
    );
    final cache = InventoryOcrPreprocessedTemplateCache.decode(
      indexJson: artifact.indexJson,
      rgbBytes: artifact.rgbBytes,
    );
    final raw = <String, Object?>{
      'imageFingerprint': _digest('3'),
      'width': 64,
      'height': 64,
      'grid': <String, Object?>{'columns': 1, 'rows': 1, 'confidence': .99},
      'slots': <Object?>[
        _slot(
          id: 'r0c0',
          column: 0,
          icon: icon,
          quantity: 12718,
          borderGrade: 2,
        ),
      ],
      'warnings': <Object?>[],
    };

    final legacy = InventoryScreenshotPostProcessor(
      catalog: catalog,
      nativeArtworkBytes: artwork,
    ).sanitize(rawResult: raw, screenshotBytes: screenshot);
    final cached = InventoryScreenshotPostProcessor(
      catalog: catalog,
      nativeArtworkBytes: const <String, Uint8List>{},
      preprocessedTemplateCache: cache,
    ).sanitize(rawResult: raw, screenshotBytes: screenshot);

    expect(cached.rows.single.selectedName, legacy.rows.single.selectedName);
    expect(cached.rows.single.quantity, legacy.rows.single.quantity);
    expect(
      cached.rows.single.matches.map(
        (match) => (match.name, match.confidence, match.sourceVisualConfidence),
      ),
      legacy.rows.single.matches.map(
        (match) => (match.name, match.confidence, match.sourceVisualConfidence),
      ),
    );
  });

  test('parallel slot workers preserve one-shot recognition exactly', () async {
    final screenshot = _png();
    final catalog = InventoryOcrMaterialCatalog.fromRecipeBookJson(
      catalog: _catalog(),
      recipeBookJson: _recipeBookJson(),
    );
    final icon = 'icons/items/${_digest('7')}.webp';
    final artwork = <String, Uint8List>{icon: screenshot};
    final slots = <Object?>[
      for (var index = 0; index < 7; index += 1)
        <String, Object?>{
          ..._slot(
            id: 'r0c$index',
            column: index,
            icon: icon,
            quantity: 1000 + index,
            borderGrade: 2,
          ),
          'box': <String, Object?>{
            'x': index.isEven ? 0 : 32,
            'y': 0,
            'width': 32,
            'height': 32,
          },
        },
    ];
    final raw = <String, Object?>{
      'imageFingerprint': _digest('4'),
      'width': 64,
      'height': 64,
      'grid': <String, Object?>{'columns': 7, 'rows': 1, 'confidence': .99},
      'slots': slots,
      'warnings': <Object?>['fixture warning'],
    };
    final oneShot = const InventoryScreenshotResultSanitizer().sanitize(
      rawResult: raw,
      screenshotBytes: screenshot,
      catalog: catalog,
      nativeArtworkBytes: artwork,
    );
    final parallel = await sanitizeInventoryScreenshotWithWorkerPoolForTesting(
      rawResult: raw,
      screenshotBytes: screenshot,
      catalog: catalog,
      nativeArtworkBytes: artwork,
    );

    Object rows(InventoryScreenshotDraft draft) => <Object?>[
      for (final row in draft.allRows)
        <String, Object?>{
          'slot': row.slotId,
          'quantity': row.quantity,
          'selected': row.selectedName,
          'review': row.reviewRequired,
          'matches': <Object?>[
            for (final match in row.matches)
              <Object?>[
                match.name,
                match.confidence,
                match.sourceVisualConfidence,
              ],
          ],
        },
    ];

    expect(rows(parallel), rows(oneShot));
    expect(parallel.warnings, oneShot.warnings);
    expect(parallel.imageFingerprint, oneShot.imageFingerprint);
  });

  test('catalog contains planner ingredients but excludes unrelated items', () {
    final catalog = InventoryOcrMaterialCatalog.fromRecipeBookJson(
      catalog: _catalog(),
      recipeBookJson: _recipeBookJson(),
    );

    expect(
      catalog.names,
      containsAll(<String>[
        'Wolf Blood',
        'Flamingo Blood',
        'Banana',
        'Milk',
        'Bird Meat',
        'Steaming Hot Grilled Bird Meat',
        'Simple Cron Meal',
        'High-Quality Sunflower',
        'Special Sunflower',
      ]),
    );
    expect(catalog.itemIds['bird meat'], 7953);
    expect(catalog.itemIds['steaming hot grilled bird meat'], 9493);
    expect(catalog.names, isNot(contains('Krea Noble Sword')));
  });

  test(
    'catalog icon sizing skips malformed artwork and keeps the largest valid image',
    () {
      image.Image artwork({required int extent, required image.Color color}) {
        final result = image.Image(
          width: extent,
          height: extent,
          numChannels: 4,
        );
        image.fill(result, color: image.ColorRgba8(22, 23, 27, 255));
        final inset = (extent * .2).round();
        image.fillRect(
          result,
          x1: inset,
          y1: inset,
          x2: extent - inset - 1,
          y2: extent - inset - 1,
          color: color,
        );
        return result;
      }

      String dataUri(image.Image value) =>
          'data:image/png;base64,${base64Encode(image.encodePng(value))}';

      final smallerWrongArtwork = artwork(
        extent: 16,
        color: image.ColorRgba8(210, 45, 55, 255),
      );
      final largestArtwork = artwork(
        extent: 48,
        color: image.ColorRgba8(35, 205, 90, 255),
      );
      final distractorArtwork = artwork(
        extent: 48,
        color: image.ColorRgba8(210, 45, 55, 255),
      );
      final malformedBytes = Uint8List.fromList(
        image.encodePng(largestArtwork),
      );
      malformedBytes[29] = malformedBytes[29] ^ 0xff;
      final malformed = 'data:image/png;base64,${base64Encode(malformedBytes)}';

      final source = _catalog();
      ModeCatalog mode(CraftMode craftMode, Map<String, String> iconDataUris) {
        final sourceMode = source.forMode(craftMode);
        return ModeCatalog(
          mode: craftMode,
          items: sourceMode.items,
          iconDataUris: iconDataUris,
          defaults: sourceMode.defaults,
          metadata: sourceMode.metadata,
          searchAliases: sourceMode.searchAliases,
        );
      }

      final materialCatalog = InventoryOcrMaterialCatalog.fromRecipeBookJson(
        catalog: CatalogSnapshot(
          sourceSha256: source.sourceSha256,
          sourceByteCount: source.sourceByteCount,
          alchemy: mode(CraftMode.alchemy, <String, String>{
            'Banana': malformed,
            'Milk': dataUri(distractorArtwork),
          }),
          cooking: mode(CraftMode.cooking, <String, String>{
            'Banana': dataUri(smallerWrongArtwork),
          }),
          processing: mode(CraftMode.processing, <String, String>{
            'Banana': dataUri(largestArtwork),
          }),
          supportingData: source.supportingData,
          collisions: source.collisions,
        ),
        recipeBookJson: _recipeBookJson(),
      );
      final screenshotBytes = Uint8List.fromList(
        image.encodePng(largestArtwork),
      );

      final row = const InventoryScreenshotResultSanitizer()
          .sanitize(
            rawResult: <String, Object?>{
              'imageFingerprint': _digest('f'),
              'width': 48,
              'height': 48,
              'grid': <String, Object?>{
                'columns': 1,
                'rows': 1,
                'confidence': .99,
              },
              'slots': <Object?>[
                <String, Object?>{
                  'id': 'r0c0',
                  'row': 0,
                  'column': 0,
                  'box': <String, Object?>{
                    'x': 0,
                    'y': 0,
                    'width': 48,
                    'height': 48,
                  },
                  'iconCandidates': <Object?>[],
                  'iconMaterialEligible': null,
                  'iconMaterialConfidence': 0,
                  'iconMaterialMargin': 0,
                  'borderGrade': 0,
                  'borderGradeConfidence': 0,
                  'quantityText': '25',
                  'quantityValue': 25,
                  'quantitySuggestedValue': null,
                  'quantityApproximate': false,
                  'quantityConfidence': .99,
                  'quantityAssumedOne': false,
                },
              ],
              'warnings': <Object?>[],
            },
            screenshotBytes: screenshotBytes,
            catalog: materialCatalog,
          )
          .rows
          .single;

      expect(row.selectedName, 'Banana');
      expect(row.matches.first.sourceVisualConfidence, greaterThan(.9));
    },
  );

  test(
    'current clean Olivine Ore and Tiger Blood artwork supplements the old atlas',
    () {
      final source = const BundledCatalogParser().parse(
        File('assets/data/app-data.json').readAsStringSync(),
      );
      final catalog = InventoryOcrMaterialCatalog.fromRecipeBookJson(
        catalog: source,
        recipeBookJson: File(
          'windows/storage_ocr/BlackSpiritStorageOcr/Assets/RecipeBook/recipes.json',
        ).readAsStringSync(),
      );
      final artwork = source.supportingData['itemIconArtwork']! as Map;
      for (final item in const <(String, int)>[
        ('Olivine Ore', 4415),
        ('Tiger Blood', 6356),
      ]) {
        final uri = artwork[_foldTest(item.$1)]! as String;
        final bytes = base64Decode(uri.substring(uri.indexOf(',') + 1));
        final decoded = image.decodeImage(bytes)!;
        final screenshot = image.Image(
          width: decoded.width,
          height: decoded.height,
          numChannels: 4,
        );
        image.fill(screenshot, color: image.ColorRgba8(22, 23, 27, 255));
        image.compositeImage(screenshot, decoded);
        final screenshotPng = Uint8List.fromList(image.encodePng(screenshot));
        final slot = _slot(id: 'r0c0', column: 0, icon: '', quantity: 45)
          ..['box'] = <String, Object?>{
            'x': 0,
            'y': 0,
            'width': decoded.width,
            'height': decoded.height,
          }
          ..['iconCandidates'] = <Object?>[]
          ..['iconMaterialEligible'] = null
          ..['iconMaterialConfidence'] = 0
          ..['iconMaterialMargin'] = 0
          ..['borderGradeConfidence'] = 0;
        final row = const InventoryScreenshotResultSanitizer()
            .sanitize(
              rawResult: <String, Object?>{
                'imageFingerprint': _digest('a'),
                'width': decoded.width,
                'height': decoded.height,
                'grid': <String, Object?>{
                  'columns': 1,
                  'rows': 1,
                  'confidence': .99,
                },
                'slots': <Object?>[slot],
                'warnings': <Object?>[],
              },
              screenshotBytes: screenshotPng,
              catalog: catalog,
            )
            .rows
            .single;
        expect(
          row.matches,
          isNotEmpty,
          reason: '${item.$1} must have a usable visual template',
        );
        expect(row.matches.first.name, item.$1);
        expect(row.matches.first.itemId, item.$2);
        expect(row.selectedName, item.$1);
        expect(row.quantity, 45);
      }
    },
  );

  test('structured planner recipe evidence admits a null-flag helper item but '
      'not an explicit non-material trophy', () {
    final recipeBook = jsonDecode(_recipeBookJson()) as Map<String, Object?>;
    final items = recipeBook['items']! as Map<String, Object?>;
    items
      ..['519'] = <String, Object?>{
        'name': 'HP Potion (Large)',
        'grade': 0,
        'icon': 'icons/items/hp-potion-large.webp',
      }
      ..['3544'] = <String, Object?>{
        'name': 'Stuffed Shadow Lion Head',
        'grade': 2,
        'icon': 'icons/items/stuffed-shadow-lion-head.webp',
      };
    recipeBook['recipes'] = <Object?>[
      <String, Object?>{
        'outputId': 519,
        'type': 'SIMPLE_ALCHEMY',
        'inputs': <Object?>[
          <String, Object?>{'itemId': 518, 'count': 3},
        ],
      },
      <String, Object?>{
        'outputId': 999999,
        'type': 'SIMPLE_ALCHEMY',
        'inputs': <Object?>[
          <String, Object?>{'itemId': 3544, 'count': 1},
        ],
      },
    ];
    final iconIndex = jsonEncode(<String, Object?>{
      'icons': <Object?>[
        <String, Object?>{
          'icon': 'icons/items/hp-potion-large.webp',
          'materialEligible': null,
        },
        <String, Object?>{
          'icon': 'icons/items/stuffed-shadow-lion-head.webp',
          'materialEligible': false,
        },
      ],
    });

    final catalog = InventoryOcrMaterialCatalog.fromRecipeBookJson(
      catalog: _catalog(),
      recipeBookJson: jsonEncode(recipeBook),
      recipeBookIconIndexJson: iconIndex,
    );

    expect(catalog.names, contains('HP Potion (Large)'));
    expect(catalog.itemIds['hp potion (large)'], 519);
    expect(catalog.names, isNot(contains('Stuffed Shadow Lion Head')));
    expect(catalog.itemIds['stuffed shadow lion head'], isNull);
  });

  test('production OCR catalog covers every real life-skill input and result', () {
    final source = const BundledCatalogParser().parse(
      File('assets/data/app-data.json').readAsStringSync(),
    );
    final recipeBookSource = File(
      'windows/storage_ocr/BlackSpiritStorageOcr/Assets/RecipeBook/recipes.json',
    ).readAsStringSync();
    final iconIndexSource = File(
      'windows/storage_ocr/BlackSpiritStorageOcr/Assets/RecipeBook/ocr/icon-index.json',
    ).readAsStringSync();
    final catalog = InventoryOcrMaterialCatalog.fromRecipeBookJson(
      catalog: source,
      recipeBookJson: recipeBookSource,
      recipeBookIconIndexJson: iconIndexSource,
    );
    final expected = <String, String>{};
    final iconNames = <String>{};

    void include(String name) {
      final trimmed = name.trim();
      if (trimmed.isNotEmpty) {
        expected.putIfAbsent(_foldTest(trimmed), () => trimmed);
      }
    }

    for (final mode in CraftMode.values) {
      final modeCatalog = source.forMode(mode);
      iconNames.addAll(modeCatalog.iconDataUris.keys.map(_foldTest));
      for (final recipe in modeCatalog.items.values) {
        if (recipe.isReferenceOnly) continue;
        include(recipe.name);
        for (final ingredients in <Iterable<Ingredient>>[
          recipe.ingredients,
          for (final variant in recipe.variants) variant.ingredients,
        ]) {
          for (final ingredient in ingredients) {
            include(ingredient.name);
            for (final option in ingredient.options) {
              include(option);
            }
          }
        }
      }
    }

    final actual = catalog.names.map(_foldTest).toSet();
    final missing = expected.keys.where((name) => !actual.contains(name));
    expect(
      missing,
      isEmpty,
      reason:
          'No Cooking, Alchemy, or Processing ingredient, substitute, '
          'intermediate, meal, elixir, draught, or real recipe result may '
          'silently disappear from storage recognition.',
    );
    final missingArtwork = expected.keys.where(
      (name) => !iconNames.contains(name),
    );
    expect(
      missingArtwork,
      isEmpty,
      reason:
          'Every recognized planner identity needs app-owned artwork so the '
          'sealed native OCR can be supplemented without guessing by name.',
    );
    expect(
      catalog.names,
      containsAll(<String>[
        'Deep Frying Oil',
        'Tiger Meat',
        'Vedelona',
        'Green Pendulous Mushroom',
        'Big Tiger Mushroom',
        'Big Dwarf Mushroom',
        'Big Emperor Mushroom',
        'Big Fortune Mushroom',
        'Old Tree Bark',
        'Thuja Sap',
        'Barley Flour',
        'Wheat Flour',
        'Potato Flour',
        'Seafood Cron Meal',
        'Simple Cron Meal',
        'Steaming Hot Grilled Bird Meat',
        'Elixir of Steel Defense',
        'Harmony Draught',
      ]),
    );
    expect(catalog.itemIds['meat pie'], 9265);
    expect(catalog.itemIds['refined oatmeal'], 9276);
    expect(catalog.itemIds['big fortune mushroom'], 5426);
    expect(
      catalog.itemIds['waragon blood'],
      6215,
      reason:
          'The helper overlay uses a reserved synthetic record ID, but Auto '
          'Arrange must use the canonical current-client item ID.',
    );
    expect(catalog.itemIds['raccoon blood'], 6210);
    expect(catalog.names, isNot(contains('Big Fortune Teller Mushroom')));
    expect(catalog.names, isNot(contains('Shattered Star Fragment')));
    expect(catalog.names, isNot(contains('Weakened Reagent')));
    expect(catalog.itemOrderGroups['big ghost mushroom'], 'mushroom:big');
    expect(catalog.itemOrderGroups['big tiger mushroom'], 'mushroom:big');
    expect(catalog.itemOrderGroups['big sky mushroom'], 'mushroom:big');
    expect(catalog.itemOrderGroups['big cloud mushroom'], 'mushroom:big');
    Set<String> membersOf(String group) => catalog.itemOrderGroups.entries
        .where((entry) => entry.value == group)
        .map((entry) => entry.key)
        .toSet();
    expect(membersOf('grain:flour'), <String>{
      'wheat flour',
      'barley flour',
      'potato flour',
      'corn flour',
      'sweet potato flour',
    });
    expect(membersOf('grain:dough'), <String>{
      'wheat dough',
      'barley dough',
      'potato dough',
      'corn dough',
      'sweet potato dough',
    });
    for (final excluded in <String>[
      'teff flour',
      'freekeh flour',
      'rice flour',
      'teff dough',
      'freekeh dough',
      'rice dough',
    ]) {
      expect(
        catalog.itemOrderGroups[excluded],
        isNull,
        reason: '$excluded is not a member of BDO\'s common grain substitute.',
      );
    }

    final recipeBook = jsonDecode(recipeBookSource) as Map<String, Object?>;
    final iconIndex = jsonDecode(iconIndexSource) as Map<String, Object?>;
    final materialIcons = <String>{
      for (final raw in iconIndex['icons']! as List<Object?>)
        if (raw is Map<String, Object?> &&
            raw['materialEligible'] == true &&
            raw['icon'] is String)
          _normalizedIconForTest(raw['icon']! as String),
    };
    const lifeSkillTypes = <String>{
      'ALCHEMY',
      'COOK',
      'DRY',
      'FIREWOOD',
      'GRIND',
      'HEAT',
      'SHAKE',
      'SIMPLE_ALCHEMY',
      'SIMPLE_COOK',
      'THINNING',
    };
    final lifeSkillInputs = <int>{};
    final lifeSkillOutputs = <int>{};
    for (final raw in recipeBook['recipes']! as List<Object?>) {
      if (raw is! Map<String, Object?> ||
          !lifeSkillTypes.contains(raw['type'])) {
        continue;
      }
      final outputId = raw['outputId'];
      if (outputId is int) lifeSkillOutputs.add(outputId);
      for (final input in raw['inputs']! as List<Object?>) {
        if (input is Map<String, Object?> && input['itemId'] is int) {
          lifeSkillInputs.add(input['itemId']! as int);
        }
      }
    }
    final helperItems = recipeBook['items']! as Map<String, Object?>;
    final expectedHelperItems = <int, String>{};
    for (final entry in helperItems.entries) {
      final id = int.tryParse(entry.key);
      final raw = entry.value;
      if (id == null ||
          raw is! Map<String, Object?> ||
          raw['icon'] is! String ||
          !materialIcons.contains(
            _normalizedIconForTest(raw['icon']! as String),
          )) {
        continue;
      }
      final description = (raw['description'] as String? ?? '').toLowerCase();
      final byproduct =
          description.contains('byproduct of alchemy') ||
          description.contains('by-product of alchemy') ||
          description.contains('byproduct of cooking') ||
          description.contains('by-product of cooking');
      if (!lifeSkillInputs.contains(id) &&
          (!lifeSkillOutputs.contains(id) || byproduct)) {
        continue;
      }
      final name = raw['name'];
      if (name is String && name.trim().isNotEmpty) {
        expectedHelperItems[id] = name;
      }
    }
    final catalogIds = catalog.itemIds.values.toSet();
    final catalogNames = catalog.names.map(_foldTest).toSet();
    final missingHelperIds = <int>{
      for (final entry in expectedHelperItems.entries)
        if (!catalogIds.contains(entry.key) &&
            !catalogNames.contains(_foldTest(entry.value)))
          entry.key,
    };
    expect(
      missingHelperIds,
      isEmpty,
      reason:
          'Every material-classified input or useful result in the sealed '
          'life-skill recipe book must remain selectable, while incidental '
          'byproducts stay outside the planner inventory.',
    );
  });

  test('source-resolution artwork resolves mushrooms, oils, flours, and doughs', () {
    final source = const BundledCatalogParser().parse(
      File('assets/data/app-data.json').readAsStringSync(),
    );
    final recipeBookSource = File(
      'windows/storage_ocr/BlackSpiritStorageOcr/Assets/RecipeBook/recipes.json',
    ).readAsStringSync();
    final iconIndexSource = File(
      'windows/storage_ocr/BlackSpiritStorageOcr/Assets/RecipeBook/ocr/icon-index.json',
    ).readAsStringSync();
    final materialCatalog = InventoryOcrMaterialCatalog.fromRecipeBookJson(
      catalog: source,
      recipeBookJson: recipeBookSource,
      recipeBookIconIndexJson: iconIndexSource,
    );
    final helperItems =
        (jsonDecode(recipeBookSource) as Map<String, Object?>)['items']!
            as Map<String, Object?>;

    String helperIcon(String name) {
      for (final raw in helperItems.values.whereType<Map<String, Object?>>()) {
        if (raw['name'] == name && raw['icon'] is String) {
          return raw['icon']! as String;
        }
      }
      throw StateError('No sealed-helper icon for $name.');
    }

    InventoryScreenshotRow recognize({
      required String actualName,
      required List<({String name, double score})> nativeCandidates,
      bool? nativeMaterialEligible = true,
      Uint8List? screenshotOverride,
      List<String> extraNativeArtworkNames = const <String>[],
    }) {
      final screenshotBytes =
          screenshotOverride ?? _appIconScreenshot(source, actualName);
      final decodedScreenshot = image.decodeImage(screenshotBytes)!;
      final candidates = <Object?>[
        for (final candidate in nativeCandidates)
          <String, Object?>{
            'icon': helperIcon(candidate.name),
            'score': candidate.score,
            'materialEligible': nativeMaterialEligible,
          },
      ];
      final nativeArtworkBytes = <String, Uint8List>{};
      if (screenshotOverride != null) {
        for (final name in <String>{
          ...nativeCandidates.map((candidate) => candidate.name),
          ...extraNativeArtworkNames,
        }) {
          final icon = helperIcon(name);
          nativeArtworkBytes.putIfAbsent(
            icon,
            () => File(
              'windows/storage_ocr/BlackSpiritStorageOcr/Assets/RecipeBook/$icon',
            ).readAsBytesSync(),
          );
        }
      }
      final slot = <String, Object?>{
        'id': 'r0c0',
        'row': 0,
        'column': 0,
        'box': <String, Object?>{
          'x': 0,
          'y': 0,
          'width': decodedScreenshot.width,
          'height': decodedScreenshot.height,
        },
        'iconCandidates': candidates,
        'iconMaterialEligible': nativeMaterialEligible,
        'iconMaterialConfidence': .96,
        'iconMaterialMargin': .3,
        'borderGrade': 0,
        'borderGradeConfidence': .92,
        'quantityText': '1000',
        'quantityValue': 1000,
        'quantitySuggestedValue': null,
        'quantityApproximate': false,
        'quantityConfidence': .98,
        'quantityAssumedOne': false,
      };
      return const InventoryScreenshotResultSanitizer()
          .sanitize(
            rawResult: <String, Object?>{
              'imageFingerprint': _digest(
                actualName.codeUnitAt(0).toRadixString(16)[0],
              ),
              'width': decodedScreenshot.width,
              'height': decodedScreenshot.height,
              'grid': <String, Object?>{
                'columns': 1,
                'rows': 1,
                'confidence': .99,
              },
              'slots': <Object?>[slot],
              'warnings': <Object?>[],
            },
            screenshotBytes: screenshotBytes,
            catalog: materialCatalog,
            nativeArtworkBytes: nativeArtworkBytes,
          )
          .rows
          .single;
    }

    expect(
      recognize(
        actualName: 'Big Tiger Mushroom',
        nativeCandidates: <({String name, double score})>[
          (name: 'Dried Cherry Salmon', score: .81),
          (name: 'Dried Maomao', score: .80),
        ],
      ).selectedName,
      'Big Tiger Mushroom',
    );
    final oil = recognize(
      actualName: 'Deep Frying Oil',
      nativeCandidates: <({String name, double score})>[
        (name: 'Olive Oil', score: .85),
        (name: 'Deep Frying Oil', score: .845),
      ],
    );
    expect(
      oil.selectedName,
      'Deep Frying Oil',
      reason: oil.matches
          .map((match) => '${match.name}:${match.confidence}')
          .join(', '),
    );
    final stormsFamily = recognize(
      actualName: 'Oil of Storms',
      nativeCandidates: <({String name, double score})>[
        (name: 'Bottle of Turbid Water', score: .85),
        (name: 'Oil of Storms', score: .85),
      ],
    );
    final storms = stormsFamily.matches.singleWhere(
      (match) => match.name == 'Oil of Storms',
    );
    final turbid = stormsFamily.matches.singleWhere(
      (match) => match.name == 'Bottle of Turbid Water',
    );
    expect(storms.artworkKey, turbid.artworkKey);
    expect(storms.sharedArtwork, isTrue);
    expect(turbid.sharedArtwork, isTrue);
    expect(stormsFamily.selectedName, 'Oil of Storms');
    expect(stormsFamily.itemSuggestionUncertain, isTrue);
    expect(
      recognize(
        actualName: 'Potato Flour',
        nativeCandidates: <({String name, double score})>[
          (name: 'Wheat Flour', score: .85),
          (name: 'Potato Flour', score: .845),
        ],
      ).selectedName,
      'Potato Flour',
    );
    expect(
      recognize(
        actualName: 'Potato Dough',
        nativeCandidates: <({String name, double score})>[
          (name: 'Wheat Dough', score: .85),
          (name: 'Potato Dough', score: .845),
        ],
      ).selectedName,
      'Potato Dough',
    );
    final bigDwarf = recognize(
      actualName: 'Big Dwarf Mushroom',
      nativeMaterialEligible: false,
      nativeCandidates: <({String name, double score})>[
        (name: 'Dried Cherry Salmon', score: .84),
        (name: 'Dried Maomao', score: .81),
      ],
    );
    expect(
      bigDwarf.selectedName,
      'Big Dwarf Mushroom',
      reason: bigDwarf.matches
          .map((match) => '${match.name}:${match.confidence}')
          .join(', '),
    );
    final bigEmperor = recognize(
      actualName: 'Big Emperor Mushroom',
      screenshotOverride: base64Decode(_bigEmperorUserCropBase64),
      nativeCandidates: <({String name, double score})>[
        (name: 'Big Sky Mushroom', score: .9543),
        (name: 'Big Ghost Mushroom', score: .9414),
        (name: 'Big Cloud Mushroom', score: .9398),
        (name: 'Big Fortune Teller Mushroom', score: .8589),
      ],
    );
    expect(
      bigEmperor.selectedName,
      'Big Emperor Mushroom',
      reason: bigEmperor.matches
          .map(
            (match) =>
                '${match.name}:${match.confidence}/${match.sourceVisualConfidence}',
          )
          .join(', '),
    );
    expect(bigEmperor.matches.first.sourceVisualConfidence, greaterThan(.90));

    final elder = recognize(
      actualName: 'Elder Tree Sap',
      screenshotOverride: base64Decode(_elderSapUserCropBase64),
      extraNativeArtworkNames: const <String>['Elder Tree Sap'],
      nativeCandidates: <({String name, double score})>[
        (name: 'Acacia Sap', score: .8281),
        (name: 'Thornwood Sap', score: .7721),
        (name: 'Cactus Sap', score: .7598),
      ],
    );
    expect(
      elder.selectedName,
      'Elder Tree Sap',
      reason: elder.matches
          .take(12)
          .map(
            (match) =>
                '${match.name}:${match.confidence}/${match.sourceVisualConfidence}',
          )
          .join(', '),
    );
    expect(
      elder.matches.first.sourceVisualConfidence,
      greaterThan(
        elder.matches
            .singleWhere((match) => match.name == 'Acacia Sap')
            .sourceVisualConfidence!,
      ),
    );

    final acacia = recognize(
      actualName: 'Acacia Sap',
      screenshotOverride: base64Decode(_acaciaSapUserCropBase64),
      nativeCandidates: <({String name, double score})>[
        (name: 'Acacia Sap', score: .8428),
        (name: 'Elder Tree Sap', score: .8325),
        (name: 'Cactus Sap', score: .7703),
        (name: 'Thornwood Sap', score: .7615),
      ],
    );
    expect(acacia.selectedName, 'Acacia Sap');
    expect(
      acacia.matches.first.sourceVisualConfidence,
      greaterThan(
        acacia.matches
            .singleWhere((match) => match.name == 'Elder Tree Sap')
            .sourceVisualConfidence!,
      ),
    );
    final thuja = recognize(
      actualName: 'Thuja Sap',
      screenshotOverride: base64Decode(_thujaSapUserCropBase64),
      nativeCandidates: <({String name, double score})>[
        (name: 'Thuja Sap', score: .8545),
        (name: 'Fir Sap', score: .8492),
        (name: 'Cedar Sap', score: .8490),
        (name: 'Birch Sap', score: .8275),
        (name: 'White Cedar Sap', score: .7880),
        (name: 'Thornwood Sap', score: .7739),
      ],
    );
    expect(
      thuja.selectedName,
      'Thuja Sap',
      reason: thuja.matches
          .map((match) => '${match.name}:${match.confidence}')
          .join(', '),
    );
    final ash = recognize(
      actualName: 'Ash Sap',
      nativeCandidates: <({String name, double score})>[
        (name: 'Loopy Tree Sap', score: .90),
        (name: 'Ash Sap', score: .89),
        (name: 'White Cedar Sap', score: .88),
        (name: 'Thuja Sap', score: .87),
      ],
    );
    expect(
      ash.selectedName,
      'Ash Sap',
      reason: ash.matches
          .map((match) => '${match.name}:${match.confidence}')
          .join(', '),
    );

    final driedFish = recognize(
      actualName: 'Dried Maomao',
      nativeCandidates: <({String name, double score})>[
        (name: 'Dried Grouper', score: .85),
      ],
    );
    final grouper = driedFish.matches.singleWhere(
      (match) => match.name == 'Dried Grouper',
    );
    final maomao = driedFish.matches.singleWhere(
      (match) => match.name == 'Dried Maomao',
    );
    expect(grouper.artworkKey, maomao.artworkKey);
    expect(
      maomao.confidence,
      closeTo(grouper.confidence, 0.0000001),
      reason:
          'App-data framing must not create false visual certainty between '
          'fish that use byte-identical installed-client artwork.',
    );
    expect(driedFish.selectedName, driedFish.matches.first.name);
    expect(driedFish.itemSuggestionUncertain, isTrue);
  });

  test(
    'known out-of-scope helper identities cannot become lower material guesses',
    () {
      final source = const BundledCatalogParser().parse(
        File('assets/data/app-data.json').readAsStringSync(),
      );
      final recipeBookSource = File(
        'windows/storage_ocr/BlackSpiritStorageOcr/Assets/RecipeBook/recipes.json',
      ).readAsStringSync();
      final helperItems =
          (jsonDecode(recipeBookSource) as Map<String, Object?>)['items']!
              as Map<String, Object?>;
      final catalog = InventoryOcrMaterialCatalog.fromRecipeBookJson(
        catalog: source,
        recipeBookJson: recipeBookSource,
        recipeBookIconIndexJson: File(
          'windows/storage_ocr/BlackSpiritStorageOcr/Assets/RecipeBook/ocr/icon-index.json',
        ).readAsStringSync(),
      );

      String helperIcon(String name) {
        for (final raw
            in helperItems.values.whereType<Map<String, Object?>>()) {
          if (raw['name'] == name && raw['icon'] is String) {
            return raw['icon']! as String;
          }
        }
        throw StateError('No sealed-helper icon for $name.');
      }

      final blank = image.Image(width: 48, height: 48, numChannels: 4);
      image.fill(blank, color: image.ColorRgba8(22, 23, 27, 255));
      final screenshotBytes = Uint8List.fromList(image.encodePng(blank));

      InventoryScreenshotDraft recognize({
        required String topName,
        required bool? topMaterial,
        required bool? aggregateMaterial,
      }) => const InventoryScreenshotResultSanitizer().sanitize(
        rawResult: <String, Object?>{
          'imageFingerprint': _digest('a'),
          'width': 48,
          'height': 48,
          'grid': <String, Object?>{'columns': 1, 'rows': 1, 'confidence': .99},
          'slots': <Object?>[
            <String, Object?>{
              'id': 'r0c0',
              'row': 0,
              'column': 0,
              'box': <String, Object?>{
                'x': 0,
                'y': 0,
                'width': 48,
                'height': 48,
              },
              'iconCandidates': <Object?>[
                <String, Object?>{
                  'icon': helperIcon(topName),
                  'score': .96,
                  'materialEligible': topMaterial,
                },
                <String, Object?>{
                  'icon': helperIcon('Barley Flour'),
                  'score': .82,
                  'materialEligible': true,
                },
              ],
              'iconMaterialEligible': aggregateMaterial,
              'iconMaterialConfidence': .96,
              'iconMaterialMargin': .3,
              'borderGrade': 0,
              'borderGradeConfidence': .92,
              'quantityText': '147',
              'quantityValue': 147,
              'quantitySuggestedValue': null,
              'quantityApproximate': false,
              'quantityConfidence': .98,
              'quantityAssumedOne': false,
            },
          ],
          'warnings': <Object?>[],
        },
        screenshotBytes: screenshotBytes,
        catalog: catalog,
      );

      for (final draft in <InventoryScreenshotDraft>[
        recognize(
          topName: 'Shattered Star Fragment',
          topMaterial: true,
          aggregateMaterial: true,
        ),
        recognize(
          topName: 'Weakened Reagent',
          topMaterial: false,
          aggregateMaterial: null,
        ),
      ]) {
        expect(draft.rows, isEmpty);
        expect(draft.hiddenRows, isEmpty);
      }
    },
  );

  test('shared bird artwork keeps every item in descending ID order', () {
    final bytes = _png();
    final catalog = InventoryOcrMaterialCatalog.fromRecipeBookJson(
      catalog: _catalog(),
      recipeBookJson: _recipeBookJson(),
    );
    final result = <String, Object?>{
      'imageFingerprint': _digest('6'),
      'width': 64,
      'height': 64,
      'grid': <String, Object?>{'columns': 1, 'rows': 1, 'confidence': .99},
      'slots': <Object?>[
        _slot(
          id: 'r0c0',
          column: 0,
          icon: 'icons/items/${_digest('6')}.webp',
          quantity: 10844,
        ),
      ],
      'warnings': <Object?>[],
    };

    final row = const InventoryScreenshotResultSanitizer()
        .sanitize(rawResult: result, screenshotBytes: bytes, catalog: catalog)
        .rows
        .single;

    expect(row.selectedName, 'Bird Meat');
    expect(row.itemSuggestionUncertain, isTrue);
    expect(row.matches.map((match) => match.name), <String>[
      'Bird Meat',
      'Chicken Meat',
      'Flamingo Meat',
      'Kuku Bird Meat',
    ]);
    expect(row.matches.map((match) => match.itemId), <int?>[
      7953,
      7921,
      7917,
      7916,
    ]);
  });

  test(
    'weak unrelated app artwork cannot displace a structured blood family',
    () {
      InventoryScreenshotRow recognize({required bool structured}) {
        final fixture = _structuredBloodAppCompetitionFixture(
          structured: structured,
        );
        final catalog = InventoryOcrMaterialCatalog.fromRecipeBookJson(
          catalog: fixture.catalog,
          recipeBookJson: fixture.recipeBookJson,
        );
        final decoded = image.decodeImage(fixture.screenshotBytes)!;
        final result = <String, Object?>{
          'imageFingerprint': _digest(structured ? '2' : '3'),
          'width': decoded.width,
          'height': decoded.height,
          'grid': <String, Object?>{'columns': 1, 'rows': 1, 'confidence': .99},
          'slots': <Object?>[
            <String, Object?>{
              'id': 'r0c0',
              'row': 0,
              'column': 0,
              'box': <String, Object?>{
                'x': 0,
                'y': 0,
                'width': decoded.width,
                'height': decoded.height,
              },
              'iconCandidates': <Object?>[
                <String, Object?>{
                  'icon': _structuredBloodIcon,
                  'score': .705,
                  'materialEligible': true,
                },
                <String, Object?>{
                  'icon': _structuredHerbalIcon,
                  'score': .70,
                  'materialEligible': true,
                },
              ],
              'iconMaterialEligible': true,
              'iconMaterialConfidence': .96,
              'iconMaterialMargin': .3,
              'borderGrade': 0,
              'borderGradeConfidence': .92,
              'quantityText': '563',
              'quantityValue': 563,
              'quantitySuggestedValue': null,
              'quantityApproximate': false,
              'quantityConfidence': .98,
              'quantityAssumedOne': false,
            },
          ],
          'warnings': <Object?>[],
        };
        return const InventoryScreenshotResultSanitizer()
            .sanitize(
              rawResult: result,
              screenshotBytes: fixture.screenshotBytes,
              catalog: catalog,
            )
            .rows
            .single;
      }

      final unstructured = recognize(structured: false);
      expect(
        unstructured.matches.first.name,
        'Goat Blood',
        reason:
            'A broad app-template pass may add a missing identity, but it must '
            'not overwrite an observed native candidate with inconsistent '
            'planner-thumbnail framing.',
      );

      final row = recognize(structured: true);
      final bloodMatches = row.matches
          .where((match) => match.orderGroupKey == 'blood:all')
          .toList(growable: false);

      expect(
        row.matches.first.name,
        'Goat Blood',
        reason:
            'A modest source-resolution score for an unrelated app template '
            'must not outrank the native structured blood family.',
      );
      expect(
        bloodMatches.map((match) => match.name),
        <String>['Goat Blood', 'Llama Blood', 'Ox Blood'],
        reason:
            'Every member backed by the exact native bottle artwork must '
            'remain available for correction.',
      );
      expect(
        bloodMatches.every(
          (match) =>
              match.artworkKey == _structuredBloodIcon &&
              match.orderGroupKey == 'blood:all',
        ),
        isTrue,
      );
      expect(
        row.matches.indexWhere((match) => match.name == 'Herbal Juice'),
        greaterThanOrEqualTo(bloodMatches.length),
      );
      expect(
        row.selectedName,
        'Goat Blood',
        reason:
            'Identical blood bottles prefill the best structured guess for '
            'amber review rather than becoming unrelated Herbal Juice.',
      );
      expect(row.itemSuggestionUncertain, isTrue);
    },
  );

  test(
    'shared salt artwork carries structured primary-ingredient evidence',
    () {
      final bytes = _png();
      final catalog = InventoryOcrMaterialCatalog.fromRecipeBookJson(
        catalog: _catalog(),
        recipeBookJson: _recipeBookJson(),
      );
      final result = <String, Object?>{
        'imageFingerprint': _digest('0'),
        'width': 64,
        'height': 64,
        'grid': <String, Object?>{'columns': 1, 'rows': 1, 'confidence': .99},
        'slots': <Object?>[
          _slot(
            id: 'r0c0',
            column: 0,
            icon: 'icons/items/${_digest('0')}.webp',
            quantity: 45065,
          ),
        ],
        'warnings': <Object?>[],
      };

      final matches = const InventoryScreenshotResultSanitizer()
          .sanitize(rawResult: result, screenshotBytes: bytes, catalog: catalog)
          .rows
          .single
          .matches;

      expect(
        matches.map((match) => match.name),
        containsAll(<String>['Salt', 'Sun-Dried Salt']),
      );

      final salt = matches.singleWhere((match) => match.name == 'Salt');
      final sunDried = matches.singleWhere(
        (match) => match.name == 'Sun-Dried Salt',
      );
      expect(salt.primaryIngredientUseCount, greaterThan(0));
      expect(sunDried.primaryIngredientUseCount, 0);
    },
  );

  test('one shared artwork can expand beyond twelve planner items', () {
    final bytes = _png();
    final catalog = InventoryOcrMaterialCatalog.fromRecipeBookJson(
      catalog: _catalog(),
      recipeBookJson: _recipeBookJson(),
    );
    final result = <String, Object?>{
      'imageFingerprint': _digest('5'),
      'width': 64,
      'height': 64,
      'grid': <String, Object?>{'columns': 1, 'rows': 1, 'confidence': .99},
      'slots': <Object?>[
        _slot(
          id: 'r0c0',
          column: 0,
          icon: 'icons/items/${_digest('5')}.webp',
          quantity: 5894,
        ),
      ],
      'warnings': <Object?>[],
    };

    final matches = const InventoryScreenshotResultSanitizer()
        .sanitize(rawResult: result, screenshotBytes: bytes, catalog: catalog)
        .rows
        .single
        .matches;

    expect(matches, hasLength(15));
    expect(matches.first.name, 'Dried Test Fish 15');
    expect(matches.last.name, 'Dried Test Fish 1');
    expect(
      matches.every((match) => match.orderGroupKey == 'dried-fish'),
      isTrue,
      reason:
          'Recorded BDO group 6 membership, rather than an item-name guess, '
          'must carry the cross-artwork inventory order group.',
    );
  });

  test(
    'a special cooking result is accepted when OCR marks it as material',
    () {
      final bytes = _png();
      final catalog = InventoryOcrMaterialCatalog.fromRecipeBookJson(
        catalog: _catalog(),
        recipeBookJson: _recipeBookJson(),
      );
      final result = <String, Object?>{
        'imageFingerprint': _digest('4'),
        'width': 64,
        'height': 64,
        'grid': <String, Object?>{'columns': 1, 'rows': 1, 'confidence': .99},
        'slots': <Object?>[
          _slot(
            id: 'r0c0',
            column: 0,
            icon: 'icons/items/${_digest('9')}.webp',
            quantity: 596,
            borderGrade: 2,
            materialEligible: true,
          ),
        ],
        'warnings': <Object?>[],
      };

      final draft = const InventoryScreenshotResultSanitizer().sanitize(
        rawResult: result,
        screenshotBytes: bytes,
        catalog: catalog,
      );

      expect(draft.hiddenRows, isEmpty);
      expect(draft.rows.single.selectedName, 'Steaming Hot Grilled Bird Meat');
      expect(
        draft.rows.single.relevance,
        InventoryOcrMaterialRelevance.relevant,
      );
    },
  );

  test('a decisive non-material result is omitted from inventory review', () {
    final bytes = _png();
    final catalog = InventoryOcrMaterialCatalog.fromRecipeBookJson(
      catalog: _catalog(),
      recipeBookJson: _recipeBookJson(),
    );
    final result = <String, Object?>{
      'imageFingerprint': _digest('6'),
      'width': 64,
      'height': 64,
      'grid': <String, Object?>{'columns': 1, 'rows': 1, 'confidence': .99},
      'slots': <Object?>[
        _slot(
          id: 'r0c0',
          column: 0,
          icon: 'icons/items/${_digest('9')}.webp',
          quantity: 4,
          borderGrade: 2,
          materialEligible: false,
          candidateMaterialEligible: true,
        ),
      ],
      'warnings': <Object?>[],
    };

    final draft = const InventoryScreenshotResultSanitizer().sanitize(
      rawResult: result,
      screenshotBytes: bytes,
      catalog: catalog,
    );

    expect(draft.rows, isEmpty);
    expect(draft.hiddenRows, isEmpty);
  });

  test(
    'a later material-looking candidate cannot override a non-material top icon',
    () {
      final bytes = _png();
      final catalog = InventoryOcrMaterialCatalog.fromRecipeBookJson(
        catalog: _catalog(),
        recipeBookJson: _recipeBookJson(),
      );
      final slot = _slot(
        id: 'r0c0',
        column: 0,
        icon: 'icons/items/${_digest('d')}.webp',
        quantity: 4,
        borderGrade: 4,
        materialEligible: false,
        candidateMaterialEligible: false,
      );
      slot['iconCandidates'] = <Object?>[
        <String, Object?>{
          'icon': 'icons/items/${_digest('d')}.webp',
          'score': .97,
          'materialEligible': false,
        },
        <String, Object?>{
          'icon': 'icons/items/${_digest('e')}.webp',
          'score': .91,
          'materialEligible': false,
        },
      ];
      final draft = const InventoryScreenshotResultSanitizer().sanitize(
        rawResult: <String, Object?>{
          'imageFingerprint': _digest('d'),
          'width': 64,
          'height': 64,
          'grid': <String, Object?>{'columns': 1, 'rows': 1, 'confidence': .99},
          'slots': <Object?>[slot],
          'warnings': <Object?>[],
        },
        screenshotBytes: bytes,
        catalog: catalog,
      );

      expect(draft.rows, isEmpty);
      expect(draft.hiddenRows, isEmpty);
    },
  );

  test(
    'reviewed Simple Cooking output overrides its conservative icon flag',
    () {
      final bytes = _png();
      final catalog = InventoryOcrMaterialCatalog.fromRecipeBookJson(
        catalog: _catalog(),
        recipeBookJson: _recipeBookJson(),
      );
      final result = <String, Object?>{
        'imageFingerprint': _digest('e'),
        'width': 64,
        'height': 64,
        'grid': <String, Object?>{'columns': 1, 'rows': 1, 'confidence': .99},
        'slots': <Object?>[
          _slot(
            id: 'r0c0',
            column: 0,
            icon: 'icons/items/${_digest('e')}.webp',
            quantity: 12,
            borderGrade: 4,
            materialEligible: false,
            candidateMaterialEligible: false,
          ),
        ],
        'warnings': <Object?>[],
      };

      final draft = const InventoryScreenshotResultSanitizer().sanitize(
        rawResult: result,
        screenshotBytes: bytes,
        catalog: catalog,
      );

      expect(draft.rows.single.selectedName, 'Simple Cron Meal');
    },
  );

  test(
    'shared artwork is prefilled for amber review and unmatched slots stay empty',
    () {
      final bytes = _png();
      final catalog = InventoryOcrMaterialCatalog.fromRecipeBookJson(
        catalog: _catalog(),
        recipeBookJson: _recipeBookJson(),
      );
      final result = <String, Object?>{
        'imageFingerprint': _digest('a'),
        'width': 64,
        'height': 64,
        'grid': <String, Object?>{'columns': 2, 'rows': 1, 'confidence': .98},
        'slots': <Object?>[
          _slot(
            id: 'r0c0',
            column: 0,
            icon: 'icons/items/${_digest('b')}.webp',
            quantity: 12718,
          ),
          _slot(
            id: 'r0c1',
            column: 1,
            icon: 'icons/items/${_digest('a')}.webp',
            quantity: 42,
          ),
        ],
        'warnings': <Object?>[],
      };

      final draft = const InventoryScreenshotResultSanitizer().sanitize(
        rawResult: result,
        screenshotBytes: bytes,
        catalog: catalog,
      );

      expect(draft.rows, hasLength(2));
      expect(draft.hiddenRows, isEmpty);
      final shared = draft.rows.first;
      final unmatched = draft.rows.last;
      expect(shared.quantity, 12718);
      expect(shared.selectedName, 'Flamingo Blood');
      expect(shared.itemSuggestionUncertain, isTrue);
      expect(shared.matches.map((match) => match.name).toSet(), <String>{
        'Wolf Blood',
        'Flamingo Blood',
      });
      expect(shared.reviewRequired, isTrue);
      expect(unmatched.matches, isEmpty);
      expect(unmatched.selectedName, isNull);
      expect(unmatched.relevance, InventoryOcrMaterialRelevance.uncertain);
    },
  );

  test('a strong unique planner match is selected automatically', () {
    final bytes = _png();
    final catalog = InventoryOcrMaterialCatalog.fromRecipeBookJson(
      catalog: _catalog(),
      recipeBookJson: _recipeBookJson(),
    );
    final result = <String, Object?>{
      'imageFingerprint': _digest('e'),
      'width': 64,
      'height': 64,
      'grid': <String, Object?>{'columns': 1, 'rows': 1, 'confidence': .99},
      'slots': <Object?>[
        _slot(
          id: 'r0c0',
          column: 0,
          icon: 'icons/items/${_digest('c')}.webp',
          quantity: 25060,
        ),
      ],
      'warnings': <Object?>[],
    };

    final row = const InventoryScreenshotResultSanitizer()
        .sanitize(rawResult: result, screenshotBytes: bytes, catalog: catalog)
        .rows
        .single;

    expect(row.selectedName, 'Clear Liquid Reagent');
    expect(row.quantity, 25060);
  });

  test('a trusted quality border selects exact Special Sunflower', () {
    final bytes = _png();
    final catalog = InventoryOcrMaterialCatalog.fromRecipeBookJson(
      catalog: _catalog(),
      recipeBookJson: _recipeBookJson(),
    );
    final result = <String, Object?>{
      'imageFingerprint': _digest('7'),
      'width': 64,
      'height': 64,
      'grid': <String, Object?>{'columns': 1, 'rows': 1, 'confidence': .99},
      'slots': <Object?>[
        _slot(
          id: 'r0c0',
          column: 0,
          icon: 'icons/items/${_digest('7')}.webp',
          quantity: 1060,
          borderGrade: 2,
        ),
      ],
      'warnings': <Object?>[],
    };

    final row = const InventoryScreenshotResultSanitizer()
        .sanitize(rawResult: result, screenshotBytes: bytes, catalog: catalog)
        .rows
        .single;

    expect(row.selectedName, 'Special Sunflower');
    expect(row.matches.map((match) => match.name), <String>[
      'Special Sunflower',
      'Sunflower',
    ]);
    expect(row.matches.first.qualityConflict, isFalse);
    expect(row.matches.last.qualityConflict, isTrue);
    expect(row.reviewReasons, isEmpty);
  });

  test('a strong unique Milk match is selected automatically', () {
    final bytes = _png();
    final catalog = InventoryOcrMaterialCatalog.fromRecipeBookJson(
      catalog: _catalog(),
      recipeBookJson: _recipeBookJson(),
    );
    final result = <String, Object?>{
      'imageFingerprint': _digest('8'),
      'width': 64,
      'height': 64,
      'grid': <String, Object?>{'columns': 1, 'rows': 1, 'confidence': .99},
      'slots': <Object?>[
        _slot(
          id: 'r0c0',
          column: 0,
          icon: 'icons/items/${_digest('8')}.webp',
          quantity: 174500,
        ),
      ],
      'warnings': <Object?>[],
    };

    final row = const InventoryScreenshotResultSanitizer()
        .sanitize(rawResult: result, screenshotBytes: bytes, catalog: catalog)
        .rows
        .single;

    expect(row.selectedName, 'Milk');
    expect(row.quantity, 174500);
    expect(row.reviewReasons, isEmpty);
  });

  test('a complete visible short amount remains available for review', () {
    final bytes = _png();
    final catalog = InventoryOcrMaterialCatalog.fromRecipeBookJson(
      catalog: _catalog(),
      recipeBookJson: _recipeBookJson(),
    );
    final slot =
        _slot(
            id: 'r0c0',
            column: 0,
            icon: 'icons/items/${_digest('7')}.webp',
            quantity: 1060,
            borderGrade: 2,
          )
          ..['quantityValue'] = null
          ..['quantitySuggestedValue'] = null
          ..['quantityConfidence'] = .62;
    final result = <String, Object?>{
      'imageFingerprint': _digest('6'),
      'width': 64,
      'height': 64,
      'grid': <String, Object?>{'columns': 1, 'rows': 1, 'confidence': .99},
      'slots': <Object?>[slot],
      'warnings': <Object?>[],
    };

    final row = const InventoryScreenshotResultSanitizer()
        .sanitize(rawResult: result, screenshotBytes: bytes, catalog: catalog)
        .rows
        .single;

    expect(row.quantityText, '1060');
    expect(row.quantity, 1060);
    expect(row.quantitySuggested, 1060);
    expect(row.quantitySuggestionUncertain, isTrue);
    expect(row.reviewRequired, isTrue);
    expect(row.reviewReasons, contains('Check the highlighted amount.'));
  });

  test('a native grammar suggestion stays available and highlighted', () {
    final bytes = _png();
    final catalog = InventoryOcrMaterialCatalog.fromRecipeBookJson(
      catalog: _catalog(),
      recipeBookJson: _recipeBookJson(),
    );
    final slot =
        _slot(
            id: 'r0c0',
            column: 0,
            icon: 'icons/items/${_digest('7')}.webp',
            quantity: 1060,
            borderGrade: 2,
          )
          ..['quantityText'] = '1060'
          ..['quantityValue'] = null
          ..['quantitySuggestedValue'] = 1060
          ..['quantityConfidence'] = .93
          ..['quantityReadStatus'] = 'reviewLowConsensus'
          ..['quantitySuggestionEvidence'] = 'mainNumericGrammar'
          ..['quantitySuggestionConfidence'] = .93;
    final result = <String, Object?>{
      'imageFingerprint': _digest('9'),
      'width': 64,
      'height': 64,
      'grid': <String, Object?>{'columns': 1, 'rows': 1, 'confidence': .99},
      'slots': <Object?>[slot],
      'warnings': <Object?>[],
    };

    final row = const InventoryScreenshotResultSanitizer()
        .sanitize(rawResult: result, screenshotBytes: bytes, catalog: catalog)
        .rows
        .single;

    expect(row.quantityText, '1060');
    expect(row.quantity, 1060);
    expect(row.quantitySuggested, 1060);
    expect(row.quantitySuggestionUncertain, isTrue);
    expect(row.reviewRequired, isTrue);
  });

  test('an agreeing direct abbreviated suggestion stays neutral', () {
    final bytes = _png();
    final catalog = InventoryOcrMaterialCatalog.fromRecipeBookJson(
      catalog: _catalog(),
      recipeBookJson: _recipeBookJson(),
    );
    final slot =
        _slot(
            id: 'r0c0',
            column: 0,
            icon: 'icons/items/${_digest('7')}.webp',
            quantity: 139900,
            borderGrade: 2,
          )
          ..['quantityText'] = '139.9K'
          ..['quantityValue'] = null
          ..['quantitySuggestedValue'] = 139900
          ..['quantityApproximate'] = true
          ..['quantityConfidence'] = .62
          ..['quantityReadStatus'] = 'reviewLowConsensus'
          ..['quantitySuggestionEvidence'] = 'mainDirectAgreement'
          ..['quantitySuggestionConfidence'] = .91;
    final result = <String, Object?>{
      'imageFingerprint': _digest('d'),
      'width': 64,
      'height': 64,
      'grid': <String, Object?>{'columns': 1, 'rows': 1, 'confidence': .99},
      'slots': <Object?>[slot],
      'warnings': <Object?>[],
    };

    final row = const InventoryScreenshotResultSanitizer()
        .sanitize(rawResult: result, screenshotBytes: bytes, catalog: catalog)
        .rows
        .single;

    expect(row.quantity, 139900);
    expect(row.quantitySuggested, 139900);
    expect(row.quantityApproximate, isTrue);
    expect(row.quantitySuggestionUncertain, isFalse);
    expect(row.reviewRequired, isFalse);
  });

  test(
    'a native confirmed amount stays neutral below the old UI threshold',
    () {
      final bytes = _png();
      final catalog = InventoryOcrMaterialCatalog.fromRecipeBookJson(
        catalog: _catalog(),
        recipeBookJson: _recipeBookJson(),
      );
      final slot =
          _slot(
              id: 'r0c0',
              column: 0,
              icon: 'icons/items/${_digest('7')}.webp',
              quantity: 1060,
              borderGrade: 2,
            )
            ..['quantityConfidence'] = .62
            ..['quantityReadStatus'] = 'confirmed';
      final result = <String, Object?>{
        'imageFingerprint': _digest('e'),
        'width': 64,
        'height': 64,
        'grid': <String, Object?>{'columns': 1, 'rows': 1, 'confidence': .99},
        'slots': <Object?>[slot],
        'warnings': <Object?>[],
      };

      final row = const InventoryScreenshotResultSanitizer()
          .sanitize(rawResult: result, screenshotBytes: bytes, catalog: catalog)
          .rows
          .single;

      expect(row.quantity, 1060);
      expect(row.quantitySuggestionUncertain, isFalse);
      expect(row.reviewRequired, isFalse);
    },
  );

  test('a low-confidence leading-zero token remains unresolved', () {
    final bytes = _png();
    final catalog = InventoryOcrMaterialCatalog.fromRecipeBookJson(
      catalog: _catalog(),
      recipeBookJson: _recipeBookJson(),
    );
    final slot =
        _slot(
            id: 'r0c0',
            column: 0,
            icon: 'icons/items/${_digest('7')}.webp',
            quantity: 1060,
            borderGrade: 2,
          )
          ..['quantityText'] = '060'
          ..['quantityValue'] = null
          ..['quantitySuggestedValue'] = 60
          ..['quantityConfidence'] = .5;
    final result = <String, Object?>{
      'imageFingerprint': _digest('a'),
      'width': 64,
      'height': 64,
      'grid': <String, Object?>{'columns': 1, 'rows': 1, 'confidence': .99},
      'slots': <Object?>[slot],
      'warnings': <Object?>[],
    };

    final row = const InventoryScreenshotResultSanitizer()
        .sanitize(rawResult: result, screenshotBytes: bytes, catalog: catalog)
        .rows
        .single;

    expect(row.quantity, isNull);
    expect(row.quantitySuggested, isNull);
  });

  test('a trusted abbreviated amount remains available for review', () {
    final bytes = _png();
    final catalog = InventoryOcrMaterialCatalog.fromRecipeBookJson(
      catalog: _catalog(),
      recipeBookJson: _recipeBookJson(),
    );
    final slot =
        _slot(
            id: 'r0c0',
            column: 0,
            icon: 'icons/items/${_digest('7')}.webp',
            quantity: 177000,
            borderGrade: 2,
          )
          ..['quantityText'] = '177.0K'
          ..['quantityValue'] = null
          ..['quantitySuggestedValue'] = null
          ..['quantityApproximate'] = true
          ..['quantityConfidence'] = .94;
    final result = <String, Object?>{
      'imageFingerprint': _digest('7'),
      'width': 64,
      'height': 64,
      'grid': <String, Object?>{'columns': 1, 'rows': 1, 'confidence': .99},
      'slots': <Object?>[slot],
      'warnings': <Object?>[],
    };

    final row = const InventoryScreenshotResultSanitizer()
        .sanitize(rawResult: result, screenshotBytes: bytes, catalog: catalog)
        .rows
        .single;

    expect(row.quantityText, '177.0K');
    expect(row.quantity, 177000);
    expect(row.quantitySuggested, 177000);
    expect(row.quantityApproximate, isTrue);
    expect(row.quantitySuggestionUncertain, isTrue);
    expect(row.reviewRequired, isTrue);
  });

  test('a native abbreviated grammar suggestion is accepted for review', () {
    final bytes = _png();
    final catalog = InventoryOcrMaterialCatalog.fromRecipeBookJson(
      catalog: _catalog(),
      recipeBookJson: _recipeBookJson(),
    );
    final slot =
        _slot(
            id: 'r0c0',
            column: 0,
            icon: 'icons/items/${_digest('7')}.webp',
            quantity: 177100,
            borderGrade: 2,
          )
          ..['quantityText'] = '177.1K'
          ..['quantityValue'] = null
          ..['quantitySuggestedValue'] = 177100
          ..['quantityApproximate'] = true
          ..['quantityConfidence'] = .93
          ..['quantityReadStatus'] = 'reviewLowConsensus'
          ..['quantitySuggestionEvidence'] = 'mainNumericGrammar'
          ..['quantitySuggestionConfidence'] = .93;
    final result = <String, Object?>{
      'imageFingerprint': _digest('b'),
      'width': 64,
      'height': 64,
      'grid': <String, Object?>{'columns': 1, 'rows': 1, 'confidence': .99},
      'slots': <Object?>[slot],
      'warnings': <Object?>[],
    };

    final row = const InventoryScreenshotResultSanitizer()
        .sanitize(rawResult: result, screenshotBytes: bytes, catalog: catalog)
        .rows
        .single;

    expect(row.quantityText, '177.1K');
    expect(row.quantity, 177100);
    expect(row.quantitySuggested, 177100);
    expect(row.quantityApproximate, isTrue);
    expect(row.quantitySuggestionUncertain, isTrue);
    expect(row.reviewRequired, isTrue);
    expect(row.reviewReasons, contains('Check the highlighted amount.'));
  });

  test('a low-confidence A-shaped separator remains unresolved', () {
    final bytes = _png();
    final catalog = InventoryOcrMaterialCatalog.fromRecipeBookJson(
      catalog: _catalog(),
      recipeBookJson: _recipeBookJson(),
    );
    final slot =
        _slot(
            id: 'r0c0',
            column: 0,
            icon: 'icons/items/${_digest('7')}.webp',
            quantity: 177100,
            borderGrade: 2,
          )
          ..['quantityText'] = '177A1K'
          ..['quantityValue'] = null
          ..['quantitySuggestedValue'] = null
          ..['quantityApproximate'] = true
          ..['quantityConfidence'] = .5;
    final result = <String, Object?>{
      'imageFingerprint': _digest('c'),
      'width': 64,
      'height': 64,
      'grid': <String, Object?>{'columns': 1, 'rows': 1, 'confidence': .99},
      'slots': <Object?>[slot],
      'warnings': <Object?>[],
    };

    final row = const InventoryScreenshotResultSanitizer()
        .sanitize(rawResult: result, screenshotBytes: bytes, catalog: catalog)
        .rows
        .single;

    expect(row.quantity, isNull);
    expect(row.quantitySuggested, isNull);
  });

  test('a quality-border conflict is prefilled but remains uncertain', () {
    final bytes = _png();
    final catalog = InventoryOcrMaterialCatalog.fromRecipeBookJson(
      catalog: _catalog(),
      recipeBookJson: _recipeBookJson(),
    );
    final result = <String, Object?>{
      'imageFingerprint': _digest('f'),
      'width': 64,
      'height': 64,
      'grid': <String, Object?>{'columns': 1, 'rows': 1, 'confidence': .99},
      'slots': <Object?>[
        _slot(
          id: 'r0c0',
          column: 0,
          icon: 'icons/items/${_digest('c')}.webp',
          quantity: 25060,
          borderGrade: 2,
        ),
      ],
      'warnings': <Object?>[],
    };

    final row = const InventoryScreenshotResultSanitizer()
        .sanitize(rawResult: result, screenshotBytes: bytes, catalog: catalog)
        .rows
        .single;

    expect(row.selectedName, 'Clear Liquid Reagent');
    expect(row.itemSuggestionUncertain, isTrue);
    expect(row.matches.single.qualityConflict, isTrue);
    expect(row.reviewReasons, contains(contains('quality border')));
  });
}

Map<String, Object?> _slot({
  required String id,
  required int column,
  required String icon,
  required int quantity,
  int borderGrade = 0,
  bool materialEligible = true,
  bool? candidateMaterialEligible,
}) => <String, Object?>{
  'id': id,
  'row': 0,
  'column': column,
  'box': <String, Object?>{'x': column * 32, 'y': 0, 'width': 32, 'height': 32},
  'iconCandidates': <Object?>[
    <String, Object?>{
      'icon': icon,
      'score': .96,
      'materialEligible': candidateMaterialEligible ?? materialEligible,
    },
  ],
  'iconMaterialEligible': materialEligible,
  'iconMaterialConfidence': .96,
  'iconMaterialMargin': .3,
  'borderGrade': borderGrade,
  'borderGradeConfidence': .92,
  'quantityText': quantity.toString(),
  'quantityValue': quantity,
  'quantitySuggestedValue': null,
  'quantityApproximate': false,
  'quantityConfidence': .98,
  'quantityAssumedOne': false,
};

Uint8List _png() {
  final source = image.Image(width: 64, height: 64, numChannels: 4);
  image.fill(source, color: image.ColorRgba8(20, 21, 24, 255));
  return Uint8List.fromList(image.encodePng(source));
}

({CatalogSnapshot catalog, String recipeBookJson, Uint8List screenshotBytes})
_structuredBloodAppCompetitionFixture({required bool structured}) {
  final herbalTemplate = image.Image(width: 40, height: 40, numChannels: 4);
  image.fill(herbalTemplate, color: image.ColorRgba8(22, 23, 27, 255));
  for (var y = 8; y < 28; y += 1) {
    for (var x = 10; x < 30; x += 1) {
      herbalTemplate.setPixelRgba(x, y, 198, 63, 84, 255);
    }
  }
  final sourceIcon = image.Image.from(herbalTemplate);
  for (var y = 8; y < 28; y += 1) {
    for (var x = 25; x < 30; x += 1) {
      sourceIcon.setPixelRgba(x, y, 22, 23, 27, 255);
    }
  }
  final screenshot = image.Image(width: 48, height: 48, numChannels: 4);
  image.fill(screenshot, color: image.ColorRgba8(22, 23, 27, 255));
  image.compositeImage(
    screenshot,
    image.copyResize(
      sourceIcon,
      width: 44,
      height: 44,
      interpolation: image.Interpolation.cubic,
    ),
    dstX: 2,
    dstY: 2,
  );
  final herbalDataUri =
      'data:image/png;base64,${base64Encode(image.encodePng(herbalTemplate))}';

  final recipe = Recipe(
    name: 'Structured Blood Test Elixir',
    type: 'alchemy',
    baseOutput: 1,
    group: 'Elixirs',
    method: null,
    ingredients: <Ingredient>[
      Ingredient(
        name: 'Goat Blood',
        quantity: 1,
        options: const <String>['Goat Blood', 'Llama Blood', 'Ox Blood'],
        substituteGroup: structured ? 'Blood Group 2' : null,
        substituteRatios: const <String, double>{},
      ),
      Ingredient(
        name: 'Herbal Juice',
        quantity: 1,
        options: const <String>[],
        substituteGroup: null,
        substituteRatios: const <String, double>{},
      ),
    ],
    marketId: null,
    sourceNote: null,
    vendor: null,
    location: null,
    npcPrice: 0,
    qualityBase: null,
    qualityGrade: null,
    outputMinimum: 1,
    outputMaximum: 1,
  );
  ModeCatalog mode(CraftMode mode) => ModeCatalog(
    mode: mode,
    items: <String, Recipe>{recipe.name: recipe},
    iconDataUris: <String, String>{'Herbal Juice': herbalDataUri},
    defaults: const <String, Object?>{},
    metadata: const <String, Object?>{},
    searchAliases: const <String, String>{},
  );
  final catalog = CatalogSnapshot(
    sourceSha256: 'structured-blood-app-competition',
    sourceByteCount: 1,
    alchemy: mode(CraftMode.alchemy),
    cooking: mode(CraftMode.cooking),
    processing: mode(CraftMode.processing),
    supportingData: const <String, Object?>{},
    collisions: const <CaseCollision>[],
  );
  final recipeBookJson = jsonEncode(<String, Object?>{
    'items': <String, Object?>{
      '6228': <String, Object?>{
        'name': 'Goat Blood',
        'grade': 0,
        'icon': _structuredBloodIcon,
      },
      '6227': <String, Object?>{
        'name': 'Llama Blood',
        'grade': 0,
        'icon': _structuredBloodIcon,
      },
      '6206': <String, Object?>{
        'name': 'Ox Blood',
        'grade': 0,
        'icon': _structuredBloodIcon,
      },
      '569': <String, Object?>{
        'name': 'Herbal Juice',
        'grade': 0,
        'icon': _structuredHerbalIcon,
      },
    },
  });
  return (
    catalog: catalog,
    recipeBookJson: recipeBookJson,
    screenshotBytes: Uint8List.fromList(image.encodePng(screenshot)),
  );
}

final String _structuredBloodIcon = 'icons/items/${_digest('a')}.webp';
final String _structuredHerbalIcon = 'icons/items/${_digest('b')}.webp';

Uint8List _appIconScreenshot(CatalogSnapshot catalog, String name) {
  String? dataUri;
  for (final mode in CraftMode.values) {
    dataUri ??= catalog.forMode(mode).iconDataUris[name];
  }
  if (dataUri == null) throw StateError('No app artwork for $name.');
  final separator = dataUri.indexOf(',');
  final decoded = image.decodeImage(
    base64Decode(dataUri.substring(separator + 1)),
  );
  if (decoded == null) throw StateError('Invalid app artwork for $name.');
  final screenshot = image.Image(width: 48, height: 48, numChannels: 4);
  image.fill(screenshot, color: image.ColorRgba8(22, 23, 27, 255));
  image.compositeImage(
    screenshot,
    image.copyResize(
      decoded,
      width: 44,
      height: 44,
      interpolation: image.Interpolation.cubic,
    ),
    dstX: 2,
    dstY: 2,
  );
  return Uint8List.fromList(image.encodePng(screenshot));
}

const String _bigEmperorUserCropBase64 =
    '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';

const String _elderSapUserCropBase64 =
    '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';

const String _acaciaSapUserCropBase64 =
    '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';

const String _thujaSapUserCropBase64 =
    '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';

String _digest(String character) => List<String>.filled(64, character).join();

String _foldTest(String value) => value.trim().toLowerCase();

String _normalizedIconForTest(String value) => value
    .trim()
    .replaceAll('\\', '/')
    .replaceFirst(RegExp(r'^\./'), '')
    .toLowerCase();

String _recipeBookJson() => jsonEncode(<String, Object?>{
  'items': <String, Object?>{
    '1': <String, Object?>{
      'name': 'Wolf Blood',
      'grade': 0,
      'icon': 'icons/items/${_digest('b')}.webp',
    },
    '2': <String, Object?>{
      'name': 'Flamingo Blood',
      'grade': 0,
      'icon': 'icons/items/${_digest('b')}.webp',
    },
    '3': <String, Object?>{
      'name': 'Clear Liquid Reagent',
      'grade': 0,
      'icon': 'icons/items/${_digest('c')}.webp',
    },
    '4': <String, Object?>{
      'name': 'Krea Noble Sword',
      'grade': 0,
      'icon': 'icons/items/${_digest('d')}.webp',
    },
    '5': <String, Object?>{
      'name': 'Sunflower',
      'grade': 0,
      'icon': 'icons/items/${_digest('7')}.webp',
    },
    '6': <String, Object?>{
      'name': 'Special Sunflower',
      'grade': 2,
      'icon': 'icons/items/${_digest('7')}.webp',
    },
    '7': <String, Object?>{
      'name': 'Milk',
      'grade': 0,
      'icon': 'icons/items/${_digest('8')}.webp',
    },
    '7953': <String, Object?>{
      'name': 'Bird Meat',
      'grade': 0,
      'icon': 'icons/items/${_digest('6')}.webp',
    },
    '7921': <String, Object?>{
      'name': 'Chicken Meat',
      'grade': 0,
      'icon': 'icons/items/${_digest('6')}.webp',
    },
    '7917': <String, Object?>{
      'name': 'Flamingo Meat',
      'grade': 0,
      'icon': 'icons/items/${_digest('6')}.webp',
    },
    '7916': <String, Object?>{
      'name': 'Kuku Bird Meat',
      'grade': 0,
      'icon': 'icons/items/${_digest('6')}.webp',
    },
    '9493': <String, Object?>{
      'name': 'Steaming Hot Grilled Bird Meat',
      'grade': 2,
      'icon': 'icons/items/${_digest('9')}.webp',
    },
    '9692': <String, Object?>{
      'name': 'Simple Cron Meal',
      'grade': 4,
      'icon': 'icons/items/${_digest('e')}.webp',
    },
    '9001': <String, Object?>{
      'name': 'Salt',
      'grade': 0,
      'icon': 'icons/items/${_digest('0')}.webp',
    },
    '9008': <String, Object?>{
      'name': 'Sun-Dried Salt',
      'grade': 0,
      'icon': 'icons/items/${_digest('0')}.webp',
    },
    for (var index = 1; index <= 15; index += 1)
      '${9100 + index}': <String, Object?>{
        'name': 'Dried Test Fish $index',
        'grade': 0,
        'icon': 'icons/items/${_digest('5')}.webp',
      },
  },
});

CatalogSnapshot _catalog() {
  final output = Recipe(
    name: 'Test Elixir',
    type: 'alchemy',
    baseOutput: 1,
    group: 'Elixirs',
    method: null,
    ingredients: <Ingredient>[
      Ingredient(
        name: 'Wolf Blood',
        quantity: 1,
        options: const <String>['Wolf Blood', 'Flamingo Blood'],
        substituteGroup: 'Blood Group 1',
        substituteRatios: const <String, double>{},
      ),
      Ingredient(
        name: 'Clear Liquid Reagent',
        quantity: 1,
        options: const <String>[],
        substituteGroup: null,
        substituteRatios: const <String, double>{},
      ),
      Ingredient(
        name: 'Banana',
        quantity: 1,
        options: const <String>[],
        substituteGroup: null,
        substituteRatios: const <String, double>{},
      ),
      Ingredient(
        name: 'Sunflower',
        quantity: 1,
        options: const <String>[],
        substituteGroup: null,
        substituteRatios: const <String, double>{},
      ),
      Ingredient(
        name: 'Milk',
        quantity: 1,
        options: const <String>[],
        substituteGroup: null,
        substituteRatios: const <String, double>{},
      ),
      Ingredient(
        name: 'Salt',
        quantity: 1,
        options: const <String>['Salt', 'Sun-Dried Salt'],
        substituteGroup: 'Salt',
        substituteRatios: const <String, double>{},
      ),
      Ingredient(
        name: 'Chicken Meat',
        quantity: 1,
        options: const <String>[
          'Bird Meat',
          'Chicken Meat',
          'Flamingo Meat',
          'Kuku Bird Meat',
        ],
        substituteGroup: 'Bird Meat',
        substituteRatios: const <String, double>{},
      ),
      Ingredient(
        name: 'Dried Test Fish 1',
        quantity: 1,
        options: List<String>.generate(
          15,
          (index) => 'Dried Test Fish ${index + 1}',
        ),
        substituteGroup: 'BDO group 6',
        substituteRatios: const <String, double>{},
      ),
    ],
    marketId: null,
    sourceNote: null,
    vendor: null,
    location: null,
    npcPrice: 0,
    qualityBase: null,
    qualityGrade: null,
    outputMinimum: null,
    outputMaximum: null,
  );
  final specialCookingResult = Recipe(
    name: 'Steaming Hot Grilled Bird Meat',
    type: 'gathered',
    baseOutput: 1,
    group: 'Cooking',
    method: null,
    ingredients: const <Ingredient>[],
    marketId: '9493',
    sourceNote: null,
    vendor: null,
    location: null,
    npcPrice: 0,
    qualityBase: 'Grilled Bird Meat',
    qualityGrade: 'blue',
    outputMinimum: null,
    outputMaximum: null,
  );
  final simpleCronMeal = Recipe(
    name: 'Simple Cron Meal',
    type: 'processing',
    baseOutput: 1,
    group: 'Processing - Simple Cooking',
    method: 'Simple Cooking',
    ingredients: const <Ingredient>[],
    marketId: '9692',
    sourceNote: null,
    vendor: null,
    location: null,
    npcPrice: 0,
    qualityBase: null,
    qualityGrade: null,
    outputMinimum: 1,
    outputMaximum: 1,
  );
  final hpPotionLarge = Recipe(
    name: 'HP Potion (Large)',
    type: 'processing',
    baseOutput: 1,
    group: 'Processing - Simple Alchemy',
    method: 'Simple Alchemy',
    ingredients: <Ingredient>[
      Ingredient(
        name: 'HP Potion (Medium)',
        quantity: 3,
        options: const <String>[],
        substituteGroup: null,
        substituteRatios: const <String, double>{},
      ),
    ],
    marketId: '519',
    sourceNote: null,
    vendor: null,
    location: null,
    npcPrice: 0,
    qualityBase: null,
    qualityGrade: null,
    outputMinimum: 1,
    outputMaximum: 1,
  );
  ModeCatalog mode(CraftMode mode) => ModeCatalog(
    mode: mode,
    items: <String, Recipe>{
      output.name: output,
      if (mode == CraftMode.cooking)
        specialCookingResult.name: specialCookingResult,
      if (mode == CraftMode.processing) simpleCronMeal.name: simpleCronMeal,
      if (mode == CraftMode.processing) hpPotionLarge.name: hpPotionLarge,
    },
    iconDataUris: const <String, String>{},
    defaults: const <String, Object?>{},
    metadata: const <String, Object?>{},
    searchAliases: const <String, String>{},
  );
  return CatalogSnapshot(
    sourceSha256: 'ocr-test-catalog',
    sourceByteCount: 1,
    alchemy: mode(CraftMode.alchemy),
    cooking: mode(CraftMode.cooking),
    processing: mode(CraftMode.processing),
    supportingData: const <String, Object?>{
      'qualityIngredients': <String>['Sunflower'],
      'qualityConversions': <String, Object?>{
        'Sunflower': <String, Object?>{
          'high': <String, Object?>{
            'name': 'High-Quality Sunflower',
            'ratio': 4,
          },
          'special': <String, Object?>{'name': 'Special Sunflower', 'ratio': 7},
        },
      },
    },
    collisions: const <CaseCollision>[],
  );
}
