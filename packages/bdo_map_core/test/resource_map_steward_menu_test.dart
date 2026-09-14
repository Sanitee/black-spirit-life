import 'package:bdo_map_core/src/widgets/resource_map_chrome_theme.dart';
import 'package:bdo_map_core/src/widgets/resource_map_panel_metrics.dart';
import 'package:bdo_map_core/src/widgets/resource_map_steward_menu.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/map_menu_capture.dart';

void main() {
  testWidgets('Steward uses compact rows without passive subtitles or badges', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    var opened = 0;
    await tester.pumpWidget(
      _testApp(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ResourceMapStewardWorkerMenu(
              selectedSection: ResourceMapWorkerMenuSection.plan,
              onSectionChanged: (_) {},
              planActions: [
                ResourceMapStewardMenuAction(
                  key: const ValueKey('compact-action'),
                  icon: ResourceMapStewardIconKind.needed,
                  label: 'To-do',
                  semanticHint: 'Open saved materials',
                  badge: '7 materials',
                  onPressed: () => opened++,
                ),
              ],
              exploreActions: const [],
              manageActions: const [],
            ),
            ResourceMapStewardListRow(
              key: const ValueKey('compact-list'),
              icon: ResourceMapStewardIconKind.houses,
              title: 'Velia',
              subtitle: '4 houses',
              badge: '2 lodging',
              semanticLabel: 'Velia houses',
              onPressed: () => opened++,
            ),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      tester.getSize(find.byKey(const ValueKey('compact-action'))).height,
      ResourceMapPanelMetrics.rowHeight,
    );
    expect(
      tester.getSize(find.byKey(const ValueKey('compact-list'))).height,
      ResourceMapPanelMetrics.rowHeight + 6,
    );
    expect(find.text('7 materials'), findsNothing);
    expect(find.text('4 houses'), findsNothing);
    expect(find.text('2 lodging'), findsNothing);
    expect(
      tester
          .getSemantics(find.byKey(const ValueKey('compact-list')))
          .getSemanticsData()
          .hint,
      '4 houses. 2 lodging',
    );
    semantics.dispose();
    for (final icon in tester.widgetList<ResourceMapStewardIcon>(
      find.byType(ResourceMapStewardIcon),
    )) {
      expect(icon.size, ResourceMapPanelMetrics.navigationArtwork);
    }
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(opened, 1);
    // Pointer activation still reaches both the compact menu and list action.
    await tester.tap(find.byKey(const ValueKey('compact-action')));
    await tester.tap(find.byKey(const ValueKey('compact-list')));
    expect(opened, 3);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'Guild Steward menu glides between categories and staggered actions',
    (tester) async {
      ResourceMapWorkerMenuSection? selected;
      var specificPresses = 0;
      late StateSetter refresh;

      await tester.pumpWidget(
        _testApp(
          disableAnimations: false,
          child: StatefulBuilder(
            builder: (context, setState) {
              refresh = setState;
              return ResourceMapStewardWorkerMenu(
                selectedSection: selected,
                onSectionChanged: (value) {
                  refresh(() => selected = value);
                },
                planActions: <ResourceMapStewardMenuAction>[
                  ResourceMapStewardMenuAction(
                    key: const ValueKey<String>('needed-action'),
                    icon: ResourceMapStewardIconKind.needed,
                    label: 'Needed for your plan',
                    semanticHint: 'Plan the materials still needed.',
                    onPressed: () {},
                  ),
                  ResourceMapStewardMenuAction(
                    key: const ValueKey<String>('specific-action'),
                    icon: ResourceMapStewardIconKind.specificItems,
                    label: 'Specific items',
                    semanticHint: 'Choose exact materials.',
                    onPressed: () => specificPresses += 1,
                  ),
                ],
                exploreActions: const <ResourceMapStewardMenuAction>[],
                manageActions: const <ResourceMapStewardMenuAction>[],
              );
            },
          ),
        ),
      );

      final plan = find.byKey(
        const ValueKey<String>('resource-map-worker-menu-plan'),
      );
      final explore = find.byKey(
        const ValueKey<String>('resource-map-worker-menu-explore'),
      );
      final manage = find.byKey(
        const ValueKey<String>('resource-map-worker-menu-manage'),
      );
      expect(plan, findsOneWidget);
      expect(explore, findsOneWidget);
      expect(manage, findsOneWidget);
      expect(find.byKey(const ValueKey<String>('needed-action')), findsNothing);
      final closedExploreLeft = tester.getTopLeft(explore).dx;

      await tester.tap(plan);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 70));
      expect(tester.binding.hasScheduledFrame, isTrue);
      expect(tester.getTopLeft(explore).dx, lessThan(closedExploreLeft));
      expect(
        find.byKey(const ValueKey<String>('needed-action')),
        findsOneWidget,
      );

      await tester.pumpAndSettle();
      expect(tester.binding.hasScheduledFrame, isFalse);
      expect(plan.hitTestable(), findsOneWidget);
      expect(explore.hitTestable(), findsNothing);
      expect(manage.hitTestable(), findsNothing);
      expect(
        find.byKey(const ValueKey<String>('needed-action')).hitTestable(),
        findsOneWidget,
      );
      expect(
        tester
            .getTopLeft(find.byKey(const ValueKey<String>('needed-action')))
            .dx,
        greaterThan(tester.getTopLeft(plan).dx),
      );

      await tester.tap(find.byKey(const ValueKey<String>('specific-action')));
      expect(specificPresses, 1);

      await tester.tap(plan);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey<String>('needed-action')), findsNothing);
      expect(explore.hitTestable(), findsOneWidget);
      expect(manage.hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Guild Steward menu remains readable at 200 percent text', (
    tester,
  ) async {
    await tester.pumpWidget(
      _testApp(
        textScaler: const TextScaler.linear(2),
        child: ResourceMapStewardWorkerMenu(
          selectedSection: ResourceMapWorkerMenuSection.plan,
          onSectionChanged: (_) {},
          planActions: <ResourceMapStewardMenuAction>[
            ResourceMapStewardMenuAction(
              key: const ValueKey<String>('large-needed-action'),
              icon: ResourceMapStewardIconKind.needed,
              label: 'Needed for your plan',
              semanticHint: 'Plan the materials still needed.',
              onPressed: () {},
            ),
            ResourceMapStewardMenuAction(
              key: const ValueKey<String>('large-specific-action'),
              icon: ResourceMapStewardIconKind.specificItems,
              label: 'Specific items',
              semanticHint: 'Choose exact materials.',
              onPressed: () {},
            ),
            ResourceMapStewardMenuAction(
              key: const ValueKey<String>('large-income-action'),
              icon: ResourceMapStewardIconKind.bestIncome,
              label: 'Best income',
              semanticHint: 'Find the strongest income route.',
              onPressed: () {},
            ),
          ],
          exploreActions: const <ResourceMapStewardMenuAction>[],
          manageActions: const <ResourceMapStewardMenuAction>[],
        ),
      ),
    );
    await tester.pumpAndSettle();

    for (final key in <String>[
      'resource-map-worker-menu-plan',
      'large-needed-action',
      'large-specific-action',
      'large-income-action',
    ]) {
      final control = find.byKey(ValueKey<String>(key));
      expect(control, findsOneWidget);
      expect(tester.getSize(control).height, greaterThanOrEqualTo(44));
    }
    for (final label in <String>[
      'Plan',
      'Needed for your plan',
      'Specific items',
      'Best income',
    ]) {
      final paragraph = tester.renderObject<RenderParagraph>(find.text(label));
      final text = tester.widget<Text>(find.text(label));
      expect(
        paragraph.didExceedMaxLines,
        isFalse,
        reason:
            '$label should remain complete at 200% text '
            '(size ${paragraph.size}, maxLines ${text.maxLines}).',
      );
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'Gather Steward Plan and Browse labels stay complete at 200 percent text',
    (tester) async {
      ResourceMapWorkerMenuSection? selected;
      late StateSetter refresh;

      final planActions = <ResourceMapStewardMenuAction>[
        ResourceMapStewardMenuAction(
          key: const ValueKey<String>('gather-needed-action'),
          icon: ResourceMapStewardIconKind.needed,
          label: 'Needed for your plan',
          semanticHint: 'Show materials that can be gathered by hand.',
          onPressed: () {},
        ),
        ResourceMapStewardMenuAction(
          key: const ValueKey<String>('gather-checklist-action'),
          icon: ResourceMapStewardIconKind.checklist,
          label: 'Checklist',
          semanticHint: 'Open the gathering checklist.',
          onPressed: () {},
        ),
        ResourceMapStewardMenuAction(
          key: const ValueKey<String>('gather-favorites-action'),
          icon: ResourceMapStewardIconKind.favorites,
          label: 'Favorites',
          semanticHint: 'Open favorite gathering materials.',
          onPressed: () {},
        ),
      ];
      final browseActions = <ResourceMapStewardMenuAction>[
        ResourceMapStewardMenuAction(
          key: const ValueKey<String>('gather-plants-action'),
          icon: ResourceMapStewardIconKind.plantsWood,
          label: 'Plants & wood',
          semanticHint: 'Browse plants and wood.',
          onPressed: () {},
        ),
        ResourceMapStewardMenuAction(
          key: const ValueKey<String>('gather-ores-action'),
          icon: ResourceMapStewardIconKind.oresMinerals,
          label: 'Ores & minerals',
          semanticHint: 'Browse ores and minerals.',
          onPressed: () {},
        ),
        ResourceMapStewardMenuAction(
          key: const ValueKey<String>('gather-blood-action'),
          icon: ResourceMapStewardIconKind.bloodHides,
          label: 'Blood & hides',
          semanticHint: 'Browse blood and hides.',
          onPressed: () {},
        ),
        ResourceMapStewardMenuAction(
          key: const ValueKey<String>('gather-coastal-action'),
          icon: ResourceMapStewardIconKind.coastal,
          label: 'Coastal gathering',
          semanticHint: 'Browse coastal gathering.',
          onPressed: () {},
        ),
      ];

      await tester.pumpWidget(
        _testApp(
          textScaler: const TextScaler.linear(2),
          child: StatefulBuilder(
            builder: (context, setState) {
              refresh = setState;
              return ResourceMapStewardWorkerMenu(
                selectedSection: selected,
                onSectionChanged: (value) {
                  refresh(() => selected = value);
                },
                semanticLabel: 'Gather map tools',
                menuContentKey: const ValueKey<String>(
                  'resource-map-gather-steward-menu',
                ),
                controlKeyPrefix: 'resource-map-gather-menu',
                exploreLabel: 'Browse',
                exploreIcon: ResourceMapStewardIconKind.browse,
                visibleSections: const <ResourceMapWorkerMenuSection>[
                  ResourceMapWorkerMenuSection.plan,
                  ResourceMapWorkerMenuSection.explore,
                ],
                planActions: planActions,
                exploreActions: browseActions,
                manageActions: const <ResourceMapStewardMenuAction>[],
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      final plan = find.byKey(
        const ValueKey<String>('resource-map-gather-menu-plan'),
      );
      final browse = find.byKey(
        const ValueKey<String>('resource-map-gather-menu-explore'),
      );
      expect(plan, findsOneWidget);
      expect(browse, findsOneWidget);
      expect(
        find.byKey(const ValueKey<String>('resource-map-gather-menu-manage')),
        findsNothing,
      );

      Future<void> expectCompleteLabels(List<String> labels) async {
        for (final label in labels) {
          final textFinder = find.text(label);
          expect(textFinder, findsOneWidget);
          expect(
            tester.renderObject<RenderParagraph>(textFinder).didExceedMaxLines,
            isFalse,
            reason: '$label must never be shortened with an ellipsis.',
          );
        }
      }

      await expectCompleteLabels(const <String>['Plan', 'Browse']);
      await tester.tap(plan);
      await tester.pumpAndSettle();
      await expectCompleteLabels(
        planActions.map((action) => action.label).toList(growable: false),
      );
      expect(browse.hitTestable(), findsNothing);

      await tester.tap(plan);
      await tester.pumpAndSettle();
      await tester.tap(browse);
      await tester.pumpAndSettle();
      await expectCompleteLabels(
        browseActions.map((action) => action.label).toList(growable: false),
      );
      expect(plan.hitTestable(), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('every Guild Steward desk object paints in both map themes', (
    tester,
  ) async {
    for (final chrome in <ResourceMapChromeThemeData>[
      ResourceMapChromeThemeData.sakuraCartographer,
      ResourceMapChromeThemeData.illuminatedAtlas,
    ]) {
      await tester.pumpWidget(
        _testApp(
          child: ResourceMapChromeTheme(
            data: chrome,
            child: Wrap(
              children: <Widget>[
                for (final kind in ResourceMapStewardIconKind.values)
                  ResourceMapStewardIcon(
                    key: ValueKey<String>('${chrome.hashCode}-${kind.name}'),
                    kind: kind,
                    size: 44,
                  ),
              ],
            ),
          ),
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('Guild Steward Plan menu keeps the approved compact hierarchy', (
    tester,
  ) async {
    await tester.pumpWidget(
      _testApp(
        child: RepaintBoundary(
          key: const ValueKey<String>('steward-plan-golden'),
          child: ColoredBox(
            color: const Color(0xFF100E12),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: ResourceMapStewardWorkerMenu(
                selectedSection: ResourceMapWorkerMenuSection.plan,
                onSectionChanged: (_) {},
                planActions: <ResourceMapStewardMenuAction>[
                  ResourceMapStewardMenuAction(
                    key: const ValueKey<String>('golden-needed'),
                    icon: ResourceMapStewardIconKind.needed,
                    label: 'Needed for your plan',
                    semanticHint: 'Plan the materials still needed.',
                    onPressed: () {},
                  ),
                  ResourceMapStewardMenuAction(
                    key: const ValueKey<String>('golden-specific'),
                    icon: ResourceMapStewardIconKind.specificItems,
                    label: 'Specific items',
                    semanticHint: 'Choose exact materials.',
                    onPressed: () {},
                  ),
                  ResourceMapStewardMenuAction(
                    key: const ValueKey<String>('golden-income'),
                    icon: ResourceMapStewardIconKind.bestIncome,
                    label: 'Best income',
                    semanticHint: 'Find the strongest income route.',
                    onPressed: () {},
                  ),
                ],
                exploreActions: const <ResourceMapStewardMenuAction>[],
                manageActions: const <ResourceMapStewardMenuAction>[],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await expectLater(
      find.byKey(const ValueKey<String>('steward-plan-golden')),
      matchesGoldenFile('goldens/resource_map_steward_plan_menu.png'),
    );
  });

  testWidgets('Gather Browse menu keeps one coherent desk-object icon pack', (
    tester,
  ) async {
    await tester.pumpWidget(
      _testApp(
        child: RepaintBoundary(
          key: const ValueKey<String>('steward-gather-golden'),
          child: ColoredBox(
            color: const Color(0xFF100E12),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: ResourceMapStewardWorkerMenu(
                selectedSection: ResourceMapWorkerMenuSection.explore,
                onSectionChanged: (_) {},
                semanticLabel: 'Gather map tools',
                exploreLabel: 'Browse',
                exploreIcon: ResourceMapStewardIconKind.browse,
                visibleSections: const <ResourceMapWorkerMenuSection>[
                  ResourceMapWorkerMenuSection.plan,
                  ResourceMapWorkerMenuSection.explore,
                ],
                planActions: const <ResourceMapStewardMenuAction>[],
                exploreActions: <ResourceMapStewardMenuAction>[
                  for (final entry
                      in const <(String, ResourceMapStewardIconKind)>[
                        (
                          'Plants & wood',
                          ResourceMapStewardIconKind.plantsWood,
                        ),
                        (
                          'Ores & minerals',
                          ResourceMapStewardIconKind.oresMinerals,
                        ),
                        ('Meat', ResourceMapStewardIconKind.meat),
                        (
                          'Blood & hides',
                          ResourceMapStewardIconKind.bloodHides,
                        ),
                        ('Mushrooms', ResourceMapStewardIconKind.mushrooms),
                        (
                          'Coastal gathering',
                          ResourceMapStewardIconKind.coastal,
                        ),
                        ('Other', ResourceMapStewardIconKind.other),
                      ])
                    ResourceMapStewardMenuAction(
                      key: ValueKey<String>('golden-${entry.$2.name}'),
                      icon: entry.$2,
                      label: entry.$1,
                      semanticHint: 'Open ${entry.$1}.',
                      onPressed: () {},
                    ),
                ],
                manageActions: const <ResourceMapStewardMenuAction>[],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await expectLater(
      find.byKey(const ValueKey<String>('steward-gather-golden')),
      matchesGoldenFile('goldens/resource_map_steward_gather_menu.png'),
    );
  });

  testWidgets('compact Steward real-font review', (tester) async {
    await tester.runAsync(loadMapMenuCaptureFonts);
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark().copyWith(
          textTheme: ThemeData.dark().textTheme.apply(fontFamily: 'Segoe UI'),
        ),
        home: ResourceMapChromeTheme(
          data: ResourceMapChromeThemeData.glassDock,
          child: RepaintBoundary(
            key: const ValueKey('steward-review'),
            child: Material(
              color: const Color(0xff08161d),
              child: Align(
                alignment: Alignment.topLeft,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: SizedBox(
                    width: 300,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        ResourceMapStewardWorkerMenu(
                          selectedSection: ResourceMapWorkerMenuSection.plan,
                          onSectionChanged: (_) {},
                          planActions: [
                            for (final label in [
                              'To-do',
                              'Specific items',
                              'Best income',
                            ])
                              ResourceMapStewardMenuAction(
                                key: ValueKey(label),
                                icon: ResourceMapStewardIconKind.plan,
                                label: label,
                                semanticHint: 'Open $label',
                                badge: '4',
                                onPressed: () {},
                              ),
                          ],
                          exploreActions: const [],
                          manageActions: const [],
                        ),
                        const SizedBox(height: 12),
                        ResourceMapStewardListRow(
                          icon: ResourceMapStewardIconKind.houses,
                          title: 'Velia',
                          subtitle: '4 houses',
                          badge: '2 lodging',
                          semanticLabel: 'Velia houses',
                          onPressed: () {},
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await captureMapMenu(
      tester,
      boundary: find.byKey(const ValueKey('steward-review')),
      name: 'steward-compact-1.0',
    );
    expect(tester.takeException(), isNull);
  });
}

Widget _testApp({
  required Widget child,
  TextScaler textScaler = TextScaler.noScaling,
  bool disableAnimations = true,
}) {
  return MaterialApp(
    home: MediaQuery(
      data: MediaQueryData(
        textScaler: textScaler,
        disableAnimations: disableAnimations,
      ),
      child: Material(
        color: const Color(0xFF100E12),
        child: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(width: 420, height: 520, child: child),
        ),
      ),
    ),
  );
}
