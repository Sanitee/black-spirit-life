import 'dart:io';
import 'dart:ui' as ui;

import 'package:bdo_craft_planner_flutter/domain/opportunities/opportunity_card_reading.dart';
import 'package:bdo_craft_planner_flutter/features/opportunities/opportunity_craft_card_material.dart';
import 'package:bdo_craft_planner_flutter/features/shared/availability_game_icon.dart';
import 'package:bdo_craft_planner_flutter/features/shared/market_count_badges.dart';
import 'package:bdo_craft_planner_flutter/features/shared/source_availability_badges.dart';
import 'package:bdo_craft_planner_flutter/visual/visual.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/availability_badge_finders.dart';
import '../../support/native_preview_fonts.dart';

void main() {
  setUpAll(loadNativePreviewFonts);
  for (final spec in RetainedThemeRegistry.themes) {
    for (final scale in [1.0, 2.0]) {
      testWidgets(
        '${spec.id} $scale independent stock/order/NPC colours and art',
        (tester) async {
          await tester.binding.setSurfaceSize(const Size(1050, 1250));
          addTearDown(() => tester.binding.setSurfaceSize(null));
          const capture = ValueKey('availability-capture');
          await tester.pumpWidget(
            MaterialApp(
              home: ThemeSpecScope(
                spec: spec,
                child: MediaQuery(
                  data: MediaQueryData(textScaler: TextScaler.linear(scale)),
                  child: Scaffold(
                    body: Align(
                      alignment: Alignment.topLeft,
                      child: RepaintBoundary(
                        key: capture,
                        child: Container(
                          width: 1000,
                          padding: const EdgeInsets.all(20),
                          color: spec.palette.surface,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              for (final sample in <(int?, int?)>[
                                (12594, 84),
                                (0, 84),
                                (null, 84),
                                (300, 0),
                              ])
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 10,
                                  ),
                                  child: SourceAvailabilityBadges(
                                    key: ValueKey('sample:${sample.$1}'),
                                    stock: sample.$1,
                                    preorders: sample.$2,
                                    npc: true,
                                    showMarket: true,
                                    density: MarketBadgeDensity.comfortable,
                                  ),
                                ),
                              const SizedBox(height: 16),
                              SizedBox(
                                width: 230,
                                child: SourceAvailabilityBadges(
                                  stock: 1234567890,
                                  preorders: 987654321,
                                ),
                              ),
                              const SizedBox(height: 16),
                              AvailabilityGameIcon(
                                artwork: AvailabilityArtwork.inventory,
                                color: spec.palette.text,
                                size: 24,
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
          for (final element in find.byType(Image).evaluate().toList()) {
            await tester.runAsync(
              () => precacheImage((element.widget as Image).image, element),
            );
          }
          await tester.pumpAndSettle();
          for (final stock in <int?>[12594, 0, null, 300]) {
            final parent = find.byKey(ValueKey('sample:$stock'));
            final stockText = find.descendant(
              of: parent,
              matching: find.text(
                stock == 12594 ? '12.594' : '${stock ?? '—'}',
              ),
            );
            expect(
              tester.widget<Text>(stockText).style!.color,
              OpportunityCraftCardMaterial.forSpec(
                spec,
                marketStockTone(stock),
              ).badgeInk,
            );
            final stockInk = tester.widget<Text>(stockText).style!.color!;
            if ((stock ?? 0) > 0) {
              expect(stockInk.g, greaterThan(stockInk.r));
              expect(stockInk.g, greaterThan(stockInk.b));
            } else if (stock == 0) {
              expect(stockInk.r, greaterThan(stockInk.g));
              expect(stockInk.r, greaterThan(stockInk.b));
            }
            expect(
              (spec.brightness == Brightness.light
                  ? (spec.palette.surface.computeLuminance() + .05) /
                        (stockInk.computeLuminance() + .05)
                  : (stockInk.computeLuminance() + .05) /
                        (spec.palette.surface.computeLuminance() + .05)),
              greaterThanOrEqualTo(4.5),
            );
            final preorder = find.descendant(
              of: parent,
              matching: find.text('Orders 84'),
            );
            if (stock != 300) {
              expect(
                tester.widget<Text>(preorder).style!.color,
                OpportunityCraftCardMaterial.forSpec(
                  spec,
                  OpportunityStockTone.mixed,
                ).badgeInk,
              );
              final orderInk = tester.widget<Text>(preorder).style!.color!;
              expect(orderInk.r, greaterThan(orderInk.g));
              expect(orderInk.g, greaterThan(orderInk.b));
              expect(
                find.descendant(
                  of: parent,
                  matching: find.byKey(
                    const ValueKey('availability-game-icon:preorders'),
                  ),
                ),
                findsOneWidget,
              );
            } else {
              expect(preorder, findsNothing);
            }
            expect(
              find.descendant(of: parent, matching: find.text('NPC')),
              findsOneWidget,
            );
            expect(
              find.descendant(
                of: parent,
                matching: find.byKey(
                  const ValueKey('availability-game-icon:stock'),
                ),
              ),
              findsOneWidget,
            );
          }
          expect(find.byIcon(Icons.shopping_basket_outlined), findsNothing);
          expect(stockBadgeText('1.234.567.890'), findsOneWidget);
          expect(tester.takeException(), isNull);
          final output = Platform.environment['AVAILABILITY_CAPTURE_DIR'];
          if (output != null) {
            final boundary = tester.renderObject<RenderRepaintBoundary>(
              find.byKey(capture),
            );
            await tester.runAsync(() async {
              await Directory(output).create(recursive: true);
              final image = await boundary.toImage(pixelRatio: 1);
              final data = await image.toByteData(
                format: ui.ImageByteFormat.png,
              );
              await File(
                '$output/${spec.id}-$scale.png',
              ).writeAsBytes(data!.buffer.asUint8List());
              image.dispose();
            });
          }
        },
      );
    }
  }
}
