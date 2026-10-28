import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:bdo_craft_planner_flutter/visual/components/item_icon_frame.dart';
import 'package:bdo_gathering_companion/src/ui/item_artwork.dart';
import 'package:bdo_gathering_companion/src/ui/theme.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _root = 'packages/bdo_gathering_companion';
const _examples = [4001, 5401, 721002, 721003, 5000, 16001];

void main() {
  test('all companion item assets resolve verified art and rarity', () {
    final provenance =
        jsonDecode(
              File(
                '$_root/assets/icons/item_artwork/provenance.json',
              ).readAsStringSync(),
            )
            as Map;
    final records = (provenance['records'] as List).cast<Map>();
    expect(records, hasLength(308));
    expect(gatheringItemGrades, hasLength(307));
    final expected = <String>{};
    for (final record in records) {
      final original = record['original'] as String;
      expected.add(original);
      expect(gatheringItemGrade(original), record['grade']);
      expect(gatheringItemArtwork(original), record['artwork']);
      expect(
        itemGradeColor(record['grade']),
        itemQualityColor(record['grade']),
      );
      expect(
        sha256.convert(File('$_root/$original').readAsBytesSync()).toString(),
        record['referenceSha256'],
      );
      expect(
        sha256
            .convert(File('$_root/${record['artwork']}').readAsBytesSync())
            .toString(),
        record['sha256'],
      );
    }
    final bundled = <String>{};
    for (final group in ['items', 'buffs']) {
      for (final file in Directory(
        '$_root/assets/icons/$group',
      ).listSync().whereType<File>()) {
        final name = file.uri.pathSegments.last;
        if (RegExp(r'^\d+\.webp$').hasMatch(name)) {
          bundled.add('assets/icons/$group/$name');
        }
      }
    }
    expect(
      bundled,
      expected,
      reason: 'Every bundled item needs the common display treatment',
    );
    for (final path in [
      'assets/icons/tools/hoe.webp',
      'assets/icons/buffs/refreshing-dream.webp',
      'assets/icons/sources/bdoworkshop_logo.png',
      'assets/icons/items/999999999.webp',
      '',
    ]) {
      expect(gatheringItemArtwork(path), path);
      expect(gatheringItemGrade(path), isNull);
    }
  });

  testWidgets('clean companion art has no baked square at the corners', (
    tester,
  ) async {
    await tester.runAsync(() async {
      // Black Stone deliberately retains its original full-bleed purple art.
      // These formerly framed materials have transparent original corners.
      for (final id in _examples.where((id) => id != 16001)) {
        final path = gatheringItemArtwork('assets/icons/items/$id.webp');
        final data = await rootBundle.load(
          'packages/bdo_gathering_companion/$path',
        );
        final codec = await ui.instantiateImageCodec(
          data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
        );
        final frame = await codec.getNextFrame();
        final pixels = (await frame.image.toByteData())!.buffer.asUint8List();
        final width = frame.image.width;
        final height = frame.image.height;
        for (final pixel in [
          0,
          width - 1,
          width * (height - 1),
          width * height - 1,
        ]) {
          expect(pixels[pixel * 4 + 3], 0, reason: 'No baked border: $id');
        }
        frame.image.dispose();
        codec.dispose();
      }
    });
  });

  for (final opacity in [0, 60, 100]) {
    testWidgets('one grade outline at every size and opacity $opacity', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: companionTheme(opacityPercent: opacity),
          home: Scaffold(
            body: Wrap(
              children: [
                for (final size in [24.0, 36.0, 44.0])
                  for (final id in _examples)
                    GameIcon(
                      'assets/icons/items/$id.webp',
                      key: ValueKey('$id-$size'),
                      size: size,
                    ),
              ],
            ),
          ),
        ),
      );
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 200)),
      );
      await tester.pump();
      for (final size in [24.0, 36.0, 44.0]) {
        for (final id in _examples) {
          final finder = find.byKey(ValueKey('$id-$size'));
          expect(tester.getSize(finder), Size.square(size));
          final decorations = tester.widgetList<DecoratedBox>(
            find.descendant(of: finder, matching: find.byType(DecoratedBox)),
          );
          final borders = decorations
              .map((widget) => widget.decoration)
              .whereType<BoxDecoration>()
              .where((decoration) => decoration.border != null);
          expect(borders, hasLength(1));
          final border = borders.single.border! as Border;
          final grade = gatheringItemGrades[id];
          expect(
            border.top.color,
            itemQualityColor(grade)!.withAlpha(grade == 0 ? 125 : 210),
          );
          expect(border.top.width, size >= 36 ? 1.2 : 1);
          expect(
            find.descendant(of: finder, matching: find.byType(CustomPaint)),
            findsNothing,
          );
          final image = tester.widget<Image>(
            find.descendant(of: finder, matching: find.byType(Image)),
          );
          expect(image.fit, BoxFit.contain);
          expect(
            (image.image as AssetImage).assetName,
            'assets/icons/item_artwork/$id.webp',
          );
        }
      }
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'explicit grades still work and inventory actions are unchanged',
    (tester) async {
      var taps = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: companionTheme(),
          home: Center(
            child: GestureDetector(
              onTap: () => taps++,
              child: const GameIcon('assets/icons/items/4001.webp', grade: 2),
            ),
          ),
        ),
      );
      final frame = tester.widget<Container>(
        find
            .descendant(
              of: find.byType(GameIcon),
              matching: find.byType(Container),
            )
            .first,
      );
      final border =
          (frame.foregroundDecoration! as BoxDecoration).border! as Border;
      expect(border.top.color, itemQualityColor(2)!.withAlpha(210));
      await tester.tap(find.byType(GameIcon));
      expect(taps, 1);
    },
  );

  testWidgets('native companion icon gallery', (tester) async {
    tester.view
      ..physicalSize = const Size(760, 300)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    const key = ValueKey('companion-gallery');
    await tester.pumpWidget(
      MaterialApp(
        theme: companionTheme(),
        home: Scaffold(
          backgroundColor: canvasColor,
          body: RepaintBoundary(
            key: key,
            child: ColoredBox(
              color: canvasColor,
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Gathering · one quality frame',
                      style: TextStyle(fontSize: 22),
                    ),
                    const SizedBox(height: 24),
                    for (final size in [44.0, 24.0])
                      Padding(
                        padding: const EdgeInsets.only(bottom: 24),
                        child: Row(
                          children: [
                            for (final id in _examples)
                              Padding(
                                padding: const EdgeInsets.only(right: 48),
                                child: GameIcon(
                                  'assets/icons/items/$id.webp',
                                  size: size,
                                ),
                              ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 400)),
    );
    await tester.pump();
    if (const bool.fromEnvironment('CAPTURE_ITEM_ICONS')) {
      await tester.runAsync(() async {
        final boundary = tester.renderObject<RenderRepaintBoundary>(
          find.byKey(key),
        );
        final image = await boundary.toImage();
        final data = (await image.toByteData(format: ui.ImageByteFormat.png))!;
        final output = File('tmp/item-icon-style/companion-gallery.png');
        await output.parent.create(recursive: true);
        await output.writeAsBytes(data.buffer.asUint8List());
        image.dispose();
      });
    }
    expect(tester.takeException(), isNull);
  });
}
