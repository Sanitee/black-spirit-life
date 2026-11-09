import 'dart:io';

import 'package:bdo_craft_planner_flutter/data/catalog/bundled_catalog_parser.dart';
import 'package:bdo_craft_planner_flutter/domain/models/craft_mode.dart';
import 'package:bdo_craft_planner_flutter/features/shared/npc_source_marker.dart';
import 'package:bdo_craft_planner_flutter/visual/visual.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../planner/planner_review_projection_test.dart' as fixture;

void main() {
  test(
    'all active vendor records have a hint in every mode; no price invented',
    () async {
      final catalog = const BundledCatalogParser().parse(
        File('assets/data/app-data.json').readAsStringSync(),
      );
      final app = fixture.controller(catalog, CraftMode.cooking, 'Beer', 1);
      addTearDown(app.dispose);
      final before = app.documentSnapshot.toJson();
      final names = {
        ...app.plannerRules.vendorInfo.keys,
        ...app.plannerRules.npcPurchasePrices.keys,
        for (final rule in app.plannerRules.acquisitionInfo.values)
          if (rule.routes.any(
            (r) => r.isDisplayable && r.kind == 'npc_purchase',
          ))
            rule.canonicalName,
        for (final mode in app.modes.values)
          for (final recipe in mode.recipes.values)
            if (recipe.npcPrice > 0 ||
                (recipe.vendor ?? '').trim().isNotEmpty)
              recipe.name,
      };
      var checked = 0;
      for (final mode in app.modes.values) {
        for (final name in names) {
          if (const {
            'removed',
            'temporarily_archived',
          }.contains(mode.resolveItemAcquisition(name)?.status)) {
            continue;
          }
          expect(
            npcVendorHint(mode, name),
            isNotNull,
            reason: '${mode.mode}: $name',
          );
          checked++;
        }
        expect(npcVendorHint(mode, 'Base Sauce'), 'Food Vendor or Innkeeper');
        expect(npcVendorHint(mode, 'base sauce'), 'Food Vendor or Innkeeper');
        expect(mode.resolveItemSource('Base Sauce').npcPrice, 0);
        expect(npcVendorHint(mode, 'Milk'), isNull);
        expect(npcVendorHint(mode, 'Corn'), isNull);
        expect(npcVendorHint(mode, 'Paprika'), contains('Milano Belucci'));
        expect(npcVendorHint(mode, 'Paprika'), contains('Calpheon'));
      }
      expect(checked, greaterThan(100));
      expect(app.documentSnapshot.toJson(), before);
      // The count is evidence of display coverage, not a new game-data audit.
      // ignore: avoid_print
      print(
        'NPC display coverage: ${names.length} identities, $checked mode checks',
      );
    },
  );

  testWidgets(
    'NPC hints wait a full second, cancel on exit and keep marker geometry',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: StandardSpec.theme.materialTheme(),
          home: ThemeSpecScope(
            spec: StandardSpec.theme,
            child: const Scaffold(
              body: Center(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    NpcSourceMarker(
                      key: ValueKey('food'),
                      vendorHint: 'Food Vendor or Innkeeper',
                    ),
                    SizedBox(width: 60),
                    NpcSourceMarker(
                      key: ValueKey('fruit'),
                      vendorHint: 'Milano Belucci · Calpheon',
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      final food = find.byKey(const ValueKey('food'));
      final fruit = find.byKey(const ValueKey('fruit'));
      final before = tester.getRect(food);
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      await mouse.moveTo(tester.getCenter(food));
      await tester.pump(const Duration(milliseconds: 800));
      expect(find.text('Food Vendor or Innkeeper'), findsNothing);
      await mouse.moveTo(Offset.zero);
      await tester.pump(const Duration(seconds: 2));
      expect(find.text('Food Vendor or Innkeeper'), findsNothing);
      await mouse.moveTo(tester.getCenter(food));
      await tester.pump(const Duration(milliseconds: 999));
      expect(find.text('Food Vendor or Innkeeper'), findsNothing);
      await tester.pump(const Duration(milliseconds: 201));
      expect(find.text('Food Vendor or Innkeeper'), findsOneWidget);
      expect(tester.getRect(food), before);
      await mouse.moveTo(tester.getCenter(fruit));
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('Milano Belucci · Calpheon'), findsNothing);
      await tester.pump(const Duration(milliseconds: 700));
      expect(find.text('Milano Belucci · Calpheon'), findsOneWidget);
      await mouse.removePointer();
      await tester.pumpAndSettle();
      expect(find.text('Milano Belucci · Calpheon'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
