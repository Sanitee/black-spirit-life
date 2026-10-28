import 'dart:io';
import 'dart:ui' show ImageByteFormat;

import 'package:bdo_craft_planner_flutter/features/planner/planner_market_summary.dart';
import 'package:bdo_craft_planner_flutter/visual/visual.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUpAll(() async {
    if (!Platform.isWindows) return;
    for (final entry in {
      'Segoe UI': ['segoeui.ttf', 'seguisb.ttf', 'segoeuib.ttf'],
      'Georgia': ['georgia.ttf', 'georgiab.ttf'],
    }.entries) {
      final loader = FontLoader(entry.key);
      for (final file in entry.value) {
        loader.addFont(
          File(
            'C:/Windows/Fonts/$file',
          ).readAsBytes().then(ByteData.sublistView),
        );
      }
      await loader.load();
    }
  });
  for (final spec in [
    StandardSpec.theme,
    IlluminatedLedgerSpec.theme,
    SakuraNightGardenSpec.theme,
  ]) {
    for (final width in [620.0, 280.0]) {
      for (final scale in [1.0, 2.0]) {
        testWidgets('compact total ${spec.id}, width $width, scale $scale', (
          tester,
        ) async {
          await tester.binding.setSurfaceSize(const Size(720, 360));
          addTearDown(() => tester.binding.setSurfaceSize(null));
          await tester.pumpWidget(
            MaterialApp(
              theme: spec.materialTheme(),
              home: ThemeSpecScope(
                spec: spec,
                child: MediaQuery(
                  data: MediaQueryData(textScaler: TextScaler.linear(scale)),
                  child: Scaffold(
                    backgroundColor: spec.palette.canvas,
                    body: Align(
                      alignment: Alignment.topRight,
                      child: RepaintBoundary(
                        key: const ValueKey('capture'),
                        child: SizedBox(
                          width: width,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                key: const ValueKey('last-need-card'),
                                width: double.infinity,
                                height: 60,
                                color: spec.palette.surfaceRaised,
                                alignment: Alignment.centerLeft,
                                padding: const EdgeInsets.all(12),
                                child: Text(
                                  'Corn',
                                  style: spec.typography.body,
                                ),
                              ),
                              PlannerMarketSummary(
                                total: 7600000,
                                loading: false,
                                fetchedAt: DateTime.utc(
                                  2026,
                                  9,
                                  24,
                                  14,
                                  33,
                                ).millisecondsSinceEpoch,
                                region: 'eu',
                                message: 'NPC prices are already included.',
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
          );
          await tester.pumpAndSettle();
          expect(find.text('Estimated Cost'), findsOneWidget);
          expect(find.text('7.6M'), findsOneWidget);
          expect(find.text('14:33'), findsOneWidget);
          expect(find.textContaining('Last fetched'), findsNothing);
          expect(find.textContaining('Region'), findsNothing);
          expect(find.textContaining('NPC prices'), findsNothing);
          final card = tester.getRect(
            find.byKey(const ValueKey('last-need-card')),
          );
          final surface = tester.getRect(
            find.byKey(PlannerMarketSummary.surfaceKey),
          );
          expect(surface.right, closeTo(card.right, .1));
          expect(surface.top, greaterThanOrEqualTo(card.bottom));
          expect(surface.width, lessThanOrEqualTo(width));
          if (width == 620 && scale == 1) {
            expect(surface.width, lessThan(400));
            expect(surface.height, lessThan(65));
            if (Platform.environment['CAPTURE_COMPACT_COST'] == '1') {
              final boundary = tester.renderObject<RenderRepaintBoundary>(
                find.byKey(const ValueKey('capture')),
              );
              await tester.runAsync(() async {
                final image = await boundary.toImage(pixelRatio: 2);
                try {
                  final bytes = await image.toByteData(
                    format: ImageByteFormat.png,
                  );
                  File(
                    'tmp/compact-cost-${spec.id}.png',
                  ).writeAsBytesSync(bytes!.buffer.asUint8List());
                } finally {
                  image.dispose();
                }
              });
            }
          }
          expect(tester.takeException(), isNull);
        });
      }
    }
  }

  for (final total in <double>[0, 500000000]) {
    testWidgets('unknown prices do not imply a complete total ($total)', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: ThemeSpecScope(
            spec: StandardSpec.theme,
            child: Scaffold(
              body: PlannerMarketSummary(
                total: total,
                loading: false,
                fetchedAt: 0,
                region: 'eu',
                hasUnknownPrices: true,
              ),
            ),
          ),
        ),
      );
      expect(
        find.text(total == 0 ? 'Estimated Cost' : 'Known Cost'),
        findsOneWidget,
      );
      if (total == 0) {
        expect(find.text('—'), findsOneWidget);
        expect(find.text('0'), findsNothing);
      } else {
        expect(find.text('500M'), findsOneWidget);
      }
      expect(
        tester
            .widget<AppSurface>(find.byKey(PlannerMarketSummary.surfaceKey))
            .semanticLabel,
        contains('Some item prices are unavailable; total is incomplete'),
      );
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('unchecked market omits time rather than inventing one', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ThemeSpecScope(
          spec: StandardSpec.theme,
          child: const Scaffold(
            body: PlannerMarketSummary(
              total: 0,
              loading: false,
              fetchedAt: 0,
              region: 'eu',
            ),
          ),
        ),
      ),
    );
    expect(find.text('Estimated Cost'), findsOneWidget);
    expect(find.text('0'), findsOneWidget);
    expect(find.text('Never'), findsNothing);
    expect(
      find.byWidgetPredicate(
        (w) => w is Text && (w.data?.contains(':') ?? false),
      ),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });
}
