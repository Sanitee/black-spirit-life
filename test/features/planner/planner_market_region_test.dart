import 'dart:async';
import 'dart:io';
import 'dart:ui' show ImageByteFormat;

import 'package:bdo_craft_planner_flutter/domain/state/planner_state.dart';
import 'package:bdo_craft_planner_flutter/domain/state/state_copy.dart';
import 'package:bdo_craft_planner_flutter/features/planner/planner.dart';
import 'package:bdo_craft_planner_flutter/features/shared/market_region_selector.dart';
import 'package:bdo_craft_planner_flutter/visual/components/section_header.dart';
import 'package:bdo_craft_planner_flutter/visual/illuminated_ledger/ledger_spec.dart';
import 'package:bdo_craft_planner_flutter/visual/sakura_night_garden/sakura_botanical_assets.dart';
import 'package:bdo_craft_planner_flutter/visual/sakura_night_garden/sakura_spec.dart';
import 'package:bdo_craft_planner_flutter/visual/standard/standard_spec.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'planner_test_fixture.dart';

const _na = ValueKey('market-region:na');
const _eu = ValueKey('market-region:eu');

PlannerMarketRefresh _refresh(String region) => PlannerMarketRefresh(
  prices: {'Sunrise Herb': region == 'na' ? 1500 : 1200},
  stock: {'Sunrise Herb': 500},
  unlistedItemNames: {},
  fetchedAt: 1784534400000,
  summary: '${region.toUpperCase()} prices checked.',
  region: region,
);

void main() {
  setUpAll(_loadFonts);

  test(
    'region change clears only regional observations and persists',
    () async {
      final harness = PlannerTestHarness(
        alchemyMarket: MarketState(
          prices: {'Sunrise Herb': 123},
          stock: {'Sunrise Herb': 4},
          preorderPrices: {'Sunrise Herb': 150},
          preorderObservedAt: {'Sunrise Herb': 20},
          tradeMarketIds: {'Sunrise Herb': '1'},
          totalTrades: {'Sunrise Herb': 500},
          tradeObservedAt: {'Sunrise Herb': 10},
          observedDailyTrades: {'Sunrise Herb': 20},
          tradeObservationHours: {'Sunrise Herb': 24},
          lastSoldAtEpochSeconds: {'Sunrise Herb': 3},
          unlistedItemNames: {'Salt'},
          fetchedAt: 42,
          amount: 543,
          search: 'herb',
          selected: 'Sunrise Herb',
          sort: 'profit',
        ),
      );
      final controller = harness.controller.active;
      controller.updateState(
        (s) => s.copyWith(inventory: {'Sunrise Herb': 2200}),
      );
      final before = controller.state.value.toJson()..remove('market');
      expect(controller.setMarketRegion(' NA '), isTrue);
      final after = controller.state.value.toJson()..remove('market');
      expect(after, before);
      final market = controller.state.value.market;
      expect(market.region, 'na');
      for (final map in [
        market.prices,
        market.stock,
        market.preorderPrices,
        market.preorderObservedAt,
        market.tradeMarketIds,
        market.totalTrades,
        market.tradeObservedAt,
        market.observedDailyTrades,
        market.tradeObservationHours,
        market.lastSoldAtEpochSeconds,
      ]) {
        expect(map, isEmpty);
      }
      expect(market.unlistedItemNames, isEmpty);
      expect(market.fetchedAt, 0);
      expect(market.amount, 543);
      expect(market.search, 'herb');
      expect(market.selected, 'Sunrise Herb');
      expect(market.sort, 'profit');
      expect(controller.setMarketRegion('na'), isFalse);
      expect(controller.setMarketRegion('kr'), isFalse);
      harness.controller.freezeMutationsForRestart();
      expect(controller.setMarketRegion('eu'), isFalse);
      expect(controller.state.value.market.region, 'na');
      await harness.controller.dispose();
    },
  );

  testWidgets('NA/EU checks selected region and refreshes visible prices', (
    tester,
  ) async {
    await setPlannerTestSize(tester, const Size(1500, 940));
    final requests = <String>[];
    final harness = PlannerTestHarness(
      checkPrices: (request) async {
        final region = request.controller.state.value.market.region;
        requests.add(region);
        return _refresh(region);
      },
    );
    await tester.pumpWidget(harness.plannerHost());
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(_na));
    await tester.pumpAndSettle();
    expect(requests, isEmpty);
    expect(harness.controller.active.state.value.market.region, 'na');
    expect(find.textContaining(' missing'), findsNothing);
    await tester.tap(find.byKey(PlannerActionKeys.p15));
    await tester.pumpAndSettle();
    expect(requests, ['na']);
    expect(
      harness.controller.active.state.value.market.prices['Sunrise Herb'],
      1500,
    );
    await tester.tap(find.byKey(_eu));
    await tester.pumpAndSettle();
    expect(requests, ['na', 'eu']);
    expect(
      harness.controller.active.state.value.market.prices['Sunrise Herb'],
      1200,
    );
    expect(find.byKey(PlannerActionKeys.p16), findsOneWidget);
    expect(tester.takeException(), isNull);
    await harness.controller.dispose();
  });

  testWidgets(
    'loading disables selector; late other-region result is ignored',
    (tester) async {
      await setPlannerTestSize(tester, const Size(1500, 940));
      final pending = Completer<PlannerMarketRefresh>();
      final harness = PlannerTestHarness(checkPrices: (_) => pending.future);
      await tester.pumpWidget(harness.plannerHost());
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(PlannerActionKeys.p15));
      await tester.pump();
      expect(tester.widget<TextButton>(find.byKey(_na)).onPressed, isNull);
      harness.controller.active.setMarketRegion('na');
      pending.complete(_refresh('eu'));
      await tester.pumpAndSettle();
      expect(harness.controller.active.state.value.market.region, 'na');
      expect(harness.controller.active.state.value.market.prices, isEmpty);
      expect(tester.widget<TextButton>(find.byKey(_eu)).onPressed, isNotNull);
      expect(tester.takeException(), isNull);
      await harness.controller.dispose();
    },
  );

  for (final entry in {
    'sakura': SakuraNightGardenSpec.theme,
    'ledger': IlluminatedLedgerSpec.theme,
    'greenhouse': StandardSpec.theme,
  }.entries) {
    for (final size in [const Size(1216, 862), const Size(916, 674)]) {
      for (final scale in [1.0, 2.0]) {
        testWidgets('${entry.key} header ${size.width} scale $scale', (
          tester,
        ) async {
          await setPlannerTestSize(tester, size);
          final harness = PlannerTestHarness();
          await tester.pumpWidget(
            RepaintBoundary(
              key: const ValueKey('region-capture'),
              child: harness.plannerHost(
                spec: entry.value,
                textScaler: TextScaler.linear(scale),
              ),
            ),
          );
          await tester.pumpAndSettle();
          final header = find.byWidgetPredicate(
            (w) => w is SectionHeader && w.title == 'Need First',
          );
          expect(header, findsOneWidget);
          expect(tester.widget<SectionHeader>(header).meta, isNull);
          expect(find.byType(MarketRegionSelector), findsOneWidget);
          expect(find.byKey(_na).hitTestable(), findsOneWidget);
          expect(find.byKey(_eu).hitTestable(), findsOneWidget);
          expect(
            find.byKey(PlannerActionKeys.p15).hitTestable(),
            findsOneWidget,
          );
          if (scale == 1 && size.width == 1216) {
            expect(
              tester.getCenter(find.byType(MarketRegionSelector)).dy,
              closeTo(
                tester.getCenter(find.byKey(PlannerActionKeys.p15)).dy,
                1,
              ),
            );
            expect(
              tester.getRect(find.byType(MarketRegionSelector)).top,
              lessThan(tester.getRect(header).bottom),
            );
          }
          if (entry.key == 'sakura') {
            await tester.runAsync(
              () => precacheImage(
                const AssetImage(SakuraBotanicalAssets.sectionBloom),
                tester.element(header),
              ),
            );
            await tester.pumpAndSettle();
            expect(
              find.descendant(
                of: header,
                matching: find.byType(SakuraSectionRuleAsset),
              ),
              findsOneWidget,
            );
          }
          expect(tester.takeException(), isNull);
          await _capture(
            tester,
            '${entry.key}-${size.width.toInt()}-${scale.toInt()}x',
          );
          await harness.controller.dispose();
        });
      }
    }
  }
}

Future<void> _loadFonts() async {
  if (!Platform.isWindows) return;
  for (final entry in {
    'Segoe UI': ['segoeui.ttf', 'seguisb.ttf', 'segoeuib.ttf'],
    'Georgia': ['georgia.ttf', 'georgiab.ttf'],
  }.entries) {
    final loader = FontLoader(entry.key);
    for (final file in entry.value) {
      loader.addFont(
        File('C:/Windows/Fonts/$file').readAsBytes().then(ByteData.sublistView),
      );
    }
    await loader.load();
  }
}

Future<void> _capture(WidgetTester tester, String name) async {
  final path = Platform.environment['PLANNER_REGION_CAPTURE_DIR'];
  if (path == null) return;
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(const ValueKey('region-capture')),
  );
  await tester.runAsync(() async {
    final image = await boundary.toImage();
    try {
      final bytes = await image.toByteData(format: ImageByteFormat.png);
      await File('$path/$name.png').writeAsBytes(bytes!.buffer.asUint8List());
    } finally {
      image.dispose();
    }
  });
}
