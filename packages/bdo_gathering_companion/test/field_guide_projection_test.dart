import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:bdo_gathering_companion/domain/bairog_benchmarks.dart';
import 'package:bdo_gathering_companion/domain/bairog_calculator.dart';
import 'package:bdo_gathering_companion/domain/models.dart';
import 'package:bdo_gathering_companion/src/services/gathering_market_service.dart';
import 'package:bdo_gathering_companion/src/ui/field_guide.dart';
import 'package:bdo_gathering_companion/src/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

class _OfflineTiles implements HttpClient {
  _OfflineTiles._();

  @override
  Future<HttpClientRequest> getUrl(Uri url) async =>
      throw const HttpException('Offline tile fixture');

  @override
  set connectionTimeout(Duration? value) {}

  @override
  void close({bool force = false}) {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

String _rateText(double value) {
  if (value >= 100) return value.toStringAsFixed(0);
  if (value >= 10) return value.toStringAsFixed(1);
  return value.toStringAsFixed(2);
}

String _silverText(double value) {
  if (value >= 1000000000) {
    return '${(value / 1000000000).toStringAsFixed(2)}B';
  }
  if (value >= 1000000) {
    return '${(value / 1000000).toStringAsFixed(value >= 100000000 ? 0 : 1)}M';
  }
  if (value >= 1000) return '${(value / 1000).toStringAsFixed(0)}K';
  return value.toStringAsFixed(0);
}

String _fullSilverNumber(double value) {
  final rounded = (value * 100).round() / 100;
  final fixed = rounded.abs().toStringAsFixed(2).split('.');
  final digits = fixed[0];
  final first = digits.length % 3;
  final groups = <String>[
    if (first > 0) digits.substring(0, first),
    for (var index = first; index < digits.length; index += 3)
      digits.substring(index, index + 3),
  ];
  final fraction = fixed[1].replaceFirst(RegExp(r'0+$'), '');
  return '${rounded < 0 ? '−' : ''}${groups.join('.')}'
      '${fraction.isEmpty ? '' : ',$fraction'}';
}

Future<void> _pumpUntilCalculationDialog(WidgetTester tester) async {
  final dialog = find.byKey(const ValueKey('market-calculation-dialog'));
  for (var attempt = 0; attempt < 100 && dialog.evaluate().isEmpty; attempt++) {
    await tester.pump(const Duration(milliseconds: 16));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
  }
  expect(dialog, findsOneWidget);
  await tester.pump(const Duration(milliseconds: 250));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Catalog catalog;

  setUpAll(() async {
    catalog = await Catalog.load();
    expect(catalog.bairogCalculatorData, isNotNull);
  });

  testWidgets(
    'finder uses unblurred glass and retains its lazy floating list',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1360, 900);
      addTearDown(tester.view.reset);
      await HttpOverrides.runZoned(() async {
        await tester.pumpWidget(
          MaterialApp(
            theme: companionTheme(),
            home: Scaffold(
              body: FieldGuide(catalog: catalog, onUse: (_) {}),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final journal = find.byKey(const ValueKey('spot-journal-surface'));
        final cards = find.byWidgetPredicate(
          (widget) =>
              widget is GlassControl &&
              widget.key is ValueKey<String> &&
              (widget.key! as ValueKey<String>).value.startsWith('spot-card-'),
        );
        expect(cards, findsWidgets);
        expect(
          find.descendant(of: journal, matching: find.byType(BackdropFilter)),
          findsNothing,
        );
        expect(tester.widget(journal), isA<Padding>());
        for (final card in cards.evaluate()) {
          expect(
            find.descendant(
              of: find.byWidget(card.widget),
              matching: find.byType(BackdropFilter),
            ),
            findsNothing,
          );
        }
        final fullHeight = tester.getSize(journal).height;
        final list = tester.widget<ListView>(
          find.byKey(const ValueKey('spot-list')),
        );
        expect(list.shrinkWrap, isFalse);
        expect(list.childrenDelegate, isA<SliverChildBuilderDelegate>());
        await tester.enterText(
          find.byKey(const ValueKey('spot-search')),
          'no-such-gathering-spot',
        );
        await tester.pumpAndSettle();
        expect(find.text('No matching spots'), findsOneWidget);
        expect(tester.getSize(journal).height, fullHeight);
        expect(tester.getRect(journal).right, lessThan(1360 * .5));
        expect(
          tester.getRect(find.text('No matching spots')).right,
          lessThanOrEqualTo(tester.getRect(journal).right),
        );
        expect(tester.takeException(), isNull);
      }, createHttpClient: (_) => _OfflineTiles._());
    },
  );

  testWidgets('journal filters and tool menu stay readable at doubled text', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1000, 720);
    addTearDown(tester.view.reset);
    await HttpOverrides.runZoned(() async {
      await tester.pumpWidget(
        MaterialApp(
          theme: companionTheme(),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: const TextScaler.linear(2),
              disableAnimations: true,
            ),
            child: child!,
          ),
          home: Scaffold(
            body: FieldGuide(catalog: catalog, onUse: (_) {}),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('spot-filter-compact-control')),
      );
      await tester.pumpAndSettle();
      final filter = find.byKey(const ValueKey('spot-ranking-nostos-821353'));
      await tester.ensureVisible(filter);
      await tester.pumpAndSettle();
      expect(tester.getSize(filter).width, greaterThan(240));
      expect(
        find.descendant(of: filter, matching: find.byType(BackdropFilter)),
        findsNothing,
      );
      await tester.tap(find.byKey(const ValueKey('spot-method-filter')));
      await tester.pumpAndSettle();
      final menuItem = find.widgetWithText(MenuItemButton, 'All tools');
      expect(menuItem, findsOneWidget);
      expect(tester.getSize(menuItem).height, greaterThanOrEqualTo(48));
      expect(tester.getSize(menuItem).width, greaterThan(224));
      expect(tester.getSize(menuItem).width, lessThan(952));
      expect(tester.takeException(), isNull);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
    }, createHttpClient: (_) => _OfflineTiles._());
  });

  test('every Bairog popup contribution has bundled item artwork', () async {
    final data = catalog.bairogCalculatorData!;
    final routeTypeIds = <int>{};
    final contributionTypeIds = <int>{};
    for (final route in data.rotations) {
      routeTypeIds.add(route.gatheringTypeId);
      routeTypeIds.addAll(
        route.typeRatios.map((ratio) => ratio.gatheringTypeId),
      );
      contributionTypeIds.addAll(route.primaryItemRatios?.keys ?? const []);
    }
    for (final drop in data.dropRates) {
      if (routeTypeIds.contains(drop.gatheringTypeId)) {
        contributionTypeIds.add(drop.itemTypeId);
      }
    }
    for (final typeId in routeTypeIds) {
      final gatheringType = data.gatheringTypesById[typeId]!;
      contributionTypeIds
        ..addAll(gatheringType.afuaruItemAverages.keys)
        ..addAll(gatheringType.chestItemAverages.keys)
        ..addAll(gatheringType.feverTimeItemAverages.keys);
    }

    final missingArtwork = <String>[];
    for (final typeId in contributionTypeIds) {
      final item = data.gatheringItemTypesById[typeId]!.item;
      final assetPath = 'assets/icons/items/${item.id}.webp';
      if (!File(assetPath).existsSync()) {
        missingArtwork.add('${item.id} ${item.name}');
        continue;
      }
      expect(assetPath, isNotEmpty, reason: '${item.name} needs an icon path.');
      final codec = await ui.instantiateImageCodec(
        await File(assetPath).readAsBytes(),
      );
      final frame = await codec.getNextFrame();
      expect(
        frame.image.width * frame.image.height,
        greaterThan(0),
        reason: '${item.name} artwork must decode as a real image.',
      );
      frame.image.dispose();
      codec.dispose();
    }

    expect(
      missingArtwork,
      isEmpty,
      reason: 'Popup items must never fall back to route or method artwork.',
    );
    expect(
      data.gatheringItemTypesById[95]!.item.id,
      5020,
      reason: 'The audited Thuja Sap contribution changed unexpectedly.',
    );
    expect(File('assets/icons/items/5020.webp').existsSync(), isTrue);
  });

  testWidgets(
    'Material hover separates its title and preserves every note line',
    (tester) async {
      tester.view
        ..devicePixelRatio = 1
        ..physicalSize = const Size(1500, 940);
      addTearDown(tester.view.reset);
      await HttpOverrides.runZoned(() async {
        await tester.pumpWidget(
          MaterialApp(
            theme: companionTheme(opacityPercent: 0),
            home: Scaffold(
              body: FieldGuide(
                catalog: catalog,
                bairogCalculatorData: catalog.bairogCalculatorData,
                initialFiltersExpanded: true,
                onUse: (_) {},
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.ensureVisible(
          find.byKey(const ValueKey('spot-ranking-sharp')),
        );
        await tester.tap(find.byKey(const ValueKey('spot-ranking-sharp')));
        await tester.enterText(
          find.byKey(const ValueKey('spot-search')),
          'Behr Wild herbs',
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('spot-route-39')));
        await tester.pumpAndSettle();
        final material = find.byKey(const ValueKey('guide-loot-821371'));
        await tester.ensureVisible(material);
        final tooltip = tester.widget<Tooltip>(
          find.ancestor(of: material, matching: find.byType(Tooltip)).first,
        );
        final spans = (tooltip.richMessage! as TextSpan).children!;
        expect(spans.first.toPlainText(), "Fairy's Breath");
        expect((spans.first as TextSpan).style!.fontWeight, FontWeight.w700);
        expect(tooltip.textAlign, TextAlign.left);
        final note = textOf(
          catalog.commonLoot.firstWhere(
            (item) => textOf(item, 'itemId') == '821371',
          ),
          'conditionalNote',
        );
        expect(tooltip.richMessage!.toPlainText(), "Fairy's Breath\n\n$note");
        await tester.tap(material);
        await tester.pumpAndSettle();
        final popup = tester.widget<AlertDialog>(find.byType(AlertDialog));
        expect(popup.scrollable, isTrue);
        for (final line
            in note.split('\n').where((line) => line.trim().isNotEmpty)) {
          expect(find.text(line), findsOneWidget);
        }
        expect(tester.takeException(), isNull);
      }, createHttpClient: (_) => _OfflineTiles._());
    },
  );

  test('Tshira shares one primary yield stream between both meats', () {
    final data = catalog.bairogCalculatorData!;
    final route = data.rotationsById[48]!;
    expect(route.averageGathersPerHour, 749);
    expect(route.primaryItemRatios, <int, double>{97: .3331, 98: .6669});

    final projection = BairogCalculator(
      data,
    ).projectRoute(routeId: 48, settings: const BairogCalculatorSettings());
    final scorpion = projection.bdoItemAmountsPerHour[7924]!;
    final snake = projection.bdoItemAmountsPerHour[7922]!;
    final primaryTotal = scorpion + snake;
    final sourcePrimary = bairogBenchmarkSet.routes
        .firstWhere((benchmark) => benchmark.sourceRouteId == 48)
        .yieldProfile
        .primaryPerHour;

    expect(projection.effectiveGathersPerHour, 749);
    expect(primaryTotal, closeTo(sourcePrimary, .3));
    expect(scorpion, closeTo(primaryTotal * .3331, .001));
    expect(snake, closeTo(primaryTotal * .6669, .001));
    expect(primaryTotal, lessThan(sourcePrimary * 1.01));
  });

  testWidgets(
    'route cards recalculate for setup and state their gathers-per-hour basis',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1500, 940);
      addTearDown(tester.view.reset);

      const baseline = BairogCalculatorSettings();
      const lowerSetup = BairogCalculatorSettings(
        mastery: 1500,
        gatheringDropRatePercent: 0,
        minigameMode: BairogMinigameMode.none,
        hedgehogTier: BairogHedgehogTier.tier4,
        enabledExpenseItemIds: <int>{},
        includeAfuaru: false,
        includeChest: false,
        includeFeverTime: false,
        includeEvergreenShard: false,
      );
      final data = catalog.bairogCalculatorData!;
      final calculator = BairogCalculator(data);
      final baselineSharp = calculator
          .projectRoute(routeId: 36, settings: baseline)
          .bdoItemAmountsPerHour[4998]!;
      final lowerSharp = calculator
          .projectRoute(routeId: 36, settings: lowerSetup)
          .bdoItemAmountsPerHour[4998]!;
      final baselineMetric = '≈${_rateText(baselineSharp)}/h';
      final lowerMetric = '≈${_rateText(lowerSharp)}/h';
      expect(lowerMetric, isNot(baselineMetric));

      var setup = baseline;
      late StateSetter updateHarness;
      await HttpOverrides.runZoned(() async {
        await tester.pumpWidget(
          MaterialApp(
            theme: companionTheme(),
            home: Scaffold(
              body: StatefulBuilder(
                builder: (context, setState) {
                  updateHarness = setState;
                  return FieldGuide(
                    catalog: catalog,
                    bairogCalculatorData: data,
                    bairogSettings: setup,
                    onUse: (_) {},
                  );
                },
              ),
            ),
          ),
        );
        await tester.pump();

        await tester.tap(
          find.byKey(const ValueKey('spot-filter-compact-control')),
        );
        await tester.pumpAndSettle();
        await tester.ensureVisible(
          find.byKey(const ValueKey('spot-ranking-sharp')),
        );
        await tester.tap(find.byKey(const ValueKey('spot-ranking-sharp')));
        await tester.pumpAndSettle();

        final routeCard = find.byKey(const ValueKey('spot-route-36'));
        expect(routeCard, findsOneWidget);
        expect(
          find.descendant(of: routeCard, matching: find.text(baselineMetric)),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: routeCard,
            matching: find.text('At 878 gathers/h'),
          ),
          findsOneWidget,
        );
        expect(
          tester
              .widgetList<Semantics>(
                find.descendant(
                  of: routeCard,
                  matching: find.byType(Semantics),
                ),
              )
              .any(
                (semantics) =>
                    semantics.properties.label?.contains('Normal 5%') == true,
              ),
          isTrue,
        );

        updateHarness(() => setup = lowerSetup);
        await tester.pumpAndSettle();

        expect(routeCard, findsOneWidget);
        expect(
          find.descendant(of: routeCard, matching: find.text(lowerMetric)),
          findsOneWidget,
        );
        expect(
          find.descendant(of: routeCard, matching: find.text(baselineMetric)),
          findsNothing,
        );
        expect(
          find.descendant(
            of: routeCard,
            matching: find.text('At 878 gathers/h'),
          ),
          findsOneWidget,
        );
        expect(
          tester
              .widgetList<Semantics>(
                find.descendant(
                  of: routeCard,
                  matching: find.byType(Semantics),
                ),
              )
              .any(
                (semantics) =>
                    semantics.properties.label?.contains('No minigame') == true,
              ),
          isTrue,
        );
        expect(tester.takeException(), isNull);
      }, createHttpClient: (_) => _OfflineTiles._());
    },
  );

  testWidgets(
    'filtered routes prefer spot portraits, then the gathered material',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1500, 940);
      addTearDown(tester.view.reset);

      await HttpOverrides.runZoned(() async {
        await tester.pumpWidget(
          MaterialApp(
            theme: companionTheme(),
            home: Scaffold(
              body: FieldGuide(
                catalog: catalog,
                bairogCalculatorData: catalog.bairogCalculatorData,
                onUse: (_) {},
              ),
            ),
          ),
        );
        await tester.pump();
        await tester.tap(
          find.byKey(const ValueKey('spot-filter-compact-control')),
        );
        await tester.pumpAndSettle();
        await tester.ensureVisible(
          find.byKey(const ValueKey('spot-ranking-nostos-821349')),
        );
        await tester.tap(
          find.byKey(const ValueKey('spot-ranking-nostos-821349')),
        );
        await tester.pumpAndSettle();

        final ashSapCard = find.byKey(const ValueKey('spot-route-40'));
        await tester.scrollUntilVisible(
          ashSapCard,
          150,
          scrollable: find.descendant(
            of: find.byKey(const ValueKey('spot-list')),
            matching: find.byType(Scrollable),
          ),
        );
        expect(ashSapCard, findsOneWidget);
        expect(
          find.descendant(
            of: ashSapCard,
            matching: find.byWidgetPredicate(
              (widget) =>
                  widget is GameIcon &&
                  widget.path == 'assets/icons/items/5001.webp' &&
                  widget.size == 44,
            ),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: ashSapCard,
            matching: find.byWidgetPredicate(
              (widget) =>
                  widget is GameIcon &&
                  widget.path == 'assets/icons/tools/fluid_collector.webp' &&
                  widget.size == 44,
            ),
          ),
          findsNothing,
        );
        expect(
          find.descendant(
            of: ashSapCard,
            matching: find.byWidgetPredicate(
              (widget) =>
                  widget is GameIcon &&
                  widget.path == 'assets/icons/tools/fluid_collector.webp' &&
                  widget.size == 30,
            ),
          ),
          findsOneWidget,
        );

        final foxSpot = catalog.spots.firstWhere(
          (spot) => spot.id == 'forest-seclusion-foxes',
        );
        final foxCard = find.byKey(const ValueKey('spot-route-43'));
        final listController = tester
            .widget<ListView>(find.byKey(const ValueKey('spot-list')))
            .controller!;
        listController.jumpTo(0);
        await tester.pump();
        await tester.scrollUntilVisible(
          foxCard,
          150,
          scrollable: find.descendant(
            of: find.byKey(const ValueKey('spot-list')),
            matching: find.byType(Scrollable),
          ),
        );
        expect(foxCard, findsOneWidget);
        expect(
          find.descendant(
            of: foxCard,
            matching: find.byWidgetPredicate(
              (widget) =>
                  widget is GameIcon &&
                  widget.path == foxSpot.icon &&
                  widget.size == 44,
            ),
          ),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      }, createHttpClient: (_) => _OfflineTiles._());
    },
  );

  testWidgets(
    'value cards use calculator tax, hidden-drop, custom-price, key, and energy math',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1500, 940);
      addTearDown(tester.view.reset);

      final data = catalog.bairogCalculatorData!;
      final calculator = BairogCalculator(data);
      final raw = calculator.projectRoute(
        routeId: 36,
        settings: const BairogCalculatorSettings(
          enabledExpenseItemIds: <int>{},
        ),
      );
      final customType = raw.items
          .where(
            (item) =>
                item.totalPerHour > 0 &&
                item.itemType.isPrimary &&
                item.itemType.vendorUnitPrice == null,
          )
          .first
          .itemType;
      final hiddenType = raw.items
          .where(
            (item) =>
                !item.itemType.isPrimary &&
                !item.itemType.globalDrop &&
                item.itemType.vendorUnitPrice == null,
          )
          .first
          .itemType;
      final settings = BairogCalculatorSettings(
        mastery: 1850,
        gatheringDropRatePercent: 72,
        hedgehogTier: BairogHedgehogTier.tier4,
        enabledExpenseItemIds: const <int>{589},
        includeChest: true,
        includeEvergreenShard: false,
        hiddenDropItemTypeIds: <int>{hiddenType.id},
        customItemPrices: <int, double>{customType.id: 1234567.5},
        dropTaxed: <int, bool>{customType.id: false},
      );
      final requested = <String, String>{};
      final orderBookCalls = <bool>[];

      await HttpOverrides.runZoned(() async {
        await tester.pumpWidget(
          MaterialApp(
            theme: companionTheme(),
            home: Scaffold(
              body: FieldGuide(
                catalog: catalog,
                bairogCalculatorData: data,
                bairogSettings: settings,
                marketOrderBookLoader:
                    (items, {includePreorders = false}) async {
                      requested.addAll(items);
                      orderBookCalls.add(includePreorders);
                      final fetchedAt = DateTime.utc(2026, 9, 4, 8);
                      return <String, GatheringMarketQuote>{
                        for (final id in items.keys)
                          id: GatheringMarketQuote(
                            itemId: int.parse(id),
                            price: 1000,
                            stock: 1234,
                            preorders: includePreorders ? 5678 : null,
                            fetchedAt: fetchedAt,
                          ),
                      };
                    },
                onUse: (_) {},
              ),
            ),
          ),
        );
        await tester.pump();
        await tester.tap(
          find.byKey(const ValueKey('spot-filter-compact-control')),
        );
        await tester.pumpAndSettle();
        await tester.ensureVisible(
          find.byKey(const ValueKey('spot-ranking-profit')),
        );
        await tester.tap(find.byKey(const ValueKey('spot-ranking-profit')));
        await tester.pumpAndSettle();

        expect(requested, containsPair('44164', 'Gold Key'));
        expect(requested, containsPair('589', 'Energy Potion (Extra Large)'));

        final marketPrices = <int, double>{
          for (final id in requested.keys) int.parse(id): 1000,
        };
        final projection = calculator.projectRoute(
          routeId: 36,
          settings: settings,
          marketPricesByBdoItemId: marketPrices,
        );
        final expected = '${_silverText(projection.netSilverPerHour)}/h';
        final routeCard = find.byKey(const ValueKey('spot-route-36'));
        // Empty gaps now intentionally pass drags through to the map. Move the
        // list's existing controller instead of assuming its centre hits a card.
        final listController = tester
            .widget<ListView>(find.byKey(const ValueKey('spot-list')))
            .controller!;
        for (
          var attempt = 0;
          attempt < 40 && routeCard.evaluate().isEmpty;
          attempt++
        ) {
          listController.jumpTo(
            (listController.offset + 120).clamp(
              0,
              listController.position.maxScrollExtent,
            ),
          );
          await tester.pump();
        }
        await tester.ensureVisible(routeCard);
        await tester.pumpAndSettle();

        expect(routeCard, findsOneWidget);
        expect(
          find.descendant(of: routeCard, matching: find.text(expected)),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: routeCard,
            matching: find.textContaining('Energy items'),
          ),
          findsNothing,
        );
        expect(
          find.descendant(
            of: routeCard,
            matching: find.textContaining('Gold Keys'),
          ),
          findsNothing,
        );
        const compactDetailIds = <int>{
          4998,
          4999,
          821348,
          821349,
          821350,
          821351,
          821352,
          821353,
        };
        final expectedContributionIds = <String>{
          for (final item in projection.items)
            if (item.totalPerHour > 0 &&
                !settings.hiddenDropItemTypeIds.contains(item.itemType.id) &&
                (settings.includeEvergreenShard ||
                    item.itemType.item.id != bairogEvergreenShardItemId) &&
                (item.itemType.isPrimary ||
                    compactDetailIds.contains(item.itemType.item.id)))
              item.itemType.item.id.toString(),
        };
        final contributionRows = find.descendant(
          of: routeCard,
          matching: find.byWidgetPredicate(
            (widget) =>
                widget.key is ValueKey &&
                (widget.key! as ValueKey).value.toString().startsWith(
                      'value-contribution-row-',
                    ) ==
                    true,
          ),
        );
        expect(contributionRows, findsNWidgets(expectedContributionIds.length));
        for (final id in expectedContributionIds) {
          expect(
            find.descendant(
              of: routeCard,
              matching: find.byKey(ValueKey('value-contribution-row-$id')),
            ),
            findsOneWidget,
          );
        }
        final contributionIcons = find.descendant(
          of: routeCard,
          matching: find.byWidgetPredicate(
            (widget) =>
                widget is GameIcon &&
                widget.key is ValueKey &&
                (widget.key! as ValueKey).value.toString().startsWith(
                      'value-contribution-icon-',
                    ) ==
                    true,
          ),
        );
        expect(
          contributionIcons,
          findsNWidgets(expectedContributionIds.length),
        );
        expect(
          tester
              .widgetList<GameIcon>(contributionIcons)
              .every((icon) => icon.size == 24),
          isTrue,
        );
        final loot = find.descendant(
          of: routeCard,
          matching: find.byKey(const ValueKey('value-card-loot')),
        );
        final cardRect = tester.getRect(routeCard);
        final lootRect = tester.getRect(loot);
        expect(lootRect.left, moreOrLessEquals(cardRect.left + 10));
        expect(lootRect.right, moreOrLessEquals(cardRect.right - 10));
        final cardSpotIcon = tester.widget<GameIcon>(
          find
              .descendant(
                of: routeCard,
                matching: find.byWidgetPredicate(
                  (widget) => widget is GameIcon && widget.size == 44,
                ),
              )
              .first,
        );

        final infoButton = find.byKey(
          const ValueKey('value-calculation-info-36'),
        );
        final infoWidget = tester.widget<IconButton>(infoButton);
        expect(
          infoWidget.tooltip,
          'Show calculation for Northwestern Gateway Lizard',
        );
        expect(infoWidget.constraints?.minWidth, greaterThanOrEqualTo(40));
        await tester.ensureVisible(infoButton);
        await tester.pumpAndSettle();
        await tester.tap(infoButton);
        await _pumpUntilCalculationDialog(tester);
        expect(orderBookCalls, contains(true));
        expect(
          find.byKey(const ValueKey('value-calculation-loading-36')),
          findsNothing,
        );
        expect(tester.widget<IconButton>(infoButton).onPressed, isNotNull);
        expect(
          find.byKey(const ValueKey('market-calculation-dialog')),
          findsOneWidget,
        );
        final calculationDialog = find.byKey(
          const ValueKey('market-calculation-dialog'),
        );
        expect(
          find.descendant(
            of: calculationDialog,
            matching: find.byWidgetPredicate(
              (widget) =>
                  widget is GameIcon &&
                  widget.path == cardSpotIcon.path &&
                  widget.size == 42,
            ),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: calculationDialog,
            matching: find.text('Northwestern Gateway Lizard'),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: calculationDialog,
            matching: find.text('Tanning'),
          ),
          findsNothing,
        );
        expect(
          find.descendant(
            of: calculationDialog,
            matching: find.text('Calculation basis'),
          ),
          findsNothing,
        );
        expect(
          find.descendant(
            of: calculationDialog,
            matching: find.byWidgetPredicate(
              (widget) => widget is GameIcon && widget.size == 24,
            ),
          ),
          findsNothing,
        );
        final customItem = projection.items.firstWhere(
          (item) => item.itemType.id == customType.id,
        );
        final customBonusPerHour =
            customItem.totalPerHour - customItem.basePerHour;
        final expectedCustomNet =
            customItem.basePerHour * 1234567.5 +
            customBonusPerHour *
                1234567.5 *
                const BairogCalculatorSettings().marketNetRate;
        final customIncome = find.byKey(
          ValueKey('calculation-income-${customType.item.id}'),
        );
        expect(customIncome, findsOneWidget);
        expect(
          find.descendant(
            of: customIncome,
            matching: find.text(_fullSilverNumber(expectedCustomNet)),
          ),
          findsOneWidget,
        );
        final customSemantics = tester
            .widgetList<Semantics>(
              find.descendant(
                of: customIncome,
                matching: find.byType(Semantics),
              ),
            )
            .firstWhere(
              (widget) =>
                  widget.properties.label?.contains('Value per hour:') == true,
            );
        expect(
          customSemantics.properties.label,
          contains('${_fullSilverNumber(expectedCustomNet)} silver'),
        );
        expect(
          find.descendant(of: customIncome, matching: find.text('Value / h')),
          findsOneWidget,
        );
        expect(
          find.descendant(of: customIncome, matching: find.text('Stock')),
          findsOneWidget,
        );
        final customMarket = tester.widget<Text>(
          find.descendant(
            of: customIncome,
            matching: find.byKey(
              ValueKey('calculation-market-${customType.item.id}'),
            ),
          ),
        );
        expect(customMarket.data, '1.234');
        expect(customMarket.style?.color, muted);
        expect(
          find.descendant(of: customIncome, matching: find.text('5.678')),
          findsNothing,
        );
        expect(
          find.descendant(
            of: customIncome,
            matching: find.byWidgetPredicate(
              (widget) =>
                  widget is GameIcon &&
                  widget.path ==
                      'assets/icons/items/${customType.item.id}.webp' &&
                  widget.size == 34,
            ),
          ),
          findsOneWidget,
        );
        for (final removedLabel in const <String>[
          'Quantity / h',
          'Market price',
          'Custom price',
          'Vendor price',
          'Before tax / h',
          'After tax / h',
          'Market stock',
          'Preorders',
        ]) {
          expect(
            find.descendant(
              of: calculationDialog,
              matching: find.text(removedLabel),
            ),
            findsNothing,
          );
        }
        expect(find.text('Income'), findsNothing);
        expect(find.text('Deductions'), findsNothing);
        expect(find.text('Marketplace tax'), findsNothing);
        expect(
          find.byKey(const ValueKey('calculation-cost-589')),
          findsNothing,
        );
        expect(
          find.byKey(const ValueKey('calculation-cost-44164')),
          findsNothing,
        );
        expect(
          find.byKey(const ValueKey('market-calculation-total-value')),
          findsNothing,
        );
        expect(
          find.byKey(const ValueKey('close-market-calculation')),
          findsNothing,
        );
        expect(tester.takeException(), isNull);
      }, createHttpClient: (_) => _OfflineTiles._());
    },
  );

  testWidgets(
    'Thuja Sap calculation uses item artwork instead of route or method artwork',
    (tester) async {
      tester.view
        ..devicePixelRatio = 1
        ..physicalSize = const Size(1500, 940);
      addTearDown(tester.view.reset);

      await HttpOverrides.runZoned(() async {
        await tester.pumpWidget(
          MaterialApp(
            theme: companionTheme(),
            home: Scaffold(
              body: FieldGuide(
                catalog: catalog,
                bairogCalculatorData: catalog.bairogCalculatorData,
                marketOrderBookLoader:
                    (items, {includePreorders = false}) async {
                      final fetchedAt = DateTime.utc(2026, 9, 4, 9);
                      return <String, GatheringMarketQuote>{
                        for (final id in items.keys)
                          id: GatheringMarketQuote(
                            itemId: int.parse(id),
                            price: 1000,
                            stock: 1234,
                            preorders: includePreorders ? 5678 : null,
                            fetchedAt: fetchedAt,
                          ),
                      };
                    },
                onUse: (_) {},
              ),
            ),
          ),
        );
        await tester.pump();
        await tester.tap(
          find.byKey(const ValueKey('spot-filter-compact-control')),
        );
        await tester.pumpAndSettle();
        await tester.ensureVisible(
          find.byKey(const ValueKey('spot-ranking-profit')),
        );
        await tester.tap(find.byKey(const ValueKey('spot-ranking-profit')));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const ValueKey('spot-search')),
          'Seoul Thuja',
        );
        await tester.pumpAndSettle();

        final routeCard = find.byKey(const ValueKey('spot-route-46'));
        expect(routeCard, findsOneWidget);

        final infoButton = find.byKey(
          const ValueKey('value-calculation-info-46'),
        );
        await tester.ensureVisible(infoButton);
        await tester.tap(infoButton);
        await _pumpUntilCalculationDialog(tester);

        final thujaIncome = find.byKey(
          const ValueKey('calculation-income-5020'),
        );
        expect(thujaIncome, findsOneWidget);
        final thujaIcon = tester.widget<GameIcon>(
          find
              .descendant(of: thujaIncome, matching: find.byType(GameIcon))
              .first,
        );
        expect(thujaIcon.path, 'assets/icons/items/5020.webp');
        expect(thujaIcon.size, 34);
        final expectedQuantity = BairogCalculator(catalog.bairogCalculatorData!)
            .projectRoute(
              routeId: 46,
              settings: const BairogCalculatorSettings(),
            )
            .bdoItemAmountsPerHour[5020]!;
        final quantity = tester.widget<Text>(
          find.byKey(const ValueKey('calculation-quantity-5020')),
        );
        expect(quantity.data, '≈ ${_fullSilverNumber(expectedQuantity)} / h');
        expect(
          tester
              .getTopLeft(
                find.byKey(const ValueKey('calculation-quantity-5020')),
              )
              .dy,
          greaterThan(
            tester
                .getBottomLeft(
                  find.descendant(
                    of: thujaIncome,
                    matching: find.text('Thuja Sap'),
                  ),
                )
                .dy,
          ),
        );
        expect(
          tester
              .widget<GlassSurface>(
                find.byKey(const ValueKey('market-calculation-surface')),
              )
              .reading,
          isTrue,
        );
        expect(
          thujaIcon.path,
          isNot(
            catalog.methods.firstWhere((method) => method.id == 'fluid').icon,
          ),
        );
        expect(File(thujaIcon.path).existsSync(), isTrue);
        expect(tester.takeException(), isNull);
      }, createHttpClient: (_) => _OfflineTiles._());
    },
  );

  testWidgets('Tiny positive projected quantities never display as zero', (
    tester,
  ) async {
    tester.view
      ..devicePixelRatio = 1
      ..physicalSize = const Size(1200, 752);
    addTearDown(tester.view.reset);
    final data = catalog.bairogCalculatorData!;
    final defaults = BairogCalculator(data);
    final positiveDefaults = <double>[
      for (final route in data.rotations)
        ...defaults
            .projectRoute(
              routeId: route.id,
              settings: const BairogCalculatorSettings(),
            )
            .bdoItemAmountsPerHour
            .values
            .where((amount) => amount > 0),
    ]..sort();
    // Keep this real-source audit visible when verifying extremely rare drops.
    debugPrint(
      'Smallest positive default quantity: ${positiveDefaults.first} / h',
    );
    const settings = BairogCalculatorSettings(customGathersPerHour: {46: 1});
    final projection = defaults.projectRoute(routeId: 46, settings: settings);
    final tiny = projection.bdoItemAmountsPerHour.entries
        .where((entry) => entry.value > 0 && entry.value < .01)
        .toList();
    expect(tiny, isNotEmpty);
    await HttpOverrides.runZoned(() async {
      await tester.pumpWidget(
        MaterialApp(
          theme: companionTheme(),
          home: Scaffold(
            body: FieldGuide(
              catalog: catalog,
              bairogCalculatorData: data,
              bairogSettings: settings,
              initialFiltersExpanded: true,
              marketOrderBookLoader:
                  (items, {includePreorders = false}) async => {
                    for (final id in items.keys)
                      id: GatheringMarketQuote(
                        itemId: int.parse(id),
                        price: 1000,
                        stock: 1,
                        preorders: includePreorders ? 0 : null,
                        fetchedAt: DateTime.now().toUtc(),
                      ),
                  },
              onUse: (_) {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.byKey(const ValueKey('spot-ranking-profit')),
      );
      await tester.tap(find.byKey(const ValueKey('spot-ranking-profit')));
      await tester.enterText(
        find.byKey(const ValueKey('spot-search')),
        'Seoul Thuja',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('value-calculation-info-46')));
      await _pumpUntilCalculationDialog(tester);
      for (final item in tiny) {
        expect(
          tester
              .widget<Text>(
                find.byKey(ValueKey('calculation-quantity-${item.key}')),
              )
              .data,
          '< 0,01 / h',
        );
      }
      expect(tester.takeException(), isNull);
    }, createHttpClient: (_) => _OfflineTiles._());
  });

  testWidgets(
    'Demand can sort value within preorder groups without reloading market data',
    (tester) async {
      tester.view
        ..devicePixelRatio = 1
        ..physicalSize = const Size(1500, 940);
      addTearDown(tester.view.reset);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

      final calls = <({bool preorders, Set<String> ids})>[];

      List<String> mountedRouteOrder() {
        const prefix = 'spot-route-';
        return find
            .descendant(
              of: find.byKey(const ValueKey('spot-list')),
              matching: find.byWidgetPredicate(
                (widget) =>
                    widget.key is ValueKey &&
                    (widget.key! as ValueKey).value.toString().startsWith(
                      prefix,
                    ),
              ),
            )
            .evaluate()
            .map(
              (element) => ((element.widget.key! as ValueKey).value as String)
                  .substring(prefix.length),
            )
            .toList(growable: false);
      }

      Future<List<String>> routeOrder() async {
        final list = tester.widget<ListView>(
          find.byKey(const ValueKey('spot-list')),
        );
        final controller = list.controller!;
        final seen = <String>{};
        controller.jumpTo(0);
        await tester.pump();
        for (var step = 0; step < 30; step++) {
          seen.addAll(mountedRouteOrder());
          if (controller.offset >= controller.position.maxScrollExtent) break;
          controller.jumpTo(
            (controller.offset + 100).clamp(
              0,
              controller.position.maxScrollExtent,
            ),
          );
          await tester.pump();
        }
        controller.jumpTo(0);
        await tester.pump();
        return seen.toList();
      }

      await HttpOverrides.runZoned(() async {
        await tester.pumpWidget(
          MaterialApp(
            theme: companionTheme(),
            home: Scaffold(
              body: FieldGuide(
                catalog: catalog,
                bairogCalculatorData: catalog.bairogCalculatorData,
                marketOrderBookLoader:
                    (items, {includePreorders = false}) async {
                      calls.add((
                        preorders: includePreorders,
                        ids: items.keys.toSet(),
                      ));
                      final fetchedAt = DateTime.utc(2026, 9, 4, 9);
                      return <String, GatheringMarketQuote>{
                        for (final id in items.keys)
                          id: GatheringMarketQuote(
                            itemId: int.parse(id),
                            price: switch (id) {
                              '6008' => 10,
                              '6014' => 1000000,
                              '6001' => 20,
                              '6002' => 2000000,
                              _ => 1,
                            },
                            stock: switch (id) {
                              '6008' || '6014' || '6001' => 0,
                              '6002' => 500,
                              _ => 100000,
                            },
                            preorders: includePreorders
                                ? switch (id) {
                                    '6008' => 1000,
                                    '6014' => 10,
                                    _ => 0,
                                  }
                                : null,
                            fetchedAt: fetchedAt,
                          ),
                      };
                    },
                onUse: (_) {},
              ),
            ),
          ),
        );
        await tester.pump();
        await tester.tap(
          find.byKey(const ValueKey('spot-filter-compact-control')),
        );
        await tester.pumpAndSettle();
        await tester.ensureVisible(
          find.byKey(const ValueKey('spot-ranking-demand')),
        );
        await tester.tap(find.byKey(const ValueKey('spot-ranking-demand')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('spot-method-filter')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Tanning'));
        await tester.pumpAndSettle();

        const preorderOrder = <String>['36', '38', '37', '47'];
        const valueWithinDemandOrder = <String>['38', '36', '47', '37'];

        expect(
          find.byKey(const ValueKey('spot-demand-sort-preorders')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('spot-demand-sort-value')),
          findsOneWidget,
        );
        expect(await routeOrder(), orderedEquals(preorderOrder));
        final marketCallCount = calls.length;

        await tester.tap(find.byKey(const ValueKey('spot-demand-sort-value')));
        await tester.pumpAndSettle();
        expect(
          await routeOrder(),
          orderedEquals(valueWithinDemandOrder),
          reason:
              'Positive-preorder spots remain first, then each demand group '
              'uses total spot silver per hour.',
        );
        expect(calls, hasLength(marketCallCount));

        await tester.tap(
          find.byKey(const ValueKey('spot-demand-sort-preorders')),
        );
        await tester.pumpAndSettle();
        expect(await routeOrder(), orderedEquals(preorderOrder));
        expect(calls, hasLength(marketCallCount));

        tester.view.physicalSize = const Size(1200, 752);
        tester.platformDispatcher.textScaleFactorTestValue = 2;
        await tester.pumpAndSettle();
        for (final key in <String>[
          'spot-demand-sort-preorders',
          'spot-demand-sort-value',
        ]) {
          final control = find.byKey(ValueKey(key));
          await tester.ensureVisible(control);
          await tester.pumpAndSettle();
          expect(control.hitTestable(), findsOneWidget);
        }
        expect(tester.takeException(), isNull);
      }, createHttpClient: (_) => _OfflineTiles._());
    },
  );

  testWidgets('calculation details never expose setup-cost rows', (
    tester,
  ) async {
    tester.view
      ..devicePixelRatio = 1
      ..physicalSize = const Size(1200, 752);
    addTearDown(tester.view.reset);

    await HttpOverrides.runZoned(() async {
      await tester.pumpWidget(
        MaterialApp(
          theme: companionTheme(),
          home: Scaffold(
            body: FieldGuide(
              catalog: catalog,
              bairogCalculatorData: catalog.bairogCalculatorData,
              bairogSettings: const BairogCalculatorSettings(
                enabledExpenseItemIds: <int>{589},
                includeChest: false,
                includeChestX10: false,
              ),
              marketPriceLoader: (items) async => <String, int>{
                for (final id in items.keys)
                  if (id != '589') id: 1000,
              },
              onUse: (_) {},
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.tap(
        find.byKey(const ValueKey('spot-filter-compact-control')),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.byKey(const ValueKey('spot-ranking-profit')),
      );
      await tester.tap(find.byKey(const ValueKey('spot-ranking-profit')));
      await tester.pumpAndSettle();

      final routeCard = find.byKey(const ValueKey('spot-route-36'));
      await tester.scrollUntilVisible(
        routeCard,
        120,
        scrollable: find
            .descendant(
              of: find.byKey(const ValueKey('spot-list')),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      final missingCostInfo = find.byKey(
        const ValueKey('value-calculation-info-36'),
      );
      await tester.ensureVisible(missingCostInfo);
      await tester.pumpAndSettle();
      await tester.tap(missingCostInfo);
      await _pumpUntilCalculationDialog(tester);

      final potionCost = find.byKey(const ValueKey('calculation-cost-589'));
      expect(potionCost, findsNothing);
      expect(find.text('Price unavailable'), findsNothing);
      expect(find.text('Not deducted'), findsNothing);
      expect(find.text('Deductions'), findsNothing);
      expect(
        find.byKey(const ValueKey('market-calculation-total-value')),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
    }, createHttpClient: (_) => _OfflineTiles._());
  });

  testWidgets(
    'calculation details retain an unpriced income item without adding it to the card',
    (tester) async {
      tester.view
        ..devicePixelRatio = 1
        ..physicalSize = const Size(1200, 752);
      addTearDown(tester.view.reset);

      await HttpOverrides.runZoned(() async {
        await tester.pumpWidget(
          MaterialApp(
            theme: companionTheme(),
            home: Scaffold(
              body: FieldGuide(
                catalog: catalog,
                bairogCalculatorData: catalog.bairogCalculatorData,
                marketOrderBookLoader:
                    (items, {includePreorders = false}) async {
                      final fetchedAt = DateTime.utc(2026, 9, 4, 9);
                      return <String, GatheringMarketQuote>{
                        for (final id in items.keys)
                          id: GatheringMarketQuote(
                            itemId: int.parse(id),
                            price: id == '6008' ? 0 : 1000,
                            stock: id == '6008' ? 321 : 1000,
                            preorders: includePreorders
                                ? id == '6008'
                                      ? 654
                                      : 0
                                : null,
                            fetchedAt: fetchedAt,
                          ),
                      };
                    },
                onUse: (_) {},
              ),
            ),
          ),
        );
        await tester.pump();
        await tester.tap(
          find.byKey(const ValueKey('spot-filter-compact-control')),
        );
        await tester.pumpAndSettle();
        await tester.ensureVisible(
          find.byKey(const ValueKey('spot-ranking-profit')),
        );
        await tester.tap(find.byKey(const ValueKey('spot-ranking-profit')));
        await tester.pumpAndSettle();

        final routeCard = find.byKey(const ValueKey('spot-route-36'));
        final listController = tester
            .widget<ListView>(find.byKey(const ValueKey('spot-list')))
            .controller!;
        for (
          var attempt = 0;
          attempt < 40 && routeCard.evaluate().isEmpty;
          attempt++
        ) {
          listController.jumpTo(
            (listController.offset + 120).clamp(
              0,
              listController.position.maxScrollExtent,
            ),
          );
          await tester.pump();
        }
        await tester.ensureVisible(routeCard);
        expect(
          find.descendant(
            of: routeCard,
            matching: find.byKey(const ValueKey('value-contribution-row-6008')),
          ),
          findsNothing,
        );
        final missingInfo = find.byKey(
          const ValueKey('value-calculation-info-36'),
        );
        await tester.ensureVisible(missingInfo);
        await tester.pumpAndSettle();
        expect(tester.widget<IconButton>(missingInfo).onPressed, isNotNull);
        await tester.tap(missingInfo);
        await _pumpUntilCalculationDialog(tester);

        final missingIncome = find.byKey(
          const ValueKey('calculation-income-6008'),
        );
        expect(missingIncome, findsOneWidget);
        final expectedQuantity = BairogCalculator(catalog.bairogCalculatorData!)
            .projectRoute(
              routeId: 36,
              settings: const BairogCalculatorSettings(),
            )
            .bdoItemAmountsPerHour[6008]!;
        expect(
          tester
              .widget<Text>(
                find.byKey(const ValueKey('calculation-quantity-6008')),
              )
              .data,
          '≈ ${_fullSilverNumber(expectedQuantity)} / h',
        );
        expect(
          find.descendant(
            of: missingIncome,
            matching: find.text('Lizard Hide'),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: missingIncome,
            matching: find.byWidgetPredicate(
              (widget) =>
                  widget is GameIcon &&
                  widget.path == 'assets/icons/items/6008.webp' &&
                  widget.size == 34,
            ),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: missingIncome,
            matching: find.text('Unavailable'),
          ),
          findsOneWidget,
        );
        final missingSemantics = tester
            .widgetList<Semantics>(
              find.descendant(
                of: missingIncome,
                matching: find.byType(Semantics),
              ),
            )
            .firstWhere(
              (widget) =>
                  widget.properties.label?.contains('Value per hour:') == true,
            );
        expect(
          missingSemantics.properties.label,
          contains('Value per hour: Value unavailable'),
        );
        expect(
          find.descendant(of: missingIncome, matching: find.text('Stock')),
          findsOneWidget,
        );
        final missingMarket = tester.widget<Text>(
          find.descendant(
            of: missingIncome,
            matching: find.byKey(const ValueKey('calculation-market-6008')),
          ),
        );
        expect(missingMarket.data, '321');
        expect(missingMarket.style?.color, muted);
        expect(
          find.descendant(of: missingIncome, matching: find.text('654')),
          findsNothing,
        );
        expect(find.text('Market stock'), findsNothing);
        expect(find.text('Preorders'), findsNothing);
        expect(
          find.byKey(const ValueKey('market-calculation-total-value')),
          findsNothing,
        );
        expect(find.text('Deductions'), findsNothing);
        expect(tester.takeException(), isNull);
      }, createHttpClient: (_) => _OfflineTiles._());
    },
  );

  for (final mode in ['value', 'demand']) {
    testWidgets('$mode shows unknown Market without a vendor market badge', (
      tester,
    ) async {
      tester.view
        ..devicePixelRatio = 1
        ..physicalSize = const Size(1200, 900);
      addTearDown(tester.view.reset);
      final raw =
          jsonDecode(
                File('assets/data/bairog_calculator.json').readAsStringSync(),
              )
              as Map<String, dynamic>;
      // Exercise the vendor guard on a visible primary row. This fixture-only
      // vendor price does not change the production catalogue or item artwork.
      for (final item in raw['gatheringItemTypes'] as List) {
        if ((item['bdo_item'] as Map)['bdo_id'] == 7924) {
          item['only_vendor_price'] = 10000;
        }
      }
      final data = BairogCalculatorData.fromJson(raw);
      await HttpOverrides.runZoned(() async {
        await tester.pumpWidget(
          MaterialApp(
            theme: companionTheme(opacityPercent: 0),
            home: Scaffold(
              body: FieldGuide(
                catalog: catalog,
                bairogCalculatorData: data,
                initialFiltersExpanded: true,
                marketOrderBookLoader:
                    (items, {includePreorders = false}) async => {
                      for (final id in items.keys)
                        id: GatheringMarketQuote(
                          itemId: int.parse(id),
                          price: 100000,
                          stock: null,
                          fetchedAt: DateTime.now().toUtc(),
                        ),
                    },
                onUse: (_) {},
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(
            ValueKey(
              mode == 'value' ? 'spot-ranking-profit' : 'spot-ranking-demand',
            ),
          ),
        );
        await tester.enterText(
          find.byKey(const ValueKey('spot-search')),
          'Tshira',
        );
        await tester.pumpAndSettle();
        final card = find.byKey(const ValueKey('spot-route-48'));
        Finder row(String id) => find.descendant(
          of: card,
          matching: find.byKey(ValueKey('$mode-contribution-row-$id')),
        );
        Finder marketIcon(Finder within) => find.descendant(
          of: within,
          matching: find.byWidgetPredicate(
            (widget) =>
                widget is Icon && widget.icon == Icons.storefront_outlined,
          ),
        );
        for (final id in ['7922', '4998', '4999']) {
          expect(row(id), findsOneWidget);
          final text = tester.widget<Text>(
            find.descendant(
              of: row(id),
              matching: find.byKey(ValueKey('$mode-stock-$id')),
            ),
          );
          expect(text.data, '—');
          expect(text.style?.color, muted);
          expect(tester.widget<Icon>(marketIcon(row(id))).color, muted);
          final tooltip = tester.widget<Tooltip>(
            find.descendant(
              of: row(id),
              matching: find.byKey(
                ValueKey(
                  mode == 'value'
                      ? 'value-stock-tooltip-$id'
                      : 'demand-contribution-tooltip-$id',
                ),
              ),
            ),
          );
          expect(tooltip.message, contains('Stock\nListings\nNot available'));
          expect(tooltip.message, isNot(contains('Marketplace\n')));
        }
        expect(row('7924'), findsOneWidget);
        expect(marketIcon(row('7924')), findsNothing);
        expect(
          find.descendant(
            of: row('7924'),
            matching: find.byKey(ValueKey('$mode-stock-7924')),
          ),
          findsNothing,
        );
        await tester.tap(find.byKey(ValueKey('$mode-calculation-info-48')));
        await _pumpUntilCalculationDialog(tester);
        final unknown = tester.widget<Text>(
          find.byKey(const ValueKey('calculation-market-7922')),
        );
        expect(unknown.data, '—');
        expect(unknown.style?.color, muted);
        expect(tester.takeException(), isNull);
      }, createHttpClient: (_) => _OfflineTiles._());
    });
  }

  testWidgets('Tshira Value card stacks both meat stock rows', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1500, 940);
    addTearDown(tester.view.reset);

    final requested = <String, String>{};
    await HttpOverrides.runZoned(() async {
      await tester.pumpWidget(
        MaterialApp(
          theme: companionTheme(),
          home: Scaffold(
            body: FieldGuide(
              catalog: catalog,
              bairogCalculatorData: catalog.bairogCalculatorData,
              marketQuoteLoader: (items) async {
                requested.addAll(items);
                final fetchedAt = DateTime.utc(2026, 9, 3, 9);
                return <String, GatheringMarketQuote>{
                  for (final entry in items.entries)
                    entry.key: GatheringMarketQuote(
                      itemId: int.parse(entry.key),
                      price: switch (entry.key) {
                        '4998' => 4800000,
                        '7922' => 30000,
                        '7924' => 30000,
                        _ => 1000,
                      },
                      stock: switch (entry.key) {
                        '4998' => 320,
                        '7922' => 1234567,
                        '7924' => 0,
                        _ => 100000,
                      },
                      fetchedAt: fetchedAt,
                    ),
                };
              },
              onUse: (_) {},
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.tap(
        find.byKey(const ValueKey('spot-filter-compact-control')),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.byKey(const ValueKey('spot-ranking-profit')),
      );
      await tester.tap(find.byKey(const ValueKey('spot-ranking-profit')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('spot-search')),
        'Tshira',
      );
      await tester.pumpAndSettle();

      expect(requested, containsPair('7922', 'Snake Meat'));
      expect(requested, containsPair('7924', 'Scorpion Meat'));
      final routeCard = find.byKey(const ValueKey('spot-route-48'));
      expect(routeCard, findsOneWidget);
      expect(
        find.descendant(
          of: routeCard,
          matching: find.byKey(const ValueKey('value-contribution-name-7922')),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: routeCard,
          matching: find.byKey(const ValueKey('value-contribution-name-7924')),
        ),
        findsOneWidget,
      );
      final snakeStockFinder = find.descendant(
        of: routeCard,
        matching: find.byKey(const ValueKey('value-stock-7922')),
      );
      final scorpionStockFinder = find.descendant(
        of: routeCard,
        matching: find.byKey(const ValueKey('value-stock-7924')),
      );
      final sharpStockFinder = find.descendant(
        of: routeCard,
        matching: find.byKey(const ValueKey('value-stock-4998')),
      );
      expect(snakeStockFinder, findsOneWidget);
      expect(scorpionStockFinder, findsOneWidget);
      expect(sharpStockFinder, findsOneWidget);
      final snakeStock = tester.widget<Text>(snakeStockFinder);
      final scorpionStock = tester.widget<Text>(scorpionStockFinder);
      expect(snakeStock.data, '1.2M');
      expect(snakeStock.style?.color, muted);
      expect(scorpionStock.data, '0');
      expect(scorpionStock.style?.color, muted);
      final snakeRow = find.descendant(
        of: routeCard,
        matching: find.byKey(const ValueKey('value-contribution-row-7922')),
      );
      final scorpionRow = find.descendant(
        of: routeCard,
        matching: find.byKey(const ValueKey('value-contribution-row-7924')),
      );
      expect(
        find.descendant(
          of: routeCard,
          matching: find.byKey(const ValueKey('value-primary-pair-7922-7924')),
        ),
        findsNothing,
      );
      expect(
        tester.getRect(snakeRow).bottom,
        lessThanOrEqualTo(tester.getRect(scorpionRow).top),
      );
      final semantics = tester.widget<Semantics>(
        find.descendant(
          of: routeCard,
          matching: find.byWidgetPredicate(
            (widget) =>
                widget is Semantics &&
                (widget.key as ValueKey?)?.value.toString().startsWith(
                      'value-card-semantics-',
                    ) ==
                    true,
          ),
        ),
      );
      expect(semantics.properties.label, contains('Snake Meat'));
      expect(semantics.properties.label, contains('Current stock: 1.234.567'));
      expect(semantics.properties.label, contains('Scorpion Meat'));
      expect(tester.takeException(), isNull);
    }, createHttpClient: (_) => _OfflineTiles._());
  });

  testWidgets(
    'Tshira stacked Value stock stays readable at minimum size and 200% text',
    (tester) async {
      tester.view
        ..devicePixelRatio = 1
        ..physicalSize = const Size(1200, 752);
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.view.reset);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

      var includeStock = false;
      await HttpOverrides.runZoned(() async {
        await tester.pumpWidget(
          MaterialApp(
            theme: companionTheme(),
            home: Scaffold(
              body: FieldGuide(
                catalog: catalog,
                bairogCalculatorData: catalog.bairogCalculatorData,
                marketQuoteLoader: (items) async {
                  final fetchedAt = DateTime.utc(2026, 9, 3, 9);
                  return <String, GatheringMarketQuote>{
                    for (final entry in items.entries)
                      entry.key: GatheringMarketQuote(
                        itemId: int.parse(entry.key),
                        price: switch (entry.key) {
                          '4998' => 4800000,
                          '7922' || '7924' => 30000,
                          _ => 1000,
                        },
                        stock: includeStock
                            ? switch (entry.key) {
                                '4998' => 320,
                                '7922' => 1234567,
                                '7924' => 0,
                                _ => 100000,
                              }
                            : null,
                        fetchedAt: fetchedAt,
                      ),
                  };
                },
                onUse: (_) {},
              ),
            ),
          ),
        );
        await tester.pump();
        await tester.tap(
          find.byKey(const ValueKey('spot-filter-compact-control')),
        );
        await tester.pumpAndSettle();
        await tester.ensureVisible(
          find.byKey(const ValueKey('spot-ranking-profit')),
        );
        await tester.tap(find.byKey(const ValueKey('spot-ranking-profit')));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const ValueKey('spot-search')),
          'Tshira',
        );
        await tester.pumpAndSettle();

        final routeCard = find.byKey(const ValueKey('spot-route-48'));
        expect(routeCard, findsOneWidget);
        final heightWithoutStock = tester.getSize(routeCard).height;
        expect(tester.takeException(), isNull);

        includeStock = true;
        await tester.tap(find.byKey(const ValueKey('spot-market-refresh')));
        await tester.pumpAndSettle();

        expect(
          find.descendant(
            of: routeCard,
            matching: find.byKey(
              const ValueKey('value-contribution-name-7922'),
            ),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: routeCard,
            matching: find.byKey(
              const ValueKey('value-contribution-name-7924'),
            ),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: routeCard,
            matching: find.byKey(const ValueKey('value-stock-7922')),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: routeCard,
            matching: find.byKey(const ValueKey('value-stock-7924')),
          ),
          findsOneWidget,
        );
        final snakeTooltip = tester.widget<Tooltip>(
          find.descendant(
            of: routeCard,
            matching: find.byKey(const ValueKey('value-stock-tooltip-7922')),
          ),
        );
        final scorpionTooltip = tester.widget<Tooltip>(
          find.descendant(
            of: routeCard,
            matching: find.byKey(const ValueKey('value-stock-tooltip-7924')),
          ),
        );
        expect(snakeTooltip.message, contains('1.234.567'));
        expect(scorpionTooltip.message, endsWith('\nNot available'));
        final snakeRow = find.descendant(
          of: routeCard,
          matching: find.byKey(const ValueKey('value-contribution-row-7922')),
        );
        final scorpionRow = find.descendant(
          of: routeCard,
          matching: find.byKey(const ValueKey('value-contribution-row-7924')),
        );
        expect(
          find.descendant(
            of: routeCard,
            matching: find.byKey(
              const ValueKey('value-primary-pair-7922-7924'),
            ),
          ),
          findsNothing,
        );
        expect(
          tester.getRect(snakeRow).bottom,
          lessThanOrEqualTo(tester.getRect(scorpionRow).top),
        );
        expect(
          tester.getSize(routeCard).height,
          lessThanOrEqualTo(heightWithoutStock),
        );
        expect(tester.takeException(), isNull);
      }, createHttpClient: (_) => _OfflineTiles._());
    },
  );

  testWidgets(
    'Value loads only zero-stock preorders and never paints stale demand red',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1500, 940);
      addTearDown(tester.view.reset);

      var failPreorders = false;
      final calls = <({bool preorders, Set<String> ids})>[];
      await HttpOverrides.runZoned(() async {
        await tester.pumpWidget(
          MaterialApp(
            theme: companionTheme(),
            home: Scaffold(
              body: FieldGuide(
                catalog: catalog,
                bairogCalculatorData: catalog.bairogCalculatorData,
                marketOrderBookLoader:
                    (items, {includePreorders = false}) async {
                      calls.add((
                        preorders: includePreorders,
                        ids: items.keys.toSet(),
                      ));
                      final fetchedAt = DateTime.utc(2026, 9, 3, 9);
                      return <String, GatheringMarketQuote>{
                        for (final id in items.keys)
                          id: GatheringMarketQuote(
                            itemId: int.parse(id),
                            price: switch (id) {
                              '7913' => 120000,
                              '4998' => 4800000,
                              '4999' => 200000,
                              _ => 1,
                            },
                            stock: switch (id) {
                              '7913' || '4999' => 0,
                              '4998' => 4231,
                              _ => 100000,
                            },
                            preorders: includePreorders && !failPreorders
                                ? switch (id) {
                                    '7913' => 1000,
                                    '4999' => 0,
                                    _ => 0,
                                  }
                                : null,
                            fetchedAt: fetchedAt,
                          ),
                      };
                    },
                onUse: (_) {},
              ),
            ),
          ),
        );
        await tester.pump();
        await tester.tap(
          find.byKey(const ValueKey('spot-filter-compact-control')),
        );
        await tester.pumpAndSettle();
        await tester.ensureVisible(
          find.byKey(const ValueKey('spot-ranking-profit')),
        );
        await tester.tap(find.byKey(const ValueKey('spot-ranking-profit')));
        await tester.pumpAndSettle();

        final baseCalls = calls.where((call) => !call.preorders).toList();
        final preorderCalls = calls.where((call) => call.preorders).toList();
        expect(baseCalls, hasLength(1));
        expect(baseCalls.single.ids, containsAll(<String>['589', '44164']));
        expect(preorderCalls, hasLength(1));
        expect(preorderCalls.single.ids, <String>{'4999', '7913'});

        final routeCard = find.byKey(const ValueKey('spot-route-17'));
        await tester.scrollUntilVisible(
          routeCard,
          120,
          scrollable: find
              .descendant(
                of: find.byKey(const ValueKey('spot-list')),
                matching: find.byType(Scrollable),
              )
              .first,
        );
        await tester.pumpAndSettle();

        Text marketCount(String id) => tester.widget<Text>(
          find.descendant(
            of: routeCard,
            matching: find.byKey(ValueKey('value-stock-$id')),
          ),
        );
        Color? marketIconColor(String id) => tester
            .widget<Icon>(
              find.descendant(
                of: find.descendant(
                  of: routeCard,
                  matching: find.byKey(ValueKey('value-contribution-row-$id')),
                ),
                matching: find.byWidgetPredicate(
                  (widget) =>
                      widget is Icon &&
                      widget.icon == Icons.storefront_outlined,
                ),
              ),
            )
            .color;

        final error = Theme.of(tester.element(routeCard)).colorScheme.error;
        expect(marketCount('4998').data, '4.231');
        expect(marketCount('4998').style?.color, muted);
        expect(marketCount('7913').data, '−1.000');
        expect(marketCount('7913').style?.color, error);
        expect(marketCount('4999').data, '0');
        expect(marketCount('4999').style?.color, muted);
        expect(marketIconColor('4998'), muted);
        expect(marketIconColor('7913'), error);
        expect(marketIconColor('4999'), muted);

        failPreorders = true;
        await tester.tap(find.byKey(const ValueKey('spot-market-refresh')));
        await tester.pumpAndSettle();

        expect(calls.where((call) => call.preorders), hasLength(2));
        expect(marketCount('7913').data, '0');
        expect(marketCount('7913').style?.color, muted);
        expect(marketIconColor('7913'), muted);
        final partialTooltip = tester.widget<Tooltip>(
          find.descendant(
            of: routeCard,
            matching: find.byKey(const ValueKey('value-stock-tooltip-7913')),
          ),
        );
        expect(partialTooltip.message, endsWith('\nNot available'));
        final semantics = tester.widget<Semantics>(
          find.descendant(
            of: routeCard,
            matching: find.byWidgetPredicate(
              (widget) =>
                  widget is Semantics &&
                  (widget.key as ValueKey?)?.value.toString().startsWith(
                        'value-card-semantics-',
                      ) ==
                      true,
            ),
          ),
        );
        expect(
          semantics.properties.label,
          contains('Preorder count is unavailable'),
        );
        expect(tester.takeException(), isNull);
      }, createHttpClient: (_) => _OfflineTiles._());
    },
  );

  testWidgets(
    'calculation Market keeps known zero neutral and rejects stale coverage',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1500, 940);
      addTearDown(tester.view.reset);

      var partialRefresh = false;
      await HttpOverrides.runZoned(() async {
        await tester.pumpWidget(
          MaterialApp(
            theme: companionTheme(),
            home: Scaffold(
              body: FieldGuide(
                catalog: catalog,
                bairogCalculatorData: catalog.bairogCalculatorData,
                marketOrderBookLoader:
                    (items, {includePreorders = false}) async {
                      final fetchedAt = DateTime.utc(2026, 9, 4, 9);
                      if (partialRefresh) {
                        if (includePreorders || !items.containsKey('7913')) {
                          return const <String, GatheringMarketQuote>{};
                        }
                        return <String, GatheringMarketQuote>{
                          '7913': GatheringMarketQuote(
                            itemId: 7913,
                            price: 120000,
                            stock: 0,
                            fetchedAt: fetchedAt,
                          ),
                        };
                      }
                      return <String, GatheringMarketQuote>{
                        for (final id in items.keys)
                          id: GatheringMarketQuote(
                            itemId: int.parse(id),
                            price: switch (id) {
                              '7913' => 120000,
                              '4998' => 4800000,
                              _ => 1000,
                            },
                            stock: switch (id) {
                              '7913' => 0,
                              '4998' => 4231,
                              _ => 100000,
                            },
                            preorders: includePreorders
                                ? id == '7913'
                                      ? 1000
                                      : 0
                                : null,
                            fetchedAt: fetchedAt,
                          ),
                      };
                    },
                onUse: (_) {},
              ),
            ),
          ),
        );
        await tester.pump();
        await tester.tap(
          find.byKey(const ValueKey('spot-filter-compact-control')),
        );
        await tester.pumpAndSettle();
        await tester.ensureVisible(
          find.byKey(const ValueKey('spot-ranking-profit')),
        );
        await tester.tap(find.byKey(const ValueKey('spot-ranking-profit')));
        await tester.pumpAndSettle();

        partialRefresh = true;
        await tester.tap(find.byKey(const ValueKey('spot-market-refresh')));
        await tester.pumpAndSettle();

        final infoButton = find.byKey(
          const ValueKey('value-calculation-info-17'),
        );
        await tester.scrollUntilVisible(
          infoButton,
          120,
          scrollable: find
              .descendant(
                of: find.byKey(const ValueKey('spot-list')),
                matching: find.byType(Scrollable),
              )
              .first,
        );
        await tester.pumpAndSettle();
        await tester.tap(infoButton);
        await _pumpUntilCalculationDialog(tester);

        Text calculationMarket(String id) =>
            tester.widget<Text>(find.byKey(ValueKey('calculation-market-$id')));

        final zeroStockWithoutPreorders = calculationMarket('7913');
        expect(zeroStockWithoutPreorders.data, '0');
        expect(zeroStockWithoutPreorders.style?.color, muted);
        expect(zeroStockWithoutPreorders.data, isNot(startsWith('−')));
        final zeroStockSemantics = tester.widget<Semantics>(
          find.descendant(
            of: find.byKey(const ValueKey('calculation-income-7913')),
            matching: find.byWidgetPredicate(
              (widget) =>
                  widget is Semantics &&
                  widget.properties.label?.contains('Value per hour:') == true,
            ),
          ),
        );
        expect(
          zeroStockSemantics.properties.label,
          contains('Stock: 0. Preorder information unavailable.'),
          reason:
              'Known zero listings must not claim a known zero preorder count.',
        );

        final retainedStockAfterFailedBase = calculationMarket('4998');
        expect(retainedStockAfterFailedBase.data, '—');
        expect(retainedStockAfterFailedBase.style?.color, muted);
        expect(retainedStockAfterFailedBase.style?.color, isNot(positive));
        expect(tester.takeException(), isNull);
      }, createHttpClient: (_) => _OfflineTiles._());
    },
  );

  testWidgets('Value to Demand escalates an in-flight market request', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1500, 940);
    addTearDown(tester.view.reset);

    final firstBase = Completer<void>();
    var blockFirstBase = true;
    final calls = <({bool preorders, Set<String> ids})>[];
    await HttpOverrides.runZoned(() async {
      await tester.pumpWidget(
        MaterialApp(
          theme: companionTheme(),
          home: Scaffold(
            body: FieldGuide(
              catalog: catalog,
              bairogCalculatorData: catalog.bairogCalculatorData,
              marketOrderBookLoader: (items, {includePreorders = false}) async {
                calls.add((
                  preorders: includePreorders,
                  ids: items.keys.toSet(),
                ));
                if (!includePreorders && blockFirstBase) {
                  blockFirstBase = false;
                  await firstBase.future;
                }
                final fetchedAt = DateTime.utc(2026, 9, 3, 9);
                return <String, GatheringMarketQuote>{
                  for (final id in items.keys)
                    id: GatheringMarketQuote(
                      itemId: int.parse(id),
                      price: 1000,
                      stock: id == '7913' ? 0 : 100000,
                      preorders: includePreorders ? 0 : null,
                      fetchedAt: fetchedAt,
                    ),
                };
              },
              onUse: (_) {},
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.tap(
        find.byKey(const ValueKey('spot-filter-compact-control')),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.byKey(const ValueKey('spot-ranking-profit')),
      );
      await tester.tap(find.byKey(const ValueKey('spot-ranking-profit')));
      await tester.pump();
      expect(calls, hasLength(1));
      expect(calls.single.ids, containsAll(<String>['589', '44164']));

      await tester.ensureVisible(
        find.byKey(const ValueKey('spot-ranking-demand')),
      );
      await tester.tap(find.byKey(const ValueKey('spot-ranking-demand')));
      await tester.pump();
      firstBase.complete();
      await tester.pumpAndSettle();

      final preorderIds = calls
          .where((call) => call.preorders)
          .expand((call) => call.ids)
          .toSet();
      expect(preorderIds, containsAll(<String>['7913', '4998']));
      expect(tester.takeException(), isNull);
    }, createHttpClient: (_) => _OfflineTiles._());
  });

  testWidgets('Demand to Value keeps the Value expense-price scope', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1500, 940);
    addTearDown(tester.view.reset);

    final firstBase = Completer<void>();
    var blockFirstBase = true;
    final calls = <({bool preorders, Set<String> ids})>[];
    await HttpOverrides.runZoned(() async {
      await tester.pumpWidget(
        MaterialApp(
          theme: companionTheme(),
          home: Scaffold(
            body: FieldGuide(
              catalog: catalog,
              bairogCalculatorData: catalog.bairogCalculatorData,
              marketOrderBookLoader: (items, {includePreorders = false}) async {
                calls.add((
                  preorders: includePreorders,
                  ids: items.keys.toSet(),
                ));
                if (!includePreorders && blockFirstBase) {
                  blockFirstBase = false;
                  await firstBase.future;
                }
                final fetchedAt = DateTime.utc(2026, 9, 3, 9);
                return <String, GatheringMarketQuote>{
                  for (final id in items.keys)
                    id: GatheringMarketQuote(
                      itemId: int.parse(id),
                      price: 1000,
                      stock: id == '7913' ? 0 : 100000,
                      preorders: includePreorders ? 0 : null,
                      fetchedAt: fetchedAt,
                    ),
                };
              },
              onUse: (_) {},
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.tap(
        find.byKey(const ValueKey('spot-filter-compact-control')),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.byKey(const ValueKey('spot-ranking-demand')),
      );
      await tester.tap(find.byKey(const ValueKey('spot-ranking-demand')));
      await tester.pump();
      expect(calls, hasLength(1));

      await tester.ensureVisible(
        find.byKey(const ValueKey('spot-ranking-profit')),
      );
      await tester.tap(find.byKey(const ValueKey('spot-ranking-profit')));
      await tester.pump();
      firstBase.complete();
      await tester.pumpAndSettle();

      final baseIds = calls
          .where((call) => !call.preorders)
          .expand((call) => call.ids)
          .toSet();
      expect(baseIds, containsAll(<String>['589', '44164']));
      expect(find.byKey(const ValueKey('spot-ranking-profit')), findsOneWidget);
      expect(tester.takeException(), isNull);
    }, createHttpClient: (_) => _OfflineTiles._());
  });

  testWidgets(
    'Value and Demand share compact route drops while details retain all income',
    (tester) async {
      tester.view
        ..devicePixelRatio = 1
        ..physicalSize = const Size(1200, 752);
      addTearDown(tester.view.reset);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

      final requested = <String, String>{};
      int priceFor(String id) => switch (id) {
        '5960' => 100000,
        '5439' => 10000,
        '4998' => 5000000,
        '589' => 21400000,
        '44164' => 3000000,
        _ => 1,
      };
      int stockFor(String id) => switch (id) {
        '5960' => 57089,
        '5439' => 123456,
        '4998' || '4999' => 0,
        _ => 100000,
      };
      int preordersFor(String id) => switch (id) {
        '5960' => 560907,
        '4998' => 24163,
        _ => 0,
      };

      await HttpOverrides.runZoned(() async {
        await tester.pumpWidget(
          MaterialApp(
            theme: companionTheme(),
            home: Scaffold(
              body: FieldGuide(
                catalog: catalog,
                bairogCalculatorData: catalog.bairogCalculatorData,
                marketOrderBookLoader:
                    (items, {includePreorders = false}) async {
                      requested.addAll(items);
                      final fetchedAt = DateTime.utc(2026, 9, 3, 9);
                      return <String, GatheringMarketQuote>{
                        for (final id in items.keys)
                          id: GatheringMarketQuote(
                            itemId: int.parse(id),
                            price: priceFor(id),
                            stock: stockFor(id),
                            preorders: includePreorders
                                ? preordersFor(id)
                                : null,
                            fetchedAt: fetchedAt,
                          ),
                      };
                    },
                onUse: (_) {},
              ),
            ),
          ),
        );
        await tester.pump();
        await tester.tap(
          find.byKey(const ValueKey('spot-filter-compact-control')),
        );
        await tester.pumpAndSettle();
        await tester.ensureVisible(
          find.byKey(const ValueKey('spot-ranking-demand')),
        );
        await tester.tap(find.byKey(const ValueKey('spot-ranking-demand')));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const ValueKey('spot-search')),
          'Behr Wild herbs',
        );
        await tester.pumpAndSettle();

        final routeCard = find.byKey(const ValueKey('spot-route-39'));
        expect(routeCard, findsOneWidget);
        expect(requested, containsPair('589', 'Energy Potion (Extra Large)'));
        expect(requested, containsPair('44164', 'Gold Key'));
        final expectedProjection =
            BairogCalculator(catalog.bairogCalculatorData!).projectRoute(
              routeId: 39,
              settings: const BairogCalculatorSettings(),
              marketPricesByBdoItemId: <int, double>{
                for (final id in requested.keys)
                  int.parse(id): priceFor(id).toDouble(),
              },
            );
        expect(
          expectedProjection.netSilverPerHour,
          lessThan(expectedProjection.totalSilverPerHour),
        );
        expect(
          find.descendant(
            of: routeCard,
            matching: find.text(
              '${_silverText(expectedProjection.netSilverPerHour)}/h',
            ),
          ),
          findsOneWidget,
        );
        final amountsByItemId = <int, double>{};
        final itemTypesByItemId = <int, BairogGatheringItemType>{};
        for (final item in expectedProjection.items) {
          if (item.totalPerHour <= 0) continue;
          final itemId = item.itemType.item.id;
          itemTypesByItemId.putIfAbsent(itemId, () => item.itemType);
          amountsByItemId.update(
            itemId,
            (value) => value + item.totalPerHour,
            ifAbsent: () => item.totalPerHour,
          );
        }
        final expectedContributions =
            <({String id, String name, double perHour, double value})>[
              for (final entry in amountsByItemId.entries)
                (
                  id: entry.key.toString(),
                  name: itemTypesByItemId[entry.key]!.item.name,
                  perHour: entry.value,
                  value:
                      entry.value *
                      (itemTypesByItemId[entry.key]!.vendorUnitPrice ??
                          priceFor(entry.key.toString())) *
                      (itemTypesByItemId[entry.key]!.vendorUnitPrice == null
                          ? const BairogCalculatorSettings().marketNetRate
                          : 1),
                ),
            ]..sort((a, b) {
              final value = b.value.compareTo(a.value);
              if (value != 0) return value;
              final rate = b.perHour.compareTo(a.perHour);
              if (rate != 0) return rate;
              final name = a.name.compareTo(b.name);
              if (name != 0) return name;
              return a.id.compareTo(b.id);
            });
        const compactDetailIds = <String>[
          '821348',
          '821349',
          '821350',
          '821351',
          '821352',
          '821353',
          '4998',
          '4999',
        ];
        final positiveIds = <String>{
          for (final contribution in expectedContributions)
            if (contribution.perHour > 0 && contribution.value > 0)
              contribution.id,
        };
        final primaryIds = <String>{
          for (final item in expectedProjection.items)
            if (item.totalPerHour > 0 && item.itemType.isPrimary)
              item.itemType.item.id.toString(),
        };
        final expectedCompactIds = <String>[
          for (final id in primaryIds)
            if (positiveIds.contains(id)) id,
          for (final id in compactDetailIds)
            if (positiveIds.contains(id) && !primaryIds.contains(id)) id,
        ];

        List<String> visibleContributionIds(String prefix, Finder card) {
          final keyPrefix = '$prefix-contribution-row-';
          return find
              .descendant(
                of: card,
                matching: find.byWidgetPredicate(
                  (widget) =>
                      widget.key is ValueKey &&
                      (widget.key! as ValueKey).value.toString().startsWith(
                        keyPrefix,
                      ),
                ),
              )
              .evaluate()
              .map(
                (element) => ((element.widget.key! as ValueKey).value as String)
                    .substring(keyPrefix.length),
              )
              .toList(growable: false);
        }

        final demandCompactIds = visibleContributionIds('demand', routeCard);
        expect(demandCompactIds, orderedEquals(expectedCompactIds));
        expect(
          find.descendant(
            of: routeCard,
            matching: find.byKey(
              const ValueKey('demand-contribution-row-5960'),
            ),
          ),
          findsNothing,
        );
        for (final entry in const <String, String>{
          '5439': 'Wild Grass',
          '4998': 'Sharp Black Crystal Shard',
          '4999': 'Black Gem Fragment',
        }.entries) {
          expect(
            find.descendant(
              of: routeCard,
              matching: find.byKey(
                ValueKey('demand-contribution-row-${entry.key}'),
              ),
            ),
            findsOneWidget,
          );
          expect(
            find.descendant(of: routeCard, matching: find.text(entry.value)),
            findsOneWidget,
          );
        }
        final rows = find.descendant(
          of: routeCard,
          matching: find.byWidgetPredicate(
            (widget) =>
                widget.key is ValueKey &&
                (widget.key! as ValueKey).value.toString().startsWith(
                  'demand-contribution-row-',
                ),
          ),
        );
        expect(rows, findsNWidgets(expectedCompactIds.length));
        final icons = find.descendant(
          of: routeCard,
          matching: find.byWidgetPredicate(
            (widget) =>
                widget is GameIcon &&
                widget.key is ValueKey &&
                (widget.key! as ValueKey).value.toString().startsWith(
                  'demand-contribution-icon-',
                ),
          ),
        );
        expect(icons, findsNWidgets(expectedCompactIds.length));
        expect(
          tester.widgetList<GameIcon>(icons).every((icon) => icon.size == 24),
          isTrue,
        );

        expect(
          find.descendant(
            of: routeCard,
            matching: find.byKey(const ValueKey('demand-stock-5960')),
          ),
          findsNothing,
        );
        expect(
          find.descendant(
            of: routeCard,
            matching: find.byKey(const ValueKey('demand-preorders-5960')),
          ),
          findsNothing,
        );
        final loot = find.descendant(
          of: routeCard,
          matching: find.byKey(const ValueKey('demand-card-loot')),
        );
        final cardRect = tester.getRect(routeCard);
        final lootRect = tester.getRect(loot);
        expect(lootRect.left, moreOrLessEquals(cardRect.left + 10));
        expect(lootRect.right, moreOrLessEquals(cardRect.right - 10));
        final demandLastRow = find.descendant(
          of: routeCard,
          matching: find.byKey(
            ValueKey('demand-contribution-row-${expectedCompactIds.last}'),
          ),
        );
        expect(
          tester.getBottomRight(demandLastRow).dy,
          lessThanOrEqualTo(cardRect.bottom),
        );
        expect(
          find.descendant(
            of: routeCard,
            matching: find.textContaining('Energy items'),
          ),
          findsNothing,
        );
        expect(
          find.descendant(
            of: routeCard,
            matching: find.textContaining('Gold Keys'),
          ),
          findsNothing,
        );
        final cardSemantics = tester.widget<Semantics>(
          find.descendant(
            of: routeCard,
            matching: find.byWidgetPredicate(
              (widget) =>
                  widget is Semantics &&
                  (widget.key as ValueKey?)?.value.toString().startsWith(
                        'demand-card-semantics-',
                      ) ==
                      true,
            ),
          ),
        );
        expect(cardSemantics.properties.label, contains('Behr Wild herbs'));
        expect(
          cardSemantics.properties.label,
          contains('Ranked by demand for Trace of Nature'),
        );
        expect(cardSemantics.properties.label, contains('Wild Grass'));
        expect(
          cardSemantics.properties.label,
          contains('Sharp Black Crystal Shard'),
        );
        expect(cardSemantics.properties.label, contains('At 1042 gathers/h'));

        final demandInfo = find.byKey(
          const ValueKey('demand-calculation-info-39'),
        );
        final demandInfoWidget = tester.widget<IconButton>(demandInfo);
        expect(
          demandInfoWidget.tooltip,
          'Show calculation for Behr Wild herbs',
        );
        expect(
          demandInfoWidget.constraints?.minWidth,
          greaterThanOrEqualTo(40),
        );
        await tester.tap(demandInfo);
        await _pumpUntilCalculationDialog(tester);
        final demandDialog = find.byKey(
          const ValueKey('market-calculation-dialog'),
        );
        expect(demandDialog, findsOneWidget);
        for (final contribution in expectedContributions) {
          expect(
            tester
                .widget<Text>(
                  find.byKey(
                    ValueKey('calculation-quantity-${contribution.id}'),
                  ),
                )
                .data,
            '≈ ${_fullSilverNumber(contribution.perHour)} / h',
          );
        }
        final demandIncome = find.byKey(
          const ValueKey('calculation-income-5960'),
        );
        expect(demandIncome, findsOneWidget);
        final stockedMarket = tester.widget<Text>(
          find.descendant(
            of: demandIncome,
            matching: find.byKey(const ValueKey('calculation-market-5960')),
          ),
        );
        expect(stockedMarket.data, '57.089');
        expect(stockedMarket.style?.color, muted);
        final preorderMarket = tester.widget<Text>(
          find.byKey(const ValueKey('calculation-market-4998')),
        );
        expect(preorderMarket.data, '−24.163');
        expect(
          preorderMarket.style?.color,
          Theme.of(tester.element(demandDialog)).colorScheme.error,
        );
        final zeroMarket = tester.widget<Text>(
          find.byKey(const ValueKey('calculation-market-4999')),
        );
        expect(zeroMarket.data, '0');
        expect(zeroMarket.style?.color, muted);
        expect(
          find.descendant(of: demandIncome, matching: find.text('Value / h')),
          findsOneWidget,
        );
        expect(
          find.descendant(of: demandIncome, matching: find.text('Stock')),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: demandDialog,
            matching: find.text('Market stock'),
          ),
          findsNothing,
        );
        expect(
          find.descendant(of: demandDialog, matching: find.text('Preorders')),
          findsNothing,
        );
        expect(
          tester
              .widgetList<GameIcon>(
                find.descendant(
                  of: demandDialog,
                  matching: find.byWidgetPredicate(
                    (widget) => widget is GameIcon && widget.size == 34,
                  ),
                ),
              )
              .isNotEmpty,
          isTrue,
        );
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
        expect(demandDialog, findsNothing);

        await tester.ensureVisible(
          find.byKey(const ValueKey('spot-ranking-profit')),
        );
        await tester.tap(find.byKey(const ValueKey('spot-ranking-profit')));
        await tester.pumpAndSettle();
        final valueCard = find.byKey(const ValueKey('spot-route-39'));
        expect(valueCard, findsOneWidget);
        expect(
          visibleContributionIds('value', valueCard),
          orderedEquals(demandCompactIds),
        );
        expect(
          find.descendant(
            of: valueCard,
            matching: find.byKey(const ValueKey('value-contribution-row-5960')),
          ),
          findsNothing,
        );
        expect(
          find.descendant(
            of: valueCard,
            matching: find.text(
              '${_silverText(expectedProjection.netSilverPerHour)}/h',
            ),
          ),
          findsOneWidget,
        );
        final valueLastRow = find.descendant(
          of: valueCard,
          matching: find.byKey(
            ValueKey('value-contribution-row-${expectedCompactIds.last}'),
          ),
        );
        expect(
          tester.getBottomRight(valueLastRow).dy,
          lessThanOrEqualTo(tester.getRect(valueCard).bottom),
        );
        await tester.tap(
          find.byKey(const ValueKey('value-calculation-info-39')),
        );
        await _pumpUntilCalculationDialog(tester);
        final calculationDialog = find.byKey(
          const ValueKey('market-calculation-dialog'),
        );
        expect(calculationDialog, findsOneWidget);
        for (final contribution in expectedContributions) {
          expect(
            tester
                .widget<Text>(
                  find.byKey(
                    ValueKey('calculation-quantity-${contribution.id}'),
                  ),
                )
                .data,
            '≈ ${_fullSilverNumber(contribution.perHour)} / h',
          );
        }
        final calculationSurface = find.byKey(
          const ValueKey('market-calculation-surface'),
        );
        final dialogRect = tester.getRect(calculationSurface);
        expect(dialogRect.left, greaterThanOrEqualTo(0));
        expect(dialogRect.top, greaterThanOrEqualTo(0));
        expect(dialogRect.right, lessThanOrEqualTo(1200));
        expect(dialogRect.bottom, lessThanOrEqualTo(752));
        expect(dialogRect.height, lessThanOrEqualTo(720));
        final twoColumnGrid = find.byKey(
          const ValueKey('market-calculation-columns-2'),
        );
        expect(twoColumnGrid, findsOneWidget);
        expect(
          find.byKey(const ValueKey('market-calculation-columns-1')),
          findsNothing,
        );
        final twoColumnTiles = find.descendant(
          of: twoColumnGrid,
          matching: find.byWidgetPredicate(
            (widget) =>
                widget.key is ValueKey &&
                (widget.key! as ValueKey).value.toString().startsWith(
                  'calculation-income-',
                ),
          ),
        );
        expect(twoColumnTiles, findsAtLeastNWidgets(2));
        final firstTwoColumnTile = tester.getRect(twoColumnTiles.at(0));
        final secondTwoColumnTile = tester.getRect(twoColumnTiles.at(1));
        expect(
          firstTwoColumnTile.top,
          moreOrLessEquals(secondTwoColumnTile.top, epsilon: 1),
        );
        expect(
          firstTwoColumnTile.right,
          lessThanOrEqualTo(secondTwoColumnTile.left),
        );
        expect(
          find.byKey(const ValueKey('calculation-income-5960')),
          findsOneWidget,
        );
        final valueTraceMarket = tester.widget<Text>(
          find.byKey(const ValueKey('calculation-market-5960')),
        );
        expect(valueTraceMarket.data, '57.089');
        expect(valueTraceMarket.style?.color, muted);
        final calculationScroll = tester.state<ScrollableState>(
          find.descendant(
            of: find.byKey(const ValueKey('market-calculation-scroll')),
            matching: find.byType(Scrollable),
          ),
        );
        expect(
          calculationScroll.position.maxScrollExtent,
          greaterThanOrEqualTo(0),
        );
        expect(
          find.byKey(const ValueKey('calculation-cost-589')),
          findsNothing,
        );
        expect(
          find.byKey(const ValueKey('calculation-cost-44164')),
          findsNothing,
        );
        expect(
          find.byKey(const ValueKey('market-calculation-total')),
          findsNothing,
        );
        expect(find.text('Income'), findsNothing);
        expect(find.text('Deductions'), findsNothing);
        final close = find.descendant(
          of: calculationDialog,
          matching: find.byTooltip('Close'),
        );
        expect(close, findsOneWidget);
        await tester.tap(close);
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('market-calculation-dialog')),
          findsNothing,
        );
        expect(
          find.byKey(const ValueKey('close-market-calculation')),
          findsNothing,
        );
        expect(find.text('Marketplace tax'), findsNothing);
        expect(
          find.text('Saved sessions do not record setup costs.'),
          findsNothing,
        );

        tester.platformDispatcher.textScaleFactorTestValue = 2;
        await tester.pumpAndSettle();
        final scaledInfo = find.byKey(
          const ValueKey('value-calculation-info-39'),
        );
        await tester.ensureVisible(scaledInfo);
        await tester.tap(scaledInfo);
        await _pumpUntilCalculationDialog(tester);
        final oneColumnGrid = find.byKey(
          const ValueKey('market-calculation-columns-1'),
        );
        expect(oneColumnGrid, findsOneWidget);
        expect(
          find.byKey(const ValueKey('market-calculation-columns-2')),
          findsNothing,
        );
        final oneColumnTiles = find.descendant(
          of: oneColumnGrid,
          matching: find.byWidgetPredicate(
            (widget) =>
                widget.key is ValueKey &&
                (widget.key! as ValueKey).value.toString().startsWith(
                  'calculation-income-',
                ),
          ),
        );
        expect(oneColumnTiles, findsAtLeastNWidgets(2));
        final firstOneColumnTile = tester.getRect(oneColumnTiles.at(0));
        final secondOneColumnTile = tester.getRect(oneColumnTiles.at(1));
        expect(
          firstOneColumnTile.bottom,
          lessThanOrEqualTo(secondOneColumnTile.top),
        );
        expect(
          firstOneColumnTile.left,
          moreOrLessEquals(secondOneColumnTile.left, epsilon: 1),
        );
        expect(tester.takeException(), isNull);
      }, createHttpClient: (_) => _OfflineTiles._());
    },
  );

  testWidgets('Tshira Demand stacks both primary meats at minimum size', (
    tester,
  ) async {
    tester.view
      ..devicePixelRatio = 1
      ..physicalSize = const Size(1200, 752);
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    await HttpOverrides.runZoned(() async {
      await tester.pumpWidget(
        MaterialApp(
          theme: companionTheme(),
          home: Scaffold(
            body: FieldGuide(
              catalog: catalog,
              bairogCalculatorData: catalog.bairogCalculatorData,
              marketOrderBookLoader: (items, {includePreorders = false}) async {
                final fetchedAt = DateTime.utc(2026, 9, 3, 9);
                return <String, GatheringMarketQuote>{
                  for (final entry in items.entries)
                    entry.key: GatheringMarketQuote(
                      itemId: int.parse(entry.key),
                      price: switch (entry.key) {
                        '4998' => 4800000,
                        '7922' || '7924' => 30000,
                        _ => 1000,
                      },
                      stock: switch (entry.key) {
                        '4998' => 0,
                        '7922' => 1234567,
                        '7924' => 0,
                        _ => 100000,
                      },
                      preorders: includePreorders
                          ? entry.key == '4998'
                                ? 7777
                                : 0
                          : null,
                      fetchedAt: fetchedAt,
                    ),
                };
              },
              onUse: (_) {},
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.tap(
        find.byKey(const ValueKey('spot-filter-compact-control')),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.byKey(const ValueKey('spot-ranking-demand')),
      );
      await tester.tap(find.byKey(const ValueKey('spot-ranking-demand')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('spot-search')),
        'Tshira',
      );
      await tester.pumpAndSettle();

      final routeCard = find.byKey(const ValueKey('spot-route-48'));
      expect(routeCard, findsOneWidget);
      expect(
        find.descendant(
          of: routeCard,
          matching: find.byKey(const ValueKey('demand-primary-pair-7922-7924')),
        ),
        findsNothing,
      );
      for (final id in const <String>['7922', '7924']) {
        expect(
          find.descendant(
            of: routeCard,
            matching: find.byKey(ValueKey('demand-contribution-row-$id')),
          ),
          findsOneWidget,
        );
        final icon = tester.widget<GameIcon>(
          find.descendant(
            of: routeCard,
            matching: find.byKey(ValueKey('demand-contribution-icon-$id')),
          ),
        );
        expect(icon.size, 24);
      }
      final snakeRow = find.descendant(
        of: routeCard,
        matching: find.byKey(const ValueKey('demand-contribution-row-7922')),
      );
      final scorpionRow = find.descendant(
        of: routeCard,
        matching: find.byKey(const ValueKey('demand-contribution-row-7924')),
      );
      expect(
        tester.getRect(snakeRow).bottom,
        lessThanOrEqualTo(tester.getRect(scorpionRow).top),
      );
      expect(
        find.descendant(
          of: routeCard,
          matching: find.byKey(const ValueKey('demand-contribution-row-4998')),
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    }, createHttpClient: (_) => _OfflineTiles._());
  });

  testWidgets(
    'Demand shows the live shortage item and both known market counts',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1500, 940);
      addTearDown(tester.view.reset);

      final requested = <String, String>{};
      await HttpOverrides.runZoned(() async {
        await tester.pumpWidget(
          MaterialApp(
            theme: companionTheme(),
            home: Scaffold(
              body: FieldGuide(
                catalog: catalog,
                bairogCalculatorData: catalog.bairogCalculatorData,
                marketOrderBookLoader:
                    (items, {includePreorders = false}) async {
                      requested.addAll(items);
                      final fetchedAt = DateTime.utc(2026, 9, 3, 9);
                      return <String, GatheringMarketQuote>{
                        for (final entry in items.entries)
                          entry.key: GatheringMarketQuote(
                            itemId: int.parse(entry.key),
                            price: switch (entry.key) {
                              '821351' => 2800000,
                              '4999' => 265000,
                              '7913' => 19300,
                              _ => 1000,
                            },
                            stock: switch (entry.key) {
                              '821351' => 0,
                              '4999' => 1636,
                              '7913' => 41660,
                              _ => 100000,
                            },
                            preorders: includePreorders
                                ? switch (entry.key) {
                                    '821351' => 63098,
                                    '4999' => 359,
                                    '7913' => 2588,
                                    _ => 0,
                                  }
                                : null,
                            fetchedAt: fetchedAt,
                          ),
                      };
                    },
                onUse: (_) {},
              ),
            ),
          ),
        );
        await tester.pump();
        await tester.tap(
          find.byKey(const ValueKey('spot-filter-compact-control')),
        );
        await tester.pumpAndSettle();
        await tester.ensureVisible(
          find.byKey(const ValueKey('spot-ranking-demand')),
        );
        await tester.tap(find.byKey(const ValueKey('spot-ranking-demand')));
        await tester.pumpAndSettle();

        expect(requested, containsPair('821351', 'Faint Wildsoul'));
        expect(requested, containsPair('4999', 'Black Gem Fragment'));
        expect(requested, containsPair('7913', 'Wolf Meat'));
        final routeCard = find.byKey(const ValueKey('spot-route-17'));
        await tester.scrollUntilVisible(
          routeCard,
          120,
          scrollable: find
              .descendant(
                of: find.byKey(const ValueKey('spot-list')),
                matching: find.byType(Scrollable),
              )
              .first,
        );
        await tester.pumpAndSettle();

        expect(
          find.descendant(of: routeCard, matching: find.text('Faint Wildsoul')),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: routeCard,
            matching: find.byKey(const ValueKey('demand-stock-821351')),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: routeCard,
            matching: find.byKey(const ValueKey('demand-preorders-821351')),
          ),
          findsOneWidget,
        );
        final stockText = tester.widget<Text>(
          find.descendant(
            of: routeCard,
            matching: find.byKey(const ValueKey('demand-stock-821351')),
          ),
        );
        final preorderText = tester.widget<Text>(
          find.descendant(
            of: routeCard,
            matching: find.byKey(const ValueKey('demand-preorders-821351')),
          ),
        );
        expect(stockText.data, '0');
        expect(stockText.style?.color, muted);
        expect(preorderText.data, '−63.098');
        expect(
          preorderText.style?.color,
          Theme.of(tester.element(routeCard)).colorScheme.error,
        );
        final demandSemantics = tester.widget<Semantics>(
          find.descendant(
            of: routeCard,
            matching: find.byKey(const ValueKey('demand-semantics-821351')),
          ),
        );
        expect(
          demandSemantics.properties.label,
          startsWith(
            'Faint Wildsoul: 116 per hour, 274M silver per hour. '
            'Current stock: 0. '
            'Current preorders: 63.098.',
          ),
        );
        expect(
          find.descendant(
            of: routeCard,
            matching: find.text('Black Gem Fragment'),
          ),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      }, createHttpClient: (_) => _OfflineTiles._());
    },
  );

  testWidgets(
    'Demand keeps rare bonus drops in details, not the compact card',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1500, 940);
      addTearDown(tester.view.reset);

      await HttpOverrides.runZoned(() async {
        await tester.pumpWidget(
          MaterialApp(
            theme: companionTheme(),
            home: Scaffold(
              body: FieldGuide(
                catalog: catalog,
                bairogCalculatorData: catalog.bairogCalculatorData,
                marketOrderBookLoader:
                    (items, {includePreorders = false}) async {
                      final fetchedAt = DateTime.utc(2026, 9, 3, 9);
                      return <String, GatheringMarketQuote>{
                        for (final entry in items.entries)
                          entry.key: GatheringMarketQuote(
                            itemId: int.parse(entry.key),
                            price: entry.key == '821469' ? 280000000 : 1000,
                            stock: entry.key == '821469' ? 0 : 100000,
                            preorders: includePreorders ? 0 : null,
                            fetchedAt: fetchedAt,
                          ),
                      };
                    },
                onUse: (_) {},
              ),
            ),
          ),
        );
        await tester.pump();
        await tester.tap(
          find.byKey(const ValueKey('spot-filter-compact-control')),
        );
        await tester.pumpAndSettle();
        await tester.ensureVisible(
          find.byKey(const ValueKey('spot-ranking-demand')),
        );
        await tester.tap(find.byKey(const ValueKey('spot-ranking-demand')));
        await tester.pumpAndSettle();

        final routeCard = find.byKey(const ValueKey('spot-route-17'));
        await tester.scrollUntilVisible(
          routeCard,
          120,
          scrollable: find
              .descendant(
                of: find.byKey(const ValueKey('spot-list')),
                matching: find.byType(Scrollable),
              )
              .first,
        );
        await tester.pumpAndSettle();

        expect(
          find.descendant(
            of: routeCard,
            matching: find.text('Evergreen Shard'),
          ),
          findsNothing,
        );
        expect(
          find.descendant(
            of: routeCard,
            matching: find.byKey(const ValueKey('demand-stock-821469')),
          ),
          findsNothing,
        );
        expect(
          find.descendant(
            of: routeCard,
            matching: find.byKey(const ValueKey('demand-preorders-821469')),
          ),
          findsNothing,
        );
        await tester.tap(
          find.byKey(const ValueKey('demand-calculation-info-17')),
        );
        await _pumpUntilCalculationDialog(tester);

        final evergreenIncome = find.byKey(
          const ValueKey('calculation-income-821469'),
        );
        expect(evergreenIncome, findsOneWidget);
        expect(
          find.descendant(
            of: evergreenIncome,
            matching: find.text('Evergreen Shard'),
          ),
          findsOneWidget,
        );
        final market = tester.widget<Text>(
          find.descendant(
            of: evergreenIncome,
            matching: find.byKey(const ValueKey('calculation-market-821469')),
          ),
        );
        expect(market.data, '0');
        expect(market.style?.color, muted);
        expect(tester.takeException(), isNull);
      }, createHttpClient: (_) => _OfflineTiles._());
    },
  );

  testWidgets(
    'Demand stages every zero-stock Nostos item and reuses fresh coverage',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1500, 940);
      addTearDown(tester.view.reset);

      const nostosIds = <String>{
        '821348',
        '821349',
        '821350',
        '821351',
        '821352',
        '821353',
      };
      final calls = <({bool preorders, Set<String> ids})>[];
      await HttpOverrides.runZoned(() async {
        await tester.pumpWidget(
          MaterialApp(
            theme: companionTheme(),
            home: Scaffold(
              body: FieldGuide(
                catalog: catalog,
                bairogCalculatorData: catalog.bairogCalculatorData,
                marketOrderBookLoader:
                    (items, {includePreorders = false}) async {
                      calls.add((
                        preorders: includePreorders,
                        ids: items.keys.toSet(),
                      ));
                      final fetchedAt = DateTime.utc(2026, 9, 3, 9);
                      return <String, GatheringMarketQuote>{
                        for (final id in items.keys)
                          id: GatheringMarketQuote(
                            itemId: int.parse(id),
                            price: nostosIds.contains(id) ? 2800000 : 1000,
                            stock: nostosIds.contains(id) ? 0 : 100000,
                            preorders: includePreorders
                                ? (nostosIds.contains(id) ? 1000 : 0)
                                : null,
                            fetchedAt: fetchedAt,
                          ),
                      };
                    },
                onUse: (_) {},
              ),
            ),
          ),
        );
        await tester.pump();
        await tester.tap(
          find.byKey(const ValueKey('spot-filter-compact-control')),
        );
        await tester.pumpAndSettle();
        await tester.ensureVisible(
          find.byKey(const ValueKey('spot-ranking-demand')),
        );
        await tester.tap(find.byKey(const ValueKey('spot-ranking-demand')));
        await tester.pumpAndSettle();

        final baseCalls = calls.where((call) => !call.preorders).toList();
        final preorderCalls = calls.where((call) => call.preorders).toList();
        expect(baseCalls.first.ids, nostosIds);
        expect(preorderCalls.first.ids, nostosIds);
        expect(
          preorderCalls.expand((call) => call.ids),
          contains('4999'),
          reason: 'Demand keeps full preorder coverage for in-stock drops.',
        );
        final callCount = calls.length;

        await tester.ensureVisible(
          find.byKey(const ValueKey('spot-ranking-browse')),
        );
        await tester.tap(find.byKey(const ValueKey('spot-ranking-browse')));
        await tester.pumpAndSettle();
        await tester.ensureVisible(
          find.byKey(const ValueKey('spot-ranking-demand')),
        );
        await tester.tap(find.byKey(const ValueKey('spot-ranking-demand')));
        await tester.pumpAndSettle();

        expect(calls, hasLength(callCount));
        expect(tester.takeException(), isNull);
      }, createHttpClient: (_) => _OfflineTiles._());
    },
  );

  testWidgets(
    'Demand preserves fresh stock without showing a failed preorder count',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1500, 940);
      addTearDown(tester.view.reset);

      var partialRefresh = false;
      await HttpOverrides.runZoned(() async {
        await tester.pumpWidget(
          MaterialApp(
            theme: companionTheme(),
            home: Scaffold(
              body: FieldGuide(
                catalog: catalog,
                bairogCalculatorData: catalog.bairogCalculatorData,
                marketOrderBookLoader:
                    (items, {includePreorders = false}) async {
                      final fetchedAt = DateTime.utc(2026, 9, 3, 9);
                      if (partialRefresh) {
                        if (!items.containsKey('821351')) return const {};
                        return <String, GatheringMarketQuote>{
                          '821351': GatheringMarketQuote(
                            itemId: 821351,
                            price: 2800000,
                            stock: 0,
                            preorders: includePreorders ? null : null,
                            fetchedAt: fetchedAt,
                          ),
                        };
                      }
                      return <String, GatheringMarketQuote>{
                        for (final id in items.keys)
                          id: GatheringMarketQuote(
                            itemId: int.parse(id),
                            price: id == '821351' ? 2800000 : 1000,
                            stock: id == '821351' ? 0 : 100000,
                            preorders: includePreorders
                                ? (id == '821351' ? 63098 : 0)
                                : null,
                            fetchedAt: fetchedAt,
                          ),
                      };
                    },
                onUse: (_) {},
              ),
            ),
          ),
        );
        await tester.pump();
        await tester.tap(
          find.byKey(const ValueKey('spot-filter-compact-control')),
        );
        await tester.pumpAndSettle();
        await tester.ensureVisible(
          find.byKey(const ValueKey('spot-ranking-demand')),
        );
        await tester.tap(find.byKey(const ValueKey('spot-ranking-demand')));
        await tester.pumpAndSettle();

        partialRefresh = true;
        await tester.tap(find.byKey(const ValueKey('spot-market-refresh')));
        await tester.pumpAndSettle();

        final routeCard = find.byKey(const ValueKey('spot-route-17'));
        await tester.scrollUntilVisible(
          routeCard,
          120,
          scrollable: find
              .descendant(
                of: find.byKey(const ValueKey('spot-list')),
                matching: find.byType(Scrollable),
              )
              .first,
        );
        await tester.pumpAndSettle();
        expect(
          find.descendant(of: routeCard, matching: find.text('Faint Wildsoul')),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: routeCard,
            matching: find.byKey(const ValueKey('demand-stock-821351')),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: routeCard,
            matching: find.byKey(const ValueKey('demand-preorders-821351')),
          ),
          findsNothing,
        );
        final tooltip = tester.widget<Tooltip>(
          find.descendant(
            of: routeCard,
            matching: find.byKey(
              const ValueKey('demand-contribution-tooltip-821351'),
            ),
          ),
        );
        expect(tooltip.message, endsWith('Preorders\nNot available'));
        expect(
          find.descendant(
            of: routeCard,
            matching: find.textContaining('partial', findRichText: true),
          ),
          findsNothing,
        );
        expect(tester.takeException(), isNull);
      }, createHttpClient: (_) => _OfflineTiles._());
    },
  );

  testWidgets(
    'Demand ignores cached broad preorders when coverage is incomplete',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1500, 940);
      addTearDown(tester.view.reset);

      const nostosIds = <String>{
        '821348',
        '821349',
        '821350',
        '821351',
        '821352',
        '821353',
      };
      final calls = <({bool preorders, Set<String> ids})>[];
      await HttpOverrides.runZoned(() async {
        await tester.pumpWidget(
          MaterialApp(
            theme: companionTheme(),
            home: Scaffold(
              body: FieldGuide(
                catalog: catalog,
                bairogCalculatorData: catalog.bairogCalculatorData,
                marketOrderBookLoader:
                    (items, {includePreorders = false}) async {
                      calls.add((
                        preorders: includePreorders,
                        ids: items.keys.toSet(),
                      ));
                      final fetchedAt = DateTime.utc(2026, 9, 3, 9);
                      if (includePreorders) {
                        final id = items.keys.first;
                        return <String, GatheringMarketQuote>{
                          id: GatheringMarketQuote(
                            itemId: int.parse(id),
                            price: 2800000,
                            stock: 0,
                            preorders: 1000,
                            fetchedAt: fetchedAt,
                          ),
                        };
                      }
                      return <String, GatheringMarketQuote>{
                        for (final id in items.keys)
                          id: GatheringMarketQuote(
                            itemId: int.parse(id),
                            price: nostosIds.contains(id) ? 2800000 : 1000,
                            stock: nostosIds.contains(id) ? 0 : 100000,
                            preorders: id == '4999' ? 359 : null,
                            fetchedAt: fetchedAt,
                          ),
                      };
                    },
                onUse: (_) {},
              ),
            ),
          ),
        );
        await tester.pump();
        await tester.tap(
          find.byKey(const ValueKey('spot-filter-compact-control')),
        );
        await tester.pumpAndSettle();
        await tester.ensureVisible(
          find.byKey(const ValueKey('spot-ranking-demand')),
        );
        await tester.tap(find.byKey(const ValueKey('spot-ranking-demand')));
        await tester.pumpAndSettle();

        final preorderCalls = calls.where((call) => call.preorders).toList();
        expect(preorderCalls, hasLength(1));
        expect(preorderCalls.single.ids, nostosIds);
        final routeCard = find.byKey(const ValueKey('spot-route-17'));
        await tester.scrollUntilVisible(
          routeCard,
          120,
          scrollable: find
              .descendant(
                of: find.byKey(const ValueKey('spot-list')),
                matching: find.byType(Scrollable),
              )
              .first,
        );
        await tester.pumpAndSettle();
        expect(
          find.descendant(of: routeCard, matching: find.text('Faint Wildsoul')),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: routeCard,
            matching: find.byKey(const ValueKey('demand-preorders-821351')),
          ),
          findsNothing,
        );
        final tooltip = tester.widget<Tooltip>(
          find.descendant(
            of: routeCard,
            matching: find.byKey(
              const ValueKey('demand-contribution-tooltip-821351'),
            ),
          ),
        );
        expect(tooltip.message, endsWith('Preorders\nNot available'));
        expect(
          find.descendant(
            of: routeCard,
            matching: find.textContaining('partial', findRichText: true),
          ),
          findsNothing,
        );
        expect(tester.takeException(), isNull);
      }, createHttpClient: (_) => _OfflineTiles._());
    },
  );

  testWidgets(
    'Demand defers the bulk base sweep when one priority Nostos quote fails',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1500, 940);
      addTearDown(tester.view.reset);

      const nostosIds = <String>{
        '821348',
        '821349',
        '821350',
        '821351',
        '821352',
        '821353',
      };
      final calls = <({bool preorders, Set<String> ids})>[];
      await HttpOverrides.runZoned(() async {
        await tester.pumpWidget(
          MaterialApp(
            theme: companionTheme(),
            home: Scaffold(
              body: FieldGuide(
                catalog: catalog,
                bairogCalculatorData: catalog.bairogCalculatorData,
                marketOrderBookLoader:
                    (items, {includePreorders = false}) async {
                      calls.add((
                        preorders: includePreorders,
                        ids: items.keys.toSet(),
                      ));
                      final fetchedAt = DateTime.utc(2026, 9, 3, 9);
                      return <String, GatheringMarketQuote>{
                        for (final id in items.keys)
                          if (includePreorders || id != '821351')
                            id: GatheringMarketQuote(
                              itemId: int.parse(id),
                              price: 2800000,
                              stock: 0,
                              preorders: includePreorders ? 0 : null,
                              fetchedAt: fetchedAt,
                            ),
                      };
                    },
                onUse: (_) {},
              ),
            ),
          ),
        );
        await tester.pump();
        await tester.tap(
          find.byKey(const ValueKey('spot-filter-compact-control')),
        );
        await tester.pumpAndSettle();
        await tester.ensureVisible(
          find.byKey(const ValueKey('spot-ranking-demand')),
        );
        await tester.tap(find.byKey(const ValueKey('spot-ranking-demand')));
        await tester.pumpAndSettle();

        final baseCalls = calls.where((call) => !call.preorders).toList();
        expect(baseCalls, hasLength(1));
        expect(baseCalls.single.ids, nostosIds);
        expect(calls.any((call) => call.ids.contains('4999')), isFalse);
        final routeCard = find.byKey(const ValueKey('spot-route-17'));
        await tester.scrollUntilVisible(
          routeCard,
          120,
          scrollable: find
              .descendant(
                of: find.byKey(const ValueKey('spot-list')),
                matching: find.byType(Scrollable),
              )
              .first,
        );
        await tester.pumpAndSettle();
        expect(
          find.descendant(
            of: routeCard,
            matching: find.byKey(const ValueKey('demand-card-total')),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: routeCard,
            matching: find.textContaining('partial', findRichText: true),
          ),
          findsNothing,
        );
        expect(tester.takeException(), isNull);
      }, createHttpClient: (_) => _OfflineTiles._());
    },
  );
}
