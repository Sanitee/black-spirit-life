import 'package:bdo_craft_planner_flutter/app_identity.dart';
import 'package:bdo_craft_planner_flutter/features/about/about.dart';
import 'package:bdo_craft_planner_flutter/visual/visual.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('shows the exact notice, plain app name, and source routes', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1000, 760);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    const spec = RetainedThemeRegistry.illuminatedLedger;
    await tester.pumpWidget(
      MaterialApp(
        theme: spec.materialTheme(),
        home: const ThemeSpecScope(
          spec: spec,
          child: Scaffold(body: AboutView()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('ABOUT BLACK SPIRIT LIFE'), findsOneWidget);
    expect(find.text(AboutView.unofficialNotice), findsOneWidget);
    expect(
      find.text('Version ${AppIdentity.applicationVersion}'),
      findsOneWidget,
    );
    expect(find.textContaining('https://bdocodex.com/'), findsOneWidget);

    await tester.drag(
      find.byKey(const ValueKey<String>('about-scroll')),
      const Offset(0, -800),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(AboutView.correctionsKey), findsOneWidget);
    expect(
      find.textContaining('Content correction or takedown'),
      findsOneWidget,
    );
  });
}
