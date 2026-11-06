import 'dart:io';
import 'package:bdo_craft_planner_flutter/data/catalog/bundled_catalog_parser.dart';
import 'package:bdo_craft_planner_flutter/data/catalog/catalog_repository.dart';
import 'package:bdo_craft_planner_flutter/data/market/shared_market_repository.dart';
import 'package:bdo_craft_planner_flutter/domain/models/craft_mode.dart';
import 'package:bdo_craft_planner_flutter/domain/state/state_copy.dart';
import 'package:bdo_craft_planner_flutter/features/planner/planner_choice_market.dart';
import 'package:bdo_craft_planner_flutter/features/planner/planner_contracts.dart';
import 'package:bdo_craft_planner_flutter/features/recipe_book/recipe_book.dart';
import 'package:bdo_craft_planner_flutter/visual/visual.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import '../../support/choice_market_transport.dart';
import '../planner/planner_choice_market_test.dart' show settle;
import '../planner/planner_review_projection_test.dart' as fixture;

void main() {
  for (final live in [false, true]) {
    testWidgets('availability profit scroll diagnostic live=$live', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final catalog = const BundledCatalogParser().parse(
        File('assets/data/app-data.json').readAsStringSync(),
      );
      final app = fixture.controller(catalog, CraftMode.cooking, 'Beer', 1);
      app.active.updateState(
        (state) => state.copyWith(
          inventory: {for (final name in app.active.recipes.keys) name: 12345},
          market: state.market.copyWith(
            prices: {for (final name in app.active.recipes.keys) name: 1000},
          ),
        ),
        immediate: true,
      );
      final book = RecipeBookController(
        modeController: app.active,
        catalogRepository: CatalogRepository.cached(catalog),
        callingContext: RecipeBookCallingContext.planner,
        allowedTargets: app.active.craftableNames,
      )..setMarketSort(RecipeBookMarketSort.availabilityProfit);
      final watch = Stopwatch()..start();
      final broker = SharedMarketRepository(
        transport: ChoiceMarketTransport(),
        requestSpacing: Duration.zero,
      );
      var notifications = 0;
      book.addListener(() => notifications++);
      final count = book.snapshot.entries.length;
      final cold = watch.elapsedMicroseconds;
      watch.reset();
      book.snapshot;
      final warm = watch.elapsedMicroseconds;
      await tester.pumpWidget(
        MaterialApp(
          home: ThemeSpecScope(
            spec: SakuraNightGardenSpec.theme,
            child: PlannerChoiceMarketScope(
              repository: live ? broker : null,
              child: RecipeBookModal(
                controller: book,
                onClose: () {},
                onActivated: (_) {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      if (live) {
        await settle(tester, broker);
        await tester.pumpAndSettle();
      }
      notifications = 0;
      final scroll = tester
          .widget<CustomScrollView>(find.byType(CustomScrollView).first)
          .controller!;
      final samples = <int>[];
      for (var i = 0; i < 24; i++) {
        watch.reset();
        scroll.jumpTo((i * 240.0).clamp(0, scroll.position.maxScrollExtent));
        await tester.pump();
        if (live) await tester.pump(const Duration(milliseconds: 150));
        samples.add(watch.elapsedMicroseconds);
        expect(tester.takeException(), isNull);
      }
      samples.sort();
      debugPrint(
        'SCROLL live=$live entries=$count cold=$cold warm=$warm p50=${samples[12]} p95=${samples[22]} max=${samples.last} notifications=$notifications us',
      );
      await tester.pumpWidget(const SizedBox());
      book.dispose();
      await broker.dispose();
      await app.dispose();
    });
  }
}
