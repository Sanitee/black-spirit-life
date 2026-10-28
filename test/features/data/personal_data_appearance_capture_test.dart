import 'dart:io';
import 'dart:ui' as ui;

import 'package:bdo_craft_planner_flutter/app/app.dart';
import 'package:bdo_craft_planner_flutter/visual/visual.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/application_test_harness.dart';

const _captureRoot = ValueKey('personal-data-capture');

void main() {
  setUpAll(_loadCaptureFonts);
  for (final spec in [
    StandardSpec.theme,
    IlluminatedLedgerSpec.theme,
    SakuraNightGardenSpec.theme,
  ]) {
    final themeName = spec.id;
    for (final width in [1200.0, 1500.0]) {
      for (final scale in [1.0, 2.0]) {
        testWidgets(
          'personal data in actual $themeName profile at $width scale $scale',
          (tester) async {
            configureApplicationTestSurface(
              tester,
              Size(width, 940),
              textScaleFactor: scale,
            );
            final original = (await tester.runAsync(
              () => ApplicationTestHarness.create(
                backgroundId: spec.isStandard ? 'greenhouse' : spec.id,
                view: 'data',
              ),
            ))!;
            final harness = original.rebindControllerInCurrentZone();
            await tester.runAsync(original.disposeControllerOnly);
            await tester.pumpWidget(
              RepaintBoundary(
                key: _captureRoot,
                child: BdoCraftPlannerApp(
                  enableOpportunityAutoCheck: false,
                  applicationFuture: Future.value(harness.bundle),
                  marketGateway: const EmptyMarketGateway(),
                ),
              ),
            );
            await tester.pumpAndSettle();
            await tester.runAsync(() async {
              await Future.wait([
                for (final element in find.byType(Image).evaluate())
                  precacheImage((element.widget as Image).image, element),
              ]);
            });
            final card = find.byKey(const ValueKey('data-personal-data-card'));
            await Scrollable.ensureVisible(
              tester.element(card),
              alignment: .08,
              duration: Duration.zero,
            );
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull);
            expect(find.text('Inventory'), findsWidgets);
            expect(find.text('Character & mastery'), findsOneWidget);
            expect(find.text('App settings'), findsOneWidget);
            expect(find.text('Favourites'), findsOneWidget);
            final activePath =
                harness.bundle.stateRepository.paths.applicationDirectory.path;
            expect(
              tester
                  .widget<SelectableText>(
                    find.byKey(const ValueKey('data-personal-data-path')),
                  )
                  .data,
              activePath,
            );
            final bounds = tester.getRect(card);
            for (final label in [
              'Inventory',
              'Character & mastery',
              'App settings',
              'Favourites',
            ]) {
              final tile = tester.getRect(
                find.byKey(ValueKey('data-category:$label')),
              );
              expect(bounds.contains(tile.topLeft), isTrue);
              expect(bounds.contains(tile.bottomRight), isTrue);
            }
            final output = Platform.environment['BSL_PROFILE_CAPTURE_DIR'];
            if (output != null && output.isNotEmpty) {
              final fileWidth = width.toInt();
              final fileScale = (scale * 100).round();
              final boundary = tester.renderObject<RenderRepaintBoundary>(
                find.byKey(_captureRoot),
              );
              await tester.runAsync(() async {
                final image = await boundary.toImage(pixelRatio: 1);
                try {
                  final bytes = await image.toByteData(
                    format: ui.ImageByteFormat.png,
                  );
                  final file = File(
                    '$output/personal-data-$themeName-$fileWidth-$fileScale.png',
                  );
                  await file.parent.create(recursive: true);
                  await file.writeAsBytes(bytes!.buffer.asUint8List());
                } finally {
                  image.dispose();
                }
              });
            }
            await tester.pumpWidget(const SizedBox.shrink());
            await harness.disposeControllerOnly();
            await tester.runAsync(
              () => harness.temporaryDirectory.delete(recursive: true),
            );
          },
        );
      }
    }
  }
}

Future<void> _loadCaptureFonts() async {
  final windowsRoot = Platform.environment['WINDIR'] ?? r'C:\Windows';
  var flutterRoot = File(Platform.resolvedExecutable).parent;
  while (!Directory(
    '${flutterRoot.path}/bin/cache/artifacts/material_fonts',
  ).existsSync()) {
    if (flutterRoot.parent.path == flutterRoot.path) {
      throw StateError('Flutter fonts not found.');
    }
    flutterRoot = flutterRoot.parent;
  }
  final materialFonts =
      '${flutterRoot.path}/bin/cache/artifacts/material_fonts';
  for (final entry in {
    'Segoe UI': [
      '$windowsRoot/Fonts/segoeui.ttf',
      '$windowsRoot/Fonts/seguisb.ttf',
      '$windowsRoot/Fonts/segoeuib.ttf',
    ],
    'Georgia': [
      '$windowsRoot/Fonts/georgia.ttf',
      '$windowsRoot/Fonts/georgiab.ttf',
      '$windowsRoot/Fonts/georgiai.ttf',
    ],
    'Roboto': [
      '$materialFonts/roboto-regular.ttf',
      '$materialFonts/roboto-bold.ttf',
    ],
    'MaterialIcons': ['$materialFonts/materialicons-regular.otf'],
  }.entries) {
    final loader = FontLoader(entry.key);
    final available = entry.value
        .where((path) => File(path).existsSync())
        .toList();
    final paths = available.isNotEmpty
        ? available
        : [
            '$materialFonts/roboto-regular.ttf',
            '$materialFonts/roboto-bold.ttf',
          ];
    for (final path in paths) {
      loader.addFont(File(path).readAsBytes().then(ByteData.sublistView));
    }
    await loader.load();
  }
}
