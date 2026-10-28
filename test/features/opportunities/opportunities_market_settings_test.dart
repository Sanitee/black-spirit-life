import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:bdo_craft_planner_flutter/data/catalog/catalog_repository.dart';
import 'package:bdo_craft_planner_flutter/domain/models/craft_mode.dart';
import 'package:bdo_craft_planner_flutter/domain/state/planner_state.dart';
import 'package:bdo_craft_planner_flutter/features/data/market_bonus_icon.dart';
import 'package:bdo_craft_planner_flutter/features/opportunities/opportunities_controller.dart';
import 'package:bdo_craft_planner_flutter/features/opportunities/opportunities_workspace.dart';
import 'package:bdo_craft_planner_flutter/visual/foundations/application_theme.dart';
import 'package:bdo_craft_planner_flutter/visual/visual.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/application_test_harness.dart';

void _glassTestWidgets(
  String description,
  Future<void> Function(WidgetTester) callback,
) => testWidgets(description, (tester) async {
  final previous = debugDisableShadows;
  debugDisableShadows = false;
  try {
    await callback(tester);
  } finally {
    debugDisableShadows = previous;
  }
});

void main() {
  setUpAll(_loadFonts);

  for (final scenario in [
    (name: 'normal', size: const Size(1280, 820), scale: 1.0),
    (name: 'compact', size: const Size(760, 620), scale: 1.0),
    (name: 'text200', size: const Size(1000, 1000), scale: 2.0),
  ]) {
    _glassTestWidgets(
      'Market settings ${scenario.name} stays readable and shared',
      (tester) async {
        configureApplicationTestSurface(
          tester,
          scenario.size,
          textScaleFactor: scenario.scale,
        );
        final fixture = (await tester.runAsync(_Fixture.create))!;
        final app = fixture.harness.bundle.controller;
        final modes = {
          for (final mode in CraftMode.values)
            mode: app.documentSnapshot.forMode(mode),
        };
        await tester.pumpWidget(
          RepaintBoundary(
            key: const ValueKey('market-settings-capture'),
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              home: Scaffold(
                body: OpportunitiesWorkspace(controller: fixture.controller),
              ),
            ),
          ),
        );
        await _settle(tester);
        await tester.ensureVisible(find.text('Market · EU'));
        await tester.tap(find.text('Market · EU'));
        await _settle(tester);

        expect(find.text('Market settings'), findsOneWidget);
        expect(find.text('Region'), findsOneWidget);
        expect(find.byType(MarketBonusIcon), findsNWidgets(2));
        expect(
          tester
              .widgetList<MarketBonusIcon>(find.byType(MarketBonusIcon))
              .map((icon) => icon.artwork),
          [MarketBonusArtwork.valuePack, MarketBonusArtwork.richMerchantsRing],
        );
        expect(
          find.text('Shared with the Planner. NPC sales have no market tax.'),
          findsNothing,
        );
        expect(find.text('65% of each market sale'), findsOneWidget);
        expect(find.text('Market tax · 35%'), findsOneWidget);
        final content = tester.getRect(
          find.byKey(const ValueKey('market-settings-content')),
        );
        expect(content.width, lessThanOrEqualTo(520));

        for (final label in ['Value Pack', 'Rich Merchant’s Ring']) {
          await tester.ensureVisible(find.text(label));
          await tester.tap(find.text(label));
          await _settle(tester);
        }
        expect(app.marketTax.value.valuePack, isTrue);
        expect(app.marketTax.value.merchantRing, isTrue);
        expect(find.text('87,75% of each market sale'), findsOneWidget);
        final fame = find.descendant(
          of: find.byKey(const ValueKey('Family Fame %')),
          matching: find.byType(TextField),
        );
        await tester.ensureVisible(fame);
        await tester.enterText(fame, '1.5');
        await _settle(tester);
        expect(app.marketTax.value.familyFameBonus, .015);
        expect(find.text('88,725% of each market sale'), findsOneWidget);
        expect(find.text('Market tax · 11,275%'), findsOneWidget);

        await tester.enterText(fame, '2');
        await _settle(tester);
        expect(app.marketTax.value.familyFameBonus, .015);
        expect(find.text('Use 0–1,5'), findsOneWidget);
        await tester.enterText(fame, '1.5');
        await tester.testTextInput.receiveAction(TextInputAction.done);
        FocusManager.instance.primaryFocus?.unfocus();
        await _settle(tester);

        await tester.ensureVisible(find.text('NA'));
        await tester.tap(find.text('NA'));
        await _settle(tester);
        expect(fixture.controller.preferences.region, 'na');
        expect(app.marketTax.value.enabled, isFalse);
        expect(app.marketTax.value.extensions['preserve'], 'yes');
        for (final mode in CraftMode.values) {
          expect(app.documentSnapshot.forMode(mode), same(modes[mode]));
        }
        expect(fixture.requests, 0);
        expect(tester.takeException(), isNull);

        final output = Platform.environment['MARKET_SETTINGS_CAPTURE_DIR'];
        if (output != null) {
          await _capture(
            tester,
            '$output/market-settings-${scenario.name}.png',
          );
        }
        await tester.pumpWidget(const SizedBox.shrink());
        await _finish(tester, fixture.dispose());
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final background in [
    'sakura-night-garden',
    'illuminated-ledger',
    'plain-cobalt',
  ]) {
    for (final scale in [1.0, 2.0]) {
      _glassTestWidgets(
        'Family Fame label stays outside the field in $background at $scale',
        (tester) async {
          configureApplicationTestSurface(
            tester,
            scale == 1 ? const Size(1280, 820) : const Size(1000, 1000),
            textScaleFactor: scale,
          );
          final fixture = (await tester.runAsync(
            () => _Fixture.create(backgroundId: background),
          ))!;
          try {
            await tester.pumpWidget(
              RepaintBoundary(
                key: const ValueKey('market-settings-capture'),
                child: MaterialApp(
                  debugShowCheckedModeBanner: false,
                  home: ThemeSpecScope(
                    spec: applicationThemeForAppearance(
                      fixture.controller.modeController.state.value.appearance,
                    ),
                    child: Scaffold(
                      body: OpportunitiesWorkspace(
                        controller: fixture.controller,
                      ),
                    ),
                  ),
                ),
              ),
            );
            await _settle(tester);
            await tester.ensureVisible(find.text('Market · EU'));
            await tester.tap(find.text('Market · EU'));
            await _settle(tester);
            final fame = find.descendant(
              of: find.byKey(const ValueKey('Family Fame %')),
              matching: find.byType(TextField),
            );
            await tester.ensureVisible(fame);
            await _settle(tester);
            void expectSeparated() {
              final label = tester.getRect(find.text('Family Fame %'));
              final field = tester.getRect(fame);
              expect(
                tester.widget<TextField>(fame).decoration!.labelText,
                isNull,
              );
              expect(label.bottom + 5, lessThanOrEqualTo(field.top + .01));
              expect(label.left, greaterThanOrEqualTo(field.left));
              expect(label.right, lessThanOrEqualTo(field.right));
              expect(field.height, greaterThanOrEqualTo(42));
              expect(tester.takeException(), isNull);
            }

            expectSeparated();
            final idleRect = tester.getRect(fame);
            final mouse = await tester.createGesture(
              kind: PointerDeviceKind.mouse,
            );
            await mouse.addPointer(location: Offset.zero);
            await mouse.moveTo(tester.getCenter(fame));
            await tester.pump(const Duration(milliseconds: 180));
            expectSeparated();
            expect(tester.getRect(fame), idleRect);
            final output = Platform.environment['MARKET_SETTINGS_CAPTURE_DIR'];
            if (output != null) {
              await _capture(
                tester,
                '$output/family-fame-$background-text${(scale * 100).round()}-hover.png',
              );
            }

            final focus = tester.widget<TextField>(fame).focusNode!;
            for (var step = 0; step < 20 && !focus.hasFocus; step++) {
              await tester.sendKeyEvent(LogicalKeyboardKey.tab);
              await tester.pump();
            }
            expect(focus.hasFocus, isTrue);
            await tester.pump(const Duration(milliseconds: 180));
            expectSeparated();
            expect(tester.getRect(fame), idleRect);
            await tester.enterText(fame, '1.5');
            await _settle(tester);
            expectSeparated();
            expect(
              fixture.harness.bundle.controller.marketTax.value.familyFameBonus,
              .015,
            );
            if (output != null) {
              await _capture(
                tester,
                '$output/family-fame-$background-text${(scale * 100).round()}-focused.png',
              );
            }
            await tester.enterText(fame, '2');
            await _settle(tester);
            expect(find.text('Use 0–1,5'), findsOneWidget);
            expectSeparated();
            FocusManager.instance.primaryFocus?.unfocus();
            await _settle(tester);
            expect(tester.widget<TextField>(fame).controller!.text, '1.5');
            expect(find.text('Use 0–1,5'), findsNothing);
            expect(fixture.requests, 0);
            await mouse.removePointer();
          } finally {
            await tester.pumpWidget(const SizedBox.shrink());
            await _finish(tester, fixture.dispose());
          }
        },
      );
    }
  }
}

final class _Fixture {
  _Fixture(this.harness, this.controller, this.requestCount);
  final ApplicationTestHarness harness;
  final OpportunitiesController controller;
  final int Function() requestCount;
  int get requests => requestCount();

  static Future<_Fixture> create({String backgroundId = 'plain-cobalt'}) async {
    final harness = await ApplicationTestHarness.create(
      backgroundId: backgroundId,
    );
    harness.bundle.controller.updateDocument(
      (state) => state.copyWith(
        marketTax: MarketTax(enabled: false, extensions: {'preserve': 'yes'}),
      ),
    );
    var requests = 0;
    final controller = OpportunitiesController(
      appController: harness.bundle.controller,
      catalog: CatalogRepository(harness.bundle.catalog),
      directory: harness.temporaryDirectory,
      clock: () => DateTime.utc(2026, 9, 11, 15),
      serviceFactory: (_) {
        requests++;
        throw StateError('Market settings must not start a market request');
      },
    );
    await controller.ready;
    await controller.calculationSettled;
    controller.change((preferences) => preferences.section = 'exchanges');
    return _Fixture(harness, controller, () => requests);
  }

  Future<void> dispose() async {
    await controller.flush();
    controller.dispose();
    await harness.dispose();
  }
}

Future<void> _settle(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 400));
  for (final element in find.byType(Image).evaluate().toList()) {
    await tester.runAsync(
      () => precacheImage((element.widget as Image).image, element),
    );
  }
  await tester.pump(const Duration(milliseconds: 400));
}

Future<void> _finish(WidgetTester tester, Future<void> work) async {
  var complete = false;
  Object? error;
  unawaited(
    work.then(
      (_) => complete = true,
      onError: (Object value) {
        error = value;
        complete = true;
      },
    ),
  );
  for (var i = 0; i < 500 && !complete; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump(const Duration(milliseconds: 20));
  }
  expect(complete, isTrue);
  if (error != null) throw error!;
}

Future<void> _capture(WidgetTester tester, String path) async {
  await tester.pump();
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(const ValueKey('market-settings-capture')),
  );
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 1);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    final file = File(path);
    await file.parent.create(recursive: true);
    await file.writeAsBytes(data!.buffer.asUint8List());
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
