import 'dart:io';
import 'dart:ui' as ui;

import 'package:bdo_craft_planner_flutter/domain/models/craft_mode.dart';
import 'package:bdo_craft_planner_flutter/features/planner/planner.dart';
import 'package:bdo_craft_planner_flutter/shared/overlays/anchored_popover.dart';
import 'package:bdo_craft_planner_flutter/visual/foundations/theme_spec.dart';
import 'package:bdo_craft_planner_flutter/visual/standard/standard_spec.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/application_test_harness.dart';

const _capture = ValueKey('planner-motion-capture');

void main() {
  setUpAll(_loadFonts);
  for (final scale in [1.0, 2.0]) {
    testWidgets(
      'real Beer formula motion at ${(scale * 100).round()} percent',
      (tester) async {
        tester.view
          ..devicePixelRatio = 1
          ..physicalSize = const Size(1500, 940);
        addTearDown(tester.view.reset);
        final original = (await tester.runAsync(
          () => ApplicationTestHarness.create(activeMode: CraftMode.cooking),
        ))!;
        final harness = original.rebindControllerInCurrentZone();
        await tester.runAsync(original.disposeControllerOnly);
        final controller = harness.bundle.controller.active;
        expect(controller.selectTarget('Beer'), isTrue);
        await tester.pumpWidget(
          RepaintBoundary(
            key: _capture,
            child: AppOverlayCoordinatorHost(
              child: MaterialApp(
                debugShowCheckedModeBanner: false,
                theme: StandardSpec.theme.materialTheme(),
                builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(
                    context,
                  ).copyWith(textScaler: TextScaler.linear(scale)),
                  child: child!,
                ),
                home: ThemeSpecScope(
                  spec: StandardSpec.theme,
                  child: Scaffold(
                    body: Padding(
                      padding: const EdgeInsets.all(12),
                      child: PlannerView(
                        controller: controller,
                        externalActions: PlannerExternalActions(
                          openRecipeBook: (_) {},
                          copyName: (_) async {},
                          checkPrices: (_) =>
                              throw StateError('No network in motion render'),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await _settle(tester);
        final step = controller.plan.value.steps.firstWhere(
          (step) => step.name == 'Beer',
        );
        final ingredient = step.ingredients.firstWhere(
          (ingredient) => ingredient.options.length > 1,
        );
        final anchor = find.byKey(
          PlannerActionKeys.row(
            'P12',
            'step:${ingredient.parentName}:${ingredient.substituteGroup}',
          ),
        );
        await tester.ensureVisible(anchor);
        await tester.tap(anchor);
        await tester.pump();
        final alternative = ingredient.options.firstWhere(
          (name) => name != ingredient.baseName,
        );
        final option = find.byKey(PlannerActionKeys.row('P13', alternative));
        await tester.ensureVisible(option);
        await _settle(tester);
        await tester.tap(option);
        expect(
          controller.state.value.substituteChoices.values,
          contains(alternative),
        );
        await tester.pump();
        await _captureImage(
          tester,
          'planner-substitute-${(scale * 100).round()}',
        );
        await tester.pumpAndSettle();
        final complete = find.byKey(PlannerActionKeys.row('P08', 'Beer'));
        await tester.ensureVisible(complete);
        await tester.tap(complete);
        await tester.pump();
        expect(
          find.byKey(const ValueKey('planner-completion-feedback:Beer')),
          findsOneWidget,
        );
        await _captureImage(
          tester,
          'planner-completed-${(scale * 100).round()}',
        );
        await tester.pump(const Duration(milliseconds: 100));
        await _captureImage(
          tester,
          'planner-collapse-${(scale * 100).round()}',
        );
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('planner-completion-feedback:Beer')),
          findsNothing,
        );
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        await harness.disposeControllerOnly();
        await tester.runAsync(
          () => harness.temporaryDirectory.delete(recursive: true),
        );
      },
    );
  }
}

Future<void> _settle(WidgetTester tester) async {
  await tester.pumpAndSettle();
  await tester.runAsync(() async {
    final futures = <Future<void>>[];
    for (final element in find.byType(Image).evaluate()) {
      final widget = element.widget as Image;
      futures.add(precacheImage(widget.image, element));
    }
    await Future.wait(futures);
  });
  await tester.pumpAndSettle();
}

Future<void> _captureImage(WidgetTester tester, String name) async {
  final directory = Platform.environment['PLANNER_MOTION_CAPTURE_DIR'];
  if (directory == null || directory.isEmpty) return;
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(_capture),
  );
  await tester.runAsync(() async {
    final image = await boundary.toImage();
    try {
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      await File(
        '$directory/$name.png',
      ).writeAsBytes(bytes!.buffer.asUint8List());
    } finally {
      image.dispose();
    }
  });
}

Future<void> _loadFonts() async {
  if (!Platform.isWindows) return;
  final win = Platform.environment['WINDIR'] ?? r'C:\Windows';
  var sdk = File(Platform.resolvedExecutable).parent;
  while (!Directory(
    '${sdk.path}/bin/cache/artifacts/material_fonts',
  ).existsSync()) {
    if (sdk.parent.path == sdk.path) {
      throw StateError('Flutter fonts not found');
    }
    sdk = sdk.parent;
  }
  for (final family in <String, List<String>>{
    'Georgia': ['$win/Fonts/georgia.ttf', '$win/Fonts/georgiab.ttf'],
    'Segoe UI': [
      '$win/Fonts/segoeui.ttf',
      '$win/Fonts/seguisb.ttf',
      '$win/Fonts/segoeuib.ttf',
    ],
    'Roboto': [
      '${sdk.path}/bin/cache/artifacts/material_fonts/roboto-regular.ttf',
      '${sdk.path}/bin/cache/artifacts/material_fonts/roboto-bold.ttf',
    ],
    'MaterialIcons': [
      '${sdk.path}/bin/cache/artifacts/material_fonts/materialicons-regular.otf',
    ],
  }.entries) {
    final loader = FontLoader(family.key);
    for (final path in family.value) {
      loader.addFont(File(path).readAsBytes().then(ByteData.sublistView));
    }
    await loader.load();
  }
}
