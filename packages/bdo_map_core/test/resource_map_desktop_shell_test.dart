import 'package:bdo_map_core/src/widgets/resource_map_desktop_shell.dart';
import 'package:bdo_map_core/src/widgets/resource_map_chrome_theme.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('field atlas exposes reusable semantic color roles', () {
    expect(ResourceMapAtlasColors.canvas, const Color(0xFF100E12));
    expect(ResourceMapAtlasColors.paper, const Color(0xFF171419));
    expect(ResourceMapAtlasColors.paperRaised, const Color(0xFF211B22));
    expect(ResourceMapAtlasColors.ink, const Color(0xFFF5EDDF));
    expect(ResourceMapAtlasColors.text, const Color(0xFFD8C9BE));
    expect(ResourceMapAtlasColors.muted, const Color(0xFFA18F86));
    expect(ResourceMapAtlasColors.warmOutline, const Color(0x667A625B));
    expect(ResourceMapAtlasColors.softOutline, const Color(0x995A4548));
    expect(ResourceMapAtlasColors.divider, ResourceMapAtlasColors.softOutline);
    expect(ResourceMapAtlasColors.primary, const Color(0xFFEAA083));
    expect(ResourceMapAtlasColors.tealDeep, const Color(0xFF44252F));
    expect(ResourceMapAtlasColors.onPrimary, ResourceMapAtlasColors.canvas);
    expect(ResourceMapAtlasColors.accent, const Color(0xFFE6C174));
    expect(ResourceMapAtlasColors.positive, const Color(0xFF7BD0A3));
    expect(ResourceMapAtlasColors.warning, const Color(0xFFE7A764));
    expect(ResourceMapAtlasColors.error, const Color(0xFFF07D84));
  });

  testWidgets(
    'map chrome defaults to Sakura and accepts package-owned scopes',
    (tester) async {
      late ResourceMapChromeThemeData fallback;
      late ResourceMapChromeThemeData scoped;

      await tester.pumpWidget(
        MaterialApp(
          home: Column(
            children: <Widget>[
              Builder(
                builder: (context) {
                  fallback = ResourceMapChromeTheme.of(context);
                  return const SizedBox.shrink();
                },
              ),
              ResourceMapChromeTheme(
                data: ResourceMapChromeThemeData.illuminatedAtlas,
                child: Builder(
                  builder: (context) {
                    scoped = ResourceMapChromeTheme.of(context);
                    return const SizedBox.shrink();
                  },
                ),
              ),
            ],
          ),
        ),
      );

      expect(fallback, same(ResourceMapChromeThemeData.sakuraCartographer));
      expect(scoped, same(ResourceMapChromeThemeData.illuminatedAtlas));
      expect(scoped.headingFontFamily, 'Georgia');
      expect(scoped.commandRadius, lessThan(fallback.commandRadius));
      expect(scoped.chromeBase, const Color(0xFF091321));
    },
  );

  testWidgets('Illuminated Atlas restyles command chrome and headings', (
    tester,
  ) async {
    final controller = TextEditingController();
    final focusNode = FocusNode();
    addTearDown(controller.dispose);
    addTearDown(focusNode.dispose);
    const chrome = ResourceMapChromeThemeData.illuminatedAtlas;

    await tester.pumpWidget(
      _shellTestApp(
        width: 700,
        height: 112,
        child: ResourceMapChromeTheme(
          data: chrome,
          child: Column(
            children: <Widget>[
              ResourceMapDesktopCommandBar(
                searchController: controller,
                searchFocusNode: focusNode,
                onSearchChanged: (_) {},
                onSearchSubmitted: (_) {},
                onSearchTapped: () {},
                onClearSearch: () {},
                onGatherPressed: () {},
                onWorkersPressed: () {},
                gatherSelected: true,
                workersSelected: false,
              ),
              const SizedBox(height: 8),
              const ResourceMapDesktopTaskStrip(
                leadingIcon: Icons.account_tree_outlined,
                title: 'Worker network',
                actions: <Widget>[],
              ),
            ],
          ),
        ),
      ),
    );

    final searchDecoration =
        tester
                .widget<AnimatedContainer>(
                  find.byKey(
                    const ValueKey<String>('resource-map-search-card'),
                  ),
                )
                .decoration!
            as BoxDecoration;
    expect(searchDecoration.gradient, chrome.idleSearchGradient);
    expect(
      searchDecoration.borderRadius,
      BorderRadius.circular(chrome.commandRadius),
    );

    final gatherDecoration =
        tester
                .widget<AnimatedContainer>(
                  find
                      .descendant(
                        of: find.byKey(
                          const ValueKey<String>('resource-map-command-gather'),
                        ),
                        matching: find.byType(AnimatedContainer),
                      )
                      .first,
                )
                .decoration!
            as BoxDecoration;
    expect(gatherDecoration.gradient, chrome.selectedModeGradient);
    expect(gatherDecoration.border!.top.color, chrome.primary);

    final taskTitle = tester.widget<Text>(find.text('Worker network'));
    expect(taskTitle.style!.fontFamily, 'Georgia');
    expect(taskTitle.style!.color, chrome.ink);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Illuminated Atlas offers selective vellum reading surfaces', (
    tester,
  ) async {
    const chrome = ResourceMapChromeThemeData.illuminatedAtlas;
    await tester.pumpWidget(
      _shellTestApp(
        width: 500,
        height: 100,
        child: ResourceMapChromeTheme(
          data: chrome,
          child: const Row(
            children: <Widget>[
              Expanded(
                child: ResourceMapSurfaceIsland(
                  key: ValueKey<String>('leather-surface'),
                  child: Text('Leather'),
                ),
              ),
              SizedBox(width: 8),
              Expanded(
                child: ResourceMapSurfaceIsland(
                  key: ValueKey<String>('vellum-surface'),
                  reading: true,
                  child: Text('Vellum'),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    BoxDecoration surfaceDecoration(String key) =>
        tester
                .widget<DecoratedBox>(
                  find
                      .descendant(
                        of: find.byKey(ValueKey<String>(key)),
                        matching: find.byType(DecoratedBox),
                      )
                      .first,
                )
                .decoration
            as BoxDecoration;

    expect(
      surfaceDecoration('leather-surface').gradient,
      chrome.surfaceGradient,
    );
    expect(
      surfaceDecoration('vellum-surface').gradient,
      chrome.readingSurfaceGradient,
    );
    expect(
      DefaultTextStyle.of(tester.element(find.text('Vellum'))).style.color,
      chrome.readingInk,
    );
  });

  testWidgets('command bar uses separate labeled field-atlas controls', (
    tester,
  ) async {
    final controller = TextEditingController();
    final focusNode = FocusNode();
    addTearDown(controller.dispose);
    addTearDown(focusNode.dispose);
    var gatherPresses = 0;
    var workerPresses = 0;

    await tester.pumpWidget(
      _shellTestApp(
        width: 700,
        height: 80,
        child: ResourceMapDesktopCommandBar(
          searchController: controller,
          searchFocusNode: focusNode,
          onSearchChanged: (_) {},
          onSearchSubmitted: (_) {},
          onSearchTapped: () {},
          onClearSearch: () {},
          onGatherPressed: () => gatherPresses += 1,
          onWorkersPressed: () => workerPresses += 1,
          gatherSelected: true,
          workersSelected: false,
        ),
      ),
    );

    expect(find.byType(Wrap), findsNothing);
    expect(find.byType(Chip), findsNothing);
    expect(find.byType(ChoiceChip), findsNothing);
    expect(find.text('Gather'), findsOneWidget);
    expect(find.text('Workers'), findsOneWidget);
    expect(
      tester
          .renderObject<RenderParagraph>(find.text('Workers'))
          .didExceedMaxLines,
      isFalse,
    );
    expect(find.text('Checklist'), findsNothing);
    expect(find.text('Favorites'), findsNothing);

    final commandDock = find.byKey(
      const ValueKey<String>('resource-map-command-dock'),
    );
    expect(
      tester.widget(commandDock),
      isA<SizedBox>(),
      reason:
          'The semantic command group must not paint one continuous slab '
          'behind search and both modes.',
    );

    final railFinder = find.byKey(
      const ValueKey<String>('resource-map-command-action-rail'),
    );
    final rail = tester.widget<Material>(railFinder);
    expect(rail.color, Colors.transparent);
    expect(rail.elevation, 0);
    expect(rail.shape, isNull);

    final gatherFinder = find.byKey(
      const ValueKey<String>('resource-map-command-gather'),
    );
    final workersFinder = find.byKey(
      const ValueKey<String>('resource-map-command-workers'),
    );
    expect(
      find.descendant(
        of: railFinder,
        matching: find.byKey(
          const ValueKey<String>('resource-map-command-checklist'),
        ),
      ),
      findsNothing,
    );
    expect(
      find.descendant(
        of: railFinder,
        matching: find.byKey(
          const ValueKey<String>('resource-map-command-favorites'),
        ),
      ),
      findsNothing,
    );
    final controlRects = <Rect>[
      tester.getRect(gatherFinder),
      tester.getRect(workersFinder),
    ];
    expect(controlRects.first.width, greaterThanOrEqualTo(112));
    expect(controlRects.last.width, greaterThanOrEqualTo(112));
    final controlTops = controlRects.map((rect) => rect.top);
    final controlBottoms = controlRects.map((rect) => rect.bottom);
    expect(
      controlTops.reduce((a, b) => a > b ? a : b) -
          controlTops.reduce((a, b) => a < b ? a : b),
      lessThanOrEqualTo(1),
    );
    expect(
      controlBottoms.reduce((a, b) => a > b ? a : b) -
          controlBottoms.reduce((a, b) => a < b ? a : b),
      lessThanOrEqualTo(1),
    );
    expect(tester.getSize(railFinder).height, 50);

    BoxDecoration controlDecoration(Finder control) {
      return tester
              .widget<AnimatedContainer>(
                find
                    .descendant(
                      of: control,
                      matching: find.byType(AnimatedContainer),
                    )
                    .first,
              )
              .decoration
          as BoxDecoration;
    }

    expect(controlDecoration(gatherFinder).color, isNull);
    expect(controlDecoration(gatherFinder).gradient, isA<LinearGradient>());
    expect(
      controlDecoration(gatherFinder).border!.top.color,
      ResourceMapAtlasColors.primary,
    );
    expect(
      controlDecoration(gatherFinder).border!.bottom.color,
      controlDecoration(gatherFinder).border!.top.color,
      reason: 'Selection is a complete outline, never a bottom underline.',
    );
    expect(
      find.descendant(of: gatherFinder, matching: find.byType(Positioned)),
      findsNothing,
    );
    expect(controlDecoration(workersFinder).color, isNull);
    expect(controlDecoration(workersFinder).gradient, isA<LinearGradient>());
    final gatherSemantics = tester.widget<Semantics>(
      find.descendant(
        of: gatherFinder,
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is Semantics && widget.properties.label == 'Gather',
        ),
      ),
    );
    expect(gatherSemantics.properties.label, 'Gather');
    expect(gatherSemantics.properties.selected, isTrue);
    final workerSemantics = tester.widget<Semantics>(
      find.descendant(
        of: workersFinder,
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is Semantics && widget.properties.label == 'Workers',
        ),
      ),
    );
    expect(workerSemantics.properties.label, 'Workers');
    expect(workerSemantics.properties.selected, isFalse);

    await tester.tap(gatherFinder);
    await tester.tap(workersFinder);
    expect(gatherPresses, 1);
    expect(workerPresses, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('search remains prominent and preserves every callback', (
    tester,
  ) async {
    final controller = TextEditingController();
    final focusNode = FocusNode();
    addTearDown(controller.dispose);
    addTearDown(focusNode.dispose);
    var taps = 0;
    var clears = 0;
    var changed = '';
    var submitted = '';

    await tester.pumpWidget(
      _shellTestApp(
        width: 700,
        height: 80,
        child: ResourceMapDesktopCommandBar(
          searchController: controller,
          searchFocusNode: focusNode,
          onSearchChanged: (value) => changed = value,
          onSearchSubmitted: (value) => submitted = value,
          onSearchTapped: () => taps += 1,
          onClearSearch: () {
            clears += 1;
            controller.clear();
          },
          onGatherPressed: () {},
          onWorkersPressed: () {},
          gatherSelected: false,
          workersSelected: true,
        ),
      ),
    );

    final fieldFinder = find.byType(TextField);
    final searchSurface = find.byKey(
      const ValueKey<String>('resource-map-search-card'),
    );
    expect(
      tester.widget<TextField>(fieldFinder).decoration!.hintText,
      'Find an item, source, node or town',
    );
    expect(tester.getSize(searchSurface).width, greaterThanOrEqualTo(280));
    final unfocusedDecoration =
        tester.widget<AnimatedContainer>(searchSurface).decoration!
            as BoxDecoration;
    expect(unfocusedDecoration.color, isNull);
    expect(unfocusedDecoration.gradient, isA<LinearGradient>());
    expect(
      unfocusedDecoration.border!.top.color,
      ResourceMapAtlasColors.warmOutline,
    );
    expect(unfocusedDecoration.boxShadow, isNotEmpty);

    await tester.tap(fieldFinder);
    await tester.pump();
    expect(focusNode.hasFocus, isTrue);
    expect(taps, 1);
    final focusedDecoration =
        tester.widget<AnimatedContainer>(searchSurface).decoration!
            as BoxDecoration;
    expect(focusedDecoration.border!.top.color, ResourceMapAtlasColors.primary);

    await tester.enterText(fieldFinder, 'Thuja Sap');
    expect(changed, 'Thuja Sap');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pump();
    expect(submitted, 'Thuja Sap');

    await tester.tap(find.byTooltip('Clear search'));
    await tester.pump();
    expect(clears, 1);
    expect(controller.text, isEmpty);
    expect(find.text('CTRL F'), findsOneWidget);
    final shortcutKeycap = find.byKey(
      const ValueKey<String>('resource-map-search-shortcut-keycap'),
    );
    final searchRect = tester.getRect(searchSurface);
    final shortcutRect = tester.getRect(shortcutKeycap);
    expect(
      searchRect.right - shortcutRect.right,
      greaterThanOrEqualTo(14),
      reason: 'The shortcut should breathe inside the search field edge.',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('narrow desktop rail keeps search visible and actions semantic', (
    tester,
  ) async {
    final controller = TextEditingController();
    final focusNode = FocusNode();
    addTearDown(controller.dispose);
    addTearDown(focusNode.dispose);

    await tester.pumpWidget(
      _shellTestApp(
        width: 560,
        height: 80,
        child: ResourceMapDesktopCommandBar(
          searchController: controller,
          searchFocusNode: focusNode,
          onSearchChanged: (_) {},
          onSearchSubmitted: (_) {},
          onSearchTapped: () {},
          onClearSearch: () {},
          onGatherPressed: () {},
          onWorkersPressed: () {},
          gatherSelected: true,
          workersSelected: false,
        ),
      ),
    );

    expect(
      tester
          .getSize(
            find.byKey(const ValueKey<String>('resource-map-search-card')),
          )
          .width,
      greaterThan(300),
    );
    expect(find.byTooltip('Gather'), findsOneWidget);
    expect(find.byTooltip('Workers'), findsOneWidget);
    expect(find.text('Gather'), findsNothing);
    expect(find.text('Workers'), findsNothing);
    expect(find.text('Checklist'), findsNothing);
    expect(find.text('Favorites'), findsNothing);
    final gatherSemantics = tester.widget<Semantics>(
      find.descendant(
        of: find.byKey(const ValueKey<String>('resource-map-command-gather')),
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is Semantics && widget.properties.label == 'Gather',
        ),
      ),
    );
    expect(gatherSemantics.properties.label, 'Gather');
    expect(gatherSemantics.properties.selected, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('large text keeps the atlas command bar usable', (tester) async {
    final controller = TextEditingController();
    final focusNode = FocusNode();
    addTearDown(controller.dispose);
    addTearDown(focusNode.dispose);

    await tester.pumpWidget(
      _shellTestApp(
        width: 700,
        height: 96,
        textScaler: const TextScaler.linear(2),
        child: ResourceMapDesktopCommandBar(
          searchController: controller,
          searchFocusNode: focusNode,
          onSearchChanged: (_) {},
          onSearchSubmitted: (_) {},
          onSearchTapped: () {},
          onClearSearch: () {},
          onGatherPressed: () {},
          onWorkersPressed: () {},
          gatherSelected: false,
          workersSelected: true,
        ),
      ),
    );

    expect(find.text('Gather'), findsNothing);
    expect(find.text('Workers'), findsNothing);
    expect(find.text('Checklist'), findsNothing);
    expect(find.text('Favorites'), findsNothing);
    expect(find.byTooltip('Gather'), findsOneWidget);
    expect(find.byTooltip('Workers'), findsOneWidget);
    expect(
      tester
          .getSize(
            find.byKey(const ValueKey<String>('resource-map-search-card')),
          )
          .width,
      greaterThan(450),
    );
    final searchRect = tester.getRect(
      find.byKey(const ValueKey<String>('resource-map-search-card')),
    );
    final shortcutRect = tester.getRect(
      find.byKey(const ValueKey<String>('resource-map-search-shortcut-keycap')),
    );
    expect(searchRect.contains(shortcutRect.topLeft), isTrue);
    expect(searchRect.contains(shortcutRect.bottomRight), isTrue);
    expect(searchRect.right - shortcutRect.right, greaterThanOrEqualTo(14));
    expect(tester.takeException(), isNull);
  });

  testWidgets('mode actions are individual semantic pills without a panel', (
    tester,
  ) async {
    var gatherPresses = 0;
    await tester.pumpWidget(
      _shellTestApp(
        width: 330,
        height: 70,
        child: ResourceMapDesktopModeActionStrip(
          actions: <ResourceMapDesktopModeAction>[
            ResourceMapDesktopModeAction(
              controlKey: const ValueKey<String>('mode-gather'),
              icon: const Icon(Icons.location_on_outlined),
              label: 'Gather',
              badge: '12',
              selected: true,
              onPressed: () => gatherPresses += 1,
            ),
            const ResourceMapDesktopModeAction(
              controlKey: ValueKey<String>('mode-workers'),
              icon: Icon(Icons.account_tree_outlined),
              label: 'Worker Network',
              badge: '18 CP',
            ),
            ResourceMapDesktopModeAction(
              controlKey: const ValueKey<String>('mode-checklist'),
              icon: const Icon(Icons.checklist_rounded),
              label: 'Gather List',
              onPressed: () {},
            ),
          ],
        ),
      ),
    );

    final strip = find.byKey(
      const ValueKey<String>('resource-map-mode-action-strip'),
    );
    final gather = find.byKey(const ValueKey<String>('mode-gather'));
    final workers = find.byKey(const ValueKey<String>('mode-workers'));
    expect(tester.getSize(gather).height, greaterThanOrEqualTo(44));
    expect(tester.getSize(workers).height, greaterThanOrEqualTo(44));
    expect(
      tester
          .getSize(find.descendant(of: strip, matching: find.byType(Row)).first)
          .width,
      greaterThan(tester.getSize(strip).width),
    );
    expect(
      find.descendant(of: strip, matching: find.byType(Card)),
      findsNothing,
    );
    expect(
      find.descendant(of: strip, matching: find.byType(Scrollbar)),
      findsNothing,
    );
    expect(
      find.descendant(of: strip, matching: find.byType(RawScrollbar)),
      findsNothing,
    );

    final gatherDecoration =
        tester
                .widget<AnimatedContainer>(
                  find
                      .descendant(
                        of: gather,
                        matching: find.byType(AnimatedContainer),
                      )
                      .first,
                )
                .decoration
            as BoxDecoration;
    expect(gatherDecoration.border!.top.color, ResourceMapAtlasColors.primary);
    expect(
      gatherDecoration.border!.bottom.color,
      gatherDecoration.border!.top.color,
      reason: 'Selected action pills use an even outline, not an underline.',
    );
    expect(
      tester
          .widget<IconTheme>(
            find.descendant(of: gather, matching: find.byType(IconTheme)).first,
          )
          .data
          .color,
      ResourceMapAtlasColors.accent,
    );
    expect(
      find.descendant(of: gather, matching: find.byType(Positioned)),
      findsNothing,
    );

    final gatherSemantics = tester.widget<Semantics>(
      find.ancestor(of: gather, matching: find.byType(Semantics)).first,
    );
    expect(gatherSemantics.properties.label, 'Gather');
    expect(gatherSemantics.properties.value, '12');
    expect(gatherSemantics.properties.selected, isTrue);
    expect(gatherSemantics.properties.enabled, isTrue);
    final workerSemantics = tester.widget<Semantics>(
      find.ancestor(of: workers, matching: find.byType(Semantics)).first,
    );
    expect(workerSemantics.properties.label, 'Worker Network');
    expect(workerSemantics.properties.enabled, isFalse);

    await tester.tap(gather);
    expect(gatherPresses, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('mode action entrance is finite and honors reduced motion', (
    tester,
  ) async {
    Widget actionStrip({required bool disableAnimations}) => _shellTestApp(
      width: 260,
      height: 70,
      disableAnimations: disableAnimations,
      child: ResourceMapDesktopModeActionStrip(
        actions: <ResourceMapDesktopModeAction>[
          ResourceMapDesktopModeAction(
            controlKey: const ValueKey<String>('motion-entry-action'),
            icon: const Icon(Icons.route_outlined),
            label: 'Route planner',
            onPressed: () {},
          ),
        ],
      ),
    );

    Finder enterTransition() => find
        .ancestor(
          of: find.byKey(const ValueKey<String>('motion-entry-action')),
          matching: find.byWidgetPredicate(
            (widget) => widget is TweenAnimationBuilder<double>,
          ),
        )
        .first;

    await tester.pumpWidget(actionStrip(disableAnimations: false));
    expect(
      tester.widget<TweenAnimationBuilder<double>>(enterTransition()).duration,
      ResourceMapDesktopMotion.enter,
    );
    await tester.pumpAndSettle();
    expect(tester.binding.hasScheduledFrame, isFalse);
    expect(
      tester
          .getSize(find.byKey(const ValueKey<String>('motion-entry-action')))
          .height,
      greaterThanOrEqualTo(44),
    );

    await tester.pumpWidget(actionStrip(disableAnimations: true));
    expect(
      tester.widget<TweenAnimationBuilder<double>>(enterTransition()).duration,
      Duration.zero,
    );
    await tester.pumpAndSettle();
    expect(tester.binding.hasScheduledFrame, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('mode action hover settles without moving its hit target', (
    tester,
  ) async {
    await tester.pumpWidget(
      _shellTestApp(
        width: 260,
        height: 70,
        disableAnimations: false,
        child: ResourceMapDesktopModeActionStrip(
          actions: <ResourceMapDesktopModeAction>[
            ResourceMapDesktopModeAction(
              controlKey: const ValueKey<String>('motion-hover-action'),
              icon: const Icon(Icons.travel_explore_outlined),
              label: 'Find nodes',
              onPressed: () {},
            ),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();

    final action = find.byKey(const ValueKey<String>('motion-hover-action'));
    final restingRect = tester.getRect(action);
    BoxDecoration actionDecoration() =>
        tester
                .widget<AnimatedContainer>(
                  find
                      .descendant(
                        of: action,
                        matching: find.byType(AnimatedContainer),
                      )
                      .first,
                )
                .decoration
            as BoxDecoration;

    expect(actionDecoration().boxShadow!.single.blurRadius, 10);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(tester.getCenter(action));
    await tester.pumpAndSettle();

    expect(actionDecoration().boxShadow!.single.blurRadius, 13);
    expect(actionDecoration().border!.top.color.a, closeTo(.72, .01));
    expect(tester.getRect(action), restingRect);

    await mouse.moveTo(const Offset(790, 590));
    await tester.pumpAndSettle();
    await mouse.removePointer();
    expect(actionDecoration().boxShadow!.single.blurRadius, 10);
    expect(tester.binding.hasScheduledFrame, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('mode strip scrolls complete labels safely at 200 percent text', (
    tester,
  ) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);
    var housingPresses = 0;
    await tester.pumpWidget(
      _shellTestApp(
        width: 300,
        height: 86,
        textScaler: const TextScaler.linear(2),
        child: ResourceMapDesktopModeActionStrip(
          controller: controller,
          actions: <ResourceMapDesktopModeAction>[
            ResourceMapDesktopModeAction(
              controlKey: const ValueKey<String>('large-gather'),
              icon: const Icon(Icons.location_on_outlined),
              label: 'Gathering Locations',
              onPressed: () {},
            ),
            ResourceMapDesktopModeAction(
              controlKey: const ValueKey<String>('large-workers'),
              icon: const Icon(Icons.account_tree_outlined),
              label: 'Worker Network',
              onPressed: () {},
            ),
            ResourceMapDesktopModeAction(
              controlKey: const ValueKey<String>('large-housing'),
              icon: const Icon(Icons.holiday_village_outlined),
              label: 'Houses and Lodging',
              onPressed: () => housingPresses += 1,
            ),
          ],
        ),
      ),
    );

    final strip = find.byKey(
      const ValueKey<String>('resource-map-mode-action-strip'),
    );
    expect(tester.getSize(strip).width, 300);
    for (final label in <String>[
      'Gathering Locations',
      'Worker Network',
      'Houses and Lodging',
    ]) {
      expect(
        tester
            .renderObject<RenderParagraph>(find.text(label))
            .didExceedMaxLines,
        isFalse,
      );
    }
    expect(tester.takeException(), isNull);

    controller.jumpTo(controller.position.maxScrollExtent);
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey<String>('large-housing')));
    expect(housingPresses, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'narrow mode strip exposes compact edge controls and reaches every action',
    (tester) async {
      final controller = ScrollController();
      addTearDown(controller.dispose);
      var lastActionPresses = 0;
      await tester.pumpWidget(
        _shellTestApp(
          width: 250,
          height: 70,
          child: ResourceMapDesktopModeActionStrip(
            controller: controller,
            actions: <ResourceMapDesktopModeAction>[
              ResourceMapDesktopModeAction(
                controlKey: const ValueKey<String>('edge-first-action'),
                icon: const Icon(Icons.location_on_outlined),
                label: 'Gathering Locations',
                onPressed: () {},
              ),
              ResourceMapDesktopModeAction(
                icon: const Icon(Icons.account_tree_outlined),
                label: 'Worker Network',
                onPressed: () {},
              ),
              ResourceMapDesktopModeAction(
                icon: const Icon(Icons.holiday_village_outlined),
                label: 'Houses and Lodging',
                onPressed: () {},
              ),
              ResourceMapDesktopModeAction(
                controlKey: const ValueKey<String>('edge-last-action'),
                icon: const Icon(Icons.checklist_rounded),
                label: 'Gather Checklist',
                onPressed: () => lastActionPresses += 1,
              ),
            ],
          ),
        ),
      );
      await tester.pump();

      const backKey = ValueKey<String>('resource-map-mode-actions-scroll-left');
      const forwardKey = ValueKey<String>(
        'resource-map-mode-actions-scroll-right',
      );
      expect(find.byKey(backKey), findsNothing);
      expect(find.byKey(forwardKey), findsOneWidget);
      expect(find.byTooltip('Show more map tasks'), findsOneWidget);
      expect(tester.getSize(find.byKey(forwardKey)).width, 52);
      expect(
        find.byKey(const ValueKey<String>('edge-last-action')).hitTestable(),
        findsNothing,
        reason: 'The final task starts outside the narrow viewport.',
      );
      expect(find.byType(Scrollbar), findsNothing);
      expect(find.byType(RawScrollbar), findsNothing);

      for (
        var step = 0;
        step < 12 && find.byKey(forwardKey).evaluate().isNotEmpty;
        step++
      ) {
        await tester.tap(find.byKey(forwardKey));
        await tester.pumpAndSettle();
      }

      expect(controller.offset, controller.position.maxScrollExtent);
      expect(find.byKey(forwardKey), findsNothing);
      expect(find.byKey(backKey), findsOneWidget);
      expect(find.byTooltip('Show previous map tasks'), findsOneWidget);
      final lastAction = find.byKey(const ValueKey<String>('edge-last-action'));
      expect(lastAction.hitTestable(), findsOneWidget);
      await tester.tap(lastAction);
      expect(lastActionPresses, 1);

      for (
        var step = 0;
        step < 12 && find.byKey(backKey).evaluate().isNotEmpty;
        step++
      ) {
        await tester.tap(find.byKey(backKey));
        await tester.pumpAndSettle();
      }

      expect(controller.offset, controller.position.minScrollExtent);
      expect(find.byKey(backKey), findsNothing);
      expect(find.byKey(forwardKey), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('bottom workbench uses finite content islands and three panes', (
    tester,
  ) async {
    await tester.pumpWidget(
      _shellTestApp(
        width: 1100,
        height: 320,
        child: ResourceMapDesktopWorkbench(
          wideBreakpoint: 700,
          header: const Text('Plan this worker route'),
          leading: const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[Text('Selected node'), Text('Beombawi Valley')],
          ),
          body: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const Text('Materials in this setup'),
              for (var index = 0; index < 14; index++)
                SizedBox(height: 30, child: Text('Material $index')),
            ],
          ),
          summary: const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[Text('Route summary'), Text('42 CP')],
          ),
        ),
      ),
    );

    final workbench = find.byKey(
      const ValueKey<String>('resource-map-network-workbench'),
    );
    final leading = find.byKey(
      const ValueKey<String>('resource-map-network-workbench-leading'),
    );
    final body = find.byKey(
      const ValueKey<String>('resource-map-network-workbench-body'),
    );
    final summary = find.byKey(
      const ValueKey<String>('resource-map-network-workbench-summary'),
    );
    expect(tester.getSize(workbench).height, 280);
    expect(tester.getTopLeft(leading).dx, lessThan(tester.getTopLeft(body).dx));
    expect(tester.getTopLeft(body).dx, lessThan(tester.getTopLeft(summary).dx));
    expect(
      find.byKey(
        const ValueKey<String>('resource-map-network-workbench-scroll'),
      ),
      findsOneWidget,
    );
    expect(find.byType(Card), findsNothing);
    expect(find.byType(Scrollbar), findsNothing);
    expect(find.byType(RawScrollbar), findsNothing);

    await tester.drag(
      find.byKey(
        const ValueKey<String>('resource-map-network-workbench-scroll'),
      ),
      const Offset(0, -180),
    );
    await tester.pump();
    expect(find.text('Material 13'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('workbench backs content without drawing a full tray', (
    tester,
  ) async {
    await tester.pumpWidget(
      _shellTestApp(
        width: 980,
        height: 260,
        child: const ResourceMapDesktopWorkbench(
          height: 238,
          body: Text('Worker route'),
        ),
      ),
    );

    final surfaceFinder = find.byKey(
      const ValueKey<String>('resource-map-network-workbench'),
    );
    final surface = tester.widget<SizedBox>(surfaceFinder);
    final islandFinder = find.descendant(
      of: surfaceFinder,
      matching: find.byType(DecoratedBox),
    );
    final island = tester.widget<DecoratedBox>(islandFinder.first);
    final decoration = island.decoration as BoxDecoration;
    final gradient = decoration.gradient! as LinearGradient;

    expect(tester.getSize(surfaceFinder).height, 238);
    expect(surface.child, isA<Column>());
    expect(decoration.color, isNull);
    expect(decoration.borderRadius, BorderRadius.circular(12));
    expect(decoration.border, isNotNull);
    expect(decoration.boxShadow, hasLength(2));
    expect(gradient.colors, hasLength(3));
    expect(gradient.colors.every((color) => color.a < 1), isTrue);
    expect(
      find.descendant(
        of: islandFinder.first,
        matching: find.byType(CustomPaint),
      ),
      findsWidgets,
    );
    expect(find.byType(BackdropFilter), findsNothing);
    expect(find.byType(Card), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'hidden workbench blocks pointers, focus and accessibility semantics',
    (tester) async {
      final visibility = ValueNotifier<bool>(true);
      final focusNode = FocusNode();
      addTearDown(visibility.dispose);
      addTearDown(focusNode.dispose);
      var presses = 0;

      await tester.pumpWidget(
        _shellTestApp(
          width: 760,
          height: 240,
          child: ValueListenableBuilder<bool>(
            valueListenable: visibility,
            builder: (context, visible, _) => ResourceMapDesktopWorkbench(
              visible: visible,
              height: 220,
              semanticLabel: 'Route editing workbench',
              body: Align(
                alignment: Alignment.topLeft,
                child: TextButton(
                  focusNode: focusNode,
                  onPressed: () => presses += 1,
                  child: const Text('Apply worker route'),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Apply worker route'));
      await tester.pump();
      expect(presses, 1);
      focusNode.requestFocus();
      await tester.pump();
      expect(focusNode.hasFocus, isTrue);

      visibility.value = false;
      await tester.pump();
      await tester.pump();

      expect(
        tester
            .widget<IgnorePointer>(
              find.byKey(
                const ValueKey<String>('resource-map-workbench-pointer-guard'),
              ),
            )
            .ignoring,
        isTrue,
      );
      expect(
        tester
            .widget<ExcludeFocus>(
              find.byKey(
                const ValueKey<String>('resource-map-workbench-focus-guard'),
              ),
            )
            .excluding,
        isTrue,
      );
      expect(
        tester
            .widget<ExcludeSemantics>(
              find.byKey(
                const ValueKey<String>(
                  'resource-map-workbench-semantics-guard',
                ),
              ),
            )
            .excluding,
        isTrue,
      );
      expect(focusNode.hasFocus, isFalse);

      final semantics = tester.ensureSemantics();
      final accessibleLabels = tester.semantics
          .simulatedAccessibilityTraversal()
          .map((node) => node.getSemanticsData().label)
          .toList();
      expect(accessibleLabels, isNot(contains('Route editing workbench')));
      expect(accessibleLabels, isNot(contains('Apply worker route')));
      semantics.dispose();

      await tester.tap(find.text('Apply worker route'), warnIfMissed: false);
      await tester.pump();
      expect(presses, 1);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('workbench slides and fades with reduced-motion support', (
    tester,
  ) async {
    final visibility = ValueNotifier<bool>(true);
    addTearDown(visibility.dispose);
    var completedTransitions = 0;

    Widget testWorkbench() => ValueListenableBuilder<bool>(
      valueListenable: visibility,
      builder: (context, visible, _) => ResourceMapDesktopWorkbench(
        visible: visible,
        height: 200,
        onAnimationEnd: () => completedTransitions += 1,
        body: const Text('Animated worker route'),
      ),
    );

    await tester.pumpWidget(
      _shellTestApp(
        width: 760,
        height: 220,
        disableAnimations: false,
        child: testWorkbench(),
      ),
    );
    visibility.value = false;
    await tester.pump();

    var slide = tester.widget<AnimatedSlide>(
      find.byKey(const ValueKey<String>('resource-map-workbench-slide')),
    );
    var fade = tester.widget<AnimatedOpacity>(
      find.byKey(const ValueKey<String>('resource-map-workbench-fade')),
    );
    expect(slide.offset, const Offset(0, 1.08));
    expect(slide.duration, const Duration(milliseconds: 220));
    expect(fade.opacity, 0);
    expect(fade.duration, const Duration(milliseconds: 220));

    await tester.pumpAndSettle();
    expect(completedTransitions, 1);

    await tester.pumpWidget(
      _shellTestApp(width: 760, height: 220, child: testWorkbench()),
    );
    slide = tester.widget<AnimatedSlide>(
      find.byKey(const ValueKey<String>('resource-map-workbench-slide')),
    );
    fade = tester.widget<AnimatedOpacity>(
      find.byKey(const ValueKey<String>('resource-map-workbench-fade')),
    );
    expect(slide.duration, Duration.zero);
    expect(fade.duration, Duration.zero);
    expect(tester.takeException(), isNull);
  });

  testWidgets('workbench stacks and scrolls under large text', (tester) async {
    await tester.pumpWidget(
      _shellTestApp(
        width: 700,
        height: 250,
        textScaler: const TextScaler.linear(2),
        child: const ResourceMapDesktopWorkbench(
          height: 230,
          header: Text('Worker route editor'),
          leading: Text('Selected production node'),
          body: Text('Materials and route changes'),
          summary: Text('Contribution Points and lodging'),
        ),
      ),
    );

    final leading = find.byKey(
      const ValueKey<String>('resource-map-network-workbench-leading'),
    );
    final body = find.byKey(
      const ValueKey<String>('resource-map-network-workbench-body'),
    );
    final summary = find.byKey(
      const ValueKey<String>('resource-map-network-workbench-summary'),
    );
    expect(tester.getTopLeft(leading).dy, lessThan(tester.getTopLeft(body).dy));
    expect(tester.getTopLeft(body).dy, lessThan(tester.getTopLeft(summary).dy));
    expect(
      find.byKey(
        const ValueKey<String>('resource-map-network-workbench-scroll'),
      ),
      findsOneWidget,
    );
    expect(find.byType(Scrollbar), findsNothing);
    expect(find.byType(RawScrollbar), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('workbench can give an internally scrolling body finite bounds', (
    tester,
  ) async {
    Widget boundedBody() {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const Text('Materials in this route'),
          const SizedBox(height: 8),
          Expanded(
            child: ListView.builder(
              key: const ValueKey<String>('bounded-workbench-list'),
              itemCount: 30,
              itemBuilder: (context, index) =>
                  SizedBox(height: 36, child: Text('Route material $index')),
            ),
          ),
        ],
      );
    }

    for (final textScaler in <TextScaler>[
      TextScaler.noScaling,
      const TextScaler.linear(2),
    ]) {
      await tester.pumpWidget(
        _shellTestApp(
          width: 700,
          height: 250,
          textScaler: textScaler,
          child: ResourceMapDesktopWorkbench(
            height: 230,
            wideBreakpoint: 600,
            bodyScrolls: false,
            header: const Text('Edit worker network'),
            body: boundedBody(),
          ),
        ),
      );

      final body = find.byKey(
        const ValueKey<String>('resource-map-network-workbench-body'),
      );
      final list = find.byKey(const ValueKey<String>('bounded-workbench-list'));
      expect(
        find.byKey(
          const ValueKey<String>('resource-map-network-workbench-scroll'),
        ),
        findsNothing,
      );
      expect(tester.getSize(body).height, greaterThan(80));
      expect(tester.getSize(list).height, greaterThan(40));
      expect(find.byType(Scrollbar), findsNothing);
      expect(find.byType(RawScrollbar), findsNothing);
      expect(tester.takeException(), isNull);

      await tester.drag(list, const Offset(0, -120));
      await tester.pump();
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('slim tool rail keeps accessible 44 pixel actions', (
    tester,
  ) async {
    var nodePresses = 0;
    await tester.pumpWidget(
      _shellTestApp(
        width: 80,
        height: 120,
        child: ResourceMapDesktopToolRail(
          actions: <ResourceMapDesktopToolRailAction>[
            ResourceMapDesktopToolRailAction(
              controlKey: const ValueKey<String>('tool-nodes'),
              icon: const Icon(Icons.hub_outlined),
              label: 'Nodes',
              selected: true,
              onPressed: () => nodePresses += 1,
            ),
            const ResourceMapDesktopToolRailAction(
              controlKey: ValueKey<String>('tool-routes'),
              icon: Icon(Icons.route_outlined),
              label: 'Routes',
            ),
            ResourceMapDesktopToolRailAction(
              controlKey: const ValueKey<String>('tool-houses'),
              icon: const Icon(Icons.house_outlined),
              label: 'Housing',
              onPressed: () {},
            ),
          ],
        ),
      ),
    );

    final rail = find.byKey(
      const ValueKey<String>('resource-map-side-tool-rail'),
    );
    final nodeAction = find.byKey(const ValueKey<String>('tool-nodes'));
    expect(tester.getSize(rail).width, 52);
    expect(tester.getSize(nodeAction), const Size(44, 44));
    expect(find.byTooltip('Nodes'), findsOneWidget);
    expect(find.byTooltip('Routes'), findsOneWidget);
    expect(find.byType(Scrollbar), findsNothing);
    expect(find.byType(RawScrollbar), findsNothing);

    final nodeSemantics = tester.widget<Semantics>(
      find.ancestor(of: nodeAction, matching: find.byType(Semantics)).first,
    );
    expect(nodeSemantics.properties.label, 'Nodes');
    expect(nodeSemantics.properties.selected, isTrue);
    expect(nodeSemantics.properties.enabled, isTrue);
    final routeSemantics = tester.widget<Semantics>(
      find
          .ancestor(
            of: find.byKey(const ValueKey<String>('tool-routes')),
            matching: find.byType(Semantics),
          )
          .first,
    );
    expect(routeSemantics.properties.enabled, isFalse);

    final animation = tester.widget<AnimatedContainer>(
      find
          .descendant(of: nodeAction, matching: find.byType(AnimatedContainer))
          .first,
    );
    expect(animation.duration, Duration.zero);

    await tester.tap(nodeAction);
    expect(nodePresses, 1);
    await tester.drag(
      find.byKey(const ValueKey<String>('resource-map-side-tool-rail-scroll')),
      const Offset(0, -80),
    );
    await tester.pump();
    expect(find.byKey(const ValueKey<String>('tool-houses')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('large text wraps the complete task title instead of clipping', (
    tester,
  ) async {
    const title = 'Worker income planner';

    await tester.pumpWidget(
      _shellTestApp(
        width: 318,
        height: 140,
        textScaler: const TextScaler.linear(2),
        child: ResourceMapDesktopTaskStrip(
          leadingIcon: Icons.account_tree_outlined,
          title: title,
          actions: const <Widget>[],
          onBack: () {},
          onClose: () {},
        ),
      ),
    );

    final titleFinder = find.text(title);
    final titleWidget = tester.widget<Text>(titleFinder);
    final titleParagraph = tester.renderObject<RenderParagraph>(titleFinder);

    expect(titleWidget.maxLines, isNull);
    expect(titleParagraph.didExceedMaxLines, isFalse);
    expect(
      tester
          .getSize(
            find.byKey(
              const ValueKey<String>('resource-map-desktop-task-strip'),
            ),
          )
          .height,
      greaterThan(48),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'context rail feathers busy map content behind readable controls',
    (tester) async {
      var backPresses = 0;
      var closePresses = 0;
      var inlinePresses = 0;

      await tester.pumpWidget(
        _shellTestApp(
          width: 414,
          height: 360,
          child: ResourceMapDesktopEdgeSurface(
            contentWidth: 318,
            child: Column(
              children: <Widget>[
                ResourceMapDesktopTaskStrip(
                  leadingIcon: Icons.account_tree_outlined,
                  title: 'Worker network',
                  actions: const <Widget>[],
                  onBack: () => backPresses += 1,
                  onClose: () => closePresses += 1,
                ),
                const SizedBox(height: 8),
                ResourceMapInlineAction(
                  key: const ValueKey<String>('test-inline-action'),
                  icon: Icons.route_outlined,
                  label: 'Current route',
                  badge: '18 CP',
                  selected: true,
                  onPressed: () => inlinePresses += 1,
                ),
              ],
            ),
          ),
        ),
      );

      final edgeFinder = find.byKey(
        const ValueKey<String>('resource-map-desktop-edge-surface'),
      );
      expect(
        tester.widget<Padding>(edgeFinder).padding,
        const EdgeInsets.only(left: 14, right: 46),
      );
      expect(tester.widget<Padding>(edgeFinder).child, isA<SizedBox>());
      final edgeScrim = tester.widget<DecoratedBox>(
        find
            .ancestor(of: edgeFinder, matching: find.byType(DecoratedBox))
            .first,
      );
      final edgeDecoration = edgeScrim.decoration as BoxDecoration;
      final edgeGradient = edgeDecoration.gradient! as LinearGradient;
      expect(edgeGradient.colors.first.a, greaterThan(.95));
      expect(edgeGradient.colors.last.a, 0);
      expect(edgeDecoration.border, isNull);
      expect(edgeDecoration.borderRadius, isNull);
      expect(find.byType(Card), findsNothing);
      expect(find.byType(ClipRRect), findsNothing);
      expect(find.byType(Divider), findsNothing);

      final taskStripFinder = find.byKey(
        const ValueKey<String>('resource-map-desktop-task-strip'),
      );
      final taskStrip = tester.getSize(taskStripFinder);
      expect(taskStrip.height, 48);
      final taskSurface = tester.widget<DecoratedBox>(
        find
            .descendant(
              of: taskStripFinder,
              matching: find.byType(DecoratedBox),
            )
            .first,
      );
      final taskDecoration = taskSurface.decoration as BoxDecoration;
      expect(taskDecoration.gradient, isA<LinearGradient>());
      expect(taskDecoration.boxShadow, isNotEmpty);
      expect(
        taskDecoration.border!.top.color,
        ResourceMapAtlasColors.warmOutline,
        reason:
            'The section/back label carries a compact legibility island instead '
            'of relying on a broad sidebar slab.',
      );
      expect(find.text('Worker network'), findsOneWidget);
      expect(find.text('18 CP'), findsOneWidget);
      final title = tester.widget<Text>(find.text('Worker network'));
      expect(title.style!.color, ResourceMapAtlasColors.ink);
      expect(title.style!.fontSize, 15);
      final inlineMaterial = tester.widget<Material>(
        find.descendant(
          of: find.byKey(const ValueKey<String>('test-inline-action')),
          matching: find.byType(Material),
        ),
      );
      expect(inlineMaterial.color, Colors.transparent);
      final inlineAnimation = tester.widget<AnimatedContainer>(
        find
            .descendant(
              of: find.byKey(const ValueKey<String>('test-inline-action')),
              matching: find.byType(AnimatedContainer),
            )
            .first,
      );
      final selectedDecoration = inlineAnimation.decoration as BoxDecoration;
      expect(inlineAnimation.duration, Duration.zero);
      expect(selectedDecoration.gradient, isA<LinearGradient>());
      expect(
        selectedDecoration.border!.top.color,
        ResourceMapAtlasColors.primary,
      );
      expect(
        selectedDecoration.border!.bottom.color,
        selectedDecoration.border!.top.color,
        reason: 'Selection is a filled island with an even outline.',
      );

      final inlineSemantics = tester.widget<Semantics>(
        find
            .descendant(
              of: find.byKey(const ValueKey<String>('test-inline-action')),
              matching: find.byType(Semantics),
            )
            .first,
      );
      expect(inlineSemantics.properties.label, 'Current route');
      expect(inlineSemantics.properties.selected, isTrue);

      await tester.tap(
        find.byKey(const ValueKey<String>('resource-map-task-back')),
      );
      await tester.tap(
        find.byKey(const ValueKey<String>('resource-map-task-close')),
      );
      await tester.tap(
        find.byKey(const ValueKey<String>('test-inline-action')),
      );
      expect(backPresses, 1);
      expect(closePresses, 1);
      expect(inlinePresses, 1);
      expect(tester.takeException(), isNull);
    },
  );
}

Widget _shellTestApp({
  required double width,
  required double height,
  required Widget child,
  TextScaler textScaler = TextScaler.noScaling,
  bool disableAnimations = true,
}) {
  return MaterialApp(
    home: MediaQuery(
      data: MediaQueryData(
        disableAnimations: disableAnimations,
        textScaler: textScaler,
      ),
      child: Material(
        color: ResourceMapAtlasColors.canvas,
        child: Center(
          child: SizedBox(
            width: width,
            height: height,
            child: Align(alignment: Alignment.topCenter, child: child),
          ),
        ),
      ),
    ),
  );
}
