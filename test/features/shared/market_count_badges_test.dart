import 'dart:ui' show PointerDeviceKind;

import 'package:bdo_craft_planner_flutter/domain/opportunities/opportunity_card_reading.dart';
import 'package:bdo_craft_planner_flutter/features/opportunities/opportunity_craft_card_material.dart';
import 'package:bdo_craft_planner_flutter/features/shared/availability_game_icon.dart';
import 'package:bdo_craft_planner_flutter/features/shared/inventory_count_badge.dart';
import 'package:bdo_craft_planner_flutter/features/shared/market_count_badges.dart';
import 'package:bdo_craft_planner_flutter/features/shared/npc_source_marker.dart';
import 'package:bdo_craft_planner_flutter/visual/components/app_tooltip.dart';
import 'package:bdo_craft_planner_flutter/visual/visual.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/availability_badge_finders.dart';

void main() {
  testWidgets(
    'short labels stay quiet on hover and retain exact accessible counts',
    (tester) async {
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(
        MaterialApp(
          home: ThemeSpecScope(
            spec: RetainedThemeRegistry.themes.first,
            child: const Scaffold(
              body: Column(
                children: [
                  MarketCountBadges(
                    stock: 32123,
                    preorders: 4999,
                    compactNumbers: true,
                  ),
                  MarketCountBadges(stock: null, preorders: null),
                  MarketCountBadges(
                    stock: 0,
                    preorders: 84,
                    npc: true,
                    showMarket: true,
                  ),
                  InventoryCountBadge(owned: 69200),
                ],
              ),
            ),
          ),
        ),
      );
      expect(stockBadgeText('32,1k'), findsOneWidget);
      expect(find.text('Orders 5k'), findsOneWidget);
      expect(find.text('69,2k'), findsOneWidget);
      expect(find.textContaining('Stock '), findsNothing);
      expect(find.textContaining('Preorders '), findsNothing);
      final tips = tester
          .widgetList<AppTooltip>(find.byType(AppTooltip))
          .toList();
      expect(
        tips
            .where((tip) => tip.approvedHover)
            .every((tip) => tip.message == 'NPC vendor'),
        isTrue,
      );
      expect(
        tips.map((tip) => tip.message),
        containsAll([
          'Market stock: 32.123',
          'Preorders: 4.999 waiting to buy',
          'Market stock: not checked',
          'Market stock: 0',
          'Preorders: 84 waiting to buy',
          'NPC vendor',
          'Owned 69.200',
        ]),
      );
      expect(
        find.bySemanticsLabel('Stock: 32.123\nPreorders: 4.999'),
        findsOneWidget,
      );
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      for (final target in [
        stockBadgeText('32,1k'),
        stockBadgeText('0'),
        stockBadgeText('—'),
        find.text('Orders 5k'),
        find.text('Orders 84'),
        find.text('69,2k'),
      ]) {
        final before = tester.getRect(target);
        await mouse.moveTo(tester.getCenter(target));
        await tester.pump(const Duration(seconds: 2));
        await tester.pumpAndSettle();
        for (final tip in tips.where((tip) => !tip.approvedHover)) {
          expect(find.text(tip.message!), findsNothing);
        }
        expect(tester.getRect(target), before);
      }
      expect(
        tester
            .getSemantics(find.byType(InventoryCountBadge))
            .getSemanticsData()
            .tooltip,
        'Owned 69.200',
      );
      await mouse.removePointer();
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      semantics.dispose();
    },
  );
  for (final spec in RetainedThemeRegistry.themes) {
    for (final density in MarketBadgeDensity.values) {
      testWidgets(
        '${spec.id} $density preserves badge vocabulary and typography',
        (tester) async {
          for (final source in [
            (
              stock: 12594,
              orders: 84,
              npc: false,
              icon: AvailabilityArtwork.stock,
              label: '12.594',
            ),
            (
              stock: 0,
              orders: 84,
              npc: false,
              icon: AvailabilityArtwork.stock,
              label: '0',
            ),
            (
              stock: null,
              orders: null,
              npc: false,
              icon: AvailabilityArtwork.stock,
              label: '—',
            ),
            (
              stock: 12594,
              orders: 84,
              npc: true,
              icon: AvailabilityArtwork.npc,
              label: 'NPC',
            ),
          ]) {
            await tester.pumpWidget(
              MaterialApp(
                home: ThemeSpecScope(
                  spec: spec,
                  child: Scaffold(
                    body: MarketCountBadges(
                      stock: source.stock,
                      preorders: source.orders,
                      npc: source.npc,
                      density: density,
                    ),
                  ),
                ),
              ),
            );
            final comfortable = density == MarketBadgeDensity.comfortable;
            final text = tester.widget<Text>(find.text(source.label));
            expect(
              text.style!.fontSize,
              source.npc ? 11.5 : (comfortable ? 14 : 12),
            );
            expect(text.style!.fontFamily, spec.typography.meta.fontFamily);
            final material = OpportunityCraftCardMaterial.forSpec(
              spec,
              source.npc
                  ? OpportunityStockTone.mixed
                  : marketStockTone(source.stock),
            );
            expect(
              text.style!.color,
              source.npc ? spec.palette.textMuted : material.badgeInk,
            );
            if (source.npc) {
              expect(find.byType(NpcSourceMarker), findsOneWidget);
              expect(
                find.descendant(
                  of: find.byType(NpcSourceMarker),
                  matching: find.byWidgetPredicate(
                    (widget) =>
                        widget is Container && widget.decoration != null,
                  ),
                ),
                findsNothing,
              );
            }
            expect(
              tester
                  .widget<AvailabilityGameIcon>(
                    find.byWidgetPredicate(
                      (w) =>
                          w is AvailabilityGameIcon && w.artwork == source.icon,
                    ),
                  )
                  .size,
              source.npc ? 14 : (comfortable ? 17 : 16),
            );
            expect(
              find.byKey(const ValueKey('availability-game-icon:preorders')),
              source.orders != null && !source.npc
                  ? findsOneWidget
                  : findsNothing,
            );
            expect(find.byType(Tooltip), findsNothing);
            expect(
              tester
                  .widgetList<AppTooltip>(find.byType(AppTooltip))
                  .every(
                    (tip) => !tip.approvedHover || tip.message == 'NPC vendor',
                  ),
              isTrue,
            );
            expect(tester.takeException(), isNull);
          }
        },
      );
    }
  }

  testWidgets(
    'comfortable counts reflow without dropping digits at enlarged text',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: ThemeSpecScope(
            spec: RetainedThemeRegistry.themes.first,
            child: MediaQuery(
              data: const MediaQueryData(textScaler: TextScaler.linear(2)),
              child: const Scaffold(
                body: SizedBox(
                  width: 230,
                  child: MarketCountBadges(
                    stock: 1234567890,
                    preorders: 987654321,
                    density: MarketBadgeDensity.comfortable,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      expect(stockBadgeText('1.234.567.890'), findsOneWidget);
      expect(find.text('Orders 987.654.321'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
