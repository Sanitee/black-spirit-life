import 'package:bdo_craft_planner_flutter/app/window/app_title_bar.dart';
import 'package:bdo_craft_planner_flutter/visual/foundations/theme_spec.dart';
import 'package:bdo_craft_planner_flutter/visual/illuminated_ledger/ledger_spec.dart';
import 'package:bdo_craft_planner_flutter/visual/sakura_night_garden/sakura_botanical_assets.dart';
import 'package:bdo_craft_planner_flutter/visual/sakura_night_garden/sakura_spec.dart';
import 'package:bdo_craft_planner_flutter/visual/standard/standard_spec.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('com.bdocraftplanner.flutter/window');

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'isMaximized') return false;
          return null;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  testWidgets('title destinations stay legible across themes and widths', (
    tester,
  ) async {
    const goldenRoot = ValueKey<String>('title-tab-strip-golden-root');
    tester.view
      ..physicalSize = const Size(1200, 216)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      RepaintBoundary(
        key: goldenRoot,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          home: Scaffold(
            backgroundColor: const Color(0xFF030706),
            body: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                _themedTitleBar(
                  StandardSpec.theme,
                  selectedLabel: 'Craft Planner',
                ),
                const SizedBox(height: 8),
                _themedTitleBar(
                  IlluminatedLedgerSpec.theme,
                  selectedLabel: 'Resource Map',
                ),
                const SizedBox(height: 8),
                _themedTitleBar(
                  SakuraNightGardenSpec.theme,
                  selectedLabel: 'Gathering',
                ),
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerLeft,
                  child: ThemeSpecScope(
                    spec: StandardSpec.theme,
                    child: const StandardVisualScope(
                      settings: StandardVisualSettings(
                        backgroundId: 'greenhouse',
                        accentHue: 158,
                      ),
                      child: ColoredBox(
                        color: Color(0xFF071A14),
                        child: SizedBox(
                          width: 280,
                          child: AppTitleTabStrip(
                            tabs: <AppTitleTab>[
                              AppTitleTab(
                                tabKey: ValueKey<String>('compact-planner-tab'),
                                artworkAssetPath:
                                    'packages/bdo_map_core/assets/images/node_icons/14.png',
                                inactiveArtworkAssetPath:
                                    'packages/bdo_map_core/assets/images/node_icons/gray/14.png',
                                label: 'Craft Planner',
                                selected: false,
                                onPressed: _noop,
                              ),
                              AppTitleTab(
                                tabKey: ValueKey<String>('compact-map-tab'),
                                artworkAssetPath:
                                    'packages/bdo_map_core/assets/images/node_icons/0.png',
                                inactiveArtworkAssetPath:
                                    'packages/bdo_map_core/assets/images/node_icons/gray/0.png',
                                artworkScale: 1.16,
                                label: 'Resource Map',
                                selected: false,
                                onPressed: _noop,
                              ),
                              AppTitleTab(
                                tabKey: ValueKey<String>(
                                  'compact-gathering-tab',
                                ),
                                artworkAssetPath:
                                    'packages/bdo_map_core/assets/images/node_icons/6.png',
                                inactiveArtworkAssetPath:
                                    'packages/bdo_map_core/assets/images/node_icons/gray/6.png',
                                label: 'Gathering',
                                selected: false,
                                onPressed: _noop,
                              ),
                              AppTitleTab(
                                tabKey: ValueKey<String>(
                                  'compact-fish-map-tab',
                                ),
                                artworkAssetPath:
                                    'packages/bdo_map_core/assets/images/node_icons/11.png',
                                inactiveArtworkAssetPath:
                                    'packages/bdo_map_core/assets/images/node_icons/gray/11.png',
                                artworkScale: 1.38,
                                label: 'Fish Map',
                                selected: true,
                                onPressed: _noop,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    final context = tester.element(find.byType(Scaffold).first);
    for (final assetPath in const <String>[
      'packages/bdo_map_core/assets/images/node_icons/14.png',
      'packages/bdo_map_core/assets/images/node_icons/gray/14.png',
      'packages/bdo_map_core/assets/images/node_icons/0.png',
      'packages/bdo_map_core/assets/images/node_icons/gray/0.png',
      'packages/bdo_map_core/assets/images/node_icons/6.png',
      'packages/bdo_map_core/assets/images/node_icons/gray/6.png',
      'packages/bdo_map_core/assets/images/node_icons/11.png',
      'packages/bdo_map_core/assets/images/node_icons/gray/11.png',
    ]) {
      await tester.runAsync(
        () => precacheImage(AssetImage(assetPath), context),
      );
    }
    for (final assetPath in const <String>[
      SakuraNightGardenSpec.blackenedCedarAssetPath,
      SakuraBotanicalAssets.titleSprig,
    ]) {
      await tester.runAsync(
        () => precacheImage(AssetImage(assetPath), context),
      );
    }
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    await expectLater(
      find.byKey(goldenRoot),
      matchesGoldenFile('title_tab_strip_responsive.png'),
    );
  });
}

Widget _themedTitleBar(ThemeSpec spec, {required String selectedLabel}) {
  final titleBar = AppTitleBar(
    workspaceNavigation: AppTitleTabStrip(
      tabs: <AppTitleTab>[
        AppTitleTab(
          tabKey: ValueKey<String>('${spec.id}-planner-tab'),
          artworkAssetPath:
              'packages/bdo_map_core/assets/images/node_icons/14.png',
          inactiveArtworkAssetPath:
              'packages/bdo_map_core/assets/images/node_icons/gray/14.png',
          label: 'Craft Planner',
          selected: selectedLabel == 'Craft Planner',
          onPressed: _noop,
        ),
        AppTitleTab(
          tabKey: ValueKey<String>('${spec.id}-map-tab'),
          artworkAssetPath:
              'packages/bdo_map_core/assets/images/node_icons/0.png',
          inactiveArtworkAssetPath:
              'packages/bdo_map_core/assets/images/node_icons/gray/0.png',
          artworkScale: 1.16,
          label: 'Resource Map',
          selected: selectedLabel == 'Resource Map',
          onPressed: _noop,
        ),
        AppTitleTab(
          tabKey: ValueKey<String>('${spec.id}-gathering-tab'),
          artworkAssetPath:
              'packages/bdo_map_core/assets/images/node_icons/6.png',
          inactiveArtworkAssetPath:
              'packages/bdo_map_core/assets/images/node_icons/gray/6.png',
          label: 'Gathering',
          selected: selectedLabel == 'Gathering',
          onPressed: _noop,
        ),
        AppTitleTab(
          tabKey: ValueKey<String>('${spec.id}-fish-map-tab'),
          artworkAssetPath:
              'packages/bdo_map_core/assets/images/node_icons/11.png',
          inactiveArtworkAssetPath:
              'packages/bdo_map_core/assets/images/node_icons/gray/11.png',
          artworkScale: 1.38,
          label: 'Fish Map',
          selected: selectedLabel == 'Fish Map',
          onPressed: _noop,
        ),
      ],
    ),
  );
  return ThemeSpecScope(
    spec: spec,
    child: StandardVisualScope(
      settings: const StandardVisualSettings(
        backgroundId: 'greenhouse',
        accentHue: 158,
      ),
      child: Theme(data: spec.materialTheme(), child: titleBar),
    ),
  );
}

void _noop() {}
