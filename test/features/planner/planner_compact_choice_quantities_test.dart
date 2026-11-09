import 'dart:convert';
import 'dart:io';

import 'package:bdo_craft_planner_flutter/app/app.dart';
import 'package:bdo_craft_planner_flutter/domain/formatting/compact_quantity.dart';
import 'package:bdo_craft_planner_flutter/domain/formatting/planner_formatters.dart';
import 'package:bdo_craft_planner_flutter/domain/models/craft_mode.dart';
import 'package:bdo_craft_planner_flutter/visual/visual.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/application_test_harness.dart';
import 'planner_sculpted_panels_test.dart' as support;

void main() {
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
        'D:/Tools/flutter/bin/cache/artifacts/material_fonts/roboto-bold.ttf',
      ],
      'MaterialIcons': [
        'D:/Tools/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
      ],
    }.entries) {
      final loader = FontLoader(entry.key);
      for (final file in entry.value) {
        loader.addFont(File(file).readAsBytes().then(ByteData.sublistView));
      }
      await loader.load();
    }
  });
  for (final spec in RetainedThemeRegistry.themes) {
    for (final scale in [1.0, 1.5, 2.0]) {
      testWidgets('shared compact choices ${spec.id} $scale', (tester) async {
        configureApplicationTestSurface(
          tester,
          const Size(1200, 900),
          textScaleFactor: scale,
        );
        final original = (await tester.runAsync(
          () => ApplicationTestHarness.create(
            activeMode: CraftMode.cooking,
            backgroundId: spec.isStandard ? 'greenhouse' : spec.id,
          ),
        ))!;
        final harness = original.rebindControllerInCurrentZone();
        await tester.runAsync(original.disposeControllerOnly);
        final mode = harness.bundle.controller.active;
        mode.selectTarget('Beer');
        mode.commitAmount('1000');
        final grain = mode.recipes['Beer']!.ingredients.firstWhere(
          (i) => i.options.contains('Corn'),
        );
        mode.selectSubstitute(
          parentName: 'Beer',
          ingredient: grain,
          selection: 'Corn',
        );
        for (final entry in {
          'Corn': 0,
          'Wheat': 1100000,
          'Barley': 1500000,
          'Potato': 999949000000000,
          'Sweet Potato': 10800,
        }.entries) {
          mode.commitInventory(entry.key, '${entry.value}');
        }
        mode.setIgnoreOwnedIngredients(true);
        final before = jsonEncode(mode.state.value.toJson());
        try {
          await tester.pumpWidget(
            RepaintBoundary(
              key: support.captureKey,
              child: BdoCraftPlannerApp(
                applicationFuture: Future.value(harness.bundle),
                enableOpportunityAutoCheck: false,
                marketGateway: const EmptyMarketGateway(),
              ),
            ),
          );
          await tester.pumpAndSettle();
          for (final host in ['need', 'queue']) {
            final anchor = host == 'need'
                ? support.k('P12:missing:Corn:${grain.substituteGroup}')
                : support.k('P12:step:Beer:${grain.substituteGroup}');
            if (host == 'queue') {
              final queueScroll = find
                  .descendant(
                    of: find.byKey(
                      const PageStorageKey<String>('planner-craft-queue'),
                    ),
                    matching: find.byType(Scrollable),
                  )
                  .first;
              final expand = support.k('P09:Beer');
              await tester.scrollUntilVisible(
                expand,
                200,
                scrollable: queueScroll,
              );
              if (anchor.evaluate().isEmpty) await support.tap(tester, expand);
            }
            await tester.ensureVisible(anchor);
            await tester.pumpAndSettle();
            await support.tap(tester, anchor);
            final panel = support.k('planner-owned-choices-panel');
            expect(panel, findsOneWidget);
            expect(find.text('Grain'), findsOneWidget);
            for (final name in ['Wheat', 'Barley', 'Potato', 'Sweet Potato']) {
              final preview = mode.previewSubstituteAmounts(
                parentName: 'Beer',
                ingredient: grain,
                selection: name,
              );
              final row = support.k('planner-owned-option:$name');
              final semantics = tester.widget<Semantics>(
                support.k('P13:$name'),
              );
              expect(
                semantics.properties.label,
                contains('owned ${formatQuantity(preview.owned)}'),
              );
              expect(
                semantics.properties.label,
                contains('missing ${formatQuantity(preview.missing)}'),
              );
              for (final field in [
                ('owned', preview.owned),
                ('missing', preview.missing),
              ]) {
                final label = find.descendant(
                  of: row,
                  matching: support.k('choice-${field.$1}:${preview.name}'),
                );
                final text = tester.widget<Text>(
                  find.descendant(of: label, matching: find.byType(Text)).first,
                );
                expect(text.data, endsWith(formatCompactQuantity(field.$2)));
                expect(text.maxLines, 1);
                expect(text.softWrap, false);
                final paragraph = tester.renderObject<RenderParagraph>(
                  find
                      .descendant(of: label, matching: find.byType(RichText))
                      .first,
                );
                final measure = TextPainter(
                  text: paragraph.text,
                  textDirection: TextDirection.ltr,
                  textScaler: paragraph.textScaler,
                )..layout();
                expect(
                  measure.width,
                  lessThanOrEqualTo(paragraph.size.width + .01),
                  reason:
                      '$name ${field.$1} must fit without clipping or shrinking',
                );
                expect(paragraph.didExceedMaxLines, isFalse);
                measure.dispose();
              }
            }
            expect(
              tester
                  .widget<Text>(
                    find
                        .descendant(
                          of: support.k('choice-owned:Wheat'),
                          matching: find.byType(Text),
                        )
                        .first,
                  )
                  .data,
              endsWith('1,1m'),
            );
            expect(
              tester
                  .widget<Text>(
                    find
                        .descendant(
                          of: support.k('choice-owned:Barley'),
                          matching: find.byType(Text),
                        )
                        .first,
                  )
                  .data,
              endsWith('1,5m'),
            );
            expect(jsonEncode(mode.state.value.toJson()), before);
            expect(tester.takeException(), isNull);
            await support.capture(tester, '${spec.id}-$scale-$host');
            if (host == 'need') {
              await tester.sendKeyEvent(LogicalKeyboardKey.escape);
              await tester.pumpAndSettle();
            } else {
              await support.tap(
                tester,
                support.k('planner-owned-option:Wheat'),
              );
              expect(panel, findsNothing);
              expect(mode.state.value.inventory['Wheat'], 1100000);
              expect(mode.state.value.inventory['Barley'], 1500000);
              expect(
                mode.state.value.substituteChoices.values,
                contains('Wheat'),
              );
            }
          }
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          await harness.disposeControllerOnly();
          await tester.runAsync(
            () => harness.temporaryDirectory.delete(recursive: true),
          );
        }
      });
    }
  }
}
