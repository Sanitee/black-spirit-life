import 'package:bdo_craft_planner_flutter/features/data/personal_data_panel.dart';
import 'package:bdo_craft_planner_flutter/visual/visual.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final spec in [
    StandardSpec.theme,
    SakuraNightGardenSpec.theme,
    IlluminatedLedgerSpec.theme,
  ]) {
    final themeName = spec.id;
    for (final width in [280.0, 560.0, 670.0]) {
      for (final scale in [1.0, 1.5, 2.0]) {
        testWidgets('framed strip $themeName $width text scale $scale', (
          tester,
        ) async {
          tester.view.physicalSize = const Size(900, 1200);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          await tester.pumpWidget(
            MaterialApp(
              theme: spec.materialTheme(),
              home: ThemeSpecScope(
                spec: spec,
                child: MediaQuery(
                  data: MediaQueryData(textScaler: TextScaler.linear(scale)),
                  child: Scaffold(
                    body: Align(
                      alignment: Alignment.topLeft,
                      child: SizedBox(
                        width: width,
                        child: AppSurface(
                          padding: const EdgeInsets.all(14),
                          child: PersonalDataPanel(
                            activePath:
                                r'Q:\Example\A long profile location\Black Spirit Life',
                            onOpenFolder: () {},
                            onChangeLocation: () {},
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
          expect(tester.takeException(), isNull);
          final keys = [
            'Inventory',
            'Character & mastery',
            'App settings',
            'Favourites',
          ];
          final boxes = [
            for (final label in keys)
              tester.getRect(find.byKey(ValueKey('data-category:$label'))),
          ];
          for (final box in boxes) {
            expect(box.left, greaterThanOrEqualTo(14));
            expect(box.right, lessThanOrEqualTo(width - 14));
            expect(box.height, greaterThanOrEqualTo(77));
          }
          expect(boxes[0].top, boxes[1].top);
          expect(boxes[0].height, boxes[1].height);
          final fourColumns = width - 28 >= 500 * scale;
          expect(boxes[2].top == boxes[0].top, fourColumns);
          expect(find.byIcon(Icons.star_outline_rounded), findsOneWidget);
          expect(find.byIcon(Icons.bookmark_outline), findsNothing);
          expect(
            tester.getSize(
              find.byKey(const ValueKey('data-personal-data-folder-inlay')),
            ),
            const Size(52, 52),
          );
          expect(find.text('Details'), findsNothing);
          expect(find.textContaining('One folder across'), findsNothing);
        });
      }
    }
  }

  testWidgets('missing folder cannot be opened; categories are not buttons', (
    tester,
  ) async {
    var opens = 0;
    var changes = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: ThemeSpecScope(
          spec: StandardSpec.theme,
          child: Scaffold(
            body: PersonalDataPanel(
              activePath: null,
              onOpenFolder: () => opens++,
              onChangeLocation: () => changes++,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Folder unavailable'), findsOneWidget);
    expect(
      tester
          .widget<AppButton>(
            find.byKey(const ValueKey('data-personal-data-open')),
          )
          .onPressed,
      isNull,
    );
    await tester.tap(find.text('Inventory'));
    expect(opens, 0);
    expect(changes, 0);
    await tester.tap(find.text('Change location'));
    expect(changes, 1);
  });
}
