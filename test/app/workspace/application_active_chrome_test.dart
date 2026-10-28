import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:bdo_craft_planner_flutter/app/appearance/appearance_actions.dart';
import 'package:bdo_craft_planner_flutter/app/window/app_title_bar.dart';
import 'package:bdo_craft_planner_flutter/app/window/app_title_bar_visual.dart';
import 'package:bdo_craft_planner_flutter/app/workspace/application_copy_toast.dart';
import 'package:bdo_craft_planner_flutter/app/workspace/application_workspace.dart';
import 'package:bdo_craft_planner_flutter/data/market/shared_market_repository.dart';
import 'package:bdo_craft_planner_flutter/data/opportunities/opportunity_market_cache_store.dart';
import 'package:bdo_craft_planner_flutter/data/opportunities/opportunity_market_service.dart';
import 'package:bdo_craft_planner_flutter/domain/models/craft_mode.dart';
import 'package:bdo_craft_planner_flutter/features/gathering/gathering_workspace.dart';
import 'package:bdo_craft_planner_flutter/features/opportunities/opportunities_item_actions.dart';
import 'package:bdo_craft_planner_flutter/features/opportunities/opportunities_preferences.dart';
import 'package:bdo_craft_planner_flutter/features/opportunities/opportunities_visuals.dart';
import 'package:bdo_craft_planner_flutter/features/opportunities/opportunities_workspace.dart';
import 'package:bdo_craft_planner_flutter/features/planner/planner.dart';
import 'package:bdo_craft_planner_flutter/features/resource_map/resource_map_workspace.dart';
import 'package:bdo_craft_planner_flutter/visual/visual.dart';
import 'package:bdo_map_core/bdo_map_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../../support/application_test_harness.dart';

const _capture = ValueKey('active-chrome-capture');
const _whale = 'Sturdy Whale Tendon Potion';
Finder _tab(String name) => find.byKey(ValueKey('top-workspace-tab-$name'));
Finder get _toast => find.byKey(ApplicationCopyToastKeys.surface);

void main() {
  setUpAll(_fonts);
  _chromeTestWidgets(
    'shortcut return retains the Planner and ignores same-tab or manual jumps',
    (tester) async {
      final f = await _fixture(tester);
      try {
        await tester.pumpWidget(_host(f));
        await _pump(tester);
        final back = find.byKey(AppTitleTabStrip.returnButtonKey);
        final planner = find.byType(PlannerView);
        final originalElement = tester.element(planner);
        final actions = tester.widget<PlannerView>(planner).externalActions;
        final mode = f.harness.bundle.controller.active;
        mode.commitAmount('73');
        final target = mode.state.value.target;
        expect(back, findsNothing);
        actions.openPlannerTarget!(
          PlannerTargetRequest(
            exactName: target,
            mode: f.harness.bundle.controller.activeMode.value,
          ),
        );
        await _pump(tester);
        expect(back, findsNothing);
        actions.openMapLookup!(
          const PlannerMapLookupRequest(
            materialName: 'Sugar',
            source: PlannerMapLookupSource.npcVendors,
          ),
        );
        await _until(
          tester,
          () => find.byType(BdoResourceMap).evaluate().isNotEmpty,
        );
        expect(find.byTooltip('Back to Planner'), findsOneWidget);
        await _captureImage(tester, 'return-arrow-resource-map', height: 120);
        // A second lookup within the map must not add a duplicate return step.
        actions.openMapLookup!(
          const PlannerMapLookupRequest(
            materialName: 'Apple',
            source: PlannerMapLookupSource.workerNodes,
          ),
        );
        await _pump(tester);
        await tester.tap(back);
        await _pump(tester);
        expect(back, findsNothing);
        expect(tester.element(planner), same(originalElement));
        expect(mode.state.value.target, target);
        expect(mode.state.value.want, 73);

        actions.openMapLookup!(
          const PlannerMapLookupRequest(
            materialName: 'Sugar',
            source: PlannerMapLookupSource.npcVendors,
          ),
        );
        await _pump(tester);
        expect(back, findsOneWidget);
        await _select(tester, 'fish-map');
        expect(back, findsNothing);
        await _select(tester, 'resource-map');
        expect(back, findsNothing);
        expect(tester.takeException(), isNull);
      } finally {
        await _dispose(tester, f);
      }
    },
  );

  _chromeTestWidgets(
    'nested shortcut return restores the open Opportunities recipe and scroll',
    (tester) async {
      final f = await _fixture(tester);
      try {
        await tester.pumpWidget(_host(f));
        await _pump(tester);
        await _select(tester, 'opportunities');
        final card = find.byKey(const ValueKey('craft-card:$_whale'));
        await _until(tester, () => card.evaluate().isNotEmpty);
        await tester.tap(card);
        await _pump(tester);
        final dialog = tester.element(find.byType(Dialog));
        final opportunities = tester.element(
          find.byType(OpportunitiesWorkspace),
        );
        final scrollable = find
            .descendant(
              of: find.byType(Dialog),
              matching: find.byType(Scrollable),
            )
            .first;
        final position = tester.state<ScrollableState>(scrollable).position;
        position.jumpTo(position.maxScrollExtent / 2);
        await tester.pump();
        final offset = position.pixels;
        final actions = OpportunityItemActionsScope.maybeOf(opportunities)!;
        final processing =
            f.harness.bundle.controller.modes[CraftMode.processing]!;
        processing.commitAmount('73');
        actions.openPlannerTarget!(
          const PlannerTargetRequest(
            exactName: _whale,
            mode: CraftMode.processing,
          ),
        );
        await _pump(tester);
        expect(find.byTooltip('Back to Opportunities'), findsOneWidget);
        await _captureImage(tester, 'return-arrow-planner', height: 120);
        expect(processing.state.value.target, _whale);
        expect(processing.state.value.want, 73);
        expect(find.byType(Dialog), findsNothing);
        actions.openMapLookup!(
          const PlannerMapLookupRequest(
            materialName: 'Sugar',
            source: PlannerMapLookupSource.npcVendors,
          ),
        );
        await _until(
          tester,
          () => find.byType(BdoResourceMap).evaluate().isNotEmpty,
        );
        expect(find.byTooltip('Back to Planner'), findsOneWidget);
        await tester.tap(find.byKey(AppTitleTabStrip.returnButtonKey));
        await _pump(tester);
        expect(find.byTooltip('Back to Opportunities'), findsOneWidget);
        expect(find.byType(PlannerView), findsOneWidget);
        await tester.tap(find.byKey(AppTitleTabStrip.returnButtonKey));
        await _pump(tester);
        expect(find.byKey(AppTitleTabStrip.returnButtonKey), findsNothing);
        expect(
          tester.element(find.byType(OpportunitiesWorkspace)),
          same(opportunities),
        );
        expect(tester.element(find.byType(Dialog)), same(dialog));
        expect(position.pixels, closeTo(offset, .1));
        expect(processing.state.value.target, _whale);
        expect(processing.state.value.want, 73);
        expect(f.transport.requests, isEmpty);
        expect(tester.takeException(), isNull);
      } finally {
        await _dispose(tester, f);
      }
    },
  );

  _chromeTestWidgets(
    'visible copy toast and title follow the active tab without resetting lifetime',
    (tester) async {
      final f = await _fixture(tester);
      final copied = <String>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copied.add((call.arguments as Map)['text'] as String);
          }
          return null;
        },
      );
      try {
        await tester.pumpWidget(_host(f));
        await _pump(tester);
        await _select(tester, 'opportunities');
        await _until(
          tester,
          () => find
              .byKey(const ValueKey('craft-card:$_whale'))
              .evaluate()
              .isNotEmpty,
        );
        await _settleImages(tester);
        final selectedTitle = _title();
        expect(selectedTitle.image, isNotNull);
        final cardSpec = tester
            .element(find.byKey(const ValueKey('craft-card:$_whale')))
            .visualTheme;
        expect(
          cardSpec,
          same(
            OpportunitiesVisualSpec.forAppearance(SakuraNightGardenSpec.theme),
          ),
        );
        await _select(tester, 'planner');
        await _settleImages(tester);
        final actions = tester
            .widget<PlannerView>(find.byType(PlannerView))
            .externalActions;
        final originalAppearance =
            f.harness.bundle.controller.documentSnapshot.alchemy.appearance;
        await actions.copyName(_whale);
        await tester.pump();
        final started = tester.binding.clock.now();
        expect(_toast, findsOneWidget);
        expect(_title().image, isNotNull);
        expect(
          _toastSpec(tester).family,
          RetainedVisualFamily.sakuraNightGarden,
        );
        await _captureImage(tester, 'planner-sakura-copy-normal');

        await _select(tester, 'opportunities');
        expect(find.text('Copied $_whale'), findsOneWidget);
        expect(
          _toastSpec(tester).palette,
          same(SakuraNightGardenSpec.theme.palette),
        );
        final decoration =
            tester.widget<Container>(_toast).decoration! as BoxDecoration;
        expect(
          decoration.gradient,
          SakuraNightGardenSpec.theme.materials.surfaceRaised,
        );
        expect(
          tester.widget<Text>(find.text('Copied $_whale')).style?.color,
          SakuraNightGardenSpec.theme.palette.text,
        );
        expect(_title().gradient, selectedTitle.gradient);
        expect(tester.getSize(find.byType(AppTitleBar)).height, 40);
        expect(tester.getRect(_toast).top, 52);
        expect(_toast.hitTestable(), findsNothing);
        await _captureImage(tester, 'opportunities-glass-copy-normal');

        await _select(tester, 'planner');
        expect(
          _toastSpec(tester).family,
          RetainedVisualFamily.sakuraNightGarden,
        );
        expect(
          f.harness.bundle.controller.documentSnapshot.alchemy.appearance,
          same(originalAppearance),
        );
        final elapsed = tester.binding.clock.now().difference(started);
        expect(elapsed, lessThan(const Duration(milliseconds: 1349)));
        await tester.pump(const Duration(milliseconds: 1349) - elapsed);
        expect(_toast, findsOneWidget);
        await tester.pump(const Duration(milliseconds: 1));
        expect(_toast, findsNothing);
        expect(copied, [_whale]);
        expect(f.transport.requests, isEmpty);

        await _select(tester, 'opportunities');
        await tester.tap(
          find.byKey(const ValueKey('opportunity-copy-name:$_whale')),
        );
        await _until(tester, () => _toast.evaluate().isNotEmpty);
        expect(
          _toastSpec(tester).palette,
          same(SakuraNightGardenSpec.theme.palette),
        );
        expect(copied, [_whale, _whale]);
      } finally {
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        );
        await _dispose(tester, f);
      }
    },
  );

  _chromeTestWidgets(
    'already visible operation error rethemes without replacing its SnackBar',
    (tester) async {
      final f = await _fixture(tester);
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            throw PlatformException(code: 'test-clipboard-unavailable');
          }
          return null;
        },
      );
      try {
        await tester.pumpWidget(_host(f));
        await _pump(tester);
        final actions = tester
            .widget<PlannerView>(find.byType(PlannerView))
            .externalActions;
        await actions.copyName('Apple');
        await tester.pump();
        final bar = tester.widget<SnackBar>(find.byType(SnackBar));
        final label = find.textContaining('could not be copied because');
        expect(
          tester.widget<Text>(label).style?.color,
          SakuraNightGardenSpec.theme.palette.text,
        );
        await _select(tester, 'fish-map');
        expect(_title().gradient, AppTitleBarVisual.fishMap.titleGradient);
        expect(tester.widget<SnackBar>(find.byType(SnackBar)), same(bar));
        expect(
          tester.widget<Text>(label).style?.color,
          AppTitleBarVisual.fishMap.foreground,
        );
        expect(
          tester.element(label).visualTheme.family,
          RetainedVisualFamily.standard,
        );
        expect(f.transport.requests, isEmpty);
      } finally {
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        );
        await _dispose(tester, f);
      }
    },
  );

  _chromeTestWidgets(
    'all Codex tabs share Appearance while Fish stays independent and retained',
    (tester) async {
      final f = await _fixture(tester);
      final parentZone = Zone.current;
      var redirectedLegacyProbes = 0;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (_) async => null,
      );
      try {
        await IOOverrides.runZoned(
          () async {
            await tester.pumpWidget(_host(f));
            await _pump(tester);
            final actions = tester
                .widget<PlannerView>(find.byType(PlannerView))
                .externalActions;
            final originalAppearance =
                f.harness.bundle.controller.documentSnapshot.alchemy.appearance;
            final sharedTitle = _title();
            await _select(tester, 'resource-map');
            expect(_title().gradient, sharedTitle.gradient);
            await _captureRoutingState(
              tester,
              actions,
              'map-glass-chrome-normal',
              ready: find.byType(BdoResourceMap),
            );
            f.harness.bundle.controller.setResourceMapInterfaceStyle(
              ResourceMapInterfaceStyle.ghostLedger,
            );
            await tester.pump();
            expect(_title().gradient, sharedTitle.gradient);
            f.harness.bundle.controller.setResourceMapUiOpacity(0);
            await _captureRoutingState(
              tester,
              actions,
              'map-ghost-chrome-normal',
            );
            await tester.pump();
            expect(_title().gradient, sharedTitle.gradient);
            await _select(tester, 'gathering');
            expect(redirectedLegacyProbes, 0);
            expect(_title().gradient, sharedTitle.gradient);
            await _captureRoutingState(
              tester,
              actions,
              'gathering-chrome-normal',
              ready: find.byKey(const ValueKey('gathering-spot-guide')),
            );
            await _select(tester, 'fish-map');
            expect(_title().gradient, AppTitleBarVisual.fishMap.titleGradient);
            // The native Fish WebView stays untouched; this widget capture
            // includes only the shared title/toast, never a fake fish page.
            await _captureRoutingState(
              tester,
              actions,
              'fish-shared-chrome-only-normal',
              height: 120,
            );
            expect(
              find.byKey(const ValueKey('test-fish-interior')),
              findsOneWidget,
            );
            final fishElement = tester.element(
              find.byKey(const ValueKey('test-fish-interior')),
            );
            final gatheringElement = tester.element(
              find.byType(GatheringWorkspace, skipOffstage: false),
            );
            f.harness.bundle.controller.updateDocument(
              (document) => AppearanceActions.selectSharedBackground(
                document,
                'illuminated-ledger',
              ),
            );
            await _pump(tester);
            expect(_title().gradient, AppTitleBarVisual.fishMap.titleGradient);
            expect(
              tester.element(find.byKey(const ValueKey('test-fish-interior'))),
              same(fishElement),
            );
            await _select(tester, 'gathering');
            expect(
              tester.element(find.byType(GatheringWorkspace)),
              same(gatheringElement),
            );
            expect(
              tester
                  .widget<GatheringWorkspace>(find.byType(GatheringWorkspace))
                  .theme!
                  .value
                  .brightness,
              Brightness.light,
            );
            await _select(tester, 'opportunities');
            expect(
              tester
                  .widget<OpportunitiesWorkspace>(
                    find.byType(OpportunitiesWorkspace),
                  )
                  .theme!
                  .value
                  .brightness,
              Brightness.light,
            );
            f.harness.bundle.controller.updateDocument(
              (document) => AppearanceActions.selectSharedBackground(
                document,
                originalAppearance.background,
              ),
            );
            await _pump(tester);
            await _select(tester, 'planner');
            expect(_title().image, isNotNull);
            expect(
              f.harness.bundle.controller.documentSnapshot.alchemy.appearance
                  .toJson(),
              originalAppearance.toJson(),
            );
            expect(
              f.harness.bundle.controller.resourceMapInterfaceStyle.value,
              ResourceMapInterfaceStyle.ghostLedger,
            );
            expect(f.transport.requests, isEmpty);
            await _dispose(tester, f);
          },
          createFile: (path) => parentZone.run(() {
            if (path
                .replaceAll('\\', '/')
                .toLowerCase()
                .contains('/bdo gathering companion/')) {
              redirectedLegacyProbes++;
              return File(
                '${f.harness.temporaryDirectory.path}/absent-legacy-sessions.json',
              );
            }
            return File(path);
          }),
        );
        expect(redirectedLegacyProbes, 0);
      } finally {
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        );
        if (!f.disposed) await _dispose(tester, f);
      }
    },
  );
}

void _chromeTestWidgets(String description, WidgetTesterCallback body) {
  testWidgets(description, (tester) async {
    final previous = debugDisableShadows;
    debugDisableShadows = false;
    try {
      await body(tester);
    } finally {
      debugDisableShadows = previous;
    }
  });
}

BoxDecoration _title() =>
    (find.byKey(AppTitleBar.materialKey).evaluate().single.widget
                as DecoratedBox)
            .decoration
        as BoxDecoration;
ThemeSpec _toastSpec(WidgetTester tester) => tester
    .widget<ApplicationCopyToastOverlay>(
      find.byType(ApplicationCopyToastOverlay),
    )
    .spec;
Future<void> _select(WidgetTester tester, String name) async {
  await tester.tap(_tab(name));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 80));
  if (name == 'opportunities') {
    final controller = tester
        .widget<OpportunitiesWorkspace>(find.byType(OpportunitiesWorkspace))
        .controller;
    await _work(tester, controller.ready);
    // Searches are intentionally session-only. Set the test's recipe after
    // startup instead of expecting an old saved search to be restored.
    if (controller.preferences.craftSearch != _whale) {
      controller.change((p) => p.craftSearch = _whale);
      await _work(tester, controller.calculationSettled);
      await _pump(tester);
    }
  }
}

class _Fixture {
  _Fixture(this.harness, this.broker, this.transport, this.tiles);
  final ApplicationTestHarness harness;
  final SharedMarketRepository broker;
  final _NoNetwork transport;
  final http.Client tiles;
  bool disposed = false;
}

Future<_Fixture> _fixture(WidgetTester tester) async {
  configureApplicationTestSurface(tester, const Size(1200, 752));
  var h = (await tester.runAsync(
    () => ApplicationTestHarness.create(backgroundId: 'sakura-night-garden'),
  ))!;
  await tester.runAsync(h.disposeControllerOnly);
  h = h.rebindControllerInCurrentZone();
  return (await tester.runAsync(() async {
    final now = DateTime.now().toUtc();
    final directory = Directory(
      '${h.bundle.stateRepository.paths.applicationDirectory.path}/opportunities',
    );
    final cache = OpportunityMarketCacheStore(directory: directory);
    final ids = <String>{
      ...(h.bundle.catalog.supportingData['marketIds']! as Map).values.map(
        (value) => '$value',
      ),
      for (final mode in h.bundle.controller.modes.values)
        for (final recipe in mode.recipes.values)
          if (recipe.marketId != null) recipe.marketId!,
    };
    await cache.save({
      'eu': {
        for (final id in ids)
          id: OpportunityMarketItem(
            itemId: id,
            basePrice: 1000,
            stock: 100000,
            quoteFetchedAt: now,
            bookFetchedAt: now,
            asks: const [OpportunityMarketLevel(price: 1000, quantity: 100000)],
            bids: const [OpportunityMarketLevel(price: 1000, quantity: 100)],
          ),
      },
    });
    await OpportunitiesPreferenceStore(directory).save(
      OpportunitiesPreferences()
        ..mode = CraftMode.processing
        ..craftSearch = _whale
        ..profitableOnly = false,
    );
    final transport = _NoNetwork();
    final broker = SharedMarketRepository(
      cacheStore: cache,
      transport: transport,
    );
    await broker.ready;
    await BdoResourceMapLoader.loadBundled();
    await BdoWorkerEconomicsLoader.loadBundled();
    await LodgingDataLoader.loadBundled();
    return _Fixture(
      h,
      broker,
      transport,
      MockClient((request) async => http.Response('', 404)),
    );
  }))!;
}

Widget _host(_Fixture f) => RepaintBoundary(
  key: _capture,
  child: MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: SakuraNightGardenSpec.theme.materialTheme(),
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(disableAnimations: true),
      child: child!,
    ),
    home: ApplicationWorkspace(
      bundle: f.harness.bundle,
      marketGateway: const EmptyMarketGateway(),
      sharedMarket: f.broker,
      enableOpportunityAutoCheck: false,
      enableBetaUpdates: false,
      resourceMapConfiguration: ResourceMapWorkspaceConfiguration(
        cacheDirectory: Directory(
          '${f.harness.temporaryDirectory.path}/map-cache',
        ),
        tileHttpClient: f.tiles,
        showSourceNotice: false,
      ),
      fishMapWorkspace: const ColoredBox(
        key: ValueKey('test-fish-interior'),
        color: Color(0xFF0A0E12),
      ),
    ),
  ),
);

class _NoNetwork implements OpportunityMarketTransport {
  final requests = <Uri>[];
  @override
  Future<OpportunityHttpResponse> post(
    Uri uri, {
    required Map<String, String> headers,
    required String body,
    Future<void>? abortTrigger,
  }) async {
    requests.add(uri);
    throw StateError('No network allowed in shell theme tests: $uri');
  }

  @override
  void close() {}
}

Future<void> _dispose(WidgetTester tester, _Fixture f) async {
  if (f.disposed) return;
  f.disposed = true;
  final opportunities = find.byType(
    OpportunitiesWorkspace,
    skipOffstage: false,
  );
  if (opportunities.evaluate().isNotEmpty) {
    await _work(
      tester,
      tester.widget<OpportunitiesWorkspace>(opportunities).controller.flush(),
    );
  }
  await tester.pumpWidget(const SizedBox.shrink());
  await _work(tester, f.broker.close());
  await _work(tester, f.harness.bundle.controller.dispose());
  f.tiles.close();
  await tester.runAsync(f.harness.dispose);
}

Future<void> _pump(WidgetTester tester) async {
  for (var i = 0; i < 4; i++) {
    await tester.pump(const Duration(milliseconds: 80));
  }
}

Future<void> _until(WidgetTester tester, bool Function() ready) async {
  for (var i = 0; i < 300 && !ready(); i++) {
    await tester.pump(const Duration(milliseconds: 20));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 5)),
    );
  }
  expect(ready(), isTrue);
  await tester.pump();
}

Future<void> _work(WidgetTester tester, Future<void> work) async {
  var done = false;
  Object? error;
  unawaited(
    work.then(
      (_) => done = true,
      onError: (Object value) {
        error = value;
        done = true;
      },
    ),
  );
  await _until(tester, () => done);
  if (error != null) throw error!;
}

Future<void> _settleImages(WidgetTester tester) async {
  for (final element in find.byType(Image).evaluate().toList()) {
    final provider = (element.widget as Image).image;
    if (provider is AssetImage || provider is MemoryImage) {
      await tester.runAsync(() => precacheImage(provider, element));
    }
  }
  await tester.pump(const Duration(milliseconds: 100));
}

Future<void> _captureRoutingState(
  WidgetTester tester,
  PlannerExternalActions actions,
  String name, {
  double? height,
  Finder? ready,
}) async {
  if (Platform.environment['ACTIVE_CHROME_CAPTURE_DIR'] == null) return;
  if (ready != null) {
    // The native host loads bundled catalog/state asynchronously. Capture the
    // actual ready feature, with the same bounded wait as other host checks.
    await _until(tester, () => ready.evaluate().isNotEmpty);
    await tester.pump(const Duration(milliseconds: 350));
  }
  await _settleImages(tester);
  await actions.copyName('Birch Sap');
  await tester.pump();
  await _captureImage(tester, name, height: height);
}

Future<void> _captureImage(
  WidgetTester tester,
  String name, {
  double? height,
}) async {
  final directory = Platform.environment['ACTIVE_CHROME_CAPTURE_DIR'];
  if (directory == null) return;
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(_capture),
  );
  await tester.runAsync(() async {
    await Directory(directory).create(recursive: true);
    final image = height == null
        ? await boundary.toImage()
        : await (boundary.debugLayer! as OffsetLayer).toImage(
            Rect.fromLTWH(0, 0, boundary.size.width, height),
          );
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

Future<void> _fonts() async {
  if (!Platform.isWindows) return;
  final win = Platform.environment['WINDIR'] ?? r'C:\Windows';
  var sdk = File(Platform.resolvedExecutable).parent;
  while (!Directory(
        '${sdk.path}/bin/cache/artifacts/material_fonts',
      ).existsSync() &&
      sdk.parent.path != sdk.path) {
    sdk = sdk.parent;
  }
  for (final entry in <String, List<String>>{
    'Segoe UI': [
      '$win/Fonts/segoeui.ttf',
      '$win/Fonts/seguisb.ttf',
      '$win/Fonts/segoeuib.ttf',
    ],
    'Georgia': ['$win/Fonts/georgia.ttf', '$win/Fonts/georgiab.ttf'],
    'Roboto': [
      '${sdk.path}/bin/cache/artifacts/material_fonts/Roboto-Regular.ttf',
    ],
    'MaterialIcons': [
      '${sdk.path}/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
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
}
