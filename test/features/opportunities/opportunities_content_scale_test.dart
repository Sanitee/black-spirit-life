import 'dart:convert';
import 'dart:io';
import 'package:bdo_craft_planner_flutter/data/catalog/catalog_repository.dart';
import 'package:bdo_craft_planner_flutter/features/opportunities/opportunities_content_scale.dart';
import 'package:bdo_craft_planner_flutter/features/opportunities/opportunities_controller.dart';
import 'package:bdo_craft_planner_flutter/features/opportunities/opportunities_preferences.dart';
import 'package:flutter_test/flutter_test.dart';
import '../../support/application_test_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('independent content scale is compatible, bounded and finite', () {
    for (final value in [null, '1.2', double.nan, double.infinity]) {
      expect(normalizeOpportunitiesContentScale(value), 1);
      expect(
        OpportunitiesPreferences.fromJson({
          'version': 1,
          'contentScale': value,
        }).contentScale,
        1,
      );
    }
    expect(normalizeOpportunitiesContentScale(-1), 1);
    expect(normalizeOpportunitiesContentScale(2), 1.25);
    final p = OpportunitiesPreferences()..contentScale = 1.17;
    expect(
      OpportunitiesPreferences.fromJson(
        jsonDecode(jsonEncode(p.toJson())),
      ).contentScale,
      1.17,
    );
  });

  test(
    'preview is display-only, commit persists independently and restart clears searches',
    () async {
      final harness = await ApplicationTestHarness.create();
      addTearDown(harness.dispose);
      final directory = Directory(
        '${harness.temporaryDirectory.path}/opportunities',
      );
      final controller = _controller(harness, directory);
      await controller.ready;
      final plannerBefore = harness.bundle.controller.documentSnapshot;
      final quotesBefore = controller.quotes;
      var notifications = 0;
      controller.addListener(() => notifications++);
      for (var percent = 100; percent <= 125; percent++) {
        controller.previewContentScale(percent / 100);
      }
      expect(controller.contentScale.value, 1.25);
      expect(controller.preferences.contentScale, 1);
      expect(controller.quotes, same(quotesBefore));
      expect(notifications, 0);
      expect(harness.bundle.controller.documentSnapshot, same(plannerBefore));
      expect(
        await File('${directory.path}/opportunities-settings.json').exists(),
        isFalse,
      );
      controller.commitContentScale();
      expect(controller.preferences.contentScale, 1.25);
      expect(notifications, 0);
      expect(controller.quotes, same(quotesBefore));
      controller.preferences
        ..craftSearch = 'Beer'
        ..exchangeSearch = 'Milk'
        ..bestUseItem = 'Aloe';
      await controller.flush();
      final saved = await OpportunitiesPreferenceStore(directory).load();
      expect(saved.contentScale, 1.25);
      expect(saved.bestUseItem, isEmpty);
      controller.dispose();
      final restarted = _controller(harness, directory);
      try {
        await restarted.ready;
        expect(restarted.contentScale.value, 1.25);
        expect(restarted.preferences.craftSearch, isEmpty);
        expect(restarted.preferences.exchangeSearch, isEmpty);
        expect(restarted.preferences.bestUseItem, isEmpty);
        expect(harness.bundle.controller.plannerContentScale.value, 1);
        restarted.previewContentScale(1.08);
        await restarted.flush();
        expect(
          (await OpportunitiesPreferenceStore(directory).load()).contentScale,
          1.08,
        );
      } finally {
        restarted.dispose();
      }
    },
  );
}

OpportunitiesController _controller(
  ApplicationTestHarness harness,
  Directory directory,
) => OpportunitiesController(
  appController: harness.bundle.controller,
  catalog: CatalogRepository(harness.bundle.catalog),
  directory: directory,
  clock: () => DateTime.utc(2026, 10, 18),
  serviceFactory: (_) => throw StateError('Zoom must not request market data'),
);
