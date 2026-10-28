import 'package:bdo_map_core/src/widgets/network_cp_breakdown.dart';
import 'package:bdo_map_core/src/widgets/resource_map_chrome_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/map_menu_capture.dart';

void main() {
  testWidgets('breakdown reconciles the limit without double-counting', (
    tester,
  ) async {
    const breakdown = NetworkCpBreakdown(
      limit: 400,
      keptNodes: 120,
      newNodes: 40,
      lodgingHouses: 15,
      royalWorkshops: 5,
    );
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: breakdown)));
    expect(breakdown.used, 180);
    expect(breakdown.remaining, 220);
    for (final label in [
      'Kept nodes',
      'New nodes',
      'Lodging houses',
      'Royal Workshops',
      'Remaining',
    ]) {
      expect(find.text(label), findsOneWidget);
    }
    expect(find.text('220 CP'), findsOneWidget);
  });

  testWidgets('empty optional costs disappear and over-limit stays negative', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: NetworkCpBreakdown(limit: 10, keptNodes: 0, newNodes: 12),
        ),
      ),
    );
    expect(find.text('Kept nodes'), findsNothing);
    expect(find.text('Lodging houses'), findsNothing);
    expect(find.text('Royal Workshops'), findsNothing);
    expect(find.text('-2 CP'), findsOneWidget);
    final text = tester.widget<Text>(find.text('-2 CP'));
    expect(
      text.style!.color,
      tester.element(find.text('-2 CP')).mapChrome.error,
    );
  });

  for (final scale in [1.0, 2.0]) {
    testWidgets('compact breakdown fits at $scale text scale', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MediaQuery(
              data: MediaQueryData(textScaler: TextScaler.linear(scale)),
              child: const SizedBox(
                width: 300,
                child: NetworkCpBreakdown(
                  limit: 500,
                  keptNodes: 120,
                  newNodes: 40,
                  lodgingHouses: 15,
                  royalWorkshops: 5,
                ),
              ),
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      expect(find.text('320 CP'), findsOneWidget);
    });

    testWidgets('themed CP review at $scale text stays compact', (
      tester,
    ) async {
      await tester.runAsync(loadMapMenuCaptureFonts);
      final chrome = ResourceMapChromeThemeData.sakuraCartographer;
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(fontFamily: 'Segoe UI'),
          home: Scaffold(
            body: MediaQuery(
              data: MediaQueryData(textScaler: TextScaler.linear(scale)),
              child: Center(
                child: RepaintBoundary(
                  key: const ValueKey('cp-breakdown-capture'),
                  child: ResourceMapChromeTheme(
                    data: chrome,
                    child: Container(
                      width: 340,
                      padding: const EdgeInsets.all(12),
                      color: chrome.paperRaised,
                      child: const NetworkCpBreakdown(
                        limit: 400,
                        keptNodes: 120,
                        newNodes: 40,
                        lodgingHouses: 15,
                        royalWorkshops: 5,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      await captureMapMenu(
        tester,
        boundary: find.byKey(const ValueKey('cp-breakdown-capture')),
        name: 'network-cp-breakdown-text${(scale * 100).round()}',
      );
    });
  }
}
