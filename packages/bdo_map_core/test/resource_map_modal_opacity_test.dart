import 'dart:io';

import 'package:bdo_map_core/bdo_map_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late BdoResourceMapDataset dataset;
  late BdoWorkerEconomicsDataset economics;
  late LodgingDataset lodging;
  late Directory cacheDirectory;
  late MockClient tileClient;

  setUpAll(() async {
    dataset = await BdoResourceMapLoader.loadBundled();
    economics = await BdoWorkerEconomicsLoader.loadBundled();
    lodging = await LodgingDataLoader.loadBundled();
    cacheDirectory = await Directory.systemTemp.createTemp('bdo_map_modals_');
    tileClient = MockClient((_) async => http.Response('', 404));
  });

  tearDownAll(() async {
    tileClient.close();
    await cacheDirectory.delete(recursive: true);
  });

  ResourceMapChromeThemeData palette(ResourceMapInterfaceStyle style) =>
      style == ResourceMapInterfaceStyle.ghostLedger
      ? ResourceMapChromeThemeData.ghostLedger
      : ResourceMapChromeThemeData.glassDock;

  Future<void> openMap(
    WidgetTester tester,
    ResourceMapInterfaceStyle style,
    double opacity, {
    ValueNotifier<ResourceMapChromeThemeData>? liveChrome,
  }) async {
    await tester.binding.setSurfaceSize(const Size(1200, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final source =
        liveChrome ?? ValueNotifier(palette(style).withUiOpacity(opacity));
    if (liveChrome == null) addTearDown(source.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(
            size: Size(1200, 800),
            disableAnimations: true,
          ),
          child: ValueListenableBuilder<ResourceMapChromeThemeData>(
            valueListenable: source,
            builder: (context, chrome, child) => ResourceMapChromeTheme(
              data: chrome,
              liveData: liveChrome,
              child: child!,
            ),
            child: BdoResourceMap(
              dataset: dataset,
              workerEconomics: economics,
              lodgingDataset: lodging,
              cacheDirectory: cacheDirectory,
              tileHttpClient: tileClient,
              showSourceNotice: false,
              interfaceStyle: style,
              uiOpacity: opacity,
              showSetupScreenshotImport: true,
              setupScreenshotPicker: () async => null,
              activeNodeRecordingPicker: () async => null,
              activeNodeRecordingScanner: (path, {onProgress}) async {
                throw StateError('This test never scans a recording.');
              },
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> tapKey(WidgetTester tester, String key) async {
    final target = find.byKey(ValueKey(key));
    await tester.ensureVisible(target);
    await tester.tap(target);
    await tester.pumpAndSettle();
  }

  void expectProtected(
    WidgetTester tester,
    ResourceMapInterfaceStyle style,
    double mapOpacity,
  ) {
    final base = palette(style);
    final alert = find.byType(AlertDialog).last;
    final context = tester.element(alert);
    final chrome = context.mapChrome;
    expect(chrome.uiOpacity, 1);
    expect(chrome.paperRaised.a, closeTo(base.paperRaised.a, .000001));
    expect(chrome.paper.a, closeTo(base.paper.a, .000001));
    expect(chrome.ink, base.ink);
    expect(chrome.text, base.text);
    expect(chrome.primary, base.primary);
    final theme = Theme.of(context);
    expect(
      theme.inputDecorationTheme.fillColor!.a,
      closeTo(base.chromeRaised.a, .000001),
    );
    expect(
      (tester.widget<AlertDialog>(alert).backgroundColor ??
              theme.dialogTheme.backgroundColor)!
          .a,
      greaterThan(.90),
    );
    // The captured modal theme must not change the underlying map preference.
    final map = tester.element(find.byType(BdoResourceMap));
    expect(map.mapChrome.uiOpacity, mapOpacity);
    expect(
      map.mapChrome.paperRaised.a,
      closeTo(
        base.paperRaised.a * (mapOpacity == 0 ? .02 : mapOpacity),
        .000001,
      ),
    );
    expect(tester.takeException(), isNull);
  }

  Future<void> openTown(WidgetTester tester) async {
    await tapKey(tester, 'resource-map-home-houses');
    final town = lodging.towns.firstWhere(
      (town) => town.name.startsWith('Calpheon'),
    );
    await tapKey(tester, 'resource-map-housing-town-${town.townNodeId}');
    await tester.tap(find.byTooltip('House options'));
    await tester.pumpAndSettle();
  }

  testWidgets(
    'an already-open map settings modal follows a live light palette',
    (tester) async {
      final live = ValueNotifier(
        ResourceMapChromeThemeData.glassDock.withUiOpacity(.25),
      );
      addTearDown(live.dispose);
      await openMap(
        tester,
        ResourceMapInterfaceStyle.glassDock,
        .25,
        liveChrome: live,
      );
      await tapKey(tester, 'resource-map-home-worker-income');
      await tapKey(tester, 'resource-map-worker-income-settings');
      final mapState = tester.state(find.byType(BdoResourceMap));
      final dialogState = tester.state(find.byType(TextField).first);
      final light = ResourceMapChromeThemeData.glassDock.withPalette(
        canvas: const Color(0xFF071A2E),
        surface: const Color(0xFFE9D5A8),
        raised: const Color(0xFFF2E3BD),
        inset: const Color(0xFFD8BF8A),
        foreground: const Color(0xFF352516),
        secondaryForeground: const Color(0xFF765F3B),
        primary: const Color(0xFF123D69),
        primaryBright: const Color(0xFF1A5487),
        trim: const Color(0xFF9A742F),
        trimBright: const Color(0xFFD6B45A),
        positive: const Color(0xFF647B35),
        warning: const Color(0xFFB78338),
        error: const Color(0xFFA45648),
        shadow: const Color(0x70352516),
      );
      live.value = light.withUiOpacity(.25);
      await tester.pumpAndSettle();
      final context = tester.element(find.byType(AlertDialog));
      expect(context.mapChrome.ink, light.ink);
      expect(context.mapChrome.uiOpacity, 1);
      expect(Theme.of(context).brightness, Brightness.light);
      expect(
        Theme.of(context).inputDecorationTheme.fillColor,
        light.chromeRaised,
      );
      expect(tester.state(find.byType(BdoResourceMap)), same(mapState));
      expect(tester.state(find.byType(TextField).first), same(dialogState));
      expect(
        tester.element(find.byType(BdoResourceMap)).mapChrome.uiOpacity,
        .25,
      );
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
    },
  );

  for (final style in ResourceMapInterfaceStyle.values) {
    for (final opacity in <double>[0, .25]) {
      testWidgets(
        '${style.name} estimate modal protects $opacity map opacity',
        (tester) async {
          await openMap(tester, style, opacity);
          await tapKey(tester, 'resource-map-home-worker-income');
          await tapKey(tester, 'resource-map-worker-income-settings');
          expectProtected(tester, style, opacity);
          final context = tester.element(find.byType(AlertDialog));
          final route = ModalRoute.of(context)! as DialogRoute;
          expect(route.barrierColor, Colors.black54);
          expect(route.barrierDismissible, isTrue);
          await tester.tap(find.text('Cancel'));
          await tester.pumpAndSettle();
          expect(find.byType(AlertDialog), findsNothing);
          expect(
            tester.element(find.byType(BdoResourceMap)).mapChrome.uiOpacity,
            opacity,
          );
        },
      );
    }

    testWidgets(
      '${style.name} explicit shop backing protects zero map opacity',
      (tester) async {
        await openMap(tester, style, 0);
        await openTown(tester);
        await tester.tap(find.text('Shop lodging'));
        await tester.pumpAndSettle();
        expectProtected(tester, style, 0);
        expect(
          tester.widget<AlertDialog>(find.byType(AlertDialog)).backgroundColor,
          isNotNull,
        );
        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();
        expect(find.byType(AlertDialog), findsNothing);
      },
    );

    testWidgets(
      '${style.name} nested recording inherits protected modal chrome',
      (tester) async {
        await openMap(tester, style, 0);
        await openTown(tester);
        await tester.tap(find.text('Scan house screenshots'));
        await tester.pumpAndSettle();
        expect(find.byType(BdoSetupScreenshotImportDialog), findsOneWidget);
        expectProtected(tester, style, 0);
        await tapKey(tester, 'setup-import-mode-nodes');
        await tapKey(tester, 'setup-import-active-list-open');
        expect(find.byType(BdoActiveNodeRecordingImportDialog), findsOneWidget);
        expectProtected(tester, style, 0);
        final context = tester.element(find.byType(AlertDialog).last);
        expect(ModalRoute.of(context)!.barrierDismissible, isFalse);
        Navigator.of(context).pop();
        await tester.pumpAndSettle();
        expect(find.byType(BdoActiveNodeRecordingImportDialog), findsNothing);
        expectProtected(tester, style, 0);
        await tapKey(tester, 'setup-screenshot-import-close');
        expect(find.byType(AlertDialog), findsNothing);
      },
    );
  }
}
