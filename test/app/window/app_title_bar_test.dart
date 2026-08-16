import 'dart:async';
import 'dart:ui' as ui;

import 'package:bdo_craft_planner_flutter/app/window/app_title_bar.dart';
import 'package:bdo_craft_planner_flutter/app/window/window_host_service.dart';
import 'package:bdo_craft_planner_flutter/app_identity.dart';
import 'package:bdo_craft_planner_flutter/visual/foundations/theme_spec.dart';
import 'package:bdo_craft_planner_flutter/visual/illuminated_ledger/ledger_spec.dart';
import 'package:bdo_craft_planner_flutter/visual/sakura_night_garden/sakura_botanical_assets.dart';
import 'package:bdo_craft_planner_flutter/visual/sakura_night_garden/sakura_spec.dart';
import 'package:bdo_craft_planner_flutter/visual/standard/standard_spec.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('com.bdocraftplanner.flutter/window');
  final calls = <String>[];

  setUp(() {
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method != 'isMaximized') calls.add(call.method);
          return switch (call.method) {
            'isMaximized' => false,
            'toggleMaximize' => true,
            _ => null,
          };
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  testWidgets('caption controls invoke distinct native operations', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: AppTitleBar())),
    );

    await tester.tap(find.byTooltip('Minimize'));
    await tester.tap(find.byTooltip('Maximize or restore'));
    await tester.tap(find.byTooltip('Close'));
    await tester.pump();

    expect(calls, ['minimize', 'toggleMaximize', 'close']);
  });

  testWidgets('optional trailing action remains before every caption control', (
    tester,
  ) async {
    const trailingKey = ValueKey<String>('test-title-trailing');
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 600,
            child: AppTitleBar(
              trailing: SizedBox.square(key: trailingKey, dimension: 40),
            ),
          ),
        ),
      ),
    );

    expect(find.byKey(AppTitleBar.trailingHostKey), findsOneWidget);
    expect(find.byKey(trailingKey), findsOneWidget);
    expect(find.byTooltip('Minimize'), findsOneWidget);
    expect(find.byTooltip('Maximize or restore'), findsOneWidget);
    expect(find.byTooltip('Close'), findsOneWidget);
    expect(
      tester.getTopLeft(find.byKey(trailingKey)).dx,
      lessThan(tester.getTopLeft(find.byTooltip('Minimize')).dx),
    );
  });

  testWidgets('startup title bar uses the Black Spirit Life identity artwork', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: AppTitleBar())),
    );

    final icon = tester.widget<Image>(
      find.descendant(
        of: find.byKey(AppTitleBar.iconFrameKey),
        matching: find.byType(Image),
      ),
    );
    expect((icon.image as AssetImage).assetName, AppIdentity.appIconAssetPath);
  });

  testWidgets('active application tab expands while the other stays compact', (
    tester,
  ) async {
    var plannerSelected = true;
    late StateSetter updateTabs;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 440,
              child: StatefulBuilder(
                builder: (context, setState) {
                  updateTabs = setState;
                  return AppTitleTabStrip(
                    tabs: <AppTitleTab>[
                      AppTitleTab(
                        tabKey: const ValueKey<String>('planner-tab'),
                        icon: Icons.calculate_outlined,
                        label: 'Craft Planner',
                        selected: plannerSelected,
                        onPressed: () =>
                            updateTabs(() => plannerSelected = true),
                      ),
                      AppTitleTab(
                        tabKey: const ValueKey<String>('map-tab'),
                        icon: Icons.travel_explore_outlined,
                        label: 'Resource Map',
                        selected: !plannerSelected,
                        onPressed: () =>
                            updateTabs(() => plannerSelected = false),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );

    final plannerSurface = find.byKey(
      AppTitleTabStrip.surfaceKey('Craft Planner'),
    );
    final mapSurface = find.byKey(AppTitleTabStrip.surfaceKey('Resource Map'));
    final plannerExpandedWidth = tester.getSize(plannerSurface).width;
    expect(plannerExpandedWidth, greaterThan(100));
    expect(tester.getSize(mapSurface).width, 52);
    expect(
      find.descendant(of: plannerSurface, matching: find.text('Craft Planner')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: mapSurface, matching: find.text('Resource Map')),
      findsNothing,
    );
    final plannerDecoration =
        tester.widget<AnimatedContainer>(plannerSurface).decoration!
            as BoxDecoration;
    expect(plannerDecoration.color, isNotNull);
    expect(plannerDecoration.gradient, isNull);
    expect(plannerDecoration.boxShadow, isNull);
    expect(plannerDecoration.border, isNotNull);

    await tester.tap(mapSurface);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 45));

    expect(
      tester.getSize(plannerSurface).width,
      inExclusiveRange(52, plannerExpandedWidth),
    );
    expect(tester.getSize(mapSurface).width, greaterThan(52));

    await tester.pumpAndSettle();

    expect(tester.getSize(plannerSurface).width, 52);
    expect(tester.getSize(mapSurface).width, greaterThan(100));
    expect(
      find.descendant(of: plannerSurface, matching: find.text('Craft Planner')),
      findsNothing,
    );
    expect(
      find.descendant(of: mapSurface, matching: find.text('Resource Map')),
      findsOneWidget,
    );
    final mapDecoration =
        tester.widget<AnimatedContainer>(mapSurface).decoration!
            as BoxDecoration;
    expect(mapDecoration.border, isNotNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'workspace title uses crisp destination artwork without a redundant icon',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetDevicePixelRatio);

      const artwork = <String, String>{
        'Craft Planner': 'assets/app/bdo_tool_icon.png',
        'Resource Map': 'assets/app/bdo_resource_map_icon.png',
      };
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AppTitleBar(
              workspaceNavigation: AppTitleTabStrip(
                tabs: <AppTitleTab>[
                  AppTitleTab(
                    tabKey: const ValueKey<String>('planner-tab'),
                    artworkAssetPath: artwork['Craft Planner'],
                    label: 'Craft Planner',
                    selected: true,
                    onPressed: () {},
                  ),
                  AppTitleTab(
                    tabKey: const ValueKey<String>('map-tab'),
                    artworkAssetPath: artwork['Resource Map'],
                    label: 'Resource Map',
                    selected: false,
                    onPressed: () {},
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(AppTitleBar.iconFrameKey), findsNothing);
      expect(find.text(AppIdentity.displayName), findsNothing);
      for (final entry in artwork.entries) {
        final artworkFinder = find.byKey(
          AppTitleTabStrip.artworkKey(entry.key),
        );
        expect(
          tester.getSize(artworkFinder),
          const Size.square(AppTitleTabStrip.artworkSize),
        );
        final image = tester.widget<Image>(
          find.descendant(of: artworkFinder, matching: find.byType(Image)),
        );
        expect(image.fit, BoxFit.cover);
        expect(image.filterQuality, FilterQuality.high);
        expect(image.isAntiAlias, isTrue);
        expect(image.gaplessPlayback, isTrue);
        expect(image.image, isA<ResizeImage>());
        final resized = image.image as ResizeImage;
        expect(resized.width, 102);
        expect(resized.height, 102);
        expect(resized.imageProvider, isA<AssetImage>());
        expect((resized.imageProvider as AssetImage).assetName, entry.value);
      }

      final compactMap = find.byKey(
        AppTitleTabStrip.surfaceKey('Resource Map'),
      );
      expect(tester.getSize(compactMap), const Size(52, 40));
      expect(
        tester
            .getRect(find.byKey(AppTitleTabStrip.artworkKey('Resource Map')))
            .center,
        tester.getRect(compactMap).center,
      );

      tester.view.devicePixelRatio = 3;
      await tester.pumpAndSettle();
      for (final label in artwork.keys) {
        final artworkFinder = find.byKey(AppTitleTabStrip.artworkKey(label));
        final image = tester.widget<Image>(
          find.descendant(of: artworkFinder, matching: find.byType(Image)),
        );
        final resized = image.image as ResizeImage;
        expect(resized.width, 102, reason: '$label at 300% display scale');
        expect(resized.height, 102, reason: '$label at 300% display scale');
      }
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('workspace destination artwork keeps high-resolution sources', (
    tester,
  ) async {
    for (final path in const <String>[
      'assets/app/bdo_tool_icon.png',
      'assets/app/bdo_resource_map_icon.png',
    ]) {
      ui.Codec? codec;
      ui.FrameInfo? frame;
      await tester.runAsync(() async {
        final data = await rootBundle.load(path);
        codec = await ui.instantiateImageCodec(
          data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
        );
        frame = await codec!.getNextFrame();
      });
      expect(frame, isNotNull);
      expect(frame!.image.width, greaterThanOrEqualTo(1024), reason: path);
      expect(frame!.image.height, greaterThanOrEqualTo(1024), reason: path);
      frame!.image.dispose();
      codec!.dispose();
    }
  });

  testWidgets(
    'selected destination stays named before the icon-only narrow fallback',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.noScaling),
            child: Scaffold(
              body: Align(
                alignment: Alignment.topLeft,
                child: SizedBox(
                  width: 360,
                  child: AppTitleTabStrip(
                    tabs: <AppTitleTab>[
                      AppTitleTab(
                        tabKey: const ValueKey<String>('planner-tab'),
                        icon: Icons.calculate_outlined,
                        label: 'Craft Planner',
                        selected: false,
                        onPressed: () {},
                      ),
                      AppTitleTab(
                        tabKey: const ValueKey<String>('map-tab'),
                        icon: Icons.travel_explore_outlined,
                        label: 'Resource Map',
                        selected: true,
                        onPressed: () {},
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );

      final plannerSurface = find.byKey(
        AppTitleTabStrip.surfaceKey('Craft Planner'),
      );
      final mapSurface = find.byKey(
        AppTitleTabStrip.surfaceKey('Resource Map'),
      );
      expect(tester.getSize(plannerSurface).width, 52);
      expect(tester.getSize(mapSurface).width, greaterThan(100));
      expect(
        find.descendant(
          of: plannerSurface,
          matching: find.text('Craft Planner'),
        ),
        findsNothing,
      );
      expect(
        find.descendant(of: mapSurface, matching: find.text('Resource Map')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey<String>('planner-tab')), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('map-tab')), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.noScaling),
            child: Scaffold(
              body: Align(
                alignment: Alignment.topLeft,
                child: SizedBox(
                  width: 92,
                  child: AppTitleTabStrip(
                    tabs: <AppTitleTab>[
                      AppTitleTab(
                        tabKey: const ValueKey<String>('planner-tab'),
                        icon: Icons.calculate_outlined,
                        label: 'Craft Planner',
                        selected: false,
                        onPressed: () {},
                      ),
                      AppTitleTab(
                        tabKey: const ValueKey<String>('map-tab'),
                        icon: Icons.travel_explore_outlined,
                        label: 'Resource Map',
                        selected: true,
                        onPressed: () {},
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.getSize(plannerSurface).width, 52);
      expect(tester.getSize(mapSurface).width, 52);
      expect(
        find.descendant(
          of: plannerSurface,
          matching: find.text('Craft Planner'),
        ),
        findsNothing,
      );
      expect(
        find.descendant(of: mapSurface, matching: find.text('Resource Map')),
        findsNothing,
      );
      expect(find.byKey(const ValueKey<String>('planner-tab')), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('map-tab')), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('active tab remains named in every theme at 200% text', (
    tester,
  ) async {
    for (final spec in const <ThemeSpec>[
      StandardSpec.theme,
      IlluminatedLedgerSpec.theme,
      SakuraNightGardenSpec.theme,
    ]) {
      await tester.pumpWidget(
        MaterialApp(
          theme: spec.materialTheme(),
          home: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(2)),
            child: ThemeSpecScope(
              spec: spec,
              child: Scaffold(
                body: Align(
                  alignment: Alignment.topLeft,
                  child: SizedBox(
                    width: 760,
                    child: AppTitleTabStrip(
                      tabs: <AppTitleTab>[
                        AppTitleTab(
                          tabKey: const ValueKey<String>('planner-tab'),
                          icon: Icons.calculate_outlined,
                          label: 'Craft Planner',
                          selected: true,
                          onPressed: () {},
                        ),
                        AppTitleTab(
                          tabKey: const ValueKey<String>('map-tab'),
                          icon: Icons.travel_explore_outlined,
                          label: 'Resource Map',
                          selected: false,
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
      );

      expect(find.text('Craft Planner'), findsOneWidget);
      expect(find.text('Resource Map'), findsNothing);
      expect(
        tester
            .getSize(find.byKey(AppTitleTabStrip.surfaceKey('Craft Planner')))
            .height,
        40,
      );
      expect(
        tester
            .getSize(find.byKey(AppTitleTabStrip.surfaceKey('Resource Map')))
            .height,
        40,
      );
      expect(tester.takeException(), isNull, reason: '${spec.family}');
    }
  });

  testWidgets(
    '600 logical pixels at 200% text keeps Planner and captions reachable',
    (tester) async {
      tester.view
        ..physicalSize = const Size(600, 200)
        ..devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.view.reset);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      var plannerActivated = false;

      await tester.pumpWidget(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          home: Scaffold(
            body: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                AppTitleBar(
                  workspaceNavigation: AppTitleTabStrip(
                    tabs: <AppTitleTab>[
                      AppTitleTab(
                        tabKey: const ValueKey<String>('planner-tab'),
                        icon: Icons.calculate_outlined,
                        label: 'Craft Planner',
                        selected: false,
                        onPressed: () => plannerActivated = true,
                      ),
                      AppTitleTab(
                        tabKey: const ValueKey<String>('map-tab'),
                        icon: Icons.travel_explore_outlined,
                        label: 'Resource Map',
                        selected: true,
                        onPressed: () {},
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pump();

      final planner = find.byKey(AppTitleTabStrip.surfaceKey('Craft Planner'));
      final map = find.byKey(AppTitleTabStrip.surfaceKey('Resource Map'));
      final titleRect = tester.getRect(find.byKey(AppTitleBar.materialKey));

      expect(planner, findsOneWidget);
      expect(map, findsOneWidget);
      expect(planner.hitTestable(), findsOneWidget);
      expect(map.hitTestable(), findsOneWidget);
      expect(tester.getSize(planner), const Size(52, 40));
      expect(tester.getSize(map).width, 52);
      expect(tester.getSize(map).height, 40);
      expect(
        find.descendant(of: map, matching: find.text('Resource Map')),
        findsNothing,
      );
      expect(
        find.descendant(
          of: planner,
          matching: find.byIcon(Icons.calculate_outlined),
        ),
        findsOneWidget,
      );
      expect(
        tester
            .widget<Semantics>(
              find.byKey(const ValueKey<String>('planner-tab')),
            )
            .properties
            .label,
        'Craft Planner',
      );

      for (final tooltip in const <String>[
        'Minimize',
        'Maximize or restore',
        'Close',
      ]) {
        final caption = find.byTooltip(tooltip);
        expect(caption, findsOneWidget);
        final captionRect = tester.getRect(caption);
        expect(captionRect.left, greaterThanOrEqualTo(titleRect.left));
        expect(captionRect.right, lessThanOrEqualTo(titleRect.right));
        expect(captionRect.top, greaterThanOrEqualTo(titleRect.top));
        expect(captionRect.bottom, lessThanOrEqualTo(titleRect.bottom));
      }

      await tester.tap(planner);
      await tester.pump();
      expect(plannerActivated, isTrue);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('title drag behavior is retained across every visual family', (
    tester,
  ) async {
    for (final spec in const <ThemeSpec>[
      StandardSpec.theme,
      IlluminatedLedgerSpec.theme,
      SakuraNightGardenSpec.theme,
    ]) {
      calls.clear();
      await tester.pumpWidget(
        MaterialApp(
          theme: spec.materialTheme(),
          home: ThemeSpecScope(
            spec: spec,
            child: Scaffold(
              body: AppTitleBar(
                workspaceNavigation: AppTitleTabStrip(
                  tabs: <AppTitleTab>[
                    AppTitleTab(
                      tabKey: const ValueKey<String>('planner-tab'),
                      icon: Icons.calculate_outlined,
                      label: 'Craft Planner',
                      selected: true,
                      onPressed: () {},
                    ),
                    AppTitleTab(
                      tabKey: const ValueKey<String>('map-tab'),
                      icon: Icons.travel_explore_outlined,
                      label: 'Resource Map',
                      selected: false,
                      onPressed: () {},
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );

      final dragRect = tester.getRect(find.byKey(AppTitleBar.dragRegionKey));
      final tabsRight = tester
          .getRect(find.byKey(AppTitleTabStrip.surfaceKey('Resource Map')))
          .right;
      final clearTitlePoint = Offset(tabsRight + 28, dragRect.center.dy);
      expect(clearTitlePoint.dx, lessThan(dragRect.right));
      final gesture = await tester.startGesture(clearTitlePoint);
      await tester.pump();
      await gesture.moveBy(const Offset(24, 0));
      await tester.pump();
      await gesture.up();
      await tester.pump(const Duration(milliseconds: 50));

      expect(
        calls.where((call) => call == 'beginDrag'),
        hasLength(1),
        reason: '${spec.family} must preserve native title dragging',
      );
    }
  });

  testWidgets('double-clicking the title strip toggles native maximize state', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: AppTitleBar())),
    );
    await tester.pump();

    await tester.tap(find.text(AppIdentity.displayName));
    await tester.pump(const Duration(milliseconds: 40));
    await tester.tap(find.text(AppIdentity.displayName));
    await tester.pump();

    expect(calls.where((call) => call == 'toggleMaximize'), hasLength(1));
    expect(_glyph('restore'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 400));
  });

  testWidgets('maximize response updates the caption icon state', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: AppTitleBar())),
    );
    await tester.pump();

    expect(_glyph('maximize'), findsOneWidget);
    await tester.tap(find.byTooltip('Maximize or restore'));
    await tester.pump();

    expect(_glyph('restore'), findsOneWidget);
  });

  testWidgets('caption artwork matches the retained pixel geometry', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: AppTitleBar())),
    );
    await tester.pump();

    for (final entry in const <String, String>{
      'minimize': 'Minimize',
      'maximize': 'Maximize or restore',
      'close': 'Close',
    }.entries) {
      final button = find.descendant(
        of: find.byTooltip(entry.value),
        matching: find.byType(IconButton),
      );
      expect(tester.getSize(button), const Size(52, 40));
      expect(
        tester.getRect(_glyph(entry.key)).center,
        tester.getRect(button).center,
      );
    }
    expect(tester.getSize(_glyph('minimize')), const Size.square(18));
    expect(tester.getSize(_glyph('maximize')), const Size.square(18));
    expect(tester.getSize(_glyph('close')), const Size.square(18));
    expect(
      await _paintedBounds(tester, _glyph('minimize')),
      const Rect.fromLTWH(1, 8, 17, 2),
    );
    expect(
      await _paintedBounds(tester, _glyph('maximize')),
      const Rect.fromLTWH(1, 1, 17, 17),
    );
    expect(
      await _paintedBounds(tester, _glyph('close')),
      const Rect.fromLTWH(1, 1, 16, 16),
    );

    await tester.tap(find.byTooltip('Maximize or restore'));
    await tester.pump();
    expect(
      await _paintedBounds(tester, _glyph('restore')),
      const Rect.fromLTWH(1, 1, 16, 16),
    );
  });

  testWidgets('Standard title strip resolves exact scene chrome', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: StandardVisualScope(
          settings: StandardVisualSettings(
            backgroundId: 'orrery',
            accentHue: 218,
          ),
          child: Scaffold(body: AppTitleBar()),
        ),
      ),
    );

    final material = tester.widget<DecoratedBox>(
      find.byKey(AppTitleBar.materialKey),
    );
    final decoration = material.decoration as BoxDecoration;
    expect(decoration.border, isNull);
    expect(
      (decoration.gradient! as LinearGradient).colors,
      StandardSpec.titleStripGradient('orrery').colors,
    );
    expect(
      tester.getSize(find.byKey(AppTitleBar.iconFrameKey)),
      const Size.square(24),
    );
    final title = tester.widget<Text>(find.text(AppIdentity.displayName));
    expect(title.style!.color, const Color(0xFFFFF0D0));
    expect(title.style!.fontFamily, 'Segoe UI');
    expect(title.style!.fontSize, 14);
    expect(title.style!.fontWeight, FontWeight.w700);
    expect(title.style!.letterSpacing, 0);
    expect(find.byKey(AppTitleBar.sakuraSprigKey), findsNothing);
    final minimize = find.descendant(
      of: find.byTooltip('Minimize'),
      matching: find.byType(IconButton),
    );
    expect(tester.getSize(minimize), const Size(52, 40));
    expect(tester.getSize(_glyph('minimize')), const Size.square(18));
    final close = find.descendant(
      of: find.byTooltip('Close'),
      matching: find.byType(IconButton),
    );
    expect(tester.getSize(close), const Size(52, 40));
    expect(tester.getSize(_glyph('close')), const Size.square(18));
    final maximize = find.descendant(
      of: find.byTooltip('Maximize or restore'),
      matching: find.byType(IconButton),
    );
    expect(tester.getSize(maximize), const Size(52, 40));
    expect(tester.getSize(_glyph('maximize')), const Size.square(18));
  });

  testWidgets('Ledger title strip uses the retained lapis and gold chrome', (
    tester,
  ) async {
    const spec = IlluminatedLedgerSpec.theme;
    await tester.pumpWidget(
      MaterialApp(
        theme: spec.materialTheme(),
        home: const ThemeSpecScope(
          spec: spec,
          child: Scaffold(body: AppTitleBar()),
        ),
      ),
    );

    final material = tester.widget<DecoratedBox>(
      find.byKey(AppTitleBar.materialKey),
    );
    final decoration = material.decoration as BoxDecoration;
    final gradient = decoration.gradient! as LinearGradient;
    expect(gradient.colors, const <Color>[
      Color(0xFF0A2744),
      Color(0xFF123D69),
      Color(0xFF071D35),
    ]);
    expect(gradient.stops, const <double>[0, .56, 1]);
    expect(
      decoration.border,
      const Border(bottom: BorderSide(color: Color(0xFFC9A14A), width: 1.5)),
    );
    final title = tester.widget<Text>(find.text(AppIdentity.displayName));
    expect(title.style!.color, const Color(0xFFEAD8A4));
    expect(title.style!.fontFamily, 'Segoe UI');
    expect(title.style!.fontSize, 14);
    expect(title.style!.fontWeight, FontWeight.w700);
    expect(title.style!.letterSpacing, 0);
    expect(find.byKey(AppTitleBar.sakuraSprigKey), findsNothing);
    expect(
      tester.getSize(find.byKey(AppTitleBar.iconFrameKey)),
      const Size.square(24),
    );
    final minimize = find.descendant(
      of: find.byTooltip('Minimize'),
      matching: find.byType(IconButton),
    );
    expect(tester.getSize(minimize), const Size(52, 40));
    expect(tester.getSize(_glyph('minimize')), const Size.square(18));
  });

  testWidgets('Sakura title strip keeps its fine serif lockup and safe sprig', (
    tester,
  ) async {
    const spec = SakuraNightGardenSpec.theme;
    await tester.pumpWidget(
      MaterialApp(
        theme: spec.materialTheme(),
        home: const ThemeSpecScope(
          spec: spec,
          child: Scaffold(body: AppTitleBar()),
        ),
      ),
    );

    final title = tester.widget<Text>(find.text(AppIdentity.displayName));
    expect(title.style!.fontFamily, 'Georgia');
    expect(title.style!.fontSize, 15);
    expect(title.style!.fontWeight, FontWeight.w600);
    expect(title.style!.color, SakuraNightGardenSpec.warmIvory);
    final sprigHost = find.byKey(AppTitleBar.sakuraSprigKey);
    final sprigImage = find.descendant(
      of: sprigHost,
      matching: find.byKey(SakuraTitleSprigAsset.imageKey),
    );
    expect(sprigHost, findsOneWidget);
    expect(tester.widget(sprigHost), isA<SakuraTitleSprigAsset>());
    expect(tester.getSize(sprigHost), SakuraTitleSprigAsset.authoredSize);
    expect(sprigImage, findsOneWidget);
    expect(find.byKey(SakuraTitleSprigAsset.failureKey), findsNothing);
    expect(
      find.ancestor(of: sprigImage, matching: find.byType(IgnorePointer)),
      findsWidgets,
    );
    expect(
      find.ancestor(of: sprigImage, matching: find.byType(ExcludeSemantics)),
      findsWidgets,
    );
    expect(
      tester.getTopRight(sprigHost).dx,
      lessThanOrEqualTo(tester.getTopLeft(find.byTooltip('Minimize')).dx),
    );
  });

  testWidgets('close waits for the pending state flush', (tester) async {
    final events = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AppTitleBar(
            beforeClose: () async {
              events.add('flush-start');
              await Future<void>.delayed(const Duration(milliseconds: 20));
              events.add('flush-end');
            },
          ),
        ),
      ),
    );

    await tester.tap(find.byTooltip('Close'));
    await tester.pump();
    expect(calls, isEmpty);
    expect(events, ['flush-start']);
    await tester.pump(const Duration(milliseconds: 20));

    expect(events, ['flush-start', 'flush-end']);
    expect(calls, ['close']);
  });

  testWidgets('close timeout leaves the window open and reports the failure', (
    tester,
  ) async {
    const timeout = Duration(milliseconds: 20);
    final errors = <Object>[];
    final never = Completer<void>();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AppTitleBar(
            windowHost: WindowHostService(closeFlushTimeout: timeout),
            beforeClose: () => never.future,
            onCloseError: errors.add,
          ),
        ),
      ),
    );

    await tester.tap(find.byTooltip('Close'));
    await tester.pump(timeout);

    expect(calls, isEmpty);
    expect(errors.single, isA<TimeoutException>());
    final closeButton = find.descendant(
      of: find.byTooltip('Close'),
      matching: find.byType(IconButton),
    );
    expect(tester.widget<IconButton>(closeButton).onPressed, isNotNull);
  });
}

Finder _glyph(String name) => find.byKey(AppTitleBar.captionGlyphKey(name));

Future<Rect> _paintedBounds(WidgetTester tester, Finder finder) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(finder);
  ui.Image? image;
  ByteData? bytes;
  await tester.runAsync(() async {
    image = await boundary.toImage(pixelRatio: 1);
    bytes = await image!.toByteData(format: ui.ImageByteFormat.rawRgba);
  });
  expect(image, isNotNull);
  expect(bytes, isNotNull);
  final rendered = image!;
  var left = rendered.width;
  var top = rendered.height;
  var right = -1;
  var bottom = -1;
  for (var y = 0; y < rendered.height; y += 1) {
    for (var x = 0; x < rendered.width; x += 1) {
      final alpha = bytes!.getUint8((y * rendered.width + x) * 4 + 3);
      if (alpha < 128) continue;
      left = x < left ? x : left;
      top = y < top ? y : top;
      right = x > right ? x : right;
      bottom = y > bottom ? y : bottom;
    }
  }
  rendered.dispose();
  expect(right, greaterThanOrEqualTo(left));
  expect(bottom, greaterThanOrEqualTo(top));
  return Rect.fromLTRB(
    left.toDouble(),
    top.toDouble(),
    (right + 1).toDouble(),
    (bottom + 1).toDouble(),
  );
}
