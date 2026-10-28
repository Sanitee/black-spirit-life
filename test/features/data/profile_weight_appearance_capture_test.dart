import 'dart:io';
import 'dart:ui' as ui;

import 'package:bdo_craft_planner_flutter/app/app.dart';
import 'package:bdo_craft_planner_flutter/domain/state/planner_state.dart';
import 'package:bdo_craft_planner_flutter/features/shared/profile_game_icon.dart';
import 'package:bdo_craft_planner_flutter/visual/visual.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/application_test_harness.dart';

const _captureRoot = ValueKey('profile-weight-capture');

void main() {
  setUpAll(_loadCaptureFonts);
  for (final spec in [
    StandardSpec.theme,
    IlluminatedLedgerSpec.theme,
    SakuraNightGardenSpec.theme,
  ]) {
    for (final width in [1200.0, 1500.0]) {
      for (final scale in [1.0, 1.5, 2.0]) {
        testWidgets(
          'open character weight in actual ${spec.id} profile at $width / ${scale}x',
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
            harness.bundle.controller.updateDocument(
              (state) => state.copyWith(
                afkWeightProfile: AfkWeightProfile(
                  maximumWeightLt: 1600,
                  currentCarriedWeightLt: 125,
                  safetyBufferLt: 25,
                  featheryStepsLevel: 5,
                ),
              ),
            );
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
            await _precacheProfileImages(tester);
            final maximum = find.byKey(
              const ValueKey('data-afk-maximum-weight'),
            );
            expect(maximum, findsOneWidget);
            expect(
              find.byKey(const ValueKey('data-afk-load-toggle')),
              findsNothing,
            );
            expect(find.byType(ProfileIcon), findsNWidgets(7));
            final bounds = tester.getRect(maximum);
            if (scale == 1) {
              expect(bounds.width, inInclusiveRange(124, 160));
            }
            final afk = tester.getRect(
              find.byKey(const ValueKey('data-afk-load-card')),
            );
            final mastery = tester.getRect(
              find.byKey(const ValueKey('data-craft-output-card')),
            );
            expect(afk.width, closeTo(mastery.width, 1));
            for (final key in [
              'data-afk-maximum-weight',
              'data-afk-current-weight',
              'data-afk-safety-buffer',
            ]) {
              final field = tester.getRect(find.byKey(ValueKey(key)));
              expect(field.width, closeTo(bounds.width, .01));
              expect(field.left, greaterThanOrEqualTo(afk.left));
              expect(field.right, lessThanOrEqualTo(afk.right));
            }
            for (final artwork in ProfileArtwork.values) {
              expect(
                tester.getSize(
                  find.byKey(ValueKey('profile-inlay:${artwork.name}')),
                ),
                const Size(52, 52),
              );
            }
            final feather = tester.widget<Image>(
              find.byKey(const ValueKey('profile-original-icon:featherySteps')),
            );
            expect(
              feather.image,
              const AssetImage(ProfileIcon.featheryAssetPath),
            );
            expect(
              feather.color,
              isNull,
              reason: 'Preserve original skill artwork.',
            );
            for (final artwork in ProfileArtwork.values.where(
              (item) => item != ProfileArtwork.featherySteps,
            )) {
              expect(
                find.byKey(ValueKey('profile-vector-icon:${artwork.name}')),
                findsNWidgets(
                  artwork == ProfileArtwork.alchemy ||
                          artwork == ProfileArtwork.processing
                      ? 2
                      : 1,
                ),
              );
            }
            expect(tester.takeException(), isNull);
            final output = Platform.environment['BSL_PROFILE_CAPTURE_DIR'];
            if (output != null && output.isNotEmpty) {
              final suffix = scale == 1 ? '' : '-${(scale * 100).round()}';
              final filename =
                  '$output/profile-${spec.id}-${width.toInt()}$suffix';
              await _saveCapture(tester, '$filename.png');
              // At enlarged text sizes the actual profile intentionally scrolls.
              // Capture the AFK result separately rather than shrinking its text
              // or claiming the first viewport verifies off-screen controls.
              await Scrollable.ensureVisible(
                tester.element(
                  find.byKey(const ValueKey('data-afk-load-card')),
                ),
                alignment: .08,
                duration: Duration.zero,
              );
              await tester.pumpAndSettle();
              await _precacheProfileImages(tester);
              expect(tester.takeException(), isNull);
              await _saveCapture(tester, '$filename-afk.png');
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

Future<void> _precacheProfileImages(WidgetTester tester) async {
  final images = find.byType(Image);
  await tester.runAsync(() async {
    await Future.wait([
      for (final element in images.evaluate())
        precacheImage((element.widget as Image).image, element),
    ]);
  });
  await tester.pumpAndSettle();
}

Future<void> _saveCapture(WidgetTester tester, String path) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(_captureRoot),
  );
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 1);
    try {
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      final file = File(path);
      await file.parent.create(recursive: true);
      await file.writeAsBytes(bytes!.buffer.asUint8List());
    } finally {
      image.dispose();
    }
  });
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
