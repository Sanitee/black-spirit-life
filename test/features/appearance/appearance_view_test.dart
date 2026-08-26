import 'dart:ui' as ui;

import 'package:bdo_craft_planner_flutter/app/state/planner_application_controller.dart';
import 'package:bdo_craft_planner_flutter/app/window/app_title_bar.dart';
import 'package:bdo_craft_planner_flutter/domain/models/catalog_models.dart';
import 'package:bdo_craft_planner_flutter/domain/models/craft_mode.dart';
import 'package:bdo_craft_planner_flutter/domain/state/planner_state.dart';
import 'package:bdo_craft_planner_flutter/features/appearance/appearance_view.dart';
import 'package:bdo_craft_planner_flutter/features/planner/planner_view.dart';
import 'package:bdo_craft_planner_flutter/features/shell/workspace_shell.dart';
import 'package:bdo_craft_planner_flutter/shared/overlays/anchored_popover.dart';
import 'package:bdo_craft_planner_flutter/visual/visual.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('reference layout exposes only themes and compact motion', (
    tester,
  ) async {
    final controller = _controller();
    await _pump(tester, controller, const Size(1200, 752));

    expect(find.text('Themes'), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('appearance-motion-controls')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey<String>('A02:standard')), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('A02')), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('A02:sakura-night-garden')),
      findsOneWidget,
    );
    expect(find.text('Atmospheric Backdrops'), findsNothing);
    expect(find.text('Plain Backdrops'), findsNothing);
    expect(find.text('Particles'), findsNothing);
    expect(find.text('Button Effects'), findsNothing);
    expect(find.byKey(const ValueKey<String>('A12')), findsNothing);
    expect(find.byKey(const ValueKey<String>('A23')), findsNothing);
    expect(find.byKey(const ValueKey<String>('A09')), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('A09:speed')), findsOneWidget);

    await controller.dispose();
  });

  testWidgets('theme cards form a proportional responsive grid', (
    tester,
  ) async {
    final controller = _controller();
    await _pump(tester, controller, const Size(1200, 752));

    final standard = tester.getRect(
      find.byKey(const ValueKey<String>('A02:standard')),
    );
    final ledger = tester.getRect(find.byKey(const ValueKey<String>('A02')));
    final sakura = tester.getRect(
      find.byKey(const ValueKey<String>('A02:sakura-night-garden')),
    );
    expect(ledger.top, closeTo(sakura.top, .01));
    expect(standard.top, closeTo(sakura.top, .01));
    expect(ledger.left, greaterThan(sakura.right));
    expect(standard.left, greaterThan(ledger.right));
    for (final card in <Rect>[standard, ledger, sakura]) {
      expect(card.width / card.height, closeTo(75 / 47, .01));
    }
    expect(tester.takeException(), isNull);

    await controller.dispose();
  });

  testWidgets(
    'transition controls form a compact aligned pair in every theme',
    (tester) async {
      for (final spec in <ThemeSpec>[
        RetainedThemeRegistry.standard,
        RetainedThemeRegistry.illuminatedLedger,
        RetainedThemeRegistry.sakuraNightGarden,
      ]) {
        for (final size in const <Size>[Size(1200, 752), Size(1500, 940)]) {
          final controller = _controller();
          await _pump(tester, controller, size, spec: spec);

          final transitionHeading = tester.getRect(find.text('TAB TRANSITION'));
          final speedHeading = tester.getRect(find.text('TRANSITION SPEED'));
          final transition = tester.getRect(
            find.byKey(const ValueKey<String>('A09')),
          );
          final speed = tester.getRect(
            find.byKey(const ValueKey<String>('A09:speed')),
          );

          expect(transition.left, closeTo(transitionHeading.left, .01));
          expect(speed.left, closeTo(speedHeading.left, .01));
          expect(transition.top, greaterThan(transitionHeading.bottom));
          expect(speed.top, closeTo(transition.top, .01));
          expect(transition.width, 128);
          expect(speed.width, 144);
          expect(speed.left - transition.right, 12);
          expect(tester.takeException(), isNull);

          await controller.dispose();
        }
      }
    },
  );

  testWidgets(
    '200% text stacks complete transition controls without clipping',
    (tester) async {
      for (final spec in <ThemeSpec>[
        RetainedThemeRegistry.standard,
        RetainedThemeRegistry.illuminatedLedger,
        RetainedThemeRegistry.sakuraNightGarden,
      ]) {
        final controller = _controller();
        await _pump(
          tester,
          controller,
          const Size(916, 714),
          spec: spec,
          textScaler: const TextScaler.linear(2),
        );

        final transitionField = tester.getRect(
          find.byKey(const ValueKey<String>('A09:transition-field')),
        );
        final speedField = tester.getRect(
          find.byKey(const ValueKey<String>('A09:speed-field')),
        );
        expect(speedField.top, closeTo(transitionField.top, .01));
        expect(find.text('Slide'), findsOneWidget);
        expect(find.text('Normal'), findsOneWidget);
        expect(tester.takeException(), isNull);

        await controller.dispose();
      }
    },
  );

  testWidgets('Illuminated Ledger selector stays visible without expansion', (
    tester,
  ) async {
    final controller = _controller();
    await _pump(
      tester,
      controller,
      const Size(1200, 752),
      spec: RetainedThemeRegistry.illuminatedLedger,
    );

    expect(find.byKey(const ValueKey<String>('A02')), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('A01')), findsNothing);
    expect(tester.takeException(), isNull);

    await controller.dispose();
  });

  testWidgets('theme cards render scaled production app previews', (
    tester,
  ) async {
    final controller = _controller();
    await _pump(tester, controller, const Size(1200, 752));

    final cases = <({Key previewKey, Key brandTitleKey, Type backdropType})>[
      (
        previewKey: const ValueKey<String>('sakura-theme-preview'),
        brandTitleKey: AppBrandLockup.sakuraTitleKey,
        backdropType: SakuraNightGardenBackdrop,
      ),
      (
        previewKey: const ValueKey<String>('ledger-theme-preview'),
        brandTitleKey: AppBrandLockup.ledgerTitleKey,
        backdropType: LedgerBackdrop,
      ),
      (
        previewKey: const ValueKey<String>('standard-theme-preview'),
        brandTitleKey: AppBrandLockup.standardTitleKey,
        backdropType: StandardBackdrop,
      ),
    ];

    for (final testCase in cases) {
      final preview = find.byKey(testCase.previewKey);
      expect(preview, findsOneWidget);
      expect(
        find.descendant(of: preview, matching: find.byType(AppTitleBar)),
        findsOneWidget,
      );
      expect(
        find.descendant(of: preview, matching: find.byType(AppTitleTabStrip)),
        findsOneWidget,
      );
      expect(
        find.descendant(of: preview, matching: find.byType(WorkspaceShell)),
        findsOneWidget,
      );
      expect(
        find.descendant(of: preview, matching: find.byType(PlannerView)),
        findsOneWidget,
      );
      expect(
        find.descendant(of: preview, matching: find.byType(AppBrandLockup)),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: preview,
          matching: find.byKey(testCase.brandTitleKey),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: preview,
          matching: find.byWidgetPredicate(
            (widget) => widget.runtimeType == testCase.backdropType,
          ),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: preview,
          matching: find.byWidgetPredicate(
            (widget) =>
                widget is FittedBox &&
                widget.fit == BoxFit.contain &&
                widget.alignment == Alignment.topLeft,
          ),
        ),
        findsOneWidget,
      );
      expect(
        tester.getSize(
          find.descendant(of: preview, matching: find.byType(AppTitleBar)),
        ),
        const Size(1200, 40),
      );
      expect(
        tester.getSize(
          find.descendant(of: preview, matching: find.byType(WorkspaceShell)),
        ),
        const Size(1200, 712),
      );

      for (final label in const <String>[
        'Planner',
        'Bonus Recipes',
        'Inventory',
        'Appearance',
        'Craft Profile',
      ]) {
        expect(
          find.descendant(of: preview, matching: find.text(label)),
          findsOneWidget,
        );
      }
      expect(
        find.descendant(of: preview, matching: find.text('Recipe Editor')),
        findsNothing,
      );
      expect(
        find.descendant(of: preview, matching: find.text('BDO CRAFT')),
        findsNothing,
      );
      expect(
        find.descendant(of: preview, matching: find.text('LIVE THEME PREVIEW')),
        findsNothing,
      );
      expect(
        find.descendant(of: preview, matching: find.byType(ExcludeFocus)),
        findsWidgets,
      );
    }
    expect(tester.takeException(), isNull);

    await controller.dispose();
  });

  testWidgets('theme selection and transition controls persist', (
    tester,
  ) async {
    final controller = _controller();
    await _pump(tester, controller, const Size(1200, 752));

    await tester.tap(find.byKey(const ValueKey<String>('A02')));
    await tester.pump();
    for (final mode in CraftMode.values) {
      expect(
        controller.documentSnapshot.forMode(mode).appearance.background,
        IlluminatedLedgerSpec.backgroundId,
      );
    }

    await tester.tap(find.byKey(const ValueKey<String>('A09')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Lift').last);
    await tester.pumpAndSettle();
    expect(controller.active.state.value.appearance.tabFade, isTrue);
    expect(controller.active.state.value.appearance.tabTransition, 'lift');
    await tester.tap(find.byKey(const ValueKey<String>('A09:speed')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Slow').last);
    await tester.pumpAndSettle();
    expect(controller.active.state.value.appearance.tabTransitionSpeed, 'slow');
    await tester.tap(find.byKey(const ValueKey<String>('A09')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Off').last);
    await tester.pumpAndSettle();
    expect(controller.active.state.value.appearance.tabFade, isFalse);
    expect(
      tester
          .widget<AppSelect<String>>(
            find.byKey(const ValueKey<String>('A09:speed')),
          )
          .onChanged,
      isNull,
    );
    expect(controller.active.state.value.appearance.tabTransitionSpeed, 'slow');
    await tester.tap(find.byKey(const ValueKey<String>('A09')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Slide').last);
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<AppSelect<String>>(
            find.byKey(const ValueKey<String>('A09:speed')),
          )
          .onChanged,
      isNotNull,
    );
    expect(controller.active.state.value.appearance.tabTransitionSpeed, 'slow');
    await controller.dispose();
  });

  testWidgets('advanced backdrop particle and button controls stay hidden', (
    tester,
  ) async {
    final controller = _controller();
    await _pump(tester, controller, const Size(1500, 940));

    for (final key in const <String>[
      'A03',
      'A04:greenhouse',
      'A05',
      'A10',
      'A11:embers',
      'A12',
      'A18:density',
      'A21',
      'A22:quiet',
      'A23',
      'A26',
    ]) {
      expect(find.byKey(ValueKey<String>(key)), findsNothing);
    }
    expect(find.byKey(const ValueKey<String>('A09')), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('A09:speed')), findsOneWidget);

    await controller.dispose();
  });

  testWidgets('HueWheel paints dark, warm, and selected-color layers', (
    tester,
  ) async {
    final boundaryKey = GlobalKey();
    const spec = RetainedThemeRegistry.standard;
    await tester.pumpWidget(
      MaterialApp(
        theme: spec.materialTheme(),
        home: ThemeSpecScope(
          spec: spec,
          child: Center(
            child: RepaintBoundary(
              key: boundaryKey,
              child: HueWheel(
                hue: 0,
                semanticLabel: 'Test hue wheel',
                onChanged: (_) {},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    final boundary =
        boundaryKey.currentContext!.findRenderObject()!
            as RenderRepaintBoundary;
    final bytes = (await tester.runAsync<Uint8List>(() async {
      final image = await boundary.toImage();
      try {
        final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
        return data!.buffer.asUint8List();
      } finally {
        image.dispose();
      }
    }))!;
    expect(
      _containsPixel(bytes, (r, g, b, a) => a > 220 && r < 45 && g < 45),
      isTrue,
    );
    expect(
      _containsPixel(
        bytes,
        (r, g, b, a) => a > 220 && r > 190 && g > 115 && b < 125,
      ),
      isTrue,
    );
    expect(
      _containsPixel(
        bytes,
        (r, g, b, a) => a > 220 && r > 210 && g < 80 && b < 80,
      ),
      isTrue,
    );
  });
}

Future<void> _pump(
  WidgetTester tester,
  PlannerApplicationController controller,
  Size size, {
  ThemeSpec spec = RetainedThemeRegistry.standard,
  TextScaler textScaler = TextScaler.noScaling,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    AppOverlayCoordinatorHost(
      child: MaterialApp(
        theme: spec.materialTheme(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: textScaler),
          child: child!,
        ),
        home: ThemeSpecScope(
          spec: spec,
          child: Scaffold(body: AppearanceView(controller: controller)),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

PlannerApplicationController _controller() => PlannerApplicationController(
  catalog: _catalog(),
  initialState: _document(),
  saveState: (state) async => state,
  saveDebounce: Duration.zero,
);

PlannerState _document() => PlannerState(
  applicationVersion: 'test',
  lastSuccessfulWriteUtc: DateTime.utc(2026),
  alchemy: _mode(CraftMode.alchemy),
  cooking: _mode(CraftMode.cooking),
  processing: _mode(CraftMode.processing),
  processingYields: const {'defaultYield': 2.5},
  marketTax: MarketTax(),
);

ModeState _mode(CraftMode mode) => ModeState(
  target: 'Recipe',
  bonusTarget: 'Recipe',
  market: MarketState(),
  appearance: AppearanceSettings.defaultsFor(mode),
);

CatalogSnapshot _catalog() => CatalogSnapshot(
  sourceSha256: 'fixture',
  sourceByteCount: 1,
  alchemy: _catalogMode(CraftMode.alchemy),
  cooking: _catalogMode(CraftMode.cooking),
  processing: _catalogMode(CraftMode.processing),
  supportingData: const {},
  collisions: const [],
);

ModeCatalog _catalogMode(CraftMode mode) => ModeCatalog(
  mode: mode,
  items: {'Recipe': _recipe(mode)},
  iconDataUris: mode == CraftMode.alchemy
      ? const {'Purified Water': _tinyIconDataUri}
      : const {},
  defaults: const {},
  metadata: const {},
  searchAliases: const {},
);

Recipe _recipe(CraftMode mode) => Recipe(
  name: 'Recipe',
  type: mode.key,
  baseOutput: 1,
  group: null,
  method: null,
  ingredients: [
    Ingredient(
      name: 'Base',
      quantity: 1,
      options: const [],
      substituteGroup: null,
      substituteRatios: const {},
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

bool _containsPixel(
  Uint8List bytes,
  bool Function(int red, int green, int blue, int alpha) matches,
) {
  for (var index = 0; index < bytes.length; index += 4) {
    if (matches(
      bytes[index],
      bytes[index + 1],
      bytes[index + 2],
      bytes[index + 3],
    )) {
      return true;
    }
  }
  return false;
}

const _tinyIconDataUri =
    'data:image/png;base64,'
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8A'
    'AQUBAScY42YAAAAASUVORK5CYII=';
