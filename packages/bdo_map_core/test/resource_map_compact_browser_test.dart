import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:bdo_map_core/bdo_map_core.dart';
import 'package:bdo_map_core/src/widgets/map_canvas.dart';
import 'package:bdo_map_core/src/widgets/resource_map_atlas_shell.dart';
import 'package:bdo_map_core/src/widgets/worker_activity_style.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// Real-data coverage for concise source rows and item/tool-only detail lists.
/// Original inventory artwork is read from the application's bundled catalog;
/// the complete map dataset and real public navigation are used throughout.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late BdoResourceMapDataset dataset;
  late Directory cacheDirectory;
  late MockClient tileClient;
  late Map<String, dynamic> itemIcons;
  final decodedIcons = <String, Uint8List>{};
  final favoriteChanges = <Set<String>>[];
  final nodePreferenceChanges = <BdoNodeNetworkPreferences>[];

  setUpAll(() async {
    dataset = await BdoResourceMapLoader.loadBundled();
    cacheDirectory = await Directory.systemTemp.createTemp(
      'bdo_map_compact_browser_',
    );
    tileClient = MockClient(
      (_) async => http.Response('', HttpStatus.notFound),
    );
    final catalog =
        jsonDecode(File('../../assets/data/app-data.json').readAsStringSync())
            as Map<String, dynamic>;
    itemIcons = <String, dynamic>{
      ...(catalog['processing'] as Map<String, dynamic>)['itemIcons']
          as Map<String, dynamic>,
      ...(catalog['cooking'] as Map<String, dynamic>)['itemIcons']
          as Map<String, dynamic>,
      ...catalog['itemIcons'] as Map<String, dynamic>,
    };
  });

  setUp(() {
    favoriteChanges.clear();
    nodePreferenceChanges.clear();
  });

  tearDownAll(() async {
    tileClient.close();
    await cacheDirectory.delete(recursive: true);
  });

  Widget originalArtwork(
    BuildContext context,
    BdoResourceDefinition resource,
    double size,
  ) {
    final encoded = itemIcons[resource.name] as String?;
    expect(
      encoded,
      isNotNull,
      reason: '${resource.name} must resolve to genuine bundled item art.',
    );
    final bytes = decodedIcons.putIfAbsent(
      resource.name,
      () => UriData.parse(encoded!).contentAsBytes(),
    );
    return Image.memory(
      bytes,
      key: ValueKey('original-item-art-${resource.id}'),
      width: size,
      height: size,
      fit: BoxFit.contain,
      gaplessPlayback: true,
    );
  }

  Future<void> openMap(
    WidgetTester tester,
    ResourceMapInterfaceStyle style, {
    double textScale = 1,
    Size viewport = const Size(1200, 800),
    BdoNodeNetworkPreferences? nodeNetworkPreferences,
  }) async {
    await tester.binding.setSurfaceSize(viewport);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(
            size: viewport,
            disableAnimations: true,
            textScaler: TextScaler.linear(textScale),
          ),
          child: ResourceMapChromeTheme(
            data: style == ResourceMapInterfaceStyle.ghostLedger
                ? ResourceMapChromeThemeData.ghostLedger
                : ResourceMapChromeThemeData.glassDock,
            child: BdoResourceMap(
              dataset: dataset,
              cacheDirectory: cacheDirectory,
              tileHttpClient: tileClient,
              showSourceNotice: false,
              interfaceStyle: style,
              resourceIconBuilder: originalArtwork,
              workerOutputIconBuilder: originalArtwork,
              nodeNetworkPreferences: nodeNetworkPreferences,
              onNodeNetworkPreferencesChanged: nodePreferenceChanges.add,
              onFavoriteResourceIdsChanged: (favorites) {
                favoriteChanges.add(Set<String>.of(favorites));
              },
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> openPlants(WidgetTester tester) async {
    await tester.tap(
      find.byKey(const ValueKey('resource-map-home-find-material')),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('resource-map-section-plantsWood')),
    );
    await tester.pumpAndSettle();
    expect(_browser, findsOneWidget);
  }

  Future<void> searchSelect(
    WidgetTester tester, {
    required String name,
    required String kind,
    required String id,
  }) async {
    await tester.enterText(
      find.byKey(const ValueKey('resource-map-atlas-search-field')),
      name,
    );
    await tester.pumpAndSettle();
    final result = find.byKey(ValueKey('resource-map-search-result-$kind-$id'));
    expect(result, findsOneWidget);
    await tester.ensureVisible(result);
    await tester.tap(result);
    await tester.pumpAndSettle();
    expect(_inspector, findsOneWidget);
  }

  for (final style in ResourceMapInterfaceStyle.values) {
    testWidgets(
      '${style.id}: source badges open only the pictured material and preserve the plan',
      (tester) async {
        final acacia = dataset.fieldSourcesById['field-source:acacia-tree']!;
        final birch = dataset.fieldSourcesById['field-source:birch-tree']!;
        final acaciaSap = dataset.resourcesById['item:5013']!;
        final birchSap = dataset.resourcesById['item:5004']!;
        final iron = dataset.resourcesById['item:4001']!;
        await openMap(
          tester,
          style,
          nodeNetworkPreferences: BdoNodeNetworkPreferences(
            desiredResourceNodeCounts: <String, int>{iron.id: 2},
          ),
        );
        await openPlants(tester);

        // These are three separate targets: star, source name, worker plan.
        await tester.tap(
          find.byKey(ValueKey('resource-map-favorite-source-${acacia.id}')),
        );
        await tester.pumpAndSettle();
        expect(favoriteChanges.last, <String>{'map:fieldSource:${acacia.id}'});
        expect(nodePreferenceChanges, isEmpty);
        expect(_inspector, findsNothing);
        await tester.tap(
          find.descendant(
            of: _sourceRow(acacia.id),
            matching: find.text(acacia.name),
          ),
        );
        await tester.pumpAndSettle();
        expect(_inspector, findsOneWidget);
        expect(
          find.byKey(ValueKey('resource-map-atlas-product-${acaciaSap.id}')),
          findsOneWidget,
        );
        expect(nodePreferenceChanges, isEmpty);
        await tester.tap(find.byKey(const ValueKey('resource-map-task-back')));
        await tester.pumpAndSettle();
        expect(_browser, findsOneWidget);

        var badge = _workerBadge(_sourceRow(acacia.id), acaciaSap.id);
        expect(badge.hitTestable(), findsOneWidget);
        expect(
          find.descendant(
            of: _sourceRow(acacia.id),
            matching: find.byKey(ValueKey('original-item-art-${acaciaSap.id}')),
          ),
          findsOneWidget,
        );
        await tester.tap(badge);
        await tester.pumpAndSettle();
        _expectWorkerTarget(tester, acaciaSap);
        expect(
          nodePreferenceChanges.last.desiredResourceNodeCounts,
          <String, int>{iron.id: 2, acaciaSap.id: 1},
        );
        expect(favoriteChanges, hasLength(1));
        await tester.tap(
          find.byKey(ValueKey('resource-map-node-target-plus-${acaciaSap.id}')),
        );
        await _settleWorkerPreview(tester);
        expect(
          nodePreferenceChanges.last.desiredResourceNodeCounts,
          <String, int>{iron.id: 2, acaciaSap.id: 2},
        );

        await tester.tap(find.byKey(const ValueKey('resource-map-task-back')));
        await tester.pumpAndSettle();
        await _scrollBrowserTo(tester, _sourceRow(birch.id));
        badge = _workerBadge(_sourceRow(birch.id), birchSap.id);
        expect(
          find.descendant(of: badge, matching: find.text('6')),
          findsNothing,
          reason:
              'The shortcut keeps its material target without a passive count.',
        );
        expect(
          find.descendant(
            of: _sourceRow(birch.id),
            matching: find.byKey(ValueKey('original-item-art-${birchSap.id}')),
          ),
          findsOneWidget,
        );
        await tester.tap(badge);
        await tester.pumpAndSettle();
        _expectWorkerTarget(tester, birchSap);
        expect(
          nodePreferenceChanges.last.desiredResourceNodeCounts,
          <String, int>{iron.id: 2, acaciaSap.id: 2, birchSap.id: 1},
          reason:
              'Opening a multi-product source must not also add Timber or Log.',
        );
        _expectNoOverflow(tester);
      },
    );

    testWidgets(
      '${style.id}: worker badge falls back to an eligible source product without adding unrelated loot',
      (tester) async {
        await openMap(tester, style);
        await tester.tap(
          find.byKey(const ValueKey('resource-map-home-find-material')),
        );
        await tester.pumpAndSettle();
        final category = find.byKey(
          const ValueKey('resource-map-section-seafoodMarine'),
        );
        await tester.ensureVisible(category);
        await tester.tap(category);
        await tester.pumpAndSettle();
        final source = dataset
            .fieldSourcesById['field-source:stillcoral-coastal-gathering']!;
        final coral = dataset.resourcesById['item:6501']!;
        final row = _sourceRow(source.id);
        await _scrollBrowserTo(tester, row);
        expect(
          dataset.workerNodesForResource('item:4476'),
          isEmpty,
          reason:
              'Red Coral, the original source artwork, has no worker source.',
        );
        final badge = _workerBadge(row, coral.id);
        expect(
          find.descendant(
            of: row,
            matching: find.byTooltip('Plan worker nodes for Coral Piece'),
          ),
          findsOneWidget,
        );
        await tester.tap(badge);
        await tester.pumpAndSettle();
        _expectWorkerTarget(tester, coral);
        expect(
          nodePreferenceChanges.last.desiredResourceNodeCounts,
          <String, int>{coral.id: 1},
        );
        expect(favoriteChanges, isEmpty);
        _expectNoOverflow(tester);
      },
    );

    testWidgets(
      '${style.id}: keyboard worker badge keeps over-capacity requests intact at 200 percent text',
      (tester) async {
        final semanticsHandle = tester.ensureSemantics();
        try {
          final acaciaSap = dataset.resourcesById['item:5013']!;
          final iron = dataset.resourcesById['item:4001']!;
          final seoul = dataset.workerNodes.singleWhere(
            (node) => node.name == 'Seoul',
          );
          await openMap(
            tester,
            style,
            textScale: 2,
            nodeNetworkPreferences: BdoNodeNetworkPreferences(
              rootNodeIds: <String>{seoul.id},
              desiredResourceNodeCounts: <String, int>{
                iron.id: 2,
                acaciaSap.id: 7,
              },
            ),
          );
          await openPlants(tester);
          final badge = _workerBadge(
            _sourceRow('field-source:acacia-tree'),
            acaciaSap.id,
          );
          expect(tester.widget<TextButton>(badge).onPressed, isNotNull);
          var semantics = tester.getSemantics(badge);
          expect(semantics.flagsCollection.isButton, isTrue);
          expect(semantics.flagsCollection.isEnabled, ui.Tristate.isTrue);
          expect(semantics.label, contains(acaciaSap.name));
          expect(semantics.label, contains('4'));
          final icon = find.descendant(
            of: badge,
            matching: find.byType(BdoNodeTypeImage),
          );
          Focus.of(tester.element(icon)).requestFocus();
          await tester.pumpAndSettle();
          semantics = tester.getSemantics(badge);
          expect(semantics.flagsCollection.isFocused, ui.Tristate.isTrue);
          await tester.sendKeyEvent(LogicalKeyboardKey.enter);
          await tester.pumpAndSettle();
          _expectWorkerTarget(tester, acaciaSap);
          expect(
            nodePreferenceChanges.last.desiredResourceNodeCounts,
            <String, int>{iron.id: 2, acaciaSap.id: 7},
          );
          expect(nodePreferenceChanges.last.rootNodeIds, <String>{seoul.id});
          expect(
            tester
                .widget<Text>(
                  find.byKey(
                    ValueKey(
                      'resource-map-node-target-availability-${acaciaSap.id}',
                    ),
                  ),
                )
                .data,
            'Maximum 4',
          );
          final plus = find.byKey(
            ValueKey('resource-map-node-target-plus-${acaciaSap.id}'),
          );
          final plusButton = find.descendant(
            of: plus,
            matching: find.byType(IconButton),
          );
          expect(tester.widget<IconButton>(plusButton).onPressed, isNull);
          _expectNoOverflow(tester);
        } finally {
          semanticsHandle.dispose();
        }
      },
    );

    for (final textScale in <double>[1, 2]) {
      for (final detailCase in <({String sourceId, String tool})>[
        (sourceId: 'field-source:dairy-cow', tool: 'Milking minigame'),
        (sourceId: 'field-source:delotia', tool: 'Bare Hands or Hoe'),
        (
          sourceId: 'field-source:marni-sniper-hunting',
          tool: 'Sniper Rifle + Butcher Knife',
        ),
      ]) {
        testWidgets(
          '${style.id} ${textScale * 100}%: ${detailCase.sourceId} keeps '
          'original items primary and genuine gathering art secondary',
          (tester) async {
            await openMap(tester, style, textScale: textScale);
            final source = dataset.fieldSourcesById[detailCase.sourceId]!;
            await searchSelect(
              tester,
              name: source.name,
              kind: 'fieldSource',
              id: source.id,
            );
            if (resolveBdoGatheringTools(detailCase.tool).tools.any(
              (kind) => bdoGatheringToolAssetSourceRect(kind) != null,
            )) {
              await tester.runAsync(
                () => precacheImage(
                  const AssetImage(
                    'assets/images/gathering_tools/interaction_00.png',
                    package: bdoGatheringToolAssetPackage,
                  ),
                  tester.element(find.byType(BdoGatheringToolIcon).first),
                ),
              );
              await tester.pumpAndSettle();
            }
            for (final product in source.products) {
              expect(product.tool, detailCase.tool);
              final resource = dataset.resourcesById[product.resourceId]!;
              final row = find.byKey(
                ValueKey('resource-map-atlas-product-${resource.id}'),
              );
              await tester.ensureVisible(row);
              await tester.pumpAndSettle();
              _expectReadableOriginalRow(tester, row, resource.name);
              final tool = find.descendant(
                of: row,
                matching: find.byType(BdoGatheringToolIcon),
              );
              final indicator = tester.widget<BdoGatheringToolIcon>(tool);
              expect(indicator.tool, product.tool);
              expect(indicator.method, product.method);
              expect(indicator.size, 27);
              final selection = resolveBdoGatheringTools(product.tool);
              expect(
                tester.getSize(tool),
                Size(selection.tools.length == 1 ? 27 : 67.5, 27),
              );
              for (final kind in selection.tools) {
                _expectOriginalTool(tester, tool, kind);
              }
              expect(
                find.descendant(of: tool, matching: find.byType(CustomPaint)),
                findsNWidgets(
                  selection.tools
                      .where(
                        (kind) => bdoGatheringToolAssetSourceRect(kind) != null,
                      )
                      .length,
                ),
              );
              expect(_rowText(tester, row), <String>[
                resource.name,
                if (selection.relation == BdoGatheringToolRelation.alternative)
                  '/',
                if (selection.relation ==
                    BdoGatheringToolRelation.requiredTogether)
                  '+',
              ]);
              final item = find.descendant(
                of: row,
                matching: find.byKey(
                  ValueKey('original-item-art-${resource.id}'),
                ),
              );
              final label = find.descendant(
                of: row,
                matching: find.text(resource.name),
              );
              expect(tester.getSize(item), const Size.square(36));
              expect(
                tester.getRect(item).right,
                lessThan(tester.getRect(label).left),
              );
              expect(
                tester.getRect(label).right,
                lessThanOrEqualTo(tester.getRect(tool).left),
              );
              expect(
                tester.getRect(tool).right,
                lessThanOrEqualTo(tester.getRect(row).right),
              );
            }
            if (detailCase.sourceId == 'field-source:dairy-cow') {
              expect(source.products.single.resourceId, 'item:9065');
              expect(
                bdoGatheringToolCatalogItemName(BdoGatheringToolKind.milking),
                isNull,
              );
              expect(find.byTooltip('Milking minigame'), findsOneWidget);
              expect(
                find.bySemanticsLabel('Interaction: Milking minigame'),
                findsOneWidget,
              );
              expect(
                find.bySemanticsLabel('Required tool: Milking minigame'),
                findsNothing,
              );
              final canvas = tester.widget<BdoMapCanvas>(
                find.byType(BdoMapCanvas),
              );
              expect(canvas.gatheringSpots, hasLength(6));
              expect(canvas.workerNodes, isEmpty);
            }
            _expectBounded(tester, _inspector, const Size(1200, 800));
            _expectNoOverflow(tester);
          },
        );
      }

      testWidgets('${style.id} ${textScale * 100}%: browser shows each name once '
          'with a compact worker shortcut and no count', (tester) async {
        await openMap(tester, style, textScale: textScale);
        await openPlants(tester);

        final acacia = dataset.fieldSourcesById['field-source:acacia-tree']!;
        final acaciaRow = _sourceRow(acacia.id);
        expect(_rowText(tester, acaciaRow), <String>[acacia.name]);
        expect(
          find.descendant(
            of: acaciaRow,
            matching: find.byTooltip('Plan worker nodes for Acacia Sap'),
          ),
          findsOneWidget,
        );
        _expectReadableOriginalRow(tester, acaciaRow, acacia.name);
        final shortcut = find.descendant(
          of: acaciaRow,
          matching: find.byTooltip('Plan worker nodes for Acacia Sap'),
        );
        final favorite = find.byKey(
          ValueKey('resource-map-favorite-source-${acacia.id}'),
        );
        expect(
          tester.getRect(shortcut).right,
          lessThan(tester.getRect(favorite).left),
        );
        expect(
          tester.getRect(shortcut).center.dy,
          closeTo(tester.getRect(favorite).center.dy, 1),
          reason:
              'Worker shortcut belongs beside the star, without another text line.',
        );
        if (textScale == 1) {
          expect(tester.getSize(acaciaRow).height, inInclusiveRange(50, 58));
        }

        for (final id in <String>[
          'field-source:citron-tree',
          'field-source:delotia',
          'field-source:poisonous-swamp-plant',
        ]) {
          final source = dataset.fieldSourcesById[id]!;
          final row = _sourceRow(id);
          await _scrollBrowserTo(tester, row);
          expect(
            _rowText(tester, row),
            <String>[source.name],
            reason:
                'No product subtitle, category, point count or Region focus copy.',
          );
          _expectReadableOriginalRow(tester, row, source.name);
        }
        _expectBounded(tester, _browser, const Size(1200, 800));
        _expectNoOverflow(tester);
      });

      testWidgets(
        '${style.id} ${textScale * 100}%: Stillcoral keeps all ten loot items '
        'and original tool artwork without location copy',
        (tester) async {
          await openMap(tester, style, textScale: textScale);
          final source = dataset
              .fieldSourcesById['field-source:stillcoral-coastal-gathering']!;
          expect(source.products, hasLength(10));
          await searchSelect(
            tester,
            name: source.name,
            kind: 'fieldSource',
            id: source.id,
          );

          for (final product in source.products) {
            final resource = dataset.resourcesById[product.resourceId]!;
            final row = find.byKey(
              ValueKey('resource-map-atlas-product-${resource.id}'),
            );
            expect(row, findsOneWidget);
            await tester.ensureVisible(row);
            await tester.pumpAndSettle();
            expect(_rowText(tester, row), <String>[resource.name]);
            _expectReadableOriginalRow(tester, row, resource.name);
            final tool = find.descendant(
              of: row,
              matching: find.byType(BdoGatheringToolIcon),
            );
            expect(tool, findsOneWidget);
            expect(tester.widget<BdoGatheringToolIcon>(tool).tool, 'Hoe');
            _expectOriginalTool(tester, tool, BdoGatheringToolKind.hoe);
          }
          final detailText = _rowText(tester, _inspector);
          expect(detailText, isNot(contains('Locations')));
          expect(detailText, isNot(contains('198')));
          expect(detailText, isNot(contains(source.category)));
          expect(
            detailText.where((text) => text.contains('orange markers')),
            isEmpty,
          );
          expect(
            detailText.where((text) => text.contains('Gather · Hoe')),
            isEmpty,
          );
          final canvas = tester.widget<BdoMapCanvas>(find.byType(BdoMapCanvas));
          expect(
            canvas.gatheringPoints,
            hasLength(198),
            reason: 'Removing copy must retain real map locations.',
          );
          _expectBounded(tester, _inspector, const Size(1200, 800));
          _expectNoOverflow(tester);
        },
      );
    }

    testWidgets(
      '${style.id}: compact source favorites still open products through Saved',
      (tester) async {
        await openMap(tester, style);
        await openPlants(tester);
        final source = dataset.fieldSourcesById['field-source:acacia-tree']!;
        final favoriteKey = 'map:fieldSource:${source.id}';
        await tester.tap(
          find.byKey(ValueKey('resource-map-favorite-source-${source.id}')),
        );
        await tester.pumpAndSettle();
        expect(favoriteChanges.last, <String>{favoriteKey});
        expect(
          _browser,
          findsOneWidget,
          reason: 'Starring must not open the source.',
        );

        await tester.tap(
          find.byKey(const ValueKey('resource-map-home-button')),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('resource-map-home-saved')));
        await tester.pumpAndSettle();
        final saved = find.byKey(ValueKey('resource-map-saved-$favoriteKey'));
        expect(saved, findsOneWidget);
        await tester.tap(saved);
        await tester.pumpAndSettle();
        expect(_inspector, findsOneWidget);
        for (final product in source.products) {
          expect(
            find.byKey(
              ValueKey('resource-map-atlas-product-${product.resourceId}'),
            ),
            findsOneWidget,
          );
        }
        final unsave = find.byKey(
          ValueKey('resource-map-detail-favorite-source-${source.id}'),
        );
        await tester.tap(unsave);
        await tester.pumpAndSettle();
        expect(favoriteChanges.last, isEmpty);
        _expectNoOverflow(tester);
      },
    );

    testWidgets(
      '${style.id}: Coral Piece shows source tools and working to-do/favorite actions',
      (tester) async {
        await openMap(tester, style);
        final resource = dataset.resourcesById['item:6501']!;
        await searchSelect(
          tester,
          name: resource.name,
          kind: 'resource',
          id: resource.id,
        );
        final details = _rowText(tester, _inspector);
        expect(details, isNot(contains('Marine material')));
        expect(details, isNot(contains('160')));
        expect(details, isNot(contains('Locations')));
        for (final entry in <(String, BdoGatheringToolKind)>[
          ('field-source:coral-stoneback-crab', BdoGatheringToolKind.pickaxe),
          (
            'field-source:stillcoral-coastal-gathering',
            BdoGatheringToolKind.hoe,
          ),
        ]) {
          final source = dataset.fieldSourcesById[entry.$1]!;
          final row = find.byKey(
            ValueKey('resource-map-atlas-source-${source.id}'),
          );
          expect(row, findsOneWidget);
          expect(_rowText(tester, row), <String>[source.name]);
          final tool = find.descendant(
            of: row,
            matching: find.byType(BdoGatheringToolIcon),
          );
          expect(tool, findsOneWidget);
          _expectOriginalTool(tester, tool, entry.$2);
          final product = source.products.firstWhere(
            (product) => product.resourceId == resource.id,
          );
          expect(
            tester.widget<BdoGatheringToolIcon>(tool).method,
            product.method,
          );
          if (entry.$2 == BdoGatheringToolKind.pickaxe) {
            expect(
              find.descendant(
                of: tool,
                matching: find.byTooltip('Defeat and mine · Pickaxe'),
              ),
              findsOneWidget,
              reason:
                  'A compact tool icon must retain the combat prerequisite.',
            );
          }
        }
        final checklist = find.byKey(
          ValueKey('resource-map-detail-checklist-${resource.id}'),
        );
        expect(find.byTooltip('Add to to-do list'), findsOneWidget);
        await tester.tap(checklist);
        await tester.pumpAndSettle();
        expect(find.byTooltip('Remove from to-do list'), findsOneWidget);
        await tester.tap(checklist);
        await tester.pumpAndSettle();
        expect(find.byTooltip('Add to to-do list'), findsOneWidget);
        final favorite = find.byKey(
          ValueKey('resource-map-detail-favorite-${resource.id}'),
        );
        await tester.tap(favorite);
        await tester.pumpAndSettle();
        expect(favoriteChanges.last, <String>{resource.id});
        await tester.tap(favorite);
        await tester.pumpAndSettle();
        expect(favoriteChanges.last, isEmpty);
        _expectNoOverflow(tester);
      },
    );
  }
}

Finder get _browser =>
    find.byKey(const ValueKey('resource-map-resource-browser'));
Finder get _inspector => find.ancestor(
  of: find.byKey(const ValueKey('resource-map-sidebar-details')),
  matching: find.byType(ResourceMapJourneySurface),
);
Finder _sourceRow(String id) =>
    find.byKey(ValueKey('resource-map-browser-source-$id'));

Finder _workerBadge(Finder row, String resourceId) => find.descendant(
  of: row,
  matching: find.byKey(ValueKey('resource-map-plan-workers-$resourceId')),
);

Future<void> _settleWorkerPreview(WidgetTester tester) async {
  final progress = find.byKey(
    const ValueKey('resource-map-node-target-preview-loading'),
  );
  await tester.pump(const Duration(milliseconds: 200));
  for (var attempt = 0; attempt < 200; attempt++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump();
    if (progress.evaluate().isEmpty) {
      await tester.pumpAndSettle();
      return;
    }
  }
  fail('The planned-material preview did not finish in time.');
}

void _expectWorkerTarget(WidgetTester tester, BdoResourceDefinition resource) {
  expect(
    find.byKey(const ValueKey('resource-map-node-planner-targets')),
    findsOneWidget,
  );
  expect(
    find.byKey(ValueKey('resource-map-node-target-${resource.id}')),
    findsOneWidget,
  );
  expect(
    find.byKey(ValueKey('resource-map-node-target-remove-${resource.id}')),
    findsOneWidget,
  );
  expect(
    tester
        .widget<TextField>(
          find.byKey(const ValueKey('resource-map-node-target-search')),
        )
        .controller!
        .text,
    resource.name,
  );
  expect(_browser, findsNothing);
  expect(_inspector, findsNothing);
  final canvas = tester.widget<BdoMapCanvas>(find.byType(BdoMapCanvas));
  expect(canvas.gatheringPoints, isEmpty);
  expect(canvas.gatheringSpots, isEmpty);
  expect(canvas.workerNodes, isNotEmpty);
}

List<String> _rowText(WidgetTester tester, Finder row) => tester
    .widgetList<Text>(find.descendant(of: row, matching: find.byType(Text)))
    .map((text) => text.data ?? text.textSpan!.toPlainText())
    .where((text) => text.isNotEmpty)
    .toList();

Future<void> _scrollBrowserTo(WidgetTester tester, Finder row) async {
  final scrollable = find.descendant(
    of: _browser,
    matching: find.byType(Scrollable),
  );
  await tester.scrollUntilVisible(row, 130, scrollable: scrollable);
  await tester.pumpAndSettle();
}

void _expectReadableOriginalRow(WidgetTester tester, Finder row, String name) {
  final label = find.descendant(of: row, matching: find.text(name));
  expect(label, findsOneWidget);
  final text = tester.widget<Text>(label);
  expect(text.style?.fontSize, 16);
  expect(text.style?.fontWeight, FontWeight.w700);
  expect(text.maxLines, isNull);
  expect(text.overflow, isNot(TextOverflow.ellipsis));
  final paragraph = tester.renderObject<RenderParagraph>(label);
  expect(paragraph.didExceedMaxLines, isFalse);
  final rowBounds = tester.getRect(row);
  final labelBounds = tester.getRect(label);
  expect(labelBounds.left, greaterThanOrEqualTo(rowBounds.left));
  expect(labelBounds.right, lessThanOrEqualTo(rowBounds.right));
  expect(labelBounds.bottom, lessThanOrEqualTo(rowBounds.bottom));
  final artwork = find.descendant(
    of: row,
    matching: find.byWidgetPredicate(
      (widget) =>
          widget is Image &&
          widget.key is ValueKey<String> &&
          (widget.key! as ValueKey<String>).value.startsWith(
            'original-item-art-',
          ),
    ),
  );
  expect(artwork, findsOneWidget);
  expect(tester.widget<Image>(artwork).image, isA<MemoryImage>());
  expect(tester.getSize(artwork), const Size.square(36));
  expect(tester.getSize(row).height, greaterThanOrEqualTo(50));
}

void _expectOriginalTool(
  WidgetTester tester,
  Finder tool,
  BdoGatheringToolKind kind,
) {
  final artwork = find.descendant(
    of: tool,
    matching: find.byKey(ValueKey('bdo-gathering-tool-artwork-${kind.name}')),
  );
  expect(artwork, findsOneWidget);
  if (bdoGatheringToolAssetSourceRect(kind) != null) {
    expect(
      find.descendant(
        of: artwork,
        matching: find.byKey(
          ValueKey('bdo-gathering-tool-sprite-${kind.name}'),
        ),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: artwork,
        matching: find.byKey(
          ValueKey('bdo-gathering-tool-fallback-${kind.name}'),
        ),
      ),
      findsNothing,
    );
  } else {
    final provider = tester.widget<Image>(artwork).image as AssetImage;
    expect(provider.assetName, bdoGatheringToolAssetPath(kind));
    expect(provider.package, bdoGatheringToolAssetPackage);
  }
  expect(tester.getSize(artwork), const Size.square(27));
}

void _expectBounded(WidgetTester tester, Finder panel, Size viewport) {
  final bounds = tester.getRect(panel);
  expect(bounds.left, greaterThanOrEqualTo(0));
  expect(bounds.top, greaterThanOrEqualTo(0));
  expect(bounds.right, lessThanOrEqualTo(viewport.width));
  expect(bounds.bottom, lessThanOrEqualTo(viewport.height));
}

void _expectNoOverflow(WidgetTester tester) {
  expect(tester.takeException(), isNull);
  expect(find.byType(Scrollbar), findsNothing);
  expect(find.byType(RawScrollbar), findsNothing);
}
