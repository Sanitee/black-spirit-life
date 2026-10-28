import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:bdo_gathering_companion/domain/models.dart';
import 'package:bdo_gathering_companion/src/domain/bairog_benchmarks.dart';
import 'package:bdo_gathering_companion/services/session_store.dart';
import 'package:bdo_gathering_companion/src/gathering_companion_home.dart';
import 'package:bdo_gathering_companion/src/services/host_services.dart';
import 'package:bdo_gathering_companion/src/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _receiptDirectory = r'C:\fixture\gathering\session-import-inbox';

const _package = 'bdo_gathering_companion';

Future<ui.Image> _decodePackageAsset(String path) async {
  final data = await rootBundle.load('packages/$_package/$path');
  final codec = await ui.instantiateImageCodec(
    data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
  );
  try {
    final frame = await codec.getNextFrame();
    return frame.image;
  } finally {
    codec.dispose();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Catalog catalog;
  late List<ui.Image> representativeArtwork;
  late Directory temporaryRoot;
  late Directory dataDirectory;
  late SessionStore store;

  setUpAll(() async {
    catalog = await Catalog.load();
    final tool = catalog.methods.firstWhere((method) => method.icon.isNotEmpty);
    final item = catalog.items.firstWhere((entry) => entry.icon.isNotEmpty);
    representativeArtwork = await Future.wait([
      _decodePackageAsset(tool.icon),
      _decodePackageAsset(item.icon),
    ]);
    temporaryRoot = await Directory.systemTemp.createTemp(
      'bdo-gathering-feature-',
    );
    dataDirectory = Directory(
      '${temporaryRoot.path}${Platform.pathSeparator}gathering',
    );
    await dataDirectory.create(recursive: true);
    final method = catalog.methods.first;
    final spot = catalog.spots.firstWhere(
      (candidate) => candidate.methodIds.contains(method.id),
    );
    await File(
      '${dataDirectory.path}${Platform.pathSeparator}sessions.json',
    ).writeAsString(
      jsonEncode({
        'schemaVersion': 1,
        'sessions': <Object?>[],
        'preferences': {'methodId': method.id, 'spotId': spot.id},
      }),
    );
    store = SessionStore(directory: dataDirectory);
    await store.load();
  });

  tearDownAll(() async {
    for (final image in representativeArtwork) {
      image.dispose();
    }
    if (await temporaryRoot.exists()) {
      await temporaryRoot.delete(recursive: true);
    }
  });

  testWidgets('real game tool and item artwork decode from package assets', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Row(
          children: [
            RawImage(image: representativeArtwork[0]),
            RawImage(image: representativeArtwork[1]),
          ],
        ),
      ),
    );
    await tester.pump();
    expect(find.byType(RawImage), findsNWidgets(2));
    expect(representativeArtwork[0].width, greaterThan(0));
    expect(representativeArtwork[0].height, greaterThan(0));
    expect(representativeArtwork[1].width, greaterThan(0));
    expect(representativeArtwork[1].height, greaterThan(0));
    expect(tester.takeException(), isNull);
  });

  testWidgets('Gathering header links the visible Bairog source logo', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1500, 940);
    addTearDown(tester.view.reset);

    const nativeChannel = MethodChannel('bdo_gathering/native');
    final openedUrls = <String>[];
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(nativeChannel, (call) async {
      if (call.method != 'openExternal') return null;
      final arguments = (call.arguments! as Map<Object?, Object?>);
      openedUrls.add(arguments['url']! as String);
      return true;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(nativeChannel, null));

    await tester.pumpWidget(
      MaterialApp(
        theme: companionTheme(),
        home: CompanionBackdrop(
          child: CompanionHome(
            catalog: catalog,
            store: store,
            glassOpacityPercent: defaultGlassOpacityPercent,
            onGlassOpacityChanged: (_) {},
            sessionImportReceiptDirectory: _receiptDirectory,
          ),
        ),
      ),
    );
    await tester.pump();

    final source = find.byKey(const ValueKey('open-bairog-source'));
    expect(source, findsOneWidget);
    final sourceLogo = tester.widget<GameIcon>(
      find.descendant(of: source, matching: find.byType(GameIcon)),
    );
    expect(sourceLogo.path, 'assets/icons/sources/bdoworkshop_logo.png');
    expect(sourceLogo.size, 34);
    expect(find.byTooltip('Bairog'), findsOneWidget);

    final sourceSemantics = tester.widget<Semantics>(
      find.byWidgetPredicate(
        (widget) =>
            widget is Semantics &&
            widget.properties.label ==
                'Open Bairog · BDO Workshop gathering calculator',
      ),
    );
    expect(sourceSemantics.properties.link, isTrue);

    final sourceRect = tester.getRect(source);
    expect(source.hitTestable(), findsOneWidget);
    expect(sourceRect.left, greaterThanOrEqualTo(0));
    expect(
      sourceRect.bottom,
      lessThanOrEqualTo(tester.view.physicalSize.height),
    );
    expect(sourceRect.size.shortestSide, greaterThanOrEqualTo(44));
    expect(sourceRect.right, lessThanOrEqualTo(1500));
    expect(find.byKey(const ValueKey('workflow-spots')), findsOneWidget);

    expect(find.text('Bairog', findRichText: true), findsNothing);
    final mouse = await tester.createGesture(kind: ui.PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(tester.getCenter(source));
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(find.text('Bairog', findRichText: true), findsOneWidget);
    expect(
      find.text('Bairog · BDO Workshop source', findRichText: true),
      findsNothing,
    );
    expect(openedUrls, isEmpty, reason: 'Hovering does not open the source.');
    await mouse.removePointer();
    await tester.pumpAndSettle();

    await tester.tap(source);
    await tester.pump();
    expect(openedUrls, <String>[
      'https://bdoworkshop.com/gathering-calculator',
    ]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Gathering header no longer shows the Garmoth Upload shortcut', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1500, 940);
    addTearDown(tester.view.reset);

    const nativeChannel = MethodChannel('bdo_gathering/native');
    final calls = <MethodCall>[];
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(nativeChannel, (call) async {
      calls.add(call);
      return true;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(nativeChannel, null));

    await tester.pumpWidget(
      MaterialApp(
        theme: companionTheme(),
        home: CompanionBackdrop(
          child: CompanionHome(
            catalog: catalog,
            store: store,
            glassOpacityPercent: defaultGlassOpacityPercent,
            onGlassOpacityChanged: (_) {},
            sessionImportReceiptDirectory: _receiptDirectory,
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.byKey(const ValueKey('open-garmoth-upload')), findsNothing);
    expect(find.text('Garmoth Upload'), findsNothing);
    expect(find.byTooltip('Garmoth Upload'), findsNothing);
    expect(find.byKey(const ValueKey('open-minigame-helper')), findsOneWidget);
    expect(find.byTooltip('Help'), findsOneWidget);
    expect(calls, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'Spots, preparation, gathering, and history retain their controls and state',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1500, 940);
      addTearDown(tester.view.reset);

      var outerPage = 0;
      late StateSetter updateOuter;
      final gathering = MaterialApp(
        theme: companionTheme(),
        home: GatheringHostServicesScope(
          services: GatheringHostServices(openExternal: (_) async => true),
          child: CompanionBackdrop(
            child: CompanionHome(
              catalog: catalog,
              store: store,
              glassOpacityPercent: defaultGlassOpacityPercent,
              onGlassOpacityChanged: (_) {},
            ),
          ),
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: StatefulBuilder(
            builder: (context, setState) {
              updateOuter = setState;
              return IndexedStack(
                index: outerPage,
                children: [gathering, const Text('Other workspace')],
              );
            },
          ),
        ),
      );
      await tester.pump();

      expect(find.byKey(const ValueKey('workflow-spots')), findsOneWidget);
      expect(find.byKey(const ValueKey('workflow-prepare')), findsOneWidget);
      expect(find.byKey(const ValueKey('workflow-gather')), findsOneWidget);
      expect(find.text('Journal'), findsOneWidget);
      expect(find.byKey(const ValueKey('spot-list')), findsOneWidget);
      expect(find.byKey(const ValueKey('preparation-summary')), findsOneWidget);
      expect(find.byKey(const ValueKey('paste-screenshot')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('workflow-prepare')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('preparation-stats')), findsOneWidget);
      expect(
        find.byKey(const ValueKey('inline-stats-mastery')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('inline-stats-drop-rate')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('inline-stats-advanced')),
        findsOneWidget,
      );
      await tester.ensureVisible(find.byKey(const ValueKey('record-results')));
      await tester.tap(find.byKey(const ValueKey('record-results')));
      await tester.pumpAndSettle();
      final sessionScroll = find.byKey(const ValueKey('session-scroll'));
      expect(
        tester
            .widget<SingleChildScrollView>(sessionScroll)
            .controller!
            .hasClients,
        isTrue,
      );
      expect(
        find.descendant(of: sessionScroll, matching: find.byType(Scrollbar)),
        findsNothing,
      );
      expect(find.byKey(const ValueKey('paste-screenshot')), findsOneWidget);
      expect(
        find.byKey(const ValueKey('open-minigame-helper')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('open-garmoth-upload')), findsNothing);

      await tester.tap(find.byKey(const ValueKey('workflow-spots')));
      await tester.pumpAndSettle();
      if (find
          .byKey(const ValueKey('spot-ranking-palette'))
          .evaluate()
          .isNotEmpty) {
        await tester.tap(
          find.byKey(const ValueKey('spot-filter-compact-control')),
        );
        await tester.pumpAndSettle();
      }
      expect(
        find.byKey(const ValueKey('spot-guide-layered-layout')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('spot-overview')), findsNothing);
      expect(find.byKey(const ValueKey('expand-spot-map')), findsNothing);
      final initialSpotList = tester.getRect(
        find.byKey(const ValueKey('spot-list')),
      );
      expect(
        find.byKey(const ValueKey('spot-filter-compact-control')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('spot-filter-vertical-label')),
        findsNothing,
      );
      expect(find.byKey(const ValueKey('spot-ranking-palette')), findsNothing);
      expect(
        find.byKey(const ValueKey('spot-ranking-sharp')).hitTestable(),
        findsNothing,
      );
      await tester.tap(
        find.byKey(const ValueKey('spot-filter-compact-control')),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('spot-filter-compact-control')),
        findsOneWidget,
      );
      final rankingPalette = tester.getRect(
        find.byKey(const ValueKey('spot-ranking-palette')),
      );
      expect(rankingPalette.width, greaterThanOrEqualTo(240));
      expect(rankingPalette.width, lessThanOrEqualTo(initialSpotList.width));
      expect(rankingPalette.left, greaterThanOrEqualTo(0));
      expect(rankingPalette.right, lessThanOrEqualTo(1500));
      expect(rankingPalette.bottom, lessThanOrEqualTo(940));
      expect(find.text('DROPS'), findsOneWidget);
      expect(find.text('MARKETPLACE'), findsOneWidget);
      expect(find.text('STAR OF NOSTOS'), findsOneWidget);
      expect(find.byKey(const ValueKey('spot-ranking-sharp')), findsOneWidget);
      expect(find.byKey(const ValueKey('spot-ranking-dust')), findsOneWidget);
      expect(
        find.byKey(const ValueKey('spot-ranking-caphras')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('spot-ranking-profit')), findsOneWidget);
      for (final material in bairogNostosMaterials) {
        expect(
          find.byKey(
            ValueKey<String>('spot-ranking-nostos-${material.itemId}'),
          ),
          findsOneWidget,
        );
      }
      expect(
        find.byKey(const ValueKey('spot-ranking-bairogGuides')),
        findsNothing,
      );
      final lastNostos = find.byKey(
        ValueKey<String>(
          'spot-ranking-nostos-${bairogNostosMaterials.last.itemId}',
        ),
      );
      await tester.ensureVisible(lastNostos);
      final lastNostosRect = tester.getRect(lastNostos);
      expect(lastNostosRect.left, greaterThanOrEqualTo(rankingPalette.left));
      expect(lastNostosRect.right, lessThanOrEqualTo(rankingPalette.right));
      expect(lastNostosRect.top, greaterThanOrEqualTo(rankingPalette.top));
      expect(lastNostosRect.bottom, lessThanOrEqualTo(rankingPalette.bottom));
      final lastNostosLabel = find.descendant(
        of: lastNostos,
        matching: find.text(bairogNostosMaterials.last.name),
      );
      final lastNostosText = tester.widget<Text>(lastNostosLabel);
      expect(lastNostosText.maxLines, isNull);
      expect(lastNostosText.overflow, isNull);
      expect(
        tester.renderObject<RenderParagraph>(lastNostosLabel).didExceedMaxLines,
        isFalse,
      );
      await tester.ensureVisible(
        find.byKey(const ValueKey('spot-ranking-browse')),
      );
      await tester.tap(find.byKey(const ValueKey('spot-ranking-browse')));
      await tester.pumpAndSettle();
      final toolAnchor = tester.widget<MenuAnchor>(
        find
            .ancestor(
              of: find.byKey(const ValueKey('spot-method-filter')),
              matching: find.byType(MenuAnchor),
            )
            .first,
      );
      expect(toolAnchor.useRootOverlay, isTrue);
      final toolTrigger = tester.getRect(
        find.byKey(const ValueKey('spot-method-filter')),
      );
      await tester.tap(find.byKey(const ValueKey('spot-method-filter')));
      await tester.pumpAndSettle();
      final allToolsRect = tester.getRect(find.text('All tools'));
      expect(allToolsRect.left, greaterThanOrEqualTo(0));
      expect(allToolsRect.right, lessThanOrEqualTo(1500));
      expect(allToolsRect.top, greaterThanOrEqualTo(toolTrigger.bottom));
      await tester.tap(find.text('All tools'));
      await tester.pumpAndSettle();
      final browseCards = find.byWidgetPredicate(
        (widget) =>
            widget.key is ValueKey<String> &&
            (widget.key! as ValueKey<String>).value.startsWith('spot-card-'),
      );
      final firstBrowseCard = tester.getRect(browseCards.at(0));
      final secondBrowseCard = tester.getRect(browseCards.at(1));
      expect(secondBrowseCard.left, closeTo(firstBrowseCard.left, .01));
      expect(secondBrowseCard.top, greaterThan(firstBrowseCard.bottom));
      expect(firstBrowseCard.width, greaterThan(300));
      await tester.tap(find.byKey(const ValueKey('spot-ranking-sharp')));
      await tester.pumpAndSettle();
      final rankedSpotList = tester.getRect(
        find.byKey(const ValueKey('spot-list')),
      );
      expect(rankedSpotList.left, closeTo(initialSpotList.left, .01));
      expect(rankedSpotList.top, greaterThan(initialSpotList.top));
      expect(rankedSpotList.width, closeTo(initialSpotList.width, .01));
      expect(rankedSpotList.bottom, closeTo(initialSpotList.bottom, .01));
      expect(find.byKey(const ValueKey('spot-source-personal')), findsNothing);
      expect(find.byKey(const ValueKey('spot-source-bairog')), findsNothing);
      expect(
        find.byKey(const ValueKey('bairog-calculator-link')),
        findsOneWidget,
      );
      expect(find.text('Yield per hour by Bairog.'), findsNothing);
      final sourceLogo = tester.widget<GameIcon>(
        find.descendant(
          of: find.byKey(const ValueKey('bairog-calculator-link')),
          matching: find.byType(GameIcon),
        ),
      );
      expect(sourceLogo.path, 'assets/icons/sources/bdoworkshop_logo.png');
      expect(
        find.ancestor(
          of: find.byKey(const ValueKey('bairog-calculator-link')),
          matching: find.byTooltip('Bairog'),
        ),
        findsOneWidget,
      );
      expect(
        find.text('Yields: Bairog Haan · BDO Workshop · 20 routes'),
        findsNothing,
      );
      final routeCards = find.byWidgetPredicate(
        (widget) =>
            widget.key is ValueKey<String> &&
            (widget.key! as ValueKey<String>).value.startsWith('spot-route-'),
      );
      final firstRouteCard = tester.getRect(routeCards.at(0));
      final secondRouteCard = tester.getRect(routeCards.at(1));
      expect(secondRouteCard.left, closeTo(firstRouteCard.left, .01));
      expect(secondRouteCard.top, greaterThan(firstRouteCard.bottom));
      final firstRouteIcons = tester.widgetList<GameIcon>(
        find.descendant(of: routeCards.at(0), matching: find.byType(GameIcon)),
      );
      expect(firstRouteIcons.any((icon) => icon.size == 44), isTrue);
      expect(
        tester
            .widget<ListView>(find.byKey(const ValueKey('spot-list')))
            .childrenDelegate
            .estimatedChildCount,
        20,
      );
      expect(find.textContaining('gathers/h'), findsWidgets);
      expect(find.text('At 878 gathers/h'), findsOneWidget);
      await tester.tap(
        find.byKey(const ValueKey('spot-filter-compact-control')),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('spot-filter-compact-control')),
        findsOneWidget,
      );
      expect(routeCards, findsWidgets);

      await tester.tap(find.byKey(const ValueKey('spot-route-36')));
      await tester.pumpAndSettle();
      expect(find.text('At 878 gathers/h'), findsOneWidget);
      expect(find.byTooltip('At 878 gathers/h'), findsNothing);

      final useSpot = find.byKey(const ValueKey('use-spot'));
      await tester.ensureVisible(useSpot);
      await tester.tap(useSpot);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('preparation-stats')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('workflow-spots')));
      await tester.pumpAndSettle();
      expect(routeCards, findsWidgets);
      expect(
        tester
            .widget<ListView>(find.byKey(const ValueKey('spot-list')))
            .childrenDelegate
            .estimatedChildCount,
        20,
        reason: 'Returning from Prepare keeps the selected Sharp ranking.',
      );
      expect(
        find.byKey(const ValueKey('spot-ranking-palette')),
        findsNothing,
        reason: 'Returning to Spots retains the collapsed filters.',
      );

      await tester.tap(find.byKey(const ValueKey('workflow-history')));
      await tester.pump();
      expect(find.byKey(const ValueKey('history-filters')), findsOneWidget);

      updateOuter(() => outerPage = 1);
      await tester.pump();
      expect(find.text('Other workspace'), findsOneWidget);
      updateOuter(() => outerPage = 0);
      await tester.pump();
      expect(find.byKey(const ValueKey('history-filters')), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    },
  );
}
