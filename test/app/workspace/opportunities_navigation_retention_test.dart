import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:bdo_craft_planner_flutter/app/window/window_host_service.dart';
import 'package:bdo_craft_planner_flutter/app/workspace/application_workspace.dart';
import 'package:bdo_craft_planner_flutter/domain/models/craft_mode.dart';
import 'package:bdo_craft_planner_flutter/features/opportunities/opportunities_controller.dart';
import 'package:bdo_craft_planner_flutter/features/opportunities/opportunities_item_actions.dart';
import 'package:bdo_craft_planner_flutter/features/opportunities/opportunities_workspace.dart';
import 'package:bdo_craft_planner_flutter/features/planner/planner_contracts.dart';
import 'package:bdo_craft_planner_flutter/features/resource_map/resource_map_workspace.dart';
import 'package:bdo_craft_planner_flutter/visual/visual.dart';
import 'package:bdo_map_core/bdo_map_core.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../../support/application_test_harness.dart';

void main() {
  setUpAll(_loadFonts);
  testWidgets('Set planner target retains the nested recipe, scroll and search', (
    tester,
  ) async {
    final fixture = await _mount(tester);
    final planner = fixture.harness.bundle.controller;
    final processing = planner.modes[CraftMode.processing]!;
    processing.commitAmount('73');
    await _openButter(tester, fixture.controller);
    final workspaceElement = tester.element(
      find.byType(OpportunitiesWorkspace),
    );
    final rootPosition = _recipePosition(tester, 'Butter');
    await tester.ensureVisible(_region('ingredient:Cream'));
    final rootOffset = rootPosition.pixels;
    await tester.tap(find.byKey(const ValueKey('ingredient-recipe-Cream')));
    await _settle(tester);
    expect(_region('opportunity-title:Cream'), findsOneWidget);
    final dialogElement = tester.element(find.byType(Dialog));
    final nestedPosition = _recipePosition(tester, 'Cream');
    expect(nestedPosition.maxScrollExtent, greaterThan(0));
    nestedPosition.jumpTo(nestedPosition.maxScrollExtent / 2);
    await tester.pump();
    final nestedOffset = nestedPosition.pixels;
    await _menu(tester, 'opportunity-title:Cream');
    expect(find.text('Set planner target'), findsOneWidget);
    await tester.tap(find.text('Set planner target'));
    await _settle(tester);
    expect(_selected(tester, 'planner'), isTrue);
    expect(planner.activeMode.value, CraftMode.processing);
    expect(processing.state.value.target, 'Cream');
    expect(processing.state.value.want, 73);
    expect(processing.state.value.view, 'plan');
    expect(find.byType(Dialog), findsNothing);
    expect(find.byType(Dialog, skipOffstage: false), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await _settle(tester);
    expect(
      find.byType(Dialog, skipOffstage: false),
      findsOneWidget,
      reason:
          'Planner keyboard actions must not close a hidden Opportunities dialog.',
    );
    expect(fixture.controller.preferences.mode, CraftMode.processing);
    expect(fixture.controller.preferences.craftSearch, 'Butter');
    await tester.tap(_tab('opportunities'));
    await _settle(tester);
    expect(
      tester.element(find.byType(OpportunitiesWorkspace)),
      same(workspaceElement),
    );
    expect(tester.element(find.byType(Dialog)), same(dialogElement));
    expect(_recipePosition(tester, 'Cream'), same(nestedPosition));
    expect(nestedPosition.pixels, closeTo(nestedOffset, .1));
    expect(
      find.byKey(const ValueKey('ingredient-recipe-trail')),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey('ingredient-recipe-back')));
    await _settle(tester);
    expect(_region('opportunity-title:Butter'), findsOneWidget);
    expect(_recipePosition(tester, 'Butter').pixels, closeTo(rootOffset, .1));
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await _settle(tester);
    expect(find.byType(Dialog), findsNothing);
    expect(_search(tester), 'Butter');
    await _dispose(tester, fixture);
  });

  testWidgets(
    'NPC map jump and direct tab switches retain the open recipe route',
    (tester) async {
      final fixture = await _mount(tester);
      await _openButter(tester, fixture.controller);
      await tester.ensureVisible(_region('ingredient:Cream'));
      await tester.tap(find.byKey(const ValueKey('ingredient-recipe-Cream')));
      await _settle(tester);
      final dialogElement = tester.element(find.byType(Dialog));
      final targetBefore = fixture.harness.bundle.controller.documentSnapshot;
      await _menu(tester, 'ingredient:Sugar');
      expect(find.text('Set planner target'), findsNothing);
      expect(find.text('Show NPC vendors'), findsOneWidget);
      await tester.tap(find.text('Show NPC vendors'));
      await _settle(tester);
      for (
        var i = 0;
        i < 30 && find.byType(BdoResourceMap).evaluate().isEmpty;
        i++
      ) {
        await _settle(tester);
      }
      expect(_selected(tester, 'resource-map'), isTrue);
      expect(find.byType(BdoResourceMap), findsOneWidget);
      expect(find.byType(Dialog), findsNothing);
      expect(find.byType(Dialog, skipOffstage: false), findsOneWidget);
      expect(
        fixture.harness.bundle.controller.activeMode.value,
        targetBefore.activeMode,
      );
      for (final mode in CraftMode.values) {
        expect(
          fixture.harness.bundle.controller.modes[mode]!.state.value.target,
          targetBefore.forMode(mode).target,
        );
        expect(
          fixture.harness.bundle.controller.modes[mode]!.state.value.want,
          targetBefore.forMode(mode).want,
        );
      }
      await tester.tap(_tab('opportunities'));
      await _settle(tester);
      expect(tester.element(find.byType(Dialog)), same(dialogElement));
      expect(_region('opportunity-title:Cream'), findsOneWidget);
      await tester.tap(_tab('planner'));
      await _settle(tester);
      expect(find.byType(Dialog), findsNothing);
      await tester.tap(_tab('opportunities'));
      await _settle(tester);
      expect(tester.element(find.byType(Dialog)), same(dialogElement));
      expect(_search(tester), 'Butter');
      await _dispose(tester, fixture);
    },
  );

  testWidgets('host rejects stale target variants without changing Planner', (
    tester,
  ) async {
    final fixture = await _mount(tester);
    final before = fixture.harness.bundle.controller.documentSnapshot;
    final actions = OpportunityItemActionsScope.maybeOf(
      tester.element(find.byType(OpportunitiesWorkspace)),
    )!;
    actions.openPlannerTarget!(
      const PlannerTargetRequest(
        exactName: 'Cream',
        mode: CraftMode.processing,
        variantId: 'not-a-real-variant',
      ),
    );
    await tester.pump();
    expect(fixture.harness.bundle.controller.documentSnapshot, same(before));
    expect(_selected(tester, 'opportunities'), isTrue);
    final mode = fixture.harness.bundle.controller.modes[CraftMode.processing]!;
    final recipe = mode.recipes.values.firstWhere(
      (recipe) => recipe.isCraftable && recipe.variants.length > 1,
    );
    final variant = recipe.variants.last;
    final wanted = mode.state.value.want;
    actions.openPlannerTarget!(
      PlannerTargetRequest(
        exactName: recipe.name,
        mode: CraftMode.processing,
        variantId: variant.id,
      ),
    );
    await _settle(tester);
    expect(mode.state.value.target, recipe.name);
    expect(mode.selectedRecipeVariantId(recipe.name), variant.id);
    expect(mode.state.value.want, wanted);
    expect(_selected(tester, 'planner'), isTrue);
    await _dispose(tester, fixture);
  });

  testWidgets(
    'actual shell item menu is content sized and correctly positioned',
    (tester) async {
      final fixture = await _mount(tester, size: const Size(1200, 752));
      await _openButter(tester, fixture.controller);
      await tester.ensureVisible(_region('ingredient:Cream'));
      await tester.tap(find.byKey(const ValueKey('ingredient-recipe-Cream')));
      await _settle(tester);
      await _menu(tester, 'opportunity-title:Cream');
      expect(find.text('Set planner target'), findsOneWidget);
      final menuItem = tester.getRect(find.text('Set planner target'));
      expect(menuItem.left, greaterThanOrEqualTo(0));
      expect(menuItem.right, lessThanOrEqualTo(1200));
      expect(
        menuItem.top,
        greaterThan(tester.getRect(_tab('opportunities')).bottom),
      );
      for (final element in find.byType(Image).evaluate().toList()) {
        await tester.runAsync(
          () => precacheImage((element.widget as Image).image, element),
        );
      }
      await _settle(tester);
      final output = Platform.environment['OPPORTUNITY_NAV_CAPTURE_DIR'];
      if (output != null && output.isNotEmpty) {
        final boundary = tester.renderObject<RenderRepaintBoundary>(
          find.byKey(const ValueKey('navigation-capture')),
        );
        await tester.runAsync(() async {
          final picture = await boundary.toImage();
          try {
            final bytes = await picture.toByteData(
              format: ui.ImageByteFormat.png,
            );
            await File(
              '$output/opportunities-target-menu-1200-normal.png',
            ).writeAsBytes(bytes!.buffer.asUint8List());
          } finally {
            picture.dispose();
          }
        });
      }
      await _dispose(tester, fixture);
    },
  );
  testWidgets('nested target reads the selected variant when its menu opens', (
    tester,
  ) async {
    final fixture = await _mount(tester);
    final mode = fixture.harness.bundle.controller.modes[CraftMode.processing]!;
    mode.commitAmount('42');
    fixture.controller.change((preferences) {
      preferences.mode = CraftMode.processing;
      preferences.craftSearch = 'Concentrated Magical Black Gem';
      preferences.profitableOnly = false;
    }, assemble: true);
    await _completeIo(tester, fixture.controller.calculationSettled);
    await _settle(tester);
    await tester.tap(
      find.byKey(const ValueKey('craft-card:Concentrated Magical Black Gem')),
    );
    await _settle(tester);
    await tester.ensureVisible(_region('ingredient:Black Gem'));
    await tester.tap(find.byKey(const ValueKey('ingredient-recipe-Black Gem')));
    await _settle(tester);
    expect(_region('opportunity-title:Black Gem'), findsOneWidget);
    await tester.tap(find.text('Standard · 10×'));
    await _settle(tester);
    expect(_region('ingredient:Black Stone Powder'), findsOneWidget);
    await _menu(tester, 'opportunity-title:Black Gem');
    await tester.tap(find.text('Set planner target'));
    await _settle(tester);
    expect(mode.state.value.target, 'Black Gem');
    expect(mode.selectedRecipeVariantId('Black Gem'), 'standard-10x');
    expect(mode.state.value.want, 42);
    await tester.tap(_tab('opportunities'));
    await _settle(tester);
    expect(_region('opportunity-title:Black Gem'), findsOneWidget);
    expect(_region('ingredient:Black Stone Powder'), findsOneWidget);
    await _dispose(tester, fixture);
  });

  testWidgets(
    'nonzero list scroll and search survive a Planner tab round-trip',
    (tester) async {
      final fixture = await _mount(tester);
      fixture.controller.change((preferences) {
        preferences.mode = CraftMode.processing;
        preferences.craftSearch = 'Crystal';
        preferences.profitableOnly = false;
      }, assemble: true);
      await _completeIo(tester, fixture.controller.calculationSettled);
      await _settle(tester);
      final position = tester
          .state<ScrollableState>(
            find
                .descendant(
                  of: find.byKey(const PageStorageKey('craft-opportunities')),
                  matching: find.byType(Scrollable),
                )
                .first,
          )
          .position;
      expect(position.maxScrollExtent, greaterThan(300));
      position.jumpTo(300);
      await _settle(tester);
      final offset = position.pixels;
      await tester.tap(_tab('planner'));
      await _settle(tester);
      await tester.tap(_tab('opportunities'));
      await _settle(tester);
      expect(fixture.controller.preferences.craftSearch, 'Crystal');
      final returnedPosition = tester
          .state<ScrollableState>(
            find
                .descendant(
                  of: find.byKey(const PageStorageKey('craft-opportunities')),
                  matching: find.byType(Scrollable),
                )
                .first,
          )
          .position;
      expect(returnedPosition.pixels, closeTo(offset, .1));
      expect(returnedPosition.pixels, greaterThan(0));
      returnedPosition.jumpTo(0);
      await _settle(tester);
      expect(_search(tester), 'Crystal');
      await _dispose(tester, fixture);
    },
  );
  testWidgets(
    'Cooking ingredient target opens its displayed Processing formula',
    (tester) async {
      final fixture = await _mount(tester);
      fixture.controller.change((preferences) {
        preferences.mode = CraftMode.cooking;
        preferences.craftSearch = 'Fruit Pudding';
        preferences.profitableOnly = false;
      }, assemble: true);
      await _completeIo(tester, fixture.controller.calculationSettled);
      await _settle(tester);
      await tester.tap(find.byKey(const ValueKey('craft-card:Fruit Pudding')));
      await _settle(tester);
      await _menu(tester, 'ingredient:Cream');
      await tester.tap(find.text('Set planner target'));
      await _settle(tester);
      final planner = fixture.harness.bundle.controller;
      expect(planner.activeMode.value, CraftMode.processing);
      expect(planner.modes[CraftMode.processing]!.state.value.target, 'Cream');
      expect(fixture.controller.preferences.mode, CraftMode.cooking);
      await tester.tap(_tab('opportunities'));
      await _settle(tester);
      expect(_region('opportunity-title:Fruit Pudding'), findsOneWidget);
      expect(_region('ingredient:Cream'), findsOneWidget);
      await _dispose(tester, fixture);
    },
  );
}

Finder _tab(String name) => find.byKey(ValueKey('top-workspace-tab-$name'));
Finder _region(String id) => find.byKey(ValueKey('opportunity-item:$id'));
bool? _selected(WidgetTester tester, String name) =>
    tester.widget<Semantics>(_tab(name)).properties.selected;
String _search(WidgetTester tester) => tester
    .widget<TextField>(
      find.descendant(
        of: find.byKey(const ValueKey('craft-search')),
        matching: find.byType(TextField),
      ),
    )
    .controller!
    .text;

ScrollPosition _recipePosition(WidgetTester tester, String name) => tester
    .state<ScrollableState>(
      find
          .descendant(
            of: find.byKey(PageStorageKey(name)),
            matching: find.byType(Scrollable),
          )
          .first,
    )
    .position;

Future<void> _menu(WidgetTester tester, String id) async {
  await tester.ensureVisible(_region(id));
  await tester.tap(
    _region(id),
    buttons: kSecondaryMouseButton,
    kind: PointerDeviceKind.mouse,
  );
  await _settle(tester);
}

Future<void> _openButter(
  WidgetTester tester,
  OpportunitiesController controller,
) async {
  controller.change((preferences) {
    preferences.mode = CraftMode.processing;
    preferences.craftSearch = 'Butter';
    preferences.profitableOnly = false;
  }, assemble: true);
  await _completeIo(tester, controller.calculationSettled);
  await _settle(tester);
  await tester.tap(find.byKey(const ValueKey('craft-card:Butter')));
  await _settle(tester);
  expect(_region('ingredient:Cream'), findsOneWidget);
}

Future<_Fixture> _mount(
  WidgetTester tester, {
  Size size = const Size(700, 680),
}) async {
  configureApplicationTestSurface(tester, size);
  final harness = (await tester.runAsync(ApplicationTestHarness.create))!;
  await tester.runAsync(harness.disposeControllerOnly);
  await tester.runAsync(BdoResourceMapLoader.loadBundled);
  await tester.runAsync(BdoWorkerEconomicsLoader.loadBundled);
  await tester.runAsync(LodgingDataLoader.loadBundled);
  final rebound = harness.rebindControllerInCurrentZone();
  final client = MockClient(
    (request) async => http.Response('Offline test', 503),
  );
  final window = _Window();
  await tester.pumpWidget(
    RepaintBoundary(
      key: const ValueKey('navigation-capture'),
      child: MaterialApp(
        home: ThemeSpecScope(
          spec: RetainedThemeRegistry.resolve(backgroundId: 'standard-dark'),
          child: ApplicationWorkspace(
            bundle: rebound.bundle,
            marketGateway: const EmptyMarketGateway(),
            windowHost: window,
            enableBetaUpdates: false,
            enableOpportunityAutoCheck: false,
            resourceMapConfiguration: ResourceMapWorkspaceConfiguration(
              cacheDirectory: Directory(
                '${rebound.temporaryDirectory.path}/map-cache',
              ),
              tileHttpClient: client,
              showSourceNotice: false,
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.tap(_tab('opportunities'));
  await tester.pump();
  final controller = tester
      .widget<OpportunitiesWorkspace>(find.byType(OpportunitiesWorkspace))
      .controller;
  await _completeIo(tester, controller.ready);
  await _completeIo(tester, controller.calculationSettled);
  return _Fixture(rebound, controller, window, client);
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 4; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 15)),
    );
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _completeIo(WidgetTester tester, Future<void> work) async {
  var complete = false;
  Object? failure;
  unawaited(
    work.then(
      (_) => complete = true,
      onError: (Object error) {
        failure = error;
        complete = true;
      },
    ),
  );
  for (var i = 0; i < 1000 && !complete; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump();
  }
  expect(complete, isTrue);
  if (failure != null) throw failure!;
}

Future<void> _dispose(WidgetTester tester, _Fixture fixture) async {
  await _completeIo(tester, fixture.window.beforeClose!());
  await tester.pumpWidget(const SizedBox.shrink());
  await _completeIo(tester, fixture.harness.dispose());
  fixture.client.close();
  expect(tester.takeException(), isNull);
}

class _Fixture {
  _Fixture(this.harness, this.controller, this.window, this.client);
  final ApplicationTestHarness harness;
  final OpportunitiesController controller;
  final _Window window;
  final http.Client client;
}

class _Window extends WindowHostService {
  Future<void> Function()? beforeClose;
  @override
  void installCloseRequestHandler(Future<void> Function()? handler) =>
      beforeClose = handler;
  @override
  void removeCloseRequestHandler() => beforeClose = null;
  @override
  Future<bool> isMaximized() async => false;
  @override
  Future<void> setBottomInset(double inset) async {}
}

Future<void> _loadFonts() async {
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
  for (final family in <String, List<String>>{
    'Segoe UI': [
      '$windows/Fonts/segoeui.ttf',
      '$windows/Fonts/seguisb.ttf',
      '$windows/Fonts/segoeuib.ttf',
    ],
    'Georgia': ['$windows/Fonts/georgia.ttf', '$windows/Fonts/georgiab.ttf'],
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
