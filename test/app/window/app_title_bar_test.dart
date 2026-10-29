import 'dart:async';
import 'dart:ui' as ui;

import 'package:bdo_craft_planner_flutter/app/window/app_title_bar.dart';
import 'package:bdo_craft_planner_flutter/app/window/app_title_bar_visual.dart';
import 'package:bdo_craft_planner_flutter/app/window/window_host_service.dart';
import 'package:bdo_craft_planner_flutter/app_identity.dart';
import 'package:bdo_craft_planner_flutter/visual/foundations/theme_spec.dart';
import 'package:bdo_craft_planner_flutter/visual/illuminated_ledger/ledger_spec.dart';
import 'package:bdo_craft_planner_flutter/visual/sakura_night_garden/sakura_botanical_assets.dart';
import 'package:bdo_craft_planner_flutter/visual/sakura_night_garden/sakura_spec.dart';
import 'package:bdo_craft_planner_flutter/visual/standard/standard_spec.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/action_hint_finder.dart';

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

  testWidgets('field desk exposes labels without changing Planner strip', (
    tester,
  ) async {
    const names = [
      'Planner',
      'Opportunities',
      'Resource Map',
      'Gathering',
      'Fish Map',
    ];
    Future<void> show({required bool fieldDesk, required double width}) async {
      await tester.binding.setSurfaceSize(Size(width, 200));
      Widget strip = AppTitleTabStrip(
        tabs: [
          for (final name in names)
            AppTitleTab(
              tabKey: ValueKey('codex-navigation-$name'),
              label: name,
              selected: name == (fieldDesk ? 'Gathering' : 'Planner'),
              icon: Icons.map_outlined,
              onPressed: () {},
            ),
        ],
      );
      if (fieldDesk) {
        strip = AppTitleBarVisualScope(
          visual: AppTitleBarVisual.gathering,
          child: strip,
        );
      }
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: strip)));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    }

    addTearDown(() => tester.binding.setSurfaceSize(null));
    await show(fieldDesk: true, width: 1200);
    for (final name in names) {
      expect(find.text(name), findsOneWidget);
    }
    await show(fieldDesk: false, width: 1200);
    expect(find.text('Planner'), findsOneWidget);
    expect(find.text('Gathering'), findsNothing);
    await show(fieldDesk: true, width: 330);
    expect(find.text('Gathering'), findsNothing);
    for (final name in names) {
      expect(findActionHint(name), findsOneWidget);
    }
  });

  testWidgets('Codex tab labels stay expanded under every Appearance theme', (
    tester,
  ) async {
    const names = [
      'Planner',
      'Opportunities',
      'Resource Map',
      'Gathering',
      'Fish Map',
    ];
    await tester.binding.setSurfaceSize(const Size(1400, 200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    for (final spec in const [
      SakuraNightGardenSpec.theme,
      IlluminatedLedgerSpec.theme,
      StandardSpec.theme,
    ]) {
      await tester.pumpWidget(
        MaterialApp(
          theme: spec.materialTheme(),
          home: ThemeSpecScope(
            spec: spec,
            child: Scaffold(
              body: AppTitleTabStrip(
                showAllLabels: true,
                tabs: [
                  for (final name in names)
                    AppTitleTab(
                      tabKey: ValueKey('shared-theme-$name'),
                      label: name,
                      selected: name == 'Gathering',
                      icon: Icons.map_outlined,
                      onPressed: () {},
                    ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      for (final name in names) {
        expect(find.text(name), findsOneWidget);
      }
      expect(tester.takeException(), isNull);
    }
  });

  for (final entry in [
    (name: 'sakura', spec: SakuraNightGardenSpec.theme, visual: null),
    (name: 'ledger', spec: IlluminatedLedgerSpec.theme, visual: null),
    (name: 'standard', spec: StandardSpec.theme, visual: null),
    (
      name: 'opportunities',
      spec: StandardSpec.theme,
      visual: AppTitleBarVisual.opportunities,
    ),
  ]) {
    testWidgets('return arrow fits and follows ${entry.name} title colours', (
      tester,
    ) async {
      var visible = false;
      var returns = 0;
      late StateSetter update;
      Widget host() => MaterialApp(
        home: ThemeSpecScope(
          spec: entry.spec,
          child: MediaQuery(
            data: const MediaQueryData(
              disableAnimations: true,
              textScaler: TextScaler.linear(2),
            ),
            child: Scaffold(
              body: Align(
                alignment: Alignment.topLeft,
                child: SizedBox(
                  width: 620,
                  child: StatefulBuilder(
                    builder: (context, setState) {
                      update = setState;
                      final title = AppTitleBar(
                        workspaceNavigation: AppTitleTabStrip(
                          returnLabel: visible ? 'Back to Planner' : null,
                          onReturn: visible ? () => returns++ : null,
                          tabs: [
                            for (final name in [
                              'Planner',
                              'Opportunities',
                              'Resource Map',
                              'Gathering',
                              'Fish Map',
                            ])
                              AppTitleTab(
                                tabKey: ValueKey('return-test-$name'),
                                icon: Icons.map_outlined,
                                label: name,
                                selected: name == 'Resource Map',
                                onPressed: () => update(() => visible = false),
                              ),
                          ],
                        ),
                      );
                      return entry.visual == null
                          ? title
                          : AppTitleBarVisualScope(
                              visual: entry.visual!,
                              child: title,
                            );
                    },
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpWidget(host());
      final arrow = find.byKey(AppTitleTabStrip.returnButtonKey);
      final first = find.byKey(const ValueKey('return-test-Planner'));
      final originalX = tester.getTopLeft(first).dx;
      expect(arrow, findsNothing);
      update(() => visible = true);
      await tester.pump();
      expect(tester.getSize(arrow), const Size(40, 40));
      expect(tester.getTopLeft(first).dx, originalX + 40);
      expect(
        tester.getTopRight(arrow).dx,
        lessThanOrEqualTo(tester.getTopLeft(first).dx),
      );
      final button = tester.widget<IconButton>(arrow);
      final colour = button.style!.foregroundColor!.resolve({})!;
      expect(colour.computeLuminance(), greaterThan(.4));
      if (entry.visual != null) {
        expect(colour, entry.visual!.tabSelectedForeground);
      }
      expect(findActionHint('Back to Planner'), findsOneWidget);
      await tester.tap(arrow);
      expect(returns, 1);
      expect(calls, isEmpty);
      for (final name in [
        'Planner',
        'Opportunities',
        'Resource Map',
        'Gathering',
        'Fish Map',
      ]) {
        expect(
          find.byKey(ValueKey('return-test-$name')).hitTestable(),
          findsOneWidget,
        );
      }
      expect(
        tester.getTopRight(findActionHint('Close')).dx,
        lessThanOrEqualTo(620),
      );
      await tester.tap(first);
      await tester.pump();
      expect(arrow, findsNothing);
      expect(tester.getTopLeft(first).dx, originalX);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'return arrow animates into space but stops accepting input immediately on hide',
    (tester) async {
      var visible = false;
      late StateSetter update;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AppTitleBar(
              workspaceNavigation: StatefulBuilder(
                builder: (context, setState) {
                  update = setState;
                  return AppTitleTabStrip(
                    returnLabel: visible ? 'Back to Opportunities' : null,
                    onReturn: visible
                        ? () => update(() => visible = false)
                        : null,
                    tabs: [
                      AppTitleTab(
                        tabKey: const ValueKey('animated-return-planner'),
                        label: 'Planner',
                        icon: Icons.calculate_outlined,
                        selected: true,
                        onPressed: () => update(() => visible = true),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      );
      final first = find.byKey(const ValueKey('animated-return-planner'));
      final initialX = tester.getTopLeft(first).dx;
      update(() => visible = true);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 40));
      expect(
        tester.getTopLeft(first).dx,
        inExclusiveRange(initialX, initialX + 40),
      );
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(first).dx, initialX + 40);
      await tester.tap(find.byKey(AppTitleTabStrip.returnButtonKey));
      await tester.pump();
      expect(find.byKey(AppTitleTabStrip.returnButtonKey), findsNothing);
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(first).dx, initialX);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('caption controls invoke distinct native operations', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: AppTitleBar())),
    );

    await tester.tap(findActionHint('Minimize'));
    await tester.tap(findActionHint('Maximize or restore'));
    await tester.tap(findActionHint('Close'));
    await tester.pump();

    expect(calls, ['minimize', 'toggleMaximize', 'requestClose']);
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
    expect(findActionHint('Minimize'), findsOneWidget);
    expect(findActionHint('Maximize or restore'), findsOneWidget);
    expect(findActionHint('Close'), findsOneWidget);
    expect(
      tester.getTopLeft(find.byKey(trailingKey)).dx,
      lessThan(tester.getTopLeft(findActionHint('Minimize')).dx),
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

  testWidgets('active application tab expands while three peers stay compact', (
    tester,
  ) async {
    var selectedTab = 0;
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
                        selected: selectedTab == 0,
                        onPressed: () => updateTabs(() => selectedTab = 0),
                      ),
                      AppTitleTab(
                        tabKey: const ValueKey<String>('map-tab'),
                        icon: Icons.travel_explore_outlined,
                        label: 'Resource Map',
                        selected: selectedTab == 1,
                        onPressed: () => updateTabs(() => selectedTab = 1),
                      ),
                      AppTitleTab(
                        tabKey: const ValueKey<String>('gathering-tab'),
                        icon: Icons.grass_rounded,
                        label: 'Gathering',
                        selected: selectedTab == 2,
                        onPressed: () => updateTabs(() => selectedTab = 2),
                      ),
                      AppTitleTab(
                        tabKey: const ValueKey<String>('fish-map-tab'),
                        icon: Icons.set_meal_rounded,
                        label: 'Fish Map',
                        selected: selectedTab == 3,
                        onPressed: () => updateTabs(() => selectedTab = 3),
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
    final gatheringSurface = find.byKey(
      AppTitleTabStrip.surfaceKey('Gathering'),
    );
    final fishMapSurface = find.byKey(AppTitleTabStrip.surfaceKey('Fish Map'));
    final plannerExpandedWidth = tester.getSize(plannerSurface).width;
    expect(plannerExpandedWidth, greaterThan(100));
    expect(tester.getSize(mapSurface).width, 52);
    expect(tester.getSize(gatheringSurface).width, 52);
    expect(tester.getSize(fishMapSurface).width, 52);
    expect(
      find.descendant(of: plannerSurface, matching: find.text('Craft Planner')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: mapSurface, matching: find.text('Resource Map')),
      findsNothing,
    );
    expect(
      find.descendant(of: gatheringSurface, matching: find.text('Gathering')),
      findsNothing,
    );
    expect(
      find.descendant(of: fishMapSurface, matching: find.text('Fish Map')),
      findsNothing,
    );
    final plannerDecoration =
        tester.widget<AnimatedContainer>(plannerSurface).decoration!
            as BoxDecoration;
    expect(plannerDecoration.color, isNotNull);
    expect(plannerDecoration.gradient, isNull);
    expect(plannerDecoration.boxShadow, isNull);
    expect(plannerDecoration.border, isNotNull);

    await tester.tap(fishMapSurface);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 45));

    expect(
      tester.getSize(plannerSurface).width,
      inExclusiveRange(52, plannerExpandedWidth),
    );
    expect(tester.getSize(fishMapSurface).width, greaterThan(52));

    await tester.pumpAndSettle();

    expect(tester.getSize(plannerSurface).width, 52);
    expect(tester.getSize(mapSurface).width, 52);
    expect(tester.getSize(gatheringSurface).width, 52);
    expect(tester.getSize(fishMapSurface).width, greaterThan(100));
    expect(
      find.descendant(of: plannerSurface, matching: find.text('Craft Planner')),
      findsNothing,
    );
    expect(
      find.descendant(of: fishMapSurface, matching: find.text('Fish Map')),
      findsOneWidget,
    );
    final mapDecoration =
        tester.widget<AnimatedContainer>(fishMapSurface).decoration!
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
        'Craft Planner':
            'packages/bdo_map_core/assets/images/node_icons/14.png',
        'Resource Map': 'packages/bdo_map_core/assets/images/node_icons/0.png',
        'Gathering': 'packages/bdo_map_core/assets/images/node_icons/6.png',
        'Fish Map':
            'packages/bdo_fishing_core/assets/fish_companion/static/fishystuff.png',
      };
      const inactiveArtwork = <String, String>{
        'Craft Planner':
            'packages/bdo_map_core/assets/images/node_icons/gray/14.png',
        'Resource Map':
            'packages/bdo_map_core/assets/images/node_icons/gray/0.png',
        'Gathering':
            'packages/bdo_map_core/assets/images/node_icons/gray/6.png',
        'Fish Map':
            'packages/bdo_fishing_core/assets/fish_companion/static/fishystuff.png',
      };
      const artworkScale = <String, double>{
        'Craft Planner': 1,
        'Resource Map': 1.16,
        'Gathering': 1,
        'Fish Map': 1,
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
                    inactiveArtworkAssetPath: inactiveArtwork['Craft Planner'],
                    artworkScale: artworkScale['Craft Planner']!,
                    label: 'Craft Planner',
                    selected: true,
                    onPressed: () {},
                  ),
                  AppTitleTab(
                    tabKey: const ValueKey<String>('map-tab'),
                    artworkAssetPath: artwork['Resource Map'],
                    inactiveArtworkAssetPath: inactiveArtwork['Resource Map'],
                    artworkScale: artworkScale['Resource Map']!,
                    label: 'Resource Map',
                    selected: false,
                    onPressed: () {},
                  ),
                  AppTitleTab(
                    tabKey: const ValueKey<String>('gathering-tab'),
                    artworkAssetPath: artwork['Gathering'],
                    inactiveArtworkAssetPath: inactiveArtwork['Gathering'],
                    artworkScale: artworkScale['Gathering']!,
                    label: 'Gathering',
                    selected: false,
                    onPressed: () {},
                  ),
                  AppTitleTab(
                    tabKey: const ValueKey<String>('fish-map-tab'),
                    artworkAssetPath: artwork['Fish Map'],
                    inactiveArtworkAssetPath: inactiveArtwork['Fish Map'],
                    artworkScale: artworkScale['Fish Map']!,
                    label: 'Fish Map',
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
          reason: entry.key,
        );
        final image = tester.widget<Image>(
          find.descendant(of: artworkFinder, matching: find.byType(Image)),
        );
        expect(image.fit, BoxFit.contain);
        expect(image.filterQuality, FilterQuality.high);
        expect(image.isAntiAlias, isTrue);
        expect(image.gaplessPlayback, isTrue);
        expect(image.image, isA<ResizeImage>());
        final resized = image.image as ResizeImage;
        final expectedRasterSize =
            (AppTitleTabStrip.artworkSize * 3 * artworkScale[entry.key]!)
                .ceil();
        expect(resized.width, expectedRasterSize);
        expect(resized.height, expectedRasterSize);
        expect(resized.imageProvider, isA<AssetImage>());
        expect(
          (resized.imageProvider as AssetImage).assetName,
          entry.key == 'Craft Planner'
              ? entry.value
              : inactiveArtwork[entry.key],
        );
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
        final expectedRasterSize =
            (AppTitleTabStrip.artworkSize * 3 * artworkScale[label]!).ceil();
        expect(
          resized.width,
          expectedRasterSize,
          reason: '$label at 300% display scale',
        );
        expect(
          resized.height,
          expectedRasterSize,
          reason: '$label at 300% display scale',
        );
      }
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('workspace destinations use square in-game node markers', (
    tester,
  ) async {
    for (final path in const <String>[
      'packages/bdo_map_core/assets/images/node_icons/14.png',
      'packages/bdo_map_core/assets/images/node_icons/gray/14.png',
      'packages/bdo_map_core/assets/images/node_icons/0.png',
      'packages/bdo_map_core/assets/images/node_icons/gray/0.png',
      'packages/bdo_map_core/assets/images/node_icons/6.png',
      'packages/bdo_map_core/assets/images/node_icons/gray/6.png',
      'packages/bdo_map_core/assets/images/node_icons/11.png',
      'packages/bdo_map_core/assets/images/node_icons/gray/11.png',
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
      expect(frame!.image.width, 256, reason: path);
      expect(frame!.image.height, 256, reason: path);
      frame!.image.dispose();
      codec!.dispose();
    }
  });

  test('tab artwork remains the exact reviewed in-game marker files', () async {
    const expected = <String, ({int bytes, String sha256})>{
      'packages/bdo_map_core/assets/images/node_icons/14.png': (
        bytes: 18406,
        sha256:
            'e89ec2c3d7dee37550982c4a734660915e057054a2500d43c309475076e814a3',
      ),
      'packages/bdo_map_core/assets/images/node_icons/gray/14.png': (
        bytes: 18075,
        sha256:
            '4cf0922df806ebf625a23ed76de7f6040895649f7fc4c4c1a5cbf6d70f40c062',
      ),
      'packages/bdo_map_core/assets/images/node_icons/0.png': (
        bytes: 8643,
        sha256:
            '215517d2f96177950f9980d91c8d34a98c8c974db158e5d985d38a7dc5e6e7a9',
      ),
      'packages/bdo_map_core/assets/images/node_icons/gray/0.png': (
        bytes: 8391,
        sha256:
            '01a7835579e9738d3343638be28710f77680c1265803117b142ae47c29c074f7',
      ),
      'packages/bdo_map_core/assets/images/node_icons/6.png': (
        bytes: 19277,
        sha256:
            'a50586869e2acf02776c2e49e7c9553b24355952089ee75811a4598f9d73b929',
      ),
      'packages/bdo_map_core/assets/images/node_icons/gray/6.png': (
        bytes: 18581,
        sha256:
            '66d6d3706d5141834cad4ca6375201f74aadd2283c370587ec65409dca63c3bb',
      ),
      'packages/bdo_map_core/assets/images/node_icons/11.png': (
        bytes: 10672,
        sha256:
            'e008dcb5b6e53c34eec6d0d1ab98c60e1fb5904ade41e5139ae14f9a573ed205',
      ),
      'packages/bdo_map_core/assets/images/node_icons/gray/11.png': (
        bytes: 10451,
        sha256:
            '6d98c2798d65f659b52f766172eb57ebfed69dd309f4a25d37e6e3c0bf41c031',
      ),
    };
    for (final entry in expected.entries) {
      final data = await rootBundle.load(entry.key);
      final bytes = data.buffer.asUint8List(
        data.offsetInBytes,
        data.lengthInBytes,
      );
      expect(bytes.length, entry.value.bytes, reason: entry.key);
      expect(sha256.convert(bytes).toString(), entry.value.sha256);
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
                        AppTitleTab(
                          tabKey: const ValueKey<String>('gathering-tab'),
                          icon: Icons.grass_rounded,
                          label: 'Gathering',
                          selected: false,
                          onPressed: () {},
                        ),
                        AppTitleTab(
                          tabKey: const ValueKey<String>('fish-map-tab'),
                          icon: Icons.set_meal_rounded,
                          label: 'Fish Map',
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
      expect(find.text('Gathering'), findsNothing);
      expect(find.text('Fish Map'), findsNothing);
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
      expect(
        tester
            .getSize(find.byKey(AppTitleTabStrip.surfaceKey('Gathering')))
            .height,
        40,
      );
      expect(
        tester
            .getSize(find.byKey(AppTitleTabStrip.surfaceKey('Fish Map')))
            .height,
        40,
      );
      expect(tester.takeException(), isNull, reason: '${spec.family}');
    }
  });

  testWidgets(
    '600 logical pixels at 200% text keeps four tabs and captions reachable',
    (tester) async {
      tester.view
        ..physicalSize = const Size(600, 200)
        ..devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.view.reset);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final activated = <String>[];

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
                        onPressed: () => activated.add('Craft Planner'),
                      ),
                      AppTitleTab(
                        tabKey: const ValueKey<String>('map-tab'),
                        icon: Icons.travel_explore_outlined,
                        label: 'Resource Map',
                        selected: true,
                        onPressed: () => activated.add('Resource Map'),
                      ),
                      AppTitleTab(
                        tabKey: const ValueKey<String>('gathering-tab'),
                        icon: Icons.grass_rounded,
                        label: 'Gathering',
                        selected: false,
                        onPressed: () => activated.add('Gathering'),
                      ),
                      AppTitleTab(
                        tabKey: const ValueKey<String>('fish-map-tab'),
                        icon: Icons.set_meal_rounded,
                        label: 'Fish Map',
                        selected: false,
                        onPressed: () => activated.add('Fish Map'),
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
      final gathering = find.byKey(AppTitleTabStrip.surfaceKey('Gathering'));
      final fishMap = find.byKey(AppTitleTabStrip.surfaceKey('Fish Map'));
      final titleRect = tester.getRect(find.byKey(AppTitleBar.materialKey));

      for (final tab in <Finder>[planner, map, gathering, fishMap]) {
        expect(tab, findsOneWidget);
        expect(tab.hitTestable(), findsOneWidget);
        expect(tester.getSize(tab), const Size(52, 40));
      }
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
      for (final entry in const <String, String>{
        'planner-tab': 'Craft Planner',
        'map-tab': 'Resource Map',
        'gathering-tab': 'Gathering',
        'fish-map-tab': 'Fish Map',
      }.entries) {
        expect(
          tester
              .widget<Semantics>(find.byKey(ValueKey<String>(entry.key)))
              .properties
              .label,
          entry.value,
        );
      }

      for (final tooltip in const <String>[
        'Minimize',
        'Maximize or restore',
        'Close',
      ]) {
        final caption = findActionHint(tooltip);
        expect(caption, findsOneWidget);
        final captionRect = tester.getRect(caption);
        expect(captionRect.left, greaterThanOrEqualTo(titleRect.left));
        expect(captionRect.right, lessThanOrEqualTo(titleRect.right));
        expect(captionRect.top, greaterThanOrEqualTo(titleRect.top));
        expect(captionRect.bottom, lessThanOrEqualTo(titleRect.bottom));
      }

      for (final tab in <Finder>[planner, map, gathering, fishMap]) {
        await tester.tap(tab);
        await tester.pump();
      }
      expect(activated, <String>[
        'Craft Planner',
        'Resource Map',
        'Gathering',
        'Fish Map',
      ]);
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
                    AppTitleTab(
                      tabKey: const ValueKey<String>('gathering-tab'),
                      icon: Icons.grass_rounded,
                      label: 'Gathering',
                      selected: false,
                      onPressed: () {},
                    ),
                    AppTitleTab(
                      tabKey: const ValueKey<String>('fish-map-tab'),
                      icon: Icons.set_meal_rounded,
                      label: 'Fish Map',
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
          .getRect(find.byKey(AppTitleTabStrip.surfaceKey('Fish Map')))
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
    await tester.tap(findActionHint('Maximize or restore'));
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
        of: findActionHint(entry.value),
        matching: find.byWidgetPredicate((widget) => widget is IconButton),
        matchRoot: true,
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

    await tester.tap(findActionHint('Maximize or restore'));
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
      of: findActionHint('Minimize'),
      matching: find.byWidgetPredicate((widget) => widget is IconButton),
      matchRoot: true,
    );
    expect(tester.getSize(minimize), const Size(52, 40));
    expect(tester.getSize(_glyph('minimize')), const Size.square(18));
    final close = find.descendant(
      of: findActionHint('Close'),
      matching: find.byWidgetPredicate((widget) => widget is IconButton),
      matchRoot: true,
    );
    expect(tester.getSize(close), const Size(52, 40));
    expect(tester.getSize(_glyph('close')), const Size.square(18));
    final maximize = find.descendant(
      of: findActionHint('Maximize or restore'),
      matching: find.byWidgetPredicate((widget) => widget is IconButton),
      matchRoot: true,
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
      of: findActionHint('Minimize'),
      matching: find.byWidgetPredicate((widget) => widget is IconButton),
      matchRoot: true,
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
      lessThanOrEqualTo(tester.getTopLeft(findActionHint('Minimize')).dx),
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

    await tester.tap(findActionHint('Close'));
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

    await tester.tap(findActionHint('Close'));
    await tester.pump(timeout);

    expect(calls, isEmpty);
    expect(errors.single, isA<TimeoutException>());
    final closeButton = find.descendant(
      of: findActionHint('Close'),
      matching: find.byWidgetPredicate((widget) => widget is IconButton),
      matchRoot: true,
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
