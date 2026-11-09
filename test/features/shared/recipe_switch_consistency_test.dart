import 'dart:io';
import 'dart:ui' as ui;
import 'package:bdo_craft_planner_flutter/domain/models/catalog_models.dart';
import 'package:bdo_craft_planner_flutter/domain/opportunities/opportunity_recipe_routes.dart';
import 'package:bdo_craft_planner_flutter/features/opportunities/opportunity_recipe_controls.dart';
import 'package:bdo_craft_planner_flutter/features/shared/recipe_switch_controls.dart';
import 'package:bdo_craft_planner_flutter/features/shared/recipe_variant_selector.dart';
import 'package:bdo_craft_planner_flutter/visual/visual.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import '../../domain/opportunities/opportunity_calculator_test.dart' as fixture;

void main() {
  final baseline = Platform.environment['BSL_SWITCH_BASELINE'] == '1';
  setUpAll(() async {
    for (final entry in {
      'Segoe UI': [
        'C:/Windows/Fonts/segoeui.ttf',
        'C:/Windows/Fonts/seguisb.ttf',
      ],
      'Georgia': [
        'C:/Windows/Fonts/georgia.ttf',
        'C:/Windows/Fonts/georgiab.ttf',
      ],
      'Roboto': [
        'D:/Tools/flutter/bin/cache/artifacts/material_fonts/roboto-regular.ttf',
      ],
    }.entries) {
      final loader = FontLoader(entry.key);
      for (final file in entry.value) {
        loader.addFont(File(file).readAsBytes().then(ByteData.sublistView));
      }
      await loader.load();
    }
  });
  final recipe = fixture.recipe(
    'Seafood Cron Meal',
    variants: [
      for (final route in ['a', 'b'])
        for (final batch in [1, 10, 100])
          RecipeVariant(
            id: '$route-$batch',
            label: route,
            type: 'processing',
            baseOutput: 1,
            method: 'Simple Cooking',
            routeId: route,
            batchMultiplier: batch,
            ingredients: [
              fixture.ingredient('$route ingredient', batch.toDouble()),
            ],
            outputMinimum: batch.toDouble(),
            outputMaximum: batch.toDouble(),
          ),
    ],
  );
  for (final theme in RetainedThemeRegistry.themes) {
    for (final view in [
      (width: 720.0, scale: 1.0),
      (width: 720.0, scale: 2.0),
      (width: 320.0, scale: 2.0),
    ]) {
      testWidgets(
        'Identical recipe switches ${theme.id} ${view.width} ${view.scale}',
        (tester) async {
          tester.view.physicalSize = const Size(1200, 1600);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          var shared = 'a-10', opportunity = 'a-10';
          await tester.pumpWidget(
            MaterialApp(
              theme: theme.materialTheme(),
              home: ThemeSpecScope(
                spec: theme,
                child: MediaQuery(
                  data: MediaQueryData(
                    size: const Size(1200, 1600),
                    textScaler: TextScaler.linear(view.scale),
                  ),
                  child: Scaffold(
                    body: Align(
                      alignment: Alignment.topLeft,
                      child: RepaintBoundary(
                        key: const ValueKey('capture'),
                        child: SizedBox(
                          width: view.width,
                          child: AppSurface(
                            role: AppSurfaceRole.modal,
                            padding: const EdgeInsets.all(16),
                            child: StatefulBuilder(
                              builder: (context, setState) => Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Recipe switches',
                                    style: theme.typography.section,
                                  ),
                                  const SizedBox(height: 20),
                                  Text(
                                    'Planner · Recipe Book · Used in',
                                    style: theme.typography.meta,
                                  ),
                                  const SizedBox(height: 10),
                                  RecipeVariantSelector(
                                    key: const ValueKey('shared-host'),
                                    recipe: recipe,
                                    selectedVariantId: shared,
                                    onSelected: (id) =>
                                        setState(() => shared = id),
                                  ),
                                  const SizedBox(height: 28),
                                  Divider(color: theme.palette.trim),
                                  const SizedBox(height: 20),
                                  Text(
                                    'Opportunities',
                                    style: theme.typography.meta,
                                  ),
                                  const SizedBox(height: 10),
                                  OpportunityRecipeControls(
                                    key: const ValueKey('opportunity-host'),
                                    routes: opportunityRecipeRoutes([recipe]),
                                    recipe: recipe,
                                    variantId: opportunity,
                                    onSelected: (formula) => setState(
                                      () => opportunity = formula.variantId!,
                                    ),
                                  ),
                                ],
                              ),
                            ),
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
          final sharedHost = find.byKey(const ValueKey('shared-host'));
          final opportunityHost = find.byKey(
            const ValueKey('opportunity-host'),
          );
          if (!baseline) {
            List<Rect> relativeRects(Finder host) {
              final origin = tester.getTopLeft(host);
              return [
                for (final element
                    in find
                        .descendant(
                          of: host,
                          matching: find.byType(RecipeSwitchChoice),
                        )
                        .evaluate())
                  tester
                      .getRect(
                        find.byElementPredicate((e) => identical(e, element)),
                      )
                      .shift(-origin),
              ];
            }

            final a = relativeRects(sharedHost),
                b = relativeRects(opportunityHost);
            expect(a.length, 5);
            expect(b.length, 5);
            for (var i = 0; i < a.length; i++) {
              expect(a[i].left, closeTo(b[i].left, .1));
              expect(a[i].top, closeTo(b[i].top, .1));
              expect(a[i].width, closeTo(b[i].width, .1));
              expect(a[i].height, closeTo(b[i].height, .1));
            }
            for (final host in [sharedHost, opportunityHost]) {
              for (final label in ['Recipe', 'Batch']) {
                final f = find.descendant(of: host, matching: find.text(label));
                final group = find
                    .descendant(
                      of: host,
                      matching: find.byType(RecipeSwitchGroup),
                    )
                    .at(label == 'Recipe' ? 0 : 1);
                expect(
                  tester.getRect(f).center.dy,
                  closeTo(tester.getRect(group).center.dy, 1),
                );
                expect(
                  tester.getRect(group).left - tester.getRect(f).right,
                  closeTo(10, 1),
                );
                expect(tester.widget<Text>(f).style!.fontSize, 14);
              }
              for (final element
                  in find
                      .descendant(of: host, matching: find.byType(Text))
                      .evaluate()) {
                final r = tester.getRect(
                  find.byElementPredicate((e) => identical(e, element)),
                );
                expect(r.left, greaterThanOrEqualTo(16));
                expect(r.right, lessThanOrEqualTo(view.width - 16));
              }
            }
            final bChoice = find.descendant(
              of: opportunityHost,
              matching: find.text('B'),
            );
            Focus.of(tester.element(bChoice)).requestFocus();
            await tester.pump();
            await tester.sendKeyEvent(LogicalKeyboardKey.enter);
            await tester.pumpAndSettle();
            expect(opportunity, 'b-10');
            await tester.tap(
              find.descendant(of: opportunityHost, matching: find.text('100×')),
            );
            await tester.pumpAndSettle();
            expect(opportunity, 'b-100');
            expect(shared, 'a-10');
            await tester.tap(
              find.descendant(of: opportunityHost, matching: find.text('A')),
            );
            await tester.pumpAndSettle();
            expect(opportunity, 'a-100');
            await tester.tap(
              find.descendant(of: opportunityHost, matching: find.text('10×')),
            );
            await tester.pumpAndSettle();
            FocusManager.instance.primaryFocus?.unfocus();
            await tester.pump();
            final mouse = await tester.createGesture(
              kind: PointerDeviceKind.mouse,
            );
            await mouse.addPointer(location: tester.getCenter(bChoice));
            await mouse.moveTo(tester.getCenter(bChoice));
            await tester.pump(const Duration(seconds: 2));
            expect(find.byType(Tooltip), findsNothing);
            await mouse.removePointer();
            await tester.pumpAndSettle();
          }
          expect(tester.takeException(), isNull);
          await tester.runAsync(() async {
            final boundary = tester.renderObject<RenderRepaintBoundary>(
              find.byKey(const ValueKey('capture')),
            );
            final image = await boundary.toImage(pixelRatio: 1.5),
                data = await image.toByteData(format: ui.ImageByteFormat.png);
            final file = File(
              'build/switch-consistency/${baseline ? 'before' : 'after'}-${theme.id}-${view.width.toInt()}-${view.scale}.png',
            );
            await file.parent.create(recursive: true);
            await file.writeAsBytes(data!.buffer.asUint8List());
            image.dispose();
          });
          await tester.pumpWidget(const SizedBox());
        },
      );
    }
  }
}
