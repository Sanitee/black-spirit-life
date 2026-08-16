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
                _themedTitleBar(StandardSpec.theme, mapSelected: false),
                const SizedBox(height: 8),
                _themedTitleBar(IlluminatedLedgerSpec.theme, mapSelected: true),
                const SizedBox(height: 8),
                _themedTitleBar(SakuraNightGardenSpec.theme, mapSelected: true),
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
                                    'assets/app/bdo_tool_icon.png',
                                label: 'Craft Planner',
                                selected: false,
                                onPressed: _noop,
                              ),
                              AppTitleTab(
                                tabKey: ValueKey<String>('compact-map-tab'),
                                artworkAssetPath:
                                    'assets/app/bdo_resource_map_icon.png',
                                label: 'Resource Map',
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
      'assets/app/bdo_tool_icon.png',
      'assets/app/bdo_resource_map_icon.png',
    ]) {
      await tester.runAsync(
        () => precacheImage(
          ResizeImage(
            AssetImage(assetPath),
            width: (AppTitleTabStrip.artworkSize * 3).round(),
            height: (AppTitleTabStrip.artworkSize * 3).round(),
          ),
          context,
        ),
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

Widget _themedTitleBar(ThemeSpec spec, {required bool mapSelected}) {
  final titleBar = AppTitleBar(
    workspaceNavigation: AppTitleTabStrip(
      tabs: <AppTitleTab>[
        AppTitleTab(
          tabKey: ValueKey<String>('${spec.id}-planner-tab'),
          artworkAssetPath: 'assets/app/bdo_tool_icon.png',
          label: 'Craft Planner',
          selected: !mapSelected,
          onPressed: _noop,
        ),
        AppTitleTab(
          tabKey: ValueKey<String>('${spec.id}-map-tab'),
          artworkAssetPath: 'assets/app/bdo_resource_map_icon.png',
          label: 'Resource Map',
          selected: mapSelected,
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
