import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:bdo_craft_planner_flutter/data/catalog/bundled_catalog_parser.dart';
import 'package:bdo_craft_planner_flutter/data/catalog/catalog_repository.dart';
import 'package:bdo_craft_planner_flutter/domain/models/craft_mode.dart';
import 'package:bdo_craft_planner_flutter/features/shared/mode_item_icon.dart';
import 'package:bdo_craft_planner_flutter/visual/visual.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../planner/planner_test_fixture.dart';

void main() {
  late CatalogRepository catalog;
  setUpAll(() async {
    catalog = CatalogRepository(
      const BundledCatalogParser().parse(
        File('assets/data/app-data.json').readAsStringSync(),
      ),
    );
    if (const bool.fromEnvironment('CAPTURE_ITEM_ICONS') &&
        Platform.isWindows) {
      final font = FontLoader('Segoe UI');
      final windows = Platform.environment['WINDIR'] ?? r'C:\Windows';
      for (final file in ['segoeui.ttf', 'seguisb.ttf', 'segoeuib.ttf']) {
        font.addFont(
          File('$windows/Fonts/$file').readAsBytes().then(ByteData.sublistView),
        );
      }
      await font.load();
    }
  });

  test('every bundled icon retains verified original bytes and grade', () {
    final provenance =
        jsonDecode(File('docs/item-artwork-provenance.json').readAsStringSync())
            as Map;
    final entries = provenance['entries'] as List;
    expect(entries, hasLength(4517));
    for (final row in entries.cast<Map>()) {
      final mode = CraftMode.values.singleWhere(
        (mode) => mode.key == row['mode'],
      );
      final name = row['name'] as String;
      final uri = catalog.iconDataUri(mode, name, preferCleanArtwork: true)!;
      final bytes = UriData.parse(uri).contentAsBytes();
      expect(
        sha256.convert(bytes).toString(),
        row['sha256'],
        reason: '$mode: $name',
      );
      expect(catalog.itemIconGrade(name), row['grade'], reason: name);
      final reference = catalog.snapshot.forMode(mode).iconDataUris[name]!;
      expect(
        sha256.convert(UriData.parse(reference).contentAsBytes()).toString(),
        row['referenceSha256'],
        reason: 'Screenshot recognition: $name',
      );
    }
    expect(catalog.itemIconGrade('Citron'), 0);
    expect(catalog.itemIconGrade('High-quality Citron'), 1);
    expect(catalog.itemIconGrade('Special Citron'), 2);
    expect(catalog.itemIconGrade("Labreska's Helmet (Bound)"), 4);
    expect(catalog.itemIconGrade('Not a real item'), isNull);
    expect(
      catalog.itemIconGrade('My ingredient', aliases: ['Special Citron']),
      2,
    );
    expect(catalog.itemIconGrade('Citron', aliases: ['Special Citron']), 0);
    expect(catalog.itemIconGradeById(9064), 0);
    expect(catalog.isEmptyIconArtwork('[Event] Drieghan Fragments'), isTrue);
    expect(catalog.isEmptyIconArtwork('Egg'), isFalse);
  });

  testWidgets('clean art has transparent corners, not a baked square frame', (
    tester,
  ) async {
    for (final name in [
      'Egg',
      'Milk',
      'Mineral Water',
      'Citron',
      'Special Citron',
    ]) {
      final bytes = UriData.parse(
        catalog.iconDataUriAcrossModes(
          CraftMode.cooking,
          name,
          preferCleanArtwork: true,
        )!,
      ).contentAsBytes();
      final corners = await tester.runAsync(() async {
        final codec = await ui.instantiateImageCodec(bytes);
        final frame = await codec.getNextFrame();
        final pixels = (await frame.image.toByteData())!;
        final width = frame.image.width;
        final height = frame.image.height;
        final alpha = [
          0,
          width - 1,
          width * (height - 1),
          width * height - 1,
        ].map((index) => pixels.getUint8(index * 4 + 3)).toList();
        frame.image.dispose();
        codec.dispose();
        return alpha;
      });
      expect(corners, everyElement(0), reason: name);
    }
  });

  testWidgets('native item frames are consistent across themes and sizes', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1060, 620);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final harness = PlannerTestHarness();
    const themes = [
      SakuraNightGardenSpec.theme,
      IlluminatedLedgerSpec.theme,
      StandardSpec.theme,
    ];
    const labels = ['Sakura', 'Ledger', 'Standard'];
    const names = [
      'Egg',
      'Milk',
      'Mineral Water',
      'Citron',
      'High-quality Citron',
      'Special Citron',
      'Perfume of Tenacity',
      "Labreska's Helmet (Bound)",
    ];
    final capture = GlobalKey();
    await tester.pumpWidget(
      MaterialApp(
        home: RepaintBoundary(
          key: capture,
          child: Material(
            child: Column(
              children: [
                for (var index = 0; index < themes.length; index++)
                  Expanded(
                    child: ThemeSpecScope(
                      spec: themes[index],
                      child: Builder(
                        builder: (context) {
                          final spec = themes[index];
                          return ColoredBox(
                            color: spec.palette.surface,
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 24,
                                vertical: 18,
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    labels[index],
                                    style: TextStyle(
                                      fontFamily: 'Segoe UI',
                                      fontSize: 20,
                                      fontWeight: FontWeight.w600,
                                      color: spec.palette.text,
                                    ),
                                  ),
                                  const SizedBox(height: 18),
                                  Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      for (final name in names)
                                        Expanded(
                                          child: Column(
                                            children: [
                                              Row(
                                                mainAxisAlignment:
                                                    MainAxisAlignment.center,
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.end,
                                                children: [
                                                  for (final size in [
                                                    44.0,
                                                    24.0,
                                                  ]) ...[
                                                    ModeItemIcon(
                                                      controller: harness
                                                          .controller
                                                          .active,
                                                      catalogRepository:
                                                          catalog,
                                                      name: name,
                                                      size: size,
                                                      searchAcrossModes: true,
                                                    ),
                                                    const SizedBox(width: 5),
                                                  ],
                                                ],
                                              ),
                                              const SizedBox(height: 10),
                                              Text(
                                                name,
                                                textAlign: TextAlign.center,
                                                style: TextStyle(
                                                  fontFamily: 'Segoe UI',
                                                  fontSize: 12,
                                                  height: 1.3,
                                                  color: spec.palette.text,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
    // Let asynchronous image decoding finish; no live application is touched.
    await tester.runAsync(() async {
      for (final element in find.byType(Image).evaluate()) {
        final image = element.widget as Image;
        await precacheImage(image.image, element);
      }
    });
    await tester.pumpAndSettle();
    expect(find.byType(ItemIconFrame), findsNWidgets(48));
    for (final element in find.byType(ModeItemIcon).evaluate()) {
      final widget = element.widget as ModeItemIcon;
      expect(widget.fit, BoxFit.contain);
      expect(widget.showFrame, isTrue);
      final frames = find.descendant(
        of: find.byWidget(widget),
        matching: find.byType(ItemIconFrame),
      );
      expect(frames, findsOneWidget);
      final frame = tester.widget<ItemIconFrame>(frames);
      expect(frame.grade, catalog.itemIconGrade(widget.name));
      expect(tester.getSize(find.byWidget(widget)), Size.square(widget.size));
    }
    expect(tester.takeException(), isNull);
    if (const bool.fromEnvironment('CAPTURE_ITEM_ICONS')) {
      final boundary =
          capture.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      await tester.runAsync(() async {
        final image = await boundary.toImage();
        final png = (await image.toByteData(format: ui.ImageByteFormat.png))!;
        final directory = Directory('tmp/item-icon-style')
          ..createSync(recursive: true);
        File(
          '${directory.path}/native-icon-themes.png',
        ).writeAsBytesSync(png.buffer.asUint8List());
        image.dispose();
      });
    }
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.runAsync(harness.controller.dispose);
  });
}
