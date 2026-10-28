import 'dart:io';
import 'dart:ui' as ui;

import 'package:bdo_map_core/bdo_map_core.dart';
import 'package:bdo_map_core/src/lodging/town_house_investment.dart';
import 'package:bdo_map_core/src/widgets/resource_map_atlas_shell.dart';
import 'package:bdo_map_core/src/widgets/resource_map_field_desk.dart';
import 'package:bdo_map_core/src/widgets/resource_map_panel_metrics.dart';
import 'package:bdo_map_core/src/widgets/town_house_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  testWidgets(
    'commands protect text with readable glass rather than blurred glyphs',
    (tester) async {
      const chrome = ResourceMapChromeThemeData.ghostLedger;
      await tester.pumpWidget(
        _testApp(
          Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 370,
              child: ResourceMapAtlasCommandMenu(
                semanticsLabel: 'Workers',
                actions: [
                  ResourceMapAtlasCommandAction(
                    key: const ValueKey('find-nodes'),
                    label: 'Find nodes',
                    icon: const Icon(Icons.travel_explore),
                    onPressed: () {},
                  ),
                ],
              ),
            ),
          ),
          chrome: chrome,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(BackdropFilter), findsNothing);
      expect(find.byType(ResourceMapPill), findsOneWidget);
      final label = tester.widget<Text>(find.text('Find nodes'));
      expect(label.style!.fontSize, 16);
      expect(label.style!.fontWeight, FontWeight.w700);
      final textStyle = DefaultTextStyle.of(
        tester.element(find.text('Find nodes')),
      ).style;
      expect(textStyle.shadows ?? const <Shadow>[], isEmpty);
      for (final style in [ResourceMapChromeThemeData.glassDock, chrome]) {
        for (final color in [
          ...style.readingSurfaceGradient.colors,
          ...style.taskStripGradient.colors,
        ]) {
          expect(
            color.a,
            greaterThanOrEqualTo(.85),
            reason: 'Map labels must not compete beneath reading surfaces.',
          );
          final backing = Color.alphaBlend(color, Colors.white);
          final bright = style.text.computeLuminance();
          final dark = backing.computeLuminance();
          expect((bright + .05) / (dark + .05), greaterThanOrEqualTo(4.5));
        }
      }
    },
  );

  testWidgets('atlas dock exposes compact selected actions', (tester) async {
    var workersOpened = false;
    await tester.pumpWidget(
      _testApp(
        ResourceMapAtlasDock(
          primaryActions: <ResourceMapAtlasDockAction>[
            ResourceMapAtlasDockAction(
              key: const ValueKey<String>('map-action'),
              label: 'Map',
              icon: const Icon(Icons.public_rounded),
              onPressed: () {},
            ),
            ResourceMapAtlasDockAction(
              key: const ValueKey<String>('workers-action'),
              label: 'Workers',
              icon: const Icon(Icons.hub_rounded),
              selected: true,
              badge: '3',
              onPressed: () => workersOpened = true,
            ),
          ],
        ),
      ),
    );

    final workers = find.byKey(const ValueKey<String>('workers-action'));
    expect(workers, findsOneWidget);
    expect(
      tester.getSemantics(workers).flagsCollection.isSelected,
      ui.Tristate.isTrue,
    );
    expect(find.text('3'), findsNothing);
    expect(find.text('Workers'), findsOneWidget);
    expect(tester.getSize(workers).height, 48);
    expect(
      tester
          .getRect(workers)
          .contains(tester.getRect(find.text('Workers')).bottomRight),
      isTrue,
    );
    await tester.tap(workers);
    expect(workersOpened, isTrue);
    expect(find.byType(Scrollbar), findsNothing);
    expect(find.byType(RawScrollbar), findsNothing);
  });

  testWidgets('atlas search and workspace keep one clear task surface', (
    tester,
  ) async {
    final controller = TextEditingController();
    final focusNode = FocusNode();
    addTearDown(controller.dispose);
    addTearDown(focusNode.dispose);
    var minimized = false;
    var closed = false;

    await tester.pumpWidget(
      _testApp(
        Column(
          children: <Widget>[
            ResourceMapAtlasSearch(
              controller: controller,
              focusNode: focusNode,
              hintText: 'Search the world',
              scopeControl: const Icon(Icons.tune_rounded),
              onChanged: (_) {},
              onSubmitted: (_) {},
              onTap: () {},
              onClear: controller.clear,
            ),
            const SizedBox(height: 12),
            Expanded(
              child: ResourceMapAtlasWorkspace(
                title: 'Gathering',
                leading: const Icon(Icons.nature_rounded),
                onMinimize: () => minimized = true,
                onClose: () => closed = true,
                child: const Center(child: Text('Focused task')),
              ),
            ),
          ],
        ),
      ),
    );

    expect(find.text('Search the world'), findsOneWidget);
    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.decoration!.filled, isFalse);
    expect(field.style!.fontSize, ResourceMapPanelMetrics.primary);
    expect(find.text('Focused task'), findsOneWidget);
    await tester.tap(
      find.byKey(
        const ValueKey<String>('resource-map-atlas-workspace-minimize'),
      ),
    );
    await tester.tap(
      find.byKey(const ValueKey<String>('resource-map-atlas-workspace-close')),
    );
    expect(minimized, isTrue);
    expect(closed, isTrue);
    expect(find.byType(Scrollbar), findsNothing);
    expect(find.byType(RawScrollbar), findsNothing);
  });

  testWidgets('Ghost Ledger dock is a typographic instrument, not icon boxes', (
    tester,
  ) async {
    await tester.pumpWidget(
      _testApp(
        ResourceMapAtlasDock(
          primaryActions: <ResourceMapAtlasDockAction>[
            ResourceMapAtlasDockAction(
              key: const ValueKey<String>('ghost-workers-action'),
              label: 'Workers',
              icon: const Icon(Icons.hub_rounded),
              selected: true,
              onPressed: () {},
            ),
          ],
        ),
        chrome: ResourceMapChromeThemeData.ghostLedger,
      ),
    );

    final action = find.byKey(const ValueKey<String>('ghost-workers-action'));
    expect(find.text('WORKERS'), findsOneWidget);
    expect(tester.getSize(action).height, 48);
    expect(
      tester
          .getRect(action)
          .contains(tester.getRect(find.text('WORKERS')).bottomRight),
      isTrue,
    );
    expect(find.byType(Card), findsNothing);
  });

  testWidgets('atlas inspector keeps Back, expand, and Close distinct', (
    tester,
  ) async {
    var wentBack = false;
    var expanded = false;
    var closed = false;
    await tester.pumpWidget(
      _testApp(
        ResourceMapAtlasInspector(
          expanded: false,
          backLabel: 'Back to material',
          onBack: () => wentBack = true,
          onToggleExpanded: () => expanded = true,
          onClose: () => closed = true,
          child: const Text('Selected place'),
        ),
      ),
    );

    await tester.tap(
      find.byKey(const ValueKey<String>('resource-map-task-back')),
    );
    await tester.tap(
      find.byKey(const ValueKey<String>('resource-map-desktop-details-expand')),
    );
    await tester.tap(
      find.byKey(const ValueKey<String>('resource-map-task-close')),
    );
    expect(wentBack, isTrue);
    expect(expanded, isTrue);
    expect(closed, isTrue);
  });

  for (final chrome in [
    ResourceMapChromeThemeData.glassDock,
    ResourceMapChromeThemeData.ghostLedger,
  ]) {
    testWidgets('${chrome.variant.name} uses the approved reading sizes', (
      tester,
    ) async {
      await tester.pumpWidget(
        _testApp(
          Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: ResourceMapPanelMetrics.menuWidth,
              child: ResourceMapAtlasCommandMenu(
                semanticsLabel: 'Workers',
                actions: [
                  ResourceMapAtlasCommandAction(
                    key: const ValueKey('size-check-row'),
                    label: 'Find nodes',
                    icon: const Icon(Icons.location_on_outlined),
                    onPressed: () {},
                  ),
                ],
              ),
            ),
          ),
          chrome: chrome,
        ),
      );
      await tester.pumpAndSettle();
      final row = find.byKey(const ValueKey('size-check-row'));
      final label = tester.widget<Text>(find.text('Find nodes'));
      expect(tester.getSize(row).height, ResourceMapPanelMetrics.optionHeight);
      expect(label.style!.fontSize, ResourceMapPanelMetrics.optionLabel);
      expect(
        IconTheme.of(
          tester.element(find.byIcon(Icons.location_on_outlined)),
        ).size,
        ResourceMapPanelMetrics.optionArtwork,
      );
      expect(
        tester.getSize(find.byType(ResourceMapAtlasCommandMenu)).height,
        ResourceMapPanelMetrics.optionHeight +
            ResourceMapPanelMetrics.optionGap +
            2,
      );
    });

    testWidgets(
      '${chrome.variant.name} search grows with results and retains focus',
      (tester) async {
        final controller = TextEditingController();
        final focus = FocusNode();
        addTearDown(controller.dispose);
        addTearDown(focus.dispose);
        var rows = 1;
        var expanded = false;
        late StateSetter update;
        await tester.pumpWidget(
          _testApp(
            Align(
              alignment: Alignment.topLeft,
              child: StatefulBuilder(
                builder: (context, setState) {
                  update = setState;
                  return ResourceMapDiscoveryLens(
                    maximumWidth: 500,
                    expandedHeight: 450,
                    expanded: expanded,
                    resultLabel: '$rows',
                    onClose: () => setState(() => expanded = false),
                    search: ResourceMapAtlasSearch(
                      controller: controller,
                      focusNode: focus,
                      hintText: 'Search the map',
                      scopeControl: const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 12),
                        child: Text('All'),
                      ),
                      onChanged: (_) => setState(() => expanded = true),
                      onSubmitted: (_) {},
                      onTap: () {},
                      onClear: controller.clear,
                    ),
                    results: ListView.builder(
                      shrinkWrap: true,
                      padding: EdgeInsets.zero,
                      itemCount: rows,
                      itemBuilder: (_, index) => SizedBox(
                        height: ResourceMapPanelMetrics.rowHeight,
                        child: Text('Material $index'),
                      ),
                    ),
                  );
                },
              ),
            ),
            chrome: chrome,
          ),
        );
        final field = find.byType(TextField);
        await tester.enterText(field, 'c');
        await tester.pumpAndSettle();
        expect(focus.hasFocus, isTrue);
        final lens = find.byType(ResourceMapDiscoveryLens);
        final shortHeight = tester.getSize(lens).height;
        expect(shortHeight, closeTo(ResourceMapPanelMetrics.rowHeight * 2, 1));

        await tester.enterText(field, 'cow');
        await tester.pumpAndSettle();
        expect(controller.text, 'cow');
        expect(focus.hasFocus, isTrue);

        update(() => rows = 12);
        await tester.pumpAndSettle();
        expect(tester.getSize(lens).height, 450);
        expect(focus.hasFocus, isTrue);

        update(() => rows = 1);
        await tester.pumpAndSettle();
        expect(tester.getSize(lens).height, shortHeight);
        expect(tester.takeException(), isNull);
        expect(find.byType(Scrollbar), findsNothing);
        expect(find.byType(RawScrollbar), findsNothing);
      },
    );
  }

  testWidgets('large text scrolls the dock horizontally inside its top band', (
    tester,
  ) async {
    var savedOpened = false;
    await tester.pumpWidget(
      _testApp(
        Align(
          alignment: Alignment.topLeft,
          child: ResourceMapAtlasDock(
            maximumWidth: 330,
            primaryActions: [
              ResourceMapAtlasDockAction(
                key: const ValueKey('large-gathering'),
                label: 'Gathering',
                icon: const Icon(Icons.grass_rounded),
                onPressed: () {},
              ),
              ResourceMapAtlasDockAction(
                key: const ValueKey('large-workers'),
                label: 'Workers',
                icon: const Icon(Icons.work_outline),
                onPressed: () {},
              ),
            ],
            secondaryActions: [
              ResourceMapAtlasDockAction(
                key: const ValueKey('large-saved'),
                label: 'Saved',
                icon: const Icon(Icons.star_outline),
                onPressed: () => savedOpened = true,
              ),
            ],
          ),
        ),
        textScale: 2,
      ),
    );
    expect(tester.getSize(find.byType(ResourceMapAtlasDock)).width, 330);
    expect(tester.getSize(find.byType(ResourceMapAtlasDock)).height, 52);
    final saved = find.byKey(const ValueKey('large-saved'));
    await Scrollable.ensureVisible(tester.element(saved));
    await tester.pumpAndSettle();
    await tester.tap(saved);
    expect(savedOpened, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('workspace titles wrap and short content does not fill height', (
    tester,
  ) async {
    const title = 'A long material name remains fully readable';
    await tester.pumpWidget(
      _testApp(
        Align(
          alignment: Alignment.topLeft,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 320, maxHeight: 500),
            child: ResourceMapAtlasWorkspace(
              title: title,
              shrinkWrap: true,
              onBack: () {},
              onClose: () {},
              child: const SizedBox(height: 52, child: Text('Material')),
            ),
          ),
        ),
        textScale: 2,
      ),
    );
    final text = tester.widget<Text>(find.text(title));
    expect(text.maxLines, isNull);
    expect(text.overflow, isNot(TextOverflow.ellipsis));
    expect(text.style!.fontSize, ResourceMapPanelMetrics.primary);
    expect(
      tester.getSize(find.byType(ResourceMapAtlasWorkspace)).height,
      lessThan(500),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('compact workshop level picker changes the same goal', (
    tester,
  ) async {
    final dataFile = [
      File('assets/data/lodging_houses.json'),
      File('packages/bdo_map_core/assets/data/lodging_houses.json'),
    ].firstWhere((file) => file.existsSync());
    final town = LodgingDataset.fromJsonString(
      dataFile.readAsStringSync(),
    ).townsByNodeId['1101']!;
    var goals = [
      const TownHouseGoal(1, 0),
      const TownHouseGoal(2, 0),
      const TownHouseGoal(3, 0),
      const TownHouseGoal(12, 1),
    ];
    await tester.pumpWidget(
      _testApp(
        Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: 320,
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
                  selectedHouseId: null,
                  browseAll: false,
                  onGoalsChanged: (value) => setState(() => goals = value),
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
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('house-workshop-level-12')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Lv. 2+'));
    await tester.pumpAndSettle();
    expect(goals.singleWhere((goal) => goal.typeId == 12).minimumLevel, 2);
    expect(goals.singleWhere((goal) => goal.typeId == 12).amount, 1);
    await tester.tap(find.byKey(const ValueKey('house-goal-minus-12')));
    await tester.pumpAndSettle();
    expect(goals.any((goal) => goal.typeId == 12), isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'native task journey stays inside 700-1200px at both text scales',
    (tester) async {
      final windowsDirectory = Platform.environment['WINDIR'] ?? 'C:/Windows';
      final flutterRoot = Platform.environment['FLUTTER_ROOT'];
      final materialFont = flutterRoot == null
          ? File(
              '${File(Platform.resolvedExecutable).parent.parent.parent.path}'
              '/material_fonts/MaterialIcons-Regular.otf',
            )
          : File(
              '$flutterRoot/bin/cache/artifacts/material_fonts/'
              'MaterialIcons-Regular.otf',
            );
      await tester.runAsync(() async {
        await (FontLoader('Segoe UI')..addFont(
              File(
                '$windowsDirectory/Fonts/segoeui.ttf',
              ).readAsBytes().then(ByteData.sublistView),
            ))
            .load();
        await (FontLoader('MaterialIcons')
              ..addFont(materialFont.readAsBytes().then(ByteData.sublistView)))
            .load();
      });
      final dataFile = [
        File('assets/data/resource_map.json'),
        File('packages/bdo_map_core/assets/data/resource_map.json'),
      ].firstWhere((file) => file.existsSync());
      final dataset = BdoResourceMapLoader.parse(dataFile.readAsStringSync());
      final cache = Directory.systemTemp.createTempSync('atlas_native_sizes_');
      final client = MockClient((_) async => http.Response('', 404));
      addTearDown(() async {
        client.close();
        await cache.delete(recursive: true);
        await tester.binding.setSurfaceSize(null);
      });

      for (final style in ResourceMapInterfaceStyle.values) {
        for (final width in [700.0, 900.0, 1200.0]) {
          for (final scale in [1.0, 2.0]) {
            final viewport = Size(width, 752);
            await tester.binding.setSurfaceSize(viewport);
            await tester.pumpWidget(
              MaterialApp(
                key: ValueKey('${style.id}-$width-$scale'),
                home: MediaQuery(
                  data: MediaQueryData(
                    size: viewport,
                    disableAnimations: true,
                    textScaler: TextScaler.linear(scale),
                  ),
                  child: ResourceMapChromeTheme(
                    data: style == ResourceMapInterfaceStyle.ghostLedger
                        ? ResourceMapChromeThemeData.ghostLedger
                        : ResourceMapChromeThemeData.glassDock,
                    child: BdoResourceMap(
                      dataset: dataset,
                      interfaceStyle: style,
                      cacheDirectory: cache,
                      tileHttpClient: client,
                      showSourceNotice: false,
                    ),
                  ),
                ),
              ),
            );
            await tester.pumpAndSettle();
            void expectOneJourney() {
              final journey = find.byType(ResourceMapJourneySurface);
              expect(journey.evaluate().length, lessThanOrEqualTo(1));
              final desk = find.byType(ResourceMapFieldDesk);
              expect(desk, findsOneWidget);
              for (final surface in [
                desk,
                if (journey.evaluate().isNotEmpty) journey,
              ]) {
                final rect = tester.getRect(surface);
                expect(rect.left, greaterThanOrEqualTo(0));
                expect(rect.top, greaterThanOrEqualTo(0));
                expect(rect.right, lessThanOrEqualTo(width));
                expect(rect.bottom, lessThanOrEqualTo(viewport.height));
              }
              expect(find.byType(ResourceMapAtlasNavigator), findsNothing);
              expect(find.byType(ResourceMapAtlasWorkspace), findsNothing);
              expect(find.byType(ResourceMapAtlasInspector), findsNothing);
            }

            Future<void> tapAction(String key) async {
              final action = find.byKey(ValueKey(key));
              await tester.ensureVisible(action);
              await tester.tap(action);
              await tester.pumpAndSettle();
              expectOneJourney();
            }

            expectOneJourney();
            final journeyRect = tester.getRect(
              find.byType(ResourceMapFieldDesk),
            );
            final searchRect = tester.getRect(find.byType(TextField));
            expect(journeyRect.contains(searchRect.topLeft), isTrue);
            expect(
              journeyRect.contains(searchRect.bottomRight - const Offset(1, 1)),
              isTrue,
            );
            for (final key in [
              'resource-map-home-find-material',
              'resource-map-home-worker-income',
              'resource-map-home-checklist',
            ]) {
              final action = find.byKey(ValueKey(key));
              await tester.ensureVisible(action);
              await tester.pumpAndSettle();
              final label = find
                  .descendant(of: action, matching: find.byType(Text))
                  .first;
              final actionRect = tester.getRect(action);
              final labelRect = tester.getRect(label);
              final text = tester.widget<Text>(label);
              expect(text.style!.fontSize, ResourceMapPanelMetrics.optionLabel);
              expect(text.overflow, isNot(TextOverflow.ellipsis));
              expect(actionRect.contains(labelRect.topLeft), isTrue);
              expect(
                actionRect.contains(labelRect.bottomRight - const Offset(1, 1)),
                isTrue,
                reason: 'Task labels must remain fully inside their action.',
              );
            }

            await tapAction('resource-map-home-find-material');
            await tapAction('resource-map-section-oresMinerals');
            expect(
              find.byKey(const ValueKey('resource-map-resource-browser')),
              findsOneWidget,
            );
            await tapAction('resource-map-task-back');
            expect(
              find.byKey(const ValueKey('resource-map-section-oresMinerals')),
              findsOneWidget,
            );
            await tapAction('resource-map-home-button');
            expect(
              find.byKey(const ValueKey('resource-map-home-find-material')),
              findsOneWidget,
            );
            await tapAction('resource-map-home-more-tools');
            await tapAction('resource-map-home-browse-nodes');
            await tapAction('resource-map-task-back');
            expect(
              find.byKey(const ValueKey('resource-map-home-find-material')),
              findsOneWidget,
            );
            expect(
              tester.takeException(),
              isNull,
              reason: '${style.id}, $width px, ${scale * 100}% text',
            );
            expect(find.byType(Scrollbar), findsNothing);
            expect(find.byType(RawScrollbar), findsNothing);
          }
        }
      }
    },
    // This acceptance pass deliberately uses the application's Windows font.
    skip: !Platform.isWindows,
  );
}

Widget _testApp(
  Widget child, {
  ResourceMapChromeThemeData chrome = ResourceMapChromeThemeData.glassDock,
  double textScale = 1,
}) {
  return MaterialApp(
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(
        context,
      ).copyWith(textScaler: TextScaler.linear(textScale)),
      child: child!,
    ),
    home: ResourceMapChromeTheme(
      data: chrome,
      child: Scaffold(body: SizedBox(width: 900, height: 700, child: child)),
    ),
  );
}
