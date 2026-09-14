import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bdo_map_core/src/lodging/lodging_data.dart';
import 'package:bdo_map_core/src/lodging/town_house_investment.dart';
import 'package:bdo_map_core/src/widgets/town_house_panel.dart';
import 'package:bdo_map_core/src/widgets/house_use_icon.dart';
import 'package:bdo_map_core/src/widgets/worker_activity_style.dart';
import 'package:bdo_map_core/src/model/resource_map_data.dart';
import 'package:bdo_map_core/src/widgets/resource_map_atlas_shell.dart';
import 'package:bdo_map_core/src/widgets/resource_map_chrome_theme.dart';
import 'package:bdo_map_core/src/widgets/resource_map_panel_metrics.dart';

void main() {
  final data = LodgingDataset.fromJsonString(
    File('assets/data/lodging_houses.json').readAsStringSync(),
  );
  final altinova = data.townsByNodeId['1101']!;
  testWidgets('workshop selector keeps the application font family', (
    tester,
  ) async {
    await tester.pumpWidget(_app(altinova, fontFamily: 'Housing test UI'));
    await tester.pumpAndSettle();
    final add = find.byKey(const ValueKey('house-add-workshop'));
    final dropdown = tester.widget<DropdownButton<int>>(add);
    expect(dropdown.style?.fontFamily, 'Housing test UI');
    expect(dropdown.style?.fontSize, TownHousePanelMetrics.primary);
    dropdown.onChanged!(12);
    await tester.pumpAndSettle();
    expect(find.text('Add another workshop'), findsOneWidget);
    expect(
      tester.widget<DropdownButton<int>>(add).style?.fontFamily,
      'Housing test UI',
    );
    expect(tester.takeException(), isNull);
  });
  for (final chrome in [
    ResourceMapChromeThemeData.glassDock,
    ResourceMapChromeThemeData.ghostLedger,
  ]) {
    testWidgets('housing keeps compact form density in ${chrome.variant}', (
      tester,
    ) async {
      await tester.pumpWidget(_app(altinova, chrome: chrome, width: 420));
      await tester.pumpAndSettle();
      final panel = find.byKey(
        const ValueKey('resource-map-town-housing-1101'),
      );
      expect(tester.getSize(panel).height, closeTo(205, 1));
      for (final type in [1, 2, 3]) {
        final goal = find.byKey(ValueKey('house-goal-$type'));
        expect(tester.getSize(goal).height, 40);
        final art = tester.widget<HouseUseIcon>(
          find.descendant(of: goal, matching: find.byType(HouseUseIcon)),
        );
        expect(art.size, 28);
        final label = find.descendant(
          of: goal,
          matching: find.text(switch (type) {
            1 => 'Lodging',
            2 => 'Storage',
            _ => 'Stable',
          }),
        );
        expect(DefaultTextStyle.of(tester.element(label)).style.fontSize, 14);
        for (final step in ['minus', 'plus']) {
          expect(
            tester
                .getSize(find.byKey(ValueKey('house-goal-$step-$type')))
                .height,
            36,
          );
        }
      }
      expect(find.text('0 beds'), findsOneWidget);
      expect(find.text('0 slots'), findsNWidgets(2));

      final add = find.byKey(const ValueKey('house-add-workshop'));
      tester.widget<DropdownButton<int>>(add).onChanged!(12);
      await tester.pumpAndSettle();
      final workshop = find.byKey(const ValueKey('house-goal-12'));
      final workshopName = find.descendant(
        of: workshop,
        matching: find.text('Armor Workshop'),
      );
      expect(
        tester.getSize(workshop).height,
        // The synthetic test font wraps this name. Keep that content while
        // limiting its level control and padding to 28 + 6 + 4 pixels.
        closeTo(tester.getSize(workshopName).height + 38, 1),
      );
      expect(find.text('Armor Workshop · Lv. 1'), findsOneWidget);
      expect(find.text('Connection'), findsOneWidget);
      expect(find.text('2 CP'), findsOneWidget);
      expect(find.byType(BackdropFilter), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
    for (final scale in [1.0, 2.0]) {
      testWidgets(
        'house panel fits 320px at $scale text in ${chrome.variant}',
        (tester) async {
          await tester.pumpWidget(_app(altinova, chrome: chrome, scale: scale));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          expect(find.byType(BackdropFilter), findsOneWidget);
          expect(find.byType(HouseUseIcon), findsWidgets);
          expect(find.text('Invest in'), findsNothing);
          expect(find.textContaining('Max. house'), findsNothing);
          expect(find.textContaining('owned'), findsNothing);
          final add = find.byKey(const ValueKey('house-add-workshop'));
          tester.widget<DropdownButton<int>>(add).onChanged!(1403);
          await tester.pumpAndSettle();
          expect(find.byKey(const ValueKey('house-goal-1403')), findsOneWidget);
          expect(find.text('Add another workshop'), findsOneWidget);
          final available = tester.widget<DropdownButton<int>>(add).items!;
          expect(available.any((item) => item.value == 1403), isFalse);
          tester.widget<DropdownButton<int>>(add).onChanged!(16);
          await tester.pumpAndSettle();
          expect(find.byKey(const ValueKey('house-goal-16')), findsOneWidget);
          expect(find.byKey(const ValueKey('house-goal-1403')), findsOneWidget);
          final removal = find.byKey(const ValueKey('house-goal-minus-1403'));
          await tester.ensureVisible(removal);
          await tester.tap(removal);
          await tester.pumpAndSettle();
          expect(find.byKey(const ValueKey('house-goal-1403')), findsNothing);
          expect(tester.takeException(), isNull);
          expect(find.byType(Scrollbar), findsNothing);
          expect(find.byType(RawScrollbar), findsNothing);
        },
      );
    }
  }
  test('housing and resource menus share compact readable density', () {
    expect(TownHousePanelMetrics.primary, 14);
    expect(TownHousePanelMetrics.artwork, 28);
    expect(TownHousePanelMetrics.rowHeight, 40);
    expect(ResourceMapPanelMetrics.primary, 14);
    expect(ResourceMapPanelMetrics.artwork, 30);
    expect(ResourceMapPanelMetrics.rowHeight, 40);
  });
  for (final width in [320.0, 340.0, 380.0]) {
    testWidgets('workshop controls align with capacity at $width pixels', (
      tester,
    ) async {
      await tester.pumpWidget(_app(altinova, width: width));
      await tester.pumpAndSettle();
      final add = find.byKey(const ValueKey('house-add-workshop'));
      tester.widget<DropdownButton<int>>(add).onChanged!(12);
      await tester.pumpAndSettle();
      final workshopPlus = find.byKey(const ValueKey('house-goal-plus-12'));
      final workshopMinus = find.byKey(const ValueKey('house-goal-minus-12'));
      final workshopName = find.descendant(
        of: find.byKey(const ValueKey('house-goal-12')),
        matching: find.text('Armor Workshop'),
      );
      expect(
        tester.getCenter(workshopPlus).dy,
        closeTo(tester.getTopLeft(workshopName).dy + 10, 4),
      );
      for (final type in [1, 2, 3]) {
        expect(
          tester.getCenter(workshopPlus).dx,
          closeTo(
            tester.getCenter(find.byKey(ValueKey('house-goal-plus-$type'))).dx,
            .1,
          ),
        );
        expect(
          tester.getCenter(workshopMinus).dx,
          closeTo(
            tester.getCenter(find.byKey(ValueKey('house-goal-minus-$type'))).dx,
            .1,
          ),
        );
      }
      expect(find.byTooltip('Remove workshop'), findsNothing);
      await tester.tap(workshopPlus);
      await tester.pumpAndSettle();
      await tester.tap(workshopMinus);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('house-goal-12')), findsOneWidget);
      await tester.tap(workshopMinus);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('house-goal-12')), findsNothing);
      expect(
        tester
            .widget<DropdownButton<int>>(add)
            .items!
            .any((item) => item.value == 12),
        isTrue,
      );
      expect(tester.takeException(), isNull);
    });
  }
  test('activity icons use bundled in-game node artwork', () {
    expect(BdoWorkerActivity.values.map(bdoWorkerActivitySourceIconType), [
      7,
      4,
      8,
      6,
      11,
      15,
    ]);
    for (final activity in BdoWorkerActivity.values) {
      expect(
        File(
          bdoNodeIconAssetPath(
            bdoWorkerActivitySourceIconType(activity),
            active: true,
          ),
        ).existsSync(),
        isTrue,
      );
    }
  });
  testWidgets('full addresses wrap and details expand below the selected row', (
    tester,
  ) async {
    final town = data.townsByNodeId['601']!;
    final house = town.houses.firstWhere(
      (h) => h.name == 'Workshop District 1-1, Rm. 2',
    );
    await tester.pumpWidget(_app(town, selected: house.id));
    await tester.pumpAndSettle();
    final name = tester.widget<Text>(find.text(house.name));
    expect(name.maxLines, isNull);
    expect(name.overflow, isNull);
    final row = find.byKey(ValueKey('resource-map-house-row-${house.id}'));
    final detail = find.byKey(
      ValueKey('resource-map-selected-house-${house.id}'),
    );
    expect(
      tester.getTopLeft(detail).dy,
      greaterThan(tester.getTopLeft(row).dy),
    );
    expect(tester.takeException(), isNull);
  });
  test('native texture mapping distinguishes common workshop types', () {
    expect(
      sha256
          .convert(
            File('assets/images/house_icons/houseicon.png').readAsBytesSync(),
          )
          .toString(),
      'c7345dee93f887da1964da1d8f75e9d97a6a1522b11ef1e508c2f3cf4adfac87',
    );
    expect(houseUseIconGroup(14), 7); // Carpentry saw
    expect(houseUseIconGroup(1403), 16); // Furniture chair
    expect(houseUseIconGroup(1510), 17); // Local specialties gear, as in game
    expect(houseUseIconRect(1), const Rect.fromLTWH(189, 265, 18, 18));
    expect(houseUseIconRect(2), const Rect.fromLTWH(208, 265, 18, 18));
    expect(houseUseIconRect(1428), houseUseIconRect(1403));
  });
}

Widget _app(
  LodgingTown town, {
  ResourceMapChromeThemeData chrome = ResourceMapChromeThemeData.glassDock,
  double scale = 1,
  double width = 320,
  String? selected,
  String? fontFamily,
}) {
  var goals = <TownHouseGoal>[
    const TownHouseGoal(1, 0),
    const TownHouseGoal(2, 0),
    const TownHouseGoal(3, 0),
  ];
  return MaterialApp(
    theme: ThemeData.dark().copyWith(
      textTheme: ThemeData.dark().textTheme.apply(fontFamily: fontFamily),
    ),
    home: MediaQuery(
      data: MediaQueryData(
        textScaler: TextScaler.linear(scale),
        disableAnimations: true,
      ),
      child: ResourceMapChromeTheme(
        data: chrome,
        child: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: width,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 580),
                child: ResourceMapAtlasWorkspace(
                  title: town.name,
                  shrinkWrap: true,
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(12),
                    child: StatefulBuilder(
                      builder: (context, setState) => TownHousePanel(
                        town: town,
                        goals: goals,
                        plan: TownHouseInvestmentPlanner.solve(
                          town: town,
                          goals: goals,
                        ),
                        owned: const {},
                        ownedUsages: const {},
                        selectedHouseId: selected,
                        browseAll: false,
                        onGoalsChanged: (value) =>
                            setState(() => goals = value),
                        onSelectHouse: (value) =>
                            setState(() => selected = value),
                        onOwnedChanged: (_) {},
                        onUseChanged: (_, _) {},
                        onBrowseChanged: (_) {},
                        onFit: () {},
                        onShopLodging: () {},
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
