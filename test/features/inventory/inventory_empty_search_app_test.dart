import 'dart:io';
import 'dart:ui' as ui;
import 'package:bdo_craft_planner_flutter/app/app.dart';
import 'package:bdo_craft_planner_flutter/features/inventory/inventory.dart';
import 'package:bdo_craft_planner_flutter/features/shell/shell.dart';
import 'package:bdo_craft_planner_flutter/visual/visual.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import '../../support/application_test_harness.dart';

void main() {
  setUpAll(() async {
    if (!Platform.isWindows) return;
    final windows = Platform.environment['WINDIR'] ?? r'C:\Windows';
    var sdk = File(Platform.resolvedExecutable).parent;
    while (!Directory(
      '${sdk.path}/bin/cache/artifacts/material_fonts',
    ).existsSync()) {
      if (sdk.parent.path == sdk.path) {
        throw StateError('Flutter fonts not found');
      }
      sdk = sdk.parent;
    }
    for (final entry in {
      'Segoe UI': ['$windows/Fonts/segoeui.ttf', '$windows/Fonts/seguisb.ttf'],
      'Georgia': ['$windows/Fonts/georgia.ttf', '$windows/Fonts/georgiab.ttf'],
      'Roboto': [
        '${sdk.path}/bin/cache/artifacts/material_fonts/roboto-regular.ttf',
      ],
      'MaterialIcons': [
        '${sdk.path}/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
      ],
    }.entries) {
      final loader = FontLoader(entry.key);
      for (final path in entry.value) {
        loader.addFont(File(path).readAsBytes().then(ByteData.sublistView));
      }
      await loader.load();
    }
  });
  for (final spec in RetainedThemeRegistry.themes) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('actual inventory empty search ${spec.id} $scale', (
        tester,
      ) async {
        configureApplicationTestSurface(
          tester,
          scale == 1 ? const Size(1200, 780) : const Size(1600, 1100),
          textScaleFactor: scale,
        );
        final original = (await tester.runAsync(
          () => ApplicationTestHarness.create(
            backgroundId: spec.isStandard ? 'greenhouse' : spec.id,
          ),
        ))!;
        final harness = original.rebindControllerInCurrentZone();
        await tester.runAsync(original.disposeControllerOnly);
        const key = ValueKey('empty-search-app-capture');
        try {
          await tester.pumpWidget(
            RepaintBoundary(
              key: key,
              child: BdoCraftPlannerApp(
                enableOpportunityAutoCheck: false,
                applicationFuture: Future.value(harness.bundle),
                marketGateway: const EmptyMarketGateway(),
              ),
            ),
          );
          await tester.pumpAndSettle();
          await tester.tap(find.byKey(ShellDestination.inventory.actionKey));
          await tester.pumpAndSettle();
          await tester.enterText(
            find.byKey(InventoryActionKeys.i01),
            'Sunrise Herbb',
          );
          await tester.pump(const Duration(milliseconds: 250));
          FocusManager.instance.primaryFocus?.unfocus();
          await tester.runAsync(() async {
            await Future.wait([
              for (final e in find.byType(Image).evaluate())
                precacheImage((e.widget as Image).image, e),
            ]);
          });
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          final directory =
              Platform.environment['BSL_READABLE_DETAILS_CAPTURE_DIR'];
          if (directory != null) {
            final boundary = tester.renderObject<RenderRepaintBoundary>(
              find.byKey(key),
            );
            await tester.runAsync(() async {
              await Directory(directory).create(recursive: true);
              final image = await boundary.toImage();
              final bytes = await image.toByteData(
                format: ui.ImageByteFormat.png,
              );
              await File(
                '$directory/inventory-${spec.id}-$scale.png',
              ).writeAsBytes(bytes!.buffer.asUint8List());
              image.dispose();
            });
          }
          expect(find.text('No matching items'), findsOneWidget);
          await tester.tap(find.byKey(InventoryActionKeys.clearSearchResults));
          await tester.pumpAndSettle();
          expect(find.text('No matching items'), findsNothing);
          expect(find.text('Sunrise Herbb'), findsNothing);
          expect(tester.takeException(), isNull);
        } finally {
          await tester.pumpWidget(const SizedBox());
          await tester.runAsync(harness.dispose);
        }
      });
    }
  }
}
