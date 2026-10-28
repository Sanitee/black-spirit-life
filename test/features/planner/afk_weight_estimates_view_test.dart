import 'dart:io';
import 'dart:ui' as ui;

import 'package:bdo_craft_planner_flutter/app/state/planner_application_controller.dart';
import 'package:bdo_craft_planner_flutter/data/catalog/bundled_catalog_parser.dart';
import 'package:bdo_craft_planner_flutter/domain/models/catalog_models.dart';
import 'package:bdo_craft_planner_flutter/domain/models/craft_mode.dart';
import 'package:bdo_craft_planner_flutter/domain/state/planner_state.dart';
import 'package:bdo_craft_planner_flutter/features/planner/planner.dart';
import 'package:bdo_craft_planner_flutter/shared/overlays/anchored_popover.dart';
import 'package:bdo_craft_planner_flutter/visual/visual.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'planner_test_fixture.dart';

late CatalogSnapshot catalog;

void main() {
  setUpAll(() async {
    catalog = const BundledCatalogParser().parse(
      File('assets/data/app-data.json').readAsStringSync(),
    );
    for (final entry in {
      'Segoe UI': [
        'C:/Windows/Fonts/segoeui.ttf',
        'C:/Windows/Fonts/seguisb.ttf',
      ],
      'Georgia': [
        'C:/Windows/Fonts/georgia.ttf',
        'C:/Windows/Fonts/georgiab.ttf',
      ],
      'MaterialIcons': [
        'D:/Tools/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
      ],
    }.entries) {
      final loader = FontLoader(entry.key);
      for (final path in entry.value) {
        if (File(path).existsSync()) {
          loader.addFont(File(path).readAsBytes().then(ByteData.sublistView));
        }
      }
      await loader.load();
    }
  });

  for (final mode in [
    CraftMode.processing,
    CraftMode.cooking,
    CraftMode.alchemy,
  ]) {
    testWidgets(
      'real catalog ${mode.key} estimate and reserve, no personal profile',
      (tester) async {
        final controller = await pumpPlan(tester, mode: mode);
        await tester.tap(
          find.byKey(const ValueKey('planner-afk-mode-maximum')),
        );
        await tester.pumpAndSettle();
        expect(find.text('Estimated load'), findsOneWidget);
        expect(find.text('Expected finish'), findsOneWidget);
        expect(value(tester, 'planner-afk-reserved-weight'), '100 LT');
        expect(value(tester, 'planner-afk-expected-weight'), startsWith('≈ '));
        if (mode == CraftMode.processing) {
          expect(value(tester, 'planner-afk-total-weight'), '1.929,1 LT');
          expect(value(tester, 'planner-afk-safe-attempts'), '19.291');
          expect(value(tester, 'planner-afk-expected-weight'), '≈ 4.822,8 LT');
          expect(
            value(tester, 'planner-afk-estimate-note'),
            startsWith('Estimate'),
          );
        } else {
          expect(
            value(tester, 'planner-afk-estimate-note'),
            startsWith('Conservative'),
          );
        }
        final inventory = controller.active.state.value.inventory;
        await capture(tester, mode.key);
        await tester.tap(find.byKey(const ValueKey('planner-afk-mode-needed')));
        await tester.pumpAndSettle();
        expect(value(tester, 'planner-afk-reserved-weight'), '100 LT');
        await tester.tap(find.byKey(const ValueKey('planner-afk-close')));
        await tester.pumpAndSettle();
        expect(controller.active.state.value.inventory, inventory);
        expect(tester.takeException(), isNull);
        await controller.dispose();
      },
    );
  }

  for (final theme in RetainedThemeRegistry.themes) {
    for (final scale in [1.0, 1.5, 2.0]) {
      testWidgets('AFK summary fits ${theme.id} at 1200x752 / $scale', (
        tester,
      ) async {
        final controller = await pumpPlan(
          tester,
          mode: CraftMode.processing,
          size: const Size(1200, 752),
          scale: scale,
          theme: theme,
        );
        await tester.tap(
          find.byKey(const ValueKey('planner-afk-mode-maximum')),
        );
        await tester.pumpAndSettle();
        final panel = tester.getRect(
          find.byKey(const ValueKey('planner-afk-split')),
        );
        for (final key in [
          'planner-afk-total-weight',
          'planner-afk-expected-weight',
          'planner-afk-reserved-weight',
          'planner-afk-close',
          'planner-afk-complete-round',
        ]) {
          final element = tester.element(find.byKey(ValueKey(key)));
          // Scroll only the popup's own viewport; scrolling its underlying
          // planner would correctly dismiss the now-detached anchored popup.
          final scrollable = Scrollable.maybeOf(element);
          if (scrollable != null) {
            await scrollable.position.ensureVisible(
              element.findRenderObject()!,
            );
          }
          await tester.pumpAndSettle();
          final rect = tester.getRect(find.byKey(ValueKey(key)));
          expect(panel.inflate(1).contains(rect.topLeft), isTrue, reason: key);
          expect(
            panel.inflate(1).contains(rect.bottomRight),
            isTrue,
            reason: key,
          );
        }
        expect(tester.takeException(), isNull);
        await controller.dispose();
      });
    }
  }
}

String? value(WidgetTester tester, String key) =>
    tester.widget<Text>(find.byKey(ValueKey(key))).data;

Future<PlannerApplicationController> pumpPlan(
  WidgetTester tester, {
  required CraftMode mode,
  Size size = const Size(1500, 940),
  double scale = 1,
  ThemeSpec? theme,
}) async {
  await setPlannerTestSize(tester, size);
  final spec = theme ?? SakuraNightGardenSpec.theme;
  ModeState state(CraftMode skill, String target) => ModeState(
    target: target,
    want: 100,
    bonusTarget: '',
    cookingMastery: 1900,
    alchemyMastery: 1900,
    processingMastery: 1767,
    useMassProcessing: false,
    market: MarketState(),
    appearance: AppearanceSettings.defaultsFor(skill),
  );
  final controller = PlannerApplicationController(
    catalog: catalog,
    initialState: PlannerState(
      applicationVersion: 'test',
      lastSuccessfulWriteUtc: DateTime.utc(2026, 10, 25),
      activeMode: mode,
      alchemy: state(CraftMode.alchemy, 'Clear Liquid Reagent'),
      cooking: state(CraftMode.cooking, 'Beer'),
      processing: state(CraftMode.processing, 'Corn Flour'),
      processingYields: const {},
      marketTax: MarketTax(),
      showDeleteTools: false,
      afkWeightProfile: AfkWeightProfile(
        maximumWeightLt: 4024,
        currentCarriedWeightLt: 107.1,
        safetyBufferLt: 100,
        featheryStepsLevel: 5,
      ),
    ),
    saveState: (document) async => document,
    saveDebounce: Duration.zero,
  );
  await tester.pumpWidget(
    RepaintBoundary(
      key: const ValueKey('afk-capture'),
      child: AppOverlayCoordinatorHost(
        child: MaterialApp(
          theme: spec.materialTheme(),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(scale)),
            child: child!,
          ),
          home: ThemeSpecScope(
            spec: spec,
            child: Scaffold(
              body: PlannerView(
                controller: controller.active,
                externalActions: PlannerExternalActions(
                  openRecipeBook: (_) {},
                  copyName: (_) async {},
                  checkPrices: (_) async =>
                      throw StateError('No network in this test'),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  final target = controller.active.state.value.target;
  final button = find.byKey(ValueKey('planner-afk-load:${mode.key}:$target'));
  await tester.ensureVisible(button);
  await tester.tap(button);
  await tester.pumpAndSettle();
  return controller;
}

Future<void> capture(WidgetTester tester, String name) async {
  final folder = Platform.environment['BSL_AFK_CAPTURE_DIR'];
  if (folder == null) return;
  for (final element in find.byType(Image).evaluate()) {
    await tester.runAsync(
      () => precacheImage((element.widget as Image).image, element),
    );
  }
  await tester.pumpAndSettle();
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(const ValueKey('afk-capture')),
  );
  final rect = tester
      .getRect(find.byKey(const ValueKey('planner-afk-split')))
      .shift(-tester.getTopLeft(find.byKey(const ValueKey('afk-capture'))));
  final layer = boundary.debugLayer! as OffsetLayer;
  await tester.runAsync(() async {
    await Directory(folder).create(recursive: true);
    final image = await layer.toImage(rect.inflate(4), pixelRatio: 1);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    await File('$folder/$name.png').writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  });
}
