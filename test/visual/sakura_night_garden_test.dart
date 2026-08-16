import 'dart:ui' as ui;

import 'package:bdo_craft_planner_flutter/visual/components/app_button.dart';
import 'package:bdo_craft_planner_flutter/visual/components/app_completion_control.dart';
import 'package:bdo_craft_planner_flutter/visual/components/app_surface.dart';
import 'package:bdo_craft_planner_flutter/visual/components/app_vector_glyph.dart';
import 'package:bdo_craft_planner_flutter/visual/components/section_header.dart';
import 'package:bdo_craft_planner_flutter/visual/foundations/theme_spec.dart';
import 'package:bdo_craft_planner_flutter/visual/sakura_night_garden/sakura_botanical_assets.dart';
import 'package:bdo_craft_planner_flutter/visual/sakura_night_garden/sakura_material_painters.dart';
import 'package:bdo_craft_planner_flutter/visual/sakura_night_garden/sakura_spec.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'retained botanical PNGs decode at their authored pixel dimensions',
    () async {
      final cases = <(String, Size, Size)>[
        (
          SakuraBotanicalAssets.sidebarBranch,
          SakuraSidebarBotanicalAsset.authoredSize,
          const Size(792, 1160),
        ),
        (
          SakuraBotanicalAssets.titleSprig,
          SakuraTitleSprigAsset.authoredSize,
          const Size(840, 160),
        ),
        (
          SakuraBotanicalAssets.sectionBloom,
          SakuraSectionBloomAsset.authoredSize,
          const Size(320, 72),
        ),
        (
          SakuraBotanicalAssets.queueRisingBloom,
          SakuraQueueCornerAsset.authoredSize,
          const Size(432, 240),
        ),
        (
          SakuraBotanicalAssets.queueLowBuds,
          SakuraQueueCornerAsset.authoredSize,
          const Size(432, 240),
        ),
        (
          SakuraBotanicalAssets.queueSplitBloom,
          SakuraQueueCornerAsset.authoredSize,
          const Size(432, 240),
        ),
      ];

      for (final (path, logicalSize, pixelSize) in cases) {
        final decoded = await _decodeAsset(path);
        addTearDown(decoded.dispose);

        expect(decoded.size, pixelSize, reason: path);
        expect(
          decoded.size.width % logicalSize.width,
          0,
          reason: '$path must use an integer horizontal source scale',
        );
        expect(
          decoded.size.height % logicalSize.height,
          0,
          reason: '$path must use an integer vertical source scale',
        );
        for (final corner in <Offset>[
          Offset.zero,
          Offset(decoded.size.width - 1, 0),
          Offset(0, decoded.size.height - 1),
          Offset(decoded.size.width - 1, decoded.size.height - 1),
        ]) {
          expect(
            decoded.alphaAt(corner.dx.toInt(), corner.dy.toInt()),
            0,
            reason: '$path must retain a transparent corner at $corner',
          );
        }
        expect(
          decoded.hasVisiblePixel,
          isTrue,
          reason: '$path must contain decoded botanical artwork',
        );
      }
    },
  );

  test('queue card indices cycle through three stable asset variants', () {
    expect(
      SakuraQueueCornerAsset.variantForIndex(0),
      SakuraQueueCornerAssetVariant.risingBloom,
    );
    expect(
      SakuraQueueCornerAsset.variantForIndex(1),
      SakuraQueueCornerAssetVariant.lowBuds,
    );
    expect(
      SakuraQueueCornerAsset.variantForIndex(2),
      SakuraQueueCornerAssetVariant.splitBloom,
    );
    expect(
      SakuraQueueCornerAsset.variantForIndex(3),
      SakuraQueueCornerAssetVariant.risingBloom,
    );
    expect(
      SakuraQueueCornerAsset.variantForIndex(-1),
      SakuraQueueCornerAssetVariant.splitBloom,
    );
  });

  test(
    'queue corner assets decode as three unique retained arrangements',
    () async {
      final decoded = <_DecodedAsset>[];
      for (final path in <String>[
        SakuraBotanicalAssets.queueRisingBloom,
        SakuraBotanicalAssets.queueLowBuds,
        SakuraBotanicalAssets.queueSplitBloom,
      ]) {
        final asset = await _decodeAsset(path);
        decoded.add(asset);
        addTearDown(asset.dispose);
        expect(asset.size, const Size(432, 240));
      }

      for (var firstIndex = 0; firstIndex < decoded.length; firstIndex++) {
        for (
          var secondIndex = firstIndex + 1;
          secondIndex < decoded.length;
          secondIndex++
        ) {
          expect(
            listEquals(decoded[firstIndex].rgba, decoded[secondIndex].rgba),
            isFalse,
            reason: 'each Queue-card variant must retain distinct authored art',
          );
        }
      }
    },
  );

  testWidgets(
    'botanical widgets keep fixed logical sizes and stay noninteractive',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: SakuraNightGardenSpec.theme.materialTheme(),
          home: const Scaffold(
            body: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                SakuraSidebarBotanicalAsset(),
                SakuraTitleSprigAsset(),
                SakuraSectionBloomAsset(),
                SakuraQueueCornerAsset(
                  variant: SakuraQueueCornerAssetVariant.risingBloom,
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pump();

      for (final (widgetType, imageKey, failureKey, expectedSize)
          in <(Type, Key, Key, Size)>[
            (
              SakuraSidebarBotanicalAsset,
              SakuraSidebarBotanicalAsset.imageKey,
              SakuraSidebarBotanicalAsset.failureKey,
              SakuraSidebarBotanicalAsset.authoredSize,
            ),
            (
              SakuraTitleSprigAsset,
              SakuraTitleSprigAsset.imageKey,
              SakuraTitleSprigAsset.failureKey,
              SakuraTitleSprigAsset.authoredSize,
            ),
            (
              SakuraSectionBloomAsset,
              SakuraSectionBloomAsset.imageKey,
              SakuraSectionBloomAsset.failureKey,
              SakuraSectionBloomAsset.authoredSize,
            ),
            (
              SakuraQueueCornerAsset,
              const ValueKey<String>('sakura-queue-risingBloom-image'),
              const ValueKey<String>('sakura-queue-risingBloom-failure'),
              SakuraQueueCornerAsset.authoredSize,
            ),
          ]) {
        final asset = find.byType(widgetType);
        final image = find.byKey(imageKey);
        expect(asset, findsOneWidget);
        expect(tester.getSize(asset), expectedSize);
        expect(image, findsOneWidget);
        expect(find.byKey(failureKey), findsNothing);
        expect(
          find.ancestor(of: image, matching: find.byType(IgnorePointer)),
          findsWidgets,
        );
        expect(
          find.ancestor(of: image, matching: find.byType(ExcludeSemantics)),
          findsWidgets,
        );
      }
    },
  );

  testWidgets(
    'Sakura card anchors a fixed asset through variable heights and hit-tests',
    (tester) async {
      var taps = 0;
      const surfaceKey = ValueKey<String>('ornamented-sakura-card');
      const buttonKey = ValueKey<String>('ornament-under-hit-target');

      Future<void> pumpCard({
        required int? ornamentIndex,
        double height = 92,
      }) async {
        await tester.pumpWidget(
          MaterialApp(
            theme: SakuraNightGardenSpec.theme.materialTheme(),
            home: ThemeSpecScope(
              spec: SakuraNightGardenSpec.theme,
              child: Scaffold(
                body: Align(
                  alignment: Alignment.topLeft,
                  child: SizedBox(
                    width: 220,
                    height: height,
                    child: AppSurface(
                      key: surfaceKey,
                      role: AppSurfaceRole.card,
                      ornamentIndex: ornamentIndex,
                      padding: EdgeInsets.zero,
                      child: Align(
                        alignment: Alignment.bottomRight,
                        child: SizedBox(
                          width: 54,
                          height: 30,
                          child: TextButton(
                            key: buttonKey,
                            onPressed: () => taps++,
                            child: const Text('Use'),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      }

      for (final height in <double>[92, 148]) {
        await pumpCard(ornamentIndex: 2, height: height);
        final surface = find.byKey(surfaceKey);
        final queueAsset = find.descendant(
          of: surface,
          matching: find.byType(SakuraQueueCornerAsset),
        );
        final surfaceRect = tester.getRect(surface);
        final assetRect = tester.getRect(queueAsset);

        expect(surfaceRect.size, Size(220, height));
        expect(assetRect.size, SakuraQueueCornerAsset.authoredSize);
        expect(assetRect.right, closeTo(surfaceRect.right - 1, .01));
        expect(assetRect.bottom, closeTo(surfaceRect.bottom - 1, .01));
        expect(
          tester.widget<SakuraQueueCornerAsset>(queueAsset).variant,
          SakuraQueueCornerAssetVariant.splitBloom,
        );

        await tester.tap(find.byKey(buttonKey));
        await tester.pump();
      }
      expect(
        taps,
        2,
        reason: 'decorative assets must never intercept card interaction',
      );

      await pumpCard(ornamentIndex: null);
      expect(
        find.descendant(
          of: find.byKey(surfaceKey),
          matching: find.byType(SakuraQueueCornerAsset),
        ),
        findsNothing,
      );
    },
  );

  testWidgets(
    'Sakura completion is visually quieter without shrinking its hit target',
    (tester) async {
      var taps = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: SakuraNightGardenSpec.theme.materialTheme(),
          home: ThemeSpecScope(
            spec: SakuraNightGardenSpec.theme,
            child: Scaffold(
              body: Align(
                alignment: Alignment.topLeft,
                child: AppCompletionControl(
                  completed: false,
                  semanticLabel: 'Done with Purified Water',
                  onPressed: () => taps++,
                ),
              ),
            ),
          ),
        ),
      );

      final control = find.byType(AppCompletionControl);
      final material = find.descendant(
        of: control,
        matching: find.byKey(AppButton.materialKey),
      );
      final glyph = tester.widget<AppVectorGlyph>(
        find.descendant(of: control, matching: find.byType(AppVectorGlyph)),
      );

      expect(tester.getSize(control), const Size.square(46));
      expect(tester.getSize(material), const Size.square(40));
      expect(glyph.size, 20);
      expect(glyph.tightBounds, isTrue);
      expect(find.bySemanticsLabel('Done with Purified Water'), findsOneWidget);

      final hitBounds = tester.getRect(control);
      await tester.tapAt(Offset(hitBounds.left + 1, hitBounds.center.dy));
      await tester.pump();
      expect(
        taps,
        1,
        reason: 'the transparent 3 px visual inset remains clickable',
      );
    },
  );

  testWidgets('canonical Sakura header keeps Craft Queue fully readable', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: SakuraNightGardenSpec.theme.materialTheme(),
        home: ThemeSpecScope(
          spec: SakuraNightGardenSpec.theme,
          child: const Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: 545,
                child: SectionHeader(
                  title: 'Craft Queue',
                  meta: '42 left',
                  trailing: SizedBox(width: 76, height: 38),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    final title = tester.renderObject<RenderParagraph>(
      find.byKey(SectionHeader.titleKey),
    );
    // Widget tests substitute Ahem for Georgia, making each character roughly
    // square and therefore unsuitable for an ellipsis assertion. Guard the
    // real fix instead: the canonical row must reserve the measured 150px
    // title allocation that the Windows Georgia lockup needs.
    expect(
      title.size.width,
      greaterThanOrEqualTo(150),
      reason:
          'title=${tester.getRect(find.byKey(SectionHeader.titleKey))}, '
          'rule=${tester.getRect(find.byKey(SectionHeader.ruleKey))}',
    );
    expect(title.text.toPlainText(), 'Craft Queue');
    expect(
      tester.getRect(find.byKey(SectionHeader.titleKey)).right,
      lessThan(tester.getRect(find.byKey(SectionHeader.ruleKey)).left),
    );
  });

  test('cedar material rendering is deterministic', () async {
    const painter = SakuraCedarGrainPainter(sidebar: true, density: .74);
    final first = await _render(painter, const Size(96, 72));
    final repeated = await _render(painter, const Size(96, 72));

    expect(listEquals(first, repeated), isTrue);
    expect(_hasPaint(first), isTrue);
    expect(painter.hitTest(const Offset(20, 20)), isFalse);
    expect(
      painter.shouldRepaint(
        const SakuraCedarGrainPainter(sidebar: true, density: .74),
      ),
      isFalse,
    );
    expect(
      painter.shouldRepaint(
        const SakuraCedarGrainPainter(sidebar: false, density: .74),
      ),
      isTrue,
    );
  });

  test('navigation material tooling remains paint-only', () {
    const painter = SakuraNavigationTabPainter();
    expect(painter.hitTest(const Offset(1, 1)), isFalse);
    expect(painter.semanticsBuilder, isNull);
  });
}

Future<Uint8List> _render(CustomPainter painter, Size size) async {
  final width = size.width.toInt();
  final height = size.height.toInt();
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  painter.paint(canvas, size);
  final picture = recorder.endRecording();
  final image = await picture.toImage(width, height);
  final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  image.dispose();
  picture.dispose();
  return data!.buffer.asUint8List();
}

bool _hasPaint(Uint8List bytes) {
  for (var index = 3; index < bytes.length; index += 4) {
    if (bytes[index] != 0) return true;
  }
  return false;
}

Future<_DecodedAsset> _decodeAsset(String path) async {
  final encoded = await rootBundle.load(path);
  final bytes = encoded.buffer.asUint8List(
    encoded.offsetInBytes,
    encoded.lengthInBytes,
  );
  final codec = await ui.instantiateImageCodec(bytes);
  final frame = await codec.getNextFrame();
  final image = frame.image;
  final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  codec.dispose();
  return _DecodedAsset(
    image: image,
    rgba: data!.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
  );
}

final class _DecodedAsset {
  const _DecodedAsset({required this.image, required this.rgba});

  final ui.Image image;
  final Uint8List rgba;

  Size get size => Size(image.width.toDouble(), image.height.toDouble());

  int alphaAt(int x, int y) => rgba[(y * image.width + x) * 4 + 3];

  bool get hasVisiblePixel {
    for (var index = 3; index < rgba.length; index += 4) {
      if (rgba[index] != 0) return true;
    }
    return false;
  }

  void dispose() => image.dispose();
}
