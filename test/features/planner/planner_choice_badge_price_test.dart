import 'dart:io';

import 'package:bdo_craft_planner_flutter/data/catalog/bundled_catalog_parser.dart';
import 'package:bdo_craft_planner_flutter/data/market/shared_market_repository.dart';
import 'package:bdo_craft_planner_flutter/domain/models/craft_mode.dart';
import 'package:bdo_craft_planner_flutter/features/opportunities/opportunity_silver_amount.dart';
import 'package:bdo_craft_planner_flutter/features/planner/planner_choice_market.dart';
import 'package:bdo_craft_planner_flutter/features/planner/planner_review_panels.dart';
import 'package:bdo_craft_planner_flutter/features/shared/inventory_count_badge.dart';
import 'package:bdo_craft_planner_flutter/features/shared/missing_count_badge.dart';
import 'package:bdo_craft_planner_flutter/features/shared/npc_source_marker.dart';
import 'package:bdo_craft_planner_flutter/visual/visual.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/choice_market_transport.dart';
import 'planner_choice_market_test.dart' show settle;
import 'planner_review_projection_test.dart' as fixture;

void main() {
  testWidgets(
    'empty-stock choice uses highest occupied bid and keeps true inventory',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final catalog = const BundledCatalogParser().parse(
        File('assets/data/app-data.json').readAsStringSync(),
      );
      final app = fixture.controller(
        catalog,
        CraftMode.cooking,
        'Stir-Fried Vegetables',
        100,
      );
      final mode = app.active;
      final ingredient = mode.recipes['Stir-Fried Vegetables']!.ingredients
          .firstWhere((i) => i.options.contains('Pumpkin'));
      mode.commitInventory('Pumpkin', '1000');
      mode.setIgnoreOwnedIngredients(false);
      final before = app.documentSnapshot;
      final transport = ChoiceMarketTransport();
      final pumpkinId = choiceMarketIdentity(
        mode,
        'Pumpkin',
        acrossModes: true,
      ).marketId!;
      transport.values[pumpkinId] = (price: 480, stock: 0, preorders: 112);
      transport.bookLevels[pumpkinId] = '650-0-100|2000-0-0|800-0-12';
      final broker = SharedMarketRepository(
        transport: transport,
        requestSpacing: Duration.zero,
      );
      await tester.pumpWidget(
        MaterialApp(
          home: ThemeSpecScope(
            spec: RetainedThemeRegistry.sakuraNightGarden,
            child: PlannerChoiceMarketScope(
              repository: broker,
              child: Scaffold(
                body: Center(
                  child: PlannerOwnedChoices(
                    controller: mode,
                    parentName: 'Stir-Fried Vegetables',
                    ingredient: ingredient,
                    options: const ['Pumpkin', 'Paprika'],
                    selected: 'Pumpkin',
                    anchorBuilder: (context, toggle, open) => TextButton(
                      onPressed: toggle,
                      child: const Text('Open'),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await settle(tester, broker);
      for (final name in ['Pumpkin', 'Paprika']) {
        final row = find.byKey(ValueKey('planner-owned-option:$name'));
        final preview = mode.previewSubstituteAmounts(
          parentName: 'Stir-Fried Vegetables',
          ingredient: ingredient,
          selection: name,
        );
        final price = tester.widget<OpportunitySilverAmount>(
          find.descendant(
            of: row,
            matching: find.byType(OpportunitySilverAmount),
          ),
        );
        expect(
          price.value,
          preview.needed *
              (name == 'Pumpkin' ? 800 : mode.resolveItemSource(name).npcPrice),
        );
        expect(
          tester
              .widget<InventoryCountBadge>(
                find.descendant(
                  of: row,
                  matching: find.byType(InventoryCountBadge),
                ),
              )
              .owned,
          preview.owned,
        );
        expect(
          tester
              .widget<MissingCountBadge>(
                find.descendant(
                  of: row,
                  matching: find.byType(MissingCountBadge),
                ),
              )
              .missing,
          preview.missing,
        );
        expect(
          find.descendant(of: row, matching: find.byType(NpcSourceMarker)),
          name == 'Paprika' ? findsOneWidget : findsNothing,
        );
      }
      expect(
        tester
            .widget<MissingCountBadge>(
              find.byKey(const ValueKey('choice-missing:Pumpkin')),
            )
            .missing,
        0,
      );
      expect(app.documentSnapshot, same(before));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await broker.dispose();
      await app.dispose();
    },
  );
}
