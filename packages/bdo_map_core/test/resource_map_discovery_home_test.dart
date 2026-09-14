import 'package:bdo_map_core/src/widgets/resource_map_chrome_theme.dart';
import 'package:bdo_map_core/src/widgets/resource_map_discovery_home.dart';
import 'package:bdo_map_core/src/widgets/resource_map_menu_artwork.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final skin in <String, ResourceMapChromeThemeData>{
    'glass': ResourceMapChromeThemeData.glassDock,
    'atlas': ResourceMapChromeThemeData.fieldAtlas,
  }.entries) {
    for (final width in <double>[280, 420, 700]) {
      for (final scale in <double>[1, 2]) {
        testWidgets('${skin.key} home wraps at $width px and ${scale}x text', (
          tester,
        ) async {
          final calls = <String, int>{};
          await _pumpHome(
            tester,
            calls: calls,
            width: width,
            scale: scale,
            chrome: skin.value,
          );

          expect(find.text('Materials'), findsOneWidget);
          expect(find.text('Income'), findsOneWidget);
          expect(find.text('Houses'), findsOneWidget);
          expect(find.text('Gather it yourself or use workers'), findsNothing);
          expect(find.text('Find nodes worth connecting'), findsNothing);
          expect(find.text('Plan materials'), findsNothing);
          expect(
            tester
                .widget<TextButton>(_action('more-tools'))
                .style!
                .textStyle!
                .resolve({})!
                .fontFamily,
            skin.value.headingFontFamily,
          );
          expect(find.byType(Scrollbar), findsNothing);
          expect(find.byType(RawScrollbar), findsNothing);
          expect(tester.takeException(), isNull);
          final home = tester.getRect(find.byType(ResourceMapDiscoveryHome));
          expect(home.width, width);
          expect(home.height.isFinite, isTrue);
          if (width == 420 && scale == 1) {
            expect(home.height, lessThanOrEqualTo(320));
          }
          for (final artwork in tester.widgetList<ResourceMapMenuArtwork>(
            find.byType(ResourceMapMenuArtwork),
          )) {
            expect(artwork.size, 30);
          }
          for (final id in ['find-material', 'worker-income', 'houses']) {
            final action = _action(id);
            expect(tester.getSize(action).height, greaterThanOrEqualTo(40));
            if (scale == 1 && width >= 420) {
              expect(tester.getSize(action).height, lessThanOrEqualTo(52));
            }
            expect(
              tester.getRect(action).left,
              greaterThanOrEqualTo(home.left),
            );
            expect(tester.getRect(action).right, lessThanOrEqualTo(home.right));
          }

          await tester.ensureVisible(_action('more-tools'));
          await tester.tap(_action('more-tools'));
          await tester.pumpAndSettle();
          for (final id in ['plan-materials', 'browse-nodes', 'setup']) {
            await tester.ensureVisible(_action(id));
            await tester.tap(_action(id));
            expect(calls[id], 1);
          }
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          expect(tester.binding.hasScheduledFrame, isFalse);
        });
      }
    }
  }

  testWidgets('each visible task calls only its host action', (tester) async {
    final calls = <String, int>{};
    await _pumpHome(tester, calls: calls);
    for (final id in [
      'find-material',
      'worker-income',
      'houses',
      'saved',
      'todo',
    ]) {
      await tester.tap(_action(id));
      expect(calls[id], 1);
      expect(
        calls.values.fold<int>(0, (sum, value) => sum + value),
        calls.length,
      );
    }
    expect(
      calls.keys,
      unorderedEquals([
        'find-material',
        'worker-income',
        'houses',
        'saved',
        'todo',
      ]),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('Houses is optional and more tools collapse out of the tree', (
    tester,
  ) async {
    await _pumpHome(tester, calls: {}, houses: false);
    expect(_action('houses'), findsNothing);
    expect(find.text('Storage, lodging and workshops'), findsNothing);
    expect(_action('plan-materials'), findsNothing);
    await tester.tap(_action('more-tools'));
    await tester.pumpAndSettle();
    expect(_action('plan-materials'), findsOneWidget);
    expect(_action('browse-nodes'), findsOneWidget);
    expect(_action('setup'), findsOneWidget);
    await tester.tap(_action('more-tools'));
    await tester.pumpAndSettle();
    expect(_action('plan-materials'), findsNothing);
    expect(_action('browse-nodes'), findsNothing);
    expect(_action('setup'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('primary tasks support keyboard focus and activation', (
    tester,
  ) async {
    final calls = <String, int>{};
    await _pumpHome(tester, calls: calls);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    expect(calls, {'find-material': 1});
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    expect(calls, {'find-material': 1, 'worker-income': 1});
    expect(tester.takeException(), isNull);
  });

  testWidgets('planner needs appears only when the host supplies that action', (
    tester,
  ) async {
    final calls = <String, int>{};
    await _pumpHome(tester, calls: calls);
    await tester.tap(_action('more-tools'));
    await tester.pumpAndSettle();
    expect(_action('plan-needs'), findsNothing);

    await _pumpHome(tester, calls: calls, plannerNeeds: true);
    expect(_action('plan-needs'), findsOneWidget);
    await tester.ensureVisible(_action('plan-needs'));
    await tester.tap(_action('plan-needs'));
    expect(calls, {'plan-needs': 1});
    expect(tester.takeException(), isNull);
  });

  testWidgets('disclosure motion respects reduced motion', (tester) async {
    await _pumpHome(tester, calls: {}, disableAnimations: false);
    await tester.tap(_action('more-tools'));
    await tester.pump();
    expect(tester.binding.hasScheduledFrame, isTrue);
    await tester.pumpAndSettle();
    expect(_action('setup'), findsOneWidget);

    await _pumpHome(tester, calls: {}, disableAnimations: true);
    await tester.tap(_action('more-tools'));
    await tester.pump();
    expect(find.byType(AnimatedSize), findsNothing);
    expect(find.byType(AnimatedRotation), findsNothing);
    expect(_action('plan-materials'), findsNothing);
    await tester.pumpAndSettle();
    expect(tester.binding.hasScheduledFrame, isFalse);
    expect(tester.takeException(), isNull);
  });
}

Finder _action(String id) => find.byKey(
  ValueKey('resource-map-home-${id == 'todo' ? 'checklist' : id}'),
);

Future<void> _pumpHome(
  WidgetTester tester, {
  required Map<String, int> calls,
  double width = 420,
  double scale = 1,
  bool houses = true,
  bool plannerNeeds = false,
  bool disableAnimations = true,
  ResourceMapChromeThemeData chrome = ResourceMapChromeThemeData.glassDock,
}) async {
  tester.view.physicalSize = Size(width + 32, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  void press(String id) =>
      calls.update(id, (count) => count + 1, ifAbsent: () => 1);
  await tester.pumpWidget(
    MaterialApp(
      home: ResourceMapChromeTheme(
        data: chrome,
        child: MediaQuery(
          data: MediaQueryData(
            size: Size(width + 32, 900),
            textScaler: TextScaler.linear(scale),
            disableAnimations: disableAnimations,
          ),
          child: Scaffold(
            body: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: SizedBox(
                width: width,
                child: ResourceMapDiscoveryHome(
                  onFindMaterial: () => press('find-material'),
                  onWorkerIncome: () => press('worker-income'),
                  onHouses: houses ? () => press('houses') : null,
                  onSaved: () => press('saved'),
                  onTodoList: () => press('todo'),
                  onPlanMaterials: () => press('plan-materials'),
                  onBrowseWorkerNodes: () => press('browse-nodes'),
                  onSetup: () => press('setup'),
                  onPlannerNeeds: plannerNeeds
                      ? () => press('plan-needs')
                      : null,
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}
