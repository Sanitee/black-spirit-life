import 'dart:io';
import 'dart:ui' as ui;

import 'package:bdo_craft_planner_flutter/app/first_run_setup.dart';
import 'package:bdo_craft_planner_flutter/app_identity.dart';
import 'package:bdo_craft_planner_flutter/visual/visual.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/application_test_harness.dart';
import 'folding_setup_test.dart';

Future<void> _fonts() async {
  const fonts = {
    'Segoe UI': [
      'C:/Windows/Fonts/segoeui.ttf',
      'C:/Windows/Fonts/seguisb.ttf',
      'C:/Windows/Fonts/segoeuib.ttf',
    ],
    'Georgia': [
      'C:/Windows/Fonts/georgia.ttf',
      'C:/Windows/Fonts/georgiab.ttf',
    ],
    'Roboto': [
      'D:/Tools/flutter/bin/cache/artifacts/material_fonts/roboto-regular.ttf',
    ],
    'MaterialIcons': [
      'D:/Tools/flutter/bin/cache/artifacts/material_fonts/materialicons-regular.otf',
    ],
  };
  for (final entry in fonts.entries) {
    final loader = FontLoader(entry.key);
    for (final path in entry.value) {
      if (await File(path).exists()) {
        loader.addFont(
          File(path).readAsBytes().then((v) => ByteData.sublistView(v)),
        );
      }
    }
    await loader.load();
  }
}

Future<void> _images(WidgetTester tester) async {
  final context = tester.element(find.byKey(const ValueKey('setup-capture')));
  for (final path in [
    AppIdentity.appIconAssetPath,
    SakuraNightGardenSpec.blackenedCedarAssetPath,
    SakuraBotanicalAssets.titleSprig,
    SakuraBotanicalAssets.sectionBloom,
    'assets/sakura/materials/charcoal-plum-lacquer.png',
  ]) {
    await tester.runAsync(() => precacheImage(AssetImage(path), context));
  }
  for (final element in find.byType(Image).evaluate()) {
    await tester.runAsync(
      () => precacheImage((element.widget as Image).image, element),
    );
  }
  await tester.pumpAndSettle();
}

Future<void> _capture(WidgetTester tester, String name) async {
  final folder = Platform.environment['BSL_SETUP_CAPTURE_DIR'];
  if (folder == null) return;
  await _images(tester);
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(const ValueKey('setup-capture')),
  );
  final bounds = tester
      .getRect(find.byKey(const ValueKey('first-run-setup-panel')))
      .shift(-tester.getTopLeft(find.byKey(const ValueKey('setup-capture'))));
  expect(boundary.debugNeedsPaint, isFalse);
  final layer = boundary.debugLayer! as OffsetLayer;
  await tester.runAsync(() async {
    await Directory(folder).create(recursive: true);
    for (final full in [false, true]) {
      final image = full
          ? await layer.toImage(Offset.zero & boundary.size, pixelRatio: 1)
          : await layer.toImage(bounds.inflate(6), pixelRatio: 1);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      await File(
        '$folder/$name${full ? '-full' : ''}.png',
      ).writeAsBytes(bytes!.buffer.asUint8List());
      image.dispose();
    }
  });
}

void main() {
  setUpAll(_fonts);
  testWidgets('actual Flutter setup captures with synthetic values only', (
    tester,
  ) async {
    configureApplicationTestSurface(tester, const Size(1200, 752));
    await pumpSetup(tester);
    expect(saveButton(tester).onPressed, isNull);
    await _capture(tester, 'empty');
    await tester.pumpWidget(const SizedBox.shrink());
    await pumpSetup(tester, document: setupDocument(filled: true));
    expect(saveButton(tester).onPressed, isNotNull);
    await _capture(tester, 'filled');
    await openSetup(tester, FirstRunSetupGroup.afkLoad);
    await _capture(tester, 'weight');
    await openSetup(tester, FirstRunSetupGroup.marketSales);
    await _capture(tester, 'sales');
    expect(tester.takeException(), isNull);
  });

  for (final theme in RetainedThemeRegistry.themes) {
    for (final scale in [1.0, 1.5, 2.0]) {
      for (final size in [const Size(1200, 752), const Size(800, 600)]) {
        testWidgets('setup fits ${theme.id} at $size / ${scale}x text', (
          tester,
        ) async {
          configureApplicationTestSurface(tester, size);
          await pumpSetup(
            tester,
            document: setupDocument(filled: true),
            scale: scale,
            theme: theme,
          );
          for (final group in FirstRunSetupSchema.groups) {
            if (group != FirstRunSetupGroup.masteryAndOutput) {
              await openSetup(tester, group);
            }
            expect(tester.takeException(), isNull);
            final viewport = Offset.zero & size;
            for (final key in [
              'first-run-setup-panel',
              'first-run-setup-title',
              'first-run-setup-skip',
              'first-run-setup-finish',
            ]) {
              final rect = tester.getRect(find.byKey(ValueKey(key)));
              expect(viewport.contains(rect.topLeft), isTrue, reason: key);
              expect(viewport.contains(rect.bottomRight), isTrue, reason: key);
            }
            // Every expanded control remains reachable within the internal scroll.
            final lastControl = switch (group) {
              FirstRunSetupGroup.masteryAndOutput => 'setup-mass-processing',
              FirstRunSetupGroup.afkLoad => 'setup-feathery-steps-5',
              FirstRunSetupGroup.marketSales => 'setup-family-fame',
            };
            await tester.ensureVisible(find.byKey(ValueKey(lastControl)));
            await tester.pumpAndSettle();
            expect(
              find.byKey(ValueKey(lastControl)).hitTestable(),
              findsOneWidget,
            );
            expect(tester.takeException(), isNull);
          }
          if (theme.id == SakuraNightGardenSpec.theme.id &&
              scale == 2 &&
              size.width == 800) {
            await _capture(tester, 'large-text-sales');
          }
        });
      }
    }
  }
}
