import 'dart:io';

import 'package:bdo_map_core/bdo_map_core.dart';
import 'package:bdo_map_core/src/lodging/town_house_investment.dart';
import 'package:bdo_map_core/src/widgets/resource_map_atlas_shell.dart';
import 'package:bdo_map_core/src/widgets/resource_map_node_quick_panel.dart';
import 'package:bdo_map_core/src/widgets/town_house_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/map_menu_capture.dart';

void main() {
  late List<BdoRoyalWorkshopGood> goods;
  late LodgingTown town;
  late BdoWorkerNode node;
  setUpAll(() async {
    await loadMapMenuCaptureFonts();
    goods = await const BdoRoyalWorkshopGoodsLoader().load();
    final houses = LodgingDataset.fromJsonString(
      File('assets/data/lodging_houses.json').readAsStringSync(),
    );
    town = houses.townsByNodeId['1101']!;
    final data = await BdoResourceMapLoader.loadBundled();
    node = data.workerNodes.firstWhere((n) => n.name == 'Heidel');
  });

  for (final scale in [1.0, 2.0]) {
    testWidgets('housing and node details remain readable at $scale text', (
      tester,
    ) async {
      final goals = [
        const TownHouseGoal(1, 2),
        const TownHouseGoal(2, 4),
        const TownHouseGoal(3, 0),
      ];
      await _host(
        tester,
        scale,
        SizedBox(
          width: 356,
          child: ResourceMapAtlasWorkspace(
            title: town.name,
            shrinkWrap: true,
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(12),
              child: TownHousePanel(
                town: town,
                goals: goals,
                plan: TownHouseInvestmentPlanner.solve(
                  town: town,
                  goals: goals,
                ),
                owned: const {},
                ownedUsages: const {},
                selectedHouseId: null,
                browseAll: false,
                onGoalsChanged: (_) {},
                onSelectHouse: (_) {},
                onOwnedChanged: (_) {},
                onUseChanged: (_, _) {},
                onBrowseChanged: (_) {},
                onFit: () {},
                onShopLodging: () {},
              ),
            ),
          ),
        ),
      );
      expect(find.text('Lodging'), findsWidgets);
      expect(tester.takeException(), isNull);
      await _capture(tester, 'housing-detail-$scale');

      await _host(
        tester,
        scale,
        SizedBox(
          width: 356,
          child: ResourceMapNodeQuickPanel(
            nodeName: node.name,
            nodeType: node.nodeType,
            region: node.region,
            contributionPoints: node.contributionPoints,
            outputs: const [],
            invested: false,
            townActions: ResourceMapTownQuickActions(onOpenHouses: () {}),
            onClose: () {},
          ),
        ),
      );
      expect(find.text(node.name), findsOneWidget);
      expect(tester.takeException(), isNull);
      await _capture(tester, 'node-detail-$scale');
    });

    testWidgets('Royal Workshop menus keep essentials at $scale text', (
      tester,
    ) async {
      var plan = BdoRoyalWorkshopPlan(accessInvested: true);
      await _host(
        tester,
        scale,
        SizedBox(
          width: 680,
          height: scale == 1 ? 420 : 700,
          child: StatefulBuilder(
            builder: (context, setState) => BdoRoyalWorkshopManager(
              plan: plan,
              goods: goods,
              yukjoHiredWorkers: 3,
              yukjoLodgingSlots: 7,
              onChanged: (next) => setState(() => plan = next),
              onOpenYukjoHousing: () {},
            ),
          ),
        ),
      );
      expect(goods.length, 124);
      expect(find.text('Assigned'), findsNothing);
      expect(find.text('Running'), findsNothing);
      expect(find.text('Yukjo lodging'), findsNothing);
      expect(find.textContaining('hired'), findsNothing);
      expect(find.textContaining('The planner reserves'), findsNothing);
      expect(find.text('Your palace'), findsNothing);
      expect(
        find.textContaining('Choose an area on the palace plan'),
        findsNothing,
      );
      await _capture(tester, 'royal-overview-$scale');
      final area = find.byKey(
        const ValueKey('royal-workshop-area-button-infirmary'),
      );
      await tester.ensureVisible(area);
      await tester.tap(area);
      await tester.pumpAndSettle();
      await _capture(tester, 'royal-workshops-$scale');
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('royal-workshop-worker-infirmary')),
        180,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      expect(find.text('Worker'), findsOneWidget);
      expect(
        find.text('Choose a worker · Choose an item'),
        findsNothing,
      );
      expect(find.byTooltip('Choose a worker · Choose an item'), findsOneWidget);
      expect(find.textContaining('Record the 5 CP investment.'), findsNothing);
      expect(find.textContaining('Unlock workshops with'), findsNothing);
      expect(find.text('Production area'), findsNothing);
      expect(find.text('Starting workshop'), findsNothing);
      expect(find.text('One worker per area.'), findsNothing);
      await _capture(tester, 'royal-area-$scale');
      final estimate = find.text('Income');
      await tester.ensureVisible(estimate);
      await tester.tap(estimate);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Rare roll'));
      expect(find.textContaining('Enter your worker'), findsNothing);
      await _capture(tester, 'royal-income-$scale');
      expect(tester.takeException(), isNull);
    });
  }
}

Future<void> _host(WidgetTester tester, double scale, Widget child) async {
  const viewport = Size(1200, 800);
  await tester.binding.setSurfaceSize(viewport);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData.dark().copyWith(
        textTheme: ThemeData.dark().textTheme.apply(fontFamily: 'Segoe UI'),
      ),
      home: ResourceMapChromeTheme(
        data: ResourceMapChromeThemeData.glassDock,
        child: MediaQuery(
          data: MediaQueryData(
            size: viewport,
            textScaler: TextScaler.linear(scale),
            disableAnimations: true,
          ),
          child: RepaintBoundary(
            key: const ValueKey('detail-review-capture'),
            child: Scaffold(
              backgroundColor: const Color(0xff08161d),
              body: Padding(padding: const EdgeInsets.all(20), child: child),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _capture(WidgetTester tester, String name) => captureMapMenu(
  tester,
  boundary: find.byKey(const ValueKey('detail-review-capture')),
  name: name,
);
