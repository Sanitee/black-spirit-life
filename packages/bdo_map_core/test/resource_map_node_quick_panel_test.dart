import 'package:bdo_map_core/src/widgets/resource_map_node_quick_panel.dart';
import 'package:bdo_map_core/src/widgets/resource_map_chrome_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('shows a compact node summary and preserves every action', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(800, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final semantics = tester.ensureSemantics();
    var investmentToggles = 0;
    var routePreviews = 0;
    var routeAdds = 0;
    var outputOpens = 0;
    var workerNodeOpens = 0;
    var parentOpens = 0;
    var pathToggles = 0;
    var backs = 0;
    var closes = 0;

    await tester.pumpWidget(
      _testApp(
        child: ResourceMapNodeQuickPanel(
          nodeName: 'Costa Farm',
          nodeType: 'Production node',
          contributionPoints: 2,
          region: 'Serendia',
          workTime: const Duration(hours: 1, minutes: 18),
          workerSiteCount: 2,
          outputs: <ResourceMapNodeOutput>[
            ResourceMapNodeOutput(
              name: 'Pumpkin',
              icon: const DecoratedBox(
                key: ValueKey<String>('exact-pumpkin-item-art'),
                decoration: BoxDecoration(
                  border: Border.fromBorderSide(
                    BorderSide(color: Color(0xFFC79B58)),
                  ),
                ),
                child: Icon(Icons.spa_outlined),
              ),
              onPressed: () => outputOpens += 1,
            ),
            const ResourceMapNodeOutput(name: 'Wheat'),
          ],
          availableWorkerNodes: <ResourceMapNodeLink>[
            ResourceMapNodeLink(
              id: 'costa-farm-pumpkin',
              title: 'Costa Farm - Farming',
              subtitle: '1 CP · Pumpkin',
              icon: const Icon(Icons.agriculture_outlined),
              onPressed: () => workerNodeOpens += 1,
            ),
          ],
          connectedFrom: ResourceMapNodeLink(
            id: 'heidel',
            title: 'Heidel',
            subtitle: 'Serendia',
            icon: const Icon(Icons.account_balance_outlined),
            onPressed: () => parentOpens += 1,
          ),
          onToggleWorkerPath: () => pathToggles += 1,
          provenance: 'Coordinates and node data: verified test fixture',
          invested: false,
          onToggleInvested: () => investmentToggles += 1,
          onPreviewRoute: () => routePreviews += 1,
          onAddCompleteRoute: () => routeAdds += 1,
          completeRouteContributionPoints: 5,
          onBack: () => backs += 1,
          backLabel: 'Worker nodes',
          onClose: () => closes += 1,
        ),
      ),
    );

    expect(find.text('Costa Farm'), findsOneWidget);
    expect(find.text('Production node · Serendia'), findsOneWidget);
    expect(find.text('2 CP'), findsOneWidget);
    expect(find.text('1h 18m'), findsOneWidget);
    expect(find.text('2 worker sites'), findsOneWidget);
    expect(find.text('Pumpkin'), findsOneWidget);
    expect(find.text('Wheat'), findsOneWidget);
    expect(find.text('AVAILABLE WORKER NODES · 1'), findsOneWidget);
    expect(find.text('Costa Farm - Farming'), findsOneWidget);
    expect(find.text('CONNECTED FROM'), findsOneWidget);
    expect(find.text('Heidel'), findsOneWidget);
    expect(find.text('Show worker path'), findsOneWidget);
    expect(
      find.text('Coordinates and node data: verified test fixture'),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('resource-map-node-more-details')),
      findsNothing,
    );
    expect(
      find.byKey(
        const ValueKey<String>('resource-map-node-output-missing-artwork'),
      ),
      findsOneWidget,
    );
    expect(find.byIcon(Icons.category_outlined), findsNothing);
    expect(
      tester
          .getSize(
            find.byKey(const ValueKey<String>('resource-map-node-quick-panel')),
          )
          .width,
      lessThanOrEqualTo(ResourceMapNodeQuickPanel.maxWidth),
    );
    expect(
      find.byKey(const ValueKey<String>('resource-map-node-quick-panel-tail')),
      findsOneWidget,
    );
    final surface = tester.widget<Material>(
      find.byKey(const ValueKey<String>('resource-map-node-quick-panel')),
    );
    expect(surface.color, Colors.transparent);
    expect(surface.elevation, 12);
    expect(surface.shadowColor, const Color(0x8F000000));
    final surfaceShape = surface.shape! as RoundedRectangleBorder;
    expect(surfaceShape.borderRadius, BorderRadius.circular(14));
    expect(surfaceShape.side, const BorderSide(color: Color(0xFF765C61)));
    final outline = tester.widget<DecoratedBox>(
      find.byKey(
        const ValueKey<String>('resource-map-node-quick-panel-accent'),
      ),
    );
    final outlineDecoration = outline.decoration as BoxDecoration;
    expect(outlineDecoration.gradient, isA<LinearGradient>());
    expect(outlineDecoration.border, isNull);
    expect(outlineDecoration.borderRadius, isNull);
    expect(
      find.byKey(
        const ValueKey<String>('resource-map-node-quick-panel-accent'),
      ),
      findsOneWidget,
    );
    final exactArtworkHost = find.byKey(
      const ValueKey<String>('resource-map-node-output-artwork-Pumpkin'),
    );
    expect(exactArtworkHost, findsOneWidget);
    expect(tester.getSize(exactArtworkHost), const Size.square(28));
    expect(
      find.descendant(
        of: exactArtworkHost,
        matching: find.byType(DecoratedBox),
      ),
      findsOneWidget,
      reason: 'Exact item art must keep only its own authored frame.',
    );

    expect(
      find.bySemanticsLabel('Costa Farm, Production node'),
      findsOneWidget,
    );
    expect(find.bySemanticsLabel('Produces Pumpkin'), findsOneWidget);
    expect(find.bySemanticsLabel('Back to Worker nodes'), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey<String>('resource-map-node-quick-back')),
    );
    expect(backs, 1);

    await tester.tap(
      find.byKey(const ValueKey<String>('resource-map-node-toggle-invested')),
    );
    await tester.tap(
      find.byKey(const ValueKey<String>('resource-map-node-preview-route')),
    );
    await tester.tap(
      find.byKey(const ValueKey<String>('resource-map-node-add-route')),
    );
    await tester.tap(
      find.byKey(const ValueKey<String>('resource-map-node-output-Pumpkin')),
    );
    await tester.tap(
      find.byKey(
        const ValueKey<String>(
          'resource-map-node-worker-site-costa-farm-pumpkin',
        ),
      ),
    );
    await tester.tap(
      find.byKey(const ValueKey<String>('resource-map-worker-path-toggle')),
    );
    await tester.tap(
      find.byKey(
        const ValueKey<String>('resource-map-node-connected-from-heidel'),
      ),
    );
    await tester.tap(
      find.byKey(const ValueKey<String>('resource-map-node-panel-close')),
    );

    expect(investmentToggles, 1);
    expect(routePreviews, 1);
    expect(routeAdds, 1);
    expect(outputOpens, 1);
    expect(workerNodeOpens, 1);
    expect(pathToggles, 1);
    expect(parentOpens, 1);
    expect(closes, 1);
    expect(tester.takeException(), isNull);
    semantics.dispose();
  });

  testWidgets(
    'invested state is clear and optional route actions stay absent',
    (tester) async {
      final semantics = tester.ensureSemantics();

      await tester.pumpWidget(
        _testApp(
          child: ResourceMapNodeQuickPanel(
            nodeName: 'Northern Wheat Plantation',
            nodeType: 'Farm',
            contributionPoints: 1,
            outputs: const <ResourceMapNodeOutput>[
              ResourceMapNodeOutput(name: 'Wheat'),
            ],
            invested: true,
            onToggleInvested: () {},
            onClose: () {},
            tailAlignment: ResourceMapNodeQuickPanelTailAlignment.end,
          ),
        ),
      );

      expect(find.text('Invested'), findsOneWidget);
      expect(find.text('Remove from my setup'), findsOneWidget);
      expect(
        find.byKey(const ValueKey<String>('resource-map-node-preview-route')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey<String>('resource-map-node-add-route')),
        findsNothing,
      );
      expect(
        tester
            .getSemantics(
              find.byKey(
                const ValueKey<String>('resource-map-node-toggle-invested'),
              ),
            )
            .label,
        contains('Remove Northern Wheat Plantation from my setup'),
      );
      expect(tester.takeException(), isNull);
      semantics.dispose();
    },
  );

  testWidgets('side pointer follows a viewport-clamped map anchor', (
    tester,
  ) async {
    await tester.pumpWidget(
      _testApp(
        child: ResourceMapNodeQuickPanel(
          nodeName: 'Edge node',
          nodeType: 'Gateway',
          contributionPoints: 1,
          outputs: const <ResourceMapNodeOutput>[],
          invested: false,
          onToggleInvested: () {},
          onClose: () {},
          tailAlignment: ResourceMapNodeQuickPanelTailAlignment.leftCenter,
          sideTailOffset: 36,
        ),
      ),
    );

    final tail = find.byKey(
      const ValueKey<String>('resource-map-node-quick-panel-tail'),
    );
    final positionedAncestors = tester
        .widgetList<Positioned>(
          find.ancestor(of: tail, matching: find.byType(Positioned)),
        )
        .where((positioned) => positioned.left == -8)
        .toList(growable: false);
    expect(positionedAncestors, hasLength(1));
    expect(positionedAncestors.single.top, 26);
    expect(positionedAncestors.single.bottom, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'shows excavation help and toggles only a verified manager marker',
    (tester) async {
      final semantics = tester.ensureSemantics();
      var markerVisible = false;
      var markerToggles = 0;

      await tester.pumpWidget(
        _testApp(
          height: 900,
          child: StatefulBuilder(
            builder: (context, setState) {
              return ResourceMapNodeQuickPanel(
                nodeName: 'Glish Ruins - Excavation',
                nodeType: 'Excavation',
                contributionPoints: 1,
                outputs: const <ResourceMapNodeOutput>[
                  ResourceMapNodeOutput(name: 'Trace of Nature'),
                ],
                invested: false,
                unlockNotice: ResourceMapNodeUnlockNotice(
                  managerName: 'Karu',
                  instructions:
                      'If this excavation is hidden, connect and invest in '
                      'its parent node first. Then speak to Karu and check '
                      'Chat. The Energy cost can vary by node.',
                  managerMarkerVisible: markerVisible,
                  onToggleManagerMarker: () {
                    setState(() => markerVisible = !markerVisible);
                    markerToggles += 1;
                  },
                ),
                onToggleInvested: () {},
                onClose: () {},
              );
            },
          ),
        ),
      );

      expect(find.text('EXCAVATION ACCESS'), findsOneWidget);
      expect(
        find.byKey(const ValueKey<String>('resource-map-node-unlock-notice')),
        findsOneWidget,
      );
      expect(find.text('Mark Karu on map'), findsOneWidget);
      expect(
        find.bySemanticsLabel(
          RegExp(r'^Excavation unlock help\. If this excavation is hidden'),
        ),
        findsOneWidget,
      );

      await tester.tap(
        find.byKey(
          const ValueKey<String>('resource-map-node-toggle-manager-marker'),
        ),
      );
      await tester.pump();

      expect(markerToggles, 1);
      expect(markerVisible, isTrue);
      expect(find.text('Hide Karu'), findsOneWidget);
      expect(tester.takeException(), isNull);
      semantics.dispose();
    },
  );

  testWidgets('does not offer a marker for an unverified NPC coordinate', (
    tester,
  ) async {
    await tester.pumpWidget(
      _testApp(
        height: 900,
        child: ResourceMapNodeQuickPanel(
          nodeName: 'Sherekhan Necropolis - Excavation',
          nodeType: 'Excavation',
          contributionPoints: 1,
          outputs: const <ResourceMapNodeOutput>[
            ResourceMapNodeOutput(name: 'Mythril'),
          ],
          invested: false,
          unlockNotice: const ResourceMapNodeUnlockNotice(
            managerName: 'Camira',
            instructions:
                'If this excavation is hidden, connect and invest in its '
                'parent node first. Then speak to Camira and check Chat. '
                'The Energy cost can vary by node.',
          ),
          onToggleInvested: () {},
          onClose: () {},
        ),
      ),
    );

    expect(find.textContaining('speak to Camira'), findsOneWidget);
    expect(
      find.byKey(
        const ValueKey<String>('resource-map-node-toggle-manager-marker'),
      ),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('town popup exposes Seoul actions without another menu', (
    tester,
  ) async {
    var workshopOpens = 0;
    var workerStorageOpens = 0;
    var houseOpens = 0;

    await tester.pumpWidget(
      _testApp(
        height: 900,
        child: ResourceMapNodeQuickPanel(
          nodeName: 'Seoul',
          nodeType: 'City',
          contributionPoints: 0,
          outputs: const <ResourceMapNodeOutput>[],
          invested: true,
          townActions: ResourceMapTownQuickActions(
            onOpenRoyalWorkshops: () => workshopOpens += 1,
            onOpenWorkersAndStorage: () => workerStorageOpens += 1,
            onOpenHouses: () => houseOpens += 1,
          ),
          onToggleInvested: () {},
          onClose: () {},
        ),
      ),
    );

    expect(find.text('Open Royal Workshops'), findsOneWidget);
    expect(find.text('Yukjo workers & storage'), findsOneWidget);
    expect(find.text('Houses'), findsOneWidget);

    await tester.tap(
      find.byKey(
        const ValueKey<String>('resource-map-town-open-royal-workshops'),
      ),
    );
    await tester.tap(
      find.byKey(
        const ValueKey<String>('resource-map-town-open-workers-storage'),
      ),
    );
    await tester.tap(
      find.byKey(const ValueKey<String>('resource-map-town-open-houses')),
    );

    expect(workshopOpens, 1);
    expect(workerStorageOpens, 1);
    expect(houseOpens, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('town popup keeps every action label complete at 200 percent', (
    tester,
  ) async {
    await tester.pumpWidget(
      _testApp(
        width: 304,
        height: 480,
        textScaler: const TextScaler.linear(2),
        child: ResourceMapNodeQuickPanel(
          nodeName: 'Seoul',
          nodeType: 'City',
          contributionPoints: 0,
          outputs: const <ResourceMapNodeOutput>[],
          invested: true,
          townActions: ResourceMapTownQuickActions(
            onOpenRoyalWorkshops: () {},
            onOpenWorkersAndStorage: () {},
            onOpenHouses: () {},
          ),
          onToggleInvested: () {},
          onClose: () {},
        ),
      ),
    );

    for (final label in <String>[
      'Seoul',
      'Open Royal Workshops',
      'Yukjo workers & storage',
      'Houses',
    ]) {
      final paragraph = tester.renderObject<RenderParagraph>(find.text(label));
      expect(
        paragraph.didExceedMaxLines,
        isFalse,
        reason: '$label should wrap instead of being clipped.',
      );
    }
    expect(
      tester
          .getSize(
            find.byKey(const ValueKey<String>('resource-map-node-quick-panel')),
          )
          .height,
      lessThanOrEqualTo(480),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('manager marker is a compact, semantic map dot', (tester) async {
    final semantics = tester.ensureSemantics();

    await tester.pumpWidget(
      _testApp(
        child: const ResourceMapManagerMarker(
          managerName: 'Karu',
          contextLabel: 'excavation node manager location',
        ),
      ),
    );

    expect(
      tester.getSize(
        find.byKey(const ValueKey<String>('resource-map-manager-marker')),
      ),
      const Size.square(ResourceMapManagerMarker.size),
    );
    expect(
      find.bySemanticsLabel('Karu, excavation node manager location'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
    semantics.dispose();
  });

  testWidgets('remains readable and overflow-safe at 200 percent text', (
    tester,
  ) async {
    await tester.pumpWidget(
      _testApp(
        width: 320,
        height: 480,
        textScaler: TextScaler.linear(2),
        child: ResourceMapNodeQuickPanel(
          nodeName: 'A Very Long Production Node Name Near Heidel',
          nodeType: 'Production node',
          contributionPoints: 3,
          region: 'A long regional description that needs to wrap',
          workTime: const Duration(hours: 3, minutes: 42),
          outputs: const <ResourceMapNodeOutput>[
            ResourceMapNodeOutput(name: 'A long worker output material name'),
            ResourceMapNodeOutput(name: 'Trace of the Earth'),
          ],
          invested: false,
          onToggleInvested: () {},
          onPreviewRoute: () {},
          onAddCompleteRoute: () {},
          completeRouteContributionPoints: 3,
          unlockNotice: const ResourceMapNodeUnlockNotice(
            managerName: 'Kamasylve Priestess Lunia',
            instructions:
                'If this excavation is hidden, connect and invest in its '
                'parent node first. Then speak to Kamasylve Priestess Lunia '
                'and check Chat. The Energy cost can vary by node.',
          ),
          onClose: () {},
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.textContaining('A Very Long Production'), findsOneWidget);
    expect(find.text('Add complete route  +3 CP'), findsOneWidget);
    expect(
      tester
          .getSize(
            find.byKey(const ValueKey<String>('resource-map-node-quick-panel')),
          )
          .width,
      lessThanOrEqualTo(ResourceMapNodeQuickPanel.maxWidth),
    );
    expect(
      tester
          .getSize(
            find.byKey(const ValueKey<String>('resource-map-node-quick-panel')),
          )
          .height,
      lessThanOrEqualTo(480),
    );
  });

  testWidgets('follows Illuminated Atlas chrome and repaints its map tail', (
    tester,
  ) async {
    Widget panel() => ResourceMapNodeQuickPanel(
      nodeName: 'Costa Farm',
      nodeType: 'Production node',
      contributionPoints: 2,
      outputs: const <ResourceMapNodeOutput>[
        ResourceMapNodeOutput(name: 'Pumpkin'),
      ],
      invested: false,
      onToggleInvested: () {},
      onClose: () {},
    );

    await tester.pumpWidget(
      _testApp(
        chrome: ResourceMapChromeThemeData.sakuraCartographer,
        child: panel(),
      ),
    );
    final tailFinder = find.byKey(
      const ValueKey<String>('resource-map-node-quick-panel-tail'),
    );
    final sakuraPainter = tester.widget<CustomPaint>(tailFinder).painter!;

    await tester.pumpWidget(
      _testApp(
        chrome: ResourceMapChromeThemeData.illuminatedAtlas,
        child: panel(),
      ),
    );

    final chrome = ResourceMapChromeThemeData.illuminatedAtlas;
    final surface = tester.widget<Material>(
      find.byKey(const ValueKey<String>('resource-map-node-quick-panel')),
    );
    final shape = surface.shape! as RoundedRectangleBorder;
    expect(surface.shadowColor, chrome.idleShadow.color);
    expect(shape.borderRadius, BorderRadius.circular(chrome.surfaceRadius));
    expect(shape.side.color, chrome.warmOutline);

    final decorated = tester.widget<DecoratedBox>(
      find.byKey(
        const ValueKey<String>('resource-map-node-quick-panel-accent'),
      ),
    );
    expect(
      (decorated.decoration as BoxDecoration).gradient,
      chrome.surfaceGradient,
    );

    final atlasPainter = tester.widget<CustomPaint>(tailFinder).painter!;
    expect(atlasPainter.shouldRepaint(sakuraPainter), isTrue);
    expect(tester.takeException(), isNull);
  });
}

Widget _testApp({
  required Widget child,
  double width = 360,
  double height = 760,
  TextScaler textScaler = TextScaler.noScaling,
  ResourceMapChromeThemeData chrome =
      ResourceMapChromeThemeData.sakuraCartographer,
}) {
  return MaterialApp(
    home: ResourceMapChromeTheme(
      data: chrome,
      child: MediaQuery(
        data: MediaQueryData(size: Size(width, height), textScaler: textScaler),
        child: Scaffold(
          backgroundColor: const Color(0xFF0A1210),
          body: Align(
            alignment: Alignment.topCenter,
            child: SizedBox(
              width: width,
              height: height,
              child: Align(alignment: Alignment.topCenter, child: child),
            ),
          ),
        ),
      ),
    ),
  );
}
