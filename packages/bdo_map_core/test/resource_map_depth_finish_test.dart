import 'package:bdo_map_core/src/widgets/resource_map_atlas_shell.dart';
import 'package:bdo_map_core/src/widgets/resource_map_chrome_theme.dart';
import 'package:bdo_map_core/src/widgets/resource_map_pill.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/map_menu_capture.dart';

const _capture = ValueKey('map-depth-capture');
const _pill = ValueKey('map-depth-pill');

// Semantic roles supplied by the app's Light Ledger appearance. The map
// package remains independent of the embedding application's theme classes.
final _lightLedger = ResourceMapChromeThemeData.glassDock.withPalette(
  canvas: const Color(0xFF071A2E),
  surface: const Color(0xFFE9D5A8),
  raised: const Color(0xFFF2E3BD),
  inset: const Color(0xFFD8BF8A),
  foreground: const Color(0xFF352516),
  secondaryForeground: const Color(0xFF765F3B),
  primary: const Color(0xFF123D69),
  primaryBright: const Color(0xFF1A5487),
  trim: const Color(0xFF9A742F),
  trimBright: const Color(0xFFD6B45A),
  positive: const Color(0xFF647B35),
  warning: const Color(0xFFB78338),
  error: const Color(0xFFA45648),
  shadow: const Color(0x70352516),
);

void main() {
  testWidgets('opacity ticks reach pill material without a trailing tween', (
    tester,
  ) async {
    var opacity = 1.0;
    late StateSetter update;
    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (context, setState) {
            update = setState;
            return ResourceMapChromeTheme(
              data: ResourceMapChromeThemeData.glassDock.withUiOpacity(opacity),
              child: const Center(
                child: SizedBox(
                  width: 280,
                  height: 50,
                  child: ResourceMapPill(key: _pill, child: Text('Iron Ore')),
                ),
              ),
            );
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    final bounds = tester.getRect(find.byKey(_pill));
    final retainedChild = find.text('Iron Ore').evaluate().single;
    for (final value in [.9, .7, .5, .2, 0.0, .4, .8, 1.0]) {
      update(() => opacity = value);
      await tester.pump();
      final container = tester.widget<AnimatedContainer>(
        find.byType(AnimatedContainer),
      );
      expect(container.duration, Duration.zero);
      final painted = tester
          .widgetList<DecoratedBox>(
            find.descendant(
              of: find.byKey(_pill),
              matching: find.byType(DecoratedBox),
            ),
          )
          .map((widget) => widget.decoration)
          .whereType<BoxDecoration>()
          .singleWhere((decoration) => decoration.gradient != null);
      expect(painted, container.decoration);
      expect(tester.hasRunningAnimations, isFalse);
      expect(tester.getRect(find.byKey(_pill)), bounds);
      expect(find.text('Iron Ore').evaluate().single, same(retainedChild));
    }
    // The immediate-opacity path must not disable later hover feedback.
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: const Offset(1, 1));
    await mouse.moveTo(bounds.center);
    await tester.pump();
    expect(
      tester.widget<AnimatedContainer>(find.byType(AnimatedContainer)).duration,
      const Duration(milliseconds: 150),
    );
    await tester.pumpAndSettle();
    await mouse.removePointer();
    await tester.pumpAndSettle();
    expect(tester.hasRunningAnimations, isFalse);
    expect(tester.takeException(), isNull);
  });

  for (final (name, theme) in [
    ('sakura', ResourceMapChromeThemeData.sakuraCartographer),
    ('ledger', _lightLedger),
    ('standard', ResourceMapChromeThemeData.glassDock),
  ]) {
    for (final textScale in [1.0, 2.0]) {
      testWidgets('$name depth keeps content and actions at $textScale text', (
        tester,
      ) async {
        final shadows = debugDisableShadows;
        debugDisableShadows = false;
        try {
          tester.view.physicalSize = const Size(1060, 560);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          await tester.runAsync(loadMapMenuCaptureFonts);
          var selected = 0;
          await tester.pumpWidget(
            MaterialApp(
              theme: ThemeData(fontFamily: 'Segoe UI'),
              home: MediaQuery(
                data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
                child: RepaintBoundary(
                  key: _capture,
                  child: CustomPaint(
                    painter: const _Terrain(),
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          for (final opacity in [1.0, .55, .15]) ...[
                            if (opacity != 1) const SizedBox(width: 24),
                            ResourceMapChromeTheme(
                              data: theme.withUiOpacity(opacity),
                              child: SizedBox(
                                width: 320,
                                child: Builder(
                                  builder: (context) => _panel(
                                    context.mapChrome,
                                    onSelect: () => selected++,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(find.text('Iron Ore'), findsNWidgets(3));
          expect(find.text('Houses'), findsNWidgets(3));
          expect(find.byType(BackdropFilter), findsNothing);
          expect(find.byType(Opacity), findsNothing);
          final firstOption = find.byType(ResourceMapPill).first;
          final bounds = tester.getRect(firstOption);
          await tester.tapAt(bounds.centerLeft + const Offset(3, 0));
          expect(selected, 1, reason: 'Raised edges remain non-interactive.');
          await tester.pumpAndSettle();
          expect(tester.getRect(firstOption), bounds);
          expect(tester.hasRunningAnimations, isFalse);
          await captureMapMenu(
            tester,
            boundary: find.byKey(_capture),
            name: 'depth-$name-text${(textScale * 100).round()}',
          );
          expect(tester.takeException(), isNull);
        } finally {
          debugDisableShadows = shadows;
        }
      });
    }
  }
}

Widget _panel(
  ResourceMapChromeThemeData chrome, {
  required VoidCallback onSelect,
}) => ResourceMapAtlasPalette(
  width: 308,
  child: Padding(
    padding: const EdgeInsets.all(8),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(6, 4, 6, 12),
          child: Text(
            'Materials',
            style: chrome.headingStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        _option(chrome, 'Iron Ore', 'iron_ore', onSelect, selected: true),
        const SizedBox(height: 8),
        _option(chrome, 'Houses', 'house', onSelect),
        const SizedBox(height: 8),
        _option(chrome, 'Income', 'silver', onSelect),
      ],
    ),
  ),
);

Widget _option(
  ResourceMapChromeThemeData chrome,
  String name,
  String artwork,
  VoidCallback onSelect, {
  bool selected = false,
}) => ResourceMapPill(
  selected: selected,
  child: InkWell(
    onTap: onSelect,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      child: Row(
        children: [
          Image.asset(
            'assets/images/menu_artwork/$artwork.webp',
            package: 'bdo_map_core',
            width: 36,
            height: 36,
            excludeFromSemantics: true,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              name,
              style: TextStyle(
                color: chrome.readingInk,
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Icon(Icons.chevron_right, size: 19, color: chrome.readingInk),
        ],
      ),
    ),
  ),
);

class _Terrain extends CustomPainter {
  const _Terrain();

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = const Color(0xff6c7a61),
    );
    for (var x = -size.height; x < size.width; x += 70) {
      canvas.drawLine(
        Offset(x, 0),
        Offset(x + size.height, size.height),
        Paint()
          ..color = const Color(0xff53634e)
          ..strokeWidth = 30,
      );
    }
  }

  @override
  bool shouldRepaint(_Terrain oldDelegate) => false;
}
